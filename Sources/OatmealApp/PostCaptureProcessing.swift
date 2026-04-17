import Foundation

struct PostCaptureProcessingRequest: Equatable, Sendable {
    let noteID: UUID
    let recordingURL: URL?
    let captureStartedAt: Date?
    let processingAnchorDate: Date
    let trigger: PostCaptureProcessingTrigger
}

enum PostCaptureProcessingTrigger: String, Equatable, Sendable {
    case immediateAfterCapture
    case relaunchRecovery
    case manualRetry
}

enum PostCaptureProcessingError: LocalizedError {
    case missingRecordingArtifact(UUID)

    var errorDescription: String? {
        switch self {
        case let .missingRecordingArtifact(noteID):
            "Oatmeal could not find the local recording artifact for note \(noteID.uuidString)."
        }
    }
}
