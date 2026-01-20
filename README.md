# Meteoradar (iOS)

Meteoradar is a SwiftUI iOS rain radar app built around one idea: **be simple and extremely fast**, especially on slow/unstable mobile networks.

The app was born from combining my passion for meteorology and programming. After switching to iOS, I also missed a sufficiently simple and fast radar app.

Simplicity and especially **speed became the priority of the whole app** and I dare say it is the fastest radar app ever. Thanks to my own server, **the images are up to 70% smaller than other apps and therefore download much faster on slow internet.**

**There will never be ads in the app and the basic features will always be free.** It is possible that some advanced features will be paid in the future because the server operation costs money.

<div align="center">
  <img src="https://radar.danielsuchy.cz/assets/app1.png" alt="App Screenshot 1" width="45%">
  <img src="https://radar.danielsuchy.cz/assets/app2.png" alt="App Screenshot 2" width="45%">
</div>

## Technical highlights (why it's fast)

- **Tiny radar overlays**: radar frames are served as compact PNG overlays, with multistep compression for even smaller size.
- **HTTP/3-capable fetching**: uses HTTP3 aiming for lower latency and better behavior on bad networks.
- **Image caching**: images are stored locally after downloading, so you never download the same image twice.
- **Priority-based loading**: images are loaded in priority order, so the most important images are loaded first. (newest observed frames -> oldest observed frames -> forecast frames)
- **No external dependencies**: pure Swift/Apple frameworks (no third‑party SDKs).
- **No ads**: the app will never show ads.

## What it does

- **Animated radar playback**: recent observed frames rendered as a map overlay
- **Forecast frames**: short horizon forecast sequence
- **Map + location**: optional "When In Use" location to show your position on the map
- **Settings**: image quality (1x/2x), overlay opacity, map appearance, frame interval

## Requirements

- **macOS** with **Xcode**
- **iOS 16.6+** deployment target (see Xcode project settings)
- Network access to fetch radar overlays from `radar.danielsuchy.cz`

## Getting started

1. Open the Xcode project: `Meteoradar/Meteoradar.xcodeproj`
2. Select the **Meteoradar** scheme and a simulator/device.
3. Press **Run** (⌘R).

## License

This project is licensed under the **PolyForm Noncommercial License 1.0.0**. See `Meteoradar/LICENSE.md`.
