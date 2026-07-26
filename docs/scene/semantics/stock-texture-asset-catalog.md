# Wallpaper Engine stock 纹理身份目录

> 事实快照：Wallpaper Engine `2.8.42` / Steam build `23967692`
>
> 官方来源：本机正版安装副本 `/Users/songziqiang/Downloads/wallpaper_engine/assets`
>
> 项目目录：[SceneStockTextures.bundle](../../../MyWallpaperX/Resources/SceneStockTextures.bundle)

## 1. 目的与边界

本目录建立官方随包 `.tex` 与 `.tex-json` 的相对路径和文件身份，方便逐项制作、替换和比较项目自有素材。官方 TEX/sidecar payload、shader、material JSON 和像素均未复制进仓库。

**资产库存状态：完整。** 对当前事实快照观察到的全部 stock 纹理相关文件，项目 counterpart 的 `assets/...` 目录、311 个 `.tex` 和 298 个 `.tex-json` 文件名与官方静态库存集合完全一致；没有待补的已知 TEX 或 sidecar 路径。这里的“完整”只表示文件身份和相对路径占位完整，不表示所有运行时 consumer、TEX metadata 或官方视觉语义已经兼容。

每个 TEX 是项目自建的合法 `TEXV0005/TEXI0001/TEXB0002` format-0 单 mip 容器，内嵌同一张 16x16 项目图标；每个 sidecar 是 `rgba8888`、`nomip=true` 的合法 JSON 占位。Particle material slot 0 已在样本本地资源查找失败后按 catalog 精确 identity 解析 bundle TEX；这只证明资源路由、TEX 解码和 GPU 上传，不证明占位容器具备对应官方文件的 codec、尺寸、通道、mip、atlas 或像素语义。

## 2. 官方静态事实

| 范围 | `.tex` 数量 | 说明 |
|---|---:|---|
| `assets/materials` | 229 | 包含 particle、LUT、gradient、util、cookie、editor、pattern 与 model editor 纹理 |
| `assets/effects` | 74 | stock Effect 的 preview、mask 与 preview-local effect texture；不是 74 个通用运行时 built-in |
| `assets/presets` | 6 | preset preview 内的纹理 |
| `assets/scenes` | 2 | 官方粒子能力 preview 场景内的纹理 |
| **合计** | **311** | 只统计 `.tex` 容器；另有 PNG/TGA/GIF 等编辑器或源素材，不混入本目录 |

`assets/materials/particle` 单独包含 164 个 `.tex`，是当前 `particle/...` built-in identity 的直接官方路径集合。runtime 接受 `particle/...`、`materials/particle/...`、`assets/materials/particle/...` 及其 `.tex`/无扩展名精确别名，统一落到 catalog 声明的 TEX；不做 basename 或相似名称猜测。原有 22-key 程序纹理只在 stock bundle 不可用时保留为兼容回退。

当前执行边界只覆盖 Particle material 的首纹理槽。catalog 中的 LUT、normal、多纹理、Effect preview、preset 和 scene preview 虽可由 resolver 精确定位，但没有对应 material/effect consumer 时不会被自动绑定；不得据此提升这些系统的执行等级。占位 TEX 只有单 mip，sidecar 当前也不进入 runtime；官方 sprite frame、色彩空间、3D texture 和逐资产格式语义仍未复现，序列帧当前会退化为单张静态图。

官方 `assets` 下共有 298 个 `.tex-json`，其中 272 个存在同路径 TEX，另 26 个在当前安装中没有对应 TEX。项目把 298 个路径全部建立为最小占位，并在 catalog 单独记录 `corresponding_texture_present`；当前 runtime 不读取 sidecar。每项同时记录官方文件大小和 SHA-256，供本机合法安装更新后判断身份是否变化；hash 不代表获得了再分发 payload 的权利。

## 3. 目录合同

权威清单是 bundle 根的 `texture-catalog.json`：

```text
official: assets/materials/particle/fire/fire1.tex
project:  assets/materials/particle/fire/fire1.tex
sidecar: assets/materials/particle/fire/fire1.tex-json
```

素材制作完成后必须直接替换 catalog 所列项目文件，保留相同相对路径、文件名和扩展名，不新增平行命名或替代目录。当前 Particle material slot 0 会从这些固定路径读取替换后的 TEX；sidecar 及 LUT、normal、多纹理、Effect preview、preset、scene preview 等 consumer 尚未接入。后续实现任一对应能力时，必须复用既有 catalog identity，并以“人工替换后的目标 TEX/sidecar 被该 consumer 实际读取”为资源链验收条件，不得再造另一套资产身份。

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

- A 级：版本文件、`.tex`/`.tex-json` 相对路径、文件大小和 hash，来自本机正版安装的只读静态检查。
- 项目事实：TEX/sidecar placeholder 和 catalog 在 app bundle 内可达；Particle slot 0 的 exact stock identity 已经 resolver、asset graph、TEX reader、CGImageSource 与 Metal upload 接入，样本本地文件优先。
- 未证明：官方运行时实际加载频率、采样参数、颜色空间、sprite frame 语义和像素等价；这些仍需自有 fixture 与 Windows golden。
