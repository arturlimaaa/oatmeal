import Foundation
import OatmealCore

public enum LocalSummaryBackend: String, Codable, CaseIterable, Equatable, Sendable {
    case mlxLocal
    case extractiveLocal
    case placeholder

    public var displayName: String {
        switch self {
        case .mlxLocal:
            "MLX Local"
        case .extractiveLocal:
            "Extractive Local"
        case .placeholder:
            "Placeholder"
        }
    }
}

public enum SummaryBackendPreference: String, Codable, CaseIterable, Equatable, Sendable {
    case automatic
    case mlxLocal
    case extractiveLocal
    case placeholder

    public var displayName: String {
        switch self {
        case .automatic:
            "Automatic"
        case .mlxLocal:
            "MLX Local"
        case .extractiveLocal:
            "Extractive Local"
        case .placeholder:
            "Placeholder"
        }
    }
}

public enum SummaryExecutionPolicy: String, Codable, CaseIterable, Equatable, Sendable {
    case allowFallback
    case requireStructuredSummary

    public var displayName: String {
        switch self {
        case .allowFallback:
            "Allow Fallback"
        case .requireStructuredSummary:
            "Require Structured Summary"
        }
    }
}

public struct LocalSummaryConfiguration: Codable, Equatable, Sendable {
    public var preferredBackend: SummaryBackendPreference
    public var executionPolicy: SummaryExecutionPolicy
    public var preferredModelName: String?

    public init(
        preferredBackend: SummaryBackendPreference = .automatic,
        executionPolicy: SummaryExecutionPolicy = .allowFallback,
        preferredModelName: String? = nil
    ) {
        self.preferredBackend = preferredBackend
        self.executionPolicy = executionPolicy
        self.preferredModelName = preferredModelName
    }

    public static let `default` = LocalSummaryConfiguration()
}

public enum SummaryRuntimeAvailability: String, Codable, Equatable, Sendable {
    case available
    case degraded
    case unavailable
}

public struct ManagedSummaryModel: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var displayName: String
    public var directoryURL: URL
    public var sizeBytes: Int64?

    public init(
        id: UUID = UUID(),
        displayName: String,
        directoryURL: URL,
        sizeBytes: Int64? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.directoryURL = directoryURL
        self.sizeBytes = sizeBytes
    }
}

public struct SummaryBackendStatus: Codable, Equatable, Sendable, Identifiable {
    public var id: String { backend.rawValue }
    public var backend: LocalSummaryBackend
    public var displayName: String
    public var availability: SummaryRuntimeAvailability
    public var detail: String
    public var isRunnable: Bool

    public init(
        backend: LocalSummaryBackend,
        displayName: String,
        availability: SummaryRuntimeAvailability,
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

public struct LocalSummaryRuntimeState: Equatable, Sendable {
    public var modelsDirectoryURL: URL
    public var discoveredModels: [ManagedSummaryModel]
    public var preferredModelName: String?
    public var backends: [SummaryBackendStatus]
    public var activePlanSummary: String

    public init(
        modelsDirectoryURL: URL,
        discoveredModels: [ManagedSummaryModel],
        preferredModelName: String? = nil,
        backends: [SummaryBackendStatus],
        activePlanSummary: String
    ) {
        self.modelsDirectoryURL = modelsDirectoryURL
        self.discoveredModels = discoveredModels
        self.preferredModelName = preferredModelName
        self.backends = backends
        self.activePlanSummary = activePlanSummary
    }
}

public enum LocalSummaryExecutionKind: String, Codable, Equatable, Sendable {
    case local
    case placeholder

    public var displayName: String {
        switch self {
        case .local:
            "Local"
        case .placeholder:
            "Placeholder"
        }
    }
}

public struct LocalSummaryExecutionPlan: Equatable, Sendable {
    public var backend: LocalSummaryBackend
    public var executionKind: LocalSummaryExecutionKind
    public var summary: String
    public var warningMessages: [String]

    public init(
        backend: LocalSummaryBackend,
        executionKind: LocalSummaryExecutionKind,
        summary: String,
        warningMessages: [String] = []
    ) {
        self.backend = backend
        self.executionKind = executionKind
        self.summary = summary
        self.warningMessages = warningMessages
    }
}

public struct SummaryJobResult: Sendable {
    public var enhancedNote: EnhancedNote
    public var backend: LocalSummaryBackend
    public var executionKind: LocalSummaryExecutionKind
    public var warningMessages: [String]

    public init(
        enhancedNote: EnhancedNote,
        backend: LocalSummaryBackend,
        executionKind: LocalSummaryExecutionKind,
        warningMessages: [String] = []
    ) {
        self.enhancedNote = enhancedNote
        self.backend = backend
        self.executionKind = executionKind
        self.warningMessages = warningMessages
    }
}

public enum SummaryPipelineError: LocalizedError, Equatable {
    case localRuntimeRequired(String)
    case backendUnavailable(String)
    case generationFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .localRuntimeRequired(message):
            message
        case let .backendUnavailable(message):
            message
        case let .generationFailed(message):
            message
        }
    }
}
