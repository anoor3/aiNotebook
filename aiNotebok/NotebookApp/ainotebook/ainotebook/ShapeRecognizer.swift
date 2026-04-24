import PencilKit
import UIKit

enum ShapeRecognizer {
    static func straightenedLine(from stroke: PKStroke) -> PKStroke? {
        let points = Array(stroke.path)
        guard points.count >= 2 else { return nil }
        guard let first = points.first, let last = points.last else { return nil }
        let start = first.location
        let end = last.location
        let diagonal = hypot(end.x - start.x, end.y - start.y)
        guard diagonal > 10 else { return nil }
        let pathLength = totalLength(for: points)
        guard pathLength > 0 else { return nil }
        let straightness = diagonal / pathLength
        guard straightness > 0.92 else { return nil }

        let startPoint = PKStrokePoint(location: start,
                                       timeOffset: first.timeOffset,
                                       size: first.size,
                                       opacity: first.opacity,
                                       force: first.force,
                                       azimuth: first.azimuth,
                                       altitude: first.altitude)
        let endPoint = PKStrokePoint(location: end,
                                     timeOffset: last.timeOffset,
                                     size: last.size,
                                     opacity: last.opacity,
                                     force: last.force,
                                     azimuth: last.azimuth,
                                     altitude: last.altitude)

        let path = PKStrokePath(controlPoints: [startPoint, endPoint], creationDate: stroke.path.creationDate)
        return PKStroke(ink: stroke.ink, path: path)
    }

    private static func totalLength(for points: [PKStrokePoint]) -> CGFloat {
        guard points.count > 1 else { return 0 }
        var length: CGFloat = 0
        for index in 1..<points.count {
            let prev = points[index - 1]
            let current = points[index]
            length += hypot(current.location.x - prev.location.x,
                            current.location.y - prev.location.y)
        }
        return length
    }
}
