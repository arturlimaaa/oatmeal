import Foundation
import OatmealCore
import OatmealEdge
@testable import OatmealUI
import XCTest

@MainActor
final class SingleMeetingAIWorkspaceAcceptanceTests: AIWorkspaceTestCase {
    func testWorkspaceReadinessGatingAndGroundedAnswersStayScopedToReadyNotes() async throws {
        let lockedNote = MeetingNote(
            id: UUID(uuidString: "D1000000-0000-0000-0000-000000000001")!,
            title: "Locked note",
            origin: .quickNote(createdAt: date(1_700_300_000))
        )
        let pendingTranscriptNote = MeetingNote(
            id: UUID(uuidString: "D1000000-0000-0000-0000-000000000002")!,
            title: "Pending transcript",
            origin: .quickNote(createdAt: date(1_700_300_010)),
            transcriptionStatus: .pending
        )
        let rawNotesNote = MeetingNote(
            id: UUID(uuidString: "D1000000-0000-0000-0000-000000000003")!,
            title: "Raw notes only",
            origin: .quickNote(createdAt: date(1_700_300_020)),
            rawNotes: "Need to confirm the onboarding rollout owner before Tuesday."
        )
        let transcriptSegmentID = UUID(uuidString: "D1000000-0000-0000-0000-000000000004")!
        let transcriptNote = MeetingNote(
            id: UUID(uuidString: "D1000000-0000-0000-0000-000000000005")!,
            title: "Transcript ready",
            origin: .quickNote(createdAt: date(1_700_300_030)),
            transcriptSegments: [
                TranscriptSegment(
                    id: transcriptSegmentID,
                    speakerName: "Alex",
                    text: "We decided to move the onboarding rollout to Tuesday after QA signs off."
                )
            ]
        )
        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let model = makeModel(
            notes: [lockedNote, pendingTranscriptNote, rawNotesNote, transcriptNote],
            persistence: persistence,
            assistantService: GroundedSingleMeetingAssistantService(responseDelay: 0),
            nowProvider: { self.date(1_700_300_100) }
        )

        let lockedState = AIWorkspacePresentationState.make(note: lockedNote, summaryExecutionPlan: nil)
        let pendingState = AIWorkspacePresentationState.make(note: pendingTranscriptNote, summaryExecutionPlan: nil)
        let rawNotesState = AIWorkspacePresentationState.make(note: rawNotesNote, summaryExecutionPlan: nil)
        let transcriptState = AIWorkspacePresentationState.make(note: transcriptNote, summaryExecutionPlan: nil)

        XCTAssertFalse(lockedState.canInteract)
        XCTAssertTrue(lockedState.introText.contains("needs local meeting material"))
        XCTAssertFalse(pendingState.canInteract)
        XCTAssertTrue(pendingState.emptyStateText.contains("Transcription is still running"))
        XCTAssertTrue(rawNotesState.canInteract)
        XCTAssertTrue(transcriptState.canInteract)

        model.submitAssistantPrompt("What changed about onboarding?", for: lockedNote.id)
        model.submitAssistantPrompt("What changed about onboarding?", for: pendingTranscriptNote.id)

        XCTAssertTrue(model.notes.first(where: { $0.id == lockedNote.id })?.assistantThread.turns.isEmpty == true)
        XCTAssertTrue(model.notes.first(where: { $0.id == pendingTranscriptNote.id })?.assistantThread.turns.isEmpty == true)

        model.submitAssistantPrompt("What changed about onboarding?", for: transcriptNote.id)
        let completed = await waitUntil {
            model.notes.first(where: { $0.id == transcriptNote.id })?.assistantThread.turns.first?.status == .completed
        }

        XCTAssertTrue(completed)
        let groundedTurn = try XCTUnwrap(
            model.notes.first(where: { $0.id == transcriptNote.id })?.assistantThread.turns.first
        )
        XCTAssertTrue(groundedTurn.response?.contains("Based on this meeting note") == true)
        XCTAssertTrue(groundedTurn.citations.contains(where: { $0.transcriptSegmentID == transcriptSegmentID }))
        XCTAssertTrue(model.notes.first(where: { $0.id == rawNotesNote.id })?.assistantThread.turns.isEmpty == true)
    }

    func testMixedMeetingThreadPersistsAcrossRelaunchWithRecipesRetryAndCitationRouting() async throws {
        let transcriptSegmentID = UUID(uuidString: "D2000000-0000-0000-0000-000000000001")!
        let targetNoteID = UUID(uuidString: "D2000000-0000-0000-0000-000000000002")!
        let unrelatedNoteID = UUID(uuidString: "D2000000-0000-0000-0000-000000000003")!
        let targetNote = MeetingNote(
            id: targetNoteID,
            title: "Launch Review",
            origin: .quickNote(createdAt: date(1_700_301_000)),
            rawNotes: "Need to send the onboarding follow-up after QA confirms the checklist.",
            transcriptSegments: [
                TranscriptSegment(
                    id: transcriptSegmentID,
                    speakerName: "Alex",
                    text: "We decided to send the onboarding follow-up after QA confirms the checklist."
                )
            ],
            enhancedNote: EnhancedNote(
                summary: "The team aligned on the onboarding follow-up timing.",
                actionItems: [ActionItem(text: "QA confirms the checklist.", assignee: "Sam")]
            )
        )
        let unrelatedNote = MeetingNote(
            id: unrelatedNoteID,
            title: "Different meeting",
            origin: .quickNote(createdAt: date(1_700_301_050)),
            transcriptSegments: [
                TranscriptSegment(
                    id: UUID(uuidString: "D2000000-0000-0000-0000-000000000099")!,
                    text: "This note should not pick up citations or turns from Launch Review."
                )
            ]
        )
        let transcriptCitation = NoteAssistantCitation(
            kind: .transcriptSegment,
            label: "Transcript",
            excerpt: "We decided to send the onboarding follow-up after QA confirms the checklist.",
            transcriptSegmentID: transcriptSegmentID
        )
        let actionItemCitation = NoteAssistantCitation(
            kind: .enhancedActionItem,
            label: "Action item",
            excerpt: "QA confirms the checklist."
        )
        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let model = makeModel(
            notes: [targetNote, unrelatedNote],
            persistence: persistence,
            assistantService: StubSingleMeetingAssistantService(
                mode: .sequence([
                    .success("Grounded answer about the onboarding follow-up.", [transcriptCitation]),
                    .success("Subject: Follow-up: Launch Review\n\nHi Alex,\n\nThanks again for the time today.", [transcriptCitation]),
                    .success("Action items from this meeting:\n\n- Sam — QA confirms the checklist.", [transcriptCitation, actionItemCitation]),
                    .failure("Oatmeal could not finish this assistant draft. Try again in a moment."),
                    .success("Recovered grounded answer after retry.", [transcriptCitation])
                ])
            ),
            nowProvider: { self.date(1_700_301_100) }
        )

        model.setSelectedNoteID(targetNoteID)
        model.submitAssistantPrompt("What changed in the meeting?", for: targetNoteID)
        let firstTurnCompleted = await waitUntil {
            model.selectedNote?.assistantThread.turns.count == 1
                && model.selectedNote?.assistantThread.turns[0].status == .completed
        }
        XCTAssertTrue(firstTurnCompleted)

        model.submitAssistantDraftAction(.followUpEmail, for: targetNoteID)
        let followUpCompleted = await waitUntil {
            model.selectedNote?.assistantThread.turns.count == 2
                && model.selectedNote?.assistantThread.turns[1].status == .completed
        }
        XCTAssertTrue(followUpCompleted)

        model.submitAssistantDraftAction(.actionItems, for: targetNoteID)
        let actionItemsCompleted = await waitUntil {
            model.selectedNote?.assistantThread.turns.count == 3
                && model.selectedNote?.assistantThread.turns[2].status == .completed
        }
        XCTAssertTrue(actionItemsCompleted)

        model.submitAssistantPrompt("Give me the confident answer again.", for: targetNoteID)
        let failureRecorded = await waitUntil {
            model.selectedNote?.assistantThread.turns.count == 4
                && model.selectedNote?.assistantThread.turns[3].status == .failed
        }
        XCTAssertTrue(failureRecorded)

        let failedTurnID = try XCTUnwrap(model.selectedNote?.assistantThread.turns[3].id)
        model.retryAssistantTurn(failedTurnID, for: targetNoteID)
        let retryCompleted = await waitUntil {
            model.selectedNote?.assistantThread.turns.count == 5
                && model.selectedNote?.assistantThread.turns[4].status == .completed
        }
        XCTAssertTrue(retryCompleted)

        let restored = makeModel(
            notes: [],
            persistence: persistence,
            assistantService: StubSingleMeetingAssistantService(mode: .success("Unused")),
            nowProvider: { self.date(1_700_301_200) }
        )

        let restoredTarget = try XCTUnwrap(restored.notes.first(where: { $0.id == targetNoteID }))
        let restoredUnrelated = try XCTUnwrap(restored.notes.first(where: { $0.id == unrelatedNoteID }))
        let turns = restoredTarget.assistantThread.turns

        XCTAssertEqual(turns.map(\.kind), [.prompt, .followUpEmail, .actionItems, .prompt, .prompt])
        XCTAssertEqual(turns.map(\.status), [.completed, .completed, .completed, .failed, .completed])
        XCTAssertEqual(turns[1].prompt, "Draft a follow-up email")
        XCTAssertEqual(turns[2].prompt, "Extract action items")
        XCTAssertEqual(turns[3].failureMessage, "Oatmeal could not finish this assistant draft. Try again in a moment.")
        XCTAssertEqual(turns[4].prompt, turns[3].prompt)
        XCTAssertTrue(turns[4].response?.contains("Recovered grounded answer after retry.") == true)
        XCTAssertTrue(turns[0].citations.contains(transcriptCitation))
        XCTAssertTrue(turns[2].citations.contains(actionItemCitation))
        XCTAssertTrue(restoredUnrelated.assistantThread.turns.isEmpty)

        let navigableCitations = turns
            .flatMap(\.citations)
            .filter { $0.kind == .transcriptSegment }

        XCTAssertFalse(navigableCitations.isEmpty)
        XCTAssertTrue(
            navigableCitations.allSatisfy {
                AssistantCitationNavigationTarget.resolve(citation: $0, in: restoredTarget)
                    == AssistantCitationNavigationTarget(transcriptSegmentID: transcriptSegmentID)
            }
        )
        XCTAssertTrue(
            navigableCitations.allSatisfy {
                AssistantCitationNavigationTarget.resolve(citation: $0, in: restoredUnrelated) == nil
            }
        )
    }

    func testRelaunchRecoveryFailsPendingTurnAndKeepsThreadRetryable() async throws {
        let noteID = UUID(uuidString: "D3000000-0000-0000-0000-000000000001")!
        var note = MeetingNote(
            id: noteID,
            title: "Recovery thread",
            origin: .quickNote(createdAt: date(1_700_302_000)),
            rawNotes: "Need to confirm the rollout owner."
        )
        let completedTurnID = note.submitAssistantPrompt(
            "What changed?",
            at: date(1_700_302_050)
        )
        _ = note.completeAssistantTurn(
            id: completedTurnID,
            response: "Grounded answer from the existing note material.",
            citations: [],
            at: date(1_700_302_060)
        )
        _ = note.submitAssistantPrompt(
            "Draft a follow-up email",
            kind: .followUpEmail,
            at: date(1_700_302_070)
        )

        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }
        try persistence.save(
            notes: [note],
            selectedSidebarItem: .allNotes,
            selectedUpcomingEventID: nil,
            selectedNoteID: noteID,
            selectedTemplateID: nil,
            collapsedSessionControllerPresentationIdentity: nil,
            pendingMeetingDetection: nil,
            meetingDetectionConfiguration: .default,
            transcriptionConfiguration: .default,
            summaryConfiguration: .default
        )

        let restored = makeModel(
            notes: [],
            persistence: persistence,
            assistantService: StubSingleMeetingAssistantService(
                mode: .success("Recovered follow-up email after relaunch.")
            ),
            nowProvider: { self.date(1_700_302_100) }
        )

        let restoredNote = try XCTUnwrap(restored.notes.first(where: { $0.id == noteID }))
        XCTAssertEqual(restoredNote.assistantThread.turns.count, 2)
        XCTAssertEqual(restoredNote.assistantThread.turns[0].status, .completed)
        XCTAssertEqual(restoredNote.assistantThread.turns[1].status, .failed)
        XCTAssertTrue(
            restoredNote.assistantThread.turns[1].failureMessage?.contains("relaunched before this answer completed") == true
        )

        let failedTurnID = try XCTUnwrap(restoredNote.assistantThread.turns[1].id)
        restored.retryAssistantTurn(failedTurnID, for: noteID)

        let recovered = await waitUntil {
            restored.notes.first(where: { $0.id == noteID })?.assistantThread.turns.count == 3
                && restored.notes.first(where: { $0.id == noteID })?.assistantThread.turns[2].status == .completed
        }
        XCTAssertTrue(recovered)

        let recoveredTurns = try XCTUnwrap(restored.notes.first(where: { $0.id == noteID })?.assistantThread.turns)
        XCTAssertEqual(recoveredTurns.map(\.status), [.completed, .failed, .completed])
        XCTAssertEqual(recoveredTurns[2].kind, .followUpEmail)
        XCTAssertEqual(recoveredTurns[2].prompt, "Draft a follow-up email")
        XCTAssertTrue(recoveredTurns[2].response?.contains("Recovered follow-up email after relaunch.") == true)
    }
}
