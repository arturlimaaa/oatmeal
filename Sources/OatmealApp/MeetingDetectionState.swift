import Foundation
import OatmealCore

struct PendingMeetingDetection: Codable, Equatable, Sendable, Identifiable {
    enum Phase: String, Codable, Equatable, Sendable {
        case start
        case endSuggestion
    }

    enum Presentation: String, Codable, Equatable, Sendable {
        case prompt
        case passiveSuggestion
    }

    enum Confidence: String, Codable, Equatable, Sendable {
        case low
        case high
    }

    struct Source: Codable, Equatable, Sendable {
        enum Kind: String, Codable, Equatable, Sendable {
            case nativeApp
            case browser
            case unknown
        }

        var kind: Kind
        var displayName: String

        static func nativeApp(_ displayName: String) -> Self {
            Self(kind: .nativeApp, displayName: displayName)
        }

        static func browser(_ displayName: String) -> Self {
            Self(kind: .browser, displayName: displayName)
        }

        static let unknown = Self(kind: .unknown, displayName: "Meeting")
    }

    let id: UUID
    var title: String
    var source: Source
    var phase: Phase
    var detectedAt: Date
    var presentation: Presentation
    var confidence: Confidence
    var promptWasDismissed: Bool
    var calendarEvent: CalendarEvent?
    var candidateCalendarEvents: [CalendarEvent]

    init(
        id: UUID = UUID(),
        title: String = "Untitled Meeting",
        source: Source,
        phase: Phase = .start,
        detectedAt: Date = Date(),
        presentation: Presentation = .prompt,
        confidence: Confidence? = nil,
        promptWasDismissed: Bool = false,
        calendarEvent: CalendarEvent? = nil,
        candidateCalendarEvents: [CalendarEvent] = []
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Meeting" : title
        self.source = source
        self.phase = phase
        self.detectedAt = detectedAt
        self.presentation = presentation
        self.confidence = confidence ?? (presentation == .prompt ? .high : .low)
        self.promptWasDismissed = promptWasDismissed
        self.calendarEvent = calendarEvent
        self.candidateCalendarEvents = candidateCalendarEvents
    }

    var effectiveTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Meeting" : title
    }

    var displayTitle: String {
        calendarEvent?.title ?? effectiveTitle
    }

    var requiresCalendarChoice: Bool {
        calendarEvent == nil && !candidateCalendarEvents.isEmpty
    }

    var calendarContextSignature: String {
        let matched = calendarEvent.map { "matched:\($0.id.uuidString)" } ?? "matched:none"
        let candidates = candidateCalendarEvents
            .map(\.id.uuidString)
            .sorted()
            .joined(separator: ",")
        return "\(phase.rawValue)|\(matched)|candidates:\(candidates)"
    }
}

struct MeetingDetectionCandidateOption: Equatable, Sendable, Identifiable {
    let id: CalendarEvent.ID
    let title: String
    let subtitle: String
}

struct MeetingDetectionPromptState: Equatable, Sendable, Identifiable {
    enum Kind: Equatable, Sendable {
        case prompt
        case passiveSuggestion
    }

    let id: UUID
    let phase: PendingMeetingDetection.Phase
    let title: String
    let sourceName: String
    let sourceKind: PendingMeetingDetection.Source.Kind
    let detectedAt: Date
    let kind: Kind
    let detailText: String
    let menuBarSummary: String
    let symbolName: String
    let headline: String
    let primaryActionTitle: String
    let primaryActionEnabled: Bool
    let secondaryActionTitle: String?
    let noteID: UUID?
    let candidateOptions: [MeetingDetectionCandidateOption]
    let selectedCandidateID: UUID?
}

enum MeetingDetectionPromptAdapter {
    static func promptState(for detection: PendingMeetingDetection?) -> MeetingDetectionPromptState? {
        guard let detection, detection.presentation == .prompt else {
            return nil
        }

        return makeState(for: detection, kind: .prompt)
    }

    static func menuBarState(for detection: PendingMeetingDetection?) -> MeetingDetectionPromptState? {
        guard let detection else {
            return nil
        }

        let kind: MeetingDetectionPromptState.Kind = detection.presentation == .prompt ? .prompt : .passiveSuggestion
        return makeState(for: detection, kind: kind)
    }

    private static func makeState(
        for detection: PendingMeetingDetection,
        kind: MeetingDetectionPromptState.Kind
    ) -> MeetingDetectionPromptState {
        let sourceLead = switch detection.source.kind {
        case .browser:
            detection.phase == .endSuggestion
                ? "Oatmeal thinks the browser call in \(detection.source.displayName) may have ended."
                : "Oatmeal noticed a likely browser call in \(detection.source.displayName)."
        case .nativeApp:
            detection.phase == .endSuggestion
                ? "Oatmeal thinks the meeting in \(detection.source.displayName) may have ended."
                : "Oatmeal noticed a likely meeting in \(detection.source.displayName)."
        case .unknown:
            detection.phase == .endSuggestion
                ? "Oatmeal thinks the meeting may have ended."
                : "Oatmeal noticed a likely meeting."
        }

        let detailText: String
        let menuBarSummary: String
        let headline: String
        let primaryActionTitle: String
        let secondaryActionTitle: String?
        let candidateOptions = detection.candidateCalendarEvents.map(makeCandidateOption)

        if detection.phase == .endSuggestion {
            switch kind {
            case .prompt:
                detailText = "\(sourceLead) Capture is still running locally. Stop recording when you are ready, or keep recording if the conversation is still going."
                menuBarSummary = "Oatmeal thinks this meeting may have ended. Stop capture when you are ready."
                headline = "Meeting may have ended"
                primaryActionTitle = "Stop Recording"
                secondaryActionTitle = "Keep Recording"
            case .passiveSuggestion:
                detailText = "\(sourceLead) Oatmeal kept the stop suggestion available in the lightweight surfaces so you can end capture when it feels right."
                menuBarSummary = "Oatmeal still thinks this meeting may have ended. Stop capture when you are ready."
                headline = "Passive suggestion"
                primaryActionTitle = "Stop Recording"
                secondaryActionTitle = nil
            }
        } else if detection.requiresCalendarChoice {
            switch kind {
            case .prompt:
                detailText = "\(sourceLead) Oatmeal found a few nearby meetings. Choose one so the start flow stays attached to the right calendar context."
                menuBarSummary = "A likely meeting was detected. Choose the right calendar event before starting."
                headline = "Choose meeting"
                primaryActionTitle = "Start Oatmeal"
                secondaryActionTitle = "Not now"
            case .passiveSuggestion:
                detailText = "\(sourceLead) Oatmeal kept the detected call in the menu bar. Reopen the prompt later to choose the right calendar meeting."
                menuBarSummary = "A likely meeting is still available. Reopen the prompt to choose a calendar match."
                headline = "Passive suggestion"
                primaryActionTitle = "Start Oatmeal"
                secondaryActionTitle = nil
            }
        } else if detection.calendarEvent != nil {
            switch kind {
            case .prompt:
                detailText = "\(sourceLead) Oatmeal matched this call to a nearby calendar event, so you can start capture without opening the full app."
                menuBarSummary = "A nearby calendar event is ready. Start Oatmeal when you are ready."
                headline = "Meeting detected"
                primaryActionTitle = "Start Oatmeal"
                secondaryActionTitle = "Not now"
            case .passiveSuggestion:
                detailText = "\(sourceLead) Oatmeal kept the matched calendar event in the menu bar so you can still start this meeting later."
                menuBarSummary = "A matched meeting is still available from the menu bar."
                headline = "Passive suggestion"
                primaryActionTitle = "Start Oatmeal"
                secondaryActionTitle = nil
            }
        } else {
            switch kind {
            case .prompt:
                detailText = "\(sourceLead) Start Oatmeal to begin local capture without opening the full app."
                menuBarSummary = "A likely meeting was detected. Start Oatmeal when you are ready."
                headline = "Meeting detected"
                primaryActionTitle = "Start Oatmeal"
                secondaryActionTitle = "Not now"
            case .passiveSuggestion:
                detailText = "\(sourceLead) Oatmeal kept a passive suggestion in the menu bar so you can still start this meeting later."
                menuBarSummary = "A likely meeting is still available from the menu bar."
                headline = "Passive suggestion"
                primaryActionTitle = "Start Oatmeal"
                secondaryActionTitle = nil
            }
        }

        return MeetingDetectionPromptState(
            id: detection.id,
            phase: detection.phase,
            title: detection.displayTitle,
            sourceName: detection.source.displayName,
            sourceKind: detection.source.kind,
            detectedAt: detection.detectedAt,
            kind: kind,
            detailText: detailText,
            menuBarSummary: menuBarSummary,
            symbolName: symbolName(for: kind, phase: detection.phase),
            headline: headline,
            primaryActionTitle: primaryActionTitle,
            primaryActionEnabled: detection.phase == .endSuggestion
                || !detection.requiresCalendarChoice
                || detection.calendarEvent != nil,
            secondaryActionTitle: secondaryActionTitle,
            noteID: detection.calendarEvent?.id,
            candidateOptions: candidateOptions,
            selectedCandidateID: detection.calendarEvent?.id
        )
    }

    private static func symbolName(
        for kind: MeetingDetectionPromptState.Kind,
        phase: PendingMeetingDetection.Phase
    ) -> String {
        if phase == .endSuggestion {
            return kind == .prompt ? "stop.circle.fill" : "stop.circle"
        }

        switch kind {
        case .prompt:
            return "dot.radiowaves.left.and.right"
        case .passiveSuggestion:
            return "bell.fill"
        }
    }

    private static func makeCandidateOption(from event: CalendarEvent) -> MeetingDetectionCandidateOption {
        let timeText = "\(event.startDate.formatted(date: .omitted, time: .shortened)) - \(event.endDate.formatted(date: .omitted, time: .shortened))"
        let attendeeText: String
        if event.attendees.isEmpty {
            attendeeText = "No attendee context"
        } else {
            attendeeText = event.attendees.map(\.name).joined(separator: ", ")
        }

        return MeetingDetectionCandidateOption(
            id: event.id,
            title: event.title,
            subtitle: "\(timeText) • \(attendeeText)"
        )
    }
}
