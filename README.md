<p align="center">
  <img src="Icons/renders/2-scissors.png" width="128" alt="Snip icon">
</p>

<h1 align="center">Snip</h1>

<p align="center">
  <b>Lark-style screenshots for Mac.</b><br>
  Press <kbd>⌘</kbd> <kbd>⇧</kbd> <kbd>A</kbd>. Snap a window or drag a region, mark it up, hide what's private, and copy or pin it.
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5.10-F05138?logo=swift&logoColor=white">
  <img alt="No network" src="https://img.shields.io/badge/network-none-2ea44f">
  <img alt="Sandboxed" src="https://img.shields.io/badge/App%20Sandbox-on-0a84ff">
</p>

<p align="center">
  <img src="Marketing/appstore-v2/1-snap.png" alt="Snap any window or region" width="880">
</p>

## Why

If you've used the screenshot tool in Lark, you know the flow: one hotkey, the screen freezes, you click the window you want, draw a box and an arrow, and hit Enter. It's on your clipboard before you've thought about it.

Snip brings that flow to the Mac as a tiny native menu bar app. There's no Electron, no account, and no uploads.

## Features

<table>
  <tr>
    <td width="50%"><img src="Marketing/appstore-v2/2-markup.png" alt="Mark it up"></td>
    <td width="50%"><img src="Marketing/appstore-v2/3-private.png" alt="Hide what's private"></td>
  </tr>
  <tr>
    <td><b>Mark it up.</b> Rectangles, ellipses, arrows, freehand ink, text, and numbered steps. Six colors, three sizes. Hold Shift to keep shapes even and arrows straight.</td>
    <td><b>Hide what's private.</b> Brush a mosaic over passwords, emails, and account numbers before you share.</td>
  </tr>
  <tr>
    <td width="50%"><img src="Marketing/appstore-v2/4-pin.png" alt="Pin it on top"></td>
    <td width="50%"><img src="Marketing/appstore-v2/5-on-device.png" alt="Everything stays on your Mac"></td>
  </tr>
  <tr>
    <td><b>Pin it on top.</b> Float a snip above your other windows while you write, code, or compare. Drag to move, scroll to zoom.</td>
    <td><b>Stays on your Mac.</b> Text recognition runs on device with Apple's Vision framework. Snip makes no network requests.</td>
  </tr>
</table>

Also included:

- **Smart window snapping.** Every display freezes and the window under the cursor lights up. Click to grab it, or drag any region.
- **Pixel-exact framing.** A magnifier shows coordinates and color. Press <kbd>C</kbd> to copy the hex value.
- **Adjustable selection.** Eight resize handles, drag to move, and arrow keys to nudge by 1 px (10 px with Shift).
- **Extract text.** On-device OCR copies the words in any snip.
- **Save or copy.** Save a PNG with <kbd>⌘</kbd> <kbd>S</kbd>, or copy with <kbd>Enter</kbd>.

## Keyboard shortcuts

| While capturing | |
| --- | --- |
| <kbd>⌘</kbd> <kbd>⇧</kbd> <kbd>A</kbd> | Start a capture from anywhere |
| Click | Snap the highlighted window |
| Drag | Select a region |
| <kbd>C</kbd> | Copy the color under the cursor |
| <kbd>←</kbd> <kbd>→</kbd> <kbd>↑</kbd> <kbd>↓</kbd> | Nudge the selection (hold <kbd>⇧</kbd> for 10 px) |
| <kbd>Shift</kbd> while drawing | Even shapes, straight arrows |
| <kbd>⌘</kbd> <kbd>Z</kbd> | Undo |
| <kbd>Enter</kbd>, <kbd>⌘</kbd> <kbd>C</kbd>, or double-click | Copy to clipboard and finish |
| <kbd>⌘</kbd> <kbd>S</kbd> | Save as PNG |
| Right-click | Reset the selection |
| <kbd>Esc</kbd> | Cancel |

| Pinned snips | |
| --- | --- |
| Drag | Move |
| Scroll | Zoom |
| <kbd>⌘</kbd> <kbd>C</kbd> / <kbd>⌘</kbd> <kbd>S</kbd> | Copy / Save |
| Right-click | Copy, Save, Close |
| Double-click or <kbd>Esc</kbd> | Close |

## Install

**Mac App Store:** submitted as *Snip: Screenshot & Markup*. The link will be added here once it's approved.

**Build from source** (requires macOS 14+ and Xcode or the Swift toolchain):

```sh
git clone https://github.com/anup-a/snip.git
cd snip
./build.sh            # builds build/Snip.app
./build.sh --install  # copies it to /Applications and launches it
```

`build.sh` signs with your Apple Development identity, so the Screen Recording permission survives rebuilds.

### First launch

Snip needs **Screen Recording** permission, like every screenshot app on macOS. On first launch a setup window links straight to *System Settings → Privacy & Security → Screen & System Audio Recording*, shows live when access is granted, and offers a one-click relaunch (macOS only applies the permission after a relaunch). You can reopen it any time from the menu bar with **Screen Recording Permission…**.

The menu bar item also has **Take Screenshot** and **Launch at Login**.

## Privacy

Snip captures only when you ask it to, and it never records video. Screenshots, annotations, and recognized text stay on your Mac. There's no analytics, no account, and no network access. The App Store build runs in the App Sandbox. See the [privacy policy](https://creatica.app/apps/snip/privacy).

## Automation

Scripts can start a capture by posting the distributed notification `com.anup.snip.capture`:

```swift
DistributedNotificationCenter.default().post(name: .init("com.anup.snip.capture"), object: nil)
```

## Project layout

```
Sources/Snip/
  AppDelegate.swift       menu bar item, hotkey, launch at login
  HotKey.swift            global ⌘⇧A registration
  ScreenCapturer.swift    freezes every display
  CaptureSession.swift    one capture from hotkey to output
  OverlayView.swift       selection, window snapping, magnifier, drawing
  Annotation.swift        shapes, mosaic, text, numbered markers, palette
  Toolbar.swift           tool, color, and size pickers
  Output.swift            clipboard, PNG save, OCR, toasts
  PinWindow.swift         floating pinned snips
  PermissionWindow.swift  guided Screen Recording setup
  DemoRenderer.swift      renders overlay states for marketing images
Marketing/
  html/                   App Store screenshots as HTML (render.sh)
  appstore-v2/            rendered 2880×1800 screenshots
  APP_STORE.md            store listing copy
archive.sh                sandboxed Mac App Store build
```

## Not yet

- Scrolling capture
- Snapping to individual buttons or panels inside a window (only whole windows for now)

Issues and pull requests are welcome.

---

<p align="center"><sub>Not affiliated with Lark or ByteDance. "Lark-style" describes the workflow that inspired Snip.</sub></p>
