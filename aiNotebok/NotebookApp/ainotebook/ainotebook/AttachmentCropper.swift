import SwiftUI
import UIKit

struct AttachmentCropSheet: View {
    let image: UIImage
    let onCancel: () -> Void
    let onSave: (UIImage) -> Void

    @StateObject private var controllerHolder = CropControllerHolder()

    var body: some View {
        NavigationView {
            AttachmentCropperView(image: image, controllerHolder: controllerHolder)
                .ignoresSafeArea()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            let result = controllerHolder.controller?.croppedImage() ?? image
                            onSave(result)
                        }
                    }
                }
                .navigationTitle("Crop Image")
                .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

final class CropControllerHolder: ObservableObject {
    weak var controller: AttachmentCropViewController?
}

struct AttachmentCropperView: UIViewControllerRepresentable {
    let image: UIImage
    @ObservedObject var controllerHolder: CropControllerHolder

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> AttachmentCropViewController {
        let controller = AttachmentCropViewController(image: image)
        controllerHolder.controller = controller
        return controller
    }

    func updateUIViewController(_ uiViewController: AttachmentCropViewController, context: Context) {}

    final class Coordinator {}
}

final class AttachmentCropViewController: UIViewController, UIScrollViewDelegate {
    private let image: UIImage
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let overlayView = UIView()
    private let overlayBorder = CAShapeLayer()
    private let overlayInset: CGFloat = 24

    init(image: UIImage) {
        self.image = image
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureScrollView()
        configureOverlay()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        overlayView.frame = view.bounds
        scrollView.frame = view.bounds.insetBy(dx: overlayInset, dy: overlayInset)
        updateZoomScales()
        updateContentInsets()
        updateOverlayMask()
    }

    private func configureScrollView() {
        scrollView.delegate = self
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.maximumZoomScale = 6
        scrollView.minimumZoomScale = 1
        scrollView.backgroundColor = .clear

        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.frame = CGRect(origin: .zero, size: image.size)

        scrollView.addSubview(imageView)
        scrollView.contentSize = image.size
        view.addSubview(scrollView)
    }

    private func configureOverlay() {
        overlayView.isUserInteractionEnabled = false
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.25)

        let maskLayer = CAShapeLayer()
        maskLayer.fillRule = .evenOdd
        overlayView.layer.mask = maskLayer

        overlayBorder.strokeColor = UIColor.white.withAlphaComponent(0.9).cgColor
        overlayBorder.lineWidth = 2
        overlayBorder.fillColor = UIColor.clear.cgColor
        overlayView.layer.addSublayer(overlayBorder)

        view.addSubview(overlayView)
    }

    private func updateOverlayMask() {
        guard let maskLayer = overlayView.layer.mask as? CAShapeLayer else {
            return
        }

        let bounds = overlayView.bounds
        let cutout = scrollView.frame
        let path = UIBezierPath(rect: bounds)
        path.append(UIBezierPath(rect: cutout))
        path.usesEvenOddFillRule = true
        maskLayer.path = path.cgPath

        overlayBorder.path = UIBezierPath(rect: cutout).cgPath
    }

    private func updateZoomScales() {
        guard image.size.width > 0, image.size.height > 0 else { return }
        let boundsSize = scrollView.bounds.size
        let widthScale = boundsSize.width / image.size.width
        let heightScale = boundsSize.height / image.size.height
        let minScale = min(widthScale, heightScale)
        scrollView.minimumZoomScale = minScale
        scrollView.maximumZoomScale = max(minScale * 4, minScale + 0.1)
        if scrollView.zoomScale < minScale {
            scrollView.zoomScale = minScale
        }
        updateContentInsets()
    }

    private func updateContentInsets() {
        let boundsSize = scrollView.bounds.size
        let scaledSize = CGSize(width: image.size.width * scrollView.zoomScale,
                                height: image.size.height * scrollView.zoomScale)
        let horizontalInset = max(0, (boundsSize.width - scaledSize.width) / 2)
        let verticalInset = max(0, (boundsSize.height - scaledSize.height) / 2)
        scrollView.contentInset = UIEdgeInsets(top: verticalInset,
                                               left: horizontalInset,
                                               bottom: verticalInset,
                                               right: horizontalInset)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateContentInsets()
    }

    func croppedImage() -> UIImage? {
        let zoomScale = scrollView.zoomScale
        guard zoomScale > 0 else { return image }

        let offsetX = (scrollView.contentOffset.x + scrollView.contentInset.left) / zoomScale
        let offsetY = (scrollView.contentOffset.y + scrollView.contentInset.top) / zoomScale
        let visibleWidth = scrollView.bounds.width / zoomScale
        let visibleHeight = scrollView.bounds.height / zoomScale

        var cropRect = CGRect(x: offsetX,
                              y: offsetY,
                              width: visibleWidth,
                              height: visibleHeight)
        let imageBounds = CGRect(origin: .zero, size: image.size)
        cropRect = cropRect.intersection(imageBounds)
        guard cropRect.width > 1, cropRect.height > 1 else { return image }

        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = image.scale
        rendererFormat.opaque = false
        let renderer = UIGraphicsImageRenderer(size: cropRect.size, format: rendererFormat)
        let cropped = renderer.image { context in
            image.draw(at: CGPoint(x: -cropRect.origin.x, y: -cropRect.origin.y))
        }
        return cropped
    }
}
