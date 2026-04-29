import Foundation
import Observation
import OatmealCore
import OatmealEdge

@MainActor
@Observable
final class AppViewModel {
    enum LightweightSurfaceMainWindowRoute: Equatable, Sendable {
        case session(noteID: MeetingNote.ID, opensTranscript: Bool)
        case note(noteID: MeetingNote.ID)
        case upcoming(eventID: CalendarEvent.ID)
        case library
    }

    private let store: InMemoryOatmealStore
    private let calendarService: CalendarAccessServing
    private let captureService: CaptureAccessServing
    private let captureEngine: MeetingCaptureEngineServing
    private let nativeMeetingDetectionService: NativeMeetingDetectionServicing
    private let browserMeetingDetectionService: BrowserMeetingDetectionServicing
    private let meetingCandidateResolver: MeetingCandidateResolving
    private let transcriptionService: any LocalTranscriptionServicing
    private let summaryService: any LocalSummaryServicing
    private let summaryModelManager: any LocalSummaryModelManaging
    private let assistantService: any SingleMeetingAssistantServicing
    private let persistence: AppPersistence
    private let audioRetentionCoordinator: AudioRetentionCoordinator
    private let nowProvider: () -> Date
    private let liveTranscriptionPollingIntervalNanoseconds: UInt64
    @ObservationIgnored private var processingTasks: [MeetingNote.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var liveTranscriptionTasks: [MeetingNote.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var assistantTasks: [MeetingNote.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var openWindowAction: ((String) -> Void)?
    @ObservationIgnored private var dismissWindowAction: ((String) -> Void)?
    private let recoveredLiveTranscriptWarning = "Final recording transcription did not complete, so Oatmeal kept the recovered near-live transcript preview. Retry transcription later for a full pass."
    private let meetingEndedSuggestionMessage = "Oatmeal thinks this meeting may have ended. Stop recording when you are ready, or keep recording if the conversation is still going."
    private let interruptedAssistantTurnMessage = "Oatmeal was relaunched before this answer completed. Ask again to regenerate it."
    @ObservationIgnored private var summaryModelManagementTask: Task<Void, Never>?
    @ObservationIgnored private var hasStartedNativeMeetingDetection = false
    @ObservationIgnored private var hasStartedBrowserMeetingDetection = false
    @ObservationIgnored private var activeDetectedMeetingSource: PendingMeetingDetection.Source?

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
    var meetingDetectionConfiguration = MeetingDetectionConfiguration.default
    var transcriptionConfiguration = LocalTranscriptionConfiguration.default
    var transcriptionRuntimeState: LocalTranscriptionRuntimeState?
    var summaryConfiguration = LocalSummaryConfiguration.default
    var summaryRuntimeState: LocalSummaryRuntimeState?
    var summaryModelCatalogState: SummaryModelCatalogState?
    var activeSummaryModelOperation: SummaryModelOperationState?
    var summaryModelManagementError: String?
    var summaryExecutionPlansByNoteID: [MeetingNote.ID: LocalSummaryExecutionPlan] = [:]
    var selectedSidebarItem: SidebarItem = .upcoming
    var selectedUpcomingEventID: CalendarEvent.ID?
    var selectedNoteID: MeetingNote.ID?
    var selectedNoteWorkspaceMode: NoteWorkspaceMode = .notes
    var selectedTemplateID: NoteTemplate.ID?
    var pendingMeetingDetection: PendingMeetingDetection?
    var searchText = ""
    var dismissedSessionControllerPresentationIdentity: String?
    var collapsedSessionControllerPresentationIdentity: String?
    var isOnboardingComplete: Bool = OnboardingCompletion.isComplete

    init(
        store: InMemoryOatmealStore = .preview(),
        calendarService: CalendarAccessServing = LiveCalendarAccessService(),
        captureService: CaptureAccessServing = LiveCaptureAccessService(),
        captureEngine: MeetingCaptureEngineServing = LiveMeetingCaptureEngine(),
        nativeMeetingDetectionService: NativeMeetingDetectionServicing = LiveNativeMeetingDetectionService(),
        browserMeetingDetectionService: BrowserMeetingDetectionServicing = LiveBrowserMeetingDetectionService(),
        meetingCandidateResolver: MeetingCandidateResolving = LiveMeetingCandidateResolver(),
        transcriptionService: (any LocalTranscriptionServicing)? = nil,
        summaryService: (any LocalSummaryServicing)? = nil,
        summaryModelManager: (any LocalSummaryModelManaging)? = nil,
        persistence: AppPersistence = .shared,
        nowProvider: @escaping () -> Date = Date.init,
        liveTranscriptionPollingInterval: TimeInterval = 4,
        assistantService: (any SingleMeetingAssistantServicing)? = nil
    ) {
        self.store = store
        self.calendarService = calendarService
        self.captureService = captureService
        self.captureEngine = captureEngine
        self.nativeMeetingDetectionService = nativeMeetingDetectionService
        self.browserMeetingDetectionService = browserMeetingDetectionService
        self.meetingCandidateResolver = meetingCandidateResolver
        self.persistence = persistence
        self.nowProvider = nowProvider
        self.liveTranscriptionPollingIntervalNanoseconds = UInt64(
            max(liveTranscriptionPollingInterval, 0.25) * 1_000_000_000
        )
        self.transcriptionService = transcriptionService ?? LocalTranscriptionPipeline(
            applicationSupportDirectoryURL: persistence.applicationSupportDirectoryURL
        )
        self.summaryService = summaryService ?? LocalSummaryPipeline(
            applicationSupportDirectoryURL: persistence.applicationSupportDirectoryURL
        )
        self.summaryModelManager = summaryModelManager ?? LocalSummaryModelManager(
            applicationSupportDirectoryURL: persistence.applicationSupportDirectoryURL
        )
        self.assistantService = assistantService ?? GroundedSingleMeetingAssistantService()
        self.audioRetentionCoordinator = AudioRetentionCoordinator(
            recordingsDirectoryURL: persistence.applicationSupportDirectoryURL
                .appendingPathComponent("Recordings", isDirectory: true)
        )

        restorePersistedState()
        refresh()
        if selectedNoteID == nil {
            selectedNoteID = notes.first?.id
        }
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

    var canDeleteSelectedNote: Bool {
        guard let note = selectedNote else {
            return false
        }
        return canDelete(note: note)
    }

    var sessionControllerState: SessionControllerState? {
        SessionControllerAdapter.controllerState(for: notes, selectedNoteID: selectedNoteID)
    }

    var menuBarSessionState: SessionControllerState? {
        SessionControllerAdapter.menuBarState(
            for: notes,
            selectedNoteID: selectedNoteID,
            referenceDate: nowProvider()
        )
    }

    var detectionPromptState: MeetingDetectionPromptState? {
        MeetingDetectionPromptAdapter.promptState(for: pendingMeetingDetection)
    }

    var browserDetectionCapabilityState: BrowserDetectionCapabilityState {
        browserMeetingDetectionService.capabilityState
    }

    var noteWorkspaceState: NoteWorkspacePresentationState? {
        guard let selectedNote else {
            return nil
        }
        return NoteWorkspacePresentationState.make(
            note: selectedNote,
            selectedMode: selectedNoteWorkspaceMode
        )
    }

    var menuBarMeetingDetectionState: MeetingDetectionPromptState? {
        MeetingDetectionPromptAdapter.menuBarState(for: pendingMeetingDetection)
    }

    var menuBarSymbolName: String {
        menuBarSessionState?.menuBarSymbolName
            ?? menuBarMeetingDetectionState?.symbolName
            ?? "circle.fill"
    }

    var shouldAutoPresentSessionControllerOnLaunch: Bool {
        sessionControllerState != nil && !isSessionControllerDismissedForCurrentState
    }

    var isSessionControllerCollapsed: Bool {
        guard let state = sessionControllerState else {
            return false
        }
        return collapsedSessionControllerPresentationIdentity == state.presentationIdentity
    }

    var isSessionControllerDismissedForCurrentState: Bool {
        guard let state = sessionControllerState else {
            return false
        }
        return dismissedSessionControllerPresentationIdentity == state.presentationIdentity
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

    func focusSessionControllerNote(openTranscript: Bool = false) {
        guard let state = sessionControllerState else {
            return
        }

        selectedSidebarItem = .allNotes
        selectedNoteID = state.noteID
        if openTranscript {
            selectedNoteWorkspaceMode = .transcript
            setLiveTranscriptPanelPresented(true, for: state.noteID)
        }
        persistState()
    }

    @discardableResult
    func routeMainWindowFromLightweightSurface(
        openTranscript: Bool = false
    ) -> LightweightSurfaceMainWindowRoute {
        if let state = sessionControllerState {
            selectedSidebarItem = .allNotes
            selectedNoteID = state.noteID
            let shouldOpenTranscript = openTranscript && state.canOpenTranscript
            if shouldOpenTranscript {
                selectedNoteWorkspaceMode = .transcript
                setLiveTranscriptPanelPresented(true, for: state.noteID)
            }
            persistState()
            return .session(noteID: state.noteID, opensTranscript: shouldOpenTranscript)
        }

        if let state = menuBarSessionState {
            selectedSidebarItem = .allNotes
            selectedNoteID = state.noteID
            if openTranscript && state.canOpenTranscript {
                selectedNoteWorkspaceMode = .transcript
                setLiveTranscriptPanelPresented(true, for: state.noteID)
            }
            persistState()
            return .note(noteID: state.noteID)
        }

        if let selectedNote {
            selectedSidebarItem = .allNotes
            selectedNoteID = selectedNote.id
            persistState()
            return .note(noteID: selectedNote.id)
        }

        if let firstNote = notes.first {
            selectedSidebarItem = .allNotes
            selectedNoteID = firstNote.id
            persistState()
            return .note(noteID: firstNote.id)
        }

        if let upcomingEvent = selectedUpcomingEvent ?? filteredUpcomingMeetings.first ?? upcomingMeetings.first {
            selectedSidebarItem = .upcoming
            selectedUpcomingEventID = upcomingEvent.id
            persistState()
            return .upcoming(eventID: upcomingEvent.id)
        }

        selectedSidebarItem = .allNotes
        selectedNoteID = nil
        persistState()
        return .library
    }

    func startQuickNoteCapture() async {
        startQuickNote()
        await toggleCapture()
    }

    func bindLightweightSurfaceWindowActions(
        openWindow: @escaping (String) -> Void,
        dismissWindow: @escaping (String) -> Void
    ) {
        openWindowAction = openWindow
        dismissWindowAction = dismissWindow
    }

    func receiveMeetingDetection(_ detection: PendingMeetingDetection) {
        if detection.phase == .endSuggestion {
            receiveMeetingEndSuggestion(detection)
            return
        }

        let resolvedDetection = meetingCandidateResolver.resolve(
            detection: detection,
            availableEvents: upcomingMeetings
        )

        guard !notes.contains(where: { $0.captureState.isActive }) else {
            return
        }

        guard meetingDetectionConfiguration.isEnabled(for: resolvedDetection.source) else {
            if pendingMeetingDetection?.source == resolvedDetection.source {
                clearPendingMeetingDetection()
            }
            return
        }

        if let pendingMeetingDetection,
           pendingMeetingDetection.source == resolvedDetection.source,
           pendingMeetingDetection.effectiveTitle.caseInsensitiveCompare(resolvedDetection.effectiveTitle) == .orderedSame,
           pendingMeetingDetection.calendarContextSignature == resolvedDetection.calendarContextSignature {
            if pendingMeetingDetection.promptWasDismissed {
                return
            }

            if pendingMeetingDetection.presentation == .passiveSuggestion,
               resolvedDetection.presentation == .prompt {
                self.pendingMeetingDetection = resolvedDetection
                syncDetectionPromptWindowFromModel()
                persistState()
            }
            return
        }

        pendingMeetingDetection = resolvedDetection
        if shouldAutomaticallyStartCapture(for: resolvedDetection) {
            Task { [weak self] in
                await self?.startPendingMeetingDetectionCapture()
            }
            return
        }
        syncDetectionPromptWindowFromModel()
        persistState()
    }

    func ignorePendingMeetingDetectionPrompt() {
        guard var pendingMeetingDetection else {
            return
        }

        if pendingMeetingDetection.phase == .endSuggestion {
            pendingMeetingDetection.presentation = .passiveSuggestion
            pendingMeetingDetection.promptWasDismissed = true
            self.pendingMeetingDetection = pendingMeetingDetection
            syncDetectionPromptWindowFromModel()
            persistState()
            return
        }

        pendingMeetingDetection.presentation = .passiveSuggestion
        pendingMeetingDetection.promptWasDismissed = true
        self.pendingMeetingDetection = pendingMeetingDetection
        syncDetectionPromptWindowFromModel()
        persistState()
    }

    func clearPendingMeetingDetection() {
        pendingMeetingDetection = nil
        syncDetectionPromptWindowFromModel()
        persistState()
    }

    func selectPendingMeetingCandidate(_ eventID: CalendarEvent.ID) {
        guard var pendingMeetingDetection,
              let event = pendingMeetingDetection.candidateCalendarEvents.first(where: { $0.id == eventID }) else {
            return
        }

        pendingMeetingDetection.calendarEvent = event
        pendingMeetingDetection.presentation = .prompt
        self.pendingMeetingDetection = pendingMeetingDetection
        syncDetectionPromptWindowFromModel()
    }

    func startPendingMeetingDetectionCapture() async {
        guard var detection = pendingMeetingDetection else {
            return
        }

        if detection.phase == .endSuggestion {
            pendingMeetingDetection = nil
            syncDetectionPromptWindowFromModel()
            persistState()
            await stopSessionControllerCapture()
            return
        }

        if detection.requiresCalendarChoice {
            detection.presentation = .prompt
            pendingMeetingDetection = detection
            syncDetectionPromptWindowFromModel()
            persistState()
            return
        }

        pendingMeetingDetection = nil
        syncDetectionPromptWindowFromModel()
        persistState()

        if let event = detection.calendarEvent {
            startNote(for: event)
        } else {
            startDetectedMeeting(title: detection.effectiveTitle)
        }

        await toggleCapture()
        if selectedNote?.captureState.isActive == true {
            activeDetectedMeetingSource = detection.source
        } else {
            activeDetectedMeetingSource = nil
        }
    }

    func stopSessionControllerCapture() async {
        guard let state = sessionControllerState, state.canStopCapture else {
            return
        }

        selectedSidebarItem = .allNotes
        selectedNoteID = state.noteID
        await toggleCapture()
    }

    func shouldWarnBeforeStoppingCapture(for noteID: MeetingNote.ID, referenceDate: Date = Date()) -> Bool {
        guard let note = notes.first(where: { $0.id == noteID }),
              note.captureState.isActive,
              let startedAt = note.captureState.startedAt else {
            return false
        }

        return referenceDate.timeIntervalSince(startedAt) < 300
    }

    func replaceScratchpad(_ text: String, for noteID: MeetingNote.ID) {
        guard var note = store.note(id: noteID) else {
            return
        }

        note.replaceScratchpad(text, updatedAt: nowProvider())
        persist(note)
    }

    func availableMicrophones() -> [CaptureInputDevice] {
        captureEngine.availableMicrophones()
    }

    func activeMicrophoneID(for noteID: MeetingNote.ID) -> String? {
        captureEngine.activeMicrophoneID(for: noteID)
    }

    func switchActiveMicrophone(to deviceID: String, for noteID: MeetingNote.ID) async throws {
        try await captureEngine.switchMicrophone(to: deviceID, for: noteID)
    }

    func stopSessionControllerCaptureForTermination() async -> Bool {
        guard let state = sessionControllerState else {
            return true
        }

        guard state.canStopCapture else {
            return true
        }

        let activeNoteID = state.noteID
        await stopSessionControllerCapture()

        if let note = notes.first(where: { $0.id == activeNoteID }) {
            return note.captureState.phase == .complete || note.processingState.isActive
        }

        return sessionControllerState?.canStopCapture != true
    }

    func selectFirstAvailableNote() {
        selectedNoteID = filteredNotes.first?.id
        persistState()
    }

    func selectFirstUpcomingMeetingIfNeeded() {
        if selectedUpcomingEventID == nil {
            selectedUpcomingEventID = filteredUpcomingMeetings.first?.id
            persistState()
        }
    }

    func refresh() {
        folders = store.folders
        notes = store.allNotes()
        templates = store.allTemplates()
        reconcileSessionControllerPresentationState()

        if selectedTemplateID == nil {
            selectedTemplateID = templates.first?.id
        }
    }

    func dismissSessionController() {
        guard let state = sessionControllerState else {
            return
        }

        dismissedSessionControllerPresentationIdentity = state.presentationIdentity
        persistState()
    }

    func reopenSessionController() {
        dismissedSessionControllerPresentationIdentity = nil
        persistState()
    }

    func toggleSessionControllerCollapsed() {
        guard let state = sessionControllerState else {
            collapsedSessionControllerPresentationIdentity = nil
            return
        }

        if collapsedSessionControllerPresentationIdentity == state.presentationIdentity {
            collapsedSessionControllerPresentationIdentity = nil
        } else {
            collapsedSessionControllerPresentationIdentity = state.presentationIdentity
            dismissedSessionControllerPresentationIdentity = nil
        }
        persistState()
    }

    func setSelectedSidebarItem(_ item: SidebarItem) {
        selectedSidebarItem = item
        persistState()
    }

    func setSelectedUpcomingEventID(_ id: CalendarEvent.ID?) {
        selectedUpcomingEventID = id
        persistState()
    }

    func setSelectedNoteID(_ id: MeetingNote.ID?) {
        selectedNoteID = id
        persistState()
    }

    func setSelectedNoteWorkspaceMode(_ mode: NoteWorkspaceMode) {
        selectedNoteWorkspaceMode = mode
        persistState()
    }

    func setSelectedTemplateID(_ id: NoteTemplate.ID?) {
        selectedTemplateID = id
        persistState()
    }

    func deleteSelectedNote() {
        guard let note = selectedNote else {
            return
        }
        deleteNote(id: note.id)
    }

    func deleteNote(id: MeetingNote.ID) {
        guard let note = store.note(id: id), canDelete(note: note) else {
            return
        }

        assistantTasks[id]?.cancel()
        assistantTasks[id] = nil
        liveTranscriptionTasks[id]?.cancel()
        liveTranscriptionTasks[id] = nil
        processingTasks[id]?.cancel()
        processingTasks[id] = nil

        try? captureEngine.deleteRecording(for: id)
        try? audioRetentionCoordinator.apply(.noteDeleted(noteID: id))
        store.delete(noteID: id)
        refresh()

        if selectedNoteID == id {
            selectedNoteID = filteredNotes.first?.id ?? notes.first?.id
            selectedNoteWorkspaceMode = .notes
            if selectedNoteID == nil {
                selectedSidebarItem = .allNotes
            }
        }

        persistState()
    }

    /// Re-runs transcription against a note's retained normalized WAV using
    /// a caller-provided language. Updates the note's `language` and appends
    /// a new `NoteTranscriptionAttempt` to `transcriptionHistory`. Throws
    /// `TranscriptionPipelineError.fileNotFound` when the note has no
    /// retained WAV (legacy notes, or notes whose audio has been deleted).
    ///
    /// This API is programmatic-only in this milestone; the note-detail UI
    /// override-and-re-transcribe affordance is wired up in a later phase.
    @discardableResult
    func reTranscribe(noteID: MeetingNote.ID, language: String) async throws -> TranscriptionJobResult {
        guard let retainedWAVURL = audioRetentionCoordinator.retainedWAVURL(for: noteID) else {
            throw TranscriptionPipelineError.fileNotFound
        }

        let result = try await transcriptionService.reTranscribe(
            noteID: noteID,
            language: language,
            retainedWAVURL: retainedWAVURL,
            configuration: transcriptionConfiguration
        )

        if var note = store.note(id: noteID) {
            let updatedAt = nowProvider()
            note.transcriptionHistory.append(
                NoteTranscriptionAttempt(
                    backend: result.backend,
                    executionKind: result.executionKind,
                    requestedAt: updatedAt,
                    completedAt: updatedAt,
                    status: .succeeded,
                    segmentCount: result.segments.count,
                    warningMessages: result.warningMessages,
                    language: language
                )
            )
            note.transcriptSegments = result.segments
            note.language = result.detectedLanguage ?? language
            note.updatedAt = updatedAt
            persist(note)
        }

        return result
    }

    func loadSystemState() async {
        await loadCalendarState()
        await refreshCapturePermissions()
        await refreshTranscriptionRuntimeState()
        await refreshSummaryRuntimeState()
        await refreshSummaryModelCatalogState()
        startNativeMeetingDetectionIfNeeded()
        startBrowserMeetingDetectionIfNeeded()
        suggestEndedMeetingsIfNeeded()
        recoverLiveSessionsIfNeeded()
        resumePostCaptureProcessingIfNeeded()
        if let pendingMeetingDetection,
           meetingDetectionConfiguration.isEnabled(for: pendingMeetingDetection.source) {
            syncDetectionPromptWindowFromModel()
        } else if pendingMeetingDetection != nil {
            clearPendingMeetingDetection()
        }
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

    func requestMicrophoneAccess() async {
        _ = await captureService.requestPermissions(
            requiresSystemAudio: false,
            calendarStatus: calendarAccessStatus
        )
        await refreshCapturePermissions()
    }

    func requestSystemAudioAccess() async {
        _ = await captureService.requestPermissions(
            requiresSystemAudio: true,
            calendarStatus: calendarAccessStatus
        )
        await refreshCapturePermissions()
    }

    func onboardingCompletionDidChange() {
        isOnboardingComplete = OnboardingCompletion.isComplete
    }

    func refreshTranscriptionRuntimeState() async {
        transcriptionRuntimeState = await transcriptionService.runtimeState(configuration: transcriptionConfiguration)
    }

    func refreshSummaryRuntimeState() async {
        summaryRuntimeState = await summaryService.runtimeState(configuration: summaryConfiguration)
    }

    func refreshSummaryModelCatalogState() async {
        summaryModelCatalogState = await summaryModelManager.catalogState()
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
        selectedNoteWorkspaceMode = .notes
        persistState()
    }

    func startDetectedMeeting(title: String) {
        let now = nowProvider()
        let note = MeetingNote(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? "Untitled Meeting",
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
        selectedNoteWorkspaceMode = .notes
        persistState()
    }

    func startNote(for event: CalendarEvent) {
        if let existingNote = note(for: event) {
            selectedSidebarItem = .allNotes
            selectedNoteID = existingNote.id
            selectedNoteWorkspaceMode = .notes
            persistState()
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
        selectedNoteWorkspaceMode = .notes
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
                note.failLiveSession(message: message, at: now)
                store.save(note)
                refresh()
                selectedNoteID = note.id
                persistState()
                return
            }

            do {
                let mode: CaptureMode = requiresSystemAudio(for: note) ? .systemAudioAndMicrophone : .microphoneOnly
                let session = try await captureEngine.startCapture(for: note.id, mode: mode)
                pendingMeetingDetection = nil
                note.captureState.beginCapture(at: session.startedAt)
                note.beginLiveSession(
                    at: session.startedAt,
                    presentTranscriptPanel: note.liveSessionState.isTranscriptPanelPresented,
                    tracksSystemAudio: mode == .systemAudioAndMicrophone
                )
                startLiveTranscription(for: session)
            } catch {
                let message = error.localizedDescription
                capturePermissionMessage = message
                activeDetectedMeetingSource = nil
                if pendingMeetingDetection?.phase == .endSuggestion {
                    pendingMeetingDetection = nil
                }
                note.captureState.fail(reason: message, at: now, recoverable: true)
                note.failLiveSession(message: message, at: now)
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
            cancelLiveTranscription(for: note.id)
            let artifact: CaptureArtifact
            do {
                artifact = try await captureEngine.stopCapture()
            } catch {
                let message = error.localizedDescription
                capturePermissionMessage = message
                activeDetectedMeetingSource = nil
                if pendingMeetingDetection?.phase == .endSuggestion {
                    pendingMeetingDetection = nil
                }
                note.captureState.fail(reason: message, at: now, recoverable: true)
                note.failLiveSession(message: message, at: now)
                store.save(note)
                refresh()
                selectedNoteID = note.id
                persistState()
                return
            }

            note.captureState.complete(at: artifact.endedAt)
            activeDetectedMeetingSource = nil
            if pendingMeetingDetection?.phase == .endSuggestion {
                pendingMeetingDetection = nil
            }
            let liveCompletionMessage: String?
            if note.liveSessionState.status == .delayed || note.liveSessionState.hasPreviewEntries {
                liveCompletionMessage = "Recording stopped. Oatmeal is reconciling the near-live transcript with the saved recording in the background."
            } else {
                liveCompletionMessage = nil
            }
            note.completeLiveSession(message: liveCompletionMessage, at: artifact.endedAt)
            var statusMessages: [String] = []
            if artifact.duration < 300 {
                statusMessages.append("Short recording saved locally. Summaries are usually more useful once a meeting runs longer than five minutes.")
            }

            summaryExecutionPlansByNoteID[note.id] = nil
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

    func setTranscriptionPreferredLocaleIdentifier(_ localeIdentifier: String?) {
        let normalized = localeIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank
        transcriptionConfiguration.preferredLocaleIdentifier = normalized
        persistState()
        Task {
            await refreshTranscriptionRuntimeState()
        }
    }

    func setSummaryBackendPreference(_ preference: SummaryBackendPreference) {
        summaryConfiguration.preferredBackend = preference
        persistState()
        Task {
            await refreshSummaryRuntimeState()
        }
    }

    func setSummaryExecutionPolicy(_ policy: SummaryExecutionPolicy) {
        summaryConfiguration.executionPolicy = policy
        persistState()
        Task {
            await refreshSummaryRuntimeState()
        }
    }

    func setSummaryPreferredModelName(_ preferredModelName: String?) {
        summaryConfiguration.preferredModelName = preferredModelName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank
        persistState()
        Task {
            await refreshSummaryRuntimeState()
        }
    }

    func setMeetingDetectionSourceEnabled(_ source: MeetingDetectionSourceSetting, enabled: Bool) {
        switch source {
        case .zoom:
            meetingDetectionConfiguration.zoomEnabled = enabled
        case .teams:
            meetingDetectionConfiguration.teamsEnabled = enabled
        case .slack:
            meetingDetectionConfiguration.slackEnabled = enabled
        case .browsers:
            meetingDetectionConfiguration.browsersEnabled = enabled
        }

        if let pendingMeetingDetection,
           !meetingDetectionConfiguration.isEnabled(for: pendingMeetingDetection.source) {
            clearPendingMeetingDetection()
        }

        persistState()
    }

    func setHighConfidenceAutoStartEnabled(_ enabled: Bool) {
        meetingDetectionConfiguration.highConfidenceAutoStartEnabled = enabled
        persistState()
    }

    func setLiveTranscriptPanelPresented(_ presented: Bool, for noteID: MeetingNote.ID) {
        guard var note = store.note(id: noteID) else {
            return
        }

        note.setLiveTranscriptPanelPresented(presented, updatedAt: nowProvider())
        persist(note)
    }

    func installSummaryModel(_ entry: SummaryModelCatalogEntry, forceRedownload: Bool = false) {
        guard activeSummaryModelOperation == nil else {
            return
        }

        summaryModelManagementError = nil
        activeSummaryModelOperation = SummaryModelOperationState(
            kind: forceRedownload ? .updating : .downloading,
            modelDisplayName: entry.displayName
        )

        summaryModelManagementTask?.cancel()
        summaryModelManagementTask = Task {
            do {
                let catalogState = try await summaryModelManager.install(
                    modelID: entry.id,
                    forceRedownload: forceRedownload
                )
                summaryModelCatalogState = catalogState
                summaryModelManagementError = nil
                activeSummaryModelOperation = nil
                await refreshSummaryRuntimeState()
            } catch is CancellationError {
                activeSummaryModelOperation = nil
            } catch {
                summaryModelManagementError = error.localizedDescription
                activeSummaryModelOperation = nil
                await refreshSummaryModelCatalogState()
            }
        }
    }

    func removeSummaryModel(_ installedModel: ManagedSummaryModel) {
        guard activeSummaryModelOperation == nil else {
            return
        }

        summaryModelManagementError = nil
        activeSummaryModelOperation = SummaryModelOperationState(
            kind: .removing,
            modelDisplayName: installedModel.displayName
        )

        summaryModelManagementTask?.cancel()
        summaryModelManagementTask = Task {
            do {
                let catalogState = try await summaryModelManager.remove(modelDirectoryURL: installedModel.directoryURL)
                summaryModelCatalogState = catalogState

                if summaryConfiguration.preferredModelName?.caseInsensitiveCompare(installedModel.displayName) == .orderedSame {
                    summaryConfiguration.preferredModelName = nil
                    persistState()
                }

                summaryModelManagementError = nil
                activeSummaryModelOperation = nil
                await refreshSummaryRuntimeState()
            } catch is CancellationError {
                activeSummaryModelOperation = nil
            } catch {
                summaryModelManagementError = error.localizedDescription
                activeSummaryModelOperation = nil
                await refreshSummaryModelCatalogState()
            }
        }
    }

    func summaryExecutionPlan(for note: MeetingNote) -> LocalSummaryExecutionPlan? {
        summaryExecutionPlansByNoteID[note.id]
    }

    func summaryPlanSummary(for note: MeetingNote) -> String? {
        summaryExecutionPlan(for: note)?.summary ?? summaryRuntimeState?.activePlanSummary
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
        summaryExecutionPlansByNoteID[note.id] = nil
        note.queueTranscription(at: now)
        persist(note)

        enqueuePostCaptureProcessing(
            PostCaptureProcessingRequest(
                noteID: note.id,
                recordingURL: recordingURL(for: note),
                captureStartedAt: note.captureState.startedAt,
                processingAnchorDate: now,
                trigger: .manualTranscriptionRetry
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
        summaryExecutionPlansByNoteID[note.id] = nil
        note.queueGeneration(templateID: template.id, at: now)
        persist(note)

        enqueuePostCaptureProcessing(
            PostCaptureProcessingRequest(
                noteID: note.id,
                recordingURL: recordingURL(for: note),
                captureStartedAt: note.captureState.startedAt,
                processingAnchorDate: now,
                trigger: .manualGenerationRetry
            )
        )

        capturePermissionMessage = "Retrying enhanced note generation."
    }

    func submitAssistantPrompt(_ prompt: String, for noteID: MeetingNote.ID) {
        submitAssistantTurn(
            prompt,
            kind: .prompt,
            for: noteID
        )
    }

    func submitAssistantDraftAction(_ kind: NoteAssistantTurnKind, for noteID: MeetingNote.ID) {
        guard let prompt = kind.assistantRecipePrompt else {
            return
        }

        submitAssistantTurn(prompt, kind: kind, for: noteID)
    }

    func retryAssistantTurn(_ turnID: UUID, for noteID: MeetingNote.ID) {
        guard let note = store.note(id: noteID),
              let turn = note.assistantThread.turns.first(where: { $0.id == turnID }),
              turn.status == .failed,
              !note.hasPendingAssistantTurn else {
            return
        }

        submitAssistantTurn(turn.prompt, kind: turn.kind, for: noteID)
    }

    private func submitAssistantTurn(
        _ prompt: String,
        kind: NoteAssistantTurnKind,
        for noteID: MeetingNote.ID
    ) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty,
              var note = store.note(id: noteID),
              note.isAIWorkspaceAvailable,
              !note.hasPendingAssistantTurn else {
            return
        }

        let requestedAt = nowProvider()
        let turnID = note.submitAssistantPrompt(trimmedPrompt, kind: kind, at: requestedAt)
        persist(note)

        assistantTasks[noteID]?.cancel()
        assistantTasks[noteID] = Task { [assistantService, weak self] in
            do {
                let response = try await assistantService.respond(
                    to: SingleMeetingAssistantRequest(
                        noteID: note.id,
                        noteTitle: note.title,
                        turnKind: kind,
                        prompt: trimmedPrompt,
                        rawNotes: note.rawNotes,
                        transcriptSegments: note.transcriptSegments,
                        enhancedNote: note.enhancedNote,
                        calendarEvent: note.calendarEvent
                    )
                )

                await MainActor.run {
                    guard let self, var latestNote = self.store.note(id: noteID) else {
                        self?.assistantTasks[noteID] = nil
                        return
                    }

                    _ = latestNote.completeAssistantTurn(
                        id: turnID,
                        response: response.text,
                        citations: response.citations,
                        at: response.generatedAt
                    )
                    self.persist(latestNote)
                    self.assistantTasks[noteID] = nil
                }
            } catch is CancellationError {
                await MainActor.run {
                    self?.assistantTasks[noteID] = nil
                }
            } catch {
                await MainActor.run {
                    guard let self, var latestNote = self.store.note(id: noteID) else {
                        self?.assistantTasks[noteID] = nil
                        return
                    }

                    _ = latestNote.failAssistantTurn(
                        id: turnID,
                        message: error.localizedDescription,
                        at: self.nowProvider()
                    )
                    self.persist(latestNote)
                    self.assistantTasks[noteID] = nil
                }
            }
        }
    }

    private func restorePersistedState() {
        let snapshot = persistence.loadOrEmpty()
        guard !snapshot.notes.isEmpty
            || snapshot.selectedSidebarItem != nil
            || snapshot.selectedUpcomingEventID != nil
            || snapshot.selectedNoteID != nil
            || snapshot.selectedNoteWorkspaceMode != nil
            || snapshot.selectedTemplateID != nil
            || snapshot.collapsedSessionControllerPresentationIdentity != nil
            || snapshot.pendingMeetingDetection != nil
            || snapshot.meetingDetectionConfiguration != .default
            || snapshot.transcriptionConfiguration != .default
            || snapshot.summaryConfiguration != .default else {
            return
        }

        for existing in store.allNotes() {
            store.delete(noteID: existing.id)
        }

        for var note in snapshot.notes {
            _ = note.prepareAssistantThreadForRelaunchRecovery(
                message: interruptedAssistantTurnMessage,
                at: nowProvider()
            )
            store.save(note)
        }

        selectedSidebarItem = snapshot.selectedSidebarItem ?? .upcoming
        selectedUpcomingEventID = snapshot.selectedUpcomingEventID
        selectedNoteID = snapshot.selectedNoteID
        selectedNoteWorkspaceMode = snapshot.selectedNoteWorkspaceMode ?? .notes
        selectedTemplateID = snapshot.selectedTemplateID
        collapsedSessionControllerPresentationIdentity = snapshot.collapsedSessionControllerPresentationIdentity
        pendingMeetingDetection = snapshot.pendingMeetingDetection
        meetingDetectionConfiguration = snapshot.meetingDetectionConfiguration
        transcriptionConfiguration = snapshot.transcriptionConfiguration
        summaryConfiguration = snapshot.summaryConfiguration
    }

    private func persistState() {
        do {
            try persistence.save(
                notes: store.allNotes(),
                selectedSidebarItem: selectedSidebarItem,
                selectedUpcomingEventID: selectedUpcomingEventID,
                selectedNoteID: selectedNoteID,
                selectedNoteWorkspaceMode: selectedNoteWorkspaceMode,
                selectedTemplateID: selectedTemplateID,
                collapsedSessionControllerPresentationIdentity: collapsedSessionControllerPresentationIdentity,
                pendingMeetingDetection: pendingMeetingDetection,
                meetingDetectionConfiguration: meetingDetectionConfiguration,
                transcriptionConfiguration: transcriptionConfiguration,
                summaryConfiguration: summaryConfiguration
            )
        } catch {
            capturePermissionMessage = "Unable to save local state: \(error.localizedDescription)"
        }
    }

    private func startNativeMeetingDetectionIfNeeded() {
        guard !hasStartedNativeMeetingDetection else {
            return
        }

        hasStartedNativeMeetingDetection = true
        nativeMeetingDetectionService.start { [weak self] detection in
            self?.receiveMeetingDetection(detection)
        }
    }

    private func startBrowserMeetingDetectionIfNeeded() {
        guard !hasStartedBrowserMeetingDetection else {
            return
        }

        hasStartedBrowserMeetingDetection = true
        browserMeetingDetectionService.start { [weak self] detection in
            self?.receiveMeetingDetection(detection)
        }
    }

    private func syncDetectionPromptWindowFromModel() {
        guard let openWindowAction, let dismissWindowAction else {
            return
        }

        let coordinator = SessionControllerSceneCoordinator(
            openWindow: openWindowAction,
            dismissWindow: dismissWindowAction
        )
        coordinator.syncDetectionPromptWindow(with: self)
    }

    private func shouldAutomaticallyStartCapture(for detection: PendingMeetingDetection) -> Bool {
        guard detection.phase == .start else {
            return false
        }

        guard meetingDetectionConfiguration.highConfidenceAutoStartEnabled else {
            return false
        }

        guard detection.confidence == .high else {
            return false
        }

        guard !detection.requiresCalendarChoice else {
            return false
        }

        let requiredPermissions: CapturePermissions
        if detection.calendarEvent != nil {
            requiredPermissions = CapturePermissions(
                microphone: capturePermissions.microphone,
                systemAudio: capturePermissions.systemAudio,
                notifications: capturePermissions.notifications,
                calendar: capturePermissions.calendar
            )
            return requiredPermissions.microphone == .granted
                && requiredPermissions.systemAudio == .granted
        }

        return capturePermissions.microphone == .granted
    }

    private func reconcileSessionControllerPresentationState() {
        guard let state = sessionControllerState else {
            dismissedSessionControllerPresentationIdentity = nil
            collapsedSessionControllerPresentationIdentity = nil
            return
        }

        if dismissedSessionControllerPresentationIdentity != state.presentationIdentity {
            dismissedSessionControllerPresentationIdentity = nil
        }

        if collapsedSessionControllerPresentationIdentity != state.presentationIdentity {
            collapsedSessionControllerPresentationIdentity = nil
        }
    }

    private func receiveMeetingEndSuggestion(_ detection: PendingMeetingDetection) {
        guard let activeDetectedMeetingSource,
              activeDetectedMeetingSource == detection.source,
              let activeNote = notes.first(where: { $0.captureState.isActive }) else {
            return
        }

        if let pendingMeetingDetection,
           pendingMeetingDetection.phase == .endSuggestion,
           pendingMeetingDetection.source == detection.source {
            if pendingMeetingDetection.promptWasDismissed {
                return
            }

            if pendingMeetingDetection.presentation == .passiveSuggestion,
               detection.presentation == .prompt {
                self.pendingMeetingDetection = detection
                syncDetectionPromptWindowFromModel()
                persistState()
            }
            return
        }

        var suggestion = detection
        if activeNote.calendarEvent != nil {
            suggestion.calendarEvent = activeNote.calendarEvent
        }
        if suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || suggestion.title == "Untitled Meeting" {
            suggestion.title = activeNote.title
        }

        surfaceMeetingEndSuggestion(for: activeNote.id, message: meetingEndedSuggestionMessage)
        pendingMeetingDetection = suggestion
        syncDetectionPromptWindowFromModel()
        persistState()
    }

    private func suggestEndedMeetingsIfNeeded() {
        let now = nowProvider()

        for note in notes where note.captureState.isActive {
            guard let calendarEvent = note.calendarEvent,
                  calendarEvent.endDate <= now else {
                continue
            }

            surfaceMeetingEndSuggestion(for: note.id, message: meetingEndedSuggestionMessage)
            if pendingMeetingDetection == nil {
                pendingMeetingDetection = PendingMeetingDetection(
                    title: note.title,
                    source: .unknown,
                    phase: .endSuggestion,
                    detectedAt: now,
                    presentation: .prompt,
                    confidence: .low,
                    calendarEvent: calendarEvent
                )
            }
        }
    }

    private func surfaceMeetingEndSuggestion(for noteID: MeetingNote.ID, message: String) {
        guard var note = store.note(id: noteID), note.captureState.isActive else {
            return
        }

        let updatedAt = nowProvider()
        let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let alreadySurfaced = note.liveSessionState.statusMessage == normalizedMessage
            || note.liveSessionState.previewEntries.contains(where: { entry in
                entry.kind == .system
                    && entry.text.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedMessage
            })
        guard !alreadySurfaced else {
            return
        }

        note.liveSessionState.statusMessage = normalizedMessage
        note.liveSessionState.lastUpdatedAt = updatedAt
        note.appendLiveTranscriptEntry(
            LiveTranscriptEntry(
                createdAt: updatedAt,
                kind: .system,
                text: normalizedMessage
            ),
            updatedAt: updatedAt
        )
        persist(note)
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

    private func recoverLiveSessionsIfNeeded() {
        let recoveredAt = nowProvider()

        for var note in notes {
            guard note.captureState.isActive else {
                continue
            }

            cancelLiveTranscription(for: note.id)
            guard captureEngine.activeSession?.noteID != note.id else {
                continue
            }

            let message = "Oatmeal restored this live session after relaunch. Resume capture to continue recording and live transcription."
            note.captureState.fail(reason: message, at: recoveredAt, recoverable: true)
            note.recordLiveSessionInterruption(updatedAt: recoveredAt)
            note.markLiveSessionRecovered(message: message, at: recoveredAt)
            persist(note)
        }
    }

    private func startLiveTranscription(for session: ActiveCaptureSession) {
        cancelLiveTranscription(for: session.noteID)

        liveTranscriptionTasks[session.noteID] = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: liveTranscriptionPollingIntervalNanoseconds)
                } catch {
                    return
                }

                guard !Task.isCancelled else {
                    return
                }

                await performLiveTranscriptionPass(noteID: session.noteID)
            }
        }
    }

    private func cancelLiveTranscription(for noteID: MeetingNote.ID) {
        liveTranscriptionTasks.removeValue(forKey: noteID)?.cancel()
    }

    private func performLiveTranscriptionPass(noteID: MeetingNote.ID) async {
        guard var note = store.note(id: noteID) else {
            cancelLiveTranscription(for: noteID)
            return
        }

        guard note.captureState.isActive else {
            cancelLiveTranscription(for: noteID)
            return
        }

        let handledRuntimeEvents = handleCaptureRuntimeEvents(for: &note)
        if handledRuntimeEvents {
            note = store.note(id: noteID) ?? note
        }

        let pendingChunks = pendingLiveChunks(for: note)
        guard !pendingChunks.isEmpty else {
            let metricsRefreshed = refreshLiveSessionMetrics(
                for: &note,
                pendingChunks: [],
                updatedAt: nowProvider()
            )
            if metricsRefreshed {
                persist(note)
            }
            return
        }

        var appendedEntries = 0

        for (index, chunk) in pendingChunks.enumerated() {
            let queuedBehindCurrentChunk = Array(pendingChunks.suffix(from: index + 1))
            let queuedMetricsChanged = refreshLiveSessionMetrics(
                for: &note,
                pendingChunks: queuedBehindCurrentChunk,
                updatedAt: nowProvider()
            )
            if queuedMetricsChanged {
                persist(note)
                note = store.note(id: noteID) ?? note
            }

            do {
                let result = try await transcriptionService.transcribe(
                    request: TranscriptionRequest(
                        audioFileURL: chunk.fileURL,
                        startedAt: chunk.startedAt,
                        preferredLocaleIdentifier: transcriptionConfiguration.preferredLocaleIdentifier
                    ),
                    configuration: transcriptionConfiguration
                )

                guard !Task.isCancelled else {
                    return
                }

                note = store.note(id: noteID) ?? note
                guard note.captureState.isActive else {
                    cancelLiveTranscription(for: noteID)
                    return
                }

                let updatedAt = nowProvider()
                let previewEntries = result.segments.map { segment in
                    LiveTranscriptEntry(
                        createdAt: segment.startTime ?? chunk.startedAt,
                        kind: .transcript,
                        speakerName: segment.speakerName ?? chunk.source.defaultSpeakerName,
                        text: segment.text
                    )
                }

                for entry in previewEntries {
                    note.appendLiveTranscriptEntry(entry, updatedAt: updatedAt)
                }

                appendedEntries += previewEntries.count
                note.registerProcessedLiveChunkID(chunk.id, updatedAt: updatedAt)
                note.recordMergedLiveChunk(updatedAt: updatedAt, sourceEndedAt: chunk.endedAt)
                _ = refreshLiveSessionMetrics(
                    for: &note,
                    pendingChunks: pendingLiveChunks(for: note),
                    updatedAt: updatedAt
                )
                note.markLiveSessionLive(
                    message: previewEntries.isEmpty
                        ? "Capture is active. Oatmeal saved another live chunk and is still preparing transcript text."
                        : "Live transcript updated \(updatedAt.formatted(date: .omitted, time: .shortened)). Oatmeal merged a saved chunk into the in-meeting transcript preview.",
                    at: updatedAt
                )
                persist(note)
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                note = store.note(id: noteID) ?? note
                let message = "Capture is still running. Oatmeal kept the recording safe and will retry the delayed live chunk in the background."
                _ = refreshLiveSessionMetrics(
                    for: &note,
                    pendingChunks: pendingLiveChunks(for: note),
                    updatedAt: nowProvider()
                )
                if note.liveSessionState.status != .delayed || note.liveSessionState.statusMessage != message {
                    note.markLiveSessionDelayed(message: message, at: nowProvider())
                    persist(note)
                }
                return
            }
        }

        if appendedEntries == 0 {
            note = store.note(id: noteID) ?? note
            note.markLiveSessionLive(
                message: "Capture is active. Oatmeal saved live chunks, but the local runtime has not emitted transcript text yet.",
                at: nowProvider()
            )
            persist(note)
        }
    }

    private func handleCaptureRuntimeEvents(for note: inout MeetingNote) -> Bool {
        let events = captureEngine.consumeRuntimeEvents(for: note.id)
        guard !events.isEmpty else {
            return false
        }

        var didMutate = false
        for event in events.sorted(by: { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.createdAt < rhs.createdAt
        }) {
            updateLiveCaptureSourceHealth(for: &note, event: event)

            switch event.kind {
            case .degraded:
                if shouldPauseCapture(for: note, event: event) {
                    note.captureState.pause(at: event.createdAt)
                    note.captureState.failureReason = event.message
                }
                note.markLiveSessionDelayed(message: event.message, at: event.createdAt)
                appendLiveRuntimeMessageIfNeeded(event.message, to: &note, at: event.createdAt)
            case .recovered:
                recordRecoveredSourceActivityIfNeeded(for: &note, event: event)
                if shouldResumeCapture(for: note, event: event) {
                    note.captureState.resume(at: event.createdAt)
                }
                note.markLiveSessionRecovered(message: event.message, at: event.createdAt)
            case .failed:
                cancelLiveTranscription(for: note.id)
                note.captureState.fail(reason: event.message, at: event.createdAt, recoverable: true)
                note.failLiveSession(message: event.message, at: event.createdAt)
                salvageInterruptedCaptureIfPossible(for: &note, at: event.createdAt)
            }

            if selectedNoteID == note.id {
                capturePermissionMessage = captureRuntimeStatusMessage(for: note, event: event)
            }
            didMutate = true
        }

        if didMutate {
            persist(note)
        }

        return didMutate
    }

    private func updateLiveCaptureSourceHealth(
        for note: inout MeetingNote,
        event: CaptureRuntimeEvent
    ) {
        let sourceStatus: LiveCaptureSourceStatus = switch event.kind {
        case .degraded:
            .delayed
        case .recovered:
            .recovered
        case .failed:
            .failed
        }

        switch event.source {
        case .microphone:
            note.updateLiveCaptureSource(.microphone, status: sourceStatus, message: event.message, updatedAt: event.createdAt)
        case .systemAudio:
            note.updateLiveCaptureSource(.systemAudio, status: sourceStatus, message: event.message, updatedAt: event.createdAt)
        case .capturePipeline:
            note.updateLiveCaptureSource(.microphone, status: sourceStatus, message: event.message, updatedAt: event.createdAt)
            if requiresSystemAudio(for: note) {
                note.updateLiveCaptureSource(.systemAudio, status: sourceStatus, message: event.message, updatedAt: event.createdAt)
            }
        }
    }

    private func recordRecoveredSourceActivityIfNeeded(
        for note: inout MeetingNote,
        event: CaptureRuntimeEvent
    ) {
        switch event.source {
        case .microphone:
            note.recordLiveCaptureSourceActivity(.microphone, updatedAt: event.createdAt)
        case .systemAudio:
            note.recordLiveCaptureSourceActivity(.systemAudio, updatedAt: event.createdAt)
        case .capturePipeline:
            note.recordLiveCaptureSourceActivity(.microphone, updatedAt: event.createdAt)
            if requiresSystemAudio(for: note) {
                note.recordLiveCaptureSourceActivity(.systemAudio, updatedAt: event.createdAt)
            }
        }
    }

    private func shouldPauseCapture(for note: MeetingNote, event: CaptureRuntimeEvent) -> Bool {
        switch event.source {
        case .capturePipeline:
            false
        case .microphone:
            !requiresSystemAudio(for: note)
        case .systemAudio:
            false
        }
    }

    private func shouldResumeCapture(for note: MeetingNote, event: CaptureRuntimeEvent) -> Bool {
        switch event.source {
        case .capturePipeline:
            false
        case .microphone:
            !requiresSystemAudio(for: note)
        case .systemAudio:
            false
        }
    }

    private func captureRuntimeStatusMessage(
        for note: MeetingNote,
        event: CaptureRuntimeEvent
    ) -> String {
        switch event.kind {
        case .failed:
            if note.processingState.isActive || note.transcriptionStatus == .pending {
                return "\(event.message) Oatmeal is salvaging the saved local artifact in the background."
            }
            return event.message
        case .degraded, .recovered:
            return event.message
        }
    }

    private func salvageInterruptedCaptureIfPossible(for note: inout MeetingNote, at date: Date) {
        guard let recordingURL = captureEngine.recordingURL(for: note.id) else {
            return
        }

        guard note.transcriptionStatus == .idle, !note.processingState.isActive else {
            return
        }

        note.queueTranscription(at: date)
        persist(note)

        enqueuePostCaptureProcessing(
            PostCaptureProcessingRequest(
                noteID: note.id,
                recordingURL: recordingURL,
                captureStartedAt: note.captureState.startedAt,
                processingAnchorDate: date,
                trigger: .interruptedCapture
            )
        )
    }

    private func appendLiveRuntimeMessageIfNeeded(
        _ message: String,
        to note: inout MeetingNote,
        at date: Date
    ) {
        if note.liveSessionState.previewEntries.last?.kind == .system,
           note.liveSessionState.previewEntries.last?.text == message {
            return
        }

        note.appendLiveTranscriptEntry(
            LiveTranscriptEntry(
                createdAt: date,
                kind: .system,
                text: message
            ),
            updatedAt: date
        )
    }

    private func noteNeedsPostCaptureRecovery(_ note: MeetingNote) -> Bool {
        guard note.captureState.phase == .complete || note.captureState.phase == .failed else {
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
        let liveChunkCatchUpCount = await catchUpPersistedLiveTranscriptionChunks(for: &note)
        if liveChunkCatchUpCount > 0 {
            statusMessages.append("Oatmeal caught up \(liveChunkCatchUpCount) delayed live transcript chunk\(liveChunkCatchUpCount == 1 ? "" : "s") from the saved local artifacts.")
        }

        note = store.note(id: request.noteID) ?? note
        let recoveredLiveSegments = recoveredLiveTranscriptSegments(from: note)

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
                if !recoveredLiveSegments.isEmpty {
                    statusMessages.append("Oatmeal is reconciling the near-live transcript with the saved recording.")
                }

                do {
                    guard let recordingURL = request.recordingURL else {
                        throw PostCaptureProcessingError.missingRecordingArtifact(request.noteID)
                    }

                    _ = try? audioRetentionCoordinator.prepareNormalizedDirectory()
                    let normalizedOutputURL = audioRetentionCoordinator
                        .paths(for: request.noteID)
                        .normalizedWAVURL

                    let result = try await transcriptionService.transcribe(
                        request: TranscriptionRequest(
                            audioFileURL: recordingURL,
                            startedAt: request.captureStartedAt ?? request.processingAnchorDate,
                            preferredLocaleIdentifier: transcriptionConfiguration.preferredLocaleIdentifier,
                            normalizedOutputURL: normalizedOutputURL
                        ),
                        configuration: transcriptionConfiguration
                    )

                    note.applyTranscript(
                        result.segments,
                        backend: result.backend,
                        executionKind: result.executionKind,
                        warnings: result.warningMessages,
                        language: result.detectedLanguage,
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

                    let recoveredAt = nowProvider()
                    if applyRecoveredLiveTranscriptIfAvailable(
                        to: &note,
                        segments: recoveredLiveSegments,
                        backend: fallbackPlan.0,
                        warningMessages: fallbackPlan.2,
                        at: recoveredAt
                    ) {
                        statusMessages.append("Full recording transcription failed, but Oatmeal kept the recovered near-live transcript and continued processing.")
                        persist(note)
                    } else {
                        note.recordTranscriptionFailure(
                            backend: fallbackPlan.0,
                            executionKind: fallbackPlan.1,
                            message: error.localizedDescription,
                            warnings: fallbackPlan.2,
                            at: recoveredAt
                        )
                        statusMessages.append("Recording saved locally, but transcription failed: \(error.localizedDescription)")
                        persist(note)
                    }
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

            do {
                let plan = try await summaryService.executionPlan(configuration: summaryConfiguration)
                summaryExecutionPlansByNoteID[note.id] = plan

                if note.generationStatus != .pending {
                    note.beginGeneration(templateID: template.id, at: nowProvider())
                    persist(note)
                }

                let result = try await summaryService.generate(
                    request: template.makeGenerationRequest(for: note),
                    configuration: summaryConfiguration
                )
                note.applyEnhancedNote(result.enhancedNote, at: nowProvider())
                statusMessages.append(contentsOf: plan.warningMessages)
                statusMessages.append(contentsOf: result.warningMessages)
            } catch {
                summaryExecutionPlansByNoteID[note.id] = nil
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
            case .interruptedCapture:
                statusMessages.insert("Capture ended unexpectedly, but Oatmeal resumed note processing from the saved local artifact.", at: 0)
            case .relaunchRecovery:
                statusMessages.insert("Oatmeal resumed unfinished processing from the previous launch.", at: 0)
            case .manualTranscriptionRetry:
                statusMessages.insert("Transcription retry finished.", at: 0)
            case .manualGenerationRetry:
                statusMessages.insert("Enhanced note retry finished.", at: 0)
            case .immediateAfterCapture:
                break
            }
            capturePermissionMessage = buildStatusMessage(from: statusMessages)
        }
    }

    private func pendingLiveChunks(for note: MeetingNote) -> [LiveTranscriptionChunk] {
        captureEngine.liveTranscriptionChunks(for: note.id)
            .filter { !note.liveSessionState.hasProcessedChunkID($0.id) }
            .sorted {
                if $0.startedAt == $1.startedAt {
                    return $0.id < $1.id
                }
                return $0.startedAt < $1.startedAt
            }
    }

    @discardableResult
    private func refreshLiveSessionMetrics(
        for note: inout MeetingNote,
        pendingChunks: [LiveTranscriptionChunk],
        updatedAt: Date
    ) -> Bool {
        var didChange = false

        if let snapshot = captureEngine.runtimeHealthSnapshot(for: note.id) {
            if let microphoneLastActivityAt = snapshot.microphoneLastActivityAt {
                didChange = note.recordLiveCaptureSourceActivity(
                    .microphone,
                    updatedAt: microphoneLastActivityAt
                ) || didChange
            }

            if let systemAudioLastActivityAt = snapshot.systemAudioLastActivityAt {
                didChange = note.recordLiveCaptureSourceActivity(
                    .systemAudio,
                    updatedAt: systemAudioLastActivityAt
                ) || didChange
            }
        }

        didChange = note.updateLiveChunkBacklog(
            pendingChunkCount: pendingChunks.count,
            oldestPendingChunkStartedAt: pendingChunks.first?.startedAt,
            updatedAt: updatedAt
        ) || didChange

        return didChange
    }

    private func catchUpPersistedLiveTranscriptionChunks(for note: inout MeetingNote) async -> Int {
        guard note.captureState.phase == .complete || note.captureState.phase == .failed else {
            return 0
        }

        let pendingChunks = pendingLiveChunks(for: note)
        guard !pendingChunks.isEmpty else {
            let metricsRefreshed = refreshLiveSessionMetrics(
                for: &note,
                pendingChunks: [],
                updatedAt: nowProvider()
            )
            if metricsRefreshed {
                persist(note)
            }
            return 0
        }

        var processedChunkCount = 0

        for (index, chunk) in pendingChunks.enumerated() {
            let queuedBehindCurrentChunk = Array(pendingChunks.suffix(from: index + 1))
            let queuedMetricsChanged = refreshLiveSessionMetrics(
                for: &note,
                pendingChunks: queuedBehindCurrentChunk,
                updatedAt: nowProvider()
            )
            if queuedMetricsChanged {
                persist(note)
                note = store.note(id: note.id) ?? note
            }

            do {
                let result = try await transcriptionService.transcribe(
                    request: TranscriptionRequest(
                        audioFileURL: chunk.fileURL,
                        startedAt: chunk.startedAt,
                        preferredLocaleIdentifier: transcriptionConfiguration.preferredLocaleIdentifier
                    ),
                    configuration: transcriptionConfiguration
                )

                let updatedAt = nowProvider()
                let previewEntries = result.segments.map { segment in
                    LiveTranscriptEntry(
                        createdAt: segment.startTime ?? chunk.startedAt,
                        kind: .transcript,
                        speakerName: segment.speakerName ?? chunk.source.defaultSpeakerName,
                        text: segment.text
                    )
                }

                for entry in previewEntries {
                    note.appendLiveTranscriptEntry(entry, updatedAt: updatedAt)
                }

                note.registerProcessedLiveChunkID(chunk.id, updatedAt: updatedAt)
                note.recordMergedLiveChunk(updatedAt: updatedAt, sourceEndedAt: chunk.endedAt)
                _ = refreshLiveSessionMetrics(
                    for: &note,
                    pendingChunks: pendingLiveChunks(for: note),
                    updatedAt: updatedAt
                )
                processedChunkCount += 1
                persist(note)
            } catch {
                _ = refreshLiveSessionMetrics(
                    for: &note,
                    pendingChunks: pendingLiveChunks(for: note),
                    updatedAt: nowProvider()
                )
                note.markLiveSessionDelayed(
                    message: "Oatmeal kept the recording safe. It will keep retrying delayed live chunks while the full note finishes processing.",
                    at: nowProvider()
                )
                persist(note)
                return processedChunkCount
            }
        }

        if processedChunkCount > 0, note.captureState.phase == .complete {
            note.completeLiveSession(
                message: "Oatmeal finished catching up delayed live transcript chunks from the saved local artifacts.",
                at: nowProvider()
            )
            persist(note)
        }

        return processedChunkCount
    }

    private func persist(_ note: MeetingNote) {
        store.save(note)
        refresh()
        if selectedNoteID == nil || selectedNoteID == note.id {
            selectedNoteID = note.id
        }
        persistState()
    }

    private func canDelete(note: MeetingNote) -> Bool {
        switch note.captureState.phase {
        case .capturing, .paused:
            return false
        case .ready, .complete, .failed:
            return true
        }
    }

    private func cleanupRecordingArtifactIfEligible(for note: MeetingNote, statusMessages: inout [String]) {
        guard note.captureState.phase == .complete else {
            return
        }

        guard note.transcriptionStatus == .succeeded, note.generationStatus == .succeeded else {
            return
        }

        if note.transcriptionHistory.last?.warningMessages.contains(recoveredLiveTranscriptWarning) == true {
            statusMessages.append("Oatmeal kept the local recording because the note is using a recovered near-live transcript.")
            return
        }

        guard recordingURL(for: note) != nil else {
            return
        }

        do {
            try audioRetentionCoordinator.apply(.normalizationSucceeded(noteID: note.id))
            statusMessages.append("Original recording was cleaned up after successful processing. A normalized copy was retained for re-transcribe.")
        } catch {
            statusMessages.append("Processing succeeded, but Oatmeal could not clean up the saved recording: \(error.localizedDescription)")
        }
    }

    private func recoveredLiveTranscriptSegments(from note: MeetingNote) -> [TranscriptSegment] {
        note.liveSessionState.previewEntries
            .filter { $0.kind == .transcript }
            .map { entry in
                TranscriptSegment(
                    startTime: entry.createdAt,
                    endTime: entry.createdAt,
                    speakerName: entry.speakerName,
                    text: entry.text
                )
            }
    }

    private func applyRecoveredLiveTranscriptIfAvailable(
        to note: inout MeetingNote,
        segments: [TranscriptSegment],
        backend: NoteTranscriptionBackend,
        warningMessages: [String],
        at updatedAt: Date
    ) -> Bool {
        guard !segments.isEmpty else {
            return false
        }

        var warnings = warningMessages
        if !warnings.contains(recoveredLiveTranscriptWarning) {
            warnings.append(recoveredLiveTranscriptWarning)
        }

        note.applyTranscript(
            segments,
            backend: backend,
            executionKind: .placeholder,
            warnings: warnings,
            at: updatedAt
        )
        return true
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

struct SummaryModelOperationState: Equatable {
    enum Kind: Equatable {
        case downloading
        case updating
        case removing

        var verb: String {
            switch self {
            case .downloading:
                "Downloading"
            case .updating:
                "Updating"
            case .removing:
                "Removing"
            }
        }
    }

    var kind: Kind
    var modelDisplayName: String

    var message: String {
        "\(kind.verb) \(modelDisplayName)…"
    }
}

private extension String {
    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}

private extension NoteAssistantTurnKind {
    var assistantRecipePrompt: String? {
        switch self {
        case .prompt:
            return nil
        case .followUpEmail:
            return "Draft a follow-up email"
        case .slackRecap:
            return "Draft a Slack recap"
        case .actionItems:
            return "Extract action items"
        case .decisionsAndRisks:
            return "Extract decisions and risks"
        }
    }
}
