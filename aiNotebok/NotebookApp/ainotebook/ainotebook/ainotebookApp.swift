import SwiftUI

@main
struct ainotebookApp: App {
    var body: some Scene {
        WindowGroup {
            LibraryRootView()
                .environment(\.font, .system(.body, design: .monospaced))
        }
        .defaultSize(CGSize(width: 1024, height: 768))
    }
}
