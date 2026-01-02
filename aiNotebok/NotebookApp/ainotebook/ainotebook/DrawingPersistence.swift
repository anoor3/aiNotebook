import Foundation
import PencilKit

enum DrawingPersistence {
    static func encode(_ drawing: PKDrawing) -> Data {
        drawing.dataRepresentation()
    }

    static func decode(from data: Data) -> PKDrawing? {
        try? PKDrawing(data: data)
    }

    static func save(_ drawing: PKDrawing, notebookID: UUID, pageID: UUID) {
        let data = encode(drawing)
        let url = drawingURL(notebookID: notebookID, pageID: pageID)

        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            print("DrawingPersistence save error:", error)
        }
    }

    static func load(notebookID: UUID, pageID: UUID) -> PKDrawing? {
        let url = drawingURL(notebookID: notebookID, pageID: pageID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(from: data)
    }

    private static func drawingURL(notebookID: UUID, pageID: UUID) -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Drawings", isDirectory: true)
            .appendingPathComponent(notebookID.uuidString, isDirectory: true)
            .appendingPathComponent("\(pageID.uuidString).drawing")
    }
}
