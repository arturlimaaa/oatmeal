import Foundation
import OatmealCore

public protocol LocalSummaryServicing: Sendable {
    func runtimeState(configuration: LocalSummaryConfiguration) async -> LocalSummaryRuntimeState
    func executionPlan(configuration: LocalSummaryConfiguration) async throws -> LocalSummaryExecutionPlan
    func generate(
        request: NoteGenerationRequest,
        configuration: LocalSummaryConfiguration
    ) async throws -> SummaryJobResult
}

public final class LocalSummaryPipeline: LocalSummaryServicing, @unchecked Sendable {
    private let inventory: SummaryModelInventory
    private let mlx: any MLXSummaryServing
    private let extractive: any ExtractiveSummaryServing
    private let placeholder: any PlaceholderSummaryServing

    public init(applicationSupportDirectoryURL: URL? = nil) {
        let baseURL = applicationSupportDirectoryURL
            ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory)
                .appendingPathComponent("Oatmeal", isDirectory: true)
        let managedPythonURL = baseURL
            .appendingPathComponent("Tools", isDirectory: true)
            .appendingPathComponent("mlx-summary", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python3", isDirectory: false)
        self.inventory = SummaryModelInventory(
            modelsDirectoryURL: baseURL.appendingPathComponent("Models/Summaries", isDirectory: true)
        )
        self.mlx = MLXSummaryBackend(managedPythonURL: managedPythonURL)
        self.extractive = ExtractiveSummaryBackend()
        self.placeholder = PlaceholderSummaryBackend()
    }

    init(
        inventory: SummaryModelInventory,
        mlx: some MLXSummaryServing = MLXSummaryBackend(),
        extractive: some ExtractiveSummaryServing,
        placeholder: some PlaceholderSummaryServing
    ) {
        self.inventory = inventory
        self.mlx = mlx
        self.extractive = extractive
        self.placeholder = placeholder
    }

    public func runtimeState(configuration: LocalSummaryConfiguration) async -> LocalSummaryRuntimeState {
        let discoveredModels = inventory.discoveredModels()
        let mlxStatus = mlx.status(configuration: configuration, discoveredModels: discoveredModels)
        let extractiveStatus = extractive.status(configuration: configuration)
        let placeholderStatus = placeholder.status()
        let backends = [mlxStatus, extractiveStatus, placeholderStatus]

        let activePlanSummary: String
        do {
            activePlanSummary = try resolvePlan(
                configuration: configuration,
                mlxStatus: mlxStatus,
                extractiveStatus: extractiveStatus,
                placeholderStatus: placeholderStatus
            ).summary
        } catch {
            activePlanSummary = error.localizedDescription
        }

        return LocalSummaryRuntimeState(
            modelsDirectoryURL: inventory.modelsDirectoryURL,
            discoveredModels: discoveredModels,
            preferredModelName: configuration.preferredModelName,
            backends: backends,
            activePlanSummary: activePlanSummary
        )
    }

    public func executionPlan(configuration: LocalSummaryConfiguration) async throws -> LocalSummaryExecutionPlan {
        let discoveredModels = inventory.discoveredModels()
        return try resolvePlan(
            configuration: configuration,
            mlxStatus: mlx.status(configuration: configuration, discoveredModels: discoveredModels),
            extractiveStatus: extractive.status(configuration: configuration),
            placeholderStatus: placeholder.status()
        )
    }

    public func generate(
        request: NoteGenerationRequest,
        configuration: LocalSummaryConfiguration
    ) async throws -> SummaryJobResult {
        let plan = try await executionPlan(configuration: configuration)
        let discoveredModels = inventory.discoveredModels()

        switch plan.backend {
        case .mlxLocal:
            do {
                let result = try await mlx.generate(
                    request: request,
                    configuration: configuration,
                    discoveredModels: discoveredModels
                )
                return merge(planWarnings: plan.warningMessages, into: result)
            } catch {
                guard configuration.executionPolicy != .requireStructuredSummary else {
                    throw error
                }

                let fallback = try await extractive.generate(request: request, configuration: configuration)
                return merge(
                    planWarnings: plan.warningMessages + [
                        "The MLX summary backend failed and Oatmeal fell back to the local extractive path: \(error.localizedDescription)"
                    ],
                    into: fallback
                )
            }
        case .extractiveLocal:
            do {
                let result = try await extractive.generate(request: request, configuration: configuration)
                return merge(planWarnings: plan.warningMessages, into: result)
            } catch {
                guard configuration.executionPolicy != .requireStructuredSummary else {
                    throw error
                }

                let fallback = try await placeholder.generate(request: request)
                return merge(
                    planWarnings: plan.warningMessages + [
                        "The local extractive summary backend failed and Oatmeal fell back to the placeholder path: \(error.localizedDescription)"
                    ],
                    into: fallback
                )
            }
        case .placeholder:
            let result = try await placeholder.generate(request: request)
            return merge(planWarnings: plan.warningMessages, into: result)
        }
    }

    private func resolvePlan(
        configuration: LocalSummaryConfiguration,
        mlxStatus: SummaryBackendStatus,
        extractiveStatus: SummaryBackendStatus,
        placeholderStatus: SummaryBackendStatus
    ) throws -> LocalSummaryExecutionPlan {
        switch configuration.preferredBackend {
        case .automatic:
            if mlxStatus.isRunnable {
                return LocalSummaryExecutionPlan(
                    backend: .mlxLocal,
                    executionKind: .local,
                    summary: "Automatic will use the MLX local model runtime for enhanced notes."
                )
            }

            if extractiveStatus.isRunnable {
                return LocalSummaryExecutionPlan(
                    backend: .extractiveLocal,
                    executionKind: .local,
                    summary: "Automatic will use the local extractive summary backend for structured notes.",
                    warningMessages: mlxStatus.detail.nilIfBlank.map { [$0] } ?? []
                )
            }

            if configuration.executionPolicy == .requireStructuredSummary {
                let message = [mlxStatus.detail, extractiveStatus.detail]
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: " ")
                throw SummaryPipelineError.localRuntimeRequired(message)
            }

            return LocalSummaryExecutionPlan(
                backend: .placeholder,
                executionKind: .placeholder,
                summary: "Automatic will use the placeholder summary backend because the richer local paths are unavailable.",
                warningMessages: [mlxStatus.detail, extractiveStatus.detail]
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            )

        case .mlxLocal:
            if mlxStatus.isRunnable {
                return LocalSummaryExecutionPlan(
                    backend: .mlxLocal,
                    executionKind: .local,
                    summary: "MLX Local is the active enhanced-note backend."
                )
            }

            if configuration.executionPolicy == .requireStructuredSummary {
                throw SummaryPipelineError.localRuntimeRequired(mlxStatus.detail)
            }

            if extractiveStatus.isRunnable {
                return LocalSummaryExecutionPlan(
                    backend: .extractiveLocal,
                    executionKind: .local,
                    summary: "MLX Local is unavailable, so Oatmeal will use the extractive local backend.",
                    warningMessages: [mlxStatus.detail]
                )
            }

            return LocalSummaryExecutionPlan(
                backend: .placeholder,
                executionKind: .placeholder,
                summary: "MLX Local is unavailable, so Oatmeal will use the placeholder summary backend.",
                warningMessages: [mlxStatus.detail]
            )

        case .extractiveLocal:
            if extractiveStatus.isRunnable {
                return LocalSummaryExecutionPlan(
                    backend: .extractiveLocal,
                    executionKind: .local,
                    summary: "Extractive Local is the active enhanced-note backend."
                )
            }

            if configuration.executionPolicy == .requireStructuredSummary {
                throw SummaryPipelineError.localRuntimeRequired(extractiveStatus.detail)
            }

            return LocalSummaryExecutionPlan(
                backend: .placeholder,
                executionKind: .placeholder,
                summary: "Extractive Local is unavailable, so Oatmeal will use the placeholder summary backend.",
                warningMessages: [extractiveStatus.detail]
            )
        case .placeholder:
            guard placeholderStatus.isRunnable else {
                throw SummaryPipelineError.backendUnavailable(placeholderStatus.detail)
            }

            return LocalSummaryExecutionPlan(
                backend: .placeholder,
                executionKind: .placeholder,
                summary: "Placeholder summary generation is explicitly selected.",
                warningMessages: [
                    "Placeholder summaries are deterministic fallback output, not the richer local structured note path."
                ]
            )
        }
    }

    private func merge(
        planWarnings: [String],
        into result: SummaryJobResult
    ) -> SummaryJobResult {
        var mergedWarnings = planWarnings
        for warning in result.warningMessages where !mergedWarnings.contains(warning) {
            mergedWarnings.append(warning)
        }

        return SummaryJobResult(
            enhancedNote: result.enhancedNote,
            backend: result.backend,
            executionKind: result.executionKind,
            warningMessages: mergedWarnings
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
