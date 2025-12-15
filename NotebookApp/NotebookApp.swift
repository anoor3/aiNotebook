import SwiftUI

@main
struct NotebookApp: App {
    var body: some Scene {
        WindowGroup {
            NotebookView()
        }
        .defaultSize(CGSize(width: 1024, height: 768))
            NotebookPageView()
        }
    }
}
