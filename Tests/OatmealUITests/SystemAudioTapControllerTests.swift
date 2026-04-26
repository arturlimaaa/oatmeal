@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
@testable import OatmealUI
import XCTest

// MARK: - Tier B: state-machine unit tests

/// Exercises ``SystemAudioTapController`` state transitions against a fake
/// ``SystemAudioTapBackend`` so the assertions don't rely on real audio
/// hardware. Runs everywhere — these are pure logic tests.
final class SystemAudioTapControllerStateMachineTests: XCTestCase {

    func testStartFromIdleEntersRunning() async throws {
        let backend = FakeBackend()
        let controller = SystemAudioTapController(
            backend: backend,
            processIDProvider: { 4242 },
            aggregateUIDFactory: { SystemAudioTapAggregateUIDPrefix + "test-1" }
        )

        XCTAssertEqual(controller.healthSnapshot.state, .idle)
        try await controller.start()
        XCTAssertEqual(controller.healthSnapshot.state, .running)
        XCTAssertEqual(backend.startCalls, 1)
        XCTAssertEqual(backend.installCalls, 1)
        XCTAssertEqual(controller.currentAggregateUID, SystemAudioTapAggregateUIDPrefix + "test-1")
    }

    func testDoubleStartIsIdempotent() async throws {
        let backend = FakeBackend()
        let controller = SystemAudioTapController(
            backend: backend,
            processIDProvider: { 4242 },
            aggregateUIDFactory: { SystemAudioTapAggregateUIDPrefix + "test-2" }
        )

        try await controller.start()
        try await controller.start()
        XCTAssertEqual(controller.healthSnapshot.state, .running)
        XCTAssertEqual(backend.startCalls, 1, "Second start() must not create another tap.")
        XCTAssertEqual(backend.installCalls, 1)
    }

    func testStopFromIdleIsSafeNoOp() async throws {
        let backend = FakeBackend()
        let controller = SystemAudioTapController(
            backend: backend,
            processIDProvider: { 4242 },
            aggregateUIDFactory: { SystemAudioTapAggregateUIDPrefix + "test-3" }
        )

        await controller.stop()
        XCTAssertEqual(controller.healthSnapshot.state, .idle)
        XCTAssertEqual(backend.teardownCalls, 0)
    }

    func testStopAfterRunningTearsDownAndReturnsToIdle() async throws {
        let backend = FakeBackend()
        let controller = SystemAudioTapController(
            backend: backend,
            processIDProvider: { 4242 },
            aggregateUIDFactory: { SystemAudioTapAggregateUIDPrefix + "test-4" }
        )

        try await controller.start()
        await controller.stop()

        XCTAssertEqual(controller.healthSnapshot.state, .idle)
        XCTAssertEqual(backend.teardownCalls, 1)
        XCTAssertNil(controller.currentAggregateUID)
    }

    func testStartFailureCleansUpAndTransitionsToFailed() async throws {
        let backend = FakeBackend()
        backend.shouldFailCreate = true
        let controller = SystemAudioTapController(
            backend: backend,
            processIDProvider: { 4242 },
            aggregateUIDFactory: { SystemAudioTapAggregateUIDPrefix + "test-5" }
        )

        await XCTAssertThrowsErrorAsync(try await controller.start())
        switch controller.healthSnapshot.state {
        case .failed:
            break
        default:
            XCTFail("Expected .failed; got \(controller.healthSnapshot.state)")
        }
        XCTAssertEqual(backend.teardownCalls, 0, "No runtime was installed; nothing to tear down.")
        XCTAssertNil(controller.currentAggregateUID)
        XCTAssertFalse(controller.healthSnapshot.errors.isEmpty)
    }

    func testStartFailureAtIOProcDestroysAggregateBeforeReturning() async throws {
        let backend = FakeBackend()
        backend.shouldFailInstall = true
        let controller = SystemAudioTapController(
            backend: backend,
            processIDProvider: { 4242 },
            aggregateUIDFactory: { SystemAudioTapAggregateUIDPrefix + "test-6" }
        )

        await XCTAssertThrowsErrorAsync(try await controller.start())
        XCTAssertEqual(backend.teardownCalls, 1, "Half-built tap must be destroyed before failure returns.")
        switch controller.healthSnapshot.state {
        case .failed:
            break
        default:
            XCTFail("Expected .failed; got \(controller.healthSnapshot.state)")
        }
        XCTAssertNil(controller.currentAggregateUID)
    }

    func testStopAfterFailureIsSafeNoOp() async throws {
        let backend = FakeBackend()
        backend.shouldFailCreate = true
        let controller = SystemAudioTapController(
            backend: backend,
            processIDProvider: { 4242 },
            aggregateUIDFactory: { SystemAudioTapAggregateUIDPrefix + "test-7" }
        )

        await XCTAssertThrowsErrorAsync(try await controller.start())
        await controller.stop()
        XCTAssertEqual(controller.healthSnapshot.state, .idle)
    }

    func testStartAfterFailureRetries() async throws {
        let backend = FakeBackend()
        backend.shouldFailCreate = true
        let controller = SystemAudioTapController(
            backend: backend,
            processIDProvider: { 4242 },
            aggregateUIDFactory: { SystemAudioTapAggregateUIDPrefix + "test-8" }
        )

        await XCTAssertThrowsErrorAsync(try await controller.start())
        backend.shouldFailCreate = false
        try await controller.start()
        XCTAssertEqual(controller.healthSnapshot.state, .running)
        XCTAssertEqual(backend.startCalls, 2, "Retry must re-invoke the backend.")
    }

    func testFirstStartPerformsStaleSweepWithRetainedNewUID() async throws {
        let backend = FakeBackend()
        let controller = SystemAudioTapController(
            backend: backend,
            processIDProvider: { 4242 },
            aggregateUIDFactory: { SystemAudioTapAggregateUIDPrefix + "test-9" }
        )

        try await controller.start()
        XCTAssertEqual(backend.sweepCalls.count, 1)
        XCTAssertEqual(backend.sweepCalls.first?.prefix, SystemAudioTapAggregateUIDPrefix)
        // The very first sweep happens before the new UID is published, so
        // `keep` is nil. That is intentional: the first lifecycle has
        // nothing to preserve.
        XCTAssertNil(backend.sweepCalls.first?.keep)
    }

    func testSweepRunsOnlyOncePerControllerLifetime() async throws {
        let backend = FakeBackend()
        let controller = SystemAudioTapController(
            backend: backend,
            processIDProvider: { 4242 },
            aggregateUIDFactory: { SystemAudioTapAggregateUIDPrefix + "test-10" }
        )

        try await controller.start()
        await controller.stop()
        try await controller.start()
        XCTAssertEqual(backend.sweepCalls.count, 1, "Sweep is once-per-lifetime, not per-start.")
    }

    func testHealthSnapshotPublishesLastBufferTimestamp() async throws {
        let backend = FakeBackend()
        let controller = SystemAudioTapController(
            backend: backend,
            processIDProvider: { 4242 },
            aggregateUIDFactory: { SystemAudioTapAggregateUIDPrefix + "test-11" }
        )

        try await controller.start()
        let beforeTimestamp = Date()
        // FakeBackend captures the timestampSink and lets the test fire
        // synthetic buffers through it.
        backend.fireSyntheticBuffer()

        // The snapshot is a lock-protected field; allow a tick for the
        // health-snapshot update to land.
        try await Task.sleep(nanoseconds: 50_000_000)
        let snapshot = controller.healthSnapshot
        XCTAssertNotNil(snapshot.lastBufferAt)
        XCTAssertGreaterThanOrEqual(snapshot.lastBufferAt!.timeIntervalSince(beforeTimestamp), 0)
    }

    func testFinishBufferStreamCompletesConsumer() async throws {
        let backend = FakeBackend()
        let controller = SystemAudioTapController(
            backend: backend,
            processIDProvider: { 4242 },
            aggregateUIDFactory: { SystemAudioTapAggregateUIDPrefix + "test-12" }
        )
        let stream = controller.audioBuffers
        try await controller.start()
        await controller.stop()
        await controller.finishBufferStream()

        let buffersTask = Task {
            var count = 0
            for await _ in stream {
                count += 1
            }
            return count
        }
        // Even if no buffers were emitted, the iteration must terminate.
        let count = await buffersTask.value
        XCTAssertEqual(count, 0)
    }
}

// MARK: - Tier C: real-recording integration tests

/// Real-hardware tests that drive ``SystemAudioTapController`` against
/// Core Audio. Skipped by default; run by setting
/// `OATMEAL_TAP_REAL_RECORDING=1` so they don't fire on CI or on machines
/// without a default audio output.
final class SystemAudioTapControllerRealRecordingTests: XCTestCase {

    private static var realRecordingEnabled: Bool {
        ProcessInfo.processInfo.environment["OATMEAL_TAP_REAL_RECORDING"] == "1"
    }

    private static var hasDefaultOutput: Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioObjectID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        return status == noErr && deviceID != kAudioObjectUnknown
    }

    func testRecordsSystemAudio() async throws {
        try Self.skipIfRealRecordingUnavailable()

        // The controller defaults to excluding its own PID. For this test
        // we need the tap to *include* the test process so the SineWavePlayer
        // tone actually reaches the capture; override the provider with a
        // non-existent PID so nothing is excluded in practice.
        let controller = SystemAudioTapController(
            processIDProvider: { 1 }
        )
        try await controller.start()
        defer {
            Task { await controller.stop() }
        }

        let collector = SystemAudioBufferCollector(stream: controller.audioBuffers)
        let collectorTask = Task { await collector.collect(for: 2.0) }

        // Play a 2-second test tone through the default output device.
        let player = SineWavePlayer(frequency: 440, durationSeconds: 2.0)
        try player.play()
        await collectorTask.value
        await controller.stop()
        await controller.finishBufferStream()
        player.stop()

        let buffers = await collector.collected
        XCTAssertFalse(buffers.isEmpty, "Tap produced no buffers during the test tone.")
        let rms = aggregateRMS(buffers)
        XCTAssertGreaterThan(rms, 0.001, "Expected captured PCM to carry audible energy; RMS=\(rms)")
    }

    func testRecoversFromOutputDeviceChange() async throws {
        try Self.skipIfRealRecordingUnavailable()
        // Programmatic default-output-device switching requires invoking
        // `AudioObjectSetPropertyData` against
        // `kAudioHardwarePropertyDefaultOutputDevice` with another live
        // output device, which the test environment can't reliably
        // produce on every machine. Document and skip; the manual
        // version of this test (developer-driven mid-recording switch)
        // belongs to local QA.
        throw XCTSkip("Default-output-device switch must be triggered by the developer; skipped in automation.")
    }

    func testExcludesOwnProcess() async throws {
        try Self.skipIfRealRecordingUnavailable()

        let controller = SystemAudioTapController()
        try await controller.start()
        defer {
            Task { await controller.stop() }
        }

        let collector = SystemAudioBufferCollector(stream: controller.audioBuffers)
        let collectorTask = Task { await collector.collect(for: 2.0) }

        let player = SineWavePlayer(frequency: 660, durationSeconds: 2.0)
        try player.play()
        await collectorTask.value
        await controller.stop()
        await controller.finishBufferStream()
        player.stop()

        let buffers = await collector.collected
        let rms = aggregateRMS(buffers)
        XCTAssertLessThan(
            rms,
            0.01,
            "Tap captured audio originating in the test process; RMS=\(rms). The exclusion list is leaking."
        )
    }

    private static func skipIfRealRecordingUnavailable() throws {
        guard realRecordingEnabled else {
            throw XCTSkip("Set OATMEAL_TAP_REAL_RECORDING=1 to run the system-audio tap real-recording tests.")
        }
        guard hasDefaultOutput else {
            throw XCTSkip("No default audio output device available on this Mac.")
        }
    }
}

// MARK: - Tier B fakes

/// In-memory ``SystemAudioTapBackend`` that records every interaction so
/// state-machine tests can assert against call counts. The fake never
/// touches Core Audio; it builds a bogus ``AudioStreamBasicDescription``
/// for the runtime structure and exposes a ``fireSyntheticBuffer()``
/// helper so tests can poke the timestampSink without involving real
/// hardware.
final class FakeBackend: SystemAudioTapBackend, @unchecked Sendable {
    struct SweepCall: Equatable {
        let prefix: String
        let keep: String?
    }

    var startCalls = 0
    var installCalls = 0
    var teardownCalls = 0
    var sweepCalls: [SweepCall] = []
    var shouldFailCreate = false
    var shouldFailInstall = false
    var capturedTimestampSink: (@Sendable (Date) -> Void)?
    var capturedErrorSink: (@Sendable (String) -> Void)?

    func createTapAndAggregateDevice(
        excludingProcessID pid: pid_t,
        aggregateUID: String
    ) throws -> SystemAudioTapResources {
        startCalls += 1
        if shouldFailCreate {
            throw SystemAudioTapError.tapCreationFailed(-1)
        }
        return SystemAudioTapResources(
            tapID: 42,
            aggregateDeviceID: 99,
            aggregateUID: aggregateUID,
            streamFormat: AudioStreamBasicDescription(
                mSampleRate: 48_000,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                mBytesPerPacket: 8,
                mFramesPerPacket: 1,
                mBytesPerFrame: 8,
                mChannelsPerFrame: 2,
                mBitsPerChannel: 32,
                mReserved: 0
            )
        )
    }

    func installIOProc(
        on resources: SystemAudioTapResources,
        bufferContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation,
        timestampSink: @escaping @Sendable (Date) -> Void,
        errorSink: @escaping @Sendable (String) -> Void
    ) throws -> SystemAudioTapRuntime {
        installCalls += 1
        if shouldFailInstall {
            throw SystemAudioTapError.ioProcInstallationFailed(-2)
        }
        capturedTimestampSink = timestampSink
        capturedErrorSink = errorSink
        let teardownTracker: @Sendable () -> Void = { [weak self] in
            self?.teardownCalls += 1
        }
        return SystemAudioTapRuntime(resources: resources, teardown: teardownTracker)
    }

    func stopAndDestroy(_ runtime: SystemAudioTapRuntime?) {
        runtime?.teardown()
    }

    func destroyResources(_ resources: SystemAudioTapResources) {
        teardownCalls += 1
    }

    func sweepStaleAggregateDevices(prefix: String, except keep: String?) {
        sweepCalls.append(SweepCall(prefix: prefix, keep: keep))
    }

    /// Drive the captured timestampSink as if a real IO proc had pushed a
    /// buffer. Lets state-machine tests verify the snapshot publishes
    /// last-buffer timestamps without touching audio hardware.
    func fireSyntheticBuffer() {
        capturedTimestampSink?(Date())
    }
}

// MARK: - Tier C helpers

/// Drains an ``AsyncStream`` of ``AVAudioPCMBuffer`` into an in-memory
/// array for the requested duration, then yields control. Real-recording
/// tests use this to pull buffers off the controller while the test tone
/// plays.
actor SystemAudioBufferCollector {
    private(set) var collected: [AVAudioPCMBuffer] = []
    private let stream: AsyncStream<AVAudioPCMBuffer>

    init(stream: AsyncStream<AVAudioPCMBuffer>) {
        self.stream = stream
    }

    func collect(for duration: TimeInterval) async {
        let deadline = Date().addingTimeInterval(duration)
        for await buffer in stream {
            collected.append(buffer)
            if Date() >= deadline {
                break
            }
        }
    }
}

/// Plays a sine wave through the default audio output. Used by the
/// real-recording tests so the tap has something to capture.
final class SineWavePlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let frequency: Double
    private let durationSeconds: Double

    init(frequency: Double, durationSeconds: Double) {
        self.frequency = frequency
        self.durationSeconds = durationSeconds
    }

    func play() throws {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44_100,
            channels: 2,
            interleaved: false
        )!
        let frameCount = AVAudioFrameCount(format.sampleRate * durationSeconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return
        }
        buffer.frameLength = frameCount
        let twoPiF = 2.0 * .pi * frequency
        for channelIndex in 0..<Int(format.channelCount) {
            guard let channelData = buffer.floatChannelData?[channelIndex] else { continue }
            for sampleIndex in 0..<Int(frameCount) {
                let t = Double(sampleIndex) / format.sampleRate
                channelData[sampleIndex] = Float(sin(twoPiF * t)) * 0.5
            }
        }

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try engine.start()
        player.scheduleBuffer(buffer, at: nil, options: [])
        player.play()
    }

    func stop() {
        player.stop()
        engine.stop()
    }
}

/// Compute the aggregate RMS of every PCM buffer. Used to decide whether a
/// recorded clip is "non-silent" against an arbitrary noise floor.
func aggregateRMS(_ buffers: [AVAudioPCMBuffer]) -> Double {
    var sumOfSquares = 0.0
    var sampleCount = 0

    for buffer in buffers {
        guard let channelData = buffer.floatChannelData else { continue }
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        for channelIndex in 0..<channels {
            for sampleIndex in 0..<frames {
                let value = Double(channelData[channelIndex][sampleIndex])
                sumOfSquares += value * value
                sampleCount += 1
            }
        }
    }

    guard sampleCount > 0 else { return 0 }
    return (sumOfSquares / Double(sampleCount)).squareRoot()
}

// MARK: - Async assertion helper

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: @autoclosure () -> String = "Expected expression to throw.",
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail(message(), file: file, line: line)
    } catch {
        // expected
    }
}
