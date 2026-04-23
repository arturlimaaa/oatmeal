import Foundation
import OatmealCore
import SwiftUI

enum PremiumTranscriptWorkspaceTone: Equatable, Sendable {
    case empty
    case ready
    case live
    case processing
    case failed
    case focused
}

struct PremiumTranscriptWorkspaceState: Equatable, Sendable {
    let tone: PremiumTranscriptWorkspaceTone
    let title: String
    let subtitle: String
    let supportingDetail: String?
    let segmentCountText: String
    let speakerCountText: String?
    let focusTitle: String?
    let focusExcerpt: String?

    static func make(
        note: MeetingNote,
        highlightedSegmentID: TranscriptSegment.ID?
    ) -> Self {
        let segments = note.transcriptSegments
        let segmentCountText = segments.isEmpty ? "No transcript" : segments.count == 1 ? "1 line" : "\(segments.count) lines"
        let speakerCountText = speakerCountText(for: segments)

        if let highlightedSegmentID,
           let segment = segments.first(where: { $0.id == highlightedSegmentID }) {
            return Self(
                tone: .focused,
                title: "Focused transcript context",
                subtitle: "Oatmeal jumped into Transcript mode from a grounded citation so you can inspect the exact meeting context without losing the note.",
                supportingDetail: segment.speakerName ?? "Transcript segment",
                segmentCountText: segmentCountText,
                speakerCountText: speakerCountText,
                focusTitle: segment.speakerName ?? "Transcript citation",
                focusExcerpt: segment.text
            )
        }

        if note.transcriptionStatus == .failed || (note.processingState.stage == .transcription && note.processingState.status == .failed) {
            return Self(
                tone: .failed,
                title: "Transcript needs another pass",
                subtitle: "The transcript review surface stays available, but this recording needs a fresh transcription pass before Oatmeal can rebuild the full text.",
                supportingDetail: note.processingState.errorMessage ?? note.transcriptionHistory.last?.errorMessage,
                segmentCountText: segmentCountText,
                speakerCountText: speakerCountText,
                focusTitle: nil,
                focusExcerpt: nil
            )
        }

        if note.captureState.phase == .capturing || note.liveSessionState.hasPreviewEntries {
            return Self(
                tone: .live,
                title: "Live transcript review",
                subtitle: "Transcript mode is tracking the meeting as it unfolds, while the polished note remains the default home for the finished recap.",
                supportingDetail: note.liveSessionState.statusMessage,
                segmentCountText: segmentCountText,
                speakerCountText: speakerCountText,
                focusTitle: nil,
                focusExcerpt: nil
            )
        }

        if note.transcriptionStatus == .pending
            || (note.processingState.stage == .transcription && (note.processingState.status == .queued || note.processingState.status == .running))
            || (note.captureState.phase == .complete && note.transcriptionStatus == .idle && segments.isEmpty) {
            return Self(
                tone: .processing,
                title: "Transcript is on the way",
                subtitle: "Oatmeal keeps transcript review as a secondary workspace while it finishes turning the saved recording into searchable meeting text.",
                supportingDetail: note.processingState.stage == .transcription ? "Transcription is active for the latest recording." : "Recording saved locally. Transcription is queued next.",
                segmentCountText: segmentCountText,
                speakerCountText: speakerCountText,
                focusTitle: nil,
                focusExcerpt: nil
            )
        }

        if !segments.isEmpty {
            return Self(
                tone: .ready,
                title: "Transcript review",
                subtitle: "Use this mode to inspect who said what, verify AI citations, and read the meeting line-by-line without competing with the default note canvas.",
                supportingDetail: note.liveSessionState.hasPreviewEntries ? "Live transcript history is still attached to this meeting." : nil,
                segmentCountText: segmentCountText,
                speakerCountText: speakerCountText,
                focusTitle: nil,
                focusExcerpt: nil
            )
        }

        return Self(
            tone: .empty,
            title: "Transcript will appear here",
            subtitle: "Transcript mode stays intentionally quiet until Oatmeal has recording or note material to turn into searchable meeting text.",
            supportingDetail: nil,
            segmentCountText: segmentCountText,
            speakerCountText: nil,
            focusTitle: nil,
            focusExcerpt: nil
        )
    }

    private static func speakerCountText(for segments: [TranscriptSegment]) -> String? {
        guard !segments.isEmpty else {
            return nil
        }

        let speakers = Set(
            segments.map {
                let trimmed = $0.speakerName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? "Speaker" : trimmed
            }
        )
        return speakers.count == 1 ? "1 speaker" : "\(speakers.count) speakers"
    }
}

struct TranscriptWorkspaceRoute: Equatable, Sendable {
    let workspaceMode: NoteWorkspaceMode
    let transcriptSegmentID: TranscriptSegment.ID

    static func resolve(
        citation: NoteAssistantCitation,
        in note: MeetingNote
    ) -> Self? {
        guard let target = AssistantCitationNavigationTarget.resolve(citation: citation, in: note) else {
            return nil
        }

        return Self(
            workspaceMode: .transcript,
            transcriptSegmentID: target.transcriptSegmentID
        )
    }
}

extension PremiumTranscriptWorkspaceTone {
    var tintColor: Color {
        switch self {
        case .empty:
            .secondary
        case .ready:
            .blue
        case .live:
            .red
        case .processing:
            .orange
        case .failed:
            .pink
        case .focused:
            .purple
        }
    }
}
