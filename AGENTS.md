# MyWallpaperX 开发规则

本文件只保存会改变实现、验证、提交或工作区安全的长期约束。能力数字、样本结论、运行报告、批次状态和历史迁移记录不在这里重复。

## 1. 工作与安全边界

- 先区分讨论、只读审查、诊断和实现。只读任务不得修改、构建、生成缓存、暂存或提交；实现任务默认做到可验证结果。
- 开工先读 `git status`，保留已有改动并确认本批文件所有权。禁止 `git reset --hard`、`git checkout --`、`git clean`、`git add -A` 和任何会覆盖他人工作的宽泛操作。
- 真实 Scene 样本根 `~/Movies/MyWallpaperX/创意工坊/Scene` 只读。benchmark、属性注入和缓存操作只能使用隔离副本、隔离 Workshop root 与临时 `HOME`。
- 只改当前目标的完整职责边界。可为了闭合目标移动或重组整个类型族，但不得顺手清理无关代码；计划外问题记录后另行排程。
- 删除历史材料、唯一失败现场或归属不明的生成物前必须先列出精确清单并取得确认。禁止对仓库根、`.codex` 根或真实样本根做递归清理。

## 2. 事实入口与证据边界

按问题读取最小入口，不全量扫描文档库：

1. 全项目导航与冲突顺序：[`docs/README.md`](docs/README.md)；
2. 长期语言、进程、依赖与所有权：[`docs/architecture/technology-stack-boundaries.md`](docs/architecture/technology-stack-boundaries.md)；
3. Scene 当前迁移顺序与停止项：[`scene-generic-execution-refactor-plan-2026-08-15.md`](docs/scene/scene-generic-execution-refactor-plan-2026-08-15.md)；
4. Scene 合同导航：[`docs/scene/semantics/README.md`](docs/scene/semantics/README.md)；
5. 当前能力与运行事实：[`coverage-ledger.md`](docs/scene/semantics/coverage-ledger.md) 和 [`runtime-evidence-index.md`](docs/scene/semantics/runtime-evidence-index.md)；
6. authored corpus 影响面：[`scene-corpus-capability-inventory.md`](docs/scene/semantics/scene-corpus-capability-inventory.md)。它不证明运行支持。

带日期的 plan、review、roadmap 和旧报告默认是历史证据；只有在 [`docs/document-role-index.json`](docs/document-role-index.json) 中登记为 `active-plan` 的文件才决定当前执行顺序。冲突时依次采用：当前代码与可复现运行证据、本文、长期架构合同、专题现役合同、现役计划、历史材料。

官方公开合同优先。只有新增或改变作者语义、owner、frame order、生命周期或安全边界时才重新核对官方/stock；现有固定证据足够覆盖本批时直接复用。MirageWallpaper 仅作 clean-room 结构交叉检查，不作为每批必读项，也不得复制其源码、shader、资产、payload、常量组合、算法表达或测试数据。

不得把 `recognized`、`wired`、静态 census、compile success、路由计数、非黑截图或单个样本通过表述为完整兼容或 Wallpaper Engine 视觉等价。

## 3. Scene 通用执行规则

### 3.1 默认扩大通用运行时，不扩大专用准入表

- 新的作者内容应通过 loss-preserving IR、通用 shader/material compiler、通用 RenderGraph、真实 ECMAScript VM、粒子组件解释器和统一 GraphExecutor 获得执行能力。
- 除非遇到现有 IR 无法表达、且会被多个未见内容复用的真实新 primitive，不新增 effect-specific planner/renderer、固定脚本 compiler、按名称的 capability catalog 或专用产品路径。例外必须在现役计划中写明复用面和退役条件。
- sample/layer/path/asset ID/hash 可以作为 typed identity、缓存、资源/publication 键、provenance 和诊断字段，但不得选择 capability、算法或产品 dispatch。
- 现有 bounded frontend、exact planner 和专用 renderer 是迁移 oracle/fallback，不是未来架构模板。新增能力优先减少这些产品 owner；不得因为旧路径已有严格测试就继续无限扩张它。
- 任务开始前回答：新增什么通用 primitive、未见内容如何受益、局部失败如何隔离、哪个旧 owner 会被撤销。前两项没有具体答案时停止实现并改写任务。

### 3.2 失败分级

- 路径逃逸、越界 GPU range、资源/时间/内存预算、target hazard、stale handle、生命周期破坏、VM/compiler timeout 或 OOM 等安全与状态完整性问题必须硬拒绝相关执行单元。
- shader/pipeline、optional provider、单个 effect/pass/script binding/particle system 等局部视觉失败默认 fail soft：停用失败单元，保留可安全执行的 base layer 和其他对象，并发布 typed status 与稳定诊断。
- optional texture/uniform/provider 缺失时使用作者默认、关闭相应 combo 或保持原始输入；不得伪造资源、target、history 或 binding。
- 未被执行路径消费的未知非关键 metadata 应保真并告警，不因“尚未逐项证明”整层拒绝。
- 禁止静默切换到语义不同的算法。fallback 必须可观测、可测试、可撤销。

### 3.3 一个批次交付一个通用结果

- 批次可以跨 `Resources`、`RenderGraph`、`Runtime`、`Rendering`、Effect、粒子或动态输入目录，但必须围绕一个可独立回滚的通用结果；不得把 shader、VM、粒子和 3D 多条迁移同时堆在未验证工作区。
- 可见回归先记录预期、实际、复现路径和首个失败 identity，用它定位公共 primitive；修复优先级由现役重构计划、影响面和回退风险共同决定，不把某个样本或专项表的下一门直接变成产品架构。
- 只有 corpus fingerprint、census schema、family 解释发生变化，或现有快照无法回答影响面时才刷新全 corpus。微小实现不以刷新 census、ledger 或所有专项表为前置仪式。
- 通用路径扩大 crash、整场拒绝或明显视觉回退时，先撤回该批产品路由，保留诊断和 fixture，再缩小 primitive 重做。不得通过收窄 corpus、删除反例或把失败重标为 `unsupported` 制造通过。

### 3.4 执行顺序

1. 明确通用 primitive、失败分级、旧 owner/fallback 与最小正反门；
2. 落公共实现，运行 inner 门确认新代码实际被加载；
3. 用未见内容 fixture 或新组合证明不是已知名称 dispatch；
4. 涉及 GPU、生命周期或可见输出时运行代表性 integration，按新失败点迭代；
5. 只在能力等级、产品 owner、matrix 合同或现役运行事实变化时同步对应权威文档；
6. 冻结 diff，运行提交门，独立提交可回滚批次。

纯规则/历史整理可独立提交。目录迁移与功能行为变化默认分开提交。

## 4. 技术栈与代码职责

- 产品 UI 保持 Swift + AppKit；Scene 主链保持 Swift + Metal；Python 只用于测试和开发工具。通用 ECMAScript VM 和 shader compiler 是已确定的迁移方向，可通过 C/C++ 薄边界或受控 worker 接入，不要求先穷举所有作者语义才开始受控产品验证。
- Swift 拥有 Scene identity、作者顺序、资源/target 生命周期、host bridge、typed diagnostics 和 Metal 调度；作者 shader 语言语义由通用 compiler 执行，ECMAScript 语言语义由 VM 执行，Swift 不重复实现完整语言。
- 新增固定 MSL 用 `.metal` 构建期编译；Workshop 作者 shader 才允许运行期编译，并在 preparation/variant 阶段完成 cache、取消、预算、reflection 和 pipeline preflight。
- 一个文件表达一个凝聚职责；一个类型族放在同一职责目录。没有真实复用、独立生命周期或清晰依赖边界时不增加抽象、协议、wrapper 或目录。
- 400 物理行是审查提醒，不是机械切割线。401–800 行的凝聚文件可以存在，但需保持单一职责；新增文件不得超过 800 行。历史超过 800 行的文件不得增长，触达时优先按真实职责缩小。禁止压缩排版、删合理空行、批量放宽 `private` 或切断强耦合流程来过门。

Scene 分类根 `MyWallpaperX/Core/SteamWorkshopScene` 不直接放 Swift。一级职责为 `Format`、`Runtime`、`Properties`、`Resources`、`Rendering`、`RenderGraph`、`Effects`、`Text`、`Particles`；布局真值由 [`script/scene_source_layout.json`](script/scene_source_layout.json) 与自动测试维护。禁止 `Misc`、`Common`、`Helpers` 等兜底目录，也不预建空目录。

RenderGraph 的目标职责是：`AuthoredGraph` 保留 authored IR 与结构规划；`ShaderContract`/`ShaderPreparation` 保留 loss-preserving source、metadata、variant 和 VFS contract；`MaterialProgram` 把 reflection、binding、state 和 texture selection 收敛成统一 Program；`EffectCompilation` 收敛为通用 graph/program 编译，不继续扩张 dedicated candidate/admission；`EffectExecution` 只保留统一 GraphExecutor 的 preparation/encoding/execution；`GraphTargets` 和 `LayerDependencies` 负责 target/resource/publication 生命周期。现有 `ShaderFrontend` 与 effect-specific planner 是迁移期 oracle，新增代码不得把其专用准入模式复制到新的 family。

`Runtime/ResolvedMaterialExecution` 继续负责 surface-scoped 原子提交、completion、rollback、epoch invalidation 和 terminal observation；scene-lifetime catalog、通用 graph telemetry、GPU executor 与 Rendering consumer 不并入。

目录迁移批次只移动完整类型族并修正路径引用，不夹带功能行为变化。首次建立新的二级职责需同步布局合同、受影响 standalone source lists、导航文档和迁移测试。

## 5. 验证与可见证据

统一入口：

```bash
python3.12 script/verify_scene_change.py --phase <inner|checkpoint|integration|milestone> --base HEAD --path <owned-path> --run
```

| 阶段 | 用途 | 最低要求 |
| --- | --- | --- |
| `inner` | 编码循环 | 受影响单元/Swift harness；不构建、不启动 App |
| `checkpoint` | 结构或非可见批次准备提交 | 定向测试、代码健康；Swift 产品改动再 build verify |
| `integration` | compiler、VM、RenderGraph、资源、运行时或可见改动 | Scene 回归、build verify、代表性隔离样本与失败隔离 |
| `milestone` | 跨 family、matrix 合同、发布或里程碑 | 按明确风险选择 fixed/full，不惯性全跑 |

- gate 必须显式报告 `planned/running/passed/failed/skipped/blocked`。`--skip-runtime`、无命令或缺私有样本只能得到 structural-only/skipped，不能返回 integration 或 visible closure PASS。
- compiler/VM/executor 的通用化批次必须至少包含一个未见内容 fixture 或新组合反例，并记录 compile/plan/runtime diagnostics；不得只用已知名称正例。
- 涉及 GPU 或可见输出的架构批次需要 GPU completed、publication、terminal compositor consumed 和 next-frame 证据，并验证失败只影响预期单元。只有声称具体 fidelity/回归恢复时才强制预定义 ROI/事件断言；广度迁移不能用任意非黑像素冒充视觉支持。
- fixed matrix 是固定回归集；full matrix 只有与当前 corpus fingerprint 一致时才是完整快照。两者不可互相替代，普通定向改动默认不跑 full。
- 新 gate 必须在 `script/scene_validation_gates.json` 记录风险、触发、成本、串行要求和退役条件。迁移期 ratchet 在迁移结束后删除或收敛为稳定不变量。
- Swift/Metal 模块缓存受权限影响时，把 `CLANG_MODULE_CACHE_PATH` 与 `SWIFT_MODULECACHE_PATH` 指向 `/private/tmp` 专用目录后再区分环境与产品失败。

## 6. 并行、提交与工作区

- 并行写入前分配互不重叠的文件或主类型所有权；共享测试、matrix 和权威文档由一名整合者修改。静态扫描和独立测试可并行，build、App runtime、benchmark、fixed/full 必须串行。
- 子代理适合有界研究、独立文件实现和冻结快照终审；主代理维护唯一批次目标、产品 owner 迁移、整合和最终运行事实。
- 提交只包含一个职责批次，信息写明问题、根因和实际验证。禁止宽泛暂存。
- `.codex` 是可重建工作区，不是源码或长期知识库。正式工具进入 `script/`，测试进入 `script/tests/`，一次性文件进入 `/private/tmp`。生成过 build/runtime 产物的批次收尾运行 `python3.12 script/audit_codex_artifacts.py --fail-on-candidates`，只清理精确归属且可重建的候选。

## 7. 汇报

过程更新只说明当前通用 primitive、正在迁移的 owner、失败分级和下一门。最终只报告：实际改动、影响范围、运行过的验证及结果、是否提交、仍未消除或未验证的边界。任何结论不得超出证据等级。
