import Foundation
import OatmealCore
@testable import OatmealUI
import XCTest

final class PremiumTechnicalDetailsStateTests: XCTestCase {
    func testReadyDetailsStateUsesSecondaryHealthyLanguage() {
        let note = MeetingNote(
            id: UUID(uuidString: "EA100000-0000-0000-0000-000000000001")!,
            title: "Healthy note",
            origin: .quickNote(createdAt: Date(timeIntervalSince1970: 1_700_700_000)),
            rawNotes: "The rollout looked good.",
            transcriptSegments: [
                TranscriptSegment(
                    id: UUID(uuidString: "EA100000-0000-0000-0000-000000000002")!,
                    text: "The rollout looked good."
                )
            ],
            enhancedNote: EnhancedNote(summary: "Healthy note")
        )

        let state = PremiumTechnicalDetailsState.make(
            note: note,
            selectedMode: .ai
        )

        XCTAssertEqual(state.tone, .ready)
        XCTAssertEqual(state.title, "Everything looks healthy")
        XCTAssertEqual(state.statusBadgeText, "Healthy")
        XCTAssertEqual(state.routeBadgeText, "Opened from AI")
    }

    func testProcessingDetailsStateUsesCalmProductLanguage() {
        let note = MeetingNote(
            id: UUID(uuidString: "EA200000-0000-0000-0000-000000000001")!,
            title: "Processing note",
            origin: .quickNote(createdAt: Date(timeIntervalSince1970: 1_700_700_100)),
            transcriptionStatus: .pending
        )

        let state = PremiumTechnicalDetailsState.make(
            note: note,
            selectedMode: .notes
        )

        XCTAssertEqual(state.tone, .processing)
        XCTAssertEqual(state.title, "Oatmeal is still finishing this meeting")
        XCTAssertEqual(state.statusBadgeText, "In progress")
    }

    func testFailedDetailsStateKeepsRetryFraming() {
        var note = MeetingNote(
            id: UUID(uuidString: "EA300000-0000-0000-0000-000000000001")!,
            title: "Failed note",
            origin: .quickNote(createdAt: Date(timeIntervalSince1970: 1_700_700_200)),
            transcriptionStatus: .failed
        )
        note.processingState.fail(
            stage: .transcription,
            message: "Decoder crashed",
            at: Date(timeIntervalSince1970: 1_700_700_210)
        )

        let state = PremiumTechnicalDetailsState.make(
            note: note,
            selectedMode: .transcript
        )

        XCTAssertEqual(state.tone, .failed)
        XCTAssertEqual(state.title, "This meeting needs a quick retry")
        XCTAssertEqual(state.statusBadgeText, "Needs attention")
        XCTAssertEqual(state.routeBadgeText, "Opened from Transcript")
    }
}
