# Amberflow

**Native radial file actions for macOS and Windows.**

Amberflow turns common file-management workflows into one drag gesture. Start dragging files in the operating system's file manager, hold a modifier key, and release onto a contextual action wheel.

The project favors native frameworks, local processing, explicit platform behavior, and non-destructive file operations. It requires no account or cloud service.

## Platform status

| Platform | Status | Technology |
| --- | --- | --- |
| macOS 14+ | Production implementation | Swift 6, SwiftUI, AppKit, ImageIO, PDFKit, Vision |
| Windows 10/11 | Preview implementation | .NET 8, WPF, Win32, Windows Shell |

The macOS application includes the complete action set and automated regression coverage. The Windows application now has its native tray lifecycle, File Explorer gesture monitor, radial drop UI, clean action-dispatch architecture, and initial file actions. Image and PDF tools are the next Windows milestone.

## Repository structure

```text
AmberFlow/
├── apps/
│   ├── macos/       Swift package, resources, tests, and packaging scripts
│   └── windows/     .NET solution, WPF application, domain core, and tests
├── docs/            Shared product specification and architecture
└── scripts/         Repository-level build and test entry points
```

See [ARCHITECTURE.md](docs/ARCHITECTURE.md) for dependency boundaries and [PRODUCT_SPEC.md](docs/PRODUCT_SPEC.md) for shared behavior, safety rules, and the Windows roadmap.

## Interaction model

| Palette | macOS | Windows | Actions |
| --- | --- | --- | --- |
| Tools | Command (⌘) | Alt | Compress, Metadata, Edit, Annotate, Add Background, Crop, Redact |
| Actions | Control (⌃) | Control | Share/AirDrop, Preview/Float, Copy, Move, Copy Path, Terminal |
| Convert | Shift (⇧) | Shift | PNG, JPG, HEIC, TIFF, PDF, TXT, MD, ZIP |

Release outside the wheel to cancel. Unsupported actions never report false success, generated files never replace their sources, and destination collisions receive numbered names.

## macOS

### Build and run

```sh
./scripts/build-macos.sh
open apps/macos/build/Amberflow.app
```

### Test

```sh
./scripts/test-macos.sh
```

### Create the universal DMG

```sh
cd apps/macos
./scripts/build-dmg.sh
```

The package is written to `apps/macos/build/Amberflow-1.7.0.dmg`. It is ad hoc signed but not Developer ID signed or notarized.

Read the [macOS guide](apps/macos/README.md) and [action audit](apps/macos/ACTION_AUDIT.md) for detailed behavior and limitations.

## Windows

### Requirements

- Windows 10 or Windows 11
- .NET 8 SDK
- Visual Studio 2022 with the **.NET desktop development** workload, or the .NET CLI

### Build, test, and run

```powershell
.\scripts\build-windows.ps1
.\scripts\test-windows.ps1
dotnet run --project .\apps\windows\src\Amberflow.Windows\Amberflow.Windows.csproj
```

### Publish a self-contained preview

```powershell
.\scripts\publish-windows.ps1 -Runtime win-x64
```

Use `win-arm64` for Windows on Arm. Published files are placed under `artifacts/windows/` and are intentionally excluded from source control.

Successful CI runs publish the self-contained x64 executable as the `Amberflow-Windows-x64` workflow artifact.

Read the [Windows guide](apps/windows/README.md) for implemented actions and current preview constraints.

## Privacy and safety

- File processing occurs locally.
- No analytics, advertising, account, or network-backed service is included.
- Conversions and edits create new files.
- Move operations preserve existing destinations and attempt rollback after partial failure.
- Sharing always requires a native system handoff and explicit user selection.
- Diagnostic output does not log file names or contents.

The macOS app stores recent-file state in `~/Library/Application Support/Amberflow/state.json`. Equivalent Windows settings persistence will be added with the next product milestone.

## Contributing

Keep platform integrations at the outer edge of the codebase and place reusable rules in the platform-neutral core. New actions should include:

1. A documented outcome and supported input set.
2. Collision and source-preservation behavior.
3. Unit coverage for domain rules.
4. A clear unavailable state on platforms where implementation is incomplete.
5. Manual verification notes for native system handoffs.

## License

No open-source license has been declared. All rights are reserved unless the repository owner states otherwise.
