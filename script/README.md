# script 目录

开发、验证、证据与发布工具。产品源码在 `MyWallpaperX/`，行为测试在 `script/tests/`；本文件是顶层入口的导航，不替代各脚本的 `--help` 或 `docs/development/repository-workflow.md` 的验证合同。

## 目录规划

| 位置 | 内容 | 状态 |
|---|---|---|
| `data/` | 台账、注册表、baseline、矩阵 JSON | 已迁移 |
| `tests/` | 行为测试与 fixtures | 保持 |
| 顶层 `*.py` | 存量工具入口；按下方"入口索引"查阅 | 待按工具族迁移 |
| `governance/` | 验证门、文档/仓库健康、提交预检 | 已迁移 |
| `release/` | 发布、签名、版本脚本 | 已迁移 |
| `build/` | 构建/运行/资源复制脚本 | 已迁移 |
| `scene/` | Scene 普查、shader 合同、证据、播放/矩阵 | 目标位置 |
| `web/` | Web 证据与基准 | 目标位置 |
| `assets/` | 资产生成器 | 目标位置 |
| `evidence/` | 外部证据提取与晋升 | 目标位置 |

存量 Python 工具暂留顶层：它们通过同目录 import 和 `Path(__file__)` 计算仓库根，迁移需要同时改测试的 `sys.path` 导入与各脚本的相对路径。迁移按工具族分批进行，每批更新 `scene_validation_gates.json` 与 CI 引用并跑对应测试。

## 约定

- 顶层 `*.py` 分两类：带 `if __name__ == "__main__"` 的 CLI 入口，和被其他脚本 import 的库模块。新增 CLI 必须带模块 docstring，并在下方"入口索引"登记。
- 一次性研究脚本不留在顶层；中间产物写 `.artifacts/` 或任务临时目录，完成后清理。
- 新测试必须能用 `script/run_scene_tests.py --module <name>` 独立运行，并在 `script/data/scene_validation_gates.json` 映射到产品路径；确实只属于全量回归的，在提交说明中标注。
- 数据台账只保留当前消费者；历史结论从 Git 查询，不靠新增台账文件保留。

## 入口索引

| 任务 | 入口 | 说明 |
|---|---|---|
| 按改动选择验证门 | `verify_scene_change.py` | 预览/执行门禁；`--test-scope changed\|release\|all` |
| 运行测试 | `run_scene_tests.py` | 默认全部 `test_*.py`；`--scope`、`--module`、`--keyword`、`-j` |
| 代码健康 | `check_code_health.py`、`check_scene_defense.py`、`check_scene_dependencies.py`、`check_test_assertions.py`、`check_repository_artifacts.py`、`check_design_gate.py` | 只读治理门；命令参数见各自 `--help` |
| 文档与仓库健康 | `document_health.py`、`document_links.py`、`document_registry.py`、`repository_health.py`、`repository_residue.py` | 文档预算、链接、角色、结构债与残留 |
| 提交预检 | `commit_preflight.py` | 读取暂存 blob，提示或拒绝不完整批次；不代替构建/测试 |
| 测试映射报告 | `check_test_mapping.py` | 列出未被任何验证路径组选中的测试；默认只报告，`--strict` 才拒绝 |
| 脚本布局报告 | `check_script_layout.py` | 列出未登记入口与超过 1000 行的测试；默认只报告 |
| Swift 格式 | `format_swift_changed.py` | 只处理改动/未跟踪 Swift 文件；`--lint` 为严格检查 |
| Scene 能力普查 | `scene_capability_census.py`、`scene_material_program_census.py`、`scene_shader_preparation_census.py`、`scene_effect_census.py` | 只读样本/材质/编译覆盖统计；输出不写入样本 |
| Scene 诊断与证据 | `scene_diagnostic_report.py`、`scene_sample_acceptance_ledger.py`、`scene_sample_debug_archive.py`、`scene_sample_snapshot.py`、`scene_helper_qualification_sites.py` | 证据归档、验收台账、快照与资格点 |
| 证据升降与审计 | `extract_wallpaper_engine_client_evidence.py`、`promote_scene_evidence.py`、`audit_codex_artifacts.py` | 外部证据提取、证据晋升与 Agent 产物审计 |
| Scene 播放验证 | `scene_wallpaper_benchmark.py`、`scene_matrix_suite.py`、`playback_process_isolation_benchmark.py`、`wallpaper_startup_benchmark.py` | 真实 App/隔离播放/启动基准；需要样本或构建产物 |
| Scene shader 编译 | `scene_shader_compiler_harness.py` | 离线通用 shader 编译/合同 harness；不进入产品运行时 |
| Web 证据与基准 | `web_wallpaper_benchmark.py`、`web_runtime_switch_benchmark.py`、`web_audio_restart_benchmark.py`、`web_space_lifecycle_benchmark.py`、`web_system_state_benchmark.py`、`web_failure_state_benchmark.py`、`web_property_persistence_gate.py` | 需要已构建 App 与真实样本；`web_benchmark_capture.py` 是共享采集库 |
| 发布 | `publish_release.py`、`release_version.py`、`validate_release_notes.py`、`validate_apple_silicon_release.py` | 只在明确发布授权后使用 |
| 构建与签名 | `build_and_run.sh`、`run_checkpoint_build.sh`、`build-scene-media-observer.sh`、`copy-scene-stock-assets.sh`、`prepare_release_version.sh`、`resolve_version.sh`、`update_project_version.sh`、`publish-steam-helper.sh`、`sign-steam-helper.sh` | 构建/打包/签名入口；缓存与产物按产物规则清理 |
| 资产生成 | `generate_scene_full_matrix.py`、`generate_scene_shader_cache_identity.py`、`generate-scene-stock-index.swift`、`scene_particle_texture_ai.py` | 矩阵、缓存身份、stock 索引与开发期纹理；后者需要外部 API 密钥 |
| Steam 账户 | `steam_auth_gate.py`、`steam-auth-gate.sh` | 显式账户/Guard 门禁；`.sh` 只是兼容入口 |

## 库模块

被 CLI/测试 import 的模块都带前缀归属：`scene_capability_census_*`、`scene_shader_compiler_*`、`scene_wallpaper_*` 是 Scene 工具的内部分解，`web_*` 是 Web 工具，`source_*` 是源码布局/迁移辅助。新增库模块优先并入既有前缀族，不要为单次调用新建顶层文件。

## 测试与 fixtures

- `tests/test_*.py` 是行为/合同测试，按 `run_scene_tests.py` 的模块名运行。
- `tests/fixtures/` 是 harness、输入和生成数据；由测试显式引用。删除 fixture 前确认没有测试、registry pattern 或夹具间 include 引用。
- 测试与产品源码的映射权威是 `scene_validation_gates.json`；未映射测试在改动验证中不会被选中，只会在全量回归中运行。
