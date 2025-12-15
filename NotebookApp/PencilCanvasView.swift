import SwiftUI
import PencilKit

struct PencilCanvasView: UIViewRepresentable {
    @ObservedObject var controller: CanvasController
    var inkColor: UIColor
    var strokeWidth: CGFloat
    var isEraserActive: Bool

    func makeUIView(context: Context) -> PKCanvasView {
        controller.canvasView.delegate = context.coordinator
        controller.apply(tool: isEraserActive ? .eraser : .pen(color: inkColor, width: strokeWidth))
        controller.updateUndoState()
        return controller.canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        let currentTool = isEraserActive ? DrawingTool.eraser : .pen(color: inkColor, width: strokeWidth)
        controller.apply(tool: currentTool)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        private let controller: CanvasController

        init(controller: CanvasController) {
            self.controller = controller
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            controller.updateUndoState()
        }
    }
}
