import Foundation
import OatmealCore
import SwiftUI

enum PremiumTechnicalDetailsTone: Equatable, Sendable {
    case quiet
    case live
    case processing
    case failed
    case ready
}

struct PremiumTechnicalDetailsState: Equatable, Sendable {
    let tone: PremiumTechnicalDetailsTone
    let title: String
    let subtitle: String
    let statusBadgeText: String
    let routeBadgeText: String

    static func make(
        note: MeetingNote,
        selectedMode: NoteWorkspaceMode
    ) -> Self {
        let routeBadgeText = switch selectedMode {
        case .notes:
            "Opened from Notes"
        case .transcript:
            "Opened from Transcript"
        case .ai:
            "Opened from AI"
        case .tasks:
            "Opened from Tasks"
        }

        if note.transcriptionStatus == .failed
            || note.generationStatus == .failed
            || note.processingState.status == .failed
            || note.captureState.phase == .failed {
            return Self(
                tone: .failed,
                title: "This meeting needs a quick retry",
                subtitle: "The saved recording and note material are still here. Use this view to inspect the failure and restart the right step without cluttering the main workspace.",
                statusBadgeText: "Needs attention",
                routeBadgeText: routeBadgeText
            )
        }

        if note.captureState.phase == .capturing {
            return Self(
                tone: .live,
                title: "Capture is live behind the scenes",
                subtitle: "Oatmeal is still recording this meeting. The main workspace stays calm while this view keeps the capture, permissions, and recovery details close by.",
                statusBadgeText: "Recording",
                routeBadgeText: routeBadgeText
            )
        }

        if note.transcriptionStatus == .pending
            || note.generationStatus == .pending
            || note.processingState.isActive {
            return Self(
                tone: .processing,
                title: "Oatmeal is still finishing this meeting",
                subtitle: "This view tracks the post-meeting pipeline while the main workspace stays focused on the note, transcript, AI, and tasks.",
                statusBadgeText: "In progress",
                routeBadgeText: routeBadgeText
            )
        }

        if note.enhancedNote != nil || !note.transcriptSegments.isEmpty || !note.rawNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Self(
                tone: .ready,
                title: "Everything looks healthy",
                subtitle: "You should not need this view often. It stays here for capture, runtime, and recovery context when you want to inspect how Oatmeal handled the meeting.",
                statusBadgeText: "Healthy",
                routeBadgeText: routeBadgeText
            )
        }

        return Self(
            tone: .quiet,
            title: "Behind-the-scenes details stay out of the way",
            subtitle: "Once the meeting has recording or note material, this view will show capture, processing, and runtime details without taking over the main workspace.",
            statusBadgeText: "Standing by",
            routeBadgeText: routeBadgeText
        )
    }
}

extension PremiumTechnicalDetailsTone {
    var tintColor: Color {
        switch self {
        case .quiet:
            .secondary
        case .live:
            .red
        case .processing:
            .orange
        case .failed:
            .pink
        case .ready:
            .green
        }
    }
}
