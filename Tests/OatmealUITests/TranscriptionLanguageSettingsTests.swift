import Foundation
import OatmealCore
import OatmealEdge
@testable import OatmealUI
import XCTest

@MainActor
final class TranscriptionLanguageSettingsTests: XCTestCase {
    func testCuratedLanguageListExposesPrimaryBCP47Codes() {
        let identifiers = OatmealSettingsView.curatedTranscriptionLanguages.map(\.identifier)
        let expected = [
            "en", "es", "pt", "fr", "de", "it", "nl", "pl",
            "ru", "tr", "ja", "ko", "zh", "ar", "hi"
        ]
        XCTAssertEqual(identifiers, expected)

        // Sanity-check display names so the picker renders human-readable
        // labels regardless of the underlying BCP 47 code.
        XCTAssertEqual(
            OatmealSettingsView.curatedTranscriptionLanguages.first(where: { $0.identifier == "es" })?.displayName,
            "Spanish"
        )
    }

    func testDefaultPreferredLocaleIdentifierIsNil() {
        let model = makeModel()
        XCTAssertNil(model.transcriptionConfiguration.preferredLocaleIdentifier)
    }

    func testSettingPreferredLocaleIdentifierWritesThroughToConfiguration() {
        let model = makeModel()

        model.setTranscriptionPreferredLocaleIdentifier("es")
        XCTAssertEqual(model.transcriptionConfiguration.preferredLocaleIdentifier, "es")

        model.setTranscriptionPreferredLocaleIdentifier("ja")
        XCTAssertEqual(model.transcriptionConfiguration.preferredLocaleIdentifier, "ja")
    }

    func testSettingPreferredLocaleIdentifierToNilRevertsToAutoDetect() {
        let model = makeModel()
        model.setTranscriptionPreferredLocaleIdentifier("pt")
        XCTAssertEqual(model.transcriptionConfiguration.preferredLocaleIdentifier, "pt")

        model.setTranscriptionPreferredLocaleIdentifier(nil)
        XCTAssertNil(model.transcriptionConfiguration.preferredLocaleIdentifier)
    }

    func testBlankPreferredLocaleIdentifierIsTreatedAsAutoDetect() {
        let model = makeModel()
        model.setTranscriptionPreferredLocaleIdentifier("fr")
        XCTAssertEqual(model.transcriptionConfiguration.preferredLocaleIdentifier, "fr")

        model.setTranscriptionPreferredLocaleIdentifier("   ")
        XCTAssertNil(model.transcriptionConfiguration.preferredLocaleIdentifier)
    }

    func testPreferredLocaleIdentifierPersistsAcrossRelaunch() {
        let persistence = makePersistence()
        addTeardownBlock { [persistence] in
            self.removePersistenceArtifacts(persistence)
        }

        let model = makeModel(persistence: persistence)
        model.setTranscriptionPreferredLocaleIdentifier("de")

        let restored = makeModel(persistence: persistence)
        XCTAssertEqual(restored.transcriptionConfiguration.preferredLocaleIdentifier, "de")
    }

    func testAutoDetectSelectionPersistsAsNilAcrossRelaunch() {
        let persistence = makePersistence()
        addTeardownBlock { [persistence] in
            self.removePersistenceArtifacts(persistence)
        }

        let model = makeModel(persistence: persistence)
        model.setTranscriptionPreferredLocaleIdentifier("ko")
        model.setTranscriptionPreferredLocaleIdentifier(nil)

        let restored = makeModel(persistence: persistence)
        XCTAssertNil(restored.transcriptionConfiguration.preferredLocaleIdentifier)
    }

    func testAppleSpeechRuntimeStatusIsDegradedWhenAutoDetectAndWhisperUnavailable() async {
        let transcriptionService = LanguageSettingsLocaleAwareTranscriptionService()
        let model = makeModel(transcriptionService: transcriptionService)
        model.setTranscriptionPreferredLocaleIdentifier(nil)

        await model.refreshTranscriptionRuntimeState()

        let runtimeState = model.transcriptionRuntimeState
        XCTAssertNotNil(runtimeState)

        let appleSpeechStatus = runtimeState?.backends.first(where: { $0.backend == .appleSpeech })
        XCTAssertNotNil(appleSpeechStatus)
        XCTAssertEqual(appleSpeechStatus?.availability, .degraded)
        XCTAssertTrue(
            (appleSpeechStatus?.detail ?? "")
                .localizedCaseInsensitiveContains("auto-detect"),
            "Apple Speech detail must mention auto-detect when running with no preferred locale; got: \(appleSpeechStatus?.detail ?? "<nil>")"
        )

        let whisperStatus = runtimeState?.backends.first(where: { $0.backend == .whisperCPPCLI })
        XCTAssertEqual(whisperStatus?.availability, .unavailable)
        XCTAssertFalse(whisperStatus?.isRunnable ?? true)
    }

    func testAppleSpeechRuntimeStatusIsAvailableWhenLanguageIsLocked() async {
        let transcriptionService = LanguageSettingsLocaleAwareTranscriptionService()
        let model = makeModel(transcriptionService: transcriptionService)
        model.setTranscriptionPreferredLocaleIdentifier("es")

        await model.refreshTranscriptionRuntimeState()

        let appleSpeechStatus = model.transcriptionRuntimeState?
            .backends
            .first(where: { $0.backend == .appleSpeech })
        XCTAssertEqual(appleSpeechStatus?.availability, .available)
        XCTAssertTrue(appleSpeechStatus?.isRunnable ?? false)
        XCTAssertFalse(
            (appleSpeechStatus?.detail ?? "")
                .localizedCaseInsensitiveContains("auto-detect"),
            "Apple Speech detail must not mention auto-detect when a language is locked; got: \(appleSpeechStatus?.detail ?? "<nil>")"
        )
    }

    private func makeModel(
        persistence: AppPersistence? = nil,
        transcriptionService: LocalTranscriptionServicing = LanguageSettingsStubTranscriptionService()
    ) -> AppViewModel {
        let persistence = persistence ?? makePersistence()
        if persistence.stateFileNameForTesting == "state.json" {
            addTeardownBlock { [persistence] in
                self.removePersistenceArtifacts(persistence)
            }
        }

        return AppViewModel(
            store: InMemoryOatmealStore(notes: []),
            calendarService: LanguageSettingsStubCalendarService(),
            captureService: LanguageSettingsStubCaptureAccessService(),
            captureEngine: LanguageSettingsStubCaptureEngine(),
            nativeMeetingDetectionService: LanguageSettingsNoopNativeMeetingDetectionService(),
            browserMeetingDetectionService: LanguageSettingsNoopBrowserMeetingDetectionService(),
            transcriptionService: transcriptionService,
            summaryService: LanguageSettingsStubSummaryService(),
            summaryModelManager: LanguageSettingsStubSummaryModelManager(),
            persistence: persistence,
            nowProvider: { Date(timeIntervalSince1970: 1_700_200_000) },
            liveTranscriptionPollingInterval: 10
        )
    }

    private func makePersistence() -> AppPersistence {
        AppPersistence(
            applicationSupportFolderName: "OatmealLanguageSettingsTests-\(UUID().uuidString)",
            stateFileName: "state.json"
        )
    }

    private func removePersistenceArtifacts(_ persistence: AppPersistence) {
        try? FileManager.default.removeItem(at: persistence.stateFileURL)
        try? FileManager.default.removeItem(at: persistence.applicationSupportDirectoryURL)
    }
}

@MainActor
private final class LanguageSettingsNoopNativeMeetingDetectionService: NativeMeetingDetectionServicing {
    func start(onDetection: @escaping @MainActor (PendingMeetingDetection) -> Void) {}
    func stop() {}
}

@MainActor
private final class LanguageSettingsNoopBrowserMeetingDetectionService: BrowserMeetingDetectionServicing {
    let capabilityState = BrowserDetectionCapabilityState(
        accessibilityTrusted: false,
        automationAvailability: .unknown
    )

    func start(onDetection: @escaping @MainActor (PendingMeetingDetection) -> Void) {}
    func stop() {}
}

@MainActor
private final class LanguageSettingsStubCaptureEngine: MeetingCaptureEngineServing {
    private(set) var activeSession: ActiveCaptureSession?

    func startCapture(for noteID: UUID, mode: CaptureMode) async throws -> ActiveCaptureSession {
        let session = ActiveCaptureSession(
            noteID: noteID,
            startedAt: Date(timeIntervalSince1970: 1_700_200_400),
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
            endedAt: session.startedAt.addingTimeInterval(120),
            mode: session.mode
        )
    }

    func recordingURL(for noteID: UUID) -> URL? {
        activeSession?.noteID == noteID ? activeSession?.fileURL : nil
    }

    func liveTranscriptionChunks(for noteID: UUID) -> [LiveTranscriptionChunk] { [] }
    func runtimeHealthSnapshot(for noteID: UUID) -> CaptureRuntimeHealthSnapshot? { nil }
    func consumeRuntimeEvents(for noteID: UUID) -> [CaptureRuntimeEvent] { [] }
    func deleteRecording(for noteID: UUID) throws {}
}

private struct LanguageSettingsStubCalendarService: CalendarAccessServing {
    func authorizationStatus() -> PermissionStatus { .granted }
    func requestAccess() async -> PermissionStatus { .granted }
    func upcomingEvents(referenceDate: Date, horizon: TimeInterval) async throws -> [CalendarEvent] { [] }
}

private struct LanguageSettingsStubCaptureAccessService: CaptureAccessServing {
    func currentPermissions(calendarStatus: PermissionStatus) async -> CapturePermissions {
        CapturePermissions(
            microphone: .granted,
            systemAudio: .granted,
            notifications: .granted,
            calendar: calendarStatus
        )
    }

    func requestPermissions(requiresSystemAudio: Bool, calendarStatus: PermissionStatus) async -> CapturePermissions {
        await currentPermissions(calendarStatus: calendarStatus)
    }
}

private struct LanguageSettingsStubTranscriptionService: LocalTranscriptionServicing {
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

/// Test transcription service that mirrors how the real
/// `LocalTranscriptionPipeline` computes Apple Speech availability based on
/// `preferredLocaleIdentifier`. Used to verify that the `.degraded` /
/// `auto-detect` hint flows out of `runtimeState(...)` to the UI without
/// needing a real `SFSpeechRecognizer`.
private struct LanguageSettingsLocaleAwareTranscriptionService: LocalTranscriptionServicing {
    func runtimeState(configuration: LocalTranscriptionConfiguration) async -> LocalTranscriptionRuntimeState {
        let whisperStatus = TranscriptionBackendStatus(
            backend: .whisperCPPCLI,
            displayName: "whisper.cpp",
            availability: .unavailable,
            detail: "whisper.cpp executable and models are not available in the test fixture.",
            isRunnable: false
        )

        let appleSpeechStatus: TranscriptionBackendStatus
        if configuration.preferredLocaleIdentifier == nil {
            appleSpeechStatus = TranscriptionBackendStatus(
                backend: .appleSpeech,
                displayName: "Apple Speech",
                availability: .degraded,
                detail: "Auto-detect requires Whisper. Apple Speech will run in the system locale (\(Locale.current.identifier)).",
                isRunnable: true
            )
        } else {
            appleSpeechStatus = TranscriptionBackendStatus(
                backend: .appleSpeech,
                displayName: "Apple Speech",
                availability: .available,
                detail: "System speech recognition is ready.",
                isRunnable: true
            )
        }

        return LocalTranscriptionRuntimeState(
            modelsDirectoryURL: FileManager.default.temporaryDirectory,
            discoveredModels: [],
            backends: [whisperStatus, appleSpeechStatus],
            activePlanSummary: "Apple Speech is the active transcription backend."
        )
    }

    func executionPlan(configuration: LocalTranscriptionConfiguration) async throws -> TranscriptionExecutionPlan {
        TranscriptionExecutionPlan(
            backend: .appleSpeech,
            executionKind: .systemService,
            summary: "Apple Speech is the active transcription backend."
        )
    }

    func transcribe(
        request: TranscriptionRequest,
        configuration: LocalTranscriptionConfiguration
    ) async throws -> TranscriptionJobResult {
        TranscriptionJobResult(
            segments: [],
            backend: .appleSpeech,
            executionKind: .systemService
        )
    }
}

private struct LanguageSettingsStubSummaryService: LocalSummaryServicing {
    func runtimeState(configuration: LocalSummaryConfiguration) async -> LocalSummaryRuntimeState {
        LocalSummaryRuntimeState(
            modelsDirectoryURL: FileManager.default.temporaryDirectory,
            discoveredModels: [],
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
            enhancedNote: EnhancedNote(summary: "Stub"),
            backend: .placeholder,
            executionKind: .placeholder
        )
    }
}

private struct LanguageSettingsStubSummaryModelManager: LocalSummaryModelManaging {
    func catalogState() async -> SummaryModelCatalogState {
        SummaryModelCatalogState(
            modelsDirectoryURL: FileManager.default.temporaryDirectory,
            downloadAvailability: .unavailable,
            downloadRuntimeDetail: "Stub model catalog",
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

private extension AppPersistence {
    var stateFileNameForTesting: String {
        stateFileURL.lastPathComponent
    }
}
