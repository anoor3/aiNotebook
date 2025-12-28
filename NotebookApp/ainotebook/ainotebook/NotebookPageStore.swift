import SwiftUI
import UIKit
import Combine

final class NotebookPageStore: ObservableObject {
    @Published var pages: [CanvasController]
    @Published var activePageID: UUID?
    @Published private(set) var pageModels: [NotebookPageModel]

    private let notebookID: UUID
    private let autosaveInterval: TimeInterval = 0.8
    private var autosaveWorkItems: [UUID: DispatchWorkItem] = [:]
    private let autosaveQueue = DispatchQueue(label: "NotebookPageStore.autosave")
    private let onModelsUpdated: (([NotebookPageModel]) -> Void)?
    private var controllerCancellables: [UUID: AnyCancellable] = [:]

    init(notebookID: UUID, pageModels: [NotebookPageModel], onModelsUpdated: (([NotebookPageModel]) -> Void)? = nil) {
        self.notebookID = notebookID
        self.pageModels = pageModels.isEmpty ? [NotebookPageModel(title: "Page 1")] : pageModels
        self.onModelsUpdated = onModelsUpdated

        self.pages = self.pageModels.map { model in
            let controller = CanvasController(id: model.id)
            configure(controller: controller, with: model)
            return controller
        }
        self.activePageID = pages.first?.id
    }

    convenience init(notebook: Notebook, onModelsUpdated: (([NotebookPageModel]) -> Void)? = nil) {
        self.init(notebookID: notebook.id, pageModels: notebook.pages, onModelsUpdated: onModelsUpdated)
    }

    var notebookIdentifier: UUID {
        notebookID
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
                 useEraser: Bool = false) -> CanvasController {
        let newModel = NotebookPageModel(title: title ?? "Page \(pageModels.count + 1)",
                                         paperStyle: paperStyle ?? pageModels.last?.paperStyle ?? .grid)
        let controller = CanvasController(id: newModel.id,
                                          strokeColor: strokeColor ?? pages.last?.strokeColor ?? UIColor(red: 0.12, green: 0.26, blue: 0.52, alpha: 1.0),
                                          strokeWidth: strokeWidth ?? pages.last?.strokeWidth ?? 3.2,
                                          useEraser: useEraser)
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

        activePageID = controller.id
        notifyModelUpdate()
        return controller
    }

    private func configure(controller: CanvasController, with model: NotebookPageModel) {
        if let saved = DrawingPersistence.load(notebookID: notebookID, pageID: model.id) ??
            (model.drawingData.flatMap { DrawingPersistence.decodeOrMigrate($0) }) {
            controller.setDrawing(saved)
            updateModel(for: model.id, drawingData: DrawingPersistence.encode(saved))
        }

        controller.setImageAttachments(model.imageAttachments)
        controller.setVoiceNotes(model.voiceNotes)

        controller.onDrawingChanged = { [weak self] drawing in
            self?.handleDrawingChange(drawing, for: model.id)
        }

        controller.onImageAttachmentsChanged = { [weak self] attachments in
            self?.handleImageChange(attachments, for: model.id)
        }

        controller.onVoiceNotesChanged = { [weak self] notes in
            self?.handleVoiceNotesChange(notes, for: model.id)
        }

        controllerCancellables[controller.id] = controller.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    private func handleDrawingChange(_ drawing: InkDrawing, for pageID: UUID) {
        let data = DrawingPersistence.encode(drawing)
        updateModel(for: pageID, drawingData: data)
        scheduleAutosave(drawing, for: pageID)
    }

    private func handleImageChange(_ attachments: [PageImageAttachment], for pageID: UUID) {
        guard let index = pageModels.firstIndex(where: { $0.id == pageID }) else { return }
        pageModels[index].imageAttachments = attachments
        notifyModelUpdate()
    }

    private func handleVoiceNotesChange(_ notes: [VoiceNote], for pageID: UUID) {
        guard let index = pageModels.firstIndex(where: { $0.id == pageID }) else { return }
        pageModels[index].voiceNotes = notes
        notifyModelUpdate()
    }

    private func updateModel(for pageID: UUID, drawingData: Data) {
        guard let index = pageModels.firstIndex(where: { $0.id == pageID }) else { return }
        pageModels[index].drawingData = drawingData
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

    private func scheduleAutosave(_ drawing: InkDrawing, for pageID: UUID) {
        autosaveWorkItems[pageID]?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            DrawingPersistence.save(drawing, notebookID: self.notebookID, pageID: pageID)
        }

        autosaveWorkItems[pageID] = workItem
        autosaveQueue.asyncAfter(deadline: .now() + autosaveInterval, execute: workItem)
    }
}
