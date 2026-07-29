import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct VoiceRecordingHistorySheet: View {
    @ObservedObject var recorder: VoiceRecorderManager
    @ObservedObject var pageStore: NotebookPageStore
    var onClose: () -> Void

    @State private var editingID: UUID?
    @State private var draftTitle: String = ""
    @FocusState private var focusedRecordingID: UUID?
    @State private var deleteTarget: VoiceRecording?
    @State private var transcriptSheetItem: RecordingSheetItem?

    var body: some View {
        NavigationStack {
            Group {
                if recorder.recordings.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            if let error = recorder.transcriptionErrorMessage {
                                errorBanner(error)
                            }
                            LazyVStack(spacing: 18) {
                                ForEach(recorder.recordings) { recording in
                                    recordingCard(for: recording)
                                }
                            }
                        }
                        .padding(.vertical, 24)
                        .padding(.horizontal, 20)
                    }
                }
            }
            .navigationTitle("Recording History")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onDisappear { endEditing() }
        .sheet(item: $transcriptSheetItem) { item in
            RecordingTranscriptSheet(recordingID: item.id,
                                     recorder: recorder,
                                     pageStore: pageStore)
        }
        .confirmationDialog("Delete recording?",
                             isPresented: Binding(get: { deleteTarget != nil },
                                                  set: { if !$0 { deleteTarget = nil } }),
                             presenting: deleteTarget) { target in
            Button("Delete", role: .destructive) {
                recorder.deleteRecording(target.id)
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: { _ in
            Text("This voice note will be permanently removed.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 48))
                .foregroundColor(.accentColor.opacity(0.7))
            Text("No recordings yet")
                .font(.title3.weight(.semibold))
            Text("Tap the mic button to capture your first voice note.")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorBanner(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.white)
            Text(error)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(Color.red)
        )
    }

    private func recordingCard(for recording: VoiceRecording) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                if editingID == recording.id {
                    TextField("Recording name", text: $draftTitle)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedRecordingID, equals: recording.id)
                        .onSubmit { commitRename(for: recording) }
                } else {
                    Text(recording.title)
                        .font(.system(.headline, design: .monospaced))
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Button(action: { togglePlayback(recording) }) {
                    Image(systemName: recorder.playingRecordingID == recording.id ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                if let label = labelForPage(recording.pageID) {
                    metaChip(icon: "doc.text", text: label)
                }
                metaChip(icon: "waveform", text: formattedDuration(recording.duration))
                metaChip(icon: "calendar", text: formattedDate(recording.createdAt))
            }

            HStack(spacing: 8) {
                if editingID == recording.id {
                    Button(action: { commitRename(for: recording) }) {
                        Label("Save", systemImage: "checkmark")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Cancel") {
                        endEditing()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(action: { beginEditing(recording) }) {
                        Label("Rename", systemImage: "pencil")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }

                Button(action: { transcriptSheetItem = RecordingSheetItem(id: recording.id) }) {
                    Label("Transcript", systemImage: "text.quote")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    deleteTarget = recording
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }

        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.thinMaterial)
                .shadow(color: Color.black.opacity(0.08), radius: 14, y: 6)
        )
    }

    private func beginEditing(_ recording: VoiceRecording) {
        editingID = recording.id
        draftTitle = recording.title
        focusedRecordingID = recording.id
    }

    private func commitRename(for recording: VoiceRecording) {
        recorder.renameRecording(recording.id, title: draftTitle)
        endEditing()
    }

    private func endEditing() {
        editingID = nil
        draftTitle = ""
        focusedRecordingID = nil
    }

    private func togglePlayback(_ recording: VoiceRecording) {
        recorder.playRecording(recording)
    }

    private func metaChip(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(Color.primary.opacity(0.06))
            )
    }

    private func labelForPage(_ pageID: UUID?) -> String? {
        guard let pageID else { return nil }
        if let model = pageStore.model(for: pageID) {
            let trimmed = model.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        if let index = pageStore.pages.firstIndex(where: { $0.id == pageID }) {
            return "Page \(index + 1)"
        }
        return nil
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

private func formattedDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

private struct RecordingSheetItem: Identifiable {
    let id: UUID
}
}

private struct RecordingTranscriptSheet: View {
    let recordingID: UUID
    @ObservedObject var recorder: VoiceRecorderManager
    @ObservedObject var pageStore: NotebookPageStore

    @Environment(\.dismiss) private var dismiss
    @State private var rewriteError: String?
    @State private var isRewriting = false
    @State private var expandedText: ExpandedTextItem?

    private var recording: VoiceRecording? {
        recorder.recordings.first(where: { $0.id == recordingID })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let recording {
                        header(for: recording)
                        transcriptSection(for: recording)
                        rewriteSection(for: recording)
                        if let summary = recording.notesSummary, !summary.isEmpty {
                            aiNotesSection(summary: summary)
                        }
                        if let rewriteError {
                            Text(rewriteError)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.red)
                        }
                    } else {
                        Text("Recording unavailable.")
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Transcript")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: dismiss.callAsFunction)
                }
            }
            .sheet(item: $expandedText) { item in
                ExpandedTextSheet(item: item)
            }
        }
    }

    private func header(for recording: VoiceRecording) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recording.title)
                .font(.title3.weight(.semibold))
            if let label = labelForPage(recording.pageID) {
                Text(label)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Text("Duration \(formattedDuration(recording.duration)) • \(formattedDate(recording.createdAt))")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    private func transcriptSection(for recording: VoiceRecording) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Transcript")
                    .font(.system(.headline, design: .monospaced))
                Spacer()
                if recorder.transcribingRecordingID == recording.id {
                    ProgressView()
                }
                Button(action: { recorder.transcribeRecording(recording) }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Re-run transcription")
                .disabled(recorder.transcribingRecordingID != nil && recorder.transcribingRecordingID != recording.id)
                if let transcript = recording.transcript, !transcript.isEmpty {
                    Button(action: { expandedText = ExpandedTextItem(title: "Transcript", body: transcript) }) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .help("Open full screen")
                }
            }

            if let transcript = recording.transcript, !transcript.isEmpty {
                ScrollView {
                    Text(transcript)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 260, maxHeight: 420)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.secondary.opacity(0.08))
                )
            } else if recorder.transcribingRecordingID == recording.id {
                Text("Processing audio…")
                    .foregroundColor(.secondary)
            } else {
                Text("No transcript yet.")
                    .foregroundColor(.secondary)
            }
        }
    }

    private func rewriteSection(for recording: VoiceRecording) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI Rewrite")
                    .font(.system(.headline, design: .monospaced))
                Spacer()
                if isRewriting {
                    ProgressView()
                }
            }
            Text("Generate polished notes from this transcript.")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundColor(.secondary)
            Button(action: { rewriteTranscript(recording) }) {
                Label("Rewrite with AI", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRewriting)
        }
    }

    private func aiNotesSection(summary: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("AI Notes")
                    .font(.system(.headline, design: .monospaced))
                Spacer()
                Button(action: { copySummary(summary) }) {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy")
                Button(action: { expandedText = ExpandedTextItem(title: "AI Notes", body: summary) }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .help("Open full screen")
            }
            ScrollView {
                Text(summary)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .frame(minHeight: 220, maxHeight: 420)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.secondary.opacity(0.08))
            )
        }
    }

    private func rewriteTranscript(_ recording: VoiceRecording) {
        guard let transcript = recording.transcript, !transcript.isEmpty else {
            rewriteError = "Transcribe the audio first."
            return
        }
        guard OpenAIChatService.Configuration.apiKey != nil else {
            rewriteError = "Missing OpenAI API key. Set OPENAI_API_KEY (or legacy OPENROUTER_API_KEY) in your Xcode Scheme environment variables, or create env/.env at the repo root (copied into the app bundle during build)."
            return
        }
        rewriteError = nil
        isRewriting = true
        Task {
            do {
                let prompt = """
You are a meticulous meeting-note assistant.
Rewrite the voice note into structured plain text with these sections:
Summary:
- ...
Key Takeaways:
- ...
Action Items:
- ...
Use concise bullet points, no markdown symbols beyond dashes, and do not invent details.

Voice note:
\(transcript)
"""
                let reply = try await OpenAIChatService.send(messages: [AIChatMessage(role: .user, text: prompt)])
                await MainActor.run {
                    recorder.updateSummary(for: recordingID, summary: reply)
                    isRewriting = false
                }
            } catch {
                await MainActor.run {
                    rewriteError = error.localizedDescription
                    isRewriting = false
                }
            }
        }
    }

#if canImport(UIKit)
    private func copySummary(_ text: String) {
        UIPasteboard.general.string = text
    }
#else
    private func copySummary(_ text: String) {}
#endif

    private struct ExpandedTextItem: Identifiable {
        let id = UUID()
        let title: String
        let body: String
    }

    private struct ExpandedTextSheet: View {
        let item: ExpandedTextItem
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                ScrollView {
                    Text(item.body)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .lineSpacing(4)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .navigationTitle(item.title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", action: dismiss.callAsFunction)
                    }
#if canImport(UIKit)
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: { UIPasteboard.general.string = item.body }) {
                            Image(systemName: "doc.on.doc")
                        }
                    }
#endif
                }
            }
        }
    }

    private func labelForPage(_ pageID: UUID?) -> String? {
        guard let pageID else { return nil }
        if let model = pageStore.model(for: pageID) {
            let trimmed = model.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        if let index = pageStore.pages.firstIndex(where: { $0.id == pageID }) {
            return "Page \(index + 1)"
        }
        return nil
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
