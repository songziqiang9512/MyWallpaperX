# Scene stock texture placeholders

This bundle contains only MyWallpaperX-authored placeholder TEX files and a clean-room catalog of stock texture path identities observed in the user's legal Wallpaper Engine 2.8.42 installation.

It does not contain official Wallpaper Engine payloads, shaders, materials, or copied pixels. Every asset is a valid `TEXV0005` / `TEXI0001` / `TEXB0002` format-0 container embedding the same MyWallpaperX 16x16 app-icon PNG. Particle material slot 0 resolves exact stock identities to these TEX placeholders after checking sample-local resources first; other material semantics are not implied.

The `assets/...` relative paths and filenames match the observed inventory of 311 `.tex` and 298 `.tex-json` files exactly. Each sidecar is a self-authored minimal JSON placeholder and is not consumed by the current runtime. Container version, codec, dimensions, mip chain, sprite frames, channels, sidecar settings, and pixels may differ per official asset until replaced with independently authored material.
