# Scene 兼容执行路线

<!-- document-role: active-plan -->

> 状态：唯一现役 Scene 执行计划
>
> 启动日期：2026-08-15
>
> 当前主线：V1-A correctness、V1-B 产品 owner debt、V2 bounded SceneScript 与 V3 bounded Particle component interpreter 已按专项表及 fresh 运行证据闭合；现役主线进入 V4 typed input/provider 收口，不提前进入 V5
>
> 当前能力只查[能力台账](semantics/coverage-ledger.md)，架构理由只查[兼容运行时架构](runtime-architecture.md)，已运行结果只查[运行证据索引](semantics/runtime-evidence-index.md)。

> 路线北极星：在一个共享 Scene 控制与输出主干上，用更少的通用 primitive 执行更多合法 authored 输入，逐步复现有证据约束的官方可观察行为。V0–V3 是对同一主干依次增加 material/shader、graph、ECMAScript VM 和 particle component 语义；V4 是贯穿其间的 typed-input 横切轨；V5 是接入同一 identity/frame/resource/Program/graph/compositor 的独立领域 epic。它们不是多套替代架构，也不允许按 sample/layer/path/hash 增长产品算法。

每个批次必须能够指出接入的共享 owner、消费的 authored schema、产出的共享运行对象、最小失败半径，以及旧产品 owner 的退出条件。回答不出这些问题时，不得新增 renderer、planner、完整 profile 或第二套资源、状态、graph、clock、history、compositor/output 链。

## 1. 成功定义

本路线优化的第一结果是“更多真实作者效果实际进入 GPU 并得到可见画面”，不是“更多结构被识别”“更多拒绝理由被证明”或“先完成一个通用平台”。

一个 correctness/capability 开发批次只有同时满足以下条件才算带来可见进展：

1. 至少一个此前未执行的真实 authored pass、script behavior 或 particle component 实际运行；
2. 运行结果沿现有 resource/target/publication/compositor 主链闭合；
3. 失败只影响真实失败单元，不抹掉无关 layer/object；
4. 产品没有新增 sample/path/hash 专用视觉算法；
5. 结果可由小型定向门快速复现和回滚。

普通 parser、IR、diagnostic、compiler census 或 matrix 变化可以是必要前置，但不能单独记为“效果完成”。

独立 owner-migration、纯规则或历史整理批次不冒充新增可见能力；它们分别按 route/撤权/回滚门或文档治理门验收，并保持既有可见结果不回退。

## 2. 当前路线前提

本节不复述 current capability，也不保存底座、backend、失败半径或样本状态的移动快照。当前能力与缺口只读取[能力台账 §1](semantics/coverage-ledger.md#1-口径)，当前运行身份与首断点只读取[运行证据索引 §1](semantics/runtime-evidence-index.md#1-当前证据快照)；两者变化时先更新各自权威，再重新审查本文的路线选择，禁止直接在计划中手改一份平行事实。

由上述现役权威导出的剩余顺序只有一条：先闭合 V1 剩余 correctness atom，再完成 V1 owner debt；之后依次完成 V2、V3，以 V4 作为贯穿既有 consumer 的输入/provider 收口轨，最后逐项进入 V5 epics。V1 未同时通过 correctness 与 owner-debt 两道门时，不把 V2 的既有 bounded 证据改写成主线切换；V4 所需 producer 可以随 V1–V3 的真实 consumer 同批接入，但不能据此跳过 V2/V3 完成门或提前进入 V5。

V1 当前已闭合和仍缺的精确 shape、route state 与升级门只查[Render Graph / Shader 覆盖表](semantics/render-graph-shader-coverage.md)，对应 App/fixture/GPU/publication/compositor 证据只查[运行证据索引](semantics/runtime-evidence-index.md)。V2–V5 同理返回各专项表。本路线只拥有顺序与完成门，不复制 atom 名单、batch 数、样本身份、报告路径或 route 快照。

## 3. 执行优先级

### V0：普通 authored material/shader 首次出画面——已封存门

V0 的目标链和首个 `slice-visible` 结论已经由[能力台账](semantics/coverage-ledger.md)、[Effect 覆盖表](semantics/effect-execution-coverage.md)、[Render Graph / Shader 覆盖表](semantics/render-graph-shader-coverage.md)与[运行证据索引](semantics/runtime-evidence-index.md)接管。V0 不再保留“第一批”清单，也不从历史断点续接；后续 shader/frontend 缺口只有在服务当前 V1–V5 纵向结果时进入对应批次。

### V1：Effect graph、FBO 与 command——已闭合门

#### V1-A：剩余 correctness atom

当前段位：2026-08-26 已由[Render Graph / Shader 覆盖表](semantics/render-graph-shader-coverage.md)与[运行证据索引](semantics/runtime-evidence-index.md)同步通过完成门；未登记或生命周期/资源合同不同的 shape 继续按明确边界 fail closed，不作为继续滞留 V1-A 的理由。现役主线已切到 V1-B，VHS/Chromatic 的 typed SceneScript attachment 明确留在 V2/V4，不能倒灌成新的 V1-A 原子。

沿同一 Program/GraphExecutor 路线逐个闭合：

- ordered multi-pass；
- authored target/FBO extent、fit、scale、format、clear 和 unique；
- ordinary、copy、swap、compose；
- current/history ping-pong；
- named target 和 cross-layer dependency；
- condition/function；
- effect-local failure isolation。

V1 不建立第二套 renderer，也不为 Motion Blur、Refraction、Glitter 等名字写专用算法。它们只可作为普通 pass、copy/history、compose、FBO 等结构的代表 fixture。

V1-A 完成门：以[Render Graph / Shader 覆盖表](semantics/render-graph-shader-coverage.md)登记的当前 shape 为准，普通 multi-pass、FBO command、history/lifecycle、condition/function、compose 与 cross-layer dependency 的剩余公共形态均有项目正反门和明确 unsupported 边界；至少一个真实 multi-pass effect 不新增 Swift matcher 即执行；任一中间 pass 或依赖失败只回退 effect/真实依赖子图。未取得同级证据的 shape 必须继续 fail closed，不能用“任意 V1 已完成”抹掉。

#### V1-B：owner debt

V1-A 不自动撤销旧 owner。完成 correctness 后，按[能力台账](semantics/coverage-ledger.md)和[Render Graph / Shader 覆盖表](semantics/render-graph-shader-coverage.md)逐项审计仍为 `observe-only`、`prefer-generic`、dedicated fallback 或重复 publication/graph owner 的产品路径；每个 profile 独立迁移，不用一个 bounded `generic-only` 外推整个 family。

当前段位：2026-08-29 已通过完成门。现役 registry 为 43 个缺省 `generic-only`、0 个 `prefer-generic`、1 个 `observe-only`；唯一 observe-only 是无 graph owner token 的 Standard Blur unowned 隔离桶，在 Program/GPU 前 typed fail-closed且不持有产品输出，因此不是遗留产品 fallback。V1 完成不把该不安全 shape 扩权为支持，也不代表 graph/shader 全兼容、视觉 parity 或发行完成；精确代码、正反/回滚与真实消费者证据只查专项表和运行证据索引。

V1-B 完成门：所有纳入 V1 完成范围的 profile 都有显式 route state、typed fallback 统计、新组合门和一次 `disable-generic` 回滚演练；产品 route 原子切到 `generic-only`，旧产品引用、执行 owner 与实现耦合测试 owner 已删除或隔离为无产品执行权的独立 oracle，能力与证据权威同步。仍承担产品 fallback 的 profile 必须登记 owner、reason、退出条件，并使 V1 保持未完成。

只有 V1-A 与 V1-B 同时通过，主线才进入 V2。

### V2：真实 SceneScript VM——已闭合 bounded 完成门

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

1. primitive scalar typed conversion、exception/source diagnostics 与 `engine` time/frame immutable input；
2. Vec typed conversion 与 `engine.userProperties` snapshot；
3. layer/scene/effect/animation typed handles；
4. cursor、audio、media events；
5. timers/jobs、dynamic asset/layer API；
6. reload、pause、teardown 和 stale-handle isolation。

现有 bounded Swift AST evaluator 在迁移期只作为已验证 fallback/oracle。不得继续为 greeting、clock、Audio Bars、launch cohort 等已知源码增加新 profile。

V2 完成门：以[SceneScript API 覆盖表](semantics/scenescript-api-coverage.md)为当前事实，一个真实 property script 和一个 lifecycle/event script 通过 VM 改变画面或产生预登记事件结果；无限循环、exception、OOM、reload/teardown 与 stale handle 只终止对应 script owner；所需 typed handle、job/timer 与 mutation transaction 有正反门。纳入 V2 完成范围的 bounded Swift/fixed owner 已完成 `generic-only` 迁移或在专项表明确保持 unsupported，不再承担静默产品 fallback。V2 通过后才进入 V3。

当前段位：2026-08-29 已由[SceneScript API 覆盖表](semantics/scenescript-api-coverage.md)和[运行证据索引](semantics/runtime-evidence-index.md)通过上述 bounded 完成门。停止与场景切换现在对每个 owner 恰好调用一次 `destroy()`，并在 callback 即使创建 timer、Promise job 或动态层后仍原子归零；旧 generation 继续 stale fail-closed。该结论不外推 file module、完整 API、所有 value type、multi-surface、官方行为 parity 或 stock clock 等未闭合 consumer，它们保持专项表中的明确边界，不再阻塞 V3 主线。

### V3：Particle component interpreter——完成

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

V3 完成门：以[Particle 组件覆盖表](semantics/particle-component-coverage.md)为当前事实，新的合法 emitter/initializer/operator/renderer/child/control-point 组合无需增加完整 definition 名称分支即可运行；unknown optional component 局部诊断，缺少 renderer、非法数值或预算失败只停用对应 system；spawn/update/render/child/teardown 有同一实例生命周期证据。纳入完成范围的 strict profile 产品 owner 已撤权或显式保持 unsupported，route/fallback/回滚门完整。V3 通过后进入 V4 收口。

当前段位：2026-08-29 已由[Particle 组件覆盖表](semantics/particle-component-coverage.md)、当前产品代码及[运行证据索引](semantics/runtime-evidence-index.md)通过上述 **bounded** 完成门。现役执行只按 authored component/material 字段进入同一 `SceneParticleRuntime`、Metal pipeline 与 compositor，不按 definition/sample/layer/path 持有专用视觉 owner；当前真实 corpus 没有多 renderer definition，未准入的多 renderer、component shape 与不安全数值继续 typed unsupported 或 system-local fail closed。公共门覆盖未见组件组合、unknown optional、缺 renderer、root/child 预算、spawn/update/render/child，以及同一 playback UUID 的 switch/stop teardown；formal particle inner 为 15 modules / ALL OK，生命周期 checkpoint 与 Developer ID build通过。该完成状态不等于通用 Particle System、完整组件/API、GPU 资源长稳归零、全部样本视觉正确或官方 parity；这些边界保留在专项表，但不再阻塞 V4。

### V4：动态输入横切轨——现在

V4 是横切 producer/provider 轨，不是另建一套输入平台。V1–V3 若闭合真实 consumer 必须同步接入它实际消费的最小 V4 原子；主线在 V3 完成后回到本轨，对尚未随 consumer 闭合的输入族作统一收口。所有输入在同一 frame commit 下走相应 typed channel，不在 consumer 内另建状态系统：

| 输入族 | typed output | 首个公共 consumer | 正反门 | 旧路径退出条件 |
|---|---|---|---|---|
| user property / Timeline / Texture Variants | immutable value snapshot；variant 变化进入 Program invalidation | V0 material、V2 VM、V3 particle | 同值稳定、新值下一帧生效、非法 target 局部拒绝 | consumer 不再自行解析 property 或保存第二份值 |
| pointer / hover / click / drag | ordered event snapshot + local/world coordinates | V2 VM、V3 control point | exact event order/identity、outside-hit 负例、capture/teardown | bounded native profile 不再持有产品事件 owner |
| system/Scene audio | immutable audio snapshot 或 provider publication | V0 Program、V2 AudioBuffers、V3 component op | 固定 buffer、静音/invalid 负例、帧相位 | consumer 不再各自重采样或保存私有 FFT |
| media / video / artwork | resource/provider publication + value/event snapshot | V0 material、V2 media API、Text | generation、last-ready、stale/cancel、next-frame | 专用 current-cover/text profile 不再持有产品 owner |
| dynamic text | resource publication；尺寸变化另触发 geometry/extent invalidation | Text compositor、V2 mutation | 内容、baseline/bounds、空值/字体失败 | consumer 不再绕过 provider publication |
| nested/effectful provider | provider publication + topology transaction | V1 dependency graph | named identity、dependency failure、teardown | provider 不再拥有私有 graph/current/history |

当前段位：V4 已有 single-surface pointer/cursor/authored-transform、direct user-property bool activation/scalar uniform与scalar→isotropic `float2` uniform、当前可见且`effects.isEmpty`的ordinary image direct color → 唯一image compositor、pass-owned typed scalar + static `scriptProperties`/audio、Vec2/audio 与 Vec3/颜色模块 → MaterialProgram、object-authored text `pointsize` → shared QuickJS → 同代动态文字纹理/逻辑尺寸 publication，以及 authored Sound 单音源循环/共享property音量及其与真实audio consumer共存时的shared spectrum provider bounded纵向原子。2026-08-30 又把 thumbnail presence 与 primary/secondary/tertiary/text/high-contrast 五色作为同代 immutable event 接入同一 QuickJS Vec owner；MaterialProgram consumer 集合先形成，再在 fresh candidate domain 只构造该集合，普通owner失败排除精确identity后重建，共享OOM则拒绝整个candidate。旧 native media-color family 已撤权删除，默认 route=`generic-only`；`disable-generic` 以fresh domain迭代发现并移除media owner直到严格fixed-point，只有末域进入产品，同时为route或construction失败target保留exact authored definition作为统一resolver的lower-priority current，四个MaterialProgram/GraphExecutor consumer不掉链，fresh process可恢复。同一路由现在也准入effectless、有效可见且不承担dependency/provider/utility职责的object-authored image `color`；精确target、正反运行与仍被后续graph transaction阻断的视觉边界只查运行输入专项表和运行证据索引，不能写成眼部发光或画面正确。每帧layer snapshot在任何cursor/vector/String/scalar callback前一次性stage/commit；发布失败会跳过本帧全部共享回调并保留previous/current。callback/update失败也不发布SceneScript高优先级值。精确 consumer、数量、route、证据与剩余缺口只查运行输入专项表和运行证据索引；这些 S3 owner migration 没有独立颜色/眼部 ROI。V4 完成门尚未成立，不能进入 V5。

同日 object-authored Bool visibility 的后继 failure-radius 修正让已提交`true`且具备exact complete base publication的安全leaf进入唯一image compositor；stock Water Waves缺省`textures`只表示没有authored source override，source replacement、空optional mask、未知/非零combo、relocated definition、多pass及target/dependency/publication完整性错误仍拒绝。代表性真实内容继续因effect只降级为base source而严格NON-PASS，截图没有变化；该结果只修复“局部effect失败吞掉整层base current”，不代表Water Waves/Shake、目标layer或整样本视觉正确，也不改变V4现役段位。精确身份、运行结果与剩余断点只查专项表及运行证据索引。

同日 current system-provider effect slice 已把 `$mediaThumbnail` 的 exact `(name,purpose)`、pending generation 与独立 premultiplied/preserved publication 尝试接入既有 MaterialProgram、GraphExecutor 与唯一 compositor；两种representation都成功派生时同代原子发布，单一purpose派生失败则只令该exact demand unavailable。真实正门证明pending→普通Program→同Program next-frame，unavailable负门保持exact previous-current。它只闭合effect-current纵向消费者，不把140 corpus中的previous、base-image/root ingress、live platform producer或眼部视觉债务改写成已完成；这些剩余分族及下一安全cohort继续只从运行输入专项表和当前代码选择。V4完成门仍未成立。

同日后继 previous system-provider effect slice 恢复公共 `$mediaPreviousThumbnail` lifecycle identity，而没有恢复B20前的fixed source/profile/renderer：共享store只在不同的新current成功decode后旋转，新current与真实上一成功previous的color/preserved representations同代原子发布；首次current没有伪previous，pending保留完整last-ready，invalid/clear对外unavailable，stale/cancel不旋转。Host先让全部surface store到达该输入generation的terminal snapshot，再派发`mediaThumbnailChanged`，随后脚本与同一prepared snapshot进入本帧。代表内容已完成unavailable→pending previous-current→ordinary Program→same Program next-frame；当批album-cover仍黑的base current首断点已由下述后继切片闭合，rounded-mask的library compilation失败仍独立留债。精确身份与报告只查运行证据索引；V4完成门仍未成立。

同日 base-material current slice 将layer instance与model material pass中的loss-preserving `usertextures` 统一投影到现役binding program；authored raw与property-resolved projection分离，bounded准入只接受slot 0、单一占用user slot、单material pass及真实作者fallback。ready `$mediaThumbnail` 继续以system-provider atom进入同一frame registry、GraphExecutor输入和唯一compositor，不重发布成layer source；当帧publication先于target preflight建立，image target extent与实际provider一致且ready provider不依赖placeholder存在。pending/absent/unavailable保留作者placeholder，publication/identity完整性错误只拒绝provider replacement并保留该slot的安全previous-current，无placeholder时仍保留typed reason。代表隔离内容已经取得binding、ready、encoded route、GPU completion、terminal compositor、next-frame与封面矩形可见证据；整selection仍因既有effect-local passthrough严格NON-PASS，因此本条只到`S4 controlled real-sample base-material slice-visible`。精确样本、数量、报告与剩余base previous/rounded-mask边界只查运行输入专项表和运行证据索引；V4完成门仍未成立。

V4 完成门：以[运行输入与属性覆盖表](semantics/runtime-input-property-coverage.md)为当前事实，每个纳入范围的 input/provider 都至少有一个真实 consumer，证明 typed producer → 正确 frame-commit channel → consumer → next-frame/event、generation/cancel/last-ready/teardown 与局部失败；consumer 内重复采样、私有值副本、私有 provider/graph owner 已撤销。尚无平台 producer 或产品策略的输入必须在专项表明确保持 unsupported，不能用另一个输入族的通过替代。V4 收口后才逐项进入 V5。

### V5：独立高级 epic

V5 不是一个可以整体“完成”的大阶段，也不允许用一个 epic 的通过外推其他项。当前能力与缺口只查[高级对象覆盖表](semantics/advanced-object-coverage.md)；以下每项分别立项、分别回滚、分别过完成门：

| epic | 共享交付对象 | epic 完成门 |
|---|---|---|
| Puppet | identity/frame/resource 下的 animation、simulation 与 geometry producer | 至少一个真实可见动作、constraint/mixing/attachment 负例、pause/reset/teardown 与预算门；未支持阶段保持 typed fail closed，旧产品 owner 归零 |
| 2D Lighting/HDR | normal/PBR/light/shadow/reflection 输入进入 Material Program、scene-post graph 与 color contract | author on/off、light/resource failure、HDR/tone-map ROI、光源/VRAM预算与非 HDR 安全回滚；官方 parity 另过预登记门 |
| 3D | model/node/material/camera/skeleton/animation/physics 的专用 importer/simulation，输出共享 Program/graph/compositor | hierarchy、camera、animation、missing/malformed asset、资源预算和 teardown 有正反门；整个 3D domain 可禁用且不影响 2D |
| RGB output | authored source selection、独立 publication 与权限受控 device adapter | topmost/hidden/composition source、无设备/拒权、连接/断开、rate limit 与 teardown 有门；禁用 adapter 不改变 wallpaper render |
| Offline bake | fixed clock、deterministic input/provider replay 与 encoder adapter，复用在线 IR/Program/graph/runtime | 帧序列、seed/audio/media/input replay、取消/进度、资源释放及 realtime-offline 对照有门；不得建立第二 renderer |
| Platform lifecycle | color management、多屏/scale/refresh、Space、sleep/wake、hot-plug 与 device-loss recovery | 每项状态变化都证明 generation/epoch、target/publication、provider/VM/particle 恢复和 stale 资源归零；失败可回到安全输出 |
| Performance / release | frame/CPU/GPU/内存/VRAM预算、长稳、双架构、许可证、签名、公证与 Gatekeeper | 代表内容与所需 matrix 的性能/压力/长稳通过，arm64/x86_64、Developer ID、hardened runtime、notarization/Gatekeeper 和发布依赖闭合；只在此门后声明 release-ready |

每个 epic 的精确 scope 由[高级对象覆盖表](semantics/advanced-object-coverage.md)对应行定义；宣告完成前，所有纳入 scope 的行都必须有完成、明确 unsupported 或平台策略结论。V5 的执行顺序由每次明确立项时的 corpus 影响、用户价值、风险与依赖决定；不得为它再创建一份平行 roadmap。所有 epics 都有上述结论后，才进入本文的最终退役门。

## 4. AI 主动纠偏合同

Scene 开发必须同时维护三个互不替代的轴：

| 轴 | 唯一用途 | 权威入口 |
|---|---|---|
| 目标合同 | 决定“应该怎样执行”、owner 和失败边界 | `AGENTS.md`、[兼容运行时架构](runtime-architecture.md)和本路线 |
| 当前事实 | 证明“当前代码实际怎样执行”及证据上限 | [能力台账](semantics/coverage-ledger.md)、专项表、[运行证据索引](semantics/runtime-evidence-index.md)和当前代码 |
| 偏差债务 | 记录目标与事实之间的首个可修复差异 | 当前 correctness atom；跨批遗留必须回写能力台账的明确待办 |

当前代码、旧测试、旧类型层级和历史 matrix 都只是描述性证据，不能自动升级成目标合同。AI 触达一个能力时必须把现状归为 `aligned`、`missing`、`contradictory`、`duplicate-owner`、`over-specialized`、`stale-document` 或 `unknown`；发现偏差后优先在当前纵向 atom 内纠正。若旧测试锁住已由目标合同和更强证据判定为错误的行为，应随实现一起改正测试，不能为了保持旧绿灯继续扩张错误架构。

若偏差超出当前用户结果，不得顺手大改；应先隔离错误 owner、保持可观察 fallback，并在能力台账写明 current、target、first breakpoint、所属 V 轨和退出条件。若新证据表明目标合同本身错误，必须先修改唯一目标合同并说明证据，再改代码；不能在实现里静默偏离规划。

本路线只决定工作轨，不复制 current 状态：

| 能力族 | 目标运行对象 | 路线 | 当前事实入口 |
|---|---|---|---|
| ordinary material/shader | Program + GraphExecutor | V0 | [Effect](semantics/effect-execution-coverage.md)、[Graph/Shader](semantics/render-graph-shader-coverage.md) |
| pass/FBO/command/dependency | shared graph/target/publication | V1 | [Graph/Shader](semantics/render-graph-shader-coverage.md) |
| SceneScript | ECMAScript VM + typed host bridge | V2 | [SceneScript](semantics/scenescript-api-coverage.md) |
| Particle | ordered component operation stream | V3 | [Particle](semantics/particle-component-coverage.md) |
| property/pointer/audio/media/text/provider | three typed frame channels | V4 横切 | [运行输入](semantics/runtime-input-property-coverage.md) |
| Puppet/lighting/HDR/3D/RGB/offline/platform | shared identity/frame/resource/Program/graph/output 上的独立 epic | V5 | [高级对象](semantics/advanced-object-coverage.md) |

发现未登记能力时，先在能力台账或对应专项表增加明确的 current/unknown/todo 行，再归入上述路线；不得再建一次性平行计划或在本路线手抄当前等级。

## 5. Fast Scene Suite

[`script/scene_fast_suite.json`](../../script/scene_fast_suite.json) 是这套低成本纵向开发集的机器合同，也是成员、选择状态和 readiness 的唯一事实入口。它固定七类能力形状、所需正反门、运行证据和指标字段；sample/layer identity 只允许存在于该开发清单、隔离 fixture 和报告中，不能进入产品 dispatch。

任何 `selection-required` 成员都不能执行或计为 Fast Scene Suite PASS，任意 `--sample-id` 或 full45 子集也不能冒充 suite PASS。成员的当前 approval/readiness 只查机器合同；每个成员只有登记 content digest、authored structure、expected route/first breakpoint、正反 oracle、ROI/事件、局部 fallback 和证据字段后才能变成 `approved`：

1. ordinary one-pass framebuffer effect；
2. ordinary pass + optional texture/combo；
3. ordered multi-pass + FBO；
4. copy/swap/history；
5. cross-layer/named provider；
6. SceneScript 可见 property/event；
7. Particle 常见 emitter/initializer/operator/renderer。

各路线段使用哪些成员由 manifest 的 V0–V3 mapping 决定。批准前仍可使用写明同等合同的代表性隔离内容推进纵向结果，但只能报告 `representative-content`，不能报告 Fast Suite。suite 是开发反馈环，不替代 fixed/full milestone，也不以任意非黑像素作为成功。

## 6. 批次工作方式

每批先填写一个最小纠偏卡：

```yaml
capability_id:
capability_profile:
target_contract:
current_observation_and_evidence:
deviation_class:
first_breakpoint:
correctness_atom:
shared_backbone_owner:
authored_input_schema:
shared_runtime_output:
product_output_owner_before:
product_output_owner_after:
route_state_before:
route_state_after:
fallback_reason_and_radius:
old_owner_retirement_condition:
unseen_composition_fixture:
positive_negative_and_visible_gate:
evidence_claim_limit:
remaining_deviation_and_exit_condition:
```

然后回答：

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

迁移中的每个 owner family 只能处于以下显式路由之一：

- `observe-only`：通用路径只收集差分，不决定产品输出；
- `prefer-generic`：通用路径先执行，失败按 typed reason 回到已验证旧路径；
- `generic-only`：在按架构合同登记的 `capability_profile` 内通用路径持有产品权，不自动外推整个 family 或 V 轨；经审查仍表达官方可观察行为、项目稳定公共合同或独立正反输入的 fixture/golden/截图 ROI 可以继续验证通用路径，但依赖旧内部类型、dispatch、私有常量组合或旧实现自生成预期的测试/oracle，以及旧可执行产品实现和 dispatch 必须删除，不得保留可重启的第二链；
- `disable-generic`：出现回滚条件时原子关闭该 `capability_profile` 的通用产品路由，不删除实现无关的 fixture 和诊断；仍有已验证旧 owner 时才可按 typed reason 回退，否则继续按现役失败分类处理：eligible visual failure 局部 fail soft 并保留安全 previous current，integrity/ABI/target/hazard/lifecycle/budget failure 硬拒绝最小不安全单元；任何分支都不得复活已退役 owner。

从 `prefer-generic` 升为 `generic-only` 前必须有新组合门、相关 Fast/代表内容、fallback 次数与原因、一次回滚演练、能力/证据回写，并证明旧 owner 不再被产品调用；同一独立 owner-migration 批次必须删除对应旧实现与专用测试 owner。不得长期保留静默双路由、可重启的第二链，也不得以“已经稳定”代替这些退出条件。

完成状态也分三层：`slice-visible` 只证明本纵向结果；`owner-migration-complete` 证明执行权与回滚合同完成；`bounded-profile-parity/release` 还必须通过预登记官方黑盒对照、生命周期、预算及所需发行门。前一层不能冒充后一层。

## 7. 指标

每个 V0–V4 checkpoint 只报告实际可采集字段；统一字段名由 Fast Suite manifest 的 `checkpointMetrics` 定义。最低包括：

- eligible authored units；
- compile/plan success；
- 实际 Program/graph/VM/component execution；
- GPU encoded effect passes；
- 至少一个非 base effect 可见的 scene 数；
- 局部降级和整 layer/scene 拒绝数；
- first compile、first effect frame、CPU/GPU frame time、内存；
- fallback 使用量及原因。

同时报告本批的语义压缩率：新增或修改多少产品执行 primitive，实际让多少此前未执行的 authored unit 进入执行。新增文件数、类型数、gate 数和台账行数不是正向 KPI；如果一个通用 primitive 只解锁一个已知 identity，必须解释为什么它仍是数据驱动能力而不是新的 profile。

没有统一 collector 的字段必须明确写 `not-collected`，不能填零或推测；本轮治理只建立字段合同，不声称已有自动 collector。指标只使用可实际采集的分母，不提前写百分比目标。compile success、route count、matrix PASS、非黑截图和进程存活均不能单独证明效果或兼容性。

## 8. 当前 V4 选择协议

当前主线只从[能力台账](semantics/coverage-ledger.md)、[运行输入与属性覆盖表](semantics/runtime-input-property-coverage.md)、实际 consumer 的专项表和[运行证据索引](semantics/runtime-evidence-index.md)中选择一个尚未闭合的 V4 typed producer/provider 纵向结果。已完成 V1–V3 批次的逐项过程、样本身份、报告路径、截图与当时的“下一门”只属于对应证据和 Git 历史，不得复制回本路线，也不得从其中续接任务。

下一批必须同时满足：

1. 对应一个真实 consumer，并能指出 producer/provider → immutable snapshot/publication → frame commit → consumer → next-frame/event 主链上的首断点；
2. 通过 typed identity/value/resource、generation/epoch 与统一 frame transaction 定义 capability，不让 consumer 自行重采样、解析或保存第二份状态；
3. 复用现有 property/resource publication、completion/rollback、GraphExecutor/VM/particle consumer 和唯一 compositor，不新增第二 registry、clock、graph/history 或输出链；
4. 同批闭合正常更新、missing/stale/cancel/invalid 的最小失败半径、新组合/未见 fixture与真实隔离运行；
5. 明确旧 consumer-local polling/profile owner 的撤权条件；平台 producer 或产品策略尚不存在时保持 typed unsupported，不用伪造输入或另一个输入族的通过代替。

候选只从[运行输入与属性覆盖表](semantics/runtime-input-property-coverage.md)、对应 consumer 专项表和[运行证据索引当前快照](semantics/runtime-evidence-index.md#1-当前证据快照)选择，不在本文维护名单。主实现者在编码前填写第 6 节纠偏卡并冻结一个纵向结果；若当前证据不能让任一候选满足上述五项，先补最小可区分证据，不退回 V1–V3 历史断点，也不以新增 consumer-local profile 制造可见结果。

V1-A/V1-B/V2/V3 bounded 完成事实已由能力台账、专项表与运行证据索引同步证明；若后续发现回归，按失败半径撤回对应产品 route 并修共享路径，不把 V4 主线改写成回收历史专用 owner。roadmap 只据权威当前事实推进段位，V4 完成门成立前不得进入 V5。

## 9. 完成与退役

当 V0–V5 的产品目标均已由[能力台账](semantics/coverage-ledger.md)和[运行证据索引](semantics/runtime-evidence-index.md)证明，所有待办都有完成、明确不支持或平台策略结论，且旧专用产品 owner 已删除/隔离后，本文转入历史目录。届时应以稳定架构合同和能力台账接管终态，不再创建另一份平行 roadmap。
