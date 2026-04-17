import Foundation

public enum OatmealSeedData {
    public static func preview(referenceDate: Date = Date()) -> InMemoryOatmealStore {
        let start = referenceDate.addingTimeInterval(30 * 60)
        let end = start.addingTimeInterval(45 * 60)

        let folderResearch = NoteFolder(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222221")!,
            name: "Customer research",
            isPinned: true,
            createdAt: referenceDate.addingTimeInterval(-86_400)
        )

        let folderInternal = NoteFolder(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "Internal meetings",
            isPinned: false,
            createdAt: referenceDate.addingTimeInterval(-43_200)
        )

        let event = CalendarEvent(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333331")!,
            title: "Product sync",
            startDate: start,
            endDate: end,
            attendees: [
                MeetingParticipant(name: "Avery Chen", email: "avery@example.com", isOrganizer: true),
                MeetingParticipant(name: "Morgan Lee", email: "morgan@example.com")
            ],
            conferencingURL: URL(string: "https://meet.example.com/product-sync"),
            source: .googleCalendar,
            kind: .meeting,
            attendanceStatus: .accepted,
            notes: "Discuss onboarding timeline and launch scope."
        )

        let transcriptSegment = TranscriptSegment(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444441")!,
            startTime: start.addingTimeInterval(5 * 60),
            endTime: start.addingTimeInterval(6 * 60),
            speakerName: "Avery",
            text: "We decided to ship the onboarding changes first and follow up on the template polish next.",
            confidence: 0.97
        )

        var note = MeetingNote(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555551")!,
            title: "Product sync",
            origin: .calendarEvent(event.id, createdAt: referenceDate.addingTimeInterval(-3_600)),
            calendarEvent: event,
            folderID: folderInternal.id,
            templateID: NoteTemplate.automatic.id,
            shareSettings: ShareSettings(privacyLevel: .anyoneWithLink, includeTranscript: false, allowViewersToChat: false),
            captureState: CaptureSessionState(
                phase: .complete,
                startedAt: referenceDate.addingTimeInterval(-3_000),
                endedAt: referenceDate.addingTimeInterval(-2_400),
                isRecoverableAfterCrash: false,
                permissions: CapturePermissions(microphone: .granted, systemAudio: .granted, notifications: .granted, calendar: .granted)
            ),
            generationStatus: .succeeded,
            rawNotes: "Agenda:\n- onboarding timing\n- template polish",
            transcriptSegments: [transcriptSegment],
            enhancedNote: EnhancedNote(
                generatedAt: referenceDate.addingTimeInterval(-2_350),
                templateID: NoteTemplate.automatic.id,
                summary: "Ship onboarding first, then revisit template polish.",
                keyDiscussionPoints: ["Onboarding changes are the current priority.", "Template polish follows next."],
                decisions: ["Ship onboarding before template polish."],
                risksOrOpenQuestions: ["Need to verify the launch timeline."],
                actionItems: [ActionItem(text: "Draft onboarding plan", assignee: "Avery", dueDate: nil, status: .open)],
                citations: [SourceCitation(transcriptSegmentIDs: [transcriptSegment.id], excerpt: transcriptSegment.text)]
            ),
            generationHistory: [
                NoteGenerationAttempt(templateID: NoteTemplate.automatic.id, requestedAt: referenceDate.addingTimeInterval(-2_360), completedAt: referenceDate.addingTimeInterval(-2_350), status: .succeeded)
            ],
            createdAt: referenceDate.addingTimeInterval(-3_600),
            updatedAt: referenceDate.addingTimeInterval(-2_350)
        )

        note.replaceRawNotes(
            "Agenda:\n- onboarding timing\n- template polish\n- follow-up on link sharing",
            updatedAt: referenceDate.addingTimeInterval(-2_300)
        )

        let quickNote = MeetingNote(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555552")!,
            title: "Quick Note",
            origin: .quickNote(createdAt: referenceDate.addingTimeInterval(-1_800)),
            folderID: folderResearch.id,
            templateID: NoteTemplate.oneOnOne.id,
            shareSettings: .default,
            captureState: .ready,
            rawNotes: "Ideas for the research dashboard",
            transcriptSegments: [],
            enhancedNote: nil,
            generationHistory: [],
            createdAt: referenceDate.addingTimeInterval(-1_800),
            updatedAt: referenceDate.addingTimeInterval(-1_800)
        )

        return InMemoryOatmealStore(
            events: [event],
            notes: [note, quickNote],
            folders: [folderResearch, folderInternal],
            templates: NoteTemplate.builtInTemplates,
            defaultTemplateID: NoteTemplate.automatic.id
        )
    }
}
