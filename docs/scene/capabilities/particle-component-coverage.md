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

初始 launch 在原 Host preparation queue 的资源/Program join 后，为主线程冻结的每个目标 Surface 构造独占 PlaybackState/Runtime，完整执行作者 starttime 的原步序列，再随 PreparedLaunch 一次移交。Session 只安装实例与 GPU pipeline，不共享 mutable Simulator、不重新冷构造或恢复种子。原请求 token 在完整步之间响应取消，未完成结果丢弃，原队列 fence 等待退出；不迁移 VM、Clock 或最终输出。

LayerImage 继续使用原 compiler：原 base-image owner 将 provider 缺 outcome 时的既有 inline 重试前移，保存最终 loaded/failed outcome，Surface 与 compiler 采用同一 texture/animation。正常已加载输入不重复读取，最终失败不增加第三次重试；deferred、视频及动态 source 继续原 provider 边界。

预热沿原固定步进、RNG、出生/死亡和 SnapshotRecorder，逐步排空历史事件，保部分末步和后续 live 随机序列；实例 rate 在原 step 内应用一次，simulationTime 不必等于 starttime 请求。完整初始 root 不计算虚拟权重，也不受3,600步/四百万工作单位限制。frame-created child 保持240步；后续同 Session display rebuild 仍有上述 root 步数/实际出生与死亡压缩前人口的加权上限，预算耗尽保部分状态及诊断，完整后台化归[开放队列](../roadmap/scene-open-breakpoint-queue.md)。入口无效时长、容量与资源边界不变。

验收核完整真实状态/RNG/事件/历史与 live handoff、多 Surface 独占、取消释放、真实初始画面和候选准备期间旧 Scene 输出。[运行证据](runtime-evidence-current.md)拥有当前结果；standalone 成本、直接 DEBUG Host 与物理多屏、daemon IPC、官方 starttime 全语义和逐帧流畅度分别设证明上限。

<a id="components"></a>
## 当前组件面

| 组件 | 已有执行路径 | 限制 |
|---|---|---|
| Emitters | 已准入的有序发射/连续与一次性出生，Sphere/Box 原计划、[速度数值](#emitter-speed)及 Sphere [方向选择](#emitter-sign) | flags、空间、audio、CP 和 instance override 必须满足该计划，不能从组件名推全参数支持 |
| Initializers | 位置、速度、旋转、尺寸、寿命、颜色、sequence 等 typed writer | 后写者及 General override 保作者顺序；未知字段只影响相关组件；HSV/Mirror/Position Around 等仍有未资格组合 |
| Operators | movement、gravity/力、颜色/alpha/size/旋转、noise、Remap、Vortex、Plane/[Sphere Collision](#sphere-collision)、[单点半径](#control-point-radius)与[双点搬移](#between-control-points)等原计划 | 不支持操作不假装执行；与 child、CP、世界空间和 lifecycle blend 分别限定 |
| Control Points | 0…7 typed identity、静态/动态位置及 emitter、initializer、force、约束消费者 | 按 authored ID 而非数组位置；CP0/system origin 与其他 world source 不混用，未知 flags/angles/parent 不猜 |
| Instance overrides | 已有颜色、发射、速度、播放及 typed 动态输入 | 新生 writer 与存量粒子不同；不以新属性自动改写既有粒子 |

<a id="control-point-position"></a>
### 控制点位置的取值职责

普通控制点的位置按当前 typed 动态值、instance override、definition offset 的顺序取一个值；前两者覆盖 definition 位置，不与它相加。Emitter、Force、位置 initializer 与距离约束使用同一取值语义。组件自己的 origin/offset 仍在取得控制点之后叠加，emitter 的 origin 继续按原角度旋转，不能与 definition 的默认位置混为一项。

鼠标绑定的 definition offset 是指针偏移，仍叠加当前有效指针；缺指针的真实消费者局部不可用，不回到系统原点。位置选择与空间转换分开：world 点经当前 `SceneParticleControlPointFrame` 的同一逆矩阵转到实际模拟空间，child 再复合原 origin/scale。冷计划和 typed 帧继续拥有字段、identity 与当前供货；没有位置 registry、缓存、第二时钟或每粒子的元数据校验。CP parent/angles 的未资格语义不能由位置覆盖实验外推。

Emitter frame 与 Simulator 共享同一纯位置选择；被普通位置覆盖替代的数值 offset 不参与 emitter offset 幅度检查。组件的 RNG、出生顺序和显式发射事务仍由原 owner 执行。验收用真实 Parser/Simulator 的默认位置、静态与动态覆盖、组件额外 offset、Around 共用端点及缺指针反例，再核 Runtime/Metal 的实际位置。官方局部静态 CP 对照中，definition=(16,24)、instance=(48,0) 得到(48,0)，独立无 override 的正控仍为(16,24)；此证据不授全部空间或完整粒子效果一致。

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

<a id="sphere-collision"></a>
### 静态球体碰撞的执行合同

Sphere沿原DefinitionParser一次准备显式local origin、radius及bouncefactor，typed plan进入原有序Simulator，不新增时钟、出生阶段、CP状态或GPU补正。缺省behavior采用已观察到的Bounce类响应，显式stock `slide`保切向响应；缺省数值、Stop/Delete和CP锁定位未资格，不猜默认或复制位义。CP333和无关附加字段不作为整操作许可，未消费选项不授完整能力。

独立实现采用当前粒子到球心的径向位置投影，以及现有Plane的法向冲量：只纠正球内非零径向位置，只改变入向法向速度；Slide的法向反弹为零。球外、出向速度及切向分量保留；零径向不猜方向。球心复用原positionReferenceOffset转换到粒子出生参考，原lifecycle blend按现有计划作用于结果，最终数值交原acceptsMotionResult接纳；坏输入或单粒子结果只影响本操作，健康后继保持。入口只校验所用数值和向量，不设幅度、flags组合或额外字段白名单；audio尚无Sphere响应消费者，保持局部不可用。

公开[碰撞合同](https://docs.wallpaperengine.io/en/scene/particles/component/operator.html#collision-operators)规定球形障碍、Origin/Radius与Bounce/Slide。官方有界输入支持缺省反弹类、factor相对响应及切向位移保留；严格时钟误差跨门，不能唯一确定首次法线、位置修正顺序、粒子尺寸裕量或精确公式。因此当前径向投影/冲量属于项目离散算法，未授官方数值一致；保原正步emit→有序operators，不为拟合截图增加出生零步或重排Movement。CP1与省略同位不能证明锁定位或CP供给，具体资格见[运行证据](runtime-evidence-current.md)。

验收核真实Parser/Simulator的几何、factor/slide、顺序、改名/无关metadata、球外/出向、坏数值/零径向及健康peer；再经原Runtime→生产Metal核可定位几何与像素，复测真实作者及独立邻例并保Plane回归。实际接触及最终贡献未到达时不得以识别/批次数宣称恢复；更复杂world/child、动态CP、连续碰撞和死亡事件仍需独立资格。

<a id="operators"></a>
## 需要保留的数值边界

- Remap 仍由原 `SceneParticleRemapValue` 准备 velocity/simplex 与 scalar-speed/FBM 两条有界计划；真实input selector/range、其他输出/操作及外层lifecycle blend尚缺完整消费者。独立静态范围、晚EventDeath实例与sine正控的当前资格见[运行证据](runtime-evidence-current.md)；场景对齐候选类不等于所有时钟/预热/rate行为已定，sine及作者缺省参数仍未资格。新实现沿[标量Remap合同](../architecture/runtime-architecture.md#particle-scalar-remap)替换两份平行可选计划，保原noise/RNG行为；不能用猜公式或新增字段组合白名单补第三路径。
- Vortex classic 与 v2 有不同 flags/轴/CP/audio 资格。当前 v2 强度与保持半径属于项目有界响应，不是官方通用公式；缩放、外生与长时数值不能由名称或短轨迹外推。
- Plane Collision消费原准备平面；静态Sphere的范围由[球体合同](#sphere-collision)维护。wallpaper Collision Bounds仍缺实际边界供货和缺省响应资格，不能拿emitter范围或自然affine反弹代替。
- Color/normalized color 的来源、writer 优先级及新生/存量作用不同，未与官方定标的算法保持明确限制；不能靠调 gain、速度或 RNG 拟合样本。
- 小数 Position Around Count 保留作者数值，经实际数学消费，不能改全局 integer parser 或取整。未资格的轴、Mirror、periodic 与空间组合不顺带放行。

源码：[Remap](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRemapValue.swift)、[Vortex](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleVortex.swift)、[Plane Collision](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleCollisionPlane.swift)、[Sphere Plan](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleCollisionSphere.swift)、[碰撞消费](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulator+Collision.swift)。

<a id="children"></a>
## Child 与事件

原 ChildRuntime 处理已准入的 static、spawn、natural-death 和 follow child 及其局部时间。child 不是克隆父 RNG/clock 的另一个全局系统；父末帧/自然死亡与显式 stop/destroy 分开，不能擅自给未接入的碰撞/delete 事件生成 child。

当前 strict 计划最多 depth two，每深度系统数和粒子容量分别受原 64/65,536 预算约束；static Rope 另有 template/扩张预算。预算是当前实现限制，不能冒充所有作者格式的永久语义。

hidden/dormant child 的实例和潜在 renderer 需求保持。已提交销毁 root 时，由实际归属退休其 CPU root 与独占 ChildRuntime；健康 root 的 RNG、clock 和状态不变。冻结 DrawBatch 继续是值，不被退休操作追写。

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

Sprite、SpriteTrail、RopeTrail、screen-displacement ribbon、refraction 与 depth 各复用原几何/材质/target owner。尺寸、atlas、TEX sprite frame、非方纹理比例与采样用途保来源；Rope 单图 atlas 的整张 source 与 Sprite 帧不是同一语义。

composition 成员使用 nearest group 的原 MainPass；canonical camera/viewport 保留几何和 Trail 度量，最终 XY 与 REFRACT 位移才转换到目标。两行 raster uniform 位于原字段之后（CPU/MSL stride304），Z/W 保原相机深度；depth 与背景快照消费真实 attachment。没有逐粒子 CPU 转换、第二相机或按效果名准入。完整职责和仿射输入合同见[组合层栅格](effect-execution-coverage.md#particle-subtree-raster)。

CPU batch 不持可写 instance buffer。原 ParticleMetalPipeline 按 root/child-template key 拥有上传 slot，形成 frame-local PreparedBatch；prepare/upload/draw/arm/cancel 由同一 GPU owner 管理。在途 buffer 与 depth/refraction pin 随真实 command 终态释放。

Surface 采用新 topology 才退出死 root/child GPU key；重建构造前过滤 committed 死 root。未提交取消释放其 slot，已提交不能用 CPU 回滚撤销。hidden 不等于退休，peer key 可复用。

材质剔除由原 Metal raster 状态消费：`normal` 编译为 back-cull，`noCull` 保双面，共用已有三角绕序与 vertex。其资格不依赖 renderer 名称或 REFRACT 组合，不改变相机、basis、尺寸与变换、纹理 UV、snapshot 或输出 owner。镜像是否翻面按实际几何投影决定，不改 front-facing 补偿作者变换。

<a id="optional-refraction-normal"></a>
### REFRACT 的可选 normal

材质 Catalog 在唯一入口保留纹理槽位并把缺省值投影为 `[String?]`。Planner 对可选第二槽只消费这个 typed 值：省略槽和显式 nil 都交给原无 normal 分支；非空引用继续经过真实资源解析、装载与格式判断，显式缺失或坏文件只使受影响资产不可用。不能通过 compactMap 把后续纹理移入空槽，也不为已解析的 nil 增加原始字段复验、默认纹理或资源 owner。条件/user texture 的动态生产者保持独立职责。

原 TextureLoader 的 nil 分支复用既有绑定并以 authoredFormat=nil 供 Pipeline 的原无 normal 标记；生产 shader 跳过 normal sample/displacement，继续实际背景采样、albedo、tint、coverage 与 overbright。本合同沿用本引擎已有的 canonical 无 normal 语义，不定义新的位移单位或公式。官方省略/null 的有界同外观结果只支持可选输入等价；合法 normal 的可定位位移仍未知，原完整对照未通过，不能写成官方零位移或完整一致。

验收在真实 Catalog→Planner/AssetGraph 检查省略、null、空值和资源改名的等价，以及显式正常/缺失 normal 与健康后继；复用原无 normal/有效 normal 的生产 Metal 像素门，再核原作者两个活动资产的实际纹理、实例、目标、command buffer 与最终捕获。不能以准备放行或全景非黑代替实际编码，不以本修复授全部材质输入、Rope/动画组合或逐输入像素贡献。

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
