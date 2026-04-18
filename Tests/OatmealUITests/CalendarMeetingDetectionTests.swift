import Foundation
import OatmealCore
import OatmealEdge
@testable import OatmealUI
import XCTest

@MainActor
final class CalendarMeetingDetectionTests: XCTestCase {
    func testResolverMatchesSingleClearNearbyCalendarEvent() {
        let detectedAt = date(1_700_091_000)
        let event = calendarEvent(
            id: UUID(uuidString: "09090909-1111-2222-3333-444444444444")!,
            title: "Weekly Product Sync",
            start: detectedAt.addingTimeInterval(-120),
            conferencingURL: URL(string: "https://meet.google.com/abc-defg-hij")
        )
        let farEvent = calendarEvent(
            id: UUID(uuidString: "09090909-AAAA-BBBB-CCCC-444444444444")!,
            title: "Later Review",
            start: detectedAt.addingTimeInterval(45 * 60)
        )

        let resolver = LiveMeetingCandidateResolver()
        let detection = resolver.resolve(
            detection: PendingMeetingDetection(
                title: "Untitled Meeting",
                source: .browser("Google Chrome"),
                detectedAt: detectedAt,
                presentation: .prompt
            ),
            availableEvents: [farEvent, event]
        )

        XCTAssertEqual(detection.calendarEvent?.id, event.id)
        XCTAssertTrue(detection.candidateCalendarEvents.isEmpty)
        XCTAssertFalse(detection.requiresCalendarChoice)
    }

    func testResolverReturnsAmbiguousCandidatesWhenMeetingsAreEquallyPlausible() {
        let detectedAt = date(1_700_091_000)
        let firstEvent = calendarEvent(
            id: UUID(uuidString: "11110000-1111-2222-3333-444444444444")!,
            title: "Product Review",
            start: detectedAt.addingTimeInterval(-60)
        )
        let secondEvent = calendarEvent(
            id: UUID(uuidString: "22220000-1111-2222-3333-444444444444")!,
            title: "Design Sync",
            start: detectedAt.addingTimeInterval(-60)
        )

        let resolver = LiveMeetingCandidateResolver()
        let detection = resolver.resolve(
            detection: PendingMeetingDetection(
                title: "Untitled Meeting",
                source: .browser("Safari"),
                detectedAt: detectedAt,
                presentation: .prompt
            ),
            availableEvents: [firstEvent, secondEvent]
        )

        XCTAssertNil(detection.calendarEvent)
        XCTAssertEqual(Set(detection.candidateCalendarEvents.map(\.id)), Set([firstEvent.id, secondEvent.id]))
        XCTAssertTrue(detection.requiresCalendarChoice)
    }

    func testLoadCalendarStatePopulatesUpcomingMeetingsAndSelectsFirstCandidate() async {
        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let firstEvent = calendarEvent(
            id: UUID(uuidString: "10101010-1111-2222-3333-444444444444")!,
            title: "Product Review",
            start: date(1_700_090_000)
        )
        let secondEvent = calendarEvent(
            id: UUID(uuidString: "20202020-1111-2222-3333-444444444444")!,
            title: "Design Sync",
            start: date(1_700_090_600)
        )
        let model = makeModel(
            calendarService: StubCalendarService(
                authorizationStatusValue: .granted,
                upcomingEventsValue: [firstEvent, secondEvent]
            ),
            persistence: persistence
        )

        await model.loadCalendarState()

        XCTAssertEqual(model.calendarAccessStatus, .granted)
        XCTAssertEqual(model.upcomingMeetings.map(\.id), [firstEvent.id, secondEvent.id])
        XCTAssertEqual(model.selectedUpcomingEventID, firstEvent.id)
        XCTAssertEqual(model.selectedUpcomingEvent?.id, firstEvent.id)
    }

    func testCalendarBackedDetectionPromptCarriesChosenEventIdentity() async {
        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let candidateEvent = calendarEvent(
            id: UUID(uuidString: "30303030-1111-2222-3333-444444444444")!,
            title: "Customer Check-In",
            start: date(1_700_091_000)
        )
        let otherEvent = calendarEvent(
            id: UUID(uuidString: "40404040-1111-2222-3333-444444444444")!,
            title: "Team Standup",
            start: date(1_700_090_800)
        )
        let model = makeModel(
            calendarService: StubCalendarService(
                authorizationStatusValue: .granted,
                upcomingEventsValue: [otherEvent, candidateEvent]
            ),
            persistence: persistence
        )

        await model.loadCalendarState()
        model.receiveMeetingDetection(
            PendingMeetingDetection(
                id: UUID(uuidString: "50505050-1111-2222-3333-444444444444")!,
                title: candidateEvent.title,
                source: .browser("Google Chrome"),
                detectedAt: date(1_700_091_050),
                presentation: .prompt,
                calendarEvent: candidateEvent
            )
        )

        XCTAssertEqual(model.detectionPromptState?.noteID, candidateEvent.id)
        XCTAssertEqual(model.menuBarMeetingDetectionState?.noteID, candidateEvent.id)
        XCTAssertEqual(model.detectionPromptState?.title, candidateEvent.title)
        XCTAssertEqual(model.detectionPromptState?.sourceKind, .browser)
        XCTAssertEqual(model.detectionPromptState?.kind, .prompt)
    }

    func testAmbiguousDetectionShowsCompactChooserUntilCandidateSelected() async {
        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let firstEvent = calendarEvent(
            id: UUID(uuidString: "AAAA1111-1111-2222-3333-444444444444")!,
            title: "Product Review",
            start: date(1_700_091_000).addingTimeInterval(-60)
        )
        let secondEvent = calendarEvent(
            id: UUID(uuidString: "BBBB1111-1111-2222-3333-444444444444")!,
            title: "Design Sync",
            start: date(1_700_091_000).addingTimeInterval(-60)
        )
        let model = makeModel(
            calendarService: StubCalendarService(
                authorizationStatusValue: .granted,
                upcomingEventsValue: [firstEvent, secondEvent]
            ),
            persistence: persistence
        )

        await model.loadCalendarState()
        model.receiveMeetingDetection(
            PendingMeetingDetection(
                id: UUID(uuidString: "CCCC1111-1111-2222-3333-444444444444")!,
                title: "Untitled Meeting",
                source: .browser("Google Chrome"),
                detectedAt: date(1_700_091_000),
                presentation: .prompt
            )
        )

        XCTAssertEqual(model.detectionPromptState?.headline, "Choose meeting")
        XCTAssertEqual(Set(model.detectionPromptState?.candidateOptions.map(\.id) ?? []), Set([firstEvent.id, secondEvent.id]))
        XCTAssertEqual(model.detectionPromptState?.selectedCandidateID, nil)
        XCTAssertFalse(model.detectionPromptState?.primaryActionEnabled ?? true)

        await model.startPendingMeetingDetectionCapture()

        XCTAssertNotNil(model.pendingMeetingDetection)
        XCTAssertEqual(model.detectionPromptState?.candidateOptions.count, 2)
        XCTAssertNil(model.selectedNote)

        model.selectPendingMeetingCandidate(secondEvent.id)

        XCTAssertEqual(model.detectionPromptState?.selectedCandidateID, secondEvent.id)
        XCTAssertTrue(model.detectionPromptState?.primaryActionEnabled == true)
    }

    func testPassiveAmbiguousDetectionReopensPromptInsteadOfStartingAdHoc() async {
        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let firstEvent = calendarEvent(
            id: UUID(uuidString: "DDDD1111-1111-2222-3333-444444444444")!,
            title: "Roadmap Review",
            start: date(1_700_091_000).addingTimeInterval(-60)
        )
        let secondEvent = calendarEvent(
            id: UUID(uuidString: "EEEE1111-1111-2222-3333-444444444444")!,
            title: "Customer Call",
            start: date(1_700_091_000).addingTimeInterval(-60)
        )
        let captureEngine = StubCaptureEngine()
        let model = makeModel(
            calendarService: StubCalendarService(
                authorizationStatusValue: .granted,
                upcomingEventsValue: [firstEvent, secondEvent]
            ),
            captureEngine: captureEngine,
            persistence: persistence
        )

        await model.loadCalendarState()
        model.receiveMeetingDetection(
            PendingMeetingDetection(
                id: UUID(uuidString: "FFFF1111-1111-2222-3333-444444444444")!,
                title: "Untitled Meeting",
                source: .browser("Safari"),
                detectedAt: date(1_700_091_000),
                presentation: .passiveSuggestion
            )
        )

        XCTAssertNil(model.detectionPromptState)
        XCTAssertEqual(model.menuBarMeetingDetectionState?.kind, .passiveSuggestion)

        await model.startPendingMeetingDetectionCapture()

        XCTAssertNotNil(model.pendingMeetingDetection)
        XCTAssertEqual(model.pendingMeetingDetection?.presentation, .prompt)
        XCTAssertEqual(model.detectionPromptState?.candidateOptions.count, 2)
        XCTAssertEqual(captureEngine.startCalls, 0)
        XCTAssertNil(model.sessionControllerState)
    }

    func testStartingCalendarBackedDetectionReusesExistingCalendarNoteForChosenCandidate() async {
        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let candidateEvent = calendarEvent(
            id: UUID(uuidString: "60606060-1111-2222-3333-444444444444")!,
            title: "Roadmap Review",
            start: date(1_700_091_400)
        )
        let existingNote = MeetingNote(
            id: UUID(uuidString: "70707070-1111-2222-3333-444444444444")!,
            title: candidateEvent.title,
            origin: .calendarEvent(candidateEvent.id, createdAt: date(1_700_091_200)),
            calendarEvent: candidateEvent,
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )

        let captureEngine = StubCaptureEngine()
        let model = makeModel(
            notes: [existingNote],
            calendarService: StubCalendarService(
                authorizationStatusValue: .granted,
                upcomingEventsValue: [candidateEvent]
            ),
            captureEngine: captureEngine,
            persistence: persistence
        )

        await model.loadCalendarState()
        model.receiveMeetingDetection(
            PendingMeetingDetection(
                id: UUID(uuidString: "80808080-1111-2222-3333-444444444444")!,
                title: candidateEvent.title,
                source: .browser("Safari"),
                detectedAt: date(1_700_091_450),
                presentation: .prompt,
                calendarEvent: candidateEvent
            )
        )

        await model.startPendingMeetingDetectionCapture()

        XCTAssertEqual(captureEngine.startCalls, 1)
        XCTAssertNil(model.pendingMeetingDetection)
        XCTAssertNil(model.detectionPromptState)
        XCTAssertNil(model.menuBarMeetingDetectionState)
        XCTAssertEqual(model.selectedNoteID, existingNote.id)
        XCTAssertEqual(model.selectedNote?.calendarEvent?.id, candidateEvent.id)
        XCTAssertEqual(model.selectedNote?.captureState.phase, .capturing)
        XCTAssertEqual(model.sessionControllerState?.kind, .active)
    }

    private func makeModel(
        notes: [MeetingNote] = [],
        calendarService: CalendarAccessServing,
        captureEngine: StubCaptureEngine = StubCaptureEngine(),
        persistence: AppPersistence
    ) -> AppViewModel {
        let model = AppViewModel(
            store: InMemoryOatmealStore(notes: notes),
            calendarService: calendarService,
            captureService: StubCaptureAccessService(),
            captureEngine: captureEngine,
            nativeMeetingDetectionService: NoopNativeMeetingDetectionService(),
            browserMeetingDetectionService: NoopBrowserMeetingDetectionService(),
            transcriptionService: StubTranscriptionService(),
            summaryService: StubSummaryService(),
            summaryModelManager: StubSummaryModelManager(state: emptySummaryModelCatalogState()),
            persistence: persistence,
            nowProvider: { Date(timeIntervalSince1970: 1_700_091_000) }
        )

        model.selectedNoteID = notes.first?.id
        return model
    }

    private func makePersistence() -> AppPersistence {
        AppPersistence(
            applicationSupportFolderName: "CalendarMeetingDetectionTests-\(UUID().uuidString)",
            stateFileName: "state.json"
        )
    }

    private func calendarEvent(id: UUID, title: String, start: Date, conferencingURL: URL? = nil) -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: title,
            startDate: start,
            endDate: start.addingTimeInterval(3_600),
            attendees: [],
            conferencingURL: conferencingURL,
            source: .manual,
            kind: .meeting,
            attendanceStatus: .accepted
        )
    }

    private func emptySummaryModelCatalogState() -> SummaryModelCatalogState {
        SummaryModelCatalogState(
            modelsDirectoryURL: FileManager.default.temporaryDirectory,
            downloadAvailability: .available,
            downloadRuntimeDetail: "Stub summary model catalog",
            items: []
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func removePersistenceArtifacts(_ persistence: AppPersistence) {
        try? FileManager.default.removeItem(at: persistence.applicationSupportDirectoryURL)
    }
}

@MainActor
private final class NoopNativeMeetingDetectionService: NativeMeetingDetectionServicing {
    func start(onDetection: @escaping @MainActor (PendingMeetingDetection) -> Void) {}
    func stop() {}
}

@MainActor
private final class NoopBrowserMeetingDetectionService: BrowserMeetingDetectionServicing {
    func start(onDetection: @escaping @MainActor (PendingMeetingDetection) -> Void) {}
    func stop() {}
}

@MainActor
private final class StubCalendarService: CalendarAccessServing {
    let authorizationStatusValue: PermissionStatus
    let upcomingEventsValue: [CalendarEvent]

    init(
        authorizationStatusValue: PermissionStatus = .notDetermined,
        upcomingEventsValue: [CalendarEvent] = []
    ) {
        self.authorizationStatusValue = authorizationStatusValue
        self.upcomingEventsValue = upcomingEventsValue
    }

    func authorizationStatus() -> PermissionStatus {
        authorizationStatusValue
    }

    func requestAccess() async -> PermissionStatus {
        authorizationStatusValue
    }

    func upcomingEvents(referenceDate _: Date, horizon _: TimeInterval) async throws -> [CalendarEvent] {
        upcomingEventsValue
    }
}

@MainActor
private final class StubCaptureAccessService: CaptureAccessServing {
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

@MainActor
private final class StubCaptureEngine: MeetingCaptureEngineServing {
    private(set) var activeSession: ActiveCaptureSession?
    private(set) var startCalls = 0

    func startCapture(for noteID: UUID, mode: CaptureMode) async throws -> ActiveCaptureSession {
        startCalls += 1
        let session = ActiveCaptureSession(
            noteID: noteID,
            startedAt: Date(timeIntervalSince1970: 1_700_091_500),
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(noteID.uuidString).m4a"),
            mode: mode
        )
        activeSession = session
        return session
    }

    func stopCapture() async throws -> CaptureArtifact {
        throw CaptureEngineError.noActiveCapture
    }

    func recordingURL(for _: UUID) -> URL? {
        nil
    }

    func liveTranscriptionChunks(for _: UUID) -> [LiveTranscriptionChunk] {
        []
    }

    func runtimeHealthSnapshot(for _: UUID) -> CaptureRuntimeHealthSnapshot? {
        nil
    }

    func consumeRuntimeEvents(for _: UUID) -> [CaptureRuntimeEvent] {
        []
    }

    func deleteRecording(for _: UUID) throws {}
}

private struct StubTranscriptionService: LocalTranscriptionServicing {
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

    func transcribe(request _: TranscriptionRequest, configuration _: LocalTranscriptionConfiguration) async throws -> TranscriptionJobResult {
        TranscriptionJobResult(
            segments: [],
            backend: .mock,
            executionKind: .placeholder
        )
    }
}

private struct StubSummaryService: LocalSummaryServicing {
    func runtimeState(configuration: LocalSummaryConfiguration) async -> LocalSummaryRuntimeState {
        LocalSummaryRuntimeState(
            modelsDirectoryURL: FileManager.default.temporaryDirectory,
            discoveredModels: [],
            preferredModelName: configuration.preferredModelName,
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

    func generate(request _: NoteGenerationRequest, configuration _: LocalSummaryConfiguration) async throws -> SummaryJobResult {
        SummaryJobResult(
            enhancedNote: EnhancedNote(summary: "Stub summary", keyDiscussionPoints: [], decisions: [], actionItems: []),
            backend: .placeholder,
            executionKind: .placeholder
        )
    }
}

private actor StubSummaryModelManager: LocalSummaryModelManaging {
    private let state: SummaryModelCatalogState

    init(state: SummaryModelCatalogState) {
        self.state = state
    }

    func catalogState() async -> SummaryModelCatalogState {
        state
    }

    func install(modelID _: String, forceRedownload _: Bool) async throws -> SummaryModelCatalogState {
        state
    }

    func remove(modelDirectoryURL _: URL) async throws -> SummaryModelCatalogState {
        state
    }
}
