# Scene 启动 D25：交接完成成本、STOP与有限GUI/Web补证

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。截止2026-10-25；当前步骤归[启动专项](../../development/wallpaper-startup-optimization-plan.md#p7整体验收退役与收尾)。本批先只读审计，随后复用未改产品的R3签名App做普通GUI与原政策入口补证；未改产品/测试或重建App。有限运行不等于完整P7或性能通过。

## 39ms属于哪个边界

复核受保护D23c与D22共同harness的10个原App记录；16个相关当前源逐项等实际D23c source map，原native/app.log SHA核等。Video原可见事件先经activation/preparation/display/PID和WindowServer证据确认，再同步进入Manager事务：先commit新产品投影，再退休旧Scene。故Video已经visible，Manager的pendingWallpaper已清、current/runtime/isPlaying已投影；这不等于全部后续UI/引擎事实都已完成。

旧Scene barrier结清后，原transaction.retired才同步调用新Video endpoint.finalize。Engine在此采用activeVideoExecution/finalized/currentContentKind/currentContentPath并发布playbackReadyNotification；下载页播放态依这些晚投影，Manager随后补一次objectWillChange。Library grid另读pending-or-current选择；setAsWallpaper本身是Void，没有统一等待回调。因此+38.713ms是**Video entry→旧端交接完成/finalized被发现**的配对正差，不能改称首画延迟，也不能因已有画面就抹去合同包含的finalize成本。

父端强ACK验证匹配operation/request/generation/transport及显式accepted/requestRetired后，control completion→Manager.retired→endpoint.finalize为原同栈处理；30秒idle timer只注册、不等待。原runner每20ms检查已经finalized的事实，强ACK→发现五点为2.262/10.190/2.702/8.475/5.875ms（中位5.875ms），是含处理和发现的合窗，不是额外产品等待。不能将其或独立分段中位从+38.713ms直接相减归因。

原wire whitelist没有保存audioSpectrumDemandChanged，app.log也没有no-demand收件时间。Child当前none检查和FIFO次序仍成立，但已有none会抑制重复事件；不能从缺日志造none→ACK耗时或判失败。Session资源事件→强ACK的21.877–40.019ms含原launch queue/main/Session fence、实际窗口确认/25ms重试、writer/pipe与父main，缺child fence/首次CG结果。D22以真实进程exit/EOF结清，候选以精确请求成功退役保留空进程；产品屏障义务相同，物理终态不同，不可把两者内部阶段当同一测点。

三份边界复核没有发现可安全删除的等待。**STOP继续窗口并行化、父端微优化和额外被动诊断**；原安全门、CPU→GPU次序、lease、none-before-ACK、1s/2s及25ms边界不变。不为解释39ms新建owner/队列/clock，不跑额外五组或改轮询美化报表。之前仅准备的单次诊断方案保持未实施，不是新的前置欠账。

## P0–P7采用与停止结算

P0/P1的原隔离、内容捕获/纯产物/当前授权/取消join和P2的可信receipt、单Root package/loose、旧managed完整准入/按需升级及合法兼容物化已有各自原owner证据。D19仅实现活跃借用期间的package弱成功文件复用，第二次45.3MB条目0重复entry读写；并发miss各走原copy，目录/跨停播/跨进程及其他转换不扩，未实施single-flight不算欠开发。

P3保已测stock清单与两行noise循环减工；内容cache/额外排序、P4成功Metal共享、P5退休WebView/daemon协议、P6转换cache/稳定origin均按成本或安全边界STOP。采用的双端口cookie名与原store准确删除保留，迟到Set-Cookie不承诺drain。不能为了完成阶段表恢复无热点cache/池或删除合法builtin extractor。

D24最终R3已完成普通UI baseline375+20次314/375交替、1810.109秒同daemon稳态和自然Quit；原21个不同ticket/request/session与GPUcompleted→activated→launched→Managercommit及两个有限可见端点成立，不冒全FPS/typed AV drain或无泄漏。原始P0/D22/最终累计90App195请求功能守卫通过；P0→D24仅Scene C1通过双臂5%噪声，配对-85.281ms/-9.865%仍低于原10%目标，其余5/6噪声失败。D22→D24多数近似，无正式额外收益，整体性能/无回归保持未通过；不回溯关闭D19输入正差。原门槛、原点、慢点和失败全部保留。

## 新鲜普通GUI与真实Web功能补证

同一R3普通GUI本轮实际有10次Manager commit（4 Scene、4 Web、2 Video），10个不同ticket/execution且recovery均0；相邻顺序覆盖Scene/Web/Video六方向。4次Scene各有不同request/session的GPUcompleted→activated→launched→commit，离开时原session-retiring另记。实际CG截图元数据记录新端owned onscreen窗口；Video/ES模块Web两次短返仍为Scene85578及同lstart，离开commit至返回accepted约10.681/20.521秒，仅NSLog wallclock上下文，非新的TTL/性能测量。Manager票据、Scene request/session与Web request不是同一UUID；两Video无统一request日志，不补造“10个request”。普通GUI原11隔离守卫、CmdQ正常parent0/ownedchild0成立；没有typed退役ACK，不能把retiring/退出偷换为全AV drain。

真实作者1103493745的React to music、Show clock私有override为true，AX与属性图可见勾选，实际页面有时钟；该图名`standard-properties-after.png`实际为有效JPEG，保原bytes/错误后缀，不授PNG格式。ES模块作者3740867386的colorschema=GREEN与AX一致，实际before/after线框白→绿。8/34个作者文件的完整捕获facts分别与after核等；原GUI continuity标准有75非静音/74变化帧，而模块为0，所有请求pauseTransitions=0，故此run自身不授主动暂停或typedprofile。

另两次原政策入口有各12守卫与typedprofile：标准请求`2AC21315`为standard/customScheme/workshopPersistent，pauseTransitions1→2、末态paused1→0，页面非静音/变化为31/28；模块请求`36D0828A`为highCompatibility/httpLoopback/scopedPersistent，同样政策暂停/恢复但实音0。随后同一parent88075在Stop后由普通UI新开模块请求`68A091F2`、实际daemon88499，仍为typed高兼容/loopback/scoped，7个窗口各76 page/nonSilent、75 changed、151/152frames、pauseTransitions0。这是**分请求的政策暂停与实音证据**，不声称模块同一请求暂停前后都有实音。原输入未注入PCM；受控OS输出/原capture与页面counter对应，不授作者扬声器播放或独占音源。

两Debug App无有效主菜单CmdQ，实际通过public `NSRunningApplication.terminate`正常退出请求、parent0/ownedchild0及无强制fallback，不写成CmdQ；前述普通GUI的CmdQ另证。政策sleep/display/lock标签由现DEBUG入口注入，不是OS真睡眠/显示操作；F12注册/真正前台focus仍未验，不新列功能开发债。模块两请求原IMG `[object Object]`/local missing日志保留：空thumbnail对象与作者fallback交互可生成对象URL，4个相关源与受保护D22/D23c/D24R3逐SHA相同，当前missing不是cookie授权拒绝。未获同作者旧raw或失败DOM/JS栈，首次时间/唯一运行时归因及完整视觉影响未证，不默认作者锅、不扩本批修复。静态附录`d25-high-web-resource-error-appendix.json` SHA`acd4b5397c37e376782fec16380287b0b0377cabc58f1be28fa15cc19abef29d`。

## 真正余项与原范围

| 范围 | 已有事实 | 尚待，不能由已有事实代验 |
|---|---|---|
| native材料峰值 | 原Root/预算/AV借用、WebM解码/timing/seek/stop及磁盘quota有界通过 | native WebM workspace和启动峰值；quota、decoded reservation或30分钟RSS不是native峰值 |
| OS恢复 | R3 20切换/30min、自然退出；D25原政策入口暂停/恢复及普通GUI有限画面 | Scene真实surface bounds/resize、OS睡眠唤醒、系统压力/显示变化；D24 manual操作[]/恢复false，sysctl0/1970，压力模拟两次255拒绝均未代验 |

原要求允许最低设备、多屏或Release缺失时明确未验，不自动增加新平台/构建矩阵。六方向/作者Web补证按上述原请求分别结算，未复用历史文字代替新run；wrapper守卫不授全FPS、typed资源drain、整机无泄漏或全作者兼容。原累计性能门仍未通过，不为补证重跑五组追绿。

## 原件与已完成的D24收尾

本轮冻结的三份review为任务目录`d25-parent-handoff-review.json`（SHA`892f148bc9fdad8ffe5dad4d89626462f35e924a3fb5447b93a246302b23cd47`）、`d25-retirement-boundary-review.json`（`017a2d6ce95dbd37dd61c27ed519ab597633c1751e2407fa08a89e7478984d39`）、`d25-passive-diagnostic-design-review.json`（`b8b87f6c0e40d2d9bc8d2764ac3f037ed5f577378c18c9f8231d81ce84af8117`）。P0–P2、P3–P6、P7审计分别为`d25-completion-audit-p0-p2.json`、`d25-completion-audit-p3-p6.json`、`d25-completion-audit-p7.json`，原报告保各自完整输入/证据SHA；它们的范围不自动扩大为全部历史矩阵重跑。新补证独审为`d25-cross-runtime-ui-independent-review.json`（`f2902c8f6065b4f3170bc5c1c0e60ae8884b47ed508e61fed59d1b9b139b4e48`）及`d25-real-web-policy-independent-review.json`（`fd00545534ba8629eba88238d7594af30871aaeb941952d33fabe6cb15e152df`）；GUI report SHA`2addc6ba6bbd370ec93529de8ac12e43def8796c6d815f9409bcc26fe4f7757a`，两policy report为`4ad4d680505cddd6fc59c0ac12e945c410e137402a9ee8102c133955f898b5b0`、`71b4d8b92ac5c1396e0f4bbb95b14bef20b92d7ab69e12f8823a1595976a9578`。首版8文档及SHA完整保`d25-docs-gui-supplement-before`，初版审计不是后续运行已过的证据。

[D24历史](scene-startup-d24-2026-10-25.md)已有真实晋升与清理，不再列pending：主保护包`wallpaper-startup-scene-d24-20261025-checkpoint`有580payload/实际28,684,493B，原图包5payload/27,421,233B，分别低于32MiB并依赖受保护D23原件。两个manifest SHA分别为`cec45fe653106a01ffba90c269ccef40c3876d95b1a93fa80f03dbe0dd9aa6e8`、`5571d9588ca3ea0144f5adf2752a35b65e96a0e7eab3d04c9e6605b34a920e6b`；5957输入的四map/全部选定字节模式、319owned及别名已核。

`d24-cleanup-receipt.json`实际移除19个精确已停路径、2,399,112 allocatedKiB（不是APFS独占可回收量），保一份DerivedData及余项输入；`d24-post-cleanup-evidence-verification.json`通过。清理时owned process/选定open handle/staged path均空，未触peer或整个任务根；全部实现仍未提交、未推送/发布。D25产品/测试未改，新增运行原件与正文/治理由本批实际收尾记录；不能改写D24 immutable包或预授真实OS恢复/材料峰值成功。

本批原件计划保留入口为`.artifacts/scene-evidence/runs/wallpaper-startup-scene-d25-20261025-checkpoint`；此处不预授晋升、payload数、manifest SHA或清理完成，均以Root后续实际收据为准，不为归档反复改写本体。
