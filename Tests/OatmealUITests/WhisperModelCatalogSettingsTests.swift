import Foundation
import OatmealCore
import OatmealEdge
@testable import OatmealUI
import XCTest

@MainActor
final class WhisperModelCatalogSettingsTests: XCTestCase {
    func testWhisperCatalogStateIsRefreshedAfterLoadSystemState() async {
        let manager = WhisperModelCatalogStubManager()
        let model = makeModel(whisperModelManager: manager)

        XCTAssertNil(model.whisperModelCatalogState)
        await model.refreshWhisperModelCatalogState()

        let state = model.whisperModelCatalogState
        XCTAssertNotNil(state)
        XCTAssertEqual(state?.items.map(\.id), CuratedModelCatalog.curatedDefaults.map(\.id))
        XCTAssertEqual(manager.catalogStateInvocations, 1)
    }

    func testInstallWhisperModelDispatchesToManagerAndUpdatesCatalogState() async {
        let manager = WhisperModelCatalogStubManager()
        let model = makeModel(whisperModelManager: manager)

        await model.refreshWhisperModelCatalogState()

        let firstEntry = CuratedModelCatalog.curatedDefaults.first!
        manager.installResult = WhisperModelCatalogState(
            modelsDirectoryURL: FileManager.default.temporaryDirectory,
            items: CuratedModelCatalog.curatedDefaults.map { entry in
                WhisperModelCatalogItemState(
                    catalogEntry: entry,
                    installedModel: entry.id == firstEntry.id ? installedFixture(for: entry) : nil
                )
            }
        )

        model.installWhisperModel(firstEntry.id)
        await waitUntil { manager.installInvocations.contains(firstEntry.id) }
        await waitUntil { model.whisperModelCatalogState?.items.first { $0.id == firstEntry.id }?.installedModel != nil }

        XCTAssertNotNil(
            model.whisperModelCatalogState?.items.first(where: { $0.id == firstEntry.id })?.installedModel
        )
    }

    func testCancelWhisperModelInstallInvokesManagerCancel() async {
        let manager = WhisperModelCatalogStubManager()
        let model = makeModel(whisperModelManager: manager)

        let firstEntry = CuratedModelCatalog.curatedDefaults.first!
        model.cancelWhisperModelInstall(firstEntry.id)

        await waitUntil { manager.cancelInvocations.contains(firstEntry.id) }
        XCTAssertTrue(manager.cancelInvocations.contains(firstEntry.id))
    }

    func testRemoveWhisperModelDispatchesToManager() async {
        let manager = WhisperModelCatalogStubManager()
        let model = makeModel(whisperModelManager: manager)

        await model.refreshWhisperModelCatalogState()

        let firstEntry = CuratedModelCatalog.curatedDefaults.first!
        manager.removeResult = WhisperModelCatalogState(
            modelsDirectoryURL: FileManager.default.temporaryDirectory,
            items: CuratedModelCatalog.curatedDefaults.map {
                WhisperModelCatalogItemState(catalogEntry: $0, installedModel: nil)
            }
        )
        model.removeWhisperModel(firstEntry.id)

        await waitUntil { manager.removeInvocations.contains(firstEntry.id) }
        await waitUntil {
            model.whisperModelCatalogState?.items.allSatisfy { $0.installedModel == nil } ?? false
        }
        XCTAssertTrue(model.whisperModelCatalogState?.items.allSatisfy { $0.installedModel == nil } ?? false)
    }

    private func installedFixture(for entry: CuratedWhisperModelEntry) -> ManagedLocalModel {
        ManagedLocalModel(
            kind: .whisper,
            displayName: entry.displayName,
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(entry.id),
            sizeBytes: entry.sizeBytes,
            variant: entry.variant,
            sizeTier: entry.sizeTier
        )
    }

    private func waitUntil(timeout: TimeInterval = 2.0, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Condition not satisfied within \(timeout) seconds")
    }

    private func makeModel(
        whisperModelManager: any LocalWhisperModelManaging
    ) -> AppViewModel {
        let persistence = AppPersistence(
            applicationSupportFolderName: "OatmealWhisperModelCatalogTests-\(UUID().uuidString)",
            stateFileName: "state.json"
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: persistence.stateFileURL)
            try? FileManager.default.removeItem(at: persistence.applicationSupportDirectoryURL)
        }

        return AppViewModel(
            store: InMemoryOatmealStore(notes: []),
            calendarService: WhisperModelCatalogStubCalendarService(),
            captureService: WhisperModelCatalogStubCaptureAccessService(),
            captureEngine: WhisperModelCatalogStubCaptureEngine(),
            nativeMeetingDetectionService: WhisperModelCatalogNoopNativeMeetingDetectionService(),
            browserMeetingDetectionService: WhisperModelCatalogNoopBrowserMeetingDetectionService(),
            transcriptionService: WhisperModelCatalogStubTranscriptionService(),
            summaryService: WhisperModelCatalogStubSummaryService(),
            summaryModelManager: WhisperModelCatalogStubSummaryModelManager(),
            whisperModelManager: whisperModelManager,
            persistence: persistence,
            nowProvider: { Date(timeIntervalSince1970: 1_700_300_000) },
            liveTranscriptionPollingInterval: 10
        )
    }
}

@MainActor
private final class WhisperModelCatalogStubManager: LocalWhisperModelManaging {
    nonisolated(unsafe) var catalogStateInvocations = 0
    nonisolated(unsafe) var installInvocations: Set<String> = []
    nonisolated(unsafe) var cancelInvocations: Set<String> = []
    nonisolated(unsafe) var removeInvocations: Set<String> = []
    nonisolated(unsafe) var installResult: WhisperModelCatalogState?
    nonisolated(unsafe) var removeResult: WhisperModelCatalogState?

    func catalogState() async -> WhisperModelCatalogState {
        catalogStateInvocations += 1
        return defaultCatalogState()
    }

    func install(
        modelID: String,
        forceRedownload _: Bool,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> WhisperModelCatalogState {
        installInvocations.insert(modelID)
        progress(0.5)
        progress(1.0)
        return installResult ?? defaultCatalogState()
    }

    func cancelInstall(modelID: String) async {
        cancelInvocations.insert(modelID)
    }

    func remove(modelID: String) async throws -> WhisperModelCatalogState {
        removeInvocations.insert(modelID)
        return removeResult ?? defaultCatalogState()
    }

    private func defaultCatalogState() -> WhisperModelCatalogState {
        WhisperModelCatalogState(
            modelsDirectoryURL: FileManager.default.temporaryDirectory,
            items: CuratedModelCatalog.curatedDefaults.map {
                WhisperModelCatalogItemState(catalogEntry: $0, installedModel: nil)
            }
        )
    }
}

@MainActor
private final class WhisperModelCatalogNoopNativeMeetingDetectionService: NativeMeetingDetectionServicing {
    func start(onDetection _: @escaping @MainActor (PendingMeetingDetection) -> Void) {}
    func stop() {}
}

@MainActor
private final class WhisperModelCatalogNoopBrowserMeetingDetectionService: BrowserMeetingDetectionServicing {
    let capabilityState = BrowserDetectionCapabilityState(
        accessibilityTrusted: false,
        automationAvailability: .unknown
    )

    func start(onDetection _: @escaping @MainActor (PendingMeetingDetection) -> Void) {}
    func stop() {}
}

@MainActor
private final class WhisperModelCatalogStubCaptureEngine: MeetingCaptureEngineServing {
    private(set) var activeSession: ActiveCaptureSession?

    func startCapture(for noteID: UUID, mode: CaptureMode) async throws -> ActiveCaptureSession {
        let session = ActiveCaptureSession(
            noteID: noteID,
            startedAt: Date(timeIntervalSince1970: 1_700_300_400),
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(noteID.uuidString).m4a"),
            mode: mode
        )
        activeSession = session
        return session
    }

    func stopCapture() async throws -> CaptureArtifact {
        guard let session = activeSession else {
            throw CaptureEngineError.noActiveCapture
        }
        activeSession = nil
        return CaptureArtifact(
            noteID: session.noteID,
            fileURL: session.fileURL,
            startedAt: session.startedAt,
            endedAt: session.startedAt.addingTimeInterval(60),
            mode: session.mode
        )
    }

    func recordingURL(for noteID: UUID) -> URL? {
        activeSession?.noteID == noteID ? activeSession?.fileURL : nil
    }

    func liveTranscriptionChunks(for _: UUID) -> [LiveTranscriptionChunk] { [] }
    func runtimeHealthSnapshot(for _: UUID) -> CaptureRuntimeHealthSnapshot? { nil }
    func consumeRuntimeEvents(for _: UUID) -> [CaptureRuntimeEvent] { [] }
    func deleteRecording(for _: UUID) throws {}
}

private struct WhisperModelCatalogStubCalendarService: CalendarAccessServing {
    func authorizationStatus() -> PermissionStatus { .granted }
    func requestAccess() async -> PermissionStatus { .granted }
    func upcomingEvents(referenceDate _: Date, horizon _: TimeInterval) async throws -> [CalendarEvent] { [] }
}

private struct WhisperModelCatalogStubCaptureAccessService: CaptureAccessServing {
    func currentPermissions(calendarStatus: PermissionStatus) async -> CapturePermissions {
        CapturePermissions(
            microphone: .granted,
            systemAudio: .granted,
            notifications: .granted,
            calendar: calendarStatus
        )
    }

    func requestPermissions(requiresSystemAudio _: Bool, calendarStatus: PermissionStatus) async -> CapturePermissions {
        await currentPermissions(calendarStatus: calendarStatus)
    }
}

private struct WhisperModelCatalogStubTranscriptionService: LocalTranscriptionServicing {
    func runtimeState(configuration _: LocalTranscriptionConfiguration) async -> LocalTranscriptionRuntimeState {
        LocalTranscriptionRuntimeState(
            modelsDirectoryURL: FileManager.default.temporaryDirectory,
            discoveredModels: [],
            backends: [],
            activePlanSummary: "Stub transcription runtime"
        )
    }

    func executionPlan(configuration _: LocalTranscriptionConfiguration) async throws -> TranscriptionExecutionPlan {
        TranscriptionExecutionPlan(
            backend: .mock,
            executionKind: .placeholder,
            summary: "Stub transcription plan"
        )
    }

    func transcribe(
        request _: TranscriptionRequest,
        configuration _: LocalTranscriptionConfiguration
    ) async throws -> TranscriptionJobResult {
        TranscriptionJobResult(
            segments: [],
            backend: .mock,
            executionKind: .placeholder
        )
    }
}

private struct WhisperModelCatalogStubSummaryService: LocalSummaryServicing {
    func runtimeState(configuration _: LocalSummaryConfiguration) async -> LocalSummaryRuntimeState {
        LocalSummaryRuntimeState(
            modelsDirectoryURL: FileManager.default.temporaryDirectory,
            discoveredModels: [],
            backends: [],
            activePlanSummary: "Stub summary runtime"
        )
    }

    func executionPlan(configuration _: LocalSummaryConfiguration) async throws -> LocalSummaryExecutionPlan {
        LocalSummaryExecutionPlan(
            backend: .placeholder,
            executionKind: .placeholder,
            summary: "Stub summary plan"
        )
    }

    func generate(
        request _: NoteGenerationRequest,
        configuration _: LocalSummaryConfiguration
    ) async throws -> SummaryJobResult {
        SummaryJobResult(
            enhancedNote: EnhancedNote(summary: "Stub"),
            backend: .placeholder,
            executionKind: .placeholder
        )
    }
}

private struct WhisperModelCatalogStubSummaryModelManager: LocalSummaryModelManaging {
    func catalogState() async -> SummaryModelCatalogState {
        SummaryModelCatalogState(
            modelsDirectoryURL: FileManager.default.temporaryDirectory,
            downloadAvailability: .unavailable,
            downloadRuntimeDetail: "Stub summary catalog",
            items: []
        )
    }

    func install(modelID _: String, forceRedownload _: Bool) async throws -> SummaryModelCatalogState {
        await catalogState()
    }

    func remove(modelDirectoryURL _: URL) async throws -> SummaryModelCatalogState {
        await catalogState()
    }
}
