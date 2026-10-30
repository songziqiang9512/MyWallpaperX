<!-- document-role: historical-evidence -->
# 全样本能力与短窗日志筛查（2026-10-29）

> **历史证据 — 非现役入口**

本轮执行用户要求的全量声明盘点、并行短窗日志筛查及公共问题归并；没有修改Core引擎或观看截图。后续选序只归[断点队列](../roadmap/scene-open-breakpoint-queue.md)，方法归[诊断合同](../development/corpus-diagnostic-workflow.md#log-first-corpus-audit)，逐样本结果由[验收台账](../capabilities/scene-sample-acceptance-ledger.md)生成，旧人工视觉裁决未改。

## 范围与能力集合

真实Scene根只读，一次扫描453目录：452可解析、3763323436缺project。声明193099点、4878结构family、2428参数profile、23940字段；19个粗能力映射不等于19条独立加载链。主链与五类prepared产品保持，按原准备/消费者分为九类视觉路线和Sound旁路；跨路线的Script/Property/Timeline/Camera不重复计链。具体分组见诊断合同。

粒子声明组件共42种：2 emitter、14 initializer、22 operator、4 renderer；CP序号不是算法。`objects.[].model`有308个raw字段叶值/37样本，含256个string MDL引用/12样本与52个粒子对象model:null/25样本；null不是加载请求。包内models presence映射451样本也不能当451个模型消费者。后续沿既有入口定点关联105个sample/model路径，未读vertex/index或纹理；这是453快照的声明澄清，不是已加载数，也不覆盖随后新增38样本。

## 执行身份与时序

产品基线`a91a76fcb`，本轮仅增加原DEBUG runner的log-only调度及原Python工具的并发/日志分支；没有第二启动器或解析器。相同签名App只stage一次，每worker独立sample/HOME/TMPDIR，提取日志后逐个删除，结束后删除公共stage。

- 普通签名Debug：主入口`14fe3b5e…d08e`、实际dylib`f3a2a3a3…ba51`。先4并发小批4例，再6并发449例；普通样本Ready后4秒、固定PCM、pointer outside、不注入真实媒体或快捷点击，453行均明确不请求PNG。
- 首轮4例30.139秒、449例1962.713秒；后者36例父超时。206单独复核59.008秒，其中Ready约51.556秒；采样指向未优化Debug的源码分析/准备，不能当能力缺口。
- 使用仓库已有优化诊断profile补36超时及317、377健康相邻，共38例、6并发、154.057秒，无父超时。Release配置加原xcconfig仍含DEBUG、Swift `-O`、C `-Os`、singlefile；主入口`3725913b…4fc0`，构建179.785秒。正式Release/WMO与性能比较均未执行。
- 当前逐样本投影显式选3例pilot、412例首轮、38例补跑，共453唯一行；保存原report SHA、行索引、App身份及所有原失败。不同profile不比较启动/CPU/GPU性能，也不把重试覆盖当原失败未发生。

450例Ready、实际GPU完成且stop为surface 1→0/GPU drained；两例持续拒首帧，另1例输入缺project。归一器分类为337 terminal-chain-complete、110 degraded、6 blocked、65组事件；6 blocked中包括前述3例及3个虽Ready但缺图单元完成的观察，不等于6幅全黑，也不等于116个已证缺能力。归一器按阶段/原因稳定排序，因果首错回原日志核对。

| 原日志/报告事实 | 样本数 | 证据上限 |
|---|---:|---|
| image纹理已加载 | 452 | 准备，不含每层可见性/像素 |
| text纹理已加载 | 254 | 栅格准备，不代布局与字体一致 |
| solid已加载 | 185 | 按需准备，不要求隐藏候选全加载 |
| 粒子已加载 / 非空提交人口 | 284 /268 | 不代每个组件正确或方向/密度一致 |
| Puppet动画层/clip准备 | 98 | 不代所有动作/auxiliary播放 |
| sprite动画入口 | 32 | 不代完整序列周期 |
| utility capture成功 / named binding成功 | 205 /44 | 对应执行，不代所有条件分支 |
| SpotLight成功 / failed报告 | 1 /3 | failed原因/可见consumer需资格，不代地球阴影归因 |

视频、文件/系统媒体、直接模型及Sound沿原日志保留逐目标事实；目前没有覆盖所有路线的统一完成统计，不能用总GPU帧冒充每条路线执行。Sound测试处于paused，PCM仅供频谱；未验可听播放、真实封面/标题/seek、真实鼠标、属性编辑或完整长Timeline。无截图审阅、官方parity、画面关闭或性能收益结论。

<a id="remaining-findings"></a>
## 公共问题归并与未决边界

- **首帧阻断分两类**：2959875782 layer134外部primary依赖报dependency-input-mismatch并撤回帧；3175039950 Program218183166b6c在terminalReplay uniform准备返回nil。后者局部采集矩阵降维与完整逆合同相交，未证明可全局改变Z或放松逆矩阵检查。
- **typed更新/拓扑**：273五个childless passthrough composition已有采集/回绘消费者却被perspective资格额外拒；3763428294、3779904456、3787382101、3804971850先拒authored mutation冲突，再报stale；363先拒516条mutation预算，再报owned handle。3808922316默认初始化995/1763仍报buffer exceeded，静态链指向sort冗余dirty与跨owner冲突，不是已证容量不足。
- **effect局部降级**：274 Xray拒slot2 halo用途proof；280 Shine缺secondary composite引用；357 Combined及texture-purpose接原队列。3632522893、3725148661、3747595588、3750312644报frontend局部fallback；3435573282/3587571382报generic-owner-revoked；3800572533报texture-binding。需实际pass/active consumer及ROI，不按effect名分派新算法。
- **资源/图观察线索**：56 solid、7 image、4 particle候选未全加载；15样本layer-source-not-ready。隐藏、alpha0、离屏、按需/退休与延迟先区分。2804817823/3039882306/3292370168虽Ready但部分图缺完成；377双视频的named-capture告警不推翻用户已确认正常的Xray。
- **脚本异常须按因果拆分**：有限读取12个代表原包，确认作者缺名字/越过父链、未赋值引用、在标量上调用Vec.add、在text索取纹理动画等不能算缺API。3047405322/3603711180无条件调用未实现的engine.isScreensaver为公共候选，360572的console.warn仍缺实际callee资格；3806202923/3812473896创建null接既有recipe/解析范围项，不补假实例。完整typed事件与成员在机器档案，不由首轮21例TypeError统计替代最终观察。

## 验证、保存与方法调整

真实DEBUG调度20方法、最近Python工具45方法、短窗验收3方法及最终归一器24方法通过；最后两项按实际修订补验，没有重跑未受影响的App。独立审查覆盖并发隔离、原视觉缺图仍失败、4秒无长稳summary仍保实际GPU/停止门、负ID及真实`layerMutations=N owner=`拒绝格式。检查不代播放正确性。

台账/archive最近16门及文档、依赖、产物、代码与防御面检查通过。额外结构组15门中1个既有迁移fixture失败：其passive-result历史源摘要在本轮未改的Core源上已失配；直接用HEAD与工作区相同源重算均为false，收据单列保留，未改无关迁移合同或声称全门绿。

本轮结果归`.artifacts/scene-evidence/runs/corpus-log-audit-20261029/`；压缩载荷保存原report/日志/runtime JSON、当前投影与来源行索引、normalization、能力集合、身份、构建参数和验证摘要，不保存Workshop副本/HOME/App/PNG。原始绝对证据路径用于关联压缩包内同名任务相对路径，需解包按需读取，不承诺旧执行目录常驻。唯一未解首帧错误另提取最小证据；普通全量结果14天到期。

本批发现普通O0 Debug是可避免的筛查耗时来源，故后续默认采用现优化诊断profile，仅重试未决例；每个普通样本仍只跑4秒，不统一拉长时窗。队列按公共首断点替换“新增81未跑”，旧具体视觉反馈保留待同状态复验，不据日志健康销账。

生成台账时移除“已移走样本还必须出现在当前运行archive”的检查：历史裁决保原overlay，不计当前分母；不新增存储或把缺目录改成运行成功。最近行为门同时覆盖当前archive有/无该历史ID时，当前行相同且overlay字节不变。

<a id="incremental-38-20261029"></a>
## 新增38份的增量观察

随后根目录为491，与保留453基线相比新增38、删除0；新包两次大小/mtime观察无变化，不把它当内容认证。沿原census显式子集只读一次，11.094秒：38份均可解析，21036声明点、887结构family、734参数profile、1870字段profile、1120 effects、125粒子层、4378包内entry/路径，未分类与包异常均0。与旧基线比较新增280个family，集合并集5158；19类粗能力及一条主链/五类prepared产品/九类视觉路线与Sound旁路不变。此为旧453与新38的集合观察，不是新鲜完整491 compact快照；原声明双页与完整缓存保留453身份，未重读旧包或拼接丢失的occurrence refs。

同一签名优化DEBUG App，源`157fc9aa7`、executable `08cf95c6…93c31b`、CDHash `8a1967f3…b4a76db`；jobs4、Ready后4秒、标准PCM、pointer outside、无PNG请求。38份共147.853秒，31 strict PASS、7 strict诊断FAIL；全部Ready/exit0，无timeout，stop surface1→0且GPU drained。并发争用下的时间不作启动/CPU/GPU性能对照，日志健康不授视觉通过。

七份告警须按实际consumer分流，不能整体记成缺图：

| 观察 | 当前归属与边界 |
|---|---|
| 3186328539 | 媒体源1045 frame0未ready；effect alpha输出0，随后effective visibility=false，隐藏原因未资格。此告警不是已证可见失败。 |
| 3382111183 /3383210272 | 活动change3d在frontend拒vec3→vec2返回；3382111183另有粒子未准备，分别记录，不以空媒体文字归Script故障。 |
| 3622727585 | 活动better_blend被generic-owner-revoked拒绝，额外attribute仅声明未读，却挡住固定顶点ABI准入；尚未取得候选编译或输出，不直接扩大顶点输入。 |
| 3737267090 /3828126394 | 活动oscilloscope分别止于同名uniform binding alias和宏重定义准备。373的utility 4→3对应默认关闭的186；scene-color-completed属成功promotion记录，不混为实际capture失败。 |
| 3382111183 /3566323704 | 粒子loading incomplete，先核每层资源、有效显隐及原typed模块边界；不把所有候选未加载都判缺能力。 |

38份均未见VM异常、typed owner拒绝或非零Script teardown failure。7份共63个script wrapper、61个teardown owner、30个首次completed target是不同维度，不以数量差推未支持。21个作者Sound源均admitted/Ready且clock推进，另17份无Sound声明；未验可听播放。默认空媒体文字等待真实媒体事件，PCM不提供标题/封面；未触发的hover、热改、animationEvent及长Timeline不新增为缺口。

原archive增加可选base入口，仅新38沿既有normalizer投影；旧453行按值完全保留、原人工overlay字节不变，491行均有运行关联，原19个视觉fail保留，其余472 unreviewed。base副本和本次subset来源分别保留SHA，summary由合并行产生，不恢复或重新归一旧日志。最近17个archive/ledger行为方法通过，审查指出的重复census ID静默覆盖已在读取入口修正并单独复验，不为派生展示字段增加第二认证。新增运行只更新这38份；旧453后继修复不被追认为本轮重验。

必要声明、原报告/日志/runtime JSON、归因、旧base输入、行保留与来源收据归本机`corpus-incremental-20261029`正式证据包；普通14天、单包32MiB，不保留Workshop副本/HOME/App/PNG。后继未闭项只并入原队列的frontend、粒子和诊断观察职责，不另建样本专用清单；下一修复先确认活动effect的真实消费者和通用拒绝原因。

<a id="self-source-override-20261030"></a>
## 有效同层输入与闲置默认资产（2026-10-30后验）

原 schema 已把完整同层 composite 候选链证明成精确 effect ingress，captured-main consumer 却再次按未生效的 shader asset default 拒绝。原 conservation owner 现在直接承接该 fact，删两处 default 复验及无调用 helper，产品净减24行；保 regular、唯一活动源、完整 ready variants、binding/target/graph 身份，未新增 route、owner、状态或逐帧工作。真实 default、通用 absence fallback 和 foreign/mixed 边界不变；唯一合同见[Sampler 来源](../capabilities/sampler-alias-precedence.md#captured-main-self-override)。

最近真实 finalizer 六方法一次编译通过（106.558s），含改名/资源改名/两种等价采样方言、实际 graph 与 asset default 同时 ready、无override实际default、pending/incomplete、foreign/mixed、内部FB及冷暖一致；原作者源码的 CPU 对照先证有fact却 sourceSlot=nil。独立静态/运行证据审查通过。Debug build 与严格签名通过，owned source无漂移。

原3622727585默认624先前拒 `utility-source-program-unsupported`；修后642/649两Program实际GPU完成，649进入compositor及次帧。**最初after3s两图完全相同，只是开场遮挡，不能判正式效果失败。** 作者258全屏solid在0–8s不透明、10s退出，150/268同到10s，436到12s；按用户提醒保留原短窗report，两份仅有误请求hover的FAIL，不修改工具或洗绿。重新以同原包/默认属性/PCM及实际pointer序列取after15s、运行18s，两份raw report均PASS；root与独审亲看原图，候选下方示波器恢复灰白线，上方绿色线及主画面保持。整景随作者timeline/PCM仍动，不以全图差值宣同phase或官方parity。

稳定基线仅将本批自有conservation源临时恢复HEAD构建（46.835s），随后精确恢复候选并构建45.109s；两个独立App身份随必要结果保留。候选主体 `177c33b4…48aa` / dylib `43767361…9e24`，含同时存在的非Scene工作区修改，未纳入本批提交或收益。普通单样本仍4秒，仅已证开场代表延长；方法归[诊断合同](../development/corpus-diagnostic-workflow.md#log-first-corpus-audit)。

未参与修法的3747190633原包保留相邻健康路径：1897的后继1900显式self override且shader仍有asset default，1898→1900→1902全链GPU/末合成/次帧保持。原默认属性、PCM、after4s/4秒请求，原包无single开场timeline；实际normal runner最少7秒。root亲看人物、粒子、时钟、青色音频条与灰白线保留，strict PASS、exit0、surface1→0/GPU排空。不据截图判字体精确布局、动作相位或官方parity。

本批只退出624这项来源拒绝及其已证局部可见损失；356的无源producer、357/363用途/Combined及其他旧视觉问题仍留原队列。未测性能、HDR、多屏和外部真实音频；必要原图、原始短窗FAIL、稳定对照、身份、门与独审限量归档 `.artifacts/scene-evidence/runs/self-source-override-20261030/`。执行副本/HOME与重试缓存提取后清理，连续构建只留现役一份Debug缓存。

<a id="incremental-31-20261030"></a>
## 新增31份日志筛查（2026-10-30）

当前522目录相对已知453+38=491新增31、移除0；原静态双页只到453，本轮经原census一次完整生成并以原renderer纯投影同步522。521可解析，唯一旧3763323436缺project；新31全部可解析，旧491声明源身份/计数不变。全体226245声明点、5271结构family、2515参数profile、24803字段profile；新31为12110声明点，涉及703 family，其中新增113，参数新增19、字段profile新增97；新unknown/unclassified均0。

新31涉及15项已有注册能力，注册新增0。沿既有九类视觉路线及Sound旁路分组，本次有静态/序列、文字、文件/系统媒体、Puppet候选、直接模型声明、粒子与Effect/Utility七类视觉入口及Sound；未识别新视频TEX或SpotLight入口。不能把15能力、family/profile或包内model presence称独立加载链：仍一条共享主链、五类prepared产品，Script/Property/Timeline是控制面。新文本11包30对象、粒子24包88根层、684 effect instance；21包puppet定义与3包objects.model只是候选，不认已执行。

复用scene_diagnostic_build.xcconfig的优化DEBUG，原签名App主体a85e9618…4dff；首构81.406s有一个并行非Scene文件漂移，补一次增量42.694s后所有冻结输入无漂移/签名通过。为先验隔离再扩并发，沿原CLI分4份pilot和剩27份，各stage同一App一次、不另造staging owner；每worker独立副本/HOME/TMPDIR，Ready后4秒、PCM、pointer outside、无PNG，结束即删除worker执行环境。四份含最大655MB包，4并发均完成后剩余6并发。不是正式Release/WMO或性能比较。

31份均Ready、有graph GPU完成、exit0且surface1→0/GPU排空，无超时；raw25 PASS/6 FAIL。原normalizer有19条结构完成、12条degraded及18组事件，排序不等于因果首错，12也不等于12个缺图。image加载31、text11、puppet clip准备16、sprite2、粒子加载23/非空人口22、utility capture28包；这些层级不同，不代每组件正确。Sound处paused，未注入外部媒体或真实鼠标/属性事件，日志不能授官方画面/音频/全参数通过。

| 公共观察 | 本轮因果资格及后继 |
|---|---|
| effect输入/前端局部降级 | 2832796442有unused texture artifact及dynamicLoop后继；2861017657 previous-blurred-composite owner缺口；3358871872条件分支内对象宏重定义；2899371377显式LOD采样.r未形成redOnly用途proof。2857410102的91是未选预设，另128/428实际活跃链被末motionblur节点textureReferenceInvalid拒绝，不能混作同一noise用途问题。具体形态与下一门归[唯一队列](../roadmap/scene-open-breakpoint-queue.md#incremental-effect-20261030)。 |
| world-space Rope | 3141464346的188/332均真实dynamicSystemTransform拒绝，资源存在、正subdivision3，超出现动态root仅Sprite平移范围。332要scene约28.4s才显alpha，4秒不裁可见损失；并入原world-space项，不与负subdivision猜测合修。 |
| 五包solid观察 | 3280903509、3303319749、3347416586、3350026230、3357689320合计22层，21个instanced solid实际已沿asset通道加载white，仅1个procedural被parser计入。共享诊断漏计，不是五个缺纹理；原raw/normalized红项保留，工具待修并入合同债。 |
| Script异常 | 3028048463的init仅收visible player层，默认19层均隐藏，随后访问空数组playerLayers[0].alpha；现enumeration/visible/alpha/isScreensaver已有。3280903509的225.alpha挂了clearcolor脚本并返回Vec3，故BAD_RETURN；两者均未资格引擎缺API，不把Vec3强转标量。 302另有506.origin的authored mutation owner冲突（25条mutation、previous-current），不归入空数组错误，保原公共mutation待资格项。 |

原491归档行逐值不变，只用full snapshot的31行明确subset投影追加；未再次扫原包，未修改人工verdict。生成台账包含全部522，旧失败与最新队列分层，不把本轮当旧491复验。必要raw报告、日志、声明、来源投影/身份/独审限量归档 .artifacts/scene-evidence/runs/corpus-incremental-20261030/；截图未请求，用户新放“截屏/已粘贴”仅供后继正式阶段对照。执行方法归原诊断合同，项目skill只补入口与高成本误判经验。

<a id="lod-channel-use-20261030"></a>
## 显式LOD采样组件用途后验（2026-10-30）

原通道分析漏认已支持的二维LOD内建调用，2899371377的7810#7811两次直接.r因此无法沿已有redOnly/noise仲裁取得数据资源。修复在原TextureChannelAnalyzer复用现采样内建名/作者同名函数裁决、参数及括号解析，删两份私有解析；产品净减43行，无新owner、用途、MSL算法或普通帧分析。普通2D多参旧范围、仅普通2D的RGB颜色proof、非红/whole/间接调用及原资源边界保持。唯一语义归[标量数据合同](../capabilities/scalar-mask-data-purpose.md#lod-channel-use)。

原真实schema门仅新增LOD方法红：原两方法通过，86.589s；同393行fixture修后3/3通过，66.344s，15项取得预期组件事实、12项拒绝保持，8项普通2D多参结果逐值不变。相邻straight-color原8方法另一次28.230s通过。两组输入无漂移；Debug30.569s、严格签名通过，主体e51a6179…be1d/dylib e351d509…ed95，包含但未提交并行非本批修改。独立静态终审通过。

原289默认输入统一静音、无指针动作请求，沿原runner首图后复位outside；没有宣称全程从启动固定鼠标。取实际8s/约12s正式窗、运行15秒，不把粒子starttime15的预热误当延迟开场。旧原包为7811局部passthrough/两项strict FAIL；候选strict PASS，7811和7814均frame0/1 GPU完成、后缀末合成/次帧成立并正常释放。两次启动的背景形变、粒子、时钟相位不同，原图外围变化弱，**不从整图差值宣原包视觉强度恢复或官方parity**。

补一份自有静态因果载体：只保原solid和7810，固定蓝灰底/速度0，原clouds shader与两个mask、tint及其余常量不变；仅Bool从on切off。一个原PKG副本沿现VFS供资源，唯一loose入口不改原件。一次实际运行即strict PASS，live accepted、同一window/surface；两on原图逐像素相同、两off亦相同，on/off有明确外围云纹差，RGB均差3.443/3.949/4.475 U8、峰40；root亲见关闭后纹理消失。这只证明原作者Program在受控输入的实际遮罩贡献，不替代原整景感知/官方验收。协议曾预计off无rejectedNodes，但现字段实际记1；其Program为明确visibility-disabled activation-passthrough、outcome成功/GPU完成，保原字段和这项协议局限，不改产品或重跑洗绿。

未参与修法的3355587815原包短窗strict PASS，root亲看人物/背景与白色框形保留，实际Program/GPU及退出正常；不由非黑或加载数授整景通过。variant/demand key已有build producer语义identity，generator覆盖本次源码，未改持久字段、手工版本或新增运行时校验。跨进程磁盘暖重放、HDR/多屏、官方整景精确像素及性能未单独验；不报告性能收益。

本批仅退出上述通道识别首门，原31份raw归档与人工裁决保持，其他前端/粒子/属性及日志问题继续留队列。必要输入、红绿/邻门、固定App身份、原包正式图与静态对照、独审归档 .artifacts/scene-evidence/runs/lod-channel-use-20261030/；临时HOME/副本与多余帧提取后清理，仅留连续构建缓存。


<a id="previous-input-shadow-20261030"></a>
## 显式previous遮蔽旧named来源后验（2026-10-30）

2861017657的30层先waterflow107、后blur585；末combine槽2同时保存实例`_rt_imageLayerComposite_30_a`和显式`previous`图绑定。启动/普通帧已只选择后者，连graph absent也不回退named；原ExactPreviousInputShadow却仅允许primary遮蔽layerSource，误拒紧邻effectOutput，四pass整体降级。沿同一predicate让primary复用已有immediate producer条件，保primary layerSource、secondary限制、foreign/unspecified/非紧邻/歧义与唯一binding；产品净减3行，不改loader、shader数学、graph/history或输出owner，不将_a/_b解释成前序输出。captured-main外层仍先要求layerSource，未扩其资格。合同归[原准入设计](../capabilities/previous-blurred-composite-admission.md#previous-input-shadow)。

两组层/效果/target改名的真实Eligibility测试在旧产品准确6项RED，原其余检查通过（50.197s）；同一922行fixture修后2方法通过（47.997s）。另跑原GraphExecutor原子GPU门1方法/112.492s及Finalizer的graph override unavailable、实际effect ingress与captured-main terminal三方法/91.133s通过，保原失败边界。Debug30.184s/严格签名通过，主体074db96b…f7d4、dylib714baa14…a163；构建输入无本批漂移。独立审查核对selection、launch和demand都不采样lower named。上批删除重复参数/括号解析后漏收紧的两项defense计数已由原工具从4→3、13→12锁定，未放宽关卡。

原286同静音、Ready后3秒图/运行7秒：修前strict FAIL、blur四节点passthrough；候选strict PASS，blur四Program、两帧GPU完成且terminal compositor消费，前级waterflow保留。未参与修法的2866723317同候选strict PASS，亲看人物、红底和花枝完整。两例均exit0、surface1→0、GPU drained。官方目录参考已查看；原286两次雪粒/相机晃动相位不同，只认完整构图与执行恢复，不从整图差值推官方精确一致。

另用自有9000000585单背景载体保留原30层、水流和blur/mask，水流速度0、相机晃动关闭、无其他对象；唯一loose场景入口、原PKG字节副本，原件只读。仅Bool热切blur visible，单次strict PASS。两ON原图逐像素相同，四OFF亦相同；同window31681/surface1，live accepted，ON四blur pass→OFF typed activation-passthrough，两状态均GPU/末合成/次帧成立。预登记32px边界内RGB梯度ON0.997532、OFF1.723259，亲看右侧背景雪点和建筑按原mask组合软化；这是效果贡献而非性能指标。OFF rejectedNodes4表示visibility-disabled跳过四作者节点，failure=-，不当编译或GPU失败。只证明原shader与mask整体在静态输入有可见贡献，不分别授mask算法、原整景像素、完整Blur或官方parity。

本批只退出286上述首门，其他effect与视觉问题继续留唯一队列；全样本原raw归档、统计及人工verdict不改。必要身份、红绿/资源失败门、原包与静态图、独审归档`.artifacts/scene-evidence/runs/previous-input-shadow-20261030/`；临时副本/HOME/App与重复帧提取后清理，保一份连续构建缓存。未做Release、HDR/多屏、跨进程暖缓存或性能比较。


<a id="optimized-texture-interface-20261030"></a>
## 后端纹理接口与Variant发布后验（2026-10-30）

2832796442的活动project806#808单pass Bokeh在未调用depth helper中保有slot2声明；最终MSL只有0/1采样与接口，反射仍保旧声明，Builder先报textureUnused，使既有loop-guard重编也无法进入。修复仅在原unused且非Resolution分支懒扫一次编译MSL整数texture属性，明确不在物理接口才退出绑定；仍存在的read/gather/query、未知属性或反射/接口错配保原拒绝。原compiler词法投影移入既有LexicalScanner，属性扫描由既有TokenScanner共享，attachment私有重复退出；不新建MSL parser、owner或普通帧工作。合同先落[原metadata设计](../architecture/shader-metadata-failure-contract.md#optimized-texture-interface)，含失败与停止边界。

首次候选清除artifact首拒，基准总分PASS，但806实际仍报utility-source-program-unsupported、没有目标Program；原静态载体也因无资格/live拒绝而失败。这些是反证，保原报告，不能用总分结清。最早后继为Finalization仍把sourceActiveSamplers全集作为活动列表，与编译Program已缩窄的0/1不一致。最终沿原发布处复用既有activeSlots，一次投影sampler及source graph-input事实；源schema/VariantAnalysis保真，真正binding缺schema、错name及活跃identity/provenance分歧继续拒绝，不改captured-main消费者。五个产品文件净增38行，增加的是缺失的接口投影与两处既有scanner复用，无新持久字段/route/资源或输出owner。

真实compiler的两组helper/slot改名在旧Builder均textureUnused红、活动helper反例通过；直接Builder另两absent红，其余保留消费/错metadata反例通过。修后dead-binding19方法中18通过，1个旧固定请求因本机未提供其旧cache按原skip，非本批遗漏覆盖。包含真实Metal及同请求暖artifact一致性；此GREEN早于attachment未知值传播修正。独审新增重复texture0加未知属性反例，准确复现一次候选误准入后改正，最终attachment4方法/22.816s通过。原颜色2方法/37.634s保持，无须放宽旧失败helper。后继Finalization新投影及原资源/ingress/captured-main门共4方法/90.106s通过，覆盖cold/warm死2退出、活动0/2保留及missing/name/zero-padding反例；避免再跑已知源码直返的第二次RED，原包首候选反证承担前后基线。

最终签名Debug29.548s、五输入无漂移，主体c3b3afca…2c65/dylib8b464930…a8bf。原283同静音、Ready后3秒/7秒运行，806#808实际Program fcf421…进入frame0/1 GPU、material1/rejected0并由compositor消费；背景横线与纹理确有软化，人物构图保留。独立3265157904原包同App严格PASS，七pass Bokeh及其余画面保持，两份均exit0/surface1→0/GPU排空。官方目录“已粘贴”图已查看；不同viewport与动画phase不作精确golden。

自有9000000808保原project层/Bokeh shader和Strength1，仅给前级普通image换自绘静态棋盘，移除无关动画；原PKG副本与唯一loose入口，原件只读。载体输入未修正，首次失败由上述产品后继造成。最终单一Bool热切在同runtime7ea5…、window32179/surface1 accepted：两ON原图逐像素相同、四OFF亦同；ON同Program完成，OFF是明确visibility-disabled activation bypass（rejected1表示跳过作者节点、failure=-），两状态GPU/末合成/次帧成立。32px内ROI梯度ON8.295020、OFF13.733548，亲看格子软化/恢复锐利。这是实际原shader贡献，非性能指标，不外推完整Bokeh家族、原整景精确像素或官方parity。

仅退出283这条公开首门，其他effect/335宏等继续留队列，原522统计、raw记录及人工裁决不改。必要基线/失败首候选、最终身份/图证、真实测试与独审归档`.artifacts/scene-evidence/runs/dead-helper-texture-20261030/`；运行HOME/App、临时PKG/棋盘及重复帧提取后清理，只保同一连续构建缓存。未做Release、HDR/多屏、长稳或同条件性能测量；不认性能收益。

<a id="ordered-object-macro-20261030"></a>
## 2026-10-30：同种对象宏顺序替换与活动示波器恢复

3358871872的122#123、96#98在活动AUDIOTHICKNESS分支将对象宏由1.0重定义为表达式，旧Preprocessor先报conflicting-macro，两个pass均局部透传，横向波形缺失。默认GLOW0未消费thickFactor，收益是解除错误宏拒绝以恢复原活动pass，不认领新的发光/厚度算法。沿[原宏设计](../architecture/shader-metadata-failure-contract.md#ordered-object-macro-redefinition)仅删除同种作者对象宏不同replacement的三行拒绝；每directive前原finishExpansion及同一macros表已承担时序，不加parser、历史状态、帧工作或效果特判。selected combo/host、undef、种类切换、语法、实际递归及预算边界保持。

固定官方2.8.0.42/exe DAAC1EA7…DA07自有六格板独立资格object语义：完整loose及30项manifest校验，前后使用旧/新值；duplicate与显式undef正控成立，inactive定义不生效。两次实际JPEG（含Display ICC、桌面15:57/15:58，SHA不同）按嵌入ICC转sRGB，四角定位完整；D=ref00、U=C=ref01，各同帧ROI误差0，满足预登记3/255，ref11可区分。首次测量误用raw ICC RGB、随后额外对角标套像素3门的失败均保留；纠正只撤销非预注册角标像素门，原图、ROI与参考格容差不改。这里只证明该静态vertex/active条件对象宏，不外推官方host或种类切换语义。

最近真实graph→preprocessor门9方法/63输入：两组变量/路径改名的顺序用例精确line9冲突RED，其余通过；GREEN8.694s全通过。涵盖无括号replacement优先级、alias消费点、include/sourceMap/metadata、inactive/undef及selected/kind/递归/紧预算反例。首轮误将保留HLSL source define视为合法的夹具错误独立保留，修夹具不扩产品。

最终Debug31.095s、单产品输入无漂移、strict deep签名通过，exe46583ae2…0dcbe/dylibee525aaf…674c。原335同PCM fixture、Ready后3秒/4秒窗口严格FAIL→PASS；两个目标Program a8dfb56d…ac27均在frame0/1完成material1/rejected0、GPU与最终compositor/次帧，frame10左右32band输入实际非零。亲看原包两条横向波形从无到有，主体/其余背景保留；独立3350026230同App严格PASS，当前波形与画面正常；未采集其修前基线，不认领前后像素不变。两者均exit0、surface1→0/GPU排空。目录官方参考已查看，viewport/音频phase不同，不认精确形状、幅度、整景parity或完整周期。

原生自有板总报告PASS，六色可见，但全屏aspect-fill裁掉上下角标，违反其预登记定位门；像素资格保持UNKNOWN，不能以总分或肉眼相似追认本机板parity，也不为载体改产品/追加窗口链路。该限制独立于官方完整板与真实原包恢复。仅退出335这条首拒，原统计/verdict不重写。必要失败/成功报告、原335前后图、独立图、官方双图/manifest、测试和独审归`.artifacts/scene-evidence/runs/ordered-object-macro-20261030/`；本轮临时运行、复制输入及guest stage在停用后清理，保唯一既有构建缓存和VM主客户端。未测Release、HDR/多屏、长稳或同条件性能，不认性能收益。

<a id="declared-framebuffer-shadow-20261030"></a>
## 2026-10-30：声明 FBO 覆盖旧候选与整层效果链恢复

2857410102的128/428默认活动，旧Template先校验被同槽explicit graph framebuffer覆盖的实例RT字符串，报textureReferenceInvalid，导致两整层source-passthrough。当前frame/launch/demand本就不回落terminal explicit framebuffer的lower值，含graph unavailable；在[原准备owner](../capabilities/sampler-alias-precedence.md#declared-framebuffer-binding)一次投影执行候选到terminal，raw diagnostics原值/provenance/ordinal全保留，terminal仍走原context/universe/node-binding校验。不解析FullCompoBuffer后缀、不扩Vocabulary；previous及普通asset/provider候选链不变，无新owner/持久状态/帧工作。产品净增12行是这一缺失投影，不在renderer打补丁。

原真实Resolver/Template最近门两组改名32项RED22通过/10预期失败，GREEN32全通过；独审补lowerRT+无binding反例后仅补新方法9.481s。四个旧结构/graph/source/声明key邻门通过；首次调用拼错新方法名ERROR原样保留，没有重复四门。旧assetVFSBoundaries在RED/GREEN均false，未改VFS、未宣称全模板suite通过，作为旧口径债入队。原atomic GPU override门1/106.752s、Finalizer typed/unavailable门1/99.643s通过，保不可用graph不暴露lower资源。Debug30.709s、产品输入无漂移且strict deep签名通过；exe53600b96…291d4/dylibd3fea8b4…8257。

同PCM、Ready后3秒/4秒原包严格FAIL→PASS。128五effect、428六effect均实际执行，含五Shake、四WaterWaves与两个末MotionBlur；frame0/1均GPU完成，末端2material+1copy/rejected0、history seeded→reused/rehydrate1、compositor/次帧成立。独立3265157904严格PASS，620中段MotionBlur及末935保持history/最终输出；两者正常stop1→0/GPU排空。原包前后弓/发丝有变化，跨启动phase不作精确因果；目录官方黑底与当前默认金底设置不同，不作golden。

自有静态source载体仅灰底+原128、原模型/五效果/参数/masks/transform保真。v1用一Bool热切五效果被effectVisibility(128,4) consumer admission明确拒绝；这是已见三节点history效果显隐热更缺口，不改产品来迎合。唯一修正v2只切前四效果、MotionBlur始终开启：同一runtime/window32992/surface1（完整身份详ZIP），accepted=true；frame123四项inactive，MotionBlur继续history/末合成，正常停止。两次run均有连续PNG采样superseded，v1另有teardown capture失败；按预登记不再重跑，**注册因果资格UNKNOWN、原FAIL保留**。

已有v2完成图的观察另列：两张晚窗OFF及第三张逐像素相同；固定中央90% ROI中ON/OFF的≥3/255变化比例8.053919%、MAE1.337629/255，亲看弓与手部变形。这些是保留下来的实际观察，不升级为注册验收PASS、单独MotionBlur贡献、官方parity或原整景完整验收。只退出128/428已证FBO首拒；91未选预设noise及新显隐/验证债保队列。必要原包、失败载体/唯一修正、身份/图证、测试和独审归`.artifacts/scene-evidence/runs/declared-framebuffer-shadow-20261030/`；复制PKG/运行HOME/App/重复采样在归档后清理，保同一迭代构建缓存。未测Release、HDR/多屏、长稳或可比性能，不认性能收益。


<a id="source-less-stage-stop-20261030"></a>
## 无纹理颜色生成候选停止（2026-10-30）

3566323704的136/287活动audio_cable→pulse链仍缺金色波形；目录官方实机图可见底部曲线，native原包无该贡献。原AUDIOPROCESSING=3的最终fragment MSL无texture接口/采样，邻接pulse有slot0。仅此事实不能证明整个ready envelope已具备可执行颜色合同，不能直接把utility-source-program-unsupported归为一个consumer计数错误。

候选沿原CapturedMainSourceConservation/Stages加入自足颜色角色，要求实际空读取、resolved color、whole-write及精确输出，保原capture/graph/compositor。最近CPU门调用真实Admission→Stages：初始79.793s准确两正例红，78.698s绿；审查发现color target已透明清屏，原geometry路线不需额外footprint证明，删门后80.029s含缩小geometry的11场景通过。原internal-terminal门94.653s通过。两次Debug/严格签名及输入无漂移通过，首候选主体3ed7a577…2f08/dylib7e230c9e…241f；删footprint候选主体bd7940f1…e2ef/dylib6fe6d45f…ba0e。以上是实验资格，均不作为有效修复交付。

同PCM fixture、原包Ready后3秒/运行4秒，两候选136/287仍报同一source-route首拒，目标Program没有进入GPU，实际图底部波形未恢复；不能从总报告仅列particle loading incomplete认整链正常。独立3782614820在首候选短播PASS且实际人物构图保持，只是未受益当前运行；不冒充最终候选的完整回归。官方与native视口/音频相位不同，只作结构定位；不做精确像素或性能结论。正式阶段与预登记ROI按screen-top y64–97%，不把作者自底部Y误当屏幕顶部。

独审另指出：sole-node限制没有独立renderer必要性，逐variant直接升级角色还可能误拒混合internal/producer envelope。下次须先保留原source/internal一致性，再用真实整个envelope事实决定生成资格，不能靠新增数量门压缩证明。本轮按预定“无实际可见收益即停止扩大”退出，全部实验产品/测试和临时设计撤回至b8ad7998f，产品净变化0；队列仍开放，REFRACT粒子余项不混销。没有增加owner、状态、缓存或常规帧开销。

必要失败原始报告、App身份、RED/GREEN/审查结论与未验收补丁归档`.artifacts/scene-evidence/runs/source-less-stage-stop-20261030/`；原生after保全尺寸无损decodedRGB8及原PNG身份，不作raw HDR证据。清理本轮原图、副本、临时HOME和重试产物，仅保连续构建缓存；后续使用前须按恢复后的产品源重建，不能把缓存中实验App称为HEAD构建。


<a id="source-independent-graph-20261030"></a>
## 捕获输入可选的完整Program图（2026-10-30）

回到上述真实能力缺口后，136#137的实际ready envelope确认：cached reachability/输入身份齐全，binding/template为空，唯一variant实际texture/sampler/source facts为空，输出已为resolved straightAlpha；只有stored-channel事实unproven。原Stage末尾强制source consumer非零才是原有拒绝，首候选的redDefined、sole-node/footprint条件属于额外限制，不能反向成为正常颜色播放许可。临时诊断在另一Program的Int-key JSON序列化中退出，未到Ready；失败保留、诊断补丁已撤回，不能据该次运行宣播放通过或推287也已捕获。

设计先落[捕获输入可用性](../capabilities/scene-format-and-render-graph.md#captured-source-availability)：背景是可用ingress，合法图可以由UV/audio、clear/seed和内部FBO产生输出。TemplateAdmission、Variant Finalization、TargetPlan/ExecutionState、Executor和compositor已分别拥有身份、实际ABI、初始化/读写/copy/history、typed publication及最终颜色，不增origin状态、producer角色或平行flow。普通Stage删来源分类、consumer计数及first诊断状态；private来源角色/internal Bool退出，精确common slot只留给attachment replay。DIRECTDRAW和必要资源/数据门保持。另在原OutputAnalyzer用非loop准入syntax恢复支配写出事实，bounded预算不改；Builder删除normalized改名源码上无用的重复color分析，typed data分支保所需事实。产品5文件净减89行。

原行为Stage门5正例均ready/Plan通过却因旧source政策拒绝；修后生成→suffix两组改名、多节点seed→FBO→output、authored clear首读及source/generator混合variant均通过（82.202s），缺clear仍由Plan报historyRequired，foreign资源/target和data附件反例保原owner。初次夹具purpose拼错的编译失败及RED后依赖断言KeyError均原样保留，非产品失败。输出事实门原3自有/实际136共4项红；修后整模块31.377s通过，含旧正反例、冷暖Program transport和实际源码，bounded仍拒dynamicLoop。Finalizer整模块90.601s通过，保source-slot/replay、pending/incomplete、wrong layer/named/self、typed data及rollback边界。CPU准备/事实门不冒充GPU像素。

最终Debug30.612s、严格签名及5产品输入无漂移；主体36c6cb3b…a033/dylib f08f50b8…3e67。原356同PCM fixture、Ready后3秒/运行4秒，136/137→139和287/289→310四Program在frame0/1各material1、rejected0、GPU完成，pulse准确消费前effectOutput并被compositor消费；frame6四Program取得非零16-bin音频。亲看旧图、候选和目录官方图，底部金橙多线从缺失恢复；原前景/蝴蝶保持。独立3782614820同最终App短播PASS，人物构图保持。两例均exit0/未timeout、surface1→0、GPU drained；原356 strict仍FAIL，REFRACT/unsupportedRenderState等粒子诊断原样保留。

本批只退出136/287生成→pulse→末合成首门，不认精确频谱幅度/色相、相位、官方整景parity、HDR/多屏、长稳或性能收益；完整FBO/variant组合本批证明到CPU准备，原图资源执行owner未改。独审实际看前后、官方及heldout并核GPU/合成/停止，支持上述有界结论。全样本历史raw/统计与人工verdict不改。有效证据归`.artifacts/scene-evidence/runs/source-independent-graph-20261030/`，旧基线精确引用前包SHA；保必要原PNG、真实prepared源码和失败，清本轮副本/HOME/重试，只留一份连续构建缓存。日常能力优先及候选失败回到根因/设计的顺序已同步路线与顶层设计，不能再把实验失败当作改做覆盖小项的默认理由。

<a id="layer-mutation-owner-capacity-20261030"></a>
## 多owner图层事务容量（2026-10-30）

优先比较Combined、动态层与REFRACT后选本首断点：Combined已有group evaluator，但357七physical pass的逻辑control alias尚未资格；REFRACT颜色/normal目前共用UV，独立周期仍待证明，不猜算法。本批以真实3632522893的31.visibility为锚：init导出256 dirty DTO、update256，再加798/810/832的4条；原Swift全帧raw512在owner分组前把五个bundle全部拒绝。C不是重复导出；拒绝撤native newborn并清initialization_pending，JS bars[]仍持旧handle，后续owned-handle失败是连锁结果，不能复活或声称任意JS heap回滚。

按[现役设计](../roadmap/batch2/script-component-api-design.md#layer-mutation-owner-capacity)复用原grouped owner与fixed-point，在coalescing前按每owner raw512接纳；超额只拒责任owner。独立atomic apply保raw512，private重复入口guard退出，产品+8/−15净−7行，未新增owner、状态或配额数字。明确退役跨所有owner的全帧总raw512上界；总分组/应用成本随真实owner数增长，C每callback DTO256、topology8192、live动态256与VM预算不冒等价Swift全帧内存/墙钟上界。未来API规划的256 owner/frame与128live旧表述不再覆盖现役图层合同。

真实CPU原16矩阵RED96差异→最终5方法3.046s全绿，含换owner/target与owner顺序、raw512+peer4、raw513虽合并1仍局部拒、净零出生、public513整体拒、preflight未发布、原冲突/拓扑容量与peer保留。513夹具拆256+257只证明Swift admission，不作两个合法C callback证明。首GREEN夹具错误反转owner内部birth/destroy，8差异仅测试时序，已修为只调owner先后；产品两次运行相同，失败收据保留，不改旧断言洗绿。

Debug基于de1d6dc99+唯一Runtime文件，30.314s/零漂移/签名0；App `f07a0cb7…b660a`、dylib `876077e1…057dd`。同原包/确定性PCM/4秒窗，budget及VM拒绝5→0；frame1/2实际255 source publications/encoded、passthrough0、topologyRevision1，cacheHit false→true，GPU completed，原先缺失的山后白频谱实图恢复。两run仍有765#effect#772的原CPU/local-passthrough失败，不认整样本完成。独立3577990983的after人物、烟花、日期与底栏可见；ready确实黑、3.14秒后恢复，strict另有non-black失败。无修前同条件357，不能断新增/既存回归，也不能把入场截图当正式效果或洗成全门PASS。三run均正常stop1→0、GPU排空、VM teardown failures/timers/jobs/dynamicLayers全0；原图/身份与日志经独立Max审查，产品边界独立静态GO。

新工作负载未优化Debug CPU p50 9.642→19.537ms、driver59.09→28.90fps；修前没有255动态绘制，不作同工作收益/退化。额外关execution observer后19.536ms/31.97fps，成本仍在，不能全归诊断；这只是一次短窗、非Release/普通优化配置/稳态或能耗结论。首个no-observer+log-only命令被既有runner前置拒绝、未启动App，纠正参数后的实际run另保，不能计两轮测量；其缺观察器的strict缺项仍保。下一项先资格优化普通帧热点，见唯一性能卡。没有原生面板、官方同音源幅度、完整fade/长稳/多屏/HDR或全样本parity结论。

本机正式包`.artifacts/scene-evidence/runs/layer-mutation-owner-capacity-20261030/metadata/samples/0/runtime_evidence.zip`为14,834,101B/80成员、SHA `d5f14931…7c0a55`，普通14天；保363修前/修后原PNG与357 ready黑原PNG、完整日志/红绿/错误夹具/构建身份。357 after保1280px sRGB JPEG及原23.67MiB 16bit PNG的SHA，只证粗构图、不供原像素/亮度/HDR golden；初包38.34MB超单包上限未归档，去此非目标原图后重提取，无拆包规避。本轮临时执行环境归档后清理，仍只留`.build-cache/scene-gravity-20261028`连续缓存。VM/官方主客户端保持运行，未为本批重启或发起新官方实验。


<a id="user-priority-20261031"></a>
## 十包用户优先项的声明与短日志（2026-10-31）

本子集为[用户十包清单](../roadmap/scene-open-breakpoint-queue.md#user-priority-20261030)，不是十个新增目录或全corpus重扫。一次census解析10/10，4570声明、433结构family、422参数profile、951字段profile，251effect及25粒子层；这些不当独立加载链。沿原一条主链、五类产品和九类视觉诊断路线/Sound分组，snapshot保在本轮证据包，不覆盖全量生成双页或历史人工verdict。

优化DEBUG（Release配置加现役诊断xcconfig、arm64）baseline221.625s构建/签名通过，App bc4f4bf6…346e1d；每包Ready后4秒、并发2、确定性PCM、默认属性/受控指针，无PNG，61.431s完成。结构strict七过三败：298/303各两条effect准入/透传，314粒子未全载；其余七过只证明该短窗。335首轮play后永久stop仍属实际播放问题，短窗PASS不能盖过；382约28.57s动作、灯光phase、媒体/鼠标分支亦未闭。归一器solid计数五包是现役已知报告口径，338的初期layer-source-not-ready须连后续成功看，不把旧计数/恢复期重开为缺图。

逐owner追踪得到三条通用能力首错：298 rgbmask视频合同、303 float复合余数、314动画层rate/blend曲线及零速准备；后继分别在所属合同/批次记录验收，不能把一项修复销掉十包。另335首次Source时长快照仍待实际原包定因：生成H264观察创建时duration0、首publication为3秒，只作机制线索，不替代335数值证据。所有用户视觉观察保待复核，音频、指针、过渡与截图时机分开。

本机正式证据`.artifacts/scene-evidence/runs/user-priority-capabilities-20261031/`保原失败/完整日志、census/归一结果、App与输入身份及必要原图；不将日志七过、后继非黑或构建次数当画面一致率。全样本历史raw、统计双页和人工裁决本轮未重写。
