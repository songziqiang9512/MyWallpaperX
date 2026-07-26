# Wallpaper Engine stock 播放资产包

> 事实快照：Wallpaper Engine `2.8.42` / Steam build `23967692`
>
> 路径清单来源：Wallpaper Engine `2.8.42` 的历史静态取证
>
> 项目目录：[SceneStockAssets.bundle](../../../MyWallpaperX/Resources/SceneStockAssets.bundle)

## 1. 目的与边界

`SceneStockAssets.bundle` 一次性建立官方 `assets/**` 中所有播放候选资产的原相对路径、文件名和扩展名。素材制作完成后直接原位替换，不新增平行命名、目录或 runtime 别名。编辑器 preset、preview、example、thumbnail 与 source-only 文件不进入 App。

**播放资产路径状态：完整。** 官方目录共有 3,113 个文件；保守播放分类纳入 919 项并建立物理文件，明确排除 2,194 项编辑器资产。这里的“完整”只表示当前官方版本的播放候选路径占位完整，不表示占位 payload 有官方语义，也不表示所有 consumer 已实现。

本包不含 catalog。运行时直接按 `SceneStockAssets.bundle/assets/...` 官方相对路径查文件；播放候选目录清单是当前资源合同，`.tex` 路径由 [test_scene_stock_texture_resolver.py](../../../script/tests/test_scene_stock_texture_resolver.py) 覆盖解析。

## 2. 纳入集合

| 类型 | 数量 | 占位合同 |
|---|---:|---|
| `.tex` | 223 | 项目自建合法 `TEXV0005/TEXI0001/TEXB0002` format-0 单 mip，内嵌同一张 16x16 项目图标 |
| `.tex-json` | 198 | 合法 `rgba8888`、`nomip=true` JSON，占位值不代表官方 metadata |
| `.json` | 208 | 合法空对象；覆盖根级 Effect/Material、通用 model、shader declaration 与 zcompat 路径 |
| `.vert` / `.frag` / `.geom` / `.h` | 268 | 项目注释占位；命中后允许 planner/compiler 按未实现或无入口失败关闭 |
| `.js` | 4 | SceneScript 模块路径的项目注释占位，不执行官方脚本 |
| `.png` | 3 | `refractnormal`、`waterflowphase`、`waterripplenormal` dependency 的合法项目图片占位 |
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
| **合计** | **2,194** | 任一分类变化都会使固定资产门失败 |

排除只针对本 App 不编辑壁纸这一产品边界。根级 46 个 Effect definition 及其 material/shader、通用 material/shader、SceneScript 模块和 zcompat 即使尚无 consumer，也保守纳入，避免后续播放能力接入时再次建立资产目录。

## 4. 运行与替换合同

当前真实 consumer 只有两组：Particle material slot 0 会在样本本地资源缺失后直接读取 `assets/materials/particle/**/*.tex`；文字解析会在壁纸包内字体缺失后直接读取 `assets/fonts/<作者文件名>`。两条路径均不依赖 catalog 或替代文件名映射。

其余 Effect、material、shader、sidecar、LUT、normal、多纹理、SceneScript 和 zcompat 文件已经具备固定物理身份，但 consumer 仍按各专项能力表推进。后续实现必须直接复用本包现有路径，并以“原位替换后的文件被对应 consumer 实际读取”为资源链验收条件；不得再创建另一个 stock 资产包或另一套命名。

生成入口只接受不存在的输出目录：

```bash
python3 script/generate_scene_stock_asset_bundle.py \
  --source-root <wallpaper-engine-root> \
  --png-placeholder MyWallpaperX/Assets.xcassets/AppIcon.appiconset/Icon-iOS-Dark-16x16@1x.png \
  --font-placeholder-root MyWallpaperX/Resources/SceneStockAssets.bundle/assets/fonts \
  --output /tmp/SceneStockAssets.bundle
```

## 5. 证据等级

- A 级：历史 2.8.42 静态取证记录了 3,113 个相对路径、扩展名及目录归属。
- 项目事实：919 个播放候选路径均有物理文件；223 个 TEX 可直接解析，15 个官方命名字体均可由 CoreText 打开；Particle slot 0 与字体 consumer 已进入 runtime。
- 未证明：未接入文件的官方加载时机、JSON/shader/sidecar 语义、TEX codec/尺寸/通道/mip/atlas/颜色空间和像素等价；这些仍需自有 fixture 与 Windows golden。
