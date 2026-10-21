import AppKit

enum FileActionError: LocalizedError {
    case invalid(String)
    case unsupported(String)
    var errorDescription: String? {
        switch self { case .invalid(let message), .unsupported(let message): return message }
    }
}

enum FileActions {
    static func validate(_ urls: [URL]) throws {
        guard !urls.isEmpty else { throw FileActionError.invalid("No file was provided.") }
        for url in urls {
            guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
                throw FileActionError.invalid("The file \(url.lastPathComponent) no longer exists.")
            }
        }
    }

    static func terminalDirectory(for url: URL) throws -> URL {
        try validate([url])
        let isDirectory = (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true
        return (isDirectory ? url : url.deletingLastPathComponent()).standardizedFileURL
    }

    // Never replace a destination item or delete a source to resolve a collision.
    static func move(_ urls: [URL], to directory: URL) throws -> [URL] {
        try validate(urls)
        guard (try directory.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else {
            throw FileActionError.invalid("Choose an existing destination folder.")
        }
        let destination = directory.resolvingSymlinksInPath().standardizedFileURL
        for url in urls {
            let source = url.resolvingSymlinksInPath().standardizedFileURL
            if (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true,
               destination.path == source.path || destination.path.hasPrefix(source.path + "/") {
                throw FileActionError.invalid("A folder cannot be moved inside itself.")
            }
        }
        var moved: [(URL, URL)] = []
        do {
            for url in urls {
                if url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL == destination {
                    moved.append((url, url))
                    continue
                }
                let isDirectory = (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true
                let target = uniqueURL(directory.appendingPathComponent(url.lastPathComponent), isDirectory: isDirectory)
                try FileManager.default.moveItem(at: url, to: target)
                moved.append((url, target))
            }
            return moved.map(\.1)
        } catch {
            // Restore already-moved items if a later item fails, without overwriting anything.
            for (source, target) in moved.reversed() where source != target {
                if !FileManager.default.fileExists(atPath: source.path) { try? FileManager.default.moveItem(at: target, to: source) }
            }
            throw error
        }
    }

    static func uniqueURL(_ proposed: URL, isDirectory: Bool = false) -> URL {
        var result = proposed
        var suffix = 2
        let ext = isDirectory ? "" : proposed.pathExtension
        let stem = ext.isEmpty ? proposed.lastPathComponent : proposed.deletingPathExtension().lastPathComponent
        while FileManager.default.fileExists(atPath: result.path) {
            let name = "\(stem) \(suffix)" + (ext.isEmpty ? "" : ".\(ext)")
            result = proposed.deletingLastPathComponent().appendingPathComponent(name, isDirectory: isDirectory)
            suffix += 1
        }
        return result
    }
}

@MainActor
enum NativeFileActions {
    @discardableResult
    static func copyFiles(_ urls: [URL], to pasteboard: NSPasteboard = .general) throws -> Bool {
        try FileActions.validate(urls)
        pasteboard.clearContents()
        guard pasteboard.writeObjects(urls as [NSURL]) else { throw FileActionError.invalid("macOS could not copy the files.") }
        return true
    }

    static func copyPaths(_ urls: [URL], to pasteboard: NSPasteboard = .general) throws {
        try FileActions.validate(urls)
        pasteboard.clearContents()
        guard pasteboard.setString(urls.map(\.path).joined(separator: "\n"), forType: .string) else {
            throw FileActionError.invalid("macOS could not copy the file paths.")
        }
    }

    static func openTerminal(for url: URL) async throws -> URL {
        let directory = try FileActions.terminalDirectory(for: url)
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            throw FileActionError.unsupported("Terminal is not installed.")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        // Terminal's native document-open handler treats a directory URL as a new
        // shell session in that directory. No pasted command or Apple Events needed.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open([directory], withApplicationAt: terminal, configuration: configuration) { app, error in
                if let error { continuation.resume(throwing: error) }
                else if app != nil { continuation.resume() }
                else { continuation.resume(throwing: FileActionError.invalid("Terminal could not open this folder.")) }
            }
        }
        return directory
    }

    static func openInPreview(_ urls: [URL]) async throws {
        try FileActions.validate(urls)
        guard let preview = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview") else {
            throw FileActionError.unsupported("Preview is not installed.")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open(urls, withApplicationAt: preview, configuration: configuration) { app, error in
                if let error { continuation.resume(throwing: error) }
                else if app != nil { continuation.resume() }
                else { continuation.resume(throwing: FileActionError.invalid("Preview could not open the file.")) }
            }
        }
    }
}
