import SwiftUI

struct NotebookContainerView: View {
    @Binding var notebook: Notebook
    @StateObject private var pageStore: NotebookPageStore
    @StateObject private var voiceRecorder: VoiceRecorderManager
    @State private var showPagesSheet = false
    @State private var showAddPageSheet = false

    init(notebook: Binding<Notebook>) {
        self._notebook = notebook
        let initialNotebook = notebook.wrappedValue
        _pageStore = StateObject(wrappedValue: NotebookPageStore(notebook: initialNotebook) { updatedPages in
            notebook.wrappedValue.pages = updatedPages
        })
        _voiceRecorder = StateObject(wrappedValue: VoiceRecorderManager(notebookID: initialNotebook.id))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NotebookPageView(paperStyle: notebook.paperStyle,
                             pageColor: notebook.paperColor,
                             pageStore: pageStore,
                             notebook: $notebook,
                             voiceRecorder: voiceRecorder)
                .navigationTitle(notebook.title)
                .navigationBarTitleDisplayMode(.inline)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    NotificationCenter.default.post(name: .notebookRequestExport, object: nil)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showPagesSheet = true
                } label: {
                    Image(systemName: "square.grid.2x2")
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddPageSheet = true
                } label: {
                    Image(systemName: "plus.rectangle.on.rectangle")
                }
            }
        }
        .sheet(isPresented: $showPagesSheet) {
            PageListView(pageStore: pageStore,
                         voiceRecorder: voiceRecorder) {
                showPagesSheet = false
            }
        }
        .sheet(isPresented: $showAddPageSheet) {
            AddPageOptionsView(notebook: $notebook,
                               pageStore: pageStore) {
                showAddPageSheet = false
            }
            .presentationDetents([.fraction(0.75)])
        }
    }

    private func addNewPage() {
        _ = pageStore.addPage(title: "Page \(pageStore.pages.count + 1)",
                              paperStyle: notebook.paperStyle)
        pageStore.retitlePages()
    }
}

private struct PageListView: View {
    @ObservedObject var pageStore: NotebookPageStore
    @ObservedObject var voiceRecorder: VoiceRecorderManager
    var onClose: () -> Void
    @State private var pendingDeleteID: UUID?

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(pageStore.pages.enumerated()), id: \.element.id) { (index, page) in
                    let recordings = voiceRecorder.recordings(for: page.id)
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Page \(index + 1)")
                            if let latest = recordings.first {
                                Text("\(latest.title) • \(formattedDuration(latest.duration))")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        if !recordings.isEmpty {
                            Menu {
                                ForEach(recordings) { recording in
                                    Button {
                                        voiceRecorder.playRecording(recording)
                                    } label: {
                                        Label(menuLabel(for: recording),
                                              systemImage: voiceRecorder.playingRecordingID == recording.id ? "stop.circle" : "play.circle")
                                    }
                                }
                                if voiceRecorder.playingRecordingID != nil {
                                    Button("Stop Playback", role: .cancel) {
                                        voiceRecorder.stopPlayback()
                                    }
                                }
                            } label: {
                                Label("Review recording", systemImage: "waveform")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                        if page.id == pageStore.activePageID {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        pageStore.activePageID = page.id
                        onClose()
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            pendingDeleteID = page.id
                        } label: {
                            Label("Delete Page", systemImage: "trash")
                        }
                        .disabled(pageStore.pages.count <= 1)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemBackground))
            .listStyle(.plain)
            .navigationTitle("Pages")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onClose() }
                }
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .confirmationDialog("Delete page?",
                             isPresented: Binding(get: { pendingDeleteID != nil },
                                                  set: { if !$0 { pendingDeleteID = nil } }),
                             presenting: pendingDeleteID) { pageID in
            Button("Delete Page", role: .destructive) {
                pageStore.deletePage(withID: pageID)
                pendingDeleteID = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteID = nil
            }
        } message: { _ in
            Text("This page will be permanently removed from the notebook.")
        }
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func menuLabel(for recording: VoiceRecording) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        let timestamp = formatter.string(from: recording.createdAt)
        return "\(recording.title) · \(formattedDuration(recording.duration)) · \(timestamp)"
    }
}

private struct AddPageOptionsView: View {
    @Binding var notebook: Notebook
    @ObservedObject var pageStore: NotebookPageStore
    var onDismiss: () -> Void
    @State private var location: InsertionLocation = .afterCurrent
    @State private var showingPDFPicker = false
    @State private var isImportingPDF = false
    @State private var importErrorMessage: String?

    enum InsertionLocation: String, CaseIterable, Identifiable {
        case beforeCurrent = "Before current"
        case afterCurrent = "After current"
        case end = "End of notebook"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Insert")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    Picker("Location", selection: $location) {
                        ForEach(InsertionLocation.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text("Import")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    Button {
                        showingPDFPicker = true
                    } label: {
                        HStack {
                            Label("Import PDF Pages", systemImage: "doc.badge.plus")
                                Spacer()
                                if isImportingPDF {
                                    ProgressView()
                                }
                            }
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                    .disabled(isImportingPDF)
                    Text("Adds every PDF page at the selected position.")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )

                Spacer(minLength: 0)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("Add Page")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        insertPage()
                        onDismiss()
                    }
                    .disabled(isImportingPDF)
                }
            }
            .sheet(isPresented: $showingPDFPicker) {
                PDFDocumentPicker(onPick: { url in
                    showingPDFPicker = false
                    importPDFPages(from: url)
                }, onCancel: {
                    showingPDFPicker = false
                })
            }
            .alert("Import Failed",
                   isPresented: Binding(get: { importErrorMessage != nil },
                                        set: { if !$0 { importErrorMessage = nil } })) {
                Button("OK", role: .cancel) { importErrorMessage = nil }
            } message: {
                Text(importErrorMessage ?? "Unknown error")
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
    }

    private func insertPage() {
        guard let targetIndex = insertionIndex(for: location) else { return }
        _ = pageStore.addPage(at: targetIndex,
                              title: "Page \(pageStore.pages.count + 1)",
                              paperStyle: notebook.paperStyle)
        pageStore.retitlePages()
    }

    private var currentIndex: Int? {
        guard let id = pageStore.activePageID else { return nil }
        return pageStore.pages.firstIndex(where: { $0.id == id })
    }

    private func insertionIndex(for location: InsertionLocation) -> Int? {
        switch location {
        case .beforeCurrent:
            guard let idx = currentIndex else { return nil }
            return idx
        case .afterCurrent:
            guard let idx = currentIndex else { return nil }
            return idx + 1
        case .end:
            return pageStore.pages.count
        }
    }

    private func importPDFPages(from url: URL) {
        guard !isImportingPDF else { return }
        guard let targetIndex = insertionIndex(for: location) else { return }
        isImportingPDF = true

        Task {
            do {
                let models = try await NotebookPDFImporter.importPages(from: url,
                                                                       paperStyle: notebook.paperStyle)
                await MainActor.run {
                    pageStore.insertPages(models, at: targetIndex)
                    pageStore.retitlePages()
                    isImportingPDF = false
                    onDismiss()
                }
            } catch {
                await MainActor.run {
                    importErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    isImportingPDF = false
                }
            }
        }
    }
}

extension Notification.Name {
    static let notebookRequestExport = Notification.Name("NotebookRequestExport")
}
