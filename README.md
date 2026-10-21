# Amberflow

Amberflow is an original native macOS menu-bar file utility inspired by the interaction model of Tangerine. Drag files in Finder or on the Desktop, hold Command, Control, or Shift, and release onto a compact action wheel.

It is built in SwiftUI with Apple frameworks only. State is stored locally in `~/Library/Application Support/Amberflow/state.json`; no account, network service, or third-party SDK is required.

## Build and run

```sh
./scripts/build-app.sh
open build/Amberflow.app
```

The packaged application is `build/Amberflow.app`. Opening it starts the menu-bar utility in the background. It has no Dock icon, main window, or Open Workspace action; opening it again does not create a window. The Finder gesture service starts at application launch, independently of the menu being opened. Preferences, recent files, and Quit are available from its menu-bar icon. Utility panels appear only when an action needs them.

## Shareable disk image

```sh
./scripts/build-dmg.sh
```

This builds a universal Intel/Apple Silicon app for macOS 14 or later and creates `build/Amberflow-1.7.0.dmg`, with an Applications shortcut and installation instructions. It leaves the running `build/Amberflow.app` untouched. The app is ad hoc signed, not Developer ID signed or notarized; recipients may need to approve it in macOS Privacy & Security. Intel is cross-compiled, not runtime-tested on this Apple Silicon development Mac. The script refuses to overwrite an existing DMG.

## Included

- Menu-bar-only operation with recent files and local persistence
- Image conversion through ImageIO, PDF creation, text/markdown export, and ZIP packaging
- Image editing, crop selection, text annotation, background color/padding, permanent pixel redaction, compression with size estimates, and a metadata inspector
- Metadata preservation toggle, metadata-free image copies, OCR and QR extraction through Vision
- PDF merge and first-page extraction through PDFKit
- Quick Look, Finder, Terminal, Share, favorite and remove actions
- Recent-file conversion, OCR, QR, path copying, previews, and Finder actions from the menu bar
- Menu-bar preferences for appearance, metadata, feedback, launch at login, and output folder
- Finder radial panel: begin dragging a selected file in Finder, then press Command, Control, or Shift without releasing the drag to reveal a compact floating action wheel near the pointer. Keep dragging onto the desired wedge and release there to perform it; releasing outside the wheel dismisses it without taking action.

## Finder radial panel

Amberflow reads file URLs from the active macOS drag pasteboard and polls the current mouse and modifier state on a timer in common run-loop modes. Opening the panel does not wait for Finder Automation or an Accessibility event tap. Start dragging a Finder or Desktop file, then press Command, Control, or Shift while keeping the mouse held. A compact 304-point wheel appears at the pointer and accepts a native file drop onto a wedge. Releasing outside the wheel dismisses it without an Amberflow action. Switching modifiers changes palettes in place. Old drag pasteboard contents and modifier presses without a new file drag never open a wheel.

Run `swift test` for regression checks. For live gesture troubleshooting, launch `build/Amberflow.app/Contents/MacOS/Amberflow --gesture-diagnostics`; its console reports button state, modifier, drag pasteboard generation, file count and panel visibility, without file names or contents.

The three palettes are:

- Command / Tools: Compress, Metadata, Edit, Crop, Annotate, Add Background, and Redact.
- Control / Actions: AirDrop, Float, Copy, Move, Copy Path, and Terminal.
- Shift / Convert: PNG, JPG, HEIC, TIFF, PDF, TXT, MD, and ZIP.

Conversions save beside each original by default and run off the UI thread with a floating progress card. Copy and Copy Path use the macOS pasteboard. Move asks for a destination and preserves collisions with numbered names; it never deletes an existing destination. AirDrop opens the system recipient chooser. Float displays the file itself through Quick Look in an always-on-top panel. Terminal opens a shell directly in the selected file's containing folder, or in the selected folder itself, without using the clipboard.

Image Edit, Crop, Annotate, Add Background, Redact, and Compress open focused utility panels only when chosen. Saves create new files. Image redaction replaces pixels in a flattened PNG; the original remains untouched. Add Background adds a color behind transparent areas and optional padding; it does not remove an existing photographic background. Compression shows a JPEG size estimate and refuses to produce a larger file. Animated images are edited/exported as a single frame. PDF Edit/Crop/Annotate open Preview, where the user chooses the appropriate tool. Secure PDF redaction is unavailable and disabled.

Image and PDF inputs can export PNG, JPG, HEIC and TIFF. PDF-to-image export uses the first page and is labeled accordingly in the wheel and recent-file menu. Images export searchable text using Vision OCR. PDFs extract text from all pages, with OCR for scanned PDFs. Plain text/RTF can export PDF/TXT/MD. ZIP supports files and folders. Unsupported conversions are dimmed instead of claiming success; errors are visible.

See [ACTION_AUDIT.md](ACTION_AUDIT.md) for per-action verification and limitations. Optional native integration checks run with `AMBERFLOW_NATIVE_ACTION_TESTS=1 swift test`; they open Terminal with a local QA file. A local UI check can be launched with `build/Amberflow.app/Contents/MacOS/Amberflow --check-action crop /absolute/path/image.png` (also edit, annotate, background, redact, compress, metadata, float, terminal).

The app deliberately does not copy Tangerine's branding or private implementation. Cloud sync, subscription billing, proprietary Office/media conversion, background removal, and secure PDF redaction are not included.
