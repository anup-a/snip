# Snip

A Lark/Feishu-style screenshot tool for macOS. Lives in the menu bar; press **⌃⇧A** anywhere.

## Features

- Freezes all displays, then dims everything except the window under the cursor (click to grab that window, or drag any region)
- Magnifier with pixel coordinates and color; press **C** to copy the hex
- Resize with 8 handles, drag to move, arrow keys nudge (Shift = 10px)
- Annotate: rectangle, ellipse, arrow, pen, mosaic, text, numbered markers; 3 sizes, 6 colors; Shift constrains shapes/arrow angle
- Undo (⌘Z), extract text via on-device OCR, pin to screen, save PNG (⌘S)
- **Enter / double-click / ⌘C** copies to clipboard, **Esc** cancels, right-click resets the selection

Pinned images: drag to move, scroll to zoom, right-click for Copy/Save/Close, double-click or Esc to close.

## Build

```sh
./build.sh            # builds build/Snip.app
./build.sh --install  # installs to /Applications and launches
```

Requires macOS 14+ and Screen Recording permission (System Settings → Privacy & Security → Screen & System Audio Recording). The app is signed with your Apple Development identity so the grant survives rebuilds.

Scripts can trigger a capture by posting the distributed notification `com.anup.snip.capture`.
