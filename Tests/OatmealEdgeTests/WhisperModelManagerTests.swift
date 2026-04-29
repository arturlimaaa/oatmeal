import Foundation
@testable import OatmealEdge
import XCTest

final class WhisperModelManagerTests: XCTestCase {
    func testCatalogStateMarksInstalledModelsBasedOnInventory() async throws {
        let modelsDirectoryURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: modelsDirectoryURL) }

        let entry = fixtureEntry()
        // Simulate a previously-installed model file in the managed dir.
        try Data("ggml".utf8).write(
            to: modelsDirectoryURL.appendingPathComponent(entry.id, isDirectory: false)
        )

        let manager = LocalWhisperModelManager(
            modelsDirectoryURL: modelsDirectoryURL,
            catalog: [entry],
            downloader: NeverInvokedDownloader()
        )

        let state = await manager.catalogState()
        XCTAssertEqual(state.items.count, 1)
        XCTAssertNotNil(state.items.first?.installedModel)
        XCTAssertEqual(state.items.first?.installedModel?.fileURL.lastPathComponent, entry.id)
    }

    func testInstallWritesModelIntoManagedDirectoryAndReportsProgress() async throws {
        let modelsDirectoryURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: modelsDirectoryURL) }

        let entry = fixtureEntry()
        let downloader = WritingDownloader(payload: Data("ggml-payload".utf8))

        let manager = LocalWhisperModelManager(
            modelsDirectoryURL: modelsDirectoryURL,
            catalog: [entry],
            downloader: downloader
        )

        let progressBox = ProgressBox()

        let state = try await manager.install(
            modelID: entry.id,
            forceRedownload: false,
            progress: { fraction in
                Task { await progressBox.append(fraction) }
            }
        )

        let targetURL = modelsDirectoryURL.appendingPathComponent(entry.id, isDirectory: false)
        let partialURL = modelsDirectoryURL.appendingPathComponent("\(entry.id).partial", isDirectory: false)

        XCTAssertTrue(FileManager.default.fileExists(atPath: targetURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialURL.path))
        XCTAssertEqual(state.items.first?.installedModel?.fileURL.lastPathComponent, entry.id)

        let observed = await progressBox.values
        XCTAssertFalse(observed.isEmpty, "downloader should have been driven to emit progress")
        XCTAssertEqual(observed.last, 1.0)
    }

    func testInstallSkipsRedownloadWhenModelAlreadyPresentAndNotForced() async throws {
        let modelsDirectoryURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: modelsDirectoryURL) }

        let entry = fixtureEntry()
        let targetURL = modelsDirectoryURL.appendingPathComponent(entry.id, isDirectory: false)
        try Data("ggml".utf8).write(to: targetURL)

        let downloader = NeverInvokedDownloader()
        let manager = LocalWhisperModelManager(
            modelsDirectoryURL: modelsDirectoryURL,
            catalog: [entry],
            downloader: downloader
        )

        let state = try await manager.install(modelID: entry.id, forceRedownload: false, progress: { _ in })
        XCTAssertEqual(state.items.first?.installedModel?.fileURL.lastPathComponent, entry.id)
        XCTAssertEqual(downloader.invocations, 0)
    }

    func testCancelInstallRemovesPartialFileAndAbortsTask() async throws {
        let modelsDirectoryURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: modelsDirectoryURL) }

        let entry = fixtureEntry()
        let downloader = HangingDownloader()
        let manager = LocalWhisperModelManager(
            modelsDirectoryURL: modelsDirectoryURL,
            catalog: [entry],
            downloader: downloader
        )

        let installTask = Task {
            try await manager.install(modelID: entry.id, forceRedownload: false, progress: { _ in })
        }

        await downloader.waitUntilStarted()
        await manager.cancelInstall(modelID: entry.id)

        do {
            _ = try await installTask.value
            XCTFail("Cancelled install should not return a successful catalog state")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let partialURL = modelsDirectoryURL.appendingPathComponent("\(entry.id).partial", isDirectory: false)
        let targetURL = modelsDirectoryURL.appendingPathComponent(entry.id, isDirectory: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetURL.path))
    }

    func testRemoveDeletesInstalledModelFromDisk() async throws {
        let modelsDirectoryURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: modelsDirectoryURL) }

        let entry = fixtureEntry()
        let targetURL = modelsDirectoryURL.appendingPathComponent(entry.id, isDirectory: false)
        try Data("ggml".utf8).write(to: targetURL)

        let manager = LocalWhisperModelManager(
            modelsDirectoryURL: modelsDirectoryURL,
            catalog: [entry],
            downloader: NeverInvokedDownloader()
        )

        let state = try await manager.remove(modelID: entry.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetURL.path))
        XCTAssertNil(state.items.first?.installedModel)
    }

    func testInstallUnknownModelThrows() async {
        let modelsDirectoryURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: modelsDirectoryURL) }

        let manager = LocalWhisperModelManager(
            modelsDirectoryURL: modelsDirectoryURL,
            catalog: [fixtureEntry()],
            downloader: NeverInvokedDownloader()
        )

        do {
            _ = try await manager.install(modelID: "ggml-bogus.bin", forceRedownload: false, progress: { _ in })
            XCTFail("Expected install of unknown model to throw")
        } catch let error as WhisperModelManagementError {
            switch error {
            case .unknownModel:
                break
            default:
                XCTFail("Expected .unknownModel error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Helpers

    private func fixtureEntry() -> CuratedWhisperModelEntry {
        CuratedWhisperModelEntry(
            id: "ggml-test.bin",
            displayName: "Whisper Test",
            sizeBytes: 1024,
            downloadURL: URL(string: "https://example.com/ggml-test.bin")!,
            variant: .multilingual,
            sizeTier: .small,
            perLanguageQualityHints: []
        )
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

// MARK: - Test downloaders

private actor ProgressBox {
    private(set) var values: [Double] = []

    func append(_ value: Double) {
        values.append(value)
    }
}

private final class NeverInvokedDownloader: WhisperModelDownloading, @unchecked Sendable {
    private(set) var invocations = 0

    func download(
        from _: URL,
        to _: URL,
        progress _: @Sendable @escaping (Double) -> Void
    ) async throws {
        invocations += 1
        XCTFail("Downloader should not have been invoked in this scenario")
    }
}

private final class WritingDownloader: WhisperModelDownloading, @unchecked Sendable {
    private let payload: Data

    init(payload: Data) {
        self.payload = payload
    }

    func download(
        from _: URL,
        to destinationURL: URL,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws {
        try payload.write(to: destinationURL)
        progress(0.5)
        progress(1.0)
    }
}

private final class HangingDownloader: WhisperModelDownloading, @unchecked Sendable {
    private let startedContinuation: AsyncStream<Void>.Continuation
    private let startedStream: AsyncStream<Void>

    init() {
        var continuation: AsyncStream<Void>.Continuation!
        self.startedStream = AsyncStream<Void> { continuation = $0 }
        self.startedContinuation = continuation
    }

    func download(
        from _: URL,
        to destinationURL: URL,
        progress _: @Sendable @escaping (Double) -> Void
    ) async throws {
        // Lay down a partial file the way the real downloader would so the
        // cancellation cleanup path has something to delete.
        FileManager.default.createFile(atPath: destinationURL.path, contents: Data("partial".utf8))
        startedContinuation.yield(())

        // Wait until cancelled. We rely on Task.checkCancellation rather than
        // a pure sleep loop so the test cancellation propagates promptly.
        while !Task.isCancelled {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw CancellationError()
    }

    func waitUntilStarted() async {
        for await _ in startedStream {
            return
        }
    }
}
