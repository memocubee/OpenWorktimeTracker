import SwiftUI

struct SummaryStatsView: View {
    @Environment(WorkdayManager.self) private var manager
    /// The week the week history is showing: 0 is this week, -1 last week.
    var weekOffset = 0
    @State private var period: Period = .week
    @State private var entries: [TimeEntry] = []
    /// Expected Hours for the working days of the period so far.
    @State private var expected: TimeInterval = 0

    enum Period: String, CaseIterable {
        case week
        case month

        var label: LocalizedStringKey {
            switch self {
            case .week: return "summary.week"
            case .month: return "summary.month"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            // Header with picker
            HStack {
                Text("summary.title")
                    .font(DesignTokens.Typography.labelSmall)
                    .foregroundStyle(DesignTokens.Colors.onSurfaceVariant)
                    .tracking(1.5)
                Spacer()
                Picker("summary.period", selection: $period) {
                    ForEach(Period.allCases, id: \.self) { option in
                        periodLabel(option).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 170)
            }

            if entries.isEmpty {
                Text("summary.noData")
                    .font(DesignTokens.Typography.bodySmall)
                    .foregroundStyle(DesignTokens.Colors.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, DesignTokens.Spacing.sm)
            } else {
                // Stats grid
                LazyVGrid(
                    columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: DesignTokens.Spacing.sm
                ) {
                    StatCard(
                        label: String(localized: "summary.totalHours"),
                        value: totalTime.hoursMinutesFormatted,
                        icon: "clock",
                        color: DesignTokens.Colors.accentBlue
                    )
                    StatCard(
                        label: String(localized: "summary.workDays"),
                        value: "\(workDays)",
                        icon: "calendar",
                        color: DesignTokens.Colors.accentGreen
                    )
                    StatCard(
                        label: String(localized: "summary.dailyAvg"),
                        value: dailyAverage.hoursMinutesFormatted,
                        icon: "chart.bar",
                        color: DesignTokens.Colors.accentOrange
                    )
                    StatCard(
                        label: String(localized: "summary.overtime"),
                        value: overtimeFormatted,
                        icon: overtimeTime >= 0 ? "arrow.up.right" : "arrow.down.right",
                        color: overtimeTime >= 0
                            ? DesignTokens.Colors.accentRed : DesignTokens.Colors.accentGreen
                    )
                }
            }
        }
        .onAppear { loadEntries() }
        .onChange(of: period) { _, _ in loadEntries() }
        .onChange(of: weekOffset) { _, _ in loadEntries() }
        .onChange(of: manager.logRevision) { _, _ in loadEntries() }
        .onChange(of: HolidayStore.shared.calendar.years) { _, _ in loadEntries() }
    }

    // MARK: - Data Loading

    /// The week is the Monday-to-Sunday week paged to above; the month is
    /// this month. Neither runs past the effective today.
    private func loadEntries() {
        let today = WorkdayDetector(newDayStartHour: manager.newDayStartHour)
            .effectiveDateString(for: manager.clock.now)
        let range: (first: String, last: String)?
        switch period {
        case .week: range = WorkWeek.bounds(offset: weekOffset, today: today)
        case .month: range = (String(today.prefix(8)) + "01", today)
        }
        guard let range else {
            entries = []
            expected = 0
            return
        }
        let end = min(range.last, today)
        entries = manager.persistence.loadAll().filter { $0.date >= range.first && $0.date <= end }

        // A past week owes every working day; today only once it has been started
        let lastOwedDay =
            end < today || entries.contains { $0.date == today } ? end : DayString.adding(-1, to: today) ?? today
        expected = WorkWeek.expectedHours(
            from: range.first, through: lastOwedDay, goalHours: targetHoursPerDay,
            holidays: HolidayStore.shared.calendar)
    }

    /// 本週, 上週, or the Monday of a week further back.
    private func periodLabel(_ option: Period) -> Text {
        guard option == .week, weekOffset != 0 else { return Text(option.label) }
        if weekOffset == -1 { return Text("week.lastWeek") }
        let today = WorkdayDetector(newDayStartHour: manager.newDayStartHour)
            .effectiveDateString(for: manager.clock.now)
        let monday = WorkWeek.bounds(offset: weekOffset, today: today).flatMap { DayString.date($0.first) }
        return Text(
            String(
                format: String(localized: "summary.weekOf"),
                monday.map(WeekHistoryView.dateFormatter.string(from:)) ?? ""))
    }

    // MARK: - Computed Stats

    private var totalTime: TimeInterval {
        entries.reduce(0) { $0 + manager.workday(for: $1).netWorkTime }
    }

    private var workDays: Int {
        entries.count
    }

    private var dailyAverage: TimeInterval {
        guard workDays > 0 else { return 0 }
        return totalTime / Double(workDays)
    }

    private var targetHoursPerDay: Double {
        manager.notificationThresholds.normalHours
    }

    /// Measured against the Expected Hours, so public holidays owe nothing
    /// and a weekend worked counts in full.
    private var overtimeTime: TimeInterval {
        totalTime - expected
    }

    private var overtimeFormatted: String {
        let sign = overtimeTime >= 0 ? "+" : "-"
        return sign + abs(overtimeTime).hoursMinutesFormatted
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(color)
                Text(label)
                    .font(DesignTokens.Typography.labelMicro)
                    .foregroundStyle(DesignTokens.Colors.onSurfaceVariant)
            }

            Text(value)
                .font(DesignTokens.Typography.titleMedium)
                .foregroundStyle(DesignTokens.Colors.onSurface)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.surfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .accessibilityElement(children: .combine)
    }
}
