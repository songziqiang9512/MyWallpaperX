# Scene 格式与 Render Graph 语义

> 目的：把 Scene 从文件实例解释为可执行图，而不是按 effect 名称选择近似动画。
>
> 证据边界：作者行为以官方文档为准；序列化字段主要来自真实 Workshop 样本和开源解析器交叉验证，不是官方稳定 schema。
>
> 实现基线：`b8842d8`；当前正式门：`.codex/scene-opacity-final13-20260723-1730/report.json`（13/13、5 类 strict backend、14 stage、1 条真实 chain、Opacity 4、Workshop Shadow 1、failed 0、blocked 2、route-only 30；相关测试 269 total / 267 passed / 2 skipped）。

## 1. 文件与资源层级

| 层级 | 常见内容 | 运行时职责 | 证据 |
|---|---|---|---|
| `project.json` | wallpaper 类型、入口文件、标题/preview、`general.properties` | 选择 Scene 入口并建立用户属性默认值 | B |
| `scene.json` / 同名入口 | `general`、`camera`、`objects` | 建立画布、相机、对象源顺序和作者状态 | B/D |
| `scene.pkg` / `gifscene.pkg` | models、materials、textures、particles、scripts 等虚拟文件 | 与 loose files 组成统一只读 VFS | B/D |
| model JSON | material、autosize、solid、crop、puppet | 定义可绘制资源与几何/角色关联 | B/D |
| material JSON | ordered passes、shader、texture slots、combos、constants、render state | 定义实际 draw pipeline | B/C/D |
| effect JSON | FBO、ordered passes、bind/target/compose/copy/swap、dependency | 定义对象 effect 子图 | C/D |
| shader | GLSL-like 源码、combo、uniform/texture annotations、includes | 定义每个像素/顶点的真实算法 | A/C/D |
| particle JSON | emitter、initializer、operator、renderer、control point、children | 定义粒子 simulation graph | A/B/D |
| SceneScript | property-bound ECMAScript module | 在事件和每帧阶段更新作者绑定值 | A/B |

播放器应把 loose files、包文件和用户替换资源挂到一个规范化、只读的资源命名空间。任何绝对路径、`..` 越界、包内重复名称或资源循环都必须受控失败。

## 2. `project.json`

当前样本稳定出现的顶层职责：

- 指定 Scene 类型与入口文件；
- 提供 preview 和 Workshop 展示信息；
- 在 `general.properties` 定义用户属性；
- 为属性提供默认值、顺序、分组、选项和显示条件；
- 部分属性直接绑定 scene/object/effect/particle/text target，另一部分由 SceneScript 消费。

### 2.1 用户属性不是效果扫描结果

属性面板只来自项目声明，不能通过扫描 shader uniform 自动生成 Wallpaper 用户属性。Shader 的 editor 参数和 Wallpaper 用户属性是不同层级；只有项目的显式 binding 才把两者连接。

### 2.2 值形态

样本中同一逻辑值可能是：

```json
true
```

或：

```json
{ "value": true, "user": "clock" }
```

也可能包含 `script` 与 `scriptproperties`。解析器必须保留静态值、用户绑定和脚本三部分，不能只递归取出 `value` 后丢掉动态来源。

## 3. `scene.json`

### 3.1 `general` 与 `camera`

高价值字段分组如下。字段名来自样本观察，行为描述由官方文档交叉验证：

| 分组 | 观察字段 | 语义 |
|---|---|---|
| 画布/投影 | `orthogonalprojection.width/height`、`fov`、`nearz`、`farz` | 作者画布和相机投影，不等同目标屏幕尺寸 |
| 清屏 | `clearenabled`、`clearcolor` | Scene 自己的清屏背景；露灰通常意味着构图或 camera cover 错误，不应靠强制拉伸掩盖 |
| 相机 | `camera.eye/center/up`、`zoom` | 2D/3D view 基础 |
| Camera Parallax | `cameraparallax`、`amount`、`delay`、`mouseinfluence` | 只有显式开启才根据鼠标移动相机；逐层 depth 再控制参与量 |
| Camera Shake | `camerashake` 及 amplitude/speed/roughness | 场景级相机行为，与对象 Shake effect 不同 |
| 后处理 | `bloom`、Bloom/HDR 参数、`hdr` | Scene 全局后处理，不应塞进每个对象的 effect stack |
| 环境 | ambient/skylight、gravity、wind | 供 lighting、particle、puppet/physics 使用 |

官方 Camera Parallax 规则：场景先显式开启，每个 layer 才出现 parallax depth；某轴为 0 时该轴不移动，两个轴都为 0 时该层不参与。背景需要作者预留 overscan，否则相机移动会露出 clear color。播放器不应擅自放大所有场景来“修复”作者本身的边缘构图，但应正确实现 cover/crop 和作者画布。

### 3.2 `objects` 是有序绘制输入

对象常见职责：

| 字段族 | 含义 |
|---|---|
| `id`、`name` | 稳定引用、调试和脚本查找 |
| `visible`、`alpha`、`color`、blend | 作者状态与最终合成 |
| `origin`、`size`、`scale`、`angles` | object transform；不得与 effect-local UV transform 混用 |
| `parent` / children | 层级 transform、可见性与生命周期传播 |
| image/model/text/particle/sound 引用 | 对象内容类型 |
| `effects[]` | 显式、有序的 effect 实例 |
| dependencies / layer texture references | 跨层资源边 |
| `parallaxdepth`、传播控制 | Camera Parallax 的逐层参数 |
| dynamic wrappers | 用户属性、Timeline 或 SceneScript 的写入目标 |

当前真实样本和 MyWallpaperX 解释层都以 source order 作为基础顺序。遇到 dependency 时，应把 dependency 加入资源/渲染图，而不是重排所有对象后丢失作者合成顺序。

## 4. 动态值的求值顺序

官方资料明确 SceneScript 是 property-bound 系统，Timeline 也绑定具体 property。建议把每个可写属性建成 typed target，而不是让脚本直接碰 renderer 内部对象。

每帧合同：

```text
authored base value
  -> user property/direct binding
  -> timeline evaluation
  -> SceneScript event/update return or direct assignment
  -> validated typed snapshot
  -> particle/text/resource update
  -> uniform upload and render
```

官方说明 Timeline animation 先更新，SceneScript 可在之后覆盖同一属性。`applyUserProperties` 首次加载调用一次，后续事件只携带变化键。具体事件见 [运行时系统语义](runtime-systems-reference.md)。

## 5. Effect definition

以下是从 WE-compatible asset 定义和开源解析器交叉归纳的 IR，不是官方公开 JSON schema：

```text
EffectDefinition
  replacementKey?
  dependencies[]
  fbos[]
    name
    scale | width/height | fit
    format
    clear?
    unique? (raw declaration)
    uvs? / conditions?
  passes[] (ordered)
    material?
    target?
    bind[] { name, index, conditions? }
    compose?
    command? (raw; observed copy/swap)
    source?
    target?
    conditions?
  functions? / gizmos? / extraFields
  unknownFieldPaths[]
```

实例 material pass 只与 definition 中的 material pass 按 ordinal 对齐；copy/swap 等 command 不消耗该 ordinal。v15 按上述合同保真保存定义，v16 在不猜测未知字段的前提下把它编译成 authored graph。

### 5.1 显式启用

effect 只有在对象 `effects[]` 引用对应 `file` 且实例 `visible` 没有解析为 false 时才进入候选图。随后还要应用用户属性、Timeline 和 SceneScript 的动态状态。播放器支持某种 effect 不能成为启用条件。

### 5.2 Ordered passes

pass 顺序是执行合同。典型类型：

- 单 pass：source + optional mask -> output；
- ping-pong：downsample -> horizontal -> vertical -> combine；
- scene compose：先捕获该 layer 后方场景，再执行折射/混合；
- stateful：本帧输入 + history RT -> 新 history -> final combine；
- command：显式 copy source -> target 或 swap 资源 identity/handle，不运行 material shader，也不消耗 material ordinal。

### 5.3 `previous` 不是“当前屏幕”

在观察到的内置定义中，`previous` 是当前 effect 开始前的固定输入：同一 effect 内所有引用都解析为同一 identity，不是“上一 pass 的 target”；只有整个 effect 完成后，effect chain 的输入才前进到该 effect 输出。它与以下资源都不同：

- 原始、未处理的 layer texture；
- 已经绘制到 Scene 的下方背景；
- `_rt_FullFrameBuffer` 一类 scene alias；
- 其他 layer 发布的 named target；
- 当前 effect 私有 ping/pong RT；
- 上一帧 history RT。

把这些资源都绑定到同一个 framebuffer 会产生重复背景、错误反馈和整屏污染。

### 5.4 `compose`

官方 Refraction 行为明确需要先捕获 layer 后面的场景，再用 normal map 折射；但私有 definition 中 raw `compose:true` 是否在所有 effect 上都等价于这一输入，当前证据不足。v16 保留 raw compose 并阻断通用执行，不能仅看到 `compose:true` 就绑定 scene background；经逐 definition 验证后再映射具体 provider。

### 5.5 copy 与 swap

Motion Blur 等定义含显式 copy，用来复制 source 像素到 target；省略 copy 或把它当 material pass，会改变 read/write 顺序。观察到的 swap command 则交换资源 identity/handle，不是像素 copy。两者都不消耗 material ordinal；swap 还必须验证 allocation scope、UV、clear/reset 和 condition 合同兼容后才能执行。

## 6. Render target 与生命周期

| 属性 | 执行含义 | 错误实现的后果 |
|---|---|---|
| `scale` | 相对 effect/source 尺寸分配 RT | blur kernel、texel size 与性能均错误 |
| fixed `width/height` / `fit` | 固定 simulation grid 或按约束 fit | ripple/fluid 状态尺寸不稳定 |
| `format` | R8、RG16F、RGBA 等数据语义 | normal、pressure、mask 精度和通道错误 |
| `unique` | 作者声明该资源需要实例唯一性；本字段本身不等于 history | 多 effect 实例错误共享；或错误常驻造成资源泄漏 |
| UV/wrap mode | repeat、clamp 或特定映射 | 云、水、glitter 出现切边或平铺错误 |
| named target | 供后续 pass/layer 精确引用 | provider 内容缺失或绑定到错误画面 |

资源注册表应以 `wallpaper + screen + object + effect instance + RT name` 作为身份基础。是否跨帧保留必须由 read-before-write、copy/swap、function/reset 和生命周期数据流判定，不能只看 `unique`。最终判为 persistent 的资源在 resize、壁纸切换、seek、停止和设备丢失时必须清理或重建。

MyWallpaperX v21 继承逐帧 registry、binding program 与 ShaderContract：实例随当前 renderer/screen 隔离，帧内 identity 区分 layer source、完整 named layer target（包含 variant）、user property 与 system key；entry 记录 ready/pending/unavailable，并已把静态 resource generation 与 named frame epoch 分离。effect-instance target table 已被 precise/standard Blur、stock Local Contrast、exact Workshop Shadow 与 exact stock Opacity 消费；`b541867` 连接 ordered all-supported chain，`809b75e` 取得首条真实 `Blur Precise -> Shadow`，`b8842d8` 再让 stock Opacity direct alpha 从 per-surface snapshot 进入 GPU。pool 会先为整链建立 plan/table、预算和 LRU 候选，再原子提交 cache；GPU 仅在全部 stage 成功后合成最终输出。其他 RGBA graph、history、跨帧 persistent、system/media/video/Texture Variants、通用 material consumer 和 copy/swap 生命周期仍未实现。

## 7. Material definition

观察到的 material pass 合同：

```text
MaterialPass
  shader
  textures[0...7]        // nullable, preserve holes
  usertextures[0...7]?   // instance/provider inputs
  combos                 // compile-time variants
  constantshadervalues   // runtime/static uniforms
  blending
  depthtest
  depthwrite
  cullmode
```

### 7.1 Texture slot

官方 shader 文档公开 `g_Texture0` 到 `g_Texture7`，并明确 sampler annotation 可以定义 `default`、`mode`、`combo`、paint defaults 等。由此得到的硬规则：

- slot 的意义由当前 shader annotation 和 material 决定；
- 数组位置必须原样保留，`null` 不得被过滤；
- optional texture 未绑定时，对应 combo 通常不定义/为 0；
- material default、effect instance override、user texture 和 explicit pass bind 必须在同一 resolver 中按来源跟踪；
- resolution、mapped size、rotation/translation 需按最终绑定 texture 更新。

`Almamu/linux-wallpaperengine` 采用“shader default -> material -> effect override -> explicit bind”的优先级，这是一条有用的 D 级佐证，但仍需用合法官方 assets/真实样本逐类验证后才能固化为 MyWallpaperX 合同。

MyWallpaperX 当前 material resolver 为每个 sparse slot 按低到高优先级保留候选，现有顺序是 material asset -> material usertexture -> instance asset -> instance usertexture -> explicit graph bind；现有 strict graph backend 取末项作为最高优先级 source。frame registry 使用的是另一份显式“首选 -> fallback”selection，并选择其中首个 ready provider；目前尚无通用 material candidate -> frame selection 桥。这是由现有数据模型和样本验证的 E 级实现事实，不是官方公开的通用优先级。v21 继续保留 ShaderContract 的 annotation/default raw/structured value；Local Contrast/Opacity planner 只对 exact stock fingerprint 使用固定 adapter，typed schema 与通用 resolver consumer 尚未实现，扩 generic backend 前仍需补齐。

### 7.2 Render state

blend、depth 和 cull 属于 material/pass 语义。未知 blend mode 不能无声回退 normal 后仍宣称支持；至少应 passthrough 并记录 `unsupported-render-state`。alpha 的 straight/premultiplied 关系要在纹理解码、effect RT 和最终 composite 三处一致。

## 8. Shader 语义

官方文档确认 Wallpaper Engine 使用自定义 GLSL-like 预处理器，并可能转换为 HLSL。兼容层需要处理：

- `GLSL`、`HLSL`、`HLSL_SM40`、`HLSL_GS40` 条件；
- `texSample2D`、`mix`、`frac`、`saturate` 等跨语言宏；
- `[COMBO]` 及 shader annotation 驱动的 compile-time permutation；
- scalar/vector/color/UV uniform metadata；
- include headers 与 blending helpers；
- vertex attributes、varyings 和 fragment output；
- 每帧 built-in uniforms。

`8474ace` 已将这条链路的第一层合同写入 interpretation v19：对 authored vertex/fragment stage 保存完整 UTF-8 source、raw SHA-256、相对路径、include reference/line、annotation raw/structured value/marker/line、uniform/attribute/varying declaration、diagnostic 与 canonical SHA；精确 host built-in identity 使用无 stage 合同。路径穿越、shader root/stage/include symlink escape、无效 UTF-8、缺失 stage、畸形 annotation 和重复 identity 均 fail closed。该实现是 line-based、loss-preserving 的 L1 source contract，不是完整 AST，也没有 include expansion、macro/permutation preprocessing、translation、stage link、compile、typed default consumption、uniform upload 或 GPU execution。

`136d35c` 没有改变上述通用结论。它只在 stock Local Contrast strict planner 中核对三份 authored shader contract 的 identity、canonical SHA、stage path、raw SHA 和 source SHA，再调用项目内手写 MSL；Gaussian `scale=(1,1)` 与 combine `strength=1` 的缺省值只在这个 exact profile 内解释。该路径不预处理、翻译或编译 authored source，也不建立通用 uniform binder。

`b541867` 同样没有改变上述 authored shader 边界。它只按作者 effect 顺序组合已由 strict planner 接受的手写 backend，并验证 layer source -> effect output 的输入连续性；每个 Local Contrast stage 从同一 per-surface snapshot 单独取得 strength。这个 scheduler 不读取任意 shader source，也不执行 copy/swap/compose/history/condition/function。

`809b75e` 也只增加一个以完整 definition/material/ShaderContract fingerprint 准入的 exact Workshop Shadow profile，并调用项目内手写 Metal backend。它没有翻译或执行任意 authored shader，没有建立官方 Shadow/lighting 语义，也没有新增 live target；其 `common_blending` mode 0 路径不能充当官方 blend oracle 或 generic `ApplyBlending` 证明。

### 8.1 关键 built-in uniforms

官方公开的高价值集合：

| 组 | 变量 |
|---|---|
| 时间/输入 | `g_Time`、`g_Daytime`、`g_Frametime`、`g_PointerPosition`、`g_PointerPositionLast` |
| surface | `g_TexelSize`、`g_TexelSizeHalf`、`g_Screen` |
| object | `g_Alpha`、`g_Color`、`g_Color4`、`g_ParallaxPosition` |
| camera/object matrices | model、inverse、view/projection、orientation vectors |
| effect/layer matrices | effect model/MVP/texture projection、layer model |
| texture | `g_TextureNResolution`、sprite rotation/translation |
| audio | 16/32/64-bin left/right spectra |

`g_TextureNResolution.xy` 是物理纹理尺寸，`.zw` 是 mapped size；压缩纹理或补齐到 2 的幂时两者可能不同。mask、flow、normal 和 effect-local UV 不能只用 drawable 尺寸推导。

## 9. Camera Parallax、Depth Parallax 和局部动画

| 能力 | 启用来源 | 空间 | 输入 | 正确行为 |
|---|---|---|---|---|
| Camera Parallax | scene `cameraparallax` + layer depth | camera/object transform | pointer、amount、delay、mouse influence | 整层按深度移动；depth 0 不移动 |
| Depth Parallax | explicit `depthparallax` effect | effect-local UV | depth map、pointer/parallax position、可选 mask | 按 depth 重采样；高质量模式有多层 raymarch |
| Shake | explicit `shake` effect | effect-local UV | flow、time offset、opacity mask、可选 audio | 只在 mask/flow 指定区域变形 |
| Swing/Foliage/Water | explicit effect | effect-local UV 或 vertex | region/mask/noise/flow/normal | 服从作者局部区域，不修改对象 transform |

这四类不能合并成一个“鼠标移动/正弦位移”开关。

## 10. 建议的通用执行顺序

下面是基于官方行为、真实样本和两个可审计实现归纳的 MyWallpaperX 目标 IR；其中 raw pass 的最终默认细节仍需更多官方 assets 验证：

```text
for object in authored source order:
  resolve parent visibility + object state
  update/create base resource
  draw base object into object working texture

  for effect in authored order where resolved visible:
    allocate/reuse effect instance RTs
    for pass in authored order:
      resolve shader variant and render state
      resolve texture0...7 without compacting holes
      execute compose/copy/swap/material node to declared target
      publish named target; keep this effect's previous fixed

    advance effect-chain input to this effect output

  composite final object output into scene target

apply scene post processing
present or read back
```

## 11. 当前 MyWallpaperX 映射

| 层级 | 当前状态 | 下一合同 |
|---|---|---|
| Scene/object IR | format 20 继承 v19 ShaderContract、v18 binding program/effective values、v17 provider metadata 与 v16 authored graph/canonical SHA，并增加 strict Local Contrast strength live-binding contract | 保持 raw/typed 双层合同，不把未知字段静默解释为支持 |
| dependency | graph 已结构化区分固定 `previous`、effect-scoped RT 和 copy/swap；五个 strict backend 与 ordered chain 已消费 effect target table，并闭合整链 identity/continuity、allocation/cache/LRU 事务、末段合成与 reset；bounded frame registry 按另一命名空间处理 named target、property-authored fallback 和受限 PNG/JPEG property source | 并行补显式 dynamic generation、system/media/video/variant/effectful/nested source；copy/swap/compose/history 仍按独立合同接入 |
| material/shader | sparse-slot candidate resolver、ShaderContract v1、strict 2-pass precise、stock standard Blur 4-pass、stock Local Contrast 4-pass、exact Workshop Shadow 与 exact stock Opacity single-pass 共 5 类 backend 已落地；运行时整体仍以手写 MSL 近似为主 | 补 typed shader defaults、preprocessor/translation/compile、通用 provider consumer、nested target 和更多 pass。现有 strict backend 不代表 official generic shader 或 Windows pixel parity |
| local deformation | Foliage/Water/Shake 等有不同程度近似 | 以 [Effects 全集](effects-reference.md) 的输入、空间和 mask 合同替换 |
| live values | format 21 binding program；per-surface snapshot 与原子 state 已由 layer alpha、solid color、exact Local Contrast strength 和 stock Opacity direct alpha consumer 执行；其他 target 仍重建，Timeline/SceneScript 未接入 | 下一高覆盖 target 必须同批接 compiler、consumer、原子 fallback 与 identity 门，再接 Timeline/SceneScript/audio/media |

## 12. 验收要求

通用 effect graph 至少需要这些确定性测试：

1. texture slot 保留 `null`，绑定身份和 resolution 正确；
2. 单 pass、ping-pong、多尺寸、多 format RT；
3. `previous`、original、scene compose、named target 和 history 互不串用；
4. copy/swap 在 command 顺序内执行、command 不占 material ordinal，且没有同纹理 read/write hazard；
5. raw `unique` 只控制实例身份；history 由数据流判定并在 resize/switch/stop 后清零；
6. optional texture 缺失时 combo 关闭，资源出现后选择正确 shader variant；
7. 未声明/默认关闭 effect 不创建 pipeline 或 RT；
8. strict chain 遇到 unsupported stage 时整链保持可诊断失败关闭，不合成任何前段结果；通用 graph 后续若采用 passthrough，也不得改变后续 effect 顺序；
9. 同一输入、时间、随机种子下，实时捕获和离线 readback 结果一致。
10. Shader source/raw hash/canonical identity 稳定；路径逃逸、无效 UTF-8、畸形 annotation、缺 stage 和重复 identity 明确失败，且 source contract 不被误报为 compiled/executed。
11. 多 effect chain 保持作者顺序、固定 effect 内 `previous`、effect 间 final output 推进、一次 layer alpha/mask/UV，以及整链 allocation/LRU/最终合成原子性。
