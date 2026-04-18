import Foundation
import OatmealCore
import OatmealEdge
@testable import OatmealUI
import XCTest

@MainActor
final class NativeMeetingDetectionTests: XCTestCase {
    func testLiveServiceEmitsDetectionForSupportedFrontmostAppOnStart() {
        let workspace = FakeNativeMeetingWorkspace()
        workspace.frontmostApplication = NativeMeetingRunningApplication(
            bundleIdentifier: "us.zoom.xos",
            localizedName: "zoom.us"
        )

        let service = LiveNativeMeetingDetectionService(
            workspace: workspace,
            supportedApps: SupportedNativeMeetingApp.defaults,
            nowProvider: { Date(timeIntervalSince1970: 1_700_060_000) }
        )

        var detections: [PendingMeetingDetection] = []
        service.start { detections.append($0) }

        XCTAssertEqual(detections.count, 1)
        XCTAssertEqual(detections.first?.title, "Untitled Meeting")
        XCTAssertEqual(detections.first?.source, .nativeApp("Zoom"))
        XCTAssertEqual(detections.first?.presentation, .prompt)
    }

    func testLiveServiceSuppressesDuplicateActivationForSameSupportedAppUntilContextChanges() {
        let workspace = FakeNativeMeetingWorkspace()
        let service = LiveNativeMeetingDetectionService(
            workspace: workspace,
            supportedApps: SupportedNativeMeetingApp.defaults,
            nowProvider: { Date(timeIntervalSince1970: 1_700_060_100) }
        )

        var detections: [PendingMeetingDetection] = []
        service.start { detections.append($0) }

        workspace.simulateActivation(
            NativeMeetingRunningApplication(
                bundleIdentifier: "com.microsoft.teams2",
                localizedName: "Microsoft Teams"
            )
        )
        workspace.simulateActivation(
            NativeMeetingRunningApplication(
                bundleIdentifier: "com.microsoft.teams2",
                localizedName: "Microsoft Teams"
            )
        )

        XCTAssertEqual(detections.count, 1)
        XCTAssertEqual(detections.first?.source, .nativeApp("Microsoft Teams"))

        workspace.simulateActivation(
            NativeMeetingRunningApplication(
                bundleIdentifier: "com.apple.TextEdit",
                localizedName: "TextEdit"
            )
        )
        workspace.simulateActivation(
            NativeMeetingRunningApplication(
                bundleIdentifier: "com.microsoft.teams2",
                localizedName: "Microsoft Teams"
            )
        )

        XCTAssertEqual(detections.count, 3)
        XCTAssertEqual(detections[1].phase, .endSuggestion)
        XCTAssertEqual(detections[1].source, .nativeApp("Microsoft Teams"))
        XCTAssertEqual(detections[2].phase, .start)
        XCTAssertEqual(detections[2].source, .nativeApp("Microsoft Teams"))
    }

    func testLoadSystemStateStartsNativeDetectionAndRoutesDetectionIntoPromptShell() async {
        let detectionService = StubNativeMeetingDetectionService()
        let model = makeModel(
            notes: [],
            nativeMeetingDetectionService: detectionService
        )

        await model.loadSystemState()
        detectionService.emit(
            PendingMeetingDetection(
                id: UUID(uuidString: "11112222-3333-4444-5555-666677778888")!,
                title: "Untitled Meeting",
                source: .nativeApp("Zoom"),
                detectedAt: date(1_700_060_200),
                presentation: .prompt
            )
        )

        XCTAssertEqual(detectionService.startCalls, 1)
        XCTAssertEqual(model.pendingMeetingDetection?.source, .nativeApp("Zoom"))
        XCTAssertEqual(model.detectionPromptState?.title, "Untitled Meeting")
        XCTAssertEqual(model.detectionPromptState?.sourceName, "Zoom")
        XCTAssertNil(model.sessionControllerState)
    }

    func testServiceDrivenNativeDetectionOpensPromptWindowWhenLightweightActionsAreBound() async {
        let detectionService = StubNativeMeetingDetectionService()
        let model = makeModel(
            notes: [],
            nativeMeetingDetectionService: detectionService
        )

        var openedWindowIDs: [String] = []
        var dismissedWindowIDs: [String] = []
        model.bindLightweightSurfaceWindowActions(
            openWindow: { openedWindowIDs.append($0) },
            dismissWindow: { dismissedWindowIDs.append($0) }
        )

        await model.loadSystemState()
        detectionService.emit(
            PendingMeetingDetection(
                id: UUID(uuidString: "12121212-3333-4444-5555-666677778888")!,
                title: "Untitled Meeting",
                source: .nativeApp("Zoom"),
                detectedAt: date(1_700_060_210),
                presentation: .prompt
            )
        )

        XCTAssertEqual(openedWindowIDs, [OatmealSceneID.meetingDetectionPrompt])
        XCTAssertTrue(dismissedWindowIDs.isEmpty)
    }

    func testActiveRecordingSuppressesOverlappingNativeDetections() async {
        let startedAt = date(1_700_060_300)
        var note = MeetingNote(
            id: UUID(uuidString: "99990000-1111-2222-3333-444455556666")!,
            title: "Already Recording",
            origin: .quickNote(createdAt: startedAt),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )
        note.captureState.beginCapture(at: startedAt)
        note.beginLiveSession(at: startedAt, presentTranscriptPanel: false, tracksSystemAudio: true)

        let detectionService = StubNativeMeetingDetectionService()
        let captureEngine = NativeDetectionStubCaptureEngine(
            activeSession: ActiveCaptureSession(
                noteID: note.id,
                startedAt: startedAt,
                fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(note.id.uuidString).m4a"),
                mode: .systemAudioAndMicrophone
            )
        )
        let model = makeModel(
            notes: [note],
            nativeMeetingDetectionService: detectionService,
            captureEngine: captureEngine
        )

        await model.loadSystemState()
        detectionService.emit(
            PendingMeetingDetection(
                id: UUID(uuidString: "AAAA0000-BBBB-CCCC-DDDD-EEEEFFFFFFFF")!,
                title: "Untitled Meeting",
                source: .nativeApp("Slack"),
                detectedAt: date(1_700_060_320),
                presentation: .prompt
            )
        )

        XCTAssertEqual(detectionService.startCalls, 1)
        XCTAssertNil(model.pendingMeetingDetection)
        XCTAssertNil(model.detectionPromptState)
        XCTAssertEqual(model.sessionControllerState?.kind, .active)
    }

    private func makeModel(
        notes: [MeetingNote],
        nativeMeetingDetectionService: NativeMeetingDetectionServicing,
        captureEngine: NativeDetectionStubCaptureEngine = NativeDetectionStubCaptureEngine()
    ) -> AppViewModel {
        let persistence = AppPersistence(
            applicationSupportFolderName: "OatmealNativeMeetingDetectionTests-\(UUID().uuidString)",
            stateFileName: "state.json"
        )

        let model = AppViewModel(
            store: InMemoryOatmealStore(notes: notes),
            calendarService: NativeDetectionStubCalendarService(),
            captureService: NativeDetectionStubCaptureAccessService(),
            captureEngine: captureEngine,
            nativeMeetingDetectionService: nativeMeetingDetectionService,
            transcriptionService: NativeDetectionStubTranscriptionService(),
            summaryService: NativeDetectionStubSummaryService(),
            summaryModelManager: NativeDetectionStubSummaryModelManager(),
            persistence: persistence,
            nowProvider: { Date(timeIntervalSince1970: 1_700_060_250) }
        )

        model.selectedNoteID = notes.first?.id
        return model
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}

@MainActor
private final class FakeNativeMeetingWorkspace: NativeMeetingApplicationWorkspace {
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
private final class StubNativeMeetingDetectionService: NativeMeetingDetectionServicing {
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
private struct NativeDetectionStubCalendarService: CalendarAccessServing {
    func authorizationStatus() -> PermissionStatus { .granted }
    func requestAccess() async -> PermissionStatus { .granted }
    func upcomingEvents(referenceDate: Date, horizon: TimeInterval) async throws -> [CalendarEvent] { [] }
}

@MainActor
private struct NativeDetectionStubCaptureAccessService: CaptureAccessServing {
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
private final class NativeDetectionStubCaptureEngine: MeetingCaptureEngineServing {
    var activeSession: ActiveCaptureSession?

    init(activeSession: ActiveCaptureSession? = nil) {
        self.activeSession = activeSession
    }

    func startCapture(for noteID: UUID, mode: CaptureMode) async throws -> ActiveCaptureSession {
        let session = ActiveCaptureSession(
            noteID: noteID,
            startedAt: Date(timeIntervalSince1970: 1_700_060_250),
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(noteID.uuidString).m4a"),
            mode: mode
        )
        activeSession = session
        return session
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

private struct NativeDetectionStubTranscriptionService: LocalTranscriptionServicing {
    func runtimeState(configuration: LocalTranscriptionConfiguration) async -> LocalTranscriptionRuntimeState {
        LocalTranscriptionRuntimeState(
            modelsDirectoryURL: FileManager.default.temporaryDirectory,
            discoveredModels: [],
            backends: [],
            activePlanSummary: "Tests"
        )
    }

    func executionPlan(configuration: LocalTranscriptionConfiguration) async throws -> TranscriptionExecutionPlan {
        TranscriptionExecutionPlan(
            backend: .mock,
            executionKind: .placeholder,
            summary: "Tests",
            warningMessages: []
        )
    }

    func transcribe(request: TranscriptionRequest, configuration: LocalTranscriptionConfiguration) async throws -> TranscriptionJobResult {
        TranscriptionJobResult(segments: [], backend: .mock, executionKind: .placeholder)
    }
}

private struct NativeDetectionStubSummaryService: LocalSummaryServicing {
    func runtimeState(configuration: LocalSummaryConfiguration) async -> LocalSummaryRuntimeState {
        LocalSummaryRuntimeState(
            modelsDirectoryURL: FileManager.default.temporaryDirectory,
            discoveredModels: [],
            preferredModelName: nil,
            backends: [],
            activePlanSummary: "Tests"
        )
    }

    func executionPlan(configuration: LocalSummaryConfiguration) async throws -> LocalSummaryExecutionPlan {
        LocalSummaryExecutionPlan(
            backend: .placeholder,
            executionKind: .placeholder,
            summary: "Tests",
            warningMessages: []
        )
    }

    func generate(request: NoteGenerationRequest, configuration: LocalSummaryConfiguration) async throws -> SummaryJobResult {
        SummaryJobResult(enhancedNote: EnhancedNote(summary: "Tests"), backend: .placeholder, executionKind: .placeholder)
    }
}

private struct NativeDetectionStubSummaryModelManager: LocalSummaryModelManaging {
    func catalogState() async -> SummaryModelCatalogState {
        SummaryModelCatalogState(
            modelsDirectoryURL: FileManager.default.temporaryDirectory,
            downloadAvailability: .unavailable,
            downloadRuntimeDetail: "Tests",
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
