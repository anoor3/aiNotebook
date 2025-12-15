import SwiftUI
import PencilKit

struct NotebookView: View {
    @StateObject private var canvasController = CanvasController()
    @State private var selectedColor: UIColor = UIColor(red: 0.13, green: 0.14, blue: 0.16, alpha: 1.0)
    @State private var strokeWidth: CGFloat = 3.0
    @State private var isEraserActive = false

    private let colors: [UIColor] = [
        UIColor(red: 0.13, green: 0.14, blue: 0.16, alpha: 1.0),
        UIColor(red: 0.11, green: 0.43, blue: 0.93, alpha: 1.0),
        UIColor(red: 0.71, green: 0.18, blue: 0.20, alpha: 1.0),
        UIColor(red: 0.13, green: 0.50, blue: 0.33, alpha: 1.0)
    ]

    private let strokeOptions: [CGFloat] = [2.0, 3.0, 4.5]

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                toolbar
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                Divider()
                    .opacity(0.3)

                ScrollView(.vertical, showsIndicators: true) {
                    ZStack(alignment: .top) {
                        GridBackground()
                            .frame(minHeight: geometry.size.height * 3)

                        PencilCanvasView(controller: canvasController,
                                         inkColor: selectedColor,
                                         strokeWidth: strokeWidth,
                                         isEraserActive: isEraserActive)
                            .frame(minHeight: geometry.size.height * 3)
                            .padding(.horizontal, 24)
                            .padding(.top, 16)
                    }
                }
                .background(Color.clear)
            }
            .background(Color(red: 0.97, green: 0.96, blue: 0.93))
            .edgesIgnoringSafeArea(.bottom)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 18) {
            Button(action: {
                isEraserActive = false
                canvasController.apply(tool: .pen(color: selectedColor, width: strokeWidth))
            }) {
                Image(systemName: "pencil.tip")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isEraserActive ? Color.secondary : Color.primary)
            }

            Button(action: {
                isEraserActive = true
                canvasController.apply(tool: .eraser)
            }) {
                Image(systemName: "eraser")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isEraserActive ? Color.primary : Color.secondary)
            }

            Divider()
                .frame(height: 20)

            Button(action: {
                canvasController.undo()
            }) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 17, weight: .medium))
            }
            .disabled(!canvasController.canUndo)
            .opacity(canvasController.canUndo ? 1.0 : 0.4)

            Button(action: {
                canvasController.redo()
            }) {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 17, weight: .medium))
            }
            .disabled(!canvasController.canRedo)
            .opacity(canvasController.canRedo ? 1.0 : 0.4)

            Divider()
                .frame(height: 20)

            HStack(spacing: 10) {
                ForEach(colors, id: \.self) { color in
                    Button(action: {
                        selectedColor = color
                        isEraserActive = false
                        canvasController.apply(tool: .pen(color: selectedColor, width: strokeWidth))
                    }) {
                        Circle()
                            .fill(Color(color))
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(selectedColor == color ? 0.6 : 0.15), lineWidth: 1)
                            )
                    }
                }
            }

            Divider()
                .frame(height: 20)

            HStack(spacing: 8) {
                ForEach(strokeOptions, id: \.self) { width in
                    Button(action: {
                        strokeWidth = width
                        isEraserActive = false
                        canvasController.apply(tool: .pen(color: selectedColor, width: strokeWidth))
                    }) {
                        Circle()
                            .fill(Color.primary.opacity(0.85))
                            .frame(width: width + 6, height: width + 6)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(strokeWidth == width ? 0.7 : 0.2), lineWidth: 1)
                            )
                    }
                }
            }

            Spacer()
        }
    }
}

private struct GridBackground: View {
    private let gridSpacing: CGFloat = 28
    private let lineColor = Color.black.opacity(0.06)

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let columns = Int(geometry.size.width / gridSpacing)
                let rows = Int(geometry.size.height / gridSpacing)

                for index in 0...columns {
                    let x = CGFloat(index) * gridSpacing
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                }

                for index in 0...rows {
                    let y = CGFloat(index) * gridSpacing
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
            }
            .stroke(lineColor, lineWidth: 0.5)
            .background(Color(red: 0.97, green: 0.96, blue: 0.93))
        }
    }
}

final class CanvasController: ObservableObject {
    fileprivate let canvasView = PKCanvasView()
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    init() {
        configureCanvas()
    }

    func apply(tool: DrawingTool) {
        switch tool {
        case .pen(let color, let width):
            canvasView.tool = PKInkingTool(.pen, color: color, width: width)
        case .eraser:
            canvasView.tool = PKEraserTool(.vector)
        }
        updateUndoState()
    }

    func undo() {
        canvasView.undoManager?.undo()
        updateUndoState()
    }

    func redo() {
        canvasView.undoManager?.redo()
        updateUndoState()
    }

    fileprivate func updateUndoState() {
        canUndo = canvasView.undoManager?.canUndo ?? false
        canRedo = canvasView.undoManager?.canRedo ?? false
    }

    private func configureCanvas() {
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .pencilOnly
        canvasView.allowsFingerDrawing = false
        canvasView.isRulerActive = false
        canvasView.scribbleInteractionEnabled = false
        canvasView.isScrollEnabled = false
        canvasView.minimumZoomScale = 1.0
        canvasView.maximumZoomScale = 1.0
        canvasView.contentInsetAdjustmentBehavior = .never
        canvasView.alwaysBounceVertical = false
        canvasView.tool = PKInkingTool(.pen, color: UIColor(red: 0.13, green: 0.14, blue: 0.16, alpha: 1.0), width: 3.0)
    }
}

enum DrawingTool {
    case pen(color: UIColor, width: CGFloat)
    case eraser
}
