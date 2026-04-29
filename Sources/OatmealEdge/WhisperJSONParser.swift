import Foundation
import OatmealCore

enum WhisperJSONParser {
    struct ParseResult: Equatable {
        let segments: [TranscriptSegment]
        let detectedLanguage: String?
    }

    static func parseTranscriptSegments(
        data: Data,
        startedAt: Date?
    ) throws -> [TranscriptSegment] {
        try parse(data: data, startedAt: startedAt).segments
    }

    static func parse(
        data: Data,
        startedAt: Date?
    ) throws -> ParseResult {
        let object = try JSONSerialization.jsonObject(with: data)
        let walker = JSONWalker(startedAt: startedAt)
        let detectedLanguage = walker.extractDetectedLanguage(from: object)
        let candidates = walker.collectSegments(from: object)

        if !candidates.isEmpty {
            return ParseResult(
                segments: candidates.map(\.segment),
                detectedLanguage: detectedLanguage
            )
        }

        if let text = walker.extractFirstTranscriptText(from: object)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return ParseResult(
                segments: [
                    TranscriptSegment(
                        startTime: startedAt,
                        endTime: startedAt,
                        speakerName: nil,
                        text: text,
                        confidence: nil
                    )
                ],
                detectedLanguage: detectedLanguage
            )
        }

        throw TranscriptionPipelineError.transcriptionFailed("whisper.cpp did not return any transcript segments.")
    }
}

private struct ParsedCandidate: Equatable {
    let startMilliseconds: Double?
    let endMilliseconds: Double?
    let segment: TranscriptSegment
}

private struct JSONWalker {
    let startedAt: Date?

    func collectSegments(from object: Any) -> [ParsedCandidate] {
        var results: [ParsedCandidate] = []
        appendSegments(from: object, into: &results)

        return results
            .sorted {
                let lhs = $0.startMilliseconds ?? 0
                let rhs = $1.startMilliseconds ?? 0
                if lhs == rhs {
                    return $0.segment.text < $1.segment.text
                }
                return lhs < rhs
            }
            .removingAdjacentDuplicates()
    }

    /// Walks the whisper.cpp JSON looking for the detected language tag.
    ///
    /// whisper.cpp's `-ojf` output places the value at `result.language`, but
    /// older builds may surface it at the top level as `language` or under
    /// `params.language`. We scan all dictionaries and return the first
    /// non-empty `language` string we find. If absent we return `nil`.
    func extractDetectedLanguage(from object: Any) -> String? {
        if let dictionary = object as? [String: Any] {
            if let language = dictionary["language"] as? String {
                let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, trimmed.lowercased() != "auto" {
                    return trimmed
                }
            }

            for value in dictionary.values {
                if let language = extractDetectedLanguage(from: value) {
                    return language
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let language = extractDetectedLanguage(from: value) {
                    return language
                }
            }
        }

        return nil
    }

    func extractFirstTranscriptText(from object: Any) -> String? {
        if let dictionary = object as? [String: Any] {
            if let text = dictionary["text"] as? String {
                return text
            }

            for value in dictionary.values {
                if let text = extractFirstTranscriptText(from: value) {
                    return text
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let text = extractFirstTranscriptText(from: value) {
                    return text
                }
            }
        }

        return nil
    }

    private func appendSegments(from object: Any, into results: inout [ParsedCandidate]) {
        if let dictionary = object as? [String: Any] {
            if let candidate = parseCandidate(from: dictionary) {
                results.append(candidate)
            }

            for value in dictionary.values {
                appendSegments(from: value, into: &results)
            }
        } else if let array = object as? [Any] {
            for value in array {
                appendSegments(from: value, into: &results)
            }
        }
    }

    private func parseCandidate(from dictionary: [String: Any]) -> ParsedCandidate? {
        guard let rawText = dictionary["text"] as? String else {
            return nil
        }

        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }

        let offsets = dictionary["offsets"] as? [String: Any]
        let timestampValues = dictionary["timestamps"] as? [String: Any]
        let startMilliseconds = parseMilliseconds(from: offsets?["from"]) ?? parseMilliseconds(from: dictionary["start"])
            ?? parseTimestampString(timestampValues?["from"])
        let endMilliseconds = parseMilliseconds(from: offsets?["to"]) ?? parseMilliseconds(from: dictionary["end"])
            ?? parseTimestampString(timestampValues?["to"])

        guard startMilliseconds != nil || endMilliseconds != nil || dictionary["id"] != nil else {
            return nil
        }

        let segment = TranscriptSegment(
            startTime: makeDate(fromMilliseconds: startMilliseconds),
            endTime: makeDate(fromMilliseconds: endMilliseconds),
            speakerName: nil,
            text: text,
            confidence: parseConfidence(from: dictionary)
        )

        return ParsedCandidate(
            startMilliseconds: startMilliseconds,
            endMilliseconds: endMilliseconds,
            segment: segment
        )
    }

    private func makeDate(fromMilliseconds milliseconds: Double?) -> Date? {
        guard let milliseconds, let startedAt else {
            return nil
        }

        return startedAt.addingTimeInterval(milliseconds / 1000)
    }

    private func parseMilliseconds(from value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            if let numeric = Double(string) {
                return numeric
            }
            return parseTimestampString(string)
        default:
            return nil
        }
    }

    private func parseTimestampString(_ value: Any?) -> Double? {
        guard let string = value as? String else {
            return nil
        }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        let pieces = normalized.split(separator: ":")
        guard !pieces.isEmpty else {
            return nil
        }

        var seconds = 0.0
        for piece in pieces {
            guard let value = Double(piece) else {
                return nil
            }
            seconds = (seconds * 60) + value
        }

        return seconds * 1000
    }

    private func parseConfidence(from dictionary: [String: Any]) -> Double? {
        if let confidence = dictionary["p"] as? NSNumber {
            return confidence.doubleValue
        }
        if let confidence = dictionary["confidence"] as? NSNumber {
            return confidence.doubleValue
        }
        return nil
    }
}

private extension Array where Element == ParsedCandidate {
    func removingAdjacentDuplicates() -> [ParsedCandidate] {
        var results: [ParsedCandidate] = []

        for candidate in self {
            if let previous = results.last,
               previous.startMilliseconds == candidate.startMilliseconds,
               previous.endMilliseconds == candidate.endMilliseconds,
               previous.segment.text == candidate.segment.text {
                continue
            }
            results.append(candidate)
        }

        return results
    }
}
