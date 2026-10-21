import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers
import PDFKit
import CoreText
import Vision

enum ConversionService {
    static let imageTypes = ["JPG": UTType.jpeg.identifier, "PNG": UTType.png.identifier,
                             "HEIC": UTType.heic.identifier, "TIFF": UTType.tiff.identifier]
    static let textExtensions: Set<String> = ["txt", "md", "csv", "tsv", "json", "xml", "yaml", "yml", "log", "swift", "js", "ts", "py", "css", "sh", "c", "h", "cpp", "rtf"]

    static func canConvert(_ url: URL, to format: String) -> Bool {
        if format == "ZIP" { return true }
        let ext = url.pathExtension.lowercased()
        let image = ImageFiles.rasterExtensions.contains(ext)
        let pdf = ext == "pdf"
        let text = textExtensions.contains(ext)
        switch format {
        case "JPG", "PNG", "HEIC", "TIFF":
            let encoders = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
            return (image || pdf) && encoders.contains(imageTypes[format] ?? "")
        case "PDF", "TXT", "MD": return image || pdf || text
        default: return false
        }
    }

    static func convert(_ input: URL, to format: String, preserveMetadata: Bool, in folder: URL) throws -> URL {
        try FileActions.validate([input])
        guard canConvert(input, to: format) else { throw ConversionError.unsupported("\(input.pathExtension.uppercased()) to \(format)") }
        if format == "ZIP", (try input.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true {
            let source = input.resolvingSymlinksInPath().standardizedFileURL.path
            let destination = folder.resolvingSymlinksInPath().standardizedFileURL.path
            guard destination != source, !destination.hasPrefix(source + "/") else {
                throw FileActionError.invalid("Save the ZIP outside the folder being archived.")
            }
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let output = FileActions.uniqueURL(folder.appendingPathComponent("\(input.deletingPathExtension().lastPathComponent).\(format.lowercased())"))
        if let type = imageTypes[format] {
            let image = input.pathExtension.lowercased() == "pdf" ? try renderPDF(input) : try ImageFiles.load(input)
            var properties: [CFString: Any] = [:]
            if preserveMetadata, let source = CGImageSourceCreateWithURL(input as CFURL, nil) {
                properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
                properties[kCGImagePropertyOrientation] = 1
                if var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                    tiff[kCGImagePropertyTIFFOrientation] = 1
                    properties[kCGImagePropertyTIFFDictionary] = tiff
                }
            }
            let flattened = format == "JPG" ? try ImageFiles.render(image, tool: .compress, settings: ImageEditSettings()) : image
            try ImageFiles.write(flattened, to: output, type: type, properties: properties)
        } else {
            switch format {
            case "PDF":
                if input.pathExtension.lowercased() == "pdf" {
                    guard let document = PDFDocument(url: input), !document.isLocked else { throw FileActionError.invalid("The PDF is locked or unreadable.") }
                    if !preserveMetadata { document.documentAttributes = [:] }
                    guard document.write(to: output) else { throw ConversionError.failed("Could not save the PDF.") }
                } else if textExtensions.contains(input.pathExtension.lowercased()) {
                    try writeTextPDF(try extractText(input), to: output)
                } else { try writeImagePDF(ImageFiles.load(input), to: output) }
            case "TXT", "MD":
                try extractText(input).write(to: output, atomically: true, encoding: .utf8)
            case "ZIP":
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                let isDirectory = (try input.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true
                process.arguments = ["-c", "-k", "--sequesterRsrc"] + (isDirectory ? ["--keepParent"] : []) + [input.path, output.path]
                try process.run(); process.waitUntilExit()
                guard process.terminationStatus == 0 else { throw ConversionError.failed("ZIP export failed.") }
            default: throw ConversionError.unsupported(format)
            }
        }
        return output
    }

    static func renderPDF(_ url: URL, page number: Int = 1) throws -> CGImage {
        guard let document = CGPDFDocument(url as CFURL), let page = document.page(at: number) else {
            throw FileActionError.invalid("The PDF page could not be read.")
        }
        let bounds = page.getBoxRect(.mediaBox)
        guard bounds.width > 0, bounds.height > 0, bounds.width.isFinite, bounds.height.isFinite else {
            throw FileActionError.invalid("The PDF page has invalid dimensions.")
        }
        let scale = min(2, 8192 / max(bounds.width, bounds.height))
        let width = max(1, Int(bounds.width * scale))
        let height = max(1, Int(bounds.height * scale))
        let context = try ImageFiles.context(width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.fill(rect)
        context.concatenate(page.getDrawingTransform(.mediaBox, rect: rect, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        guard let image = context.makeImage() else { throw FileActionError.invalid("The PDF could not be rendered.") }
        return image
    }

    static func extractText(_ input: URL) throws -> String {
        let ext = input.pathExtension.lowercased()
        if ext == "pdf" {
            guard let document = PDFDocument(url: input), !document.isLocked else { throw FileActionError.invalid("The PDF is locked or unreadable.") }
            if let text = document.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
            var pages: [String] = []
            for index in 1...max(1, document.pageCount) { pages.append(try recognizeText(renderPDF(input, page: index))) }
            let text = pages.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw FileActionError.unsupported("No readable text was found in this PDF.") }
            return text
        }
        if ImageFiles.rasterExtensions.contains(ext) {
            let text = try recognizeText(ImageFiles.load(input))
            guard !text.isEmpty else { throw FileActionError.unsupported("No readable text was found in this image.") }
            return text
        }
        guard textExtensions.contains(ext) else { throw ConversionError.unsupported(ext) }
        if ext == "rtf" {
            return try NSAttributedString(url: input, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil).string
        }
        return try String(contentsOf: input, encoding: .utf8)
    }

    private static func recognizeText(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    static func writeImagePDF(_ image: CGImage, to output: URL) throws {
        var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let consumer = CGDataConsumer(url: output as CFURL), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw ConversionError.failed("Could not create the PDF.")
        }
        context.beginPDFPage(nil); context.draw(image, in: box); context.endPDFPage(); context.closePDF()
    }

    private static func writeTextPDF(_ text: String, to output: URL) throws {
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let consumer = CGDataConsumer(url: output as CFURL), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw ConversionError.failed("Could not create the PDF.")
        }
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let string = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let framesetter = CTFramesetterCreateWithAttributedString(string)
        let path = CGPath(rect: box.insetBy(dx: 42, dy: 42), transform: nil)
        var index = 0
        repeat {
            context.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: index, length: 0), path, nil)
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            context.endPDFPage()
            guard visible.length > 0 else { break }
            index += visible.length
        } while index < string.length
        context.closePDF()
    }
}

extension RadialItem {
    func unavailableReason(for urls: [URL]) -> String? {
        guard !urls.isEmpty else { return "Drag a file first." }
        let allImages = urls.allSatisfy { ImageFiles.rasterExtensions.contains($0.pathExtension.lowercased()) }
        switch self {
        case .edit, .crop, .annotate, .addBackground, .redact:
            guard urls.count == 1 else { return "Use one file at a time for this image tool." }
            if allImages { return nil }
            if [.edit, .crop, .annotate].contains(self), urls[0].pathExtension.lowercased() == "pdf" { return nil }
            if self == .edit { return nil }
            if self == .redact { return "Redaction supports images. Secure PDF redaction is not included." }
            return "This tool supports raster images only."
        case .compress:
            return allImages && urls.count > 1 ? "Compress one image at a time to choose its quality." : nil
        case .convert(let format):
            return urls.allSatisfy { ConversionService.canConvert($0, to: format) } ? nil : "\(format) is not supported for this file type."
        default: return nil
        }
    }
}
