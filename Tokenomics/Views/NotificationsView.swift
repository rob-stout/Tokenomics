import SwiftUI
import UserNotifications

/// Settings sub-screen for per-provider notification thresholds and alert window selection
struct NotificationsView: View {
    @ObservedObject var viewModel: UsageViewModel

    /// Live notification permission status — checked when the view appears
    @State private var authStatus: UNAuthorizationStatus = .notDetermined

    /// Local copies of configs so changes are reflected immediately in the UI
    @State private var configs: [ProviderId: SettingsService.NotificationConfig] = [:]
    @State private var alertWindow: SettingsService.AlertWindow = SettingsService.alertWindow

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                // Permission warning
                if authStatus == .denied {
                    deniedBanner
                        .padding(.bottom, 8)
                }

                // Provider alert thresholds
                sectionLabel("PROVIDER ALERTS")

                VStack(spacing: 0) {
                    let connected = viewModel.connectedProviders
                    if connected.isEmpty {
                        Text("No providers connected.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 10)
                    } else {
                        ForEach(connected) { providerId in
                            providerRow(for: providerId)
                            if providerId != connected.last {
                                Divider()
                            }
                        }
                    }
                }

                Text("Notify when usage crosses this threshold.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                    .padding(.bottom, 12)

                Divider()

                // Alert window picker
                sectionLabel("ALERT WINDOW")
                    .padding(.top, 8)

                Picker("", selection: $alertWindow) {
                    ForEach(SettingsService.AlertWindow.allCases, id: \.self) { window in
                        Text(window.displayLabel).tag(window)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: alertWindow) { newValue in
                    SettingsService.alertWindow = newValue
                }

                Text("Which usage window triggers alerts.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .onAppear {
            loadConfigs()
            Task { await checkPermissions() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: { viewModel.showNotifications = false }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Settings")
                }
                .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Text("Notifications")
                .font(.headline)
                .fontWeight(.medium)

            Spacer()

            // Invisible balance element for centering
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text("Settings")
            }
            .font(.caption)
            .hidden()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Permission Denied Banner

    private var deniedBanner: some View {
        Button(action: openSystemNotificationSettings) {
            HStack(spacing: 6) {
                Image(systemName: "bell.slash")
                    .font(.caption)
                Text("Notifications are disabled in System Settings.")
                    .font(.caption2)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "arrow.up.forward.square")
                    .font(.caption2)
            }
            .foregroundStyle(.orange)
            .padding(8)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section Label

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.bottom, 4)
    }

    // MARK: - Provider Row

    @ViewBuilder
    private func providerRow(for providerId: ProviderId) -> some View {
        let binding = configBinding(for: providerId)

        HStack(spacing: 10) {
            Text(providerId.displayName)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Stepper: minus button, threshold label, plus button
            HStack(spacing: 0) {
                Button(action: { adjustThreshold(for: providerId, delta: -10) }) {
                    Image(systemName: "minus")
                        .font(.caption2)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!binding.wrappedValue.isEnabled || binding.wrappedValue.threshold <= 50)

                Text("\(binding.wrappedValue.threshold)%")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 36)

                Button(action: { adjustThreshold(for: providerId, delta: 10) }) {
                    Image(systemName: "plus")
                        .font(.caption2)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!binding.wrappedValue.isEnabled || binding.wrappedValue.threshold >= 100)
            }
            .foregroundStyle(binding.wrappedValue.isEnabled ? .primary : .secondary)

            Toggle("", isOn: Binding(
                get: { binding.wrappedValue.isEnabled },
                set: { newValue in
                    var config = binding.wrappedValue
                    config.isEnabled = newValue
                    configs[providerId] = config
                    SettingsService.setNotificationConfig(config, for: providerId)
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func configBinding(for providerId: ProviderId) -> Binding<SettingsService.NotificationConfig> {
        Binding(
            get: { configs[providerId] ?? SettingsService.NotificationConfig() },
            set: { configs[providerId] = $0 }
        )
    }

    private func adjustThreshold(for providerId: ProviderId, delta: Int) {
        var config = configs[providerId] ?? SettingsService.NotificationConfig()
        config.threshold = min(max(config.threshold + delta, 50), 100)
        configs[providerId] = config
        SettingsService.setNotificationConfig(config, for: providerId)
    }

    private func loadConfigs() {
        for id in ProviderId.allCases {
            configs[id] = SettingsService.notificationConfig(for: id)
        }
        alertWindow = SettingsService.alertWindow
    }

    @MainActor
    private func checkPermissions() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authStatus = settings.authorizationStatus
    }

    private func openSystemNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Notifications Row Subtitle

extension UsageViewModel {
    /// Subtitle text for the Notifications row in Settings
    var notificationsSubtitle: String {
        let connected = connectedProviders
        guard !connected.isEmpty else { return "No providers" }

        let configs = connected.map { SettingsService.notificationConfig(for: $0) }

        // All disabled
        if configs.allSatisfy({ !$0.isEnabled }) {
            return "Off"
        }

        // All enabled with the same threshold
        let enabledConfigs = configs.filter(\.isEnabled)
        let thresholds = Set(enabledConfigs.map(\.threshold))
        if thresholds.count == 1, enabledConfigs.count == connected.count,
           let t = thresholds.first {
            return "\(t)% — All providers"
        }

        return "Custom"
    }
}
