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
/// by tabular unit tests. Subsequent tickets layer auto-routing across `.en`
/// and multilingual variants and `.en` blocking on top of the same shape.
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
        return Decision(
            whisperLanguageArg: whisperLanguageArgument(for: configuredLocale),
            modelToUse: discoveredModels.first,
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
}
