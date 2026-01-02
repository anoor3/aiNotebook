import SwiftUI
import PencilKit

struct NotebookView: View {
    private static let palette: [UIColor] = [
        UIColor(red: 0.13, green: 0.14, blue: 0.16, alpha: 1.0),
        UIColor(red: 0.11, green: 0.43, blue: 0.93, alpha: 1.0),
        UIColor(red: 0.71, green: 0.18, blue: 0.20, alpha: 1.0),
        UIColor(red: 0.13, green: 0.50, blue: 0.33, alpha: 1.0)
    ]

    private static let strokeOptions: [CGFloat] = [0.7, 3.0, 6.0]

    @StateObject private var canvasController: CanvasController

    init() {
        let controller = CanvasController(strokeColor: Self.palette[0], strokeWidth: Self.strokeOptions[1])
        _canvasController = StateObject(wrappedValue: controller)
    }

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
                                          pageSize: CGSize(width: 1024, height: 1400),
                                          paperStyle: .grid)
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
                canvasController.tool = .pen
            }) {
                Image(systemName: "pencil.tip")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(canvasController.tool == .eraser ? Color.secondary : Color.primary)
            }

            Button(action: {
                canvasController.tool = .eraser
            }) {
                Image(systemName: "eraser")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(canvasController.tool == .eraser ? Color.primary : Color.secondary)
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
                ForEach(Self.palette, id: \.self) { color in
                    let isSelected = canvasController.strokeColor == color && canvasController.tool != .eraser
                    Button(action: {
                        canvasController.tool = .pen
                        canvasController.strokeColor = color
                    }) {
                        Circle()
                            .fill(Color(color))
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(isSelected ? 0.6 : 0.15), lineWidth: 1)
                            )
                    }
                }
            }

            Divider()
                .frame(height: 20)

            HStack(spacing: 8) {
                ForEach(Self.strokeOptions, id: \.self) { width in
                    let isSelected = abs(canvasController.strokeWidth - width) < 0.1 && canvasController.tool != .eraser
                    Button(action: {
                        canvasController.tool = .pen
                        canvasController.strokeWidth = width
                    }) {
                        Circle()
                            .fill(Color.primary.opacity(0.85))
                            .frame(width: width + 6, height: width + 6)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(isSelected ? 0.7 : 0.2), lineWidth: 1)
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
