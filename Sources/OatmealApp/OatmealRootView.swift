#if canImport(AppKit)
import AppKit
#endif
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
                .navigationSplitViewColumnWidth(min: 224, ideal: 248, max: 276)
        } content: {
            contentColumn
                .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 420)
        } detail: {
            detailColumn
        }
        .searchable(text: searchTextBinding, placement: .toolbar)
        .task {
            model.bindLightweightSurfaceWindowActions(
                openWindow: { id in openWindow(id: id) },
                dismissWindow: { id in dismissWindow(id: id) }
            )
            await model.loadSystemState()
            model.selectFirstUpcomingMeetingIfNeeded()
            guard !didEvaluateLaunchSessionController else {
                return
            }
            didEvaluateLaunchSessionController = true
            router.presentSessionControllerOnLaunchIfNeeded()
            router.syncDetectionPromptWindow()
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
        .onChange(of: model.detectionPromptState) { _, _ in
            router.syncDetectionPromptWindow()
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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Oatmeal")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))

                    Text("Local-first meeting workspace")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                SidebarSection(title: "Workspace", subtitle: "Your notes and next meetings") {
                    SidebarDestinationButton(
                        title: "Upcoming",
                        subtitle: model.upcomingMeetings.isEmpty ? "Next seven days" : "\(model.upcomingMeetings.count) meetings in the next 7 days",
                        systemImage: "calendar",
                        badge: model.upcomingMeetings.isEmpty ? nil : "\(model.upcomingMeetings.count)",
                        isSelected: model.selectedSidebarItem == .upcoming
                    ) {
                        model.setSelectedSidebarItem(.upcoming)
                    }

                    SidebarDestinationButton(
                        title: "All Notes",
                        subtitle: model.notes.isEmpty ? "Meeting library" : "\(model.notes.count) captured meetings",
                        systemImage: "note.text",
                        badge: model.notes.isEmpty ? nil : "\(model.notes.count)",
                        isSelected: model.selectedSidebarItem == .allNotes
                    ) {
                        model.setSelectedSidebarItem(.allNotes)
                    }

                    SidebarDestinationButton(
                        title: "Templates",
                        subtitle: "Reusable output formats",
                        systemImage: "square.and.pencil",
                        badge: model.templates.isEmpty ? nil : "\(model.templates.count)",
                        isSelected: model.selectedSidebarItem == .templates
                    ) {
                        model.setSelectedSidebarItem(.templates)
                    }
                }

                if !model.folders.isEmpty {
                    SidebarSection(title: "Folders", subtitle: "Pinned context and collections") {
                        ForEach(model.folders) { folder in
                            SidebarDestinationButton(
                                title: folder.name,
                                subtitle: folderSubtitle(for: folder),
                                systemImage: folder.isPinned ? "star.square.on.square" : "folder",
                                badge: noteCountText(for: folder),
                                isSelected: model.selectedSidebarItem == .folder(folder.id)
                            ) {
                                model.setSelectedSidebarItem(.folder(folder.id))
                            }
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
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
                    workspaceState: model.noteWorkspaceState,
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
                    canDeleteNote: model.canDeleteSelectedNote,
                    setLiveTranscriptPanelPresented: { model.setLiveTranscriptPanelPresented($0, for: note.id) },
                    setSelectedWorkspaceMode: { model.setSelectedNoteWorkspaceMode($0) },
                    submitAssistantPrompt: { model.submitAssistantPrompt($0, for: note.id) },
                    submitAssistantDraftAction: { model.submitAssistantDraftAction($0, for: note.id) },
                    retryAssistantTurn: { model.retryAssistantTurn($0, for: note.id) },
                    retryTranscription: { model.retryTranscription() },
                    retryGeneration: { model.retryGeneration() },
                    deleteNote: { model.deleteSelectedNote() }
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
        WorkspaceColumnSurface(
            eyebrow: "Schedule",
            title: "Upcoming Meetings",
            subtitle: upcomingSubtitle,
            accessory: {
                LibraryMetricPill(
                    title: model.calendarAccessStatus == .granted ? "\(model.filteredUpcomingMeetings.count)" : "Calendar",
                    systemImage: model.calendarAccessStatus == .granted ? "calendar" : "calendar.badge.exclamationmark"
                )
            }
        ) {
            if model.calendarAccessStatus != .granted {
                ColumnEmptyState(
                    title: "Calendar Access Needed",
                    message: "Grant calendar access to see real meetings from your Mac.",
                    systemImage: "calendar.badge.plus"
                )
            } else if model.isLoadingUpcomingMeetings {
                ColumnLoadingState(title: "Loading meetings…")
            } else if model.filteredUpcomingMeetings.isEmpty {
                ColumnEmptyState(
                    title: "No Upcoming Meetings",
                    message: "Nothing in the next seven days matches the current filter.",
                    systemImage: "calendar"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.filteredUpcomingMeetings) { event in
                            Button {
                                model.setSelectedUpcomingEventID(event.id)
                            } label: {
                                UpcomingMeetingRow(
                                    event: event,
                                    existingNote: model.note(for: event),
                                    isSelected: model.selectedUpcomingEventID == event.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                }
            }
        }
    }

    private var noteList: some View {
        WorkspaceColumnSurface(
            eyebrow: noteColumnEyebrow,
            title: listTitle,
            subtitle: noteListSubtitle,
            accessory: {
                LibraryMetricPill(
                    title: "\(model.filteredNotes.count)",
                    systemImage: "line.3.horizontal.decrease.circle"
                )
            }
        ) {
            if model.filteredNotes.isEmpty {
                ColumnEmptyState(
                    title: "No Notes",
                    message: "Nothing matches the current filter yet.",
                    systemImage: "tray"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.filteredNotes) { note in
                            Button {
                                model.setSelectedNoteID(note.id)
                            } label: {
                                NoteRow(
                                    note: note,
                                    folder: model.folder(for: note),
                                    isSelected: model.selectedNoteID == note.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                }
            }
        }
    }

    private var templateList: some View {
        WorkspaceColumnSurface(
            eyebrow: "Library",
            title: "Templates",
            subtitle: "Reusable structures for polished meeting notes.",
            accessory: {
                LibraryMetricPill(
                    title: "\(model.templates.count)",
                    systemImage: "square.and.pencil"
                )
            }
        ) {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(model.templates) { template in
                        Button {
                            model.setSelectedTemplate(template)
                        } label: {
                            TemplateListRow(
                                template: template,
                                isSelected: model.selectedTemplateID == template.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
            }
        }
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

    private var noteColumnEyebrow: String {
        switch model.selectedSidebarItem {
        case .allNotes:
            "Library"
        case .templates:
            "Library"
        case .upcoming:
            "Schedule"
        case .folder:
            "Folder"
        }
    }

    private var noteListSubtitle: String {
        let trimmedQuery = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch model.selectedSidebarItem {
        case .allNotes:
            if trimmedQuery.isEmpty {
                return "Recent conversations, polished notes, and in-flight meetings."
            }
            return "Showing \(model.filteredNotes.count) notes that match \"\(trimmedQuery)\"."
        case let .folder(folderID):
            let folderName = model.folders.first(where: { $0.id == folderID })?.name ?? "this folder"
            if trimmedQuery.isEmpty {
                return "Focused notes collected in \(folderName)."
            }
            return "Showing \(model.filteredNotes.count) notes from \(folderName) that match \"\(trimmedQuery)\"."
        case .templates:
            return "Reusable structures for polished meeting notes."
        case .upcoming:
            return "The next seven days from your connected calendars."
        }
    }

    private var upcomingSubtitle: String {
        let trimmedQuery = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            return "The next seven days from your connected calendars."
        }
        return "Showing \(model.filteredUpcomingMeetings.count) meetings that match \"\(trimmedQuery)\"."
    }

    private func folderSubtitle(for folder: NoteFolder) -> String {
        let count = model.notes.filter { $0.folderID == folder.id }.count
        if folder.isPinned {
            return count == 1 ? "Pinned · 1 note" : "Pinned · \(count) notes"
        }
        return count == 1 ? "1 note" : "\(count) notes"
    }

    private func noteCountText(for folder: NoteFolder) -> String? {
        let count = model.notes.filter { $0.folderID == folder.id }.count
        return count == 0 ? nil : "\(count)"
    }
}

private struct NoteRow: View {
    let note: MeetingNote
    let folder: NoteFolder?
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(note.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Text(relativeTimestamp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(note.enhancedNote?.summary ?? note.rawNotes.nilIfBlank ?? "Ready to capture notes")
                .lineLimit(2)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)

                Text(noteDisplayStatus)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let folder {
                    Text("• \(folder.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(rowBorder, lineWidth: isSelected ? 1.4 : 1)
        )
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

    private var relativeTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: note.updatedAt, relativeTo: Date())
    }

    private var rowBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.accentColor.opacity(0.10))
        }
        return AnyShapeStyle(Color(nsColor: .controlBackgroundColor).opacity(0.58))
    }

    private var rowBorder: Color {
        isSelected ? .accentColor.opacity(0.32) : Color.primary.opacity(0.06)
    }
}

private struct UpcomingMeetingRow: View {
    let event: CalendarEvent
    let existingNote: MeetingNote?
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(startLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(event.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if let contextLine {
                        Text(contextLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 8) {
                    Text(relativeStartLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if existingNote != nil {
                        StatusPill(title: "Note Ready", systemImage: "checkmark.circle.fill", tint: .green)
                    }
                }
            }

            HStack(spacing: 8) {
                MetadataPill(title: timeRangeLabel, systemImage: "clock")
                if let location = event.location?.nilIfBlank {
                    MetadataPill(title: location, systemImage: "mappin")
                }
                if !event.attendees.isEmpty {
                    MetadataPill(title: attendeeLabel, systemImage: "person.2")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(rowBorder, lineWidth: isSelected ? 1.4 : 1)
        )
    }

    private var relativeStartLabel: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: event.startDate, relativeTo: Date())
    }

    private var startLabel: String {
        event.startDate.formatted(date: .abbreviated, time: .shortened)
    }

    private var timeRangeLabel: String {
        "\(event.startDate.formatted(date: .omitted, time: .shortened))–\(event.endDate.formatted(date: .omitted, time: .shortened))"
    }

    private var attendeeLabel: String {
        if event.attendees.count == 1 {
            return event.attendees[0].name
        }
        return "\(event.attendees[0].name) +\(event.attendees.count - 1)"
    }

    private var contextLine: String? {
        let pieces = [
            event.location?.nilIfBlank,
            event.attendees.isEmpty ? nil : attendeeLabel
        ].compactMap { $0 }
        return pieces.isEmpty ? nil : pieces.joined(separator: " · ")
    }

    private var rowBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.accentColor.opacity(0.10))
        }
        return AnyShapeStyle(Color(nsColor: .controlBackgroundColor).opacity(0.58))
    }

    private var rowBorder: Color {
        isSelected ? .accentColor.opacity(0.32) : Color.primary.opacity(0.06)
    }
}

private struct TemplateListRow: View {
    let template: NoteTemplate
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(template.name)
                    .font(.headline.weight(.semibold))

                Spacer()

                if template.isDefault {
                    StatusPill(title: "Default", systemImage: "sparkles", tint: .blue)
                }
            }

            Text(template.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor).opacity(0.58),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.32) : Color.primary.opacity(0.06), lineWidth: isSelected ? 1.4 : 1)
        )
    }
}

private struct WorkspaceColumnSurface<Accessory: View, Content: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(eyebrow.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(title)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))

                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                accessory
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .padding(18)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

private struct SidebarSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                content
            }
        }
    }
}

private struct SidebarDestinationButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let badge: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                if let badge {
                    Text(badge)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor).opacity(0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.28) : Color.primary.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct LibraryMetricPill: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.65), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
            )
    }
}

private struct StatusPill: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct MetadataPill: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.045), in: Capsule())
    }
}

private struct ColumnEmptyState: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct ColumnLoadingState: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(title)
                .foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
    let workspaceState: NoteWorkspacePresentationState?
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
    let canDeleteNote: Bool
    let setLiveTranscriptPanelPresented: (Bool) -> Void
    let setSelectedWorkspaceMode: (NoteWorkspaceMode) -> Void
    let submitAssistantPrompt: (String) -> Void
    let submitAssistantDraftAction: (NoteAssistantTurnKind) -> Void
    let retryAssistantTurn: (UUID) -> Void
    let retryTranscription: () -> Void
    let retryGeneration: () -> Void
    let deleteNote: () -> Void
    @State private var isLiveTranscriptPanelExpanded = false
    @State private var isTechnicalDetailsPresented = false
    @State private var isDeleteConfirmationPresented = false
    @State private var assistantPrompt = ""
    @State private var highlightedTranscriptSegmentID: UUID?
    @State private var transcriptScrollRequest = 0

    private var liveTranscriptPanelState: LiveTranscriptPanelState? {
        LiveTranscriptPanelAdapter.panelState(for: note)
    }

    private var aiWorkspaceState: AIWorkspacePresentationState {
        AIWorkspacePresentationState.make(
            note: note,
            summaryExecutionPlan: summaryExecutionPlan
        )
    }

    private var premiumNoteWorkspaceStatus: PremiumNoteWorkspaceStatusState {
        PremiumNoteWorkspaceStatusState.make(
            note: note,
            templateName: template?.name
        )
    }

    private var premiumTaskWorkspaceSnapshot: PremiumTaskWorkspaceSnapshot {
        PremiumTaskWorkspaceSnapshot.make(note: note)
    }

    private var premiumTranscriptWorkspaceState: PremiumTranscriptWorkspaceState {
        PremiumTranscriptWorkspaceState.make(
            note: note,
            highlightedSegmentID: highlightedTranscriptSegmentID
        )
    }

    private var premiumAIWorkspaceState: PremiumAIWorkspaceState {
        PremiumAIWorkspaceState.make(
            note: note,
            summaryExecutionPlan: summaryExecutionPlan
        )
    }

    private var premiumTechnicalDetailsState: PremiumTechnicalDetailsState {
        PremiumTechnicalDetailsState.make(
            note: note,
            selectedMode: resolvedWorkspaceState.selectedMode
        )
    }

    private var resolvedWorkspaceState: NoteWorkspacePresentationState {
        workspaceState ?? NoteWorkspacePresentationState.make(
            note: note,
            selectedMode: .notes
        )
    }

    private var shouldShowLiveTranscriptPanel: Bool {
        isLiveTranscriptPanelExpanded || isLiveTranscriptPanelPresented
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                workspaceHero
                workspaceModeBar

                Divider()
                    .padding(.horizontal, 28)

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        workspaceModeContent
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .background(workspaceBackground)
            .sheet(isPresented: $isTechnicalDetailsPresented) {
                technicalDetailsSheet
            }
            .alert("Delete note?", isPresented: $isDeleteConfirmationPresented) {
                Button("Delete", role: .destructive) {
                    deleteNote()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the note and any saved local recording for it.")
            }
            .onAppear {
                isLiveTranscriptPanelExpanded = isLiveTranscriptPanelPresented
            }
            .onChange(of: note.id) { _, _ in
                isLiveTranscriptPanelExpanded = note.liveSessionState.isTranscriptPanelPresented
                assistantPrompt = ""
                highlightedTranscriptSegmentID = nil
                transcriptScrollRequest = 0
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
            .onChange(of: highlightedTranscriptSegmentID) { _, segmentID in
                guard let segmentID else {
                    return
                }
                scrollToTranscript(segmentID, using: proxy)
            }
            .onChange(of: transcriptScrollRequest) { _, _ in
                guard let segmentID = highlightedTranscriptSegmentID else {
                    return
                }
                scrollToTranscript(segmentID, using: proxy)
            }
            .onChange(of: resolvedWorkspaceState.selectedMode) { _, newMode in
                guard newMode == .transcript, let segmentID = highlightedTranscriptSegmentID else {
                    return
                }
                scrollToTranscript(segmentID, using: proxy)
            }
        }
    }

    private var workspaceHero: some View {
        VStack(alignment: .leading, spacing: 18) {
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

                Menu {
                    Button {
                        setSelectedWorkspaceMode(.notes)
                    } label: {
                        Label("Notes", systemImage: "doc.text")
                    }

                    Button {
                        setSelectedWorkspaceMode(.transcript)
                    } label: {
                        Label("Transcript", systemImage: "text.alignleft")
                    }

                    Button {
                        setSelectedWorkspaceMode(.ai)
                    } label: {
                        Label("AI", systemImage: "sparkles")
                    }

                    Button {
                        setSelectedWorkspaceMode(.tasks)
                    } label: {
                        Label("Tasks", systemImage: "checklist")
                    }

                    Divider()

                    Button {
                        isTechnicalDetailsPresented = true
                    } label: {
                        Label("Technical Details", systemImage: "slider.horizontal.3")
                    }

                    Divider()

                    Button(role: .destructive) {
                        isDeleteConfirmationPresented = true
                    } label: {
                        Label("Delete Note", systemImage: "trash")
                    }
                    .disabled(!canDeleteNote)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
            }

            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(heroMetaLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .controlBackgroundColor),
                    Color(nsColor: .windowBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var workspaceModeBar: some View {
        HStack {
            Picker("Workspace Mode", selection: Binding(
                get: { resolvedWorkspaceState.selectedMode },
                set: { setSelectedWorkspaceMode($0) }
            )) {
                ForEach(resolvedWorkspaceState.availableModes) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 380)

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var workspaceModeContent: some View {
        switch resolvedWorkspaceState.selectedMode {
        case .notes:
            notesWorkspace
        case .transcript:
            transcriptWorkspace
        case .ai:
            aiWorkspaceMode
        case .tasks:
            tasksWorkspace
        }
    }

    private var notesWorkspace: some View {
        VStack(alignment: .leading, spacing: 24) {
            premiumNoteWorkspaceStatusCard

            premiumMeetingNoteCanvas

            minimalistWorkspaceLinks

            if note.rawNotes.nilIfBlank != nil {
                DisclosureGroup("Working notes") {
                    workingNotesSection
                        .padding(.top, 14)
                }
                .padding(.horizontal, 4)
            }

            if let liveTranscriptPanelState {
                liveTranscriptEntryPointSection(liveTranscriptPanelState)
            }
        }
    }

    private var technicalDetailsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PremiumWorkspacePanel(
                        eyebrow: "Behind the scenes",
                        title: premiumTechnicalDetailsState.title,
                        subtitle: premiumTechnicalDetailsState.subtitle,
                        tint: premiumTechnicalDetailsState.tone.tintColor
                    ) {
                        HStack(spacing: 10) {
                            WorkspaceHeroBadge(
                                title: "Status",
                                value: premiumTechnicalDetailsState.statusBadgeText,
                                color: premiumTechnicalDetailsState.tone.tintColor
                            )
                            WorkspaceHeroBadge(
                                title: "Context",
                                value: premiumTechnicalDetailsState.routeBadgeText,
                                color: .secondary
                            )
                        }
                    }

                    metadataSection
                    processingSection
                    captureSection
                    transcriptionSection
                    summaryRuntimeSection
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(workspaceBackground)
            .navigationTitle("Technical Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        isTechnicalDetailsPresented = false
                    }
                }
            }
        }
        .frame(minWidth: 720, minHeight: 640)
    }

    private var transcriptWorkspace: some View {
        VStack(alignment: .leading, spacing: 24) {
            premiumTranscriptWorkspaceHeader

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    transcriptSection
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 20) {
                        transcriptWorkspaceFocusRail

                        if let liveTranscriptPanelState {
                            if shouldShowLiveTranscriptPanel {
                                liveTranscriptSection(liveTranscriptPanelState)
                            } else {
                                liveTranscriptEntryPointSection(liveTranscriptPanelState)
                            }
                        }
                    }
                    .frame(width: 320, alignment: .topLeading)
                }

                VStack(alignment: .leading, spacing: 20) {
                    transcriptSection
                    transcriptWorkspaceFocusRail

                    if let liveTranscriptPanelState {
                        if shouldShowLiveTranscriptPanel {
                            liveTranscriptSection(liveTranscriptPanelState)
                        } else {
                            liveTranscriptEntryPointSection(liveTranscriptPanelState)
                        }
                    }
                }
            }
        }
    }

    private var aiWorkspaceMode: some View {
        VStack(alignment: .leading, spacing: 24) {
            premiumAIWorkspaceHeader
            aiConversationWorkspace
        }
    }

    private var tasksWorkspace: some View {
        VStack(alignment: .leading, spacing: 24) {
            premiumTasksWorkspaceHeader

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    premiumActionItemsWorkspace
                        .frame(maxWidth: .infinity, alignment: .leading)

                    premiumDecisionsWorkspace
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 20) {
                    premiumActionItemsWorkspace
                    premiumDecisionsWorkspace
                }
            }

            structuredWorkflowHistory
        }
    }

    private var aiStarterPrompts: [String] {
        if note.enhancedNote != nil {
            return [
                "What changed in the meeting?",
                "What should I do next?",
                "What decisions were made?"
            ]
        }

        if !note.transcriptSegments.isEmpty {
            return [
                "What are the main takeaways?",
                "What should I follow up on?",
                "Summarize the key decision."
            ]
        }

        return [
            "What stands out in these notes?",
            "Turn this into a short recap.",
            "What should I clarify next?"
        ]
    }

    private var workspaceBackground: some View {
        Color(nsColor: .textBackgroundColor)
    }

    private var premiumNoteWorkspaceStatusCard: some View {
        PremiumWorkspacePanel(
            eyebrow: premiumNoteWorkspaceStatus.tone == .ready ? "Ready" : "Workspace State",
            title: premiumNoteWorkspaceStatus.title,
            subtitle: premiumNoteWorkspaceStatus.detail,
            tint: premiumNoteWorkspaceStatus.tone.tintColor
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if let supportingDetail = premiumNoteWorkspaceStatus.supportingDetail {
                    Text(supportingDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if premiumNoteWorkspaceStatus.tone == .failed || premiumNoteWorkspaceStatus.tone == .processing {
                    HStack(spacing: 10) {
                        if canRetryTranscription {
                            Button("Retry transcription") {
                                retryTranscription()
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        if canRetryGeneration {
                            Button("Retry polished note") {
                                retryGeneration()
                            }
                            .buttonStyle(.bordered)
                        }

                        if note.processingState.isActive {
                            Label("Oatmeal keeps running the post-meeting pipeline in the background.", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var premiumMeetingNoteCanvas: some View {
        PremiumWorkspacePanel(
            eyebrow: "Meeting Note",
            title: note.enhancedNote == nil ? "Polished recap" : "Polished recap",
            subtitle: note.enhancedNote == nil
                ? "This view stays centered on the polished meeting note instead of scattering summary and tasks across separate utility cards."
                : "The main note stays focused on what matters most after the meeting: summary, key points, decisions, and risks.",
            tint: .accentColor
        ) {
            VStack(alignment: .leading, spacing: 24) {
                if let enhanced = note.enhancedNote {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(enhanced.summary)
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)

                        if !enhanced.keyDiscussionPoints.isEmpty {
                            premiumNoteSection(
                                title: "Key Discussion",
                                systemImage: "text.quote"
                            ) {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(enhanced.keyDiscussionPoints, id: \.self) { bullet in
                                        Label(bullet, systemImage: "circle.fill")
                                            .labelStyle(.oatmealBullet)
                                    }
                                }
                            }
                        }

                        if !enhanced.decisions.isEmpty {
                            premiumNoteSection(
                                title: "Decisions",
                                systemImage: "checkmark.seal.fill"
                            ) {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(enhanced.decisions, id: \.self) { decision in
                                        Label(decision, systemImage: "checkmark.circle.fill")
                                            .labelStyle(.oatmealBullet)
                                    }
                                }
                            }
                        }

                        if !enhanced.risksOrOpenQuestions.isEmpty {
                            premiumNoteSection(
                                title: "Risks & Open Questions",
                                systemImage: "exclamationmark.bubble.fill"
                            ) {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(enhanced.risksOrOpenQuestions, id: \.self) { risk in
                                        Label(risk, systemImage: "circle.fill")
                                            .labelStyle(.oatmealBullet)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("The polished note will take shape here as soon as Oatmeal has enough meeting material to work from.")
                            .font(.title3.weight(.semibold))

                        if note.rawNotes.nilIfBlank == nil {
                            Text("Capture, transcript, or raw notes will turn this into the final recap. Until then, Oatmeal keeps the workspace calm and focused instead of filling it with operational scaffolding.")
                                .foregroundStyle(.secondary)
                        } else {
                            premiumNoteSection(
                                title: "Working Notes",
                                systemImage: "square.and.pencil"
                            ) {
                                Text(note.rawNotes)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var minimalistWorkspaceLinks: some View {
        HStack(spacing: 10) {
            Button {
                setSelectedWorkspaceMode(.ai)
            } label: {
                Label("Ask AI", systemImage: "sparkles")
            }
            .buttonStyle(.bordered)

            Button {
                setSelectedWorkspaceMode(.tasks)
            } label: {
                Label("Tasks", systemImage: "checklist")
            }
            .buttonStyle(.bordered)

            Button {
                setSelectedWorkspaceMode(.transcript)
            } label: {
                Label("Transcript", systemImage: "text.alignleft")
            }
            .buttonStyle(.bordered)

            Spacer()
        }
    }

    private var notesWorkspaceTaskRail: some View {
        PremiumWorkspacePanel(
            eyebrow: "Follow-up",
            title: "Tasks & next steps",
            subtitle: premiumTaskWorkspaceSnapshot.hasStructuredContent
                ? "Follow-up work stays attached to the meeting instead of being buried in a secondary utilities column."
                : "As action items, decisions, and risks emerge, Oatmeal keeps them here as a clean meeting-side rail.",
            tint: .orange
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    WorkspaceHeroBadge(
                        title: "Open",
                        value: "\(premiumTaskWorkspaceSnapshot.openItems.count)",
                        color: .orange
                    )

                    WorkspaceHeroBadge(
                        title: "Decisions",
                        value: "\(premiumTaskWorkspaceSnapshot.decisions.count)",
                        color: .green
                    )

                    WorkspaceHeroBadge(
                        title: "Risks",
                        value: "\(premiumTaskWorkspaceSnapshot.risks.count)",
                        color: .pink
                    )
                }

                if premiumTaskWorkspaceSnapshot.totalActionItemCount == 0 {
                    Text("No structured action items are attached to this note yet.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(premiumTaskWorkspaceSnapshot.openItems.prefix(3))) { item in
                            PremiumActionItemRow(item: item)
                        }

                        if premiumTaskWorkspaceSnapshot.totalActionItemCount > 3 {
                            Text("\(premiumTaskWorkspaceSnapshot.totalActionItemCount - 3) more items live in the Tasks mode.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Button {
                    setSelectedWorkspaceMode(.tasks)
                } label: {
                    Label("Open Tasks workspace", systemImage: "arrow.right.circle")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var heroMetaLine: String {
        let timestamp = (note.calendarEvent?.startDate ?? note.captureState.startedAt ?? note.createdAt)
            .formatted(date: .abbreviated, time: .shortened)
        var parts: [String] = [captureLabel, timestamp]

        if let folder {
            parts.append(folder.name)
        }

        if let attendees = note.calendarEvent?.attendees.map(\.name), !attendees.isEmpty {
            if attendees.count == 1 {
                parts.append(attendees[0])
            } else {
                parts.append("\(attendees[0]) +\(attendees.count - 1)")
            }
        }

        return parts.joined(separator: " • ")
    }

    private var metadataSection: some View {
        DetailCard(title: "Meeting Context & Status") {
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

    private var premiumAIWorkspaceHeader: some View {
        PremiumWorkspacePanel(
            eyebrow: "Meeting AI",
            title: premiumAIWorkspaceState.title,
            subtitle: premiumAIWorkspaceState.subtitle,
            tint: premiumAIWorkspaceState.tone.tintColor
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if let supportingDetail = premiumAIWorkspaceState.supportingDetail {
                    Text(supportingDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("\(premiumAIWorkspaceState.threadCountText) • \(premiumAIWorkspaceState.citationCountText) • \(premiumAIWorkspaceState.sourceCountText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var aiConversationWorkspace: some View {
        PremiumWorkspacePanel(
            eyebrow: "Thread",
            title: note.assistantThread.turns.isEmpty ? "Start with a grounded question" : "Conversation for this meeting",
            subtitle: note.assistantThread.turns.isEmpty
                ? "Freeform prompts, quick drafts, and structured workflows all land in one durable thread attached to this note."
                : "The thread stays scoped to this meeting and keeps prompts, drafts, retries, and citations together in one place.",
            tint: .purple
        ) {
            VStack(alignment: .leading, spacing: 20) {
                if note.assistantThread.turns.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(aiWorkspaceState.emptyStateText)
                            .foregroundStyle(.secondary)

                        aiStarterPromptSection
                    }
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(note.assistantThread.turns) { turn in
                            AssistantWorkspaceTurnView(
                                turn: turn,
                                note: note,
                                onOpenCitation: handleAssistantCitationTap(_:),
                                onRetry: { retryAssistantTurn(turn.id) }
                            )
                        }
                    }
                }

                Divider()

                aiComposerSection

                DisclosureGroup("Actions") {
                    aiActionRail
                        .padding(.top, 14)
                }

                DisclosureGroup("Sources") {
                    aiGroundingRail
                        .padding(.top, 14)
                }
            }
        }
    }

    private var aiStarterPromptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Try one of these")
                .font(.subheadline.weight(.semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(aiStarterPrompts, id: \.self) { prompt in
                        Button {
                            assistantPrompt = prompt
                        } label: {
                            Text(prompt)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.purple.opacity(0.10))
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!aiWorkspaceState.canInteract || note.hasPendingAssistantTurn)
                    }
                }
            }
        }
    }

    private var aiComposerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $assistantPrompt)
                .font(.body)
                .frame(minHeight: 88)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.secondary.opacity(0.10))
                )
                .disabled(!aiWorkspaceState.canInteract)

            HStack(alignment: .center, spacing: 12) {
                Text(
                    note.hasPendingAssistantTurn
                        ? "Oatmeal is generating the latest answer for this note."
                        : aiWorkspaceState.composerFootnote
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Menu {
                    Section("Quick Drafts") {
                        ForEach(NoteAssistantTurnKind.allCases.filter(\.isDraftingAction), id: \.self) { kind in
                            Button(kind.displayLabel) {
                                submitAssistantDraftAction(kind)
                            }
                        }
                    }

                    Section("Structured Workflows") {
                        ForEach(NoteAssistantTurnKind.allCases.filter(\.isStructuredWorkflow), id: \.self) { kind in
                            Button(kind.displayLabel) {
                                submitAssistantDraftAction(kind)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                }
                .menuStyle(.borderlessButton)
                .disabled(note.hasPendingAssistantTurn || !aiWorkspaceState.canInteract)

                Button("Send") {
                    let prompt = assistantPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !prompt.isEmpty else {
                        return
                    }
                    assistantPrompt = ""
                    submitAssistantPrompt(prompt)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    !aiWorkspaceState.canInteract
                        || assistantPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || note.hasPendingAssistantTurn
                )
            }
        }
    }

    private var aiActionRail: some View {
        VStack(alignment: .leading, spacing: 14) {
            premiumAIActionSection(
                title: "Quick drafts",
                detail: "Turn this meeting into a ready-to-send artifact.",
                kinds: NoteAssistantTurnKind.allCases.filter(\.isDraftingAction)
            )

            premiumAIActionSection(
                title: "Structured workflows",
                detail: "Extract action items, decisions, and risks from this meeting.",
                kinds: NoteAssistantTurnKind.allCases.filter(\.isStructuredWorkflow)
            )
        }
    }

    private func premiumAIActionSection(
        title: String,
        detail: String,
        kinds: [NoteAssistantTurnKind]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(kinds, id: \.self) { kind in
                    Button {
                        submitAssistantDraftAction(kind)
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: kind.actionSystemImage)
                                .foregroundStyle(.purple)
                                .frame(width: 18)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.displayLabel)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(kind.pendingStatusMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.purple.opacity(0.10))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(note.hasPendingAssistantTurn || !aiWorkspaceState.canInteract)
                }
            }
        }
    }

    private var aiGroundingRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(aiWorkspaceState.introText)
                .foregroundStyle(.secondary)

            ForEach(premiumAIWorkspaceState.sources) { source in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(source.title)
                            .font(.subheadline.weight(.semibold))
                        Text(source.readiness.label)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(source.readiness.color.opacity(0.12), in: Capsule())
                            .foregroundStyle(source.readiness.color)
                    }

                    Text(source.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var premiumTasksWorkspaceHeader: some View {
        PremiumWorkspacePanel(
            eyebrow: "Tasks Workspace",
            title: "Follow-up work for this meeting",
            subtitle: "Tasks, decisions, and open questions stay grounded to this note so the follow-up picture is easy to scan.",
            tint: .orange
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    WorkspaceHeroBadge(
                        title: "Open",
                        value: "\(premiumTaskWorkspaceSnapshot.openItems.count)",
                        color: .orange
                    )
                    WorkspaceHeroBadge(
                        title: "Delegated",
                        value: "\(premiumTaskWorkspaceSnapshot.delegatedItems.count)",
                        color: .blue
                    )
                    WorkspaceHeroBadge(
                        title: "Done",
                        value: "\(premiumTaskWorkspaceSnapshot.doneItems.count)",
                        color: .green
                    )
                }

                HStack(spacing: 10) {
                    Button {
                        submitAssistantDraftAction(.actionItems)
                    } label: {
                        Label("Refresh action items", systemImage: NoteAssistantTurnKind.actionItems.actionSystemImage)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(note.hasPendingAssistantTurn || !aiWorkspaceState.canInteract)

                    Button {
                        submitAssistantDraftAction(.decisionsAndRisks)
                    } label: {
                        Label("Refresh decisions & risks", systemImage: NoteAssistantTurnKind.decisionsAndRisks.actionSystemImage)
                    }
                    .buttonStyle(.bordered)
                    .disabled(note.hasPendingAssistantTurn || !aiWorkspaceState.canInteract)
                }
            }
        }
    }

    private var premiumActionItemsWorkspace: some View {
        PremiumWorkspacePanel(
            eyebrow: "Action Items",
            title: premiumTaskWorkspaceSnapshot.totalActionItemCount == 0 ? "No structured follow-up yet" : "Action items",
            subtitle: premiumTaskWorkspaceSnapshot.totalActionItemCount == 0
                ? "Run the structured workflows or let the polished note finish generating to populate this space."
                : "Open work, delegated items, and completed follow-up all stay tied to this meeting.",
            tint: .orange
        ) {
            VStack(alignment: .leading, spacing: 18) {
                if premiumTaskWorkspaceSnapshot.totalActionItemCount == 0 {
                    Text("Oatmeal will surface follow-up work here once this meeting produces structured action items.")
                        .foregroundStyle(.secondary)
                } else {
                    premiumTaskSection(
                        title: "Open",
                        items: premiumTaskWorkspaceSnapshot.openItems
                    )

                    premiumTaskSection(
                        title: "Delegated",
                        items: premiumTaskWorkspaceSnapshot.delegatedItems
                    )

                    premiumTaskSection(
                        title: "Completed",
                        items: premiumTaskWorkspaceSnapshot.doneItems
                    )
                }
            }
        }
    }

    private var premiumDecisionsWorkspace: some View {
        PremiumWorkspacePanel(
            eyebrow: "Decisions",
            title: "Decision log & open questions",
            subtitle: "Structured takeaways stay visible next to the action list so the meeting’s outcome is legible at a glance.",
            tint: .green
        ) {
            VStack(alignment: .leading, spacing: 20) {
                if premiumTaskWorkspaceSnapshot.decisions.isEmpty && premiumTaskWorkspaceSnapshot.risks.isEmpty {
                    Text("No structured decisions or open questions are attached to this meeting yet.")
                        .foregroundStyle(.secondary)
                } else {
                    if !premiumTaskWorkspaceSnapshot.decisions.isEmpty {
                        premiumNoteSection(
                            title: "Decisions",
                            systemImage: "checkmark.seal.fill"
                        ) {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(premiumTaskWorkspaceSnapshot.decisions, id: \.self) { decision in
                                    Label(decision, systemImage: "checkmark.circle.fill")
                                        .labelStyle(.oatmealBullet)
                                }
                            }
                        }
                    }

                    if !premiumTaskWorkspaceSnapshot.risks.isEmpty {
                        premiumNoteSection(
                            title: "Risks & Open Questions",
                            systemImage: "exclamationmark.bubble.fill"
                        ) {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(premiumTaskWorkspaceSnapshot.risks, id: \.self) { risk in
                                    Label(risk, systemImage: "circle.fill")
                                        .labelStyle(.oatmealBullet)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var structuredWorkflowHistory: some View {
        DetailCard(title: "Structured Workflow History") {
            let workflowTurns = note.assistantThread.turns.filter { $0.kind.isStructuredWorkflow }

            if workflowTurns.isEmpty {
                Text("Run one of the structured workflows above and Oatmeal will keep the grounded readout here for this meeting.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(workflowTurns) { turn in
                        AssistantWorkspaceTurnView(
                            turn: turn,
                            note: note,
                            onOpenCitation: handleAssistantCitationTap(_:),
                            onRetry: { retryAssistantTurn(turn.id) }
                        )
                    }
                }
            }
        }
    }

    private var captureSection: some View {
        DetailCard(title: "Capture & Permissions") {
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
        DetailCard(title: "Transcript Engine") {
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
        DetailCard(title: "Behind-the-Scenes Progress") {
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
        DetailCard(title: "Summary Engine") {
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

    private var workingNotesSection: some View {
        PremiumWorkspacePanel(
            eyebrow: "Working Material",
            title: "Raw notes",
            subtitle: note.rawNotes.nilIfBlank == nil
                ? "Raw notes stay available as supporting material without competing with the polished meeting note."
                : "These notes support the polished recap without taking over the main note view.",
            tint: .secondary
        ) {
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

    private var premiumTranscriptWorkspaceHeader: some View {
        PremiumWorkspacePanel(
            eyebrow: premiumTranscriptWorkspaceState.tone == .focused ? "Transcript Focus" : "Transcript Workspace",
            title: premiumTranscriptWorkspaceState.title,
            subtitle: premiumTranscriptWorkspaceState.subtitle,
            tint: premiumTranscriptWorkspaceState.tone.tintColor
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if let supportingDetail = premiumTranscriptWorkspaceState.supportingDetail {
                    Text(supportingDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    WorkspaceHeroBadge(
                        title: "Transcript",
                        value: premiumTranscriptWorkspaceState.segmentCountText,
                        color: premiumTranscriptWorkspaceState.tone.tintColor
                    )

                    if let speakerCountText = premiumTranscriptWorkspaceState.speakerCountText {
                        WorkspaceHeroBadge(
                            title: "Speakers",
                            value: speakerCountText,
                            color: .secondary
                        )
                    }

                    WorkspaceHeroBadge(
                        title: "Mode",
                        value: "Review",
                        color: .blue
                    )
                }
            }
        }
    }

    private var transcriptWorkspaceFocusRail: some View {
        PremiumWorkspacePanel(
            eyebrow: premiumTranscriptWorkspaceState.focusTitle == nil ? "Review Flow" : "Focused Citation",
            title: premiumTranscriptWorkspaceState.focusTitle ?? "Transcript stays secondary",
            subtitle: premiumTranscriptWorkspaceState.focusExcerpt ?? "Transcript mode is where Oatmeal lets you verify exact meeting language without taking over the polished note workspace.",
            tint: premiumTranscriptWorkspaceState.focusTitle == nil ? .blue : premiumTranscriptWorkspaceState.tone.tintColor
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if premiumTranscriptWorkspaceState.focusTitle == nil {
                    Text("Use this space to validate grounded answers, inspect phrasing, and trace the meeting line-by-line. When you’re done, jump back to Notes for the polished recap.")
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        highlightedTranscriptSegmentID = nil
                    } label: {
                        Label("Clear transcript focus", systemImage: "arrow.uturn.backward.circle")
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    setSelectedWorkspaceMode(.notes)
                } label: {
                    Label("Return to Notes", systemImage: "arrow.left.circle")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func premiumNoteSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)

            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.secondary.opacity(0.08))
        )
    }

    @ViewBuilder
    private func premiumTaskSection(title: String, items: [ActionItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(items) { item in
                        PremiumActionItemRow(item: item)
                    }
                }
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
        PremiumWorkspacePanel(
            eyebrow: "Transcript",
            title: note.transcriptSegments.isEmpty ? "No transcript yet" : "Meeting transcript",
            subtitle: note.transcriptSegments.isEmpty
                ? transcriptPlaceholderText
                : "A deliberate reading surface for transcript review, verification, and source inspection.",
            tint: .blue
        ) {
            if note.transcriptSegments.isEmpty {
                Text(transcriptPlaceholderText)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(note.transcriptSegments) { segment in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .center, spacing: 10) {
                                Text(segmentHeader(segment))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                if highlightedTranscriptSegmentID == segment.id {
                                    Text("Focused")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                                        .foregroundStyle(Color.accentColor)
                                }
                            }

                            Text(segment.text)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(highlightedTranscriptSegmentID == segment.id ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(highlightedTranscriptSegmentID == segment.id ? Color.accentColor.opacity(0.26) : Color.secondary.opacity(0.08))
                        )
                        .id(segment.id)
                    }
                }
            }
        }
        .id(transcriptSectionScrollID)
    }

    private var transcriptSectionScrollID: String {
        "transcript-section-\(note.id.uuidString)"
    }

    private func handleAssistantCitationTap(_ citation: NoteAssistantCitation) {
        guard let route = TranscriptWorkspaceRoute.resolve(citation: citation, in: note) else {
            return
        }

        setSelectedWorkspaceMode(route.workspaceMode)
        if highlightedTranscriptSegmentID == route.transcriptSegmentID {
            transcriptScrollRequest += 1
        }
        highlightedTranscriptSegmentID = route.transcriptSegmentID
    }

    private func scrollToTranscript(
        _ segmentID: UUID,
        using proxy: ScrollViewProxy
    ) {
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(transcriptSectionScrollID, anchor: .top)
                proxy.scrollTo(segmentID, anchor: .center)
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

private struct WorkspaceHeroBadge: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color.opacity(0.12))
        )
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

private struct PremiumWorkspacePanel<Content: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)

                Text(title)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(tint.opacity(0.10))
        )
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

private struct PremiumActionItemRow: View {
    let item: ActionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusColor)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.text)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        if let assignee = item.assignee {
                            Text(assignee)
                        }

                        if let dueDate = item.dueDate {
                            Text(dueDate.formatted(date: .abbreviated, time: .omitted))
                        }

                        if item.assignee == nil, item.dueDate == nil {
                            Text("No owner yet")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Text(statusLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.14), in: Capsule())
                    .foregroundStyle(statusColor)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.secondary.opacity(0.08))
        )
    }

    private var statusSymbol: String {
        switch item.status {
        case .open:
            "circle"
        case .delegated:
            "arrowshape.turn.up.right.circle.fill"
        case .done:
            "checkmark.circle.fill"
        }
    }

    private var statusLabel: String {
        switch item.status {
        case .open:
            "Open"
        case .delegated:
            "Delegated"
        case .done:
            "Done"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .open:
            .orange
        case .delegated:
            .blue
        case .done:
            .green
        }
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

private struct AssistantWorkspaceTurnView: View {
    let turn: NoteAssistantTurn
    let note: MeetingNote
    let onOpenCitation: (NoteAssistantCitation) -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Text("You")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if turn.kind != .prompt {
                        Label(turn.kind.displayLabel, systemImage: turn.kind.actionSystemImage)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }

                    Spacer()

                    Text(turn.requestedAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(turn.prompt)
                    .font(.body)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor.opacity(0.10))
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Label("Oatmeal", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    AssistantTurnStatusBadge(status: turn.status)

                    Spacer()

                    if turn.status == .completed, turn.response?.isEmpty == false {
                        Button(turn.kind.copyLabel) {
                            copyResponseToPasteboard()
                        }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                    }

                    if turn.status == .failed {
                        Button("Retry") {
                            onRetry()
                        }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                    }

                    if let completedAt = turn.completedAt {
                        Text(completedAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                switch turn.status {
                case .pending:
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text(turn.kind.pendingStatusMessage)
                            .foregroundStyle(.secondary)
                    }
                case .completed:
                    VStack(alignment: .leading, spacing: 10) {
                        Text(turn.response ?? "No assistant response was saved for this turn.")
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)

                        if !turn.citations.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Sources")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                ForEach(turn.citations) { citation in
                                    if AssistantCitationNavigationTarget.resolve(citation: citation, in: note) != nil {
                                        Button {
                                            onOpenCitation(citation)
                                        } label: {
                                            citationCard(citation: citation, navigable: true)
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        citationCard(citation: citation, navigable: false)
                                    }
                                }
                            }
                        }
                    }
                case .failed:
                    VStack(alignment: .leading, spacing: 8) {
                        Text(turn.failureMessage ?? "Oatmeal could not complete this answer.")
                            .foregroundStyle(.secondary)
                        Text("Retry this turn to ask Oatmeal again from the same note-local context.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.08))
            )
        }
    }

    private func copyResponseToPasteboard() {
        guard let response = turn.response, !response.isEmpty else {
            return
        }

        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(response, forType: .string)
        #endif
    }

    @ViewBuilder
    private func citationCard(citation: NoteAssistantCitation, navigable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(citation.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if navigable {
                    Label("Jump to transcript", systemImage: "arrow.down.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            Text(citation.excerpt)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(navigable ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.04))
        )
    }
}

struct AssistantCitationNavigationTarget: Equatable, Sendable {
    let transcriptSegmentID: UUID

    static func resolve(citation: NoteAssistantCitation, in note: MeetingNote) -> AssistantCitationNavigationTarget? {
        guard let transcriptSegmentID = citation.transcriptSegmentID,
              note.transcriptSegments.contains(where: { $0.id == transcriptSegmentID }) else {
            return nil
        }

        return AssistantCitationNavigationTarget(transcriptSegmentID: transcriptSegmentID)
    }
}

private struct AssistantTurnStatusBadge: View {
    let status: NoteAssistantTurnStatus

    var body: some View {
        Text(status.displayLabel)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(badgeColor.opacity(0.12))
            .foregroundStyle(badgeColor)
            .clipShape(Capsule())
    }

    private var badgeColor: Color {
        switch status {
        case .pending:
            .orange
        case .completed:
            .green
        case .failed:
            .pink
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

private extension NoteAssistantTurnKind {
    var actionSystemImage: String {
        switch self {
        case .prompt:
            "text.bubble"
        case .followUpEmail:
            "envelope"
        case .slackRecap:
            "bubble.left.and.bubble.right"
        case .actionItems:
            "list.bullet"
        case .decisionsAndRisks:
            "checkmark.circle"
        }
    }

    var pendingStatusMessage: String {
        switch self {
        case .prompt:
            "Generating a grounded answer for this meeting."
        case .followUpEmail:
            "Drafting a grounded follow-up email for this meeting."
        case .slackRecap:
            "Drafting a grounded Slack recap for this meeting."
        case .actionItems:
            "Extracting grounded action items and likely owners for this meeting."
        case .decisionsAndRisks:
            "Extracting grounded decisions, tentative discussion, and open questions for this meeting."
        }
    }

    var copyLabel: String {
        switch self {
        case .prompt:
            "Copy Response"
        case .followUpEmail, .slackRecap:
            "Copy Draft"
        case .actionItems, .decisionsAndRisks:
            "Copy Readout"
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
