# MyWallpaperX 开发规则

本文件只保留会影响实现、验证、提交或工作区安全的现役规则。能力等级、样本计数、报告路径和历史结论不在这里重复，以现役语义文档和运行证据为准。

## 1. 工作边界

- 先确认用户要的是讨论、只读审查、诊断还是实现。只读任务不得修改、构建、生成缓存、暂存或提交。
- 保留工作区已有改动；先读 `git status`、相关规则、现役文档和受影响代码。不得用 `git reset --hard`、`git checkout --`、`git clean` 或宽泛的暂存命令覆盖他人工作。
- 只修改与当前目标直接相关的文件。发现计划外问题时，记录影响并单独决定是否纳入；不得顺手重构或清理。
- 信息不足时先用本机代码、测试、样本和可验证资料补齐。对未验证结论明确标为推断。

## 2. 工具与子代理协作

工具调用和并行委派是日常开发流程的一部分，不是可省略的附加步骤。除纯问答、单文件且根因明确的微小改动外，主 Agent 在改动前必须先并行完成工作区/历史检查、受影响代码与调用链追踪、测试/文档合同核对；优先使用 `rg`、`git status`、`git diff`、现有 `script/` 入口和实际测试，不凭文件名或报错文本猜测。

满足任一条件时，主 Agent 必须在可用并发槽内启动 2 至 3 个子代理并行处理独立子任务：

- 根因可能位于两个无重叠职责域，或实现前同时需要代码追踪、运行复现、样本/证据或资料核对；
- 改动触达公共运行链路，需要实现外的独立回归影响审查；
- 有多个独立样本故障，或文档、门禁、测试可与实现拆成明确任务；
- 目录迁移、架构调整或跨模块改动需要独立的影响盘点和验收。

默认分工为：一个子代理只读追踪代码与影响面；一个子代理只读核对测试、样本和证据合同；需要时一个子代理审查拟定方案或负责已分配、互不重叠的文件。单一问题的实现者应直接使用工具完成检查、修改和定向验证；不得为简单任务建立串行的角色扮演链路。

- 子代理任务必须写明目标、只读或可写、唯一文件所有权、不得触碰的路径、验收命令和回报格式。未获转交不得修改他人已认领文件。
- 同一文件、同一主类型的强耦合 extension、同一测试/矩阵合同、尚未确定接口的上下游实现不得并行写入。跨所有权改动先回报主 Agent，由主 Agent 重新分配或自行整合。
- 只读子代理不得格式化、生成缓存、暂存、提交或修改文件。需要运行验证时使用独立临时目录、临时 `HOME` 和隔离样本副本。
- 主 Agent 是唯一整合者：负责定义接口和所有权、读取最终 diff、处理冲突、运行合并后的最小充分验证，并统一暂存、提交和对外结论。子代理不得自行提交或宣告整体通过。
- 子代理回报必须包含：已查证事实、读取/修改的精确路径、实际命令与结果、未验证项，以及对其他子任务的接口或风险。

以下资源锁必须遵守：

| 可并行 | 必须串行 |
| --- | --- |
| `rg`/文档/历史只读核对、独立 Python 单测、`check_code_health.py`、静态结构和链接测试 | `script/build_and_run.sh`、共享 `.codex/DerivedData` 的 Xcode 构建、真实宿主 runtime benchmark、固定/完整样本门 |
| `run_scene_tests.py` 的模块并行调度 | 同时运行多个 benchmark、与 benchmark 并行的 App 启动/构建、同一测试或矩阵合同的并发写入 |

`script/build_and_run.sh` 会终止同名 App 并复用 `.codex/DerivedData`；`scene_wallpaper_benchmark.py` 使用宿主运行态；二者不得与彼此或同类运行并行。`python3 script/audit_codex_artifacts.py --fail-on-candidates` 只在所有 benchmark、构建和临时运行完成后执行。

优先复用现有入口：单模块使用 `python3 -m unittest script.tests.test_scene_<能力>`；相关模块使用 `python3 script/run_scene_tests.py -k <keyword> -j <n>`；Swift 改动使用 `python3 script/check_code_health.py --check --base-ref HEAD`；定向真实 Scene 使用隔离 root 的 `scene_wallpaper_benchmark.py --sample-id <id>`。`run_scene_tests.py` 会发现全部 `script/tests/test_*.py`，并非严格 Scene-only 过滤器。

## 3. Scene 事实与证据

真实创意工坊样本根 `~/Movies/MyWallpaperX/创意工坊/` 只读。任何 benchmark、属性注入、缓存操作或样本修改都必须在隔离副本中进行，并同时使用隔离的 Workshop root 与临时 `HOME`；不得直接改动、删除或清理真实样本。

Scene 开发和报告使用以下层级，低层或历史材料不得反向覆盖高层事实：

1. [总覆盖台账](docs/scene/semantics/coverage-ledger.md)：系统摘要与专项表入口。
2. [能力依赖图](docs/scene/semantics/capability-dependency-map.md)：确认公共前置能力和开发顺序。
3. Effect、粒子、SceneScript、Graph/Shader、运行输入/属性和高级对象专项表：逐项等级、代码、测试与缺口的事实来源。
4. [运行证据索引](docs/scene/semantics/runtime-evidence-index.md)：当前可宣称的样本、构建与运行事实。
5. [Web/Scene 现状路线](docs/reviews/web-scene-current-state-roadmap-2026-07-19.md)：跨系统摘要和路线入口，不替代专项表或运行证据。

不得将 `recognized`、`wired`、`executed-degraded`、固定 strict profile、固定样本通过或静态参考材料表述为完整兼容或 Wallpaper Engine 视觉等价。官方/参考材料只可作为 clean-room 证据；不得复制其 payload、shader、纹理、JSON、二进制或算法表达，新增断言使用项目自有 fixture。

## 4. 实现流程

### 修复前

对每个报错样本或用户可见问题，先确认：

- 预期行为、实际行为与可复现路径；
- 根因归类：样本逻辑、框架实现、依赖、解析、缓存/构建产物或环境；
- 是否属于公共逻辑并影响多个样本；
- 受影响文件、样本和验证范围。

开始改动前给出简短计划：问题与根因假设、拟改位置、影响范围、验证样本及每步验收标准。优先修复共享逻辑，不得用样本 ID 分支、跳过校验、隐藏错误或放宽 fail-closed 行为制造通过。

### 实现与提交

- 单次只处理一个相对独立的问题；完成后立即运行该问题的定向验证与合理的回归集合。
- 先确认改动被实际加载，再解释运行结果：检查构建产物、缓存、入口、配置和资源路径；必要时重建隔离运行环境。
- 验证通过后才提交该问题。提交信息须说明问题、根因和验证；不混入无关改动。
- 修改文档、规则或门禁时也保持独立提交边界，并验证链接、脚本或门禁合同，没有功能改动时不虚构运行验证。

## 5. 验证选择

按影响面选择最小充分集合，不默认全量运行：

| 改动范围 | 至少验证 |
| --- | --- |
| 单一解析分支、effect profile 或样本逻辑 | 对应单元/模块测试和定向隔离样本 |
| 公共解析、属性、缓存、资源链或运行时 | 相关测试集合和能覆盖受影响分支的定向隔离样本；仅在定向集合无法覆盖共享风险时增加固定门 |
| RenderGraph、核心执行链路、公共依赖或目录迁移 | Scene 全量测试、代码健康和签名构建；固定门按下述触发条件决定，不因目录或公共代码改动自动运行 |
| 真实样本新增/移除、完整矩阵合同变化、发布或里程碑收口 | 重建隔离副本并运行完整快照门 |

`script/scene_wallpaper_sample_matrix.json` 是固定回归门，`script/scene_wallpaper_full_sample_matrix.json` 是当前真实 Scene 目录的完整快照门。两者有重叠但不可互相替代，报告必须分别说明；部分样本或矩阵缺失不得写成 PASS。

固定门不是每次公共改动的默认步骤。只有改动同时影响多个固定样本可能共用的行为，且定向样本与模块测试不能充分覆盖该风险时才运行；运行前记录受影响的共享合同、所选固定样本和定向验证不足的原因。

完整快照门是昂贵的里程碑核实，不得作为日常回归的惯性动作。除样本集合或完整矩阵合同变动、发布/里程碑收口外，只有预期影响跨样本且无法由定向样本、模块测试和固定门合理排除时才可运行；执行前必须说明该全量运行要核实的具体假设与替代验证为何不足。普通解析、effect、资源或公共运行时改动默认不跑完整快照。

Swift/Metal 测试若受模块缓存权限阻塞，先将 `CLANG_MODULE_CACHE_PATH` 与 `SWIFT_MODULECACHE_PATH` 指向 `/private/tmp` 下的专用目录，再区分环境失败与产品回归。

## 6. Swift 代码健康

- 新增或未列入 `script/code_health_baseline.json` 的 Swift 文件不得超过 400 个物理行。不得压缩语句、删除合理空行或降低可读性规避限制。
- 历史超限文件只能保持或缩小；触达时先判断能否按真实职责拆出独立声明或 extension。只有有复用、独立生命周期或可明显降低复杂度时才新增类型、协议、包装层或文件。
- 拆分须保持行为、命名和访问边界。不得为跨文件访问批量放宽 `private`，也不得为满足行数机械切开强耦合流程。
- 修改 Swift 后、构建前和提交前运行：`python3 script/check_code_health.py --check --base-ref HEAD`。文件缩短时先运行 `python3 script/check_code_health.py --ratchet-baseline`，再执行检查。
- 未经用户明确批准，不得新增历史例外、提高额度、移除源码根目录或提高 400 行阈值。新增 Swift 源码根目录、Tests 或 helper target 时必须纳入扫描；远端比较使用 `--base-ref <base-ref>`。

## 7. Scene 源码布局

`MyWallpaperX/Core/SteamWorkshopScene` 是分类根目录，不直接放置 Swift 文件。当前布局合同由 `script/tests/test_scene_semantics_coverage.py` 强制：源码只可位于以下九个一级目录，且当前不允许二级源码目录：

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

- 同一主类型与其 extension 必须在同一目录；不得新增 `Misc`、`Common`、`Helpers` 等兜底目录，也不得为未来能力预建空目录。
- 只有现有九类不能表达一组已经落地、具有共同生命周期或清晰依赖边界的多个文件时，才考虑新增一级目录。
- `RenderGraph` 的密度达到需要二级分组时，必须作为独立架构变更：先更新本规则、布局测试、受影响文档链接和测试源码路径，再按职责小批迁移；不得在功能修复中顺手移动文件。迁移完成前，现有一层深合同继续生效。
- 移动 Scene 源码时保持 `project.pbxproj` 无无关改动，并按第 5 节的核心执行链路范围验证。

## 8. `.codex` 工作区

`.codex` 是本机生成物工作区，不是源码、正式测试脚本或长期归档目录：

- 可复用的 Python/Swift/Shell 工具进入 `script/`，正式自动测试进入 `script/tests/`；一次性脚本使用 `mktemp -d`，任务结束前删除或整理为正式入口。
- 新的长期断言并入现有固定/完整矩阵或正式测试。定向 Scene 运行优先使用 `scene_wallpaper_benchmark.py --sample-id <id>`；不得为每轮测试留下新的 `.codex` matrix。
- 正式测试不得硬编码带日期的 `.codex` runtime 路径。真实样本 fixture 统一由 `script/scene_real_test_fixture.json` 指向当前主线完整门。
- benchmark 的隔离样本、副本、临时 `HOME` 和 `runtime-app-*` 只属于当次运行；PASS 后应由既有流程清理，FAIL 仅保留失败现场。检查完整沙箱时显式使用 `--keep-runtime` 或 `--keep-runtime-app`。
- 每个开发批次收尾前运行 `python3 script/audit_codex_artifacts.py --fail-on-candidates`。它只报告候选项，不授权清理；确认后才可移入废纸篓。禁止 `rm -rf .codex`、`git clean` 或按名称/日期模糊删除。
- 只保留共享 `.codex/DerivedData`，不得长期留下单次能力验证的 `DerivedData-*`。

## 9. 汇报

过程更新简短说明正在处理的问题、已确认根因、拟改位置和下一步。最终仅报告：改动、影响范围、实际运行的验证与结果、是否提交，以及尚未消除的风险或未验证项。不要把静态检查、样本矩阵、路由计数或历史文档描述成超出其证据范围的结论。
