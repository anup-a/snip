# Snip — Mac App Store listing

App record created 2026-09-29: **Snip: Screenshot & Markup**, Apple ID 6817088290. "Snip" alone was already taken. The app still shows as Snip on the Mac. Build 1.0.0 (1) uploaded and attached. Listing, price, screenshots (the v2 set from `Marketing/appstore-v2/`, 5 shots, rendered by `Marketing/html/render.sh`), and privacy label are filled in. Submitted for review 2026-09-29 (state WAITING_FOR_REVIEW), release type MANUAL. App Review contact: Anup Aglawe, +971 586614185.

## Name

**Snip**

Tagline for the repo only: "Lark-style screenshots for Mac. Press ⌘⇧A."

Do not use Lark, Feishu, or ByteDance in the App Store name, subtitle, keywords, description, or screenshots. Lark is ByteDance's product. The store listing below does not use it.

### Name collision

Check App Store Connect before paying for the record.

- Mac App Store already lists **Snip: Batchcrop Scanned Photos** (id 1538901870), a scan-cropping app. A short name of Snip may be rejected as too close.
- An open-source macOS screenshot app also named **Snip** (rixinhahaha/snip, Product Hunt March 2026) does the same job: capture, annotate, copy. It may not be on the store, but the name is in use.

If Connect rejects the name, pick a longer unique name and keep the menu bar label short.

## Metadata

| Field | Value |
| --- | --- |
| Bundle ID | `com.anup.snip` |
| SKU | `snip-mac` |
| Version | 1.0.0 (1) |
| Category | Productivity |
| Secondary | Graphics & Design |
| Price | Free. Not applied in App Store Connect yet, because the app record does not exist. |
| Support URL | https://creatica.app/apps/snip/support |
| Privacy Policy URL | https://creatica.app/apps/snip/privacy |
| Age rating | 4+ |
| Copyright | 2026 Anup Aglawe |

**Subtitle** (30 characters): `Snap, annotate, and pin`

**Promotional text** (170). App Store Connect rejects ⌘ and ⇧, so spell out the keys:

Take a screenshot from anywhere with Command-Shift-A. Snap a window or drag a region, mark it up, hide private details, and copy or pin it. Everything stays on your Mac.

**Description:**

Snip is a menu bar screenshot tool for Mac. Press Command-Shift-A, click a window, or drag any region. The screen freezes so nothing moves while you frame the shot.

Mark it up before you share. Draw rectangles, ellipses, arrows, and freehand ink. Drop numbered steps and text. Pick a color and a stroke size. Hold Shift to keep shapes even.

Hide what should stay private. Brush a mosaic over passwords, emails, and account numbers, then copy the rest.

Pin a snip on top of your work, save a PNG, or copy it with Enter. Extract the words in a shot with on-device text recognition. Nothing is uploaded.

Snip only captures when you ask. It needs Screen Recording permission, which macOS requires for every screenshot app, and it never records video.

**Keywords** (100 characters, commas count):

`screenshot,annotate,markup,capture,pin,mosaic,clipboard,menu bar`

**What's New:**

First release. Snap a window or a region, mark it up, mosaic private details, copy, save, or pin.

**Review notes:**

Menu bar app (no Dock icon). First launch opens "Set Up Snip" and links to System Settings, Privacy & Security, Screen & System Audio Recording. Hotkey is Command-Shift-A. No account. No network. OCR uses the on-device Vision framework.

## Screenshots

All four are 2880×1800, an accepted Mac size. Upload in this order:

1. `Marketing/appstore/1-snap.png` — Snap any window. Press ⌘⇧A, then click. Or drag any area.
2. `Marketing/appstore/2-markup.png` — Mark it up in seconds. Boxes, arrows, numbers, and text.
3. `Marketing/appstore/3-private.png` — Hide what's private. Mosaic passwords and emails before you share.
4. `Marketing/appstore/4-pin.png` — Pin it on top. Keep a snip floating while you work.

Captions are burned in. Raw overlay renders are in `Marketing/raw/`. After `./build.sh`, rebuild with `Marketing/render-raw.sh` and then `Marketing/compose.sh`.

## Privacy

Data Not Collected. Suggested privacy policy text, still needs a public URL:

> Snip does not collect, store, or transmit personal data. Screenshots stay on your Mac. Text recognition runs on device. Snip uses the Screen Recording permission only when you take a screenshot, and it does not record video.

Support URL is also required. Neither URL exists yet.

Nutrition label answers:

- Contact info, location, identifiers, usage data, diagnostics: not collected
- Screen contents: processed on device for the capture you asked for, and for text recognition if you use it. Not linked to identity. Not used for tracking.

## Store build

`./archive.sh` writes `build/Snip.app` and `build/Snip.pkg` is the installer package. The app is sandboxed, hardened, and signed with Apple Distribution. The package is signed with the Mac Installer certificate. `altool --validate-app` stops with "create this app in App Store Connect first" until the Mac app record exists.

The copy in `/Applications` is a development-signed sandbox build so it can launch on this Mac. App Store signatures are rejected by Gatekeeper until Apple installs them. A sandboxed capture was exercised here: the screen froze and the magnifier appeared.

Bundle ID `com.anup.snip` is registered (App Store Connect id `58TSBJF522`). The Mac App Store profile is `Snip Mac App Store`.

## Still required before upload

1. Create the Mac app in App Store Connect. The API key on this Mac can update apps but cannot create them, and the browser session is not signed in. Name Snip, bundle `com.anup.snip`, SKU `snip-mac`, primary locale en-US.
2. If the name is rejected, lengthen the store name and say so. Then upload `build/Snip.pkg` with `altool --upload-app`.
3. Set the price to free, paste the support and privacy URLs, and paste the listing from this file. Release type stays manual.

Not in this version, and not promised on the store page: scrolling capture, and snapping to buttons or panels inside a window.
