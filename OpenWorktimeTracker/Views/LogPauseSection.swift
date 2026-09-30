import SwiftUI

/// The Log Editor's breaks: every Pause Interval of the selected day with its
/// start and end, plus the aggregate Pause of a Daily Log from before Pause
/// Intervals existed.
struct LogPauseSection: View {
    /// The Daily Log as last saved, which decides whether the older aggregate
    /// row is shown at all.
    let entry: TimeEntry
    let dayStart: Date
    let dayEnd: Date?
    let validationError: PauseEditError?
    @Binding var pauses: [PauseInterval]
    @Binding var legacyHours: Int
    @Binding var legacyMinutes: Int

    private static let defaultLength: TimeInterval = 30 * 60

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "pauses.title"))
                .font(.system(size: 12, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            ForEach(pauses) { pause in
                pauseRow(pause)
            }

            if entry.manualPauseSeconds > 0 {
                legacyRow
            }

            Button {
                addPause()
            } label: {
                Label(String(localized: "pauses.add"), systemImage: "plus")
            }

            if let validationError {
                Label(validationError.localizedDescription, systemImage: "exclamationmark.triangle")
                    .font(DesignTokens.Typography.bodySmall)
                    .foregroundStyle(DesignTokens.Colors.accentRed)
            }
        }
    }

    // MARK: - Rows

    private func pauseRow(_ pause: PauseInterval) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            DatePicker(
                "pauses.edit.start", selection: startBinding(for: pause.id),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()

            Text(verbatim: "–")
                .foregroundStyle(.secondary)

            if pause.end != nil {
                DatePicker(
                    "pauses.edit.end", selection: endBinding(for: pause.id),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
            } else {
                Text("pauses.edit.stillOpen")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(pause.duration(endingAt: Date()).breakDurationText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button {
                pauses.removeAll { $0.id == pause.id }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("pauses.edit.delete"))
            .help(Text("pauses.edit.delete"))
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(DesignTokens.Colors.accentOrange.opacity(0.08))
        )
    }

    private var legacyRow: some View {
        HStack(spacing: 16) {
            Text("pauses.legacy.label")
                .font(.system(size: 12))
            Spacer()
            Stepper(value: $legacyHours, in: 0...8) {
                Text(verbatim: "\(legacyHours)h")
                    .monospacedDigit()
                    .frame(width: 30, alignment: .trailing)
            }
            .accessibilityLabel(Text("logEditor.pauseHours"))
            Stepper(value: $legacyMinutes, in: 0...59) {
                Text(verbatim: "\(legacyMinutes)m")
                    .monospacedDigit()
                    .frame(width: 35, alignment: .trailing)
            }
            .accessibilityLabel(Text("logEditor.pauseMinutes"))
            Button {
                legacyHours = 0
                legacyMinutes = 0
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("pauses.edit.delete"))
            .help(Text("pauses.edit.delete"))
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(DesignTokens.Colors.accentOrange.opacity(0.08))
        )
    }

    // MARK: - Editing

    private func startBinding(for id: UUID) -> Binding<Date> {
        Binding(
            get: { pauses.first { $0.id == id }?.start ?? dayStart },
            set: { newValue in
                guard let index = pauses.firstIndex(where: { $0.id == id }) else { return }
                pauses[index].start = newValue
            }
        )
    }

    private func endBinding(for id: UUID) -> Binding<Date> {
        Binding(
            get: { pauses.first { $0.id == id }?.end ?? dayStart },
            set: { newValue in
                guard let index = pauses.firstIndex(where: { $0.id == id }) else { return }
                pauses[index].end = newValue
            }
        )
    }

    /// Starts the new break where the last one ended (or at the start of the
    /// day), 30 minutes long but never past the end of the day or now.
    private func addPause() {
        let upper = dayEnd ?? Date()
        let lastEnd = pauses.map { $0.end ?? upper }.max()
        let start = min(max(dayStart, lastEnd ?? dayStart), upper)
        let end = min(start.addingTimeInterval(Self.defaultLength), upper)
        pauses.append(PauseInterval(start: start, end: end))
        pauses.sort { $0.start < $1.start }
    }
}
