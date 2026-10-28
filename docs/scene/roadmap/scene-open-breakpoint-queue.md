<!-- document-role: active-plan -->

# Scene 当前断点修复队列

> 更新：2026-10-28。这里只保具体未闭问题；按**画面合成/正常播放 → 有证性能成本 → 属性接线 → 合同与验证债**选序，服从[兼容路线](scene-compatibility-roadmap.md)。已闭首门、正常/误报及旧批背景移入[退出记录](../history/open-breakpoint-reconciliation-2026-10-23.md)。部分修复按子现象退出，不销整样本账。

“运行首拒”不等于缺图；“待复验”不等于当前HEAD缺陷。默认隐藏、空媒体、作者入场/延迟、未ready、没有golden或未验更宽profile均不单独排实现。矩阵PASS/FAIL不代视觉裁决。样本原verdict及运行关联归[台账](../capabilities/scene-sample-acceptance-ledger.md)，分母归[声明统计](../capabilities/scene-corpus-capability-inventory.md)，现存证据身份归[运行记录](../capabilities/runtime-evidence-current.md#local-evidence-availability)。

<a id="user-required-20261028"></a>
2026-10-28用户集中必修反馈已并入以下原条目，先推进U40，再按可区分的合成/播放首错选序；观察仍待实证。两377双视频/Xray已按用户确认退出；“其余基本问题不大”不自动结清其他旧账。

<a id="static-capability-gaps"></a>
<a id="runtime-open"></a>
## 1. 有定位依据的开放能力

本页合并原静态审计的14类剩余问题，静态缺口不等于样本故障或可见恢复。下表区分已复现的拒绝和仍未资格的像素影响；无可见consumer时不为清日志优先实现。旧STOP仅在出现新的可区分证据后重入，不重复原失格载体或放宽门。

| 公共首断点 / 样本 | 未闭问题与最小下一门 |
|---|---|
| Program来源/命名绑定 · 3086016320 | 430仍拒execution-stage-conservation/named binding，属父426下封面转场，默认父alpha0；无可归因默认ROI。先取可见媒体正控及base/potential/selected依赖向量，再沿原多槽owner扩展；保隐藏forward259的作者顺序，不将其归因独立1521频谱。 |
| source材质/lookup · 3616476797 /3679907516 | 361113与36771/74/83仍有source-only render-state首拒；36771回调产黑、83初alpha0待thumbnail，74普通effect实际已消费。先资格受控媒体/source独占ROI，区分texture×g_Color4等价与非等价source；不泛化translucent/VERSION2、吞lookup错误或据缺祖父认缺API。 |
| forward copy-background · 2972071249 | 313引用后置隐藏composition234，dependency stage order拒绝仍在；隐式copyBackground使全局prepass不独立于作者顺序，白波形因果未定。先证consumer prefix与跨consumer身份，复用原graph发布；[原板正控STOP](../capabilities/runtime-evidence-current.md#forward-composition-prefix-20261019)不作语义结论。 |
| <a id="animation-auxiliary"></a>Puppet auxiliary · 3577990983 /3822822401 | [Reader](../../../MyWallpaperX/Core/SteamWorkshopScene/Format/SceneMdlPuppetAnimationReader.swift)仍限auxiliary header/scalar/后缀且modern AABB后标记为零；更广scalar/shape无pose消费者，[Selector](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Puppet/ScenePuppetAnimationSelection.swift)拒多个非中性alpha contributor。357尚有多个非中性alpha contributor或未消费scalar/shape的组合（1678/258非零scalar、1678 keyed shape）；单个非一alpha不在本缺口。382的244.visible metadata缺席早于VM，由clip235的MDLA6 AABB后dense scalar拒绝引起；骨3恒4700且有正权重顶点，depth/order/位移与混合语义均UNKNOWN。先取得字段消费者合同及可归因姿态；不补假metadata、跳record或猜骨深度。保[shape边界](../capabilities/advanced-object-coverage.md#op-puppet-blend-shapes)及正式`fan-animation-scalar-20261023`/`fan-scalar-observable-stop-20261023`失败。 |
| <a id="effect-source-admission"></a>effect输入/来源 · 357/363增量 | [需求准备](../../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialRuntimeCatalog.swift)将活动sampler未获用途proof记purposeUnproven；[Timeline编译](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Timeline/SceneTimelineTargetCompiler.swift)拒effect constant的parent/children Combined，[whole-stage准入](../../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialPreviousBlurredCompositeOwnerAdmission.swift)要求utility source无child/dependency。357320 slot1用途proof与233 Combined、3632522893的765子785/Blur772 whole-stage childless门仍拒；可归因ROI未证。357须证5个Aperture/2个Opacity根的逻辑control身份；363须证source完成、pin/extent。沿原prepared链，不挑首root、转红mask或删guard；[Combined资格](../capabilities/runtime-evidence-current.md#effect-combined-qualification-20261018)保持STOP。 |
| N08 · 3337494481 world/负subdivision RopeTrail | 十个visible复制层仍unavailable，原hidden不计缺图；空间/细分语义UNKNOWN。先取可区分正控，不猜abs/clamp、不重复旧白线矩阵；[缓存观察资格](../history/rope-trail-profile-qualification-2026-10-15.md#cache-observer-20261022)失败保留。 |
| <a id="puppet-physics"></a>U40 ·3187857248重复拖动/重力 | ge=true、r=false/t=true仍使translationPhysics=nil；释放冲量现明确unsupported后停用原owner，仍只首轮可拖。禁止取消能力标记或以noop续跑（已实测累计形变）。须取得有效gravity/世界方向/状态消费者资格后扩唯一Motion，同时核本地query寿命与重复释手；官方质量/friction精确值未闭。[边界与失败](../history/puppet-linear-impulse-2026-10-28.md) |

| SceneScript跨层动画控制 · 2887099508 | 395.visibility初始化首错：普通getLayer句柄缺getAnimationLayer，阻断309/front leg动作定位；其后blush22普通Timeline.setFrame尚未动态到达。沿原prepared动画/Timeline owner补通用跨层句柄与控制，不按名称分派。[边界](../history/script-initialization-barrier-2026-10-28.md) |
| SceneScript相机读写 · 2887099508 | 无init的265.visibility首次update缺getCameraTransforms，后续setCameraTransforms也缺；作者欲让eye/center随mkj的13秒origin轨迹运动。须沿唯一camera typed链补读写及可归因运动；不把当前静态画面当相机动画已执行。 |

<a id="qv-visual-repairs"></a>
<a id="qf-2026-10-07-用户点名四样本公共主链修复"></a>

已闭公共主链按[历史对账](../history/open-breakpoint-reconciliation-2026-10-23.md#closed-first-gates)查询；本页不重复关闭过程。

<a id="visual-pending"></a>
## 2. 用户具体差异：待当前身份复验

本节保未闭反馈，**不声明当前HEAD均有缺陷**。旧QV及U组原身份缺App/属性/声源/phase，先固定同状态和ROI；执行数不能关闭画面差异。未知不按图层名补算法，不能用不同viewport或音源追色/坐标。

| 样本 / 具体余项 | 下一关闭门与边界 |
|---|---|
| 3779107475 ·疑似骨骼动画 | 静态163/clip530见MDLA6 state1非bind且非常量，bone15有189正权重顶点；bounds后37×301 scalar仍无已证消费者（与382 auxiliary同族）。须实际active clip/同phase pose ROI资格，未跑新画面，不把静态拒绝直接当完整动画故障。 |
| 3022080536 ·静止水墨烟雾 | 静态已见fog/sprite child的bounds-only emitter被non-audio static profile排除，早于出生/混合；root/black rope在同点会退化。须原包静止→移动、零/非零声源核实际供需及ROI，再区分bounds-only默认语义与child emitter准入；未作新运行，不直接去guard记完成。 |
| 2919854127 /2927205881 /3175039950 · 音频可见性 | 蓝环未见、曲线右短段、白方雪粒人口0分别保待复验。先同源PCM与作者实际触发条件、出生/像素正控；不把非零总量当目标band、改阈值或共用“发光”修法。 |
| 3577990983 · 远距离提前hover放大 | 先同设置官方/原生及真实鼠标对照；作者约602场景单位半径只解释部分观察，不调全局倍率，也不与已正常的199固定视口认同根。[入口边界](../capabilities/runtime-evidence-current.md#physical-pointer-ingress-20261023) |
| 2887542690 · 音频ROI、黑遮挡/字体、片区布局 | 图框内音频缺可重复正证，pointer消融已STOP；先取得可区分输入/ROI，不把旧外悬蓝条消失当音频恢复。[资格](../history/composition-local-perspective-2026-10-16.md) |
| 2134765860 · 旧右黑块 | 默认日景/Night选项4未定位独立黑矩形；旧ROI、媒体和phase不齐。仅待同状态可区分复现，不列当前已证缺图，不据无归属mask实施。旧`213-black-region-night-qualification-20261016`收据按[可用性边界](../capabilities/runtime-evidence-current.md#local-evidence-availability)使用 |
| 3768903841 · 云形/烟花色彩细节 | 同phase对照source/Program和ROI；四束spot已执行不关闭横向深云片反馈，也不证明新光照根因。[边界](../history/runtime-evidence-index.md#e-spot-light) |
| 3226487183 · 手部 | 原1028手部未闭；实际origin/reference/effect链正常、MDL source Z全零。先定位同phase形变，不改坐标或由别的XYZ修复推受益。 |
| 3809618616 · 布局裁切/音频活动 | 先确认当前具体差异和状态，不重开已闭int compound/TEX照片入口。[最后整合](../history/committed-range-review-repairs-2026-10-07.md#整合验证) |
| 3791967416 · 局部图案/合成、眼部完整周期 | 对齐完整周期/ROI；单次闭眼无虹膜已证，不重修barcode/seek/bone alpha。[边界](../history/puppet-clipping-2026-10-08.md#跨样本app与最终冻结) |
| 3789316755 /3211615441 · 频谱形状/幅度/全柱活动 | 同声源App A/B及静音/噪声反例；不把已闭容量/PCM或峰值策略当官方形状。[证据](../capabilities/runtime-evidence-current.md#e-2026-09-28-audio-band-peaks) |
| 3211615441 · 图片切换/首焦点/按住、多步跟随位置 | 锁真实跨帧按住和连续轨迹，不以同帧down/up关闭完整交互。[事件边界](../capabilities/runtime-evidence-current.md#e-2026-09-28-effect-cursor-visibility) |
| 3788467391 · 漩涡方向/速度/形态、长预热 | 原300秒预热被预算截断，需可比相位/原轨迹；不旋转整背景补偿。[Rope边界](../capabilities/runtime-evidence-current.md#e-2026-09-28-rope-trail-texture) |
| 1315486372 · 光线宽软/中段渐隐、水波位置 | 先沿实际texture/aspect/sampler/instance/混合找ROI首错；非方Sprite同端尺寸比1只否定基本主轴猜测，strict官方锚点未资格，不重跑方形板或猜×2。[最新边界](../history/light-particle-qualification-2026-10-23.md#light-particle-qualification-20261023) |
| 3769761761 · 斜光偏弱/缺失 | 原35秒仍缺头发上方斜带；root/child归因板crop与LOW正控失败，B/official未跑。先取得完整注册且可辨贡献，不据无G判child失效，不调size/alpha或重复默认晚窗；`.01`属instanceoverride。[资格](../history/light-particle-qualification-2026-10-23.md#light-particle-qualification-20261023) |
| 3113287126 · 小提琴粒子方向/数量 | 五系统输出、Count3.02与挂点修复不关闭方向/密度；目录无官方截屏，需独立同phase发射/运动对照，不凭观感调参数。[执行边界](../capabilities/runtime-evidence-current.md#particle-fractional-count-20261022) |
| 3437487219 · 地球色调/右半阴影、闪烁与collision | 地球色调与右半阴影为用户当前必修反馈；MR/specular/pigment、Cloud coverage/宽夜侧仍未闭，中性Chroma仅JPEG响应。层90释边首错已退出，见[记录](../history/parallel-script-compatibility-2026-10-28.md#vec3-reflect)，不代整体collision；同状态复验，禁套generic4白名单/调gain。[材质边界](../history/model-view-tint-2026-10-28.md) |
| 3743305891 · 十字流星尺寸 | 父world/子local各有scale但无重复乘证据；先取得同phase可归属尺寸正控，不改作者flags/scale。 |
| 3768229922 · 完整开场/过渡 | 短窗PSYCHE GEAR标识已在，只保主体/完整过渡待复验；固定完整默认开场，不能从稳定帧缺标识反推故障。[边界](../capabilities/runtime-evidence-current.md#default-camera-single-20261019) |
| 3770444459 · 溅水滴黑 | 10-23原包20秒未圈出可归因黑水ROI；待锁source/合成，不猜改blend。旧water目录不可用，新身份见[后验](../history/composition-root-effect-local-source-2026-10-23.md)。 |
| 3351163962 · 新补报左上文字超环 | 需确切文本、属性/时刻/viewport；旧默认三文本同状态对照只闭旧范围，不能代验新补报或直接改anchor。[旧对照](../capabilities/runtime-evidence-current.md#u25-u35-current-qualification-20261018) |
| 3768724269 · 旧光束范围/根部、右上渐变 | 用户称近官方、当前未确认新gross缺陷，仅待新同状态ROI；不按观感调gain，不重开已闭sunrays热显隐。[边界](../capabilities/runtime-evidence-current.md#quad-visibility-live-20261020) |
| 3287715210 · 眼周过亮/渐变弱、横移细竖纹 | 两个余项分别复验。终端8位量化有证，不证明内部F16或条纹根因，不额外压暗/重复优先消融Bloom。[证据](../capabilities/runtime-evidence-current.md#e-2026-10-08-gradient-storage-isolation) |
| 3750813609 /3363252053 · 相机过强/纵向反转 | 用户三轮未接受且曾挂起，保低优先同输入体验复验；不以默认camera后继代验或补偿不同viewport。 |
| 3662790108 · 球体/曲率、点击交互 | 只保旧具体视觉/交互余项，同条件复验；首帧文字发布已闭，未消费Data不作引擎缺口，旧8.8FPS不作当前结论。[后验边界](../history/text-publication-first-frame-2026-10-23.md) |
| 3589454154 · Bloom、细线微颗粒、轮廓布局 | 用户调序暂缓；保持合法屏外投影，不用视锥剔除消影。[边界](../history/saturn-light-delivery-2026-10-07.md) |
| 3747492842 · 闪烁/光束位置/crop/文字构图 | 固定当前输入/phase找首个不同stage，不重开正交near-plane。 |
| N07 · 3248220186运动/密度/亮度 | 同phase/音源复验旧具体余项，不再排world Sprite不支持。[边界](../history/particle-world-depth-2026-10-11.md) |
| N03 · 3337494481遮挡/构图、solid亮度 | 侧clock/date跨面文字、扁盒/粉顶、亮度旧观察仍待同pointer/phase；effect CPU、229 fallback/黑背景尚无可行动归因。原默认text板正控失败，不能猜depth/整quad策略；官方rim倒字/title黑影不计缺陷。[资格](../capabilities/runtime-evidence-current.md#native-text-depth-qualification-20261023) |
| 2938612768 · 右下时钟裁切 | 同输入后期图均在、执行集合相同但根因未定；先复验布局/输出ROI，不改矩阵期待。[证据](../history/frame-texture-snapshot-convergence-2026-10-14.md) |
| 2775915974 · 顶部灰边 | 旧反馈缺当前身份，先判作者画布露底；方向/顶部事件修复不代验该边。 |
| 3712499998 · 重复文字/样式 | 若当前仍重复，定位实际String/图层组合，不再补已闭Vec构造API。 |
| 3477054430 · 显示不全、月亮过亮/球体/文字、低频与猫受光 | 按当前原输入/声源/phase逐ROI定位；已有雾/Bloom等有界后验不合并销账。[原边界](../history/shared-shader-type-compatibility-2026-10-09.md#u12-真实-pcm-与系统采集后继) |

<a id="user-three-samples-20261017"></a>
### 用户指定优先复验

已有明确首错批结束或收益递减后，先复验本项及用户新补报的380异常，再选旧候选；缺同身份结论先核目录官方实机参考，不从截图猜算法。

| 样本 | 具体余项 / 下一门 |
|---|---|
| 3351179520 · 文字环位置/尺度与旋转漂移 | 8原图跨53.496秒未见明显整圈平移/半径跳变，但未得同帧slot1/MVP/g_Time，精确贴合仍partial。仅有新可区分几何/官方ROI才再开，不重复长窗、不强制三组TRS同速同心或用glyph框补偿。[资格](../capabilities/runtime-evidence-current.md#ring-motion-qualification-20261018) |

<a id="qv-cccea6c-user-report"></a>
### U组未闭子现象

原观看身份cccea6c1a8a738fd97889fda53e8c9cb0603908d缺App二进制/属性/音源/时间；以下未注明新证据者均待当前复验。同一余项只保一处，U40、U22/提交率、U42分别归能力、性能、属性段。

| 编号 / 样本 | 未闭余项与下一门 |
|---|---|
| U01 · 3764725758 | 左斜光、眼睛飘动。830/1706实际执行但aspect不同、缺可归因光束ROI；先同状态及完整眼周期，不调gain/点位。[复验](../capabilities/runtime-evidence-current.md#open-visual-qualification-20261018) |
| U02 · 3549827466 /3581882134 | 354缺光ROI、358暖亮/冷暗来源仍UNKNOWN；先分来源/phase，不按族名调gain。[复验](../capabilities/runtime-evidence-current.md#u02-three-lighting-fresh-20261018) |
| U05 · 3723344874 | 人物后烟雾/涡动。末combine的Dye版本/R梯度+A权重未见绑定首错；需合格同帧空间分布/uniform/ROI，不用单质心、盲加时或gain。[内容边界](../capabilities/runtime-evidence-current.md#u05-fluid-content-20261018) |
| U10 · 3793998447 | 音频响应/具体属性差异待同输入；默认整环缺失未复现，不再排整环Program不支持。[资格](../capabilities/runtime-evidence-current.md#u10-active-ring-20261018) |
| U11 · 3792249095 | 外圈样式/内外位置差异；底图本含图案，音源phase未齐。先实际ROI，不改相机/半径/涡旋或重开已证Sprite基础尺度。[资格](../capabilities/runtime-evidence-current.md#u11-visible-ring-20261018) |
| U13 · 3042492564 | 原光束、右裁切/blur、布局和媒体交互仍保；additive及camera origin setter首门已退出，不将默认XY夹零写像素收益。 |
| U14 · 2932157836 | 原blur/精确spin及媒体仲裁仍保。不重修已闭timer取消身份。[边界](../capabilities/runtime-evidence-current.md#shared-timer-cancellation-20261018) |
| U15 · 3299228616 | hover水波弱，须真实pointer与可归因ROI，不抬gain；滚动背景矩形已退出。 |
| U17 · 3233141951 | 脸/龙/小人/刀的准确轨迹及双色音频待同状态。403请求513仍有Bool seed数值污染；仅改literal true虽能播放，黑形像素/收益UNKNOWN，后继须新producer/ROI而非重跑该单变量板。[边界](../capabilities/runtime-evidence-current.md#combined-timeline-playback-20261017) |
| U19 · 3807668787 | 958 A2C/pointer轨迹准入仍拒，可见收益未证，原型已撤；先唯一ROI/实际几何采样和有效连续时序。[STOP](../capabilities/runtime-evidence-current.md#particle-coverage-qualification-20261018) |
| U24 · 3420215721 | 中央环亮度；同状态复验，349/409默认hidden文字不算缺字。 |
| U28 · 2684431262 | 略发光/整体合成差异；先同状态ROI，不把原洋红色当占位、250²GIF当golden。[资格](../capabilities/runtime-evidence-current.md#u28-visual-qualification-20261018) |
| U29 · 3470948192 | 35秒后仍黑水滴/缺亮边拖尾；反射空间/能量UNKNOWN，官方OFF正控STOP。不重跑失格载体或调亮度/距离追图。[停止](../capabilities/runtime-evidence-current.md#model-reflection-prototype-20261018) |
| U30 · 3750813609 | 时钟颜色已复现但[资格STOP](../capabilities/runtime-evidence-current.md#clock-color-current-20261019)；雨弱待同phase，雷电仅不确定观察。先可区分输入，不实施Text白源/模糊或借别包profile归因。 |
| U31 · 3264246690 | 人物边缘AA、警戒带运动；先当前对照，头/左肘与口罩关闭不代验两项。 |
| U32 · 2131872317 | 蓝烟花完整上升轨迹/逐子出生空间UNKNOWN；当前有蓝短线→亮点，但无连续官方蓝周期正控。先新同状态参考，不重跑native短窗或调重力/速度/RNG。[资格](../capabilities/runtime-evidence-current.md#blue-firework-qualification-20261020) |
| U33 · 3769688830 | 玩偶左右循环却单向转；先分黄球UV Spin与父挂点往复，目标ROI/整段尚未资格，不凭Spin判作者设计。[边界](../capabilities/runtime-evidence-current.md#ring-motion-qualification-20261018) |
| U36 · 3780119725 | 新补报人物/地面/摩托中层鼠标不响应、发光过强；脸黑线/缺块、动画/闪烁旧项亦保留。先具体层ROI/轨迹/属性/光照，不以旧短轨迹基础响应外推全景gain/delay。[旧边界](../capabilities/runtime-evidence-current.md#visual-feedback-followup-20261018) |
| U37 · 3769364482 | 三Shake的Breathing及发光突现风格；先可归因复验，基本loop/opacity已退出。[边界](../capabilities/runtime-evidence-current.md#u37-scalar-loop-20261018) |
| U39 · 3219398263 /2932631210 | 前者方向疑反、两者背景漩涡；固定各ROI状态，不凭单帧共改符号。293人物恢复与静态密度不代验方向。[边界](../capabilities/runtime-evidence-current.md#additive-terminal-density-20261019) |

低优先待当前复验：3028090166光束、2419444134白点数量/密度、3113554287顿挫、2304304373雾气叠加；一般烟花/洋红/拖尾尚缺唯一sampleID，先补身份，不派生通用算法。

<a id="performance-open"></a>
## 3. 性能：当前可避免成本待归因

阈值/有效基线/STOP只归[性能卡](performance-convergence-card.md)，不重开已撤movement、帧载荷、MDL/cache/排序等旧campaign；源码复杂度/调用数和旧FPS不作收益或新缺陷。

| 反馈 / 样本 | 未闭问题 / 下一门 |
|---|---|
| CPU高温、GPU满载 | 用户报告近100°C与GPU常满，设备/配置/窗口成本未锁。联合整进程CPU/GPU及实际工作归因；局部收益不关闭整体反馈，温度/能耗未测不认领。 |
| N09 · 3476868923 /3507496797 /3662790108重型准备 | 旧冷69秒超时后153.425/93.820秒ready、366冷120秒无图；当前缓存约19.4秒不能作冷暖收益对照。prepare70.338含model43.313，不相加；先当前唯一大成本/可省工作，不延timeout或减内容冒充优化。 |
| U22 · 3805547608视频越播越卡 | 当前普通App长稳复验；65/100秒双视频无递减只排短窗，不关闭长期反馈。[运行](../history/named-timeline-interaction-2026-10-10.md) |
| 3372715909 · 视频背景卡帧/发布空档与动态实例 | 用户当前必修反馈；原作者官方也曾崩溃，不据此定根因。旧20秒观测仅定位availability：100非loop空档1.682秒、144次hasNew=false、428新帧全发布、copy/导入失败0，不等于解码/转换根因或收益。120动态实例/dormant未闭，须新可见供帧证据；只在首个长空档交叉查询Scene请求与output host映射时刻的hasNew，不二次acquire，不重复已撤包装或全样本矩阵。[原设计](../capabilities/material-video-assets.md#video-consumer-demand) |
| 3749463715观感低帧率 | 锁设备/App、属性/窗口及实际提交/呈现率，区别U40重复拖动，不从观感直接判性能回归。 |
| U24 · 3420215721提交率 | 旧未提交1879需当前分母/drop原因；60秒931帧已不freeze，不认当前预算不足。 |
| 轻重切换驻留上移 | 已缩到purgeable分配、持有owner未定；先有效分配来源/退出平台，不重复无caller整轮切换或写allocator泄漏。[资格](../history/scene-switch-residency-qualification-2026-10-15.md) |

<a id="properties-open"></a>
## 4. 属性编辑余项

能力/选序归[属性卡](properties-panel-card.md)及[输入覆盖](../capabilities/runtime-input-property-coverage.md)。

| 反馈 | 未闭问题 / 下一门 |
|---|---|
| U42 · 面板打开/编辑、长Combo、语言 | 打开/编辑总延迟、完整系统键盘chrome、长Combo完整显示/更多locale仍待实际资格；有限AX滚动/本地化不代全范围，旧“严重卡顿/中文都变英文”不无条件沿用。先单个可达控件/动作与成本，沿Intent→store→consumer取证，未审词汇不直接算错译。 |
| <a id="particle-color-target"></a>静态 · particle绝对color direct target | [TargetMapping](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/ScenePropertyBindingCompiler+TargetMapping.swift)对particle .color返回nil，[binding编译](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/ScenePropertyBindingProgram.swift)报unsupportedTarget，无direct typed instruction。先取得实际合法定义及绝对/归一化颜色单位，再复用同一instruction/出生consumer；不扩成全部粒子颜色或数值转换故障。 |

<a id="contract-validation-debt"></a>
## 5. 静态缺口、候选与验证债

静态项明确缺消费者或当前拒绝面，候选/旧测试债另注明；这些不与已复现可见故障混排。仅缺官方合同或当前身份时先资格；更宽profile未测归专题能力表，不自动转待实现。

| 项目 | 具体依据 / 最小下一门 |
|---|---|
| <a id="animation-direct-state"></a>静态 · direct MDL与dense state1更广动画 | [DirectModel playback](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Puppet/ScenePuppetPlaybackState+DirectModel.swift)对实际参与且权重>0的非中性bone alpha/auxiliary选typed bind fallback并拒非空attachment；[资源准备](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/ScenePreparedStaticModelResources.swift)只为单geometry/entry安装动画。dense state1的[Reader](../../../MyWallpaperX/Core/SteamWorkshopScene/Format/SceneMdlPuppetAnimationReader.swift)限reference全帧恒定，[Evaluator](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Puppet/ScenePuppetAnimationEvaluator.swift)限无独立reference matrices且bind差≤0.0001，含state1的多opaque contributor仍拒。先证合法channel/attachment坐标基、多part或非中性reference的姿态ROI，扩同一selector/evaluator/pose/stream；不把任意state1当state0。[动画合同](../capabilities/direct-model-skeletal-animation.md) |
| <a id="effect-render-state"></a>静态 · resolved effect非overwrite state | 最早[Template admission](../../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapabilityTemplateAdmission.swift)复用[RenderState谓词](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneMaterialRenderState.swift)仅准normal、depth test/write disabled、nocull、alpha unspecified/enabled，Finalizer/PassEncoder再核；只指resolved fullscreen effect，不泛指普通图片/模型。先证active pass精确state、blend factor、alpha convention/输出用途，再沿原Program做像素正反门。 |
| <a id="dynamic-resource-recipe"></a>静态 · 动态特殊资源/默认材质recipe | [createLayer](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSLayerSceneHost.c)按字段存在拒Puppet animations/puppetAnimationLayers/effects，composition另拒copybackground/config/parent/children/dependencies；[图片catalog](../../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/ScenePreparedImageMaterialCatalog.swift)仍限单link/pass/显式纹理、无user texture/value输入、受限combo/静态scalar。先锁实际constructor和prepared资源，沿kind/catalog/拓扑补消费者，不把特殊资源扁平化成普通image。 |
| <a id="static-model-material"></a>静态 · static model material state/Program | [Entry](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/ScenePreparedStaticModelResources.swift)保blending/投影depthWrite，[颜色draw](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+StaticModels.swift)仅用normal选opaque coverage；[Pipeline](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Metal/SceneStaticModelPipeline.swift)固定source-over/greaterEqual，未消费逐pass additive/raw depthTest/alphaWriting。[binding compiler](../../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneStaticModelMaterialBindingCompiler.swift)只证固定renderer接口，非pass0报material-pass-index，任意shader未执行/接口失败报shader-interface-unproven。先active pass/interface与非零背景ROI/state/coverage合同，复用geometry/material和唯一输出，保淡出/depth/PMA；文件/blob数不代缺图。[有界策略](batch2/2d-lighting-material-design.md#static-model-normal-coverage) |
| <a id="point-volume"></a>静态 · point volumetric consumer | [SpotLightPlan](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Lighting/SceneSpotLightPlan.swift)只收bounded spotLight/lspot，[Runtime](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Lighting/SceneSpotLightRuntime.swift)只将该plan交SpotLightPipeline，无point-volume路线。先真实visible consumer及输入/输出合同，ordinary point surface/model lighting不代验volume。 |
| <a id="periodic-emission-cap"></a>静态 · random-periodic每周期数量 | maxtoemitperperiod保为maximumEmissionCount；[periodic admission](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticlePeriodicEmission.swift)要求nil，否则schedule unsupported且不发射。先核实际consumer其他CP依赖，取得cap schedule/reset/随机/rollback合同，再沿原schedule/出生owner验fixed-dt/seed/数量；不只删cap guard。 |
| 普通unlit数值下溢 | 10-08旧GPU反例在alpha=.5、vertex=.25、R8 clip=128/255下RGB约2.5098被算0；未fresh复验/未证活跃真实consumer。先资格真实影响，再沿唯一颜色乘积owner保有限值，不全图压暗/加cap。[证据](../capabilities/runtime-evidence-current.md#e-2026-10-08-unlit-product) |
| text size更新时序 | VM catalog size与实际排版logical extent分离，公开仅只读像素分辨率；setter后时机/padding装饰未知。先行为资格，不把本静态候选当U25根因或新建重复排版owner。 |
| 3808922316 sort冗余dirty | sort已写topology journal，重复property DTO再与另一owner冲突并误报buffer；额外可见收益未证。若实施只退冗余标脏，保顺序/owner/rollback，不扩buffer或新排序owner。旧资格`380-layer-sort-qualification-20261019`不作当前可见收益 |
| Timeline event-only归属 | Vec2/Vec3或numeric String可能被classifier吞attachment但无VM control；无真实target资格、已STOP。须先证可达consumer/control owner，不能据静态形状扩API。[API边界](../capabilities/scenescript-api-coverage.md) |
| 3766415113普通captureFrame1×1 | 旧daemon已呈现而ScreenCaptureKit得1×1、Metal诊断完整；先当前窗口frame/时机，不把诊断替图称普通capture修复。[尝试](../history/shader-completed-cache-retention-2026-10-15.md#未完成边界与无效尝试) |
| <a id="particle-world-space"></a>world-space affine/CP force · 359777 Bird | [空间准备](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleWorldSpacePlan+Descriptor.swift)限无parent/attachment/child的origin writer/单Sprite等组合，[同帧plan](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleWorldSpacePlan.swift)限basis/Z不变；[world CP force](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleControlPointForce.swift)限正交无层级local system、bounded CP、零operator origin。Bird operator10非零origin仍拒，270可见鸟群/音频出生UNKNOWN。先证active Z/rotation/scale、层级或空间consumer及ROI，沿原空间/出生/绘制扩展；零origin缺省距离不重开，不另造坐标链。 |
| 3605722997 · 脚本49 notfunction | console.warn仅静态候选，目标55为MP4-backed image且控制API已有；callee/初始available未证。先堆栈/实际调用，不据标签补API或改类型。 |
| 粒子unsupported与位置映射 | mapsequencebetweencontrolpoints、其余CP约束、Mirror、nested/event、非均匀child变换、深duration/9999 delay及322的68→64 matrix child预算独立开放，后者像素/成本待资格；只在真实active consumer有资格时实施。Position Around默认Z有效映射有反证，但斜轴六候选全拒；须新可区分出生/空间证据，不拟合phase/重跑旧板，不关闭311/379方向与速度。[位置边界](../capabilities/particle-component-coverage.md#position-around-position-mapping) |
| <a id="particle-cp-distance"></a>3742497499 · CP距离/death child | [parseOperator](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleDefinitionParser+Operator.swift)无maintaindistancetocontrolpoint case，Simulator无typed位置约束消费者；135默认活跃/GPU有输出但此算子未接。death child在multiplysize/setopacity拒，setcolor已接，174隐藏不算consumer。距离及六板均STOP；先资格distance/variable-strength/轨迹，不能替为maintaindistancebetweencontrolpoints；另分Alpha初始化、事件输入、尺寸消费与真实splash ROI，不跳未知mode或用root计数替child。[资格](../history/particle-initializer-qualification-2026-10-23.md#event-inheritance) |
| 源码目录6项漏登记 | 3ce7adae2下Lighting输入、3个UserShortcuts、Puppet属性准备及shortcut dispatch仍不在filename合同；与本批已登记的两个prepared新源无关，只读核表同旧6项。按实际owner补登记，不移动/删合法代码消红；原收据在`native-text-bounds-20261022`正式包。 |
| 运行诊断显隐归一 | 381隐藏/特殊solid聚合load-incomplete、380隐藏分支异常降级仍待核；先消费既有active/retired事实，保raw，不把结构标签当缺图。[诊断合同](../development/corpus-diagnostic-workflow.md) |
| 历史GPU门/hidden extent覆盖 | 固定f79088a5输入的两条旧GPU红、hidden extent Python桩P2尚无fresh真实harness关闭链；先核生产可达分支与fixture，不称当前HEAD故障。[已闭graph债另归历史](../history/graph-color-purpose-reconciliation-2026-10-12.md) |

## 6. 进入与退出

- 先固定输入/属性/时间/音源/viewport/App身份，标明运行反例、用户待复验或静态候选；只选有用户价值的共享首错。
- 沿authored→prepared Program/graph/resources→typed frame→Metal→唯一compositor；保唯一owner和局部失败，不新增样本规则、普通帧解析/编译/整图哈希。
- 关闭需同语义正例、改名/等价输入与相邻反例、真实输出、独立健康样本及相称生命周期证据；按子现象移[历史](../history/open-breakpoint-reconciliation-2026-10-23.md)，不刷新整样本verdict或追认旧失格图。
- 旧证据不足保unknown，专题未测范围不另造当前bug；代表批更新，不为刷绿重跑全corpus。未经授权不提交/发布。
