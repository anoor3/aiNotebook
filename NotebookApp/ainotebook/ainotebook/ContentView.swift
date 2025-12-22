import SwiftUI

struct ContentView: View {
    @StateObject private var pageStore = NotebookPageStore(notebookID: UUID(),
                                                           pageModels: [NotebookPageModel(title: "Page 1")])
    var body: some View {
        NotebookPageView(pageStore: pageStore)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
