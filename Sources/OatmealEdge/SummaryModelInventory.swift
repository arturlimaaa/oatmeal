import Foundation

struct SummaryModelInventory: Sendable {
    let modelsDirectoryURL: URL

    init(modelsDirectoryURL: URL) {
        self.modelsDirectoryURL = modelsDirectoryURL
    }

    func discoveredModels() -> [ManagedSummaryModel] {
        ensureDirectoryExists()

        guard let directoryEnumerator = FileManager.default.enumerator(
            at: modelsDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var candidates: [ManagedSummaryModel] = []
        for case let candidateURL as URL in directoryEnumerator {
            guard isModelDirectory(candidateURL) else {
                continue
            }

            candidates.append(
                ManagedSummaryModel(
                    displayName: candidateURL.lastPathComponent,
                    directoryURL: candidateURL,
                    sizeBytes: directorySize(at: candidateURL)
                )
            )
            directoryEnumerator.skipDescendants()
        }

        return candidates.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private func ensureDirectoryExists() {
        if FileManager.default.fileExists(atPath: modelsDirectoryURL.path) {
            return
        }

        try? FileManager.default.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)
    }

    private func isModelDirectory(_ candidateURL: URL) -> Bool {
        let values = try? candidateURL.resourceValues(forKeys: [.isDirectoryKey])
        guard values?.isDirectory == true else {
            return false
        }

        let requiredMarkers = [
            "config.json",
            "tokenizer.json",
            "tokenizer.model",
            "model.safetensors",
            "model.safetensors.index.json"
        ]

        let existingNames = (try? FileManager.default.contentsOfDirectory(atPath: candidateURL.path)) ?? []
        let existingNamesSet = Set(existingNames)

        let hasConfig = existingNamesSet.contains("config.json")
        let hasTokenizer = existingNamesSet.contains("tokenizer.json") || existingNamesSet.contains("tokenizer.model")
        let hasWeights = existingNames.contains { $0.hasSuffix(".safetensors") || $0 == "model.safetensors.index.json" }

        return hasConfig && (hasTokenizer || hasWeights || requiredMarkers.contains(where: existingNamesSet.contains))
    }

    private func directorySize(at url: URL) -> Int64? {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true, let size = values?.fileSize else {
                continue
            }
            total += Int64(size)
        }

        return total > 0 ? total : nil
    }
}
