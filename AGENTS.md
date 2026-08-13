# MyWallpaperX 开发规则

本文件只保存会改变实现、验证、提交或工作区安全的长期约束。能力数字、样本结论、运行报告、批次计划和历史迁移状态不在这里重复。

## 1. 工作与安全边界

- 先区分讨论、只读审查、诊断和实现。只读任务不得修改、构建、生成缓存、暂存或提交；实现任务默认做到可验证结果。
- 开工先读 `git status`，保留已有改动并确认本批文件所有权。禁止 `git reset --hard`、`git checkout --`、`git clean`、`git add -A` 和任何会覆盖他人工作的宽泛操作。
- 真实 Scene 样本根 `~/Movies/MyWallpaperX/创意工坊/Scene` 只读。benchmark、属性注入和缓存操作只能使用隔离副本、隔离 Workshop root 与临时 `HOME`。
- 只改当前目标的完整职责边界。可为了闭合该目标移动或重组整个类型族，但不得顺手清理无关代码；计划外问题记录后另行排程。
- 删除历史材料、唯一失败现场或归属不明的生成物前必须先列出精确清单并取得确认。禁止对仓库根、`.codex` 根或真实样本根做递归清理。

## 2. 事实入口与证据边界

按问题读取最小入口，不全量扫描文档库：

1. 全项目导航与冲突顺序：[`docs/README.md`](docs/README.md)；
2. 长期语言、进程、依赖与所有权：[`docs/architecture/technology-stack-boundaries.md`](docs/architecture/technology-stack-boundaries.md)；
3. Scene 合同导航：[`docs/scene/semantics/README.md`](docs/scene/semantics/README.md)；
4. 当前能力与运行事实：[`coverage-ledger.md`](docs/scene/semantics/coverage-ledger.md) 和 [`runtime-evidence-index.md`](docs/scene/semantics/runtime-evidence-index.md)；
5. authored corpus 影响面：[`scene-corpus-capability-inventory.md`](docs/scene/semantics/scene-corpus-capability-inventory.md)。它不证明运行支持。

带日期的 plan、review、roadmap 和旧报告默认是历史证据，只有现役入口明确链接时才参与当前工作。冲突时依次采用：当前代码与可复现运行证据、本文、长期架构合同、专题现役合同、历史材料。

官方公开合同优先。只有新增或改变作者语义、owner、frame order、生命周期或安全边界时，才需要重新核对官方/stock；现有固定证据足够覆盖本批时直接复用。MirageWallpaper 仅在官方材料不足或需要交叉核对完整 producer-to-consumer 链时读取固定 revision，且只借鉴职责、状态传播和顺序；不得复制其 GPL 源码、shader、资产、payload、常量组合、算法表达或测试数据。

不得把 `recognized`、`wired`、静态 census、strict profile、路由计数、非黑截图或单个样本通过表述为完整兼容或 Wallpaper Engine 视觉等价。

## 3. Scene 修复流程

### 3.1 修复前只确定首断边

用户可见缺图、错误合成、黑窗、动态失效或交互失效时，先记录：

- 预期、实际和可复现路径；
- render chain 的第一个失败 identity（sample/layer/effect/pass/slot/target）；
- 公共根因假设、预计影响 family 和尚未证明的后继；
- 本批 tentative correctness atom、项目自有正反门和真实样本 sentinel/ROI。

首断边之前不要求凭空证明尚未执行的所有下游阶段。静态推断必须标明，修复后用新运行结果继续追链。

### 3.2 一个批次闭合一个用户结果

- correctness atom 是恢复同一公共用户结果所需的最小完整链，可以跨 `Resources`、`RenderGraph`、`Rendering`、Effect、粒子或动态输入目录；不得按源码目录或能力等级把 selection、Program、publication 和 compositor 人为拆成多个“已修复”批次。
- sample/layer/path/hash 可作为 typed identity、资源/缓存/publication 键和诊断字段，但不得以特定字面量选择 capability、算法或产品 dispatch。
- 未证明的 producer、texture、颜色、alpha、target 或生命周期继续 fail closed。提前拒绝坏层并保住其余画面是故障隔离，不是该层已经支持。
- 只有 corpus fingerprint、census schema、family 解释发生变化，或现有快照无法回答影响面时才刷新全 corpus；普通 family 修复不把 census 当成前置仪式。

### 3.3 执行顺序

1. 主实现者落公共代码和 inner 正反门；
2. 运行最小定向测试，确认改动实际被加载；
3. 对可见或运行时改动运行定向 integration，按新首断边迭代到链稳定；
4. 同步本 atom 必需的测试、matrix、ledger 和现役文档；
5. 冻结 diff 后只做一次稳定快照终审；
6. 运行提交门并提交单一职责批次。

不得在每条移动快照审计意见后反复重跑完整验证，也不得用连续子代理审计替代主实现。纯规则/历史整理可独立提交；与 correctness atom 同步的测试、matrix 和能力记录必须随该 atom 一起交付。

## 4. 技术栈与代码职责

- 产品 UI 保持 Swift + AppKit；Scene 主链保持 Swift + Metal。Python 只用于测试和开发工具。候选 VM/compiler/XPC 必须按长期技术边界完成许可证、签名、预算、失败隔离与发布准入后才能取得产品执行权。
- 新增固定 MSL 用 `.metal` 构建期编译；Workshop 作者 shader 才允许运行期编译，并在 preparation/variant 阶段完成 cache、取消、预算、reflection 和 pipeline preflight。
- 一个文件表达一个凝聚职责；一个类型族放在同一职责目录。没有真实复用、独立生命周期或清晰依赖边界时不增加抽象、协议、wrapper 或目录。
- 400 物理行是审查提醒，不是机械切割线。401–800 行的凝聚文件可以存在，但需要保持单一职责；新增文件不得超过 800 行。历史超过 800 行的文件不得增长，触达时优先按真实职责缩小。禁止压缩排版、删合理空行、批量放宽 `private` 或切断强耦合流程来过门。

Scene 分类根 `MyWallpaperX/Core/SteamWorkshopScene` 不直接放 Swift。一级职责为 `Format`、`Runtime`、`Properties`、`Resources`、`Rendering`、`RenderGraph`、`Effects`、`Text`、`Particles`。密集类型族应按完整生命周期迁移到语义明确的二级目录；禁止 `Misc`、`Common`、`Helpers` 等兜底目录，也不预建空目录。布局真值由 [`script/scene_source_layout.json`](script/scene_source_layout.json) 与自动测试维护。

现有 RenderGraph 二级职责：`EffectExecution` 负责统一 GraphExecutor 的 stage preparation/encoding/execution；`GraphTargets` 负责 authored graph target 的计划、状态、分配、驻留、资源命令与 publication；`ShaderFrontend` 负责有界作者 shader 的词法、语法、语义/颜色证明、翻译与 Metal source emission；`ShaderPreparation` 负责 directive/macro 预处理、variant 环境与解析、prepared source 产生及畸形 metadata 准入。`SceneShaderContract`、`SceneShaderSourceGraph`、FrameInputs、`ShaderFrontend` 和 resolved Program 均属于其他生命周期，不并入 `ShaderPreparation`。named layer target 不属于 authored effect FBO/history，不因名称相似并入 `GraphTargets`。

目录迁移批次默认只移动完整类型族并修正路径引用，不夹带功能行为变化；保持 Swift 内容和 `project.pbxproj` 无无关改动。首次建立新的二级职责需同步布局合同、受影响 standalone source lists、导航文档和迁移测试。

## 5. 验证与可见证据

统一入口：

```bash
python3.12 script/verify_scene_change.py --phase <inner|checkpoint|integration|milestone> --base HEAD --path <owned-path> --run
```

| 阶段 | 用途 | 最低要求 |
| --- | --- | --- |
| `inner` | 编码循环 | 受影响单元/Swift harness；不构建、不启动 App |
| `checkpoint` | 结构或非可见批次准备提交 | 定向测试、代码健康；Swift 产品改动再 build verify |
| `integration` | RenderGraph、资源、运行时或可见改动 | Scene 回归、build verify、定向隔离样本；可见声明必须闭合真实链 |
| `milestone` | 样本集合、matrix 合同、发布或里程碑 | 按明确风险选择 fixed/full，不能惯性全跑 |

- gate 必须显式报告 `planned/running/passed/failed/skipped/blocked`。`--skip-runtime`、无命令或缺私有样本只能得到 structural-only/skipped，不能返回 integration 或 visible closure PASS。
- integration 不得因选择 Scene 全量而丢弃显式映射的非 `test_scene_*` 模块；多个 benchmark 必须使用独立输出目录。未显式选择 fixed/full 时不得暗中声称 matrix 覆盖。
- 声称恢复显示、纹理、合成、动态或交互时，必须同时有项目自有 synthetic 正反门和同一隔离真实样本证据：GPU completed、精确 publication identity、terminal compositor consumed、next-frame 成功，以及预先定义 ROI/事件断言。进程存活、exit 0、任意非黑像素、全屏 motion 或 route/claim 数不能替代它。
- fixed matrix 是固定回归集；full matrix 只有与当前 corpus fingerprint 一致时才是完整快照。两者不可互相替代，普通解析/effect/资源改动默认不跑 full。
- 新 gate 必须在 `script/scene_validation_gates.json` 记录风险、触发、成本、串行要求和退役条件。迁移期计数 ratchet 在迁移结束后删除或收敛为稳定不变量。
- Swift/Metal 模块缓存受权限影响时，把 `CLANG_MODULE_CACHE_PATH` 与 `SWIFT_MODULECACHE_PATH` 指向 `/private/tmp` 专用目录后再区分环境与产品失败。

## 6. 并行、提交与工作区

- 并行写入前分配互不重叠的文件或主类型所有权；共享测试、matrix 和权威文档由一名整合者修改。静态扫描和独立测试可并行，build、App runtime、benchmark、fixed/full 必须串行。
- 子代理适合有界研究、独立文件实现和冻结快照终审；主代理维护唯一首断边、correctness atom、整合和最终运行事实。
- 提交只包含一个职责批次，信息写明问题、根因和实际验证。目录迁移与功能修复分开提交；禁止宽泛暂存。
- `.codex` 是可重建工作区，不是源码或长期知识库。正式工具进入 `script/`，测试进入 `script/tests/`，一次性文件进入 `/private/tmp`。生成过 build/runtime 产物的批次收尾运行 `python3.12 script/audit_codex_artifacts.py --fail-on-candidates`，只清理精确归属且可重建的候选。

## 7. 汇报

过程更新只说明当前首断边、正在修改的职责和下一门。最终只报告：实际改动、影响范围、运行过的验证及结果、是否提交、仍未消除或未验证的边界。任何结论不得超出证据等级。
