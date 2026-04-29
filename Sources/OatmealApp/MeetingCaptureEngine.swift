import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

enum CaptureMode: String, Equatable, Sendable {
    case microphoneOnly
    case systemAudioAndMicrophone
}

struct CaptureInputDevice: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let isDefault: Bool
}

enum LiveTranscriptionChunkSource: String, Equatable, Sendable {
    case mixed
    case systemAudio
    case microphone

    var defaultSpeakerName: String? {
        switch self {
        case .mixed:
            nil
        case .systemAudio:
            "Meeting Audio"
        case .microphone:
            "Me"
        }
    }
}

struct ActiveCaptureSession: Equatable, Sendable {
    let noteID: UUID
    let startedAt: Date
    let fileURL: URL
    let mode: CaptureMode
}

struct LiveTranscriptionChunk: Equatable, Sendable, Identifiable {
    let id: String
    let noteID: UUID
    let source: LiveTranscriptionChunkSource
    let fileURL: URL
    let startedAt: Date
    let endedAt: Date
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

struct CaptureRuntimeHealthSnapshot: Equatable, Sendable {
    let noteID: UUID
    let microphoneLastActivityAt: Date?
    let systemAudioLastActivityAt: Date?
}

enum CaptureRuntimeEventKind: String, Equatable, Sendable {
    case degraded
    case recovered
    case failed
}

enum CaptureRuntimeEventSource: String, Equatable, Sendable {
    case microphone
    case systemAudio
    case capturePipeline
}

struct CaptureRuntimeEvent: Equatable, Sendable, Identifiable {
    let id: UUID
    let noteID: UUID
    let kind: CaptureRuntimeEventKind
    let source: CaptureRuntimeEventSource
    let message: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        noteID: UUID,
        kind: CaptureRuntimeEventKind,
        source: CaptureRuntimeEventSource,
        message: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.noteID = noteID
        self.kind = kind
        self.source = source
        self.message = message
        self.createdAt = createdAt
    }
}

enum CaptureEngineError: LocalizedError {
    case alreadyCapturing
    case noActiveCapture
    case missingInputDevice
    case noDisplayAvailable
    case unknownInputDevice
    case microphoneSwitchRequiresRestart(String)
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
        case .unknownInputDevice:
            "The selected microphone is no longer available."
        case let .microphoneSwitchRequiresRestart(deviceName):
            "Switching to \(deviceName) needs a fresh recording. Stop and restart capture to use that microphone."
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
    func availableMicrophones() -> [CaptureInputDevice]
    func activeMicrophoneID(for noteID: UUID) -> String?
    func switchMicrophone(to id: String, for noteID: UUID) async throws
    func liveTranscriptionChunks(for noteID: UUID) -> [LiveTranscriptionChunk]
    func runtimeHealthSnapshot(for noteID: UUID) -> CaptureRuntimeHealthSnapshot?
    func consumeRuntimeEvents(for noteID: UUID) -> [CaptureRuntimeEvent]
    func deleteRecording(for noteID: UUID) throws
}

@MainActor
final class LiveMeetingCaptureEngine: MeetingCaptureEngineServing {
    private let fileManager: FileManager
    private let persistence: AppPersistence
    private let liveChunkDuration: TimeInterval

    private var activeRecorder: (any CaptureRecorder)?

    init(
        fileManager: FileManager = .default,
        persistence: AppPersistence = .shared,
        liveChunkDuration: TimeInterval = 8
    ) {
        self.fileManager = fileManager
        self.persistence = persistence
        self.liveChunkDuration = liveChunkDuration
    }

    var activeSession: ActiveCaptureSession? {
        activeRecorder?.activeSession
    }

    func startCapture(for noteID: UUID, mode: CaptureMode) async throws -> ActiveCaptureSession {
        if let activeRecorder {
            if activeRecorder.hasOngoingCapture {
                throw CaptureEngineError.alreadyCapturing
            }

            self.activeRecorder = nil
        }

        try prepareRecordingDirectory()
        try clearExistingRecordingFiles(for: noteID)
        try prepareLiveChunkDirectory(for: noteID)

        let recorder: any CaptureRecorder
        switch mode {
        case .microphoneOnly:
            recorder = MicrophoneCaptureRecorder(
                noteID: noteID,
                fileURL: microphoneRecordingURL(for: noteID),
                liveChunkDirectoryURL: liveChunkDirectoryURL(for: noteID),
                liveChunkDuration: liveChunkDuration
            )
        case .systemAudioAndMicrophone:
            recorder = try await ScreenAudioCaptureRecorder(
                noteID: noteID,
                fileURL: systemAudioRecordingURL(for: noteID),
                liveChunkDirectoryURL: liveChunkDirectoryURL(for: noteID),
                liveChunkDuration: liveChunkDuration
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

        guard recorder.hasOngoingCapture else {
            activeRecorder = nil
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

    func availableMicrophones() -> [CaptureInputDevice] {
        let defaultMicrophoneID = AVCaptureDevice.default(for: .audio)?.uniqueID
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )

        let devices = discoverySession.devices.map { device in
            CaptureInputDevice(
                id: device.uniqueID,
                name: device.localizedName,
                isDefault: device.uniqueID == defaultMicrophoneID
            )
        }

        return devices.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault {
                return lhs.isDefault && !rhs.isDefault
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func activeMicrophoneID(for noteID: UUID) -> String? {
        guard let activeRecorder, activeRecorder.captureNoteID == noteID else {
            return nil
        }

        return activeRecorder.currentMicrophoneID
    }

    func switchMicrophone(to id: String, for noteID: UUID) async throws {
        guard let activeRecorder, activeRecorder.captureNoteID == noteID else {
            throw CaptureEngineError.noActiveCapture
        }

        try await activeRecorder.switchMicrophone(to: id)
    }

    func liveTranscriptionChunks(for noteID: UUID) -> [LiveTranscriptionChunk] {
        if activeRecorder?.captureNoteID == noteID, activeRecorder?.hasOngoingCapture == true {
            return activeRecorder?.completedLiveTranscriptionChunks ?? []
        }

        return persistedLiveTranscriptionChunks(for: noteID)
    }

    func runtimeHealthSnapshot(for noteID: UUID) -> CaptureRuntimeHealthSnapshot? {
        guard let activeRecorder, activeRecorder.captureNoteID == noteID else {
            return nil
        }

        return activeRecorder.runtimeHealthSnapshot
    }

    func consumeRuntimeEvents(for noteID: UUID) -> [CaptureRuntimeEvent] {
        guard let activeRecorder, activeRecorder.captureNoteID == noteID else {
            return []
        }

        let events = activeRecorder.consumeRuntimeEvents()
        if !activeRecorder.hasOngoingCapture {
            self.activeRecorder = nil
        }
        return events
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

    private func liveChunkDirectoryURL(for noteID: UUID) -> URL {
        recordingsDirectoryURL
            .appendingPathComponent("LiveChunks", isDirectory: true)
            .appendingPathComponent(noteID.uuidString, isDirectory: true)
    }

    private func prepareRecordingDirectory() throws {
        let directoryURL = recordingsDirectoryURL
        if fileManager.fileExists(atPath: directoryURL.path) {
            return
        }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func prepareLiveChunkDirectory(for noteID: UUID) throws {
        let directoryURL = liveChunkDirectoryURL(for: noteID)
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

        let liveChunkDirectoryURL = liveChunkDirectoryURL(for: noteID)
        if fileManager.fileExists(atPath: liveChunkDirectoryURL.path) {
            try fileManager.removeItem(at: liveChunkDirectoryURL)
        }
    }

    private func persistedLiveTranscriptionChunks(for noteID: UUID) -> [LiveTranscriptionChunk] {
        let directoryURL = liveChunkDirectoryURL(for: noteID)
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return []
        }

        let keys: [URLResourceKey] = [.isRegularFileKey, .creationDateKey, .contentModificationDateKey]
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.compactMap { url in
            guard url.pathExtension.lowercased() == "caf" else {
                return nil
            }

            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else {
                return nil
            }

            let chunkID = url.deletingPathExtension().lastPathComponent
            guard let separatorIndex = chunkID.lastIndex(of: "-") else {
                return nil
            }

            let sourceRawValue = String(chunkID[..<separatorIndex])
            guard let source = LiveTranscriptionChunkSource(rawValue: sourceRawValue) else {
                return nil
            }

            let startedAt = values.creationDate ?? values.contentModificationDate ?? .distantPast
            let endedAt = values.contentModificationDate ?? startedAt

            return LiveTranscriptionChunk(
                id: chunkID,
                noteID: noteID,
                source: source,
                fileURL: url,
                startedAt: startedAt,
                endedAt: endedAt
            )
        }
        .sorted { lhs, rhs in
            if lhs.startedAt == rhs.startedAt {
                return lhs.id < rhs.id
            }
            return lhs.startedAt < rhs.startedAt
        }
    }
}

private protocol CaptureRecorder: Sendable {
    var captureNoteID: UUID { get }
    var hasOngoingCapture: Bool { get }
    var activeSession: ActiveCaptureSession? { get }
    var completedLiveTranscriptionChunks: [LiveTranscriptionChunk] { get }
    var runtimeHealthSnapshot: CaptureRuntimeHealthSnapshot? { get }
    var currentMicrophoneID: String? { get }
    func consumeRuntimeEvents() -> [CaptureRuntimeEvent]
    func start() async throws -> ActiveCaptureSession
    func stop() async throws -> CaptureArtifact
    func switchMicrophone(to id: String) async throws
}

private final class MicrophoneCaptureRecorder: CaptureRecorder, @unchecked Sendable {
    private let noteID: UUID
    private let fileURL: URL
    private let liveChunkDirectoryURL: URL
    private let liveChunkDuration: TimeInterval
    private let notificationCenter: NotificationCenter
    private let lock = NSLock()
    private let recoveryQueue: DispatchQueue

    private var audioEngine: AVAudioEngine?
    private var recordingFile: AVAudioFile?
    private var activeSessionStorage: ActiveCaptureSession?
    private var liveChunkRecorder: RollingAudioChunkRecorder?
    private var observerTokens: [NSObjectProtocol] = []
    private var runtimeEventsStorage: [CaptureRuntimeEvent] = []
    private var isAttemptingRecovery = false
    private var lastInputSampleAt: Date?

    private var availableMicrophones: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    init(
        noteID: UUID,
        fileURL: URL,
        liveChunkDirectoryURL: URL,
        liveChunkDuration: TimeInterval,
        notificationCenter: NotificationCenter = .default
    ) {
        self.noteID = noteID
        self.fileURL = fileURL
        self.liveChunkDirectoryURL = liveChunkDirectoryURL
        self.liveChunkDuration = liveChunkDuration
        self.notificationCenter = notificationCenter
        recoveryQueue = DispatchQueue(label: "ai.oatmeal.capture.mic-recovery.\(noteID.uuidString)")
    }

    var captureNoteID: UUID {
        noteID
    }

    var hasOngoingCapture: Bool {
        lock.withLock { activeSessionStorage != nil }
    }

    var activeSession: ActiveCaptureSession? {
        activeSessionStorage
    }

    var completedLiveTranscriptionChunks: [LiveTranscriptionChunk] {
        lock.withLock {
            liveChunkRecorder?.completedChunks ?? []
        }
    }

    var runtimeHealthSnapshot: CaptureRuntimeHealthSnapshot? {
        lock.withLock {
            guard activeSessionStorage != nil else {
                return nil
            }

            return CaptureRuntimeHealthSnapshot(
                noteID: noteID,
                microphoneLastActivityAt: lastInputSampleAt,
                systemAudioLastActivityAt: nil
            )
        }
    }

    var currentMicrophoneID: String? {
        AVCaptureDevice.default(for: .audio)?.uniqueID
    }

    func consumeRuntimeEvents() -> [CaptureRuntimeEvent] {
        lock.withLock {
            let events = runtimeEventsStorage
            runtimeEventsStorage.removeAll()
            return events
        }
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

        let liveChunkRecorder = RollingAudioChunkRecorder(
            noteID: noteID,
            source: .microphone,
            directoryURL: liveChunkDirectoryURL,
            format: inputFormat,
            chunkDuration: liveChunkDuration
        )

        do {
            try installRecordingTap(
                on: engine,
                inputFormat: inputFormat,
                recordingFile: recordingFile,
                liveChunkRecorder: liveChunkRecorder
            )
        } catch {
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
        self.liveChunkRecorder = liveChunkRecorder
        lock.withLock {
            lastInputSampleAt = session.startedAt
        }
        startObservingDeviceChanges(for: engine)
        return session
    }

    func stop() async throws -> CaptureArtifact {
        guard let session = activeSessionStorage, let engine = audioEngine else {
            throw CaptureEngineError.noActiveCapture
        }

        stopObservingDeviceChanges()
        let inputNode = engine.inputNode
        inputNode.removeTap(onBus: 0)
        engine.stop()
        engine.reset()

        lock.withLock {
            do {
                try liveChunkRecorder?.finishOpenChunk(endedAt: Date())
            } catch {
                // Keep stop resilient if the sidecar live chunk cannot be finalized cleanly.
            }
        }

        audioEngine = nil
        recordingFile = nil
        activeSessionStorage = nil
        liveChunkRecorder = nil
        lock.withLock {
            lastInputSampleAt = nil
        }

        return CaptureArtifact(
            noteID: session.noteID,
            fileURL: session.fileURL,
            startedAt: session.startedAt,
            endedAt: Date(),
            mode: session.mode
        )
    }

    func switchMicrophone(to id: String) async throws {
        guard let targetDevice = availableMicrophones.first(where: { $0.uniqueID == id }) else {
            throw CaptureEngineError.unknownInputDevice
        }

        if targetDevice.uniqueID == currentMicrophoneID {
            return
        }

        enqueueRuntimeEvent(
            kind: .degraded,
            message: "Oatmeal cannot hot-switch microphone-only capture yet. Stop and restart recording to use \(targetDevice.localizedName)."
        )
        throw CaptureEngineError.microphoneSwitchRequiresRestart(targetDevice.localizedName)
    }

    private func installRecordingTap(
        on engine: AVAudioEngine,
        inputFormat: AVAudioFormat,
        recordingFile: AVAudioFile,
        liveChunkRecorder: RollingAudioChunkRecorder
    ) throws {
        let inputNode = engine.inputNode
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { buffer, _ in
            let capturedAt = Date()
            do {
                try recordingFile.write(from: buffer)
            } catch {
                // Prototype path: write failures surface as truncated output.
            }

            self.lock.withLock {
                self.lastInputSampleAt = capturedAt
                do {
                    try liveChunkRecorder.append(buffer, capturedAt: capturedAt)
                } catch {
                    // Keep the full recording path authoritative even if live chunking fails.
                }
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw error
        }
    }

    private func startObservingDeviceChanges(for engine: AVAudioEngine) {
        stopObservingDeviceChanges()

        let configurationChangeName = NSNotification.Name.AVAudioEngineConfigurationChange
        observerTokens.append(
            notificationCenter.addObserver(forName: configurationChangeName, object: engine, queue: nil) { [weak self] _ in
                self?.scheduleRecoveryAttempt(
                    degradedMessage: "Microphone configuration changed. Oatmeal is reconnecting the input automatically.",
                    recoveredMessage: "Microphone configuration changed. Oatmeal recovered the input automatically."
                )
            }
        )

        observerTokens.append(
            notificationCenter.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: nil) { [weak self] notification in
                guard let self, Self.notificationTargetsAudioDevice(notification) else {
                    return
                }

                self.scheduleRecoveryAttempt(
                    degradedMessage: "A microphone device disconnected. Oatmeal is trying to recover the input automatically.",
                    recoveredMessage: "A microphone device changed. Oatmeal recovered the input automatically."
                )
            }
        )

        observerTokens.append(
            notificationCenter.addObserver(forName: AVCaptureDevice.wasConnectedNotification, object: nil, queue: nil) { [weak self] notification in
                guard let self, Self.notificationTargetsAudioDevice(notification) else {
                    return
                }

                self.scheduleRecoveryAttempt(
                    degradedMessage: "A microphone device connected, but Oatmeal could not switch the live capture automatically. Stop and restart capture if your voice does not return.",
                    recoveredMessage: "A microphone device connected. Oatmeal recovered the input automatically."
                )
            }
        )
    }

    private func stopObservingDeviceChanges() {
        observerTokens.forEach(notificationCenter.removeObserver)
        observerTokens.removeAll()
    }

    private func scheduleRecoveryAttempt(
        degradedMessage: String,
        recoveredMessage: String
    ) {
        recoveryQueue.async { [weak self] in
            self?.attemptAutomaticRecovery(
                degradedMessage: degradedMessage,
                recoveredMessage: recoveredMessage
            )
        }
    }

    private func attemptAutomaticRecovery(
        degradedMessage: String,
        recoveredMessage: String
    ) {
        let shouldAttempt = lock.withLock { () -> Bool in
            guard activeSessionStorage != nil, !isAttemptingRecovery else {
                return false
            }
            isAttemptingRecovery = true
            return true
        }

        guard shouldAttempt else {
            return
        }

        defer {
            lock.withLock {
                isAttemptingRecovery = false
            }
        }

        guard let recordingFile, let liveChunkRecorder else {
            enqueueRuntimeEvent(kind: .degraded, message: degradedMessage)
            return
        }

        let newEngine = AVAudioEngine()
        let inputFormat = newEngine.inputNode.inputFormat(forBus: 0)
        guard inputFormat.channelCount > 0 else {
            enqueueRuntimeEvent(
                kind: .degraded,
                message: "No microphone input is currently available. Reconnect a microphone, then stop and restart capture if your voice does not return."
            )
            return
        }

        let recordingFormat = recordingFile.processingFormat
        guard Self.formatsAreCompatible(inputFormat, recordingFormat) else {
            enqueueRuntimeEvent(
                kind: .degraded,
                message: "The microphone changed to an incompatible input format. Oatmeal kept the recording safe, but stop and restart capture to continue with the new device."
            )
            return
        }

        do {
            try installRecordingTap(
                on: newEngine,
                inputFormat: inputFormat,
                recordingFile: recordingFile,
                liveChunkRecorder: liveChunkRecorder
            )
        } catch {
            enqueueRuntimeEvent(
                kind: .degraded,
                message: "\(degradedMessage) \(error.localizedDescription)"
            )
            return
        }

        let oldEngine = lock.withLock { () -> AVAudioEngine? in
            let engine = audioEngine
            audioEngine = newEngine
            return engine
        }

        oldEngine?.inputNode.removeTap(onBus: 0)
        oldEngine?.stop()
        oldEngine?.reset()
        startObservingDeviceChanges(for: newEngine)
        enqueueRuntimeEvent(kind: .recovered, message: recoveredMessage)
    }

    private func enqueueRuntimeEvent(kind: CaptureRuntimeEventKind, message: String, createdAt: Date = Date()) {
        lock.withLock {
            if let lastEvent = runtimeEventsStorage.last,
               lastEvent.kind == kind,
               lastEvent.message == message {
                return
            }

            runtimeEventsStorage.append(
                CaptureRuntimeEvent(
                    noteID: noteID,
                    kind: kind,
                    source: .microphone,
                    message: message,
                    createdAt: createdAt
                )
            )
        }
    }

    private static func formatsAreCompatible(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.sampleRate == rhs.sampleRate
            && lhs.channelCount == rhs.channelCount
            && lhs.commonFormat == rhs.commonFormat
            && lhs.isInterleaved == rhs.isInterleaved
    }

    private static func notificationTargetsAudioDevice(_ notification: Notification) -> Bool {
        guard let device = notification.object as? AVCaptureDevice else {
            return false
        }

        return device.hasMediaType(.audio)
    }
}

private final class RollingAudioChunkRecorder: @unchecked Sendable {
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

        guard let currentChunkFile else {
            return
        }

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

private final class ScreenAudioCaptureRecorder: NSObject, CaptureRecorder, @unchecked Sendable {
    private let noteID: UUID
    private let fileURL: URL
    private let liveChunkDirectoryURL: URL
    private let liveChunkDuration: TimeInterval
    private let notificationCenter: NotificationCenter
    private let lock = NSLock()
    private let sampleHandlerQueue: DispatchQueue
    private let healthMonitorInterval: TimeInterval = 2
    private let sourceHeartbeatTimeout: TimeInterval = 6

    private var stream: SCStream?
    private var streamConfiguration: SCStreamConfiguration?
    private var recordingOutput: SCRecordingOutput?
    private var activeSessionStorage: ActiveCaptureSession?
    private var pendingSession: ActiveCaptureSession?
    private var pendingArtifact: CaptureArtifact?
    private var startContinuation: CheckedContinuation<ActiveCaptureSession, Error>?
    private var stopContinuation: CheckedContinuation<CaptureArtifact, Error>?
    private var completedLiveChunksStorage: [LiveTranscriptionChunk] = []
    private var liveChunkRecorders: [LiveTranscriptionChunkSource: RollingAudioChunkRecorder] = [:]
    private var observerTokens: [NSObjectProtocol] = []
    private var runtimeEventsStorage: [CaptureRuntimeEvent] = []
    private var microphoneInputIsDegraded = false
    private var systemAudioInputIsDegraded = false
    private var lastMicrophoneSampleAt: Date?
    private var lastSystemAudioSampleAt: Date?
    private var healthMonitorTimer: DispatchSourceTimer?
    private var unexpectedFailureHandled = false
    private var selectedMicrophoneIDStorage: String?

    private var availableMicrophones: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    init(
        noteID: UUID,
        fileURL: URL,
        liveChunkDirectoryURL: URL,
        liveChunkDuration: TimeInterval,
        notificationCenter: NotificationCenter = .default
    ) async throws {
        self.noteID = noteID
        self.fileURL = fileURL
        self.liveChunkDirectoryURL = liveChunkDirectoryURL
        self.liveChunkDuration = liveChunkDuration
        self.notificationCenter = notificationCenter
        sampleHandlerQueue = DispatchQueue(label: "ai.oatmeal.capture.live-chunks.\(noteID.uuidString)")
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
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleHandlerQueue)
            if #available(macOS 15.0, *) {
                try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: sampleHandlerQueue)
            }
        } catch {
            throw CaptureEngineError.failedToPrepareRecording(error.localizedDescription)
        }

        self.stream = stream
        self.streamConfiguration = configuration
        self.recordingOutput = recordingOutput
    }

    var activeSession: ActiveCaptureSession? {
        lock.withLock { activeSessionStorage }
    }

    var captureNoteID: UUID {
        noteID
    }

    var hasOngoingCapture: Bool {
        lock.withLock {
            activeSessionStorage != nil
                || pendingSession != nil
                || pendingArtifact != nil
                || startContinuation != nil
                || stopContinuation != nil
        }
    }

    var completedLiveTranscriptionChunks: [LiveTranscriptionChunk] {
        lock.withLock { completedLiveChunksStorage }
    }

    var runtimeHealthSnapshot: CaptureRuntimeHealthSnapshot? {
        lock.withLock {
            guard activeSessionStorage != nil || pendingSession != nil else {
                return nil
            }

            return CaptureRuntimeHealthSnapshot(
                noteID: noteID,
                microphoneLastActivityAt: lastMicrophoneSampleAt,
                systemAudioLastActivityAt: lastSystemAudioSampleAt
            )
        }
    }

    var currentMicrophoneID: String? {
        lock.withLock {
            selectedMicrophoneIDStorage ?? AVCaptureDevice.default(for: .audio)?.uniqueID
        }
    }

    func consumeRuntimeEvents() -> [CaptureRuntimeEvent] {
        lock.withLock {
            let events = runtimeEventsStorage
            runtimeEventsStorage.removeAll()
            return events
        }
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
            unexpectedFailureHandled = false
            lastMicrophoneSampleAt = session.startedAt
            lastSystemAudioSampleAt = session.startedAt
            selectedMicrophoneIDStorage = streamConfiguration?.microphoneCaptureDeviceID ?? AVCaptureDevice.default(for: .audio)?.uniqueID
        }
        startObservingDeviceChanges()
        startHealthMonitor()

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

        stopObservingDeviceChanges()
        stopHealthMonitor()
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

    func switchMicrophone(to id: String) async throws {
        guard let targetDevice = availableMicrophones.first(where: { $0.uniqueID == id }) else {
            throw CaptureEngineError.unknownInputDevice
        }

        if targetDevice.uniqueID == currentMicrophoneID {
            return
        }

        guard let stream, let streamConfiguration else {
            throw CaptureEngineError.noActiveCapture
        }

        if #available(macOS 15.0, *) {
            streamConfiguration.microphoneCaptureDeviceID = targetDevice.uniqueID
            try await stream.updateConfiguration(streamConfiguration)
            lock.withLock {
                selectedMicrophoneIDStorage = targetDevice.uniqueID
                lastMicrophoneSampleAt = Date()
                enqueueRuntimeEventLocked(
                    kind: .recovered,
                    source: .microphone,
                    message: "Oatmeal switched the microphone to \(targetDevice.localizedName).",
                    createdAt: Date()
                )
            }
        } else {
            throw CaptureEngineError.microphoneSwitchRequiresRestart(targetDevice.localizedName)
        }
    }

    private func appendLiveSampleBuffer(_ sampleBuffer: CMSampleBuffer, source: LiveTranscriptionChunkSource) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return
        }

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else {
            return
        }

        let audioFormat = AVAudioFormat(cmAudioFormatDescription: formatDescription)
        guard let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: audioFormat,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else {
            return
        }

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: pcmBuffer.mutableAudioBufferList
        )
        guard status == noErr else {
            return
        }

        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)
        let capturedAt = Date()

        lock.withLock {
            switch source {
            case .microphone:
                lastMicrophoneSampleAt = capturedAt
                if microphoneInputIsDegraded {
                    microphoneInputIsDegraded = false
                    enqueueRuntimeEventLocked(
                        kind: .recovered,
                        source: .microphone,
                        message: "Microphone input recovered. Oatmeal resumed live capture automatically.",
                        createdAt: capturedAt
                    )
                }
            case .systemAudio:
                lastSystemAudioSampleAt = capturedAt
                if systemAudioInputIsDegraded {
                    systemAudioInputIsDegraded = false
                    enqueueRuntimeEventLocked(
                        kind: .recovered,
                        source: .systemAudio,
                        message: "System audio recovered. Oatmeal resumed the meeting feed automatically.",
                        createdAt: capturedAt
                    )
                }
            case .mixed:
                break
            }

            let recorder = recorderForLiveSource(source, format: audioFormat)
            do {
                try recorder.append(pcmBuffer, capturedAt: capturedAt)
                refreshCompletedLiveChunksStorage()
            } catch {
                // The full recording artifact remains authoritative even if live chunking drops a sample.
            }
        }
    }

    private func recorderForLiveSource(
        _ source: LiveTranscriptionChunkSource,
        format: AVAudioFormat
    ) -> RollingAudioChunkRecorder {
        if let recorder = liveChunkRecorders[source] {
            return recorder
        }

        let recorder = RollingAudioChunkRecorder(
            noteID: noteID,
            source: source,
            directoryURL: liveChunkDirectoryURL,
            format: format,
            chunkDuration: liveChunkDuration
        )
        liveChunkRecorders[source] = recorder
        return recorder
    }

    private func finishOpenLiveChunks(endedAt: Date) {
        lock.withLock {
            for recorder in liveChunkRecorders.values {
                do {
                    try recorder.finishOpenChunk(endedAt: endedAt)
                } catch {
                    // Preserve the primary recording even if one live chunk cannot be finalized.
                }
            }
            refreshCompletedLiveChunksStorage()
        }
    }

    private func refreshCompletedLiveChunksStorage() {
        completedLiveChunksStorage = liveChunkRecorders.values
            .flatMap(\.completedChunks)
            .sorted(by: { lhs, rhs in
                if lhs.startedAt == rhs.startedAt {
                    return lhs.id < rhs.id
                }
                return lhs.startedAt < rhs.startedAt
            })
    }

    private func startObservingDeviceChanges() {
        stopObservingDeviceChanges()

        observerTokens.append(
            notificationCenter.addObserver(
                forName: AVCaptureDevice.wasDisconnectedNotification,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                guard let self, Self.notificationTargetsAudioDevice(notification) else {
                    return
                }

                self.enqueueMicrophoneDegradedEvent(
                    "A microphone device disconnected. Oatmeal is still saving the meeting audio locally and will recover your mic automatically if it comes back."
                )
            }
        )
    }

    private func stopObservingDeviceChanges() {
        observerTokens.forEach(notificationCenter.removeObserver)
        observerTokens.removeAll()
    }

    private func startHealthMonitor() {
        stopHealthMonitor()

        let timer = DispatchSource.makeTimerSource(queue: sampleHandlerQueue)
        timer.schedule(deadline: .now() + healthMonitorInterval, repeating: healthMonitorInterval)
        timer.setEventHandler { [weak self] in
            self?.evaluateSourceHealthHeartbeat()
        }
        healthMonitorTimer = timer
        timer.resume()
    }

    private func stopHealthMonitor() {
        healthMonitorTimer?.cancel()
        healthMonitorTimer = nil
    }

    private func enqueueMicrophoneDegradedEvent(_ message: String) {
        lock.withLock {
            guard !microphoneInputIsDegraded else {
                enqueueRuntimeEventLocked(kind: .degraded, source: .microphone, message: message)
                return
            }

            microphoneInputIsDegraded = true
            enqueueRuntimeEventLocked(
                kind: .degraded,
                source: .microphone,
                message: message
            )
        }
    }

    private func enqueueSystemAudioDegradedEvent(_ message: String) {
        lock.withLock {
            guard !systemAudioInputIsDegraded else {
                enqueueRuntimeEventLocked(kind: .degraded, source: .systemAudio, message: message)
                return
            }

            systemAudioInputIsDegraded = true
            enqueueRuntimeEventLocked(
                kind: .degraded,
                source: .systemAudio,
                message: message
            )
        }
    }

    private func evaluateSourceHealthHeartbeat(referenceDate: Date = Date()) {
        lock.withLock {
            guard activeSessionStorage != nil else {
                return
            }

            if let lastMicrophoneSampleAt,
               referenceDate.timeIntervalSince(lastMicrophoneSampleAt) >= sourceHeartbeatTimeout,
               !microphoneInputIsDegraded {
                microphoneInputIsDegraded = true
                enqueueRuntimeEventLocked(
                    kind: .degraded,
                    source: .microphone,
                    message: "Microphone samples have paused. Oatmeal is still saving the meeting audio locally and will recover your voice feed when it resumes.",
                    createdAt: referenceDate
                )
            }

            if let lastSystemAudioSampleAt,
               referenceDate.timeIntervalSince(lastSystemAudioSampleAt) >= sourceHeartbeatTimeout,
               !systemAudioInputIsDegraded {
                systemAudioInputIsDegraded = true
                enqueueRuntimeEventLocked(
                    kind: .degraded,
                    source: .systemAudio,
                    message: "System audio samples have paused. Oatmeal is still keeping the local recording safe and will recover the meeting feed when it resumes.",
                    createdAt: referenceDate
                )
            }
        }
    }

    private func enqueueRuntimeEventLocked(
        kind: CaptureRuntimeEventKind,
        source: CaptureRuntimeEventSource,
        message: String,
        createdAt: Date = Date()
    ) {
        if let lastEvent = runtimeEventsStorage.last,
           lastEvent.kind == kind,
           lastEvent.source == source,
           lastEvent.message == message {
            return
        }

        runtimeEventsStorage.append(
            CaptureRuntimeEvent(
                noteID: noteID,
                kind: kind,
                source: source,
                message: message,
                createdAt: createdAt
            )
        )
    }

    private func handleUnexpectedCaptureFailure(message: String, endedAt: Date = Date()) {
        let shouldHandle = lock.withLock { () -> Bool in
            let isUnexpected = activeSessionStorage != nil && startContinuation == nil && stopContinuation == nil
            guard isUnexpected, !unexpectedFailureHandled else {
                return false
            }

            unexpectedFailureHandled = true
            return true
        }

        guard shouldHandle else {
            return
        }

        stopObservingDeviceChanges()
        stopHealthMonitor()
        finishOpenLiveChunks(endedAt: endedAt)

        lock.withLock {
            pendingSession = nil
            pendingArtifact = nil
            activeSessionStorage = nil
            stream = nil
            streamConfiguration = nil
            recordingOutput = nil
            liveChunkRecorders = [:]
            microphoneInputIsDegraded = false
            systemAudioInputIsDegraded = false
            selectedMicrophoneIDStorage = nil
            enqueueRuntimeEventLocked(
                kind: .failed,
                source: .capturePipeline,
                message: message,
                createdAt: endedAt
            )
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
                unexpectedFailureHandled = false
            }
            continuation.resume(returning: session)
        case let .failure(error):
            stopObservingDeviceChanges()
            stopHealthMonitor()
            lock.withLock {
                pendingSession = nil
                activeSessionStorage = nil
                unexpectedFailureHandled = false
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
            stopObservingDeviceChanges()
            stopHealthMonitor()
            lock.withLock {
                pendingArtifact = nil
                activeSessionStorage = nil
                stream = nil
                streamConfiguration = nil
                recordingOutput = nil
                completedLiveChunksStorage = []
                liveChunkRecorders = [:]
                runtimeEventsStorage = []
                microphoneInputIsDegraded = false
                systemAudioInputIsDegraded = false
                lastMicrophoneSampleAt = nil
                lastSystemAudioSampleAt = nil
                unexpectedFailureHandled = false
                selectedMicrophoneIDStorage = nil
            }
            continuation.resume(returning: artifact)
        case let .failure(error):
            stopObservingDeviceChanges()
            stopHealthMonitor()
            lock.withLock {
                pendingArtifact = nil
                activeSessionStorage = nil
                stream = nil
                streamConfiguration = nil
                recordingOutput = nil
                completedLiveChunksStorage = []
                liveChunkRecorders = [:]
                runtimeEventsStorage = []
                microphoneInputIsDegraded = false
                systemAudioInputIsDegraded = false
                lastMicrophoneSampleAt = nil
                lastSystemAudioSampleAt = nil
                unexpectedFailureHandled = false
                selectedMicrophoneIDStorage = nil
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

    private static func notificationTargetsAudioDevice(_ notification: Notification) -> Bool {
        guard let device = notification.object as? AVCaptureDevice else {
            return false
        }

        return device.hasMediaType(.audio)
    }
}

extension ScreenAudioCaptureRecorder: SCRecordingOutputDelegate, SCStreamDelegate, SCStreamOutput {
    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        let session = lock.withLock { pendingSession }
        guard let session else { return }
        Task { @MainActor [weak self] in
            self?.resumeStart(with: .success(session))
        }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        let shouldResumeStart = lock.withLock { startContinuation != nil }
        let shouldResumeStop = lock.withLock { stopContinuation != nil }
        Task { @MainActor [weak self] in
            if shouldResumeStart {
                self?.resumeStart(with: .failure(error))
            } else if shouldResumeStop {
                self?.resumeStop(with: .failure(error))
            } else {
                self?.handleUnexpectedCaptureFailure(
                    message: "Screen and system audio capture stopped unexpectedly. Oatmeal kept the partial local recording artifacts that were already saved, and will salvage the note in the background."
                )
            }
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        let artifact = lock.withLock { pendingArtifact }
        guard let artifact else { return }
        finishOpenLiveChunks(endedAt: artifact.endedAt)
        Task { @MainActor [weak self] in
            self?.resumeStop(with: .success(artifact))
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        let shouldResumeStart = lock.withLock { startContinuation != nil }
        let shouldResumeStop = lock.withLock { stopContinuation != nil }
        Task { @MainActor [weak self] in
            if shouldResumeStart {
                self?.resumeStart(with: .failure(error))
            } else if shouldResumeStop {
                self?.resumeStop(with: .failure(error))
            } else {
                self?.handleUnexpectedCaptureFailure(
                    message: "Live screen and system audio capture was interrupted. Oatmeal kept the locally saved portion of the recording and will finish whatever it can in the background."
                )
            }
        }
    }

    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        switch type {
        case .audio:
            appendLiveSampleBuffer(sampleBuffer, source: .systemAudio)
        case .microphone:
            appendLiveSampleBuffer(sampleBuffer, source: .microphone)
        default:
            break
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
