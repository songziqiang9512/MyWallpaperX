# Scene 开发方法

目标是在原生 macOS Swift/Metal 底座上兼容 Wallpaper Engine 作者的 Scene 行为与可见结果。执行结构遵循仓库架构合同；官方结果一致性按有界同输入对照验证，私有实现研究遵守下述 clean-room 隔离。

本参考保存 Scene 开发中跨批次仍有用的取证、纵向切片、identity、失效域和可见证据方法。它不保存当前路线阶段、compiler/VM 选择快照、能力数字、sample、route 统计或最近 PASS；这些只能从现役入口和当前运行取得。

## 目录

1. [按问题选择权威](#按问题选择权威)
2. [来源与上下文隔离](#来源与上下文隔离)
3. [重建统一执行链](#重建统一执行链)
4. [定义 correctness atom](#定义-correctness-atom)
5. [Identity、frame channel 与失效域](#identityframe-channel-与失效域)
6. [局部失败与事务安全](#局部失败与事务安全)
7. [Owner 迁移与 route](#owner-迁移与-route)
8. [验证与声明](#验证与声明)
9. [反漂移终审](#反漂移终审)

## 按问题选择权威

从 `docs/scene/README.md` 按任务选择现役路线，再按实际问题选择最小入口；导航本身不拥有阶段或能力事实：

| 问题 | 唯一入口 |
|---|---|
| 最终执行单元、语言/进程/失败目标 | `docs/scene/architecture/runtime-architecture.md` 与长期技术边界 |
| 工程结构、生命周期、性能与成本消融顺序 | `docs/scene/roadmap/engine-refactor-program.md` |
| 作者能力、可见正确性与兼容验收顺序 | `docs/scene/roadmap/scene-compatibility-roadmap.md` |
| 实际接线、进程、装载与释放 owner | `docs/scene/architecture/runtime-as-built-map.md`，随后核对 live call sites |
| 主链、普通帧成本与风险分级验证 | `docs/scene/development/development-workflow.md`；通用工具入口查仓库开发工作流 |
| 当前能力及明确缺口 | `docs/scene/capabilities/coverage-ledger.md` 与命中专项表 |
| 当前构建、GPU/compositor、sample、签名事实 | `docs/scene/capabilities/runtime-evidence-current.md` |
| 来源类别和可用边界 | `docs/scene/development/source-index.md` |
| 公开资料仍不足时的官方黑盒/clean-room 研究与独立实现交接 | `docs/scene/development/official-client-behavior-research-workflow.md` |
| corpus 中作者实际声明了什么 | `docs/scene/capabilities/scene-corpus-capability-inventory.md`；不证明运行支持 |
| gate 成员、phase、readiness | 当前脚本 `--help`、`script/scene_validation_gates.json`、`script/scene_fast_suite.json` |

不要每次 Scene 任务读取所有入口。工程任务与作者兼容任务分别由对应现役路线选序；涉及两条路线时选一个主结果与验收，能力台账和运行证据只回答各自事实。不要把当前 roadmap 阶段、具体 backend 推荐、旧计划、sample 数量或 evidence report 复制进 Skill。

## 来源与上下文隔离

做语义结论时使用 `source-index.md` 当前定义的来源名和边界，不从 Skill 复制一份固定枚举。始终分开：作者公开合同、固定官方客户端可观察结果、版本有界静态职责、authored corpus、第三方结构模式、项目当前证据和项目策略。

公开资料、现有 golden 和合法 corpus 仍不能回答会阻塞当前 atom 的 observable 时，先定义候选解释和区分实验，优先官方客户端黑盒差分。只有黑盒仍不能决定 producer、identity/state、顺序、生命周期或失败边界时，才启动有界 clean-room 静态研究。

`research-context-only` 内容、反编译地址/指令/伪代码、私有算法表达、shader、资产、payload 和常量表不能进入 implementation context。研究任务只交接经审查的中性行为合同、自有 fixture 与官方对照协议；实现由 fresh context 独立完成。第三方项目只提供职责/状态/顺序 checklist，不定义官方语义或可复制实现。

## 重建统一执行链

从真实输入向最终输出追踪，并用当前代码/布局 manifest 确认 owner：

```text
authored project/scene/package/resource
  -> loss-preserving decode and authored identity/order
  -> property/Timeline/script/input/provider state
  -> material/shader/effect graph preparation
  -> Program/reflection/binding/render state/targets
  -> current GraphExecutor and specialized producers
  -> ordered layer and scene composition
  -> terminal drawable/readback observation
```

“通用”表示共享 scene/object identity、frame semantics、typed state、resource/provider、Program、graph/target lifecycle 和唯一 compositor，不表示一个巨型 renderer。2D、3D、particle、text、media、lighting 可以保留必要 importer/simulation/geometry/provider，但不能拥有第二资源系统、clock、graph、property tree、history 或 final output。

目录和二级职责从 `script/scene_source_layout.json`、当前源码和自动测试获取。不要把旧目录表当长期 owner；新增或移动类型族时同步所有现役 standalone source lists/harnesses。

## 定义 correctness atom

每批只闭合一个可回滚纵向结果：

```yaml
capability_and_target: bounded author-visible result plus target contract
source_boundary: named source category and what it proves
current_fact_and_debt: first unsupported/wrong identity; owner; fallback/route
correctness_atom: real input -> producer -> executor -> publication -> user result
previous_current: local failure must preserve which safe input/output
counterexamples: unsafe rejection; local failure; unseen composition/name
evidence_limit: highest claim this batch can support
```

先用隔离真实内容定位首断点，再实现服务该结果的最小公共 slice。parser、IR、diagnostic、census、完整 compiler/VM/particle platform、full matrix 或 release gate 只有实际服务当前 atom 或风险升级时才进入；它们单独通过不能记为视觉能力。

checkpoint 使用新组合或未见 fixture 证明公共 primitive 不依赖 sample/layer/path/hash/asset/screenshot identity。只有 corpus fingerprint/schema/family 解释变化或现有 snapshot 无法回答影响面时刷新全 corpus。

## Identity、frame channel 与失效域

先读取 `docs/scene/architecture/runtime-architecture.md` 当前的作者 identity/order、typed frame channel、frame commit、optional resource 和失效域合同；本 Skill 不复制其枚举。为当前 producer 建立一张工作表：payload contract、source identity/generation、commit phase、consumer、最小 invalidation domain、stale/teardown 反例。

沿真实命令链区分 original input、effect previous/current、named/temporary target、history、cross-layer dependency、provider publication 与 terminal compositor output。验证 `copy`、`swap`、`clear`、`compose`、`bind` 和 pass target 按现役合同作为命令保留，不能因降低为无类型 metadata 丢失。

把每个动态输入映射到现役合同中的恰好一个 primary channel，并显式记录跨 channel publication；不要在 consumer 内重建另一套状态。用当前失效域规则选择最小重建范围，加入“普通值变化不会 relaunch”和“topology 变化不会复用 stale graph”的反例。对 optional resource 分别测试 authored absent、pending、ready、wrong-purpose，不伪造资源或扩大 variant。

## 局部失败与事务安全

实现前重读 `AGENTS.md` 和 `docs/scene/architecture/runtime-architecture.md` 的当前失败分类与 previous-current 合同；Skill 中的例子不能重定义 hard/soft 边界。为每个 failure 记录：identity、canonical classification、最小不安全或局部单元、previous current、真实依赖子图、是否已 encode/publish，以及 typed diagnostic。

eligible local failure 必须证明 previous current 与不受影响 suffix 仍可提交；unsafe failure 必须证明只拒绝当前最小不安全单元。不能从错误发生在 shader、binding、VM 或 provider 这一名称直接推断半径。任何降级都不得伪造 target/history/resource/binding，不能在部分 encode 已提交后假装 CPU rollback，并须保持现役 target reservation、completion、publication、rollback 和 epoch 原子合同。若新路径扩大 crash、整 layer/frame 拒绝或明显视觉回退，先撤回产品 route，保留 fixture/diagnostic，再缩小 atom。

## Owner 迁移与 route

route state 的名称、定义和进入条件只从当前 `AGENTS.md`、runtime architecture、roadmap 与代码/diagnostics 读取。对每个迁移 owner 实时确认：谁发布产品输出；新旧路径是否静默双执行；fallback typed reason/identity/count；回滚是否原子；旧 owner 是否仍被产品引用。

公共前置 slice 可以在旧 owner 仍存在时交付，但不能声称 owner migration。只有 canonical gate 要求的可见正证、局部失败反例、未见组合、fallback 审计和回滚演练成立，且旧产品引用已撤销，才能更新 route/owner 权威。禁止长期静默双输出或把故障回滚状态当稳态完成。

## 验证与声明

从仓库开发工作流和 Scene 开发工作流选择 `script/verify_scene_change.py` 的适用阶段，运行前读取当前 `--help` 和预览，确认路径选择、phase 和 runtime prerequisites；`--owned-path` 只选择本批已变更文件，`--path` 可预览预期影响面，均不是文件锁或执行沙箱。inner 验证最近正反例；Swift 产品或构建输入变化做 checkpoint Debug build；GPU/VM/resource/lifecycle/visible 变化补相称 integration；共享合同、完整能力或发布结论才升级 milestone。

可见或动态声明沿同一 identity 证明：实际 input -> selected route/Program/VM/component -> execution completion -> resource/target publication -> terminal compositor -> next-frame -> 预登记 ROI/事件方向 -> local-failure counterexample。没有这条链，只报告 structural/compiled/routed/host-stage 的真实等级。

分别处理当前 slice 可见、owner migration、官方 bounded parity 和 release readiness；等级定义查技术栈合同、对应路线与验证工作流，当前执行选择查 gate。recognized、wired、census、compile、route count、non-black、matrix 或单样本不能外推完整兼容。

真实 Workshop/Scene 根只读；runtime home、属性注入、cache、output 和样本使用隔离副本。确认启动的是当前 App/build，不复用旧截图/report/terminal observation。

## 反漂移终审

冻结 owned diff 后确认：没有 identity-based 视觉算法；没有为新 effect/script/particle family 新增名称专用产品 owner；没有第二 renderer/resource/clock/graph/property/history/compositor；作者顺序、slot hole、target/publication 未丢失；现役 runtime architecture 定义的 typed frame channels 和最小失效域未混淆；local visual failure 保留 previous current 而 unsafe error 仍 fail closed；route 可观察且声明不超过证据；implementation context 未消费 research-only/第三方实现；Skill 没有覆盖当前 roadmap、ledger、evidence 或机器 manifest。
