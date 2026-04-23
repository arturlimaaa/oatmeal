import Foundation
import OatmealCore

enum NoteWorkspaceMode: String, Codable, Equatable, Sendable, CaseIterable, Identifiable {
    case notes
    case transcript
    case ai
    case tasks

    var id: Self { self }

    var title: String {
        switch self {
        case .notes:
            "Notes"
        case .transcript:
            "Transcript"
        case .ai:
            "AI"
        case .tasks:
            "Tasks"
        }
    }

    var systemImage: String {
        switch self {
        case .notes:
            "doc.text"
        case .transcript:
            "text.alignleft"
        case .ai:
            "sparkles"
        case .tasks:
            "checklist"
        }
    }

    var emptyStateTitle: String {
        switch self {
        case .notes:
            "Notes Workspace"
        case .transcript:
            "Transcript Workspace"
        case .ai:
            "AI Workspace"
        case .tasks:
            "Tasks Workspace"
        }
    }
}

struct NoteWorkspacePresentationState: Equatable, Sendable {
    let noteID: MeetingNote.ID
    let selectedMode: NoteWorkspaceMode
    let availableModes: [NoteWorkspaceMode]

    static func make(
        note: MeetingNote,
        selectedMode: NoteWorkspaceMode
    ) -> Self {
        Self(
            noteID: note.id,
            selectedMode: selectedMode,
            availableModes: NoteWorkspaceMode.allCases
        )
    }

    func badgeText(for mode: NoteWorkspaceMode, note: MeetingNote) -> String? {
        switch mode {
        case .notes:
            return nil
        case .transcript:
            let count = note.transcriptSegments.count
            guard count > 0 else {
                return note.liveSessionState.hasPreviewEntries ? "Live" : nil
            }
            return count == 1 ? "1 line" : "\(count)"
        case .ai:
            let count = note.assistantThread.turns.count
            guard count > 0 else {
                return nil
            }
            return "\(count)"
        case .tasks:
            let count = note.enhancedNote?.actionItems.count ?? 0
            guard count > 0 else {
                return nil
            }
            return "\(count)"
        }
    }
}
