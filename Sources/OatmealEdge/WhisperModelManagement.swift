import Foundation

/// Snapshot for one curated whisper-model entry plus whatever the inventory
/// currently knows about an installed copy on disk.
public struct WhisperModelCatalogItemState: Equatable, Sendable, Identifiable {
    public var id: String { catalogEntry.id }
    public var catalogEntry: CuratedWhisperModelEntry
    public var installedModel: ManagedLocalModel?

    public init(
        catalogEntry: CuratedWhisperModelEntry,
        installedModel: ManagedLocalModel?
    ) {
        self.catalogEntry = catalogEntry
        self.installedModel = installedModel
    }
}

/// Aggregate state surfaced to the Settings UI for the multilingual-models
/// section. Mirrors `SummaryModelCatalogState` so the two sections look
/// structurally identical at the call site.
public struct WhisperModelCatalogState: Equatable, Sendable {
    public var modelsDirectoryURL: URL
    public var items: [WhisperModelCatalogItemState]

    public init(
        modelsDirectoryURL: URL,
        items: [WhisperModelCatalogItemState]
    ) {
        self.modelsDirectoryURL = modelsDirectoryURL
        self.items = items
    }
}

public enum WhisperModelManagementError: LocalizedError, Equatable {
    case unknownModel(String)
    case installationFailed(String)
    case removalFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case let .unknownModel(message),
             let .installationFailed(message),
             let .removalFailed(message):
            return message
        case .cancelled:
            return "The download was cancelled."
        }
    }
}

/// Abstraction so tests can drive the manager without hitting the network.
/// Implementations download the requested URL into `destinationURL` and
/// stream progress in `[0, 1]` units. Throwing `CancellationError` (or
/// `WhisperModelManagementError.cancelled`) is the canonical "user cancelled"
/// signal.
public protocol WhisperModelDownloading: Sendable {
    func download(
        from url: URL,
        to destinationURL: URL,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws
}

public protocol LocalWhisperModelManaging: Sendable {
    func catalogState() async -> WhisperModelCatalogState
    func install(
        modelID: String,
        forceRedownload: Bool,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> WhisperModelCatalogState
    func cancelInstall(modelID: String) async
    func remove(modelID: String) async throws -> WhisperModelCatalogState
}

public final class LocalWhisperModelManager: LocalWhisperModelManaging, @unchecked Sendable {
    private let modelsDirectoryURL: URL
    private let inventory: LocalModelInventory
    private let catalog: [CuratedWhisperModelEntry]
    private let downloader: any WhisperModelDownloading
    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "com.oatmeal.whispermodelmanager.state")
    private var activeInstalls: [String: Task<WhisperModelCatalogState, Error>] = [:]

    public convenience init(
        applicationSupportDirectoryURL: URL? = nil,
        catalog: [CuratedWhisperModelEntry] = CuratedModelCatalog.curatedDefaults
    ) {
        let baseURL = applicationSupportDirectoryURL
            ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory)
                .appendingPathComponent("Oatmeal", isDirectory: true)
        let modelsDirectoryURL = baseURL.appendingPathComponent("Models", isDirectory: true)
        self.init(
            modelsDirectoryURL: modelsDirectoryURL,
            catalog: catalog,
            downloader: URLSessionWhisperModelDownloader()
        )
    }

    public init(
        modelsDirectoryURL: URL,
        catalog: [CuratedWhisperModelEntry] = CuratedModelCatalog.curatedDefaults,
        downloader: any WhisperModelDownloading = URLSessionWhisperModelDownloader(),
        fileManager: FileManager = .default
    ) {
        self.modelsDirectoryURL = modelsDirectoryURL
        self.catalog = catalog
        self.downloader = downloader
        self.fileManager = fileManager
        self.inventory = LocalModelInventory(modelsDirectoryURL: modelsDirectoryURL)
    }

    public func catalogState() async -> WhisperModelCatalogState {
        buildCatalogState()
    }

    public func install(
        modelID: String,
        forceRedownload: Bool,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> WhisperModelCatalogState {
        guard let entry = catalog.first(where: { $0.id == modelID }) else {
            throw WhisperModelManagementError.unknownModel(
                "Oatmeal does not recognize the requested whisper model."
            )
        }

        // If a matching install is already in flight we re-use its task so
        // concurrent UI clicks don't race on the same partial file.
        if let existing = task(for: modelID) {
            return try await existing.value
        }

        let task = Task<WhisperModelCatalogState, Error> { [self] in
            try await performInstall(entry: entry, forceRedownload: forceRedownload, progress: progress)
        }
        register(task: task, for: modelID)

        do {
            let result = try await task.value
            unregister(modelID: modelID)
            return result
        } catch {
            unregister(modelID: modelID)
            throw error
        }
    }

    public func cancelInstall(modelID: String) async {
        guard let entry = catalog.first(where: { $0.id == modelID }) else {
            return
        }
        if let task = task(for: modelID) {
            task.cancel()
            // Wait for the cancellation to settle so the partial file is
            // gone by the time the caller reads catalog state again.
            _ = try? await task.value
        }
        // Belt-and-braces: clean up an orphaned partial file even if no task
        // was registered (e.g. the manager was restarted mid-download).
        let partialURL = partialFileURL(for: entry)
        try? fileManager.removeItem(at: partialURL)
    }

    public func remove(modelID: String) async throws -> WhisperModelCatalogState {
        guard let entry = catalog.first(where: { $0.id == modelID }) else {
            throw WhisperModelManagementError.unknownModel(
                "Oatmeal does not recognize the requested whisper model."
            )
        }

        let targetURL = destinationFileURL(for: entry)
        if fileManager.fileExists(atPath: targetURL.path) {
            do {
                try fileManager.removeItem(at: targetURL)
            } catch {
                throw WhisperModelManagementError.removalFailed(
                    "Oatmeal could not remove \(entry.displayName): \(error.localizedDescription)"
                )
            }
        }
        return buildCatalogState()
    }

    // MARK: - Private helpers

    private func performInstall(
        entry: CuratedWhisperModelEntry,
        forceRedownload: Bool,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> WhisperModelCatalogState {
        try ensureModelsDirectoryExists()
        let targetURL = destinationFileURL(for: entry)
        let partialURL = partialFileURL(for: entry)

        if fileManager.fileExists(atPath: targetURL.path), !forceRedownload {
            return buildCatalogState()
        }

        // Reset any leftover partial from a prior aborted run; we always
        // start downloads from zero rather than attempting byte-range
        // resumption (the simpler story is good enough for Phase 5).
        try? fileManager.removeItem(at: partialURL)

        do {
            try await downloader.download(
                from: entry.downloadURL,
                to: partialURL,
                progress: progress
            )
        } catch is CancellationError {
            try? fileManager.removeItem(at: partialURL)
            throw CancellationError()
        } catch {
            try? fileManager.removeItem(at: partialURL)
            throw WhisperModelManagementError.installationFailed(
                "Oatmeal could not download \(entry.displayName): \(error.localizedDescription)"
            )
        }

        if Task.isCancelled {
            try? fileManager.removeItem(at: partialURL)
            throw CancellationError()
        }

        do {
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            try fileManager.moveItem(at: partialURL, to: targetURL)
        } catch {
            try? fileManager.removeItem(at: partialURL)
            throw WhisperModelManagementError.installationFailed(
                "Oatmeal downloaded \(entry.displayName) but could not save it: \(error.localizedDescription)"
            )
        }

        return buildCatalogState()
    }

    private func buildCatalogState() -> WhisperModelCatalogState {
        let discovered = inventory.discoveredModels()
        let installedByFilename = Dictionary(
            uniqueKeysWithValues: discovered.map {
                ($0.fileURL.lastPathComponent.lowercased(), $0)
            }
        )

        let items = catalog.map { entry in
            WhisperModelCatalogItemState(
                catalogEntry: entry,
                installedModel: installedByFilename[entry.id.lowercased()]
            )
        }

        return WhisperModelCatalogState(
            modelsDirectoryURL: modelsDirectoryURL,
            items: items
        )
    }

    private func ensureModelsDirectoryExists() throws {
        if fileManager.fileExists(atPath: modelsDirectoryURL.path) {
            return
        }
        try fileManager.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)
    }

    private func destinationFileURL(for entry: CuratedWhisperModelEntry) -> URL {
        modelsDirectoryURL.appendingPathComponent(entry.id, isDirectory: false)
    }

    private func partialFileURL(for entry: CuratedWhisperModelEntry) -> URL {
        modelsDirectoryURL.appendingPathComponent("\(entry.id).partial", isDirectory: false)
    }

    private func task(for modelID: String) -> Task<WhisperModelCatalogState, Error>? {
        queue.sync { activeInstalls[modelID] }
    }

    private func register(task: Task<WhisperModelCatalogState, Error>, for modelID: String) {
        queue.sync { activeInstalls[modelID] = task }
    }

    private func unregister(modelID: String) {
        queue.sync { _ = activeInstalls.removeValue(forKey: modelID) }
    }
}

/// Default `URLSession`-backed downloader. Streams bytes via
/// `URLSession.bytes(for:)` so we can publish granular progress without
/// inheriting `URLSessionDownloadDelegate`'s callback gymnastics. Falls back
/// to "indeterminate" progress (best-effort) when the server omits a
/// `Content-Length` header.
public final class URLSessionWhisperModelDownloader: WhisperModelDownloading, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func download(
        from url: URL,
        to destinationURL: URL,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws {
        let (byteStream, response) = try await session.bytes(for: URLRequest(url: url))

        let expectedBytes: Int64
        if let httpResponse = response as? HTTPURLResponse,
           let value = httpResponse.value(forHTTPHeaderField: "Content-Length"),
           let parsed = Int64(value),
           parsed > 0 {
            expectedBytes = parsed
        } else {
            expectedBytes = response.expectedContentLength
        }

        FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: destinationURL) else {
            throw WhisperModelManagementError.installationFailed(
                "Oatmeal could not open the partial download file for writing."
            )
        }
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)
        var written: Int64 = 0
        var lastReportedFraction: Double = -1

        for try await byte in byteStream {
            if Task.isCancelled {
                throw CancellationError()
            }
            buffer.append(byte)
            if buffer.count >= 64 * 1024 {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if expectedBytes > 0 {
                    let fraction = min(Double(written) / Double(expectedBytes), 1.0)
                    if fraction - lastReportedFraction >= 0.01 {
                        lastReportedFraction = fraction
                        progress(fraction)
                    }
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            written += Int64(buffer.count)
        }
        if expectedBytes > 0 {
            progress(1.0)
        } else {
            // No reliable content length; emit a single completion tick so
            // callers can mark the row as done without wedging at 0.
            progress(1.0)
        }
    }
}
