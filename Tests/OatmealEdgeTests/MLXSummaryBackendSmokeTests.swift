import Foundation
import OatmealCore
@testable import OatmealEdge
import XCTest

final class MLXSummaryBackendSmokeTests: XCTestCase {
    func testMLXSummaryBackendSmokeTestWhenRuntimeAndFixtureArePresent() async throws {
        let environment = ProcessInfo.processInfo.environment

        guard let modelDirectoryPath = environment["OATMEAL_EDGE_MLX_SMOKE_MODEL_DIR"] else {
            throw XCTSkip("Set OATMEAL_EDGE_MLX_SMOKE_MODEL_DIR to run the MLX summary smoke test.")
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: modelDirectoryPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw XCTSkip("Configured MLX summary model directory does not exist: \(modelDirectoryPath)")
        }

        let backend = MLXSummaryBackend()
        let configuration = LocalSummaryConfiguration(
            preferredBackend: .mlxLocal,
            executionPolicy: .requireStructuredSummary,
            preferredModelName: URL(fileURLWithPath: modelDirectoryPath).lastPathComponent
        )
        let discoveredModels = [
            ManagedSummaryModel(
                displayName: URL(fileURLWithPath: modelDirectoryPath).lastPathComponent,
                directoryURL: URL(fileURLWithPath: modelDirectoryPath)
            )
        ]
        let status = backend.status(configuration: configuration, discoveredModels: discoveredModels)

        guard status.isRunnable else {
            throw XCTSkip("MLX summary runtime is not available for the smoke test: \(status.detail)")
        }

        let request = NoteGenerationRequest(
            noteID: UUID(),
            title: "Weekly product sync",
            template: .automatic,
            meetingEvent: CalendarEvent(
                title: "Weekly product sync",
                startDate: Date(timeIntervalSince1970: 1_710_000_000),
                endDate: Date(timeIntervalSince1970: 1_710_003_600),
                attendees: [
                    MeetingParticipant(name: "Alex"),
                    MeetingParticipant(name: "Priya")
                ],
                source: .manual
            ),
            rawNotes: """
            - Reviewed recorder stabilization before shipping more UI.
            - Priya to verify system-audio permission onboarding copy.
            - Need a follow-up on artifact cleanup after successful summaries.
            """,
            transcriptSegments: [
                TranscriptSegment(speakerName: "Alex", text: "We should keep the floating recorder widget deferred until the capture pipeline is stable."),
                TranscriptSegment(speakerName: "Priya", text: "I will verify the system-audio permission onboarding copy and propose edits by tomorrow."),
                TranscriptSegment(speakerName: "Alex", text: "Open question: should we delete normalized audio immediately after successful local processing?")
            ]
        )

        let result = try await backend.generate(
            request: request,
            configuration: configuration,
            discoveredModels: discoveredModels
        )

        XCTAssertEqual(result.backend, .mlxLocal)
        XCTAssertEqual(result.executionKind, .local)
        XCTAssertEqual(result.enhancedNote.templateID, request.template.id)
        XCTAssertFalse(result.enhancedNote.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(
            result.enhancedNote.summary.localizedCaseInsensitiveContains("json"),
            "The smoke-test output should be a real summary, not raw schema echo."
        )
        XCTAssertTrue(
            !result.enhancedNote.keyDiscussionPoints.isEmpty
                || !result.enhancedNote.decisions.isEmpty
                || !result.enhancedNote.risksOrOpenQuestions.isEmpty
                || !result.enhancedNote.actionItems.isEmpty,
            "Expected the MLX backend to return at least one structured field beyond the summary."
        )
    }
}
