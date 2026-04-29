import Foundation

/// Severity hint for how well a Whisper model handles a particular language.
///
/// Used to colour and rank the curated model catalog in Settings. The values
/// are intentionally coarse — we only ever offer three levels of guidance
/// because finer granularity would be misleading when the underlying numbers
/// (Whisper's WER table) shift between releases.
public enum QualityTier: String, Equatable, Sendable, Codable {
    case recommended
    case acceptable
    case notRecommended

    /// Lower number == better. Used for stable ordering of catalog rows.
    fileprivate var sortOrder: Int {
        switch self {
        case .recommended: 0
        case .acceptable: 1
        case .notRecommended: 2
        }
    }
}

/// Per-language quality hint attached to a catalog entry.
///
/// `bcp47` is the BCP 47 primary language subtag (e.g. `"es"`, `"pl"`). The
/// absence of an entry for a given language is intentionally meaningful and
/// distinct from `notRecommended`: callers should treat missing entries as
/// "no opinion" and avoid filtering the model out.
public struct LanguageQualityHint: Equatable, Sendable, Codable {
    public let bcp47: String
    public let tier: QualityTier

    public init(bcp47: String, tier: QualityTier) {
        self.bcp47 = bcp47
        self.tier = tier
    }
}

/// One curated multilingual Whisper model that the user can download from
/// Settings.
///
/// `id` doubles as the on-disk filename so the existing `LocalModelInventory`
/// discovers the model without further wiring once it lands in the managed
/// models directory. `downloadURL` is a static string sourced from the
/// canonical Hugging Face mirror for `whisper.cpp`-style ggml weights — see
/// `CuratedModelCatalog.curatedDefaults` for the URL pattern.
public struct CuratedWhisperModelEntry: Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let sizeBytes: Int64
    public let downloadURL: URL
    public let variant: WhisperModelClassifier.Variant
    public let sizeTier: WhisperModelClassifier.SizeTier
    public let perLanguageQualityHints: [LanguageQualityHint]

    public init(
        id: String,
        displayName: String,
        sizeBytes: Int64,
        downloadURL: URL,
        variant: WhisperModelClassifier.Variant,
        sizeTier: WhisperModelClassifier.SizeTier,
        perLanguageQualityHints: [LanguageQualityHint]
    ) {
        self.id = id
        self.displayName = displayName
        self.sizeBytes = sizeBytes
        self.downloadURL = downloadURL
        self.variant = variant
        self.sizeTier = sizeTier
        self.perLanguageQualityHints = perLanguageQualityHints
    }

    /// Looks up the curated quality hint for a given BCP 47 language code.
    /// Returns `nil` for languages we don't have an opinion on.
    public func qualityHint(for bcp47: String) -> QualityTier? {
        let lowered = bcp47.lowercased()
        return perLanguageQualityHints.first { $0.bcp47.lowercased() == lowered }?.tier
    }
}

/// Curated catalog of multilingual Whisper models offered in the Settings UI.
///
/// The recommendation function ranks entries for a target language: hinted
/// `.recommended` first, then `.acceptable`, then `.notRecommended`. Within a
/// tier, smaller models sort first (cheaper download wins ties). Entries
/// without an opinion for the requested language fall after the explicit
/// `notRecommended` bucket so the user can still see them; tests pin this
/// ordering invariant.
public enum CuratedModelCatalog {
    /// Initial multilingual ggml Whisper models hosted on the Hugging Face
    /// mirror used by upstream whisper.cpp distributions.
    ///
    /// URL pattern:
    /// `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/<filename>`
    ///
    /// Per-language quality hints are heuristic, derived from Whisper's WER
    /// table and community usage notes. They reflect rough buckets, not
    /// precise benchmarks. Languages with no listed hint are treated as "no
    /// opinion" by `recommendations(for:)`.
    public static let curatedDefaults: [CuratedWhisperModelEntry] = [
        CuratedWhisperModelEntry(
            id: "ggml-base.bin",
            displayName: "Whisper Base (multilingual)",
            sizeBytes: 142_000_000,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")!,
            variant: .multilingual,
            sizeTier: .base,
            perLanguageQualityHints: [
                LanguageQualityHint(bcp47: "en", tier: .acceptable),
                LanguageQualityHint(bcp47: "es", tier: .notRecommended),
                LanguageQualityHint(bcp47: "fr", tier: .notRecommended),
                LanguageQualityHint(bcp47: "it", tier: .notRecommended),
                LanguageQualityHint(bcp47: "pt", tier: .notRecommended),
                LanguageQualityHint(bcp47: "de", tier: .notRecommended),
                LanguageQualityHint(bcp47: "nl", tier: .notRecommended),
                LanguageQualityHint(bcp47: "pl", tier: .notRecommended),
                LanguageQualityHint(bcp47: "ru", tier: .notRecommended),
                LanguageQualityHint(bcp47: "tr", tier: .notRecommended),
                LanguageQualityHint(bcp47: "ja", tier: .notRecommended),
                LanguageQualityHint(bcp47: "ko", tier: .notRecommended),
                LanguageQualityHint(bcp47: "zh", tier: .notRecommended),
                LanguageQualityHint(bcp47: "ar", tier: .notRecommended),
                LanguageQualityHint(bcp47: "hi", tier: .notRecommended)
            ]
        ),
        CuratedWhisperModelEntry(
            id: "ggml-small.bin",
            displayName: "Whisper Small (multilingual)",
            sizeBytes: 466_000_000,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin")!,
            variant: .multilingual,
            sizeTier: .small,
            perLanguageQualityHints: [
                LanguageQualityHint(bcp47: "en", tier: .recommended),
                LanguageQualityHint(bcp47: "es", tier: .acceptable),
                LanguageQualityHint(bcp47: "fr", tier: .acceptable),
                LanguageQualityHint(bcp47: "it", tier: .acceptable),
                LanguageQualityHint(bcp47: "pt", tier: .acceptable),
                LanguageQualityHint(bcp47: "de", tier: .acceptable),
                LanguageQualityHint(bcp47: "nl", tier: .acceptable),
                LanguageQualityHint(bcp47: "pl", tier: .notRecommended),
                LanguageQualityHint(bcp47: "ru", tier: .notRecommended),
                LanguageQualityHint(bcp47: "tr", tier: .notRecommended),
                LanguageQualityHint(bcp47: "ja", tier: .notRecommended),
                LanguageQualityHint(bcp47: "ko", tier: .notRecommended),
                LanguageQualityHint(bcp47: "zh", tier: .notRecommended),
                LanguageQualityHint(bcp47: "ar", tier: .notRecommended),
                LanguageQualityHint(bcp47: "hi", tier: .notRecommended)
            ]
        ),
        CuratedWhisperModelEntry(
            id: "ggml-medium.bin",
            displayName: "Whisper Medium (multilingual)",
            sizeBytes: 1_530_000_000,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin")!,
            variant: .multilingual,
            sizeTier: .medium,
            perLanguageQualityHints: [
                LanguageQualityHint(bcp47: "en", tier: .recommended),
                LanguageQualityHint(bcp47: "es", tier: .recommended),
                LanguageQualityHint(bcp47: "fr", tier: .recommended),
                LanguageQualityHint(bcp47: "it", tier: .recommended),
                LanguageQualityHint(bcp47: "pt", tier: .recommended),
                LanguageQualityHint(bcp47: "de", tier: .recommended),
                LanguageQualityHint(bcp47: "nl", tier: .recommended),
                LanguageQualityHint(bcp47: "pl", tier: .recommended),
                LanguageQualityHint(bcp47: "ru", tier: .recommended),
                LanguageQualityHint(bcp47: "tr", tier: .recommended),
                LanguageQualityHint(bcp47: "ja", tier: .recommended),
                LanguageQualityHint(bcp47: "zh", tier: .recommended),
                LanguageQualityHint(bcp47: "ar", tier: .acceptable),
                LanguageQualityHint(bcp47: "hi", tier: .acceptable),
                LanguageQualityHint(bcp47: "ko", tier: .acceptable)
            ]
        ),
        CuratedWhisperModelEntry(
            id: "ggml-large-v3.bin",
            displayName: "Whisper Large v3 (multilingual)",
            sizeBytes: 3_090_000_000,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin")!,
            variant: .multilingual,
            sizeTier: .large,
            perLanguageQualityHints: [
                LanguageQualityHint(bcp47: "en", tier: .recommended),
                LanguageQualityHint(bcp47: "es", tier: .recommended),
                LanguageQualityHint(bcp47: "fr", tier: .recommended),
                LanguageQualityHint(bcp47: "it", tier: .recommended),
                LanguageQualityHint(bcp47: "pt", tier: .recommended),
                LanguageQualityHint(bcp47: "de", tier: .recommended),
                LanguageQualityHint(bcp47: "nl", tier: .recommended),
                LanguageQualityHint(bcp47: "pl", tier: .recommended),
                LanguageQualityHint(bcp47: "ru", tier: .recommended),
                LanguageQualityHint(bcp47: "tr", tier: .recommended),
                LanguageQualityHint(bcp47: "ja", tier: .recommended),
                LanguageQualityHint(bcp47: "ko", tier: .recommended),
                LanguageQualityHint(bcp47: "zh", tier: .recommended),
                LanguageQualityHint(bcp47: "ar", tier: .recommended),
                LanguageQualityHint(bcp47: "hi", tier: .recommended)
            ]
        )
    ]

    /// Ranks `entries` for a target language. Hinted `.recommended` rows come
    /// first, then `.acceptable`, then `.notRecommended`. Entries without an
    /// opinion for the language are placed after the explicit
    /// `notRecommended` bucket — they're still surfaced, just demoted. Within
    /// a tier, smaller `sizeTier` first (cheapest viable download wins ties).
    public static func recommendations(
        for bcp47: String,
        in entries: [CuratedWhisperModelEntry] = curatedDefaults
    ) -> [CuratedWhisperModelEntry] {
        let normalized = bcp47.lowercased()
        return entries.sorted { lhs, rhs in
            let lhsTier = lhs.qualityHint(for: normalized)
            let rhsTier = rhs.qualityHint(for: normalized)

            switch (lhsTier, rhsTier) {
            case let (lhsTier?, rhsTier?):
                if lhsTier != rhsTier {
                    return lhsTier.sortOrder < rhsTier.sortOrder
                }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }

            if lhs.sizeTier != rhs.sizeTier {
                return lhs.sizeTier < rhs.sizeTier
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }
}
