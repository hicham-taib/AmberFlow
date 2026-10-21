import SwiftUI
import AppKit
import ImageIO
import PDFKit

struct MetadataEntry: Identifiable {
    let id: String
    let value: String
}

enum FileMetadata {
    static func entries(for url: URL) throws -> [MetadataEntry] {
        try FileActions.validate([url])
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey, .typeIdentifierKey, .isDirectoryKey])
        var entries = [MetadataEntry(id: "Name", value: url.lastPathComponent),
                       MetadataEntry(id: "Location", value: url.deletingLastPathComponent().path),
                       MetadataEntry(id: "Type", value: values.typeIdentifier ?? "Unknown"),
                       MetadataEntry(id: "Size", value: ByteCountFormatter.string(fromByteCount: Int64(values.fileSize ?? 0), countStyle: .file))]
        if let date = values.creationDate { entries.append(.init(id: "Created", value: date.formatted())) }
        if let date = values.contentModificationDate { entries.append(.init(id: "Modified", value: date.formatted())) }
        if ImageFiles.rasterExtensions.contains(url.pathExtension.lowercased()),
           let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
            entries += flatten(properties, prefix: "Image")
        } else if url.pathExtension.lowercased() == "pdf", let document = PDFDocument(url: url) {
            entries.append(.init(id: "PDF.Pages", value: "\(document.pageCount)"))
            entries.append(.init(id: "PDF.Encrypted", value: document.isEncrypted ? "Yes" : "No"))
            let attributes: [AnyHashable: Any] = document.documentAttributes ?? [:]
            for (key, value) in attributes.sorted(by: { String(describing: $0.key) < String(describing: $1.key) }) {
                entries.append(.init(id: "PDF.\(key)", value: String(describing: value)))
            }
        }
        return entries
    }

    private static func flatten(_ values: [String: Any], prefix: String) -> [MetadataEntry] {
        values.sorted { $0.key < $1.key }.flatMap { key, value -> [MetadataEntry] in
            let name = prefix + "." + key.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
            if let dictionary = value as? [String: Any] { return flatten(dictionary, prefix: name) }
            if value is Data { return [.init(id: name, value: "Binary data")] }
            return [.init(id: name, value: String(describing: value))]
        }
    }

    static func sanitizedCopy(of url: URL, in directory: URL? = nil) throws -> URL {
        let folder = directory ?? url.deletingLastPathComponent()
        let output = FileActions.uniqueURL(folder.appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-clean.png"))
        try ImageFiles.write(ImageFiles.load(url), to: output)
        return output
    }
}

@MainActor
final class MetadataPanelController {
    static let shared = MetadataPanelController()
    private var panel: NSWindow?

    func show(urls: [URL], outputDirectory: URL? = nil) {
        panel?.close()
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 540),
                            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "File Metadata"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: MetadataInspector(urls: urls, outputDirectory: outputDirectory))
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }
}

struct MetadataInspector: View {
    let urls: [URL]
    let outputDirectory: URL?
    @State private var index = 0
    @State private var message = ""
    private var url: URL { urls[index] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("File Metadata").font(.title2.weight(.semibold))
            if urls.count > 1 {
                Picker("File", selection: $index) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { index, url in Text(url.lastPathComponent).tag(index) }
                }
            } else { Text(url.lastPathComponent).foregroundStyle(.secondary) }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach((try? FileMetadata.entries(for: url)) ?? []) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.id).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(entry.value).textSelection(.enabled)
                        }
                        Divider()
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if ImageFiles.rasterExtensions.contains(url.pathExtension.lowercased()) {
                Button("Save Copy Without Personal Metadata") {
                    do { message = "Saved \(try FileMetadata.sanitizedCopy(of: url, in: outputDirectory).lastPathComponent)" }
                    catch { message = error.localizedDescription }
                }
                Text("Creates a new PNG in \(outputDirectory?.lastPathComponent ?? "the source folder"); the original stays unchanged.").font(.caption).foregroundStyle(.secondary)
                Text("Removes source EXIF/GPS. Basic dimensions and color-profile tags may be regenerated.").font(.caption).foregroundStyle(.secondary)
            }
            if !message.isEmpty { Text(message).font(.caption).textSelection(.enabled) }
        }.padding(22)
    }
}
