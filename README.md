# LaySwitch

[![Tests](https://github.com/evsigneevk/LaySwitch/actions/workflows/tests.yml/badge.svg)](https://github.com/evsigneevk/LaySwitch/actions/workflows/tests.yml)
[![License: GPL v3](https://img.shields.io/badge/license-GPLv3-blue)](LICENSE)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-brightgreen)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6.0-orange)](https://www.swift.org)

A lightweight macOS menu bar utility that automatically remembers and restores the keyboard input source (layout) for each application. When you switch to an app, LaySwitch instantly restores the layout you were using there last — no manual switching required.


---

## Features

- Runs silently in the menu bar — no Dock icon, no windows
- Remembers one layout per application
- Restores layout instantly on app focus
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

**3. Build:**

```bash
bash build.sh
```

This compiles the Swift sources and produces `LaySwitch.app` in the project root.

**4. Install:**

```bash
cp -r LaySwitch.app /Applications/
open /Applications/LaySwitch.app
```

The app appears as **LS** in your menu bar. That's it — it starts working immediately.

> **First launch / Gatekeeper:** If macOS shows a warning that the app cannot be opened, go to
> **System Settings → Privacy & Security** and click **Open Anyway**.

## Launch at Login

Click the **LS** menu bar icon → **Launch at Login**. A checkmark confirms it is enabled.
This writes a LaunchAgent plist to `~/Library/LaunchAgents/com.layswitch.app.plist` — no elevated privileges required.

## Uninstall

```bash
# Remove the app
rm -rf /Applications/LaySwitch.app

# Remove launch at login entry (if enabled)
launchctl bootout "gui/$(id -u)/com.layswitch.app" 2>/dev/null || true
rm -f ~/Library/LaunchAgents/com.layswitch.app.plist

# Remove saved layout mappings
rm -rf ~/Library/Application\ Support/LaySwitch
```

## How It Works

LaySwitch listens for `NSWorkspace.didActivateApplicationNotification`. On every app switch:

1. **Save** — reads the current input source and stores it under the previous app's bundle ID.
2. **Restore** — looks up the newly active app's bundle ID and switches to its saved layout.

Input source switching uses the Carbon **Text Input Services** (TIS) API — the only public API on macOS for programmatic keyboard layout switching.

## Project Structure

```
LaySwitch/
├── App/
│   ├── AppDelegate.swift       # @main entry point, owns all components
│   └── Info.plist              # LSUIElement = YES (no Dock icon)
├── InputSource/
│   └── InputSourceManager.swift  # TIS API wrapper
├── Focus/
│   └── AppFocusMonitor.swift     # NSWorkspace notification observer
├── Storage/
│   └── LayoutStore.swift         # JSON persistence
├── LoginItem/
│   └── LoginItemManager.swift    # LaunchAgent plist management
└── UI/
    └── StatusBarController.swift # menu bar item and menu

LaySwitchTests/
├── LayoutStoreTests.swift
└── AppFocusMonitorTests.swift

Assets/
└── LaySwitch.jpeg   # source image — icns is generated at build time

Package.swift        # Swift Package Manager manifest (tests)
build.sh             # build script — produces LaySwitch.app (no Xcode required)
```

## Running Tests

Tests use Swift Package Manager and run on any machine with Xcode installed:

```bash
swift test
```

CI runs automatically on every pull request via GitHub Actions (`swift test --enable-code-coverage`).

## Debugging

Layout switching is logged via `os_log`. View live in **Console.app** — filter by
subsystem `com.layswitch.app`.

Or from the terminal:

```bash
log stream --predicate 'subsystem == "com.layswitch.app"' --level info
```

Current saved mappings:

```bash
cat ~/Library/Application\ Support/LaySwitch/layouts.json | python3 -m json.tool
```

With `jq`:

```bash
jq . ~/Library/Application\ Support/LaySwitch/layouts.json
```
