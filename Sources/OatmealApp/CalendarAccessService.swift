import CryptoKit
import EventKit
import Foundation
import OatmealCore

@MainActor
protocol CalendarAccessServing {
    func authorizationStatus() -> PermissionStatus
    func requestAccess() async -> PermissionStatus
    func upcomingEvents(referenceDate: Date, horizon: TimeInterval) async throws -> [CalendarEvent]
}

enum CalendarAccessError: LocalizedError {
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            "Oatmeal does not have calendar access yet."
        }
    }
}

@MainActor
final class LiveCalendarAccessService: CalendarAccessServing {
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    func authorizationStatus() -> PermissionStatus {
        Self.mapAuthorizationStatus(EKEventStore.authorizationStatus(for: .event))
    }

    func requestAccess() async -> PermissionStatus {
        do {
            if #available(macOS 14.0, *) {
                _ = try await eventStore.requestFullAccessToEvents()
            } else {
                _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                    eventStore.requestAccess(to: .event) { granted, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: granted)
                        }
                    }
                }
            }
        } catch {
            return authorizationStatus()
        }

        return authorizationStatus()
    }

    func upcomingEvents(referenceDate: Date, horizon: TimeInterval) async throws -> [CalendarEvent] {
        guard authorizationStatus() == .granted else {
            throw CalendarAccessError.unauthorized
        }

        let endDate = referenceDate.addingTimeInterval(horizon)
        let predicate = eventStore.predicateForEvents(withStart: referenceDate, end: endDate, calendars: nil)

        return eventStore.events(matching: predicate)
            .map(Self.mapEvent(_:))
            .filter(\.isRelevantForHomeScreen)
            .sorted { $0.startDate < $1.startDate }
    }

    private static func mapAuthorizationStatus(_ status: EKAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined:
            .notDetermined
        case .fullAccess, .writeOnly:
            .granted
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .restricted
        }
    }

    private static func mapEvent(_ event: EKEvent) -> CalendarEvent {
        let attendees = makeParticipants(from: event)
        let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? "Untitled meeting"
        let kind = eventKind(for: event, title: title)

        return CalendarEvent(
            id: stableEventID(for: event),
            title: title,
            startDate: event.startDate,
            endDate: event.endDate,
            attendees: attendees,
            conferencingURL: event.url,
            source: eventSource(for: event),
            kind: kind,
            attendanceStatus: attendanceStatus(for: event),
            location: event.location,
            notes: event.notes,
            timezoneIdentifier: event.timeZone?.identifier
        )
    }

    private static func makeParticipants(from event: EKEvent) -> [MeetingParticipant] {
        var participants: [MeetingParticipant] = []

        if let organizer = event.organizer {
            participants.append(
                MeetingParticipant(
                    id: stableParticipantID(for: organizer),
                    name: organizer.name?.nilIfBlank ?? "Organizer",
                    email: emailAddress(for: organizer),
                    isOrganizer: true
                )
            )
        }

        for attendee in event.attendees ?? [] {
            let participant = MeetingParticipant(
                id: stableParticipantID(for: attendee),
                name: attendee.name?.nilIfBlank ?? "Attendee",
                email: emailAddress(for: attendee),
                isOrganizer: false
            )

            if !participants.contains(where: { $0.id == participant.id }) {
                participants.append(participant)
            }
        }

        return participants
    }

    private static func emailAddress(for participant: EKParticipant) -> String? {
        let absolute = participant.url.absoluteString
        guard let absolute = absolute.nilIfBlank else {
            return nil
        }

        if absolute.hasPrefix("mailto:") {
            return String(absolute.dropFirst("mailto:".count))
        }

        return absolute
    }

    private static func eventSource(for event: EKEvent) -> CalendarEventSource {
        let sourceTitle = event.calendar.source.title.lowercased()

        if event.calendar.source.sourceType == .exchange
            || sourceTitle.contains("exchange")
            || sourceTitle.contains("outlook")
            || sourceTitle.contains("office")
            || sourceTitle.contains("microsoft") {
            return .microsoftCalendar
        }

        if sourceTitle.contains("google") || sourceTitle.contains("gmail") {
            return .googleCalendar
        }

        return .local
    }

    private static func eventKind(for event: EKEvent, title: String) -> CalendarEventKind {
        if event.isAllDay {
            return .allDayPlaceholder
        }

        let normalizedTitle = title.lowercased()
        if normalizedTitle.contains("focus")
            || normalizedTitle.contains("out of office")
            || normalizedTitle == "ooo"
            || normalizedTitle.contains("do not book") {
            return .focusBlock
        }

        return .meeting
    }

    private static func attendanceStatus(for event: EKEvent) -> AttendanceStatus {
        if let selfParticipant = event.attendees?.first(where: \.isCurrentUser) {
            switch selfParticipant.participantStatus {
            case .accepted, .completed, .delegated:
                return .accepted
            case .declined:
                return .declined
            case .tentative:
                return .tentative
            case .pending, .unknown, .inProcess:
                return .invited
            @unknown default:
                return .unknown
            }
        }

        return .unknown
    }

    private static func stableEventID(for event: EKEvent) -> UUID {
        stableUUID(seed: event.calendarItemExternalIdentifier.nilIfBlank ?? event.eventIdentifier ?? "\(event.title ?? "event")|\(event.startDate.timeIntervalSince1970)")
    }

    private static func stableParticipantID(for participant: EKParticipant) -> UUID {
        stableUUID(seed: participant.url.absoluteString.nilIfBlank ?? participant.name?.nilIfBlank ?? UUID().uuidString)
    }

    private static func stableUUID(seed: String) -> UUID {
        let digest = SHA256.hash(data: Data(seed.utf8))
        let bytes = Array(digest.prefix(16))

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
