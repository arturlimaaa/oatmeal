import Foundation
import OatmealCore

/// Single decision point for the multilingual transcription pipeline.
///
/// Given the user's configured locale, the discovered Whisper models, and the
/// active backend preference, `LanguagePolicy` returns the language argument
/// that should be passed to whisper.cpp's `-l` flag, the model the pipeline
/// should run, whether the configuration is degraded, and any blocking reason
/// that should be surfaced to the user.
///
/// This is intentionally a pure function with no I/O so it can be exercised
/// by tabular unit tests. Phase 3 layers auto-routing across `.en` and
/// multilingual variants and `.en` blocking on top of the same shape.
public struct LanguagePolicy {
    public struct Decision: Equatable {
        public let whisperLanguageArg: String
        public let modelToUse: ManagedLocalModel?
        public let isDegraded: Bool
        public let blockingReason: String?

        public init(
            whisperLanguageArg: String,
            modelToUse: ManagedLocalModel?,
            isDegraded: Bool,
            blockingReason: String?
        ) {
            self.whisperLanguageArg = whisperLanguageArg
            self.modelToUse = modelToUse
            self.isDegraded = isDegraded
            self.blockingReason = blockingReason
        }
    }

    public static func decide(
        configuredLocale: String?,
        discoveredModels: [ManagedLocalModel],
        activeBackend: TranscriptionBackendPreference
    ) -> Decision {
        _ = activeBackend // reserved for richer routing in subsequent tickets

        let languageArg = whisperLanguageArgument(for: configuredLocale)
        let whisperModels = discoveredModels.filter { $0.kind == .whisper }

        // No models discovered at all: the existing model-missing error in
        // `WhisperCPPTranscriptionBackend.installationState(...)` covers this
        // case, so the policy intentionally does not double-handle it.
        guard !whisperModels.isEmpty else {
            return Decision(
                whisperLanguageArg: languageArg,
                modelToUse: nil,
                isDegraded: false,
                blockingReason: nil
            )
        }

        let englishOnlyModels = whisperModels.filter { $0.variant == .englishOnly }
        let multilingualModels = whisperModels.filter { $0.variant != .englishOnly }

        if languageArg == "auto" {
            if let preferred = preferredModel(in: multilingualModels) {
                return Decision(
                    whisperLanguageArg: "auto",
                    modelToUse: preferred,
                    isDegraded: false,
                    blockingReason: nil
                )
            }

            if !englishOnlyModels.isEmpty {
                return Decision(
                    whisperLanguageArg: "auto",
                    modelToUse: preferredModel(in: englishOnlyModels),
                    isDegraded: true,
                    blockingReason: "Auto-detect requires a multilingual Whisper model. Download a multilingual model in Settings to enable auto-detect."
                )
            }

            // Whisper models exist but none have classification info (only
            // possible with synthetic fixtures). Fall back to the first.
            return Decision(
                whisperLanguageArg: "auto",
                modelToUse: preferredModel(in: whisperModels),
                isDegraded: false,
                blockingReason: nil
            )
        }

        if languageArg == "en" {
            if let preferred = preferredModel(in: englishOnlyModels) {
                return Decision(
                    whisperLanguageArg: "en",
                    modelToUse: preferred,
                    isDegraded: false,
                    blockingReason: nil
                )
            }

            if let preferred = preferredModel(in: multilingualModels) {
                return Decision(
                    whisperLanguageArg: "en",
                    modelToUse: preferred,
                    isDegraded: false,
                    blockingReason: nil
                )
            }

            return Decision(
                whisperLanguageArg: "en",
                modelToUse: preferredModel(in: whisperModels),
                isDegraded: false,
                blockingReason: nil
            )
        }

        // Specific non-English language.
        if let preferred = preferredModel(in: multilingualModels) {
            return Decision(
                whisperLanguageArg: languageArg,
                modelToUse: preferred,
                isDegraded: false,
                blockingReason: nil
            )
        }

        if !englishOnlyModels.isEmpty {
            return Decision(
                whisperLanguageArg: languageArg,
                modelToUse: preferredModel(in: englishOnlyModels),
                isDegraded: true,
                blockingReason: "Whisper's English-only model cannot transcribe \(languageArg). Download a multilingual model in Settings."
            )
        }

        return Decision(
            whisperLanguageArg: languageArg,
            modelToUse: preferredModel(in: whisperModels),
            isDegraded: false,
            blockingReason: nil
        )
    }

    /// Maps a locale identifier (BCP 47, POSIX, or bare language code) to the
    /// argument whisper.cpp expects after `-l`. Returns `"auto"` when the
    /// caller has not configured a preference, otherwise the BCP 47 primary
    /// language subtag (e.g. `"en"`, `"es"`, `"pt"`).
    public static func whisperLanguageArgument(for localeIdentifier: String?) -> String {
        guard let localeIdentifier else {
            return "auto"
        }

        let trimmed = localeIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "auto"
        }

        let locale = NSLocale(localeIdentifier: trimmed)
        if let languageCode = locale.object(forKey: .languageCode) as? String, !languageCode.isEmpty {
            return languageCode.lowercased()
        }

        return String(trimmed.prefix(2)).lowercased()
    }

    /// Picks the smallest-tier Whisper model from the provided list, breaking
    /// ties alphabetically by `displayName`. Models with `nil` `sizeTier`
    /// (synthetic fixtures that never went through filename classification)
    /// sort last so real, classified inventory always wins.
    private static func preferredModel(in models: [ManagedLocalModel]) -> ManagedLocalModel? {
        guard !models.isEmpty else { return nil }
        return models.sorted { lhs, rhs in
            switch (lhs.sizeTier, rhs.sizeTier) {
            case let (lhsTier?, rhsTier?):
                if lhsTier != rhsTier {
                    return lhsTier < rhsTier
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
        }.first
    }
}
