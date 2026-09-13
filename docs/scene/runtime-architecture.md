# Scene 兼容运行时架构

<!-- document-role: stable-contract -->

> 状态：现役长期架构合同
>
> 最近复核：2026-09-14
>
> 当前实现程度与缺口只查[能力台账](semantics/coverage-ledger.md)；本文件描述目标处理方式，不把目标冒充现役能力。

## 1. 产品目标

MyWallpaperX Scene 的首要目标是尽快让真实 Wallpaper Engine Scene 在 macOS 上得到可辨认、可持续改进的正确画面。长期仍保持 Swift + AppKit 产品宿主和 Swift + Metal 渲染底座，但不再把每个已知 effect、shader 表达式、脚本或粒子组合翻译成一条专用 Swift 产品路径。

兼容对象是有证据约束的官方作者可观察行为，不是对 Wallpaper Engine 未公开内部 renderer、RenderGraph 或算法的猜测与复刻。样本、layer、path、asset、hash 和截图只用于发现影响面、验证与回归，永远不能选择产品视觉算法。项目的长期工程目标是**语义压缩**：用更少的共享运行 primitive 执行更多合法 authored 输入，而不是随样本数量增长 planner、profile、renderer 和 dispatch。

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

主链的输入产品不限定为纹理。准备阶段必须把 authored 输入降低为受约束的产品，由唯一 compositor 按作者顺序消费。产品只分为五个有限类别：`TextureProduct`（图片、视频、文字及栅格 effect）、`GeometryProduct`（Puppet/3D 世界空间几何）、`SimulationProduct`（粒子与物理状态）、`ProviderProduct`（异步媒体与动态资源）和 `GraphProduct`（多 pass、依赖 target、history）。这五类是架构分类和职责合同，不要求建立一个空的公共 enum、protocol、wrapper 或 registry；每个具体 owner 只携带本领域所需的 identity、logical extent、资源、encode/publication 和生命周期。它们共用 frame clock、resource/provider generation、target/publication/completion、rollback 与唯一最终输出，不能形成平行 renderer。Puppet atlas 是 mesh 的采样资源；准备好的 GeometryProduct 必须携带不可变的 effect-source extent 合同。该层有 effect 时，atlas 以自身 mapped extent 原样进入普通 GraphProduct，graph-final 纹理再由同一个 GeometryProduct 采样；尺寸在现有 pool hard limit 或驻留预算内无法精确保留时局部拒绝 graph，不能静默降采样。atlas 与 graph-final 纹理都不是已组合的 Puppet layer source，不能由普通 quad 或命名 provider 路径发布。

`TextureProduct` 的 mip 权威是编译后资源实际携带的 level 序列。`nomip` / `halfmip` 属于作者导入与离线编译输入，不能在没有格式证据时映射成 TEX V5 flag、第二套 sampler policy 或运行时 registry。有效 TEX 的单级或多级链在 upload、尺寸归一化、candidate 与 Program identity 中必须保持：单级 embedded/loose 纹理仍可走现役 bounded normalization且归一化后保持单级；已验证的多级 embedded color TEX 是作者编译后的采样产品，即使 base 长边超过 loose-image 的 4096 normalization limit，也必须在设备分配允许时完整保留 base 和所有 level，否则局部失败关闭。没有编译 TEX 权威的直接 PNG/JPEG 默认生成完整 mip 链；共享 sampler 只消费现有 texture 的 `mipmapLevelCount` 与现役 filter/address 状态。

SceneScript 对 layer 的查询只能是上述主链状态的 typed projection。layer identity、作者顺序、parent、只读 authored size 和静态 transform 在 load/generation 边界由同一个 descriptor 准备；逐帧 local transform 与 world matrix 必须从现役 immutable dynamic snapshot 和 renderer 的 canonical world-frame resolver 取得，并随既有 surface transaction 原子提交、回滚。VM bridge 只验证并复制 column-major ABI，不能另做坐标换算或保存第二份 transform 权威。同一 callback 的 local transform setter 可读取自己的 staged local 值，但 world matrix 只在整帧提交后的下一 snapshot 更新；缺少 canonical matrix 时只拒绝该 getter。不得为 matrix、parent、attachment 或 dynamic layer 增设另一套坐标系统、snapshot、调度器或 renderer。

SceneScript cursor hit 同样只能消费 renderer 的 canonical world frame、camera projection 和 layer size。作者省略的 local transform 字段按 renderer 已有默认值及 parent 继承解析，cursor owner 不得要求这些字段重复显式声明，也不得另建平行的 hit-test 坐标或 parallax 规则。事件准入由 descriptor identity、typed owner、公开 callback 和静态预算决定，禁止扫描 JavaScript 源码写法来区分同一种 object visibility owner。

兼容 profile 只能由 authored 语义、拓扑、类型化资源/状态、静态预算和失败合同定义，禁止包含 sample/layer/path/hash/screenshot 身份。每个 profile 必须能由现有通用 primitive 表达，并声明局部失败半径、fallback 原因和退役条件；若需要第二套 registry、clock、property tree、graph 或 compositor，必须停止并重新设计。Puppet 的现役产品是 `GeometryProduct`：静态 bind pose 与动态 pose 都保留原始 mesh 像素坐标和作者 UV，并在 preparation 时固定 `exactSamplingTexture` effect-source extent；调用方把层级 transform、作者 origin/scale、pivot、parallax 和 camera VP 合成唯一 world MVP，mesh 最终只向主 target 编码一次。受限 `MDLV0023 + MDLS0004 + MDAT0001` attachment 在 generation 边界保留 bone identity 与 attachment-local matrix；逐帧 current frame 由同一 Puppet pose 的 bone world 乘 local frame，再经 Scene 基换算进入 canonical world-frame resolver。child、SceneScript layer/bone snapshot 与 cursor hit 必须消费该帧同一阶段的 typed pose；脚本完成后的最终 pose同时驱动 skinning、attachment child world frame 和本帧 encode。动态 frame 缺失或非法时只对该 attachment 使用已验证的静态 bind frame，不能建立第二套坐标权威。旧 coverage 归一化、coverage 大纹理、逐帧重组纹理、尺寸 ceiling、重组预算/cache、通用 2048 effect target 压缩和 `.puppet` layer-source identity 已退役。只有作者 package 确实缺少所引用 mesh 时，才允许该局部层以明确原因降级为普通 `TextureProduct`；非法路径、mesh 读取/解析/验证、资源分配、精确 target 或 encode 失败不能把 atlas 冒充组合输出。命名图层 provider 当前只表达完整栅格层源，不能携带 mesh/world transform，因此 Puppet 作为跨层 provider 在依赖计划编译阶段明确拒绝，直到建立能原子携带几何与放置坐标的 typed publication。当前能力只覆盖台账登记的 Puppet mesh/version/动画和 attachment 形状，不外推为通用 3D、全部 Puppet 语义或官方逐像素 parity。

实施时按能够闭合真实画面的纵向切片扩展这条链。不得先分别建设完整 compiler、RenderGraph、VM、particle platform，再等待它们全部完成后才允许真实内容执行。

### 1.1 一个产品主干，多个通用语义执行器

“一条执行主链”约束的是产品控制、状态、资源和最终输出所有权，不表示把不同语言和对象域压进一个巨型 renderer。以下边界在所有迁移中保持不变：

| 必须只有一个产品权威 | 可以独立演进、但必须生产或消费共享运行对象 |
|---|---|
| scene/object identity 与作者顺序 | authored shader compiler/backend |
| frame clock、typed frame channels 与 frame commit | ECMAScript VM 与 typed host bridge |
| property/state 权威、generation 与 invalidation | particle component interpreter/simulator |
| resource/provider registry | text rasterizer、media/video decoder/provider |
| graph、target、history、publication 与 rollback 生命周期 | 3D importer、geometry、animation、physics、lighting |
| compositor、drawable 与每个 surface 的最终输出决策 | 其他接入共享 Program/resource/graph/compositor 的领域 producer |

同一个明确登记的 `capability_profile` 在产品运行时只能有一个输出 owner 和一个 route decision。`capability_profile` 只能由 authored schema、结构 topology、typed resource/state/constant bounds、failure contract 与公共执行 identity 定义，并登记在能力台账和 route diagnostic；不得包含 sample/layer/path/hash/screenshot identity。迁移期的新旧实现可以暂时共存，但不得静默双执行；旧 owner 只能通过 typed fallback reason 接管已经验证的 bounded 输入，并且必须有退出条件。`generic-only` 只证明该 `capability_profile` 的执行权迁移，不自动证明整个 effect、shader、script、particle family 或 V 轨完成。

进入 `generic-only` 后，只有经审查仍表达官方可观察行为、项目稳定公共合同或独立正反输入的 authored fixture、golden、截图 ROI 和行为反例可以继续验证通用路径；依赖旧内部类型、dispatch、私有常量组合或由旧实现自生成预期的测试/oracle 必须删除，或先转换为实现无关的行为合同。旧产品 dispatch、planner、renderer、可重新接回产品的实现和实现耦合测试 owner 必须在同一独立 owner-migration 批次删除或移出产品边界。纯离线 oracle 只有在不持有产品依赖和路由、且仍能提供独立行为价值时才可保留。

Agent 若准备新增第二套 resource registry、property tree、frame clock、graph/history、compositor/final output owner，或让 sample/layer/path/hash/screenshot identity 选择视觉算法，说明设计已经偏离本合同，必须停止当前实现并重新接入上述共享主干。

## 2. 证据来源及其边界

架构决策必须按[资料来源索引](semantics/source-index.md)的命名来源标注，以下是本文使用它们时的裁决顺序：

1. Wallpaper Engine 官方公开文档定义作者可见合同；
2. 固定版本、输入、环境、时间和事件下的官方客户端黑盒观察定义对应 bounded profile 实际发生的外部结果，不证明内部算法或其他版本；
3. 固定版本官方客户端静态取证补充未公开的职责、顺序和数据流，只能标为版本有界结构；
4. 合法 authored corpus 观察只决定作者数据的实际形状和影响面，不证明运行支持；
5. 当前 MyWallpaperX 代码与可复现运行证据决定已经实现什么，不反向定义应当怎样；
6. MirageWallpaper 等第三方项目只提供 clean-room 结构对照，不能定义官方语义或像素结果；
7. MyWallpaperX 策略只在不伪写上述外部事实的前提下定义跨平台实现、安全、失效半径和迁移方式。

### 2.1 目标合同、当前事实与偏差债务

任何设计和实现决策必须同时保留三条互不替代的轴：

| 轴 | 回答的问题 | 权威来源 |
|---|---|---|
| 目标合同 | 为满足作者可观察行为和本项目长期边界，最终应怎样处理 | 官方公开合同、bounded 官方结果合同与本文的项目自有架构策略 |
| 当前事实 | 当前代码、owner、路由和运行结果实际上怎样 | 当前源码、能力台账与可复现运行证据 |
| 偏差债务 | 当前事实偏离目标合同在哪里、由谁持有、如何回滚和退役 | 现役路线/能力表中的 owner、route state、fallback reason、纠正门与退役条件 |

现有代码、测试、目录和旧报告不能把偶然实现升级成目标合同。触达一个旧 owner 时，先列出本职责内的偏差，再在当前纵向结果所需范围内把数据和执行权迁向目标；不得为了兼容已知错误路径而继续扩张其 matcher、wrapper、专用 IR 或测试预期。无法同批纠正的部分保持为显式债务，不能通过降低目标合同来消失。

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

官方公开文档没有公开内部 RenderGraph。2.8.42 固定客户端静态取证只支持 condition、ordinary material、copy、swap、compose、FBO 和 layer-local logical pair 等版本有界结构；它没有闭合通用跨帧 history、device-loss 结果或 MyWallpaperX publication 语义。后三者在官方黑盒结果出现前必须分别标为 unknown 或 `MyWallpaperX-strategy`，不得表述为官方内部处理链。

当上述来源不足以决定当前纵向切片时，必须由官方客户端研究工作流控制问题范围、工具边界和实现交接。固定客户端静态观察只提供版本有界结构；对一个 bounded profile 的画面、事件、状态和失败结果是否一致，仍须由固定输入、环境、时间与事件下的官方客户端黑盒对照证明。

## 3. 基于上述证据的 MyWallpaperX 处理策略

本节是 MyWallpaperX 自有架构策略：它综合官方作者合同、2.8.42 固定客户端观察、当前代码/运行证据和第三方结构对照，但不是 Wallpaper Engine 官方公开的内部实现说明。

### 3.0 最短播放链与复杂度预算

目标不是建设一套覆盖所有异常、诊断和兼容情形的平台，而是保持一条可快速迭代的产品播放链：

```text
authored document/assets
  -> prepare once (IR / Program / graph / resources)
  -> update typed frame values or publications
  -> execute prepared Metal passes
  -> unique compositor/output
```

任何产品层类型或阶段都必须说明自己直接生产上述链上的对象、消费作者输入，或保护会导致 crash、GPU 越界、stale generation/epoch、target hazard、错误 publication/completion 的完整性边界。仅生产报告、hash、诊断、兼容判断、重复 route state 或未来扩展点的机制不得常驻播放链；诊断/benchmark 模式可以旁路观察同一执行结果，但不能反向成为提交或出画面的必要条件。

复杂度按删除方向管理：优先复用和收窄现有 owner；能由不可变 prepared value、直接函数或已有 typed channel 表达时，不新增 protocol、registry、wrapper、planner、profile 或 renderer。实现通用替代并撤权后，旧 owner、旧准入、旧诊断和只验证旧内部结构的测试成族删除。衡量进展以正确画面、布局、首帧和帧时间为主，不以类型数、gate 数、diagnostic 覆盖或拒绝理由数量为正向指标。

每个进入 Program/graph 的效果参数必须在 load、generation 或明确 invalidation 边界形成不可变执行合同。编译后的 variant 为每个 active uniform 精确记录一个来源：host semantic、已编码 static value、带 typed producer/fallback/schema 的 dynamic value、neutral texture metadata 或 self-composite metadata；layer capability 同时记录 effect texture projection 的几何来源及是否需要可逆矩阵，source product 记录 effect 输入尺寸是普通可缩放还是必须精确等于采样纹理。普通帧只读取 typed 动态值和仍须实时验证的资源 identity/readiness/range，再按已准备的来源编码；不得重新扫描作者声明、重新选择 host/static/dynamic lane、遍历 stage 推断 inverse/extent 要求，或按当帧碰巧可用的纹理与矩阵改变参数含义。

effect texture projection 必须对应该层最终实际提交给 effect graph 的卡片：fullscreen 使用 canonical output geometry，普通 image、Puppet、composition 与 direct draw 使用其 live emitted world geometry。source texture 的 logical extent、UV/resource metadata 与 output placement 是不同职责，不能让采样源尺寸替代放置矩阵，也不能让 coverage、atlas 或 capture texture 成为第二套几何权威；尺寸 planning 只能消费已准备 source product 的 extent contract，不能由各 effect 在帧内争抢或覆盖。五类产品可以提供不同的动态值和资源，但其参数来源、projection source、extent contract、失效键和局部失败半径都必须先降低到同一 prepared Program/graph 合同；新增参数能力时扩展 typed source 类别或现有 producer，不能在 frame preflight 中添加 effect/sample 特判。

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

现有 target pool、resource generation、frame reservation、publication、command-buffer completion、rollback、epoch invalidation 和唯一 terminal compositor owner 是应保留的底座。产品帧只保存提交/消费所需的轻量状态；完整 terminal observation、graph hash 和逐节点证据只在主动诊断或 benchmark 模式构造。快速出效果不等于放弃 GPU 事务安全，也不允许把证据系统变成提交成功的第二授权者。

需要改变的是 admission 粒度：Program/graph 可以按 effect 或依赖子图准备和提交，不能要求一层中所有 authored effect 都先形成完整 capability conservation 才允许任何可见结果。

### 3.4 通用执行不等于单体 renderer

2D image/composition、3D model、particle、text、media、lighting 和 post-process 可以保留各自真正需要的专用 importer、simulation、geometry 或 provider；通用指的是它们必须共享稳定的 scene/object identity、frame clock、typed state、resource/provider、Material Program、graph/target 生命周期和最终 compositor output。

不得为了“统一”把所有对象压进一个 draw call、一个巨型类型或一个先建完才可运行的平台，也不得让专用子系统重新拥有第二套资源、属性、图、帧时序或最终输出。新增专用子系统时，先声明它生产哪种共享运行对象、如何接入现有 graph/output、局部失败如何回到安全的 previous current。

### 3.5 启动是候选事务，不是全量兼容门

用户设置 Scene 后，主线程只接受请求、发布真实阶段并最终提交 AppKit surface；package、model、Program、作者 shader、资源和 pipeline preparation 在可取消的后台执行器完成。新请求采用 newer-wins，候选失败、取消或过期不能撤销当前 active，也不能提前改变持久化的当前壁纸。

首帧准备只覆盖当前内容和属性快照实际需要的 Program、shader variant、资源与 surface。未来可能出现的 optional provider、program variant 或未使用 catalog 不能倒灌成首帧的无界 eager compile；它们必须按第 5.5 节的最小失效域，在真正需要前异步准备并通过 generation 复核后原子发布。项目固定 MSL 必须构建期编译，不能在 surface 创建或 draw/pass encode 时首次 `makeLibrary(source:)`。

准备产物按 `PreparedContent -> PreparedLaunchPlan -> PreparedDeviceResources` 分层复用，分别以 content/package generation、属性与 runtime/compiler schema、OS/Metal/compiler/device identity 失效。作者 shader 的持久化缓存只允许保存 accepted Program/Preparation；key 必须覆盖完整 source/source-graph digest、combo、optional provider/readiness、格式与 frontend/compiler schema，value 必须带自身 digest 并在读取后复核 stage、backend、Program identity 和 cache key。拒绝、超时、诊断、损坏或字段失配不得成为可复用成功，统一安全 miss 后在 preparation executor 重建。

`MTLTexture`、`MTLLibrary`、`MTLRenderPipelineState`、surface、publication 和其他进程内对象不能直接跨进程序列化。后续 `PreparedDeviceResources` 若使用 Metal binary archive 或等价设备缓存，必须额外绑定 OS、Metal compiler、device registry/family、attachment format/sample count 和 Program identity；在这些门闭合前，磁盘命中只代表 CPU Program/preparation 可复用，不得声明 device 资源或首帧已经 ready。缓存只能复用已经通过安全校验的不可变产物，不能绕过 path/range/ABI、generation、target/publication 或失败合同。具体状态机、进度、候选首帧和回滚要求见[Scene 启动响应与按需诊断合同](../architecture/scene-launch-responsiveness-contract.md)。

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

第一批 compiler 集成必须先在独立、可终止的 subprocess harness 中验证不可信作者输入、诊断、reflection、预算和产物，不直接取得产品执行权。进入产品路径前必须作出显式故障隔离决策：要么以故障注入证明 in-process backend 的 crash、hang、timeout、OOM、取消和损坏结果不会杀死 App 或污染 cache/Program，要么使用可重启的 bundled compiler worker。完整 XPC 平台不是第一张画面的前置，但“尚未选择隔离策略”不能进入产品执行权。

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

每个迁移 owner 使用同一套显式 route state：

| route state | 产品执行权 |
|---|---|
| `observe-only` | 通用路径只编译、规划和记录差异，不发布产品输出 |
| `prefer-generic` | 通用路径优先；只有已验证旧 owner 可按 typed fallback reason 接管失败的 bounded 输入 |
| `generic-only` | 在明确登记的 `capability_profile` 内只有通用路径持有产品执行权；旧产品实现与 dispatch 已退役，历史 fixture/golden 继续验证通用路径，纯离线 oracle 必须与产品依赖隔离 |
| `disable-generic` | 故障时原子关闭该通用产品 route；仍有已验证旧 owner 时可按 typed reason 回退，否则继续按现役失败分类处理，eligible visual failure 局部 fail soft 并保留安全 previous current，integrity/ABI/target/hazard/lifecycle/budget failure 硬拒绝最小不安全单元；不得复活已退役 owner |

路由选择、fallback reason、输入 identity 和计数必须可观察，禁止同一输入静默双执行。`observe-only -> prefer-generic -> generic-only` 的每次转换都要原子可回退；进入 `generic-only` 前必须通过真实纵向正证、局部失败反例、新组合/未见 fixture、fallback 统计和一次回滚演练。同一独立 owner-migration 批次必须完成产品路径旧引用撤销、旧产品 owner 删除或隔离以及权威文档同步，之后才能声明 `owner-migration-complete`；长期停在 `disable-generic` 仍是未完成偏差债务。

### 5.2 Effect graph 通路

在同一条普通通路上增加 FBO、copy、swap、compose、clear、condition、named target、history 和 cross-layer dependency。不得另建“高级 effect renderer”。

feedback target 的格式和持久生命周期只说明“像素如何保存到下一次 graph 执行”，不能决定“像素是什么”。preparation 必须根据完整 Program variant envelope 独立解析输出的 `SceneTextureContent`：参与普通颜色插值、混合或滤镜的反馈结果保持 color contract；只有所有可执行 variant 都证明整值状态变换时，RGBA 才能作为 typed data publication。copy/swap 只传播已经解析的内容事实，不得因源/目标同格式把 color 升格为 data。terminal compositor 只消费 color，named provider 只发布与依赖声明一致的 data；内容合同无法证明时拒绝最小 graph/effect，不得在普通帧试错、双执行或按样本回退。

### 5.3 动态行为通路

Timeline、user property、SceneScript、pointer、audio、media 和 system state 都参加同一个有序 frame commit，但不能压进同一类值容器。commit 明确汇合三条 typed channel：

1. `immutable value/event snapshot`：time、property、pointer、audio scalar、事件和普通 uniform/value；
2. `resource/provider publication`：video frame、media artwork、dynamic text/texture 与各自 generation/readiness；
3. `topology/VM mutation transaction`：对象/层/effect 增删、visibility/condition 引起的图变化，以及脚本产生的受控 mutation。

producer 的优先级、同帧/下一帧可见性和冲突处理由 frame commit 统一决定；consumer 只读取与自身职责匹配的 channel，不得各自建立状态系统，也不得把 resource generation 或 topology change 伪装成普通 value-only 更新。

异步 provider 的控制命令也必须先成为 owner-scoped typed transaction effect，再由 provider 在同一 command generation 内执行。每次 seek、play、pause、rate、host suspend/resume、rebuild 或 rollback 都使旧 player anchor 失效；AVFoundation notification、decode completion 等不携带 generation 的异步回调，只有同时证明当前 command generation、当前 anchor 与回调对应的可观察终态后，才可修改 typed lifecycle 或发布新资源。迟到回调只能被忽略，不能覆盖更新的作者命令。初始资源尚未 ready 时仍按最小 layer 保留 previous-current；诊断/benchmark 只有在同 layer 后续取得 terminal compositor 和 next-frame success 时，才能把该启动 pending 记为已恢复，不能用等待或静默吞掉失败伪造首帧成功。

作者层的 SceneScript topology mutation 必须保持 owner、identity 和失败域可证明。当前只允许 effectful object-visibility owner 销毁自身且无子层的 authored layer；该操作与当帧 Boolean value 原子求值，只有全部 surface submission 成功后才从 render order、descriptor projection 和下一帧 VM snapshot 同时消失。跨 owner 销毁、带子层销毁、静态 sort/create、stale handle 和回生继续局部拒绝，不能用普通 `visible=false` 冒充 topology 已改变。

TextureAnimation 的脚本控制遵守同一边界：launch preparation 只登记 animated TEX 的 immutable frame/source 定义；每帧在 QuickJS callback 前由唯一 SceneClock 与现有播放控制状态形成 immutable handle snapshot。`rate/play/pause/stop/setFrame/join` 只产生 owner-scoped typed command，全部 surface submission 成功后才提交，并从下一帧同时影响普通 atlas UV、resolved-material preflight 和既有 multi-image upload。播放控制不拥有 texture、provider、timer、clock、resource registry 或 renderer；`join` 只移除 layer-local override。prepared 动画必须由 frame batch 提供 playback time，consumer 不得自行回读 `sceneTime` 形成第二条时钟路径。

### 5.4 Particle 通路

Particle definition 编译为有序 component ops；system 实例拥有固定步进、spawn/death/event、control point、child 和 renderer 生命周期。未知 optional component 产生诊断并跳过；缺少唯一 renderer 或产生非法数值时停用该 particle system，不终止整个 scene。

### 5.5 五类变化与最小失效域

通用执行不等于每帧重新解析、编译和建图。所有动态变化必须先归入以下一种失效域，再只更新最小 owner：

`Program`、graph topology、target plan、reflection、pipeline key 和不随帧变化的 ABI 检查必须缓存在对应 generation 的 prepared object 中。正常帧只允许更新 value buffer、真正变化的 resource publication/geometry，以及 command-buffer/epoch/publication 的常数级提交检查。任何逐帧 JSON 编码、整图 hash、全 catalog scan、全 ABI 重验或 evidence object 构造都视为架构回归，除非显式处于诊断/benchmark 模式。

| 变化 | 典型输入 | 允许失效的最小范围 | 默认不做 |
|---|---|---|---|
| value-only | time、pointer、audio、alpha、color、transform、effect scalar、TextureAnimation playback control/time | 当前 surface 的 immutable value/uniform snapshot 或现有播放状态；动画帧变化只更新既有 UV/provider 内容 | 不重编 shader，不重建 graph，不另建时钟 |
| resource-generation | video frame、media artwork、dynamic text、user texture、multi-image animation 的实际上传内容 | provider publication、受影响 slot binding 与 resource generation | 控制命令本身不升级为资源 generation；不改变 material/graph identity，除非尺寸或用途合同真的变化 |
| geometry/extent | dynamic text size、mesh/atlas geometry、viewport/target extent | 受影响 geometry buffer、target allocation 与依赖它们的 node；保持无关 Program/provider | 不重建整 Scene，不清空尺寸无关的 cache |
| program-variant | optional slot presence、combo、material feature、render-state variant | 受影响 Program/pipeline cache entry；必要时重做该 effect admission | 不重建无关 layer 或整 Scene |
| topology | layer/effect visibility、condition、FBO/target 结构、动态增删对象 | 受影响依赖子图、target reservation 与原子 execution plan | 不清空未受影响的 provider、Program 和 surface state |

每个 target、provider、Program 和 graph node 都必须声明自己的 invalidation domain。consumer 不得以“实现方便”为由把 value-only 更新升级成整 Scene relaunch；也不得在结构已变化时仅改 uniform 而继续复用 stale graph。

### 5.6 V4 是横切输入轨，不是 V3 之后的整个平台

V4 的 user property、pointer、audio、media、video/provider、dynamic text 和交互能力贯穿 V0–V3。每项输入都以一个独立纵向原子推进：typed producer -> 对应 frame-commit channel -> 现有 Program/VM/component consumer -> 可见或事件结果 -> teardown/局部失败。一个输入不得等待全部 V4 完成，也不能因另一个输入已完成而共享其 owner-migration 结论。

### 5.7 V5 是独立 epics 集合

Puppet、2D lighting/HDR、3D、RGB、offline bake、color/multi-display/device recovery 与 performance/release 分别是独立 epic，不构成必须顺序完成的单一 V5 平台。每个 epic 按 corpus 影响和用户价值单独登记输入、输出、首个可见切片、失败/回滚、验收门和旧 owner 退役条件；任何一个 epic 都不得等待“完整 V5”，也不能把自己的通过外推为其他 epic 或发行完成。

## 6. 三层完成门

### 6.1 `slice-visible`

- 定向编译/单测和风险所需的 App build 通过；
- 一个真实代表输入实际进入新 Program/graph/VM/component 路径；
- GPU/VM completion、publication、terminal compositor/next-frame 或对应事件链闭合；
- 预定义 ROI/事件观察到目标方向，局部失败反例不抹掉无关 layer/object。

这一级只证明当前 bounded 纵向结果，不改变旧 owner 的产品权威，也不证明官方等价。

### 6.2 `owner-migration`

- route state 已从 `observe-only`/`prefer-generic` 原子迁到 `generic-only`；
- Fast Scene Suite、相关新组合/未见 fixture、正常与局部降级路径通过；
- fallback reason/计数和差分已审计，并完成一次 `disable-generic` 回滚演练；
- 旧 owner 已撤销产品引用或隔离为无产品执行权的测试 oracle，能力/owner 文档同步。

这一级证明产品所有权迁移完成；若旧 owner 仍承担 fallback，迁移仍未完成。

### 6.3 `parity-release`

- 未见内容与更广 corpus；
- fixed/full matrix；
- cache、取消、压力、长稳、性能和内存；
- arm64/x86_64、许可证、Developer ID、hardened runtime、notarization 和 Gatekeeper；
- 对任何声称兼容或 fidelity 的 bounded profile，按预先登记输入、时间、事件和容差通过固定官方客户端黑盒 golden/ROI/状态序列；未运行时只能标为项目自有实现或 parity 未验证。

`slice-visible -> owner-migration -> parity-release` 只能逐层提升并分别报告。发行条件不能倒灌成第一个真实 effect 的开发前置；开发成功也不能反向冒充所有权迁移、官方一致或发行就绪。

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

具体顺序、当前段位和任务选择只看[Scene 兼容执行路线](scene-compatibility-roadmap.md)。
