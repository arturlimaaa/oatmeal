import Foundation
import OatmealCore
import OatmealEdge
@testable import OatmealUI
import XCTest

@MainActor
final class DetectionSettingsTests: XCTestCase {
    func testDisabledNativeAppSourceSuppressesDetection() {
        let captureEngine = DetectionSettingsStubCaptureEngine()
        let model = makeModel(captureEngine: captureEngine)

        model.setMeetingDetectionSourceEnabled(.zoom, enabled: false)
        model.receiveMeetingDetection(
            PendingMeetingDetection(
                id: UUID(uuidString: "44444444-1111-2222-3333-444444444444")!,
                title: "Untitled Meeting",
                source: .nativeApp("Zoom"),
                detectedAt: date(1_700_100_100),
                presentation: .prompt
            )
        )

        XCTAssertEqual(captureEngine.startCalls, 0)
        XCTAssertNil(model.pendingMeetingDetection)
        XCTAssertNil(model.detectionPromptState)
        XCTAssertNil(model.menuBarMeetingDetectionState)
    }

    func testDisabledBrowserSourceSuppressesDetection() {
        let captureEngine = DetectionSettingsStubCaptureEngine()
        let model = makeModel(captureEngine: captureEngine)

        model.setMeetingDetectionSourceEnabled(.browsers, enabled: false)
        model.receiveMeetingDetection(
            PendingMeetingDetection(
                id: UUID(uuidString: "45555555-1111-2222-3333-444444444444")!,
                title: "Untitled Meeting",
                source: .browser("Safari"),
                detectedAt: date(1_700_100_110),
                presentation: .passiveSuggestion
            )
        )

        XCTAssertEqual(captureEngine.startCalls, 0)
        XCTAssertNil(model.pendingMeetingDetection)
        XCTAssertNil(model.detectionPromptState)
        XCTAssertNil(model.menuBarMeetingDetectionState)
    }

    func testHighConfidenceAutoStartBeginsCaptureWithoutShowingPrompt() async {
        let captureEngine = DetectionSettingsStubCaptureEngine()
        let model = makeModel(captureEngine: captureEngine)
        model.capturePermissions = .fullyGranted(calendar: .granted)
        model.setHighConfidenceAutoStartEnabled(true)

        var openedWindowIDs: [String] = []
        var dismissedWindowIDs: [String] = []
        model.bindLightweightSurfaceWindowActions(
            openWindow: { openedWindowIDs.append($0) },
            dismissWindow: { dismissedWindowIDs.append($0) }
        )

        model.receiveMeetingDetection(
            PendingMeetingDetection(
                id: UUID(uuidString: "46666666-1111-2222-3333-444444444444")!,
                title: "Untitled Meeting",
                source: .nativeApp("Zoom"),
                detectedAt: date(1_700_100_120),
                presentation: .prompt,
                confidence: .high
            )
        )

        let autoStarted = await waitUntil { captureEngine.startCalls == 1 }
        XCTAssertTrue(autoStarted)
        XCTAssertNil(model.pendingMeetingDetection)
        XCTAssertNil(model.detectionPromptState)
        XCTAssertNil(model.menuBarMeetingDetectionState)
        XCTAssertEqual(model.selectedNote?.title, "Untitled Meeting")
        XCTAssertEqual(model.selectedNote?.captureState.phase, .capturing)
        XCTAssertTrue(openedWindowIDs.isEmpty)
        XCTAssertEqual(dismissedWindowIDs, [OatmealSceneID.meetingDetectionPrompt])
    }

    func testLowConfidenceDetectionFallsBackToPassiveSuggestionWhenAutoStartIsEnabled() {
        let captureEngine = DetectionSettingsStubCaptureEngine()
        let model = makeModel(captureEngine: captureEngine)
        model.capturePermissions = .fullyGranted(calendar: .granted)
        model.setHighConfidenceAutoStartEnabled(true)

        var openedWindowIDs: [String] = []
        var dismissedWindowIDs: [String] = []
        model.bindLightweightSurfaceWindowActions(
            openWindow: { openedWindowIDs.append($0) },
            dismissWindow: { dismissedWindowIDs.append($0) }
        )

        model.receiveMeetingDetection(
            PendingMeetingDetection(
                id: UUID(uuidString: "47777777-1111-2222-3333-444444444444")!,
                title: "Untitled Meeting",
                source: .browser("Safari"),
                detectedAt: date(1_700_100_130),
                presentation: .passiveSuggestion,
                confidence: .low
            )
        )

        XCTAssertEqual(captureEngine.startCalls, 0)
        XCTAssertNil(model.detectionPromptState)
        XCTAssertEqual(model.menuBarMeetingDetectionState?.kind, .passiveSuggestion)
        XCTAssertTrue(openedWindowIDs.isEmpty)
        XCTAssertEqual(dismissedWindowIDs, [OatmealSceneID.meetingDetectionPrompt])
    }

    func testHighConfidenceAutoStartFallsBackToPromptWhenPermissionsAreMissing() {
        let captureEngine = DetectionSettingsStubCaptureEngine()
        let model = makeModel(captureEngine: captureEngine)
        model.capturePermissions = CapturePermissions(
            microphone: .denied,
            systemAudio: .granted,
            notifications: .granted,
            calendar: .granted
        )
        model.setHighConfidenceAutoStartEnabled(true)

        var openedWindowIDs: [String] = []
        var dismissedWindowIDs: [String] = []
        model.bindLightweightSurfaceWindowActions(
            openWindow: { openedWindowIDs.append($0) },
            dismissWindow: { dismissedWindowIDs.append($0) }
        )

        model.receiveMeetingDetection(
            PendingMeetingDetection(
                id: UUID(uuidString: "48888888-1111-2222-3333-444444444444")!,
                title: "Untitled Meeting",
                source: .nativeApp("Zoom"),
                detectedAt: date(1_700_100_140),
                presentation: .prompt,
                confidence: .high
            )
        )

        XCTAssertEqual(captureEngine.startCalls, 0)
        XCTAssertNotNil(model.pendingMeetingDetection)
        XCTAssertEqual(model.detectionPromptState?.kind, .prompt)
        XCTAssertNil(model.menuBarMeetingDetectionState?.noteID)
        XCTAssertEqual(openedWindowIDs, [OatmealSceneID.meetingDetectionPrompt])
        XCTAssertTrue(dismissedWindowIDs.isEmpty)
    }

    func testHighConfidenceAutoStartFallsBackToMeetingChooserWhenCalendarSelectionIsRequired() {
        let captureEngine = DetectionSettingsStubCaptureEngine()
        let firstEvent = calendarEvent(
            id: UUID(uuidString: "66666666-1111-2222-3333-444444444444")!,
            title: "Product Review",
            start: date(1_700_100_200)
        )
        let secondEvent = calendarEvent(
            id: UUID(uuidString: "77777777-1111-2222-3333-444444444444")!,
            title: "Design Sync",
            start: date(1_700_100_200)
        )
        let model = makeModel(
            captureEngine: captureEngine,
            upcomingMeetings: [firstEvent, secondEvent]
        )
        model.capturePermissions = .fullyGranted(calendar: .granted)
        model.setHighConfidenceAutoStartEnabled(true)

        var openedWindowIDs: [String] = []
        var dismissedWindowIDs: [String] = []
        model.bindLightweightSurfaceWindowActions(
            openWindow: { openedWindowIDs.append($0) },
            dismissWindow: { dismissedWindowIDs.append($0) }
        )

        model.receiveMeetingDetection(
            PendingMeetingDetection(
                id: UUID(uuidString: "88888888-1111-2222-3333-444444444444")!,
                title: "Untitled Meeting",
                source: .browser("Google Chrome"),
                detectedAt: date(1_700_100_210),
                presentation: .prompt,
                confidence: .high
            )
        )

        XCTAssertEqual(captureEngine.startCalls, 0)
        XCTAssertNotNil(model.pendingMeetingDetection)
        XCTAssertEqual(model.detectionPromptState?.headline, "Choose meeting")
        XCTAssertFalse(model.detectionPromptState?.primaryActionEnabled ?? true)
        XCTAssertEqual(openedWindowIDs, [OatmealSceneID.meetingDetectionPrompt])
        XCTAssertTrue(dismissedWindowIDs.isEmpty)
    }

    func testDetectionSettingsPersistAcrossRelaunch() {
        let persistence = makePersistence()
        addTeardownBlock { [persistence] in
            self.removePersistenceArtifacts(persistence)
        }

        let model = makeModel(persistence: persistence)
        model.setMeetingDetectionSourceEnabled(.zoom, enabled: false)
        model.setMeetingDetectionSourceEnabled(.browsers, enabled: false)
        model.setHighConfidenceAutoStartEnabled(true)

        let restored = makeModel(persistence: persistence)

        XCTAssertFalse(restored.meetingDetectionConfiguration.zoomEnabled)
        XCTAssertTrue(restored.meetingDetectionConfiguration.teamsEnabled)
        XCTAssertTrue(restored.meetingDetectionConfiguration.slackEnabled)
        XCTAssertFalse(restored.meetingDetectionConfiguration.browsersEnabled)
        XCTAssertTrue(restored.meetingDetectionConfiguration.highConfidenceAutoStartEnabled)
    }

    private func makeModel(
        captureEngine: DetectionSettingsStubCaptureEngine = DetectionSettingsStubCaptureEngine(),
        upcomingMeetings: [CalendarEvent] = [],
        persistence: AppPersistence? = nil,
        captureService: CaptureAccessServing = DetectionSettingsStubCaptureAccessService()
    ) -> AppViewModel {
        let persistence = persistence ?? makePersistence()
        if persistence.stateFileNameForTesting == "state.json" {
            addTeardownBlock { [persistence] in
                self.removePersistenceArtifacts(persistence)
            }
        }

        let model = AppViewModel(
            store: InMemoryOatmealStore(notes: []),
            calendarService: DetectionSettingsStubCalendarService(),
            captureService: captureService,
            captureEngine: captureEngine,
            nativeMeetingDetectionService: NoopNativeMeetingDetectionService(),
            browserMeetingDetectionService: NoopBrowserMeetingDetectionService(),
            transcriptionService: DetectionSettingsStubTranscriptionService(),
            summaryService: DetectionSettingsStubSummaryService(),
            summaryModelManager: DetectionSettingsStubSummaryModelManager(),
            persistence: persistence,
            nowProvider: { Date(timeIntervalSince1970: 1_700_100_000) },
            liveTranscriptionPollingInterval: 10
        )

        model.upcomingMeetings = upcomingMeetings
        return model
    }

    private func makePersistence() -> AppPersistence {
        AppPersistence(
            applicationSupportFolderName: "OatmealDetectionSettingsTests-\(UUID().uuidString)",
            stateFileName: "state.json"
        )
    }

    private func removePersistenceArtifacts(_ persistence: AppPersistence) {
        try? FileManager.default.removeItem(at: persistence.stateFileURL)
        try? FileManager.default.removeItem(at: persistence.applicationSupportDirectoryURL)
    }

    private func calendarEvent(id: UUID, title: String, start: Date) -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: title,
            startDate: start,
            endDate: start.addingTimeInterval(30 * 60),
            source: .local
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 500_000_000,
        intervalNanoseconds: UInt64 = 20_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: intervalNanoseconds)
        }
        return condition()
    }
}

@MainActor
private final class NoopNativeMeetingDetectionService: NativeMeetingDetectionServicing {
    func start(onDetection: @escaping @MainActor (PendingMeetingDetection) -> Void) {}
    func stop() {}
}

@MainActor
private final class NoopBrowserMeetingDetectionService: BrowserMeetingDetectionServicing {
    let capabilityState = BrowserDetectionCapabilityState(
        accessibilityTrusted: false,
        automationAvailability: .unknown
    )

    func start(onDetection: @escaping @MainActor (PendingMeetingDetection) -> Void) {}
    func stop() {}
}

@MainActor
private final class DetectionSettingsStubCaptureEngine: MeetingCaptureEngineServing {
    private(set) var activeSession: ActiveCaptureSession?
    private(set) var startCalls = 0

    func startCapture(for noteID: UUID, mode: CaptureMode) async throws -> ActiveCaptureSession {
        startCalls += 1
        let session = ActiveCaptureSession(
            noteID: noteID,
            startedAt: Date(timeIntervalSince1970: 1_700_100_400),
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

private struct DetectionSettingsStubCalendarService: CalendarAccessServing {
    func authorizationStatus() -> PermissionStatus { .granted }
    func requestAccess() async -> PermissionStatus { .granted }
    func upcomingEvents(referenceDate: Date, horizon: TimeInterval) async throws -> [CalendarEvent] { [] }
}

private struct DetectionSettingsStubCaptureAccessService: CaptureAccessServing {
    func currentPermissions(calendarStatus: PermissionStatus) async -> CapturePermissions {
        .fullyGranted(calendar: calendarStatus)
    }

    func requestPermissions(requiresSystemAudio: Bool, calendarStatus: PermissionStatus) async -> CapturePermissions {
        await currentPermissions(calendarStatus: calendarStatus)
    }
}

private struct DetectionSettingsStubTranscriptionService: LocalTranscriptionServicing {
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

private struct DetectionSettingsStubSummaryService: LocalSummaryServicing {
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

private struct DetectionSettingsStubSummaryModelManager: LocalSummaryModelManaging {
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

private extension CapturePermissions {
    static func fullyGranted(calendar: PermissionStatus) -> CapturePermissions {
        CapturePermissions(
            microphone: .granted,
            systemAudio: .granted,
            notifications: .granted,
            calendar: calendar
        )
    }
}

private extension AppPersistence {
    var stateFileNameForTesting: String {
        stateFileURL.lastPathComponent
    }
}
