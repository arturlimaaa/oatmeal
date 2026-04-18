import OatmealCore
import OatmealEdge
import SwiftUI

struct OatmealRootView: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var didEvaluateLaunchSessionController = false

    private var coordinator: SessionControllerSceneCoordinator {
        SessionControllerSceneCoordinator(
            openWindow: { id in openWindow(id: id) },
            dismissWindow: { id in dismissWindow(id: id) }
        )
    }

    private var router: SessionControllerCommandRouter {
        SessionControllerCommandRouter(model: model, coordinator: coordinator)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
        .searchable(text: searchTextBinding, placement: .toolbar)
        .task {
            await model.loadSystemState()
            model.selectFirstUpcomingMeetingIfNeeded()
            guard !didEvaluateLaunchSessionController else {
                return
            }
            didEvaluateLaunchSessionController = true
            router.presentSessionControllerOnLaunchIfNeeded()
        }
        .onChange(of: model.selectedSidebarItem) { _, newValue in
            switch newValue {
            case .upcoming:
                model.selectFirstUpcomingMeetingIfNeeded()
            case .templates:
                model.setSelectedTemplateID(model.templates.first?.id)
            default:
                model.selectFirstAvailableNote()
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.startQuickNote()
                } label: {
                    Label("Quick Note", systemImage: "square.and.pencil")
                }

                Button {
                    Task {
                        await model.toggleCapture()
                        router.syncSessionControllerWindow()
                    }
                } label: {
                    Label(captureButtonTitle, systemImage: captureButtonImage)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedSidebarItem == .templates || model.selectedSidebarItem == .upcoming || model.selectedNote == nil || model.isPreparingCapture)
            }
        }
    }

    private var sidebar: some View {
        List(selection: selectedSidebarItemBinding) {
            Section("Workspace") {
                Label("Upcoming", systemImage: "calendar")
                    .tag(SidebarItem.upcoming)

                Label("All Notes", systemImage: "note.text")
                    .tag(SidebarItem.allNotes)

                Label("Templates", systemImage: "square.and.pencil")
                    .tag(SidebarItem.templates)
            }

            Section("Folders") {
                ForEach(model.folders) { folder in
                    FolderLabel(folder: folder)
                        .tag(SidebarItem.folder(folder.id))
                }
            }
        }
        .navigationTitle("Oatmeal")
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch model.selectedSidebarItem {
        case .upcoming:
            upcomingList
        case .templates:
            templateList
        default:
            noteList
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        switch model.selectedSidebarItem {
        case .upcoming:
            if model.calendarAccessStatus != .granted {
                CalendarPermissionView(
                    status: model.calendarAccessStatus,
                    isLoading: model.isLoadingUpcomingMeetings
                ) {
                    await model.requestCalendarAccess()
                }
            } else if let event = model.selectedUpcomingEvent {
                UpcomingEventDetailView(
                    event: event,
                    existingNote: model.note(for: event)
                ) {
                    model.startNote(for: event)
                }
            } else if let upcomingMeetingsError = model.upcomingMeetingsError {
                ContentUnavailableView(
                    "Unable to Load Meetings",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text(upcomingMeetingsError)
                )
            } else {
                ContentUnavailableView(
                    "No Upcoming Meetings",
                    systemImage: "calendar",
                    description: Text("Your next seven days are clear, or the connected calendars do not have any relevant meetings.")
                )
            }
        case .templates:
            if let template = model.selectedTemplate {
                TemplateDetailView(template: template)
            } else {
                ContentUnavailableView(
                    "Select a Template",
                    systemImage: "square.and.pencil",
                    description: Text("Choose a built-in or custom template to inspect its structure.")
                )
            }
        default:
            if let note = model.selectedNote {
                MeetingDetailView(
                    note: note,
                    folder: model.folder(for: note),
                    template: model.selectedTemplate,
                    capturePermissions: model.capturePermissions,
                    isPreparingCapture: model.isPreparingCapture,
                    capturePermissionMessage: model.capturePermissionMessage,
                    recordingURL: model.recordingURL(for: note),
                    transcriptionConfiguration: model.transcriptionConfiguration,
                    transcriptionPlanSummary: model.transcriptionRuntimeState?.activePlanSummary,
                    summaryConfiguration: model.summaryConfiguration,
                    summaryPlanSummary: model.summaryPlanSummary(for: note),
                    summaryExecutionPlan: model.summaryExecutionPlan(for: note),
                    isLiveTranscriptPanelPresented: note.liveSessionState.isTranscriptPanelPresented,
                    canRetryTranscription: model.canRetryTranscription(for: note),
                    canRetryGeneration: model.canRetryGeneration(for: note),
                    setLiveTranscriptPanelPresented: { model.setLiveTranscriptPanelPresented($0, for: note.id) },
                    retryTranscription: { model.retryTranscription() },
                    retryGeneration: { model.retryGeneration() }
                )
            } else {
                ContentUnavailableView(
                    "Select a Note",
                    systemImage: "note.text",
                    description: Text("Choose a meeting or start a Quick Note to begin.")
                )
            }
        }
    }

    private var upcomingList: some View {
        List(model.filteredUpcomingMeetings, selection: selectedUpcomingEventIDBinding) { event in
            UpcomingMeetingRow(event: event, existingNote: model.note(for: event))
                .tag(event.id)
        }
        .navigationTitle("Upcoming Meetings")
        .overlay {
            if model.calendarAccessStatus != .granted {
                ContentUnavailableView(
                    "Calendar Access Needed",
                    systemImage: "calendar.badge.plus",
                    description: Text("Grant calendar access to see real meetings from your Mac.")
                )
            } else if model.isLoadingUpcomingMeetings {
                ProgressView("Loading meetings…")
            } else if model.filteredUpcomingMeetings.isEmpty {
                ContentUnavailableView(
                    "No Upcoming Meetings",
                    systemImage: "calendar",
                    description: Text("Nothing in the next seven days matches the current filter.")
                )
            }
        }
    }

    private var noteList: some View {
        List(model.filteredNotes, selection: selectedNoteIDBinding) { note in
            NoteRow(note: note, folder: model.folder(for: note))
                .tag(note.id)
        }
        .navigationTitle(listTitle)
        .overlay {
            if model.filteredNotes.isEmpty {
                ContentUnavailableView(
                    "No Notes",
                    systemImage: "tray",
                    description: Text("Nothing matches the current filter yet.")
                )
            }
        }
    }

    private var templateList: some View {
        List(model.templates, selection: selectedTemplateIDBinding) { template in
            Button {
                model.setSelectedTemplate(template)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(template.name)
                            .font(.headline)
                        if template.isDefault {
                            Text("Default")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.blue.opacity(0.12), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                    }

                    Text(template.description)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .tag(template.id)
        }
        .navigationTitle("Templates")
    }

    private var listTitle: String {
        switch model.selectedSidebarItem {
        case .upcoming:
            "Upcoming Meetings"
        case .allNotes:
            "All Notes"
        case .templates:
            "Templates"
        case let .folder(folderID):
            model.folders.first(where: { $0.id == folderID })?.name ?? "Folder"
        }
    }

    private var captureButtonTitle: String {
        guard let note = model.selectedNote else {
            return "Start Capture"
        }

        return switch note.captureState.phase {
        case .capturing, .paused:
            "Stop Capture"
        case .failed:
            "Resume Capture"
        case .ready, .complete:
            "Start Capture"
        }
    }

    private var captureButtonImage: String {
        switch model.selectedNote?.captureState.phase {
        case .capturing, .paused:
            "stop.fill"
        case .failed:
            "arrow.clockwise"
        default:
            "waveform"
        }
    }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { model.searchText },
            set: { model.searchText = $0 }
        )
    }

    private var selectedSidebarItemBinding: Binding<SidebarItem?> {
        Binding(
            get: { model.selectedSidebarItem },
            set: { model.setSelectedSidebarItem($0 ?? .allNotes) }
        )
    }

    private var selectedUpcomingEventIDBinding: Binding<CalendarEvent.ID?> {
        Binding(
            get: { model.selectedUpcomingEventID },
            set: { model.setSelectedUpcomingEventID($0) }
        )
    }

    private var selectedNoteIDBinding: Binding<MeetingNote.ID?> {
        Binding(
            get: { model.selectedNoteID },
            set: { model.setSelectedNoteID($0) }
        )
    }

    private var selectedTemplateIDBinding: Binding<NoteTemplate.ID?> {
        Binding(
            get: { model.selectedTemplateID },
            set: { model.setSelectedTemplateID($0) }
        )
    }
}

private struct NoteRow: View {
    let note: MeetingNote
    let folder: NoteFolder?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(note.title)
                    .font(.headline)

                Spacer()

                Text(noteDisplayStatus)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.14), in: Capsule())
                    .foregroundStyle(statusColor)
            }

            Text(note.enhancedNote?.summary ?? note.rawNotes.nilIfBlank ?? "Ready to capture notes")
                .lineLimit(2)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Text(note.calendarEvent.map(eventLabel) ?? note.createdAt.formatted(date: .abbreviated, time: .shortened))

                if let folder {
                    Text(folder.name)
                }

                let attendees = note.calendarEvent?.attendees.map(\.name).joined(separator: ", ")
                if let attendees, !attendees.isEmpty {
                    Text(attendees)
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var noteDisplayStatus: String {
        switch note.captureState.phase {
        case .capturing:
            "Capturing"
        case .paused:
            "Paused"
        case .failed:
            "Failed"
        case .complete:
            switch (note.processingState.stage, note.processingState.status) {
            case (.transcription, .queued), (.transcription, .running):
                "Transcribing"
            case (.generation, .queued), (.generation, .running):
                "Generating"
            case (.transcription, .failed):
                "Transcript Failed"
            case (.generation, .failed):
                "Note Failed"
            case (.complete, .completed):
                "Ready"
            default:
                switch note.transcriptionStatus {
                case .failed:
                    "Transcript Failed"
                case .pending:
                    "Transcribing"
                case .succeeded where note.generationStatus == .pending:
                    "Generating"
                case .succeeded where note.generationStatus == .succeeded:
                    "Ready"
                default:
                    "Complete"
                }
            }
        case .ready:
            "Ready"
        }
    }

    private var statusColor: Color {
        switch note.captureState.phase {
        case .capturing:
            .red
        case .paused:
            .orange
        case .failed:
            .pink
        case .complete:
            switch note.processingState.status {
            case .queued, .running:
                .orange
            case .failed:
                .pink
            case .completed:
                .green
            case .idle:
                if note.generationStatus == .succeeded {
                    .green
                } else {
                    .secondary
                }
            }
        case .ready:
            .secondary
        }
    }

    private func eventLabel(_ event: CalendarEvent) -> String {
        event.startDate.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct UpcomingMeetingRow: View {
    let event: CalendarEvent
    let existingNote: MeetingNote?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(event.title)
                    .font(.headline)

                Spacer()

                if existingNote != nil {
                    Text("Note Ready")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.green.opacity(0.14), in: Capsule())
                        .foregroundStyle(.green)
                }
            }

            HStack(spacing: 10) {
                Text(event.startDate.formatted(date: .abbreviated, time: .shortened))
                if let location = event.location?.nilIfBlank {
                    Text(location)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !event.attendees.isEmpty {
                Text(event.attendees.map(\.name).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CalendarPermissionView: View {
    let status: PermissionStatus
    let isLoading: Bool
    let requestAccess: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Connect Your Calendar")
                .font(.system(size: 30, weight: .semibold, design: .rounded))

            Text(description)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 620, alignment: .leading)

            Button {
                Task {
                    await requestAccess()
                }
            } label: {
                if isLoading {
                    ProgressView()
                } else {
                    Label(buttonTitle, systemImage: "calendar.badge.plus")
                }
            }
            .buttonStyle(.borderedProminent)

            if status == .denied || status == .restricted {
                Text("If access was denied previously, re-enable Calendar permissions for Oatmeal in System Settings.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var buttonTitle: String {
        switch status {
        case .notDetermined:
            "Grant Calendar Access"
        case .denied, .restricted:
            "Try Again"
        case .granted:
            "Refresh"
        }
    }

    private var description: String {
        switch status {
        case .notDetermined:
            "Upcoming is now wired for real macOS calendar data. Grant access and Oatmeal will show your next meetings directly from Calendar."
        case .denied:
            "Calendar access was denied. Oatmeal can still work for Quick Notes, but the Upcoming view needs permission to surface meetings."
        case .restricted:
            "Calendar access is restricted on this Mac. Oatmeal can still work for Quick Notes, but it cannot read meetings right now."
        case .granted:
            "Calendar access is enabled."
        }
    }
}

private struct UpcomingEventDetailView: View {
    let event: CalendarEvent
    let existingNote: MeetingNote?
    let openNote: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(event.title)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))

                HStack(spacing: 16) {
                    Label(event.startDate.formatted(date: .complete, time: .shortened), systemImage: "calendar")
                    if let location = event.location?.nilIfBlank {
                        Label(location, systemImage: "mappin.and.ellipse")
                    }
                }
                .foregroundStyle(.secondary)

                DetailCard(title: "Meeting Overview") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("Source", value: event.source.displayLabel)
                        LabeledContent("Type", value: event.kind.displayLabel)
                        if let url = event.conferencingURL {
                            LabeledContent("Call Link", value: url.absoluteString)
                        }
                        if let timezone = event.timezoneIdentifier {
                            LabeledContent("Timezone", value: timezone)
                        }
                    }
                }

                DetailCard(title: "Participants") {
                    if event.attendees.isEmpty {
                        Text("No attendee metadata was available from the calendar entry.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(event.attendees) { attendee in
                                HStack {
                                    Text(attendee.name)
                                    if attendee.isOrganizer {
                                        Text("Organizer")
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(.blue.opacity(0.12), in: Capsule())
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }
                }

                DetailCard(title: existingNote == nil ? "Ready to Start" : "Existing Note") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(existingNote == nil
                             ? "Create a meeting note now to start capture, add agenda bullets, and keep this call ready in your workspace."
                             : "A note already exists for this meeting. Open it to continue editing or start capture.")
                            .foregroundStyle(.secondary)

                        Button(existingNote == nil ? "Open Meeting Note" : "Open Existing Note") {
                            openNote()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct MeetingDetailView: View {
    let note: MeetingNote
    let folder: NoteFolder?
    let template: NoteTemplate?
    let capturePermissions: CapturePermissions
    let isPreparingCapture: Bool
    let capturePermissionMessage: String?
    let recordingURL: URL?
    let transcriptionConfiguration: LocalTranscriptionConfiguration
    let transcriptionPlanSummary: String?
    let summaryConfiguration: LocalSummaryConfiguration
    let summaryPlanSummary: String?
    let summaryExecutionPlan: LocalSummaryExecutionPlan?
    let isLiveTranscriptPanelPresented: Bool
    let canRetryTranscription: Bool
    let canRetryGeneration: Bool
    let setLiveTranscriptPanelPresented: (Bool) -> Void
    let retryTranscription: () -> Void
    let retryGeneration: () -> Void
    @State private var isLiveTranscriptPanelExpanded = false

    private var liveTranscriptPanelState: LiveTranscriptPanelState? {
        LiveTranscriptPanelAdapter.panelState(for: note)
    }

    private var shouldShowLiveTranscriptPanel: Bool {
        isLiveTranscriptPanelExpanded || isLiveTranscriptPanelPresented
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                summaryCards
                metadataSection
                captureSection
                if let liveTranscriptPanelState {
                    if shouldShowLiveTranscriptPanel {
                        liveTranscriptSection(liveTranscriptPanelState)
                    } else {
                        liveTranscriptEntryPointSection(liveTranscriptPanelState)
                    }
                }
                processingSection
                transcriptionSection
                summaryRuntimeSection
                rawNotesSection
                if liveTranscriptPanelState == nil {
                    transcriptSection
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            isLiveTranscriptPanelExpanded = isLiveTranscriptPanelPresented
        }
        .onChange(of: note.id) { _, _ in
            isLiveTranscriptPanelExpanded = note.liveSessionState.isTranscriptPanelPresented
        }
        .onChange(of: isLiveTranscriptPanelPresented) { _, newValue in
            isLiveTranscriptPanelExpanded = newValue
        }
        .onChange(of: isLiveTranscriptPanelExpanded) { _, newValue in
            guard newValue != note.liveSessionState.isTranscriptPanelPresented else {
                return
            }
            setLiveTranscriptPanelPresented(newValue)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(note.title)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))

                    if let event = note.calendarEvent {
                        Text(event.startDate.formatted(date: .complete, time: .shortened))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(note.createdAt.formatted(date: .complete, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    if let folder {
                        FolderLabel(folder: folder)
                    }

                    Label(captureLabel, systemImage: "waveform")
                        .foregroundStyle(statusColor)
                }
            }

            if let attendees = note.calendarEvent?.attendees.map(\.name), !attendees.isEmpty {
                Text("Participants: \(attendees.joined(separator: ", "))")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var summaryCards: some View {
        HStack(alignment: .top, spacing: 16) {
            DetailCard(title: "Enhanced Note") {
                if let enhanced = note.enhancedNote {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(enhanced.summary)
                            .font(.title3.weight(.semibold))

                        ForEach(enhanced.keyDiscussionPoints, id: \.self) { bullet in
                            Label(bullet, systemImage: "circle.fill")
                                .labelStyle(.oatmealBullet)
                        }

                        if !enhanced.decisions.isEmpty {
                            Divider()
                            Text("Decisions")
                                .font(.headline)
                            ForEach(enhanced.decisions, id: \.self) { decision in
                                Label(decision, systemImage: "checkmark.seal.fill")
                                    .labelStyle(.oatmealBullet)
                            }
                        }
                    }
                } else {
                    Text("Stop capture to generate the first enhanced note from the transcript, raw notes, and template context.")
                        .foregroundStyle(.secondary)
                }
            }

            DetailCard(title: "Action Items") {
                let actionItems = note.enhancedNote?.actionItems ?? []
                if actionItems.isEmpty {
                    Text("No action items yet.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(actionItems) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.text)
                                    .font(.headline)
                                Text(item.assignee ?? "Unassigned")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var metadataSection: some View {
        DetailCard(title: "Meeting Context") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Origin", value: note.isQuickNote ? "Quick Note" : "Calendar Event")
                LabeledContent("Template", value: template?.name ?? "Automatic")
                LabeledContent("Sharing", value: note.shareSettings.privacyLevel.displayLabel)
                LabeledContent("Transcript in shared link", value: note.shareSettings.includeTranscript ? "Included" : "Hidden")
                LabeledContent("Pipeline state", value: processingStatusSummary)
                LabeledContent("Transcription status", value: note.transcriptionStatus.displayLabel)
                LabeledContent("Generation status", value: note.generationStatus.displayLabel)
                LabeledContent("Summary runtime", value: summaryExecutionPlan?.backend.displayName ?? summaryConfiguration.preferredBackend.displayName)
            }
        }
    }

    private var captureSection: some View {
        DetailCard(title: "Capture Readiness") {
            VStack(alignment: .leading, spacing: 12) {
                PermissionLine(name: "Microphone", status: capturePermissions.microphone, required: true)
                PermissionLine(name: "System Audio", status: capturePermissions.systemAudio, required: note.calendarEvent != nil)
                PermissionLine(name: "Notifications", status: capturePermissions.notifications, required: false)
                PermissionLine(name: "Calendar", status: capturePermissions.calendar, required: note.calendarEvent != nil)

                if let recordingURL {
                    LabeledContent("Local recording", value: recordingURL.lastPathComponent)
                }

                if isPreparingCapture {
                    ProgressView("Checking permissions…")
                        .padding(.top, 4)
                }

                if let capturePermissionMessage {
                    Text(capturePermissionMessage)
                        .foregroundStyle(.secondary)
                } else if let failureReason = note.captureState.failureReason {
                    Text(failureReason)
                        .foregroundStyle(.secondary)
                } else if note.calendarEvent == nil {
                    Text("Quick Notes record your microphone locally. Scheduled meeting notes use a heavier capture path that also records system audio.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Calendar-backed meetings require both microphone and Screen & System Audio access so Oatmeal can record your side plus call audio into one local artifact.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var transcriptionSection: some View {
        DetailCard(title: "Transcription Runtime") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Preferred backend", value: transcriptionConfiguration.preferredBackend.displayName)
                LabeledContent("Execution policy", value: transcriptionConfiguration.executionPolicy.displayName)

                if let lastAttempt = note.transcriptionHistory.last {
                    LabeledContent("Last backend", value: lastAttempt.backend.displayLabel)
                    LabeledContent("Execution kind", value: lastAttempt.executionKind.displayLabel)

                    if !lastAttempt.warningMessages.isEmpty {
                        Text(lastAttempt.warningMessages.joined(separator: " "))
                            .foregroundStyle(.secondary)
                    }

                    if let errorMessage = lastAttempt.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.secondary)
                    }
                } else if let transcriptionPlanSummary {
                    Text(transcriptionPlanSummary)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No transcription attempts have run for this note yet.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var processingSection: some View {
        DetailCard(title: "Processing") {
            let rows = processingRows

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    ProcessingJobRow(row: row)

                    if index < rows.count - 1 {
                        Divider()
                    }
                }

                Text(processingFootnote)
                    .foregroundStyle(.secondary)

                if canRetryTranscription || canRetryGeneration {
                    Divider()

                    HStack(spacing: 12) {
                        if canRetryTranscription {
                            Button("Retry Transcription") {
                                retryTranscription()
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        if canRetryGeneration {
                            Button("Retry Enhanced Note") {
                                retryGeneration()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private var summaryRuntimeSection: some View {
        DetailCard(title: "Summary Runtime") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Preferred backend", value: summaryConfiguration.preferredBackend.displayName)
                LabeledContent("Execution policy", value: summaryConfiguration.executionPolicy.displayName)

                if let summaryExecutionPlan {
                    LabeledContent("Planned backend", value: summaryExecutionPlan.backend.displayName)
                    LabeledContent("Execution kind", value: summaryExecutionPlan.executionKind.rawValue.capitalized)
                    Text(summaryExecutionPlan.summary)
                        .foregroundStyle(.secondary)

                    if !summaryExecutionPlan.warningMessages.isEmpty {
                        Text(summaryExecutionPlan.warningMessages.joined(separator: " "))
                            .foregroundStyle(.secondary)
                    }
                } else if let summaryPlanSummary {
                    Text(summaryPlanSummary)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No summary runtime plan has been prepared for this note yet.")
                        .foregroundStyle(.secondary)
                }

                if let lastAttempt = note.generationHistory.last {
                    LabeledContent("Last request", value: processingTimestamp(lastAttempt.requestedAt))

                    if let completedAt = lastAttempt.completedAt {
                        LabeledContent("Last completion", value: processingTimestamp(completedAt))
                    }

                    if let errorMessage = lastAttempt.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var rawNotesSection: some View {
        DetailCard(title: "Raw Notes") {
            if note.rawNotes.nilIfBlank == nil {
                Text("No raw notes yet.")
                    .foregroundStyle(.secondary)
            } else {
                TextEditor(text: .constant(note.rawNotes))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 180)
            }
        }
    }

    private func liveTranscriptSection(_ panelState: LiveTranscriptPanelState) -> some View {
        DetailCard(title: "Live Transcript") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    liveTranscriptStatusSummary(panelState)

                    Spacer()

                    Button("Hide Panel") {
                        isLiveTranscriptPanelExpanded = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                DisclosureGroup(isExpanded: $isLiveTranscriptPanelExpanded) {
                    VStack(alignment: .leading, spacing: 14) {
                        if panelState.lines.isEmpty {
                            Text(panelState.placeholderText)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(panelState.lines) { line in
                                VStack(alignment: .leading, spacing: 6) {
                                    if let lineHeader = line.headerText {
                                        Text(lineHeader)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(line.text)
                                }
                                .padding(.bottom, 4)
                            }
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text(panelState.lines.isEmpty ? "Waiting for live updates" : "Live transcript preview")
                        .font(.headline)
                }
            }
        }
    }

    private func liveTranscriptEntryPointSection(_ panelState: LiveTranscriptPanelState) -> some View {
        DetailCard(title: "Live Transcript") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    liveTranscriptStatusSummary(panelState)

                    Spacer()

                    Button("Open Panel") {
                        isLiveTranscriptPanelExpanded = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Text(liveTranscriptEntryPointText(for: panelState))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func liveTranscriptStatusSummary(_ panelState: LiveTranscriptPanelState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                LiveTranscriptStatusBadge(
                    title: "Session Health",
                    value: panelState.healthLabel,
                    color: panelState.healthColor
                )

                LiveTranscriptStatusBadge(
                    title: "Capture",
                    value: panelState.captureLabel,
                    color: captureBadgeColor(for: panelState.captureLabel)
                )

                if panelState.usesPersistedSessionState {
                    LiveTranscriptStatusBadge(
                        title: "Storage",
                        value: "Saved Locally",
                        color: .blue
                    )
                }
            }

            if !panelState.sourceBadges.isEmpty {
                FlexibleBadgeRow(badges: panelState.sourceBadges)
            }

            if !panelState.metricBadges.isEmpty {
                FlexibleBadgeRow(badges: panelState.metricBadges)
            }

            Text(panelState.detailText)
                .foregroundStyle(.secondary)

            if let lastUpdatedText = panelState.lastUpdatedText {
                Text("Last event: \(lastUpdatedText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func captureBadgeColor(for captureLabel: String) -> Color {
        switch captureLabel.lowercased() {
        case "recording":
            .green
        case "paused":
            .orange
        case "interrupted":
            .pink
        default:
            .secondary
        }
    }

    private func liveTranscriptEntryPointText(for panelState: LiveTranscriptPanelState) -> String {
        if let latestLine = panelState.lines.last?.text.nilIfBlank {
            let count = panelState.lines.count
            let noun = count == 1 ? "update" : "updates"
            return "Oatmeal has already staged \(count) live transcript \(noun). Open the panel to inspect the latest chunk: \(latestLine)"
        }

        return panelState.placeholderText
    }

    private var transcriptSection: some View {
        DetailCard(title: "Transcript") {
            if note.transcriptSegments.isEmpty {
                Text(transcriptPlaceholderText)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(note.transcriptSegments) { segment in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(segmentHeader(segment))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(segment.text)
                        }
                        .padding(.bottom, 4)
                    }
                }
            }
        }
    }

    private var captureLabel: String {
        switch note.captureState.phase {
        case .ready:
            "Ready"
        case .capturing:
            "Capturing"
        case .paused:
            "Paused"
        case .failed:
            "Failed"
        case .complete:
            switch (note.processingState.stage, note.processingState.status) {
            case (.transcription, .queued), (.transcription, .running):
                "Transcribing"
            case (.generation, .queued), (.generation, .running):
                "Generating"
            case (.transcription, .failed):
                "Transcript Failed"
            case (.generation, .failed):
                "Note Failed"
            default:
                "Complete"
            }
        }
    }

    private var statusColor: Color {
        switch note.captureState.phase {
        case .capturing:
            .red
        case .paused:
            .orange
        case .failed:
            .pink
        case .complete:
            switch note.processingState.status {
            case .queued, .running:
                .orange
            case .failed:
                .pink
            case .completed:
                .green
            case .idle:
                .green
            }
        case .ready:
            .secondary
        }
    }

    private func segmentHeader(_ segment: TranscriptSegment) -> String {
        let speaker = segment.speakerName ?? "Speaker"
        if let startTime = segment.startTime {
            return "\(speaker) • \(startTime.formatted(date: .omitted, time: .standard))"
        }
        return speaker
    }

    private var transcriptPlaceholderText: String {
        if note.processingState.stage == .transcription, note.processingState.status == .queued {
            return "Transcription is queued for the latest capture."
        }
        if note.processingState.stage == .transcription, note.processingState.status == .running {
            return "Transcription is running for the latest capture."
        }
        if note.captureState.phase == .complete && note.transcriptionStatus == .idle {
            return "Recording saved. Transcription is queued."
        }
        if let errorMessage = note.transcriptionHistory.last?.errorMessage {
            return "Transcription failed for the last capture: \(errorMessage)"
        }
        return "Transcript will appear here when capture begins."
    }

    private var processingStatusSummary: String {
        let stage = note.processingState.stage.rawValue.capitalized
        let status = note.processingState.status.rawValue.capitalized
        return stage == "Idle" && status == "Idle" ? "Idle" : "\(stage) • \(status)"
    }

    private var processingRows: [ProcessingJobRowModel] {
        [
            transcriptionProcessingRow,
            generationProcessingRow
        ]
    }

    private var transcriptionProcessingRow: ProcessingJobRowModel {
        let lastAttempt = note.transcriptionHistory.last
        let transcriptCount = note.transcriptSegments.count
        let transcriptSummary = transcriptCount == 1 ? "1 segment ready" : "\(transcriptCount) segments ready"

        switch note.transcriptionStatus {
        case .pending:
            return ProcessingJobRowModel(
                id: "transcription",
                title: "Transcription",
                detail: lastAttempt.map { "\($0.backend.displayLabel) • \($0.executionKind.displayLabel)" } ?? "Running the latest recording through the selected runtime.",
                secondaryDetail: lastAttempt.map { "Started \(processingTimestamp($0.requestedAt))" },
                state: .running,
                warningMessages: lastAttempt?.warningMessages ?? [],
                errorMessage: lastAttempt?.errorMessage
            )
        case .succeeded:
            return ProcessingJobRowModel(
                id: "transcription",
                title: "Transcription",
                detail: lastAttempt.map { "\($0.backend.displayLabel) • \($0.executionKind.displayLabel)" } ?? "Transcript finished successfully.",
                secondaryDetail: lastAttempt.map { completedAttemptSummary(requestedAt: $0.requestedAt, completedAt: $0.completedAt, resultSummary: $0.segmentCount == 0 ? transcriptSummary : segmentSummary(for: $0.segmentCount)) } ?? transcriptSummary,
                state: .completed,
                warningMessages: lastAttempt?.warningMessages ?? [],
                errorMessage: nil
            )
        case .failed:
            return ProcessingJobRowModel(
                id: "transcription",
                title: "Transcription",
                detail: lastAttempt?.errorMessage ?? "The last transcription attempt failed.",
                secondaryDetail: lastAttempt.map { failureAttemptSummary(requestedAt: $0.requestedAt, completedAt: $0.completedAt) },
                state: .failed,
                warningMessages: lastAttempt?.warningMessages ?? [],
                errorMessage: lastAttempt?.errorMessage
            )
        case .idle:
            if note.processingState.stage == .transcription, note.processingState.status == .queued {
                return ProcessingJobRowModel(
                    id: "transcription",
                    title: "Transcription",
                    detail: transcriptionPlanSummary ?? "Recording saved and queued for transcription.",
                    secondaryDetail: recordingURL.map { "Artifact ready: \($0.lastPathComponent)" },
                    state: .queued,
                    warningMessages: [],
                    errorMessage: nil
                )
            }

            if note.processingState.stage == .transcription, note.processingState.status == .running {
                return ProcessingJobRowModel(
                    id: "transcription",
                    title: "Transcription",
                    detail: "Running the latest recording through the selected runtime.",
                    secondaryDetail: note.processingState.startedAt.map { "Started \(processingTimestamp($0))" },
                    state: .running,
                    warningMessages: [],
                    errorMessage: nil
                )
            }

            if transcriptCount > 0 {
                return ProcessingJobRowModel(
                    id: "transcription",
                    title: "Transcription",
                    detail: lastAttempt.map { "\($0.backend.displayLabel) • \($0.executionKind.displayLabel)" } ?? "Transcript is already attached to this note.",
                    secondaryDetail: lastAttempt.map { completedAttemptSummary(requestedAt: $0.requestedAt, completedAt: $0.completedAt, resultSummary: $0.segmentCount == 0 ? transcriptSummary : segmentSummary(for: $0.segmentCount)) } ?? transcriptSummary,
                    state: .completed,
                    warningMessages: lastAttempt?.warningMessages ?? [],
                    errorMessage: nil
                )
            }

            if note.captureState.phase == .complete {
                return ProcessingJobRowModel(
                    id: "transcription",
                    title: "Transcription",
                    detail: transcriptionPlanSummary ?? "Recording saved and waiting to be transcribed.",
                    secondaryDetail: recordingURL.map { "Artifact ready: \($0.lastPathComponent)" },
                    state: .queued,
                    warningMessages: [],
                    errorMessage: nil
                )
            }

            return ProcessingJobRowModel(
                id: "transcription",
                title: "Transcription",
                detail: "Starts automatically after capture stops.",
                secondaryDetail: nil,
                state: .waiting,
                warningMessages: [],
                errorMessage: nil
            )
        }
    }

    private var generationProcessingRow: ProcessingJobRowModel {
        let lastAttempt = note.generationHistory.last
        let templateSummary = "Template: \(template?.name ?? "Automatic")"
        let runtimeSummary = summaryExecutionPlan.map {
            "\($0.backend.displayName) • \($0.executionKind.rawValue.capitalized)"
        } ?? summaryPlanSummary

        switch note.generationStatus {
        case .pending:
            return ProcessingJobRowModel(
                id: "generation",
                title: "Enhanced Note",
                detail: runtimeSummary ?? "Building the structured note from the transcript, raw notes, and template context.",
                secondaryDetail: lastAttempt.map { "Started \(processingTimestamp($0.requestedAt)) • \(templateSummary)" } ?? templateSummary,
                state: .running,
                warningMessages: summaryExecutionPlan?.warningMessages ?? [],
                errorMessage: lastAttempt?.errorMessage
            )
        case .succeeded:
            return ProcessingJobRowModel(
                id: "generation",
                title: "Enhanced Note",
                detail: note.enhancedNote?.summary.nilIfBlank ?? "Enhanced note generated successfully.",
                secondaryDetail: lastAttempt.map { completedAttemptSummary(requestedAt: $0.requestedAt, completedAt: $0.completedAt, resultSummary: templateSummary) } ?? templateSummary,
                state: .completed,
                warningMessages: [],
                errorMessage: nil
            )
        case .failed:
            return ProcessingJobRowModel(
                id: "generation",
                title: "Enhanced Note",
                detail: lastAttempt?.errorMessage ?? "The last enhanced-note generation attempt failed.",
                secondaryDetail: lastAttempt.map { failureAttemptSummary(requestedAt: $0.requestedAt, completedAt: $0.completedAt) },
                state: .failed,
                warningMessages: [],
                errorMessage: lastAttempt?.errorMessage
            )
        case .idle:
            if note.processingState.stage == .generation, note.processingState.status == .queued {
                return ProcessingJobRowModel(
                    id: "generation",
                    title: "Enhanced Note",
                    detail: runtimeSummary ?? "Enhanced note generation is queued next.",
                    secondaryDetail: templateSummary,
                    state: .queued,
                    warningMessages: summaryExecutionPlan?.warningMessages ?? [],
                    errorMessage: nil
                )
            }

            if note.processingState.stage == .generation, note.processingState.status == .running {
                return ProcessingJobRowModel(
                    id: "generation",
                    title: "Enhanced Note",
                    detail: runtimeSummary ?? "Building the structured note from the transcript, raw notes, and template context.",
                    secondaryDetail: note.processingState.startedAt.map { "Started \(processingTimestamp($0)) • \(templateSummary)" } ?? templateSummary,
                    state: .running,
                    warningMessages: summaryExecutionPlan?.warningMessages ?? [],
                    errorMessage: nil
                )
            }

            if note.enhancedNote != nil {
                return ProcessingJobRowModel(
                    id: "generation",
                    title: "Enhanced Note",
                    detail: note.enhancedNote?.summary.nilIfBlank ?? "Enhanced note is ready.",
                    secondaryDetail: lastAttempt.map { completedAttemptSummary(requestedAt: $0.requestedAt, completedAt: $0.completedAt, resultSummary: templateSummary) } ?? templateSummary,
                    state: .completed,
                    warningMessages: [],
                    errorMessage: nil
                )
            }

            if note.transcriptionStatus == .succeeded || !note.transcriptSegments.isEmpty {
                return ProcessingJobRowModel(
                    id: "generation",
                    title: "Enhanced Note",
                    detail: runtimeSummary ?? "Transcript is ready. Enhanced note generation is queued next.",
                    secondaryDetail: templateSummary,
                    state: .queued,
                    warningMessages: summaryExecutionPlan?.warningMessages ?? [],
                    errorMessage: nil
                )
            }

            if note.transcriptionStatus == .pending {
                return ProcessingJobRowModel(
                    id: "generation",
                    title: "Enhanced Note",
                    detail: "Waiting for transcription to finish before generating the note.",
                    secondaryDetail: templateSummary,
                    state: .queued,
                    warningMessages: [],
                    errorMessage: nil
                )
            }

            if note.transcriptionStatus == .failed {
                return ProcessingJobRowModel(
                    id: "generation",
                    title: "Enhanced Note",
                    detail: "Blocked until transcription succeeds.",
                    secondaryDetail: templateSummary,
                    state: .waiting,
                    warningMessages: [],
                    errorMessage: nil
                )
            }

            return ProcessingJobRowModel(
                id: "generation",
                title: "Enhanced Note",
                detail: "Runs after the transcript is ready.",
                secondaryDetail: templateSummary,
                state: .waiting,
                warningMessages: [],
                errorMessage: nil
            )
        }
    }

    private var processingFootnote: String {
        if note.processingState.status == .failed || note.generationStatus == .failed || note.transcriptionStatus == .failed {
            return "Failed jobs keep the local artifact and note context intact so you can retry without losing the capture."
        }
        if note.processingState.isActive || note.generationStatus == .pending || note.transcriptionStatus == .pending {
            return "Oatmeal processes capture in stages so transcript and note generation can continue after recording stops."
        }
        if note.captureState.phase == .complete {
            return "Post-capture work runs in sequence: transcription first, then enhanced note generation."
        }
        return "Post-capture jobs begin once recording ends."
    }

    private func completedAttemptSummary(requestedAt: Date, completedAt: Date?, resultSummary: String) -> String {
        if let completedAt {
            return "Completed \(processingTimestamp(completedAt)) • \(resultSummary)"
        }
        return "Started \(processingTimestamp(requestedAt)) • \(resultSummary)"
    }

    private func failureAttemptSummary(requestedAt: Date, completedAt: Date?) -> String {
        if let completedAt {
            return "Failed \(processingTimestamp(completedAt))"
        }
        return "Started \(processingTimestamp(requestedAt))"
    }

    private func processingTimestamp(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func segmentSummary(for count: Int) -> String {
        count == 1 ? "1 segment ready" : "\(count) segments ready"
    }
}

struct LiveTranscriptPanelState: Equatable, Sendable {
    enum HealthTone: Equatable, Sendable {
        case live
        case delayed
        case recovered
        case failed
    }

    struct Line: Equatable, Sendable, Identifiable {
        let id: String
        let kind: LiveTranscriptEntryKind
        let speakerName: String?
        let timestampText: String?
        let text: String

        var headerText: String? {
            let source = kind == .system ? "Oatmeal" : speakerName?.nilIfBlank
            let parts = [source, timestampText?.nilIfBlank].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " • ")
        }
    }

    struct SourceBadge: Equatable, Sendable, Identifiable {
        let id: String
        let title: String
        let value: String
        let detailText: String?
        let tone: HealthTone
    }

    let healthLabel: String
    let captureLabel: String
    let healthTone: HealthTone
    let detailText: String
    let placeholderText: String
    let lines: [Line]
    let sourceBadges: [SourceBadge]
    let metricBadges: [SourceBadge]
    let usesPersistedSessionState: Bool
    let isPresented: Bool
    let showsPersistenceBadge: Bool
    let lastUpdatedText: String?

    var healthColor: Color {
        switch healthTone {
        case .live:
            .green
        case .delayed:
            .orange
        case .recovered:
            .blue
        case .failed:
            .pink
        }
    }
}

private struct FlexibleBadgeRow: View {
    let badges: [LiveTranscriptPanelState.SourceBadge]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(badges) { badge in
                HStack(spacing: 8) {
                    LiveTranscriptStatusBadge(
                        title: badge.title,
                        value: badge.value,
                        color: color(for: badge.tone)
                    )

                    if let detailText = badge.detailText?.nilIfBlank {
                        Text(detailText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    private func color(for tone: LiveTranscriptPanelState.HealthTone) -> Color {
        switch tone {
        case .live:
            .green
        case .delayed:
            .orange
        case .recovered:
            .blue
        case .failed:
            .pink
        }
    }
}

enum LiveTranscriptPanelAdapter {
    static func panelState(for note: MeetingNote) -> LiveTranscriptPanelState? {
        let liveSessionState = note.liveSessionState
        let shouldExposePanel = note.captureState.isActive
            || liveSessionState.isTranscriptPanelPresented
            || liveSessionStatusesThatExposePanel.contains(liveSessionState.status)
        guard shouldExposePanel else {
            return nil
        }

        return LiveTranscriptPanelState(
            healthLabel: liveSessionState.status.displayLabel,
            captureLabel: captureLabel(for: note.captureState),
            healthTone: tone(for: liveSessionState.status),
            detailText: liveSessionState.statusMessage?.nilIfBlank ?? fallbackDetailText(for: liveSessionState),
            placeholderText: fallbackPlaceholderText(for: liveSessionState),
            lines: liveSessionState.previewEntries.map(line(from:)),
            sourceBadges: sourceBadges(for: note),
            metricBadges: metricBadges(for: note),
            usesPersistedSessionState: true,
            isPresented: liveSessionState.isTranscriptPanelPresented,
            showsPersistenceBadge: liveSessionState.status != .idle,
            lastUpdatedText: liveSessionState.lastUpdatedAt?.formatted(date: .omitted, time: .shortened)
        )
    }

    static func reflectedSession(from value: Any) -> ReflectedLiveSessionState? {
        let mirror = Mirror(reflecting: value)
        let candidateLabels = [
            "liveSessionState",
            "liveSession",
            "activeLiveSession",
            "persistedLiveSessionState"
        ]

        for label in candidateLabels {
            if let candidate = mirror.descendant(label),
               let snapshot = makeReflectedSession(from: candidate) {
                return snapshot
            }
        }

        let typeName = normalize(label: String(describing: mirror.subjectType))
        guard typeName.contains("livesession") else {
            return nil
        }

        return makeReflectedSession(from: value)
    }

    private static func makeReflectedSession(from value: Any) -> ReflectedLiveSessionState? {
        let lines = reflectedLines(in: value)
        let healthLabel = reflectedHealthLabel(in: value)
        let detailText = reflectedString(
            in: value,
            labels: ["detailText", "statusDetail", "statusMessage", "summary", "panelSummary", "recoverySummary", "detail"]
        )
        let isRecovered = reflectedBool(
            in: value,
            labels: ["isRecovered", "recoveredAfterRelaunch", "didRecover"]
        ) ?? false
        let isDelayed = reflectedBool(
            in: value,
            labels: ["isDelayed", "isCatchingUp", "isLaggingBehind", "hasBacklog"]
        ) ?? false
        let isActive = reflectedBool(
            in: value,
            labels: ["isActive", "isRunning", "captureIsActive", "isCapturing"]
        ) ?? reflectedRawValue(
            in: value,
            labels: ["phase", "status", "state"]
        ).map { activeStateLabels.contains(normalize(label: $0)) } ?? false

        let resolvedHealthLabel = healthLabel
            ?? {
                if isRecovered {
                    return "Recovered"
                }
                if isDelayed {
                    return "Delayed"
                }
                if isActive || !lines.isEmpty {
                    return "Live"
                }
                return nil
            }()

        guard resolvedHealthLabel != nil || !lines.isEmpty || detailText != nil else {
            return nil
        }

        return ReflectedLiveSessionState(
            healthLabel: resolvedHealthLabel ?? "Live",
            detailText: detailText,
            placeholderText: reflectedString(
                in: value,
                labels: ["placeholderText", "emptyTranscriptMessage", "emptyStateMessage"]
            ),
            lines: lines
        )
    }

    private static func reflectedHealthLabel(in value: Any) -> String? {
        if let label = reflectedString(
            in: value,
            labels: ["healthLabel", "displayLabel", "sessionHealthLabel", "statusLabel"]
        ) {
            return titleCaseHealthLabel(label)
        }

        if let rawValue = reflectedRawValue(
            in: value,
            labels: ["health", "sessionHealth", "liveHealth", "status", "state"]
        ) {
            return titleCaseHealthLabel(rawValue)
        }

        return nil
    }

    private static func reflectedLines(in value: Any) -> [LiveTranscriptPanelState.Line] {
        let collectionLabels = [
            "transcriptSegments",
            "segments",
            "incrementalSegments",
            "entries",
            "previewEntries",
            "transcriptEntries",
            "transcriptLines",
            "mergedTranscriptSegments"
        ]

        for label in collectionLabels {
            if let candidate = Mirror(reflecting: value).descendant(label) {
                let lines = makeLines(fromCollection: candidate)
                if !lines.isEmpty {
                    return lines
                }
            }
        }

        return []
    }

    private static func makeLines(fromCollection value: Any) -> [LiveTranscriptPanelState.Line] {
        if let entries = value as? [LiveTranscriptEntry] {
            return entries.map(line(from:))
        }

        if let segments = value as? [TranscriptSegment] {
            return segments.map(line(from:))
        }

        if let entries = value as? [String] {
            return entries.enumerated().compactMap { index, entry -> LiveTranscriptPanelState.Line? in
                let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    return nil
                }
                return LiveTranscriptPanelState.Line(
                    id: "string-\(index)",
                    kind: .transcript,
                    speakerName: nil,
                    timestampText: nil,
                    text: trimmed
                )
            }
        }

        return Mirror(reflecting: value).children.enumerated().compactMap { index, child in
            line(from: child.value, fallbackID: "reflected-\(index)")
        }
    }

    private static func line(from entry: LiveTranscriptEntry) -> LiveTranscriptPanelState.Line {
        LiveTranscriptPanelState.Line(
            id: entry.id.uuidString,
            kind: entry.kind,
            speakerName: entry.speakerName,
            timestampText: entry.createdAt.formatted(date: .omitted, time: .shortened),
            text: entry.text
        )
    }

    private static func line(from segment: TranscriptSegment) -> LiveTranscriptPanelState.Line {
        LiveTranscriptPanelState.Line(
            id: segment.id.uuidString,
            kind: .transcript,
            speakerName: segment.speakerName,
            timestampText: segment.startTime?.formatted(date: .omitted, time: .shortened),
            text: segment.text
        )
    }

    private static func line(from value: Any, fallbackID: String) -> LiveTranscriptPanelState.Line? {
        if let entry = value as? LiveTranscriptEntry {
            return line(from: entry)
        }

        if let segment = value as? TranscriptSegment {
            return line(from: segment)
        }

        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return nil
            }
            return LiveTranscriptPanelState.Line(
                id: fallbackID,
                kind: .transcript,
                speakerName: nil,
                timestampText: nil,
                text: trimmed
            )
        }

        let text = reflectedString(in: value, labels: ["text", "content", "displayText", "excerpt"])
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let speakerName = reflectedString(in: value, labels: ["speakerName", "speaker"])
        let timestamp = reflectedDate(
            in: value,
            labels: ["startTime", "timestamp", "capturedAt", "createdAt"]
        )?.formatted(date: .omitted, time: .shortened)

        return LiveTranscriptPanelState.Line(
            id: reflectedString(in: value, labels: ["id"]) ?? fallbackID,
            kind: reflectedRawValue(in: value, labels: ["kind"]) == LiveTranscriptEntryKind.system.rawValue ? .system : .transcript,
            speakerName: speakerName,
            timestampText: timestamp,
            text: text
        )
    }

    private static func reflectedString(in value: Any, labels: [String]) -> String? {
        let normalizedLabels = Set(labels.map(normalize(label:)))
        for child in Mirror(reflecting: value).children {
            guard let label = child.label, normalizedLabels.contains(normalize(label: label)) else {
                continue
            }

            let candidateValue = unwrapped(child.value) ?? child.value
            if let string = candidateValue as? String {
                return string.nilIfBlank
            }
        }

        return nil
    }

    private static func reflectedBool(in value: Any, labels: [String]) -> Bool? {
        let normalizedLabels = Set(labels.map(normalize(label:)))
        for child in Mirror(reflecting: value).children {
            guard let label = child.label, normalizedLabels.contains(normalize(label: label)) else {
                continue
            }

            let candidateValue = unwrapped(child.value) ?? child.value
            if let boolValue = candidateValue as? Bool {
                return boolValue
            }
        }

        return nil
    }

    private static func reflectedDate(in value: Any, labels: [String]) -> Date? {
        let normalizedLabels = Set(labels.map(normalize(label:)))
        for child in Mirror(reflecting: value).children {
            guard let label = child.label, normalizedLabels.contains(normalize(label: label)) else {
                continue
            }

            let candidateValue = unwrapped(child.value) ?? child.value
            if let dateValue = candidateValue as? Date {
                return dateValue
            }
        }

        return nil
    }

    private static func reflectedRawValue(in value: Any, labels: [String]) -> String? {
        let normalizedLabels = Set(labels.map(normalize(label:)))
        for child in Mirror(reflecting: value).children {
            guard let label = child.label, normalizedLabels.contains(normalize(label: label)) else {
                continue
            }

            let candidateValue = unwrapped(child.value) ?? child.value
            if let stringValue = candidateValue as? String {
                return stringValue.nilIfBlank
            }

            let rawValueMirror = Mirror(reflecting: candidateValue)
            if let rawValueChild = rawValueMirror.children.first(where: { $0.label == "rawValue" }),
               let rawString = rawValueChild.value as? String {
                return rawString.nilIfBlank
            }
        }

        return nil
    }

    private static func fallbackDetailText(for liveSessionState: LiveSessionState) -> String {
        switch liveSessionState.status {
        case .live:
            return "Oatmeal is listening locally and saving session progress so this panel can recover after a relaunch."
        case .delayed:
            return "Capture is still running. Oatmeal is catching up on transcript work in the background."
        case .recovered:
            return "Oatmeal restored this live session after relaunch and is preserving the recovered timeline here."
        case .failed:
            return "Live transcript updates are paused until session health recovers."
        case .completed:
            return "Recording stopped. Oatmeal will finish the durable transcript and enhanced note in the background."
        case .idle:
            return "Open this panel during an active meeting to monitor live transcript progress."
        }
    }

    private static func fallbackPlaceholderText(for liveSessionState: LiveSessionState) -> String {
        switch liveSessionState.status {
        case .live:
            return "Incremental transcript updates will appear here as Oatmeal saves live preview entries."
        case .delayed:
            return "Oatmeal is still recording and will fill in live transcript updates as it catches up."
        case .recovered:
            return "Recovered transcript updates will appear here as the session reconciles after relaunch."
        case .failed:
            return "Live transcript updates are unavailable until session health improves."
        case .completed:
            return "Capture is finished. The durable transcript will continue updating in the background."
        case .idle:
            return "Open this panel during an active meeting to watch live transcript updates."
        }
    }

    private static func fallbackHealthLabel(for note: MeetingNote) -> String {
        switch note.captureState.phase {
        case .capturing:
            return "Live"
        case .paused:
            return "Delayed"
        case .failed:
            return note.captureState.canResumeAfterCrash ? "Recovered" : "Delayed"
        case .ready, .complete:
            return "Live"
        }
    }

    private static func captureLabel(for captureState: CaptureSessionState) -> String {
        switch captureState.phase {
        case .capturing:
            return "Recording"
        case .paused:
            return "Paused"
        case .failed:
            return "Interrupted"
        case .complete:
            return "Stopped"
        case .ready:
            return "Ready"
        }
    }

    private static func sourceBadges(for note: MeetingNote) -> [LiveTranscriptPanelState.SourceBadge] {
        var badges: [LiveTranscriptPanelState.SourceBadge] = [
            LiveTranscriptPanelState.SourceBadge(
                id: LiveCaptureSourceID.microphone.rawValue,
                title: LiveCaptureSourceID.microphone.displayLabel,
                value: note.liveSessionState.microphoneSource.status.displayLabel,
                detailText: sourceDetailText(
                    message: note.liveSessionState.microphoneSource.statusMessage,
                    lastActivityAt: note.liveSessionState.metrics.microphoneLastActivityAt
                ),
                tone: tone(for: note.liveSessionState.microphoneSource.status)
            )
        ]

        if note.liveSessionState.systemAudioSource.status != .notRequired {
            badges.append(
                LiveTranscriptPanelState.SourceBadge(
                    id: LiveCaptureSourceID.systemAudio.rawValue,
                    title: LiveCaptureSourceID.systemAudio.displayLabel,
                    value: note.liveSessionState.systemAudioSource.status.displayLabel,
                    detailText: sourceDetailText(
                        message: note.liveSessionState.systemAudioSource.statusMessage,
                        lastActivityAt: note.liveSessionState.metrics.systemAudioLastActivityAt
                    ),
                    tone: tone(for: note.liveSessionState.systemAudioSource.status)
                )
            )
        }

        return badges
    }

    private static func metricBadges(for note: MeetingNote) -> [LiveTranscriptPanelState.SourceBadge] {
        let metrics = note.liveSessionState.metrics
        var badges: [LiveTranscriptPanelState.SourceBadge] = []

        if note.captureState.isActive || metrics.pendingChunkCount > 0 || metrics.peakPendingChunkCount > 0 {
            let backlogValue: String = if metrics.pendingChunkCount == 0 {
                "Clear"
            } else if metrics.pendingChunkCount == 1 {
                "1 Chunk"
            } else {
                "\(metrics.pendingChunkCount) Chunks"
            }

            badges.append(
                LiveTranscriptPanelState.SourceBadge(
                    id: "metrics-backlog",
                    title: "Backlog",
                    value: backlogValue,
                    detailText: backlogDetailText(for: metrics),
                    tone: metrics.pendingChunkCount > 0 ? .delayed : .live
                )
            )
        }

        if metrics.recoveryCount > 0 || metrics.interruptionCount > 0 {
            badges.append(
                LiveTranscriptPanelState.SourceBadge(
                    id: "metrics-recoveries",
                    title: "Recoveries",
                    value: "\(metrics.recoveryCount)",
                    detailText: "Automatic capture recoveries in this session.",
                    tone: metrics.recoveryCount > 0 ? .recovered : .live
                )
            )

            badges.append(
                LiveTranscriptPanelState.SourceBadge(
                    id: "metrics-interruptions",
                    title: "Interruptions",
                    value: "\(metrics.interruptionCount)",
                    detailText: "Source pauses or failures Oatmeal absorbed.",
                    tone: metrics.interruptionCount > 0 ? .delayed : .live
                )
            )
        }

        if let lastMergedLiveChunkAt = metrics.lastMergedLiveChunkAt {
            badges.append(
                LiveTranscriptPanelState.SourceBadge(
                    id: "metrics-last-merge",
                    title: "Last Merge",
                    value: lastMergedLiveChunkAt.formatted(date: .omitted, time: .shortened),
                    detailText: mergeDetailText(for: metrics),
                    tone: .live
                )
            )
        }

        return badges
    }

    private static func sourceDetailText(
        message: String?,
        lastActivityAt: Date?
    ) -> String? {
        let parts = [
            message?.nilIfBlank,
            lastActivityAt.map { "Last sample \($0.formatted(date: .omitted, time: .shortened))." }
        ]
        .compactMap { $0?.nilIfBlank }

        guard !parts.isEmpty else {
            return nil
        }

        return parts.joined(separator: " ")
    }

    private static func backlogDetailText(for metrics: LiveSessionMetrics) -> String? {
        var parts: [String] = []

        if metrics.peakPendingChunkCount > 0 {
            let noun = metrics.peakPendingChunkCount == 1 ? "chunk" : "chunks"
            parts.append("Peak backlog \(metrics.peakPendingChunkCount) \(noun).")
        }

        if let oldestPendingChunkStartedAt = metrics.oldestPendingChunkStartedAt {
            parts.append("Oldest pending chunk \(oldestPendingChunkStartedAt.formatted(date: .omitted, time: .shortened)).")
        }

        guard !parts.isEmpty else {
            return nil
        }

        return parts.joined(separator: " ")
    }

    private static func mergeDetailText(for metrics: LiveSessionMetrics) -> String {
        if let lastMergedChunkLatency = metrics.lastMergedChunkLatency {
            return "Latest live chunk merged \(durationText(for: lastMergedChunkLatency)) after the chunk closed."
        }

        return "Latest live chunk merged into the in-meeting preview."
    }

    private static func durationText(for duration: TimeInterval) -> String {
        if duration < 1 {
            return "in under a second"
        }

        if duration < 10 {
            return "in \(String(format: "%.1f", duration))s"
        }

        return "in \(Int(duration.rounded()))s"
    }

    private static func fallbackDetailText(for note: MeetingNote) -> String {
        switch note.captureState.phase {
        case .capturing:
            return "Capture is active. Oatmeal can reopen this panel and recover progress from saved live-session state if the app relaunches."
        case .paused:
            return "Capture is paused. Oatmeal will keep the session scaffold around and catch up when recording resumes."
        case .failed:
            return note.captureState.canResumeAfterCrash
                ? "Oatmeal retained the session state so this meeting can recover after a relaunch."
                : "Capture needs attention before live transcript updates can continue."
        case .ready, .complete:
            return "Live transcript updates will appear here while capture is active."
        }
    }

    private static func fallbackPlaceholderText(for note: MeetingNote) -> String {
        switch note.captureState.phase {
        case .capturing:
            return "Incremental transcript updates will appear here as live chunks are saved."
        case .paused:
            return "Capture is paused, so the live transcript is waiting for the meeting to resume."
        case .failed:
            return note.captureState.canResumeAfterCrash
                ? "Recovered transcript chunks will appear here after the session resumes."
                : "Live transcript updates are unavailable until capture is healthy again."
        case .ready, .complete:
            return "Open this panel during an active meeting to watch live transcript updates."
        }
    }

    private static func tone(for status: LiveSessionStatus) -> LiveTranscriptPanelState.HealthTone {
        switch status {
        case .delayed:
            return .delayed
        case .recovered:
            return .recovered
        case .failed:
            return .failed
        default:
            return .live
        }
    }

    private static func tone(for status: LiveCaptureSourceStatus) -> LiveTranscriptPanelState.HealthTone {
        switch status {
        case .delayed:
            .delayed
        case .recovered:
            .recovered
        case .failed:
            .failed
        case .active:
            .live
        case .idle, .notRequired:
            .live
        }
    }

    private static func tone(for healthLabel: String) -> LiveTranscriptPanelState.HealthTone {
        switch normalize(label: healthLabel) {
        case "delayed", "catchingup":
            .delayed
        case "recovered":
            .recovered
        case "failed":
            .failed
        default:
            .live
        }
    }

    private static func titleCaseHealthLabel(_ rawLabel: String) -> String {
        switch normalize(label: rawLabel) {
        case "live", "active", "healthy":
            "Live"
        case "delayed", "catchingup", "lagging":
            "Delayed"
        case "recovered", "recoveredafterrelaunch":
            "Recovered"
        default:
            rawLabel
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
        }
    }

    private static func normalize(label: String) -> String {
        label
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }

    private static func unwrapped(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else {
            return value
        }
        return mirror.children.first?.value
    }

    private static let activeStateLabels: Set<String> = [
        "active",
        "capturing",
        "live",
        "running"
    ]

    private static let liveSessionStatusesThatExposePanel: Set<LiveSessionStatus> = [
        .live,
        .delayed,
        .recovered,
        .failed
    ]

    struct ReflectedLiveSessionState {
        let healthLabel: String
        let detailText: String?
        let placeholderText: String?
        let lines: [LiveTranscriptPanelState.Line]
    }
}

private struct LiveTranscriptStatusBadge: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        Text("\(title): \(value)")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }
}

private struct TemplateDetailView: View {
    let template: NoteTemplate

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(template.name)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))

                Text(template.description)
                    .font(.title3)
                    .foregroundStyle(.secondary)

                DetailCard(title: "Instructions") {
                    Text(template.instructions)
                }

                DetailCard(title: "Sections") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(template.sections, id: \.self) { section in
                            Label(section, systemImage: "checkmark.circle")
                                .labelStyle(.oatmealBullet)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct ProcessingJobRowModel: Identifiable {
    enum State {
        case waiting
        case queued
        case running
        case completed
        case failed

        var displayLabel: String {
            switch self {
            case .waiting:
                "Waiting"
            case .queued:
                "Queued"
            case .running:
                "Running"
            case .completed:
                "Completed"
            case .failed:
                "Failed"
            }
        }

        var symbolName: String {
            switch self {
            case .waiting:
                "clock"
            case .queued:
                "tray.full"
            case .running:
                "hourglass"
            case .completed:
                "checkmark.circle.fill"
            case .failed:
                "exclamationmark.triangle.fill"
            }
        }

        var color: Color {
            switch self {
            case .waiting:
                .secondary
            case .queued:
                .orange
            case .running:
                .orange
            case .completed:
                .green
            case .failed:
                .pink
            }
        }
    }

    let id: String
    let title: String
    let detail: String
    let secondaryDetail: String?
    let state: State
    let warningMessages: [String]
    let errorMessage: String?
}

private struct ProcessingJobRow: View {
    let row: ProcessingJobRowModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: row.state.symbolName)
                .foregroundStyle(row.state.color)
                .frame(width: 16, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(row.title)
                    .font(.headline)

                Text(row.detail)
                    .foregroundStyle(.primary)
                    .lineLimit(3)

                if let secondaryDetail = row.secondaryDetail {
                    Text(secondaryDetail)
                        .foregroundStyle(.secondary)
                }

                if !row.warningMessages.isEmpty {
                    Text(row.warningMessages.joined(separator: " "))
                        .foregroundStyle(.secondary)
                }

                if let errorMessage = row.errorMessage, row.state == .failed, errorMessage != row.detail {
                    Text(errorMessage)
                        .foregroundStyle(.pink)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                if row.state == .running {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(row.state.displayLabel)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(row.state.color.opacity(0.14), in: Capsule())
            .foregroundStyle(row.state.color)
        }
    }
}

private struct DetailCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct FolderLabel: View {
    let folder: NoteFolder

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
            Text(folder.name)

            if folder.isPinned {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
    }
}

private struct PermissionLine: View {
    let name: String
    let status: PermissionStatus
    let required: Bool

    var body: some View {
        HStack {
            Text(name)
            Spacer()
            if !required {
                Text("Optional")
                    .foregroundStyle(.secondary)
            }
            Text(status.displayLabel)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.14), in: Capsule())
                .foregroundStyle(statusColor)
        }
    }

    private var statusColor: Color {
        switch status {
        case .granted:
            .green
        case .notDetermined:
            .orange
        case .denied, .restricted:
            .pink
        }
    }
}

private struct OatmealBulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 10) {
            configuration.icon
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .padding(.top, 5)

            configuration.title
        }
    }
}

private extension LabelStyle where Self == OatmealBulletLabelStyle {
    static var oatmealBullet: OatmealBulletLabelStyle { .init() }
}

private extension SharePrivacyLevel {
    var displayLabel: String {
        switch self {
        case .private:
            "Private"
        case .anyoneWithLink:
            "Anyone with link"
        case .teamOnly:
            "Team only"
        }
    }
}

private extension PermissionStatus {
    var displayLabel: String {
        switch self {
        case .notDetermined:
            "Not Determined"
        case .granted:
            "Granted"
        case .denied:
            "Denied"
        case .restricted:
            "Restricted"
        }
    }
}

private extension NoteTranscriptionBackend {
    var displayLabel: String {
        switch self {
        case .whisperCPPCLI:
            "whisper.cpp"
        case .appleSpeech:
            "Apple Speech"
        case .mock:
            "Placeholder"
        }
    }
}

private extension NoteTranscriptionExecutionKind {
    var displayLabel: String {
        switch self {
        case .local:
            "Local Runtime"
        case .systemService:
            "System Service"
        case .placeholder:
            "Placeholder"
        }
    }
}

private extension NoteTranscriptionStatus {
    var displayLabel: String {
        switch self {
        case .idle:
            "Waiting"
        case .pending:
            "Running"
        case .succeeded:
            "Completed"
        case .failed:
            "Failed"
        }
    }
}

private extension NoteGenerationStatus {
    var displayLabel: String {
        switch self {
        case .idle:
            "Waiting"
        case .pending:
            "Running"
        case .succeeded:
            "Completed"
        case .failed:
            "Failed"
        }
    }
}

private extension CalendarEventSource {
    var displayLabel: String {
        switch self {
        case .googleCalendar:
            "Google Calendar"
        case .microsoftCalendar:
            "Microsoft Calendar"
        case .local:
            "Local Calendar"
        case .manual:
            "Manual"
        }
    }
}

private extension CalendarEventKind {
    var displayLabel: String {
        switch self {
        case .meeting:
            "Meeting"
        case .focusBlock:
            "Focus Block"
        case .allDayPlaceholder:
            "All-Day Placeholder"
        case .adHoc:
            "Ad Hoc"
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : self
    }
}
