import AppKit

@main
enum OpenWorktimeTrackerApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            ForkDefaults.register()
        }
        let delegate = AppDelegate()
        let manager = WorkdayManager()
        delegate.workdayManager = manager
        app.delegate = delegate
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            manager.bootstrap()
        }
        withExtendedLifetime(delegate) {
            // Keep status-item mouse routing independent of SwiftUI's scene lifecycle.
            app.run()
        }
    }
}
