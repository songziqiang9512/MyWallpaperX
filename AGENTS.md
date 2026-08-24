# MyWallpaperX 开发规则

本文件只保存会改变实现、验证、提交或工作区安全的长期约束。能力数字、样本结论、运行报告、批次状态和历史迁移记录不在这里重复。

## 1. 工作与安全边界

- 先区分讨论、只读审查、诊断和实现。只读任务不得修改、构建、生成缓存、暂存或提交；实现任务默认做到与风险相称的可验证结果。
- 开工先读 `git status`，保留已有改动并确认本批文件所有权。禁止 `git reset --hard`、`git checkout --`、`git clean`、`git add -A` 和任何会覆盖他人工作的宽泛操作。
- 真实 Scene 样本根 `~/Movies/MyWallpaperX/创意工坊/Scene` 只读。benchmark、属性注入和缓存只能使用隔离副本、隔离 Workshop root 与临时 `HOME`。
- 只改当前目标的完整职责边界。可为了闭合结果移动或重组整个类型族，但不得顺手清理无关代码；计划外问题进入现役能力台账或路线后另批处理。
- 删除历史材料、唯一失败现场或归属不明的生成物前必须列出精确清单并取得确认。禁止对仓库根、`.codex` 根或真实样本根做递归清理。

## 2. 事实入口与证据边界

按问题读取最小入口：

1. 全项目导航与文档角色：[`docs/README.md`](docs/README.md)；
2. 长期语言、进程和依赖边界：[`technology-stack-boundaries.md`](docs/architecture/technology-stack-boundaries.md)；
3. Scene 目标处理方式：[`runtime-architecture.md`](docs/scene/runtime-architecture.md)；
4. Scene 唯一现役顺序：[`scene-compatibility-roadmap.md`](docs/scene/scene-compatibility-roadmap.md)；
5. 当前能力与运行事实：[`coverage-ledger.md`](docs/scene/semantics/coverage-ledger.md)和[`runtime-evidence-index.md`](docs/scene/semantics/runtime-evidence-index.md)；
6. authored corpus 影响面：[`scene-corpus-capability-inventory.md`](docs/scene/semantics/scene-corpus-capability-inventory.md)，它不证明运行支持；
7. 已退役计划、评审和基线：[`docs/history/README.md`](docs/history/README.md)，只用于追溯。

冲突时依次采用：当前代码与可复现运行证据、本文、长期架构合同、专题当前状态/稳定合同、现役计划、历史证据。这个顺序只裁决“当前是什么”的事实冲突，不允许当前错误实现覆盖目标合同；目标合同仍按来源边界由官方作者行为、本文与长期架构合同裁决。历史文件中的“当前”“下一批”和命令没有现役约束力。

每个实现判断必须同时写清三条轴：**目标合同**说明按官方作者行为与项目长期架构最终应当怎样；**当前事实**只说明当前代码和可复现证据现在怎样；**偏差债务**登记二者差异、现任 owner、fallback/route state、纠正门和退役条件。旧代码、旧测试和旧目录只证明现状，不得反向成为规范。AI 触达一个现有 owner 时必须主动列出本职责内的偏差，并在当前纵向结果所需范围内纠正；不得为了兼容已知错误实现而扩张错误抽象、专用分支或测试预期。暂时无法同批纠正的偏差必须显式留债并保持目标合同不变。

必须使用[Scene 资料来源索引](docs/scene/semantics/source-index.md)的七类命名来源：`official-public-contract`、`official-client-dynamic-golden`、`official-client-static-observation`、`authored-corpus-observation`、`third-party-reference-pattern`、`MyWallpaperX-current-evidence`和`MyWallpaperX-strategy`。corpus 只证明作者写了什么，项目当前证据只证明现在做到了什么，二者都不能直接变成目标策略。动态观察证明固定条件下发生了什么，不证明内部实现；静态观察只提供版本有界的职责和顺序，不证明画面。不得把官方未公开的内部 GraphExecutor/算法归给官方，也不得用 MirageWallpaper 定义官方语义。Mirage 只可借鉴职责、状态传播和顺序；不得复制其源码、shader、资产、payload、常量组合、算法表达或测试数据。

不得把 `recognized`、`wired`、静态 census、compile success、路由计数、非黑截图、matrix PASS 或单个样本通过表述为完整兼容或 Wallpaper Engine 视觉等价。

### 2.1 官方客户端行为研究

- 官方公开合同、现役资料、既有固定客户端证据和合法 corpus 仍不能回答一个会阻塞当前纵向切片的可观察语义时，先定义首断点、候选解释和区分它们的 observable，再按[官方客户端行为研究与一致性验证工作流](docs/scene/semantics/official-client-behavior-research-workflow.md)执行。
- 能由固定输入的官方客户端黑盒差分回答时优先测行为。只有黑盒仍不能决定 producer、state/identity、顺序、生命周期或失败边界时，才对合法取得、版本/build/hash 固定的本地客户端做范围明确的 clean-room 静态分析；不得把 Ghidra 变成每项功能的前置仪式。
- 静态研究只提炼高层字段归属、职责、状态、顺序和生命周期。产品实现只能消费项目自有行为合同、正反 fixture 和官方结果对照协议；不得保存、提交或照译地址、指令、伪代码、函数体、私有算法表达、shader、资产、payload、常量表或原始分析工程。
- 实际查看地址、指令、反编译伪代码/函数体/控制流、连续私有布局或调用链、私有 shader/payload/算法表达/公式/常量表等可还原实现表达的 clean-room 静态研究，必须与重叠职责的产品实现使用隔离任务和 fresh context；研究任务不得修改产品源码，实现任务只能接收经过审查的中性行为合同、自有 fixture 与官方黑盒对照协议，不得继承原始分析输出、上下文或笔记。
- 标为 `research-context-only` 的取证页只能由独立研究任务读取；implementation task 必须从现役入口和中性合同开始，不得宽泛扫入取证页。历史摘要、旧计划、高层静态结论、经审查的中性合同和历史证据本身不构成上下文污染，只能作为低权重线索，并须用当前代码、现役权威和可复现证据重新验证，不能直接续接其“当前”结论。
- 实现上下文意外看到禁止跨界的原始或可还原实现表达时按职责重叠处理：若它会影响当前实现选择，立即停止该职责的产品写入，完成中性交接并由 fresh implementation context 接手；若能够明确证明与当前切片无关，则隔离精确内容、不使用也不传播，可继续不重叠的实现。无法判断是否重叠时按重叠处理。
- 算法和 Metal 实现可以独立选择；对声称兼容的 bounded profile，固定输入、环境、时间和事件下的画面、事件顺序、状态、资源生命周期与失败结果必须通过预先登记的官方客户端对照容差。未运行官方对照时不得声称官方结果一致。

## 3. Scene 快速兼容执行

### 3.1 默认执行作者数据，不默认扩张专用准入

- 新内容首先尝试走声明式 definition/material/shader、通用 graph、真实 ECMAScript VM、particle component registry 和统一 Metal executor。
- definition/material/shader path、component/API name 可以选择作者数据、共享 primitive、缓存、资源和诊断；sample/layer/path/hash/截图身份不得选择特制视觉算法或固定输出。
- 除非现有 IR 无法表达多个内容都会复用的新 primitive，不新增 effect-specific planner/renderer、固定脚本 profile、完整 particle preset renderer 或样本产品旁路。
- 现有 bounded frontend、exact planner 和专用 renderer 是迁移 fallback/oracle。通用路径取得相同可见结果并稳定后再精确撤权；不得要求每个前置批次都先删除旧 owner，也不得长期保留静默双路由。
- 每个迁移 owner 必须显式登记 route state：`observe-only` 只观察/诊断、不持有产品输出；`prefer-generic` 由通用路径优先、旧 owner 仅作带原因的已验证 fallback；`generic-only` 只有通用路径持有产品执行权，旧实现只可作测试 oracle；`disable-generic` 只用于故障回滚并形成待退出偏差债务。每次 fallback 都必须输出 typed reason、影响 identity 和可聚合计数。
- route state 变更必须证明原子切换和回滚演练。进入 `generic-only` 前至少需要目标纵向结果、局部失败反例、新组合/未见 fixture 与 fallback 统计；撤销旧产品 owner 前还须确认产品路径无旧引用并同步权威文档。不得以长期 `disable-generic` 或静默双执行代替修复。
- 新功能从一个可闭合真实画面的纵向切片开始；不得把完整 compiler、RenderGraph、VM、particle platform 或发行准入作为第一张正确画面的前置工程。

### 3.2 失败按影响分级

- 路径逃逸、非法 GPU range、确定的 target hazard/ABI 不匹配、stale handle、generation/epoch/publication/lifecycle 破坏、VM/compiler timeout、OOM 或预算超限必须硬拒绝对应执行单元。
- shader/pass、optional provider、script binding/API、particle component 等视觉失败默认 fail soft：停用最小失败 effect/pass/script/component/依赖子图，保留进入它以前的 current、其他 layer/object 和安全的 compositor 输出。
- optional texture/uniform/provider 优先采用作者默认、关闭对应 combo 或保持原始输入；不得伪造资源、target、history、binding 或语义不同的 fallback。
- 未消费的未知非关键 metadata 保真并告警。局部 fallback 必须可观察、可测试、可撤销。
- 保留现有 command-buffer、target/publication、completion、rollback 和 epoch 原子安全；不得用“事务完整”要求一层所有 authored effect 在 launch 时全部获准后才允许任何一个执行。

### 3.3 一个批次交付一个可见或可执行结果

- 可见问题先记录预期、实际、复现路径和统一链的第一个失败 identity；本批说明要恢复的真实作者输入、闭合到的用户结果、局部失败边界和项目正反门。
- 批次可以跨 Resources、RenderGraph、Runtime、Rendering、Effect、粒子或动态输入目录，只要它们共同闭合同一个可回滚纵向结果。
- 普通 parser/IR/diagnostic/census 只有实际服务当前纵向切片时才进入批次；它们单独通过不能记为效果完成。
- 只有 corpus fingerprint/schema/family 解释变化，或现有快照无法回答影响面时才刷新全 corpus。普通效果修复不把 census、全台账重写或 full matrix 当作前置仪式。
- 新路径扩大 crash、整层拒绝或明显视觉回退时，先撤回产品路由，保留 fixture 和诊断，再缩小切片；不得删除反例、收窄 corpus 或把失败改名为 `unsupported` 制造通过。

### 3.4 执行顺序

1. 在当前代码和隔离真实内容上确定首断点、previous-current fallback 和最小正反门；
2. 落通用执行切片，运行 inner 门确认新代码实际加载；
3. 尽早运行一个代表性真实内容，按新的首断点迭代到实际 Program/VM/component 和可见输出；
4. 在 checkpoint 加入新组合/未见 fixture，证明没有退化为已知名称视觉特判；
5. 按能力、owner、matrix 或运行事实的真实变化同步唯一权威文档；
6. 冻结 diff，运行提交门并提交单一职责批次。

纯规则/历史整理可独立提交。目录迁移与功能行为变化默认分开提交。

## 4. 技术栈与代码职责

- 产品 UI 保持 Swift + AppKit；Scene GPU 主链保持 Swift + Metal；Python 3.12 只用于测试和开发工具。作者 shader 后端与 SceneScript VM 的推荐方案和替代条件只由[兼容运行时架构](docs/scene/runtime-architecture.md)决定。
- Swift 拥有 identity、作者顺序、IR、属性、资源/target 生命周期、host bridge、typed diagnostics 和 Metal 调度；通用 compiler 执行 shader 语言语义，真实 VM 执行 ECMAScript，component interpreter 执行粒子组合。
- 新增固定 MSL 用 `.metal` 构建期编译。Workshop 作者 shader 在 preparation/variant 阶段完成 cache、取消/预算、reflection 和 pipeline preflight；不得在 draw/pass encode 热路径首次同步编译。
- 一个文件表达一个凝聚职责；没有真实复用、独立生命周期或清晰依赖边界时不增加协议、wrapper 或目录。400 行是审查提醒，新增文件不得超过 800 行，历史超过 800 行的文件不得增长；禁止用压缩排版、删空行或切断强耦合流程过门。

Scene 分类根 `MyWallpaperX/Core/SteamWorkshopScene` 不直接放 Swift。一级职责为 `Format`、`Runtime`、`Properties`、`Resources`、`Rendering`、`RenderGraph`、`Effects`、`Text`、`Particles`；布局真值由 [`script/scene_source_layout.json`](script/scene_source_layout.json) 与自动测试维护。禁止 `Misc`、`Common`、`Helpers` 等兜底目录和预建空目录。

`AuthoredGraph` 保存/降低作者图；`ShaderContract`/`ShaderPreparation` 保存 source、metadata、variant 和 VFS；`MaterialProgram` 形成统一 Program；`EffectCompilation` 收敛为普通 material/graph 编译而非 dedicated catalog；`EffectExecution` 只保留 GraphExecutor；`GraphTargets`/`LayerDependencies` 拥有 target/resource/publication。`Runtime/ResolvedMaterialExecution` 保留 surface-scoped commit、completion、rollback、epoch 和 terminal observation。

目录迁移只移动完整类型族和路径引用，不夹带行为变化。新增二级职责需同步布局合同、standalone source lists、导航和迁移测试。

## 5. 验证与证据

统一入口：

```bash
python3.12 script/verify_scene_change.py --phase <inner|checkpoint|integration|milestone> --base HEAD --path <owned-path> --run
```

| 阶段 | 目的 | 最低要求 |
|---|---|---|
| `inner` | 快速编码循环 | 最近单元/harness；不构建、不启动 App |
| `checkpoint` | 可提交实现 | 定向测试、代码健康；Swift 产品改动再 build；通用化改动加入新组合/未见 fixture |
| `integration` | GPU、VM、资源、生命周期或可见变化 | 已批准 Fast case；尚未批准时使用契约化代表隔离内容并明确不是 suite PASS；实际执行、局部降级、compositor 输出 |
| `milestone` | 跨 family、matrix、性能或发布 | 按风险选择 fixed/full、压力、长稳、签名/发布门 |

- gate 显式报告 `planned/running/passed/failed/skipped/blocked`；缺命令、`--skip-runtime` 或缺样本只能得到 structural-only/skipped。
- Fast Scene Suite 成员与 readiness 只查 `script/scene_fast_suite.json`；`selection-required` 成员、任意 `--sample-id` 或 full matrix 子集不能报告为 Fast Suite PASS。
- 声称具体显示或动态恢复时，需要实际执行身份、GPU/VM completion、publication、terminal compositor、next-frame，以及与声明相称的截图 ROI/事件证据。架构广度迁移仍不能用任意非黑像素冒充视觉支持。
- 完成状态分三层独立报告：`slice-visible` 只证明当前纵向切片真实可见或可执行；`owner-migration` 还要求显式 route state、fallback 指标、回滚演练和旧 owner 撤权；`parity-release` 再要求对应 bounded profile 的官方黑盒容差、发布依赖、性能/长稳与签名门。前一层不得冒充后一层，发行门也不得倒灌阻塞第一张正确画面。
- fixed 与 full 不互相替代；普通定向开发默认不跑 full。发行、跨 corpus 合同和无法由低成本门覆盖的风险才进入 milestone。
- 新 gate 必须登记在 `script/scene_validation_gates.json`；迁移期 ratchet 结束后删除或收敛为稳定不变量。

## 6. 并行、提交与工作区

- 并行写入前分配互不重叠的文件或主类型；共享测试、matrix 和权威文档由一名整合者修改。静态扫描和独立测试可并行，build、App runtime、benchmark、fixed/full 必须串行。
- 主实现者维护唯一纵向结果、首断点、fallback、整合和最终运行事实；子代理适合有界研究、独立文件和冻结 diff 终审。
- 提交只包含一个职责批次，信息写明问题、根因、实际结果和验证；禁止宽泛暂存。
- `.codex` 是可重建工作区，不是源码或知识库。正式工具进入 `script/`，测试进入 `script/tests/`，一次性文件进入 `/private/tmp`。生成 build/runtime 产物后按现役规则审计，只清理精确归属且可重建的候选。
- Scene benchmark 默认只保留 `report.json`、日志、必要截图和 identity/hash 摘要；staged App、隔离样本副本、临时 `HOME` 与 runtime cache 无论正反门结果都应在报告形成后清理，中断和异常也必须收尾。只有为了定位当前唯一失败现场时才显式使用 `--keep-runtime`，并记录保留理由、体量和清理触发条件；批次闭合后不得继续保留已被最终证据替代的 debug runtime、重试副本或独立 DerivedData。`docs/scene/evidence/` 是仓库忽略的本机证据缓存：最终报告、结构化runtime evidence、必要日志与正反截图可以先通过 `script/promote_scene_evidence.py` 做有界提纯，但不得暂存或提交；权威文档只保存可复核摘要、输入/App/报告/manifest identity 与 SHA-256，不链接或依赖该本机目录。不得缓存 staged App、runtime/sample副本、Workshop包或普通重试。

## 7. 汇报

过程更新只说明当前首断点、正在闭合的纵向结果、失败半径和下一门。最终只报告：实际改动、影响范围、运行过的验证及结果、是否提交、仍未消除或未验证的边界。任何结论不得超出证据等级。
