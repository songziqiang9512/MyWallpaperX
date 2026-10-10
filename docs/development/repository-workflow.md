# 仓库开发工作流

<!-- document-role: stable-contract -->

适用于 App、Video、Web、Scene、Steam、工具与文档。安全、设计前置和提交权限以 [AGENTS.md](../../AGENTS.md) 为准；当前 owner 与未覆盖边界查[仓库职责图](../architecture/repository-map.md)。Scene 特有的帧、资源、视觉与性能方法在 [Scene 工作流](../scene/development/development-workflow.md)。

## 定位与决定

1. 写代码前从用户角度明确问题、预期结果和完成边界，核对原生 macOS 产品方向与[技术栈合同](../architecture/technology-stack-boundaries.md)。检查 Git 状态，列出本批文件；用简短说明连接用户结果、当前首断点与验证，不为常规任务另建计划。
2. 从[文档入口](../README.md)或 `python3.12 -B script/document_registry.py --list` 选择任务。`--query scene`、`--query 发布` 返回当前索引中的合同、状态和源码指针；design area 的 owner/status 直接读取原登记，不复制。查询不执行命令，也不读取研究正文。
3. 沿 producer → 第一个错误状态/identity → consumer 追踪，区分“缺实现”“实现偏差”“合同未定”；按下述判定完成必要设计。
4. 只闭合一个职责结果。数据/持久化/IPC 变化须说明兼容、取消、失败、旧版本与退出；普通局部修复不另造设计、registry 或工作流。

## 设计判定与记录

任一项命中即先设计：①新增重要产品/作者能力，或横切多个 owner；②改变 identity、clock、graph、资源生命周期或最终输出权威；③改变用户数据、持久化、IPC 或发布语义且难以回退；④改变机器冻结家族的职责或扩大规模；⑤引入重要外部依赖，或需外部取证才能确定官方行为。既有合同内的局部修复、纯移动和文案调整不因文件数量而要求新设计。

优先修订所属专题的现役设计，无合适承接者才新建。设计从完整用户结果和主链出发，至少写清目标/非目标、当前差距、职责与数据流、关键方案取舍、失败/回退/旧实现退出、验收与未定项。先保存到仓库、接入现有路线和文档索引，再写对应实现；设计变化修订同一权威，不在实施时临时裁决另一个架构。

同步[设计登记](../../script/design_gated_areas.json)的 owner、designDoc、状态与有实际依据的匹配范围；设计未定保留 `blocked-pending-design`，方案和边界明确后才能标为 `approved`。已批准的旧设计不自动覆盖新增范围。落库指仓库中的可审查文件，不要求未经用户授权先 Git 提交；`approved` 表示设计可实施，不表示用户授权发布或能力验收完成。

`check_design_gate.py` 只能拦住已登记且命中模式的 blocked 实施，空模式只提示，未登记能力无法自动识别；它不判断设计质量或先后时序。上述判定和设计覆盖范围仍由实现者、审查者负责，不能以门禁通过替代。

## 并行与验证

并行按精确文件分工，共享 JSON 和同一文件由单个整合者写入。审查者只读冻结的 diff、未跟踪清单和对应证据；修订后重审受影响结论。提交权限遵循 AGENTS.md。

```bash
# 显式预览指定路径（包括尚未修改的预期影响面）
python3.12 -B script/verify_scene_change.py --phase inner --path docs/README.md

# 仅选择本批真实变更；可重复 --owned-path，输出同时列出被排除的改动
python3.12 -B script/verify_scene_change.py --phase inner --base HEAD --owned-path docs/README.md
```

确认计划里的模块和 unresolved 项后加 `--run`。默认不传 owned 参数仍选择全部变化；owned 选择不是文件锁或执行沙箱，单个全局棘轮仍可能发现其他会话的违规。被排除项不能被计入本批验证。删除、重命名要声明涉及的旧/新路径。

| 阶段 | 触发判定 | 所需结果 |
|---|---|---|
| inner | 单元或工具合同的最小反馈 | 最近输入/输出/失败反例，轻量治理门；不自动要求 App 构建或全样本 |
| checkpoint | Swift 产品变更、项目/资源构建面 | inner 加 Debug build、适用质量/设计门；构建只证明可构建 |
| integration | GPU/VM/资源/生命周期/可见输出或跨 runtime | 隔离代表内容或对应 UI/IPC 事件；Scene 显式选 `--sample-id` / `--sample-root` / `--app` / `--output-dir`，缺 corpus 显式记录未验证 |
| milestone | 共享合同、完整能力或发布结论 | 说明为何较小范围不足，再选 `--matrix-tier`、长稳、官方对照或发布门 |

编排器按路径映射显式选择模块；手动最近门用 `script/run_scene_tests.py --module <module>`，该测试入口的 `--scope scene` 不能当作全量。现役参数、CI 跳过运行态的理由及门列表以 `verify_scene_change.py --help` 和预览为准；这里不维护第二份 gate 组合。

## 查询结构债与复用构建

`python3.12 -B script/repository_health.py --format json --limit 50` 从现役 code-health、结构/防御面与测试断言基线、真实 Swift 文件及测试路由派生报告；`--path <精确路径>` 聚焦单个职责。报告区分真实行数、未关联测试的路径和仅登记的冻结预算，不运行验证，不建立第二份债务台账。未关联产品路径或已失效的测试模块会进入编排报告，单独构建成功不能把它们标为 `closure_complete`。

纯源码移动仍报告缺失测试映射；只有唯一、字节相同的旧删除→新文件证明及本次构建通过才能闭合。复制、歧义、正文变化或后续行为编辑均不适用。

不再要求每批为全仓未修改项填写清偿receipt。旧receipt仅保存在历史库；后续在本次改动涉及的owner上解决真实问题，并同步其已有基线。文件不超过1000行且职责清楚即可，不用400行或逐文件测试映射数量制造拆分/测试任务。

`script/run_checkpoint_build.sh` 默认退出时清理隔离 DerivedData；同一 checkout 可用 `--cache-dir /private/tmp/<任务缓存>` 复用，仓库内只允许 `.build-cache/`，禁止真实样本目录。缓存键绑定 checkout、构建器、Xcode、SDK 和配置；Xcode 管源码增量，全局锁拒绝并行 checkpoint。指定缓存成功失败均保留，收尾报告路径与用途并按精确清单清理。复用不替代冷构建或运行验收。 共享 scheme 的 Run（Cmd+R）用 Release 优化构建，Test、Analyze 保持 Debug。逐行调试/`DEBUG` 诊断用 `xcodebuild -configuration Debug`、现有 Debug runner，或临时在 Edit Scheme → Run → Build Configuration 改为 Debug，结束恢复 Release。优化构建保留符号与错误日志；逐帧诊断按需开启。

## 代码与知识交付

“家族”是同类结构职责的现有清单；“防御面”是重复helper、无消费者入口和吞错等检查范围。它们帮助发现偏差，不要求每轮扫描或清偿全仓。

- 按真实行为写产品测试；静态治理可检查文件、索引与结构，但不冒充产品行为。源码字符串断言的存量冻结只覆盖检测器明示的范围，不能据此宣称测试已经行为化。
- 先保留当前正确行为，再按职责拆解。新增抽象必须有实际消费者与生命周期；共享 owner 变更检查迟到事件、取消、重入、释放及下一次操作，不用多一层 wrapper 掩盖错误 owner。
- 文档角色在 `docs/document-role-index.json` 唯一登记。导航只提供链接；当前状态拥有当前事实；参考资料不决定产品行为；稳定合同和计划分别拥有目标与顺序。所有非忽略 docs Markdown（包括未提交新文件）都被检查，未声明角色不会逃过发现。
- 当前文档正文默认受 `document_health` 只降预算约束。新增权威或合理扩展、移动、合并或退役由 owner、reason 与仓库内 decision（决策文档或本节锚点）说明，在原 baseline 的 `adjustments` 精确登记 section/path 及变更前后规范 JSON 的 SHA256；仅匹配当次变更的记录放行，其他变更不获豁免。`--check` 报告所需调整身份供填写；下一批可替换过期记录，不累计第二台账。实际正文、归档载荷和锚点、索引及硬预算校验仍执行；机器只核登记和内容一致，不确认设计已获人工批准。稳定合同的lastReviewed绑定可核验Git维护日期或hash导航审计，不能借刷新日期宣称重新验证运行能力。
- `check_test_assertions.py --census-expressions` 输出v1之外的字面量membership断言及operand供溯源；里面包含合法行为检查，不能整体算作源码形状债或直接扩正则执法。
- 每轮清理本轮已结束的可重建执行环境，最终证据按[产物保留规则](../../.agents/skills/mywallpaperx-maintainer/references/artifact-governance.md)限量留存；`promote_scene_evidence.py --prune-expired`清理工具登记的到期包，唯一失败证据可明确保护。旧材料归档不代表磁盘空间已释放。
- 结束前核对实际 diff、行为结果、未覆盖风险与其他会话改动。独立审查绑定具体内容；“无发现”不替代执行证据。提交、推送和发布状态分别报告，不能把它们合成“完成”。

获得提交授权后，提交信息写清具体问题、已证根因、实际结果与验证范围；说明必要的未验证边界。简单修改可用短正文，不为凑四个标题复制日志；提交、推送和发布仍分别按用户授权。

## 可选暂存面快检

`python3.12 -B script/commit_preflight.py --owned-file /private/tmp/<批次路径数组>.json` 秒级读取当前worktree的暂存blob，核对owned、JSON和gate元数据，默认提示，`--strict`才拒绝。它不暂存、不运行构建或测试；未暂存修复不会掩盖暂存错误。可用 `--message-file` 检查实际Git trailers，`Area: Scene` 等值由工具公开白名单约束，发布工具仅复用解析结果做分组，不自动发布。

如需自动提示，可显式 `--install`，用 `--uninstall`恢复；这里未默认安装。hooksPath为共享仓库配置，会影响其全部worktree，hook的owned快照由common Git目录保存，不绑定安装checkout；每次按提交所在工作树解析index，可从其他worktree卸载。现有有效hooksPath、默认hooks、用户追加内容和符号链接均受保护，工具拒绝覆盖。`MWX_OWNED_PATHS`可给hook传JSON路径清单；不提供时诚实提示归属未验证。

## 规则退出

反复出现、可客观判定、运行成本相称的问题优先复用现有门。登记触发范围、失败含义、owner及调整/退役条件，补一个会被拒绝的反例；主观设计质量和用户意图不做关键词门。修复存量后同步收紧基线；合理扩张用设计和验证解释，规则修订优先替换、合并或删除。

| 现有机制 | 实际覆盖及边界 |
|---|---|
| `check_code_health.py` | 管理目录内 Swift 的1000行上限（含fixtures）；其他语言、第三方来源和职责质量须人工核查，不代表全语言已达标。 |
| `check_design_gate.py` | 上述已登记设计的准入；无法发现所有新能力，也不代替设计审查。 |
| `check_scene_dependencies.py` / `check_scene_defense.py` / 结构清单 | 各自声明的依赖试点、重复/无消费者/吞错与家族预算；不代表全部架构质量。 |
| `document_registry.py` / `document_health.py` / 链接测试 | 文档登记、入口、角色、预算、归档完整性及链接；内容是否仍符合实现须实际复核。 |
| `check_repository_artifacts.py` / `repository_residue.py` | Git可见大文件与已知残留路径；不扫描或清理整块磁盘。 |
| `promote_scene_evidence.py` | 显式晋升的runs包预算/期限，调用 `--prune-expired` 才清理；其他临时环境按产物规则收尾。 |

`verify_scene_change.py` 按实际改动选择适用验证门，需 `--run` 才执行；证据晋升/清理使用表中显式命令，编排器不代为调用。CI在push/PR运行验证，但不执行私有真实样本验收。门不是后台常驻监控，局部通过不等于全仓完成；原始证据、用户媒体和未登记产物不能按“门通过”推定可删除。

关闭能力或重构卡时撤去临时fallback，归档完成过程并收紧对应预算。清理defense的unused acknowledgements前，核对仍服务的历史比较版本，只删除各版本均不再需要的精确记录。

## 余项处理顺序

之前治理发现的余项继续按实际收益处理：先删过期测试与错误入口；再围绕当前产品缺陷处理职责混杂、重复owner和不合理依赖；修改高风险行为时补最近的行为反例。50条依赖试点存量由其原机器基线跟踪，缺映射仅是查询线索，不是必须为每个文件新建测试的配额。源码形状测试随触达行为迁移，不能为了数量降低而删仍有独立价值的回归。全产品兼容、性能和真实账号验收归各现役路线；导航效率在真实任务中检验，不另设治理路线与产品路线争夺优先级。
