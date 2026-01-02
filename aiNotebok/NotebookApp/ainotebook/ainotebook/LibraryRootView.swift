import SwiftUI

struct LibraryRootView: View {
    @State private var notebooks: [Notebook] = []
    @State private var navigationPath: [Notebook.ID] = []
    @State private var showingNewNotebook = false
    @State private var renameNotebookID: Notebook.ID?
    @State private var hasLoadedLibrary = false
    @State private var hasRestoredSession = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            LibraryView(notebooks: notebooks,
                        onOpen: openNotebook,
                        onNewNotebook: { showingNewNotebook = true },
                        onDelete: deleteNotebook,
                        onRenameRequest: { notebook in renameNotebookID = notebook.id },
                        onFavoriteToggle: toggleFavorite)
                .navigationDestination(for: Notebook.ID.self) { id in
                    if let binding = binding(for: id) {
                        NotebookContainerView(notebook: binding)
                    } else {
                        Text("Notebook not found")
                    }
                }
        }
        .sheet(isPresented: $showingNewNotebook) {
            NewNotebookSheet { notebook in
                notebooks.append(notebook)
                navigationPath = [notebook.id]
                SessionStatePersistence.save(notebookID: notebook.id,
                                              pageIndex: notebook.currentPageIndex)
            }
        }
        .sheet(item: Binding<RenameSession?>(
            get: { renameNotebookID.map(RenameSession.init) },
            set: { renameNotebookID = $0?.id }
        )) { session in
            if let binding = binding(for: session.id) {
                RenameNotebookSheet(notebook: binding) {
                    renameNotebookID = nil
                }
            } else {
                Text("Notebook missing")
            }
        }
        .task {
            loadLibraryIfNeeded()
        }
        .onChange(of: notebooks) { updated in
            NotebookLibraryPersistence.save(updated)
        }
    }

    private func binding(for id: Notebook.ID) -> Binding<Notebook>? {
        guard let index = notebooks.firstIndex(where: { $0.id == id }) else { return nil }
        return $notebooks[index]
    }

    private func openNotebook(_ notebook: Notebook) {
        updateLastOpened(for: notebook.id)
        SessionStatePersistence.save(notebookID: notebook.id,
                                      pageIndex: notebook.currentPageIndex)
        navigationPath = [notebook.id]
    }

    private func updateLastOpened(for id: Notebook.ID) {
        if let index = notebooks.firstIndex(where: { $0.id == id }) {
            notebooks[index].lastOpened = Date()
        }
    }

    private func deleteNotebook(_ notebook: Notebook) {
        notebooks.removeAll { $0.id == notebook.id }
        SessionStatePersistence.clearIfMatching(notebook.id)
    }

    private func toggleFavorite(_ notebook: Notebook) {
        guard let index = notebooks.firstIndex(where: { $0.id == notebook.id }) else { return }
        notebooks[index].isFavorite.toggle()
    }

    private func loadLibraryIfNeeded() {
        guard !hasLoadedLibrary else { return }
        hasLoadedLibrary = true

        if let saved = NotebookLibraryPersistence.load() {
            notebooks = saved
        } else {
            notebooks = Notebook.sampleData
        }

        restoreLastSessionIfNeeded()
    }

    private func restoreLastSessionIfNeeded() {
        guard !hasRestoredSession,
              let (notebookID, pageIndex) = SessionStatePersistence.load(),
              let index = notebooks.firstIndex(where: { $0.id == notebookID }) else { return }

        let pageClamp = max(0, min(pageIndex, notebooks[index].pages.count - 1))
        notebooks[index].currentPageIndex = pageClamp
        navigationPath = [notebookID]
        hasRestoredSession = true
    }
}

private struct RenameSession: Identifiable {
    let id: Notebook.ID
}

struct LibraryView: View {
    var notebooks: [Notebook]
    var onOpen: (Notebook) -> Void
    var onNewNotebook: () -> Void
    var onDelete: (Notebook) -> Void
    var onRenameRequest: (Notebook) -> Void
    var onFavoriteToggle: (Notebook) -> Void

    private let gridItems = Array(repeating: GridItem(.flexible(), spacing: 18), count: 3)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridItems, spacing: 18) {
                NewNotebookCard(action: onNewNotebook)

                ForEach(notebooks) { notebook in
                    NotebookCardView(notebook: notebook)
                        .onTapGesture { onOpen(notebook) }
                        .contextMenu {
                            Button("Rename", action: { onRenameRequest(notebook) })
                            Button(notebook.isFavorite ? "Unfavorite" : "Favorite", action: { onFavoriteToggle(notebook) })
                            Divider()
                            Button(role: .destructive) { onDelete(notebook) } label: { Text("Delete") }
                        }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
        .navigationTitle("Library")
    }
}

struct NotebookCardView: View {
    let notebook: Notebook

    var body: some View {
        NotebookCardCover(notebook: notebook)
            .frame(height: 190)
    }
}

private struct NotebookCardCover: View {
    let notebook: Notebook

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [notebook.coverColor.opacity(0.95),
                                              notebook.coverColor.opacity(0.65)],
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)

            VStack(spacing: 16) {
                if notebook.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundColor(.white.opacity(0.9))
                        .font(.title3)
                }

                Spacer()

                Text(notebook.title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)

                Spacer()

                HStack {
                    Text("\(notebook.pages.count) pages")
                    Spacer()
                    Text(formatted(date: notebook.lastOpened))
                }
                .font(.caption.bold())
                .foregroundColor(.white.opacity(0.92))
            }
            .padding(24)
        }
    }

    private func formatted(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}

struct NewNotebookCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 30, weight: .semibold))
                Text("New Notebook")
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity)
            .padding(32)
            .background(RoundedRectangle(cornerRadius: 20).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6])))
        }
        .buttonStyle(.plain)
    }
}

struct NewNotebookSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = "My Subject"
    @State private var selectedColor: Color = Color(red: 0.28, green: 0.4, blue: 0.9)
    @State private var paperStyle: PaperStyle = .grid
    var onCreate: (Notebook) -> Void

    private let colorOptions: [Color] = [
        .blue, .green, .orange, .pink, .purple, .red, .mint, .brown
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Details")) {
                    TextField("Subject", text: $title)
                    Picker("Paper style", selection: $paperStyle) {
                        ForEach(PaperStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                }

                Section(header: Text("Cover")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4)) {
                        ForEach(colorOptions, id: \.self) { color in
                            CoverColorOption(color: color,
                                             isSelected: color == selectedColor)
                                .onTapGesture { selectedColor = color }
                        }
                    }
                }
            }
            .navigationTitle("New Notebook")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let notebook = Notebook(title: title,
                                                coverColor: selectedColor,
                                                paperStyle: paperStyle)
                        onCreate(notebook)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

private struct CoverColorOption: View {
    let color: Color
    let isSelected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [color.opacity(0.98), color.opacity(0.6)],
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
                .frame(height: 54)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(isSelected ? 1.0 : 0.25), lineWidth: isSelected ? 3 : 1)
                )
                .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)

            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                    .blur(radius: 1)
                    .padding(3)
                    .blendMode(.screen)

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(colors: [Color.white.opacity(0.25), Color.clear],
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing)
                    )
                    .padding(2)
                    .allowsHitTesting(false)
            }
        }
        .padding(4)
    }
}

struct RenameNotebookSheet: View {
    @Binding var notebook: Notebook
    var onClose: () -> Void
    @State private var title: String = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Subject", text: $title)
            }
            .navigationTitle("Rename Notebook")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onClose() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        notebook.title = title
                        notebook.lastOpened = Date()
                        onClose()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { title = notebook.title }
        }
    }
}
