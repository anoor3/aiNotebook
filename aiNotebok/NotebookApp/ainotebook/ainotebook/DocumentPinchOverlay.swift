import SwiftUI
import UIKit

/// A transparent UIKit view that finds its nearest parent UIScrollView and attaches a
/// UIPinchGestureRecognizer to it. This provides native-feel pinch-to-zoom that drives
/// a shared zoom scale for all pages in the document.
///
/// The pinch gesture fires simultaneously with the ScrollView's pan gesture, so scrolling
/// continues to work normally. Apple Pencil touches are excluded via allowedTouchTypes.
struct DocumentPinchOverlay: UIViewRepresentable {
    @Binding var zoomScale: CGFloat
    @Binding var pinchBaseScale: CGFloat
    
    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 3.0
    
    func makeUIView(context: Context) -> PinchInstallerView {
        let view = PinchInstallerView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }
    
    func updateUIView(_ uiView: PinchInstallerView, context: Context) {
        // Ensure the pinch is installed (may not have parent on first call)
        uiView.installPinchIfNeeded()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(zoomScale: $zoomScale, pinchBaseScale: $pinchBaseScale, minScale: minScale, maxScale: maxScale)
    }
    
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let zoomScale: Binding<CGFloat>
        let pinchBaseScale: Binding<CGFloat>
        let minScale: CGFloat
        let maxScale: CGFloat
        var pinchGesture: UIPinchGestureRecognizer?
        
        init(zoomScale: Binding<CGFloat>, pinchBaseScale: Binding<CGFloat>, minScale: CGFloat, maxScale: CGFloat) {
            self.zoomScale = zoomScale
            self.pinchBaseScale = pinchBaseScale
            self.minScale = minScale
            self.maxScale = maxScale
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                pinchBaseScale.wrappedValue = zoomScale.wrappedValue
            case .changed:
                let proposedScale = pinchBaseScale.wrappedValue * gesture.scale
                let clamped = min(max(proposedScale, minScale), maxScale)
                zoomScale.wrappedValue = clamped
            case .ended, .cancelled:
                var final = zoomScale.wrappedValue
                if final < minScale { final = minScale }
                if final > maxScale { final = maxScale }
                // Snap to 1.0 if very close to avoid near-1x artifacts
                if abs(final - 1.0) < 0.05 { final = 1.0 }
                if abs(final - zoomScale.wrappedValue) > 0.001 {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        zoomScale.wrappedValue = final
                    }
                }
            default:
                break
            }
        }
        
        // Allow simultaneous recognition with ScrollView's pan and other gestures
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
        
        // Only recognize direct finger touches, never Apple Pencil (stylus)
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            return touch.type == .direct
        }
    }
}

/// Helper UIView that installs a UIPinchGestureRecognizer on the nearest parent UIScrollView.
/// This approach ensures the pinch gesture is recognized by the same view that handles scrolling,
/// providing seamless coexistence between zoom and scroll.
final class PinchInstallerView: UIView {
    weak var coordinator: DocumentPinchOverlay.Coordinator?
    private var installed = false
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        installPinchIfNeeded()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        installPinchIfNeeded()
    }
    
    func installPinchIfNeeded() {
        guard !installed, let coordinator = coordinator else { return }
        
        // Walk up the view hierarchy to find the SwiftUI ScrollView's underlying UIScrollView
        guard let scrollView = findParentScrollView() else { return }
        
        // Check if we already added our pinch gesture
        let existingPinch = scrollView.gestureRecognizers?.first(where: { $0 is DocumentPinchGesture })
        guard existingPinch == nil else {
            installed = true
            return
        }
        
        let pinch = DocumentPinchGesture(target: coordinator, action: #selector(DocumentPinchOverlay.Coordinator.handlePinch(_:)))
        pinch.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        pinch.delegate = coordinator
        scrollView.addGestureRecognizer(pinch)
        coordinator.pinchGesture = pinch
        installed = true
    }
    
    private func findParentScrollView() -> UIScrollView? {
        var current: UIView? = superview
        while let view = current {
            if let scrollView = view as? UIScrollView {
                return scrollView
            }
            current = view.superview
        }
        return nil
    }
}

/// Subclass marker so we can identify our gesture recognizer on the scroll view.
final class DocumentPinchGesture: UIPinchGestureRecognizer {}
