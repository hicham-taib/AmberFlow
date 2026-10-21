import SwiftUI
import AppKit
import ImageIO
import CoreImage
import CoreText
import UniformTypeIdentifiers

enum ImageTool: String, Sendable {
    case edit, crop, annotate, addBackground, redact, compress
    init(_ action: RadialItem) {
        switch action {
        case .crop: self = .crop
        case .annotate: self = .annotate
        case .addBackground: self = .addBackground
        case .redact: self = .redact
        case .compress: self = .compress
        default: self = .edit
        }
    }
    var title: String {
        switch self {
        case .edit: return "Edit Image"
        case .crop: return "Crop Image"
        case .annotate: return "Annotate Image"
        case .addBackground: return "Add Background"
        case .redact: return "Redact Image"
        case .compress: return "Compress Image"
        }
    }
    var help: String {
        switch self {
        case .crop: return "Drag a rectangle around the area to keep."
        case .redact: return "Drag rectangles over areas to remove permanently from the saved copy."
        case .annotate: return "Enter text, then click the image to position it."
        case .addBackground: return "Choose a background color and the space around the image."
        case .compress: return "Save a smaller JPEG copy. Transparent areas become white."
        case .edit: return "Adjust color and brightness, or rotate the image."
        }
    }
}

struct ImageEditSettings: Sendable {
    var crop: CGRect?
    var redactions: [CGRect] = []
    var annotation = ""
    var annotationPoint = CGPoint(x: 0.08, y: 0.08)
    var background: [CGFloat] = [1, 1, 1, 1]
    var padding: CGFloat = 0.08
    var quality = 0.65
    var brightness = 0.0
    var contrast = 1.0
    var saturation = 1.0
    var quarterTurns = 0
}

enum ImageFiles {
    static let rasterExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "webp", "avif", "bmp", "gif"]

    static func load(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw FileActionError.unsupported("This file is not a supported raster image.")
        }
        let dimension = max(properties[kCGImagePropertyPixelWidth] as? Int ?? 1,
                            properties[kCGImagePropertyPixelHeight] as? Int ?? 1)
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: dimension]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw FileActionError.invalid("The image could not be decoded.")
        }
        return image
    }

    static func write(_ image: CGImage, to url: URL, type: String = UTType.png.identifier,
                      quality: Double = 0.9, properties: [CFString: Any] = [:]) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) else {
            throw FileActionError.unsupported("This Mac cannot write the selected image format.")
        }
        var options = properties
        options[kCGImageDestinationLossyCompressionQuality] = quality
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw FileActionError.invalid("The image could not be saved.")
        }
    }

    static func jpegSize(_ image: CGImage, quality: Double) -> Int {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return Int.max }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data.length : Int.max
    }

    static func context(width: Int, height: Int) throws -> CGContext {
        guard width > 0, height > 0, width <= 32_768, height <= 32_768,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw FileActionError.invalid("The image is too large to process.")
        }
        return context
    }

    static func adjusted(_ image: CGImage, settings: ImageEditSettings) throws -> CGImage {
        let orientations: [CGImagePropertyOrientation] = [.up, .right, .down, .left]
        var result = CIImage(cgImage: image).oriented(orientations[settings.quarterTurns % 4])
        result = result.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: settings.brightness,
                                                                      kCIInputContrastKey: settings.contrast,
                                                                      kCIInputSaturationKey: settings.saturation])
        guard let rendered = CIContext().createCGImage(result, from: result.extent) else {
            throw FileActionError.invalid("The adjustments could not be applied.")
        }
        return rendered
    }

    static func render(_ image: CGImage, tool: ImageTool, settings: ImageEditSettings) throws -> CGImage {
        if tool == .edit { return try adjusted(image, settings: settings) }
        if tool == .crop {
            guard let selection = settings.crop?.intersection(CGRect(x: 0, y: 0, width: 1, height: 1)),
                  !selection.isNull, selection.width > 0, selection.height > 0,
                  let cropped = image.cropping(to: CGRect(x: selection.minX * CGFloat(image.width),
                                                          y: selection.minY * CGFloat(image.height),
                                                          width: selection.width * CGFloat(image.width),
                                                          height: selection.height * CGFloat(image.height)).integral) else {
                throw FileActionError.invalid("Drag a crop rectangle first.")
            }
            return cropped
        }
        let padding = tool == .addBackground ? Int(CGFloat(max(image.width, image.height)) * settings.padding) : 0
        let width = image.width + padding * 2
        let height = image.height + padding * 2
        let context = try context(width: width, height: height)
        if tool == .addBackground || tool == .compress {
            let color = tool == .compress ? [CGFloat(1), 1, 1, 1] : settings.background
            context.setFillColor(red: color[0], green: color[1], blue: color[2], alpha: color[3])
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        context.draw(image, in: CGRect(x: padding, y: padding, width: image.width, height: image.height))
        if tool == .redact {
            guard !settings.redactions.isEmpty else { throw FileActionError.invalid("Draw at least one redaction rectangle.") }
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.setShouldAntialias(false)
            for rect in settings.redactions {
                let clipped = rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
                guard !clipped.isNull else { continue }
                context.fill(CGRect(x: clipped.minX * CGFloat(width), y: (1 - clipped.maxY) * CGFloat(height),
                                    width: clipped.width * CGFloat(width), height: clipped.height * CGFloat(height)).integral)
            }
        }
        if tool == .annotate {
            guard !settings.annotation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw FileActionError.invalid("Enter annotation text first.")
            }
            let fontSize = max(18, CGFloat(width) / 22)
            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
            let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font,
                                                           NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)]
            context.setShadow(offset: CGSize(width: 1, height: -1), blur: 2, color: CGColor(gray: 0, alpha: 1))
            for (index, text) in settings.annotation.components(separatedBy: "\n").enumerated() {
                context.textPosition = CGPoint(x: settings.annotationPoint.x * CGFloat(width),
                                               y: (1 - settings.annotationPoint.y) * CGFloat(height) - fontSize * (1 + CGFloat(index) * 1.2))
                CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)), context)
            }
        }
        guard let output = context.makeImage() else { throw FileActionError.invalid("Could not create the edited image.") }
        return output
    }

    static func export(_ input: URL, tool: ImageTool, settings: ImageEditSettings, in directory: URL? = nil) throws -> URL {
        let image = try render(load(input), tool: tool, settings: settings)
        if tool == .compress, jpegSize(image, quality: settings.quality) >= (try input.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0 {
            throw FileActionError.invalid("This image is already smaller than the requested JPEG. Choose a lower quality.")
        }
        let folder = directory ?? input.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ext = tool == .compress ? "jpg" : "png"
        let output = FileActions.uniqueURL(folder.appendingPathComponent("\(input.deletingPathExtension().lastPathComponent)-\(tool.rawValue).\(ext)"))
        try write(image, to: output, type: tool == .compress ? UTType.jpeg.identifier : UTType.png.identifier, quality: settings.quality)
        return output
    }
}

@MainActor
final class ImageToolModel: ObservableObject {
    let image: CGImage
    let input: URL
    let tool: ImageTool
    let outputDirectory: URL?
    @Published var settings = ImageEditSettings()
    @Published var selection: CGRect?
    @Published var backgroundColor = Color.white
    @Published var error = ""

    init(tool: ImageTool, url: URL, outputDirectory: URL?) throws {
        self.tool = tool; input = url; self.outputDirectory = outputDirectory
        image = try ImageFiles.load(url)
    }

    var preview: CGImage {
        if tool == .edit { return (try? ImageFiles.adjusted(image, settings: settings)) ?? image }
        if tool == .addBackground { return (try? ImageFiles.render(image, tool: tool, settings: settings)) ?? image }
        return image
    }
    var originalByteCount: Int { (try? input.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
    var compressedByteCount: Int {
        guard let rendered = try? ImageFiles.render(image, tool: .compress, settings: settings) else { return Int.max }
        return ImageFiles.jpegSize(rendered, quality: settings.quality)
    }
    var canSave: Bool {
        switch tool {
        case .crop: return settings.crop != nil
        case .redact: return !settings.redactions.isEmpty
        case .annotate: return !settings.annotation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .compress: return compressedByteCount < originalByteCount
        default: return true
        }
    }
}

@MainActor
final class ImageToolPanelController {
    static let shared = ImageToolPanelController()
    private var panel: NSWindow?

    func show(tool: ImageTool, url: URL, outputDirectory: URL?, onResult: @escaping (Result<URL, Error>) -> Void) throws {
        let model = try ImageToolModel(tool: tool, url: url, outputDirectory: outputDirectory)
        panel?.close()
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 640),
                            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "\(tool.title) · \(url.lastPathComponent)"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 620, height: 520)
        panel.contentView = NSHostingView(rootView: ImageToolView(model: model, onClose: { panel.close() }, onResult: onResult))
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }
}

struct ImageToolView: View {
    @ObservedObject var model: ImageToolModel
    let onClose: () -> Void
    let onResult: (Result<URL, Error>) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.tool.title).font(.title2.weight(.semibold))
            Text(model.tool.help).foregroundStyle(.secondary)
            controls
            canvas.frame(minHeight: 260).background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            if !model.error.isEmpty { Text(model.error).foregroundStyle(.red).font(.caption) }
            HStack {
                Text("Original stays unchanged · saves a new copy").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: onClose).keyboardShortcut(.cancelAction)
                Button("Save Copy") { save() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(.orange).disabled(!model.canSave)
            }
        }.padding(22).onChange(of: model.backgroundColor) { _, value in
            let color = NSColor(value).usingColorSpace(.sRGB) ?? .white
            model.settings.background = [color.redComponent, color.greenComponent, color.blueComponent, 1]
        }
    }

    @ViewBuilder private var controls: some View {
        switch model.tool {
        case .edit:
            HStack {
                VStack { Text("Brightness"); Slider(value: $model.settings.brightness, in: -0.5...0.5) }
                VStack { Text("Contrast"); Slider(value: $model.settings.contrast, in: 0.5...2) }
                VStack { Text("Saturation"); Slider(value: $model.settings.saturation, in: 0...2) }
                Button("Rotate 90°") { model.settings.quarterTurns = (model.settings.quarterTurns + 1) % 4 }
            }.font(.caption)
        case .annotate:
            TextField("Annotation text", text: $model.settings.annotation, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...3)
        case .addBackground:
            HStack { ColorPicker("Background", selection: $model.backgroundColor, supportsOpacity: false); Text("Padding"); Slider(value: $model.settings.padding, in: 0...0.25).frame(width: 200) }
        case .compress:
            HStack { Text("Quality"); Slider(value: $model.settings.quality, in: 0.15...0.95); Text("\(Int(model.settings.quality * 100))%").monospacedDigit() }
            let original = ByteCountFormatter.string(fromByteCount: Int64(model.originalByteCount), countStyle: .file)
            let compressed = ByteCountFormatter.string(fromByteCount: Int64(model.compressedByteCount), countStyle: .file)
            Text(model.canSave ? "\(original) → \(compressed)" : "Already optimized at this quality. Lower the quality to reduce size.").font(.caption).foregroundStyle(.secondary)
        case .redact:
            Button("Clear Redactions") { model.settings.redactions = [] }
        case .crop:
            Button("Reset Crop") { model.settings.crop = nil }
        }
    }

    private var canvas: some View {
        GeometryReader { geometry in
            let image = model.preview
            let scale = min(geometry.size.width / CGFloat(image.width), geometry.size.height / CGFloat(image.height))
            let width = CGFloat(image.width) * scale
            let height = CGFloat(image.height) * scale
            ZStack(alignment: .topLeading) {
                Rectangle().fill(model.tool == .addBackground ? model.backgroundColor : Color.clear)
                Image(nsImage: NSImage(cgImage: image, size: .zero)).resizable().frame(width: width, height: height)
                if let rect = model.settings.crop { selection(rect, width: width, height: height, color: .orange) }
                ForEach(Array(model.settings.redactions.enumerated()), id: \.offset) { _, rect in
                    Rectangle().fill(.black).frame(width: rect.width * width, height: rect.height * height).offset(x: rect.minX * width, y: rect.minY * height)
                }
                if let rect = model.selection { selection(rect, width: width, height: height, color: model.tool == .redact ? .black : .orange) }
                if model.tool == .annotate {
                    Text(model.settings.annotation).font(.system(size: max(18, CGFloat(image.width) / 22) * scale, weight: .bold))
                        .foregroundStyle(.white).shadow(color: .black, radius: 2)
                        .offset(x: model.settings.annotationPoint.x * width, y: model.settings.annotationPoint.y * height)
                }
            }
            .frame(width: width, height: height).clipped().contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let start = normalized(value.startLocation, width: width, height: height)
                let end = normalized(value.location, width: width, height: height)
                if model.tool == .annotate { model.settings.annotationPoint = end }
                else if model.tool == .crop || model.tool == .redact {
                    model.selection = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
                }
            }.onEnded { _ in
                if let rect = model.selection, rect.width > 0.005, rect.height > 0.005 {
                    if model.tool == .crop { model.settings.crop = rect }
                    else if model.tool == .redact { model.settings.redactions.append(rect) }
                }
                model.selection = nil
            })
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }

    private func normalized(_ point: CGPoint, width: CGFloat, height: CGFloat) -> CGPoint {
        CGPoint(x: min(1, max(0, point.x / width)), y: min(1, max(0, point.y / height)))
    }
    private func selection(_ rect: CGRect, width: CGFloat, height: CGFloat, color: Color) -> some View {
        Rectangle().fill(color.opacity(0.15)).overlay(Rectangle().stroke(color, lineWidth: 2))
            .frame(width: rect.width * width, height: rect.height * height).offset(x: rect.minX * width, y: rect.minY * height)
    }
    private func save() {
        let color = NSColor(model.backgroundColor).usingColorSpace(.sRGB) ?? .white
        model.settings.background = [color.redComponent, color.greenComponent, color.blueComponent, 1]
        do {
            let result = try ImageFiles.export(model.input, tool: model.tool, settings: model.settings, in: model.outputDirectory)
            onResult(.success(result)); onClose()
        } catch { model.error = error.localizedDescription; onResult(.failure(error)) }
    }
}
