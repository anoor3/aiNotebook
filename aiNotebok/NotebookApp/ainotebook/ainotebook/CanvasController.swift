import SwiftUI
import PencilKit
import UIKit

enum CanvasDrawingTool: Equatable {
    case pen
    case highlighter
    case eraser

    var isDrawingTool: Bool { self != .eraser }
}

final class CanvasController: ObservableObject {
    let id: UUID
    let canvasView: PKCanvasView
    var onDrawingChanged: ((PKDrawing) -> Void)?

    private static let allowedStrokeWidths: [CGFloat] = [0.7, 3.0, 6.0]

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

    @Published var tool: CanvasDrawingTool {
        didSet { applyCurrentTool() }
    }

    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    init(id: UUID = UUID(),
         strokeColor: UIColor = UIColor(red: 0.12, green: 0.26, blue: 0.52, alpha: 1.0),
         strokeWidth: CGFloat = 3.2,
         tool: CanvasDrawingTool = .pen) {
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
        self.tool = tool
        applyCurrentTool()
        updateUndoState()
    }

    func currentDrawing() -> PKDrawing {
        canvasView.drawing
    }

    func setDrawing(_ drawing: PKDrawing) {
        canvasView.drawing = drawing
        updateUndoState()
    }

    func publishDrawingChange() {
        let drawing = canvasView.drawing
        onDrawingChanged?(drawing)
    }

    func applyCurrentTool() {
        switch tool {
        case .eraser:
            canvasView.tool = PKEraserTool(.vector)
        case .pen:
            let color = CanvasController.enhancedColor(from: CanvasController.opaqueColor(from: strokeColor))
            canvasView.tool = PKInkingTool(.pen, color: color, width: strokeWidth)
        case .highlighter:
            let color = CanvasController.highlighterColor(from: strokeColor)
            let width = CanvasController.highlighterWidth(for: strokeWidth)
            canvasView.tool = PKInkingTool(.marker, color: color, width: width)
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

    private static func enhancedColor(from color: UIColor) -> UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 1
        if color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) {
            let boostedSaturation = min(1.0, saturation * 1.15 + 0.05)
            let boostedBrightness = min(1.0, brightness * 1.1 + 0.04)
            return UIColor(hue: hue, saturation: boostedSaturation, brightness: boostedBrightness, alpha: alpha)
        }
        return color
    }

    private static func highlighterColor(from color: UIColor) -> UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 1
        guard color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return color.withAlphaComponent(0.72)
        }
        let pastelSaturation = min(0.65, max(0.25, saturation * 0.55 + 0.2))
        let boostedBrightness = min(1.0, brightness * 0.95 + 0.15)
        return UIColor(hue: hue,
                       saturation: pastelSaturation,
                       brightness: boostedBrightness,
                       alpha: 0.72)
    }

    private static func highlighterWidth(for baseWidth: CGFloat) -> CGFloat {
        let adjusted = nearestStrokeWidth(to: baseWidth)
        switch adjusted {
        case ..<1.0:
            return 12
        case ..<5.0:
            return 24
        default:
            return 32
        }
    }
}
