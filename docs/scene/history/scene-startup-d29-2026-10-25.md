# Scene 启动 D29–D30：收窄原因并停止无效微调

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。截止2026-10-25；任务顺序归[启动专项](../../development/wallpaper-startup-optimization-plan.md#p7整体验收退役与收尾)。D29三个任务目录实验及D30一次真正HEAD/current对照均未改产品，本页合并同一问题后继，避免另立重复过程入口。D28产品、测试与App身份保持；媒体内存风险、原seek失败及P2/P7仍开放。

## 一次seek边界观察

沿D28原MP4、原Harness、颜色/held/generation/commit期待及2秒内部、12秒外部截止期，只在任务目录Source加入有界标量事件。一次执行两个操作：seek6、seek2。均收到finished=true的AV完成回调，主队列校验接受；完成延迟分别18.943291ms、6.798250ms。main canary分别127.083µs、70.084µs，未触事件上限。

本次没有复现失败，按预定 **STOP unknown**；不重采，不改产品，不把D28原矩阵的seek2、latest6-2-6、paused-discard-after三个失败改绿。它们都是首个目标仍pending，不能归到discard或缓存路径；本次一子例两个操作也不能报作原六方法全部通过。

历史逐字节核对：初始HEAD `ae0ac798`与实际D7-before整Source相同，当前position枚举及七个相关方法仍逐字节相同。pending→AV完成→main校验机制属于优化前代码；当前Source仅有物化/worker参数、stop时asset保活的差异。**机制不是本专项新增；没有初始HEAD的同条件红点，仍不能断言这次失败本身早已存在。** 不从一次绿点推导修法或排除周边构造/环境影响。

实际报告 `d29-seek-boundary/execution-once/report.json` SHA `05636f6accd6e1f5c51facb071f166c4c2c93b3223a12fda66b02fd848fe6105`；独审 `d29-seek-result-review.json` SHA `3c7ad7f9f3d71e740a338fe464cfb935cac67167271243abac245fb23438ed31`。

## 回调内存观察：停止bytes额外复制假设

沿[D28薄delegate](scene-startup-d28-2026-10-25.md)同13个Swift源、CommonHarness及[D27合法长GOP](scene-startup-d27-2026-10-25.md)输入，任务ObjC层用固定32槽观察bytes前、bytes后、原sink后。callback内不新增Data、malloc、输出或队列；只正常atexit打印。实际两个callback、六点完整、无重叠/丢点，原行为和字节账通过。

| media回调边界 | current footprint B | malloc zone in-use B | malloc zone allocated B |
|---|---:|---:|---:|
| bytes前 | 36,684,424 | 32,181,248 | 54,411,264 |
| bytes后 | 36,684,424 | 32,181,248 | 54,411,264 |
| 原sink后 | 36,684,424 | 32,180,672 | 54,411,264 |

10,388,859B媒体段的约10MB增量在callback进入时已经存在；本输入下不支持bytes读取或原FD sink再制造同量大块内存，**停止这条假设**。公开aggregate observer不授独占分配归属，不能称SDK泄漏、永不复制或把全部差额归到packet。`zoneMaxSizeInUse`原值为0，不当作真实零峰值。reader前高水位36,995,744B，与D28原值相同。

实际报告 SHA `857b1c825d95536d69ae2a8416aa8682723d2d60ea4631127d8e575aea3acbf5`；独审 SHA `a07c42a788de8a7772b2c048306427732941bcda0ad9a601714bb9ae1f1b850a`。公开生命周期依据是Apple [NSData.bytes](https://developer.apple.com/documentation/foundation/nsdata/bytes)及本机AVAssetWriterInput.h的样本保留合同，不据此识别实际分配owner。

## 输入借用候选：行为通过，停止采用

在原Payload owner内一次Data→不可变NSData桥接，每个原packet用公开managed `CMBlockBuffer(buffer:deallocator:)`强捕获backing代替逐包分配/复制；无手工retain/free、逃逸的Data闭包指针、新队列或缓存。原timing/NotSync、关键帧flush、取消、30秒writer期限与磁盘预约保持。候选及observer均只在任务目录，逆投影逐字节恢复D28，12个其他Swift源、原CommonHarness和ObjC header/implementation不变。

一次ARC clang、原O/WMO Swift编译、fresh current native自然exit0；桥接地址比较只在`payload.withUnsafeBytes`内返回Bool，本输入确实共享。原130帧/全部PTS与17ms时长/end、三个逆向再前向精确seek、output=ledger 10,389,494B和原file保活通过。

| reader前进程高水位 | B | MiB |
|---|---:|---:|
| D27旧URLwriter | 20,726,384 | 19.77 |
| D28产品机制 | 36,995,744 | 35.28 |
| D29任务借用候选 | 36,111,008 | 34.44 |

相对D28只少884,736B（2.391%），仍高旧链15,384,624B。单次小差不能证明稳定收益，更没有解释主要增量；**停止候选，不增加产品裸指针/释放闭包的维护负担，不追测或重跑旧writer**。`passed=true`只表示共同语义/来源/共享检查通过，不是性能验收。采用前COW/最后借用门未运行；候选已停止，因此不再扩展它的采用测试，也不把它列作未来实现债。

实际protocol SHA `913e47d1f83b04c564c5bd239bf68e16500e88174a081861c6844260bc7980fa`；报告与source/终态审查归同包。未改输入能力、GOP限制或flush，未回退绕过磁盘预约的旧URLwriter。

## D30后继：真正初始HEAD与当前对照

一次预登记before→current、各seek2/latest6-2-6/paused-discard-after三子例，同D28原MP4及原颜色oracle。before六份产品源码和原compile方法逐字节来自初始HEAD `ae0ac798`，含旧OwnedFile与Payload，不再只比较D28 callback前后；current用实际工作树完整依赖。两臂共用当前完整Harness `beabfe68…7370`，HEAD/current的原subTest断言AST、readiness DTO/提取核相同；不加shim、source marker或callback journal，保原swift5 flags、2秒内界、12秒外界。

两Swift、一个clang及六native共9命令自然exit0、无timeout/signal，24.196秒。两臂原三子例均通过；独审从六份raw重算像素/代际/commit、seek2先6蓝后2红、latest[6,2,6]、paused候选discard/同texture重试且仍停6秒，结果一致。34个frozen文件及源/输入/binary/mode前后稳定。原SDK弃用警告保存，不称零警告。Root另核所有实际PID已退出、原flock可重取并明确归还窗口；工作树330owned文件未变。

本次没有复现旧失败，只授这一次真正HEAD/current的一致性，**不称修复或排除间歇，不抹D28原三红，停止重采**。实际protocol SHA `df12f2daa38345aee79eac6f6ab483d639ad02d36548def80b433840069b47b4`；report SHA `e8d73b691dceb35ecff432a3492800c44faa0b49967660ea1fdeb19754a97ed3`；raw独审 SHA `f797e326792530e9b4dc3fc1211eff4cddbf96d2d456b8059f5bf49c54ba0ede`。

整产品内存准备确认D7全展开直接前驱App及原真实publisher仍可复用；P0 App已不存在，不以D7或裸ae0替代原P0。独立v3出版、当前admittedSource/旧cache路径资格、采样进程集及事前预算由[原专项P2](../../development/wallpaper-startup-optimization-plan.md#p2scene-一次安全挂载按需读取退出全量解包)维护。任务采样适配/C ABI源仅静态准备，**未编译、未采样、没有新RAM通过结论**。首个预定A/B兼资格、不另pilot；用户选择OS恢复稍后，未执行锁屏、睡眠、显示或压力操作。

D30必要证据单独保存在`.artifacts/scene-evidence/runs/wallpaper-startup-scene-d30-20261025-checkpoint/`，引用D29/D28保护包与原输入；实际归档/清理以包内/任务终态收据为准。保留一份DerivedData及尚待执行的RAM准备，不重新构建产品；全部改动继续未提交。

## 验收范围与下一步

当前机器Mac16,1/M4、16GiB、macOS27.0.1，不是最低8GiB设备证据。整产品内存正式比较沿[性能卡](../roadmap/performance-convergence-card.md)的固定process set/窗口、交替基线/候选、相对门及事前绝对预算；native leaf用于发现和归因风险。单个隔离remux点既不能授完整P2通过，也不能代替含旧全包展开成本的整体P2对照。此范围澄清不豁免已知增量：最大合法输入、允许并发与最后借用仍须评价，不倒定阈值，不建立全RSS账本/watchdog。

后继回到：①事前最低设备/并发/系统余量政策与整产品内存覆盖；②原seek失败的可区分定位；③实际resize、睡眠/唤醒/解锁及系统压力；④汇总验收、原噪声/停止方向结算。P4/P5/P6已停止方向不是待补功能，不再追加同类适配微调。原D24累计五组、5/6噪声失败及30分钟/20切换结果保持，不重跑追绿。

三个实验分别在peer明确整组交接与原flock内执行；两诊断29.606秒，借用候选15.104秒。所有实际compiler/native自然终态、ps及锁释放核验，立即明确归还窗口。实验前后D28全部329个owned文件byte/mode稳定；本批没有新产品build/App证据，原D28的有界资格不扩张。最终文档门、独审与有限归档另记包内收据。

证据包：`.artifacts/scene-evidence/runs/wallpaper-startup-scene-d29-20261025-checkpoint/`；直接引用保护中的D28包和D27原输入，不重复保存10MB媒体。仅保小源码、协议、原日志、命令/来源/终态与停止结论；编译物、隔离HOME/cache和派生输出退出后清理。保留一份任务`DerivedData`供后继，未暂存、提交、推送或发布。
