import Foundation
import OatmealCore
@testable import OatmealEdge
import XCTest

final class LocalSummaryPipelineTests: XCTestCase {
    func testAutomaticUsesMLXBackendWhenRunnable() async throws {
        let tempDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let pipeline = LocalSummaryPipeline(
            inventory: SummaryModelInventory(modelsDirectoryURL: tempDirectory),
            mlx: StubMLXSummaryBackend(
                reportedStatus: SummaryBackendStatus(
                    backend: .mlxLocal,
                    displayName: "MLX Local",
                    availability: .available,
                    detail: "Ready.",
                    isRunnable: true
                )
            ),
            extractive: StubExtractiveSummaryBackend(
                reportedStatus: SummaryBackendStatus(
                    backend: .extractiveLocal,
                    displayName: "Extractive Local",
                    availability: .available,
                    detail: "Ready.",
                    isRunnable: true
                )
            ),
            placeholder: StubPlaceholderSummaryBackend(
                reportedStatus: SummaryBackendStatus(
                    backend: .placeholder,
                    displayName: "Placeholder",
                    availability: .available,
                    detail: "Ready.",
                    isRunnable: true
                )
            )
        )

        let plan = try await pipeline.executionPlan(configuration: .default)
        XCTAssertEqual(plan.backend, .mlxLocal)
        XCTAssertEqual(plan.executionKind, .local)
    }

    func testAutomaticUsesExtractiveBackendWhenRunnable() async throws {
        let tempDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let pipeline = LocalSummaryPipeline(
            inventory: SummaryModelInventory(modelsDirectoryURL: tempDirectory),
            mlx: StubMLXSummaryBackend(
                reportedStatus: SummaryBackendStatus(
                    backend: .mlxLocal,
                    displayName: "MLX Local",
                    availability: .unavailable,
                    detail: "MLX unavailable.",
                    isRunnable: false
                )
            ),
            extractive: StubExtractiveSummaryBackend(
                reportedStatus: SummaryBackendStatus(
                    backend: .extractiveLocal,
                    displayName: "Extractive Local",
                    availability: .available,
                    detail: "Ready.",
                    isRunnable: true
                )
            ),
            placeholder: StubPlaceholderSummaryBackend(
                reportedStatus: SummaryBackendStatus(
                    backend: .placeholder,
                    displayName: "Placeholder",
                    availability: .available,
                    detail: "Ready.",
                    isRunnable: true
                )
            )
        )

        let plan = try await pipeline.executionPlan(configuration: .default)
        XCTAssertEqual(plan.backend, .extractiveLocal)
        XCTAssertEqual(plan.executionKind, .local)
    }

    func testExplicitExtractiveFallsBackToPlaceholderWhenFallbackIsAllowed() async throws {
        let tempDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let pipeline = LocalSummaryPipeline(
            inventory: SummaryModelInventory(modelsDirectoryURL: tempDirectory),
            mlx: StubMLXSummaryBackend(
                reportedStatus: SummaryBackendStatus(
                    backend: .mlxLocal,
                    displayName: "MLX Local",
                    availability: .unavailable,
                    detail: "MLX unavailable.",
                    isRunnable: false
                )
            ),
            extractive: StubExtractiveSummaryBackend(
                reportedStatus: SummaryBackendStatus(
                    backend: .extractiveLocal,
                    displayName: "Extractive Local",
                    availability: .unavailable,
                    detail: "Extractive runtime is unavailable.",
                    isRunnable: false
                )
            ),
            placeholder: StubPlaceholderSummaryBackend(
                reportedStatus: SummaryBackendStatus(
                    backend: .placeholder,
                    displayName: "Placeholder",
                    availability: .available,
                    detail: "Ready.",
                    isRunnable: true
                )
            )
        )

        let plan = try await pipeline.executionPlan(
            configuration: LocalSummaryConfiguration(
                preferredBackend: .extractiveLocal,
                executionPolicy: .allowFallback
            )
        )

        XCTAssertEqual(plan.backend, .placeholder)
        XCTAssertEqual(plan.executionKind, .placeholder)
        XCTAssertTrue(plan.warningMessages.contains("Extractive runtime is unavailable."))
    }

    func testRequireStructuredSummaryFailsWhenExtractiveBackendIsUnavailable() async {
        let tempDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let pipeline = LocalSummaryPipeline(
            inventory: SummaryModelInventory(modelsDirectoryURL: tempDirectory),
            mlx: StubMLXSummaryBackend(
                reportedStatus: SummaryBackendStatus(
                    backend: .mlxLocal,
                    displayName: "MLX Local",
                    availability: .unavailable,
                    detail: "MLX unavailable.",
                    isRunnable: false
                )
            ),
            extractive: StubExtractiveSummaryBackend(
                reportedStatus: SummaryBackendStatus(
                    backend: .extractiveLocal,
                    displayName: "Extractive Local",
                    availability: .unavailable,
                    detail: "Extractive runtime is unavailable.",
                    isRunnable: false
                )
            ),
            placeholder: StubPlaceholderSummaryBackend(
                reportedStatus: SummaryBackendStatus(
                    backend: .placeholder,
                    displayName: "Placeholder",
                    availability: .available,
                    detail: "Ready.",
                    isRunnable: true
                )
            )
        )

        do {
            _ = try await pipeline.executionPlan(
                    configuration: LocalSummaryConfiguration(
                        preferredBackend: .extractiveLocal,
                        executionPolicy: .requireStructuredSummary
                    )
                )
            XCTFail("Expected the summary pipeline to fail when structured summary is required.")
        } catch {
            XCTAssertEqual(
                error as? SummaryPipelineError,
                .localRuntimeRequired("Extractive runtime is unavailable.")
            )
        }
    }

    func testExtractiveSummaryBuildsStructuredEnhancedNote() async throws {
        let tempDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let pipeline = LocalSummaryPipeline(
            inventory: SummaryModelInventory(modelsDirectoryURL: tempDirectory),
            mlx: StubMLXSummaryBackend(
                reportedStatus: SummaryBackendStatus(
                    backend: .mlxLocal,
                    displayName: "MLX Local",
                    availability: .unavailable,
                    detail: "MLX unavailable.",
                    isRunnable: false
                )
            ),
            extractive: ExtractiveSummaryBackend(),
            placeholder: StubPlaceholderSummaryBackend(
                reportedStatus: SummaryBackendStatus(
                    backend: .placeholder,
                    displayName: "Placeholder",
                    availability: .available,
                    detail: "Ready.",
                    isRunnable: true
                )
            )
        )

        let segment1 = TranscriptSegment(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            speakerName: "Jordan",
            text: "We decided to ship the macOS beta to design partners next Tuesday."
        )
        let segment2 = TranscriptSegment(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            speakerName: "Alex",
            text: "Alex to send the revised onboarding copy after the meeting."
        )
        let segment3 = TranscriptSegment(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            speakerName: "Priya",
            text: "Open question: do we need screen-sharing indicators in the recorder widget?"
        )

        let request = NoteGenerationRequest(
            noteID: UUID(),
            title: "Recorder architecture review",
            template: .automatic,
            meetingEvent: CalendarEvent(
                title: "Recorder architecture review",
                startDate: Date(timeIntervalSince1970: 1_710_000_000),
                endDate: Date(timeIntervalSince1970: 1_710_003_600),
                attendees: [
                    MeetingParticipant(name: "Alex"),
                    MeetingParticipant(name: "Priya")
                ],
                source: .manual
            ),
            rawNotes: """
            - Reviewed Jamie-style recorder constraints
            - Agreed to keep widget work behind a stable capture pipeline
            - Priya to draft launch checklist
            - Risk: system audio permission flow still feels fragile
            """,
            transcriptSegments: [segment1, segment2, segment3]
        )

        let result = try await pipeline.generate(request: request, configuration: .default)
        let enhancedNote = result.enhancedNote

        XCTAssertEqual(result.backend, .extractiveLocal)
        XCTAssertEqual(result.executionKind, .local)
        XCTAssertEqual(enhancedNote.templateID, request.template.id)
        XCTAssertTrue(enhancedNote.summary.contains("Recorder architecture review"))
        XCTAssertTrue(enhancedNote.keyDiscussionPoints.contains("Reviewed Jamie-style recorder constraints"))
        XCTAssertTrue(enhancedNote.decisions.contains { $0.contains("Agreed to keep widget work behind a stable capture pipeline") })
        XCTAssertTrue(enhancedNote.decisions.contains { $0.contains("ship the macOS beta") })
        XCTAssertTrue(enhancedNote.risksOrOpenQuestions.contains { $0.contains("system audio permission flow") })
        XCTAssertTrue(enhancedNote.risksOrOpenQuestions.contains { $0.contains("screen-sharing indicators") })
        XCTAssertTrue(enhancedNote.actionItems.contains { $0.assignee == "Priya" && $0.text.contains("draft launch checklist") })
        XCTAssertTrue(enhancedNote.actionItems.contains { $0.assignee == "Alex" && $0.text.contains("revised onboarding copy") })
        XCTAssertFalse(enhancedNote.citations.isEmpty)
        XCTAssertTrue(enhancedNote.citations.contains { $0.transcriptSegmentIDs.contains(segment1.id) })
        XCTAssertTrue(enhancedNote.citations.contains { $0.transcriptSegmentIDs.contains(segment2.id) })
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private struct StubMLXSummaryBackend: MLXSummaryServing {
    let reportedStatus: SummaryBackendStatus
    var generatedNote: EnhancedNote?

    func status(
        configuration: LocalSummaryConfiguration,
        discoveredModels: [ManagedSummaryModel]
    ) -> SummaryBackendStatus {
        reportedStatus
    }

    func generate(
        request: NoteGenerationRequest,
        configuration: LocalSummaryConfiguration,
        discoveredModels: [ManagedSummaryModel]
    ) async throws -> SummaryJobResult {
        SummaryJobResult(
            enhancedNote: generatedNote ?? EnhancedNote(
                generatedAt: Date(timeIntervalSince1970: 321),
                templateID: request.template.id,
                summary: "MLX output"
            ),
            backend: .mlxLocal,
            executionKind: .local
        )
    }
}

private struct StubExtractiveSummaryBackend: ExtractiveSummaryServing {
    let reportedStatus: SummaryBackendStatus
    var generatedNote: EnhancedNote?

    func status(configuration: LocalSummaryConfiguration) -> SummaryBackendStatus {
        reportedStatus
    }

    func generate(
        request: NoteGenerationRequest,
        configuration: LocalSummaryConfiguration
    ) async throws -> SummaryJobResult {
        SummaryJobResult(
            enhancedNote: generatedNote ?? EnhancedNote(
                generatedAt: Date(timeIntervalSince1970: 123),
                templateID: request.template.id,
                summary: "Extractive output"
            ),
            backend: .extractiveLocal,
            executionKind: .local
        )
    }
}

private struct StubPlaceholderSummaryBackend: PlaceholderSummaryServing {
    let reportedStatus: SummaryBackendStatus
    var generatedNote: EnhancedNote?

    func status() -> SummaryBackendStatus {
        reportedStatus
    }

    func generate(request: NoteGenerationRequest) async throws -> SummaryJobResult {
        guard let generatedNote else {
            throw SummaryPipelineError.backendUnavailable(reportedStatus.detail)
        }

        return SummaryJobResult(
            enhancedNote: generatedNote,
            backend: .placeholder,
            executionKind: .placeholder
        )
    }
}
