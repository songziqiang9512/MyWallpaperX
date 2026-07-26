# Scene stock texture placeholders

This bundle contains only MyWallpaperX placeholder PNG files and a clean-room catalog of stock texture path identities observed in the user's legal Wallpaper Engine 2.8.42 installation.

It does not contain Wallpaper Engine TEX files, TEX metadata, shaders, materials, or copied pixels. Every PNG currently has the same bytes as the MyWallpaperX 16x16 app icon and is not consumed by the Scene runtime.

The official `.tex` path is retained in `texture-catalog.json`; the project counterpart uses the same `assets/...` hierarchy and filename stem with a `.png` extension so placeholder bytes cannot be mistaken for a valid TEX container.
