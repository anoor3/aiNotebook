import Foundation
import SwiftUI

struct NotebookPageModel: Identifiable, Hashable {
    let id: UUID
    var title: String
    var created: Date
    var paperStyle: PaperStyle

    init(id: UUID = UUID(), title: String, created: Date = Date(), paperStyle: PaperStyle = .grid) {
        self.id = id
        self.title = title
        self.created = created
        self.paperStyle = paperStyle
    }
}

enum PaperStyle: String, CaseIterable, Identifiable {
    case grid = "Grid"
    case dot = "Dot"
    case blank = "Blank"
    case lined = "Lined"

    var id: String { rawValue }
}

struct Notebook: Identifiable, Hashable {
    let id: UUID
    var title: String
    var coverColor: Color
    var paperStyle: PaperStyle
    var lastOpened: Date
    var isFavorite: Bool
    var pages: [NotebookPageModel]
    var currentPageIndex: Int

    init(id: UUID = UUID(),
         title: String,
         coverColor: Color,
         paperStyle: PaperStyle = .grid,
         lastOpened: Date = Date(),
         isFavorite: Bool = false,
         pages: [NotebookPageModel] = [NotebookPageModel(title: "Page 1")],
         currentPageIndex: Int = 0) {
        self.id = id
        self.title = title
        self.coverColor = coverColor
        self.paperStyle = paperStyle
        self.lastOpened = lastOpened
        self.isFavorite = isFavorite

        let normalizedPages: [NotebookPageModel]
        if pages.isEmpty {
            normalizedPages = [NotebookPageModel(title: "Page 1", paperStyle: paperStyle)]
        } else {
            normalizedPages = pages.map { page in
                NotebookPageModel(id: page.id, title: page.title, created: page.created, paperStyle: paperStyle)
            }
        }

        self.pages = normalizedPages
        self.currentPageIndex = min(currentPageIndex, self.pages.count - 1)
    }

    static var sampleData: [Notebook] {
        [
            Notebook(title: "Product Design", coverColor: Color(red: 0.16, green: 0.3, blue: 0.58)),
            Notebook(title: "Meeting Notes", coverColor: Color(red: 0.85, green: 0.52, blue: 0.26), paperStyle: .lined),
            Notebook(title: "Sketchbook", coverColor: Color(red: 0.28, green: 0.68, blue: 0.38), paperStyle: .blank)
        ]
    }
}
