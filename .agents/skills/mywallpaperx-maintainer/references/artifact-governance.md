# 临时产物与膨胀治理

本参考处理 build、runtime、benchmark、matrix、报告、截图、缓存和历史 residue。目标是限制无界增长并找到真实 writer，不是把“可重建”自动变成删除授权。

## 目录

1. [选择治理强度](#选择治理强度)
2. [输出位置与输入保护](#输出位置与输入保护)
3. [高体量生命周期卡](#高体量生命周期卡)
4. [Writer-first 审计](#writer-first-审计)
5. [清理决策](#清理决策)
6. [运行后收尾](#运行后收尾)

## 选择治理强度

| 等级 | 适用 | 要求 |
|---|---|---|
| Bounded | 使用现役工具、已知隔离输出根、普通定向 test/build，或输出种类与上限已由现役工具约束的短时 runtime | 记录实际 output root、是否保留、是否清理；遵循工具既有合同，无需另写完整卡 |
| Managed | 新 producer、benchmark/matrix、会采集大量 runtime evidence 的运行、长稳/逐帧输出、共享或非默认根、未知/异常增长、真实输入写入风险、唯一失败证据 | 启动前写生命周期卡；运行前后检查体量、文件数、writer、进程和保留理由 |
| Investigation | 用户问旧文件为何仍出现、归属不明、旧安装 App 或 helper 可能写入 | 全程先只读，追踪 executable/PID/mtime/open handle，再给精确候选；不先删除 |

没有生成文件的 discussion/read-only 任务将 artifact 状态记为 `not-applicable`，不为完成清单制造输出。

## 输出位置与输入保护

- 使用仓库现役隔离 DerivedData 或工具明确的 `--output`、runtime home、Workshop copy 和 cache 参数。
- 工具支持隔离时，每个 managed run 使用独立目录；现役工具必须使用共享根时，先串行化、记录精确子树与 writer，并避免与其他 lane 复用同一运行输出。同一迭代只保留有诊断价值的失败现场与最终候选。
- 一次性分析使用 `/private/tmp` 下精确的任务目录；正式工具和测试仍进入仓库规定位置。
- 用户源视频、真实 Workshop/Scene 根、原始 `project.json` 和资产永远是只读输入，不是 cache、property injection、manifest 或 report 输出根。
- `.codex` 是可重建工作区，不是源码或长期知识库；但归属不明和唯一证据仍不能自动删除。
- `docs/scene/evidence/` 是由仓库级 ignore 保护的本机证据缓存，不是源码或 Git 事实入口。可用 `script/promote_scene_evidence.py` 在清理 runtime 前提纯最终报告、日志和截图，但不得暂存或提交；权威文档只记录有界结论、输入/App/report/manifest identity 与 SHA-256，不链接或依赖该目录。

## 高体量生命周期卡

只对 Managed 等级记录：

```yaml
producer_and_build_identity:
owned_output_roots:
read_only_input_roots:
expected_classes_and_budget:
retention_reason:
cleanup_trigger:
protected_evidence:
```

运行前检查可用磁盘与输出根当前体量，按实际证据问题限制帧、截图、trace、持续时间和 retry。工具支持显式 output/cache 参数时必须传入，不能依赖 cwd 或用户目录的隐式 writer。

## Writer-first 审计

当旧 artifact、Workshop residue 或异常增长出现时：

1. 记录仓库 status/worktree 和候选绝对路径。
2. 按 size、count、mtime、文件类型和目录层级确定增长形状。
3. 检查当前 App、旧 `/Applications` App、helper、WebContent、xcodebuild、Python/benchmark、定时任务和仍打开的文件句柄。
4. 核对实际 executable path、bundle/build identity、PID 和时间线，区分当前生成、旧安装生成、仍运行任务和历史 residue。
5. 找到 writer 与错误 route/retention 后先修根因，再讨论历史文件。

优先复用当前 `script/audit_codex_artifacts.py`，但先读代码和 `--help` 确认只读默认与扫描范围。工具标记 `candidate` 只表示分类，不构成删除授权；体量阈值从当前环境和工具读取，不固化进 Skill。

## 清理决策

删除或移动前必须：列出精确绝对 manifest；解析 realpath/symlink 并验证位于允许的派生根；排除 worktree、源数据、真实样本、运行中 output、open handle、归属不明内容和唯一证据；保留必要 summary/hash；取得当前规则要求的确认；逐项处理而非 wildcard 或大根递归。

禁止把仓库根、整个 `.codex`、真实 Scene/Workshop 根、用户视频、git worktree、并行 lane、运行目录或唯一失败证据作为清理目标。优先可恢复操作；用户只要求审计时停在候选 manifest。

## 运行后收尾

- 停止或明确记录仍运行的 App/helper/benchmark/service。
- 对 Bounded run 记录 output root 和保留状态；对 Managed run 再记录体量、文件数、writer 与 protected evidence。
- 检查是否误写真实输入根，并复查 `git status --untracked-files=all`。
- 长期事实只进入对应权威文档的摘要/identity，不把整个输出目录变成知识真值。
- 将可重建 retry 和重复输出列成精确候选；没有授权不实际清理。

删除 residue 不能证明 writer 已修复，clean worktree 也不能证明没有外部 artifact 增长。
