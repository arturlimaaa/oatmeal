import Foundation
import OatmealCore
@testable import OatmealEdge
import XCTest

final class OatmealEdgeTests: XCTestCase {
    func testAutomaticUsesWhisperWhenLocalRuntimeIsRunnable() async throws {
        let tempDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let pipeline = LocalTranscriptionPipeline(
            inventory: LocalModelInventory(modelsDirectoryURL: tempDirectory),
            whisper: StubWhisperBackend(
                reportedStatus: TranscriptionBackendStatus(
                    backend: .whisperCPPCLI,
                    displayName: "whisper.cpp",
                    availability: .available,
                    detail: "Ready.",
                    isRunnable: true
                )
            ),
            appleSpeech: StubSpeechBackend(
                reportedStatus: TranscriptionBackendStatus(
                    backend: .appleSpeech,
                    displayName: "Apple Speech",
                    availability: .available,
                    detail: "Ready.",
                    isRunnable: true
                )
            ),
            mock: StubMockBackend()
        )

        let plan = try await pipeline.executionPlan(configuration: .default)
        XCTAssertEqual(plan.backend, .whisperCPPCLI)
        XCTAssertEqual(plan.executionKind, .local)
    }

    func testAutomaticFallsBackToMockWhenSpeechBackendsAreNotRunnable() async throws {
        let tempDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let pipeline = LocalTranscriptionPipeline(
            inventory: LocalModelInventory(modelsDirectoryURL: tempDirectory),
            whisper: StubWhisperBackend(
                reportedStatus: TranscriptionBackendStatus(
                    backend: .whisperCPPCLI,
                    displayName: "whisper.cpp",
                    availability: .unavailable,
                    detail: "No local runtime.",
                    isRunnable: false
                )
            ),
            appleSpeech: StubSpeechBackend(
                reportedStatus: TranscriptionBackendStatus(
                    backend: .appleSpeech,
                    displayName: "Apple Speech",
                    availability: .unavailable,
                    detail: "Speech auth missing.",
                    isRunnable: false
                )
            ),
            mock: StubMockBackend()
        )

        let plan = try await pipeline.executionPlan(configuration: .default)
        XCTAssertEqual(plan.backend, .mock)
        XCTAssertEqual(plan.executionKind, .placeholder)
    }

    func testRequireLocalFailsWithoutLocalRuntime() async {
        let tempDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let pipeline = LocalTranscriptionPipeline(
            inventory: LocalModelInventory(modelsDirectoryURL: tempDirectory),
            whisper: StubWhisperBackend(
                reportedStatus: TranscriptionBackendStatus(
                    backend: .whisperCPPCLI,
                    displayName: "whisper.cpp",
                    availability: .unavailable,
                    detail: "No local runtime configured.",
                    isRunnable: false
                )
            ),
            appleSpeech: StubSpeechBackend(
                reportedStatus: TranscriptionBackendStatus(
                    backend: .appleSpeech,
                    displayName: "Apple Speech",
                    availability: .available,
                    detail: "Ready.",
                    isRunnable: true
                )
            ),
            mock: StubMockBackend()
        )

        do {
            _ = try await pipeline.executionPlan(
                configuration: LocalTranscriptionConfiguration(
                    preferredBackend: .automatic,
                    executionPolicy: .requireLocal
                )
            )
            XCTFail("Expected requireLocal to fail without a dedicated local runtime.")
        } catch {
            XCTAssertEqual(
                error as? TranscriptionPipelineError,
                .localRuntimeRequired("No local ASR runtime is configured yet, so Oatmeal must fall back to the best available non-local path. No local runtime configured.")
            )
        }
    }

    func testInventoryFindsWhisperModelsInManagedFolder() throws {
        let tempDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let whisperModelURL = tempDirectory.appendingPathComponent("tiny.en.gguf")
        try Data("model".utf8).write(to: whisperModelURL)

        let inventory = LocalModelInventory(modelsDirectoryURL: tempDirectory)
        let models = inventory.discoveredModels()

        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models.first?.kind, .whisper)
        XCTAssertEqual(models.first?.displayName, "tiny.en")
    }

    func testWhisperJSONParserBuildsTimedTranscriptSegments() throws {
        let data = Data(
            """
            {
              "transcription": [
                {
                  "text": " hello world",
                  "offsets": {
                    "from": 1200,
                    "to": 3450
                  },
                  "id": 1,
                  "p": 0.92
                },
                {
                  "text": " second line",
                  "offsets": {
                    "from": 4000,
                    "to": 5200
                  },
                  "id": 2,
                  "p": 0.81
                }
              ]
            }
            """.utf8
        )

        let start = Date(timeIntervalSince1970: 1_000)
        let segments = try WhisperJSONParser.parseTranscriptSegments(data: data, startedAt: start)

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].text, "hello world")
        XCTAssertEqual(segments[0].startTime, start.addingTimeInterval(1.2))
        XCTAssertEqual(segments[0].endTime, start.addingTimeInterval(3.45))
        XCTAssertEqual(segments[0].confidence, 0.92)
    }

    func testAutomaticUsesExtractiveSummaryBackendWhenAvailable() async throws {
        let tempDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let pipeline = LocalSummaryPipeline(
            inventory: SummaryModelInventory(modelsDirectoryURL: tempDirectory),
            mlx: StubMLXSummaryBackend(
                reportedStatus: SummaryBackendStatus(
                    backend: .mlxLocal,
                    displayName: "MLX Local",
                    availability: .unavailable,
                    detail: "MLX unavailable.",
                    isRunnable: false
                )
            ),
            extractive: StubExtractiveSummaryBackend(
                reportedStatus: SummaryBackendStatus(
                    backend: .extractiveLocal,
                    displayName: "Extractive Local",
                    availability: .available,
                    detail: "Ready.",
                    isRunnable: true
                )
            ),
            placeholder: StubPlaceholderSummaryBackend()
        )

        let plan = try await pipeline.executionPlan(configuration: .default)
        XCTAssertEqual(plan.backend, .extractiveLocal)
        XCTAssertEqual(plan.executionKind, .local)
    }

    func testRequireStructuredSummaryFailsWithoutExtractiveRuntime() async {
        let tempDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let pipeline = LocalSummaryPipeline(
            inventory: SummaryModelInventory(modelsDirectoryURL: tempDirectory),
            mlx: StubMLXSummaryBackend(
                reportedStatus: SummaryBackendStatus(
                    backend: .mlxLocal,
                    displayName: "MLX Local",
                    availability: .unavailable,
                    detail: "MLX unavailable.",
                    isRunnable: false
                )
            ),
            extractive: StubExtractiveSummaryBackend(
                reportedStatus: SummaryBackendStatus(
                    backend: .extractiveLocal,
                    displayName: "Extractive Local",
                    availability: .unavailable,
                    detail: "No structured local summary backend is available.",
                    isRunnable: false
                )
            ),
            placeholder: StubPlaceholderSummaryBackend()
        )

        do {
            _ = try await pipeline.executionPlan(
                configuration: LocalSummaryConfiguration(
                    preferredBackend: .extractiveLocal,
                    executionPolicy: .requireStructuredSummary
                )
            )
            XCTFail("Expected the pipeline to require the structured local backend.")
        } catch {
            XCTAssertEqual(
                error as? SummaryPipelineError,
                .localRuntimeRequired("No structured local summary backend is available.")
            )
        }
    }

    func testExtractiveSummaryBuildsStructuredEnhancedNote() async throws {
        let backend = ExtractiveSummaryBackend()
        let request = NoteGenerationRequest(
            noteID: UUID(),
            title: "Launch Review",
            template: .projectReview,
            meetingEvent: nil,
            rawNotes: """
            ### Status
            - Launch checklist reviewed
            - Next step: send the final checklist to ops
            """,
            transcriptSegments: [
                TranscriptSegment(text: "We decided to keep the rollout on Friday."),
                TranscriptSegment(text: "Question: do we need legal sign-off for the email copy?"),
                TranscriptSegment(text: "Action: Maya will send the final checklist to ops.")
            ]
        )

        let result = try await backend.generate(
            request: request,
            configuration: .default
        )

        XCTAssertEqual(result.backend, .extractiveLocal)
        XCTAssertEqual(result.executionKind, .local)
        XCTAssertTrue(result.enhancedNote.summary.contains("Launch Review"))
        XCTAssertTrue(result.enhancedNote.decisions.contains { $0.contains("decided") })
        XCTAssertTrue(result.enhancedNote.risksOrOpenQuestions.contains { $0.contains("Question") || $0.contains("question") })
        XCTAssertTrue(result.enhancedNote.actionItems.contains { $0.text.localizedCaseInsensitiveContains("checklist") })
        XCTAssertFalse(result.enhancedNote.citations.isEmpty)
    }

    func testMLXBackendPrefersManagedPythonOverPATH() throws {
        let tempDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let managedPythonURL = tempDirectory.appendingPathComponent("python3", isDirectory: false)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: managedPythonURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: managedPythonURL.path)

        let processExecutor = RecordingProcessExecutor()
        let backend = MLXSummaryBackend(
            executableLocator: ExecutableLocator(environment: ["PATH": "/usr/bin:/bin"]),
            processExecutor: processExecutor,
            managedPythonURL: managedPythonURL
        )

        let status = backend.status(
            configuration: LocalSummaryConfiguration(
                preferredBackend: .mlxLocal,
                executionPolicy: .allowFallback,
                preferredModelName: "Managed Test Model"
            ),
            discoveredModels: [
                ManagedSummaryModel(
                    displayName: "Managed Test Model",
                    directoryURL: tempDirectory.appendingPathComponent("Managed Test Model", isDirectory: true)
                )
            ]
        )

        XCTAssertEqual(status.backend, .mlxLocal)
        XCTAssertEqual(status.availability, .available)
        XCTAssertTrue(status.isRunnable)
        XCTAssertEqual(processExecutor.invocations, [managedPythonURL.path])
    }

    func testWhisperCPPBackendSmokeTestWhenRuntimeAndFixtureArePresent() async throws {
        let environment = ProcessInfo.processInfo.environment
        let recordingPath = environment["OATMEAL_EDGE_SMOKE_RECORDING_PATH"]
        let modelPath = environment["OATMEAL_EDGE_SMOKE_MODEL_PATH"]
            ?? NSHomeDirectory() + "/Library/Application Support/Oatmeal/Models/ggml-base.en.bin"

        guard let recordingPath else {
            throw XCTSkip("Set OATMEAL_EDGE_SMOKE_RECORDING_PATH to run the whisper.cpp smoke test.")
        }

        guard FileManager.default.fileExists(atPath: recordingPath) else {
            throw XCTSkip("Configured smoke-test recording does not exist: \(recordingPath)")
        }

        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw XCTSkip("Configured smoke-test model does not exist: \(modelPath)")
        }

        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/whisper-cli")
            || FileManager.default.isExecutableFile(atPath: "/usr/local/bin/whisper-cli") else {
            throw XCTSkip("whisper.cpp CLI is not installed for the smoke test.")
        }

        let backend = WhisperCPPTranscriptionBackend()
        let request = TranscriptionRequest(
            audioFileURL: URL(fileURLWithPath: recordingPath),
            startedAt: Date(timeIntervalSince1970: 0),
            preferredLocaleIdentifier: "en_US"
        )
        let result = try await backend.transcribe(
            request: request,
            configuration: LocalTranscriptionConfiguration(
                preferredBackend: .whisperCPPCLI,
                executionPolicy: .requireLocal,
                preferredLocaleIdentifier: "en_US"
            ),
            discoveredModels: [
                ManagedLocalModel(
                    kind: .whisper,
                    displayName: "ggml-base.en",
                    fileURL: URL(fileURLWithPath: modelPath)
                )
            ]
        )

        XCTAssertEqual(result.backend, .whisperCPPCLI)
        XCTAssertEqual(result.executionKind, .local)
        XCTAssertFalse(result.segments.isEmpty)
        XCTAssertFalse(result.segments.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private struct StubWhisperBackend: WhisperCPPTranscriptionServing {
    let reportedStatus: TranscriptionBackendStatus

    func status(configuration: LocalTranscriptionConfiguration, discoveredModels: [ManagedLocalModel]) -> TranscriptionBackendStatus {
        reportedStatus
    }

    func transcribe(
        request: TranscriptionRequest,
        configuration: LocalTranscriptionConfiguration,
        discoveredModels: [ManagedLocalModel]
    ) async throws -> TranscriptionJobResult {
        TranscriptionJobResult(
            segments: [
                TranscriptSegment(text: "Local whisper output")
            ],
            backend: .whisperCPPCLI,
            executionKind: .local
        )
    }
}

private struct StubSpeechBackend: AppleSpeechTranscriptionServing {
    let reportedStatus: TranscriptionBackendStatus

    func status(preferredLocaleIdentifier: String?) -> TranscriptionBackendStatus {
        reportedStatus
    }

    func transcribe(request: TranscriptionRequest) async throws -> TranscriptionJobResult {
        TranscriptionJobResult(
            segments: [
                TranscriptSegment(text: "Speech output")
            ],
            backend: .appleSpeech,
            executionKind: .systemService
        )
    }
}

private struct StubMockBackend: MockTranscriptionServing {
    func transcribe(request: TranscriptionRequest) async throws -> TranscriptionJobResult {
        TranscriptionJobResult(
            segments: [
                TranscriptSegment(text: "Mock output")
            ],
            backend: .mock,
            executionKind: .placeholder
        )
    }
}

private struct StubMLXSummaryBackend: MLXSummaryServing {
    let reportedStatus: SummaryBackendStatus
    var shouldThrow = false

    func status(
        configuration: LocalSummaryConfiguration,
        discoveredModels: [ManagedSummaryModel]
    ) -> SummaryBackendStatus {
        reportedStatus
    }

    func generate(
        request: NoteGenerationRequest,
        configuration: LocalSummaryConfiguration,
        discoveredModels: [ManagedSummaryModel]
    ) async throws -> SummaryJobResult {
        if shouldThrow {
            throw SummaryPipelineError.generationFailed("Stub MLX failure")
        }

        return SummaryJobResult(
            enhancedNote: EnhancedNote(
                generatedAt: Date(),
                templateID: request.template.id,
                summary: "MLX summary for \(request.title)"
            ),
            backend: .mlxLocal,
            executionKind: .local
        )
    }
}

private struct StubExtractiveSummaryBackend: ExtractiveSummaryServing {
    let reportedStatus: SummaryBackendStatus
    var shouldThrow = false

    func status(configuration: LocalSummaryConfiguration) -> SummaryBackendStatus {
        reportedStatus
    }

    func generate(
        request: NoteGenerationRequest,
        configuration: LocalSummaryConfiguration
    ) async throws -> SummaryJobResult {
        if shouldThrow {
            throw SummaryPipelineError.generationFailed("Stub extractive failure")
        }

        return SummaryJobResult(
            enhancedNote: EnhancedNote(
                generatedAt: Date(),
                templateID: request.template.id,
                summary: "Extractive summary for \(request.title)"
            ),
            backend: .extractiveLocal,
            executionKind: .local
        )
    }
}

private struct StubPlaceholderSummaryBackend: PlaceholderSummaryServing {
    func status() -> SummaryBackendStatus {
        SummaryBackendStatus(
            backend: .placeholder,
            displayName: "Placeholder",
            availability: .available,
            detail: "Ready.",
            isRunnable: true
        )
    }

    func generate(request: NoteGenerationRequest) async throws -> SummaryJobResult {
        SummaryJobResult(
            enhancedNote: EnhancedNote(
                generatedAt: Date(),
                templateID: request.template.id,
                summary: "Placeholder summary"
            ),
            backend: .placeholder,
            executionKind: .placeholder
        )
    }
}

private final class RecordingProcessExecutor: @unchecked Sendable, ProcessExecuting {
    private(set) var invocations: [String] = []

    func run(
        executableURL: URL,
        arguments _: [String],
        environment _: [String: String],
        currentDirectoryURL _: URL?
    ) throws -> ProcessExecutionResult {
        invocations.append(executableURL.path)
        return ProcessExecutionResult(
            terminationStatus: 0,
            standardOutput: "",
            standardError: ""
        )
    }
}
