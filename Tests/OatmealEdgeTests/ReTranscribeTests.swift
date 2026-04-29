import Foundation
import OatmealCore
@testable import OatmealEdge
import XCTest

/// Integration coverage for the re-transcribe API on `LocalTranscriptionPipeline`.
///
/// The tests use `LanguageStubBackend` (a `MockTranscriptionServing` adaptor
/// that lets each invocation observe its incoming locale) to verify that the
/// caller-supplied language threads through to the active backend, that the
/// retained WAV path is reused across attempts, and that the missing-file
/// case reports `TranscriptionPipelineError.fileNotFound`.
final class ReTranscribeTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReTranscribeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root = temporaryRoot, FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        temporaryRoot = nil
        try super.tearDownWithError()
    }

    func testReTranscribeReusesRetainedWAVAndOverridesLanguage() async throws {
        let inventoryDir = temporaryRoot.appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: inventoryDir, withIntermediateDirectories: true)

        let retainedWAVURL = temporaryRoot.appendingPathComponent("retained-\(UUID().uuidString).wav")
        try Data("PCMfixture".utf8).write(to: retainedWAVURL)

        let mock = LanguageStubBackend(detectedLanguage: nil)
        let pipeline = LocalTranscriptionPipeline(
            inventory: LocalModelInventory(modelsDirectoryURL: inventoryDir),
            whisper: LanguageStubWhisperBackend(),
            appleSpeech: LanguageStubSpeechBackend(),
            mock: mock
        )

        // First pass: configuration is on auto-detect, mock backend is the
        // resolved plan because no Whisper or Speech runtime is available.
        let firstResult = try await pipeline.transcribe(
            request: TranscriptionRequest(
                audioFileURL: retainedWAVURL,
                preferredLocaleIdentifier: nil
            ),
            configuration: LocalTranscriptionConfiguration(
                preferredBackend: .mock,
                executionPolicy: .allowSystemFallback,
                preferredLocaleIdentifier: nil
            )
        )
        XCTAssertEqual(firstResult.backend, .mock)

        // Re-transcribe with an explicit language override.
        let secondResult = try await pipeline.reTranscribe(
            noteID: UUID(),
            language: "es",
            retainedWAVURL: retainedWAVURL,
            configuration: LocalTranscriptionConfiguration(
                preferredBackend: .mock,
                executionPolicy: .allowSystemFallback,
                preferredLocaleIdentifier: nil
            )
        )

        XCTAssertEqual(secondResult.backend, .mock)
        let observedLocales = await mock.observedLocales
        XCTAssertEqual(observedLocales.count, 2)
        XCTAssertNil(observedLocales.first ?? "")
        XCTAssertEqual(observedLocales.last ?? nil, "es")

        // Both calls used the same retained WAV path.
        let observedURLs = await mock.observedAudioFileURLs
        XCTAssertEqual(observedURLs.count, 2)
        XCTAssertEqual(observedURLs[0], retainedWAVURL)
        XCTAssertEqual(observedURLs[1], retainedWAVURL)
    }

    func testReTranscribeThrowsFileNotFoundWhenWAVDoesNotExist() async throws {
        let inventoryDir = temporaryRoot.appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: inventoryDir, withIntermediateDirectories: true)

        let pipeline = LocalTranscriptionPipeline(
            inventory: LocalModelInventory(modelsDirectoryURL: inventoryDir),
            whisper: LanguageStubWhisperBackend(),
            appleSpeech: LanguageStubSpeechBackend(),
            mock: LanguageStubBackend(detectedLanguage: nil)
        )

        let absentWAV = temporaryRoot.appendingPathComponent("missing-\(UUID().uuidString).wav")
        XCTAssertFalse(FileManager.default.fileExists(atPath: absentWAV.path))

        do {
            _ = try await pipeline.reTranscribe(
                noteID: UUID(),
                language: "es",
                retainedWAVURL: absentWAV,
                configuration: .default
            )
            XCTFail("Expected reTranscribe to throw fileNotFound when the retained WAV is missing.")
        } catch let error as TranscriptionPipelineError {
            XCTAssertEqual(error, .fileNotFound)
        }
    }
}

// MARK: - Stubs

/// Tracks both the audio file URLs and the locale identifiers each call sees
/// so the re-transcribe test can assert that the same retained WAV was used
/// twice with different languages.
private actor LanguageStubBackend: MockTranscriptionServing {
    private(set) var observedLocales: [String?] = []
    private(set) var observedAudioFileURLs: [URL] = []
    private let detectedLanguage: String?

    init(detectedLanguage: String?) {
        self.detectedLanguage = detectedLanguage
    }

    func transcribe(request: TranscriptionRequest) async throws -> TranscriptionJobResult {
        observedLocales.append(request.preferredLocaleIdentifier)
        observedAudioFileURLs.append(request.audioFileURL)
        return TranscriptionJobResult(
            segments: [TranscriptSegment(text: "stub")],
            backend: .mock,
            executionKind: .placeholder,
            warningMessages: [],
            detectedLanguage: detectedLanguage
        )
    }
}

private struct LanguageStubWhisperBackend: WhisperCPPTranscriptionServing {
    func status(
        configuration _: LocalTranscriptionConfiguration,
        discoveredModels _: [ManagedLocalModel]
    ) -> TranscriptionBackendStatus {
        TranscriptionBackendStatus(
            backend: .whisperCPPCLI,
            displayName: "whisper.cpp",
            availability: .unavailable,
            detail: "Stub Whisper backend reports unavailable.",
            isRunnable: false
        )
    }

    func transcribe(
        request _: TranscriptionRequest,
        configuration _: LocalTranscriptionConfiguration,
        discoveredModels _: [ManagedLocalModel]
    ) async throws -> TranscriptionJobResult {
        throw TranscriptionPipelineError.backendUnavailable("Stub Whisper unavailable")
    }
}

private struct LanguageStubSpeechBackend: AppleSpeechTranscriptionServing {
    func status(preferredLocaleIdentifier _: String?) -> TranscriptionBackendStatus {
        TranscriptionBackendStatus(
            backend: .appleSpeech,
            displayName: "Apple Speech",
            availability: .unavailable,
            detail: "Stub Apple Speech backend reports unavailable.",
            isRunnable: false
        )
    }

    func transcribe(request _: TranscriptionRequest) async throws -> TranscriptionJobResult {
        throw TranscriptionPipelineError.speechRecognizerUnavailable("Stub Apple Speech unavailable")
    }
}
