import Foundation
import OatmealCore

public enum TranscriptionBackendPreference: String, Codable, CaseIterable, Equatable, Sendable {
    case automatic
    case whisperCPPCLI
    case appleSpeech
    case mock

    public var displayName: String {
        switch self {
        case .automatic:
            "Automatic"
        case .whisperCPPCLI:
            "whisper.cpp"
        case .appleSpeech:
            "Apple Speech"
        case .mock:
            "Placeholder"
        }
    }
}

public enum TranscriptionExecutionPolicy: String, Codable, CaseIterable, Equatable, Sendable {
    case preferLocal
    case allowSystemFallback
    case requireLocal

    public var displayName: String {
        switch self {
        case .preferLocal:
            "Prefer Local"
        case .allowSystemFallback:
            "Allow Fallback"
        case .requireLocal:
            "Require Local"
        }
    }
}

public struct LocalTranscriptionConfiguration: Codable, Equatable, Sendable {
    public var preferredBackend: TranscriptionBackendPreference
    public var executionPolicy: TranscriptionExecutionPolicy
    public var preferredLocaleIdentifier: String?

    public init(
        preferredBackend: TranscriptionBackendPreference = .automatic,
        executionPolicy: TranscriptionExecutionPolicy = .allowSystemFallback,
        preferredLocaleIdentifier: String? = nil
    ) {
        self.preferredBackend = preferredBackend
        self.executionPolicy = executionPolicy
        self.preferredLocaleIdentifier = preferredLocaleIdentifier
    }

    public static let `default` = LocalTranscriptionConfiguration()
}

public enum TranscriptionRuntimeAvailability: String, Codable, Equatable, Sendable {
    case available
    case degraded
    case unavailable
}

public enum ManagedLocalModelKind: String, Codable, Equatable, Sendable {
    case whisper
}

public struct ManagedLocalModel: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: ManagedLocalModelKind
    public var displayName: String
    public var fileURL: URL
    public var sizeBytes: Int64?

    public init(
        id: UUID = UUID(),
        kind: ManagedLocalModelKind,
        displayName: String,
        fileURL: URL,
        sizeBytes: Int64? = nil
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.fileURL = fileURL
        self.sizeBytes = sizeBytes
    }
}

public struct TranscriptionBackendStatus: Codable, Equatable, Sendable, Identifiable {
    public var id: String { backend.rawValue }
    public var backend: NoteTranscriptionBackend
    public var displayName: String
    public var availability: TranscriptionRuntimeAvailability
    public var detail: String
    public var isRunnable: Bool

    public init(
        backend: NoteTranscriptionBackend,
        displayName: String,
        availability: TranscriptionRuntimeAvailability,
        detail: String,
        isRunnable: Bool
    ) {
        self.backend = backend
        self.displayName = displayName
        self.availability = availability
        self.detail = detail
        self.isRunnable = isRunnable
    }
}

public struct LocalTranscriptionRuntimeState: Equatable, Sendable {
    public var modelsDirectoryURL: URL
    public var discoveredModels: [ManagedLocalModel]
    public var backends: [TranscriptionBackendStatus]
    public var activePlanSummary: String

    public init(
        modelsDirectoryURL: URL,
        discoveredModels: [ManagedLocalModel],
        backends: [TranscriptionBackendStatus],
        activePlanSummary: String
    ) {
        self.modelsDirectoryURL = modelsDirectoryURL
        self.discoveredModels = discoveredModels
        self.backends = backends
        self.activePlanSummary = activePlanSummary
    }
}

public struct TranscriptionRequest: Sendable {
    public var audioFileURL: URL
    public var startedAt: Date?
    public var preferredLocaleIdentifier: String?

    public init(
        audioFileURL: URL,
        startedAt: Date? = nil,
        preferredLocaleIdentifier: String? = nil
    ) {
        self.audioFileURL = audioFileURL
        self.startedAt = startedAt
        self.preferredLocaleIdentifier = preferredLocaleIdentifier
    }
}

public struct TranscriptionExecutionPlan: Equatable, Sendable {
    public var backend: NoteTranscriptionBackend
    public var executionKind: NoteTranscriptionExecutionKind
    public var summary: String
    public var warningMessages: [String]

    public init(
        backend: NoteTranscriptionBackend,
        executionKind: NoteTranscriptionExecutionKind,
        summary: String,
        warningMessages: [String] = []
    ) {
        self.backend = backend
        self.executionKind = executionKind
        self.summary = summary
        self.warningMessages = warningMessages
    }
}

public struct TranscriptionJobResult: Sendable {
    public var segments: [TranscriptSegment]
    public var backend: NoteTranscriptionBackend
    public var executionKind: NoteTranscriptionExecutionKind
    public var warningMessages: [String]

    public init(
        segments: [TranscriptSegment],
        backend: NoteTranscriptionBackend,
        executionKind: NoteTranscriptionExecutionKind,
        warningMessages: [String] = []
    ) {
        self.segments = segments
        self.backend = backend
        self.executionKind = executionKind
        self.warningMessages = warningMessages
    }
}

public enum TranscriptionPipelineError: LocalizedError, Equatable {
    case fileNotFound
    case localRuntimeRequired(String)
    case backendUnavailable(String)
    case speechAuthorizationRequired
    case speechRecognizerUnavailable(String)
    case transcriptionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound:
            "The recorded audio file could not be found."
        case let .localRuntimeRequired(message):
            message
        case let .backendUnavailable(message):
            message
        case .speechAuthorizationRequired:
            "Speech recognition permission has not been granted for Oatmeal yet."
        case let .speechRecognizerUnavailable(message):
            message
        case let .transcriptionFailed(message):
            message
        }
    }
}
