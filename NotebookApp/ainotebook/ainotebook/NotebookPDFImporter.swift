import Foundation
import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import UIKit

enum NotebookPDFImporterError: LocalizedError {
    case invalidDocument
    case emptyDocument
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .invalidDocument:
            return "The selected PDF file couldn’t be opened."
        case .emptyDocument:
            return "The PDF doesn’t contain any pages."
        case .renderFailed:
            return "Failed to render one of the PDF pages."
        }
    }
}

enum NotebookPDFImporter {
    private static let basePageSize = CGSize(width: 800, height: 1000)

    static func importNotebook(from url: URL,
                               preferredTitle: String?,
                               coverColor: Color,
                               paperStyle: PaperStyle,
                               paperColor: PaperColor) async throws -> Notebook {
        let pageModels = try await loadPageModelsAsync(from: url, paperStyle: paperStyle)
        let trimmedTitle = preferredTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle: String
        if let trimmedTitle, !trimmedTitle.isEmpty {
            resolvedTitle = trimmedTitle
        } else {
            resolvedTitle = url.deletingPathExtension().lastPathComponent
        }

        return Notebook(title: resolvedTitle.isEmpty ? "Imported PDF" : resolvedTitle,
                        coverColor: coverColor,
                        paperStyle: paperStyle,
                        paperColor: paperColor,
                        pages: pageModels,
                        currentPageIndex: 0)
    }

    static func importPages(from url: URL,
                            paperStyle: PaperStyle) async throws -> [NotebookPageModel] {
        try await loadPageModelsAsync(from: url, paperStyle: paperStyle)
    }

    private static func loadPageModelsAsync(from url: URL,
                                            paperStyle: PaperStyle) async throws -> [NotebookPageModel] {
        try await Task.detached(priority: .userInitiated) {
            try loadPageModels(from: url, paperStyle: paperStyle)
        }.value
    }

    private static func loadPageModels(from url: URL,
                                       paperStyle: PaperStyle) throws -> [NotebookPageModel] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let document = PDFDocument(url: url) else {
            throw NotebookPDFImporterError.invalidDocument
        }

        let pageCount = document.pageCount
        guard pageCount > 0 else {
            throw NotebookPDFImporterError.emptyDocument
        }

        var pageModels: [NotebookPageModel] = []
        pageModels.reserveCapacity(pageCount)

        for index in 0..<pageCount {
            try autoreleasepool {
                guard let pdfPage = document.page(at: index),
                      let rendered = render(page: pdfPage, targetSize: basePageSize),
                      let data = rendered.pngData() ?? rendered.jpegData(compressionQuality: 0.95) else {
                    throw NotebookPDFImporterError.renderFailed
                }

                let attachment = NotebookPageImage(imageData: data,
                                                    center: CGPoint(x: basePageSize.width / 2,
                                                                     y: basePageSize.height / 2),
                                                    size: basePageSize,
                                                    rotation: 0,
                                                    isLocked: true)

                let pageModel = NotebookPageModel(title: "Page \(index + 1)",
                                                  paperStyle: paperStyle,
                                                  drawingData: nil,
                                                  images: [attachment])
                pageModels.append(pageModel)
            }
        }

        return pageModels
    }

    private static func render(page: PDFPage, targetSize: CGSize) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: targetSize))

            guard let pdfPageRef = page.pageRef else { return }

            ctx.cgContext.saveGState()
            ctx.cgContext.translateBy(x: 0, y: targetSize.height)
            ctx.cgContext.scaleBy(x: 1, y: -1)

            let rect = CGRect(origin: .zero, size: targetSize)
            let transform = pdfPageRef.getDrawingTransform(.mediaBox,
                                                           rect: rect,
                                                           rotate: 0,
                                                           preserveAspectRatio: true)
            ctx.cgContext.concatenate(transform)
            ctx.cgContext.drawPDFPage(pdfPageRef)
            ctx.cgContext.restoreGState()
        }
    }
}

struct PDFDocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void
    var onCancel: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf], asCopy: true)
        controller.delegate = context.coordinator
        controller.allowsMultipleSelection = false
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let onCancel: (() -> Void)?

        init(onPick: @escaping (URL) -> Void, onCancel: (() -> Void)?) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel?()
        }
    }
}
