import UIKit
import PencilKit

final class TiledInkView: UIView {
    private struct TileKey: Hashable {
        let x: Int
        let y: Int
    }

    private final class InkTileView: UIView {
        var image: CGImage? {
            didSet { layer.contents = image }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            layer.contentsScale = UIScreen.main.scale
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    private let tileSize: CGFloat = 512
    private let renderQueue = DispatchQueue(label: "ink.tile.render.queue", qos: .userInitiated)
    private let cache = InkTileCache(capacity: 150)
    private var tiles: [TileKey: InkTileView] = [:]
    private var visibleKeys: Set<TileKey> = []
    private var pageSize: CGSize
    private var drawing = PKDrawing()
    private let scaleBuckets: [CGFloat] = [1.0, 1.5, 2.0, 3.0]
    private var currentScaleStep: Int = 100
    private var memoryObserver: NSObjectProtocol?

    init(pageSize: CGSize) {
        self.pageSize = pageSize
        super.init(frame: .zero)
        isOpaque = false
        isUserInteractionEnabled = false
        rebuildTiles()
        memoryObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                                                object: nil,
                                                                queue: .main) { [weak self] _ in
            self?.handleMemoryWarning()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let observer = memoryObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func updatePageSize(_ newSize: CGSize) {
        guard newSize != pageSize else { return }
        pageSize = newSize
        rebuildTiles()
        cache.removeAll()
    }

    func setDrawing(_ drawing: PKDrawing) {
        self.drawing = drawing
        cache.removeAll()
        tiles.values.forEach { $0.image = nil }
    }

    func updateVisibleRect(_ rect: CGRect, zoomScale: CGFloat) {
        guard pageSize.width > 0, pageSize.height > 0 else { return }
        let bucket = nearestScaleStep(for: zoomScale)
        currentScaleStep = bucket
        let expanded = rect.insetBy(dx: -tileSize, dy: -tileSize).intersection(CGRect(origin: .zero, size: pageSize))
        let previousKeys = visibleKeys
        let newKeys = Set(keys(intersecting: expanded))
        visibleKeys = newKeys

        for key in newKeys {
            displayTile(for: key, scaleStep: bucket)
        }

        let droppedKeys = previousKeys.subtracting(newKeys)
        for key in droppedKeys {
            tiles[key]?.image = nil
        }
    }

    func handleMemoryWarning() {
        cache.removeAll()
        tiles.values.forEach { $0.image = nil }
    }

    private func rebuildTiles() {
        tiles.values.forEach { $0.removeFromSuperview() }
        tiles.removeAll()

        guard pageSize.width > 0, pageSize.height > 0 else { return }

        let columns = Int(ceil(pageSize.width / tileSize))
        let rows = Int(ceil(pageSize.height / tileSize))

        for y in 0..<rows {
            for x in 0..<columns {
                let origin = CGPoint(x: CGFloat(x) * tileSize, y: CGFloat(y) * tileSize)
                let size = CGSize(width: min(tileSize, pageSize.width - origin.x),
                                  height: min(tileSize, pageSize.height - origin.y))
                let rect = CGRect(origin: origin, size: size)
                let tileView = InkTileView(frame: rect)
                tileView.backgroundColor = .clear
                tileView.isUserInteractionEnabled = false
                addSubview(tileView)
                tiles[TileKey(x: x, y: y)] = tileView
            }
        }
        setNeedsLayout()
    }

    private func keys(intersecting rect: CGRect) -> [TileKey] {
        guard !tiles.isEmpty else { return [] }
        let clamped = rect.intersection(CGRect(origin: .zero, size: pageSize))
        guard !clamped.isNull else { return [] }

        return tiles.compactMap { key, tile in
            tile.frame.intersects(clamped) ? key : nil
        }
    }

    private func displayTile(for key: TileKey, scaleStep: Int) {
        guard let tile = tiles[key] else { return }
        let identifier = InkTileIdentifier(x: key.x, y: key.y, scaleStep: scaleStep)
        if let image = cache.image(for: identifier) {
            tile.image = image
            return
        }

        let tileRect = tile.frame
        let drawingSnapshot = drawing
        renderQueue.async { [weak self] in
            autoreleasepool {
                let scale = CGFloat(scaleStep) / 100.0 * UIScreen.main.scale
                let image = drawingSnapshot.image(from: tileRect, scale: max(scale, UIScreen.main.scale))
                guard let cgImage = image.cgImage ?? image.asCGImage() else { return }
                DispatchQueue.main.async {
                    guard let self, let tile = self.tiles[key], self.visibleKeys.contains(key) else { return }
                    tile.image = cgImage
                    self.cache.insert(cgImage, for: identifier)
                }
            }
        }
    }

    private func nearestScaleStep(for zoomScale: CGFloat) -> Int {
        let bucket = scaleBuckets.min(by: { abs($0 - zoomScale) < abs($1 - zoomScale) }) ?? 1.0
        return Int(bucket * 100)
    }
}

private extension UIImage {
    func asCGImage() -> CGImage? {
        if let cg = self.cgImage {
            return cg
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let rendered = renderer.image { _ in
            self.draw(at: .zero)
        }
        return rendered.cgImage
    }
}
