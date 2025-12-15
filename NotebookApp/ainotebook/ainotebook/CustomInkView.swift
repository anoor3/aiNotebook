import UIKit
import PencilKit

final class CustomInkView: UIView {
    private let renderQueue = DispatchQueue(label: "ink.render.queue", qos: .userInteractive)
    private var pendingWorkItem: DispatchWorkItem?
    private var currentScale: CGFloat = UIScreen.main.scale

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        contentScaleFactor = UIScreen.main.scale
        layer.contentsScale = UIScreen.main.scale
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateScale(_ scale: CGFloat) {
        currentScale = max(scale, UIScreen.main.scale)
        layer.contentsScale = currentScale
        contentScaleFactor = currentScale
    }

    func update(drawing: PKDrawing, scale: CGFloat) {
        let strokes = drawing.strokes
        let boundsSize = bounds.size
        guard boundsSize.width > 0, boundsSize.height > 0 else { return }

        pendingWorkItem?.cancel()

        var workItem: DispatchWorkItem?
        let newWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let image = self.renderImage(for: strokes, size: boundsSize, scale: max(scale, 1.0) * UIScreen.main.scale)
            DispatchQueue.main.async { [weak self] in
                guard let self = self,
                      let currentWorkItem = workItem,
                      self.pendingWorkItem === currentWorkItem,
                      !currentWorkItem.isCancelled,
                      let cgImage = image else { return }
                self.layer.contents = cgImage
            }
        }
        workItem = newWorkItem

        pendingWorkItem = newWorkItem
        renderQueue.async(execute: newWorkItem)
    }

    private func renderImage(for strokes: [PKStroke], size: CGSize, scale: CGFloat) -> CGImage? {
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        guard width > 0, height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: width * 4,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for stroke in strokes {
            guard let path = makeSmoothedPath(from: stroke) else { continue }
            let color = saturatedColor(from: stroke.ink.color)
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(max(0.5, averageWidth(for: stroke)))
            context.addPath(path.cgPath)
            context.strokePath()
        }

        return context.makeImage()
    }

    private func makeSmoothedPath(from stroke: PKStroke) -> UIBezierPath? {
        let points = Array(stroke.path)
        guard points.count > 1 else { return nil }

        let path = UIBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        func point(at index: Int) -> CGPoint {
            let safeIndex = max(0, min(points.count - 1, index))
            return points[safeIndex].location
        }

        path.move(to: point(at: 0))

        for i in 0..<(points.count - 1) {
            let p0 = point(at: i - 1)
            let p1 = point(at: i)
            let p2 = point(at: i + 1)
            let p3 = point(at: i + 2)

            let segments = 8
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

    private func averageWidth(for stroke: PKStroke) -> CGFloat {
        let points = Array(stroke.path)
        guard !points.isEmpty else { return 1.0 }
        let total = points.reduce(CGFloat(0)) { $0 + $1.size.width }
        return total / CGFloat(points.count)
    }

    private func saturatedColor(from color: UIColor) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 1
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let maxValue = max(red, max(green, blue))
        let saturationBoost: CGFloat = 0.1
        let adjustedRed = min(1.0, red + (maxValue - red) * saturationBoost)
        let adjustedGreen = min(1.0, green + (maxValue - green) * saturationBoost)
        let adjustedBlue = min(1.0, blue + (maxValue - blue) * saturationBoost)

        return UIColor(red: adjustedRed, green: adjustedGreen, blue: adjustedBlue, alpha: 1.0)
    }
}
