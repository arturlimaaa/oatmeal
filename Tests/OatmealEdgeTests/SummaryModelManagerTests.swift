import Foundation
@testable import OatmealEdge
import XCTest

final class SummaryModelManagerTests: XCTestCase {
    func testCatalogStateMarksInstalledCuratedModelsAndDownloadRuntimeReady() async throws {
        let baseURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: baseURL) }

        let entry = fixtureCatalogEntry()
        try makeExecutable(at: MLXRuntimeEnvironment.defaultManagedPythonURL(baseURL: baseURL))
        try createModelFixture(
            at: baseURL
                .appendingPathComponent("Models", isDirectory: true)
                .appendingPathComponent("Summaries", isDirectory: true)
                .appendingPathComponent(entry.suggestedDirectoryName, isDirectory: true)
        )

        let manager = LocalSummaryModelManager(
            applicationSupportDirectoryURL: baseURL,
            catalog: [entry],
            executableLocator: ExecutableLocator(environment: ["PATH": "/usr/bin:/bin"]),
            processExecutor: SuccessfulProcessExecutor()
        )

        let state = await manager.catalogState()

        XCTAssertEqual(state.downloadAvailability, .available)
        XCTAssertEqual(state.items.count, 1)
        XCTAssertEqual(state.items.first?.installedModel?.directoryURL.lastPathComponent, entry.suggestedDirectoryName)
    }

    func testInstallUsesManagedPythonAndCreatesModelDirectory() async throws {
        let baseURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: baseURL) }

        let entry = fixtureCatalogEntry()
        let managedPythonURL = MLXRuntimeEnvironment.defaultManagedPythonURL(baseURL: baseURL)
        try makeExecutable(at: managedPythonURL)
        let processExecutor = InstallingProcessExecutor()

        let manager = LocalSummaryModelManager(
            applicationSupportDirectoryURL: baseURL,
            catalog: [entry],
            executableLocator: ExecutableLocator(environment: ["PATH": "/usr/bin:/bin"]),
            processExecutor: processExecutor
        )

        let state = try await manager.install(modelID: entry.id, forceRedownload: false)

        XCTAssertGreaterThanOrEqual(processExecutor.invocations.count, 1)
        XCTAssertTrue(processExecutor.invocations.allSatisfy { $0 == managedPythonURL.path })
        XCTAssertEqual(state.items.first?.installedModel?.directoryURL.lastPathComponent, entry.suggestedDirectoryName)
    }

    func testRemoveDeletesInstalledModelDirectory() async throws {
        let baseURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: baseURL) }

        let entry = fixtureCatalogEntry()
        try makeExecutable(at: MLXRuntimeEnvironment.defaultManagedPythonURL(baseURL: baseURL))
        let modelDirectoryURL = baseURL
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("Summaries", isDirectory: true)
            .appendingPathComponent(entry.suggestedDirectoryName, isDirectory: true)
        try createModelFixture(at: modelDirectoryURL)

        let manager = LocalSummaryModelManager(
            applicationSupportDirectoryURL: baseURL,
            catalog: [entry],
            executableLocator: ExecutableLocator(environment: ["PATH": "/usr/bin:/bin"]),
            processExecutor: SuccessfulProcessExecutor()
        )

        let state = try await manager.remove(modelDirectoryURL: modelDirectoryURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: modelDirectoryURL.path))
        XCTAssertNil(state.items.first?.installedModel)
    }

    private func fixtureCatalogEntry() -> SummaryModelCatalogEntry {
        SummaryModelCatalogEntry(
            id: "fixture-model",
            displayName: "Fixture Model",
            repositoryID: "mlx-community/fixture-model",
            suggestedDirectoryName: "FixtureModel",
            summary: "Fixture",
            footprintDescription: "Tiny"
        )
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeExecutable(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func createModelFixture(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: url.appendingPathComponent("config.json", isDirectory: false))
        try Data("{}".utf8).write(to: url.appendingPathComponent("tokenizer.json", isDirectory: false))
        try Data("weights".utf8).write(to: url.appendingPathComponent("model.safetensors", isDirectory: false))
    }
}

private final class SuccessfulProcessExecutor: @unchecked Sendable, ProcessExecuting {
    func run(
        executableURL _: URL,
        arguments _: [String],
        environment _: [String: String],
        currentDirectoryURL _: URL?
    ) throws -> ProcessExecutionResult {
        ProcessExecutionResult(
            terminationStatus: 0,
            standardOutput: "",
            standardError: ""
        )
    }
}

private final class InstallingProcessExecutor: @unchecked Sendable, ProcessExecuting {
    private(set) var invocations: [String] = []

    func run(
        executableURL: URL,
        arguments: [String],
        environment _: [String: String],
        currentDirectoryURL _: URL?
    ) throws -> ProcessExecutionResult {
        invocations.append(executableURL.path)

        if let outputIndex = arguments.firstIndex(of: "--output-dir"), arguments.indices.contains(outputIndex + 1) {
            let outputURL = URL(fileURLWithPath: arguments[outputIndex + 1], isDirectory: true)
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: outputURL.appendingPathComponent("config.json", isDirectory: false))
            try Data("{}".utf8).write(to: outputURL.appendingPathComponent("tokenizer.json", isDirectory: false))
            try Data("weights".utf8).write(to: outputURL.appendingPathComponent("model.safetensors", isDirectory: false))
        }

        return ProcessExecutionResult(
            terminationStatus: 0,
            standardOutput: "",
            standardError: ""
        )
    }
}
