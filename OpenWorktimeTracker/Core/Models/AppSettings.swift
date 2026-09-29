import Foundation

enum AppSettingsKey {
    // Defined once in SharedDefaults so the widget target (which cannot see this
    // app-only file) and the app always use identical UserDefaults keys.
    static let orangeThresholdHours = SharedDefaults.orangeThresholdSettingKey
    static let redThresholdHours = SharedDefaults.redThresholdSettingKey
    static let breakAfter6hMinutes = "breakAfter6hMinutes"
    static let breakAfter9hMinutes = "breakAfter9hMinutes"
    static let notificationsEnabled = "notificationsEnabled"
    static let normalNotificationHours = SharedDefaults.normalHoursSettingKey
    static let criticalNotificationHours = "criticalNotificationHours"
    static let milestoneNotificationHours = "milestoneNotificationHours"
    static let launchAtLogin = "launchAtLogin"
    static let idleThresholdMinutes = "idleThresholdMinutes"
    static let logFolderBookmark = "logFolderBookmark"
    static let newDayStartHour = "newDayStartHour"
    static let iCloudSyncEnabled = "iCloudSyncEnabled"
    static let manualPunchMode = "manualPunchMode"
}

enum AppDefaults {
    // Defined once in SharedDefaults for the settings the widget also reads.
    static let orangeThresholdHours = SharedDefaults.orangeThresholdDefault
    static let redThresholdHours = SharedDefaults.redThresholdDefault
    static let normalNotificationHours = SharedDefaults.normalHoursDefault
    static let breakAfter6hMinutes: Int = 30
    static let breakAfter9hMinutes: Int = 45
    static let notificationsEnabled: Bool = true
    static let criticalNotificationHours: Double = 9.83
    static let milestoneNotificationHours: Double = 10.0
    static let launchAtLogin: Bool = true
    static let idleThresholdMinutes: Int = 5
    static let newDayStartHour: Int = 4  // Before 4 AM is still "yesterday"
    static let iCloudSyncEnabled: Bool = false
    /// Off upstream; the zh-Hant fork turns it on in `ForkDefaults`.
    static let manualPunchMode: Bool = false
}

/// zh-Hant fork: personal defaults (manual clock-in, 8h goal, red at 9h, no
/// automatic German break deduction). Registered only in the running app, so
/// the unit tests keep exercising upstream defaults.
enum ForkDefaults {
    static func register(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            AppSettingsKey.manualPunchMode: true,
            AppSettingsKey.breakAfter6hMinutes: 0,
            AppSettingsKey.breakAfter9hMinutes: 0,
            AppSettingsKey.normalNotificationHours: 8.0,
            AppSettingsKey.orangeThresholdHours: 8.0,
            AppSettingsKey.redThresholdHours: 9.0,
            AppSettingsKey.criticalNotificationHours: 9.0,
            AppSettingsKey.milestoneNotificationHours: 10.0,
        ])
    }
}
