import Foundation
import OatmealCore

protocol MockTranscriptionServing: Sendable {
    func transcribe(request: TranscriptionRequest) async throws -> TranscriptionJobResult
}

struct MockTranscriptionBackend: MockTranscriptionServing {
    func transcribe(request: TranscriptionRequest) async throws -> TranscriptionJobResult {
        let audioFileURL = request.audioFileURL
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            throw TranscriptionPipelineError.fileNotFound
        }

        let values = try audioFileURL.resourceValues(forKeys: [
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .isRegularFileKey
        ])

        guard values.isRegularFile == true else {
            throw TranscriptionPipelineError.fileNotFound
        }

        let fileSize = Int64(values.fileSize ?? 0)
        let basisDate = request.startedAt ?? values.contentModificationDate ?? values.creationDate ?? Date(timeIntervalSince1970: 0)
        let topics = deriveTopics(from: audioFileURL.deletingPathExtension().lastPathComponent)
        let segmentCount = max(1, min(4, Int((fileSize % 4) + 1)))
        let totalSpan: TimeInterval = max(18, min(180, Double(max(fileSize, 1)) / 16.0))
        let segmentSpan = totalSpan / Double(segmentCount)

        var segments: [TranscriptSegment] = []
        for index in 0..<segmentCount {
            let startOffset = segmentSpan * Double(index)
            let endOffset = min(totalSpan, startOffset + segmentSpan)
            let topic = topics[index % topics.count]
            let confidence = 0.84 + (Double((fileSize + Int64(index * 11)) % 12) / 100)

            segments.append(
                TranscriptSegment(
                    startTime: basisDate.addingTimeInterval(startOffset),
                    endTime: basisDate.addingTimeInterval(endOffset),
                    speakerName: index % 2 == 0 ? "Speaker 1" : "Speaker 2",
                    text: transcriptLine(for: topic, index: index, fileSize: fileSize),
                    confidence: min(confidence, 0.99)
                )
            )
        }

        return TranscriptionJobResult(
            segments: segments,
            backend: .mock,
            executionKind: .placeholder,
            warningMessages: [
                "Oatmeal used its placeholder transcript path because no runnable speech backend was available."
            ]
        )
    }

    private func deriveTopics(from fileName: String) -> [String] {
        let rawParts = fileName
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let normalized = rawParts.isEmpty ? ["audio", "note"] : rawParts
        return normalized.map { $0.lowercased() }
    }

    private func transcriptLine(for topic: String, index: Int, fileSize: Int64) -> String {
        let phrases = [
            "Reviewed \(topic) and captured the main points.",
            "Follow-up for \(topic): keep the next step small and concrete.",
            "Noted one action item for \(topic) based on the recording.",
            "Summarized the \(topic) discussion with a focus on delivery."
        ]

        let suffix = "Source hint: \(max(fileSize, 1)) bytes, segment \(index + 1)."
        return "\(phrases[index % phrases.count]) \(suffix)"
    }
}
