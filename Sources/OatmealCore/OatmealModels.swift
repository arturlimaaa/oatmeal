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
    public var enhancedNote: EnhancedNote?
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
        enhancedNote: EnhancedNote? = nil,
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
        self.enhancedNote = enhancedNote
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
        case enhancedNote
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
        enhancedNote = try container.decodeIfPresent(EnhancedNote.self, forKey: .enhancedNote)
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
        try container.encodeIfPresent(enhancedNote, forKey: .enhancedNote)
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

    public var canBeSharedWithTranscript: Bool {
        shareSettings.includeTranscript
    }

    public var needsPostCaptureRecovery: Bool {
        processingState.needsRelaunchRecovery
    }

    public mutating func assignFolder(_ folderID: UUID?, updatedAt: Date = Date()) {
        self.folderID = folderID
        self.updatedAt = updatedAt
    }

    public mutating func replaceRawNotes(_ text: String, updatedAt: Date = Date()) {
        rawNotes = text
        self.updatedAt = updatedAt
    }

    public mutating func appendTranscriptSegment(_ segment: TranscriptSegment, updatedAt: Date = Date()) {
        transcriptSegments.append(segment)
        self.updatedAt = updatedAt
    }

    public mutating func appendTranscriptSegments(_ segments: [TranscriptSegment], updatedAt: Date = Date()) {
        transcriptSegments.append(contentsOf: segments)
        self.updatedAt = updatedAt
    }

    public mutating func queueTranscription(at queuedAt: Date = Date()) {
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
