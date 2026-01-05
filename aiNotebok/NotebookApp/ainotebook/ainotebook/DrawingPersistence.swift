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

    static func deletePage(notebookID: UUID, pageID: UUID) {
        let url = drawingURL(notebookID: notebookID, pageID: pageID)
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            print("DrawingPersistence delete page error:", error)
        }
    }

    static func deleteNotebook(notebookID: UUID) {
        let directory = notebookDirectoryURL(notebookID: notebookID)
        do {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        } catch {
            print("DrawingPersistence delete notebook error:", error)
        }
    }

    private static func drawingURL(notebookID: UUID, pageID: UUID) -> URL {
        notebookDirectoryURL(notebookID: notebookID)
            .appendingPathComponent("\(pageID.uuidString).drawing")
    }

    private static func notebookDirectoryURL(notebookID: UUID) -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Drawings", isDirectory: true)
            .appendingPathComponent(notebookID.uuidString, isDirectory: true)
    }
}
