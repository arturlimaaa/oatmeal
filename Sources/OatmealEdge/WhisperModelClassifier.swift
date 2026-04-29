import Foundation

/// Pure-function classifier that maps a Whisper model filename onto the
/// orthogonal axes the routing layer cares about: whether the model is the
/// English-only `.en` variant or a multilingual variant, and which size tier
/// it belongs to.
///
/// Filename conventions handled:
/// - `ggml-base.en.bin`, `ggml-base.bin`
/// - `ggml-small.en-q5_0.bin` (quantization suffixes)
/// - `ggml-medium.bin`, `ggml-large-v3.bin`
/// - `whisper-small.en.gguf`
/// - bare filenames containing the word `whisper` with no recognizable size
///
/// The intent is to keep filename-shape knowledge isolated here so callers can
/// reason about Whisper variants without re-parsing strings.
public struct WhisperModelClassifier: Sendable {
    public enum Variant: String, Codable, Equatable, Sendable {
        case englishOnly
        case multilingual
    }

    public enum SizeTier: String, Codable, Equatable, Sendable, Comparable {
        case tiny
        case base
        case small
        case medium
        case large
        case other

        private var sortOrder: Int {
            switch self {
            case .tiny: 0
            case .base: 1
            case .small: 2
            case .medium: 3
            case .large: 4
            case .other: 5
            }
        }

        public static func < (lhs: SizeTier, rhs: SizeTier) -> Bool {
            lhs.sortOrder < rhs.sortOrder
        }
    }

    public struct Classification: Equatable, Sendable {
        public let variant: Variant
        public let sizeTier: SizeTier

        public init(variant: Variant, sizeTier: SizeTier) {
            self.variant = variant
            self.sizeTier = sizeTier
        }
    }

    /// Classifies a model by inspecting the filename. The lookup is
    /// case-insensitive and tolerant of separators and quantization suffixes.
    public static func classify(filename: String) -> Classification {
        let lowered = filename.lowercased()
        let variant = detectVariant(in: lowered)
        let sizeTier = detectSizeTier(in: lowered)
        return Classification(variant: variant, sizeTier: sizeTier)
    }

    private static func detectVariant(in lowered: String) -> Variant {
        // The `.en` infix appears between the size token and the rest of the
        // filename in every Whisper distribution we've seen. Detect it by
        // looking for the literal `.en` token bounded by non-alpha characters
        // so we don't false-match filenames that merely contain the letters
        // `en` inside another word (e.g. `frozen`, `tencent`).
        let scalars = Array(lowered.unicodeScalars)
        let target: [Unicode.Scalar] = [".", "e", "n"]
        var index = 0
        while index <= scalars.count - target.count {
            if scalars[index] == target[0],
               scalars[index + 1] == target[1],
               scalars[index + 2] == target[2] {
                let trailingIndex = index + target.count
                let isAtEnd = trailingIndex == scalars.count
                let trailingIsBoundary = isAtEnd || !isAlphanumeric(scalars[trailingIndex])
                if trailingIsBoundary {
                    return .englishOnly
                }
            }
            index += 1
        }
        return .multilingual
    }

    private static func detectSizeTier(in lowered: String) -> SizeTier {
        // Order matters: check longer tokens before shorter tokens that could
        // appear as substrings (none today, but cheap insurance).
        let candidates: [(String, SizeTier)] = [
            ("medium", .medium),
            ("large", .large),
            ("small", .small),
            ("tiny", .tiny),
            ("base", .base)
        ]
        for (token, tier) in candidates where lowered.contains(token) {
            return tier
        }
        return .other
    }

    private static func isAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.alphanumerics.contains(scalar)
    }
}
