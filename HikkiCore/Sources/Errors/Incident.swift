import Foundation

/// One reported failure: its code, a short id and when. The id goes into the log line and the toast's "Copy details",
/// so what the user saw can be found in an exported log (`grep K3F9QX`).
public struct Incident: Sendable, Equatable, Identifiable {
    public let code: ErrorCode
    /// Six characters from an alphabet without look-alikes (no 0/O, 1/I/L).
    public let id: String
    public let date: Date

    public init(code: ErrorCode, id: String = Incident.newID(), date: Date = .now) {
        self.code = code
        self.id = id
        self.date = date
    }

    static let alphabet = Array("23456789ABCDEFGHJKMNPQRSTUVWXYZ")

    public static func newID() -> String {
        String((0..<6).map { _ in alphabet.randomElement()! })
    }

    /// "HK-2001 · K3F9QX" — what a toast shows under its message and what a report quotes.
    public var reference: String { "\(code.display) · \(id)" }

    /// Logs the failure (code, incident id, the error's own description — never page content) and returns it for
    /// the user to see. `category` is the log category; `context` adds ids and counts.
    @discardableResult
    public static func report(
        _ code: ErrorCode, _ error: (any Error)? = nil, category: String, context: [String: String] = [:]
    ) -> Incident {
        let incident = Incident(code: code)
        var fields = context
        fields["code"] = code.display
        fields["incident"] = incident.id
        if let error { fields["error"] = describe(error) }
        let level: LogLevel =
            switch code.severity {
            case .error: .error
            case .warning: .warn
            case .info: .info
            }
        Log.write(level, "\(code.rawValue)", category: category, context: fields)
        return incident
    }

    /// The error's type and description, for the log (`NSError` domain/code included).
    public static func describe(_ error: any Error) -> String {
        let ns = error as NSError
        let text = String(describing: error)
        guard ns.domain != "Foundation._GenericObjCError" else { return text }
        let typeName = String(reflecting: type(of: error))
        return ns.domain.isEmpty || text.contains(ns.domain) ? "\(typeName): \(text)" : "\(ns.domain) \(ns.code): \(text)"
    }
}
