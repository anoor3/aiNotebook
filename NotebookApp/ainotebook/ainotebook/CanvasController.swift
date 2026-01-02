import SwiftUI
import UIKit

final class CanvasController: ObservableObject {
    enum EraserMode: String, CaseIterable {
        case precision
        case stroke

        var width: CGFloat {
            switch self {
            case .precision:
                return 6.0
            case .stroke:
                return 14.0
            }
        }
    }
    let id: UUID
    let canvasView: DrawingCanvasView
    var onDrawingChanged: ((InkDrawing) -> Void)?
    var onImageAttachmentsChanged: (([PageImageAttachment]) -> Void)?
    var onVoiceNotesChanged: (([VoiceNote]) -> Void)?

    private static let allowedStrokeWidths: [CGFloat] = [1.8, 3.0, 4.4]
    private var undoManager = InkUndoManager()
    private var penStrokeWidth: CGFloat

    @Published var strokeColor: UIColor {
        didSet {
            let normalized: UIColor
            if useHighlighter {
                normalized = strokeColor.withAlphaComponent(0.35)
            } else {
                normalized = CanvasController.opaqueColor(from: strokeColor)
            }
            if !strokeColor.isEqual(normalized) {
                strokeColor = normalized
                return
            }
            applyCurrentTool()
        }
    }

    @Published var strokeWidth: CGFloat {
        didSet {
            let adjusted = CanvasController.nearestStrokeWidth(to: strokeWidth)
            if abs(strokeWidth - adjusted) > 0.001 {
                strokeWidth = adjusted
                return
            }
            penStrokeWidth = adjusted
            applyCurrentTool()
        }
    }

    @Published var useEraser: Bool {
        didSet {
            if useEraser {
                useHighlighter = false
            }
            applyCurrentTool()
        }
    }

    @Published var useHighlighter: Bool {
        didSet {
            if useHighlighter {
                useEraser = false
            }
            applyCurrentTool()
        }
    }

    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published var imageAttachments: [PageImageAttachment] = [] {
        didSet {
            canvasView.setAttachments(imageAttachments)
            onImageAttachmentsChanged?(imageAttachments)
        }
    }

    @Published var voiceNotes: [VoiceNote] = [] {
        didSet { onVoiceNotesChanged?(voiceNotes) }
    }
    @Published var eraserMode: EraserMode = .stroke {
        didSet { applyCurrentTool() }
    }

    init(id: UUID = UUID(),
         strokeColor: UIColor = UIColor(red: 0.12, green: 0.26, blue: 0.52, alpha: 1.0),
         strokeWidth: CGFloat = 3.2,
         useEraser: Bool = false,
         useHighlighter: Bool = false) {
        self.id = id
        let view = DrawingCanvasView()
        canvasView = view
        self.strokeColor = CanvasController.opaqueColor(from: strokeColor)
        let normalizedWidth = CanvasController.nearestStrokeWidth(to: strokeWidth)
        self.strokeWidth = normalizedWidth
        self.penStrokeWidth = normalizedWidth
        self.useEraser = useEraser
        self.useHighlighter = useHighlighter
        configureCallbacks()
        applyCurrentTool()
        setDrawing(.empty)
        canvasView.setAttachments(imageAttachments)
        updateUndoState()
    }

    func currentDrawingValue() -> InkDrawing {
        undoManager.drawing
    }

    func setDrawing(_ drawing: InkDrawing) {
        undoManager = InkUndoManager(drawing: drawing)
        canvasView.setDrawing(drawing)
        updateUndoState()
    }

    func setImageAttachments(_ attachments: [PageImageAttachment]) {
        imageAttachments = attachments
        canvasView.setAttachments(attachments)
    }

    func setVoiceNotes(_ notes: [VoiceNote]) {
        voiceNotes = notes
    }

    func setEraserMode(_ mode: EraserMode) {
        eraserMode = mode
    }

    func publishDrawingChange() {
        onDrawingChanged?(undoManager.drawing)
    }

    func applyCurrentTool() {
        let color: UIColor
        if useHighlighter {
            color = strokeColor.withAlphaComponent(0.35)
        } else {
            color = CanvasController.opaqueColor(from: strokeColor)
        }
        let width: CGFloat
        if useEraser {
            width = eraserMode.width
        } else if useHighlighter {
            width = max(penStrokeWidth, 5.5)
        } else {
            width = penStrokeWidth
        }
        canvasView.setTool(color: color, width: width, isEraser: useEraser)
    }

    func undo() {
        guard let updatedDrawing = undoManager.undo() else { return }
        canvasView.setDrawing(updatedDrawing)
        publishDrawingChange()
        updateUndoState()
    }

    func redo() {
        guard let updatedDrawing = undoManager.redo() else { return }
        canvasView.setDrawing(updatedDrawing)
        publishDrawingChange()
        updateUndoState()
    }

    func updateUndoState() {
        canUndo = undoManager.canUndo
        canRedo = undoManager.canRedo
    }

    func resetZoom(animated: Bool = true) {
        // Zoom is managed by ZoomableCanvasHostView.
    }

    private static func nearestStrokeWidth(to width: CGFloat) -> CGFloat {
        guard let closest = allowedStrokeWidths.min(by: { abs($0 - width) < abs($1 - width) }) else {
            return width
        }
        return closest
    }

    private static func opaqueColor(from color: UIColor) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 1.0
        if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return UIColor(red: red, green: green, blue: blue, alpha: 1.0)
        }
        return color.withAlphaComponent(1.0)
    }

    private func configureCallbacks() {
        canvasView.onStrokeCommitted = { [weak self] stroke in
            self?.handleStrokeCommitted(stroke)
        }
        canvasView.onAttachmentsChanged = { [weak self] updated in
            self?.imageAttachments = updated
        }
    }

    private func handleStrokeCommitted(_ stroke: InkStroke) {
        undoManager.apply(.addStroke(stroke))
        let updated = undoManager.drawing
        canvasView.setDrawing(updated)
        publishDrawingChange()
        updateUndoState()
    }
}
