import ServiceManagement
import SwiftUI

/// Settings window (⌘,).
struct SettingsView: View {
    @Bindable var model: CleanerModel
    /// Login item state lives in the system, not UserDefaults; re-read on appear.
    @ViewState private var loginStatus = SMAppService.mainApp.status
    @ViewState private var loginError: String?
    private let updates = UpdateChecker.shared

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: launchAtLogin)
                    .toggleStyle(.checkbox)
                if loginStatus == .requiresApproval {
                    LabeledContent("Needs your approval in Login Items") {
                        Button("Open Settings…") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if let loginError {
                    Text(loginError).foregroundStyle(.red)
                }
            } header: {
                Text("General")
            }

            Section {
                Toggle("Clean automatically", isOn: $model.autoCleanEnabled)
                Group {
                    Stepper(value: $model.autoCleanEvery, in: 1...30) {
                        Text("Every \(model.autoCleanEvery) \(model.autoCleanUnit.label(model.autoCleanEvery))")
                            .monospacedDigit()
                    }
                    Picker("Repeat", selection: $model.autoCleanUnit) {
                        Text("Hours").tag(AutoCleanUnit.hour)
                        Text("Days").tag(AutoCleanUnit.day)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Ask before cleaning", isOn: $model.autoCleanAsk)
                        .toggleStyle(.checkbox)
                    LabeledContent("Next clean") {
                        Text(model.nextAutoClean?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                    }
                }
                .disabled(!model.autoCleanEnabled)
            } header: {
                Text("Auto Clean")
            } footer: {
                Text(footer).foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Version", value: "\(UpdateChecker.version) (\(UpdateChecker.build))")
                LabeledContent {
                    if case .available(let version, let url) = updates.status {
                        Link("Download \(version)…", destination: url)
                    } else {
                        Button("Check for Updates…") { Task { await updates.check() } }
                            .disabled(updates.status == .checking)
                    }
                } label: {
                    updateStatus
                }
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { loginStatus = SMAppService.mainApp.status }
    }

    @ViewBuilder private var updateStatus: some View {
        switch updates.status {
        case .idle:
            Text("Updates")
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…")
            }
        case .upToDate:
            Label("YK Cleaner is up to date", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .available(let version, _):
            Label("Version \(version) is available", systemImage: "arrow.down.circle.fill")
                .foregroundStyle(.tint)
        case .failed(let message):
            Text(message).foregroundStyle(.red)
        }
    }

    private var footer: String {
        let when = "Runs while YK Cleaner is open; a missed run happens when you next open it."
        return model.autoCleanAsk
            ? "Scans the areas ticked in Cleaner and asks before deleting. " + when
            : "Permanently deletes everything in the areas ticked in Cleaner, without asking. Areas that need an administrator password are skipped. " + when
    }

    private var launchAtLogin: Binding<Bool> {
        Binding {
            loginStatus == .enabled || loginStatus == .requiresApproval
        } set: { on in
            do {
                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                loginError = nil
            } catch {
                loginError = error.localizedDescription
            }
            loginStatus = SMAppService.mainApp.status
        }
    }
}
