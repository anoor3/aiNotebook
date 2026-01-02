import Foundation
import SwiftUI
import UIKit

struct NotebookPageModel: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var created: Date
    var paperStyle: PaperStyle
    var drawingData: Data?
    var images: [NotebookPageImage]

    private enum CodingKeys: String, CodingKey {
        case id, title, created, paperStyle, drawingData, images
    }

    init(id: UUID = UUID(),
         title: String,
         created: Date = Date(),
         paperStyle: PaperStyle = .grid,
         drawingData: Data? = nil,
         images: [NotebookPageImage] = []) {
        self.id = id
        self.title = title
        self.created = created
        self.paperStyle = paperStyle
        self.drawingData = drawingData
        self.images = images
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        created = try container.decodeIfPresent(Date.self, forKey: .created) ?? Date()
        paperStyle = try container.decodeIfPresent(PaperStyle.self, forKey: .paperStyle) ?? .grid
        drawingData = try container.decodeIfPresent(Data.self, forKey: .drawingData)
        images = try container.decodeIfPresent([NotebookPageImage].self, forKey: .images) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(created, forKey: .created)
        try container.encode(paperStyle, forKey: .paperStyle)
        try container.encodeIfPresent(drawingData, forKey: .drawingData)
        try container.encode(images, forKey: .images)
    }
}

struct NotebookPageImage: Identifiable, Hashable, Codable {
    let id: UUID
    var imageData: Data
    var center: CGPoint
    var size: CGSize
    var rotation: Double

    init(id: UUID = UUID(),
         imageData: Data,
         center: CGPoint,
         size: CGSize,
         rotation: Double = 0) {
        self.id = id
        self.imageData = imageData
        self.center = center
        self.size = size
        self.rotation = rotation
    }
}

enum PaperStyle: String, CaseIterable, Identifiable, Codable {
    case grid = "Grid"
    case dot = "Dot"
    case blank = "Blank"
    case lined = "Lined"

    var id: String { rawValue }
}

struct Notebook: Identifiable, Hashable, Codable {
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
                NotebookPageModel(id: page.id,
                                  title: page.title,
                                  created: page.created,
                                  paperStyle: paperStyle,
                                  drawingData: page.drawingData,
                                  images: page.images)
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
    private enum CodingKeys: String, CodingKey {
        case id, title, coverColor, paperStyle, lastOpened, isFavorite, pages, currentPageIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        let codableColor = try container.decode(CodableColor.self, forKey: .coverColor)
        coverColor = codableColor.color
        paperStyle = try container.decode(PaperStyle.self, forKey: .paperStyle)
        lastOpened = try container.decode(Date.self, forKey: .lastOpened)
        isFavorite = try container.decode(Bool.self, forKey: .isFavorite)
        let decodedPages = try container.decodeIfPresent([NotebookPageModel].self, forKey: .pages) ?? []
        pages = Notebook.normalizePages(decodedPages, paperStyle: paperStyle)
        currentPageIndex = min(try container.decodeIfPresent(Int.self, forKey: .currentPageIndex) ?? 0,
                               max(pages.count - 1, 0))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(CodableColor(coverColor), forKey: .coverColor)
        try container.encode(paperStyle, forKey: .paperStyle)
        try container.encode(lastOpened, forKey: .lastOpened)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(pages, forKey: .pages)
        try container.encode(currentPageIndex, forKey: .currentPageIndex)
    }
}

private extension Notebook {
    static func normalizePages(_ pages: [NotebookPageModel], paperStyle: PaperStyle) -> [NotebookPageModel] {
        if pages.isEmpty {
            return [NotebookPageModel(title: "Page 1", paperStyle: paperStyle)]
        }
        return pages.map { page in
            NotebookPageModel(id: page.id,
                              title: page.title,
                              created: page.created,
                              paperStyle: paperStyle,
                              drawingData: page.drawingData,
                              images: page.images)
        }
    }
}

struct CodableColor: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(_ color: Color) {
        let uiColor = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 1
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        red = Double(r)
        green = Double(g)
        blue = Double(b)
        alpha = Double(a)
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}
