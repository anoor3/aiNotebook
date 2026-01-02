import SwiftUI
import UIKit
import AVFoundation

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
    @State private var isHighlighterActive = false
    @State private var showImagePicker = false
    @State private var showImagePickerSheet = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var isRecording = false
    @State private var audioRecorder: AVAudioRecorder?
    @State private var showVoiceNotes = false
    @State private var audioPlayer: AVAudioPlayer?
    @State private var eraserMode: CanvasController.EraserMode = .stroke
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
                                    ForEach(pageStore.pages, id: \.id) { controller in
                                        notebookPage(for: controller,
                                                     pageSize: pageSize,
                                                     viewportHeight: viewportHeight)
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
        .sheet(isPresented: $showImagePickerSheet) {
            ImagePicker(sourceType: imagePickerSource) { image in
                showImagePickerSheet = false
                guard let image else { return }
                insertImage(image)
            }
        }
        .sheet(isPresented: $showVoiceNotes) {
            VoiceNotesList(notes: activePageController?.voiceNotes ?? [],
                           onClose: { showVoiceNotes = false },
                           onPlay: { note in playVoiceNote(note) })
        }
        .onChange(of: activePageController?.imageAttachments ?? []) { _ in
            // ensure selection resets when switching pages
            eraserMode = activePageController?.eraserMode ?? .stroke
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
                isHighlighterActive = false
                applyToolSettings(useEraser: false, useHighlighter: false)
            }

            toolButton(systemName: "eraser", isActive: isUsingEraser) {
                isUsingEraser = true
                isHighlighterActive = false
                applyToolSettings(useEraser: true, useHighlighter: false)
            }
            .contextMenu {
                ForEach(CanvasController.EraserMode.allCases, id: \.self) { mode in
                    Button {
                        eraserMode = mode
                        isUsingEraser = true
                        isHighlighterActive = false
                        applyToolSettings(useEraser: true, useHighlighter: false, eraserMode: mode)
                    } label: {
                        Label(mode == .precision ? "Precision Eraser" : "Stroke Eraser",
                              systemImage: eraserMode == mode ? "checkmark" : "circle")
                    }
                }
            }

            toolButton(systemName: "highlighter", isActive: isHighlighterActive) {
                toggleHighlighter()
            }

            Divider().frame(height: 20)

            colorButtons

            Divider().frame(height: 20)

            thicknessButtons

            Divider().frame(height: 20)

            Button(action: {
                imagePickerSource = .photoLibrary
                showImagePicker = true
            }) {
                Image(systemName: "photo")
            }
            .buttonStyle(ToolbarButtonStyle(isActive: false))
            .confirmationDialog("Insert Image", isPresented: $showImagePicker, titleVisibility: .visible) {
                Button("Choose from Photos") {
                    imagePickerSource = .photoLibrary
                    showImagePicker = false
                    presentImagePicker()
                }
                Button("Take Photo") {
                    imagePickerSource = .camera
                    showImagePicker = false
                    presentImagePicker()
                }
                Button("Cancel", role: .cancel) { showImagePicker = false }
            }

            Button(action: { toggleRecording() }) {
                Image(systemName: isRecording ? "stop.circle.fill" : "mic")
            }
            .buttonStyle(ToolbarButtonStyle(isActive: isRecording))
            .contextMenu {
                Button("Voice Notes") { showVoiceNotes = true }
            }

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
                    isHighlighterActive = false
                    applyToolSettings(useEraser: false, strokeColor: color, useHighlighter: false)
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
                    isHighlighterActive = false
                    applyToolSettings(useEraser: false, strokeWidth: width, useHighlighter: false)
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
        guard let id = pageStore.activePageID else { return pageStore.pages.first }
        return pageStore.pages.first(where: { $0.id == id }) ?? pageStore.pages.first
    }

    private var pageIndicatorText: String? {
        guard let activeID = pageStore.activePageID,
              let index = pageStore.pages.firstIndex(where: { $0.id == activeID }) else { return nil }
        return "Page \(index + 1) of \(pageStore.pages.count)"
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
                                   strokeWidth: CGFloat? = nil,
                                   useHighlighter: Bool? = nil,
                                   eraserMode: CanvasController.EraserMode? = nil) {
        for controller in pageStore.pages {
            if let eraser = useEraser {
                controller.useEraser = eraser
            }
            if let highlighter = useHighlighter {
                controller.useHighlighter = highlighter
            }
            if let eraserMode = eraserMode {
                controller.setEraserMode(eraserMode)
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
        isHighlighterActive = false
        applyToolSettings(useEraser: false, strokeColor: color, useHighlighter: false)
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
                                  useEraser: isUsingEraser)
            applyToolSettings(eraserMode: eraserMode)
            isLoadingNextPage = false
        }
    }

    private func toggleHighlighter() {
        isUsingEraser = false
        isHighlighterActive.toggle()
        if isHighlighterActive {
            let highlightColor = UIColor.yellow.withAlphaComponent(0.35)
            applyToolSettings(useEraser: false, strokeColor: highlightColor, useHighlighter: true)
        } else {
            applyToolSettings(useEraser: false, strokeColor: currentStrokeColor, useHighlighter: false)
        }
    }

    private func presentImagePicker() {
        if imagePickerSource == .camera && !UIImagePickerController.isSourceTypeAvailable(.camera) {
            imagePickerSource = .photoLibrary
        }
        showImagePickerSheet = true
    }

    private func insertImage(_ image: UIImage) {
        guard let controller = activePageController,
              let data = image.jpegData(compressionQuality: 0.9) else { return }
        let aspect = image.size.height / max(image.size.width, 1)
        let targetWidth: CGFloat = 320
        let size = CGSize(width: targetWidth, height: targetWidth * aspect)
        let position = CodablePoint(CGPoint(x: defaultPageSize.width / 2, y: defaultPageSize.height / 2))
        let attachment = PageImageAttachment(imageData: data,
                                             position: position,
                                             size: CodableSize(width: size.width, height: size.height),
                                             rotation: 0)
        controller.imageAttachments.append(attachment)
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard let pageID = pageStore.activePageID else { return }
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            guard granted else { return }
            DispatchQueue.main.async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                    try session.setActive(true)

                    let url = DrawingPersistence.voiceNoteURL(notebookID: pageStore.notebookIdentifier,
                                                              pageID: pageID,
                                                              noteID: UUID())
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                            withIntermediateDirectories: true)
                    let settings: [String: Any] = [
                        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                        AVSampleRateKey: 44100,
                        AVNumberOfChannelsKey: 1,
                        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                    ]
                    let recorder = try AVAudioRecorder(url: url, settings: settings)
                    recorder.prepareToRecord()
                    recorder.record()
                    self.audioRecorder = recorder
                    self.isRecording = true
                } catch {
                    self.audioRecorder = nil
                    self.isRecording = false
                }
            }
        }
    }

    private func stopRecording() {
        guard let recorder = audioRecorder, let controller = activePageController else { return }
        recorder.stop()
        recorder.prepareToPlay()
        let duration = recorder.currentTime
        let fileURL = recorder.url
        audioRecorder = nil
        isRecording = false

        let note = VoiceNote(duration: duration, fileName: fileURL.lastPathComponent)
        controller.voiceNotes.append(note)
    }

    private func playVoiceNote(_ note: VoiceNote) {
        guard let url = DrawingPersistence.existingVoiceNoteURL(fileName: note.fileName,
                                                                notebookID: pageStore.notebookIdentifier,
                                                                pageID: pageStore.activePageID) else { return }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
        } catch {
            audioPlayer = nil
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
        NotebookPageView(pageStore: NotebookPageStore(notebookID: UUID(),
                                                      pageModels: [NotebookPageModel(title: "Page 1")]))
            .previewInterfaceOrientation(.landscapeLeft)
            .previewDevice("iPad (10th generation)")
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType
    var completion: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (UIImage?) -> Void

        init(completion: @escaping (UIImage?) -> Void) {
            self.completion = completion
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            completion(nil)
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage
            completion(image)
        }
    }
}

struct VoiceNotesList: View {
    var notes: [VoiceNote]
    var onClose: () -> Void
    var onPlay: (VoiceNote) -> Void

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            List(notes) { note in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formatter.string(from: note.createdAt))
                            .font(.subheadline)
                        Text(String(format: "%.1f sec", note.duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: { onPlay(note) }) {
                        Image(systemName: "play.circle")
                    }
                }
            }
            .navigationTitle("Voice Notes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
        }
    }
}
