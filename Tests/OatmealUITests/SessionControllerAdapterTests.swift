import Foundation
import OatmealCore
@testable import OatmealUI
import XCTest

@MainActor
final class SessionControllerAdapterTests: XCTestCase {
    func testAdapterExposesActiveCaptureNoteState() throws {
        let startedAt = date(1_700_020_000)
        var note = MeetingNote(
            id: UUID(uuidString: "A1111111-1111-1111-1111-111111111111")!,
            title: "Design Review",
            origin: .quickNote(createdAt: startedAt),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )

        note.captureState.beginCapture(at: startedAt)
        note.beginLiveSession(at: startedAt, presentTranscriptPanel: false, tracksSystemAudio: true)

        let state = try XCTUnwrap(SessionControllerAdapter.state(for: note))
        XCTAssertEqual(state.title, "Design Review")
        XCTAssertEqual(state.kind, .active)
        XCTAssertEqual(state.healthLabel, "Live")
        XCTAssertEqual(state.captureLabel, "Recording")
        XCTAssertEqual(state.microphoneLabel, "Live")
        XCTAssertEqual(state.systemAudioLabel, "Live")
        XCTAssertFalse(state.showsProcessingIndicator)
    }

    func testAdapterMapsDelayedAndRecoveredStateLabels() throws {
        let startedAt = date(1_700_020_100)
        var delayedNote = MeetingNote(
            id: UUID(uuidString: "B2222222-2222-2222-2222-222222222222")!,
            title: "Customer Call",
            origin: .quickNote(createdAt: startedAt),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )

        delayedNote.captureState.beginCapture(at: startedAt)
        delayedNote.beginLiveSession(at: startedAt, presentTranscriptPanel: true, tracksSystemAudio: true)
        delayedNote.markLiveSessionDelayed(
            message: "Oatmeal is catching up on background transcript work.",
            at: date(1_700_020_140)
        )
        delayedNote.updateLiveCaptureSource(
            .systemAudio,
            status: .delayed,
            message: "System audio samples are lagging behind.",
            updatedAt: date(1_700_020_141)
        )

        let delayedState = try XCTUnwrap(SessionControllerAdapter.state(for: delayedNote))
        XCTAssertEqual(delayedState.kind, .active)
        XCTAssertEqual(delayedState.healthLabel, "Delayed")
        XCTAssertEqual(delayedState.captureLabel, "Recording")
        XCTAssertEqual(delayedState.systemAudioLabel, "Delayed")
        XCTAssertEqual(delayedState.controllerStatusTitle, "Catching up live transcript")
        XCTAssertEqual(delayedState.controllerStatusSymbolName, "clock.arrow.circlepath")
        XCTAssertEqual(
            delayedState.detailText,
            "Oatmeal is catching up on background transcript work."
        )

        var recoveredNote = delayedNote
        recoveredNote.markLiveSessionRecovered(
            message: "Oatmeal recovered the live session and is back on track.",
            at: date(1_700_020_180)
        )
        recoveredNote.updateLiveCaptureSource(
            .systemAudio,
            status: .recovered,
            message: "System audio is healthy again.",
            updatedAt: date(1_700_020_181)
        )

        let recoveredState = try XCTUnwrap(SessionControllerAdapter.state(for: recoveredNote))
        XCTAssertEqual(recoveredState.kind, .active)
        XCTAssertEqual(recoveredState.healthLabel, "Recovered")
        XCTAssertEqual(recoveredState.systemAudioLabel, "Recovered")
        XCTAssertEqual(recoveredState.controllerStatusTitle, "Recovered session")
        XCTAssertEqual(
            recoveredState.detailText,
            "Oatmeal recovered the live session and is back on track."
        )
    }

    func testAdapterShowsPostCaptureProcessingVisibilityAfterStop() throws {
        let startedAt = date(1_700_020_200)
        var note = MeetingNote(
            id: UUID(uuidString: "C3333333-3333-3333-3333-333333333333")!,
            title: "Weekly Sync",
            origin: .quickNote(createdAt: startedAt),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )

        note.captureState.beginCapture(at: startedAt)
        note.beginLiveSession(at: startedAt, presentTranscriptPanel: false, tracksSystemAudio: false)
        note.captureState.complete(at: date(1_700_020_420))
        note.completeLiveSession(
            message: "Recording stopped. Oatmeal will finish transcription in the background.",
            at: date(1_700_020_420)
        )
        note.queueTranscription(at: date(1_700_020_425))

        let state = try XCTUnwrap(SessionControllerAdapter.state(for: note))
        XCTAssertEqual(state.kind, .processing)
        XCTAssertEqual(state.healthLabel, "Completed")
        XCTAssertEqual(state.captureLabel, "Stopped")
        XCTAssertTrue(state.showsProcessingIndicator)
        XCTAssertEqual(state.processingLabel, "Transcription Queued")
        XCTAssertEqual(state.controllerStatusTitle, "Finishing transcript")
        XCTAssertEqual(state.transcriptActionTitle, "Transcript")
    }

    func testAdapterShowsEnhancedNoteGenerationState() throws {
        let startedAt = date(1_700_020_250)
        var note = MeetingNote(
            id: UUID(uuidString: "C3434343-3333-3333-3333-333333333333")!,
            title: "Summary Pass",
            origin: .quickNote(createdAt: startedAt),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )

        note.captureState.beginCapture(at: startedAt)
        note.beginLiveSession(at: startedAt, presentTranscriptPanel: true, tracksSystemAudio: false)
        note.captureState.complete(at: date(1_700_020_410))
        note.completeLiveSession(
            message: "Recording stopped. Oatmeal has the transcript and is shaping the enhanced note.",
            at: date(1_700_020_410)
        )
        note.beginGeneration(templateID: NoteTemplate.automatic.id, at: date(1_700_020_420))

        let state = try XCTUnwrap(SessionControllerAdapter.state(for: note))
        XCTAssertEqual(state.kind, .processing)
        XCTAssertEqual(state.processingLabel, "Enhanced Note Running")
        XCTAssertEqual(state.controllerStatusTitle, "Writing enhanced note")
        XCTAssertEqual(
            state.controllerStatusDetail,
            "Transcript is ready. Oatmeal is shaping the enhanced note in the background."
        )
    }

    func testAdapterMapsInterruptedStateLabels() throws {
        let startedAt = date(1_700_020_300)
        let failedAt = date(1_700_020_360)
        var note = MeetingNote(
            id: UUID(uuidString: "C4444444-3333-3333-3333-333333333333")!,
            title: "Interrupted Session",
            origin: .quickNote(createdAt: startedAt),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )

        note.captureState.beginCapture(at: startedAt)
        note.beginLiveSession(at: startedAt, presentTranscriptPanel: true, tracksSystemAudio: true)
        note.captureState.fail(
            reason: "The microphone stream stopped unexpectedly.",
            at: failedAt,
            recoverable: true
        )
        note.recordLiveSessionInterruption(updatedAt: failedAt)
        note.failLiveSession(message: "Capture needs attention before live updates can continue.", at: failedAt)
        note.updateLiveCaptureSource(
            .microphone,
            status: .failed,
            message: "Microphone audio dropped out.",
            updatedAt: failedAt
        )

        let state = try XCTUnwrap(SessionControllerAdapter.state(for: note))
        XCTAssertEqual(state.kind, .active)
        XCTAssertEqual(state.healthLabel, "Failed")
        XCTAssertEqual(state.captureLabel, "Interrupted")
        XCTAssertEqual(state.microphoneLabel, "Failed")
        XCTAssertEqual(state.controllerStatusTitle, "Capture interrupted")
        XCTAssertEqual(state.controllerStatusSymbolName, "exclamationmark.triangle.fill")
        XCTAssertEqual(
            state.detailText,
            "Capture needs attention before live updates can continue."
        )
    }

    func testMenuBarAdapterShowsRecentlyCompletedSessionWithinWindow() throws {
        let startedAt = date(1_700_020_320)
        let completedAt = date(1_700_020_500)
        var note = MeetingNote(
            id: UUID(uuidString: "C5555555-3333-3333-3333-333333333333")!,
            title: "Finished Session",
            origin: .quickNote(createdAt: startedAt),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )

        note.captureState.beginCapture(at: startedAt)
        note.beginLiveSession(at: startedAt, presentTranscriptPanel: true, tracksSystemAudio: false)
        note.captureState.complete(at: completedAt)
        note.completeLiveSession(
            message: "Recording stopped. Oatmeal finished the durable note.",
            at: completedAt
        )
        note.applyTranscript(
            [TranscriptSegment(text: "Everything is wrapped up.")],
            backend: .mock,
            executionKind: .placeholder,
            at: completedAt
        )
        note.applyEnhancedNote(
            EnhancedNote(summary: "The meeting is complete and ready to review."),
            at: completedAt
        )

        XCTAssertNil(SessionControllerAdapter.controllerState(for: note))

        let menuBarState = try XCTUnwrap(
            SessionControllerAdapter.menuBarState(
                for: note,
                referenceDate: completedAt.addingTimeInterval(120)
            )
        )
        XCTAssertEqual(menuBarState.kind, .recent)
        XCTAssertEqual(menuBarState.menuBarSectionTitle, "Recently Completed")
        XCTAssertEqual(menuBarState.controllerStatusTitle, "Ready to review")
        XCTAssertEqual(menuBarState.primaryActionTitle, "Review Note")
        XCTAssertEqual(menuBarState.menuBarSymbolName, "checkmark.circle.fill")
    }

    func testMenuBarAdapterHidesRecentlyCompletedSessionAfterWindowExpires() {
        let startedAt = date(1_700_020_330)
        let completedAt = date(1_700_020_400)
        var note = MeetingNote(
            id: UUID(uuidString: "C5656565-3333-3333-3333-333333333333")!,
            title: "Expired Session",
            origin: .quickNote(createdAt: startedAt),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )

        note.captureState.beginCapture(at: startedAt)
        note.beginLiveSession(at: startedAt, presentTranscriptPanel: false, tracksSystemAudio: false)
        note.captureState.complete(at: completedAt)
        note.completeLiveSession(at: completedAt)
        note.applyTranscript(
            [TranscriptSegment(text: "Complete.")],
            backend: .mock,
            executionKind: .placeholder,
            at: completedAt
        )
        note.applyEnhancedNote(EnhancedNote(summary: "Ready"), at: completedAt)

        XCTAssertNil(
            SessionControllerAdapter.menuBarState(
                for: note,
                referenceDate: completedAt.addingTimeInterval(20 * 60)
            )
        )
    }

    func testAdapterHidesWhenNoActiveOrProcessingSessionExists() {
        let note = MeetingNote(
            id: UUID(uuidString: "D4444444-4444-4444-4444-444444444444")!,
            title: "Archived Note",
            origin: .quickNote(createdAt: date(1_700_020_500)),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )

        XCTAssertNil(SessionControllerAdapter.state(for: note))
        XCTAssertNil(SessionControllerAdapter.state(for: nil))
    }

    func testCollectionAdapterPrefersLiveSessionOverSelectedProcessingNote() throws {
        let liveStartedAt = date(1_700_020_600)
        var liveNote = MeetingNote(
            id: UUID(uuidString: "E5555555-5555-5555-5555-555555555555")!,
            title: "Live Session",
            origin: .quickNote(createdAt: liveStartedAt),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )
        liveNote.captureState.beginCapture(at: liveStartedAt)
        liveNote.beginLiveSession(at: liveStartedAt, presentTranscriptPanel: false, tracksSystemAudio: true)

        let processingStartedAt = date(1_700_020_700)
        var processingNote = MeetingNote(
            id: UUID(uuidString: "F6666666-6666-6666-6666-666666666666")!,
            title: "Queued Follow Up",
            origin: .quickNote(createdAt: processingStartedAt),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )
        processingNote.captureState.complete(at: date(1_700_020_760))
        processingNote.completeLiveSession(
            message: "Recording stopped. Oatmeal is still transcribing.",
            at: date(1_700_020_760)
        )
        processingNote.queueTranscription(at: date(1_700_020_761))

        let state = try XCTUnwrap(
            SessionControllerAdapter.state(
                for: [processingNote, liveNote],
                selectedNoteID: processingNote.id
            )
        )

        XCTAssertEqual(state.noteID, liveNote.id)
        XCTAssertEqual(state.title, "Live Session")
        XCTAssertEqual(state.kind, .active)
    }
}

private func date(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: seconds)
}
