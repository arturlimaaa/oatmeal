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

    func testDecideReturnsFirstDiscoveredModelForNow() {
        let firstModel = ManagedLocalModel(
            kind: .whisper,
            displayName: "tiny.en",
            fileURL: URL(fileURLWithPath: "/tmp/tiny.en.bin")
        )
        let secondModel = ManagedLocalModel(
            kind: .whisper,
            displayName: "small",
            fileURL: URL(fileURLWithPath: "/tmp/small.bin")
        )

        let decision = LanguagePolicy.decide(
            configuredLocale: "en-US",
            discoveredModels: [firstModel, secondModel],
            activeBackend: .automatic
        )

        XCTAssertEqual(decision.modelToUse, firstModel)
    }

    func testDecideReturnsNilModelWhenInventoryIsEmpty() {
        let decision = LanguagePolicy.decide(
            configuredLocale: "es",
            discoveredModels: [],
            activeBackend: .whisperCPPCLI
        )

        XCTAssertEqual(decision.whisperLanguageArg, "es")
        XCTAssertNil(decision.modelToUse)
    }
}
