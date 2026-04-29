import OatmealCore
import SwiftUI

enum OatmealSceneID {
    static let main = "oatmeal-main"
    static let sessionController = "oatmeal-session-controller"
    static let meetingDetectionPrompt = "oatmeal-meeting-detection-prompt"
    static let onboarding = "oatmeal-onboarding"
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
        VStack(alignment: .leading, spacing: 0) {
            if let state = model.menuBarSessionState {
                recordingHeader(state)
                recordingWaveform
                recordingSourceCards
                recordingControls(state)
                if let end = endSuggestionState {
                    endSuggestionHint(end)
                }
                quietTail
            } else if let detectionState = model.menuBarMeetingDetectionState {
                detectionHeader(detectionState)
                detectionBody(detectionState)
                detectionControls(detectionState)
                quietTail
            } else {
                idleHeader
                idleControls
            }
            OMHairline()
            localGuaranteeFooter
        }
        .frame(width: 340, alignment: .leading)
        .background(Color.om.paper.opacity(0.86))
    }

    /// Two ring-tinted cards that show what Oatmeal is capturing right now:
    /// the mic on the left, system audio on the right. Each card has a mini
    /// waveform — a visual cue that the channel is live.
    private var recordingSourceCards: some View {
        HStack(spacing: 8) {
            sourceCard(icon: "mic.fill", title: "Mic", subtitle: "You")
            sourceCard(icon: "speaker.wave.2.fill", title: "System", subtitle: "Others")
        }
        .padding(.horizontal, OMSpacing.s4)
        .padding(.bottom, OMSpacing.s3)
    }

    private func sourceCard(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.om.ring)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.om.ink)
                Text(subtitle)
                    .font(.om.meta)
                    .foregroundStyle(Color.om.ink3)
            }
            Spacer(minLength: 4)
            OMWaveform(barCount: 4, tint: Color.om.ring)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.om.ring.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: OMRadius.sm)
                .strokeBorder(Color.om.ring.opacity(0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: OMRadius.sm))
    }

    private var endSuggestionState: MeetingDetectionPromptState? {
        guard let detection = model.menuBarMeetingDetectionState,
              detection.phase == .endSuggestion else {
            return nil
        }
        return detection
    }

    // MARK: Recording

    private func recordingHeader(_ state: SessionControllerState) -> some View {
        HStack(alignment: .center, spacing: 8) {
            OMRecDot()
            Text(recordingLabel(for: state))
                .font(.om.body)
                .foregroundStyle(Color.om.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(state.elapsedText() ?? "--:--")
                    .font(.om.meta)
                    .monospacedDigit()
                    .foregroundStyle(Color.om.ink3)
            }
        }
        .padding(.horizontal, OMSpacing.s4)
        .padding(.top, OMSpacing.s3)
        .padding(.bottom, OMSpacing.s2)
    }

    private var recordingWaveform: some View {
        RecorderWaveformBar()
            .padding(.horizontal, OMSpacing.s4)
            .padding(.bottom, OMSpacing.s3)
    }

    private func recordingControls(_ state: SessionControllerState) -> some View {
        HStack(alignment: .center, spacing: OMSpacing.s2) {
            OMButton(variant: .secondary) {
                _ = router.openMainWindow(openTranscript: true)
            } label: {
                Label("Transcript", systemImage: "text.alignleft")
                    .labelStyle(.titleOnly)
            }
            .disabled(!state.canOpenTranscript)

            if state.canStopCapture {
                OMButton(variant: .destructive) {
                    Task { await router.stopCapture() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill").font(.system(size: 9))
                        Text("Stop & save")
                    }
                }
            }
            Spacer(minLength: 0)
            OMKbd("⌘⇧9")
        }
        .padding(.horizontal, OMSpacing.s4)
        .padding(.bottom, OMSpacing.s3)
    }

    // MARK: Detection

    private func detectionHeader(_ state: MeetingDetectionPromptState) -> some View {
        HStack(alignment: .center, spacing: OMSpacing.s2) {
            OatLeafMark(size: 16, tint: Color.om.oat2)
            Text(state.headline)
                .font(.om.body)
                .foregroundStyle(Color.om.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, OMSpacing.s4)
        .padding(.top, OMSpacing.s3)
        .padding(.bottom, OMSpacing.s1)
    }

    private func detectionBody(_ state: MeetingDetectionPromptState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(state.title)
                .font(.om.sectionTitle)
                .foregroundStyle(Color.om.ink)
                .lineLimit(2)
            Text(state.menuBarSummary)
                .font(.om.caption)
                .foregroundStyle(Color.om.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, OMSpacing.s4)
        .padding(.bottom, OMSpacing.s3)
    }

    private func detectionControls(_ state: MeetingDetectionPromptState) -> some View {
        HStack(alignment: .center, spacing: OMSpacing.s2) {
            OMButton(state.primaryActionTitle, variant: .primary) {
                Task { await router.startPendingMeetingDetection() }
            }
            if let secondary = state.secondaryActionTitle {
                OMButton(secondary, variant: .secondary) {
                    router.ignorePendingMeetingDetection()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, OMSpacing.s4)
        .padding(.bottom, OMSpacing.s3)
    }

    // MARK: End-suggestion inline hint

    private func endSuggestionHint(_ state: MeetingDetectionPromptState) -> some View {
        VStack(alignment: .leading, spacing: OMSpacing.s2) {
            Text(state.headline.uppercased())
                .font(.om.eyebrow)
                .tracking(1.8)
                .foregroundStyle(Color.om.ember)
            Text(state.menuBarSummary)
                .font(.om.caption)
                .foregroundStyle(Color.om.ink2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: OMSpacing.s2) {
                OMButton(state.primaryActionTitle, variant: .destructive) {
                    Task { await router.startPendingMeetingDetection() }
                }
                if let secondary = state.secondaryActionTitle {
                    OMButton(secondary, variant: .secondary) {
                        router.ignorePendingMeetingDetection()
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(OMSpacing.s3)
        .background(
            RoundedRectangle(cornerRadius: OMRadius.md)
                .fill(Color.om.ember.opacity(0.08))
        )
        .padding(.horizontal, OMSpacing.s4)
        .padding(.bottom, OMSpacing.s3)
    }

    // MARK: Quiet tail — secondary affordance that exists in every non-idle state

    private var quietTail: some View {
        HStack(spacing: 0) {
            Button {
                _ = router.openMainWindow()
            } label: {
                HStack(spacing: 4) {
                    Text("Open Oatmeal")
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 9))
                }
                .font(.om.caption)
                .foregroundStyle(Color.om.ink3)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, OMSpacing.s4)
        .padding(.bottom, OMSpacing.s3)
    }

    // MARK: Idle

    private var idleHeader: some View {
        HStack(alignment: .center, spacing: OMSpacing.s2) {
            OatLeafMark(size: 18, tint: Color.om.ink)
            Text("Oatmeal")
                .font(.om.sectionTitle)
                .foregroundStyle(Color.om.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, OMSpacing.s4)
        .padding(.top, OMSpacing.s3)
        .padding(.bottom, OMSpacing.s1)
    }

    private var idleControls: some View {
        VStack(alignment: .leading, spacing: OMSpacing.s2) {
            Text("No active session")
                .font(.om.caption)
                .foregroundStyle(Color.om.ink3)
                .padding(.bottom, OMSpacing.s1)
            HStack(spacing: OMSpacing.s2) {
                OMButton("Start recording", variant: .primary) {
                    Task { await router.startQuickNoteCapture() }
                }
                OMButton("Open Oatmeal", variant: .secondary) {
                    _ = router.openMainWindow()
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, OMSpacing.s4)
        .padding(.bottom, OMSpacing.s3)
    }

    // MARK: Footer

    private var localGuaranteeFooter: some View {
        HStack(spacing: OMSpacing.s1 + 2) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.om.ink3)
            Text("Audio stays on this Mac. Transcribing locally.")
                .font(.om.caption)
                .foregroundStyle(Color.om.ink3)
        }
        .padding(.horizontal, OMSpacing.s4)
        .padding(.vertical, OMSpacing.s2 + 2)
    }

    // MARK: Copy

    private func recordingLabel(for state: SessionControllerState) -> String {
        let prefix = state.kind == .processing ? "Wrapping up" : "Recording"
        return "\(prefix) · \(state.title)"
    }
}

/// 60-bar decorative waveform for the top of the recorder popover. Bars are
/// shaped to read as a recent audio signal — recent samples on the right feel
/// "live," older samples on the left feel settled.
private struct RecorderWaveformBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                HStack(alignment: .center, spacing: 1.5) {
                    ForEach(0..<60, id: \.self) { i in
                        let frac = Double(i) / 60.0
                        let phase = t * 1.8 + Double(i) * 0.23
                        let base = abs(sin(phase)) * (0.4 + frac * 0.7)
                        let h = reduceMotion ? 10.0 : 4.0 + base * 22.0
                        Capsule()
                            .fill(i < 46 ? Color.om.ink2 : Color.om.ink4)
                            .frame(width: max(1.5, (geo.size.width - 60 * 1.5) / 60), height: h)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: OMRadius.md)
                .fill(Color.om.oat.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: OMRadius.md)
                        .strokeBorder(Color.om.ring.opacity(0.12), lineWidth: 1)
                )
        )
        .accessibilityHidden(true)
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
    private enum RecorderMeetingTab: String, CaseIterable, Identifiable {
        case scratchpad
        case transcript

        var id: String { rawValue }

        var title: String {
            switch self {
            case .scratchpad:
                "Scratchpad"
            case .transcript:
                "Transcript"
            }
        }
    }

    @Environment(AppViewModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: RecorderMeetingTab = .scratchpad
    @State private var selectedMicrophoneID: String?
    @State private var recorderMessage: String?
    @State private var isStopWarningPresented = false

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

    private var availableMicrophones: [CaptureInputDevice] {
        model.availableMicrophones()
    }

    private var scratchpadBinding: Binding<String> {
        Binding(
            get: { currentNote?.scratchpad ?? "" },
            set: { model.replaceScratchpad($0, for: state.noteID) }
        )
    }

    let state: SessionControllerState

    var body: some View {
        VStack(alignment: .leading, spacing: isCollapsed ? 10 : 14) {
            if isCollapsed {
                compactRecorderView
            } else {
                expandedMeetingView
            }
        }
        .padding(isCollapsed ? 12 : 16)
        .frame(
            minWidth: isCollapsed ? 276 : 360,
            idealWidth: isCollapsed ? 292 : 380,
            maxWidth: isCollapsed ? 308 : 400
        )
        .background(
            RoundedRectangle(cornerRadius: OMRadius.lg, style: .continuous)
                .fill(Color.om.paper.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: OMRadius.lg, style: .continuous)
                .strokeBorder(Color.om.line, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 22, y: 12)
        .padding(8)
        .animation(.easeInOut(duration: 0.18), value: isCollapsed)
        .onAppear {
            refreshLocalState()
        }
        .onChange(of: state.noteID) { _, _ in
            refreshLocalState()
        }
        .onChange(of: currentNote?.scratchpad) { _, _ in
            if recorderMessage != nil {
                recorderMessage = nil
            }
        }
        .alert("Stop recording?", isPresented: $isStopWarningPresented) {
            Button("Continue Recording", role: .cancel) {}
            Button("Stop Anyway", role: .destructive) {
                Task {
                    await router.stopCapture()
                }
            }
        } message: {
            Text("This recording is still under five minutes. Jamie warns that very short captures often produce weaker notes, so Oatmeal is checking before it stops.")
        }
    }

    private var compactRecorderView: some View {
        HStack(spacing: 10) {
            Button {
                model.toggleSessionControllerCollapsed()
            } label: {
                HStack(spacing: 10) {
                    if state.tone == .live {
                        OMRecDot(size: 8)
                    } else {
                        Circle()
                            .fill(color(for: state.tone))
                            .frame(width: 8, height: 8)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.title)
                            .font(.om.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.om.ink)
                            .lineLimit(1)

                        Text(compactSubtitle)
                            .font(.om.caption)
                            .foregroundStyle(Color.om.ink3)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            elapsedChip

            if state.canStopCapture {
                OMButton(variant: .destructive) {
                    stopCaptureFromRecorder()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill").font(.system(size: 9))
                        Text("Stop")
                    }
                }
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

    private var expandedMeetingView: some View {
        VStack(alignment: .leading, spacing: 16) {
            expandedHeader
            recorderStrip
            endSuggestionCallout
            microphoneSelectorRow
            recorderTabBar
            activeTabContent

            if state.showsProcessingIndicator {
                processingRibbon
            }

            actionRail
        }
    }

    private var expandedHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                OMEyebrow(state.kind == .processing ? "Wrapping up" : "Recording")

                Text(state.title)
                    .font(.om.sectionTitle)
                    .foregroundStyle(Color.om.ink)
                    .lineLimit(2)

                Text(expandedSubtitle)
                    .font(.om.caption)
                    .foregroundStyle(Color.om.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                elapsedChip

                HStack(spacing: 6) {
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
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 8) {
                if state.tone == .live {
                    OMRecDot(size: 8)
                } else {
                    Circle()
                        .fill(color(for: state.tone))
                        .frame(width: 8, height: 8)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.controllerStatusTitle)
                        .font(.om.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.om.ink)

                    Text(state.kind == .processing ? "Oatmeal is finishing this note locally." : "Oatmeal is recording this meeting locally.")
                        .font(.om.caption)
                        .foregroundStyle(Color.om.ink3)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.om.paper2, in: RoundedRectangle(cornerRadius: OMRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: OMRadius.md)
                .strokeBorder(Color.om.line, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var endSuggestionCallout: some View {
        if let detectionState = model.menuBarMeetingDetectionState,
           detectionState.phase == .endSuggestion {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: detectionState.symbolName)
                        .foregroundStyle(Color.om.ember)
                        .font(.system(size: 12, weight: .semibold))
                    OMEyebrow(detectionState.headline)
                }

                Text(detectionState.detailText)
                    .font(.om.caption)
                    .foregroundStyle(Color.om.ink2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    OMButton(detectionState.primaryActionTitle, variant: .destructive) {
                        Task {
                            await router.startPendingMeetingDetection()
                        }
                    }
                    if let secondaryActionTitle = detectionState.secondaryActionTitle {
                        OMButton(secondaryActionTitle, variant: .secondary) {
                            router.ignorePendingMeetingDetection()
                        }
                    }
                }
            }
            .padding(12)
            .background(Color.om.ember.opacity(0.08), in: RoundedRectangle(cornerRadius: OMRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: OMRadius.md)
                    .strokeBorder(Color.om.ember.opacity(0.20), lineWidth: 1)
            )
        }
    }

    private var scratchpadCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            labelRow(title: "Scratchpad", caption: "Private notes stay here and are excluded from summaries and sharing.")

            TextEditor(text: scratchpadBinding)
                .font(.om.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 130)
                .padding(8)
                .background(Color.om.card, in: RoundedRectangle(cornerRadius: OMRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: OMRadius.md)
                        .strokeBorder(Color.om.line, lineWidth: 1)
                )

            if let recorderMessage {
                Text(recorderMessage)
                    .font(.om.caption)
                    .foregroundStyle(Color.om.ink3)
            }
        }
        .padding(12)
        .background(Color.om.paper2, in: RoundedRectangle(cornerRadius: OMRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: OMRadius.md)
                .strokeBorder(Color.om.line, lineWidth: 1)
        )
    }

    private var transcriptPreviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            labelRow(title: "Transcript", caption: transcriptCaption)

            if transcriptPreviewLines.isEmpty {
                Text(transcriptEmptyState)
                    .font(.om.body)
                    .foregroundStyle(Color.om.ink3)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(transcriptPreviewLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.om.body)
                            .foregroundStyle(Color.om.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.om.paper2, in: RoundedRectangle(cornerRadius: OMRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: OMRadius.md)
                .strokeBorder(Color.om.line, lineWidth: 1)
        )
    }

    private var processingRibbon: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.om.oat2)
                .font(.system(size: 11, weight: .semibold))

            Text(state.processingLabel ?? "Transcribing, writing the summary, and extracting tasks in the background.")
                .font(.om.caption)
                .foregroundStyle(Color.om.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.om.oat.opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.om.oat.opacity(0.16), lineWidth: 1))
    }

    private var actionRail: some View {
        HStack(spacing: 8) {
            if state.canStopCapture {
                OMButton(variant: .destructive) {
                    stopCaptureFromRecorder()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill").font(.system(size: 9))
                        Text("Stop & save")
                    }
                }
            }

            OMButton("Open note", variant: .secondary) {
                _ = router.openMainWindow()
            }

            if state.canOpenTranscript {
                OMButton("Transcript", variant: .secondary) {
                    _ = router.openMainWindow(openTranscript: true)
                }
            }

            Spacer()
        }
    }

    private var microphoneSelectorRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.fill")
                .foregroundStyle(Color.om.ring)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                OMEyebrow("Microphone")

                Text(selectedMicrophoneName ?? "Default microphone")
                    .font(.om.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.om.ink)
            }

            Spacer(minLength: 0)

            Menu {
                ForEach(availableMicrophones) { device in
                    Button {
                        Task {
                            await switchMicrophone(to: device)
                        }
                    } label: {
                        Label(device.name, systemImage: device.id == selectedMicrophoneID ? "checkmark" : "")
                    }
                }
            } label: {
                Text("Change")
                    .font(.om.button)
                    .foregroundStyle(Color.om.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.om.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.om.line2, lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.om.card, in: RoundedRectangle(cornerRadius: OMRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: OMRadius.md)
                .strokeBorder(Color.om.line, lineWidth: 1)
        )
    }

    private var recorderTabBar: some View {
        HStack(spacing: 6) {
            ForEach(RecorderMeetingTab.allCases) { tab in
                let isActive = selectedTab == tab
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.title)
                        .font(.om.button)
                        .foregroundStyle(isActive ? Color.om.paper : Color.om.ink2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(isActive ? Color.om.ink : Color.om.card)
                        )
                        .overlay(
                            Capsule().strokeBorder(isActive ? Color.om.ink : Color.om.line2, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var activeTabContent: some View {
        switch selectedTab {
        case .scratchpad:
            scratchpadCard
        case .transcript:
            transcriptPreviewCard
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

        if state.kind == .processing {
            return "Oatmeal is finishing this meeting locally."
        }

        return "Stay in the conversation while Oatmeal records in the background."
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
            ? "A quick look at what Oatmeal is hearing right now."
            : "Transcript snippets show up here while Oatmeal catches up."
    }

    private var transcriptEmptyState: String {
        if state.kind == .processing {
            return "Oatmeal is reconciling the final transcript from the saved recording."
        }

        return "Transcript updates will appear here as Oatmeal catches up."
    }

    private var elapsedChip: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Text(state.elapsedText() ?? "--:--")
                .font(.om.meta)
                .monospacedDigit()
                .foregroundStyle(Color.om.ink2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.om.card, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.om.line, lineWidth: 1))
        }
    }

    private func labelRow(title: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            OMEyebrow(title)
            Text(caption)
                .font(.om.caption)
                .foregroundStyle(Color.om.ink3)
        }
    }

    private func surfaceControlButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.om.ink3)
                .frame(width: 24, height: 24)
                .background(Color.om.card, in: Circle())
                .overlay(Circle().strokeBorder(Color.om.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func color(for tone: SessionControllerState.Tone) -> Color {
        switch tone {
        case .live:
            Color.om.recDot
        case .delayed:
            Color.om.honey
        case .recovered:
            Color.om.sage2
        case .failed:
            Color.om.ember
        case .neutral:
            Color.om.ink3
        }
    }

    private var selectedMicrophoneName: String? {
        availableMicrophones.first(where: { $0.id == selectedMicrophoneID })?.name
    }

    private func refreshLocalState() {
        selectedTab = .scratchpad
        selectedMicrophoneID = model.activeMicrophoneID(for: state.noteID)
        recorderMessage = nil
    }

    private func stopCaptureFromRecorder() {
        if model.shouldWarnBeforeStoppingCapture(for: state.noteID) {
            isStopWarningPresented = true
            return
        }

        Task {
            await router.stopCapture()
        }
    }

    private func switchMicrophone(to device: CaptureInputDevice) async {
        do {
            try await model.switchActiveMicrophone(to: device.id, for: state.noteID)
            selectedMicrophoneID = device.id
            recorderMessage = "Using \(device.name)."
        } catch {
            recorderMessage = error.localizedDescription
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

    private let surface = Color(nsColor: NSColor(srgbRed: 0.125, green: 0.102, blue: 0.078, alpha: 0.82))
    private let cream = Color(.sRGB, red: 0.961, green: 0.937, blue: 0.894, opacity: 1)
    private var creamMuted: Color { cream.opacity(0.72) }
    private var creamDim: Color { cream.opacity(0.45) }
    private var creamHairline: Color { cream.opacity(0.08) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            headline
            contextLine
            if !state.candidateOptions.isEmpty {
                candidateChooser
            }
            countdownBar
            actions
        }
        .frame(width: 360)
        .background(
            RoundedRectangle(cornerRadius: OMRadius.lg, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: OMRadius.lg, style: .continuous)
                        .fill(surface)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: OMRadius.lg, style: .continuous)
                .strokeBorder(cream.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 24, y: 14)
        .padding(8)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            OatLeafMark(size: 18, tint: cream)
            Text("Oatmeal")
                .font(.om.body)
                .fontWeight(.medium)
                .foregroundStyle(creamMuted)
            Spacer(minLength: 0)
            Text(nowLabel)
                .font(.om.meta)
                .foregroundStyle(creamDim)
        }
        .padding(.horizontal, OMSpacing.s4)
        .padding(.top, OMSpacing.s3 + 2)
        .padding(.bottom, 6)
    }

    private var headline: some View {
        Text(headlineCopy)
            .font(.om.sectionTitle)
            .foregroundStyle(cream)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, OMSpacing.s4)
            .padding(.bottom, 6)
    }

    private var contextLine: some View {
        (
            Text(state.title)
                .font(.om.body)
                .fontWeight(.medium)
                .foregroundStyle(cream)
            + Text(" · \(state.sourceName)")
                .font(.om.body)
                .foregroundStyle(creamMuted)
        )
        .padding(.horizontal, OMSpacing.s4)
        .padding(.bottom, OMSpacing.s3)
    }

    @ViewBuilder
    private var candidateChooser: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Choose the meeting".uppercased())
                .font(.om.eyebrow)
                .tracking(1.8)
                .foregroundStyle(creamDim)
            ForEach(state.candidateOptions) { option in
                candidateButton(option)
            }
        }
        .padding(.horizontal, OMSpacing.s4)
        .padding(.bottom, OMSpacing.s3)
    }

    /// Decorative auto-start countdown shown above the actions. The detection
    /// state doesn't expose an auto-start deadline on the model yet, so the
    /// bar fills from 0→1 over ~8 seconds and the mono label counts down the
    /// same interval. If the user taps Record / Not a meeting first, the
    /// prompt dismisses and the animation disposes with the window.
    private var countdownBar: some View {
        let window: Double = 8
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Auto-starts")
                    .font(.om.meta)
                    .foregroundStyle(creamDim)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed = context.date.timeIntervalSince(state.detectedAt)
                    let remaining = max(0, Int((window - elapsed).rounded(.up)))
                    Text("\(remaining)s")
                        .font(.om.meta)
                        .monospacedDigit()
                        .foregroundStyle(creamMuted)
                }
            }
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                let elapsed = context.date.timeIntervalSince(state.detectedAt)
                let progress = max(0, min(1, elapsed / window))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(cream.opacity(0.10))
                        Capsule()
                            .fill(cream.opacity(0.55))
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 3)
            }
            .frame(height: 3)
        }
        .padding(.horizontal, OMSpacing.s4)
        .padding(.bottom, OMSpacing.s3)
    }

    private var actions: some View {
        VStack(spacing: 0) {
            Rectangle().fill(creamHairline).frame(height: 1)
            HStack(spacing: OMSpacing.s2) {
                Button {
                    Task { await router.startPendingMeetingDetection() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "mic.fill").font(.system(size: 11))
                        Text(state.primaryActionTitle)
                            .font(.om.button)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .foregroundStyle(Color(.sRGB, red: 0.109, green: 0.090, blue: 0.071, opacity: 1))
                    .background(cream)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(!state.primaryActionEnabled)

                if let secondary = state.secondaryActionTitle {
                    Button {
                        router.ignorePendingMeetingDetection()
                    } label: {
                        Text(secondary)
                            .font(.om.button)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .foregroundStyle(cream)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(cream.opacity(0.18), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(OMSpacing.s3)
        }
    }

    private func candidateButton(_ option: MeetingDetectionCandidateOption) -> some View {
        let isSelected = state.selectedCandidateID == option.id

        return Button {
            router.selectPendingMeetingCandidate(option.id)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? cream : creamDim)
                    .font(.system(size: 14))

                VStack(alignment: .leading, spacing: 1) {
                    Text(option.title)
                        .font(.om.body)
                        .fontWeight(.medium)
                        .foregroundStyle(cream)
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)
                    Text(option.subtitle)
                        .font(.om.caption)
                        .foregroundStyle(creamDim)
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? cream.opacity(0.12) : cream.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Copy

    private var headlineCopy: String {
        switch state.phase {
        case .start:
            return "A meeting looks like it just started."
        case .endSuggestion:
            return "This meeting looks like it ended."
        }
    }

    private var nowLabel: String {
        let delta = Date().timeIntervalSince(state.detectedAt)
        switch delta {
        case ..<10:   return "now"
        case 10..<60: return "\(Int(delta))s"
        case 60..<3600:
            let m = Int(delta / 60)
            return "\(m)m"
        default:
            let h = Int(delta / 3600)
            return "\(h)h"
        }
    }
}

private func nonBlank(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
        return nil
    }
    return value
}
