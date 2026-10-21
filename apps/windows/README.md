# Amberflow for Windows

Native Windows implementation of Amberflow, built with .NET 8, WPF, and Win32 APIs.

## Current preview

The application runs in the notification area and watches for drag-like movement in File Explorer. While dragging files, hold:

- **Alt** for Tools
- **Control** for Actions
- **Shift** for Convert

The first implementation includes working Copy, Copy Path, collision-safe Move, Preview/Open, Terminal, and ZIP actions. Other wheel entries are explicit roadmap items and display an honest unavailable message.

## Build

Install the [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0) and use Windows 10 or Windows 11:

```powershell
dotnet restore .\Amberflow.Windows.sln
dotnet build .\Amberflow.Windows.sln -c Release
dotnet test .\Amberflow.Windows.sln -c Release
```

Run the desktop application:

```powershell
dotnet run --project .\src\Amberflow.Windows\Amberflow.Windows.csproj
```

From the repository root, the equivalent commands are:

```powershell
.\scripts\build-windows.ps1
.\scripts\test-windows.ps1
```

Every successful `main` build also publishes `Amberflow-Windows-x64` as a GitHub Actions artifact. It contains the self-contained preview executable and does not require a separate .NET runtime installation.

## Constraints in this stage

- Build and runtime validation must be performed on Windows; WPF cannot run on macOS.
- Gesture detection is intentionally scoped to File Explorer and appears only after drag-threshold movement.
- Tools and non-ZIP conversions are not implemented yet.
- Preview currently uses the registered Windows application instead of an always-on-top embedded preview.
- The notification-area icon is temporary and will be replaced with the product icon during packaging work.

See [the shared product specification](../../docs/PRODUCT_SPEC.md) and [architecture](../../docs/ARCHITECTURE.md) for design decisions and the delivery roadmap.
