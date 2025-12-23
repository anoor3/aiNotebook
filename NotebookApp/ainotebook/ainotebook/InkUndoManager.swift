import Foundation

enum InkEdit {
    case addStroke(InkStroke)
    case clear(previous: [InkStroke])
}

struct InkUndoManager {
    private(set) var drawing: InkDrawing
    private var undoStack: [InkEdit] = []
    private var redoStack: [InkEdit] = []

    init(drawing: InkDrawing = .empty) {
        self.drawing = drawing
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    mutating func apply(_ edit: InkEdit) {
        applyEdit(edit)
        undoStack.append(edit)
        redoStack.removeAll()
    }

    mutating func clearAll() {
        let previous = drawing.strokes
        apply(.clear(previous: previous))
    }

    mutating func undo() -> InkDrawing? {
        guard let last = undoStack.popLast() else { return nil }
        revert(edit: last)
        redoStack.append(last)
        return drawing
    }

    mutating func redo() -> InkDrawing? {
        guard let edit = redoStack.popLast() else { return nil }
        applyEdit(edit)
        undoStack.append(edit)
        return drawing
    }

    private mutating func applyEdit(_ edit: InkEdit) {
        switch edit {
        case .addStroke(let stroke):
            drawing.strokes.append(stroke)
        case .clear:
            drawing.strokes.removeAll()
        }
    }

    private mutating func revert(edit: InkEdit) {
        switch edit {
        case .addStroke:
            _ = drawing.strokes.popLast()
        case .clear(let previous):
            drawing.strokes = previous
        }
    }
}
