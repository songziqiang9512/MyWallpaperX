# Scene 启动 D27：长 GOP 对照与新增峰值风险

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。截止2026-10-25；任务顺序归[启动专项](../../development/wallpaper-startup-optimization-plan.md#p7整体验收退役与收尾)。本批仅运行任务副本的native机制对照，没有修改产品/长期测试、重建App或提交。共同媒体行为通过，新增峰值风险未解决，不授完整P2/P7或整体性能。

## 输入修正与真实执行

当前分段writer仅在后续同步帧且间隔达到1秒时flush，长GOP可能直到finish才交付整段Data。本机SDK `AVAssetWriter.h:483–487`明确indefinite passthrough应在sync sample前flush，否则错误；不能任意在P帧按字节切段。回调Data在原磁盘预约前已经存在，磁盘额度不等于RAM额度。

首配方为固定seed27的高熵lossless VP9、320×180、130帧/17ms、g1000。生成10,400,385B，SHA`82374ba159e0148ded9c936b5fb1abce0bc9ac7e8d1fdfc1573c0ae3f0ab4c5a`；生成与唯一编译exit0，但首个current在共同parser、任何writer之前拒绝`VP9 superframe`，native exit−5，只有entry内存点，before未跑。实际packet12/23为双帧superframe，footer sizes精确覆盖payload，并非仅marker偶合。原失败报告SHA`1c04bc9e321405aee681e3e21df7ab0e0c9c78cef4d543e7439ae887f6172314`完整保留，不能改写为writer失败、内存比较或通过。

修正仅为生成器添加`-auto-alt-ref 0 -lag-in-frames 0`，新目录执行一次，未改parser/原行为门或覆写首失败。复用原13源`-O -whole-module-optimization`二进制SHA`fb78e5277156d263a827777d529c73cb672e984b7bc1d759a41f9bd741474f14`，不重编。原保护D8的Before URLwriter源码保持字节不动；当前Payload只有可逆整数counter观测。common Harness实际解析核到130packet、仅keyframe0、320×180及全部PTS/duration精确17ms；新输入10,389,608B，SHA`f1a5fd3e1b0ba73a054a53a7ac3ce949c82274f3b4dc983ac94cfb8f1c794870`。

固定current→before顺序，两臂独立fresh进程与HOME，原30秒writer/20秒native上限保留。两次native均正常exit0、无超时，生成约0.827秒、各native约0.778/0.775秒；这些运行时长不是启动性能验收。实际命令、二进制摘要、全部编译源/模式、原始stdout/stderr、输入及前后身份均保存。

## 共同功能与内存观察

两臂实际playable、全部130帧尺寸/PTS、compressed sample durations及asset end、三个反向再前向精确seek目标的宽高/时间共九子判断均通过，PTS/duration数组相等。容器布局本就不同，不要求output SHA相等；仅current另验至少一个moof、原file保活及全部输出按原8GiB磁盘总账计费。current收到initialization1/media1两个callback，合计10,389,494B等实际output/ledger，最大单次10,388,859B。

下表为各自进程在该边界观察到的lifetime max physical footprint；两个PID98791/98793的内核启动身份分别稳定，十次API均成功。

| 执行边界 | 旧URLwriter B | 当前segment writer B |
|---|---:|---:|
| main入口 | 2,081,320 | 2,081,320 |
| 同份payload与共同parse之后 | 12,780,072 | 12,780,072 |
| remux返回、任何reader之前 | 20,726,384 | 47,317,664 |
| 两个reader之后 | 34,177,768 | 60,719,872 |
| 原seek及完整readback之后 | 39,781,096 | 61,784,832 |

reader前高水位增加26,591,280B（128.296764%），该查询的current footprint也分别等于表中值；完整harness最后高水位增加22,003,736B。这是**待解决的新增峰值风险**，不能用没有绝对RAM政策或`report.passed=true`豁免；后者只证明本次行为、来源/身份及记录资格。

单次固定顺序、一个约10MiB输入不构成正式噪声统计、全App回退比例、多owner或256MiB输入上界；高水位差不是独占workspace或某类分配的大小。当前Sink不持Data数组，AV段缓冲、CM样本复制、Foundation桥接与allocator各自贡献未归因，不能直接称Data泄漏。原D24累计5/6噪声失败、旧seek归因未知及真实OS恢复未验仍保留。

## 下一责任点与原件

先在任务副本仅给同步`makeSample + input.append`增加throwing autoreleasepool，用同一合法输入和共同Harness区分临时对象释放；不跨await、不改关键帧/flush/ACK/取消/期限或磁盘账本。可逆候选design SHA`f05056556dcdd1242a4d9c315ad0586151afc03f3a15df6f0a483cd40c4dabee`，尚未编译/运行或进入产品。无清楚降低即停此假设，风险仍未解；不顺势收紧合法输入、增加queue/cache、任意非sync切段或恢复不受控URL写盘。若需NSData原生delegate，只先做有明确生命周期的任务级区分，不能凭猜测更换产品桥接/技术栈。

修正协议SHA`38ac85feed9c4434907964afb7b22c8d2be68902ea06d1dbf2e0253fd4a87087`，实际结果`d27-long-gop/corrected-no-altref-once/report.json` SHA`4782d3ff1c12bc0060e6717a056960260895643a88bd12d975c24d88930f6c79`，独审SHA`a896fed0ae7dd8fff511c592a77eb0372e045417813c1f9794ab9d095af13915`。原配方、修正、actual source closure和两输入均保留。拟保护入口为`.artifacts/scene-evidence/runs/wallpaper-startup-scene-d27-20261025-checkpoint`；实际晋升/字节核验和精确清理由Root后续收据结算，不在本体预授成功。
