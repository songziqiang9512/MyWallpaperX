# Scene 格式与 Render Graph 语义

> 目的：把 Scene 从文件实例解释为可执行图，而不是按 effect 名称选择近似动画。
>
> 证据边界：作者行为以官方文档为准；序列化字段主要来自真实 Workshop 样本和开源解析器交叉验证，不是官方稳定 schema。

## 1. 文件与资源层级

| 层级 | 常见内容 | 运行时职责 | 证据 |
|---|---|---|---|
| `project.json` | wallpaper 类型、入口文件、标题/preview、`general.properties` | 选择 Scene 入口并建立用户属性默认值 | B |
| `scene.json` / 同名入口 | `general`、`camera`、`objects` | 建立画布、相机、对象源顺序和作者状态 | B/D |
| `scene.pkg` / `gifscene.pkg` | models、materials、textures、particles、scripts 等虚拟文件 | 与 loose files 组成统一只读 VFS | B/D |
| model JSON | material、autosize、solid、crop、puppet | 定义可绘制资源与几何/角色关联 | B/D |
| material JSON | ordered passes、shader、texture slots、combos、constants、render state | 定义实际 draw pipeline | B/C/D |
| effect JSON | FBO、ordered passes、bind/target/compose/copy、dependency | 定义对象 effect 子图 | C/D |
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
    unique
    uvs / conditions?
  passes[] (ordered)
    material?
    target?
    bind[] { name, index }
    compose?
    command? = copy
    source?
    target?
  gizmos / editor metadata
```

### 5.1 显式启用

effect 只有在对象 `effects[]` 引用对应 `file` 且实例 `visible` 没有解析为 false 时才进入候选图。随后还要应用用户属性、Timeline 和 SceneScript 的动态状态。播放器支持某种 effect 不能成为启用条件。

### 5.2 Ordered passes

pass 顺序是执行合同。典型类型：

- 单 pass：source + optional mask -> output；
- ping-pong：downsample -> horizontal -> vertical -> combine；
- scene compose：先捕获该 layer 后方场景，再执行折射/混合；
- stateful：本帧输入 + history RT -> 新 history -> final combine；
- command：显式 copy source -> target，不运行 material shader。

### 5.3 `previous` 不是“当前屏幕”

在观察到的内置定义中，pass 常把上一 effect 或基础 layer 输出作为 `previous`。它与以下资源都不同：

- 原始、未处理的 layer texture；
- 已经绘制到 Scene 的下方背景；
- `_rt_FullFrameBuffer` 一类 scene alias；
- 其他 layer 发布的 named target；
- 当前 effect 私有 ping/pong RT；
- 上一帧 history RT。

把这些资源都绑定到同一个 framebuffer 会产生重复背景、错误反馈和整屏污染。

### 5.4 `compose`

`compose:true` 表示 effect 需要已合成场景作为输入。Refraction 是已确认的典型：先捕获 layer 后面的场景，再用 normal map 折射。它不能用 layer 自身 texture 或最终屏幕截图替代。

### 5.5 `copy`

Motion Blur 等定义含显式 copy，用来更新跨帧历史。省略 copy 或把它当普通 pass，会改变 read/write 顺序并形成同一纹理读写冲突。

## 6. Render target 与生命周期

| 属性 | 执行含义 | 错误实现的后果 |
|---|---|---|
| `scale` | 相对 effect/source 尺寸分配 RT | blur kernel、texel size 与性能均错误 |
| fixed `width/height` / `fit` | 固定 simulation grid 或按约束 fit | ripple/fluid 状态尺寸不稳定 |
| `format` | R8、RG16F、RGBA 等数据语义 | normal、pressure、mask 精度和通道错误 |
| `unique` | effect 实例私有、通常需跨帧保留 | 多实例串状态或 history 每帧丢失 |
| UV/wrap mode | repeat、clamp 或特定映射 | 云、水、glitter 出现切边或平铺错误 |
| named target | 供后续 pass/layer 精确引用 | provider 内容缺失或绑定到错误画面 |

资源注册表应以 `wallpaper + screen + object + effect instance + RT name` 作为身份基础。resize、壁纸切换、seek、停止和设备丢失必须清理或重建 history，不能让旧壁纸状态泄漏。

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
      execute compose/copy/material pass to declared target
      publish named target and advance previous when definition requires

  composite final object output into scene target

apply scene post processing
present or read back
```

## 11. 当前 MyWallpaperX 映射

| 层级 | 当前状态 | 下一合同 |
|---|---|---|
| Scene/object IR | format 14 已保留 camera、层级、effects、nullable slots、combos、typed constants | 补全 effect definition/FBO/pass command，而不只保留实例 override |
| dependency | bounded named target、clipping 和单静态 image provider 已执行 | 扩展为通用、可诊断 DAG，区分 scene compose 与 history |
| material/shader | 只解析 material metadata；运行时主要是手写 MSL 近似 | 先建统一 slot/combo/uniform/render-state executor，再迁移高频 effect |
| local deformation | Foliage/Water/Shake 等有不同程度近似 | 以 [Effects 全集](effects-reference.md) 的输入、空间和 mask 合同替换 |
| live values | 属性覆盖部分 target；Timeline/SceneScript/provider 未统一 | 建 typed target snapshot 和统一 frame context |

## 12. 验收要求

通用 effect graph 至少需要这些确定性测试：

1. texture slot 保留 `null`，绑定身份和 resolution 正确；
2. 单 pass、ping-pong、多尺寸、多 format RT；
3. `previous`、original、scene compose、named target 和 history 互不串用；
4. `copy` 在 command 顺序内执行且没有同纹理 read/write hazard；
5. `unique` 状态按 effect instance 隔离，resize/switch/stop 后清零；
6. optional texture 缺失时 combo 关闭，资源出现后选择正确 shader variant；
7. 未声明/默认关闭 effect 不创建 pipeline 或 RT；
8. unsupported pass 保持可诊断 passthrough，不改变后续 effect 顺序；
9. 同一输入、时间、随机种子下，实时捕获和离线 readback 结果一致。
