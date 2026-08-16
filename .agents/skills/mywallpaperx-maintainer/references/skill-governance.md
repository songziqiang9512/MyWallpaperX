# Skill 自纠与知识治理

本参考只处理 Skill 本身、仓库规则和权威路由的长期一致性。它不保存当前产品能力、路线阶段、样本结论或单次修复历史。

## 目录

1. [Skill 的角色](#skill-的角色)
2. [偏差分类](#偏差分类)
3. [自动修正条件](#自动修正条件)
4. [最小修正方法](#最小修正方法)
5. [规则进入与退出](#规则进入与退出)
6. [风险分级验证](#风险分级验证)
7. [定期漂移审计](#定期漂移审计)

## Skill 的角色

Skill 只保存三类信息：将 Agent 路由到当前权威的入口、难以低成本重建的判断方法、反复造成高成本错误的边界。当前实现真值属于代码和可复现证据，目标属于仓库合同，当前路线/能力/证据属于各自现役文档或机器 manifest。

Skill 不拥有架构决策。发现冲突时，先回答是 Skill 错、实现偏离、目标改变，还是证据不足；不要为了让 Skill 看起来正确而修改产品或文档。

## 偏差分类

| Class | 判据 | 动作 |
|---|---|---|
| `skill-error` | 路由、owner 提示、命令、方法或限制已被当前权威和证据明确证伪 | 最小修正 Skill |
| `implementation-deviation` | 目标合同仍有效，当前实现走了错误 owner 或行为 | 修当前纵向职责；Skill 只在表达不清时改 |
| `contract-change` | 用户、官方行为或架构决策改变了目标 | 先更新唯一合同和迁移影响，再更新 Skill 路由 |
| `ambiguous` | 当前事实或目标证据不足 | 保持边界，设计最小区分实验，不新增长期规则 |

使用最小记录：`skill_statement`、`live_counterevidence`、`classification`、`affected_owner`、`smallest_correction`、`verification`。单个旧文件、历史报告、当前错误实现或个人偏好不能独立证明 Skill 错。

## 自动修正条件

本仓库用户已授权在开发中持续发现并纠正已证伪的 Skill，但这项 standing maintenance request 不自动扩大产品或其他文件的写入范围。实际修改仍同时满足：

1. 当前是允许写入的实现任务；只读/讨论只报告候选。
2. 反证足以区分 `skill-error` 与 `implementation-deviation`。
3. 错误直接影响当前目标，不只是可能影响未来同类任务或低价值措辞偏好。
4. 将精确 Skill 文件加入 owned scope，并重新检查 tracked/untracked 状态。
5. Skill 路径没有归属不明、用户并行或其他 Agent lane 的重叠改动。

条件不全时保留当前产品任务边界，报告修正候选和缺少的裁决证据。不要借“主动纠偏”扩大产品、提交、删除或发布权限；Skill 修正若与产品变更是独立职责，分别暂存和提交。

## 最小修正方法

- 错路径改成稳定入口或 discovery 方法，不换成另一组易过期文件清单。
- 错 owner 改为 producer-to-consumer 识别方法；只有确属稳定合同的 owner 才直接写入。
- 错命令改成现役统一入口，并要求读取当前 `--help`、plan 或 manifest。
- 过强规则降级为带适用条件的默认方法。
- 已由 `AGENTS.md`、现役文档或机器 gate 拥有的合同改成短路由，删除重复正文。
- 删除一次性数字、route phase、样本、报告、dirty lane 和 workaround，不用新快照替换旧快照。
- 优先替换或删除旧句，不在末尾追加“例外的例外”。

## 规则进入与退出

新增规则至少满足一项：防止可重复的高成本/安全错误；保存非显然 owner、identity 或 lifecycle 方法；路由到唯一权威；收敛反复手工流程；阻止常见证据夸大。

不加入：低成本可由 `rg`、schema、`--help` 或文件名发现的清单；与 `AGENTS.md` 完全重复的段落；当前 PASS/样本/提交/报告；单次 bug；无 consumer 的未来抽象；只增加形式负担的检查项。

定期删除已被稳定 gate 取代的手工步骤、不存在的路径/flag、迁移结束后的 fallback 指导、重复权威正文，以及没有改善 owner/证据决策的规则。行数不是门；任务所需上下文和错误决策率才是指标。

## 风险分级验证

| 修正等级 | 最低验证 |
|---|---|
| Mechanical | frontmatter/YAML、链接、路径、重复文本、Markdown 和 owned-file diff；fresh-context 为 `not-applicable` |
| Domain method/owner | Mechanical 全部，加一个直接命中该 Video、Web、Scene、macOS 或治理表面的 fresh-context 只读任务 |
| Cross-cutting authority/trigger/safety | Mechanical 全部，加所有受影响域及至少一个跨模块任务；只有真正影响三域时才要求 Video/Web/Scene 全套 |
| Major restructure | Cross-cutting 验证，加默认上下文负载审计、未见任务和独立冻结内容终审 |

前向测试使用 fresh context，只给 Skill 路径、自然任务和原始仓库，不泄漏预期答案或本轮诊断。测试默认只读；若会启动 App、修改文件或使用真实样本，必须另有授权。失败后先判断是 Skill 缺陷、任务本身证据不足还是测试提示泄漏，再修正并重跑受影响等级。

## 定期漂移审计

1. 展开所有 Skill 文件，包括 untracked manifest；空 `git diff` 不能证明未跟踪内容正确。
2. 核对 frontmatter 触发面、`openai.yaml` 默认提示和“不加载 build-macos-apps”边界一致。
3. 核对每个 reference 由 `SKILL.md` 一层直达，且只在命中任务时加载。
4. 检查文档角色、脚本 interface、owner 提示和路径仍存在；语义由当前权威决定。
5. 搜索 current phase、PASS 数量、样本 ID、commit、dated conclusion、dirty lane 和重复合同。
6. 运行当前 `skill-creator` validator、YAML/链接/路径检查和风险相称的前向测试。
7. 冻结 Skill-only manifest，确认没有产品源码、历史材料、缓存或报告进入提交。

Skill 发布只证明指导结构与测试任务表现；没有运行产品 runtime 时，不得据此更新 Web/Scene/Video 当前运行结论。
