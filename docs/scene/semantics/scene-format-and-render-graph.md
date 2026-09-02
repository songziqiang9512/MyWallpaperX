# Scene 格式与 Render Graph 语义

> 目的：把 Scene 从文件实例解释为可执行图，而不是按 effect 名称选择近似动画。
>
> 证据边界：作者行为以官方文档为准；序列化字段主要来自真实 Workshop 样本和开源解析器交叉验证，不是官方稳定 schema。
>
> 格式与 graph 实现基线、当前 45 样本完整快照门与固定 13 样本回归门、签名 App 身份及聚合缺口统一见 [运行证据索引](runtime-evidence-index.md)；本表不复制基线 commit，避免随代码演进失真。文内出现的 commit 号是该项能力的**历史落地提交**，不是当前基线。

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

历史 R2 批次在既有 `SceneResourceView` 上为 shader 建立完整候选 source graph：package、loose 与 stock 候选各自保存 provenance/content identity，stage root 与 include edge 共用路径安全、冲突、缺失、循环和预算诊断；这些结构继续作为现役底座。raw ShaderContract projection 来自更早的 R1 历史批次，source graph 不能反向改写它或扩大 GPU admission。package -> loose -> stock 顺序是 MyWallpaperX 的明确 VFS policy，不是已经证明的官方所有客户端版本优先级；R1/R2 只说明来源，不构成当前迁移顺序。

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

### 2.3 版本是独立声明事实

project 与 scene 的 version 现在分别保留为 missing、合法整数、类型错误或越界事实，并记录各自 provenance。两者不会被折叠成一个猜测的 effective version，也不会自动注入默认、macro 或 compatibility patch。只有现役文档、合法跨版本资产或 clean-room 运行证据能证明某条版本规则时，才允许把它登记为公共 normalization；未知形态继续失败关闭。

## 3. `scene.json`

### 3.1 `general` 与 `camera`

高价值字段分组如下。字段名来自样本观察，行为描述由官方文档交叉验证：

| 分组 | 观察字段 | 语义 |
|---|---|---|
| 画布/投影 | `orthogonalprojection.width/height`、`fov`、`nearz`、`farz` | 作者画布和相机投影，不等同目标屏幕尺寸 |
| 清屏 | `clearenabled`、`clearcolor` | Scene 自己的清屏背景；露灰通常意味着构图或 camera cover 错误，不应靠强制拉伸掩盖 |
| 相机 | `camera.eye/center/up`、`zoom` | 2D/3D view 基础 |
| Camera Parallax | `cameraparallax`、`amount`、`delay`、`mouseinfluence` | 只有显式开启才根据鼠标移动相机；逐层 depth 再控制参与量 |
| Camera Shake | `camerashake` 及 amplitude/speed/roughness | 作者显式开启的场景级相机行为；当前项目只准入有合法 authored projection 的 2D orthographic 子域，与对象 Shake effect 不同 |
| 后处理 | `bloom`、Bloom/HDR 参数、`hdr` | Scene 全局后处理，不应塞进每个对象的 effect stack |
| 环境 | ambient/skylight、gravity、wind | 供 lighting、particle、puppet/physics 使用 |

官方 Camera Parallax 规则：场景先显式开启，每个 layer 才出现 parallax depth；某轴为 0 时该轴不移动，两个轴都为 0 时该层不参与。背景需要作者预留 overscan，否则相机移动会露出 clear color。播放器不应擅自放大所有场景来“修复”作者本身的边缘构图，但应正确实现 cover/crop 和作者画布。

官方 2.8.42 的 Scene Camera Shake 由 `general.camerashake` 独立 author gate 控制，并在 base/default/path camera 之后、共享 view 与 Camera Parallax 之前给 camera eye/center 加同一位移。orthographic 分支只产生 XY 位移，幅度以 authored `orthogonalprojection.height` 为基准；真正的 perspective Scene 使用另一套 XYZ 合同。MyWallpaperX 当前只执行可静态证明投影尺寸与参数范围的 orthographic 子域，缺失、畸形或 perspective projection 保持失败关闭；particle 的 perspective flag 只选择后续投影，不另算一套 shake。

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
  version?
  replacementKey?
  name? / description? / group?
  performance? / preview? / editable?  // editor metadata, not execution identity
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
  functions{}? (named registry)
    <name> { action, fbos[] }
  gizmos? / extraFields
  unknownFieldPaths[]
```

实例 material pass 只与 definition 中的 material pass 按 ordinal 对齐；copy/swap 等 command 不消耗该 ordinal。v15 按上述合同保真保存定义，v16 在不猜测未知字段的前提下把它编译成 authored graph。

`Almamu/linux-wallpaperengine` 的 `EffectParser.cpp:19-114` 可交叉确认 `name/description/group/preview`、dependencies、ordered passes、material/bind/command/source/target，以及 FBO `name/format/scale/unique` 这一通用子集。它不解析 `compose`、conditions、functions、gizmos、clear、fit、absolute extent 或 UV；这些扩展字段仍来自合法样本/WE-compatible assets 的 B/C 级观察，不能因第三方 parser 缺失而从 IR 删除。该源码树也不附带 stock effect definitions，因此不能校验每个 effect 的具体参数和 pass 数。

Wallpaper Engine 2.8.42 的 64 位官方客户端静态 parser 进一步确认：FBO 集中读取 `conditions/format/scale/width/height/fit/unique/clear/uvs`，pass 集中读取 `conditions/command/source/target/compose/material`，pass 内 material 引用另带 `index/conditions`，definition function 则按名称读取 `action/fbos`，并区分 `rgb_backbuffer/rgba_backbuffer`。`repeat` 是已观察的 FBO `uvs` 取值，不是 function 字段。condition 在对应 FBO、pass 或 material 引用纳入结构前求值；`command` 与可选 `source/target` 保持独立字段；`compose:true` 设置独立状态并增加 compose 参与计数。

后续 resource prepare/executor 静态链补足了实现形状：缺省 FBO extent 来自 layer，显式 `width/height` 覆盖，`fit` 保持比例限制长边，`scale` 再作为 allocation divisor；非-unique FBO 走 name/extent/format cache key，`unique:true` 把 effect identity 纳入 key。四分量 `clear` 在 create/resize prepare 后执行，不是 frame executor 的逐帧 clear；`uvs:"repeat"` 会改变底层创建 policy，但 exact sampler address mode 仍未闭合。ordinary/copy/swap 为不同节点路径，swap 改写后续 logical index，effect resize/reprepare 不复位 mapping、effect reparse 才复位；compose 在 pass 后推进 layer-local full-frame pair。copy 的 exact pixel primitive、ambient-input/alias 结果、clear 的颜色解释和 device-loss history 仍未知，方法与限制见 [官方客户端运行机制静态取证](client-runtime-static-forensics.md)。

对安装目录 `assets/effects` 的结构化交叉扫描按“含字段的 `effect.json` 文件数”统计（包含 preview 副本）：`copy` 3、`swap` 2、`compose:true` 2、`unique:true` 5、`clear` 2、`previous` 22。Motion Blur 提供 `copy source -> target` 与 unique FBO 的代表形状，Fluid Simulation 提供 velocity/dye RT 的 swap 及多个 unique/clear RT，Refraction 提供 `compose:true`；这些资产可约束 authored graph 保真，但 preview 重复项不能当成独立实现样本。

### 5.1 显式启用

effect 只有在对象 `effects[]` 引用对应 `file` 且实例 `visible` 没有解析为 false 时才进入候选图。随后还要应用用户属性、Timeline 和 SceneScript 的动态状态。播放器支持某种 effect 不能成为启用条件。

### 5.2 Ordered passes

pass 顺序是执行合同。典型类型：

- 单 pass：source + optional mask -> output；
- ping-pong：downsample -> horizontal -> vertical -> combine；
- layer-local compose：先把 layer 自身的 base content 写入双缓冲 current，再按 ordinary pass/effect boundary 推进 current；需要 scene background 的效果必须由独立 provider 显式满足；
- stateful：本帧输入 + history RT -> 新 history -> final combine；
- command：显式 copy source -> target 或 swap 资源 identity/handle，不运行 material shader，也不消耗 material ordinal。

### 5.3 `previous` 不是“当前屏幕”

`previous` 不是“已经画到屏幕上的内容”，也不是任意上一 pass 的 target。2.8.42 的逐 pass 路径表明它读取 layer-local pair 在该 pass 执行时的 current：没有 raw compose 时，同一 effect 内 current 不变，因此所有 `previous` 都仍是 effect-start input；某个 ordinary `compose:true` pass 成功后 current 才推进，后续 pass 的 `previous` 随即读取新成员；effect boundary 再把最终 output 交给下一 effect。它与以下资源都不同：

- 原始、未处理的 layer texture；
- 已经绘制到 Scene 的下方背景；
- `_rt_FullFrameBuffer` 一类 scene alias；
- 其他 layer 发布的 named target；
- 当前 effect 私有 ping/pong RT；
- 上一帧 history RT。

把这些资源都绑定到同一个 framebuffer 会产生重复背景、错误反馈和整屏污染。

### 5.4 `compose`

官方 Refraction 的视觉语义可能另需 scene background，但 raw `compose:true` 本身不创建或选择该 provider。2.8.42 的有界执行链确认它是 layer-local 双缓冲调度标记：至少一个 effect active 时，layer 按 active effect 与已纳入 compose transition 的总数选择初始 current，把 layer 自身的 base content 只渲染一次到该成员；每个 effect 写另一成员，并在 effect 边界把 effect output 交给下一个 effect。

raw 标记只附着在 ordinary material pass。该 pass 的缺省/负 full-frame 输入读取当时的 current；只有 pass 实际执行后才在同一 effect 内把 current 推进到刚写入成员，下一 pass 随即观察新内容。condition-false 结构在 pass vector/count 形成前已被排除，copy/swap/function 也不会推进 pair。链结束后最终 current 进入 layer final-output 与普通 compositor 路径。`_rt_FullFrameBuffer` 受另一 effect flag 控制，不能因看到 raw compose 就绑定 scene background。

项目的通用实现因此应表达“base capture 一次 + effect boundary + compose ordinary-pass boundary + final publication”的 typed transaction，而不是为 Refraction 或某个样本建立专用背景抓取。clear/alias 的 exact 像素语义、独立 ambient flag 的作者含义与跨版本差异仍保持 fail closed。

### 5.5 copy 与 swap

Motion Blur 等定义含显式 `copy source -> target`，Fluid Simulation 定义含成对 `swap`；项目当前 typed command 合同分别按像素复制与 logical resource identity 交换执行，且两者都不消耗 material ordinal。

官方客户端 executor 已把两者的结构区别闭合：

- `copy` 激活 source render target，调用 target 的专用 copy operation，再恢复 source；不运行 material；
- `swap` 要求 source/target 都能解析，然后交换存储在 effect runtime pass records 中的所有非-swap source、target 与 bind resource index；不复制像素，也不运行 material；
- pass 按 authored index 顺序执行，所以 swap 后的节点立即读取新 mapping；mapping 存在于持久 runtime records 中，后续帧再次执行 swap 可形成 ping-pong/history identity rotation；
- 未知 command literal 不产生第三种 command enum，而会落回 ordinary-pass shape。MyWallpaperX 对未知值应 fail closed，不复制这种宽松降级。

这支持项目当前“copy 是内容操作、swap 是 logical mapping 操作”的 typed IR。仍须用自有正反 fixture 验证 exact copy primitive、read/write 可见点、allocation scope、UV/color、clear/reset、condition 与 alias hazard；静态结构不等于已证明完整像素等价。

### 5.6 Condition 是图准入条件

2.8.42 客户端的 Ghidra 静态执行路径确认，condition 在受影响 pass/FBO/bind 纳入执行图之前求值。目标执行合同：

- 不满足条件的节点不分配 RT、不构建 material，也不留下部分 texture binding；
- 合法 condition 以 array 保存；元素 object 的 key 是 combo identity，value 可为直接数值相等比较，或带数值和 `ge/gt/le/lt` 的比较 object；有效条目共同决定准入；
- 缺少 combo key 时 2.8.42 的数值入口取零，但非 array、非 object、错误类型和跨版本默认不是可复制的宽松合同，项目必须在 typed AST admission 时 fail closed；
- condition 改变时，graph identity、resource allocation 与输出切换必须是同一事务。

### 5.7 Definition function 与 shader `[PASS]` 不是 graph pass

definition function 是按名称登记的显式调用目标，不是逐帧自动 command。当前闭合的 action 只有 `clear`：parser 把 `fbos` 名称解析为已有 target identity，运行时收到 function 名称后按声明顺序逐个激活、clear、恢复。没有证据把它自动绑定到 create、resize、frame 或 compose；未解析 action/target 继续 fail closed。

shader `// [PASS]` 又属于 shader frontend metadata，不占 effect material ordinal。2.8.42 当前能验证的 token 只有 `shadow`，并与 3D shadow-caster 路径对应；官方 [Shader Variables](https://docs.wallpaperengine.io/en/scene/shader/variables.html) 只公开 `[COMBO]`，没有公开任意 `[PASS]` token 或 2D schedule。现役 bounded 2D material executor 因此只保真携带 metadata，遇到 active `[PASS]` 时拒绝执行，不能把它猜成额外 ordinary draw。

## 6. Render target 与生命周期

| 属性 | 执行含义 | 错误实现的后果 |
|---|---|---|
| `scale` | 相对 effect/source 尺寸分配 RT | blur kernel、texel size 与性能均错误 |
| fixed `width/height` / `fit` | 固定 simulation grid 或按约束 fit | ripple/fluid 状态尺寸不稳定 |
| `format` | R8、RG16F、RGBA 等数据语义 | normal、pressure、mask 精度和通道错误 |
| `unique` | 作者声明该资源需要实例唯一性；本字段本身不等于 history | 多 effect 实例错误共享；或错误常驻造成资源泄漏 |
| UV/wrap mode | repeat、clamp 或特定映射 | 云、水、glitter 出现切边或平铺错误 |
| named target | 供后续 pass/layer 精确引用 | provider 内容缺失或绑定到错误画面 |

资源注册表应以 `wallpaper + screen + object + effect instance + RT name` 作为身份基础。是否跨帧保留必须由 read-before-write、copy/swap、function/reset 和生命周期数据流判定，不能只看 `unique`。swap 直接改 runtime logical mapping，mapping 本身也必须进入 effect/reset generation；最终判为 persistent 的资源和 mapping 在 resize、壁纸切换、seek、停止和设备丢失时必须清理或重建。

当前内存 `SceneRuntimeInput` 继承逐帧 registry、binding program 与 ShaderContract，并保留 direct text content/point-size/color target。effect target table继续由普通graph admission和剩余bounded fallback消费；dynamic text 以 per-layer signature/generation 更新纹理，不塞进 effect graph。同帧 copy/swap 已有严格 plan/runtime；统一 node scheduler 可按 authored nodeIndex 在 Precise Blur 的两个 material node 之间执行一个 copy 或 swap，并把更新后的 logical texture mapping 交给后段 encoder；现役普通MaterialProgram/GraphExecutor与剩余bounded fallback可按作者顺序消费previous output、effect texture、scene time、pointer或effect-local RT；Shake、Foliage Sway、Water Ripple与Water Flow的已迁移profile不再拥有专用strict产品owner。classic primary named-provider不再由exact Clipping owner规划；现役共享binding允许任意已准入MaterialProgram的pass 0/slot 1消费一个primary `_a` hidden image graph，并沿acyclic、单活动依赖闭包依赖优先执行和发布effectful provider，最终author compositor顺序不变。author-disabled named alternative只有在active+inactive引用完整解释descriptor依赖集合时才不进入当前产品边；unexplained dependency、authoredDependencies、secondary、多活动provider、cycle、child与非image继续拒绝。其他dynamic variants、system/media/video、通用history/跨帧persistent、compose与Texture Variants仍未实现。

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

`Almamu/linux-wallpaperengine` 采用“shader default -> material -> effect override -> explicit bind”的优先级，这是一条 `third-party-reference-pattern` 结构佐证，但不证明官方语义或 MyWallpaperX 当前能力；仍需由官方公开合同、合法输入与黑盒结果逐类验证。

历史 **v22** 时点的 material resolver 与 frame registry 仍是两份分离的选择合同，尚无 material candidate -> frame selection 桥；该批只增加 direct text binding/generation，不改变 ShaderContract 或 strict adapter。现役 bounded Template/Program/GraphExecutor 已建立受限同代 resource selection 与执行桥，但 ordinary authored material 的通用 provider/backend 仍未闭合；当前事实统一见 §12 和[运行证据索引](runtime-evidence-index.md)，不能从 v22 叙事推断现役缺口或升级 generic shader/provider 能力。

### 7.2 Render state

blend、depth 和 cull 属于 material/pass 语义。未知 blend mode 不能无声回退 normal 后仍宣称支持；至少应 passthrough 并记录 `unsupported-render-state`。alpha 的 straight/premultiplied 关系要在纹理解码、effect RT 和最终 composite 三处一致。

`linux-wallpaperengine` 的 parser 在字段缺失或未知时分别回退 `normal`、`nocull`、`disabled`、`disabled`（`MaterialParser.cpp:39-56,73-127`）。这是 `third-party-reference-pattern` 的 fallback，不是官方默认值或 MyWallpaperX 支持证明；其 unknown enum 会记录错误后继续运行，项目边界只由现役合同与自身正反门决定。

### 7.3 Material resolution 与 value channels

2.8.42 客户端静态执行路径确认存在集中式 indexed resolver，联合处理 authored slot、user/system/provider reference、可选尺寸信息和 fallback。由此强化以下公共合同：

- sparse slot 和来源 identity 必须保留，不能压缩数组或只留下最终路径；
- `constantshadervalues`、动态 user values 与 shader metadata defaults 是不同 value channel；
- 缺失值会参考 shader metadata 的方向已有静态支持，但完整 override 优先级仍需合法资产与运行 fixture 确认；
- authored blend state 可能同时参与 GPU pipeline state 与 shader variant identity，planner 不能把两者彻底分离；
- 官方公开 material slot 仍是 0...7；客户端内部更大容量只作为内部事实，不扩宽兼容声明。

## 8. Shader 语义

官方文档确认 Wallpaper Engine 使用自定义 GLSL-like 预处理器，并可能转换为 HLSL。兼容层需要处理：

- `GLSL`、`HLSL`、`HLSL_SM40`、`HLSL_GS40` 条件；
- `texSample2D`、`mix`、`frac`、`saturate` 等跨语言宏；
- `[COMBO]` 及 shader annotation 驱动的 compile-time permutation；
- scalar/vector/color/UV uniform metadata；
- include headers 与 blending helpers；
- vertex attributes、varyings 和 fragment output；
- 每帧 built-in uniforms。

历史提交 `8474ace` 将这条链路的第一层 raw contract 写入 interpretation v19：对 authored vertex/fragment stage 保存完整 UTF-8 source、raw SHA-256、相对路径、include reference/line、annotation raw/structured value/marker/line、uniform/attribute/varying declaration、diagnostic 与 canonical SHA；精确 host built-in identity 使用无 stage 合同。路径穿越、shader root/stage/include symlink escape、无效 UTF-8、缺失 stage和重复 identity均 fail closed。严格JSON失败的annotation仍以raw source和`malformedAnnotation`诊断保存，不形成structured record；现役Template只允许跳过声明外、注释独占行的畸形`[COMBO]`，且root stage必须另有词法无条件、同名、除坏`options`外顶层字段完全相同的合法record。附着声明、conditional/conflicting/missing counterpart、其他fatal diagnostic、缺少必需combo/default或最终schema冲突继续失败关闭。这个历史 raw projection 是 line-based、loss-preserving 的 L1 source contract，不是完整 AST；当时还没有 include expansion、macro/permutation preprocessing、translation、stage link、compile、typed default consumption、uniform upload 或 GPU execution，后续现役能力见 §12。

历史时点 **R2** 在这份 raw contract 旁新增 bounded preparation，而不是改写它：source graph 可展开有界 include，directive evaluator 支持 object-like `#define/#undef`、条件栈与 relational/equality 分层的整数/布尔表达式；macro expansion 区分 code、string、character、line/block comment，selected/host macro 保留 defined/undefined 所有权。只有 active 非 directive 行贡献 annotation/declaration/diagnostic，输出 dependency digest、逐行 source map 与 prepared identity；exact `[COMBO]` 的数值以 Decimal-first exact Int64 carrier 保存，sampler readiness/requirement、explicit material value、active options 和 annotation default 进入带 provenance 的 typed variant。fixed-point 以词法无条件 root/include schema 为 immutable base，对最多 8 个条件候选穷举非空子集；多个 stable prepared signature 报歧义，候选数或估算累计工作超过 256 MiB 报审计预算。backend/version/platform/texture-format macro 仍是 host-owned requirement；当时 Metal backend 没有 verified provider，function-like/cross-language macro/prelude、`#elif`、directive-line annotation、完整 shader translation 与 stage execution 也未实现。

该 R2 时点的 prepared program 另有显式 input/output color representation carrier，但普通 authored pass 标为 unresolved；如果旧 raw frontend 本来失败，prepared source 即使成功也会以 `shader-color-contract-unproven` 关闭，不能扩大 renderer 准入。若旧 raw frontend 本来成功，R2 preparation failure 只作为诊断，不缩小原有 accepted subset。这段只解释历史迁移边界，不是现役开发顺序。

历史时点 **R3** 在这条 handoff 上建立独立 `SceneResolvedMaterialTemplate -> SceneResolvedMaterialProgram` 边界：Template 固定保存 `0...7` 八槽及 hole、低到高 candidate provenance、combo/uniform/state 与 exact graph role；Program 只能从一个 validated frame/resource/dynamic snapshot 形成，把 request/candidate/content generation、purpose/content/physical/mapped/UV/sampler、active variant/reflection、uniform bytes、typed state 和保守 color transfer 共同写入 semantic/exact identity。只有 exact provider 显式 `absent` 可跳过较高优先级候选，missing/pending/unavailable/incomplete 或未证 purpose/state/color 均失败关闭；`material` annotation 只作 lookup key，不是 purpose。当时 production bridge 只做 CPU 审计并固定 `gpuEncoded=0`；这描述的是 R4 接管前的历史状态。现役 bounded Program/typed adapter 已由唯一 GraphExecutor 消费，当前边界统一见 §12 和[运行证据索引](runtime-evidence-index.md)，但这仍不证明 ordinary authored shader 已有通用 backend。

历史提交`136d35c`没有改变上述通用结论。它当时只在stock Local Contrast strict planner中核对三份authored shader contract的identity、canonical SHA、stage path、raw SHA和source SHA，再调用项目内手写MSL；Gaussian `scale=(1,1)`与combine `strength=1`的缺省值只在这个exact profile内解释。该旧路径不预处理、翻译或编译authored source，也不建立通用uniform binder；其planner与手写产品backend现已删除。

历史提交`b541867`同样没有改变上述authored shader边界。它当时只按作者effect顺序组合已由strict planner接受的手写backend，并验证layer source -> effect output的输入连续性；每个Local Contrast stage从同一per-surface snapshot单独取得strength。这个旧scheduler不读取任意shader source，也不执行copy/swap/compose/history/condition/function。现役exact stock四节点图改由source-proven MaterialProgram、GraphTargets与GraphExecutor执行，typed strength仍由通用snapshot供给；当前owner与运行边界见[E-V1-LOCAL-CONTRAST-SHARED-OWNER](runtime-evidence-index.md#e-v1-local-contrast-shared-owner)。

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
| Scene Camera Shake | scene `camerashake` | shared scene camera | absolute scene time、amplitude、roughness、speed、projection | 作者开启时给全场共享 camera eye/center 加同一位移；不替代任何局部 effect |
| Depth Parallax | explicit `depthparallax` effect | effect-local UV | depth map、pointer/parallax position、可选 mask | 按 depth 重采样；高质量模式有多层 raymarch |
| Effect Shake | explicit `shake` effect | effect-local UV | flow、time offset、opacity mask、可选 audio | 只在 mask/flow 指定区域变形 |
| Swing/Foliage/Water | explicit effect | effect-local UV 或 vertex | region/mask/noise/flow/normal | 服从作者局部区域，不修改对象 transform |

这些机制不能合并成一个“鼠标移动/正弦位移”开关。

## 10. 建议的通用执行顺序

下面是基于官方行为、真实样本和两个可审计实现归纳的 MyWallpaperX 目标 IR；其中 raw pass 的最终默认细节仍需更多官方 assets 验证：

```text
for object in authored source order:
  resolve parent visibility + object state
  update/create base resource
  draw base object into object working texture

  for effect in authored order where resolved visible:
    evaluate node/FBO/bind conditions before allocation
    allocate/reuse effect instance RTs
    for pass in authored order:
      resolve shader variant and render state
      resolve authored/provider/default value channels without compacting holes
      update each slot's metadata from the final texture candidate/generation
      execute compose/copy/swap/material node to declared target
      publish named target; keep this effect's previous fixed

    advance effect-chain input to this effect output

  composite final object output into scene target

apply scene post processing
present or read back
```

当整条 effect route 精确为 `.unclaimed` 时，当前产品还有一条与上述 effect graph transaction 分离的 source-stage 故障隔离路径。它只在不存在已授权/可执行 typed dependency、source-copy、frame target 或 final-alpha，exact static-file 或 current-media publication atom 完整，layer color blend 属于现役共享范围，且有限 authored quad 与 viewport 有正面积交集时，才把原始 source 按作者几何交给普通 final layer compositor。作者 alpha/tint/brightness 由现役 `sourceFragmentUniforms` 消费；normal blend 直接合成，非普通 blend 先用既有 offscreen source capture 应用样式，再由同一个 `SceneLayerColorBlendPipeline` 与主 target 合成。alpha 为0仍编码但对背景零贡献；不支持的 blend 继续拒绝。coverage/opacity 资源默认阻断；已证例外是 exact stock Pulse 单 pass 在 `PULSEALPHA=0` 时，以及严格 stock identity 准入的 Water Waves 单 pass 在 `TIMEOFFSET/PERSPECTIVE/DUALWAVES` 缺省/0 时。Pulse 可选 mask 在 alpha 分支关闭时不改变 source alpha；Water Waves slot-1 mask 只是被跳过 effect 的 effect-local 位移输入，不是独立 opacity/final-alpha law，本降级不声称 effect 输出与 raw source 逐像素 coverage 恒等。`PULSEALPHA=1` 有无 loaded mask、非法 pass/path/combo、非 stock Water Waves identity 或 combo 及任一 typed Opacity entry 仍阻断。visible authored dependency edge 还会同时阻断 static-file provider 与 consumer，hidden/self 不阻断；唯一 X-Ray consumer 端豁免由 current stock 与 exact historical stock 两条公共资源身份授权。每条身份都把完整 typed definition variant、唯一 typed material pass、root-stage canonical identity 及 VFS sourceGraph dependency/唯一 stock `common_blending` include 原子闭合，digest 只校验登记资源内容而不按 sample/layer/hash 选择算法；historical 身份不进入 current execution planner，只允许 consumer 显示自己的 base source。实例还必须只有一个真实存在的非 self provider，全部跨层输入精确等于 slot-1 provider composite；provider 端仍一律阻断。current-media 保留先前独立审查的 authority。该路径不执行 effect、不发布 `effectOutput`、不消费 authored dependency，也不把任何已执行前缀当作可恢复输出；记录 `degraded-layer-source-passthrough` 并强制 benchmark 为 NON-PASS。当前 strict fallback 仍按整条 claimed chain 原子失败，这是现役实现事实而不是新通用 graph 的验收不变量；V0/V1 必须把普通路径的失败半径收窄到 effect/pass/真实依赖子图，恢复进入该 effect 前的 previous current，并继续无关 layer suffix。现役真实 style cohort 与透明反例见 [E-V4-AUTHORED-LAYER-STYLE-SOURCE-PASSTHROUGH](runtime-evidence-index.md#e-v4-authored-layer-style-source-passthrough)；较早 `2241938645:68` 与 `1636394814:195/24` 仍只证明各自登记的基础 source/X-Ray 边界。

HDR、video HDR 和 display-output 等最终路径应拥有 typed output-mode/transfer identity，不能隐含为一个统一 framebuffer conversion。

## 11. 二进制资产合同（TEX BC 与 Puppet MDL）

除下述明确标为官方客户端静态路径的项目外，序列化细节均属“真实样本 + 第三方播放器解释”证据，不是官方 schema；任何超出已验证形状的数据必须 fail closed。

- **TEX V5 writer/consumer 与动态采样状态**（2.8.42 官方客户端静态路径）：`resourcecompiler64.exe` 的同一策略入口按类型读取 `format`、`nointerpolation`、`clampuvs`、`nomip` / `halfmip`、image/sprite sequence、crop/resize 与 `slice3d`；`nomip` 会转换成内部“生成 mip”的反向状态，字段名不能直接映射成 container bit。writer 固定组织 `TEXV0005 -> TEXI0001 -> TEXB0004`，仅有序列元数据时追加 `TEXS0003`。64 位主程序 V5 consumer 走 chunk loop 并按 TEXI/TEXB/TEXS marker 分派，V4 走旧式直接 handler。运行中的 `nointerpolation/clampuvs` 另由 image-layer property 注册，支持 bool 与 `{value: ...}`，分别写入 filter/address 状态；两个 descriptor 的直接 callback 均为 null。resource preparation 把 TEX subtype 与 layer state 折叠为 sampler policy：`nointerpolation` 选择 D3D11 point，否则为 min/mag/mip linear；`clampuvs` 选择 U/V/W clamp，否则为 wrap。完整状态字及额外位进入 sampler cache key，cache miss 才创建，随后按 material slot 绑定；其他 sampler 位仍有额外分支。动态 property 写入如何保证 resource reprepare、mip/边缘像素、Metal 等价与 Windows sampling golden 仍未闭合。
- **TEX BC 存储与用途**（`8bac86e` + 2.8.42 sidecar/TEX 相关性）：TEXI format 4/6/7 分别描述 BC3/BC2/BC1 存储，块网格按存储尺寸（4 对齐 padding）持有，作者内容尺寸在 TEXB `imageWidth/imageHeight`。但 numeric format 4 同时承载普通 `dxt5` 颜色与 packed-normal `dxt5n`，所以格式不能单独决定处理。明确为 **color** 的 BC 块存 straight alpha，在当前 premultiplied source-over 合同下需要解码、裁剪并按 color purpose premultiply；**data/normal** consumer 必须保留 packed 通道并跳过颜色预乘/色彩转换。BC5（format 5）也是法线存储候选，但不能据此反推所有法线只会使用 format 5。cache key、upload、sampler 与 shader variant 都必须包含 resource purpose 和 physical/mapped metadata。
- **TEX 3D LUT 有界资源接入**（`fdf36e6b`）：2.8.42 审计记录的 LUT 变体在常规 TEX header 后多一个 depth；当前随包 28 个 `assets/materials/lut/*.tex` 均为 `TEXV0005/TEXI0001/TEXB0004`、format 0、texture 32×32×32、image 1024×32、单 image/单 mip、free-image format 13、零 metadata，payload PNG 实际为 32×1024 的纵向 32-slice atlas。共享 reader 只在 marker 位于 offset 50 且完整 profile/预算一致时保留 header/mip depth；`.lookupTable` loader 将逐 slice RGBA 上传为 Metal `.type3D/.rgba8Unorm`，普通 2D purpose/candidate 明确拒绝 volume。项目自有 2×2×2 fixture 锁定全部 voxel 顺序，stock corpus 只锁资源形状与同一路由；`ccsimple.frag` 的 `sampler3D` 仅证明后续 consumer 类型方向。本批不实现 material slot、LUT sampling、颜色空间或 Color Grading 效果连接，也不构成 Windows 数值/像素等价。
- `b9bdbd5e` / `226ea5f7` 把 `8b06538d` 只服务 strict REFRACT 的用途合同扩展到共享 `SceneTextureLoader` 并让 data image 严格 fail closed；`d432d4d5` 再把 cache/upload identity 穷举为 `premultipliedColor`、`straightAlbedo`、generic `preservedChannels`、`mask`、`noise`、`flow`、`phase`、`normal`，`b623f421` 新增 Depth Parallax 专用 `depth`。现役专用Effect辅助纹理调用已收敛为29个并显式传入purpose：mask 15、noise 6、flow 1、phase 1、normal 1、depth 1、generic preserved 2、X-Ray straight albedo 1、premultiplied Blend color 1；Water Flow不再计入专用调用。非预乘用途各自 cache 稳定、跨 purpose identity 分离；preserved/data用途仍按严格 source-channel policy 上传，direct/embedded data image只在原尺寸、无 decode 映射、integer packed、明确非预乘 alpha 或无 alpha（skip）且32-bit byte order受控的RGB(A/X) provider可归一为RGBA时直通。`.straightAlbedo`另只允许effective TEXB0003、完整mip/payload与decoded extent证明JPEG、authored physical=mapped且CGImage无alpha的单图按既有4096预算等比缩放；authored padding、TEXB0004 metadata伪装、带alpha、格式冲突与其他data purpose不继承该例外。`378e68e7`曾为旧Water Flow flow/phase与Standard Blur mask建立共享`SceneTextureCandidate`；现役Water Flow已删除专用loader/slot owner，作者flow与exact stock phase改由普通material asset catalog/publication及Program消费；`de5f01b6` 又接入 static plain base image 与 bounded distinct REFRACT normal；`d87de042` 再让同一 static base candidate 在 direct、inline、offscreen 与 authored-effect 路由都经过最终原子校验；`b623f421` 复用同一原子携带 slot 1 R8 depth。尺寸模型明确区分 header extent、首 mip/encoded physical、实际 Metal texture 与 mapped content：raw/BC 仍要求首 mip对齐 header；已验证 TEXB0003 embedded PNG/JPEG 可为 encoded=decoded=mapped、同时不同于 header，且全部 mip/payload/format 必须逐项对账；上述opaque JPEG缩放候选以实际Metal extent作为physical/mapped并使用identity UV。candidate physical 始终记录实际 Metal texture；base 只消费 static single-image non-sprite、identity RGBA8 linear-clamp candidate，但可作为已支持 Effect/offscreen 的 base 输入；REFRACT normal 只消费 distinct static single-image non-sprite format 0/4，Depth Parallax 只消费 R8 `.depth` 与 axis-aligned mapped UV，其他形态保持 legacy 或失败关闭。自动门覆盖Water Flow stock phase publication、作者loose覆盖与普通Program运行，另覆盖Standard Blur padding、fractional premultiplied base、opaque JPEG straight-albedo预算缩放及padded/mislabeled负例、effectful base 正负 GPU split、mapped REFRACT normal、Depth mapped R8、错误 purpose/identity/UV/sampler/Metal contract、BC/raw purpose 与 particle coverage；定向门见 [E-EFFECT-TEXTURE-PURPOSE](runtime-evidence-index.md#e-effect-texture-purpose)、[E-TEXTURE-CANDIDATE](runtime-evidence-index.md#e-texture-candidate)、[E-V1-XRAY-OPAQUE-JPEG-ASSET-PUBLICATION](runtime-evidence-index.md#e-v1-xray-opaque-jpeg-asset-publication)、[E-V1-WATER-FLOW-GRAPH-OWNER](runtime-evidence-index.md#e-v1-water-flow-graph-owner)、[E-EFFECT-DEPTH-PARALLAX](runtime-evidence-index.md#e-effect-depth-parallax) 与 [E-PARTICLE](runtime-evidence-index.md#e-particle)。format 5 / BC5、effectful/nested/child provider、generic Effect/material DXT5n、Windows golden、动态 generation/cancel、sprite rotation、clamp-border 与通用 material slot 仍未闭合。
- **Puppet MDL mesh block**（`8bac86e`及2026-09-02版本扩展）：MDLV0016/0017/0021/0023，marker 9 字节；首个 `MDLS` 偏移为 mesh 搜索上界。块形状为 `u32 vertexBytes` + 顶点 + `u32 indexBytes` + uint16 三角形索引；0016只接受已核验stride 52，0017/0021/0023只接受80或84，position是块内偏移0的3个float，四bone index/weight位于`stride - 40/-24`，UV是stride尾部8字节。判定条件 `max(index) == vertexCount - 1` 对同一version的候选stride数学互斥，天然唯一。加载时按层声明size归一化顶点并重组图集为bind-pose纹理；静态0016可按exact source/atlas/size复用，animated target不复用。
- **MDLS / MDAT 静态 attachment**（`49ee89a`）：受限 reader 只接受已验证的 `MDLV0023 + MDLS0004 + MDAT0001`。MDAT 条目为 `u16 boneIndex + name\0 + 列主序 4x4 attachment-local matrix`；沿 MDLS parent hierarchy 求 bone world 后乘 attachment local，再用 `F * M * F`（`F = diag(1,-1,1,1)`）转为 Scene bind frame。child transform 顺序为 `parentWorld * attachmentSceneBind * childLocal`；非法 bounds/count/parent/bone/name/matrix、parent model 无同名 attachment 或运行时 frame 非 16 个有限 float 均 fail closed 到普通 parent transform并输出诊断。
- **MDLS skin / MDLA 动画**（`2be2b44`、`f1ee79b`、`0892e74b`及2026-09-02版本扩展）：受限reader只接受已验证的 `MDLV0016 + MDLS0002 + MDLA0003`、`MDLV0017 + MDLS0002 + MDLA0004` 或 `MDLV0023 + MDLS0004 + MDLA0006` version pair。52/80/84-byte record的四bone index/weight均按`stride - 40/-24`读取，每顶点权重必须有限、非负且和为1。MDLA每个bone track保存`frameCount + 1`个完整TRS；局部矩阵顺序为`T * Rz * Ry * Rx * S`，层级world后用`animatedWorld * inverse(bindWorld)`做normalized four-weight LBS。当前消费`loop`、blend=1、无blend-in/out的单个non-additive clip（rate可为有限正作者值），或rate=1、全部additive、首帧逐bone贴合bind pose且driven-bone集两两不相交的clips；绑定visibility通过typed per-frame snapshot激活。MDLA0003 per-bone auxiliary scalar只严格验证并丢弃；冲突bone、混合opaque/additive、非bind reference、插值、动画attachment follow、constraint/IK/physics均未执行并回退bind pose。

- **2026-09-02 straight-albedo 现役更正**：上方JPEG-only缩放边界已被共享candidate正反门扩为source-proven opaque embedded JPEG或RGB PNG；仍要求effective TEXB0003、完整逐mip magic/decoded extent、authored physical=mapped且CGImage无alpha。带alpha PNG、padding、TEXB0004、格式/extent冲突及其他data purpose不继承；实际Metal extent仍同时作为physical/mapped并使用identity UV。见[E-V4-OPAQUE-PNG-STRAIGHT-ALBEDO-AND-ACTIVE-READINESS](runtime-evidence-index.md#e-v4-opaque-png-straight-albedo-and-active-readiness)。

## 12. 当前 MyWallpaperX 映射

| 层级 | 当前状态 | 下一合同 |
|---|---|---|
| Scene/object IR | format 25 继承 v24 attachment frame，并增加 authored Puppet `animationlayers` 的 id/animation/additive/blend/blend-in/out/time/rate/static-or-bound visibility；bounded runtime 消费 disjoint-bone additive 与 typed visibility | 保持 raw/typed 双层合同；保存声明不等于支持冲突 mixing/权重、SceneScript visibility 或动画 attachment |
| base image color | 普通 image 与 solid 在进入 effect/color blend 前消费作者 `g_Color4 × brightness`；text 的同名字段留给 CoreText，避免双重着色；mode 31 继续执行既有 `A + B × opacity` | 动态 non-solid color binding、线性/显示色空间和 Windows SDR/HDR 裁剪 golden |
| dependency | graph 已结构化区分固定 `previous`、effect-scoped RT 和 copy/swap；十四类 strict backend 与 ordered chain 已消费 effect target table，并闭合整链 identity/continuity、allocation/cache/LRU 事务、末段合成与 reset；Precise Blur interleave、Shake/Foliage/Water/X-Ray/God Rays 链已执行。bounded frame registry按另一命名空间处理named target、property-authored fallback和受限PNG/JPEG property source；primary `_a` named-provider已由共享binding/current-frame publication/MaterialProgram/GraphExecutor执行static、backward、forward与acyclic单活动依赖的effectful nested image graph，旧Clipping专用capture/renderer owner已删除。secondary、多活动provider、未解释依赖、cycle/child/非image在binding前typed拒绝 | 继续在同一dependency/publication/Program/GraphExecutor主干补system/media/video/variant、secondary/multiple-active、真实persistent/history consumer、compose与更多经过合同门的topology；不得新建第二target/resource链 |
| material/shader | sparse-slot resolver、ShaderContract v1与R2 preparation已落地；R3又从production raw graph形成固定8槽Template，并在同代snapshot内原子形成provider publication、active variant/reflection、uniform/state/color及semantic/exact Program identity。R4已由唯一GraphExecutor执行bounded Program/typed adapter；B24删除缺`sourceGraph`时从raw stages伪造的`fallbackGraph`与`legacyContract` provenance。现役preparation只消费typed loader提供的package/loose/stock VFS graph；缺图稳定报`shader-source-graph-missing`，only-explicit-absent资源fallback与unknown fail-closed合同保持 | R5/B25已删除剩余observation与明确不可达的旧执行surface。后续只在统一框架中扩展generic shader/resource/visual semantics；现有Program/strict backend、完整矩阵PASS或非黑都不代表official generic shader、Windows pixel parity或Wallpaper Engine视觉等价 |
| local deformation | exact stock Shake flow-map profile 为受限 `L3`；Foliage/Water 等仍有不同程度近似 | 继续按 [Effects 全集](effects-reference.md) 补 dynamic Shake、输入、空间、mask 与 sampler 合同 |
| live values | format 25 继承 binding program；layer alpha、solid color、direct text、Local Contrast/Opacity consumer 已执行；Timeline 的 **48/48** 现役 authored host 已进入受限 typed target/绝对时钟/作者 Bézier evaluator，并执行 9 条 Loop wrap 闭合段，覆盖 effect constant、layer alpha、bounded relative transform、root particle scalar、text width 与单一 default 2D camera Combined；Puppet animation visibility 的 direct User Property binding 编译为 typed bool target 并逐帧消费；通用 SceneScript 未接入 | generic Combined、其他 relative/target、multiple path/3D camera、Puppet SceneScript visibility 与 event crossing 继续 fail closed；Timeline 精确子项以 [覆盖台账 §6.1](coverage-ledger.md#61-timeline-与-scenescript) 为准 |

## 13. 验收要求

通用 effect graph 至少需要这些确定性测试：

1. texture slot 保留 `null`，绑定身份和 resolution 正确；
2. 单 pass、ping-pong、多尺寸、多 format RT；
3. `previous`、original、scene compose、named target 和 history 互不串用；
4. copy/swap 在 command 顺序内执行、command 不占 material ordinal，且没有同纹理 read/write hazard；
5. raw `unique` 只控制实例身份；history 由数据流判定并在 resize/switch/stop 后清零；
6. optional texture 缺失时 combo 关闭，资源出现后选择正确 shader variant；
7. 未声明/默认关闭 effect 不创建 pipeline 或 RT；
8. 当前 strict fallback 遇到 unsupported stage 时仍整条 claimed chain 可诊断失败关闭；source-stage 降级只输出已证明安全的精确 source 并保持 NON-PASS，不发布 effect 或伪造 partial-prefix 成功。exact Pulse 的 `PULSEALPHA=0` 局部 mask 正门、`PULSEALPHA=1`/Opacity 负门、strict-identity Water Waves effect-local 位移 mask 正门、current/exact-historical 双资源身份闭合且 provider 存在的 X-Ray consumer 端 provider-input 豁免、historical 无 execution owner 及 provider 端阻断，以及 visible 跨层 static provider+consumer 双端阻断必须同时保留。V0/V1 新通用路径的验收要求则是 effect/pass/真实依赖子图局部降级、恢复 previous current、继续无关 layer suffix，同时保持作者 effect 顺序和 target/publication hazard 安全；
9. 同一输入、时间、随机种子下，实时捕获和离线 readback 结果一致。
10. Shader source/raw hash/canonical identity 稳定；路径逃逸、无效 UTF-8、缺 stage和重复identity明确失败；畸形annotation保留raw/diagnostic，只有声明外comment-only `[COMBO]`能逐条证明其词法无条件合法counterpart同名且除坏`options`外顶层字段相同时才跳过，附着声明、conditional/conflicting/missing counterpart、其他fatal diagnostic与schema缺口仍失败；source contract不得被误报为compiled/executed。
11. 多 effect chain 保持作者顺序、固定 effect 内 `previous`、effect 间 final output 推进、一次 layer alpha/mask/UV，以及整链 allocation/LRU/最终合成原子性。
