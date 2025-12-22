import SwiftUI

final class NotebookPageStore: ObservableObject {
    @Published var pages: [CanvasController]
    @Published var activePageID: UUID?

    init(pages: [CanvasController]) {
        self.pages = pages.isEmpty ? [CanvasController()] : pages
        self.activePageID = self.pages.first?.id
    }

    func controller(for id: UUID?) -> CanvasController? {
        guard let id = id else { return pages.first }
        return pages.first(where: { $0.id == id }) ?? pages.first
    }

    func addPage(after index: Int? = nil) -> CanvasController {
        let controller = CanvasController()
        if let index = index, pages.indices.contains(index) {
            pages.insert(controller, at: index + 1)
        } else {
            pages.append(controller)
        }
        activePageID = controller.id
        return controller
    }
}
