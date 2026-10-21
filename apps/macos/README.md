# Amberflow for macOS

The production macOS implementation is a Swift 6 package using SwiftUI, AppKit, ImageIO, PDFKit, Vision, and other Apple frameworks.

## Build and run

```sh
./scripts/build-app.sh
open build/Amberflow.app
```

## Test

```sh
swift test
```

Optional native Terminal integration checks:

```sh
AMBERFLOW_NATIVE_ACTION_TESTS=1 swift test
```

## Package

```sh
./scripts/build-dmg.sh
```

The result is `build/Amberflow-1.7.0.dmg`. The script creates and verifies a universal Apple Silicon/Intel application with an ad hoc signature. It refuses to overwrite an existing release image.

See [ACTION_AUDIT.md](ACTION_AUDIT.md) for verified behaviors and current limitations.
