import Foundation

struct ProcessExecutionResult: Equatable, Sendable {
    let terminationStatus: Int32
    let standardOutput: String
    let standardError: String
}

enum ProcessExecutionError: LocalizedError, Equatable {
    case executableNotFound(String)
    case failedToLaunch(String)
    case nonZeroExit(executable: String, status: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case let .executableNotFound(executable):
            return "Required executable was not found: \(executable)"
        case let .failedToLaunch(message):
            return "Unable to launch external process: \(message)"
        case let .nonZeroExit(executable, status, message):
            let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedMessage.isEmpty {
                return "\(executable) exited with status \(status)."
            }
            return "\(executable) exited with status \(status): \(trimmedMessage)"
        }
    }
}

protocol ProcessExecuting: Sendable {
    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectoryURL: URL?
    ) throws -> ProcessExecutionResult
}

struct ProcessExecutor: ProcessExecuting {
    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectoryURL: URL? = nil
    ) throws -> ProcessExecutionResult {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw ProcessExecutionError.executableNotFound(executableURL.path)
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = currentDirectoryURL
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw ProcessExecutionError.failedToLaunch(error.localizedDescription)
        }

        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let standardOutput = String(decoding: outputData, as: UTF8.self)
        let standardError = String(decoding: errorData, as: UTF8.self)

        let result = ProcessExecutionResult(
            terminationStatus: process.terminationStatus,
            standardOutput: standardOutput,
            standardError: standardError
        )

        guard process.terminationStatus == 0 else {
            throw ProcessExecutionError.nonZeroExit(
                executable: executableURL.lastPathComponent,
                status: process.terminationStatus,
                message: standardError.nilIfBlank ?? standardOutput
            )
        }

        return result
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
