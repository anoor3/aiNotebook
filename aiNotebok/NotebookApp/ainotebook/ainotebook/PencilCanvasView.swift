import SwiftUI
import PencilKit
import UIKit

struct CanvasAttachment: Identifiable {
    let id: UUID
    let imageData: Data
    var center: CGPoint
    var size: CGSize
    var rotation: CGFloat
}

struct PencilCanvasView: UIViewRepresentable {
    @ObservedObject var controller: CanvasController
    var pageSize: CGSize
    var paperStyle: PaperStyle = .grid
    var attachments: [CanvasAttachment] = []
    var editingAttachmentID: UUID?
    var disableCanvasInteraction = false
    var onAttachmentChanged: ((CanvasAttachment) -> Void)?
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
        context.coordinator.attachmentsDidUpdate(attachmentsChanged: onAttachmentChanged,
                                                 tapOutside: onAttachmentTapOutside)
        return host
    }

    func updateUIView(_ uiView: ZoomableCanvasHostView, context: Context) {
        controller.applyCurrentTool()
        uiView.updatePageSize(pageSize)
        context.coordinator.attachmentsDidUpdate(attachmentsChanged: onAttachmentChanged,
                                                 tapOutside: onAttachmentTapOutside)
        uiView.updateAttachments(attachments,
                                 editingID: editingAttachmentID,
                                 delegate: context.coordinator)
        uiView.setPageInteractionEnabled(!disableCanvasInteraction)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller,
                    onAttachmentChanged: onAttachmentChanged,
                    onAttachmentTapOutside: onAttachmentTapOutside)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIScrollViewDelegate, AttachmentOverlayViewDelegate {
        private let controller: CanvasController
        private weak var hostView: ZoomableCanvasHostView?
        private var observingGesture = false
        private var onAttachmentChanged: ((CanvasAttachment) -> Void)?
        private var onAttachmentTapOutside: (() -> Void)?

        init(controller: CanvasController,
             onAttachmentChanged: ((CanvasAttachment) -> Void)? = nil,
             onAttachmentTapOutside: (() -> Void)? = nil) {
            self.controller = controller
            self.onAttachmentChanged = onAttachmentChanged
            self.onAttachmentTapOutside = onAttachmentTapOutside
        }

        func attach(hostView: ZoomableCanvasHostView) {
            self.hostView = hostView
            hostView.setScrollDelegate(self)

            // ensure initial render is crisp
            hostView.updateInk(with: controller.canvasView.drawing)

            if !observingGesture {
                controller.canvasView.drawingGestureRecognizer.addTarget(
                    self,
                    action: #selector(handleDrawingGesture(_:))
                )
                observingGesture = true
            }
        }

        func attachmentsDidUpdate(attachmentsChanged: ((CanvasAttachment) -> Void)? = nil,
                                   tapOutside: (() -> Void)? = nil) {
            if let attachmentsChanged {
                onAttachmentChanged = attachmentsChanged
            }
            if let tapOutside {
                onAttachmentTapOutside = tapOutside
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
            hostView?.updateInk(with: controller.canvasView.drawing)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            if scale < 1.0 {
                hostView?.resetZoom(animated: true)
                hostView?.updateZoomScale(1.0)
            } else {
                hostView?.updateZoomScale(scale)
            }
            hostView?.updateInk(with: controller.canvasView.drawing)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            // keep overlay & ink in sync if you’re compositing
            hostView?.updateInk(with: controller.canvasView.drawing)
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

        func attachmentOverlay(_ overlay: AttachmentOverlayView, didUpdate attachment: CanvasAttachment) {
            onAttachmentChanged?(attachment)
        }

        func attachmentOverlayDidTapOutside(_ overlay: AttachmentOverlayView) {
            onAttachmentTapOutside?()
        }
    }
}

final class ZoomableCanvasHostView: UIView {
    private let scrollView = CanvasScrollView()
    private let contentView = UIView()
    private let backgroundView = PageBackgroundView()
    private let gridView = GridPaperCanvasView()
    private let attachmentOverlayView = AttachmentOverlayView()
    private let inkView = CustomInkView()
    private let eraserOverlayView = EraserHighlightView()
    private let canvasView: PKCanvasView
    private let paperStyle: PaperStyle

    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?
    private var currentZoomScale: CGFloat = 1.0
    private let baseContentScale = UIScreen.main.scale
    private var lastInkRenderSize: CGSize = .zero

    private var pageSize: CGSize {
        didSet { updatePageSizeConstraints() }
    }

    var zoomableContentView: UIView { contentView }
    var eraserCoordinateSpace: UIView { eraserOverlayView }
    var currentZoomScaleFactor: CGFloat { max(1.0, currentZoomScale) }

    init(canvasView: PKCanvasView, pageSize: CGSize, paperStyle: PaperStyle) {
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
        inkView.setNeedsDisplay()
        lastInkRenderSize = .zero
        updateInk(with: canvasView.drawing)
        attachmentOverlayView.updateBounds(CGSize(width: newSize.width, height: newSize.height))
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

        // Ink view (usually raster-based)
        inkView.updateScale(targetScale)

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
        attachmentOverlayView.translatesAutoresizingMaskIntoConstraints = false
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
        contentView.addSubview(attachmentOverlayView)
        contentView.addSubview(inkView)
        contentView.addSubview(eraserOverlayView)
        contentView.addSubview(canvasView)

        let subviews = [backgroundView, gridView, attachmentOverlayView, inkView, eraserOverlayView, canvasView]
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
        inkView.setNeedsDisplay()
        updateInk(with: canvasView.drawing)
        attachmentOverlayView.updateBounds(CGSize(width: pageSize.width, height: pageSize.height))
    }

    func updateAttachments(_ attachments: [CanvasAttachment],
                           editingID: UUID?,
                           delegate: AttachmentOverlayViewDelegate?) {
        attachmentOverlayView.delegate = delegate
        attachmentOverlayView.update(attachments: attachments,
                                     editingID: editingID,
                                     boundsSize: pageSize)
    }

    func setPageInteractionEnabled(_ enabled: Bool) {
        canvasView.isUserInteractionEnabled = enabled
        scrollView.isScrollEnabled = enabled
        scrollView.panGestureRecognizer.isEnabled = enabled
        scrollView.pinchGestureRecognizer?.isEnabled = enabled
    }
}

protocol AttachmentOverlayViewDelegate: AnyObject {
    func attachmentOverlay(_ overlay: AttachmentOverlayView, didUpdate attachment: CanvasAttachment)
    func attachmentOverlayDidTapOutside(_ overlay: AttachmentOverlayView)
}

final class AttachmentOverlayView: UIView, UIGestureRecognizerDelegate {
    weak var delegate: AttachmentOverlayViewDelegate?
    private var attachmentViews: [UUID: AttachmentItemView] = [:]
    private var editingID: UUID?
    private var pageBounds: CGRect = .zero
    private lazy var backgroundTapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap(_:)))
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        gesture.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        return gesture
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        addGestureRecognizer(backgroundTapGesture)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateBounds(_ size: CGSize) {
        pageBounds = CGRect(origin: .zero, size: size)
        attachmentViews.values.forEach { $0.pageBounds = pageBounds }
    }

    func update(attachments: [CanvasAttachment], editingID: UUID?, boundsSize: CGSize) {
        self.editingID = editingID
        updateBounds(boundsSize)
        let attachmentIDs = Set(attachments.map { $0.id })

        for (id, view) in attachmentViews where !attachmentIDs.contains(id) {
            view.removeFromSuperview()
            attachmentViews.removeValue(forKey: id)
        }

        for attachment in attachments {
            let view: AttachmentItemView
            if let existing = attachmentViews[attachment.id] {
                view = existing
                view.attachment = attachment
                view.pageBounds = pageBounds
            } else {
                let newView = AttachmentItemView(attachment: attachment)
                newView.pageBounds = pageBounds
                newView.onCommitTransform = { [weak self] updated in
                    guard let self else { return }
                    self.delegate?.attachmentOverlay(self, didUpdate: updated)
                }
                attachmentViews[attachment.id] = newView
                addSubview(newView)
                view = newView
            }

            view.isEditing = attachment.id == editingID
        }

        let isEditing = editingID != nil
        isUserInteractionEnabled = isEditing
        backgroundTapGesture.isEnabled = isEditing
    }

    @objc private func handleBackgroundTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        delegate?.attachmentOverlayDidTapOutside(self)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === backgroundTapGesture,
              let editingID,
              let view = attachmentViews[editingID] else {
            return true
        }
        let location = touch.location(in: self)
        return !view.frame.contains(location)
    }
}

final class AttachmentItemView: UIView, UIGestureRecognizerDelegate {
    var attachment: CanvasAttachment {
        didSet { applyCurrentState() }
    }
    var pageBounds: CGRect = .zero {
        didSet { clampToBounds() }
    }
    var isEditing: Bool = false {
        didSet { updateEditingState() }
    }
    var onCommitTransform: ((CanvasAttachment) -> Void)?

    private let imageView = UIImageView()
    private let borderLayer = CAShapeLayer()
    private lazy var panGesture: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        gesture.delegate = self
        gesture.minimumNumberOfTouches = 1
        gesture.maximumNumberOfTouches = 1
        gesture.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        return gesture
    }()
    private lazy var pinchGesture: UIPinchGestureRecognizer = {
        let gesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        gesture.delegate = self
        gesture.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        return gesture
    }()

    private var initialCenter: CGPoint = .zero
    private var initialSize: CGSize = .zero

    init(attachment: CanvasAttachment) {
        self.attachment = attachment
        super.init(frame: .zero)
        configure()
        applyCurrentState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = true
        clipsToBounds = false
        imageView.translatesAutoresizingMaskIntoConstraints = true
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        addSubview(imageView)

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.2
        layer.shadowOffset = CGSize(width: 0, height: 3)
        layer.shadowRadius = 6

        borderLayer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.7).cgColor
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.lineWidth = 2
        borderLayer.isHidden = true
        layer.addSublayer(borderLayer)

        addGestureRecognizer(panGesture)
        addGestureRecognizer(pinchGesture)
    }

    private func applyCurrentState() {
        guard let renderedImage = UIImage(data: attachment.imageData) else { return }
        imageView.image = renderedImage
        bounds = CGRect(origin: .zero, size: attachment.size)
        center = attachment.center
        transform = CGAffineTransform(rotationAngle: attachment.rotation)
        clampToBounds()
        updateShadowPath()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        updateShadowPath()
    }

    private func updateShadowPath() {
        borderLayer.path = UIBezierPath(roundedRect: bounds, cornerRadius: 18).cgPath
    }

    private func updateEditingState() {
        panGesture.isEnabled = isEditing
        pinchGesture.isEnabled = isEditing
        borderLayer.isHidden = !isEditing
    }

    private func clampToBounds() {
        guard pageBounds.width > 0, pageBounds.height > 0 else { return }
        var newCenter = attachment.center
        let halfWidth = attachment.size.width / 2
        let halfHeight = attachment.size.height / 2

        newCenter.x = max(halfWidth, min(pageBounds.width - halfWidth, newCenter.x))
        newCenter.y = max(halfHeight, min(pageBounds.height - halfHeight, newCenter.y))
        attachment.center = newCenter
        center = newCenter
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard isEditing else { return }
        switch gesture.state {
        case .began:
            initialCenter = attachment.center
        case .changed:
            let translation = gesture.translation(in: superview)
            var updatedCenter = CGPoint(x: initialCenter.x + translation.x,
                                        y: initialCenter.y + translation.y)
            updatedCenter = clampedCenter(for: updatedCenter, size: attachment.size)
            attachment.center = updatedCenter
            center = updatedCenter
        case .ended, .cancelled, .failed:
            onCommitTransform?(attachment)
        default:
            break
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard isEditing else { return }
        switch gesture.state {
        case .began:
            initialSize = attachment.size
            gesture.scale = 1.0
        case .changed:
            let aspect = initialSize.height / max(initialSize.width, 1)
            let minDimension: CGFloat = 120
            let maxWidth = pageBounds.width * 0.95
            let maxHeight = pageBounds.height * 0.95

            var newWidth = initialSize.width * gesture.scale
            newWidth = max(minDimension, min(newWidth, maxWidth))
            var newHeight = newWidth * aspect

            if newHeight < minDimension {
                newHeight = minDimension
                newWidth = newHeight / max(aspect, 0.01)
            }

            if newHeight > maxHeight {
                newHeight = maxHeight
                newWidth = newHeight / max(aspect, 0.01)
            }

            attachment.size = CGSize(width: newWidth, height: newHeight)
            bounds = CGRect(origin: .zero, size: attachment.size)
            updateShadowPath()
            clampToBounds()
        case .ended, .cancelled, .failed:
            onCommitTransform?(attachment)
        default:
            break
        }
    }

    private func clampedCenter(for center: CGPoint, size: CGSize) -> CGPoint {
        guard pageBounds.width > 0, pageBounds.height > 0 else { return center }
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        var clamped = center
        clamped.x = max(halfWidth, min(pageBounds.width - halfWidth, clamped.x))
        clamped.y = max(halfHeight, min(pageBounds.height - halfHeight, clamped.y))
        return clamped
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
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
