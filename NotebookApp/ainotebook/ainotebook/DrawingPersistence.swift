import Foundation
#if canImport(PencilKit)
import PencilKit
#endif

enum DrawingPersistence {
    private static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func encode(_ drawing: InkDrawing) -> Data {
        (try? jsonEncoder.encode(drawing)) ?? Data()
    }

    static func decode(from data: Data) -> InkDrawing? {
        try? jsonDecoder.decode(InkDrawing.self, from: data)
    }

    static func decodeOrMigrate(_ data: Data) -> InkDrawing? {
        if let decoded = decode(from: data) {
            return decoded
        }
#if canImport(PencilKit)
        return convertLegacyDrawing(data: data)
#else
        return nil
#endif
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

        if let data = try? Data(contentsOf: url), let decoded = decode(from: data) {
            return decoded
        }

        // Attempt migration from legacy PKDrawing file if present.
        if let migrated = migrateLegacyDrawing(notebookID: notebookID, pageID: pageID) {
            return migrated
        }

        return nil
    }

    private static func migrateLegacyDrawing(notebookID: UUID, pageID: UUID) -> InkDrawing? {
        let legacyURL = legacyDrawingURL(notebookID: notebookID, pageID: pageID)
        guard let legacyData = try? Data(contentsOf: legacyURL) else { return nil }
#if canImport(PencilKit)
        guard let converted = convertLegacyDrawing(data: legacyData) else { return nil }
        save(converted, notebookID: notebookID, pageID: pageID)
        return converted
#else
        return nil
#endif
    }

#if canImport(PencilKit)
    private static func convertLegacyDrawing(data: Data) -> InkDrawing? {
        guard let pkDrawing = try? PKDrawing(data: data) else { return nil }
        let strokes: [InkStroke] = pkDrawing.strokes.map { stroke in
            let points = stroke.path.map { point in
                StrokePoint(location: CodablePoint(point.location),
                            force: point.force,
                            azimuth: point.azimuth,
                            altitude: point.altitude,
                            timestamp: point.timeOffset,
                            width: point.size.width)
            }
            let style = InkStyle(color: CodableColor(stroke.ink.color),
                                 isEraser: stroke.ink.inkType == .eraser,
                                 baseWidth: stroke.path.first?.size.width ?? 3.0)
            return InkStroke(id: UUID(), points: points, style: style)
        }
        return InkDrawing(strokes: strokes)
    }
#endif

    private static func drawingURL(notebookID: UUID, pageID: UUID) -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Drawings", isDirectory: true)
            .appendingPathComponent(notebookID.uuidString, isDirectory: true)
            .appendingPathComponent("\(pageID.uuidString).drawing")
    }

    static func voiceNoteURL(notebookID: UUID, pageID: UUID, noteID: UUID) -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("VoiceNotes", isDirectory: true)
            .appendingPathComponent(notebookID.uuidString, isDirectory: true)
            .appendingPathComponent(pageID.uuidString, isDirectory: true)
            .appendingPathComponent("\(noteID.uuidString).m4a")
    }

    static func existingVoiceNoteURL(fileName: String, notebookID: UUID, pageID: UUID?) -> URL? {
        guard let pageID else { return nil }
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = base
            .appendingPathComponent("VoiceNotes", isDirectory: true)
            .appendingPathComponent(notebookID.uuidString, isDirectory: true)
            .appendingPathComponent(pageID.uuidString, isDirectory: true)
            .appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func legacyDrawingURL(notebookID: UUID, pageID: UUID) -> URL {
        drawingURL(notebookID: notebookID, pageID: pageID)
    }
}
