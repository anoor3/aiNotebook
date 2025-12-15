import SwiftUI
import PencilKit

/// Grid background that mimics light notebook paper.
struct GridPaperBackground: View {
    let spacing: CGFloat = 28
    let gridColor: Color = Color(.sRGB, red: 223/255, green: 223/255, blue: 206/255, opacity: 0.25)
    let pageColor: Color = Color(.sRGB, red: 250/255, green: 248/255, blue: 240/255, opacity: 1)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                pageColor
                Canvas { context, size in
                    var path = Path()

                    // Vertical lines
                    stride(from: 0, through: size.width, by: spacing).forEach { x in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                    }

                    // Horizontal lines
                    stride(from: 0, through: size.height, by: spacing).forEach { y in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                    }

                    context.stroke(path, with: .color(gridColor), lineWidth: 0.5)
                }
            }
            .ignoresSafeArea()
        }
    }
}

struct NotebookPageView: View {
    @StateObject private var canvasController = CanvasController()
    /// Muted academic-friendly palette.
    private let palette: [UIColor] = [
        UIColor(red: 0.12, green: 0.26, blue: 0.52, alpha: 1.0),
        UIColor(red: 0.16, green: 0.48, blue: 0.32, alpha: 1.0),
        UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0),
        UIColor(red: 0.72, green: 0.20, blue: 0.18, alpha: 1.0)
    ]

    private let thicknessOptions: [CGFloat] = [2.2, 3.2, 4.2]

    var body: some View {
        ZStack(alignment: .top) {
            GridPaperBackground()

            VStack(spacing: 12) {
                toolbar
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack {
                        PencilCanvasView(controller: canvasController)
                            .frame(minHeight: 2200) // Plenty of writing room
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 120)
                }
            }
        }
    }

    /// Compact toolbar styled like native iPadOS tools.
    private var toolbar: some View {
        HStack(spacing: 18) {
            toolButton(systemName: "pencil.tip", isActive: !canvasController.useEraser) {
                canvasController.useEraser = false
            }

            toolButton(systemName: "eraser", isActive: canvasController.useEraser) {
                canvasController.useEraser = true
            }

            Divider().frame(height: 20)

            colorButtons

            Divider().frame(height: 20)

            thicknessButtons

            Spacer()

            Button(action: { canvasController.undo() }) {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(ToolbarButtonStyle())

            Button(action: { canvasController.redo() }) {
                Image(systemName: "arrow.uturn.forward")
            }
            .buttonStyle(ToolbarButtonStyle())
        }
        .frame(height: 44)
        .padding(10)
        .background(.thinMaterial)
        .clipShape(Capsule())
    }

    private var colorButtons: some View {
        HStack(spacing: 12) {
            ForEach(Array(palette.enumerated()), id: \.offset) { _, color in
                let isSelected = canvasController.strokeColor == color && !canvasController.useEraser
                Button(action: {
                    canvasController.useEraser = false
                    canvasController.strokeColor = color
                }) {
                    Circle()
                        .fill(Color(color))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle().stroke(Color.primary.opacity(isSelected ? 0.6 : 0), lineWidth: 1.5)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private var thicknessButtons: some View {
        HStack(spacing: 10) {
            ForEach(thicknessOptions, id: \.self) { width in
                let isSelected = abs(canvasController.strokeWidth - width) < 0.1 && !canvasController.useEraser
                Button(action: {
                    canvasController.useEraser = false
                    canvasController.strokeWidth = width
                }) {
                    Capsule()
                        .fill(Color.primary.opacity(0.8))
                        .frame(width: 24, height: width)
                        .overlay(
                            Capsule().stroke(Color.accentColor.opacity(isSelected ? 0.7 : 0), lineWidth: 1.5)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private func toolButton(systemName: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .symbolVariant(isActive ? .fill : .none)
        }
        .buttonStyle(ToolbarButtonStyle(isActive: isActive))
    }
}

/// Simple rounded control look that matches iPadOS toolbars.
struct ToolbarButtonStyle: ButtonStyle {
    var isActive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(8)
            .foregroundColor(isActive ? .accentColor : .primary)
            .background(
                Capsule()
                    .fill(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
    }
}

struct NotebookPageView_Previews: PreviewProvider {
    static var previews: some View {
        NotebookPageView()
            .previewInterfaceOrientation(.landscapeLeft)
            .previewDevice("iPad (10th generation)")
    }
}
