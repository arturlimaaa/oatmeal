import Foundation
import OatmealCore
@testable import OatmealUI
import XCTest

@MainActor
final class PremiumTranscriptWorkspaceStateTests: AIWorkspaceTestCase {
    func testReadyTranscriptWorkspaceSummarizesReviewContext() {
        let note = MeetingNote(
            id: UUID(uuidString: "E1000000-0000-0000-0000-000000000001")!,
            title: "Transcript Review",
            origin: .quickNote(createdAt: date(1_700_500_000)),
            transcriptSegments: [
                TranscriptSegment(
                    id: UUID(uuidString: "E1000000-0000-0000-0000-000000000002")!,
                    speakerName: "Alex",
                    text: "We should review the transcript in its own workspace."
                ),
                TranscriptSegment(
                    id: UUID(uuidString: "E1000000-0000-0000-0000-000000000003")!,
                    speakerName: "Sam",
                    text: "That keeps it secondary to the polished note."
                )
            ]
        )

        let state = PremiumTranscriptWorkspaceState.make(note: note, highlightedSegmentID: nil)

        XCTAssertEqual(state.tone, .ready)
        XCTAssertEqual(state.title, "Transcript review")
        XCTAssertEqual(state.segmentCountText, "2 lines")
        XCTAssertEqual(state.speakerCountText, "2 speakers")
        XCTAssertNil(state.focusTitle)
    }

    func testFocusedTranscriptWorkspaceElevatesCitedSegment() {
        let segmentID = UUID(uuidString: "E2000000-0000-0000-0000-000000000002")!
        let note = MeetingNote(
            id: UUID(uuidString: "E2000000-0000-0000-0000-000000000001")!,
            title: "Cited transcript",
            origin: .quickNote(createdAt: date(1_700_500_100)),
            transcriptSegments: [
                TranscriptSegment(
                    id: segmentID,
                    speakerName: "Alex",
                    text: "This is the exact transcript line the AI answer referenced."
                )
            ]
        )

        let state = PremiumTranscriptWorkspaceState.make(note: note, highlightedSegmentID: segmentID)

        XCTAssertEqual(state.tone, .focused)
        XCTAssertEqual(state.title, "Focused transcript context")
        XCTAssertEqual(state.focusTitle, "Alex")
        XCTAssertEqual(state.focusExcerpt, "This is the exact transcript line the AI answer referenced.")
        XCTAssertEqual(state.segmentCountText, "1 line")
    }

    func testProcessingAndFailureTranscriptStatesUseProductLanguage() {
        let processingNote = MeetingNote(
            id: UUID(uuidString: "E3000000-0000-0000-0000-000000000001")!,
            title: "Processing transcript",
            origin: .quickNote(createdAt: date(1_700_500_200)),
            transcriptionStatus: .pending
        )
        let processingState = PremiumTranscriptWorkspaceState.make(note: processingNote, highlightedSegmentID: nil)
        XCTAssertEqual(processingState.tone, .processing)
        XCTAssertEqual(processingState.title, "Transcript is on the way")

        let failedNote = MeetingNote(
            id: UUID(uuidString: "E3000000-0000-0000-0000-000000000002")!,
            title: "Failed transcript",
            origin: .quickNote(createdAt: date(1_700_500_210)),
            transcriptionStatus: .failed
        )
        let failedState = PremiumTranscriptWorkspaceState.make(note: failedNote, highlightedSegmentID: nil)
        XCTAssertEqual(failedState.tone, .failed)
        XCTAssertEqual(failedState.title, "Transcript needs another pass")
    }

    func testTranscriptWorkspaceRouteOnlyResolvesForCurrentNoteTranscriptCitation() {
        let segmentID = UUID(uuidString: "E4000000-0000-0000-0000-000000000002")!
        let note = MeetingNote(
            id: UUID(uuidString: "E4000000-0000-0000-0000-000000000001")!,
            title: "Transcript route",
            origin: .quickNote(createdAt: date(1_700_500_300)),
            transcriptSegments: [
                TranscriptSegment(
                    id: segmentID,
                    text: "Jump to this line from AI."
                )
            ]
        )

        let matchingCitation = NoteAssistantCitation(
            kind: .transcriptSegment,
            label: "Transcript",
            excerpt: "Jump to this line from AI.",
            transcriptSegmentID: segmentID
        )
        let missingCitation = NoteAssistantCitation(
            kind: .transcriptSegment,
            label: "Transcript",
            excerpt: "Missing line",
            transcriptSegmentID: UUID()
        )
        let rawNotesCitation = NoteAssistantCitation(
            kind: .rawNotes,
            label: "Raw notes",
            excerpt: "Not transcript-backed"
        )

        XCTAssertEqual(
            TranscriptWorkspaceRoute.resolve(citation: matchingCitation, in: note),
            TranscriptWorkspaceRoute(workspaceMode: .transcript, transcriptSegmentID: segmentID)
        )
        XCTAssertNil(TranscriptWorkspaceRoute.resolve(citation: missingCitation, in: note))
        XCTAssertNil(TranscriptWorkspaceRoute.resolve(citation: rawNotesCitation, in: note))
    }
}
