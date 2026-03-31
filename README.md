# LaySwitch

[![License: GPL v3](https://img.shields.io/badge/license-GPLv3-blue)](LICENSE)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-brightgreen)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6.0-orange)](https://www.swift.org)

A lightweight macOS menu bar utility that automatically remembers and restores the keyboard input source (layout) for each application. When you switch to an app, LaySwitch restores the layout you were using there last — no manual switching required.

---

## Features

- Runs silently in the menu bar — no Dock icon, no windows
- Remembers one layout per application
- Restores layout on app focus
- Works correctly with fullscreen apps on separate Spaces
- Optional launch at login
- Stores mappings in `~/Library/Application Support/LaySwitch/layouts.json`

## Requirements

| Requirement | Version |
|---|---|
| macOS | 15.0 Sequoia or later |
| Xcode Command Line Tools | 16.0 or later (Swift 6) |

No Apple Developer account or paid certificate required.

## Build & Install

**1. Install Xcode Command Line Tools** (if not already installed):

```bash
xcode-select --install
```

**2. Clone the repository:**

```bash
git clone git@github.com:evsigneevk/LaySwitch.git
cd LaySwitch
```

**3. Build and install:**

```bash
make install
```

This compiles the sources, stops any running instance, copies `LaySwitch.app` to `/Applications`, and launches it.

The app appears as **LS** in your menu bar. That's it — it starts working immediately.

> **First launch / Gatekeeper:** If macOS shows a warning that the app cannot be opened, go to
> **System Settings → Privacy & Security** and click **Open Anyway**.

## Make targets

| Command | Description |
|---|---|
| `make install` | Compile `LaySwitch.app` → Stop running instance → copy to `/Applications` → launch |
| `make build` | Compile `LaySwitch.app` in the project root (no install) |
| `make uninstall` | Stop → remove login item → delete app and saved layouts |
| `make logs` | Stream live logs from the running app |

## Launch at Login

Click the **LS** menu bar icon → **Launch at Login**. A checkmark confirms it is enabled.
This writes a LaunchAgent plist to `~/Library/LaunchAgents/com.layswitch.app.plist` — no elevated privileges required.

## Uninstall

```bash
make uninstall
```

Stops the app, removes the login item if enabled, deletes `/Applications/LaySwitch.app`, and removes saved layout mappings.

## How It Works

LaySwitch listens for two `NSWorkspace` notifications:

1. **`didDeactivateApplication`** — when an app loses focus, the current input source is saved for it.
2. **`didActivateApplication`** — when an app gains focus, its saved layout is restored after a short delay (100 ms by default).

The delay lets Space-transition animations fully complete before the layout switch is applied, which prevents interference from transient system layout events during the animation.

If the user switches away before the delay elapses, the pending restore is cancelled and no layout is saved for that brief visit.

Input source switching uses the Carbon **Text Input Services** (TIS) API — the only public API on macOS for programmatic keyboard layout switching.

## Project Structure

```
LaySwitch/
├── App/
│   ├── AppDelegate.swift         # @main entry point, owns all components
│   └── Info.plist                # LSUIElement = YES (no Dock icon)
├── InputSource/
│   └── InputSourceManager.swift  # TIS API wrapper
├── Focus/
│   └── AppFocusMonitor.swift     # save on deactivation, restore on activation
├── Storage/
│   └── LayoutStore.swift         # JSON persistence
├── LoginItem/
│   └── LoginItemManager.swift    # LaunchAgent plist management
└── UI/
    └── StatusBarController.swift # menu bar item and menu

Assets/
└── LaySwitch.jpeg   # source image — icns is generated at build time

Makefile             # build / install / logs
build.sh             # build script invoked by make build
Package.swift        # Swift Package Manager manifest
```

## Debugging

```bash
make logs
```

Or filter by subsystem in **Console.app**: `com.layswitch.app`.

Current saved mappings:

```bash
jq . ~/Library/Application\ Support/LaySwitch/layouts.json
```
