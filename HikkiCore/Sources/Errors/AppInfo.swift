import Foundation

/// What a report says about where it came from: app version and build, the OS, the device model, language and the
/// bridge protocol — on the launch log line, in "Copy details" and in the diagnostics bundle. Nothing about pages.
public struct AppInfo: Codable, Sendable, Equatable {
    public var version: String
    public var build: String
    public var os: String
    public var device: String
    public var locale: String
    public var protocolVersion: Int
    public var session: String

    public static func current(bundle: Bundle = .main) -> AppInfo {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if os(macOS)
            let platform = "macOS"
        #else
            let platform = "iOS"
        #endif
        return AppInfo(
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
            os: "\(platform) \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            device: machine(),
            locale: Locale.preferredLanguages.first ?? Locale.current.identifier,
            protocolVersion: BridgeProtocol.version,
            session: Log.session)
    }

    /// The hardware model ("Mac16,1", "iPhone17,1"; the simulator says so).
    static func machine() -> String {
        #if targetEnvironment(simulator)
            return "Simulator " + (ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "")
        #else
            var size = 0
            sysctlbyname("hw.machine", nil, &size, nil, 0)
            var bytes = [CChar](repeating: 0, count: max(size, 1))
            sysctlbyname("hw.machine", &bytes, &size, nil, 0)
            #if os(macOS)
                // On a Mac hw.machine is the architecture; the model is hw.model.
                var modelSize = 0
                sysctlbyname("hw.model", nil, &modelSize, nil, 0)
                var model = [CChar](repeating: 0, count: max(modelSize, 1))
                sysctlbyname("hw.model", &model, &modelSize, nil, 0)
                return String(decoding: model.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            #else
                return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            #endif
        #endif
    }

    /// The fields as log context.
    public var context: [String: String] {
        [
            "version": version, "build": build, "os": os, "device": device, "locale": locale,
            "protocol": String(protocolVersion),
        ]
    }

    /// One line for a report: "Hikki 1.0 (1) · macOS 26.0.1 · Mac16,1 · en-JP · session K3F9QX".
    public var summary: String {
        "Hikki \(version) (\(build)) · \(os) · \(device) · \(locale) · session \(session)"
    }

    /// What "Copy details" puts on the clipboard for an incident.
    public func details(for incident: Incident, message: String) -> String {
        let time = incident.date.formatted(.iso8601)
        return "\(incident.code.display) \(message)\nIncident \(incident.id) · \(time)\n\(summary)"
    }
}
