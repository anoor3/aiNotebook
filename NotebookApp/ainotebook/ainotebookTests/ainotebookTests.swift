//
//  ainotebookTests.swift
//  ainotebookTests
//
//  Created by Abdullah Noor on 12/15/25.
//

import Testing
@testable import ainotebook

struct ainotebookTests {

    @Test func drawingEncodingRoundTrips() throws {
        let style = InkStyle(color: CodableColor(.systemBlue), isEraser: false, baseWidth: 3.0)
        let points = [
            StrokePoint(location: CodablePoint(CGPoint(x: 1, y: 2)), force: 0.5, azimuth: 0.1, altitude: 0.7, timestamp: 0.1, width: 2.5),
            StrokePoint(location: CodablePoint(CGPoint(x: 3, y: 4)), force: 0.6, azimuth: 0.2, altitude: 0.6, timestamp: 0.2, width: 2.6),
            StrokePoint(location: CodablePoint(CGPoint(x: 5, y: 6)), force: 0.7, azimuth: 0.3, altitude: 0.5, timestamp: 0.3, width: 2.7)
        ]
        let stroke = InkStroke(id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!, points: points, style: style)
        let drawing = InkDrawing(strokes: [stroke])

        let data = DrawingPersistence.encode(drawing)
        let decoded = DrawingPersistence.decode(from: data)

        #expect(decoded == drawing)
    }

    @Test func undoManagerSupportsUndoRedo() throws {
        let strokeA = InkStroke(id: UUID(), points: [], style: InkStyle(color: CodableColor(.black), isEraser: false, baseWidth: 3))
        let strokeB = InkStroke(id: UUID(), points: [], style: InkStyle(color: CodableColor(.red), isEraser: false, baseWidth: 3))

        var manager = InkUndoManager()
        #expect(manager.canUndo == false)
        #expect(manager.canRedo == false)

        manager.apply(.addStroke(strokeA))
        #expect(manager.drawing.strokes.count == 1)
        #expect(manager.canUndo)
        #expect(manager.canRedo == false)

        manager.apply(.addStroke(strokeB))
        #expect(manager.drawing.strokes.count == 2)

        _ = manager.undo()
        #expect(manager.drawing.strokes.last == strokeA)
        #expect(manager.canUndo)
        #expect(manager.canRedo)

        _ = manager.redo()
        #expect(manager.drawing.strokes.last == strokeB)
        #expect(manager.canRedo == false)
    }
}
