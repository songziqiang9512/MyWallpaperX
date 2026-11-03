# Scene 当前验证范围

<!-- document-role: current-state -->

<a id="scope"></a>
## 冻结身份

2026-11-03 验证opaque视频资产的straight颜色用途与终态局部失败，基线`f9ee9bad364a32b001e80b3d37711a02510c803d`。签名Debug构建成功，7产品SHA前后相同；构建收据为`.artifacts/scene-goal-asset-video-20261103/final-build-inputs.json`。

App executable SHA-256为`7c8faa1adbc7e31d49c1c9738115bc27bbe6bfc14417410f325ce20c72c9345b`，Swift产品`MyWallpaperX.debug.dylib`为`c20eb41769cc3fa0cb81fd7baf600f8d91c5f653a062a422466b995156f5dbce`。`-Onone`，Developer ID Team `H9QWU9XN8R`、无时间戳；arm64、macOS27.2、Xcode27.2。

<a id="coverage"></a>
## 最近实际覆盖

下表收据根为`.artifacts/scene-goal-asset-video-20261103/`；能力合同见[视频资产](material-video-assets.md)。

| 职责 | 实际结果与边界 |
|---|---|
| 自有utility输入 | 同shader静态红图与MP4/TEX slot1混合白色capture；冷暂停、运行及改名双Surface呈粉色，中心约(254,64,64)，保cyan peer与隐藏坏视频。`native-color-recovery.json`保同包基线对照；`presentation-final/`保最终App窗口。 |
| 坏视频 | utility终态保白背景与peer；普通终态可直接完成资格，不强求先pending。`presentation-ordinary-terminal-final.log`通过；输入、App/dylib身份稳定，停止GPU排空。 |
| 材料与真实帧 | 准备门2变体通过；`material-gpu-tests-final.log`4项通过，两AV变体32/31帧各60项检查通过，含opaque straight、straight拒PMA/未知alpha、原data/PMA、发布身份及缓存/AV借用边界。 |
| Finalizer/Graph/Bridge | `terminal-tests.log`与`terminal-coordinator-final.log`合计59项通过；3种purpose×9状态区分终态与pending/非法publication，3阶段实际GPU局部passthrough保原输入及健康suffix。 |
| 独立真实邻例 | `.artifacts/scene-evidence/runs/video-asset-neighbor-20261103/video-neighbor/report.json`：未改作者`3586308277`，输入SHA一致；Ready后7秒Graph/GPU与停止排空通过，原图绿字、森林、粒子及音条可见。不作扫描时序parity。 |

<a id="limits"></a>
## 未验证范围

本批是直接Host及自有材料/窗口证据，不覆盖普通App选择、client/daemon IPC、物理多屏、真实298完整画面、effect.visible组合wrapper、全部codec/透明视频、完整语料、长稳、macOS26最低版本、优化性能/能耗或发行；采样窗口不代表全部呈现时刻，无官方像素parity。

能力见[索引](README.md#overview)，未闭输入见[队列](../roadmap/scene-open-breakpoint-queue.md)，测量见[性能卡](../roadmap/performance-convergence-card.md)。
