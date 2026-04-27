@preconcurrency import AVFoundation
import Foundation

// MARK: - Public types

/// Snapshot of the audio pipeline's health, exposed to the recorder layer
/// so it can populate ``CaptureRuntimeHealthSnapshot`` and decide whether
/// the capture is degraded.
struct PipelineHealthSnapshot: Equatable, Sendable {
    let state: State
    let lastMicrophoneBufferAt: Date?
    let lastSystemAudioBufferAt: Date?
    let sampleRate: Double
    let channelCount: UInt32
    let microphoneFrameCount: AVAudioFramePosition

    enum State: Equatable, Sendable {
        case idle
        case starting
        case running
        case stopping
        case failed(reason: String)
    }

    init(
        state: State = .idle,
        lastMicrophoneBufferAt: Date? = nil,
        lastSystemAudioBufferAt: Date? = nil,
        sampleRate: Double = 0,
        channelCount: UInt32 = 0,
        microphoneFrameCount: AVAudioFramePosition = 0
    ) {
        self.state = state
        self.lastMicrophoneBufferAt = lastMicrophoneBufferAt
        self.lastSystemAudioBufferAt = lastSystemAudioBufferAt
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.microphoneFrameCount = microphoneFrameCount
    }
}

enum CaptureAudioPipelineError: LocalizedError, Equatable {
    case missingInputDevice
    case prepareFailed(String)
    case startFailed(String)
    case noActiveSession
    case stopFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingInputDevice:
            return "No microphone input device is currently available."
        case .prepareFailed(let detail):
            return "Failed to prepare the audio pipeline: \(detail)"
        case .startFailed(let detail):
            return "Failed to start the audio pipeline: \(detail)"
        case .noActiveSession:
            return "There is no active capture session to stop."
        case .stopFailed(let detail):
            return "Failed to stop the audio pipeline cleanly: \(detail)"
        }
    }
}

// MARK: - CaptureAudioPipeline

/// Unified audio pipeline driven by `AVAudioEngine`. Captures the
/// microphone today and exposes a placeholder hook
/// (``attachSystemAudioBuffers(_:)``) that Issue C will use to feed the
/// process-tap stream from `SystemAudioTapController` into the same
/// writer.
///
/// The pipeline writes the master output as `.m4a` AAC and the
/// rolling-chunk transcript sidecars as PCM `.caf` so the existing
/// transcription layer keeps working unchanged.
///
/// Not yet wired into `MeetingCaptureEngine`. Lives parallel to
/// `MicrophoneCaptureRecorder` until Issue C swaps the engine over.
actor CaptureAudioPipeline {
    private let noteID: UUID
    private let liveChunkDuration: TimeInterval

    private var session: ActiveCaptureSession?
    private var engine: AVAudioEngine?
    private var outputFile: AVAudioFile?
    private var liveChunkRecorder: PipelineLiveChunkRecorder?
    private var snapshotState: PipelineHealthSnapshot
    private var hasSystemAudioStreamAttached = false

    init(
        noteID: UUID,
        liveChunkDuration: TimeInterval = 30
    ) {
        self.noteID = noteID
        self.liveChunkDuration = liveChunkDuration
        self.snapshotState = PipelineHealthSnapshot()
    }

    var healthSnapshot: PipelineHealthSnapshot {
        snapshotState
    }

    var isRunning: Bool {
        if case .running = snapshotState.state { return true }
        return false
    }

    var completedLiveTranscriptionChunks: [LiveTranscriptionChunk] {
        liveChunkRecorder?.completedChunks ?? []
    }

    /// Open the audio engine, install the input tap, and begin writing the
    /// `.m4a` master file plus rolling PCM chunks. Idempotent: calling
    /// `start` while already running returns the existing session without
    /// re-opening hardware.
    func start(
        outputURL: URL,
        liveChunkDirectoryURL: URL
    ) async throws -> ActiveCaptureSession {
        if let session {
            return session
        }
        switch snapshotState.state {
        case .starting, .stopping:
            // Another start/stop is in flight — treat as no-op rather than
            // racing the hardware open.
            if let session { return session }
            throw CaptureAudioPipelineError.startFailed("pipeline is busy transitioning")
        default:
            break
        }

        snapshotState = PipelineHealthSnapshot(
            state: .starting,
            lastMicrophoneBufferAt: nil,
            lastSystemAudioBufferAt: nil,
            sampleRate: snapshotState.sampleRate,
            channelCount: snapshotState.channelCount,
            microphoneFrameCount: 0
        )

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            snapshotState = PipelineHealthSnapshot(state: .failed(reason: "missing input device"))
            throw CaptureAudioPipelineError.missingInputDevice
        }

        // AAC `.m4a` output. AVAudioFile delegates encoding to ExtAudioFile
        // when the settings dict requests a compressed format.
        let aacSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: inputFormat.channelCount,
            AVEncoderBitRateKey: 96_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let outputFile: AVAudioFile
        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            outputFile = try AVAudioFile(forWriting: outputURL, settings: aacSettings)
        } catch {
            snapshotState = PipelineHealthSnapshot(state: .failed(reason: error.localizedDescription))
            throw CaptureAudioPipelineError.prepareFailed(error.localizedDescription)
        }

        let chunkRecorder = PipelineLiveChunkRecorder(
            noteID: noteID,
            source: .microphone,
            directoryURL: liveChunkDirectoryURL,
            format: inputFormat,
            chunkDuration: liveChunkDuration
        )

        // Install the tap before starting the engine. Tap callbacks land on
        // an audio thread; we hop onto the actor for state mutation.
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let capturedAt = Date()
            Task { [buffer] in
                await self.handleMicrophoneBuffer(buffer, capturedAt: capturedAt)
            }
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            snapshotState = PipelineHealthSnapshot(state: .failed(reason: error.localizedDescription))
            throw CaptureAudioPipelineError.startFailed(error.localizedDescription)
        }

        let startedAt = Date()
        let session = ActiveCaptureSession(
            noteID: noteID,
            startedAt: startedAt,
            fileURL: outputURL,
            mode: .microphoneOnly
        )
        self.session = session
        self.engine = engine
        self.outputFile = outputFile
        self.liveChunkRecorder = chunkRecorder
        self.snapshotState = PipelineHealthSnapshot(
            state: .running,
            lastMicrophoneBufferAt: nil,
            lastSystemAudioBufferAt: nil,
            sampleRate: inputFormat.sampleRate,
            channelCount: inputFormat.channelCount,
            microphoneFrameCount: 0
        )
        return session
    }

    /// Stop the engine, finalize the master file, close any open chunk,
    /// and return the recording artifact. Idempotent: calling `stop`
    /// without an active session throws ``CaptureAudioPipelineError/noActiveSession``
    /// rather than crashing.
    func stop() async throws -> CaptureArtifact {
        guard let session, let engine else {
            throw CaptureAudioPipelineError.noActiveSession
        }

        snapshotState = PipelineHealthSnapshot(
            state: .stopping,
            lastMicrophoneBufferAt: snapshotState.lastMicrophoneBufferAt,
            lastSystemAudioBufferAt: snapshotState.lastSystemAudioBufferAt,
            sampleRate: snapshotState.sampleRate,
            channelCount: snapshotState.channelCount,
            microphoneFrameCount: snapshotState.microphoneFrameCount
        )

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine.reset()

        hasSystemAudioStreamAttached = false

        let endedAt = Date()
        do {
            try liveChunkRecorder?.finishOpenChunk(endedAt: endedAt)
        } catch {
            // Don't let a sidecar finalize failure block the master stop.
        }

        // AVAudioFile finalizes on deinit; release it.
        outputFile = nil
        self.engine = nil
        self.session = nil

        snapshotState = PipelineHealthSnapshot(
            state: .idle,
            lastMicrophoneBufferAt: snapshotState.lastMicrophoneBufferAt,
            lastSystemAudioBufferAt: snapshotState.lastSystemAudioBufferAt,
            sampleRate: snapshotState.sampleRate,
            channelCount: snapshotState.channelCount,
            microphoneFrameCount: snapshotState.microphoneFrameCount
        )

        return CaptureArtifact(
            noteID: session.noteID,
            fileURL: session.fileURL,
            startedAt: session.startedAt,
            endedAt: endedAt,
            mode: session.mode
        )
    }

    /// Placeholder hook. Issue C swaps the body for the real mix-and-write
    /// path that consumes buffers from `SystemAudioTapController`. Today,
    /// the call just records that an attach happened so the wiring point
    /// in Issue C lands without churning the pipeline file again.
    /// Idempotent — second attach is ignored.
    func attachSystemAudioBuffers(_ stream: AsyncStream<AVAudioPCMBuffer>) {
        guard !hasSystemAudioStreamAttached else { return }
        hasSystemAudioStreamAttached = true
        _ = stream
    }

    /// Test seam mirroring the heartbeat path that Issue C will produce
    /// when system-audio buffers arrive. Lets pipeline tests assert the
    /// snapshot updates the system-audio timestamp without having to drive
    /// a real `AsyncStream<AVAudioPCMBuffer>` through actor isolation.
    func recordSystemAudioBufferForTesting(at timestamp: Date = Date()) {
        recordSystemAudioHeartbeat(capturedAt: timestamp)
    }

    // MARK: - Internal handlers

    private func handleMicrophoneBuffer(_ buffer: AVAudioPCMBuffer, capturedAt: Date) async {
        guard isRunning, let outputFile else { return }
        do {
            try outputFile.write(from: buffer)
            try liveChunkRecorder?.append(buffer, capturedAt: capturedAt)
        } catch {
            // Writes to the master file or the sidecar failing should not
            // tear down the session — surface via the snapshot's state and
            // keep going so the rest of the meeting still records.
            snapshotState = PipelineHealthSnapshot(
                state: .failed(reason: error.localizedDescription),
                lastMicrophoneBufferAt: snapshotState.lastMicrophoneBufferAt,
                lastSystemAudioBufferAt: snapshotState.lastSystemAudioBufferAt,
                sampleRate: snapshotState.sampleRate,
                channelCount: snapshotState.channelCount,
                microphoneFrameCount: snapshotState.microphoneFrameCount
            )
            return
        }

        snapshotState = PipelineHealthSnapshot(
            state: .running,
            lastMicrophoneBufferAt: capturedAt,
            lastSystemAudioBufferAt: snapshotState.lastSystemAudioBufferAt,
            sampleRate: snapshotState.sampleRate,
            channelCount: snapshotState.channelCount,
            microphoneFrameCount: snapshotState.microphoneFrameCount + AVAudioFramePosition(buffer.frameLength)
        )
    }

    private func recordSystemAudioHeartbeat(capturedAt: Date) {
        snapshotState = PipelineHealthSnapshot(
            state: snapshotState.state,
            lastMicrophoneBufferAt: snapshotState.lastMicrophoneBufferAt,
            lastSystemAudioBufferAt: capturedAt,
            sampleRate: snapshotState.sampleRate,
            channelCount: snapshotState.channelCount,
            microphoneFrameCount: snapshotState.microphoneFrameCount
        )
    }
}

// MARK: - Internal chunked recorder

/// Minimal copy of the chunked-recording behavior `MicrophoneCaptureRecorder`
/// uses, rebuilt here so the pipeline doesn't have to reach across into
/// `MeetingCaptureEngine.swift`'s file-private types. Issue C consolidates
/// the duplicate when the old recorder is removed.
final class PipelineLiveChunkRecorder: @unchecked Sendable {
    private let noteID: UUID
    private let source: LiveTranscriptionChunkSource
    private let directoryURL: URL
    private let format: AVAudioFormat
    private let chunkDurationFrames: AVAudioFramePosition

    private(set) var completedChunks: [LiveTranscriptionChunk] = []
    private var currentChunkFile: AVAudioFile?
    private var currentChunkIndex = 0
    private var currentChunkStartedAt: Date?
    private var currentChunkFrameCount: AVAudioFramePosition = 0
    private var currentChunkFileURL: URL?

    init(
        noteID: UUID,
        source: LiveTranscriptionChunkSource,
        directoryURL: URL,
        format: AVAudioFormat,
        chunkDuration: TimeInterval
    ) {
        self.noteID = noteID
        self.source = source
        self.directoryURL = directoryURL
        self.format = format
        self.chunkDurationFrames = AVAudioFramePosition(max(format.sampleRate * max(chunkDuration, 1), 1))
    }

    func append(_ buffer: AVAudioPCMBuffer, capturedAt: Date) throws {
        if currentChunkFile == nil {
            try beginChunk(at: capturedAt)
        }
        guard let currentChunkFile else { return }
        try currentChunkFile.write(from: buffer)
        currentChunkFrameCount += AVAudioFramePosition(buffer.frameLength)
        if currentChunkFrameCount >= chunkDurationFrames {
            try finishOpenChunk(endedAt: capturedAt)
        }
    }

    func finishOpenChunk(endedAt: Date) throws {
        guard let startedAt = currentChunkStartedAt, let fileURL = currentChunkFileURL else {
            currentChunkFile = nil
            currentChunkStartedAt = nil
            currentChunkFileURL = nil
            currentChunkFrameCount = 0
            return
        }
        currentChunkFile = nil
        currentChunkStartedAt = nil
        currentChunkFileURL = nil
        completedChunks.append(
            LiveTranscriptionChunk(
                id: "\(source.rawValue)-\(currentChunkIndex - 1)",
                noteID: noteID,
                source: source,
                fileURL: fileURL,
                startedAt: startedAt,
                endedAt: endedAt
            )
        )
        currentChunkFrameCount = 0
    }

    private func beginChunk(at capturedAt: Date) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = directoryURL.appendingPathComponent(
            "\(source.rawValue)-\(String(format: "%04d", currentChunkIndex)).caf",
            isDirectory: false
        )
        currentChunkIndex += 1
        currentChunkFile = try AVAudioFile(
            forWriting: fileURL,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        currentChunkStartedAt = capturedAt
        currentChunkFileURL = fileURL
        currentChunkFrameCount = 0
    }
}
