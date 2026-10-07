---
title: "Lark/Feishu style screenshots for Mac"
date: 2026-10-07
author: Anup Aglawe
---

# Lark/Feishu style screenshots for Mac

If you've used Lark or Feishu (飞书) at work, you probably hit ⌘⇧A more times a day than you'd guess. Someone asks where a bug shows up. You press the shortcut, box the problem, draw an arrow, press Enter, and paste. Ten seconds, maybe less.

Then you open a Mac where Lark isn't part of your day, and that flow is gone. You press ⌘⇧4, take the shot, open it somewhere else to annotate, export it, and drag it into the chat. It works. It just feels slow once you've had the other thing.

I missed it enough that I built a small Mac app to get it back. It's called Snip.

## What the Lark flow actually feels like

The part people remember is the freeze. You press the hotkey and the screen stops. Menus, tooltips, and hover states stay exactly where they were, so you can capture things that disappear the moment you move the mouse.

Then:

- The window under your cursor lights up. Click it to grab the whole window, or drag to select any region.
- A toolbar shows up right next to the selection. You draw boxes, arrows, and text on top of the frozen screen, without opening another app.
- If there's an email address, a token, or a customer name in the shot, you brush a mosaic over it.
- You press Enter. It's on your clipboard. You paste it into chat, a doc, or a ticket.

There's no file saved to your Desktop, no editor window, no export step. Capture and markup are one action. For engineers filing bugs and PMs giving feedback on designs, that adds up quickly.

## Why the usual Mac options don't quite fit

macOS has a good built-in screenshot tool. ⌘⇧4 and ⌘⇧5 are fast and reliable. But markup happens after the capture, in the floating thumbnail or in Preview, as a separate step. There's no freeze-then-annotate-in-place flow, and no quick way to blur private details before sharing.

There are also excellent third party tools. CleanShot X is the one most people mention, and it's well made. It's also paid, and it does a lot more than this one workflow. If what you want is exactly the Lark muscle memory, a full-featured capture suite can feel like more app than you need.

So the gap I kept running into was narrow: one hotkey, frozen screen, mark it up right there, hide the private bits, Enter to copy. Free, and native.

## What Snip does

Snip is a native macOS menu bar app. It sits in your menu bar and waits for ⌘⇧A.

**Freeze and select.** Press ⌘⇧A and every display freezes. The window under your cursor is highlighted. Click to snap it, or drag any region. A magnifier shows pixel coordinates and the color under the cursor (press C to copy the hex value). You can resize the selection with handles and nudge it with the arrow keys, 1 px at a time or 10 px with Shift.

**Mark it up.** Rectangles, ellipses, arrows, freehand ink, text, and numbered steps. Six colors, three sizes. Hold Shift for even shapes and straight arrows. ⌘Z undoes.

**Hide what's private.** Brush a mosaic over passwords, emails, and account numbers before you share.

**Copy, save, or pin.** Enter (or ⌘C, or a double-click) copies to the clipboard and finishes. ⌘S saves a PNG. You can also pin a snip so it floats above your other windows while you code or write. Drag to move it, scroll to zoom.

**Extract text on device.** Snip can copy the text in any snip using OCR. Recognition runs on your Mac with Apple's Vision framework.

**No network, no account.** Snip makes no network requests. There's no sign-in, no analytics, and no uploads. Your screenshots and any recognized text stay on your Mac.

**Free and open source.** Snip is MIT licensed. The code is on GitHub, and it's written in Swift. No Electron.

A couple of things it doesn't do yet: scrolling capture, and snapping to individual buttons or panels inside a window. Right now it snaps to whole windows. Both are on the list.

## How to try it

Snip is available now from GitHub: [github.com/anup-a/snip](https://github.com/anup-a/snip)

1. Go to the [latest release](https://github.com/anup-a/snip/releases/latest) and download the .dmg. It's a universal build for Apple silicon and Intel, signed and notarized, and needs macOS 14 or later.
2. Open it and drag Snip to Applications.
3. On first launch, Snip asks for Screen Recording permission, like every screenshot app on macOS. A setup window links you to the right place in System Settings and offers a relaunch once access is granted.
4. Press ⌘⇧A.

If you'd rather build it yourself, the README has the steps. Clone the repo and run `./build.sh`.

Snip has also been submitted to the Mac App Store as "Snip: Screenshot & Markup." It's in review right now, so it isn't live there yet. I'll add the link to the README once it's approved.

## A quick note on names

Snip is an independent project. It is not affiliated with, endorsed by, or connected to ByteDance, Lark, or Feishu. "Lark-style" just describes the workflow that inspired it.

## That's it

I built Snip because I wanted one specific thing back on my Mac. If you've had ⌘⇧A in your fingers for years, it might be useful to you too.

Try it, and if something feels off compared to the flow you remember, open an issue on GitHub. Issues and pull requests are welcome.
