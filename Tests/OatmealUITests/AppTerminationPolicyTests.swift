import Foundation
import OatmealCore
@testable import OatmealUI
import XCTest

@MainActor
final class AppTerminationPolicyTests: XCTestCase {
    func testTerminationPromptAppearsForActiveCaptureSession() throws {
        let startedAt = Date(timeIntervalSince1970: 1_700_030_000)
        var note = MeetingNote(
            id: UUID(uuidString: "E5555555-5555-5555-5555-555555555555")!,
            title: "Board Review",
            origin: .quickNote(createdAt: startedAt),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )

        note.captureState.beginCapture(at: startedAt)
        note.beginLiveSession(at: startedAt, presentTranscriptPanel: false, tracksSystemAudio: true)

        let state = try XCTUnwrap(SessionControllerAdapter.state(for: note))
        let prompt = try XCTUnwrap(AppTerminationPolicy.prompt(for: state))

        XCTAssertEqual(prompt.title, "Quit While Recording?")
        XCTAssertEqual(prompt.continueButtonTitle, "Keep Recording")
        XCTAssertEqual(prompt.stopAndQuitButtonTitle, "Stop and Quit")
        XCTAssertEqual(prompt.quitButtonTitle, "Quit Anyway")
        XCTAssertTrue(prompt.message.contains("Board Review"))
    }

    func testTerminationPromptIsNilWhenNoLiveCaptureIsActive() {
        let startedAt = Date(timeIntervalSince1970: 1_700_030_100)
        var note = MeetingNote(
            id: UUID(uuidString: "F6666666-6666-6666-6666-666666666666")!,
            title: "Finished Sync",
            origin: .quickNote(createdAt: startedAt),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )

        note.captureState.beginCapture(at: startedAt)
        note.beginLiveSession(at: startedAt, presentTranscriptPanel: false, tracksSystemAudio: false)
        note.captureState.complete(at: Date(timeIntervalSince1970: 1_700_030_320))
        note.completeLiveSession(
            message: "Recording stopped. Oatmeal is finishing the transcript in the background.",
            at: Date(timeIntervalSince1970: 1_700_030_320)
        )
        note.queueTranscription(at: Date(timeIntervalSince1970: 1_700_030_321))

        let state = SessionControllerAdapter.state(for: note)
        XCTAssertNotNil(state)
        XCTAssertNil(AppTerminationPolicy.prompt(for: state))
    }

    func testTerminationPromptIsNilForRecoveredSessionThatIsNoLongerRecording() throws {
        let startedAt = Date(timeIntervalSince1970: 1_700_030_200)
        let recoveredAt = Date(timeIntervalSince1970: 1_700_030_260)
        var note = MeetingNote(
            id: UUID(uuidString: "F7777777-6666-6666-6666-666666666666")!,
            title: "Recovered Sync",
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

        let state = try XCTUnwrap(SessionControllerAdapter.state(for: note))

        XCTAssertFalse(state.canStopCapture)
        XCTAssertNil(AppTerminationPolicy.prompt(for: state))
    }

    func testTerminationChoiceMappingMatchesAlertButtonOrder() {
        XCTAssertEqual(
            AppTerminationPolicy.choice(for: .alertFirstButtonReturn),
            .keepRecording
        )
        XCTAssertEqual(
            AppTerminationPolicy.choice(for: .alertSecondButtonReturn),
            .stopAndQuit
        )
        XCTAssertEqual(
            AppTerminationPolicy.choice(for: .alertThirdButtonReturn),
            .quitAnyway
        )
    }
}
