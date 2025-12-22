import SwiftUI

struct NotebookContainerView: View {
    @Binding var notebook: Notebook
    @StateObject private var pageStore: NotebookPageStore
    @State private var showPagesSheet = false
    @State private var showAddPageSheet = false

    init(notebook: Binding<Notebook>) {
        self._notebook = notebook
        let controllers: [CanvasController]
        if notebook.wrappedValue.pages.isEmpty {
            controllers = [CanvasController()]
        } else {
            controllers = notebook.wrappedValue.pages.map { _ in CanvasController() }
        }
        _pageStore = StateObject(wrappedValue: NotebookPageStore(pages: controllers))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NotebookPageView(paperStyle: notebook.paperStyle, pageStore: pageStore)
                .navigationTitle(notebook.title)
                .navigationBarTitleDisplayMode(.inline)
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
        let controller = CanvasController()
        pageStore.pages.append(controller)
        pageStore.activePageID = controller.id
        notebook.pages.append(NotebookPageModel(title: "Page \(notebook.pages.count + 1)", paperStyle: notebook.paperStyle))
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
        guard notebook.pages.count == pageStore.pages.count else {
            assertionFailure("Page models and controllers must remain aligned")
            return
        }

        let controller = CanvasController()
        let model = NotebookPageModel(title: "Page \(notebook.pages.count + 1)", paperStyle: notebook.paperStyle)

        switch location {

        case .beforeCurrent:
            guard let idx = currentIndex,
                  idx >= 0,
                  idx <= pageStore.pages.count,
                  idx <= notebook.pages.count
            else { return }

            pageStore.pages.insert(controller, at: idx)
            notebook.pages.insert(model, at: idx)
            pageStore.activePageID = controller.id
            retitlePages()

        case .afterCurrent:
            guard let idx = currentIndex else { return }

            let insertIndex = min(idx + 1, pageStore.pages.count)

            guard insertIndex <= notebook.pages.count else { return }

            pageStore.pages.insert(controller, at: insertIndex)
            notebook.pages.insert(model, at: insertIndex)
            pageStore.activePageID = controller.id
            retitlePages()

        case .end:
            pageStore.pages.append(controller)
            notebook.pages.append(model)
            pageStore.activePageID = controller.id
            retitlePages()
        }
        assert(notebook.pages.count == pageStore.pages.count, "Page models and controllers must stay aligned after insertion")
    }

    private var currentIndex: Int? {
        guard let id = pageStore.activePageID else { return nil }
        return pageStore.pages.firstIndex(where: { $0.id == id })
    }

    private func retitlePages() {
        for index in notebook.pages.indices {
            notebook.pages[index].title = "Page \(index + 1)"
        }
    }
}
