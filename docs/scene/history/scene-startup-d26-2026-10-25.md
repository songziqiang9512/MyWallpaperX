# Scene 启动 D26：生成VP9夹具与普通启动的有限内存观察

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。截止2026-10-25；当前步骤及验收归[启动专项](../../development/wallpaper-startup-optimization-plan.md#p7整体验收退役与收尾)，长期来源/退出边界归[启动合同](../architecture/scene-launch-responsiveness-contract.md)。本批只在任务副本和外部原工具观测；没有修改产品或长期测试、没有重建App，不授完整P2/P7或性能通过。

## 事前范围与唯一执行

`d26-pre-execution-scope.json`在编译/App/native之前已记录：没有适用于AV/WebM native workspace或完整产品启动的预登记绝对RAM上限。既有源长度、纹理解码/GPU与私有磁盘额度互相独立，不能借作全进程RAM门；本次只取得绝对观察与原行为事实，不从测后数字倒设阈值。

原`test_scene_video_segment_materialization`的生成WebM夹具方法沿12份实际Swift输入编译，AST提取原HARNESS/CARRIERS，不import原测试、不触发setup或ffmpeg。输入直接复用受保护D8生成VP9 WebM，238,352B、320×180、130帧/17ms，SHA`9923799c693bc0563f5c82ee9e7ec9569e86684c28c25ed27a729e5a20ed7faf`。仅任务副本在原SegmentSink锁内累计整数，在原完成后输出一次；两份Swift去观测markers逐字恢复原源码。一次`-O -whole-module-optimization`编译和一次native均exit0、无timeout；原20秒child、30秒writer及全部5项播放/解码/PTS与duration/精确seek/磁盘计费事实保留并成立，执行后STOP，未重采。

## Native数值及其边界

同一PID94058/启动身份的`proc_pid_rusage(RUSAGE_INFO_V4)`五点均成功；下表是截至查询时的**进程lifetime max physical footprint**，不是该阶段独占分配量。

| 原执行边界 | lifetime高水位B |
|---|---:|
| main入口、payload读取前 | 2,064,912 |
| 原payload及fixture metadata parse后 | 2,523,664 |
| 原remux完成、AV reader前 | 5,718,640 |
| 原decoded与compressed timing readers后 | 8,700,624 |
| 原seek及完整output readback返回后 | 8,700,624 |

最后高水位约8.29756MiB。原fixture先parse，原writeWebM再parse；两reader、精确seek、末尾完整output Data读取/fragment扫描及任务观测开销均计入进程。不能将此数称为产品独占workspace、GPU/系统总量、无额外拷贝或最大合法输入/长GOP的上界；lifetime高水位的阶段差也不是独占内存成本。

原closed/failure guard之后、finish之前接纳的callback共4次，其中initialization1、separable3；Data.count合计238,802B，最大单次108,561B，合计与实际输出及原磁盘reserved字节核等。该计数不包含guard拒绝、framework内排队或尚未到达delegate的Data，不等于AV内部缓冲峰值；原磁盘账本没有被重新解释成RAM预算。

## 实际R3普通App观察

复用D24最终R3签名App，原构建receipt SHA`20eacd1d6e4ab0b8f6bcb0521c7f1618d31163661af3798cbae845eed33e9333`，exe SHA`fc02305c1f335189e747ba83af0fc3d951e6729b50fbed588c1902c9366b5b42`，CDHash`b9f38f9fb87be1f15853c9a1662c0333bb5ca9bf`。隔离普通UI只选择一次3750342273，request/session、首GPU完成→activated→launched→父产品commit唯一对应；11个原隔离/来源/偏好/签名/退出守卫成立。普通退出前未强制清理，`beforeCleanup.parentExitCode`和`processCleanup.exitCode`均0，owned子进程已退出。报告没有顶层exitCode，不将正常退出换成typed GPU/AV drain。

| 独立进程身份 | 成功/失败查询 | 观察到的lifetime最高footprintB |
|---|---:|---:|
| 父App93448 | 632/0 | 123,454,664（约117.73554MiB） |
| 原可选Web预备93473 | 144/1 | 11,502,336 |
| Scene daemon93933 | 41/1 | 311,149,672（约296.73545MiB） |

819次查询中817次成功；两个末次错误均为已观察child退出后的ESRCH，原错误/null保留，不填0或声称全部API成功。成功查询的PID/lstart、kernel start/UUID均一致。App过程约139秒，kernel观察跨度138.03564秒，含约两分钟GUI选取等待、早期可选Web预备及后续工作；不是20秒运行或selection→首帧独占窗口。各进程lifetime峰值不能相加成同时总量，最后成功查询后到实际退出之间、短命helper与独立系统AV进程也不由本次完整覆盖。375是Sound输入，本次App并没有证明WebM remux的整产品峰值。

## 保留的未验与证据入口

本轮没有before/current内存对照或预登记绝对RAM门，故**峰值预算未验收**。如要评价原预算目标，先按最低支持设备、允许并发和系统余量定政策，冻结metric、窗口、输入覆盖，再取得同条件证据；不能抄本次MiB设阈值，也不因此新增全RSS ledger/watchdog/cache。原性能卡5%噪声、10%/非目标门不变，累计5/6噪声失败、Video交接完成正差及旧seek偶发归因未知均保留，未重采翻绿。真实OS睡眠唤醒、显示/bounds/resize和压力操作仍未执行；异步提问未答不当通过，STOP方案不算欠开发。

原native报告`d26-native-peak/execution-once/report.json` SHA`14d24148647f7e1f03c8cdb3c2a5b4f534921e092cc86ae8d821bcd6dd234d90`，App报告`d26-startup-peak-ui/report.json` SHA`7ca8293467dfadb56e0ec0da199f7c83dcc19998d5e6a34c583381fe9ebe47f9`。实际命令、二进制摘要及raw stdout/stderr、12源/模式及输入前后SHA、五点/819query原件均保留；native结果独审SHA`f857c4f32738736364c4dab91cd8f9a957aa4fbc2301309440c9eb7a6b348d25`，App结果独审SHA`b3757d3be467107f42ba6c382bef2cef148f2bd5b3d7108f8f5f17c2fcabf6fb`。

保护入口拟为`.artifacts/scene-evidence/runs/wallpaper-startup-scene-d26-20261025-checkpoint`；晋升、完整性与精确已停产物清理按Root后续实际收据结算，此处不预写成功或数量。原产品/测试及一份R3 DerivedData未因本批改变，未暂存、提交、推送或发布。
