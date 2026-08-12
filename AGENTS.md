# MyWallpaperX 开发规则

本文件只保留会影响实现、验证、提交或工作区安全的现役规则。能力等级、样本计数、报告路径和历史结论不在这里重复，以现役语义文档和运行证据为准。

## 1. 工作边界

- 先确认用户要的是讨论、只读审查、诊断还是实现。只读任务不得修改、构建、生成缓存、暂存或提交。
- 保留工作区已有改动；先读 `git status`、相关规则、现役文档和受影响代码。不得用 `git reset --hard`、`git checkout --`、`git clean` 或宽泛的暂存命令覆盖他人工作。
- 只修改与当前目标直接相关的文件。发现计划外问题时，记录影响并单独决定是否纳入；不得顺手重构或清理。
- 信息不足时先用本机代码、测试、样本和可验证资料补齐。对未验证结论明确标为推断。

## 2. Scene 事实与证据

真实创意工坊样本根 `~/Movies/MyWallpaperX/创意工坊/` 只读。任何 benchmark、属性注入、缓存操作或样本修改都必须在隔离副本中进行，并同时使用隔离的 Workshop root 与临时 `HOME`；不得直接改动、删除或清理真实样本。

Scene 事实按类型使用唯一入口，历史计划或低层材料不得覆盖现役事实：

1. [总覆盖台账](docs/scene/semantics/coverage-ledger.md)：系统摘要与专项表入口。
2. Effect、粒子、SceneScript、Graph/Shader、运行输入/属性和高级对象专项表：逐项等级、代码、测试与缺口。
3. [运行证据索引](docs/scene/semantics/runtime-evidence-index.md)：当前基线、样本、构建、签名和运行报告。
4. [能力依赖图](docs/scene/semantics/capability-dependency-map.md)：公共前置能力与开发顺序。

带日期的 plan、roadmap 和 review 默认是批次快照；只有 `docs/README.md` 或专题入口明确列为“现役迁移目标/现役执行计划”的文件才可指导当前顺序，但仍不是能力或运行基线的权威入口。

开始 Scene 任务时，先从 `docs/scene/semantics/README.md` 按问题类型进入专项表，再核对总覆盖台账与运行证据索引；排开发顺序时补读能力依赖图，涉及官方客户端或公开资料时补读 `source-index.md`。不得全量扫描文档库后凭文件名选任务，也不得从静态取证直接推导“已支持”。

不得将 `recognized`、`wired`、`executed-degraded`、固定 strict profile、固定样本通过或静态参考材料表述为完整兼容或 Wallpaper Engine 视觉等价。官方/参考材料只可作为 clean-room 证据；不得复制其 payload、shader、纹理、JSON、二进制或算法表达，新增断言使用项目自有 fixture。

### 2.1 用户可见 Scene 闭环与批次原子性

- 真实样本出现缺图、合成纹理丢失、黑窗、交互无效或明显错误显示时，当前优先级由该样本实际 render chain 的**第一个断裂边**决定。必须沿 `asset/texture selection -> admission/owner -> Program/variant -> GPU encode -> publication -> compositor -> next frame -> 目标 ROI` 记录精确 layer/effect/pass/slot/target identity；文档分类、源码目录、能力等级和 occurrence 数只帮助界定语义与影响面，不能代替排程。
- 一个 correctness atom 是恢复同一用户可见结果所需的最小公共闭环。相互依赖的 selection、admission、Program、render target、publication 与 composition 即使跨 `Resources`、`RenderGraph`、`Rendering` 或多个 D/L 节点，也必须同批实现和验收；不得把其中一段标成“显示已修复”后把真正 consumer 留到后续。基础工作只有在没有已知可见断链，或明确标为前置且不宣称用户收益时，才可独立提交。
- 样本 ID、layer ID、资源路径和 hash 可以作为通用 typed identity、资源解析/缓存键、publication/ownership 键和诊断字段，但不得以某个特定样本、layer、路径或 hash 字面量决定 capability eligibility、算法选择或样本专用 dispatch。公共实现仍须按作者结构、typed identity、官方合同和 clean-room 证据准入，未知形态继续失败关闭。
- 实现路径有疑问时，依次查现役语义/证据库、官方公开文档与 stock corpus、必要的本机官方客户端 clean-room Ghidra 取证，最后用 MirageWallpaper 交叉验证；参考项目不得覆盖官方证据。官方已证的解析顺序、资源身份、生命周期和合成路径是实现目标，证据仍不足时保持 unsupported，不以近似结果补空白。
- 现有代码若采用了与已证官方路径冲突的 ownership、顺序或数据模型，应在该职责边界内替换错误模型和旧入口，不得继续叠加 sample workaround、兼容 flag 或下游补丁来维持错误架构。
- fail-closed 必须保留，但报告要区分“提前拒绝坏层并保住其余已证画面”和“已经实现被拒绝层”。前者是故障隔离，不是该 effect、纹理或合成语义已支持。

## 3. 技术栈与架构边界

[技术栈与架构路线边界](docs/architecture/technology-stack-boundaries.md) 是语言职责、跨语言/跨进程所有权、性能合同和候选依赖准入的唯一长期入口。最终产品主体为 Swift + AppKit，现有 SwiftUI 只作为 [0 SwiftUI 迁移计划](docs/architecture/appkit-migration-plan-2026-05-17.md)中的受控残留，不新增 SwiftUI 产品面或扩大 hosting bridge。Scene 主链保持 Swift + Metal：Swift 拥有产品语义、typed IR、资源/属性/生命周期和 GPU 调度，Metal/MSL 拥有 GPU 执行，Python 只用于测试与开发工具。

- C/C++ 只可进入有明确生态优势的 VM/compiler ABI 或经 profiling 证明的局部 kernel，不得接管 Scene 业务语义、样本路由或第二套 renderer；长期边界使用窄 typed C ABI 或版本化进程协议。
- QuickJS-NG、JavaScriptCore、Slang、DXC、Metal Shader Converter、glslang、SPIRV-Cross 与 XPC 均是带准入门的候选，不是当前能力。新增依赖先做无产品执行权的项目自有 fixture / shadow 评估，完成预算、失败关闭、许可证、双架构、签名和发布门后，才能按公共 capability family 迁移。
- 进程边界只用于故障、权限或资源隔离；compiler worker 可评估 XPC，需要拥有桌面窗口的 renderer 保持在 App 或可呈现窗口的 helper application。不得把 draw/pass/uniform/JS property access 等每帧细粒度操作改成 XPC 往返。
- 新增项目自有固定 MSL 使用 `.metal` 构建期编译；Workshop 作者 shader 才允许运行期编译，并须在 preparation/variant 阶段完成 cache、取消、预算、reflection 和 pipeline preflight，不在 encode 热路径首次同步编译。现有 Swift 字符串 shader 属于受控迁移债务，不在无性能证据时机械重写。
- 性能结论必须区分首帧、稳态 frame time、hitch、内存、能耗和恢复；记录硬件、OS、显示器、构建/App 身份与样本。平均 FPS、非黑、进程存活或样本门通过不能单独证明性能闭环。
- 仓库 Python 工具链固定为 3.12.x，本地与 CI 必须显式选择兼容解释器。当前 Swift 5 language mode 不作为性能缺陷；Swift 6 strict concurrency 只在 R4/R5 后按模块迁移。
- R4/R5 已于 2026-08-12 完成公共能力接管、旧 owner 撤权和残留删除。后续 VM、shader compiler 或 service 原型仍不得据此升级覆盖台账或取得隐式 execution owner；任何新增产品执行面必须重新走公共 capability、失败关闭和运行证据门。

## 4. 实现流程

### 修复前

对每个报错样本或用户可见问题，先确认：

- 预期行为、实际行为与可复现路径；
- 根因归类：样本逻辑、框架实现、依赖、解析、缓存/构建产物或环境；
- 第一个断裂边及其精确 identity，而不是只记录最终聚合错误；
- 是否属于公共逻辑、影响哪些样本，以及恢复该结果所需的完整 correctness atom；
- 受影响文件、样本、项目自有正反门和目标 ROI；若目标是官方等价，还要写明同相位官方 golden 或其他足以证明等价的证据。

开始改动前给出简短计划：问题与根因假设、第一个断裂边、correctness atom、拟改位置、影响范围、验证样本及每步验收标准。优先修复共享逻辑，不得用样本 ID 分支、跳过校验、隐藏错误或放宽 fail-closed 行为制造通过。

### 实现与提交

- 单次只处理一个 correctness atom。编码循环先跑 inner 门；生产代码稳定后只做一次终审，再运行 integration/隔离样本并同步文档，不得在每条移动快照审计意见后反复跑完整验证。
- 主代理必须实际落下本批公共生产代码、测试和整合；子代理只承担文件所有权明确的独立实现，或有界只读研究、稳定快照终审。不得用连续子代理审计代替主实现；连续两个审计周期仍未让目标可见链前进时，停止追加补丁，回到隔离样本重新确定第一个断裂边和批次边界。
- 先确认改动被实际加载，再解释运行结果：检查构建产物、缓存、入口、配置和资源路径；必要时重建隔离运行环境。
- 验证通过后才提交该问题。提交信息须说明问题、根因和验证；不混入无关改动。
- 修改文档、规则或门禁时也保持独立提交边界，并验证链接、脚本或门禁合同，没有功能改动时不虚构运行验证。

## 5. 验证选择

按影响面选择最小充分集合，不默认全量运行。优先使用统一入口先解释、再执行；在脏工作区中用可重复的 `--path` 只声明本批拥有的文件：

```bash
python3 script/verify_scene_change.py --phase checkpoint --base HEAD --path <path> --run
```

验证分为四级，同一份未变化源码已由较高一级覆盖的检查不得手工重复：

| 阶段 | 使用时机 | 至少验证 |
| --- | --- |
| `inner` | 编码循环 | 受影响的单元/Swift harness；不构建、不启动 App、不跑矩阵 |
| `checkpoint` | 一个独立问题准备提交 | 受影响测试；Swift 产品代码再跑代码健康与 `script/build_and_run.sh verify` |
| `integration` | 公共 RenderGraph、资源、属性或运行时批次准备交付 | Scene 全量测试、代码健康、构建启动与受影响定向隔离样本；可见修复还须验证完整 render chain 与 ROI |
| `milestone` | 样本/矩阵变化、发布或里程碑 | 先按风险选择 fixed；仅在便宜证据仍不能排除风险时运行 full |

目录迁移继续按布局/链接门、受路径影响测试、代码健康和 build verify 验证；首次改变布局合同再增加 Scene 全量测试。CI 没有私有 Workshop corpus 时可显式记录原因跳过运行样本，但不得把该结果写成运行证据。

`script/scene_wallpaper_sample_matrix.json` 是固定回归门，`script/scene_wallpaper_full_sample_matrix.json` 是当前真实 Scene 目录的完整快照门。两者有重叠但不可互相替代，报告必须分别说明；部分样本或矩阵缺失不得写成 PASS。

固定门不是每次公共改动的默认步骤。只有改动同时影响多个固定样本可能共用的行为，且定向样本与模块测试不能充分覆盖该风险时才运行；运行前记录受影响的共享合同、所选固定样本和定向验证不足的原因。

完整快照门是昂贵的里程碑核实，不得作为日常回归的惯性动作。除样本集合或完整矩阵合同变动、发布/里程碑收口外，只有预期影响跨样本且无法由定向样本、模块测试和固定门合理排除时才可运行；执行前必须说明该全量运行要核实的具体假设与替代验证为何不足。普通解析、effect、资源或公共运行时改动默认不跑完整快照。

Swift/Metal 测试若受模块缓存权限阻塞，先将 `CLANG_MODULE_CACHE_PATH` 与 `SWIFT_MODULECACHE_PATH` 指向 `/private/tmp` 下的专用目录，再区分环境失败与产品回归。

每个新增 gate 必须在 `script/scene_validation_gates.json` 声明所保护风险、触发条件、成本、串行要求和退役条件。迁移期 occurrence/count ratchet 在迁移完成后必须删除或收敛为稳定架构不变量，不得永久保留阶段性快照数字。

声称“恢复显示、纹理或合成”时，checkpoint/integration 必须同时有项目自有 synthetic 正反门和同一隔离真实样本证据。报告至少证明目标 layer/stage 的 GPU completed、精确 publication identity、terminal compositor consumed、next-frame 再成功，并在预先指定的 ROI 中出现可读的目标内容；全屏 non-black、进程存活、exit 0、loaded/route/claim 数或矩阵计数都不能替代该证据。声称 Wallpaper Engine 视觉等价还必须另有同相位官方 golden 和明确像素/时序容差。

## 6. Swift 代码健康

- 新增或未列入 `script/code_health_baseline.json` 的 Swift 文件不得超过 400 个物理行。不得压缩语句、删除合理空行或降低可读性规避限制。
- 历史超限文件只能保持或缩小；触达时先判断能否按真实职责拆出独立声明或 extension。只有有复用、独立生命周期或可明显降低复杂度时才新增类型、协议、包装层或文件。
- 拆分须保持行为、命名和访问边界。不得为跨文件访问批量放宽 `private`，也不得为满足行数机械切开强耦合流程。
- 每份未变化的 Swift diff 在 checkpoint 前至少通过一次 `python3 script/check_code_health.py --check --base-ref HEAD`；`script/build_and_run.sh` 内的成功结果已满足同一源码版本，不再重复。文件缩短时先运行 `python3 script/check_code_health.py --ratchet-baseline`，再执行检查。
- 未经用户明确批准，不得新增历史例外、提高额度、移除源码根目录或提高 400 行阈值。新增 Swift 源码根目录、Tests 或 helper target 时必须纳入扫描；远端比较使用 `--base-ref <base-ref>`。

## 7. Scene 源码布局

`MyWallpaperX/Core/SteamWorkshopScene` 是分类根目录，不直接放置 Swift 文件。`script/scene_source_layout.json` 是机器可读布局合同，`script/tests/test_scene_semantics_coverage.py` 强制执行。源码只可位于以下九个一级目录：

| 目录 | 职责 |
| --- | --- |
| `Format` | Project、Document、PKG/TEX、JSON 与 interpretation |
| `Runtime` | Host、frame context、runtime model、descriptor 与 diagnostics |
| `Properties` | 用户属性、binding program、dynamic snapshot 与 live update |
| `Resources` | asset/resource index、texture loader、path resolver 与 video source |
| `Rendering` | Metal 核心、compositor、layer、camera、geometry 与 utility |
| `RenderGraph` | authored effect graph、dependency、render target、offscreen pool 与 ShaderContract |
| `Effects` | 具体 effect 的 pipeline、runtime plan 与 renderer |
| `Text` | 文字 descriptor、font、geometry、texture 与 dynamic text |
| `Particles` | 粒子 definition、parser、simulation、pipeline、texture 与 trail |

- 当前已落地的二级目录为 `RenderGraph/EffectExecution`，用于 authored-effect GPU execution 的完整 renderer 类型族；当前包括供统一 GraphExecutor 调用的 `SceneEffectStageRenderer*` per-stage typed backend，不再包含 standalone/whole-chain 产品 renderer，其余类别目前仍平铺，三级源码目录保持受控。
- 同一主类型与其 extension 必须在同一目录；不得新增 `Misc`、`Common`、`Helpers` 等兜底目录，也不得为未来能力预建空目录。
- 只有现有九类不能表达一组已经落地、具有共同生命周期或清晰依赖边界的多个文件时，才考虑新增一级目录。
- 当目录密度、共同生命周期或职责边界表明有必要时，可灵活新增二级目录，不要求预先固定全局分组方案；同批同步本规则、布局 manifest、自动门、受影响文档链接和测试源码路径，并按完整类型族迁移。
- 移动 Scene 源码时保持 Swift 内容字节不变和 `project.pbxproj` 无无关改动，并按“验证选择”的目录迁移合同验证。

## 8. `.codex` 工作区

`.codex` 是本机生成物工作区，不是源码、正式测试脚本或长期归档目录：

- 可复用的 Python/Swift/Shell 工具进入 `script/`，正式自动测试进入 `script/tests/`；一次性脚本使用 `mktemp -d`，任务结束前删除或整理为正式入口。
- 新的长期断言并入现有固定/完整矩阵或正式测试。定向 Scene 运行优先使用 `scene_wallpaper_benchmark.py --sample-id <id>`；不得为每轮测试留下新的 `.codex` matrix。
- 正式测试不得硬编码带日期的 `.codex` runtime 路径。真实样本 fixture 统一由 `script/scene_real_test_fixture.json` 指向当前主线完整门。
- benchmark 的隔离样本、副本、临时 `HOME` 和 `runtime-app-*` 只属于当次运行；PASS 后应由既有流程清理，FAIL 仅保留失败现场。检查完整沙箱时显式使用 `--keep-runtime` 或 `--keep-runtime-app`。
- 产生过 `.codex` build、benchmark 或 runtime 产物的批次，收尾前运行 `python3 script/audit_codex_artifacts.py --fail-on-candidates`。对目标精确、已无 fixture/文档/测试/进程引用、且属于可重建或重复运行结果的无用残留，可无需再次询问直接删除。
- 删除后重跑审计，最终只报告实际删除范围、释放空间、保留例外和不可恢复性。归属不清、仍是唯一失败现场/运行证据/样本输入的候选只报告不删。禁止 `rm -rf .codex`、`git clean` 或按名称/日期模糊删除。
- 只保留共享 `.codex/DerivedData`，不得长期留下单次能力验证的 `DerivedData-*`。

## 9. 并行工作

- 并行写入前分配互不重叠的文件或主类型所有权；同一测试、矩阵和权威文档不得并发修改。
- 静态扫描和彼此独立的测试模块可以并行；`script/build_and_run.sh`、共享 `.codex/DerivedData`、App runtime、benchmark、固定门和完整门必须串行。
- 一个批次由主代理维护唯一断裂边、correctness atom 和稳定快照。只读代理必须基于明确快照一次性给出 PASS/BLOCK，不得在共享源码持续变化时循环追审；审计结论不能替代主代理阅读权威资料、实现代码和取得运行证据。
- 一个共享批次只由一名整合者暂存和提交，禁止 `git add -A`。

## 10. 汇报

过程更新简短说明正在处理的问题、已确认根因、拟改位置和下一步。最终仅报告：改动、影响范围、实际运行的验证与结果、是否提交，以及尚未消除的风险或未验证项。不要把静态检查、样本矩阵、路由计数或历史文档描述成超出其证据范围的结论。
