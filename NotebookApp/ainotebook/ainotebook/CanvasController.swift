import SwiftUI
import UIKit

final class CanvasController: ObservableObject {
    let id: UUID
    let canvasView: DrawingCanvasView
    var onDrawingChanged: ((InkDrawing) -> Void)?

    private static let allowedStrokeWidths: [CGFloat] = [1.8, 3.0, 4.4]
    private var currentDrawing: InkDrawing = .empty
    private var undoStack: [InkDrawing] = []
    private var redoStack: [InkDrawing] = []

    @Published var strokeColor: UIColor {
        didSet {
            let normalized = CanvasController.opaqueColor(from: strokeColor)
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
            applyCurrentTool()
        }
    }

    @Published var useEraser: Bool {
        didSet { applyCurrentTool() }
    }

    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    init(id: UUID = UUID(),
         strokeColor: UIColor = UIColor(red: 0.12, green: 0.26, blue: 0.52, alpha: 1.0),
         strokeWidth: CGFloat = 3.2,
         useEraser: Bool = false) {
        self.id = id
        let view = DrawingCanvasView()
        canvasView = view
        self.strokeColor = CanvasController.opaqueColor(from: strokeColor)
        self.strokeWidth = CanvasController.nearestStrokeWidth(to: strokeWidth)
        self.useEraser = useEraser
        configureCallbacks()
        applyCurrentTool()
        updateUndoState()
    }

    func currentDrawingValue() -> InkDrawing {
        currentDrawing
    }

    func setDrawing(_ drawing: InkDrawing) {
        currentDrawing = drawing
        canvasView.setDrawing(drawing)
        undoStack.removeAll()
        redoStack.removeAll()
        updateUndoState()
    }

    func publishDrawingChange() {
        onDrawingChanged?(currentDrawing)
    }

    func applyCurrentTool() {
        let color = CanvasController.opaqueColor(from: strokeColor)
        canvasView.setTool(color: color, width: strokeWidth, isEraser: useEraser)
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(currentDrawing)
        currentDrawing = previous
        publishDrawingChange()
        updateUndoState()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(currentDrawing)
        currentDrawing = next
        publishDrawingChange()
        updateUndoState()
    }

    func updateUndoState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
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
        canvasView.onDrawingChanged = { [weak self] drawing in
            guard let self else { return }
            self.undoStack.append(self.currentDrawing)
            self.currentDrawing = drawing
            self.canvasView.setDrawing(drawing)
            self.redoStack.removeAll()
            self.publishDrawingChange()
            self.updateUndoState()
        }
    }
}
