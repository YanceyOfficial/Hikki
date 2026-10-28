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
    /// The product is being asked for (the sheet's Try Again).
    private(set) var isLoadingProduct = false
    /// What the last Restore Purchases or Try Again found, shown in the unlock sheet (a toast would sit under it).
    private(set) var notice: String?
    /// The unlock sheet is up (Settings, the read-only bar, or something that would write).
    var isShowingUnlock = false {
        didSet { if !isShowingUnlock { notice = nil } }
    }
    /// Where this build came from, as About marks it: nothing for the App Store's own.
    private(set) var distribution: Distribution = {
        #if DEBUG
            .debug
        #else
            .appStore
        #endif
    }()

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
        downloaded = await downloadDate()
        unlocked = await Self.ownsUnlock()
        if product == nil { await loadProduct() }
        update()
    }

    /// Asks the store for the unlock. An empty answer (no error) means the store doesn't offer it to this build —
    /// in TestFlight, an in-app purchase not yet cleared for sale or the Paid Apps agreement not in effect.
    private func loadProduct() async {
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        do {
            product = try await Product.products(for: [Self.unlockID]).first
            if product == nil { Log.warn("store offers no product \(Self.unlockID)", category: "store") }
        } catch {
            Log.warn("store products unavailable: \(error)", category: "store")
        }
    }

    /// The sheet's Try Again, when the store couldn't be reached or offered nothing.
    func retryProduct() async {
        notice = nil
        await loadProduct()
        if product == nil { notice = String(localized: "app:unlock.stillUnavailable") }
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
        notice = nil
        do {
            try await AppStore.sync()
            await refresh()
            if !unlocked { say(String(localized: "app:unlock.nothingToRestore")) }
        } catch StoreKitError.userCancelled {
            // The Apple Account sign-in was dismissed: nothing to say.
        } catch {
            if isShowingUnlock {
                Log.warn("restore failed: \(error)", category: "store")
                notice = ErrorCode.restoreFailed.message
            } else {
                Toasts.report(.restoreFailed, error, category: "store")
            }
        }
    }

    /// A word about a restore: in the unlock sheet while it is up (a toast would sit under it), else a toast.
    private func say(_ text: String) {
        if isShowingUnlock { notice = text } else { Toasts.shared.show(.info, text) }
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

    /// When this Apple Account first got the app; this install's first launch where the App Store can't say. Reads
    /// where the build came from on the way (TestFlight's builds are the store's sandbox).
    private func downloadDate() async -> Date {
        do {
            if case .verified(let transaction) = try await AppTransaction.shared {
                #if !DEBUG
                    distribution = Distribution(transaction.environment)
                #endif
                return transaction.originalPurchaseDate
            }
        } catch {
            Log.warn("app transaction unavailable: \(error)", category: "store")
        }
        return Self.firstLaunch()
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
            isLoading: purchases.isLoadingProduct, notice: purchases.notice,
            onUnlock: { Task { await purchases.buy(with: purchase) } },
            onRetry: { Task { await purchases.retryProduct() } },
            onRestore: { Task { await purchases.restore() } },
            onClose: { purchases.isShowingUnlock = false }
        )
        // The price, if it couldn't be read at launch (offline then).
        .task { if purchases.product == nil { await purchases.refresh() } }
    }
}

/// Where a build came from: the App Store, TestFlight (the store's sandbox), Xcode's StoreKit testing, or a Debug
/// build.
enum Distribution: Equatable {
    case appStore, testFlight, xcode, debug

    init(_ environment: AppStore.Environment) {
        switch environment {
        case .sandbox: self = .testFlight
        case .xcode: self = .xcode
        default: self = .appStore
        }
    }

    /// The mark About shows; none for the App Store's own build.
    var label: String? {
        switch self {
        case .appStore: nil
        case .testFlight: String(localized: "app:about.build.testFlight")
        case .xcode: String(localized: "app:about.build.xcode")
        case .debug: String(localized: "app:about.build.debug")
        }
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
