import SwiftUI
import PencilKit
import UIKit

struct PencilCanvasView: UIViewRepresentable {
    @ObservedObject var controller: CanvasController
    var pageSize: CGSize
    var paperStyle: PaperStyle = .grid
    var attachments: [CanvasAttachment] = []
    @Binding var editingAttachmentID: UUID?
    var onAttachmentChanged: ((CanvasAttachment) -> Void)?
    var onAttachmentDeleted: ((UUID) -> Void)?
    var onAttachmentDuplicated: ((CanvasAttachment) -> Void)?
    var onAttachmentCropped: ((CanvasAttachment) -> Void)?
    var onAttachmentDone: (() -> Void)?
    var onAttachmentTapOutside: (() -> Void)?

    func makeUIView(context: Context) -> ZoomableCanvasHostView {
        controller.canvasView.delegate = context.coordinator
        controller.disableScribbleInteraction()
        controller.applyCurrentTool()
        controller.updateUndoState()

        let host = ZoomableCanvasHostView(
            canvasView: controller.canvasView,
            pageSize: pageSize,
            paperStyle: paperStyle
        )
        context.coordinator.attach(hostView: host)
        updateOverlay(in: host)
        return host
    }

    func updateUIView(_ uiView: ZoomableCanvasHostView, context: Context) {
        controller.applyCurrentTool()
        uiView.updatePageSize(pageSize)
        updateOverlay(in: uiView)
        context.coordinator.handleToolChange(newTool: controller.tool)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIScrollViewDelegate {
        private let controller: CanvasController
        private weak var hostView: ZoomableCanvasHostView?
        private var observingGesture = false
        private var lastTool: CanvasDrawingTool

        init(controller: CanvasController) {
            self.controller = controller
            self.lastTool = controller.tool
        }

        func attach(hostView: ZoomableCanvasHostView) {
            self.hostView = hostView
            hostView.setScrollDelegate(self)

            // ensure initial render is crisp
            hostView.updateInk(with: controller.canvasView.drawing)
            handleToolChange(newTool: controller.tool)

            if !observingGesture {
                controller.canvasView.drawingGestureRecognizer.addTarget(
                    self,
                    action: #selector(handleDrawingGesture(_:))
                )
                observingGesture = true
            }
        }
        
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            controller.updateUndoState()
            hostView?.updateInk(with: canvasView.drawing)
            if controller.tool != .eraser {
                hostView?.finishEraserOverlay()
            }
            controller.publishDrawingChange()
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hostView?.zoomableContentView
        }

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            hostView?.prepareForZoomInteraction()
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            let z = scrollView.zoomScale
            hostView?.updateZoomScale(z)

            hostView?.setNeedsGridRedraw()
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            if scale < 1.0 {
                hostView?.resetZoom(animated: true)
                hostView?.updateZoomScale(1.0)
            } else {
                hostView?.updateZoomScale(scale)
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            // keep overlay & ink in sync if you’re compositing
        }

        func handleToolChange(newTool: CanvasDrawingTool) {
            guard let hostView else {
                lastTool = newTool
                return
            }

            if lastTool != .selection, newTool == .selection {
                hostView.beginSelection(for: controller.canvasView.drawing)
            } else if lastTool == .selection, newTool != .selection {
                hostView.endSelection(with: controller.canvasView.drawing)
            }

            lastTool = newTool
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            hostView?.updateInk(with: canvasView.drawing)
        }

        @objc private func handleDrawingGesture(_ gesture: UIGestureRecognizer) {
            guard let host = hostView, controller.tool == .eraser else { return }
            let point = gesture.location(in: host.eraserCoordinateSpace)

            // IMPORTANT:
            // Width should scale visually with zoom, otherwise it looks wrong.
            // But DO NOT multiply by insane values — just proportional to zoom.
            let width = controller.strokeWidth * max(1.0, host.currentZoomScaleFactor)

            switch gesture.state {
            case .began:
                host.beginEraserOverlay(at: point, width: width)
            case .changed:
                host.continueEraserOverlay(at: point, width: width)
            case .ended, .cancelled, .failed:
                host.finishEraserOverlay()
            default:
                break
            }
        }

        deinit {
            if observingGesture {
                controller.canvasView.drawingGestureRecognizer.removeTarget(
                    self,
                    action: #selector(handleDrawingGesture(_:))
                )
            }
        }

    }

    private func updateOverlay(in hostView: ZoomableCanvasHostView) {
        let overlayView = AttachmentOverlay(attachments: attachments,
                                            pageSize: pageSize,
                                            editingAttachmentID: $editingAttachmentID,
                                            onUpdate: { attachment in
                                                onAttachmentChanged?(attachment)
                                            },
                                            onDelete: { id in
                                                onAttachmentDeleted?(id)
                                            },
                                            onDuplicate: { attachment in
                                                onAttachmentDuplicated?(attachment)
                                            },
                                            onCrop: { attachment in
                                                onAttachmentCropped?(attachment)
                                            },
                                            onDoneEditing: {
                                                onAttachmentDone?()
                                            },
                                            onTapBackground: {
                                                onAttachmentTapOutside?()
                                            })
        hostView.updateAttachmentOverlay(overlayView)
    }
}

final class ZoomableCanvasHostView: UIView {
    private let scrollView = CanvasScrollView()
    private let contentView = UIView()
    private let backgroundView = PageBackgroundView()
    private let gridView = GridPaperCanvasView()
    let attachmentContainer = UIView()
    private let inkView: TiledInkView
    private let eraserOverlayView = EraserHighlightView()
    private let canvasView: PKCanvasView
    private let paperStyle: PaperStyle
    private var attachmentHostingController: UIHostingController<AttachmentOverlay>?

    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?
    private var currentZoomScale: CGFloat = 1.0
    private let baseContentScale = UIScreen.main.scale
    private var lastInkRenderSize: CGSize = .zero

    private var pageSize: CGSize {
        didSet { updatePageSizeConstraints() }
    }
    private var selectionHiddenRect: CGRect?

    var zoomableContentView: UIView { contentView }
    var eraserCoordinateSpace: UIView { eraserOverlayView }
    var currentZoomScaleFactor: CGFloat { max(1.0, currentZoomScale) }

    init(canvasView: PKCanvasView, pageSize: CGSize, paperStyle: PaperStyle) {
        self.canvasView = canvasView
        self.pageSize = pageSize
        self.paperStyle = paperStyle
        self.inkView = TiledInkView(pageSize: pageSize)
        super.init(frame: .zero)
        configureHierarchy()
        updateZoomScale(1.0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setScrollDelegate(_ delegate: UIScrollViewDelegate) {
        scrollView.delegate = delegate
    }

    func resetZoom(animated: Bool) {
        scrollView.setZoomScale(1.0, animated: animated)
        prepareForZoomInteraction()
        updateZoomScale(1.0)
    }

    func prepareForZoomInteraction() {
        scrollView.panGestureRecognizer.minimumNumberOfTouches = scrollView.zoomScale > 1.02 ? 1 : 2
    }

    func setNeedsGridRedraw() {
        gridView.setNeedsDisplay()
        prepareForZoomInteraction()
    }

    func updatePageSize(_ newSize: CGSize) {
        guard pageSize != newSize else { return }
        pageSize = newSize
        inkView.updatePageSize(pageSize)
        inkView.clearAll()
        updateInk(with: canvasView.drawing)
    }

    /// Geometry-only changes (corners, masks). Do NOT do resolution changes here.
    func updateZoomScale(_ scale: CGFloat) {
        currentZoomScale = scale
        let shouldApplyCorners = scale <= 1.02

        backgroundView.layer.cornerRadius = shouldApplyCorners ? 32 : 0
        backgroundView.layer.masksToBounds = shouldApplyCorners

        gridView.layer.cornerRadius = shouldApplyCorners ? 32 : 0
        gridView.layer.masksToBounds = shouldApplyCorners

        canvasView.layer.cornerRadius = shouldApplyCorners ? 32 : 0
        canvasView.clipsToBounds = shouldApplyCorners
    }

    /// 🔥 Resolution-only changes (prevents blur). Safe + necessary.
    func updateRenderScale(_ zoomScale: CGFloat) {
        let effective = max(1.0, zoomScale)
        let targetScale = baseContentScale * effective

        // Grid redraw crisp
        if abs(gridView.contentScaleFactor - targetScale) > 0.01 {
            gridView.contentScaleFactor = targetScale
            gridView.layer.contentsScale = targetScale
            gridView.setNeedsDisplay()
        }

        // Canvas crisp (does NOT change drawing coordinates)
        if abs(canvasView.contentScaleFactor - targetScale) > 0.01 {
            canvasView.contentScaleFactor = targetScale
            canvasView.layer.contentsScale = targetScale
            canvasView.setNeedsDisplay()
        }

        // If PencilKit internally uses a subview for rendering, keep it crisp too
        if let drawingView = canvasView.drawingGestureRecognizer.view ?? canvasView.subviews.first {
            if abs(drawingView.contentScaleFactor - targetScale) > 0.01 {
                drawingView.contentScaleFactor = targetScale
                drawingView.layer.contentsScale = targetScale
                drawingView.setNeedsDisplay()
            }
        }
    }

    func updateInk(with drawing: PKDrawing) {
        // feed zoom so rasterization matches current zoom level
        inkView.update(drawing: drawing, scale: max(1.0, currentZoomScale))
        lastInkRenderSize = inkView.bounds.size
    }

    func beginEraserOverlay(at point: CGPoint, width: CGFloat) {
        eraserOverlayView.beginStroke(at: point, width: width)
    }

    func continueEraserOverlay(at point: CGPoint, width: CGFloat) {
        eraserOverlayView.continueStroke(at: point, width: width)
    }

    func finishEraserOverlay() {
        eraserOverlayView.endStroke()
    }

    func beginSelection(for drawing: PKDrawing) {
        let rect = expandedSelectionRect(from: drawing.bounds)
        selectionHiddenRect = rect
        inkView.hideTiles(in: rect)
    }

    func endSelection(with drawing: PKDrawing) {
        let newRect = expandedSelectionRect(from: drawing.bounds)
        let dirty = selectionHiddenRect.map { $0.union(newRect) } ?? newRect
        inkView.showTiles(in: dirty, drawing: drawing, scale: max(1.0, currentZoomScale))
        selectionHiddenRect = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inkBounds = inkView.bounds.size
        if inkBounds.width > 0,
           inkBounds.height > 0,
           inkBounds != .zero,
           inkBounds != lastInkRenderSize {
            lastInkRenderSize = inkBounds
            updateInk(with: canvasView.drawing)
        }
    }

    private func configureHierarchy() {
        // Outer container
        backgroundColor = .clear

        // Page owns the color (prevents border bleed)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.clipsToBounds = false
        contentView.layer.cornerRadius = 0
        contentView.backgroundColor = UIColor(red: 252/255, green: 244/255, blue: 220/255, alpha: 1)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 3.0
        scrollView.bouncesZoom = true
        scrollView.isMultipleTouchEnabled = true
        scrollView.backgroundColor = .clear
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.pinchGestureRecognizer?.requiresExclusiveTouchType = false
        scrollView.panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        scrollView.pinchGestureRecognizer?.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
        scrollView.contentInsetAdjustmentBehavior = .never

        addSubview(scrollView)
        scrollView.addSubview(contentView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let leading = contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor)
        let trailing = contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor)
        let top = contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor)
        let bottom = contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor)
        widthConstraint = contentView.widthAnchor.constraint(equalToConstant: pageSize.width)
        heightConstraint = contentView.heightAnchor.constraint(equalToConstant: pageSize.height)

        var constraints = [leading, trailing, top, bottom]
        if let widthConstraint = widthConstraint { constraints.append(widthConstraint) }
        if let heightConstraint = heightConstraint { constraints.append(heightConstraint) }
        NSLayoutConstraint.activate(constraints)

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        gridView.translatesAutoresizingMaskIntoConstraints = false
        attachmentContainer.translatesAutoresizingMaskIntoConstraints = false
        inkView.translatesAutoresizingMaskIntoConstraints = false
        eraserOverlayView.translatesAutoresizingMaskIntoConstraints = false
        canvasView.translatesAutoresizingMaskIntoConstraints = false

        canvasView.removeFromSuperview()
        canvasView.backgroundColor = .clear
        canvasView.alpha = 1.0

        backgroundView.layer.cornerRadius = 32
        backgroundView.layer.masksToBounds = true

        gridView.layer.cornerRadius = 32
        gridView.layer.masksToBounds = true
        gridView.paperStyle = paperStyle

        inkView.isUserInteractionEnabled = false

        canvasView.layer.cornerRadius = 32
        canvasView.clipsToBounds = true

        contentView.addSubview(backgroundView)
        contentView.addSubview(gridView)
        contentView.addSubview(attachmentContainer)
        contentView.addSubview(inkView)
        contentView.addSubview(eraserOverlayView)
        contentView.addSubview(canvasView)

        attachmentContainer.isUserInteractionEnabled = true
        attachmentContainer.backgroundColor = .clear
        let subviews = [backgroundView, gridView, attachmentContainer, inkView, eraserOverlayView, canvasView]
        subviews.forEach { subview in
            NSLayoutConstraint.activate([
                subview.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                subview.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                subview.topAnchor.constraint(equalTo: contentView.topAnchor),
                subview.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
        }

        // Initial state
        prepareForZoomInteraction()
    }

    private func updatePageSizeConstraints() {
        widthConstraint?.constant = pageSize.width
        heightConstraint?.constant = pageSize.height
        layoutIfNeeded()
        inkView.updatePageSize(pageSize)
        updateInk(with: canvasView.drawing)
    }

    private func expandedSelectionRect(from rect: CGRect) -> CGRect {
        let padding: CGFloat = 32
        var target = rect.isNull || rect.isEmpty ? CGRect(origin: .zero, size: pageSize) : rect
        target = target.insetBy(dx: -padding, dy: -padding)
        let pageRect = CGRect(origin: .zero, size: pageSize)
        target = target.intersection(pageRect)
        if target.isNull {
            return pageRect
        }
        return target
    }

    func updateAttachmentOverlay(_ overlay: AttachmentOverlay) {
        if let hosting = attachmentHostingController {
            hosting.rootView = overlay
        } else {
            let hosting = UIHostingController(rootView: overlay)
            hosting.view.backgroundColor = .clear
            hosting.view.frame = attachmentContainer.bounds
            hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            attachmentContainer.addSubview(hosting.view)
            attachmentHostingController = hosting
        }
    }

}

final class CanvasScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool {
        true
    }
}

final class EraserHighlightView: UIView {
    private let shapeLayer = CAShapeLayer()
    private var path = UIBezierPath()

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        isUserInteractionEnabled = false
        backgroundColor = .clear
        shapeLayer.strokeColor = UIColor.white.withAlphaComponent(0.4).cgColor
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.lineCap = .round
        shapeLayer.lineJoin = .round
        shapeLayer.shadowColor = UIColor.black.cgColor
        shapeLayer.shadowOpacity = 0.2
        shapeLayer.shadowRadius = 4
        layer.addSublayer(shapeLayer)
    }

    func beginStroke(at point: CGPoint, width: CGFloat) {
        path = UIBezierPath()
        path.move(to: point)
        updateLayer(lineWidth: width)
    }

    func continueStroke(at point: CGPoint, width: CGFloat) {
        path.addLine(to: point)
        updateLayer(lineWidth: width)
    }

    func endStroke() {
        path.removeAllPoints()
        shapeLayer.path = nil
    }

    private func updateLayer(lineWidth: CGFloat) {
        shapeLayer.path = path.cgPath
        shapeLayer.lineWidth = max(4, lineWidth + 12)
    }
}

final class PageBackgroundView: UIView {
    private let pageColor = UIColor(red: 252/255, green: 244/255, blue: 220/255, alpha: 1.0)

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = pageColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class GridPaperCanvasView: UIView {
    var paperStyle: PaperStyle = .grid
    private let gridColor = UIColor(red: 205/255, green: 205/255, blue: 185/255, alpha: 0.85)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        contentScaleFactor = UIScreen.main.scale
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        switch paperStyle {
        case .grid:
            context.setStrokeColor(gridColor.cgColor)
            context.setLineWidth(1.0 / contentScaleFactor)
            drawGrid(in: context, rect: rect)
        case .dot:
            context.setFillColor(gridColor.withAlphaComponent(0.4).cgColor)
            drawDots(in: context, rect: rect)
        case .blank:
            break
        case .lined:
            context.setStrokeColor(UIColor(red: 0.63, green: 0.7, blue: 0.86, alpha: 0.5).cgColor)
            context.setLineWidth(1.0 / contentScaleFactor)
            drawLines(in: context, rect: rect)
        }
    }

    private func drawGrid(in context: CGContext, rect: CGRect) {
        let spacing: CGFloat = 32
        let insetRect = rect.insetBy(dx: 0.5, dy: 0.5)

        var x = insetRect.minX
        while x <= insetRect.maxX + 0.5 {
            context.move(to: CGPoint(x: x, y: insetRect.minY))
            context.addLine(to: CGPoint(x: x, y: insetRect.maxY))
            x += spacing
        }

        var y = insetRect.minY
        while y <= insetRect.maxY + 0.5 {
            context.move(to: CGPoint(x: insetRect.minX, y: y))
            context.addLine(to: CGPoint(x: insetRect.maxX, y: y))
            y += spacing
        }

        context.strokePath()
    }

    private func drawDots(in context: CGContext, rect: CGRect) {
        let spacing: CGFloat = 28
        let dotSize: CGFloat = 2
        let insetRect = rect.insetBy(dx: 0.5, dy: 0.5)

        for x in stride(from: insetRect.minX, through: insetRect.maxX, by: spacing) {
            for y in stride(from: insetRect.minY, through: insetRect.maxY, by: spacing) {
                let dotRect = CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize)
                context.fillEllipse(in: dotRect)
            }
        }
    }

    private func drawLines(in context: CGContext, rect: CGRect) {
        let spacing: CGFloat = 32
        let insetRect = rect.insetBy(dx: 0.5, dy: 0.5)

        for y in stride(from: insetRect.minY, through: insetRect.maxY, by: spacing) {
            context.move(to: CGPoint(x: insetRect.minX, y: y))
            context.addLine(to: CGPoint(x: insetRect.maxX, y: y))
        }
        context.strokePath()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        setNeedsDisplay()
    }
}
