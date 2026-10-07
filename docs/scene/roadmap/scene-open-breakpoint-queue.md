<!-- document-role: active-plan -->

# Scene 当前断点修复队列

> 复核：2026-10-08。本文是[兼容 P 路线](scene-compatibility-roadmap.md)的派生待修队列，保存所有已登记开放问题，不建立第二套阶段。当前优先 **纹理与最终合成 → 特效 → 频谱等直观显示**；启动阻塞需同时定位，性能优化不能牺牲画面正确性。

## 1. 全样本依据与状态

[全样本统计](../capabilities/scene-corpus-capability-inventory.md)已按243样本刷新，声明解析及守恒通过；[验收台账](../capabilities/scene-sample-acceptance-ledger.md)补齐同一成员全集。声明、旧运行与人工裁决分栏：旧归档为2026-09-17的混合App身份，旧失败可能已被后继修复，新增成员没有运行关联便保留not-run。当前批次查[运行证据](../capabilities/runtime-evidence-current.md)，不能把静态 family、加载比例、benchmark或少数截图算成全样本正确率。

本页的“已证缺陷”已有执行反例，“能力缺口”指可达合同缺失或未支持profile，“待研究”指行为/根因尚不明确，“待复验”指技术首断点已修但视觉或入口未验。后两类仍是待办；证据不足继续用可区分实验，不按样本补偿。没有修复事件的family不等于故障；静态missing纹理须核optional/default/VFS，粗分类model3d不得当真实3D数量。

### 当前三张工作卡

| 卡 | 目标与共享职责 | 最小交付与停止条件 |
|---|---|---|
| T1 材质与纹理合成 | 单pass静态源与中性材质常量乘色已接通；0–1 user Alpha已接同一compositor及热切；mixed user color公共入口已接，原366颜色热切及307背景颜色已通过共享显隐错配修复；继续核更宽Alpha域、非中性Power、多同model图层及perspective；按全243声明选共同首断点 | 优先扩现有neutral-tint与materialConstant消费者；先区分已有链路和真实缺口，避免新Program重复求值。每个新增profile均需真实输出、style叠加及健康反例；透明state研究仍只按已证边界准入 |
| T2 颜色与HDR输出 | 旧SDR shoulder压暗已修；对剩余条纹、HDR物理显示及用户样本复验，按采样purpose/alpha/颜色域→中间target→最终输出定位 | 保留作者HDR/SDR意图；同内容默认/关闭/开启和实际呈现对照。已有16F与热切执行不等于物理亮度正确；找到首错owner再修改 |
| E1 特效与频谱 | 将运行拒绝按共享shader/slot/graph/动态输入首断点归并；频谱用同声源对照形状和活跃度 | 复用现compiler/graph/audio producer，选覆盖面明确的族恢复动态结果；不抬gain、改作者参数或放宽测试制造通过 |

当前以T1为首个代码切片；T2保留高优先用户视觉验收，不能重做已修SDR shoulder。每批闭合后重新比较三者，不等243样本全部重跑才开始修复。完整矩阵扩容与证据关联随共同修复推进。

## 2. 纹理、合成与特效公共缺口

| 待办 | 状态、证据与下一关闭门 |
|---|---|
| 自定义源材质未准入组合 | **首入口已修，公共边界待补**：[833静态双纹理源](../history/source-material-entry-2026-10-08.md)已实际执行并消费后effect；3层中性静态乘色改由既有compositor消费，已跑通3原样本；原“7层动态常量”中1层已有S4，不再列为缺能力，其余6层中3609108600与3610154602的0–1 user Alpha已接原/clone消费者并完成实际运行；3665307769的mixed user color及内层开关接入既有Vec3 owner，原包彩虹已运行、受控热切通过；原包颜色热切的同key visible错配已按官方保Bool合同修复。宽域Alpha、Power=.99或多source消费者仍待接线/运行。1层perspective、更多multi-pass/provider待证。细分见该记录的后继更正；不能把已修380照片归入同根因 |
| 显隐属性的其他非Bool/缺失类型引用 | **color范围已修，其他输入待复验**：243场景/project身份核同的直连layer.visible统计有color 2样本2处、slider 3样本4处、缺定义40处及有声明但无type的2处；合计27样本48处只是声明。color两原包3665307769/3078285611热切现已实际变色、不重建；完成记录归入[显隐错配修复](../history/source-material-entry-2026-10-08.md#后继修正颜色与显隐错配局部保留)。slider与缺定义不得沿用该合同或直接认定失败，按同key合法消费者、当前回退及官方可观察行为继续归因。 |
| 材质颜色的组合缺口 | **部分已修，组合余项待补**：静态中性RGB已进入原/动态图层；脚本tint占用layer color的覆盖已修，迁至materialConstant并退出clone颜色覆写；受控前后GPU及原379彩虹通过。named组合仍待官方合同与实际消费者证实，不直接给raw capture叠加材质调制。复核10候选样本/11层没有named边；193频谱12条named声明被作者previous绑定覆盖，不能计为漏Alpha。优先处理3690859128双source共用模型的已知准入限制；不得外推静态/脚本乘色结果 |
| 普通unlit数值边界 | **溢出已修、下溢待修**：4×1e38×1e-37的Inf沿现shader回算有限40，无全图压暗/cap。[有界证据](../capabilities/runtime-evidence-current.md#e-2026-10-08-unlit-product)。source alpha=.5、vertex=.25、R8clip=128/255的weighted组合仍输出0（数学RGB≈2.5098），属于既有fast-math下溢；此失败保留，不能由溢出正例关闭。优先真实多source颜色消费者，数值余项不扩大为所有HDR已修 |
| 默认变暗、HDR/SDR最终显示 | **旧压暗首断点已修，视觉余项待复验**：旧SDR shoulder把白点1压到0.75；[白点修复](../history/sdr-white-preservation-implementation-2026-10-06.md)实测RGB(191,64,128)恢复(255,64,128)。EDR及OFF→ON→OFF已有同surface headroom执行证据；用户样本、多屏SDR、暂停重绘及物理亮度未据此关闭。沿唯一颜色/output owner定位，见[热切证据](../history/hdr-live-toggle-verification-2026-10-07.md)；Bloom iterations0/1空间语义另作官方控制 |
| shader compound边界 | **能力缺口**：已有int四则复合赋值恢复，qualified LHS、`%=`与vertex剩余见[原合同](../history/int-compound-assignment-normalizer-2026-10-07.md)。先核真实引用和类型，扩同一normalizer，保留scope/优先级/非法输入反例 |
| 未定义varying分量 | **待研究**：sine_wave_circle激活变体读取未初始化分量。不能猜零填充；先取得公开或受控官方可观察合同，再决定归一化/局部拒绝 |
| 透明target的alphaWeightedAdditive | **待研究**：普通源coverage已修，named/透明target的完整alpha合成尚未同输入裁决，见[coverage证据](../capabilities/runtime-evidence-current.md#e-2026-09-27-direct-draw-coverage)。先核唯一compositor当前blend，不能重新造光束专用补偿 |
| named纹理optional回退 | **编译ABI丢失已修**：generic accepted直接传递已校验PMA槽；3078285611原包192/effect2恢复材质执行、named189绑定、首帧/下一帧GPU与最终合成，benchmark PASS；自有半透明色与非法三候选反例通过。真实换曲/previous封面及完整视觉仍待验；不再把原`optional-named-fallback-unproven`当未修。[修复证据](../history/mixed-provider-color-abi-2026-10-08.md) |
| stock noise视觉等价 | **待研究**：按需准备/readiness已修；缺资产synthetic替代的密度/语义未证。375时钟包自带clouds，不属于替代收益；见[资源链证据](../capabilities/runtime-evidence-current.md#e-2026-09-26-stock-noise-preparation) |
| 更多条件/隐藏组与依赖 | **能力边界/待复验**：根层effect/Bloom条件、style热切及嵌套image/text成员已贯通；更多condition、跨层依赖、隐藏层级、group transform/alpha/clip等按[D1](batch2/composition-render-target-design.md)逐个真实profile闭合，保持固定准备闭包与唯一输出 |
| 同层secondary可见覆盖 | **待复验**：同层_a/_b路由已执行，不能继续列作统一拒绝；未激活及其他形态仍需producer→consumer→最终输出对照。旧v2“11PASS/2FAIL”不是当前缺陷全集 |

<a id="qv-visual-repairs"></a>
<a id="qf-2026-10-07-用户点名四样本公共主链修复"></a>

## 3. 用户报告的视觉余项（QV/QF）

同根因修复只出现一次；以下样本是回归输入，不是实现分派键。已修技术链不能代替整样本验收。

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
| 3287715210 全屏横移细竖条纹 | 已定位gradient_color，终端16F超过256级已执行；恢复作者速度后物理屏/官方对照仍缺。区分纹理、输出精度与系统呈现，不重复优先消融Bloom。[证据](../capabilities/runtime-evidence-current.md#e-2026-09-27-scene-color-precision) |
| 3113287126 小提琴粒子锚定 | MDLV0017挂点恢复，粒子已从腿部回到琴/手；具体发散、密度、动画/视差和长稳仍待复验。[证据](../capabilities/runtime-evidence-current.md#e-2026-09-27-puppet-legacy-attachments) |
| 3750813609 时钟黑白 | 原包clouds资产ready，不能把synthetic noise记作修复；时钟ROI与作者预期仍待比对。[证据](../capabilities/runtime-evidence-current.md#e-2026-09-26-stock-noise-preparation) |
| 3792817546 /3790726145 /2986218263 指针/绳带 | CP0 flags/default、world/perspective、Rope及pointer三门已贯通；剩余原生输入和官方绳带宽度/UV/颜色，child profile另见下表。[执行证据](../capabilities/runtime-evidence-current.md#e-2026-09-28-rope-gate-admission) |
| 3750813609 /3363252053 相机过强、纵向反转 | 两项输入/收敛子缺陷已修但用户三轮验收仍失败，**用户曾要求挂起**。有官方同输入时重启layout/显示器/脚本相机输入对照；不拿约50px量级正确当体验通过 |
| 3662790108 JUNO /3589454154 土星 | JUNO默认albedo、完整两跳导航及原生进退已验，布局对照仍缺；[三体3509243656/土星旧启动失败已闭](../history/l1-heavy-retest-2026-10-07.md)，普通入口约14秒且三体用户确认；土星灯送达恢复，23模型材质接口及直接光能量/环影/颗粒仍未关闭。[最终土星](../history/committed-range-review-repairs-2026-10-07.md#整合验证)、[导航](../history/juno-full-scene-navigation-acceptance-2026-10-06.md) |
| 3747492842 额外闪烁 | 固定输入与phase连续输出，核首个不同stage，再定根因 |
| 3088601835 雪雾及旧低优先项 | 用户认为雪雾已较正常，官方也过曝；3028090166光束、2419444134白点、3113554287顿挫、2304304373雾气、烟花/洋红/一般拖尾保留低优先未验。公共修复涉及或用户重新点名时重启，不以沉默记PASS |

## 4. 其他共享能力与执行边界

| 共享责任/待办 | 证据边界与下一门 |
|---|---|
| 粒子子系统/控制点/时长的已知unsupported profile | **能力缺口**：getsuga childScaleOutsideBoundedProfile("1 1 2")、mapsequencebetweencontrolpoints、控制点约束、child变换及深层duration/9999 delay仍有独立缺口。 按真实producer/consumer逐族设计、验证child变换/状态；maxtoemitperperiod另列待研究，不混成倍率问题。 根加载、8/8 particle或Rope可见不证明这些子系统。 [依据1](../capabilities/runtime-evidence-current.md#e-2026-09-28-periodic-instance-overrides)、[依据2](../capabilities/runtime-evidence-current.md#e-2026-09-28-rope-gate-admission) |
| SceneScript尚未覆盖的类型/骨骼/文字内容边界 | **能力缺口**：angles/reset、文字布局、完整类型转换与String真实可见内容尚未闭合；重力、多骨spring/后继动画另有缺口。 先核实际作者调用与既有owner，再选择有证据的typed输出纵切。 这是现役队列的开放边界；冲量数值未知单独待研究，不用空API消除报错。  |
| Graph执行大门基线失败 | **验证债待归因**：本批同原harness在`cccea6c1`和修后均271检查、同30项false，新增失败0；mixed/system潜在依赖六项均true。逐项核对输入、旧期待与产品实际行为，不改断言消红，也不直接认定30个产品故障；[失败差集来源](../history/mixed-provider-color-abi-2026-10-08.md)。 |
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
