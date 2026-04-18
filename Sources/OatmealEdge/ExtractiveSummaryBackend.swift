import Foundation
import OatmealCore

public protocol ExtractiveSummaryServing: Sendable {
    func status(configuration: LocalSummaryConfiguration) -> SummaryBackendStatus
    func generate(
        request: NoteGenerationRequest,
        configuration: LocalSummaryConfiguration
    ) async throws -> SummaryJobResult
}

public protocol PlaceholderSummaryServing: Sendable {
    func status() -> SummaryBackendStatus
    func generate(request: NoteGenerationRequest) async throws -> SummaryJobResult
}

public struct ExtractiveSummaryBackend: ExtractiveSummaryServing {
    public init() {}

    public func status(configuration: LocalSummaryConfiguration) -> SummaryBackendStatus {
        SummaryBackendStatus(
            backend: .extractiveLocal,
            displayName: "Extractive Local",
            availability: .available,
            detail: "Fully local structured note generation using transcript and raw-note heuristics. This is the current offline summary backend.",
            isRunnable: true
        )
    }

    public func generate(
        request: NoteGenerationRequest,
        configuration: LocalSummaryConfiguration
    ) async throws -> SummaryJobResult {
        let rawLines = normalizedRawLines(from: request.rawNotes)
        let transcriptLines = normalizedTranscriptLines(from: request.transcriptSegments)
        let combinedLines = deduplicated(rawLines + transcriptLines)

        guard !combinedLines.isEmpty else {
            throw SummaryPipelineError.generationFailed(
                "Oatmeal could not build an enhanced note because no transcript or raw-note content was available."
            )
        }

        let summary = buildSummary(title: request.title, rawLines: rawLines, transcriptLines: transcriptLines)
        let keyPoints = extractKeyDiscussionPoints(rawLines: rawLines, transcriptLines: transcriptLines)
        let decisions = extractTaggedLines(
            from: combinedLines,
            keywords: ["decided", "decision", "agreed", "approved", "ship", "greenlit", "resolved"],
            limit: 5
        )
        let openQuestions = extractTaggedLines(
            from: combinedLines,
            keywords: ["question", "risk", "blocker", "unclear", "concern", "issue", "dependency"],
            limit: 5
        )
        let actionItems = extractActionItems(from: combinedLines)
        let citations = extractCitations(
            from: request.transcriptSegments,
            for: keyPoints + decisions + openQuestions + actionItems.map(\.text)
        )

        let enhancedNote = EnhancedNote(
            generatedAt: Date(),
            templateID: request.template.id,
            summary: summary,
            keyDiscussionPoints: keyPoints,
            decisions: decisions,
            risksOrOpenQuestions: openQuestions,
            actionItems: actionItems,
            citations: citations
        )

        return SummaryJobResult(
            enhancedNote: enhancedNote,
            backend: .extractiveLocal,
            executionKind: .local
        )
    }

    private func normalizedRawLines(from rawNotes: String) -> [String] {
        rawNotes
            .split(whereSeparator: \.isNewline)
            .map { normalizeLine(String($0)) }
            .filter { !$0.isEmpty }
    }

    private func normalizedTranscriptLines(from transcriptSegments: [TranscriptSegment]) -> [String] {
        transcriptSegments
            .map(\.text)
            .map(normalizeLine(_:))
            .filter { !$0.isEmpty }
    }

    private func normalizeLine(_ line: String) -> String {
        var normalized = line.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = normalized.first, "#-*•".contains(first) {
            normalized.removeFirst()
            normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return normalized
    }

    private func buildSummary(title: String, rawLines: [String], transcriptLines: [String]) -> String {
        let primary = rawLines.first ?? transcriptLines.first ?? "Captured meeting details"
        let secondary = (rawLines.dropFirst().first { $0.caseInsensitiveCompare(primary) != .orderedSame })
            ?? transcriptLines.first { $0.caseInsensitiveCompare(primary) != .orderedSame }

        if let secondary {
            return "Meeting recap for \(title): \(sentence(primary)) \(sentence(secondary))"
        }

        return "Meeting recap for \(title): \(sentence(primary))"
    }

    private func extractKeyDiscussionPoints(rawLines: [String], transcriptLines: [String]) -> [String] {
        let rawBullets = rawLines.filter { !$0.isEmpty }
        let transcriptHighlights = transcriptLines.filter { $0.split(separator: " ").count >= 5 }
        let points = deduplicated(rawBullets + transcriptHighlights)
        return Array(points.prefix(6))
    }

    private func extractTaggedLines(
        from lines: [String],
        keywords: [String],
        limit: Int
    ) -> [String] {
        let matches = lines.filter { line in
            let lowercased = line.lowercased()
            return keywords.contains(where: { lowercased.contains($0) })
        }
        return Array(deduplicated(matches).prefix(limit))
    }

    private func extractActionItems(from lines: [String]) -> [ActionItem] {
        let keywords = [
            "action", "follow up", "next step", "todo", "send", "share",
            "schedule", "review", "prepare", "draft", "update", "reach out", "circle back", "owner"
        ]

        let candidates = lines.filter { line in
            let lowercased = line.lowercased()
            return keywords.contains(where: { lowercased.contains($0) })
        }

        return Array(deduplicated(candidates).prefix(6)).map { line in
            ActionItem(text: sentence(line), assignee: inferredAssignee(from: line))
        }
    }

    private func extractCitations(
        from transcriptSegments: [TranscriptSegment],
        for highlightLines: [String]
    ) -> [SourceCitation] {
        guard !transcriptSegments.isEmpty else {
            return []
        }

        let matchedSegments = transcriptSegments.filter { segment in
            let segmentText = segment.text.lowercased()
            return highlightLines.contains(where: { highlight in
                let normalizedHighlight = highlight.lowercased()
                return !normalizedHighlight.isEmpty
                    && (segmentText.contains(normalizedHighlight)
                        || normalizedHighlight.contains(segmentText.prefix(40)))
            })
        }

        let sourceSegments = matchedSegments.isEmpty ? Array(transcriptSegments.prefix(3)) : Array(matchedSegments.prefix(4))
        return sourceSegments.map { segment in
            SourceCitation(transcriptSegmentIDs: [segment.id], excerpt: segment.text)
        }
    }

    private func inferredAssignee(from line: String) -> String? {
        let words = line.split(separator: " ")
        guard let first = words.first else {
            return nil
        }

        let firstWord = String(first)
        guard firstWord.first?.isUppercase == true, firstWord.count > 1 else {
            return nil
        }

        return firstWord
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

    private func deduplicated(_ lines: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for line in lines {
            let key = line.lowercased()
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            result.append(line)
        }

        return result
    }
}

public struct PlaceholderSummaryBackend: PlaceholderSummaryServing {
    public init() {}

    public func status() -> SummaryBackendStatus {
        SummaryBackendStatus(
            backend: .placeholder,
            displayName: "Placeholder",
            availability: .available,
            detail: "Deterministic fallback summary generation that keeps the note pipeline usable when the richer local backend fails.",
            isRunnable: true
        )
    }

    public func generate(request: NoteGenerationRequest) async throws -> SummaryJobResult {
        let summary: String
        if request.rawNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            summary = "Meeting recap for \(request.title)."
        } else {
            summary = request.rawNotes
        }

        let transcriptExcerpts = request.transcriptSegments.prefix(2).map { segment in
            SourceCitation(transcriptSegmentIDs: [segment.id], excerpt: segment.text)
        }

        let actionItems = request.transcriptSegments
            .filter { $0.text.lowercased().contains("action") || $0.text.lowercased().contains("follow up") }
            .map { ActionItem(text: $0.text, assignee: nil, dueDate: nil, status: .open) }

        return SummaryJobResult(
            enhancedNote: EnhancedNote(
                generatedAt: Date(),
                templateID: request.template.id,
                summary: summary,
                keyDiscussionPoints: request.rawNotes
                    .split(separator: "\n")
                    .map(String.init)
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                decisions: request.transcriptSegments
                    .filter { $0.text.lowercased().contains("decided") }
                    .map(\.text),
                risksOrOpenQuestions: request.transcriptSegments
                    .filter { $0.text.lowercased().contains("risk") || $0.text.lowercased().contains("question") }
                    .map(\.text),
                actionItems: actionItems,
                citations: Array(transcriptExcerpts)
            ),
            backend: .placeholder,
            executionKind: .placeholder,
            warningMessages: [
                "Oatmeal used the placeholder summary backend instead of the richer local structured note path."
            ]
        )
    }
}
