import Foundation

enum SessionStatePersistence {
    private static let notebookKey = "LastOpenedNotebookID"
    private static let pageIndexKey = "LastOpenedNotebookPageIndex"

    static func save(notebookID: UUID, pageIndex: Int) {
        let defaults = UserDefaults.standard
        defaults.set(notebookID.uuidString, forKey: notebookKey)
        defaults.set(pageIndex, forKey: pageIndexKey)
    }

    static func load() -> (UUID, Int)? {
        let defaults = UserDefaults.standard
        guard let idString = defaults.string(forKey: notebookKey),
              let id = UUID(uuidString: idString) else { return nil }
        let pageIndex = defaults.integer(forKey: pageIndexKey)
        return (id, pageIndex)
    }

    static func clear() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: notebookKey)
        defaults.removeObject(forKey: pageIndexKey)
    }

    static func clearIfMatching(_ notebookID: UUID) {
        let defaults = UserDefaults.standard
        guard let idString = defaults.string(forKey: notebookKey) else { return }
        if idString == notebookID.uuidString {
            clear()
        }
    }
}
