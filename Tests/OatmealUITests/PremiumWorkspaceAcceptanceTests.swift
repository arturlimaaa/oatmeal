import Foundation
import OatmealCore
import OatmealEdge
@testable import OatmealUI
import XCTest

@MainActor
final class PremiumWorkspaceAcceptanceTests: AIWorkspaceTestCase {
    func testPremiumWorkspaceModesPersistAcrossRelaunch() {
        let noteID = UUID(uuidString: "EB100000-0000-0000-0000-000000000001")!
        let note = MeetingNote(
            id: noteID,
            title: "Workspace note",
            origin: .quickNote(createdAt: date(1_700_800_000)),
            rawNotes: "Need to follow up with QA.",
            transcriptSegments: [
                TranscriptSegment(
                    id: UUID(uuidString: "EB100000-0000-0000-0000-000000000002")!,
                    speakerName: "Alex",
                    text: "We need to follow up with QA before launch."
                )
            ],
            enhancedNote: EnhancedNote(
                summary: "The team needs a QA follow-up.",
                actionItems: [ActionItem(text: "Follow up with QA", assignee: "Artur")]
            )
        )

        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let model = makeModel(
            notes: [note],
            persistence: persistence,
            assistantService: StubSingleMeetingAssistantService(mode: .success("Unused")),
            nowProvider: { self.date(1_700_800_100) }
        )

        model.setSelectedSidebarItem(.allNotes)
        model.setSelectedNoteID(noteID)
        model.setSelectedNoteWorkspaceMode(.tasks)

        let restored = makeModel(
            notes: [],
            persistence: persistence,
            assistantService: StubSingleMeetingAssistantService(mode: .success("Unused")),
            nowProvider: { self.date(1_700_800_200) }
        )

        XCTAssertEqual(restored.selectedNoteID, noteID)
        XCTAssertEqual(restored.selectedNoteWorkspaceMode, .tasks)
        XCTAssertEqual(restored.noteWorkspaceState?.availableModes, NoteWorkspaceMode.allCases)
    }

    func testPremiumWorkspaceCitationRoutingStaysNoteLocal() {
        let targetSegmentID = UUID(uuidString: "EB200000-0000-0000-0000-000000000001")!
        let targetNote = MeetingNote(
            id: UUID(uuidString: "EB200000-0000-0000-0000-000000000002")!,
            title: "Target note",
            origin: .quickNote(createdAt: date(1_700_801_000)),
            transcriptSegments: [
                TranscriptSegment(id: targetSegmentID, text: "We need to redo onboarding copy.")
            ]
        )
        let unrelatedNote = MeetingNote(
            id: UUID(uuidString: "EB200000-0000-0000-0000-000000000003")!,
            title: "Unrelated note",
            origin: .quickNote(createdAt: date(1_700_801_100)),
            transcriptSegments: [
                TranscriptSegment(
                    id: UUID(uuidString: "EB200000-0000-0000-0000-000000000099")!,
                    text: "Different transcript."
                )
            ]
        )
        let citation = NoteAssistantCitation(
            kind: .transcriptSegment,
            label: "Transcript",
            excerpt: "We need to redo onboarding copy.",
            transcriptSegmentID: targetSegmentID
        )

        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let model = makeModel(
            notes: [targetNote, unrelatedNote],
            persistence: persistence,
            assistantService: StubSingleMeetingAssistantService(mode: .success("Unused")),
            nowProvider: { self.date(1_700_801_200) }
        )

        model.setSelectedSidebarItem(.allNotes)
        model.setSelectedNoteID(targetNote.id)
        model.setSelectedNoteWorkspaceMode(.ai)

        let targetRoute = TranscriptWorkspaceRoute.resolve(citation: citation, in: targetNote)
        let unrelatedRoute = TranscriptWorkspaceRoute.resolve(citation: citation, in: unrelatedNote)

        XCTAssertEqual(targetRoute?.workspaceMode, .transcript)
        XCTAssertEqual(targetRoute?.transcriptSegmentID, targetSegmentID)
        XCTAssertNil(unrelatedRoute)

        if let targetRoute {
            model.setSelectedNoteWorkspaceMode(targetRoute.workspaceMode)
        }

        XCTAssertEqual(model.selectedNoteWorkspaceMode, .transcript)
    }

    func testPremiumWorkspaceAIModeKeepsThreadScopedAcrossModeSwitchesAndRelaunch() async throws {
        let targetNoteID = UUID(uuidString: "EB300000-0000-0000-0000-000000000001")!
        let targetNote = MeetingNote(
            id: targetNoteID,
            title: "Launch review",
            origin: .quickNote(createdAt: date(1_700_802_000)),
            rawNotes: "Need to send the launch recap.",
            transcriptSegments: [
                TranscriptSegment(
                    id: UUID(uuidString: "EB300000-0000-0000-0000-000000000002")!,
                    text: "We need to send the launch recap."
                )
            ]
        )
        let unrelatedNote = MeetingNote(
            id: UUID(uuidString: "EB300000-0000-0000-0000-000000000003")!,
            title: "Different meeting",
            origin: .quickNote(createdAt: date(1_700_802_010)),
            rawNotes: "Unrelated"
        )

        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let model = makeModel(
            notes: [targetNote, unrelatedNote],
            persistence: persistence,
            assistantService: StubSingleMeetingAssistantService(
                mode: .success("Grounded answer for the launch review only.")
            ),
            nowProvider: { self.date(1_700_802_100) }
        )

        model.setSelectedSidebarItem(.allNotes)
        model.setSelectedNoteID(targetNoteID)
        model.setSelectedNoteWorkspaceMode(.ai)
        model.submitAssistantPrompt("What changed?", for: targetNoteID)

        let completed = await waitUntil {
            model.selectedNote?.assistantThread.turns.first?.status == .completed
        }
        XCTAssertTrue(completed)

        model.setSelectedNoteWorkspaceMode(.tasks)
        model.setSelectedNoteWorkspaceMode(.ai)

        let restored = makeModel(
            notes: [],
            persistence: persistence,
            assistantService: StubSingleMeetingAssistantService(mode: .success("Unused")),
            nowProvider: { self.date(1_700_802_200) }
        )

        XCTAssertEqual(restored.selectedNoteID, targetNoteID)
        XCTAssertEqual(restored.selectedNoteWorkspaceMode, .ai)
        XCTAssertEqual(restored.selectedNote?.assistantThread.turns.count, 1)
        XCTAssertTrue(restored.notes.first(where: { $0.id == unrelatedNote.id })?.assistantThread.turns.isEmpty == true)
    }
}
