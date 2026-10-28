import HikkiCore
import HikkiUI
import SwiftUI

/// "Sync with this iCloud account?" — asked when the device signed in to another iCloud account than the one the
/// workspace syncs with (`CloudSync.Status.accountChanged`): from the toast that says so, and from Settings →
/// Workspace. Confirming hands the workspace to the account in use (`AppModel.adoptCurrentAccount`: everything goes
/// up to it; the old account's copy stays as it is).
struct AccountHandoverAlert: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.alert("app:cloud.handover.title", isPresented: $isPresented) {
            Button("app:cloud.handover.confirm") { model.adoptCurrentAccount() }
                .accessibilityIdentifier("confirm-account-handover")
            Button("app:common.cancel", role: .cancel) {}
        } message: {
            Text("app:cloud.handover.message")
        }
    }
}
