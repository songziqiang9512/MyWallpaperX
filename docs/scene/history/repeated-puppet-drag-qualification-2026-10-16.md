<!-- document-role: historical-evidence -->
# U40 连续 Puppet 拖动：fresh 资格与候选 API 缺口

> **历史证据 — 非现役入口**。截止：2026-10-18。保留fresh三轮故障、早期载体失败与后继官方有界观察。U40未闭合，没有通用冲量合同、重复交互修复或完整样本通过结论。

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
实际释放循环还可能触及启用字段省略的有效bone0，后继Q4观察与native reader的未启用判定分开。方向空间、单位/增益、广义angular缺省、重复累加/reset及更广solver仍未闭合；禁止猜default或削减异常fuse把后续callback恢复包装为物理修复。
早期`handoff-review-receipt.json`的approved=true仅接受当轮交接与证据边界，implementationAuthorizedByThisReceipt=false仍保留；本文不引用作者算法正文。

<a id="official-pose-query-observation"></a>

## 官方自有载体与query观察

三轮后继均使用固定官方2.8.0.42，wallpaper32 SHA256为`daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07`。原始PNG、输入身份、observer、预登记及关闭/清理回执随正式包保留；不能把API正常返回、getter、整图hash或工具缩略图单独当作物理正控。

**早期Q1失败保留。** 两次fixture qualification失败后按原门STOP；第二次opaque MDL自有格线的getter读回localX+40，但原四个ROI×31帧没有变形，两次均未发出impulse。该历史失败不改写成成功，也不再概括后续所有官方资格。

**R3 setter正控合格，零impulse。** 静态跟进发现旧第二载体保留MDL却把原`genericimage4`改成缺少skin输入的`genericimage`。R3只恢复shader，rig/纹理/driver/ROI与阈值不变；第二格可见grid弯曲、局部轮廓移动6–8px，2331个RGB像素变化，其他三格逐像素稳定。原ROI内无绿色文字污染。此结果限定该载体，不把静态shader差异推广为所有无响应的原因。

**Q2观察到视觉脉冲，原joint gate仍UNKNOWN。** 相同translation-only bone1在age2分别执行no-call、zero、显式`D=(200,0,0), angular=(0,0,0)`及省略angular。显式/省略两格正常返回undefined，局部轮廓同相位移动超过3px，原ROI二值mask相同或最多1px差；no-call/zero控制稳定。原联合门另要求local-origin非零，实际登记的绝对delta仅f0/3/12/60显示0，其余登记帧只有E−M差值0，故不回写原门为PASS；“没有物理运动”的早期肉眼判断已由原像素反证撤回。这不证明通用angular默认值、数值精确等价或solver一致。

**Q3取得O/L/W分道的有界观察。** 只替换观测脚本，Q2其余四个资源entry、rig、调用块、age2/D200/zero参数及text scale .5保持；首帧存各格各getter baseline，在原八个相对回调采样点全部打印绝对delta。O=`getLocalBoneOrigin(1)`、L=`getLocalBoneTransform(1).m[12..14]`均显示0；W=`getBoneTransform(1).m[12..14]`在f0显示0，后续登记点有正/负/衰减的X响应，显式/省略两格显示一致，Y/Z显示0；no-call/zero三类query都显示0。显示分辨率为.001，不能写成数学精确零或精确等价，也不外推全部矩阵/骨/parent情形。

Q3原ROI的E/M峰值为2556/2559个RGB变化像素，y=220局部左轮廓各移动10px，两个控制格31图均逐像素稳定；终态33行、24条采样及F60完整可读，绿色文字包围框`[16,404,404,784]`未侵入ROI。`Mat4.m`的Array16/全finite门通过，仅证明首帧和登记采样；不是未观测帧的承诺。窗口3998524关闭后remaining=0、guest stage删除、receiver5368身份不变，输入drift=[]。名义100ms和复制后UTC不提供精确显示延迟。

Q3时native物理推进把结果写入`scriptBoneOverrides`，随后同一pose被发布给local/world getter，不能满足上述观察。Q4/Q5只补足会改变公共状态设计的两个问题，不追加方向/振幅矩阵或据接线方案已知推动未知冲量实施。

**Q4：有效骨、启用字段省略时的有界处置。** 原bone0有实际skin权重，`se/re/t`均缺席，不能由native reader的nil定义官方disabled默认。相同D200的显式角零及省略角两调用均正常返回undefined；31张原ROI逐RGB无变化，O/L/W登记值显示0。独立同骨setter+40 hold正控改变4409个像素、轮廓移动7–8px；O/L显示40、W显示10，后者受本载体layer scale影响。全部24查询/33行可读、原ROI无绿色诊断。结论仅为本配置正常返回而未观察到响应，不推广为所有disabled骨no-op、通用角缺省或单位合同。

**Q5：一次setter后的局部寿命与物理续存。** 同一已启用平移物理bone1，C无调用、H持续+40、S仅age2写一次+40、I仅一次D200显式角零。S在同callback的O/L显示40，后续f1/2/3/6/12/30/60显示0；W从10继续衰减并反向，f60显示+0.001，不称精确归零。H始终O/L40、W10；I本地显示0而世界及网格运动。C的31个原ROI稳定；H/I实际轮廓分别移动8/9px，峰值2331/2455变化像素；S峰值2122，后续仍有可见余振。33行、24查询、finite门、identity及关闭/清理均通过独审。完整数表由正式包`q5/independent-review/query-observations.json`唯一保存，不将.25的载体scale倒推冲量单位。

Q5首次CLI dispatch在0.15s返回255，未出现receiver或实验回执；只读预检确认原receiver不变、stage缺席和冻结runner可见后，以完全同argv/input完成一次实际实验。失败与预检保留，不计作第二次物理试验。上述结果只支持本平移profile的本地translation overlay按cadence退出、物理位置/速度续存；rotation/scale/其余matrix分量及非物理骨寿命未知。职责方案归[D4](../roadmap/batch2/script-component-api-design.md#puppet-query-render-pose)。
U40仍须修后按原输入验证三轮持续响应、释放后继续更新、健康邻居与原生入口；不关闭N06、N08、其他Puppet profile、整样本视觉、物理多屏或性能专项。

<a id="native-query-render-pose"></a>

## 本地translation查询与render分域：有界实施

按[D4先行设计](../roadmap/batch2/script-component-api-design.md#puppet-query-render-pose)，原PlaybackState保物理位置/速度与render override；已准入平移物理骨的query origin在新simulation cadence回动画基值，同callback setter仍覆盖。仅替换translation分量，rotation/scale/其余basis及非物理骨行为保持。原typed pose携query-local/render-local，C world以物理hierarchy重建；world setter用物理parent求局部值，未写骨的运动不被纯query矩阵抹掉。原rollback baseline同时撤回两镜像，GPU source-update FIFO/资源退休不变；新render镜像仅实际骨owner按count分配与复用。相同cadence不重复推进，不新增clock或solver。

一次Debug build通过，4331输入drift=[]、签名验证成功；App executable SHA `7b9f5d8ab6dccb19246736fdf786d68358446d93007cb3538a9925bf8fd3b44a`、dylib SHA `8fde6f355f812a8828840ac0328b0372f4c82b703ccdf3db0a801a3c07e9812f`。真实QuickJS门4/4、Metal门16/16均一次通过；前者含改名/placement变体、父子与邻骨、local/world写、非法refresh与撤回，后者含非零动画base、同cadence保持、下一cadence query复位而world/attachment/真实顶点续存及原FIFO/coverage反例。强制OOM注入与更广matrix寿命未验，不将静态失败路径审查写成已测。

同身份隔离App的四格self输入实际执行C控制、H持续setter、S一次setter及N非物理骨旧行为。S采样F0的O/L40、W10，F1的O/L0、W9.644，后续world反向而网格继续；数值轨迹仍属项目原近似，不声称官方solver一致。24张Metal截图中C固定ROI逐RGB不变，H/S轮廓最大移动21/12px，红色失败标记及绿色文字侵入均为0。Root查看ready、运动中及after原图，输入/App未漂移，VM6owner全quiescent、无callback拒绝，停止1→0/GPU drained。

未参与修法的原3791967416沿同一App运行：608/962实际发布各58骨pose，六个Puppet draw进入合成；ready为作者Logo，after人物、眼部、花、手与背景呈现，17owner退出无失败、GPU drained。未验证完整闭眼周期/旧局部图案差异，不关闭其队列。3357627941另保普通image/video/graph邻例；其日志无Puppet资格，不能用旧matrix标题把它冒充Puppet回归。两个原包project/pkg均只读、复制及原件重核drift=[]。这些结果只闭合局部查询首门；impulse入口、原三轮释放交互及性能收益仍未验。

<a id="impulse-direction-20261018"></a>

## 冲量方向与实现边界（2026-10-18）

固定官方2.8.0.42的32位客户端（4,303,856B，SHA `daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07`）沿已资格的三root rig，比较无调用、原尺度、加载时90°旋转和半尺度四臂。三个调用臂均仅一次bone1、direction `(200,0,0)`、显式angular零；记录完整O/L/W、真实时间与8个相对callback。首轮在首callback改rotation导致基线不稳，`PREBASE_MOVING / normal0/3`，没有发出冲量；该失败保留，不作方向证据。后继仅将90°设为加载值，其他输入和阈值保持，取得稳定基线、正常返回3/3与完整24/24观察。

后继31张原图中control像素不变，原尺度/旋转/半尺度最大轮廓位移8/8/5px。首次后继观察中原尺度与旋转的world X均8.291，其他world分量零，独立复核确认90°实际basis；仅支持**静态root、该XY输入的world-fixed方向响应**。两者反变换局部位移33.164，未触预登记40的判断界限；半尺度已到局部50的上限，故缩放、增益和单位仍UNKNOWN，不能用其比值拟合。完整动态挂点、非均匀缩放、角冲量及官方数值parity均未验。

限时静态研究仅查看同身份客户端的三个函数体，补充入口将原direction逐分量累加到每骨持久向量、入口未作矩阵/质量/dt/额外gain转换且不立即改local matrix的事实。后继积分消费者未裁定，不能将该向量命名为velocity或pending force；local-origin setter后的通知也未展开，不能推断它清速度。达到三函数预算即停止，无额外参数矩阵或猜测公式进入产品。原始静态材料留仓库外，仅中性事实、身份及限制进入本记录。

原562/598各有三root，但都依附动态parent attachment且有XY缩放动画；当前先全体局部物理、再解world的调度不足以直接承接world耦合。后继设计应复用canonical parent-first/cache顺序和同一个PlaybackState/Motion，先父pose/attachment、再子carrier与一次推进；不得新增树/solver/clock或用静态bind冒当前姿态。具体惯性和单位合同仍未选定，本次没有实现冲量API或关闭原三轮释放故障。现有matrix命令跨owner顺序另在D4修复，不与这些未知混记。

本轮原图、冻结输入、失败回执与独审统一保存于 `.artifacts/scene-evidence/runs/u40-impulse-direction-20261018/`：213 entries、62张原PNG，ZIP 2,667,866B，SHA `7569e28f536bfb1997ddebafdca84a59020f0c402e24c79800b1ed02583fe3b0`；`passed=null`，因释放语义未解protected。A1原prefix与A2共同suffix可逐字节还原原输入，已核原包SHA；一次逐entry原字节审核通过。静态原件63.3MB留仓库外，不进入该包。不计样本通过或性能收益。

## 证据与保留

忽略根`.artifacts/tmp/u40-drag-qualification-20261016/`保资格计划、构建身份与中性投影。
`controlled-repeated-drag/neutral-projection.json` SHA为`45565f4d095520a4a409ae343c8dee661d679748f6162a675771c05ca1520a1b`。
`neutral-failures.json`位于同一controlled目录；骨origin资格见`bone-origin-qualification/neutral-bone-origins.json`。
最终中性API projection SHA为`15cbbe780ef729c015d809336063229afdd5f40695fe6e8037f9b7d1c75f0dd5`，receipt SHA为`16cc240a8a6a13c98f763142751150f7dbb7ccb758e6205c7f6f8a03e26486a8`。
`cleanup.json`保留controlled三张held及一张released PNG，共30,791,766B；native/pose无资格及重复PNG已删，必要日志gzip、中性投影与执行receipt保留。
本次清10个file/65,399,845B；前轮native-cleanup另记344项/948,068,524B，分列为磁盘产物清理，不计内存或性能收益。owned App=[]且GPU drained；原374 project/pkg重核sourceDrift=[]。
研究停止后已确认无打开句柄并清理同根样本副本及HOME共792文件/90,837,449B，收据为`environment-retirement-cleanup.json`；唯一DerivedData仍供后继批复用。
早期受控轮的promotion预算拒绝与当时未重试记录保留，未知证据未删；官方Q1中性交接原路径为`.artifacts/tmp/u40-bone-impulse-blackbox-20261016/`。当轮窗口/guest/cache清理与VM保持running的记录不等于U40修复。

下列官方观察包位于`.artifacts/scene-evidence/runs/`，均protected unresolved U40、无自动到期；临时总预算调用参数未修改仓库默认策略。各包内`actual-review.json`保存独立原像素复核与完整输入/回执hash，Q3封包后另逐entry对原bytes验证87/87一致。

| 阶段与正式ZIP | entry / bytes | ZIP SHA256 |
|---|---:|---|
| [R3 · setter正控](../../../.artifacts/scene-evidence/runs/u40-skin-consumer-qualification-20261016/final/samples/3749463715/runtime_evidence.zip) | 89 / 2,161,133 | `6a018609939d2422700cfd2cb7218adef61ec2f88ac5b930f9a6ae972aaf7ae8` |
| [Q2 · 视觉脉冲，原joint gate UNKNOWN](../../../.artifacts/scene-evidence/runs/u40-translation-impulse-contract-20261016/final/samples/3749463715/runtime_evidence.zip) | 85 / 1,230,986 | `48bc4c10c602606f3803e52638e2e494f0dadcf049ddb8101899e27fc273ff44` |
| [Q3 · query投影观察](../../../.artifacts/scene-evidence/runs/u40-physics-query-projection-20261016/final/samples/3749463715/runtime_evidence.zip) | 87 / 1,510,219 | `c595175f7b844b1e6492f3b761179c73cecf938c9fd1daf3327b4e4d5a6a4b04` |
| [Q4/Q5 · 省略启用字段与setter寿命](../../../.artifacts/scene-evidence/runs/u40-pose-query-contract-20261017/final/samples/3749463715/runtime_evidence.zip) | 186 / 3,190,639 | `5a25fde480a0c945b2428eae17686caeafa598a521616e3f9eedc472ed6908b0` |

已闭query/render片的[原生验收包](../../../.artifacts/scene-evidence/runs/u40-query-render-projection-20261017/final/samples/3749463715/runtime_evidence.zip)按普通14天保留：82 entries / 26,305,297B，SHA `cef4271ae6f2d91baee2e73b5681ecdafd96bee9d7ddc1f2d0631357a36852c2`。含24张self、335两张与379两张原图、原日志/输入身份、实际CPU/Metal命令和独审；81源逐字节匹配后清理重复执行环境。官方Q4/Q5另核185源一致再清临时副本，VM保持running。用户临时授权总预算1536MiB，单包32MiB及到期策略不变。

真实用户媒体只读；U41既有提交`b132add7`不作为U40修复；提交、推送与发布状态由root另行汇报。
