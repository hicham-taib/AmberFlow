# Amberflow 1.7 action audit

This audit distinguishes output tests from native application handoffs. Tests use generated local fixtures, preserve original files, and do not send files to other devices.

## Tools wheel

| Action | Implemented behavior | Verification / limit |
| --- | --- | --- |
| Compress | JPEG quality panel, estimated original/result sizes; ZIP for non-images | Generated image produces a smaller, decodable JPEG. Already optimized inputs cannot save a larger "compressed" copy. One image at a time. |
| Metadata | Inspect real file, image EXIF/GPS and PDF attributes; save a clean PNG copy | Pixel dimensions and embedded GPS are read; GPS/private EXIF are absent from clean copy and remain in original. |
| Edit | Brightness, contrast, saturation and rotation, saved as new PNG | Output changes and rotation dimensions are tested. The real UI Rotate + Save Copy flow produced a 500×800 image from an 800×500 original. PDFs use Preview; other files use their default application. |
| Crop | Drag a rectangle and save the selected pixels | Dimensions and exact source pixels are checked. PDFs use Preview's cropping tools. |
| Annotate | Text entry and image positioning, flattened into a new PNG | Rendered pixel data changes and original stays unchanged. PDFs use Preview's annotation tools. |
| Add BG | Choose a background color and padding, saved as a new PNG | Output dimensions and exact background pixel color are tested. It does not remove a photographic background. |
| Redact | Draw solid black regions; save flattened image pixels | Redacted pixels become opaque black; other pixels remain. No original pixels/layers are embedded in the exported PNG. Secure PDF redaction remains disabled. |

Image editors operate on one raster image at a time. Animated formats export one frame. Original files are never edited in place.

## Actions wheel

| Action | Implemented behavior | Verification / limit |
| --- | --- | --- |
| Terminal | Open Terminal directly at a file's containing directory; a selected directory opens itself | Native launch test passes without changing the clipboard. A newly created Terminal shell's actual `cwd` was independently observed at `build/Terminal QA`; its process parent is Terminal. Special-character paths and missing inputs are tested. |
| Copy | Put file URLs on the macOS pasteboard | Two real files round-trip with spaces/Unicode intact. Invalid inputs do not clear the existing clipboard. |
| Copy Path | Copy exact full paths, separated by newlines | Real pasteboard contents checked. No shell escaping is added to file paths. |
| Move | Ask for destination; use numbered names on collisions | Existing contents are preserved; same-folder moves do nothing; folder-into-itself is rejected; a partial failure rolls back moved items when possible. |
| Float | Always-on-top Quick Look content preview, including switching among multiple files | A real file preview was visually verified in the running app. Preview support depends on installed Quick Look providers. |
| AirDrop | Retain and open macOS AirDrop service after checking file support | System handoff; a recipient must be chosen by the user. Actual receipt on another device is not verified. No file is sent automatically. |

## Conversion wheel

| Action | Verification / supported inputs |
| --- | --- |
| PNG | Generated input converts to a decodable PNG with correct dimensions. Also supports the first PDF page. |
| JPG | Same dimension/decode checks; transparent areas flatten onto white. Also supports the first PDF page. |
| HEIC | Encoded and decoded on this Mac with correct dimensions. Only enabled if the native encoder is available. |
| TIFF | Encoded and decoded with correct dimensions. Also supports the first PDF page. |
| PDF | Image creates a readable one-page PDF. Text creates a readable PDF and its text round-trips. Existing PDFs can be copied to a new file. |
| TXT | Plain text retains contents; PDF text extraction and actual image OCR are tested. Scanned PDF text uses OCR. |
| MD | Same text/OCR checks. It is plain extracted text in a Markdown file; document layout is not reconstructed. |
| ZIP | Archive is extracted and payload bytes are verified. Single files do not acquire an unwanted parent folder. ZIPs cannot be written inside the directory being archived. |

Unsupported input/format combinations are dimmed and rejected. Results use collision-free names. Batch outputs use each file's own source folder unless an explicit output folder is configured. Conversion settings are captured per job, and conversion work runs off the main thread.

## Other checks

- Existing drag-gesture regressions cover Command/Control/Shift, stale drag data, late release, cancellation, palette switching, and every wedge's hit area.
- The timer is tested in AppKit's drag-tracking run-loop mode.
- Vision QR decoding is tested against a generated QR image.
- All 42 test functions, including optional native Terminal launch and fixture preparation, passed with `AMBERFLOW_NATIVE_ACTION_TESTS=1 swift test`.
- Live UI checks verified metadata inspection, cleaned-copy saving, rotation/save, actual Float content, and the compression estimate/save controls.
- UI QA runs use an isolated temporary history; their sample record was removed from regular history without changing other records.
- Launch remains menu-bar-only (`LSUIElement`, accessory activation), without a main workspace window.
- Launch-at-login and actual AirDrop delivery require user/system choices and are not enabled as part of testing.
- Cloud sync, billing, Office/media codecs, automatic background removal, secure PDF redaction, and whole-document image export are outside this build.
