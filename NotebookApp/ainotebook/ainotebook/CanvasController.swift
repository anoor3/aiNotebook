import SwiftUI
import PencilKit
import UIKit

final class CanvasController: ObservableObject {
    let id: UUID
    let canvasView: PKCanvasView

    private static let allowedStrokeWidths: [CGFloat] = [1.8, 3.0, 4.4]

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
        let view = PKCanvasView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.drawingPolicy = .pencilOnly
        view.isRulerActive = false
        view.isScrollEnabled = false
        view.alwaysBounceVertical = false
        view.alwaysBounceHorizontal = false
        view.maximumZoomScale = 1.0
        view.minimumZoomScale = 1.0
        view.bouncesZoom = false
        view.showsHorizontalScrollIndicator = false
        view.showsVerticalScrollIndicator = false
        view.allowsFingerDrawing = false
        view.contentScaleFactor = UIScreen.main.scale
        view.layer.contentsScale = UIScreen.main.scale
        canvasView = view
        self.strokeColor = CanvasController.opaqueColor(from: strokeColor)
        self.strokeWidth = CanvasController.nearestStrokeWidth(to: strokeWidth)
        self.useEraser = useEraser
        applyCurrentTool()
        updateUndoState()
    }

    func applyCurrentTool() {
        if useEraser {
            canvasView.tool = PKEraserTool(.vector)
        } else {
            let color = CanvasController.opaqueColor(from: strokeColor)
            canvasView.tool = PKInkingTool(.pen, color: color, width: strokeWidth)
        }
    }

    func undo() {
        canvasView.undoManager?.undo()
        updateUndoState()
    }

    func redo() {
        canvasView.undoManager?.redo()
        updateUndoState()
    }

    func updateUndoState() {
        canUndo = canvasView.undoManager?.canUndo ?? false
        canRedo = canvasView.undoManager?.canRedo ?? false
    }

    func resetZoom(animated: Bool = true) {
        canvasView.setZoomScale(1.0, animated: animated)
        canvasView.panGestureRecognizer.minimumNumberOfTouches = 2
    }

    func disableScribbleInteraction() {
        if #available(iOS 14.0, *) {
            for interaction in canvasView.interactions {
                if let scribble = interaction as? UIScribbleInteraction {
                    canvasView.removeInteraction(scribble)
                }
            }
        }
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
}
