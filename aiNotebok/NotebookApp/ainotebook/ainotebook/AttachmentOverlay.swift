import SwiftUI
import UIKit

struct CanvasAttachment: Identifiable, Equatable {
    let id: UUID
    let imageData: Data
    var center: CGPoint
    var size: CGSize
    var rotation: CGFloat

    static func == (lhs: CanvasAttachment, rhs: CanvasAttachment) -> Bool {
        lhs.id == rhs.id &&
        lhs.imageData == rhs.imageData &&
        lhs.center == rhs.center &&
        lhs.size == rhs.size &&
        lhs.rotation == rhs.rotation
    }
}

struct AttachmentOverlay: View {
    let attachments: [CanvasAttachment]
    let pageSize: CGSize
    @Binding var editingAttachmentID: UUID?
    var onUpdate: (CanvasAttachment) -> Void
    var onDelete: ((UUID) -> Void)? = nil
    var onDuplicate: ((CanvasAttachment) -> Void)? = nil
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
                                       handleSelectionChange(to: attachment.id)
                                   },
                                   onCommit: onUpdate,
                                   onDelete: { onDelete?(attachment.id) },
                                   onDuplicate: { onDuplicate?(attachment) },
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
    let onCrop: (() -> Void)?
    let onDone: (() -> Void)?

    @State private var workingAttachment: CanvasAttachment
    @State private var renderedImage: UIImage?
    @State private var dragStart: CGPoint?
    @State private var scaleStart: CGSize?
    @State private var rotationStart: CGFloat?
    @State private var isInteracting = false

    init(attachment: CanvasAttachment,
         pageSize: CGSize,
         isEditing: Bool,
         onSelect: @escaping () -> Void,
         onCommit: @escaping (CanvasAttachment) -> Void,
         onDelete: (() -> Void)?,
         onDuplicate: (() -> Void)? = nil,
         onCrop: (() -> Void)? = nil,
         onDone: (() -> Void)? = nil) {
        self.attachment = attachment
        self.pageSize = pageSize
        self.isEditing = isEditing
        self.onSelect = onSelect
        self.onCommit = onCommit
        self.onDelete = onDelete
        self.onDuplicate = onDuplicate
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
                        .clipped()
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(isEditing ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 2)
                        )
                        .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
                        .rotationEffect(.radians(Double(workingAttachment.rotation)))
                        .overlay(alignment: .top) {
                            if isEditing && !isInteracting {
                                controlBar
                                    .scaleEffect(0.9)
                                    .padding(.top, -60)
                            }
                        }
                }
                .position(workingAttachment.center)
                .gesture(editingGesture)
                .simultaneousGesture(TapGesture().onEnded { onSelect() })
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

    private var editingGesture: some Gesture {
        let drag = DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isEditing else { return }
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
                guard isEditing else { return }
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
                guard isEditing else { return }
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
        let aspect = size.height / max(size.width, 0.01)

        var newWidth = max(minDimension, min(size.width, maxWidth))
        var newHeight = newWidth * aspect

        if newHeight < minDimension {
            newHeight = minDimension
            newWidth = newHeight / max(aspect, 0.01)
        }

        if newHeight > maxHeight {
            newHeight = maxHeight
            newWidth = newHeight / max(aspect, 0.01)
        }

        return CGSize(width: newWidth, height: newHeight)
    }
}
