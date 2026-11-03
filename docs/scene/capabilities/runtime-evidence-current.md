# Scene 当前验证范围

<!-- document-role: current-state -->

<a id="scope"></a>
## 冻结身份

本轮验证日期为 **2026-11-03**。合并候选以主仓 `codex/engine-refactor-program` 的 `485b12c14fd3db85ba35c85676037dd072f693fa` 为基础，采用本工作树的 Scene 架构与文档，并融合文字离屏特效 RGB 修复。

本机收据目录为 `.artifacts/scene-integration-preflight-20261103/`。`candidate-build-source-identity.json` 绑定4404个产品/工程/构建输入，构建后无内容漂移。`candidate-debug-app-identity.json` 记录完整代码产物：App executable SHA-256 为 `b6810884bf3005baed2e15e94119d65f9c768627d5594cf0c2c1a00f431e87bc`，实际 Swift 产品所在 `MyWallpaperX.debug.dylib` 为 `b794f8e7bfac87f36d03b8798019f9667e1f896da843befd75239181de11937b`。

构建为未优化 Debug（`-Onone`），本机 Developer ID Team `H9QWU9XN8R` 签名且严格验证通过，关闭签名时间戳。运行环境是 arm64、macOS 27.2、Xcode 27.2；这不是 macOS 26 最低版本、优化构建、公证或正式发行验收。

<a id="coverage"></a>
## 最近实际覆盖

| 职责 | 本轮结果 | 证据入口 |
|---|---|---|
| 完整工程接线 | checkpoint Debug 与本机签名 Debug 均构建成功；4404输入无漂移 | `candidate-debug-build.log`、`candidate-signed-debug-build-v3.log` |
| 文字 source 颜色与回退 | 25项检查通过：10项准备准入正反例、15组真实 Metal 读回，覆盖投影、glyph alpha、SDR/HDR 及首阶段停用/library/pipeline 失败 | `text-rgb-new-gpu-v2.log` |
| 相邻执行链 | 15个测试方法通过，包含原36项颜色/末合成情形、资源命令、GraphExecutor、activation 与 execution capability | `scene-neighbor-tests.log` |
| 文档与工具 | 239个测试中238项通过、1项因可选 census 缓存缺席跳过；文档登记、链接、结构、扫描/归档和验证路由均在范围内 | `candidate-final-document-tool-tests-v2.log` |
| 真实壁纸直接 Host | `3589819394` 与独立邻例 `3471294034` 各运行8秒，均报告 PASS、加载完整、Graph GPU 编码无失败；停止时 Surface 1→0、GPU 排空 | `native-text-neighbors/report.json` |

两例 ready/after 原始截图已人工查看：`3589819394` 的文字白亮放射保持，`3471294034` 的人物、网格、文字和红色粒子均有输出。该输入没有官方同状态逐像素对照。样本原目录和隔离副本的内容核验无变化，见 `native-input-verification.json`。

<a id="limits"></a>
## 未验证范围

直接 Host 运行不覆盖普通 App 选择、client/daemon IPC、跨引擎切换和真实多屏链路。本轮没有重新执行全部组件、完整语料、长稳、所有外部输入/播放器、官方完整 parity、物理 HDR/EDR、优化构建性能或能耗验收。

短窗 functional PASS 不代表60 FPS达标：`3471294034` 在本次未优化 Debug 中呈现间隔中位数为125ms，未与同配置基线比较，不能认定新回归或优化收益。下一测量按[性能方法](../roadmap/performance-convergence-card.md)进行；能力与输入缺口见[能力索引](README.md#overview)和[开放队列](../roadmap/scene-open-breakpoint-queue.md)。

运行收据只证明其绑定的源码、App、输入和入口。产品源码、构建参数或 gate 输入变化后，应重新选择相称验证；只修正文档与引用不重新赋予旧运行额外证明力。
