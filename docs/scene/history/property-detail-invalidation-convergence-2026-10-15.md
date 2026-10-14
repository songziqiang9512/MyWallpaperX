<!-- document-role: historical-evidence -->

# 属性编辑时的详情失效收敛（2026-10-15）

> **历史证据 — 非现役入口**

现役职责与后继归[属性卡](../roadmap/properties-panel-card.md#detail-display-invalidation)，成本口径与停止项归[性能卡](../roadmap/performance-convergence-card.md)。本片减少普通属性通知导致的外层详情内容/footer重复重建；原属性存储、每次通知与typed更新不变。

## 职责与最近行为门

最早owner是原`SteamWorkshopItemDetailSheet`及`+Observation`，没有另建事件/store/cache。仅activeRecordID匹配的ready Scene且raw sourceVideoURL/exportedVideoURL均nil时，比较resolved item、raw latest record与原内存中的下载/依赖任务、进度presence/phase、刷新/错误、previewReloadToken及账号订阅展示输入；不调用playable/videoURL/Video-Web播放判定等可能I/O的getter。非active、非Scene、非ready或视频fallback仍走原重建。状态仅在原view寿命内，实际rebuild结束后才记录，排队多脉冲比较最终状态。

只过滤Service普通通知。WallpaperManager、Scene launch、auth与subscriptions通知保强制rebuild，原coalescer以OR累计force，执行前取出/清位，重入仍可排下一轮；configure、inspection与诊断入口保原强制刷新。此边界防止账号重置到相同unknown展示值时吞掉原subscriptionButton查询Task。持久preview只创建/持有一个height约束，重挂可重新激活同对象。

最终5路径freeze aggregate `fd6a3502a354c58305dcbc598340ae8aeed6a65b8dde9080e033e3d5bf029daf`（按排序后的relative path、NUL、文件SHA、LF取SHA256）。两个产品SHA为Sheet `e4aa63a2c3dcf6594b36ea296de1cb2ad0e8cc6a4836decd9a4463b28f7ea1ca`、Observation `8ff089ee42726a7448a2c6b9199d508d41e898f12f97ca6941392469c88fbd0f`。

`test_steam_detail_layout`中的真实detail行为门编译原产品与AppKit helper，复用真实普通store/update叶，外部Service/账号/播放/inspection叶用fixture替身。最终52项事实通过：20次独立保存/dispatch/pulse全保留，合资格view identity不变且无新增I/O getter；元数据、任务、刷新、错误、预览、切item、进度presence/phase、保守分支及合并/重入均有反例；实际unknown按钮refresh Task和四类force先后顺序已验。preview在必要metadata/force重建后仍为同一height对象、数量有界且实高156。其余6个未受force修订影响的最近方法复用此前PASS；独审绑定最终源ACK。

复跑受影响门：`python3.12 -B -m unittest -v script.tests.test_steam_detail_layout.SteamDetailLayoutTests.test_scene_property_notifications_preserve_actual_detail`。该门证明真实owner行为，不包含原生编辑输入、daemon、可见窗口合成或整App成本。

## 同active局部CPU对照

原三轮playing=false的基线只用于定位；未拿它与active候选计算收益。后继共同active/playing fixture固定unordered 400×760窗口、20次原更新、50ms间隔、main-thread CPU时钟与外部叶，同harness/support/编译flags，仅两产品源不同。第一次active-pair基线噪声8.8072792311%超5%，保留为无资格，未以大降幅豁免。

唯一环境控制复测两臂同加公开`beginActivity([.userInitiated,.latencyCritical])`覆盖原settle/测量并平衡endActivity，未增事件、绘制或预热。各编译一次后按B1/C1/C2/B2/B3/C3运行，输入/binary无漂移、六进程exit0。B binary `abd47ce46cd581fe550460d6da59b0368df842a0449c164014463e5a23cd9991`，C `9db260b6dcc32f5896dd29699ee1703f38403d3fc4c7f46b32e9a398f1b9a3db`。

| pair | B完整窗主线程CPU ns | C完整窗主线程CPU ns | C/B |
|---|---:|---:|---:|
| 1 | 522337208 | 46264041 | 0.08857121470848771 |
| 2 | 546081667 | 43047583 | 0.07882993625566997 |
| 3 | 554052167 | 38093875 | 0.06875503295342224 |

配对ratio中位`0.07882993625566997`，本局部完整窗口CPU下降92.1170063744%；基线噪声`max(abs(B_i/median(B)-1))=4.3481516474%`，满足≤5%、降幅≥10%且>2noise。候选自身波动约11.51%，不称两臂均低噪声，不由本轮推断App Nap成因。六进程各20事件/20steps且allChecks=true；每B内容/footer替换20次、live约束1020→1039，每C替换0次、约束1019→1019，liveViews均154。该收益仅属于activity-controlled unordered AppKit测量窗，不计整App、native延迟、GPU、RAM或能耗收益。

## 普通原生入口与画面

一次最终Debug构建23.669691s、输入无漂移，App executable SHA `31608b5e13133164800418b89a67550c36b3fe5f8851efc590b156b7bd9b8119`。正常下载详情保持打开属性，2932631210使用原作者newproperty5/6=false暴露背景；真实bound ColorWell键盘输入`00FF00`/`007FFF`均到达行值与实际背景。首次未绑定global colorpanel编辑无效，已排除。session `2D1BFD5B-31EE-44C0-8A38-9BBED20AAF66`、request `9536F783-22CB-4375-8825-FC7FBED2ADBD`保持一次启动/首帧。

(32,32)–(288,288)的65536像素ROI依次为绿色(117,251,76)、蓝色(55,125,247)，重开保蓝与作者开关；reset恢复黑色(0,0,0)及原toggle默认，再复用作者关闭条件核背景。此为OS颜色管理后的实际像素，不是作者RGB逐字节golden。详情metadata正常补全，实际Stop后列表/footer恢复“设为壁纸”。native未测UI对象identity，该事实由52项行为门提供。

紧接同App播放独立3248220186，session `5863930A-9E3F-4C82-AD2E-8B2457BE8D74`、daemon6930，实图见粒子球与06:32:07时钟，原生HDR属性列表可见。Stop后17/17 VM quiescent，failures/timers/jobs/mutations/dynamicLayers=0；CmdQ正常exit0，parent6451及daemon6468/6930消失。293停止紧接新launch的旧VM收尾未完整捕获，不认领其quiescent、pin归零或全部资源drain；独立画面不扩为完整粒子/HDR/官方parity。

## 证据保留与后继

本机`.artifacts/tmp/property-detail-invalidation-screen-20261015/`保原baseline、active-pair无资格原数、active-controlled/protocol与六份raw/summary、focused-force-final的52事实及源码身份；`.artifacts/tmp/property-detail-invalidation-native-20261015/`保冻结App、构建/操作日志、背景ROI和必要原图。源verify为`source_changes=[]`；隔离副本差异仅提前移走的324 discovery marker。清9个已停止可再建产物共569,631,626B（UI模块缓存、5个fixture binary、样本副本、独占HOME/tmp及前批已替换Debug App），不把磁盘清理当运行内存下降。保当前Debug App供紧接暖capability资格、一份DerivedData及共享shader cache连续复用。未复制promotion：现有evidence cache 1GiB总预算已满，prune-expired无可删项，未提高预算或删除未知/唯一旧证据；本轮限定proof约14.6MiB、CPU raw/source/freeze与失败原数继续原地保留。

本片关闭合资格普通属性通知的外层重复重建，不关闭整个属性性能专项。下一项先归因暖capability准备的CPU/RAM及失效范围；既有NO-GO不重启，不盲造cache。Web/Video/非active分支、整面板延迟、多surface、最低设备及长稳仍保原边界。
