import Foundation
import OatmealCore
import OatmealEdge
@testable import OatmealUI
import XCTest

@MainActor
final class WorkspaceShellTests: AIWorkspaceTestCase {
    func testWorkspaceModePersistsAcrossRelaunch() {
        let noteID = UUID(uuidString: "F1000000-0000-0000-0000-000000000001")!
        let note = MeetingNote(
            id: noteID,
            title: "Design Review",
            origin: .quickNote(createdAt: date(1_700_400_000)),
            rawNotes: "Need to confirm the handoff.",
            transcriptSegments: [
                TranscriptSegment(
                    id: UUID(uuidString: "F1000000-0000-0000-0000-000000000002")!,
                    text: "We should ship the workspace redesign next week."
                )
            ],
            enhancedNote: EnhancedNote(
                summary: "The team aligned on sequencing the redesign work.",
                actionItems: [ActionItem(text: "Ship the workspace redesign next week.", assignee: "Artur")]
            )
        )

        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let model = makeModel(
            notes: [note],
            persistence: persistence,
            assistantService: StubSingleMeetingAssistantService(mode: .success("Unused")),
            nowProvider: { self.date(1_700_400_100) }
        )

        model.setSelectedSidebarItem(.allNotes)
        model.setSelectedNoteID(noteID)
        model.setSelectedNoteWorkspaceMode(.tasks)

        let restored = makeModel(
            notes: [],
            persistence: persistence,
            assistantService: StubSingleMeetingAssistantService(mode: .success("Unused")),
            nowProvider: { self.date(1_700_400_200) }
        )

        XCTAssertEqual(restored.selectedSidebarItem, .allNotes)
        XCTAssertEqual(restored.selectedNoteID, noteID)
        XCTAssertEqual(restored.selectedNoteWorkspaceMode, .tasks)
        XCTAssertEqual(restored.noteWorkspaceState?.selectedMode, .tasks)
    }

    func testTranscriptRouteFromLightweightSurfaceSelectsTranscriptMode() {
        let noteID = UUID(uuidString: "F2000000-0000-0000-0000-000000000001")!
        let startedAt = date(1_700_401_000)
        var note = MeetingNote(
            id: noteID,
            title: "Customer Call",
            origin: .quickNote(createdAt: startedAt),
            transcriptSegments: [
                TranscriptSegment(
                    id: UUID(uuidString: "F2000000-0000-0000-0000-000000000002")!,
                    text: "The team wants a transcript-first view for customer calls."
                )
            ]
        )
        note.captureState.beginCapture(at: startedAt)
        note.beginLiveSession(
            at: startedAt,
            presentTranscriptPanel: false,
            tracksSystemAudio: true
        )

        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let model = makeModel(
            notes: [note],
            persistence: persistence,
            assistantService: StubSingleMeetingAssistantService(mode: .success("Unused")),
            nowProvider: { self.date(1_700_401_100) }
        )

        model.setSelectedSidebarItem(.upcoming)
        let route = model.routeMainWindowFromLightweightSurface(openTranscript: true)

        XCTAssertEqual(route, .session(noteID: noteID, opensTranscript: true))
        XCTAssertEqual(model.selectedSidebarItem, .allNotes)
        XCTAssertEqual(model.selectedNoteID, noteID)
        XCTAssertEqual(model.selectedNoteWorkspaceMode, .transcript)
        XCTAssertTrue(model.selectedNote?.liveSessionState.isTranscriptPanelPresented == true)
    }

    func testStartingQuickNoteResetsWorkspaceModeToNotes() {
        let note = MeetingNote(
            id: UUID(uuidString: "F3000000-0000-0000-0000-000000000001")!,
            title: "Existing Note",
            origin: .quickNote(createdAt: date(1_700_402_000))
        )

        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let model = makeModel(
            notes: [note],
            persistence: persistence,
            assistantService: StubSingleMeetingAssistantService(mode: .success("Unused")),
            nowProvider: { self.date(1_700_402_100) }
        )

        model.setSelectedNoteWorkspaceMode(.ai)
        model.startQuickNote()

        XCTAssertEqual(model.selectedSidebarItem, .allNotes)
        XCTAssertEqual(model.selectedNoteWorkspaceMode, .notes)
        XCTAssertEqual(model.selectedNote?.title, "Quick Note")
    }

    func testDeletingSelectedNoteSelectsNextAvailableNoteAndResetsMode() {
        let first = MeetingNote(
            id: UUID(uuidString: "F4000000-0000-0000-0000-000000000001")!,
            title: "First",
            origin: .quickNote(createdAt: date(1_700_403_000))
        )
        let secondID = UUID(uuidString: "F4000000-0000-0000-0000-000000000002")!
        let second = MeetingNote(
            id: secondID,
            title: "Second",
            origin: .quickNote(createdAt: date(1_700_403_100))
        )

        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let model = makeModel(
            notes: [first, second],
            persistence: persistence,
            assistantService: StubSingleMeetingAssistantService(mode: .success("Unused")),
            nowProvider: { self.date(1_700_403_200) }
        )

        model.setSelectedSidebarItem(.allNotes)
        model.setSelectedNoteID(first.id)
        model.setSelectedNoteWorkspaceMode(.ai)
        model.deleteSelectedNote()

        XCTAssertEqual(model.notes.count, 1)
        XCTAssertEqual(model.selectedNoteID, secondID)
        XCTAssertEqual(model.selectedNoteWorkspaceMode, .notes)
    }

    func testShortRecordingStopWarningLogicOnlyTriggersUnderFiveMinutes() {
        let noteID = UUID(uuidString: "F5000000-0000-0000-0000-000000000001")!
        var note = MeetingNote(
            id: noteID,
            title: "Short Capture",
            origin: .quickNote(createdAt: date(1_700_404_000))
        )
        note.captureState.beginCapture(at: date(1_700_404_000))

        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let model = makeModel(
            notes: [note],
            persistence: persistence,
            assistantService: StubSingleMeetingAssistantService(mode: .success("Unused")),
            nowProvider: { self.date(1_700_404_100) }
        )

        XCTAssertTrue(model.shouldWarnBeforeStoppingCapture(for: noteID, referenceDate: date(1_700_404_100)))
        XCTAssertFalse(model.shouldWarnBeforeStoppingCapture(for: noteID, referenceDate: date(1_700_404_301)))
    }
}
