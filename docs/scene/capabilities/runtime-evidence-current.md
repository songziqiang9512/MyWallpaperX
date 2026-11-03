# Scene 当前验证范围

<!-- document-role: current-state -->

<a id="scope"></a>
## 冻结身份

2026-11-03 验证文字前景 HDR 亮度的准备期采用，基线为 `0625f8e766d3a5339ae65795ab028ee8899dc6c3`。签名Debug构建成功、两产品SHA前后相同；产品只改 Document → TextStyle 的有效亮度，普通帧不增加判断或 owner；源码与构建绑定在 `.artifacts/scene-goal-scan-20261103/sdr-text-build-inputs.json`。

签名 Debug App executable SHA-256 为 `f1d823287d407b5e643ab4c3e5aaf6f1720e7cd3119aef4b78420900bd51a0a3`，实际 Swift 产品 `MyWallpaperX.debug.dylib` 为 `22bf8d92ca0a735ded1f4d0e790533644764f6bb0657aa4192c85d4842d85846`。构建为 `-Onone`，Developer ID Team `H9QWU9XN8R`，无时间戳；环境 arm64、macOS27.2、Xcode27.2。

<a id="coverage"></a>
## 最近实际覆盖

收据位于 `.artifacts/scene-goal-scan-20261103/`；benchmark 原件为 `.artifacts/scene-evidence/runs/sdr-text-{brightness,original,neighbor}-20261103/`。

| 职责 | 实际结果与边界 |
|---|---|
| 解析与静态/动态栅格 | `text-raster-tests.log`：16项通过，含新增3项，另53项接线邻例通过；真实 Document/Descriptor/Metal 纹理覆盖 SDR 的0/1/4、wrapper与改名、作者值保真、alpha/几何、动态内容及 HDR 原输出。背景只检查原样保留，不作语义资格。 |
| 字色恢复 | 两固定相位及亮度0/1共4例 Graph GPU 运行通过。作者亮度、0、1的候选图逐字节相同；候选与基线单位亮度图差异0。原0亮度基线全黑触发非黑失败，候选恢复绿色；`sdr-text-pixel-comparison.json`、`sdr-zero-native-recovery.json`。 |
| 扫描相位 | 同1512×982黑底三文字图，候选offset0→0.5变化6442像素、最大RGB差103。只证明固定相位响应；全文本背景动画差分不作扫描归因。 |
| 真实工程 | 未改作者输入的 `3586308277` 与未参与修复的 `3471294034` 各运行10秒，加载、Graph GPU、停止排空通过，原图已查看；见原工程与邻例证据包。 |
| 官方行为研究 | 固定 Wallpaper Engine2.8.42/文件版本2.8.0.42；166文件批次完整SHA校验。原生控制台实际见两相位和零亮度文字仍绿，与公开 HDR brightness 合同相符。`oracle/observation.json` 记录身份、CLI返回和失败层；官方截图未取得有效渲染像素，不作数值parity。 |

<a id="limits"></a>
## 未验证范围

直接 Host 不覆盖普通 App 选择、client/daemon IPC、多屏、长稳与全部外部输入；本批不证明原工程扫描时间/方向与官方一致、backgroundbrightness、HDR文字高光保真、物理EDR、完整语料、macOS26最低版本、优化构建性能、能耗或发行。HDR开启仍保既有8bit栅格行为。

能力合同见[能力索引](README.md#overview)，未闭输入见[开放队列](../roadmap/scene-open-breakpoint-queue.md)，测量方法见[性能卡](../roadmap/performance-convergence-card.md)。结果只适用于绑定的源码、App、输入与入口。
