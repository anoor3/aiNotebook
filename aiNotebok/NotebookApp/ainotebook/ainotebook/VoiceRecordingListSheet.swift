import AVFoundation
import SwiftUI

struct VoiceRecordingListSheet: View {
    @ObservedObject var recorder: VoiceRecorderManager
    var onClose: () -> Void
    @State private var currentlyPlayingID: UUID?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var playbackDelegate: PlaybackDelegate?
    @State private var playbackErrorMessage: String?

    var body: some View {
        NavigationView {
            Group {
                if recorder.recordings.isEmpty {
                    ContentUnavailableView("No Recordings", systemImage: "waveform", description: Text("Record a voice note to see it here."))
                } else {
                    List {
                        ForEach(recorder.recordings) { recording in
                            recordingRow(recording)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Voice Recordings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        stopPlayback()
                        onClose()
                    }
                }
            }
            .alert("Playback Error", isPresented: Binding(get: {
                playbackErrorMessage != nil
            }, set: { _ in
                playbackErrorMessage = nil
            })) {
                Button("OK", role: .cancel) {
                    playbackErrorMessage = nil
                }
            } message: {
                Text(playbackErrorMessage ?? "Unknown error")
            }
        }
    }

    private func recordingRow(_ recording: VoiceRecording) -> some View {
        HStack(spacing: 12) {
            Button(action: {
                togglePlayback(for: recording)
            }) {
                Image(systemName: currentlyPlayingID == recording.id ? "stop.fill" : "play.fill")
                    .font(.headline)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(recording.createdAt, style: .date)
                    .font(.headline)
                Text("Duration: \(formattedDuration(recording.duration))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }

    private func togglePlayback(for recording: VoiceRecording) {
        if currentlyPlayingID == recording.id {
            stopPlayback()
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            let url = recorder.recordingURL(for: recording)
            let player = try AVAudioPlayer(contentsOf: url)
            let delegate = PlaybackDelegate(onFinish: {
                stopPlayback()
            })
            player.delegate = delegate
            playbackDelegate = delegate
            audioPlayer = player
            currentlyPlayingID = recording.id
            player.play()
        } catch {
            playbackErrorMessage = error.localizedDescription
            stopPlayback()
        }
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        playbackDelegate = nil
        currentlyPlayingID = nil
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private final class PlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        super.init()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}
