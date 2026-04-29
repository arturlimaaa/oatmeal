import Foundation
@testable import OatmealEdge
import XCTest

final class WhisperModelClassifierTests: XCTestCase {
    func testClassifiesEnglishOnlyVariants() {
        let cases: [(String, WhisperModelClassifier.SizeTier)] = [
            ("ggml-tiny.en.bin", .tiny),
            ("ggml-base.en.bin", .base),
            ("ggml-small.en.bin", .small),
            ("ggml-medium.en.bin", .medium),
            ("ggml-large.en.bin", .large),
            ("ggml-small.en-q5_0.bin", .small),
            ("ggml-base.en-q4_0.bin", .base),
            ("whisper-small.en.gguf", .small),
            ("GGML-MEDIUM.EN.BIN", .medium)
        ]

        for (filename, expectedTier) in cases {
            let classification = WhisperModelClassifier.classify(filename: filename)
            XCTAssertEqual(classification.variant, .englishOnly, "Expected \(filename) to be englishOnly")
            XCTAssertEqual(classification.sizeTier, expectedTier, "Expected \(filename) tier = \(expectedTier)")
        }
    }

    func testClassifiesMultilingualVariants() {
        let cases: [(String, WhisperModelClassifier.SizeTier)] = [
            ("ggml-tiny.bin", .tiny),
            ("ggml-base.bin", .base),
            ("ggml-small.bin", .small),
            ("ggml-medium.bin", .medium),
            ("ggml-large.bin", .large),
            ("ggml-large-v3.bin", .large),
            ("ggml-large-v3-turbo.bin", .large),
            ("ggml-medium-q5_0.bin", .medium),
            ("whisper-small.gguf", .small),
            ("GGML-BASE.BIN", .base)
        ]

        for (filename, expectedTier) in cases {
            let classification = WhisperModelClassifier.classify(filename: filename)
            XCTAssertEqual(classification.variant, .multilingual, "Expected \(filename) to be multilingual")
            XCTAssertEqual(classification.sizeTier, expectedTier, "Expected \(filename) tier = \(expectedTier)")
        }
    }

    func testClassifiesWhisperFilenamesWithoutSizeAsOther() {
        let cases = [
            "whisper-custom.bin",
            "whisper.gguf",
            "my-whisper-model.bin"
        ]

        for filename in cases {
            let classification = WhisperModelClassifier.classify(filename: filename)
            XCTAssertEqual(classification.sizeTier, .other, "Expected \(filename) tier = other")
            XCTAssertEqual(classification.variant, .multilingual, "Expected \(filename) variant = multilingual")
        }
    }

    func testClassifiesUnknownFilenamesAsMultilingualOther() {
        let cases = [
            "random.bin",
            "fancy-model.gguf",
            "asdf.bin"
        ]

        for filename in cases {
            let classification = WhisperModelClassifier.classify(filename: filename)
            XCTAssertEqual(classification.variant, .multilingual)
            XCTAssertEqual(classification.sizeTier, .other)
        }
    }

    func testDoesNotMisreadEnAsEnglishOnlyInsideOtherTokens() {
        // Words that contain the letters "en" but not the bounded `.en` token
        // must remain multilingual.
        let cases = [
            "frozen-base.bin",
            "whisper-tencent.bin",
            "open-large.bin"
        ]

        for filename in cases {
            let classification = WhisperModelClassifier.classify(filename: filename)
            XCTAssertEqual(classification.variant, .multilingual, "Expected \(filename) to remain multilingual")
        }
    }

    func testSizeTierOrderingIsExpected() {
        let ordered: [WhisperModelClassifier.SizeTier] = [.tiny, .base, .small, .medium, .large, .other]
        for (lhs, rhs) in zip(ordered, ordered.dropFirst()) {
            XCTAssertLessThan(lhs, rhs, "Expected \(lhs) < \(rhs)")
        }
    }
}
