import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(WorkdayManager.self) private var manager

    // Appearance
    @AppStorage(AppSettingsKey.orangeThresholdHours) private var orangeThreshold = AppDefaults
        .orangeThresholdHours
    @AppStorage(AppSettingsKey.redThresholdHours) private var redThreshold = AppDefaults
        .redThresholdHours

    // ArbZG Breaks

    // Notifications
    @AppStorage(AppSettingsKey.notificationsEnabled) private var notificationsEnabled = AppDefaults
        .notificationsEnabled
    @AppStorage(AppSettingsKey.normalNotificationHours) private var normalHours = AppDefaults
        .normalNotificationHours
    @AppStorage(AppSettingsKey.criticalNotificationHours) private var criticalHours = AppDefaults
        .criticalNotificationHours
    @AppStorage(AppSettingsKey.milestoneNotificationHours) private var milestoneHours = AppDefaults
        .milestoneNotificationHours

    // Idle
    @AppStorage(AppSettingsKey.idleThresholdMinutes) private var idleThreshold = AppDefaults
        .idleThresholdMinutes

    // Startup
    @AppStorage(AppSettingsKey.manualPunchMode) private var manualPunchMode = AppDefaults
        .manualPunchMode
    @State private var launchAtLogin = AppDelegate.isLaunchAtLoginEnabled

    // Cloud
    @AppStorage(AppSettingsKey.iCloudSyncEnabled) private var iCloudSync = AppDefaults
        .iCloudSyncEnabled

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("settings.general", systemImage: "gear")
                }

            notificationsTab
                .tabItem {
                    Label("settings.notifications", systemImage: "bell")
                }

            dataTab
                .tabItem {
                    Label("settings.data", systemImage: "folder")
                }
        }
        .frame(width: 520, height: 520)
    }

    // MARK: - General Tab

    var generalTab: some View {
        Form {
            Section(String(localized: "settings.appearance")) {
                HStack {
                    Text("settings.orangeThreshold")
                    Spacer()
                    TextField("settings.orangeThreshold", value: $orangeThreshold, format: .number)
                        .labelsHidden()
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: orangeThreshold) { _, newValue in
                            orangeThreshold = max(0, newValue)
                            if orangeThreshold >= redThreshold {
                                redThreshold = orangeThreshold + 0.5
                            }
                        }
                }
                HStack {
                    Text("settings.redThreshold")
                    Spacer()
                    TextField("settings.redThreshold", value: $redThreshold, format: .number)
                        .labelsHidden()
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: redThreshold) { _, newValue in
                            redThreshold = max(0.5, newValue)
                            if redThreshold <= orangeThreshold {
                                orangeThreshold = redThreshold - 0.5
                            }
                        }
                }
            }

            Section(String(localized: "settings.idleDetection")) {
                HStack {
                    Text("settings.idleThreshold")
                    Spacer()
                    TextField("settings.idleThreshold", value: $idleThreshold, format: .number)
                        .labelsHidden()
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: idleThreshold) { _, newValue in
                            idleThreshold = max(1, newValue)
                        }
                }
            }

            Section(String(localized: "settings.startup")) {
                Toggle(String(localized: "settings.manualPunch"), isOn: $manualPunchMode)
                Toggle(String(localized: "settings.launchAtLogin"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        AppDelegate.setLaunchAtLogin(newValue)
                    }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Notifications Tab

    var notificationsTab: some View {
        Form {
            Section {
                Toggle(
                    String(localized: "settings.enableNotifications"), isOn: $notificationsEnabled)
            }

            Section(String(localized: "settings.thresholds")) {
                HStack {
                    Text("settings.normalHours")
                    Spacer()
                    TextField("settings.normalHours", value: $normalHours, format: .number)
                        .labelsHidden()
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: normalHours) { _, newValue in
                            normalHours = max(0.5, newValue)
                            if criticalHours < normalHours {
                                criticalHours = normalHours
                            }
                            if milestoneHours < criticalHours {
                                milestoneHours = criticalHours
                            }
                        }
                }
                HStack {
                    Text("settings.criticalHours")
                    Spacer()
                    TextField("settings.criticalHours", value: $criticalHours, format: .number)
                        .labelsHidden()
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: criticalHours) { _, newValue in
                            criticalHours = max(normalHours, newValue)
                            if milestoneHours < criticalHours {
                                milestoneHours = criticalHours
                            }
                        }
                }
                HStack {
                    Text("settings.milestoneHours")
                    Spacer()
                    TextField("settings.milestoneHours", value: $milestoneHours, format: .number)
                        .labelsHidden()
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: milestoneHours) { _, newValue in
                            milestoneHours = max(criticalHours, newValue)
                        }
                }
            }

            Text("settings.notificationHelp")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    // MARK: - Data Tab

    private var dataTab: some View {
        Form {
            Section(String(localized: "settings.logs")) {
                Text(manager.persistence.logDirectory.path)
                    .font(DesignTokens.Typography.bodySmall)
                    .foregroundStyle(DesignTokens.Colors.onSurfaceVariant)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button(String(localized: "settings.openLogFolder")) {
                        NSWorkspace.shared.open(manager.persistence.logDirectory)
                    }

                    Button(String(localized: "settings.chooseLogFolder")) {
                        chooseLogFolder()
                    }
                }
            }

            Section(String(localized: "settings.cloudSync")) {
                Toggle(String(localized: "settings.syncICloud"), isOn: $iCloudSync)
                    .onChange(of: iCloudSync) { _, newValue in
                        if newValue {
                            manager.persistence.syncWithCloud()
                        }
                    }

                if iCloudSync {
                    if CloudSyncManager.shared.iCloudAvailable {
                        Label("settings.iCloudConnected", systemImage: "checkmark.icloud")
                            .foregroundStyle(.secondary)
                            .font(.caption)

                        Button(String(localized: "settings.syncNow")) {
                            manager.persistence.syncWithCloud()
                        }
                    } else {
                        Label(
                            String(localized: "settings.iCloudUnavailable"),
                            systemImage: "exclamationmark.icloud"
                        )
                        .foregroundStyle(DesignTokens.Colors.accentOrange)
                        .font(.caption)
                    }
                }
            }

            Section(String(localized: "settings.export")) {
                Button(String(localized: "settings.exportCSV")) {
                    if let url = manager.exportCSV() {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            Section(String(localized: "settings.about")) {
                HStack {
                    Text("settings.version")
                    Spacer()
                    Text(
                        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                            as? String ?? "?"
                    )
                    .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Helpers

    private func chooseLogFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "settings.choosePrompt")
        panel.message = String(localized: "settings.chooseMessage")

        if panel.runModal() == .OK, let url = panel.url {
            manager.persistence.setCustomLogFolder(url)
        }
    }
}
