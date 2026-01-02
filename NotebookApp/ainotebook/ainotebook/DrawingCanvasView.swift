import UIKit

enum EraserOverlayEvent {
    case began
    case moved
    case ended
}

final class DrawingCanvasView: UIView {
    var onStrokeCommitted: ((InkStroke) -> Void)?
    var onEraserOverlay: ((EraserOverlayEvent, CGPoint, CGFloat) -> Void)?
    var onAttachmentsChanged: (([PageImageAttachment]) -> Void)?

    private(set) var drawing: InkDrawing = .empty {
        didSet {
            inkView.update(drawing: drawing, scale: currentScale)
        }
    }

    private var attachments: [PageImageAttachment] = []
    private let attachmentsView = AttachmentContainerView()
    private let inkView = CustomInkView()
    private let currentStrokeLayer = CAShapeLayer()
    private var activeSamples: [StrokePoint] = []
    private var isEraser = false
    private var strokeColor: UIColor = UIColor(red: 0.12, green: 0.26, blue: 0.52, alpha: 1.0)
    private var strokeWidth: CGFloat = 3.2
    private var currentScale: CGFloat = UIScreen.main.scale

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        isOpaque = false
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        isExclusiveTouch = false

        attachmentsView.translatesAutoresizingMaskIntoConstraints = false
        attachmentsView.onAttachmentsUpdated = { [weak self] updated in
            self?.attachments = updated
            self?.onAttachmentsChanged?(updated)
        }
        addSubview(attachmentsView)

        inkView.translatesAutoresizingMaskIntoConstraints = false
        inkView.isUserInteractionEnabled = false
        inkView.layer.masksToBounds = false
        addSubview(inkView)

        NSLayoutConstraint.activate([
            attachmentsView.leadingAnchor.constraint(equalTo: leadingAnchor),
            attachmentsView.trailingAnchor.constraint(equalTo: trailingAnchor),
            attachmentsView.topAnchor.constraint(equalTo: topAnchor),
            attachmentsView.bottomAnchor.constraint(equalTo: bottomAnchor),
            inkView.leadingAnchor.constraint(equalTo: leadingAnchor),
            inkView.trailingAnchor.constraint(equalTo: trailingAnchor),
            inkView.topAnchor.constraint(equalTo: topAnchor),
            inkView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        currentStrokeLayer.strokeColor = strokeColor.cgColor
        currentStrokeLayer.fillColor = UIColor.clear.cgColor
        currentStrokeLayer.lineCap = .round
        currentStrokeLayer.lineJoin = .round
        currentStrokeLayer.lineWidth = strokeWidth
        layer.addSublayer(currentStrokeLayer)
    }

    func setDrawing(_ drawing: InkDrawing) {
        self.drawing = drawing
    }

    func setAttachments(_ attachments: [PageImageAttachment]) {
        self.attachments = attachments
        attachmentsView.update(attachments: attachments)
    }

    func setTool(color: UIColor, width: CGFloat, isEraser: Bool) {
        self.isEraser = isEraser
        strokeColor = color
        strokeWidth = width
        currentStrokeLayer.strokeColor = color.cgColor
        currentStrokeLayer.lineWidth = width
    }

    func updateScale(_ scale: CGFloat) {
        let normalized = max(scale, UIScreen.main.scale)
        guard abs(currentScale - normalized) > 0.01 else { return }
        currentScale = normalized
        contentScaleFactor = normalized
        layer.contentsScale = normalized
        inkView.updateScale(normalized)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, touch.type == .pencil else { return }
        activeSamples = []
        appendSample(from: touch)
        updatePreviewPath()

        if isEraser {
            onEraserOverlay?(.began, touch.location(in: self), strokeWidth)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, touch.type == .pencil else { return }
        appendSample(from: touch)
        updatePreviewPath()

        if isEraser {
            onEraserOverlay?(.moved, touch.location(in: self), strokeWidth)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, touch.type == .pencil else { return }
        finalizeStroke(lastTouch: touch)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, touch.type == .pencil else { return }
        finalizeStroke(lastTouch: touch)
    }

    private func finalizeStroke(lastTouch: UITouch?) {
        if let touch = lastTouch {
            appendSample(from: touch)
        }

        guard !activeSamples.isEmpty else {
            currentStrokeLayer.path = nil
            return
        }

        let style = InkStyle(color: CodableColor(strokeColor),
                             isEraser: isEraser,
                             baseWidth: strokeWidth)
        let stroke = InkStroke(id: UUID(),
                               points: activeSamples,
                               style: style)
        currentStrokeLayer.path = nil
        let finalPoint = activeSamples.last?.location.point ?? .zero
        onStrokeCommitted?(stroke)
        activeSamples.removeAll()

        if isEraser {
            onEraserOverlay?(.ended, finalPoint, strokeWidth)
        }
    }

    private func appendSample(from touch: UITouch) {
        let location = touch.location(in: self)
        let force = normalizedForce(for: touch)
        let adjustedWidth = adjustedWidth(for: force)
        let sample = StrokePoint(location: CodablePoint(location),
                                 force: force,
                                 azimuth: azimuth(from: touch),
                                 altitude: altitude(from: touch),
                                 timestamp: touch.timestamp,
                                 width: adjustedWidth)
        activeSamples.append(sample)
    }

    private func normalizedForce(for touch: UITouch) -> CGFloat {
        guard touch.type == .pencil else { return 0 }
        let maxForce = touch.maximumPossibleForce
        guard maxForce > 0 else { return 0 }
        return min(max(touch.force / maxForce, 0), 1)
    }

    private func adjustedWidth(for force: CGFloat) -> CGFloat {
        let base = strokeWidth
        let forceMultiplier: CGFloat = 0.45
        return base * (1 + force * forceMultiplier)
    }

    private func azimuth(from touch: UITouch) -> CGFloat? {
        guard touch.type == .pencil else { return nil }
        return touch.azimuthAngle(in: self)
    }

    private func altitude(from touch: UITouch) -> CGFloat? {
        guard touch.type == .pencil else { return nil }
        return touch.altitudeAngle
    }

    private func updatePreviewPath() {
        guard activeSamples.count > 1 else { return }
        let path = makeSmoothedPath(for: activeSamples)
        currentStrokeLayer.strokeColor = (isEraser ? UIColor.white : strokeColor).cgColor
        currentStrokeLayer.lineWidth = activeSamples.last?.width ?? strokeWidth
        currentStrokeLayer.path = path.cgPath
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let touch = event?.allTouches?.first {
            if touch.type == .pencil {
                return self
            } else {
                let converted = attachmentsView.convert(point, from: self)
                if let target = attachmentsView.hitTest(converted, with: event) {
                    return target
                }
            }
        }
        return super.hitTest(point, with: event)
    }

    private func makeSmoothedPath(for samples: [StrokePoint]) -> UIBezierPath {
        let points = samples.map { $0.location.point }
        let path = UIBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        guard points.count > 1 else {
            if let point = points.first {
                path.move(to: point)
                path.addLine(to: point)
            }
            return path
        }

        func point(at index: Int) -> CGPoint {
            let safeIndex = max(0, min(points.count - 1, index))
            return points[safeIndex]
        }

        path.move(to: point(at: 0))

        for i in 0..<(points.count - 1) {
            let p0 = point(at: i - 1)
            let p1 = point(at: i)
            let p2 = point(at: i + 1)
            let p3 = point(at: i + 2)

            let segments = 6
            for step in 1...segments {
                let t = CGFloat(step) / CGFloat(segments)
                let tt = t * t
                let ttt = tt * t

                let q1 = -ttt + 2.0 * tt - t
                let q2 = 3.0 * ttt - 5.0 * tt + 2.0
                let q3 = -3.0 * ttt + 4.0 * tt + t
                let q4 = ttt - tt

                let x = 0.5 * (p0.x * q1 + p1.x * q2 + p2.x * q3 + p3.x * q4)
                let y = 0.5 * (p0.y * q1 + p1.y * q2 + p2.y * q3 + p3.y * q4)
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        return path
    }
}

final class AttachmentContainerView: UIView {
    var onAttachmentsUpdated: (([PageImageAttachment]) -> Void)?
    var onDeleteAttachment: ((UUID) -> Void)?
    var onSelectionChanged: ((UUID?) -> Void)?

    private var attachmentViews: [UUID: AttachmentImageView] = [:]
    private var attachments: [PageImageAttachment] = []
    private var selectedAttachmentID: UUID?

    func update(attachments: [PageImageAttachment]) {
        self.attachments = attachments
        let ids = Set(attachments.map { $0.id })

        // Remove missing views
        for (id, view) in attachmentViews where !ids.contains(id) {
            view.removeFromSuperview()
            attachmentViews.removeValue(forKey: id)
        }

        // Add or update
        for attachment in attachments {
            let view: AttachmentImageView
            if let existing = attachmentViews[attachment.id] {
                view = existing
            } else {
                view = AttachmentImageView(attachment: attachment)
                view.onUpdate = { [weak self] updated in
                    self?.applyUpdate(updated)
                }
                view.onSelect = { [weak self] id in
                    self?.selectAttachment(id)
                }
                view.onDelete = { [weak self] id in
                    self?.deleteAttachment(id)
                }
                addSubview(view)
                attachmentViews[attachment.id] = view
            }
            view.apply(attachment: attachment)
            view.setSelected(attachment.id == selectedAttachmentID)
        }

        if let selected = selectedAttachmentID, !ids.contains(selected) {
            selectedAttachmentID = nil
            onSelectionChanged?(nil)
        } else if selectedAttachmentID == nil, let last = attachments.last?.id {
            selectAttachment(last)
        }

        let clearTap = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap))
        clearTap.cancelsTouchesInView = false
        addGestureRecognizer(clearTap)
    }

    private func applyUpdate(_ attachment: PageImageAttachment) {
        guard let index = attachments.firstIndex(where: { $0.id == attachment.id }) else { return }
        attachments[index] = attachment
        onAttachmentsUpdated?(attachments)
    }

    private func deleteAttachment(_ id: UUID) {
        attachments.removeAll { $0.id == id }
        attachmentViews[id]?.removeFromSuperview()
        attachmentViews.removeValue(forKey: id)
        if selectedAttachmentID == id {
            selectedAttachmentID = nil
            onSelectionChanged?(nil)
        }
        onDeleteAttachment?(id)
        onAttachmentsUpdated?(attachments)
    }

    private func selectAttachment(_ id: UUID?) {
        selectedAttachmentID = id
        for (attachmentID, view) in attachmentViews {
            view.setSelected(attachmentID == id)
        }
        onSelectionChanged?(id)
    }

    @objc private func handleBackgroundTap(_ gesture: UITapGestureRecognizer) {
        selectAttachment(nil)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let target = super.hitTest(point, with: event) else { return nil }
        return target === self ? nil : target
    }
}

final class AttachmentImageView: UIView, UIGestureRecognizerDelegate, UIContextMenuInteractionDelegate {
    var onUpdate: ((PageImageAttachment) -> Void)?
    var onSelect: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?

    private var attachment: PageImageAttachment
    private let imageView = UIImageView()
    private let borderLayer = CAShapeLayer()
    private let cornerLayer = CAShapeLayer()

    init(attachment: PageImageAttachment) {
        self.attachment = attachment
        super.init(frame: .zero)
        configure()
        apply(attachment: attachment)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(attachment: PageImageAttachment) {
        self.attachment = attachment
        if let image = UIImage(data: attachment.imageData) {
            imageView.image = image
        }
        let size = attachment.size.size
        bounds = CGRect(origin: .zero, size: size)
        center = attachment.position.point
        transform = CGAffineTransform(rotationAngle: CGFloat(attachment.rotation))
        updateSelectionVisuals()
    }

    private func configure() {
        clipsToBounds = true
        layer.cornerRadius = 6
        layer.addSublayer(borderLayer)
        layer.addSublayer(cornerLayer)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        let rotate = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate(_:)))
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleSelect))
        [pan, pinch, rotate].forEach { gesture in
            gesture.delegate = self
            gesture.cancelsTouchesInView = false
            gesture.delaysTouchesBegan = false
            addGestureRecognizer(gesture)
        }
        addGestureRecognizer(tap)

        let menuInteraction = UIContextMenuInteraction(delegate: self)
        addInteraction(menuInteraction)

        updateSelectionVisuals()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: superview)
        center = CGPoint(x: center.x + translation.x, y: center.y + translation.y)
        gesture.setTranslation(.zero, in: superview)
        if gesture.state == .ended || gesture.state == .cancelled {
            commitUpdate()
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        let scale = gesture.scale
        bounds.size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        gesture.scale = 1.0
        if gesture.state == .ended || gesture.state == .cancelled {
            commitUpdate()
        }
    }

    @objc private func handleRotate(_ gesture: UIRotationGestureRecognizer) {
        transform = transform.rotated(by: gesture.rotation)
        gesture.rotation = 0
        if gesture.state == .ended || gesture.state == .cancelled {
            commitUpdate()
        }
    }

    private func commitUpdate() {
        let newAttachment = PageImageAttachment(id: attachment.id,
                                                imageData: attachment.imageData,
                                                position: CodablePoint(center),
                                                size: CodableSize(width: bounds.width, height: bounds.height),
                                                rotation: Double(atan2(Double(transform.b), Double(transform.a))))
        onUpdate?(newAttachment)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touch.type != .pencil
    }

    @objc private func handleSelect() {
        onSelect?(attachment.id)
        updateSelectionVisuals()
    }

    func setSelected(_ isSelected: Bool) {
        borderLayer.isHidden = !isSelected
        cornerLayer.isHidden = !isSelected
    }

    private func updateSelectionVisuals() {
        borderLayer.frame = bounds
        borderLayer.path = UIBezierPath(roundedRect: bounds, cornerRadius: 8).cgPath
        borderLayer.strokeColor = UIColor.systemBlue.cgColor
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.lineWidth = 2

        let cornerPath = UIBezierPath()
        let cornerSize: CGFloat = 8
        let inset: CGFloat = 4
        let points = [
            CGPoint(x: inset, y: inset),
            CGPoint(x: bounds.width - inset, y: inset),
            CGPoint(x: inset, y: bounds.height - inset),
            CGPoint(x: bounds.width - inset, y: bounds.height - inset)
        ]
        for p in points {
            cornerPath.move(to: CGPoint(x: p.x - cornerSize / 2, y: p.y))
            cornerPath.addLine(to: CGPoint(x: p.x + cornerSize / 2, y: p.y))
            cornerPath.move(to: CGPoint(x: p.x, y: p.y - cornerSize / 2))
            cornerPath.addLine(to: CGPoint(x: p.x, y: p.y + cornerSize / 2))
        }
        cornerLayer.frame = bounds
        cornerLayer.path = cornerPath.cgPath
        cornerLayer.strokeColor = UIColor.systemBlue.cgColor
        cornerLayer.lineWidth = 2
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            UIMenu(children: [
                UIAction(title: "Delete", attributes: .destructive) { [weak self] _ in
                    guard let id = self?.attachment.id else { return }
                    self?.onDelete?(id)
                }
            ])
        }
    }
}
