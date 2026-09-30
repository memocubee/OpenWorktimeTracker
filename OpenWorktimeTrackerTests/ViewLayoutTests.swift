import AppKit
import SwiftUI
import Vision
import XCTest

@testable import OpenWorktimeTracker

final class ViewLayoutTests: XCTestCase {
    @MainActor
    func testNormalStatusUsesNativeAdaptiveForeground() throws {
        let manager = WorkdayManager(store: InMemoryDailyLogStore())
        let controller = MenuBarController(manager: manager)
        let button = try XCTUnwrap(controller.statusItem.button)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            button.appearance = NSAppearance(named: appearance)
            XCTAssertNil(button.contentTintColor, "Let the status bar choose its contrasting foreground")
            XCTAssertEqual(
                button.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
                .controlTextColor,
                "Use the native title's foreground rather than an explicit label or threshold color")
            XCTAssertTrue(try XCTUnwrap(button.image).isTemplate)
            XCTAssertEqual(button.title, manager.menuBarTitle)
        }
    }

    @MainActor
    func testStatusRestoresNativeForegroundAfterThresholdColors() async throws {
        let suiteName = "status-colors-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let clock = ManualClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        let manager = WorkdayManager(
            defaults: defaults, clock: clock, store: InMemoryDailyLogStore(),
            idleDetector: IdleDetector(clock: clock, idleTime: { 0 }),
            widgetStore: SharedDefaults(defaults: defaults))
        let controller = MenuBarController(manager: manager)
        let button = try XCTUnwrap(controller.statusItem.button)
        manager.startNewDay()
        for (hours, level) in [(9.0, ThresholdLevel.elevated), (11.0, .critical), (1.0, .normal)] {
            manager.updateStartTime(clock.now.addingTimeInterval(-hours * 3600))
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(manager.thresholdLevel, level)
            XCTAssertNil(button.contentTintColor)
            let image = try XCTUnwrap(button.image)
            if level == .normal {
                XCTAssertTrue(image.isTemplate)
                XCTAssertEqual(button.title, manager.menuBarTitle)
            } else {
                XCTAssertFalse(image.isTemplate)
                XCTAssertEqual(button.title, "")
                XCTAssertTrue(button.accessibilityLabel()?.contains(manager.menuBarTitle) == true)
                try assertThresholdPixels(in: image)
            }
        }
        manager.endDay()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(button.contentTintColor)
        XCTAssertEqual(
            button.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
            .controlTextColor)
        XCTAssertTrue(try XCTUnwrap(button.image).isTemplate)
    }

    private func assertThresholdPixels(in image: NSImage) throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        var iconPixels = 0
        var textPixels = 0
        let iconWidth = Int(20 * CGFloat(bitmap.pixelsWide) / image.size.width)
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if color.alphaComponent > 0.5 && color.redComponent > color.greenComponent * 1.1
                    && color.redComponent > color.blueComponent * 1.1 {
                    if x < iconWidth { iconPixels += 1 } else { textPixels += 1 }
                }
            }
        }
        XCTAssertGreaterThan(iconPixels, 20, "The icon must render in its threshold color, not black")
        XCTAssertGreaterThan(textPixels, 20, "The time must render in its threshold color, not black")
    }

    @MainActor
    func testSettingsRowsRemainReadableInBothLanguagesAndAppearances() async throws {
        for language in ["de", "en"] {
            for dark in [false, true] {
                for (content, labels) in [
                    (AnyView(SettingsView().generalTab), [
                        "settings.orangeThreshold", "settings.redThreshold",
                        "settings.breakAfter6h", "settings.breakAfter9h", "settings.idleThreshold"
                    ]),
                    (AnyView(SettingsView().notificationsTab), [
                        "settings.normalHours", "settings.criticalHours", "settings.milestoneHours"
                    ])
                ] {
                    let host = NSHostingView(rootView: content.frame(width: 520, height: 480)
                        .environment(\.locale, Locale(identifier: language))
                        .environment(\.colorScheme, dark ? .dark : .light))
                    let window = NSWindow(
                        contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
                        styleMask: [.titled], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    window.contentView = host
                    window.orderFront(nil)
                    defer { window.close() }
                    try await Task.sleep(for: .milliseconds(100))
                    host.layoutSubtreeIfNeeded()
                    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
                    attachment.name = "settings-\(labels.count)-\(language)-\(dark)"
                    attachment.lifetime = .keepAlways
                    add(attachment)

                    try assertSettingsContents(image: XCTUnwrap(bitmap.cgImage), labels: labels, language: language)
                }
            }
        }
    }

    private func assertSettingsContents(image: CGImage, labels: [String], language: String) throws {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [language]
        try VNImageRequestHandler(cgImage: image).perform([request])
        let observations = request.results ?? []
        let bundlePath = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
        let bundle = try XCTUnwrap(Bundle(path: bundlePath))
        for key in labels {
            let label = bundle.localizedString(forKey: key, value: nil, table: nil)
            let normalized = label.filter(\.isLetter).lowercased()
            let row = try XCTUnwrap(observations.first {
                $0.topCandidates(1).first?.string.filter(\.isLetter).lowercased().contains(normalized) == true
            }, "Every settings row must remain readable: \(label)")
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            request.regionOfInterest = CGRect(
                x: 0.86, y: row.boundingBox.minY - 0.01, width: 0.12, height: row.boundingBox.height + 0.02)
            try VNImageRequestHandler(cgImage: image).perform([request])
            let values = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            XCTAssertEqual(values.count, 1, "One readable value beside \(label): \(values)")
            for value in values {
                XCTAssertNotNil(
                    value.range(of: #"^\d+([.,]\d+)?$"#, options: .regularExpression),
                    "No duplicate label fragments in the value column: \(value)")
            }
        }
    }

    @MainActor
    func testNativeApplicationPreservesEditingShortcuts() throws {
        let delegate = AppDelegate()
        let menu = delegate.makeMainMenu()
        let appMenu = try XCTUnwrap(menu.items.first?.submenu)
        XCTAssertEqual(appMenu.items.first?.keyEquivalent, ",")
        XCTAssertTrue(appMenu.items.first?.target === delegate)
        let editMenu = try XCTUnwrap(menu.items.dropFirst().first?.submenu)
        for (item, expected) in zip(editMenu.items, [
            ("undo:", "z"), ("redo:", "Z"), ("cut:", "x"),
            ("copy:", "c"), ("paste:", "v"), ("selectAll:", "a")
        ]) {
            XCTAssertEqual(item.action, Selector(expected.0))
            XCTAssertEqual(item.keyEquivalent, expected.1)
            XCTAssertNil(item.target)
        }
        XCTAssertEqual(editMenu.items.count, 6)
    }

    @MainActor
    func testNativeStatusButtonOpensAndClosesExistingDashboard() async throws {
        XCTAssertTrue(NSApp.delegate is AppDelegate)
        let manager = WorkdayManager(store: InMemoryDailyLogStore())
        let controller = MenuBarController(manager: manager)
        let button = try XCTUnwrap(controller.statusItem.button)
        XCTAssertTrue(button.target === controller)
        XCTAssertNotNil(button.action)
        XCTAssertFalse(controller.popover.isShown)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(button.sendAction(button.action, to: button.target))
        for _ in 0..<30 where !controller.popover.isShown {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(controller.popover.isShown)
        XCTAssertEqual(
            controller.popover.contentSize,
            NSSize(width: DesignTokens.popoverWidth, height: DesignTokens.popoverMinHeight))
        XCTAssertTrue(button.sendAction(button.action, to: button.target))
        for _ in 0..<30 where controller.popover.isShown {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertFalse(controller.popover.isShown)
        XCTAssertEqual(manager.state, .notStarted)
    }

    @MainActor
    func testPromptsFitInCompactWindowsInBothAppearances() throws {
        let manager = WorkdayManager(store: InMemoryDailyLogStore())
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        for language in ["de", "en"] {
            for dark in [false, true] {
                for midnight in [false, true] {
                    let period = IdlePeriod(
                        idleStart: end.addingTimeInterval(midnight ? -50_400 : -2_700),
                        idleEnd: end, spansMidnight: midnight)
                    try assertLayout(
                        IdlePromptView(idlePeriod: period).environment(manager),
                        name: "idle-\(language)-\(dark)-\(midnight)",
                        language: language, dark: dark,
                        bounds: CGSize(width: DesignTokens.promptWidth, height: 640))
                }
                try assertLayout(
                    MaxHoursPromptView(hours: 10).environment(manager),
                    name: "max-hours-\(language)-\(dark)",
                    language: language, dark: dark,
                    bounds: CGSize(width: DesignTokens.promptWidth, height: 480))
            }
        }
    }

    @MainActor
    func testMetricCardsFitPopoverWidthBeforeStarting() throws {
        let manager = WorkdayManager(store: InMemoryDailyLogStore())
        for language in ["de", "en"] {
            try assertLayout(
                MetricCardsView().environment(manager)
                    .frame(width: DesignTokens.popoverWidth - 2 * DesignTokens.Spacing.lg),
                name: "metrics-not-started-\(language)", language: language, dark: false,
                bounds: CGSize(
                    width: DesignTokens.popoverWidth - 2 * DesignTokens.Spacing.lg, height: 250))
        }
    }

    @MainActor
    func testLogEditorFitsNarrowDetailColumn() throws {
        let manager = WorkdayManager(store: InMemoryDailyLogStore())
        var entry = TimeEntry(startTime: Date(timeIntervalSince1970: 1_700_000_000))
        entry.endTime = entry.startTime.addingTimeInterval(8 * 3600)
        entry.status = .ended
        try assertLayout(
            LogEntryEditView(entry: entry, manager: manager, onSave: { _ in }, onDelete: { _ in })
                .frame(width: 380, height: 450),
            name: "log-editor-narrow", language: "de", dark: false,
            bounds: CGSize(width: 380, height: 450))
    }

    @MainActor
    private func assertLayout<Content: View>(
        _ content: Content, name: String, language: String, dark: Bool,
        bounds: CGSize
    ) throws {
        let host = NSHostingView(rootView: content
            .background(DesignTokens.Colors.surface)
            .environment(\.locale, Locale(identifier: language))
            .environment(\.colorScheme, dark ? .dark : .light))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let size = host.fittingSize
        XCTAssertEqual(size.width, bounds.width, accuracy: 1, name)
        XCTAssertGreaterThan(size.height, 0, name)
        XCTAssertLessThanOrEqual(size.height, bounds.height, name)
        host.setFrameSize(size)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
