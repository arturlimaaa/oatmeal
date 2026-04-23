import Foundation
import OatmealCore
import OatmealEdge
@testable import OatmealUI
import XCTest

final class PremiumAIWorkspaceStateTests: XCTestCase {
    func testReadyAIWorkspaceSummarizesThreadAndGroundingSources() {
        let noteID = UUID(uuidString: "E5000000-0000-0000-0000-000000000001")!
        let segmentID = UUID(uuidString: "E5000000-0000-0000-0000-000000000002")!
        var note = MeetingNote(
            id: noteID,
            title: "Launch Review",
            origin: .quickNote(createdAt: Date(timeIntervalSince1970: 1_700_600_000)),
            rawNotes: "Need to send the launch follow-up after QA signs off.",
            transcriptSegments: [
                TranscriptSegment(
                    id: segmentID,
                    speakerName: "Alex",
                    text: "We should send the launch follow-up after QA signs off."
                )
            ],
            enhancedNote: EnhancedNote(
                summary: "The team aligned on the launch follow-up timing."
            )
        )
        let turnID = note.submitAssistantPrompt(
            "What changed in the meeting?",
            at: Date(timeIntervalSince1970: 1_700_600_010)
        )
        _ = note.completeAssistantTurn(
            id: turnID,
            response: "The launch follow-up now waits for QA sign-off.",
            citations: [
                NoteAssistantCitation(
                    kind: .transcriptSegment,
                    label: "Transcript",
                    excerpt: "We should send the launch follow-up after QA signs off.",
                    transcriptSegmentID: segmentID
                )
            ],
            at: Date(timeIntervalSince1970: 1_700_600_020)
        )

        let state = PremiumAIWorkspaceState.make(
            note: note,
            summaryExecutionPlan: nil
        )

        XCTAssertEqual(state.tone, .ready)
        XCTAssertEqual(state.title, "Meeting AI thread")
        XCTAssertEqual(state.threadCountText, "1 turn")
        XCTAssertEqual(state.citationCountText, "1 citation")
        XCTAssertEqual(state.sourceCountText, "4 sources")
        XCTAssertTrue(state.sources.contains(where: { $0.id == "transcript" && $0.readiness == .ready }))
        XCTAssertTrue(state.sources.contains(where: { $0.id == "raw-notes" && $0.readiness == .ready }))
        XCTAssertTrue(state.sources.contains(where: { $0.id == "enhanced-note" && $0.readiness == .ready }))
        XCTAssertTrue(state.sources.contains(where: { $0.id == "meeting-context" && $0.readiness == .ready }))
    }

    func testLockedAndWarmingAIStatesUseProductLanguage() {
        let lockedNote = MeetingNote(
            id: UUID(uuidString: "E6000000-0000-0000-0000-000000000001")!,
            title: "Locked AI",
            origin: .quickNote(createdAt: Date(timeIntervalSince1970: 1_700_600_100))
        )
        let lockedState = PremiumAIWorkspaceState.make(
            note: lockedNote,
            summaryExecutionPlan: nil
        )

        XCTAssertEqual(lockedState.tone, .empty)
        XCTAssertEqual(lockedState.title, "Meeting AI needs note material")
        XCTAssertTrue(lockedState.subtitle.contains("opens as soon as this note has enough"))

        let warmingNote = MeetingNote(
            id: UUID(uuidString: "E6000000-0000-0000-0000-000000000002")!,
            title: "Warming AI",
            origin: .quickNote(createdAt: Date(timeIntervalSince1970: 1_700_600_110)),
            transcriptionStatus: .pending
        )
        let warmingState = PremiumAIWorkspaceState.make(
            note: warmingNote,
            summaryExecutionPlan: nil
        )

        XCTAssertEqual(warmingState.tone, .processing)
        XCTAssertEqual(warmingState.title, "Meeting AI is warming up")
        XCTAssertTrue(warmingState.subtitle.contains("safe note-local meeting context"))
    }

    func testPendingAssistantTurnPromotesDraftingState() {
        var note = MeetingNote(
            id: UUID(uuidString: "E7000000-0000-0000-0000-000000000001")!,
            title: "Pending AI",
            origin: .quickNote(createdAt: Date(timeIntervalSince1970: 1_700_600_200)),
            rawNotes: "Need to confirm the rollout owner."
        )
        _ = note.submitAssistantPrompt(
            "What changed about rollout ownership?",
            at: Date(timeIntervalSince1970: 1_700_600_210)
        )

        let fallbackPlan = LocalSummaryExecutionPlan(
            backend: .placeholder,
            executionKind: .placeholder,
            summary: "Oatmeal will use the placeholder summary backend."
        )
        let state = PremiumAIWorkspaceState.make(
            note: note,
            summaryExecutionPlan: fallbackPlan
        )

        XCTAssertEqual(state.tone, .processing)
        XCTAssertEqual(state.title, "Oatmeal is drafting from this meeting")
        XCTAssertTrue(state.supportingDetail?.contains("safer local fallback path") == true)
    }
}
