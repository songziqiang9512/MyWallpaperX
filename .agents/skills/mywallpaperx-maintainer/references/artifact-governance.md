# 产物保留与清理

每轮按“临时执行环境 → 必要结果 → 清理”收尾。没有生成产物的讨论或只读检查无需制造报告。

## 放置与保留

| 类型 | 位置与期限 |
|---|---|
| DerivedData、staged App、运行样本副本、临时 HOME、重试输出 | 独立任务临时目录；进程结束并提取必要结果后当轮删除。默认 checkpoint build 已自动清理。 |
| 连续迭代的构建缓存 | 显式 `--cache-dir`，同一任务只留一份；任务结束清理，跨轮保留须报告路径和用途，下一轮先复核是否仍需。 |
| 最终日志、必要截图、身份与报告 | `promote_scene_evidence.py` 提取至 `.artifacts/scene-evidence/runs/`；默认14天、单包32 MiB、总量1 GiB，达到总预算停止新增，不静默删除未知材料。 |
| 未解决失败的最小复现 | 使用 `--protect-reason` 说明问题，不自动到期；仍计入总预算，问题解决后重新提取普通有期限结果并清理原包。 |
| 既有未分类证据 | `.artifacts/scene-evidence/archive/` 保存迁移的旧证据，按需查询，不继续写入；缓存普查在 `census/`。迁移保留原字节，不假称释放磁盘。 |
| 长期结论 | 当前路线或对应合同仅写结论、验证身份和必要边界；Scene过程进 `docs/scene/history/`，跨专题过程进 `docs/history/`，不把整个输出纳入版本库。 |

## 每轮操作

1. 启动前选精确输出目录。真实用户媒体、Workshop/Scene原件只读；不把仓库根、`.codex`根或样本根当输出。
2. 运行时限制时长、截图和重试数量；只留最终候选和有诊断价值的失败，避免同内容反复复制。
3. 需要保留时运行 `python3.12 -B script/promote_scene_evidence.py --run final=/绝对路径/report.json --destination 任务名`；失败尚未解决加 `--protect-reason 原因`。
4. 收尾运行 `python3.12 -B script/promote_scene_evidence.py --prune-expired`，只清工具登记、已到期、哈希未变且无打开句柄的包；改过、未登记或正在使用的内容保留并报告。
5. 删除本轮可重建产物前确认进程已退出，逐项记录精确路径；用户已授权常规清理，无需每次重复询问。未知归属、唯一未解决证据和原始资料先列清单，不批量猜删。
6. 最终报告用一段说明保留路径/原因和清理结果。外部引用或仍在执行的目录明确保留；不要声称移动到忽略目录就减少了磁盘占用。

历史 `.codex` 不自动整根清理；需要排查时用只读 `script/audit_codex_artifacts.py --json` 识别运行配置、实际writer和候选。它的candidate仅是待核验材料，不能按大小直接删。新证据不再写docs/scene，旧安装工具如重新生成该目录应定位并修正writer。
