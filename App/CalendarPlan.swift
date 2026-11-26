import EventKit
import Foundation

/// Reads the dashboard's run events (titles starting 🏃 or 🏁) and trips from the Mac's calendars.
/// Used when Google Calendar isn't connected in Settings, and as the fallback if Google can't be reached.
@MainActor
final class CalendarPlan {
    static let shared = CalendarPlan()
    private let store = EKEventStore()

    var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    func requestAccess() async -> Bool {
        if hasAccess { return true }
        do { return try await store.requestFullAccessToEvents() } catch { return false }
    }

    func upcoming() -> CalendarRead? {
        guard hasAccess else { return nil }
        let (start, end) = PlanWindow.range()
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
        return CalendarRead(events: events.map { e in
            // An all-day end is midnight after the last day, so step back a second.
            let start: Date = e.startDate ?? Date()
            let end: Date = e.endDate ?? start
            let last = end > start ? end.addingTimeInterval(-1) : start
            let cal = e.calendar
            let name = cal?.title.lowercased() ?? ""
            let ignore = cal?.type == .subscription || cal?.type == .birthday
                || ["holiday", "birthdays", "phases of the moon"].contains { name.contains($0) }
            return CalEvent(date: Fmt.key(start), endDate: Fmt.key(last), title: e.title ?? "",
                            notes: e.notes ?? "", location: e.location ?? "", travelIgnored: ignore)
        })
    }
}
