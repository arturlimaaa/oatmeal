import Foundation
import OatmealCore
import SwiftUI

enum PremiumNoteWorkspaceTone: Equatable, Sendable {
    case empty
    case ready
    case live
    case processing
    case failed
}

struct PremiumNoteWorkspaceStatusState: Equatable, Sendable {
    let tone: PremiumNoteWorkspaceTone
    let title: String
    let detail: String
    let supportingDetail: String?

    static func make(note: MeetingNote, templateName: String?) -> Self {
        let templateSummary = templateName ?? "Automatic"

        if note.transcriptionStatus == .failed || (note.processingState.stage == .transcription && note.processingState.status == .failed) {
            return Self(
                tone: .failed,
                title: "Transcription needs another pass",
                detail: "The recording is still safe locally. Retry transcription and Oatmeal will keep building this note from the saved artifact.",
                supportingDetail: note.processingState.errorMessage ?? note.transcriptionHistory.last?.errorMessage
            )
        }

        if note.generationStatus == .failed || (note.processingState.stage == .generation && note.processingState.status == .failed) {
            return Self(
                tone: .failed,
                title: "This note needs another summary pass",
                detail: "The transcript and working material are already here. Retry the polished note to rebuild the meeting summary, tasks, and decisions.",
                supportingDetail: note.processingState.errorMessage ?? note.generationHistory.last?.errorMessage
            )
        }

        switch note.captureState.phase {
        case .capturing:
            return Self(
                tone: .live,
                title: "Oatmeal is listening to this meeting",
                detail: "Capture is active now. Keep taking lightweight notes and Oatmeal will turn the meeting into a polished note after recording stops.",
                supportingDetail: note.calendarEvent == nil
                    ? "Quick Note capture records your microphone locally."
                    : "Calendar capture records your microphone and system audio together."
            )
        case .paused:
            return Self(
                tone: .processing,
                title: "Capture is paused",
                detail: "The meeting note is still intact. Resume recording when the conversation picks up again and Oatmeal will catch up from the saved session state.",
                supportingDetail: nil
            )
        case .failed:
            return Self(
                tone: .failed,
                title: "Capture needs attention",
                detail: note.captureState.canResumeAfterCrash
                    ? "Oatmeal kept the session state so this meeting can recover after a relaunch."
                    : "Capture hit an interruption before the note was fully recorded. The saved material is still available for recovery and retry.",
                supportingDetail: note.captureState.failureReason
            )
        case .ready, .complete:
            break
        }

        if note.generationStatus == .pending
            || (note.processingState.stage == .generation && (note.processingState.status == .queued || note.processingState.status == .running)) {
            return Self(
                tone: .processing,
                title: "Writing your meeting note",
                detail: "The transcript is ready and Oatmeal is shaping the polished recap, tasks, and decisions for this meeting.",
                supportingDetail: "Template: \(templateSummary)"
            )
        }

        if note.transcriptionStatus == .pending
            || (note.processingState.stage == .transcription && (note.processingState.status == .queued || note.processingState.status == .running))
            || (note.captureState.phase == .complete && note.transcriptionStatus == .idle && note.transcriptSegments.isEmpty) {
            return Self(
                tone: .processing,
                title: "Transcribing the meeting",
                detail: "Oatmeal is turning the saved recording into a searchable transcript before it writes the polished note.",
                supportingDetail: "Template: \(templateSummary)"
            )
        }

        if let enhancedNote = note.enhancedNote {
            let itemCount = enhancedNote.actionItems.count
            let taskSummary = itemCount == 0 ? "No action items yet" : itemCount == 1 ? "1 action item" : "\(itemCount) action items"
            return Self(
                tone: .ready,
                title: "Meeting note ready",
                detail: "The recap is ready to review, share, and turn into follow-up work.",
                supportingDetail: "\(taskSummary) • Template: \(templateSummary)"
            )
        }

        if note.rawNotes.isBlank == false || note.transcriptSegments.isEmpty == false {
            return Self(
                tone: .ready,
                title: "Working material is ready",
                detail: "This note already has meeting material. Oatmeal can keep shaping the polished recap as soon as processing runs.",
                supportingDetail: note.rawNotes.isBlank == false ? "Raw notes are available below." : "Transcript material is already attached to this note."
            )
        }

        return Self(
            tone: .empty,
            title: "Start capturing or add working notes",
            detail: "The default note view will turn into a polished meeting recap as soon as Oatmeal has transcript or note material to work with.",
            supportingDetail: "Template: \(templateSummary)"
        )
    }
}

struct PremiumTaskWorkspaceSnapshot: Equatable, Sendable {
    let openItems: [ActionItem]
    let delegatedItems: [ActionItem]
    let doneItems: [ActionItem]
    let decisions: [String]
    let risks: [String]

    static func make(note: MeetingNote) -> Self {
        let items = note.enhancedNote?.actionItems ?? []
        return Self(
            openItems: items.filter { $0.status == .open },
            delegatedItems: items.filter { $0.status == .delegated },
            doneItems: items.filter { $0.status == .done },
            decisions: note.enhancedNote?.decisions ?? [],
            risks: note.enhancedNote?.risksOrOpenQuestions ?? []
        )
    }

    var totalActionItemCount: Int {
        openItems.count + delegatedItems.count + doneItems.count
    }

    var hasStructuredContent: Bool {
        totalActionItemCount > 0 || decisions.isEmpty == false || risks.isEmpty == false
    }
}

private extension String {
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension PremiumNoteWorkspaceTone {
    var tintColor: Color {
        switch self {
        case .empty:
            .secondary
        case .ready:
            .green
        case .live:
            .red
        case .processing:
            .orange
        case .failed:
            .pink
        }
    }
}
