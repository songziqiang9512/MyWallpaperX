<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**

# 壁纸启动首批：测量校准、固定索引与原生窗口配置

> 截止：2026-10-24。本文记录本批校准故障、有效基线及 P3a/P0b 有界机制；后续步骤和裁决归[启动专项](../../development/wallpaper-startup-optimization-plan.md)。测量资格、局部减工与正式性能卡验收分别结算，不认领专项完成。

## 本批改变

原 Scene benchmark 默认 direct Host，不能覆盖设置入口之前的准备和产品切换事务；Web 旧观测混入提交后的轮询延迟。现在沿现有 Debug runner 逐轮调用 `SteamWorkshopService.setAsWallpaper`：Scene 绑定 ticket/request/execution、真实 presented payload 及父端 finalize；Web 绑定产品 intent epoch、execution 和原 `Session.committedAt`。观测不提交、激活或发布输出。

统一脚本 `script/wallpaper_startup_benchmark.py` 固定签名 App、样本路径和条件，核输入前后摘要，记录原始运行、实际 HOME/cache、父子进程及退出结果。Scene 同进程暖必须同 daemon PID/generation。Web 每个 App 序列的第一项只建立 active，不计 W0；后六次设置属于同组相关观测，不能称为六个独立 App 样本。

Release 不启用这些观测；没有安装、替换生产 App，也没有提交本批实现。最初方案文档已按用户要求提交 `ae0ac798c`；实现始于该提交的干净独立工作树。

## 偏好隔离故障与修正

首次校准错误地把 `HOME` / `CFFIXED_USER_HOME` 当作 `UserDefaults.standard` 隔离保证。实测 Foundation 文件目录虽已隔离，标准偏好仍写入生产 bundle 域。因此首轮生产身份报告全部作废，只保留故障诊断，不参与前后性能对比。

用户确认原帧率 30 FPS、未暂停，且不记得原壁纸，授权恢复默认偏好。已重置播放选择、恢复默认静音、保留 30 FPS 与播放状态；没有清空媒体库。修复收据只含变更键名和摘要，私有偏好备份只留任务临时目录，不进入仓库或证据包。

新的资格同时要求：

- 签名与 Info.plist 均是专用 `com.songziqiang.MyWallpaperX.Debug.Startup`；产品装配前读回独立标准域随机哨兵，并核实际 HOME、Library、cache、workshop 和 report 路径。
- 每组 C0 通过 defaults API 清空并验证测试标准域；C1/W0 保留，组结束后清理；Steam Debug suite 仍独立。不能以删除临时 HOME 代替标准域清理。
- 每套运行前后同时比较生产偏好语义和磁盘摘要，任何变化均使整套失败；不输出偏好私有值。
- 清除继承的 `MWX_` / `MYWALLPAPERX_` 运行覆盖，记录被移除的变量名；两个 Scene shader 缓存门仅在 DEBUG 为精确测试身份开放原隔离 HOME 路径。

独立身份的权限状态与生产 App 不等价；没有以关闭作者音频来消除慢点。错误哨兵与 HOME 不一致的签名 App 实测均在产品装配前拒绝、没有生成成功报告，生产偏好前后不变。

独审另发现漏写 Scene report、混用 Web/Scene report，以及专用测试 App 普通启动的入口缺口；已用统一 Scene intent 谓词、互斥测量 lane 和专用身份入口限制修正。最终签名候选的六项真实反例均在装配前拒绝：裸测试 App、Web/Scene 只有 mode、错误哨兵、HOME 不一致、混合 lane。原 runner 继续拥有完整参数语法，不增加第二套解析 owner。异常路径会先核对/清理已知自有进程，再清测试偏好；无法确认退出时保留失败域及环境，并仍复核生产双摘要。

## 有效输入与身份

| 项目 | 固定值 / 范围 |
|---|---|
| 基线 App | `2.11.0 (283)`；专用测试 bundle；Team `H9QWU9XN8R` |
| executable SHA-256 | `5772f34e22c55f237fa2f36e3baeef84f9c981c6435ad595fda3473a03a5bc18` |
| CDHash | `09f89d629fa8060a5c3dc15e26c690ae5a6e6778` |
| 构建 | Xcode 27.1；签名 Debug，`-O` / wholemodule / 无 Debug dylib；构建前后 Git 可见输入摘要相同 |
| 帧率 / 策略 | 30 FPS；隔离偏好内关闭四种自动暂停条件，其他设置为默认；无额外截图开销 |
| Scene | `3766415113` 隔离副本，9 个计入摘要的文件，1,563,992 bytes；SHA-256 `ae7dbbabb154044742d749bd199f0ede0e4cc29003559681de3f000bbac21c3b` |
| Web | 自有独立 HTML fixture `900000001`；CSS 动画，无音频需求；不是作者样本兼容验收 |
| 条件 | 每引擎 5 组；每组 C0 新 HOME/标准域、新 App，C1 同 HOME/标准域的新 App，W0 同 App 序列 |
| 系统 | 未清 OS 页缓存；输入摘要在启动前读取文件；WebKit PID/内部缓存冷暖未知 |

Scene 此输入由普通 record 走 legacy root，不具有 managed commit receipt/版本租约；不能用它证明后续 P2 managed 完整性或 GC 安全。用户原始媒体只读，所有产品运行使用临时副本。

## 当前有效数值

主指标以 ms 计；Scene 为设置入口至 daemon 实际 presented 时间，Web 为设置入口至父端 Host finalize。Web 不称屏幕物理呈现。以下全部保留原慢点；没有热身删点，也没有放宽性能卡噪声阈值。

| 引擎 / 条件 | 观测数 | 中位 | 范围 | 最大偏离中位 / 中位 |
|---|---:|---:|---:|---:|
| Scene C0 | 5 | 1115.758 | 1061.523–1434.611 | 28.577% |
| Scene C1 | 5 | 894.249 | 871.025–925.033 | 3.442% |
| Scene W0 | 5 | 207.891 | 204.322–210.550 | 1.717% |
| Web C0 | 5 | 1068.710 | 877.064–1115.030 | 17.932% |
| Web C1 | 5 | 925.722 | 903.054–1105.688 | 19.441% |
| Web W0 | 30，来自 5 个 App | 482.713 | 281.469–496.735 | 41.690% |

Web 五个 App 的 W0 组内中位分别为 480.682、484.603、489.347、459.983、486.592 ms。这些分组信息保留相关性，不能用合并 30 项掩盖快慢两类路径。Scene C1/W0 在本批通过 5% 噪声筛；Scene C0 和 Web 各条件只具测量/故障定位资格，尚不能支撑普通前后提速比例结论。

两引擎各 15 次 App 运行均正常退出，已观察的自有子进程没有残留；标准域哨兵、输入摘要和生产偏好双摘要检查通过。WebKit 系统进程未归属确认，不能把它们填作零或宣称所有 WebKit 状态退出。

## 首断点与顺序修订

Scene 的实际日志表明：C0/C1 设置至 accepted 中位约 666/669 ms，同进程约 0.65 ms；模型阶段约 156–161 ms。C0 首轮额外等待主要出现在 program/setup 和 surface 激活，资源阶段相对稳定。不能把整个模型时间归给 stock 索引，也不能将这些嵌套区间机械相加。当前能可靠比较的是 C1/W0；后续应在原 owner 内证明每项减少的实际工作。

Web 独立无音频 fixture 的资格运行也出现 288–500 ms 的 W0 波动，六轮均采用预启动 daemon。慢四轮的 prepared→activationConfirmed 为 236–242 ms，快两轮为 17–30 ms；activationConfirmed→父端 finalize 为 4–8 ms。因此不能先把长尾归给音频、依赖扫描或进程新建。

准备完成后的激活门依次涉及旧 active 的原生输出暂停 ACK、candidate 原生媒体策略 ACK，以及 WindowServer 可见/几何/层级/alpha 确认。准备前已有 host ready、1×1 afterScreenUpdates snapshot 和准备态媒体 ACK，但 ready 不保证作者异步任务与全部子资源结束。本轮随后补齐同 candidate 的发送、接收、策略确认与首次可见时间，区分三个门；没有省略确认、提前 ready 或用更宽 timeout 获利。

补充的 schema 3 已在真实产品路径资格通过，9 个请求的子端时间均匹配 activation identity。W0 慢轮 prepared→父端发送低于 1 ms、发送→子端接受低于 0.2 ms，原生媒体 ACK 约18–21 ms；首次可见确认约230–239 ms，首次 retry 全为 `window-target-geometry-mismatch`。快轮约27 ms 即确认，说明本输入的主要差异位于窗口几何确认；这些是采样时刻，不是物理呈现。不能再将其归为旧输出 ACK 或音频，亦不能仅凭 reason 断言默认展示动画；后续短实验保留全部确认门。C0 这轮出现2628 ms原点，仍保留，不混入原五组分布或删除。

## P3a：首个独立改造与前后对比

依据稳定 W0 模型成本，先将原 ResourceView 中 App 自带固定 stock 的完整 Root/index/lookup 共享一份，未提前实施包挂载或模型缓存。唯一成功槽受原 owner 的锁保护，按当前 Locale 值匹配；并发首次访问只构建一次。package/loose 和显式 custom stock 每次重建；枚举/metadata 不完整只用于本次原 best-effort 路径，不登记成功。没有 mtime 身份、后台 watcher、属性/VM/grant/lease/GPU 状态缓存。

候选 executable SHA-256 为 `650201350a25d6a3a2cd1c5445974af70358fa3ba3ce06e7628a994f6eed36d3`，CDHash `d5e3ac17cb61486caa5273f57821b1ca5edf723d`，仍为相同专用身份/版本/签名优化 Debug。构建耗时333.955秒、前后源码摘要一致。一次构建合入 P0 安全修正、Web 被动分段和 P3a，Scene 的行为变化只有 stock 索引共享；基线 App 已冻结。

统一脚本支持 `--baseline-app`；两 App 各 stage 一次，每组交替先后，各自 C0/C1/W0 连续执行、独立 HOME/suite。五组固定 Scene 输入比较如下：

| 条件 | baseline 中位 / 范围 ms | candidate 中位 / 范围 ms | 中位变化 | baseline / candidate 噪声 |
|---|---:|---:|---:|---:|
| C0 | 1143.688 / 1085.634–1489.473 | 1169.062 / 1075.449–1210.461 | +2.219% | 30.234% / 8.008% |
| C1 | 880.508 / 870.254–926.677 | 893.268 / 879.192–924.274 | +1.449% | 5.243% / 3.471% |
| W0 | 212.843 / 205.801–225.771 | 67.727 / 64.961–68.612 | −145.116 ms，−68.180% | 6.074% / 4.084% |

W0 父端 finalize 中位213.197→68.030 ms；模型分段159.069→12.706 ms，worker `model-build` 也由156–174降至12–14 ms。资源分段18.519→18.713 ms、surface→launched 24.847→26.756 ms，首帧仍完成原门；减少的是重复索引工作。30 次 App 运行、40 个请求均通过资格与退出检查，两臂既有 `source-domain-variant-dependent` 降级均20次，没有新增记录失败；生产双摘要及输入摘要不变。

**结算：** 保留已证的同进程局部减工及本次实测数值；baseline W0 噪声6.074%超过原5%门，不删点、不放宽门，不能称正式性能卡整体通过。C0/C1 没有证明提速，也不能由上述中位涨幅与高噪声推导普遍回退。后续专项终验仍须按原门结算原始、直接前驱与最终版本。

未参与修复的 `3141421197` 另作一组健康对比，六次 App / 八个请求均成功且退出干净，W0 观测233.460→123.954 ms。只有一组，不给性能统计结论，也不替代完整视觉/能力验收。

## P0b：Web 原生窗口配置与剩余长尾

外部 task-local 采样器仅查询本任务 staged App 内的精确进程，记录窗口矩形/层级/alpha/在屏状态，不记录标题或其他 App 内容。旧版本七轮均有连续缩放与过冲；目标为 `(0,0,1512,982)`，一轮先短暂到达目标、随后变为 `(-1,-1,1514,984)` 再回落。另一快轮已在过冲前确认。这证明只加重试或放宽阈值不能保证提交后的几何稳定。

产品变化只有现 `makeSurface` 内首次显示前的 `window.animationBehavior = .none`。它关闭原生桌面窗口的自动展示/隐藏动画，未改变作者 CSS/JS/RAF、窗口 frame/level/Space/alpha、WKWebView、旧输出暂停屏障、当前媒体 ACK、精确可见确认和50ms重试。候选短实验七轮的2127个在屏观测均保持完整目标矩形及alpha 1；前六轮覆盖 finalize 后3.32–3.48秒，最后一轮仅16ms。该外部诊断带额外开销，不混入正式计时。

最终候选 executable SHA-256 `d2f8da18e69dfb220bd8cc5f14aaa080100a178b912fc63414211aef1b4c5057`，CDHash `b777b797e7ee7337bf56caddefe4e4b38df8b16c`；专用签名/版本/优化配置同前，构建326.919秒，构建前后源码摘要一致。直接前驱为 P3a 的 `650201…`，两者的产品行为差异仅上述窗口配置。

五组交替运行，每臂 C0/C1 各五个 App，W0 为五个 App 内的30次相关选择。主指标仍是父端原 finalize，不称屏幕物理呈现：

| 条件 | 前驱中位 / 范围 ms | 候选中位 / 范围 ms | 本次观测中位变化 | 前驱 / 候选噪声 |
|---|---:|---:|---:|---:|
| C0 | 1097.519 / 906.133–1100.411 | 878.772 / 853.012–900.368 | −19.931% | 17.438% / 2.931% |
| C1 | 1071.409 / 1030.138–1192.853 | 893.401 / 862.916–899.594 | −16.614% | 11.335% / 3.412% |
| W0 | 489.287 / 282.074–500.856 | 268.349 / 261.833–600.186 | −45.155% | 42.350% / 123.659% |

两臂各45行子端观测均与当前 activation 匹配；几何 retry 由45/45降为0/45，W0 原生媒体 ACK 中位20.637→20.366ms，父端均在当前 ACK 后接受确认。各15次 App 均正常退出、自有子进程无残留；输入与生产偏好双摘要不变。保留“几何等待消除、本次中位数改善”的有界结论；原噪声门未全过，不能泛化为整体提速保证或正式性能卡通过。

**600.186ms 原点未解决：** 候选第5组 W0 index 1 的 selection→prepared 为573.875ms；prepared→发送0.980ms、发送→子端0.163ms，子端→可见19.147ms、当前媒体 ACK 19.370ms。既有 daemon 已采用、hello 早于 selection 388.55ms，日志 process 阶段为0，无几何 retry。因此能排除本次窗口等待复发与新建 daemon，尚不能继续归因 IO/WebKit。此前臂未出现同一慢点；既不能称已证的新回归，也不能将其注销成旧噪声。保留原始整组与原点日志，下轮从原 prepare owner 分段，不另建准备 owner。

Scene 另做两轮只读几何查漏，未见 Web 式连续缩放；所有非零矩形均为完整目标。采样中位间隔9.852ms、最大17.566ms，首次完整在屏观测在 presented 后约5/11ms，不能证明精确 presented 瞬间。旧270ms surface 慢点未复现，未据此给 Scene 套用 Web 配置。

真实作者 Web `1103493745` 的隔离副本另跑七次设置，并在用户播放音乐时使用原连续性观测。实际系统采集启动、75帧非静音频谱全部到达作者页面，其中74帧变化；一次2.5秒窗口内页面152帧、最大间隔18ms，暂停转换0。七次设置均提交、App及已知子进程正常退出，生产偏好不变。系统授权在该次实际运行可用，不推断永久 TCC 状态；单一作者与短窗口不替代完整音频/长期稳态验收。

## 验证与未覆盖

已通过签名优化 Debug 构建；6 个最近模块通过：统一脚本资格反例、Scene startup reducer、实际 daemon switch 取消与 stale 回调、产品入口隔离策略、shader 缓存门、Release diagnostic 隔离。其中 shader 门为结构检查，不能称为完整 shader cache 性能验证。

P3a 的真实 ResourceView fixture 8项通过，覆盖32路并发、完整 namespace 对照、优先级退回、custom 修改/删除/改名、不完整恢复和默认根外部重定向。实际 Catalog、stock material、stock noise 与 Release 隔离模块通过；Web endpoint 门覆盖普通/DEBUG/测量三条编译执行路径、错身份、producer time 保真及观测无提交权。测试不模拟同进程系统 Locale 切换，也没有单独注入 metadata-only 故障；完整 App build 验证实际 MainActor 配置。文档路由、设计、代码行数、依赖与防御面门通过。

P0b 实际签名构建、短窗口轨迹、五组交替、真实作者音频与既有 playback visibility 门通过。未为一行配置添加只镜像源码形状的测试；CG结构轨迹验证的是原生窗口机制，不代表全部作者视觉/物理显示时刻。

本批未证明：字节/CPU/Metal 创建计数、managed 资源路径、全部作者音频及 Scene 能力、双屏/最低设备、跨引擎六方向、Release 运行及最终 30 分钟稳态；Web prepared 前长尾仍未闭合。后续按目标阶段触达相应输入，不为 P0 扩全量矩阵。

本机证据由正式 promoter 提取到忽略目录：普通包 [.artifacts/scene-evidence/runs/wallpaper-startup-p0-p3a-20261024](../../../.artifacts/scene-evidence/runs/wallpaper-startup-p0-p3a-20261024/batch/report.json)，默认保留14天，约13.1MB。入口的 `samples.label` 保留原路径，数值 `id` 映射 manifest 中已提取文件；`p0-isolated-*` 是有效基线，`p3a-scene-*` / `p0b-web-comparison` 是完整交替对比，另含真实反例、几何轨迹、音频和三次有效构建日志/源码身份。早期生产身份报告明确标为 `measurementEligible=false`，旧 `passed` 字段不能恢复其资格。没有提取私有偏好值、媒体、App、HOME 或缓存。

未解决 Web prepared 长尾的整批原始点、对应 W0 native/app.log 和构建身份另有[保护包](../../../.artifacts/scene-evidence/runs/wallpaper-startup-web-prepare-unresolved-20261024/slow-web-prepare/report.json)，约2.5MB，带明确 `protect-reason`，不自动到期；归因或修复后重提普通包再退役。两包逐文件摘要复核通过后，已删除37项停止使用的临时测试目录/日志与未使用输入，约20.2MB，精确收据在 `/private/tmp/mwx-startup-optimization-fbRhFY/batch-cleanup-receipt.json`。独审没有新增代码阻断。

持续专项仍保留任务根 `/private/tmp/mwx-startup-optimization-fbRhFY/` 中唯一 `DerivedData`（最新候选）、`p0-baseline-app`（原有效基线）、`p3a-baseline-app`（Web直接前驱）和已取得资格的固定路径 Scene/Web/fixture 副本，供下一批及专项最终比较；停止使用后逐项清理。私有恢复备份仅在该根留待审核，权限0600，不在证据包中。本批没有安装 App、暂存、提交或推送；goal 继续进行，P1/P2及其余采用阶段尚未完成。
