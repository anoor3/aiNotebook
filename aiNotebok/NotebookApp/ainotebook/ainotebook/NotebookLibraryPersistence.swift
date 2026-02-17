import Foundation

enum NotebookLibraryPersistence {
    private static let filename = "notebooks.json"
    private static let queue = DispatchQueue(label: "NotebookLibraryPersistence.queue", qos: .utility)

    static func load() -> [Notebook]? {
        let url = fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([Notebook].self, from: data)
        } catch {
            print("NotebookLibraryPersistence load error:", error)
            return nil
        }
    }

    static func save(_ notebooks: [Notebook]) {
        let url = fileURL()
        queue.async {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(notebooks)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            } catch {
                print("NotebookLibraryPersistence save error:", error)
            }
        }
    }

    private static func fileURL() -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("NotebookLibrary", isDirectory: true)
            .appendingPathComponent(filename)
    }
}
