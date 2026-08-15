# Scene 兼容运行时架构

> 状态：现役长期架构合同
>
> 最近复核：2026-08-15
>
> 当前实现程度与缺口只查[能力台账](semantics/coverage-ledger.md)；本文件描述目标处理方式，不把目标冒充现役能力。

## 1. 产品目标

MyWallpaperX Scene 的首要目标是尽快让真实 Wallpaper Engine Scene 在 macOS 上得到可辨认、可持续改进的正确画面。长期仍保持 Swift + AppKit 产品宿主和 Swift + Metal 渲染底座，但不再把每个已知 effect、shader 表达式、脚本或粒子组合翻译成一条专用 Swift 产品路径。

目标只有一条执行主链：

```text
project / scene / package / texture
  -> 宽容解码 + loss-preserving IR
  -> 作者状态、属性、Timeline、脚本 mutation
  -> material / shader / effect graph 编译
  -> 统一 Program、资源绑定和 render state
  -> Metal GraphExecutor
  -> layer composition
  -> scene post process
  -> drawable
```

实施时按能够闭合真实画面的纵向切片扩展这条链。不得先分别建设完整 compiler、RenderGraph、VM、particle platform，再等待它们全部完成后才允许真实内容执行。

## 2. 证据来源及其边界

架构决策按以下证据强度裁决：

1. Wallpaper Engine 官方公开文档定义作者可见合同；
2. 固定版本、输入、环境、时间和事件下的官方客户端黑盒观察定义对应 bounded profile 实际发生的外部结果，不证明内部算法或其他版本；
3. 固定版本官方客户端静态取证补充未公开的职责、顺序和数据流，只能标为版本有界结构；
4. 当前 MyWallpaperX 代码与可复现运行证据决定已经实现什么；
5. MirageWallpaper 等第三方项目只提供 clean-room 结构对照，不能定义官方语义或像素结果。

官方公开合同当前明确支持以下架构判断：

- effect 可以附着于多类 layer、按作者顺序组合并跨 layer 连接；
- effect shader 使用 Wallpaper Engine 的 GLSL-like dialect，经自定义预处理、翻译和编译执行；
- SceneScript 基于 ECMAScript，网页 API 被移除并换成 wallpaper host API；
- Particle 由 General、Renderer、Emitter、Initializer、Operator、Child 和 Control Point 等组件组合。

资料入口：

- [Effects Introduction](https://docs.wallpaperengine.io/en/scene/effects/introduction.html)
- [Shader Programming Overview](https://docs.wallpaperengine.io/en/scene/shader/overview.html)
- [Shader Syntax Overview](https://docs.wallpaperengine.io/en/scene/shader/syntax.html)
- [SceneScript Introduction](https://docs.wallpaperengine.io/en/scene/scenescript/introduction.html)
- [Particle Systems Overview](https://docs.wallpaperengine.io/en/scene/particles/introduction.html)
- [官方客户端行为研究与一致性验证工作流](semantics/official-client-behavior-research-workflow.md)
- [官方客户端运行机制静态取证](semantics/client-runtime-static-forensics.md)
- [MirageWallpaper 固定 revision 静态研究](semantics/miragewallpaper-rendering-reference.md)

官方公开文档没有公开内部 RenderGraph。普通 material、FBO、copy、swap、compose、history、ping-pong 和 publication 的具体处理链来自 2.8.42 客户端静态取证及独立结构交叉检查，文档和实现不得把它们表述成跨版本官方保证。

当上述来源不足以决定当前纵向切片时，必须由官方客户端研究工作流控制问题范围、工具边界和实现交接。固定客户端静态观察只提供版本有界结构；对一个 bounded profile 的画面、事件、状态和失败结果是否一致，仍须由固定输入、环境、时间与事件下的官方客户端黑盒对照证明。

## 3. 基于上述证据的 MyWallpaperX 处理策略

本节是 MyWallpaperX 自有架构策略：它综合官方作者合同、2.8.42 固定客户端观察、当前代码/运行证据和第三方结构对照，但不是 Wallpaper Engine 官方公开的内部实现说明。

### 3.1 数据选择数据，执行器解释数据

允许以下分派：

- definition path/name 装载对应 effect definition；
- material/shader path 装载作者声明；
- component type/name 选择共享 particle primitive；
- SceneScript module/API name 选择受控 host bridge；
- identity 作为资源、缓存、publication、诊断和回归键。

禁止以下分派：

- sample/layer/path/hash 选择特制视觉算法；
- effect 名称直接选择一套绕过作者 material/shader 的硬编码像素结果；
- 已知截图或资产 ID 决定产品输出；
- 为通过固定 matrix 而在产品代码中返回样本专用结果。

判断标准是：身份可以选择作者数据和共享 primitive，不能选择样本专用答案。

### 3.2 尽量执行，局部降级

安全与状态完整性问题必须硬拒绝对应执行单元：

- 路径或符号链接逃逸；
- 非法 buffer/texture range、确定的 target hazard 或 ABI 不匹配；
- stale handle、generation、epoch、publication 或生命周期破坏；
- 编译器/VM 超时、OOM、预算超限；
- 无法安全解析的 graph command。

视觉兼容问题默认只停用最小失败单元：

- 某个 shader 或 pass 编译失败；
- optional uniform、texture、provider 或 metadata 缺失；
- 某个 SceneScript API 或 particle component 尚未实现；
- 某个 effect target 无法建立，但进入该 effect 前的 current texture 仍有效。

Effect 链保持下面的语义：

```text
previous = current
attempt(effect)
  success -> current = effect.output
  failure -> diagnostic + current = previous
continue
```

如果后续节点依赖失败节点未发布的 named target，只跳过真实受影响的依赖子图。不得因为一个 optional pass 不支持就在 launch 阶段取消整个可见 layer。

### 3.3 保留事务安全，不扩大视觉失败半径

现有 target pool、resource generation、frame reservation、publication、command-buffer completion、rollback、epoch invalidation 和 terminal compositor observation 是应保留的底座。快速出效果不等于放弃 GPU 事务安全。

需要改变的是 admission 粒度：Program/graph 可以按 effect 或依赖子图准备和提交，不能要求一层中所有 authored effect 都先形成完整 capability conservation 才允许任何可见结果。

### 3.4 通用执行不等于单体 renderer

2D image/composition、3D model、particle、text、media、lighting 和 post-process 可以保留各自真正需要的专用 importer、simulation、geometry 或 provider；通用指的是它们必须共享稳定的 scene/object identity、frame clock、typed state、resource/provider、Material Program、graph/target 生命周期和最终 compositor output。

不得为了“统一”把所有对象压进一个 draw call、一个巨型类型或一个先建完才可运行的平台，也不得让专用子系统重新拥有第二套资源、属性、图、帧时序或最终输出。新增专用子系统时，先声明它生产哪种共享运行对象、如何接入现有 graph/output、局部失败如何回到安全的 previous current。

## 4. 目标执行单元

| 单元 | 长期职责 | 当前迁移策略 |
|---|---|---|
| Swift Scene host | identity、作者顺序、IR、属性、资源/target 生命周期、诊断、Metal 调度 | 保留并收窄；不重复实现完整语言 |
| Shader preparation | include、directive、combo、PASS、作者 metadata、版本和 source provenance | 复用现有 loss-preserving 部分；逐步解除手写语义 analyzer 的默认阻断权 |
| Shader backend | 语言解析、类型、stage link、reflection 和 MSL 生成 | 优先验证上游 glslang → SPIR-V → SPIRV-Cross MSL；从上游固定版本集成，不复制 Mirage vendor 或桥接代码 |
| Material compiler | reflection + slots + defaults + host/author uniforms + render state → Program | 收敛现有 MaterialProgram；普通 authored material 是默认候选，不依赖 effect 名称 |
| Graph compiler | condition、pass、target、clear、copy、swap、compose、history 和 dependency → graph IR | 扩展现有 AuthoredGraph/GraphTargets，不建立第二套图 |
| GraphExecutor | ordered encode、target publication、effect-local current、terminal handoff | 保留现有 Metal executor，并支持按 effect/子图局部失败 |
| SceneScript VM | ECMAScript、module、exception、timer/job 和实例生命周期 | 优先上游 QuickJS-NG C API；先闭合最小 per-scene VM，不扩张 Swift 自制 AST 解释器 |
| SceneScript host bridge | typed handles、events、engine/time/audio/media/property 和 mutation buffer | Swift 拥有；按真实视觉切片逐组开放 API |
| Particle interpreter | 按 authored component 顺序构造 emitter/initializer/operator/renderer/child/control-point ops | 收敛现有粒子 runtime；type registry 选择共享 primitive，不按完整效果名 dispatch |
| Compositor | base/source、effect current、layer blend、scene post 和 drawable | 保留唯一 Metal compositor，不引入第二 renderer 主链 |

### 4.1 作者 shader 的推荐后端

当前最短的 macOS 路线是：

```text
WE GLSL-like source
  -> 现有 VFS/include/metadata/variant preparation
  -> 小型兼容 normalization + generated prelude
  -> glslang (GLSL -> SPIR-V)
  -> SPIRV-Cross (SPIR-V -> MSL + reflection)
  -> MTLDevice.makeLibrary / pipeline cache
```

选择依据：作者语言公开形态接近 GLSL；glslang 与 SPIRV-Cross 都提供独立上游和可固定版本，能够把语言语义从 Swift 手写 analyzer 移出，同时继续使用 Metal。Mirage 的 glslang/Vulkan 路线只提供“通用编译器 + 反射 + 图执行”职责拆分的固定 revision 静态结构对照，不能证明其可构建性、运行效果或产品可行性，也不能复制其 vendor 树、shader bridge、常量、payload 或 Vulkan 选择。

Slang、DXC + Metal Shader Converter 可以保留为对照，但在当前 corpus 没有证明它们比 GLSL → SPIR-V → MSL 少一层 dialect 转换以前，不作为首条产品路线。

第一条执行切片只需普通 vertex/fragment、常见 uniform/sampler、combo 和 render state。复杂 geometry、3D system shader 和全部历史 dialect 不阻塞普通 effect 首次出画面。

### 4.2 SceneScript 的推荐 VM

官方当前公开合同只确认 ECMAScript-based SceneScript。对 Wallpaper Engine 2.8.42 Windows 客户端的静态观察识别到 V8 runtime；这不是官方公开或跨版本保证，而引入完整 V8 对本项目的体积、构建和发布成本也过高。MyWallpaperX 首选上游 QuickJS-NG：

- C API 边界窄；
- 可设置 heap、stack 和 interrupt budget；
- 不默认暴露 DOM、Node、文件或网络；
- 可建立 per-scene/per-surface context 和显式 teardown；
- 参考项目只提供 per-scene VM + host bridge 的固定 revision 静态结构对照；其 QuickJS vendor 和 bridge 实现不得复制，也不能由此推断当前构建或运行结果。

JavaScriptCore 是系统自带对照，但当前 Xcode SDK 没有公开的执行时间限制入口。除非通过独立 worker 获得可靠终止和预算证据，否则不作为第一实现。

## 5. 纵向兼容执行

### 5.1 普通 effect 快速通路

第一条产品通路必须覆盖：

```text
effect definition
  -> condition/default/combo
  -> one ordinary material pass
  -> source/optional texture slots
  -> authored shader backend
  -> Program
  -> current texture
  -> layer compositor
```

现有 effect-specific backend 只能作为可观测 fallback。通用路径尝试失败后可以临时回退到已验证旧实现；不得为新 effect 增加同类 matcher/backend/renderer。

### 5.2 Effect graph 通路

在同一条普通通路上增加 FBO、copy、swap、compose、clear、condition、named target、history 和 cross-layer dependency。不得另建“高级 effect renderer”。

### 5.3 动态行为通路

Timeline、user property、SceneScript、pointer、audio、media 和 system state 都写入同一个 typed frame snapshot/mutation transaction。不同 producer 可以有优先级，但 consumer 不得各自再实现一套动态状态模型。

### 5.4 Particle 通路

Particle definition 编译为有序 component ops；system 实例拥有固定步进、spawn/death/event、control point、child 和 renderer 生命周期。未知 optional component 产生诊断并跳过；缺少唯一 renderer 或产生非法数值时停用该 particle system，不终止整个 scene。

### 5.5 五类变化与最小失效域

通用执行不等于每帧重新解析、编译和建图。所有动态变化必须先归入以下一种失效域，再只更新最小 owner：

| 变化 | 典型输入 | 允许失效的最小范围 | 默认不做 |
|---|---|---|---|
| value-only | time、pointer、audio、alpha、color、transform、effect scalar | 当前 surface 的 immutable value/uniform snapshot | 不重编 shader，不重建 graph |
| resource-generation | video frame、media artwork、dynamic text、user texture、TextureAnimation | provider publication、受影响 slot binding 与 resource generation | 不改变 material/graph identity，除非尺寸或用途合同真的变化 |
| geometry/extent | dynamic text size、mesh/atlas geometry、viewport/target extent | 受影响 geometry buffer、target allocation 与依赖它们的 node；保持无关 Program/provider | 不重建整 Scene，不清空尺寸无关的 cache |
| program-variant | optional slot presence、combo、material feature、render-state variant | 受影响 Program/pipeline cache entry；必要时重做该 effect admission | 不重建无关 layer 或整 Scene |
| topology | layer/effect visibility、condition、FBO/target 结构、动态增删对象 | 受影响依赖子图、target reservation 与原子 execution plan | 不清空未受影响的 provider、Program 和 surface state |

每个 target、provider、Program 和 graph node 都必须声明自己的 invalidation domain。consumer 不得以“实现方便”为由把 value-only 更新升级成整 Scene relaunch；也不得在结构已变化时仅改 uniform 而继续复用 stale graph。

## 6. 开发、产品和发布三层门

### 开发执行门

- 定向编译/单测；
- 一个真实代表内容实际进入新路径；
- GPU/VM 执行无 crash；
- 截图或事件观察到预期方向的变化；
- 失败不会抹掉无关 layer。

### 产品 checkpoint

- App build；
- 小型 Fast Scene Suite；
- Program/graph/VM/component diagnostics；
- publication、completion、terminal compositor 和 next-frame；
- 正常和局部降级两条路径。

### milestone / release

- 未见内容与更广 corpus；
- fixed/full matrix；
- cache、取消、压力、长稳、性能和内存；
- arm64/x86_64、许可证、Developer ID、hardened runtime、notarization 和 Gatekeeper；
- 需要宣称 fidelity 时再加入 Windows golden 或预定义 ROI/事件门。

发行条件不能倒灌成第一个真实 effect 的开发前置；开发成功也不能反向冒充发行就绪。

## 7. 迁移终态

达到以下状态才算架构迁移完成：

1. 普通 authored material/shader 是默认执行候选；
2. 多 pass、FBO 和 command 由同一 graph compiler/executor 处理；
3. SceneScript 由真实 ECMAScript VM 执行；
4. Particle 由 component interpreter 执行；
5. 一个 effect/pass/script/component 失败只影响其真实依赖面；
6. 产品不再用 sample/path/hash 或完整 effect identity 选择特制视觉算法；
7. 现有 dedicated backend、bounded Swift language frontend 和 fixed script evaluator 已删除，或隔离为不持有产品执行权的测试 oracle；仍承担产品 fallback 的路径属于未完成迁移，必须可观察并登记退役条件；
8. 当前能力、运行证据和性能/发布边界分别由各自权威文档证明。

具体顺序和当前第一批工作只看[Scene 兼容执行路线](scene-compatibility-roadmap.md)。
