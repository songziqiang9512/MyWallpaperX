# D8：可信 package 挂载、媒体磁盘预算与真实入口

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**

> 截止：2026-10-24。本文保存本批过程与限定证据，不决定后续任务。现役顺序归[启动专项](../../development/wallpaper-startup-optimization-plan.md)，长期职责归[启动合同](../architecture/scene-launch-responsiveness-contract.md)与[源码职责图](../architecture/runtime-as-built-map.md)。后续实现尚未提交。

## 本批改变

原库事务在同一次复制/FD 校验中生成 receipt，经原 canonical publication 发布完整版本；没有建立第二库、租约或来源 owner。父端原 service 捕获具体 generation、完整 commit、receipt 与原 lease，经原请求、Shell、IPC 交给 SourceFacts。managed 请求要求当前 transport 的 source schema 能力，旧 child 不能忽略来源字段后继续执行。属性请求沿同一准入，原 Request/Task 持租约到后台工作实际 join；managed 属性 memo 暂不复用。

有可信 receipt 时，原 ResourceView 挂同一 package Reader/FD，完整表负责 literal namespace，实际消费的 entry 核预期摘要后发布。Host 不再要求展开目录 URL。无 ref 的旧 managed 先完整核原作者树，再把同次认证的不可变 package bytes 交原 extractor；这一路仍有全读/展开成本。已有 ref 却失配必须拒绝，不能降回无 ref 路径或低优先级 Root。

package 的纹理身份贯穿原 Loader、candidate、provider publication 与 direct draw，不伪造作者文件 URL。目录 ordinary index 保原隐藏/package-descendant 语义；package 的完整 raw 表与 ordinary 可见投影分开。真实消费者暴露的大小写 subtree、未承诺普通 missing、缓存被不同来源填入后的认证问题均在原 Root 修正，未按样本选择算法。authenticated loose cache 命中前仍核预期 bytes，性能数据包含此成本。

私有媒体仍归原 OwnedFile。8GiB 进程磁盘账本覆盖 Sound、外部视频、TEX MP4 和 WebM 的预约、partial、已发布文件与实际最后借用。已知长度在首次 payload 读取/写入前预约；WebM 保原 VP9 passthrough，以公开 AVAssetWriter segment delegate 将输出逐段预约后写入受控 FD。保原活跃播放、seek/clock 与 stop 时交接，未增加播放器或资源 registry。磁盘账本不等于 AV 内部 workspace/RSS 上界，也不证明 decoder drain。

## 实际身份与验证

直接前驱是本轮开始前保留的实际 D7 App，exe `725b8e9c23edc4d92fc16a513042235981bc9cd7494945bde05ce356b50ad766`；候选 exe `677026821eec6ed98acd9c23bf311fa9b8f996e6affd14edf3059ef43fa42658`。双方均为同配置的签名 Debug.Startup，2.11.0(283)。候选 Debug 构建 366.925 秒，构建前后 5925 输入不变，深度严格签名验证通过；源码清单摘要 `0c8ac5152075d2c0f5289f7d76ebe3ba29372bbf5df43df29afbe768fdeb9d07`。

构建后产品文件唯一差异是一行 AVAssetWriterDelegate 外部回调的 inventory 注释，移除该精确注释后 SHA 仍等于已构建/媒体门的 `9721f562…16644`。这不是重新构建记录，也不冒称当前所有文件字节仍等于构建清单；事实归 `d8-framework-callback-annotation.json`。

最近门分别保留实际来源清单与原始结果，不将重复运行相加：

| 范围 | 限定结果 | 原始资格入口 |
|---|---|---|
| 原库事务、出版与 receipt | 56 方法通过 | `d8-library-cpu-v1.json` |
| package Reader/Root、真实 Loader、shader 与 Metal publication | 39 方法通过 | `d8-resource-final-tests.json` |
| 父端准入、lease、属性与传输 | 13 方法通过 | `d8-consumer-final-source-v1.json` |
| 媒体预算、VP9、实际 Sound/AV 借用 | 48 个独立方法分批通过 | `d8-media-budget-cpu-v3/`、`v4/`、`v5/` |
| 原 async launch 与 daemon protocol | 13+4 方法通过 | `d8-main-nearest-results-current.json`、`d8-protocol-module.log` |
| 当前完整 SourceFacts 纵链 | 原 2 方法通过，17 完整性/取消/lazy 与 6 旧 managed 反例成立 | `d8-sourcefacts-final-v6-qualification.json` |

SourceFacts 当前全投影与等价目录及保留的合格 D7 输出相等；最后一轮没有重新编译/运行 D7。更早 v2 原始对照确实编译并执行前驱与候选，二者证据分别保留。Swift6/default MainActor 严格类型检查通过。

原结构门从 12/15 修至 15/15：补九个真实职责文件的精确登记，修正迁移后的 FrameInputContract 路径，给已有三 case 的无行为结果枚举作一次来源绑定的窄分类。基线仍 66，全局扫描与增长拒绝保留，未把 R4/R5 完成值或被动结果当成新的执行 owner；反例继续拒绝方法、状态、额外 case、alias/extension 与登记篡改。最初失败 JSON/trace、中间 14/15 与最终结果保留；私有重试曾覆盖最初 runner log，该份原日志字节未保留，不冒称完整保全。事实归 `d8-structure-final.json`。代码行数、依赖、Scene defense、设计门及最终文档登记/健康门通过；不是全能力或性能验收。

真实 VP9 原 URL writer 与新 segment writer 均完成 130 帧解码、0.017 秒样本时长、2.21 秒总时长及 ImageGenerator/AVPlayerVideoOutput 精确前后 seek。首轮 unittest 的 64×48 失败日志保留，测试临时媒体已删除；后继同配方诊断的输入与两 writer 容器另行保留，两端都触发同平台 decoder malfunction，不能称这些媒体与首轮字节相同，或写成仅新容器失败。BGRA 解码样本的 duration 无效不用于时长证明，最终改从原 compressed sample timing 观察，未放宽时长或 seek 断言。

## 产品入口、属性与输出

先用轻量原包作一轮真实 setAsWallpaper：6 次 App 启动、8 次设置请求均通过。随后较大真实内容 `3750342273` 经同一个原 importer 分别发布到两份隔离库，作者事实一致、generation 独立；导入不在计时窗内。五组 AB/BA 交替，每 arm 保持连续 C0/C1/W0。30 次 App 启动、40 次设置请求均完成真实 presented 与父端 finalize，正常退出且 owned children 清零。候选每条 native row 的 admittedSource 与具体发布 source.json 的类型和值严格一致，仅 rootURL 规范化物理路径；旧 D7 无该观测，不声称观察到其 IPC 来源。

| 条件 | 前驱首帧中位 ms（范围） | 候选首帧中位 ms（范围） | 基线噪声 |
|---|---|---|---|
| C0 新 HOME/新进程 | 1822.771（1605.391–2107.327） | 1635.165（1592.075–1987.620） | 15.61% |
| C1 同 HOME/新进程 | 1152.654（1079.399–1314.807） | 1034.191（1029.043–1092.807） | 14.07% |
| W0 同 daemon 重设 | 303.161（281.231–365.108） | 262.259（257.667–314.266） | 20.43% |

**三条件都超过原 5% 噪声门，不认正式提速或无性能回退。** 所有原点保留，没有删除慢点、补跑至绿或放宽门。C0 只表示产品 HOME 为空，未清 OS 页缓存。五份前驱 HOME 留下 140 个展开缓存文件、262,680,990 字节，候选五份没有展开完成 marker/payload；这是存留产物观察，不是 syscall 写入量。原始结果及逐点/配对分析归 `d8-managed-heavy-comparison-five/report.json` 与 `d8-managed-heavy-five-analysis.json`。

实际普通 UI 使用原隔离 guard 与现有参数组合，无自动 runner：已下载→详情→属性调节。无属性的 900000003 只能证明路由；同一已资格自建 package 中真实绑定的 amount=0.6 滑块、enabled=1 开关则两次打开均出现，原属性准备成功形成可编辑模型。未改属性值，不声称实际 live 像素变化。双方 UI 均真实 Cmd-Q，wrapper 验正常退出、签名、来源三文件与正式偏好不变。观察归 `d8-ui-properties-observation.json`。

另用原 daemon stdin 协议补独立执行端 GPU 资格：load→prepared→commit→实际 presented→两次 capture→shutdown。前驱 rendered 27→57、候选 22→52，双方原始 exited 均 code=0/gpuDrained=true、进程退出0，所有源和出版字节不变。四张图都显示山体、雪雾及中央日期/时钟；相位未锁，不认像素或精确相邻帧等价。这不是同一父端产品请求，不证明 parent lease 或 AV drain。首次 wrapper 使用小写 UUID 导致错过 Swift 大写事件，未 commit 而触原 watchdog；仅修观察身份后换全新输出，原失败保留，未改产品。结论归 `d8-managed-daemon-gpu-assessment.json`。

## 未关闭与后续边界

- D7 repeated-video 原 6 方法中的一次 `discard-after` 失败仍未分类，两处 await 共用文案。D8 仅前驱/当前各执行一次分相位 probe：都保住 discard 后 cache 并通过原像素/纹理/generation 断言；未复现不等于修复，不以新 VP9 门关闭旧门。
- 正常库发布原服务会拒绝仍有旧 lease 的 generation，随后原 reclamation gate 再核，未发现 D8 新增的可达 loose 目录换源缺口。绕过服务强换目录不在此结论内，Root 不会跟随 retired 目录。
- 旧 managed 持久 receipt 迁移、跨 provider 同内容文件共享、native workspace/峰值与稳态资源、D4 残余、Web C1 归因和 P3–P7 整体门仍开放。此次不作全 Scene、Release、多屏、最低设备或官方像素一致结论。

最终小报告、原日志、必要图片及失败最小材料沿产物规则提取到 `.artifacts/scene-evidence/runs/wallpaper-startup-scene-d8-20261024-checkpoint/`；精确清理与最终治理资格由该包收据说明。连续迭代仅保留任务根的一份 DerivedData；实际 before App/source 与唯一未解 seek 材料继续保留供后续回归。Git 改动全部未暂存、未提交、未推送。
