import Foundation

struct MLXRuntimeEnvironment: Sendable {
    private let executableLocator: ExecutableLocator
    private let processExecutor: ProcessExecuting
    private let environment: [String: String]
    private let managedPythonURL: URL?

    init(
        executableLocator: ExecutableLocator = ExecutableLocator(),
        processExecutor: ProcessExecuting = ProcessExecutor(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        managedPythonURL: URL? = nil
    ) {
        self.executableLocator = executableLocator
        self.processExecutor = processExecutor
        self.environment = environment
        self.managedPythonURL = managedPythonURL ?? Self.defaultManagedPythonURL()
    }

    func pythonExecutableURL() -> URL? {
        if let configuredPath = environment["OATMEAL_MLX_PYTHON_PATH"], !configuredPath.isEmpty {
            let configuredURL = URL(fileURLWithPath: configuredPath)
            if FileManager.default.isExecutableFile(atPath: configuredURL.path) {
                return configuredURL
            }
        }

        if let managedPythonURL, FileManager.default.isExecutableFile(atPath: managedPythonURL.path) {
            return managedPythonURL
        }

        return executableLocator.locate(
            candidateNames: ["python3"],
            fallbackAbsolutePaths: ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
        )
    }

    func pythonEnvironmentSupports(
        requiredModules: [String],
        pythonURL: URL
    ) -> Bool {
        guard !requiredModules.isEmpty else {
            return true
        }

        let checks = requiredModules
            .map { "importlib.util.find_spec('\($0)')" }
            .joined(separator: " and ")
        let script = "import importlib.util, sys; sys.exit(0 if \(checks) else 1)"

        do {
            _ = try processExecutor.run(
                executableURL: pythonURL,
                arguments: ["-c", script],
                environment: environment,
                currentDirectoryURL: nil
            )
            return true
        } catch {
            return false
        }
    }

    static func defaultManagedPythonURL(baseURL: URL? = nil) -> URL {
        let rootURL = baseURL
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("Oatmeal", isDirectory: true)

        return rootURL
            .appendingPathComponent("Tools", isDirectory: true)
            .appendingPathComponent("mlx-summary", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python3", isDirectory: false)
    }
}
