import Foundation
import OatmealCore

protocol WhisperCPPTranscriptionServing: Sendable {
    func status(configuration: LocalTranscriptionConfiguration, discoveredModels: [ManagedLocalModel]) -> TranscriptionBackendStatus
    func transcribe(
        request: TranscriptionRequest,
        configuration: LocalTranscriptionConfiguration,
        discoveredModels: [ManagedLocalModel]
    ) async throws -> TranscriptionJobResult
}

struct WhisperCPPTranscriptionBackend: WhisperCPPTranscriptionServing {
    private let locator: ExecutableLocator
    private let normalizer: any AudioNormalizing
    private let executor: any ProcessExecuting
    private let environment: [String: String]

    init(
        locator: ExecutableLocator = ExecutableLocator(),
        normalizer: some AudioNormalizing = AudioNormalizationService(),
        executor: some ProcessExecuting = ProcessExecutor(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.locator = locator
        self.normalizer = normalizer
        self.executor = executor
        self.environment = environment
    }

    func status(configuration: LocalTranscriptionConfiguration, discoveredModels: [ManagedLocalModel]) -> TranscriptionBackendStatus {
        let policyDecision = LanguagePolicy.decide(
            configuredLocale: configuration.preferredLocaleIdentifier,
            discoveredModels: discoveredModels,
            activeBackend: configuration.preferredBackend
        )
        let installation = installationState(
            discoveredModels: discoveredModels,
            policyModel: policyDecision.modelToUse,
            blockingReason: policyDecision.blockingReason
        )
        return TranscriptionBackendStatus(
            backend: .whisperCPPCLI,
            displayName: "whisper.cpp",
            availability: installation.availability,
            detail: installation.detail,
            isRunnable: installation.isRunnable
        )
    }

    func transcribe(
        request: TranscriptionRequest,
        configuration: LocalTranscriptionConfiguration,
        discoveredModels: [ManagedLocalModel]
    ) async throws -> TranscriptionJobResult {
        guard FileManager.default.fileExists(atPath: request.audioFileURL.path) else {
            throw TranscriptionPipelineError.fileNotFound
        }

        let policyDecision = LanguagePolicy.decide(
            configuredLocale: request.preferredLocaleIdentifier,
            discoveredModels: discoveredModels,
            activeBackend: configuration.preferredBackend
        )

        if let blockingReason = policyDecision.blockingReason {
            throw TranscriptionPipelineError.backendUnavailable(blockingReason)
        }

        let installation = installationState(
            discoveredModels: discoveredModels,
            policyModel: policyDecision.modelToUse,
            blockingReason: policyDecision.blockingReason
        )
        guard let executableURL = installation.executableURL else {
            throw TranscriptionPipelineError.backendUnavailable(installation.detail)
        }
        guard let model = installation.model else {
            throw TranscriptionPipelineError.backendUnavailable(installation.detail)
        }
        guard let normalizationPlan = installation.normalizationPlan else {
            throw TranscriptionPipelineError.backendUnavailable(installation.detail)
        }

        let jobDirectoryURL = try makeJobDirectory()
        // The job directory holds whisper.cpp's intermediate JSON output. The
        // normalized WAV lives outside this directory when the caller supplied
        // a stable retention path so deleting the job directory after the run
        // does not destroy the artifact reused for re-transcribe.
        defer {
            try? FileManager.default.removeItem(at: jobDirectoryURL)
        }
        let normalizedURL = request.normalizedOutputURL ?? jobDirectoryURL.appendingPathComponent("normalized.wav")
        let outputPrefixURL = jobDirectoryURL.appendingPathComponent("transcript")

        try normalizer.normalize(inputURL: request.audioFileURL, outputURL: normalizedURL)

        let threadCount = String(max(1, min(ProcessInfo.processInfo.activeProcessorCount, 8)))
        _ = try executor.run(
            executableURL: executableURL,
            arguments: [
                "-m", model.fileURL.path,
                "-f", normalizedURL.path,
                "-ojf",
                "-of", outputPrefixURL.path,
                "-l", policyDecision.whisperLanguageArg,
                "-t", threadCount,
                "-np"
            ],
            environment: environment,
            currentDirectoryURL: jobDirectoryURL
        )

        let jsonURL = outputPrefixURL.appendingPathExtension("json")
        guard FileManager.default.fileExists(atPath: jsonURL.path) else {
            throw TranscriptionPipelineError.transcriptionFailed("whisper.cpp completed without producing a JSON transcript.")
        }

        let jsonData = try Data(contentsOf: jsonURL)
        let parseResult = try WhisperJSONParser.parse(data: jsonData, startedAt: request.startedAt)

        // If whisper.cpp's JSON did not surface a detected language (older
        // builds, or a `-l auto` run that resolved to silence), fall back to
        // the policy's configured argument when it is a real language code.
        let detectedLanguage = parseResult.detectedLanguage ?? {
            let arg = policyDecision.whisperLanguageArg
            return arg == "auto" ? nil : arg
        }()

        return TranscriptionJobResult(
            segments: parseResult.segments,
            backend: .whisperCPPCLI,
            executionKind: .local,
            warningMessages: [
                "Transcribed locally with whisper.cpp using \(model.displayName) after normalizing audio with \(normalizationPlan.tool.displayName)."
            ],
            detectedLanguage: detectedLanguage
        )
    }

    private func installationState(
        discoveredModels: [ManagedLocalModel],
        policyModel: ManagedLocalModel? = nil,
        blockingReason: String? = nil
    ) -> WhisperInstallationState {
        let executableURL = locator.locate(
            envKey: "OATMEAL_WHISPER_BINARY_PATH",
            candidateNames: ["whisper-cli", "whisper-cpp"],
            fallbackAbsolutePaths: [
                "/opt/homebrew/bin/whisper-cli",
                "/opt/homebrew/bin/whisper-cpp",
                "/usr/local/bin/whisper-cli",
                "/usr/local/bin/whisper-cpp"
            ]
        )

        let normalizationPlan = normalizer.availablePlan()
        let model = policyModel ?? discoveredModels.first

        let detailParts = [
            executableURL == nil ? "Install or point Oatmeal at a `whisper.cpp` CLI binary via `OATMEAL_WHISPER_BINARY_PATH`." : nil,
            model == nil ? "Add a Whisper model file to Oatmeal's Models folder or set `OATMEAL_WHISPER_MODEL_PATH`." : nil,
            normalizationPlan == nil ? "Install `ffmpeg` or make `afconvert` available so Oatmeal can normalize recordings to 16 kHz WAV." : nil
        ].compactMap { $0 }

        // Prepend the language policy's blocking reason so it leads the
        // user-facing detail. Phase 5's curated catalog UI will turn this
        // string into a button; until then, surfacing it via the existing
        // detail mechanism is enough to make it visible.
        let blockingPrefix: String? = (blockingReason?.isEmpty == false) ? blockingReason : nil

        if detailParts.isEmpty, let executableURL, let model, let normalizationPlan {
            let baseDetail = "Ready to run locally with \(executableURL.lastPathComponent), model \(model.displayName), and \(normalizationPlan.tool.displayName) audio normalization."
            if let blockingPrefix {
                return WhisperInstallationState(
                    executableURL: executableURL,
                    model: model,
                    normalizationPlan: normalizationPlan,
                    availability: .unavailable,
                    detail: "\(blockingPrefix) \(baseDetail)"
                )
            }
            return WhisperInstallationState(
                executableURL: executableURL,
                model: model,
                normalizationPlan: normalizationPlan,
                availability: .available,
                detail: baseDetail
            )
        }

        let combinedDetail: String = {
            let installationDetail = detailParts.joined(separator: " ")
            switch (blockingPrefix, installationDetail.isEmpty) {
            case let (reason?, false):
                return "\(reason) \(installationDetail)"
            case let (reason?, true):
                return reason
            case (nil, _):
                return installationDetail
            }
        }()

        return WhisperInstallationState(
            executableURL: executableURL,
            model: model,
            normalizationPlan: normalizationPlan,
            availability: .unavailable,
            detail: combinedDetail
        )
    }

    private func makeJobDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("oatmeal-whisper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }
}

private struct WhisperInstallationState: Equatable {
    let executableURL: URL?
    let model: ManagedLocalModel?
    let normalizationPlan: AudioNormalizationPlan?
    let availability: TranscriptionRuntimeAvailability
    let detail: String

    var isRunnable: Bool {
        executableURL != nil && model != nil && normalizationPlan != nil
    }
}
