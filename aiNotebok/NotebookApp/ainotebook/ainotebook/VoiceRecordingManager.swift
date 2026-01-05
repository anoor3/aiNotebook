import Foundation
import AVFoundation
import Speech

final class VoiceRecorderManager: NSObject, ObservableObject {
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var recordings: [VoiceRecording] = []
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published private(set) var recordingPageID: UUID?
    @Published private(set) var playingRecordingID: UUID?
    @Published private(set) var transcribingRecordingID: UUID?
    @Published private(set) var transcriptionErrorMessage: String?

    private let notebookID: UUID
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var audioSessionActive = false
    private var currentFileURL: URL?
    private var currentRecordingPageID: UUID?
    private var durationTimer: Timer?
    private var currentRecordingTitle: String?
    private var recognitionTask: SFSpeechRecognitionTask?

    init(notebookID: UUID) {
        self.notebookID = notebookID
        super.init()
        recordings = loadRecordings()
    }

    deinit {
        stopRecordingIfNeeded()
        stopPlayback()
        cancelTranscription()
        deactivateAudioSession()
        stopDurationUpdates()
    }

    func requestPermission(completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    func toggleRecording(for pageID: UUID?, pageLabel: String?) {
        if isRecording {
            stopRecording()
        } else if let pageID {
            startRecording(for: pageID, pageLabel: pageLabel)
        }
    }

    func stopRecordingIfNeeded() {
        if isRecording {
            stopRecording()
        }
    }

    private func startRecording(for pageID: UUID, pageLabel: String?) {
        guard audioRecorder == nil else { return }
        requestPermission { [weak self] granted in
            guard let self else { return }
            guard granted else { return }
            self.beginRecording(for: pageID, pageLabel: pageLabel)
        }
    }

    private func beginRecording(for pageID: UUID, pageLabel: String?) {
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
            currentRecordingPageID = pageID
            currentRecordingTitle = defaultTitle(for: pageLabel)

            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()
            isRecording = true
            recordingDuration = 0
            recordingPageID = pageID
            beginDurationUpdates()
        } catch {
            print("VoiceRecorderManager start error: \(error)")
            audioRecorder = nil
            currentFileURL = nil
            currentRecordingPageID = nil
            deactivateAudioSession()
        }
    }

    func stopRecording() {
        guard let recorder = audioRecorder else { return }
        let duration = recorder.currentTime
        recorder.stop()
        audioRecorder = nil
        isRecording = false
        recordingDuration = 0
        recordingPageID = nil
        stopDurationUpdates()

        if let url = currentFileURL {
            if duration < 0.25 {
                try? FileManager.default.removeItem(at: url)
            } else {
                persistRecording(fileURL: url, duration: duration)
            }
        }

        currentFileURL = nil
        currentRecordingPageID = nil
        currentRecordingTitle = nil
        deactivateAudioSession()
    }

    private func beginDurationUpdates() {
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.recordingDuration = self.audioRecorder?.currentTime ?? self.recordingDuration
            }
        }
        if let durationTimer {
            RunLoop.main.add(durationTimer, forMode: .common)
        }
    }

    private func stopDurationUpdates() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func persistRecording(fileURL: URL, duration: TimeInterval) {
        let record = VoiceRecording(fileName: fileURL.lastPathComponent,
                                    createdAt: Date(),
                                    duration: duration,
                                    pageID: currentRecordingPageID,
                                    title: currentRecordingTitle ?? defaultTitle(for: nil))
        recordings.insert(record, at: 0)
        saveRecordings()
    }

    func recordings(for pageID: UUID) -> [VoiceRecording] {
        recordings.filter { $0.pageID == pageID }
    }

    func latestRecording(for pageID: UUID) -> VoiceRecording? {
        recordings.first(where: { $0.pageID == pageID })
    }

    func renameRecording(_ recordingID: UUID, title: String) {
        guard let index = recordings.firstIndex(where: { $0.id == recordingID }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = trimmed.isEmpty ? defaultTitle(for: nil) : trimmed
        recordings[index].title = sanitized
        saveRecordings()
    }

    func deleteRecording(_ recordingID: UUID) {
        guard let index = recordings.firstIndex(where: { $0.id == recordingID }) else { return }
        let recording = recordings.remove(at: index)
        if playingRecordingID == recordingID {
            stopPlayback()
        }
        let fileURL = recordingsDirectory().appendingPathComponent(recording.fileName)
        try? FileManager.default.removeItem(at: fileURL)
        saveRecordings()
    }

    func updateSummary(for recordingID: UUID, summary: String?) {
        guard let index = recordings.firstIndex(where: { $0.id == recordingID }) else { return }
        recordings[index].notesSummary = summary
        saveRecordings()
    }

    func transcribeRecording(_ recording: VoiceRecording) {
        guard transcribingRecordingID == nil else { return }
        guard let url = recordingURL(for: recording) else { return }
        requestSpeechAuthorization { [weak self] granted in
            guard let self else { return }
            guard granted else {
                DispatchQueue.main.async {
                    self.transcriptionErrorMessage = "Speech recognition permission denied."
                }
                return
            }
            self.beginTranscription(for: recording, audioURL: url)
        }
    }

    func playRecording(_ recording: VoiceRecording) {
        if playingRecordingID == recording.id {
            stopPlayback()
            return
        }

        guard let url = recordingURL(for: recording) else { return }
        stopPlayback()

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            audioPlayer?.play()
            playingRecordingID = recording.id
        } catch {
            print("VoiceRecorderManager playback error: \(error)")
            audioPlayer = nil
            playingRecordingID = nil
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        playingRecordingID = nil
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            print("VoiceRecorderManager playback deactivate error: \(error)")
        }
    }

    private func requestSpeechAuthorization(completion: @escaping (Bool) -> Void) {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            completion(true)
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { newStatus in
                DispatchQueue.main.async {
                    completion(newStatus == .authorized)
                }
            }
        default:
            completion(false)
        }
    }

    private func beginTranscription(for recording: VoiceRecording, audioURL: URL) {
        transcribingRecordingID = recording.id
        transcriptionErrorMessage = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        guard let recognizer = SFSpeechRecognizer(locale: Locale.current), recognizer.isAvailable else {
            transcriptionErrorMessage = "Speech recognizer unavailable."
            transcribingRecordingID = nil
            return
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = false

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async {
                    self.transcriptionErrorMessage = error.localizedDescription
                }
                self.finishTranscriptionFor(recording.id, text: nil)
                return
            }

            if let result, result.isFinal {
                let text = result.bestTranscription.formattedString
                self.finishTranscriptionFor(recording.id, text: text)
            }
        }
    }

    private func finishTranscriptionFor(_ recordingID: UUID, text: String?) {
        DispatchQueue.main.async {
            if let index = self.recordings.firstIndex(where: { $0.id == recordingID }) {
                self.recordings[index].transcript = text
                self.saveRecordings()
            }
            self.recognitionTask = nil
            self.transcribingRecordingID = nil
        }
    }

    private func cancelTranscription() {
        recognitionTask?.cancel()
        recognitionTask = nil
        transcribingRecordingID = nil
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

    private func recordingURL(for recording: VoiceRecording) -> URL? {
        let url = recordingsDirectory().appendingPathComponent(recording.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
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

    private func defaultTitle(for pageLabel: String?) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let timestamp = formatter.string(from: Date())
        if let pageLabel {
            return "\(pageLabel) • \(timestamp)"
        }
        return "Recording • \(timestamp)"
    }
}

extension VoiceRecorderManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stopPlayback()
    }
}
