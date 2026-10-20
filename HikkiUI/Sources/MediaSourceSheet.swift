import SwiftUI

/// Where a phone's picture or file comes from.
public enum MediaSource: String, CaseIterable, Sendable {
    case camera, library, files, scan
}

/// The phone's photo / file sheet (Notion's): Camera and Photos as two large tiles, then Files and Scan document as
/// rows. A source the device lacks (no camera, no scanner) is left out; a pick hands its source back and the caller
/// presents that picker.
public struct MediaSourceSheet: View {
    let available: Set<MediaSource>
    let onPick: (MediaSource) -> Void

    public init(available: Set<MediaSource> = Set(MediaSource.allCases), onPick: @escaping (MediaSource) -> Void) {
        self.available = available
        self.onPick = onPick
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Text("app:media.title").font(.hk(.base, .semibold)).foregroundStyle(Theme.foreground)
            HStack(spacing: Spacing.s3) {
                if available.contains(.camera) { MediaSourceTile(source: .camera, onPick: onPick) }
                if available.contains(.library) { MediaSourceTile(source: .library, onPick: onPick) }
            }
            VStack(spacing: Spacing.s0) {
                ForEach([MediaSource.files, .scan].filter(available.contains), id: \.self) { source in
                    MediaSourceRow(source: source, onPick: onPick)
                }
            }
            .glassEffect(.regular, in: .rect(cornerRadius: Radius.xl))
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("media-source-sheet")
    }
}

extension MediaSource {
    var title: LocalizedStringKey {
        switch self {
        case .camera: "app:media.camera"
        case .library: "app:media.library"
        case .files: "app:media.files"
        case .scan: "app:media.scan"
        }
    }

    var icon: Icon {
        switch self {
        case .camera: .camera
        case .library: .images
        case .files: .file
        case .scan: .scan
        }
    }
}

/// A large source: its icon over its name, on glass.
private struct MediaSourceTile: View {
    let source: MediaSource
    let onPick: (MediaSource) -> Void
    @Environment(\.colorTone) private var tone

    var body: some View {
        Button {
            onPick(source)
        } label: {
            VStack(spacing: Spacing.s2) {
                IconView(source.icon, size: TextSize.x2l.rawValue).foregroundStyle(tone.fill)
                Text(source.title).font(.hk(.sm, .medium)).foregroundStyle(Theme.foreground)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.s5)
            .contentShape(.rect(cornerRadius: Radius.xl))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Radius.xl))
        .accessibilityIdentifier("media-source-\(source.rawValue)")
    }
}

/// A source as a row: its icon, its name.
private struct MediaSourceRow: View {
    let source: MediaSource
    let onPick: (MediaSource) -> Void

    var body: some View {
        Button {
            onPick(source)
        } label: {
            HStack(spacing: Spacing.s3) {
                IconView(source.icon, size: TextSize.lg.rawValue)
                    .foregroundStyle(Theme.mutedForeground)
                    .frame(width: Spacing.s6)
                Text(source.title).font(.hk(.base)).foregroundStyle(Theme.foreground)
                Spacer(minLength: Spacing.s0)
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, Spacing.s3)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("media-source-\(source.rawValue)")
    }
}

#Preview {
    VStack {
        Spacer()
        MediaSourceSheet { _ in }
    }
}

#Preview("No camera") {
    VStack {
        Spacer()
        MediaSourceSheet(available: [.library, .files]) { _ in }
    }
}
