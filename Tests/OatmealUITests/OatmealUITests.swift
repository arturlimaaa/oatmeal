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
            calendarService: StubCalendarService(),
            captureService: StubCaptureAccessService(),
            captureEngine: captureEngine,
            transcriptionService: transcriptionService,
            summaryService: StubSummaryService(),
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
        XCTAssertNil(model.recordingURL(for: model.selectedNote!))

        let stats = await transcriptionService.stats()
        XCTAssertEqual(stats.executionPlanCalls, 1)
        XCTAssertEqual(stats.transcribeCalls, 1)
        XCTAssertEqual(captureEngine.deletedNoteIDs, [note.id])
    }

    func testStartingCaptureBeginsPersistedLiveSession() async throws {
        let noteID = UUID(uuidString: "12121212-3434-5656-7878-909090909090")!
        let note = MeetingNote(
            id: noteID,
            title: "Live Note",
            origin: .quickNote(createdAt: date(1_700_010_000)),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )
        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let model = AppViewModel(
            store: InMemoryOatmealStore(notes: [note]),
            calendarService: StubCalendarService(),
            captureService: StubCaptureAccessService(),
            captureEngine: StubCaptureEngine(),
            transcriptionService: StubTranscriptionService(
                result: TranscriptionJobResult(
                    segments: [],
                    backend: .mock,
                    executionKind: .placeholder
                )
            ),
            summaryService: StubSummaryService(),
            summaryModelManager: StubSummaryModelManager(state: emptySummaryModelCatalogState()),
            persistence: persistence,
            nowProvider: { Date(timeIntervalSince1970: 1_700_010_100) }
        )

        model.selectedNoteID = noteID
        await model.toggleCapture()

        XCTAssertEqual(model.selectedNote?.captureState.phase, .capturing)
        XCTAssertEqual(model.selectedNote?.liveSessionState.status, .live)
        XCTAssertEqual(model.selectedNote?.liveSessionState.previewEntries.first?.kind, .system)
    }

    func testLiveTranscriptionUpdatesPreviewDuringActiveCapture() async throws {
        let noteID = UUID(uuidString: "15151515-3434-5656-7878-909090909090")!
        let note = MeetingNote(
            id: noteID,
            title: "Near-Live Note",
            origin: .quickNote(createdAt: date(1_700_010_500)),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )
        let artifactURL = try makeRecordingFixtureURL(fileName: "live-transcription-preview.m4a")
        let liveChunkURL = try makeRecordingFixtureURL(fileName: "live-transcription-preview-chunk.caf")
        let captureEngine = StubCaptureEngine(
            artifact: CaptureArtifact(
                noteID: noteID,
                fileURL: artifactURL,
                startedAt: date(1_700_010_600),
                endedAt: date(1_700_010_900),
                mode: .microphoneOnly
            ),
            recordingURLs: [noteID: artifactURL],
            liveChunksByNoteID: [
                noteID: [
                    LiveTranscriptionChunk(
                        id: "microphone-0000",
                        noteID: noteID,
                        source: .microphone,
                        fileURL: liveChunkURL,
                        startedAt: date(1_700_010_620),
                        endedAt: date(1_700_010_700)
                    )
                ]
            ]
        )
        let transcriptionService = StubTranscriptionService(
            result: TranscriptionJobResult(
                segments: [
                    TranscriptSegment(
                        speakerName: "Alex",
                        text: "Live transcript chunk from the active capture."
                    )
                ],
                backend: .mock,
                executionKind: .placeholder
            )
        )
        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let model = AppViewModel(
            store: InMemoryOatmealStore(notes: [note]),
            calendarService: StubCalendarService(),
            captureService: StubCaptureAccessService(),
            captureEngine: captureEngine,
            transcriptionService: transcriptionService,
            summaryService: StubSummaryService(),
            summaryModelManager: StubSummaryModelManager(state: emptySummaryModelCatalogState()),
            persistence: persistence,
            nowProvider: { Date(timeIntervalSince1970: 1_700_010_700) },
            liveTranscriptionPollingInterval: 0.25
        )

        model.selectedNoteID = noteID
        model.setLiveTranscriptPanelPresented(true, for: noteID)

        await model.toggleCapture()

        let livePreviewUpdated = await waitUntil {
            model.selectedNote?.liveSessionState.previewEntries.contains(where: {
                $0.text == "Live transcript chunk from the active capture."
            }) == true
        }

        XCTAssertTrue(livePreviewUpdated)
        XCTAssertEqual(model.selectedNote?.liveSessionState.status, .live)

        let liveStats = await transcriptionService.stats()
        XCTAssertGreaterThanOrEqual(liveStats.transcribeCalls, 1)

        await model.toggleCapture()

        let completed = await waitUntil {
            model.selectedNote?.generationStatus == .succeeded
                && model.selectedNote?.transcriptionStatus == .succeeded
        }

        XCTAssertTrue(completed)
    }

    func testActiveCaptureHandlesRuntimeDegradationAndRecoveryEvents() async throws {
        let noteID = UUID(uuidString: "17171717-3434-5656-7878-909090909090")!
        let note = MeetingNote(
            id: noteID,
            title: "Device Change Note",
            origin: .quickNote(createdAt: date(1_700_011_200)),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )
        let artifactURL = try makeRecordingFixtureURL(fileName: "device-change-resilience.m4a")
        let degradedMessage = "A microphone device disconnected. Oatmeal is trying to recover the input automatically."
        let recoveredMessage = "A microphone device changed. Oatmeal recovered the input automatically."
        let recoveredAt = date(1_700_011_500)
        let captureEngine = StubCaptureEngine(
            artifact: CaptureArtifact(
                noteID: noteID,
                fileURL: artifactURL,
                startedAt: date(1_700_011_300),
                endedAt: date(1_700_011_800),
                mode: .microphoneOnly
            ),
            runtimeEventBatchesByNoteID: [
                noteID: [
                    [
                        CaptureRuntimeEvent(
                            noteID: noteID,
                            kind: .degraded,
                            source: .microphone,
                            message: degradedMessage,
                            createdAt: date(1_700_011_350)
                        )
                    ],
                    [
                        CaptureRuntimeEvent(
                            noteID: noteID,
                            kind: .recovered,
                            source: .microphone,
                            message: recoveredMessage,
                            createdAt: recoveredAt
                        )
                    ]
                ]
            ]
        )
        let transcriptionService = StubTranscriptionService(
            result: TranscriptionJobResult(
                segments: [],
                backend: .mock,
                executionKind: .placeholder
            )
        )
        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let model = AppViewModel(
            store: InMemoryOatmealStore(notes: [note]),
            calendarService: StubCalendarService(),
            captureService: StubCaptureAccessService(),
            captureEngine: captureEngine,
            transcriptionService: transcriptionService,
            summaryService: StubSummaryService(),
            summaryModelManager: StubSummaryModelManager(state: emptySummaryModelCatalogState()),
            persistence: persistence,
            nowProvider: { Date(timeIntervalSince1970: 1_700_011_600) },
            liveTranscriptionPollingInterval: 0.25
        )

        model.selectedNoteID = noteID
        model.setLiveTranscriptPanelPresented(true, for: noteID)

        await model.toggleCapture()

        let degraded = await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            model.selectedNote?.captureState.phase == .paused
                && model.selectedNote?.liveSessionState.status == .delayed
                && model.selectedNote?.liveSessionState.previewEntries.contains(where: {
                    $0.kind == .system && $0.text == degradedMessage
                }) == true
        }

        XCTAssertTrue(degraded)
        XCTAssertEqual(model.selectedNote?.liveSessionState.previewEntries.first?.kind, .system)

        let recovered = await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            model.selectedNote?.captureState.phase == .capturing
                && model.selectedNote?.liveSessionState.status == .recovered
                && model.selectedNote?.liveSessionState.previewEntries.contains(where: {
                    $0.kind == .system && $0.text == recoveredMessage
                }) == true
        }

        XCTAssertTrue(recovered)
        XCTAssertTrue(model.selectedNote?.liveSessionState.previewEntries.contains(where: {
            $0.kind == .system && $0.text == degradedMessage
        }) == true)
        XCTAssertTrue(model.selectedNote?.liveSessionState.previewEntries.contains(where: {
            $0.kind == .system && $0.text == recoveredMessage
        }) == true)

        let metrics = try XCTUnwrap(reflectedSessionHealthMetrics(in: model.selectedNote))
        XCTAssertEqual(
            reflectedInt(in: metrics, labels: ["recoveryCount", "recoveries", "recoveryEventsCount"]),
            1
        )
        XCTAssertEqual(
            reflectedInt(in: metrics, labels: ["interruptionCount", "interruptions", "interruptionEventsCount"]),
            1
        )
        XCTAssertEqual(
            reflectedDate(
                in: metrics,
                labels: ["microphoneLastActivityAt", "microphoneLastUpdatedAt", "microphoneActivityAt"]
            ),
            recoveredAt
        )
    }

    func testMicrophoneRuntimeHealthPersistsAcrossReloadDuringActiveCapture() async throws {
        let noteID = UUID(uuidString: "18181818-3434-5656-7878-909090909090")!
        let note = MeetingNote(
            id: noteID,
            title: "Microphone Health Note",
            origin: .quickNote(createdAt: date(1_700_011_200)),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )
        let artifactURL = try makeRecordingFixtureURL(fileName: "microphone-health-persistence.m4a")
        let degradedMessage = "A microphone device disconnected. Oatmeal is trying to recover the input automatically."
        let recoveredMessage = "A microphone device changed. Oatmeal recovered the input automatically."
        let degradedAt = date(1_700_011_350)
        let recoveredAt = date(1_700_011_500)
        let captureEngine = StubCaptureEngine(
            artifact: CaptureArtifact(
                noteID: noteID,
                fileURL: artifactURL,
                startedAt: date(1_700_011_300),
                endedAt: date(1_700_011_800),
                mode: .microphoneOnly
            ),
            runtimeEventBatchesByNoteID: [
                noteID: [
                    [
                        CaptureRuntimeEvent(
                            noteID: noteID,
                            kind: .degraded,
                            source: .microphone,
                            message: degradedMessage,
                            createdAt: degradedAt
                        )
                    ],
                    [
                        CaptureRuntimeEvent(
                            noteID: noteID,
                            kind: .recovered,
                            source: .microphone,
                            message: recoveredMessage,
                            createdAt: recoveredAt
                        )
                    ]
                ]
            ]
        )
        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let model = AppViewModel(
            store: InMemoryOatmealStore(notes: [note]),
            calendarService: StubCalendarService(),
            captureService: StubCaptureAccessService(),
            captureEngine: captureEngine,
            transcriptionService: StubTranscriptionService(
                result: TranscriptionJobResult(
                    segments: [],
                    backend: .mock,
                    executionKind: .placeholder
                )
            ),
            summaryService: StubSummaryService(),
            summaryModelManager: StubSummaryModelManager(state: emptySummaryModelCatalogState()),
            persistence: persistence,
            nowProvider: { Date(timeIntervalSince1970: 1_700_011_600) },
            liveTranscriptionPollingInterval: 0.25
        )

        model.selectedNoteID = noteID
        model.setLiveTranscriptPanelPresented(true, for: noteID)

        await model.toggleCapture()

        let degraded = await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            model.selectedNote?.captureState.phase == .paused
                && model.selectedNote?.liveSessionState.status == .delayed
                && model.selectedNote?.liveSessionState.statusMessage == degradedMessage
                && model.selectedNote?.liveSessionState.previewEntries.contains(where: {
                    $0.kind == .system && $0.text == degradedMessage
                }) == true
        }

        XCTAssertTrue(degraded)
        XCTAssertNil(model.selectedNote?.liveSessionState.lastRecoveryAt)

        let recovered = await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            model.selectedNote?.captureState.phase == .capturing
                && model.selectedNote?.liveSessionState.status == .recovered
                && model.selectedNote?.liveSessionState.statusMessage == recoveredMessage
                && model.selectedNote?.liveSessionState.lastRecoveryAt == recoveredAt
                && model.selectedNote?.liveSessionState.previewEntries.contains(where: {
                    $0.kind == .system && $0.text == recoveredMessage
                }) == true
        }

        XCTAssertTrue(recovered)

        let restored = AppViewModel(
            store: InMemoryOatmealStore(),
            calendarService: StubCalendarService(),
            captureService: StubCaptureAccessService(),
            captureEngine: StubCaptureEngine(),
            transcriptionService: StubTranscriptionService(
                result: TranscriptionJobResult(
                    segments: [],
                    backend: .mock,
                    executionKind: .placeholder
                )
            ),
            summaryService: StubSummaryService(),
            summaryModelManager: StubSummaryModelManager(state: emptySummaryModelCatalogState()),
            persistence: persistence,
            nowProvider: Date.init
        )

        XCTAssertEqual(restored.selectedNote?.id, noteID)
        XCTAssertEqual(restored.selectedNote?.captureState.phase, .capturing)
        XCTAssertEqual(restored.selectedNote?.liveSessionState.status, .recovered)
        XCTAssertEqual(restored.selectedNote?.liveSessionState.statusMessage, recoveredMessage)
        XCTAssertEqual(restored.selectedNote?.liveSessionState.lastRecoveryAt, recoveredAt)
        XCTAssertTrue(restored.selectedNote?.liveSessionState.previewEntries.contains(where: {
            $0.kind == .system && $0.text == degradedMessage
        }) == true)
        XCTAssertTrue(restored.selectedNote?.liveSessionState.previewEntries.contains(where: {
            $0.kind == .system && $0.text == recoveredMessage
        }) == true)

        let metrics = try XCTUnwrap(reflectedSessionHealthMetrics(in: restored.selectedNote))
        XCTAssertEqual(
            reflectedInt(in: metrics, labels: ["recoveryCount", "recoveries", "recoveryEventsCount"]),
            1
        )
        XCTAssertEqual(
            reflectedInt(in: metrics, labels: ["interruptionCount", "interruptions", "interruptionEventsCount"]),
            1
        )
        XCTAssertEqual(
            reflectedDate(
                in: metrics,
                labels: ["microphoneLastActivityAt", "microphoneLastUpdatedAt", "microphoneActivityAt"]
            ),
            recoveredAt
        )
    }

    func testLoadSystemStateMarksRecoveredLiveSessionMetricsAfterRelaunch() async throws {
        let noteID = UUID(uuidString: "1B1B1B1B-3434-5656-7878-909090909090")!
        let startedAt = date(1_700_011_700)
        let lastMicrophoneActivityAt = date(1_700_011_760)
        let lastSystemAudioActivityAt = date(1_700_011_820)
        let recoveredAt = date(1_700_012_000)

        var note = MeetingNote(
            id: noteID,
            title: "Relaunch Recovery Metrics",
            origin: .quickNote(createdAt: startedAt),
            templateID: NoteTemplate.automatic.id,
            captureState: CaptureSessionState(
                phase: .capturing,
                startedAt: startedAt
            )
        )
        note.beginLiveSession(at: startedAt, presentTranscriptPanel: true, tracksSystemAudio: true)
        note.updateLiveCaptureSource(
            LiveCaptureSourceID.microphone,
            status: LiveCaptureSourceStatus.active,
            message: "Microphone connected.",
            updatedAt: lastMicrophoneActivityAt
        )
        note.updateLiveCaptureSource(
            LiveCaptureSourceID.systemAudio,
            status: LiveCaptureSourceStatus.active,
            message: "System audio connected.",
            updatedAt: lastSystemAudioActivityAt
        )

        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let model = AppViewModel(
            store: InMemoryOatmealStore(notes: [note]),
            calendarService: StubCalendarService(),
            captureService: StubCaptureAccessService(),
            captureEngine: StubCaptureEngine(),
            transcriptionService: StubTranscriptionService(
                result: TranscriptionJobResult(
                    segments: [],
                    backend: .mock,
                    executionKind: .placeholder
                )
            ),
            summaryService: StubSummaryService(),
            summaryModelManager: StubSummaryModelManager(state: emptySummaryModelCatalogState()),
            persistence: persistence,
            nowProvider: { recoveredAt }
        )

        model.selectedNoteID = noteID

        await model.loadSystemState()

        let recovered = await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            model.selectedNote?.captureState.phase == .failed
                && model.selectedNote?.captureState.canResumeAfterCrash == true
                && model.selectedNote?.liveSessionState.status == .recovered
                && model.selectedNote?.liveSessionState.lastRecoveryAt == recoveredAt
                && model.selectedNote?.liveSessionState.previewEntries.contains(where: {
                    $0.kind == LiveTranscriptEntryKind.system
                        && $0.text.localizedCaseInsensitiveContains("restored this live session after relaunch")
                }) == true
        }

        XCTAssertTrue(recovered)

        let recoveredMetrics = try XCTUnwrap(reflectedSessionHealthMetrics(in: model.selectedNote))
        XCTAssertEqual(
            reflectedInt(in: recoveredMetrics, labels: ["recoveryCount", "recoveries", "recoveryEventsCount"]),
            1
        )
        XCTAssertEqual(
            reflectedInt(in: recoveredMetrics, labels: ["interruptionCount", "interruptions", "interruptionEventsCount"]),
            1
        )
        XCTAssertEqual(
            reflectedDate(
                in: recoveredMetrics,
                labels: ["microphoneLastActivityAt", "microphoneLastUpdatedAt", "microphoneActivityAt"]
            ),
            lastMicrophoneActivityAt
        )
        XCTAssertEqual(
            reflectedDate(
                in: recoveredMetrics,
                labels: ["systemAudioLastActivityAt", "systemAudioLastUpdatedAt", "systemAudioActivityAt"]
            ),
            lastSystemAudioActivityAt
        )

        let restored = AppViewModel(
            store: InMemoryOatmealStore(),
            calendarService: StubCalendarService(),
            captureService: StubCaptureAccessService(),
            captureEngine: StubCaptureEngine(),
            transcriptionService: StubTranscriptionService(
                result: TranscriptionJobResult(
                    segments: [],
                    backend: .mock,
                    executionKind: .placeholder
                )
            ),
            summaryService: StubSummaryService(),
            summaryModelManager: StubSummaryModelManager(state: emptySummaryModelCatalogState()),
            persistence: persistence,
            nowProvider: Date.init
        )

        let restoredNote = try XCTUnwrap(restored.notes.first(where: { $0.id == noteID }))
        XCTAssertEqual(restoredNote.captureState.phase, .failed)
        XCTAssertEqual(restoredNote.liveSessionState.status, .recovered)
        XCTAssertEqual(restoredNote.liveSessionState.lastRecoveryAt, recoveredAt)

        let persistedMetrics = try XCTUnwrap(reflectedSessionHealthMetrics(in: restoredNote))
        XCTAssertEqual(
            reflectedInt(in: persistedMetrics, labels: ["recoveryCount", "recoveries", "recoveryEventsCount"]),
            1
        )
        XCTAssertEqual(
            reflectedInt(in: persistedMetrics, labels: ["interruptionCount", "interruptions", "interruptionEventsCount"]),
            1
        )
        XCTAssertEqual(
            reflectedDate(
                in: persistedMetrics,
                labels: ["microphoneLastActivityAt", "microphoneLastUpdatedAt", "microphoneActivityAt"]
            ),
            lastMicrophoneActivityAt
        )
        XCTAssertEqual(
            reflectedDate(
                in: persistedMetrics,
                labels: ["systemAudioLastActivityAt", "systemAudioLastUpdatedAt", "systemAudioActivityAt"]
            ),
            lastSystemAudioActivityAt
        )
    }

    func testActiveCaptureFailureSalvagesPartialRecordingArtifact() async throws {
        let noteID = UUID(uuidString: "19191919-3434-5656-7878-909090909090")!
        let note = MeetingNote(
            id: noteID,
            title: "Capture Failure Salvage",
            origin: .quickNote(createdAt: date(1_700_011_900)),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready,
            rawNotes: "### Context\n- keep partial artifacts for salvage"
        )
        let artifactURL = try makeRecordingFixtureURL(fileName: "runtime-failure-salvage.m4a")
        let failureMessage = "The capture runtime failed, but Oatmeal can still salvage the partial recording."
        let captureEngine = StubCaptureEngine(
            artifact: CaptureArtifact(
                noteID: noteID,
                fileURL: artifactURL,
                startedAt: date(1_700_011_950),
                endedAt: date(1_700_012_350),
                mode: .microphoneOnly
            ),
            recordingURLs: [noteID: artifactURL],
            runtimeEventBatchesByNoteID: [
                noteID: [
                    [
                        CaptureRuntimeEvent(
                            noteID: noteID,
                            kind: .failed,
                            source: .capturePipeline,
                            message: failureMessage,
                            createdAt: date(1_700_012_050)
                        )
                    ]
                ]
            ]
        )
        let transcriptionService = StubTranscriptionService(
            result: TranscriptionJobResult(
                segments: [
                    TranscriptSegment(
                        speakerName: "Meeting Audio",
                        text: "Recovered transcript from the partial recording."
                    )
                ],
                backend: .mock,
                executionKind: .placeholder
            )
        )
        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let model = AppViewModel(
            store: InMemoryOatmealStore(notes: [note]),
            calendarService: StubCalendarService(),
            captureService: StubCaptureAccessService(),
            captureEngine: captureEngine,
            transcriptionService: transcriptionService,
            summaryService: StubSummaryService(),
            persistence: persistence,
            nowProvider: { Date(timeIntervalSince1970: 1_700_012_500) },
            liveTranscriptionPollingInterval: 0.25
        )

        model.selectedNoteID = noteID
        model.setLiveTranscriptPanelPresented(true, for: noteID)

        await model.toggleCapture()

        let failed = await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            model.selectedNote?.captureState.phase == .failed
                && model.selectedNote?.captureState.failureReason == failureMessage
                && model.selectedNote?.liveSessionState.status == .failed
                && model.selectedNote?.liveSessionState.previewEntries.contains(where: {
                    $0.kind == .system && $0.text == failureMessage
                }) == true
        }

        XCTAssertTrue(failed)

        let salvaged = await waitUntil(timeoutNanoseconds: 3_000_000_000) {
            model.selectedNote?.transcriptionStatus == .succeeded
                && model.selectedNote?.generationStatus == .succeeded
                && model.selectedNote?.processingState.stage == .complete
                && model.selectedNote?.processingState.status == .completed
        }

        XCTAssertTrue(salvaged)
        XCTAssertEqual(
            model.selectedNote?.transcriptSegments.map(\.text),
            ["Recovered transcript from the partial recording."]
        )
        XCTAssertNotNil(model.selectedNote?.enhancedNote)
        XCTAssertEqual(model.selectedNote?.liveSessionState.status, .failed)
        let failureAt = date(1_700_012_050)
        XCTAssertEqual(model.selectedNote?.liveSessionState.microphoneSource.lastUpdatedAt, failureAt)

        let metrics = try XCTUnwrap(reflectedSessionHealthMetrics(in: model.selectedNote))
        XCTAssertEqual(
            reflectedInt(in: metrics, labels: ["interruptionCount", "interruptions", "interruptionEventsCount"]),
            1
        )
        XCTAssertEqual(
            reflectedDate(
                in: metrics,
                labels: ["microphoneLastActivityAt", "microphoneLastUpdatedAt", "microphoneActivityAt"]
            ),
            failureAt
        )

        let stats = await transcriptionService.stats()
        XCTAssertEqual(stats.executionPlanCalls, 1)
        XCTAssertEqual(stats.transcribeCalls, 1)
    }

    func testActiveCaptureTracksPendingLiveChunkBacklogWhileCatchingUp() async throws {
        let noteID = UUID(uuidString: "1A1A1A1A-3434-5656-7878-909090909090")!
        let note = MeetingNote(
            id: noteID,
            title: "Backlog Metrics",
            origin: .quickNote(createdAt: date(1_700_013_000)),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )
        let artifactURL = try makeRecordingFixtureURL(fileName: "backlog-metrics.m4a")
        let firstChunkURL = try makeRecordingFixtureURL(fileName: "backlog-metrics-0000.caf")
        let secondChunkURL = try makeRecordingFixtureURL(fileName: "backlog-metrics-0001.caf")
        let captureEngine = StubCaptureEngine(
            artifact: CaptureArtifact(
                noteID: noteID,
                fileURL: artifactURL,
                startedAt: date(1_700_013_050),
                endedAt: date(1_700_013_500),
                mode: .microphoneOnly
            ),
            recordingURLs: [noteID: artifactURL],
            liveChunksByNoteID: [
                noteID: [
                    LiveTranscriptionChunk(
                        id: "microphone-0000",
                        noteID: noteID,
                        source: .microphone,
                        fileURL: firstChunkURL,
                        startedAt: date(1_700_013_100),
                        endedAt: date(1_700_013_150)
                    ),
                    LiveTranscriptionChunk(
                        id: "microphone-0001",
                        noteID: noteID,
                        source: .microphone,
                        fileURL: secondChunkURL,
                        startedAt: date(1_700_013_151),
                        endedAt: date(1_700_013_200)
                    )
                ]
            ]
        )
        let transcriptionService = PausingTranscriptionService(
            result: TranscriptionJobResult(
                segments: [TranscriptSegment(text: "Chunk processed while backlog was pending.")],
                backend: .mock,
                executionKind: .placeholder
            )
        )
        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let model = AppViewModel(
            store: InMemoryOatmealStore(notes: [note]),
            calendarService: StubCalendarService(),
            captureService: StubCaptureAccessService(),
            captureEngine: captureEngine,
            transcriptionService: transcriptionService,
            summaryService: StubSummaryService(),
            summaryModelManager: StubSummaryModelManager(state: emptySummaryModelCatalogState()),
            persistence: persistence,
            nowProvider: { Date(timeIntervalSince1970: 1_700_013_250) },
            liveTranscriptionPollingInterval: 0.1
        )

        model.selectedNoteID = noteID
        model.setLiveTranscriptPanelPresented(true, for: noteID)

        await model.toggleCapture()

        let backlogObserved = await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            guard let note = model.selectedNote,
                  let metrics = self.reflectedSessionHealthMetrics(in: note) else {
                return false
            }

            return self.reflectedInt(
                in: metrics,
                labels: ["pendingLiveChunkCount", "pendingChunkCount", "backlogDepth", "backlogCount"]
            ) == 1
        }

        XCTAssertTrue(backlogObserved)

        await transcriptionService.resumeFirstTranscription()

        let caughtUp = await waitUntil(timeoutNanoseconds: 3_000_000_000) {
            model.selectedNote?.liveSessionState.processedChunkIDs.sorted() == [
                "microphone-0000",
                "microphone-0001"
            ]
        }

        XCTAssertTrue(caughtUp)

        let metrics = try XCTUnwrap(reflectedSessionHealthMetrics(in: model.selectedNote))
        XCTAssertEqual(
            reflectedInt(in: metrics, labels: ["pendingLiveChunkCount", "pendingChunkCount", "backlogDepth", "backlogCount"]),
            0
        )
        XCTAssertEqual(
            reflectedInt(in: metrics, labels: ["peakPendingChunkCount", "peakBacklogCount", "maxPendingChunkCount"]),
            1
        )
        XCTAssertNil(
            reflectedDate(
                in: metrics,
                labels: ["oldestPendingChunkStartedAt", "oldestPendingChunkAt", "oldestBacklogChunkAt"]
            )
        )
        XCTAssertEqual(
            reflectedDate(
                in: metrics,
                labels: ["lastMergedLiveChunkAt", "lastMergedChunkAt", "mergedChunkAt"]
            ),
            date(1_700_013_250)
        )
        XCTAssertEqual(
            reflectedInt(in: metrics, labels: ["peakPendingChunkCount", "peakBacklogCount", "maxPendingChunkCount"]),
            1
        )
        XCTAssertEqual(
            try XCTUnwrap(
                reflectedDouble(in: metrics, labels: ["lastMergedChunkLatency", "chunkLatency", "lastChunkLatency"])
            ),
            date(1_700_013_250).timeIntervalSince(date(1_700_013_200)),
            accuracy: 0.001
        )
    }

    func testSetLiveTranscriptPanelPresentedPersistsAcrossReload() async throws {
        let noteID = UUID(uuidString: "13131313-3434-5656-7878-909090909090")!
        let note = MeetingNote(
            id: noteID,
            title: "Panel Preference",
            origin: .quickNote(createdAt: date(1_700_010_200)),
            templateID: NoteTemplate.automatic.id,
            captureState: .ready
        )
        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let model = AppViewModel(
            store: InMemoryOatmealStore(notes: [note]),
            calendarService: StubCalendarService(),
            captureService: StubCaptureAccessService(),
            captureEngine: StubCaptureEngine(),
            transcriptionService: StubTranscriptionService(
                result: TranscriptionJobResult(
                    segments: [],
                    backend: .mock,
                    executionKind: .placeholder
                )
            ),
            summaryService: StubSummaryService(),
            summaryModelManager: StubSummaryModelManager(state: emptySummaryModelCatalogState()),
            persistence: persistence,
            nowProvider: { Date(timeIntervalSince1970: 1_700_010_300) }
        )

        model.setLiveTranscriptPanelPresented(true, for: noteID)

        XCTAssertEqual(model.selectedNote?.liveSessionState.isTranscriptPanelPresented, true)

        let restored = AppViewModel(
            store: InMemoryOatmealStore(),
            calendarService: StubCalendarService(),
            captureService: StubCaptureAccessService(),
            captureEngine: StubCaptureEngine(),
            transcriptionService: StubTranscriptionService(
                result: TranscriptionJobResult(
                    segments: [],
                    backend: .mock,
                    executionKind: .placeholder
                )
            ),
            summaryService: StubSummaryService(),
            summaryModelManager: StubSummaryModelManager(state: emptySummaryModelCatalogState()),
            persistence: persistence,
            nowProvider: Date.init
        )

        XCTAssertEqual(restored.selectedNote?.id, noteID)
        XCTAssertEqual(restored.selectedNote?.liveSessionState.isTranscriptPanelPresented, true)
    }

    func testLiveTranscriptPanelAdapterUsesPersistedPreviewEntriesAndStatusMessage() {
        var note = MeetingNote(
            id: UUID(uuidString: "14141414-3434-5656-7878-909090909090")!,
            title: "Panel Adapter",
            origin: .quickNote(createdAt: date(1_700_010_400)),
            templateID: NoteTemplate.automatic.id,
            captureState: CaptureSessionState(
                phase: .capturing,
                startedAt: date(1_700_010_450)
            )
        )

        note.beginLiveSession(at: date(1_700_010_450), presentTranscriptPanel: true)
        note.appendLiveTranscriptEntry(
            LiveTranscriptEntry(
                createdAt: date(1_700_010_470),
                kind: .transcript,
                speakerName: "Alex",
                text: "Placeholder transcript chunk."
            ),
            updatedAt: date(1_700_010_470)
        )
        note.markLiveSessionDelayed(
            message: "Background transcription is catching up.",
            at: date(1_700_010_480)
        )

        let panelState = LiveTranscriptPanelAdapter.panelState(for: note)

        XCTAssertEqual(panelState?.healthLabel, "Delayed")
        XCTAssertEqual(panelState?.detailText, "Background transcription is catching up.")
        XCTAssertEqual(panelState?.lines.count, 2)
        XCTAssertEqual(panelState?.lines.last?.text, "Placeholder transcript chunk.")
        XCTAssertEqual(panelState?.lines.last?.speakerName, "Alex")
        XCTAssertEqual(panelState?.usesPersistedSessionState, true)
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
            calendarService: StubCalendarService(),
            captureService: StubCaptureAccessService(),
            captureEngine: StubCaptureEngine(recordingURLs: [noteID: artifactURL]),
            transcriptionService: transcriptionService,
            summaryService: StubSummaryService(),
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
            calendarService: StubCalendarService(),
            captureService: StubCaptureAccessService(),
            captureEngine: StubCaptureEngine(recordingURLs: [:]),
            transcriptionService: transcriptionService,
            summaryService: StubSummaryService(),
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

    func testRetryGenerationRunsWithoutRetranscribing() async throws {
        let noteID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        var note = MeetingNote(
            id: noteID,
            title: "Retry Generation",
            origin: .quickNote(createdAt: date(1_700_003_000)),
            templateID: NoteTemplate.automatic.id,
            captureState: CaptureSessionState(
                phase: .complete,
                startedAt: date(1_700_003_100),
                endedAt: date(1_700_003_500)
            ),
            generationStatus: .failed,
            transcriptionStatus: .succeeded,
            rawNotes: "### Context\n- Retry generation only",
            transcriptSegments: [TranscriptSegment(text: "Transcript already exists.")]
        )
        note.recordGenerationFailure("generator crashed", at: date(1_700_003_550))

        let transcriptionService = StubTranscriptionService(
            result: TranscriptionJobResult(
                segments: [TranscriptSegment(text: "This path should not run.")],
                backend: .mock,
                executionKind: .placeholder
            )
        )
        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let model = AppViewModel(
            store: InMemoryOatmealStore(notes: [note]),
            calendarService: StubCalendarService(),
            captureService: StubCaptureAccessService(),
            captureEngine: StubCaptureEngine(),
            transcriptionService: transcriptionService,
            summaryService: StubSummaryService(),
            persistence: persistence,
            nowProvider: { Date(timeIntervalSince1970: 1_700_003_600) }
        )

        model.selectedNoteID = noteID
        XCTAssertTrue(model.canRetryGeneration(for: note))

        model.retryGeneration()

        let completed = await waitUntil {
            model.selectedNote?.generationStatus == .succeeded
        }

        XCTAssertTrue(completed)
        XCTAssertNotNil(model.selectedNote?.enhancedNote)

        let stats = await transcriptionService.stats()
        XCTAssertEqual(stats.transcribeCalls, 0)
    }

    func testRetryTranscriptionUsesRetainedRecordingAndRegeneratesNote() async throws {
        let noteID = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
        let artifactURL = try makeRecordingFixtureURL(fileName: "retry-transcription.m4a")
        var note = MeetingNote(
            id: noteID,
            title: "Retry Transcription",
            origin: .quickNote(createdAt: date(1_700_004_000)),
            templateID: NoteTemplate.automatic.id,
            captureState: CaptureSessionState(
                phase: .complete,
                startedAt: date(1_700_004_100),
                endedAt: date(1_700_004_500)
            ),
            generationStatus: .failed,
            transcriptionStatus: .failed,
            rawNotes: "### Context\n- Keep the artifact for retry"
        )
        note.recordTranscriptionFailure(
            backend: .mock,
            executionKind: .placeholder,
            message: "temporary runtime issue",
            at: date(1_700_004_520)
        )
        note.recordGenerationFailure("blocked on transcript", at: date(1_700_004_530))

        let captureEngine = StubCaptureEngine(recordingURLs: [noteID: artifactURL])
        let transcriptionService = StubTranscriptionService(
            result: TranscriptionJobResult(
                segments: [TranscriptSegment(text: "Retry succeeded from the retained artifact.")],
                backend: .mock,
                executionKind: .placeholder
            )
        )
        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let model = AppViewModel(
            store: InMemoryOatmealStore(notes: [note]),
            calendarService: StubCalendarService(),
            captureService: StubCaptureAccessService(),
            captureEngine: captureEngine,
            transcriptionService: transcriptionService,
            summaryService: StubSummaryService(),
            persistence: persistence,
            nowProvider: { Date(timeIntervalSince1970: 1_700_004_600) }
        )

        model.selectedNoteID = noteID
        XCTAssertTrue(model.canRetryTranscription(for: note))

        model.retryTranscription()

        let completed = await waitUntil {
            model.selectedNote?.generationStatus == .succeeded
                && model.selectedNote?.transcriptionStatus == .succeeded
        }

        XCTAssertTrue(completed)
        XCTAssertEqual(model.selectedNote?.transcriptSegments.first?.text, "Retry succeeded from the retained artifact.")
        XCTAssertNil(model.recordingURL(for: model.selectedNote!))

        let stats = await transcriptionService.stats()
        XCTAssertEqual(stats.transcribeCalls, 1)
        XCTAssertEqual(captureEngine.deletedNoteIDs, [noteID])
    }

    func testSummaryConfigurationPersistsAndRestores() async throws {
        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }
        let summaryService = StubSummaryService(
            runtimeState: LocalSummaryRuntimeState(
                modelsDirectoryURL: FileManager.default.temporaryDirectory,
                discoveredModels: [
                    ManagedSummaryModel(
                        displayName: "Qwen2.5-0.5B-Instruct-4bit",
                        directoryURL: FileManager.default.temporaryDirectory
                            .appendingPathComponent("Qwen2.5-0.5B-Instruct-4bit", isDirectory: true)
                    )
                ],
                backends: [],
                activePlanSummary: "Stub summary runtime"
            )
        )

        let model = AppViewModel(
            store: InMemoryOatmealStore.preview(),
            calendarService: StubCalendarService(),
            captureService: StubCaptureAccessService(),
            captureEngine: StubCaptureEngine(),
            transcriptionService: StubTranscriptionService(
                result: TranscriptionJobResult(
                    segments: [],
                    backend: .mock,
                    executionKind: .placeholder
                )
            ),
            summaryService: summaryService,
            persistence: persistence,
            nowProvider: Date.init
        )

        model.setSummaryBackendPreference(.extractiveLocal)
        model.setSummaryExecutionPolicy(.requireStructuredSummary)
        model.setSummaryPreferredModelName("Qwen2.5-0.5B-Instruct-4bit")

        let refreshed = await waitUntil {
            model.summaryRuntimeState?.preferredModelName == "Qwen2.5-0.5B-Instruct-4bit"
        }

        XCTAssertTrue(refreshed)

        let restored = AppViewModel(
            store: InMemoryOatmealStore.preview(),
            calendarService: StubCalendarService(),
            captureService: StubCaptureAccessService(),
            captureEngine: StubCaptureEngine(),
            transcriptionService: StubTranscriptionService(
                result: TranscriptionJobResult(
                    segments: [],
                    backend: .mock,
                    executionKind: .placeholder
                )
            ),
            summaryService: StubSummaryService(),
            persistence: persistence,
            nowProvider: Date.init
        )

        XCTAssertEqual(restored.summaryConfiguration.preferredBackend, .extractiveLocal)
        XCTAssertEqual(restored.summaryConfiguration.executionPolicy, .requireStructuredSummary)
        XCTAssertEqual(restored.summaryConfiguration.preferredModelName, "Qwen2.5-0.5B-Instruct-4bit")
    }

    func testLoadSystemStateUsesSummaryServiceAndExposesPlan() async throws {
        let noteID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        var note = MeetingNote(
            id: noteID,
            title: "Summary Runtime",
            origin: .quickNote(createdAt: date(1_700_005_000)),
            templateID: NoteTemplate.automatic.id,
            captureState: CaptureSessionState(
                phase: .complete,
                startedAt: date(1_700_005_100),
                endedAt: date(1_700_005_500)
            ),
            generationStatus: .idle,
            transcriptionStatus: .succeeded,
            rawNotes: "### Context\n- Use the summary service seam",
            transcriptSegments: [TranscriptSegment(text: "Transcript is already present.")]
        )
        note.processingState = PostCaptureProcessingState(
            stage: .generation,
            status: .queued,
            queuedAt: date(1_700_005_520)
        )

        let summaryService = StubSummaryService(
            runtimeState: LocalSummaryRuntimeState(
                modelsDirectoryURL: FileManager.default.temporaryDirectory,
                discoveredModels: [],
                backends: [
                    SummaryBackendStatus(
                        backend: .extractiveLocal,
                        displayName: "Extractive Local",
                        availability: .available,
                        detail: "Stub edge runtime is available.",
                        isRunnable: true
                    )
                ],
                activePlanSummary: "Stub edge runtime will generate the enhanced note."
            ),
            plan: LocalSummaryExecutionPlan(
                backend: .extractiveLocal,
                executionKind: .local,
                summary: "Stub edge runtime will generate the enhanced note.",
                warningMessages: ["Using stubbed local runtime."]
            ),
            result: SummaryJobResult(
                enhancedNote: EnhancedNote(
                    generatedAt: Date(),
                    templateID: NoteTemplate.automatic.id,
                    summary: "Generated by summary service",
                    keyDiscussionPoints: ["Point A"],
                    decisions: ["Decision A"],
                    actionItems: [ActionItem(text: "Action A")]
                ),
                backend: .extractiveLocal,
                executionKind: .local,
                warningMessages: ["Using stubbed local runtime."]
            )
        )
        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let model = AppViewModel(
            store: InMemoryOatmealStore(notes: [note]),
            calendarService: StubCalendarService(),
            captureService: StubCaptureAccessService(),
            captureEngine: StubCaptureEngine(),
            transcriptionService: StubTranscriptionService(
                result: TranscriptionJobResult(
                    segments: [TranscriptSegment(text: "This should not be used.")],
                    backend: .mock,
                    executionKind: .placeholder
                )
            ),
            summaryService: summaryService,
            persistence: persistence,
            nowProvider: { Date(timeIntervalSince1970: 1_700_005_600) }
        )

        await model.loadSystemState()

        let completed = await waitUntil {
            model.selectedNote?.generationStatus == .succeeded
        }

        XCTAssertTrue(completed)
        XCTAssertEqual(model.selectedNote?.enhancedNote?.summary, "Generated by summary service")
        XCTAssertEqual(model.summaryExecutionPlan(for: model.selectedNote!)?.backend, .extractiveLocal)
        XCTAssertEqual(model.summaryExecutionPlan(for: model.selectedNote!)?.executionKind, .local)

        let stats = await summaryService.stats()
        XCTAssertEqual(stats.executionPlanCalls, 1)
        XCTAssertEqual(stats.generateCalls, 1)
    }

    func testLoadSystemStateRecoversPersistedLiveSessionState() async throws {
        let noteID = UUID(uuidString: "ABABABAB-CDCD-EFEF-1212-343434343434")!
        var note = MeetingNote(
            id: noteID,
            title: "Recovered Live Session",
            origin: .quickNote(createdAt: date(1_700_011_000)),
            templateID: NoteTemplate.automatic.id,
            captureState: CaptureSessionState(
                phase: .capturing,
                startedAt: date(1_700_011_100),
                isRecoverableAfterCrash: true
            )
        )
        note.beginLiveSession(at: date(1_700_011_100), presentTranscriptPanel: true)

        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let model = AppViewModel(
            store: InMemoryOatmealStore(notes: [note]),
            calendarService: StubCalendarService(),
            captureService: StubCaptureAccessService(),
            captureEngine: StubCaptureEngine(),
            transcriptionService: StubTranscriptionService(
                result: TranscriptionJobResult(
                    segments: [],
                    backend: .mock,
                    executionKind: .placeholder
                )
            ),
            summaryService: StubSummaryService(),
            summaryModelManager: StubSummaryModelManager(state: emptySummaryModelCatalogState()),
            persistence: persistence,
            nowProvider: { Date(timeIntervalSince1970: 1_700_011_500) }
        )

        await model.loadSystemState()

        XCTAssertEqual(model.selectedNote?.captureState.phase, .failed)
        XCTAssertEqual(model.selectedNote?.liveSessionState.status, .recovered)
        XCTAssertTrue(model.selectedNote?.liveSessionState.previewEntries.contains(where: {
            $0.text.localizedCaseInsensitiveContains("restored this live session")
        }) == true)
        let metrics = try XCTUnwrap(reflectedSessionHealthMetrics(in: model.selectedNote))
        XCTAssertEqual(
            reflectedInt(in: metrics, labels: ["recoveryCount", "recoveries", "recoveryEventsCount"]),
            1
        )
        XCTAssertEqual(
            reflectedInt(in: metrics, labels: ["interruptionCount", "interruptions", "interruptionEventsCount"]),
            1
        )
    }

    func testLoadSystemStateFallsBackToRecoveredLiveTranscriptWhenFinalPassFails() async throws {
        let noteID = UUID(uuidString: "CDCDCDCD-EFEF-1212-3434-565656565656")!
        var note = MeetingNote(
            id: noteID,
            title: "Recovered Live Transcript",
            origin: .quickNote(createdAt: date(1_700_012_000)),
            templateID: NoteTemplate.automatic.id,
            captureState: CaptureSessionState(
                phase: .complete,
                startedAt: date(1_700_012_100),
                endedAt: date(1_700_012_900)
            ),
            rawNotes: "### Context\n- keep the recovered live transcript if the final pass fails"
        )
        note.beginLiveSession(at: date(1_700_012_100), presentTranscriptPanel: true)
        note.appendLiveTranscriptEntry(
            LiveTranscriptEntry(
                createdAt: date(1_700_012_400),
                speakerName: "Meeting Audio",
                text: "Customer wants offline-first meeting notes."
            ),
            updatedAt: date(1_700_012_400)
        )
        note.completeLiveSession(at: date(1_700_012_900))

        let recordingURL = FileManager.default.temporaryDirectory.appendingPathComponent("recovered-live-\(noteID.uuidString).m4a")
        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let captureEngine = StubCaptureEngine(recordingURLs: [noteID: recordingURL])
        let transcriptionService = StubTranscriptionService(
            result: TranscriptionJobResult(
                segments: [],
                backend: .mock,
                executionKind: .placeholder
            ),
            error: NSError(domain: "OatmealUITests", code: 17, userInfo: [NSLocalizedDescriptionKey: "Simulated final-pass failure"])
        )

        let model = AppViewModel(
            store: InMemoryOatmealStore(notes: [note]),
            calendarService: StubCalendarService(),
            captureService: StubCaptureAccessService(),
            captureEngine: captureEngine,
            transcriptionService: transcriptionService,
            summaryService: StubSummaryService(),
            persistence: persistence,
            nowProvider: { Date(timeIntervalSince1970: 1_700_013_000) }
        )

        await model.loadSystemState()

        let completed = await waitUntil {
            model.selectedNote?.generationStatus == .succeeded
        }

        XCTAssertTrue(completed)
        XCTAssertEqual(model.selectedNote?.transcriptionStatus, .succeeded)
        XCTAssertEqual(
            model.selectedNote?.transcriptSegments.map(\.text),
            ["Customer wants offline-first meeting notes."]
        )
        XCTAssertEqual(model.selectedNote?.transcriptionHistory.last?.executionKind, .placeholder)
        XCTAssertTrue(
            model.selectedNote?.transcriptionHistory.last?.warningMessages.contains(where: {
                $0.localizedCaseInsensitiveContains("kept the recovered near-live transcript preview")
            }) == true
        )
        XCTAssertEqual(captureEngine.deletedNoteIDs, [])

        let stats = await transcriptionService.stats()
        XCTAssertEqual(stats.executionPlanCalls, 1)
        XCTAssertEqual(stats.transcribeCalls, 1)
    }

    func testLoadSystemStateCatchesUpOnlyUnprocessedLiveChunksFromSavedArtifacts() async throws {
        let noteID = UUID(uuidString: "DEDEDEDE-AAAA-BBBB-CCCC-787878787878")!
        let recordingURL = try makeRecordingFixtureURL(fileName: "live-catchup-\(noteID.uuidString).m4a")
        let firstChunkURL = try makeRecordingFixtureURL(fileName: "microphone-0000-\(noteID.uuidString).caf")
        let secondChunkURL = try makeRecordingFixtureURL(fileName: "microphone-0001-\(noteID.uuidString).caf")

        var note = MeetingNote(
            id: noteID,
            title: "Chunk Catch-Up",
            origin: .quickNote(createdAt: date(1_700_014_000)),
            templateID: NoteTemplate.automatic.id,
            captureState: CaptureSessionState(
                phase: .complete,
                startedAt: date(1_700_014_100),
                endedAt: date(1_700_014_900)
            ),
            rawNotes: "### Context\n- resume delayed live chunks after relaunch"
        )
        note.beginLiveSession(at: date(1_700_014_100), presentTranscriptPanel: true)
        note.appendLiveTranscriptEntry(
            LiveTranscriptEntry(
                createdAt: date(1_700_014_300),
                speakerName: "Me",
                text: "Already merged chunk."
            ),
            updatedAt: date(1_700_014_300)
        )
        note.registerProcessedLiveChunkID("microphone-0000", updatedAt: date(1_700_014_300))
        note.completeLiveSession(at: date(1_700_014_900))

        let captureEngine = StubCaptureEngine(
            recordingURLs: [noteID: recordingURL],
            liveChunksByNoteID: [
                noteID: [
                    LiveTranscriptionChunk(
                        id: "microphone-0000",
                        noteID: noteID,
                        source: .microphone,
                        fileURL: firstChunkURL,
                        startedAt: date(1_700_014_200),
                        endedAt: date(1_700_014_350)
                    ),
                    LiveTranscriptionChunk(
                        id: "microphone-0001",
                        noteID: noteID,
                        source: .microphone,
                        fileURL: secondChunkURL,
                        startedAt: date(1_700_014_351),
                        endedAt: date(1_700_014_500)
                    )
                ]
            ]
        )
        let transcriptionService = StubTranscriptionService(
            result: TranscriptionJobResult(
                segments: [TranscriptSegment(text: "Recovered delayed chunk.")],
                backend: .mock,
                executionKind: .placeholder
            )
        )
        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let model = AppViewModel(
            store: InMemoryOatmealStore(notes: [note]),
            calendarService: StubCalendarService(),
            captureService: StubCaptureAccessService(),
            captureEngine: captureEngine,
            transcriptionService: transcriptionService,
            summaryService: StubSummaryService(),
            persistence: persistence,
            nowProvider: { Date(timeIntervalSince1970: 1_700_015_000) }
        )

        await model.loadSystemState()

        let completed = await waitUntil {
            model.selectedNote?.generationStatus == .succeeded
        }

        XCTAssertTrue(completed)
        XCTAssertEqual(
            model.selectedNote?.liveSessionState.processedChunkIDs.sorted(),
            ["microphone-0000", "microphone-0001"]
        )
        XCTAssertEqual(
            model.selectedNote?.liveSessionState.previewEntries.filter { $0.kind == .transcript }.map(\.text),
            ["Already merged chunk.", "Recovered delayed chunk."]
        )

        let metrics = try XCTUnwrap(reflectedSessionHealthMetrics(in: model.selectedNote))
        XCTAssertEqual(
            reflectedInt(in: metrics, labels: ["pendingLiveChunkCount", "pendingChunkCount", "backlogDepth", "backlogCount"]),
            0
        )
        XCTAssertNil(
            reflectedDate(
                in: metrics,
                labels: ["oldestPendingChunkStartedAt", "oldestPendingChunkAt", "oldestBacklogChunkAt"]
            )
        )
        XCTAssertEqual(
            reflectedDate(
                in: metrics,
                labels: ["lastMergedLiveChunkAt", "lastMergedChunkAt", "mergedChunkAt"]
            ),
            date(1_700_015_000)
        )
        XCTAssertEqual(
            try XCTUnwrap(
                reflectedDouble(in: metrics, labels: ["lastMergedChunkLatency", "chunkLatency", "lastChunkLatency"])
            ),
            500,
            accuracy: 0.001
        )

        let stats = await transcriptionService.stats()
        XCTAssertEqual(stats.executionPlanCalls, 1)
        XCTAssertEqual(stats.transcribeCalls, 2)
    }

    func testLoadSystemStateRefreshesSummaryModelCatalog() async throws {
        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let catalogEntry = SummaryModelCatalogEntry(
            id: "fixture-model",
            displayName: "Fixture Model",
            repositoryID: "mlx-community/fixture-model",
            suggestedDirectoryName: "FixtureModel",
            summary: "Fixture",
            footprintDescription: "Tiny"
        )
        let catalogState = SummaryModelCatalogState(
            modelsDirectoryURL: FileManager.default.temporaryDirectory,
            downloadAvailability: .available,
            downloadRuntimeDetail: "Ready",
            items: [
                SummaryModelCatalogItemState(
                    catalogEntry: catalogEntry,
                    installedModel: nil
                )
            ]
        )
        let model = AppViewModel(
            store: InMemoryOatmealStore.preview(),
            calendarService: StubCalendarService(),
            captureService: StubCaptureAccessService(),
            captureEngine: StubCaptureEngine(),
            transcriptionService: StubTranscriptionService(
                result: TranscriptionJobResult(
                    segments: [],
                    backend: .mock,
                    executionKind: .placeholder
                )
            ),
            summaryService: StubSummaryService(),
            summaryModelManager: StubSummaryModelManager(state: catalogState),
            persistence: persistence,
            nowProvider: Date.init
        )

        await model.loadSystemState()

        XCTAssertEqual(model.summaryModelCatalogState?.items.count, 1)
        XCTAssertEqual(model.summaryModelCatalogState?.items.first?.catalogEntry.displayName, "Fixture Model")
    }

    func testRemoveSummaryModelClearsPreferredSelection() async throws {
        let persistence = makePersistence()
        defer { removePersistenceArtifacts(persistence) }

        let installedModel = ManagedSummaryModel(
            displayName: "Fixture Model",
            directoryURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("FixtureModel", isDirectory: true)
        )
        let catalogEntry = SummaryModelCatalogEntry(
            id: "fixture-model",
            displayName: "Fixture Model",
            repositoryID: "mlx-community/fixture-model",
            suggestedDirectoryName: "FixtureModel",
            summary: "Fixture",
            footprintDescription: "Tiny"
        )
        let initialCatalogState = SummaryModelCatalogState(
            modelsDirectoryURL: FileManager.default.temporaryDirectory,
            downloadAvailability: .available,
            downloadRuntimeDetail: "Ready",
            items: [
                SummaryModelCatalogItemState(
                    catalogEntry: catalogEntry,
                    installedModel: installedModel
                )
            ]
        )
        let emptyCatalogState = SummaryModelCatalogState(
            modelsDirectoryURL: FileManager.default.temporaryDirectory,
            downloadAvailability: .available,
            downloadRuntimeDetail: "Ready",
            items: [
                SummaryModelCatalogItemState(
                    catalogEntry: catalogEntry,
                    installedModel: nil
                )
            ]
        )
        let summaryService = StubSummaryService(
            runtimeState: LocalSummaryRuntimeState(
                modelsDirectoryURL: FileManager.default.temporaryDirectory,
                discoveredModels: [installedModel],
                backends: [],
                activePlanSummary: "Stub summary runtime"
            )
        )
        let modelManager = StubSummaryModelManager(
            state: initialCatalogState,
            removedState: emptyCatalogState
        )

        let model = AppViewModel(
            store: InMemoryOatmealStore.preview(),
            calendarService: StubCalendarService(),
            captureService: StubCaptureAccessService(),
            captureEngine: StubCaptureEngine(),
            transcriptionService: StubTranscriptionService(
                result: TranscriptionJobResult(
                    segments: [],
                    backend: .mock,
                    executionKind: .placeholder
                )
            ),
            summaryService: summaryService,
            summaryModelManager: modelManager,
            persistence: persistence,
            nowProvider: Date.init
        )

        await model.refreshSummaryModelCatalogState()
        model.setSummaryPreferredModelName(installedModel.displayName)

        let selected = await waitUntil {
            model.summaryRuntimeState?.preferredModelName == installedModel.displayName
        }

        XCTAssertTrue(selected)

        model.removeSummaryModel(installedModel)

        let removed = await waitUntil {
            model.summaryConfiguration.preferredModelName == nil
                && model.summaryModelCatalogState?.items.first?.installedModel == nil
                && model.summaryRuntimeState?.preferredModelName == nil
        }

        XCTAssertTrue(removed)
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func emptySummaryModelCatalogState() -> SummaryModelCatalogState {
        SummaryModelCatalogState(
            modelsDirectoryURL: FileManager.default.temporaryDirectory,
            downloadAvailability: .available,
            downloadRuntimeDetail: "Ready",
            items: []
        )
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
    private let liveChunksByNoteID: [UUID: [LiveTranscriptionChunk]]
    private let runtimeHealthSnapshotsByNoteID: [UUID: CaptureRuntimeHealthSnapshot]
    private var runtimeEventBatchesByNoteID: [UUID: [[CaptureRuntimeEvent]]]
    private(set) var deletedNoteIDs: [UUID] = []

    init(
        artifact: CaptureArtifact? = nil,
        recordingURLs: [UUID: URL] = [:],
        liveChunksByNoteID: [UUID: [LiveTranscriptionChunk]] = [:],
        runtimeHealthSnapshotsByNoteID: [UUID: CaptureRuntimeHealthSnapshot] = [:],
        runtimeEventBatchesByNoteID: [UUID: [[CaptureRuntimeEvent]]] = [:]
    ) {
        self.artifact = artifact
        self.recordingURLs = recordingURLs
        self.liveChunksByNoteID = liveChunksByNoteID
        self.runtimeHealthSnapshotsByNoteID = runtimeHealthSnapshotsByNoteID
        self.runtimeEventBatchesByNoteID = runtimeEventBatchesByNoteID
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
        guard !deletedNoteIDs.contains(noteID) else {
            return nil
        }
        return recordingURLs[noteID] ?? (artifact?.noteID == noteID ? artifact?.fileURL : nil)
    }

    func liveTranscriptionChunks(for noteID: UUID) -> [LiveTranscriptionChunk] {
        liveChunksByNoteID[noteID] ?? []
    }

    func runtimeHealthSnapshot(for noteID: UUID) -> CaptureRuntimeHealthSnapshot? {
        runtimeHealthSnapshotsByNoteID[noteID]
    }

    func consumeRuntimeEvents(for noteID: UUID) -> [CaptureRuntimeEvent] {
        guard activeSession?.noteID == noteID else {
            return []
        }

        guard var batches = runtimeEventBatchesByNoteID[noteID], !batches.isEmpty else {
            return []
        }

        let events = batches.removeFirst()
        runtimeEventBatchesByNoteID[noteID] = batches.isEmpty ? nil : batches
        return events
    }

    func enqueueRuntimeEventBatch(_ events: [CaptureRuntimeEvent], for noteID: UUID) {
        runtimeEventBatchesByNoteID[noteID, default: []].append(events)
    }

    func deleteRecording(for noteID: UUID) throws {
        deletedNoteIDs.append(noteID)
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
    private let error: Error?

    init(result: TranscriptionJobResult, error: Error? = nil) {
        self.result = result
        self.error = error
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
        if let error {
            throw error
        }
        return result
    }

    func stats() -> (executionPlanCalls: Int, transcribeCalls: Int) {
        (executionPlanCalls, transcribeCalls)
    }
}

private actor PausingTranscriptionService: LocalTranscriptionServicing {
    private(set) var executionPlanCalls = 0
    private(set) var transcribeCalls = 0
    private var isFirstTranscribeCall = true
    private var firstCallContinuation: CheckedContinuation<TranscriptionJobResult, Error>?

    private let runtimeStateValue = LocalTranscriptionRuntimeState(
        modelsDirectoryURL: FileManager.default.temporaryDirectory,
        discoveredModels: [],
        backends: [],
        activePlanSummary: "Pausing stub runtime"
    )
    private let plan = TranscriptionExecutionPlan(
        backend: .mock,
        executionKind: .placeholder,
        summary: "Pausing stub plan"
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
        if isFirstTranscribeCall {
            isFirstTranscribeCall = false
            return try await withCheckedThrowingContinuation { continuation in
                firstCallContinuation = continuation
            }
        }

        return result
    }

    func resumeFirstTranscription() {
        firstCallContinuation?.resume(returning: result)
        firstCallContinuation = nil
    }
}

private extension OatmealUITests {
    func reflectedSessionHealthMetrics(in note: MeetingNote?) -> Any? {
        guard let note else {
            return nil
        }

        return reflectedValue(
            in: note.liveSessionState,
            labels: ["sessionHealthMetrics", "liveSessionMetrics", "healthMetrics", "metrics"]
        )
    }

    func reflectedValue(in value: Any, labels: [String]) -> Any? {
        let normalizedLabels = Set(labels.map(normalizedLabel(_:)))
        for child in Mirror(reflecting: value).children {
            guard let label = child.label, normalizedLabels.contains(normalizedLabel(label)) else {
                continue
            }
            return child.value
        }

        return nil
    }

    func reflectedInt(in value: Any, labels: [String]) -> Int? {
        reflectedValue(in: value, labels: labels) as? Int
    }

    func reflectedDate(in value: Any, labels: [String]) -> Date? {
        reflectedValue(in: value, labels: labels) as? Date
    }

    func reflectedDouble(in value: Any, labels: [String]) -> Double? {
        reflectedValue(in: value, labels: labels) as? Double
    }

    func normalizedLabel(_ label: String) -> String {
        label.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

private actor StubSummaryService: LocalSummaryServicing {
    private(set) var executionPlanCalls = 0
    private(set) var generateCalls = 0

    private let runtimeStateValue: LocalSummaryRuntimeState
    private let planValue: LocalSummaryExecutionPlan
    private let resultValue: SummaryJobResult

    init(
        runtimeState: LocalSummaryRuntimeState = LocalSummaryRuntimeState(
            modelsDirectoryURL: FileManager.default.temporaryDirectory,
            discoveredModels: [],
            backends: [],
            activePlanSummary: "Stub summary runtime"
        ),
        plan: LocalSummaryExecutionPlan = LocalSummaryExecutionPlan(
            backend: .extractiveLocal,
            executionKind: .local,
            summary: "Stub summary plan"
        ),
        result: SummaryJobResult = SummaryJobResult(
            enhancedNote: EnhancedNote(
                generatedAt: Date(),
                templateID: NoteTemplate.automatic.id,
                summary: "Generated summary",
                keyDiscussionPoints: ["Context"],
                decisions: ["Decision"],
                actionItems: [ActionItem(text: "Action")]
            ),
            backend: .extractiveLocal,
            executionKind: .local
        )
    ) {
        runtimeStateValue = runtimeState
        planValue = plan
        resultValue = result
    }

    func runtimeState(configuration: LocalSummaryConfiguration) async -> LocalSummaryRuntimeState {
        var runtimeState = runtimeStateValue
        runtimeState.preferredModelName = configuration.preferredModelName
        return runtimeState
    }

    func executionPlan(configuration: LocalSummaryConfiguration) async throws -> LocalSummaryExecutionPlan {
        executionPlanCalls += 1
        return planValue
    }

    func generate(
        request: NoteGenerationRequest,
        configuration: LocalSummaryConfiguration
    ) async throws -> SummaryJobResult {
        generateCalls += 1
        return SummaryJobResult(
            enhancedNote: EnhancedNote(
                generatedAt: resultValue.enhancedNote.generatedAt,
                templateID: request.template.id,
                summary: resultValue.enhancedNote.summary,
                keyDiscussionPoints: resultValue.enhancedNote.keyDiscussionPoints.isEmpty
                    ? request.rawNotes
                        .split(separator: "\n")
                        .map(String.init)
                        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    : resultValue.enhancedNote.keyDiscussionPoints,
                decisions: resultValue.enhancedNote.decisions.isEmpty
                    ? request.transcriptSegments.map(\.text)
                    : resultValue.enhancedNote.decisions,
                risksOrOpenQuestions: resultValue.enhancedNote.risksOrOpenQuestions,
                actionItems: resultValue.enhancedNote.actionItems.isEmpty
                    ? request.transcriptSegments.map { ActionItem(text: $0.text) }
                    : resultValue.enhancedNote.actionItems,
                citations: resultValue.enhancedNote.citations
            ),
            backend: resultValue.backend,
            executionKind: resultValue.executionKind,
            warningMessages: resultValue.warningMessages
        )
    }

    func stats() -> (executionPlanCalls: Int, generateCalls: Int) {
        (executionPlanCalls, generateCalls)
    }
}

private actor StubSummaryModelManager: LocalSummaryModelManaging {
    private var stateValue: SummaryModelCatalogState
    private let removedState: SummaryModelCatalogState?

    init(
        state: SummaryModelCatalogState,
        removedState: SummaryModelCatalogState? = nil
    ) {
        stateValue = state
        self.removedState = removedState
    }

    func catalogState() async -> SummaryModelCatalogState {
        stateValue
    }

    func install(modelID _: String, forceRedownload _: Bool) async throws -> SummaryModelCatalogState {
        stateValue
    }

    func remove(modelDirectoryURL _: URL) async throws -> SummaryModelCatalogState {
        if let removedState {
            stateValue = removedState
        }
        return stateValue
    }
}
