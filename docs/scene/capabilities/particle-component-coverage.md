# Particle 当前组件与执行边界

<!-- document-role: current-state -->

<a id="simulation"></a>
## 准备、模拟与空间

DefinitionParser 保作者顺序、已有字段解析与未知组件诊断；原组件 owner 准备 emitter/initializer/operator、control point、child 和 renderer 计划。每屏 PlaybackState 拥有模拟器、RNG、活动实例和轨迹历史，Session cadence 推进一次；View/GPU 重试不重新出生、执行事件或模拟。

root local/world、layer/world/camera、attachment 与 child space 分别保身份。共享 canonical world/camera 供 emission 和 draw 使用；固定线性基的祖先 origin 平移沿同一 reference/current 链接入 root、child 和生产 model。Pointer/CP 先在当前局部空间取值，实际出生与位置操作各转换一次，不能把 reference 指针再次当新生位置加偏移；职责见[祖先平移合同](../architecture/runtime-architecture.md#particle-world-translation)。不逐粒子重解层级或用 abs/clamp 猜坐标。

执行按准备好的作者顺序处理发射、初始化、操作、运动/死亡和 child，再产实例值与 draw batch。prewarm 执行真实模拟，不只移动 clock。snapshot/restore 属于原 CPU state，不复制 GPU 上传状态。

源码：[Runtime](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRuntime.swift)、[PlaybackState](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticlePlaybackState.swift)。

<a id="prewarm-work"></a>
### 预热准备与工作边界

初始 launch 在原 Host preparation queue 的资源/Program join 后，为冻结目标构造独占 PlaybackState/Runtime 与 material runtime，再随 PreparedLaunch 移交。增量新增屏复用同一显式 worker，取 job-start committed typed 值、拓扑与 audio，完整执行作者 starttime。已有销毁时沿原拓扑投影脱离已销毁父层，再解析预热及首批绘制共用的世界矩阵。audio 在 root/static-child warmup 前接入。Session 共用单屏安装与 GPU pipeline，不共享 mutable Simulator、不冷构造或恢复种子。采用时当前意图/revision、无历史 emit、零步首帧及取消/同 loader 接力归[显示协调](../architecture/runtime-architecture.md#display-reconciliation)；VM、Clock 与最终输出不迁移。

LayerImage 继续使用原 compiler：原 base-image owner 将 provider 缺 outcome 时的既有 inline 重试前移，保存最终 loaded/failed outcome，Surface 与 compiler 采用同一 texture/animation。正常已加载输入不重复读取，最终失败不增加第三次重试；deferred、视频及动态 source 继续原 provider 边界。

预热沿原固定步进、RNG、出生/死亡和 SnapshotRecorder，预热期不再记录 birth/death 事件（原每步排空成空操作；显式发射候选预算按实际 capacity 起算），保部分末步和后续 live 随机序列；作者 starttime 以模拟秒推进；实时入口只把固定墙钟步长乘一次实例 rate，预热直接提交原模拟 slice。同一 step 消费已投影的时间，保粒龄、出生、积分和历史同域，不暂换实例字段或另建时钟。所有 root 沿 worker 完整准备，退役3,600步、四百万加权关卡及专属工作计数；static/frame-created child 仍保240步及截断诊断。入口无效时长、容量与资源边界不变。

存量基线、Movement、AlphaFade 和 Turbulence 各一次同步借用原粒子数组，保算子及逐粒顺序、半衰积分、Vortex 半径和局部失败。AlphaFade 复用当步归一寿命，保淡入后淡出两次乘法的原次序及边界。Turbulence 的空间场、时钟及随机采样见[持续力合同](#continuous-turbulence)。指针不逃逸。见[基线](runtime-evidence-current.md#particle-baseline-borrow)与[Movement](runtime-evidence-current.md#particle-movement-borrow)。同一 Simulator 按原序收集死亡事件并清振荡缓存。粒子存储的连续 live 区间是死亡前缀之后的后缀：队首死亡只前移区间起点（O(1)），累计前缀达到 64 时做一次摊销压缩；遇到首个非队首死亡仍按原 read/write 压紧已读存活段。reset、operator、事件与快照只观察连续 live 区间；renderer 和 child 的 live-range 交接直接共享 ArraySlice，保留视图时由原 Array COW 隔离后续写入；Sprite 当前回调仅在合并 transient births 时物化并排序样本。Rope/RopeTrail 的既有几何准备保持，顺序、payload 与 rollback 不变。死亡扫描仅为 live 事件或振荡缓存复制死亡 payload；预热不生成事件，见[死亡移除证据](runtime-evidence-current.md#particle-death-compaction)、[前缀存储证据](runtime-evidence-current.md#particle-lead-death-buffer)与[预热证据](runtime-evidence-current.md#particle-prewarm-hotpath)。reset 仅写实际算子改变的 alpha/size/color，其余属性自出生保持初值。步进内 GPU 有限性接受与拒绝边界不变，仅把逐 lane 转换合为一次 `SIMD3<Float>` 转换。两者都不改算子次序、固定步进、RNG、出生/死亡、快照与 live handoff；实测与限制见[预热热路径](runtime-evidence-current.md#particle-prewarm-hotpath)。

Remap 和 Position Offset 保现有八角三维梯度噪声，格点求和及插值顺序有原生位值和首屏计时验收。`prewarmStepBudget` 只截断本次模拟，Snapshot 无续热游标。默认隐藏 root 在零步初始 advance 清人口和轨迹，保 RNG、ID、模拟时间及已完成 emitter，未完成者沿原 rearm。

<a id="natural-birth-lifetime"></a>
### 普通发射的首步粒龄

在模拟步内出生的粒子立即参与作者算子，包括首步位移。其外观曲线仍从粒龄 0 读值，此后按原实际子步累计并在作者寿命处退休。官版短寿命板的前后连续状态及两档 rate 见[出生到消失对照](runtime-evidence-current.md#ember-birth-lifetime-376)。位移积分与年龄起点同归原 Simulator。

原步内发射前已有的粒子身份分界用于同一 reset 循环，只推进进入该步时已存在的粒子。冷预热与实时使用同一步骤，显式发射在步前已经入列，继续随现存粒子推进。正常绘制消费算子后的活粒子；同一回调内出生又死亡时，临时绘制仍取算子前的出生样本。低帧率下一次绘制可能已跨过多个模拟子步。

<a id="continuous-turbulence"></a>
### 持续 Turbulence

冷准备解析场尺度、时钟频率、三轴掩码、相位跨度、速度端点和生命混合。Scene 相机的正交分支缺省 scale .01、timescale 20、mask (1,1,0)、speed 500…1000；其他投影缺省 .5、1、(1,1,1)、1…5。作者显式值保留有符号。相位两端缺省 0，运行只消费跨度。粒子用同一个稳定单位样本选择相位跨度和速度区间，随机单位从现有身份推导，每步至多取一次且不消费出生序列。

场坐标为 `(粒子当前位置 + Scene 秒 × (作者时钟尺度 × 实例 rate) + 相位跨度 × 单位样本) × 空间尺度`。在粒子既有空间按三个循环轴序 (x,y,z)、(z,x,y)、(y,z,x) 求三维 simplex 有符号标量，只取非零掩码的分量。使用公开 Perlin 置换及四个角的紧支撑权重，最高角梯度寻址保官版经验证的第三轴索引。零尺度得到零力。以掩码、实例 speed、稳定采样速度、生命混合和模拟步长累加存量速度。音频沿已有频带峰值与曲线作用于采样速度。低于 40 Hz，沿真实 Scene 帧间隔以 `(0.025 / 帧秒)^0.7` 衰减持续力，同一 Surface 帧只算一次。首场预热使用全强度，事件产生的子实例预热读同帧因子，粒龄仍走原步进。继承相机、时钟和音频的现有准备路径；不建第二时钟、缓存或逐粒子状态。

以 Scene 帧间隔独立计量后比较同龄粒子轨迹，覆盖零空间、负尺度、非零时钟、相同相位跨度、两档实例 rate、三轴掩码和顺序反例。用原包和使用同一算子的独立原包核对终端合成。移动的成熟光带覆盖仍需独立的同龄链路证据。[官版作者参数](https://docs.wallpaperengine.io/en/scene/particles/component/operator.html#turbulence) · [同龄轨迹与原包复验](runtime-evidence-current.md#particle-continuous-turbulence-field)

<a id="initializer-execution"></a>
初始化分派继续由原 `SceneParticleInitializerExecutionPlan` 冷准备，按作者顺序为每个 initializer 保留一个带对应 payload 的 enum case。出生只枚举这一个执行序列，退出每次复制完整 raw initializer、再索引九组 optional 聚合计划的双链。Scalar/Vector/Color 的必备 payload 由 case 直接持有，退役不可能缺失的热 guard；原 Definition 仍拥有作者事实、冷准入和诊断名称，不另存 kind 镜像、计划表或缓存。CP 需求收集和显式发射工作量同样消费原有序计划；原预算值和失败半径保持。

<a id="turbulent-velocity-speed-range"></a>
<a id="turbulent-birth-clock"></a>
出生 `turbulentvelocityrandom` 沿当前 Scene 帧时钟采样一维 simplex 梯度噪声。相位端点独立缺省为 0/.1，音频响应作用于相位跨度。采样输入为 `(Scene 秒 + 相位) × (作者时钟尺度 × 实例 rate)`，预热在当前 Scene 时刻采样，内部年龄仍逐步推进。按有符号的角尺度乘 π 加方向偏移，绕单位化的作者 Right 旋转整个 Forward，保留其长度。固定位置、同场不同年龄、负尺度和零时钟分别验收。随机速度沿原采样及 Movement，正交速度缺省已核 100/250，其他投影待独立验证。

冷准备形成旋转基，出生只消费帧时间、实例 rate、音频及两次原顺序随机取样。位置和第二路方向噪声退出；显式发射和事件建立的子实例接同帧 typed 时间，子预热复用同帧频谱。持续 Turbulence 保自身位置、相位与作用力合同。[速度对照](runtime-evidence-current.md#ember-turbulent-birth-speed) · [出生方向与预热对照](runtime-evidence-current.md#ember-birth-scene-simplex)

真正不可用的 HSV/list、Turbulent、Offset、Around/Between payload 仍保原 case、ordinal 和原诊断：HSV/list nil 只 attempted；Turbulent/Offset 即使 nil 仍 unknown，Turbulent nil 保 helper 的普通零/strict NaN；Around/Between nil 只局部 break，已具计划但本次 CP 不可用时 strict 才拒当前出生。事件继承只准备 operation，本次 parent context、audio、位置和时间继续由原 live 消费者供给。不得借本批前移随机区间减法、消耗或省略 RNG、改变 pow/乘加顺序、浮点环境、writer 顺序、快照和后继 live 状态。

验收先以当前优化机器码和采样确认实际复制，再用同输入交错对照否证收益；无可分辨收益就退回候选并重排。保完整粒子/RNG/emitter/归一寿命摘要、不可用组件和 strict 反例、显式事务与预热后 live 接力，另做实际作者和独立样本运行。单次 profiled 时长不作无采样基线，CPU harness 不外推 App Ready、GPU、能耗或全库收益。

验收核完整真实状态/RNG/事件/历史与 live handoff、多 Surface 独占、取消释放、真实初始画面和候选准备期间旧 Scene 输出。[运行证据](runtime-evidence-current.md)拥有当前结果；[官方 General 资料](../development/source-index.md#官方作者资料)按秒描述编辑器系统 Start Time，未直接定义 raw JSON 换算、内部步长/上限或隐藏创建策略。standalone 成本、直接 DEBUG Host 与物理多屏、daemon IPC、官方完整语义和逐帧流畅度分别设证明上限。

<a id="components"></a>
## 当前组件面

| 组件 | 已有执行路径 | 限制 |
|---|---|---|
| Emitters | 已准入的有序发射/连续与一次性出生，Sphere/Box 原计划、[速度数值](#emitter-speed)及 Sphere [方向选择](#emitter-sign) | flags、空间、audio、CP 和 instance override 必须满足该计划，不能从组件名推全参数支持 |
| Initializers | 位置、速度、旋转、尺寸、寿命、颜色、sequence 等 typed writer | 后写者及 General override 保作者顺序；未知字段只影响相关组件；HSV/Mirror/Position Around 等仍有未资格组合 |
| Operators | movement、gravity/力、颜色/alpha/size/旋转、noise、Remap、Vortex、Plane/[Sphere](#sphere-collision)/[Bounds](#bounds-collision) Collision、[单点半径](#control-point-radius)与[双点搬移](#between-control-points)等原计划 | 不支持操作不假装执行；与 child、CP、世界空间和 lifecycle blend 分别限定 |
| Control Points | 0…7 typed identity、静态/动态位置及 emitter、initializer、force、约束消费者 | 按 authored ID 而非数组位置；CP0/system origin 与其他 world source 不混用，未知 flags/angles/parent 不猜 |
| Instance overrides | 已有颜色、发射、速度、播放及 typed 动态输入 | 出生保各自基值。存量按实际算子消费，尺寸见 [SizeChange](#size-change-instance-override) |

<a id="instance-color"></a>
### 实例颜色覆盖

`instanceoverride.color` 除以255一次，优先于 `colorn`，在 initializer 后替换新生直色。属性只改变后续出生。
<a id="hdr-instance-brightness"></a>
`instanceoverride.brightness` 在场景装载时由 HDR 与 Bloom 同开选中，强度为0也有效。沿原 typed slider 和 Simulator 出生 writer 给直色乘有限标量，缺省或不可用取1。三类颜色均可乘，保零值、超白、alpha、后继 writer 与材质 `overbright`。热值只供有绑定的根实例，不传 child 模板。父事件颜色仍是实际出生值。禁用颜色覆盖沿原实现，官版 bit8、运行中切换 Bloom、脚本和动画供值待证。[运行对照](runtime-evidence-current.md#hdr-particle-instance-brightness)

<a id="ordinary-particle-sdr-material-gain"></a>
### 普通粒子在归一化颜色附件的材质增亮

共用普通非折射片元的 Sprite、SpriteTrail、Rope 和 RopeTrail 先在直色空间过滤纹理，以作者 tint 和材质 `overbright` 乘 RGB。在 BGRA8／RGBA8 归一化附件，每个片元在乘覆盖前把各颜色通道裁到 1；等价地，以片元的纹理与粒子联合 alpha 裁 PMA RGB。该 alpha 同时继续供原透叠或加色混合，多个片元各自裁幅后仍照常叠加。16 位浮点保留中间超白；折射与 A2C 的独立片元继续使用各自合同。

由原 Metal Pipeline 按目标格式冷选普通片元变体，删除按 Trail、R8、实例颜色来源和算子筛选的窄许可。沿原纹理、实例与材质传递输出，不增加帧分支、资源读取或 PSO 数量。验收取有色纹理、不同增益和 alpha、非黑底、半透明、两层加色、等价改名及浮点反例。原包核脚边光、独立原包核高增益青光，复用零增益、未超白和原白掩码的健康对照。

<a id="neutral-mask-trail-color"></a>3823864170 的白色 R8 半透明 SpriteTrail 是该裁幅的特例。双背景、改名和独立纹理的[验收](runtime-evidence-current.md#neutral-mask-trail-382)。

<a id="size-change-instance-override"></a>
### SizeChange 的实例尺寸

出生将有效 `instanceoverride.size` 纳入尺寸基值。模拟步从该基值重置，再按作者顺序执行各尺寸算子。每条 `sizechange` 将按寿命进度插值的原曲线值与当前有效尺寸倍率相乘，再乘入粒子尺寸。缺省倍率及禁用位128为1。单条和多条沿同一规则。热倍率随原 typed 输入进入模拟步，存量曲线读取当前值，出生基值继续保留；新生同时取得当时的出生倍率。无 SizeChange 的普通卡和其它尺寸算子沿各自既有规则。

原模拟器统一取得有效倍率，每条 SizeChange 在粒子循环外取值一次。现有曲线、预热、实例载体、GPU 几何和混合路径继续使用。验收覆盖单位值、放大和缩小、禁用位、等价端点、多条顺序、其它 writer、重复步、热重绑，以及原包与独立作者的实际 GPU 帧。脚本 `instance.size` 沿[原句柄事务](scenescript-api-coverage.md#particle-instance-scalars)供同一倍率，显式出生使用已发布快照。

<a id="control-point-position"></a>
### 控制点位置的取值职责

普通控制点的位置按当前 typed 动态值、instance override、definition offset 的顺序取一个值；前两者覆盖 definition 位置，不与它相加。Emitter、Force、位置 initializer 与距离约束使用同一取值语义。组件自己的 origin/offset 仍在取得控制点之后叠加，emitter 的 origin 继续按原角度旋转，不能与 definition 的默认位置混为一项。

鼠标绑定的 definition offset 是指针偏移，仍叠加当前有效指针；缺指针的真实消费者局部不可用，不回到系统原点。位置选择与空间转换分开：world 点经当前 `SceneParticleControlPointFrame` 的同一逆矩阵转到实际模拟空间，child 再复合原 origin/scale。冷计划和 typed 帧继续拥有字段、identity 与当前供货；没有位置 registry、缓存、第二时钟或每粒子的元数据校验。CP parent/angles 的未资格语义不能由位置覆盖实验外推。现有指针位置范围内，flags 恰为1、无 parent 且 offset 为省略或三维零的有效控制点，在 DefinitionParser 把静态三分量零角字面归入已有省略角度表示，Emitter、Around 和 Force 继续共用原 pointer 位置。带绑定的角度、非零和错型字段、父绑定及其它 flags 保原规则，动态角度仍走现有输入。本次不新增帧内比较、RNG 或 renderer 分支。验收固定移动路径，对照作者零角与省略，覆盖无指针、非零和改名，分别观察 SpriteTrail 与 Rope 的真实跟随。

Emitter frame 与 Simulator 共享同一纯位置选择；被普通位置覆盖替代的 definition offset 不参与 emitter offset 幅度检查。带角度 emitter 也不能因未消费的默认 offset 错型而拒绝。原 DefinitionParser 入口分别保存 offset 与其余 id/flags/angles/parent 的不可变解析错误，替换旧聚合；角度消费者只取后者，带角度 emitter 的默认位置仍被选中时在原 offset 分支消费前者，不能让坏位置冒充省略。位置覆盖不放开坏角度、flags、parent 或被选中的坏位置。world Force、ReduceMovement 与 Vortex 保原两类字段的拒绝范围；未读聚合的 static/pointer 分支不借此新增检查或授予资格。不增加兼容聚合 wrapper、供值链或逐粒子检查，RNG、出生顺序和显式发射事务仍由原 owner 执行。

验收用真实 Parser/Simulator 的默认位置、静态与动态覆盖、组件额外 offset、Around 共用端点及缺指针反例；带原角度的错型默认位置须与合法默认的同覆盖对照，保无覆盖、无 value、坏 metadata/被选位置及健康 emitter，再核实际 Runtime/Metal 与 App 固定位置、改名/等价输入。旧 App 若未命中首错或早于此处资源/producer失败，停止实施并回到资格，不追着结果调整 ROI。官方局部静态 CP 对照中，definition=(16,24)、instance=(48,0) 得到(48,0)，独立无 override 的正控仍为(16,24)；此证据不授错型 JSON、角度位义、全部空间或完整粒子效果一致。

<a id="control-point-radius"></a>
### 单控制点半径约束合同

`maintaindistancetocontrolpoint` 在原 Parser 一次准备 CP、distance 与 variablestrength，按作者 operator 顺序调整位置。CP 缺省0、distance缺省200；零或缺省强度采用直接半径约束，正强度使用每步 `min(strength × duration, 1)`，再应用原生命周期混合，不把编辑器显示的0…1范围当存储许可。未消费的附加字段与 raw flags 不阻断这些已实现输入。距离和强度只要求入口数值有限，不增加幅度白名单或逐粒子重复解析。

先把已有粒子随控制点相对上一步的位移搬移，再由当前位置朝 `CP + normalize(P − CP) × distance` 插值；保留已有 velocity。上一控制点与双点端点共用原 Simulator 的 typed 约束历史及快照，不增加另一个状态表。空粒子步仍推进点基线，首次供货不虚构初始位移；当前自然出生不重复搬移，半径操作照常执行。缺当前点只跳本操作并清其基线，复供从当前点开始。零径向长度不猜方向或删除粒子，已有安全位置保持；最终数值沿原 `acceptsMotionResult` 接纳，单粒子失败不撤健康后继。

控制点取值和 world→local 复用[位置职责](#control-point-position)。历史点以原 root reference 或 child canonical 空间保存，搬移量只转换一次；半径比较使用实际粒子的出生参考偏移，距离保局部单位，祖先与 child 的缩放由原转换和绘制消费。普通帧、构造预热及显式调用仍走原 typed 输入，实际 consumer 驱动 pointer/world frame 需求，不借 Force 的环境许可。

公开[组件说明](https://docs.wallpaperengine.io/en/scene/particles/component/operator.html#maintain-distance-to-control-point)和[实例API](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IParticleSystemInstance.html#controlpoint1-vec3)定义参数与供值入口；数值、步长和缺省行为来自固定官方客户端对照。该对照支持正强度逐步插值、单步上限、零/缺省强度的直接约束、缺省距离与显式200的有界等价、当前局部控制点搬移及已有速度保留；运行身份和原始资格归[运行证据](runtime-evidence-current.md)。负强度、零径向长度的官方行为、分数 lifecycle 混合与搬移的精确组合，以及同 cadence 改CP后显式发射的旧/新 cohort 顺序仍未资格。复用现空间合同不等于官方全部 world/child 组合一致，不能从一个作者恢复外推完整粒子兼容。

<a id="between-control-points"></a>
### 双控制点位置与距离约束

`mapsequencebetweencontrolpoints` 在原 initializer execution plan 中准备；Around 使用同一计划数组，没有第二份按 initializer 对齐的控制点数组。缺省 Count32、bounds0…1、CP0→1、Repeat。有限正 Count 不设编辑器范围上限；有效值不大于1时取首端。Repeat 的离散序列包含末端，Mirror 往返不重复转折端点。实例 Count 仅在 raw bit16 开启时参与，保小数；General 的 Count override 位仍由原统一倍率消费者决定，不把周期 cap 的向下取整套到路径序列。

同一相位 u 产生项目包络 `4u(1−u)`：bit1作用位置扰动，bit2作用速度扰动，bit4按 `1−amount×(1−包络)` 缩放尺寸，amount缺省0.9。两个当前端点按 bounds 插值；只去掉当次 emitter 的 CP 平移，保 emitter 额外 origin、之前 writer 和位置噪声，不取第一个 emitter 猜来源。后续 writer 保作者顺序。该包络与官方局部位置/速度点位及尺寸顺序相容，精确全域公式和像素仍未资格，不能以本引擎数值回归宣称官方完整一致。

raw flags 按消费者取位，没有组合许可表；未知附加字段和未消费选项不阻断已实现 writer。raw0x08和0x20当前只保未消费诊断，周期重启及弧向参数仍需真实消费者；非零arcamount尚无消费者，其与bit8的关联未资格，不能以缺该位宣称参数无效；坏的尺寸选项也只使该尺寸写入不可用，不撤位置/速度。缺真实端点只跳相关普通初始化，后继 writer 与健康 emitter 保持；显式 exact-n 沿原候选事务处理失败，不借旧普通帧的 world frame。有限性最终在原出生结果消费处检查。

`maintaindistancebetweencontrolpoints` 按原 operator 顺序，以当前位置在上一对端点轴上的比例分配两端位移；保法向偏移、已有运动和原 lifecycle blend。每 operator 只有上一对端点，进入同一 Simulator 快照；每步统一推进一次，本步已按当前端点出生的粒子不再重复位移。旧轴无法计算比例或缺输入只影响相关操作，复供从当前端点建基线；端点不变时不遍历粒子。初始 typed CP/angles 在预热前进入原模拟器，普通帧和显式调用点各自供当前值。

General world 根系统的约束端点先进入原 translation reference。world child 的约束使用 canonical root 空间：端点来自当前 origin/scale，存量粒子来自原出生 origin/scale，位移再转回 child；follow 移动不会额外拉动世界空间粒子。出生原点复用原 ChildSystem 表，构造预热存量也进入该表；本次帧值只沿函数参数传递，Simulator 不另存表。

空间与生命周期职责见[架构合同](../architecture/runtime-architecture.md#particle-control-point-components)。验证区分真实 Parser/Simulator、Runtime→生产 Metal、实际作者捕获和官方局部对照；未覆盖的弧向、周期/显式序列、多 emitter、parent映射与更复杂 child 行为见[队列](../roadmap/scene-open-breakpoint-queue.md)。

<a id="emitter-speed"></a>
### 发射速度数值

speedmin/speedmax 是有符号初速，端点独立缺省0。原 SpawnPlan 准备有限有序区间，抽样顺序与原 seed 保留。非零半径的负值沿径向向内。

Sphere 固定零半径时，出生位移为零，初速使用同一次球面抽样的方向。Directions 缺省沿 XY，各轴幅度参与方向加权，sign 仍用于选择非零出生位置的侧向。原 SpawnPlan 预备绝对轴权重，零半径按最大权重归一；轴集合不变时，统一放大 Directions 不改变初速。保留轴、径向和速度抽样的次序，沿原初速、initializer、实例倍率和坐标链。正半径和极小正半径继续用实际位移，Box、图像发射与全零轴沿原行为。不新增粒子字段或渲染分支。对照见[零半径初速证据](runtime-evidence-current.md#zero-radius-sphere-launch)。

有当前世界基底且无 CP 供货的 General 世界根球形发射器，在自然出生时用完整世界基底下的发射向量长度计算 `launchVector / worldLength × speed`，保作者速率及变换后的方向。出生半径仍随层缩放；局部粒子初速也随层缩放。Initializer、CP 发射、子粒子、显式发射与 world Movement 仍用原坐标消费者。

原 initializer、实例乘数和坐标变换之后才校验寿命与Float/GPU可表示性；失败只丢该新生，显式命令沿原 exact-n 事务回滚。固定轴、速度符号和端点、溢出、改名及原作者见[运行证据](runtime-evidence-current.md#world-sphere-launch-speed-365)。

<a id="continuous-emitter-audio-response"></a>
### 普通持续发射的音频响应

符合原普通持续 Sphere／Box 发射合同的音频模式直接读取共享的作者16档。Left／Right 取相应侧，Center 对每个选中档先取双侧平均。含首尾的选择区间取峰值。峰值按作者 bounds 归一到0…1，先做 smoothstep，再取作者指数幂。持续发射的指数接受有限正值，删除原16上限。允许超过1的上游频谱进入 bounds 运算。

原发射计划在准备时选择公式，原普通速率积分、余量、出生顺序及容量继续承接响应。静音不产生新出生，已出生粒子按原寿命播放。沿原合格模式、范围与时序准入，坏声明只影响相应发射器。初始化器与算子共享输入并沿各自原响应。无需额外的频谱、副本或时钟，调试回执与产品用同一次选带。

验收含错频、左右错档、边界、超过1、E1／E100、坏模式、关闭音频及改名，相邻初始化器与算子保原行为。复用官版选频板和原曲，核原包出生与画面、独立作者和静音邻例。[选带与曲线实证](runtime-evidence-current.md#floor-beam-emitter-338211)

<a id="emitter-sign"></a>
### 发射方向字段

Directions 是各轴距离倍率；原形状及有限值检查在冷准备消费，不再限制其绝对幅度。Sphere/Box 共用原 SpawnPlan 的距离字段，分别准备规范化的标量区间与原向量区间。Sphere 将径向幂写成最大半径归一化的下端幂，保原轴 mask/维数和每次出生的随机抽样顺序；先将单位方向乘 Directions，再乘最大半径，最后乘归一化因子，避免小半径先求幂或先缩小导致错误零。径向随机值恰为0时直接取原下端；零半径仍为零。旧绝对半径幂字段退出，准备标量净减一个，不增加缓存、owner或逐粒子校验。

规范化后仍非有限的Sphere半径在原cached shape入口局部拒绝，不继续消耗该无效新生的RNG/ID；其他shape的距离语义保持。正常有限输入保原抽样次数/顺序，归一化运算不承诺旧公式逐bit舍入相同。有限输入产生的实际乘积溢出仍由原最终Float/GPU检查拒绝，保健康peer与显式exact-n候选事务回滚；不以Double有限替代最终可表示性。该数值修正不宣称恢复尚无幅度门独立拒绝证据的作者内容。

Sphere 的 sign 逐轴按原有限值选边，零取双侧，任意非零含小数按正负选侧，幅度不乘半径或速度。退役冷 SpawnPlan 的整数截断和抽样中的近零门。入口仍校验原形状，CP、随机顺序、实例倍率和世界转换沿原链。

<a id="box-distance"></a>Box 绕 CP/发射原点逐轴抽样。Distance Min 是带符号距离基值，Directions 的绝对值缩放 Min→Max 的跨度；每个非零轴以对称随机符号映射到原点两侧，零方向仍归零。Min=0 沿原双侧最大距离抽样，保持普通宽度和随机序列。轴间沿原 RNG 次序；非有限距离轴在 SpawnPlan 局部归零，邻轴仍出生。位置和径向初速继续消费同一偏移，Sphere/图像发射沿各自现役语义。验收覆盖固定/反序端点、正负/零方向、默认/改名与独立作者。Box 的 sign 无消费者，解析入口投影到省略，Sphere 与其它形状保原字段及资格。正例核自然/显式出生及 GPU，坏方向、Sphere 或图像声明失败限对应组件。

官版实际1/2/3轴均用小数选侧，静止雾与无遮挡对照分离出生和画面遮挡。旧手工JPEG的双侧判断退役。验收核改名、零、正负小数/整数、坏输入、原包和独立整数源。[运行证据](runtime-evidence-current.md#moon-fog-fractional-sign)

验收在真实Parser→冷计划→constructor中核整数/小数、各轴、缺省、改名及非有限反例，保健康peer、RNG/事务；用原Runtime→生产vertex/Metal读回几何和像素，并复测原作者与独立邻例的birth→目标batch→main/seal/GPU捕获。未资格组合继续按实际消费者的最小失败单元处理，不能再扩一个数值白名单。

<a id="periodic-emission"></a>
### 周期发射的数量合同

原 DefinitionParser → SpawnPlan → EmitterState → Simulator 承接周期数量。`maxtoemitperperiod` 只解析一次并进入原周期计划；缺省、0与负数沿无上限路径，正数由原自然发射消费者逐活动窗执行，不能因存在该字段拒绝整个发射器。当前 `count` 同时缩放发射率与周期上限，有效上限取正数乘积向下取整，再减去本周期已消费的自然请求数量；中途更新 `count` 不重置已用数量。每个 emitter 只在原 State 增加一个计数值，进入新活动窗及既有 rearm 清零；不保存倍率副本或第二份剩余额度，不建许可表、调度器或缓存。

沿原窗口时钟/RNG推进，触顶只抑制本窗额外自然请求，不提前进入间隔，不停止小数余量积分；余量跨间隔与周期保留。跨多个窗的单步须在原循环内逐窗限额和重置，不能先合并所有活动秒再限一次。无上限仍保原活动秒聚合后一次积分的运算顺序。准备期的字段/时间区间检查、原1024窗口工作预算与非有限 accumulator 的局部失败保持；此消费者不借 cap 开放其他尚无消费者的 flags/audio/burst/duration 组合。

自然出生仍按作者 emitter 顺序，经过原系统容量裁剪与 constructor；额度按原 maximumParticleCount 有界的调度请求消费是本引擎当前策略，容量饱和时的官方计费点尚未确定。官方短命满槽对照中，无上限也会延后出生，不能据它选择计费公式；该通用调度差异独立留在[队列](../roadmap/scene-open-breakpoint-queue.md)。不为未证组合新增播放许可或改动已可用路径。显式 exact-n 沿原调用点/事务及容量处理，不扣自然额度，不把 cap guard 搬到整个 preparedPlaybackWork；早期显式调用对自然相位的官方差异另列队列，不以晚命令仍贡献证明完整交互一致。

状态随原 emitter 数组的值快照、候选回滚、prewarm→live 和 rearm 生命周期走；GPU重试不重发。验收使用真实 Parser/Simulator 的固定两周期、倍率小数与热更新、余量、改名/相邻无上限、独立 emitter、随机窗/跨窗步、快照/回滚及播放生命周期，并经原 Runtime→生产 Metal 核实际几何/像素和作者目标 batch→main/seal/GPU。官方手工图只证明已测输入的可见出生位置与控制时钟，不是内部人口、RGB或所有参数一致证明。

<a id="sphere-collision"></a>
### 静态球体碰撞的执行合同

Sphere沿原DefinitionParser一次准备显式local origin、radius及bouncefactor，typed plan进入原有序Simulator，不新增时钟、出生阶段、CP状态或GPU补正。缺省behavior采用已观察到的Bounce类响应，显式stock `slide`保切向响应；缺省数值、Stop/Delete和CP锁定位未资格，不猜默认或复制位义。CP333和无关附加字段不作为整操作许可，未消费选项不授完整能力。

独立实现采用当前粒子到球心的径向位置投影，以及现有Plane的法向冲量：只纠正球内非零径向位置，只改变入向法向速度；Slide的法向反弹为零。球外、出向速度及切向分量保留；零径向不猜方向。球心复用原positionReferenceOffset转换到粒子出生参考，原lifecycle blend按现有计划作用于结果，最终数值交原acceptsMotionResult接纳；坏输入或单粒子结果只影响本操作，健康后继保持。入口只校验所用数值和向量，不设幅度、flags组合或额外字段白名单；audio尚无Sphere响应消费者，保持局部不可用。

公开[碰撞合同](https://docs.wallpaperengine.io/en/scene/particles/component/operator.html#collision-operators)规定球形障碍、Origin/Radius与Bounce/Slide。官方有界输入支持缺省反弹类、factor相对响应及切向位移保留；严格时钟误差跨门，不能唯一确定首次法线、位置修正顺序、粒子尺寸裕量或精确公式。因此当前径向投影/冲量属于项目离散算法，未授官方数值一致；保原正步emit→有序operators，不为拟合截图增加出生零步或重排Movement。CP1与省略同位不能证明锁定位或CP供给，具体资格见[运行证据](runtime-evidence-current.md)。

验收核真实Parser/Simulator的几何、factor/slide、顺序、改名/无关metadata、球外/出向、坏数值/零径向及健康peer；再经原Runtime→生产Metal核可定位几何与像素，复测真实作者及独立邻例并保Plane回归。实际接触及最终贡献未到达时不得以识别/批次数宣称恢复；更复杂world/child、动态CP、连续碰撞和死亡事件仍需独立资格。

<a id="bounds-collision"></a>
### 壁纸边界碰撞的实现合同

正交平面中带无参数 `collisionbounds` 的局部坐标根粒子系统在作者画布边缘回弹。固定官方客户端的右边界对照支持保留切向和约半速的法向回弹。原作者、独立邻例及受控终端画面范围见[运行证据](runtime-evidence-current.md#particle-bounds-oracle)。

原 Parser 冷准备识别算子。Runtime 只在有需求的原根实例保留作者画布尺寸，在实际预热或推进时与对应世界矩阵汇合，含既有粒子局部 Y 换向。物理边界使用画布范围，窗口取景和鼠标视差继续由渲染处理。Simulator 在作者顺序的原位置消费。将越界中心夹到对应画布边，直接逆变换该点，只反射出界方向的法向速度，保切向和已朝内的速度。缺省采用 0.5，接触位置沿原固定步进决定。

实现不增加状态时钟、第二份粒子空间、帧内图重建或全系统扫描。平面逆变换在供货处计算一次，单粒子在界内直接返回，原 Z 保留。不能取得合法画布或同空间变换时仅跳过该算子并保 Movement、Fade 与其他系统。优先接通作者缺省输入，显式 Bounce/Slide、控制点锁定、旋转停止、Stop/Delete、General 世界空间、子系统和非平面作用各随可区分证据扩展。

验收用真实 Parser/Simulator 复现作者 891 的同 ID 入向越界和反弹，核画布边界、切向、朝内、未碰触、同顺序与改名，以及缩放/旋转、预热和无有效画布的反例。经原 Runtime→生产 Metal 验证固定输入的轨迹与最终像素，原作者须保原折射材质、显隐和主景；独立作者至少复测相邻 Sphere/Plane 和原相机取景。官方右边界控制只限定已测行为，不用于拟合作者画面。

<a id="scalar-oscillation"></a>
### Alpha 与 Size 振荡

两种标量算子共用冷准备的相位、频率及尺度跨度。以稳定粒子单位样本 `u` 同时在相位与频率区间取值，振荡系数为 `scaleMin + u × (scaleMax − scaleMin) × (sin((粒龄秒 + 相位) × 频率) + 1) / 2`。频率缺省 1…10，相位 0…2π。Alpha 尺度缺省0…1，Size .8…1.2。固定尺度直接采用作者值。粒龄沿原固定模拟步，blend 以归一寿命把系数向 1 混合后乘当前属性。基线重置及作者顺序继续归原 Simulator。

与持续 Turbulence 共用原粒子身份取样语义，不进发射 RNG，也不新增逐粒缓存。退役旧相位外加、余弦起点及不受粒子幅值约束的各自采样。Position 振荡仍消费自身向量与位移合同。验收覆盖固定频率/相位、相位变体、Size 与 Alpha 同源、固定端点、作者混合及既有 position 邻例。固定实机轨迹以单粒亮度和卡片宽度测量，真实作者以原图层实际合成验证。成熟覆盖继续以同龄 Sprite/Trail 分别比较。[官方作者说明](https://docs.wallpaperengine.io/en/scene/particles/component/operator.html#oscillate-alpha) · [定相位与原包复验](runtime-evidence-current.md#particle-scalar-oscillation)

<a id="operators"></a>
## 需要保留的数值边界

- Remap 仍由原 `SceneParticleRemapValue` 准备 velocity/simplex 与 scalar-speed/FBM 两条有界计划；真实input selector/range、其他输出/操作及外层lifecycle blend尚缺完整消费者。独立静态范围、晚EventDeath实例与sine正控的当前资格见[运行证据](runtime-evidence-current.md)；场景对齐候选类不等于所有时钟/预热/rate行为已定，sine及作者缺省参数仍未资格。新实现沿[标量Remap合同](../architecture/runtime-architecture.md#particle-scalar-remap)替换两份平行可选计划，保原noise/RNG行为；不能用猜公式或新增字段组合白名单补第三路径。
- Vortex classic 与 v2 有不同 flags/轴/CP/audio 资格。现有默认原点的 v2 固定半径及强度为项目有界响应。显式控制点的方案见[定向 Vortex](#oriented-vortex)。
- Plane Collision消费原准备平面；静态Sphere由[球体合同](#sphere-collision)维护。壁纸画布边界的实现范围归[Bounds合同](#bounds-collision)。
- Position Around Count 是序列除数，支持大于等于 1 的有限作者数值，保留小数。整数可沿 ID 取余，小数沿原分段余数，超出 ID 范围的除数直接消费原 ID；计数只参与相位计算。准备时由同一 typed plan 汇合控制点和发射源约束，出生只消费该计划。未资格的轴、Mirror、periodic 与空间组合仍沿原边界。
- Position Around 使用同一粒子空间中的实际出生位置与目标控制点之差。轴向投影保留出生所在的轴向平面，垂轴分量给出半径；绑定只决定实际出生位置。斜轴以局部负 Z 在垂轴平面的投影为零相位，正交切向按作者轴取向；正负 Z 两极均从正 Y 向正 X 起转。速度的 X/Y/Z 分量分别进入同相位的切向、径向和带符号轴向，保留原出生抽样与叠加顺序。以同一对正弦、余弦求位置和速度，退役独立的速度旋转。Mirror、极近轴数值边界及完整动态相位仍待资格。
- Control Point Force 沿点与粒子的径向施力，正吸引、负排斥，强度随距离递减至零。General 世界根的指针力用当前完整世界基底量测距离，作为门限、衰减及单位化的依据；以原局部相对向量累加冲量，无第二次转换。局部、非指针与子系统各用原距离空间。保原点供货、缺省距离、约四分之三的加速度倍率、生命周期权重和 Movement 顺序。精确时步与其他模式分别判定。
- 线性 Movement 把作者 drag 消费为每秒速度半衰次数，步内速度保留量为 `2^(-drag × dt)`。沿原 gravity 输入与当前空间变换，按同一步内的保留量积分重力，再交原位置、Vortex 与数值接纳链。零 drag 仍作整步重力积分，负值保有符号增长。因子每次 operator 求一次，替换原逐粒子线性阻尼；Angular Movement 沿其独立合同。固定客户端同龄及正负初速对照支持此项目模型，精确时步顺序和大 drag 偏差仍待资格。

源码：[Remap](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRemapValue.swift)、[Vortex](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleVortex.swift)、[Plane Collision](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleCollisionPlane.swift)、[Sphere Plan](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleCollisionSphere.swift)、[碰撞消费](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulator+Collision.swift)。

<a id="oriented-vortex"></a>
### Vortex v2 的显式定向控制点

`flags=2` 的 v2 可读取已准备的非原点控制点。该作用接受可供货的局部点及其角度，沿当前 typed 角度、实例值、声明默认的优先级，在算子当步计算旋转轴。该模式的 `ringradius`、`ringwidth` 和 `ringpulldistance` 是留存值，官版删字段对照限于此模式。真正环形选择、拉力、额外旗标和未资格控制点空间保留原边界。

General 世界粒子沿原参考坐标。无控制点的根球形发射器显式 origin 是世界位移，沿[发射入口](#emitter-speed)投影一次。定向点 Vortex 将轴及相对位置带入同一受力空间，保轴幅度。切向仍取垂轴分量及点距。半径约束以控制点到粒子的完整方向投影速度，复用已求点距。作者算子依序执行，冲量一次映回，Movement 独占位置积分。[实机与原包](runtime-evidence-current.md#vortex-radius-center-365)核近轴、垂轴及零力。

同一 Vortex kernel 保已有非世界原点固定半径。显式定向点退出 CP0 零角零位及必须隔离后续算子的关卡，沿原计划、固定模拟步、当前参考点和粒子 rollback。缺当前基底或不可用控制点仅略过该算子，后继约束和 Force 按作者顺序继续。无需其首帧固定半径状态和额外资源。验收核镜像角度、删留停用字段、原点世界出生、旋转和独立倍率、旧原点邻例、原包内圈及健康外场，并把近似结果与官方相位分开记录。

<a id="children"></a>
## Child 与事件

原 ChildRuntime 处理已准入的 static、spawn、natural-death 和 follow child 及其局部时间。child 不是克隆父 RNG/clock 的另一个全局系统；父末帧/自然死亡与显式 stop/destroy 分开，不能擅自给未接入的碰撞/delete 事件生成 child。

当前 strict 计划最多 depth two，每深度系统数和粒子容量分别受原 64/65,536 预算约束；static Rope 另有 template/扩张预算。预算是当前实现限制，不能冒充所有作者格式的永久语义。

hidden/dormant child 的实例和潜在 renderer 需求保持。已提交销毁 root 时，由实际归属退休其 CPU root 与独占 ChildRuntime；健康 root 的 RNG、clock 和状态不变。冻结 DrawBatch 继续是值，不被退休操作追写。

<a id="child-plane-scale"></a>
### Child 平面缩放与 Sprite 几何

目标是让正值非等比 XY 的局部 screen Sprite 沿原 child 事件与批次出图。中心仍为 `origin + scale × position`，速度沿原变换；原 `size × scale.x` 继续承担共同尺寸，原 Template 冷准备唯一形状比例 `scale.y / scale.x`，经既有 DrawBatch 到 CameraFrame。Sprite 的粒子旋转先执行，平面比例随后作用于系统局部几何，最后进入原 layer/camera；不得再把 child scale 乘进中心模型，或借 TEX 帧宽高伪装形状。

CameraFrame 在原 screen 几何处形成 `linear × diag(1, ratio, 1) × billboardBasis`，只供既有 `spriteRight/Up/Forward`；中心模型、方向/光照基、view 基及 VP 不受该比例改写。比例为1走原几何，无新 shader、GPU布局、逐粒字段、owner、缓存或时钟。旧 XY 等比与任意已准入 Z、Trail/Rope 的尺寸与速度链保持；这不是完整 XYZ 形状缩放的资格。

新范围限 `z=1`、非 General world 的局部 screen Sprite leaf；其他非等比 renderer 在原冷计划按 renderer 局部诊断，健康 Sprite/父/peer 继续。镜像、声明旋转、嵌套缩放和 world movement 沿已有边界，不用资源名、路径或样本选择算法。验收使用真实准备→事件→batch→CameraFrame→Metal，核两向非等比、旋转角点、中心只缩放一次、改名、等比邻例与混合不支持输出，并补真实 follow/spawn 作者和独立邻例。官方同输入正控及误差裁决归[运行证据](runtime-evidence-current.md)，未资格的倾转/世界空间不外推一致。

<a id="child-declaration-options"></a>
### Child声明选项与实际输入需求

ChildGraphExpansion先解析已有trigger/transform并取得asset，再按原typed selector/可执行plan判断CP读取需求。无CP消费者的leaf沿原事件、constructor、实例、预算和draw执行；不解释的declaration flags或未消费start index保一次准备诊断，不用flags==0或{0,1}作播放许可。CP需求判断只在冷准备且有非零未解释声明flags时执行；flags0的start index是被动参数，不启用绑定或触发读取许可。无新增状态、时钟、CP表或逐帧定义扫描。

CP需求不能用CP数组或共同controlpoint字段猜：Emitter的实际source（含隐式pointer CP0）、Around/Between initializer、Radius/Maintain、Force、Reduce及Vortex v2的CP0分别沿各自既有typed计划取事实；Sphere残留CP333不产生读取。非零未解释声明遇到真实reader或未资格子树时，仅该child template保持绑定不可用，父和健康peer继续；不能删请求后读默认点。原flags0/startnil与static raw-parent copy路径保持，旧parent-mapping诊断缺口独立留队列，不借本批改变其未知位置语义。

公开[Children合同](https://docs.wallpaperengine.io/en/scene/particles/component/children.html#child-particle-system-configuration)规定death在父末位置创建及可选控制点设置，但没有declaration位表。官方同输入flags0/1的无CP/无继承leaf三点L，在真实death、晚父存活和死亡后平移条件下等位稳定，支持此base切片；flags0/start1的CP正控保持真实静态半径读取；另一CP支线白蓝重合，parent-particle来源和位义仍未知，不能外推所有flags、General world位或祖先镜像组合。验收用真实GraphExpansion→事件→child Simulator/Metal，核活跃CP及隐式源反例、改名/无关metadata、正常死亡/显式销毁、健康peer、快照及实际作者捕获；不以准备放行或root draw代child贡献。

<a id="event-value-inheritance"></a>
### 事件值继承的职责合同

父出生/死亡事件已经携带真实粒子状态；ChildRuntime 在原有 child 系统构造点只投影继承消费者需要的 color、size、alpha，follow 在原父状态刷新点更新同一 typed context，不能另建 parent registry、时钟或 per-particle 影子状态。Snapshot、restore、clear 继续由原 Simulator frame 值持有。上下文不得依赖 Parser 目标之外的完整粒子类型，投影留在实际 runtime owner。

`inheritinitialvaluefromevent` 的 input 在原解析入口一次转为已实现操作的 typed enum，缺省 setcolor；multiplysize 以触发时父 size 的一半乘当前子 size，setopacity 赋父当前 alpha；固定官方的父倍率2/3及独立同源参照限定这两个消费者的单位和供值候选，不能外推全部死亡末帧混合公式。未消费的编辑器字段不参与播放许可；未知或错型 input 只使该 writer 不可用，不整批拒绝健康 child。实际无 parent 的初始化不伪造供值；连续 operator 仍只有原 follow setcolor 消费者，不由共享 enum 顺带扩其他模式。原全字段白名单、整 template 的继承许可和 initializer plan 的重复 Bool 随替换退出。

初始化沿原作者顺序修改同一新生状态，最后由原构造点统一建立 initialColor/Alpha/Size 并校验最终 GPU 数值。随机 size/alpha writer 沿作者顺序相乘；继承 opacity 后的 alpharandom 继续乘该继承值。官方两次 size4→6、alpha.5→.8及固定父.4→继承→random.5分别与独立24/.4/.2参照相容，直接覆盖候选不成立。原 Simulator 冷准备一个出生 size seed：有 size writer 时取乘法单位1，无 size writer 保原默认20；它不进入活动快照，不在逐出生时反复扫描定义。不能按样本或固定声明形状分支。无消费者、缺上下文和坏值局部降级；最终实际溢出仍沿原出生拒绝，不让一个新生污染健康系统。

验收使用真实 Parser→Simulator→ChildRuntime→实例/生产 Metal，包含原事件载荷、当前/出生基值可区分输入、follow 后续出生、随机 writer 交错、改名/无关字段、坏 selector、无 event、最终溢出与健康 peer，保原快照/RNG/显式事务。真实作者须取得死亡触发、child 接纳出生、目标 batch 及最终 capture，不能以 root 已有 draw 或准备门放行代替。公开组件说明与本机有界对照不授全部 selector、RGB 取值时点、世界空间、完整作者效果或性能一致。

<a id="rendering"></a>
## Renderer、材质与 GPU

Sprite、SpriteTrail、RopeTrail、refraction 与 depth 复用原几何、材质和目标。保 TEX 帧与非方宽高比；Rope 按整图取样。 <a id="world-sprite-trail-length"></a>根世界 SpriteTrail 以同帧绘制线性基把模拟速度映到场景，再用世界速率乘作者 length、限制于作者上下界。实例上传同域单位方向与已限伸展，Metal 沿此方向应用粒径和原帧宽高比，退出纵轴的第二次图层缩放；零速度没有纵向位移。局部 SpriteTrail 仍先在局部限长再变换，子系统和端点型 Rope 沿原几何。无新模拟状态；组件计划一次求速度与方向。验收保同纹理单粒/叠加、上下限、局部对照、旋转镜像和改名，并用原景与独立作者比可见足迹。

本地尺寸透视根 SpriteTrail 的 Screen 宽轴取局部眼线与速度的垂向，随模型变换，绕序随手性，过眼平面时 U 连续。CameraFrame 每批投影一次眼点，退出会放大近眼尾部的宽度反解。共线用相机横轴，模型不可逆沿局部朝向。其余几何模式各用原宽轴规则。

<a id="multiple-renderer-outputs"></a>
### 同一模拟的多个 renderer 输出

每个系统共用原模拟、RNG 和活粒子。按作者 renderer ordinal 准备有效输出，保重复 kind 和顺序。坏组件只退出自身，容器可无根绘制。child 的 RopeTrail 仍因缺历史消费者而局部不可用。

原root/template拥有共享材质与source资源；输出只持实际几何Plan、orientation/camera及必要instances/history。Sprite帧、Rope整图和REFRACT的color/normal是原资源的不同consumer view，按实际需求各准备一次并共享同身份texture，不能为Rope全局抹掉animation或重建材质/源图。材质状态沿原compiler冷编一次；退出whole-definition的camera选择及其混入material state的字段，实际prepared renderer/DrawBatch向原CameraFrame供相机约定，REFRACT和ordinary输入边界保持。

一次advance后只消费一次step snapshots，Sprite/SpriteTrail读取同次current/transient population，Rope读当前粒子，RopeTrail保各自有界历史与死亡排空。不同RopeTrail采样策略由原StepSnapshotRecorder按冷准备的唯一policy分别保必要间隔/容量；同一步需要的particle snapshot只转换一次并共享，不增加模拟推进、全局clock或每帧建图。相同policy不重复录制，不用最细间隔配某个单策略容量截短另一条尾迹。snapshot/restore、pause/stop、显隐与退休覆盖全部输出，population、事件与生命周期计数不按renderer倍增。

原Metal上传key扩展为layer、child-template与renderer ordinal，避免prepare多batch时覆写同一可变buffer/count；不按kind合并重复组件，不新增GPU owner、缓存或compositor。原command completion、cancel、在途slot和按layer退休释放承接所有ordinal。root与child已有Sprite/SpriteTrail/Rope消费者一并退出scalar选择；未实现的几何/纹理/child组合仍只在其真实消费处失败，不新增组件数量或名称许可。

验收比较真实Runtime中完整renderer数组与各单组件对照的模拟状态/RNG及每输出instances，含改名、重复kind、坏组件/健康peer、不同历史策略、死亡排空、rollback/stop与child事件。生产Metal核同root/template多个ordinal的可区分像素和原completion释放；原作者核每个活动输出的材质/normal/背景、main/GPU及实际画面，另保单renderer独立邻例。加载层数、batch数或非黑不能代替像素贡献；若组合视觉仍不可分，记录边界，不改作者rate/alpha、叠加顺序或几何参数拟合。

composition 成员使用 nearest group 的原 MainPass；canonical camera/viewport 保留几何和 Trail 度量，最终 XY 与 REFRACT 位移才转换到目标。两行 raster uniform 位于原字段之后（CPU/MSL stride304），Z/W 保原相机深度；depth 与背景快照消费真实 attachment。没有逐粒子 CPU 转换、第二相机或按效果名准入。完整职责和仿射输入合同见[组合层栅格](effect-execution-coverage.md#particle-subtree-raster)。

CPU batch 不持可写 instance buffer。原 ParticleMetalPipeline 按 root/child-template/renderer-ordinal key 拥有上传 slot，形成 frame-local PreparedBatch；prepare/upload/draw/arm/cancel 由同一 GPU owner 管理。在途 buffer 与 depth/refraction pin 随真实 command 终态释放。

Surface 采用新 topology 才退出死 root/child GPU key；重建构造前过滤 committed 死 root。未提交取消释放其 slot，已提交不能用 CPU 回滚撤销。hidden 不等于退休，peer key 可复用。

材质剔除由原 Metal raster 状态消费：`normal` 编译为 back-cull，`noCull` 保双面，共用已有三角绕序与 vertex。其资格不依赖 renderer 名称或 REFRACT 组合，不改变相机、basis、尺寸与变换、纹理 UV、snapshot 或输出 owner。镜像是否翻面按实际几何投影决定，不改 front-facing 补偿作者变换。

<a id="root-world-sprite-alignment"></a>
### General 世界根 Sprite 的屏幕朝向

符合既有场景相机几何合同的 Sprite，screen 朝向在 General 世界根上使用现有世界屏幕轴。原 root 变换继续决定出生和中心，世界尺寸与粒子自身旋转照原输入。原 renderer 冷准备选择已有 `.worldScreen`，退出这类卡片轴对根层旋转的局部继承。折射、未识别的朝向、局部 Sprite、子系统、显式固定或竖直方向和拖尾沿各自原几何计划。

实机正、零、负根旋转验证屏幕轴及真实出生位置，局部正角验证原几何。独立世界根作者与已显式世界 Sprite、Trail 作为邻例。沿现 CameraFrame/Metal 消费，无新增 shader、状态或逐粒运算。

<a id="rope-trail-length"></a>
### RopeTrail 的缺省 length

省略 `length` 的合法轨迹与显式 `1` 使用同一准备计划。固定官方2.8.0.42的原生加载归一静态观察支持缺键填1.0；不据常量推时间单位、完整history公式或官方像素一致。

原DefinitionParser入口仅为RopeTrail真正缺键补1，传原typed Double给RopeTrailPlan；null、坏类型与显式非正值保原边界，不把所有nil都变缺省。原step snapshot、history裁尾/退役、UV/joins、资源与GPU继续消费同一计划；不新增字段、状态、缓存或普通帧分支。缺键语义与[公共朝向及subdivision](#rope-trail-world-subdivision)分别在原owner准备，不扩动画或预算。

回归沿真实Parser→Runtime比较省略/显式1及改名的出生、轨迹与快照重试，保null/坏值/零/负值及健康peer；App核同帧两轨平移后实际像素、原作者活动root的出生/材质/主合成/GPU，另核未参与修改的RopeTrail。无实际轨迹或首障碍转移时记录断点，不调长度救图。

<a id="rope-trail-world-subdivision"></a>
### 公共朝向与 RopeTrail subdivision

RopeTrail复用[公共renderer Worldspace选项](https://docs.wallpaperengine.io/en/scene/particles/component/renderer.html)，由原`isWorldSpace → Orientation → CameraFrame → Metal`消费朝向；它与General的存量位置/尺寸语义分开。几何计划不再只因已解释bit0拒绝整renderer，未知位仍局限该renderer。此接线不新增raw bit映射、owner或视觉算法；固定客户端的特定draw reader仍未知，不授官方像素一致。

原RopeTrailPlan把已接纳整数subdivision一次归一到0…32，再派生段数、snapshot间隔及容量；固定2.8.0.42的加载静态证支持该钳制。负数不取abs，缺省1、length准备及原history/UV/joins/预算不变；退出负数误拒和归一后重复的范围检查。不在帧内重新解析或检查原声明。

验收沿真实Parser/Runtime保flags0/1、General world独立、-16/0与33/32、资源/ID及参数顺序变体、unknown2/3和健康peer；生产Metal与App补非identity系统朝向、固定像素/形态和实际root材质→target→合成→GPU。原作者活动十root与未参与修复的内容分别取证。相机view轴和geometry轴的既有独立选择不在本批改写；其差异尚非已证错误，若阻断实际结果则另沿原owner定位，不用新许可或fallback掩盖。后继无实际出生/轨迹、资源失败或现预算不足时记录首断点，不提预算或缩内容冒称恢复。

<a id="optional-refraction-normal"></a>
### REFRACT 的可选 normal

材质 Catalog 在唯一入口保留纹理槽位并把缺省值投影为 `[String?]`。Planner 对可选第二槽只消费这个 typed 值：省略槽和显式 nil 都交给原无 normal 分支；非空引用继续经过真实资源解析、装载与格式判断，显式缺失或坏文件只使受影响资产不可用。不能通过 compactMap 把后续纹理移入空槽，也不为已解析的 nil 增加原始字段复验、默认纹理或资源 owner。条件/user texture 的动态生产者保持独立职责。

原 TextureLoader 的 nil 分支复用既有绑定并以 authoredFormat=nil 供 Pipeline 的原无 normal 标记；生产 shader 跳过 normal sample/displacement，继续实际背景采样、albedo、tint、coverage 与 overbright。本合同沿用本引擎已有的 canonical 无 normal 语义，不定义新的位移单位或公式。官方省略/null 的同外观结果支持可选输入等价。有效 normal 的横向位移另见[普通混合对照](runtime-evidence-current.md#particle-refraction-normal-2860569355)。

验收在真实 Catalog→Planner/AssetGraph 检查省略、null、空值和资源改名的等价，以及显式正常/缺失 normal 与健康后继；复用原无 normal/有效 normal 的生产 Metal 像素门，再核原作者两个活动资产的实际纹理、实例、目标、command buffer 与最终捕获。不能以准备放行或全景非黑代替实际编码，不以本修复授全部材质输入、Rope/动画组合或逐输入像素贡献。

<a id="particle-refraction-normal-blend"></a>
### REFRACT 的普通混合

有效 REFRACT 的 `normal` 直接替换 RGB，使用原背景、normal 位移与非预乘 albedo/tint。粒子 alpha 控制位移，贴图与粒子 alpha 均不缩放替换 RGB。本机先从位移点的预乘背景还原颜色，零 alpha 不供色。PSO 再按当前目标 alpha 关联替换色并保留目标覆盖率，使透明目标仍满足原存储合同。半透明与加法保持原单次预乘覆盖。只在有需求时准备替换变体，共用现有资源和背景快照。

验收用不同色背景及贴图与粒子 alpha 独立变化核 RGB、正负位移、缺 normal、改名与紧邻合法 blend。原包须实际恢复波纹，另验独立旧 blend 作者。官版桌面只核 RGB，本机预乘存储由实际 Metal 验证。Composition 官版内部 alpha 和取样域另行资格。

<a id="ambient-particle-lighting"></a>
### 无直接灯的粒子 ambient 消费

原 native REFRACT 材质在零直接灯场景消费 `LIGHTING=1` 的真实 authored ambient，实际接通范围归[运行证据](runtime-evidence-current.md#particle-lighting-control)。官方模块的零计数组装分支初始化并返回零光照增量；stock fragment 在此之外将 albedo/tint 的 RGB 乘 `g_LightAmbientColor`，经原 HDR CombineLighting 后再消费背景与 overbright。这是有条件的 source 语义，不授作者实际宏计数或完整官方像素一致性。

- **准备与唯一来源**：原 ParticleRuntime/AssetGraph 在冷准备确认原 ortho ambient 供货可用，并按既有 typed light 声明及 General 类别判断是否存在可能的直接灯消费者，给原 RefractionPlanner 传最小能力事实。显隐、位置与强度的当前零值不能当成永远无灯；已有动态直接灯需求仍局部不支持，不先模拟再逐帧拒绘。Plan/Declaration/Binding 保留真实 lighting operation，替换本范围的整项 LIGHTING 拒绝，不改变其他材质输入的消费资格。
- **帧链与数学**：原 OrderedLayerEncoding 从同帧 LightSnapshot 只交付 authoredShaderLighting 的 ambient 和原 scene HDR 状态，沿原 particle uniform/fragment 消费；不使用 ortho native receiver 的 ambient/sky 换位或 image 的 ambient+sky 公式。RGB 调制与 HDR 饱和发生在原背景相乘、overbright 和最终 coverage/PMA 合成之前；alpha、几何、normal 解码、REFRACT 位移与背景快照继续原 consumer。未启用 lighting 的路径保原运算，不新增灯表、状态/时钟、资源/输出 owner、PSO cache 或普通帧场景扫描。
- **无贡献输入**：`DOUBLESIDEDLIGHTING=0/1` 只改变直接光 PBR 的正反面响应。未启 `LIGHTING` 时该分支不存在；上述 ambient-only L1 的零计数模块也不调用该 PBR。原 Planner 对这些既有可消费材质承接双面无操作输入，退出整项拒绝；L1 的直接灯/ambient 资格仍由原 lighting 条件独立决定。复用现 Plan/Binding，不另存双面位或增加 fragment 分支；normal 解码与 raster cull 分属原消费者，不能借该 combo 修改几何剔除或 REFRACT 位移。
- **失败与退出**：已识别的直接灯需求、shadow/cookie和既有无效资源保持原最小资产失败；CUTOUT 另由[原覆盖运算](#cutout-particle-coverage)消费，双面位不为未支持的 lighting 组合授能力。未typed的tube仍沿原light降级，本批不新解析或以typed空数组授全部raw灯覆盖。不将未解释的材质输入当零灯，不用 unlit 替代未消费 operation。冷环境事实随原 descriptor/准备重建，帧输入只读已确定类型。将来接入完整直接光照时，由原材质/LightSnapshot 消费者替换该能力限制，不保并行 ambient owner 或额外回退链。

验收先扩原 Plan/AssetGraph 与生产 Metal 门：零灯的 L1 与 L0、非白 ambient、RGB/alpha、HDR/overbright次序、normal与背景、资源/ID改名、合法数值变体，以及可热显隐直接灯、未知combo/坏资源和健康peer反例。双面输入在 L1 保缺 ambient/潜在直接灯拒绝，在 L0 保真实 unlit 输出，raster cull 始终独立；无 frame/shader 变更时复用同身份像素门，仅补冷准备与真实输出。先用未改参数的真实作者核自然 accepted-birth、非零 batch、实际 normal/background→main/seal/GPU与可见贡献，再用独立作者及既有L0内容防回退。最小交付以真实可见粒子恢复为准；只有准备放行、无出生、错误normal/颜色或无最终贡献时回到首错，不扩大光照、提高音频或调作者参数补图。

<a id="cutout-particle-coverage"></a>
### REFRACT 的 CUTOUT 覆盖

原 native REFRACT 的 CUTOUT 是 soft alpha 运算，不是几何 discard、raster cull 或 A2C。stock fragment 在 lighting、背景采样及 overbright 之后，用原 texture-format 转换后的 albedo alpha × particle alpha 计算 smoothstep(start,end,alpha) × opacity，再按原 blend 输出。normal 位移仍使用 CUTOUT 前的 particle alpha，不能让覆盖阈值改变位移或先饱和输入。

- 原 Planner 只在 `CUTOUT=1` 准备默认 `.1/.2/1` 或显式静态 start/end/opacity，沿 Declaration→AssetGraph→TextureLoader→Binding 传一个可选 Float 三元值；缺省/0 沿原 coverage 表达式，不解析或验证已识别 inactive cutout 常量的值。已知 key、active static/scalar/finite 在原入口单次遍历，退出旧三轮重复验证及 CUTOUT combo/静态常量整项拒绝；不另建材质状态、动态 store、资源或输出 owner。
- 当前消费范围为有限、严格有序的 Float 阈值及 0…1 opacity，使结果属于原 coverage/PMA 域。阈值不受编辑器 0…1 范围限制；等宽、逆序及域外 alpha 行为尚未资格，在冷准备只拒该资产，不加 epsilon、硬 step、范围钳制或 shader 内重验。active 动态参数、pass 级 user 输入、普通非 REFRACT CUTOUT、未知 combo、直接光和坏资源仍分别保原边界；不能把聚合的 user 需求假定为 inactive 参数。
- 原 drawRefraction 将现有材质参数、UV scales、ambient 与 cutout 合为一个栈上 fragment uniform 包，一次绑定；旧分散 fragment buffer 参数同批退出，既有几何/纹理路径不变。共享 vertex 的旧 tint 提前饱和 alpha，另传原颜色/raw alpha 给 active CUTOUT，避免丢失超过 1 的输入或零 alpha 下负阈值所需的颜色；旧 tint、normal、L0/A2C 运算保持，插值成本不预称为零。只有启 CUTOUT 的 fragment 消费新 smoothstep coverage，RGB 最后乘一次 coverage 并输出一次 PMA；不增加 PSO、逐粒 CPU 运算、热解析或临时数组分配。

验证扩真实冷准备与原生产 Metal 像素门：省略/显式默认、资源/ID改名、另一组有序阈值与 opacity、阈值上下/中点、raw alpha 超过 1、LA8/normal/背景、HDR/overbright/PMA 次序及 inactive 常量。保坏类型/动态值、未资格阈值、潜在灯和健康 peer。因 fragment ABI 改变，本批补原 L0、ambient 与双面实际作者；主作者按实际获准推进、自然出生和非零 batch 选窗，核真实 color/normal/background→main/seal/GPU及画面。供货、覆盖或位置先失败时回到首错，不调作者参数补图；不由此授四层逐输入像素、完整光照或官方一致性。

<a id="rope-span-uv"></a>
### Rope 同位采样的逐段 UV

原 RopePlan 的几何采样仍只为同位连续样本保留首个 Sample，位置、join、宽度、size/color/alpha 不重建。纹理端点属于各个可画 span：合并几何位置时，保该节点第一次到达的 incoming UV，并将 outgoing UV 推进到最后一个同位采样；原 instance 读取 tail.outgoing 与 head.incoming。退出“几何节点只有一个 UV、强迫相邻段共值”的旧职责，不改原 `uvPositions` 的 index/lifetime、fallback、scale 或 scrolling 规则。只在同一临时 samples 中加一个端值，复用原 per-segment frame/range；无新数组、持久状态、shader/ABI、资源或 owner。

固定官方的非对称静态输入在显式 subdivision0、uvsmoothing=false 下，以六点及同向斜线作正控，在两个重复节点见 UV 跳变、连续节点保持连续；低画幅读口失败保留，高画幅仅修采集资格，所有 oracle/阈值保持。此证据支持逐 span 端值供货，不决定默认 UV 模式、曲线或内部出生/去重阶段。subdivision>0 仍完整生成原曲线样本，再沿原距离阈值合并；不能先按原节点位置跳过整条 span。RopeTrail 沿原历史消费者。

验收直接调用原 Plan，覆盖首/中/末重复、无重复/全同位、改名/按ID排序、重复记录不同外观及健康 peer；保首个 Sample 外观，核 index、寿命/fallback、缩放/scrolling 和细分非零曲线。实际 App 用同一色带控制核供货到原 GPU，再核原作者与另一活动 Rope 场景；未取得的完整轨迹、默认/曲线官版一致性及 A2C 分别保界。

<a id="rope-source"></a>
### 单图 Rope 纹理

原 `SceneParticleChildTemplateSupport.loadTexture` 为 root/child 统一准备整图纹理：TEX 只要求实际单 image；SpriteFrame 索引由 TEX 解析入口一次验证，内部不重扫帧表。尺寸、解码和上传由原 loader 检查。General flags、renderer flags、animationmode、sequencemultiplier 与 Rope UV 选项不授纹理播放许可；UV 和几何继续由原 RopePlan 消费。

Rope 整图路径不构造 SpriteAnimation，只传整图消费选择和原纹理/采样结果；不传完整 definition、RopePlan 或 profile 证明。Sprite/SpriteTrail 保原帧选择；RopeTrail、多 image 和 refraction 的独立资源/帧边界保持。资源失败只使受影响 root/child-template 不可用，不补默认纹理，不新增状态、时钟或资源 owner。

固定官方 2.8.0.42 的两场 A/B 在 General0/renderer0 与 General7/renderer1 下，省略动画字段和 randomframe/111 的 Rope 都呈整张四色图集，Sprite 正控与移动时钟/peer 同场成立。此为单图整张 source 的定性依据，不授多 image、RopeTrail、精确官方 RGBA 或完整 UV 公式；原生与 App 的实际消费资格见[运行证据](runtime-evidence-current.md)。

<a id="material-state"></a>
### 材质状态与几何职责

材质状态由实际 shader 输入、颜色输出与附件需求决定，与几何及相机选择分开。A2C 和共同 depth 不以 screen Sprite、noCull 或 renderer 名称授予执行许可；各原 owner 消费自己的准备结果，不新增能力 token、管线、时钟或持久状态。

- 原 RenderStateCompiler 消费已解析的 blend/cull/depth/alpha 和已支持材质输入。A2C 复用共享 `particleVertex`，仅采用 straight tint、硬件 coverage 与 alpha-to-one；Sprite、SpriteTrail、Rope 和 RopeTrail 的几何、实例与 joins 仍由各自原计划产生。材质不重验 renderer 字段；Rope 的完整计划检查与普通 Sprite/SpriteTrail 当前缺省/诊断行为不能混作一种全局资格。
- A2C 不额外禁止 cull 或 depth。共同 depth 接受已有普通颜色材质输入或已准备 REFRACT 事实，实际 PSO、nearest pass、depth clear/store/load 与 writer/readonly 次序继续由原 GPU owner 消费。REFRACT planner 当前无 depth-write 语义，不在下游重复其入口判断；A2C+REFRACT 没有组合 fragment/PSO，不能据此伪造执行。
- `usesSceneCamera` 保留原选择及 CameraFrame 的 native projection/Y 转换语义；它不再充当材质或深度的播放许可。新增 Rope coverage 不能令普通 Rope 自动切 native 相机。
- overbright 是准备期静态 scalar，转为后端 Float 后须有限且非负。shader 直接消费其数值，不能以 64 或编辑器范围作额外播放上限；未实现的 combo、user sampler/value、自定义 shader 或多 pass 仍需真实消费者，不能因状态已准备就宣称其输入生效。
- 保留原 sampleCount1、像素格式和深度附件变体，不为 A2C 名称新增 MSAA/resolve 生命周期。PSO 或资源失败只使实际受影响 batch 不可用，健康 peer 继续；不得退回另一个 blend 来冒称 coverage。单采样硬件结果不证明平滑抗锯齿或官方 coverage mask 一致。

验收使用原 Runtime 的 live-particle Rope 与独立 RopeTrail history，读取实际 joins/vertex、硬件 alpha 正反例、非方纹理、急转/合并段、镜像/cull、共同深度 writer/readonly、缺 PSO 和健康后继；overbright65 用低输入颜色避免饱和掩盖。真实作者以活动 pointer 轨迹期间的 batch、纹理、捕获身份和终端画面取证，静止帧或默认隐藏 child 的准备诊断不能证明轨迹恢复。若原几何、输入或资源出现下一断点，沿实际 owner 修正或登记，不继续追加模式名单。

<a id="native-particle-main-depth"></a>
### 原生透视粒子读取主画布深度

原生透视 Sprite 已沿 SceneCamera 投影。普通颜色批次按材质开启测试且关闭写入时，在最终主画布绘制位置借用同一 pass、同 command buffer 已由透视模型写入的 reverse-Z 深度。沿原层变换、实例缓冲、透明混合和唯一颜色输出，用已有反向 VP 与只读 `.greaterEqual`。当前深度域保留写入的投影事实，若已混入正交模型写入、没有同域写入或附件不可用，沿原无深度批次。借用只 load，不分配、清空、复制或延后帧。

原生透视根层的普通 translucent Sprite 以作者 `depthtest` 决定读取，`depthwrite` 不产生写入。冷准备只给无附着、无 child 系统且全部有效 renderer 为普通 Sprite 的根层带出此意图。原上传步骤按当前相机与实际目标把写入投影为关闭，后续排序、预约与编码消费同一批次状态。能测试时借既有只读深度，测试关闭或还没有可共用的深度时直接画颜色。原私有正向路径继续用于其他投影、同根有正交实体写入的场景、组、混合 renderer、child、折射、加色和 coverage 的实际写入。

冷准备登记可达的无附件与 `depth32Float` PSO，缺可选变体时保必需绘制。只读加色粒子按 [Composition 背景截点](effect-execution-coverage.md#perspective-composition-prefix) 调度。实际绘制写入建立深度有效性。合格批次复用 MainPass，免私有深度预约、清除和读写。

验收分别单关 `depthtest` 和 `depthwrite`，保原粒子材质、同一固定相机和几何。在前置实体覆盖及外区验证读入，在实际后绘粒子和普通透视实体验证无新增遮挡。改名、无匹配深度、异相机、组、加色写入和具名画布截点保实际边界。原包需验证后继画布读取与文字合成，独立作者须保实际私有深度或同域只读的原行为。纹理覆盖阈值及其他粒子写入仍需各自证据。

<a id="playback"></a>
## 播放命令

`play/pause/stop/isPlaying/emitParticles` 沿原 typed handle 和 PlaybackState 生效。pause 保实例，stop 清活动播放和出生。显式 emit 取当前回调前缀的值及已提交祖先链。粒子或祖先缺索引且 world Float 变换偏离作者值时，沿原描述补本次快照的 seed，交原 typed resolver 和 world resolver。相等则保静态帧。固定点重建复用调用上下文，晚写不修改已捕获位置，渲染重试不重放出生。沿既有空间资格验证两次调用位置及尾部再写反例。

新 Surface、重建、暂停恢复、退出与失败延续原 Scene clock/transaction，不另建粒子播放时钟。完整 Sound/media/UI 不属于 Particle 的输出 owner。

<a id="limits"></a>
## 当前缺口与回归

双端点的弧向/周期重启、更多 CP 约束、Position Around 的 Mirror、复杂 nested/event/非均匀 child 变换与部分 Vortex/HSV/Position Around 数值仍有未实现或待资格边界。不能以非空 batch 或门禁通过替代方向、数量、相位和官方像素。普通粒子额外 combo 与用户材质输入尚无通用 shader 执行合同；通过 raster 状态编译不能作为这些输入已被消费的证据。

最近行为入口：[真实 CPU runtime](../../../script/tests/scene/test_scene_particle_runtime.py)、[事务](../../../script/tests/scene/test_scene_particle_playback_transaction.py)、[Metal renderer](../../../script/tests/scene/test_scene_particle_rendering.py)、[App 生命周期](../../../script/tests/scene/test_scene_particle_playback_integration.py)。具体下一资格见[队列](../roadmap/scene-open-breakpoint-queue.md)。
