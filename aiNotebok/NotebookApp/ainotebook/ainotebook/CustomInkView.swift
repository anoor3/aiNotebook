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

    private let tileSize: CGFloat = 256
    private let renderQueue = DispatchQueue(label: "ink.tile.render.queue", qos: .userInteractive)
    private var tiles: [TileKey: InkTileView] = [:]
    private var hiddenTileKeys: Set<TileKey> = []
    private var pageSize: CGSize

    init(pageSize: CGSize) {
        self.pageSize = pageSize
        super.init(frame: .zero)
        isOpaque = false
        isUserInteractionEnabled = false
        rebuildTiles()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updatePageSize(_ newSize: CGSize) {
        guard newSize != pageSize else { return }
        pageSize = newSize
        rebuildTiles()
    }

    func update(drawing: PKDrawing, scale: CGFloat, dirtyRect: CGRect? = nil) {
        let keys = keys(intersecting: dirtyRect)
        for key in keys {
            renderTile(for: key, drawing: drawing, scale: scale)
        }
        hiddenTileKeys.subtract(keys)
    }

    func hideTiles(in rect: CGRect) {
        let keys = keys(intersecting: rect)
        for key in keys {
            tiles[key]?.isHidden = true
        }
        hiddenTileKeys.formUnion(keys)
    }

    func showTiles(in rect: CGRect, drawing: PKDrawing, scale: CGFloat) {
        let keys = keys(intersecting: rect)
        for key in keys {
            renderTile(for: key, drawing: drawing, scale: scale)
            tiles[key]?.isHidden = false
            hiddenTileKeys.remove(key)
        }
    }

    func clearAll() {
        hiddenTileKeys.removeAll()
        for tile in tiles.values {
            tile.image = nil
            tile.isHidden = false
        }
    }

    private func rebuildTiles() {
        tiles.values.forEach { $0.removeFromSuperview() }
        tiles.removeAll()
        hiddenTileKeys.removeAll()

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

    private func keys(intersecting rect: CGRect?) -> [TileKey] {
        guard !tiles.isEmpty else { return [] }
        guard let rect = rect?.standardized else {
            return Array(tiles.keys)
        }
        let clamped = rect.intersection(CGRect(origin: .zero, size: pageSize))
        guard !clamped.isNull else { return [] }

        return tiles.compactMap { key, tile in
            tile.frame.intersects(clamped) ? key : nil
        }
    }

    private func renderTile(for key: TileKey, drawing: PKDrawing, scale: CGFloat) {
        guard let tile = tiles[key] else { return }
        let tileRect = tile.frame
        let effectiveScale = max(scale, 1.0) * UIScreen.main.scale
        let snapshot = drawing

        renderQueue.async { [weak self] in
            let image = snapshot.image(from: tileRect, scale: effectiveScale)
            guard let cgImage = image.cgImage ?? image.asCGImage() else { return }
            DispatchQueue.main.async {
                guard let tile = self?.tiles[key] else { return }
                tile.image = cgImage
            }
        }
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
