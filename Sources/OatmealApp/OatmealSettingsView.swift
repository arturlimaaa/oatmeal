import OatmealEdge
import SwiftUI

struct OatmealSettingsView: View {
    private static let automaticSummaryModelSelection = "__automatic_summary_model__"

    @Environment(AppViewModel.self) private var model
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("meetingReminderMinutes") private var meetingReminderMinutes = 1
    @AppStorage("shareDefault") private var shareDefault = "private"

    var body: some View {
        Form {
            Section("Capture") {
                Toggle("Launch Oatmeal at login", isOn: $launchAtLogin)

                Stepper(value: $meetingReminderMinutes, in: 0 ... 15) {
                    Text("Meeting reminder: \(meetingReminderMinutes) min before")
                }
            }

            Section("Auto-detection") {
                Toggle(
                    "Detect Zoom meetings",
                    isOn: Binding(
                        get: { model.meetingDetectionConfiguration.zoomEnabled },
                        set: { model.setMeetingDetectionSourceEnabled(.zoom, enabled: $0) }
                    )
                )

                Toggle(
                    "Detect Teams meetings",
                    isOn: Binding(
                        get: { model.meetingDetectionConfiguration.teamsEnabled },
                        set: { model.setMeetingDetectionSourceEnabled(.teams, enabled: $0) }
                    )
                )

                Toggle(
                    "Detect Slack calls",
                    isOn: Binding(
                        get: { model.meetingDetectionConfiguration.slackEnabled },
                        set: { model.setMeetingDetectionSourceEnabled(.slack, enabled: $0) }
                    )
                )

                Toggle(
                    "Detect browser calls",
                    isOn: Binding(
                        get: { model.meetingDetectionConfiguration.browsersEnabled },
                        set: { model.setMeetingDetectionSourceEnabled(.browsers, enabled: $0) }
                    )
                )

                Toggle(
                    "Auto-start for high-confidence detections",
                    isOn: Binding(
                        get: { model.meetingDetectionConfiguration.highConfidenceAutoStartEnabled },
                        set: { model.setHighConfidenceAutoStartEnabled($0) }
                    )
                )

                LabeledContent(
                    "Browser detection",
                    value: model.browserDetectionCapabilityState.automationAvailability == .available
                        ? "Full"
                        : "Limited"
                )

                Text(model.browserDetectionCapabilityState.detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !launchAtLogin {
                    Text("Auto-detection works best when Oatmeal launches at login, so it is already running when you join a call.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Low-confidence detections still use the existing Start Oatmeal prompt or passive menu-bar suggestion.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Transcription") {
                Picker(
                    "Backend",
                    selection: Binding(
                        get: { model.transcriptionConfiguration.preferredBackend },
                        set: { model.setTranscriptionBackendPreference($0) }
                    )
                ) {
                    ForEach(TranscriptionBackendPreference.allCases, id: \.self) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                }

                Picker(
                    "Execution policy",
                    selection: Binding(
                        get: { model.transcriptionConfiguration.executionPolicy },
                        set: { model.setTranscriptionExecutionPolicy($0) }
                    )
                ) {
                    ForEach(TranscriptionExecutionPolicy.allCases, id: \.self) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }

                if let runtimeState = model.transcriptionRuntimeState {
                    Text(runtimeState.activePlanSummary)
                        .foregroundStyle(.secondary)

                    ForEach(runtimeState.backends) { backend in
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent(backend.displayName, value: backend.availability.rawValue.capitalized)
                            Text(backend.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    LabeledContent("Models folder", value: runtimeState.modelsDirectoryURL.path)

                    if runtimeState.discoveredModels.isEmpty {
                        Text("No local whisper-compatible models were discovered yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(runtimeState.discoveredModels) { model in
                            LabeledContent(model.displayName, value: model.fileURL.lastPathComponent)
                        }
                    }
                } else {
                    ProgressView("Inspecting local runtime…")
                }
            }

            Section("Enhanced Notes") {
                Picker(
                    "Backend",
                    selection: Binding(
                        get: { model.summaryConfiguration.preferredBackend },
                        set: { model.setSummaryBackendPreference($0) }
                    )
                ) {
                    ForEach(SummaryBackendPreference.allCases, id: \.self) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                }

                Picker(
                    "Execution policy",
                    selection: Binding(
                        get: { model.summaryConfiguration.executionPolicy },
                        set: { model.setSummaryExecutionPolicy($0) }
                    )
                ) {
                    ForEach(SummaryExecutionPolicy.allCases, id: \.self) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }

                if let runtimeState = model.summaryRuntimeState {
                    if runtimeState.discoveredModels.isEmpty {
                        LabeledContent("MLX model", value: preferredSummaryModelLabel(for: runtimeState))
                    } else {
                        Picker(
                            "MLX model",
                            selection: Binding(
                                get: { preferredSummaryModelSelection(for: runtimeState) },
                                set: { selection in
                                    model.setSummaryPreferredModelName(
                                        selection == Self.automaticSummaryModelSelection ? nil : selection
                                    )
                                }
                            )
                        ) {
                            Text("Auto").tag(Self.automaticSummaryModelSelection)
                            ForEach(runtimeState.discoveredModels) { discoveredModel in
                                Text(discoveredModel.displayName).tag(discoveredModel.displayName)
                            }
                        }

                        if let unavailablePreferredModelName = unavailablePreferredSummaryModelName(for: runtimeState) {
                            Text(
                                "\(unavailablePreferredModelName) is no longer discovered locally. Oatmeal will use Auto until you choose another model."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    Text(runtimeState.activePlanSummary)
                        .foregroundStyle(.secondary)

                    ForEach(runtimeState.backends) { backend in
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent(backend.displayName, value: backend.availability.rawValue.capitalized)
                            Text(backend.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    LabeledContent("Models folder", value: runtimeState.modelsDirectoryURL.path)

                    if runtimeState.discoveredModels.isEmpty {
                        Text("No local MLX-compatible summary models were discovered yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(runtimeState.discoveredModels) { model in
                            LabeledContent(model.displayName, value: model.directoryURL.lastPathComponent)
                        }
                    }
                } else {
                    ProgressView("Inspecting summary runtime…")
                }

                if let catalogState = model.summaryModelCatalogState {
                    LabeledContent("Model downloads", value: catalogState.downloadAvailability.rawValue.capitalized)
                    Text(catalogState.downloadRuntimeDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let operation = model.activeSummaryModelOperation {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(operation.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let error = model.summaryModelManagementError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    ForEach(catalogState.items) { item in
                        SummaryModelCatalogRow(
                            item: item,
                            preferredModelName: model.summaryConfiguration.preferredModelName,
                            downloadsAvailable: catalogState.downloadAvailability == .available,
                            isBusy: model.activeSummaryModelOperation != nil,
                            onUse: {
                                model.setSummaryPreferredModelName(item.catalogEntry.displayName)
                            },
                            onDownload: {
                                model.installSummaryModel(item.catalogEntry)
                            },
                            onUpdate: {
                                model.installSummaryModel(item.catalogEntry, forceRedownload: true)
                            },
                            onRemove: {
                                guard let installedModel = item.installedModel else {
                                    return
                                }
                                model.removeSummaryModel(installedModel)
                            }
                        )
                    }

                    Text("You can also place any MLX-compatible model folder directly into the managed summaries directory.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView("Inspecting model library…")
                }
            }

            Section("Sharing") {
                Picker("Default link access", selection: $shareDefault) {
                    Text("Private").tag("private")
                    Text("Anyone with link").tag("public")
                    Text("Team domain").tag("team")
                }
            }

            Section("Privacy") {
                LabeledContent("Audio capture", value: "Local on this Mac")
                LabeledContent("Transcription strategy", value: "Offline-first runtime plan with explicit fallback")
                LabeledContent("Summary strategy", value: "Local structured notes with deterministic fallback")
                LabeledContent("Model training", value: "Disabled for third-party providers")
            }

            Section("Advanced") {
                Button("Replay welcome & permissions onboarding") {
                    OnboardingCompletion.reset()
                    model.onboardingCompletionDidChange()
                }
            }
        }
        .task {
            await model.refreshTranscriptionRuntimeState()
            await model.refreshSummaryRuntimeState()
            await model.refreshSummaryModelCatalogState()
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private func preferredSummaryModelSelection(for runtimeState: LocalSummaryRuntimeState) -> String {
        let preferredModelName = runtimeState.preferredModelName
            ?? model.summaryConfiguration.preferredModelName
        guard let preferredModelName else {
            return Self.automaticSummaryModelSelection
        }

        return runtimeState.discoveredModels.first(where: {
            $0.displayName.caseInsensitiveCompare(preferredModelName) == .orderedSame
        })?.displayName ?? Self.automaticSummaryModelSelection
    }

    private func preferredSummaryModelLabel(for runtimeState: LocalSummaryRuntimeState) -> String {
        runtimeState.preferredModelName
            ?? model.summaryConfiguration.preferredModelName
            ?? "Auto"
    }

    private func unavailablePreferredSummaryModelName(for runtimeState: LocalSummaryRuntimeState) -> String? {
        let preferredModelName = runtimeState.preferredModelName
            ?? model.summaryConfiguration.preferredModelName
        guard let preferredModelName else {
            return nil
        }

        let isDiscovered = runtimeState.discoveredModels.contains {
            $0.displayName.caseInsensitiveCompare(preferredModelName) == .orderedSame
        }
        return isDiscovered ? nil : preferredModelName
    }
}

private struct SummaryModelCatalogRow: View {
    let item: SummaryModelCatalogItemState
    let preferredModelName: String?
    let downloadsAvailable: Bool
    let isBusy: Bool
    let onUse: () -> Void
    let onDownload: () -> Void
    let onUpdate: () -> Void
    let onRemove: () -> Void

    private var isInstalled: Bool {
        item.installedModel != nil
    }

    private var isSelected: Bool {
        guard let preferredModelName else {
            return false
        }

        return preferredModelName.caseInsensitiveCompare(item.catalogEntry.displayName) == .orderedSame
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.catalogEntry.displayName)
                    .font(.headline)

                if item.catalogEntry.recommended {
                    badge("Recommended")
                }

                if isInstalled {
                    badge("Installed")
                }

                if isSelected {
                    badge("Selected")
                }
            }

            Text(item.catalogEntry.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Text(item.catalogEntry.footprintDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let sizeBytes = item.installedModel?.sizeBytes {
                    Text(ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                if isInstalled {
                    if !isSelected {
                        Button("Use", action: onUse)
                            .disabled(isBusy)
                    }

                    Button("Update", action: onUpdate)
                        .disabled(isBusy || !downloadsAvailable)

                    Button("Remove", role: .destructive, action: onRemove)
                        .disabled(isBusy)
                } else {
                    Button("Download", action: onDownload)
                        .disabled(isBusy || !downloadsAvailable)
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }
}
