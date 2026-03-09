import AppKit
import PDFKit
import UniformTypeIdentifiers

final class FileService {
    static let shared = FileService()
    private init() {}

    // MARK: - File picker

    @MainActor
    func pickFiles() -> [Attachment] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .image, .pdf, .plainText, .sourceCode,
            .json, .xml, .yaml, .swiftSource, .pythonScript
        ]
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap { processFile(url: $0) }
    }

    // MARK: - Route by extension

    func processFile(url: URL) -> Attachment? {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent
        switch ext {
        case "pdf":
            return processPDF(url: url, name: name)
        case "png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "heic", "heif":
            return processImageURL(url: url, name: name)
        default:
            return processTextFile(url: url, name: name)
        }
    }

    // MARK: - Image

    func processImageURL(url: URL, name: String) -> Attachment? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return processImageData(data, name: name)
    }

    func processImageData(_ data: Data, name: String = "Screenshot") -> Attachment? {
        let resized = resizeIfNeeded(data: data, maxBytes: 3_000_000)
        return Attachment(type: .image, name: name, data: resized)
    }

    // MARK: - PDF

    func processPDF(url: URL, name: String) -> Attachment? {
        guard let doc = PDFDocument(url: url) else { return nil }
        var text = ""
        for i in 0..<doc.pageCount {
            text += doc.page(at: i)?.string ?? ""
            text += "\n"
        }
        return Attachment(type: .pdf, name: name, text: text)
    }

    // MARK: - Text

    func processTextFile(url: URL, name: String) -> Attachment? {
        let text = (try? String(contentsOf: url, encoding: .utf8))
            ?? (try? String(contentsOf: url, encoding: .isoLatin1))
        guard let text else { return nil }
        return Attachment(type: .text, name: name, text: text)
    }

    // MARK: - Clipboard image

    func imageFromClipboard() -> Attachment? {
        let pb = NSPasteboard.general
        if let data = pb.data(forType: .png) {
            return processImageData(data, name: "Screenshot")
        }
        if let data = pb.data(forType: .tiff),
           let img = NSImage(data: data),
           let png = img.pngData() {
            return processImageData(png, name: "Screenshot")
        }
        return nil
    }

    // MARK: - Resize helper

    private func resizeIfNeeded(data: Data, maxBytes: Int) -> Data {
        guard data.count > maxBytes, let img = NSImage(data: data) else { return data }
        let scale  = sqrt(Double(maxBytes) / Double(data.count))
        let newSz  = NSSize(width: img.size.width * scale, height: img.size.height * scale)
        let canvas = NSImage(size: newSz)
        canvas.lockFocus()
        img.draw(in: NSRect(origin: .zero, size: newSz))
        canvas.unlockFocus()
        return canvas.pngData() ?? data
    }
}

// MARK: - NSImage → PNG

extension NSImage {
    func pngData() -> Data? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }
}
