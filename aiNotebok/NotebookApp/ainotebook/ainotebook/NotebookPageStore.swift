import SwiftUI
import PencilKit
import UIKit

final class NotebookPageStore: ObservableObject {
    @Published var pages: [CanvasController]
    @Published var activePageID: UUID?
    @Published private(set) var pageModels: [NotebookPageModel]
    @Published var pageImages: [UUID: [NotebookPageImage]]

    private let notebookID: UUID
    private let autosaveInterval: TimeInterval = 0.8
    private var autosaveWorkItems: [UUID: DispatchWorkItem] = [:]
    private let autosaveQueue = DispatchQueue(label: "NotebookPageStore.autosave")
    private let onModelsUpdated: (([NotebookPageModel]) -> Void)?

    init(notebookID: UUID, pageModels: [NotebookPageModel], onModelsUpdated: (([NotebookPageModel]) -> Void)? = nil) {
        self.notebookID = notebookID
        self.onModelsUpdated = onModelsUpdated

        let normalizedModels = pageModels.isEmpty ? [NotebookPageModel(title: "Page 1")] : pageModels
        self.pageModels = normalizedModels
        self.pageImages = Dictionary(uniqueKeysWithValues: normalizedModels.map { ($0.id, $0.images) })

        let controllers = normalizedModels.map { model in
            CanvasController(id: model.id)
        }
        self.pages = controllers
        self.activePageID = controllers.first?.id

        for (controller, model) in zip(controllers, normalizedModels) {
            configure(controller: controller, with: model)
        }
    }

    convenience init(notebook: Notebook, onModelsUpdated: (([NotebookPageModel]) -> Void)? = nil) {
        self.init(notebookID: notebook.id, pageModels: notebook.pages, onModelsUpdated: onModelsUpdated)
    }

    func controller(for id: UUID?) -> CanvasController? {
        guard let id = id else { return pages.first }
        return pages.first(where: { $0.id == id }) ?? pages.first
    }

    func model(for id: UUID) -> NotebookPageModel? {
        pageModels.first(where: { $0.id == id })
    }

    @discardableResult
    func addPage(at index: Int? = nil,
                 title: String? = nil,
                 paperStyle: PaperStyle? = nil,
                 strokeColor: UIColor? = nil,
                 strokeWidth: CGFloat? = nil,
                 tool: CanvasDrawingTool = .pen) -> CanvasController {
        let newModel = NotebookPageModel(title: title ?? "Page \(pageModels.count + 1)",
                                         paperStyle: paperStyle ?? pageModels.last?.paperStyle ?? .grid)
        let controller = CanvasController(id: newModel.id,
                                          strokeColor: strokeColor ?? pages.last?.strokeColor ?? UIColor(red: 0.12, green: 0.26, blue: 0.52, alpha: 1.0),
                                          strokeWidth: strokeWidth ?? pages.last?.strokeWidth ?? 3.2,
                                          tool: tool)
        configure(controller: controller, with: newModel)

        if let index,
           index >= 0,
           index <= pages.count {
            pageModels.insert(newModel, at: index)
            pages.insert(controller, at: index)
        } else {
            pageModels.append(newModel)
            pages.append(controller)
        }
        pageImages[newModel.id] = newModel.images

        activePageID = controller.id
        notifyModelUpdate()
        return controller
    }

    private func configure(controller: CanvasController, with model: NotebookPageModel) {
        if let saved = DrawingPersistence.load(notebookID: notebookID, pageID: model.id) ??
            (model.drawingData.flatMap { DrawingPersistence.decode(from: $0) }) {
            controller.setDrawing(saved)
            updateModel(for: model.id, drawingData: DrawingPersistence.encode(saved))
        }

        controller.onDrawingChanged = { [weak self] drawing in
            self?.handleDrawingChange(drawing, for: model.id)
        }
    }

    private func handleDrawingChange(_ drawing: PKDrawing, for pageID: UUID) {
        let data = DrawingPersistence.encode(drawing)
        updateModel(for: pageID, drawingData: data)
        scheduleAutosave(drawing, for: pageID)
    }

    private func updateModel(for pageID: UUID, drawingData: Data) {
        guard let index = pageModels.firstIndex(where: { $0.id == pageID }) else { return }
        pageModels[index].drawingData = drawingData
        notifyModelUpdate()
    }

    func images(for pageID: UUID) -> [NotebookPageImage] {
        pageImages[pageID] ?? []
    }

    func addImage(_ image: NotebookPageImage, to pageID: UUID) {
        var images = pageImages[pageID] ?? []
        images.append(image)
        setImages(images, for: pageID)
    }

    func updateImageTransform(pageID: UUID,
                              imageID: UUID,
                              center: CGPoint,
                              size: CGSize,
                              rotation: Double) {
        guard var images = pageImages[pageID],
              let index = images.firstIndex(where: { $0.id == imageID }) else { return }
        images[index].center = center
        images[index].size = size
        images[index].rotation = rotation
        setImages(images, for: pageID)
    }

    func updateImageContent(pageID: UUID,
                            imageID: UUID,
                            imageData: Data,
                            size: CGSize) {
        guard var images = pageImages[pageID],
              let index = images.firstIndex(where: { $0.id == imageID }) else { return }
        images[index].imageData = imageData
        images[index].size = size
        setImages(images, for: pageID)
    }

    func removeImage(pageID: UUID, imageID: UUID) {
        guard var images = pageImages[pageID] else { return }
        images.removeAll { $0.id == imageID }
        setImages(images, for: pageID)
    }

    func setImages(_ images: [NotebookPageImage], for pageID: UUID) {
        pageImages[pageID] = images
        if let index = pageModels.firstIndex(where: { $0.id == pageID }) {
            pageModels[index].images = images
        }
        notifyModelUpdate()
    }

    func retitlePages() {
        for index in pageModels.indices {
            pageModels[index].title = "Page \(index + 1)"
        }
        notifyModelUpdate()
    }

    private func notifyModelUpdate() {
        onModelsUpdated?(pageModels)
    }

    private func scheduleAutosave(_ drawing: PKDrawing, for pageID: UUID) {
        autosaveWorkItems[pageID]?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            DrawingPersistence.save(drawing, notebookID: self.notebookID, pageID: pageID)
        }

        autosaveWorkItems[pageID] = workItem
        autosaveQueue.asyncAfter(deadline: .now() + autosaveInterval, execute: workItem)
    }
}
