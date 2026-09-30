import SwiftUI

/// Next to Resume while paused: for the user who forgot to press it, resume
/// at the time they actually came back, and optionally move the break's start.
struct ResumeAtButton: View {
    @Environment(WorkdayManager.self) private var manager

    @State private var isPresented = false
    @State private var pauseStart = Date()
    @State private var returnedAt = Date()
    @State private var error: PauseEditError?

    var body: some View {
        Button {
            pauseStart = manager.currentEntry?.currentPauseStart ?? Date()
            returnedAt = Date()
            error = nil
            isPresented = true
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .frame(minHeight: 28)
                .padding(.vertical, DesignTokens.Spacing.xs)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .fixedSize()
        .accessibilityLabel(Text("resumeAt.title"))
        .help(Text("resumeAt.title"))
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            editor
        }
    }

    private var canMovePauseStart: Bool {
        manager.currentEntry?.openPause != nil
    }

    private var editor: some View {
        let now = Date()
        let dayStart = manager.currentEntry?.startTime ?? now
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("resumeAt.title")
                .font(DesignTokens.Typography.labelLarge)
                .foregroundStyle(DesignTokens.Colors.onSurface)

            Text("resumeAt.hint")
                .font(DesignTokens.Typography.bodySmall)
                .foregroundStyle(DesignTokens.Colors.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)

            LabeledContent("resumeAt.pauseStart") {
                if canMovePauseStart {
                    DatePicker(
                        "resumeAt.pauseStart", selection: $pauseStart,
                        in: dayStart...max(dayStart, now), displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .datePickerStyle(.field)
                } else {
                    Text(pauseStart.hoursMinutesString)
                        .monospacedDigit()
                }
            }

            LabeledContent("resumeAt.returnTime") {
                DatePicker(
                    "resumeAt.returnTime", selection: $returnedAt,
                    in: min(pauseStart, now)...now, displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .datePickerStyle(.field)
            }

            if let error {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                    .font(DesignTokens.Typography.bodySmall)
                    .foregroundStyle(DesignTokens.Colors.accentRed)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("metric.cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("resumeAt.confirm") { confirm() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(width: 300)
    }

    private func confirm() {
        if returnedAt < pauseStart {
            error = .endNotAfterStart
            return
        }
        if let open = manager.currentEntry?.openPause, open.start != pauseStart {
            var moved = open
            moved.start = pauseStart
            if let failure = manager.updatePause(moved) {
                error = failure
                return
            }
        }
        manager.resume(at: returnedAt)
        isPresented = false
    }
}
