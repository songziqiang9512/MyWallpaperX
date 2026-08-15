# Scene 兼容执行路线

<!-- document-role: active-plan -->

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

## 2. 当前路线前提

本节不复述 current capability，也不保存底座、backend、失败半径或样本状态的移动快照。当前能力与缺口只读取[能力台账 §1](semantics/coverage-ledger.md#1-口径)，当前运行身份与首断点只读取[运行证据索引 §1](semantics/runtime-evidence-index.md#1-当前证据快照)；两者变化时先更新各自权威，再重新审查本文的路线选择，禁止直接在计划中手改一份平行事实。

本文只保存由上述现役权威导出的计划决策：下一批选择 V0，在现有产品主链内建立最小、真实、可回退的普通 effect 执行切片，不先建设 G0/G1 式完整平台。仓库中的历史专用实现、旧测试、旧类型层级和旧 matrix 只构成需要审计的偏差候选，不自动取得目标架构或下一批执行权。

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

### V4：动态输入横切轨

V4 不是排在 V3 后面的串行阶段，而是随 V0–V3 的真实 consumer 一起接入。所有输入在同一 frame commit 下走相应 typed channel，不在 consumer 内另建状态系统：

| 输入族 | typed output | 首个公共 consumer | 正反门 | 旧路径退出条件 |
|---|---|---|---|---|
| user property / Timeline / Texture Variants | immutable value snapshot；variant 变化进入 Program invalidation | V0 material、V2 VM、V3 particle | 同值稳定、新值下一帧生效、非法 target 局部拒绝 | consumer 不再自行解析 property 或保存第二份值 |
| pointer / hover / click / drag | ordered event snapshot + local/world coordinates | V2 VM、V3 control point | exact event order/identity、outside-hit 负例、capture/teardown | bounded native profile 不再持有产品事件 owner |
| system/Scene audio | immutable audio snapshot 或 provider publication | V0 Program、V2 AudioBuffers、V3 component op | 固定 buffer、静音/invalid 负例、帧相位 | consumer 不再各自重采样或保存私有 FFT |
| media / video / artwork | resource/provider publication + value/event snapshot | V0 material、V2 media API、Text | generation、last-ready、stale/cancel、next-frame | 专用 current-cover/text profile 不再持有产品 owner |
| dynamic text | resource publication；尺寸变化另触发 geometry/extent invalidation | Text compositor、V2 mutation | 内容、baseline/bounds、空值/字体失败 | consumer 不再绕过 provider publication |
| nested/effectful provider | provider publication + topology transaction | V1 dependency graph | named identity、dependency failure、teardown | provider 不再拥有私有 graph/current/history |

### V5：独立高级 epic

V5 不是一个可以整体“完成”的大阶段。以下 epic 分别按 corpus 影响和用户价值立项，互不阻塞：

| epic | entry | 交付对象 | 最小门 | rollback / 完成 |
|---|---|---|---|---|
| Puppet | authored puppet carrier + animation/mixing/constraint/physics | 共享 identity/frame/resource 下的专用 simulation/geometry producer | 一个可见动作、约束负例、teardown | feature route 可回退；旧 owner 归零后才算迁移完成 |
| 2D Lighting/HDR | normal/PBR/light/shadow/reflection/HDR declarations | shared Material Program、scene post graph 和 color contract | light on/off、HDR/tone-map ROI、资源失败 | 保留非 HDR compositor；parity 另过官方门 |
| 3D | model/node/material/camera/skeleton/physics | 专用 importer/simulation，输出共享 Program/graph/compositor | hierarchy、camera、animation、missing asset | 3D domain 可整体停用且不影响 2D |
| RGB device | authored RGB output | 权限受控的 provider/device adapter | 无设备、拒权、连接/断开 | adapter 可禁用，不影响画面执行 |
| offline bake | fixed clock + deterministic input/provider | 复用在线 IR/graph/runtime 的离屏输出 | 帧序列、音频/随机合同、取消 | 回退实时播放；不得建立第二 renderer |
| platform/release | color management、多屏、刷新率、sleep/wake/reset、性能、签名 | 恢复、预算与发行合同 | 长稳、资源恢复、双架构、签名/公证 | 不倒灌阻塞 V0 首张画面；对外发布前必须闭合 |

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

任何 `selection-required` 成员都不能执行或计为 Fast Scene Suite PASS，任意 `--sample-id` 或 full45 子集也不能冒充 suite PASS。V0-0 的计划动作是为前两类各批准一个成员；每个成员只有登记 content digest、authored structure、expected route/first breakpoint、正反 oracle、ROI/事件、局部 fallback 和证据字段后才能变成 `approved`：

1. ordinary one-pass framebuffer effect；
2. ordinary pass + optional texture/combo；
3. ordered multi-pass + FBO；
4. copy/swap/history；
5. cross-layer/named provider；
6. SceneScript 可见 property/event；
7. Particle 常见 emitter/initializer/operator/renderer。

V0 只需要前两类，V1 增加 3–5，V2/V3 分别增加 6/7。批准前仍可使用写明同等合同的代表性隔离内容推进首张画面，但只能报告 `representative-content`，不能报告 Fast Suite。suite 是开发反馈环，不替代 fixed/full milestone，也不以任意非黑像素作为成功。

## 6. 批次工作方式

每批先填写一个最小纠偏卡：

```yaml
capability_id:
target_contract:
current_observation_and_evidence:
deviation_class:
first_breakpoint:
correctness_atom:
route_state_before:
route_state_after:
fallback_reason_and_radius:
positive_negative_and_visible_gate:
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
- `generic-only`：通用路径持有产品权，旧路径只可作为离线 oracle；
- `disable-generic`：出现回滚条件时原子关闭通用产品路由，不删除 fixture 和诊断。

从 `prefer-generic` 升为 `generic-only` 前必须有新组合门、相关 Fast/代表内容、fallback 次数与原因、一次回滚演练、能力/证据回写，并证明旧 owner 不再被产品调用；之后才删除对应旧实现。不得长期保留静默双路由，也不得以“已经稳定”代替这些退出条件。

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

## 8. 下一批精确断点

V0 第一批从能力台账登记的 `SceneEffectStageCompiler.resolveDedicatedStage -> noBackendAccepted` 断点开始：

1. V0-0 从隔离 corpus 为 Fast Scene Suite 前两类各批准一个成员；若选择成本阻塞编译 spike，先用同合同的代表内容推进，但不得声称 suite 已建立；
2. 在独立 subprocess harness 建立 upstream shader backend spike；第一条普通 pass 能编译后再做有界 source census，按真实失败类别决定 normalization，不以全 corpus 报告阻塞首次出画面；
3. 复用现有 source graph、preparation、slot/default/combo 和 Program ABI，绕开 effect-name matcher；
4. 让 ordinary authored stage 先尝试 generic backend；
5. 把 frontend analyzer 从默认 admission 改为 diagnostic/oracle，安全/ABI/resource 检查仍保留；
6. 将失败半径收窄到当前 effect，并保留 previous current；同时修正 renderer 中 claimed layer/quad draw 失败后停止整个后续 layer suffix 的行为；
7. 用已批准的前两类或明确标记的代表内容取得可见正证；
8. 按显式 route state、fallback metric 和回滚门决定哪些 dedicated backend 可以撤权。

如果 shader backend spike 证明 glslang → SPIR-V → SPIRV-Cross MSL 对当前 dialect 不可行，保留 fixture、diagnostics 和失败分类，再评估 Slang 或 HLSL/DXC 路径；不得在没有 corpus 数据前并行建设三套 compiler。

## 9. 完成与退役

当 V0–V5 的产品目标均已由[能力台账](semantics/coverage-ledger.md)和[运行证据索引](semantics/runtime-evidence-index.md)证明，所有待办都有完成、明确不支持或平台策略结论，且旧专用产品 owner 已删除/隔离后，本文转入历史目录。届时应以稳定架构合同和能力台账接管终态，不再创建另一份平行 roadmap。
