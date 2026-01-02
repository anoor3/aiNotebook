import SwiftUI
import PencilKit
import UIKit
import UniformTypeIdentifiers

private struct PageVisibilityPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]

    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

struct NotebookPageView: View {
    @Binding var notebook: Notebook
    @ObservedObject var pageStore: NotebookPageStore
    var paperStyle: PaperStyle
    private let coverPageID = UUID()
    private static let penPalette: [UIColor] = [
        UIColor(red: 0.12, green: 0.26, blue: 0.52, alpha: 1.0),
        UIColor(red: 0.16, green: 0.48, blue: 0.32, alpha: 1.0),
        UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0),
        UIColor(red: 0.72, green: 0.20, blue: 0.18, alpha: 1.0)
    ]

    private static let highlighterPalette: [UIColor] = [
        UIColor(red: 1.00, green: 0.93, blue: 0.48, alpha: 1.0),
        UIColor(red: 1.00, green: 0.82, blue: 0.38, alpha: 1.0),
        UIColor(red: 0.98, green: 0.66, blue: 0.66, alpha: 1.0),
        UIColor(red: 0.68, green: 0.88, blue: 0.53, alpha: 1.0),
        UIColor(red: 0.58, green: 0.78, blue: 0.96, alpha: 1.0)
    ]

    private static let thicknessOptions: [CGFloat] = [0.7, 3.0, 6.0]
    private let scrollSpaceName = "NotebookScroll"
    private let basePageSize = CGSize(width: 800, height: 1000)

    @State private var isLoadingNextPage = false
    @State private var currentStrokeColor: UIColor
    @State private var penStrokeColor: UIColor
    @State private var highlighterStrokeColor: UIColor
    @State private var currentStrokeWidth: CGFloat
    @State private var currentTool: CanvasDrawingTool = .pen
    @State private var lastDrawingTool: CanvasDrawingTool = .pen
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
    @State private var isCoverActive = false
    @State private var didApplyInitialPage = false
    @State private var showImageOptions = false
    @State private var imagePickerSource: ImagePickerSource?
    @State private var pendingImagePageID: UUID?
    @State private var showAIChat = false
    @State private var aiMessages: [AIChatMessage] = AIChatMessage.seedConversation
    @State private var aiQueryMode: AIQueryMode = .text
    @State private var aiPanelDragOffset: CGFloat = 0
    /// Holds the currently editable image so PencilKit interaction can be paused while the finger manipulates it.
    @State private var editingAttachmentContext: EditingAttachmentContext?
    @State private var showExportSheet = false
    @State private var exportSelection: Set<UUID> = []
    @State private var exportFormat: NotebookExportFormat = .pdf
    @State private var isExportingSelection = false
    @State private var exportErrorMessage: String?
    @State private var shareURLs: [URL] = []
    @State private var isPresentingShareSheet = false

    init(paperStyle: PaperStyle = .grid, pageStore: NotebookPageStore, notebook: Binding<Notebook>) {
        self.paperStyle = paperStyle
        self._pageStore = ObservedObject(wrappedValue: pageStore)
        self._notebook = notebook
        let defaultColor = Self.penPalette[0]
        let defaultHighlighter = Self.highlighterPalette[0]
        let defaultWidth = Self.thicknessOptions[1]
        _currentStrokeColor = State(initialValue: defaultColor)
        _penStrokeColor = State(initialValue: defaultColor)
        _highlighterStrokeColor = State(initialValue: defaultHighlighter)
        _currentStrokeWidth = State(initialValue: defaultWidth)
    }

    var body: some View {
        GeometryReader { geometry in
            let pageSize = basePageSize
            let pageScale = pageScale(for: geometry.size.width)
            let scaledSize = CGSize(width: pageSize.width * pageScale,
                                    height: pageSize.height * pageScale)
            let scaledHeight = scaledSize.height
            let viewportHeight = max(min(scaledHeight + 60, geometry.size.height - 80), 420)

            ZStack(alignment: .top) {
                Color(red: 0.97, green: 0.96, blue: 0.92)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    toolbar
                        .padding(.top, 12)

                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 40) {
                                dropTarget(pageID: coverPageID, viewSize: scaledSize) {
                                    coverPage(pageSize: pageSize, viewportHeight: viewportHeight)
                                        .scaleEffect(pageScale, anchor: .center)
                                        .frame(width: scaledSize.width,
                                               height: scaledSize.height)
                                }
                                    .id(coverPageID)

                                ForEach(pageStore.pages, id: \.id) { controller in
                                    dropTarget(pageID: controller.id, viewSize: scaledSize) {
                                        notebookPage(for: controller,
                                                     pageSize: pageSize,
                                                         viewportHeight: viewportHeight)
                                            .scaleEffect(pageScale, anchor: .center)
                                            .frame(width: scaledSize.width,
                                                   height: scaledSize.height)
                                    }
                                        .frame(maxWidth: .infinity)
                                        .id(controller.id)
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
                    if closest.key == coverPageID {
                        if !isCoverActive {
                            isCoverActive = true
                            showPageIndicatorTemporary()
                        }
                        return
                    }

                    if isCoverActive {
                        isCoverActive = false
                    }

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
        .overlay(alignment: .leading) {
            if showAIChat {
                let panelWidth = min(520, UIScreen.main.bounds.width * 0.5)
                AIChatSheet(messages: $aiMessages,
                            queryMode: $aiQueryMode,
                            onClose: { showAIChat = false })
                    .frame(width: panelWidth)
                    .frame(maxHeight: .infinity)
                    .padding(.top, 80)
                    .padding(.bottom, 8)
                    .offset(x: aiPanelDragOffset)
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { value in
                                aiPanelDragOffset = min(0, value.translation.width)
                            }
                            .onEnded { value in
                                if value.translation.width < -panelWidth * 0.25 {
                                    showAIChat = false
                                }
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                    aiPanelDragOffset = 0
                                }
                            }
                    )
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: showAIChat)
        .onChange(of: showAIChat) { isVisible in
            if !isVisible {
                aiPanelDragOffset = 0
            }
        }
        .onChange(of: customColor) { _ in
            applyCustomColorSelection()
        }
        .onChange(of: pageStore.activePageID) { id in
            guard let id = id else { return }
            if let index = pageStore.pages.firstIndex(where: { $0.id == id }) {
                notebook.currentPageIndex = index
                SessionStatePersistence.save(notebookID: notebook.id, pageIndex: index)
            }
            isProgrammaticJump = true
            withAnimation {
                scrollProxy?.scrollTo(id, anchor: .top)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isProgrammaticJump = false
            }
            showPageIndicatorTemporary()
        }
        .onAppear {
            ensureInitialPageSelection()
        }
        .sheet(isPresented: $showExportSheet) {
            PageExportSheet(pages: pageStore.pageModels,
                            selectedPageIDs: $exportSelection,
                            format: $exportFormat,
                            isExporting: isExportingSelection,
                            errorMessage: exportErrorMessage,
                            onSelectAll: {
                                exportSelection = Set(pageStore.pageModels.map { $0.id })
                            },
                            onClearSelection: {
                                exportSelection.removeAll()
                            },
                            onExport: startExport)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isPresentingShareSheet, onDismiss: cleanupShareFiles) {
            ShareSheet(activityItems: shareURLs)
        }
        .sheet(isPresented: $showImageOptions) {
            ImageInsertOptionsSheet(canUseCamera: ImagePickerSource.camera.isAvailable,
                                    onSelect: { source in
                                        presentPicker(for: source)
                                    },
                                    onCancel: {
                                        cancelImageInsertion()
                                    })
            .presentationDetents([.medium])
        }
        .sheet(item: $imagePickerSource) { source in
            CroppingImagePicker(sourceType: source.uiKitSource) { image in
                handleImageSelection(image)
            } onCancel: {
                cancelImageInsertion()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .notebookRequestExport)) { _ in
            presentExportOptions()
        }
    }

    /// Compact toolbar styled like native iPadOS tools.
    private var toolbar: some View {
        HStack(spacing: 18) {
            toolButton(systemName: "pencil.tip", isActive: currentTool == .pen) {
                selectTool(.pen)
            }

            toolButton(isActive: currentTool == .highlighter, action: { selectTool(.highlighter) }) {
                HighlighterIcon(isActive: currentTool == .highlighter)
            }

            toolButton(systemName: "eraser", isActive: currentTool == .eraser) {
                selectTool(.eraser)
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

            Button(action: presentImageOptions) {
                Image(systemName: "photo.on.rectangle")
            }
            .buttonStyle(ToolbarButtonStyle(isActive: false))

            Button(action: { showAIChat = true }) {
                AISparkleGlyph()
            }
            .buttonStyle(ToolbarButtonStyle(isActive: false))
        }
        .frame(height: 44)
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private var colorButtons: some View {
        let palette = palette(for: displayedDrawingTool)

        return HStack(spacing: 12) {
            ForEach(Array(palette.enumerated()), id: \.offset) { (_, color) in
                let isSelected = currentStrokeColor == color && displayedDrawingTool != .eraser
                Button(action: {
                    let targetTool = displayedDrawingTool
                    currentStrokeColor = color
                    storeColor(color, for: targetTool)
                    currentTool = targetTool
                    lastDrawingTool = targetTool
                    applyToolSettings(tool: targetTool, strokeColor: color)
                }) {
                    Circle()
                        .fill(Color(color))
                        .frame(width: 22, height: 22)
                        .background(
                            Circle()
                                .fill(Color.accentColor.opacity(isSelected ? 0.18 : 0))
                                .blur(radius: isSelected ? 2 : 0)
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(isSelected ? 0.85 : 0), lineWidth: isSelected ? 1.4 : 0)
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.accentColor.opacity(isSelected ? 0.7 : 0), lineWidth: isSelected ? 2.5 : 0)
                                .scaleEffect(isSelected ? 1.2 : 1.0)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }

            customColorButton
        }
    }

    private var customColorButton: some View {
        let customUIColor = UIColor(customColor)
        let activeTool = displayedDrawingTool
        let isSelected = currentStrokeColor == customUIColor && activeTool != .eraser

        return Button(action: {
            let targetTool = activeTool
            applyCustomColorSelection(for: targetTool)
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
                let isSelected = abs(currentStrokeWidth - width) < 0.1 && currentTool != .eraser
                Button(action: {
                    let targetTool = currentTool == .eraser ? lastDrawingTool : currentTool
                    currentStrokeWidth = width
                    currentTool = targetTool
                    lastDrawingTool = targetTool
                    applyToolSettings(tool: targetTool, strokeWidth: width)
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

    private var displayedDrawingTool: CanvasDrawingTool {
        currentTool == .eraser ? lastDrawingTool : currentTool
    }

    private func toolButton<Content: View>(isActive: Bool,
                                           action: @escaping () -> Void,
                                           @ViewBuilder label: () -> Content) -> some View {
        Button(action: action) {
            label()
        }
        .buttonStyle(ToolbarButtonStyle(isActive: isActive))
    }

    private func toolButton(systemName: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        toolButton(isActive: isActive, action: action) {
            Image(systemName: systemName)
                .symbolVariant(isActive ? .fill : .none)
        }
    }

    private func selectTool(_ tool: CanvasDrawingTool) {
        currentTool = tool
        if tool != .eraser {
            lastDrawingTool = tool
        }
        if tool.isDrawingTool {
            let color = lastColor(for: tool)
            currentStrokeColor = color
            applyToolSettings(tool: tool, strokeColor: color)
        } else {
            applyToolSettings(tool: tool)
        }
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
        guard let id = pageStore.activePageID else { return pageStore.pages.first }
        return pageStore.pages.first(where: { $0.id == id }) ?? pageStore.pages.first
    }

    private var pageIndicatorText: String? {
        if isCoverActive { return "Cover" }
        guard let activeID = pageStore.activePageID,
              let index = pageStore.pages.firstIndex(where: { $0.id == activeID }) else { return nil }
        return "Page \(index + 1) of \(pageStore.pages.count)"
    }

    private func coverPage(pageSize: CGSize, viewportHeight: CGFloat) -> some View {
        NotebookCoverPage(notebook: $notebook)
            .frame(width: pageSize.width, height: pageSize.height)
            .shadow(color: Color.black.opacity(0.08), radius: 18, y: 8)
            .padding(.horizontal, 4)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: PageVisibilityPreferenceKey.self,
                                           value: [coverPageID: distanceToCenter(for: proxy, viewportHeight: viewportHeight)])
                }
            )
    }

    private func notebookPage(for controller: CanvasController, pageSize: CGSize, viewportHeight: CGFloat) -> some View {
        let pageID = controller.id
        let isEditingThisPage = editingAttachmentContext?.pageID == pageID
        let editingID = isEditingThisPage ? editingAttachmentContext?.attachmentID : nil

        return ZStack(alignment: .topTrailing) {
            // PencilCanvasView keeps all PencilKit logic untouched while the attachment overlay lives inside the UIKit host.
            PencilCanvasView(controller: controller,
                             pageSize: pageSize,
                             paperStyle: paperStyle,
                             attachments: canvasAttachments(for: pageID),
                             editingAttachmentID: editingID,
                             disableCanvasInteraction: isEditingThisPage,
                             onAttachmentChanged: { updated in
                                 handleAttachmentUpdate(updated, for: pageID)
                             },
                             onAttachmentTapOutside: {
                                 handleTapOutsideEditing(for: pageID)
                             })

            if isEditingThisPage {
                Button("Done") {
                    finalizeImageEditing()
                }
                .buttonStyle(.borderedProminent)
                .padding(16)
            }
        }
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

    private func palette(for tool: CanvasDrawingTool) -> [UIColor] {
        switch tool {
        case .highlighter:
            return Self.highlighterPalette
        default:
            return Self.penPalette
        }
    }

    private func lastColor(for tool: CanvasDrawingTool) -> UIColor {
        switch tool {
        case .pen:
            return penStrokeColor
        case .highlighter:
            return highlighterStrokeColor
        case .eraser:
            return penStrokeColor
        }
    }

    private func storeColor(_ color: UIColor, for tool: CanvasDrawingTool) {
        switch tool {
        case .pen:
            penStrokeColor = color
        case .highlighter:
            highlighterStrokeColor = color
        case .eraser:
            break
        }
    }

    private func applyToolSettings(tool: CanvasDrawingTool? = nil,
                                   strokeColor: UIColor? = nil,
                                   strokeWidth: CGFloat? = nil) {
        for controller in pageStore.pages {
            if let tool {
                controller.tool = tool
            }
            if let color = strokeColor {
                controller.strokeColor = color
            }
            if let width = strokeWidth {
                controller.strokeWidth = width
            }
        }
    }

    private func applyCustomColorSelection(for toolOverride: CanvasDrawingTool? = nil) {
        let color = UIColor(customColor)
        currentStrokeColor = color
        let targetTool = toolOverride ?? displayedDrawingTool
        currentTool = targetTool
        lastDrawingTool = targetTool
        storeColor(color, for: targetTool)
        applyToolSettings(tool: targetTool, strokeColor: color)
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
            _ = pageStore.addPage(title: "Page \(pageStore.pages.count + 1)",
                                  paperStyle: paperStyle,
                                  strokeColor: currentStrokeColor,
                                  strokeWidth: currentStrokeWidth,
                                  tool: currentTool)
            isLoadingNextPage = false
        }
    }

    private func pageScale(for availableWidth: CGFloat) -> CGFloat {
        let horizontalPadding: CGFloat = 96
        let usableWidth = max(availableWidth - horizontalPadding, basePageSize.width)
        let scale = usableWidth / basePageSize.width
        return min(max(scale, 1.0), 1.25)
    }

    @ViewBuilder
    private func dropTarget<Content: View>(pageID: UUID,
                                           viewSize: CGSize,
                                           @ViewBuilder content: () -> Content) -> some View {
        content()
            .contentShape(Rectangle())
            .onDrop(of: [.image, .fileURL, .url], isTargeted: nil) { providers, location in
                handleDropProviders(providers,
                                    location: location,
                                    pageID: pageID,
                                    viewSize: viewSize)
                return providers.contains { supportedProvider($0) }
            }
    }

    private func handleDropProviders(_ providers: [NSItemProvider],
                                     location: CGPoint,
                                     pageID: UUID,
                                     viewSize: CGSize) {
        var handled = false
        for provider in providers {
            if provider.canLoadObject(ofClass: UIImage.self) {
                handled = true
                loadImage(from: provider, location: location, pageID: pageID, viewSize: viewSize)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url = (item as? URL)
                        ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                    guard let url else { return }
                    loadImage(fromFileURL: url) { image in
                        if let image {
                            insertDroppedImage(image, at: location, pageID: pageID, viewSize: viewSize)
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                    let url = (item as? URL)
                        ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                    guard let url,
                          let scheme = url.scheme?.lowercased(),
                          scheme == "http" || scheme == "https" else { return }
                    loadRemoteImage(from: url,
                                    location: location,
                                    pageID: pageID,
                                    viewSize: viewSize)
                }
            }
        }
        if !handled {
            feedbackForUnsupportedDrop()
        }
    }

    private func supportedProvider(_ provider: NSItemProvider) -> Bool {
        provider.canLoadObject(ofClass: UIImage.self)
        || provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        || provider.hasItemConformingToTypeIdentifier(UTType.url.identifier)
    }

    private func presentImageOptions() {
        pendingImagePageID = activePageController?.id ?? pageStore.pages.first?.id
        showImageOptions = pendingImagePageID != nil
    }

    private func presentExportOptions() {
        exportSelection = Set(pageStore.pageModels.map { $0.id })
        exportFormat = .pdf
        exportErrorMessage = nil
        showExportSheet = true
    }

    private func presentPicker(for source: ImagePickerSource) {
        guard source.isAvailable else { return }
        if pendingImagePageID == nil {
            pendingImagePageID = activePageController?.id ?? pageStore.pages.first?.id
        }
        guard pendingImagePageID != nil else {
            cancelImageInsertion()
            return
        }
        imagePickerSource = source
        showImageOptions = false
    }

    private func handleImageSelection(_ image: UIImage) {
        guard let pageID = pendingImagePageID ?? activePageController?.id ?? pageStore.pages.first?.id else {
            cancelImageInsertion()
            return
        }
        pendingImagePageID = nil

        guard let data = image.pngData() ?? image.jpegData(compressionQuality: 0.9) else {
            cancelImageInsertion()
            return
        }
        let size = defaultImageSize(for: image)
        let center = CGPoint(x: basePageSize.width / 2, y: basePageSize.height / 2)
        let attachment = NotebookPageImage(imageData: data,
                                           center: center,
                                           size: size,
                                           rotation: 0)
        pageStore.addImage(attachment, to: pageID)
        editingAttachmentContext = EditingAttachmentContext(pageID: pageID, attachmentID: attachment.id)
        imagePickerSource = nil
    }

    private func defaultImageSize(for image: UIImage) -> CGSize {
        let maxWidth = basePageSize.width * 0.65
        let maxHeight = basePageSize.height * 0.65
        let minWidth: CGFloat = 220
        let aspect = image.size.height / max(image.size.width, 1)

        var width = max(minWidth, min(maxWidth, image.size.width))
        var height = width * aspect

        if height > maxHeight {
            height = maxHeight
            width = height / max(aspect, 0.01)
        }

        return CGSize(width: width, height: height)
    }

    private func canvasAttachments(for pageID: UUID) -> [CanvasAttachment] {
        pageStore.images(for: pageID).compactMap { model in
            CanvasAttachment(id: model.id,
                             imageData: model.imageData,
                             center: model.center,
                             size: model.size,
                             rotation: CGFloat(model.rotation))
        }
    }

    private func handleAttachmentUpdate(_ attachment: CanvasAttachment, for pageID: UUID) {
        pageStore.updateImageTransform(pageID: pageID,
                                       imageID: attachment.id,
                                       center: attachment.center,
                                       size: attachment.size,
                                       rotation: Double(attachment.rotation))
    }

    /// Called when the overlay detects a background tap so the dragged image becomes fixed and PencilKit resumes drawing.
    private func handleTapOutsideEditing(for pageID: UUID) {
        guard editingAttachmentContext?.pageID == pageID else { return }
        finalizeImageEditing()
    }

    /// Ends editing mode so the image becomes part of the page content and finger gestures return to scrolling/drawing.
    private func finalizeImageEditing() {
        editingAttachmentContext = nil
    }

    private func cancelImageInsertion() {
        pendingImagePageID = nil
        imagePickerSource = nil
        showImageOptions = false
    }

    private func startExport() {
        guard !isExportingSelection else { return }
        let payloads = exportPayloads()
        guard !payloads.isEmpty else {
            exportErrorMessage = "Select at least one page."
            return
        }

        let notebookTitle = notebook.title
        isExportingSelection = true
        exportErrorMessage = nil

        Task {
            do {
                let urls = try await Task.detached(priority: .userInitiated) {
                    try NotebookExportService.export(pages: payloads,
                                                     format: exportFormat,
                                                     notebookTitle: notebookTitle,
                                                     pageSize: basePageSize)
                }.value

                await MainActor.run {
                    shareURLs = urls
                    isExportingSelection = false
                    showExportSheet = false
                    isPresentingShareSheet = true
                }
            } catch {
                await MainActor.run {
                    exportErrorMessage = error.localizedDescription
                    isExportingSelection = false
                }
            }
        }
    }

    private func cleanupShareFiles() {
        for url in shareURLs {
            try? FileManager.default.removeItem(at: url)
        }
        shareURLs.removeAll()
    }

    private func exportPayloads() -> [NotebookExportPagePayload] {
        var payloads: [NotebookExportPagePayload] = []
        for (index, page) in pageStore.pageModels.enumerated() {
            guard exportSelection.contains(page.id),
                  let controller = pageStore.controller(for: page.id) else {
                continue
            }
            let drawing = controller.canvasView.drawing
            let drawingData = DrawingPersistence.encode(drawing)
            let attachments = pageStore.images(for: page.id)
            let payload = NotebookExportPagePayload(id: page.id,
                                                    title: page.title,
                                                    pageNumber: index + 1,
                                                    paperStyle: page.paperStyle,
                                                    drawingData: drawingData,
                                                    attachments: attachments)
            payloads.append(payload)
        }
        return payloads
    }
}

extension NotebookPageView {
    private func ensureInitialPageSelection() {
        guard !didApplyInitialPage else { return }
        didApplyInitialPage = true
        guard !pageStore.pages.isEmpty else { return }
        let targetIndex = max(0, min(notebook.currentPageIndex, pageStore.pages.count - 1))
        guard pageStore.pages.indices.contains(targetIndex) else { return }
        let controller = pageStore.pages[targetIndex]
        DispatchQueue.main.async {
            pageStore.activePageID = controller.id
        }
    }
}

private struct EditingAttachmentContext: Identifiable {
    let pageID: UUID
    let attachmentID: UUID

    var id: UUID { attachmentID }
}

private enum AIQueryMode: String, CaseIterable, Identifiable {
    case text
    case selection
    case image

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: return "Text Prompt"
        case .selection: return "Select Area"
        case .image: return "Upload Image"
        }
    }

    var subtitle: String {
        switch self {
        case .text:
            return "Describe what you need help with."
        case .selection:
            return "Highlight part of the page to ask about it."
        case .image:
            return "Share a reference photo or diagram."
        }
    }
}

struct AIChatMessage: Identifiable, Hashable {
    enum Role {
        case user, assistant
    }

    let id: UUID
    var role: Role
    var text: String
    var timestamp: Date

    init(id: UUID = UUID(), role: Role, text: String, timestamp: Date = .now) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }

    static var seedConversation: [AIChatMessage] {
        [
            AIChatMessage(role: .assistant,
                          text: "Hi! I'm your notebook assistant. Ask anything about your notes or attach a reference image.")
        ]
    }
}

private struct AIChatSheet: View {
    @Binding var messages: [AIChatMessage]
    @Binding var queryMode: AIQueryMode
    var onClose: () -> Void

    @State private var draftMessage: String = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            header

            VStack(alignment: .leading, spacing: 8) {
                Picker("Query Mode", selection: $queryMode) {
                    ForEach(AIQueryMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if messages.count <= 1 {
                    Text(queryMode.subtitle)
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    modeAccessory
                }
            }

            chatStream
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            inputField
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Notebook AI")
                    .font(.title2.weight(.bold))
                Text("Ask questions about this page or attach context")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: {
                onClose()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var modeAccessory: some View {
        switch queryMode {
        case .text:
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
                .overlay(
                    HStack {
                        Image(systemName: "pencil.and.outline")
                            .foregroundColor(.accentColor)
                        Text("Use natural language to describe ideas, questions, or todo items.")
                            .font(.callout)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding()
                )
                .frame(maxWidth: .infinity)
        case .selection:
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundColor(.accentColor)
                .overlay(
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Coming soon: drag a box around strokes to ask about that region.", systemImage: "lasso.sparkles")
                            .foregroundColor(.accentColor)
                        Text("For now, describe the area you want feedback on in the text box below.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                )
        case .image:
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.tertiarySystemFill))
                .overlay(
                    VStack(spacing: 10) {
                        Image(systemName: "photo.badge.plus")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        Text("Image uploads will be available soon. Mention the picture you want me to analyze in your prompt.")
                            .multilineTextAlignment(.center)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                )
        }
    }

    private var chatStream: some View {
        Group {
            if messages.count <= 1 {
                VStack(spacing: 16) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 34))
                        .foregroundColor(.accentColor.opacity(0.75))
                    Text("Use natural language to describe ideas, questions, or TODOs.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(messages) { message in
                                AIChatBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 10)
                    }
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        DispatchQueue.main.async {
                            if let last = messages.last?.id {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: messages) { _ in
                        withAnimation(.easeOut(duration: 0.25)) {
                            if let last = messages.last?.id {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
    }

    private var inputField: some View {
        HStack(spacing: 12) {
            TextField("Ask something...", text: $draftMessage, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                .disabled(isSending)

            Button(action: sendMessage) {
                if isSending {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .padding(10)
                        .background(Capsule().fill(Color.accentColor))
                } else {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Capsule().fill(draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.accentColor))
                }
            }
            .disabled(draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
        }
    }

    private func sendMessage() {
        let trimmed = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(AIChatMessage(role: .user, text: trimmed))
        draftMessage = ""
        errorMessage = nil
        isSending = true

        Task {
            do {
                let reply = try await OpenRouterChatService.send(messages: messages)
                await MainActor.run {
                    messages.append(AIChatMessage(role: .assistant, text: reply))
                    isSending = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSending = false
                }
            }
        }
    }
}

private struct AIChatBubble: View {
    let message: AIChatMessage

    var body: some View {
        HStack {
            if message.role == .assistant {
                bubble
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                bubble
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message.text)
                .font(.body)
                .foregroundColor(message.role == .assistant ? .primary : .white)
            Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(message.role == .assistant ? Color(.secondarySystemBackground) : Color.accentColor)
        )
    }
}

/// Stylized marker glyph used for the highlighter toggle.
private struct HighlighterIcon: View {
    var isActive: Bool

    private var baseColor: Color {
        isActive ? Color.primary : Color.primary.opacity(0.7)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(baseColor)
                .frame(width: 28, height: 12)
                .offset(y: -4)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.primary.opacity(0.25), lineWidth: 1)
                        .offset(y: -4)
                )

            MarkerNibShape()
                .fill(baseColor)
                .frame(width: 28, height: 14)
                .shadow(color: Color.primary.opacity(0.15), radius: 2, x: 0, y: 1)

            Capsule()
                .fill(Color.white.opacity(isActive ? 0.35 : 0.18))
                .frame(width: 16, height: 4)
                .offset(x: -4, y: -10)

            Capsule()
                .fill(Color.white.opacity(isActive ? 0.4 : 0.2))
                .frame(width: 10, height: 3)
                .offset(x: 5, y: -12)
        }
        .frame(width: 30, height: 26)
        .rotationEffect(.degrees(-6))
    }
}

private struct MarkerNibShape: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.width * 0.18
        return Path { path in
            path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
        }
    }
}

/// Shiny "AI" badge used on the toolbar.
private struct AISparkleGlyph: View {
    var body: some View {
        Text("AI")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.95))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    .shadow(color: Color.accentColor.opacity(0.6), radius: 4)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(LinearGradient(colors: [Color.accentColor.opacity(0.7), .clear, Color.accentColor.opacity(0.7)],
                                            startPoint: .leading,
                                            endPoint: .trailing),
                            lineWidth: 3)
                    .blur(radius: 1.2)
                    .opacity(0.6)
            )
            .shadow(color: Color.accentColor.opacity(0.45), radius: 6, x: 0, y: 2)
    }
}

private struct ImageInsertOptionsSheet: View {
    let canUseCamera: Bool
    let onSelect: (ImagePickerSource) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("Insert Image")
                    .font(.title3.weight(.semibold))

                VStack(spacing: 16) {
                    Button {
                        onSelect(.photoLibrary)
                    } label: {
                        HStack {
                            Label("Choose from Photos", systemImage: "photo")
                            Spacer()
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(.secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        onSelect(.camera)
                    } label: {
                        HStack {
                            Label("Take Photo", systemImage: "camera")
                            Spacer()
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(canUseCamera ? Color(.secondarySystemBackground) : Color(.systemGray5)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canUseCamera)
                }

                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .padding(.top, 8)
            }
            .padding(24)
            .navigationBarHidden(true)
        }
    }
}

private struct PageExportSheet: View {
    let pages: [NotebookPageModel]
    @Binding var selectedPageIDs: Set<UUID>
    @Binding var format: NotebookExportFormat
    let isExporting: Bool
    let errorMessage: String?
    let onSelectAll: () -> Void
    let onClearSelection: () -> Void
    let onExport: () -> Void

    private var selectedCount: Int { selectedPageIDs.count }

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Picker("Format", selection: $format) {
                    ForEach(NotebookExportFormat.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Text(format.description)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Button("Select All", action: onSelectAll)
                    Spacer()
                    Button("Clear", action: onClearSelection)
                        .disabled(selectedPageIDs.isEmpty)
                }

                HStack {
                    Text("\(selectedCount) selected")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                            exportRow(for: page, index: index)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: onExport) {
                    Label(isExporting ? "Preparing…" : "Export & Share",
                          systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExporting || selectedPageIDs.isEmpty)

                if isExporting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                }
            }
            .padding()
            .navigationTitle("Export Pages")
        }
    }

    private func exportRow(for page: NotebookPageModel, index: Int) -> some View {
        let isSelected = selectedPageIDs.contains(page.id)
        return Button(action: {
            toggle(page.id)
        }) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(page.title.isEmpty ? "Page \(index + 1)" : page.title)
                        .font(.headline)
                    Text("Page \(index + 1)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .opacity(0.5)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear,
                                    lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(isSelected ? "Deselect" : "Select") {
                toggle(page.id)
            }
        }
    }

    private func toggle(_ id: UUID) {
        if selectedPageIDs.contains(id) {
            selectedPageIDs.remove(id)
        } else {
            selectedPageIDs.insert(id)
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private enum ImagePickerSource: String, CaseIterable, Identifiable {
    case photoLibrary
    case camera

    var id: String { rawValue }

    var uiKitSource: UIImagePickerController.SourceType {
        switch self {
        case .photoLibrary:
            return .photoLibrary
        case .camera:
            return .camera
        }
    }

    var isAvailable: Bool {
        switch self {
        case .photoLibrary:
            return UIImagePickerController.isSourceTypeAvailable(.photoLibrary)
        case .camera:
            return UIImagePickerController.isSourceTypeAvailable(.camera)
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
                ForEach(Array(suggestions.enumerated()), id: \.offset) { (_, color) in
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

private struct NotebookCoverPage: View {
    @Binding var notebook: Notebook

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .fill(LinearGradient(colors: [notebook.coverColor.opacity(0.98),
                                              notebook.coverColor.opacity(0.7)],
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
                .overlay(
                    RoundedRectangle(cornerRadius: 40, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1.5)
                )

            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .fill(
                    LinearGradient(colors: [Color.white.opacity(0.2), Color.clear],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                )
                .blur(radius: 1.5)
                .padding(4)

            VStack(alignment: .leading, spacing: 30) {
                Text(notebook.title)
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 3)

                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 2)

                VStack(alignment: .leading, spacing: 12) {
                    Label("Pages \(notebook.pages.count)", systemImage: "doc.on.doc")
                    Label(Date.now.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                }
                .foregroundColor(.white.opacity(0.85))
                .font(.subheadline.weight(.medium))

                Spacer()

                HStack {
                    Spacer()
                    Image(systemName: "bookmark.fill")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.85))
                        .padding(16)
                        .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                }
            }
            .padding(44)
        }
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
        NotebookPageView(pageStore: NotebookPageStore(notebookID: UUID(),
                                                      pageModels: [NotebookPageModel(title: "Page 1")]),
                         notebook: .constant(Notebook(title: "Preview",
                                                       coverColor: Color(red: 0.3, green: 0.5, blue: 0.8))))
            .previewInterfaceOrientation(.landscapeLeft)
            .previewDevice("iPad (10th generation)")
    }
}

struct CroppingImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onSelection: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.allowsEditing = true // keeps the simple built-in crop UI
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CroppingImagePicker

        init(parent: CroppingImagePicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true) {
                self.parent.onCancel()
            }
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let edited = info[.editedImage] as? UIImage
            let original = info[.originalImage] as? UIImage
            picker.dismiss(animated: true) {
                if let image = edited ?? original {
                    self.parent.onSelection(image)
                } else {
                    self.parent.onCancel()
                }
            }
        }
    }
}

private extension NotebookPageView {
    func loadImage(from provider: NSItemProvider, location: CGPoint, pageID: UUID, viewSize: CGSize) {
        provider.loadObject(ofClass: UIImage.self) { item, _ in
            if let image = item as? UIImage {
                DispatchQueue.main.async {
                    insertDroppedImage(image, at: location, pageID: pageID, viewSize: viewSize)
                }
            } else {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                    guard let url else { return }
                    loadImage(fromFileURL: url) { image in
                        if let image {
                            insertDroppedImage(image, at: location, pageID: pageID, viewSize: viewSize)
                        }
                    }
                }
            }
        }
    }

    func loadImage(fromFileURL url: URL, completion: @escaping (UIImage?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let data = try? Data(contentsOf: url)
            let image = data.flatMap { UIImage(data: $0) }
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    func loadRemoteImage(from url: URL, location: CGPoint, pageID: UUID, viewSize: CGSize) {
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else { return }
            await MainActor.run {
                insertDroppedImage(image, at: location, pageID: pageID, viewSize: viewSize)
            }
        }
    }

    func insertDroppedImage(_ image: UIImage, at location: CGPoint, pageID: UUID, viewSize: CGSize) {
        let scaleWidth = viewSize.width / basePageSize.width
        let scaleHeight = viewSize.height / basePageSize.height
        let scale = min(scaleWidth, scaleHeight)
        let offsetX = (viewSize.width - basePageSize.width * scale) / 2
        let offsetY = (viewSize.height - basePageSize.height * scale) / 2
        let normalizedX = (location.x - offsetX) / scale
        let normalizedY = (location.y - offsetY) / scale
        let clampedCenter = CGPoint(x: max(0, min(basePageSize.width, normalizedX)),
                                    y: max(0, min(basePageSize.height, normalizedY)))
        let size = defaultImageSize(for: image)
        guard let data = image.pngData() ?? image.jpegData(compressionQuality: 0.95) else { return }
        let attachment = NotebookPageImage(imageData: data,
                                           center: clampedCenter,
                                           size: size,
                                           rotation: 0)
        pageStore.addImage(attachment, to: pageID)
    }

    func feedbackForUnsupportedDrop() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
