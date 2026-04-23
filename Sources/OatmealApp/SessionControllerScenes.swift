import OatmealCore
import SwiftUI

enum OatmealSceneID {
    static let main = "oatmeal-main"
    static let sessionController = "oatmeal-session-controller"
    static let meetingDetectionPrompt = "oatmeal-meeting-detection-prompt"
}

struct OatmealMenuBarContent: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

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
        VStack(alignment: .leading, spacing: 16) {
            if let state = model.menuBarSessionState {
                sessionSummary(state)
                if let detectionState = model.menuBarMeetingDetectionState,
                   detectionState.phase == .endSuggestion {
                    Divider()
                    detectionSummary(detectionState)
                }
            } else if let detectionState = model.menuBarMeetingDetectionState {
                detectionSummary(detectionState)
            } else {
                idleSummary
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Button("Open Oatmeal") {
                    _ = router.openMainWindow()
                }

                if let controllerState = model.sessionControllerState {
                    if let detectionState = model.menuBarMeetingDetectionState,
                       detectionState.phase == .endSuggestion {
                        Button(detectionState.primaryActionTitle, role: .destructive) {
                            Task {
                                await router.startPendingMeetingDetection()
                            }
                        }

                        if let secondaryActionTitle = detectionState.secondaryActionTitle {
                            Button(secondaryActionTitle) {
                                router.ignorePendingMeetingDetection()
                            }
                        }
                    }

                    Button("Reopen Session Controller") {
                        router.reopenSessionController()
                    }

                    Button("Open Live Transcript") {
                        _ = router.openMainWindow(openTranscript: true)
                    }
                    .disabled(!controllerState.canOpenTranscript)

                    if controllerState.canStopCapture {
                        Button("Stop Capture", role: .destructive) {
                            Task {
                                await router.stopCapture()
                            }
                        }
                    }
                } else if let state = model.menuBarSessionState {
                    Button("Open Live Transcript") {
                        _ = router.openMainWindow(openTranscript: true)
                    }
                    .disabled(!state.canOpenTranscript)

                    Button("Start Quick Note") {
                        Task {
                            await router.startQuickNoteCapture()
                        }
                    }
                } else if let detectionState = model.menuBarMeetingDetectionState {
                    Button(detectionState.primaryActionTitle) {
                        Task {
                            await router.startPendingMeetingDetection()
                        }
                    }

                    if model.detectionPromptState != nil {
                        Button("Not now") {
                            router.ignorePendingMeetingDetection()
                        }
                    }

                    Button("Start Quick Note") {
                        Task {
                            await router.startQuickNoteCapture()
                        }
                    }
                } else {
                    Button("Start Quick Note") {
                        Task {
                            await router.startQuickNoteCapture()
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
    }

    @ViewBuilder
    private func sessionSummary(_ state: SessionControllerState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label {
                    Text(state.menuBarSectionTitle)
                        .font(.headline)
                } icon: {
                    Image(systemName: state.menuBarSymbolName)
                        .foregroundStyle(color(for: state.tone))
                }

                Spacer()

                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    if let elapsedText = state.elapsedText() {
                        Text(elapsedText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(state.title)
                .font(.title3.weight(.semibold))
                .lineLimit(2)

            Text(state.menuBarSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Image(systemName: state.controllerStatusSymbolName)
                    .foregroundStyle(color(for: state.tone))
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.controllerStatusTitle)
                        .font(.caption.weight(.semibold))
                    if let lifecycleText = state.lifecycleTimestampText() {
                        Text(lifecycleText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 8) {
                SessionControllerBadge(
                    title: "Session",
                    value: state.healthLabel,
                    tone: state.tone
                )

                SessionControllerBadge(
                    title: "Capture",
                    value: state.captureLabel,
                    tone: state.kind == .processing ? .neutral : state.tone
                )
            }
        }
    }

    private func detectionSummary(_ state: MeetingDetectionPromptState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(state.headline)
                    .font(.headline)
            } icon: {
                Image(systemName: state.symbolName)
                    .foregroundStyle(state.phase == .endSuggestion ? .pink : .orange)
            }

            Text(state.title)
                .font(.title3.weight(.semibold))
                .lineLimit(2)

            Text(state.menuBarSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                SessionControllerBadge(
                    title: "Source",
                    value: state.sourceName,
                    tone: .delayed
                )

                SessionControllerBadge(
                    title: "State",
                    value: detectionStateLabel(for: state),
                    tone: state.phase == .endSuggestion
                        ? .failed
                        : (state.kind == .prompt ? .live : .neutral)
                )
            }
        }
    }

    private var idleSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Oatmeal")
                    .font(.headline)
            } icon: {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.secondary)
            }

            Text("No active session")
                .font(.title3.weight(.semibold))

            Text("Start a Quick Note here, or open the main app to work with calendar-backed meetings and existing notes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func color(for tone: SessionControllerState.Tone) -> Color {
        switch tone {
        case .live:
            .red
        case .delayed:
            .orange
        case .recovered:
            .blue
        case .failed:
            .pink
        case .neutral:
            .secondary
        }
    }

    private func detectionStateLabel(for state: MeetingDetectionPromptState) -> String {
        if state.phase == .endSuggestion {
            return state.kind == .prompt ? "Stop hint" : "Passive hint"
        }

        return state.kind == .prompt ? "Prompting" : "Passive"
    }
}

struct SessionControllerWindowRootView: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            if let state = model.sessionControllerState, !model.isSessionControllerDismissedForCurrentState {
                FloatingSessionControllerView(state: state)
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
            }
        }
        .task {
            dismissIfNeeded()
        }
        .onChange(of: model.sessionControllerState) { _, _ in
            dismissIfNeeded()
        }
        .onChange(of: model.isSessionControllerDismissedForCurrentState) { _, _ in
            dismissIfNeeded()
        }
    }

    private func dismissIfNeeded() {
        guard model.sessionControllerState == nil || model.isSessionControllerDismissedForCurrentState else {
            return
        }

        dismissWindow(id: OatmealSceneID.sessionController)
    }
}

struct MeetingDetectionPromptWindowRootView: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            if let state = model.detectionPromptState {
                FloatingMeetingDetectionPromptView(state: state)
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
            }
        }
        .task {
            dismissIfNeeded()
        }
        .onChange(of: model.detectionPromptState) { _, _ in
            dismissIfNeeded()
        }
    }

    private func dismissIfNeeded() {
        guard model.detectionPromptState == nil else {
            return
        }

        dismissWindow(id: OatmealSceneID.meetingDetectionPrompt)
    }
}

private struct FloatingSessionControllerView: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    private var coordinator: SessionControllerSceneCoordinator {
        SessionControllerSceneCoordinator(
            openWindow: { id in openWindow(id: id) },
            dismissWindow: { _ in }
        )
    }

    private var router: SessionControllerCommandRouter {
        SessionControllerCommandRouter(model: model, coordinator: coordinator)
    }

    private var isCollapsed: Bool {
        model.isSessionControllerCollapsed
    }

    private var currentNote: MeetingNote? {
        model.notes.first(where: { $0.id == state.noteID })
    }

    let state: SessionControllerState

    var body: some View {
        VStack(alignment: .leading, spacing: isCollapsed ? 10 : 16) {
            if isCollapsed {
                compactRecorderView
            } else {
                expandedMeetingView
            }
        }
        .padding(isCollapsed ? 14 : 18)
        .frame(
            minWidth: isCollapsed ? 276 : 372,
            idealWidth: isCollapsed ? 292 : 404,
            maxWidth: isCollapsed ? 308 : 428
        )
        .background(
            RoundedRectangle(cornerRadius: isCollapsed ? 22 : 24, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: isCollapsed ? 22 : 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 24, y: 14)
        .padding(8)
        .animation(.easeInOut(duration: 0.18), value: isCollapsed)
    }

    private var compactRecorderView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                recorderPill

                Spacer(minLength: 0)

                elapsedChip

                surfaceControlButton(
                    systemImage: "rectangle.expand.vertical",
                    accessibilityLabel: "Expand Recorder"
                ) {
                    model.toggleSessionControllerCollapsed()
                }

                surfaceControlButton(
                    systemImage: "xmark",
                    accessibilityLabel: "Dismiss Recorder"
                ) {
                    model.dismissSessionController()
                    dismiss()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(state.title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(2)

                Text(compactSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                if let firstSource = state.sourceStatuses.first {
                    SessionControllerMiniBadge(
                        title: firstSource.title,
                        value: firstSource.label,
                        tone: firstSource.tone
                    )
                }

                Spacer(minLength: 0)

                if state.canStopCapture {
                    Button("Stop", role: .destructive) {
                        Task {
                            await router.stopCapture()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Button("Open") {
                    _ = router.openMainWindow()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var expandedMeetingView: some View {
        VStack(alignment: .leading, spacing: 16) {
            expandedHeader
            recorderStrip
            endSuggestionCallout
            scratchpadCard
            transcriptPreviewCard

            if state.showsProcessingIndicator {
                processingRibbon
            }

            actionRail
        }
    }

    private var expandedHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(state.menuBarSectionTitle.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1.1)

                Text(state.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)

                Text(expandedSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 10) {
                elapsedChip

                HStack(spacing: 8) {
                    surfaceControlButton(
                        systemImage: "rectangle.compress.vertical",
                        accessibilityLabel: "Collapse Recorder"
                    ) {
                        model.toggleSessionControllerCollapsed()
                    }

                    surfaceControlButton(
                        systemImage: "xmark",
                        accessibilityLabel: "Dismiss Recorder"
                    ) {
                        model.dismissSessionController()
                        dismiss()
                    }
                }
            }
        }
    }

    private var recorderStrip: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(color(for: state.tone).opacity(0.14))
                        .frame(width: 44, height: 44)

                    Circle()
                        .fill(color(for: state.tone))
                        .frame(width: 12, height: 12)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(state.controllerStatusTitle)
                        .font(.headline)

                    if let detail = nonBlank(state.controllerStatusDetail) ?? nonBlank(state.detailText) {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let lifecycleText = state.lifecycleTimestampText() {
                        Text(lifecycleText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                SessionControllerMiniBadge(
                    title: "Session",
                    value: state.healthLabel,
                    tone: state.tone
                )

                SessionControllerMiniBadge(
                    title: "Capture",
                    value: state.captureLabel,
                    tone: state.kind == .processing ? .neutral : state.tone
                )

                ForEach(state.sourceStatuses) { source in
                    SessionControllerMiniBadge(
                        title: source.title,
                        value: source.label,
                        tone: source.tone
                    )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var endSuggestionCallout: some View {
        if let detectionState = model.menuBarMeetingDetectionState,
           detectionState.phase == .endSuggestion {
            VStack(alignment: .leading, spacing: 10) {
                Text(detectionState.headline.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.pink)
                    .tracking(1.0)

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: detectionState.symbolName)
                        .foregroundStyle(.pink)
                        .font(.headline)

                    Text(detectionState.detailText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Button(detectionState.primaryActionTitle, role: .destructive) {
                        Task {
                            await router.startPendingMeetingDetection()
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    if let secondaryActionTitle = detectionState.secondaryActionTitle {
                        Button(secondaryActionTitle) {
                            router.ignorePendingMeetingDetection()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.pink.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.pink.opacity(0.18), lineWidth: 1)
            )
        }
    }

    private var scratchpadCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            labelRow(title: "Scratchpad", caption: scratchpadCaption)

            Text(scratchpadPreview)
                .font(.callout)
                .foregroundStyle(nonBlank(currentNote?.rawNotes) == nil ? .secondary : .primary)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.36))
        )
    }

    private var transcriptPreviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            labelRow(title: "Transcript Preview", caption: transcriptCaption)

            if transcriptPreviewLines.isEmpty {
                Text(transcriptEmptyState)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(transcriptPreviewLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 2)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.36))
        )
    }

    private var processingRibbon: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .foregroundStyle(.secondary)

            Text(state.processingLabel ?? "Oatmeal is finishing the meeting note in the background.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.36), in: Capsule())
    }

    private var actionRail: some View {
        HStack(spacing: 10) {
            if state.canStopCapture {
                Button("Stop Capture", role: .destructive) {
                    Task {
                        await router.stopCapture()
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            Button("Open Note") {
                _ = router.openMainWindow()
            }
            .buttonStyle(.bordered)

            if state.canOpenTranscript {
                Button("Transcript") {
                    _ = router.openMainWindow(openTranscript: true)
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
    }

    private var compactSubtitle: String {
        if state.kind == .processing {
            return state.processingLabel ?? expandedSubtitle
        }
        return expandedSubtitle
    }

    private var expandedSubtitle: String {
        if let detail = nonBlank(state.detailText) {
            return detail
        }

        let sourceSummary = state.sourceStatuses
            .map { "\($0.title) \($0.label.lowercased())" }
            .joined(separator: " • ")

        if !sourceSummary.isEmpty {
            return sourceSummary
        }

        return state.menuBarSummary
    }

    private var scratchpadPreview: String {
        if let rawNotes = nonBlank(currentNote?.rawNotes) {
            return rawNotes
        }

        if state.canStopCapture {
            return "Use the main note window for longer notes. Oatmeal keeps this recorder small so you can stay in the meeting."
        }

        return "No scratchpad text yet. Open the full note if you want to add more context while Oatmeal finishes processing."
    }

    private var scratchpadCaption: String {
        nonBlank(currentNote?.rawNotes) == nil
            ? "Lightweight notes stay attached to this meeting."
            : "Raw notes from this meeting stay visible here."
    }

    private var transcriptPreviewLines: [String] {
        guard let note = currentNote else {
            return []
        }

        let liveLines = note.liveSessionState.previewEntries
            .suffix(3)
            .map(\.text)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if !liveLines.isEmpty {
            return liveLines
        }

        return note.transcriptSegments
            .suffix(3)
            .map(\.text)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var transcriptCaption: String {
        state.canOpenTranscript
            ? "A quick look at what Oatmeal is hearing."
            : "Live transcript snippets will show up here while recording."
    }

    private var transcriptEmptyState: String {
        if state.kind == .processing {
            return "Oatmeal is reconciling the final transcript from the saved recording."
        }

        return "Transcript updates will appear here as Oatmeal catches up."
    }

    private var recorderPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color(for: state.tone))
                .frame(width: 8, height: 8)
            Text(recorderPillText)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(color(for: state.tone).opacity(0.12), in: Capsule())
    }

    private var recorderPillText: String {
        switch state.kind {
        case .active:
            return state.controllerStatusTitle
        case .processing:
            return "Wrapping up"
        case .recent:
            return "Ready"
        }
    }

    private var elapsedChip: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Text(state.elapsedText() ?? "--:--")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.34), in: Capsule())
        }
    }

    private func labelRow(title: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1.0)

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func surfaceControlButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.34), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func color(for tone: SessionControllerState.Tone) -> Color {
        switch tone {
        case .live:
            Color(red: 0.84, green: 0.24, blue: 0.19)
        case .delayed:
            Color(red: 0.86, green: 0.55, blue: 0.17)
        case .recovered:
            Color(red: 0.22, green: 0.46, blue: 0.82)
        case .failed:
            Color(red: 0.78, green: 0.25, blue: 0.41)
        case .neutral:
            .secondary
        }
    }
}

private struct FloatingMeetingDetectionPromptView: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    private var coordinator: SessionControllerSceneCoordinator {
        SessionControllerSceneCoordinator(
            openWindow: { id in openWindow(id: id) },
            dismissWindow: { _ in }
        )
    }

    private var router: SessionControllerCommandRouter {
        SessionControllerCommandRouter(model: model, coordinator: coordinator)
    }

    let state: MeetingDetectionPromptState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            detail
            candidateChooser
            actions
        }
        .padding(16)
        .frame(minWidth: 300, idealWidth: 324, maxWidth: 340)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 24, y: 14)
        .padding(8)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.orange.opacity(0.14))
                    .frame(width: 38, height: 38)

                Image(systemName: state.symbolName)
                    .foregroundStyle(.orange)
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(state.headline.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1.0)
                Text(state.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
            }

            Spacer()
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 8) {
            SessionControllerMiniBadge(
                title: "Source",
                value: state.sourceName,
                tone: state.phase == .endSuggestion ? .failed : .delayed
            )

            Text(state.detailText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var candidateChooser: some View {
        if !state.candidateOptions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Choose the meeting")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(state.candidateOptions) { option in
                    candidateButton(option)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(state.primaryActionTitle) {
                Task {
                    await router.startPendingMeetingDetection()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!state.primaryActionEnabled)

            if let secondaryActionTitle = state.secondaryActionTitle {
                Button(secondaryActionTitle) {
                    router.ignorePendingMeetingDetection()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func candidateButton(_ option: MeetingDetectionCandidateOption) -> some View {
        let isSelected = state.selectedCandidateID == option.id

        return Button {
            router.selectPendingMeetingCandidate(option.id)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .font(.body)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(option.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()
            }
            .padding(10)
            .background(candidateBackgroundColor(isSelected), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func candidateBackgroundColor(_ isSelected: Bool) -> Color {
        isSelected ? Color.accentColor.opacity(0.14) : Color.white.opacity(0.36)
    }
}

private struct SessionControllerBadge: View {
    let title: String
    let value: String
    let tone: SessionControllerState.Tone

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(color.opacity(0.12), in: Capsule())
    }

    private var color: Color {
        switch tone {
        case .live:
            Color(red: 0.84, green: 0.24, blue: 0.19)
        case .delayed:
            Color(red: 0.86, green: 0.55, blue: 0.17)
        case .recovered:
            Color(red: 0.22, green: 0.46, blue: 0.82)
        case .failed:
            Color(red: 0.78, green: 0.25, blue: 0.41)
        case .neutral:
            .secondary
        }
    }
}

private struct SessionControllerMiniBadge: View {
    let title: String
    let value: String
    let tone: SessionControllerState.Tone

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text("\(title): \(value)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(color.opacity(0.12), in: Capsule())
    }

    private var color: Color {
        switch tone {
        case .live:
            Color(red: 0.84, green: 0.24, blue: 0.19)
        case .delayed:
            Color(red: 0.86, green: 0.55, blue: 0.17)
        case .recovered:
            Color(red: 0.22, green: 0.46, blue: 0.82)
        case .failed:
            Color(red: 0.78, green: 0.25, blue: 0.41)
        case .neutral:
            .secondary
        }
    }
}

private func nonBlank(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
        return nil
    }
    return value
}
