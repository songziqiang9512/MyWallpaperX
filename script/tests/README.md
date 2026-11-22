# script/tests

行为测试与测试夹具。目标是按主题集合目录组织，顶层只保留本文件、共享 `fixtures/` 和少量高频入口。

## 目录规划

| 位置 | 内容 |
|---|---|
| `governance/` | 验证门、文档/仓库健康、提交预检 |
| `release/` | 发布、签名、打包与安装契约 |
| `web/` | Web 宿主、证据与基准 |
| `steam/` | Steam 获取、会话、下载与入库 |
| `ui/` | 库、网格、工具栏、设置、在线来源与屏保 |
| `scene/` | Scene 解析、shader、渲染、粒子、Puppet、脚本与证据 |
| `fixtures/` | 共享 fixture 与 harness（保持） |
| `support/` | 跨集合测试 support 模块（迁移目标） |

顶层不再新增 `test_*.py`。新测试放入对应集合目录；跨集合共用的 support 模块放入 `support/`，单集合的放该集合内。

## 生命周期

- 每个测试必须能被 `run_scene_tests.py --module <basename>` 独立运行；basename 在仓库内唯一。
- 改动验证按 `scene_validation_gates.json` 的 path group 选择测试；新增测试必须登记映射，或明确标注全量回归专属。
- 未映射测试由 `check_test_mapping.py` 报告，只进入全量回归，不阻塞改动验证。
- 对应能力已退役、源码已删除或长期无法运行的测试应删除，并在提交说明记录原因。
- 一次性研究夹具优先复用现有 support 或 fixture；不把一次性验证固化成长期测试文件。

## 运行

```bash
python3 script/run_scene_tests.py --module test_verify_scene_change
python3 script/run_scene_tests.py --scope scene -j 4
python3 script/check_test_mapping.py
```
