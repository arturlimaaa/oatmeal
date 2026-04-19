import Foundation
import OatmealCore
import OatmealEdge
@testable import OatmealUI
import XCTest

@MainActor
final class SingleMeetingAIWorkspaceTests: XCTestCase {
    func testSubmittingAssistantPromptTransitionsFromPendingToCompleted() async {
        let noteID = UUID(uuidString: "A1000000-0000-0000-0000-000000000001")!
        let note = MeetingNote(
            id: noteID,
            title: "Launch Review",
            origin: .quickNote(createdAt: date(1_700_200_000)),
            rawNotes: "Need to align on onboarding and launch timing."
        )
        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let assistantService = StubSingleMeetingAssistantService(
            mode: .success("Here is the saved note-level answer."),
            responseDelayNanoseconds: 80_000_000
        )

        let model = makeModel(
            notes: [note],
            persistence: persistence,
            assistantService: assistantService,
            nowProvider: { self.date(1_700_200_100) }
        )

        model.submitAssistantPrompt("What changed in the meeting?", for: noteID)

        XCTAssertEqual(model.selectedNote?.assistantThread.turns.count, 1)
        XCTAssertEqual(model.selectedNote?.assistantThread.turns.first?.status, .pending)
        XCTAssertTrue(model.selectedNote?.hasPendingAssistantTurn == true)

        let completed = await waitUntil {
            model.selectedNote?.assistantThread.turns.first?.status == .completed
        }

        XCTAssertTrue(completed)
        XCTAssertEqual(
            model.selectedNote?.assistantThread.turns.first?.response,
            "Here is the saved note-level answer."
        )
        XCTAssertFalse(model.selectedNote?.hasPendingAssistantTurn ?? true)
    }

    func testAssistantThreadPersistsAcrossRelaunch() async throws {
        let noteID = UUID(uuidString: "A2000000-0000-0000-0000-000000000002")!
        let note = MeetingNote(
            id: noteID,
            title: "Customer Debrief",
            origin: .quickNote(createdAt: date(1_700_201_000)),
            transcriptSegments: [TranscriptSegment(text: "We should follow up on the support backlog.")]
        )
        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let model = makeModel(
            notes: [note],
            persistence: persistence,
            assistantService: StubSingleMeetingAssistantService(
                mode: .success("Persisted response"),
                responseDelayNanoseconds: 10_000_000
            ),
            nowProvider: { self.date(1_700_201_100) }
        )

        model.submitAssistantPrompt("Summarize the next step.", for: noteID)
        let completed = await waitUntil {
            model.selectedNote?.assistantThread.turns.first?.status == .completed
        }
        XCTAssertTrue(completed)

        let restored = makeModel(
            notes: [],
            persistence: persistence,
            assistantService: StubSingleMeetingAssistantService(mode: .success("Unused")),
            nowProvider: { self.date(1_700_201_200) }
        )

        let restoredNote = try XCTUnwrap(restored.notes.first(where: { $0.id == noteID }))
        XCTAssertEqual(restoredNote.assistantThread.turns.count, 1)
        XCTAssertEqual(restoredNote.assistantThread.turns[0].prompt, "Summarize the next step.")
        XCTAssertEqual(restoredNote.assistantThread.turns[0].response, "Persisted response")
        XCTAssertEqual(restoredNote.assistantThread.turns[0].status, .completed)
        XCTAssertEqual(restoredNote.assistantThread.turns[0].citations, [])
    }

    func testAssistantFailureStateIsPersistedOnTheNote() async {
        let noteID = UUID(uuidString: "A3000000-0000-0000-0000-000000000003")!
        let note = MeetingNote(
            id: noteID,
            title: "Hiring Sync",
            origin: .quickNote(createdAt: date(1_700_202_000)),
            enhancedNote: EnhancedNote(summary: "Need to decide on the candidate debrief.")
        )
        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let model = makeModel(
            notes: [note],
            persistence: persistence,
            assistantService: StubSingleMeetingAssistantService(
                mode: .failure("Oatmeal could not draft this answer right now."),
                responseDelayNanoseconds: 20_000_000
            ),
            nowProvider: { self.date(1_700_202_100) }
        )

        model.submitAssistantPrompt("Draft a response", for: noteID)

        let failed = await waitUntil {
            model.selectedNote?.assistantThread.turns.first?.status == .failed
        }

        XCTAssertTrue(failed)
        XCTAssertEqual(
            model.selectedNote?.assistantThread.turns.first?.failureMessage,
            "Oatmeal could not draft this answer right now."
        )
        XCTAssertFalse(model.selectedNote?.hasPendingAssistantTurn ?? true)
    }

    func testGroundedAssistantResponseIncludesTranscriptCitationsFromSelectedNoteOnly() async {
        let targetSegmentID = UUID(uuidString: "B4000000-0000-0000-0000-000000000004")!
        let targetNote = MeetingNote(
            id: UUID(uuidString: "B4000000-0000-0000-0000-000000000004")!,
            title: "Onboarding Review",
            origin: .quickNote(createdAt: date(1_700_203_000)),
            rawNotes: "Need to confirm the onboarding rollout window.",
            transcriptSegments: [
                TranscriptSegment(
                    id: targetSegmentID,
                    speakerName: "Alex",
                    text: "We decided to launch the onboarding refresh next Tuesday after QA signs off."
                ),
                TranscriptSegment(
                    id: UUID(uuidString: "B4000000-0000-0000-0000-000000000005")!,
                    speakerName: "Sam",
                    text: "QA will confirm the checklist on Monday morning."
                )
            ]
        )
        let unrelatedSegmentID = UUID(uuidString: "B4000000-0000-0000-0000-000000000099")!
        let unrelatedNote = MeetingNote(
            id: UUID(uuidString: "B4000000-0000-0000-0000-000000000098")!,
            title: "Different meeting",
            origin: .quickNote(createdAt: date(1_700_202_500)),
            transcriptSegments: [
                TranscriptSegment(
                    id: unrelatedSegmentID,
                    text: "This unrelated note talks about pricing, not onboarding."
                )
            ]
        )
        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let model = makeModel(
            notes: [targetNote, unrelatedNote],
            persistence: persistence,
            assistantService: GroundedSingleMeetingAssistantService(responseDelay: 0),
            nowProvider: { self.date(1_700_203_100) }
        )

        model.setSelectedNoteID(targetNote.id)
        model.submitAssistantPrompt("What did we decide about onboarding?", for: targetNote.id)

        let completed = await waitUntil {
            model.selectedNote?.assistantThread.turns.first?.status == .completed
        }

        XCTAssertTrue(completed)
        let turn = try? XCTUnwrap(model.selectedNote?.assistantThread.turns.first)
        XCTAssertTrue(turn?.response?.contains("Based on this meeting note") == true)
        XCTAssertTrue(turn?.citations.contains(where: { $0.transcriptSegmentID == targetSegmentID }) == true)
        XCTAssertFalse(turn?.citations.contains(where: { $0.transcriptSegmentID == unrelatedSegmentID }) == true)
    }

    func testGroundedAssistantAdmitsUncertaintyWhenMeetingContextIsWeak() async {
        let noteID = UUID(uuidString: "B5000000-0000-0000-0000-000000000005")!
        let note = MeetingNote(
            id: noteID,
            title: "Budget Check-in",
            origin: .quickNote(createdAt: date(1_700_204_000)),
            rawNotes: "Reviewed current infrastructure budget."
        )
        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let model = makeModel(
            notes: [note],
            persistence: persistence,
            assistantService: GroundedSingleMeetingAssistantService(responseDelay: 0),
            nowProvider: { self.date(1_700_204_100) }
        )

        model.submitAssistantPrompt("What did we decide about onboarding ownership?", for: noteID)

        let completed = await waitUntil {
            model.selectedNote?.assistantThread.turns.first?.status == .completed
        }

        XCTAssertTrue(completed)
        let turn = try? XCTUnwrap(model.selectedNote?.assistantThread.turns.first)
        XCTAssertTrue(turn?.response?.contains("don’t have enough grounded context") == true)
        XCTAssertTrue(turn?.citations.allSatisfy { $0.kind != .transcriptSegment } == true)
    }

    func testFollowUpEmailDraftActionUsesGroundedAssistantThreadAndSelectedNoteOnly() async throws {
        let targetSegmentID = UUID(uuidString: "C6000000-0000-0000-0000-000000000006")!
        let targetNote = MeetingNote(
            id: UUID(uuidString: "C6000000-0000-0000-0000-000000000006")!,
            title: "Launch Review",
            origin: .quickNote(createdAt: date(1_700_205_000)),
            calendarEvent: CalendarEvent(
                id: UUID(uuidString: "C6000000-0000-0000-0000-000000000016")!,
                title: "Launch Review",
                startDate: date(1_700_205_000),
                endDate: date(1_700_205_900),
                attendees: [
                    MeetingParticipant(name: "Alex"),
                    MeetingParticipant(name: "Sam")
                ],
                source: .googleCalendar
            ),
            rawNotes: "Aligned on the onboarding refresh launch plan.",
            transcriptSegments: [
                TranscriptSegment(
                    id: targetSegmentID,
                    speakerName: "Alex",
                    text: "We decided to ship the onboarding refresh next Tuesday after QA signs off."
                )
            ],
            enhancedNote: EnhancedNote(
                summary: "Aligned on the onboarding refresh launch plan.",
                decisions: ["Ship the onboarding refresh next Tuesday after QA signs off."],
                actionItems: [ActionItem(text: "QA will confirm the checklist on Monday morning.", assignee: "Sam")]
            )
        )
        let unrelatedSegmentID = UUID(uuidString: "C6000000-0000-0000-0000-000000000099")!
        let unrelatedNote = MeetingNote(
            id: UUID(uuidString: "C6000000-0000-0000-0000-000000000098")!,
            title: "Different meeting",
            origin: .quickNote(createdAt: date(1_700_204_900)),
            transcriptSegments: [
                TranscriptSegment(
                    id: unrelatedSegmentID,
                    text: "This unrelated note focuses on pricing changes."
                )
            ]
        )
        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let model = makeModel(
            notes: [targetNote, unrelatedNote],
            persistence: persistence,
            assistantService: GroundedSingleMeetingAssistantService(responseDelay: 0),
            nowProvider: { self.date(1_700_205_100) }
        )

        model.setSelectedNoteID(targetNote.id)
        model.submitAssistantDraftAction(.followUpEmail, for: targetNote.id)

        let completed = await waitUntil {
            model.selectedNote?.assistantThread.turns.first?.status == .completed
        }

        XCTAssertTrue(completed)
        let turn = try XCTUnwrap(model.selectedNote?.assistantThread.turns.first)
        XCTAssertEqual(turn.kind, .followUpEmail)
        XCTAssertEqual(turn.prompt, "Draft a follow-up email")
        XCTAssertTrue(turn.response?.contains("Subject: Follow-up: Launch Review") == true)
        XCTAssertTrue(turn.response?.contains("Hi Alex and Sam,") == true)
        XCTAssertFalse(turn.citations.isEmpty)
        XCTAssertTrue(
            turn.citations.contains { citation in
                citation.excerpt.contains("onboarding refresh") || citation.excerpt.contains("checklist")
            }
        )
        XCTAssertFalse(turn.citations.contains(where: { $0.transcriptSegmentID == unrelatedSegmentID }))
    }

    func testSlackRecapDraftActionPersistsAcrossRelaunch() async throws {
        let noteID = UUID(uuidString: "C7000000-0000-0000-0000-000000000007")!
        let note = MeetingNote(
            id: noteID,
            title: "Customer Debrief",
            origin: .quickNote(createdAt: date(1_700_206_000)),
            rawNotes: "Customer wants a revised rollout plan by Friday.",
            transcriptSegments: [
                TranscriptSegment(text: "We should send the revised rollout plan by Friday.")
            ],
            enhancedNote: EnhancedNote(
                summary: "Customer asked for a revised rollout plan by Friday.",
                actionItems: [ActionItem(text: "Send the revised rollout plan by Friday.", assignee: "Jordan")]
            )
        )
        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let model = makeModel(
            notes: [note],
            persistence: persistence,
            assistantService: GroundedSingleMeetingAssistantService(responseDelay: 0),
            nowProvider: { self.date(1_700_206_100) }
        )

        model.submitAssistantDraftAction(.slackRecap, for: noteID)

        let completed = await waitUntil {
            model.selectedNote?.assistantThread.turns.first?.status == .completed
        }
        XCTAssertTrue(completed)

        let restored = makeModel(
            notes: [],
            persistence: persistence,
            assistantService: StubSingleMeetingAssistantService(mode: .success("Unused")),
            nowProvider: { self.date(1_700_206_200) }
        )

        let restoredNote = try XCTUnwrap(restored.notes.first(where: { $0.id == noteID }))
        XCTAssertEqual(restoredNote.assistantThread.turns.count, 1)
        XCTAssertEqual(restoredNote.assistantThread.turns[0].kind, .slackRecap)
        XCTAssertEqual(restoredNote.assistantThread.turns[0].prompt, "Draft a Slack recap")
        XCTAssertTrue(restoredNote.assistantThread.turns[0].response?.contains("Quick recap from Customer Debrief:") == true)
        XCTAssertEqual(restoredNote.assistantThread.turns[0].status, .completed)
    }

    private func makeModel(
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

    private func makePersistence() -> AppPersistence {
        AppPersistence(
            applicationSupportFolderName: "OatmealAIWorkspaceTests-\(UUID().uuidString)",
            stateFileName: "state.json"
        )
    }

    private func removePersistenceArtifacts(_ persistence: AppPersistence) {
        try? FileManager.default.removeItem(at: persistence.stateFileURL)
        try? FileManager.default.removeItem(at: persistence.applicationSupportDirectoryURL)
    }

    private func waitUntil(
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

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}

@MainActor
private struct AIWorkspaceStubCalendarService: CalendarAccessServing {
    func authorizationStatus() -> PermissionStatus { .granted }
    func requestAccess() async -> PermissionStatus { .granted }
    func upcomingEvents(referenceDate: Date, horizon: TimeInterval) async throws -> [CalendarEvent] { [] }
}

@MainActor
private struct AIWorkspaceStubCaptureAccessService: CaptureAccessServing {
    func currentPermissions(calendarStatus: PermissionStatus) async -> CapturePermissions {
        .fullyGranted(calendar: calendarStatus)
    }

    func requestPermissions(requiresSystemAudio: Bool, calendarStatus: PermissionStatus) async -> CapturePermissions {
        .fullyGranted(calendar: calendarStatus)
    }
}

@MainActor
private final class AIWorkspaceStubCaptureEngine: MeetingCaptureEngineServing {
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
private final class AIWorkspaceNoopNativeMeetingDetectionService: NativeMeetingDetectionServicing {
    func start(onDetection: @escaping @MainActor (PendingMeetingDetection) -> Void) {}
    func stop() {}
}

@MainActor
private final class AIWorkspaceNoopBrowserMeetingDetectionService: BrowserMeetingDetectionServicing {
    func start(onDetection: @escaping @MainActor (PendingMeetingDetection) -> Void) {}
    func stop() {}
}

private struct AIWorkspaceStubTranscriptionService: LocalTranscriptionServicing {
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

private struct AIWorkspaceStubSummaryService: LocalSummaryServicing {
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

private struct AIWorkspaceStubSummaryModelManager: LocalSummaryModelManaging {
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

private actor StubSingleMeetingAssistantService: SingleMeetingAssistantServicing {
    enum Mode {
        case success(String, [NoteAssistantCitation] = [])
        case failure(String)
    }

    private let mode: Mode
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

        switch mode {
        case let .success(text, citations):
            return SingleMeetingAssistantResponse(
                text: text,
                citations: citations,
                generatedAt: Date(timeIntervalSince1970: 1_700_999_999)
            )
        case let .failure(message):
            throw SingleMeetingAssistantError.failed(message)
        }
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
