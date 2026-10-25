<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**

# Scene 启动 D6：Sound 私有快照与在途 CPU 退出

> 截止2026-10-24。步骤归[启动专项](../../development/wallpaper-startup-optimization-plan.md)，稳定边界归[启动合同](../architecture/scene-launch-responsiveness-contract.md)。本批闭合目录Sound及已迁CPU退出的限定行为，最终签名/产品资格通过；正式性能卡未过，不认无回退、提速或P2b完成。D4/D5历史时点不倒改。

## 原 owner、读写域与释放

Sound沿原Host launchPreparationQueue→Program→Registry迁移，不新增播放器、工作队列或全局缓存。作者handle在原Root同FD读核以最多64KiB块写排他0600私有文件，完整读取、来源核及close成功才发布；取消、换源、写失败清唯一partial，snapshot/stream共用读核，不按diagnosticPath重开。Program保candidate-first/roots、格式名单、Binding与random槽位/分布；选中普通不可用保unavailable，不转低根，硬错/取消拒候选并保旧active。同compile同源成功文件共享；原loop/single/random item工厂的实际AVURLAsset持文件pin，Program/Source先退不unlink，最后借用释放清文件。

字体Store与共享baseImages deferred在原锁内线性化关闭、入队与原queue尾fence。连续文字值保单在途/追最新；每屏退休等字体、GPU及已有export。全clearContext在清launchContext前将deferred尾登记进原retiringSurfaceDrain，先stop后drain仍能等待；单屏重建不关闭共享owner。CPU/原退休group终态后提交最终surface GPU barrier；Host还等原launch队列尾，无Session也不能早回。主线程不wait，无新资源或退休owner，exited.gpuDrained仍仅原GPU含义。

存储首版把私有pool建在extractor.outputURL下，下一次精确validCache把它当extra，重建时绕过AV pin删除私有路径，并重复解包。实际旧源码/Host实参→真实Extractor/AV借用反例中，暖marker、暖私有bytes、重建后bytes、私有域分离及仅借用者仍保文件五字段均false。仅推断outputURL父目录的中间方案又会在普通failed report的合法loose场景写作者目录，未构建即被替代。最终只读暴露原Extractor.cacheRootURL，由Host显式传Program.privateCacheDirectory；Program不推断路径，原私有池与hash展开根并列，extractor精确校验不放宽。真实最终门15字段全true，含failed/missing loose仍选原来源且作者路径/bytes不变，暖marker保持、强制损坏重建不毁实际AV借用，最后释放才unlink。

这不授可信receipt或managed暖身份，不建立聚合磁盘预算，也不证明通用AV decoder/callback drain。Sound保原无bytes/duration上限，仅有界块分配和初始长度；其他嵌入/外部video仍有把extraction cacheDirectory作为私有文件base的存量风险，未由本次Sound纠偏关闭。

## actual-before、资格失败与最近门

实际D5-final三个CPU反例分别证明：无Session Host越过阻塞prepare队列；Session越过真实在途Store；deferred cancel返回时加载仍在途。首个Store probe漏动态字段未排任务，资格失败独立保留，补参数后才取有效反例。D6 v1独审再发现stop清context后丢共享deferred等待；真实Base/Teardown/Shutdown同输入before失败、修后等待成功，v1源码和日志均保留。

最终14模块去重**134方法、0 failure/error/skip**：最终四Sound模块新跑58，实际依赖SHA未变的非Sound76项复用，非14模块同批全跑或134项GPU。最终58项与337.577155s签名构建的完整5911文件来源均为`d34c5c0b463662e220aaa411211508ec953a4cee3558f16b49d0213271f56c93`，无build→validation delta。原133项聚合保留为存储纠偏前资格，不冒充最终源。最终聚合收据`d6-final-tests-v2.json` SHA `94d3a33c8e04bd6d16aee715bb0d175bfa2d22758e1f55ad4f75bf8ae1140647`。

原批结构门15项仍有3项失败：目录布局、render-chain inventory、声明完成状态；D5/D6当时诊断仅runner耗时不同。存储纠偏后复跑测试断言、依赖、code-health、defense、design五个相关静态门全部通过；未重新认定结构门，三个既有失败继续开放，baseline未放宽。

原Sound before49项通过；current的旧volume夹具API失败限定修复后单项重跑，不删原点。新AV首轮7/1失败因夹具尚持其他player/AV对象，最终将非借用对象限于autoreleasepool，仅借真实looper item.asset，保原file-held/final-unlink断言；产品未因此改动。codec夹具缺try、一次重复Suite setup资格失误另存，后者不作为before；实际v1独立二进制反例才作存储负门。最终58含新增真实Reader/Extractor/Facade→Root→Program→Registry/AV组合，不是Program替身消融。

原native15项有14通过、1失败：受控退休failure Proxy先等full-stop barrier才放退休handler，与新等待顺序形成夹具循环。构建终态后仅搬原6行wait块到deliver/finished之后，原断言不变；重跑shutdown2，复用dynamic13 mixed。Prepared16/Paused18/Host1早期PASS缺完整依赖map，保资格缺口，最终另跑35项捕获全Git双hash，不追造旧收据。最近门含CPU、QuickJS、CoreText、Metal raster/export、AppKit及真实AV；静音自有WAV/MP3/FLAC不等于实音PCM或扬声器验收。

## 冻结构建与产品输入资格

最终Debug/WMO构建通过，337.577155s，完整来源before/after为上述d34c；App executable为`4ab51c6954a9e653a8b1c0af3011a298103d168868d430eb7482a73cb8944077`。Startup身份com.songziqiang.MyWallpaperX.Debug.Startup，2.11.0(283)，Team H9QWU9XN8R，deep/strict验签有效。实际D5-final比较App为`32b7399ff09e9e1eb43ebbdcec38a5305135d6744d2feffc0373d3ce633183dc`。修正前App61bc/344.342361s及其a309来源收据保留，不能代表最终构建；原fixture-only资格变化不虚构成产品变动。

跨版本实际执行**162 App/216请求**：最终有效60/80、被替代的原候选60/80、目标无效正式/先导36/48、仅准入有效pilot6/8。首轮无效Sound场景漏必需startsilent（30/40）；首个pilot虽已补startsilent:false，但自有音频仍放audio/而原extractor只展开sounds/下的音频（6/8）。两类输入虽generic呈现/退出成功却均admitted0/rejected3，不能评估目标复制成本；只修隔离fixture的字段/路径后，第二pilot才取得准入资格（6/8）。存储缺陷版本的有效原点与字体不确定性仍保留：原Sound W0 36.048→47.228ms、字体26.534→33.955ms，不与最终版本混池或删点。原无效formal、pilots与最终固定批次均各自独立计数。

最终一次固定五组交替AB/BA，两输入共**60 App/80请求全部有资格**：原setAsWallpaper入口、实际presented/parent finalize、正常退出及输入/App/nonce/生产偏好检查。C0新隔离HOME/cache新App，C1保同内容/HOME/cache重开App，W0同App第二次且同daemon；不清OS页缓存。该入口资格不证明逐请求AV ready/playing、PCM或typed drain ACK。

| 五组中位，ms | C0 前驱 → D6 | C1 前驱 → D6 | W0 前驱 → D6 |
|---|---:|---:|---:|
| 自有三Sound PKG | 821.868 → 821.533 | 810.033 → 839.645 | 41.523 → 40.029 |
| 自有四层字体 PKG | 796.414 → 815.771 | 797.857 → 786.857 | 29.109 → 27.706 |

| 条件 | 前驱/候选最大相对中位偏差 | 两 arm 均≤5% | 原非目标预算 / 中位变化 |
|---|---:|---|---:|
| 自有三Sound PKG / C0 | 3.5495% / 5.2712% | 未过 | 7.0990% / 在内 |
| 自有三Sound PKG / C1 | 2.7067% / 5.0274% | 未过 | 5.4134% / 在内 |
| 自有三Sound PKG / W0 | 11.1914% / 44.4728% | 未过 | 22.3828% / 在内 |
| 自有四层字体 PKG / C0 | 5.5752% / 4.1026% | 未过 | 11.1505% / 在内 |
| 自有四层字体 PKG / C1 | 5.2585% / 4.2597% | 未过 | 10.5169% / 在内 |
| 自有四层字体 PKG / W0 | 14.0335% / 14.6142% | 未过 | 28.0669% / 在内 |

六条件noise均false、target均false、raw `medianChangeWithinTimingBudget`均true，`wholePerformanceCardPassed=false`。高噪声预算在内不证明无回退或收益。全部五点、范围、配对值保留，未混池、剔点或重复到绿；`d6-runtime-final-analysis.json`负责最终口径。D4模型W0父端resource-progress→surface-progress重叠窗口+6.429ms、Web C1及字体呈现不确定性仍开放，不能归因本次Sound或把观察窗口叫独占CPU/GPU。

## 归档、清理与后续

正式包`.artifacts/scene-evidence/runs/wallpaper-startup-scene-d6-20261024`已提取，884个payload（含report）、22,951,302B，manifest SHA `dc0e76e58b5c65f58dce7f2827a1b81a67b9a54e2d7d2773d68ce23e7006cd7e`；全部原件/归档逐项SHA与大小一致，默认14天/32MiB不变。已删除临时源路径时，按`d6-evidence-copy-verification.json`的mapping及包内`batch/report.json` label寻找归档，不把原路径失效说成证据不存在。最终文档、治理、审查与清理小收据由独立`wallpaper-startup-scene-d6-20261024-closeout`接续，主包不改写，不预填closeout数量。

`d6-cleanup-receipt.json`已执行精确停用目录清理：5530文件、1908目录、2,038,571,338逻辑B，不等于物理释放量；相关进程/打开句柄均为空，已归档文字重新核验。保一份`/private/tmp/mwx-startup-optimization-fbRhFY/DerivedData`及当前App4ab，`d6-predecessor-app`保实际D5-final App32b，`d6-sound-inputs-v3`及原有输入供后继。旧D6 App/cache/native输出已按计划删；D4 App与受保护包不动，根层小收据保至doc closeout，未声称所有D6 raw均已删除。

可信receipt/同源library lease、package backing/按需包IO、聚合物化预算、其余媒体存储及extractor产品退出继续后继。未验长稳、多屏、Release、能耗/温控、完整视觉/音频或通用AV drain；600正文预算与591永久redirect不扩。未触碰真实用户媒体或官方原件，未安装测试App；修改限隔离worktree，未暂存/提交/推送，主checkout与暂存状态由最终收尾再核。持续goal继续，不以本批限定闭合代表专项完成。
