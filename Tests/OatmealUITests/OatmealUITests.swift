import Foundation
import OatmealCore
import OatmealEdge
@testable import OatmealUI
import XCTest

@MainActor
final class OatmealUITests: XCTestCase {
    func testToggleCaptureQueuesAndCompletesPostCaptureProcessing() async throws {
        let note = MeetingNote(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            title: "Quick Note",
            origin: .quickNote(createdAt: date(1_700_000_000)),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready,
            rawNotes: "### Context\n- follow up on launch timing"
        )
        let artifactURL = try makeRecordingFixtureURL(fileName: "queued-processing.m4a")
        let captureEngine = StubCaptureEngine(
            artifact: CaptureArtifact(
                noteID: note.id,
                fileURL: artifactURL,
                startedAt: date(1_700_000_100),
                endedAt: date(1_700_000_400),
                mode: .microphoneOnly
            )
        )
        let transcriptionService = StubTranscriptionService(
            result: TranscriptionJobResult(
                segments: [TranscriptSegment(text: "Action: finalize the launch checklist.")],
                backend: .mock,
                executionKind: .placeholder
            )
        )
        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let model = AppViewModel(
            store: InMemoryOatmealStore(notes: [note]),
            generator: StubNoteGenerationService(),
            calendarService: StubCalendarService(),
            captureService: StubCaptureAccessService(),
            captureEngine: captureEngine,
            transcriptionService: transcriptionService,
            persistence: persistence,
            nowProvider: { Date(timeIntervalSince1970: 1_700_000_500) }
        )

        model.selectedNoteID = note.id

        await model.toggleCapture()
        XCTAssertEqual(model.selectedNote?.captureState.phase, .capturing)

        await model.toggleCapture()

        XCTAssertEqual(model.selectedNote?.captureState.phase, .complete)
        XCTAssertEqual(model.selectedNote?.processingState.stage, .transcription)
        XCTAssertEqual(model.selectedNote?.processingState.status, .queued)

        let completed = await waitUntil {
            model.selectedNote?.generationStatus == .succeeded
                && model.selectedNote?.transcriptionStatus == .succeeded
        }

        XCTAssertTrue(completed)
        XCTAssertEqual(model.selectedNote?.transcriptSegments.count, 1)
        XCTAssertNotNil(model.selectedNote?.enhancedNote)

        let stats = await transcriptionService.stats()
        XCTAssertEqual(stats.executionPlanCalls, 1)
        XCTAssertEqual(stats.transcribeCalls, 1)
    }

    func testLoadSystemStateResumesPendingTranscriptionAndGeneration() async throws {
        let noteID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let artifactURL = try makeRecordingFixtureURL(fileName: "recovery-transcription.m4a")
        var note = MeetingNote(
            id: noteID,
            title: "Recovered Note",
            origin: .quickNote(createdAt: date(1_700_001_000)),
            templateID: NoteTemplate.automatic.id,
            captureState: CaptureSessionState(
                phase: .complete,
                startedAt: date(1_700_001_100),
                endedAt: date(1_700_001_500)
            ),
            transcriptionStatus: .pending,
            rawNotes: "### Decisions\n- Keep recovery deterministic"
        )
        note.generationStatus = .idle

        let transcriptionService = StubTranscriptionService(
            result: TranscriptionJobResult(
                segments: [TranscriptSegment(text: "We decided to resume pending jobs on launch.")],
                backend: .mock,
                executionKind: .placeholder
            )
        )
        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let model = AppViewModel(
            store: InMemoryOatmealStore(notes: [note]),
            generator: StubNoteGenerationService(),
            calendarService: StubCalendarService(),
            captureService: StubCaptureAccessService(),
            captureEngine: StubCaptureEngine(recordingURLs: [noteID: artifactURL]),
            transcriptionService: transcriptionService,
            persistence: persistence,
            nowProvider: { Date(timeIntervalSince1970: 1_700_001_600) }
        )

        await model.loadSystemState()

        let completed = await waitUntil {
            model.selectedNote?.transcriptionStatus == .succeeded
                && model.selectedNote?.generationStatus == .succeeded
        }

        XCTAssertTrue(completed)
        XCTAssertEqual(model.selectedNote?.transcriptSegments.count, 1)
        XCTAssertNotNil(model.selectedNote?.enhancedNote)

        let stats = await transcriptionService.stats()
        XCTAssertEqual(stats.transcribeCalls, 1)
    }

    func testLoadSystemStateResumesGenerationWithoutRetranscribing() async throws {
        let noteID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        var note = MeetingNote(
            id: noteID,
            title: "Generation Recovery",
            origin: .quickNote(createdAt: date(1_700_002_000)),
            templateID: NoteTemplate.automatic.id,
            captureState: CaptureSessionState(
                phase: .complete,
                startedAt: date(1_700_002_100),
                endedAt: date(1_700_002_500)
            ),
            generationStatus: .pending,
            transcriptionStatus: .succeeded,
            rawNotes: "### Summary\n- Use transcript when it already exists",
            transcriptSegments: [TranscriptSegment(text: "Transcript is already ready.")]
        )
        note.beginGeneration(templateID: NoteTemplate.automatic.id, at: date(1_700_002_550))

        let transcriptionService = StubTranscriptionService(
            result: TranscriptionJobResult(
                segments: [TranscriptSegment(text: "This should not be used.")],
                backend: .mock,
                executionKind: .placeholder
            )
        )
        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let model = AppViewModel(
            store: InMemoryOatmealStore(notes: [note]),
            generator: StubNoteGenerationService(),
            calendarService: StubCalendarService(),
            captureService: StubCaptureAccessService(),
            captureEngine: StubCaptureEngine(recordingURLs: [:]),
            transcriptionService: transcriptionService,
            persistence: persistence,
            nowProvider: { Date(timeIntervalSince1970: 1_700_002_600) }
        )

        await model.loadSystemState()

        let completed = await waitUntil {
            model.selectedNote?.generationStatus == .succeeded
        }

        XCTAssertTrue(completed)
        XCTAssertEqual(model.selectedNote?.transcriptSegments.first?.text, "Transcript is already ready.")
        XCTAssertNotNil(model.selectedNote?.enhancedNote)

        let stats = await transcriptionService.stats()
        XCTAssertEqual(stats.transcribeCalls, 0)
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func makePersistence() -> AppPersistence {
        AppPersistence(applicationSupportFolderName: "OatmealUITests-\(UUID().uuidString)")
    }

    private func removePersistenceArtifacts(_ persistence: AppPersistence) {
        try? FileManager.default.removeItem(at: persistence.applicationSupportDirectoryURL)
    }

    private func makeRecordingFixtureURL(fileName: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName, isDirectory: false)
        try Data("fixture".utf8).write(to: url, options: [.atomic])
        return url
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        pollIntervalNanoseconds: UInt64 = 20_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
        return condition()
    }
}

@MainActor
private final class StubCalendarService: CalendarAccessServing {
    func authorizationStatus() -> PermissionStatus { .notDetermined }
    func requestAccess() async -> PermissionStatus { .notDetermined }
    func upcomingEvents(referenceDate: Date, horizon: TimeInterval) async throws -> [CalendarEvent] { [] }
}

@MainActor
private final class StubCaptureAccessService: CaptureAccessServing {
    func currentPermissions(calendarStatus: PermissionStatus) async -> CapturePermissions {
        CapturePermissions(
            microphone: .granted,
            systemAudio: .granted,
            notifications: .granted,
            calendar: calendarStatus
        )
    }

    func requestPermissions(requiresSystemAudio: Bool, calendarStatus: PermissionStatus) async -> CapturePermissions {
        await currentPermissions(calendarStatus: calendarStatus)
    }
}

@MainActor
private final class StubCaptureEngine: MeetingCaptureEngineServing {
    private(set) var activeSession: ActiveCaptureSession?
    private let artifact: CaptureArtifact?
    private let recordingURLs: [UUID: URL]

    init(artifact: CaptureArtifact? = nil, recordingURLs: [UUID: URL] = [:]) {
        self.artifact = artifact
        self.recordingURLs = recordingURLs
    }

    func startCapture(for noteID: UUID, mode: CaptureMode) async throws -> ActiveCaptureSession {
        let fileURL = artifact?.fileURL
            ?? recordingURLs[noteID]
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("\(noteID.uuidString).m4a")
        let session = ActiveCaptureSession(
            noteID: noteID,
            startedAt: artifact?.startedAt ?? Date(),
            fileURL: fileURL,
            mode: mode
        )
        activeSession = session
        return session
    }

    func stopCapture() async throws -> CaptureArtifact {
        guard let artifact else {
            throw CaptureEngineError.noActiveCapture
        }
        activeSession = nil
        return artifact
    }

    func recordingURL(for noteID: UUID) -> URL? {
        recordingURLs[noteID] ?? (artifact?.noteID == noteID ? artifact?.fileURL : nil)
    }
}

private actor StubTranscriptionService: LocalTranscriptionServicing {
    private(set) var executionPlanCalls = 0
    private(set) var transcribeCalls = 0

    private let runtimeStateValue = LocalTranscriptionRuntimeState(
        modelsDirectoryURL: FileManager.default.temporaryDirectory,
        discoveredModels: [],
        backends: [],
        activePlanSummary: "Stub runtime"
    )
    private let plan = TranscriptionExecutionPlan(
        backend: .mock,
        executionKind: .placeholder,
        summary: "Stub plan"
    )
    private let result: TranscriptionJobResult

    init(result: TranscriptionJobResult) {
        self.result = result
    }

    func runtimeState(configuration: LocalTranscriptionConfiguration) async -> LocalTranscriptionRuntimeState {
        runtimeStateValue
    }

    func executionPlan(configuration: LocalTranscriptionConfiguration) async throws -> TranscriptionExecutionPlan {
        executionPlanCalls += 1
        return plan
    }

    func transcribe(
        request: TranscriptionRequest,
        configuration: LocalTranscriptionConfiguration
    ) async throws -> TranscriptionJobResult {
        transcribeCalls += 1
        return result
    }

    func stats() -> (executionPlanCalls: Int, transcribeCalls: Int) {
        (executionPlanCalls, transcribeCalls)
    }
}

private struct StubNoteGenerationService: NoteGenerationService {
    func generate(from request: NoteGenerationRequest) throws -> EnhancedNote {
        EnhancedNote(
            generatedAt: Date(),
            templateID: request.template.id,
            summary: "Generated summary for \(request.title)",
            keyDiscussionPoints: request.rawNotes
                .split(separator: "\n")
                .map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            decisions: request.transcriptSegments.map(\.text),
            actionItems: request.transcriptSegments.map { ActionItem(text: $0.text) }
        )
    }
}
