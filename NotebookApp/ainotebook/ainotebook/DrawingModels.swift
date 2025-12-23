import Foundation
import SwiftUI
import UIKit

struct CodablePoint: Codable, Hashable {
    var x: CGFloat
    var y: CGFloat

    init(_ point: CGPoint) {
        self.x = point.x
        self.y = point.y
    }

    var point: CGPoint {
        CGPoint(x: x, y: y)
    }
}

struct InkSample: Codable, Hashable {
    var location: CodablePoint
    var force: CGFloat
    var azimuth: CGFloat?
    var altitude: CGFloat?
    var timestamp: TimeInterval
    var width: CGFloat
}

struct InkStroke: Identifiable, Codable, Hashable {
    var id: UUID
    var points: [InkSample]
    var color: CodableColor
    var isEraser: Bool
}

struct InkDrawing: Codable, Hashable {
    var strokes: [InkStroke]

    static var empty: InkDrawing {
        InkDrawing(strokes: [])
    }
}

extension CodableColor {
    init(_ uiColor: UIColor) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 1
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.red = Double(r)
        self.green = Double(g)
        self.blue = Double(b)
        self.alpha = Double(a)
    }

    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}
