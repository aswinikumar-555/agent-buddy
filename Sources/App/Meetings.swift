// Meetings from the macOS Calendar app (any account added there: Google, iCloud,
// Exchange, …). Read-only; asks for calendar access once.
import EventKit
import Foundation

struct Meeting: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let calendar: String
    let joinURL: URL?     // Zoom, Google Meet, Teams, … link from the event

    func isNow(_ now: Date) -> Bool { start <= now && now < end }
}

final class MeetingWatcher {
    private let store = EKEventStore()
    private(set) var access: Access = .unknown
    enum Access { case unknown, granted, denied }

    /// Asks once (macOS shows its own prompt); later calls just read the answer.
    func requestAccess(_ done: @escaping (Access) -> Void) {
        let status = EKEventStore.authorizationStatus(for: .event)
        NSLog("Agent Buddy: calendar access status \(status.rawValue)")
        if status == .fullAccess { access = .granted; done(access); return }
        if status == .denied || status == .restricted { access = .denied; done(access); return }
        store.requestFullAccessToEvents { granted, error in
            NSLog("Agent Buddy: calendar access \(granted ? "granted" : "not granted") \(error.map { "\($0)" } ?? "")")
            DispatchQueue.main.async {
                self.access = granted ? .granted : .denied
                done(self.access)
            }
        }
    }

    /// Timed events (not all-day) from now until the end of tomorrow, skipping ones you declined.
    func upcoming(now: Date = Date()) -> [Meeting] {
        guard access == .granted else { return [] }
        let cal = Calendar.current
        let from = now.addingTimeInterval(-4 * 3600)
        let to = cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        let events = store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: nil))
        return events.compactMap { e in
            guard !e.isAllDay, e.endDate > now, e.status != .canceled else { return nil }
            if let me = e.attendees?.first(where: \.isCurrentUser), me.participantStatus == .declined { return nil }
            return Meeting(id: (e.calendarItemIdentifier) + "@\(e.startDate.timeIntervalSince1970)",
                           title: e.title?.isEmpty == false ? e.title! : "Meeting",
                           start: e.startDate, end: e.endDate,
                           calendar: e.calendar?.title ?? "",
                           joinURL: Self.joinLink(e))
        }
        .sorted { $0.start < $1.start }
    }

    /// The first video-call link in the event's URL, location or notes.
    static func joinLink(_ e: EKEvent) -> URL? {
        let text = [e.url?.absoluteString, e.location, e.notes].compactMap { $0 }.joined(separator: " ")
        let pattern = #"https://[^\s<>"']*(zoom\.us/|meet\.google\.com/|teams\.microsoft\.com/|teams\.live\.com/|webex\.com/|whereby\.com/|around\.co/|meet\.jit\.si/)[^\s<>"']*"#
        guard let r = text.range(of: pattern, options: .regularExpression) else { return e.url }
        return URL(string: String(text[r]))
    }
}
