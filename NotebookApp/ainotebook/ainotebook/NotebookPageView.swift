import SwiftUI
import PencilKit

private struct PageVisibilityPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]

    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

struct NotebookPageView: View {
    @ObservedObject var pageStore: NotebookPageStore
    var paperStyle: PaperStyle
    private static let palette: [UIColor] = [
        UIColor(red: 0.12, green: 0.26, blue: 0.52, alpha: 1.0),
        UIColor(red: 0.16, green: 0.48, blue: 0.32, alpha: 1.0),
        UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0),
        UIColor(red: 0.72, green: 0.20, blue: 0.18, alpha: 1.0)
    ]

    private static let thicknessOptions: [CGFloat] = [2.2, 3.2, 4.2]
    private let scrollSpaceName = "NotebookScroll"
    private let defaultPageSize = CGSize(width: 800, height: 1000)

    @State private var isLoadingNextPage = false
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
    @State private var showPageIndicator = false
    @State private var pageIndicatorWorkItem: DispatchWorkItem?
    @State private var scrollProxy: ScrollViewProxy?
    @State private var isProgrammaticJump = false

    init(paperStyle: PaperStyle = .grid, pageStore: NotebookPageStore) {
        self.paperStyle = paperStyle
        self._pageStore = ObservedObject(wrappedValue: pageStore)
        let defaultColor = Self.palette[0]
        let defaultWidth = Self.thicknessOptions[1]
        _currentStrokeColor = State(initialValue: defaultColor)
        _currentStrokeWidth = State(initialValue: defaultWidth)
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

                    ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 40) {
                                ForEach(pageStore.pageModels, id: \.id) { model in
                                    if let controller = pageStore.controller(for: model) {
                                        notebookPage(for: controller,
                                                     pageSize: pageSize,
                                                     viewportHeight: viewportHeight)
                                        .frame(maxWidth: .infinity)
                                        .id(model.id)
                                    }
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
                        .onAppear {
                            scrollProxy = proxy
                        }
                    }
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .onPreferenceChange(PageVisibilityPreferenceKey.self) { values in
                    guard let closest = values.min(by: { $0.value < $1.value }) else { return }
                    guard !isProgrammaticJump else { return }
                    if pageStore.activePageID != closest.key {
                        pageStore.activePageID = closest.key
                        showPageIndicatorTemporary()
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
        .overlay(alignment: .bottomTrailing) {
            if showPageIndicator, let indicatorText = pageIndicatorText {
                Text(indicatorText)
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .padding(18)
                    .transition(.opacity)
            }
        }
        .onChange(of: customColor) { _ in
            applyCustomColorSelection()
        }
        .onChange(of: pageStore.activePageID) { id in
            guard let id = id else { return }
            isProgrammaticJump = true
            withAnimation {
                scrollProxy?.scrollTo(id, anchor: .top)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isProgrammaticJump = false
            }
            showPageIndicatorTemporary()
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
        pageStore.controller(for: pageStore.activePageID)
    }

    private var pageIndicatorText: String? {
        guard let activeID = pageStore.activePageID,
              let index = pageStore.pageModels.firstIndex(where: { $0.id == activeID }) else { return nil }
        return "Page \(index + 1) of \(pageStore.pageModels.count)"
    }

    private func notebookPage(for controller: CanvasController, pageSize: CGSize, viewportHeight: CGFloat) -> some View {
        PencilCanvasView(controller: controller, pageSize: pageSize, paperStyle: paperStyle)
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

    private func showPageIndicatorTemporary() {
        showPageIndicator = true
        pageIndicatorWorkItem?.cancel()
        let workItem = DispatchWorkItem { showPageIndicator = false }
        pageIndicatorWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: workItem)
    }

    private func distanceToCenter(for proxy: GeometryProxy, viewportHeight: CGFloat) -> CGFloat {
        let frame = proxy.frame(in: .named(scrollSpaceName))
        let scrollCenter = viewportHeight / 2
        return abs(frame.midY - scrollCenter)
    }

    private func applyToolSettings(useEraser: Bool? = nil,
                                   strokeColor: UIColor? = nil,
                                   strokeWidth: CGFloat? = nil) {
        for controller in pageStore.controllersInOrder {
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
            let model = NotebookPageModel(title: "Page \(pageStore.pageModels.count + 1)", paperStyle: paperStyle)
            let newController = CanvasController(id: model.id,
                                                 strokeColor: currentStrokeColor,
                                                 strokeWidth: currentStrokeWidth,
                                                 useEraser: isUsingEraser)
            pageStore.insertPage(model, controller: newController)
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
                .frame(width: 280, height: 280)

            HStack(spacing: 6) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { _, color in
                    Button(action: {
                        onSelectSuggestion(color)
                    }) {
                        Circle()
                            .fill(color)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle().stroke(Color.white.opacity(0.85), lineWidth: 2)
                            )
                            .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
                    }
                }
            }

            Button("Done") {
                onClose()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .frame(width: 300)
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

private struct PaperBackground: View {
    var style: PaperStyle

    var body: some View {
        switch style {
        case .grid:
            GridPaperBackground()
        case .dot:
            DotPaperBackground()
        case .blank:
            Color(red: 0.97, green: 0.96, blue: 0.92)
        case .lined:
            LinedPaperBackground()
        }
    }
}

private struct DotPaperBackground: View {
    private let spacing: CGFloat = 28
    private let dotColor = Color.black.opacity(0.12)

    var body: some View {
        GeometryReader { geometry in
            Color(red: 0.97, green: 0.96, blue: 0.92)
                .overlay(
                    Canvas { context, size in
                        let dotSize: CGFloat = 2
                        var path = Path()
                        stride(from: 0, through: size.width, by: spacing).forEach { x in
                            stride(from: 0, through: size.height, by: spacing).forEach { y in
                                let rect = CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize)
                                path.addEllipse(in: rect)
                            }
                        }
                        context.fill(path, with: .color(dotColor))
                    }
                )
        }
    }
}

private struct LinedPaperBackground: View {
    private let spacing: CGFloat = 32
    private let lineColor = Color(red: 0.63, green: 0.7, blue: 0.86).opacity(0.5)

    var body: some View {
        GeometryReader { geometry in
            Color(red: 0.97, green: 0.96, blue: 0.92)
                .overlay(
                    Canvas { context, size in
                        var path = Path()
                        stride(from: 0, through: size.height, by: spacing).forEach { y in
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                        }
                        context.stroke(path, with: .color(lineColor), lineWidth: 1)
                    }
                )
        }
    }
}

private struct GridPaperBackground: View {
    private let spacing: CGFloat = 28
    private let gridColor = Color(red: 0.78, green: 0.78, blue: 0.72).opacity(0.5)

    var body: some View {
        GeometryReader { geometry in
            Color(red: 0.97, green: 0.96, blue: 0.92)
                .overlay(
                    Canvas { context, size in
                        var path = Path()

                        stride(from: 0, through: size.width, by: spacing).forEach { x in
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: size.height))
                        }

                        stride(from: 0, through: size.height, by: spacing).forEach { y in
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                        }

                        context.stroke(path, with: .color(gridColor), lineWidth: 0.7)
                    }
                )
        }
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
        NotebookPageView(pageStore: NotebookPageStore(models: [NotebookPageModel(title: "Page 1")]))
            .previewInterfaceOrientation(.landscapeLeft)
            .previewDevice("iPad (10th generation)")
    }
}
