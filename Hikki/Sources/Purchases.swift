import Foundation
import HikkiCore
import HikkiUI
import StoreKit
import SwiftUI

/// The trial and the unlock (StoreKit 2): free to download with everything open for `Access.trialDays` days from the
/// first download (the App Store's `AppTransaction.originalPurchaseDate`, the same on every device of the Apple
/// Account), then one non-consumable in-app purchase — iPhone, iPad and Mac together (universal purchase). Without it
/// the app turns read only (`Access.expired`): pages open, search, copy and export; nothing is written, made,
/// imported or asked of AI, and every way in to those asks for the unlock (`allowsWriting`).
@Observable @MainActor
final class Purchases {
    static let shared = Purchases()
    /// The product in App Store Connect (and `Hikki/Hikki.storekit` for local testing).
    static let unlockID = "app.yancey.hikki.unlock"

    private(set) var access: Access = .trial(daysLeft: Access.trialDays)
    /// The unlock as the App Store sells it here (its localized price); nil until loaded, or when the store can't be
    /// reached.
    private(set) var product: Product?
    private(set) var isPurchasing = false
    /// The unlock sheet is up (Settings, the read-only bar, or something that would write).
    var isShowingUnlock = false

    private var downloaded: Date?
    private var unlocked = false
    private var updates: Task<Void, Never>?
    /// A Debug run's state is set by hand (`HIKKI_ACCESS`), never read from the store.
    private var forced = false

    private init() {}

    /// Reads the purchase state and follows it (refunds, a purchase on another device, Ask to Buy approvals).
    func start() {
        guard updates == nil else { return }
        #if DEBUG
            // Debug runs are never held to the trial — the developer's own instance, UI tests on their own data. To
            // see it: HIKKI_ACCESS=trial|expired|unlocked, or `store` for StoreKit itself (the Hikki-StoreKit scheme,
            // with Hikki/Hikki.storekit).
            switch ProcessInfo.processInfo.environment["HIKKI_ACCESS"] {
            case "store"?: break
            case "trial"?: force(.trial(daysLeft: 3))
            case "expired"?: force(.expired)
            default: force(.unlocked)
            }
            if forced { return }
        #endif
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
        Task { await refresh() }
    }

    #if DEBUG
        private func force(_ state: Access) {
            access = state
            forced = true
        }
    #endif

    /// Asks again: the download date, whether the unlock is owned, the product.
    func refresh() async {
        guard !forced else { return }
        downloaded = await Self.downloadDate()
        unlocked = await Self.ownsUnlock()
        if product == nil {
            do {
                product = try await Product.products(for: [Self.unlockID]).first
            } catch {
                Log.warn("store products unavailable: \(error)", category: "store")
            }
        }
        update()
    }

    /// Whether something may be written now; when not, the unlock sheet comes up instead.
    func allowsWriting() -> Bool {
        if access.canWrite { return true }
        isShowingUnlock = true
        return false
    }

    /// Buys the unlock through SwiftUI's purchase action (it shows the system's sheet over the right window).
    func buy(with purchase: PurchaseAction) async {
        guard let product, !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await purchase(product) {
            case .success(let result):
                await handle(result)
            case .pending, .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            Toasts.report(.purchaseFailed, error, category: "store")
        }
    }

    /// Restore Purchases: the App Store sends this Apple Account's purchases again.
    func restore() async {
        do {
            try await AppStore.sync()
            await refresh()
            if !unlocked { Toasts.shared.show(.info, String(localized: "app:unlock.nothingToRestore")) }
        } catch {
            Toasts.report(.restoreFailed, error, category: "store")
        }
    }

    private func handle(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = result, transaction.productID == Self.unlockID else { return }
        let wasUnlocked = unlocked
        unlocked = transaction.revocationDate == nil
        await transaction.finish()
        update()
        Log.info("unlock \(unlocked ? "owned" : "revoked")", category: "store")
        if unlocked && !wasUnlocked {
            isShowingUnlock = false
            Toasts.shared.show(.success, String(localized: "app:unlock.thanks"))
        }
    }

    private func update() {
        access = Access.on(.now, downloaded: downloaded ?? Self.firstLaunch(), unlocked: unlocked)
    }

    /// When this Apple Account first got the app; this install's first launch where the App Store can't say.
    private static func downloadDate() async -> Date {
        do {
            if case .verified(let transaction) = try await AppTransaction.shared {
                return transaction.originalPurchaseDate
            }
        } catch {
            Log.warn("app transaction unavailable: \(error)", category: "store")
        }
        return firstLaunch()
    }

    private static func firstLaunch() -> Date {
        let key = "store.firstLaunch"
        if let date = UserDefaults.standard.object(forKey: key) as? Date { return date }
        let now = Date.now
        UserDefaults.standard.set(now, forKey: key)
        return now
    }

    private static func ownsUnlock() async -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == unlockID, transaction.revocationDate == nil {
                return true
            }
        }
        return false
    }
}

/// The unlock sheet over a window: `UnlockSheet` with the store's state, buying through SwiftUI's purchase action.
struct UnlockHost: View {
    @Environment(\.purchase) private var purchase
    private let purchases = Purchases.shared

    var body: some View {
        UnlockSheet(
            status: purchases.access.unlockStatus, price: purchases.product?.displayPrice, isPurchasing: purchases.isPurchasing,
            onUnlock: { Task { await purchases.buy(with: purchase) } },
            onRestore: { Task { await purchases.restore() } },
            onClose: { purchases.isShowingUnlock = false }
        )
        // The price, if it couldn't be read at launch (offline then).
        .task { if purchases.product == nil { await purchases.refresh() } }
    }
}

extension Access {
    var unlockStatus: UnlockStatus {
        switch self {
        case .trial(let days): .trial(daysLeft: days)
        case .expired: .expired
        case .unlocked: .unlocked
        }
    }
}
