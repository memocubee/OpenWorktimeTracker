import SwiftUI

struct SummaryStatsView: View {
    @Environment(WorkdayManager.self) private var manager
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
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
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
        .onChange(of: manager.logRevision) { _, _ in loadEntries() }
        .onChange(of: HolidayStore.shared.calendar.years) { _, _ in loadEntries() }
    }

    // MARK: - Data Loading

    /// The week runs Monday to Sunday like the week history; both periods end
    /// on the effective today.
    private func loadEntries() {
        let today = WorkdayDetector(newDayStartHour: manager.newDayStartHour)
            .effectiveDateString(for: manager.clock.now)
        let start: String?
        switch period {
        case .week: start = DayString.monday(of: today)
        case .month: start = String(today.prefix(8)) + "01"
        }
        guard let start else {
            entries = []
            expected = 0
            return
        }
        entries = manager.persistence.loadAll().filter { $0.date >= start && $0.date <= today }

        // Today only owes hours once it has been started
        let lastOwedDay = entries.contains { $0.date == today } ? today : DayString.adding(-1, to: today) ?? today
        expected = WorkWeek.expectedHours(
            from: start, through: lastOwedDay, goalHours: targetHoursPerDay,
            holidays: HolidayStore.shared.calendar)
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
