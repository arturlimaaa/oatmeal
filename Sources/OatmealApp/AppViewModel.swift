import Foundation
import Observation
import OatmealCore
import OatmealEdge

@MainActor
@Observable
final class AppViewModel {
    private let store: InMemoryOatmealStore
    private let generator: NoteGenerationService
    private let calendarService: CalendarAccessServing
    private let captureService: CaptureAccessServing
    private let captureEngine: MeetingCaptureEngineServing
    private let transcriptionService: any LocalTranscriptionServicing
    private let persistence: AppPersistence
    private let nowProvider: () -> Date
    @ObservationIgnored private var processingTasks: [MeetingNote.ID: Task<Void, Never>] = [:]

    var folders: [NoteFolder] = []
    var notes: [MeetingNote] = []
    var templates: [NoteTemplate] = []
    var upcomingMeetings: [CalendarEvent] = []
    var calendarAccessStatus: PermissionStatus = .notDetermined
    var capturePermissions = CapturePermissions()
    var isLoadingUpcomingMeetings = false
    var isPreparingCapture = false
    var upcomingMeetingsError: String?
    var capturePermissionMessage: String?
    var transcriptionConfiguration = LocalTranscriptionConfiguration.default
    var transcriptionRuntimeState: LocalTranscriptionRuntimeState?
    var selectedSidebarItem: SidebarItem = .upcoming
    var selectedUpcomingEventID: CalendarEvent.ID?
    var selectedNoteID: MeetingNote.ID?
    var selectedTemplateID: NoteTemplate.ID?
    var searchText = ""

    init(
        store: InMemoryOatmealStore = .preview(),
        generator: NoteGenerationService = DeterministicNoteGenerationService(),
        calendarService: CalendarAccessServing = LiveCalendarAccessService(),
        captureService: CaptureAccessServing = LiveCaptureAccessService(),
        captureEngine: MeetingCaptureEngineServing = LiveMeetingCaptureEngine(),
        transcriptionService: (any LocalTranscriptionServicing)? = nil,
        persistence: AppPersistence = .shared,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.generator = generator
        self.calendarService = calendarService
        self.captureService = captureService
        self.captureEngine = captureEngine
        self.persistence = persistence
        self.nowProvider = nowProvider
        self.transcriptionService = transcriptionService ?? LocalTranscriptionPipeline(
            applicationSupportDirectoryURL: persistence.applicationSupportDirectoryURL
        )

        restorePersistedState()
        refresh()
        selectedNoteID = notes.first?.id
    }

    var filteredNotes: [MeetingNote] {
        let source: [MeetingNote]
        switch selectedSidebarItem {
        case .upcoming:
            source = []
        case .allNotes:
            source = notes
        case let .folder(folderID):
            source = notes.filter { $0.folderID == folderID }
        case .templates:
            source = notes
        }

        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return source
        }

        let results = store.search(query: trimmedQuery)
        let notesByID = Dictionary(uniqueKeysWithValues: source.map { ($0.id, $0) })
        return results.compactMap { notesByID[$0.noteID] }
    }

    var filteredUpcomingMeetings: [CalendarEvent] {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return upcomingMeetings
        }

        return upcomingMeetings.filter { event in
            event.title.localizedCaseInsensitiveContains(trimmedQuery)
                || event.attendees.contains { $0.name.localizedCaseInsensitiveContains(trimmedQuery) }
                || (event.location?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
        }
    }

    var selectedNote: MeetingNote? {
        get { notes.first(where: { $0.id == selectedNoteID }) ?? filteredNotes.first }
        set { selectedNoteID = newValue?.id }
    }

    var selectedUpcomingEvent: CalendarEvent? {
        upcomingMeetings.first(where: { $0.id == selectedUpcomingEventID })
            ?? filteredUpcomingMeetings.first
    }

    var selectedTemplate: NoteTemplate? {
        get { templates.first(where: { $0.id == selectedTemplateID }) ?? templates.first }
        set { selectedTemplateID = newValue?.id }
    }

    func folder(for note: MeetingNote) -> NoteFolder? {
        guard let folderID = note.folderID else {
            return nil
        }
        return folders.first(where: { $0.id == folderID })
    }

    func note(for event: CalendarEvent) -> MeetingNote? {
        notes.first(where: { $0.calendarEvent?.id == event.id })
    }

    func recordingURL(for note: MeetingNote) -> URL? {
        captureEngine.recordingURL(for: note.id)
    }

    func selectFirstAvailableNote() {
        selectedNoteID = filteredNotes.first?.id
    }

    func selectFirstUpcomingMeetingIfNeeded() {
        if selectedUpcomingEventID == nil {
            selectedUpcomingEventID = filteredUpcomingMeetings.first?.id
        }
    }

    func refresh() {
        folders = store.folders
        notes = store.allNotes()
        templates = store.allTemplates()

        if selectedTemplateID == nil {
            selectedTemplateID = templates.first?.id
        }
    }

    func loadSystemState() async {
        await loadCalendarState()
        await refreshCapturePermissions()
        await refreshTranscriptionRuntimeState()
        resumePostCaptureProcessingIfNeeded()
    }

    func loadCalendarState() async {
        calendarAccessStatus = calendarService.authorizationStatus()
        if calendarAccessStatus == .granted {
            await refreshUpcomingMeetings()
        } else {
            upcomingMeetings = []
            upcomingMeetingsError = nil
        }
    }

    func requestCalendarAccess() async {
        isLoadingUpcomingMeetings = true
        calendarAccessStatus = await calendarService.requestAccess()
        isLoadingUpcomingMeetings = false

        if calendarAccessStatus == .granted {
            await refreshUpcomingMeetings()
        }

        await refreshCapturePermissions()
    }

    func refreshUpcomingMeetings() async {
        guard calendarAccessStatus == .granted else {
            upcomingMeetings = []
            upcomingMeetingsError = nil
            return
        }

        isLoadingUpcomingMeetings = true
        defer { isLoadingUpcomingMeetings = false }

        do {
            upcomingMeetings = try await calendarService.upcomingEvents(
                referenceDate: nowProvider(),
                horizon: 7 * 24 * 60 * 60
            )
            upcomingMeetingsError = nil
            selectFirstUpcomingMeetingIfNeeded()
        } catch {
            upcomingMeetings = []
            upcomingMeetingsError = error.localizedDescription
        }
    }

    func refreshCapturePermissions() async {
        capturePermissions = await captureService.currentPermissions(calendarStatus: calendarAccessStatus)
    }

    func refreshTranscriptionRuntimeState() async {
        transcriptionRuntimeState = await transcriptionService.runtimeState(configuration: transcriptionConfiguration)
    }

    func startQuickNote() {
        let now = nowProvider()
        let note = MeetingNote(
            title: "Quick Note",
            origin: .quickNote(createdAt: now),
            templateID: selectedTemplate?.id ?? store.defaultTemplate.id,
            captureState: .ready,
            rawNotes: "### Context\n- ",
            createdAt: now,
            updatedAt: now
        )

        store.save(note)
        refresh()
        selectedSidebarItem = .allNotes
        selectedNoteID = note.id
        persistState()
    }

    func startNote(for event: CalendarEvent) {
        if let existingNote = note(for: event) {
            selectedSidebarItem = .allNotes
            selectedNoteID = existingNote.id
            return
        }

        let now = nowProvider()
        let note = MeetingNote(
            title: event.title,
            origin: .calendarEvent(event.id, createdAt: now),
            calendarEvent: event,
            templateID: selectedTemplate?.id ?? store.defaultTemplate.id,
            captureState: .ready,
            rawNotes: "### Agenda\n- ",
            createdAt: now,
            updatedAt: now
        )

        store.save(note)
        refresh()
        selectedSidebarItem = .allNotes
        selectedNoteID = note.id
        persistState()
    }

    func toggleCapture() async {
        guard var note = selectedNote else {
            return
        }

        let now = nowProvider()
        switch note.captureState.phase {
        case .ready, .complete, .failed:
            guard !hasPendingPostCaptureWork(note) else {
                capturePermissionMessage = "Oatmeal is still processing the last recording for this note. Wait for it to finish before starting a new capture."
                return
            }

            capturePermissionMessage = nil
            isPreparingCapture = true
            let permissions = await captureService.requestPermissions(
                requiresSystemAudio: requiresSystemAudio(for: note),
                calendarStatus: calendarAccessStatus
            )
            isPreparingCapture = false
            capturePermissions = permissions
            note.captureState.permissions = permissions

            guard captureRequirementsSatisfied(for: note, permissions: permissions) else {
                let message = captureFailureMessage(for: note, permissions: permissions)
                capturePermissionMessage = message
                note.captureState.fail(reason: message, at: now, recoverable: true)
                store.save(note)
                refresh()
                selectedNoteID = note.id
                persistState()
                return
            }

            do {
                let mode: CaptureMode = requiresSystemAudio(for: note) ? .systemAudioAndMicrophone : .microphoneOnly
                let session = try await captureEngine.startCapture(for: note.id, mode: mode)
                note.captureState.beginCapture(at: session.startedAt)
            } catch {
                let message = error.localizedDescription
                capturePermissionMessage = message
                note.captureState.fail(reason: message, at: now, recoverable: true)
                store.save(note)
                refresh()
                selectedNoteID = note.id
                persistState()
                return
            }

            if note.rawNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                note.replaceRawNotes("### Context\n- ", updatedAt: now)
            }

        case .capturing, .paused:
            capturePermissionMessage = nil
            note.captureState.permissions = capturePermissions
            let artifact: CaptureArtifact
            do {
                artifact = try await captureEngine.stopCapture()
            } catch {
                let message = error.localizedDescription
                capturePermissionMessage = message
                note.captureState.fail(reason: message, at: now, recoverable: true)
                store.save(note)
                refresh()
                selectedNoteID = note.id
                persistState()
                return
            }

            note.captureState.complete(at: artifact.endedAt)
            var statusMessages: [String] = []
            if artifact.duration < 300 {
                statusMessages.append("Short recording saved locally. Summaries are usually more useful once a meeting runs longer than five minutes.")
            }

            note.queueTranscription(at: artifact.endedAt)
            store.save(note)
            refresh()
            selectedNoteID = note.id
            persistState()

            enqueuePostCaptureProcessing(
                PostCaptureProcessingRequest(
                    noteID: note.id,
                    recordingURL: artifact.fileURL,
                    captureStartedAt: artifact.startedAt,
                    processingAnchorDate: artifact.endedAt,
                    trigger: .immediateAfterCapture
                )
            )

            statusMessages.append("Recording saved locally. Oatmeal is transcribing and generating notes in the background.")
            capturePermissionMessage = buildStatusMessage(from: statusMessages)
        }

        store.save(note)
        refresh()
        selectedNoteID = note.id
        persistState()
    }

    func setTranscriptionBackendPreference(_ preference: TranscriptionBackendPreference) {
        transcriptionConfiguration.preferredBackend = preference
        persistState()
        Task {
            await refreshTranscriptionRuntimeState()
        }
    }

    func setTranscriptionExecutionPolicy(_ policy: TranscriptionExecutionPolicy) {
        transcriptionConfiguration.executionPolicy = policy
        persistState()
        Task {
            await refreshTranscriptionRuntimeState()
        }
    }

    func setSelectedTemplate(_ template: NoteTemplate) {
        selectedTemplateID = template.id
        guard var note = selectedNote else {
            persistState()
            return
        }
        note.templateID = template.id
        note.updatedAt = nowProvider()
        store.save(note)
        refresh()
        persistState()
    }

    func canRetryTranscription(for note: MeetingNote) -> Bool {
        guard note.captureState.phase == .complete else {
            return false
        }

        guard note.transcriptionStatus == .failed else {
            return false
        }

        guard !hasPendingPostCaptureWork(note) else {
            return false
        }

        return recordingURL(for: note) != nil
    }

    func canRetryGeneration(for note: MeetingNote) -> Bool {
        guard note.captureState.phase == .complete else {
            return false
        }

        guard note.generationStatus == .failed else {
            return false
        }

        guard !hasPendingPostCaptureWork(note) else {
            return false
        }

        return note.transcriptionStatus == .succeeded
            || !note.transcriptSegments.isEmpty
            || !note.rawNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func retryTranscription() {
        guard var note = selectedNote, canRetryTranscription(for: note) else {
            return
        }

        let now = nowProvider()
        note.transcriptionStatus = .idle
        note.generationStatus = .idle
        note.queueTranscription(at: now)
        persist(note)

        enqueuePostCaptureProcessing(
            PostCaptureProcessingRequest(
                noteID: note.id,
                recordingURL: recordingURL(for: note),
                captureStartedAt: note.captureState.startedAt,
                processingAnchorDate: now,
                trigger: .manualRetry
            )
        )

        capturePermissionMessage = "Retrying transcription for the saved recording."
    }

    func retryGeneration() {
        guard var note = selectedNote, canRetryGeneration(for: note) else {
            return
        }

        let now = nowProvider()
        let template = store.template(id: note.templateID ?? selectedTemplate?.id ?? store.defaultTemplate.id)
            ?? selectedTemplate
            ?? store.defaultTemplate

        note.generationStatus = .idle
        note.queueGeneration(templateID: template.id, at: now)
        persist(note)

        enqueuePostCaptureProcessing(
            PostCaptureProcessingRequest(
                noteID: note.id,
                recordingURL: recordingURL(for: note),
                captureStartedAt: note.captureState.startedAt,
                processingAnchorDate: now,
                trigger: .manualRetry
            )
        )

        capturePermissionMessage = "Retrying enhanced note generation."
    }

    private func restorePersistedState() {
        let snapshot = persistence.loadOrEmpty()
        guard !snapshot.notes.isEmpty
            || snapshot.selectedTemplateID != nil
            || snapshot.transcriptionConfiguration != .default else {
            return
        }

        for existing in store.allNotes() {
            store.delete(noteID: existing.id)
        }

        for note in snapshot.notes {
            store.save(note)
        }

        selectedTemplateID = snapshot.selectedTemplateID
        transcriptionConfiguration = snapshot.transcriptionConfiguration
    }

    private func persistState() {
        do {
            try persistence.save(
                notes: store.allNotes(),
                selectedTemplateID: selectedTemplateID,
                transcriptionConfiguration: transcriptionConfiguration
            )
        } catch {
            capturePermissionMessage = "Unable to save local state: \(error.localizedDescription)"
        }
    }

    private func enqueuePostCaptureProcessing(_ request: PostCaptureProcessingRequest) {
        guard processingTasks[request.noteID] == nil else {
            return
        }

        processingTasks[request.noteID] = Task { [weak self] in
            guard let self else { return }
            await self.runPostCaptureProcessing(request)
            self.processingTasks[request.noteID] = nil
        }
    }

    private func resumePostCaptureProcessingIfNeeded() {
        for var note in notes where noteNeedsPostCaptureRecovery(note) {
            if note.preparePostCaptureRecovery(at: nowProvider()) {
                persist(note)
            }

            enqueuePostCaptureProcessing(
                PostCaptureProcessingRequest(
                    noteID: note.id,
                    recordingURL: captureEngine.recordingURL(for: note.id),
                    captureStartedAt: note.captureState.startedAt,
                    processingAnchorDate: note.captureState.endedAt ?? note.updatedAt,
                    trigger: .relaunchRecovery
                )
            )
        }
    }

    private func noteNeedsPostCaptureRecovery(_ note: MeetingNote) -> Bool {
        guard note.captureState.phase == .complete else {
            return false
        }

        if note.needsPostCaptureRecovery {
            return true
        }

        let recordingURL = captureEngine.recordingURL(for: note.id)
        let hasRawNotes = !note.rawNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasTranscript = note.transcriptionStatus == .succeeded || !note.transcriptSegments.isEmpty
        let hasEnhancedNote = note.generationStatus == .succeeded || note.enhancedNote != nil

        if note.transcriptionStatus == .idle, recordingURL != nil {
            return true
        }

        if !hasEnhancedNote, hasTranscript || hasRawNotes {
            return true
        }

        return false
    }

    private func hasPendingPostCaptureWork(_ note: MeetingNote) -> Bool {
        note.processingState.isActive
            || note.transcriptionStatus == .pending
            || note.generationStatus == .pending
            || processingTasks[note.id] != nil
    }

    private func runPostCaptureProcessing(_ request: PostCaptureProcessingRequest) async {
        guard var note = store.note(id: request.noteID) else {
            return
        }

        let processingDate = max(request.processingAnchorDate, nowProvider())
        var statusMessages: [String] = []

        if note.transcriptionStatus != .succeeded {
            let transcriptionPlan: TranscriptionExecutionPlan?
            do {
                transcriptionPlan = try await transcriptionService.executionPlan(configuration: transcriptionConfiguration)
                if note.transcriptionStatus != .pending, let transcriptionPlan {
                    note.beginTranscription(
                        backend: transcriptionPlan.backend,
                        executionKind: transcriptionPlan.executionKind,
                        at: processingDate
                    )
                    persist(note)
                }
            } catch {
                transcriptionPlan = nil
                note.recordTranscriptionFailure(
                    backend: fallbackTranscriptionBackend(),
                    executionKind: fallbackTranscriptionExecutionKind(),
                    message: error.localizedDescription,
                    at: processingDate
                )
                statusMessages.append("Transcription could not start: \(error.localizedDescription)")
                persist(note)
            }

            if note.transcriptionStatus != .failed {
                do {
                    guard let recordingURL = request.recordingURL else {
                        throw PostCaptureProcessingError.missingRecordingArtifact(request.noteID)
                    }

                    let result = try await transcriptionService.transcribe(
                        request: TranscriptionRequest(
                            audioFileURL: recordingURL,
                            startedAt: request.captureStartedAt ?? request.processingAnchorDate,
                            preferredLocaleIdentifier: transcriptionConfiguration.preferredLocaleIdentifier
                        ),
                        configuration: transcriptionConfiguration
                    )

                    note.applyTranscript(
                        result.segments,
                        backend: result.backend,
                        executionKind: result.executionKind,
                        warnings: result.warningMessages,
                        at: nowProvider()
                    )
                    statusMessages.append(contentsOf: result.warningMessages)
                    persist(note)
                } catch {
                    let fallbackPlan = transcriptionPlan.map {
                        ($0.backend, $0.executionKind, $0.warningMessages)
                    } ?? (
                        fallbackTranscriptionBackend(),
                        fallbackTranscriptionExecutionKind(),
                        []
                    )

                    note.recordTranscriptionFailure(
                        backend: fallbackPlan.0,
                        executionKind: fallbackPlan.1,
                        message: error.localizedDescription,
                        warnings: fallbackPlan.2,
                        at: nowProvider()
                    )
                    statusMessages.append("Recording saved locally, but transcription failed: \(error.localizedDescription)")
                    persist(note)
                }
            }
        }

        note = store.note(id: request.noteID) ?? note
        let canGenerate = note.transcriptionStatus == .succeeded
            || !note.rawNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if canGenerate, note.generationStatus != .succeeded {
            let template = store.template(id: note.templateID ?? selectedTemplate?.id ?? store.defaultTemplate.id)
                ?? selectedTemplate
                ?? store.defaultTemplate

            if note.generationStatus != .pending, note.processingState.stage != .generation {
                note.queueGeneration(templateID: template.id, at: nowProvider())
                persist(note)
            }

            if note.generationStatus != .pending {
                note.beginGeneration(templateID: template.id, at: nowProvider())
                persist(note)
            }

            do {
                let enhanced = try generator.generate(from: template.makeGenerationRequest(for: note))
                note.applyEnhancedNote(enhanced, at: nowProvider())
            } catch {
                note.recordGenerationFailure(error.localizedDescription, at: nowProvider())
                statusMessages.append("Enhanced note generation failed: \(error.localizedDescription)")
            }

            persist(note)
        } else if note.generationStatus == .pending
            || (note.processingState.stage == .generation && note.processingState.isActive) {
            note.recordGenerationFailure(
                "Enhanced note generation was skipped because no transcript or raw notes were available.",
                at: nowProvider()
            )
            statusMessages.append("Enhanced note generation was skipped because no transcript or raw notes were available.")
            persist(note)
        }

        note = store.note(id: request.noteID) ?? note
        cleanupRecordingArtifactIfEligible(for: note, statusMessages: &statusMessages)

        if selectedNoteID == note.id {
            switch request.trigger {
            case .relaunchRecovery:
                statusMessages.insert("Oatmeal resumed unfinished processing from the previous launch.", at: 0)
            case .manualRetry:
                statusMessages.insert("Manual retry finished.", at: 0)
            case .immediateAfterCapture:
                break
            }
            capturePermissionMessage = buildStatusMessage(from: statusMessages)
        }
    }

    private func persist(_ note: MeetingNote) {
        store.save(note)
        refresh()
        if selectedNoteID == nil || selectedNoteID == note.id {
            selectedNoteID = note.id
        }
        persistState()
    }

    private func cleanupRecordingArtifactIfEligible(for note: MeetingNote, statusMessages: inout [String]) {
        guard note.captureState.phase == .complete else {
            return
        }

        guard note.transcriptionStatus == .succeeded, note.generationStatus == .succeeded else {
            return
        }

        guard recordingURL(for: note) != nil else {
            return
        }

        do {
            try captureEngine.deleteRecording(for: note.id)
            statusMessages.append("Local recording artifact was cleaned up after successful processing.")
        } catch {
            statusMessages.append("Processing succeeded, but Oatmeal could not clean up the saved recording: \(error.localizedDescription)")
        }
    }

    private func requiresSystemAudio(for note: MeetingNote) -> Bool {
        note.calendarEvent != nil
    }

    private func captureRequirementsSatisfied(for note: MeetingNote, permissions: CapturePermissions) -> Bool {
        guard permissions.microphone == .granted else {
            return false
        }

        if requiresSystemAudio(for: note) {
            return permissions.systemAudio == .granted
        }

        return true
    }

    private func captureFailureMessage(for note: MeetingNote, permissions: CapturePermissions) -> String {
        var missing: [String] = []

        if permissions.microphone != .granted {
            missing.append("Microphone")
        }

        if requiresSystemAudio(for: note), permissions.systemAudio != .granted {
            missing.append("Screen & System Audio")
        }

        guard !missing.isEmpty else {
            return "Capture could not start."
        }

        return "Grant \(missing.joined(separator: " and ")) access in System Settings to start capture."
    }

    private func fallbackTranscriptionBackend() -> NoteTranscriptionBackend {
        switch transcriptionConfiguration.preferredBackend {
        case .automatic, .mock:
            .mock
        case .whisperCPPCLI:
            .whisperCPPCLI
        case .appleSpeech:
            .appleSpeech
        }
    }

    private func fallbackTranscriptionExecutionKind() -> NoteTranscriptionExecutionKind {
        switch fallbackTranscriptionBackend() {
        case .appleSpeech:
            .systemService
        case .mock:
            .placeholder
        case .whisperCPPCLI:
            .local
        }
    }

    private func buildStatusMessage(from messages: [String]) -> String? {
        let filtered = messages
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !filtered.isEmpty else {
            return nil
        }

        return filtered.joined(separator: " ")
    }
}
