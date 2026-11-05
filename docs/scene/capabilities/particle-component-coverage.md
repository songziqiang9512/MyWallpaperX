# Particle 当前组件与执行边界

<!-- document-role: current-state -->

<a id="simulation"></a>
## 准备、模拟与空间

DefinitionParser 保作者顺序、已有字段解析与未知组件诊断；原组件 owner 准备 emitter/initializer/operator、control point、child 和 renderer 计划。每屏 PlaybackState 拥有模拟器、RNG、活动实例和轨迹历史，Session cadence 推进一次；View/GPU 重试不重新出生、执行事件或模拟。

root local/world、layer/world/camera、attachment 与 child space 分别保身份。共享 canonical world/camera 供 emission 和 draw 使用；固定线性基的祖先 origin 平移沿同一 reference/current 链接入 root、child 和生产 model。Pointer/CP 先在当前局部空间取值，实际出生与位置操作各转换一次，不能把 reference 指针再次当新生位置加偏移；职责见[祖先平移合同](../architecture/runtime-architecture.md#particle-world-translation)。不逐粒子重解层级或用 abs/clamp 猜坐标。

执行按准备好的作者顺序处理发射、初始化、操作、运动/死亡和 child，再产实例值与 draw batch。prewarm 执行真实模拟，不只移动 clock。snapshot/restore 属于原 CPU state，不复制 GPU 上传状态。

源码：[Runtime](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRuntime.swift)、[PlaybackState](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticlePlaybackState.swift)。

<a id="prewarm-work"></a>
### 预热工作预算

预热沿原 Simulator 固定步进、RNG、出生/死亡和 SnapshotRecorder 执行。首240步与frame-created child的既有步数范围保持；root扩展仍最多3,600步、四百万加权工作单位。扩展按每个实际完成步流式计价：进入初始化的出生次数承接原initializer权重，原normalizedLives的死亡压缩前数量承接常规/算子权重，Boids保实际数量平方的保守项；不把最大容量或每个存量粒子都当作每步重新初始化。

本切片只调整原warmUp，Trail历史仍按实际处理数量乘原historyCapacity保守计价，不改Recorder、不跳历史或新增普通帧计数/持久预算。每步完整执行后计价，越预算便停止下一步；最多多一个完整步的估价，不为精确截断增加快照事务或回滚。原事件每步排空、部分末步、模拟rate与后续live随机序列均保留。缺省/无效时长、容量和资源的入口职责不扩张。

starttime请求的wall-step序列与实际simulationTime分开：实例rate仍在原step内应用一次，验收按相同请求步序列与rate的正常模拟对照，不能强制simulationTime等于starttime。对稀疏大容量、密集/短命/失败出生、Boids、无粒子和Trail历史分别核实际状态、预算退出、初始画面与准备成本；预算耗尽保真实部分结果和诊断，不承诺所有作者都完成长预热。官方starttime单位与本地成本估计不是同一资格。

<a id="components"></a>
## 当前组件面

| 组件 | 已有执行路径 | 限制 |
|---|---|---|
| Emitters | 已准入的有序发射/连续与一次性出生，Sphere/Box 原计划、[速度数值](#emitter-speed)及 Sphere [方向选择](#emitter-sign) | flags、空间、audio、CP 和 instance override 必须满足该计划，不能从组件名推全参数支持 |
| Initializers | 位置、速度、旋转、尺寸、寿命、颜色、sequence 等 typed writer | 后写者及 General override 保作者顺序；未知字段只影响相关组件；HSV/Mirror/Position Around 等仍有未资格组合 |
| Operators | movement、gravity/力、颜色/alpha/size/旋转、noise、Remap、Vortex、Plane Collision 等原计划 | 不支持操作不假装执行；与 child、CP、世界空间和 lifecycle blend 分别限定 |
| Control Points | 0…7 typed identity、已接入的静态/动态位置与 emitter/force consumer | 按 authored ID 而非数组位置；CP0/system origin 与其他 world source 不混用，未知 flags/angles/parent 不猜 |
| Instance overrides | 已有颜色、发射、速度、播放及 typed 动态输入 | 新生 writer 与存量粒子不同；不以新属性自动改写既有粒子 |

<a id="control-point-position"></a>
### 控制点位置的取值职责

普通控制点的位置按当前 typed 动态值、instance override、definition offset 的顺序取一个值；前两者覆盖 definition 位置，不与它相加。Emitter、Force 和位置 initializer 使用同一取值语义。组件自己的 origin/offset 仍在取得控制点之后叠加，emitter 的 origin 继续按原角度旋转，不能与 definition 的默认位置混为一项。

鼠标绑定的 definition offset 是指针偏移，仍叠加当前有效指针；缺指针的真实消费者局部不可用，不回到系统原点。位置选择与空间转换分开：world 点经当前 `SceneParticleControlPointFrame` 的同一逆矩阵转到实际模拟空间，child 再复合原 origin/scale。冷计划和 typed 帧继续拥有字段、identity 与当前供货；没有位置 registry、缓存、第二时钟或每粒子的元数据校验。CP parent/angles 的未资格语义不能由位置覆盖实验外推。

Emitter frame 与 Simulator 共享同一纯位置选择；被普通位置覆盖替代的数值 offset 不参与 emitter offset 幅度检查。组件的 RNG、出生顺序和显式发射事务仍由原 owner 执行。验收用真实 Parser/Simulator 的默认位置、静态与动态覆盖、组件额外 offset、Around 共用端点及缺指针反例，再核 Runtime/Metal 的实际位置。官方局部静态 CP 对照中，definition=(16,24)、instance=(48,0) 得到(48,0)，独立无 override 的正控仍为(16,24)；此证据不授全部空间或完整粒子效果一致。

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

speedmin/speedmax 是原发射方向上的有符号数值；缺少的每个端点独立取0。有限端点在原冷 SpawnPlan 入口准备有序区间，保负号与原值，不取绝对值、不夹到0或人为幅度上限。区间正规化不抽样；原 RNG 沿作者出生顺序取值，保每次出生的 seed/抽样协议，再经 `relative/length × speed` 消费；负值允许沿相对方向向内，作者逆序端点与其有序表达等价。

初始速度继续按原initializer顺序、CP frame、instance multiplier与world转换处理。最终出生状态在这些运算之后才检查正寿命及Float/GPU可表示性，有限Double不等于最终安全结果；失败局部丢弃该新生，保健康emitter和既有粒子。显式exact-n命令继续用原候选state事务回滚，不增加校验器、重试、许可、缓存或第二模拟器。Directions/sign、schedule、audio与空间仍由各原消费者的实际合同约束。

验收经过真实Parser→冷计划→constructor→state/事件及Runtime→生产vertex/Metal：固定一轴/半径的负速度向内、正/逆序与单端缺省、改名、1e6以上但最终Float合法的输入；非有限端点、实际Float溢出及健康peer分别核。作者沿相同输入与有效rate/音频分支核accepted birth、目标batch与最终捕获，汇总PASS不代出生或draw；未做官方同条件对照时只声明本引擎已证数值合同。

<a id="emitter-sign"></a>
### 发射方向字段

Sphere 的 sign 在原冷 SpawnPlan 逐分量向零取整，零保持双侧，非零的符号选择该轴正/负侧；其幅度不乘入距离或速度。Definition 保作者有限数值及原有形状诊断，去除只准-1/0/1的数值枚举许可；不改变 Directions、半径分布、RNG、CP、instance override、world 转换或最终新生数值检查，不新增 owner、状态、缓存或普通帧工作。两个同源雨粒子的整数10因此可进入既有constructor；小数0.5不被误作强制正侧。

Box 不消费 sign，解析入口把该无关字段投影为 nil，不因其合法、错型或非有限内容拒绝有效 Box；原 root 字典及既有组件来源记录不改。Directions、sign 与 duration 在原 parseEmitter 各解析一次，复用已解析结果判 malformed；仅 Box 忽略 sign，Sphere、LayerImage 及未知 kind 的字段和资格保持。原 SpawnPlan 的 Sphere 分支才准备 sign 与轴 mask，其他 shape 写中性值；不增加字段、owner、fallback 或普通帧工作。验收核 Box 缺省/零/非单位/小数/垃圾 sign 的相同实际出生、事件、RNG 和 Metal 输出，并用带有效 emission map 的 LayerImage、Sphere 坏输入和无关健康 peer 保反例。当前没有该门独立活动拒绝的作者资格，不宣称恢复某个 Workshop 作者。

此分量语义依据固定官方客户端的合法、非单位、小数及跨轴静止几何控制；取整后取符号与等价阈值实现的内部形式未区分。手工原生JPEG中心读数不是RGB阈值分析、精确计数、分布或全参数官方一致证明，具体运行范围见[证据](runtime-evidence-current.md)。

验收在真实Parser→冷计划→constructor中核整数/小数、各轴、缺省、改名及非有限反例，保健康peer、RNG/事务；用原Runtime→生产vertex/Metal读回几何和像素，并复测原作者与独立邻例的birth→目标batch→main/seal/GPU捕获。未资格组合继续按实际消费者的最小失败单元处理，不能再扩一个数值白名单。

<a id="periodic-emission"></a>
### 周期发射的数量合同

原 DefinitionParser → SpawnPlan → EmitterState → Simulator 承接周期数量。`maxtoemitperperiod` 只解析一次并进入原周期计划；缺省、0与负数沿无上限路径，正数由原自然发射消费者逐活动窗执行，不能因存在该字段拒绝整个发射器。当前 `count` 同时缩放发射率与周期上限，有效上限取正数乘积向下取整，再减去本周期已消费的自然请求数量；中途更新 `count` 不重置已用数量。每个 emitter 只在原 State 增加一个计数值，进入新活动窗及既有 rearm 清零；不保存倍率副本或第二份剩余额度，不建许可表、调度器或缓存。

沿原窗口时钟/RNG推进，触顶只抑制本窗额外自然请求，不提前进入间隔，不停止小数余量积分；余量跨间隔与周期保留。跨多个窗的单步须在原循环内逐窗限额和重置，不能先合并所有活动秒再限一次。无上限仍保原活动秒聚合后一次积分的运算顺序。准备期的字段/时间区间检查、原1024窗口工作预算与非有限 accumulator 的局部失败保持；此消费者不借 cap 开放其他尚无消费者的 flags/audio/burst/duration 组合。

自然出生仍按作者 emitter 顺序，经过原系统容量裁剪与 constructor；额度按原 maximumParticleCount 有界的调度请求消费是本引擎当前策略，容量饱和时的官方计费点尚未确定。官方短命满槽对照中，无上限也会延后出生，不能据它选择计费公式；该通用调度差异独立留在[队列](../roadmap/scene-open-breakpoint-queue.md)。不为未证组合新增播放许可或改动已可用路径。显式 exact-n 沿原调用点/事务及容量处理，不扣自然额度，不把 cap guard 搬到整个 preparedPlaybackWork；早期显式调用对自然相位的官方差异另列队列，不以晚命令仍贡献证明完整交互一致。

状态随原 emitter 数组的值快照、候选回滚、prewarm→live 和 rearm 生命周期走；GPU重试不重发。验收使用真实 Parser/Simulator 的固定两周期、倍率小数与热更新、余量、改名/相邻无上限、独立 emitter、随机窗/跨窗步、快照/回滚及播放生命周期，并经原 Runtime→生产 Metal 核实际几何/像素和作者目标 batch→main/seal/GPU。官方手工图只证明已测输入的可见出生位置与控制时钟，不是内部人口、RGB或所有参数一致证明。

<a id="operators"></a>
## 需要保留的数值边界

- Remap 复用原 `SceneParticleRemapValue`：有界 velocity/simplex 与 scalar-speed/fbm 路径分别准备；显式输入通道、其他操作和生命周期 blends 仍缺消费者。官方常量输出控制中，省略 operation 与 Multiply 表现相近，显式 `remap` 与 Assign 表现相近；这不是默认 Assign 的依据。三相位与预热控制只取得定性亮度、冻结稳定性和运动钟偏移，尚不能确定 sine 公式、范围缺省、处理顺序及 Remap 输入时钟。原始输入和独审保存在 `.artifacts/scene-goal-generic-consumer-followup-20261105`；新消费者遵守[标量 Remap 合同](../architecture/runtime-architecture.md#particle-scalar-remap)，不以猜测公式替换字段白名单。
- Vortex classic 与 v2 有不同 flags/轴/CP/audio 资格。当前 v2 强度与保持半径属于项目有界响应，不是官方通用公式；缩放、外生与长时数值不能由名称或短轨迹外推。
- Plane Collision 消费已准备平面及响应；wallpaper Collision Bounds 仍没有可接受的通用缩放/外生行为合同，不能拿 emitter 范围或自然 affine 反弹代替。
- Color/normalized color 的来源、writer 优先级及新生/存量作用不同，未与官方定标的算法保持明确限制；不能靠调 gain、速度或 RNG 拟合样本。
- 小数 Position Around Count 保留作者数值，经实际数学消费，不能改全局 integer parser 或取整。未资格的轴、Mirror、periodic 与空间组合不顺带放行。

源码：[Remap](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRemapValue.swift)、[Vortex](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleVortex.swift)、[Plane Collision](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleCollisionPlane.swift)。

<a id="children"></a>
## Child 与事件

原 ChildRuntime 处理已准入的 static、spawn、natural-death 和 follow child 及其局部时间。child 不是克隆父 RNG/clock 的另一个全局系统；父末帧/自然死亡与显式 stop/destroy 分开，不能擅自给未接入的碰撞/delete 事件生成 child。

当前 strict 计划最多 depth two，每深度系统数和粒子容量分别受原 64/65,536 预算约束；static Rope 另有 template/扩张预算。预算是当前实现限制，不能冒充所有作者格式的永久语义。

hidden/dormant child 的实例和潜在 renderer 需求保持。已提交销毁 root 时，由实际归属退休其 CPU root 与独占 ChildRuntime；健康 root 的 RNG、clock 和状态不变。冻结 DrawBatch 继续是值，不被退休操作追写。

<a id="rendering"></a>
## Renderer、材质与 GPU

Sprite、SpriteTrail、RopeTrail、screen-displacement ribbon、refraction 与 depth 各复用原几何/材质/target owner。尺寸、atlas、TEX sprite frame、非方纹理比例与采样用途保来源；Rope 单图 atlas 的整张 source 与 Sprite 帧不是同一语义。

composition 成员使用 nearest group 的原 MainPass；canonical camera/viewport 保留几何和 Trail 度量，最终 XY 与 REFRACT 位移才转换到目标。两行 raster uniform 位于原字段之后（CPU/MSL stride304），Z/W 保原相机深度；depth 与背景快照消费真实 attachment。没有逐粒子 CPU 转换、第二相机或按效果名准入。完整职责和仿射输入合同见[组合层栅格](effect-execution-coverage.md#particle-subtree-raster)。

CPU batch 不持可写 instance buffer。原 ParticleMetalPipeline 按 root/child-template key 拥有上传 slot，形成 frame-local PreparedBatch；prepare/upload/draw/arm/cancel 由同一 GPU owner 管理。在途 buffer 与 depth/refraction pin 随真实 command 终态释放。

Surface 采用新 topology 才退出死 root/child GPU key；重建构造前过滤 committed 死 root。未提交取消释放其 slot，已提交不能用 CPU 回滚撤销。hidden 不等于退休，peer key 可复用。

材质剔除由原 Metal raster 状态消费：`normal` 编译为 back-cull，`noCull` 保双面，共用已有三角绕序与 vertex。其资格不依赖 renderer 名称或 REFRACT 组合，不改变相机、basis、尺寸与变换、纹理 UV、snapshot 或输出 owner。镜像是否翻面按实际几何投影决定，不改 front-facing 补偿作者变换。

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

<a id="playback"></a>
## 播放命令

`play/pause/stop/isPlaying/emitParticles` 沿原 typed handle 和 PlaybackState 生效。pause 保实例，stop 清其活动播放/出生；显式 emit 的参数与 transform 取调用点，不能被稍后的 callback 返回值追改。同 cadence 的命令、GPU deferred 和缺 drawable 不得重放出生。

新 Surface、重建、暂停恢复、退出与失败延续原 Scene clock/transaction，不另建粒子播放时钟。完整 Sound/media/UI 不属于 Particle 的输出 owner。

<a id="limits"></a>
## 当前缺口与回归

双端点的弧向/周期重启、更多 CP 约束、Position Around 的 Mirror、复杂 nested/event/非均匀 child 变换、Collision Bounds 与部分 Vortex/HSV/Position Around 数值仍有未实现或待资格边界。不能以非空 batch 或门禁通过替代方向、数量、相位和官方像素。普通粒子额外 combo 与用户材质输入尚无通用 shader 执行合同；通过 raster 状态编译不能作为这些输入已被消费的证据。

最近行为入口：[真实 CPU runtime](../../../script/tests/test_scene_particle_runtime.py)、[事务](../../../script/tests/test_scene_particle_playback_transaction.py)、[Metal renderer](../../../script/tests/test_scene_particle_rendering.py)、[App 生命周期](../../../script/tests/test_scene_particle_playback_integration.py)。具体下一资格见[队列](../roadmap/scene-open-breakpoint-queue.md)。
