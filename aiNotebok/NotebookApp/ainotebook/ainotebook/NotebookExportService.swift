import Foundation
import SwiftUI
import UIKit
import PencilKit

struct NotebookExportPagePayload {
    let id: UUID
    let title: String
    let pageNumber: Int
    let paperStyle: PaperStyle
    let drawingData: Data
    let attachments: [NotebookPageImage]
}

enum NotebookExportFormat: String, CaseIterable, Identifiable {
    case pdf
    case images

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pdf: return "PDF"
        case .images: return "Images"
        }
    }

    var description: String {
        switch self {
        case .pdf:
            return "Combine selected pages into a single PDF."
        case .images:
            return "Export each page as a separate PNG image."
        }
    }
}

enum NotebookExportError: LocalizedError {
    case renderFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .renderFailed:
            return "Couldn’t render one of the notebook pages."
        case .writeFailed:
            return "Failed to write the exported file."
        }
    }
}

enum NotebookExportService {
    static func export(pages: [NotebookExportPagePayload],
                       format: NotebookExportFormat,
                       notebookTitle: String,
                       pageSize: CGSize) throws -> [URL] {
        guard !pages.isEmpty else { return [] }

        switch format {
        case .pdf:
            let url = try exportPDF(pages: pages,
                                    notebookTitle: notebookTitle,
                                    pageSize: pageSize)
            return [url]
        case .images:
            return try exportImages(pages: pages,
                                    notebookTitle: notebookTitle,
                                    pageSize: pageSize)
        }
    }

    private static func exportPDF(pages: [NotebookExportPagePayload],
                                  notebookTitle: String,
                                  pageSize: CGSize) throws -> URL {
        let bounds = CGRect(origin: .zero, size: pageSize)
        let rendererFormat = UIGraphicsPDFRendererFormat()
        rendererFormat.documentInfo = [
            kCGPDFContextCreator as String: "Notebook Export",
            kCGPDFContextTitle as String: notebookTitle
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: rendererFormat)
        let url = temporaryURL(for: notebookTitle, extension: "pdf")

        do {
            try renderer.writePDF(to: url) { context in
                for page in pages {
                    context.beginPage()
                    render(page: page,
                           in: context.cgContext,
                           pageSize: pageSize)
                }
            }
        } catch {
            throw NotebookExportError.writeFailed
        }

        return url
    }

    private static func exportImages(pages: [NotebookExportPagePayload],
                                     notebookTitle: String,
                                     pageSize: CGSize) throws -> [URL] {
        var urls: [URL] = []
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = UIScreen.main.scale
        format.opaque = true
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: pageSize, format: format)

        for page in pages {
            let image = renderer.image { context in
                render(page: page,
                       in: context.cgContext,
                       pageSize: pageSize)
            }

            guard let data = image.pngData() else {
                throw NotebookExportError.renderFailed
            }

            let filename = "\(sanitizeFilename(notebookTitle))-page\(page.pageNumber)-\(UUID().uuidString).png"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

            do {
                try data.write(to: url, options: .atomic)
            } catch {
                throw NotebookExportError.writeFailed
            }
            urls.append(url)
        }

        return urls
    }

    private static func render(page: NotebookExportPagePayload,
                                in context: CGContext,
                                pageSize: CGSize) {
        let rect = CGRect(origin: .zero, size: pageSize)
        let image = snapshotDrawing(drawingData: page.drawingData,
                                    pageSize: pageSize,
                                    attachments: page.attachments,
                                    paperStyle: page.paperStyle)
        context.saveGState()
        context.interpolationQuality = .high
        image.draw(in: rect)
        context.restoreGState()
    }

    private static func drawBackground(in context: CGContext, rect: CGRect) {
        let pageColor = UIColor(red: 252/255, green: 244/255, blue: 220/255, alpha: 1.0)
        context.setFillColor(pageColor.cgColor)
        context.fill(rect)
    }

    private static func drawPaperStyle(_ style: PaperStyle,
                                       in context: CGContext,
                                       rect: CGRect) {
        let gridColor = UIColor(red: 205/255, green: 205/255, blue: 185/255, alpha: 0.85)
        context.saveGState()
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        switch style {
        case .grid:
            context.setStrokeColor(gridColor.cgColor)
            context.setLineWidth(1.0 / UIScreen.main.scale)
            drawGrid(in: context, rect: rect)
        case .dot:
            context.setFillColor(gridColor.withAlphaComponent(0.4).cgColor)
            drawDots(in: context, rect: rect)
        case .blank:
            break
        case .lined:
            context.setStrokeColor(UIColor(red: 0.63, green: 0.7, blue: 0.86, alpha: 0.5).cgColor)
            context.setLineWidth(1.0 / UIScreen.main.scale)
            drawLines(in: context, rect: rect)
        }

        context.restoreGState()
    }

    private static func drawGrid(in context: CGContext, rect: CGRect) {
        let spacing: CGFloat = 32
        let insetRect = rect.insetBy(dx: 0.5, dy: 0.5)

        var x = insetRect.minX
        while x <= insetRect.maxX + 0.5 {
            context.move(to: CGPoint(x: x, y: insetRect.minY))
            context.addLine(to: CGPoint(x: x, y: insetRect.maxY))
            x += spacing
        }

        var y = insetRect.minY
        while y <= insetRect.maxY + 0.5 {
            context.move(to: CGPoint(x: insetRect.minX, y: y))
            context.addLine(to: CGPoint(x: insetRect.maxX, y: y))
            y += spacing
        }

        context.strokePath()
    }

    private static func drawDots(in context: CGContext, rect: CGRect) {
        let spacing: CGFloat = 28
        let dotSize: CGFloat = 2
        let insetRect = rect.insetBy(dx: 0.5, dy: 0.5)

        for x in stride(from: insetRect.minX, through: insetRect.maxX, by: spacing) {
            for y in stride(from: insetRect.minY, through: insetRect.maxY, by: spacing) {
                let dotRect = CGRect(x: x - dotSize / 2,
                                     y: y - dotSize / 2,
                                     width: dotSize,
                                     height: dotSize)
                context.fillEllipse(in: dotRect)
            }
        }
    }

    private static func drawLines(in context: CGContext, rect: CGRect) {
        let spacing: CGFloat = 32
        let insetRect = rect.insetBy(dx: 0.5, dy: 0.5)

        for y in stride(from: insetRect.minY, through: insetRect.maxY, by: spacing) {
            context.move(to: CGPoint(x: insetRect.minX, y: y))
            context.addLine(to: CGPoint(x: insetRect.maxX, y: y))
        }
        context.strokePath()
    }

    private static func snapshotDrawing(drawingData: Data,
                                         pageSize: CGSize,
                                         attachments: [NotebookPageImage],
                                         paperStyle: PaperStyle) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3.0
        format.opaque = true
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: pageSize, format: format)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: pageSize)
            drawBackground(in: ctx.cgContext, rect: rect)
            drawPaperStyle(paperStyle, in: ctx.cgContext, rect: rect)
            if let drawing = DrawingPersistence.decode(from: drawingData) {
                let drawingImage = drawing.image(from: rect, scale: format.scale)
                ctx.cgContext.saveGState()
                ctx.cgContext.interpolationQuality = .high
                drawingImage.draw(in: rect)
                ctx.cgContext.restoreGState()
            }
            ctx.cgContext.saveGState()
            drawAttachments(attachments, in: ctx.cgContext)
            ctx.cgContext.restoreGState()
        }
    }

    private static func drawAttachments(_ attachments: [NotebookPageImage], in context: CGContext) {
        for attachment in attachments {
            guard let image = UIImage(data: attachment.imageData) else { continue }
            let size = attachment.size
            let frame = CGRect(x: -size.width / 2,
                               y: -size.height / 2,
                               width: size.width,
                               height: size.height)

            context.saveGState()
            context.translateBy(x: attachment.center.x, y: attachment.center.y)
            context.rotate(by: CGFloat(attachment.rotation))
            context.interpolationQuality = .high
            let clipPath = UIBezierPath(roundedRect: frame, cornerRadius: 18)
            clipPath.addClip()
            image.draw(in: frame)
            context.restoreGState()
        }
    }

    private static func temporaryURL(for notebookTitle: String, extension fileExtension: String) -> URL {
        let sanitized = sanitizeFilename(notebookTitle)
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("\(sanitized)-export-\(UUID().uuidString).\(fileExtension)")
    }

    private static func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return name.components(separatedBy: invalid).joined(separator: "-")
    }
}
