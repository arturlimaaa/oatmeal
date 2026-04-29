import Foundation
import OatmealCore
import Speech

protocol AppleSpeechTranscriptionServing: Sendable {
    func status(preferredLocaleIdentifier: String?) -> TranscriptionBackendStatus
    func transcribe(request: TranscriptionRequest) async throws -> TranscriptionJobResult
}

struct AppleSpeechTranscriptionBackend: AppleSpeechTranscriptionServing {
    func status(preferredLocaleIdentifier: String?) -> TranscriptionBackendStatus {
        let recognizer = makeRecognizer(localeIdentifier: preferredLocaleIdentifier)
        let authorizationStatus = SFSpeechRecognizer.authorizationStatus()
        let isAutoDetect = (preferredLocaleIdentifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        guard recognizer != nil else {
            return TranscriptionBackendStatus(
                backend: .appleSpeech,
                displayName: "Apple Speech",
                availability: .unavailable,
                detail: "No compatible Apple Speech recognizer is available for the selected locale.",
                isRunnable: false
            )
        }

        switch authorizationStatus {
        case .authorized:
            let isAvailable = recognizer?.isAvailable == true
            if isAvailable, isAutoDetect {
                let systemLocaleIdentifier = Locale.current.identifier
                return TranscriptionBackendStatus(
                    backend: .appleSpeech,
                    displayName: "Apple Speech",
                    availability: .degraded,
                    detail: "Auto-detect requires Whisper. Apple Speech will run in the system locale (\(systemLocaleIdentifier)).",
                    isRunnable: true
                )
            }
            return TranscriptionBackendStatus(
                backend: .appleSpeech,
                displayName: "Apple Speech",
                availability: isAvailable ? .available : .degraded,
                detail: isAvailable
                    ? "System speech recognition is ready, but macOS may still use network-backed transcription."
                    : "Speech recognition is authorized but the system service is not currently available.",
                isRunnable: isAvailable
            )
        case .notDetermined:
            return TranscriptionBackendStatus(
                backend: .appleSpeech,
                displayName: "Apple Speech",
                availability: .degraded,
                detail: "Speech recognition permission has not been granted yet.",
                isRunnable: false
            )
        case .denied:
            return TranscriptionBackendStatus(
                backend: .appleSpeech,
                displayName: "Apple Speech",
                availability: .unavailable,
                detail: "Speech recognition permission is denied for Oatmeal.",
                isRunnable: false
            )
        case .restricted:
            return TranscriptionBackendStatus(
                backend: .appleSpeech,
                displayName: "Apple Speech",
                availability: .unavailable,
                detail: "Speech recognition is restricted on this Mac.",
                isRunnable: false
            )
        @unknown default:
            return TranscriptionBackendStatus(
                backend: .appleSpeech,
                displayName: "Apple Speech",
                availability: .unavailable,
                detail: "Speech recognition reported an unknown authorization state.",
                isRunnable: false
            )
        }
    }

    func transcribe(request: TranscriptionRequest) async throws -> TranscriptionJobResult {
        guard FileManager.default.fileExists(atPath: request.audioFileURL.path) else {
            throw TranscriptionPipelineError.fileNotFound
        }

        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw TranscriptionPipelineError.speechAuthorizationRequired
        }

        guard let recognizer = makeRecognizer(localeIdentifier: request.preferredLocaleIdentifier) else {
            throw TranscriptionPipelineError.speechRecognizerUnavailable("The configured Apple Speech locale is not supported.")
        }

        guard recognizer.isAvailable else {
            throw TranscriptionPipelineError.speechRecognizerUnavailable("Apple Speech is not available right now.")
        }

        let recognizerLocaleIdentifier = recognizer.locale.identifier
        let speechRequest = SFSpeechURLRecognitionRequest(url: request.audioFileURL)
        speechRequest.shouldReportPartialResults = false
        speechRequest.taskHint = .dictation
        speechRequest.addsPunctuation = true

        return try await withCheckedThrowingContinuation { continuation in
            let bridge = RecognitionBridge(continuation: continuation, request: request)
            bridge.task = recognizer.recognitionTask(with: speechRequest) { result, error in
                if let error {
                    bridge.resume(
                        with: .failure(
                            TranscriptionPipelineError.transcriptionFailed(error.localizedDescription)
                        )
                    )
                    return
                }

                guard let result, result.isFinal else {
                    return
                }

                let formattedSegments = Self.makeSegments(from: result, request: request)
                bridge.resume(
                    with: .success(
                        TranscriptionJobResult(
                            segments: formattedSegments,
                            backend: .appleSpeech,
                            executionKind: .systemService,
                            warningMessages: [
                                "Apple Speech on macOS 15 is a best-effort fallback and may use network-backed recognition."
                            ],
                            detectedLanguage: recognizerLocaleIdentifier.isEmpty ? nil : recognizerLocaleIdentifier
                        )
                    )
                )
            }
        }
    }

    private func makeRecognizer(localeIdentifier: String?) -> SFSpeechRecognizer? {
        if let localeIdentifier, !localeIdentifier.isEmpty {
            return SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
        }
        return SFSpeechRecognizer()
    }

    private static func makeSegments(
        from result: SFSpeechRecognitionResult,
        request: TranscriptionRequest
    ) -> [TranscriptSegment] {
        let baseDate = request.startedAt
        let segments = result.bestTranscription.segments.map { segment in
            let startTime = baseDate.map { $0.addingTimeInterval(segment.timestamp) }
            let endTime = startTime.map { $0.addingTimeInterval(segment.duration) }
            return TranscriptSegment(
                startTime: startTime,
                endTime: endTime,
                speakerName: nil,
                text: segment.substring,
                confidence: Double(segment.confidence)
            )
        }

        if !segments.isEmpty {
            return segments
        }

        return [
            TranscriptSegment(
                startTime: baseDate,
                endTime: baseDate,
                speakerName: nil,
                text: result.bestTranscription.formattedString,
                confidence: nil
            )
        ]
    }
}

private final class RecognitionBridge: @unchecked Sendable {
    private let continuation: CheckedContinuation<TranscriptionJobResult, Error>
    private let request: TranscriptionRequest
    private let lock = NSLock()
    private var hasResumed = false

    var task: SFSpeechRecognitionTask?

    init(
        continuation: CheckedContinuation<TranscriptionJobResult, Error>,
        request: TranscriptionRequest
    ) {
        self.continuation = continuation
        self.request = request
    }

    func resume(with result: Result<TranscriptionJobResult, Error>) {
        lock.lock()
        defer { lock.unlock() }

        guard !hasResumed else {
            return
        }

        hasResumed = true
        task?.cancel()

        switch result {
        case let .success(value):
            continuation.resume(returning: value)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }
}
