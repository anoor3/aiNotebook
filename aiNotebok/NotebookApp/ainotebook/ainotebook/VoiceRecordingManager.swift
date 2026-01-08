import Foundation
import AVFoundation

final class VoiceRecorderManager: NSObject, ObservableObject {
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var recordings: [VoiceRecording] = []

    private let notebookID: UUID
    private var audioRecorder: AVAudioRecorder?
    private var audioSessionActive = false
    private var currentFileURL: URL?

    init(notebookID: UUID) {
        self.notebookID = notebookID
        super.init()
        recordings = loadRecordings()
    }

    deinit {
        stopRecordingIfNeeded()
        deactivateAudioSession()
    }

    func requestPermission(completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    func stopRecordingIfNeeded() {
        if isRecording {
            stopRecording()
        }
    }

    private func startRecording() {
        guard audioRecorder == nil else { return }
        requestPermission { [weak self] granted in
            guard let self else { return }
            guard granted else { return }
            self.beginRecording()
        }
    }

    private func beginRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            audioSessionActive = true

            let directory = recordingsDirectory()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let fileName = "\(UUID().uuidString).m4a"
            let url = directory.appendingPathComponent(fileName)
            currentFileURL = url

            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()
            isRecording = true
        } catch {
            print("VoiceRecorderManager start error: \(error)")
            audioRecorder = nil
            currentFileURL = nil
            deactivateAudioSession()
        }
    }

    private func stopRecording() {
        guard let recorder = audioRecorder else { return }
        let duration = recorder.currentTime
        recorder.stop()
        audioRecorder = nil
        isRecording = false

        if let url = currentFileURL {
            if duration < 0.25 {
                try? FileManager.default.removeItem(at: url)
            } else {
                persistRecording(fileURL: url, duration: duration)
            }
        }

        currentFileURL = nil
        deactivateAudioSession()
    }

    private func persistRecording(fileURL: URL, duration: TimeInterval) {
        let record = VoiceRecording(id: UUID(),
                                    fileName: fileURL.lastPathComponent,
                                    createdAt: Date(),
                                    duration: duration)
        recordings.insert(record, at: 0)
        saveRecordings()
    }

    private func recordingsDirectory() -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("VoiceNotes", isDirectory: true)
            .appendingPathComponent(notebookID.uuidString, isDirectory: true)
    }

    private func recordingsMetadataURL() -> URL {
        recordingsDirectory().appendingPathComponent("recordings.json")
    }

    func recordingURL(for recording: VoiceRecording) -> URL {
        recordingsDirectory().appendingPathComponent(recording.fileName)
    }

    private func loadRecordings() -> [VoiceRecording] {
        let url = recordingsMetadataURL()
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([VoiceRecording].self, from: data)) ?? []
    }

    private func saveRecordings() {
        let url = recordingsMetadataURL()
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(recordings)
            try data.write(to: url, options: .atomic)
        } catch {
            print("VoiceRecorderManager save error: \(error)")
        }
    }

    private func deactivateAudioSession() {
        guard audioSessionActive else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            print("VoiceRecorderManager session deactivate error: \(error)")
        }
        audioSessionActive = false
    }
}
