# Scene stock texture placeholders

This bundle contains only MyWallpaperX placeholder PNG files and a clean-room catalog of stock texture path identities observed in the user's legal Wallpaper Engine 2.8.42 installation.

It does not contain Wallpaper Engine TEX files, TEX metadata, shaders, materials, or copied pixels. Every PNG currently has the same bytes as the MyWallpaperX 16x16 app icon. Particle material slot 0 resolves exact stock identities to these PNGs after checking sample-local resources first; other material semantics are not implied.

The official `.tex` path is retained in `texture-catalog.json`; the project counterpart uses the same `assets/...` hierarchy and filename stem with a `.png` extension so placeholder bytes cannot be mistaken for a valid TEX container.
