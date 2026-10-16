<!-- document-role: historical-evidence -->
# U40 连续 Puppet 拖动：fresh 资格与候选 API 缺口

> **历史证据 — 非现役入口**。截止：2026-10-16。保留fresh三轮故障与早期两次载体失败，并记录后继R3 setter正控、Q2视觉脉冲和Q3 query/render分道的有界观察。U40未闭合，没有交互修复、通用冲量合同或完整样本通过结论。

当前状态与后继归[断点队列](../roadmap/scene-open-breakpoint-queue.md)，属性专项归[工作卡](../roadmap/properties-panel-card.md)，执行边界归[兼容路线](../roadmap/scene-compatibility-roadmap.md)。

## 问题与资格范围

3749463715 的用户报告为胸部拖动只首次有效，第二次及后续失效。
本轮先证明首轮选骨、持续按住、实际骨写与GPU几何响应，再用同一输入重复三轮。
不从短gesture、事件日志或单张人物图推断骨骼功能；不按样本或骨号增加可见算法。
早期native资格只消费中性metadata、typed结果与Root实际图像观察；后继按授权阅读作者释放调用链及合法stock接口，独立研究行为，不复制或照译参考算法。

既有DEBUG pointer schedule新增可登记的press/held/between时间，保持原触发入口。
单次selected骨origin投影仅用于选择起点，输出layer-render NDC、finite/inViewport等数值事实。
它投影已发布pose且零pointer parallax，不能替代实际hit与骨写资格，也不改变产品交互语义。
新增工具与测试是取证能力，不是U40修复。

## 有效受控三轮

同一Session、同NDC起点`(-0.260381,-0.347046)`到终点`(-0.180381,-0.347046)`。
计划press=1s、held=2s、between=6s，每轮同方向/幅度/持有窗口；不比较随机手势。
最终Debug build exit0，23.565s，工具/测试输入drift=[]。
受控运行PID43970，exit0、40.101302s、ready、timedOut=false、reaped=true、inputDrift=[]，停止GPU drained。
Root实际查看三张held图，再结合typed GPU回执判定，不以截图文件存在代替观看。

| 窗口 | layer598实际结果 | 邻居与边界 |
|---|---|---|
| 第1轮按住 | 21条GPU completed均scriptWritten；21个geometry hash，revision1→160 | cursorDown/Up都到达；首轮持续骨响应已资格 |
| 第1轮释放之后 | visibility owner报code=exception，TypeError:not a function | 保异常事实，不能以空操作隐藏缺口 |
| 第2轮 | 首次事件报code=disabled，无598 cursor callback/骨写；21条记录只有1个geometry hash、revision285固定 | 562仍收到down/up，不能据此认定全局pointer失效 |
| 第3轮 | 无598 cursor callback/骨写；22条记录只有1个geometry hash、revision285固定 | 562继续收到down/up；未证明其全部物理行为 |

该结果fresh复现“首轮有效、释放后后续失效”，并把异常/disable与骨几何停止对应起来。
这是受控override入口证据，不等于原生OS拖放或固定官方行为已一致。

## 未取得资格的 native 尝试

native-attempt-1 的Library窗口改变了交互上下文。
native-attempt-2 的短down/up被同帧合并，没有首轮scriptWritten骨响应。
两次都不计native功能成功，也不用于决定capture或physics算法；不为凑重复轮数追加无资格运行。

## 候选依赖与待定合同

最终中性AST报告与后继读源均确认两层各有独立4331B wrapper，回调形态含update/down/up/init；释放延时链首个缺失host方法为`applyBonePhysicsImpulse`，实际调用形态是两参`[Number,Vec3]`，后续才进入animation控制。不是getAnimation缺失；尚无动态PC因果证明，不能把静态首缺口写成已确证异常调用点。
实际释放循环还可能触及未启用物理的有效bone0，不能由下面bone1的translation-only观察替代其处置合同。方向空间、单位/增益、广义angular缺省、重复累加/reset及更广solver仍未闭合；禁止no-op、猜default或削减异常fuse把后续callback恢复包装为物理修复。
早期`handoff-review-receipt.json`的approved=true仅接受当轮交接与证据边界，implementationAuthorizedByThisReceipt=false仍保留；本文不引用作者算法正文。

<a id="official-pose-query-observation"></a>

## 官方自有载体与query观察

三轮后继均使用固定官方2.8.0.42，wallpaper32 SHA256为`daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07`。原始PNG、输入身份、observer、预登记及关闭/清理回执随正式包保留；不能把API正常返回、getter、整图hash或工具缩略图单独当作物理正控。

**早期Q1失败保留。** 两次fixture qualification失败后按原门STOP；第二次opaque MDL自有格线的getter读回localX+40，但原四个ROI×31帧没有变形，两次均未发出impulse。该历史失败不改写成成功，也不再概括后续所有官方资格。

**R3 setter正控合格，零impulse。** 静态跟进发现旧第二载体保留MDL却把原`genericimage4`改成缺少skin输入的`genericimage`。R3只恢复shader，rig/纹理/driver/ROI与阈值不变；第二格可见grid弯曲、局部轮廓移动6–8px，2331个RGB像素变化，其他三格逐像素稳定。原ROI内无绿色文字污染。此结果限定该载体，不把静态shader差异推广为所有无响应的原因。

**Q2观察到视觉脉冲，原joint gate仍UNKNOWN。** 相同translation-only bone1在age2分别执行no-call、zero、显式`D=(200,0,0), angular=(0,0,0)`及省略angular。显式/省略两格正常返回undefined，局部轮廓同相位移动超过3px，原ROI二值mask相同或最多1px差；no-call/zero控制稳定。原联合门另要求local-origin非零，实际登记的绝对delta仅f0/3/12/60显示0，其余登记帧只有E−M差值0，故不回写原门为PASS；“没有物理运动”的早期肉眼判断已由原像素反证撤回。这不证明通用angular默认值、数值精确等价或solver一致。

**Q3取得O/L/W分道的有界观察。** 只替换观测脚本，Q2其余四个资源entry、rig、调用块、age2/D200/zero参数及text scale .5保持；首帧存各格各getter baseline，在原八个相对回调采样点全部打印绝对delta。O=`getLocalBoneOrigin(1)`、L=`getLocalBoneTransform(1).m[12..14]`均显示0；W=`getBoneTransform(1).m[12..14]`在f0显示0，后续登记点有正/负/衰减的X响应，显式/省略两格显示一致，Y/Z显示0；no-call/zero三类query都显示0。显示分辨率为.001，不能写成数学精确零或精确等价，也不外推全部矩阵/骨/parent情形。

Q3原ROI的E/M峰值为2556/2559个RGB变化像素，y=220局部左轮廓各移动10px，两个控制格31图均逐像素稳定；终态33行、24条采样及F60完整可读，绿色文字包围框`[16,404,404,784]`未侵入ROI。`Mat4.m`的Array16/全finite门通过，仅证明首帧和登记采样；不是未观测帧的承诺。窗口3998524关闭后remaining=0、guest stage删除、receiver5368身份不变，输入drift=[]。名义100ms和复制后UTC不提供精确显示延迟。

现native的物理推进把结果写入`scriptBoneOverrides`，随后同一pose被发布给local/world getter；不能用这一投影直接满足Q3观察。后继须在已有唯一PlaybackState/typed pose职责内区分query与render姿态，并澄清实际作者释放链所需disabled骨及参数合同，不增加第二物理/clock owner。官方观察已停止扩展，不再追加方向/振幅矩阵，也不据接线方案已知推动未知语义实施。
U40仍须修后按原输入验证三轮持续响应、释放后继续更新、健康邻居与原生入口；不关闭N06、N08、其他Puppet profile、整样本视觉、物理多屏或性能专项。

## 证据与保留

忽略根`.artifacts/tmp/u40-drag-qualification-20261016/`保资格计划、构建身份与中性投影。
`controlled-repeated-drag/neutral-projection.json` SHA为`45565f4d095520a4a409ae343c8dee661d679748f6162a675771c05ca1520a1b`。
`neutral-failures.json`位于同一controlled目录；骨origin资格见`bone-origin-qualification/neutral-bone-origins.json`。
最终中性API projection SHA为`15cbbe780ef729c015d809336063229afdd5f40695fe6e8037f9b7d1c75f0dd5`，receipt SHA为`16cc240a8a6a13c98f763142751150f7dbb7ccb758e6205c7f6f8a03e26486a8`。
`cleanup.json`保留controlled三张held及一张released PNG，共30,791,766B；native/pose无资格及重复PNG已删，必要日志gzip、中性投影与执行receipt保留。
本次清10个file/65,399,845B；前轮native-cleanup另记344项/948,068,524B，分列为磁盘产物清理，不计内存或性能收益。owned App=[]且GPU drained；原374 project/pkg重核sourceDrift=[]。
研究停止后已确认无打开句柄并清理同根样本副本及HOME共792文件/90,837,449B，收据为`environment-retirement-cleanup.json`；唯一DerivedData仍供后继批复用。
早期受控轮的promotion预算拒绝与当时未重试记录保留，未知证据未删；官方Q1中性交接原路径为`.artifacts/tmp/u40-bone-impulse-blackbox-20261016/`。当轮窗口/guest/cache清理与VM保持running的记录不等于U40修复。

后继正式包位于`.artifacts/scene-evidence/runs/`，均protected unresolved U40、无自动到期；本机授权的1280MiB总预算调用参数未修改仓库默认策略。各包内`actual-review.json`保存独立原像素复核与完整输入/回执hash，Q3封包后另逐entry对原bytes验证87/87一致。

| 阶段与正式ZIP | entry / bytes | ZIP SHA256 |
|---|---:|---|
| [R3 · setter正控](../../../.artifacts/scene-evidence/runs/u40-skin-consumer-qualification-20261016/final/samples/3749463715/runtime_evidence.zip) | 89 / 2,161,133 | `6a018609939d2422700cfd2cb7218adef61ec2f88ac5b930f9a6ae972aaf7ae8` |
| [Q2 · 视觉脉冲，原joint gate UNKNOWN](../../../.artifacts/scene-evidence/runs/u40-translation-impulse-contract-20261016/final/samples/3749463715/runtime_evidence.zip) | 85 / 1,230,986 | `48bc4c10c602606f3803e52638e2e494f0dadcf049ddb8101899e27fc273ff44` |
| [Q3 · query投影观察](../../../.artifacts/scene-evidence/runs/u40-physics-query-projection-20261016/final/samples/3749463715/runtime_evidence.zip) | 87 / 1,510,219 | `c595175f7b844b1e6492f3b761179c73cecf938c9fd1daf3327b4e4d5a6a4b04` |

真实用户媒体只读；U41既有提交`b132add7`不作为U40修复；提交、推送与发布状态由root另行汇报。
