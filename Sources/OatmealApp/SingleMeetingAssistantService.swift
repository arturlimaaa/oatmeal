import Foundation
import OatmealCore

struct SingleMeetingAssistantRequest: Sendable {
    let noteID: MeetingNote.ID
    let noteTitle: String
    let turnKind: NoteAssistantTurnKind
    let prompt: String
    let rawNotes: String
    let transcriptSegments: [TranscriptSegment]
    let enhancedNote: EnhancedNote?
    let calendarEvent: CalendarEvent?
}

struct SingleMeetingAssistantResponse: Sendable {
    let text: String
    let citations: [NoteAssistantCitation]
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

struct GroundedSingleMeetingAssistantService: SingleMeetingAssistantServicing {
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

        let planner = SingleMeetingAssistantGroundingPlanner(request: request)
        return planner.makeResponse(generatedAt: Date())
    }
}

private struct SingleMeetingAssistantGroundingPlanner {
    private let request: SingleMeetingAssistantRequest
    private let promptTokens: Set<String>
    private let evidence: [Evidence]

    init(request: SingleMeetingAssistantRequest) {
        self.request = request
        self.promptTokens = Self.normalizedTokens(from: request.prompt)
        self.evidence = Self.buildEvidence(from: request)
    }

    func makeResponse(generatedAt: Date) -> SingleMeetingAssistantResponse {
        let scoredEvidence = rankEvidence()
        let selectedEvidence = Array(scoredEvidence.prefix(3))
        let citations = selectedEvidence.map(\.citation)

        guard !evidence.isEmpty else {
            return missingEvidenceResponse(generatedAt: generatedAt)
        }

        let hasStrongGrounding = selectedEvidence.contains { $0.score >= 6 }
        if !hasStrongGrounding {
            return weakGroundingResponse(
                selectedEvidence: selectedEvidence,
                citations: citations,
                generatedAt: generatedAt
            )
        }

        switch request.turnKind {
        case .prompt:
            return answerResponse(
                selectedEvidence: selectedEvidence,
                citations: citations,
                generatedAt: generatedAt
            )
        case .followUpEmail:
            return followUpEmailResponse(
                selectedEvidence: selectedEvidence,
                citations: citations,
                generatedAt: generatedAt
            )
        case .slackRecap:
            return slackRecapResponse(
                selectedEvidence: selectedEvidence,
                citations: citations,
                generatedAt: generatedAt
            )
        }
    }

    private func missingEvidenceResponse(generatedAt: Date) -> SingleMeetingAssistantResponse {
        SingleMeetingAssistantResponse(
            text: """
            I don’t have enough grounded meeting material in this note to \(requestedTaskDescription) yet.

            Add raw notes or let Oatmeal finish the transcript first, and I’ll work from that note only.
            """,
            citations: [],
            generatedAt: generatedAt
        )
    }

    private func weakGroundingResponse(
        selectedEvidence: [ScoredEvidence],
        citations: [NoteAssistantCitation],
        generatedAt: Date
    ) -> SingleMeetingAssistantResponse {
        let fallbackCitations = Array(citations.prefix(2))
        let fallbackHighlights = Array(selectedEvidence.prefix(2)).map { sentence($0.summaryLine) }
        let fallbackSummary = fallbackHighlights.isEmpty
            ? "The current note only has light local evidence."
            : fallbackHighlights.map { "• \($0)" }.joined(separator: "\n")

        return SingleMeetingAssistantResponse(
            text: """
            I don’t have enough grounded context in this meeting note to \(requestedTaskDescription) confidently.

            The closest note-local evidence I found is:
            \(fallbackSummary)
            """,
            citations: fallbackCitations,
            generatedAt: generatedAt
        )
    }

    private func answerResponse(
        selectedEvidence: [ScoredEvidence],
        citations: [NoteAssistantCitation],
        generatedAt: Date
    ) -> SingleMeetingAssistantResponse {
        let answerBody = selectedEvidence.map { "• \(sentence($0.summaryLine))" }.joined(separator: "\n")
        let cautiousSuffix = selectedEvidence.count == 1
            ? "\n\nThis answer is grounded in a narrow slice of the note, so I’d treat it as partial."
            : ""

        return SingleMeetingAssistantResponse(
            text: """
            Based on this meeting note, the strongest grounded answer to “\(request.prompt)” is:

            \(answerBody)\(cautiousSuffix)
            """,
            citations: citations,
            generatedAt: generatedAt
        )
    }

    private func followUpEmailResponse(
        selectedEvidence: [ScoredEvidence],
        citations: [NoteAssistantCitation],
        generatedAt: Date
    ) -> SingleMeetingAssistantResponse {
        let trimmedTitle = request.noteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = trimmedTitle.isEmpty ? "Follow-up" : "Follow-up: \(trimmedTitle)"
        let meetingReference = trimmedTitle.isEmpty ? "today’s meeting" : "“\(trimmedTitle)”"
        let bulletList = selectedEvidence.map { "- \(sentence($0.summaryLine))" }.joined(separator: "\n")

        return SingleMeetingAssistantResponse(
            text: """
            Subject: \(subject)

            \(emailGreeting)

            Thanks again for the time today. Here’s a quick follow-up from \(meetingReference):

            \(bulletList)

            Please reply if I missed anything.

            Thanks,
            """,
            citations: citations,
            generatedAt: generatedAt
        )
    }

    private func slackRecapResponse(
        selectedEvidence: [ScoredEvidence],
        citations: [NoteAssistantCitation],
        generatedAt: Date
    ) -> SingleMeetingAssistantResponse {
        let trimmedTitle = request.noteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let openingLine = trimmedTitle.isEmpty
            ? "Quick recap:"
            : "Quick recap from \(trimmedTitle):"
        let bulletList = selectedEvidence.map { "- \(sentence($0.summaryLine))" }.joined(separator: "\n")

        return SingleMeetingAssistantResponse(
            text: """
            \(openingLine)

            \(bulletList)

            Let me know if I missed anything.
            """,
            citations: citations,
            generatedAt: generatedAt
        )
    }

    private func rankEvidence() -> [ScoredEvidence] {
        evidence
            .map { evidence in
                ScoredEvidence(
                    evidence: evidence,
                    score: score(for: evidence)
                )
            }
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }

                if lhs.evidence.baseWeight != rhs.evidence.baseWeight {
                    return lhs.evidence.baseWeight > rhs.evidence.baseWeight
                }

                return lhs.evidence.ordinal < rhs.evidence.ordinal
            }
    }

    private func score(for evidence: Evidence) -> Double {
        var score = evidence.baseWeight
        let normalizedPrompt = request.prompt.lowercased()
        let normalizedText = evidence.searchText

        if !promptTokens.isEmpty {
            let overlap = promptTokens.intersection(evidence.tokens)
            score += Double(overlap.count) * 4
        }

        if normalizedText.contains(normalizedPrompt) && normalizedPrompt.count > 6 {
            score += 8
        }

        if normalizedPrompt.contains("decision"), evidence.citation.kind == .enhancedDecision {
            score += 8
        }

        if normalizedPrompt.contains("risk")
            || normalizedPrompt.contains("question")
            || normalizedPrompt.contains("blocker") {
            if evidence.citation.kind == .enhancedRisk {
                score += 8
            }
        }

        if normalizedPrompt.contains("action")
            || normalizedPrompt.contains("follow up")
            || normalizedPrompt.contains("next step")
            || normalizedPrompt.contains("owner") {
            if evidence.citation.kind == .enhancedActionItem {
                score += 8
            }
        }

        if normalizedPrompt.contains("summary")
            || normalizedPrompt.contains("recap")
            || normalizedPrompt.contains("overview")
            || normalizedPrompt.contains("what changed") {
            if evidence.citation.kind == .enhancedSummary || evidence.citation.kind == .rawNotes {
                score += 5
            }
        }

        if normalizedPrompt.contains("who")
            || normalizedPrompt.contains("attendee")
            || normalizedPrompt.contains("when")
            || normalizedPrompt.contains("where") {
            if evidence.citation.kind == .metadata {
                score += 6
            }
        }

        switch request.turnKind {
        case .prompt:
            break
        case .followUpEmail:
            switch evidence.citation.kind {
            case .enhancedActionItem:
                score += 8
            case .enhancedDecision:
                score += 6
            case .enhancedSummary, .rawNotes:
                score += 5
            case .metadata:
                score += 2
            default:
                break
            }
        case .slackRecap:
            switch evidence.citation.kind {
            case .enhancedSummary, .rawNotes:
                score += 7
            case .enhancedDecision:
                score += 6
            case .enhancedActionItem, .enhancedKeyPoint:
                score += 5
            case .metadata:
                score += 2
            default:
                break
            }
        }

        return score
    }

    private var requestedTaskDescription: String {
        switch request.turnKind {
        case .prompt:
            return "answer “\(request.prompt)”"
        case .followUpEmail:
            return "draft a follow-up email"
        case .slackRecap:
            return "draft a Slack recap"
        }
    }

    private var emailGreeting: String {
        let attendeeNames = request.calendarEvent?.attendees.map(\.name) ?? []
        switch attendeeNames.count {
        case 1:
            return "Hi \(attendeeNames[0]),"
        case 2:
            return "Hi \(attendeeNames[0]) and \(attendeeNames[1]),"
        default:
            return "Hi all,"
        }
    }

    private func sentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return trimmed
        }

        if let last = trimmed.last, ".!?".contains(last) {
            return trimmed
        }

        return trimmed + "."
    }

    private static func buildEvidence(from request: SingleMeetingAssistantRequest) -> [Evidence] {
        var evidence: [Evidence] = []

        for (index, segment) in request.transcriptSegments.enumerated() {
            let speakerName = segment.speakerName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = speakerName.map { "Transcript • \($0)" } ?? "Transcript"
            evidence.append(
                Evidence(
                    citation: NoteAssistantCitation(
                        kind: .transcriptSegment,
                        label: label,
                        excerpt: segment.text,
                        transcriptSegmentID: segment.id
                    ),
                    summaryLine: segment.text,
                    baseWeight: 3.5,
                    ordinal: index
                )
            )
        }

        let rawLines = request.rawNotes
            .split(separator: "\n")
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for (index, line) in rawLines.enumerated() {
            evidence.append(
                Evidence(
                    citation: NoteAssistantCitation(
                        kind: .rawNotes,
                        label: "Raw notes",
                        excerpt: line
                    ),
                    summaryLine: line,
                    baseWeight: 2.8,
                    ordinal: 1_000 + index
                )
            )
        }

        if let enhancedNote = request.enhancedNote {
            if !enhancedNote.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                evidence.append(
                    Evidence(
                        citation: NoteAssistantCitation(
                            kind: .enhancedSummary,
                            label: "Enhanced summary",
                            excerpt: enhancedNote.summary
                        ),
                        summaryLine: enhancedNote.summary,
                        baseWeight: 3.0,
                        ordinal: 2_000
                    )
                )
            }

            evidence.append(contentsOf: enhancedNote.keyDiscussionPoints.enumerated().map { index, point in
                Evidence(
                    citation: NoteAssistantCitation(
                        kind: .enhancedKeyPoint,
                        label: "Key point",
                        excerpt: point
                    ),
                    summaryLine: point,
                    baseWeight: 2.7,
                    ordinal: 2_100 + index
                )
            })

            evidence.append(contentsOf: enhancedNote.decisions.enumerated().map { index, decision in
                Evidence(
                    citation: NoteAssistantCitation(
                        kind: .enhancedDecision,
                        label: "Decision",
                        excerpt: decision
                    ),
                    summaryLine: decision,
                    baseWeight: 3.1,
                    ordinal: 2_200 + index
                )
            })

            evidence.append(contentsOf: enhancedNote.risksOrOpenQuestions.enumerated().map { index, risk in
                Evidence(
                    citation: NoteAssistantCitation(
                        kind: .enhancedRisk,
                        label: "Risk / question",
                        excerpt: risk
                    ),
                    summaryLine: risk,
                    baseWeight: 2.9,
                    ordinal: 2_300 + index
                )
            })

            evidence.append(contentsOf: enhancedNote.actionItems.enumerated().map { index, item in
                let line = item.assignee.map { "\($0) owns: \(item.text)" } ?? item.text
                return Evidence(
                    citation: NoteAssistantCitation(
                        kind: .enhancedActionItem,
                        label: "Action item",
                        excerpt: line
                    ),
                    summaryLine: line,
                    baseWeight: 3.0,
                    ordinal: 2_400 + index
                )
            })
        }

        evidence.append(contentsOf: metadataEvidence(from: request))
        return evidence
    }

    private static func metadataEvidence(from request: SingleMeetingAssistantRequest) -> [Evidence] {
        var evidence: [Evidence] = []
        let title = request.noteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            evidence.append(
                Evidence(
                    citation: NoteAssistantCitation(
                        kind: .metadata,
                        label: "Meeting title",
                        excerpt: title
                    ),
                    summaryLine: "This note is for “\(title)”.",
                    baseWeight: 1.0,
                    ordinal: 3_000
                )
            )
        }

        guard let event = request.calendarEvent else {
            return evidence
        }

        evidence.append(
            Evidence(
                citation: NoteAssistantCitation(
                    kind: .metadata,
                    label: "Calendar timing",
                    excerpt: "\(event.startDate.formatted(date: .abbreviated, time: .shortened)) to \(event.endDate.formatted(date: .omitted, time: .shortened))"
                ),
                summaryLine: "The calendar event ran from \(event.startDate.formatted(date: .abbreviated, time: .shortened)) to \(event.endDate.formatted(date: .omitted, time: .shortened)).",
                baseWeight: 1.1,
                ordinal: 3_010
            )
        )

        if !event.attendees.isEmpty {
            let attendees = event.attendees.map(\.name).joined(separator: ", ")
            evidence.append(
                Evidence(
                    citation: NoteAssistantCitation(
                        kind: .metadata,
                        label: "Attendees",
                        excerpt: attendees
                    ),
                    summaryLine: "Attendees: \(attendees)",
                    baseWeight: 1.2,
                    ordinal: 3_020
                )
            )
        }

        if let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines),
           !location.isEmpty {
            evidence.append(
                Evidence(
                    citation: NoteAssistantCitation(
                        kind: .metadata,
                        label: "Location",
                        excerpt: location
                    ),
                    summaryLine: "Location: \(location)",
                    baseWeight: 1.1,
                    ordinal: 3_030
                )
            )
        }

        return evidence
    }

    private static func normalizedTokens(from text: String) -> Set<String> {
        let stopWords: Set<String> = [
            "a", "an", "and", "are", "as", "at", "be", "but", "by", "did", "do", "for", "from",
            "how", "i", "in", "is", "it", "me", "of", "on", "or", "that", "the", "this", "to",
            "was", "we", "what", "when", "where", "who", "why", "with", "you"
        ]

        let components = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        return Set(components.filter { token in
            token.count > 2 && !stopWords.contains(token)
        })
    }

    private struct Evidence {
        let citation: NoteAssistantCitation
        let summaryLine: String
        let baseWeight: Double
        let ordinal: Int

        var searchText: String {
            [citation.label, citation.excerpt, summaryLine].joined(separator: " ").lowercased()
        }

        var tokens: Set<String> {
            SingleMeetingAssistantGroundingPlanner.normalizedTokens(from: searchText)
        }
    }

    private struct ScoredEvidence {
        let evidence: Evidence
        let score: Double

        var citation: NoteAssistantCitation { evidence.citation }
        var summaryLine: String { evidence.summaryLine }
    }
}
