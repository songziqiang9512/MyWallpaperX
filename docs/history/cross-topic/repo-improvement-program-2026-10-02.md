# MyWallpaperX 仓库改良方案（修订版 3·终审后）

> **历史证据 — 非现役入口**

- 截止：2026-10-02。由只读研究工作流 dwfrun-fcceca6d 产出（六视角现状侦察＋四主题业界调研 → 综合差距分析 → 主笔起草 → 三视角两轮审查 → 独立终审后修订版 3），全文 18 条 P0-P2 改良条目，逐条含问题/方案/执行步骤/验收门/退役条件。
- 本文是改良提案的定稿存档：不决定当前能力、架构或下一任务；任何实施须按 AGENTS.md 批次与设计前置纪律另行立项，采纳与否由 owner 裁决。
- 文内【复核】【侦察】【审查】【调研】【推测】为证据口径标注，定义见文首声明。

**性质**：改良提案（只读调研产物），未经 owner 批准前不含任何实施动作。撰写会话严格只读：未编辑/创建文件、未构建（无 xcodebuild）、未生成缓存（python3 一律 `-B`）、未暂存/提交（仅 /private/tmp 一次性命令模拟，用后即删）。

**证据口径**（全文标注）：
- 【复核】＝本撰写会话 2026-10-02 只读命令实测（命令与关键输出随条目给出）；
- 【侦察】＝输入材料《现状侦察》给定的实测证据，本会话未复跑的项按原样引用；
- 【审查】＝审查员意见给定的实测事实（关键项本会话已只读复核，复核处单独标注）；
- 【调研】＝输入材料《业界调研》给定来源；【推测】＝无法从证据定案的推断，全部收入 §9。

**未复跑声明**：侦察项中 141.7s 模块计时、code-health 237 warnings/0 errors、5095 链接 0 断链、role-index 13 项测试通过、67/80 提交统计、blob top-5、CI 行号等未在本会话复跑（只读纪律、任务口径为文件级核对），均标【侦察】。全仓『sampler-alias grep 命中 20 文件』的侦察口径会扫入 16GB 本机证据缓存【审查指出】；本会话以 tracked md 口径复核为 3 处引用（`git grep -l 'sampler-alias' -- '*.md'`＝d2-d3 历史文档、runtime-architecture.md、runtime-evidence-current.md，均非导航入口），『四层导航零引用』已独立复核成立。

**工作区状态**：存在并行会话未提交改动（会话起始快照：`docs/document-role-index.json`、`docs/scene/scene-compatibility-roadmap.md`、`script/design_gated_areas.json`、`script/scene_source_layout.json` 被修改，`docs/scene/design/optional-named-source-failure-design.md` 未跟踪）。治理 JSON 计数以本会话实测为准：path_groups 64【复核】、role index documents 67【复核】、gated areas 19【复核】（侦察时 63/65/18）——不归因、不清理，漂移常态化因此列入每批固定首步（§5）。

**本轮修订**（独立终审后最小化修订，五项）：①P2-2 验收命令换为不被新建 Debug/ 目录误计的形式（/private/tmp 模拟实测：旧命令=1、新命令=0【复核】）；②批11 排程三处对齐——code_health_baseline.json 补入 §5.1 判据、批11 入临界区全集、区域设计文档点名（design_gated_areas 对应条目 designDoc【复核】）；③批15『批5 在飞禁插』三处对齐（§5.1 规则＋条目＋批次表）；④P1-4 冻结口径显式定义为声明关键字类、表达式类为已声明豁免边界＋二期扩正则（示例断言实测不在口径内【复核】）；⑤P0-5 大小门补存量违例清点与冻结条款（script/ 519 个 tracked 文件中 >5MB 仅 census 一项【复核】，门上线即绿可达性已验证）。

---

## 1. 目标与非目标

### 1.1 目标（判据化）

- **G1 首跳命中**：Agent 从任意指令出发，最少跳数命中当前事实与合同。导航页只放指针不复制事实；大型权威文档锚点化＋顶部快照＋阅读契约（证据页已是范本）。判据：§8-M1（样例任务已按真实频率重选，见 P0-2）。
- **G2 单一权威、机器执法**：新约束一律扩展现有机制（document-role-index、scene_validation_gates.json、三条棘轮基线）落成机器可检的门，不引入第二套治理或平行索引。判据：§8-M2/M3。
- **G3 存量冻结、只许收缩**：存量违例先冻结计数、新增即红；清偿按卡走固定节拍（冻结≠清偿，Packwerk 教训）。判据：§8-M7。
- **G4 失败半径与批次纪律**：一条改良＝一个可见结果＝一个职责批次；秒级确定性 JSON 对账才允许进提交期，重门不进 inner；并行会话靠 owned-paths 机器隔离而非口头约定。判据：§8-M4。
- **G5 推测与开放问题显式化**：无法从证据定案的点写开放问题交 owner（§9，共 13 项），并附『裁决点→批次』对照（§5.3）。

### 1.2 非目标（显式拒绝清单）

| 拒绝项 | 依据 |
|---|---|
| llms.txt/llms-full.txt、平台化（Confluence/Notion）、全文搜索型第二治理 | 【调研·文档架构 caveats】；违反 docs/README.md:44『同一当前事实只保留一个权威解释』【复核】 |
| 任何第二套主链权威（property/provider/clock/graph/resource registry/compositor） | AGENTS.md:17【复核】 |
| docs 顶级目录按 Diátaxis 四象限重组 | 【调研·文档架构 caveats】治理轴与读者意图轴正交 |
| 拆 Swift target／微服务化 | 【调研·代码治理 caveats】 |
| 覆盖率百分比门禁、通用复杂度阈值 | 【调研·代码治理 caveats】Goodhart；400/1000 行限＋家族预算更贴合 |
| 扩写 AGENTS.md 为大而全模板 | AGENTS.md:3＋:21【复核】；38 行【复核】已是范本；【调研·Agent 协作 caveats】 |
| git 历史 rewrite（census 历史 blob） | 破坏性、owner 单独裁决，P0-5 明确不含 |
| CODEOWNERS、PR 审查流、定时公开评审、社区流程 | 【调研·标杆 caveats】owner 已由 design_gated_areas.json owner 字段承载【复核】 |
| 绕过 `--accept-growth/--reason` 通道扩任何棘轮预算 | AGENTS.md:20/:34【复核】 |
| 把构建/测试/全仓扫描塞进 inner 或 git 钩子 | AGENTS.md:34【复核】；【调研·标杆 caveats】 |
| 重排 Compilation 家族（243 文件）目录结构 | 处置走 P2-5 债务队列＋OQ10 owner 裁决，不做本方案内重组条目 |

## 2. 现状诊断摘要（六域要点＋调研佐证）

### 2.1 仓库结构
资产：Scene 子树 7 顶层/30 二级目录与 `script/scene_source_layout.json` 契约 100% 一致、692/692 Scene 前缀、禁 Common/Helpers/Misc，家族预算冻结（shape-analyzer 123 成员 inventory）【侦察】。子树内非 Swift tracked 文件（.metal、QuickJSNG 的 LICENSE/README.md/.c/.h）与布局契约共存无冲突【复核 git ls-files】。
要点问题：①Compilation 家族 243 文件/81,494 行高度聚集（high）【侦察】——处置口径见 OQ10；②Format(31)/Diagnostics(12) 两个平铺顶层无二级契约，43 文件不受 file_globs 门禁【复核 find 计数；布局测试对 depth-2 文件显式跳过，见 P2-3】；③App/ 35 文件中 21 个 Debug 前缀 runner 与产品入口混居【复核 ls 计数】；④7 处 .mimosa 会话状态散布源码树与资源 bundle【复核 find 计数】；⑤Top 2 文件恰好压 1000 行硬限【推测：行数服从拆分边界，OQ2；code-health 基线 notes 佐证见 P1-5】。
调研佐证：结构纪律即 fitness function 形态【调研·代码治理另注】；出路是 inventory 冻结＋偿还队列（P2-3/P2-5），不是重组。

### 2.2 文档体系
资产：入口链短（每跳 ≤120 行）【侦察】；git 跟踪 md 117 个/8.84MB【复核】、5095 相对链接 0 断链且链接门挂 checkpoint+CI【侦察】；角色索引＋13 项测试实测通过【侦察】。
要点问题：①读取分层指引引用的节结构与两份最高权威台账实际不符（high，P0-1）【复核】；②角色索引发现域只覆盖 historyRoot∪带 marker 自声明文件，无 marker 的非 history 文件对测试不可见（P0-3，触发链本身已生效——见该条；未标记缺口实测 31 份【复核】）；③前三大 md 文件占跟踪总量 58%【复核计算 5,100,651/8,844,776B，含历史版 2.78MB】，超长单行 7108/6562 字节【复核】，coverage-ledger 0 锚点、58 条日期记录占头部 670 行【复核】；④『## 1 当前证据快照』名不副实：标题在 629 行，236 条 E-* 中 53 条在标题前【复核】。
调研佐证：Google freshness 元数据＋文档棘轮、渐进披露四件套【调研·文档架构 practice 2/3/4】。

### 2.3 规则与机器门
资产：单一编排器 verify_scene_change.py＋gates 注册表（64 path group【复核】/383 module 引用【侦察】）＋unmapped-change 强制映射门【复核 :427-437】；编排器自身 1058 行测试治理【侦察】；三条棘轮基线带显式改基线通道【侦察】；静态门成本极低【侦察】。
要点问题：①design-gate 缺席注册表【复核：'design-gate' in gates == False；:334/:350/:354 三处硬编码 append】；且编排器还发出其他未注册 id——动态 `{test_scope}-tests`（:292-297）、repository-all-tests（:305-311）、unmapped-change（:427-437）【复核代码；发出 id 全集 12 个/注册 9 个为审查实测】，注册完备率口径需在 P1-3 定义；②render_chain_authority_ratchet 37 条规则【复核】唯一执行者是被 INNER_HEAVY_MODULES【复核 :24】排除出 inner 的 test_scene_semantics_coverage（141.7s 三职责混杂，当前 3 个失败属并行改动不归因）【侦察】；③测试形状禁令与文档删除方向条款纯散文无执法【侦察】；④AGENTS.md:18 无限定措辞与 inner 阶段实际行为不一致【复核 :351-352 代码分支；真实 .metal 路径预览实测见 P1-3】。
调研佐证：『必须发生的边界用确定性门执法，而非建议性文本』【调研·Agent 协作 practice 2】。

### 2.4 代码质量
资产：卫生标记 0；code-health/scene-defense 实跑通过【侦察】；行为对拍基建真实【侦察】。
要点问题：①**声明关键字类**源文本断言 43 文件 181 处（冻结口径 v1＝`assert(In|NotIn)` 匹配以 `(func|let|var|struct|class|enum|case|guard|if) ` 开头的源码字符串）【复核 grep 计数】；**表达式类**源文本断言（如 assertIn("slot.candidates.indices.reversed()", source)——该行实测存在但不被口径 v1 匹配【复核：口径内命中 0、行存在 1】）是口径外的已知豁免边界（P1-4 显式声明＋二期处置）；两 类均与 AGENTS.md:35『不得把源码文本…作为通过条件』【复核】冲突，该条款纯散文无执法；②renderFrame 为 SceneMetalRenderer.swift 全文唯一函数（约 950 行贯穿五类职责）【复核：1000 行、`grep -c 'func '`=1；起点 :47 为侦察】，两文件顶格 1000 行【复核 wc】且仍在增长（code-health 基线 notes 记 2026-09-30 为 943/997【复核】）；③237 个超 review 限文件仅 warning【侦察】；④VectorConversion 近同义对 780/785 行【侦察】。
调研佐证：『红先行』变异判据、LSC 机械变更分流、Packwerk todo 清偿节拍【调研·代码治理 practice 1/5/6】。

### 2.5 Agent 导航体验
资产：入口链四层各司其职；SKILL 路由层 109 行纯路由【复核 wc】经 harness 自动可见【侦察】；semantics/README 当前能力入口表 8 行主题权威【复核】。
要点问题：①sampler-alias-precedence.md 设计合同从全部四层导航不可发现【复核：AGENTS.md＋三个 README grep exit 1】，tracked md 仅 3 处正文引用【复核 git grep】、无一是导航入口；②coverage-ledger 打开首先是 670 行日期流水，分层表未描述其地位【复核】；③S0-S5 定义埋在 runtime-evidence-current.md:625 导语【复核】而导航层无链接；④『失败半径→phase』判定分散三处：AGENTS.md:34 一句【复核】、development-workflow.md:42 仅 inner 命令【侦察】、integration/milestone 必选参数检查在 build_plan 运行门 unresolved 逻辑（:373-382【复核】；argparse 定义在 :510-535【复核】）；⑤三份并行路由文本（AGENTS.md:16、docs/README.md:7-22、scene-engine.md）漂移风险【推测——当前三处一致为侦察实测】；⑥术语（S0-S5、E-*、named source taxonomy、recognized/wired、owned paths、家族/防御面）无『术语→单一权威定义』入口，首跳命中以术语已知为前提【审查指出】。
调研佐证：最小高信号上下文＋JIT 检索、agents.md 精确路径映射、CPython 任务路由【调研·Agent 协作 practice 1、代码治理 practice 4、标杆 practice 2】。

### 2.6 开发流程与验证
资产：门选择可先预览后运行（本会话三次预览实跑【复核】）；发布一条命令端到端带双向核对【侦察】；checkpoint 构建隔离自清理＋活锁锁【复核 run_checkpoint_build.sh:5/22-44/46-56】；提交信息四要素文化【侦察】。
要点问题：①changed_paths 默认全量收集，无 owned-paths 机器支持（high，P0-4）【复核 :79-98】；②63.6MB census 快照 tracked 且反复重写【复核 63,613,673B/tracked；blob top-5 为侦察】，且存在多个已定位消费者（见 P0-5）；③checkpoint 每次全量冷构建无缓存复用【复核 :48-56；CI 固定缓存路径为侦察；冷构建时长未实测——只读禁构建】；④提交纪律无机器防护（.git/hooks 全为 *.sample、core.hooksPath 空【复核】），存在多职责/标题-内容不符提交【侦察】；⑤治理 JSON 是并行会话公共写热点【侦察】。
调研佐证：文件所有权拆分、aider 秒级 pre-commit＋curl 机检【调研·Agent 协作 practice 5、标杆 practice 5】。

### 2.7 总体判断
治理基建已领先业界常规【调研·文档架构另注明示】。瓶颈不是『缺规则』，而是五类缺口：①导航层与事实层脱节（说假话＋覆盖缺口＋术语无入口）；②既有执法机制的缝隙（发现域缺口、design-gate 注册、owned-paths、注册完备率口径）；③冻结≠清偿（无节拍无排序）；④单点重门＋巨文件（inner 不可用、顶格 1000 行且在涨）；⑤并行协作纯靠口头约定。分别对应 P0 全部五条、P1-2/P1-3/P1-4/P1-5、P2-5。

## 3. 设计原则

1. **首跳命中**。一切改良以『Agent 从任意指令出发、最少跳数命中当前事实与合同』为判据，且以真实任务频率为选择依据（不按撰写会话自身任务面挑选，见 P0-2）。导航页只放指针不复制事实（docs/README.md:44 已有条款【复核】，本方案补机器执法）；大型权威文档必须锚点化＋顶部快照＋阅读契约——证据页已有范本，推广而非发明（P1-1）。被拒反例：更深的导航链、llms.txt 全量注入。
2. **单一权威、机器执法**。新约束优先落成机器可检的门/棘轮/结构断言，一律扩展现有机制，不引入第二套治理或平行索引。任何新门必须带完整 lifecycle 元数据进注册表（P1-2/P1-3 立此规矩），且注册完备率分母＝编排器实际发出的 gate id 集合（机器可数），防落地即失真。
3. **存量冻结、只许收缩**。存量违例（声明类形状断言 43 文件/181 处、237 个超限文件、123 个分析器成员、18 个 canonicalHelpers、31 份未标记文档、Compilation 聚集）先冻结计数或显式接受（OQ10/OQ12/OQ13），新增即红，清偿按卡走固定节拍；冻结不等于清偿（Packwerk 教训【调研·代码治理 practice 1】）；任何冻结口径必须显式声明其覆盖面与豁免边界（P1-4 修正立此规矩）。
4. **失败半径与批次纪律**。一条改良＝一个可见结果＝一个职责批次（AGENTS.md:37【复核】）；秒级确定性 JSON 对账才允许进提交期，重门不进 inner（AGENTS.md:34【复核】）；并行会话靠 owned-paths 机器隔离而非口头约定（P0-4）；owned paths 声明一律点名到文件，不占用整目录（P0-5 修正立此规矩）；治理临界区批次严格串行（§5.1，批11 已补入对齐）。
5. **推测与开放问题显式化**。无法从证据定案的点写开放问题交 owner（§9），并附裁决点→批次对照（§5.3）；实施时核对项在条目内显式标注为实施前置核对，不冒充已核实事实——本版已把审查员代跑的核对（P0-5 消费者、P0-3 缺口计数、P2-2 验收命令可达性）升级进条目正文。

## 4. 分域改良条目

Owner 约定：本仓库为单一人类裁决者＋Agent 会话执行模型【调研·标杆 caveats】。条目中 Owner 指批准与验收的仓库 owner；执行指占用该批 owned paths 的 Agent 会话（**owned paths 一律点名到文件，不声明整目录所有权**）；触达 Scene 产品域时须与 `script/design_gated_areas.json` 对应区域 owner 字段对齐【复核：19 区域，owner 词汇以 scene-e-route(8)/web-route(2)/app-shell(2) 及组件 owner 为主】。

### 4.1 P0：导航真话、执法触发、并行隔离、体积止血

#### P0-1 ｜导航真话修正：读取分层表、history banner 与死链对齐文件实际结构
- **元信息**：文档｜S｜批1（治理临界区，§5.1）｜无前置｜Owner：仓库 owner；执行会话占 `docs/scene/semantics/README.md`、`docs/history/scene/runtime-evidence-index.md`、`docs/scene/design/composition-render-target-design.md`、`docs/scene/semantics/coverage-ledger.md`、`script/tests/test_document_role_index.py`（新增断言）
- **问题与证据**：semantics/README.md:12-14【复核 Read】当前状态层引『runtime-evidence-current.md 的 ## 1 当前证据快照』——该标题在 629 行且 236 条 E-* 中 53 条在标题前【复核 grep】，照做等于读入约 3855 行；:14 冷档层引『运行证据 ## 2』——该文件全文仅 1 个 H2，## 2 不存在【复核】；:14 引『台账 ## 8 的批次记录』——## 8 实为『现役路线映射』(1311 行)，58 条日期批次记录在第 3-669 行、位于 ## 1 口径(670 行)之前【复核】；history/runtime-evidence-index.md 头部历史 banner(:2)与遗留『状态：现役证据入口』(:4)、『当前核对分支』(:8)并存【复核 Read】；composition-render-target-design.md:19 以行内代码引用不存在的 `docs/history/scene/new-sample-gap-analysis.md`【复核 grep】（真实文件 tracked 于 docs/scene/semantics/【复核 git log】）——因是行内代码而非 md 链接，链接门【侦察】覆盖不到，本身即链接门盲区样本。
- **方案**：本批只让指引说真话，不做结构改造（留给 P1-1）：①修 semantics/README.md:12-14 节号与描述匹配现状；②删 history 文件头部遗留『状态/核对分支』块，仅保留历史 banner；③修 composition-render-target-design.md:19 引用为真实路径；④coverage-ledger 日期批次区首行补一句分层地位说明。
- **执行步骤**：1) 逐条修正四个文件；2) 新增机器断言防回潮（见验收门）；3) 跑角色索引测试＋全仓链接门。
- **验收门（机器可检）**：①test_document_role_index 新增断言：解析 semantics/README.md 分层表引用的『文件＋节名』，逐一 `grep -n '^## '` 校验节存在（对『## 2』类不存在引用即刻红）；②新增断言 history 文件头部不含『状态：现役』字样（现有 test_all_history_documents_are_explicit_historical_evidence 只 assertIn banner【侦察】）；③`python3 -B -m unittest script.tests.test_document_role_index` 通过；④全仓链接门（test_scene_semantics_coverage.py:721【复核】）绿。
- **退役/回退**：P1-1 结构改造后再同步一次节号（已列入 P1-1 验收）；纯文档改动 `git revert` 即回退。
- **风险**：低。行内代码路径引用不受链接门覆盖——如 owner 认可，『分层表引用节名断言』可作行内路径的补充检查（本批不做，防范围膨胀）。

#### P0-3 ｜封堵文档登记逃逸（批2a/批2b 拆分）：发现域冻结＋三份权威补登记，后批补全集或豁免
- **元信息**：规则｜批2a：S；批2b：M（登记全集非纯机械，见下）｜批2a、批2b 均治理临界区，串行｜批2a 前置批1；批2b 前置 OQ12 裁决（豁免类划分）｜Owner：仓库 owner；批2a 执行会话占 `script/tests/test_document_role_index.py`、`script/tests/test_verify_scene_change.py`、`docs/document-role-index.json`、三份待登记 md、script/ 新冻结基线 JSON；批2b 另占其余 28 份未标记 md 及其 entrypoint 文件
- **问题与证据**（触发链与发现域两层）：触发链**已经存在且生效**【复核】：scene_validation_gates.json 的 documentation path group（`{"id":"documentation","patterns":["docs/**","script/design_gated_areas.json"],"modules":["test_document_role_index",…]}`）在工作区与 HEAD 均存在（`git show HEAD:...` 解析比对一致）；实跑预览 `python3 -B script/verify_scene_change.py --phase inner --path docs/scene/semantics/source-index.md` 输出 `groups: documentation, semantics`，focused-tests 已含 `--module test_document_role_index`。真实缺口在**发现域且远大于三份**【复核，本会话 census】：`git ls-files 'docs/scene/semantics/*.md' | wc -l`=28，仅 2 份有 marker（official-client-behavior-research-workflow.md、runtime-evidence-current.md），26 份未标记（含 semantics/README.md 本身、coverage-ledger.md、source-index.md、9 个 coverage 专项表、6 份 forensics/reference 文档、两份样本台账等，逐份清单已实测）；design 22 份中 17 份有 marker，**5 份未标记恰为**：alpha-display-fallback-design.md、batch2-design-index.md、scene-resource-admission.md、scene-startup-pipeline.md、static-source-draw-only-degradation.md【复核 grep -L 清单】。**合计 31 份未标记**。机制根因【复核】：test_document_role_index.py:110-150 发现集合＝historyRoot rglob ∪ 带 marker 的 additionalPaths（:121-126 要求相等；:139-149 要求 indexed=discovered），无 marker 的非 history 文件对测试不可见。**登记全集非纯机械**【审查指出＋复核】：每份新登记须满足 test_each_entrypoint_actually_links_its_document（:308-321，entrypoint 须含 md 链接）与 stable-contract 元数据断言——forensics 类文档当前导航层无链接；batch2-design-index.md 本身是 12 份索引文档的 entrypoint【复核 python 计数】。初稿『断言要求全部登记＋只补三份』自相矛盾，已拆批修正。
- **方案**：**批2a（冻结＋三份权威补登记）**：①发现断言＝『新增即红＋存量冻结』：docs/scene/{semantics,design} 下 tracked md 集合必须 ⊆ 冻结基线（记录现存 31 份未标记路径）∪ 已登记集合——新增 md 无 marker 即红，存量 31 份计数只降不升（ratchet 模式，与 P1-4 同构）；②触发语义回归锁定：新增测试断言 documentation path group 的 patterns 含 `docs/**` 且 modules 含 test_document_role_index（防未来收缩）；③补登记三份**当前权威**文件（coverage-ledger.md『当前能力唯一权威』、new-sample-gap-analysis.md、static-source-draw-only-degradation.md）——含 marker、索引条目、entrypoint 链接与 stable-contract 元数据，使基线降至 28。**批2b（OQ12 裁决后）**：对剩余 28 份按 owner 裁决口径补登记或按豁免类（候选：目录 README、forensics 研究档）显式豁免——豁免进基线的 exempted 分类而非无记录；每份新登记补 entrypoint 链接（部分需在导航层加链接，非纯机械，故 M）。
- **执行步骤（批2a）**：1) 生成 31 份未标记清单入冻结基线 JSON；2) 写发现断言（新建无 marker md 应红——红先行）；3) 三份权威文件登记（含 entrypoint 链接）使基线降 28；4) 写触发回归测试（临时移除 docs/** pattern 应红）；5) 扩展编排器测试。（批2b）：OQ12 裁决 → 逐份登记/豁免 → entrypoint 链接补录 → 基线降至豁免外 0。
- **验收门（批2a）**：①`python3 -B -m unittest script.tests.test_document_role_index` 通过；②发现断言红先行自测（新建无 marker md 红）＋基线 31→28 只降不升有断言；③触发回归红先行自测；④预览命令（同上）计划含 test_document_role_index——**本会话已实测绿**【复核】，作回归锚点。（批2b）：①豁免类经 owner 认可后，豁免外登记 100% 且机器可数（基线 exempted 分类非零即须对应 OQ12 裁决记录）；②每份新登记的 entrypoint 链接测试绿；③M3 达成（见 §8）。
- **退役/回退**：批2a 独立 revert（删基线与断言）；批2b 独立 revert；history 由 historyRoot 机制另管【侦察】不涉。
- **风险**：豁免类划分错误会把应登记的权威挡在门外——豁免须对应 OQ12 裁决记录且基线可审计；批2b 的 entrypoint 补录触碰导航页，与批4b/批9 的导航改动错开（§5.1 串行已覆盖）。

#### P0-4 ｜verify_scene_change 支持 owned paths 圈定，并行会话互不吸入对方改动
- **元信息**：流程｜M｜批3（治理临界区）｜与批2a 同改 verify_scene_change.py 串行；与批6 同文件，批3×批6 亦须串行（§5.1）｜Owner：仓库 owner；执行会话占 `script/verify_scene_change.py`、`script/tests/test_verify_scene_change.py`
- **问题与证据**：changed_paths 默认 --base HEAD 时全量收集 `git diff --name-only --diff-filter=ACDMRTUXB`＋`git ls-files --others --exclude-standard`【复核 :79-98（二审复跑 :82-97 同）】，仅显式 --path 白名单可覆盖；并行会话跨职责修改会扩大另一会话门禁范围（当前工作区即实例【复核 git status 过滤】）；AGENTS.md:7『开工划定 owned paths』【复核】无机器支持——**这也是批5 在飞期间须禁插批12/批15/批17 的原因**（P0-4 落地前无机器隔离）。
- **方案**：增加 --exclude/--owned-only 模式：按会话声明的 owned paths 过滤变更集，未声明路径不计入门禁计划；默认全量行为不变。**排除可见性护栏**：owned-only 的预览输出与批次报告必须列出被排除的变更路径清单（可事后审计），防止前缀写错静默漏门。可选配套（owner 裁决后做）：每会话 owned path 集登记进共享任务清单并校验不重叠【调研·Agent 协作 practice 5】。
- **执行步骤**：1) argparse 增参＋过滤实现＋排除清单输出；2) 编排器既有测试（1058 行【侦察】）扩展用例：构造含模拟并行改动的路径集，断言 owned-only 计划不含非 owned 路径触发的门（code-health/design-gate/scene-defense），且预览列出被排除路径；3) 人工复核一例预览。
- **验收门**：①新用例通过；②预览演示：当前工作区状态下 owned-only 圈定 docs/** 后计划不含 Swift 改动触发的 code-health/build-verify，且输出含被排除路径清单（仅预览不运行）。
- **退役/回退**：纯增量参数，默认路径零改动。
- **风险**：圈定过窄漏掉共享基线耦合——默认不变、显式选用；unmapped-change 门（:427-437【复核】）对已圈入路径保留兜底，被排除路径靠可见性清单审计。

#### P0-2 ｜任务型路由表机器化（批4a/4b 拆分）：任务→事实权威＋设计合同＋验证门＋入口测试
- **元信息**：Agent 体验｜M｜批4a＋批4b（均治理临界区）｜批4a 前置批2a（三份权威入索引＋新增即红）＋OQ6 裁决（硬前置）；批4b 前置＝路由表覆盖面经 owner 验收达标｜Owner：仓库 owner；owner 词汇与 design_gated_areas.json 对齐【复核】；批4a 执行会话占路由 JSON、`script/tests/` 新路由表测试、AGENTS.md/docs/README.md/scene-engine.md 各一行指针；批4b 另含三份文本去重
- **问题与证据**：①sampler-alias-precedence.md 四层导航零引用【复核 grep exit 1】，tracked md 仅 3 处正文引用【复核 git grep】；②docs/README.md:7-22 角色表按事实类型组织【复核】，回答『某事实在哪』而非『我要动 X 需要过哪些权威与门』；③『失败半径→phase』判定分散三处（§2.5-④【复核】）；④三份并行路由文本漂移风险【推测】；⑤**角色表不可删**：docs/README.md 是 5 份索引文档的 entrypoint（appkit-migration、technology-stack-boundaries、runtime-architecture、scene-launch-responsiveness-contract、scene-steamkit-migration-plan【复核 python 计数】），其中 4 份的入口链接正来自该角色表；test_each_entrypoint_actually_links_its_document（test_document_role_index.py:308-321【复核】）要求 entrypoint 内含指向文档的 md 链接——删除该表即红此测试；⑥高频任务无路由：『修复 Scene 样本视觉缺陷』是近期提交最高频任务类【侦察 git log 样例】，『发布新版本』链路零覆盖，『新增能力是否触发设计前置』（AGENTS.md:18 判定程序①-⑤【复核】）无任务键——首版任务键必须按可机器复核的频率依据重选（一审 blocker，已修正）。
- **方案**：落一张机器可查『任务类型→最短必读清单＋owner＋设计前置＋验证门组合（含各 phase 必选参数）＋最近入口测试』映射，以 script/ 新 JSON 承载（不扩 role index 语义），--list/--query 暴露。**docs/README.md 角色表保留为指针/链接枢纽**，路由表增补任务→门维度而非替换该表——entrypoint 字段零迁移。批4a 只建表＋接口＋测试，三份导航文本各加一行指针、**不删任何既有映射**；批4b 在覆盖面经 owner 验收达标后再做指针化与删除重复映射。**首版任务键**：批4a 第 1 步跑 git log 提交标题任务前缀分布并记入证据；必含『修复 Scene 视觉缺陷』（映射：coverage-ledger 快照→对应设计合同→官方取证工作流→视觉验证门组合）与『发布新版本』（release-signing.md→publish_release.py→签名/构建/Release 核验门）；『新增能力是否触发设计前置』作为首层查询（AGENTS.md:18 判定程序→design_gated_areas.json→check_design_gate）；S0-S5 表【复核 :625】纳入可链接位置（批9a 后升级为稳定小节链接）。**术语键**（S0-S5、E-*、named source taxonomy、recognized/wired、owned paths、家族/防御面→各自唯一权威定义）是否进路由表或升格 source-index 为术语权威入口，并入 OQ6 裁决。
- **执行步骤（批4a）**：1) git log 频率统计进证据；2) OQ6 裁决任务键集合与术语键方案；3) 定 JSON schema；4) 首版数据（含两个必含键＋设计前置首层查询）；5) --list/--query 接口；6) 三份文本各加一行指针（不删映射）；7) 互检＋完备触发测试。（批4b）：覆盖面达标后去重＋指针化，复跑 role index 测试。
- **验收门（批4a）**：①路由表引用的每个路径存在（测试断言）；②design_gated_areas 全部区域（19【复核】）出现在表；③断言 sampler-alias-precedence.md 等 stable-contract 设计合同可从任一导航入口 ≤1 跳可达（沿指针行/角色表/入口链接遍历一层断言）；④互检一致：同一文件不出现两种角色声明，且 role index 中 stable-contract 类新登记必须被至少一个任务键引用或显式豁免（**完备触发**）；⑤--query 对『修复 Scene 视觉缺陷』『发布新版本』『设计前置判定』三任务返回非空且含 gate 组合。（批4b）：去重后 role index 全部测试绿（含 entrypoint 链接测试）、全仓链接门绿，被删映射逐条列出对应路由表条目。
- **退役/回退**：路由表是索引不是权威；批4a 可独立 revert（只增不删）；批4b revert 即恢复三份文本原状。
- **风险**：任务粒度不合用（OQ6 硬前置缓解）；批4b 去重误伤 entrypoint 链接——验收门含 entrypoint 测试兜底；AGENTS.md 触碰保持收敛改写（:21【复核】）且不增行数预算。

#### P0-5 ｜census 快照移出 git 追踪并加大文件门（含存量违例清点与冻结条款）
- **元信息**：结构｜**M**（消费者已实测存在，处置含消费者改写＋测试调整＋注册表分类＋存量清点四件事）｜批5（治理临界区：大小门注册触 scene_validation_gates.json/CI）｜Owner：仓库 owner；**执行会话 owned paths 点名清单**：`script/scene_capability_census.py`、`script/scene_sample_debug_archive.py`、`script/scene_wallpaper_benchmark.py`、`script/tests/test_scene_capability_census.py`、`script/tests/test_scene_product_entry_audio_baseline.py`、`script/scene_validation_gates.json`、`.gitignore`、`.github/workflows/`、新大小门脚本（显式点名新路径，如 `script/check_tracked_file_budget.py`）、census 快照落点生成方配置；**批5 在飞期间批12/批15/批17 不得插入**（P0-4 未落地前 changed_paths 全量收集【复核 :82-97】会把 run_checkpoint_build.sh【复核 :48 确在 script/】与队列/清单新文件吸进批5 门禁计划）
- **问题与证据**：script/scene_capability_census_snapshot.json 磁盘 63,613,673 字节且 tracked【复核 ls/git ls-files】；全库最大 blob 前 5 名中 3 个是其历史版本【侦察】。**消费者已定位**（审查实测＋本会话逐条复核 grep -n）：`script/scene_validation_gates.json:1563`（该 tracked 路径登记于 path group patterns）、`script/tests/test_scene_capability_census.py:1038`、`script/tests/test_scene_product_entry_audio_baseline.py:84`、`script/scene_sample_debug_archive.py:37`（DEFAULT_SNAPSHOT 常量）、`script/scene_wallpaper_benchmark.py:8897`、`script/scene_capability_census.py` 6 处默认路径【复核 grep -c=6】。**存量违例清点（终审补，本会话已跑）**【复核：python3 遍历 `git ls-files script/` 全部 519 个 tracked 文件按大小排序】：>5MB 者仅 census 快照一项（次大 scene_sample_debug_archive.json 617,966 字节，其余 top-8 均 <5MB）——大小门在 census 移出后上线即绿，可达性已验证；blob top-5 的其余历史条目属历史 blob，不影响只检当前 tracked 文件的前向门（rewrite 明确不含）。
- **方案**：①消费者逐一处置：测试改 skip-if-absent 或『先再生快照再运行』路径，工具脚本默认路径改 evidence 缓存落点（docs/scene/evidence/ 为仓库忽略本机缓存【复核 AGENTS.md:38】）；②path group 中该 pattern 分类调整：untrack 后按 unmapped-change 门规则显式登记豁免或改组（预览验证不阻塞）；③`git rm --cached`＋.gitignore，快照生成方改写本机落点；④大小门（断言 script/ 下 tracked 单文件 ≤5MB 建议值，挂 CI 或注册进编排器带 lifecycle 元数据）**带冻结条款**：门附基线豁免清单——若未来出现第二个 >5MB tracked 文件，须显式改基线登记 owner/理由/退役条件后方可入库（与其他棘轮一致，本方案其他门均有的存量处置路径本门补齐）；批5 实施时以本会话清点结果为基线并复跑核验（固定首步重测口径，防清点与实施间漂移）；⑤历史 blob 不 rewrite、LFS 由 owner 单独裁决（OQ3）。
- **执行步骤**：1) 复跑存量清点（同口径）确认仍仅 census 一项，结果记入批说明；2) 消费者改写与测试调整（fresh checkout 语义验证）；3) path group 分类调整＋预览；4) git rm --cached＋.gitignore＋生成方落点；5) 大小门（带基线豁免清单）红先行自测（构造 >5MB tracked 文件应红；构造带豁免登记的 >5MB 文件应绿）。
- **验收门**：①`git ls-files script/scene_capability_census_snapshot.json` 输出为空；②相关消费者测试在无快照环境下绿（CI fresh checkout 即天然验证）；③编排器预览对该路径无 unmapped-change 阻塞；④大小门绿且红先行自测通过（含豁免通道自测）；⑤批5 提交不含清单外 script/ 文件（批次 diff 路径集 ⊆ owned 点名清单）。
- **退役/回退**：git rm --cached 可逆（重新 add 即恢复）；大小门阈值 owner 可调。
- **风险**：消费者改写遗漏致 CI 红——验收门②兜底；清点与实施之间新增大文件——步骤 1 复跑核验。

### 4.2 P1：权威文档标准、重门拆分、棘轮补位、巨文件第一步

#### P1-1 ｜大型权威文档四件套标准化（批9a/9b/9c 拆分）：锚点寻址＋顶部快照＋归档指针＋复核元数据
- **元信息**：文档｜L｜批9a/9b/9c（均治理临界区）｜批9a 前置批1；批9c 前置 OQ7 裁决｜Owner：仓库 owner；执行会话占 runtime-evidence-current.md、coverage-ledger.md、docs/history/、document-role-index schema、test_document_role_index
- **问题与证据**：前三大 md 文件占跟踪总量 58%【复核计算 5,100,651/8,844,776B】；coverage-ledger 67 个 H2 中 58 个是日期记录、0 锚点、无顶部快照【复核】；『## 1 当前证据快照』名不副实【复核】；S0-S5 定义埋在 625 行导语【复核】；超长单行 7108/6562 字节【复核】；runtime-architecture.md『最近复核：2026-09-15』【复核 :7】无机器门（复核戳陈旧为推断，标注）。
- **方案**：把证据页头部已自发实现的四件套【侦察 runtime-evidence-current.md:1-7＋279 锚点】立为大型权威文档标准，按失败半径拆三批：①批9a：runtime-evidence-current.md 顶部建真正独立短快照节（不含流水），S0-S5 表提为可链接小节，E-* 锚点寻址保持；②批9b：coverage-ledger 日期批次区滚动归档进 docs/history（遵守 AGENTS.md:21【复核】），顶部加快照、保留条目建锚点、超长单行拆行，『快照外保留条数/行数』入只降不升文档棘轮【调研·文档架构 practice 4】；③批9c（OQ7 裁决后另批）：role index 为 stable-contract 增 lastReviewed 必填元数据＋陈旧度断言【调研·文档架构 practice 2】——与文档手术分批，避免 schema 强制字段带未定取数逻辑上线。
- **执行步骤**：1) 批9a 证据页先行（自身即范本）；2) 全仓链接门；3) 批9b 保留判据直接采用 semantics/README.md:16 已有文本【复核】（仍改变 owner/route/失败半径/验证门/未决问题者留当前层）；4) 锚点迁移映射表防断链；5) 批9c 按裁决取数方案落地断言。
- **验收门**：①机器门：现役 >N 行（建议 600）权威文档必须含锚点＋归档指针＋快照节；②文档行数棘轮可 ratchet 下降且新增即红；③每批全仓链接门对新增/迁移锚点绿；④P0-1 分层表节名断言对改造后结构复跑绿；⑤批9c：lastReviewed 断言进测试且对陈旧戳红（红先行：临时改旧日期应红）。
- **退役/回退**：归档材料按 history 机制管理（不可取得现役角色【复核 docs/README.md:42】）；每批独立可 revert；批9c 独立回退不影响 9a/9b。
- **风险**：大文件手术伤锚点——映射表＋每批链接门；批9b 是全案最高风险文档手术，置于批9a 验证四件套门之后。

#### P1-2 ｜重门拆分：render-chain ratchet 与文档链接扫描独立成轻量 gate，inner 阶段可跑结构棘轮
- **元信息**：规则｜M｜批6（治理临界区）｜**开工前置**：test_scene_semantics_coverage 现存 3 个失败【侦察】已归因或相关并行改动已落批，否则批6 顺延——拆分是把红模块内容搬进新门，新门不能带红出生；与批3 同改 verify_scene_change.py 须串行｜Owner：仓库 owner；执行会话占 `script/tests/test_scene_semantics_coverage.py`、scene_validation_gates.json、verify_scene_change.py、script/ 新检查脚本（显式点名新路径）
- **问题与证据**：render_chain_authority_ratchet 37 条规则【复核 python3 计数 rules=37】的唯一执行者是 test_scene_semantics_coverage：单模块实测 141.7s、三职责混杂（全仓链接扫描＋目录布局契约＋ratchet）【侦察】，被 INNER_HEAVY_MODULES【复核 :24，注释写明成本动机 :21-23】排除出 inner；无独立 gate id 不进注册表【复核：9 门 keys 无对应条目】，与 scene-defense 严重不对称。
- **方案**：把 render-chain ratchet 与文档链接扫描拆为独立轻量检查并注册进 gates（带完整五字段元数据——注册表 schema 已强制【复核 :70-75】），使结构棘轮 inner 可跑；test_scene_semantics_coverage 保留目录布局契约或同样拆出；收缩 INNER_HEAVY_MODULES。拆分前先处置现存 3 个失败（归因进批说明或等并行改动落批）。
- **执行步骤**：1) 失败归因/落批确认；2) 拆链接扫描为独立检查脚本；3) 拆 ratchet 执行；4) 两新门注册＋path group 挂接；5) 计时进证据；6) INNER_HEAVY_MODULES 收缩。
- **验收门**：①注册表完备性测试（test_verify_scene_change.py:51-61 类【侦察】）自动覆盖两个新 gate；②新结构棘轮独立运行计时进证据（目标：141.7s 混合模块降为秒级~十秒级单项）；③INNER_HEAVY_MODULES 缩小且有测试断言锁定；④inner 预览（--phase inner --path script/scene_source_layout.json）计划含新结构棘轮门。
- **退役/回退**：拆分期保持 scene_source_layout.json 单一 JSON 源；回退＝恢复单一测试模块。
- **风险**：拆分后路径触发面需重新登记，漏登记由 unmapped-change 门【复核】兜住。

#### P1-3 ｜design-gate 补进门注册表元数据并对齐 inner 阶段触发语义，同时定义注册完备率口径
- **元信息**：规则｜**M**（OQ1 裁决＋可能的 AGENTS.md 措辞修订与 governance 逐字断言同步＋注册表补条目＋contentPatterns 收窄四件事耦合；收窄可经 owner 裁决拆为后续小批）｜批7（治理临界区）｜前置批6（同 JSON 串行）｜Owner：仓库 owner
- **问题与证据**：design-gate 缺席注册表【复核：'design-gate' in gates == False；:334/:350/:354 三处硬编码】，注册表完备性测试只迭代 gates 内条目【侦察】覆盖不到它；inner 阶段非 Swift Scene 产品路径不附加 design-gate——**真实 .metal 路径预览实测**【复核：`--phase inner --path MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneStaticModel.metal` 输出 groups: rendering，focused-tests（9 模块）＋scene-defense，无 design-gate、无 unmapped-change】；根因在 :351-352 elif 分支【复核】；AGENTS.md:18『产品路径变更时自动附加为 design-gate 门』【复核】无限定措辞与该行为不一致；design_gated_areas 全 approved、门零命中【侦察（18 区域时点）；现 19 区域【复核】】。**注册完备率口径缺口**：编排器还发出未注册 id——动态 `{test_scope}-tests`（:292-297）、repository-all-tests（:305-311）、unmapped-change（:427-437）【复核代码位置；发出 id 全集 12/注册 9 为审查实测】，M2 若按初稿口径会在本条落地后误报 100%。
- **方案**：①design-gate 补进 gates 注册表（含 retirement，零命中退役语义待 owner 定——OQ8）；②inner 阶段 Scene 产品路径（含非 Swift）统一附加 design-gate（倾向案，符合 :18 原文无限定语义），或按 owner 裁决修订 AGENTS.md:18/:34 措辞为『Swift 产品路径』（二选一，OQ1）；③**定义注册完备率口径**：动态名门（`{scope}-tests`）豁免，repository-all-tests 与 unmapped-change 要么注册要么进显式豁免清单（豁免须写 reason），M2 分母随之机器可数；④contentPatterns 收窄到声明文件类型——与触发面变化同步，或拆后续小批（owner 裁决）。
- **执行步骤**：1) OQ1 裁决；2) 注册表补条目＋豁免清单；3) 触发分支改或措辞改（措辞案须同步 test_scene_governance_contract 逐字断言【侦察 :237-267】）；4) 编排器测试新增（真实 .metal 路径 inner 预览含 design-gate 断言，或措辞修订后一致断言）；5) contentPatterns 收窄＋命中面回归（或拆小批）。
- **验收门**：①`python3 -B -c "import json; print('design-gate' in json.load(open('script/scene_validation_gates.json'))['gates'])"` 输出 True；②test_registry_requires_complete_lifecycle_metadata 通过并覆盖 design-gate；③上述 .metal inner 预览断言（或一致断言）通过；④完备率脚本/测试按新口径输出 100%（动态豁免与显式豁免清单生效）。
- **退役/回退**：注册条目带 retirement 即入退役管理；措辞修订属 AGENTS.md 收敛改写（:21 允许）。
- **风险**：触发面扩大误命中——与收窄同批或拆小批紧随；口径定义不当会漏掉未来新未注册门——完备率测试以『发出 id ⊆ 注册 ∪ 显式豁免』为断言形式。

#### P1-4 ｜源码形状断言棘轮（口径 v1＝声明关键字类）：43 文件/181 处先冻结只降不升，表达式类为已声明豁免边界、二期扩正则
- **元信息**：代码｜M｜批8（治理临界区：ratchet 注册触 gates）｜冻结先行零迁移；迁移按卡后续挂靠；表达式类扩正则属二期（OQ13）｜Owner：仓库 owner；涉及 Scene 产品域时对齐区域 owner；执行会话占 script/ 新基线与检查脚本（显式点名新路径）、编排器注册、首个示范组测试文件
- **问题与证据**：**冻结口径 v1（显式定义）**＝`assert(In|NotIn)\(.*"(func|let|var|struct|class|enum|case|guard|if) ` 即断言字符串以 Swift 声明关键字开头——**声明关键字类**源文本断言 43 文件 181 处【复核：`grep -rlE <口径 v1> script/tests/test_scene_*.py | wc -l`=43、-rn 计 181】；**表达式类**源文本断言不在口径 v1 内：本方案援引的示例 assertIn("slot.candidates.indices.reversed()", source) 实测存在但不被口径 v1 匹配【复核：该行存在=1、口径内命中=0；同文件声明类=23 处与侦察吻合】——初稿把 181 处笼统描述为『直接匹配 Swift 源文本』且验收门宣称无边界『新增即红』，口径失真（终审指出，本版修正）。两类均与 AGENTS.md:35【复核】冲突，该条款纯散文无执法。
- **方案**：①shape-assertion ratchet **按口径 v1** 建立：按文件计数入基线 JSON（模式仿 scene_defense_baseline 的 --accept-growth/--ratchet-baseline【侦察】），新增（口径 v1 内）即 gate 报错，挂 checkpoint（静态 grep 秒级）——与批2a 文档冻结基线同构；②**表达式类＝已声明豁免边界＋二期**：批8 附带一次表达式类规模普查（人工口径抽样，估计量级记入批说明，不做机器冻结——机械识别『任意表达式字符串 vs 合法断言值』误报率高），扩正则方案交 owner 二期裁决（OQ13）；**扩正则时基线须重新生成、计数一次性上调后冻结新基线**（防口径漂移虚降），并只许在 P2-5 节拍内下降；③存量迁移按触达族分组以 LSC 模式推进【调研·代码治理 practice 6】：每组同一变换规则＋机械门＋抽 1-2 文件完整行为迁移示范；④排序用红先行判据【调研·代码治理 practice 5】：故意改坏对应实现后仍绿的优先迁移。
- **执行步骤**：1) 口径 v1 正则与基线计数口径绑定写入检查脚本（口径变更即基线重生成）；2) 预跑生成基线（43/181 起点【复核】）；3) 表达式类规模普查记入批说明；4) 检查脚本挂 checkpoint；5) 首个示范组选 test_scene_resolved_material_runtime_bridge（声明类 23 处居首【复核】）抽 1-2 处做行为断言迁移。
- **验收门**：①ratchet 脚本＋基线进编排器注册（带 lifecycle 元数据），**口径 v1 内**新增形状断言即红（红先行自测：加一处声明类断言应红）；②基线记录 43 文件/181 处起点只降不升，且基线文件内嵌口径 v1 正则原文（口径与计数不可分离）；③表达式类普查结果记入批说明（豁免边界显式化）；④首批示范：一处源文本断言换为行为断言，且故意改坏对应实现时新断言能红（演示进证据）。
- **退役/回退**：基线归零后转为『禁止任何新增』绝对门；二期扩正则由 OQ13 裁决后另批实施；回退＝删基线（不推荐，等于放弃 AGENTS.md:35 执法）。
- **风险**：口径 v1 覆盖不全——豁免边界已显式声明并普查留档，二期扩正则收口（OQ13）；不追求一批清零（Packwerk 教训【调研】）；行为断言迁移防『高覆盖零断言』注水【调研 caveats】。

#### P1-5 ｜顶格巨文件第一步：renderFrame 按 defer/阶段边界提取私有 stage 方法（显式设计前置）
- **元信息**：代码｜M｜**批11（治理临界区：触 code_health_baseline.json——§5.1 判据已补入此文件，批11 入全集；终审修正三处对齐）**｜**开工前置**：OQ2 裁决＋区域设计前置（见方案②）；建议批12 落地后复跑验证｜Owner：仓库 owner；区域 owner＝design_gated_areas『SceneDesktopWallpaperHost / SceneMetalView / SceneMetalRenderer』（对应区域条目 id=scene-frame-admission-retry，designDoc=`docs/scene/design/frame-admission-retry-design.md`【复核】；**另注**：SceneMetalRenderer.swift 同时出现在另两条 approved 区域 matchPatterns（scene-debug-frame-capture-lifecycle、scene-persistent-color-output）【复核】，批说明须确认 stage 提取不触及两条合同边界）；执行会话占 `MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer.swift`、`MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapabilityVariant+Compilation.swift`、`script/code_health_baseline.json`、`docs/scene/design/frame-admission-retry-design.md`
- **问题与证据**：两文件均恰好 1000 行【复核 wc】；`script/code_health_baseline.json` 为 reviewLineLimit=400/hardLineLimit=1000【复核 Read :3-4】，其 notes.pendingSceneRegistration 记录 2026-09-30 实测两文件为 943/997 行【复核 :26】——现已双双 1000【复核】，顶格属实且仍在增长（佐证 OQ2 存疑）；renderFrame 为全文唯一函数（约 :47 起【侦察】，`grep -c 'func '`=1【复核】），单函数贯穿纹理帧/粒子提交/深度租约/effect 证据/compositor seal 五类职责【侦察】；同目录已有 19 个 SceneMetalRenderer+Extension 拆分文件【侦察】，扩展拆分是既有惯例；>800 行文件 21 个、超 review 限 237 个仅 warning【侦察】。
- **方案**：①按 renderFrame 内既有 defer/阶段边界提取私有 stage 方法（或循既有 +Extension 惯例——按区域设计裁决），把两个顶格文件降到硬限之下；**defer 块跨函数边界会改变作用域：defer 必须随所属 stage 整体迁移而非按行切**；stage 提取新增签名/参数行，预计需动用『分两批』fallback；②**显式设计前置**：renderFrame 横切五类职责命中 AGENTS.md:18 判定程序①『横切多个 owner 或主链节点』【复核】，所属区域已登记——批11 开工前批说明必须引用 `docs/scene/design/frame-admission-retry-design.md` 或先补『stage 提取边界＝纯结构移动、不改表达式语义』的设计裁决段；③不改视觉语义、不顺手裁决算法（AGENTS.md §3【复核】）；code-health 基线随批收紧。
- **执行步骤**：1) OQ2＋设计前置落批说明；2) 通读 renderFrame 标注天然阶段边界（defer 块归属、提交序列）；3) 每阶段提为私有方法，纯结构移动，defer 随迁；4) code-health 复跑；5) checkpoint Debug build＋指定行为门；6) 边界不清晰时缩小步子分两批（每批一个可见降行结果）。
- **验收门**：①`python3 script/check_code_health.py` 0 error 且两文件 <1000 行；②checkpoint Debug build（run_checkpoint_build.sh）通过；③**行为判据**：指定行为门清单（rendering/frame 相关既有行为门）绿，且对 1-2 个关键 stage 做改坏演示（故意破坏 stage 内一处逻辑，对应行为门红——红先行），证明提取后行为断言仍有效；④code-health 基线随批收紧。
- **退役/回退**：纯结构移动，git revert 即回退；不与视觉语义变更混批。
- **风险**：巨函数提取回归——行为门＋隔离 checkpoint 构建＋改坏演示兜底；本条只处理两个顶格文件，其余超限文件进 P2-5 队列排序。

#### P1-6 ｜Scene 子树根增嵌套指针型 AGENTS.md：从任意源码文件一跳到达权威入口
- **元信息**：Agent 体验｜S｜批10（治理临界区：占 test_document_role_index）｜OQ4 裁决后执行；须与批1/2/9a/9b/9c 错开（同文件）｜Owner：仓库 owner；执行会话占 `MyWallpaperX/Core/SteamWorkshopScene/AGENTS.md`（新建指针桩）、test_document_role_index
- **问题与证据**：Scene 核心 184,321 行 Swift/692 文件【侦察】独占单树而无就近入口：全仓当前仅根 AGENTS.md 一个【复核：`find . -name 'AGENTS.md' -not -path './.git/*'` 仅 ./AGENTS.md】；Agent 落在子树任意文件时导航链为 SKILL.md(109 行【复核】)→根 AGENTS.md(38 行【复核】)→docs/README 角色表→scene/README→合同文档四跳【侦察】。**可行性已核实**【复核】：布局契约测试只走 *.swift（test_scene_semantics_coverage.py:291-295 断言子树根无 Swift 文件、:308 rglob('*.swift')），子树已存在非 Swift tracked 文件（.metal、QuickJSNG LICENSE/README.md/.c/.h【复核 git ls-files】）——嵌套 AGENTS.md 不需要动 scene_source_layout.json。此条为研究惯例建议非侦察缺口【调研·Agent 协作 practice 3、文档架构 practice 6、标杆 practice 1 一致推荐：closest-wins、≤32KiB、防规则下沉 caveat】。
- **方案**：在 MyWallpaperX/Core/SteamWorkshopScene/ 放 5-10 行纯指针 AGENTS.md（入口文档、门禁命令、硬边界条款号指针——如『Scene 硬边界见根 AGENTS.md §3』），零新规则；机器门断言嵌套 AGENTS.md 每行为链接或一句话指针、≤10 行、不复制根文件条款。
- **执行步骤**：1) OQ4 裁决（指针桩 vs 目录 README 指针降级案）；2) 写桩；3) test_document_role_index 增形状断言；4) 桩纳入登记（指针类条目）。
- **验收门**：①断言嵌套文件 ≤10 行且为指针形状；②断言根文件条款文本不出现在嵌套桩（防规则下沉）；③桩内链接全绿（全仓链接门）。形状断言对象是文档文件，不与 AGENTS.md:35（限定产品代码测试【复核】）冲突。
- **退役/回退**：删桩即回退。
- **风险**：规则下沉漂移——机器门钉住形状；与 AGENTS.md:21 删除方向条款的相容性见 OQ4。

#### P1-7 ｜checkpoint 构建缓存复用：固定 module cache 目录把全量冷构建降为半增量
- **元信息**：流程｜M｜批12（独立批，owned paths 仅 run_checkpoint_build.sh——与批5 点名清单不相交）｜无前置；**批5 在飞期间不得插入**（§5.1）｜Owner：仓库 owner
- **问题与证据**：run_checkpoint_build.sh 每次第 48 行 `mktemp -d /private/tmp/mywallpaperx-checkpoint-build.XXXXXX` 全新 DerivedData【复核 Read＋二审 sed -n '48p' 同】，50-56 行 xcodebuild Debug 全量、退出即删（9-19 行 trap）【复核】，无跨运行模块缓存复用；全局锁 owner 存在时 exit 2（32-35 行【复核】）使并行会话排队；CI 显式设固定 CLANG/SWIFT_MODULE_CACHE_PATH 对照【侦察 ci.yml:70-71】；冷构建绝对时长未实测（只读禁构建）——收益为推断，标注。
- **方案**：SWIFT/CLANG module cache 指向固定可复用目录（按会话或分支 key 隔离防污染），保留临时 DerivedData 自清理与活锁锁语义不变；**固定缓存目录的生命周期策略显式写进批说明**（依赖 /private/tmp 的 OS 级定期清理属可接受方案，但须声明而非默认）；前后构建时长写入本机证据缓存作收益证据。
- **执行步骤**：1) **先实测冷构建基线**（改脚本前跑两次当前脚本计时，为 M6 补对照数字）；2) 定 cache 目录与 key 方案；3) 改脚本（仅注入两个环境变量，隔离/清理/锁逻辑零改动）；4) 同系列两次构建计时进证据；5) 收益不显著（阈值 owner 定，建议 <20%）如实报告并回退。
- **验收门**：①M6 冷构建基线数字实测进证据（步骤 1 产物）；②第二次构建时长显著下降（数字进证据与批次报告）；③锁/清理/活锁语义不回退（dry-run 或脚本测试断言：锁占用 exit 2、退出清理 DerivedData）。
- **退役/回退**：删两行环境变量注入即回退；收益未量化前不宣称完成。
- **风险**：缓存跨会话/跨分支污染——key 隔离；/private/tmp 清理导致缓存失效属预期（回退为冷构建，无 correctness 风险）。

### 4.3 P2：结构收尾、提交辅助、债务节拍（按价值序）

#### P2-2 ｜App 层职责分离：21 个 Debug runner 移入 App/Debug 子目录
- **元信息**：结构｜S｜批13（治理临界区：patterns 登记）｜Owner：仓库 owner；执行会话占 `MyWallpaperX/App/`、scene_validation_gates patterns
- **问题与证据**：App/ 35 个平铺文件中 21 个（60%）是 Debug 前缀 runner/诊断工具【复核：`ls MyWallpaperX/App | grep -c '^Debug'`=21、总数 35——该命令在**现状**下有效；移动后因新建 Debug/ 目录本身会被同命令误计，验收须用下述新命令（终审指出，/private/tmp 模拟实测：旧命令移动后=1、新命令=0【复核】）】；工程为 PBXFileSystemSynchronizedRootGroup（5 处【侦察】），移动目录即编译生效。注意 SCENE_PRODUCT_PATTERNS 已含 `MyWallpaperX/App/DebugScenePlaybackRunner*.swift`【复核 :27】，移动后须同步。
- **方案**：21 个 Debug* 移入 App/Debug/（目录本身是交付物，出现在 `ls MyWallpaperX/App` 属预期）；新路径同步登记 patterns 防 unmapped-change 阻塞；实施前 grep 脚本/测试对旧路径的引用（侦察未覆盖，实施前置核对，OQ5）。
- **执行步骤**：1) `grep -rn 'App/Debug' script/ docs/ .github/` 核对引用面；2) git mv；3) patterns 与 SCENE_PRODUCT_PATTERNS 同步；4) checkpoint Debug build 验证。
- **验收门**：①**`find MyWallpaperX/App -maxdepth 1 -name 'Debug*.swift' | wc -l` = 0**（App 顶层不再有 Debug 前缀 Swift 文件；等效可用 `ls MyWallpaperX/App | grep -c '^Debug.*\.swift'`=0——两者模拟实测均为 0【复核】）；②编排器对新路径（App/Debug/**）不报 unmapped-change（预览断言）；③checkpoint Debug build 通过。
- **退役/回退**：git mv 回即可；按 owned paths 一批完成。
- **风险**：外部脚本按旧路径引用——先核对再移动。

#### P2-3 ｜Format/Diagnostics 纳入布局契约：自引用二级清单使 43 个平铺文件受 file_globs 门禁
- **元信息**：结构｜S｜批14（治理临界区）｜Owner：仓库 owner；执行会话占 `script/scene_source_layout.json`
- **问题与证据**：Format（31 文件）与 Diagnostics（12 文件）【复核 find 计数】是仅有的两个无二级分层的平铺顶层目录，不在 declared_second_level_directories 内【侦察 Python 校验】，43 个文件不受 file_globs 逐文件契约约束——**schema 兼容性已核实**【复核】：布局测试对 depth-2 文件显式跳过契约（test_scene_semantics_coverage.py:311-312 `if len(relative.parts) == 2: continue`），自引用二级键＋全量 file_globs 可直接落进 declared_second_level_directories 既有结构（:305/:319）。
- **方案**：为两目录增加自引用二级契约（目录名即键＋file_globs 列现有全部文件＋responsibility 补写），纳入同一布局测试；属 inventory 冻结而非家族增长，批说明显式声明（先例：分析器家族 123 成员 inventory【侦察 scene_source_layout.json:1217】）。
- **执行步骤**：1) 生成两目录文件清单入 JSON；2) responsibility 各一句；3) 布局契约测试双向校验；4) 新增文件必须显式改基线才可入库。
- **验收门**：布局契约测试对两目录『实际文件＝声明 glob』双向一致（0 漂移）；人为新增未声明文件时红（红先行自测）。
- **退役/回退**：删两键即回现状（不推荐）；inventory 语义与退役条件（两目录二级化时该键退役）由 owner 认可（OQ9）。
- **风险**：低；与批6 拆分后的布局门同源 JSON，无双读。

#### P2-1 ｜本机生成物收敛与证据缓存清点
- **元信息**：结构｜S｜批15（独立批；删除动作需 owner 按清单确认；**批5 在飞期间不得插入——§5.1 附加排程规则已同步列名批15，批说明与 §5.1 一致（终审修正三处对齐）**）｜Owner：仓库 owner；执行会话占仓库外目录与精确清单文件
- **问题与证据**：mimosa 扫描会话状态目录散布产品源码树与 SceneStockAssets.bundle 内部 7 处【复核：`find MyWallpaperX -name '.mimosa' | wc -l`=7】；.gitignore:59 已忽略、无追踪【侦察】；script/ 与 evidence/ 另有 __pycache__ 65 项与 137KB .DS_Store【侦察】；本机 evidence 缓存 349 目录/16GB【侦察】此前无任何管理条目，而 P0-5 还要向其新增 census 快照落点。
- **方案**：①mimosa 扫描统一 outputDir 到仓库外（工具默认 ~/.mimosa）；既有 7 处确认非活动状态后按精确清单删除（AGENTS.md:10【复核】）；②__pycache__/.DS_Store 按精确清单处理，禁止递归清理；③**证据缓存容量清点与可清项提案**：对 docs/scene/evidence/ 做容量清点（含 P0-5 快照新落点），列出可重建/可清理候选——**只提案不删除**，删除仍按精确清单＋owner 确认。
- **执行步骤**：1) 确认无活动扫描；2) 列精确清单交 owner 确认；3) 逐项删除；4) mimosa 调用统一 outputDir；5) 证据缓存清点报告＋可清项提案（单独交 owner）。
- **验收门**：①`find MyWallpaperX -name '.mimosa' | wc -l` = 0；②.gitignore 覆盖不变；③生成物按精确清单归零（清单进批次报告）；④清点报告产出（删除与否由 owner 另行裁决）。
- **退役/回退**：删除的是可重建状态，无需回退通道；防线是『先确认后删除』。
- **风险**：丢失活动扫描状态——非扫描期执行＋owner 确认双保险；批5 并行会改 .gitignore 与 evidence 落点、扰动清点基准——以批5 不在飞为排程前提。

#### P2-4 ｜提交期轻量机械辅助：秒级 JSON 对账＋owned paths 核对＋area trailer 约定
- **元信息**：流程｜M｜批16（治理临界区：对账项若注册进门）｜Owner：仓库 owner；执行会话占 script/ 新提示脚本（显式点名新路径）、development-workflow.md、（可选）release 脚本约定
- **问题与证据**：工作区安全与提交纪律条款完全无机器防护【侦察 grep 零命中；复核 .git/hooks 全 *.sample、hooksPath 空】；80 条提交中 6 条多职责标题、674feadc 标题与实际 diff 不符【侦察】。**git hooks 为仓库级共享**：任一会话安装后所有并行会话的提交都过该钩子（审查指出；属 git 机制，本会话未实测安装行为）。
- **方案**：①可选 pre-commit 提示脚本：核对暂存路径与批次 owned paths 声明一致＋秒级 JSON 基线对账——仅秒级确定性检查，构建/测试绝不进钩子【调研·标杆 practice 5 caveat】；仓库级共享影响如实写入安装说明，或由 owner 裁决会话级 hooksPath 方案（OQ11）；②提交信息 area trailer 约定供 publish_release.py 机械生成更新日志（是否消费由 owner 定）；③显式安装脚本启用。
- **执行步骤**：1) 写提示脚本（默认只提示不阻断，--strict 可选阻断）；2) dry-run 测试；3) 钩子单次运行实测计时；4) trailer 约定写入 development-workflow.md；5) 安装脚本＋共享影响说明。
- **验收门**：①dry-run 测试断言警告/通过输出；②钩子单次运行实测 <2s（计时进证据）；③trailer 约定写入且 publish_release.py 可解析；④安装说明含仓库级共享影响声明（或按 OQ11 采用会话级方案）。
- **退役/回退**：卸载脚本一步回退；git 破坏性操作无对应 hook 事件，此条只能覆盖暂存面——如实声明边界，不宣称替代 AGENTS.md §1。
- **风险**：钩子拖慢提交——严格秒级＋实测计时；提示不阻断降低对并行会话干扰。

#### P2-5 ｜冻结面的偿还队列：分级债务队列与清偿节拍（含超限文件与 Compilation 聚集域）
- **元信息**：流程｜M｜批17（基本独立；若清点打印改 .github 则并入治理临界区；**批5 在飞期间不得插入**——队列 JSON 落 script/，虽与批5 点名清单不相交，但 P0-4 未落地前全量收集会吸入）｜Owner：仓库 owner；候选项涉及 Scene 产品域时对齐区域 owner；执行会话占 script/ 新队列生成脚本与队列 JSON（显式点名新路径）
- **问题与证据**：棘轮执法完备但清偿无节拍：defense 基线 18 个 canonicalHelpers 与 13 条 acknowledgedChanges、layout 冻结 123 个分析器成员、**237 个超 review 限文件（含 Compilation 243 文件聚集域的超限成员）**均无排序【侦察】；Packwerk todo 滞留数年教训【调研·代码治理 practice 1】；VectorConversion 近同义对 780/785 行【侦察】等具体候选无排序【调研·标杆 practice 4】。**文档登记冻结基线（批2a 产物：31 份未标记）与形状断言表达式类豁免边界（P1-4 二期，OQ13）亦入队**——三份权威已在批2a 清偿，余项随批2b/豁免裁决/二期扩正则清偿。
- **方案**：为冻结家族/防御面/超限文件/文档登记缺口建机器可排序偿还队列（S-actionable 分级＋难度＋触达族；VectorConversion 近同义对、Compilation 超限成员等候选入队）；队列以 JSON/脚本形态存在于 script/（非 docs/）；每 E 卡/批次关闭时机械清点未下降项并写原因，把『收缩随卡关闭同批 ratchet 下降』（AGENTS.md:20【复核】）变成机械节拍；--drop-unused-acknowledgements（工具已有【侦察】）变为固定节拍执行。Compilation 聚集域的整体处置是 OQ10 owner 裁决点，队列先收其超限文件维度。
- **执行步骤**：1) 队列生成脚本从三份基线 JSON＋code-health 输出＋批2a 文档冻结基线机器生成（不手写）；2) 分级字段（actionable/difficulty/family）；3) 批次收尾清点钩子；4) CI 或 checkpoint 打印未清偿计数。
- **验收门**：①队列存在于 script/ 且为机器生成；②未清偿计数有只降不升断言；③批终审逐条核对新增项；④连续两个批次未下降项均有原因记录（抽样复核）。
- **退役/回退**：队列只作索引不作权威（权威仍是基线 JSON）；删脚本零影响基线。
- **风险**：队列腐化——机器生成、只作索引；计数下降仍须绑定回放验证梯级（零违例≠能运行【调研】）。

#### P2-6 ｜依赖方向机器断言：把 layout responsibility 文字升级为可检验跨目录引用边＋todo 棘轮
- **元信息**：代码｜L｜批18（治理临界区）｜前置批6（复用独立 gate 注册模式）｜Owner：仓库 owner；试点边涉及区域 owner 对齐；执行会话占 scene_source_layout.json（或旁挂单一源 JSON）、script/ 新扫描脚本（显式点名新路径）、todo 基线
- **问题与证据**：scene_source_layout.json 各目录 responsibility（如 Graph 的 no frame submission ownership【侦察 :24/:107/:299 等】）只是文字，跨目录引用方向无机器断言；Compilation(243 文件)←Rendering←Systems 单向性靠纪律维持【侦察】。
- **方案**：把顶层目录间单向链与 Resources 被依赖位置声明为可检验边；词法扫描跨目录类型引用（复用 check_scene_defense 基建与 --accept-growth/--ratchet-baseline 模式【侦察】）；存量违例进 Packwerk 风格 todo 棘轮只许收缩；不做 public/private API 面（Packwerk 教训【调研】）；扫描语料并入 script/tests 内嵌 Swift harness 片段（教训：26 候选中 21 个被 harness 引用【调研引 engine-refactor-program.md:228】）；先单边试点（建议『Rendering 不引用 Compilation 内部类型』）再扩全图。
- **执行步骤**：1) 边声明进单一 JSON 源；2) 词法扫描脚本（试点一边）；3) 预跑存量违例入 todo 基线；4) 注册进编排器带 lifecycle 元数据；5) 试点收益 owner 验收后决定扩图。
- **验收门**：①新检查＋todo 基线注册进编排器（完备性测试覆盖）；②存量违例数进基线；③新增违例 CI 红（红先行自测）；④试点边报告进证据。
- **退役/回退**：todo 归零后转绝对门；试点误报率高则收缩边范围或退役（retirement 字段写明）。
- **风险**：词法扫描盲区——定位为结构信号非运行证明；L 工作量，试点后再扩。

## 5. 分阶段路线图与依赖

### 5.1 治理临界区（严格串行）与独立批

排序总则（AGENTS.md:37【复核】）：每批开工 `git status --short --branch --untracked-files=all` 划 owned paths（AGENTS.md:7【复核】）；**owned paths 一律点名到文件，不声明整目录所有权**（P0-5 修正立此规矩）。

**治理临界区批次全集**（判据：触达 scene_validation_gates.json、verify_scene_change.py、test_verify_scene_change.py、scene_source_layout.json、**code_health_baseline.json（终审补入，批11 据此入集）**、document-role-index.json、test_document_role_index.py、AGENTS.md 之一）：**批1、2a、2b、3、4a、4b、5、6、7、8、9a、9b、9c、10、11、13、14、16、18——彼此严格串行，禁止并行排程**（批11 原三处矛盾已对齐：元信息、本判据、全集一致）。同文件对显式登记：批2a×批2b（role index＋test）、批2a×批3（verify_scene_change.py＋test_document_role_index）、批3×批6（verify_scene_change.py）、批6×批7（gates JSON）、批9a/9b/9c×批1/批10（test_document_role_index）、批11×批8（均触治理 JSON，按全集串行覆盖）。

**可按价值插入的独立批**（owned paths 与一切在飞批次完全不相交，**以点名清单为判据**）：批12（P1-7，仅 run_checkpoint_build.sh）、批15（P2-1，仓库外目录＋精确清单；其 evidence 清点只读）、批17（P2-5，新队列 JSON＋只读三基线；若清点打印改 .github 则并入临界区）。**附加排程规则（终审三处对齐）**：批5 在飞期间，**批12、批15、批17** 均不得插入（P0-4 未落地前 changed_paths 全量收集【复核 :82-97】会把批12 的脚本改动、批15 的清单新文件与批17 的队列新文件吸进批5 的门禁计划；批15 另受『批5 改 .gitignore 与 evidence 落点扰动清点基准』约束）。

**每个触达治理 JSON 批次的固定首步**：重测治理计数并记入批次报告（现状基线【复核】：path_groups 64、role index documents 67、gated areas 19、script/ tracked >5MB 文件数 1；侦察时 63/65/18——漂移常态化，以开工时实测为准）。

### 5.2 批次表

| 批 | 条目 | 前置 | 可见结果 | 关键验证 |
|---|---|---|---|---|
| 1 | P0-1 | 无（临界区） | 导航指引与文件实际结构一致 | 角色索引测试＋链接门 |
| 2a | P0-3 冻结＋三份 | 批1 串行 | 新增即红＋31 份冻结基线＋三份权威入索引 | 发现断言红先行＋基线 31→28 |
| 2b | P0-3 补全集/豁免 | 批2a＋OQ12 | 28 份按豁免类清偿或登记 | 豁免外 100%＋entrypoint 测试绿 |
| 3 | P0-4 | 批2a 串行 | owned-only 圈定＋排除清单可见 | 编排器新用例＋预览 |
| 4a | P0-2 建表 | 批2a＋OQ6 硬前置 | 路由表 --query 一跳命中（只增不删） | 互检＋完备触发＋三任务 --query |
| 4b | P0-2 去重 | 批4a 覆盖面 owner 验收 | 三份文本指针化、重复映射消除 | role index 全测＋entrypoint 测试＋链接门 |
| 5 | P0-5 | 无（临界区；点名清单纪律） | census 出库＋消费者处置＋大小门（带存量冻结） | ls-files 空＋fresh checkout 绿＋存量清点进批说明＋diff⊆清单 |
| 6 | P1-2 | 现存 3 失败归因/落批；批3 串行 | 结构棘轮 inner 可跑 | 注册表测试＋计时 |
| 7 | P1-3 | 批6＋OQ1 | design-gate 入注册表＋完备率口径 | gates 含 design-gate＋.metal 预览断言 |
| 8 | P1-4 | 无（临界区） | 口径 v1 冻结＋表达式类普查＋首批示范 | 口径内新增即红＋基线内嵌口径 |
| 9a | P1-1 证据页 | 批1 | 真快照节＋S0-S5 可链接 | 链接门＋四件套门 |
| 9b | P1-1 台账 | 批9a | 台账归档＋锚点＋文档棘轮 | 链接门＋棘轮 |
| 9c | P1-1 复核元数据 | 批9b＋OQ7 | lastReviewed 必填＋陈旧度断言 | 陈旧戳红先行 |
| 10 | P1-6 | OQ4；与批1/2/9 错开 | Scene 子树一跳入口 | 桩形状断言 |
| 11 | P1-5 | **临界区**；OQ2＋设计前置；批12 后复跑 | 两文件 <1000 行 | code-health＋checkpoint build＋改坏演示 |
| 12 | P1-7 | 无（独立；批5 在飞时禁插） | 冷构建基线＋第二次构建提速实测 | 步骤1 基线＋计时＋锁语义断言 |
| 13 | P2-2 | 无（临界区） | App/Debug 分层 | **find -maxdepth 1 计数 0**＋checkpoint build |
| 14 | P2-3 | 批6 衔接 | Format/Diagnostics 入契约 | 布局双向一致 |
| 15 | P2-1 | owner 清单确认；**批5 在飞时禁插** | 生成物归零＋缓存清点报告 | find 计数 0＋清点报告 |
| 16 | P2-4 | OQ11（或批内声明共享） | 提交期辅助可用 | dry-run＋计时 |
| 17 | P2-5 | 无（基本独立；批5 在飞时禁插） | 债务队列＋清点节拍 | 只降不升断言 |
| 18 | P2-6 | 批6 | 依赖边试点 | 新增违例红 |
| 19 | 终批复评 | 全部落地后 | M1-M8 机器输出汇总（方案完成判据） | --query 三任务、完备率、marker 覆盖、INNER_HEAVY、大小门、构建计时、队列计数、链接门 |

### 5.3 裁决点→批次对照（单人 owner 批阅视图）

| 裁决点 | 批次 | 性质 |
|---|---|---|
| OQ12 登记全集 vs 豁免类划分 | 批2b | 硬前置 |
| OQ6 路由表任务键＋术语键 | 批4a | 硬前置 |
| OQ1 design-gate 措辞/触发二选一；OQ8 零命中退役语义 | 批7 | 硬前置 |
| OQ3 census 消费者处置方案/LFS/历史 blob | 批5 | 前置（消费者已定位） |
| 批6 现存失败归因确认 | 批6 | 开工条件 |
| OQ2 1000 行上限动机 | 批11 | 开工前 |
| OQ7 lastReviewed 取数来源 | 批9c | 硬前置 |
| OQ4 嵌套桩相容性 | 批10 | 硬前置 |
| OQ5 Debug runner 引用面 | 批13 | 实施时核对 |
| OQ9 inventory 冻结口径 | 批14 | 批说明认可 |
| OQ13 表达式类源文本断言二期扩正则 | 批8 普查→二期批 | 批8 留档，扩正则另批 |
| P1-7 提速阈值＋缓存生命周期策略 | 批12 | 批说明认可 |
| OQ11 hooks 仓库级/会话级 | 批16 | 硬前置（或批内声明） |
| OQ10 Compilation 聚集处置 | 批17（或显式接受） | 队列收录口径 |
| P2-1 删除清单＋缓存可清项 | 批15 | 删除前置 |

## 6. 保持不动清单及理由

1. **AGENTS.md 38 行纯长期约束定位**【复核 wc -l】：符合最小高信号纪律【调研·Agent 协作 practice 1】；只允许收敛改写（P1-3 措辞案、P0-2 指针行均属此类），不允许追加。
2. **门禁编排器 verify_scene_change.py＋scene_validation_gates.json 注册表＋unmapped-change 强制映射门**（64 path group【复核】/383 module 引用【侦察】；编排器自身 1058 行测试治理【侦察】；unmapped 兜底【复核 :427-437】）：改良只在注册表内补条目与拆分重模块（P1-2/P1-3），不改架构。
3. **三条棘轮基线与显式改基线通道**（--accept-growth --reason 台账、acknowledgedChanges 逐条记录【侦察】）：符合『只许说明退役理由后下降』【复核 AGENTS.md:20/:34】，机制不变，只补清偿节拍（P2-5）；P0-5 大小门沿用同一基线豁免通道（终审补齐存量冻结条款）。
4. **scene_source_layout.json 布局契约与命名纪律**（692/692 Scene 前缀、禁 Common/Helpers/Misc、双向校验、responsibility 逐目录声明【侦察】）：只做增量纳入（P2-3）与责任升级试点（P2-6），不重排目录。**Compilation 家族聚集（243 文件/81,494 行【侦察】）现状处置＝接受并按 P2-5 队列偿还其超限维度，或显式接受现状——owner 裁决点 OQ10**，本方案不新增重组条目。
5. **发布自动化 publish_release.py**（一条命令端到端＋双向核对＋并行改动显式拒绝【侦察】）**与 run_checkpoint_build.sh 的隔离/自清理/活锁锁语义**【复核】：P1-7 只加缓存复用不改隔离语义；发布任务的首跳命中由 P0-2 路由键覆盖（批4a），发布链本身不动。
6. **测试行为对拍基建与 mywallpaperx-maintainer SKILL 路由层**（109 行纯路由【复核】、经 harness 自动可见【侦察】）：**『保持』指 109 行纯路由、纯指针的形态，而非内容永久冻结**——批4a 允许各加一行指针；批4b 经验收后才可去重；scene-engine.md 在批4b 前保持 harness 注入的最小预置知识面（Agent 未读仓库前的基本路由能力），避免指针化反而多一跳。
7. **文档角色索引机制本身**（document-role-index＋13 项测试【侦察】＋全仓链接门【侦察】）：只扩发现域冻结与触发回归锁定（P0-3），不引第二套治理。
8. **证据页头部阅读契约＋E-* 锚点寻址模式**（runtime-evidence-current.md:1-7＋279 锚点【侦察】）：作为 P1-1 推广播范本；『## 1 快照名不副实』是标签问题而非模式问题。
9. **提交信息四要素文化**（67/80 带正文【侦察】）：P2-4 只加机械提示，不改四要素约定。
10. **本机 evidence 缓存的内容治理不属仓库治理范围**（AGENTS.md:38 定位为仓库忽略的本机证据缓存【复核】）——本方案只做容量清点与可清项提案（P2-1 步骤⑤），不做内容级管理条目。

## 7. 风险与回退

| 风险 | 涉及 | 缓解 | 回退 |
|---|---|---|---|
| 并行会话在治理临界区冲突 | §5.1 全集批次（含批11） | 临界区批次严格串行＋开工 git status 划 owned paths＋点名清单纪律＋固定首步重测计数；P0-4 落地后机器隔离 | 各批独立 revert |
| 批5 目录级 owned paths 吸入他批改动 | P0-5/批12/批15/批17 | owned paths 点名到文件＋批5 在飞禁插批12/批15/批17＋验收门⑤ diff⊆清单 | 摘除误入文件重新提交 |
| 大文件手术伤锚点 | P1-1 | 锚点映射表＋每批链接门；批9a 先行、批9b/9c 拆分缩失败半径 | 分批 revert |
| 路由表过渡期覆盖不足 | P0-2 | 批4a 只增不删（通用角色表保留为枢纽）；覆盖达标后才批4b 去重 | 批4a 独立 revert |
| 路由表自身漂移成第二权威/失完备 | P0-2 | 单一 JSON 源＋互检＋stable-contract 新登记必须进任务键或显式豁免（完备触发） | 删表恢复指针 |
| 批2a 冻结基线漏登/批2b 豁免错分 | P0-3 | 基线机器生成自 git ls-files＋grep；豁免须对应 OQ12 裁决记录且可审计 | 基线可重生成；豁免可撤销 |
| 形状断言口径覆盖不全 | P1-4 | 口径 v1 显式声明＋基线内嵌正则；表达式类普查留档为已声明豁免边界；二期扩正则时基线重生成防虚降（OQ13） | 二期收口 |
| 大小门存量违例处置缺位 | P0-5 | 存量清点已跑（>5MB 仅 census【复核】）＋实施时复跑＋基线豁免清单通道 | 豁免可撤销 |
| 执法触发面扩大误命中 | P1-3、P0-3 | contentPatterns 收窄同批或拆小批紧随；默认行为不变 | 收回触发分支 |
| owned-only 圈定漏真实耦合/静默漏门 | P0-4 | 默认全量不变；排除路径清单强制可见（预览＋批次报告） | 停用参数 |
| 巨函数提取回归 | P1-5 | 纯结构移动＋defer 随迁＋行为门＋隔离构建＋改坏演示；必要时分两批 | git revert |
| 新门带红出生 | P1-2 | 开工前置：现存 3 失败归因或并行改动落批，否则顺延 | 顺延/恢复单模块 |
| census 消费者破坏/CI 红 | P0-5 | 消费者已定位并纳入正文；fresh checkout 验收兜底 | 重新 git add |
| 钩子拖慢提交＋仓库级共享影响 | P2-4 | 严格秒级＋实测计时＋默认提示不阻断＋共享影响如实声明（或 OQ11 会话级） | 卸载脚本 |
| 缓存跨会话/分支污染 | P1-7 | key 隔离；先测基线再改；不显著如实回退 | 删环境变量注入 |
| 队列/索引腐化 | P2-5、P0-2 | 机器生成、只作索引；权威仍是基线 JSON | 删索引脚本 |
| 词法扫描盲区误判 | P2-6 | 结构信号定位；单边试点后再扩 | 收缩/退役检查 |
| 删除类操作误删 | P2-1 | 精确清单＋owner 确认双保险（AGENTS.md:10【复核】）；缓存只提案不删 | 不执行 |

全局回退策略：全部条目均为增量、无破坏性 git 操作、不 rewrite 历史；均可独立 `git revert`；唯一接近不可逆的是 P2-1 按清单删除（先确认后执行硬前置）与 P0-5 `git rm --cached`（可重新 add 恢复）。

## 8. 成效度量

| # | 度量 | 基线（证据） | 目标 | 出处 |
|---|---|---|---|---|
| M1 | Agent 定位事实的路径长度 | 『修复 Scene 视觉缺陷』：需沿四层入口链拼装台账＋设计合同＋验证门（分散三处【复核】）；『发布新版本』：release-signing 链可达但门禁组合无单点；『sampler 合同』：四层导航 0 引用【复核 exit 1】 | 三任务 --query 一步返回必读清单＋gate 组合；设计合同 ≤1 跳；台账先读快照节（≤150 行建议值） | P0-2/P1-1 |
| M2 | 门禁注册完备率 | 分母＝编排器实际发出 gate id 集合（机器可数；现状 12 发出/9 注册【审查实测；三处未注册发出点代码位置本会话复核】） | 口径定义后 100%（design-gate 等真实执行门全部注册；动态门豁免、兜底门注册或显式豁免） | P1-3 |
| M3 | 文档登记覆盖率 | **docs md 变更触发角色索引测试：已生效**（documentation path group【复核注册表＋预览实跑】）；缺口＝未标记 31 份（semantics 2/28 有 marker、design 17/22【复核 census】） | 批2a：新增即红＋31 份冻结只降不升（→28）；批2b：豁免类外 100% 登记（豁免对应 OQ12 裁决记录） | P0-3 |
| M4 | 结构棘轮 inner 可用性 | INNER_HEAVY_MODULES 含 1 模块（141.7s 三职责【侦察】） | 集合空；ratchet 独立计时秒级~十秒级进证据 | P1-2 |
| M5 | 仓库体积止血 | script/ tracked 单文件最大 63.6MB【复核】；**>5MB tracked 文件数＝1（仅 census，次大 617KB）【复核清点 519 文件】**；blob top-5 中 3 个为 census 历史版本【侦察】 | tracked 单文件 ≤5MB 门（建议值，带基线豁免清单）；census 出库后即绿；新 blob 停止入库 | P0-5 |
| M6 | checkpoint 构建时长 | 基线未实测——批12 步骤1 先补测（冷构建两次计时） | 第二次构建显著下降，实测数字进证据 | P1-7 |
| M7 | 清偿节拍 | 未下降冻结项清点机制：无；**声明类**形状断言 43 文件/181 处【复核，口径 v1】；表达式类规模待批8 普查；超限文件 237 无排序【侦察】 | 每批清点原因率 100%；基线只降不升（口径 v1 内新增即红） | P1-4/P2-5 |
| M8 | 链接与导航真话 | 5095 链接 0 断链【侦察】；分层表引用失真【复核】；行内代码路径为链接门盲区【复核实例】 | 0 断链保持＋分层表节名断言绿 | P0-1/P1-1/P1-2 |

度量复评：批19 终批复评汇总 M1-M8 机器输出（§5.2），作为方案完成判据；各度量以对应批次验收门输出为准，未实测项（M6 基线）在批12 补测，不以推断数字宣称完成（AGENTS.md:36【复核】）。

## 9. 开放问题（交 owner 裁决，不硬编结论）

- **OQ1（P1-3/批7）**：AGENTS.md:18/:34 措辞二选一——A：inner 含非 Swift Scene 产品路径统一附加 design-gate（符合原文无限定语义，本方案倾向）；B：措辞收敛为『Swift 产品路径』。
- **OQ2（P1-5/批11）**：1000 行硬限是否存在人为拆分动机——两文件 2026-09-30 为 943/997、现 1000【复核基线 notes＋wc】仍仅是相关性，动机未证实【推测】；裁决影响后续拆分边界服从职责还是行数。
- **OQ3（P0-5/批5）**：census 消费者处置方案（skip-if-absent vs 先再生）、是否引入 LFS（新依赖）；历史 blob 是否 rewrite（本方案明确不含）。
- **OQ4（P1-6/批10）**：嵌套指针桩与 AGENTS.md:21 删除方向条款的相容性；不合则降级为 scene/README 内目录指针。
- **OQ5（P2-2/批13）**：21 个 Debug runner 旧路径引用面（实施时 grep 核对，侦察未覆盖）。
- **OQ6（P0-2/批4a，硬前置）**：路由表首版任务键集合——按 git log 频率重选（必含『修复 Scene 视觉缺陷』『发布新版本』＋设计前置首层查询），以及术语键方案（进路由表 vs 升格 source-index 为术语权威入口并断言定义唯一）。
- **OQ7（P1-1/批9c，硬前置）**：lastReviewed 陈旧度断言取数来源（git log 路径过滤 vs 人工戳）。
- **OQ8（P1-3/批7）**：design-gate 零命中状态是否计入『空转门退役清单』及退役判据。
- **OQ9（P2-3/批14）**：inventory 冻结语义与『结构性家族只许收缩』条款的批说明口径——自引用键退役条件（两目录二级化时）。
- **OQ10（P2-5/批17 或显式接受）**：Compilation 聚集（243 文件/81,494 行【侦察】）处置口径——接受并按队列偿还超限维度 vs 显式接受现状。
- **OQ11（P2-4/批16）**：git hooks 方案——仓库级共享（如实声明影响）vs 会话级 hooksPath。
- **OQ12（P0-3/批2b，硬前置）**：31 份未标记文档的清偿口径——全部登记 vs 豁免类划分（候选豁免类：目录 README、forensics 研究档；batch2-design-index.md 作为 12 份文档 entrypoint【复核】的角色归属一并裁决）；豁免须留裁决记录并可审计。
- **OQ13（P1-4/二期）**：表达式类源文本断言的二期扩正则时机与正则形态（扩正则时基线重生成、计数一次性上调后冻结，防口径漂移虚降）；批8 表达式类普查结果为裁决输入。

---

（全文完。修订版 3 为独立终审后最小化修订，五项全部经本会话只读/一次性模拟复核：①P2-2 验收命令换为 `find MyWallpaperX/App -maxdepth 1 -name 'Debug*.swift' | wc -l`（/private/tmp 模拟：旧命令移动后=1、新命令=0）；②批11 排程三处对齐（code_health_baseline.json 补入 §5.1 判据、批11 入临界区全集、区域设计文档点名 frame-admission-retry-design.md＋另两条 approved 覆盖区域注明）；③批15 禁插三处对齐（§5.1 规则列名批12/批15/批17＋条目＋批次表）；④P1-4 口径 v1 显式定义、表达式类为已声明豁免边界＋二期扩正则（示例断言实测存在但不在口径内）＋新增 OQ13；⑤P0-5 大小门补存量清点（script/ 519 个 tracked 文件 >5MB 仅 census 一项）与基线豁免冻结条款。累计 0 项工作区写入；未复核项按【侦察】【审查】【调研】【推测】标注。）