import Foundation

enum AIChatPersistence {
    private static let directoryName = "AIChats"

    private static func directoryURL() -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(directoryName, isDirectory: true)
    }

    private static func fileURL(for notebookID: UUID) -> URL {
        directoryURL().appendingPathComponent("\(notebookID.uuidString).json")
    }

    static func load(for notebookID: UUID) -> [AIChatMessage]? {
        let url = fileURL(for: notebookID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([AIChatMessage].self, from: data)
    }

    static func save(_ messages: [AIChatMessage], for notebookID: UUID) {
        do {
            let dir = directoryURL()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(messages)
            try data.write(to: fileURL(for: notebookID), options: .atomic)
        } catch {
            print("AIChatPersistence save error: \(error)")
        }
    }

    static func delete(for notebookID: UUID) {
        let url = fileURL(for: notebookID)
        try? FileManager.default.removeItem(at: url)
    }
}
