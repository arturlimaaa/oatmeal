import Foundation
import OatmealCore
import OatmealEdge
@testable import OatmealUI
import XCTest

@MainActor
final class SessionControllerCommandTests: XCTestCase {
    func testFocusSessionControllerNoteUsesHighestPrioritySessionAndOpensTranscript() {
        let liveStartedAt = date(1_700_050_000)
        var liveNote = MeetingNote(
            id: UUID(uuidString: "AAAA0000-1111-2222-3333-444444444444")!,
            title: "Live Review",
            origin: .quickNote(createdAt: liveStartedAt),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )
        liveNote.captureState.beginCapture(at: liveStartedAt)
        liveNote.beginLiveSession(at: liveStartedAt, presentTranscriptPanel: false, tracksSystemAudio: true)

        var processingNote = MeetingNote(
            id: UUID(uuidString: "BBBB0000-1111-2222-3333-444444444444")!,
            title: "Queued Follow Up",
            origin: .quickNote(createdAt: date(1_700_050_050)),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )
        processingNote.captureState.complete(at: date(1_700_050_080))
        processingNote.completeLiveSession(
            message: "Recording stopped. Oatmeal is still transcribing.",
            at: date(1_700_050_080)
        )
        processingNote.queueTranscription(at: date(1_700_050_081))

        let model = makeModel(
            notes: [processingNote, liveNote],
            captureEngine: CommandStubCaptureEngine()
        )
        model.selectedNoteID = processingNote.id

        model.focusSessionControllerNote(openTranscript: true)

        XCTAssertEqual(model.selectedSidebarItem, .allNotes)
        XCTAssertEqual(model.selectedNoteID, liveNote.id)
        XCTAssertTrue(model.selectedNote?.liveSessionState.isTranscriptPanelPresented == true)
    }

    func testStartQuickNoteCaptureStartsCaptureThroughShellCommand() async {
        let captureEngine = CommandStubCaptureEngine()
        let model = makeModel(notes: [], captureEngine: captureEngine)

        await model.startQuickNoteCapture()

        XCTAssertEqual(captureEngine.startCalls, 1)
        XCTAssertEqual(model.selectedSidebarItem, .allNotes)
        XCTAssertEqual(model.selectedNote?.title, "Quick Note")
        XCTAssertEqual(model.selectedNote?.captureState.phase, .capturing)
        XCTAssertEqual(model.sessionControllerState?.kind, .active)
        XCTAssertEqual(model.sessionControllerState?.captureLabel, "Recording")
    }

    func testStopSessionControllerCaptureStopsActiveCaptureThroughShellCommand() async {
        let noteID = UUID(uuidString: "CCCC0000-1111-2222-3333-444444444444")!
        let startedAt = date(1_700_050_100)
        var note = MeetingNote(
            id: noteID,
            title: "Active Session",
            origin: .quickNote(createdAt: startedAt),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )
        note.captureState.beginCapture(at: startedAt)
        note.beginLiveSession(at: startedAt, presentTranscriptPanel: false, tracksSystemAudio: false)

        let captureEngine = CommandStubCaptureEngine(
            activeSession: ActiveCaptureSession(
                noteID: noteID,
                startedAt: startedAt,
                fileURL: recordingURL(named: "session-controller-stop.m4a"),
                mode: .microphoneOnly
            ),
            artifact: CaptureArtifact(
                noteID: noteID,
                fileURL: recordingURL(named: "session-controller-stop.m4a"),
                startedAt: startedAt,
                endedAt: date(1_700_050_220),
                mode: .microphoneOnly
            )
        )
        let model = makeModel(
            notes: [note],
            captureEngine: captureEngine,
            transcriptionService: CommandStubTranscriptionService(
                delayNanoseconds: 250_000_000,
                result: TranscriptionJobResult(
                    segments: [TranscriptSegment(text: "Follow up next week.")],
                    backend: .mock,
                    executionKind: .placeholder
                )
            )
        )
        model.selectedNoteID = noteID

        await model.stopSessionControllerCapture()

        XCTAssertEqual(captureEngine.stopCalls, 1)
        XCTAssertEqual(model.selectedNoteID, noteID)
        XCTAssertEqual(model.selectedNote?.captureState.phase, .complete)
        XCTAssertEqual(model.selectedNote?.processingState.stage, .transcription)
        XCTAssertEqual(model.sessionControllerState?.kind, .processing)
    }

    func testStopSessionControllerCaptureForTerminationReturnsTrueAfterSafeStop() async {
        let noteID = UUID(uuidString: "DEDE0000-1111-2222-3333-444444444444")!
        let startedAt = date(1_700_050_150)
        var note = MeetingNote(
            id: noteID,
            title: "Quit Flow Demo",
            origin: .quickNote(createdAt: startedAt),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )
        note.captureState.beginCapture(at: startedAt)
        note.beginLiveSession(at: startedAt, presentTranscriptPanel: false, tracksSystemAudio: false)

        let captureEngine = CommandStubCaptureEngine(
            activeSession: ActiveCaptureSession(
                noteID: noteID,
                startedAt: startedAt,
                fileURL: recordingURL(named: "termination-stop-success.m4a"),
                mode: .microphoneOnly
            ),
            artifact: CaptureArtifact(
                noteID: noteID,
                fileURL: recordingURL(named: "termination-stop-success.m4a"),
                startedAt: startedAt,
                endedAt: date(1_700_050_260),
                mode: .microphoneOnly
            )
        )
        let model = makeModel(
            notes: [note],
            captureEngine: captureEngine,
            transcriptionService: CommandStubTranscriptionService(
                delayNanoseconds: 250_000_000,
                result: TranscriptionJobResult(
                    segments: [TranscriptSegment(text: "Safe stop complete.")],
                    backend: .mock,
                    executionKind: .placeholder
                )
            )
        )
        model.selectedNoteID = noteID

        let didStopSafely = await model.stopSessionControllerCaptureForTermination()

        XCTAssertTrue(didStopSafely)
        XCTAssertEqual(captureEngine.stopCalls, 1)
        XCTAssertEqual(model.selectedNote?.captureState.phase, .complete)
        XCTAssertEqual(model.sessionControllerState?.kind, .processing)
    }

    func testStopSessionControllerCaptureForTerminationClearsQuitPromptAfterSafeStop() async {
        let noteID = UUID(uuidString: "DEDF0000-1111-2222-3333-444444444444")!
        let startedAt = date(1_700_050_155)
        var note = MeetingNote(
            id: noteID,
            title: "Quit Prompt Reset",
            origin: .quickNote(createdAt: startedAt),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )
        note.captureState.beginCapture(at: startedAt)
        note.beginLiveSession(at: startedAt, presentTranscriptPanel: false, tracksSystemAudio: false)

        let captureEngine = CommandStubCaptureEngine(
            activeSession: ActiveCaptureSession(
                noteID: noteID,
                startedAt: startedAt,
                fileURL: recordingURL(named: "termination-prompt-reset.m4a"),
                mode: .microphoneOnly
            ),
            artifact: CaptureArtifact(
                noteID: noteID,
                fileURL: recordingURL(named: "termination-prompt-reset.m4a"),
                startedAt: startedAt,
                endedAt: date(1_700_050_265),
                mode: .microphoneOnly
            )
        )
        let model = makeModel(
            notes: [note],
            captureEngine: captureEngine,
            transcriptionService: CommandStubTranscriptionService(
                delayNanoseconds: 250_000_000,
                result: TranscriptionJobResult(
                    segments: [TranscriptSegment(text: "Stop-and-quit path is safe.")],
                    backend: .mock,
                    executionKind: .placeholder
                )
            )
        )
        model.selectedNoteID = noteID

        XCTAssertNotNil(AppTerminationPolicy.prompt(for: model.sessionControllerState))

        let didStopSafely = await model.stopSessionControllerCaptureForTermination()

        XCTAssertTrue(didStopSafely)
        XCTAssertNil(AppTerminationPolicy.prompt(for: model.sessionControllerState))
        XCTAssertEqual(model.sessionControllerState?.kind, .processing)
    }

    func testStopSessionControllerCaptureForTerminationReturnsFalseWhenStopFails() async {
        let noteID = UUID(uuidString: "ABCD0000-1111-2222-3333-444444444444")!
        let startedAt = date(1_700_050_180)
        var note = MeetingNote(
            id: noteID,
            title: "Termination Failure Demo",
            origin: .quickNote(createdAt: startedAt),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )
        note.captureState.beginCapture(at: startedAt)
        note.beginLiveSession(at: startedAt, presentTranscriptPanel: false, tracksSystemAudio: false)

        let captureEngine = CommandStubCaptureEngine(
            activeSession: ActiveCaptureSession(
                noteID: noteID,
                startedAt: startedAt,
                fileURL: recordingURL(named: "termination-stop-failure.m4a"),
                mode: .microphoneOnly
            ),
            artifact: CaptureArtifact(
                noteID: noteID,
                fileURL: recordingURL(named: "termination-stop-failure.m4a"),
                startedAt: startedAt,
                endedAt: date(1_700_050_280),
                mode: .microphoneOnly
            ),
            stopErrorMessage: "Microphone capture could not be finalized."
        )
        let model = makeModel(notes: [note], captureEngine: captureEngine)
        model.selectedNoteID = noteID

        let didStopSafely = await model.stopSessionControllerCaptureForTermination()

        XCTAssertFalse(didStopSafely)
        XCTAssertEqual(captureEngine.stopCalls, 1)
        XCTAssertEqual(model.selectedNote?.captureState.phase, .failed)
        XCTAssertEqual(model.sessionControllerState?.kind, .active)
    }

    func testRouteMainWindowFromLightweightSurfaceFallsBackToSelectedNoteWhenIdle() {
        let note = MeetingNote(
            id: UUID(uuidString: "EEEE0000-1111-2222-3333-444444444444")!,
            title: "Weekly Notes",
            origin: .quickNote(createdAt: date(1_700_050_320)),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )
        let model = makeModel(notes: [note], captureEngine: CommandStubCaptureEngine())
        model.selectedSidebarItem = .upcoming
        model.selectedUpcomingEventID = UUID(uuidString: "99999999-8888-7777-6666-555555555555")
        model.selectedNoteID = note.id

        let route = model.routeMainWindowFromLightweightSurface()

        XCTAssertEqual(route, .note(noteID: note.id))
        XCTAssertEqual(model.selectedSidebarItem, .allNotes)
        XCTAssertEqual(model.selectedNoteID, note.id)
    }

    func testRouteMainWindowFromLightweightSurfaceFallsBackToUpcomingMeetingWhenNoNotesExist() {
        let eventID = UUID(uuidString: "12121212-3434-5656-7878-909090909090")!
        let upcomingEvent = CalendarEvent(
            id: eventID,
            title: "Roadmap Review",
            startDate: date(1_700_050_600),
            endDate: date(1_700_050_960),
            attendees: [],
            source: .manual
        )
        let model = makeModel(notes: [], captureEngine: CommandStubCaptureEngine())
        model.upcomingMeetings = [upcomingEvent]
        model.selectedSidebarItem = .allNotes
        model.selectedNoteID = nil

        let route = model.routeMainWindowFromLightweightSurface()

        XCTAssertEqual(route, .upcoming(eventID: eventID))
        XCTAssertEqual(model.selectedSidebarItem, .upcoming)
        XCTAssertEqual(model.selectedUpcomingEventID, eventID)
    }

    func testRouteMainWindowFromLightweightSurfacePrefersRecentCompletedMenuBarState() {
        let startedAt = date(1_700_050_120)
        let completedAt = date(1_700_050_240)
        var recentNote = MeetingNote(
            id: UUID(uuidString: "EEEE1000-1111-2222-3333-444444444444")!,
            title: "Finished Design Review",
            origin: .quickNote(createdAt: startedAt),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )
        recentNote.captureState.beginCapture(at: startedAt)
        recentNote.beginLiveSession(at: startedAt, presentTranscriptPanel: false, tracksSystemAudio: false)
        recentNote.captureState.complete(at: completedAt)
        recentNote.completeLiveSession(at: completedAt)
        recentNote.applyTranscript(
            [TranscriptSegment(text: "Final transcript")],
            backend: .mock,
            executionKind: .placeholder,
            at: completedAt
        )
        recentNote.applyEnhancedNote(
            EnhancedNote(summary: "Recent note"),
            at: completedAt
        )

        let olderIdleNote = MeetingNote(
            id: UUID(uuidString: "EEEE2000-1111-2222-3333-444444444444")!,
            title: "Backlog",
            origin: .quickNote(createdAt: date(1_700_040_320)),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )

        let model = makeModel(notes: [olderIdleNote, recentNote], captureEngine: CommandStubCaptureEngine())
        model.selectedNoteID = olderIdleNote.id

        XCTAssertNil(model.sessionControllerState)
        XCTAssertEqual(model.menuBarSessionState?.kind, .recent)

        let route = model.routeMainWindowFromLightweightSurface(openTranscript: true)

        XCTAssertEqual(route, .note(noteID: recentNote.id))
        XCTAssertEqual(model.selectedSidebarItem, .allNotes)
        XCTAssertEqual(model.selectedNoteID, recentNote.id)
        XCTAssertTrue(model.selectedNote?.liveSessionState.isTranscriptPanelPresented == true)
    }

    func testDetectedMeetingSurfacesAsPendingPromptWithoutOpeningRecorderShell() {
        let model = makeModel(notes: [], captureEngine: CommandStubCaptureEngine())
        let detectedMeeting = detectedMeetingContext(
            id: UUID(uuidString: "11110000-AAAA-BBBB-CCCC-DDDDDDDDDDDD")!,
            detectedAt: date(1_700_051_200)
        )

        var openedWindowIDs: [String] = []
        var dismissedWindowIDs: [String] = []
        let coordinator = SessionControllerSceneCoordinator(
            openWindow: { openedWindowIDs.append($0) },
            dismissWindow: { dismissedWindowIDs.append($0) }
        )
        let router = SessionControllerCommandRouter(model: model, coordinator: coordinator)

        router.receiveMeetingDetection(detectedMeeting)

        guard let prompt = model.detectionPromptState else {
            XCTFail("Expected a pending detected meeting prompt.")
            return
        }
        XCTAssertEqual(prompt.title, "Untitled Meeting")
        XCTAssertEqual(prompt.sourceName, "Google Chrome")
        XCTAssertEqual(prompt.headline, "Meeting detected")
        XCTAssertEqual(prompt.primaryActionTitle, "Start Oatmeal")
        XCTAssertEqual(model.menuBarMeetingDetectionState?.kind, .prompt)
        XCTAssertNil(model.sessionControllerState)
        XCTAssertNil(model.selectedNoteID)
        XCTAssertEqual(model.selectedSidebarItem, .upcoming)
        XCTAssertEqual(openedWindowIDs, [OatmealSceneID.meetingDetectionPrompt])
        XCTAssertTrue(dismissedWindowIDs.isEmpty)
    }

    func testIgnoringDetectedMeetingPromptDowngradesToPassiveMenuBarSuggestion() {
        let model = makeModel(notes: [], captureEngine: CommandStubCaptureEngine())
        let detectedMeeting = detectedMeetingContext(
            id: UUID(uuidString: "22220000-AAAA-BBBB-CCCC-DDDDDDDDDDDD")!,
            detectedAt: date(1_700_051_300)
        )

        var openedWindowIDs: [String] = []
        var dismissedWindowIDs: [String] = []
        let coordinator = SessionControllerSceneCoordinator(
            openWindow: { openedWindowIDs.append($0) },
            dismissWindow: { dismissedWindowIDs.append($0) }
        )
        let router = SessionControllerCommandRouter(model: model, coordinator: coordinator)

        router.receiveMeetingDetection(detectedMeeting)
        router.ignorePendingMeetingDetection()

        XCTAssertNil(model.detectionPromptState)
        guard let suggestion = model.menuBarMeetingDetectionState else {
            XCTFail("Expected a passive detected meeting suggestion after ignoring the prompt.")
            return
        }
        XCTAssertEqual(suggestion.title, "Untitled Meeting")
        XCTAssertEqual(suggestion.sourceName, "Google Chrome")
        XCTAssertEqual(suggestion.kind, .passiveSuggestion)
        XCTAssertEqual(suggestion.primaryActionTitle, "Start Oatmeal")
        XCTAssertNil(model.sessionControllerState)
        XCTAssertEqual(openedWindowIDs, [OatmealSceneID.meetingDetectionPrompt])
        XCTAssertEqual(dismissedWindowIDs, [OatmealSceneID.meetingDetectionPrompt])
    }

    func testStartingDetectedMeetingCaptureClearsPromptAndHandsOffToSessionController() async {
        let captureEngine = CommandStubCaptureEngine()
        let model = makeModel(notes: [], captureEngine: captureEngine)
        let detectedMeeting = detectedMeetingContext(
            id: UUID(uuidString: "33330000-AAAA-BBBB-CCCC-DDDDDDDDDDDD")!,
            detectedAt: date(1_700_051_400)
        )

        var openedWindowIDs: [String] = []
        var dismissedWindowIDs: [String] = []
        let coordinator = SessionControllerSceneCoordinator(
            openWindow: { openedWindowIDs.append($0) },
            dismissWindow: { dismissedWindowIDs.append($0) }
        )
        let router = SessionControllerCommandRouter(model: model, coordinator: coordinator)

        router.receiveMeetingDetection(detectedMeeting)

        await router.startPendingMeetingDetection()

        XCTAssertEqual(captureEngine.startCalls, 1)
        XCTAssertNil(model.pendingMeetingDetection)
        XCTAssertNil(model.detectionPromptState)
        XCTAssertNil(model.menuBarMeetingDetectionState)
        XCTAssertEqual(model.selectedNote?.title, "Untitled Meeting")
        XCTAssertEqual(model.selectedNote?.captureState.phase, .capturing)
        XCTAssertEqual(model.sessionControllerState?.kind, .active)
        XCTAssertEqual(
            openedWindowIDs,
            [OatmealSceneID.meetingDetectionPrompt, OatmealSceneID.sessionController]
        )
        XCTAssertEqual(dismissedWindowIDs, [OatmealSceneID.meetingDetectionPrompt])
    }

    func testSharedCommandRouterOpensRecoveredTranscriptInMainWindow() {
        let recoveredNoteID = UUID(uuidString: "ABAB0000-1111-2222-3333-444444444444")!
        let idleNoteID = UUID(uuidString: "CDCD0000-1111-2222-3333-444444444444")!
        let recoveredAt = date(1_700_050_500)

        var recoveredNote = MeetingNote(
            id: recoveredNoteID,
            title: "Recovered Standup",
            origin: .quickNote(createdAt: recoveredAt),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )
        recoveredNote.captureState.beginCapture(at: recoveredAt)
        recoveredNote.beginLiveSession(at: recoveredAt, presentTranscriptPanel: false, tracksSystemAudio: true)
        recoveredNote.captureState.pause(at: recoveredAt.addingTimeInterval(90))
        recoveredNote.markLiveSessionRecovered(
            message: "Oatmeal recovered the live session after a capture interruption.",
            at: recoveredAt.addingTimeInterval(91)
        )

        let idleNote = MeetingNote(
            id: idleNoteID,
            title: "Backlog Cleanup",
            origin: .quickNote(createdAt: recoveredAt.addingTimeInterval(-600)),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )

        let model = makeModel(notes: [idleNote, recoveredNote], captureEngine: CommandStubCaptureEngine())
        model.selectedNoteID = idleNoteID

        var openedWindowIDs: [String] = []
        let router = SessionControllerCommandRouter(
            model: model,
            coordinator: SessionControllerSceneCoordinator(
                openWindow: { openedWindowIDs.append($0) },
                dismissWindow: { _ in }
            )
        )

        let route = router.openMainWindow(openTranscript: true)

        XCTAssertEqual(route, .session(noteID: recoveredNoteID, opensTranscript: true))
        XCTAssertEqual(openedWindowIDs, [OatmealSceneID.main])
        XCTAssertEqual(model.selectedSidebarItem, .allNotes)
        XCTAssertEqual(model.selectedNoteID, recoveredNoteID)
        XCTAssertTrue(model.selectedNote?.liveSessionState.isTranscriptPanelPresented == true)
    }

    func testModelSessionControllerStateSurfacesDelayedLiveSession() throws {
        let noteID = UUID(uuidString: "ABAC0000-1111-2222-3333-444444444444")!
        let startedAt = date(1_700_050_700)
        var note = MeetingNote(
            id: noteID,
            title: "Catching Up Session",
            origin: .quickNote(createdAt: startedAt),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )
        note.captureState.beginCapture(at: startedAt)
        note.beginLiveSession(at: startedAt, presentTranscriptPanel: true, tracksSystemAudio: true)
        note.markLiveSessionDelayed(
            message: "Oatmeal kept the recording safe and is catching up on live transcript work.",
            at: startedAt.addingTimeInterval(90)
        )
        note.updateLiveCaptureSource(
            .systemAudio,
            status: .delayed,
            message: "System audio is temporarily behind the microphone stream.",
            updatedAt: startedAt.addingTimeInterval(91)
        )

        let model = makeModel(notes: [note], captureEngine: CommandStubCaptureEngine())
        let state = try XCTUnwrap(model.sessionControllerState)

        XCTAssertEqual(state.noteID, noteID)
        XCTAssertEqual(state.healthLabel, "Delayed")
        XCTAssertEqual(state.controllerStatusTitle, "Catching up live transcript")
        XCTAssertEqual(
            state.controllerStatusDetail,
            "Oatmeal kept the recording safe and is catching up on live transcript work."
        )
        XCTAssertEqual(state.systemAudioLabel, "Delayed")
    }

    func testModelSessionControllerStateSurfacesInterruptedLiveSession() throws {
        let noteID = UUID(uuidString: "ABAD0000-1111-2222-3333-444444444444")!
        let startedAt = date(1_700_050_760)
        let failedAt = date(1_700_050_820)
        var note = MeetingNote(
            id: noteID,
            title: "Interrupted Capture",
            origin: .quickNote(createdAt: startedAt),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )
        note.captureState.beginCapture(at: startedAt)
        note.beginLiveSession(at: startedAt, presentTranscriptPanel: true, tracksSystemAudio: false)
        note.captureState.fail(reason: "The microphone stream stopped unexpectedly.", at: failedAt, recoverable: true)
        note.recordLiveSessionInterruption(updatedAt: failedAt)
        note.failLiveSession(message: "Capture needs attention before live updates can continue.", at: failedAt)
        note.updateLiveCaptureSource(
            .microphone,
            status: .failed,
            message: "Microphone audio dropped out.",
            updatedAt: failedAt
        )

        let model = makeModel(notes: [note], captureEngine: CommandStubCaptureEngine())
        let state = try XCTUnwrap(model.sessionControllerState)

        XCTAssertEqual(state.noteID, noteID)
        XCTAssertEqual(state.kind, .active)
        XCTAssertEqual(state.captureLabel, "Interrupted")
        XCTAssertEqual(state.controllerStatusTitle, "Capture interrupted")
        XCTAssertEqual(
            state.controllerStatusDetail,
            "Capture needs attention before live updates can continue."
        )
    }

    func testDismissAndReopenSessionControllerTrackCurrentSessionVisibility() {
        let startedAt = date(1_700_050_900)
        var note = MeetingNote(
            id: UUID(uuidString: "EFEF0000-1111-2222-3333-444444444444")!,
            title: "Demo Session",
            origin: .quickNote(createdAt: startedAt),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )
        note.captureState.beginCapture(at: startedAt)
        note.beginLiveSession(at: startedAt, presentTranscriptPanel: false, tracksSystemAudio: true)

        let model = makeModel(notes: [note], captureEngine: CommandStubCaptureEngine())

        XCTAssertFalse(model.isSessionControllerDismissedForCurrentState)

        model.dismissSessionController()
        XCTAssertTrue(model.isSessionControllerDismissedForCurrentState)

        model.reopenSessionController()
        XCTAssertFalse(model.isSessionControllerDismissedForCurrentState)

        model.toggleSessionControllerCollapsed()
        XCTAssertTrue(model.isSessionControllerCollapsed)

        model.toggleSessionControllerCollapsed()
        XCTAssertFalse(model.isSessionControllerCollapsed)
    }

    func testPostCaptureHandoffClearsDismissedAndCollapsedStateForNewPresentationIdentity() async {
        let noteID = UUID(uuidString: "FAFA0000-1111-2222-3333-444444444444")!
        let startedAt = date(1_700_050_940)
        var note = MeetingNote(
            id: noteID,
            title: "Handoff Session",
            origin: .quickNote(createdAt: startedAt),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )
        note.captureState.beginCapture(at: startedAt)
        note.beginLiveSession(at: startedAt, presentTranscriptPanel: false, tracksSystemAudio: false)

        let captureEngine = CommandStubCaptureEngine(
            activeSession: ActiveCaptureSession(
                noteID: noteID,
                startedAt: startedAt,
                fileURL: recordingURL(named: "session-controller-handoff.m4a"),
                mode: .microphoneOnly
            ),
            artifact: CaptureArtifact(
                noteID: noteID,
                fileURL: recordingURL(named: "session-controller-handoff.m4a"),
                startedAt: startedAt,
                endedAt: date(1_700_051_040),
                mode: .microphoneOnly
            )
        )
        let model = makeModel(
            notes: [note],
            captureEngine: captureEngine,
            transcriptionService: CommandStubTranscriptionService(
                delayNanoseconds: 250_000_000,
                result: TranscriptionJobResult(
                    segments: [TranscriptSegment(text: "Background handoff completed.")],
                    backend: .mock,
                    executionKind: .placeholder
                )
            )
        )

        model.dismissSessionController()
        XCTAssertTrue(model.isSessionControllerDismissedForCurrentState)

        model.reopenSessionController()
        model.toggleSessionControllerCollapsed()
        XCTAssertTrue(model.isSessionControllerCollapsed)

        await model.stopSessionControllerCapture()

        XCTAssertEqual(model.sessionControllerState?.kind, .processing)
        XCTAssertFalse(model.isSessionControllerDismissedForCurrentState)
        XCTAssertFalse(model.isSessionControllerCollapsed)
    }

    func testPersistenceRestoresLightweightRoutingAndCollapsedControllerState() {
        let startedAt = date(1_700_051_000)
        var note = MeetingNote(
            id: UUID(uuidString: "FEFE0000-1111-2222-3333-444444444444")!,
            title: "Recovered Demo",
            origin: .quickNote(createdAt: startedAt),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )
        note.captureState.beginCapture(at: startedAt)
        note.beginLiveSession(at: startedAt, presentTranscriptPanel: true, tracksSystemAudio: true)

        let persistence = AppPersistence(
            applicationSupportFolderName: "OatmealSessionControllerRestoreTests-\(UUID().uuidString)",
            stateFileName: "state.json"
        )

        let firstModel = makeModel(
            notes: [note],
            captureEngine: CommandStubCaptureEngine(),
            persistence: persistence
        )
        firstModel.setSelectedSidebarItem(.allNotes)
        firstModel.setSelectedNoteID(note.id)
        firstModel.toggleSessionControllerCollapsed()

        let restoredModel = makeModel(
            notes: [],
            captureEngine: CommandStubCaptureEngine(),
            persistence: persistence
        )

        XCTAssertEqual(restoredModel.selectedSidebarItem, .allNotes)
        XCTAssertEqual(restoredModel.selectedNoteID, note.id)
        XCTAssertEqual(restoredModel.selectedNote?.id, note.id)
        XCTAssertTrue(restoredModel.isSessionControllerCollapsed)
        XCTAssertTrue(restoredModel.selectedNote?.liveSessionState.isTranscriptPanelPresented == true)
    }

    private func makeModel(
        notes: [MeetingNote],
        captureEngine: CommandStubCaptureEngine,
        transcriptionService: CommandStubTranscriptionService = CommandStubTranscriptionService(),
        persistence: AppPersistence? = nil
    ) -> AppViewModel {
        let persistence = persistence ?? AppPersistence(
            applicationSupportFolderName: "OatmealSessionControllerCommandTests-\(UUID().uuidString)",
            stateFileName: "state.json"
        )

        let model = AppViewModel(
            store: InMemoryOatmealStore(notes: notes),
            calendarService: CommandStubCalendarService(),
            captureService: CommandStubCaptureAccessService(),
            captureEngine: captureEngine,
            transcriptionService: transcriptionService,
            summaryService: CommandStubSummaryService(),
            summaryModelManager: CommandStubSummaryModelManager(),
            persistence: persistence,
            nowProvider: { Date(timeIntervalSince1970: 1_700_050_300) }
        )

        if model.selectedNoteID == nil {
            model.selectedNoteID = notes.first?.id
        }
        return model
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func recordingURL(named name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: false)
    }

    private func detectedMeetingContext(
        id: UUID,
        detectedAt: Date
    ) -> PendingMeetingDetection {
        PendingMeetingDetection(
            id: id,
            title: "Untitled Meeting",
            source: .browser("Google Chrome"),
            detectedAt: detectedAt,
            presentation: .prompt
        )
    }
}

@MainActor
private struct CommandStubCalendarService: CalendarAccessServing {
    func authorizationStatus() -> PermissionStatus { .granted }
    func requestAccess() async -> PermissionStatus { .granted }
    func upcomingEvents(referenceDate: Date, horizon: TimeInterval) async throws -> [CalendarEvent] { [] }
}

@MainActor
private struct CommandStubCaptureAccessService: CaptureAccessServing {
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
private final class CommandStubCaptureEngine: MeetingCaptureEngineServing {
    var activeSession: ActiveCaptureSession?
    var artifact: CaptureArtifact
    var stopErrorMessage: String?
    private(set) var startCalls = 0
    private(set) var stopCalls = 0
    private var recordingURLs: [UUID: URL] = [:]

    init(
        activeSession: ActiveCaptureSession? = nil,
        artifact: CaptureArtifact? = nil,
        stopErrorMessage: String? = nil
    ) {
        let defaultArtifact = CaptureArtifact(
            noteID: UUID(uuidString: "DDDD0000-1111-2222-3333-444444444444")!,
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("session-controller-default.m4a"),
            startedAt: Date(timeIntervalSince1970: 1_700_050_010),
            endedAt: Date(timeIntervalSince1970: 1_700_050_120),
            mode: .microphoneOnly
        )
        self.activeSession = activeSession
        self.artifact = artifact ?? defaultArtifact
        self.stopErrorMessage = stopErrorMessage
        if let activeSession {
            recordingURLs[activeSession.noteID] = activeSession.fileURL
        }
        recordingURLs[self.artifact.noteID] = self.artifact.fileURL
    }

    func startCapture(for noteID: UUID, mode: CaptureMode) async throws -> ActiveCaptureSession {
        startCalls += 1
        let session = ActiveCaptureSession(
            noteID: noteID,
            startedAt: Date(timeIntervalSince1970: 1_700_050_020),
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(noteID.uuidString).m4a"),
            mode: mode
        )
        activeSession = session
        artifact = CaptureArtifact(
            noteID: noteID,
            fileURL: session.fileURL,
            startedAt: session.startedAt,
            endedAt: Date(timeIntervalSince1970: 1_700_050_220),
            mode: mode
        )
        recordingURLs[noteID] = session.fileURL
        return session
    }

    func stopCapture() async throws -> CaptureArtifact {
        stopCalls += 1
        if let stopErrorMessage {
            throw CaptureEngineError.failedToStopRecording(stopErrorMessage)
        }
        activeSession = nil
        recordingURLs[artifact.noteID] = artifact.fileURL
        return artifact
    }

    func recordingURL(for noteID: UUID) -> URL? {
        recordingURLs[noteID]
    }

    func liveTranscriptionChunks(for noteID: UUID) -> [LiveTranscriptionChunk] { [] }
    func runtimeHealthSnapshot(for noteID: UUID) -> CaptureRuntimeHealthSnapshot? { nil }
    func consumeRuntimeEvents(for noteID: UUID) -> [CaptureRuntimeEvent] { [] }

    func deleteRecording(for noteID: UUID) throws {
        recordingURLs[noteID] = nil
    }
}

private struct CommandStubTranscriptionService: LocalTranscriptionServicing {
    let delayNanoseconds: UInt64
    let result: TranscriptionJobResult

    init(
        delayNanoseconds: UInt64 = 0,
        result: TranscriptionJobResult = TranscriptionJobResult(
            segments: [TranscriptSegment(text: "Test transcript")],
            backend: .mock,
            executionKind: .placeholder
        )
    ) {
        self.delayNanoseconds = delayNanoseconds
        self.result = result
    }

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
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return result
    }
}

private struct CommandStubSummaryService: LocalSummaryServicing {
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
            enhancedNote: EnhancedNote(summary: "Generated"),
            backend: .placeholder,
            executionKind: .placeholder
        )
    }
}

private struct CommandStubSummaryModelManager: LocalSummaryModelManaging {
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
