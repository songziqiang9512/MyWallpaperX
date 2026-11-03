# Scene 开发方法

目标是在原生 macOS Swift/Metal 底座上兼容 Wallpaper Engine 作者的 Scene 行为与可见结果。执行结构遵循仓库架构合同；官方结果一致性按有界同输入对照验证，参考研究与独立实现遵守下述方法。

本参考保存 Scene 开发中跨批次仍有用的取证、纵向切片、identity、失效域和可见证据方法。它不保存当前路线阶段、compiler/VM 选择快照、能力数字、sample、route 统计或最近 PASS；这些只能从现役入口和当前运行取得。

## 目录

1. [按问题选择权威](#按问题选择权威)
2. [来源与独立实现](#来源与独立实现)
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
| 组件分类、准备/实例状态/消费/释放职责 | `docs/scene/capabilities/runtime-systems-reference.md`；源码入口由运行架构维护 |
| 工程结构、生命周期与成本消融设计 | `docs/scene/architecture/runtime-architecture.md`，当前问题从队列定位 |
| 作者能力、可见正确性与兼容验收顺序 | `docs/scene/roadmap/scene-open-breakpoint-queue.md` |
| 实际接线、进程、装载与释放 owner | `docs/scene/architecture/runtime-architecture.md`，随后核对 live call sites |
| 主链、普通帧成本与风险分级验证 | `docs/scene/development/development-workflow.md`；通用工具入口查仓库开发工作流 |
| 当前能力及明确缺口 | `docs/scene/capabilities/README.md` 与命中专项表 |
| 当前构建、GPU/compositor、sample、签名事实 | `docs/scene/capabilities/runtime-evidence-current.md` |
| 来源类别和可用边界 | `docs/scene/development/source-index.md` |
| 官方黑盒、参考研究与独立实现 | `docs/scene/development/official-client-behavior-research-workflow.md` |
| corpus 中作者实际声明了什么 | `script/scene_capability_census.py` 的本次生成报告；不证明运行支持 |
| gate 成员、phase、readiness | 当前脚本 `--help`、`script/scene_validation_gates.json`、`script/scene_fast_suite.json` |

不要每次 Scene 任务读取所有入口。由当前问题队列和性能工作卡定位一个主结果与验收；能力表和运行证据只回答各自事实。不要把当前 roadmap 阶段、具体 backend 推荐、旧计划、sample 数量或 evidence report 复制进 Skill。

## 来源与独立实现

做语义结论时使用 `source-index.md` 当前定义的来源名和边界，不从 Skill 复制一份固定枚举。始终分开：作者公开合同、固定官方客户端可观察结果、版本有界静态职责、authored corpus、第三方结构模式、项目当前证据和项目策略。

公开资料、现有 golden 和合法 corpus 仍不能回答当前问题时，定义候选解释和区分实验，选择能最快消除关键歧义的黑盒或有界源码/静态研究；静态结论不能替代官方运行结果。

可以阅读作者脚本、shader、参考源码和反编译资料，研究后由同一 Agent 继续独立实现；阅读本身不触发停工或上下文隔离。不得直接复制、照译或移植参考实现；把结论落实到本项目的唯一 owner，以自有正反 fixture 和实际运行验收。第三方实现不能定义官方语义或证明官方结果一致。

## 重建统一执行链

从真实输入向最终输出追踪，并用当前代码/布局 manifest 确认 owner：

```text
authored project/scene/package/resource
  -> loss-preserving decode and authored identity/order
  -> prepared Program/graphs/bindings/resource requirements
  -> typed frame update: properties/Timeline/VM/input/provider state
  -> Metal encode through the existing executors and producers
  -> ordered layer and scene composition
  -> terminal drawable/readback observation
```

准备工作发生在加载和实际失效边界；普通帧消费准备结果，只更新活动状态、采用就绪资源并编码。追踪时分清作者事实、不可变准备结果和实例当前值，以及变换依赖、行为更新顺序和渲染依赖；这些职责不要求新增平行状态树、管理器或统一组件框架。具体边界按运行时架构与组件合同裁决。

“通用”表示共享 scene/object identity、frame semantics、typed state、resource/provider、Program、graph/target lifecycle 和唯一 compositor，不表示一个巨型 renderer。2D、3D、particle、text、media、lighting 可以保留必要 importer/simulation/geometry/provider，但不能拥有第二资源系统、clock、graph、property tree、history 或 final output。

所有effect沿实际编译、接口/表示、资源与执行合同准入；不要把效果名、固定源码形状、pass数量或kernel/方向/scale组合当播放许可。已由原owner接纳的事实直接传递。遗留源码形状补偿按[技术栈合同](../../../../docs/architecture/technology-stack-boundaries.md)作为待通用化债务处理，不能以继续扩大模式名单代替通用能力。

目录和二级职责从 `script/scene_source_layout.json`、当前源码和自动测试获取。不要把旧目录表当长期 owner；新增或移动类型族时同步所有现役 standalone source lists/harnesses。

## 定义 correctness atom

常规兼容修复以一个可验证纵向结果限定范围：

```yaml
capability_and_target: bounded author-visible result plus target contract
source_boundary: named source category and what it proves
current_fact_and_debt: first unsupported/wrong identity; owner; fallback/route
correctness_atom: real input -> producer -> executor -> publication -> user result
previous_current: local failure must preserve which safe input/output
counterexamples: unsafe rejection; local failure; unseen composition/name
evidence_limit: highest claim this batch can support
```

先用隔离真实内容定位首断点，再实现服务该结果的最小公共 slice。parser、IR、diagnostic、census、完整 compiler/VM/particle platform、full matrix 或 release gate 只有实际服务当前结果或风险升级时才进入；它们单独通过不能记为视觉能力。

架构级任务另按工程设计中的迁移合同核对完整范围、迁移前正确能力及最终退出条件，按能力族分批落实和提交。每批明确原 owner 的退出与独立收益，不能用一个易验证的小切片、目录搬迁或新增 facade 替代整体迁移；最终验证也不能缩成迁移中恰好通过的样本集合。

收口分别核职责合同、实际执行与证据覆盖。没有普通帧解析、没有测得热点或未发现运行错误，不能关闭仍违反目标依赖/分期合同的真实结构债；纯DTO、混合namespace与算法调用也不能仅凭词法数混判。有限Context/descriptor审查与少量direct-host结果不能代替全部组件寿命和所要求的产品入口；入口覆盖按[验证方法](verification-and-handoff.md#首次隔离运行)实际经过的链裁决。由现役合同补齐真实缺口，不为清数字新增wrapper/cache或把独立兼容缺口扩成无限重构。

checkpoint 使用新组合或未见 fixture 证明公共 primitive 不依赖 sample/layer/path/hash/asset/screenshot identity。只有 corpus fingerprint/schema/family 解释变化或现有 snapshot 无法回答影响面时刷新全 corpus。

## 新增或全量样本筛查

先读 `docs/scene/development/development-workflow.md#声明扫描与运行诊断`，复用其 census → benchmark → normalizer → archive 链。已知样本集合同时核本次 snapshot 与所选 subset/archive，不把历史报告分母直接当新增基线。一次盘点产生能力并集与影响面，family/profile/声明数量不当独立加载链数。

批量筛查优先现有优化 DEBUG 配置，每批 App只stage一次；按当前 `--help` 设置隔离worker、Ready后3–5秒及有界并发，先小批再按设备余量扩大。`--log-only --terminal-snapshot` 可附一次 after Metal读回，导出缩放保持原渲染尺寸；它仍是诊断profile。核同一捕获request、command buffer、Surface/frame与GPU回执，再把PNG作为画面观察；绑定、局部graph tail及全景非黑均不授逐输入可见贡献。普通Debug冷准备超时先区分配置/争用，只补未决项；过渡、延迟和输入分支只对相应子集延长，不整批重复。

分别核作者声明、被选输入和实际消费；包内库存、注释样例、未选条件分支不能作缺图分母，聚合加载比例只作线索，raw ordinal或pass归因丢失则保unknown。旁路copy的GPU完成不授原effect执行；无graph的普通/粒子输出可由唯一捕获request/CB/Surface/GPU及drawable token/extent见证，不虚构graph ID。恢复前后的失败与成功分开保留；pre-Ready拒绝不能不经同subject和后续消费者核对就当持续故障，也不能用一个后续good掩盖身份/安全错误。看图先核阶段与输入，再找作者参考；共同首错回当前队列核是否已闭，再选公共修复，历史raw拒绝不能直接重开现役已修项。

## Identity、frame channel 与失效域

先读取 `docs/scene/architecture/runtime-architecture.md` 当前的作者 identity/order、typed frame channel、frame commit、optional resource 和失效域合同；本 Skill 不复制其枚举。为当前 producer 建立一张工作表：payload contract、source identity/generation、commit phase、consumer、最小 invalidation domain、stale/teardown 反例。

沿真实命令链区分 original input、effect previous/current、named/temporary target、history、cross-layer dependency、provider publication 与 terminal compositor output。验证 `copy`、`swap`、`clear`、`compose`、`bind` 和 pass target 按现役合同作为命令保留，不能因降低为无类型 metadata 丢失。

把每个动态输入映射到现役合同中的恰好一个 primary channel，并显式记录跨 channel publication；不要在 consumer 内重建另一套状态。用当前失效域规则选择最小重建范围，加入“普通值变化不会 relaunch”和“topology 变化不会复用 stale graph”的反例。对 optional resource 分别测试 authored absent、pending、ready、wrong-purpose，不伪造资源或扩大 variant。

## 局部失败与事务安全

实现前重读 `AGENTS.md` 和 `docs/scene/architecture/runtime-architecture.md` 的当前失败分类与 previous-current 合同；Skill 中的例子不能重定义 hard/soft 边界。为每个 failure 记录：identity、canonical classification、最小不安全或局部单元、previous current、真实依赖子图、是否已 encode/publish，以及 typed diagnostic。

eligible local failure 必须证明 previous current 与不受影响 suffix 仍可提交；unsafe failure 必须证明只拒绝当前最小不安全单元。不能从错误发生在 shader、binding、VM 或 provider 这一名称直接推断半径。任何降级都不得伪造 target/history/resource/binding，不能在部分 encode 已提交后假装 CPU rollback，并须保持现役 target reservation、completion、publication、rollback 和 epoch 原子合同。若新路径扩大 crash、整 layer/frame 拒绝或明显视觉回退，先撤回产品 route，保留 fixture/diagnostic，再缩小 atom。

## Owner 迁移与 route

route state 的名称、定义和进入条件只从当前 `AGENTS.md`、runtime architecture、roadmap 与代码/diagnostics 读取。对每个迁移 owner 实时确认：谁发布产品输出；新旧路径是否静默双执行；fallback typed reason/identity/count；回滚是否原子；旧 owner 是否仍被产品引用。

公共前置 slice 可以在旧 owner 仍存在时交付，但不能声称 owner migration。按受影响合同验证可见行为、局部失败、未见组合及实际使用的 fallback/回滚边界，撤销旧产品引用后再更新 owner 权威。复用已有请求、失效和输出机制；直接替换重复职责不因此要求新建 route registry、认证关卡或迁移状态机。禁止长期静默双输出或把故障回滚状态当稳态完成。

## 验证与声明

从仓库开发工作流和 Scene 开发工作流选择 `script/verify_scene_change.py` 的适用阶段，运行前读取当前 `--help` 和预览，确认路径选择、phase 和 runtime prerequisites；`--owned-path` 只选择本批已变更文件，`--path` 可预览预期影响面，均不是文件锁或执行沙箱。inner 验证最近正反例；Swift 产品或构建输入变化做 checkpoint Debug build；GPU/VM/resource/lifecycle/visible 变化补相称 integration；共享合同、完整能力或发布结论才升级 milestone。

按所声明的结果沿同一 identity 取证：实际 input -> selected route/Program/VM/component -> execution completion -> 对应 consumer。视觉结果核 resource/target publication、terminal compositor 与预登记 ROI；声音、事件和脚本状态核各自真实输出或事件消费者。next-frame、局部失败反例按受影响语义选择；未到相应 consumer 时，只报告实际到达的阶段。

像素正控只要求当前问题必需的真实贡献；先按既有几何、alpha与颜色合同确认oracle，未覆盖区及合法中性插值不必变化。仅断言误设且产品、输入、载体、二进制均未改时，保首失败并复用同身份有效GPU读回重放最终断言；不能称新GPU运行。

分别说明实际可见范围、owner交接、官方有界对照与发行验证；证据要求查技术栈合同和验证工作流，当前执行选择查gate。recognized、wired、census、compile、route count、non-black、matrix 或单样本不能外推完整兼容。

真实 Workshop/Scene 根只读；runtime home、属性注入、cache、output 和样本使用隔离副本。确认启动的是当前 App/build，不复用旧截图/report/terminal observation。

先核输入协议的调度时基：墙钟秒位、启动后时长与 simulation cadence 不能混用。运行窗口须覆盖协议规定的触发与尾部观测；窗口尚未覆盖该区间时，缺输入边或截图只能记取证未完成。已覆盖仍无事件则定位输入调度链，不能无限归为等待。延长窗口仍保原输入和失败记录，不以移动触发时间或取消断言冒充行为恢复。

## 反漂移终审

冻结 owned diff 后确认：没有 identity-based 视觉算法；没有为新 effect/script/particle family 新增名称专用产品 owner；没有第二 renderer/resource/clock/graph/property/history/compositor；作者顺序、slot hole、target/publication 未丢失；现役 runtime architecture 定义的 typed frame channels 和最小失效域未混淆；local visual failure 保留 previous current 而 unsafe error 仍 fail closed；route 可观察且声明不超过证据；研究来源与局限已标清，实现未直接复制、照译或移植参考代码；Skill 没有覆盖当前 roadmap、ledger、evidence 或机器 manifest。
