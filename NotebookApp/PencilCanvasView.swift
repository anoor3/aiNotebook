import SwiftUI
import PencilKit

/// Controller keeps a single PKCanvasView instance alive and exposes
/// properties SwiftUI can bind to for tool updates and undo/redo actions.
final class CanvasController: ObservableObject {
    @Published var strokeColor: UIColor = UIColor(red: 0.12, green: 0.26, blue: 0.52, alpha: 1.0) {
        didSet { applyCurrentTool() }
    }

    @Published var strokeWidth: CGFloat = 3.2 {
        didSet { applyCurrentTool() }
    }

    @Published var useEraser: Bool = false {
        didSet { applyCurrentTool() }
    }

    let canvasView: PKCanvasView = {
        let view = PKCanvasView()
        // Only Apple Pencil draws; finger is reserved for scrolling and navigation.
        view.drawingPolicy = .pencilOnly
        view.allowsFingerDrawing = false
        view.backgroundColor = .clear   // Grid shows through
        view.alwaysBounceVertical = true
        view.maximumZoomScale = 1.0
        view.minimumZoomScale = 1.0
        view.isRulerActive = false
        return view
    }()

    init() {
        applyCurrentTool()
    }

    /// Explicitly disables Scribble so the canvas remains pen-only.
    func disableScribble() {
        if #available(iOS 14.0, *) {
            canvasView.interactions
                .compactMap { $0 as? UIScribbleInteraction }
                .forEach { $0.isEnabled = false }
        }
    }

    /// Applies pen or eraser based on the current selection.
    func applyCurrentTool() {
        if useEraser {
            canvasView.tool = PKEraserTool(.vector)
        } else {
            canvasView.tool = PKInkingTool(.pen, color: strokeColor, width: strokeWidth)
        }
    }

    func undo() { canvasView.undoManager?.undo() }
    func redo() { canvasView.undoManager?.redo() }
}

/// SwiftUI wrapper for PKCanvasView so it can be embedded in layouts.
struct PencilCanvasView: UIViewRepresentable {
    @ObservedObject var controller: CanvasController

    func makeUIView(context: Context) -> PKCanvasView {
        controller.canvasView.delegate = context.coordinator
        controller.disableScribble()
        controller.applyCurrentTool()
        return controller.canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        controller.applyCurrentTool()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// Coordinator exists for future delegate hooks if needed.
    final class Coordinator: NSObject, PKCanvasViewDelegate { }
}
