<!-- document-role: historical-evidence -->

# 开放断点队列对账与退出记录（2026-10-23 起）

> **历史证据 — 非现役入口**。10-23首次从原256行队列移出已闭首门、已解释反馈与纯未验范围；后继关闭按节注明实际运行，不将局部结果升为整样本PASS。未闭具体问题仍由[当前队列](../roadmap/scene-open-breakpoint-queue.md)维护，当前语义归能力/架构专题。

原队列SHA256 `84fffc77d349ac8748bb4607554748336ac8586fc62910bb334ee5134d31bd48`（80,674字节）；只读对账基于现代码、既有正式证据及近期提交，未新增App/VM或全库扫描。原字节和逐项去留映射暂存本机`.artifacts/scene-queue-reconciliation-20261023/`。本页仅索引有界结论，不复制原队列或各专项过程。原静态审计14类未闭问题已按公共owner合入同一现役队列，静态缺口仍不等于可见故障。

<a id="closed-first-gates"></a>
## 已关闭的公共首门

以下只关闭列明能力/现象。视口、相位、音源、全属性、HDR/Release、长稳及性能没有随局部修复自动通过；部分修复样本的具体余项仍在现役，历史关闭不能覆盖新补报。

| 样本 / 公共语义 | 有界关闭与证据 |
|---|---|
| 3808922316 · sort topology-only | 纯SORT退出property dirty/空DTO，原包三个visibility init完成，buffer异常退出；只闭此公共首错，无可见层序验收。[本批边界](#layer-sort-topology-only-20261029) |
| 3175039950 · dead-varying uniform投影 | Program218的无消费者inverse退出实际布局，原局部采集回绘首拒及未Ready退出；严格样本结果仍FAIL，不授整样本PASS。[本批边界](#dead-varying-uniform-20261029) |
| 3662790108 · provider文字发布/首提升 | 未adopt文字发布不再误作surface失效；原包由反复准备超时恢复一次held/Host提升，开场说明可见。只认启动恢复，球体/曲率/交互仍开放；无消费的Data误读不列引擎待修。[后验](text-publication-first-frame-2026-10-23.md) |
| 3321237804 · 普通视频首提升、主时钟 | 实际可见视频首publication及同次全surface/GPU完成后提升；冷暂停、改名双屏/坏源与旧active门支持有界首呈现。639字形不可表达时同链typographic重排恢复主HH:MM；不认seek目标同步/全部字体或整景parity。[视频](initial-video-presentation-2026-10-23.md)、[文字](../capabilities/runtime-evidence-current.md#native-text-bounds-20261022) |
| 281/299292 · Bool文字创建 | nil-path文本不再被图片路径门误拒；原文字/隐藏副本沿typed事务。阴影Off→Static受控副本偏移黑字可见，不外推默认姿态/精确XY。[后验](../capabilities/runtime-evidence-current.md#boolean-dynamic-text-20261021) |
| 374 · image font脚本值 | 合法String赋值不throw，保有界JS值而不吞任意错误；公开字体热切同surface生效，450异常1→0。默认crop/人物遮挡、34字体未全验。[后验](../capabilities/runtime-evidence-current.md#image-font-script-state-20261020) |
| 302 · graph-final多槽与直接锚点 | 216/328的阶段守恒/命名绑定首拒退出；可见封面从白占位恢复非均匀梯度，216默认隐藏仅认准备首拒关闭，不认默认像素收益。[后验](../capabilities/runtime-evidence-current.md#optional-graph-output-slot-vector-20261020) |
| 338 · prepared音频/颜色来源 | 306/effect364启动与编译首拒退出，Program/GPU/合成/次帧成立；ink归因仍不可靠，整景unreviewed，不把旧fallback续列故障。[后验](../capabilities/runtime-evidence-current.md#audio-packed-source-view-20261020) |
| 329 · 骨架/四元数、条件动画与数组 | 默认34站位/连续变姿、单臂闪骨、动作控件及保存/reset有实际关闭；音频rate、同session条件热切、437数组/白波形和多色大片各有有界后验。仍不升整样本；后继首呈现批329旧/新同有utility505/七graph失败，原NON-PASS不充新回归。[骨架](../capabilities/runtime-evidence-current.md#direct-model-skeletal-animation-20261019)、[连续性](../capabilities/runtime-evidence-current.md#puppet-rotation-continuity-20261020)、[数组](../capabilities/runtime-evidence-current.md#generic-varying-array-20261021)、[截面](../capabilities/runtime-evidence-current.md#screen-displacement-ribbon-20261020) |
| 3226487183 · 眼/脸颈/点击色散 | 默认眼/动画、脸颈组装和2522点击非零Alpha进入作者Program，瞬态RGB分离/回清晰黑面具成立；手部反馈仍开放。[后验](../capabilities/runtime-evidence-current.md#shader-float2-consumer-width-20261017) |
| 382 · 右上两束光 | sampler presence不再被editor require阻断，默认恢复蓝白光并实际执行/末合成/次帧；format条件未扩。[后验](../capabilities/runtime-evidence-current.md#sampler-presence-requirements-20261017) |
| 3577990983 /3616389236 · 人物/底栏与dock | 357 counted targets恢复中央人物；usershortcut保底图后16透明花叶恢复，210二维fallback恢复半透明dock；361顶部8链环恢复。文件/目录/App配置打开获用户确认；357 aux/233/320与hover仍开放。[人物](../capabilities/runtime-evidence-current.md#puppet-multi-target-20261017)、[底图](../capabilities/runtime-evidence-current.md#user-shortcut-authored-fallback-20261017)、[dock](../capabilities/runtime-evidence-current.md#shader-vec2-authored-fallback-20261018) |
| 3022080536 · 静态mesh format9/20B | 原bind/UV/world链恢复纸底/书法/双印，主体动画及独立legacy16/52保持。[后验](../capabilities/runtime-evidence-current.md#mdl-static-position-uv20-20261017) |
| 3599986633 · 空effect lookup | 官方空集合返回null的已资格合同接回原handle，作者alpha journal解除177黑幕，九凤主幅恢复；702 destroy旧观察不是此缺图根因。[后验](../capabilities/runtime-evidence-current.md#empty-effect-lookup-20261017) |
| 317 · mix值边界 | 七条mix异常退出、56按下/释放尺寸响应恢复；仅此反馈，不认全部标题/粒子/播放。[后验](../capabilities/runtime-evidence-current.md#wemath-mix-value-boundary-20261017) |
| 2964778792 · world root origin/stop | 动态origin准备和74.stop首门退出，原包第一idle黑Z已可见；截图协议失败仍保，不升整样本。[后验](../capabilities/runtime-evidence-current.md#particle-root-world-translation-20261017) |
| 3795384177 · Count5省略字段 | 原122/116沿plan补四个编辑器默认字段，两源初始化/GPU及主体保留；严格golden仍STOP，不认全局phase/basis/速度或外圈样式。[后验](../capabilities/runtime-evidence-current.md#particle-position-defaults-20261023) |
| 3707474273 /3775655074 · 顶层组合根FX | 五根15个pixelate/VHS/pulse实际Program/GPU/末消费/次帧，TV马赛克/噪声/RGB边恢复。仅顶层正交普通成员、无utility后代，保隐藏往返/旧nested及独立378；不认精确grid/alpha。[后验](../capabilities/runtime-evidence-current.md#compose-subtree-qualification-20261021) |
| 3782614820 /3802005866 · 组合本地边界 | 前者五人物接缝与四黑线对齐；后者蓝条/框外白细线退出、框内频谱保持。普通成员组复用原pool/输出并补根alpha一次消费，不把白框当作者clip声明。[378](../capabilities/runtime-evidence-current.md#composition-background-bounds-20261022)、[380](../capabilities/runtime-evidence-current.md#composition-member-bounds-20261018) |
| 1994794519 · 末材质投影/物理鼠标 | 原三点恢复目标揭露；固定视口真实鼠标左/中/右获用户确认贴合。更多DPI/多屏/属性未验，不关闭357的独立hover报告。[后验](../capabilities/runtime-evidence-current.md#image-terminal-placement-20261021) |
| 2999907577 · opaque辅助颜色边界 | 默认7号金属流体背景/上文字恢复，原节点执行及stop/drain成立，不升全部模式/精细灯光。[后验](../capabilities/runtime-evidence-current.md#independent-signal-opaque-auxiliary-20261021) |
| 3448845950 · 启动锚点/颜色Vec3.equals及左上白卡 | 691零帧依赖错配退出；持续typed颜色正常。后继固定普通组合local source后，原包多余左上白卡退出、下背板/时钟/唱片保留；泛称布局余项不再无依据占待修队列，不认整景parity。[启动](../capabilities/runtime-evidence-current.md#named-dependency-direct-anchor-20261020)、[颜色](../capabilities/runtime-evidence-current.md#vec3-equals-color-20261021)、[局部源](composition-root-effect-local-source-2026-10-23.md) |
| 3745828537 · Sprite coverage | 原51/65花簇恢复两侧/四角，人物前景保持；200秒预热仍受预算，未因此开放Rope958。[后验](../capabilities/runtime-evidence-current.md#sprite-alpha-coverage-20261020) |
| 2849382252 /3748311238 · 源密度/轴域 | 前者三弧恢复连续白芯；后者柱盖高端悬留退出、继续移动且圆角恢复，用户最新实测正常。旧末弧原型STOP不追认。[密度](../capabilities/runtime-evidence-current.md#background-terminal-density-20261019)、[轴域](../capabilities/runtime-evidence-current.md#utility-axis-domain-20261019) |
| 3554161528 /3581882134 /3603711180 · 开场镜头 | 原包由始终全景恢复近→全，关Opening直接全景反例保持；只闭镜头缺失，不代验358光照/360其他profile。[后验](../capabilities/runtime-evidence-current.md#default-camera-single-20261019) |
| 3754630802 · 骨架source XYZ | 源Z清零反例定位蒙皮前丢Z；实际两次开→闭→开恢复，不认完整30秒/所有动画。[后验](../capabilities/runtime-evidence-current.md#u27-lion-blink-qualification-20261018) |
| 2974757317 · 合法无回调Bool模块 | 屏外origin首值保留，卡片下重复矩形退出；未改AudioBars/mask/作者坐标。[后验](../capabilities/runtime-evidence-current.md#u25-u35-current-qualification-20261018) |
| 3396722575 /3617056047 /3471294034 | modern dense常量轨道恢复发/身体动画；静态mesh基适配恢复正向罐体/圆内位置；selected provider恢复菱形网格。各只关原反馈。[dense](../capabilities/runtime-evidence-current.md#constant-dense-state1-20261018)、[基适配](../capabilities/runtime-evidence-current.md#static-model-canvas-basis-20261018)、[provider](../capabilities/runtime-evidence-current.md#selected-provider-admission-20261018) |
| 3337494481 /2887542690 · 共享输出/局部构图首门 | 前者五层主源和白音频条/模型共享深度首门已退出，侧clock/date跨面文字和整体构图仍未闭；后者composition创建、286控制及限定透视回绘已接，旧外悬蓝条退出，图框内音频无正证。分别保[文字资格STOP](../capabilities/runtime-evidence-current.md#native-text-depth-qualification-20261023)与[局部透视边界](composition-local-perspective-2026-10-16.md)，不合并成整景通过。 |
| 3042492564 · additive与camera setter | X炫光恢复白亮，关Shine保持；默认camera alias setter事务首拒退出、实际属性热改同surface生效。默认XY夹零不认默认布局收益，光束/封面blur/媒体交互仍开放。[additive](../capabilities/runtime-evidence-current.md#builtin-image-additive-rgb-20261022)、[D4](../roadmap/batch2/script-component-api-design.md#default-camera-origin-setter) |
| 3768724269 /3743305891 /3233141951 /3769364482 | 分别关闭sunrays同代开关/startup-false、频谱白条非零/静音收回、Timeline实际导出/肩颈火焰淡出、基本loop/opacity。光形尺寸/轨迹/风格等现役余项不合并关闭。[显隐](../capabilities/runtime-evidence-current.md#quad-visibility-live-20261020)、[频谱](source-material-entry-2026-10-08.md#perspective-neutral-tint-20261019)、[Timeline](../capabilities/runtime-evidence-current.md#combined-timeline-playback-20261017)、[loop](../capabilities/runtime-evidence-current.md#u37-scalar-loop-20261018) |
| DEBUG诊断/宏合同 | pointer after按请求deadline、晚互动与关闭反例已闭；378退休1780不再复活进expected集合；跨物理行函数宏同一展开owner恢复两侧红。旧早图不追认；宏批独立347正常stop未验、原FAIL保留。[时序](../development/corpus-diagnostic-workflow.md#evidence-capture-timing)、[退休](../capabilities/runtime-evidence-current.md#retired-layer-diagnostic-20261023)、[宏](../capabilities/runtime-evidence-current.md#logical-macro-invocation-20261018) |
| 图片灯光family/四点域 | genericimage4的lpoint/directional与source-proven四点域已接；仅固定24/20/0及实际332位置收益等有界范围，R2不完整点集保unit。旧point增益/更宽BRDF不是本批关闭。[灯光](builtin-image-light-families-2026-10-23.md)、[四点域](authored-direct-draw-domain-2026-10-23.md) |

<a id="bounded-feedback-exits"></a>
## 其他已闭或已解释反馈

“未复现/本窗正常”只撤对应实现候选，不证明所有状态正常；出现新同身份反例仍可重开。下表不复用旧FAIL制造当前故障。

| 样本 | 退出依据与限制 |
|---|---|
| 2784267518 | 眼内强/零PCM及关181四窗支持轻微响应，退出“完全无响应”；不认官方同声源强度/halo一致。[证据](../capabilities/runtime-evidence-current.md#pulse-eye-response-278-20261021) |
| 3766299002 | 两主题原visibility单向热变与脸/眼覆盖成立，笼统开关异常本窗未复现；未验完整往返/真实面板或持久化。 |
| 3742497499 /3822822401 | 用户解释时钟需鼠标拼合、蝴蝶延迟正常，撤早图缺失候选；374距离/death child及382 scalar拒绝仍开放。 |
| 3585542943 /3603711180 | 12秒原图可辨青绿照明/帘发肩光，笼统缺光本窗不成立，不认精确强度/形态；3581882134色温差仍保。[复验](../capabilities/runtime-evidence-current.md#u02-three-lighting-fresh-20261018) |
| 3351163962 | 同908×590默认hour/seconds/greeting相对环心差≤1.643px，低于事前4px门；仅闭旧范围，新补报文字超环仍保。[对照](../capabilities/runtime-evidence-current.md#u25-u35-current-qualification-20261018) |
| 3750342273 /3797217144 | 前者七点归一化输入山体移动回中心、零深度字固定，不复现完全无视差；后者原输入人物转正、基础入场恢复。真实鼠标/精确gain与响应曲线parity未验。[视差](../capabilities/runtime-evidence-current.md#parallax-depth-omission-20261018)、[入场](../capabilities/runtime-evidence-current.md#single-timeline-response-fallback-20261018) |
| 3605722997 /1695673397 | 前者默认只见裙脚由animation=false对照归18秒入场phase；后者同aspect灰带占比差≤预锁1个百分点。退出相机/拉伸遮边修法，不推所有比例或其余脚本正常。[灰带](default-2d-camera-inputs-2026-10-16.md#169露底资格与正常比例差异) |
| 3088601835 | 用户认为雪雾较正常、官方亦过曝；无新具体差异，退出调色待修，不认全条件通过。[原反馈](../capabilities/runtime-evidence-current.md#e-2026-09-27-user-retest-priorities) |
| 833227004 /2797913147 /3748311238 /2932631210 /2813231542 | 原流动/主体缺失分别有多帧source、旧mesh/精确atlas及原图关闭；293背景漩涡仍保。[source](source-material-entry-2026-10-08.md)、[主体](../capabilities/runtime-evidence-current.md#e-2026-09-14-missing-subject-refresh) |
| 3113287126 /3264246690 /3807668787 | 分别只闭琴/手锚点、头/左肘与口罩、头冠/音频；方向数量、AA/警戒带、958轨迹仍在现役，不整样本销账。[锚点](../capabilities/runtime-evidence-current.md#e-2026-09-27-puppet-legacy-attachments)、[口罩](authored-layer-retirement-2026-10-07.md#project-visibility-complete-retirement) |
| 3122339805 | 两窗口拖动/文字X偏移及媒体后桌面停帧有实际关闭；连续拖动/全部设置未验不新建故障。[事件](event-visibility-persistence-2026-10-10.md)、[桌面](terminal-attachment-desktop-freeze-2026-10-10.md) |
| 3232289987 /3587571382 /3238423642 | 原头发五官/右臂组装、额头视差裂缝、头错位分别有实际关闭；323842旧18.7FPS未资格，不算当前掉帧或性能已修。[v21](../capabilities/runtime-evidence-current.md#e-2026-10-08-puppet-v21)、[视差](../capabilities/runtime-evidence-current.md#e-2026-10-08-inherited-parallax)、[矩阵](../capabilities/scene-sample-debug-ledger.md#2026-09-13-3238423642-scenescript-world-matrix-与作者布局初始化) |
| 3357627941 /3662390671 | 原本地视频选择/WebM缺图有真实前景关闭，更宽codec不是原报告。[选择](user-property-video-2026-10-16.md)、[WebM](embedded-webm-video-2026-10-10.md) |
| 3747190633 /3807151772 /3782740481 | 原条带/三环在受控非零输入中可见，退出完全缺失；外部声源/幅度parity未验。[条带](../capabilities/runtime-evidence-current.md#e-2026-10-08-localized-graph-input)、[三环](named-timeline-interaction-2026-10-10.md) |
| 3765760121 /3788734811 /3787382101 | 默认鱼眼/卡片倒置已有实际反馈关闭；Water Waves六组A/B只作用对应mask，旧“全身受影响”过期，不改整体verdict。[裁决](../capabilities/scene-sample-debug-ledger.md#用户可见失败待办按当前复现更新不以公共修复代替逐项验收)、[mask](../capabilities/runtime-evidence-current.md#2026-09-13-3787382101-water-waves-作者-mask-同构-ab) |
| 3796588443 /3804441338 /3806337293 | 网点混合/频谱、镂空框时间日期、灰层过曝/缺环及路径自转各有有界关闭；后者无Candidate solid保作者1024²，椭圆轴稳定而点列继续动，不认精确速度。[网点](shared-shader-type-compatibility-2026-10-09.md#solid源尺寸后继)、[框](../capabilities/runtime-evidence-current.md#e-2026-10-08-frame-declaration)、[solid](../capabilities/runtime-evidence-current.md#procedural-solid-local-source-20261018) |
| 3793998447 /3299228616 /2932157836 /3420215721 | 分别撤默认整环Program不支持、滚动背景矩形、timer跨owner取消首错、封面依赖freeze；音频/水波、spin/媒体仲裁与亮度余项仍在现役。[环](../capabilities/runtime-evidence-current.md#u10-active-ring-20261018)、[背景](../capabilities/runtime-evidence-current.md#childless-passthrough-background-20261018)、[timer](../capabilities/runtime-evidence-current.md#shared-timer-cancellation-20261018)、[freeze](terminal-attachment-desktop-freeze-2026-10-10.md#u24-cover-dependency) |
| 3724289844 | 半帧率限定于未优化Debug；同源优化Debug普通窗达目标。停止timer/clock/history改动，不认整体性能或温度根因。[资格](../capabilities/runtime-evidence-current.md#water-cadence-qualification-20261021) |

<a id="identity-and-qualification-boundaries"></a>
## 不是已修结论的退出与边界

| 旧项 | 保留的未知 / 当前归属 |
|---|---|
| 3509243656关闭身份债 | 旧[实机正常记录](../capabilities/scene-sample-debug-ledger.md#用户可见失败待办按当前复现更新不以公共修复代替逐项验收)缺强App/输入/图片身份；只退出依据旧fail重开开场/模拟/坐标的产品实施，补链仍待办，不记HEAD通过或新修复。 |
| 3610154602缺席控件/祖父 | 435/423异常依赖缺席播放器控件/不存在祖父，现lookup合同已执行；动态导入是否应提供producer未知。先有合法producer证据再开共享首错，非“已修/作者错误”。正式`texture-animation-owner-qualification-20261016`保原资格。 |
| 3078285611容器数值强制 | effect6/22/24对整个scriptProperties容器算术，健康5读Number成员；无whole-container特殊数值合同。只退出缺API/重复numeric修法，不认官方结果或作者错误；中性收据`307-speed-consumer-research-20261016/qualification.json`保持UNKNOWN。 |
| 3766387484 /3792817546 /3790726145 /2986218263 | 已恢复旧clock/date或CP/Rope/pointer首门，剩“其他effect/原生输入/官方UV颜色未验”仅归[能力台账](../capabilities/coverage-ledger.md)及专题；新具体现象才入队，不当修复或缺陷。 |
| 光照/RF05与更宽profile | 旧point增益/spot父scale/更广BRDF、物理多屏/异步故障组合、LUT/alpha/nested/Puppet/Vec4/HDR等未验范围归[光照](../capabilities/lighting-sample-inventory.md)、[输入/lifecycle](../capabilities/runtime-input-property-coverage.md)、[材质](../capabilities/render-graph-shader-coverage.md)/[对象](../capabilities/advanced-object-coverage.md)；没有具体可达反例不占当前故障队列，亦不声明已修。 |
| 属性声明候选 | visibility slider/缺定义、condition-only Combo、maxwidth声明不自动等于热更缺口；314 fireplacesound已属Sound mixed修复，304 clock_lang有真实text consumer。未知组合归[属性输入](../capabilities/runtime-input-property-coverage.md)，不另造condition/value-only旁路。 |

<a id="intake-and-evidence-context"></a>
## 历史采集背景与使用限制

10-21新增24包、后继5包和10-22新增17包均是当时固定短窗运行，不刷新人工整体验收。17包无官方“截屏”、默认20秒/固定PCM/中心pointer及5/10/15秒系列；当时目录373、矩阵17PASS只属运行门，全部视觉unreviewed。旧pointer路径约2秒写after的图不追认请求8秒；后继调度修复只约束新采集。旧[N组](new-scene-intake-2026-10-11.md)及[3221354414首诊](../capabilities/runtime-evidence-current.md#intake-3221354414-20261017)同属历史入口。批身份/分母不在本记录继续维护，见[运行索引](../capabilities/runtime-evidence-current.md#intake-20261022)和[台账](../capabilities/scene-sample-acceptance-ledger.md)。

旧证据路径被清理不撤销已限定后验，也不提供新的当前身份；STOP、无golden、无可见consumer与执行计数均不能补出像素裁决。真实反馈待复验仍在现役；本次只调整文档职责，不新增算法、测量或性能收益。

<a id="static-audit-retirement"></a>
## 静态审计退役与已闭范围

原`scene-full-sample-static-audit.md`的14类真实残余已合入当前队列的12个公共条目，保留首owner、缺失消费者与退出门；独立问题文档删除，不另留现役副本。整理前55行版本可由`git show 3ce7adae2:docs/scene/roadmap/scene-full-sample-static-audit.md`追溯；本次逐项映射及源身份归本机限期证据，不能由静态迁移认领新运行或修复。

退出当前待办的静态过程包括：direct默认骨骼/条件热切与rate脚本、neutral恒定state1、Puppet单alpha贡献、root world平移与未声明peer的同帧adoption、已准备Puppet/普通图片/空composition窄片、genericimage4 directional、32项varying、native shortcut及普通Timeline基础关键帧。各自范围和后验仍由能力合同与既有运行记录持有，非中性channel、多个alpha贡献、更广空间/材质/volume等残余没有随之关闭。任意shader派发键、editor metadata、未知MDLA尾部、未复现旧截图与未验golden不再独立充当缺陷；没有把这些未知写成已支持。

<a id="neutral-instance-cover-20261028"></a>
## 2026-10-28：实例封面默认覆盖

`73be060b1` 的 `3042492564` / `2932157836` 在自建非白封面已发布、Store ready 后，base provider 仍为0 binding / 1 rejected，原图分别呈灰白/全白占位。根因是合法实例 fallback 与 stock 中性默认纹理不等时被准备期提前拒绝；stock 自带 slot/VERSION 又不能冒充 procedural neutral。

原 `SceneBaseMaterialProviderBindingCompiler` 允许已支持的普通单 pass builtin 中性默认 slot 被实例颜色资产覆盖，复用原 fallbackAsset/demand/Store/typed frame/末合成；不改 blend、alpha、shader 算法、生命周期或资源认证，不增加 owner、持久状态和帧内运算。新许可仅消费普通 VERSION1–2 且无常量/动态 shader 值的材质；未知/多槽/多pass/数据用途仍按原链局部拒绝，等值旧路保持。产品净增7行，新增内容只表达此前丢失的覆盖关系。

同签名 Debug、零频谱/30FPS请求下，两包实际 A（橙/青/黄）→B（绿/紫/蓝）→clear 均能换图并回到作者旋转音乐图标，构图与时钟仍在；第一张 ready 尚处作者过渡，后继稳定A已显示，未假称瞬时首帧。两包 current base binding 变1、rejected变0；预先选定封面ROI的白像素占比由93.5%/约100%降为A/B的0%，仅为该ROI观察，非整景相似度。各14秒正常退出，surface1→0/GPU drained。

未参与修法的 `3617056047` 同App8秒保罐体、圆环与文字，正常退出；它只提供相邻材质/合成回归，不认物理、媒体或官方parity。最近 provider 行为门通过，含 current/previous、资源与模型改名、loaded组合/常量/动态值反例和旧等值路径；独审指出的 loaded材质范围P2已修，最终无开放P1/P2。Debug构建与4447产品输入无漂移、严格签名通过。普通App/daemon实时系统媒体来源、全部属性、HDR/多屏及性能未另验；不变更人工整样本verdict。队列仅退出白覆子问题，原光束/blur/精确spin及媒体仲裁余项保留。

正式证据：主仓 `.artifacts/scene-evidence/runs/neutral-instance-cover-20261028-{304,293,control}/`；两样本各保修前、稳定A/B/clear原图及日志，公共包保存App/输入身份、最近门、构建与独审摘要。普通14天、单包32MiB/总5GiB；运行副本、App/HOME和构建缓存当批清理。

本轮另续接318重力研究，未改求解器：官方2.8.0.42载体可显示BASE，但自动阶段多次错过HOLD；改为离散属性后未确认命令改变阶段，仍缺实际HOLD正控制，不据getter/文字或该结果拟合重力、质量与增益。U40仍未修，保原unsupported边界；后续须先解决实验控制，再扩消费者。

<a id="particle-audio-mode-default-20261028"></a>
## 2026-10-28：未启用音频的粒子继续出生

`b3b83d635` 原302在相同固定pointer静止后移动、零PCM的14秒窗中，layer52仅一个child template，red_fire因bounds/exponent残值被推定音频而`outsideStrictStaticProfile`整拒；根与黑Rope同点又无可绘线段，纸面无烟。旧9月“消除红烟”只是藏掉合法child，不能作为音频默认合同。

固定官方2.8.0.42（exe SHA `daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07`）沿原302全部资产/父子图、定点CP和自有16band精确peak标签，三臂只变red_fire emitter/initializer的mode为省略/0/3。OFF、NIL各两张原图均在`p=0`持续出灰褐烟，ON3无烟；这只裁定省略mode关闭，不证明非零FFT、公式、RNG或完整轨迹等价。载体改动、原包及各臂身份、命令和原图随证据保留，未复制官方实现。

原声明owner改为`(mode ?? 0) != 0`，prepared Plan仅从显式有效mode建立声道，删除nil→Center及重复启用判断。辅助字段保真，未知显式非零沿原局部拒绝；child guard、parser、数值/evaluator、资源与末合成不变。产品净减23行，无新owner、状态、缓存、校验层或普通帧工作。19项音频门与runtime49项执行/10项外部语料未配置跳过通过，覆盖nil/null/0及残值、显式三声道/坏模式、声源无关、改名/等价声明、static child固定和移动pointer；现有显式音频child拒绝反例保持。独立审查无P1/P2。

冻结4447产品输入无漂移，正常签名Debug App主程序 `bed67719…d4e2d`、dylib `91a89c3d…c6248` 构建及严格签名通过。原302同14秒静止→移动在零PCM及受控非零PCM下均可见静止烟团，移动阶段child输出从1批变2批、原Rope链保持，未由离散图认领完整连续尾迹；child templates变2、unsupported变0；主体与背景保持，两run均exit0、surface1→0/GPU drained。未参与修法的366同App8秒保人物、机甲、背景与栏排构图，正常退出；它的可达同族child也不再被默认模式挡住，但该短窗不认精确烟团贡献或全景parity。无性能比较，新增烟团的实际渲染成本未测。

**仍开放**：原302候选烟团偏红，官方定点烟为灰褐，出生恢复不等于水墨颜色已对齐。后继独立颜色载体PLAIN和RGB1见明亮烟团，但RGB255请求未确认标签切换，自动输入也返回`noWindowsAvailable`，本次单位假设保持UNKNOWN；不据此除255、调gain/混合或修改ColorChange。显式音频child emitter、FFT响应幅度、更多颜色/继承/材质组合、HDR/多屏及完整样本均未验。定向包内普查378包/1014 particle JSON见19样本29条无mode辅助残值，只说明声明覆盖，不宣称29处可见恢复，也不刷新全样本裁决。

正式证据：主仓`.artifacts/scene-evidence/runs/particle-audio-mode-default-20261028-{302,control}/`，保修前/修后必要原图、官方三臂与未完整颜色试验、输入/App/源补丁、最近门、构建和审查摘要；普通14天、单包32MiB/总5GiB。只关闭缺省mode错误启用所致的整拒子问题，颜色继续留在唯一队列。运行副本/临时HOME及不再使用的App/重试产物提取后清理，连续迭代仅保一份缓存与当前App。

<a id="cross-layer-animation-seek-20261028"></a>
## 2026-10-28 普通 owner 跨层动画定位

**问题与结果。** 2887099508 的395.visibility在init定位其他layer的已准备Puppet动画，旧普通layer handle缺getAnimationLayer；修首方法后仍缺普通Timeline.setFrame，任一throw会撤回整包。现沿原LayerAccessHandle→同domain catalog/journal→typed owner effects→原Puppet/Timeline Runtime接通，删除caller必须是nested及source/target同parent的耦合；没有第二owner/clock/cache。visible写入和ended注册仍只允许exact nested self。普通Timeline seek保小数、playing/paused和group共享位置；采样边界沿原sampler，有限越界未称官方parity。

**真实准备首错。** API-only候选App SHA `561251f8e86a00c4ddadcf036d2afec450705eb6f8607f397c071bbc9fca7c12`仍出现395 RangeError：四个目标默认hidden，旧Selector未留下可寻址槽。现仅Puppet LayerLoad显式保留可用static-hidden槽；DirectModel默认不扩。槽保持authored index/id和visible=false，资源按MDLA ID准备一次，坏optional只失去该槽；坏required保原失败。新增静态槽不挤走既有visible/bound/scripted的alpha/reference组合；未知aux scalar仍未开放。独审发现全optional失败误退bind，已用真实reference顶点反例修正为复用原已准备reference，无重复prepare。

**固定输入与最终消费者。** 基线工作区a4cf10c4c，UI并行19aabeb42为不重叠提交；最终Debug由19aabeb42加本批15产品文件构建，签名校验及编译前后产品输入无漂移，App SHA `1d07c360e5df2337416beb64346ad5e72664fb314c45b55e87964ec14fd3063f`。288原包只读复制、默认属性、零FFT、中心hover，12秒窗口：395无异常/整包拒绝；309/index0/id443/clip422、325/index3/id532/clip505、175/index1/id408/clip672、162/index1/id412/clip508均从0到29，后续保持29且visible=false。blush22实际target为313/effect1/pass0/amount，原日志elapsedFrames=29/value=0.0015266175703933247，进入generic effect consumer。主画面人物、腿、书本、背景保持，未自动显示隐藏动作；265相机TypeError仍明确在队列，不能称288整景已修。

**反例与独立样本。** 既有真实C/ABI/Swift门覆盖普通caller与接收层分域、name/index/改名/等价表达、无nested/最后nested退休后的catalog、borrowed/value-only/stale/pending retirement、exact-self可见/ended；普通Timeline含小数、paused/playing、group及当前/命名句柄。真实fixed-point门将四Puppet与一个effect Timeline、layer mutation放同init：晚C throw或Swift拒绝整owner撤回，健康peer保留，失败可重试、成功不重放。31项publication/init、29项Puppet Runtime及named Timeline/native+ASan门通过；最终隐藏准备三最近门32项通过，badOnly/reference与bind均比较实际顶点和coverage。首轮fixture形状/旧DTO漂移、命令参数命名和签名style失败均保留日志，非引擎结果。独审一次全范围及P2定点复核GO。

未参与修法原3351179520在同最终App/默认/零FFT运行8秒，Root实看人物、纸片、Wallpaper Engine文字与蓝背景合成保持，无VM failure；两包exit0、surface1→0、GPU drained。288目录无官方“截屏”图，不冒称官方同相位、所有动作/HDR/多屏/性能通过；本批只关闭跨层初始化子项，未改全样本verdict或样本分母。原包的其余拒绝仍按真实可见consumer选择，不以日志数认缺画面。

**证据与清理。** `.artifacts/scene-evidence/runs/cross-layer-animation-seek-20261028/`保必要前后图、原始日志、App/产品输入身份、测试/构建及独审摘要；普通14天、单包32MiB。临时样本/HOME/App及重试载体在提取后删除；连续后继只保一份任务构建缓存，路径见本批收尾。无新增官方VM实验，未改变官方客户端或真实媒体。

<a id="static-camera-transforms-20261028"></a>
## 2026-10-28 静态相机 DTO 与共享投影

**通用能力。** 原thisScene缺get/setCameraTransforms，288的普通265.visibility首次update即throw；现DTO与partial写入沿原SceneHost/C mirror→append-only owner journal→OwnerEffects→同DynamicLayerRuntime plan/dictionary→原snapshot/resolver→唯一CameraFrame。普通source与camera target分域，不伪造layerID；不新增CameraRuntime、clock、registry、缓存或产品文件。原fixed-point两处重复plan构造收为每轮一处；prepared四defs复用现index，native保descriptor seed、正交canonical，旧path zoom定义优先。本帧只overlay最终admitted camera字段，其他layer setter时序保原；失败撤整owner，正常peer保留。C命令仅首次setter按4→64有界分配，getter栈副本叠本callback有序partial，原snapshot pending/rollback与TimerSnapshot cursor复用。

**投影与边界。** 正交static view在canvas fit前应用，canonical跳额外矩阵；原CameraFrame统一供render、material view、粒子screen basis与cursor反投影，无逐层重求相机。default path隐藏仅屏蔽原origin/zoom，global eye/center/up独立消费（独审P2已修）；native消费口保zoom1，DTO/getter可保作者值，符合公开zoom仅2D边界。bootstrap getter沿既有initialized/pending阶段返回constructor seed，首次正常snapshot转运行base，无新stage flag或人为init setter许可。init写与prepare覆盖次序、hidden path/API zoom、完整跨owner官方次序仍未知，不由本片裁决。

**官方有界证据。** 固定2.8.0.42/wallpaper32 SHA `daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07`，Windows11/Parallels27.0.3。同一自有800×600板的eye/center共同+100X，五彩标记实际均−100px、Y不变；宽容RGB阈值扫描最大误差0.5px，独审原client ROI=(53,174,800,600)。init eye=(2,2,2)、首update=(0,0,0)与saved eye不同，R1在init保存base再恢复导致斜视，不作正常baseline；R2仅将测量base延至首update并增加readout。没有拍BASE/SAME，不宣称set(get)无跳变或完整初始化语义。原始输入/工具/身份、失败与小ROI图已归`.artifacts/scene-evidence/runs/static-camera-ortho-anchor-20261028/`。

**测试与真实App。** pure-C snapshot原子性通过；新真实VM bridge/事务含global、partial、Vec3副本、改名/等价、TimerSnapshot、overflow与数值反例；原default2D、particle frame、native frame与动态层门按受影响范围复用首轮有效结果及定点重验。首轮Cursor漏传0 tests编译失败、旧‘camera defs不存在/完整DTO等identity’断言、非法particle Y-model载体失败均保真：只同步实际fallback/producer合同与合法Y模型，没有删实际值、alias、peer、创建/退休/冲突反例。新增native/default/hidden path、zoom不改3D FOV/poll、两非对称marker及逆投影均通过，编译输入187/171无漂移。全范围独审及两处消费口定点复核GO。

签名Debug在8258a8e35加本批产品源，主App SHA `6091b2d938d1f5dccc3aabf02f416f50971b028d6dcc60ce6649e20307d32843`，产品输入无漂移。首build发现未更新LiveConsumers camera enum分支，已将三个仅script字段纳入原非property路径，最终Debug通过；未改文件的Swift6隔离诊断保原日志，不记warning清零。原288默认/零FFT/中心hover运行17秒，265回调completed，无VM failure，早段相机位移真实合成；Metal receipt的after实际为首帧后约3.66秒，series0004为约15.85秒，后者人物/腿/书/窗/水面完整归位。Root曾把after标签误作run末帧而怀疑持续灰边，又将官方后段图误作开场依据，已按时间戳撤回这两个推断；生产Single会取length末值，未据误读改Timeline/getter。

原288官方fresh复制包project SHA `eea311abbed2dc973ba7c6b00fd13479b543005b519622ea46095b2f1baa7a42`、pkg `c650ed538f6a787fce2bc9fb9d032a83d46b49487a28620422a69b61da279e7d`；1000×650两图约在CLI后30/70秒，Root只认与native末段的主要完整构图接近，不作首13秒或逐像素parity。两者无orthogonalprojection.auto区别，原轨迹首/末delta均0，不能因saved camera非零就额外补偿。普通layer getter读取Timeline值有现CPU合同但尚无官方配对资格，未借本片改它或新增已证缺陷。

独立3554161528默认13秒和3437487219默认8秒保人物/星空与地球/银河合成，无VM failure；343色调/光影余项仍在原队列。三包均exit0、surface1→0/GPU drained。原native两深度真实Debug App seed/rotated两臂及独立ROI全通过（30.765秒），并未改其oracle来适配本片；不冒称性能收益、完整HDR/多屏、全部交互或整288已修。camera API首错退出队列，其他问题保持原优先级。

**产物。** 必要原图、失败/成功日志、App/输入/测试身份与独审在`.artifacts/scene-evidence/runs/static-camera-transforms-20261028/`普通14天；不保App/用户包/临时HOME。官方预览已用定点CLI确认关闭，客户端与VM保留；Windows与本机测试副本提取后清理，连续开发只复用一份原任务build-cache。

<a id="geometry-named-content-20261029"></a>
## 2026-10-29 几何命名栅格的输出表示

**通用语义。** GeometryProduct将上游graph-final按真实mesh/coverage栅格化为PMA命名输出。原Coordinator误把其reservation content覆成上游straight表示，实际消费正确比较content时拒整帧。单源及有序多源现保几何reservation的PMA，普通graph-copy继续继承final content；复用已验证binding向量，不新增状态、owner或算法，epoch/slot/物理纹理、pin/rollback保持。产品一文件净减1行。

**回归与限制。** 真实Coordinator门经prepare→provider publication→consumer覆盖原PMA copy、straight copy、geometry straight→PMA、mixed两种顺序及content/texture/epoch/slot反例。同一最终夹具，冻结旧源失败、候选通过；删除夹具重复Aggregate算法，直接装配产品完整声明，四测试文件≤1000行、合计净减120行。原独立geometry像素probe的旧入口先后缺真实RenderState及DEBUG编译条件，未取得fresh结果，未改该入口或认像素门通过；这项验证债独立留队。

**实际画面。** 原295在基线持续dependency-input-mismatch、无Ready；修后layer1413的visible publication和134 binding成功、mismatch为0，Ready9648.709ms，完整主体与背景出画。独立322默认人物、背景文字、频谱和发光曲线保持，不关闭旧手部等反馈。两例各Ready后7秒、after请求3秒、固定PCM，均exit0/FAIL[]、normalization terminal-chain-complete、surface1→0/GPU drained。它们是本修复的两次画面验收，不重跑全量；未验官方同phase、全属性/长周期、普通桌面媒体、完整HDR或性能。

**身份与保存。** 普通Debug25.546秒、现优化DEBUG28.310秒构建通过，7个受测/配置源无漂移；后者App SHA256 `2a76ace1a2b5e47278bb699aa2991b50b5c9159d79cdeeaa6af781ef24d376dc`。独审复核产品、真实声明装配、两图与日志GO。必要原图/日志及来源明确的逐样本投影在`.artifacts/scene-evidence/runs/geometry-named-content-20261029/{2959875782,3226487183}/native/`；summary保存完整原report、源摘要、原失败和验证记录，均普通14天、每包≤32MiB。原全量归档的blocked属于修前身份，保留历史而不回写成功；只退出本次首帧断点，不授整样本官方PASS。

<a id="dead-varying-uniform-20261029"></a>
## 2026-10-29 无消费者顶点uniform的准备期投影

**通用语义。** 同一DeadBindingAnalyzer不再只由inactive sampler Resolution触发：fragment不读、且vertex全部引用都落在已有可删范围内的uniform，随纯dead-varying计算退出bounded/generic实际布局。复用main顶层分量写、单定义局部引用闭包和纯度证明；既有后端mul仅供删除证明接纳，同名作者函数/宏、副作用、采样、活读及控制流边界保留。generic用既有非执行语法入口取得事实，无关动态loop不妨碍投影，也不扩大bounded执行资格。无活跃inverse时terminalReplay自然不再求逆；活读inverse仍拒奇异矩阵，未补假逆矩阵或改变局部采集丢弃无关Z的语义。[合同](../architecture/shader-metadata-failure-contract.md#dead-varying-uniform-projection)

**验证。** 实际编译主门16通过、1条保留作者请求跳过；死inverse及改名/等价表达的两后端layout与控制输入相同，第二次请求产物/layout一致，活读与副作用反例保留，动态音频例仍由bounded报dynamicLoop。合并调用的第二类prepared-normalization在夹具编译时被停止，整次exit1，不能称全绿。实际Program两门PASS，覆盖flat raster无inverse与真正活读inverse拒绝；普通Debug29.323秒、优化DEBUG诊断构建31.140秒通过，独审对有界范围给GO。

**真实输出。** 原3175039950由Program218183166b6c的pass-uniforms-rejected、未Ready恢复至Ready4440.089ms；147#effect#674首帧与次帧均succeeded、GPU完成且compositor消费。Root实看人物、雪人、白方雪粒和地面可见。严格report仍FAIL，仅报utility capture失败及低于planned计数；未参与修法的3226487183严格PASS、Ready10320.286ms，其背景文字、谱条与发光线可见。两例均exit0、surface1→0、GPU drained；不作性能、完整HDR、全属性或官方parity结论。

**退出边界。** 317默认newproperty24=1选择人物+雪人，495为选项2的隐藏composition，子层479/488也隐藏；当前可见雪人属于423组，无实际可见consumer要求495输出。现隐藏组未分配source却记capture failed，8条静态planned只有5条succeeded，保[合同与验证债](../roadmap/scene-open-breakpoint-queue.md#contract-validation-debt)。修前归档被Program218挡在utility执行前，不能写成“修前已复现495 failed”。两方块雪粒393/1229当前已出生、非空并完成GPU，修前预热人口也已非零，撤去“人口0待修”的现状表述；音频rate发布不证明音频导致出生或对应像素变化，相关因果尚未资格，不新增已知缺陷，也不据可见白粒结清音频一致性。

**证据保存。** 必要原图、日志、来源身份与逐样本投影保存于`.artifacts/scene-evidence/runs/dead-varying-uniform-20261029/{3175039950,3226487183}/native/`，`summary/`保原report、构建/Program/编译门及独审收据，普通14天。原全量的blocked记录保留修前身份，本批仅退出列明首门。

<a id="layer-sort-topology-only-20261029"></a>
## 2026-10-29 排序仅由原拓扑journal发布

**通用语义。** sortLayer只向原C topology journal追加有序操作，经OwnerEffects carrier与接受owner集合投影到Swift候选；即时层序、提交及拒绝回放共用原journal。退掉冗余property dirty及空DTO，真实authored属性继续走owner-local DTO；未改lookup、动态层ownership、预算、返回值或新增owner。产品一文件净删6行，不按同目标去重。

**真实门。** 冻结旧C源配新门仅失败一条纯SORT零DTO断言；候选C两门9.359秒、Swift layer_order十五门29.15秒通过。实际VM→DTO→接受集回放覆盖纯SORT零DTO、真实alpha共存、C/Swift顺序一致和拒绝仅撤first保peer。sharedFirst写authored103的C.alpha，peer写102的B.alpha；前者是owner-local DTO，不声称撞到另一owner的共享record.dirty_owner_identity。原no-op、非法目标/索引、foreign dynamic、throw、创建/销毁及晚拒绝边界保持。

**原包日志。** 两例按jobs2、Ready后4秒运行，整次16.9秒，均日志PASS/exit0、surface1→0、GPU drained。3808922316的679/995/1763 visibility init均completed，无layer mutation buffer exceeded，admittedLayers=0；不同输入时刻的admittedOwners总量不作为本批增幅。未参与修法的3372715909保admittedDynamic=1，报告声明的运行门及GPU/drain通过，未验视频内容；不关闭其长期切换/AV驻留反馈，其他样本同callback mutation冲突及预算问题仍保现役。

**验证边界。** 普通Debug35.740秒、优化DEBUG诊断构建41.611秒通过；两profile均有3条预存actor隔离警告，C源无新警告，另项跟进。独审对有界范围给GO。本批log-only、PNG=0，只认真实VM与原包短窗日志，不认可见层序收益、性能、官方parity或长时间切换；273的passthrough透视仍需先补官方小正反臂及现役D1资格，未随sort修复开放。

**证据保存。** 原日志、输入/产品身份、基线反例、构建及最近门收据的归档保存在`.artifacts/scene-evidence/runs/layer-sort-topology-only-20261029/native/`及`metadata/`，普通14天；不刷新原全量verdict或其他样本的可见裁决。

<a id="preparation-isolation-20261029"></a>
## 2026-10-29 CPU准备值的隔离归属

SourceFacts在检查与launch准备队列同步建立，原类型却继承App默认MainActor；Client内不可变callback facts的Equatable也错误继承该隔离。现仅为这条实际调用链的CPU loader/builder、MDL解析结果及facts显式标注nonisolated，共10个产品文件、11处类型声明，产品行数不变。UI、Client会话存储、传输与发布仍归原MainActor；没有新增owner、线程跳转、锁、状态或普通帧工作。

保原Swift5、default-isolation=MainActor及InferIsolatedConformances，普通Debug37.916秒和优化DEBUG诊断89.073秒构建成功、两者无编译警告，冻结12个源文件无漂移。原3条预存警告退出后，前两轮暴露的CPU叶隔离警告逐项修正，失败日志保留；共享旧测试夹具缺camera DTO与newborn getter，改为提取产品原声明/原getter，不复制业务算法或降低断言。实际准备取消加alpha builder共14项通过，未受后继编辑影响的callback facts停启门复用原PASS；独立审查核对隔离与共享夹具。

本批只修编译期职责声明，不声称可见画面、性能、Swift6完整模式或TSan通过，也不重复执行GPU/官方对照。必要源码差分、身份、前后构建与测试日志及审查保存在本机`.artifacts/scene-evidence/runs/preparation-isolation-20261029/metadata/`，普通14天；连续迭代仍只保留原一份构建缓存。
