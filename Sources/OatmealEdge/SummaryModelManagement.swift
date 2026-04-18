import Foundation

public struct SummaryModelCatalogEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var displayName: String
    public var repositoryID: String
    public var suggestedDirectoryName: String
    public var summary: String
    public var footprintDescription: String
    public var recommended: Bool

    public init(
        id: String,
        displayName: String,
        repositoryID: String,
        suggestedDirectoryName: String,
        summary: String,
        footprintDescription: String,
        recommended: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.repositoryID = repositoryID
        self.suggestedDirectoryName = suggestedDirectoryName
        self.summary = summary
        self.footprintDescription = footprintDescription
        self.recommended = recommended
    }

    public static let curatedDefaults: [SummaryModelCatalogEntry] = [
        SummaryModelCatalogEntry(
            id: "qwen2.5-0.5b-instruct-4bit",
            displayName: "Qwen2.5-0.5B-Instruct-4bit",
            repositoryID: "mlx-community/Qwen2.5-0.5B-Instruct-4bit",
            suggestedDirectoryName: "Qwen2.5-0.5B-Instruct-4bit",
            summary: "Fastest local summary model. Good default for concise meeting notes on most Apple Silicon Macs.",
            footprintDescription: "Approx. 0.5B params, 4-bit",
            recommended: true
        )
    ]
}

public struct SummaryModelCatalogItemState: Equatable, Sendable, Identifiable {
    public var id: String { catalogEntry.id }
    public var catalogEntry: SummaryModelCatalogEntry
    public var installedModel: ManagedSummaryModel?

    public init(
        catalogEntry: SummaryModelCatalogEntry,
        installedModel: ManagedSummaryModel?
    ) {
        self.catalogEntry = catalogEntry
        self.installedModel = installedModel
    }
}

public struct SummaryModelCatalogState: Equatable, Sendable {
    public var modelsDirectoryURL: URL
    public var downloadAvailability: SummaryRuntimeAvailability
    public var downloadRuntimeDetail: String
    public var items: [SummaryModelCatalogItemState]

    public init(
        modelsDirectoryURL: URL,
        downloadAvailability: SummaryRuntimeAvailability,
        downloadRuntimeDetail: String,
        items: [SummaryModelCatalogItemState]
    ) {
        self.modelsDirectoryURL = modelsDirectoryURL
        self.downloadAvailability = downloadAvailability
        self.downloadRuntimeDetail = downloadRuntimeDetail
        self.items = items
    }
}

public enum SummaryModelManagementError: LocalizedError, Equatable {
    case unknownModel(String)
    case runtimeUnavailable(String)
    case installationFailed(String)
    case removalFailed(String)
    case invalidModelLocation(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownModel(message),
             let .runtimeUnavailable(message),
             let .installationFailed(message),
             let .removalFailed(message),
             let .invalidModelLocation(message):
            return message
        }
    }
}

public protocol LocalSummaryModelManaging: Sendable {
    func catalogState() async -> SummaryModelCatalogState
    func install(modelID: String, forceRedownload: Bool) async throws -> SummaryModelCatalogState
    func remove(modelDirectoryURL: URL) async throws -> SummaryModelCatalogState
}

public final class LocalSummaryModelManager: LocalSummaryModelManaging, @unchecked Sendable {
    private let fileManager: FileManager
    private let inventory: SummaryModelInventory
    private let processExecutor: ProcessExecuting
    private let runtimeEnvironment: MLXRuntimeEnvironment
    private let catalog: [SummaryModelCatalogEntry]

    public init(
        applicationSupportDirectoryURL: URL? = nil,
        catalog: [SummaryModelCatalogEntry] = SummaryModelCatalogEntry.curatedDefaults
    ) {
        let baseURL = applicationSupportDirectoryURL
            ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory)
                .appendingPathComponent("Oatmeal", isDirectory: true)
        self.fileManager = .default
        self.catalog = catalog
        self.inventory = SummaryModelInventory(
            modelsDirectoryURL: baseURL.appendingPathComponent("Models/Summaries", isDirectory: true)
        )
        self.processExecutor = ProcessExecutor()
        self.runtimeEnvironment = MLXRuntimeEnvironment(
            processExecutor: processExecutor,
            managedPythonURL: MLXRuntimeEnvironment.defaultManagedPythonURL(baseURL: baseURL)
        )
    }

    init(
        applicationSupportDirectoryURL: URL,
        catalog: [SummaryModelCatalogEntry],
        executableLocator: ExecutableLocator,
        processExecutor: ProcessExecuting,
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.fileManager = fileManager
        self.catalog = catalog
        self.inventory = SummaryModelInventory(
            modelsDirectoryURL: applicationSupportDirectoryURL.appendingPathComponent("Models/Summaries", isDirectory: true)
        )
        self.processExecutor = processExecutor
        self.runtimeEnvironment = MLXRuntimeEnvironment(
            executableLocator: executableLocator,
            processExecutor: processExecutor,
            environment: environment,
            managedPythonURL: MLXRuntimeEnvironment.defaultManagedPythonURL(baseURL: applicationSupportDirectoryURL)
        )
    }

    public func catalogState() async -> SummaryModelCatalogState {
        buildCatalogState()
    }

    public func install(modelID: String, forceRedownload: Bool) async throws -> SummaryModelCatalogState {
        try await Task.detached(priority: .utility) { [self] in
            try installSynchronously(modelID: modelID, forceRedownload: forceRedownload)
        }.value
    }

    public func remove(modelDirectoryURL: URL) async throws -> SummaryModelCatalogState {
        try await Task.detached(priority: .utility) { [self] in
            try removeSynchronously(modelDirectoryURL: modelDirectoryURL)
        }.value
    }

    private func buildCatalogState() -> SummaryModelCatalogState {
        let discoveredModels = inventory.discoveredModels()
        let installedModelsByDirectoryName = Dictionary(
            uniqueKeysWithValues: discoveredModels.map { ($0.directoryURL.lastPathComponent.lowercased(), $0) }
        )

        let availability: SummaryRuntimeAvailability
        let detail: String
        if let pythonURL = runtimeEnvironment.pythonExecutableURL() {
            if runtimeEnvironment.pythonEnvironmentSupports(requiredModules: ["huggingface_hub"], pythonURL: pythonURL) {
                availability = .available
                detail = "Model downloads are ready. Oatmeal will use the managed MLX Python environment to fetch curated models."
            } else {
                availability = .unavailable
                detail = "python3 is available, but the managed environment does not provide `huggingface_hub`, so Oatmeal cannot download models yet."
            }
        } else {
            availability = .unavailable
            detail = "python3 was not found, so Oatmeal cannot download local summary models yet."
        }

        let items = catalog.map { entry in
            SummaryModelCatalogItemState(
                catalogEntry: entry,
                installedModel: installedModelsByDirectoryName[entry.suggestedDirectoryName.lowercased()]
            )
        }

        return SummaryModelCatalogState(
            modelsDirectoryURL: inventory.modelsDirectoryURL,
            downloadAvailability: availability,
            downloadRuntimeDetail: detail,
            items: items
        )
    }

    private func installSynchronously(
        modelID: String,
        forceRedownload: Bool
    ) throws -> SummaryModelCatalogState {
        guard let entry = catalog.first(where: { $0.id == modelID }) else {
            throw SummaryModelManagementError.unknownModel("Oatmeal does not recognize the requested summary model.")
        }

        guard let pythonURL = runtimeEnvironment.pythonExecutableURL() else {
            throw SummaryModelManagementError.runtimeUnavailable(
                "python3 was not found, so Oatmeal cannot download \(entry.displayName)."
            )
        }

        guard runtimeEnvironment.pythonEnvironmentSupports(requiredModules: ["huggingface_hub"], pythonURL: pythonURL) else {
            throw SummaryModelManagementError.runtimeUnavailable(
                "The configured python environment does not provide `huggingface_hub`, so Oatmeal cannot download \(entry.displayName)."
            )
        }

        let scriptURL = try downloadScriptURL()
        let destinationURL = inventory.modelsDirectoryURL
            .appendingPathComponent(entry.suggestedDirectoryName, isDirectory: true)
        try ensureModelsDirectoryExists()

        do {
            _ = try processExecutor.run(
                executableURL: pythonURL,
                arguments: [
                    scriptURL.path,
                    "--repo-id", entry.repositoryID,
                    "--output-dir", destinationURL.path,
                ] + (forceRedownload ? ["--force"] : []),
                environment: ProcessInfo.processInfo.environment,
                currentDirectoryURL: inventory.modelsDirectoryURL
            )
        } catch {
            throw SummaryModelManagementError.installationFailed(
                "Oatmeal could not download \(entry.displayName): \(error.localizedDescription)"
            )
        }

        return buildCatalogState()
    }

    private func removeSynchronously(modelDirectoryURL: URL) throws -> SummaryModelCatalogState {
        let resolvedURL = modelDirectoryURL.standardizedFileURL.resolvingSymlinksInPath()
        let modelsDirectoryURL = inventory.modelsDirectoryURL.standardizedFileURL.resolvingSymlinksInPath()
        let modelsDirectoryPath = modelsDirectoryURL.path.hasSuffix("/")
            ? modelsDirectoryURL.path
            : modelsDirectoryURL.path + "/"

        guard resolvedURL.path.hasPrefix(modelsDirectoryPath) else {
            throw SummaryModelManagementError.invalidModelLocation(
                "Oatmeal only removes models inside its managed summaries folder."
            )
        }

        guard fileManager.fileExists(atPath: resolvedURL.path) else {
            return buildCatalogState()
        }

        do {
            try fileManager.removeItem(at: resolvedURL)
        } catch {
            throw SummaryModelManagementError.removalFailed(
                "Oatmeal could not remove the local model at \(resolvedURL.lastPathComponent): \(error.localizedDescription)"
            )
        }

        return buildCatalogState()
    }

    private func ensureModelsDirectoryExists() throws {
        if fileManager.fileExists(atPath: inventory.modelsDirectoryURL.path) {
            return
        }

        try fileManager.createDirectory(at: inventory.modelsDirectoryURL, withIntermediateDirectories: true)
    }

    private func downloadScriptURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "download_summary_model", withExtension: "py") else {
            throw SummaryModelManagementError.runtimeUnavailable(
                "Oatmeal could not find the bundled model download helper."
            )
        }

        return url
    }
}
