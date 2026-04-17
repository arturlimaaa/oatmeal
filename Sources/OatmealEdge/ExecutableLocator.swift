import Foundation

struct ExecutableLocator: Sendable {
    private let environment: [String: String]

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.environment = environment
    }

    func locate(envKey: String? = nil, candidateNames: [String], fallbackAbsolutePaths: [String] = []) -> URL? {
        var candidates: [URL] = []

        if let envKey, let path = environment[envKey], !path.isEmpty {
            candidates.append(URL(fileURLWithPath: path))
        }

        if let rawPath = environment["PATH"] {
            let directories = rawPath
                .split(separator: ":")
                .map(String.init)
                .filter { !$0.isEmpty }

            for directory in directories {
                for name in candidateNames {
                    candidates.append(URL(fileURLWithPath: directory).appendingPathComponent(name))
                }
            }
        }

        candidates.append(contentsOf: fallbackAbsolutePaths.map(URL.init(fileURLWithPath:)))

        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }
}
