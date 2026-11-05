// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A reminder or calendar event made from something the user highlighted in an item.
public struct Reminder: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case reminder, event }
    public var id: String
    /// The highlighted words, used as the reminder's wording.
    public var text: String
    public var due: Date
    public var kind: Kind
    /// Remind again an hour later when it is still open.
    public var nudge: Bool
    public var done: Bool
    /// The Calendar event that was created for a `.event`, so it can be found again.
    public var eventID: String?

    public init(id: String = UUID().uuidString, text: String, due: Date, kind: Kind = .reminder, nudge: Bool = false, done: Bool = false, eventID: String? = nil) {
        self.id = id; self.text = text; self.due = due; self.kind = kind; self.nudge = nudge; self.done = done; self.eventID = eventID
    }
}

/// Picks and parses times for a reminder: what the text itself says ("tomorrow", "before Friday", "at 3pm", "in 2 hours"),
/// else the next free slot in working hours. Pure functions of the clock, so they are tested.
public enum ReminderTime {
    public struct Option: Equatable, Sendable { public var label: String; public var date: Date }
    public struct Suggestion: Equatable, Sendable {
        public var pick: Date
        public var reason: String
        public var options: [Option]
    }

    static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    static let workStart = 9, workEnd = 18

    public static func suggest(now: Date = Date(), text: String, busy: [Date] = [], calendar cal: Calendar = .current) -> Suggestion {
        let pick: Date; let reason: String
        if let (parsed, why) = parse(text, now: now, calendar: cal) { pick = parsed; reason = why }
        else {
            pick = freeSlot(after: now, busy: busy, calendar: cal)
            reason = busy.contains { abs($0.timeIntervalSince(pick)) < 1800 } ? "Next free slot." : (busy.isEmpty ? "Next free slot in working hours." : "Free slot: nothing else is set around then.")
        }
        var options: [Option] = []
        func add(_ label: String, _ d: Date) { if abs(d.timeIntervalSince(pick)) > 60, !options.contains(where: { $0.label == label }) { options.append(Option(label: label, date: d)) } }
        add("In 1 hour", roundedUp(now.addingTimeInterval(3600), minutes: 1, calendar: cal))
        add("Tomorrow morning", at(workStart, 0, daysFrom: 1, now: now, calendar: cal))
        add("Next week", nextWeekday(2, from: now, calendar: cal, hour: workStart))
        return Suggestion(pick: pick, reason: reason, options: options)
    }

    /// A time the text asks for, with a short reason; nil when it says nothing about time.
    public static func parse(_ raw: String, now: Date = Date(), calendar cal: Calendar = .current) -> (Date, String)? {
        let t = raw.lowercased()
        // "in 2 hours", "in 30 minutes", "in 3 days"
        if let m = t.range(of: #"\bin (\d{1,3}) ?(minute|min|hour|hr|day)s?\b"#, options: .regularExpression) {
            let parts = t[m].split(separator: " ").map(String.init)
            if parts.count >= 3, let n = Int(parts[1].filter(\.isNumber)) {
                let unit = parts[2].hasPrefix("min") ? 60 : parts[2].hasPrefix("h") ? 3600 : 86400
                return (now.addingTimeInterval(Double(n * unit)), "Says \"\(t[m])\".")
            }
        }
        let clock = clockTime(in: t)
        var day: Date?; var why = ""
        if t.contains("tonight") { day = cal.startOfDay(for: now); why = "Says \"tonight\"." ; return (set(day!, clock ?? (20, 0), cal, now: now, fallbackLater: true), why) }
        if t.contains("tomorrow") { day = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)); why = "Says \"tomorrow\"." }
        else if t.contains("next week") { return (nextWeekday(2, from: now, calendar: cal, hour: clock?.0 ?? workStart, minute: clock?.1 ?? 0), "Says \"next week\".") }
        else if let (idx, name, before) = weekday(in: t) {
            var d = nextWeekdayDate(idx + 1, from: now, calendar: cal)
            if before {   // "before Friday": the day before, in the afternoon
                d = cal.date(byAdding: .day, value: -1, to: d) ?? d
                if d < cal.startOfDay(for: now) { d = cal.startOfDay(for: now) }
                return (set(d, clock ?? (16, 0), cal, now: now, fallbackLater: true), "Says \"before \(name)\".")
            }
            day = d; why = "Says \"\(name)\"."
        } else if t.contains("today") || t.contains("this afternoon") || t.contains("this morning") || t.contains("end of day") || t.contains("eod") {
            day = cal.startOfDay(for: now); why = "Says \"today\"."
            if clock == nil { return (freeSlot(after: now, busy: [], calendar: cal), why) }
        }
        if let day { return (set(day, clock ?? (workStart, 0), cal, now: now, fallbackLater: false), why) }
        if let clock {   // only a time: today if it is still ahead, else tomorrow
            let d = set(cal.startOfDay(for: now), clock, cal, now: now, fallbackLater: true)
            return (d, "Says \"\(String(format: "%d:%02d", clock.0, clock.1))\".")
        }
        return nil
    }

    // MARK: pieces

    private static func clockTime(in t: String) -> (Int, Int)? {
        if let m = t.range(of: #"\b(\d{1,2})(?::(\d{2}))? ?(am|pm)\b"#, options: .regularExpression) {
            let s = String(t[m]); let pm = s.hasSuffix("pm")
            let digits = s.replacingOccurrences(of: "am", with: "").replacingOccurrences(of: "pm", with: "").trimmingCharacters(in: .whitespaces).split(separator: ":")
            if var h = Int(digits[0]), (1...12).contains(h) { if pm && h < 12 { h += 12 }; if !pm && h == 12 { h = 0 }; return (h, digits.count > 1 ? Int(digits[1]) ?? 0 : 0) }
        }
        if let m = t.range(of: #"\b([01]?\d|2[0-3]):([0-5]\d)\b"#, options: .regularExpression) {
            let p = t[m].split(separator: ":"); if let h = Int(p[0]), let mi = Int(p[1]) { return (h, mi) }
        }
        if let m = t.range(of: #"\bat (\d{1,2})\b"#, options: .regularExpression), let h = Int(t[m].dropFirst(3)), (1...12).contains(h) { return (h < 7 ? h + 12 : h, 0) }
        return nil
    }

    private static func weekday(in t: String) -> (Int, String, Bool)? {
        for (i, name) in weekdays.enumerated() {
            let short = String(name.prefix(3))
            if t.range(of: #"\b(\#(name)|\#(short))\b"#, options: .regularExpression) != nil {
                return (i, name.capitalized, t.contains("before \(name)") || t.contains("before \(short)"))
            }
        }
        return nil
    }

    private static func set(_ day: Date, _ time: (Int, Int), _ cal: Calendar, now: Date, fallbackLater: Bool) -> Date {
        var d = cal.date(bySettingHour: time.0, minute: time.1, second: 0, of: day) ?? day
        if fallbackLater, d <= now { d = cal.date(byAdding: .day, value: 1, to: d) ?? d }
        return d
    }

    private static func at(_ h: Int, _ m: Int, daysFrom: Int, now: Date, calendar cal: Calendar) -> Date {
        let day = cal.date(byAdding: .day, value: daysFrom, to: cal.startOfDay(for: now)) ?? now
        return cal.date(bySettingHour: h, minute: m, second: 0, of: day) ?? day
    }

    /// The next date that falls on `weekday` (1 = Sunday … 7 = Saturday), today excluded.
    private static func nextWeekdayDate(_ weekday: Int, from now: Date, calendar cal: Calendar) -> Date {
        cal.nextDate(after: cal.startOfDay(for: now), matching: DateComponents(weekday: weekday), matchingPolicy: .nextTime) ?? now
    }

    static func nextWeekday(_ weekday: Int, from now: Date, calendar cal: Calendar, hour: Int, minute: Int = 0) -> Date {
        let d = nextWeekdayDate(weekday, from: now, calendar: cal)
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: d) ?? d
    }

    static func roundedUp(_ d: Date, minutes: Int, calendar cal: Calendar) -> Date {
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: d)
        let m = c.minute ?? 0; let up = (m + minutes - 1) / minutes * minutes
        return (cal.date(from: c) ?? d).addingTimeInterval(Double(up - m) * 60)
    }

    /// The first half hour inside working hours, an hour or more from now, that no other reminder sits next to.
    static func freeSlot(after now: Date, busy: [Date], calendar cal: Calendar) -> Date {
        var d = roundedUp(now.addingTimeInterval(3600), minutes: 30, calendar: cal)
        for _ in 0..<96 {
            let h = cal.component(.hour, from: d)
            if h < workStart { d = cal.date(bySettingHour: workStart, minute: 0, second: 0, of: d) ?? d }
            else if h >= workEnd { d = cal.date(bySettingHour: workStart, minute: 0, second: 0, of: cal.date(byAdding: .day, value: 1, to: d) ?? d) ?? d }
            if !busy.contains(where: { abs($0.timeIntervalSince(d)) < 1800 }) { return d }
            d = d.addingTimeInterval(1800)
        }
        return d
    }

    /// "Today 15:30", "Tomorrow 09:00", "Mon 09:00", or "12 Nov 09:00".
    public static func label(_ d: Date, now: Date = Date(), calendar cal: Calendar = .current) -> String {
        let f = DateFormatter(); f.calendar = cal; f.locale = Locale.current
        f.dateFormat = "HH:mm"; let time = f.string(from: d)
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: d)).day ?? 0
        switch days {
        case 0: return "Today \(time)"
        case 1: return "Tomorrow \(time)"
        case 2...6: f.dateFormat = "EEE"; return "\(f.string(from: d)) \(time)"
        default: f.dateFormat = "d MMM"; return "\(f.string(from: d)) \(time)"
        }
    }
}

/// One line of the Agenda: a reminder from an item, or an event from the calendar.
public struct AgendaEntry: Identifiable, Equatable, Sendable {
    public var id: String
    public var date: Date
    public var title: String
    public var detail: String
    public var kind: Reminder.Kind
    public var fromCalendar: Bool
    public var itemID: String?
    public var done: Bool
    public init(id: String, date: Date, title: String, detail: String = "", kind: Reminder.Kind, fromCalendar: Bool = false, itemID: String? = nil, done: Bool = false) {
        self.id = id; self.date = date; self.title = title; self.detail = detail; self.kind = kind; self.fromCalendar = fromCalendar; self.itemID = itemID; self.done = done
    }
}

/// The "Noty is keeping tabs" paragraph. Plain rules over the entries, so it works with no model; an agent can say more through the MCP tools.
public enum AgendaSummary {
    public static func text(entries: [AgendaEntry], now: Date = Date(), calendar cal: Calendar = .current) -> String {
        let open = entries.filter { !$0.done }
        let startOfToday = cal.startOfDay(for: now)
        let overdue = open.filter { $0.date < startOfToday && !$0.fromCalendar }
        let pastToday = open.filter { $0.date >= startOfToday && $0.date < now && !$0.fromCalendar && cal.isDate($0.date, inSameDayAs: now) }.count
        let today = open.filter { cal.isDate($0.date, inSameDayAs: now) }
        let reminders = today.filter { !$0.fromCalendar }.count, events = today.filter { $0.fromCalendar || $0.kind == .event }.count
        var parts: [String] = []
        if today.isEmpty { parts.append("Nothing is scheduled today.") }
        else {
            var bits: [String] = []
            if events > 0 { bits.append("\(events) event\(events == 1 ? "" : "s")") }
            if reminders > 0 { bits.append("\(reminders) reminder\(reminders == 1 ? "" : "s")") }
            parts.append("Today: " + bits.joined(separator: " and ") + (pastToday > 0 ? " (\(pastToday) already past due)" : "") + ".")
            if let next = today.filter({ $0.date >= now }).min(by: { $0.date < $1.date }) {
                let f = DateFormatter(); f.dateFormat = "HH:mm"
                parts.append("Next up: \(next.title) at \(f.string(from: next.date)).")
            }
        }
        if !overdue.isEmpty { parts.append("\(overdue.count) reminder\(overdue.count == 1 ? " is" : "s are") overdue from earlier days.") }
        let week = Dictionary(grouping: open.filter { $0.date >= cal.startOfDay(for: now) && $0.date < (cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: now)) ?? now) }) { cal.startOfDay(for: $0.date) }
        if let heavy = week.max(by: { $0.value.count < $1.value.count }), heavy.value.count >= 4 {
            let f = DateFormatter(); f.dateFormat = "EEEE"
            parts.append("\(f.string(from: heavy.key)) is the heaviest day with \(heavy.value.count) items.")
        }
        return parts.joined(separator: " ")
    }
}
