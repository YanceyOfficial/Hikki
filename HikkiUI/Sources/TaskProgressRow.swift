import SwiftUI

/// A long job's row in a form (Settings → Import & Export): what it is doing ("Importing 3 of 20"), a bar that fills
/// as it goes and a Cancel button. Plain values in; the caller runs the job and stops it in `onCancel`.
public struct TaskProgressRow: View {
    private let label: Text
    private let done: Int
    private let total: Int
    private let cancelTitle: LocalizedStringKey
    private let onCancel: () -> Void

    public init(_ label: Text, done: Int, total: Int, cancelTitle: LocalizedStringKey, onCancel: @escaping () -> Void) {
        self.label = label
        self.done = done
        self.total = total
        self.cancelTitle = cancelTitle
        self.onCancel = onCancel
    }

    public var body: some View {
        HStack(spacing: Spacing.s3) {
            VStack(alignment: .leading, spacing: Spacing.s1_5) {
                label
                    .font(.hk(.sm))
                    .foregroundStyle(Theme.foreground)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                // Nothing counted yet (the files are still being listed): an indeterminate bar.
                if total > 0 {
                    ProgressView(value: Double(min(done, total)), total: Double(total))
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
            }
            .animation(Motion.easeOut(), value: done)
            Button(cancelTitle, role: .cancel, action: onCancel)
                .accessibilityIdentifier("task-progress-cancel")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-progress")
    }
}

#Preview {
    Form {
        TaskProgressRow(Text(verbatim: "Importing 3 of 20"), done: 3, total: 20, cancelTitle: "Cancel") {}
        TaskProgressRow(Text(verbatim: "Reading files…"), done: 0, total: 0, cancelTitle: "Cancel") {}
    }
    .formStyle(.grouped)
}
