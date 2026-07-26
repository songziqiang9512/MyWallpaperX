# Wallpaper Engine stock 纹理身份目录

> 事实快照：Wallpaper Engine `2.8.42` / Steam build `23967692`
>
> 官方来源：本机正版安装副本 `/Users/songziqiang/Downloads/wallpaper_engine/assets`
>
> 项目目录：[SceneStockTextures.bundle](../../../MyWallpaperX/Resources/SceneStockTextures.bundle)

## 1. 目的与边界

本目录只建立官方随包 `.tex` 的相对路径和文件身份，方便逐项制作、替换和比较项目自有素材。官方 `.tex`、`.tex-json`、shader、JSON 和像素 payload 均未复制进仓库。

项目 counterpart 保留 `assets/...` 目录与文件名 stem，但扩展名从 `.tex` 改为 `.png`。不能把 PNG 改名成 `.tex`：那会制造无法解析的假容器。当前 311 个 PNG 都是同一张 16x16 项目图标占位。Particle material slot 0 已在样本本地资源查找失败后按 catalog 精确 identity 解析 bundle PNG；这只证明资源路由和 GPU 可加载，不证明占位图具备官方像素、尺寸、通道或 atlas 语义。

## 2. 官方静态事实

| 范围 | `.tex` 数量 | 说明 |
|---|---:|---|
| `assets/materials` | 229 | 包含 particle、LUT、gradient、util、cookie、editor、pattern 与 model editor 纹理 |
| `assets/effects` | 74 | stock Effect 的 preview、mask 与 preview-local effect texture；不是 74 个通用运行时 built-in |
| `assets/presets` | 6 | preset preview 内的纹理 |
| `assets/scenes` | 2 | 官方粒子能力 preview 场景内的纹理 |
| **合计** | **311** | 只统计 `.tex` 容器；另有 PNG/TGA/GIF 等编辑器或源素材，不混入本目录 |

`assets/materials/particle` 单独包含 164 个 `.tex`，是当前 `particle/...` built-in identity 的直接官方路径集合。runtime 接受 `particle/...`、`materials/particle/...`、`assets/materials/particle/...` 及其 `.tex`/`.png` 精确别名，统一落到 catalog 声明的 PNG；不做 basename 或相似名称猜测。原有 22-key 程序纹理只在 stock bundle 不可用时保留为兼容回退。

当前执行边界只覆盖 Particle material 的首纹理槽。catalog 中的 LUT、normal、多纹理、Effect preview、preset 和 scene preview 虽可由 resolver 精确定位，但没有对应 material/effect consumer 时不会被自动绑定；不得据此提升这些系统的执行等级。PNG 也不携带官方 `.tex-json` 的 mip、sprite frame、色彩空间或 3D texture metadata，序列帧当前会退化为单张静态图。

311 个 `.tex` 中 272 个存在同路径 `.tex-json` sidecar。catalog 只记录 sidecar 是否存在，不复制 sidecar 内容。每项同时记录官方文件大小和 SHA-256，供本机合法安装更新后判断身份是否变化；hash 不代表获得了再分发 payload 的权利。

## 3. 目录合同

权威清单是 bundle 根的 `texture-catalog.json`：

```text
official: assets/materials/particle/fire/fire1.tex
project:  assets/materials/particle/fire/fire1.png
```

生成入口：

```bash
python3 script/generate_scene_stock_texture_catalog.py \
  --source-root /Users/songziqiang/Downloads/wallpaper_engine \
  --placeholder MyWallpaperX/Assets.xcassets/AppIcon.appiconset/Icon-iOS-Dark-16x16@1x.png \
  --output /tmp/SceneStockTextures.bundle \
  --steam-build-id 23967692
```

脚本只接受不存在的输出目录，避免覆盖人工制作的素材。Wallpaper Engine 更新后，应生成到临时目录，先比较 catalog，再由人工决定哪些项目资产需要替换。

## 4. 证据等级

- A 级：版本文件、`.tex` 相对路径、文件大小、hash、sidecar 是否存在，来自本机正版安装的只读静态检查。
- 项目事实：PNG placeholder 和 catalog 在 app bundle 内可达；Particle slot 0 的 exact stock identity 已经 resolver、asset graph、CGImageSource 与 Metal upload 接入，样本本地文件优先。
- 未证明：官方运行时实际加载频率、采样参数、颜色空间、sprite frame 语义和像素等价；这些仍需自有 fixture 与 Windows golden。
