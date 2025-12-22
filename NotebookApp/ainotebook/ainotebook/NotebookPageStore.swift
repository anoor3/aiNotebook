import SwiftUI

final class NotebookPageStore: ObservableObject {
    @Published var pageModels: [NotebookPageModel]
    @Published private(set) var pageControllers: [UUID: CanvasController]
    @Published var activePageID: UUID?

    init(models: [NotebookPageModel], controllers: [UUID: CanvasController] = [:]) {
        let normalizedModels = models.isEmpty ? [NotebookPageModel(title: "Page 1")] : models
        self.pageModels = normalizedModels

        var controllerMap = controllers.filter { entry in
            normalizedModels.contains(where: { $0.id == entry.key })
        }
        for model in normalizedModels where controllerMap[model.id] == nil {
            controllerMap[model.id] = CanvasController(id: model.id)
        }
        self.pageControllers = controllerMap
        self.activePageID = normalizedModels.first?.id
    }

    var controllersInOrder: [CanvasController] {
        pageModels.compactMap { pageControllers[$0.id] }
    }

    func controller(for id: UUID?) -> CanvasController? {
        guard let id = id else { return pageModels.first.flatMap { pageControllers[$0.id] } }
        return pageControllers[id] ?? pageModels.first.flatMap { pageControllers[$0.id] }
    }

    func controller(for model: NotebookPageModel) -> CanvasController? {
        controller(for: model.id)
    }

    func index(of id: UUID?) -> Int? {
        guard let id = id else { return nil }
        return pageModels.firstIndex(where: { $0.id == id })
    }

    func insertPage(_ model: NotebookPageModel, at index: Int? = nil, controller: CanvasController? = nil) {
        let safeIndex: Int
        if let index, index >= 0, index <= pageModels.count {
            safeIndex = index
        } else {
            safeIndex = pageModels.count
        }

        pageModels.insert(model, at: safeIndex)
        pageControllers[model.id] = controller ?? CanvasController(id: model.id)
        activePageID = model.id
    }

    func syncControllers() {
        pageControllers = pageControllers.filter { entry in
            pageModels.contains(where: { $0.id == entry.key })
        }

        for model in pageModels where pageControllers[model.id] == nil {
            pageControllers[model.id] = CanvasController(id: model.id)
        }
    }

    func updateModels(_ models: [NotebookPageModel]) {
        pageModels = models.isEmpty ? [NotebookPageModel(title: "Page 1")] : models
        syncControllers()
    }
}
