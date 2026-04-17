import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

enum CaptureMode: String, Equatable, Sendable {
    case microphoneOnly
    case systemAudioAndMicrophone
}

struct ActiveCaptureSession: Equatable, Sendable {
    let noteID: UUID
    let startedAt: Date
    let fileURL: URL
    let mode: CaptureMode
}

struct CaptureArtifact: Equatable, Sendable {
    let noteID: UUID
    let fileURL: URL
    let startedAt: Date
    let endedAt: Date
    let mode: CaptureMode

    var duration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }
}

enum CaptureEngineError: LocalizedError {
    case alreadyCapturing
    case noActiveCapture
    case missingInputDevice
    case noDisplayAvailable
    case failedToPrepareRecording(String)
    case failedToStartRecording(String)
    case failedToStopRecording(String)

    var errorDescription: String? {
        switch self {
        case .alreadyCapturing:
            "A recording is already in progress."
        case .noActiveCapture:
            "There is no active recording to stop."
        case .missingInputDevice:
            "No microphone input device is currently available."
        case .noDisplayAvailable:
            "No display was available for system-audio capture."
        case let .failedToPrepareRecording(message):
            "Unable to prepare local recording: \(message)"
        case let .failedToStartRecording(message):
            "Unable to start local recording: \(message)"
        case let .failedToStopRecording(message):
            "Unable to stop local recording: \(message)"
        }
    }
}

@MainActor
protocol MeetingCaptureEngineServing {
    var activeSession: ActiveCaptureSession? { get }
    func startCapture(for noteID: UUID, mode: CaptureMode) async throws -> ActiveCaptureSession
    func stopCapture() async throws -> CaptureArtifact
    func recordingURL(for noteID: UUID) -> URL?
    func deleteRecording(for noteID: UUID) throws
}

@MainActor
final class LiveMeetingCaptureEngine: MeetingCaptureEngineServing {
    private let fileManager: FileManager
    private let persistence: AppPersistence

    private var activeRecorder: (any CaptureRecorder)?

    init(
        fileManager: FileManager = .default,
        persistence: AppPersistence = .shared
    ) {
        self.fileManager = fileManager
        self.persistence = persistence
    }

    var activeSession: ActiveCaptureSession? {
        activeRecorder?.activeSession
    }

    func startCapture(for noteID: UUID, mode: CaptureMode) async throws -> ActiveCaptureSession {
        guard activeRecorder == nil else {
            throw CaptureEngineError.alreadyCapturing
        }

        try prepareRecordingDirectory()
        try clearExistingRecordingFiles(for: noteID)

        let recorder: any CaptureRecorder
        switch mode {
        case .microphoneOnly:
            recorder = MicrophoneCaptureRecorder(
                noteID: noteID,
                fileURL: microphoneRecordingURL(for: noteID)
            )
        case .systemAudioAndMicrophone:
            recorder = try await ScreenAudioCaptureRecorder(
                noteID: noteID,
                fileURL: systemAudioRecordingURL(for: noteID)
            )
        }

        activeRecorder = recorder
        do {
            return try await recorder.start()
        } catch {
            activeRecorder = nil
            throw error
        }
    }

    func stopCapture() async throws -> CaptureArtifact {
        guard let recorder = activeRecorder else {
            throw CaptureEngineError.noActiveCapture
        }

        do {
            let artifact = try await recorder.stop()
            activeRecorder = nil
            return artifact
        } catch {
            activeRecorder = nil
            throw error
        }
    }

    func recordingURL(for noteID: UUID) -> URL? {
        let systemURL = systemAudioRecordingURL(for: noteID)
        if fileManager.fileExists(atPath: systemURL.path) {
            return systemURL
        }

        let microphoneURL = microphoneRecordingURL(for: noteID)
        if fileManager.fileExists(atPath: microphoneURL.path) {
            return microphoneURL
        }

        return nil
    }

    func deleteRecording(for noteID: UUID) throws {
        try clearExistingRecordingFiles(for: noteID)
    }

    private func microphoneRecordingURL(for noteID: UUID) -> URL {
        recordingsDirectoryURL.appendingPathComponent("\(noteID.uuidString).caf", isDirectory: false)
    }

    private func systemAudioRecordingURL(for noteID: UUID) -> URL {
        recordingsDirectoryURL.appendingPathComponent("\(noteID.uuidString).mp4", isDirectory: false)
    }

    private var recordingsDirectoryURL: URL {
        persistence.applicationSupportDirectoryURL.appendingPathComponent("Recordings", isDirectory: true)
    }

    private func prepareRecordingDirectory() throws {
        let directoryURL = recordingsDirectoryURL
        if fileManager.fileExists(atPath: directoryURL.path) {
            return
        }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func clearExistingRecordingFiles(for noteID: UUID) throws {
        for url in [microphoneRecordingURL(for: noteID), systemAudioRecordingURL(for: noteID)] {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }
}

private protocol CaptureRecorder: Sendable {
    var activeSession: ActiveCaptureSession? { get }
    func start() async throws -> ActiveCaptureSession
    func stop() async throws -> CaptureArtifact
}

private final class MicrophoneCaptureRecorder: CaptureRecorder, @unchecked Sendable {
    private let noteID: UUID
    private let fileURL: URL

    private var audioEngine: AVAudioEngine?
    private var recordingFile: AVAudioFile?
    private var activeSessionStorage: ActiveCaptureSession?

    init(noteID: UUID, fileURL: URL) {
        self.noteID = noteID
        self.fileURL = fileURL
    }

    var activeSession: ActiveCaptureSession? {
        activeSessionStorage
    }

    func start() async throws -> ActiveCaptureSession {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        guard inputFormat.channelCount > 0 else {
            throw CaptureEngineError.missingInputDevice
        }

        let recordingFile: AVAudioFile
        do {
            recordingFile = try AVAudioFile(
                forWriting: fileURL,
                settings: inputFormat.settings,
                commonFormat: inputFormat.commonFormat,
                interleaved: inputFormat.isInterleaved
            )
        } catch {
            throw CaptureEngineError.failedToPrepareRecording(error.localizedDescription)
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { buffer, _ in
            do {
                try recordingFile.write(from: buffer)
            } catch {
                // Prototype path: write failures surface as truncated output.
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw CaptureEngineError.failedToStartRecording(error.localizedDescription)
        }

        let session = ActiveCaptureSession(
            noteID: noteID,
            startedAt: Date(),
            fileURL: fileURL,
            mode: .microphoneOnly
        )

        self.recordingFile = recordingFile
        audioEngine = engine
        activeSessionStorage = session
        return session
    }

    func stop() async throws -> CaptureArtifact {
        guard let session = activeSessionStorage, let engine = audioEngine else {
            throw CaptureEngineError.noActiveCapture
        }

        let inputNode = engine.inputNode
        inputNode.removeTap(onBus: 0)
        engine.stop()
        engine.reset()

        audioEngine = nil
        recordingFile = nil
        activeSessionStorage = nil

        return CaptureArtifact(
            noteID: session.noteID,
            fileURL: session.fileURL,
            startedAt: session.startedAt,
            endedAt: Date(),
            mode: session.mode
        )
    }
}

private final class ScreenAudioCaptureRecorder: NSObject, CaptureRecorder, @unchecked Sendable {
    private let noteID: UUID
    private let fileURL: URL
    private let lock = NSLock()

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var activeSessionStorage: ActiveCaptureSession?
    private var pendingSession: ActiveCaptureSession?
    private var pendingArtifact: CaptureArtifact?
    private var startContinuation: CheckedContinuation<ActiveCaptureSession, Error>?
    private var stopContinuation: CheckedContinuation<CaptureArtifact, Error>?

    init(noteID: UUID, fileURL: URL) async throws {
        self.noteID = noteID
        self.fileURL = fileURL
        super.init()

        let shareableContent = try await Self.currentShareableContent()
        guard let display = Self.preferredDisplay(from: shareableContent) else {
            throw CaptureEngineError.noDisplayAvailable
        }

        let excludedApplications = shareableContent.applications.filter {
            $0.processID == ProcessInfo.processInfo.processIdentifier
        }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApplications,
            exceptingWindows: []
        )

        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.queueDepth = 3
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.captureMicrophone = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.streamName = "Oatmeal Capture"

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)

        let outputConfiguration = SCRecordingOutputConfiguration()
        outputConfiguration.outputURL = fileURL
        outputConfiguration.outputFileType = .mp4

        let recordingOutput = SCRecordingOutput(
            configuration: outputConfiguration,
            delegate: self
        )

        do {
            try stream.addRecordingOutput(recordingOutput)
        } catch {
            throw CaptureEngineError.failedToPrepareRecording(error.localizedDescription)
        }

        self.stream = stream
        self.recordingOutput = recordingOutput
    }

    var activeSession: ActiveCaptureSession? {
        lock.withLock { activeSessionStorage }
    }

    func start() async throws -> ActiveCaptureSession {
        guard let stream else {
            throw CaptureEngineError.failedToPrepareRecording("stream was not configured")
        }

        let session = ActiveCaptureSession(
            noteID: noteID,
            startedAt: Date(),
            fileURL: fileURL,
            mode: .systemAudioAndMicrophone
        )

        lock.withLock {
            pendingSession = session
        }

        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                startContinuation = continuation
            }

            stream.startCapture(completionHandler: { [weak self] error in
                guard let self, let error else { return }
                self.resumeStart(with: .failure(CaptureEngineError.failedToStartRecording(error.localizedDescription)))
            })
        }
    }

    func stop() async throws -> CaptureArtifact {
        guard let stream, let session = activeSession else {
            throw CaptureEngineError.noActiveCapture
        }

        let artifact = CaptureArtifact(
            noteID: session.noteID,
            fileURL: session.fileURL,
            startedAt: session.startedAt,
            endedAt: Date(),
            mode: session.mode
        )

        lock.withLock {
            pendingArtifact = artifact
        }

        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                stopContinuation = continuation
            }

            stream.stopCapture(completionHandler: { [weak self] error in
                guard let self, let error else { return }
                self.resumeStop(with: .failure(CaptureEngineError.failedToStopRecording(error.localizedDescription)))
            })
        }
    }

    private func resumeStart(with result: Result<ActiveCaptureSession, Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<ActiveCaptureSession, Error>? in
            defer { startContinuation = nil }
            return startContinuation
        }

        guard let continuation else { return }

        switch result {
        case let .success(session):
            lock.withLock {
                pendingSession = nil
                activeSessionStorage = session
            }
            continuation.resume(returning: session)
        case let .failure(error):
            lock.withLock {
                pendingSession = nil
                activeSessionStorage = nil
            }
            continuation.resume(throwing: error)
        }
    }

    private func resumeStop(with result: Result<CaptureArtifact, Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<CaptureArtifact, Error>? in
            defer { stopContinuation = nil }
            return stopContinuation
        }

        guard let continuation else { return }

        switch result {
        case let .success(artifact):
            lock.withLock {
                pendingArtifact = nil
                activeSessionStorage = nil
                stream = nil
                recordingOutput = nil
            }
            continuation.resume(returning: artifact)
        case let .failure(error):
            lock.withLock {
                pendingArtifact = nil
                activeSessionStorage = nil
                stream = nil
                recordingOutput = nil
            }
            continuation.resume(throwing: error)
        }
    }

    private static func currentShareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.current
    }

    private static func preferredDisplay(from shareableContent: SCShareableContent) -> SCDisplay? {
        shareableContent.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? shareableContent.displays.first
    }
}

extension ScreenAudioCaptureRecorder: SCRecordingOutputDelegate, SCStreamDelegate {
    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        let session = lock.withLock { pendingSession }
        guard let session else { return }
        Task { @MainActor [weak self] in
            self?.resumeStart(with: .success(session))
        }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        let shouldResumeStart = lock.withLock { startContinuation != nil }
        Task { @MainActor [weak self] in
            if shouldResumeStart {
                self?.resumeStart(with: .failure(error))
            } else {
                self?.resumeStop(with: .failure(error))
            }
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        let artifact = lock.withLock { pendingArtifact }
        guard let artifact else { return }
        Task { @MainActor [weak self] in
            self?.resumeStop(with: .success(artifact))
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        let shouldResumeStart = lock.withLock { startContinuation != nil }
        Task { @MainActor [weak self] in
            if shouldResumeStart {
                self?.resumeStart(with: .failure(error))
            } else {
                self?.resumeStop(with: .failure(error))
            }
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
