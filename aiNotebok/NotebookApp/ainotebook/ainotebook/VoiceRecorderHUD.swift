import SwiftUI

struct VoiceRecorderHUD: View {
    @ObservedObject var recorder: VoiceRecorderManager
    var currentPageID: UUID?
    var pageLabel: String?
    var onShowHistory: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Voice Recorder")
                    .font(.caption.weight(.semibold))
                if let pageLabel {
                    Text(pageLabel)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 8) {
                circleButton(systemName: "mic.fill",
                             tint: .accentColor,
                             action: startRecording)
                    .disabled(currentPageID == nil)
                    .opacity(currentPageID == nil ? 0.4 : 1)

                circleButton(systemName: "clock.arrow.circlepath",
                             tint: Color(.secondarySystemBackground),
                             foreground: .primary,
                             action: onShowHistory)

                circleButton(systemName: "xmark",
                             tint: Color(.secondarySystemBackground),
                             foreground: .secondary,
                             action: onClose)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: Color.black.opacity(0.12), radius: 6, y: 4)
        .fixedSize()
    }

    private func startRecording() {
        recorder.toggleRecording(for: currentPageID, pageLabel: pageLabel)
    }

    private func circleButton(systemName: String,
                              tint: Color,
                              foreground: Color = .white,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(foreground)
                .frame(width: 28, height: 28)
                .background(Circle().fill(tint))
        }
        .buttonStyle(.plain)
    }
}

struct VoiceRecordingIndicator: View {
    let duration: TimeInterval
    var onStop: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .shadow(color: Color.red.opacity(0.5), radius: 4)

            Text(formattedDuration(duration))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundColor(.primary)

            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(Color.red.opacity(0.9))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: Color.black.opacity(0.18), radius: 6, y: 3)
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let clamped = max(0, Int(duration.rounded()))
        let minutes = clamped / 60
        let seconds = clamped % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
