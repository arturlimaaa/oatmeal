import Foundation

public struct MeetingParticipant: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var email: String?
    public var isOrganizer: Bool

    public init(id: UUID = UUID(), name: String, email: String? = nil, isOrganizer: Bool = false) {
        self.id = id
        self.name = name
        self.email = email
        self.isOrganizer = isOrganizer
    }
}

public enum CalendarEventSource: String, Codable, Equatable, Sendable {
    case googleCalendar
    case microsoftCalendar
    case local
    case manual
}

public enum CalendarEventKind: String, Codable, Equatable, Sendable {
    case meeting
    case focusBlock
    case allDayPlaceholder
    case adHoc
}

public enum AttendanceStatus: String, Codable, Equatable, Sendable {
    case unknown
    case invited
    case accepted
    case tentative
    case declined
}

public struct CalendarEvent: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var attendees: [MeetingParticipant]
    public var conferencingURL: URL?
    public var source: CalendarEventSource
    public var kind: CalendarEventKind
    public var attendanceStatus: AttendanceStatus
    public var location: String?
    public var notes: String?
    public var timezoneIdentifier: String?

    public init(
        id: UUID = UUID(),
        title: String,
        startDate: Date,
        endDate: Date,
        attendees: [MeetingParticipant] = [],
        conferencingURL: URL? = nil,
        source: CalendarEventSource,
        kind: CalendarEventKind = .meeting,
        attendanceStatus: AttendanceStatus = .unknown,
        location: String? = nil,
        notes: String? = nil,
        timezoneIdentifier: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.attendees = attendees
        self.conferencingURL = conferencingURL
        self.source = source
        self.kind = kind
        self.attendanceStatus = attendanceStatus
        self.location = location
        self.notes = notes
        self.timezoneIdentifier = timezoneIdentifier
    }

    public var isRelevantForHomeScreen: Bool {
        kind == .meeting && attendanceStatus != .declined
    }

    public var isUpcoming: Bool {
        endDate > Date()
    }
}

public struct NoteOrigin: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case calendarEvent
        case quickNote
    }

    public var kind: Kind
    public var createdAt: Date
    public var calendarEventID: UUID?

    public init(kind: Kind, createdAt: Date = Date(), calendarEventID: UUID? = nil) {
        self.kind = kind
        self.createdAt = createdAt
        self.calendarEventID = calendarEventID
    }

    public static func calendarEvent(_ eventID: UUID, createdAt: Date = Date()) -> Self {
        Self(kind: .calendarEvent, createdAt: createdAt, calendarEventID: eventID)
    }

    public static func quickNote(createdAt: Date = Date()) -> Self {
        Self(kind: .quickNote, createdAt: createdAt, calendarEventID: nil)
    }
}

public struct TranscriptSegment: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var startTime: Date?
    public var endTime: Date?
    public var speakerName: String?
    public var text: String
    public var confidence: Double?

    public init(
        id: UUID = UUID(),
        startTime: Date? = nil,
        endTime: Date? = nil,
        speakerName: String? = nil,
        text: String,
        confidence: Double? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.speakerName = speakerName
        self.text = text
        self.confidence = confidence
    }
}

public enum LiveTranscriptEntryKind: String, Codable, Equatable, Hashable, Sendable {
    case system
    case transcript
}

public struct LiveTranscriptEntry: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var createdAt: Date
    public var kind: LiveTranscriptEntryKind
    public var speakerName: String?
    public var text: String

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        kind: LiveTranscriptEntryKind = .transcript,
        speakerName: String? = nil,
        text: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.speakerName = speakerName
        self.text = text
    }
}

public enum ActionItemStatus: String, Codable, Equatable, Sendable {
    case open
    case done
    case delegated
}

public struct ActionItem: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var text: String
    public var assignee: String?
    public var dueDate: Date?
    public var status: ActionItemStatus

    public init(
        id: UUID = UUID(),
        text: String,
        assignee: String? = nil,
        dueDate: Date? = nil,
        status: ActionItemStatus = .open
    ) {
        self.id = id
        self.text = text
        self.assignee = assignee
        self.dueDate = dueDate
        self.status = status
    }
}

public struct SourceCitation: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var transcriptSegmentIDs: [UUID]
    public var excerpt: String

    public init(id: UUID = UUID(), transcriptSegmentIDs: [UUID], excerpt: String) {
        self.id = id
        self.transcriptSegmentIDs = transcriptSegmentIDs
        self.excerpt = excerpt
    }
}

public enum NoteAssistantTurnStatus: String, Codable, Equatable, Sendable {
    case pending
    case completed
    case failed

    public var displayLabel: String {
        switch self {
        case .pending:
            "Generating"
        case .completed:
            "Ready"
        case .failed:
            "Failed"
        }
    }
}

public enum NoteAssistantTurnKind: String, Codable, Equatable, Sendable, CaseIterable {
    case prompt
    case followUpEmail
    case slackRecap

    public var displayLabel: String {
        switch self {
        case .prompt:
            "Prompt"
        case .followUpEmail:
            "Follow-up Email"
        case .slackRecap:
            "Slack Recap"
        }
    }

    public var isDraftingAction: Bool {
        self != .prompt
    }
}

public enum NoteAssistantCitationKind: String, Codable, Equatable, Sendable {
    case transcriptSegment
    case rawNotes
    case enhancedSummary
    case enhancedKeyPoint
    case enhancedDecision
    case enhancedRisk
    case enhancedActionItem
    case metadata

    public var displayLabel: String {
        switch self {
        case .transcriptSegment:
            "Transcript"
        case .rawNotes:
            "Raw notes"
        case .enhancedSummary:
            "Summary"
        case .enhancedKeyPoint:
            "Key point"
        case .enhancedDecision:
            "Decision"
        case .enhancedRisk:
            "Risk / question"
        case .enhancedActionItem:
            "Action item"
        case .metadata:
            "Meeting context"
        }
    }
}

public struct NoteAssistantCitation: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: NoteAssistantCitationKind
    public var label: String
    public var excerpt: String
    public var transcriptSegmentID: UUID?

    public init(
        id: UUID = UUID(),
        kind: NoteAssistantCitationKind,
        label: String,
        excerpt: String,
        transcriptSegmentID: UUID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.excerpt = excerpt
        self.transcriptSegmentID = transcriptSegmentID
    }
}

public struct NoteAssistantTurn: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: NoteAssistantTurnKind
    public var prompt: String
    public var response: String?
    public var citations: [NoteAssistantCitation]
    public var requestedAt: Date
    public var completedAt: Date?
    public var status: NoteAssistantTurnStatus
    public var failureMessage: String?

    public init(
        id: UUID = UUID(),
        kind: NoteAssistantTurnKind = .prompt,
        prompt: String,
        response: String? = nil,
        citations: [NoteAssistantCitation] = [],
        requestedAt: Date = Date(),
        completedAt: Date? = nil,
        status: NoteAssistantTurnStatus,
        failureMessage: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.prompt = prompt
        self.response = response
        self.citations = citations
        self.requestedAt = requestedAt
        self.completedAt = completedAt
        self.status = status
        self.failureMessage = failureMessage
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case prompt
        case response
        case citations
        case requestedAt
        case completedAt
        case status
        case failureMessage
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decodeIfPresent(NoteAssistantTurnKind.self, forKey: .kind) ?? .prompt
        prompt = try container.decode(String.self, forKey: .prompt)
        response = try container.decodeIfPresent(String.self, forKey: .response)
        citations = try container.decodeIfPresent([NoteAssistantCitation].self, forKey: .citations) ?? []
        requestedAt = try container.decode(Date.self, forKey: .requestedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        status = try container.decode(NoteAssistantTurnStatus.self, forKey: .status)
        failureMessage = try container.decodeIfPresent(String.self, forKey: .failureMessage)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(prompt, forKey: .prompt)
        try container.encodeIfPresent(response, forKey: .response)
        try container.encode(citations, forKey: .citations)
        try container.encode(requestedAt, forKey: .requestedAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(failureMessage, forKey: .failureMessage)
    }
}

public struct NoteAssistantThread: Codable, Equatable, Sendable {
    public var turns: [NoteAssistantTurn]
    public var updatedAt: Date?

    public init(
        turns: [NoteAssistantTurn] = [],
        updatedAt: Date? = nil
    ) {
        self.turns = turns
        self.updatedAt = updatedAt
    }

    public static let empty = NoteAssistantThread()

    public var hasConversation: Bool {
        !turns.isEmpty
    }

    public var hasPendingTurn: Bool {
        turns.contains(where: { $0.status == .pending })
    }

    @discardableResult
    public mutating func submitPrompt(
        _ prompt: String,
        kind: NoteAssistantTurnKind = .prompt,
        at date: Date = Date()
    ) -> UUID {
        let turn = NoteAssistantTurn(
            kind: kind,
            prompt: prompt,
            requestedAt: date,
            status: .pending
        )
        turns.append(turn)
        updatedAt = date
        return turn.id
    }

    @discardableResult
    public mutating func completeTurn(
        id: UUID,
        response: String,
        citations: [NoteAssistantCitation] = [],
        at date: Date = Date()
    ) -> Bool {
        guard let index = turns.firstIndex(where: { $0.id == id }) else {
            return false
        }

        turns[index].response = response
        turns[index].citations = citations
        turns[index].completedAt = date
        turns[index].status = .completed
        turns[index].failureMessage = nil
        updatedAt = date
        return true
    }

    @discardableResult
    public mutating func failTurn(
        id: UUID,
        message: String,
        at date: Date = Date()
    ) -> Bool {
        guard let index = turns.firstIndex(where: { $0.id == id }) else {
            return false
        }

        turns[index].completedAt = date
        turns[index].status = .failed
        turns[index].failureMessage = message
        turns[index].citations = []
        updatedAt = date
        return true
    }

    @discardableResult
    public mutating func failPendingTurnsForRelaunchRecovery(
        message: String,
        at date: Date = Date()
    ) -> Bool {
        var didChange = false

        for index in turns.indices where turns[index].status == .pending {
            turns[index].completedAt = date
            turns[index].status = .failed
            turns[index].failureMessage = message
            didChange = true
        }

        if didChange {
            updatedAt = date
        }

        return didChange
    }
}

public struct EnhancedNote: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var generatedAt: Date
    public var templateID: UUID?
    public var summary: String
    public var keyDiscussionPoints: [String]
    public var decisions: [String]
    public var risksOrOpenQuestions: [String]
    public var actionItems: [ActionItem]
    public var citations: [SourceCitation]

    public init(
        id: UUID = UUID(),
        generatedAt: Date = Date(),
        templateID: UUID? = nil,
        summary: String,
        keyDiscussionPoints: [String] = [],
        decisions: [String] = [],
        risksOrOpenQuestions: [String] = [],
        actionItems: [ActionItem] = [],
        citations: [SourceCitation] = []
    ) {
        self.id = id
        self.generatedAt = generatedAt
        self.templateID = templateID
        self.summary = summary
        self.keyDiscussionPoints = keyDiscussionPoints
        self.decisions = decisions
        self.risksOrOpenQuestions = risksOrOpenQuestions
        self.actionItems = actionItems
        self.citations = citations
    }
}

public enum NoteGenerationStatus: String, Codable, Equatable, Sendable {
    case idle
    case pending
    case succeeded
    case failed
}

public enum NoteTranscriptionStatus: String, Codable, Equatable, Sendable {
    case idle
    case pending
    case succeeded
    case failed
}

public enum NoteTranscriptionBackend: String, Codable, Equatable, Sendable {
    case whisperCPPCLI
    case appleSpeech
    case mock
}

public enum NoteTranscriptionExecutionKind: String, Codable, Equatable, Sendable {
    case local
    case systemService
    case placeholder
}

public struct NoteTranscriptionAttempt: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var backend: NoteTranscriptionBackend
    public var executionKind: NoteTranscriptionExecutionKind
    public var requestedAt: Date
    public var completedAt: Date?
    public var status: NoteTranscriptionStatus
    public var segmentCount: Int
    public var warningMessages: [String]
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        backend: NoteTranscriptionBackend,
        executionKind: NoteTranscriptionExecutionKind,
        requestedAt: Date = Date(),
        completedAt: Date? = nil,
        status: NoteTranscriptionStatus,
        segmentCount: Int = 0,
        warningMessages: [String] = [],
        errorMessage: String? = nil
    ) {
        self.id = id
        self.backend = backend
        self.executionKind = executionKind
        self.requestedAt = requestedAt
        self.completedAt = completedAt
        self.status = status
        self.segmentCount = segmentCount
        self.warningMessages = warningMessages
        self.errorMessage = errorMessage
    }
}

public struct NoteGenerationAttempt: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var templateID: UUID?
    public var requestedAt: Date
    public var completedAt: Date?
    public var status: NoteGenerationStatus
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        templateID: UUID? = nil,
        requestedAt: Date = Date(),
        completedAt: Date? = nil,
        status: NoteGenerationStatus,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.templateID = templateID
        self.requestedAt = requestedAt
        self.completedAt = completedAt
        self.status = status
        self.errorMessage = errorMessage
    }
}

public enum PostCaptureProcessingStage: String, Codable, Equatable, Sendable {
    case idle
    case transcription
    case generation
    case complete
}

public enum PostCaptureProcessingStatus: String, Codable, Equatable, Sendable {
    case idle
    case queued
    case running
    case completed
    case failed
}

public struct PostCaptureProcessingState: Codable, Equatable, Sendable {
    public var stage: PostCaptureProcessingStage
    public var status: PostCaptureProcessingStatus
    public var queuedAt: Date?
    public var startedAt: Date?
    public var completedAt: Date?
    public var errorMessage: String?

    public init(
        stage: PostCaptureProcessingStage = .idle,
        status: PostCaptureProcessingStatus = .idle,
        queuedAt: Date? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        errorMessage: String? = nil
    ) {
        self.stage = stage
        self.status = status
        self.queuedAt = queuedAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.errorMessage = errorMessage
    }

    public static let idle = PostCaptureProcessingState()

    public var needsRelaunchRecovery: Bool {
        status == .queued || status == .running
    }

    public var isActive: Bool {
        needsRelaunchRecovery
    }

    public mutating func queue(_ stage: PostCaptureProcessingStage, at date: Date = Date()) {
        self.stage = stage
        status = .queued
        queuedAt = date
        startedAt = nil
        completedAt = nil
        errorMessage = nil
    }

    public mutating func start(_ stage: PostCaptureProcessingStage, at date: Date = Date()) {
        self.stage = stage
        status = .running
        if queuedAt == nil {
            queuedAt = date
        }
        startedAt = date
        completedAt = nil
        errorMessage = nil
    }

    public mutating func complete(stage: PostCaptureProcessingStage, at date: Date = Date()) {
        self.stage = stage
        status = .completed
        if queuedAt == nil {
            queuedAt = date
        }
        if startedAt == nil {
            startedAt = date
        }
        completedAt = date
        errorMessage = nil
    }

    public mutating func fail(stage: PostCaptureProcessingStage, message: String, at date: Date = Date()) {
        self.stage = stage
        status = .failed
        if queuedAt == nil {
            queuedAt = date
        }
        completedAt = date
        errorMessage = message
    }

    public mutating func prepareForRelaunchRecovery(at date: Date = Date()) {
        guard needsRelaunchRecovery else { return }
        status = .queued
        queuedAt = queuedAt ?? date
        startedAt = nil
        completedAt = nil
        errorMessage = nil
    }
}

public enum LiveSessionStatus: String, Codable, Equatable, Sendable {
    case idle
    case live
    case delayed
    case recovered
    case completed
    case failed

    public var displayLabel: String {
        switch self {
        case .idle:
            "Idle"
        case .live:
            "Live"
        case .delayed:
            "Delayed"
        case .recovered:
            "Recovered"
        case .completed:
            "Completed"
        case .failed:
            "Failed"
        }
    }
}

public enum LiveCaptureSourceID: String, Codable, Equatable, Sendable {
    case microphone
    case systemAudio

    public var displayLabel: String {
        switch self {
        case .microphone:
            "Microphone"
        case .systemAudio:
            "System Audio"
        }
    }
}

public enum LiveCaptureSourceStatus: String, Codable, Equatable, Sendable {
    case idle
    case active
    case delayed
    case recovered
    case failed
    case notRequired

    public var displayLabel: String {
        switch self {
        case .idle:
            "Idle"
        case .active:
            "Live"
        case .delayed:
            "Delayed"
        case .recovered:
            "Recovered"
        case .failed:
            "Failed"
        case .notRequired:
            "Not Needed"
        }
    }
}

public struct LiveCaptureSourceState: Codable, Equatable, Sendable {
    public var status: LiveCaptureSourceStatus
    public var statusMessage: String?
    public var lastUpdatedAt: Date?

    public init(
        status: LiveCaptureSourceStatus = .idle,
        statusMessage: String? = nil,
        lastUpdatedAt: Date? = nil
    ) {
        self.status = status
        self.statusMessage = statusMessage
        self.lastUpdatedAt = lastUpdatedAt
    }

    public static let idle = LiveCaptureSourceState()

    public mutating func reset(isRequired: Bool, at date: Date) {
        status = isRequired ? .active : .notRequired
        statusMessage = isRequired ? "Connected" : "Not required for this note."
        lastUpdatedAt = date
    }

    public mutating func update(
        status: LiveCaptureSourceStatus,
        message: String? = nil,
        at date: Date = Date()
    ) {
        self.status = status
        if let message {
            statusMessage = message
        }
        lastUpdatedAt = date
    }
}

public struct LiveSessionMetrics: Codable, Equatable, Sendable {
    public var recoveryCount: Int
    public var interruptionCount: Int
    public var microphoneLastActivityAt: Date?
    public var systemAudioLastActivityAt: Date?
    public var lastMergedLiveChunkAt: Date?
    public var lastMergedChunkLatency: TimeInterval?
    public var pendingChunkCount: Int
    public var peakPendingChunkCount: Int
    public var oldestPendingChunkStartedAt: Date?

    public init(
        recoveryCount: Int = 0,
        interruptionCount: Int = 0,
        microphoneLastActivityAt: Date? = nil,
        systemAudioLastActivityAt: Date? = nil,
        lastMergedLiveChunkAt: Date? = nil,
        lastMergedChunkLatency: TimeInterval? = nil,
        pendingChunkCount: Int = 0,
        peakPendingChunkCount: Int = 0,
        oldestPendingChunkStartedAt: Date? = nil
    ) {
        self.recoveryCount = recoveryCount
        self.interruptionCount = interruptionCount
        self.microphoneLastActivityAt = microphoneLastActivityAt
        self.systemAudioLastActivityAt = systemAudioLastActivityAt
        self.lastMergedLiveChunkAt = lastMergedLiveChunkAt
        self.lastMergedChunkLatency = lastMergedChunkLatency
        self.pendingChunkCount = pendingChunkCount
        self.peakPendingChunkCount = peakPendingChunkCount
        self.oldestPendingChunkStartedAt = oldestPendingChunkStartedAt
    }

    public static let empty = LiveSessionMetrics()

    public mutating func reset(at date: Date, tracksSystemAudio: Bool) {
        recoveryCount = 0
        interruptionCount = 0
        microphoneLastActivityAt = date
        systemAudioLastActivityAt = tracksSystemAudio ? date : nil
        lastMergedLiveChunkAt = nil
        lastMergedChunkLatency = nil
        pendingChunkCount = 0
        peakPendingChunkCount = 0
        oldestPendingChunkStartedAt = nil
    }

    @discardableResult
    public mutating func recordRecovery() -> Bool {
        recoveryCount += 1
        return true
    }

    @discardableResult
    public mutating func recordInterruption() -> Bool {
        interruptionCount += 1
        return true
    }

    @discardableResult
    public mutating func recordSourceActivity(
        _ source: LiveCaptureSourceID,
        at date: Date
    ) -> Bool {
        switch source {
        case .microphone:
            return Self.updateDate(&microphoneLastActivityAt, with: date)
        case .systemAudio:
            return Self.updateDate(&systemAudioLastActivityAt, with: date)
        }
    }

    @discardableResult
    public mutating func registerMergedLiveChunk(
        mergedAt date: Date,
        sourceEndedAt: Date?
    ) -> Bool {
        var didChange = Self.updateDate(&lastMergedLiveChunkAt, with: date)
        let latency = sourceEndedAt.map { max(date.timeIntervalSince($0), 0) }
        if lastMergedChunkLatency != latency {
            lastMergedChunkLatency = latency
            didChange = true
        }
        return didChange
    }

    @discardableResult
    public mutating func updateBacklog(
        pendingChunkCount: Int,
        oldestPendingChunkStartedAt: Date?
    ) -> Bool {
        let normalizedCount = max(pendingChunkCount, 0)
        var didChange = false

        if self.pendingChunkCount != normalizedCount {
            self.pendingChunkCount = normalizedCount
            didChange = true
        }

        if peakPendingChunkCount < normalizedCount {
            peakPendingChunkCount = normalizedCount
            didChange = true
        }

        if self.oldestPendingChunkStartedAt != oldestPendingChunkStartedAt {
            self.oldestPendingChunkStartedAt = oldestPendingChunkStartedAt
            didChange = true
        }

        return didChange
    }

    @discardableResult
    private static func updateDate(_ target: inout Date?, with date: Date) -> Bool {
        if let target, target >= date {
            return false
        }

        target = date
        return true
    }

    private enum CodingKeys: String, CodingKey {
        case recoveryCount
        case interruptionCount
        case microphoneLastActivityAt
        case systemAudioLastActivityAt
        case legacyLastMicrophoneActivityAt = "lastMicrophoneActivityAt"
        case legacyLastSystemAudioActivityAt = "lastSystemAudioActivityAt"
        case lastMergedLiveChunkAt
        case lastMergedChunkLatency
        case pendingChunkCount
        case peakPendingChunkCount
        case oldestPendingChunkStartedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recoveryCount = try container.decodeIfPresent(Int.self, forKey: .recoveryCount) ?? 0
        interruptionCount = try container.decodeIfPresent(Int.self, forKey: .interruptionCount) ?? 0
        microphoneLastActivityAt = try container.decodeIfPresent(Date.self, forKey: .microphoneLastActivityAt)
            ?? container.decodeIfPresent(Date.self, forKey: .legacyLastMicrophoneActivityAt)
        systemAudioLastActivityAt = try container.decodeIfPresent(Date.self, forKey: .systemAudioLastActivityAt)
            ?? container.decodeIfPresent(Date.self, forKey: .legacyLastSystemAudioActivityAt)
        lastMergedLiveChunkAt = try container.decodeIfPresent(Date.self, forKey: .lastMergedLiveChunkAt)
        lastMergedChunkLatency = try container.decodeIfPresent(TimeInterval.self, forKey: .lastMergedChunkLatency)
        pendingChunkCount = try container.decodeIfPresent(Int.self, forKey: .pendingChunkCount) ?? 0
        peakPendingChunkCount = try container.decodeIfPresent(Int.self, forKey: .peakPendingChunkCount) ?? pendingChunkCount
        oldestPendingChunkStartedAt = try container.decodeIfPresent(Date.self, forKey: .oldestPendingChunkStartedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(recoveryCount, forKey: .recoveryCount)
        try container.encode(interruptionCount, forKey: .interruptionCount)
        try container.encodeIfPresent(microphoneLastActivityAt, forKey: .microphoneLastActivityAt)
        try container.encodeIfPresent(systemAudioLastActivityAt, forKey: .systemAudioLastActivityAt)
        try container.encodeIfPresent(lastMergedLiveChunkAt, forKey: .lastMergedLiveChunkAt)
        try container.encodeIfPresent(lastMergedChunkLatency, forKey: .lastMergedChunkLatency)
        try container.encode(pendingChunkCount, forKey: .pendingChunkCount)
        try container.encode(peakPendingChunkCount, forKey: .peakPendingChunkCount)
        try container.encodeIfPresent(oldestPendingChunkStartedAt, forKey: .oldestPendingChunkStartedAt)
    }
}

public struct LiveSessionState: Codable, Equatable, Sendable {
    public var status: LiveSessionStatus
    public var isTranscriptPanelPresented: Bool
    public var previewEntries: [LiveTranscriptEntry]
    public var processedChunkIDs: [String]
    public var metrics: LiveSessionMetrics
    public var microphoneSource: LiveCaptureSourceState
    public var systemAudioSource: LiveCaptureSourceState
    public var statusMessage: String?
    public var lastUpdatedAt: Date?
    public var lastRecoveryAt: Date?

    public init(
        status: LiveSessionStatus = .idle,
        isTranscriptPanelPresented: Bool = false,
        previewEntries: [LiveTranscriptEntry] = [],
        processedChunkIDs: [String] = [],
        metrics: LiveSessionMetrics = .empty,
        microphoneSource: LiveCaptureSourceState = .idle,
        systemAudioSource: LiveCaptureSourceState = LiveCaptureSourceState(status: .notRequired),
        statusMessage: String? = nil,
        lastUpdatedAt: Date? = nil,
        lastRecoveryAt: Date? = nil
    ) {
        self.status = status
        self.isTranscriptPanelPresented = isTranscriptPanelPresented
        self.previewEntries = previewEntries
        self.processedChunkIDs = processedChunkIDs
        self.metrics = metrics
        self.microphoneSource = microphoneSource
        self.systemAudioSource = systemAudioSource
        self.statusMessage = statusMessage
        self.lastUpdatedAt = lastUpdatedAt
        self.lastRecoveryAt = lastRecoveryAt
    }

    public static let idle = LiveSessionState()

    public var hasPreviewEntries: Bool {
        !previewEntries.isEmpty
    }

    public func hasProcessedChunkID(_ chunkID: String) -> Bool {
        processedChunkIDs.contains(chunkID)
    }

    public var isActive: Bool {
        status == .live || status == .delayed
    }

    public mutating func begin(
        at date: Date = Date(),
        presentTranscriptPanel: Bool = false,
        tracksSystemAudio: Bool = false
    ) {
        status = .live
        isTranscriptPanelPresented = presentTranscriptPanel
        previewEntries = []
        processedChunkIDs = []
        metrics.reset(at: date, tracksSystemAudio: tracksSystemAudio)
        microphoneSource.reset(isRequired: true, at: date)
        systemAudioSource.reset(isRequired: tracksSystemAudio, at: date)
        statusMessage = "Oatmeal is listening locally and preparing live transcript updates."
        lastUpdatedAt = date
        appendEntry(
            LiveTranscriptEntry(
                createdAt: date,
                kind: .system,
                text: "Live session started. Background transcript updates will appear here."
            ),
            updatedAt: date
        )
    }

    public mutating func appendEntry(_ entry: LiveTranscriptEntry, updatedAt: Date = Date()) {
        previewEntries.append(entry)
        lastUpdatedAt = updatedAt
    }

    public mutating func registerProcessedChunkID(_ chunkID: String, updatedAt: Date = Date()) {
        if !processedChunkIDs.contains(chunkID) {
            processedChunkIDs.append(chunkID)
        }
        lastUpdatedAt = updatedAt
    }

    public mutating func presentTranscriptPanel(_ presented: Bool, updatedAt: Date = Date()) {
        isTranscriptPanelPresented = presented
        lastUpdatedAt = updatedAt
    }

    public mutating func markLive(message: String? = nil, at date: Date = Date()) {
        status = .live
        if let message {
            statusMessage = message
        }
        lastUpdatedAt = date
    }

    public mutating func markDelayed(message: String, at date: Date = Date()) {
        status = .delayed
        statusMessage = message
        _ = metrics.recordInterruption()
        lastUpdatedAt = date
    }

    public mutating func markRecovered(message: String, at date: Date = Date()) {
        status = .recovered
        statusMessage = message
        _ = metrics.recordRecovery()
        lastUpdatedAt = date
        lastRecoveryAt = date
        appendEntry(
            LiveTranscriptEntry(
                createdAt: date,
                kind: .system,
                text: message
            ),
            updatedAt: date
        )
    }

    public mutating func complete(message: String? = nil, at date: Date = Date()) {
        status = .completed
        statusMessage = message ?? "Recording stopped. Oatmeal will finish transcription in the background."
        lastUpdatedAt = date
        appendEntry(
            LiveTranscriptEntry(
                createdAt: date,
                kind: .system,
                text: statusMessage ?? "Recording stopped."
            ),
            updatedAt: date
        )
    }

    public mutating func fail(message: String, at date: Date = Date()) {
        status = .failed
        statusMessage = message
        _ = metrics.recordInterruption()
        lastUpdatedAt = date
        appendEntry(
            LiveTranscriptEntry(
                createdAt: date,
                kind: .system,
                text: message
            ),
            updatedAt: date
        )
    }

    public mutating func replaceTranscriptPreviewEntries(
        _ entries: [LiveTranscriptEntry],
        updatedAt: Date = Date()
    ) {
        let systemEntries = previewEntries.filter { $0.kind == .system }
        previewEntries = systemEntries + entries
        lastUpdatedAt = updatedAt
    }

    public mutating func updateSource(
        _ source: LiveCaptureSourceID,
        status: LiveCaptureSourceStatus,
        message: String? = nil,
        at date: Date = Date()
    ) {
        switch source {
        case .microphone:
            microphoneSource.update(status: status, message: message, at: date)
        case .systemAudio:
            systemAudioSource.update(status: status, message: message, at: date)
        }
        if status != .idle && status != .notRequired {
            _ = metrics.recordSourceActivity(source, at: date)
        }
        lastUpdatedAt = date
    }

    @discardableResult
    public mutating func recordSourceActivity(
        _ source: LiveCaptureSourceID,
        at date: Date = Date()
    ) -> Bool {
        let didChange = metrics.recordSourceActivity(source, at: date)
        if didChange {
            lastUpdatedAt = date
        }
        return didChange
    }

    @discardableResult
    public mutating func registerMergedLiveChunk(
        updatedAt date: Date = Date(),
        sourceEndedAt: Date? = nil
    ) -> Bool {
        let didChange = metrics.registerMergedLiveChunk(
            mergedAt: date,
            sourceEndedAt: sourceEndedAt
        )
        if didChange {
            lastUpdatedAt = date
        }
        return didChange
    }

    @discardableResult
    public mutating func updateBacklog(
        pendingChunkCount: Int,
        oldestPendingChunkStartedAt: Date?,
        at date: Date = Date()
    ) -> Bool {
        let didChange = metrics.updateBacklog(
            pendingChunkCount: pendingChunkCount,
            oldestPendingChunkStartedAt: oldestPendingChunkStartedAt
        )
        if didChange {
            lastUpdatedAt = date
        }
        return didChange
    }

    @discardableResult
    public mutating func recordRecovery(at date: Date = Date()) -> Bool {
        let didChange = metrics.recordRecovery()
        if didChange {
            lastUpdatedAt = date
        }
        return didChange
    }

    @discardableResult
    public mutating func recordInterruption(at date: Date = Date()) -> Bool {
        let didChange = metrics.recordInterruption()
        if didChange {
            lastUpdatedAt = date
        }
        return didChange
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case isTranscriptPanelPresented
        case previewEntries
        case processedChunkIDs
        case metrics
        case microphoneSource
        case systemAudioSource
        case statusMessage
        case lastUpdatedAt
        case lastRecoveryAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(LiveSessionStatus.self, forKey: .status) ?? .idle
        isTranscriptPanelPresented = try container.decodeIfPresent(Bool.self, forKey: .isTranscriptPanelPresented) ?? false
        previewEntries = try container.decodeIfPresent([LiveTranscriptEntry].self, forKey: .previewEntries) ?? []
        processedChunkIDs = try container.decodeIfPresent([String].self, forKey: .processedChunkIDs) ?? []
        metrics = try container.decodeIfPresent(LiveSessionMetrics.self, forKey: .metrics) ?? .empty
        microphoneSource = try container.decodeIfPresent(LiveCaptureSourceState.self, forKey: .microphoneSource) ?? .idle
        systemAudioSource = try container.decodeIfPresent(LiveCaptureSourceState.self, forKey: .systemAudioSource) ?? LiveCaptureSourceState(status: .notRequired)
        statusMessage = try container.decodeIfPresent(String.self, forKey: .statusMessage)
        lastUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .lastUpdatedAt)
        lastRecoveryAt = try container.decodeIfPresent(Date.self, forKey: .lastRecoveryAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encode(isTranscriptPanelPresented, forKey: .isTranscriptPanelPresented)
        try container.encode(previewEntries, forKey: .previewEntries)
        try container.encode(processedChunkIDs, forKey: .processedChunkIDs)
        try container.encode(metrics, forKey: .metrics)
        try container.encode(microphoneSource, forKey: .microphoneSource)
        try container.encode(systemAudioSource, forKey: .systemAudioSource)
        try container.encodeIfPresent(statusMessage, forKey: .statusMessage)
        try container.encodeIfPresent(lastUpdatedAt, forKey: .lastUpdatedAt)
        try container.encodeIfPresent(lastRecoveryAt, forKey: .lastRecoveryAt)
    }
}

public enum SharePrivacyLevel: String, Codable, Equatable, Sendable {
    case `private`
    case anyoneWithLink
    case teamOnly
}

public struct ShareSettings: Codable, Equatable, Sendable {
    public var privacyLevel: SharePrivacyLevel
    public var includeTranscript: Bool
    public var allowViewersToChat: Bool

    public init(
        privacyLevel: SharePrivacyLevel = .private,
        includeTranscript: Bool = false,
        allowViewersToChat: Bool = false
    ) {
        self.privacyLevel = privacyLevel
        self.includeTranscript = includeTranscript
        self.allowViewersToChat = allowViewersToChat
    }

    public static let `default` = ShareSettings()
}

public struct SharedNoteLink: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var noteID: UUID
    public var token: String
    public var url: URL
    public var settings: ShareSettings
    public var createdAt: Date
    public var revokedAt: Date?

    public init(
        id: UUID = UUID(),
        noteID: UUID,
        token: String,
        url: URL,
        settings: ShareSettings,
        createdAt: Date = Date(),
        revokedAt: Date? = nil
    ) {
        self.id = id
        self.noteID = noteID
        self.token = token
        self.url = url
        self.settings = settings
        self.createdAt = createdAt
        self.revokedAt = revokedAt
    }

    public var isRevoked: Bool {
        revokedAt != nil
    }
}

public struct NoteFolder: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var isPinned: Bool
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, isPinned: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.isPinned = isPinned
        self.createdAt = createdAt
    }
}

public enum TemplateKind: String, Codable, Equatable, Sendable {
    case automatic
    case oneOnOne
    case standUp
    case interview
    case customerCall
    case projectReview
    case custom
}

public enum TemplateValidationError: Error, Equatable, Sendable {
    case emptyName
    case emptySections
    case emptyInstructions
}

public struct NoteTemplate: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: TemplateKind
    public var name: String
    public var description: String
    public var instructions: String
    public var sections: [String]
    public var isDefault: Bool

    public init(
        id: UUID = UUID(),
        kind: TemplateKind = .custom,
        name: String,
        description: String = "",
        instructions: String,
        sections: [String],
        isDefault: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.description = description
        self.instructions = instructions
        self.sections = sections
        self.isDefault = isDefault
    }

    public func validate() throws {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw TemplateValidationError.emptyName
        }

        if instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw TemplateValidationError.emptyInstructions
        }

        if sections.isEmpty {
            throw TemplateValidationError.emptySections
        }
    }

    public func makeGenerationRequest(for note: MeetingNote) -> NoteGenerationRequest {
        NoteGenerationRequest(
            noteID: note.id,
            title: note.title,
            template: self,
            meetingEvent: note.calendarEvent,
            rawNotes: note.rawNotes,
            transcriptSegments: note.transcriptSegments,
            folderID: note.folderID,
            shareSettings: note.shareSettings
        )
    }
}

public struct NoteGenerationRequest: Codable, Equatable, Sendable {
    public var noteID: UUID
    public var title: String
    public var template: NoteTemplate
    public var meetingEvent: CalendarEvent?
    public var rawNotes: String
    public var transcriptSegments: [TranscriptSegment]
    public var folderID: UUID?
    public var shareSettings: ShareSettings

    public init(
        noteID: UUID,
        title: String,
        template: NoteTemplate,
        meetingEvent: CalendarEvent?,
        rawNotes: String,
        transcriptSegments: [TranscriptSegment],
        folderID: UUID? = nil,
        shareSettings: ShareSettings = .default
    ) {
        self.noteID = noteID
        self.title = title
        self.template = template
        self.meetingEvent = meetingEvent
        self.rawNotes = rawNotes
        self.transcriptSegments = transcriptSegments
        self.folderID = folderID
        self.shareSettings = shareSettings
    }
}

public struct MeetingNote: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var origin: NoteOrigin
    public var calendarEvent: CalendarEvent?
    public var folderID: UUID?
    public var templateID: UUID?
    public var shareSettings: ShareSettings
    public var captureState: CaptureSessionState
    public var generationStatus: NoteGenerationStatus
    public var transcriptionStatus: NoteTranscriptionStatus
    public var rawNotes: String
    public var transcriptSegments: [TranscriptSegment]
    public var liveSessionState: LiveSessionState
    public var enhancedNote: EnhancedNote?
    public var assistantThread: NoteAssistantThread
    public var transcriptionHistory: [NoteTranscriptionAttempt]
    public var generationHistory: [NoteGenerationAttempt]
    public var processingState: PostCaptureProcessingState
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        origin: NoteOrigin,
        calendarEvent: CalendarEvent? = nil,
        folderID: UUID? = nil,
        templateID: UUID? = nil,
        shareSettings: ShareSettings = .default,
        captureState: CaptureSessionState = .ready,
        generationStatus: NoteGenerationStatus = .idle,
        transcriptionStatus: NoteTranscriptionStatus = .idle,
        rawNotes: String = "",
        transcriptSegments: [TranscriptSegment] = [],
        liveSessionState: LiveSessionState = .idle,
        enhancedNote: EnhancedNote? = nil,
        assistantThread: NoteAssistantThread = .empty,
        transcriptionHistory: [NoteTranscriptionAttempt] = [],
        generationHistory: [NoteGenerationAttempt] = [],
        processingState: PostCaptureProcessingState = .idle,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.origin = origin
        self.calendarEvent = calendarEvent
        self.folderID = folderID
        self.templateID = templateID
        self.shareSettings = shareSettings
        self.captureState = captureState
        self.generationStatus = generationStatus
        self.transcriptionStatus = transcriptionStatus
        self.rawNotes = rawNotes
        self.transcriptSegments = transcriptSegments
        self.liveSessionState = liveSessionState
        self.enhancedNote = enhancedNote
        self.assistantThread = assistantThread
        self.transcriptionHistory = transcriptionHistory
        self.generationHistory = generationHistory
        self.processingState = processingState
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case origin
        case calendarEvent
        case folderID
        case templateID
        case shareSettings
        case captureState
        case generationStatus
        case transcriptionStatus
        case rawNotes
        case transcriptSegments
        case liveSessionState
        case enhancedNote
        case assistantThread
        case transcriptionHistory
        case generationHistory
        case processingState
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        origin = try container.decode(NoteOrigin.self, forKey: .origin)
        calendarEvent = try container.decodeIfPresent(CalendarEvent.self, forKey: .calendarEvent)
        folderID = try container.decodeIfPresent(UUID.self, forKey: .folderID)
        templateID = try container.decodeIfPresent(UUID.self, forKey: .templateID)
        shareSettings = try container.decodeIfPresent(ShareSettings.self, forKey: .shareSettings) ?? .default
        captureState = try container.decodeIfPresent(CaptureSessionState.self, forKey: .captureState) ?? .ready
        generationStatus = try container.decodeIfPresent(NoteGenerationStatus.self, forKey: .generationStatus) ?? .idle
        transcriptionStatus = try container.decodeIfPresent(NoteTranscriptionStatus.self, forKey: .transcriptionStatus) ?? .idle
        rawNotes = try container.decodeIfPresent(String.self, forKey: .rawNotes) ?? ""
        transcriptSegments = try container.decodeIfPresent([TranscriptSegment].self, forKey: .transcriptSegments) ?? []
        liveSessionState = try container.decodeIfPresent(LiveSessionState.self, forKey: .liveSessionState) ?? .idle
        enhancedNote = try container.decodeIfPresent(EnhancedNote.self, forKey: .enhancedNote)
        assistantThread = try container.decodeIfPresent(NoteAssistantThread.self, forKey: .assistantThread) ?? .empty
        transcriptionHistory = try container.decodeIfPresent([NoteTranscriptionAttempt].self, forKey: .transcriptionHistory) ?? []
        generationHistory = try container.decodeIfPresent([NoteGenerationAttempt].self, forKey: .generationHistory) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        processingState = try container.decodeIfPresent(PostCaptureProcessingState.self, forKey: .processingState)
            ?? Self.derivedProcessingState(
                transcriptionStatus: transcriptionStatus,
                generationStatus: generationStatus,
                transcriptionHistory: transcriptionHistory,
                generationHistory: generationHistory,
                updatedAt: updatedAt
            )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(origin, forKey: .origin)
        try container.encodeIfPresent(calendarEvent, forKey: .calendarEvent)
        try container.encodeIfPresent(folderID, forKey: .folderID)
        try container.encodeIfPresent(templateID, forKey: .templateID)
        try container.encode(shareSettings, forKey: .shareSettings)
        try container.encode(captureState, forKey: .captureState)
        try container.encode(generationStatus, forKey: .generationStatus)
        try container.encode(transcriptionStatus, forKey: .transcriptionStatus)
        try container.encode(rawNotes, forKey: .rawNotes)
        try container.encode(transcriptSegments, forKey: .transcriptSegments)
        try container.encode(liveSessionState, forKey: .liveSessionState)
        try container.encodeIfPresent(enhancedNote, forKey: .enhancedNote)
        try container.encode(assistantThread, forKey: .assistantThread)
        try container.encode(transcriptionHistory, forKey: .transcriptionHistory)
        try container.encode(generationHistory, forKey: .generationHistory)
        try container.encode(processingState, forKey: .processingState)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    public var isQuickNote: Bool {
        origin.kind == .quickNote
    }

    public var hasTranscript: Bool {
        !transcriptSegments.isEmpty
    }

    public var hasLiveTranscriptPreview: Bool {
        liveSessionState.hasPreviewEntries
    }

    public var hasRawNotes: Bool {
        !rawNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var canBeSharedWithTranscript: Bool {
        shareSettings.includeTranscript
    }

    public var needsPostCaptureRecovery: Bool {
        processingState.needsRelaunchRecovery
    }

    public var isAIWorkspaceAvailable: Bool {
        hasRawNotes || hasTranscript || enhancedNote != nil || hasLiveTranscriptPreview
    }

    public var hasPendingAssistantTurn: Bool {
        assistantThread.hasPendingTurn
    }

    public mutating func assignFolder(_ folderID: UUID?, updatedAt: Date = Date()) {
        self.folderID = folderID
        self.updatedAt = updatedAt
    }

    public mutating func replaceRawNotes(_ text: String, updatedAt: Date = Date()) {
        rawNotes = text
        self.updatedAt = updatedAt
    }

    @discardableResult
    public mutating func submitAssistantPrompt(
        _ prompt: String,
        kind: NoteAssistantTurnKind = .prompt,
        at updatedAt: Date = Date()
    ) -> UUID {
        let turnID = assistantThread.submitPrompt(prompt, kind: kind, at: updatedAt)
        self.updatedAt = updatedAt
        return turnID
    }

    @discardableResult
    public mutating func completeAssistantTurn(
        id: UUID,
        response: String,
        citations: [NoteAssistantCitation] = [],
        at updatedAt: Date = Date()
    ) -> Bool {
        let didChange = assistantThread.completeTurn(
            id: id,
            response: response,
            citations: citations,
            at: updatedAt
        )
        if didChange {
            self.updatedAt = updatedAt
        }
        return didChange
    }

    @discardableResult
    public mutating func failAssistantTurn(
        id: UUID,
        message: String,
        at updatedAt: Date = Date()
    ) -> Bool {
        let didChange = assistantThread.failTurn(id: id, message: message, at: updatedAt)
        if didChange {
            self.updatedAt = updatedAt
        }
        return didChange
    }

    @discardableResult
    public mutating func prepareAssistantThreadForRelaunchRecovery(
        message: String,
        at updatedAt: Date = Date()
    ) -> Bool {
        let didChange = assistantThread.failPendingTurnsForRelaunchRecovery(
            message: message,
            at: updatedAt
        )
        if didChange {
            self.updatedAt = updatedAt
        }
        return didChange
    }

    public mutating func appendTranscriptSegment(_ segment: TranscriptSegment, updatedAt: Date = Date()) {
        transcriptSegments.append(segment)
        self.updatedAt = updatedAt
    }

    public mutating func appendTranscriptSegments(_ segments: [TranscriptSegment], updatedAt: Date = Date()) {
        transcriptSegments.append(contentsOf: segments)
        self.updatedAt = updatedAt
    }

    public mutating func beginLiveSession(
        at startedAt: Date = Date(),
        presentTranscriptPanel: Bool = false,
        tracksSystemAudio: Bool = false
    ) {
        liveSessionState.begin(
            at: startedAt,
            presentTranscriptPanel: presentTranscriptPanel,
            tracksSystemAudio: tracksSystemAudio
        )
        updatedAt = startedAt
    }

    public mutating func appendLiveTranscriptEntry(_ entry: LiveTranscriptEntry, updatedAt: Date = Date()) {
        liveSessionState.appendEntry(entry, updatedAt: updatedAt)
        self.updatedAt = updatedAt
    }

    public mutating func registerProcessedLiveChunkID(_ chunkID: String, updatedAt: Date = Date()) {
        liveSessionState.registerProcessedChunkID(chunkID, updatedAt: updatedAt)
        self.updatedAt = updatedAt
    }

    @discardableResult
    public mutating func recordLiveCaptureSourceActivity(
        _ source: LiveCaptureSourceID,
        updatedAt: Date = Date()
    ) -> Bool {
        let didChange = liveSessionState.recordSourceActivity(source, at: updatedAt)
        if didChange {
            self.updatedAt = updatedAt
        }
        return didChange
    }

    @discardableResult
    public mutating func recordMergedLiveChunk(
        updatedAt: Date = Date(),
        sourceEndedAt: Date? = nil
    ) -> Bool {
        let didChange = liveSessionState.registerMergedLiveChunk(
            updatedAt: updatedAt,
            sourceEndedAt: sourceEndedAt
        )
        if didChange {
            self.updatedAt = updatedAt
        }
        return didChange
    }

    @discardableResult
    public mutating func updateLiveChunkBacklog(
        pendingChunkCount: Int,
        oldestPendingChunkStartedAt: Date?,
        updatedAt: Date = Date()
    ) -> Bool {
        let didChange = liveSessionState.updateBacklog(
            pendingChunkCount: pendingChunkCount,
            oldestPendingChunkStartedAt: oldestPendingChunkStartedAt,
            at: updatedAt
        )
        if didChange {
            self.updatedAt = updatedAt
        }
        return didChange
    }

    @discardableResult
    public mutating func recordLiveSessionRecovery(updatedAt: Date = Date()) -> Bool {
        let didChange = liveSessionState.recordRecovery(at: updatedAt)
        if didChange {
            self.updatedAt = updatedAt
        }
        return didChange
    }

    @discardableResult
    public mutating func recordLiveSessionInterruption(updatedAt: Date = Date()) -> Bool {
        let didChange = liveSessionState.recordInterruption(at: updatedAt)
        if didChange {
            self.updatedAt = updatedAt
        }
        return didChange
    }

    public mutating func setLiveTranscriptPanelPresented(_ presented: Bool, updatedAt: Date = Date()) {
        liveSessionState.presentTranscriptPanel(presented, updatedAt: updatedAt)
        self.updatedAt = updatedAt
    }

    public mutating func markLiveSessionLive(message: String? = nil, at updatedAt: Date = Date()) {
        liveSessionState.markLive(message: message, at: updatedAt)
        self.updatedAt = updatedAt
    }

    public mutating func updateLiveCaptureSource(
        _ source: LiveCaptureSourceID,
        status: LiveCaptureSourceStatus,
        message: String? = nil,
        updatedAt: Date = Date()
    ) {
        liveSessionState.updateSource(source, status: status, message: message, at: updatedAt)
        self.updatedAt = updatedAt
    }

    public mutating func markLiveSessionDelayed(message: String, at updatedAt: Date = Date()) {
        liveSessionState.markDelayed(message: message, at: updatedAt)
        self.updatedAt = updatedAt
    }

    public mutating func markLiveSessionRecovered(message: String, at updatedAt: Date = Date()) {
        liveSessionState.markRecovered(message: message, at: updatedAt)
        self.updatedAt = updatedAt
    }

    public mutating func completeLiveSession(message: String? = nil, at updatedAt: Date = Date()) {
        liveSessionState.complete(message: message, at: updatedAt)
        self.updatedAt = updatedAt
    }

    public mutating func failLiveSession(message: String, at updatedAt: Date = Date()) {
        liveSessionState.fail(message: message, at: updatedAt)
        self.updatedAt = updatedAt
    }

    public mutating func replaceLiveTranscriptPreviewEntries(
        _ entries: [LiveTranscriptEntry],
        updatedAt: Date = Date()
    ) {
        liveSessionState.replaceTranscriptPreviewEntries(entries, updatedAt: updatedAt)
        self.updatedAt = updatedAt
    }

    public mutating func queueTranscription(at queuedAt: Date = Date()) {
        processingState.queue(.transcription, at: queuedAt)
        updatedAt = queuedAt
    }

    public mutating func prepareTranscriptionRetry(at queuedAt: Date = Date()) {
        transcriptSegments = []
        enhancedNote = nil
        transcriptionStatus = .idle
        generationStatus = .idle
        processingState.queue(.transcription, at: queuedAt)
        updatedAt = queuedAt
    }

    public mutating func beginTranscription(
        backend: NoteTranscriptionBackend,
        executionKind: NoteTranscriptionExecutionKind,
        at requestedAt: Date = Date()
    ) {
        transcriptionStatus = .pending
        processingState.start(.transcription, at: requestedAt)
        transcriptionHistory.append(
            NoteTranscriptionAttempt(
                backend: backend,
                executionKind: executionKind,
                requestedAt: requestedAt,
                completedAt: nil,
                status: .pending
            )
        )
        updatedAt = requestedAt
    }

    public mutating func applyTranscript(
        _ segments: [TranscriptSegment],
        backend: NoteTranscriptionBackend,
        executionKind: NoteTranscriptionExecutionKind,
        warnings: [String] = [],
        at updatedAt: Date = Date()
    ) {
        transcriptSegments = segments
        transcriptionStatus = .succeeded
        processingState.complete(stage: .transcription, at: updatedAt)
        if let lastIndex = transcriptionHistory.indices.last {
            transcriptionHistory[lastIndex].backend = backend
            transcriptionHistory[lastIndex].executionKind = executionKind
            transcriptionHistory[lastIndex].status = .succeeded
            transcriptionHistory[lastIndex].completedAt = updatedAt
            transcriptionHistory[lastIndex].segmentCount = segments.count
            transcriptionHistory[lastIndex].warningMessages = warnings
            transcriptionHistory[lastIndex].errorMessage = nil
        } else {
            transcriptionHistory.append(
                NoteTranscriptionAttempt(
                    backend: backend,
                    executionKind: executionKind,
                    requestedAt: updatedAt,
                    completedAt: updatedAt,
                    status: .succeeded,
                    segmentCount: segments.count,
                    warningMessages: warnings
                )
            )
        }
        self.updatedAt = updatedAt
    }

    public mutating func recordTranscriptionFailure(
        backend: NoteTranscriptionBackend,
        executionKind: NoteTranscriptionExecutionKind,
        message: String,
        warnings: [String] = [],
        at updatedAt: Date = Date()
    ) {
        transcriptionStatus = .failed
        processingState.fail(stage: .transcription, message: message, at: updatedAt)
        if let lastIndex = transcriptionHistory.indices.last {
            transcriptionHistory[lastIndex].backend = backend
            transcriptionHistory[lastIndex].executionKind = executionKind
            transcriptionHistory[lastIndex].status = .failed
            transcriptionHistory[lastIndex].completedAt = updatedAt
            transcriptionHistory[lastIndex].segmentCount = transcriptSegments.count
            transcriptionHistory[lastIndex].warningMessages = warnings
            transcriptionHistory[lastIndex].errorMessage = message
        } else {
            transcriptionHistory.append(
                NoteTranscriptionAttempt(
                    backend: backend,
                    executionKind: executionKind,
                    requestedAt: updatedAt,
                    completedAt: updatedAt,
                    status: .failed,
                    segmentCount: transcriptSegments.count,
                    warningMessages: warnings,
                    errorMessage: message
                )
            )
        }
        self.updatedAt = updatedAt
    }

    public mutating func queueGeneration(templateID: UUID?, at queuedAt: Date = Date()) {
        self.templateID = templateID
        processingState.queue(.generation, at: queuedAt)
        updatedAt = queuedAt
    }

    public mutating func prepareGenerationRetry(templateID: UUID?, at queuedAt: Date = Date()) {
        self.templateID = templateID
        enhancedNote = nil
        generationStatus = .idle
        processingState.queue(.generation, at: queuedAt)
        updatedAt = queuedAt
    }

    public mutating func beginGeneration(templateID: UUID?, at requestedAt: Date = Date()) {
        generationStatus = .pending
        self.templateID = templateID
        processingState.start(.generation, at: requestedAt)
        generationHistory.append(
            NoteGenerationAttempt(templateID: templateID, requestedAt: requestedAt, completedAt: nil, status: .pending, errorMessage: nil)
        )
        updatedAt = requestedAt
    }

    public mutating func applyEnhancedNote(_ enhancedNote: EnhancedNote, at updatedAt: Date = Date()) {
        self.enhancedNote = enhancedNote
        self.templateID = enhancedNote.templateID ?? templateID
        generationStatus = .succeeded
        processingState.complete(stage: .complete, at: updatedAt)
        if let lastIndex = generationHistory.indices.last {
            generationHistory[lastIndex].status = .succeeded
            generationHistory[lastIndex].completedAt = updatedAt
            generationHistory[lastIndex].errorMessage = nil
        } else {
            generationHistory.append(
                NoteGenerationAttempt(templateID: templateID, requestedAt: updatedAt, completedAt: updatedAt, status: .succeeded)
            )
        }
        self.updatedAt = updatedAt
    }

    public mutating func recordGenerationFailure(_ message: String, at updatedAt: Date = Date()) {
        generationStatus = .failed
        processingState.fail(stage: .generation, message: message, at: updatedAt)
        if let lastIndex = generationHistory.indices.last {
            generationHistory[lastIndex].status = .failed
            generationHistory[lastIndex].completedAt = updatedAt
            generationHistory[lastIndex].errorMessage = message
        } else {
            generationHistory.append(
                NoteGenerationAttempt(
                    templateID: templateID,
                    requestedAt: updatedAt,
                    completedAt: updatedAt,
                    status: .failed,
                    errorMessage: message
                )
            )
        }
        self.updatedAt = updatedAt
    }

    @discardableResult
    public mutating func preparePostCaptureRecovery(at recoveredAt: Date = Date()) -> Bool {
        guard processingState.needsRelaunchRecovery else {
            return false
        }

        processingState.prepareForRelaunchRecovery(at: recoveredAt)
        updatedAt = recoveredAt
        return true
    }

    private static func derivedProcessingState(
        transcriptionStatus: NoteTranscriptionStatus,
        generationStatus: NoteGenerationStatus,
        transcriptionHistory: [NoteTranscriptionAttempt],
        generationHistory: [NoteGenerationAttempt],
        updatedAt: Date
    ) -> PostCaptureProcessingState {
        if generationStatus == .pending {
            return PostCaptureProcessingState(
                stage: .generation,
                status: .running,
                queuedAt: generationHistory.last?.requestedAt ?? updatedAt,
                startedAt: generationHistory.last?.requestedAt ?? updatedAt
            )
        }

        if transcriptionStatus == .pending {
            return PostCaptureProcessingState(
                stage: .transcription,
                status: .running,
                queuedAt: transcriptionHistory.last?.requestedAt ?? updatedAt,
                startedAt: transcriptionHistory.last?.requestedAt ?? updatedAt
            )
        }

        if generationStatus == .failed {
            return PostCaptureProcessingState(
                stage: .generation,
                status: .failed,
                queuedAt: generationHistory.last?.requestedAt,
                startedAt: generationHistory.last?.requestedAt,
                completedAt: generationHistory.last?.completedAt ?? updatedAt,
                errorMessage: generationHistory.last?.errorMessage
            )
        }

        if transcriptionStatus == .failed {
            return PostCaptureProcessingState(
                stage: .transcription,
                status: .failed,
                queuedAt: transcriptionHistory.last?.requestedAt,
                startedAt: transcriptionHistory.last?.requestedAt,
                completedAt: transcriptionHistory.last?.completedAt ?? updatedAt,
                errorMessage: transcriptionHistory.last?.errorMessage
            )
        }

        if generationStatus == .succeeded {
            return PostCaptureProcessingState(
                stage: .complete,
                status: .completed,
                queuedAt: generationHistory.last?.requestedAt,
                startedAt: generationHistory.last?.requestedAt,
                completedAt: generationHistory.last?.completedAt ?? updatedAt
            )
        }

        if transcriptionStatus == .succeeded {
            return PostCaptureProcessingState(
                stage: .transcription,
                status: .completed,
                queuedAt: transcriptionHistory.last?.requestedAt,
                startedAt: transcriptionHistory.last?.requestedAt,
                completedAt: transcriptionHistory.last?.completedAt ?? updatedAt
            )
        }

        return .idle
    }
}

public enum PermissionStatus: String, Codable, Equatable, Sendable {
    case notDetermined
    case granted
    case denied
    case restricted
}

public struct CapturePermissions: Codable, Equatable, Sendable {
    public var microphone: PermissionStatus
    public var systemAudio: PermissionStatus
    public var notifications: PermissionStatus
    public var calendar: PermissionStatus

    public init(
        microphone: PermissionStatus = .notDetermined,
        systemAudio: PermissionStatus = .notDetermined,
        notifications: PermissionStatus = .notDetermined,
        calendar: PermissionStatus = .notDetermined
    ) {
        self.microphone = microphone
        self.systemAudio = systemAudio
        self.notifications = notifications
        self.calendar = calendar
    }

    public var allRequiredPermissionsGranted: Bool {
        microphone == .granted && systemAudio == .granted && notifications == .granted && calendar == .granted
    }
}

public enum CapturePhase: String, Codable, Equatable, Sendable {
    case ready
    case capturing
    case paused
    case failed
    case complete
}

public struct CaptureSessionState: Codable, Equatable, Sendable {
    public var phase: CapturePhase
    public var startedAt: Date?
    public var pausedAt: Date?
    public var endedAt: Date?
    public var failureReason: String?
    public var isRecoverableAfterCrash: Bool
    public var permissions: CapturePermissions

    public init(
        phase: CapturePhase = .ready,
        startedAt: Date? = nil,
        pausedAt: Date? = nil,
        endedAt: Date? = nil,
        failureReason: String? = nil,
        isRecoverableAfterCrash: Bool = false,
        permissions: CapturePermissions = CapturePermissions()
    ) {
        self.phase = phase
        self.startedAt = startedAt
        self.pausedAt = pausedAt
        self.endedAt = endedAt
        self.failureReason = failureReason
        self.isRecoverableAfterCrash = isRecoverableAfterCrash
        self.permissions = permissions
    }

    public static let ready = CaptureSessionState()

    public var canResumeAfterCrash: Bool {
        phase == .failed && isRecoverableAfterCrash
    }

    public var isActive: Bool {
        phase == .capturing || phase == .paused
    }

    public mutating func beginCapture(at date: Date = Date()) {
        phase = .capturing
        startedAt = date
        pausedAt = nil
        endedAt = nil
        failureReason = nil
        isRecoverableAfterCrash = true
    }

    public mutating func pause(at date: Date = Date()) {
        guard phase == .capturing else { return }
        phase = .paused
        pausedAt = date
    }

    public mutating func resume(at date: Date = Date()) {
        guard phase == .paused || canResumeAfterCrash else { return }
        phase = .capturing
        pausedAt = nil
        if startedAt == nil {
            startedAt = date
        }
        failureReason = nil
        isRecoverableAfterCrash = true
    }

    public mutating func complete(at date: Date = Date()) {
        phase = .complete
        endedAt = date
        isRecoverableAfterCrash = false
    }

    public mutating func fail(reason: String, at date: Date = Date(), recoverable: Bool = false) {
        phase = .failed
        endedAt = date
        failureReason = reason
        isRecoverableAfterCrash = recoverable
    }
}

public enum NoteSearchField: String, Codable, Equatable, Hashable, Sendable {
    case title
    case rawNotes
    case transcript
    case summary
    case decisions
    case actionItems
    case folder
    case template
}

public struct NoteSearchFilters: Codable, Equatable, Sendable {
    public var folderID: UUID?
    public var startDate: Date?
    public var endDate: Date?

    public init(folderID: UUID? = nil, startDate: Date? = nil, endDate: Date? = nil) {
        self.folderID = folderID
        self.startDate = startDate
        self.endDate = endDate
    }
}

public struct NoteSearchResult: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var noteID: UUID
    public var title: String
    public var snippet: String
    public var matchedFields: [NoteSearchField]
    public var folderName: String?

    public init(
        id: UUID = UUID(),
        noteID: UUID,
        title: String,
        snippet: String,
        matchedFields: [NoteSearchField],
        folderName: String? = nil
    ) {
        self.id = id
        self.noteID = noteID
        self.title = title
        self.snippet = snippet
        self.matchedFields = matchedFields
        self.folderName = folderName
    }
}
