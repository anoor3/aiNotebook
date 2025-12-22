import SwiftUI

struct ContentView: View {
    @StateObject private var pageStore = NotebookPageStore(pages: [CanvasController()])
    var body: some View {
        NotebookPageView(pageStore: pageStore)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
