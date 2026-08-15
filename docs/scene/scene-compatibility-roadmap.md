# Scene 兼容执行路线

> 状态：唯一现役 Scene 执行计划
>
> 启动日期：2026-08-15
>
> 当前主线：V0 普通 authored material/shader 纵向通路
>
> 当前能力只查[能力台账](semantics/coverage-ledger.md)，架构理由只查[兼容运行时架构](runtime-architecture.md)，已运行结果只查[运行证据索引](semantics/runtime-evidence-index.md)。

## 1. 成功定义

本路线优化的第一结果是“更多真实作者效果实际进入 GPU 并得到可见画面”，不是“更多结构被识别”“更多拒绝理由被证明”或“先完成一个通用平台”。

一个开发批次只有同时满足以下条件才算带来可见进展：

1. 至少一个此前未执行的真实 authored pass、script behavior 或 particle component 实际运行；
2. 运行结果沿现有 resource/target/publication/compositor 主链闭合；
3. 失败只影响真实失败单元，不抹掉无关 layer/object；
4. 产品没有新增 sample/path/hash 专用视觉算法；
5. 结果可由小型定向门快速复现和回滚。

普通 parser、IR、diagnostic、compiler census 或 matrix 变化可以是必要前置，但不能单独记为“效果完成”。

## 2. 当前判断

当前 Swift/Metal 底座已经拥有 Scene IR、资源和 provider identity、GraphTargets、LayerDependencies、Program、GraphExecutor、compositor、frame transaction、GPU completion 和运行证据设施。继续重写这些底座不会最快改善画面。

当前首要断点是：普通 authored effect 并没有一条默认的“准备作者 shader → 通用编译 → 反射和绑定 → ordinary graph node → Metal encode”路线；stage compiler 仍主要依赖 dedicated candidate/backend，shader frontend 又把大量未证明语义当作产品准入条件。一个 stage 失败还可能让整个 layer capability 不成立。

2026-08-15 静态快照中，`SteamWorkshopScene` 已有 **615 个 Swift 文件 / 109,337 行**，其中 `RenderGraph` 为 **251 个文件 / 51,503 行**。这些数字不证明能力，但说明继续用新增类型、matcher 和 correctness gate 换取单个 bounded profile 已经不是经济路线。最后一组 formal full45 是 **45/45 PASS**，而 fixed13 仍为 **12/13 NON-PASS**，最新两个定向可见样本为 **0/2 NON-PASS**；formal matrix 只能证明其合同内的结构/回归，不能覆盖用户可见基准。

因此下一批不得先做 G0/G1 式完整平台建设。V0 要在现有主链内建立最小、真实、可回退的普通 effect 执行切片。

## 3. 执行优先级

### V0：普通 authored material/shader 首次出画面——现在

目标链：

```text
effect definition
  -> ordinary material pass
  -> VFS/include + combo/default
  -> general shader backend
  -> reflection + texture/uniform/state binding
  -> Program
  -> GraphExecutor
  -> layer current
  -> compositor
```

第一批只要求：

- image/composition layer 的普通 vertex + fragment pass；
- framebuffer/source slot 和常见 optional authored texture；
- 常见 scalar/vector/matrix uniform、`g_Texture0...7` hole、combo 和基础 render state；
- glslang → SPIR-V → SPIRV-Cross MSL 的独立编译 harness；
- preparation-time MSL library/pipeline cache，不在 encode 热路径首次编译；
- compiler 失败时跳过当前 effect并保留 previous current；
- 现有 dedicated backend 作为明确、可观测 fallback，不新增同类 backend。

第一批不要求：

- 所有官方 effect；
- 任意 shader 或完整历史 dialect；
- 多 pass/FBO/history；
- 删除所有旧 planner；
- full matrix、x86_64、Developer ID 或 notarization；
- 每个 analyzer 都迁移或删除。

V0 完成门：至少一个此前因 `noBackendAccepted`、frontend admission 或 color-contract 阻断而未执行的真实 ordinary effect，使用通用作者程序实际产生 GPU effect output；同场其他 layer 保持；另有编译失败的局部降级反例。证据必须区分 compile、Program、encode、completion、publication、terminal compositor 和 next-frame，截图需证明预期方向变化，但不外推 Wallpaper Engine 像素等价。

### V1：Effect graph、FBO 与 command——紧随 V0

沿同一 Program/GraphExecutor 路线增加：

- ordered multi-pass；
- authored target/FBO extent、fit、scale、format、clear 和 unique；
- ordinary、copy、swap、compose；
- current/history ping-pong；
- named target 和 cross-layer dependency；
- condition/function；
- effect-local failure isolation。

V1 不建立第二套 renderer，也不为 Motion Blur、Refraction、Glitter 等名字写专用算法。它们只可作为普通 pass、copy/history、compose、FBO 等结构的代表 fixture。

完成门：普通多 pass、FBO command chain、history chain 和 cross-layer chain 各有项目正反门；至少一个真实 multi-pass effect 不新增 Swift matcher 即开始执行；一个中间 pass 失败只回退其 effect/依赖子图。

### V2：真实 SceneScript VM——可与 V1 研究并行

首条纵向链：

```text
inline/file source
  -> QuickJS-NG per-scene runtime/context
  -> one property owner
  -> init/update
  -> typed return or mutation buffer
  -> existing frame snapshot
  -> next-frame visible result
```

依次扩展：

1. primitive/Vec typed conversion、exception 和 source diagnostics；
2. `engine` time/frame/user-property；
3. layer/scene/effect/animation typed handles；
4. cursor、audio、media events；
5. timers/jobs、dynamic asset/layer API；
6. reload、pause、teardown 和 stale-handle isolation。

现有 bounded Swift AST evaluator 在迁移期只作为已验证 fallback/oracle。不得继续为 greeting、clock、Audio Bars、launch cohort 等已知源码增加新 profile。

完成门：一个真实 property script 和一个生命周期/事件 script 通过 VM 改变画面；无限循环、exception、OOM/stale handle 只终止对应 script owner；当前 bounded fallback 在对应 VM 路径稳定以后再撤权。

### V3：Particle component interpreter——可与 V1/V2 研究并行

按官方组件面把 definition 编译为共享 operation stream：

- General/material；
- Emitter；
- Initializer；
- Operator；
- Renderer；
- Child/event child；
- Control Point；
- instance override 和 Timeline/property input。

从当前 corpus 高频组件和缺少可见效果的代表系统开始，不按完整 particle definition 名称写 renderer。现有通用 emitter/initializer/operator/renderer 继续保留，严格 profile 逐步改成数据驱动 registry。

完成门：新的合法组件组合无需增加完整效果名分支即可运行；unknown optional component 局部诊断，缺少 renderer/非法数值只停用对应 system；spawn/update/render/child/teardown 有同一实例生命周期证据。

### V4：动态输入、Provider、Text、Audio、Media 和交互

这不是 V0 的前置阶段，而是贯穿 V0–V3 的输入扩展：

- user property 和 Texture Variants；
- pointer button/hover/click/drag 与局部坐标；
- system audio、Scene sound layer 和 SceneScript AudioBuffers；
- media status/metadata/timeline/current/previous artwork；
- video/system/provider generation；
- dynamic text、字体、alignment、outline/shadow；
- effectful/nested provider 和跨层 current/history。

每个输入都写入现有 typed frame snapshot、resource publication 或 VM mutation，不在 consumer 内各自建立状态系统。

### V5：Puppet、2D Lighting/HDR、3D、RGB、离线与发行

在 V0–V3 持续提供真实画面后，按 corpus 影响和用户价值选择：

- Puppet animation/mixing/constraint/physics；
- normal/PBR、light、shadow/reflection、Scene HDR/Bloom/tone mapping；
- 3D model/node/material/camera/skeleton/physics；
- RGB device；
- offline fixed-clock bake；
- color management、多屏、不同刷新率、sleep/wake/device reset；
- 长稳、性能、内存、能耗、签名、公证和发布。

V5 的发行门不倒灌到 V0 开发执行门；涉及产品发布时仍必须完整验证。

## 4. 全能力状态与归属

所有 Scene 能力必须处于“当前能力”或“明确待办”之一，不能只存在于旧计划。为避免各专项表的旧 `L0-L4` 含义互不一致，现役路线使用统一的结果等级：

| 等级 | 固定含义 | 可以声明 | 不能外推 |
|---|---|---|---|
| `S0 missing` | 产品没有入口或 consumer | 缺失 | 不得称 recognized/wired |
| `S1 preserved` | 能解析、保真、识别或诊断 | IR/schema preserved | 不得称 executable |
| `S2 wired` | 产品 owner、typed plan/target/provider/consumer 与自动测试已接线，但没有该接线之后的真实闭环 | wired / executable candidate | 不得称 visible/current fidelity |
| `S3 executed` | 真实产品路径已执行，并观察到必要的 CPU/GPU、publication/completion/rollback | bounded execution | 不得称视觉正确或相似 |
| `S4 visible` | 预定义隔离内容、ROI、事件或时间目标取得可见正证，且局部失败边界成立 | bounded visible result | 不得外推整个 family 或官方等价 |
| `S5 parity-ready` | 官方公开行为或合法 Windows golden、动态时序、生命周期与预算均闭合 | 对应精确合同的 parity/production-ready | 不得由非黑、matrix PASS 或单截图推导 |

同一能力族可以同时含 `S4` 子集和 `S0` 缺口；表中必须把二者同时写出。下表的 `S3/S4` 只表示[运行证据索引](semantics/runtime-evidence-index.md)仍登记了绑定特定 App/commit/fixture 的最近有效精确证据，不表示当前 HEAD 已重新运行或仍通过；本次治理没有构建 App、启动 Scene 或重跑这些证据。`311115e3` 触达的相关旧可见链尤其需要 fresh 回归后才能声明 current-visible；其新增 hover/click、shared alpha、audio-scaled value、property→Vec3、identity display、media color/title/artist 等产品接线因为没有更新后的真实可见证据，当前最高只能记为 `S2 / visible unknown`。

| 能力族 | 最近登记结果（identity-bound，非 current-HEAD PASS） | 明确待办 | 路线与事实入口 |
|---|---|---|---|
| Format | loose project/scene、PKGV、常见 TEX/对象已达 bounded `S3`；未知 schema 多为 `S1` | 私有版本、完整 VFS case/symlink/duplicate、多格式兼容 | V0/V1；[总台账](semantics/coverage-ledger.md)、[格式/图合同](semantics/scene-format-and-render-graph.md) |
| Resource/provider | PNG/JPEG、常见 TEX/BC1-3、embedded MP4、property texture、current cover、typed generation 有 `S3-S4` 子集；8-slot/named/R8 为 mixed `S2-S3` | generic video/material provider、`_b` 数据流、Texture Variants、live media producer、更多格式/颜色合同 | V0/V1/V4；[运行输入覆盖](semantics/runtime-input-property-coverage.md) |
| Property/Timeline | catalog/UI/persistence、layer/text/effect/root-particle/Timeline 子集有 `S3-S4`；新 audio/property/shared projections 为 `S2` | shortcut、Sound volume、generic script mutation、完整 Combined/3D targets 与 topology invalidation | V2/V4；[运行输入覆盖](semantics/runtime-input-property-coverage.md) |
| Base layer/object | image、solid、text、container、常见 particle、2D hierarchy/order 有 `S3-S4`；Puppet 仅 bounded | Sound、generic light、3D model 和完整 attachment/dynamic hierarchy | V0/V3/V5；[高级对象覆盖](semantics/advanced-object-coverage.md) |
| Effect/shader/material | 多个 strict/bounded profile 有 `S3-S4`；arbitrary authored shader 仍无默认 backend | 先通用 ordinary compiler，再扩 state/resource/color/helper；Motion Blur、Fluid、Glitter、Refraction 等不得继续靠新 matcher | V0；[Effect 覆盖](semantics/effect-execution-coverage.md)、[Graph/Shader 覆盖](semantics/render-graph-shader-coverage.md) |
| Graph target/command | bounded current capture、`_a`、Cursor history、部分 logical target/R8 有 `S3-S4`；FBO/copy/swap 多为 `S1-S2` | generic ordinary/copy/swap/compose/condition/function/history、`_b`、multi-dependency | V1；[Graph/Shader 覆盖](semantics/render-graph-shader-coverage.md) |
| Composition/dependency | basic layer compose 与少数 named/captured chain 有 `S3-S4` | nested/effectful/child provider、generic scene composition、RGB/secondary/multiple dependency | V1/V4；[总台账](semantics/coverage-ledger.md) |
| SceneScript | bounded AST/fade/origin 子集最高 `S4`；binding/source evidence `S1`；最新 native projections `S2` | QuickJS-NG ECMAScript、modules、host objects/handles、events/timers/shared、mutation/teardown | V2；[SceneScript 覆盖](semantics/scenescript-api-coverage.md) |
| Particle | common Sprite/emitter/initializer/operator/child/rope/audio/CP 有 mixed `S2-S4` | component registry 泛化、collision、dynamic Layer Image、lighting/HDR、cross-space、offline | V3/V5；[Particle 覆盖](semantics/particle-component-coverage.md) |
| Text | CoreText static/direct/bounded Date、alignment/pivot/limits 有 `S3-S4`；media title/artist wiring `S2` | baseline、outline/shadow、完整 typography、generic media/SceneScript text | V4；[运行输入覆盖](semantics/runtime-input-property-coverage.md) |
| 3D/lighting/HDR | carrier/metadata 最多 `S1`；没有可声明的完整执行 | model/node/material/camera/animation/skeleton/physics、light/shadow/reflection/HDR/tone mapping | V5；[高级对象覆盖](semantics/advanced-object-coverage.md) |
| Interaction | pointer world/窄 local 与少数 effect/particle 有 `S3-S4`；primary-button hit-test、bounded click/hover 为 `S2` | generic event queue、VM bridge、完整 local coordinates、多按钮、drag/capture/puppet hitbox | V2/V4；[运行输入覆盖](semantics/runtime-input-property-coverage.md)、[SceneScript 覆盖](semantics/scenescript-api-coverage.md) |
| Audio/Sound | host FFT 16/32/64 与部分 effect/particle/Program consumer 有 `S3-S4`；audio-scaled rate/scale wiring `S2` | Sound layer/self-playback spectrum、SceneScript AudioBuffers/average、数值/生命周期 golden | V3/V4；[运行输入覆盖](semantics/runtime-input-property-coverage.md) |
| Media/video | embedded MP4、current cover、last-ready/fade 有 `S3-S4`；playback/colors/title/artist snapshot/consumer 为 `S2` | live macOS producer、status/timeline、previous cover、generic events/transition/provider arbitration | V4；[运行输入覆盖](semantics/runtime-input-property-coverage.md) |
| Performance/release | stop/switch/diagnostic 与局部预算有 `S2-S3` | frame pacing/quality tiers、CPU/GPU/VRAM/leak预算、30min/2h soak、多屏/sleep/hot-plug、offline、签名/公证发布闭环 | V5/release；[高级对象覆盖](semantics/advanced-object-coverage.md)、[签名流程](../release/release-signing.md) |

若发现官方能力未出现在总台账或专项表，先补权威能力行并标 `S0/S1/unknown`，再按本表归入 V0–V5；不得用新的一次性 plan 代替现役台账。当前没有任何能力族可不带限定地记为完整 `S5`。

## 5. Fast Scene Suite

建立一个小型、稳定、低成本的纵向开发集，成员从隔离真实 corpus 选择并记录 authored structure，不把 sample ID 写入产品代码：

1. ordinary one-pass framebuffer effect；
2. ordinary pass + optional texture/combo；
3. ordered multi-pass + FBO；
4. copy/swap/history；
5. cross-layer/named provider；
6. SceneScript 可见 property/event；
7. Particle 常见 emitter/initializer/operator/renderer。

V0 只需要前两类，V1 增加 3–5，V2/V3 分别增加 6/7。suite 是开发反馈环，不替代 fixed/full milestone，也不以任意非黑像素作为成功。

## 6. 批次工作方式

每批只需回答：

1. 哪个真实作者输入目前没有执行？
2. 它在统一链的第一个失败点是什么？
3. 本批闭合到哪个可见结果？
4. 失败如何限制在 effect/pass/script/component/依赖子图？
5. 使用哪个真实代表内容和哪个项目正反门？

不再强制每批：

- 先证明完整通用平台；
- 提交前必须撤销一个旧 owner；
- 编码循环必须加入未见 corpus fixture；
- 更新所有专项表或刷新全 corpus；
- 运行 fixed/full、签名和公证。

通用路径已经可见替代旧路径后，才在后续同职责批次撤销旧 owner；不得长期保留静默双路由。未见组合在 checkpoint/milestone 定期验证，用于防止名称特判，而不是阻止第一张正确画面。

## 7. 指标

每个 V0–V4 checkpoint 至少报告：

- eligible authored units；
- compile/plan success；
- 实际 Program/graph/VM/component execution；
- GPU encoded effect passes；
- 至少一个非 base effect 可见的 scene 数；
- 局部降级和整 layer/scene 拒绝数；
- first compile、first effect frame、CPU/GPU frame time、内存；
- fallback 使用量及原因。

同时报告本批的语义压缩率：新增或修改多少产品执行 primitive，实际让多少此前未执行的 authored unit 进入执行。新增文件数、类型数、gate 数和台账行数不是正向 KPI；如果一个通用 primitive 只解锁一个已知 identity，必须解释为什么它仍是数据驱动能力而不是新的 profile。

指标只使用可实际采集的分母，不提前写百分比目标。compile success、route count、matrix PASS、非黑截图和进程存活均不能单独证明效果或兼容性。

## 8. 下一批精确断点

V0 第一批从当前 `SceneEffectStageCompiler` 的 `resolveDedicatedStage -> noBackendAccepted` 断点开始：

1. 先用 Fast Scene Suite 前两类建立独立 upstream shader backend spike；第一条普通 pass 能编译后再做有界 source census，按真实失败类别决定 normalization，不以全 corpus 报告阻塞首次出画面；
2. 复用现有 source graph、preparation、slot/default/combo 和 Program ABI，绕开 effect-name matcher；
3. 让 ordinary authored stage 先尝试 generic backend；
4. 把 frontend analyzer 从默认 admission 改为 diagnostic/oracle，安全/ABI/resource 检查仍保留；
5. 将失败半径收窄到当前 effect，并保留 previous current；同时修正 renderer 中 claimed layer/quad draw 失败后停止整个后续 layer suffix 的行为；
6. 用 Fast Scene Suite 前两类取得可见正证；
7. 稳定后才决定哪些 dedicated backend 可以撤权。

如果 shader backend spike 证明 glslang → SPIR-V → SPIRV-Cross MSL 对当前 dialect 不可行，保留 fixture、diagnostics 和失败分类，再评估 Slang 或 HLSL/DXC 路径；不得在没有 corpus 数据前并行建设三套 compiler。

## 9. 完成与退役

当 V0–V5 的产品目标均已由[能力台账](semantics/coverage-ledger.md)和[运行证据索引](semantics/runtime-evidence-index.md)证明，所有待办都有完成、明确不支持或平台策略结论，且旧专用产品 owner 已删除/隔离后，本文转入历史目录。届时应以稳定架构合同和能力台账接管终态，不再创建另一份平行 roadmap。
