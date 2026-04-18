import Foundation
import OatmealCore

struct SessionControllerState: Equatable, Sendable, Identifiable {
    enum Kind: Equatable, Sendable {
        case active
        case processing
        case recent
    }

    enum Tone: Equatable, Sendable {
        case live
        case delayed
        case recovered
        case failed
        case neutral
    }

    struct SourceStatus: Equatable, Sendable, Identifiable {
        let id: String
        let title: String
        let label: String
        let detailText: String?
        let tone: Tone
    }

    let id: UUID
    let noteID: UUID
    let title: String
    let kind: Kind
    let healthLabel: String
    let captureLabel: String
    let detailText: String?
    let microphoneLabel: String
    let systemAudioLabel: String?
    let showsProcessingIndicator: Bool
    let processingLabel: String?
    let sourceStatuses: [SourceStatus]
    let tone: Tone
    let menuBarSymbolName: String
    let menuBarSummary: String
    let captureStartedAt: Date?
    let captureEndedAt: Date?
    let lastUpdatedAt: Date?
    let canStopCapture: Bool
    let canOpenTranscript: Bool
    let presentationIdentity: String
    let controllerStatusTitle: String
    let controllerStatusDetail: String?
    let controllerStatusSymbolName: String
    let primaryActionTitle: String
    let transcriptActionTitle: String
    let menuBarSectionTitle: String

    func elapsedText(referenceDate: Date = Date()) -> String? {
        guard let captureStartedAt else {
            return nil
        }

        let endDate = if canStopCapture {
            referenceDate
        } else {
            captureEndedAt ?? referenceDate
        }

        let duration = max(endDate.timeIntervalSince(captureStartedAt), 0)
        return Self.elapsedFormatter.string(from: duration)
    }

    var compactStatusLine: String {
        if let detailText, !detailText.isEmpty {
            return detailText
        }
        return menuBarSummary
    }

    func lifecycleTimestampText(referenceDate: Date = Date()) -> String? {
        let anchorDate: Date?
        let prefix: String

        if kind == .processing, let captureEndedAt {
            anchorDate = captureEndedAt
            prefix = "Stopped"
        } else {
            switch tone {
            case .recovered:
                anchorDate = lastUpdatedAt ?? captureStartedAt
                prefix = "Recovered"
            case .failed:
                anchorDate = lastUpdatedAt ?? captureEndedAt ?? captureStartedAt
                prefix = "Interrupted"
            case .delayed:
                anchorDate = lastUpdatedAt ?? captureStartedAt
                prefix = "Updated"
            case .live:
                anchorDate = captureStartedAt
                prefix = "Started"
            case .neutral:
                anchorDate = lastUpdatedAt ?? captureEndedAt ?? captureStartedAt
                prefix = "Updated"
            }
        }

        guard let anchorDate else {
            return nil
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "\(prefix) \(formatter.localizedString(for: anchorDate, relativeTo: referenceDate))"
    }

    private static let elapsedFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter
    }()
}

enum SessionControllerAdapter {
    private static let recentCompletionWindow: TimeInterval = 15 * 60

    static func state(for note: MeetingNote?) -> SessionControllerState? {
        controllerState(for: note)
    }

    static func state(
        for notes: [MeetingNote],
        selectedNoteID: MeetingNote.ID?
    ) -> SessionControllerState? {
        controllerState(for: notes, selectedNoteID: selectedNoteID)
    }

    static func controllerState(for note: MeetingNote?) -> SessionControllerState? {
        state(for: note, referenceDate: Date(), includesRecentCompletion: false)
    }

    static func menuBarState(for note: MeetingNote?, referenceDate: Date = Date()) -> SessionControllerState? {
        state(for: note, referenceDate: referenceDate, includesRecentCompletion: true)
    }

    private static func state(
        for note: MeetingNote?,
        referenceDate: Date,
        includesRecentCompletion: Bool
    ) -> SessionControllerState? {
        guard let note else {
            return nil
        }

        let kind = kind(for: note, referenceDate: referenceDate, includesRecentCompletion: includesRecentCompletion)
        guard let kind else {
            return nil
        }

        let sourceStatuses = makeSourceStatuses(for: note)
        let tone = tone(for: note.liveSessionState.status, kind: kind)
        let processingLabel = kind == .processing ? processingLabel(for: note.processingState) : nil
        let detailText = detailText(for: note, kind: kind, processingLabel: processingLabel)

        return SessionControllerState(
            id: note.id,
            noteID: note.id,
            title: note.title,
            kind: kind,
            healthLabel: note.liveSessionState.status.displayLabel,
            captureLabel: captureLabel(for: note.captureState),
            detailText: detailText,
            microphoneLabel: note.liveSessionState.microphoneSource.status.displayLabel,
            systemAudioLabel: note.liveSessionState.systemAudioSource.status == .notRequired
                ? nil
                : note.liveSessionState.systemAudioSource.status.displayLabel,
            showsProcessingIndicator: kind == .processing,
            processingLabel: processingLabel,
            sourceStatuses: sourceStatuses,
            tone: tone,
            menuBarSymbolName: menuBarSymbolName(for: tone, kind: kind),
            menuBarSummary: menuBarSummary(
                for: note,
                kind: kind,
                detailText: detailText,
                processingLabel: processingLabel
            ),
            captureStartedAt: note.captureState.startedAt,
            captureEndedAt: note.captureState.endedAt,
            lastUpdatedAt: note.liveSessionState.lastUpdatedAt ?? note.processingState.startedAt ?? note.updatedAt,
            canStopCapture: note.captureState.isActive,
            canOpenTranscript: note.captureState.isActive
                || note.liveSessionState.hasPreviewEntries
                || !note.transcriptSegments.isEmpty,
            presentationIdentity: presentationIdentity(for: note, kind: kind),
            controllerStatusTitle: controllerStatusTitle(for: note, kind: kind),
            controllerStatusDetail: controllerStatusDetail(for: note, kind: kind, processingLabel: processingLabel),
            controllerStatusSymbolName: controllerStatusSymbolName(for: note, kind: kind),
            primaryActionTitle: primaryActionTitle(for: kind),
            transcriptActionTitle: transcriptActionTitle(for: note, kind: kind),
            menuBarSectionTitle: menuBarSectionTitle(for: kind)
        )
    }

    static func controllerState(
        for notes: [MeetingNote],
        selectedNoteID: MeetingNote.ID?
    ) -> SessionControllerState? {
        rankedState(
            for: notes,
            selectedNoteID: selectedNoteID,
            referenceDate: Date(),
            includesRecentCompletion: false
        )
    }

    static func menuBarState(
        for notes: [MeetingNote],
        selectedNoteID: MeetingNote.ID?,
        referenceDate: Date = Date()
    ) -> SessionControllerState? {
        rankedState(
            for: notes,
            selectedNoteID: selectedNoteID,
            referenceDate: referenceDate,
            includesRecentCompletion: true
        )
    }

    private static func rankedState(
        for notes: [MeetingNote],
        selectedNoteID: MeetingNote.ID?,
        referenceDate: Date,
        includesRecentCompletion: Bool
    ) -> SessionControllerState? {
        let rankedStates = notes
            .compactMap { note -> (MeetingNote, SessionControllerState)? in
                guard let state = state(
                    for: note,
                    referenceDate: referenceDate,
                    includesRecentCompletion: includesRecentCompletion
                ) else {
                    return nil
                }
                return (note, state)
            }
            .sorted(by: isHigherPriority)

        guard let highestPriority = rankedStates.first else {
            return nil
        }

        if let selectedNoteID,
           let selected = rankedStates.first(where: { $0.0.id == selectedNoteID }) {
            let selectedRank = rank(for: selected.0, state: selected.1)
            let highestRank = rank(for: highestPriority.0, state: highestPriority.1)
            if selectedRank <= highestRank {
                return selected.1
            }
        }

        return highestPriority.1
    }

    private static func isHigherPriority(
        lhs: (MeetingNote, SessionControllerState),
        rhs: (MeetingNote, SessionControllerState)
    ) -> Bool {
        let lhsRank = rank(for: lhs.0, state: lhs.1)
        let rhsRank = rank(for: rhs.0, state: rhs.1)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }

        let lhsDate = priorityDate(for: lhs.0)
        let rhsDate = priorityDate(for: rhs.0)
        return lhsDate > rhsDate
    }

    private static func rank(for note: MeetingNote, state: SessionControllerState) -> Int {
        if note.captureState.isActive {
            return 0
        }

        switch note.liveSessionState.status {
        case .failed:
            return 1
        case .delayed:
            return 2
        case .recovered:
            return 3
        case .completed, .idle, .live:
            break
        }

        if state.kind == .processing {
            return 4
        }

        if state.kind == .recent {
            return 5
        }

        return 6
    }

    private static func priorityDate(for note: MeetingNote) -> Date {
        note.captureState.startedAt
            ?? note.processingState.startedAt
            ?? note.processingState.queuedAt
            ?? note.liveSessionState.lastUpdatedAt
            ?? note.updatedAt
    }

    private static func presentationIdentity(
        for note: MeetingNote,
        kind: SessionControllerState.Kind
    ) -> String {
        let anchorDate = note.captureState.startedAt
            ?? note.captureState.endedAt
            ?? note.processingState.startedAt
            ?? note.processingState.queuedAt
            ?? note.liveSessionState.lastUpdatedAt
            ?? note.updatedAt
        let timestamp = Int(anchorDate.timeIntervalSince1970)
        return "\(note.id.uuidString)#\(kind)#\(timestamp)"
    }

    private static func kind(
        for note: MeetingNote,
        referenceDate: Date,
        includesRecentCompletion: Bool
    ) -> SessionControllerState.Kind? {
        if note.captureState.isActive
            || note.liveSessionState.status == .delayed
            || note.liveSessionState.status == .recovered
            || note.liveSessionState.status == .failed {
            return .active
        }

        if note.processingState.isActive {
            return .processing
        }

        if includesRecentCompletion, isRecentlyCompleted(note, referenceDate: referenceDate) {
            return .recent
        }

        return nil
    }

    private static func isRecentlyCompleted(_ note: MeetingNote, referenceDate: Date) -> Bool {
        guard note.generationStatus == .succeeded || note.processingState.stage == .complete else {
            return false
        }

        let completedAt = note.processingState.completedAt
            ?? note.generationHistory.last?.completedAt
            ?? note.transcriptionHistory.last?.completedAt
            ?? note.captureState.endedAt
            ?? note.updatedAt
        return max(referenceDate.timeIntervalSince(completedAt), 0) <= recentCompletionWindow
    }

    private static func captureLabel(for captureState: CaptureSessionState) -> String {
        switch captureState.phase {
        case .capturing:
            return "Recording"
        case .paused:
            return "Paused"
        case .failed:
            return "Interrupted"
        case .complete:
            return "Stopped"
        case .ready:
            return "Ready"
        }
    }

    private static func processingLabel(for state: PostCaptureProcessingState) -> String {
        let stage = switch state.stage {
        case .idle:
            "Idle"
        case .transcription:
            "Transcription"
        case .generation:
            "Enhanced Note"
        case .complete:
            "Complete"
        }

        let status = switch state.status {
        case .idle:
            "Idle"
        case .queued:
            "Queued"
        case .running:
            "Running"
        case .completed:
            "Completed"
        case .failed:
            "Failed"
        }

        return "\(stage) \(status)"
    }

    private static func detailText(
        for note: MeetingNote,
        kind: SessionControllerState.Kind,
        processingLabel: String?
    ) -> String? {
        if let statusMessage = nonBlank(note.liveSessionState.statusMessage) {
            return statusMessage
        }

        if kind == .processing {
            if let errorMessage = nonBlank(note.processingState.errorMessage) {
                return errorMessage
            }
            return processingLabel ?? "Oatmeal is finishing this note in the background."
        }

        if kind == .recent {
            return "Oatmeal finished this note recently. Open it from the menu bar whenever you are ready."
        }

        switch note.liveSessionState.status {
        case .live:
            return "Oatmeal is recording locally and keeping the lightweight session controller in sync."
        case .delayed:
            return "Oatmeal kept the recording safe and is catching up on live transcript work."
        case .recovered:
            return "Oatmeal recovered this session after a disruption and kept the live state intact."
        case .failed:
            return nonBlank(note.captureState.failureReason)
                ?? "Capture needs attention before live updates can continue."
        case .completed:
            return "Capture is complete and Oatmeal is finishing the durable note in the background."
        case .idle:
            return nil
        }
    }

    private static func makeSourceStatuses(for note: MeetingNote) -> [SessionControllerState.SourceStatus] {
        var statuses: [SessionControllerState.SourceStatus] = [
            SessionControllerState.SourceStatus(
                id: LiveCaptureSourceID.microphone.rawValue,
                title: LiveCaptureSourceID.microphone.displayLabel,
                label: note.liveSessionState.microphoneSource.status.displayLabel,
                detailText: nonBlank(note.liveSessionState.microphoneSource.statusMessage),
                tone: tone(for: note.liveSessionState.microphoneSource.status)
            )
        ]

        if note.liveSessionState.systemAudioSource.status != .notRequired {
            statuses.append(
                SessionControllerState.SourceStatus(
                    id: LiveCaptureSourceID.systemAudio.rawValue,
                    title: LiveCaptureSourceID.systemAudio.displayLabel,
                    label: note.liveSessionState.systemAudioSource.status.displayLabel,
                    detailText: nonBlank(note.liveSessionState.systemAudioSource.statusMessage),
                    tone: tone(for: note.liveSessionState.systemAudioSource.status)
                )
            )
        }

        return statuses
    }

    private static func tone(
        for status: LiveSessionStatus,
        kind: SessionControllerState.Kind
    ) -> SessionControllerState.Tone {
        switch status {
        case .live:
            return .live
        case .delayed:
            return .delayed
        case .recovered:
            return .recovered
        case .failed:
            return .failed
        case .completed, .idle:
            return kind == .active ? .live : .neutral
        }
    }

    private static func tone(for status: LiveCaptureSourceStatus) -> SessionControllerState.Tone {
        switch status {
        case .active, .idle, .notRequired:
            return .live
        case .delayed:
            return .delayed
        case .recovered:
            return .recovered
        case .failed:
            return .failed
        }
    }

    private static func menuBarSymbolName(
        for tone: SessionControllerState.Tone,
        kind: SessionControllerState.Kind
    ) -> String {
        if kind == .processing {
            return "gearshape.2.fill"
        }
        if kind == .recent {
            return "checkmark.circle.fill"
        }

        switch tone {
        case .live:
            return "record.circle.fill"
        case .delayed:
            return "clock.arrow.circlepath"
        case .recovered:
            return "arrow.clockwise.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .neutral:
            return "circle.fill"
        }
    }

    private static func menuBarSummary(
        for note: MeetingNote,
        kind: SessionControllerState.Kind,
        detailText: String?,
        processingLabel: String?
    ) -> String {
        if kind == .processing {
            return processingLabel ?? "Background processing is still running."
        }

        if kind == .recent {
            return "The enhanced note is ready to review in Oatmeal."
        }

        if let detailText {
            return detailText
        }

        if note.captureState.isActive {
            return "Recording is active."
        }

        return "\(note.liveSessionState.status.displayLabel) • \(captureLabel(for: note.captureState))"
    }

    private static func controllerStatusTitle(
        for note: MeetingNote,
        kind: SessionControllerState.Kind
    ) -> String {
        if kind == .processing {
            switch note.processingState.stage {
            case .transcription:
                return note.processingState.status == .failed
                    ? "Transcript needs retry"
                    : "Finishing transcript"
            case .generation:
                return note.processingState.status == .failed
                    ? "Enhanced note needs retry"
                    : "Writing enhanced note"
            case .complete:
                return "Ready to review"
            case .idle:
                return "Finishing note"
            }
        }

        if kind == .recent {
            return "Ready to review"
        }

        switch note.liveSessionState.status {
        case .live:
            return "Recording now"
        case .delayed:
            return "Catching up live transcript"
        case .recovered:
            return "Recovered session"
        case .failed:
            return "Capture interrupted"
        case .completed:
            return "Capture finished"
        case .idle:
            return "Session ready"
        }
    }

    private static func controllerStatusDetail(
        for note: MeetingNote,
        kind: SessionControllerState.Kind,
        processingLabel: String?
    ) -> String? {
        if kind == .processing {
            if let errorMessage = nonBlank(note.processingState.errorMessage) {
                return errorMessage
            }

            switch note.processingState.stage {
            case .transcription:
                return "Recording is safe. Oatmeal is still turning it into a durable transcript."
            case .generation:
                return "Transcript is ready. Oatmeal is shaping the enhanced note in the background."
            case .complete:
                return "Background work is complete and the note is ready to review."
            case .idle:
                return processingLabel ?? "Oatmeal is finishing this note in the background."
            }
        }

        if kind == .recent {
            return "Oatmeal finished the enhanced note recently. Open the main app or jump into the transcript from here."
        }

        if let statusMessage = nonBlank(note.liveSessionState.statusMessage) {
            return statusMessage
        }

        return detailText(for: note, kind: kind, processingLabel: processingLabel)
    }

    private static func controllerStatusSymbolName(
        for note: MeetingNote,
        kind: SessionControllerState.Kind
    ) -> String {
        if kind == .processing {
            switch note.processingState.stage {
            case .transcription:
                return note.processingState.status == .failed
                    ? "exclamationmark.bubble.fill"
                    : "waveform.badge.magnifyingglass"
            case .generation:
                return note.processingState.status == .failed
                    ? "exclamationmark.text.bubble.fill"
                    : "doc.text.magnifyingglass"
            case .complete:
                return "checkmark.circle.fill"
            case .idle:
                return "gearshape.2.fill"
            }
        }

        if kind == .recent {
            return "checkmark.circle.fill"
        }

        switch note.liveSessionState.status {
        case .live:
            return "record.circle.fill"
        case .delayed:
            return "clock.arrow.circlepath"
        case .recovered:
            return "arrow.clockwise.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .idle:
            return "circle.fill"
        }
    }

    private static func primaryActionTitle(for kind: SessionControllerState.Kind) -> String {
        switch kind {
        case .active:
            return "Open Note"
        case .processing:
            return "Open Note"
        case .recent:
            return "Review Note"
        }
    }

    private static func transcriptActionTitle(
        for note: MeetingNote,
        kind: SessionControllerState.Kind
    ) -> String {
        if kind == .active, note.captureState.isActive {
            return "Live Transcript"
        }
        return "Transcript"
    }

    private static func menuBarSectionTitle(for kind: SessionControllerState.Kind) -> String {
        switch kind {
        case .active:
            return "Active Session"
        case .processing:
            return "Finishing Up"
        case .recent:
            return "Recently Completed"
        }
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
