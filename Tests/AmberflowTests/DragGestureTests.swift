import AppKit
import Testing
@testable import Amberflow

struct DragGestureTests {
    let file = URL(fileURLWithPath: "/tmp/amberflow-gesture-test.png")
    let point = NSPoint(x: 420, y: 360)

    func sample(down: Bool = true, mode: RadialMode? = nil, count: Int = 11, urls: [URL]? = nil) -> FileDragGesture.Sample {
        .init(mouseIsDown: down, point: point, mode: mode, pasteboardChangeCount: count, urls: urls ?? [file])
    }

    @Test(arguments: [RadialMode.command, .control, .shift])
    func opensDuringHeldDrag(mode: RadialMode) {
        var gesture = FileDragGesture(pasteboardChangeCount: 10)
        #expect(gesture.update(sample()) == .none)
        #expect(gesture.update(sample(mode: mode)) == .show(mode, [file], point))
    }

    @Test func stationaryDragStillDetectsModifier() {
        var gesture = FileDragGesture(pasteboardChangeCount: 10)
        _ = gesture.update(sample())
        #expect(gesture.update(sample(mode: .command)) == .show(.command, [file], point))
    }

    @Test func modifierWithoutDragDoesNotOpen() {
        var gesture = FileDragGesture(pasteboardChangeCount: 10)
        #expect(gesture.update(sample(down: false, mode: .command)) == .none)
        #expect(gesture.update(sample(mode: .command)) == .none)
    }

    @Test func staleDragPasteboardDoesNotOpenDuringPlainClick() {
        var gesture = FileDragGesture(pasteboardChangeCount: 11)
        #expect(gesture.update(sample(mode: .shift)) == .none)
    }

    @Test func delayedPayloadCanOpenWhileMouseStillHeld() {
        var gesture = FileDragGesture(pasteboardChangeCount: 10)
        #expect(gesture.update(sample(mode: .control, urls: [])) == .none)
        #expect(gesture.update(sample(mode: .control)) == .show(.control, [file], point))
    }

    @Test func releaseNeverOpensALatePanel() {
        var gesture = FileDragGesture(pasteboardChangeCount: 10)
        _ = gesture.update(sample(mode: .command, urls: []))
        #expect(gesture.update(sample(down: false, mode: .command)) == .none)
        #expect(gesture.update(sample(mode: .command)) == .none)
    }

    @Test func releaseDismissesWithoutExecutingAction() {
        var gesture = FileDragGesture(pasteboardChangeCount: 10)
        _ = gesture.update(sample(mode: .command))
        #expect(gesture.update(sample(down: false)) == .hide)
        #expect(gesture.update(sample(down: false)) == .none)
    }

    @Test func modifierSwitchKeepsAnchor() {
        var gesture = FileDragGesture(pasteboardChangeCount: 10)
        _ = gesture.update(sample(mode: .command))
        var moved = sample(mode: .shift)
        moved.point = NSPoint(x: 100, y: 100)
        #expect(gesture.update(moved) == .show(.shift, [file], point))
    }

    @Test func cancellationRemainsUntilMouseReleased() {
        var gesture = FileDragGesture(pasteboardChangeCount: 10)
        _ = gesture.update(sample(mode: .command))
        gesture.cancel()
        #expect(gesture.update(sample(mode: .command)) == .none)
        _ = gesture.update(sample(down: false))
        #expect(gesture.update(sample(mode: .control, count: 12)) == .show(.control, [file], point))
    }

    @Test func noFilePayloadNeverOpens() {
        var gesture = FileDragGesture(pasteboardChangeCount: 10)
        #expect(gesture.update(sample(mode: .command, urls: [])) == .none)
    }

    @Test func allWedgeCentersHitTheMatchingAction() {
        for mode in [RadialMode.command, .control, .shift] {
            let items = RadialItem.items(for: mode)
            for (index, item) in items.enumerated() {
                let angle = (-90 + Double(index) * 360 / Double(items.count)) * .pi / 180
                let point = NSPoint(x: RadialGeometry.center + cos(angle) * 101,
                                    y: RadialGeometry.center + sin(angle) * 101)
                #expect(RadialGeometry.item(at: point, mode: mode) == item)
            }
        }
    }

    @Test func centerAndOutsideAreNotActions() {
        #expect(RadialGeometry.item(at: NSPoint(x: 152, y: 152), mode: .command) == nil)
        #expect(RadialGeometry.item(at: .zero, mode: .command) == nil)
    }

    @Test @MainActor func realFileURLPasteboardRoundTrip() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        #expect(pasteboard.writeObjects([file as NSURL]))
        #expect(DraggedFiles.read(from: pasteboard) == [file])
    }

    @Test @MainActor func legacyFinderPathsAreAccepted() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        #expect(pasteboard.setPropertyList([file.path], forType: DraggedFiles.legacyFileNames))
        #expect(DraggedFiles.read(from: pasteboard) == [file])
    }

    @Test @MainActor func multipleFilesAndUnicodeNamesSurviveTheDragPasteboard() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let files = [file, URL(fileURLWithPath: "/tmp/Crème – image 你好.heic")]
        #expect(pasteboard.writeObjects(files as [NSURL]))
        #expect(DraggedFiles.read(from: pasteboard) == files)
    }

    @Test @MainActor func timerRunsInNativeDragTrackingMode() {
        let probe = TimerProbe()
        let timer = GesturePolling.start(interval: 0.005) { probe.fired = true }
        defer { timer.invalidate() }
        let deadline = Date().addingTimeInterval(0.2)
        while !probe.fired, Date() < deadline {
            RunLoop.main.run(mode: .eventTracking, before: deadline)
        }
        #expect(probe.fired)
    }
}

@MainActor private final class TimerProbe { var fired = false }
