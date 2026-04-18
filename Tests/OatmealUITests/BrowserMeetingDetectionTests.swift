import Foundation
import OatmealCore
import OatmealEdge
@testable import OatmealUI
import XCTest

@MainActor
final class BrowserMeetingDetectionTests: XCTestCase {
    func testLiveServiceEmitsPromptForSupportedBrowserWhenMicrophoneActivityAppears() {
        let workspace = FakeBrowserMeetingWorkspace()
        workspace.frontmostApplication = NativeMeetingRunningApplication(
            bundleIdentifier: "com.google.Chrome",
            localizedName: "Google Chrome"
        )
        let activityMonitor = FakeBrowserMeetingActivityMonitor()
        let service = LiveBrowserMeetingDetectionService(
            workspace: workspace,
            activityMonitor: activityMonitor,
            supportedBrowsers: SupportedMeetingBrowser.defaults,
            nowProvider: { Date(timeIntervalSince1970: 1_700_080_000) }
        )

        var detections: [PendingMeetingDetection] = []
        service.start { detections.append($0) }
        activityMonitor.emit(
            BrowserMeetingActivitySnapshot(
                isMicrophoneActive: true,
                isSystemAudioActive: true,
                capturedAt: Date(timeIntervalSince1970: 1_700_080_010)
            )
        )

        XCTAssertEqual(detections.count, 1)
        XCTAssertEqual(detections.first?.source, .browser("Google Chrome"))
        XCTAssertEqual(detections.first?.presentation, .prompt)
    }

    func testLiveServiceEmitsPassiveSuggestionWhenOnlySystemAudioLooksMeetingLike() {
        let workspace = FakeBrowserMeetingWorkspace()
        workspace.frontmostApplication = NativeMeetingRunningApplication(
            bundleIdentifier: "com.apple.Safari",
            localizedName: "Safari"
        )
        let activityMonitor = FakeBrowserMeetingActivityMonitor()
        let service = LiveBrowserMeetingDetectionService(
            workspace: workspace,
            activityMonitor: activityMonitor,
            supportedBrowsers: SupportedMeetingBrowser.defaults,
            nowProvider: { Date(timeIntervalSince1970: 1_700_080_020) }
        )

        var detections: [PendingMeetingDetection] = []
        service.start { detections.append($0) }
        activityMonitor.emit(
            BrowserMeetingActivitySnapshot(
                isMicrophoneActive: false,
                isSystemAudioActive: true,
                capturedAt: Date(timeIntervalSince1970: 1_700_080_030)
            )
        )

        XCTAssertEqual(detections.count, 1)
        XCTAssertEqual(detections.first?.source, .browser("Safari"))
        XCTAssertEqual(detections.first?.presentation, .passiveSuggestion)
    }

    func testLiveServiceEscalatesSameBrowserFromPassiveToPromptWhenMicrophoneTurnsOn() {
        let workspace = FakeBrowserMeetingWorkspace()
        workspace.frontmostApplication = NativeMeetingRunningApplication(
            bundleIdentifier: "company.thebrowser.Browser",
            localizedName: "Arc"
        )
        let activityMonitor = FakeBrowserMeetingActivityMonitor()
        let service = LiveBrowserMeetingDetectionService(
            workspace: workspace,
            activityMonitor: activityMonitor,
            supportedBrowsers: SupportedMeetingBrowser.defaults,
            nowProvider: { Date(timeIntervalSince1970: 1_700_080_040) }
        )

        var detections: [PendingMeetingDetection] = []
        service.start { detections.append($0) }
        activityMonitor.emit(
            BrowserMeetingActivitySnapshot(
                isMicrophoneActive: false,
                isSystemAudioActive: true,
                capturedAt: Date(timeIntervalSince1970: 1_700_080_050)
            )
        )
        activityMonitor.emit(
            BrowserMeetingActivitySnapshot(
                isMicrophoneActive: true,
                isSystemAudioActive: true,
                capturedAt: Date(timeIntervalSince1970: 1_700_080_060)
            )
        )

        XCTAssertEqual(detections.count, 2)
        XCTAssertEqual(detections.first?.presentation, .passiveSuggestion)
        XCTAssertEqual(detections.last?.presentation, .prompt)
        XCTAssertEqual(detections.last?.source, .browser("Arc"))
    }

    func testLoadSystemStateStartsBrowserDetectionAndRoutesPromptIntoPromptShell() async {
        let detectionService = StubBrowserMeetingDetectionService()
        let model = makeModel(browserMeetingDetectionService: detectionService)

        var openedWindowIDs: [String] = []
        var dismissedWindowIDs: [String] = []
        model.bindLightweightSurfaceWindowActions(
            openWindow: { openedWindowIDs.append($0) },
            dismissWindow: { dismissedWindowIDs.append($0) }
        )

        await model.loadSystemState()
        detectionService.emit(
            PendingMeetingDetection(
                id: UUID(uuidString: "B0000000-1234-5678-90AB-1234567890AB")!,
                title: "Untitled Meeting",
                source: .browser("Google Chrome"),
                detectedAt: date(1_700_080_100),
                presentation: .prompt
            )
        )

        XCTAssertEqual(detectionService.startCalls, 1)
        XCTAssertEqual(model.pendingMeetingDetection?.source, .browser("Google Chrome"))
        XCTAssertEqual(model.detectionPromptState?.sourceKind, .browser)
        XCTAssertEqual(model.detectionPromptState?.sourceName, "Google Chrome")
        XCTAssertEqual(openedWindowIDs, [OatmealSceneID.meetingDetectionPrompt])
        XCTAssertTrue(dismissedWindowIDs.isEmpty)
    }

    func testBrowserAutoDetectionSurfacesPromptThenStartsCaptureThroughExistingFlow() async {
        let detectionService = StubBrowserMeetingDetectionService()
        let captureEngine = BrowserDetectionStubCaptureEngine()
        let model = makeModel(
            browserMeetingDetectionService: detectionService,
            captureEngine: captureEngine
        )

        var openedWindowIDs: [String] = []
        var dismissedWindowIDs: [String] = []
        let coordinator = SessionControllerSceneCoordinator(
            openWindow: { openedWindowIDs.append($0) },
            dismissWindow: { dismissedWindowIDs.append($0) }
        )
        model.bindLightweightSurfaceWindowActions(
            openWindow: { openedWindowIDs.append($0) },
            dismissWindow: { dismissedWindowIDs.append($0) }
        )

        await model.loadSystemState()
        detectionService.emit(
            PendingMeetingDetection(
                id: UUID(uuidString: "B0000000-1234-5678-90AB-1234567890AC")!,
                title: "Untitled Meeting",
                source: .browser("Google Chrome"),
                detectedAt: date(1_700_080_110),
                presentation: .prompt
            )
        )

        XCTAssertEqual(model.detectionPromptState?.sourceKind, .browser)
        XCTAssertNil(model.sessionControllerState)

        await model.startPendingMeetingDetectionCapture()
        coordinator.syncSessionControllerWindow(with: model)

        XCTAssertEqual(captureEngine.startCalls, 1)
        XCTAssertNil(model.pendingMeetingDetection)
        XCTAssertNil(model.detectionPromptState)
        XCTAssertEqual(model.selectedNote?.title, "Untitled Meeting")
        XCTAssertEqual(model.selectedNote?.captureState.phase, .capturing)
        XCTAssertEqual(model.sessionControllerState?.kind, .active)
        XCTAssertEqual(
            openedWindowIDs,
            [OatmealSceneID.meetingDetectionPrompt, OatmealSceneID.sessionController]
        )
        XCTAssertEqual(dismissedWindowIDs, [OatmealSceneID.meetingDetectionPrompt])
    }

    func testIgnoredBrowserPromptRemainsPassiveWhenSameMeetingBecomesHighConfidenceAgain() async {
        let detectionService = StubBrowserMeetingDetectionService()
        let model = makeModel(browserMeetingDetectionService: detectionService)

        await model.loadSystemState()
        let detectedAt = date(1_700_080_120)
        detectionService.emit(
            PendingMeetingDetection(
                id: UUID(uuidString: "B0000000-1234-5678-90AB-1234567890AD")!,
                title: "Untitled Meeting",
                source: .browser("Google Chrome"),
                detectedAt: detectedAt,
                presentation: .prompt
            )
        )

        model.ignorePendingMeetingDetectionPrompt()
        XCTAssertNil(model.detectionPromptState)
        XCTAssertEqual(model.menuBarMeetingDetectionState?.kind, .passiveSuggestion)

        detectionService.emit(
            PendingMeetingDetection(
                id: UUID(uuidString: "B0000000-1234-5678-90AB-1234567890AE")!,
                title: "Untitled Meeting",
                source: .browser("Google Chrome"),
                detectedAt: detectedAt.addingTimeInterval(10),
                presentation: .prompt
            )
        )

        XCTAssertNil(model.detectionPromptState)
        XCTAssertEqual(model.menuBarMeetingDetectionState?.kind, .passiveSuggestion)
    }

    func testBrowserPassiveSuggestionCanUpgradeToPromptBeforeUserDismissesIt() async {
        let detectionService = StubBrowserMeetingDetectionService()
        let model = makeModel(browserMeetingDetectionService: detectionService)

        await model.loadSystemState()
        detectionService.emit(
            PendingMeetingDetection(
                id: UUID(uuidString: "B0000000-1234-5678-90AB-1234567890AF")!,
                title: "Untitled Meeting",
                source: .browser("Safari"),
                detectedAt: date(1_700_080_130),
                presentation: .passiveSuggestion
            )
        )

        XCTAssertNil(model.detectionPromptState)
        XCTAssertEqual(model.menuBarMeetingDetectionState?.kind, .passiveSuggestion)

        detectionService.emit(
            PendingMeetingDetection(
                id: UUID(uuidString: "B0000000-1234-5678-90AB-1234567890B0")!,
                title: "Untitled Meeting",
                source: .browser("Safari"),
                detectedAt: date(1_700_080_135),
                presentation: .prompt
            )
        )

        XCTAssertEqual(model.detectionPromptState?.kind, .prompt)
        XCTAssertEqual(model.detectionPromptState?.sourceName, "Safari")
    }

    func testActiveRecordingSuppressesOverlappingBrowserDetections() async {
        let startedAt = date(1_700_080_200)
        var note = MeetingNote(
            id: UUID(uuidString: "BEEF0000-1111-2222-3333-444455556666")!,
            title: "Already Recording",
            origin: .quickNote(createdAt: startedAt),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )
        note.captureState.beginCapture(at: startedAt)
        note.beginLiveSession(at: startedAt, presentTranscriptPanel: false, tracksSystemAudio: true)

        let detectionService = StubBrowserMeetingDetectionService()
        let captureEngine = BrowserDetectionStubCaptureEngine(
            activeSession: ActiveCaptureSession(
                noteID: note.id,
                startedAt: startedAt,
                fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(note.id.uuidString).m4a"),
                mode: .systemAudioAndMicrophone
            )
        )
        let model = makeModel(
            notes: [note],
            browserMeetingDetectionService: detectionService,
            captureEngine: captureEngine
        )

        await model.loadSystemState()
        detectionService.emit(
            PendingMeetingDetection(
                id: UUID(uuidString: "B0000000-1234-5678-90AB-1234567890B1")!,
                title: "Untitled Meeting",
                source: .browser("Google Chrome"),
                detectedAt: date(1_700_080_210),
                presentation: .prompt
            )
        )

        XCTAssertNil(model.pendingMeetingDetection)
        XCTAssertNil(model.detectionPromptState)
        XCTAssertEqual(model.sessionControllerState?.kind, .active)
    }

    private func makeModel(
        notes: [MeetingNote] = [],
        browserMeetingDetectionService: BrowserMeetingDetectionServicing,
        captureEngine: BrowserDetectionStubCaptureEngine = BrowserDetectionStubCaptureEngine()
    ) -> AppViewModel {
        let persistence = AppPersistence(
            applicationSupportFolderName: "OatmealBrowserMeetingDetectionTests-\(UUID().uuidString)",
            stateFileName: "state.json"
        )

        let model = AppViewModel(
            store: InMemoryOatmealStore(notes: notes),
            calendarService: BrowserDetectionStubCalendarService(),
            captureService: BrowserDetectionStubCaptureAccessService(),
            captureEngine: captureEngine,
            nativeMeetingDetectionService: NoopNativeMeetingDetectionService(),
            browserMeetingDetectionService: browserMeetingDetectionService,
            transcriptionService: BrowserDetectionStubTranscriptionService(),
            summaryService: BrowserDetectionStubSummaryService(),
            summaryModelManager: BrowserDetectionStubSummaryModelManager(),
            persistence: persistence,
            nowProvider: { Date(timeIntervalSince1970: 1_700_080_090) }
        )

        model.selectedNoteID = notes.first?.id
        return model
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}

@MainActor
private final class FakeBrowserMeetingWorkspace: NativeMeetingApplicationWorkspace {
    var frontmostApplication: NativeMeetingRunningApplication?
    private var handler: (@MainActor (NativeMeetingRunningApplication?) -> Void)?

    func observeActivation(_ handler: @escaping @MainActor (NativeMeetingRunningApplication?) -> Void) -> AnyObject {
        self.handler = handler
        return NSObject()
    }

    func removeObserver(_ token: AnyObject) {
        handler = nil
    }

    func simulateActivation(_ application: NativeMeetingRunningApplication?) {
        frontmostApplication = application
        handler?(application)
    }
}

@MainActor
private final class FakeBrowserMeetingActivityMonitor: BrowserMeetingActivityMonitoring {
    private var handler: (@MainActor (BrowserMeetingActivitySnapshot) -> Void)?

    func start(onUpdate: @escaping @MainActor (BrowserMeetingActivitySnapshot) -> Void) {
        handler = onUpdate
    }

    func stop() {
        handler = nil
    }

    func emit(_ snapshot: BrowserMeetingActivitySnapshot) {
        handler?(snapshot)
    }
}

@MainActor
private final class NoopNativeMeetingDetectionService: NativeMeetingDetectionServicing {
    func start(onDetection: @escaping @MainActor (PendingMeetingDetection) -> Void) {}
    func stop() {}
}

@MainActor
private final class StubBrowserMeetingDetectionService: BrowserMeetingDetectionServicing {
    private var handler: (@MainActor (PendingMeetingDetection) -> Void)?
    private(set) var startCalls = 0

    func start(onDetection: @escaping @MainActor (PendingMeetingDetection) -> Void) {
        startCalls += 1
        handler = onDetection
    }

    func stop() {}

    func emit(_ detection: PendingMeetingDetection) {
        handler?(detection)
    }
}

@MainActor
private final class BrowserDetectionStubCaptureEngine: MeetingCaptureEngineServing {
    private(set) var activeSession: ActiveCaptureSession?
    private(set) var startCalls = 0
    private(set) var stopCalls = 0

    init(activeSession: ActiveCaptureSession? = nil) {
        self.activeSession = activeSession
    }

    func startCapture(for noteID: UUID, mode: CaptureMode) async throws -> ActiveCaptureSession {
        startCalls += 1
        let session = ActiveCaptureSession(
            noteID: noteID,
            startedAt: Date(timeIntervalSince1970: 1_700_080_140),
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(noteID.uuidString).m4a"),
            mode: mode
        )
        activeSession = session
        return session
    }

    func stopCapture() async throws -> CaptureArtifact {
        stopCalls += 1
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
private struct BrowserDetectionStubCalendarService: CalendarAccessServing {
    func authorizationStatus() -> PermissionStatus { .granted }
    func requestAccess() async -> PermissionStatus { .granted }
    func upcomingEvents(referenceDate: Date, horizon: TimeInterval) async throws -> [CalendarEvent] { [] }
}

@MainActor
private struct BrowserDetectionStubCaptureAccessService: CaptureAccessServing {
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
private struct BrowserDetectionStubTranscriptionService: LocalTranscriptionServicing {
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
private struct BrowserDetectionStubSummaryService: LocalSummaryServicing {
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
private struct BrowserDetectionStubSummaryModelManager: LocalSummaryModelManaging {
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
