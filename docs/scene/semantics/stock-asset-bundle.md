# Wallpaper Engine stock 播放资产包

> 事实快照：Wallpaper Engine `2.8.42` / Steam build `23967692`
>
> 路径清单来源：Wallpaper Engine `2.8.42` 的历史静态取证
>
> 项目目录：[SceneStockAssets.bundle](../../../MyWallpaperX/Resources/SceneStockAssets.bundle)

## 1. 目的与边界

`SceneStockAssets.bundle` 按官方 `assets/**` 的原相对路径、文件名和扩展名保存 Scene 所需的项目自有资源。素材原位落地，不新增平行命名、目录或 runtime 别名；包可以同时包含播放、编辑器、preview、example、thumbnail 和 source-only 资源。

bundle 不设目录级的文件清单、文件数量或 preview 排除门禁。逐资产的官方 codec/尺寸/通道/mip/atlas/像素 parity 未证明，也不表示所有 consumer 已实现。

本包不含 catalog。运行时直接按 `SceneStockAssets.bundle/assets/...` 官方相对路径查文件；各 consumer 的定向功能测试负责验证其实际使用的资源。

## 2. 运行与替换合同

当前真实 consumer 只有两组：Particle material slot 0 会在样本本地资源缺失后直接读取 `assets/materials/particle/**/*.tex`；文字解析会在壁纸包内字体缺失后直接读取 `assets/fonts/<作者文件名>`。两条路径均不依赖 catalog 或替代文件名映射。

其余 Effect、material、shader、sidecar、LUT、normal、多纹理、SceneScript 和 zcompat 文件已经具备固定物理身份，但 consumer 仍按各专项能力表推进。后续实现必须直接复用本包现有路径，并以“包内现有文件被对应 consumer 实际读取”为资源链验收条件；不得再创建另一个 stock 资产包或另一套命名。

占位生成器 `script/generate_scene_stock_asset_bundle.py` 与历史集合门 `script/tests/test_scene_stock_asset_bundle.py` 已随真实素材落地退役（`47e2fa8`）。bundle 内容不再有目录级门禁，由各 consumer 门验证运行时实际读取的资源。

## 3. 证据等级

- A 级：历史 2.8.42 静态取证记录了 3,113 个相对路径、扩展名及目录归属。
- 项目事实：Particle slot 0 可直接解码并上传包内 `particle/debris/debris1` 的 1024x128 R8 spritesheet；字体 consumer 可由 CoreText 打开官方命名字体。Particle slot 0 与字体 consumer 已进入 runtime。
- 未证明：未接入文件的官方加载时机、JSON/shader/sidecar 语义、TEX codec/尺寸/通道/mip/atlas/颜色空间和像素等价；这些仍需自有 fixture 与 Windows golden。
