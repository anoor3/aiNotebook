import SwiftUI
import PencilKit

private struct PageVisibilityPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]

    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

struct NotebookPageView: View {
    private static let palette: [UIColor] = [
        UIColor(red: 0.12, green: 0.26, blue: 0.52, alpha: 1.0),
        UIColor(red: 0.16, green: 0.48, blue: 0.32, alpha: 1.0),
        UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0),
        UIColor(red: 0.72, green: 0.20, blue: 0.18, alpha: 1.0)
    ]

    private static let thicknessOptions: [CGFloat] = [2.2, 3.2, 4.2]
    private let scrollSpaceName = "NotebookScroll"
    private let defaultPageSize = CGSize(width: 800, height: 1000)

    @State private var pages: [CanvasController]
    @State private var isLoadingNextPage = false
    @State private var activePageID: UUID?
    @State private var currentStrokeColor: UIColor
    @State private var currentStrokeWidth: CGFloat
    @State private var isUsingEraser = false
    @State private var showCustomColorPicker = false
    @State private var customColor: Color = Color(red: 0.95, green: 0.55, blue: 0.2)
    @State private var paletteSelection = CGPoint(x: 0.6, y: 0.3)
    private let customColorSuggestions: [Color] = [
        Color(red: 0.99, green: 0.36, blue: 0.33),
        Color(red: 0.98, green: 0.68, blue: 0.24),
        Color(red: 0.99, green: 0.85, blue: 0.32),
        Color(red: 0.34, green: 0.78, blue: 0.38),
        Color(red: 0.26, green: 0.64, blue: 0.94),
        Color(red: 0.53, green: 0.44, blue: 0.96),
        Color(red: 0.74, green: 0.41, blue: 0.89),
        Color(red: 0.95, green: 0.52, blue: 0.70)
    ]

    init() {
        let defaultColor = Self.palette[0]
        let defaultWidth = Self.thicknessOptions[1]
        let controller = CanvasController(strokeColor: defaultColor, strokeWidth: defaultWidth)
        _pages = State(initialValue: [controller])
        _currentStrokeColor = State(initialValue: defaultColor)
        _currentStrokeWidth = State(initialValue: defaultWidth)
        _activePageID = State(initialValue: controller.id)
    }

    var body: some View {
        GeometryReader { geometry in
            let pageSize = defaultPageSize
            let viewportHeight = max(min(pageSize.height + 60, geometry.size.height - 80), 420)

            ZStack(alignment: .top) {
                Color(red: 0.97, green: 0.96, blue: 0.92)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    toolbar
                        .padding(.top, 12)

                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 40) {
                                ForEach(pages, id: \.id) { controller in
                                    notebookPage(for: controller,
                                                 pageSize: pageSize,
                                                 viewportHeight: viewportHeight)
                                    .frame(maxWidth: .infinity)
                            }

                            addPagePrompt
                                .onAppear {
                                    requestAdditionalPage()
                                }
                        }
                        .padding(.vertical, 40)
                        .frame(maxWidth: .infinity)
                    }
                    .coordinateSpace(name: scrollSpaceName)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .onPreferenceChange(PageVisibilityPreferenceKey.self) { values in
                    guard let closest = values.min(by: { $0.value < $1.value }) else { return }
                    if activePageID != closest.key {
                        activePageID = closest.key
                    }
                }
            }
        }
        .overlay(alignment: .center) {
            if showCustomColorPicker {
                ZStack {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()

                    CustomColorPopover(customColor: $customColor,
                                       suggestions: customColorSuggestions,
                                       paletteSelection: $paletteSelection,
                                       onClose: { showCustomColorPicker = false },
                                       onSelectSuggestion: { color in
                                           customColor = color
                                           updatePaletteSelection(for: color)
                                       })
                        .padding(24)
                }
            }
        }
        .onChange(of: customColor) { _ in
            applyCustomColorSelection()
        }
    }

    /// Compact toolbar styled like native iPadOS tools.
    private var toolbar: some View {
        HStack(spacing: 18) {
            toolButton(systemName: "pencil.tip", isActive: !isUsingEraser) {
                isUsingEraser = false
                applyToolSettings(useEraser: false)
            }

            toolButton(systemName: "eraser", isActive: isUsingEraser) {
                isUsingEraser = true
                applyToolSettings(useEraser: true)
            }

            Divider().frame(height: 20)

            colorButtons

            Divider().frame(height: 20)

            thicknessButtons

            Spacer()

            Button(action: { activePageController?.undo() }) {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(ToolbarButtonStyle(isActive: false))
            .disabled(!(activePageController?.canUndo ?? false))
            .opacity((activePageController?.canUndo ?? false) ? 1.0 : 0.4)

            Button(action: { activePageController?.redo() }) {
                Image(systemName: "arrow.uturn.forward")
            }
            .buttonStyle(ToolbarButtonStyle(isActive: false))
            .disabled(!(activePageController?.canRedo ?? false))
            .opacity((activePageController?.canRedo ?? false) ? 1.0 : 0.4)
        }
        .frame(height: 44)
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private var colorButtons: some View {
        HStack(spacing: 12) {
            ForEach(Array(Self.palette.enumerated()), id: \.offset) { _, color in
                let isSelected = currentStrokeColor == color && !isUsingEraser
                Button(action: {
                    currentStrokeColor = color
                    isUsingEraser = false
                    applyToolSettings(useEraser: false, strokeColor: color)
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

            customColorButton
        }
    }

    private var customColorButton: some View {
        let customUIColor = UIColor(customColor)
        let isSelected = currentStrokeColor == customUIColor && !isUsingEraser

        return Button(action: {
            isUsingEraser = false
            applyCustomColorSelection()
            updatePaletteSelection(for: customColor)
            showCustomColorPicker = true
        }) {
            Circle()
                .fill(AngularGradient(gradient: Gradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red]), center: .center))
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(isSelected ? 0.7 : 0.15), lineWidth: 2)
                )
                .frame(width: 26, height: 26)
                .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var thicknessButtons: some View {
        HStack(spacing: 10) {
            ForEach(Self.thicknessOptions, id: \.self) { width in
                let isSelected = abs(currentStrokeWidth - width) < 0.1 && !isUsingEraser
                Button(action: {
                    currentStrokeWidth = width
                    isUsingEraser = false
                    applyToolSettings(useEraser: false, strokeWidth: width)
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

    private var addPagePrompt: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.secondary)

            Text("Scroll for a new page")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if isLoadingNextPage {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var activePageController: CanvasController? {
        guard let id = activePageID else { return pages.first }
        return pages.first(where: { $0.id == id }) ?? pages.first
    }

    private func notebookPage(for controller: CanvasController, pageSize: CGSize, viewportHeight: CGFloat) -> some View {
        PencilCanvasView(controller: controller, pageSize: pageSize)
            .frame(width: pageSize.width, height: pageSize.height)
            .shadow(color: Color.black.opacity(0.08), radius: 18, y: 8)
            .padding(.horizontal, 4)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: PageVisibilityPreferenceKey.self,
                                           value: [controller.id: distanceToCenter(for: proxy, viewportHeight: viewportHeight)])
                }
            )
    }

    private func distanceToCenter(for proxy: GeometryProxy, viewportHeight: CGFloat) -> CGFloat {
        let frame = proxy.frame(in: .named(scrollSpaceName))
        let scrollCenter = viewportHeight / 2
        return abs(frame.midY - scrollCenter)
    }

    private func applyToolSettings(useEraser: Bool? = nil,
                                   strokeColor: UIColor? = nil,
                                   strokeWidth: CGFloat? = nil) {
        for controller in pages {
            if let eraser = useEraser {
                controller.useEraser = eraser
            }
            if let color = strokeColor {
                controller.strokeColor = color
            }
            if let width = strokeWidth {
                controller.strokeWidth = width
            }
        }
    }

    private func applyCustomColorSelection() {
        let color = UIColor(customColor)
        currentStrokeColor = color
        applyToolSettings(useEraser: false, strokeColor: color)
    }

    private func updatePaletteSelection(for color: Color) {
        let uiColor = UIColor(color)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        if uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) {
            paletteSelection = CGPoint(x: CGFloat(hue), y: CGFloat(1 - brightness))
        }
    }

private func requestAdditionalPage() {
        guard !isLoadingNextPage else { return }
        isLoadingNextPage = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let newController = CanvasController(strokeColor: currentStrokeColor,
                                                 strokeWidth: currentStrokeWidth,
                                                 useEraser: isUsingEraser)
            pages.append(newController)
            activePageID = newController.id
            isLoadingNextPage = false
        }
    }
}

private struct CustomColorPopover: View {
    @Binding var customColor: Color
    let suggestions: [Color]
    @Binding var paletteSelection: CGPoint
    let onClose: () -> Void
    let onSelectSuggestion: (Color) -> Void

    var body: some View {
        VStack(spacing: 12) {
            CustomGradientPalette(selection: $customColor, indicatorPoint: $paletteSelection)
                .frame(width: 300, height: 300)

            HStack(spacing: 8) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { _, color in
                    Button(action: {
                        onSelectSuggestion(color)
                    }) {
                        Circle()
                            .fill(color)
                            .frame(width: 30, height: 30)
                            .overlay(
                                Circle().stroke(Color.white.opacity(0.85), lineWidth: 2)
                            )
                            .shadow(color: Color.black.opacity(0.18), radius: 2, x: 0, y: 1)
                    }
                }
            }

            Button("Done") {
                onClose()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .frame(width: 320)
    }
}

private struct CustomGradientPalette: View {
    @Binding var selection: Color
    @Binding var indicatorPoint: CGPoint
    @GestureState private var dragLocation: CGPoint? = nil

    var body: some View {
        GeometryReader { geo in
            paletteBody(in: geo)
        }
        .aspectRatio(1.6, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 6)
    }

    private func paletteBody(in geo: GeometryProxy) -> some View {
        let drag = DragGesture(minimumDistance: 0)
            .updating($dragLocation) { value, state, _ in
                state = value.location
            }
            .onChanged { value in
                updateSelection(at: value.location, in: geo)
            }
            .onEnded { value in
                updateSelection(at: value.location, in: geo)
            }

        return ZStack(alignment: .topLeading) {
            LinearGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], startPoint: .leading, endPoint: .trailing)
                .overlay(
                    LinearGradient(colors: [.white.opacity(0.05), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                )
                .gesture(drag)

            Circle()
                .strokeBorder(Color.white, lineWidth: 2)
                .background(Circle().fill(selection))
                .frame(width: 26, height: 26)
                .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 2)
                .position(x: indicatorPoint.x * geo.size.width,
                          y: indicatorPoint.y * geo.size.height)
        }
    }

    private func updateSelection(at point: CGPoint, in geo: GeometryProxy) {
        let x = max(0, min(point.x, geo.size.width))
        let y = max(0, min(point.y, geo.size.height))

        indicatorPoint = CGPoint(x: x / geo.size.width, y: y / geo.size.height)

        let hue = Double(indicatorPoint.x)
        let brightness = Double(1 - indicatorPoint.y)
        selection = Color(hue: hue, saturation: 1.0, brightness: brightness)
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
