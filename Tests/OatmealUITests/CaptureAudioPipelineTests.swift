@preconcurrency import AVFoundation
import Foundation
@testable import OatmealUI
import OatmealCore
import XCTest

// MARK: - Tier B unit tests (state machine)

/// Exercises ``CaptureAudioPipeline`` lifecycle invariants without
/// touching real audio hardware. These run on every CI machine.
final class CaptureAudioPipelineLifecycleTests: XCTestCase {
    func testStopBeforeStartThrowsNoActiveSession() async throws {
        let pipeline = CaptureAudioPipeline(noteID: UUID())
        do {
            _ = try await pipeline.stop()
            XCTFail("Expected stop() before start() to throw")
        } catch let error as CaptureAudioPipelineError {
            XCTAssertEqual(error, .noActiveSession)
        }
    }

    func testHealthSnapshotStartsIdle() async {
        let pipeline = CaptureAudioPipeline(noteID: UUID())
        let snapshot = await pipeline.healthSnapshot
        XCTAssertEqual(snapshot.state, .idle)
        XCTAssertNil(snapshot.lastMicrophoneBufferAt)
        XCTAssertNil(snapshot.lastSystemAudioBufferAt)
        XCTAssertEqual(snapshot.microphoneFrameCount, 0)
    }

    func testAttachSystemAudioBuffersIsIdempotentAndHeartbeatUpdates() async throws {
        // The real consumer of `attachSystemAudioBuffers` lands in Issue C.
        // Today the placeholder just remembers the attach happened.
        // We verify two invariants:
        //   1. The placeholder accepts the attach without crashing and
        //      treats the second attach as a no-op (single-attach by design).
        //   2. The system-audio heartbeat seam updates the snapshot — Issue C
        //      will reuse the same path when real buffers arrive.
        let pipeline = CaptureAudioPipeline(noteID: UUID())
        let (stream1, _) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        let (stream2, _) = AsyncStream<AVAudioPCMBuffer>.makeStream()

        await pipeline.attachSystemAudioBuffers(stream1)
        await pipeline.attachSystemAudioBuffers(stream2) // no-op by design

        let firstSnapshot = await pipeline.healthSnapshot
        XCTAssertNil(firstSnapshot.lastSystemAudioBufferAt)

        let timestamp = Date()
        await pipeline.recordSystemAudioBufferForTesting(at: timestamp)
        let secondSnapshot = await pipeline.healthSnapshot
        XCTAssertEqual(secondSnapshot.lastSystemAudioBufferAt, timestamp)
    }
}

// MARK: - Tier C real-recording tests

/// Drives a real `AVAudioEngine` capture session for two seconds and
/// asserts the resulting `.m4a` file is non-silent. Gated behind an
/// environment variable so CI runners without a microphone skip
/// gracefully.
final class CaptureAudioPipelineRealRecordingTests: XCTestCase {
    private static var realRecordingEnabled: Bool {
        ProcessInfo.processInfo.environment["OATMEAL_PIPELINE_REAL_RECORDING"] == "1"
    }

    private static var hasMicrophoneInputDevice: Bool {
        AVCaptureDevice.default(for: .audio) != nil
    }

    private static func skipIfRealRecordingUnavailable() throws {
        guard realRecordingEnabled else {
            throw XCTSkip("Set OATMEAL_PIPELINE_REAL_RECORDING=1 to run the audio-pipeline real-recording tests.")
        }
        guard hasMicrophoneInputDevice else {
            throw XCTSkip("No microphone input device available on this Mac.")
        }
    }

    func testRecordsMicrophone() async throws {
        try Self.skipIfRealRecordingUnavailable()

        let workDir = try makeWorkingDirectory()
        defer { try? FileManager.default.removeItem(at: workDir) }

        let outputURL = workDir.appendingPathComponent("recording.m4a")
        let chunkDir = workDir.appendingPathComponent("chunks", isDirectory: true)

        let pipeline = CaptureAudioPipeline(noteID: UUID(), liveChunkDuration: 30)
        _ = try await pipeline.start(outputURL: outputURL, liveChunkDirectoryURL: chunkDir)
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let artifact = try await pipeline.stop()

        XCTAssertEqual(artifact.fileURL, outputURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let size = (attributes[.size] as? UInt64) ?? 0
        XCTAssertGreaterThan(size, 1024, "Recording is suspiciously small: \(size) bytes")

        // Read the file back and check at least one sample is non-zero.
        let file = try AVAudioFile(forReading: outputURL)
        XCTAssertGreaterThan(file.length, 0)
        let frameCount = AVAudioFrameCount(min(file.length, 48_000))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
            XCTFail("Could not allocate read buffer")
            return
        }
        try file.read(into: buffer, frameCount: frameCount)
        let rms = computeRMS(buffer)
        XCTAssertGreaterThan(
            rms,
            0.0001,
            "Captured PCM appears entirely silent (RMS=\(rms)). Microphone may be muted."
        )
    }

    func testEmitsLiveChunks() async throws {
        try Self.skipIfRealRecordingUnavailable()

        let workDir = try makeWorkingDirectory()
        defer { try? FileManager.default.removeItem(at: workDir) }

        let outputURL = workDir.appendingPathComponent("recording.m4a")
        let chunkDir = workDir.appendingPathComponent("chunks", isDirectory: true)

        // Force two rotations during the 2-second window: chunkDuration < 1s.
        let pipeline = CaptureAudioPipeline(noteID: UUID(), liveChunkDuration: 0.8)
        _ = try await pipeline.start(outputURL: outputURL, liveChunkDirectoryURL: chunkDir)
        try await Task.sleep(nanoseconds: 2_000_000_000)
        _ = try await pipeline.stop()

        let chunks = await pipeline.completedLiveTranscriptionChunks
        XCTAssertGreaterThanOrEqual(
            chunks.count,
            2,
            "Expected at least 2 live chunks across a 2s recording with 0.8s rotation; got \(chunks.count)"
        )
        for chunk in chunks {
            XCTAssertTrue(FileManager.default.fileExists(atPath: chunk.fileURL.path))
        }
    }

    func testReportsHealth() async throws {
        try Self.skipIfRealRecordingUnavailable()

        let workDir = try makeWorkingDirectory()
        defer { try? FileManager.default.removeItem(at: workDir) }

        let outputURL = workDir.appendingPathComponent("recording.m4a")
        let chunkDir = workDir.appendingPathComponent("chunks", isDirectory: true)

        let pipeline = CaptureAudioPipeline(noteID: UUID())
        _ = try await pipeline.start(outputURL: outputURL, liveChunkDirectoryURL: chunkDir)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let mid = await pipeline.healthSnapshot
        _ = try await pipeline.stop()

        XCTAssertEqual(mid.state, .running)
        XCTAssertNotNil(mid.lastMicrophoneBufferAt, "Snapshot should reflect microphone activity within 1s.")
        XCTAssertGreaterThan(mid.sampleRate, 0)
        XCTAssertGreaterThan(mid.channelCount, 0)
        XCTAssertGreaterThan(mid.microphoneFrameCount, 0)
    }

    // MARK: Helpers

    private func makeWorkingDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("oatmeal-pipeline-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func computeRMS(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let floatData = buffer.floatChannelData else { return 0 }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else { return 0 }
        var sumSquares: Double = 0
        for channel in 0..<channelCount {
            let samples = floatData[channel]
            for frame in 0..<frameCount {
                let value = Double(samples[frame])
                sumSquares += value * value
            }
        }
        return (sumSquares / Double(frameCount * channelCount)).squareRoot()
    }
}
