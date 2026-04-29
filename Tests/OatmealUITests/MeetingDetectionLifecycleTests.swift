import Foundation
import OatmealCore
import OatmealEdge
@testable import OatmealUI
import XCTest

@MainActor
final class MeetingDetectionLifecycleTests: XCTestCase {
    func testIgnoredPromptSuppressesRepeatedPromptForSameOngoingDetection() {
        let model = makeModel()

        var openedWindowIDs: [String] = []
        var dismissedWindowIDs: [String] = []
        model.bindLightweightSurfaceWindowActions(
            openWindow: { openedWindowIDs.append($0) },
            dismissWindow: { dismissedWindowIDs.append($0) }
        )

        model.receiveMeetingDetection(
            detectedMeeting(
                id: UUID(uuidString: "99111111-1111-2222-3333-444444444444")!,
                detectedAt: date(1_700_110_100)
            )
        )
        model.ignorePendingMeetingDetectionPrompt()
        model.receiveMeetingDetection(
            detectedMeeting(
                id: UUID(uuidString: "99222222-1111-2222-3333-444444444444")!,
                detectedAt: date(1_700_110_160)
            )
        )

        XCTAssertNil(model.detectionPromptState)
        XCTAssertEqual(model.menuBarMeetingDetectionState?.kind, .passiveSuggestion)
        XCTAssertEqual(model.pendingMeetingDetection?.presentation, .passiveSuggestion)
        XCTAssertEqual(model.pendingMeetingDetection?.promptWasDismissed, true)
        XCTAssertEqual(openedWindowIDs, [OatmealSceneID.meetingDetectionPrompt])
        XCTAssertEqual(dismissedWindowIDs, [OatmealSceneID.meetingDetectionPrompt])
    }

    func testRelaunchRestoresPassiveSuggestionWhenPromptWasIgnored() {
        let persistence = makePersistence()
        addTeardownBlock { [persistence] in
            self.removePersistenceArtifacts(persistence)
        }

        let model = makeModel(persistence: persistence)
        model.receiveMeetingDetection(
            detectedMeeting(
                id: UUID(uuidString: "99333333-1111-2222-3333-444444444444")!,
                detectedAt: date(1_700_110_200)
            )
        )
        model.ignorePendingMeetingDetectionPrompt()

        let restored = makeModel(persistence: persistence)

        XCTAssertNil(restored.detectionPromptState)
        XCTAssertEqual(restored.menuBarMeetingDetectionState?.kind, .passiveSuggestion)
        XCTAssertEqual(restored.pendingMeetingDetection?.presentation, .passiveSuggestion)
        XCTAssertEqual(restored.pendingMeetingDetection?.promptWasDismissed, true)
        XCTAssertEqual(restored.pendingMeetingDetection?.source, .browser("Google Chrome"))
    }

    func testRelaunchRestoresPendingPromptDetectionWhenMeetingWasStillAwaitingStart() {
        let persistence = makePersistence()
        addTeardownBlock { [persistence] in
            self.removePersistenceArtifacts(persistence)
        }

        let model = makeModel(persistence: persistence)
        model.receiveMeetingDetection(
            detectedMeeting(
                id: UUID(uuidString: "99444444-1111-2222-3333-444444444444")!,
                detectedAt: date(1_700_110_240)
            )
        )

        let restored = makeModel(persistence: persistence)

        XCTAssertEqual(restored.detectionPromptState?.kind, .prompt)
        XCTAssertEqual(restored.detectionPromptState?.title, "Untitled Meeting")
        XCTAssertEqual(restored.menuBarMeetingDetectionState?.kind, .prompt)
        XCTAssertEqual(restored.menuBarMeetingDetectionState?.secondaryActionTitle, "Not now")
        XCTAssertEqual(restored.pendingMeetingDetection?.presentation, .prompt)
        XCTAssertEqual(restored.pendingMeetingDetection?.source, .browser("Google Chrome"))
    }

    func testDetectedMeetingEndSuggestionDoesNotAutoStopActiveCapture() async {
        let startedAt = date(1_700_110_300)
        let calendarEvent = CalendarEvent(
            id: UUID(uuidString: "99555555-1111-2222-3333-444444444444")!,
            title: "Customer Call",
            startDate: startedAt.addingTimeInterval(-45 * 60),
            endDate: startedAt.addingTimeInterval(-5 * 60),
            source: .local
        )
        var note = MeetingNote(
            id: UUID(uuidString: "99666666-1111-2222-3333-444444444444")!,
            title: "Customer Call",
            origin: .calendarEvent(calendarEvent.id, createdAt: startedAt.addingTimeInterval(-45 * 60)),
            calendarEvent: calendarEvent,
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )
        note.captureState.beginCapture(at: startedAt.addingTimeInterval(-20 * 60))
        note.beginLiveSession(
            at: startedAt.addingTimeInterval(-20 * 60),
            presentTranscriptPanel: false,
            tracksSystemAudio: true
        )

        let captureEngine = MeetingDetectionLifecycleStubCaptureEngine(
            activeSession: ActiveCaptureSession(
                noteID: note.id,
                startedAt: startedAt.addingTimeInterval(-20 * 60),
                fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(note.id.uuidString).m4a"),
                mode: .systemAudioAndMicrophone
            )
        )
        let model = makeModel(
            notes: [note],
            captureEngine: captureEngine,
            nowProvider: { startedAt }
        )

        await model.loadSystemState()

        XCTAssertEqual(model.selectedNote?.captureState.phase, .capturing)

        let statusMessage = model.selectedNote?.liveSessionState.statusMessage?.lowercased() ?? ""
        let previewTexts = model.selectedNote?.liveSessionState.previewEntries.map { $0.text.lowercased() } ?? []
        let surfacedMeetingEndSuggestion = statusMessage.contains("ended")
            || statusMessage.contains("stop")
            || previewTexts.contains(where: { $0.contains("ended") || $0.contains("stop") })

        XCTAssertTrue(
            surfacedMeetingEndSuggestion,
            "Issue #21 should surface a non-destructive meeting-end suggestion while leaving capture active."
        )
    }

    private func makeModel(
        notes: [MeetingNote] = [],
        captureEngine: MeetingDetectionLifecycleStubCaptureEngine = MeetingDetectionLifecycleStubCaptureEngine(),
        persistence: AppPersistence? = nil,
        nowProvider: @escaping () -> Date = { Date(timeIntervalSince1970: 1_700_110_000) }
    ) -> AppViewModel {
        let persistence = persistence ?? makePersistence()

        return AppViewModel(
            store: InMemoryOatmealStore(notes: notes),
            calendarService: MeetingDetectionLifecycleStubCalendarService(),
            captureService: MeetingDetectionLifecycleStubCaptureAccessService(),
            captureEngine: captureEngine,
            nativeMeetingDetectionService: MeetingDetectionLifecycleNoopNativeDetectionService(),
            browserMeetingDetectionService: MeetingDetectionLifecycleNoopBrowserDetectionService(),
            transcriptionService: MeetingDetectionLifecycleStubTranscriptionService(),
            summaryService: MeetingDetectionLifecycleStubSummaryService(),
            summaryModelManager: MeetingDetectionLifecycleStubSummaryModelManager(),
            persistence: persistence,
            nowProvider: nowProvider,
            liveTranscriptionPollingInterval: 10
        )
    }

    private func makePersistence() -> AppPersistence {
        AppPersistence(
            applicationSupportFolderName: "OatmealMeetingDetectionLifecycleTests-\(UUID().uuidString)",
            stateFileName: "state.json"
        )
    }

    private func removePersistenceArtifacts(_ persistence: AppPersistence) {
        try? FileManager.default.removeItem(at: persistence.stateFileURL)
        try? FileManager.default.removeItem(at: persistence.applicationSupportDirectoryURL)
    }

    private func detectedMeeting(id: UUID, detectedAt: Date) -> PendingMeetingDetection {
        PendingMeetingDetection(
            id: id,
            title: "Untitled Meeting",
            source: .browser("Google Chrome"),
            detectedAt: detectedAt,
            presentation: .prompt
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}

@MainActor
private final class MeetingDetectionLifecycleNoopNativeDetectionService: NativeMeetingDetectionServicing {
    func start(onDetection: @escaping @MainActor (PendingMeetingDetection) -> Void) {}
    func stop() {}
}

@MainActor
private final class MeetingDetectionLifecycleNoopBrowserDetectionService: BrowserMeetingDetectionServicing {
    let capabilityState = BrowserDetectionCapabilityState(
        accessibilityTrusted: false,
        automationAvailability: .unknown
    )

    func start(onDetection: @escaping @MainActor (PendingMeetingDetection) -> Void) {}
    func stop() {}
}

@MainActor
private final class MeetingDetectionLifecycleStubCaptureEngine: MeetingCaptureEngineServing {
    var activeSession: ActiveCaptureSession?

    init(activeSession: ActiveCaptureSession? = nil) {
        self.activeSession = activeSession
    }

    func startCapture(for noteID: UUID, mode: CaptureMode) async throws -> ActiveCaptureSession {
        let session = ActiveCaptureSession(
            noteID: noteID,
            startedAt: Date(timeIntervalSince1970: 1_700_110_400),
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

    func liveTranscriptionChunks(for noteID: UUID) -> [LiveTranscriptionChunk] {
        []
    }

    func runtimeHealthSnapshot(for noteID: UUID) -> CaptureRuntimeHealthSnapshot? {
        nil
    }

    func consumeRuntimeEvents(for noteID: UUID) -> [CaptureRuntimeEvent] {
        []
    }

    func deleteRecording(for noteID: UUID) throws {}
}

@MainActor
private struct MeetingDetectionLifecycleStubCalendarService: CalendarAccessServing {
    func authorizationStatus() -> PermissionStatus { .granted }
    func requestAccess() async -> PermissionStatus { .granted }
    func upcomingEvents(referenceDate: Date, horizon: TimeInterval) async throws -> [CalendarEvent] { [] }
}

@MainActor
private struct MeetingDetectionLifecycleStubCaptureAccessService: CaptureAccessServing {
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

@MainActor
private struct MeetingDetectionLifecycleStubTranscriptionService: LocalTranscriptionServicing {
    func runtimeState(configuration: LocalTranscriptionConfiguration) async -> LocalTranscriptionRuntimeState {
        LocalTranscriptionRuntimeState(
            modelsDirectoryURL: FileManager.default.temporaryDirectory,
            discoveredModels: [],
            backends: [],
            activePlanSummary: "Placeholder transcription is ready."
        )
    }

    func executionPlan(configuration: LocalTranscriptionConfiguration) async throws -> TranscriptionExecutionPlan {
        TranscriptionExecutionPlan(
            backend: .mock,
            executionKind: .placeholder,
            summary: "Placeholder transcription"
        )
    }

    func transcribe(request: TranscriptionRequest, configuration: LocalTranscriptionConfiguration) async throws -> TranscriptionJobResult {
        TranscriptionJobResult(
            segments: [],
            backend: .mock,
            executionKind: .placeholder
        )
    }
}

@MainActor
private struct MeetingDetectionLifecycleStubSummaryService: LocalSummaryServicing {
    func runtimeState(configuration: LocalSummaryConfiguration) async -> LocalSummaryRuntimeState {
        LocalSummaryRuntimeState(
            modelsDirectoryURL: FileManager.default.temporaryDirectory,
            discoveredModels: [],
            backends: [],
            activePlanSummary: "Placeholder summary is ready."
        )
    }

    func executionPlan(configuration: LocalSummaryConfiguration) async throws -> LocalSummaryExecutionPlan {
        LocalSummaryExecutionPlan(
            backend: .placeholder,
            executionKind: .placeholder,
            summary: "Placeholder summary"
        )
    }

    func generate(request: NoteGenerationRequest, configuration: LocalSummaryConfiguration) async throws -> SummaryJobResult {
        SummaryJobResult(
            enhancedNote: EnhancedNote(summary: "Placeholder"),
            backend: .placeholder,
            executionKind: .placeholder
        )
    }
}

@MainActor
private struct MeetingDetectionLifecycleStubSummaryModelManager: LocalSummaryModelManaging {
    func catalogState() async -> SummaryModelCatalogState {
        SummaryModelCatalogState(
            modelsDirectoryURL: FileManager.default.temporaryDirectory,
            downloadAvailability: .available,
            downloadRuntimeDetail: "Placeholder summary models are available.",
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
