# Amberflow architecture

Amberflow is organized as a platform monorepo. Each operating system owns its native UI and system integrations while following the same product language and safety rules.

```text
AmberFlow/
├── apps/
│   ├── macos/                  Native SwiftUI implementation
│   └── windows/
│       ├── src/
│       │   ├── Amberflow.Core          Domain rules with no UI dependency
│       │   ├── Amberflow.Application   Use-case contracts and dispatch
│       │   └── Amberflow.Windows       WPF UI and Windows integrations
│       └── tests/
├── docs/                       Shared product and architecture decisions
└── scripts/                    Repository-level build entry points
```

## Dependency direction

```text
Amberflow.Windows ──→ Amberflow.Application ──→ Amberflow.Core
       │                                              ↑
       └──────────────────────────────────────────────┘
```

`Amberflow.Core` contains stable concepts such as palettes, actions, radial geometry, and collision-safe output naming. It does not reference WPF, Win32, the filesystem, or clipboard APIs.

`Amberflow.Application` defines use cases through small interfaces. It validates dispatch requests and converts infrastructure failures into user-visible errors without knowing how the UI renders them.

`Amberflow.Windows` is the composition root. It owns WPF controls, Win32 gesture observation, File Explorer integration, dialogs, clipboard operations, process launches, and concrete action handlers.

The macOS application remains a native Swift package because its gesture loop and integrations depend directly on AppKit, SwiftUI, ImageIO, Vision, and PDFKit. Its code can be decomposed internally over time without forcing artificial source sharing with .NET.

## Engineering rules

1. Originals are never overwritten by conversion or editing actions.
2. Move and export collisions receive numbered names.
3. Partial multi-file moves attempt rollback before surfacing an error.
4. Unsupported actions are visible as roadmap items but never claim success.
5. Core rules must be testable without launching platform UI.
6. Generated binaries and local IDE state are not committed.
7. Platform-specific behavior is documented rather than hidden behind misleading abstraction.

## Windows gesture pipeline

```text
File Explorer drag
  → Win32 input polling confirms drag-like movement and a modifier
  → WPF topmost radial drop target appears at the pointer
  → OLE file drop supplies actual paths
  → radial hit testing selects an action
  → ActionDispatcher invokes one concrete handler
  → handler reports success or an actionable error
```

The preview implementation intentionally activates only while File Explorer is the foreground process. It does not install a shell extension, inject into Explorer, or use a global keyboard hook.
