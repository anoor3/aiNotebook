import SwiftUI

struct NotebookContainerView: View {
    @Binding var notebook: Notebook
    @StateObject private var pageStore: NotebookPageStore
    @State private var showPagesSheet = false
    @State private var showAddPageSheet = false
    @State private var coverID = UUID()

    init(notebook: Binding<Notebook>) {
        self._notebook = notebook
        let initialNotebook = notebook.wrappedValue
        _pageStore = StateObject(wrappedValue: NotebookPageStore(notebookID: initialNotebook.id,
                                                                 pageModels: initialNotebook.pages,
                                                                 initialPageIndex: initialNotebook.currentPageIndex) { updatedPages in
            notebook.wrappedValue.pages = updatedPages
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)

            ZStack(alignment: .topTrailing) {
                NotebookPageView(paperStyle: notebook.paperStyle,
                                 notebookTitle: notebook.title,
                                 coverColor: notebook.coverColor,
                                 pageStore: pageStore,
                                 coverID: coverID)
            }
        }
        .toolbar {
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
            PageListView(pageStore: pageStore) {
                showPagesSheet = false
            }
        }
        .sheet(isPresented: $showAddPageSheet) {
            AddPageOptionsView(notebook: $notebook,
                               pageStore: pageStore) {
                showAddPageSheet = false
            }
        }
        .onChange(of: pageStore.activePageID) { _ in
            updateNotebookCurrentPageIndex()
        }
        .onAppear {
            updateNotebookCurrentPageIndex()
        }
    }

    private func addNewPage() {
        _ = pageStore.addPage(title: "Page \(pageStore.pages.count + 1)",
                              paperStyle: notebook.paperStyle)
        pageStore.retitlePages()
    }

    private func updateNotebookCurrentPageIndex() {
        guard let activeID = pageStore.activePageID,
              let idx = pageStore.pages.firstIndex(where: { $0.id == activeID }) else { return }
        notebook.currentPageIndex = idx
    }

    private var header: some View {
        HStack {
            Text("Pages")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            Spacer()

            Text(notebook.title)
                .font(.headline.weight(.semibold))

            Spacer()

            Text("Last opened \(formatted(date: notebook.lastOpened))")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private func formatted(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

private struct PageListView: View {
    @ObservedObject var pageStore: NotebookPageStore
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(pageStore.pages.enumerated()), id: \.element.id) { index, page in
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Page \(index + 1)")
                        }
                        Spacer()
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
                }
            }
            .navigationTitle("Pages")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onClose() }
                }
            }
        }
    }
}

private struct AddPageOptionsView: View {
    @Binding var notebook: Notebook
    @ObservedObject var pageStore: NotebookPageStore
    var onDismiss: () -> Void
    @State private var location: InsertionLocation = .afterCurrent

    enum InsertionLocation: String, CaseIterable, Identifiable {
        case beforeCurrent = "Before current"
        case afterCurrent = "After current"
        case end = "End of notebook"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Insert")) {
                    Picker("Location", selection: $location) {
                        ForEach(InsertionLocation.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                }

            }
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
                }
            }
        }
    }

    private func insertPage() {
        switch location {

        case .beforeCurrent:
            guard let idx = currentIndex else { return }
            _ = pageStore.addPage(at: idx,
                                  title: "Page \(pageStore.pages.count + 1)",
                                  paperStyle: notebook.paperStyle)
            pageStore.retitlePages()

        case .afterCurrent:
            guard let idx = currentIndex else { return }

            _ = pageStore.addPage(at: idx + 1,
                                  title: "Page \(pageStore.pages.count + 1)",
                                  paperStyle: notebook.paperStyle)
            pageStore.retitlePages()

        case .end:
            _ = pageStore.addPage(title: "Page \(pageStore.pages.count + 1)",
                                  paperStyle: notebook.paperStyle)
            pageStore.retitlePages()
        }
    }

    private var currentIndex: Int? {
        guard let id = pageStore.activePageID else { return nil }
        return pageStore.pages.firstIndex(where: { $0.id == id })
    }

}
