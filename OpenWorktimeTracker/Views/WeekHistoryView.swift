import SwiftUI

/// The last seven calendar days as columns, oldest on the left and today last.
/// Each worked day's bar carries its Net Work Time on top and the heatmap's
/// colour, so overtime days stand out; days without work stay as empty slots.
struct WeekHistoryView: View {
    @Environment(WorkdayManager.self) private var manager
    @State private var bars: [WeekBar] = []

    private static let barAreaHeight: CGFloat = 72

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Text("history.last7days")
                    .font(DesignTokens.Typography.labelSmall)
                    .foregroundStyle(DesignTokens.Colors.onSurfaceVariant)
                    .tracking(1.5)
                Spacer()
                Text(weekTotal)
                    .font(DesignTokens.Typography.labelSmall)
                    .foregroundStyle(DesignTokens.Colors.accentBlue)
                    .monospacedDigit()
            }

            let maxHours = WeekBar.chartMaxHours(for: bars, scale: manager.heatScale)
            HStack(alignment: .bottom, spacing: DesignTokens.Spacing.xs) {
                ForEach(bars) { bar in
                    DayColumn(bar: bar, maxHours: maxHours, barAreaHeight: Self.barAreaHeight)
                }
            }
        }
        .onAppear { loadHistory() }
        .onChange(of: manager.logRevision) { _, _ in loadHistory() }
    }

    private func loadHistory() {
        bars = WeekBar.lastSevenDays(
            now: manager.clock.now, newDayStartHour: manager.newDayStartHour, scale: manager.heatScale
        ) { date in
            manager.store.load(for: date).map { entry in
                WeekBar.Log(
                    netWorkTime: manager.workday(for: entry).netWorkTime,
                    startTime: entry.startTime,
                    endTime: entry.endTime)
            }
        }
    }

    private var weekTotal: String {
        let total = bars.reduce(0.0) { $0 + $1.netWorkTime }
        return String(
            format: String(localized: "history.total"),
            total.hoursMinutesFormatted)
    }
}

// MARK: - Day Column

private struct DayColumn: View {
    let bar: WeekBar
    let maxHours: Double
    let barAreaHeight: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            // Bar with its hours sitting right above it
            VStack(spacing: 2) {
                Spacer(minLength: 0)
                Text(bar.hasLog ? bar.netWorkTime.hoursMinutesFormatted : "—")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(hoursColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                RoundedRectangle(cornerRadius: 3)
                    .fill(bar.hasLog ? bar.level.color : DesignTokens.Colors.onSurfaceVariant.opacity(0.18))
                    .frame(height: barHeight)
                    .overlay {
                        if bar.isToday {
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(DesignTokens.Colors.onSurface.opacity(0.55), lineWidth: 1.5)
                        }
                    }
            }
            .frame(height: barAreaHeight + 16)

            Text(Self.weekdayFormatter.string(from: day))
                .font(DesignTokens.Typography.labelMicro)
                .fontWeight(bar.isToday ? .bold : .medium)
                .foregroundStyle(
                    bar.isToday ? DesignTokens.Colors.onSurface : DesignTokens.Colors.onSurfaceVariant)
                .lineLimit(1)
            Text(Self.dateFormatter.string(from: day))
                .font(.system(size: 9))
                .foregroundStyle(DesignTokens.Colors.onSurfaceVariant)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .help(tooltip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(tooltip))
    }

    private var hoursColor: Color {
        guard bar.hasLog else { return DesignTokens.Colors.onSurfaceVariant.opacity(0.6) }
        return bar.level >= .overtime ? bar.level.color : DesignTokens.Colors.onSurface
    }

    private var barHeight: CGFloat {
        guard bar.hasLog, bar.netHours > 0, maxHours > 0 else { return 3 }
        return max(3, barAreaHeight * CGFloat(min(1, bar.netHours / maxHours)))
    }

    private var day: Date {
        Self.parser.date(from: bar.date) ?? Date()
    }

    private var tooltip: String {
        guard let log = bar.log else {
            return String(
                format: String(localized: "heatmap.tooltip.empty"), WorkHeatmapView.tooltipDate(day))
        }
        let summary = WorkHeatmapView.tooltip(
            date: day, startTime: log.startTime, endTime: log.endTime, netHours: bar.netHours)
        guard let overtime = bar.overtimeHoursMinutes else { return summary }
        return summary + "\n"
            + String(format: String(localized: "history.tooltip.overtime"), overtime.hours, overtime.minutes)
    }

    private static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter
    }()
}
