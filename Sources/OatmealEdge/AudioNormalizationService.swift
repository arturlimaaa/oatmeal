import Foundation

enum AudioNormalizationTool: String, Equatable, Sendable {
    case ffmpeg
    case afconvert

    var displayName: String {
        switch self {
        case .ffmpeg:
            "ffmpeg"
        case .afconvert:
            "afconvert"
        }
    }
}

struct AudioNormalizationPlan: Equatable, Sendable {
    let tool: AudioNormalizationTool
    let executableURL: URL
}

enum AudioNormalizationError: LocalizedError, Equatable {
    case unsupportedInput(String)
    case toolUnavailable

    var errorDescription: String? {
        switch self {
        case let .unsupportedInput(fileName):
            "Oatmeal could not normalize \(fileName) into 16 kHz mono WAV."
        case .toolUnavailable:
            "No supported local audio normalization tool was found."
        }
    }
}

protocol AudioNormalizing: Sendable {
    func availablePlan() -> AudioNormalizationPlan?
    func normalize(inputURL: URL, outputURL: URL) throws
}

struct AudioNormalizationService: AudioNormalizing {
    private let locator: ExecutableLocator
    private let executor: any ProcessExecuting
    private let environment: [String: String]

    init(
        locator: ExecutableLocator = ExecutableLocator(),
        executor: some ProcessExecuting = ProcessExecutor(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.locator = locator
        self.executor = executor
        self.environment = environment
    }

    func availablePlan() -> AudioNormalizationPlan? {
        if let ffmpegURL = locator.locate(
            envKey: "OATMEAL_FFMPEG_BINARY_PATH",
            candidateNames: ["ffmpeg"],
            fallbackAbsolutePaths: ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
        ) {
            return AudioNormalizationPlan(tool: .ffmpeg, executableURL: ffmpegURL)
        }

        if let afconvertURL = locator.locate(
            envKey: "OATMEAL_AFCONVERT_BINARY_PATH",
            candidateNames: ["afconvert"],
            fallbackAbsolutePaths: ["/usr/bin/afconvert"]
        ) {
            return AudioNormalizationPlan(tool: .afconvert, executableURL: afconvertURL)
        }

        return nil
    }

    func normalize(inputURL: URL, outputURL: URL) throws {
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw TranscriptionPipelineError.fileNotFound
        }

        guard let plan = availablePlan() else {
            throw AudioNormalizationError.toolUnavailable
        }

        try createParentDirectoryIfNeeded(for: outputURL)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        switch plan.tool {
        case .ffmpeg:
            _ = try executor.run(
                executableURL: plan.executableURL,
                arguments: [
                    "-y",
                    "-i", inputURL.path,
                    "-map", "0:a:0",
                    "-ac", "1",
                    "-ar", "16000",
                    "-c:a", "pcm_s16le",
                    outputURL.path
                ],
                environment: environment,
                currentDirectoryURL: outputURL.deletingLastPathComponent()
            )
        case .afconvert:
            _ = try executor.run(
                executableURL: plan.executableURL,
                arguments: [
                    inputURL.path,
                    "-o", outputURL.path,
                    "-f", "WAVE",
                    "-d", "LEI16@16000",
                    "-c", "1",
                    "--mix"
                ],
                environment: environment,
                currentDirectoryURL: outputURL.deletingLastPathComponent()
            )
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw AudioNormalizationError.unsupportedInput(inputURL.lastPathComponent)
        }
    }

    private func createParentDirectoryIfNeeded(for outputURL: URL) throws {
        let directoryURL = outputURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: directoryURL.path) {
            return
        }

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }
}
