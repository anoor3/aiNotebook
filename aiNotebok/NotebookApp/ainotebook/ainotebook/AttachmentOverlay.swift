import SwiftUI
import UIKit

struct CanvasAttachment: Identifiable, Equatable {
    let id: UUID
    let imageData: Data
    var center: CGPoint
    var size: CGSize
    var rotation: CGFloat
    var isLocked: Bool

    static func == (lhs: CanvasAttachment, rhs: CanvasAttachment) -> Bool {
        lhs.id == rhs.id &&
        lhs.imageData == rhs.imageData &&
        lhs.center == rhs.center &&
        lhs.size == rhs.size &&
        lhs.rotation == rhs.rotation &&
        lhs.isLocked == rhs.isLocked
    }
}

struct AttachmentOverlay: View {
    let attachments: [CanvasAttachment]
    let pageSize: CGSize
    @Binding var editingAttachmentID: UUID?
    var onUpdate: (CanvasAttachment) -> Void
    var onDelete: ((UUID) -> Void)? = nil
    var onDuplicate: ((CanvasAttachment) -> Void)? = nil
    var onCopy: ((CanvasAttachment) -> Void)? = nil
    var onCrop: ((CanvasAttachment) -> Void)? = nil
    var onDoneEditing: (() -> Void)? = nil
    var onTapBackground: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            if editingAttachmentID != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editingAttachmentID = nil
                        onTapBackground?()
                    }
            }

            ForEach(attachments) { attachment in
                let isEditingAttachment = editingAttachmentID == attachment.id
                AttachmentItemView(attachment: attachment,
                                   pageSize: pageSize,
                                   isEditing: isEditingAttachment,
                                   onSelect: {
                                       guard !attachment.isLocked else { return }
                                       handleSelectionChange(to: attachment.id)
                                   },
                                   onCommit: onUpdate,
                                   onDelete: { onDelete?(attachment.id) },
                                   onDuplicate: { onDuplicate?(attachment) },
                                   onCopy: { onCopy?(attachment) },
                                   onCrop: { onCrop?(attachment) },
                                   onDone: finishEditing)
                    .zIndex(isEditingAttachment ? 2 : 1)
            }
        }
        .frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
        .allowsHitTesting(editingAttachmentID != nil)
    }

    private func handleSelectionChange(to attachmentID: UUID) {
        if editingAttachmentID != attachmentID {
            editingAttachmentID = attachmentID
        }
    }

    private func finishEditing() {
        editingAttachmentID = nil
        onDoneEditing?()
    }
}

private struct AttachmentItemView: View {
    let attachment: CanvasAttachment
    let pageSize: CGSize
    let isEditing: Bool
    let onSelect: () -> Void
    let onCommit: (CanvasAttachment) -> Void
    let onDelete: (() -> Void)?
    let onDuplicate: (() -> Void)?
    let onCopy: (() -> Void)?
    let onCrop: (() -> Void)?
    let onDone: (() -> Void)?

    private let attachmentCornerRadius: CGFloat = 6
    private let handleMargin: CGFloat = 0
    private let rotationHandleSpacing: CGFloat = 90

    @State private var workingAttachment: CanvasAttachment
    @State private var renderedImage: UIImage?
    @State private var dragStart: CGPoint?
    @State private var scaleStart: CGSize?
    @State private var rotationStart: CGFloat?
    @State private var activeHandleState: HandleDragState?
    @State private var rotationDragState: RotationDragState?
    @State private var isInteracting = false
    private var allowsEditing: Bool { !attachment.isLocked }

    init(attachment: CanvasAttachment,
         pageSize: CGSize,
         isEditing: Bool,
         onSelect: @escaping () -> Void,
         onCommit: @escaping (CanvasAttachment) -> Void,
         onDelete: (() -> Void)?,
         onDuplicate: (() -> Void)? = nil,
         onCopy: (() -> Void)? = nil,
         onCrop: (() -> Void)? = nil,
         onDone: (() -> Void)? = nil) {
        self.attachment = attachment
        self.pageSize = pageSize
        self.isEditing = isEditing
        self.onSelect = onSelect
        self.onCommit = onCommit
        self.onDelete = onDelete
        self.onDuplicate = onDuplicate
        self.onCopy = onCopy
        self.onCrop = onCrop
        self.onDone = onDone
        _workingAttachment = State(initialValue: attachment)
        _renderedImage = State(initialValue: UIImage(data: attachment.imageData))
    }

    var body: some View {
        Group {
            if let image = renderedImage {
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: workingAttachment.size.width,
                               height: workingAttachment.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: attachmentCornerRadius))

                    if isEditing && allowsEditing {
                        selectionOverlay
                    }
                }
                .frame(width: workingAttachment.size.width, height: workingAttachment.size.height)
                .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
                .rotationEffect(.radians(Double(workingAttachment.rotation)))
                .overlay(alignment: .top) {
                    if isEditing && allowsEditing && !isInteracting {
                        controlBar
                            .scaleEffect(0.9)
                            .offset(y: -workingAttachment.size.height / 2 - 60)
                    }
                }
                .position(workingAttachment.center)
                .gesture(editingGesture, including: .gesture)
                .simultaneousGesture(TapGesture().onEnded {
                    if allowsEditing { onSelect() }
                })
                .allowsHitTesting(allowsEditing)
            } else {
                EmptyView()
            }
        }
        .onChange(of: attachment) { updated in
            workingAttachment = updated
            renderedImage = UIImage(data: updated.imageData)
        }
    }

    private var controlBar: some View {
        HStack(spacing: 14) {
            if let onCrop {
                controlButton(systemName: "crop", action: onCrop)
            }
            if let onCopy {
                controlButton(systemName: "doc.on.doc", action: onCopy)
            }
            if let onDuplicate {
                controlButton(systemName: "plus.square.on.square", action: onDuplicate)
            }
            if let onDelete {
                controlButton(systemName: "trash", tint: .red, action: onDelete)
            }
            if let onDone {
                controlButton(systemName: "checkmark.circle", tint: .green, action: onDone)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
        .shadow(color: Color.black.opacity(0.2), radius: 10, y: 4)
    }

    private func controlButton(systemName: String, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .symbolVariant(.fill)
                .foregroundStyle(tint)
                .padding(10)
        }
        .buttonStyle(.plain)
        .background(Color.white.opacity(0.6), in: Circle())
    }

    private var selectionOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.9), style: StrokeStyle(lineWidth: 1.2, dash: [5]))

            ForEach(HandlePosition.allCases, id: \.self) { position in
                ResizeHandleView()
                    .offset(position.offset(for: workingAttachment.size, margin: handleMargin))
                    .gesture(resizeGesture(for: position))
            }
        }
        .frame(width: workingAttachment.size.width, height: workingAttachment.size.height)
        .overlay(alignment: .bottom) { rotationOverlay }
    }

    private var rotationOverlay: some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(Color.accentColor.opacity(0.55))
                .frame(width: 2, height: max(20, rotationHandleSpacing - 36))
            RotationHandleView()
        }
        .contentShape(Rectangle())
        .offset(y: rotationHandleSpacing)
        .gesture(rotationHandleGesture)
    }

    private func resizeGesture(for position: HandlePosition) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isEditing, allowsEditing else { return }
                if activeHandleState?.position != position {
                    activeHandleState = HandleDragState(position: position, attachment: workingAttachment)
                }
                guard let state = activeHandleState else { return }
                setInteracting(true)
                let local = convertToLocalTranslation(value.translation, rotation: state.attachment.rotation)
                workingAttachment = adjustedAttachment(from: state.attachment,
                                                        translation: local,
                                                        handle: position)
            }
            .onEnded { _ in
                activeHandleState = nil
                commitTransform()
                setInteracting(false)
            }
    }

    private var rotationHandleGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isEditing, allowsEditing else { return }
                if rotationDragState == nil {
                    rotationDragState = RotationDragState(attachment: workingAttachment,
                                                           handleVector: rotationHandleVector(for: workingAttachment))
                }
                guard let state = rotationDragState else { return }
                setInteracting(true)
                let vector = CGVector(dx: state.handleVector.dx + value.translation.width,
                                      dy: state.handleVector.dy + value.translation.height)
                var updated = state.attachment
                let angle = atan2(vector.dy, vector.dx)
                updated.rotation = angle - (.pi / 2)
                workingAttachment = updated
            }
            .onEnded { _ in
                rotationDragState = nil
                commitTransform()
                setInteracting(false)
            }
    }

    private enum HandlePosition: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

        var horizontalFactor: CGFloat {
            switch self {
            case .topLeft, .left, .bottomLeft: return -1
            case .topRight, .right, .bottomRight: return 1
            default: return 0
            }
        }

        var verticalFactor: CGFloat {
            switch self {
            case .topLeft, .top, .topRight: return -1
            case .bottomLeft, .bottom, .bottomRight: return 1
            default: return 0
            }
        }

        var affectsWidth: Bool { horizontalFactor != 0 }
        var affectsHeight: Bool { verticalFactor != 0 }

        func offset(for size: CGSize, margin: CGFloat) -> CGSize {
            let halfWidth = size.width / 2
            let halfHeight = size.height / 2

            var x: CGFloat = 0
            switch horizontalFactor {
            case -1: x = -halfWidth - margin
            case 1: x = halfWidth + margin
            default: x = 0
            }

            var y: CGFloat = 0
            switch verticalFactor {
            case -1: y = -halfHeight - margin
            case 1: y = halfHeight + margin
            default: y = 0
            }

            return CGSize(width: x, height: y)
        }
    }

    private struct ResizeHandleView: View {
        var body: some View {
            Circle()
                .fill(Color.white)
                .frame(width: 12, height: 12)
                .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                .overlay(
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 1.5)
                )
        }
    }

    private struct RotationHandleView: View {
        var body: some View {
            Circle()
                .fill(Color.white)
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
        }
    }

    private func convertToLocalTranslation(_ translation: CGSize, rotation: CGFloat) -> CGSize {
        let angle = -rotation
        let cosA = cos(angle)
        let sinA = sin(angle)
        return CGSize(width: translation.width * cosA - translation.height * sinA,
                      height: translation.width * sinA + translation.height * cosA)
    }

    private func adjustedAttachment(from start: CanvasAttachment,
                                     translation: CGSize,
                                     handle: HandlePosition) -> CanvasAttachment {
        var local = translation
        if !handle.affectsWidth { local.width = 0 }
        if !handle.affectsHeight { local.height = 0 }

        var size = start.size
        size.width += local.width * handle.horizontalFactor
        size.height += local.height * handle.verticalFactor
        size = clampedSize(size)

        var centerOffsetLocal = CGSize.zero
        if handle.affectsWidth { centerOffsetLocal.width = local.width / 2 }
        if handle.affectsHeight { centerOffsetLocal.height = local.height / 2 }

        let rotatedOffset = rotate(offset: centerOffsetLocal, angle: start.rotation)
        var center = CGPoint(x: start.center.x + rotatedOffset.width,
                             y: start.center.y + rotatedOffset.height)
        center = clampedCenter(center, size: size)

        var updated = start
        updated.size = size
        updated.center = center
        return updated
    }

    private func rotate(offset: CGSize, angle: CGFloat) -> CGSize {
        let cosA = cos(angle)
        let sinA = sin(angle)
        return CGSize(width: offset.width * cosA - offset.height * sinA,
                      height: offset.width * sinA + offset.height * cosA)
    }

    private struct HandleDragState {
        let position: HandlePosition
        let attachment: CanvasAttachment
    }

    private struct RotationDragState {
        let attachment: CanvasAttachment
        let handleVector: CGVector
    }

    private func rotationHandleVector(for attachment: CanvasAttachment) -> CGVector {
        let distance = (attachment.size.height / 2) + rotationHandleSpacing
        let base = CGVector(dx: 0, dy: distance)
        return CGVector(dx: base.dx * cos(attachment.rotation) - base.dy * sin(attachment.rotation),
                        dy: base.dx * sin(attachment.rotation) + base.dy * cos(attachment.rotation))
    }

    private var editingGesture: some Gesture {
        let drag = DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isEditing, allowsEditing else { return }
                setInteracting(true)
                if dragStart == nil {
                    dragStart = workingAttachment.center
                }
                guard let dragStart else { return }
                var updated = workingAttachment
                let proposed = CGPoint(x: dragStart.x + value.translation.width,
                                       y: dragStart.y + value.translation.height)
                updated.center = clampedCenter(proposed, size: updated.size)
                workingAttachment = updated
            }
            .onEnded { _ in
                guard isEditing else { return }
                dragStart = nil
                commitTransform()
                setInteracting(false)
            }

        let scale = MagnificationGesture()
            .onChanged { value in
                guard isEditing, allowsEditing else { return }
                setInteracting(true)
                if scaleStart == nil {
                    scaleStart = workingAttachment.size
                }
                guard let base = scaleStart else { return }
                var newSize = CGSize(width: base.width * value, height: base.height * value)
                newSize = clampedSize(newSize)
                var updated = workingAttachment
                updated.size = newSize
                updated.center = clampedCenter(updated.center, size: newSize)
                workingAttachment = updated
            }
            .onEnded { _ in
                guard isEditing else { return }
                scaleStart = nil
                commitTransform()
                setInteracting(false)
            }

        let rotation = RotationGesture()
            .onChanged { value in
                guard isEditing, allowsEditing else { return }
                setInteracting(true)
                if rotationStart == nil {
                    rotationStart = workingAttachment.rotation
                }
                guard let base = rotationStart else { return }
                var updated = workingAttachment
                updated.rotation = base + CGFloat(value.radians)
                workingAttachment = updated
            }
            .onEnded { _ in
                guard isEditing else { return }
                rotationStart = nil
                commitTransform()
                setInteracting(false)
            }

        return drag.simultaneously(with: scale).simultaneously(with: rotation)
    }

    private func commitTransform() {
        var clamped = workingAttachment
        clamped.center = clampedCenter(clamped.center, size: clamped.size)
        clamped.size = clampedSize(clamped.size)
        workingAttachment = clamped
        onCommit(clamped)
    }

    private func setInteracting(_ flag: Bool) {
        withAnimation(.easeInOut(duration: 0.2)) {
            isInteracting = flag
        }
    }

    private func clampedCenter(_ center: CGPoint, size: CGSize) -> CGPoint {
        guard pageSize.width > 0, pageSize.height > 0 else { return center }
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        let minX = halfWidth
        let maxX = max(halfWidth, pageSize.width - halfWidth)
        let minY = halfHeight
        let maxY = max(halfHeight, pageSize.height - halfHeight)
        var adjusted = center
        adjusted.x = min(maxX, max(minX, adjusted.x))
        adjusted.y = min(maxY, max(minY, adjusted.y))
        return adjusted
    }

    private func clampedSize(_ size: CGSize) -> CGSize {
        guard pageSize.width > 0, pageSize.height > 0 else { return size }
        let minDimension: CGFloat = 120
        let maxWidth = pageSize.width * 0.95
        let maxHeight = pageSize.height * 0.95

        let width = max(minDimension, min(size.width, maxWidth))
        let height = max(minDimension, min(size.height, maxHeight))
        return CGSize(width: width, height: height)
    }
}
