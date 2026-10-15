import HikkiCore
import HikkiUI
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// The app's toasts (one list, shown by every window's `ToastHost`): what the user should know right now — a failure
/// with its code, or a quick confirmation. Failures go through `report`, which logs them with an incident id first,
/// so every error toast can be found in an exported log.
@Observable
final class Toasts {
    static let shared = Toasts()

    struct Item: Identifiable {
        let id = UUID()
        let kind: ToastView.Kind
        let message: String
        /// "HK-2001 · K3F9QX" for a reported failure.
        let reference: String?
        let actionTitle: LocalizedStringKey?
        let action: (() -> Void)?
        /// Shows of the same message while this one is up only restart its timer.
        let key: String
    }

    /// Visible toasts, oldest first.
    private(set) var items: [Item] = []
    /// At most this many at once; the oldest makes room.
    static let limit = 3
    @ObservationIgnored private var timers: [UUID: Task<Void, Never>] = [:]

    /// A failure: logged with its code and an incident id (from any thread, at once), then shown with "Copy details".
    /// `info` codes are only logged.
    @discardableResult
    nonisolated static func report(
        _ code: ErrorCode, _ error: (any Error)? = nil, category: String, context: [String: String] = [:]
    ) -> Incident {
        let incident = Incident.report(code, error, category: category, context: context)
        guard code.severity != .info else { return incident }
        Task { @MainActor in shared.show(incident) }
        return incident
    }

    func show(_ incident: Incident) {
        let message = incident.code.message
        let details = AppInfo.current().details(for: incident, message: message)
        show(
            Item(
                kind: incident.code.severity == .warning ? .warning : .error, message: message,
                reference: incident.reference, actionTitle: "app:toast.copyDetails",
                action: { Clipboard.copy(details) }, key: incident.code.rawValue))
    }

    /// A confirmation or note ("Link copied").
    func show(_ kind: ToastView.Kind, _ message: String, actionTitle: LocalizedStringKey? = nil, action: (() -> Void)? = nil) {
        show(Item(kind: kind, message: message, reference: nil, actionTitle: actionTitle, action: action, key: message))
    }

    func dismiss(_ id: UUID) {
        timers[id]?.cancel()
        timers[id] = nil
        items.removeAll { $0.id == id }
    }

    private func show(_ item: Item) {
        if let same = items.first(where: { $0.key == item.key }) {
            schedule(same)
            return
        }
        items.append(item)
        while items.count > Self.limit { dismiss(items[0].id) }
        schedule(item)
    }

    /// How long a toast stays: confirmations briefly, failures long enough to read and copy.
    static func lifetime(_ kind: ToastView.Kind) -> Duration {
        switch kind {
        case .success, .info: .seconds(3)
        case .warning: .seconds(6)
        case .error: .seconds(10)
        }
    }

    private func schedule(_ item: Item) {
        timers[item.id]?.cancel()
        timers[item.id] = Task { [weak self] in
            try? await Task.sleep(for: Self.lifetime(item.kind))
            guard !Task.isCancelled else { return }
            self?.dismiss(item.id)
        }
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        #else
            UIPasteboard.general.string = text
        #endif
    }
}

/// A window's toasts, at the bottom centre (above the iPhone's floating bar).
struct ToastHost: ViewModifier {
    @State private var toasts = Toasts.shared
    var bottomInset: CGFloat = Spacing.s4

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            ToastStack(toasts.items) { item in
                ToastView(
                    kind: item.kind, message: item.message, reference: item.reference, actionTitle: item.actionTitle,
                    action: item.action.map { action in
                        {
                            action()
                            toasts.dismiss(item.id)
                        }
                    },
                    close: { toasts.dismiss(item.id) })
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.bottom, bottomInset)
        }
    }
}

extension View {
    func toastHost(bottomInset: CGFloat = Spacing.s4) -> some View { modifier(ToastHost(bottomInset: bottomInset)) }
}
