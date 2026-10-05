import SwiftUI

/// One Monday-to-Sunday week at a time, this week first, paged with arrows.
/// The header weighs Net Work Time against the week's Expected Hours, the
/// columns carry the heatmap's colours, and Public Holidays are called out so
/// it is clear which days are meant to be off.
struct WeekHistoryView: View {
    @Environment(WorkdayManager.self) private var manager
    @State private var offset: Int
    @State private var week: WorkWeek?

    private static let barAreaHeight: CGFloat = 52

    /// `initialOffset` weeks from this one: -1 opens on last week.
    init(initialOffset: Int = 0) {
        _offset = State(initialValue: min(0, initialOffset))
    }

    var body: some View {
        // Until the first load lands, read the week directly so the first frame is complete
        let week = self.week ?? currentWeek()
        let maxHours = WeekBar.chartMaxHours(for: week.bars, scale: manager.heatScale)

        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                header(week)
                progress(week)
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                HStack(alignment: .bottom, spacing: DesignTokens.Spacing.xs) {
                    ForEach(week.bars) { bar in
                        DayColumn(bar: bar, maxHours: maxHours, barAreaHeight: Self.barAreaHeight)
                    }
                }

                if !week.holidays.isEmpty {
                    holidayList(week.holidays)
                }
            }
        }
        .onAppear {
            HolidayStore.shared.refreshIfNeeded()
            loadWeek()
        }
        .onChange(of: manager.logRevision) { _, _ in loadWeek() }
        .onChange(of: offset) { _, _ in loadWeek() }
        .onChange(of: HolidayStore.shared.calendar.years) { _, _ in loadWeek() }
    }

    private func loadWeek() {
        week = currentWeek()
    }

    private func currentWeek() -> WorkWeek {
        WorkWeek.week(
            offset: offset,
            today: WorkdayDetector(newDayStartHour: manager.newDayStartHour).effectiveDateString(for: manager.clock.now),
            scale: manager.heatScale, holidays: HolidayStore.shared.calendar
        ) { date in
            manager.store.load(for: date).map { entry in
                WeekBar.Log(
                    netWorkTime: manager.workday(for: entry).netWorkTime,
                    startTime: entry.startTime,
                    endTime: entry.endTime)
            }
        }
    }

    // MARK: - Header

    private func header(_ week: WorkWeek) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            pageButton("chevron.left", help: "week.previous") { offset -= 1 }

            Button {
                offset = 0
            } label: {
                Text(title(week))
                    .font(DesignTokens.Typography.labelSmall)
                    .foregroundStyle(DesignTokens.Colors.onSurface)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .help(offset == 0 ? Text(verbatim: "") : Text("week.backToThisWeek"))

            pageButton("chevron.right", help: "week.next") { offset += 1 }
                .disabled(offset >= 0)

            Spacer(minLength: DesignTokens.Spacing.sm)

            Text(
                String(
                    format: String(localized: "week.workedOfExpected"),
                    week.worked.hoursMinutesFormatted, week.expected.hoursMinutesFormatted)
            )
            .font(DesignTokens.Typography.labelSmall)
            .foregroundStyle(DesignTokens.Colors.onSurfaceVariant)
            .monospacedDigit()
            .lineLimit(1)
            .help(
                String(
                    format: String(localized: "week.expected.help"),
                    week.workingDays, WorkHeatmapView.hours(manager.heatScale.goalHours)))
        }
    }

    private func pageButton(_ icon: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 16, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(DesignTokens.Colors.onSurfaceVariant)
        .help(Text(help))
        .accessibilityLabel(Text(help))
    }

    /// "本週 10/5–10/11", "上週 9/28–10/4", or just the range further back.
    private func title(_ week: WorkWeek) -> String {
        let range = [week.firstDate, week.lastDate]
            .compactMap(DayString.date)
            .map(Self.dateFormatter.string(from:))
            .joined(separator: "–")
        switch week.offset {
        case 0: return String(localized: "week.thisWeek") + " " + range
        case -1: return String(localized: "week.lastWeek") + " " + range
        default: return range
        }
    }

    // MARK: - Progress

    private func progress(_ week: WorkWeek) -> some View {
        let fraction = week.expected > 0 ? min(1, week.worked / week.expected) : (week.worked > 0 ? 1 : 0)
        let isOver = week.balance >= 60 && week.worked > 0
        return HStack(spacing: DesignTokens.Spacing.sm) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(DesignTokens.Colors.surfaceContainerHighest)
                    Capsule()
                        .fill(isOver ? DesignTokens.Colors.accentOrange : DesignTokens.Colors.accentGreen)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 4)

            Text(balanceText(week, isOver: isOver))
                .font(DesignTokens.Typography.labelMicro)
                .foregroundStyle(isOver ? DesignTokens.Colors.accentOrange : DesignTokens.Colors.onSurfaceVariant)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }

    /// This week counts down what is left; past weeks report how they ended.
    private func balanceText(_ week: WorkWeek, isOver: Bool) -> String {
        let amount = abs(week.balance).hoursMinutesFormatted
        if week.expected == 0 && week.worked == 0 { return String(localized: "week.dayOff") }
        if isOver { return String(format: String(localized: "week.over"), amount) }
        if abs(week.balance) < 60 { return String(localized: "week.onTarget") }
        return String(format: String(localized: week.offset == 0 ? "week.remaining" : "week.short"), amount)
    }

    // MARK: - Holidays

    private func holidayList(_ holidays: [Holiday]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "beach.umbrella")
                .font(.system(size: 10))
                .accessibilityHidden(true)
            Text(holidays.map(Self.holidayLabel).joined(separator: " · "))
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(DesignTokens.Typography.labelMicro)
        .foregroundStyle(DesignTokens.Colors.accentBlue)
    }

    /// "10/9（週五）國慶日補假"
    static func holidayLabel(_ holiday: Holiday) -> String {
        guard let day = DayString.date(holiday.date) else { return holidayName(holiday) }
        return String(
            format: String(localized: "week.holiday"),
            dateFormatter.string(from: day), weekdayFormatter.string(from: day), holidayName(holiday))
    }

    static func holidayName(_ holiday: Holiday) -> String {
        holiday.name.isEmpty ? String(localized: "week.dayOff") : holiday.name
    }

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter
    }()

    static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()
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
                Text(topLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(topLabelColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                RoundedRectangle(cornerRadius: 3)
                    .fill(barColor)
                    .frame(height: barHeight)
                    .overlay {
                        if bar.isToday {
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(DesignTokens.Colors.onSurface.opacity(0.55), lineWidth: 1.5)
                        }
                    }
            }
            .frame(height: barAreaHeight + 16)

            Text(WeekHistoryView.weekdayFormatter.string(from: day))
                .font(DesignTokens.Typography.labelMicro)
                .fontWeight(bar.isToday ? .bold : .medium)
                .foregroundStyle(weekdayColor)
                .lineLimit(1)
        }
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity)
        .background {
            if bar.holiday != nil {
                RoundedRectangle(cornerRadius: 4)
                    .fill(DesignTokens.Colors.accentBlue.opacity(0.1))
            }
        }
        .contentShape(Rectangle())
        .help(tooltip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(tooltip))
    }

    /// Hours worked, 放假 on an unworked day off, a dash on an unworked
    /// past day, nothing yet on a future one.
    private var topLabel: String {
        if bar.hasLog { return bar.netWorkTime.hoursMinutesFormatted }
        if bar.holiday != nil { return String(localized: "week.dayOff") }
        return bar.isFuture ? " " : "—"
    }

    private var topLabelColor: Color {
        if bar.hasLog {
            return bar.level >= .overtime ? bar.level.color : DesignTokens.Colors.onSurface
        }
        if bar.holiday != nil { return DesignTokens.Colors.accentBlue }
        return DesignTokens.Colors.onSurfaceVariant.opacity(0.6)
    }

    private var barColor: Color {
        if bar.hasLog { return bar.level.color }
        if bar.holiday != nil { return DesignTokens.Colors.accentBlue.opacity(0.35) }
        return DesignTokens.Colors.onSurfaceVariant.opacity(0.18)
    }

    private var weekdayColor: Color {
        if bar.holiday != nil { return DesignTokens.Colors.accentBlue }
        return bar.isToday ? DesignTokens.Colors.onSurface : DesignTokens.Colors.onSurfaceVariant
    }

    private var barHeight: CGFloat {
        guard bar.hasLog, bar.netHours > 0, maxHours > 0 else { return 3 }
        return max(3, barAreaHeight * CGFloat(min(1, bar.netHours / maxHours)))
    }

    private var day: Date {
        DayString.date(bar.date) ?? Date()
    }

    private var tooltip: String {
        let summary: String
        if let log = bar.log {
            summary = WorkHeatmapView.tooltip(
                date: day, startTime: log.startTime, endTime: log.endTime, netHours: bar.netHours)
        } else {
            summary = String(
                format: String(localized: "heatmap.tooltip.empty"), WorkHeatmapView.tooltipDate(day))
        }
        var lines = [summary]
        if let overtime = bar.overtimeHoursMinutes {
            lines.append(String(format: String(localized: "history.tooltip.overtime"), overtime.hours, overtime.minutes))
        }
        if let holiday = bar.holiday {
            lines.append(WeekHistoryView.holidayName(holiday))
        }
        return lines.joined(separator: "\n")
    }
}
