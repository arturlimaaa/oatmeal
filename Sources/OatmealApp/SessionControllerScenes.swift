import SwiftUI

enum OatmealSceneID {
    static let main = "oatmeal-main"
    static let sessionController = "oatmeal-session-controller"
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
            } else {
                idleSummary
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Button("Open Oatmeal") {
                    _ = router.openMainWindow()
                }

                if let controllerState = model.sessionControllerState {
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

    let state: SessionControllerState

    var body: some View {
        VStack(alignment: .leading, spacing: isCollapsed ? 12 : 14) {
            header

            if isCollapsed {
                compactSummary
            } else {
                expandedSummary
            }
        }
        .padding(16)
        .frame(
            minWidth: isCollapsed ? 300 : 340,
            idealWidth: isCollapsed ? 320 : 360,
            maxWidth: isCollapsed ? 340 : 380
        )
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .padding(8)
        .animation(.easeInOut(duration: 0.18), value: isCollapsed)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: state.menuBarSymbolName)
                        .foregroundStyle(color(for: state.tone))
                    Text(state.title)
                        .font(.headline)
                        .lineLimit(2)
                }

                if let detailText = nonBlank(state.detailText) {
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    if let elapsedText = state.elapsedText() {
                        Text(elapsedText)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        model.toggleSessionControllerCollapsed()
                    } label: {
                        Image(systemName: isCollapsed ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button {
                        model.dismissSessionController()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var expandedSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusCallout
            primaryBadges
            sourceBadges

            if state.showsProcessingIndicator {
                Label(
                    state.processingLabel ?? "Background processing is still running.",
                    systemImage: "gearshape.2.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            actionRow
        }
    }

    private var compactSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            compactStatusHeader

            compactBadgeStrip

            if state.showsProcessingIndicator {
                Text(state.processingLabel ?? "Finishing background work")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            compactActionRow
        }
    }

    private var compactStatusHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: state.controllerStatusSymbolName)
                .font(.headline)
                .foregroundStyle(color(for: state.tone))

            VStack(alignment: .leading, spacing: 4) {
                Text(state.controllerStatusTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(state.compactStatusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let lifecycleText = state.lifecycleTimestampText() {
                    Text(lifecycleText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statusCallout: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: state.controllerStatusSymbolName)
                .font(.title3)
                .foregroundStyle(color(for: state.tone))
                .frame(width: 28, height: 28)
                .background(color(for: state.tone).opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(state.controllerStatusTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if let detailText = nonBlank(state.controllerStatusDetail) {
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let lifecycleText = state.lifecycleTimestampText() {
                    Text(lifecycleText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(color(for: state.tone).opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color(for: state.tone).opacity(0.18), lineWidth: 1)
        )
    }

    private var primaryBadges: some View {
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

    private var sourceBadges: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(state.sourceStatuses) { source in
                HStack(spacing: 8) {
                    SessionControllerBadge(
                        title: source.title,
                        value: source.label,
                        tone: source.tone
                    )

                    if let detailText = nonBlank(source.detailText) {
                        Text(detailText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    private var compactBadgeStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
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

            HStack(spacing: 8) {
                ForEach(state.sourceStatuses) { source in
                    SessionControllerMiniBadge(
                        title: source.title,
                        value: source.label,
                        tone: source.tone
                    )
                }
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            if state.canStopCapture {
                Button("Stop Capture", role: .destructive) {
                    Task {
                        await router.stopCapture()
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            Button(state.primaryActionTitle) {
                _ = router.openMainWindow()
            }
            .buttonStyle(.bordered)

            if state.canOpenTranscript {
                Button(state.transcriptActionTitle) {
                    _ = router.openMainWindow(openTranscript: true)
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
    }

    private var compactActionRow: some View {
        HStack(spacing: 8) {
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

            if state.canOpenTranscript {
                Button(state.transcriptActionTitle) {
                    _ = router.openMainWindow(openTranscript: true)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Spacer()
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
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
    }

    private var color: Color {
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
        .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 1))
    }

    private var color: Color {
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
}

private func nonBlank(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
        return nil
    }
    return value
}
