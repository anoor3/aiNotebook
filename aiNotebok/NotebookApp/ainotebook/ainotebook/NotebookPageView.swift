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
    var pageColor: PaperColor
    private let coverPageID = UUID()
    private let notebookID: UUID
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
    private let shapePasteboardType = "com.ainotebook.shapeKind"

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
    @State private var suppressScrollToActivePage = false
    @State private var isCoverActive = false
    @State private var didApplyInitialPage = false
    @State private var showImageOptions = false
    @State private var showShapesSheet = false
    @State private var imagePickerSource: ImagePickerSource?
    @State private var pendingImagePageID: UUID?
    @State private var showAIChat = false
    @State private var aiMessages: [AIChatMessage] = AIChatMessage.seedConversation
    @State private var aiQueryMode: AIQueryMode = .text
    @State private var aiPanelDragOffset: CGFloat = 0
    /// Holds the currently editable image so PencilKit interaction can be paused while the finger manipulates it.
    @State private var editingAttachmentContext: EditingAttachmentContext?
    @State private var croppingAttachmentContext: CroppingAttachmentContext?
    @State private var showExportSheet = false
    @State private var exportSelection: Set<UUID> = []
    @State private var exportFormat: NotebookExportFormat = .pdf
    @State private var isExportingSelection = false
    @State private var exportErrorMessage: String?
    @State private var shareURLs: [URL] = []
    @State private var isPresentingShareSheet = false
    @State private var showVoiceRecorderHUD = false
    @State private var showRecordingHistory = false
    @State private var showCalculator = false
    @ObservedObject private var voiceRecorder: VoiceRecorderManager
    @State private var shapeAttachmentKinds: [UUID: ShapeTemplate.Kind] = [:]
    @State private var pasteboardHasImage = UIPasteboard.general.hasImages
    @State private var sharedZoomScale: CGFloat = 1.0
    @State private var pinchBaseScale: CGFloat = 1.0

    private var workspaceBackground: Color {
        switch pageColor {
        case .classic:
            return Color(red: 0.95, green: 0.94, blue: 0.9)
        case .white:
            return Color(red: 245/255, green: 245/255, blue: 240/255)
        }
    }

    init(paperStyle: PaperStyle = .grid,
         pageColor: PaperColor = .classic,
         pageStore: NotebookPageStore,
         notebook: Binding<Notebook>,
         voiceRecorder: VoiceRecorderManager) {
        self.paperStyle = paperStyle
        self.pageColor = pageColor
        self._pageStore = ObservedObject(wrappedValue: pageStore)
        self._notebook = notebook
        self.notebookID = notebook.wrappedValue.id
        let defaultColor = Self.penPalette[0]
        let defaultHighlighter = Self.highlighterPalette[0]
        let defaultWidth = Self.thicknessOptions[1]
        _currentStrokeColor = State(initialValue: defaultColor)
        _penStrokeColor = State(initialValue: defaultColor)
        _highlighterStrokeColor = State(initialValue: defaultHighlighter)
        _currentStrokeWidth = State(initialValue: defaultWidth)
        _voiceRecorder = ObservedObject(wrappedValue: voiceRecorder)
        if let savedMessages = AIChatPersistence.load(for: notebook.wrappedValue.id), !savedMessages.isEmpty {
            _aiMessages = State(initialValue: savedMessages)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let pageSize = basePageSize
            let baseScale = self.pageScale(for: geometry.size.width)
            let pageScale = baseScale * sharedZoomScale
            let scaledHeight = pageSize.height * pageScale
            let viewportHeight = max(min(scaledHeight + 60, geometry.size.height - 80), 420)
            let isZoomedOut = sharedZoomScale < 0.85

            ZStack(alignment: .top) {
                workspaceBackground
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    toolbar
                        .padding(.top, 12)

                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                coverPage(pageSize: pageSize,
                                          viewportHeight: viewportHeight,
                                          isZoomedOut: isZoomedOut)
                                    .frame(width: pageSize.width, height: pageSize.height)
                                    .scaleEffect(pageScale, anchor: .center)
                                    .frame(width: pageSize.width * pageScale,
                                           height: pageSize.height * pageScale,
                                           alignment: .center)
                                    .id(coverPageID)

                                ForEach(pageStore.pages, id: \.id) { controller in
                                    Rectangle()
                                        .fill(Color.black.opacity(0.6))
                                        .frame(height: 2)

                                    notebookPage(for: controller,
                                                 pageSize: pageSize,
                                                 viewportHeight: viewportHeight,
                                                 pageScale: pageScale,
                                                 isZoomedOut: isZoomedOut)
                                        .frame(maxWidth: .infinity)
                                        .id(controller.id)
                                }

                                addPagePrompt
                                    .onAppear {
                                        requestAdditionalPage()
                                    }
                            }
                            .padding(.vertical, 0)
                            .frame(maxWidth: .infinity)
                        }
                        .coordinateSpace(name: scrollSpaceName)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let newScale = pinchBaseScale * value
                                    sharedZoomScale = max(0.75, min(newScale, 2.5))
                                }
                                .onEnded { value in
                                    let final = max(0.75, min(pinchBaseScale * value, 2.5))
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        sharedZoomScale = final
                                    }
                                    pinchBaseScale = final
                                }
                        )
                        .onAppear {
                            scrollProxy = proxy
                            scrollToActivePage(animated: false)
                        }
                    }
                }
                .padding(.horizontal, 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .onPreferenceChange(PageVisibilityPreferenceKey.self) { values in
                    DispatchQueue.main.async {
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
                            suppressScrollToActivePage = true
                            pageStore.activePageID = closest.key
                            showPageIndicatorTemporary()
                        }
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
                    .font(.system(.caption, design: .monospaced).bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .padding(18)
                    .transition(.opacity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            refreshPasteboardState()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            let orientation = UIDevice.current.orientation
            guard orientation.isValidInterfaceOrientation else { return }
            scrollToActivePage(animated: false)
        }
        .onChange(of: currentStrokeColor) { newColor in
            updateSelectedAttachmentColor(with: newColor)
        }
        .overlay(alignment: .leading) {
            if showAIChat {
                let panelWidth = min(520, UIScreen.main.bounds.width * 0.5)
                AIChatSheet(messages: $aiMessages,
                            queryMode: $aiQueryMode,
                            onClose: { showAIChat = false },
                            onNewChat: resetAIChat)
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
        .onChange(of: aiMessages) { messages in
            AIChatPersistence.save(messages, for: notebookID)
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
            if suppressScrollToActivePage {
                suppressScrollToActivePage = false
            } else {
                scrollToActivePage()
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
                .presentationDetents([.large])
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
        .sheet(item: $croppingAttachmentContext) { context in
            if let image = UIImage(data: context.attachment.imageData) {
                AttachmentCropSheet(image: image,
                                    onCancel: { croppingAttachmentContext = nil },
                                    onSave: { cropped in
                                        handleCroppedImage(cropped, for: context)
                                        croppingAttachmentContext = nil
                                    })
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(.largeTitle, design: .monospaced))
                    Text("Unable to load image for cropping.")
                        .multilineTextAlignment(.center)
                    Button("Close") {
                        croppingAttachmentContext = nil
                    }
                }
                .padding()
            }
        }
        .sheet(isPresented: $showShapesSheet) {
            ShapePickerSheet(onSelect: { shape in
                insertShape(shape)
                showShapesSheet = false
            }, onClose: {
                showShapesSheet = false
            })
        }
        .onReceive(NotificationCenter.default.publisher(for: .notebookRequestExport)) { _ in
            presentExportOptions()
        }
        .overlay(alignment: .topTrailing) {
            let currentPageID = pageStore.activePageID ?? pageStore.pages.first?.id
            let currentPageLabel = pageLabel(for: currentPageID)
            VStack(alignment: .trailing, spacing: 10) {
                if voiceRecorder.isRecording {
                    VoiceRecordingIndicator(duration: voiceRecorder.recordingDuration) {
                        voiceRecorder.stopRecording()
                    }
                }

                if showVoiceRecorderHUD {
                    VoiceRecorderHUD(recorder: voiceRecorder,
                                     currentPageID: currentPageID,
                                     pageLabel: currentPageLabel,
                                     onShowHistory: { showRecordingHistory = true },
                                     onClose: { showVoiceRecorderHUD = false })
                }
            }
            .padding(.trailing, 24)
            .padding(.top, 80)
        }
        .onChange(of: voiceRecorder.isRecording) { isRecording in
            if isRecording {
                showVoiceRecorderHUD = false
            }
        }
        .sheet(isPresented: $showRecordingHistory) {
            VoiceRecordingHistorySheet(recorder: voiceRecorder,
                                       pageStore: pageStore,
                                       onClose: { showRecordingHistory = false })
                .presentationDetents([.large])
        }
        .overlay {
            if showCalculator {
                ScientificCalculatorView(onClose: { showCalculator = false })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(5)
            }
        }
        .onDisappear {
            voiceRecorder.stopRecordingIfNeeded()
        }
    }

    /// Compact toolbar styled like native iPadOS tools.
    private var toolbar: some View {
        HStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
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

                    toolButton(systemName: "lasso", isActive: currentTool == .selection) {
                        selectTool(.selection)
                    }

                    Divider().frame(height: 20)

                    colorButtons

                    Divider().frame(height: 20)

                    thicknessButtons

                    Divider().frame(height: 20)

                    Button(action: { showCalculator = true }) {
                        Image(systemName: "function")
                    }
                    .buttonStyle(ToolbarButtonStyle(isActive: false))
                }
                .padding(.horizontal, 4)
            }

            HStack(spacing: 12) {
                if let controller = activePageController {
                    UndoRedoControls(controller: controller)
                }

                Button(action: presentImageOptions) {
                    Image(systemName: "photo.on.rectangle")
                }
                .buttonStyle(ToolbarButtonStyle(isActive: false))

                Button(action: { showShapesSheet = true }) {
                    Image(systemName: "square.on.circle")
                }
                .buttonStyle(ToolbarButtonStyle(isActive: false))

                Button(action: { showVoiceRecorderHUD.toggle() }) {
                    Image(systemName: "waveform.and.mic")
                }
                .buttonStyle(ToolbarButtonStyle(isActive: false))

                Button(action: { showAIChat = true }) {
                    AISparkleGlyph()
                }
                .buttonStyle(ToolbarButtonStyle(isActive: false))
            }
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
                let isSelected = currentStrokeColor == color && displayedDrawingTool.isDrawingTool
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
        let isSelected = currentStrokeColor == customUIColor && activeTool.isDrawingTool

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
                let isSelected = abs(currentStrokeWidth - width) < 0.1 && displayedDrawingTool.isDrawingTool
                Button(action: {
                    let targetTool = displayedDrawingTool
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
        switch currentTool {
        case .eraser, .selection:
            return lastDrawingTool
        default:
            return currentTool
        }
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
        if tool.isDrawingTool {
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
                .font(.system(.subheadline, design: .monospaced))
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

    private func coverPage(pageSize: CGSize, viewportHeight: CGFloat, isZoomedOut: Bool) -> some View {
        NotebookCoverPage(notebook: $notebook)
            .shadow(color: isZoomedOut ? Color.clear : Color.black.opacity(0.08),
                    radius: isZoomedOut ? 0 : 18,
                    y: isZoomedOut ? 0 : 8)
            .padding(.horizontal, isZoomedOut ? 0 : 4)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: PageVisibilityPreferenceKey.self,
                                           value: [coverPageID: distanceToCenter(for: proxy, viewportHeight: viewportHeight)])
                }
            )
    }

    private func notebookPage(for controller: CanvasController,
                              pageSize: CGSize,
                              viewportHeight: CGFloat,
                              pageScale: CGFloat,
                              isZoomedOut: Bool) -> some View {
        let pageID = controller.id
        let attachments = canvasAttachments(for: pageID)
        let binding = Binding<UUID?>(
            get: {
                guard editingAttachmentContext?.pageID == pageID else { return nil }
                return editingAttachmentContext?.attachmentID
            },
            set: { newValue in
                if let id = newValue {
                    editingAttachmentContext = EditingAttachmentContext(pageID: pageID, attachmentID: id)
                } else if editingAttachmentContext?.pageID == pageID {
                    editingAttachmentContext = nil
                }
            }
        )

        let pageContent = PencilCanvasView(controller: controller,
                                           pageSize: pageSize,
                                           paperStyle: paperStyle,
                                           paperColor: pageColor,
                                           attachments: attachments,
                                           sharedZoomScale: $sharedZoomScale,
                                           editingAttachmentID: binding,
                                           onAttachmentChanged: { updated in
                                               handleAttachmentUpdate(updated, for: pageID)
                                           },
                                           onAttachmentDeleted: { imageID in
                                               deleteAttachment(imageID, for: pageID)
                                           },
                                           onAttachmentDuplicated: { attachment in
                                               duplicateAttachment(attachment, for: pageID, pageSize: pageSize)
                                           },
                                           onAttachmentCopied: { attachment in
                                               copyAttachment(attachment)
                                           },
                                           onAttachmentCropped: { attachment in
                                               startCropping(attachment, for: pageID, pageSize: pageSize)
                                           },
                                           onAttachmentDone: {
                                               finalizeImageEditing()
                                           },
                                           onAttachmentTapOutside: {
                                               handleTapOutsideEditing(for: pageID)
                                           })
        .frame(width: pageSize.width, height: pageSize.height)
        .contentShape(Rectangle())
        .gesture(pageTapGesture(attachments: attachments,
                                pageID: pageID,
                                pageSize: pageSize))
        .onDrop(of: [UTType.image.identifier], delegate: AttachmentDropDelegate(pageSize: pageSize) { location, image in
            handleDroppedImage(image,
                               at: location,
                               pageSize: pageSize,
                               pageID: pageID)
        })
        .onAppear {
            setCanvasInteraction(enabled: binding.wrappedValue == nil, for: controller)
        }
        .onChange(of: binding.wrappedValue) { newValue in
            setCanvasInteraction(enabled: newValue == nil, for: controller)
        }

        return pageContent
            .scaleEffect(pageScale, anchor: .center)
            .frame(width: pageSize.width * pageScale,
                   height: pageSize.height * pageScale,
                   alignment: .center)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: PageVisibilityPreferenceKey.self,
                                           value: [controller.id: distanceToCenter(for: proxy, viewportHeight: viewportHeight)])
                }
            )
    }

    private func pageTapGesture(attachments: [CanvasAttachment],
                                pageID: UUID,
                                pageSize: CGSize) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                handlePageTap(at: value.location,
                              attachments: attachments,
                              pageID: pageID,
                              pageSize: pageSize)
            }
    }

    private func handlePageTap(at location: CGPoint,
                               attachments: [CanvasAttachment],
                               pageID: UUID,
                               pageSize: CGSize) {
        if let editing = editingAttachmentContext {
            guard editing.pageID == pageID else { return }
            if let target = attachment(containing: location,
                                       in: attachments,
                                       pageSize: pageSize) {
                editingAttachmentContext = EditingAttachmentContext(pageID: pageID, attachmentID: target.id)
            } else {
                handleTapOutsideEditing(for: pageID)
            }
            return
        }

        guard let target = attachment(containing: location, in: attachments, pageSize: pageSize) else {
            return
        }
        editingAttachmentContext = EditingAttachmentContext(pageID: pageID, attachmentID: target.id)
    }

    private func attachment(containing point: CGPoint,
                            in attachments: [CanvasAttachment],
                            pageSize: CGSize) -> CanvasAttachment? {
        guard point.x >= 0,
              point.y >= 0,
              point.x <= pageSize.width,
              point.y <= pageSize.height else { return nil }

        for attachment in attachments.reversed() {
            if attachment.isLocked { continue }
            if attachmentContains(point, attachment: attachment) {
                return attachment
            }
        }
        return nil
    }

    private func attachmentContains(_ point: CGPoint, attachment: CanvasAttachment) -> Bool {
        let translated = CGPoint(x: point.x - attachment.center.x,
                                 y: point.y - attachment.center.y)
        let rotation = CGAffineTransform(rotationAngle: -attachment.rotation)
        let aligned = translated.applying(rotation)
        let rect = CGRect(x: -attachment.size.width / 2,
                          y: -attachment.size.height / 2,
                          width: attachment.size.width,
                          height: attachment.size.height)
        return rect.contains(aligned)
    }

    private func showPageIndicatorTemporary() {
        showPageIndicator = true
        pageIndicatorWorkItem?.cancel()
        let workItem = DispatchWorkItem { showPageIndicator = false }
        pageIndicatorWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: workItem)
    }

    private func setCanvasInteraction(enabled: Bool, for controller: CanvasController) {
        controller.canvasView.isUserInteractionEnabled = enabled
    }

    private func scrollToActivePage(animated: Bool = true) {
        guard let proxy = scrollProxy,
              let targetID = pageStore.activePageID else { return }
        isProgrammaticJump = true
        let scrollAction = {
            proxy.scrollTo(targetID, anchor: .top)
        }
        if animated {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                scrollAction()
            }
        } else {
            scrollAction()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isProgrammaticJump = false
        }
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
        case .eraser, .selection:
            return penStrokeColor
        }
    }

    private func storeColor(_ color: UIColor, for tool: CanvasDrawingTool) {
        switch tool {
        case .pen:
            penStrokeColor = color
        case .highlighter:
            highlighterStrokeColor = color
        case .eraser, .selection:
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
        guard insertImage(image,
                           on: pageID,
                           pageSize: basePageSize,
                           preferredCenter: nil) != nil else {
            cancelImageInsertion()
            return
        }
        imagePickerSource = nil
    }

    private func insertShape(_ kind: ShapeTemplate.Kind) {
        guard let pageID = activePageController?.id ?? pageStore.pages.first?.id else { return }
        let color = currentStrokeColor
        let image = renderedShapeImage(for: kind, color: color)
        if let newID = insertImage(image,
                                   on: pageID,
                                   pageSize: basePageSize,
                                   preferredCenter: nil) {
            shapeAttachmentKinds[newID] = kind
        }
    }

    private func pasteFromClipboard() {
        guard pasteboardHasImage else { return }
        guard let pageID = activePageController?.id ?? pageStore.pages.first?.id else { return }
        guard let image = UIPasteboard.general.image else { return }
        if let newID = insertImage(image,
                                   on: pageID,
                                   pageSize: basePageSize,
                                   preferredCenter: nil) {
            if let kindRaw = UIPasteboard.general.value(forPasteboardType: shapePasteboardType) as? String,
               let kind = ShapeTemplate.Kind(rawValue: kindRaw) {
                shapeAttachmentKinds[newID] = kind
            }
        }
        refreshPasteboardState()
    }

    private func refreshPasteboardState() {
        pasteboardHasImage = UIPasteboard.general.hasImages
    }

    private func renderedShapeImage(for kind: ShapeTemplate.Kind, color: UIColor) -> UIImage {
        let canvasSize = CGSize(width: 720, height: 720)
        let inset: CGFloat = 140
        let rect = CGRect(origin: .zero, size: canvasSize).insetBy(dx: inset, dy: inset)
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: UIGraphicsImageRendererFormat.default())
        let strokeColor = color
        let lineWidth: CGFloat = 10

        return renderer.image { ctx in
            ctx.cgContext.setFillColor(UIColor.clear.cgColor)
            ctx.cgContext.setStrokeColor(strokeColor.cgColor)
            ctx.cgContext.setLineWidth(lineWidth)
            ctx.cgContext.setLineCap(.round)
            ctx.cgContext.setLineJoin(.round)

            switch kind {
            case .rectangle:
                let path = UIBezierPath(rect: rect)
                strokeColor.setStroke()
                path.lineWidth = lineWidth
                path.stroke()
            case .square:
                let side = min(rect.width, rect.height)
                let squareRect = CGRect(x: rect.midX - side / 2,
                                        y: rect.midY - side / 2,
                                        width: side,
                                        height: side)
                let path = UIBezierPath(rect: squareRect)
                strokeColor.setStroke()
                path.lineWidth = lineWidth
                path.stroke()
            case .roundedRectangle:
                let path = UIBezierPath(roundedRect: rect, cornerRadius: 90)
                strokeColor.setStroke()
                path.lineWidth = lineWidth
                path.stroke()
            case .circle:
                let path = UIBezierPath(ovalIn: rect)
                strokeColor.setStroke()
                path.lineWidth = lineWidth
                path.stroke()
            case .triangle:
                let path = UIBezierPath()
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.close()
                strokeColor.setStroke()
                path.lineWidth = lineWidth
                path.stroke()
            case .line:
                ctx.cgContext.move(to: CGPoint(x: rect.minX, y: rect.midY))
                ctx.cgContext.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                ctx.cgContext.strokePath()
            case .arrow:
                let start = CGPoint(x: rect.minX, y: rect.midY)
                let end = CGPoint(x: rect.maxX - 90, y: rect.midY)
                ctx.cgContext.move(to: start)
                ctx.cgContext.addLine(to: end)
                ctx.cgContext.strokePath()

                let head = UIBezierPath()
                head.move(to: CGPoint(x: rect.maxX - 90, y: rect.midY - 60))
                head.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                head.addLine(to: CGPoint(x: rect.maxX - 90, y: rect.midY + 60))
                strokeColor.setStroke()
                head.lineWidth = lineWidth
                head.stroke()
            }
        }
    }

    private func updateSelectedAttachmentColor(with color: UIColor) {
        guard let context = editingAttachmentContext,
              let kind = shapeAttachmentKinds[context.attachmentID] else { return }
        let image = renderedShapeImage(for: kind, color: color)
        guard let data = image.pngData() else { return }
        guard let model = pageStore.images(for: context.pageID).first(where: { $0.id == context.attachmentID }) else { return }
        pageStore.updateImageContent(pageID: context.pageID,
                                     imageID: context.attachmentID,
                                     imageData: data,
                                     size: model.size)
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
                             rotation: CGFloat(model.rotation),
                             isLocked: model.isLocked)
        }
    }

    private func handleAttachmentUpdate(_ attachment: CanvasAttachment, for pageID: UUID) {
        pageStore.updateImageTransform(pageID: pageID,
                                       imageID: attachment.id,
                                       center: attachment.center,
                                       size: attachment.size,
                                       rotation: Double(attachment.rotation))
    }

    private func deleteAttachment(_ imageID: UUID, for pageID: UUID) {
        pageStore.removeImage(pageID: pageID, imageID: imageID)
        shapeAttachmentKinds.removeValue(forKey: imageID)
        if editingAttachmentContext?.pageID == pageID,
           editingAttachmentContext?.attachmentID == imageID {
            editingAttachmentContext = nil
        }
    }

    private func duplicateAttachment(_ attachment: CanvasAttachment,
                                     for pageID: UUID,
                                     pageSize: CGSize) {
        let offset: CGFloat = 36
        var newCenter = CGPoint(x: attachment.center.x + offset,
                                y: attachment.center.y + offset)
        newCenter = clampedCenter(newCenter, for: attachment.size, pageSize: pageSize)

        let duplicate = NotebookPageImage(imageData: attachment.imageData,
                                          center: newCenter,
                                          size: attachment.size,
                                          rotation: Double(attachment.rotation),
                                          isLocked: attachment.isLocked)
        pageStore.addImage(duplicate, to: pageID)
        editingAttachmentContext = EditingAttachmentContext(pageID: pageID, attachmentID: duplicate.id)
        if let kind = shapeAttachmentKinds[attachment.id] {
            shapeAttachmentKinds[duplicate.id] = kind
        }
    }

    private func copyAttachment(_ attachment: CanvasAttachment) {
        guard let image = UIImage(data: attachment.imageData) else { return }
        var item: [String: Any] = [:]
        if let data = image.pngData() {
            item[UTType.png.identifier] = data
        }
        if let kind = shapeAttachmentKinds[attachment.id] {
            item[shapePasteboardType] = kind.rawValue
        }
        UIPasteboard.general.setItems([item], options: [:])
        refreshPasteboardState()
    }

    private func startCropping(_ attachment: CanvasAttachment,
                               for pageID: UUID,
                               pageSize: CGSize) {
        guard UIImage(data: attachment.imageData) != nil else { return }
        croppingAttachmentContext = CroppingAttachmentContext(pageID: pageID,
                                                             attachment: attachment,
                                                             pageSize: pageSize)
    }

    private func handleCroppedImage(_ image: UIImage,
                                    for context: CroppingAttachmentContext) {
        guard let data = image.pngData() ?? image.jpegData(compressionQuality: 0.9) else { return }
        let targetWidth = context.attachment.size.width
        let newSize = resizedSize(for: image.size,
                                  targetWidth: targetWidth,
                                  pageSize: context.pageSize)
        pageStore.updateImageContent(pageID: context.pageID,
                                     imageID: context.attachment.id,
                                     imageData: data,
                                     size: newSize)
    }

    private func handleDroppedImage(_ image: UIImage, at location: CGPoint, pageSize: CGSize, pageID: UUID) {
        _ = insertImage(image,
                        on: pageID,
                        pageSize: pageSize,
                        preferredCenter: location)
    }

    @discardableResult
    private func insertImage(_ image: UIImage,
                             on pageID: UUID,
                             pageSize: CGSize,
                             preferredCenter: CGPoint?) -> UUID? {
        guard let data = image.pngData() ?? image.jpegData(compressionQuality: 0.9) else {
            return nil
        }
        let size = defaultImageSize(for: image)
        let center: CGPoint
        if let preferredCenter {
            center = clampedCenter(preferredCenter, for: size, pageSize: pageSize)
        } else {
            center = CGPoint(x: pageSize.width / 2, y: pageSize.height / 2)
        }
        let attachment = NotebookPageImage(imageData: data,
                                           center: center,
                                           size: size,
                                           rotation: 0,
                                           isLocked: false)
        pageStore.addImage(attachment, to: pageID)
        editingAttachmentContext = EditingAttachmentContext(pageID: pageID, attachmentID: attachment.id)
        return attachment.id
    }

    private func clampedCenter(_ center: CGPoint, for size: CGSize, pageSize: CGSize) -> CGPoint {
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        var adjusted = center
        adjusted.x = max(halfWidth, min(pageSize.width - halfWidth, adjusted.x))
        adjusted.y = max(halfHeight, min(pageSize.height - halfHeight, adjusted.y))
        return adjusted
    }

    private func resizedSize(for imageSize: CGSize,
                              targetWidth: CGFloat,
                              pageSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGSize(width: targetWidth, height: targetWidth)
        }

        let minDimension: CGFloat = 120
        let maxWidth = pageSize.width * 0.95
        let maxHeight = pageSize.height * 0.95

        var width = max(minDimension, min(targetWidth, maxWidth))
        let aspect = imageSize.height / imageSize.width
        var height = width * aspect

        if height > maxHeight {
            height = maxHeight
            width = height / max(aspect, 0.01)
        }

        if height < minDimension {
            height = minDimension
            width = height / max(aspect, 0.01)
        }

        return CGSize(width: width, height: height)
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
                                                    paperColor: notebook.paperColor,
                                                    drawingData: drawingData,
                                                    attachments: attachments)
            payloads.append(payload)
        }
        return payloads
    }

    private func resetAIChat() {
        aiMessages = AIChatMessage.seedConversation
        AIChatPersistence.delete(for: notebookID)
    }

    private func pageLabel(for pageID: UUID?) -> String? {
        guard let pageID else { return nil }
        if let model = pageStore.model(for: pageID) {
            let trimmed = model.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        if let index = pageStore.pages.firstIndex(where: { $0.id == pageID }) {
            return "Page \(index + 1)"
        }
        return nil
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

private struct CroppingAttachmentContext: Identifiable {
    let pageID: UUID
    let attachment: CanvasAttachment
    let pageSize: CGSize

    var id: UUID { attachment.id }
}

private struct AttachmentDropDelegate: DropDelegate {
    let pageSize: CGSize
    let onDrop: (CGPoint, UIImage) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.image])
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [UTType.image]).first else {
            return false
        }
        let location = info.location
        provider.loadObject(ofClass: UIImage.self) { object, _ in
            guard let image = object as? UIImage else { return }
            DispatchQueue.main.async {
                onDrop(clampedLocation(location, pageSize: pageSize), image)
            }
        }
        return true
    }

    private func clampedLocation(_ location: CGPoint, pageSize: CGSize) -> CGPoint {
        var adjusted = location
        adjusted.x = max(0, min(pageSize.width, adjusted.x))
        adjusted.y = max(0, min(pageSize.height, adjusted.y))
        return adjusted
    }
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

struct AIChatMessage: Identifiable, Hashable, Codable {
    enum Role: String, Codable {
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
    var onNewChat: () -> Void

    @State private var draftMessage: String = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            Divider().opacity(0.3)

            chatStream
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(.caption, design: .monospaced))
                    Text(errorMessage)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(2)
                }
                .foregroundColor(.red)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }

            Divider().opacity(0.3)

            inputField
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.15), radius: 20, x: -5, y: 0)
        )
        .environment(\.font, .system(.body, design: .default))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(
                    LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("AI Assistant")
                    .font(.system(.headline, design: .monospaced))
                Text("Ask anything about your notes")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if messages.count > 1 {
                Button(action: {
                    draftMessage = ""
                    errorMessage = nil
                    onNewChat()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                        Text("New Chat")
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                    }
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(.subheadline, design: .monospaced).weight(.medium))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var chatStream: some View {
        Group {
            if messages.count <= 1 {
                VStack(spacing: 20) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 40))
                        .foregroundStyle(
                            LinearGradient(colors: [.blue.opacity(0.6), .purple.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    VStack(spacing: 6) {
                        Text("Start a conversation")
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        Text("Ask questions, brainstorm ideas, or get help with your notes.")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(messages) { message in
                                AIChatBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(.vertical, 16)
                        .padding(.horizontal, 16)
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            if let last = messages.last?.id {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: messages) { _ in
                        withAnimation(.easeOut(duration: 0.2)) {
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
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message...", text: $draftMessage, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .focused($isInputFocused)
                .disabled(isSending)

            Button(action: sendMessage) {
                Group {
                    if isSending {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 34, height: 34)
                .background(
                    Circle().fill(
                        draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
                            ? Color.gray.opacity(0.4)
                            : Color.accentColor
                    )
                )
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
                let reply = try await OpenAIChatService.send(messages: messages)
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
        HStack(alignment: .top, spacing: 10) {
            if message.role == .assistant {
                Image(systemName: "sparkles")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.purple)
                    .frame(width: 24, height: 24)
                    .background(Color.purple.opacity(0.1), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(message.text)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .padding(14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 50)
            } else {
                Spacer(minLength: 50)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(message.text)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)
                        .textSelection(.enabled)
                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(14)
                .background(
                    LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            }
        }
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
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .bold))
            Text("AI")
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundStyle(
            LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(colors: [Color.purple.opacity(0.15), Color.blue.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(
                    LinearGradient(colors: [.purple.opacity(0.5), .blue.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
        )
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
                    .font(.system(.title3, design: .monospaced).weight(.semibold))

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
                    .font(.system(.footnote, design: .monospaced))
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
                        .font(.system(.footnote, design: .monospaced))
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
                        .font(.system(.caption, design: .monospaced))
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
                    .font(.system(.title3, design: .monospaced))
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(page.title.isEmpty ? "Page \(index + 1)" : page.title)
                        .font(.system(.headline, design: .monospaced))
                    Text("Page \(index + 1)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(.footnote, design: .monospaced))
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
                .font(.system(.subheadline, design: .monospaced).weight(.medium))

                Spacer()

                HStack {
                    Spacer()
                    Image(systemName: "bookmark.fill")
                        .font(.system(.title2, design: .monospaced))
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
            Color(red: 233/255, green: 228/255, blue: 216/255)
        case .lined:
            LinedPaperBackground()
        }
    }
}

private struct DotPaperBackground: View {
    private let spacing: CGFloat = 28
    private let dotColor = Color(red: 178/255, green: 172/255, blue: 156/255).opacity(0.55)

    var body: some View {
        GeometryReader { geometry in
            Color(red: 233/255, green: 228/255, blue: 216/255)
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
            Color(red: 233/255, green: 228/255, blue: 216/255)
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
    private let gridColor = Color(red: 178/255, green: 172/255, blue: 156/255).opacity(0.85)

    var body: some View {
        GeometryReader { geometry in
            Color(red: 233/255, green: 228/255, blue: 216/255)
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

private struct UndoRedoControls: View {
    @ObservedObject var controller: CanvasController

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { controller.undo() }) {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(ToolbarButtonStyle(isActive: false))
            .disabled(!controller.canUndo)
            .opacity(controller.canUndo ? 1.0 : 0.4)

            Button(action: { controller.redo() }) {
                Image(systemName: "arrow.uturn.forward")
            }
            .buttonStyle(ToolbarButtonStyle(isActive: false))
            .disabled(!controller.canRedo)
            .opacity(controller.canRedo ? 1.0 : 0.4)
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
                                                       coverColor: Color(red: 0.3, green: 0.5, blue: 0.8))),
                         voiceRecorder: VoiceRecorderManager(notebookID: UUID()))
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
        picker.allowsEditing = false
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

struct ShapeTemplate: Identifiable {
    enum Kind: String, CaseIterable, Identifiable {
        case rectangle
        case roundedRectangle
        case square
        case circle
        case triangle
        case line
        case arrow

        var id: String { rawValue }
    }

    let id = UUID()
    let name: String
    let symbolName: String
    let kind: Kind

    static let catalog: [ShapeTemplate] = [
        ShapeTemplate(name: "Rectangle", symbolName: "rectangle", kind: .rectangle),
        ShapeTemplate(name: "Square", symbolName: "square", kind: .square),
        ShapeTemplate(name: "Rounded", symbolName: "app", kind: .roundedRectangle),
        ShapeTemplate(name: "Circle", symbolName: "circle", kind: .circle),
        ShapeTemplate(name: "Triangle", symbolName: "triangle", kind: .triangle),
        ShapeTemplate(name: "Line", symbolName: "minus", kind: .line),
        ShapeTemplate(name: "Arrow", symbolName: "arrow.right", kind: .arrow)
    ]
}

struct ShapePickerSheet: View {
    let onSelect: (ShapeTemplate.Kind) -> Void
    let onClose: () -> Void

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 72), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(ShapeTemplate.catalog) { template in
                            Button {
                                onSelect(template.kind)
                            } label: {
                                Image(systemName: template.symbolName)
                                    .font(.system(size: 26, weight: .semibold))
                                    .frame(width: 56, height: 56)
                                    .foregroundStyle(Color.accentColor)
                                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text("GIF stickers coming soon.")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .navigationTitle("Shapes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
        }
    }
}
