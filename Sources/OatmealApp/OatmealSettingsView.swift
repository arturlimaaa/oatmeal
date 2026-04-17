import OatmealEdge
import SwiftUI

struct OatmealSettingsView: View {
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
                LabeledContent("Model training", value: "Disabled for third-party providers")
            }
        }
        .task {
            await model.refreshTranscriptionRuntimeState()
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
