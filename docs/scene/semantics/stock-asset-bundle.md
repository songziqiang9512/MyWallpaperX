# Wallpaper Engine stock 播放资产包

> 事实快照：Wallpaper Engine `2.8.42` / Steam build `23967692`
>
> 路径清单来源：Wallpaper Engine `2.8.42` 的历史静态取证
>
> 项目目录：[SceneStockAssets.bundle](../../../MyWallpaperX/Resources/SceneStockAssets.bundle)

## 1. 目的与边界

`SceneStockAssets.bundle` 一次性建立官方 `assets/**` 中所有播放候选资产的原相对路径、文件名和扩展名。素材已按这些路径原位落地，不新增平行命名、目录或 runtime 别名。编辑器 preset、preview、example、thumbnail 与 source-only 文件不进入 App。

**播放资产路径状态：完整；payload 已为真实素材。** 官方目录共有 3,113 个文件；保守播放分类纳入 919 项并建立物理文件，明确排除 2,194 项编辑器资产。“完整”只表示当前官方版本的播放候选路径与 payload 均已落地；逐资产的官方 codec/尺寸/通道/mip/atlas/像素 parity 未证明，也不表示所有 consumer 已实现。

本包不含 catalog。运行时直接按 `SceneStockAssets.bundle/assets/...` 官方相对路径查文件；播放候选目录清单是当前资源合同，`.tex` 路径由 [test_scene_stock_texture_resolver.py](../../../script/tests/test_scene_stock_texture_resolver.py) 覆盖解析。

## 2. 纳入集合

| 类型 | 数量 | payload 状态 |
|---|---:|---|
| `.tex` | 223 | 真实 TEX 素材：`TEXV0005/TEXI0001` 头接 `TEXB0001`–`TEXB0004` 容器，格式（ARGB8888/RG88/R8/DXT）、尺寸与 mip 链逐资产各异，含非方形与序列帧 spritesheet |
| `.tex-json` | 198 | 195 项携带真实 metadata（`format`/`clampuvs`/`nonpoweroftwo`/`spritesheetsequences` 等）；`util/noflow`、`waterflowphase`、`waterripplenormal` 3 项仍是最小占位；runtime 均不解析，仅作 dependency 存在性检查 |
| `.json` | 208 | 真实 effect/material/model/shader declaration 与 zcompat 定义 |
| `.vert` / `.frag` / `.geom` / `.h` | 268 | 真实 shader 源码（含 COMBO 声明与 include）；命中后仍允许 planner/compiler 按未实现或无入口失败关闭 |
| `.js` | 4 | 真实 SceneScript 基础模块源码；当前 runtime 不执行 |
| `.png` | 3 | `refractnormal`、`waterflowphase`、`waterripplenormal` dependency 的真实图像 payload |
| `.ttf` / `.otf` | 15 | 8 个原版与 7 个替代字体，均按官方物理文件名组织 |
| **合计** | **919** | — |

223 个 TEX 中，`assets/materials/particle` 保持全部 164 项，是 `particle/...` built-in identity 的直接路径集合。另有 LUT 28、gradient 16、util 9、cookie 4、pattern 2；`materials/editor` 和 `materials/models/editor` 的 6 个 TEX 明确排除。

15 个字体全部位于 `assets/fonts/<官方文件名>`。例如 Poppins Medium payload 物理保存为 `Atami-Regular.otf`，Permanent Marker 分别复制为 `summer85.ttf` 与 `Lazer84.ttf`，Segment7 Standard 另复制为 `CursedTimerUlil-Aznm.ttf`。字体解析器直接读取作者请求的官方路径；替代字体仍报 `stockSubstituted`。

## 3. 编辑器排除集合

| 排除原因 | 数量 | 边界 |
|---|---:|---|
| `presets/**` | 1,058 | 编辑器插入 preset 与其预览/编译产物 |
| preview 路径或 `_preview.gif` | 831 | Effect/particle/preset UI 预览 |
| `scenes/**` | 244 | particle/model/GIF/video 等编辑器能力预览场景 |
| editor 路径或 `editor*` 文件 | 42 | editor material、model、shader 与工具资源 |
| 与 TEX 同 stem 的 PNG/TGA/GIF | 8 | 编辑器编译源；播放端保留对应 TEX |
| `particles/example*.json` | 6 | 编辑器示例定义 |
| 字体文本文件 | 4 | 不属于播放端资产 |
| Web thumbnail fallback | 1 | 编辑器/缩略图资源 |
| **合计** | **2,194** | 分类口径来自历史静态取证快照 |

排除只针对本 App 不编辑壁纸这一产品边界。根级 46 个 Effect definition 及其 material/shader、通用 material/shader、SceneScript 模块和 zcompat 即使尚无 consumer，也保守纳入，避免后续播放能力接入时再次建立资产目录。

## 4. 运行与替换合同

当前真实 consumer 只有两组：Particle material slot 0 会在样本本地资源缺失后直接读取 `assets/materials/particle/**/*.tex`；文字解析会在壁纸包内字体缺失后直接读取 `assets/fonts/<作者文件名>`。两条路径均不依赖 catalog 或替代文件名映射。

其余 Effect、material、shader、sidecar、LUT、normal、多纹理、SceneScript 和 zcompat 文件已经具备固定物理身份，但 consumer 仍按各专项能力表推进。后续实现必须直接复用本包现有路径，并以“包内现有文件被对应 consumer 实际读取”为资源链验收条件；不得再创建另一个 stock 资产包或另一套命名。

占位生成器 `script/generate_scene_stock_asset_bundle.py` 与 919 项集合门 `script/tests/test_scene_stock_asset_bundle.py` 已随真实素材落地退役（`47e2fa8`）；bundle 内容由 `.tex` 直查门与各 consumer 门守护。

## 5. 证据等级

- A 级：历史 2.8.42 静态取证记录了 3,113 个相对路径、扩展名及目录归属。
- 项目事实：919 个播放候选路径均有物理文件且 payload 为真实素材；223 个 TEX 可直接解码（定向 runtime 门以 `particle/debris/debris1` 验证 1024x128 R8 spritesheet 上传），15 个官方命名字体均可由 CoreText 打开；Particle slot 0 与字体 consumer 已进入 runtime。
- 未证明：未接入文件的官方加载时机、JSON/shader/sidecar 语义、TEX codec/尺寸/通道/mip/atlas/颜色空间和像素等价；这些仍需自有 fixture 与 Windows golden。
