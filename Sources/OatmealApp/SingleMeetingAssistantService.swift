import Foundation
import OatmealCore

struct SingleMeetingAssistantRequest: Sendable {
    let noteID: MeetingNote.ID
    let noteTitle: String
    let prompt: String
    let rawNotes: String
    let transcriptSegments: [TranscriptSegment]
    let enhancedNote: EnhancedNote?
}

struct SingleMeetingAssistantResponse: Sendable {
    let text: String
    let generatedAt: Date
}

protocol SingleMeetingAssistantServicing: Sendable {
    func respond(to request: SingleMeetingAssistantRequest) async throws -> SingleMeetingAssistantResponse
}

enum SingleMeetingAssistantError: LocalizedError, Equatable {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .failed(message):
            return message
        }
    }
}

struct PlaceholderSingleMeetingAssistantService: SingleMeetingAssistantServicing {
    private let responseDelayNanoseconds: UInt64

    init(responseDelay: TimeInterval = 0.35) {
        self.responseDelayNanoseconds = UInt64(max(responseDelay, 0) * 1_000_000_000)
    }

    func respond(to request: SingleMeetingAssistantRequest) async throws -> SingleMeetingAssistantResponse {
        if responseDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: responseDelayNanoseconds)
        }

        if request.prompt.localizedCaseInsensitiveContains("#fail")
            || request.prompt.localizedCaseInsensitiveContains("force fail") {
            throw SingleMeetingAssistantError.failed(
                "Oatmeal could not finish this assistant draft. Try again in a moment."
            )
        }

        let transcriptCount = request.transcriptSegments.count
        let noteMaterialSummary: String
        if let enhancedNote = trimmedOrNil(request.enhancedNote?.summary) {
            noteMaterialSummary = "Enhanced note summary: \(enhancedNote)"
        } else if trimmedOrNil(request.rawNotes) != nil {
            noteMaterialSummary = "Raw notes are available for this meeting."
        } else if transcriptCount > 0 {
            let noun = transcriptCount == 1 ? "segment" : "segments"
            noteMaterialSummary = "Transcript includes \(transcriptCount) \(noun)."
        } else {
            noteMaterialSummary = "Oatmeal will answer from the meeting note once richer grounding lands."
        }

        let response = """
        Oatmeal is saving this assistant thread directly on “\(request.noteTitle)”.

        Prompt: \(request.prompt)

        \(noteMaterialSummary)

        This first workspace slice is intentionally narrow: the thread is durable and note-scoped, and richer grounded answers will land in the next issue.
        """

        return SingleMeetingAssistantResponse(
            text: response,
            generatedAt: Date()
        )
    }

    private func trimmedOrNil(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        return value
    }
}
