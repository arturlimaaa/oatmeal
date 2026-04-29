import Foundation
@testable import OatmealEdge
import XCTest

final class CuratedModelCatalogTests: XCTestCase {
    func testCuratedDefaultsExposeExpectedMultilingualFamily() {
        let identifiers = CuratedModelCatalog.curatedDefaults.map(\.id)
        XCTAssertEqual(identifiers, [
            "ggml-base.bin",
            "ggml-small.bin",
            "ggml-medium.bin",
            "ggml-large-v3.bin"
        ])

        for entry in CuratedModelCatalog.curatedDefaults {
            XCTAssertEqual(entry.variant, .multilingual, "\(entry.id) should be classified as multilingual")
            XCTAssertTrue(
                entry.downloadURL.absoluteString.hasPrefix(
                    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/"
                ),
                "\(entry.id) should resolve via the canonical Hugging Face mirror, got \(entry.downloadURL)"
            )
            XCTAssertTrue(
                entry.downloadURL.absoluteString.hasSuffix(entry.id),
                "\(entry.id) URL should end in the filename so the on-disk artifact matches the catalog id"
            )
            XCTAssertGreaterThan(entry.sizeBytes, 0)
        }
    }

    func testRecommendationsForFullySupportedLanguageRanksByQualityThenSize() {
        // Polish has `medium` and `large-v3` as `.recommended`, `small` and
        // `base` as `.notRecommended`. Within each tier, smaller wins.
        let recommendations = CuratedModelCatalog.recommendations(for: "pl")
        XCTAssertEqual(recommendations.map(\.id), [
            "ggml-medium.bin",
            "ggml-large-v3.bin",
            "ggml-base.bin",
            "ggml-small.bin"
        ])
    }

    func testRecommendationsForLanguageWhereOnlyLargeIsRecommended() {
        // Korean: large is recommended, medium is acceptable, base+small are
        // notRecommended (and base is smaller than small).
        let recommendations = CuratedModelCatalog.recommendations(for: "ko")
        XCTAssertEqual(recommendations.map(\.id), [
            "ggml-large-v3.bin",
            "ggml-medium.bin",
            "ggml-base.bin",
            "ggml-small.bin"
        ])
    }

    func testRecommendationsForLanguageWithNoOpinionFallsBackToSizeOrder() {
        // Use a custom catalog where no entry has an opinion on the target
        // language so the fallback kicks in. The expected ordering then is
        // smallest size tier first.
        let entries = [
            sampleEntry(id: "large.bin", tier: .large),
            sampleEntry(id: "small.bin", tier: .small),
            sampleEntry(id: "base.bin", tier: .base)
        ]
        let recommendations = CuratedModelCatalog.recommendations(for: "xx", in: entries)
        XCTAssertEqual(recommendations.map(\.id), ["base.bin", "small.bin", "large.bin"])
    }

    func testRecommendationsKeepEntriesWithNoOpinionAfterExplicitNotRecommended() {
        let entries = [
            sampleEntry(
                id: "explicit-not-recommended.bin",
                tier: .small,
                hints: [LanguageQualityHint(bcp47: "zz", tier: .notRecommended)]
            ),
            sampleEntry(id: "no-opinion-base.bin", tier: .base, hints: []),
            sampleEntry(
                id: "explicit-recommended.bin",
                tier: .medium,
                hints: [LanguageQualityHint(bcp47: "zz", tier: .recommended)]
            )
        ]

        let recommendations = CuratedModelCatalog.recommendations(for: "zz", in: entries)
        XCTAssertEqual(recommendations.map(\.id), [
            "explicit-recommended.bin",
            "explicit-not-recommended.bin",
            "no-opinion-base.bin"
        ])
    }

    func testRecommendationsIsCaseInsensitiveOnLanguageCode() {
        let lowercase = CuratedModelCatalog.recommendations(for: "pl")
        let uppercase = CuratedModelCatalog.recommendations(for: "PL")
        XCTAssertEqual(lowercase.map(\.id), uppercase.map(\.id))
    }

    func testQualityHintLookupReturnsNilForUnknownLanguage() {
        let entry = CuratedModelCatalog.curatedDefaults.first { $0.id == "ggml-medium.bin" }
        XCTAssertNotNil(entry?.qualityHint(for: "ja"))
        XCTAssertNil(entry?.qualityHint(for: "xx"))
    }

    private func sampleEntry(
        id: String,
        tier: WhisperModelClassifier.SizeTier,
        hints: [LanguageQualityHint] = []
    ) -> CuratedWhisperModelEntry {
        CuratedWhisperModelEntry(
            id: id,
            displayName: id,
            sizeBytes: 1,
            downloadURL: URL(string: "https://example.com/\(id)")!,
            variant: .multilingual,
            sizeTier: tier,
            perLanguageQualityHints: hints
        )
    }
}
