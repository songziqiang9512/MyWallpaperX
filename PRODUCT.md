# MyWallpaperX

A native macOS desktop wallpaper manager that keeps live wallpapers running behind
everything else: video, web pages, and Wallpaper Engine scenes.

## Product truth

- **Platform:** macOS 26 or later. Native Swift / AppKit throughout; Scene wallpapers
  render through Metal. No SwiftUI in the product UI.
- **Three engines, one app:** Video (local and downloaded video, looped with audio
  and a spectrum visualiser), Web (a dedicated host process renders the page),
  Scene (Wallpaper Engine projects, properties editable in-app).
- **One library, many sources:** local imports, Steam Workshop (signed-in Steam
  account, owned and subscribed items, search and filters, download queue),
  Pixabay, Wallhaven, and Pixiv. Playlists, favourites, multi-select, search and
  filtering work across all of them.
- **Lives with the system:** per-display playback, a system screen-saver extension,
  optional mirroring of the still frame to the macOS desktop picture, launch at
  login, resume at launch, menu-bar panel, and global playback shortcuts.
- **Built for long sessions:** auto-switch, pause-on-battery / idle / other-app
  focus / full screen, per-scene frame-rate cap, Scene HDR, and a spectrum
  visualiser driven by system audio.
- **Language:** English source with Chinese, German, French, and Russian
  translations; the app follows the system language.

## Audience and scene

A person who treats the desktop as a place they sit in for hours: designers,
developers, and anyone who keeps a screen on while working. They want motion and
atmosphere, but they also want their machine to stay quiet, cool, and predictable.
They are comfortable installing a helper and signing into Steam to get content;
they are not looking for a toy.

## Job

Find something worth looking at, put it on the desktop, and then forget about it —
without it costing battery, frame rate, or attention. When something goes wrong,
the app says which engine and which step, and leaves the previous wallpaper alone.

## What the help book must do

Answer "how do I…" questions for the capabilities above, quickly, for a reader who
already owns the app. It is a reference, not an advertisement: real menu names,
real limits, honest failure paths. It is shipped offline inside the app bundle and
opened from the Help menu, in the system language.

## Visual commitments

- The product's own materials: dark desktop light, metal, glass, deep space, and
  motion in the background. Nothing bright-white and clinical.
- The help book follows the system appearance rather than inventing its own world:
  macOS semantic surfaces, the system accent, native type, and light/dark variants
  that switch with the OS. It reads as documentation first.
- No invented features, prices, benchmarks, or customer names.

## Assumptions

PRODUCT.md was written during the help-book rebuild from repository code and docs,
not from a product-owner interview. Claims above were checked against modules,
settings strings, Info.plist, and the existing help pages; anything not verifiable
in the repository was left out.
