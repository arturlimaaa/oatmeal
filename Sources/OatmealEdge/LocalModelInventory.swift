import Foundation

struct LocalModelInventory: Sendable {
    let modelsDirectoryURL: URL
    private let environment: [String: String]

    init(
        modelsDirectoryURL: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.modelsDirectoryURL = modelsDirectoryURL
        self.environment = environment
    }

    func discoveredModels() -> [ManagedLocalModel] {
        ensureModelsDirectoryExistsIfNeeded()

        var candidates: [URL] = []
        if let environmentModelPath = environment["OATMEAL_WHISPER_MODEL_PATH"], !environmentModelPath.isEmpty {
            candidates.append(URL(fileURLWithPath: environmentModelPath))
        }

        if let contents = try? FileManager.default.contentsOfDirectory(
            at: modelsDirectoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            candidates.append(contentsOf: contents)
        }

        let allowedExtensions = Set(["bin", "gguf"])
        return candidates
            .filter {
                allowedExtensions.contains($0.pathExtension.lowercased())
                || $0.lastPathComponent.lowercased().contains("whisper")
            }
            .compactMap { url in
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values?.isRegularFile ?? true else {
                    return nil
                }

                let classification = WhisperModelClassifier.classify(filename: url.lastPathComponent)
                return ManagedLocalModel(
                    kind: .whisper,
                    displayName: url.deletingPathExtension().lastPathComponent,
                    fileURL: url,
                    sizeBytes: values?.fileSize.map(Int64.init),
                    variant: classification.variant,
                    sizeTier: classification.sizeTier
                )
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func ensureModelsDirectoryExistsIfNeeded() {
        if FileManager.default.fileExists(atPath: modelsDirectoryURL.path) {
            return
        }

        try? FileManager.default.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)
    }
}
