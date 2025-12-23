import SwiftUI

struct PencilCanvasView: UIViewRepresentable {
    @ObservedObject var controller: CanvasController
    var pageSize: CGSize
    var paperStyle: PaperStyle = .grid

    func makeUIView(context: Context) -> ZoomableCanvasHostView {
        controller.applyCurrentTool()
        controller.updateUndoState()

        let host = ZoomableCanvasHostView(canvasView: controller.canvasView,
                                          pageSize: pageSize,
                                          paperStyle: paperStyle)
        context.coordinator.attach(hostView: host)
        return host
    }

    func updateUIView(_ uiView: ZoomableCanvasHostView, context: Context) {
        controller.applyCurrentTool()
        uiView.updatePageSize(pageSize)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        private let controller: CanvasController
        private weak var hostView: ZoomableCanvasHostView?

        init(controller: CanvasController) {
            self.controller = controller
        }

        func attach(hostView: ZoomableCanvasHostView) {
            self.hostView = hostView
            hostView.setScrollDelegate(self)
            hostView.updateInk(with: controller.currentDrawingValue())
            controller.canvasView.onEraserOverlay = { [weak self] event, point, width in
                guard let host = self?.hostView else { return }
                let scaledWidth = width * host.currentZoomScaleFactor
                switch event {
                case .began:
                    host.beginEraserOverlay(at: point, width: scaledWidth)
                case .moved:
                    host.continueEraserOverlay(at: point, width: scaledWidth)
                case .ended:
                    host.finishEraserOverlay()
                }
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hostView?.zoomableContentView
        }

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            hostView?.prepareForZoomInteraction()
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            hostView?.setNeedsGridRedraw()
            hostView?.updateZoomScale(scrollView.zoomScale)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            if scale < 1.0 {
                hostView?.resetZoom(animated: true)
                hostView?.updateZoomScale(1.0)
            } else {
                hostView?.updateZoomScale(scale)
            }
        }
    }
}

final class ZoomableCanvasHostView: UIView {
    private let scrollView = CanvasScrollView()
    private let contentView = UIView()
    private let backgroundView = PageBackgroundView()
    private let gridView = GridPaperCanvasView()
    private let eraserOverlayView = EraserHighlightView()
    private let canvasView: DrawingCanvasView
    private let paperStyle: PaperStyle
    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?
    private var currentZoomScale: CGFloat = 1.0
    private let baseContentScale = UIScreen.main.scale

    private var pageSize: CGSize {
        didSet { updatePageSizeConstraints() }
    }

    var zoomableContentView: UIView { contentView }
    var eraserCoordinateSpace: UIView { eraserOverlayView }
    var currentZoomScaleFactor: CGFloat { max(1.0, currentZoomScale) }

    init(canvasView: DrawingCanvasView, pageSize: CGSize, paperStyle: PaperStyle) {
        self.canvasView = canvasView
        self.pageSize = pageSize
        self.paperStyle = paperStyle
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
        canvasView.setNeedsDisplay()
    }

    func updateZoomScale(_ scale: CGFloat) {
        currentZoomScale = scale
        let shouldApplyCorners = scale <= 1.02

        backgroundView.layer.cornerRadius = shouldApplyCorners ? 32 : 0
        backgroundView.layer.masksToBounds = shouldApplyCorners

        gridView.layer.cornerRadius = shouldApplyCorners ? 32 : 0
        gridView.layer.masksToBounds = shouldApplyCorners

        canvasView.layer.cornerRadius = shouldApplyCorners ? 32 : 0
        canvasView.clipsToBounds = shouldApplyCorners

        let effectiveScale = max(1.0, scale)
        let targetScale = baseContentScale * effectiveScale

        if abs(gridView.contentScaleFactor - targetScale) > 0.01 {
            gridView.contentScaleFactor = targetScale
            gridView.layer.contentsScale = targetScale
            gridView.setNeedsDisplay()
        }

        canvasView.updateScale(targetScale)
    }

    func updateInk(with drawing: InkDrawing) {
        canvasView.setDrawing(drawing)
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

    private func configureHierarchy() {
        backgroundColor = UIColor(red: 252/255, green: 244/255, blue: 220/255, alpha: 1)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.clipsToBounds = false
        contentView.layer.cornerRadius = 0

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 3.0
        scrollView.bouncesZoom = true
        scrollView.isMultipleTouchEnabled = true
        scrollView.backgroundColor = UIColor(red: 252/255, green: 244/255, blue: 220/255, alpha: 1)
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
        canvasView.translatesAutoresizingMaskIntoConstraints = false

        canvasView.removeFromSuperview()
        canvasView.backgroundColor = .clear
        canvasView.alpha = 1.0

        backgroundView.layer.cornerRadius = 32
        backgroundView.layer.masksToBounds = true
        gridView.layer.cornerRadius = 32
        gridView.layer.masksToBounds = true
        gridView.paperStyle = paperStyle
        canvasView.layer.cornerRadius = 32
        canvasView.clipsToBounds = true

        contentView.addSubview(backgroundView)
        contentView.addSubview(gridView)
        contentView.addSubview(canvasView)
        contentView.addSubview(eraserOverlayView)

        let subviews = [backgroundView, gridView, canvasView, eraserOverlayView]
        subviews.forEach { subview in
            NSLayoutConstraint.activate([
                subview.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                subview.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                subview.topAnchor.constraint(equalTo: contentView.topAnchor),
                subview.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
        }
        prepareForZoomInteraction()
    }

    private func updatePageSizeConstraints() {
        widthConstraint?.constant = pageSize.width
        heightConstraint?.constant = pageSize.height
        layoutIfNeeded()
        canvasView.setNeedsDisplay()
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
