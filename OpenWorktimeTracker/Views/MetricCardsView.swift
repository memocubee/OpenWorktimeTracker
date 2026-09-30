import SwiftUI

struct MetricCardsView: View {
    @Environment(WorkdayManager.self) private var manager
    @State private var isEditingStart = false
    @State private var isEditingEnd = false
    @State private var editedStartTime = Date()
    @State private var editedEndTime = Date()

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            // Row 1: Start, Gross
            HStack(spacing: DesignTokens.Spacing.sm) {
                // Start time (tappable to edit)
                Button {
                    editedStartTime = manager.currentEntry?.startTime ?? Date()
                    isEditingStart.toggle()
                } label: {
                    MetricCard(
                        icon: "arrow.right.circle",
                        label: String(localized: "metric.start"),
                        value: manager.currentEntry?.startTime.hoursMinutesString ?? "--:--",
                        isEditable: true
                    )
                }
                .buttonStyle(.plain)
                .disabled(manager.currentEntry == nil)
                .help(Text("metric.editStartTime"))

                MetricCard(
                    icon: "clock",
                    label: String(localized: "metric.gross"),
                    value: manager.grossTime.hoursMinutesFormatted
                )
            }

            // Row 2: Pauses, End/ETA
            HStack(spacing: DesignTokens.Spacing.sm) {
                MetricCard(
                    icon: "pause.circle",
                    label: String(localized: "metric.pause"),
                    value: manager.pauseTime.hoursMinutesFormatted,
                    accent: manager.pauseTime > 0 ? DesignTokens.Colors.accentOrange : nil
                )

                if manager.state == .ended {
                    // End time (tappable to edit)
                    Button {
                        editedEndTime = manager.currentEntry?.endTime ?? Date()
                        isEditingEnd.toggle()
                    } label: {
                        MetricCard(
                            icon: "stop.circle",
                            label: String(localized: "metric.end"),
                            value: manager.currentEntry?.endTime?.hoursMinutesString ?? "--:--",
                            isEditable: true
                        )
                    }
                    .buttonStyle(.plain)
                    .help(Text("metric.editEndTime"))
                } else if manager.state == .notStarted {
                    MetricCard(
                        icon: "target",
                        label: String(localized: "metric.target"),
                        value: "--:--"
                    )
                } else if let eta = manager.estimatedEndTime {
                    MetricCard(
                        icon: "target",
                        label: String(localized: "metric.eta"),
                        value: eta.hoursMinutesString,
                        accent: DesignTokens.Colors.accentBlue
                    )
                } else {
                    MetricCard(
                        icon: "checkmark.circle",
                        label: String(localized: "metric.target"),
                        value: String(localized: "metric.reached")
                    )
                }
            }

            if manager.autoBreak > 0 {
                LabeledContent {
                    Text(manager.autoBreak.hoursMinutesFormatted)
                        .monospacedDigit()
                } label: {
                    Label("metric.autoBreak", systemImage: "cup.and.saucer")
                }
                .font(DesignTokens.Typography.bodySmall)
                .foregroundStyle(DesignTokens.Colors.onSurfaceVariant)
                .help(Text("metric.autoBreak.help"))
            }
        }
        .popover(isPresented: $isEditingStart, arrowEdge: .bottom) {
            timeEditor(
                title: String(localized: "metric.editStartTime"),
                date: $editedStartTime,
                range: Date.distantPast...(manager.currentEntry?.endTime ?? Date())
            ) {
                manager.updateStartTime(editedStartTime)
                isEditingStart = false
            }
        }
        .popover(isPresented: $isEditingEnd, arrowEdge: .bottom) {
            timeEditor(
                title: String(localized: "metric.editEndTime"),
                date: $editedEndTime,
                range: (manager.currentEntry?.startTime ?? Date())...Date.distantFuture
            ) {
                manager.updateEndTime(editedEndTime)
                isEditingEnd = false
            }
        }
    }

    private func timeEditor(
        title: String, date: Binding<Date>, range: ClosedRange<Date>, onSave: @escaping () -> Void
    )
        -> some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Text(title)
                .font(DesignTokens.Typography.labelLarge)
                .foregroundStyle(DesignTokens.Colors.onSurface)

            DatePicker(title, selection: date, in: range, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.field)

            HStack {
                Button(String(localized: "metric.cancel")) {
                    isEditingStart = false
                    isEditingEnd = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(String(localized: "metric.save")) {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(width: 240)
    }
}

// MARK: - Metric Card

private struct MetricCard: View {
    let icon: String
    let label: String
    let value: String
    var accent: Color?
    var isEditable: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(DesignTokens.Typography.labelMicro)
                if isEditable {
                    Spacer()
                    Image(systemName: "pencil")
                        .font(.system(size: 8))
                        .opacity(0.5)
                }
            }
            .foregroundStyle(DesignTokens.Colors.onSurfaceVariant)

            Text(value)
                .font(DesignTokens.Typography.titleMedium)
                .foregroundStyle(accent ?? DesignTokens.Colors.onSurface)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.surfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(value))
    }
}
