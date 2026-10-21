import Foundation

/// A date in a page: the editor's `dateMention` chip (`apps/editor/src/lib/dates.ts`), read from stored content.
/// Times are wall-clock — "09:00" is 9:00 wherever the reader is — so a date becomes a moment only against the
/// device's calendar, and a reminder rings at that wall-clock time (a calendar trigger, not an instant). The editor's
/// `fireMoment` and `fireDate` here must agree.
public struct DateMention: Sendable, Equatable {
    /// Names the chip in its page (Mark done / Snooze find it by this); nil in a chip from before ids.
    public var id: String?
    /// "YYYY-MM-DD".
    public var date: String
    /// "HH:mm", or nil for the whole day.
    public var time: String?
    /// Minutes before the date (at `dayTime` without a time) that the reminder rings; nil: no reminder.
    public var remind: Int?
    public var done: Bool
    /// A snoozed reminder rings at this wall-clock time instead ("2026-10-22T10:00").
    public var snoozed: String?

    /// When a reminder on a whole day rings.
    public static let dayTime = "09:00"

    public init(id: String?, date: String, time: String? = nil, remind: Int? = nil, done: Bool = false, snoozed: String? = nil) {
        self.id = id
        self.date = date
        self.time = time
        self.remind = remind
        self.done = done
        self.snoozed = snoozed
    }

    /// From a chip's `attrs`; nil without a well-formed date.
    public init?(attrs: JSONValue?) {
        guard case .object(let attrs)? = attrs, case .string(let date)? = attrs["date"],
            Self.components(date: date, time: nil) != nil
        else { return nil }
        self.date = date
        id = if case .string(let id)? = attrs["id"], !id.isEmpty { id } else { nil }
        time = if case .string(let time)? = attrs["time"], Self.components(date: date, time: time) != nil { time } else { nil }
        remind = if case .number(let minutes)? = attrs["remind"], minutes >= 0 { Int(minutes) } else { nil }
        done = attrs["done"] == .bool(true)
        snoozed = if case .string(let snoozed)? = attrs["snoozed"], !snoozed.isEmpty { snoozed } else { nil }
    }

    /// The chip's stored attributes.
    public var attrs: JSONValue {
        .object([
            "id": id.map(JSONValue.string) ?? .null,
            "date": .string(date),
            "time": time.map(JSONValue.string) ?? .null,
            "remind": remind.map { .number(Double($0)) } ?? .null,
            "done": .bool(done),
            "snoozed": snoozed.map(JSONValue.string) ?? .null,
        ])
    }

    /// The chip as text for search and word counts — the editor's `dateText`: "2026-10-22" or "2026-10-22 09:30".
    public var text: String { time.map { "\(date) \($0)" } ?? date }

    /// The day (at its time, else at midnight) on `calendar`.
    public func day(in calendar: Calendar) -> Date? {
        Self.components(date: date, time: time).flatMap(calendar.date(from:))
    }

    /// When the reminder rings, as wall-clock components: the snooze's time, else the date (at `dayTime` without a
    /// time) less `remind` minutes. nil without a reminder.
    public func fireComponents(in calendar: Calendar) -> DateComponents? {
        guard let remind else { return nil }
        if let snoozed {
            let parts = snoozed.split(separator: "T", maxSplits: 1).map(String.init)
            return parts.count == 2 ? Self.components(date: parts[0], time: parts[1]) : nil
        }
        guard let event = Self.components(date: date, time: time ?? Self.dayTime).flatMap(calendar.date(from:)),
            let fire = calendar.date(byAdding: .minute, value: -remind, to: event)
        else { return nil }
        return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
    }

    public func fireDate(in calendar: Calendar) -> Date? {
        fireComponents(in: calendar).flatMap(calendar.date(from:))
    }

    /// A reminder that has rung and isn't marked done.
    public func isOverdue(now: Date, calendar: Calendar) -> Bool {
        guard !done, let fire = fireDate(in: calendar) else { return false }
        return fire <= now
    }

    /// Snoozed: rings again `minutes` after `now` (wall clock).
    public mutating func snooze(minutes: Int, now: Date, calendar: Calendar) {
        let later = now.addingTimeInterval(TimeInterval(minutes * 60))
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: later)
        snoozed = String(
            format: "%04d-%02d-%02dT%02d:%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
        done = false
    }

    public mutating func markDone() {
        done = true
        snoozed = nil
    }

    /// "YYYY-MM-DD" (and "HH:mm") as calendar components; nil when either is malformed or no such day.
    static func components(date: String, time: String?) -> DateComponents? {
        let d = date.split(separator: "-").compactMap { Int($0) }
        guard d.count == 3, date.count == 10, (1...12).contains(d[1]), (1...31).contains(d[2]) else { return nil }
        var c = DateComponents(year: d[0], month: d[1], day: d[2], hour: 0, minute: 0)
        if let time {
            let t = time.split(separator: ":").compactMap { Int($0) }
            guard t.count == 2, time.count == 5, (0...23).contains(t[0]), (0...59).contains(t[1]) else { return nil }
            c.hour = t[0]
            c.minute = t[1]
        }
        // February 30th isn't a day.
        let gregorian = Calendar(identifier: .gregorian)
        guard let day = gregorian.date(from: c), gregorian.component(.day, from: day) == d[2] else { return nil }
        return c
    }
}

/// The dates in a page's content, and changes to one of them (a reminder's Mark done / Snooze, written natively).
public enum DateMentions {
    /// A chip where it was found: its line's block id and the line's words without the chip (a notification's
    /// title, Home's row).
    public struct Found: Sendable, Equatable {
        public var mention: DateMention
        public var blockId: String
        public var text: String

        public init(mention: DateMention, blockId: String, text: String) {
            self.mention = mention
            self.blockId = blockId
            self.text = text
        }
    }

    private static let lineTypes: Set<String> = ["paragraph", "heading", "detailsSummary"]

    /// Every date in the content, in document order.
    public static func find(in content: JSONValue?) -> [Found] {
        guard let content else { return [] }
        var out: [Found] = []
        visit(content, into: &out)
        return out
    }

    private static func visit(_ node: JSONValue, into out: inout [Found]) {
        guard case .object(let fields) = node, case .array(let children)? = fields["content"] else { return }
        if case .string(let type)? = fields["type"], lineTypes.contains(type) {
            let chips = children.compactMap { child -> DateMention? in
                guard case .object(let f) = child, f["type"] == .string("dateMention") else { return nil }
                return DateMention(attrs: f["attrs"])
            }
            guard !chips.isEmpty else { return }
            let words = children.filter {
                if case .object(let f) = $0, f["type"] == .string("dateMention") { false } else { true }
            }
            .map { ContentText.plainText(of: $0) }.joined()
            let text = words.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let blockId: String =
                if case .object(let attrs)? = fields["attrs"], case .string(let id)? = attrs["id"] { id } else { "" }
            out.append(contentsOf: chips.map { Found(mention: $0, blockId: blockId, text: text) })
            return
        }
        for child in children { visit(child, into: &out) }
    }

    /// The content with the chip named `id` changed by `change`; nil when no chip has that id.
    public static func updating(_ content: JSONValue, id: String, _ change: (inout DateMention) -> Void) -> JSONValue? {
        var found = false
        func map(_ node: JSONValue) -> JSONValue {
            guard case .object(var fields) = node else { return node }
            if fields["type"] == .string("dateMention"), var mention = DateMention(attrs: fields["attrs"]),
                mention.id == id
            {
                found = true
                change(&mention)
                fields["attrs"] = mention.attrs
                return .object(fields)
            }
            if case .array(let children)? = fields["content"] { fields["content"] = .array(children.map(map)) }
            return .object(fields)
        }
        let next = map(content)
        return found ? next : nil
    }
}

/// A date somewhere in the workspace, with its page: what Home's Upcoming and the reminders are made from.
public struct DateEntry: Sendable, Equatable, Identifiable {
    public var pageId: String
    public var pageTitle: String
    public var found: DateMentions.Found

    public init(pageId: String, pageTitle: String, found: DateMentions.Found) {
        self.pageId = pageId
        self.pageTitle = pageTitle
        self.found = found
    }

    public var id: String { "\(pageId)/\(found.mention.id ?? "\(found.blockId)/\(found.mention.text)")" }
    public var mention: DateMention { found.mention }

    /// Every date in a page.
    public static func entries(pageId: String, title: String, content: JSONValue?) -> [DateEntry] {
        DateMentions.find(in: content).map { DateEntry(pageId: pageId, pageTitle: title, found: $0) }
    }
}

public enum Upcoming {
    /// Home's Upcoming: reminders that have rung and aren't done (oldest first), then every date from today through
    /// the next `days` days (soonest first).
    public static func items(_ entries: [DateEntry], now: Date, calendar: Calendar, days: Int = 7) -> [DateEntry] {
        let overdue = entries.filter { $0.mention.isOverdue(now: now, calendar: calendar) }
            .sorted { ($0.mention.fireDate(in: calendar) ?? .distantPast) < ($1.mention.fireDate(in: calendar) ?? .distantPast) }
        let shown = Set(overdue.map(\.id))
        let today = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: days, to: today) else { return overdue }
        let soon = entries.filter { entry in
            guard !shown.contains(entry.id), let day = entry.mention.day(in: calendar) else { return false }
            return day >= today && day < end
        }
        .sorted { ($0.mention.day(in: calendar) ?? .distantFuture) < ($1.mention.day(in: calendar) ?? .distantFuture) }
        return overdue + soon
    }

    /// The reminders still to ring, soonest first, at most `limit` (iOS keeps 64 pending notifications per app).
    public static func pending(_ entries: [DateEntry], now: Date, calendar: Calendar, limit: Int = 64)
        -> [(entry: DateEntry, fire: DateComponents)]
    {
        entries.compactMap { entry -> (DateEntry, DateComponents, Date)? in
            guard !entry.mention.done, let fire = entry.mention.fireComponents(in: calendar),
                let at = calendar.date(from: fire), at > now
            else { return nil }
            return (entry, fire, at)
        }
        .sorted { $0.2 < $1.2 }
        .prefix(limit)
        .map { ($0.0, $0.1) }
    }

    /// How a date reads relative to today: Today / Tomorrow / Yesterday, a weekday within the week ahead, else the
    /// date (with its year when not this one) — the editor's `dateLabel`.
    public enum Day: Sendable, Equatable {
        case today, tomorrow, yesterday
        case weekday(Date)
        case date(Date, withYear: Bool)
    }

    public static func day(of mention: DateMention, now: Date, calendar: Calendar) -> Day? {
        guard let components = DateMention.components(date: mention.date, time: nil),
            let day = calendar.date(from: components)
        else { return nil }
        let diff = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: day).day ?? 0
        switch diff {
        case 0: return .today
        case 1: return .tomorrow
        case -1: return .yesterday
        case 2..<7: return .weekday(day)
        default:
            return .date(day, withYear: calendar.component(.year, from: day) != calendar.component(.year, from: now))
        }
    }
}
