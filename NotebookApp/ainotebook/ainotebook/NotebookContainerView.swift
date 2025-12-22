import SwiftUI

struct NotebookContainerView: View {
    @Binding var notebook: Notebook
    @StateObject private var pageStore: NotebookPageStore
    @State private var showPagesSheet = false
    @State private var showAddPageSheet = false

    init(notebook: Binding<Notebook>) {
        self._notebook = notebook
        let pageModels = notebook.wrappedValue.pages.isEmpty
        ? [NotebookPageModel(title: "Page 1", paperStyle: notebook.wrappedValue.paperStyle)]
        : notebook.wrappedValue.pages

        var controllers: [UUID: CanvasController] = [:]
        for model in pageModels {
            controllers[model.id] = CanvasController(id: model.id)
        }

        _pageStore = StateObject(wrappedValue: NotebookPageStore(models: pageModels, controllers: controllers))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NotebookPageView(paperStyle: notebook.paperStyle, pageStore: pageStore)
                .navigationTitle(notebook.title)
                .navigationBarTitleDisplayMode(.inline)
                .onChange(of: pageStore.pageModels) { models in
                    notebook.pages = models
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
    }

    private func addNewPage() {
        let model = NotebookPageModel(title: "Page \(pageStore.pageModels.count + 1)", paperStyle: notebook.paperStyle)
        let controller = CanvasController(id: model.id)
        pageStore.insertPage(model, controller: controller)
        notebook.pages.append(model)
        retitlePages()
    }
}

private struct PageListView: View {
    @ObservedObject var pageStore: NotebookPageStore
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(pageStore.pageModels.enumerated()), id: \.element.id) { index, page in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(page.title)
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
        let model = NotebookPageModel(title: "Page \(pageStore.pageModels.count + 1)", paperStyle: notebook.paperStyle)
        let controller = CanvasController(id: model.id)
        let targetIndex = resolvedInsertionIndex()

        guard let insertionIndex = targetIndex else { return }
        pageStore.insertPage(model, at: insertionIndex, controller: controller)
        notebook.pages.insert(model, at: insertionIndex)
        retitlePages()
    }

    private var currentIndex: Int? {
        guard let id = pageStore.activePageID else { return nil }
        return pageStore.pageModels.firstIndex(where: { $0.id == id })
    }

    private func resolvedInsertionIndex() -> Int? {
        let totalPages = pageStore.pageModels.count

        switch location {
        case .beforeCurrent:
            guard let idx = currentIndex else { return 0 }
            return min(idx, totalPages)
        case .afterCurrent:
            guard let idx = currentIndex else { return totalPages }
            return min(idx + 1, totalPages)
        case .end:
            return totalPages
        }
    }

    private func retitlePages() {
        notebook.pages = notebook.pages.enumerated().map { index, page in
            var updatedPage = page
            updatedPage.title = "Page \(index + 1)"
            return updatedPage
        }
        pageStore.updateModels(notebook.pages)
    }
}
