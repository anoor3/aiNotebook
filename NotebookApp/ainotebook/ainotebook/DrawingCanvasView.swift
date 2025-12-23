import UIKit

enum EraserOverlayEvent {
    case began
    case moved
    case ended
}

final class DrawingCanvasView: UIView {
    var onDrawingChanged: ((InkDrawing) -> Void)?
    var onEraserOverlay: ((EraserOverlayEvent, CGPoint, CGFloat) -> Void)?

    private(set) var drawing: InkDrawing = .empty {
        didSet {
            inkView.update(drawing: drawing, scale: currentScale)
        }
    }

    private let inkView = CustomInkView()
    private let currentStrokeLayer = CAShapeLayer()
    private var activeSamples: [InkSample] = []
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

        inkView.translatesAutoresizingMaskIntoConstraints = false
        inkView.isUserInteractionEnabled = false
        inkView.layer.masksToBounds = false
        addSubview(inkView)

        NSLayoutConstraint.activate([
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
        guard let touch = touches.first else { return }
        activeSamples = []
        appendSample(from: touch)
        updatePreviewPath()

        if isEraser {
            onEraserOverlay?(.began, touch.location(in: self), strokeWidth)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        appendSample(from: touch)
        updatePreviewPath()

        if isEraser {
            onEraserOverlay?(.moved, touch.location(in: self), strokeWidth)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finalizeStroke(lastTouch: touches.first)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finalizeStroke(lastTouch: touches.first)
    }

    private func finalizeStroke(lastTouch: UITouch?) {
        if let touch = lastTouch {
            appendSample(from: touch)
        }

        guard !activeSamples.isEmpty else {
            currentStrokeLayer.path = nil
            return
        }

        let stroke = InkStroke(id: UUID(),
                               points: activeSamples,
                               color: CodableColor(strokeColor),
                               isEraser: isEraser)
        drawing.strokes.append(stroke)
        currentStrokeLayer.path = nil
        let finalPoint = activeSamples.last?.location.point ?? .zero
        onDrawingChanged?(drawing)
        activeSamples.removeAll()

        if isEraser {
            onEraserOverlay?(.ended, finalPoint, strokeWidth)
        }
    }

    private func appendSample(from touch: UITouch) {
        let location = touch.location(in: self)
        let force = normalizedForce(for: touch)
        let adjustedWidth = adjustedWidth(for: force)
        let sample = InkSample(location: CodablePoint(location),
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

    private func makeSmoothedPath(for samples: [InkSample]) -> UIBezierPath {
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
