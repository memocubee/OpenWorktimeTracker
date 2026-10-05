import SwiftUI

/// The two halves of the popover: today's clock and actions, or the history.
enum MenuBarTab: String, CaseIterable {
    case today
    case records

    /// Remembers the last tab across popover openings.
    static let storageKey = "menuBarSelectedTab"

    var label: LocalizedStringKey {
        switch self {
        case .today: return "menubar.tab.today"
        case .records: return "menubar.tab.records"
        }
    }
}

struct MenuBarView: View {
    @Environment(WorkdayManager.self) private var manager
    @AppStorage(MenuBarTab.storageKey) private var selectedTab: MenuBarTab = .today
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            tabPicker

            switch selectedTab {
            case .today:
                headerSection

                Divider().opacity(0.15)

                ScrollView {
                    TodayTabView()
                        .padding(DesignTokens.Spacing.lg)
                }

                actionButtons
                    .padding(DesignTokens.Spacing.lg)
                    .background(DesignTokens.Colors.surfaceContainer)

            case .records:
                Divider().opacity(0.15)
                    .padding(.top, DesignTokens.Spacing.sm)

                ScrollView {
                    RecordsTabView()
                        .padding(DesignTokens.Spacing.lg)
                }

                HStack {
                    Spacer()
                    moreMenu
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.vertical, DesignTokens.Spacing.sm)
                .background(DesignTokens.Colors.surfaceContainer)
            }
        }
        .frame(width: DesignTokens.popoverWidth, height: DesignTokens.popoverMinHeight)
        .background(DesignTokens.Colors.surface)
        .environment(manager)
    }

    // MARK: - Tabs

    private var tabPicker: some View {
        Picker("menubar.tab", selection: $selectedTab) {
            ForEach(MenuBarTab.allCases, id: \.self) { tab in
                Text(tab.label).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.top, DesignTokens.Spacing.md)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    String(
                        format: String(localized: "menubar.workday"),
                        manager.currentEntry?.date ?? Date().dateString)
                )
                .font(DesignTokens.Typography.headlineSmall)
                .foregroundStyle(DesignTokens.Colors.onSurface)

                Text("timer.accessibility.netWorkTime")
                    .font(DesignTokens.Typography.labelSmall)
                    .foregroundStyle(DesignTokens.Colors.onSurfaceVariant)
            }

            Spacer()

            statusBadge
        }
        .padding(DesignTokens.Spacing.lg)
        .accessibilityElement(children: .combine)
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            if manager.state == .running {
                Image(systemName: "record.circle")
                    .accessibilityHidden(true)
            } else if manager.state == .paused {
                Image(systemName: "pause.circle")
                    .accessibilityHidden(true)
            }
            Text(manager.state.localizedLabel)
                .font(DesignTokens.Typography.labelMicro)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(stateColor.opacity(0.15))
        .clipShape(Capsule())
        .foregroundStyle(stateColor)
    }

    // MARK: - Actions

    private var actionButtons: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            if manager.state == .notStarted {
                ActionButton(
                    title: String(localized: "menubar.start"), icon: "play.fill",
                    style: .primary
                ) {
                    manager.startNewDay()
                }
            } else if manager.state == .running {
                ActionButton(
                    title: String(localized: "menubar.pause"), icon: "pause.fill",
                    style: .primary
                ) {
                    manager.pause()
                }
            } else if manager.state == .paused {
                ActionButton(
                    title: String(localized: "menubar.resume"), icon: "play.fill",
                    style: .primary
                ) {
                    manager.resume()
                }
            } else if manager.state == .ended {
                ActionButton(
                    title: String(localized: "menubar.restart"), icon: "arrow.counterclockwise",
                    style: .secondary
                ) {
                    manager.restartDay()
                }
            }

            if manager.state == .running || manager.state == .paused {
                ActionButton(
                    title: String(localized: "menubar.endDay"), icon: "stop.fill",
                    style: .secondary
                ) {
                    manager.endDay()
                }
            }

            moreMenu
        }
    }

    private var moreMenu: some View {
        Menu {
            Button(String(localized: "menubar.logEditor")) {
                LogEditorWindowController.shared.show(manager: manager)
            }
            Button(String(localized: "menubar.openLogFolder")) {
                NSWorkspace.shared.open(manager.persistence.logDirectory)
            }
            Button(String(localized: "menubar.exportCSV")) {
                if let url = manager.exportCSV() {
                    NSWorkspace.shared.open(url)
                }
            }
            Divider()
            Button(String(localized: "menubar.settings")) {
                onOpenSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            Divider()
            Button(String(localized: "menubar.quit")) {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "ellipsis.circle")
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
            .font(DesignTokens.Typography.bodySmall)
            .foregroundStyle(DesignTokens.Colors.onSurfaceVariant)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(DesignTokens.Colors.surfaceContainerHigh)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel(Text("menubar.moreActions"))
        .help(Text("menubar.moreActions"))
    }

    // MARK: - Helpers

    private var stateColor: Color {
        manager.state.accent.color
    }
}

// MARK: - Today Tab

/// The clock, today's figures and the note. Actions sit in the popover's footer.
struct TodayTabView: View {
    @Environment(WorkdayManager.self) private var manager
    @State private var noteText = ""

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            TimerDisplayView()

            MetricCardsView()

            if manager.currentEntry != nil {
                noteSection
            }
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("menubar.note")
                .font(DesignTokens.Typography.labelSmall)
                .foregroundStyle(DesignTokens.Colors.onSurfaceVariant)
                .textCase(.uppercase)
                .tracking(1.5)

            TextField(
                String(localized: "menubar.note.placeholder"), text: $noteText, axis: .vertical
            )
            .textFieldStyle(.plain)
            .accessibilityLabel(Text("menubar.note"))
            .font(DesignTokens.Typography.bodySmall)
            .lineLimit(2...4)
            .padding(DesignTokens.Spacing.sm)
            .background(DesignTokens.Colors.surfaceContainerLow)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            .onChange(of: noteText) { _, newValue in
                manager.updateNote(newValue)
            }
            .onAppear {
                noteText = manager.currentEntry?.note ?? ""
            }
            .onChange(of: manager.currentEntry?.note) { _, _ in
                noteText = manager.currentEntry?.note ?? ""
            }
        }
    }
}

// MARK: - Records Tab

/// History: the six-month heatmap first, then the last seven days, then the
/// week or month totals.
struct RecordsTabView: View {
    /// The week paged to above, which the summary's week totals follow.
    @State private var weekOffset = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            WorkHeatmapView()

            Divider().opacity(0.15)

            WeekHistoryView(offset: $weekOffset)

            Divider().opacity(0.15)

            SummaryStatsView(weekOffset: weekOffset)
        }
    }
}
