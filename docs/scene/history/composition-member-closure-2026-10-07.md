<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。工作卡与验收门见[断点队列 QF 段](../roadmap/scene-open-breakpoint-queue.md#qv-visual-repairs)；设计裁决见[D1](../roadmap/batch2/composition-render-target-design.md)。

# 组合成员闭包扩展到完整 parent 级联（2026-10-07）

起点 `7cf9c9b9`（工作树）。承接用户点名样本 3226487183（纹理合成错误）：层 2522「中间人物整体」（组级 chromatic_aberration）与层 115975「音频框」（组级 opacity+脚本显隐）被 `execution-route-utility-composition-subtree-shape` 整组拒绝。定性：组员是带 transform 父子链的 image/text（如 2522 的成员 1095→840→1420 三级链，成员自带 7–13 个效果），而 `SceneUtilityLayerSourceRoute` 的成员守卫要求 image/solid/text 成员 `childLayerIDs.isEmpty`——D1（2026-10-04）落地 isolated group target 后，成员闭包仍停留在「扁平一层」，与既裁决「成员随 parent 分组」不一致。

## 修复（1 产品文件 + 设计修订）

`SceneUtilityLayerSourceRoute.resolve` 成员类型守卫删除 `child.childLayerIDs.isEmpty` 要求：成员闭包=完整 parent 闭包（`pending` 递归本就收集深层成员），中间 plain 成员允许拥有子层；深层成员沿既有 world frame 父链（`SceneLayerWorldFrameResolver` 的 `parentWorld * attachment * local`）合成进同一组目标。模型/粒子/灯成员、非组合 utility 成员、passthrough、根级依赖组、父子索引双向一致、无环（`descendants.insert` 幂等）与 `childID != layer.id` 自引用拒绝全部保持原状。成员级 `dependencyLayerIDs` 准入在扩展前后一致（不新增成员级依赖检查，官方语义未证前维持现状，已在 D1 卡登记）。设计修订入[D1「成员闭包扩展到完整 parent 级联（2026-10-07）」](../roadmap/batch2/composition-render-target-design.md)。

## 验证（2026-10-07，隔离根 /private/tmp/mwx-sample4，Debug App `10ca958adbcf1ec8…`）

- 3226487183 当前 HEAD 回放：修复前 capability-admission 拒绝层 2522/115975 各一条（`reason=execution-route-utility-composition-subtree-shape`）；修复后同码零拒绝，且两层的组级效果进入 `effect-cpu-invocation origin=utility-composition` 遥测（2522 chromatic_aberration、115975 opacity；修复前遥测只有 1625/2168/982 三组的组级效果）。材质 runtime audit 修复前后均零失败（claimed=encoded，failures=0）。
- 组合/渲染门 14/14 模块全绿（`verify_scene_change.py --phase inner --path <本文件>` 推导集；`MWX_SCENE_INTEGRATION_APP` 指向修复后 Debug 二进制）：含 composition authored order 十案 App 像素门、composition source identity、fullscreen visibility、utility layers 源套件、visible graph output render plan 等，252.8s 全 OK。
- 结构门：scene-dependencies PASS、scene-defense ratchet holds、design-gate pass（D1 设计修订命中已批准域）、repository-residue PASS、code-health PASS（1133 文件硬限内）。
- fixed13 基线对账：见下节（回填）。
- 独立只读子代理审查：APPROVE，P0/P1 零，P2 三条已处置（成员级依赖裁决句入 D1 卡；运行证据段=本文；文档排序无合同不处理）。

## 已知边界与后续

- 3226487183 的用户可见「错位」症状在组捕获准入后画面基本不变（成员像素与扁平绘制一致、组级色差强度为动画值）：剩余可见差异（侧脸大图缺失、游离手臂碎片）指向两侧拆分源文件链的 puppet 附件/脚本原点域（origin 由用户属性脚本求值、`*_puppet.mdl` 骨架），与组合捕获无关——已登记为断点队列 QF 批A2。
- 冷缓存 Debug 启动成本：3226487183 capability-catalog 阶段 15.5s→48.3s（46 个新增准入材质的逐 shader 规范化/分析，冷缓存每次重算；launch-result-cache 命中后回温）。Release 与热启动未测，按 Q2 排序另行处理，不构成本批回退证据。
- 官方 parity 不在本批范围：成员闭包的官方语义依据仍是 D1 的「成员随 parent 分组」黑盒裁决，未做新官方实验。

## fixed13 对账（回填）

同输入双跑归因（本改动 App `10ca958adbcf1ec8…` vs 干净 HEAD `7cf9c9b9` worktree App，fixed13 矩阵、duration 10、冷缓存各一次）：13 样本逐样本 passed 标志+失败清单对比——11 样本完全一致（含 4 个样本的 `effect_graph_*count/sha256` 漂移两跑共有=2026-09-25 钉定期望后的既有 HEAD 漂移，与本改动无关，刷新归 Q1T full-matrix 扩张流程）；`375755836` 本改动 PASS / 基线 FAIL（presentation stream 环境敏感抖动族，方向有利）；`3747492842` 批跑中多出的两条 checker 串（observation diagnostic / execution contract not satisfied）在本改动单样本复跑中不复现（同二进制复现基线失败集）=运行级抖动。结论：本改动 fixed13 零回归。
