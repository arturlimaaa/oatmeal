import Foundation
import OatmealCore

public protocol LocalTranscriptionServicing: Sendable {
    func runtimeState(configuration: LocalTranscriptionConfiguration) async -> LocalTranscriptionRuntimeState
    func executionPlan(configuration: LocalTranscriptionConfiguration) async throws -> TranscriptionExecutionPlan
    func transcribe(request: TranscriptionRequest, configuration: LocalTranscriptionConfiguration) async throws -> TranscriptionJobResult
}

public final class LocalTranscriptionPipeline: LocalTranscriptionServicing, @unchecked Sendable {
    private let inventory: LocalModelInventory
    private let whisper: any WhisperCPPTranscriptionServing
    private let appleSpeech: any AppleSpeechTranscriptionServing
    private let mock: any MockTranscriptionServing

    public init(applicationSupportDirectoryURL: URL) {
        self.inventory = LocalModelInventory(
            modelsDirectoryURL: applicationSupportDirectoryURL.appendingPathComponent("Models", isDirectory: true)
        )
        self.whisper = WhisperCPPTranscriptionBackend()
        self.appleSpeech = AppleSpeechTranscriptionBackend()
        self.mock = MockTranscriptionBackend()
    }

    init(
        inventory: LocalModelInventory,
        whisper: some WhisperCPPTranscriptionServing = WhisperCPPTranscriptionBackend(),
        appleSpeech: some AppleSpeechTranscriptionServing,
        mock: some MockTranscriptionServing
    ) {
        self.inventory = inventory
        self.whisper = whisper
        self.appleSpeech = appleSpeech
        self.mock = mock
    }

    public func runtimeState(configuration: LocalTranscriptionConfiguration) async -> LocalTranscriptionRuntimeState {
        let discoveredModels = inventory.discoveredModels()
        let whisperStatus = whisper.status(configuration: configuration, discoveredModels: discoveredModels)
        let appleSpeechStatus = appleSpeech.status(preferredLocaleIdentifier: configuration.preferredLocaleIdentifier)
        let backends = [
            whisperStatus,
            appleSpeechStatus,
            TranscriptionBackendStatus(
                backend: .mock,
                displayName: "Placeholder",
                availability: .available,
                detail: "Deterministic development transcript that keeps the app usable when no real backend can run.",
                isRunnable: true
            )
        ]

        let activePlanSummary: String
        do {
            activePlanSummary = try resolvePlan(
                configuration: configuration,
                whisperStatus: whisperStatus,
                appleSpeechStatus: appleSpeechStatus,
                discoveredModels: discoveredModels
            ).summary
        } catch {
            activePlanSummary = error.localizedDescription
        }

        return LocalTranscriptionRuntimeState(
            modelsDirectoryURL: inventory.modelsDirectoryURL,
            discoveredModels: discoveredModels,
            backends: backends,
            activePlanSummary: activePlanSummary
        )
    }

    public func executionPlan(configuration: LocalTranscriptionConfiguration) async throws -> TranscriptionExecutionPlan {
        let discoveredModels = inventory.discoveredModels()
        let whisperStatus = whisper.status(configuration: configuration, discoveredModels: discoveredModels)
        let appleSpeechStatus = appleSpeech.status(preferredLocaleIdentifier: configuration.preferredLocaleIdentifier)
        return try resolvePlan(
            configuration: configuration,
            whisperStatus: whisperStatus,
            appleSpeechStatus: appleSpeechStatus,
            discoveredModels: discoveredModels
        )
    }

    public func transcribe(
        request: TranscriptionRequest,
        configuration: LocalTranscriptionConfiguration
    ) async throws -> TranscriptionJobResult {
        let plan = try await executionPlan(configuration: configuration)
        let discoveredModels = inventory.discoveredModels()
        let appleSpeechStatus = appleSpeech.status(preferredLocaleIdentifier: configuration.preferredLocaleIdentifier)

        switch plan.backend {
        case .whisperCPPCLI:
            do {
                let result = try await whisper.transcribe(
                    request: request,
                    configuration: configuration,
                    discoveredModels: discoveredModels
                )
                return merge(planWarnings: plan.warningMessages, into: result)
            } catch {
                guard configuration.executionPolicy != .requireLocal else {
                    throw error
                }

                if appleSpeechStatus.isRunnable {
                    let fallback = try await appleSpeech.transcribe(request: request)
                    return merge(
                        planWarnings: plan.warningMessages + [
                            "whisper.cpp failed and Oatmeal fell back to Apple Speech: \(error.localizedDescription)"
                        ],
                        into: fallback
                    )
                }

                let fallback = try await mock.transcribe(request: request)
                return merge(
                    planWarnings: plan.warningMessages + [
                        "whisper.cpp failed and Oatmeal fell back to the placeholder transcript: \(error.localizedDescription)"
                    ],
                    into: fallback
                )
            }
        case .appleSpeech:
            do {
                let result = try await appleSpeech.transcribe(request: request)
                return merge(planWarnings: plan.warningMessages, into: result)
            } catch {
                guard configuration.preferredBackend == .automatic,
                      configuration.executionPolicy != .requireLocal else {
                    throw error
                }

                let fallback = try await mock.transcribe(request: request)
                return merge(
                    planWarnings: plan.warningMessages + [
                        "Apple Speech failed and Oatmeal fell back to the placeholder transcript: \(error.localizedDescription)"
                    ],
                    into: fallback
                )
            }
        case .mock:
            let result = try await mock.transcribe(request: request)
            return merge(planWarnings: plan.warningMessages, into: result)
        }
    }

    private func resolvePlan(
        configuration: LocalTranscriptionConfiguration,
        whisperStatus: TranscriptionBackendStatus,
        appleSpeechStatus: TranscriptionBackendStatus,
        discoveredModels: [ManagedLocalModel]
    ) throws -> TranscriptionExecutionPlan {
        let localRuntimeMessage = discoveredModels.isEmpty
            ? "No local ASR runtime is configured yet, so Oatmeal must fall back to the best available non-local path."
            : "Local Whisper model files are present."

        switch configuration.preferredBackend {
        case .automatic:
            if whisperStatus.isRunnable {
                return TranscriptionExecutionPlan(
                    backend: .whisperCPPCLI,
                    executionKind: .local,
                    summary: "Automatic will use whisper.cpp for fully local transcription.",
                    warningMessages: []
                )
            }

            if configuration.executionPolicy == .requireLocal {
                throw TranscriptionPipelineError.localRuntimeRequired(
                    "\(localRuntimeMessage) \(whisperStatus.detail)".trimmingCharacters(in: .whitespaces)
                )
            }

            if appleSpeechStatus.isRunnable {
                var warnings = [
                    localRuntimeMessage,
                    "Apple Speech on macOS 15 does not guarantee on-device execution for every locale."
                ]
                if appleSpeechStatus.availability == .degraded {
                    warnings.append(appleSpeechStatus.detail)
                }
                if !whisperStatus.detail.isEmpty {
                    warnings.append(whisperStatus.detail)
                }

                return TranscriptionExecutionPlan(
                    backend: .appleSpeech,
                    executionKind: .systemService,
                    summary: "Automatic will use Apple Speech until a dedicated local ASR runtime is configured.",
                    warningMessages: warnings
                )
            }

            return TranscriptionExecutionPlan(
                backend: .mock,
                executionKind: .placeholder,
                summary: "Automatic will use the placeholder transcript path because no runnable speech backend is available.",
                warningMessages: [localRuntimeMessage, whisperStatus.detail, appleSpeechStatus.detail]
            )

        case .whisperCPPCLI:
            if whisperStatus.isRunnable {
                return TranscriptionExecutionPlan(
                    backend: .whisperCPPCLI,
                    executionKind: .local,
                    summary: "whisper.cpp is the active local transcription backend.",
                    warningMessages: []
                )
            }

            if configuration.executionPolicy == .requireLocal {
                throw TranscriptionPipelineError.localRuntimeRequired(whisperStatus.detail)
            }

            if appleSpeechStatus.isRunnable {
                return TranscriptionExecutionPlan(
                    backend: .appleSpeech,
                    executionKind: .systemService,
                    summary: "whisper.cpp is unavailable, so Oatmeal will fall back to Apple Speech.",
                    warningMessages: [
                        whisperStatus.detail,
                        "Apple Speech on macOS 15 may use network-backed recognition."
                    ]
                )
            }

            return TranscriptionExecutionPlan(
                backend: .mock,
                executionKind: .placeholder,
                summary: "whisper.cpp is unavailable, so Oatmeal will use the placeholder transcript path.",
                warningMessages: [
                    whisperStatus.detail,
                    "Placeholder transcripts are deterministic mock output, not real speech recognition."
                ]
            )

        case .appleSpeech:
            guard appleSpeechStatus.isRunnable else {
                throw TranscriptionPipelineError.backendUnavailable(appleSpeechStatus.detail)
            }

            return TranscriptionExecutionPlan(
                backend: .appleSpeech,
                executionKind: .systemService,
                summary: "Apple Speech is the active transcription backend.",
                warningMessages: [
                    "Apple Speech on macOS 15 may use network-backed recognition."
                ]
            )

        case .mock:
            return TranscriptionExecutionPlan(
                backend: .mock,
                executionKind: .placeholder,
                summary: "Placeholder transcription is explicitly selected.",
                warningMessages: [
                    "Placeholder transcripts are deterministic mock output, not real speech recognition."
                ]
            )
        }
    }

    private func merge(
        planWarnings: [String],
        into result: TranscriptionJobResult
    ) -> TranscriptionJobResult {
        var mergedWarnings = planWarnings
        for warning in result.warningMessages where !mergedWarnings.contains(warning) {
            mergedWarnings.append(warning)
        }

        return TranscriptionJobResult(
            segments: result.segments,
            backend: result.backend,
            executionKind: result.executionKind,
            warningMessages: mergedWarnings,
            detectedLanguage: result.detectedLanguage
        )
    }
}
