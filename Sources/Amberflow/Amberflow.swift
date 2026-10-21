import SwiftUI
import AppKit
import CoreGraphics
import UniformTypeIdentifiers
import ImageIO
import PDFKit
import Vision
import AVFoundation
import Combine
import ServiceManagement
import Quartz

// MARK: - Local model

struct FlowFile: Identifiable, Codable, Hashable {
    let id: UUID
    let path: String
    let name: String
    let ext: String
    let byteCount: Int64
    let addedAt: Date
    var favorite: Bool

    var url: URL { URL(fileURLWithPath: path) }
    var displaySize: String { ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file) }
    var kind: FileKind { FileKind(extensionName: ext) }
}

enum FileKind: String, CaseIterable {
    case image, document, spreadsheet, audio, video, archive, other

    init(extensionName: String) {
        switch extensionName.lowercased() {
        case "jpg", "jpeg", "png", "heic", "tiff", "tif", "webp", "avif", "bmp", "gif", "svg": self = .image
        case "pdf", "doc", "docx", "pages", "txt", "md", "rtf", "rtfd", "html", "epub", "ppt", "pptx": self = .document
        case "xls", "xlsx", "csv", "tsv", "ods": self = .spreadsheet
        case "mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma": self = .audio
        case "mov", "mp4", "m4v", "avi", "mkv", "webm": self = .video
        case "zip", "tar", "gz", "dmg": self = .archive
        default: self = .other
        }
    }

    var color: Color {
        switch self { case .image: return .orange; case .document: return .blue; case .spreadsheet: return .green; case .audio: return .pink; case .video: return .purple; case .archive: return .brown; case .other: return .gray }
    }
    var icon: String {
        switch self { case .image: return "photo.fill"; case .document: return "doc.richtext.fill"; case .spreadsheet: return "tablecells.fill"; case .audio: return "waveform"; case .video: return "film.fill"; case .archive: return "archivebox.fill"; case .other: return "doc.fill" }
    }
}

enum AmberSection: String, CaseIterable, Identifiable {
    case workspace, tools, history, settings, pro
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self { case .workspace: return "square.grid.2x2.fill"; case .tools: return "wand.and.stars"; case .history: return "clock.arrow.circlepath"; case .settings: return "slider.horizontal.3"; case .pro: return "sparkles" }
    }
}

enum AmberTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum RadialMode: String {
    case command, control, shift

    init?(flags: NSEvent.ModifierFlags) {
        let relevant = flags.intersection(.deviceIndependentFlagsMask)
        if relevant.contains(.command) { self = .command }
        else if relevant.contains(.control) { self = .control }
        else if relevant.contains(.shift) { self = .shift }
        else { return nil }
    }

    init?(cgFlags: CGEventFlags) {
        if cgFlags.contains(.maskCommand) { self = .command }
        else if cgFlags.contains(.maskControl) { self = .control }
        else if cgFlags.contains(.maskShift) { self = .shift }
        else { return nil }
    }

    var title: String {
        switch self { case .command: return "TOOLS"; case .control: return "ACTIONS"; case .shift: return "CONVERT" }
    }
}

enum RadialItem: Hashable {
    case compress, metadata, edit, crop, annotate, addBackground, redact
    case airDrop, float, copy, move, copyPath, terminal
    case convert(String)

    static func items(for mode: RadialMode) -> [RadialItem] {
        switch mode {
        case .command: return [.compress, .metadata, .edit, .annotate, .addBackground, .crop, .redact]
        case .control: return [.airDrop, .float, .copy, .move, .copyPath, .terminal]
        case .shift: return [.convert("PNG"), .convert("JPG"), .convert("HEIC"), .convert("TIFF"), .convert("PDF"), .convert("TXT"), .convert("MD"), .convert("ZIP")]
        }
    }

    var label: String {
        switch self {
        case .compress: return "COMPRESS"; case .metadata: return "METADATA"; case .edit: return "EDIT"; case .crop: return "CROP"; case .annotate: return "ANNOTATE"; case .addBackground: return "ADD BG"; case .redact: return "REDACT"
        case .airDrop: return "AIRDROP"; case .float: return "FLOAT"; case .copy: return "COPY"; case .move: return "MOVE"; case .copyPath: return "COPY PATH"; case .terminal: return "TERMINAL"
        case .convert(let format): return format
        }
    }

    var icon: String {
        switch self {
        case .compress: return "arrow.down.right.and.arrow.up.left"; case .metadata: return "tag"; case .edit: return "slider.horizontal.3"; case .crop: return "crop"; case .annotate: return "pencil.and.outline"; case .addBackground: return "photo"; case .redact: return "eye.slash"
        case .airDrop: return "airplayaudio"; case .float: return "pin.fill"; case .copy: return "doc.on.doc"; case .move: return "folder"; case .copyPath: return "doc.text"; case .terminal: return "terminal"
        case .convert: return "arrow.triangle.2.circlepath"
        }
    }

    var tint: Color {
        switch self { case .edit: return .blue; case .redact: return .purple; case .airDrop: return .orange; case .convert: return .orange; default: return .orange }
    }
}

@MainActor
final class AmberStore: ObservableObject {
    @Published var files: [FlowFile] = []
    @Published var selectedIDs: Set<UUID> = []
    @Published var section: AmberSection = .workspace
    @Published var outputFormat = "JPG"
    @Published var preserveMetadata = true
    @Published var theme: AmberTheme = AmberTheme(rawValue: UserDefaults.standard.string(forKey: "amber.theme") ?? "system") ?? .system
    @Published var outputDirectory = UserDefaults.standard.string(forKey: "amber.output") ?? ""
    @Published var soundFeedback = UserDefaults.standard.object(forKey: "amber.sound") as? Bool ?? true
    @Published var launchAtLogin = UserDefaults.standard.bool(forKey: "amber.login")
    @Published var hasFullUnlock = UserDefaults.standard.bool(forKey: "amber.pro")
    @Published var isWorking = false
    @Published var statusMessage = "Drop files to begin"
    @Published var gestureStatus = "Starting Finder gestures…"

    private let stateURL: URL
    private let progressPanel = ConversionProgressPanelController()
    private var sharingService: NSSharingService?
    private var feedbackGeneration = 0

    init() {
        let base = ProcessInfo.processInfo.arguments.contains("--check-action")
            ? FileManager.default.temporaryDirectory.appendingPathComponent("Amberflow Action QA", isDirectory: true)
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Amberflow", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        stateURL = base.appendingPathComponent("state.json")
        load()
    }

    var selectedFiles: [FlowFile] { files.filter { selectedIDs.contains($0.id) } }
    var recentFiles: [FlowFile] { files.sorted { $0.addedAt > $1.addedAt } }
    var outputURL: URL? { outputDirectory.isEmpty ? nil : URL(fileURLWithPath: outputDirectory, isDirectory: true) }

    func add(urls: [URL]) {
        var added = 0
        for url in urls {
            guard FileManager.default.fileExists(atPath: url.path), !files.contains(where: { $0.path == url.path }) else { continue }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            let file = FlowFile(id: UUID(), path: url.path, name: url.lastPathComponent, ext: url.pathExtension, byteCount: Int64(values?.fileSize ?? 0), addedAt: Date(), favorite: false)
            files.insert(file, at: 0); selectedIDs.insert(file.id); added += 1
        }
        if added > 0 { statusMessage = "\(added) file\(added == 1 ? "" : "s") ready"; save() }
    }

    func focus(urls: [URL]) {
        add(urls: urls)
        let paths = Set(urls.map(\.path))
        selectedIDs = Set(files.filter { paths.contains($0.path) }.map(\.id))
        if !selectedIDs.isEmpty { statusMessage = selectedIDs.count == 1 ? "Finder file selected" : "\(selectedIDs.count) Finder files selected" }
        save()
    }

    func toggleSelection(_ id: UUID) { if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) } }
    func remove(_ file: FlowFile) { files.removeAll { $0.id == file.id }; selectedIDs.remove(file.id); save() }
    func toggleFavorite(_ file: FlowFile) { guard let i = files.firstIndex(of: file) else { return }; files[i].favorite.toggle(); save() }
    func clearHistory() { files.removeAll(); selectedIDs.removeAll(); save(); statusMessage = "Workspace cleared" }
    func unlockLocally() { hasFullUnlock = true; UserDefaults.standard.set(true, forKey: "amber.pro") }

    func performRadialAction(_ action: RadialItem, urls: [URL]) {
        do { try FileActions.validate(urls) }
        catch { reportError(error); return }
        if let reason = action.unavailableReason(for: urls) {
            reportError(FileActionError.unsupported(reason))
            return
        }
        focus(urls: urls)
        switch action {
        case .compress:
            if urls.allSatisfy({ FileKind(extensionName: $0.pathExtension) == .image }) {
                showImageTool(.compress, url: urls[0])
            } else { outputFormat = "ZIP"; convertSelected() }
        case .metadata:
            MetadataPanelController.shared.show(urls: urls, outputDirectory: outputURL)
            statusMessage = "File metadata opened"
        case .edit, .crop, .annotate, .addBackground, .redact:
            if FileKind(extensionName: urls[0].pathExtension) == .image {
                showImageTool(ImageTool(action), url: urls[0])
            } else if urls[0].pathExtension.lowercased() == "pdf" {
                Task {
                    do { try await NativeFileActions.openInPreview(urls); statusMessage = "Opened in Preview — use its Tools menu" }
                    catch { reportError(error) }
                }
            } else if !NSWorkspace.shared.open(urls[0]) {
                reportError(FileActionError.unsupported("No application could open this file."))
            }
        case .airDrop:
            guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
                reportError(FileActionError.unsupported("AirDrop is not available for these files on this Mac.")); return
            }
            sharingService = service
            service.perform(withItems: urls)
            statusMessage = "AirDrop opened — choose a recipient"
        case .float:
            FloatingFilePanelController.shared.show(urls: urls)
            statusMessage = "Floating preview opened"
        case .copy:
            do { try NativeFileActions.copyFiles(urls); statusMessage = "Copied \(urls.count == 1 ? "file" : "files")" }
            catch { reportError(error) }
        case .move:
            move(urls: urls)
        case .copyPath:
            do { try NativeFileActions.copyPaths(urls); statusMessage = "Copied path\(urls.count == 1 ? "" : "s")" }
            catch { reportError(error) }
        case .terminal:
            if let url = urls.first { openTerminal(FlowFile(id: UUID(), path: url.path, name: url.lastPathComponent, ext: url.pathExtension, byteCount: 0, addedAt: Date(), favorite: false)) }
        case .convert(let format):
            outputFormat = format
            convertSelected()
        }
    }

    private func move(urls: [URL]) {
        let panel = NSOpenPanel()
        panel.title = "Move selected files to…"
        panel.prompt = "Move"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            do {
                let moved = try FileActions.move(urls, to: destination)
                self?.files.removeAll { urls.contains($0.url) }
                self?.focus(urls: moved)
                let changed = zip(urls, moved).filter { $0 != $1 }.count
                self?.statusMessage = changed == 0 ? "Files are already in that folder" : "Moved \(changed) file\(changed == 1 ? "" : "s")"
            } catch { self?.reportError(error) }
        }
    }

    private func showImageTool(_ tool: ImageTool, url: URL) {
        do {
            try ImageToolPanelController.shared.show(tool: tool, url: url, outputDirectory: outputURL) { [weak self] result in
                switch result {
                case .success(let output): self?.statusMessage = "Saved \(output.lastPathComponent)"
                case .failure(let error): self?.reportError(error)
                }
            }
        } catch { reportError(error) }
    }

    func reportError(_ error: Error) {
        feedbackGeneration += 1
        let generation = feedbackGeneration
        statusMessage = error.localizedDescription
        progressPanel.show(title: "Could not complete action", detail: statusMessage, progress: 0)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            if !isWorking, feedbackGeneration == generation { progressPanel.hide() }
        }
    }

    func setTheme(_ value: AmberTheme) {
        theme = value
        UserDefaults.standard.set(value.rawValue, forKey: "amber.theme")
        applyAppearance()
    }

    func applyAppearance() {
        switch theme {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
    func setOutputDirectory(_ url: URL?) { outputDirectory = url?.path ?? ""; UserDefaults.standard.set(outputDirectory, forKey: "amber.output") }
    func setSound(_ value: Bool) { soundFeedback = value; UserDefaults.standard.set(value, forKey: "amber.sound") }
    func setLogin(_ value: Bool) {
        launchAtLogin = value
        UserDefaults.standard.set(value, forKey: "amber.login")
        if #available(macOS 13.0, *) {
            do {
                if value { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                statusMessage = value ? "Could not enable launch at login" : "Could not disable launch at login"
            }
        }
    }

    func convertSelected() {
        let targets = selectedFiles
        guard !targets.isEmpty else { statusMessage = "Select at least one file"; return }
        guard !isWorking else { statusMessage = "A conversion is already in progress"; return }
        let format = outputFormat
        let preserve = preserveMetadata
        let chosenFolder = outputURL
        feedbackGeneration += 1
        let generation = feedbackGeneration
        isWorking = true; statusMessage = "Preparing \(targets.count) file\(targets.count == 1 ? "" : "s")…"
        progressPanel.show(title: "Converting to \(format)", detail: targets.first?.name ?? "Selected files", progress: 0)
        Task { @MainActor in
            var completed = 0; var failures: [String] = []
            for file in targets {
                progressPanel.show(title: "Converting to \(format)", detail: file.name, progress: Double(completed) / Double(targets.count))
                let input = file.url
                let folder = chosenFolder ?? input.deletingLastPathComponent()
                do {
                    _ = try await Task.detached(priority: .userInitiated) {
                        try ConversionService.convert(input, to: format, preserveMetadata: preserve, in: folder)
                    }.value
                    completed += 1
                }
                catch { failures.append("\(file.name): \(error.localizedDescription)") }
            }
            isWorking = false
            statusMessage = failures.isEmpty ? "Finished \(completed) conversion\(completed == 1 ? "" : "s")" : "Saved \(completed); \(failures.first ?? "an error occurred")"
            progressPanel.show(title: failures.isEmpty ? "Saved \(format)" : "Conversion needs attention",
                               detail: failures.first ?? "\(completed) of \(targets.count) saved", progress: failures.isEmpty ? 1 : 0)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(failures.isEmpty ? 1.5 : 5))
                if feedbackGeneration == generation, !isWorking { progressPanel.hide() }
            }
            if soundFeedback, failures.isEmpty { NSSound(named: "Glass")?.play() }
        }
    }

    func runOCR() {
        guard let file = selectedFiles.first else { statusMessage = "Select an image first"; return }
        do {
            let text = try ConversionService.extractText(file.url)
            let destination = FileActions.uniqueURL((outputURL ?? file.url.deletingLastPathComponent()).appendingPathComponent(file.url.deletingPathExtension().lastPathComponent + " OCR.txt"))
            try text.write(to: destination, atomically: true, encoding: .utf8)
            statusMessage = "OCR saved to \(destination.lastPathComponent)"
        } catch { reportError(error) }
    }

    func runQR() {
        guard let file = selectedFiles.first else { statusMessage = "Select an image first"; return }
        do {
            let codes = try VisionService.detectQR(at: file.url)
            guard !codes.isEmpty else { statusMessage = "No QR codes found"; return }
            let destination = FileActions.uniqueURL((outputURL ?? file.url.deletingLastPathComponent()).appendingPathComponent(file.url.deletingPathExtension().lastPathComponent + " QR.txt"))
            try codes.joined(separator: "\n").write(to: destination, atomically: true, encoding: .utf8)
            statusMessage = "QR results saved to \(destination.lastPathComponent)"
        } catch { reportError(error) }
    }

    func mergePDFs() {
        let urls = selectedFiles.map(\.url).filter { $0.pathExtension.lowercased() == "pdf" }
        guard urls.count >= 2 else { statusMessage = "Select two or more PDFs"; return }
        let output = FileActions.uniqueURL((outputURL ?? urls[0].deletingLastPathComponent()).appendingPathComponent("Amberflow merged.pdf"))
        let merged = PDFDocument()
        for url in urls { if let pdf = PDFDocument(url: url) { for i in 0..<pdf.pageCount { if let page = pdf.page(at: i) { merged.insert(page, at: merged.pageCount) } } } }
        guard merged.write(to: output) else { statusMessage = "Could not write merged PDF"; return }
        statusMessage = "Merged PDF saved"
    }

    func reveal(_ file: FlowFile) { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
    func openTerminal(_ file: FlowFile) {
        Task {
            do {
                let directory = try await NativeFileActions.openTerminal(for: file.url)
                statusMessage = "Terminal opened in \(directory.lastPathComponent)"
            } catch { reportError(error) }
        }
    }

    private func load() { guard let data = try? Data(contentsOf: stateURL), let decoded = try? JSONDecoder().decode([FlowFile].self, from: data) else { return }; files = decoded.filter { FileManager.default.fileExists(atPath: $0.path) } }
    func save() { guard let data = try? JSONEncoder().encode(files) else { return }; try? data.write(to: stateURL, options: .atomic) }
}

enum ConversionError: LocalizedError {
    case unsupported(String), failed(String)
    var errorDescription: String? { switch self { case .unsupported(let value): return "Amberflow cannot convert \(value) offline yet."; case .failed(let value): return value } }
}

enum VisionService {
    static func recognizeText(at url: URL) throws -> String {
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(url: url, options: [:]); try handler.perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
    static func detectQR(at url: URL) throws -> [String] {
        let request = VNDetectBarcodesRequest(); request.symbologies = [.qr, .aztec, .dataMatrix, .pdf417]
        let handler = VNImageRequestHandler(url: url, options: [:]); try handler.perform([request])
        return (request.results ?? []).compactMap(\.payloadStringValue)
    }
}

// MARK: - App shell

@main
struct AmberflowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Amberflow", systemImage: "circle.lefthalf.filled") {
            MenuBarView(store: delegate.store)
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = AmberStore()
    private var finderShortcutController: FinderShortcutController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.applyAppearance()
        if finderShortcutController == nil { finderShortcutController = FinderShortcutController(store: store) }
        // Explicit local QA entry point; normal launch remains menu-bar-only.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--check-action"), arguments.count > index + 2 {
            let actions: [String: RadialItem] = ["terminal": .terminal, "metadata": .metadata, "float": .float,
                                               "edit": .edit, "crop": .crop, "annotate": .annotate,
                                               "background": .addBackground, "redact": .redact, "compress": .compress]
            if let action = actions[arguments[index + 1]] {
                let url = URL(fileURLWithPath: arguments[index + 2])
                DispatchQueue.main.async { self.store.performRadialAction(action, urls: [url]) }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { false }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@MainActor
final class FloatingFilePanelController {
    static let shared = FloatingFilePanelController()
    private var panel: NSPanel?

    func show(urls: [URL]) {
        let panel = self.panel ?? NSPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 440), styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.title = urls.count == 1 ? (urls.first?.lastPathComponent ?? "Preview") : "Amberflow Preview"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: FloatingFileView(urls: urls))
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }
}

@MainActor
final class ConversionProgressPanelController {
    private let panel: NSPanel

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 126), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    func show(title: String, detail: String, progress: Double) {
        panel.contentView = NSHostingView(rootView: ConversionProgressView(title: title, detail: detail, progress: progress))
        let screen = NSScreen.main ?? NSScreen.screens.first
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 360, height: 126)
        panel.setFrame(NSRect(x: bounds.maxX - size.width - 24, y: bounds.minY + 24, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }
}

struct ConversionProgressView: View {
    let title: String
    let detail: String
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.orange)
                Text(title).font(.system(size: 17, weight: .semibold, design: .rounded))
                Spacer()
            }
            Text(detail).font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.secondary).lineLimit(1)
            ProgressView(value: progress).tint(.orange)
        }
        .padding(18)
        .frame(width: 360, height: 126, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.65), lineWidth: 1))
    }
}

struct FloatingFileView: View {
    let urls: [URL]
    @State private var index = 0

    var body: some View {
        VStack(spacing: 10) {
            if urls.count > 1 {
                Picker("File", selection: $index) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { index, url in Text(url.lastPathComponent).tag(index) }
                }.padding(.horizontal, 12)
            }
            if !urls.isEmpty { QuickLookFileView(url: urls[index]).frame(minWidth: 320, minHeight: 250) }
        }.padding(10)
    }
}

struct QuickLookFileView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView {
        let preview = QLPreviewView(frame: .zero, style: .normal)!
        preview.autostarts = false
        preview.previewItem = url as NSURL
        return preview
    }
    func updateNSView(_ preview: QLPreviewView, context: Context) { preview.previewItem = url as NSURL }
    static func dismantleNSView(_ preview: QLPreviewView, coordinator: ()) { preview.close() }
}

extension Notification.Name { static let amberAddFiles = Notification.Name("Amberflow.addFiles") }

@MainActor
final class FinderShortcutController {
    private let store: AmberStore
    private let panel = RadialPanelController()
    private let dragPasteboard = NSPasteboard(name: .drag)
    private var gesture: FileDragGesture
    private var timer: Timer?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastReadChangeCount = -1
    private var draggedURLs: [URL] = []
    private var releaseGeneration = 0
    private let diagnostics = ProcessInfo.processInfo.arguments.contains("--gesture-diagnostics")
    private var lastDiagnostic = ""
    private var dragActivity: NSObjectProtocol?

    init(store: AmberStore) {
        self.store = store
        gesture = FileDragGesture(pasteboardChangeCount: dragPasteboard.changeCount)
        // Common modes continue firing while a native drag tracking loop is running.
        timer = GesturePolling.start { [weak self] in self?.poll() }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.observe(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.observe(event) }
            return event
        }
        store.gestureStatus = "Ready · drag a file, then hold ⌘, ⌃, or ⇧"
    }

    private func observe(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 {
            gesture.cancel()
            panel.hide()
            store.gestureStatus = "Drag cancelled"
        } else { poll() }
    }

    private func poll() {
        let mouseIsDown = NSEvent.pressedMouseButtons & 1 != 0
        if mouseIsDown, dragActivity == nil {
            dragActivity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Respond promptly while a file is being dragged")
        } else if !mouseIsDown, let activity = dragActivity {
            ProcessInfo.processInfo.endActivity(activity)
            dragActivity = nil
        }
        let changeCount = dragPasteboard.changeCount
        if mouseIsDown, gesture.hasNewPasteboard(changeCount), changeCount != lastReadChangeCount || draggedURLs.isEmpty {
            draggedURLs = DraggedFiles.read(from: dragPasteboard)
            lastReadChangeCount = changeCount
        }
        let effect = gesture.update(.init(mouseIsDown: mouseIsDown, point: NSEvent.mouseLocation,
                                         mode: RadialMode(flags: NSEvent.modifierFlags),
                                         pasteboardChangeCount: changeCount, urls: draggedURLs))
        if diagnostics {
            let signature = "held=\(mouseIsDown) dragBoard=\(changeCount) files=\(draggedURLs.count) modifier=\(RadialMode(flags: NSEvent.modifierFlags)?.rawValue ?? "none") panel=\(panel.isVisible)"
            if signature != lastDiagnostic {
                print("AMBERFLOW_GESTURE \(signature)")
                fflush(stdout)
                lastDiagnostic = signature
            }
        }
        switch effect {
        case .none: break
        case let .show(mode, urls, anchor):
            releaseGeneration += 1
            store.gestureStatus = "\(mode.title.capitalized) · release on an option"
            panel.show(mode: mode, urls: urls, at: anchor) { [weak self] action, droppedURLs in
                guard let self else { return }
                self.gesture.cancel()
                self.panel.hide()
                self.store.performRadialAction(action, urls: droppedURLs)
                self.store.gestureStatus = "Ready · drag a file, then hold ⌘, ⌃, or ⇧"
            }
        case .update(let point): panel.updateDrag(at: point)
        case .hide:
            // Let AppKit finish performDragOperation before dismissing the destination.
            releaseGeneration += 1
            let generation = releaseGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                guard let self, self.releaseGeneration == generation else { return }
                self.panel.hide()
                self.store.gestureStatus = "Ready · drag a file, then hold ⌘, ⌃, or ⇧"
            }
        }
    }
}

@MainActor
final class RadialPanelModel: ObservableObject {
    @Published var hovered: RadialItem?
    @Published var unavailableReason: String?
}

@MainActor
final class RadialPanelController {
    private let panel: NSPanel
    private let model = RadialPanelModel()
    private var mode: RadialMode = .command
    private var urls: [URL] = []
    private var actionHandler: ((RadialItem, [URL]) -> Void)?
    var isVisible: Bool { panel.isVisible }

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: RadialGeometry.size, height: RadialGeometry.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Amberflow Drag Actions"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .none
    }

    func show(mode: RadialMode, urls: [URL], at cursor: NSPoint, onAction: @escaping (RadialItem, [URL]) -> Void) {
        self.mode = mode
        self.urls = urls
        model.hovered = nil
        model.unavailableReason = nil
        actionHandler = onAction
        let destination = RadialDropView(rootView: RadialWheelView(mode: mode, urls: urls, model: model))
        destination.actionAtPoint = { point in RadialGeometry.item(at: point, mode: mode) }
        destination.onHover = { [weak self] item in self?.setHover(item) }
        destination.canDrop = { $0.unavailableReason(for: urls) == nil }
        destination.onDrop = { [weak self] item, droppedURLs in
            guard let self, let handler = self.actionHandler else { return false }
            self.hide()
            // Complete AppKit's drop first; dialogs and conversions start on the next turn.
            DispatchQueue.main.async { handler(item, droppedURLs) }
            return true
        }
        panel.contentView = destination
        let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) }) ?? NSScreen.main
        let size = NSSize(width: RadialGeometry.size, height: RadialGeometry.size)
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = min(max(cursor.x - size.width / 2, bounds.minX + 12), bounds.maxX - size.width - 12)
        let y = min(max(cursor.y - size.height / 2, bounds.minY + 12), bounds.maxY - size.height - 12)
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
        panel.orderFrontRegardless()
    }

    func updateDrag(at screenPoint: NSPoint) {
        setHover(item(at: screenPoint))
    }

    private func setHover(_ item: RadialItem?) {
        guard model.hovered != item else { return }
        model.hovered = item
        model.unavailableReason = item?.unavailableReason(for: urls)
    }

    func hide() {
        model.hovered = nil
        actionHandler = nil
        panel.orderOut(nil)
    }

    private func item(at screenPoint: NSPoint) -> RadialItem? {
        let localX = screenPoint.x - panel.frame.minX
        let localY = panel.frame.height - (screenPoint.y - panel.frame.minY)
        return RadialGeometry.item(at: NSPoint(x: localX, y: localY), mode: mode)
    }
}

@MainActor
final class RadialDropView: NSView {
    var actionAtPoint: ((NSPoint) -> RadialItem?)?
    var onHover: ((RadialItem?) -> Void)?
    var onDrop: ((RadialItem, [URL]) -> Bool)?
    var canDrop: ((RadialItem) -> Bool)?
    override var isFlipped: Bool { true }

    init(rootView: RadialWheelView) {
        super.init(frame: NSRect(x: 0, y: 0, width: RadialGeometry.size, height: RadialGeometry.size))
        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
        registerForDraggedTypes([.fileURL, DraggedFiles.legacyFileNames])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    override func wantsPeriodicDraggingUpdates() -> Bool { true }

    private func action(for sender: any NSDraggingInfo) -> RadialItem? {
        actionAtPoint?(convert(sender.draggingLocation, from: nil))
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let item = action(for: sender)
        onHover?(item)
        // Keep receiving native drag updates while the cursor crosses the center/gaps.
        // prepareForDragOperation rejects a release unless it lands on a real wedge.
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) { onHover?(nil) }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let action = action(for: sender) else { return false }
        return canDrop?(action) ?? true
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let item = action(for: sender), canDrop?(item) ?? true else { return false }
        let urls = DraggedFiles.read(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        sender.animatesToDestination = true
        return onDrop?(item, urls) ?? false
    }
}

struct RadialWheelView: View {
    let mode: RadialMode
    let urls: [URL]
    @ObservedObject var model: RadialPanelModel
    private let size = RadialGeometry.size
    private let center = RadialGeometry.center
    private let outerRadius = RadialGeometry.outerRadius
    private let innerRadius = RadialGeometry.innerRadius
    private var items: [RadialItem] { RadialItem.items(for: mode) }

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial).frame(width: 292, height: 292)
                .overlay(Circle().stroke(Color.white.opacity(0.68), lineWidth: 2))
            ForEach(Array(items.enumerated()), id: \.element) { index, action in
                let angleStep = 360.0 / Double(items.count)
                let centerAngle = -90.0 + Double(index) * angleStep
                let segmentHalfWidth = max(13.0, angleStep / 2.0 - 3.5)
                RadialSegment(start: centerAngle - segmentHalfWidth, end: centerAngle + segmentHalfWidth, innerRadius: innerRadius, outerRadius: outerRadius)
                    .fill(model.hovered == action ? action.tint.opacity(0.34) : Color.white.opacity(0.80))
                    .overlay(RadialSegment(start: centerAngle - segmentHalfWidth, end: centerAngle + segmentHalfWidth, innerRadius: innerRadius, outerRadius: outerRadius).stroke(Color.black.opacity(0.10), lineWidth: 1))
                VStack(spacing: 6) {
                        Image(systemName: action.icon).font(.system(size: 17, weight: .medium))
                        Text(action.label).font(.system(size: 9, weight: .bold, design: .rounded)).tracking(0.15)
                }
                .foregroundStyle(.black.opacity(0.88)).frame(width: 89, height: 61)
                .opacity(action.unavailableReason(for: urls) == nil ? 1 : 0.3)
                .position(polarPosition(angle: centerAngle, radius: 101))
            }
            VStack(spacing: 4) {
                Text(model.hovered?.label ?? sizeLabel).font(.system(size: model.hovered == nil ? 16 : 12, weight: .semibold, design: .rounded)).tracking(model.hovered == nil ? 0 : 0.4)
                Text(model.hovered == nil ? mode.title : (model.unavailableReason == nil ? hoveredHint : "NOT AVAILABLE")).font(.system(size: 8, weight: .bold, design: .rounded)).tracking(0.8).foregroundStyle(.secondary)
            }
            .frame(width: 105, height: 46)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.8), lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
        .frame(width: size, height: size)
        .background(Color.clear)
        .allowsHitTesting(false)
    }

    private var sizeLabel: String {
        if urls.count > 1 { return "\(urls.count) files" }
        guard let url = urls.first, let values = try? url.resourceValues(forKeys: [.fileSizeKey]), let bytes = values.fileSize else { return "Ready" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private var hoveredHint: String {
        if urls.first?.pathExtension.lowercased() == "pdf", let item = model.hovered {
            if case .convert(let format) = item, ConversionService.imageTypes[format] != nil { return "FIRST PAGE" }
            if [.edit, .crop, .annotate].contains(item) { return "PREVIEW" }
        }
        return sizeLabel
    }

    private func polarPosition(angle: Double, radius: CGFloat) -> CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(x: center + CGFloat(cos(radians)) * radius, y: center + CGFloat(sin(radians)) * radius)
    }
}

struct RadialSegment: Shape {
    let start: Double
    let end: Double
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerStart = point(center: center, radius: outerRadius, angle: start)
        let innerEnd = point(center: center, radius: innerRadius, angle: end)
        let innerStart = point(center: center, radius: innerRadius, angle: start)
        var path = Path()
        path.move(to: innerStart)
        path.addLine(to: outerStart)
        path.addArc(center: center, radius: outerRadius, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        path.addLine(to: innerEnd)
        path.addArc(center: center, radius: innerRadius, startAngle: .degrees(end), endAngle: .degrees(start), clockwise: true)
        path.closeSubpath()
        return path
    }

    private func point(center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(x: center.x + CGFloat(cos(radians)) * radius, y: center.y + CGFloat(sin(radians)) * radius)
    }
}

// MARK: - Shared components

struct AmberBackground: View {
    var body: some View { ZStack { Color(nsColor: .windowBackgroundColor); LinearGradient(colors: [Color.orange.opacity(0.10), Color.clear, Color.pink.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea() } }
}

struct AmberCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View { content.padding(18).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.10))) }
}

struct BrandMark: View {
    var small = false
    var body: some View { ZStack { RoundedRectangle(cornerRadius: small ? 8 : 13).fill(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)); Circle().stroke(.white.opacity(0.95), lineWidth: small ? 2 : 3).padding(small ? 6 : 9); Circle().fill(.white.opacity(0.95)).frame(width: small ? 5 : 8, height: small ? 5 : 8) }.frame(width: small ? 28 : 46, height: small ? 28 : 46).shadow(color: .orange.opacity(0.35), radius: 8) }
}

struct SidebarView: View {
    @ObservedObject var store: AmberStore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 11) { BrandMark(small: true); VStack(alignment: .leading, spacing: 1) { Text("Amberflow").font(.headline); Text("Quiet file utility").font(.caption).foregroundStyle(.secondary) } }
            VStack(alignment: .leading, spacing: 4) { Text("WORKSPACE").font(.caption2.weight(.bold)).foregroundStyle(.secondary).padding(.horizontal, 10); ForEach([AmberSection.workspace, .tools, .history], id: \.self) { section in SidebarButton(section: section, store: store) } }
            VStack(alignment: .leading, spacing: 4) { Text("PERSONALIZE").font(.caption2.weight(.bold)).foregroundStyle(.secondary).padding(.horizontal, 10); ForEach([AmberSection.pro, .settings], id: \.self) { section in SidebarButton(section: section, store: store) } }
            Spacer()
            if !store.hasFullUnlock { HStack { Image(systemName: "sparkles").foregroundStyle(.orange); VStack(alignment: .leading) { Text("Amberflow Pro").font(.subheadline.weight(.semibold)); Text("All tools, always local").font(.caption).foregroundStyle(.secondary) }; Spacer() }.padding(10).background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 13)) }
        }.padding(18).frame(minWidth: 220, idealWidth: 240).background(.thinMaterial)
    }
}

struct SidebarButton: View {
    let section: AmberSection; @ObservedObject var store: AmberStore
    var body: some View { Button { store.section = section } label: { Label(section.title, systemImage: section.icon).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8).padding(.horizontal, 10).contentShape(Rectangle()).background(store.section == section ? Color.orange.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain).foregroundStyle(store.section == section ? .primary : .secondary) }
}

struct RootView: View {
    @ObservedObject var store: AmberStore
    var body: some View { NavigationSplitView { SidebarView(store: store) } detail: { DetailView(store: store) }.background(AmberBackground()).onReceive(NotificationCenter.default.publisher(for: .amberAddFiles)) { _ in openFiles() } }
    private func openFiles() { let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = true; panel.begin { if $0 == .OK { store.add(urls: panel.urls) } } }
}

struct DetailView: View {
    @ObservedObject var store: AmberStore
    var body: some View { switch store.section { case .workspace: WorkspaceView(store: store); case .tools: ToolsView(store: store); case .history: HistoryView(store: store); case .settings: SettingsView(store: store); case .pro: ProView(store: store) } }
}

struct MenuBarView: View {
    @ObservedObject var store: AmberStore
    private let formats = ["PNG", "JPG", "HEIC", "TIFF", "PDF", "TXT", "MD", "ZIP"]

    var body: some View {
        Text("Amberflow \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
        Text(store.gestureStatus)
        Text(store.statusMessage)
        Divider()
        Menu {
            Text("Drag a file in Finder or on the Desktop")
            Text("Keep holding the mouse, then press:")
            Text("⌘  Tools     ⌃  Actions     ⇧  Convert")
            Text("Release on an option to use it")
            Text("Release outside the wheel to cancel")
        } label: { Label("How to Use", systemImage: "cursorarrow.motionlines") }
        Menu {
            if store.recentFiles.isEmpty { Text("Files you use will appear here") }
            ForEach(Array(store.recentFiles.prefix(10))) { file in
                Menu(file.name) {
                    Button("Reveal in Finder") { store.reveal(file) }
                    Button("Open File") { NSWorkspace.shared.open(file.url) }
                    Menu("Convert to…") {
                        ForEach(formats, id: \.self) { format in
                            Button(format + (file.ext.lowercased() == "pdf" && ConversionService.imageTypes[format] != nil ? " (first page)" : "")) { store.performRadialAction(.convert(format), urls: [file.url]) }
                                .disabled(RadialItem.convert(format).unavailableReason(for: [file.url]) != nil)
                        }
                    }
                    Button("Copy Path") { store.performRadialAction(.copyPath, urls: [file.url]) }
                    Button("Float Preview") { store.performRadialAction(.float, urls: [file.url]) }
                    if file.kind == .image {
                        Divider()
                        Button("Extract Text (OCR)") { store.focus(urls: [file.url]); store.runOCR() }
                        Button("Read QR Codes") { store.focus(urls: [file.url]); store.runQR() }
                    }
                }
            }
        } label: { Label("Recent Files", systemImage: "clock") }
        Divider()
        Menu {
            Picker("Appearance", selection: Binding(get: { store.theme }, set: { store.setTheme($0) })) {
                ForEach(AmberTheme.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Preserve Metadata", isOn: $store.preserveMetadata)
            Toggle("Sound Feedback", isOn: Binding(get: { store.soundFeedback }, set: { store.setSound($0) }))
            Toggle("Launch at Login", isOn: Binding(get: { store.launchAtLogin }, set: { store.setLogin($0) }))
            Divider()
            Text("Output: \(store.outputDirectory.isEmpty ? "Beside original" : URL(fileURLWithPath: store.outputDirectory).lastPathComponent)")
            Button("Choose Output Folder…") { chooseOutputFolder() }
            Button("Save Beside Original") { store.setOutputDirectory(nil) }
                .disabled(store.outputDirectory.isEmpty)
        } label: { Label("Preferences", systemImage: "gearshape") }
        Divider()
        Button("Quit Amberflow") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { if $0 == .OK { store.setOutputDirectory(panel.url) } }
    }
}

// MARK: - Workspace

struct WorkspaceView: View {
    @ObservedObject var store: AmberStore
    @State private var isTargeted = false
    @State private var showingOutput = false
    @State private var showingPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) { VStack(alignment: .leading, spacing: 5) { Text("Your workspace").font(.largeTitle.weight(.bold)); Text("Drop files in. Amberflow keeps the flow moving.").foregroundStyle(.secondary) }; Spacer(); Button { openFiles() } label: { Label("Add files", systemImage: "plus") }.buttonStyle(.borderedProminent).tint(.orange) }
            DropZone(store: store, isTargeted: $isTargeted)
            HStack(alignment: .center) { Text(store.files.isEmpty ? "Ready when you are" : "Queue · \(store.files.count) file\(store.files.count == 1 ? "" : "s")").font(.title3.weight(.semibold)); Spacer(); if !store.files.isEmpty { Button("Clear") { store.clearHistory() }.buttonStyle(.borderless).foregroundStyle(.secondary) } }
            if store.files.isEmpty { EmptyState() } else { ScrollView { LazyVStack(spacing: 10) { ForEach(store.recentFiles) { file in FileRow(file: file, store: store) } } } }
            HStack(spacing: 12) { OutputPicker(store: store); Spacer(); Text(store.statusMessage).font(.caption).foregroundStyle(.secondary).lineLimit(1); Button { store.convertSelected() } label: { Label(store.isWorking ? "Working…" : "Convert selection", systemImage: store.isWorking ? "hourglass" : "arrow.right.circle.fill") }.buttonStyle(.borderedProminent).tint(.orange).disabled(store.isWorking || store.selectedFiles.isEmpty) }
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func openFiles() { let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = true; panel.begin { if $0 == .OK { store.add(urls: panel.urls) } } }
}

struct DropZone: View {
    @ObservedObject var store: AmberStore; @Binding var isTargeted: Bool
    var body: some View { AmberCard { VStack(spacing: 12) { ZStack { Circle().fill(Color.orange.opacity(isTargeted ? 0.23 : 0.12)).frame(width: 68, height: 68); Image(systemName: isTargeted ? "arrow.down.circle.fill" : "tray.and.arrow.down.fill").font(.system(size: 30, weight: .semibold)).foregroundStyle(.orange) }; Text(isTargeted ? "Release to add" : "Drop files here").font(.title2.weight(.semibold)); Text("Images, documents, audio, video, and folders").foregroundStyle(.secondary); Text("Files stay on this Mac").font(.caption).foregroundStyle(.tertiary) }.frame(maxWidth: .infinity).padding(.vertical, 20) }.overlay(RoundedRectangle(cornerRadius: 20).stroke(isTargeted ? Color.orange : Color.clear, lineWidth: 2)).onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in for provider in providers { provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in let url: URL?; if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) } else { url = item as? URL }; if let url { DispatchQueue.main.async { store.add(urls: [url]) } } } }; return true } }
}

struct EmptyState: View { var body: some View { VStack(spacing: 10) { Image(systemName: "sparkles.rectangle.stack").font(.system(size: 42)).foregroundStyle(.orange.opacity(0.75)); Text("Nothing in the queue").font(.title3.weight(.semibold)); Text("Add a file or drop a folder to start a local workflow.").foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(40) } }

struct OutputPicker: View {
    @ObservedObject var store: AmberStore
    private let formats = ["JPG", "PNG", "HEIC", "TIFF", "PDF", "TXT", "MD", "ZIP"]
    var body: some View { HStack(spacing: 8) { Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.orange); Picker("Output", selection: $store.outputFormat) { ForEach(formats, id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 120); Toggle("Metadata", isOn: $store.preserveMetadata).toggleStyle(.checkbox).font(.caption) } }
}

struct FileRow: View {
    let file: FlowFile; @ObservedObject var store: AmberStore
    var body: some View { HStack(spacing: 12) { Button { store.toggleSelection(file.id) } label: { Image(systemName: store.selectedIDs.contains(file.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(store.selectedIDs.contains(file.id) ? .orange : .secondary).font(.title3) }.buttonStyle(.plain); ZStack { RoundedRectangle(cornerRadius: 10).fill(file.kind.color.opacity(0.15)); Image(systemName: file.kind.icon).foregroundStyle(file.kind.color) }.frame(width: 38, height: 38); VStack(alignment: .leading, spacing: 3) { Text(file.name).lineLimit(1).font(.subheadline.weight(.semibold)); Text("\(file.ext.uppercased()) · \(file.displaySize)").font(.caption).foregroundStyle(.secondary) }; Spacer(); if file.favorite { Image(systemName: "star.fill").foregroundStyle(.orange).font(.caption) }; Menu { Button(file.favorite ? "Unfavorite" : "Favorite") { store.toggleFavorite(file) }; Button("Reveal in Finder") { store.reveal(file) }; Button("Open Terminal Here") { store.openTerminal(file) }; Divider(); Button("Remove", role: .destructive) { store.remove(file) } } label: { Image(systemName: "ellipsis.circle").font(.title3) }.menuStyle(.borderlessButton) }.padding(.horizontal, 14).padding(.vertical, 9).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14)).contentShape(Rectangle()).onTapGesture { store.toggleSelection(file.id) } }
}

// MARK: - Tools, history, preferences, pro

struct ToolsView: View {
    @ObservedObject var store: AmberStore
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 20) { PageHeader(title: "Toolbox", subtitle: "Focused actions for the files you already selected.")
        AmberCard { VStack(alignment: .leading, spacing: 14) { Label("Image lab", systemImage: "photo.on.rectangle.angled").font(.title3.weight(.semibold)); Text("Compress, preserve metadata, or turn an image into a shareable PDF.").foregroundStyle(.secondary); HStack { ToolButton(title: "Compress to JPG", icon: "arrow.down.right.and.arrow.up.left") { store.outputFormat = "JPG"; store.convertSelected() }; ToolButton(title: "Make PDF", icon: "doc.richtext") { store.outputFormat = "PDF"; store.convertSelected() }; ToolButton(title: "OCR text", icon: "text.viewfinder") { store.runOCR() }; ToolButton(title: "Read QR", icon: "qrcode.viewfinder") { store.runQR() } } } }
        AmberCard { VStack(alignment: .leading, spacing: 14) { Label("PDF studio", systemImage: "doc.text.image").font(.title3.weight(.semibold)); Text("Combine selected PDFs into one document without uploading them.").foregroundStyle(.secondary); HStack { ToolButton(title: "Merge PDFs", icon: "square.stack.3d.up") { store.mergePDFs() }; ToolButton(title: "Reveal output", icon: "folder") { if let url = store.outputURL { NSWorkspace.shared.open(url) } } } } }
        AmberCard { VStack(alignment: .leading, spacing: 14) { Label("Format compass", systemImage: "circle.grid.cross").font(.title3.weight(.semibold)); Text("Amberflow uses native macOS codecs and keeps a transparent boundary around offline formats.").foregroundStyle(.secondary); FormatMatrix() } }
    }.padding(28).frame(maxWidth: .infinity, alignment: .topLeading) } }
}

struct ToolButton: View { let title: String; let icon: String; let action: () -> Void; var body: some View { Button(action: action) { Label(title, systemImage: icon).frame(minWidth: 128) }.buttonStyle(.bordered).tint(.orange) } }

struct FormatMatrix: View {
    let rows: [(String, String, String)] = [("Images", "JPG · PNG · HEIC · TIFF", "Native"), ("Documents", "PDF · TXT · MD", "Native"), ("Archives", "ZIP", "Native"), ("Office / media", "DOCX · XLSX · MOV · MP3", "Open in source app")]
    var body: some View { VStack(spacing: 0) { ForEach(rows, id: \.0) { row in HStack { Text(row.0).frame(width: 110, alignment: .leading).font(.subheadline.weight(.semibold)); Text(row.1).foregroundStyle(.secondary); Spacer(); Text(row.2).font(.caption).foregroundStyle(row.2 == "Native" ? .green : .secondary).padding(.horizontal, 9).padding(.vertical, 4).background(Color.primary.opacity(0.06), in: Capsule()) }.padding(.vertical, 9); Divider() } } }
}

struct HistoryView: View { @ObservedObject var store: AmberStore; var body: some View { VStack(alignment: .leading, spacing: 20) { PageHeader(title: "History", subtitle: "A local trail of files Amberflow has seen."); if store.recentFiles.isEmpty { EmptyState() } else { ScrollView { LazyVStack(spacing: 9) { ForEach(store.recentFiles) { FileRow(file: $0, store: store) } } } } }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) } }

struct SettingsView: View {
    @ObservedObject var store: AmberStore
    var body: some View { Form { Section("Finder & Desktop") { Label(store.gestureStatus, systemImage: "cursorarrow.motionlines"); Text("Drag a file in Finder or on the Desktop. Keep holding the mouse, then hold ⌘ for tools, ⌃ for actions, or ⇧ for conversion. Release over an option to use it; release outside to cancel.").font(.caption).foregroundStyle(.secondary) }
        Section("Appearance") { Picker("Theme", selection: Binding(get: { store.theme }, set: { store.setTheme($0) })) { ForEach(AmberTheme.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented); Toggle("Sound and haptic feedback", isOn: Binding(get: { store.soundFeedback }, set: { store.setSound($0) })); Toggle("Launch at login", isOn: Binding(get: { store.launchAtLogin }, set: { store.setLogin($0) })) }
        Section("Workflow") { HStack { Text("Output folder"); Spacer(); Text(store.outputDirectory.isEmpty ? "Same as source" : URL(fileURLWithPath: store.outputDirectory).lastPathComponent).foregroundStyle(.secondary); Button("Choose…") { chooseFolder() } }; Text("Choose a folder where Amberflow may save results. Every folder inside it is included.").font(.caption).foregroundStyle(.secondary) }
        Section("About Amberflow") { HStack { BrandMark(); VStack(alignment: .leading) { Text("Amberflow \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")").font(.headline); Text("A native, local-first file utility").foregroundStyle(.secondary) }; Spacer() }; Text("Built with SwiftUI, ImageIO, PDFKit, and Vision. Your files never leave this Mac.").font(.caption).foregroundStyle(.secondary) }
    }.formStyle(.grouped).padding(20) }
    private func chooseFolder() { let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.begin { if $0 == .OK { store.setOutputDirectory(panel.url) } } }
}

struct ProView: View { @ObservedObject var store: AmberStore; var body: some View { VStack(alignment: .leading, spacing: 22) { PageHeader(title: "Amberflow Pro", subtitle: "A clear catalogue of the power tools included in this build."); AmberCard { VStack(alignment: .leading, spacing: 15) { HStack { Image(systemName: "sparkles").font(.title2).foregroundStyle(.orange); Text(store.hasFullUnlock ? "Full access is on" : "Unlock the complete local toolkit").font(.title3.weight(.semibold)); Spacer(); if !store.hasFullUnlock { Button("Enable locally") { store.unlockLocally() }.buttonStyle(.borderedProminent).tint(.orange) } else { Label("Enabled", systemImage: "checkmark.seal.fill").foregroundStyle(.green) } }; Text("This original implementation does not connect to a billing service. Pro is a local feature flag so every tool can be tested without an account.").font(.caption).foregroundStyle(.secondary) } }
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) { ForEach([("Batch drops", "tray.2"), ("Vision OCR + QR", "viewfinder"), ("PDF studio", "doc.text.image"), ("Image compression", "dial.medium"), ("Metadata control", "tag"), ("Local history", "clock.arrow.circlepath")], id: \.0) { name, icon in HStack { Image(systemName: icon).foregroundStyle(.orange); Text(name); Spacer(); Image(systemName: "checkmark").foregroundStyle(.green) }.padding(13).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 13)) } }
        Spacer()
    }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) } }

struct PageHeader: View { let title: String; let subtitle: String; var body: some View { VStack(alignment: .leading, spacing: 5) { Text(title).font(.largeTitle.weight(.bold)); Text(subtitle).foregroundStyle(.secondary) } } }
