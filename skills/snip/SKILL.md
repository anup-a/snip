---
name: snip
description: Use on macOS to see or show what is on screen. Screenshot a window, app or region; capture a whole scrolling window as one long image (native and Electron apps, not only web pages); record a short video of a flow; mark up a screenshot with boxes, arrows, numbered steps, labels or blur to point the user at something; float an image on the user's screen; or read the text on screen with its positions.
---

# snip

`snip` is the command-line side of Snip, the Mac screenshot app. Every command prints the file it wrote; add `--json` for `{"path", "width", "height", …}`. `snip help` lists every flag. Files land in `$TMPDIR/snip/` unless you pass `-o`.

## Setting up

Check with `snip version`. If it is missing: `git clone https://github.com/anup-a/snip && ./snip/install-cli.sh` (installs to `~/.local/bin/snip`).

macOS asks for two permissions, granted to the app running `snip` (the user's terminal or agent app), not to snip:

- **Screen Recording** for `shot`, `scroll`, `record`, `ocr` and `windows`.
- **Accessibility** for `scroll`, which sends scroll-wheel events.

When `snip` says a permission is off, pass its message to the user: they flip the switch in System Settings and restart that app. You can't grant it yourself.

## Picking the target

`--app NAME` (the app's frontmost window), `--window ID` (from `snip windows`), `--region x,y,w,h` (screen points, top-left origin) or `--screen N`. With no target, `shot` and `record` take the main screen. `scroll` always needs a window or region.

## Coordinates

- Targets (`--region`, `--at`) are in **screen points**.
- Images are in **pixels**, usually 2× the points on a Retina display. `--json` reports `scale`.
- `snip ocr IMAGE --json` returns each line's `box` as `[x, y, w, h]` in that image's pixels, which is exactly what `snip mark` takes. So the way to point at something is: `ocr` to find it, then `mark` on the same image.

## Recipes

**Check how something looks.** `snip shot --app Safari`, then read the PNG.

**The whole scrolling window.** `snip scroll --app Slack` scrolls to the top, steps down to the end and stitches one image. It moves the pointer onto the window and brings the app forward, so tell the user before you run it. Use `--at x,y` (points inside the window) when the part that scrolls isn't in the middle, and `--max 20000` to cap the height in pixels. Ctrl-C or a timeout still saves what it has.

**A demo or bug-repro video.**
```
snip record --app "My App" --background      # returns at once with the .mp4 path
…drive the app…
snip stop                                    # finishes the file, prints path and seconds
```
For a fixed length: `snip record --app "My App" --seconds 10`.

**Point the user at something.** Marks apply in order, and `--color` changes the marks after it:
```
snip mark shot.png --box 120,340,400,90 --step 140,360 --color blue --arrow 900,700,540,420 --text 900,710,"This button is disabled" --blur 60,40,300,30
```
Steps number themselves 1, 2, 3. `--blur` pixelates (emails, tokens, faces). Without `-o` the result is `shot.marked.png` next to the input.

**Show the user directly.** `snip pin marked.png` floats the image above every window and returns at once. The user drags it, scrolls to zoom, and closes it with Esc or a double-click.

**Read the screen.** `snip ocr --app Notes` or `snip ocr shot.png`; add `--json` for boxes. The first text recognition after installing takes a few minutes while macOS prepares its model; later runs take about a second.
