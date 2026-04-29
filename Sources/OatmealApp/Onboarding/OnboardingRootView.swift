import OatmealCore
import SwiftUI

struct OnboardingRootView: View {
    @Environment(AppViewModel.self) private var model

    @State private var currentStep: Step = .welcome
    @State private var isSystemAudioExplainerPresented = false

    private enum Step: Int, CaseIterable {
        case welcome = 1
        case permissions = 2
        case done = 3

        var label: String { "Step \(rawValue) of 3" }
    }

    var body: some View {
        HStack(spacing: 0) {
            brandPane
            rightPane
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.om.paper)
        .task {
            await model.refreshCapturePermissions()
            await model.loadCalendarState()
        }
        .alert(
            "macOS will ask for screen recording access next.",
            isPresented: $isSystemAudioExplainerPresented
        ) {
            Button("Continue") {
                Task {
                    await model.requestSystemAudioAccess()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("That's how Oatmeal captures the other side of a call — it doesn't record video, and audio stays on your Mac.")
        }
    }

    // MARK: Brand pane

    /// Left rail — stays consistent across all three steps so the brand is the
    /// stable spine of the flow. Headline + subline change with the step.
    private var brandPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            OatLeafMark(size: 24, tint: Color.om.ink)
                .padding(.top, 40)
                .padding(.leading, 40)

            Spacer()

            OatmealBowlMark(size: 220)
                .frame(maxWidth: .infinity, alignment: .center)

            Spacer().frame(maxHeight: 80)

            VStack(alignment: .leading, spacing: 12) {
                brandHeadline
                Text(brandTagline)
                    .font(.om.caption)
                    .foregroundStyle(Color.om.ink3)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 320, alignment: .leading)
            }
            .padding(.leading, 40)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: 450, maxHeight: .infinity, alignment: .leading)
        .background(Color.om.paper2)
        .overlay(alignment: .trailing) { OMHairline(.vertical) }
    }

    private var brandHeadline: some View {
        Group {
            switch currentStep {
            case .welcome:
                Text("Welcome\n").font(.om.title).foregroundStyle(Color.om.ink)
                    + Text("to Oatmeal.").font(.om.title).italic().foregroundStyle(Color.om.ink2)
            case .permissions:
                Text("Three\n").font(.om.title).foregroundStyle(Color.om.ink)
                    + Text("tiny asks.").font(.om.title).italic().foregroundStyle(Color.om.ink2)
            case .done:
                Text("All set.\n").font(.om.title).foregroundStyle(Color.om.ink)
                    + Text("Serve warm.").font(.om.title).italic().foregroundStyle(Color.om.ink2)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var brandTagline: String {
        switch currentStep {
        case .welcome:
            "A quieter kind of meeting assistant. Everything you record, transcribe, and write stays on this Mac."
        case .permissions:
            "macOS will ask once. Oatmeal won't upload anything; permissions are local to this Mac."
        case .done:
            "Audio stays on your machine. Nothing leaves the bowl without your say-so."
        }
    }

    // MARK: Right pane

    @ViewBuilder
    private var rightPane: some View {
        switch currentStep {
        case .welcome:
            welcomePane
        case .permissions:
            permissionsPane
        case .done:
            donePane
        }
    }

    // Right pane is a header + body + footer column; each step provides its own
    // header + body and shares the same footer (step dashes + buttons).
    private var welcomePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            OMEyebrow(currentStep.label)
                .padding(.top, 40)
            Text("A quieter kind of\nmeeting assistant.")
                .font(.custom("InstrumentSerif-Regular", size: 28, relativeTo: .largeTitle))
                .foregroundStyle(Color.om.ink)
                .padding(.top, 6)
            Text("Oatmeal lives in your menu bar. It notices when a meeting starts, captures audio quietly, transcribes locally with Whisper, and writes you a clean note when the call ends. Everything stays on this Mac.")
                .font(.om.caption)
                .foregroundStyle(Color.om.ink2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .frame(maxWidth: 360, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                onboardingFeatureRow(icon: "mic.fill", title: "On-device transcription", subtitle: "Local Whisper, no cloud round-trip.")
                onboardingFeatureRow(icon: "sparkles", title: "Notes written by Oatmeal", subtitle: "Decisions, action items, summary.")
                onboardingFeatureRow(icon: "lock.fill", title: "Local-first by default", subtitle: "Audio and notes stay on this Mac.")
            }
            .padding(.top, 28)

            Spacer()

            footer
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.om.paper)
    }

    private var permissionsPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            OMEyebrow(currentStep.label)
                .padding(.top, 40)
            Text("Three tiny permissions.")
                .font(.custom("InstrumentSerif-Regular", size: 28, relativeTo: .largeTitle))
                .foregroundStyle(Color.om.ink)
                .padding(.top, 6)
            Text("macOS will ask once. Audio stays on your machine — we never upload it.")
                .font(.om.caption)
                .foregroundStyle(Color.om.ink3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .frame(maxWidth: 340, alignment: .leading)

            VStack(spacing: 10) {
                PermissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "Record your voice during meetings.",
                    status: model.capturePermissions.microphone,
                    action: { Task { await model.requestMicrophoneAccess() } }
                )
                PermissionRow(
                    icon: "speaker.wave.2.fill",
                    title: "System audio",
                    description: "Record the other side of the call.",
                    status: model.capturePermissions.systemAudio,
                    action: {
                        if model.capturePermissions.systemAudio == .notDetermined {
                            isSystemAudioExplainerPresented = true
                        } else {
                            Task { await model.requestSystemAudioAccess() }
                        }
                    }
                )
                PermissionRow(
                    icon: "calendar",
                    title: "Calendar",
                    description: "See what's on your schedule — never uploaded.",
                    status: model.calendarAccessStatus,
                    action: { Task { await model.requestCalendarAccess() } }
                )
            }
            .padding(.top, 24)

            Spacer()

            footer
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.om.paper)
    }

    private var donePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            OMEyebrow(currentStep.label)
                .padding(.top, 40)
            Text("You're set.")
                .font(.custom("InstrumentSerif-Regular", size: 28, relativeTo: .largeTitle))
                .foregroundStyle(Color.om.ink)
                .padding(.top, 6)
            Text("Oatmeal lives in the menu bar. It will notice your next call and offer to record it. Nothing leaves your Mac unless you ask it to.")
                .font(.om.caption)
                .foregroundStyle(Color.om.ink2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .frame(maxWidth: 360, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                onboardingFeatureRow(icon: "tray.full", title: "Library", subtitle: "All your meetings, grouped by day.")
                onboardingFeatureRow(icon: "sparkles", title: "Ask this meeting", subtitle: "Grounded chat, never leaves the note.")
                onboardingFeatureRow(icon: "command", title: "⌘⇧9", subtitle: "Start or stop recording from anywhere.")
            }
            .padding(.top, 28)

            Spacer()

            footer
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.om.paper)
    }

    // Shared footer: step dashes on the left, Skip / Continue on the right.
    // The continue label and action vary per step.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            OMHairline()
            HStack {
                stepProgressDashes
                Spacer()
                if currentStep != .done {
                    OMButton("Skip for now", variant: .secondary) {
                        completeOnboarding()
                    }
                }
                OMButton(variant: .primary) {
                    advance()
                } label: {
                    HStack(spacing: 6) {
                        Text(continueButtonLabel)
                        Image(systemName: "chevron.right").font(.system(size: 9))
                    }
                }
                .disabled(!canAdvance)
            }
            .padding(.top, 18)
        }
    }

    // Three 20x3 step bars: filled `ink` for completed/current steps,
    // `line2` for upcoming. Lit count = currentStep.rawValue.
    private var stepProgressDashes: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { idx in
                Capsule()
                    .fill(idx < currentStep.rawValue ? Color.om.ink : Color.om.line2)
                    .frame(width: 20, height: 3)
            }
        }
    }

    private var continueButtonLabel: String {
        switch currentStep {
        case .welcome:     "Get started"
        case .permissions: canAdvance ? "Continue" : "Grant microphone"
        case .done:        "Open Oatmeal"
        }
    }

    private var canAdvance: Bool {
        switch currentStep {
        case .welcome:     true
        case .permissions: model.capturePermissions.microphone == .granted
        case .done:        true
        }
    }

    private func advance() {
        switch currentStep {
        case .welcome:
            currentStep = .permissions
        case .permissions:
            currentStep = .done
        case .done:
            completeOnboarding()
        }
    }

    private func completeOnboarding() {
        OnboardingCompletion.markComplete()
        model.onboardingCompletionDidChange()
    }

    // MARK: Helpers

    private func onboardingFeatureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.om.paper2)
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.om.ink2)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.om.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.om.ink)
                Text(subtitle)
                    .font(.om.caption)
                    .foregroundStyle(Color.om.ink3)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let status: PermissionStatus
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.om.paper2)
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.om.ink2)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.om.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.om.ink)
                    Text(description)
                        .font(.om.caption)
                        .foregroundStyle(Color.om.ink3)
                }

                Spacer(minLength: 12)

                statusBadge
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: OMRadius.md)
                    .fill(status == .notDetermined ? Color.om.card : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OMRadius.md)
                    .strokeBorder(Color.om.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(status == .granted || status == .restricted)
    }

    private var statusBadge: some View {
        HStack(spacing: 5) {
            if status == .granted {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
            }
            Text(badgeLabel)
        }
        .font(.om.caption)
        .fontWeight(.semibold)
        .foregroundStyle(badgeForeground)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(badgeBackground)
        )
    }

    private var badgeLabel: String {
        switch status {
        case .granted:       return "Granted"
        case .notDetermined: return "Not set"
        case .denied:        return "Denied"
        case .restricted:    return "Restricted"
        }
    }

    private var badgeForeground: Color {
        switch status {
        case .granted:       return Color.om.sage2
        case .notDetermined: return Color.om.ink3
        case .denied, .restricted: return Color.om.ember
        }
    }

    private var badgeBackground: Color {
        switch status {
        case .granted:       return Color.om.sage2.opacity(0.12)
        case .notDetermined: return Color.om.paper2
        case .denied, .restricted: return Color.om.ember.opacity(0.10)
        }
    }
}
