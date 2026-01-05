import SwiftUI

struct VoiceRecorderHUD: View {
    @ObservedObject var recorder: VoiceRecorderManager
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(recorder.isRecording ? Color.red : Color.accentColor)
                .frame(width: 10, height: 10)
                .shadow(color: recorder.isRecording ? Color.red.opacity(0.5) : .clear, radius: 4)

            Text(recorder.isRecording ? "Recording…" : "Voice Recorder")
                .font(.footnote.weight(.semibold))

            Button(action: recorder.toggleRecording) {
                Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                    .font(.footnote.weight(.bold))
                    .padding(6)
                    .background(recorder.isRecording ? Color.red : Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(Circle())
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
        .shadow(color: Color.black.opacity(0.15), radius: 6, y: 4)
    }
}
