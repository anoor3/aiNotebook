import SwiftUI

struct NotebookContainerView: View {
    @Binding var notebook: Notebook
    @StateObject private var pageStore: NotebookPageStore
    @State private var showPagesSheet = false
    @State private var showAddPageSheet = false

    init(notebook: Binding<Notebook>) {
        self._notebook = notebook
        let initialNotebook = notebook.wrappedValue
        _pageStore = StateObject(wrappedValue: NotebookPageStore(notebook: initialNotebook) { updatedPages in
            notebook.wrappedValue.pages = updatedPages
        })
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NotebookPageView(paperStyle: notebook.paperStyle,
                             pageStore: pageStore,
                             notebook: $notebook)
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
        _ = pageStore.addPage(title: "Page \(pageStore.pages.count + 1)",
                              paperStyle: notebook.paperStyle)
        pageStore.retitlePages()
    }
}

private struct PageListView: View {
    @ObservedObject var pageStore: NotebookPageStore
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(pageStore.pages.enumerated()), id: \.element.id) { (index, page) in
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

extension Notification.Name {
    static let notebookRequestExport = Notification.Name("NotebookRequestExport")
}
