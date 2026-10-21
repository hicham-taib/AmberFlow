import AppKit

@MainActor
enum GesturePolling {
    static func start(interval: TimeInterval = 1.0 / 60, tick: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { tick() }
        }
        timer.tolerance = 0.003
        // Explicit modes also work before AppKit has populated the common-mode set.
        for mode in [RunLoop.Mode.common, .eventTracking, .modalPanel] {
            RunLoop.main.add(timer, forMode: mode)
        }
        return timer
    }
}

// A fresh drag pasteboard is the evidence that the held mouse is carrying files.
// Reading Finder's selection through Apple Events is deliberately not part of this path.
struct FileDragGesture {
    struct Sample {
        var mouseIsDown: Bool
        var point: NSPoint
        var mode: RadialMode?
        var pasteboardChangeCount: Int
        var urls: [URL]
    }

    enum Effect: Equatable {
        case none
        case show(RadialMode, [URL], NSPoint)
        case update(NSPoint)
        case hide
    }

    private var baseline: Int
    private var urls: [URL] = []
    private var shownMode: RadialMode?
    private var anchor: NSPoint?
    private var cancelled = false

    init(pasteboardChangeCount: Int) { baseline = pasteboardChangeCount }

    func hasNewPasteboard(_ changeCount: Int) -> Bool { changeCount != baseline }

    mutating func update(_ sample: Sample) -> Effect {
        guard sample.mouseIsDown else {
            let wasVisible = shownMode != nil
            baseline = sample.pasteboardChangeCount
            urls = []
            shownMode = nil
            anchor = nil
            cancelled = false
            return wasVisible ? .hide : .none
        }
        guard !cancelled else { return .none }

        if sample.pasteboardChangeCount != baseline, !sample.urls.isEmpty {
            urls = sample.urls
        }
        guard !urls.isEmpty else { return .none }
        if let mode = sample.mode, mode != shownMode {
            anchor = anchor ?? sample.point
            shownMode = mode
            return .show(mode, urls, anchor!)
        }
        return shownMode == nil ? .none : .update(sample.point)
    }

    mutating func cancel() {
        cancelled = true
        shownMode = nil
        urls = []
        anchor = nil
    }
}

@MainActor
enum DraggedFiles {
    static let legacyFileNames = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    static func read(from pasteboard: NSPasteboard) -> [URL] {
        let directURLs = (pasteboard.pasteboardItems ?? []).compactMap { item -> URL? in
            guard let value = item.string(forType: .fileURL), let nativeURL = NSURL(string: value), nativeURL.isFileURL else { return nil }
            return nativeURL.filePathURL
        }
        if !directURLs.isEmpty { return directURLs }
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ?? []
        let urls = objects.compactMap { ($0 as? NSURL).map { $0 as URL } }.filter(\.isFileURL)
        if !urls.isEmpty { return urls }
        if let paths = pasteboard.propertyList(forType: legacyFileNames) as? [String] {
            return paths.map { URL(fileURLWithPath: $0) }
        }
        return []
    }
}

enum RadialGeometry {
    static let size: CGFloat = 304
    static let center = size / 2
    static let outerRadius: CGFloat = 141
    static let innerRadius: CGFloat = 59

    static func item(at point: NSPoint, mode: RadialMode) -> RadialItem? {
        let dx = point.x - center
        let dy = point.y - center
        guard (innerRadius...outerRadius).contains(hypot(dx, dy)) else { return nil }
        let items = RadialItem.items(for: mode)
        let step = 360.0 / Double(items.count)
        let angle = atan2(dy, dx) * 180 / .pi
        let relative = (angle + 450).truncatingRemainder(dividingBy: 360)
        let index = Int((relative + step / 2) / step) % items.count
        let centerAngle = -90 + Double(index) * step
        let difference = abs((angle - centerAngle + 540).truncatingRemainder(dividingBy: 360) - 180)
        return difference <= max(13, step / 2 - 3.5) ? items[index] : nil
    }
}
