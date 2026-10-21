import AppKit
import CoreImage
import ImageIO
import PDFKit
import CoreText
import Testing
@testable import Amberflow

final class ActionFixture {
    let directory: URL
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Amberflow QA \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: directory) }
    func file(_ name: String = "file.txt", text: String = "Amberflow test content") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    func folder(_ name: String) throws -> URL {
        let url = directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func image(width: Int = 256, height: Int = 128, noise: Bool = false) throws -> CGImage {
        var bytes: [UInt8] = []
        var seed: UInt32 = 1977
        bytes.reserveCapacity(width * height * 4)
        for y in 0..<height { for x in 0..<width {
            if noise {
                seed = seed &* 1664525 &+ 1013904223
                bytes += [UInt8((seed >> 24) & 255), UInt8((seed >> 16) & 255), UInt8((seed >> 8) & 255), 255]
            } else { bytes += [UInt8((x * 37 + y * 13) % 256), UInt8((x * 11 + y * 47) % 256), UInt8((x * 7 + y * 19) % 256), 255] }
        } }
        let data = Data(bytes)
        return try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).union(.byteOrder32Big),
                                    provider: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
    func png(_ name: String = "sample.png", width: Int = 256, height: Int = 128) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try ImageFiles.write(image(width: width, height: height), to: url)
        return url
    }
}

struct FileActionTests {
    @Test func terminalUsesFilesParentAndSelectedFolderItself() throws {
        let fixture = try ActionFixture()
        let file = try fixture.file("quote ' dollar $ (example) 你好.txt")
        #expect(try FileActions.terminalDirectory(for: file) == fixture.directory.standardizedFileURL)
        #expect(try FileActions.terminalDirectory(for: fixture.directory) == fixture.directory.standardizedFileURL)
        #expect(throws: (any Error).self) { try FileActions.terminalDirectory(for: fixture.directory.appendingPathComponent("missing")) }
    }

    @Test func movePreservesCollidingFileAndUsesUniqueName() throws {
        let fixture = try ActionFixture()
        let source = try fixture.file("same.txt", text: "source")
        let folder = try fixture.folder("destination")
        let existing = folder.appendingPathComponent("same.txt")
        try "existing".write(to: existing, atomically: true, encoding: .utf8)
        let moved = try FileActions.move([source], to: folder)
        #expect(try String(contentsOf: existing, encoding: .utf8) == "existing")
        #expect(try String(contentsOf: moved[0], encoding: .utf8) == "source")
        #expect(moved[0].lastPathComponent == "same 2.txt")
        #expect(!FileManager.default.fileExists(atPath: source.path))
    }

    @Test func movingWithinSameFolderDoesNotDeleteOrRenameSource() throws {
        let fixture = try ActionFixture(); let file = try fixture.file()
        #expect(try FileActions.move([file], to: fixture.directory) == [file])
        #expect(try String(contentsOf: file, encoding: .utf8) == "Amberflow test content")
    }

    @Test func directoryCannotBeMovedInsideItself() throws {
        let fixture = try ActionFixture(); let nested = try fixture.folder("inside")
        #expect(throws: (any Error).self) { try FileActions.move([fixture.directory], to: nested) }
        #expect(FileManager.default.fileExists(atPath: nested.path))
    }

    @Test func partialMoveFailureRollsBackMovedFiles() throws {
        let fixture = try ActionFixture(); let file = try fixture.file(); let folder = try fixture.folder("target")
        #expect(throws: (any Error).self) { try FileActions.move([file, file], to: folder) }
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @Test @MainActor func copyAndCopyPathUseRealFilePasteboards() throws {
        let fixture = try ActionFixture(); let first = try fixture.file("one space.txt"); let second = try fixture.file("é two.txt")
        let pasteboard = NSPasteboard.withUniqueName(); defer { pasteboard.releaseGlobally() }
        try NativeFileActions.copyFiles([first, second], to: pasteboard)
        #expect(DraggedFiles.read(from: pasteboard) == [first, second])
        try NativeFileActions.copyPaths([first, second], to: pasteboard)
        #expect(pasteboard.string(forType: .string) == first.path + "\n" + second.path)
        #expect(throws: (any Error).self) { try NativeFileActions.copyFiles([fixture.directory.appendingPathComponent("missing")], to: pasteboard) }
        #expect(pasteboard.string(forType: .string) == first.path + "\n" + second.path)
    }
}

struct ImageActionTests {
    @Test func cropKeepsRequestedPixelsAndDimensions() throws {
        let fixture = try ActionFixture(); let input = try fixture.image()
        var settings = ImageEditSettings(); settings.crop = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        let output = try ImageFiles.render(input, tool: .crop, settings: settings)
        #expect(output.width == 128 && output.height == 64)
        #expect(pixel(output, x: 4, y: 4) == pixel(input, x: 4, y: 4))
    }

    @Test func redactionPermanentlyReplacesPixelsAndLeavesOtherPixels() throws {
        let fixture = try ActionFixture(); let input = try fixture.image()
        var settings = ImageEditSettings(); settings.redactions = [CGRect(x: 0, y: 0, width: 0.5, height: 0.5)]
        let output = try ImageFiles.render(input, tool: .redact, settings: settings)
        #expect(pixel(output, x: 20, y: 20) == [0, 0, 0, 255])
        #expect(pixel(output, x: 200, y: 90) == pixel(input, x: 200, y: 90))
    }

    @Test func backgroundAddsChosenColorAndPadding() throws {
        let fixture = try ActionFixture(); let input = try fixture.image()
        var settings = ImageEditSettings(); settings.padding = 0.125; settings.background = [0, 0, 1, 1]
        let output = try ImageFiles.render(input, tool: .addBackground, settings: settings)
        #expect(output.width == 320 && output.height == 192)
        #expect(pixel(output, x: 2, y: 2) == [0, 0, 255, 255])
    }

    @Test func annotationAndAdjustmentChangeActualImageData() throws {
        let fixture = try ActionFixture(); let input = try fixture.image()
        var settings = ImageEditSettings(); settings.annotation = "Hello Amberflow"
        let annotated = try ImageFiles.render(input, tool: .annotate, settings: settings)
        #expect(annotated.dataProvider!.data! as Data != input.dataProvider!.data! as Data)
        settings.quarterTurns = 1; settings.brightness = 0.2
        let edited = try ImageFiles.render(input, tool: .edit, settings: settings)
        #expect(edited.width == input.height && edited.height == input.width)
    }

    @Test func imageExportsNeverOverwriteOriginalOrPreviousResult() throws {
        let fixture = try ActionFixture(); let input = try fixture.png(); let before = try Data(contentsOf: input)
        var settings = ImageEditSettings(); settings.annotation = "Original remains"
        let first = try ImageFiles.export(input, tool: .annotate, settings: settings)
        let second = try ImageFiles.export(input, tool: .annotate, settings: settings)
        #expect(first != second && first != input)
        #expect(try Data(contentsOf: input) == before)
        #expect(try ImageFiles.load(first).width == 256)
    }

    @Test func compressionProducesSmallerDecodableJPEG() throws {
        let fixture = try ActionFixture(); let input = fixture.directory.appendingPathComponent("photo-like.png")
        try ImageFiles.write(fixture.image(width: 512, height: 512, noise: true), to: input)
        let result = try ImageFiles.export(input, tool: .compress, settings: ImageEditSettings())
        #expect(result.pathExtension == "jpg")
        #expect(try ImageFiles.load(result).width == 512)
        #expect(try Data(contentsOf: result).count < Data(contentsOf: input).count)
    }

    @Test func compressionRejectsLargerOutputForAlreadyOptimizedImages() throws {
        let fixture = try ActionFixture(); let input = try fixture.png(width: 512, height: 512)
        #expect(throws: (any Error).self) { try ImageFiles.export(input, tool: .compress, settings: ImageEditSettings()) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path) == ["sample.png"])
    }

    @Test func emptyCropAnnotationAndRedactionFailClearly() throws {
        let fixture = try ActionFixture(); let input = try fixture.image()
        for tool in [ImageTool.crop, .annotate, .redact] {
            #expect(throws: (any Error).self) { try ImageFiles.render(input, tool: tool, settings: ImageEditSettings()) }
        }
    }

    @Test func metadataInspectorReadsRealDimensionsAndSanitizerRemovesGPS() throws {
        let fixture = try ActionFixture(); let input = fixture.directory.appendingPathComponent("metadata.jpg")
        let properties: [CFString: Any] = [kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 35.0,
                                                                        kCGImagePropertyGPSLatitudeRef: "N",
                                                                        kCGImagePropertyGPSLongitude: 5.0,
                                                                        kCGImagePropertyGPSLongitudeRef: "W"],
                                         kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "private marker"]]
        try ImageFiles.write(fixture.image(), to: input, type: "public.jpeg", properties: properties)
        let metadata = try FileMetadata.entries(for: input)
        #expect(metadata.contains { $0.id == "Image.PixelWidth" && $0.value == "256" })
        #expect(metadata.contains { $0.id.contains("GPS.Latitude") })
        let clean = try FileMetadata.sanitizedCopy(of: input)
        let cleanMetadata = try FileMetadata.entries(for: clean)
        #expect(!cleanMetadata.contains { $0.id.contains("GPS") || $0.value.contains("private marker") })
        #expect(try FileMetadata.entries(for: input).contains { $0.id.contains("GPS.Latitude") })
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        let bytes = image.dataProvider!.data! as Data
        let offset = y * image.bytesPerRow + x * 4
        return Array(bytes[offset..<(offset + 4)])
    }
}

struct ConversionActionTests {
    @Test(arguments: ["PNG", "JPG", "HEIC", "TIFF"])
    func imageFormatsWriteValidImages(format: String) throws {
        let fixture = try ActionFixture(); let input = try fixture.png()
        #expect(ConversionService.canConvert(input, to: format))
        let output = try ConversionService.convert(input, to: format, preserveMetadata: false, in: fixture.directory)
        let decoded = try ImageFiles.load(output)
        #expect(decoded.width == 256 && decoded.height == 128)
        #expect(output != input)
    }

    @Test func imageToPDFAndPDFToImageAreReadable() throws {
        let fixture = try ActionFixture(); let input = try fixture.png()
        let pdf = try ConversionService.convert(input, to: "PDF", preserveMetadata: false, in: fixture.directory)
        #expect(PDFDocument(url: pdf)?.pageCount == 1)
        let output = try ConversionService.convert(pdf, to: "PNG", preserveMetadata: false, in: fixture.directory)
        #expect(try ImageFiles.load(output).width == 512)
    }

    @Test(arguments: ["TXT", "MD"])
    func textExportsPreserveContents(format: String) throws {
        let fixture = try ActionFixture(); let input = try fixture.file(text: "Hello\nCrème\nこんにちは")
        let output = try ConversionService.convert(input, to: format, preserveMetadata: false, in: fixture.directory)
        #expect(try String(contentsOf: output, encoding: .utf8) == String(contentsOf: input, encoding: .utf8))
    }

    @Test func textToPDFAndPDFTextExtractionPreserveText() throws {
        let fixture = try ActionFixture(); let input = try fixture.file(text: "HELLO AMBERFLOW\nThis is a PDF export test.")
        let pdf = try ConversionService.convert(input, to: "PDF", preserveMetadata: false, in: fixture.directory)
        let output = try ConversionService.convert(pdf, to: "TXT", preserveMetadata: false, in: fixture.directory)
        #expect(try String(contentsOf: output, encoding: .utf8).contains("HELLO AMBERFLOW"))
    }

    @Test func zipRoundTripPreservesTheFile() throws {
        let fixture = try ActionFixture(); let input = try fixture.file("quoted ' file.txt", text: "ZIP payload")
        let zip = try ConversionService.convert(input, to: "ZIP", preserveMetadata: false, in: fixture.directory)
        let destination = try fixture.folder("unpacked")
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, destination.path]; try process.run(); process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(try String(contentsOf: destination.appendingPathComponent(input.lastPathComponent), encoding: .utf8) == "ZIP payload")
    }

    @Test func unsupportedConversionsAndRecursiveZipAreRejected() throws {
        let fixture = try ActionFixture(); let input = try fixture.file()
        #expect(!ConversionService.canConvert(input, to: "PNG"))
        #expect(throws: (any Error).self) { try ConversionService.convert(input, to: "PNG", preserveMetadata: false, in: fixture.directory) }
        #expect(throws: (any Error).self) { try ConversionService.convert(fixture.directory, to: "ZIP", preserveMetadata: false, in: fixture.directory) }
    }

    @Test func allWheelOptionsHaveDefinedSupportRules() {
        let image = URL(fileURLWithPath: "/tmp/sample.png")
        let pdf = URL(fileURLWithPath: "/tmp/sample.pdf")
        let actions = [RadialMode.command, .control, .shift].flatMap { RadialItem.items(for: $0) }
        #expect(actions.count == 21)
        for action in actions { #expect(action.unavailableReason(for: [image]) == nil) }
        #expect(RadialItem.redact.unavailableReason(for: [pdf]) != nil)
        #expect(RadialItem.crop.unavailableReason(for: [image, image]) != nil)
    }

    @Test func imageTextConversionActuallyRecognizesText() throws {
        let fixture = try ActionFixture()
        let context = try ImageFiles.context(width: 1100, height: 220)
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1100, height: 220))
        let text = NSAttributedString(string: "HELLO AMBERFLOW", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica-Bold" as CFString, 64, nil), NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)])
        context.textPosition = CGPoint(x: 60, y: 90)
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
        let input = fixture.directory.appendingPathComponent("text-image.png")
        try ImageFiles.write(#require(context.makeImage()), to: input)
        for format in ["TXT", "MD"] {
            let output = try ConversionService.convert(input, to: format, preserveMetadata: false, in: fixture.directory)
            #expect(try String(contentsOf: output, encoding: .utf8).uppercased().contains("HELLO AMBERFLOW"))
        }
    }

    @Test func qrReaderDecodesActualQRCode() throws {
        let fixture = try ActionFixture()
        let filter = try #require(CIFilter(name: "CIQRCodeGenerator"))
        filter.setValue(Data("AMBERFLOW QR TEST".utf8), forKey: "inputMessage")
        let ciImage = try #require(filter.outputImage).transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let image = try #require(CIContext().createCGImage(ciImage, from: ciImage.extent))
        let input = fixture.directory.appendingPathComponent("qr.png")
        try ImageFiles.write(image, to: input)
        #expect(try VisionService.detectQR(at: input).contains("AMBERFLOW QR TEST"))
    }
}

struct NativeActionTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AMBERFLOW_NATIVE_ACTION_TESTS"] == "1"))
    func preparePersistentPanelFixtures() throws {
        let folder = URL(fileURLWithPath: "/Users/hicham/Desktop/App/Amberflow/build/Action QA", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fixture = try ActionFixture()
        try ImageFiles.write(fixture.image(width: 800, height: 500, noise: true), to: folder.appendingPathComponent("sample.png"))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["AMBERFLOW_NATIVE_ACTION_TESTS"] == "1"))
    @MainActor func terminalOpensSelectedFilesFolderWithoutChangingClipboard() async throws {
        let path = "/Users/hicham/Desktop/App/Amberflow/build/Terminal QA/drag example.txt"
        let input = URL(fileURLWithPath: path)
        let clipboardGeneration = NSPasteboard.general.changeCount
        let opened = try await NativeFileActions.openTerminal(for: input)
        #expect(opened == input.deletingLastPathComponent())
        #expect(NSPasteboard.general.changeCount == clipboardGeneration)
    }
}
