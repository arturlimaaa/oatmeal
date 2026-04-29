import Foundation
import OatmealCore
@testable import OatmealEdge
import XCTest

final class LanguagePolicyTests: XCTestCase {
    func testWhisperLanguageArgumentMappings() {
        let cases: [(String?, String)] = [
            (nil, "auto"),
            ("", "auto"),
            ("   ", "auto"),
            ("en", "en"),
            ("en-US", "en"),
            ("es-ES", "es"),
            ("pt_BR", "pt"),
            ("PL", "pl")
        ]

        for (input, expected) in cases {
            XCTAssertEqual(
                LanguagePolicy.whisperLanguageArgument(for: input),
                expected,
                "Expected locale \(input ?? "nil") to map to \(expected)"
            )
        }
    }

    func testDecideUsesAutoWhenLocaleIsMissing() {
        let decision = LanguagePolicy.decide(
            configuredLocale: nil,
            discoveredModels: [],
            activeBackend: .automatic
        )

        XCTAssertEqual(decision.whisperLanguageArg, "auto")
        XCTAssertNil(decision.modelToUse)
        XCTAssertFalse(decision.isDegraded)
        XCTAssertNil(decision.blockingReason)
    }

    func testDecideUsesAutoWhenLocaleIsEmptyString() {
        let decision = LanguagePolicy.decide(
            configuredLocale: "",
            discoveredModels: [],
            activeBackend: .automatic
        )

        XCTAssertEqual(decision.whisperLanguageArg, "auto")
    }

    func testDecideExtractsLanguageCodeForLockedLocale() {
        let cases: [(String, String)] = [
            ("en", "en"),
            ("en-US", "en"),
            ("es-ES", "es"),
            ("pt_BR", "pt")
        ]

        for (input, expected) in cases {
            let decision = LanguagePolicy.decide(
                configuredLocale: input,
                discoveredModels: [],
                activeBackend: .whisperCPPCLI
            )

            XCTAssertEqual(decision.whisperLanguageArg, expected)
            XCTAssertFalse(decision.isDegraded)
            XCTAssertNil(decision.blockingReason)
        }
    }

    func testDecideReturnsNilModelWhenInventoryIsEmpty() {
        let decision = LanguagePolicy.decide(
            configuredLocale: "es",
            discoveredModels: [],
            activeBackend: .whisperCPPCLI
        )

        XCTAssertEqual(decision.whisperLanguageArg, "es")
        XCTAssertNil(decision.modelToUse)
        XCTAssertNil(decision.blockingReason)
    }

    // MARK: - English-locked routing

    func testEnglishLockedPrefersEnglishOnlyModel() {
        let smallEN = makeWhisperModel(name: "small.en", variant: .englishOnly, sizeTier: .small)
        let mediumMultilingual = makeWhisperModel(name: "medium", variant: .multilingual, sizeTier: .medium)

        let decision = LanguagePolicy.decide(
            configuredLocale: "en-US",
            discoveredModels: [mediumMultilingual, smallEN],
            activeBackend: .whisperCPPCLI
        )

        XCTAssertEqual(decision.whisperLanguageArg, "en")
        XCTAssertEqual(decision.modelToUse, smallEN)
        XCTAssertFalse(decision.isDegraded)
        XCTAssertNil(decision.blockingReason)
    }

    func testEnglishLockedPrefersSmallestEnglishOnlyTier() {
        let baseEN = makeWhisperModel(name: "base.en", variant: .englishOnly, sizeTier: .base)
        let smallEN = makeWhisperModel(name: "small.en", variant: .englishOnly, sizeTier: .small)
        let mediumEN = makeWhisperModel(name: "medium.en", variant: .englishOnly, sizeTier: .medium)

        let decision = LanguagePolicy.decide(
            configuredLocale: "en",
            discoveredModels: [mediumEN, smallEN, baseEN],
            activeBackend: .whisperCPPCLI
        )

        XCTAssertEqual(decision.modelToUse, baseEN)
        XCTAssertEqual(decision.whisperLanguageArg, "en")
    }

    func testEnglishLockedFallsBackToMultilingualWhenNoEnglishOnly() {
        let smallMultilingual = makeWhisperModel(name: "small", variant: .multilingual, sizeTier: .small)
        let mediumMultilingual = makeWhisperModel(name: "medium", variant: .multilingual, sizeTier: .medium)

        let decision = LanguagePolicy.decide(
            configuredLocale: "en-US",
            discoveredModels: [mediumMultilingual, smallMultilingual],
            activeBackend: .whisperCPPCLI
        )

        XCTAssertEqual(decision.whisperLanguageArg, "en")
        XCTAssertEqual(decision.modelToUse, smallMultilingual)
        XCTAssertFalse(decision.isDegraded)
        XCTAssertNil(decision.blockingReason)
    }

    // MARK: - Auto-detect routing

    func testAutoDetectUsesMultilingualModelWhenAvailable() {
        let smallEN = makeWhisperModel(name: "small.en", variant: .englishOnly, sizeTier: .small)
        let largeMultilingual = makeWhisperModel(name: "large", variant: .multilingual, sizeTier: .large)

        let decision = LanguagePolicy.decide(
            configuredLocale: nil,
            discoveredModels: [smallEN, largeMultilingual],
            activeBackend: .automatic
        )

        XCTAssertEqual(decision.whisperLanguageArg, "auto")
        XCTAssertEqual(decision.modelToUse, largeMultilingual)
        XCTAssertFalse(decision.isDegraded)
        XCTAssertNil(decision.blockingReason)
    }

    func testAutoDetectIsBlockedWhenOnlyEnglishOnlyAvailable() {
        let smallEN = makeWhisperModel(name: "small.en", variant: .englishOnly, sizeTier: .small)
        let mediumEN = makeWhisperModel(name: "medium.en", variant: .englishOnly, sizeTier: .medium)

        let decision = LanguagePolicy.decide(
            configuredLocale: nil,
            discoveredModels: [smallEN, mediumEN],
            activeBackend: .automatic
        )

        XCTAssertEqual(decision.whisperLanguageArg, "auto")
        XCTAssertTrue(decision.isDegraded)
        XCTAssertNotNil(decision.blockingReason)
        XCTAssertEqual(
            decision.blockingReason,
            "Auto-detect requires a multilingual Whisper model. Download a multilingual model in Settings to enable auto-detect."
        )
    }

    func testAutoDetectIsBlockedWhenLocaleIsEmptyAndOnlyEnglishOnly() {
        let baseEN = makeWhisperModel(name: "base.en", variant: .englishOnly, sizeTier: .base)

        let decision = LanguagePolicy.decide(
            configuredLocale: "   ",
            discoveredModels: [baseEN],
            activeBackend: .whisperCPPCLI
        )

        XCTAssertEqual(decision.whisperLanguageArg, "auto")
        XCTAssertNotNil(decision.blockingReason)
    }

    // MARK: - Specific non-English routing

    func testSpecificNonEnglishUsesMultilingualModel() {
        let smallEN = makeWhisperModel(name: "small.en", variant: .englishOnly, sizeTier: .small)
        let baseMultilingual = makeWhisperModel(name: "base", variant: .multilingual, sizeTier: .base)
        let mediumMultilingual = makeWhisperModel(name: "medium", variant: .multilingual, sizeTier: .medium)

        let decision = LanguagePolicy.decide(
            configuredLocale: "es-ES",
            discoveredModels: [smallEN, mediumMultilingual, baseMultilingual],
            activeBackend: .whisperCPPCLI
        )

        XCTAssertEqual(decision.whisperLanguageArg, "es")
        XCTAssertEqual(decision.modelToUse, baseMultilingual)
        XCTAssertFalse(decision.isDegraded)
        XCTAssertNil(decision.blockingReason)
    }

    func testSpecificNonEnglishIsBlockedWhenOnlyEnglishOnlyAvailable() {
        let smallEN = makeWhisperModel(name: "small.en", variant: .englishOnly, sizeTier: .small)

        let decision = LanguagePolicy.decide(
            configuredLocale: "es-ES",
            discoveredModels: [smallEN],
            activeBackend: .whisperCPPCLI
        )

        XCTAssertEqual(decision.whisperLanguageArg, "es")
        XCTAssertTrue(decision.isDegraded)
        XCTAssertEqual(
            decision.blockingReason,
            "Whisper's English-only model cannot transcribe es. Download a multilingual model in Settings."
        )
    }

    // MARK: - Tie-breaking

    func testTieBreakingIsAlphabeticalWithinSameTier() {
        let alphaModel = makeWhisperModel(name: "alpha", variant: .multilingual, sizeTier: .small)
        let bravoModel = makeWhisperModel(name: "bravo", variant: .multilingual, sizeTier: .small)

        let decision = LanguagePolicy.decide(
            configuredLocale: "es",
            discoveredModels: [bravoModel, alphaModel],
            activeBackend: .whisperCPPCLI
        )

        XCTAssertEqual(decision.modelToUse, alphaModel)
    }

    func testNilSizeTierSortsLastAmongMultilingualModels() {
        let unclassified = makeWhisperModel(name: "synthetic", variant: .multilingual, sizeTier: nil)
        let baseMultilingual = makeWhisperModel(name: "base", variant: .multilingual, sizeTier: .base)

        let decision = LanguagePolicy.decide(
            configuredLocale: "fr",
            discoveredModels: [unclassified, baseMultilingual],
            activeBackend: .whisperCPPCLI
        )

        XCTAssertEqual(decision.modelToUse, baseMultilingual)
    }

    // MARK: - Helpers

    private func makeWhisperModel(
        name: String,
        variant: WhisperModelClassifier.Variant?,
        sizeTier: WhisperModelClassifier.SizeTier?
    ) -> ManagedLocalModel {
        ManagedLocalModel(
            kind: .whisper,
            displayName: name,
            fileURL: URL(fileURLWithPath: "/tmp/\(name).bin"),
            sizeBytes: nil,
            variant: variant,
            sizeTier: sizeTier
        )
    }
}
