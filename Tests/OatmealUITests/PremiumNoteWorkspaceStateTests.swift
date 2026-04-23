import Foundation
import OatmealCore
@testable import OatmealUI
import XCTest

final class PremiumNoteWorkspaceStateTests: XCTestCase {
    func testReadyNoteUsesProductLanguageAndTaskSummary() {
        let note = MeetingNote(
            id: UUID(uuidString: "E1000000-0000-0000-0000-000000000001")!,
            title: "Launch Review",
            origin: .quickNote(createdAt: Date(timeIntervalSince1970: 1_700_500_000)),
            enhancedNote: EnhancedNote(
                summary: "The team aligned on launch sequencing.",
                actionItems: [
                    ActionItem(text: "Confirm QA checklist.", assignee: "Sam"),
                    ActionItem(text: "Send launch note.", assignee: "Artur")
                ]
            )
        )

        let state = PremiumNoteWorkspaceStatusState.make(
            note: note,
            templateName: "Launch Review"
        )

        XCTAssertEqual(state.tone, PremiumNoteWorkspaceTone.ready)
        XCTAssertEqual(state.title, "Meeting note ready")
        XCTAssertTrue(state.detail.contains("recap is ready"))
        XCTAssertEqual(state.supportingDetail, "2 action items • Template: Launch Review")
    }

    func testTranscriptionPendingPrefersTranscribingState() {
        var note = MeetingNote(
            id: UUID(uuidString: "E2000000-0000-0000-0000-000000000001")!,
            title: "Customer Call",
            origin: .quickNote(createdAt: Date(timeIntervalSince1970: 1_700_500_100))
        )
        note.captureState.complete(at: Date(timeIntervalSince1970: 1_700_500_200))
        note.queueTranscription(at: Date(timeIntervalSince1970: 1_700_500_210))

        let state = PremiumNoteWorkspaceStatusState.make(
            note: note,
            templateName: nil
        )

        XCTAssertEqual(state.tone, PremiumNoteWorkspaceTone.processing)
        XCTAssertEqual(state.title, "Transcribing the meeting")
        XCTAssertTrue(state.detail.contains("searchable transcript"))
        XCTAssertEqual(state.supportingDetail, "Template: Automatic")
    }

    func testGenerationPendingPrefersWritingState() {
        var note = MeetingNote(
            id: UUID(uuidString: "E3000000-0000-0000-0000-000000000001")!,
            title: "Design Review",
            origin: .quickNote(createdAt: Date(timeIntervalSince1970: 1_700_500_300)),
            transcriptionStatus: .succeeded,
            transcriptSegments: [
                TranscriptSegment(text: "We should ship the redesign next week.")
            ]
        )
        note.queueGeneration(templateID: nil, at: Date(timeIntervalSince1970: 1_700_500_320))

        let state = PremiumNoteWorkspaceStatusState.make(
            note: note,
            templateName: "Automatic"
        )

        XCTAssertEqual(state.tone, PremiumNoteWorkspaceTone.processing)
        XCTAssertEqual(state.title, "Writing your meeting note")
        XCTAssertTrue(state.detail.contains("polished recap"))
        XCTAssertEqual(state.supportingDetail, "Template: Automatic")
    }

    func testFailedGenerationUsesRecoveryCopy() {
        var note = MeetingNote(
            id: UUID(uuidString: "E4000000-0000-0000-0000-000000000001")!,
            title: "Planning",
            origin: .quickNote(createdAt: Date(timeIntervalSince1970: 1_700_500_400)),
            transcriptionStatus: .succeeded,
            transcriptSegments: [
                TranscriptSegment(text: "We need a stronger launch story.")
            ]
        )
        note.beginGeneration(
            templateID: nil,
            at: Date(timeIntervalSince1970: 1_700_500_410)
        )
        note.recordGenerationFailure(
            "Local summary runtime timed out.",
            at: Date(timeIntervalSince1970: 1_700_500_420)
        )

        let state = PremiumNoteWorkspaceStatusState.make(
            note: note,
            templateName: nil
        )

        XCTAssertEqual(state.tone, PremiumNoteWorkspaceTone.failed)
        XCTAssertEqual(state.title, "This note needs another summary pass")
        XCTAssertTrue(state.detail.contains("Retry the polished note"))
        XCTAssertEqual(state.supportingDetail, "Local summary runtime timed out.")
    }

    func testTaskSnapshotGroupsActionItemsAndStructuredTakeaways() {
        let note = MeetingNote(
            id: UUID(uuidString: "E5000000-0000-0000-0000-000000000001")!,
            title: "Ops Review",
            origin: .quickNote(createdAt: Date(timeIntervalSince1970: 1_700_500_500)),
            enhancedNote: EnhancedNote(
                summary: "The team aligned on operations follow-up.",
                decisions: ["Ship the new runbook this week."],
                risksOrOpenQuestions: ["Need infra sign-off on the rollback plan."],
                actionItems: [
                    ActionItem(text: "Update runbook.", assignee: "Riley", status: .open),
                    ActionItem(text: "Confirm rollback owner.", assignee: "Morgan", status: .delegated),
                    ActionItem(text: "Close out last incident retro.", assignee: "Pat", status: .done)
                ]
            )
        )

        let snapshot = PremiumTaskWorkspaceSnapshot.make(note: note)

        XCTAssertEqual(snapshot.openItems.count, 1)
        XCTAssertEqual(snapshot.delegatedItems.count, 1)
        XCTAssertEqual(snapshot.doneItems.count, 1)
        XCTAssertEqual(snapshot.decisions, ["Ship the new runbook this week."])
        XCTAssertEqual(snapshot.risks, ["Need infra sign-off on the rollback plan."])
        XCTAssertTrue(snapshot.hasStructuredContent)
    }
}
