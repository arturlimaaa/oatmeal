import Foundation
@testable import OatmealUI
import XCTest

final class AudioRetentionCoordinatorTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioRetentionCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root = temporaryRoot, FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        temporaryRoot = nil
        try super.tearDownWithError()
    }

    func testPathsAreStablePerNoteIDAndUnderRecordingsDirectory() {
        let recordingsDir = temporaryRoot.appendingPathComponent("Recordings", isDirectory: true)
        let coordinator = AudioRetentionCoordinator(recordingsDirectoryURL: recordingsDir)
        let noteID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

        let paths = coordinator.paths(for: noteID)

        XCTAssertEqual(
            paths.microphoneURL,
            recordingsDir.appendingPathComponent("\(noteID.uuidString).caf", isDirectory: false)
        )
        XCTAssertEqual(
            paths.systemAudioURL,
            recordingsDir.appendingPathComponent("\(noteID.uuidString).mp4", isDirectory: false)
        )
        XCTAssertEqual(
            paths.normalizedWAVURL,
            recordingsDir
                .appendingPathComponent("Normalized", isDirectory: true)
                .appendingPathComponent("\(noteID.uuidString).wav", isDirectory: false)
        )

        // Repeated calls return the same shape for the same note ID.
        XCTAssertEqual(paths, coordinator.paths(for: noteID))
    }

    func testNormalizationSucceededDeletesOriginalsButKeepsNormalizedWAV() throws {
        let recordingsDir = temporaryRoot.appendingPathComponent("Recordings", isDirectory: true)
        let coordinator = AudioRetentionCoordinator(recordingsDirectoryURL: recordingsDir)
        let noteID = UUID()

        try writeFixtureFiles(coordinator: coordinator, noteID: noteID, includeWAV: true, includeLiveChunk: true)

        try coordinator.apply(.normalizationSucceeded(noteID: noteID))

        let paths = coordinator.paths(for: noteID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.microphoneURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.systemAudioURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.normalizedWAVURL.path))
        XCTAssertEqual(coordinator.retainedWAVURL(for: noteID), paths.normalizedWAVURL)
        // Live-chunk directory is part of the originals and should be cleared.
        let liveChunkDir = recordingsDir
            .appendingPathComponent("LiveChunks", isDirectory: true)
            .appendingPathComponent(noteID.uuidString, isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: liveChunkDir.path))
    }

    func testNoteDeletedRemovesNormalizedWAV() throws {
        let recordingsDir = temporaryRoot.appendingPathComponent("Recordings", isDirectory: true)
        let coordinator = AudioRetentionCoordinator(recordingsDirectoryURL: recordingsDir)
        let noteID = UUID()

        try writeFixtureFiles(coordinator: coordinator, noteID: noteID, includeWAV: true, includeLiveChunk: false)
        // Simulate the post-normalization state by removing the originals first.
        try coordinator.apply(.normalizationSucceeded(noteID: noteID))
        XCTAssertNotNil(coordinator.retainedWAVURL(for: noteID))

        try coordinator.apply(.noteDeleted(noteID: noteID))

        XCTAssertNil(coordinator.retainedWAVURL(for: noteID))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: coordinator.paths(for: noteID).normalizedWAVURL.path)
        )
    }

    func testApplyIsIdempotentWhenFilesAreAlreadyMissing() throws {
        let recordingsDir = temporaryRoot.appendingPathComponent("Recordings", isDirectory: true)
        let coordinator = AudioRetentionCoordinator(recordingsDirectoryURL: recordingsDir)
        let noteID = UUID()

        // Nothing on disk for this note — both events should be no-ops, not throw.
        XCTAssertNoThrow(try coordinator.apply(.normalizationSucceeded(noteID: noteID)))
        XCTAssertNoThrow(try coordinator.apply(.noteDeleted(noteID: noteID)))
        XCTAssertNil(coordinator.retainedWAVURL(for: noteID))
    }

    func testRetainedWAVURLReturnsNilWhenWAVIsAbsent() throws {
        let recordingsDir = temporaryRoot.appendingPathComponent("Recordings", isDirectory: true)
        let coordinator = AudioRetentionCoordinator(recordingsDirectoryURL: recordingsDir)
        let noteID = UUID()

        XCTAssertNil(coordinator.retainedWAVURL(for: noteID))

        // Writing only the originals (no WAV) still leaves retainedWAVURL nil.
        try writeFixtureFiles(coordinator: coordinator, noteID: noteID, includeWAV: false, includeLiveChunk: false)
        XCTAssertNil(coordinator.retainedWAVURL(for: noteID))
    }

    func testPrepareNormalizedDirectoryCreatesDirectoryAndIsIdempotent() throws {
        let recordingsDir = temporaryRoot.appendingPathComponent("Recordings", isDirectory: true)
        let coordinator = AudioRetentionCoordinator(recordingsDirectoryURL: recordingsDir)

        let dir = try coordinator.prepareNormalizedDirectory()
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))

        // Calling it again must not throw or invalidate the existing directory.
        XCTAssertNoThrow(try coordinator.prepareNormalizedDirectory())
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
    }

    // MARK: - Helpers

    private func writeFixtureFiles(
        coordinator: AudioRetentionCoordinator,
        noteID: UUID,
        includeWAV: Bool,
        includeLiveChunk: Bool
    ) throws {
        let paths = coordinator.paths(for: noteID)
        try FileManager.default.createDirectory(
            at: paths.microphoneURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("microphone".utf8).write(to: paths.microphoneURL)
        try Data("system".utf8).write(to: paths.systemAudioURL)

        if includeWAV {
            try FileManager.default.createDirectory(
                at: paths.normalizedWAVURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("wav".utf8).write(to: paths.normalizedWAVURL)
        }

        if includeLiveChunk {
            let liveChunkDir = paths.microphoneURL.deletingLastPathComponent()
                .appendingPathComponent("LiveChunks", isDirectory: true)
                .appendingPathComponent(noteID.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: liveChunkDir, withIntermediateDirectories: true)
            try Data("chunk".utf8).write(
                to: liveChunkDir.appendingPathComponent("microphone-0000-\(noteID.uuidString).caf")
            )
        }
    }
}
