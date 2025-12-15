import SwiftUI
import PencilKit

struct PencilCanvasView: UIViewRepresentable {
    @ObservedObject var controller: CanvasController
    var pageSize: CGSize

    func makeUIView(context: Context) -> ZoomableCanvasHostView {
        controller.canvasView.delegate = context.coordinator
        controller.disableScribbleInteraction()
        controller.applyCurrentTool()
        controller.updateUndoState()

        let host = ZoomableCanvasHostView(canvasView: controller.canvasView, pageSize: pageSize)
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

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIScrollViewDelegate {
        private let controller: CanvasController
        private weak var hostView: ZoomableCanvasHostView?

        init(controller: CanvasController) {
            self.controller = controller
        }

        func attach(hostView: ZoomableCanvasHostView) {
            self.hostView = hostView
            hostView.setScrollDelegate(self)
            hostView.updateInk(with: controller.canvasView.drawing)
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            controller.updateUndoState()
            hostView?.updateInk(with: canvasView.drawing)
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
    private let inkView = CustomInkView()
    private let canvasView: PKCanvasView
    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?
    private var currentZoomScale: CGFloat = 1.0
    private let baseContentScale = UIScreen.main.scale

    private var pageSize: CGSize {
        didSet { updatePageSizeConstraints() }
    }

    var zoomableContentView: UIView { contentView }

    init(canvasView: PKCanvasView, pageSize: CGSize) {
        self.canvasView = canvasView
        self.pageSize = pageSize
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
        inkView.setNeedsDisplay()
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

        inkView.updateScale(targetScale)

        if abs(gridView.contentScaleFactor - targetScale) > 0.01 {
            gridView.contentScaleFactor = targetScale
            gridView.layer.contentsScale = targetScale
            gridView.setNeedsDisplay()
        }

        if abs(canvasView.contentScaleFactor - targetScale) > 0.01 {
            canvasView.contentScaleFactor = targetScale
            canvasView.layer.contentsScale = targetScale
            canvasView.setNeedsDisplay()
        }

        if let drawingView = canvasView.drawingGestureRecognizer.view ?? canvasView.subviews.first {
            if abs(drawingView.contentScaleFactor - targetScale) > 0.01 {
                drawingView.contentScaleFactor = targetScale
                drawingView.layer.contentsScale = targetScale
                drawingView.setNeedsDisplay()
            }
        }
    }

    func updateInk(with drawing: PKDrawing) {
        inkView.update(drawing: drawing, scale: max(1.0, currentZoomScale))
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
        scrollView.canCancelContentTouches = false
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
        inkView.translatesAutoresizingMaskIntoConstraints = false
        canvasView.translatesAutoresizingMaskIntoConstraints = false

        canvasView.removeFromSuperview()
        canvasView.backgroundColor = .clear
        canvasView.alpha = 1.0

        backgroundView.layer.cornerRadius = 32
        backgroundView.layer.masksToBounds = true
        gridView.layer.cornerRadius = 32
        gridView.layer.masksToBounds = true
        inkView.isUserInteractionEnabled = false
        canvasView.layer.cornerRadius = 32
        canvasView.clipsToBounds = true

        contentView.addSubview(backgroundView)
        contentView.addSubview(gridView)
        contentView.addSubview(inkView)
        contentView.addSubview(canvasView)

        let subviews = [backgroundView, gridView, inkView, canvasView]
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
        inkView.setNeedsDisplay()
    }
}

final class CanvasScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool {
        false
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
    private let spacing: CGFloat = 32
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
        let scale = contentScaleFactor
        let lineWidth = 1.0 / scale
        context.setStrokeColor(gridColor.cgColor)
        context.setLineWidth(lineWidth)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        let insetRect = rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)

        var x = insetRect.minX
        while x <= insetRect.maxX + lineWidth {
            context.move(to: CGPoint(x: x, y: insetRect.minY))
            context.addLine(to: CGPoint(x: x, y: insetRect.maxY))
            x += spacing
        }

        var y = insetRect.minY
        while y <= insetRect.maxY + lineWidth {
            context.move(to: CGPoint(x: insetRect.minX, y: y))
            context.addLine(to: CGPoint(x: insetRect.maxX, y: y))
            y += spacing
        }

        context.strokePath()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        setNeedsDisplay()
    }
}
