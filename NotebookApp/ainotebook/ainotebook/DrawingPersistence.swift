import Foundation

enum DrawingPersistence {
    static func encode(_ drawing: InkDrawing) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(drawing)) ?? Data()
    }

    static func decode(from data: Data) -> InkDrawing? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(InkDrawing.self, from: data)
    }

    static func save(_ drawing: InkDrawing, notebookID: UUID, pageID: UUID) {
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

    static func load(notebookID: UUID, pageID: UUID) -> InkDrawing? {
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
