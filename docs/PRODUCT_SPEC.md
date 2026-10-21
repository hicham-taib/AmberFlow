# Shared product specification

## Product promise

Amberflow shortens file workflows without replacing the operating system's file manager. A user starts a native file drag, reveals a contextual wheel with a modifier, and drops onto one explicit action.

## Platform controls

| Palette | macOS | Windows |
| --- | --- | --- |
| Tools | Command (⌘) | Alt |
| Actions | Control (⌃) | Control |
| Convert | Shift (⇧) | Shift |

Windows uses Alt instead of the Windows key because a bare Windows-key gesture conflicts with the Start menu.

## Shared palettes

- **Tools:** Compress, Metadata, Edit, Annotate, Add Background, Crop, Redact
- **Actions:** Share/AirDrop, Preview/Float, Copy, Move, Copy Path, Terminal
- **Convert:** PNG, JPG, HEIC, TIFF, PDF, TXT, MD, ZIP

Labels may adapt to native platform language, but an action must retain the same outcome and safety expectations.

## Cross-platform safety contract

- Releasing outside the wheel cancels without side effects.
- A missing or stale input produces an error before clipboard or filesystem state changes.
- Generated files use a new path and preserve the source.
- Move never overwrites an existing destination.
- Multi-file operations report partial failure and roll back when practical.
- Share actions always show the system recipient or target picker.
- Unsupported formats are disabled or reported honestly.
- File contents and paths stay local unless the user explicitly invokes a system sharing action.

## Windows delivery stages

### Stage 1 — foundation (current)

- Native tray application lifecycle
- File Explorer drag/modifier observation
- Radial WPF drop target with shared palettes
- Copy, Copy Path, Move, Preview/Open, Terminal, and ZIP handlers
- Testable radial geometry, action catalog, and collision naming

### Stage 2 — native file tools

- Windows Imaging Component-based image conversion
- Image crop, adjustment, annotation, background, and flattened redaction
- Metadata inspection and clean-copy export
- PDF text extraction and first-page rendering

### Stage 3 — product readiness

- Settings and recent-file persistence
- Startup registration
- Native Windows share UI
- Signed MSIX packaging and upgrade behavior
- Accessibility, keyboard navigation, telemetry-free diagnostics, and Windows 10/11 QA
