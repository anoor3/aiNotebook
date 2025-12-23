import SwiftUI

struct ContentView: View {
    @StateObject private var pageStore = NotebookPageStore(notebookID: UUID(),
                                                           pageModels: [NotebookPageModel(title: "Page 1")])
    var body: some View {
        NotebookPageView(paperStyle: .grid,
                         notebookTitle: "Preview Notebook",
                         coverColor: Color(red: 0.28, green: 0.4, blue: 0.9),
                         pageStore: pageStore)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
