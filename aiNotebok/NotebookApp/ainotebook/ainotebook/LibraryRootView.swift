import SwiftUI

struct LibraryRootView: View {
    @State private var notebooks: [Notebook] = []
    @State private var navigationPath: [Notebook.ID] = []
    @State private var showingNewNotebook = false
    @State private var renameNotebookID: Notebook.ID?
    @State private var hasLoadedLibrary = false
    @State private var hasRestoredSession = false
    @State private var showingTrash = false
    @State private var showingMarketplace = false
    @State private var showingThemePicker = false
    @State private var currentThemeID: LibraryThemeID = LibraryThemePreference.load()
    @State private var prefersDarkMode: Bool = UserDefaults.standard.bool(forKey: "NotebookDarkModePreference")

    private var theme: LibraryTheme { currentThemeID.theme }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            LibraryView(notebooks: activeNotebooks,
                        onOpen: openNotebook,
                        onNewNotebook: { showingNewNotebook = true },
                        onDelete: deleteNotebook,
                        onRenameRequest: { notebook in renameNotebookID = notebook.id },
                        onFavoriteToggle: toggleFavorite,
                        onOpenTrash: { showingTrash = true },
                        onOpenMarketplace: { showingMarketplace = true },
                        onOpenThemePicker: { showingThemePicker = true },
                        onToggleDarkMode: toggleDarkMode,
                        trashCount: trashedNotebooks.count,
                        themeID: currentThemeID,
                        prefersDarkMode: prefersDarkMode)
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
        .sheet(isPresented: $showingTrash) {
            NotebookTrashSheet(notebooks: trashedNotebooks,
                               onRestore: restoreNotebook,
                               onDeleteForever: permanentlyDeleteNotebook) {
                showingTrash = false
            }
        }
        .sheet(isPresented: $showingMarketplace) {
            NotebookMarketplaceSheet(onDismiss: { showingMarketplace = false })
        }
        .sheet(isPresented: $showingThemePicker) {
            ThemePickerSheet(currentThemeID: $currentThemeID, onDismiss: { showingThemePicker = false })
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
        .preferredColorScheme(navigationPath.isEmpty ? (prefersDarkMode ? .dark : .light) : nil)
        .onChange(of: currentThemeID) { newID in
            LibraryThemePreference.save(newID)
        }
    }

    private func toggleDarkMode() {
        prefersDarkMode.toggle()
        UserDefaults.standard.set(prefersDarkMode, forKey: "NotebookDarkModePreference")
    }

    private func binding(for id: Notebook.ID) -> Binding<Notebook>? {
        guard let index = notebooks.firstIndex(where: { $0.id == id }) else { return nil }
        return $notebooks[index]
    }

    private func openNotebook(_ notebook: Notebook) {
        guard !notebook.isTrashed else { return }
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
        guard let index = notebooks.firstIndex(where: { $0.id == notebook.id }) else { return }
        notebooks[index].isTrashed = true
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

        guard !notebooks[index].isTrashed else { return }

        let pageClamp = max(0, min(pageIndex, notebooks[index].pages.count - 1))
        notebooks[index].currentPageIndex = pageClamp
        navigationPath = [notebookID]
        hasRestoredSession = true
    }

    private func restoreNotebook(_ notebook: Notebook) {
        guard let index = notebooks.firstIndex(where: { $0.id == notebook.id }) else { return }
        notebooks[index].isTrashed = false
    }

    private func permanentlyDeleteNotebook(_ notebook: Notebook) {
        notebooks.removeAll { $0.id == notebook.id }
        SessionStatePersistence.clearIfMatching(notebook.id)
        DrawingPersistence.deleteNotebook(notebookID: notebook.id)
        VoiceRecorderManager.clearNotebookRecordings(notebookID: notebook.id)
        AIChatPersistence.delete(for: notebook.id)
        ImagePersistence.deleteNotebook(notebookID: notebook.id)
    }

    private var activeNotebooks: [Notebook] {
        notebooks.filter { !$0.isTrashed }
    }

    private var trashedNotebooks: [Notebook] {
        notebooks.filter { $0.isTrashed }
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
    var onOpenTrash: () -> Void
    var onOpenMarketplace: () -> Void
    var onOpenThemePicker: () -> Void
    var onToggleDarkMode: () -> Void
    var trashCount: Int
    var themeID: LibraryThemeID
    var prefersDarkMode: Bool

    private var theme: LibraryTheme { themeID.theme }
    private let gridItems = Array(repeating: GridItem(.flexible(), spacing: 18), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerView

                LazyVGrid(columns: gridItems, spacing: 18) {
                    ThemedNewNotebookCard(theme: theme, prefersDarkMode: prefersDarkMode, action: onNewNotebook)

                    ForEach(notebooks) { notebook in
                        ThemedNotebookCard(notebook: notebook, theme: theme)
                            .onTapGesture { onOpen(notebook) }
                            .contextMenu {
                                Button("Rename", action: { onRenameRequest(notebook) })
                                Button(notebook.isFavorite ? "Unfavorite" : "Favorite", action: { onFavoriteToggle(notebook) })
                                Divider()
                                Button(role: .destructive) { onDelete(notebook) } label: { Text("Move to Trash") }
                            }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
        .background(themeBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var themeBackground: Color {
        if themeID == .retroDark {
            return prefersDarkMode ? Color(red: 0.08, green: 0.08, blue: 0.08) : Color(red: 0.96, green: 0.96, blue: 0.94)
        }
        return theme.backgroundColor
    }

    @ViewBuilder
    private var headerView: some View {
        switch theme.headerButtonStyle {
        case .circleIcon:
            HStack(spacing: 12) {
                Text("Library")
                    .font(theme.headerTitleFont)
                Spacer()
                LibraryIconButton(systemName: prefersDarkMode ? "sun.max" : "moon", label: "Toggle mode", action: onToggleDarkMode)
                LibraryIconButton(systemName: "bag", label: "Marketplace", action: onOpenMarketplace)
                LibraryIconButton(systemName: "paintpalette", label: "Theme", action: onOpenThemePicker)
                LibraryIconButton(systemName: "trash", label: "Trash", badge: trashCount, action: onOpenTrash)
            }
        case .pillLabel:
            HStack(spacing: 12) {
                Text("Library")
                    .font(theme.headerTitleFont)
                    .foregroundColor(prefersDarkMode ? .white : .black)
                Spacer()
                Button(action: onToggleDarkMode) {
                    Image(systemName: prefersDarkMode ? "sun.max" : "moon")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(prefersDarkMode ? .white : .black)
                        .frame(width: 36, height: 36)
                        .background((prefersDarkMode ? Color.white : Color.black).opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                RetroPillButton(icon: "house.fill", label: "Marketplace", darkMode: prefersDarkMode, action: onOpenMarketplace)
                RetroPillButton(icon: "paintpalette.fill", label: "Theme", darkMode: prefersDarkMode, action: onOpenThemePicker)
                RetroPillButton(icon: "trash.fill", label: "Trash", darkMode: prefersDarkMode, action: onOpenTrash)
            }
        }
    }
}

// MARK: - Themed Notebook Card

private struct ThemedNotebookCard: View {
    let notebook: Notebook
    let theme: LibraryTheme

    var body: some View {
        if theme.cardUsesGradientCover {
            classicCard
        } else {
            retroCard
        }
    }

    private var classicCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous)
                .fill(LinearGradient(colors: [notebook.coverColor.opacity(0.95),
                                              notebook.coverColor.opacity(0.65)],
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
                .shadow(color: theme.cardShadowColor, radius: theme.cardShadowRadius, x: 0, y: 4)

            VStack(spacing: 16) {
                if notebook.isFavorite {
                    Image(systemName: theme.favoriteIcon)
                        .foregroundColor(theme.favoriteColor)
                        .font(.system(.title3, design: .monospaced))
                }
                Spacer()
                Text(notebook.title)
                    .font(theme.cardTitleFont)
                    .multilineTextAlignment(.center)
                    .foregroundColor(theme.cardTitleColor ?? .white)
                    .padding(.horizontal, 12)
                Spacer()
                HStack {
                    Text("\(notebook.pages.count) pages")
                    Spacer()
                    Text(shortDate(notebook.lastOpened))
                }
                .font(theme.cardMetaFont)
                .foregroundColor(theme.cardMetaColor)
            }
            .padding(24)
        }
        .frame(height: 190)
    }

    private var retroCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous)
                .fill(notebook.coverColor)
                .shadow(color: theme.cardShadowColor, radius: theme.cardShadowRadius, x: 0, y: 4)

            // Notebook/binder decorative lines
            NotebookPatternOverlay(patternIndex: 0)
                .clipShape(RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous))

            VStack(spacing: 16) {
                if notebook.isFavorite {
                    Image(systemName: theme.favoriteIcon)
                        .foregroundColor(.white.opacity(0.9))
                        .font(.system(.title3, design: .monospaced))
                }
                Spacer()
                Text(notebook.title)
                    .font(theme.cardTitleFont)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                Spacer()
                HStack {
                    Text("\(notebook.pages.count) pages")
                    Spacer()
                    Text(shortDate(notebook.lastOpened))
                    if notebook.isFavorite {
                        Text("★")
                    }
                }
                .font(theme.cardMetaFont)
                .foregroundColor(.white.opacity(0.9))
            }
            .padding(24)
        }
        .frame(height: 190)
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/dd/yy"
        return formatter.string(from: date)
    }
}

// MARK: - Themed New Notebook Card

private struct ThemedNewNotebookCard: View {
    let theme: LibraryTheme
    var prefersDarkMode: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(prefersDarkMode ? theme.newCardIconColor : .black)
                Text("New Notebook")
                    .font(theme.cardMetaFont)
                    .foregroundColor(prefersDarkMode ? theme.newCardTextColor : .black)
            }
            .frame(maxWidth: .infinity, minHeight: 190)
            .background(
                RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [8]))
                    .foregroundColor(prefersDarkMode ? theme.newCardBorderColor : Color.black.opacity(0.4))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Notebook Pattern Overlay

private struct NotebookPatternOverlay: View {
    let patternIndex: Int

    var body: some View {
        Canvas { context, size in
            let h = size.height
            let lineColor = Color.white.opacity(0.35)

            // Spine: 3 vertical lines on left
            for x in [CGFloat(8), CGFloat(12), CGFloat(16)] {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 4))
                path.addLine(to: CGPoint(x: x, y: h - 4))
                context.stroke(path, with: .color(lineColor), lineWidth: 0.8)
            }
        }
    }
}

// MARK: - Retro Pill Button

private struct RetroPillButton: View {
    let icon: String
    let label: String
    var darkMode: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(label)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
            }
            .foregroundColor(darkMode ? .white : .black)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                (darkMode ? Color(red: 0.18, green: 0.18, blue: 0.18) : Color(red: 0.88, green: 0.88, blue: 0.86)),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Theme Picker Sheet

private struct ThemePickerSheet: View {
    @Binding var currentThemeID: LibraryThemeID
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ForEach(LibraryThemeID.allCases) { themeOption in
                    Button {
                        currentThemeID = themeOption
                        LibraryThemePreference.save(themeOption)
                    } label: {
                        HStack(spacing: 16) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(themeOption.theme.backgroundColor)
                                .frame(width: 60, height: 60)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(themeOption.theme.cardBackground)
                                        .frame(width: 30, height: 30)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(themeOption.displayName)
                                    .font(.system(.headline, design: .monospaced))
                                Text(themeOption == .classic ? "Light background, colorful covers" : "Dark background, monospace, retro style")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if themeOption == currentThemeID {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                                    .font(.system(.title3, design: .monospaced))
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(themeOption == currentThemeID ? Color.accentColor.opacity(0.08) : Color(.tertiarySystemFill))
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle("Choose Theme")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
    }
}

private struct NotebookTrashSheet: View {
    var notebooks: [Notebook]
    var onRestore: (Notebook) -> Void
    var onDeleteForever: (Notebook) -> Void
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if notebooks.isEmpty {
                    VStack(alignment: .center, spacing: 8) {
                        Image(systemName: "trash")
                            .font(.system(.title, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text("Trash is empty")
                            .font(.system(.headline, design: .monospaced))
                        Text("Notebooks you delete will appear here.")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else {
                    ForEach(notebooks) { notebook in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(notebook.coverColor)
                                .frame(width: 28, height: 28)
                            VStack(alignment: .leading) {
                                Text(notebook.title)
                                    .font(.system(.headline, design: .monospaced))
                                Text("Last opened \(formatted(date: notebook.lastOpened))")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button { onRestore(notebook) } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            Button(role: .destructive) { onDeleteForever(notebook) } label: {
                                Label("Delete Permanently", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", role: .destructive) {
                                onDeleteForever(notebook)
                            }
                            Button("Restore") {
                                onRestore(notebook)
                            }
                            .tint(.green)
                        }
                    }
                }
            }
            .navigationTitle("Trash")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
    }

    private func formatted(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

private struct NotebookMarketplaceSheet: View {
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "bag")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
                Text("Marketplace coming soon")
                    .font(.system(.title3, design: .monospaced).bold())
                Text("We’re curating templates and covers you can drop directly into your notebooks.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                Spacer()
            }
            .padding()
            .navigationTitle("Marketplace")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDismiss)
                }
            }
        }
    }
}

// Theme persistence is now in LibraryTheme.swift (LibraryThemePreference)

private struct LibraryIconButton: View {
    var systemName: String
    var label: String
    var badge: Int? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: systemName)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                    )

                if let badge, badge > 0 {
                    Text("\(min(badge, 99))")
                        .font(.system(.caption2, design: .monospaced).bold())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.red, in: Capsule())
                        .foregroundColor(.white)
                        .offset(x: 10, y: -10)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}


struct NewNotebookSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = "My Subject"
    @State private var selectedColor: Color = Color(red: 0.28, green: 0.4, blue: 0.9)
    @State private var paperStyle: PaperStyle = .grid
    @State private var paperColor: PaperColor = .classic
    @State private var showingPDFPicker = false
    @State private var isImportingPDF = false
    @State private var importErrorMessage: String?
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
                    Picker("Page color", selection: $paperColor) {
                        ForEach(PaperColor.allCases) { color in
                            Text(color.rawValue).tag(color)
                        }
                    }
                    .pickerStyle(.segmented)
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

                Section(header: Text("Import"), footer: Text("Each PDF page becomes its own notebook page you can annotate.")) {
                    Button {
                        showingPDFPicker = true
                    } label: {
                        HStack {
                            Label("Import PDF as Notebook", systemImage: "doc.badge.plus")
                            Spacer()
                            if isImportingPDF {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isImportingPDF)
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
                                                paperStyle: paperStyle,
                                                paperColor: paperColor)
                        onCreate(notebook)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isImportingPDF)
                }
            }
            .sheet(isPresented: $showingPDFPicker) {
                PDFDocumentPicker(onPick: { url in
                    showingPDFPicker = false
                    importPDFNotebook(from: url)
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
    }

    private func importPDFNotebook(from url: URL) {
        guard !isImportingPDF else { return }
        isImportingPDF = true
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle: String
        if trimmedTitle.isEmpty || trimmedTitle == "My Subject" {
            resolvedTitle = url.deletingPathExtension().lastPathComponent
        } else {
            resolvedTitle = trimmedTitle
        }

        Task {
            do {
                let notebook = try await NotebookPDFImporter.importNotebook(from: url,
                                                                            preferredTitle: resolvedTitle,
                                                                            coverColor: selectedColor,
                                                                            paperStyle: paperStyle,
                                                                            paperColor: paperColor)
                await MainActor.run {
                    onCreate(notebook)
                    isImportingPDF = false
                    dismiss()
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
