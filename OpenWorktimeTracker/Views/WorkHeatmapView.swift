import SwiftUI

/// Contribution-style calendar of the last six months' Net Work Time, so
/// overtime days stand out at a glance. The computation lives in `WorkHeatmap`.
struct WorkHeatmapView: View {
    @Environment(WorkdayManager.self) private var manager
    @State private var logs: [HeatmapLog] = []

    private static let cellSize: CGFloat = 10
    private static let cellGap: CGFloat = 2
    private static let weekdayLabelWidth: CGFloat = 14

    var body: some View {
        let heatmap = WorkHeatmap(logs: logs, scale: manager.heatScale, today: Date())

        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("heatmap.title")
                .font(DesignTokens.Typography.labelSmall)
                .foregroundStyle(DesignTokens.Colors.onSurfaceVariant)
                .tracking(1.5)

            statsRow(heatmap.stats)

            ViewThatFits(in: .horizontal) {
                grid(heatmap)
                ScrollView(.horizontal, showsIndicators: false) {
                    grid(heatmap)
                }
                .defaultScrollAnchor(.trailing)
            }

            legend(heatmap.scale)
        }
        .onAppear { loadLogs() }
        .onChange(of: manager.logRevision) { _, _ in loadLogs() }
    }

    // MARK: - Data Loading

    private func loadLogs() {
        logs = manager.persistence.loadAll().map { entry in
            HeatmapLog(
                date: entry.date,
                netHours: manager.workday(for: entry).netWorkTime.inHours,
                startTime: entry.startTime,
                endTime: entry.endTime
            )
        }
    }

    // MARK: - Stats

    private func statsRow(_ stats: HeatmapStats) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            HeatmapStat(
                label: String(localized: "heatmap.workedDays"),
                value: String(format: String(localized: "heatmap.days"), stats.workedDays)
            )
            HeatmapStat(
                label: String(localized: "heatmap.overtimeDays"),
                value: String(format: String(localized: "heatmap.days"), stats.overtimeDays),
                valueColor: stats.overtimeDays > 0 ? DesignTokens.Colors.accentOrange : nil
            )
            HeatmapStat(
                label: String(localized: "heatmap.average"),
                value: String(format: String(localized: "heatmap.hours"), Self.hours(stats.averageHours))
            )
        }
    }

    // MARK: - Grid

    private func grid(_ heatmap: WorkHeatmap) -> some View {
        let column = Self.cellSize + Self.cellGap
        let labels = Dictionary(
            heatmap.monthLabelColumns().map { ($0.column, $0.date) }, uniquingKeysWith: { first, _ in first })

        return VStack(alignment: .leading, spacing: Self.cellGap) {
            // Month labels, each starting over its column and free to overflow to the right
            HStack(spacing: 0) {
                Color.clear.frame(width: Self.weekdayLabelWidth + Self.cellGap, height: 1)
                ForEach(heatmap.weeks.indices, id: \.self) { index in
                    Color.clear
                        .frame(width: column, height: 12)
                        .overlay(alignment: .leading) {
                            if let date = labels[index] {
                                Text(Self.monthFormatter.string(from: date))
                                    .font(.system(size: 9))
                                    .foregroundStyle(DesignTokens.Colors.onSurfaceVariant)
                                    .fixedSize()
                            }
                        }
                }
            }

            HStack(alignment: .top, spacing: Self.cellGap) {
                weekdayLabels
                ForEach(heatmap.weeks.indices, id: \.self) { index in
                    VStack(spacing: Self.cellGap) {
                        ForEach(heatmap.weeks[index]) { day in
                            HeatmapCell(day: day, size: Self.cellSize)
                        }
                    }
                }
            }
        }
        .fixedSize()
    }

    /// Monday, Wednesday and Friday, like GitHub.
    private var weekdayLabels: some View {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        return VStack(alignment: .leading, spacing: Self.cellGap) {
            ForEach(0..<7, id: \.self) { row in
                Text(row % 2 == 1 && row < symbols.count ? symbols[row] : "")
                    .font(.system(size: 8))
                    .foregroundStyle(DesignTokens.Colors.onSurfaceVariant)
                    .frame(width: Self.weekdayLabelWidth, height: Self.cellSize, alignment: .leading)
            }
        }
    }

    // MARK: - Legend

    private func legend(_ scale: HeatScale) -> some View {
        let goal = Self.hours(scale.goalHours)
        let red = Self.hours(scale.redHours)
        return HStack(spacing: DesignTokens.Spacing.xs) {
            ForEach([HeatLevel.none, .light, .medium, .deep], id: \.self) { level in
                HeatmapSwatch(level: level, size: Self.cellSize)
            }
            legendLabel(String(format: String(localized: "heatmap.legend.upTo"), goal))
            HeatmapSwatch(level: .overtime, size: Self.cellSize)
                .padding(.leading, DesignTokens.Spacing.xs)
            legendLabel(String(format: String(localized: "heatmap.legend.between"), goal, red))
            HeatmapSwatch(level: .excessive, size: Self.cellSize)
                .padding(.leading, DesignTokens.Spacing.xs)
            legendLabel(String(format: String(localized: "heatmap.legend.above"), red))
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func legendLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9))
            .foregroundStyle(DesignTokens.Colors.onSurfaceVariant)
            .monospacedDigit()
    }

    // MARK: - Formatting

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter
    }()

    private static let hoursFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    /// `8`, `9.5` — hours with at most one decimal.
    static func hours(_ value: Double) -> String {
        hoursFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }
}

// MARK: - Cell

private struct HeatmapCell: View {
    let day: HeatmapDay
    let size: CGFloat

    var body: some View {
        Group {
            if day.isTracked {
                HeatmapSwatch(level: day.level, size: size)
                    .help(tooltip)
                    .accessibilityLabel(Text(tooltip))
            } else {
                // Outside the tracked range: in the future, or before the first log
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(DesignTokens.Colors.outlineVariant.opacity(0.5), lineWidth: 0.5)
                    .frame(width: size, height: size)
                    .accessibilityHidden(true)
            }
        }
    }

    private var tooltip: String {
        let date = String(
            format: String(localized: "heatmap.tooltip.date"),
            Self.dateFormatter.string(from: day.date),
            Self.weekdayFormatter.string(from: day.date))
        guard let log = day.log, log.netHours > 0 else {
            return String(format: String(localized: "heatmap.tooltip.empty"), date)
        }
        return String(
            format: String(localized: "heatmap.tooltip"),
            date,
            log.startTime.hoursMinutesString,
            log.endTime?.hoursMinutesString ?? String(localized: "heatmap.running"),
            WorkHeatmapView.hours(log.netHours))
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()
}

// MARK: - Swatch

private struct HeatmapSwatch: View {
    let level: HeatLevel
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: size, height: size)
    }

    private var color: Color {
        switch level {
        case .none: return DesignTokens.Colors.surfaceContainerHighest
        case .light: return DesignTokens.Colors.accentGreen.opacity(0.3)
        case .medium: return DesignTokens.Colors.accentGreen.opacity(0.6)
        case .deep: return DesignTokens.Colors.accentGreen
        case .overtime: return DesignTokens.Colors.accentOrange
        case .excessive: return DesignTokens.Colors.accentRed
        }
    }
}

// MARK: - Stat

private struct HeatmapStat: View {
    let label: String
    let value: String
    var valueColor: Color?

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(DesignTokens.Typography.labelMicro)
                .foregroundStyle(DesignTokens.Colors.onSurfaceVariant)
            Text(value)
                .font(DesignTokens.Typography.labelLarge)
                .foregroundStyle(valueColor ?? DesignTokens.Colors.onSurface)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(DesignTokens.Colors.surfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .accessibilityElement(children: .combine)
    }
}
