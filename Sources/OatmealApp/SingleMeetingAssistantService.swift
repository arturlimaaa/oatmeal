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
        case .actionItems:
            return actionItemsResponse(
                selectedEvidence: selectedEvidence,
                fallbackCitations: citations,
                generatedAt: generatedAt
            )
        case .decisionsAndRisks:
            return decisionsAndRisksResponse(
                selectedEvidence: selectedEvidence,
                fallbackCitations: citations,
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

    private func actionItemsResponse(
        selectedEvidence: [ScoredEvidence],
        fallbackCitations: [NoteAssistantCitation],
        generatedAt: Date
    ) -> SingleMeetingAssistantResponse {
        let findings = actionItemFindings()
        guard !findings.isEmpty else {
            return SingleMeetingAssistantResponse(
                text: """
                I couldn’t find a grounded action item in this meeting note.

                The note has meeting context, but it doesn’t make follow-up work explicit enough for Oatmeal to extract action items without guessing.
                """,
                citations: Array(fallbackCitations.prefix(2)),
                generatedAt: generatedAt
            )
        }

        let bulletList = findings.map { "- \($0.line)" }.joined(separator: "\n")
        let hasUnclearOwner = findings.contains { $0.ownerState == .unknown }
        let hasLikelyOwner = findings.contains { $0.ownerState == .likely }
        var notes: [String] = []
        if hasLikelyOwner {
            notes.append("I labeled owners as likely when the note pointed to them strongly but did not make ownership fully explicit.")
        }
        if hasUnclearOwner {
            notes.append("Anything marked as ownership unclear stayed that way because this meeting note did not support naming an owner confidently.")
        }

        let suffix = notes.isEmpty ? "" : "\n\n" + notes.joined(separator: "\n")
        return SingleMeetingAssistantResponse(
            text: """
            Action items from this meeting:

            \(bulletList)\(suffix)
            """,
            citations: uniqueCitations(findings.map(\.citation) + fallbackCitations, limit: 4),
            generatedAt: generatedAt
        )
    }

    private func decisionsAndRisksResponse(
        selectedEvidence: [ScoredEvidence],
        fallbackCitations: [NoteAssistantCitation],
        generatedAt: Date
    ) -> SingleMeetingAssistantResponse {
        let decisions = confirmedDecisionFindings()
        let risks = riskFindings()
        let tentative = tentativeDiscussionFindings(
            excluding: Set(decisions.map(\.normalizedKey)).union(risks.map(\.normalizedKey))
        )

        guard !decisions.isEmpty || !risks.isEmpty || !tentative.isEmpty else {
            return SingleMeetingAssistantResponse(
                text: """
                I couldn’t find grounded decisions, risks, or open questions in this meeting note yet.

                There is meeting context here, but not enough explicit evidence to separate confirmed decisions from tentative discussion without overreaching.
                """,
                citations: Array(fallbackCitations.prefix(2)),
                generatedAt: generatedAt
            )
        }

        let decisionsSection = decisions.isEmpty
            ? "- No grounded decision surfaced from this note."
            : decisions.map { "- \($0.line)" }.joined(separator: "\n")
        let tentativeSection = tentative.isEmpty
            ? "- No grounded tentative thread stood out once confirmed decisions were separated."
            : tentative.map { "- \($0.line)" }.joined(separator: "\n")
        let risksSection = risks.isEmpty
            ? "- No grounded open question or risk stood out from this note."
            : risks.map { "- \($0.line)" }.joined(separator: "\n")

        return SingleMeetingAssistantResponse(
            text: """
            Decision and risk readout for this meeting:

            Confirmed decisions
            \(decisionsSection)

            Tentative / still under discussion
            \(tentativeSection)

            Open questions / risks
            \(risksSection)
            """,
            citations: uniqueCitations(
                decisions.map(\.citation) + risks.map(\.citation) + tentative.map(\.citation) + fallbackCitations,
                limit: 5
            ),
            generatedAt: generatedAt
        )
    }

    private func actionItemFindings() -> [StructuredFinding] {
        var findings: [StructuredFinding] = []
        var seen = Set<String>()

        for item in request.enhancedNote?.actionItems ?? [] {
            let cleanedText = cleanStructuredLine(item.text)
            guard !cleanedText.isEmpty else {
                continue
            }

            let trimmedOwner = item.assignee?.trimmingCharacters(in: .whitespacesAndNewlines)
            let owner = (trimmedOwner?.isEmpty == false) ? trimmedOwner : nil
            let ownerState: ActionOwnerState
            let line: String
            if let owner {
                ownerState = .confirmed
                line = "\(owner) — \(sentence(cleanedText))"
            } else if let inferredOwner = inferExplicitOwner(from: cleanedText) {
                ownerState = .likely
                line = "Likely owner: \(inferredOwner) — \(sentence(cleanedText))"
            } else {
                ownerState = .unknown
                line = "Ownership unclear — \(sentence(cleanedText))"
            }

            let normalizedKey = normalizedComparableLine(cleanedText)
            guard seen.insert(normalizedKey).inserted else {
                continue
            }

            findings.append(
                StructuredFinding(
                    line: line,
                    normalizedKey: normalizedKey,
                    citation: NoteAssistantCitation(
                        kind: .enhancedActionItem,
                        label: "Action item",
                        excerpt: owner.map { "\($0) owns: \(cleanedText)" } ?? cleanedText
                    ),
                    ownerState: ownerState
                )
            )
        }

        for source in discussionSources() {
            guard let extracted = extractActionCandidate(from: source.text, speakerName: source.speakerName) else {
                continue
            }

            guard seen.insert(extracted.normalizedKey).inserted else {
                continue
            }

            findings.append(
                StructuredFinding(
                    line: extracted.line,
                    normalizedKey: extracted.normalizedKey,
                    citation: source.citation,
                    ownerState: extracted.ownerState
                )
            )
        }

        return Array(findings.prefix(4))
    }

    private func confirmedDecisionFindings() -> [StructuredFinding] {
        var findings: [StructuredFinding] = []
        var seen = Set<String>()

        for decision in request.enhancedNote?.decisions ?? [] {
            let cleanedDecision = cleanStructuredLine(decision)
            guard !cleanedDecision.isEmpty else {
                continue
            }
            let normalizedKey = normalizedComparableLine(cleanedDecision)
            guard seen.insert(normalizedKey).inserted else {
                continue
            }

            findings.append(
                StructuredFinding(
                    line: sentence(cleanedDecision),
                    normalizedKey: normalizedKey,
                    citation: NoteAssistantCitation(
                        kind: .enhancedDecision,
                        label: "Decision",
                        excerpt: cleanedDecision
                    )
                )
            )
        }

        for source in discussionSources() where isConfirmedDecision(source.text) {
            let cleanedDecision = cleanStructuredLine(source.text)
            let normalizedKey = normalizedComparableLine(cleanedDecision)
            guard !cleanedDecision.isEmpty, seen.insert(normalizedKey).inserted else {
                continue
            }

            findings.append(
                StructuredFinding(
                    line: sentence(cleanedDecision),
                    normalizedKey: normalizedKey,
                    citation: source.citation
                )
            )
        }

        return Array(findings.prefix(3))
    }

    private func riskFindings() -> [StructuredFinding] {
        var findings: [StructuredFinding] = []
        var seen = Set<String>()

        for risk in request.enhancedNote?.risksOrOpenQuestions ?? [] {
            let cleanedRisk = cleanStructuredLine(risk)
            guard !cleanedRisk.isEmpty else {
                continue
            }
            let normalizedKey = normalizedComparableLine(cleanedRisk)
            guard seen.insert(normalizedKey).inserted else {
                continue
            }

            findings.append(
                StructuredFinding(
                    line: sentence(cleanedRisk),
                    normalizedKey: normalizedKey,
                    citation: NoteAssistantCitation(
                        kind: .enhancedRisk,
                        label: "Risk / question",
                        excerpt: cleanedRisk
                    )
                )
            )
        }

        for source in discussionSources() where isRiskOrQuestion(source.text) {
            let cleanedRisk = cleanStructuredLine(source.text)
            let normalizedKey = normalizedComparableLine(cleanedRisk)
            guard !cleanedRisk.isEmpty, seen.insert(normalizedKey).inserted else {
                continue
            }

            findings.append(
                StructuredFinding(
                    line: sentence(cleanedRisk),
                    normalizedKey: normalizedKey,
                    citation: source.citation
                )
            )
        }

        return Array(findings.prefix(3))
    }

    private func tentativeDiscussionFindings(excluding excludedKeys: Set<String>) -> [StructuredFinding] {
        var findings: [StructuredFinding] = []
        var seen = excludedKeys

        for source in discussionSources() where isTentativeDiscussion(source.text) {
            let cleanedLine = cleanStructuredLine(source.text)
            let normalizedKey = normalizedComparableLine(cleanedLine)
            guard !cleanedLine.isEmpty, seen.insert(normalizedKey).inserted else {
                continue
            }

            findings.append(
                StructuredFinding(
                    line: sentence(cleanedLine),
                    normalizedKey: normalizedKey,
                    citation: source.citation
                )
            )
        }

        return Array(findings.prefix(3))
    }

    private func discussionSources() -> [DiscussionSource] {
        var sources: [DiscussionSource] = request.transcriptSegments.enumerated().map { _, segment in
            DiscussionSource(
                text: segment.text,
                speakerName: segment.speakerName,
                citation: NoteAssistantCitation(
                    kind: .transcriptSegment,
                    label: segment.speakerName.map { "Transcript • \($0)" } ?? "Transcript",
                    excerpt: segment.text,
                    transcriptSegmentID: segment.id
                )
            )
        }

        let rawLines = request.rawNotes
            .split(separator: "\n")
            .map(String.init)
            .map(cleanStructuredLine)
            .filter { !$0.isEmpty }
        sources.append(contentsOf: rawLines.map { line in
            DiscussionSource(
                text: line,
                speakerName: nil,
                citation: NoteAssistantCitation(
                    kind: .rawNotes,
                    label: "Raw notes",
                    excerpt: line
                )
            )
        })

        if let enhancedNote = request.enhancedNote {
            sources.append(contentsOf: enhancedNote.keyDiscussionPoints.map { point in
                let cleanedPoint = cleanStructuredLine(point)
                return DiscussionSource(
                    text: cleanedPoint,
                    speakerName: nil,
                    citation: NoteAssistantCitation(
                        kind: .enhancedKeyPoint,
                        label: "Key point",
                        excerpt: cleanedPoint
                    )
                )
            })
        }

        return sources
    }

    private func extractActionCandidate(from text: String, speakerName: String?) -> ActionCandidate? {
        let cleanedLine = cleanStructuredLine(text)
        guard isActionLike(cleanedLine) else {
            return nil
        }

        let ownerResolution = resolveOwner(for: cleanedLine, speakerName: speakerName)
        let line: String
        switch ownerResolution.state {
        case let .explicit(owner):
            line = "\(owner) — \(sentence(ownerResolution.actionText))"
        case let .likely(owner):
            line = "Likely owner: \(owner) — \(sentence(ownerResolution.actionText))"
        case .unknown:
            line = "Ownership unclear — \(sentence(ownerResolution.actionText))"
        }

        return ActionCandidate(
            line: line,
            normalizedKey: normalizedComparableLine(ownerResolution.actionText),
            ownerState: ownerResolution.ownerState
        )
    }

    private func uniqueCitations(_ citations: [NoteAssistantCitation], limit: Int) -> [NoteAssistantCitation] {
        var seen = Set<String>()
        var result: [NoteAssistantCitation] = []

        for citation in citations {
            let key = [
                citation.kind.rawValue,
                citation.label,
                citation.excerpt,
                citation.transcriptSegmentID?.uuidString ?? ""
            ].joined(separator: "|")
            guard seen.insert(key).inserted else {
                continue
            }
            result.append(citation)
            if result.count == limit {
                break
            }
        }

        return result
    }

    private func cleanStructuredLine(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return trimmed
        }

        let prefixes = ["- ", "• ", "* ", "decision: ", "risk: ", "open question: ", "question: ", "action item: "]
        let lowered = trimmed.lowercased()
        for prefix in prefixes where lowered.hasPrefix(prefix) {
            return String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }

    private func normalizedComparableLine(_ text: String) -> String {
        cleanStructuredLine(text)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func inferExplicitOwner(from text: String) -> String? {
        resolveOwner(for: text, speakerName: nil).namedOwner
    }

    private func resolveOwner(for text: String, speakerName: String?) -> OwnerResolution {
        let trimmed = cleanStructuredLine(text)
        let lowercased = trimmed.lowercased()
        let attendees = request.calendarEvent?.attendees.map(\.name) ?? []

        let explicitVerbs = [" will ", " to ", " owns ", " can ", " should "]
        for attendee in attendees where !attendee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let normalizedAttendee = attendee.lowercased()
            if explicitVerbs.contains(where: { lowercased.contains("\(normalizedAttendee)\($0)") })
                || lowercased.hasPrefix("\(normalizedAttendee) will ")
                || lowercased.hasPrefix("\(normalizedAttendee) to ")
                || lowercased.hasPrefix("owner: \(normalizedAttendee)") {
                return OwnerResolution(
                    state: .explicit(attendee),
                    ownerState: .confirmed,
                    actionText: trimmed,
                    namedOwner: attendee
                )
            }
        }

        if let speakerName,
           (lowercased.hasPrefix("i will ")
            || lowercased.hasPrefix("i'll ")
            || lowercased.hasPrefix("i can ")
            || lowercased.hasPrefix("let me ")) {
            let rewritten = trimmed
                .replacingOccurrences(of: "I will ", with: "")
                .replacingOccurrences(of: "I'll ", with: "")
                .replacingOccurrences(of: "I can ", with: "")
                .replacingOccurrences(of: "Let me ", with: "")
            return OwnerResolution(
                state: .likely(speakerName),
                ownerState: .likely,
                actionText: cleanStructuredLine(rewritten),
                namedOwner: speakerName
            )
        }

        return OwnerResolution(
            state: .unknown,
            ownerState: .unknown,
            actionText: trimmed,
            namedOwner: nil
        )
    }

    private func isActionLike(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let indicators = [
            "follow up", "next step", "send ", "share ", "confirm ", "confirming", "review ",
            "prepare ", "draft ", "update ", "schedule ", "book ", "ship ", "finalize ",
            "close the loop", "circle back", "own ", "owner:", "needs to ", "need to "
        ]

        if indicators.contains(where: { lowercased.contains($0) }) {
            return true
        }

        return lowercased.contains(" will ") || lowercased.contains(" to ")
    }

    private func isConfirmedDecision(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let patterns = [
            "decided", "agreed", "decision", "approved", "greenlit", "move forward with",
            "we will", "ship ", "confirmed that"
        ]
        return patterns.contains(where: { lowercased.contains($0) })
    }

    private func isRiskOrQuestion(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let patterns = [
            "risk", "blocker", "open question", "unresolved", "need to confirm", "waiting on",
            "concern", "dependency", "pending", "unclear", "question"
        ]
        return patterns.contains(where: { lowercased.contains($0) })
    }

    private func isTentativeDiscussion(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let patterns = [
            "discussed", "considering", "maybe", "might", "could", "proposal", "option",
            "tentative", "under discussion", "exploring", "possible"
        ]
        return patterns.contains(where: { lowercased.contains($0) })
    }

    private struct DiscussionSource {
        let text: String
        let speakerName: String?
        let citation: NoteAssistantCitation
    }

    private struct StructuredFinding {
        let line: String
        let normalizedKey: String
        let citation: NoteAssistantCitation
        var ownerState: ActionOwnerState = .unknown
    }

    private struct ActionCandidate {
        let line: String
        let normalizedKey: String
        let ownerState: ActionOwnerState
    }

    private enum ActionOwnerState: Equatable {
        case confirmed
        case likely
        case unknown
    }

    private enum OwnerLabelState {
        case explicit(String)
        case likely(String)
        case unknown
    }

    private struct OwnerResolution {
        let state: OwnerLabelState
        let ownerState: ActionOwnerState
        let actionText: String
        let namedOwner: String?
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
        case .actionItems:
            switch evidence.citation.kind {
            case .enhancedActionItem:
                score += 8
            case .rawNotes, .transcriptSegment:
                if isActionLike(evidence.summaryLine) {
                    score += 5
                }
            case .metadata:
                score += 1
            default:
                break
            }
        case .decisionsAndRisks:
            switch evidence.citation.kind {
            case .enhancedDecision:
                score += 8
            case .enhancedRisk:
                score += 7
            case .enhancedKeyPoint:
                score += 5
            case .rawNotes, .transcriptSegment:
                if isConfirmedDecision(evidence.summaryLine) || isRiskOrQuestion(evidence.summaryLine) || isTentativeDiscussion(evidence.summaryLine) {
                    score += 4
                }
            case .metadata:
                score += 1
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
        case .actionItems:
            return "extract action items"
        case .decisionsAndRisks:
            return "extract decisions, risks, and open questions"
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
                    speakerName: speakerName,
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
                    speakerName: nil,
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
                        speakerName: nil,
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
                    speakerName: nil,
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
                    speakerName: nil,
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
                    speakerName: nil,
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
                    speakerName: nil,
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
                    speakerName: nil,
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
                speakerName: nil,
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
                    speakerName: nil,
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
                    speakerName: nil,
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
        let speakerName: String?
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
