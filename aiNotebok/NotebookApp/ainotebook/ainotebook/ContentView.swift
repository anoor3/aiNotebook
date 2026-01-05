import SwiftUI

struct ContentView: View {
    @StateObject private var pageStore: NotebookPageStore
    @State private var notebook: Notebook
    @StateObject private var voiceRecorder: VoiceRecorderManager

    init() {
        let initialNotebook = Notebook(title: "Demo",
                                       coverColor: Color(red: 0.2, green: 0.4, blue: 0.8),
                                       pages: [NotebookPageModel(title: "Page 1")])
        _notebook = State(initialValue: initialNotebook)
        _pageStore = StateObject(wrappedValue: NotebookPageStore(notebookID: initialNotebook.id,
                                                                pageModels: initialNotebook.pages))
        _voiceRecorder = StateObject(wrappedValue: VoiceRecorderManager(notebookID: initialNotebook.id))
    }

    var body: some View {
        NotebookPageView(pageStore: pageStore,
                         notebook: $notebook,
                         voiceRecorder: voiceRecorder)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
