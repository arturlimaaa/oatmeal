@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import OSLog

// MARK: - Public surface

/// Lifecycle state exposed by ``SystemAudioTapController`` via its
/// ``SystemAudioTapHealthSnapshot``.
///
/// The controller is one of:
///
/// - `.idle`         — never started, or fully torn down.
/// - `.starting`     — `start()` is in progress.
/// - `.running`      — the tap and aggregate device are live; buffers are
///                     flowing through ``SystemAudioTapController/audioBuffers``.
/// - `.stopping`     — `stop()` is in progress.
/// - `.failed`       — a previous lifecycle operation failed; the controller
///                     has cleaned up Core Audio resources but retains the
///                     terminal reason for the snapshot. `stop()` from this
///                     state is a no-op; `start()` is allowed and will
///                     reset the state to `.starting`.
public enum SystemAudioTapState: Equatable, Sendable {
    case idle
    case starting
    case running
    case stopping
    case failed(reason: String)
}

/// Read-only health snapshot mirroring the style of
/// ``CaptureRuntimeHealthSnapshot``. Captured atomically; safe to surface
/// from any concurrency domain.
public struct SystemAudioTapHealthSnapshot: Equatable, Sendable {
    public let state: SystemAudioTapState
    /// Wall-clock time of the most recently delivered audio buffer, or `nil`
    /// if no buffer has been emitted in the current lifecycle.
    public let lastBufferAt: Date?
    /// Bounded log of error strings encountered during the lifecycle. The
    /// most recent entry is last.
    public let errors: [String]

    public init(
        state: SystemAudioTapState,
        lastBufferAt: Date?,
        errors: [String]
    ) {
        self.state = state
        self.lastBufferAt = lastBufferAt
        self.errors = errors
    }
}

/// Errors surfaced by ``SystemAudioTapController``. The string forms
/// (`localizedDescription`) are the values appended to
/// ``SystemAudioTapHealthSnapshot/errors`` and stored as the reason on
/// ``SystemAudioTapState/failed(reason:)``.
public enum SystemAudioTapError: LocalizedError, Equatable {
    case tapDescriptionUnavailable
    case tapCreationFailed(OSStatus)
    case aggregateDeviceCreationFailed(OSStatus)
    case ioProcInstallationFailed(OSStatus)
    case ioProcStartFailed(OSStatus)
    case audioFormatUnavailable
    case unsupportedOS

    public var errorDescription: String? {
        switch self {
        case .tapDescriptionUnavailable:
            return "Could not construct a Core Audio tap description on this system."
        case let .tapCreationFailed(status):
            return "AudioHardwareCreateProcessTap failed (status \(status))."
        case let .aggregateDeviceCreationFailed(status):
            return "AudioHardwareCreateAggregateDevice failed (status \(status))."
        case let .ioProcInstallationFailed(status):
            return "AudioDeviceCreateIOProcIDWithBlock failed (status \(status))."
        case let .ioProcStartFailed(status):
            return "AudioDeviceStart failed (status \(status))."
        case .audioFormatUnavailable:
            return "Could not resolve the aggregate device's audio stream format."
        case .unsupportedOS:
            return "System audio process taps are not available on this OS."
        }
    }
}

/// Abstraction over the Core Audio hardware-tap C API. Production callers
/// never touch this; the default implementation in ``CoreAudioTapBackend``
/// invokes the real `AudioHardwareCreate*` functions. Tests inject a fake
/// implementation to exercise the controller's state-machine logic without
/// requiring real audio hardware.
public protocol SystemAudioTapBackend: Sendable {
    /// Create a process tap and aggregate device. Returns the IDs of both
    /// objects plus the audio stream format the aggregate device exposes.
    /// May throw ``SystemAudioTapError``. Implementations must clean up any
    /// partially-created resources before throwing.
    func createTapAndAggregateDevice(
        excludingProcessID pid: pid_t,
        aggregateUID: String
    ) throws -> SystemAudioTapResources

    /// Install an IO proc on the aggregate device that pumps PCM buffers
    /// into the supplied async-stream continuation. Returns an opaque
    /// handle that ``stopAndDestroy(_:)`` will tear down.
    func installIOProc(
        on resources: SystemAudioTapResources,
        bufferContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation,
        timestampSink: @escaping @Sendable (Date) -> Void,
        errorSink: @escaping @Sendable (String) -> Void
    ) throws -> SystemAudioTapRuntime

    /// Tear down the IO proc, aggregate device, and process tap, in that
    /// order. Safe to invoke on a runtime that never started; no-op if the
    /// argument is `nil`.
    func stopAndDestroy(_ runtime: SystemAudioTapRuntime?)

    /// Destroy a tap + aggregate device pair that had no IO proc installed.
    /// Used by ``SystemAudioTapController/start()`` to clean up after
    /// ``installIOProc(on:bufferContinuation:timestampSink:errorSink:)``
    /// throws.
    func destroyResources(_ resources: SystemAudioTapResources)

    /// Enumerate all aggregate devices whose UID begins with the supplied
    /// prefix and destroy each one. Used at process start to clear stale
    /// devices left over from previous crashes.
    func sweepStaleAggregateDevices(prefix: String, except keep: String?)
}

/// Bag of Core Audio object IDs handed back from
/// ``SystemAudioTapBackend/createTapAndAggregateDevice(excludingProcessID:aggregateUID:)``.
public struct SystemAudioTapResources: Sendable {
    public let tapID: AudioObjectID
    public let aggregateDeviceID: AudioObjectID
    public let aggregateUID: String
    public let streamFormat: AudioStreamBasicDescription

    public init(
        tapID: AudioObjectID,
        aggregateDeviceID: AudioObjectID,
        aggregateUID: String,
        streamFormat: AudioStreamBasicDescription
    ) {
        self.tapID = tapID
        self.aggregateDeviceID = aggregateDeviceID
        self.aggregateUID = aggregateUID
        self.streamFormat = streamFormat
    }
}

/// Opaque handle representing an installed IO proc that the backend can
/// later tear down. Real backends store the proc ID and aggregate ID;
/// fake backends carry whatever bookkeeping they need.
public final class SystemAudioTapRuntime: @unchecked Sendable {
    let resources: SystemAudioTapResources
    let teardown: @Sendable () -> Void

    init(resources: SystemAudioTapResources, teardown: @escaping @Sendable () -> Void) {
        self.resources = resources
        self.teardown = teardown
    }
}

/// Standard prefix used for Oatmeal-owned aggregate devices. Stable across
/// processes so a relaunch sweep can find leftover devices and destroy
/// them. Any UID beginning with this string is considered Oatmeal's
/// property and is fair game for cleanup.
public let SystemAudioTapAggregateUIDPrefix = "ai.oatmeal.system-audio-tap."

// MARK: - Controller

/// Wraps a Core Audio process tap and a private aggregate device, exposing
/// the captured PCM buffers as an `AsyncStream<AVAudioPCMBuffer>`. The
/// controller is the lowest-level building block of the new system-audio
/// path: it has no opinion about microphones, file output, or live
/// transcription chunks. Wiring into the recording engine happens upstream.
///
/// Concurrency model:
///
/// - `start()` and `stop()` are async actor methods; calling them
///   concurrently is safe and idempotent. The actor enforces serialized
///   state transitions.
/// - The IO proc is *not* actor-isolated — Core Audio invokes it on a
///   real-time thread. The proc never touches actor state directly; it
///   pushes into the async-stream continuation and into a small set of
///   `Sendable` sinks the actor wires up.
/// - `audioBuffers` and `healthSnapshot` are `nonisolated`, safe to read
///   from anywhere.
public actor SystemAudioTapController {

    // MARK: Public surface

    /// Async stream of PCM buffers captured from the system audio tap.
    /// Completes when the controller is stopped. Subscribers should accept
    /// that the stream may finish without an explicit error if the
    /// controller is torn down.
    public nonisolated var audioBuffers: AsyncStream<AVAudioPCMBuffer> {
        bufferStreamHolder.stream
    }

    /// Snapshot of the controller's lifecycle. Always reflects the most
    /// recent transition; lock-free read.
    public nonisolated var healthSnapshot: SystemAudioTapHealthSnapshot {
        snapshotStorage.read()
    }

    /// The stable UID we tagged our aggregate device with. `nil` when we
    /// do not currently own one.
    public nonisolated var currentAggregateUID: String? {
        aggregateUIDStorage.read()
    }

    // MARK: Configuration

    private let backend: SystemAudioTapBackend
    private let processIDProvider: @Sendable () -> pid_t
    private let aggregateUIDFactory: @Sendable () -> String
    private let logger: Logger

    // MARK: Internal state (actor-isolated)

    private var state: SystemAudioTapState = .idle
    private var runtime: SystemAudioTapRuntime?
    private var didSweepStaleDevices = false

    // MARK: Cross-domain state (lock-protected)

    private let bufferStreamHolder = AudioBufferStreamHolder()
    private let snapshotStorage = HealthSnapshotStorage()
    private let aggregateUIDStorage = AtomicOptionalString()

    // MARK: Init

    public init(
        backend: SystemAudioTapBackend = CoreAudioTapBackend(),
        processIDProvider: @escaping @Sendable () -> pid_t = { ProcessInfo.processInfo.processIdentifier },
        aggregateUIDFactory: @escaping @Sendable () -> String = {
            SystemAudioTapAggregateUIDPrefix + UUID().uuidString
        }
    ) {
        self.backend = backend
        self.processIDProvider = processIDProvider
        self.aggregateUIDFactory = aggregateUIDFactory
        logger = Logger(subsystem: "ai.oatmeal", category: "SystemAudioTapController")
        snapshotStorage.write(SystemAudioTapHealthSnapshot(state: .idle, lastBufferAt: nil, errors: []))
    }

    // MARK: Lifecycle

    /// Open the tap and aggregate device, install the IO proc, and begin
    /// emitting buffers on ``audioBuffers``.
    ///
    /// Idempotent: a second call while the controller is already
    /// `.starting` or `.running` is a silent no-op. A call after a prior
    /// failure resets the state and retries.
    ///
    /// On failure, all Core Audio resources created during the attempt are
    /// destroyed before the error is re-thrown, and the controller
    /// transitions to `.failed`.
    public func start() async throws {
        switch state {
        case .running, .starting:
            return
        case .stopping:
            // A stop is in flight; let it land before we reopen.
            return
        case .idle, .failed:
            break
        }

        transition(to: .starting)
        sweepStaleDevicesIfNeeded()

        let pid = processIDProvider()
        let aggregateUID = aggregateUIDFactory()

        let resources: SystemAudioTapResources
        do {
            resources = try backend.createTapAndAggregateDevice(
                excludingProcessID: pid,
                aggregateUID: aggregateUID
            )
        } catch {
            recordError(error)
            transition(to: .failed(reason: errorMessage(error)))
            throw error
        }

        aggregateUIDStorage.write(resources.aggregateUID)

        let installed: SystemAudioTapRuntime
        do {
            installed = try backend.installIOProc(
                on: resources,
                bufferContinuation: bufferStreamHolder.continuation,
                timestampSink: { [snapshotStorage] timestamp in
                    snapshotStorage.update { snapshot in
                        SystemAudioTapHealthSnapshot(
                            state: snapshot.state,
                            lastBufferAt: timestamp,
                            errors: snapshot.errors
                        )
                    }
                },
                errorSink: { [snapshotStorage] message in
                    snapshotStorage.update { snapshot in
                        SystemAudioTapHealthSnapshot(
                            state: snapshot.state,
                            lastBufferAt: snapshot.lastBufferAt,
                            errors: appendBoundedError(message, into: snapshot.errors)
                        )
                    }
                }
            )
        } catch {
            // Tear down the half-built tap before reporting failure.
            backend.destroyResources(resources)
            aggregateUIDStorage.write(nil)
            recordError(error)
            transition(to: .failed(reason: errorMessage(error)))
            throw error
        }

        runtime = installed
        transition(to: .running)
    }

    /// Tear down the IO proc, aggregate device, and process tap. Safe from
    /// any state. Subsequent `audioBuffers` iterations terminate cleanly.
    public func stop() async {
        switch state {
        case .idle, .stopping:
            return
        case .failed:
            // Already torn down by the failure path; nothing to do.
            transition(to: .idle)
            return
        case .starting, .running:
            break
        }

        transition(to: .stopping)
        let local = runtime
        runtime = nil
        backend.stopAndDestroy(local)
        aggregateUIDStorage.write(nil)
        transition(to: .idle)
    }

    /// Finish the buffer stream. Callers that want subscribers to see a
    /// terminal completion should invoke this after `stop()`. Kept as a
    /// distinct method so a controller can be reused across a stop/start
    /// cycle without dropping its long-lived consumer.
    public func finishBufferStream() {
        bufferStreamHolder.finish()
    }

    // MARK: State helpers

    private func transition(to newState: SystemAudioTapState) {
        state = newState
        snapshotStorage.update { snapshot in
            SystemAudioTapHealthSnapshot(
                state: newState,
                lastBufferAt: snapshot.lastBufferAt,
                errors: snapshot.errors
            )
        }
    }

    private func recordError(_ error: Error) {
        let message = errorMessage(error)
        logger.error("SystemAudioTapController error: \(message, privacy: .public)")
        snapshotStorage.update { snapshot in
            SystemAudioTapHealthSnapshot(
                state: snapshot.state,
                lastBufferAt: snapshot.lastBufferAt,
                errors: appendBoundedError(message, into: snapshot.errors)
            )
        }
    }

    private func sweepStaleDevicesIfNeeded() {
        guard !didSweepStaleDevices else { return }
        didSweepStaleDevices = true
        backend.sweepStaleAggregateDevices(
            prefix: SystemAudioTapAggregateUIDPrefix,
            except: aggregateUIDStorage.read()
        )
    }
}

private func errorMessage(_ error: Error) -> String {
    if let localized = error as? LocalizedError, let description = localized.errorDescription {
        return description
    }
    return error.localizedDescription
}

private func appendBoundedError(_ message: String, into existing: [String], cap: Int = 16) -> [String] {
    var copy = existing
    copy.append(message)
    if copy.count > cap {
        copy.removeFirst(copy.count - cap)
    }
    return copy
}

// MARK: - Cross-domain storage

/// Async-stream wrapper that exposes a single shared stream and a
/// continuation to push into. Owning code calls ``finish()`` when the
/// controller fully shuts down.
final class AudioBufferStreamHolder: @unchecked Sendable {
    let stream: AsyncStream<AVAudioPCMBuffer>
    let continuation: AsyncStream<AVAudioPCMBuffer>.Continuation

    init() {
        var capturedContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation!
        stream = AsyncStream<AVAudioPCMBuffer>(bufferingPolicy: .bufferingNewest(256)) { continuation in
            capturedContinuation = continuation
        }
        continuation = capturedContinuation
    }

    func finish() {
        continuation.finish()
    }
}

/// Lock-protected `SystemAudioTapHealthSnapshot` so the actor can publish
/// updates that ``SystemAudioTapController/healthSnapshot`` (a
/// `nonisolated` getter) can read without await.
final class HealthSnapshotStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot = SystemAudioTapHealthSnapshot(state: .idle, lastBufferAt: nil, errors: [])

    func read() -> SystemAudioTapHealthSnapshot {
        lock.withLock { snapshot }
    }

    func write(_ next: SystemAudioTapHealthSnapshot) {
        lock.withLock { snapshot = next }
    }

    func update(_ transform: (SystemAudioTapHealthSnapshot) -> SystemAudioTapHealthSnapshot) {
        lock.withLock { snapshot = transform(snapshot) }
    }
}

/// Atomic optional string used to surface the current aggregate UID
/// through a `nonisolated` getter on the controller.
final class AtomicOptionalString: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    func read() -> String? {
        lock.withLock { value }
    }

    func write(_ next: String?) {
        lock.withLock { value = next }
    }
}

// MARK: - CoreAudioTapBackend

/// Production backend that talks to the real Core Audio
/// `AudioHardwareCreate*` family. The implementation is intentionally
/// blunt — every Core Audio call is wrapped in an explicit OSStatus check
/// so failures fail loud rather than producing a silent recording.
public final class CoreAudioTapBackend: SystemAudioTapBackend, @unchecked Sendable {

    public init() {}

    public func createTapAndAggregateDevice(
        excludingProcessID pid: pid_t,
        aggregateUID: String
    ) throws -> SystemAudioTapResources {
        guard #available(macOS 14.2, *) else {
            throw SystemAudioTapError.unsupportedOS
        }

        // Translate our own PID to an AudioObjectID so we can place it on
        // the tap description's exclusion list.
        let selfObject = audioObjectID(forPID: pid)
        let excludedProcesses: [AudioObjectID] = selfObject.map { [$0] } ?? []

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: excludedProcesses)
        description.uuid = UUID()
        description.isPrivate = true
        description.isExclusive = false
        description.isMixdown = true
        description.name = "Oatmeal System Audio Tap"

        var tapID: AudioObjectID = kAudioObjectUnknown
        let tapStatus = AudioHardwareCreateProcessTap(description, &tapID)
        guard tapStatus == noErr, tapID != kAudioObjectUnknown else {
            throw SystemAudioTapError.tapCreationFailed(tapStatus)
        }

        // Build the aggregate-device dictionary. The aggregate device
        // bridges the tap into something an IO proc can pull from.
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "Oatmeal Aggregate (Tap)",
            kAudioAggregateDeviceUIDKey as String: aggregateUID,
            kAudioAggregateDeviceIsPrivateKey as String: 1,
            kAudioAggregateDeviceIsStackedKey as String: 0,
            kAudioAggregateDeviceTapAutoStartKey as String: 1,
            kAudioAggregateDeviceTapListKey as String: [
                [
                    kAudioSubTapUIDKey as String: description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey as String: 0
                ]
            ]
        ]

        var aggregateID: AudioObjectID = kAudioObjectUnknown
        let aggregateStatus = AudioHardwareCreateAggregateDevice(
            aggregateDescription as CFDictionary,
            &aggregateID
        )
        guard aggregateStatus == noErr, aggregateID != kAudioObjectUnknown else {
            // Roll back the tap before propagating the failure.
            AudioHardwareDestroyProcessTap(tapID)
            throw SystemAudioTapError.aggregateDeviceCreationFailed(aggregateStatus)
        }

        // Resolve the stream format the aggregate device exposes so that
        // the IO proc can wrap each buffer in a properly-shaped
        // `AVAudioPCMBuffer`.
        let streamFormat: AudioStreamBasicDescription
        do {
            streamFormat = try Self.streamFormat(for: aggregateID)
        } catch {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            AudioHardwareDestroyProcessTap(tapID)
            throw error
        }

        return SystemAudioTapResources(
            tapID: tapID,
            aggregateDeviceID: aggregateID,
            aggregateUID: aggregateUID,
            streamFormat: streamFormat
        )
    }

    public func installIOProc(
        on resources: SystemAudioTapResources,
        bufferContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation,
        timestampSink: @escaping @Sendable (Date) -> Void,
        errorSink: @escaping @Sendable (String) -> Void
    ) throws -> SystemAudioTapRuntime {
        var asbd = resources.streamFormat
        guard let avFormat = AVAudioFormat(streamDescription: &asbd) else {
            throw SystemAudioTapError.audioFormatUnavailable
        }

        let aggregateID = resources.aggregateDeviceID

        var procID: AudioDeviceIOProcID?
        let installStatus = AudioDeviceCreateIOProcIDWithBlock(
            &procID,
            aggregateID,
            nil
        ) { _, inputData, _, _, _ in
            // Real-time thread. Convert AudioBufferList -> AVAudioPCMBuffer
            // and push it into the stream. Drop, don't block, on overflow.
            guard let pcmBuffer = makePCMBuffer(from: inputData, format: avFormat) else {
                return
            }
            timestampSink(Date())
            _ = bufferContinuation.yield(pcmBuffer)
        }

        guard installStatus == noErr, let procID else {
            errorSink("AudioDeviceCreateIOProcIDWithBlock failed: \(installStatus)")
            throw SystemAudioTapError.ioProcInstallationFailed(installStatus)
        }

        let startStatus = AudioDeviceStart(aggregateID, procID)
        guard startStatus == noErr else {
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            errorSink("AudioDeviceStart failed: \(startStatus)")
            throw SystemAudioTapError.ioProcStartFailed(startStatus)
        }

        let tapID = resources.tapID
        let runtime = SystemAudioTapRuntime(resources: resources) {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            AudioHardwareDestroyAggregateDevice(aggregateID)
            AudioHardwareDestroyProcessTap(tapID)
        }
        return runtime
    }

    public func stopAndDestroy(_ runtime: SystemAudioTapRuntime?) {
        runtime?.teardown()
    }

    public func destroyResources(_ resources: SystemAudioTapResources) {
        AudioHardwareDestroyAggregateDevice(resources.aggregateDeviceID)
        AudioHardwareDestroyProcessTap(resources.tapID)
    }

    public func sweepStaleAggregateDevices(prefix: String, except keep: String?) {
        for deviceID in enumerateAllAudioDevices() {
            guard let uid = audioDeviceUID(deviceID), uid.hasPrefix(prefix) else {
                continue
            }
            if let keep, uid == keep {
                continue
            }
            AudioHardwareDestroyAggregateDevice(deviceID)
        }
    }

    // MARK: Helpers

    private static func streamFormat(for deviceID: AudioObjectID) throws -> AudioStreamBasicDescription {
        // Tap aggregate devices expose their audio on the input scope; the
        // global scope returns an empty format. Query the input scope and
        // fall back through input-stream virtual format if the device-level
        // query also comes up empty.
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var asbd = AudioStreamBasicDescription()
        var status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &asbd)
        if status == noErr, asbd.mSampleRate > 0, asbd.mChannelsPerFrame > 0 {
            return asbd
        }

        // Fallback: enumerate input streams and grab the first virtual format.
        var streamsAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamsSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &streamsAddress, 0, nil, &streamsSize) == noErr,
              streamsSize > 0
        else {
            throw SystemAudioTapError.audioFormatUnavailable
        }
        let streamCount = Int(streamsSize) / MemoryLayout<AudioObjectID>.size
        var streams = [AudioObjectID](repeating: 0, count: streamCount)
        let streamsStatus = streams.withUnsafeMutableBufferPointer { ptr in
            AudioObjectGetPropertyData(deviceID, &streamsAddress, 0, nil, &streamsSize, ptr.baseAddress!)
        }
        guard streamsStatus == noErr, let firstStream = streams.first, firstStream != 0 else {
            throw SystemAudioTapError.audioFormatUnavailable
        }

        var virtualFormatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioStreamPropertyVirtualFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        asbd = AudioStreamBasicDescription()
        status = AudioObjectGetPropertyData(firstStream, &virtualFormatAddress, 0, nil, &size, &asbd)
        guard status == noErr, asbd.mSampleRate > 0, asbd.mChannelsPerFrame > 0 else {
            throw SystemAudioTapError.audioFormatUnavailable
        }
        return asbd
    }
}

// MARK: - Free helpers

/// Translate a unix process identifier into an ``AudioObjectID``. Returns
/// `nil` if the system cannot resolve the PID — typically because the
/// process has already exited or because we lack the entitlement.
func audioObjectID(forPID pid: pid_t) -> AudioObjectID? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var inPID = pid
    var outObject: AudioObjectID = kAudioObjectUnknown
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        UInt32(MemoryLayout<pid_t>.size),
        &inPID,
        &size,
        &outObject
    )
    guard status == noErr, outObject != kAudioObjectUnknown else {
        return nil
    }
    return outObject
}

/// Enumerate every audio device the system knows about. Used by the
/// stale-aggregate sweep.
func enumerateAllAudioDevices() -> [AudioObjectID] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    let sizeStatus = AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &dataSize
    )
    guard sizeStatus == noErr, dataSize > 0 else {
        return []
    }

    let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
    var devices = [AudioObjectID](repeating: kAudioObjectUnknown, count: count)
    let getStatus = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &dataSize,
        &devices
    )
    guard getStatus == noErr else {
        return []
    }
    return devices
}

/// Read an audio device's UID property, or `nil` if it cannot be
/// retrieved (e.g., the device has gone away mid-sweep).
func audioDeviceUID(_ deviceID: AudioObjectID) -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceUID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var size = UInt32(MemoryLayout<CFString?>.size)
    var uid: CFString?
    let status = withUnsafeMutablePointer(to: &uid) { uidPointer -> OSStatus in
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, uidPointer)
    }
    guard status == noErr, let uidString = uid as String? else {
        return nil
    }
    return uidString
}

/// Convert a Core Audio `AudioBufferList` (real-time-thread input) into an
/// `AVAudioPCMBuffer` so consumers can stay in `AVAudioEngine`-land.
/// Returns `nil` on any structural mismatch — the IO proc treats this as
/// a dropped frame rather than crashing.
func makePCMBuffer(
    from inputData: UnsafePointer<AudioBufferList>,
    format: AVAudioFormat
) -> AVAudioPCMBuffer? {
    let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
    guard abl.count > 0, abl[0].mDataByteSize > 0 else {
        return nil
    }

    let bytesPerFrame = max(format.streamDescription.pointee.mBytesPerFrame, 1)
    let frameCount = AVAudioFrameCount(abl[0].mDataByteSize / bytesPerFrame)
    guard frameCount > 0 else { return nil }

    guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        return nil
    }
    pcmBuffer.frameLength = frameCount

    let destination = UnsafeMutableAudioBufferListPointer(pcmBuffer.mutableAudioBufferList)
    let copyChannels = min(destination.count, abl.count)
    for index in 0..<copyChannels {
        let source = abl[index]
        var dest = destination[index]
        let bytes = min(source.mDataByteSize, dest.mDataByteSize)
        if let src = source.mData, let dst = dest.mData, bytes > 0 {
            memcpy(dst, src, Int(bytes))
        }
        dest.mDataByteSize = source.mDataByteSize
        destination[index] = dest
    }
    return pcmBuffer
}
