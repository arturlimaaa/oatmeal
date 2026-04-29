import OatmealEdge
import SwiftUI

struct OatmealSettingsView: View {
    private static let automaticSummaryModelSelection = "__automatic_summary_model__"
    private static let autoDetectLanguageSelection = "__auto_detect_language__"

    /// Curated list of primary BCP 47 languages offered in the picker.
    /// Display name shown to the user, identifier persisted to
    /// `LocalTranscriptionConfiguration.preferredLocaleIdentifier`.
    // TODO(multilingual): regional variants
    static let curatedTranscriptionLanguages: [(identifier: String, displayName: String)] = [
        ("en", "English"),
        ("es", "Spanish"),
        ("pt", "Portuguese"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("nl", "Dutch"),
        ("pl", "Polish"),
        ("ru", "Russian"),
        ("tr", "Turkish"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("zh", "Chinese"),
        ("ar", "Arabic"),
        ("hi", "Hindi")
    ]

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

                Picker(
                    "Transcription language",
                    selection: Binding(
                        get: { transcriptionLanguageSelection() },
                        set: { selection in
                            model.setTranscriptionPreferredLocaleIdentifier(
                                selection == Self.autoDetectLanguageSelection ? nil : selection
                            )
                        }
                    )
                ) {
                    Text("Auto-detect").tag(Self.autoDetectLanguageSelection)
                    ForEach(Self.curatedTranscriptionLanguages, id: \.identifier) { entry in
                        Text(entry.displayName).tag(entry.identifier)
                    }
                }

                Text("Auto-detect is slower than locking a single language and requires a multilingual Whisper model.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if appleSpeechIsActiveBackend, model.transcriptionConfiguration.preferredLocaleIdentifier == nil {
                    Text("Auto-detect requires Whisper. Apple Speech will run in the system locale instead.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

            Section("Multilingual models") {
                if let catalogState = model.whisperModelCatalogState {
                    Text(
                        "Download a multilingual Whisper model to transcribe non-English meetings or use auto-detect. Models save to the managed models folder and are picked up automatically."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let error = model.whisperModelManagementError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    ForEach(orderedWhisperCatalogItems(from: catalogState)) { item in
                        WhisperModelCatalogRow(
                            item: item,
                            qualityHint: item.catalogEntry.qualityHint(
                                for: targetLanguageBCP47ForHints()
                            ),
                            installProgress: model.whisperModelInstallProgress[item.id],
                            isInstalling: model.whisperModelInstallProgress[item.id] != nil,
                            onDownload: { model.installWhisperModel(item.id) },
                            onCancel: { model.cancelWhisperModelInstall(item.id) },
                            onRemove: { model.removeWhisperModel(item.id) }
                        )
                    }

                    LabeledContent("Models folder", value: catalogState.modelsDirectoryURL.path)
                } else {
                    ProgressView("Inspecting model catalog…")
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
            await model.refreshWhisperModelCatalogState()
        }
        .formStyle(.grouped)
        .padding(20)
    }

    /// Returns the picker tag that should appear visually selected.
    ///
    /// The user has explicitly chosen "Auto-detect" when
    /// `preferredLocaleIdentifier` is `nil`. We honour that choice rather than
    /// silently mapping it to the system locale's primary language: the issue
    /// allows showing "Auto-detect" as the visible default and the picker UX
    /// is clearer when the explicit choice round-trips visibly.
    private func transcriptionLanguageSelection() -> String {
        guard let localeIdentifier = model.transcriptionConfiguration.preferredLocaleIdentifier else {
            return Self.autoDetectLanguageSelection
        }

        let primary = LanguagePolicy.whisperLanguageArgument(for: localeIdentifier)
        if let match = Self.curatedTranscriptionLanguages.first(where: { $0.identifier == primary }) {
            return match.identifier
        }
        return Self.autoDetectLanguageSelection
    }

    /// True when the runtime resolved Apple Speech as the active backend
    /// (typically because Whisper is unavailable). Used to surface the
    /// auto-detect-requires-Whisper hint inline.
    private var appleSpeechIsActiveBackend: Bool {
        guard let summary = model.transcriptionRuntimeState?.activePlanSummary else {
            return false
        }
        return summary.localizedCaseInsensitiveContains("Apple Speech")
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

    /// Returns the BCP 47 language code we use to look up curated quality
    /// hints. Falls back to English when the user has chosen Auto-detect so
    /// the section still renders informative guidance instead of a row of
    /// "no opinion" entries.
    private func targetLanguageBCP47ForHints() -> String {
        guard let identifier = model.transcriptionConfiguration.preferredLocaleIdentifier else {
            return "en"
        }
        return LanguagePolicy.whisperLanguageArgument(for: identifier)
    }

    /// Catalog entries ranked for the user's target language, with already-
    /// installed entries pinned to the top so the user can immediately
    /// confirm what's on disk.
    private func orderedWhisperCatalogItems(
        from state: WhisperModelCatalogState
    ) -> [WhisperModelCatalogItemState] {
        let bcp47 = targetLanguageBCP47ForHints()
        let recommendedOrder = CuratedModelCatalog.recommendations(
            for: bcp47,
            in: state.items.map { $0.catalogEntry }
        )
        let lookup = Dictionary(uniqueKeysWithValues: state.items.map { ($0.id, $0) })
        let ranked = recommendedOrder.compactMap { lookup[$0.id] }
        return ranked.sorted { lhs, rhs in
            let lhsInstalled = lhs.installedModel != nil
            let rhsInstalled = rhs.installedModel != nil
            if lhsInstalled != rhsInstalled {
                return lhsInstalled
            }
            return ranked.firstIndex(where: { $0.id == lhs.id }) ?? 0
                < (ranked.firstIndex(where: { $0.id == rhs.id }) ?? 0)
        }
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

private struct WhisperModelCatalogRow: View {
    let item: WhisperModelCatalogItemState
    let qualityHint: QualityTier?
    let installProgress: Double?
    let isInstalling: Bool
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onRemove: () -> Void

    private var isInstalled: Bool {
        item.installedModel != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.catalogEntry.displayName)
                    .font(.headline)

                if isInstalled {
                    badge("Installed")
                }

                if let qualityHint {
                    badge(qualityHint.displayName)
                }
            }

            HStack(spacing: 12) {
                Text(ByteCountFormatter.string(fromByteCount: item.catalogEntry.sizeBytes, countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(item.catalogEntry.sizeTier.rawValue.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if isInstalling, let progress = installProgress {
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)
            }

            HStack(spacing: 10) {
                if isInstalling {
                    Button("Cancel", role: .cancel, action: onCancel)
                } else if isInstalled {
                    Button("Remove", role: .destructive, action: onRemove)
                } else {
                    Button("Download", action: onDownload)
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

private extension QualityTier {
    var displayName: String {
        switch self {
        case .recommended: "Recommended"
        case .acceptable: "Acceptable"
        case .notRecommended: "Not recommended"
        }
    }
}
