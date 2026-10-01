import SwiftUI

struct SummaryStatsView: View {
    @Environment(WorkdayManager.self) private var manager
    @State private var period: Period = .week
    @State private var entries: [TimeEntry] = []

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
    }

    // MARK: - Data Loading

    private func loadEntries() {
        let all = manager.persistence.loadAll()
        let calendar = Calendar.current
        let now = Date()

        switch period {
        case .week:
            guard
                let weekStart = calendar.date(
                    from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
                )
            else {
                entries = []
                return
            }
            entries = all.filter { entry in
                guard let date = parseDate(entry.date) else { return false }
                return date >= weekStart && date <= now
            }

        case .month:
            let components = calendar.dateComponents([.year, .month], from: now)
            guard let monthStart = calendar.date(from: components) else {
                entries = []
                return
            }
            entries = all.filter { entry in
                guard let date = parseDate(entry.date) else { return false }
                return date >= monthStart && date <= now
            }
        }
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

    private var overtimeTime: TimeInterval {
        totalTime - (Double(workDays) * targetHoursPerDay * 3600)
    }

    private var overtimeFormatted: String {
        let sign = overtimeTime >= 0 ? "+" : "-"
        return sign + abs(overtimeTime).hoursMinutesFormatted
    }

    // MARK: - Helpers

    private func parseDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: dateString)
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
