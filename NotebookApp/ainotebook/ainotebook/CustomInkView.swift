import UIKit

final class CustomInkView: UIView {
    private let renderQueue = DispatchQueue(label: "ink.render.queue", qos: .userInteractive)
    private var pendingWorkItem: DispatchWorkItem?
    private var currentScale: CGFloat = UIScreen.main.scale
    private let renderer = StrokeRenderer()

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

    func update(drawing: InkDrawing, scale: CGFloat) {
        let strokes = drawing.strokes
        let boundsSize = bounds.size
        guard boundsSize.width > 0, boundsSize.height > 0 else { return }

        pendingWorkItem?.cancel()

        var workItem: DispatchWorkItem?
        let newWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let image = self.renderer.render(drawing: drawing, size: boundsSize, scale: max(scale, 1.0) * UIScreen.main.scale)
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
}
