import Foundation
import OatmealCore

protocol MLXSummaryServing: Sendable {
    func status(
        configuration: LocalSummaryConfiguration,
        discoveredModels: [ManagedSummaryModel]
    ) -> SummaryBackendStatus

    func generate(
        request: NoteGenerationRequest,
        configuration: LocalSummaryConfiguration,
        discoveredModels: [ManagedSummaryModel]
    ) async throws -> SummaryJobResult
}

struct MLXSummaryBackend: MLXSummaryServing {
    private let processExecutor: ProcessExecuting
    private let runtimeEnvironment: MLXRuntimeEnvironment

    init(
        executableLocator: ExecutableLocator = ExecutableLocator(),
        processExecutor: ProcessExecuting = ProcessExecutor(),
        managedPythonURL: URL? = nil
    ) {
        self.processExecutor = processExecutor
        self.runtimeEnvironment = MLXRuntimeEnvironment(
            executableLocator: executableLocator,
            processExecutor: processExecutor,
            managedPythonURL: managedPythonURL
        )
    }

    func status(
        configuration: LocalSummaryConfiguration,
        discoveredModels: [ManagedSummaryModel]
    ) -> SummaryBackendStatus {
        guard let pythonURL = runtimeEnvironment.pythonExecutableURL() else {
            return SummaryBackendStatus(
                backend: .mlxLocal,
                displayName: "MLX Local",
                availability: .unavailable,
                detail: "python3 was not found, so Oatmeal cannot launch the MLX summary runtime.",
                isRunnable: false
            )
        }

        guard runtimeEnvironment.pythonEnvironmentSupports(requiredModules: ["mlx", "mlx_lm"], pythonURL: pythonURL) else {
            return SummaryBackendStatus(
                backend: .mlxLocal,
                displayName: "MLX Local",
                availability: .unavailable,
                detail: "python3 is available, but the `mlx` and `mlx_lm` packages are not installed in that environment.",
                isRunnable: false
            )
        }

        guard !discoveredModels.isEmpty else {
            return SummaryBackendStatus(
                backend: .mlxLocal,
                displayName: "MLX Local",
                availability: .degraded,
                detail: "MLX is installed, but no local summary model was found in Oatmeal's managed summaries folder.",
                isRunnable: false
            )
        }

        let activeModelName = resolvedModel(from: discoveredModels, preferredModelName: configuration.preferredModelName)?.displayName
            ?? discoveredModels.first?.displayName
            ?? "unknown"
        let detail = "MLX Local is ready. Oatmeal will use `\(activeModelName)` for on-device enhanced note generation."

        return SummaryBackendStatus(
            backend: .mlxLocal,
            displayName: "MLX Local",
            availability: .available,
            detail: detail,
            isRunnable: true
        )
    }

    func generate(
        request: NoteGenerationRequest,
        configuration: LocalSummaryConfiguration,
        discoveredModels: [ManagedSummaryModel]
    ) async throws -> SummaryJobResult {
        guard let pythonURL = runtimeEnvironment.pythonExecutableURL() else {
            throw SummaryPipelineError.backendUnavailable("python3 was not found for the MLX summary runtime.")
        }

        guard runtimeEnvironment.pythonEnvironmentSupports(requiredModules: ["mlx", "mlx_lm"], pythonURL: pythonURL) else {
            throw SummaryPipelineError.backendUnavailable(
                "The configured python3 environment does not provide the `mlx` and `mlx_lm` packages."
            )
        }

        guard let model = resolvedModel(from: discoveredModels, preferredModelName: configuration.preferredModelName) else {
            throw SummaryPipelineError.backendUnavailable(
                "No local MLX summary model is available in Oatmeal's managed summaries folder."
            )
        }

        let scriptURL = try pythonRunnerScriptURL()
        let fileManager = FileManager.default
        let tempDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("oatmeal-summary-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDirectoryURL) }

        let inputURL = tempDirectoryURL.appendingPathComponent("request.json", isDirectory: false)
        let outputURL = tempDirectoryURL.appendingPathComponent("response.json", isDirectory: false)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(MLXSummaryPromptRequest(request: request)).write(to: inputURL, options: [.atomic])

        _ = try processExecutor.run(
            executableURL: pythonURL,
            arguments: [
                scriptURL.path,
                "--input", inputURL.path,
                "--output", outputURL.path,
                "--model", model.directoryURL.path
            ],
            environment: ProcessInfo.processInfo.environment,
            currentDirectoryURL: tempDirectoryURL
        )

        let outputData = try Data(contentsOf: outputURL)
        let decoder = JSONDecoder()
        let response = try decoder.decode(MLXSummaryPromptResponse.self, from: outputData)
        let enhancedNote = response.makeEnhancedNote(
            templateID: request.template.id,
            transcriptSegments: request.transcriptSegments
        )

        return SummaryJobResult(
            enhancedNote: enhancedNote,
            backend: .mlxLocal,
            executionKind: .local,
            warningMessages: response.warningMessages
        )
    }

    private func resolvedModel(
        from discoveredModels: [ManagedSummaryModel],
        preferredModelName: String?
    ) -> ManagedSummaryModel? {
        if let preferredModelName {
            if let preferred = discoveredModels.first(where: {
                $0.displayName.caseInsensitiveCompare(preferredModelName) == .orderedSame
            }) {
                return preferred
            }
        }

        return discoveredModels.first
    }

    private func pythonRunnerScriptURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "mlx_summary_runner", withExtension: "py") else {
            throw SummaryPipelineError.backendUnavailable(
                "Oatmeal could not find the bundled MLX summary runner script."
            )
        }

        return url
    }
}

private struct MLXSummaryPromptRequest: Codable {
    struct Segment: Codable {
        let speakerName: String?
        let text: String
    }

    struct Event: Codable {
        let title: String
        let attendeeNames: [String]
        let startDate: Date?
        let endDate: Date?
        let location: String?
    }

    let title: String
    let templateName: String
    let templateInstructions: String
    let templateSections: [String]
    let rawNotes: String
    let transcriptSegments: [Segment]
    let event: Event?

    init(request: NoteGenerationRequest) {
        title = request.title
        templateName = request.template.name
        templateInstructions = request.template.instructions
        templateSections = request.template.sections
        rawNotes = request.rawNotes
        transcriptSegments = request.transcriptSegments.map {
            Segment(speakerName: $0.speakerName, text: $0.text)
        }
        event = request.meetingEvent.map {
            Event(
                title: $0.title,
                attendeeNames: $0.attendees.map(\.name),
                startDate: $0.startDate,
                endDate: $0.endDate,
                location: $0.location
            )
        }
    }
}

private struct MLXSummaryPromptResponse: Codable {
    struct OutputActionItem: Codable {
        let text: String
        let assignee: String?
    }

    let summary: String
    let keyDiscussionPoints: [String]
    let decisions: [String]
    let risksOrOpenQuestions: [String]
    let actionItems: [OutputActionItem]
    let warningMessages: [String]

    func makeEnhancedNote(
        templateID: UUID,
        transcriptSegments: [TranscriptSegment]
    ) -> EnhancedNote {
        let normalizedKeyPoints = keyDiscussionPoints.map(normalizeLine(_:)).filter { !$0.isEmpty }
        let normalizedDecisions = decisions.map(normalizeLine(_:)).filter { !$0.isEmpty }
        let normalizedRisks = risksOrOpenQuestions.map(normalizeLine(_:)).filter { !$0.isEmpty }
        let normalizedActions = actionItems
            .map {
                ActionItem(
                    text: normalizeSentence($0.text),
                    assignee: $0.assignee?.trimmingCharacters(in: .whitespacesAndNewlines),
                    dueDate: nil,
                    status: .open
                )
            }
            .filter { !$0.text.isEmpty }

        let highlights = normalizedKeyPoints + normalizedDecisions + normalizedRisks + normalizedActions.map(\.text)
        let citations: [SourceCitation] = transcriptSegments.compactMap { segment in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return nil
            }

            let segmentText = text.lowercased()
            guard highlights.contains(where: {
                let highlight = $0.lowercased()
                return !highlight.isEmpty && (segmentText.contains(highlight) || highlight.contains(segmentText))
            }) else {
                return nil
            }

            return SourceCitation(transcriptSegmentIDs: [segment.id], excerpt: text)
        }

        return EnhancedNote(
            generatedAt: Date(),
            templateID: templateID,
            summary: normalizeSentence(summary),
            keyDiscussionPoints: normalizedKeyPoints,
            decisions: normalizedDecisions,
            risksOrOpenQuestions: normalizedRisks,
            actionItems: normalizedActions,
            citations: citations
        )
    }

    private func normalizeLine(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeSentence(_ text: String) -> String {
        let trimmed = normalizeLine(text)
        guard !trimmed.isEmpty else {
            return trimmed
        }

        if let last = trimmed.last, ".!?".contains(last) {
            return trimmed
        }

        return trimmed + "."
    }
}
