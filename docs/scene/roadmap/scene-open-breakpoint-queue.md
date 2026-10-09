<!-- document-role: active-plan -->

# Scene 当前断点修复队列

> 复核：2026-10-08。本文是[兼容 P 路线](scene-compatibility-roadmap.md)的派生待修队列，保存所有已登记开放问题，不建立第二套阶段。当前优先 **纹理与最终合成 → 特效 → 频谱等直观显示**；启动阻塞需同时定位，性能优化不能牺牲画面正确性。

## 1. 全样本依据与状态

[全样本统计](../capabilities/scene-corpus-capability-inventory.md)已按243样本刷新，声明解析及守恒通过；[验收台账](../capabilities/scene-sample-acceptance-ledger.md)补齐同一成员全集。声明、旧运行与人工裁决分栏：旧归档为2026-09-17的混合App身份，旧失败可能已被后继修复，新增成员没有运行关联便保留not-run。当前批次查[运行证据](../capabilities/runtime-evidence-current.md)，不能把静态 family、加载比例、benchmark或少数截图算成全样本正确率。

本页的“已证缺陷”已有执行反例，“能力缺口”指可达合同缺失或未支持profile，“待研究”指行为/根因尚不明确，“待复验”指技术首断点已修但视觉或入口未验。后两类仍是待办；证据不足继续用可区分实验，不按样本补偿。没有修复事件的family不等于故障；静态missing纹理须核optional/default/VFS，粗分类model3d不得当真实3D数量。

### 当前三张工作卡

| 卡 | 目标与共享职责 | 最小交付与停止条件 |
|---|---|---|
| T1 材质与纹理合成 | 单pass静态源与中性材质常量乘色已接通；0–1 user Alpha已接同一compositor及热切；mixed user color公共入口已接，原366颜色热切及307背景颜色已通过共享显隐错配修复；同model多图层共享已接；继续核更宽Alpha域、非中性Power及perspective；按全243声明选共同首断点 | 优先扩现有neutral-tint与materialConstant消费者；先区分已有链路和真实缺口，避免新Program重复求值。每个新增profile均需真实输出、style叠加及健康反例；透明state研究仍只按已证边界准入 |
| T2 颜色与HDR输出 | 旧SDR shoulder压暗已修；对剩余条纹、HDR物理显示及用户样本复验，按采样purpose/alpha/颜色域→中间target→最终输出定位 | 保留作者HDR/SDR意图；同内容默认/关闭/开启和实际呈现对照。已有16F与热切执行不等于物理亮度正确；找到首错owner再修改 |
| E1 特效与频谱 | 将运行拒绝按共享shader/slot/graph/动态输入首断点归并；频谱用同声源对照形状和活跃度 | 复用现compiler/graph/audio producer，选覆盖面明确的族恢复动态结果；不抬gain、改作者参数或放宽测试制造通过 |

T1材质、T2 HDR裁剪/暂停、E1 prefix/标量及同层current已闭；328仅证F16量化，不据此换全图精度。T2透明RGB跨effect与静态源/source/capture两卡已闭合，U19灰头冠恢复亮色；U23坐标拒绝与背景强网点已修，U21数组/环形输出及灰斜层已修，下一复核剩余颜色/光束；[类型兼容后验](../history/shared-shader-type-compatibility-2026-10-09.md)保留实际运行及未决合同，不重做已修SDR shoulder或已执行效果；按批回写矩阵。

## 2. 纹理、合成与特效公共缺口

| 待办 | 状态、证据与下一关闭门 |
|---|---|
| 自定义源材质未准入组合 | **首入口已修，公共边界待补**：[833静态双纹理源](../history/source-material-entry-2026-10-08.md)已实际执行并消费后effect；3层中性静态乘色改由既有compositor消费，已跑通3原样本；原“7层动态常量”中1层已有S4，不再列为缺能力，其余6层中3609108600与3610154602的0–1 user Alpha已接原/clone消费者并完成实际运行；3665307769的mixed user color及内层开关接入既有Vec3 owner，原包彩虹已运行、受控热切通过；原包颜色热切的同key visible错配已按官方保Bool合同修复。同model多source已沿原入口接通，见[共享材质证据](../capabilities/runtime-evidence-current.md#e-2026-10-08-shared-source-material)；宽域Alpha、Power=.99仍待接线/运行。1层perspective、更多multi-pass/provider待证。细分见该记录的后继更正；不能把已修380照片归入同根因；自有literal-blue源在官方2.8.0.42为蓝，而当前native源准入`texture-purpose-unproven`后回退白色，见`/private/tmp/mwx-self-composite-contract-20261008/native/snapshot-rejected`；这是通用自定义源片段入口缺口，不能用后续effect同色通过掩盖，另沿源Program准入补齐。 |
| 显隐属性的其他非Bool/缺失类型引用 | **color范围已修，其他输入待复验**：243场景/project身份核同的直连layer.visible统计有color 2样本2处、slider 3样本4处、缺定义40处及有声明但无type的2处；合计27样本48处只是声明。color两原包3665307769/3078285611热切现已实际变色、不重建；完成记录归入[显隐错配修复](../history/source-material-entry-2026-10-08.md#后继修正颜色与显隐错配局部保留)。slider与缺定义不得沿用该合同或直接认定失败，按同key合法消费者、当前回退及官方可观察行为继续归因。 |
| 材质颜色的组合缺口 | **部分已修，组合余项待补**：静态中性RGB已进入原/动态图层；脚本tint占用layer color的覆盖已修，迁至materialConstant并退出clone颜色覆写；受控前后GPU及原379彩虹通过。named组合仍待官方合同与实际消费者证实，不直接给raw capture叠加材质调制。复核10候选样本/11层没有named边；193频谱12条named声明被作者previous绑定覆盖，不能计为漏Alpha。3690859128双source共用模型限制已修，证据见[共享材质](../capabilities/runtime-evidence-current.md#e-2026-10-08-shared-source-material)；首引用删除后的官方续跑未知，保留既有安全退休，不能外推所有材料实例范围 |
| 普通unlit数值边界 | **溢出已修、下溢待修**：4×1e38×1e-37的Inf沿现shader回算有限40，无全图压暗/cap。[有界证据](../capabilities/runtime-evidence-current.md#e-2026-10-08-unlit-product)。source alpha=.5、vertex=.25、R8clip=128/255的weighted组合仍输出0（数学RGB≈2.5098），属于既有fast-math下溢；此失败保留，不能由溢出正例关闭。优先真实多source颜色消费者，数值余项不扩大为所有HDR已修 |
| 默认变暗、HDR/SDR最终显示 | **旧压暗与特效自动裁剪已修，视觉余项待复验**：旧SDR shoulder把白点1压到0.75；[白点修复](../history/sdr-white-preservation-implementation-2026-10-06.md)实测RGB(191,64,128)恢复(255,64,128)。EDR及OFF→ON→OFF已有同surface headroom执行证据；暂停HDR热切与有界异步失败恢复已补[独立证据](../capabilities/runtime-evidence-current.md#e-2026-10-08-paused-display-recovery)；共享PMA输入/合成输出自动RGB裁剪另由[实际GPU反例与缓存升级](../capabilities/runtime-evidence-current.md#e-2026-10-08-hdr-color-boundary)修复，作者限幅保留；用户样本、多屏SDR及物理亮度仍未关闭。沿唯一颜色/output owner定位，见[热切证据](../history/hdr-live-toggle-verification-2026-10-07.md)；Bloom iterations0/1空间语义另作官方控制 |
| 显式UNorm的generic准入 | **自有输入边界，真实样本命中未证**：`sample→alpha×uniform→saturateRGBA`控制在generic ordinary路径被`compiler-artifact-colortransfer`拒绝，实际bounded Program的HDR/SDR/零alpha GPU正确。243包严格文本扫描未找到直接对应，不能外推语义不存在；原163 color Pulse、252 alpha Pulse已实际GPU执行，不能作为该缺口影响面。先核真实未准入引用，再扩原分析/准入；不注入fact或新增执行链。[输入与证据](../capabilities/runtime-evidence-current.md#e-2026-10-08-hdr-color-boundary) |
| shader compound边界 | **能力缺口**：已有int四则复合赋值恢复，qualified LHS、`%=`与vertex剩余见[原合同](../history/int-compound-assignment-normalizer-2026-10-07.md)。先核真实引用和类型，扩同一normalizer，保留scope/优先级/非法输入反例 |
| 透明RGB跨effect丢失 | **普通effect与静态源两卡已接通**：[执行记录](../history/authored-color-continuity-2026-10-09.md#静态源上传与采集后继)覆盖原straightAlbedo上传、Candidate映射、unlit采集、typed命名发布和唯一compositor。U19头冠灰边恢复亮色。动态PMA/命名几何隐藏RGB与source小输入官方准入仍未证；不能外推所有混合/HDR问题已修。 |
| varying局部重名误删全局声明 | **审查静态反例、待修**：`SceneGenericShaderSourceNormalizer.hasLocalDeclaration` 把同名局部/参数存在误当全局varying已死；不属于prefix宽度裁决。复用已有scope/global引用事实，验证main仍读全局、局部声明前读取、嵌套局部退出后读取、全局确实已死四种边界；不另建scope算法，不退回正则删除，不以新增prefix guard声称已修。 |
| 未定义varying分量 | **待研究**：sine_wave_circle激活变体读取未初始化分量。3747190633、3807151772及3809609151的sine_wave共享prefix/标量转换已在本批隔离App执行；后继self取错基础输入已按官方单pass链合同归一化到同一graph ingress，错误snapshot试验撤回；见[音频后验证据](../capabilities/runtime-evidence-current.md#e-2026-10-08-localized-graph-input)。不能猜零填充；先取得公开或受控官方可观察合同，再决定归一化/局部拒绝 |
| solid多stage普通混合分域 | **官方差异已证，产品余项**：[源尺寸后继](../history/shared-shader-type-compatibility-2026-10-09.md#solid源尺寸后继)显示mode0前段源栅格、末段投影栅格不同；本批仅开放single-stage terminal，高级混合仍消费原graph texture。多stage普通混合保留旧高分辨率路径；下一扩展须在现transaction内保证尾段inactive/失败不覆盖前段输入、prefix局部失败能被同一terminal receipt合法确认，不加第二输出owner。 |
| 透明target的alphaWeightedAdditive | **待研究**：普通源coverage已修，named/透明target的完整alpha合成尚未同输入裁决，见[coverage证据](../capabilities/runtime-evidence-current.md#e-2026-09-27-direct-draw-coverage)。先核唯一compositor当前blend，不能重新造光束专用补偿 |
| named纹理optional回退 | **编译ABI丢失已修**：generic accepted直接传递已校验PMA槽；3078285611原包192/effect2恢复材质执行、named189绑定、首帧/下一帧GPU与最终合成，benchmark PASS；自有半透明色与非法三候选反例通过。真实换曲/previous封面及完整视觉仍待验；不再把原`optional-named-fallback-unproven`当未修。[修复证据](../history/mixed-provider-color-abi-2026-10-08.md) |
| stock noise视觉等价 | **待研究**：按需准备/readiness已修；缺资产synthetic替代的密度/语义未证。375时钟包自带clouds，不属于替代收益；见[资源链证据](../capabilities/runtime-evidence-current.md#e-2026-09-26-stock-noise-preparation) |
| 更多条件/隐藏组与依赖 | **能力边界/待复验**：根层effect/Bloom条件、style热切及嵌套image/text成员已贯通；更多condition、跨层依赖、隐藏层级、group transform/alpha/clip等按[D1](batch2/composition-render-target-design.md)逐个真实profile闭合，保持固定准备闭包与唯一输出 |
| 同层secondary可见覆盖 | **待复验**：同层_a/_b路由已执行，不能继续列作统一拒绝；未激活及其他形态仍需producer→consumer→最终输出对照。旧v2“11PASS/2FAIL”不是当前缺陷全集 |

<a id="qv-visual-repairs"></a>
<a id="qf-2026-10-07-用户点名四样本公共主链修复"></a>

## 3. 用户报告的视觉余项（QV/QF）

同根因修复只出现一次；以下样本是回归输入，不是实现分派键。已修技术链不能代替整样本验收。最新一轮人工报告见[cccea6c 实机反馈](#qv-cccea6c-user-report)，与下列历史余项并存，不覆盖其证据身份。

| 样本/现象 | 当前剩余与下一门 |
|---|---|
| 3226487183 游离手臂、侧脸碎片 | **待归因**：composition成员闭包已修，Puppet姿态/挂点合成仍错。层1028 authored origin(-70,-606)，rootWorld(-154.9,414.9)，117顶点4个入视锥；934/876拆分件亦错位。沿origin→attachment/bone world→skinning核首错坐标，门为手臂画外、侧脸对齐且组级效果不回退。[闭包记录](../history/composition-member-closure-2026-10-07.md) |
| 833227004 流动效果缺失 | **首断点已修**：共享源Program恢复真实多帧flow与完整映射；受控后effect组合已消费同源。完整同时间官方parity仍未证，见[记录](../history/source-material-entry-2026-10-08.md) |
| 3809618616 全屏渐变、照片 | **原技术缺陷已修**：int compound恢复150柱，TEXB3/ImageIO方向恢复照片；剩余音频活动、完整交互与显示比例裁切复验。见[最终380运行](../history/committed-range-review-repairs-2026-10-07.md#整合验证)，不能继续写“照片归待修D” |
| 3791967416 合成/眼部/局部图案 | 裁剪有界片已完成：最终冻结eye105闭眼无虹膜；原包intro已退，barcode/audio数据槽/seek/bone alpha技术链已修。**完整眼部周期、局部图案与整体官方视觉仍开放**，见[最终身份与未验边界](../history/puppet-clipping-2026-10-08.md#跨样本app与最终冻结)；不重开已闭首断点 |
| 3789316755 /3211615441 频谱形状、幅度、全柱活跃度 | 动态容量、非有限单赋值、连续PCM/频带和峰值策略已修；同声源实际App A/B、静音/设备噪声与真实用户视觉仍待验。峰值策略不等于官方算法；见[频带证据](../capabilities/runtime-evidence-current.md#e-2026-09-28-audio-band-peaks) |
| 3211615441 点击、跟随与条件特效 | 事件接线、effect显隐、style布局与三点跟随已执行；剩余首焦点点击、按住期间外观、多步移动、位置及完整视觉。见[事件证据](../capabilities/runtime-evidence-current.md#e-2026-09-28-effect-cursor-visibility)；同帧down/up不算按住验收 |
| 3788467391 漩涡 | RopeTrail纹理跨度修正且用户确认转动更明显；原版方向/速度/形态、300秒预热被预算截断仍待验。见[纹理修复](../capabilities/runtime-evidence-current.md#e-2026-09-28-rope-trail-texture)，不得用整背景旋转替代 |
| 1315486372 顶部光线、中部渐隐 | 基础粒子旋转/载体修复保留；完整范围、根部和渐隐节奏未验。绝对sprite size须独立官方标尺，不从另一renderer或截图任意倍增 |
| 3769761761 缺左上向右下斜光 | 局部粒子变换、trail默认与alpha修复均未恢复官方目标；Shine/GodRays各pass已有输出，1/2/4倍size实验未恢复。保持**待归因**，官方同viewport/phase分离粒子与shader来源，见[诊断](../capabilities/runtime-evidence-current.md#e-2026-09-28-ray-source-diagnosis)；不改作者参数作“修复” |
| 3768724269 光束范围/根部/位置与脱层感 | additive、源coverage、方形载体和shader视差输入已修；用户仍指范围过大或根部深入。固定相机开关、作者depth和官方同状态核MVP/载体及连续输出；见[视差输入](../capabilities/runtime-evidence-current.md#e-2026-09-27-parallax-shader-input)；不强绑背景变形 |
| 3287715210 眼周过亮、淡入淡出弱 | 源coverage已修；原样本相位对照及用户视觉未验，不额外压暗。[证据](../capabilities/runtime-evidence-current.md#e-2026-09-27-direct-draw-coverage) |
| 3287715210 全屏横移细竖条纹 | 已定位gradient_color，终端16F超过256级已执行；10-08原包与gradient-only的phase4实际App均完成GPU/退出；shader为float、终端16F，共享HDR裁剪修复未证明是条纹根因。[自有恒定源实验](../capabilities/runtime-evidence-current.md#e-2026-10-08-gradient-storage-isolation)证明F16写出可形成平台，未证明本样本根因；官方隔离输入传输未成功。恢复同输入官方/物理屏对照后再裁决精度或呈现，区分纹理、输出精度与系统呈现，不重复优先消融Bloom。[证据](../capabilities/runtime-evidence-current.md#e-2026-09-27-scene-color-precision) |
| 3113287126 小提琴粒子锚定 | MDLV0017挂点恢复，粒子已从腿部回到琴/手；具体发散、密度、动画/视差和长稳仍待复验。[证据](../capabilities/runtime-evidence-current.md#e-2026-09-27-puppet-legacy-attachments) |
| 3750813609 时钟黑白 | 原包clouds资产ready，不能把synthetic noise记作修复；时钟ROI与作者预期仍待比对。[证据](../capabilities/runtime-evidence-current.md#e-2026-09-26-stock-noise-preparation) |
| 3792817546 /3790726145 /2986218263 指针/绳带 | CP0 flags/default、world/perspective、Rope及pointer三门已贯通；剩余原生输入和官方绳带宽度/UV/颜色，child profile另见下表。[执行证据](../capabilities/runtime-evidence-current.md#e-2026-09-28-rope-gate-admission) |
| 3750813609 /3363252053 相机过强、纵向反转 | 两项输入/收敛子缺陷已修但用户三轮验收仍失败，**用户曾要求挂起**。有官方同输入时重启layout/显示器/脚本相机输入对照；不拿约50px量级正确当体验通过 |
| 3662790108 JUNO /3589454154 土星 | JUNO默认albedo、完整两跳导航及原生进退已验，布局对照仍缺；[三体3509243656/土星旧启动失败已闭](../history/l1-heavy-retest-2026-10-07.md)，普通入口约14秒且三体用户确认；土星灯送达恢复，23模型材质接口及直接光能量/环影/颗粒仍未关闭。[最终土星](../history/committed-range-review-repairs-2026-10-07.md#整合验证)、[导航](../history/juno-full-scene-navigation-acceptance-2026-10-06.md) |
| 3747492842 额外闪烁 | 固定输入与phase连续输出，核首个不同stage，再定根因 |
| 3088601835 雪雾及旧低优先项 | 用户认为雪雾已较正常，官方也过曝；3028090166光束、2419444134白点、3113554287顿挫、2304304373雾气、烟花/洋红/一般拖尾保留低优先未验。公共修复涉及或用户重新点名时重启，不以沉默记PASS |

<a id="qv-cccea6c-user-report"></a>

### cccea6c 实机反馈（2026-10-08 接收，待当前版本复核）

来源：用户实测Debug `cccea6c`（`cccea6c1a8a738fd97889fda53e8c9cb0603908d`）；缺App二进制、属性、声源及时间身份。以下全部列入待修/待归因，**不是当前 HEAD 已复现缺陷或根因结论**。后继提交、既有技术修复和过去“修好过”均不能自动关闭本表。真实样本及其 `截屏*` 官方参考只读；参考变量不齐时仍可定位明显缺失，但不能宣称逐像素一致。

每行的①②等是独立子现象，关闭时逐项记录当前运行身份、首错职责、共因修复与跨样本实际收益；一项通过不关闭整行。相似现象先分组调查，根因证实后才合并修复项。排查列只是既有职责的入口，不是新算法、已确诊根因或按样本分派规则。旧表保存历史证据，以下保存这次新增观察，引用同一修复结果，不能各做一遍实现。

| 编号 / 样本 | 用户观察（全部待复核） | 先查的共享职责 / 关闭门 |
|---|---|---|
| U01 · 3764725758 | ①左侧向右下光束缺失；②人物眼睛错误地飘动 | 光束实际来源/激活/合成；眼部变形与挂点。两项分别定位，不先假定同因 |
| U02 · 3549827466、3585542943、3581882134、3603711180 | 四样本均缺光束特效 | 各取实际 particle/shader occurrence，比较准入、geometry、coverage 与最终合成；四样本分别复验 |
| U03 · 3587571382 | 纹理合成错误，额头缺块 | **主报告现象已修复**：[原包视差开启实机](../capabilities/runtime-evidence-current.md#e-2026-10-08-inherited-parallax)额头恢复。继承视差的position改消费与depth同源的当帧world frame，未改纹理/木偶/作者参数；完整交互及官方逐像素未验。 |
| U04 · 3747190633 | 音频条不出现 | **主报告现象已修复**：[中文previous补接](../capabilities/runtime-evidence-current.md#e-2026-10-08-localized-graph-input)后原包layer1897消费左右32频谱，条带可见并进入GPU/最终合成。受控PCM不代表外部声源验收；后继sine_wave已通过公共prefix/标量转换与self→graph输入修复，青色条带及内部波纹可见，错误灰矩形消失；[本批后验](../capabilities/runtime-evidence-current.md#e-2026-10-08-varying-scalar-conversion)保留最终身份与边界，不代表整样本parity。 |
| U05 · 3723344874 | 人物背后流体烟雾缺失 | 实际烟雾作者定义→资源/Program或粒子→层序/合成 |
| U06 · 3662390671 | 大面积纹理缺失 | layer185 Scene.tex为TEXB0004内嵌WebM/VP9；[本机探针](../capabilities/runtime-evidence-current.md#e-2026-10-08-frame-declaration)原WebM报AVFoundation -11828，同码流remux MP4报-11833且0frame。不能仅放宽magic或换容器准入；沿原decode职责选择能实际出帧的方案，系统/设备广泛支持未证。另有同源Frame Builder，尚无当前原包可见复验 |
| U07 · 3804441338 | 中间方框全白、文字不可见；官方应为两个描边镂空矩形 | **主报告现象已修复，整样本未宣称全通过。** [同身份实机后验](../capabilities/runtime-evidence-current.md#e-2026-10-08-frame-declaration)：共用 Projection 退役重复 regex、移除死 slot2；typed 默认背景 PMA 事实接入实际 generic ABI；导数 builtin 在原后端适配。198/218 两框镂空与时间/日期文字可见，245中心图形及272圆角遮罩编码，18个effect occurrence进入输出、无准备/执行失败。跨样本380620的同源三效果也进入链路。官方逐像素、真实音频/媒体和完整交互未验，不能据此报全样本正确率。 |
| U08 · 3802005866 | 音频条及背后蓝背景似乎越出作者限定矩形 | 作者边界→变换/clip/target extent；需先确认限定区域合同 |
| U09 · 3797217144 | 缺奥特曼旋转并由小放大的出场动画 | intro/Timeline/脚本启动、变换及首帧至入场结束时序 |
| U10 · 3793998447 | 似乎缺作者音频光圈和其他属性 | 音频消费、属性声明→入口→typed 更新；先清点具体未生效属性，不猜字段 |
| U11 · 3792249095 | 缺音频发光，整体样式与原版差距大 | 音频驱动→effect/颜色/合成，并保留整体构图复验 |
| U12 · 3477054430 | ①整体颜色差异大；②建筑窗户不亮 | 颜色域、mask、发光与最终输出；旧 mask/几何恢复不关闭这两项 |
| U13 · 3042492564 | ①顶部两道分叉光束差异大；②歌曲识别封面不显示 | 光束仍开放；[封面后验](../capabilities/runtime-evidence-current.md#e-2026-10-08-media-base-fallback)已闭合mask供给、idle连续scalar及换图事件帧旧值覆盖：同一typed admission消费restart preview，4次事件当帧均1并连续递减，无stale/拒绝。主动init/update/overlay与失败回滚不改，未新增clock/值链。**布局/AA/blur与真实播放器仍待修**：默认无resize窗口右侧裁切原因未定，不能关闭②或整样本。 |
| U14 · 2932157836 | 歌曲封面不显示 | [本批后验](../capabilities/runtime-evidence-current.md#e-2026-10-08-media-base-fallback)：**mask技术首断点已闭**：同Store复用preserved上传发布current/previous mask的typed data视图，原包受控红→绿→蓝出现中间像素、clear恢复作者音符图片，事件/GPU/退出正常。独立blur/spin拒绝及真实播放器来源仍待复验，不关闭整样本 |
| U15 · 3299228616 | ①鼠标划过水波不明显；②时钟上方矩形独立运动，似未与其他内容同层合成 | pointer→水波输入；graph/变换/相机及合成空间，不能用抬强度掩盖 |
| U16 · 3122339805 | ①两个可移动窗口消失（用户称曾修复）；②文字区域包括关闭按钮 X 轻微偏移 | 回归候选：脚本/动态对象生命周期与位置、文字布局；复验连续拖动与文字 ROI |
| U17 · 3233141951 | ①脸部不随头发做木偶动画；②背后龙头飞行轨迹不对；③黑色小人动画缺失；④官方音频条双色重叠，现仅粉色 | pose/attachment、轨迹/时序、动画激活、audio 层序/混合四项各自闭合 |
| U18 · 3232289987 | 头发合成位置错位 | **主报告现象已修复**：[MDLV0021版本合同补接](../capabilities/runtime-evidence-current.md#e-2026-10-08-puppet-v21)使躯干骨骼、动画与五官/右臂挂点进入原链，原包前发/五官回到头部。完整交互/官方逐像素未验；generic max重载仍走既有共享fallback，保留后续归因。 |
| U19 · 3807668787 | ①头冠应亮色发光却像灰色阴影；②音频条缺失 | **两项主报告现象已修，整样本未关闭**：②沿[原音频证据](../capabilities/runtime-evidence-current.md#e-2026-10-08-localized-graph-input)；①[静态源后继](../history/authored-color-continuity-2026-10-09.md#静态源上传与采集后继)保留BC3透明texel的作者RGB，原包GodRays五节点与终端均执行，灰外圈恢复亮色，频谱仍可见。未改gain、关闭effect或按样本补色。未验完整交互/外部音源/官方精确数值。 |
| U20 · 3807151772 | 音频条消失，用户称之前修好过 | **主报告现象已修复**：[同一中文previous修复](../capabilities/runtime-evidence-current.md#e-2026-10-08-localized-graph-input)后原包layer399的16频谱进入实际GPU/合成，条带可见。未验外部声源/完整交互；后继sine_wave已走同一公共编译与graph输入链，黄色频谱和条内波纹可见；[本批后验](../capabilities/runtime-evidence-current.md#e-2026-10-08-varying-scalar-conversion)保留最终身份与边界，不关闭整样本。 |
| U21 · 3806337293 | ①人物层上下叠灰层；②下半身过曝；③环形音频条缺失 | **三项已在原包受控PCM关闭**：[音频索引后继](../history/shared-shader-type-compatibility-2026-10-09.md#u21音频索引后继)恢复两环，灰斜层/额外过曝消失；21材质实际执行，完整交互/外部音源未验 |
| U22 · 3805547608 | ①右上角点击切换背景失效；②用户报告带视频层样本普遍越播越卡、帧率递减 | hit/event→属性→媒体切换；视频 decode/publication/资源释放/队列长稳。普遍影响面待测，不能由单样本外推 |
| U23 · 3796588443 | ①纹理混合明显错误；②音频条缺失 | **光效与强网点已修，整样本未关闭；②受控频谱已绘制**：[源尺寸后继](../history/shared-shader-type-compatibility-2026-10-09.md#solid源尺寸后继)接回原静态源/Candidate，原始entry副本背景恢复、普通光柱官方对照无回退。LOVE色阶与灰紫矩形属作者设计；完整交互/外部音源及全图逐像素仍未验，59节点执行不算正确率 |
| U24 · 3420215721 | 完全静止，用户称之前修好过 | 回归候选：clock/暂停状态→脚本/动画/粒子实际帧更新 |
| U25 · 3351163962 | 左上音频圆环内时间文字跑到环外 | text anchor/布局/parent transform，核圆环和文字的共同坐标 |
| U26 · 2849382252 | 三条白色图形分辨率明显过低 | 原资产/采样/target extent/几何，不先认定压缩或任意提高分辨率 |
| U27 · 3754630802 | 狮子头眨眼异常 | 实际动画/纹理序列/clip 与周期；需关键帧对照明确异常 |
| U28 · 2684431262 | 显示与官方明显不同，需核作者定义及实现偏差 | 先对照构图逐层定位首个错误，现象尚不足以指定算法 |
| U29 · 3470948192 | ①整体差异大；②主体水滴缺发光 | 与旧文字/NaN问题分开复核实际 source/effect/合成，不能仅首帧文字通过 |
| U30 · 3750813609 | ①闪电缺失；②时钟文字发光不符；③雨水不明显；用户提示参考项目 | 闪电关联既有 periodic 限额待研究项；文字与雨各自核输入/颜色/合成。参考仅 clean-room 行为合同，不读取复制私有实现 |
| U31 · 3264246690 | ①人物边缘锯齿（用户怀疑压缩）；②点击切换面部口罩缺失；③灰色警戒带运动不对 | 解码/采样/geometry、hit/事件/显隐、作者运动时序分别核验；旧 mesh/atlas恢复不关闭本行 |
| U32 · 2131872317 | ①爆炸烟花效果差且种类似乎不足；②爆炸散开时乱飘 | root/child 声明及准入、力/速度/空间/随机序列，固定 dt/seed 与官方有界轨迹对照 |
| U33 · 3769688830 | 右上圆形水球玩偶应左右循环转动，现持续单向转 | 作者 rotation/oscillation/Timeline 时间与方向，不专设摆动算法 |
| U34 · 3782740481 | 人物周身音频环缺失，用户称之前修好过 | 回归候选：同声源、作者条件、动态 geometry 与最终显示 |
| U35 · 2974757317 | 卡片下方多出似倒影的独立矩形音频条 | named/previous capture、层序、变换/clip，先确定作者是否本有该层 |
| U36 · 3780119725 | 官方整个场景随鼠标视差移动，现中间一层固定；需核官方镜头定义 | 相机/作者 depth/parent→各层 MVP 与 effect 输入，不能硬绑背景或全图后移 |
| U37 · 3769364482 | 人物发光突现，应渐显渐隐有呼吸感 | 作者 opacity/Timeline/effect 常量→typed frame→合成，复验完整周期 |
| U38 · 3750342273 | 缺鼠标晃动镜头视差 | pointer/相机配置→各层变换，沿既有相机 owner 修复 |
| U39 · 3219398263 | 中间漩涡方向似反，与官方有差异 | 作者时间/角度/UV/空间约定，固定相位对照后裁决方向 |
| U40 · 3749463715 | 胸部点击拖动仅第一次有效，第二次及后续失效 | pointer capture/up/cancel、状态复位及动画/physics 消费；至少连续三轮 down/move/up 验收 |
| U41 · 3357627941 | 属性面板无替换视频媒体资源的选择入口 | project 属性类型→现有 AppKit 编辑器/资源选择→typed binding→视频 consumer，不另造 provider |
| U42 · 跨样本属性面板 | ①打开后浏览/滚动严重卡顿；②疑似原中文属性显示成英文，用户询问官方是否有中英映射并提示参考研究 | 沿既有属性 UI 测主线程/布局/重复解析；查作者 locale token/字典、系统语言与官方 fallback。映射表是否存在未证，不硬编码翻译表 |

**执行顺序及单链约束。** U14封面mask、U13连续scalar/同帧旧值、U07镂空矩形、U03额头缺块及U18头发错位主报告现象已修，U04/U20/U19②音频条现已通过同一中文previous补接恢复；完成项不再当作未做。U19灰头冠、U21两环/灰层及U23强网点已修；下一定位HDR/SDR颜色、U12窗光等公共首错。U06 WebM/VP9 decode与重型剩余显示复验保留高优先级。随后复核 U16/U24/U34“曾好后坏”及 U22 持续退化，再归并光束、音频、动画/交互；属性入口与面板仍开放。条纹官方小输入已有有界证据，328物理显示未闭。顺序仍属于既有T1/T2/E1与P路线，不另建路线。

重写必须在原职责入口替换旧实现，并证明原有效输入/效果和失败隔离不回退；同一输入不可同时走新旧两套 owner。发现能由已有参数、入口或 primitive 表达的能力，优先补接或扩展该处。每批报告逐子现象关闭数、实际复测样本及剩余范围，不把本表录入率当画面修复率。

## 4. 其他共享能力与执行边界

| 共享责任/待办 | 证据边界与下一门 |
|---|---|
| 粒子子系统/控制点/时长的已知unsupported profile | **能力缺口**：getsuga childScaleOutsideBoundedProfile("1 1 2")、mapsequencebetweencontrolpoints、控制点约束、child变换及深层duration/9999 delay仍有独立缺口。 按真实producer/consumer逐族设计、验证child变换/状态；maxtoemitperperiod另列待研究，不混成倍率问题。 根加载、8/8 particle或Rope可见不证明这些子系统。 [依据1](../capabilities/runtime-evidence-current.md#e-2026-09-28-periodic-instance-overrides)、[依据2](../capabilities/runtime-evidence-current.md#e-2026-09-28-rope-gate-admission) |
| SceneScript尚未覆盖的类型/骨骼/文字内容边界 | **能力缺口**：angles/reset、文字布局、完整类型转换与String真实可见内容尚未闭合；重力、多骨spring/后继动画另有缺口。 先核实际作者调用与既有owner，再选择有证据的typed输出纵切。 这是现役队列的开放边界；冲量数值未知单独待研究，不用空API消除报错。  |
| Graph执行大门基线失败 | **验证债待归因**：本批同原harness在`cccea6c1`和修后均271检查、同30项false，新增失败0；mixed/system潜在依赖六项均true。本批增量另确认HEAD同样失败的sync_launch_generation旧入口截取、PBR startup夹具缺type；embedded_image_orientation裸runner的非包import失败，补PYTHONPATH后行为门通过。收据`/private/tmp/mwx-user-repairs-20261008`保留同输入对照；另两门在固定`f79088a5`源码复现同失败：`persistent_history_visual_failure_gpu`的initial passthrough、`preserved_channel_frame_local_unique`的8项false；对照收据`/private/tmp/mwx-scene-background-color-20261008/baseline-comparison-receipt.json`，根因仍待诊断。这些测试债不能伪称门全绿。逐项核对输入、旧期待与产品实际行为，不改断言消红，也不直接认定30个产品故障；[失败差集来源](../history/mixed-provider-color-abi-2026-10-08.md)。 |
| 共享shader引用分析的scope证明债 | **静态反例已证、实际样本影响未量化**：GlobalReferenceAnalyzer误把局部initializer内同名global及非block if后同名global当局部；现有loop相关遮蔽同需核。红证`/private/tmp/mwx-user-repairs-20261008/frame-declaration/reference-analysis-debt.json`。本批三个analyzer保持原样，新uniform冲突准入只用词法完全无token事实、不消费该证明。后续修原分析owner并核所有消费方，不能另建scope扫描器。 |
| hidden resolvedMaterial extent Python桩覆盖债 | **能力缺口**：已登记审查P2-1为隐藏provider extent分支的测试覆盖，生产跨层813与同层_a/_b已关闭。 检查最新真实harness是否已覆盖该分支；缺时补行为反例并同步退役旧待办。 未检查到fresh关闭链，只登记测试债，不宣称生产extent错误。  |
| 累计tombstone扫描Program绑定的非阻断成本 | **能力缺口**：作者退休历史登记剩余Program绑定扫描；同页后继仅关闭双demand memo抖动，未宣称消除此成本。 先取得同输入有效性能基线，再在同owner简化；不新增缓存/拓扑owner。 是成本后继，不是已测FPS/能耗退化。 [依据1](../capabilities/runtime-evidence-current.md)、[依据2](../history/authored-layer-retirement-2026-10-07.md) |
| cursor/Solid/previous-pointer的未证公开语义与Host组合 | **待研究/复验**：localPosition已恢复像素单位，但官方Y原点、text padding/puppet hitBox、缺省/隐藏Solid及父语义未定；按住中途关闭/重开、跨owner动态handle/stale及previous侧作者效果未验。 先自有官方/Host组合反例，再原生录屏；保留旧capture up而无hit不click。 不从绘制visible推导命中过滤，不因普通拖放用户通过关闭所有输入语义。 [依据1](../capabilities/runtime-evidence-current.md#e-2026-09-28-cursor-local-pixels)、[依据2](../capabilities/runtime-evidence-current.md#e-2026-09-28-dynamic-solid) |
| 雷电每周期数量上限与remainder | **待研究/复验**：405/412因maxtoemitperperiod=32先在periodic profile拒绝，不是instance count/rate倍率；公开Emitter和现有参考不能裁定限额执行。 受控官方确定每窗数量、fraction remainder、跨窗与count/rate组合，再在现emitter状态内实现。 原包加载8/8或根系统存在不等于雷电恢复。 [依据1](../capabilities/runtime-evidence-current.md#e-2026-09-28-periodic-instance-overrides) |
| bone physics impulse、gravity/spring与高级Puppet profile | **待研究/复验**：选骨/蒙皮后松手100ms到applyBonePhysicsImpulse可达；省略angular、physics-disabled、direction空间及数值仍unknown。IK、跨层geometry provider和完整3D另需专项。 只用公开/作者/官方受控观测补合同，净化交接给独立实现，沿原journal/motion推进。 不以no-op、位置跳变或空API伪造冲量；不消费私有实现表达。 [依据1](../capabilities/runtime-evidence-current.md#e-2026-09-28-bone-impulse-research) |
| clipping未知source alpha/nested软边及更多格式 | **待研究/复验**：当前只有opaque sources和单样本规则获受控证据；本地GPU nested交集不是官方nested parity，非一source coverage局部关闭。legacy suffix、更多版本未知。 真实引用优先；官方受控fractional source alpha/nested/软边区分，再扩已有IR/prepare/fragment链。 51样本reader非回退不能算51样本裁剪获益；不因源列表含self推定cycle。 [依据1](../history/puppet-clipping-2026-10-08.md) |
| Puppet mixing/ended/lookup等未开放控制语义 | **待研究/复验**：多clip非一alpha、非共轴多轨及额外opaque顺序没有完整官方合同；ended只已证loop单次越界，single/mirror/多圈及跨层lookup/create/destroy关闭。 先找到authored可达需求与可区分官方控制，再设计局部owner支持及typed unsupported。 自然single/mirror姿态可播放不等于ended callbacks已支持。 [依据1](../history/puppet-static-weight-2026-10-07.md)、[依据2](../history/puppet-bone-alpha-2026-10-07.md) |
| directional/point/spot及2D ambient精确光照合同 | **待研究/复验**：方向光地板+凸增响应、point剖面不一致、spot朝向/pitch、2D ambient/spot/directional、config point=false象限及k精确值未全定。 分类型/consumer的自有官方black-box矩阵，保留已落地门控/有界4灯/零点最大能量。 2D >4灯整包拒绝与零点哨兵已闭；两旧测试红由`e4443511`/`49672888`[明确偿清](../history/head-preexisting-red-clearance-2026-10-07.md)，不重新列为产品缺陷。 [依据1](../history/static-model-light-input-semantics-2026-10-06.md)、[依据2](../history/2d-lit-image-light-contract-2026-10-06.md) |
| 初始化/事件事务的真实多显示器及异步GPU组合 | **待研究/复验**：init/timer/storage/cursor typed撤回、single/multi-surface屏障、String init-only已有门；真多屏坐标/重建拖动、其他事件资源家族和异步GPU故障整合仍未验。shared heap明确非事务。 真实多显示器/重建中途拖动、具体资源事件/GPU故障注入，遵守现失败边界。 不重新引入每帧JS heap序列化伪回滚；shared非回滚不自动等于待实现通用回滚。 [依据1](../capabilities/runtime-evidence-current.md#e-2026-09-27-shared-identity)、[依据2](../capabilities/runtime-evidence-current.md#e-2026-09-28-cursor-surface-routing) |
| 脚本video effect/ended组合与多屏资源寿命 | **待研究/复验**：视频命令和真实样本protocol已过；effect graph、ended组合、多屏生命周期没有相同范围验收。 实际App的effect+seek/stop+ended与多surface恢复/释放反例。 不按视频原包3/3输出推所有脚本side effects通过。 [依据1](../capabilities/runtime-evidence-current.md#e-2026-09-28-video-real-samples) |
| 慢启动与cold preparation/跨帧复用性能 | **待研究/复验**：323在70.45s ready且首图后超duration+60被终止，因果未定；322历史新准入46材质冷shader分析15.5→48.3s，旧Q2跨帧复用需当前有效基线。 定位当前launch关键路径与同输入有效性能基线，保留超时/退出/后继输出；达到明确owner再简化。 不归因Puppet或reader、不抬timeout掩盖、不把重DEBUG FPS作性能通过。 [依据1](../history/puppet-clipping-2026-10-08.md)、[依据2](../history/composition-member-closure-2026-10-07.md) |
| Steam签名安装身份与真实授权三引擎门 | **待研究/复验**：队列保留用户安装候选后冻结identity并跑QR/授权下载/三引擎；2.0.9(277)仅是原条目历史候选，不在本次复核为最新发布。 用户实际安装身份与真实授权路径验证，按发布/账号合同执行。 未读真实账号或运行下载，不推测当前候选版本/兼容。  |
| 作者leaf删除之外的级联与destroy callback顺序 | **待研究/复验**：当前只已准备作者leaf；父子级联、完整IScene、destroy callback新增跨对象绘制副作用、官方精确先后和multi-surface联验未完成。 先找到authored可达需求并取得官方callback/topology合同，再沿现唯一journal/lifecycle扩展。 intro成功退出不支持任意对象树删除，不嵌套第二套事务。 [依据1](../capabilities/runtime-evidence-current.md)、[依据2](../history/authored-layer-retirement-2026-10-07.md) |

### 专项表补齐的公共待办

以下是尚未覆盖的具体合同范围；有界外不等于当前所有声明都失败。按真实可达引用和第一个错误consumer选切片，与上表同owner合并，不各造一套实现。

| 公共能力 | 剩余范围与最小关闭门 |
|---|---|
| 纹理解码/布局/用途 | LUT已能读取及3D上传，material/3D sampler消费仍缺；BC5 signed normal实际加载/GPU采样已[闭合](../history/d3-authored-normal-input-implementation-2026-10-02.md)，更广Effect/material组合及官方parity待验；straight-alpha resize、未证purpose/default/slot、动态atlas替换与rotated/trimmed/fractional/异尺寸帧、VFS case/symlink/重复/压缩/并发提取及digest边界。先选真实active slot，复用loader/registry/Program，以非方/半透明/LUT/normal GPU像素及generation/stale反例关闭。[资源合同](../capabilities/scene-format-and-render-graph.md)、[Provider范围](../capabilities/runtime-input-property-coverage.md) |
| 材质/Graph接口 | 任意source/vertex属性、custom mesh shader、helper/prelude/environment/annotation；更广command/condition/function/compose、format/UV、secondary/forward/cycle/child/non-image/multi-dependency与history resize/seek/device-loss/多surface。逐实际闭包验证prepared→publication→consumer→终端，健康兄弟保留，不以binding ready代替输出。[Graph专项](../capabilities/render-graph-shader-coverage.md) |
| 仍表列L0/L1的Effect族 | Cloud Motion、Swing、Radial Blur、Blend Gradient、Nitro、Reflection、Refraction、Skew、Edge Detection；先用243census确认实际active引用及当前首断点，再扩共享compiler/slot/graph。Blend Gradient需current/previous/第三输入与真实事件transition，不能复活专用wipe；Clouds/Fire已有执行，不列整族缺失。[Effect专项](../capabilities/effect-execution-coverage.md) |
| 已执行Effect的未证profile | Clouds/Fire/Pixelate，Blur/Precise/MotionBlur，Pulse/X-Ray，Water家族，Iris/DepthParallax/Foliage/Noise/Gradient/Hue，Tint/Blend/Opacity，FilmGrain/VHS/Chromatic/ColorKey，Glitter/Shimmer/Wave/Mask/Sharpen，Shine/GodRays/LightShafts/LocalContrast/Bloom及AdvancedFluid：尚有额外sampler/mask/provider、控制流/混合类型、非default combo、HDR/alpha、非全屏/复杂UV、多pass/target及Fluid非零LightingV1/module/command。按精确reason聚合，实际参数开关ROI与健康suffix验证；不将所有golden未验变成缺实现。[各族边界](../capabilities/effect-execution-coverage.md) |
| 文字字体与布局 | 字体替代golden、baseline/blockalign、更多maxRows/ellipsis/Unicode、outline/shadow负offset、动态extent/hitbox/多surface及效果链。已有文字VM、媒体文字、宽度/速度/留白不重做；沿CoreText与同代source atom，验证字形/advance/kerning和真实文字ROI。[文字专项](../capabilities/runtime-input-property-coverage.md) |
| 音频需求与consumer | 显式开启后仍须关联active demand的样本3754639143/3777761326/3788066613；更广effect/particle/脚本音频输入，capture scope替换、权限/hotplug/sleep/teardown/多surface。当前普通入口PCM→16/32/64 snapshot→exact GPU字节→全柱ROI；未激活声明不记失效，静音/噪声反例保留。[音频/API](../capabilities/scenescript-api-coverage.md)、[统计](../capabilities/scene-corpus-capability-inventory.md) |
| 属性、Timeline与动态类型 | texture variants、usershortcut/icon/绑定事件、scheme color、复杂条件/冲突/mixed targets、generic Combined、动画name/seek/metadata/rate/isPlaying、Animation Events、Vec4/matrix及更多pass/asset/model类型。Transform Vec2和first/change property事件已执行；新target须typed consumer、失败保旧值，events须大delta/loop/mirror/单handler失败隔离，最后真实热切/seek输出。[动态专项](../capabilities/runtime-input-property-coverage.md) |
| 动态文件、媒体及视频 | 更广asset/property slot替换、previous封面transition/multipass/variant，主流播放器（Apple Music、QQ音乐、汽水音乐等）、歌词、仲裁/来源退出、状态/进度；视频loop首帧、codec/device-loss及effect/ended/多屏。系统来源与Music补充已接通；逐真实来源换曲/缺字段/暂停/退出/禁用/迟到epoch和current/previous独立ROI验证，复用唯一需求驱动producer。[媒体设计](batch2/system-media-input-design.md)、[输入证据](../history/scene-system-media-input-implementation-2026-10-05.md) |
| 粒子算子与子系统 | 动态Layer Image发射/颜色/运动，CP速度/双CP放置/Remap Initial与跨空间约束，sphere/bounds/quad/model collision及slide/stop/delete，Boids separation/clamp/spatial，更广noise/Vortex/Remap/audio；child深层/angles/event offset/非均匀mirror/inheritance及direct color/vector/存量更新。先核真实producer/空间/事件合同，用固定dt/seed数量轨迹、顺序与预算反例；editor gizmo是播放no-op，不列缺口。[粒子专项](../capabilities/particle-component-coverage.md) |
| 粒子材质与renderer | custom shader、Cutout、Lighting/HDR/blend，世界/透视/复杂parent，Sprite绝对size/atlas，multiple renderer，Rope join/animated/root-world及RopeTrail subdivision/UV/死亡尾迹/pause/seek。既有Trail仿射宽轴/Screen/Fixed门不重做；联合准入＋真实GPU几何/alpha/UV反例，绝对size先官方标尺。[材质/renderer](../capabilities/particle-component-coverage.md) |
| Puppet与3D扩展 | 更多MDL/MDLA/MDAT/point attachment，Texture Channels/morph/blend rules/perspective/extrusion；模型mesh/node/layout/skeleton/animation/attachment/rootmotion/physics/custom stock shader，PBR/normal/specular/environment/shadow/volume/tube、height/live fog、动态3D camera选择/path。优先实际作者可达输入，沿原pose/GeometryProduct/material owner扩展，安全格式门与GPU/官方ROI分验；已有Puppet裁剪和静态3D不重写。[高级专项](../capabilities/advanced-object-coverage.md) |
| API、平台与资源策略 | 复杂previous/multi-button输入、模块图、完整Vec2/3/4与Mat3/4、asset handles、级联destroy；真实异步GPU/provider恢复、per-display FPS/quality/global VRAM/复用/长稳。先同输入基线及多屏/sleep/hotplug/重建拖动/故障门，不把shared heap非事务改造成逐帧序列化。[API](../capabilities/scenescript-api-coverage.md)、[高级专项](../capabilities/advanced-object-coverage.md) |
| 低优先产品能力 | RGB设备输出与离线固定clock/seed/replay/encoder尚未有产品闭环；保留待办，先emulator/author-off及共享clock逐帧等价，不能抢纹理/效果/频谱主序，也不因243无对应已证失败而宣称支持。[产品能力](../capabilities/advanced-object-coverage.md) |

### 归档事件全量对账入口

旧运行归档的firstBreakpoint与全部secondaryEvents按stage/owner/reason合并为以下10类（源：[运行归档](../../../script/scene_sample_debug_archive.json)）。这张表保留次级断点，**不是当前失败表**；已知后继按备注退出重修，尚无当前证据的关联项属于复跑/归因待办。

| 共享事件与归档样本 | 当前处置 |
|---|---|
| `EffectStageAdmission / admitted-fallback`：2959875782 | 295的provider与同层引用已修；复核仍激活的passthrough原因，不能据旧fallback重开整链。 |
| `EffectStageAdmission / unified-capability-unavailable`：3264246690, 3554161528, 3788897599 | 按scroll/clouds等实际激活shader variant查询现Program route；Clouds已有后继执行，不把旧拒绝复刻成新专用效果。 |
| `GraphExecutor / layer-source-not-ready`：3585875739, 3743305891, 3747492842, 3775355045, 3775373546, 3780940857 | 区分启动暂未ready且后续恢复与持续失败；video已有后继恢复，需completion/publication/next-frame共同裁决。 |
| `GraphTargets / named-target-capture-failed`：3775355045, 3775373546 | 两视频样本有后继完整运行；核同身份capture恢复，不能只用旧失败日志或首帧成功关闭所有组合。 |
| `BaseImageTextureStore / base-image-texture-load-incomplete`：3264246690, 3629927359, 3784012236 | 326旧mesh/atlas首断点已修；362/378的实际texture demand、purpose、decode与最终source重新定位，不能把loaded计数当具体原因。 |
| `ParticleRuntime / particle-layer-load-incomplete`：2974757317, 2986218263, 3396722575, 3665307769, 3690859128, 3712499998, 3779904456, 3780119725, 3788467391 | 298 Rope已贯通；其余按当前root/child准入具体原因复验，保留366子profile，不以九条旧计数断言九个当前失败。 |
| `SceneScriptVM / scene-script-bad-return`：3122339805, 3470948192 | 核text content当前值类型/producer与实际文字输出；此前其他target的维度修复不替代本项复验。 |
| `SceneScriptVM / scene-script-exception-range-error`：3789316755 | 378动态层容量与局部非有限赋值已修；保留频谱外观复验，不重造容量owner。 |
| `SceneScriptVM / scene-script-exception-reference-error`：3779026256 | 实际复验visibility脚本/module输入并核最早缺失API或值，禁止自动吞异常。 |
| `SceneScriptVM / scene-script-exception-type-error`：3078285611, 3448845950, 3470948192, 3601964477, 3610154602, 3612199597, 3612795410, 3665307769, 3747492842, 3788066613 | 3078285611当前layer60/effect6、22、24的speed脚本报`TypeError: toPrimitive`；3665307769三处异常已由原包和隔离App确认是作者断引用：374访问不存在祖父，386引用不存在的background/outline；实际399进度条lookup正常，不补造句柄，不再归作引擎lookup缺口，整体媒体面板视觉仍待验（见[归因记录](../history/source-material-entry-2026-10-08.md#后继归因原包遗留断引用)）；3610154602于本次Alpha最终链路复验仍见layer435 `getTextureAnimation`接收null，保留为独立脚本缺口（不是Alpha未接通）；按effectConstant/text/layer等target及准确异常定位host API/返回类型；复用同一VM owner，不按统一TypeError泛化修法。 |

### 原人工裁决逐项保留

以下19条来自[人工裁决原记录](../../../script/scene_sample_acceptance_verdicts.json)（2026-09-06/08），本次不改verdict。旧技术原因与当前视觉余项分开；旧FPS、unknown和历史fail不代表当前运行。相同能力合并到上方共享卡，不能因为人工记录尚未更新而重新实现已修链。

| 样本 | 旧观察的当前处置 |
|---|---|
| 1315486372 | 水波位置也保留复验，与上表光线一起按实际stage定位。 |
| 2775915974 | 方向/顶部事件已修；顶部灰边及全构图仍待复验，不重新修输入符号。 |
| 3238423642 | 头部修复保留；整体视觉与性能重新取当前身份基线，旧FPS不作现值。 |
| 3264246690 | 左肘mesh/atlas已恢复，完整构图未人工关闭。 |
| 3287715210 | 音频已有后继共享tap链；原图音频与上表条纹/眼光共同复验。 |
| 3437487219 | 未取得该样本collision后继关闭证据，先复跑定位owner；日期/时间不重修。 |
| 3448845950 | 脚本效果、完整布局仍复验；不要按旧黑屏重开资源owner。 |
| 3470948192 | NaN、文字碎片、异常背景均保留当前运行定位，不能只验首帧文字。 |
| 3477054430 | mask及多段几何已有有界恢复；球体/月亮、嵌套脚本minvalue输入及文字布局需当前复验。 |
| 3509243656 | 旧启动失败已关闭；开场模拟、坐标文字仍属整景视觉验收。 |
| 3662790108 | JUNO完整导航已有后继证据；球体/曲率/布局和性能边界按上表核，不把8.8FPS当现值。 |
| 3712499998 | WEVector及Vec3(Vec2)技术断点已闭，环形频谱可见；重复文字与完整样式未裁决。 |
| 3747492842 | 闪烁之外保留光束位置、viewport裁切和文字构图复验。 |
| 3750813609 | 时钟与雨丝亮度保留；不能因山寺构图通过关闭文字ROI。 |
| 3765760121 | 倒置修复保留，整样本视觉待验。 |
| 3766387484 | 日期/星期/时钟恢复保留，其余effect实际输出与ROI待验。 |
| 3780119725 | 脸部黑线/缺块、动画profile、光照及闪烁均待当前身份复验；压缩修复不等于动画全通。 |
| 3787382101 | Water Waves mask已由六组同构强度A/B关闭技术债，见[mask证据](../capabilities/runtime-evidence-current.md#e-2026-09-13-water-waves-mask-ab)；只保留整样本视觉验收，不再实施同一mask修复。 |
| 3788734811 | 倒置修复保留，整体视觉等价待验。 |

## 5. 全量关联、验收与退出

- **待办：运行关联更新。** 当前243是作者声明全集；45成员full matrix与fixed13只作历史回归。复用现census→debug archive→acceptance ledger工具，以最新同身份报告关联所有事件（不只第一断点），将共因聚合到上述owner；新增样本没有当前报告保留not-run，陈旧报告保留日期和代码身份。先修最有价值的共享缺口，随批更新代表覆盖，不能全量刷绿掩盖漂移。
- **待办：缺少oracle/人工身份。** 旧19个人工fail与对应观看者/截图身份缺项保持原状，不按本次统计或技术修复覆盖。只在实际复核后更新人工verdict。目录`截屏*`仅为用户确认的官方实机参考；未同步viewport、属性、时间、声源者不作逐像素parity。
- **待办：全专项未覆盖profile。** 上表是旧断点对账与用户报告；专项能力中未执行、未证和局部拒绝须按上述专项范围查询并纳入共同修复，不默认已兼容。每次扩大profile前核真实引用/现owner/可区分反例，不按family数量制造任务量。
- **闭合纪律。** 同族正例、健康异族/失败反例、真实动态输出、相称build/运行与独立审查通过后提交；标明实际画面收益与受益面，下一批和当前专项进度。没有可复验分母就报告闭合链及剩余项，不编完整正确率。复用现有prepared/typed/encode/唯一compositor，普通帧不新增解析/编译/整图哈希。
- **已完成退出待修。** composition成员、int compound、TEXB3照片、Puppet reader/权重/alpha/seek/intro、barcode/data purpose、Rope准入、音频容量与事件/事务等的已闭首断点只留上述历史链接；旧Q0“v2两失败”、380“照片待修”、379“条码/暗幕未修”、298“world/Rope仍被拒”均已退役。其他未验合同保留各自行，不将整样本标为完成。
- 工程性能与Steam安装授权门仍分别归[工程路线](engine-refactor-program.md)和[Steam路线](scene-steamkit-migration-plan.md)，不能把旧签名版本当当前待安装指令。纯性能项排在画面/启动正确性之后；先同输入有效基线，再简化既有owner，不以降低作者分辨率换通过。
