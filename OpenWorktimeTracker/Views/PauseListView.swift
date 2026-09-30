import SwiftUI

/// Today's breaks under the metric cards, each one editable after the fact.
struct PauseListView: View {
    @Environment(WorkdayManager.self) private var manager

    var body: some View {
        if let entry = manager.currentEntry, !entry.pauses.isEmpty || entry.manualPauseSeconds > 0 {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("pauses.title")
                    .font(DesignTokens.Typography.labelSmall)
                    .foregroundStyle(DesignTokens.Colors.onSurfaceVariant)

                ForEach(entry.pauses) { pause in
                    PauseRowView(pause: pause)
                }

                if entry.manualPauseSeconds > 0 {
                    LegacyPauseRowView(seconds: entry.manualPauseSeconds)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Text

enum PauseText {
    /// "休息 12:10–13:20（1 小時 10 分）", or for the open break "休息 14:00–進行中（20 分鐘）".
    static func row(_ pause: PauseInterval, now: Date) -> String {
        let duration = pause.duration(endingAt: now).breakDurationText
        if let end = pause.end {
            return String(
                format: String(localized: "pauses.row"),
                pause.start.hoursMinutesString, end.hoursMinutesString, duration)
        }
        return String(format: String(localized: "pauses.row.open"), pause.start.hoursMinutesString, duration)
    }

    static func legacy(_ seconds: TimeInterval) -> String {
        String(format: String(localized: "pauses.legacy"), seconds.breakDurationText)
    }
}

extension TimeInterval {
    /// "1 小時 10 分" or "25 分鐘".
    var breakDurationText: String {
        let totalMinutes = Int(max(0, self)) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return String(format: String(localized: "pauses.duration.hoursMinutes"), hours, minutes)
        }
        return String(format: String(localized: "pauses.duration.minutes"), minutes)
    }
}

// MARK: - Row chrome

private struct PauseRowLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "cup.and.saucer")
                .font(.system(size: 10))
                .accessibilityHidden(true)
            Text(text)
                .monospacedDigit()
            Spacer()
            Image(systemName: "pencil")
                .font(.system(size: 9))
                .opacity(0.5)
                .accessibilityHidden(true)
        }
        .font(DesignTokens.Typography.bodySmall)
        .foregroundStyle(DesignTokens.Colors.onSurfaceVariant)
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs + 2)
        .background(DesignTokens.Colors.surfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .contentShape(Rectangle())
    }
}

private struct PauseEditorChrome<Fields: View>: View {
    let title: LocalizedStringKey
    let error: PauseEditError?
    let onDelete: () -> Void
    let onCancel: () -> Void
    let onSave: () -> Void
    @ViewBuilder let fields: Fields

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text(title)
                .font(DesignTokens.Typography.labelLarge)
                .foregroundStyle(DesignTokens.Colors.onSurface)

            fields

            if let error {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                    .font(DesignTokens.Typography.bodySmall)
                    .foregroundStyle(DesignTokens.Colors.accentRed)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("pauses.edit.delete", role: .destructive, action: onDelete)
                Spacer()
                Button("metric.cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("metric.save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(width: 300)
    }
}

// MARK: - A recorded break

private struct PauseRowView: View {
    @Environment(WorkdayManager.self) private var manager
    let pause: PauseInterval

    @State private var isEditing = false
    @State private var editedStart = Date()
    @State private var editedEnd = Date()
    @State private var error: PauseEditError?

    var body: some View {
        Button {
            editedStart = pause.start
            editedEnd = pause.end ?? Date()
            error = nil
            isEditing = true
        } label: {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                PauseRowLabel(text: PauseText.row(pause, now: context.date))
            }
        }
        .buttonStyle(.plain)
        .help(Text("pauses.edit.help"))
        .popover(isPresented: $isEditing, arrowEdge: .bottom) {
            PauseEditorChrome(
                title: "pauses.edit.title",
                error: error,
                onDelete: { finish(manager.deletePause(id: pause.id)) },
                onCancel: { isEditing = false },
                onSave: save,
                fields: { editorFields }
            )
        }
    }

    @ViewBuilder private var editorFields: some View {
        LabeledContent("pauses.edit.start") {
            DatePicker("pauses.edit.start", selection: $editedStart, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.field)
        }
        LabeledContent("pauses.edit.end") {
            if pause.end != nil {
                DatePicker("pauses.edit.end", selection: $editedEnd, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.field)
            } else {
                Text("pauses.edit.stillOpen")
                    .foregroundStyle(DesignTokens.Colors.onSurfaceVariant)
            }
        }
    }

    private func save() {
        var updated = pause
        updated.start = editedStart
        if pause.end != nil {
            updated.end = editedEnd
        }
        finish(manager.updatePause(updated))
    }

    private func finish(_ result: PauseEditError?) {
        error = result
        if result == nil {
            isEditing = false
        }
    }
}

// MARK: - An aggregate-only break from an older Daily Log

private struct LegacyPauseRowView: View {
    @Environment(WorkdayManager.self) private var manager
    let seconds: TimeInterval

    @State private var isEditing = false
    @State private var hours = 0
    @State private var minutes = 0
    @State private var error: PauseEditError?

    var body: some View {
        Button {
            hours = seconds.hoursComponent
            minutes = seconds.minutesComponent
            error = nil
            isEditing = true
        } label: {
            PauseRowLabel(text: PauseText.legacy(seconds))
        }
        .buttonStyle(.plain)
        .help(Text("pauses.edit.help"))
        .popover(isPresented: $isEditing, arrowEdge: .bottom) {
            PauseEditorChrome(
                title: "pauses.legacy.title",
                error: error,
                onDelete: { finish(manager.updateLegacyPauseSeconds(0)) },
                onCancel: { isEditing = false },
                onSave: { finish(manager.updateLegacyPauseSeconds(TimeInterval(hours * 3600 + minutes * 60))) },
                fields: { durationSteppers }
            )
        }
    }

    private var durationSteppers: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            Stepper(value: $hours, in: 0...8) {
                Text(verbatim: "\(hours)h").monospacedDigit()
            }
            .accessibilityLabel(Text("logEditor.pauseHours"))
            Stepper(value: $minutes, in: 0...59) {
                Text(verbatim: "\(minutes)m").monospacedDigit()
            }
            .accessibilityLabel(Text("logEditor.pauseMinutes"))
        }
    }

    private func finish(_ result: PauseEditError?) {
        error = result
        if result == nil {
            isEditing = false
        }
    }
}
