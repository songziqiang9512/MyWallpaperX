# 官方 19 工程 fixture 清单

审查日期：2026-07-25
证据来源：本机 Wallpaper Engine 2.8.42 正版安装 `projects/defaultprojects`
审查方式：只读静态解析 `project.json` / scene 文件 / 资产目录

> 这批工程随正版安装分发，**全部为解包状态（0 个 `.pkg`）**。它们是一批官方分发、结构完全可见的正向输入 corpus；本文不声称它们覆盖全部官方作者工程或历史版本。
>
> [运行证据索引](runtime-evidence-index.md) 记录的 45 个可运行样本全部来自 Workshop 用户作品。本文补的是官方自制侧的正向 fixture 基线。

## 1. 结论先行

1. **`project.json` 的 `type` 字段可缺席**。19 个工程中 3 个没有 `type`；兼容 loader 需要保留基于 `file` 扩展名的受限 fallback，并对未知扩展 fail closed。
2. **scene 文件名不固定为 `scene.json`**。4 个工程用 `<工程名>.json`，唯一权威是 `project.json` 的 `file` 字段。
3. **`general.orthogonalprojection` 是三态**：缺席 / 显式 `null` / `{width, height}` 对象。不是布尔。
4. **`camera.paths` 是文件引用数组**，指向 `scripts/*.json`。`scripts/` 目录在 scene 工程中装的是**相机路径数据，不是 SceneScript**。
5. 工程内的 `effects/<name>/effect.json` 是 stock effect 的**工程本地派生版本**：观察到的样本去掉了 `replacementkey`，并把 material/shader 重定向到工程自有文件。
6. 对象类型键（`image`/`model`/`particle`/`sprite`/`text`/`sound`/`light`）会以**显式 `null` 占位**出现在其他类型的对象上，判别必须判 null 而非判键存在；`id`、`name`、`origin` 全部可缺席，最小对象只有一个 `model` 键。
7. 19 个工程能覆盖 model / particle / sprite / text / sound / point light / effect / 相机路径 / spritesheet / image sequence，但**不覆盖 puppet warp、粒子 children、光源以外的 2D 光照、`.pkg` 解包与 TEX 版本矩阵**。

## 2. 工程类型与入口

| 工程 | `type` | `file` | 判定 |
|---|---|---|---|
| arsenal / beach / deep_space / demon_core / dino_run / dna_fragment / eagleflag / neon_sunset / razer_bedroom / razer_vortex / retro / shimmering_particles | `scene` | `scene.json` | scene |
| fantasticcar | `scene` | `fantasticcar.json` | scene |
| ricepod | `scene` | `ricepod.json` | scene |
| **audiophile** | **缺席** | `audiophile.json` | scene（按扩展名） |
| **techno** | **缺席** | `techno.json` | scene（按扩展名） |
| corsair_collection / corsair_o_tron | `web` | `index.html` | web |
| **sheep** | **缺席** | `sheep.exe` | **application**（Unity 可执行体） |

合计 **16 scene + 2 web + 1 application**。

两条对 loader 的硬约束：

1. **不能按 `scene.json` 硬编码路径**。必须读 `project.json.file`。
2. **`type` 缺席时需要受限 fallback**：本 corpus 支持 `.json` → scene-shaped、`.html` → web、`.exe` → application 的兼容规则。静态文件只能证明输入形态，不能证明官方 loader 的完整优先级或未知扩展策略。

`project.json` 的键并集：`authorsteamid, approved, contentrating, description, file, general, official, preview, tags, templateoptions, timestamp, title, type, version, visibility`。其中只有 `file`、`general`、`preview`、`title` 在 19 个工程中全部出现。

## 3. Scene 能力矩阵（16 个 scene 工程）

| 工程 | objects | image | model | particle | sprite | text | sound | light | effect 实例 | 相机路径 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|:---:|
| `dino_run` | 36 | 32 | 0 | 0 | 0 | 2 | 2 | 0 | 22 | — |
| `razer_bedroom` | 18 | 18 | 0 | 0 | 0 | 0 | 0 | 0 | 15 | — |
| `ricepod` | 8 | 0 | 6 | 1 | **1** | 0 | 0 | 0 | 0 | ✓ |
| `dna_fragment` | 6 | 0 | 5 | 1 | 0 | 0 | 0 | 0 | 0 | ✓ |
| `neon_sunset` | 5 | 2 | 2 | 1 | 0 | 0 | 0 | 0 | 1 | ✓ |
| `shimmering_particles` | 5 | 1 | 0 | 4 | 0 | 0 | 0 | 0 | 0 | — |
| `demon_core` | 4 | 0 | 2 | 1 | 0 | 0 | 0 | **1** | 0 | ✓ |
| `audiophile` | 4 | 0 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | — |
| `fantasticcar` | 4 | 0 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | ✓ |
| `techno` | 4 | 0 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | — |
| `arsenal` | 3 | 0 | 1 | 0 | 0 | 0 | 0 | **2** | 0 | ✓ |
| `beach` | 3 | 3 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | — |
| `razer_vortex` | 3 | 3 | 0 | 0 | 0 | 0 | 0 | 0 | 3 | — |
| `retro` | 3 | 2 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | — |
| `deep_space` | 2 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | — |
| `eagleflag` | **1** | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | — |

合计 109 个对象：image 64、model 29、particle 8、light 3、text 2、sound 2、sprite 1。七类之和恰好等于对象总数，且**没有任何对象带两个非 null 类型键**——在本 corpus 中类型键是互斥且完备的。

scene 文件顶层键只有 4 个：`general`、`objects`、`camera`，以及 3 个工程有的 `version`（`dino_run`、`razer_bedroom`、`shimmering_particles`）。**`version` 可缺席**。

### 3.1 类型判别必须判 null，不能判键存在

类型键会以**显式 `null` 占位**出现在不属于该类型的对象上。本 corpus 中的 null 占位次数：`model` ×3、`particle` ×2、`sprite` ×2、`image` ×1。

`arsenal` 的两个点光源对象就同时携带 `"model": null, "particle": null, "sprite": null`：

```
{ "light": "point", "color": …, "intensity": …, "radius": …,
  "model": null, "particle": null, "sprite": null, "origin": …, … }
```

按 `key in object` 判别会把它判成 model 或 particle 对象。**判别条件必须是 `object[key] != null`。** 这是本文初版的实际错误来源，属于会静默产出错误层类型、不报错的一类 bug。

同类键还有 `particlesrc`（1 次，取值 `null`，出现在 `ricepod` 一个 `particle` 非 null 的对象上）——非类型键也存在 null 占位。

### 3.2 `sprite` 对象引用 material，不是图片

唯一样本 `ricepod/objects[7]`（`name: "sun"`）：

```
"sprite": "materials/sprites/sunsprite.json"
```

取值是 **material JSON 路径**，与 `image` 对象的资源引用形态不同。单样本不足以确定 sprite 对象的完整字段集与渲染语义，只能确认引用目标类别。

### 3.3 `id` / `name` / `origin` 均可缺席

109 个对象中只有 101 个带 `id`、`name`、`origin`。缺席的 8 个全部集中在 `audiophile`（4）与 `techno`（4）——正是 §2 中 `project.json` 缺 `type` 的两个工程。

其中 4 个对象是**单键对象**：

```
{ "model": "models/…" }
```

其余 4 个只多一个键（`reflected`、`skin` 或 `origin`）。

对 loader 的三条硬约束：

1. **不能把 `id` 当必填**。需要稳定层身份时（如 SceneScript `getLayer` / `getLayerIndex`、effect 归属）必须能为无 `id` 对象合成索引身份，且合成规则要在同一工程内可重复。
2. **不能把 `origin`/`scale`/`angles` 当必填**，缺席时用默认变换，不是解析失败。
3. 这两个工程同时缺 `type` 与对象元数据，指向**较早的工程格式版本**（等级 C，无版本字段可证）。它们是最有价值的向后兼容负向门：任何按「字段必然存在」写的解析路径都会在这里先崩。

## 4. `general` 与投影

`general` 键在 16 个 scene 中的出现次数：

| 键 | 次数 | 键 | 次数 |
|---|---:|---|---:|
| `norecompile` | 16 | `clearenabled` | 5 |
| `clearcolor` | 16 | `farz` / `fov` / `nearz` | 4 |
| `ambientcolor` | 14 | `bloomhdrfeather` / `bloomhdrscatter` / `bloomhdrstrength` / `bloomhdrthreshold` / `hdr` / `zoom` | 3 |
| `bloom` | 14 | `supportsaudioprocessing` | 2 |
| `skylightcolor` | 14 | `bloomhdriterations` | 1 |
| `orthogonalprojection` | 10 | | |
| `camerafade` | 8 | | |
| `bloomstrength` / `bloomthreshold` | 7 | | |
| `cameraparallax*`（4 个）/ `camerapreview` / `camerashake*`（4 个） | 7 | | |

### 4.1 `orthogonalprojection` 三态

| 形态 | 工程 | 语义 |
|---|---|---|
| `{width, height}` | beach、deep_space、dino_run、eagleflag、razer_bedroom、razer_vortex、retro、shimmering_particles | 正交，给出场景坐标空间尺寸 |
| 显式 `null` | neon_sunset、ricepod | 透视 |
| 键缺席 | arsenal、audiophile、demon_core、dna_fragment、fantasticcar、techno | 透视 |

实际取值：`1920×1080`、`2200×1080`、`2520×1080`、`5760×1080`、`3840×2160`、`343×193`。**`dino_run` 的 `343×193` 说明这是场景单位而非像素**，不能当作渲染分辨率。

按「有值即正交」解析会把显式 `null` 误判为正交。当前工程结构把 `null` 与缺席都用于透视形态，但运行时投影选择和默认值仍需 Windows 运行门确认。

### 4.2 透视参数

只有 4 个工程给出 `fov`/`nearz`/`farz`：`dino_run`、`razer_bedroom`、`razer_vortex`、`shimmering_particles`，取值全部相同——`fov = 50.0`、`nearz ≈ 0.01`、`farz = 10000.0`。

注意这 4 个工程**同时是正交工程**（都有 `orthogonalprojection` 对象）。即透视参数与正交配置并存，正交生效时透视参数是死数据。不能用「有 fov 即透视」判定。

`nearz` 在 `dino_run` 中序列化为 `0.0099999998`（float32），在其余三者为 `0.009999999776482582`（double 展开的 float32）。同一常量两种写法，比较必须按 float32 精度。这与 [内联脚本 binding target 取证](scenescript-binding-target-forensics.md) §5 的 float32 结论一致。

### 4.3 音频处理

`supportsaudioprocessing` 只出现在 2 个工程：`audiophile` 为 `true`，`techno` 为 `false`，其余 14 个缺席。字段名与项目内容支持“音频处理能力开关”的 C 级解释，但缺席默认值和具体 provider 行为需要单独确认。

## 5. 相机路径

6 个工程使用相机路径，全部是透视工程：`arsenal`、`demon_core`、`dna_fragment`、`fantasticcar`、`neon_sunset`、`ricepod`。

`camera` 对象只有 4 个键：`center`、`eye`、`up`（16/16 全部存在，空格分隔字符串）和 `paths`（6/16）。

`paths` 是**文件路径字符串数组**，全部 6 个工程都是单元素 `["scripts/camera_00.json"]`。被引文件结构：

```
{ "paths": [ { "duration": <number>, "name": <string>,
               "transforms": [ { "center": "x y z", "eye": "x y z",
                                 "up": "x y z", "timestamp": <number> } ] } ] }
```

即**两层同名嵌套**：`scene.camera.paths[]` 是文件引用，被引文件里的 `paths[]` 才是路径数据。

| 工程 | path 数 | duration | 每 path transform 数 |
|---|---:|---|---:|
| `fantasticcar` | 6 | 26, 29, 26, 33, 29, 33 | 2 |
| `arsenal` | 5 | 30, 40, 50, 45, 60 | 2 |
| `demon_core` | 4 | 300, 450, 400, 350 | 2 |
| `ricepod` | 4 | 43, 35, 37, 43 | 2 |
| `dna_fragment` | 1 | 5 | 2 |
| `neon_sunset` | 1 | 5.0 | **1** |

两个必须处理的边界：

1. **`neon_sunset` 的 path 只有 1 个 transform**，无法插值。退化 path 必须不崩溃（合理行为是保持该 transform 静止）。
2. `duration` 在 `neon_sunset` 是 `5.0`、其余是整数 `5`/`30`/`300`。类型必须按 number 解析，不能按 int。

`transforms` 的向量同样是空格分隔字符串，与 §4 一致的解析规则。

## 6. Effect 引用与本地分叉

只有 4 个工程使用 effect，共 41 个实例：

| 引用路径 | 实例数 | 使用工程 |
|---|---:|---|
| `effects/scroll/effect.json` | 30 | dino_run ×21、razer_bedroom ×9 |
| `effects/tint/effect.json` | 9 | razer_bedroom ×6、razer_vortex ×3 |
| `effects/godrays/effect.json` | 1 | dino_run |
| `effects/filmgrain/effect.json` | 1 | neon_sunset |

**全部为工程相对路径，没有一个引用 stock effect ID。** 且工程内的副本与 `assets/effects/` 下的同名 stock 版本**逐字节不同，且更小**。

以 `tint` 为例，两版差异：

| 字段 | stock (`assets/effects/tint`) | 工程副本 (`razer_vortex/effects/tint`) |
|---|---|---|
| `replacementkey` | `"tint"` | **删除** |
| `passes[0].material` | `materials/effects/tint.json` | `materials/effects/rz.json` |
| `dependencies` | `tint.json` / `tint.frag` / `tint.vert` | `rz.json` / `rz.frag` / `rz.vert` |
| 其余（`version`、`name`、`description`、`group`、`preview`） | 一致 | 一致 |

即：作者把 stock effect 拖入工程后，编辑器写出的是一个**去掉 `replacementkey` 的分叉**，material 与 shader 全部重定向到工程自有文件。这解释了为什么工程副本更小。

推论（等级 C）：`replacementkey` 是 stock effect 的替换身份标识，工程本地 effect 不参与替换机制，因此被剥离。

**孤儿资产**：`razer_bedroom/effects/pulse/effect.json` 存在于磁盘但 `scene.json` 中零引用。loader 不能假设磁盘上的 effect 目录都被使用，依赖收集必须从 scene 引用出发而非扫目录。

## 7. 纹理与 `.tex-json`

129 个 `.tex` 文件，容器魔数**全部为 `TEXV0005`**（内含 `TEXI0001` + `TEXB0003`）。这批工程无法覆盖 TEX 版本矩阵。

87 个 `.tex-json` 是作者侧配置 sidecar，其中 78 个显式包含 `format`。键并集：

| 键 | 出现数 | 语义 |
|---|---:|---|
| `format` | 78 | 目标压缩格式 |
| `nonpoweroftwo` | 58 | 允许非 2 的幂尺寸 |
| `clampuvs` | 57 | UV clamp |
| `nomip` | 47 | 不生成 mipmap |
| `bleedtransparentcolors` | 47 | 透明像素颜色外扩（防边缘黑边） |
| `nointerpolation` | 34 | 点采样 |
| `srgb` | 10 | sRGB 色彩空间 |
| `spritesheet` + `spritesheetsequences` | 6 | 精灵表动画 |
| `imagesequence` + `frameduration` | 3 | 逐帧图片序列 |

`format` 取值分布：`rgba8888` ×67、`dxt5n` ×5、`dxt5n+` ×5、`dxt5` ×1、缺席 ×9。

`dxt5n` / `dxt5n+` 的 10 个 sidecar 全部是 `*_normal.tex-json`（arsenal 5、fantasticcar 4、eagleflag 1）。它们是压缩法线输入的官方正向 corpus；具体 shader 分支与像素结果见 [Shader source 前置合同审查](shader-prelude-and-backend-abstraction.md)，不能只由 sidecar 名称宣称运行 parity。

`srgb` 集中在 `razer_bedroom`（10 个中的绝大部分），并与该工程 `hdr: true` 同时出现；这是 corpus 相关性，不证明 HDR 是启用 sRGB 标注的原因或必要条件。

两种动画纹理形态：

```
spritesheet:    {"spritesheet": true,
                 "spritesheetsequences": [{"duration": 1, "frames": 2,
                                           "width": 24, "height": 24}]}
imagesequence:  {"frameduration": 0.1,
                 "imagesequence": ["a_01.png", "a_02.gif", ...]}
```

注意 `imagesequence` 的**帧文件可以混合扩展名**（首帧 `.png`、后续 `.gif`）。按统一扩展名匹配会漏帧。

## 8. Shader 编译缓存

工程内存在两类预编译 shader blob 目录：

| 目录 | 魔数 | 后缀 | 出现工程数 | 目标 |
|---|---|---|---:|---|
| `shaders/blobsSM40/` | `SHDV0069`（内含 `DXBC`） | `.dxs` | 6 | D3D Shader Model 4.0 |
| `shaders/blobsGES3/` | `SHDD0066` | `.gxs` | 4 | OpenGL ES 3 |

文件名是 40 位十六进制（SHA-1 形态），且同名 blob 跨工程复用（如 `af6b4c9d…dxs` 同时出现在 `deep_space` 与 `razer_vortex`）。这支持“稳定缓存身份”的高可信解释，但静态文件不能确认 key 的确切输入是否为源码、combo、编译器版本或它们的组合。

对 MyWallpaperX 的意义：这些 blob 是 Windows/GLES 后端产物，macOS 侧不应执行；资源索引应把它们分类并跳过，而不是当作未知致命资源。MSL 缓存可以采用自有、版本化的完整 variant key，但不能把 40 位文件名反推成已确认的官方 key 算法。

## 9. 粒子系统覆盖

7 个粒子文件分布在 6 个工程。顶层键并集：`material`、`maxcount`、`emitter`、`initializer`、`operator`（7/7 全有），`starttime`、`controlpoint`（5/7），`renderer`（5/7），`children`、`flags`（4/7），`animationmode`、`sequencemultiplier`（2/7）。

| 文件 | maxcount | emitter | initializer | operator | renderer | controlpoint |
|---|---:|---:|---:|---:|---:|---:|
| `shimmering_particles/small_motes_copy1.json` | 400 | 1 | 6 | 5 | 1 | 8 |
| `shimmering_particles/dustmotes.json` | 200 | 1 | 4 | 4 | 1 | 8 |
| `neon_sunset/stars.json` | 1024 | 1 | 4 | 2 | 1 | 8 |
| `ricepod/starfield.json` | 250 | 1 | 4 | 2 | 1 | 8 |
| `dino_run/coinget.json` | 500 | 1 | 3 | 3 | 1 | 8 |
| `demon_core/particles.json` | 200 | 1 | 4 | 2 | **0** | 0 |
| `dna_fragment/particles.json` | 100 | 1 | 3 | 2 | **0** | 0 |

出现的组件名：

| 类别 | 组件 |
|---|---|
| emitter | `sphererandom` ×6、`boxrandom` ×1 |
| initializer | `lifetimerandom` ×7、`sizerandom` ×7、`velocityrandom` ×6、`colorrandom` ×6、`angularvelocityrandom` ×1、`rotationrandom` ×1 |
| operator | `movement` ×7、`alphafade` ×7、`oscillateposition` ×2、`oscillatealpha` ×2、`sizechange` ×1、`angularmovement` ×1 |
| renderer | `sprite` ×4、`spritetrail` ×1 |

三条可用事实：

1. **`renderer` 可缺席**（`demon_core`、`dna_fragment`）。这两个文件同时也没有 `controlpoint`；官方缺省 renderer 的选择与可见性仍需运行门确认。
2. **`controlpoint` 一旦存在就恰好是 8 个**，5/5 一致。这是固定槽位实现的候选证据，不足以排除其他长度。
3. **`children` 键在 4 个文件中存在但全部为空数组**。子粒子系统在官方自制工程中零覆盖，不能用这批 fixture 验证。

`emitter` 恒为 1 个——多发射器场景同样零覆盖。

## 10. 资产格式清单

| 扩展名 | 含义 | 出现工程 |
|---|---|---|
| `.tex` / `.tex-json` | 编译纹理 + 作者侧配置 | 全部 scene |
| `.png` / `.jpg` / `.tga` / `.gif` | 源图 | 全部 scene |
| `.mdl` | 编译模型 | arsenal、audiophile、demon_core、dna_fragment、fantasticcar、neon_sunset、retro、ricepod、techno |
| `.fbx` | 源模型 | arsenal、demon_core、dna_fragment、retro |
| `.obj` + `.mtl` | 源模型（另一路） | audiophile、fantasticcar、neon_sunset、ricepod、techno |
| `.frag` / `.vert` | 自定义 shader 源码 | 15 个 scene（`arsenal` 除外） |
| `.dxs` / `.gxs` | 预编译 shader 缓存 | 见 §8 |
| `.wav` | 音效 | dino_run（2 个） |

**`.mdl` 与源模型成对分发**，且源格式有 `.fbx` 与 `.obj+.mtl` 两路。工程同时带编译产物和源文件，说明官方分发的是**编辑器可再编辑的完整工程**，不是运行时精简包。

自定义 shader 共 45 对 `.frag`/`.vert`，命名与工程绑定（`ricepodjet`、`technohex`、`neonsun`、`audiophileflow` 等）。`arsenal` 是唯一没有自定义 shader 的 scene 工程——它只有 `.dxs` 缓存，源码未随包。

## 11. 建议的最小正向门

按覆盖能力从窄到宽排序，每一档只引入一个新维度：

| 档 | 工程 | 新增覆盖维度 | 为什么选它 |
|---:|---|---|---|
| G0 | `eagleflag` | 单 image layer + 正交 + `dxt5n+` 法线 | **1 个 object**，全库最小 scene；同时是压缩法线输入的最小载体 |
| G1 | `deep_space` | 2 image layer + 自定义 shader | 无 model/particle/effect 干扰的纯 shader 门 |
| G2 | `razer_vortex` | effect 链 + `constantshadervalues` + SceneScript 绑定 | 3 object / 3 effect，是 script-bound shader constant 的最小样本 |
| G3 | `shimmering_particles` | 粒子 ×4 + HDR + bloom + scene 级 script 绑定 | 粒子与 HDR 的最小交集 |
| G4 | `retro` | image + model 混合 | 首个引入 `.mdl` 的小工程（3 object） |
| G5 | `arsenal` | 透视 + 相机路径 + model + 2 个 point light | 首个透视 + 路径动画；无自定义 shader 源码，适合几何、路径与点光输入门 |
| G6 | `demon_core` | point light + 无 renderer 粒子 | 同时覆盖 3D 点光与粒子 renderer 缺省输入 |
| G7 | `razer_bedroom` | 18 layer + 15 effect + HDR + sRGB + 6 处 script | 大规模 2D 合成 + 色彩空间 |
| G8 | `dino_run` | 36 layer + text + sound + spritesheet + imagesequence + 7141B 脚本 | 全库最复杂；覆盖文字、音频、两种动画纹理和动态 layer 生命周期 |

G0–G3 建议作为**回归门**（每次改动都跑），G4–G8 作为**快照门**（阶段性跑）。

各门的接入前提：

| 门 | 前置能力 |
|---|---|
| G0 | scene 解析、image layer、正交投影、TEX 解码（含 DXT5n） |
| G1 | + 自定义 shader 编译（prelude 见 [Shader Prelude 文档](shader-prelude-and-backend-abstraction.md)） |
| G2 | + effect 链、`constantshadervalues`、SceneScript VM |
| G3 | + 粒子系统、HDR/bloom |
| G5 | + 透视相机、相机路径插值、`.mdl` 加载 |
| G8 | + 文字渲染、音频、spritesheet/imagesequence |

此外 `audiophile` 与 `techno` 应作为**格式健壮性门**单独跑，而不是排进能力阶梯：它们同时缺 `project.json.type` 与对象的 `id`/`name`/`origin`（见 §2、§3.3），只需要 `.mdl` 加载即可解析。任何按「字段必然存在」写的路径会在这两个工程先失败，因此它们的成本远低于其暴露的问题面。`techno` 另有 `supportsaudioprocessing: false` 与 `audiophile` 的 `true` 构成同一字段的正反两例。

## 12. 这批 fixture 覆盖不到的

以下能力在 19 个工程中**零样本**，不能用它们建门：

- Puppet Warp（无 puppet 数据）
- 粒子 `children` 子系统（键存在但全空）
- 多 emitter 粒子（恒为 1）
- 2D lights（只观察到 `arsenal` 2 个、`demon_core` 1 个 point light，均为 3D 场景）
- `.pkg` 打包解析（全部解包）
- TEX 版本矩阵（129 个全为 `TEXV0005`）
- 视频纹理、Timeline 动画事件、Texture Variants、`displaycondition`
- 用户属性的全部类型（`project.json.general` 中的属性未在本文展开，需单独取证）

这些仍需 Workshop 样本或自建 fixture，见 [资料来源与证据索引](source-index.md) §7。

## 13. Clean-room 边界

本文记录工程名、文件名、字段名、字段取值、组件名、资产格式与数量统计。这些是结构与合同信息。

**不复制官方工程的 scene 数据、shader 源码、模型、纹理或脚本进仓库。** 运行或注入测试前应复制到隔离 root 并使用临时 HOME；原始安装副本只作只读来源，与 [资料来源与证据索引](source-index.md) §6 的隔离原则一致。

需要可提交到仓库的 fixture 时，按本文的结构规格自建等价最小工程，不放官方 payload。

## 14. 关联文档

- [内联脚本与 binding target 取证](scenescript-binding-target-forensics.md) —— 本批工程中 13 处内联 SceneScript 的详细取证
- [Shader Prelude 与跨后端抽象层取证](shader-prelude-and-backend-abstraction.md) —— `dxt5n` 与 `DecompressNormal` 分支的对接
- [场景格式与 Render Graph](scene-format-and-render-graph.md) —— scene 文件整体结构
- [运行时系统语义](runtime-systems-reference.md) —— 粒子组件语义
- [运行证据索引](runtime-evidence-index.md) —— Workshop 侧现役样本矩阵
- [资料来源与证据索引](source-index.md) —— 本文来源应登记于此
