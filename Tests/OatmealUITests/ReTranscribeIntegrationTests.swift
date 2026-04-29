import Foundation
import OatmealCore
import OatmealEdge
@testable import OatmealUI
import XCTest

/// End-to-end coverage for the multilingual re-transcribe flow exposed on
/// `AppViewModel`. The tests pre-create a retained normalized WAV at the
/// stable per-note path the `AudioRetentionCoordinator` chooses, drive the
/// programmatic re-transcribe API with a different language, and assert that
/// the note's transcription history grows with each attempt and that all
/// attempts run against the same retained WAV.
@MainActor
final class ReTranscribeIntegrationTests: XCTestCase {
    func testReTranscribeAppendsHistoryEntryWithOverriddenLanguageAndReusesRetainedWAV() async throws {
        let persistence = AppPersistence(applicationSupportFolderName: "ReTranscribeIntegrationTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: persistence.applicationSupportDirectoryURL) }

        let noteID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

        // Pre-stage a retained normalized WAV at the stable path the
        // coordinator picks. The retention layout is `Recordings/Normalized/<uuid>.wav`.
        let coordinator = AudioRetentionCoordinator(
            recordingsDirectoryURL: persistence.applicationSupportDirectoryURL
                .appendingPathComponent("Recordings", isDirectory: true)
        )
        try coordinator.prepareNormalizedDirectory()
        let retainedWAVURL = coordinator.paths(for: noteID).normalizedWAVURL
        try Data("WAV".utf8).write(to: retainedWAVURL)

        // Seed a note with a single succeeded transcription attempt to mirror
        // the post-Phase-1 state: auto-detect picked the wrong language.
        var note = MeetingNote(
            id: noteID,
            title: "Bilingual standup",
            origin: .quickNote(createdAt: Date(timeIntervalSince1970: 1_700_100_000)),
            templateID: NoteTemplate.automatic.id,
            captureState: CaptureSessionState(
                phase: .complete,
                startedAt: Date(timeIntervalSince1970: 1_700_100_100),
                endedAt: Date(timeIntervalSince1970: 1_700_100_500)
            )
        )
        note.applyTranscript(
            [TranscriptSegment(text: "We are talking about the launch.")],
            backend: .mock,
            executionKind: .placeholder,
            language: "en",
            at: Date(timeIntervalSince1970: 1_700_100_510)
        )

        let store = InMemoryOatmealStore(notes: [note])
        let transcriptionService = LanguageRecordingTranscriptionService()
        let model = AppViewModel(
            store: store,
            calendarService: NullCalendarService(),
            captureService: NullCaptureAccessService(),
            captureEngine: NullCaptureEngine(),
            transcriptionService: transcriptionService,
            summaryService: NullSummaryService(),
            summaryModelManager: NullSummaryModelManager(),
            persistence: persistence,
            nowProvider: { Date(timeIntervalSince1970: 1_700_100_900) }
        )
        model.selectedNoteID = noteID

        // Programmatic override + re-transcribe with Spanish.
        let result = try await model.reTranscribe(noteID: noteID, language: "es")

        XCTAssertEqual(result.detectedLanguage, "es")

        let updated = try XCTUnwrap(model.selectedNote)
        XCTAssertEqual(updated.language, "es")
        XCTAssertEqual(updated.transcriptionHistory.count, 2)
        XCTAssertEqual(updated.transcriptionHistory.first?.language, "en")
        XCTAssertEqual(updated.transcriptionHistory.last?.language, "es")
        XCTAssertEqual(updated.transcriptionHistory.last?.status, .succeeded)
        XCTAssertEqual(updated.transcriptSegments.first?.text, "Re-transcribed in es")

        let observed = await transcriptionService.observed
        XCTAssertEqual(observed.count, 1)
        let firstObservation = try XCTUnwrap(observed.first)
        XCTAssertEqual(firstObservation.audioFileURL, retainedWAVURL)
        XCTAssertEqual(firstObservation.language, "es")
        XCTAssertEqual(firstObservation.noteID, noteID)
    }

    func testReTranscribeThrowsFileNotFoundWhenRetainedWAVIsMissing() async throws {
        let persistence = AppPersistence(applicationSupportFolderName: "ReTranscribeIntegrationTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: persistence.applicationSupportDirectoryURL) }

        let noteID = UUID(uuidString: "FFFFFFFF-1111-2222-3333-444444444444")!
        var note = MeetingNote(
            id: noteID,
            title: "No retained audio",
            origin: .quickNote(createdAt: Date(timeIntervalSince1970: 1_700_200_000)),
            templateID: NoteTemplate.automatic.id,
            captureState: CaptureSessionState(
                phase: .complete,
                startedAt: Date(timeIntervalSince1970: 1_700_200_100),
                endedAt: Date(timeIntervalSince1970: 1_700_200_500)
            )
        )
        note.applyTranscript(
            [TranscriptSegment(text: "Old transcript without retained audio.")],
            backend: .mock,
            executionKind: .placeholder,
            language: "en",
            at: Date(timeIntervalSince1970: 1_700_200_510)
        )

        let store = InMemoryOatmealStore(notes: [note])
        let transcriptionService = LanguageRecordingTranscriptionService()
        let model = AppViewModel(
            store: store,
            calendarService: NullCalendarService(),
            captureService: NullCaptureAccessService(),
            captureEngine: NullCaptureEngine(),
            transcriptionService: transcriptionService,
            summaryService: NullSummaryService(),
            summaryModelManager: NullSummaryModelManager(),
            persistence: persistence,
            nowProvider: { Date(timeIntervalSince1970: 1_700_200_900) }
        )
        model.selectedNoteID = noteID

        do {
            _ = try await model.reTranscribe(noteID: noteID, language: "es")
            XCTFail("Expected reTranscribe to throw fileNotFound when no retained WAV exists.")
        } catch let error as TranscriptionPipelineError {
            XCTAssertEqual(error, .fileNotFound)
        }

        let updated = try XCTUnwrap(model.selectedNote)
        XCTAssertEqual(updated.transcriptionHistory.count, 1)
        XCTAssertEqual(updated.language, "en")
        let observed = await transcriptionService.observed
        XCTAssertTrue(observed.isEmpty, "Backend should not be invoked when the retained WAV is missing.")
    }
}

// MARK: - Stubs

private actor LanguageRecordingTranscriptionService: LocalTranscriptionServicing {
    struct Observation: Equatable {
        let noteID: UUID
        let audioFileURL: URL
        let language: String
    }

    private(set) var observed: [Observation] = []

    private let runtimeStateValue = LocalTranscriptionRuntimeState(
        modelsDirectoryURL: FileManager.default.temporaryDirectory,
        discoveredModels: [],
        backends: [],
        activePlanSummary: "Stub"
    )

    func runtimeState(configuration: LocalTranscriptionConfiguration) async -> LocalTranscriptionRuntimeState {
        runtimeStateValue
    }

    func executionPlan(configuration: LocalTranscriptionConfiguration) async throws -> TranscriptionExecutionPlan {
        TranscriptionExecutionPlan(
            backend: .mock,
            executionKind: .placeholder,
            summary: "Stub plan"
        )
    }

    func transcribe(
        request: TranscriptionRequest,
        configuration: LocalTranscriptionConfiguration
    ) async throws -> TranscriptionJobResult {
        TranscriptionJobResult(
            segments: [TranscriptSegment(text: "Stub transcript")],
            backend: .mock,
            executionKind: .placeholder
        )
    }

    func reTranscribe(
        noteID: UUID,
        language: String,
        retainedWAVURL: URL,
        configuration: LocalTranscriptionConfiguration
    ) async throws -> TranscriptionJobResult {
        guard FileManager.default.fileExists(atPath: retainedWAVURL.path) else {
            throw TranscriptionPipelineError.fileNotFound
        }
        observed.append(Observation(noteID: noteID, audioFileURL: retainedWAVURL, language: language))
        return TranscriptionJobResult(
            segments: [TranscriptSegment(text: "Re-transcribed in \(language)")],
            backend: .mock,
            executionKind: .placeholder,
            warningMessages: [],
            detectedLanguage: language
        )
    }
}

@MainActor
private final class NullCalendarService: CalendarAccessServing {
    func authorizationStatus() -> PermissionStatus { .notDetermined }
    func requestAccess() async -> PermissionStatus { .notDetermined }
    func upcomingEvents(referenceDate: Date, horizon: TimeInterval) async throws -> [CalendarEvent] { [] }
}

@MainActor
private final class NullCaptureAccessService: CaptureAccessServing {
    func currentPermissions(calendarStatus: PermissionStatus) async -> CapturePermissions {
        CapturePermissions(microphone: .granted, systemAudio: .granted, notifications: .granted, calendar: calendarStatus)
    }

    func requestPermissions(requiresSystemAudio: Bool, calendarStatus: PermissionStatus) async -> CapturePermissions {
        await currentPermissions(calendarStatus: calendarStatus)
    }
}

@MainActor
private final class NullCaptureEngine: MeetingCaptureEngineServing {
    var activeSession: ActiveCaptureSession? { nil }

    func startCapture(for noteID: UUID, mode: CaptureMode) async throws -> ActiveCaptureSession {
        throw CaptureEngineError.noActiveCapture
    }

    func stopCapture() async throws -> CaptureArtifact {
        throw CaptureEngineError.noActiveCapture
    }

    func recordingURL(for noteID: UUID) -> URL? { nil }

    func liveTranscriptionChunks(for noteID: UUID) -> [LiveTranscriptionChunk] { [] }

    func runtimeHealthSnapshot(for noteID: UUID) -> CaptureRuntimeHealthSnapshot? { nil }

    func consumeRuntimeEvents(for noteID: UUID) -> [CaptureRuntimeEvent] { [] }

    func deleteRecording(for noteID: UUID) throws {}
}

@MainActor
private final class NullSummaryService: LocalSummaryServicing {
    private let runtimeStateValue = LocalSummaryRuntimeState(
        modelsDirectoryURL: FileManager.default.temporaryDirectory,
        discoveredModels: [],
        backends: [],
        activePlanSummary: "Null"
    )

    func runtimeState(configuration: LocalSummaryConfiguration) async -> LocalSummaryRuntimeState {
        runtimeStateValue
    }

    func executionPlan(configuration: LocalSummaryConfiguration) async throws -> LocalSummaryExecutionPlan {
        LocalSummaryExecutionPlan(
            backend: .placeholder,
            executionKind: .placeholder,
            summary: "Null plan"
        )
    }

    func generate(
        request: NoteGenerationRequest,
        configuration: LocalSummaryConfiguration
    ) async throws -> SummaryJobResult {
        SummaryJobResult(
            enhancedNote: EnhancedNote(
                generatedAt: Date(),
                templateID: request.template.id,
                summary: "Null"
            ),
            backend: .placeholder,
            executionKind: .placeholder
        )
    }
}

private struct NullSummaryModelManager: LocalSummaryModelManaging {
    func catalogState() async -> SummaryModelCatalogState {
        SummaryModelCatalogState(
            modelsDirectoryURL: FileManager.default.temporaryDirectory,
            downloadAvailability: .unavailable,
            downloadRuntimeDetail: "Null summary model catalog",
            items: []
        )
    }

    func install(modelID: String, forceRedownload: Bool) async throws -> SummaryModelCatalogState {
        await catalogState()
    }

    func remove(modelDirectoryURL: URL) async throws -> SummaryModelCatalogState {
        await catalogState()
    }
}
