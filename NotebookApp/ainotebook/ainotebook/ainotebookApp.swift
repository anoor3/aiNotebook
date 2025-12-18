import SwiftUI

@main
struct ainotebookApp: App {
    var body: some Scene {
        WindowGroup {
            NotebookPageView()
        }
        .defaultSize(CGSize(width: 1024, height: 768))
    }
}
