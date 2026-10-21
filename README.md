# Amberflow

**A fast, native file-action wheel for macOS.**

Amberflow turns common Finder workflows into a single drag gesture. Start dragging one or more files, hold a modifier key, and drop onto the action you want—without opening a full application window or breaking your flow.

Built entirely with SwiftUI and Apple frameworks, Amberflow runs as a lightweight menu-bar utility. It requires no account, cloud service, network connection, or third-party SDK.

## Highlights

- Three contextual radial palettes for tools, file actions, and conversions
- Native image editing, cropping, annotation, background, redaction, and compression
- Image, PDF, text, Markdown, and ZIP conversion
- OCR and QR recognition powered by Apple Vision
- Metadata inspection and metadata-free image copies
- Quick Look previews, AirDrop, clipboard, Finder, and Terminal integration
- Collision-safe file moves and non-destructive output naming
- Recent-file history, favorites, configurable output location, and launch-at-login support
- Local-only state and processing

## Requirements

- macOS 14 Sonoma or later
- Apple Silicon or Intel Mac
- Swift 6 and Xcode Command Line Tools when building from source

## Install from the DMG

1. Open `Amberflow-1.7.0.dmg`.
2. Drag **Amberflow** into the **Applications** folder.
3. Launch Amberflow from Applications.
4. Look for the Amberflow icon in the macOS menu bar.

The current release is ad hoc signed, but it is not Developer ID signed or notarized. If macOS blocks the first launch, open **System Settings → Privacy & Security** and approve Amberflow there.

To uninstall, quit Amberflow, move `/Applications/Amberflow.app` to the Trash, and remove it from **System Settings → General → Login Items** if present.

## Use the action wheel

1. In Finder or on the Desktop, start dragging one or more files.
2. While continuing to hold the drag, press **Command**, **Control**, or **Shift**.
3. Move the pointer over an action in the wheel.
4. Release the file to run the selected action.

Release outside the wheel to cancel. You can switch modifier keys while dragging to change palettes without restarting the gesture.

| Modifier | Palette | Actions |
| --- | --- | --- |
| **Command (⌘)** | Tools | Compress, Metadata, Edit, Crop, Annotate, Add Background, Redact |
| **Control (⌃)** | Actions | AirDrop, Float, Copy, Move, Copy Path, Terminal |
| **Shift (⇧)** | Convert | PNG, JPG, HEIC, TIFF, PDF, TXT, MD, ZIP |

Amberflow reads file URLs from the active macOS drag pasteboard and observes the current pointer and modifier state. It does not rely on Finder Automation or an Accessibility event tap. Stale drag data and modifier-only key presses do not open the wheel.

## Capabilities

### Image tools

- **Edit:** Adjust brightness, contrast, saturation, and rotation.
- **Crop:** Select and export a rectangular image region.
- **Annotate:** Add flattened text annotations.
- **Add Background:** Place a color behind transparent content with optional padding.
- **Redact:** Permanently replace selected pixels in a flattened PNG.
- **Compress:** Preview estimated JPEG size and save only when the result is smaller.
- **Metadata:** Inspect file, EXIF, GPS, and PDF metadata or create a clean image copy.

All image operations create new files and leave the originals unchanged. Animated images are exported as a single frame. PDF editing, cropping, and annotation open in Preview; secure PDF redaction is intentionally unavailable.

### File actions

- **AirDrop** opens the native recipient chooser and never sends automatically.
- **Float** presents selected files in an always-on-top Quick Look panel.
- **Copy** places file URLs on the macOS pasteboard.
- **Move** asks for a destination and adds numbered suffixes instead of overwriting collisions.
- **Copy Path** copies exact absolute paths separated by newlines.
- **Terminal** opens a shell in the selected folder or the selected file's containing folder.

### Conversion

| Input | Supported output |
| --- | --- |
| Images | PNG, JPG, HEIC, TIFF, PDF, TXT/MD through OCR, ZIP |
| PDFs | PNG, JPG, HEIC, TIFF from the first page; TXT/MD from text extraction or OCR; ZIP |
| Plain text and RTF | PDF, TXT, MD, ZIP |
| Files and folders | ZIP |

Conversions run away from the main UI and display progress. Results are saved beside each source by default, or in the configured output folder. Unsupported combinations are disabled and conversion errors are surfaced to the user.

## Build from source

Clone the repository and build the application bundle:

```sh
git clone https://github.com/hicham-taib/AmberFlow.git
cd AmberFlow
./scripts/build-app.sh
open build/Amberflow.app
```

The build script compiles a release bundle by default, copies its resources, and applies an ad hoc signature. Pass `debug` to create a debug build instead:

```sh
./scripts/build-app.sh debug
```

## Create a distributable DMG

```sh
./scripts/build-dmg.sh
```

The packaging script builds separate Apple Silicon and Intel binaries, combines them into a universal application, verifies both architectures and the code signature, then creates:

```text
build/Amberflow-1.7.0.dmg
```

The disk image includes an Applications shortcut and installation instructions. To prevent accidental replacement of a release artifact, the script stops if a DMG with the same version already exists.

## Test and diagnose

Run the automated regression suite:

```sh
swift test
```

The suite covers drag-state transitions, radial hit testing, file moves and clipboard behavior, image operations, metadata removal, OCR, QR recognition, PDF conversion, and ZIP round trips.

Optional native integration tests open Terminal with a local QA fixture:

```sh
AMBERFLOW_NATIVE_ACTION_TESTS=1 swift test
```

Inspect the live Finder gesture state without logging file names or contents:

```sh
build/Amberflow.app/Contents/MacOS/Amberflow --gesture-diagnostics
```

Launch a focused local UI check:

```sh
build/Amberflow.app/Contents/MacOS/Amberflow \
  --check-action crop /absolute/path/to/image.png
```

Supported check actions are `edit`, `crop`, `annotate`, `background`, `redact`, `compress`, `metadata`, `float`, and `terminal`.

For detailed action-by-action verification and current constraints, see [ACTION_AUDIT.md](ACTION_AUDIT.md).

## Privacy and data

Amberflow performs file processing locally with Apple system frameworks. It does not include analytics, advertising, cloud sync, user accounts, or network-backed services.

Recent-file state is stored at:

```text
~/Library/Application Support/Amberflow/state.json
```

## Current scope

Amberflow does not include cloud sync, subscription billing, proprietary Office or media codecs, automatic photographic background removal, secure PDF redaction, or whole-document PDF image export. It is an original implementation and does not copy Tangerine branding or private code.

## License

No open-source license has been declared. All rights are reserved unless the repository owner states otherwise.
