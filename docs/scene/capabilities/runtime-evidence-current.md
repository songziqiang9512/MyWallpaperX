# Scene 当前验证范围

<!-- document-role: current-state -->

<a id="scope"></a>
## 冻结身份

本轮验证日期为 **2026-11-03**，基线为 `6b5e76b89560655b0ab232cec0bfb250decefe71`，产品变更仅为 solid 颜色脚本接入已有 Vec3 consumer。候选源码与构建身份由 `.artifacts/scene-goal-solid-20261103/candidate-identity.json` 绑定；普通帧未增加 owner、纹理或计算阶段。

签名 Debug App executable SHA-256 为 `4b159273aa223298a24c7379396a52a1bd3fc77a087a7fce156962514c327209`，实际 Swift 产品所在 `MyWallpaperX.debug.dylib` 为 `2ed3b210a10efcdaf4b3c0a99b6d492bbe9fa8f868d9859e14350a1961a090ef`。基线与候选同为未优化 Debug（`-Onone`），本机 Developer ID Team `H9QWU9XN8R`，签名时间戳关闭；环境为 arm64、macOS27.2、Xcode27.2。

<a id="coverage"></a>
## 最近实际覆盖

| 职责 | 本轮结果与证据 |
|---|---|
| 工程接线 | 基线与候选签名 Debug 构建成功；`baseline-debug-build.log`、`candidate-debug-build.log` |
| Vec3 owner / typed consumer | `test_scene_script_solid` 六个方法通过；新增30项覆盖非白seed、wrapper、改名、effectful solid、image、媒体事件和拒绝/失败边界。坏返回/异常只证明真实VM不发布新值及resolver给定current后的保留，未实测完整Session提交/回退；`vector-tests-v2.log` |
| 近邻行为与真实值类型 | 39项vector/媒体、22项solid资源/描述符与Metal白纹理、7项support消费者检查通过。失效standalone门改用真实Catalog值声明和当前源清单，移除旧重复类型；`neighbor-tests.log`的原编译失败及`solid-layer-tests-v4.log`、`solid-layer-support-consumer-tests.log`保留 |
| 实际颜色输出 | 两个自有色板使用不同ID/资源名/变量名及非白seed。基线脚本侧错误保seed；候选两例各4096像素与同帧静态对照逐字节一致；`native-color-comparison.json`及两份`*-native/report.json` |
| 独立真实文字邻例 | 未参与修复的`3586308277`运行10秒，加载与Graph GPU执行通过，停止时Surface释放、GPU排空；原图已查看。该运行不证明其扫描方向/可见度与官方一致；`real-neighbor-native/report.json` |

表中相对收据均在 `.artifacts/scene-goal-solid-20261103/`。颜色输出比较固定同一输入、窗口和配置；基础benchmark PASS本身不会检查两个色板是否同色，实际恢复由独立像素比较证明。

<a id="limits"></a>
## 未验证范围

本轮直接 Host 不覆盖普通 App 选择、client/daemon IPC、真实多屏、长稳与全部外部输入。named/依赖/初始隐藏solid的颜色准入、所有effect组合、完整语料、官方同状态parity、macOS26最低版本、物理HDR/EDR、优化构建性能、能耗和正式发行均未由本次证明。

具体能力边界见[能力索引](README.md#overview)，未闭输入与后续资格见[开放队列](../roadmap/scene-open-breakpoint-queue.md)，测量方法见[性能卡](../roadmap/performance-convergence-card.md)。运行结果只证明其绑定的源码、App、输入和入口；代码或控制条件改变后重新选择相称验证。
