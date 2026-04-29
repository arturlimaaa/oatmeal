#if canImport(AppKit)
import AppKit
#endif
import OatmealCore
import OatmealEdge
import SwiftUI

enum LibraryViewMode: Hashable {
    case list
    case grid
}

enum LibraryFilter: Hashable {
    case allMeetings
    case today
    case thisWeek
    case unreviewed
    case actionItems

    var menuLabel: String {
        switch self {
        case .allMeetings: return "All time"
        case .today:       return "Today"
        case .thisWeek:    return "This week"
        case .unreviewed:  return "Unreviewed"
        case .actionItems: return "Action items"
        }
    }
}

struct OatmealRootView: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var didEvaluateLaunchSessionController = false
    @State private var libraryFilter: LibraryFilter = .allMeetings
    @State private var libraryPath = NavigationPath()
    @State private var libraryViewMode: LibraryViewMode = .list

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
        Group {
            if model.isOnboardingComplete {
                mainSplitView
            } else {
                OnboardingRootView()
            }
        }
        .task {
            model.bindLightweightSurfaceWindowActions(
                openWindow: { id in openWindow(id: id) },
                dismissWindow: { id in dismissWindow(id: id) }
            )
            await model.loadSystemState()
            // The sidebar no longer exposes Upcoming / Templates routes. If the
            // persisted sidebar selection lands on one of them, drop it back
            // onto All meetings so the user isn't stuck on a dead branch.
            if case .upcoming = model.selectedSidebarItem {
                model.setSelectedSidebarItem(.allNotes)
            } else if case .templates = model.selectedSidebarItem {
                model.setSelectedSidebarItem(.allNotes)
            }
            guard !didEvaluateLaunchSessionController else {
                return
            }
            didEvaluateLaunchSessionController = true
            router.syncDetectionPromptWindow()
        }
        .onChange(of: model.selectedSidebarItem) { _, _ in
            // Switching sidebar filter pops the workspace back to library.
            libraryPath = NavigationPath()
        }
        .onChange(of: model.detectionPromptState) { _, _ in
            router.syncDetectionPromptWindow()
        }
    }

    private var mainSplitView: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            NavigationStack(path: $libraryPath) {
                noteList
                    .navigationDestination(for: MeetingNote.ID.self) { noteID in
                        meetingDetailDestination(for: noteID)
                    }
            }
        }
    }

    @ViewBuilder
    private func meetingDetailDestination(for noteID: MeetingNote.ID) -> some View {
        if let note = model.notes.first(where: { $0.id == noteID }) {
            MeetingDetailView(
                note: note,
                folder: model.folder(for: note),
                canRetryGeneration: model.canRetryGeneration(for: note),
                canDeleteNote: model.canDeleteSelectedNote,
                submitAssistantPrompt: { model.submitAssistantPrompt($0, for: note.id) },
                submitAssistantDraftAction: { model.submitAssistantDraftAction($0, for: note.id) },
                retryGeneration: { model.retryGeneration() },
                deleteNote: { model.deleteSelectedNote() }
            )
            .toolbar(.hidden, for: .windowToolbar)
            .navigationBarBackButtonHidden(true)
        } else {
            ContentUnavailableView(
                "Note unavailable",
                systemImage: "note.text",
                description: Text("This note is no longer available.")
            )
        }
    }

    fileprivate func openNote(_ noteID: MeetingNote.ID) {
        model.setSelectedNoteID(noteID)
        libraryPath.append(noteID)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                OatLeafMark(size: 18, tint: Color.om.ink)
                Text("Oatmeal")
                    .font(.om.sectionTitle)
                    .foregroundStyle(Color.om.ink)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 4) {
                        SidebarNavRow(
                            title: "All meetings",
                            systemImage: "tray.full",
                            badge: model.notes.isEmpty ? nil : "\(model.notes.count)",
                            isSelected: isFilterRowSelected(.allMeetings)
                        ) { selectFilter(.allMeetings) }

                        SidebarNavRow(
                            title: "Today",
                            systemImage: "calendar",
                            badge: countText(todayNotes.count),
                            isSelected: isFilterRowSelected(.today)
                        ) { selectFilter(.today) }

                        SidebarNavRow(
                            title: "Unreviewed",
                            systemImage: "sparkles",
                            badge: countText(unreviewedNotes.count),
                            isSelected: isFilterRowSelected(.unreviewed)
                        ) { selectFilter(.unreviewed) }

                        SidebarNavRow(
                            title: "Action items",
                            systemImage: "checkmark.circle",
                            badge: countText(openActionItemCount),
                            isSelected: isFilterRowSelected(.actionItems)
                        ) { selectFilter(.actionItems) }
                    }
                    .padding(.horizontal, 12)

                    if !model.folders.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            OMEyebrow("Folders")
                                .padding(.horizontal, 20)
                                .padding(.bottom, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(model.folders) { folder in
                                    SidebarNavRow(
                                        title: folder.name,
                                        systemImage: folder.isPinned ? "star" : "folder",
                                        badge: noteCountText(for: folder),
                                        isSelected: model.selectedSidebarItem == .folder(folder.id)
                                    ) {
                                        libraryFilter = .allMeetings
                                        model.setSelectedSidebarItem(.folder(folder.id))
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                        }
                    }
                }
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)

            Spacer(minLength: 0)

            OMHairline()
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.om.ink3)
                Text(sidebarFooterText)
                    .font(.om.meta)
                    .foregroundStyle(Color.om.ink3)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.om.paper2)
    }

    private func selectFilter(_ filter: LibraryFilter) {
        libraryFilter = filter
        if model.selectedSidebarItem != .allNotes {
            model.setSelectedSidebarItem(.allNotes)
        }
    }

    private func isFilterRowSelected(_ filter: LibraryFilter) -> Bool {
        guard model.selectedSidebarItem == .allNotes else { return false }
        return libraryFilter == filter
    }

    private func countText(_ count: Int) -> String? {
        count == 0 ? nil : "\(count)"
    }

    private var todayNotes: [MeetingNote] {
        let cal = Calendar.current
        return model.notes.filter { cal.isDateInToday(meetingStart(for: $0)) }
    }

    private var unreviewedNotes: [MeetingNote] {
        model.notes.filter { $0.enhancedNote == nil }
    }

    private var openActionItemCount: Int {
        model.notes.reduce(0) { acc, note in
            acc + (note.enhancedNote?.actionItems.filter { $0.status == .open }.count ?? 0)
        }
    }

    private var sidebarFooterText: String {
        let count = model.notes.count
        if count == 0 {
            return "0 meetings · on this Mac"
        }
        return count == 1 ? "1 meeting · on this Mac" : "\(count) meetings · on this Mac"
    }

    private func recoveredSessionBanner(title: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(Color.om.ember)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                OMEyebrow("Recovered")
                Text("Picked up an in-flight recording — \(title).")
                    .font(.om.body)
                    .foregroundStyle(Color.om.ink)
                Text("Reopen the recorder to keep going, or dismiss to handle later.")
                    .font(.om.caption)
                    .foregroundStyle(Color.om.ink3)
            }
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                OMButton("Open recorder", variant: .primary) {
                    router.reopenSessionController()
                }
                OMButton("Dismiss", variant: .secondary) {
                    model.dismissSessionController()
                }
            }
        }
        .padding(14)
        .background(Color.om.ember.opacity(0.06))
        .overlay(alignment: .bottom) { OMHairline() }
    }

    private var noteList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.shouldAutoPresentSessionControllerOnLaunch,
               let recoveredTitle = model.sessionControllerState?.title {
                recoveredSessionBanner(title: recoveredTitle)
            }
            librarySubToolbar
            OMHairline()
            libraryPageHead
            OMHairline()

            if displayedNotes.isEmpty {
                libraryEmptyState
            } else {
                switch libraryViewMode {
                case .list: noteListContent
                case .grid: noteGridContent
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.om.paper)
    }

    private var noteListContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groupedNotesByDay, id: \.dayKey) { group in
                    HStack(spacing: 10) {
                        OMEyebrow(group.label)
                        Rectangle()
                            .fill(Color.om.line)
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 4)
                    ForEach(group.notes) { note in
                        MeetingRow(
                            startDate: meetingStart(for: note),
                            endDate: meetingEnd(for: note),
                            title: note.title,
                            peopleLine: peopleLine(for: note),
                            tag: tagLabel(for: note),
                            isLive: note.captureState.phase == .capturing,
                            isSelected: model.selectedNoteID == note.id
                        ) {
                            openNote(note.id)
                        }
                        .padding(.horizontal, 8)
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    private var noteGridContent: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 14, alignment: .top)
                ],
                alignment: .leading,
                spacing: 14
            ) {
                ForEach(groupedNotesByDay.flatMap(\.notes)) { note in
                    MeetingCard(
                        startDate: meetingStart(for: note),
                        endDate: meetingEnd(for: note),
                        title: note.title,
                        peopleLine: peopleLine(for: note),
                        tag: tagLabel(for: note),
                        isLive: note.captureState.phase == .capturing,
                        isSelected: model.selectedNoteID == note.id
                    ) {
                        openNote(note.id)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    private var libraryPageHead: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                OMEyebrow("Library")
                Text(listTitle)
                    .font(OatmealTypography.serif(48))
                    .foregroundStyle(Color.om.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .truncationMode(.tail)
                Text(libraryHeadMetaLine)
                    .font(.om.meta)
                    .foregroundStyle(Color.om.ink3)
            }
            Spacer(minLength: 16)
            HStack(spacing: 6) {
                OMButton(
                    "Grid",
                    variant: libraryViewMode == .grid ? .primary : .secondary
                ) {
                    libraryViewMode = .grid
                }
                OMButton(
                    "List",
                    variant: libraryViewMode == .list ? .primary : .secondary
                ) {
                    libraryViewMode = .list
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var libraryHeadMetaLine: String {
        let notes = displayedNotes
        let totalMinutes = notes.reduce(0) { acc, note in
            guard let start = note.captureState.startedAt ?? note.calendarEvent?.startDate,
                  let end = note.captureState.endedAt ?? note.calendarEvent?.endDate
            else { return acc }
            return acc + max(0, Int(end.timeIntervalSince(start) / 60))
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let audio: String = {
            if hours == 0 { return "\(minutes)m" }
            if minutes == 0 { return "\(hours)h" }
            return "\(hours)h \(minutes)m"
        }()
        let actions = notes.reduce(0) { acc, note in
            acc + (note.enhancedNote?.actionItems.count ?? 0)
        }
        return "\(notes.count) kept · \(audio) of audio · \(actions) action items"
    }

    private var librarySubToolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.om.ink3)
                TextField("Search transcripts, people, action items…", text: searchTextBinding)
                    .textFieldStyle(.plain)
                    .font(.om.body)
                    .foregroundStyle(Color.om.ink)
                Spacer(minLength: 0)
                OMKbd("⌘K")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.om.card, in: RoundedRectangle(cornerRadius: OMRadius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: OMRadius.sm)
                    .strokeBorder(Color.om.line, lineWidth: 1)
            )
            .frame(maxWidth: 420)

            Menu {
                ForEach(libraryFilterOptions, id: \.self) { option in
                    Button {
                        libraryFilter = option
                    } label: {
                        if option == libraryFilter {
                            Label(option.menuLabel, systemImage: "checkmark")
                        } else {
                            Text(option.menuLabel)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar").font(.system(size: 11))
                    Text(libraryFilter.menuLabel)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(Color.om.ink2)
                .background(Color.om.card, in: RoundedRectangle(cornerRadius: OMRadius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: OMRadius.sm)
                        .strokeBorder(Color.om.line, lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer(minLength: 0)

            OMButton(variant: .primary) {
                model.startQuickNote()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                    Text("New meeting")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var libraryEmptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color.om.ink3)
            Text("No meetings yet")
                .font(.om.sectionTitle)
                .foregroundStyle(Color.om.ink)
            Text("Start a new meeting or let auto-detection notice your next call.")
                .font(.om.caption)
                .foregroundStyle(Color.om.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct NoteDayGroup {
        let dayKey: Date
        let label: String
        let notes: [MeetingNote]
    }

    private var libraryFilterOptions: [LibraryFilter] {
        [.allMeetings, .today, .thisWeek, .unreviewed, .actionItems]
    }

    private var displayedNotes: [MeetingNote] {
        let base = model.filteredNotes
        // Folder selections use the model's own narrowing; they get no extra
        // view-layer filter on top.
        if case .folder = model.selectedSidebarItem { return base }

        switch libraryFilter {
        case .allMeetings:
            return base
        case .today:
            let cal = Calendar.current
            return base.filter { cal.isDateInToday(meetingStart(for: $0)) }
        case .thisWeek:
            let cal = Calendar.current
            guard let weekStart = cal.dateInterval(of: .weekOfYear, for: .now)?.start else {
                return base
            }
            return base.filter { meetingStart(for: $0) >= weekStart }
        case .unreviewed:
            return base.filter { $0.enhancedNote == nil }
        case .actionItems:
            return base.filter {
                ($0.enhancedNote?.actionItems.contains(where: { $0.status == .open }) ?? false)
            }
        }
    }

    private var groupedNotesByDay: [NoteDayGroup] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let sorted = displayedNotes.sorted(by: {
            meetingStart(for: $0) > meetingStart(for: $1)
        })
        let buckets = Dictionary(grouping: sorted) { note -> Date in
            calendar.startOfDay(for: meetingStart(for: note))
        }
        return buckets.keys
            .sorted(by: >)
            .map { day in
                NoteDayGroup(
                    dayKey: day,
                    label: dayLabel(for: day, today: today, calendar: calendar),
                    notes: buckets[day] ?? []
                )
            }
    }

    private func dayLabel(for day: Date, today: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        let dateText = formatter.string(from: day)
        if calendar.isDate(day, inSameDayAs: today) {
            return "TODAY · \(dateText.uppercased())"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return "YESTERDAY · \(dateText.uppercased())"
        }
        return dateText.uppercased()
    }

    private func meetingStart(for note: MeetingNote) -> Date {
        note.calendarEvent?.startDate ?? note.createdAt
    }

    private func meetingEnd(for note: MeetingNote) -> Date? {
        note.calendarEvent?.endDate ?? note.captureState.endedAt
    }

    private func peopleLine(for note: MeetingNote) -> String? {
        let names = note.calendarEvent?.attendees.map(\.name) ?? []
        guard !names.isEmpty else { return nil }
        if names.count <= 3 { return names.joined(separator: ", ") }
        let head = names.prefix(2).joined(separator: ", ")
        return "\(head) +\(names.count - 2)"
    }

    private func tagLabel(for note: MeetingNote) -> String? {
        if let folder = model.folder(for: note) {
            return folder.name
        }
        return nil
    }

    private var listTitle: String {
        if case let .folder(folderID) = model.selectedSidebarItem {
            return model.folders.first(where: { $0.id == folderID })?.name ?? "Folder"
        }
        switch libraryFilter {
        case .allMeetings: return "All meetings"
        case .today:       return "Today"
        case .thisWeek:    return "This week"
        case .unreviewed:  return "Unreviewed"
        case .actionItems: return "Action items"
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

    private func noteCountText(for folder: NoteFolder) -> String? {
        let count = model.notes.filter { $0.folderID == folder.id }.count
        return count == 0 ? nil : "\(count)"
    }
}

private struct SidebarNavRow: View {
    let title: String
    let systemImage: String
    let badge: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.om.ink : Color.om.ink3)
                    .frame(width: 14)
                Text(title)
                    .font(.om.body)
                    .foregroundStyle(isSelected ? Color.om.ink : Color.om.ink2)
                Spacer(minLength: 6)
                if let badge {
                    Text(badge)
                        .font(.om.meta)
                        .foregroundStyle(Color.om.ink3)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: OMRadius.sm)
                    .fill(isSelected ? Color.om.card : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct MeetingDetailView: View {
    let note: MeetingNote
    let folder: NoteFolder?
    let canRetryGeneration: Bool
    let canDeleteNote: Bool
    let submitAssistantPrompt: (String) -> Void
    let submitAssistantDraftAction: (NoteAssistantTurnKind) -> Void
    let retryGeneration: () -> Void
    let deleteNote: () -> Void

    @State private var isDeleteConfirmationPresented = false
    @State private var isSummaryPresented = false
    @State private var assistantPrompt = ""
    @State private var transcriptSpeakerFilter: Set<String> = []
    @State private var transcriptSearchText: String = ""
    @State private var isTranscriptSearchVisible: Bool = false
    @FocusState private var isTranscriptSearchFocused: Bool
    @State private var pendingTranscriptScrollTarget: UUID?
    @State private var highlightedTranscriptSegment: UUID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            workspaceSubToolbar
            OMHairline()

            if isSummaryPresented, note.enhancedNote != nil {
                summaryView
            } else {
                HStack(spacing: 0) {
                    workspaceTranscriptColumn
                        .frame(width: 360, alignment: .topLeading)
                    OMHairline(.vertical)
                    workspaceNotesColumn
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    OMHairline(.vertical)
                    workspaceChatColumn
                        .frame(width: 340, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .background(Color.om.paper)
        .alert("Delete note?", isPresented: $isDeleteConfirmationPresented) {
            Button("Delete", role: .destructive) { deleteNote() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the note and any saved local recording for it.")
        }
        .onChange(of: note.id) { _, _ in
            assistantPrompt = ""
            isSummaryPresented = false
        }
    }

    private var workspaceSubToolbar: some View {
        HStack(spacing: 10) {
            OMButton(variant: .secondary) {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
            }

            if note.captureState.phase == .capturing {
                recordingStateChip
                Rectangle()
                    .fill(Color.om.line)
                    .frame(width: 1, height: 16)
            }

            Text(note.title)
                .font(.om.rowTitle)
                .foregroundStyle(Color.om.ink)
                .lineLimit(1)

            if let line = subToolbarMetaLine {
                Rectangle()
                    .fill(Color.om.line)
                    .frame(width: 1, height: 14)
                Text(line)
                    .font(.om.meta)
                    .foregroundStyle(Color.om.ink3)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            OMButton(variant: .secondary) {
                retryGeneration()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles").font(.system(size: 10))
                    Text("Summarize")
                }
            }
            .disabled(!canRetryGeneration)

            OMButton(variant: .secondary) {
                submitAssistantDraftAction(.actionItems)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle").font(.system(size: 10))
                    Text("Extract actions")
                }
            }

            OMButton(variant: .secondary) {} label: {
                HStack(spacing: 5) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 10))
                    Text("Share")
                }
            }

            if note.enhancedNote != nil {
                OMButton(
                    isSummaryPresented ? "Workspace" : "Summary",
                    variant: isSummaryPresented ? .secondary : .primary
                ) {
                    isSummaryPresented.toggle()
                }
            }

            Menu {
                Button(role: .destructive) {
                    isDeleteConfirmationPresented = true
                } label: {
                    Label("Delete note", systemImage: "trash")
                }
                .disabled(!canDeleteNote)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.om.ink3)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.om.paper2)
    }

    private var recordingStateChip: some View {
        HStack(spacing: 6) {
            OMRecDot(size: 7)
            Text("Recording")
                .font(.om.meta)
                .fontWeight(.semibold)
                .foregroundStyle(Color.om.recDot)
            if let startedAt = note.captureState.startedAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(captureElapsedLabel(from: startedAt, now: context.date))
                        .font(.om.meta)
                        .monospacedDigit()
                        .foregroundStyle(Color.om.recDot.opacity(0.8))
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.om.recDot.opacity(0.10)))
    }

    private func captureElapsedLabel(from start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private var subToolbarMetaLine: String? {
        guard let attendees = note.calendarEvent?.attendees.map(\.name), !attendees.isEmpty else {
            return nil
        }
        if attendees.count == 1 { return attendees[0] }
        if attendees.count == 2 { return attendees.joined(separator: ", ") }
        return "\(attendees[0]), \(attendees[1]) +\(attendees.count - 2)"
    }

    // MARK: - Column 1: Transcript

    private var workspaceTranscriptColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                OMEyebrow("Transcript")
                Spacer()
                HStack(spacing: 6) {
                    transcriptSpeakerMenu
                    OMButton(
                        "Search",
                        variant: isTranscriptSearchVisible ? .primary : .secondary
                    ) {
                        isTranscriptSearchVisible.toggle()
                        if isTranscriptSearchVisible {
                            isTranscriptSearchFocused = true
                        } else {
                            transcriptSearchText = ""
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            OMHairline()

            if isTranscriptSearchVisible {
                transcriptSearchBar
                OMHairline()
            }

            if !transcriptSpeakerFilter.isEmpty || !trimmedTranscriptSearch.isEmpty {
                transcriptFilterStatusRow
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let segments = filteredTranscriptSegments
                        if segments.isEmpty && !note.transcriptSegments.isEmpty {
                            transcriptNoMatchesHint
                        } else if note.transcriptSegments.isEmpty {
                            transcriptEmptyHint
                        } else {
                            ForEach(segments) { segment in
                                transcriptSegmentRow(segment)
                                    .id(segment.id)
                            }
                        }
                        if note.captureState.phase == .capturing {
                            liveCaretRow
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollIndicators(.hidden)
                .onChange(of: pendingTranscriptScrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                    pendingTranscriptScrollTarget = nil
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.om.paper)
    }

    private var transcriptSpeakerMenu: some View {
        let speakers = transcriptSpeakerOptions
        let activeCount = transcriptSpeakerFilter.count
        return Menu {
            Button {
                transcriptSpeakerFilter.removeAll()
            } label: {
                if transcriptSpeakerFilter.isEmpty {
                    Label("All speakers", systemImage: "checkmark")
                } else {
                    Text("All speakers")
                }
            }
            if !speakers.isEmpty {
                Divider()
                ForEach(speakers, id: \.self) { name in
                    Button {
                        if transcriptSpeakerFilter.contains(name) {
                            transcriptSpeakerFilter.remove(name)
                        } else {
                            transcriptSpeakerFilter.insert(name)
                        }
                    } label: {
                        if transcriptSpeakerFilter.contains(name) {
                            Label(name, systemImage: "checkmark")
                        } else {
                            Text(name)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(activeCount == 0 ? "Speakers" : "Speakers · \(activeCount)")
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .font(.om.button)
            .foregroundStyle(activeCount == 0 ? Color.om.ink2 : Color.om.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(activeCount == 0 ? Color.om.card : Color.om.paper3, in: RoundedRectangle(cornerRadius: OMRadius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: OMRadius.sm)
                    .strokeBorder(Color.om.line, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(speakers.isEmpty)
    }

    private var transcriptSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Color.om.ink3)
            TextField("Search transcript…", text: $transcriptSearchText)
                .textFieldStyle(.plain)
                .font(.om.body)
                .foregroundStyle(Color.om.ink)
                .focused($isTranscriptSearchFocused)
                .onSubmit { isTranscriptSearchFocused = false }
            if !transcriptSearchText.isEmpty {
                Button {
                    transcriptSearchText = ""
                    isTranscriptSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.om.ink3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.om.paper2)
    }

    private var transcriptFilterStatusRow: some View {
        let matches = filteredTranscriptSegments.count
        let total = note.transcriptSegments.count
        return HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 11))
                .foregroundStyle(Color.om.ink3)
            Text("\(matches) of \(total) lines")
                .font(.om.meta)
                .foregroundStyle(Color.om.ink3)
            Spacer()
            Button {
                transcriptSpeakerFilter.removeAll()
                transcriptSearchText = ""
            } label: {
                Text("Clear")
                    .font(.om.meta)
                    .foregroundStyle(Color.om.ink2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Color.om.paper2.opacity(0.6))
    }

    private var transcriptNoMatchesHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No matching lines.")
                .font(.om.body)
                .foregroundStyle(Color.om.ink3)
            Text("Adjust the speaker filter or search above.")
                .font(.om.caption)
                .foregroundStyle(Color.om.ink4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 14)
    }

    private var transcriptSpeakerOptions: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for segment in note.transcriptSegments {
            let name = segment.speakerName ?? ""
            guard !name.isEmpty, !seen.contains(name) else { continue }
            seen.insert(name)
            ordered.append(name)
        }
        return ordered
    }

    private var trimmedTranscriptSearch: String {
        transcriptSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredTranscriptSegments: [TranscriptSegment] {
        let query = trimmedTranscriptSearch
        let speakers = transcriptSpeakerFilter
        guard !query.isEmpty || !speakers.isEmpty else {
            return note.transcriptSegments
        }
        return note.transcriptSegments.filter { segment in
            let speakerName = segment.speakerName ?? ""
            if !speakers.isEmpty, !speakers.contains(speakerName) {
                return false
            }
            if !query.isEmpty,
               !segment.text.localizedCaseInsensitiveContains(query),
               !speakerName.localizedCaseInsensitiveContains(query) {
                return false
            }
            return true
        }
    }

    private func transcriptSegmentRow(_ segment: TranscriptSegment) -> some View {
        let isHighlighted = highlightedTranscriptSegment == segment.id
        return HStack(alignment: .top, spacing: 10) {
            Text(transcriptTimeLabel(for: segment))
                .font(.om.meta)
                .monospacedDigit()
                .foregroundStyle(Color.om.ink4)
                .frame(width: 44, alignment: .leading)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(segment.speakerName ?? "Speaker")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OatmealSpeakerColor.color(for: segment.speakerName ?? ""))
                Text(segment.text)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.om.ink2)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OMRadius.sm)
                .fill(isHighlighted ? Color.om.honey.opacity(0.18) : Color.clear)
        )
        .animation(.easeOut(duration: 0.35), value: isHighlighted)
    }

    private var liveCaretRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("•••")
                .font(.om.meta)
                .foregroundStyle(Color.om.ink4)
                .frame(width: 44, alignment: .leading)
            HStack(spacing: 8) {
                OMWaveform(barCount: 5, tint: Color.om.ink3)
                Text("transcribing locally…")
                    .font(.system(size: 12))
                    .italic()
                    .foregroundStyle(Color.om.ink3)
            }
        }
        .opacity(0.6)
    }

    private var transcriptEmptyHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No transcript yet.")
                .font(.om.body)
                .foregroundStyle(Color.om.ink3)
            Text("Once audio is captured, Oatmeal transcribes locally and lines appear here.")
                .font(.om.caption)
                .foregroundStyle(Color.om.ink4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 14)
    }

    private func transcriptTimeLabel(for segment: TranscriptSegment) -> String {
        guard let start = segment.startTime,
              let noteStart = note.captureState.startedAt ?? note.calendarEvent?.startDate
        else { return "--:--" }
        let seconds = max(0, Int(start.timeIntervalSince(noteStart)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Column 2: Notes

    private var workspaceNotesColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OMEyebrow("Notes · Written by Oatmeal")
                Text(note.title)
                    .font(OatmealTypography.serif(42))
                    .kerning(-0.84)
                    .foregroundStyle(Color.om.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                Text(notesMetaLine)
                    .font(.om.meta)
                    .foregroundStyle(Color.om.ink3)
                    .padding(.top, 10)

                if let enhanced = note.enhancedNote {
                    if !enhanced.decisions.isEmpty {
                        notesSectionWithBullets(title: "Decisions", items: enhanced.decisions)
                    }
                    if !enhanced.summary.isEmpty {
                        notesSectionWithParagraphs(title: "Discussion", paragraphs: splitParagraphs(enhanced.summary))
                    }
                    if !enhanced.keyDiscussionPoints.isEmpty {
                        notesSectionWithBullets(title: "Key discussion", items: enhanced.keyDiscussionPoints)
                    }
                    if !enhanced.risksOrOpenQuestions.isEmpty {
                        notesSectionWithBullets(title: "Risks & open questions", items: enhanced.risksOrOpenQuestions)
                    }
                    if !enhanced.actionItems.isEmpty {
                        inlineActionItemsCard(enhanced.actionItems)
                            .padding(.top, 32)
                    }
                } else {
                    notesPlaceholder
                        .padding(.top, 32)
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 56)
            .padding(.vertical, 32)
        }
        .scrollIndicators(.hidden)
        .background(Color.om.card)
    }

    private var notesMetaLine: String {
        let start = note.captureState.startedAt ?? note.calendarEvent?.startDate ?? note.createdAt
        let dateText = start.formatted(
            .dateTime
                .weekday(.abbreviated)
                .month(.abbreviated)
                .day()
        )
        var parts = [dateText]
        if let minutes = durationMinutes {
            parts.append("\(minutes)m")
        }
        if let attendees = note.calendarEvent?.attendees, !attendees.isEmpty {
            parts.append(attendees.count == 1 ? attendees[0].name : "\(attendees.count) people")
        }
        parts.append("Recorded locally")
        return parts.joined(separator: " · ")
    }

    private var durationMinutes: Int? {
        guard let start = note.captureState.startedAt ?? note.calendarEvent?.startDate,
              let end = note.captureState.endedAt ?? note.calendarEvent?.endDate
        else { return nil }
        let m = max(0, Int(end.timeIntervalSince(start) / 60))
        return m == 0 ? nil : m
    }

    @ViewBuilder
    private func notesSectionWithBullets(title: String, items: [String]) -> some View {
        notesSectionHeader(title)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, text in
                HStack(alignment: .top, spacing: 10) {
                    Text("•")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.om.oat)
                    Text(text)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.om.ink)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.top, 10)
    }

    @ViewBuilder
    private func notesSectionWithParagraphs(title: String, paragraphs: [String]) -> some View {
        notesSectionHeader(title)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, text in
                Text(text)
                    .font(.om.bodyParagraph)
                    .foregroundStyle(Color.om.ink2)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 12)
    }

    private func notesSectionHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color.om.line)
                .frame(height: 1)
                .padding(.top, 28)
            Text(title)
                .font(.om.sectionTitle)
                .foregroundStyle(Color.om.ink)
                .padding(.top, 16)
        }
    }

    private func splitParagraphs(_ text: String) -> [String] {
        text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var notesPlaceholder: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes will appear here once Oatmeal finishes writing them.")
                .font(.om.bodyParagraph)
                .foregroundStyle(Color.om.ink3)
            Text("Recording continues in the background; you can close this window at any time.")
                .font(.om.caption)
                .foregroundStyle(Color.om.ink4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func inlineActionItemsCard(_ items: [ActionItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.om.ink3)
                    Text("Action items")
                        .font(.om.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.om.ink)
                }
                Spacer()
                Text("\(items.filter { $0.status == .open }.count) open")
                    .font(.om.meta)
                    .foregroundStyle(Color.om.ink3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Rectangle().fill(Color.om.line).frame(height: 1)

            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                if idx > 0 {
                    Rectangle().fill(Color.om.line).frame(height: 1)
                }
                actionItemCardRow(item)
            }
        }
        .background(Color.om.paper2)
        .overlay(
            RoundedRectangle(cornerRadius: OMRadius.md)
                .strokeBorder(Color.om.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: OMRadius.md))
    }

    private func actionItemCardRow(_ item: ActionItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Color.om.ink3, lineWidth: 1.2)
                .frame(width: 14, height: 14)
                .overlay {
                    if item.status == .done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.om.sage2)
                    }
                }
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.text)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.om.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if let assignee = item.assignee, !assignee.isEmpty {
                        Text(assignee)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(OatmealSpeakerColor.color(for: assignee))
                    } else {
                        Text("Unassigned")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.om.ink4)
                    }
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.om.ink3)
                    if let due = item.dueDate {
                        Text(due.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.om.meta)
                            .foregroundStyle(Color.om.ink3)
                    } else {
                        Text("No due date")
                            .font(.om.meta)
                            .foregroundStyle(Color.om.ink4)
                    }
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Column 3: Chat

    private var workspaceChatColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                OatLeafMark(size: 14, tint: Color.om.oat2)
                Text("Ask this meeting")
                    .font(.om.sectionTitle)
                    .foregroundStyle(Color.om.ink)
                Spacer()
                OMKbd("⌘J")
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)

            Text("Grounded in this transcript. Never leaves your Mac.")
                .font(.system(size: 11))
                .foregroundStyle(Color.om.ink3)
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 14)

            OMHairline()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if note.assistantThread.turns.isEmpty {
                        chatEmptyHint
                    } else {
                        ForEach(note.assistantThread.turns) { turn in
                            chatTurn(turn)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)

            OMHairline()
            chatSuggestionChips
            chatComposer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.om.paper)
    }

    private var chatEmptyHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing yet.")
                .font(.om.body)
                .foregroundStyle(Color.om.ink3)
            Text("Ask a question below and Oatmeal will answer using the transcript only.")
                .font(.om.caption)
                .foregroundStyle(Color.om.ink4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func chatTurn(_ turn: NoteAssistantTurn) -> some View {
        Text(turn.prompt)
            .font(.system(size: 13))
            .foregroundStyle(Color.om.paper)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                UnevenRoundedRectangle(
                    cornerRadii: .init(topLeading: 12, bottomLeading: 12, bottomTrailing: 3, topTrailing: 12)
                )
                .fill(Color.om.ink)
            )
            .frame(maxWidth: 240, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)

        if let response = turn.response, !response.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(response)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.om.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        UnevenRoundedRectangle(
                            cornerRadii: .init(topLeading: 12, bottomLeading: 3, bottomTrailing: 12, topTrailing: 12)
                        )
                        .fill(Color.om.card)
                    )
                    .overlay(
                        UnevenRoundedRectangle(
                            cornerRadii: .init(topLeading: 12, bottomLeading: 3, bottomTrailing: 12, topTrailing: 12)
                        )
                        .strokeBorder(Color.om.line, lineWidth: 1)
                    )
                if !turn.citations.isEmpty {
                    citationRow(turn.citations)
                }
            }
            .frame(maxWidth: 290, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if turn.status == .pending {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Thinking…")
                    .font(.om.caption)
                    .foregroundStyle(Color.om.ink3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let failure = turn.failureMessage {
            Text(failure)
                .font(.om.caption)
                .foregroundStyle(Color.om.ember)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func citationRow(_ citations: [NoteAssistantCitation]) -> some View {
        HStack(spacing: 6) {
            ForEach(citations) { citation in
                CitationPill(
                    speakerName: citationSpeakerName(citation),
                    timestamp: citationTimestamp(citation),
                    style: .workspace,
                    action: citation.transcriptSegmentID.map { id in
                        { jumpToTranscriptSegment(id) }
                    }
                )
            }
        }
    }

    private func jumpToTranscriptSegment(_ id: UUID) {
        guard note.transcriptSegments.contains(where: { $0.id == id }) else { return }
        if !transcriptSpeakerFilter.isEmpty || !trimmedTranscriptSearch.isEmpty {
            transcriptSpeakerFilter.removeAll()
            transcriptSearchText = ""
        }
        pendingTranscriptScrollTarget = id
        withAnimation(.easeOut(duration: 0.25)) {
            highlightedTranscriptSegment = id
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            if highlightedTranscriptSegment == id {
                withAnimation(.easeOut(duration: 0.4)) {
                    highlightedTranscriptSegment = nil
                }
            }
        }
    }

    private func citationSpeakerName(_ citation: NoteAssistantCitation) -> String {
        if let id = citation.transcriptSegmentID,
           let seg = note.transcriptSegments.first(where: { $0.id == id }),
           let name = seg.speakerName, !name.isEmpty {
            return name
        }
        return citation.label.isEmpty ? "Speaker" : citation.label
    }

    private func citationTimestamp(_ citation: NoteAssistantCitation) -> String {
        guard let id = citation.transcriptSegmentID,
              let seg = note.transcriptSegments.first(where: { $0.id == id }),
              let start = seg.startTime,
              let noteStart = note.captureState.startedAt ?? note.calendarEvent?.startDate
        else { return citation.label }
        let seconds = max(0, Int(start.timeIntervalSince(noteStart)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private let chatSuggestions = [
        "Summarize in 3 bullets",
        "What did I commit to?",
        "Draft follow-up email"
    ]

    private var chatSuggestionChips: some View {
        HStack(spacing: 6) {
            ForEach(chatSuggestions, id: \.self) { suggestion in
                Button {
                    assistantPrompt = suggestion
                } label: {
                    Text(suggestion)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.om.ink2)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.om.paper2, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.om.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var chatComposer: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12))
                .foregroundStyle(Color.om.oat2)
            TextField("Ask this meeting…", text: $assistantPrompt)
                .textFieldStyle(.plain)
                .font(.om.body)
                .foregroundStyle(Color.om.ink)
                .onSubmit { submitPrompt() }
            Button {
                submitPrompt()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.om.paper)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle().fill(
                            assistantPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.om.ink3
                                : Color.om.ink
                        )
                    )
            }
            .buttonStyle(.plain)
            .disabled(assistantPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.om.card)
        .overlay(
            RoundedRectangle(cornerRadius: OMRadius.md)
                .strokeBorder(Color.om.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: OMRadius.md))
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    private func submitPrompt() {
        let trimmed = assistantPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        submitAssistantPrompt(trimmed)
        assistantPrompt = ""
    }

    private var summaryView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                summaryHeader
                OMHairline()
                HStack(alignment: .top, spacing: 40) {
                    summaryLeftColumn
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .layoutPriority(1.3)
                    summaryRightRail
                        .frame(width: 280, alignment: .topLeading)
                }
            }
            .padding(40)
            .frame(maxWidth: 980, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
        .background(Color.om.paper)
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            OMEyebrow(summaryHeaderEyebrow)
            Text(note.title)
                .font(.om.display)
                .foregroundStyle(Color.om.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Text(summaryMetaLine)
                    .font(.om.meta)
                    .foregroundStyle(Color.om.ink3)
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                    Text("Recorded locally")
                }
                .font(.om.meta)
                .foregroundStyle(Color.om.ink3)
            }
        }
    }

    private var summaryLeftColumn: some View {
        VStack(alignment: .leading, spacing: 32) {
            if let enhanced = note.enhancedNote, !enhanced.summary.isEmpty {
                HStack(alignment: .top, spacing: 16) {
                    Rectangle()
                        .fill(Color.om.oat)
                        .frame(width: 2)
                    Text(enhanced.summary)
                        .font(.om.pullQuote)
                        .foregroundStyle(Color.om.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let decisions = note.enhancedNote?.decisions, !decisions.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    OMEyebrow("Decisions · \(decisions.count)")
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(decisions.enumerated()), id: \.offset) { index, text in
                            summaryDecisionRow(index: index + 1, text: text)
                        }
                    }
                }
            }

            if !summaryTopics.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    OMEyebrow("Topics · \(summaryTopics.count)")
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(summaryTopics.enumerated()), id: \.offset) { index, topic in
                            if index > 0 {
                                Rectangle().fill(Color.om.line).frame(height: 1)
                            }
                            summaryTopicRow(topic)
                                .padding(.vertical, 14)
                        }
                    }
                }
            }
        }
    }

    private var summaryRightRail: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let enhanced = note.enhancedNote, !enhanced.actionItems.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.om.ink3)
                        Text("Action items")
                            .font(.om.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.om.ink)
                        Spacer()
                        Text("\(enhanced.actionItems.filter { $0.status == .open }.count) open")
                            .font(.om.meta)
                            .foregroundStyle(Color.om.ink3)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    Rectangle().fill(Color.om.line).frame(height: 1)

                    ForEach(Array(enhanced.actionItems.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Rectangle().fill(Color.om.line).frame(height: 1)
                        }
                        summaryActionItemRow(item)
                    }
                }
                .background(Color.om.card)
                .overlay(
                    RoundedRectangle(cornerRadius: OMRadius.md)
                        .strokeBorder(Color.om.line, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: OMRadius.md))
            }

            if !speakerShares.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    OMEyebrow("Speakers")
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(speakerShares, id: \.name) { share in
                            summarySpeakerRow(share)
                        }
                    }
                }
                .padding(16)
                .background(Color.om.paper2)
                .overlay(
                    RoundedRectangle(cornerRadius: OMRadius.md)
                        .strokeBorder(Color.om.line, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: OMRadius.md))
            }
        }
    }

    private func summaryActionItemRow(_ item: ActionItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Color.om.ink3, lineWidth: 1.2)
                .frame(width: 14, height: 14)
                .overlay {
                    if item.status == .done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.om.sage2)
                    }
                }
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.text)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.om.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if let assignee = item.assignee, !assignee.isEmpty {
                        Text(assignee)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(OatmealSpeakerColor.color(for: assignee))
                    } else {
                        Text("Unassigned")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.om.ink4)
                    }
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.om.ink3)
                    if let due = item.dueDate {
                        Text(due.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.om.meta)
                            .foregroundStyle(Color.om.ink3)
                    } else {
                        Text("No due date")
                            .font(.om.meta)
                            .foregroundStyle(Color.om.ink4)
                    }
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func summaryDecisionRow(index: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(index)")
                .font(.om.meta)
                .fontWeight(.bold)
                .foregroundStyle(Color.white)
                .frame(width: 22, height: 22)
                .background(Color.om.oat, in: Circle())
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Color.om.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    private func summaryTopicRow(_ topic: SummaryTopic) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(topic.title)
                    .font(.om.rowTitle)
                    .foregroundStyle(Color.om.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 10)
                Text(topic.timeLabel ?? "—")
                    .font(.om.meta)
                    .foregroundStyle(Color.om.ink3)
            }
            if let excerpt = topic.excerpt {
                Text(excerpt)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.om.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func summarySpeakerRow(_ share: SpeakerShare) -> some View {
        HStack(spacing: 10) {
            Text(share.name)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(OatmealSpeakerColor.color(for: share.name))
                .lineLimit(1)
                .frame(width: 90, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.om.line)
                    Capsule()
                        .fill(OatmealSpeakerColor.color(for: share.name))
                        .frame(width: geo.size.width * CGFloat(share.fraction))
                }
            }
            .frame(height: 4)
            Text(share.percentageLabel)
                .font(.om.meta)
                .foregroundStyle(Color.om.ink3)
                .frame(width: 34, alignment: .trailing)
        }
    }

    private var summaryHeaderEyebrow: String {
        let dateText = (note.calendarEvent?.startDate ?? note.createdAt)
            .formatted(date: .abbreviated, time: .omitted)
        var parts = ["Meeting", dateText]
        if let folder, !folder.name.isEmpty {
            parts.append(folder.name)
        }
        return parts.joined(separator: " · ")
    }

    private var summaryMetaLine: String {
        let start = (note.calendarEvent?.startDate ?? note.captureState.startedAt ?? note.createdAt)
            .formatted(date: .omitted, time: .shortened)
        var parts = [start]
        if let attendees = note.calendarEvent?.attendees.map(\.name), !attendees.isEmpty {
            parts.append(attendees.count == 1 ? attendees[0] : "\(attendees.count) people")
        }
        if let duration = summaryDurationLabel {
            parts.append(duration)
        }
        return parts.joined(separator: " · ")
    }

    private var summaryDurationLabel: String? {
        guard
            let start = note.captureState.startedAt ?? note.calendarEvent?.startDate,
            let end = note.captureState.endedAt ?? note.calendarEvent?.endDate
        else { return nil }
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        if minutes == 0 { return nil }
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    private struct SummaryTopic {
        let title: String
        let excerpt: String?
        let timeLabel: String?
    }

    private var summaryTopics: [SummaryTopic] {
        guard let enhanced = note.enhancedNote else { return [] }
        return enhanced.keyDiscussionPoints.map { point in
            SummaryTopic(title: point, excerpt: nil, timeLabel: nil)
        }
    }

    private struct SpeakerShare {
        let name: String
        let fraction: Double
        let percentageLabel: String
    }

    private var speakerShares: [SpeakerShare] {
        var durations: [String: TimeInterval] = [:]
        var counts: [String: Int] = [:]
        for segment in note.transcriptSegments {
            let name = segment.speakerName ?? "Speaker"
            counts[name, default: 0] += 1
            if let start = segment.startTime, let end = segment.endTime {
                durations[name, default: 0] += max(0, end.timeIntervalSince(start))
            }
        }
        let totalDuration = durations.values.reduce(0, +)
        let totalCount = counts.values.reduce(0, +)

        let base: [(String, Double)]
        if totalDuration > 0 {
            base = durations.map { ($0.key, $0.value / totalDuration) }
        } else if totalCount > 0 {
            base = counts.map { ($0.key, Double($0.value) / Double(totalCount)) }
        } else {
            return []
        }

        return base
            .sorted { $0.1 > $1.1 }
            .map { name, fraction in
                SpeakerShare(
                    name: name,
                    fraction: fraction,
                    percentageLabel: "\(Int((fraction * 100).rounded()))%"
                )
            }
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
