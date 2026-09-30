import SwiftUI

/// Popover for setting today's Pause total directly, in hours and minutes.
/// There are no Pause intervals to pick from: the user only states how long
/// the breaks were in total.
struct PauseTotalEditor: View {
    @Environment(WorkdayManager.self) private var manager
    let onClose: () -> Void

    @State private var hours: Int
    @State private var minutes: Int
    @State private var saveError: TotalPauseEditError?
    private let initialMinutes: Int

    init(initialTotal: TimeInterval, onClose: @escaping () -> Void) {
        let totalMinutes = max(0, Int(initialTotal) / 60)
        self.initialMinutes = totalMinutes
        self._hours = State(initialValue: totalMinutes / 60)
        self._minutes = State(initialValue: totalMinutes % 60)
        self.onClose = onClose
    }

    private var enteredMinutes: Int { max(0, hours) * 60 + max(0, minutes) }
    private var enteredTotal: TimeInterval { TimeInterval(enteredMinutes * 60) }
    private var validationError: TotalPauseEditError? { manager.totalPauseError(for: enteredTotal) }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("metric.editPause")
                .font(DesignTokens.Typography.labelLarge)
                .foregroundStyle(DesignTokens.Colors.onSurface)

            if manager.state == .paused {
                pausedContent
            } else {
                editorContent
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(width: 260)
    }

    private var pausedContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("pauseTotal.pausedHint")
                .font(DesignTokens.Typography.bodySmall)
                .foregroundStyle(DesignTokens.Colors.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(String(localized: "pauseTotal.ok")) { onClose() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("pauseTotal.label")
                .font(DesignTokens.Typography.labelMicro)
                .foregroundStyle(DesignTokens.Colors.onSurfaceVariant)

            HStack(spacing: DesignTokens.Spacing.md) {
                field(value: $hours, range: 0...23, unit: "pauseTotal.hours")
                field(value: $minutes, range: 0...59, unit: "pauseTotal.minutes")
            }

            if manager.idlePauseTime >= 60 {
                Text(String(format: String(localized: "pauseTotal.idleNote"),
                            manager.idlePauseTime.hoursMinutesFormatted))
                    .font(DesignTokens.Typography.bodySmall)
                    .foregroundStyle(DesignTokens.Colors.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = saveError ?? validationError {
                Text(error.errorDescription ?? "")
                    .font(DesignTokens.Typography.bodySmall)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(String(localized: "metric.cancel")) { onClose() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "metric.save")) { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(validationError != nil)
            }
        }
        .onChange(of: hours) { saveError = nil }
        .onChange(of: minutes) { saveError = nil }
    }

    private func field(value: Binding<Int>, range: ClosedRange<Int>, unit: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 40)
                .accessibilityLabel(Text(unit))
            Stepper("", value: value, in: range)
                .labelsHidden()
            Text(unit)
                .font(DesignTokens.Typography.bodySmall)
                .foregroundStyle(DesignTokens.Colors.onSurfaceVariant)
        }
    }

    private func save() {
        // Unchanged: keep the stored seconds rather than rounding them away.
        guard enteredMinutes != initialMinutes else {
            onClose()
            return
        }
        if let error = manager.setTotalPause(enteredTotal) {
            saveError = error
        } else {
            onClose()
        }
    }
}
