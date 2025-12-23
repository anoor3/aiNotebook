import UIKit

struct StrokeRenderSample {
    let point: CGPoint
    let width: CGFloat
}

final class StrokeRenderer {
    func render(drawing: InkDrawing, size: CGSize, scale: CGFloat) -> CGImage? {
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
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for stroke in drawing.strokes {
            render(stroke: stroke, in: context)
        }

        return context.makeImage()
    }

    private func render(stroke: InkStroke, in context: CGContext) {
        guard let samples = makeSmoothedSamples(from: stroke.points) else { return }

        context.setBlendMode(stroke.style.isEraser ? .clear : .normal)
        context.setStrokeColor(stroke.style.isEraser ? UIColor.clear.cgColor : saturatedColor(from: stroke.style.uiColor).cgColor)

        for index in 1..<samples.count {
            let start = samples[index - 1]
            let end = samples[index]
            let segmentWidth = max(0.5, (start.width + end.width) / 2)
            context.setLineWidth(segmentWidth)
            context.move(to: start.point)
            context.addLine(to: end.point)
            context.strokePath()
        }
    }

    private func makeSmoothedSamples(from points: [StrokePoint]) -> [StrokeRenderSample]? {
        guard points.count > 1 else { return nil }
        var output: [StrokeRenderSample] = []

        func sample(at index: Int) -> StrokePoint {
            let safeIndex = max(0, min(points.count - 1, index))
            return points[safeIndex]
        }

        for i in 0..<(points.count - 1) {
            let p0 = sample(at: i - 1)
            let p1 = sample(at: i)
            let p2 = sample(at: i + 1)
            let p3 = sample(at: i + 2)

            let segments = 8
            for step in 0..<segments {
                let t = CGFloat(step) / CGFloat(segments)
                let tt = t * t
                let ttt = tt * t

                let q1 = -ttt + 2.0 * tt - t
                let q2 = 3.0 * ttt - 5.0 * tt + 2.0
                let q3 = -3.0 * ttt + 4.0 * tt + t
                let q4 = ttt - tt

                let x = 0.5 * (p0.location.point.x * q1 + p1.location.point.x * q2 + p2.location.point.x * q3 + p3.location.point.x * q4)
                let y = 0.5 * (p0.location.point.y * q1 + p1.location.point.y * q2 + p2.location.point.y * q3 + p3.location.point.y * q4)
                let w = max(0.5, 0.5 * (p1.width + p2.width))
                output.append(StrokeRenderSample(point: CGPoint(x: x, y: y), width: w))
            }
        }

        if let last = points.last {
            output.append(StrokeRenderSample(point: last.location.point, width: max(0.5, last.width)))
        }

        return output
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
