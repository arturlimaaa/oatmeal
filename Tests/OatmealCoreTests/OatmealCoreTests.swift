import XCTest
@testable import OatmealCore

final class OatmealCoreTests: XCTestCase {
    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    func testUpcomingMeetingsFilterIrrelevantAndDeclinedEvents() {
        let now = date(1_700_000_000)
        let relevant = CalendarEvent(
            title: "Design review",
            startDate: now.addingTimeInterval(600),
            endDate: now.addingTimeInterval(3_600),
            source: .googleCalendar,
            kind: .meeting,
            attendanceStatus: .accepted
        )
        let declined = CalendarEvent(
            title: "Skipped meeting",
            startDate: now.addingTimeInterval(600),
            endDate: now.addingTimeInterval(3_600),
            source: .googleCalendar,
            kind: .meeting,
            attendanceStatus: .declined
        )
        let focusBlock = CalendarEvent(
            title: "Focus time",
            startDate: now.addingTimeInterval(600),
            endDate: now.addingTimeInterval(3_600),
            source: .googleCalendar,
            kind: .focusBlock,
            attendanceStatus: .accepted
        )
        let allDay = CalendarEvent(
            title: "OOO",
            startDate: now.addingTimeInterval(600),
            endDate: now.addingTimeInterval(3_600),
            source: .googleCalendar,
            kind: .allDayPlaceholder,
            attendanceStatus: .accepted
        )

        let store = InMemoryOatmealStore(events: [declined, focusBlock, allDay, relevant])
        let meetings = store.upcomingMeetings(referenceDate: now, horizon: 7_200)

        XCTAssertEqual(meetings, [relevant])
    }

    func testNoteCanBelongToOnlyOneFolderAtATime() {
        let folderA = NoteFolder(id: UUID(uuidString: "AAAA1111-1111-1111-1111-111111111111")!, name: "A")
        let folderB = NoteFolder(id: UUID(uuidString: "BBBB2222-2222-2222-2222-222222222222")!, name: "B")
        var note = MeetingNote(
            title: "Quick note",
            origin: .quickNote(createdAt: date(1_700_000_000)),
            folderID: folderA.id,
            rawNotes: "hello"
        )

        note.assignFolder(folderB.id, updatedAt: date(1_700_000_100))

        let store = InMemoryOatmealStore(notes: [note], folders: [folderA, folderB])
        XCTAssertEqual(store.noteCount(in: folderA.id), 0)
        XCTAssertEqual(store.noteCount(in: folderB.id), 1)
        XCTAssertEqual(store.note(id: note.id)?.folderID, folderB.id)
    }

    func testShareSettingsDefaultHidesTranscriptAndStartsPrivate() {
        let settings = ShareSettings.default

        XCTAssertEqual(settings.privacyLevel, .private)
        XCTAssertFalse(settings.includeTranscript)
        XCTAssertFalse(settings.allowViewersToChat)
    }

    func testShareLinksRespectPrivacySettings() throws {
        let note = MeetingNote(
            title: "Private note",
            origin: .quickNote(createdAt: date(1_700_000_000)),
            shareSettings: .default
        )
        let store = InMemoryOatmealStore(notes: [note])

        XCTAssertThrowsError(try store.createShareLink(for: note, baseURL: URL(string: "https://share.example.com")!))

        let shareable = MeetingNote(
            title: "Shareable note",
            origin: .quickNote(createdAt: date(1_700_000_000)),
            shareSettings: ShareSettings(privacyLevel: .anyoneWithLink, includeTranscript: false)
        )
        let shareLink = try store.createShareLink(for: shareable, baseURL: URL(string: "https://share.example.com")!)

        XCTAssertEqual(shareLink.noteID, shareable.id)
        XCTAssertEqual(shareLink.settings.privacyLevel, .anyoneWithLink)
        XCTAssertFalse(shareLink.settings.includeTranscript)
        XCTAssertFalse(shareLink.isRevoked)
    }

    func testTemplateValidationRejectsEmptyFields() {
        let invalidByName = NoteTemplate(name: " ", instructions: "Keep it concise", sections: ["Summary"])
        XCTAssertThrowsError(try invalidByName.validate())

        let invalidByInstructions = NoteTemplate(name: "Custom", instructions: " ", sections: ["Summary"])
        XCTAssertThrowsError(try invalidByInstructions.validate())

        let invalidBySections = NoteTemplate(name: "Custom", instructions: "Keep it concise", sections: [])
        XCTAssertThrowsError(try invalidBySections.validate())
    }

    func testBuiltInTemplatesIncludeAutomaticDefault() {
        XCTAssertTrue(NoteTemplate.builtInTemplates.contains(where: { $0.kind == .automatic && $0.isDefault }))
        XCTAssertTrue(NoteTemplate.builtInTemplates.contains(where: { $0.kind == .oneOnOne }))
        XCTAssertTrue(NoteTemplate.builtInTemplates.contains(where: { $0.kind == .standUp }))
        XCTAssertTrue(NoteTemplate.builtInTemplates.contains(where: { $0.kind == .interview }))
        XCTAssertTrue(NoteTemplate.builtInTemplates.contains(where: { $0.kind == .customerCall }))
        XCTAssertTrue(NoteTemplate.builtInTemplates.contains(where: { $0.kind == .projectReview }))
    }

    func testGenerationFailurePreservesRawNotesAndTranscript() {
        let noteID = UUID()
        var note = MeetingNote(
            id: noteID,
            title: "Product sync",
            origin: .quickNote(createdAt: date(1_700_000_000)),
            rawNotes: "Need to follow up",
            transcriptSegments: [
                TranscriptSegment(text: "We decided to ship this week.")
            ]
        )

        note.beginGeneration(templateID: NoteTemplate.automatic.id, at: date(1_700_000_100))
        note.recordGenerationFailure("provider timeout", at: date(1_700_000_120))

        XCTAssertEqual(note.generationStatus, .failed)
        XCTAssertEqual(note.rawNotes, "Need to follow up")
        XCTAssertEqual(note.transcriptSegments.count, 1)
        XCTAssertEqual(note.generationHistory.last?.errorMessage, "provider timeout")
        XCTAssertNil(note.enhancedNote)
        XCTAssertEqual(note.processingState.stage, .generation)
        XCTAssertEqual(note.processingState.status, .failed)
    }

    func testQueuedAndRecoveredPostCaptureProcessingState() {
        var note = MeetingNote(
            title: "Customer sync",
            origin: .quickNote(createdAt: date(1_700_000_000))
        )

        note.queueTranscription(at: date(1_700_000_010))

        XCTAssertEqual(note.processingState.stage, .transcription)
        XCTAssertEqual(note.processingState.status, .queued)
        XCTAssertTrue(note.needsPostCaptureRecovery)

        XCTAssertTrue(note.preparePostCaptureRecovery(at: date(1_700_000_020)))
        XCTAssertEqual(note.processingState.status, .queued)
        XCTAssertEqual(note.processingState.queuedAt, date(1_700_000_010))
        XCTAssertNil(note.processingState.startedAt)
    }

    func testLegacyPendingTranscriptionDecodesRecoverableProcessingState() throws {
        let noteID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let originCreatedAt = date(1_700_000_000)
        let requestedAt = date(1_700_000_100)
        let updatedAt = date(1_700_000_120)
        let json = """
        {
          "id": "\(noteID.uuidString)",
          "title": "Legacy note",
          "origin": {
            "kind": "quickNote",
            "createdAt": \(originCreatedAt.timeIntervalSinceReferenceDate)
          },
          "shareSettings": {
            "privacyLevel": "private",
            "includeTranscript": false,
            "allowViewersToChat": false
          },
          "captureState": {
            "phase": "complete",
            "startedAt": \(originCreatedAt.timeIntervalSinceReferenceDate),
            "endedAt": \(updatedAt.timeIntervalSinceReferenceDate),
            "isRecoverableAfterCrash": false,
            "permissions": {
              "microphone": "granted",
              "systemAudio": "granted",
              "notifications": "granted",
              "calendar": "granted"
            }
          },
          "generationStatus": "idle",
          "transcriptionStatus": "pending",
          "rawNotes": "",
          "transcriptSegments": [],
          "transcriptionHistory": [
            {
              "id": "\(UUID().uuidString)",
              "backend": "mock",
              "executionKind": "placeholder",
              "requestedAt": \(requestedAt.timeIntervalSinceReferenceDate),
              "status": "pending",
              "segmentCount": 0,
              "warningMessages": []
            }
          ],
          "generationHistory": [],
          "createdAt": \(originCreatedAt.timeIntervalSinceReferenceDate),
          "updatedAt": \(updatedAt.timeIntervalSinceReferenceDate)
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        let note = try decoder.decode(MeetingNote.self, from: Data(json.utf8))

        XCTAssertEqual(note.processingState.stage, .transcription)
        XCTAssertEqual(note.processingState.status, .running)
        XCTAssertEqual(note.processingState.queuedAt, requestedAt)
        XCTAssertTrue(note.needsPostCaptureRecovery)
    }

    func testTemplateShapingPreservesTranscriptAndMetadata() {
        let event = CalendarEvent(
            title: "Roadmap review",
            startDate: date(1_700_000_000),
            endDate: date(1_700_003_600),
            attendees: [MeetingParticipant(name: "Avery")],
            source: .microsoftCalendar,
            kind: .meeting,
            attendanceStatus: .accepted
        )
        let note = MeetingNote(
            title: "Roadmap review",
            origin: .calendarEvent(event.id, createdAt: date(1_700_000_000)),
            calendarEvent: event,
            folderID: UUID(),
            templateID: NoteTemplate.projectReview.id,
            shareSettings: ShareSettings(privacyLevel: .anyoneWithLink, includeTranscript: false),
            rawNotes: "Launch scope\nRisks",
            transcriptSegments: [TranscriptSegment(text: "Decided to cut scope.")]
        )

        let request = NoteTemplate.projectReview.makeGenerationRequest(for: note)

        XCTAssertEqual(request.noteID, note.id)
        XCTAssertEqual(request.meetingEvent, event)
        XCTAssertEqual(request.rawNotes, note.rawNotes)
        XCTAssertEqual(request.transcriptSegments, note.transcriptSegments)
        XCTAssertEqual(request.template.id, NoteTemplate.projectReview.id)
    }

    func testSearchMatchesTranscriptAndReturnsSnippetContext() {
        let folder = NoteFolder(name: "Customer research")
        let note = MeetingNote(
            title: "Customer interview",
            origin: .quickNote(createdAt: date(1_700_000_000)),
            folderID: folder.id,
            rawNotes: "Talked about onboarding",
            transcriptSegments: [
                TranscriptSegment(text: "We need a faster onboarding flow for new users.")
            ],
            enhancedNote: EnhancedNote(
                summary: "Onboarding is the top issue.",
                decisions: ["Ship onboarding changes first."],
                actionItems: [ActionItem(text: "Follow up on onboarding")]
            )
        )

        let store = InMemoryOatmealStore(notes: [note], folders: [folder])
        let results = store.search(query: "onboarding")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.noteID, note.id)
        XCTAssertTrue(results.first?.matchedFields.contains(.transcript) == true)
        XCTAssertTrue(results.first?.matchedFields.contains(.rawNotes) == true || results.first?.matchedFields.contains(.summary) == true)
        XCTAssertTrue(results.first?.snippet.lowercased().contains("onboarding") == true)
        XCTAssertEqual(results.first?.folderName, "Customer research")
    }

    func testCaptureStateTransitionsAndCrashRecoveryEligibility() {
        var state = CaptureSessionState.ready
        XCTAssertEqual(state.phase, .ready)
        XCTAssertFalse(state.isActive)

        state.beginCapture(at: date(1_700_000_000))
        XCTAssertEqual(state.phase, .capturing)
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.startedAt, date(1_700_000_000))

        state.pause(at: date(1_700_000_100))
        XCTAssertEqual(state.phase, .paused)
        XCTAssertEqual(state.pausedAt, date(1_700_000_100))

        state.resume(at: date(1_700_000_200))
        XCTAssertEqual(state.phase, .capturing)

        state.fail(reason: "system audio permission denied", at: date(1_700_000_300), recoverable: true)
        XCTAssertEqual(state.phase, .failed)
        XCTAssertTrue(state.canResumeAfterCrash)

        state.resume(at: date(1_700_000_400))
        XCTAssertEqual(state.phase, .capturing)
    }

    func testPreviewSeedProvidesNotesFoldersTemplatesAndUpcomingMeeting() {
        let now = date(1_700_000_000)
        let store = OatmealSeedData.preview(referenceDate: now)

        XCTAssertFalse(store.folders.isEmpty)
        XCTAssertFalse(store.allTemplates().isEmpty)
        XCTAssertFalse(store.allNotes().isEmpty)
        XCTAssertEqual(store.upcomingMeetings(referenceDate: now, horizon: 3_600).count, 1)
    }
}
