import Foundation
import OatmealCore
import OatmealEdge
@testable import OatmealUI
import XCTest

@MainActor
final class SessionControllerSceneCoordinatorTests: XCTestCase {
    func testCoordinatorOpensMainWindowAndFocusesActiveSession() {
        let note = liveNote(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            title: "Design Review"
        )
        let model = makeModel(notes: [note])

        var openedWindowIDs: [String] = []
        let coordinator = SessionControllerSceneCoordinator(
            openWindow: { openedWindowIDs.append($0) },
            dismissWindow: { _ in }
        )

        coordinator.openMainWindow(with: model, openTranscript: true)

        XCTAssertEqual(openedWindowIDs, [OatmealSceneID.main])
        XCTAssertEqual(model.selectedSidebarItem, .allNotes)
        XCTAssertEqual(model.selectedNoteID, note.id)
        XCTAssertTrue(model.selectedNote?.liveSessionState.isTranscriptPanelPresented == true)
    }

    func testCoordinatorSyncPresentsControllerWhenSessionStateExists() {
        let note = liveNote(
            id: UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA")!,
            title: "Customer Call"
        )
        let model = makeModel(notes: [note])

        var openedWindowIDs: [String] = []
        var dismissedWindowIDs: [String] = []
        let coordinator = SessionControllerSceneCoordinator(
            openWindow: { openedWindowIDs.append($0) },
            dismissWindow: { dismissedWindowIDs.append($0) }
        )

        coordinator.syncSessionControllerWindow(with: model)

        XCTAssertEqual(openedWindowIDs, [OatmealSceneID.sessionController])
        XCTAssertTrue(dismissedWindowIDs.isEmpty)
    }

    func testCoordinatorSyncDismissesControllerWhenNoSessionStateExists() {
        let note = MeetingNote(
            id: UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!,
            title: "Archived",
            origin: .quickNote(createdAt: date(1_700_040_000)),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )
        let model = makeModel(notes: [note])

        var openedWindowIDs: [String] = []
        var dismissedWindowIDs: [String] = []
        let coordinator = SessionControllerSceneCoordinator(
            openWindow: { openedWindowIDs.append($0) },
            dismissWindow: { dismissedWindowIDs.append($0) }
        )

        coordinator.syncSessionControllerWindow(with: model)

        XCTAssertTrue(openedWindowIDs.isEmpty)
        XCTAssertEqual(dismissedWindowIDs, [OatmealSceneID.sessionController])
    }

    func testCoordinatorSyncDismissesControllerWhenOnlyRecentMenuBarStateExists() {
        let completedAt = date(1_700_040_080)
        var note = MeetingNote(
            id: UUID(uuidString: "BCBCBCBC-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!,
            title: "Recently Completed",
            origin: .quickNote(createdAt: date(1_700_040_000)),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )
        note.captureState.beginCapture(at: date(1_700_040_010))
        note.beginLiveSession(at: date(1_700_040_010), presentTranscriptPanel: false, tracksSystemAudio: false)
        note.captureState.complete(at: completedAt)
        note.completeLiveSession(at: completedAt)
        note.applyTranscript(
            [TranscriptSegment(text: "Ready to review.")],
            backend: .mock,
            executionKind: .placeholder,
            at: completedAt
        )
        note.applyEnhancedNote(EnhancedNote(summary: "Wrapped"), at: completedAt)

        let model = makeModel(notes: [note])

        var openedWindowIDs: [String] = []
        var dismissedWindowIDs: [String] = []
        let coordinator = SessionControllerSceneCoordinator(
            openWindow: { openedWindowIDs.append($0) },
            dismissWindow: { dismissedWindowIDs.append($0) }
        )

        XCTAssertNil(model.sessionControllerState)
        XCTAssertEqual(model.menuBarSessionState?.kind, .recent)

        coordinator.syncSessionControllerWindow(with: model)

        XCTAssertTrue(openedWindowIDs.isEmpty)
        XCTAssertEqual(dismissedWindowIDs, [OatmealSceneID.sessionController])
    }

    func testCoordinatorSyncDismissesWhenCurrentSessionWasManuallyHidden() {
        let note = liveNote(
            id: UUID(uuidString: "ACACACAC-1234-5678-90AB-ACACACACACAC")!,
            title: "Hidden Session"
        )
        let model = makeModel(notes: [note])
        model.dismissSessionController()

        var openedWindowIDs: [String] = []
        var dismissedWindowIDs: [String] = []
        let coordinator = SessionControllerSceneCoordinator(
            openWindow: { openedWindowIDs.append($0) },
            dismissWindow: { dismissedWindowIDs.append($0) }
        )

        coordinator.syncSessionControllerWindow(with: model)

        XCTAssertTrue(openedWindowIDs.isEmpty)
        XCTAssertEqual(dismissedWindowIDs, [OatmealSceneID.sessionController])
    }

    func testLaunchPresentationOnlyOpensWhenRecoverableSessionExists() {
        let note = liveNote(
            id: UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!,
            title: "Recovered Session"
        )
        let model = makeModel(notes: [note])

        var openedWindowIDs: [String] = []
        let coordinator = SessionControllerSceneCoordinator(
            openWindow: { openedWindowIDs.append($0) },
            dismissWindow: { _ in }
        )

        coordinator.presentSessionControllerOnLaunchIfNeeded(with: model)

        XCTAssertEqual(openedWindowIDs, [OatmealSceneID.sessionController])
    }

    func testLaunchPresentationSkipsSessionHiddenForCurrentPresentationIdentity() {
        let note = liveNote(
            id: UUID(uuidString: "0A0A0A0A-1234-1234-1234-1234567890AB")!,
            title: "Hidden On Relaunch"
        )
        let model = makeModel(notes: [note])
        model.dismissSessionController()

        var openedWindowIDs: [String] = []
        let coordinator = SessionControllerSceneCoordinator(
            openWindow: { openedWindowIDs.append($0) },
            dismissWindow: { _ in }
        )

        coordinator.presentSessionControllerOnLaunchIfNeeded(with: model)

        XCTAssertTrue(openedWindowIDs.isEmpty)
        XCTAssertFalse(model.shouldAutoPresentSessionControllerOnLaunch)
    }

    func testLaunchPresentationOpensRecoveredSessionAfterRelaunchRecovery() {
        let startedAt = date(1_700_040_200)
        let recoveredAt = date(1_700_040_260)
        var note = MeetingNote(
            id: UUID(uuidString: "0B0B0B0B-1234-1234-1234-1234567890AB")!,
            title: "Recovered After Relaunch",
            origin: .quickNote(createdAt: startedAt),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )
        note.captureState.beginCapture(at: startedAt)
        note.beginLiveSession(at: startedAt, presentTranscriptPanel: true, tracksSystemAudio: true)
        note.captureState.fail(
            reason: "Oatmeal restored this live session after relaunch. Resume capture to continue recording and live transcription.",
            at: recoveredAt,
            recoverable: true
        )
        note.recordLiveSessionInterruption(updatedAt: recoveredAt)
        note.markLiveSessionRecovered(
            message: "Oatmeal restored this live session after relaunch. Resume capture to continue recording and live transcription.",
            at: recoveredAt
        )

        let model = makeModel(notes: [note])

        var openedWindowIDs: [String] = []
        let coordinator = SessionControllerSceneCoordinator(
            openWindow: { openedWindowIDs.append($0) },
            dismissWindow: { _ in }
        )

        coordinator.presentSessionControllerOnLaunchIfNeeded(with: model)

        XCTAssertTrue(model.shouldAutoPresentSessionControllerOnLaunch)
        XCTAssertEqual(openedWindowIDs, [OatmealSceneID.sessionController])
    }

    private func makeModel(notes: [MeetingNote]) -> AppViewModel {
        let persistence = AppPersistence(
            applicationSupportFolderName: "OatmealSessionControllerSceneCoordinatorTests-\(UUID().uuidString)",
            stateFileName: "state.json"
        )
        let model = AppViewModel(
            store: InMemoryOatmealStore(notes: notes),
            calendarService: CoordinatorStubCalendarService(),
            captureService: CoordinatorStubCaptureAccessService(),
            captureEngine: CoordinatorStubCaptureEngine(),
            transcriptionService: CoordinatorStubTranscriptionService(
                result: TranscriptionJobResult(
                    segments: [],
                    backend: .mock,
                    executionKind: .placeholder
                )
            ),
            summaryService: CoordinatorStubSummaryService(),
            summaryModelManager: CoordinatorStubSummaryModelManager(),
            persistence: persistence,
            nowProvider: { Date(timeIntervalSince1970: 1_700_040_100) }
        )
        model.selectedNoteID = notes.first?.id
        return model
    }

    private func liveNote(id: UUID, title: String) -> MeetingNote {
        let startedAt = date(1_700_040_010)
        var note = MeetingNote(
            id: id,
            title: title,
            origin: .quickNote(createdAt: startedAt),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )
        note.captureState.beginCapture(at: startedAt)
        note.beginLiveSession(at: startedAt, presentTranscriptPanel: false, tracksSystemAudio: true)
        return note
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}

@MainActor
private struct CoordinatorStubCalendarService: CalendarAccessServing {
    func authorizationStatus() -> PermissionStatus { .granted }
    func requestAccess() async -> PermissionStatus { .granted }
    func upcomingEvents(referenceDate: Date, horizon: TimeInterval) async throws -> [CalendarEvent] { [] }
}

@MainActor
private struct CoordinatorStubCaptureAccessService: CaptureAccessServing {
    func currentPermissions(calendarStatus: PermissionStatus) async -> CapturePermissions { CapturePermissions() }
    func requestPermissions(requiresSystemAudio: Bool, calendarStatus: PermissionStatus) async -> CapturePermissions { CapturePermissions() }
}

@MainActor
private final class CoordinatorStubCaptureEngine: MeetingCaptureEngineServing {
    var activeSession: ActiveCaptureSession?

    func startCapture(for noteID: UUID, mode: CaptureMode) async throws -> ActiveCaptureSession {
        throw CaptureEngineError.failedToStartRecording("Not needed for coordinator tests.")
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

private struct CoordinatorStubTranscriptionService: LocalTranscriptionServicing {
    let result: TranscriptionJobResult

    func runtimeState(configuration: LocalTranscriptionConfiguration) async -> LocalTranscriptionRuntimeState {
        LocalTranscriptionRuntimeState(
            modelsDirectoryURL: FileManager.default.temporaryDirectory,
            discoveredModels: [],
            backends: [],
            activePlanSummary: "Test"
        )
    }

    func executionPlan(configuration: LocalTranscriptionConfiguration) async throws -> TranscriptionExecutionPlan {
        TranscriptionExecutionPlan(
            backend: .mock,
            executionKind: .placeholder,
            summary: "Test"
        )
    }

    func transcribe(request: TranscriptionRequest, configuration: LocalTranscriptionConfiguration) async throws -> TranscriptionJobResult {
        result
    }
}

private struct CoordinatorStubSummaryService: LocalSummaryServicing {
    func runtimeState(configuration: LocalSummaryConfiguration) async -> LocalSummaryRuntimeState {
        LocalSummaryRuntimeState(
            modelsDirectoryURL: FileManager.default.temporaryDirectory,
            discoveredModels: [],
            preferredModelName: nil,
            backends: [],
            activePlanSummary: "Test"
        )
    }

    func executionPlan(configuration: LocalSummaryConfiguration) async throws -> LocalSummaryExecutionPlan {
        LocalSummaryExecutionPlan(
            backend: .placeholder,
            executionKind: .placeholder,
            summary: "Test"
        )
    }

    func generate(request: NoteGenerationRequest, configuration: LocalSummaryConfiguration) async throws -> SummaryJobResult {
        SummaryJobResult(
            enhancedNote: EnhancedNote(
                summary: "Test summary"
            ),
            backend: .placeholder,
            executionKind: .placeholder
        )
    }
}

private struct CoordinatorStubSummaryModelManager: LocalSummaryModelManaging {
    func catalogState() async -> SummaryModelCatalogState {
        SummaryModelCatalogState(
            modelsDirectoryURL: FileManager.default.temporaryDirectory,
            downloadAvailability: .available,
            downloadRuntimeDetail: "Test",
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
