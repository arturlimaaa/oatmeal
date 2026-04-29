import Foundation
import OatmealCore
@testable import OatmealEdge
import XCTest

final class WhisperJSONParserLanguageTests: XCTestCase {
    func testParseExtractsDetectedLanguageWhenPresent() throws {
        let data = Data(
            """
            {
              "result": {
                "language": "es"
              },
              "transcription": [
                {
                  "text": " Hola mundo",
                  "offsets": { "from": 0, "to": 1500 },
                  "id": 1,
                  "p": 0.91
                }
              ]
            }
            """.utf8
        )

        let start = Date(timeIntervalSince1970: 1_000)
        let parsed = try WhisperJSONParser.parse(data: data, startedAt: start)

        XCTAssertEqual(parsed.detectedLanguage, "es")
        XCTAssertEqual(parsed.segments.count, 1)
        XCTAssertEqual(parsed.segments[0].text, "Hola mundo")
        XCTAssertEqual(parsed.segments[0].confidence, 0.91)
    }

    func testParseHandlesTopLevelLanguageField() throws {
        let data = Data(
            """
            {
              "language": "pl",
              "transcription": [
                {
                  "text": " Dzień dobry",
                  "offsets": { "from": 100, "to": 1600 },
                  "id": 1
                }
              ]
            }
            """.utf8
        )

        let parsed = try WhisperJSONParser.parse(data: data, startedAt: nil)

        XCTAssertEqual(parsed.detectedLanguage, "pl")
        XCTAssertEqual(parsed.segments.count, 1)
        XCTAssertEqual(parsed.segments[0].text, "Dzień dobry")
    }

    func testParseReturnsNilLanguageWhenFieldMissing() throws {
        let data = Data(
            """
            {
              "transcription": [
                {
                  "text": " hello world",
                  "offsets": { "from": 1200, "to": 3450 },
                  "id": 1,
                  "p": 0.92
                }
              ]
            }
            """.utf8
        )

        let start = Date(timeIntervalSince1970: 1_000)
        let parsed = try WhisperJSONParser.parse(data: data, startedAt: start)

        XCTAssertNil(parsed.detectedLanguage)
        XCTAssertEqual(parsed.segments.count, 1)
        XCTAssertEqual(parsed.segments[0].text, "hello world")
        XCTAssertEqual(parsed.segments[0].startTime, start.addingTimeInterval(1.2))
    }

    func testParseTreatsAutoLanguageAsAbsent() throws {
        // Some whisper.cpp builds echo back the requested `auto` argument
        // rather than the resolved code; we should treat that as "no
        // detection" so downstream consumers do not persist `"auto"` as the
        // note language.
        let data = Data(
            """
            {
              "result": { "language": "auto" },
              "transcription": [
                {
                  "text": " ambiguous",
                  "offsets": { "from": 0, "to": 100 },
                  "id": 1
                }
              ]
            }
            """.utf8
        )

        let parsed = try WhisperJSONParser.parse(data: data, startedAt: nil)

        XCTAssertNil(parsed.detectedLanguage)
        XCTAssertEqual(parsed.segments.count, 1)
    }

    func testParseTranscriptSegmentsBackCompatPreserved() throws {
        // The pre-existing API still returns just segments; this guards
        // against regressions to the older shape.
        let data = Data(
            """
            {
              "result": { "language": "en" },
              "transcription": [
                {
                  "text": " hi",
                  "offsets": { "from": 0, "to": 100 },
                  "id": 1
                }
              ]
            }
            """.utf8
        )

        let segments = try WhisperJSONParser.parseTranscriptSegments(data: data, startedAt: nil)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].text, "hi")
    }
}
