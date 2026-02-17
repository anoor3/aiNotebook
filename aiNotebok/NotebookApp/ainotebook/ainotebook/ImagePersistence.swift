import Foundation
import UIKit

enum ImagePersistence {
    static func save(_ data: Data, notebookID: UUID, imageID: UUID) {
        let url = imageURL(notebookID: notebookID, imageID: imageID)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            print("ImagePersistence save error:", error)
        }
    }

    static func load(notebookID: UUID, imageID: UUID) -> Data? {
        let url = imageURL(notebookID: notebookID, imageID: imageID)
        return try? Data(contentsOf: url)
    }

    static func deleteNotebook(notebookID: UUID) {
        let directory = notebookDirectoryURL(notebookID: notebookID)
        try? FileManager.default.removeItem(at: directory)
    }

    private static func imageURL(notebookID: UUID, imageID: UUID) -> URL {
        notebookDirectoryURL(notebookID: notebookID)
            .appendingPathComponent("\(imageID.uuidString).img")
    }

    private static func notebookDirectoryURL(notebookID: UUID) -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Images", isDirectory: true)
            .appendingPathComponent(notebookID.uuidString, isDirectory: true)
    }
}
