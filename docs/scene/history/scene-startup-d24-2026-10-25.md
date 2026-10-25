# Scene 启动 D24：P7稳态、累计功能与旧工具退役

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。截止2026-10-25；后继归[启动专项](../../development/wallpaper-startup-optimization-plan.md#p7整体验收退役与收尾)。最终R3的20次普通UI轻重切换、30分钟稳态、自然退出及累计功能资格成立；整体性能与完整P7仍未授通过。

## 产品范围与真实构建

本批只移除原ScenePkgExtractor facade中全product/script/test无非nil调用的toolURL/Process支线、空协议与无producer状态。SourceFacts两处继续走原builtin构造；URL和authenticated snapshot双入口、普通missing/failed报告、sourceChanged与原取消穿透、合法legacy兼容解包均保留。它是不可达代码退役，不是新的启动提速。完整资源输入和强退役合同沿原owner，未新增reader/cache/播放权威。

最终R3签名Debug构建367.932秒，5957输入map前后稳定，strict签名exit0；source map为`138d5c2a4fb1fd607db5012318ca0dd1a0acd5a2b1d457358033fecc4dddebb5`，App executable为`fc02305c1f335189e747ba83af0fc3d951e6729b50fbed588c1902c9366b5b42`，CDHash为`b9f38f9fb87be1f15853c9a1662c0333bb5ca9bf`。实际build收据SHA为`20eacd1d6e4ab0b8f6bcb0521c7f1618d31163661af3798cbae845eed33e9333`。构建耗时不作为产品性能指标；后续文档修订不倒写构建身份。

## 最近门、原失败与输入纠偏

- facade/Facts/Model原1方法的9个硬错误/取消/普通失败行为检查通过，位于最初混合批次中；该批随后cache-alias断言失败，不能将整批记绿。
- R1实际4方法中1失败：旧夹具强定`/private/var/`，本轮TMPDIR为`/private/tmp/`。R2实际3方法中1错误：新增samefile预检发生在home创建前。保两份原report/raw；只将测试路径改为真实系统alias并先mkdir，再用samefile确认，原warm/damage/version/路径断言未放宽。
- R3原cache extractor与package source-input两模块23方法/127条编译及原生命令全部通过、0fail/error/skip、实际依赖无漂移。加上前述facade已资格方法是分批复用，不能称24方法同轮重跑或全GPU。
- `ae0ac798c`真HEAD的原seek父方法和完整原6产品源一次执行通过，保原9个seek子case、2个EOF控制及2秒等待/12秒子进程门；不是重跑整个6方法模块，也不能证明历史D7/D11间歇失败由本专项引入或已经修复。按预定规则STOP这条产品改动方向，旧失败原点保留。

普通UI轻输入最初选3766415113；实际publisher编译通过但prepare报ENOENT，原因是旧Scene入库检查在缺少loose入口时只开固定`scene.pkg`，该输入只有`gifscene.pkg`。这不是本批放宽资格或改作者的理由。原失败、staging及未改变heavy/作者/偏好守卫保留，不重试376。改用健康3141421197的真实`scene.pkg`，沿原17产品/2carrier真实prepare/publish/auth成功；不手写metadata/marker/receipt，也不称376发布成功。

UI独立库的heavy375 generation为`a9cb4809-8141-4230-8234-ece0e023b2ea`，18作者事实/59,243,475B；light314 generation为`194e9905-3f0d-4b95-af14-e26324774dae`，11作者事实/6,364,462B。它们与下述累计legacy输入不是同一资格集。前驱C的约21分钟诊断自然退出但未到正式steady-end，保false；首次最终wrapper又被编译进程QuietWindow守卫在播放前中止，保原false，不追认为最终长运行。

## 最终R3普通UI：20切换与30分钟

新的普通App隔离HOME/私有defaults suite、30FPS及实际签名App，不运行Startup选择runner、不预shutdown。先真实heavy375 baseline0，然后1=light314、2=heavy375交替至20，每次由原产品Service/Manager提交后观察。原日志独立证实21个不同ticket/request/session、21个GPUcompleted首帧与后续activated→launched→Manager commit，20次previous-session链完整；父PID50974、Scene PID51114及各自lstart保持。外部marker只做顺序标记，不是成功权威；request/session与Manager ticket是原日志近邻关联，不冒称同UUID或完整每row source DTO。

20步完成后重375正式steady-start→steady-end为**1810.109155667秒**，原始资源日志与report的2500个全程采样逐项一致；稳态内1681点均为Scene51114/lstart`Sun Oct 25 09:02:08 2026`。RSS首235984、末191888KiB，min191520/max236032KiB；累计CPU计数增243.78秒。它们是该进程离散资源观察，不是CPU独占归因、能耗、峰值、性能对照或无泄漏证明。

两张原3024×1964截图来自记录的同一owned CGWindow70244/PID51114、logical1512×982：09:17→09:47时钟与雪花位置变化，雪山输出保持。只证两个有限后续可见端点，不证30分钟每帧可见、满30FPS或官方像素一致。独立review确认原21commit前缀未改、20步在稳态前、普通Quit在steady-end后；原11check全true，parent自然exit0/ownedchildren0、无fallback介入，临时defaults清除。原publication完整commit/marker/receipt/作者tree、共享输入/生产偏好、source/staged签名及工具守卫均保持。HOME/staged App的精确回收结果以本批Root清理收据为准，不以UI PASS代替清理。

`report.json` SHA为`1f7f7576d081141b93b31a1946f5888f11bbfc4335a078134c7a773bfc7f932e`；限定独审为`d24-final-ui-runtime-independent-review.json`，SHA`53a21b621321cc646c8b8cb9371977b717385e8e7d7c8846f5f92426fae9077f`。自然进程退出不等于typed GPU/AV drain或最后AV borrower释放。本轮未证实际睡眠/唤醒、显示缩放/变化或系统压力；`sleep-requested`是后来延期的标签，两个`memory_pressure -S`模拟均exit255/Operation not permitted，不能记作压力通过。

## 原始P0、D22与最终D24累计对照

按冻结原core和规范化`MyWallpaperX.app` staging，一次执行两输入×三臂×五轮C0/C1/W0，共90App/195请求（Scene60、Web135），全部功能/退出/偏好/签名/输入守卫通过，观察到的环境快照无冲突。输入为原Scene3766415113与自建Web900000001；P0无admittedSource，故这是原legacy产品兼容和累计首帧/commit对照，不冒充三臂managed receipt等价。C0是空HOME，不是OS/GPU/WebKit缓存清空。Scene是entry→presented，Web是原entry→commit，不称Web物理呈现。

实际三App为P0 `5772f34e…a03a5bc18`、D22共同DEBUG harness重建`99f43b1b…94745e8`（不是原D22实存691802cd binary）、最终R3 `fc02305c…6b5b42`。原`run_selection/run_arm_conditions/summarize/summarize_paired`与5%噪声/10%目标/非目标预算不改，原点全部保留，无warmup、自动重采或删慢点。

下表第一数值列为原独立summary中位ms；配对列均为同iteration的candidate−baseline，负值更快，ms与%分别取五对中位。Web W0独立summary含30个暖row；配对与noise先在每App原6个暖row取中位，单位仍是5个App，不用30row虚增样本。

| 条件 | 原summary P0 / D22 / D24 ms | P0→D24配对Δms / Δ% | P0 / D24噪声 | 双臂≤5% |
|---|---|---|---|---|
| Scene C0 | 1053.666 / 990.565 / 1000.049 | -58.680 / -5.569% | 3.700% / 6.481% | 未通过 |
| Scene C1 | 864.485 / 777.455 / 779.204 | -85.281 / -9.865% | 2.838% / 1.580% | 通过 |
| Scene W0 | 211.072 / 71.558 / 71.196 | -137.834 / -65.940% | 1.949% / 27.225% | 未通过 |
| Web C0 | 1041.135 / 851.200 / 848.906 | -208.615 / -19.727% | 17.666% / 3.296% | 未通过 |
| Web C1 | 1047.539 / 829.655 / 829.837 | -213.370 / -20.510% | 1.633% / 5.285% | 未通过 |
| Web W0 | 478.018 / 293.459 / 288.449 | -211.694 / -42.305% | 24.538% / 0.288% | 未通过 |

仅Scene C1噪声合格，但配对降幅9.865%仍未达原10%目标；其余5/6条件噪声失败。D24 Scene W0保留90.579ms慢点，不删除它以使噪声过门。所有功能资格成立仍不授整体正式提速、冷暖无回归或完整性能卡完成。

| 条件 | D22→D24配对Δms / Δ% | D22 / D24噪声 | 双臂≤5% |
|---|---|---|---|
| Scene C0 | +11.248 / +1.138% | 2.263% / 6.481% | 未通过 |
| Scene C1 | +7.064 / +0.908% | 2.932% / 1.580% | 通过 |
| Scene W0 | -0.906 / -1.243% | 5.106% / 27.225% | 未通过 |
| Web C0 | +14.061 / +1.684% | 5.694% / 3.296% | 未通过 |
| Web C1 | +5.514 / +0.660% | 1.373% / 5.285% | 未通过 |
| Web W0 | -5.025 / -1.712% | 3.075% / 0.288% | 通过 |

D22→D24多数接近，Scene C1为+7.064ms，未获正式额外收益；只有Scene C1/Web W0的双噪声过门也不能反推其他条件或整体无回归。原报告`performanceAccepted=false`，SHA`d35f25b56d4db521218c6df0f0cf9e8be4a1ff9516df01ec36c975acc61c3cc0`。这组legacy输入不关闭D19原managed输入C1正差，也不覆盖D23跨类型交接。

原D23c Video handoff五对+38.713ms继续保留，但它是旧Scene屏障后的交接完成观察，不是已测出的Video首次可见回退。[D25只读复核](scene-startup-d25-2026-10-25.md)确认visible/Manager commit在退休前，Engine finalized/readiness在旧端屏障后；强ACK→原runner发现2.262–10.190ms含20ms轮询尾部，未发现额外父端等待。资源事件→强ACK仍缺child fence/首次CG结果，不能全归窗口动画或删除撤回门。无可安全减工环节，STOP额外诊断和产品微优化，不抹完成成本、不改clock/退出/timeout或原五对。

## 剩余与证据收尾

采用阶段的限定功能、资源减工与生命周期事实保留；已STOP候选不列未来必做开发。D25审计后的真实余项是新鲜六方向、真实ES模块/作者Web属性主动暂停实音、native WebM workspace/启动峰值和OS恢复，不能缩成只余人工P7；未有新结果前均待测，见[当前专项](../../development/wallpaper-startup-optimization-plan.md#p7整体验收退役与收尾)。已有TTL/Quit、20切换/30min及legacy累计不替代这些项。保护归档/精确清理/Git状态已由下列真实收据完成；多屏/最低设备/Release、全FPS/AV drain、能耗或整体性能未获自动资格。

另一次独立短UI观察沿同一实际R3重375启动，父73925/Scene74046，303.395秒两端owned窗71676仍为1512×982，09:58→10:03时钟/雪位置改变；283资源样本及340环境快照守卫通过，普通Cmd-Q自然0/child0。人工问题尚无回复，未操作睡眠、缩放或压力；三个恢复结论明确false/null，不能补齐P7。原report SHA`d2d6c5c78f1ed391bd94d065c4a6a47649d6dd8c01d0a065fae78a3aa8b15f9a`，独审SHA`f6f8314a865e96f90e2f15d2beb64bb06d8fbb6c9ce11cb53fe04eecb89f06bf`。

本轮必要源重建、首错raw、376失败、前驱21分钟诊断、播放前冲突、最终23方法/seek、真实UI原日志/图/采样、90App原native与协议的证据位置为`.artifacts/scene-evidence/runs/wallpaper-startup-scene-d24-20261025-checkpoint`。原5张PNG完整保存在并列保护包`wallpaper-startup-scene-d24-images-20261025-checkpoint`，主包报告逐图绑定别名/长度/SHA及图片报告摘要，两个包分别遵守32MiB上限，不删原图或提高预算。实际晋升/保护状态与摘要以两个包内`manifest.json`为准；Root逐payload/source-mode复核和精确清理收据分别位于本机任务目录`/private/tmp/mwx-startup-optimization-fbRhFY/d24-promoted-evidence-verification.json`、`d24-cleanup-receipt.json`，不将collect成功等同晋升或物理回收。连续迭代只保留该任务`DerivedData`一份缓存及余项需要的输入/App；运行中/未知归属及唯一未解证据先保留。初始方案提交ae0ac798c之后全部实现保持未提交，未推送或发布。
