import Foundation
import OatmealCore
import OatmealEdge
@testable import OatmealUI
import XCTest

@MainActor
class AIWorkspaceTestCase: XCTestCase {
    func makeModel(
        notes: [MeetingNote],
        persistence: AppPersistence,
        assistantService: any SingleMeetingAssistantServicing,
        nowProvider: @escaping () -> Date
    ) -> AppViewModel {
        AppViewModel(
            store: InMemoryOatmealStore(notes: notes),
            calendarService: AIWorkspaceStubCalendarService(),
            captureService: AIWorkspaceStubCaptureAccessService(),
            captureEngine: AIWorkspaceStubCaptureEngine(),
            nativeMeetingDetectionService: AIWorkspaceNoopNativeMeetingDetectionService(),
            browserMeetingDetectionService: AIWorkspaceNoopBrowserMeetingDetectionService(),
            transcriptionService: AIWorkspaceStubTranscriptionService(),
            summaryService: AIWorkspaceStubSummaryService(),
            summaryModelManager: AIWorkspaceStubSummaryModelManager(),
            persistence: persistence,
            nowProvider: nowProvider,
            assistantService: assistantService
        )
    }

    func makePersistence() -> AppPersistence {
        AppPersistence(
            applicationSupportFolderName: "OatmealAIWorkspaceTests-\(UUID().uuidString)",
            stateFileName: "state.json"
        )
    }

    func removePersistenceArtifacts(_ persistence: AppPersistence) {
        try? FileManager.default.removeItem(at: persistence.stateFileURL)
        try? FileManager.default.removeItem(at: persistence.applicationSupportDirectoryURL)
    }

    func waitUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        pollNanoseconds: UInt64 = 20_000_000,
        predicate: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            if predicate() {
                return true
            }
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
        return predicate()
    }

    func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}

@MainActor
struct AIWorkspaceStubCalendarService: CalendarAccessServing {
    func authorizationStatus() -> PermissionStatus { .granted }
    func requestAccess() async -> PermissionStatus { .granted }
    func upcomingEvents(referenceDate: Date, horizon: TimeInterval) async throws -> [CalendarEvent] { [] }
}

@MainActor
struct AIWorkspaceStubCaptureAccessService: CaptureAccessServing {
    func currentPermissions(calendarStatus: PermissionStatus) async -> CapturePermissions {
        .aiWorkspaceFullyGranted(calendar: calendarStatus)
    }

    func requestPermissions(requiresSystemAudio: Bool, calendarStatus: PermissionStatus) async -> CapturePermissions {
        .aiWorkspaceFullyGranted(calendar: calendarStatus)
    }
}

@MainActor
final class AIWorkspaceStubCaptureEngine: MeetingCaptureEngineServing {
    var activeSession: ActiveCaptureSession?

    func startCapture(for noteID: UUID, mode: CaptureMode) async throws -> ActiveCaptureSession {
        throw CaptureEngineError.failedToStartRecording("Not needed for AI workspace tests.")
    }

    func stopCapture() async throws -> CaptureArtifact {
        throw CaptureEngineError.noActiveCapture
    }

    func recordingURL(for noteID: UUID) -> URL? { nil }
    func liveTranscriptionChunks(for noteID: UUID) -> [LiveTranscriptionChunk] { [] }
    func runtimeHealthSnapshot(for noteID: UUID) -> CaptureRuntimeHealthSnapshot? { nil }
    func consumeRuntimeEvents(for noteID: UUID) -> [CaptureRuntimeEvent] { [] }
    func deleteRecording(for noteID: UUID) throws {}
}

@MainActor
final class AIWorkspaceNoopNativeMeetingDetectionService: NativeMeetingDetectionServicing {
    func start(onDetection: @escaping @MainActor (PendingMeetingDetection) -> Void) {}
    func stop() {}
}

@MainActor
final class AIWorkspaceNoopBrowserMeetingDetectionService: BrowserMeetingDetectionServicing {
    func start(onDetection: @escaping @MainActor (PendingMeetingDetection) -> Void) {}
    func stop() {}
}

struct AIWorkspaceStubTranscriptionService: LocalTranscriptionServicing {
    func runtimeState(configuration: LocalTranscriptionConfiguration) async -> LocalTranscriptionRuntimeState {
        LocalTranscriptionRuntimeState(
            modelsDirectoryURL: FileManager.default.temporaryDirectory,
            discoveredModels: [],
            backends: [],
            activePlanSummary: "Stub transcription runtime"
        )
    }

    func executionPlan(configuration: LocalTranscriptionConfiguration) async throws -> TranscriptionExecutionPlan {
        TranscriptionExecutionPlan(
            backend: .mock,
            executionKind: .placeholder,
            summary: "Stub transcription plan"
        )
    }

    func transcribe(
        request: TranscriptionRequest,
        configuration: LocalTranscriptionConfiguration
    ) async throws -> TranscriptionJobResult {
        TranscriptionJobResult(
            segments: [],
            backend: .mock,
            executionKind: .placeholder
        )
    }
}

struct AIWorkspaceStubSummaryService: LocalSummaryServicing {
    func runtimeState(configuration: LocalSummaryConfiguration) async -> LocalSummaryRuntimeState {
        LocalSummaryRuntimeState(
            modelsDirectoryURL: FileManager.default.temporaryDirectory,
            discoveredModels: [],
            preferredModelName: nil,
            backends: [],
            activePlanSummary: "Stub summary runtime"
        )
    }

    func executionPlan(configuration: LocalSummaryConfiguration) async throws -> LocalSummaryExecutionPlan {
        LocalSummaryExecutionPlan(
            backend: .placeholder,
            executionKind: .placeholder,
            summary: "Stub summary plan"
        )
    }

    func generate(request: NoteGenerationRequest, configuration: LocalSummaryConfiguration) async throws -> SummaryJobResult {
        SummaryJobResult(
            enhancedNote: EnhancedNote(summary: "Stub summary"),
            backend: .placeholder,
            executionKind: .placeholder
        )
    }
}

struct AIWorkspaceStubSummaryModelManager: LocalSummaryModelManaging {
    func catalogState() async -> SummaryModelCatalogState {
        SummaryModelCatalogState(
            modelsDirectoryURL: FileManager.default.temporaryDirectory,
            downloadAvailability: .unavailable,
            downloadRuntimeDetail: "Stub summary model catalog",
            items: []
        )
    }

    func install(modelID: String, forceRedownload: Bool) async throws -> SummaryModelCatalogState {
        await catalogState()
    }

    func remove(modelDirectoryURL: URL) async throws -> SummaryModelCatalogState {
        await catalogState()
    }
}

actor StubSingleMeetingAssistantService: SingleMeetingAssistantServicing {
    enum Mode {
        case success(String, [NoteAssistantCitation] = [])
        case failure(String)
        case sequence([Mode])
    }

    private var mode: Mode
    private let responseDelayNanoseconds: UInt64

    init(
        mode: Mode,
        responseDelayNanoseconds: UInt64 = 0
    ) {
        self.mode = mode
        self.responseDelayNanoseconds = responseDelayNanoseconds
    }

    func respond(to request: SingleMeetingAssistantRequest) async throws -> SingleMeetingAssistantResponse {
        if responseDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: responseDelayNanoseconds)
        }

        let currentMode = dequeueMode()

        switch currentMode {
        case let .success(text, citations):
            return SingleMeetingAssistantResponse(
                text: text,
                citations: citations,
                generatedAt: Date(timeIntervalSince1970: 1_700_999_999)
            )
        case let .failure(message):
            throw SingleMeetingAssistantError.failed(message)
        case .sequence:
            throw SingleMeetingAssistantError.failed("Sequence mode must dequeue to a concrete result.")
        }
    }

    private func dequeueMode() -> Mode {
        switch mode {
        case let .sequence(steps):
            guard let first = steps.first else {
                return .failure("No stubbed assistant response remained.")
            }
            let remaining = Array(steps.dropFirst())
            mode = remaining.isEmpty ? first : .sequence(remaining)
            return first
        case let concreteMode:
            return concreteMode
        }
    }
}

extension CapturePermissions {
    static func aiWorkspaceFullyGranted(calendar: PermissionStatus) -> CapturePermissions {
        CapturePermissions(
            microphone: .granted,
            systemAudio: .granted,
            notifications: .granted,
            calendar: calendar
        )
    }
}
