// SPDX-License-Identifier: Apache-2.0

import AppKit
import EventKit
import UserNotifications
import NotyKit

/// Local notifications for reminders. Everything is rescheduled from the library, so a reminder added by an agent or on another Mac still fires.
@MainActor
enum NotifyScheduler {
    private static var center: UNUserNotificationCenter? { Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current() }   // a bare `swift run` binary has no identity

    static func authorize() async -> Bool {
        guard let c = center else { return false }
        return (try? await c.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func sync(_ items: [Item]) {
        guard let c = center else { return }
        let now = Date(); let cal = Calendar.current
        var wanted: [(UNNotificationRequest, Date)] = []
        for it in items where !it.done {
            for r in it.reminders where !r.done && r.kind == .reminder {
                func request(_ id: String, _ when: Date, _ title: String) -> UNNotificationRequest {
                    let content = UNMutableNotificationContent()
                    content.title = title; content.body = "\(it.title) · \(it.pathLabel)"; content.sound = .default
                    content.userInfo = ["item": it.id]
                    let trigger = UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: when), repeats: false)
                    return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                }
                if r.due > now { wanted.append((request("noty-rem-\(r.id)", r.due, r.text), r.due)) }
                if r.nudge, r.due.addingTimeInterval(3600) > now { wanted.append((request("noty-rem-\(r.id)-nudge", r.due.addingTimeInterval(3600), "Still open: \(r.text)"), r.due.addingTimeInterval(3600))) }
            }
        }
        let soonest = wanted.sorted { $0.1 < $1.1 }.prefix(60).map(\.0)   // the system keeps at most 64 pending
        Task {
            let pending = await c.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("noty-rem-") }
            c.removePendingNotificationRequests(withIdentifiers: pending)
            for r in soonest { try? await c.add(r) }
        }
    }
}

/// Opens an item when its notification is clicked, and shows the banner even while Noty is in front.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let id = response.notification.request.content.userInfo["item"] as? String else { return }
        await MainActor.run { if let url = URL(string: Deeplink.url(item: id)) { AppDelegate.shared.application(NSApp, open: [url]) } }
    }
}

/// The user's Calendar: events for the Agenda, busy times for the AI pick, and new events from "Schedule".
@MainActor
final class CalendarBridge {
    static let shared = CalendarBridge()
    private let store = EKEventStore()

    var authorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    var denied: Bool { [.denied, .restricted].contains(EKEventStore.authorizationStatus(for: .event)) }

    func request() async -> Bool {
        if authorized { return true }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    func events(from: Date, to: Date) -> [EKEvent] {
        guard authorized else { return [] }
        return store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: nil)).filter { !$0.isAllDay }.sorted { $0.startDate < $1.startDate }
    }

    /// Start times of events in the next two weeks, so the suggested time avoids them.
    func busyStarts() -> [Date] { events(from: Date(), to: Date().addingTimeInterval(14 * 86400)).map(\.startDate) }

    func add(title: String, start: Date, notes: String) throws -> String {
        let e = EKEvent(eventStore: store)
        e.title = title; e.startDate = start; e.endDate = start.addingTimeInterval(3600); e.notes = notes
        e.calendar = store.defaultCalendarForNewEvents
        try store.save(e, span: .thisEvent)
        return e.eventIdentifier ?? ""
    }
}
