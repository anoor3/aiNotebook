import SwiftUI

struct ContentView: View {
    @StateObject private var pageStore = NotebookPageStore(notebookID: UUID(),
                                                           pageModels: [NotebookPageModel(title: "Page 1")])
    @State private var notebook = Notebook(title: "Demo", coverColor: Color(red: 0.2, green: 0.4, blue: 0.8))
    var body: some View {
        NotebookPageView(pageStore: pageStore, notebook: $notebook)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
