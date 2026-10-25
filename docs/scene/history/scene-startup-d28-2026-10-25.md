# Scene 启动 D28：媒体回调薄适配与剩余峰值风险

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。截止2026-10-25；任务顺序归[启动专项](../../development/wallpaper-startup-optimization-plan.md#p7整体验收退役与收尾)。本批薄适配已进入工作树产品候选并完成签名Debug；局部降低只由同输入native对照证明，媒体新增峰值风险、seek失败与P2/P7原性能门仍未关闭。

## 包级释放池实际结果

沿[D27](scene-startup-d27-2026-10-25.md)同一合法长GOP输入（10,389,608B，SHA `f1a5fd3e1b0ba73a054a53a7ac3ce949c82274f3b4dc983ac94cfb8f1c794870`），原13源闭包与CommonHarness不变，仅在同步`makeSample + input.append`外包throwing autoreleasepool；原取消、30秒writer期限、关键帧flush、磁盘预约、输出保活不变。不跨await，没有增加队列或改变输入能力。

一次`-O -whole-module-optimization`编译11.755秒、一个fresh current native约1.749秒，PID1557/1588均自然exit0，无超时/强清，终态另以ps确认。未重新生成输入或重跑旧writer。Root在原checkpoint锁内实查无App/编译/native后执行，尚未收到另一会话整组窗口确认；不把间隙当作整组释放，不认领独占性能，后续明确交接再执行。原始命令、模式/源码前后、binary与5个内核采样均保存。

原130帧解码、全部PTS、compressed时长和asset end、原三个反向再前向精确seek检查均通过。current仍initialization1/media1，共2callback；最大10,388,859B、合计10,389,494B，实际output=ledger，至少一个moof、原file保活均通过。binary SHA `434668c5d96e652b2b9db2b8a6261c422abc3e4e687a75f39d404c3fbbe490b3`，源码/模式/输入稳定。

| 边界 | D27旧URLwriter高水位 B | D27当前高水位 B | 包级释放池高水位 B |
|---|---:|---:|---:|
| inputParsed | 12,780,072 | 12,780,072 | 12,730,920 |
| remux返回、reader前 | 20,726,384 | 47,317,664 | 47,432,376 |
| reader后 | 34,177,768 | 60,719,872 | 62,178,072 |
| seek/readback后 | 39,781,096 | 61,784,832 | 62,178,072 |

包级释放池reader前current footprint同为47,432,376B，较D27当前增加114,712B（约0.2424%），**没有清楚降低，停止此假设，不采用产品**。单候选观测不授正式噪声统计、全App比例或分配类型归因；风险仍未解。reader后当前footprint回落不等于高水位降低，不能择后一个低点宣称成功。

实际协议SHA `345215d44d98f48c272b1bf9acd4cb6657a5a5de0a49b71e759d62004ebeb19b`，报告`d28-packet-pool/execution-once/report.json` SHA `2ca7d7988fbebf77267a4dd3569b4a2be3e5dc84ae57eb8cdaece1dd853b4bba`，独审SHA `c0d98d8aeca69fc3b1d888ced7f153cd2559510f88537ac1e9d3023a1e2c6768`。

## NSData薄适配原型实际结果

在另一会话明确交窗、Root再次实查无App/编译/native并取得原checkpoint锁后，一次ARC clang约1.914秒、原O/WMO Swift约11.670秒、一个fresh current约1.262秒，三PID4230/4235/4241均自然exit0且ps终态；结束立即明确归还窗口。本次只换原回调入口，无packet pool、新输入生成或旧writer重跑。

| 边界 | NSData薄适配高水位 B |
|---|---:|
| inputParsed | 12,763,688 |
| remux返回、reader前 | 36,995,744 |
| reader后 | 50,496,280 |
| seek/readback后 | 50,496,280 |

reader前current footprint同36,995,744B，较D27当前减少10,321,920B（21.8141%），仍高旧URLwriter16,269,360B。共同130帧/时序/三个seek及2callback的10,389,494B output=ledger、原file保活均通过。这个结果支持同语义薄适配减少一部分额外开销，不能独占归因为SDK泄漏、AV段缓冲或宣称全部差额已消失。原型binary SHA `bb047bee64b462acd9ec45bf016d87e499d1c2a53fbf38cd281d70f61dbc8f7b`；协议SHA `19b17a1005ef85e325cd9defb5ccf2287766e527ca481b8fed7384717f1a447f`；实际report SHA `e91ba13481aa8d12c9881a4e9c3da23054523ab1a0952f1cd625b269844d4fa9`；独审SHA `1e2e747bbc9d58eb7eeb98c697c8cbc87d289d77b8d91cb57119d986d4d1918f`。

选择把同语义薄层接入原产品owner，六个直接Payload fixture的编译/链接同步；产品结果待最近负控、Debug与真实媒体运行后结算，原型不冒充产品验收。新增总桥接头只聚合原QuickJS及media imports，不把media逻辑放进QuickJS或新建资源模型。

## 产品集成与实际回归

设计先写入专项P7，再修改原`SceneVideoPayloadPreparation`和19行header/27行ObjC薄delegate；App总桥接头仅两个imports，两构建配置指向它。原Swift sink、锁、写FD、磁盘额度/退款、取消、关键帧flush与file pin未另建owner。实现收据`d28-product-implementation.json` SHA `fa2ec10bc651b48edd70a9e164af30fc4e700778d07d7bb632661e5f4d791463`；改前完整文件、差异与独审均保留。原Swift delegate已退出，不保第二回调链。Scene防御门同步删掉已退役callback对应两条旧豁免，未改检测器或阈值。

六个模块共58个独立方法实际执行，57个通过；`test_playing_seek_first_pixels_and_discarded_retry_match_latest_target`保留三个失败子场景：seek2、latest6-2-6、paused-discard-after。原2秒内未收到target6新candidate，seek2实际失败在前置seek6，不能把失败写成已修。该输入为原libx264 MP4，没有走本批WebM分段callback；静态无直接变化路径不排除二进制/调度影响。随后预定一次before→current共同seek2窄对照，两臂均通过；没有重跑另两个失败子场景，也没有覆盖或解释原失败。原report/stdout/stderr、原输入/断言与独审均保留，不报全58绿。

属性routing与属性video初次各有fixture setUp编译错误，分别缺此前ScenePlayback异步准入的fixture字段/入口，及既有material fixture调用的两个Pkg真实依赖。只补fixture载体/真实编译输入，原20+2方法断言不改；routing载体显式等待原异步任务，不伪造来源认证。修后两模块22个方法通过，原失败仍保留。不能以重跑方法数重复计入58。`d28-repaired-fixture-regressions/report.json` SHA `811057bbeb5b883e4a5867a768fed2339d9e18c75749a3609940a8f00a642031`，独审`d28-fixture-repair-and-seek-independent-review.json` SHA `976d0535378e1792aebd8d199f4abaa8ff5bb22598c0c34537b77b60961dd6be`。

固定5966文件的Debug构建429.496秒自然成功、原strict深签名exit0，冻结输入无变化；build.log实际含新增`.m`的ScanDependencies/CompileC及最终成功。App executable SHA `bb658162115009255322a906641147f749013e35d333f493f24cd309687a2099`，源hash表SHA `0c2c34e5fb3640ce37cbf82ac43faa1a2c9f9a8f17b0fc297f174390b6aec478`。构建时间不作为启动性能。

静态六门（结构15方法、依赖、残留、代码健康、防御、设计）最终通过。首次结构门的两个失败属于此前已退役`ScenePkgExtracting`的清单未收紧；本批只把其协议计数4→3并移除旧路径，其他清单深度相等，未改检测器。原失败`d28-static-gates-initial.json`和前后清单保留。

**产品入口运行状态：** 首次9秒意图探针实际在0.5秒内被既有隔离准入拒绝，日志说明缺测试环境合同；exit0但无runner result、私有MP4或截图，明确不是播放通过。原命令/日志、PID9692自然终态、实际用户正式与测试偏好文件身份未变均保存；Root立即归还peer窗口，先修测试驱动，不更改产品隔离门。

后继v2复用原`wallpaper_startup_benchmark.run_selection(scene,single)`，按既有准入补标准域token、同值flag及隔离HOME/Library/Caches/report，使用原Scene startup single/FPS30；删掉不兼容的evidence-dir，不混Web请求或更改bundle身份。原row45秒/outer90秒截止期不改，这不是原9秒稳态。peer明确交窗后一次执行通过：真实Service `steam-workshop-set-as-wallpaper`、同作者根、requested/applied FPS30，原匹配ticket/request/execution/epoch/gen，GPU completed→first-frame→activation→presented→产品commit/finalize，failures空。观察到实际私有MP4 10,389,494B和ftyp头，退出后消失，说明新writer路径实际运行；不保存这个派生视频重复载荷。原parent14304、ditto14312及daemon14316自然终态，无强清，Root另ps与共享锁复核并立即归还peer窗口；正式偏好semantic/file身份、App与输入稳定，测试域/私有suite依原helper清理。

v2报告`d28-app-inputs/startup-single-v2/execution-once/report.json` SHA `260faccf602f56ffdc282e645397fb9c45cbdbbda3cf53f54d4119a892aed206`；原native.json、app.log、实况MP4/PID与终态收据均保。原single不启execution lifecycle capture，未取得截图或`video-frame-v1`逐帧日志；firstPresent还允许普通不可用媒体局部降级，因此**本次只授真实产品启动/字节路径及正常退出，不授持续可见视频、9秒稳态、typed AV drain、managed receipt或新性能/内存对比**。实际解码/时序/seek与GPU媒体覆盖只按上述native/fixture各自范围认领。

## 下一责任点

Apple官方[autoreleasepool指南](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/MemoryMgmt/Articles/mmAutoreleasePools.html)只支持缩短临时对象寿命的方法，未证明当前原因。本机SDK `AVAssetWriter.h:469/472/483–487`及[分段API](https://developer.apple.com/documentation/avfoundation/avassetwriterdelegate)规定跨callback借用须保有NSData、无report重载优先及sync前flush/异线程回调。本次未找到Apple公开确认当前Swift Data桥接泄漏或版本修复，不能把第三方历史复现当作D27归因。

任务原型采用的边界与产品集成目标一致：原生接NSData，同步借bytes/length/type给原Swift Sink/Writer.rawbuffer，adapter强持Swift sink、worker强持弱delegate至原终态；无Data转换、指针逃逸、手动free、新队列/资源模型/输出owner。不带已停止packet pool，原flush/取消/期限与磁盘账本保持。薄适配已取得局部降低并集成；真实产品single入口与私有输出通过，持续可见媒体/typed AV drain不由此授予；三个seek子失败与剩余native增量继续按原门结算。

原D24累计5/6噪声失败、旧seek归因未知、39ms交接完成成本STOP、真实OS恢复与事前RAM政策仍保留。原件与后续状态以本机D28保护包及Root结算收据为准，不在本体预授晋升/清理成功。
