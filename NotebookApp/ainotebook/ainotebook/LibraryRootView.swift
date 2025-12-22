import SwiftUI

struct LibraryRootView: View {
    @State private var notebooks: [Notebook] = Notebook.sampleData
    @State private var navigationPath: [Notebook.ID] = []
    @State private var showingNewNotebook = false
    @State private var renameNotebookID: Notebook.ID?

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
    }

    private func binding(for id: Notebook.ID) -> Binding<Notebook>? {
        guard let index = notebooks.firstIndex(where: { $0.id == id }) else { return nil }
        return $notebooks[index]
    }

    private func openNotebook(_ notebook: Notebook) {
        updateLastOpened(for: notebook.id)
        navigationPath = [notebook.id]
    }

    private func updateLastOpened(for id: Notebook.ID) {
        if let index = notebooks.firstIndex(where: { $0.id == id }) {
            notebooks[index].lastOpened = Date()
        }
    }

    private func deleteNotebook(_ notebook: Notebook) {
        notebooks.removeAll { $0.id == notebook.id }
    }

    private func toggleFavorite(_ notebook: Notebook) {
        guard let index = notebooks.firstIndex(where: { $0.id == notebook.id }) else { return }
        notebooks[index].isFavorite.toggle()
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
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(notebook.coverColor)
                .frame(height: 120)
                .overlay(
                    Text(notebook.title)
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(12), alignment: .bottomLeading)

            Text("Last opened \(formatted(date: notebook.lastOpened))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func formatted(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
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
    @State private var title: String = "My Notebook"
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
                    TextField("Notebook name", text: $title)
                    Picker("Paper style", selection: $paperStyle) {
                        ForEach(PaperStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                }

                Section(header: Text("Cover")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4)) {
                        ForEach(colorOptions, id: \.self) { color in
                            Circle()
                                .fill(color)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle().stroke(Color.white.opacity(color == selectedColor ? 1 : 0), lineWidth: 2)
                                )
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
                        let notebook = Notebook(title: title, coverColor: selectedColor, paperStyle: paperStyle)
                        onCreate(notebook)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct RenameNotebookSheet: View {
    @Binding var notebook: Notebook
    var onClose: () -> Void
    @State private var title: String = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Notebook name", text: $title)
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
