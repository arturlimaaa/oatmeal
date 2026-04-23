import Foundation
import OatmealCore
import OatmealEdge
import SwiftUI

enum PremiumAIWorkspaceTone: Equatable, Sendable {
    case empty
    case ready
    case processing
    case failed
}

struct PremiumAIWorkspaceSourceSummary: Equatable, Sendable, Identifiable {
    enum Readiness: Equatable, Sendable {
        case ready
        case partial
        case unavailable

        var color: Color {
            switch self {
            case .ready:
                .green
            case .partial:
                .orange
            case .unavailable:
                .secondary
            }
        }

        var label: String {
            switch self {
            case .ready:
                "Ready"
            case .partial:
                "Partial"
            case .unavailable:
                "Unavailable"
            }
        }
    }

    let id: String
    let title: String
    let detail: String
    let readiness: Readiness
}

struct PremiumAIWorkspaceState: Equatable, Sendable {
    let tone: PremiumAIWorkspaceTone
    let title: String
    let subtitle: String
    let supportingDetail: String?
    let threadCountText: String
    let citationCountText: String
    let sourceCountText: String
    let sources: [PremiumAIWorkspaceSourceSummary]

    static func make(
        note: MeetingNote,
        summaryExecutionPlan: LocalSummaryExecutionPlan?
    ) -> Self {
        let presentation = AIWorkspacePresentationState.make(
            note: note,
            summaryExecutionPlan: summaryExecutionPlan
        )
        let sources = sourceSummaries(for: note)
        let turnCount = note.assistantThread.turns.count
        let citationCount = note.assistantThread.turns.reduce(into: 0) { partialResult, turn in
            partialResult += turn.citations.count
        }

        let tone: PremiumAIWorkspaceTone
        let title: String
        let subtitle: String
        let supportingDetail: String?

        if !presentation.canInteract {
            if note.transcriptionStatus == .pending {
                tone = .processing
                title = "Meeting AI is warming up"
                subtitle = "Oatmeal is still assembling safe note-local meeting context before this workspace can answer."
            } else if note.transcriptionStatus == .failed {
                tone = .failed
                title = "Meeting AI is waiting for safer context"
                subtitle = "Transcription needs another pass or you need more note material before Oatmeal can answer without guessing."
            } else {
                tone = .empty
                title = "Meeting AI needs note material"
                subtitle = "This workspace opens as soon as this note has enough transcript, raw notes, summary material, or live preview context to ground against."
            }
            supportingDetail = presentation.emptyStateText
        } else if note.hasPendingAssistantTurn {
            tone = .processing
            title = "Oatmeal is drafting from this meeting"
            subtitle = "The thread stays attached to this note while Oatmeal writes the latest grounded answer or draft."
            supportingDetail = presentation.composerFootnote
        } else if turnCount > 0 {
            tone = .ready
            title = "Meeting AI thread"
            subtitle = "Questions, drafts, and structured workflows stay attached to this note so the conversation feels like part of the document."
            supportingDetail = presentation.composerFootnote
        } else {
            tone = .ready
            title = "Ask Oatmeal about this meeting"
            subtitle = "Start with a freeform question or trigger a draft from the actions rail. Every answer stays scoped to this note."
            supportingDetail = presentation.composerFootnote
        }

        return Self(
            tone: tone,
            title: title,
            subtitle: subtitle,
            supportingDetail: supportingDetail,
            threadCountText: turnCount == 0 ? "No turns yet" : turnCount == 1 ? "1 turn" : "\(turnCount) turns",
            citationCountText: citationCount == 0 ? "No citations yet" : citationCount == 1 ? "1 citation" : "\(citationCount) citations",
            sourceCountText: sources.isEmpty ? "No sources yet" : sources.count == 1 ? "1 source" : "\(sources.count) sources",
            sources: sources
        )
    }

    private static func sourceSummaries(for note: MeetingNote) -> [PremiumAIWorkspaceSourceSummary] {
        var sources: [PremiumAIWorkspaceSourceSummary] = []

        if !note.transcriptSegments.isEmpty {
            let count = note.transcriptSegments.count
            sources.append(
                PremiumAIWorkspaceSourceSummary(
                    id: "transcript",
                    title: "Transcript",
                    detail: count == 1 ? "1 transcript line is available for citations and grounded answers." : "\(count) transcript lines are available for citations and grounded answers.",
                    readiness: .ready
                )
            )
        } else if note.liveSessionState.hasPreviewEntries {
            sources.append(
                PremiumAIWorkspaceSourceSummary(
                    id: "transcript",
                    title: "Transcript",
                    detail: "A live transcript preview exists, but the final transcript is still catching up.",
                    readiness: .partial
                )
            )
        } else {
            sources.append(
                PremiumAIWorkspaceSourceSummary(
                    id: "transcript",
                    title: "Transcript",
                    detail: "No transcript is attached to this note yet.",
                    readiness: .unavailable
                )
            )
        }

        if !note.rawNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sources.append(
                PremiumAIWorkspaceSourceSummary(
                    id: "raw-notes",
                    title: "Working notes",
                    detail: "Raw notes are attached, so Oatmeal can ground answers in your own scratchpad too.",
                    readiness: .ready
                )
            )
        }

        if let enhancedNote = note.enhancedNote {
            let actionItemCount = enhancedNote.actionItems.count
            let detail = actionItemCount == 0
                ? "The polished recap is ready and can be used as grounded meeting context."
                : "The polished recap is ready with \(actionItemCount) action item" + (actionItemCount == 1 ? "." : "s.")
            sources.append(
                PremiumAIWorkspaceSourceSummary(
                    id: "enhanced-note",
                    title: "Polished note",
                    detail: detail,
                    readiness: .ready
                )
            )
        }

        let meetingContextDetail: String
        if let event = note.calendarEvent {
            meetingContextDetail = "Calendar context is attached from \(event.title)."
        } else {
            meetingContextDetail = "Quick Note timing and note-local metadata stay in scope for this meeting."
        }
        sources.append(
            PremiumAIWorkspaceSourceSummary(
                id: "meeting-context",
                title: "Meeting context",
                detail: meetingContextDetail,
                readiness: .ready
            )
        )

        return sources
    }
}

struct AIWorkspacePresentationState: Equatable, Sendable {
    let canInteract: Bool
    let introText: String
    let emptyStateText: String
    let composerFootnote: String

    static func make(
        note: MeetingNote,
        summaryExecutionPlan: LocalSummaryExecutionPlan?
    ) -> AIWorkspacePresentationState {
        if !note.isAIWorkspaceAvailable {
            if note.transcriptionStatus == .pending {
                return AIWorkspacePresentationState(
                    canInteract: false,
                    introText: "Oatmeal is still building the local meeting context for this workspace. It will open up as soon as the transcript or your own raw notes are available.",
                    emptyStateText: "Transcription is still running for this meeting. Add raw notes now or wait for the transcript to finish before asking Oatmeal questions.",
                    composerFootnote: "This workspace unlocks automatically when Oatmeal has note-local material to ground against."
                )
            }

            if note.transcriptionStatus == .failed {
                return AIWorkspacePresentationState(
                    canInteract: false,
                    introText: "Oatmeal does not have enough safe local meeting context to answer yet because the transcript failed and there are no usable raw notes or summary artifacts to ground against.",
                    emptyStateText: "Retry transcription or add raw notes first. Oatmeal will not guess when the meeting context is still incomplete.",
                    composerFootnote: "This workspace stays locked until the note has local material Oatmeal can cite safely."
                )
            }

            return AIWorkspacePresentationState(
                canInteract: false,
                introText: "Oatmeal needs local meeting material before this workspace can answer. It only works from the transcript, raw notes, enhanced note, or live transcript preview attached to this note.",
                emptyStateText: "Add a few raw notes or wait for capture/transcription to finish, and the workspace will become available automatically.",
                composerFootnote: "Responses stay note-local and only unlock when Oatmeal has grounded meeting context."
            )
        }

        if summaryExecutionPlan?.backend == .placeholder || summaryExecutionPlan?.executionKind == .placeholder {
            return AIWorkspacePresentationState(
                canInteract: true,
                introText: "Ask Oatmeal about this meeting. The richer local summary path is unavailable right now, so answers will stay grounded in the transcript, notes, and metadata already attached to this note.",
                emptyStateText: "No assistant prompts yet. Ask what changed, what was decided, or generate a draft, and Oatmeal will answer from the local material it already has.",
                composerFootnote: "Responses stay attached to this meeting and will survive relaunch, even while Oatmeal is using the safer local fallback path."
            )
        }

        return AIWorkspacePresentationState(
            canInteract: true,
            introText: "Ask Oatmeal about this meeting. Answers stay scoped to this note and cite the local transcript, notes, summary, or meeting metadata they came from.",
            emptyStateText: "No assistant prompts yet. Ask what changed, what was decided, or generate a draft, and Oatmeal will work from this note only.",
            composerFootnote: "Responses stay attached to this meeting and will survive relaunch."
        )
    }
}

extension PremiumAIWorkspaceTone {
    var tintColor: Color {
        switch self {
        case .empty:
            .secondary
        case .ready:
            .purple
        case .processing:
            .orange
        case .failed:
            .pink
        }
    }
}
