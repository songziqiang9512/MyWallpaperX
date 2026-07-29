# Scene Particle 官方组件覆盖台账

> 状态：现役专题能力表
>
> 最近核对：2026-07-29
>
> 口径来源：[官方页面目录](official-page-catalog.md)、[运行时系统语义](runtime-systems-reference.md)、[资料来源与证据索引](source-index.md)
> 当前结论：MyWallpaperX 已有可见的 2D Sprite 粒子子集，并执行非音频 Turbulent Velocity Random、非音频 Turbulence operator、zero-min centered Box、常见 Random initializer exponent、lifetime-normalized Alpha/Size oscillation、TEX filter/address/mip sampler、严格的 child 层级 ≤ 2（depth-one static/default-static/`eventspawn` / natural-`eventdeath` / `eventfollow`，加 depth-two 仅 event 触发的 nested child）、有限 static origin translation、持续/混合/duration child emitter、静态可逆 layer world frame 下的 General/Movement/Renderer world-space 子集，以及严格 `genericparticle` `REFRACT=1` 双纹理背景折射子集；它仍不是通用 Particle System，尤其没有 Layer Image、static angles/scale、event child transform、collision/delete event、动态 Control Point、动态 world-space system transform、Rope、Audio Response（声明已保真解析，执行缺公式证据）、Lighting 和通用 Particle Material。
> 粒子落地提交分别是 eventspawn/death `f4173ea`/`7d53c10`、eventfollow `928acca`、持续 child/root aggregate budget `2f897bc`、static/default-static `899704b`、有限 static origin `678a052`、strict depth-two nested child/per-depth 预算 `b86db59`、非音频 turbulent velocity `4a17ee6`、strict REFRACT `e698c18`、static world-space `54a6ebc`、非音频 Turbulence operator `7b1d36f`、TEX sampler `d19e76b`、分布/offset/lifetime oscillation `d792296` 与实际 mip 链 `f4e8a0c`。本专项表不复制全局实现基线；当前固定 13 样本门 particle 为 `76/76`，完整 45 样本门为 `127/130`，两者仍是 `8f4cd30` 的最近统一门；新能力只跑 E-PARTICLE 所列定向门，不能把旧统一门外推到新实现。仍不是通用 Particle System。

本文把官方 Particle 的 General、Emitter、Initializer、Operator、Renderer、Control Point、Children、instance override 与 material 逐项映射到当前实现。它是 [总覆盖台账](coverage-ledger.md) 中 Particle 行的展开表；总表与本文冲突时，以本文更细粒度、更新的代码证据为准。

## 1. 等级口径

| 等级 | 本文判定条件 |
|---|---|
| `L0` | 当前粒子管线没有对应字段、类型、路由或执行入口。 |
| `L1` | 能识别名称、保留部分字段或输出 unsupported 诊断，但没有有效执行。 |
| `L2` | 已进入 typed IR、资源图或运行路由，但没有完成执行与正反测试。 |
| `L3` | 有受限执行器和正反测试；仍未通过 Wallpaper Engine 数值或像素基准。 |
| `L4` | 作者启用、输入、顺序、生命周期和数值/视觉均经合法 Windows Wallpaper Engine golden 核验。 |

每项只给一个等级。`L3` 的限制写在“当前边界”，不能把它理解为完整兼容。当前没有任何 Particle 项达到 `L4`。

## 2. 证据路径缩写

表内缩写均为可点击的仓库相对路径；每一行至少给出一处当前代码或测试证据。所有 `L3` 子集的隔离样本、GPU 与视觉运行证据统一引用 [E-PARTICLE](runtime-evidence-index.md#e-particle)，不能仅凭代码路径抬级。对 `L0` 项，证据表示当前 typed model/parser/simulator 中没有对应字段或分支，或已有负向诊断门。

| 缩写 | 路径 |
|---|---|
| DEF | [MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleDefinition.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleDefinition.swift) |
| PAR | [MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleDefinitionParser.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleDefinitionParser.swift) |
| SIM | [MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleSimulator.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleSimulator.swift) |
| RANDOM | [MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleSimulator+Random.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleSimulator+Random.swift) |
| OSC | [MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleOscillationCache.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleOscillationCache.swift) |
| SUP | [MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleSimulationSupport.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleSimulationSupport.swift) |
| RUN | [MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleRuntime.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleRuntime.swift) |
| CHILD | [MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleChildRuntime.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleChildRuntime.swift) |
| CHILD-EXPAND | [MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleChildGraphExpansion.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleChildGraphExpansion.swift) |
| CHILD-LIFE | [MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleChildLifecycle.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleChildLifecycle.swift) |
| AST | [MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleAssetGraph.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleAssetGraph.swift) |
| GPU | [MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleMetalPipeline.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleMetalPipeline.swift) |
| SAMP | [MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleSamplerStateSet.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleSamplerStateSet.swift) |
| REFR | [MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleRefractionPlan.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleRefractionPlan.swift) |
| SNAP | [MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneFramebufferSnapshot.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneFramebufferSnapshot.swift) |
| CAM | [MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleCameraFrame.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleCameraFrame.swift) |
| WORLD | [MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleWorldSpacePlan.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleWorldSpacePlan.swift) |
| WORLD-DESC | [MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneParticleWorldSpacePlan+Descriptor.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneParticleWorldSpacePlan+Descriptor.swift) |
| TRAIL | [MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleTrailRenderPlan.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleTrailRenderPlan.swift) |
| TEX | [MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleTextureSource.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleTextureSource.swift) |
| BUILTIN | [MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleBuiltInTextureRegistry.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleBuiltInTextureRegistry.swift) |
| STOCK-ASSETS | [stock 播放资产包](stock-asset-bundle.md) |
| STOCK-RESOLVER | [MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneStockTextureResolver.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneStockTextureResolver.swift) |
| PLAY | [MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticlePlaybackState.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticlePlaybackState.swift) |
| T-DEF | [script/tests/test_scene_particle_definitions.py](../../../script/tests/test_scene_particle_definitions.py) |
| T-SIM | [script/tests/test_scene_particle_simulator.py](../../../script/tests/test_scene_particle_simulator.py) |
| T-RUN | [script/tests/test_scene_particle_runtime.py](../../../script/tests/test_scene_particle_runtime.py) |
| T-AST | [script/tests/test_scene_particle_assets.py](../../../script/tests/test_scene_particle_assets.py) |
| T-GPU | [script/tests/test_scene_particle_rendering.py](../../../script/tests/test_scene_particle_rendering.py) |
| T-CAM | [script/tests/test_scene_particle_camera_frame.py](../../../script/tests/test_scene_particle_camera_frame.py) |
| T-TRAIL | [script/tests/test_scene_particle_trail_plan.py](../../../script/tests/test_scene_particle_trail_plan.py) |
| T-TEX | [script/tests/test_scene_particle_builtin_textures.py](../../../script/tests/test_scene_particle_builtin_textures.py) |

## 3. General

官方入口：[General](https://docs.wallpaperengine.io/en/scene/particles/component/general.html)、[Sprite Sheet tutorial](https://docs.wallpaperengine.io/en/scene/particles/tutorial/spritesheet.html)。

| ID / 能力 | 官方语义摘要 | 等级 | 代码/测试证据路径 | 当前边界 | 下一验收门 |
|---|---|---|---|---|---|
| G01 Material reference | 粒子系统引用 material，material 决定纹理、shader 与 render state。 | `L3` | [DEF] [AST] [T-AST] | 只执行 `genericparticle` 近似路径和首纹理；完整能力见 Material 表。 | 多纹理 material fixture、未知 shader fail-closed、Windows 像素门。 |
| G02 Maximum count | `max count` 限制系统同时存活的粒子数量并进入预算。 | `L3` | [DEF] [SIM] [T-SIM] | 上限额外硬夹到 20,000，尚未核验官方边界和 runtime change。 | 0、1、超大值、动态修改与压力 fixture。 |
| G03 Start time / prewarm | 开始时间影响系统何时进入已推进状态，不能由“层可见”替代。 | `L3` | [DEF] [SIM] [T-SIM] | 当前直接当 prewarm duration，最多 240 次步进；未核验 WE 的 start-time 精确定义。 | 与 Windows 在 0、正值、长时长下做粒子状态 golden。 |
| G04 World space | 粒子出生后不再随粒子系统的位置/旋转变化。 | `L3` | [DEF] [WORLD] [WORLD-DESC] [RUN] [CHILD] [T-CAM] [T-RUN] | 仅静态、可逆 layer/ancestor world frame；root 与 strict child `eventfollow` 为每个新粒子保存出生系统原点。inline script、transform Timeline/诊断、有效 parallax、循环或奇异 frame 均 fail closed；无动态 parent 或 Windows golden。 | 动态 parent/Timeline、camera/multi-screen 与 Windows 轨迹 golden。 |
| G05 Perspective rendering | 作者可选择透视粒子相机，而非一律正交 billboard。 | `L3` | [DEF] [CAM] [RUN] [T-CAM] [T-RUN] | 使用自有固定 eye-distance 相机；未与 WE FOV/depth 做像素核验。 | 正交/透视同场景 Windows golden 和 near/far 边界门。 |
| G06 Sprite sheet animation mode | Sprite Sheet 可按 Sequence 或 Random Frame 选择帧。 | `L3` | [DEF] [RUN] [T-GPU] | 仅当前 TEX sprite metadata；未知 mode 默认为 Sequence。 | 非法 mode fail-closed、完整 atlas 与 Windows 帧序列门。 |
| G07 Frame blending | 相邻 sprite 帧可插值，作者也可关闭。 | `L3` | [DEF] [RUN] [GPU] [T-GPU] | 仅 Sequence 混帧；未核验颜色空间、边缘 sampling。 | 相邻帧像素 golden、Random Frame 和禁用负向门。 |
| G08 Sequence multiplier | 作者倍率控制一生内 sprite sequence 的播放次数/进度。 | `L3` | [DEF] [RUN] [T-GPU] | 只接 lifetime-normalized selector；负值和超大值未对 WE。 | 0、负值、分数、大倍率的帧索引 golden。 |
| G09 Allow color override | General 可声明实例是否允许覆盖 color。 | `L0` | [DEF] [PAR] [T-DEF] | 没有 allow-color typed field；只要实例有值就尝试应用。 | 保存 gate 字段并证明禁止时 override 不生效。 |
| G10 Allow count override | General 可声明实例是否允许覆盖 count。 | `L0` | [DEF] [PAR] [T-DEF] | 没有 allow-count gate。 | allow/deny 两组发射数量 fixture。 |
| G11 Allow lifetime override | General 可声明实例是否允许覆盖 lifetime。 | `L0` | [DEF] [PAR] [T-DEF] | 没有 allow-lifetime gate。 | allow/deny 两组 lifetime 数值门。 |
| G12 Allow size override | General 可声明实例是否允许覆盖 size。 | `L0` | [DEF] [PAR] [T-DEF] | 没有 allow-size gate。 | allow/deny 两组 GPU size 门。 |
| G13 Allow speed override | General 可声明实例是否允许覆盖 speed。 | `L0` | [DEF] [PAR] [T-DEF] | 没有 allow-speed gate。 | allow/deny 两组 velocity/position 门。 |
| G14 Component authored order | 多个 emitter/initializer/operator 按作者顺序组成一个系统。 | `L2` | [PAR] [SIM] [T-DEF] [T-SIM] | 数组顺序已路由，但没有顺序交换的定向断言；renderer 最终只选一个支持项。 | 重复同类 component、顺序交换与 Windows 状态 golden。 |
| G15 Fixed simulation step | 模拟必须使用明确 dt，实时和离线才能稳定复现。 | `L3` | [SIM] [PLAY] [T-SIM] | 固定 1/60；外层 delta 夹到 0.25，但没有 dropped-time 统计。 | pause/resume、长卡顿、离线 fixed-clock 等价门。 |
| G16 Deterministic seed | 同 wallpaper/system/particle seed 应可重放随机结果。 | `L3` | [SUP] [SIM] [T-SIM] | 当前 seed 只来自 layer ID；未建立 wallpaper/system/component seed hierarchy。 | 明确 seed 合成合同并与 Windows 分布/序列核验。 |
| G17 Visibility and parent gating | 不可见或被父级隐藏的粒子层不得继续当作可见输出。 | `L3` | [RUN] [PLAY] [T-RUN] | 初始化时过滤 visible layer；运行中 visibility 变化仍依赖 Scene 重建。 | typed live visibility、停止发射/恢复策略和资源代际门。 |
| G18 Pause/resume | 暂停时不发射；恢复是否追帧由统一时钟合同决定。 | `L0` | [PLAY] [SIM] [T-SIM] | 只有 delta clamp，没有 particle pause state。 | 共享 SceneClock pause/seek/discontinuity fixture。 |

## 4. Emitters

官方入口：[Emitter](https://docs.wallpaperengine.io/en/scene/particles/component/emitter.html)。

| ID / 能力 | 官方语义摘要 | 等级 | 代码/测试证据路径 | 当前边界 | 下一验收门 |
|---|---|---|---|---|---|
| E01 Sphere Random | 在 origin/control point 周围的球或圆范围随机生成。 | `L3` | [DEF] [PAR] [SIM] [T-SIM] | 自有均匀半径算法；未核验 WE 的维度、seed 与 exponent 分布。 | 2D/3D、空方向、固定 seed 的位置分布 golden。 |
| E02 Box Random | 在矩形或盒范围内随机生成。 | `L3` | [DEF] [PAR] [RANDOM] [T-SIM] | `distancemin` 缺省或各轴为 0 时按 `-abs(max)...+abs(max)` 围绕 origin；显式正非零 min/max 保留作者区间。direction 仍只作逐轴乘法，sign、混合零/非零轴、反向范围和 WE 分布未核验。 | 各轴反向/禁用、混合轴与 Windows 固定 seed 分布门。 |
| E03 Layer Image | 从 image/text/puppet 的有效像素发射，可继承颜色和 motion。 | `L1` | [PAR] [T-DEF] | 名称只进入 unsupported diagnostic，没有 source layer/bitmap IR。 | 静态 image bitmap emitter，再补 text/puppet 与 motion。 |
| E04 Origin / offset | 作者 offset 决定发射中心，可叠加 control point。 | `L3` | [DEF] [SIM] [T-DEF] | 仅 local vector；没有 object/world/child 空间转换。 | local/object/world 三空间正反 fixture。 |
| E05 Directions and sign | 可限制随机方向维度并固定正负方向。 | `L2` | [DEF] [SIM] [T-DEF] | 字段和执行分支存在，但测试只证明解析；Sphere/Box 组合和零向量 fallback 未验证。 | 全 2^3 direction/sign 组合状态门。 |
| E06 Distance min/max | 定义 Sphere 半径或 Box 各轴范围。 | `L3` | [DEF] [SIM] [T-SIM] | 无 exponent/bias；非法范围走自有归一化。 | min=max、min>max、负值和分布 golden。 |
| E07 Rate | 连续发射率按时间积累，不应依赖显示刷新率。 | `L3` | [DEF] [SIM] [T-SIM] | 固定步 remainder 可用；rate override 的时间缩放语义未核验。 | 30/60/120 FPS 等量、分数 rate 与 Windows 门。 |
| E08 Instantaneous count | 在计划时点一次性发射指定数量。 | `L3` | [DEF] [SIM] [T-SIM] | 只支持首个 instantaneous burst；无周期 burst。 | delay + periodic burst 组合 fixture。 |
| E09 Duration | 限制 emitter 持续发射时间。 | `L3` | [DEF] [SIM] [T-SIM] | 受 rate override 缩放 elapsed，是否符合官方未核验。 | 边界时刻、rate override 和帧率独立门。 |
| E10 Delay | emitter 可在系统启动后延迟开始。 | `L0` | [DEF] [PAR] [SIM] | 没有 delay 字段或 schedule state。 | typed delay + delay 前零发射/边界帧门。 |
| E11 Periodic emission | emitter 可按周期重复发射窗口或 burst。 | `L0` | [DEF] [PAR] [SIM] | 没有 period/repeat 状态。 | period、phase、duration、burst 组合状态机测试。 |
| E12 One per frame | 作者 flag 可将本次发射限制为每帧最多一个。 | `L3` | [DEF] [SIM] [T-DEF] [T-SIM] | 这里的“帧”实际是 1/60 simulation step，不一定等于 WE render frame。 | 不同 render FPS 下与官方计数核验。 |
| E13 Speed min/max | 生成时按范围给粒子初始径向速度。 | `L2` | [DEF] [SIM] [T-DEF] | 已接入 velocity，但没有 emitter speed 的定向数值断言；零半径会走自有零速度。 | 零半径、负速度、各 emitter 的 velocity golden。 |
| E14 Control point source | emitter 可把指定 control point 作为发射基准。 | `L2` | [DEF] [SIM] [T-DEF] | 仅有静态 local offset 分支，测试未断言最终位置；不支持角度、指针、parent/world。 | CP 0...7 静态位置断言，再补动态移动与坐标转换门。 |
| E15 Audio response | rate/shape/speed 等参数可由频谱范围、amount、exponent 调制。 | `L1` | [DEF] [PAR] [SUP] [T-DEF] [T-SIM] | 五字段按粒子自身 schema 保真进 IR（`audioprocessingmode`/`bounds`/`exponent`/`frequencystart`/`frequencyend`；粒子**没有** `audioamount`，字段名与 effect 侧不同），emitter/turbulent velocity/operator 三类共用同一声明类型，启用后一律报 `audioResponseIgnored`。 | 频谱 snapshot 已可用（[E-AUDIO-INPUT](runtime-evidence-index.md#e-audio-input)），阻塞项是**求值公式与调制目标无证据**：粒子侧无 shader 源码，第三方参考实现是 `audioAmplitude = 0.0` 的 TODO 占位、默认值在 emitter/initializer 两处自相矛盾。需 Windows golden 或官方算法。 |
| E16 Layer Image color/motion inherit | Layer Image 可从命中像素继承颜色和纹理运动。 | `L0` | [DEF] [PAR] [SIM] | 无 emission sample、pixel color 或 motion field。 | CPU/GPU emission map 和继承值 initializer fixture。 |
| E17 Layer Image bitmap update | 动态 source 变化时才更新 emission bitmap，不应无条件每帧重建。 | `L0` | [AST] [RUN] [SIM] | 没有 source generation 或 emission bitmap cache。 | 静态零重建、时钟 text 按 generation 更新的性能门。 |

## 5. Initializers

官方入口：[Initializer](https://docs.wallpaperengine.io/en/scene/particles/component/initializer.html)。Initializer 只在粒子创建时运行。

| ID / 能力 | 官方语义摘要 | 等级 | 代码/测试证据路径 | 当前边界 | 下一验收门 |
|---|---|---|---|---|---|
| I01 Lifetime Random | 从范围为新粒子选择 lifetime。 | `L3` | [DEF] [RANDOM] [T-SIM] | 无 exponent 时为线性；finite nonnegative exponent 使用 `pow(U,e)`。单位、clamp、非法/极值与 WE RNG 未核验。 | 零/负 lifetime、分数/大 exponent 与 Windows 固定 seed 分布门。 |
| I02 Size Random | 从范围为新粒子选择初始 size。 | `L3` | [DEF] [RANDOM] [T-SIM] | scalar 路径消费 exponent；单位、renderer 像素比例与 WE RNG 未核验。 | size 0、透视缩放和 Windows 画面门。 |
| I03 Color Random | 用一个随机系数在作者给定的两个颜色之间插值。 | `L3` | [DEF] [RANDOM] [T-SIM] | RGB 共用同一 exponent-biased 插值系数并按 0...255 除法；线性/sRGB 与 WE RNG 合同未知。 | 色彩空间、端点/中间值分布和 Windows pixel golden。 |
| I04 HSV Color Random | 在 HSV 范围采样后转换为粒子颜色。 | `L1` | [PAR] [SUP] [T-DEF] | 仅保留 unsupported 名称。 | typed HSV ranges、wrap、转换色彩空间测试。 |
| I05 Color List | 从作者颜色列表按规则选择。 | `L1` | [PAR] [SUP] [T-DEF] | 列表内容没有 typed IR。 | list、weight/index 语义 fixture 和 seed 门。 |
| I06 Alpha Random | 从范围选择初始 alpha。 | `L3` | [DEF] [RANDOM] [T-SIM] | scalar exponent 路径已共用；无官方 clamp/precision/RNG golden。 | 0、1、越界、override 组合测试。 |
| I07 Velocity Random | 仅设置初始 velocity；位置推进仍需 Movement operator。 | `L3` | [DEF] [RANDOM] [T-SIM] | 各轴独立随机并消费同一 exponent；轴相关性与 WE 分布未知。 | 无 Movement 时静止负向门和 Windows 分布 golden。 |
| I08 Inherit Control Point Velocity | 新粒子继承指定 control point 的速度。 | `L1` | [PAR] [SUP] [T-DEF] | 没有 CP previous/current state或 velocity。 | 动态 CP 两帧差分、空间转换和倍率 fixture。 |
| I09 Turbulent Velocity Random | 使用方向、noise phase/scale/time 和速度范围初始化湍流速度。 | `L3` | [DEF] [PAR] [SIM] [SUP] [T-DEF] [T-SIM] | 非音频 profile 使用项目自建确定性 3D gradient noise；`offset` 已从 noise time 分离，并作为 forward→tangent 平面弧度旋转，`scale=0` 仍保留 offset。right/up/noise mapping 与单位是 clean-room；Audio profile 继续 fail closed，无 Windows WE 数值/像素等价证据。 | 合法 Windows WE 固定 seed/offset/phase/time 状态 golden；audio 分支另需官方算法或 golden。 |
| I10 Rotation Random | 为新粒子选择初始旋转。 | `L2` | [DEF] [SIM] [T-DEF] | 已接入 simulator，但现有测试只证明 component 解析，没有最终 rotation 数值断言。 | screen/upright/fixed 下角度 golden。 |
| I11 Position Offset Random | 在 emitter 结果上增加随机位置 offset。 | `L1` | [PAR] [SUP] [T-DEF] | 名称可诊断，未保存专用范围或执行。 | typed min/max、作者顺序和空间 fixture。 |
| I12 Angular Velocity Random | 为新粒子选择初始角速度。 | `L3` | [DEF] [SIM] [T-SIM] | 只有 Angular Movement 才推进；单位未核验。 | 无/有 Angular Movement 的状态 golden。 |
| I13 Position Around Control Point | 围绕指定 CP 放置新粒子。 | `L1` | [PAR] [SUP] [T-DEF] | 没有 typed CP/radius fields。 | CP 0...7、range、local/world 空间 fixture。 |
| I14 Position Between Control Points | 在两个 CP 之间按规则放置新粒子。 | `L1` | [PAR] [SUP] [T-DEF] | 没有两个 CP identity 和插值字段。 | 端点、随机比例、移动 CP fixture。 |
| I15 Remap Initial Value | 把一个初值范围映射到另一个粒子属性。 | `L1` | [PAR] [SUP] [T-DEF] | 没有 source/target property typed enum。 | typed particle channel、clamp/extrapolate 数值门。 |
| I16 Inherit Value From Event | child/event 粒子继承 parent 的 color/size/alpha 等值。 | `L1` | [PAR] [SUP] [CHILD] [T-DEF] [T-RUN] | child runtime 收到 typed parent particle state，但 child initializer/operator 尚不消费 color/size/alpha。 | 每种继承 channel 的 typed fixture 与正反数值门。 |
| I17 Exponent bias | Random min/max 可用 exponent 改变分布密度。 | `L3` | [DEF] [PAR] [RANDOM] [T-DEF] [T-SIM] | scalar、vector 各轴与 color 共用插值因子消费 finite nonnegative exponent；当前公式为 `pow(U,e)`，非法/负值回退无 bias。自动门覆盖 0/1/2、vector 与 color；这只是项目合同，不是官方 RNG 等价。 | 分数/大 exponent、非法值与 Windows fixed-seed 分布 golden。 |
| I18 Run once in authored order | 每个 initializer 对新粒子执行一次，顺序可影响最终初值。 | `L2` | [PAR] [SIM] [T-SIM] | 代码按数组运行，但没有重复 initializer 或顺序交换的定向断言。 | 重复 initializer 与交换顺序的状态 golden。 |

## 6. Operators

官方入口：[Operator](https://docs.wallpaperengine.io/en/scene/particles/component/operator.html)。Operator 在单粒子存活期间按作者顺序更新。

| ID / 能力 | 官方语义摘要 | 等级 | 代码/测试证据路径 | 当前边界 | 下一验收门 |
|---|---|---|---|---|---|
| O01 Movement | 用 velocity、gravity、drag 随时间推进位置。 | `L3` | [DEF] [SIM] [WORLD] [T-SIM] | 自有 semi-implicit integration；world-space 子集先用静态逆 world linear frame 把作者 velocity/gravity 转回 local simulation direction。 | 不同 dt、gravity/drag、动态 parent 边界与 Windows 轨迹 golden。 |
| O02 Angular Movement | 用 angular velocity、force、drag 推进旋转。 | `L3` | [DEF] [SIM] [T-SIM] | 角度单位和三轴 renderer 关系未核验。 | 三 orientation、不同 dt 的旋转 golden。 |
| O03 Cap Velocity | 将速度限制在作者范围而不改变方向语义。 | `L1` | [PAR] [SUP] [T-DEF] | 只有 unsupported diagnostic。 | min/max、超限、零向量 fixture。 |
| O04 Alpha Fade | 在 lifetime 的淡入/淡出区间调制 alpha。 | `L3` | [DEF] [SIM] [T-SIM] | 默认值与边界行为为自有近似。 | 交叠区间、零长度、边界帧 golden。 |
| O05 Size Change | 随 normalized age 从起值变化到终值。 | `L3` | [DEF] [SIM] [T-SIM] | 线性插值且乘初始 size；官方 curve/remap 未核验。 | start/end 外区间和 Windows 数值门。 |
| O06 Color Change | 随 normalized age 改变 color。 | `L3` | [DEF] [SIM] [T-SIM] | 线性乘法近似；色彩空间未知。 | RGB/linear-sRGB、越界值与 pixel golden。 |
| O07 Alpha Change | 随 normalized age 改变 alpha。 | `L3` | [DEF] [SIM] [T-SIM] | 线性乘法近似。 | 与 Alpha Fade 顺序交换、边界值门。 |
| O08 Oscillate Position | 以 frequency/phase/scale/mask 周期偏移位置。 | `L3` | [DEF] [SIM] [T-SIM] | 当前按 velocity-like 增量累加，可能与官方绝对 offset 语义不同。 | 长时无漂移门和 Windows 轨迹 golden。 |
| O09 Oscillate Alpha | 周期调制 alpha，并受 blend window 控制。 | `L3` | [DEF] [SIM] [OSC] [T-SIM] | frequency 解释为每个粒子 lifetime 的周期数：`cos(2π*f*normalizedLife+phase)`；每步从 initial alpha 重置后按作者 operator 顺序组合，粗/细 fixed-step 在非零相位点一致。随机 phase/seed/default 与 WE 数值未核验。 | 缺省参数、随机范围、窗口边界和 Windows 数值 golden。 |
| O10 Oscillate Size | 周期调制 size，并受 blend window 控制。 | `L3` | [DEF] [SIM] [OSC] [T-SIM] | 与 Alpha 共用 lifetime frequency；每步从 initial size 重置后组合。自有默认 0.8...1.2、phase/seed 未核验官方。 | 显式/缺省参数、随机范围与 Windows 数值门。 |
| O11 Control Point Force | control point 对粒子施加吸引/排斥力。 | `L1` | [DEF] [PAR] [SUP] [T-SIM] | `controlpointattract` typed，但 simulator 明确忽略。 | local/world CP force、threshold、falloff 轨迹门。 |
| O12 Maintain Distance To Control Point | 约束粒子和一个 CP 的距离。 | `L1` | [PAR] [SUP] [T-DEF] | 只有 unsupported 名称。 | constraint solver、stiffness/damping fixture。 |
| O13 Maintain Distance Between Control Points | 约束两个 CP 之间的关系。 | `L1` | [PAR] [SUP] [T-DEF] | 没有双 CP typed identity。 | 两端动态 CP 和固定 dt 稳定性门。 |
| O14 Reduce Movement Near Control Point | 靠近 CP 时按距离衰减运动。 | `L1` | [PAR] [SUP] [T-DEF] | 只有 unsupported 名称。 | 距离曲线、零半径和 world/local fixture。 |
| O15 Turbulence | 用确定性 noise field 持续改变运动。 | `L3` | [DEF] [PAR] [SIM] [SUP] [T-DEF] [T-SIM] | 非音频 profile 按作者顺序消费 mask、phase、scale、time scale、speed range、normalized-age blend window、fixed `dt` 与静态 speed override；particle ID、operator index 和 simulation seed 产生稳定 phase/speed，最终非有限 velocity 写入失败关闭。缺省 `scale=0.005`、`speed=500...1000`、`timeScale=0.01`、`mask=(1,1,0)`、`phase=0...0` 来自现有 stock corpus/clean-room parser 交叉推断，不是官方数值合同；audio-enabled profile 零执行并保留 `audioResponseIgnored`/`unsupportedOperator`。 | Windows WE 固定 seed/phase/time 数值与轨迹 golden；另以官方算法或 golden 接入 audio phase 调制。 |
| O16 Vortex | 围绕中心/CP 产生旋转场。 | `L1` | [DEF] [PAR] [SUP] [T-SIM] | typed 部分字段但执行明确忽略。 | axis、radius、speed、CP/world fixture。 |
| O17 Boids | 粒子按邻域 separation/alignment/cohesion 群集运动。 | `L1` | [PAR] [SUP] [T-DEF] | 只有 unsupported 名称；没有 spatial index。 | 小规模确定性邻域 fixture 和预算门。 |
| O18 Remap Value | 每帧把一个粒子通道映射到另一个通道。 | `L1` | [PAR] [SUP] [T-DEF] | 没有 source/target channel typed model。 | typed channel + clamp/extrapolate 数值门。 |
| O19 Inherit Value From Event | event/child 在运行期继承 parent 值。 | `L1` | [PAR] [SUP] [T-DEF] | 没有 event payload 或 parent particle handle。 | Children event runtime 后做 color/size/alpha fixture。 |
| O20 Plane Collision | 粒子与平面碰撞并执行响应。 | `L1` | [PAR] [SUP] [T-DEF] | 名称可诊断，没有 shape/solver 字段。 | hit time、normal、bounce/slide/stop/delete fixture。 |
| O21 Sphere Collision | 粒子与球体/CP sphere 碰撞。 | `L1` | [PAR] [SUP] [T-DEF] | 名称可诊断，没有 radius/CP solver。 | 内外命中、移动 CP 与 tunneling 门。 |
| O22 Bounds Collision | 粒子与包围边界碰撞。 | `L1` | [PAR] [SUP] [T-DEF] | 名称可诊断，没有 bounds solver。 | 四边/六面、角碰撞与固定 dt 门。 |
| O23 Quad Collision | 粒子与有限 quad 表面碰撞。 | `L1` | [PAR] [SUP] [T-DEF] | 名称可诊断，没有 quad geometry。 | 平面内外、边缘、旋转 quad fixture。 |
| O24 Model Collision | 粒子与 model/depth geometry 碰撞。 | `L1` | [PAR] [SUP] [T-DEF] | 名称可诊断；没有 model runtime。 | 先完成 model/depth provider，再做 hit/event 门。 |
| O25 Collision response | Collision 可 bounce、slide、stop、delete，并产生 death event。 | `L0` | [DEF] [PAR] [SIM] | 没有 response enum、collision state 或 collision-produced event。 | 每种 response 的速度/存活状态 fixture。 |
| O26 Blend-in/out windows | 很多 operator 以单粒子 normalized age 的 0...1 窗口混合权重。 | `L2` | [DEF] [SIM] [T-DEF] [T-SIM] | oscillation 与 Turbulence 已消费窗口，Turbulence 有窗口内/外运行断言；仍没有覆盖所有已支持 operator 的统一 weight 合同。 | 提取统一权重并覆盖所有支持 operator。 |
| O27 Normalized age and order | 每个 operator 读取同一 age/lifetime，并按作者顺序运行。 | `L2` | [SIM] [T-SIM] | Turbulence/Movement 顺序交换已锁定首步位置差异，证明这一组合按作者顺序；仍无重复 operator、event/collision 阶段与通用顺序门。 | 重复 operator、更多顺序交换与死亡边界 golden。 |
| O28 World-space movement flag | Movement 可选择 local/world 空间。 | `L3` | [DEF] [PAR] [SIM] [WORLD] [RUN] [T-SIM] [T-RUN] | 静态可逆 world frame 下执行世界方向 velocity/gravity；动态 script/Timeline/parallax/奇异 frame 仍报 `worldSpaceMovementUnsupported`。 | parent 动画时 local/world 分离门与 Windows 数值 golden。 |
| O29 Audio-modulated operator | Vortex/Turbulence 等 operator 可读取频谱调制。 | `L1` | [DEF] [PAR] [SUP] [T-DEF] | 声明与 emitter/initializer 共用同一类型并保真保存；启用后进入 `audioResponseIgnored`（此前 operator 完全无诊断、会静默按无音频路径模拟）。 | 同 E15：缺求值公式证据。语料唯一命中的 `vortex`（`2419444134`）其 operator 本体亦为 `L1`。 |

## 7. Renderers

官方入口：[Renderer](https://docs.wallpaperengine.io/en/scene/particles/component/renderer.html)。

| ID / 能力 | 官方语义摘要 | 等级 | 代码/测试证据路径 | 当前边界 | 下一验收门 |
|---|---|---|---|---|---|
| R01 Sprite | 每个粒子绘制独立 textured sprite。 | `L3` | [DEF] [RUN] [GPU] [SAMP] [T-GPU] [T-RUN] | 自有 quad shader、首纹理、两种 blend；renderer 必须显式传入 texture sampling，TEX filter/address/mip 进入真实 Metal sampler。additive 既有 premultiply 合同不变，精确 alpha/size 仍无 Windows pixel parity。 | 尺寸/旋转/alpha/color/UV/sampling 的 Windows golden。 |
| R02 Sprite Trail | 沿 velocity 拉伸 sprite，length 乘 speed 并受 min/max 限制。 | `L3` | [DEF] [TRAIL] [RUN] [T-TRAIL] [T-GPU] | 只做单 quad stretch；未核验 orientation、单位和低速边界。 | 速度方向、旋转、透视、atlas 联合 pixel 门。 |
| R03 Rope | 连续连接存活粒子，并维持 subdivision 与 UV continuity。 | `L1` | [DEF] [PAR] [RUN] [T-DEF] [T-RUN] | typed kind/segments/subdivision 可见，runtime 明确拒绝。 | rope topology buffer、连续 UV 与生命周期 fixture。 |
| R04 Rope Trail | 按轨迹长度保留 segments，并绘制连续 rope。 | `L1` | [DEF] [PAR] [RUN] [T-DEF] | typed kind/字段可见，runtime 明确拒绝。 | trail history、segments/subdivision、reset/resize 门。 |
| R05 Multiple renderers | 一个系统可有多个 renderer；不能只取第一个后宣称完整。 | `L2` | [DEF] [PAR] [RUN] [T-DEF] | parser 保留全部，runtime 扫描后只选择首个支持 renderer。 | 同系统 Sprite + Trail 双输出与顺序测试。 |
| R06 Screen orientation | Sprite 始终面向相机屏幕基。 | `L3` | [DEF] [RUN] [CAM] [T-CAM] [T-GPU] | 自有 camera basis；未做 WE pixel golden。 | 正交/透视、旋转层和非方画布门。 |
| R07 Upright orientation | Sprite 保持 world-up，同时面向相机。 | `L3` | [DEF] [CAM] [T-CAM] [T-GPU] | world-up 固定为当前实现约定。 | 相机/父级旋转和 Windows orientation 门。 |
| R08 Fixed orientation / axis | Sprite 使用作者轴和 layer transform 的固定平面。 | `L2` | [DEF] [RUN] [CAM] [T-DEF] [T-CAM] | axis 已路由到 renderer，但没有 authored-axis 端到端断言。 | 非默认 axis 的 GPU 几何和截图门。 |
| R09 Renderer world space | renderer 的 orientation 可独立于粒子系统 orientation。 | `L3` | [DEF] [RUN] [T-DEF] [T-GPU] [T-RUN] | Sprite 的 screen/upright/fixed world orientation 已与 system rotation/scale 解耦；这与 General/Movement world-space 分开准入。Trail/Rope、3D camera 和 Windows orientation golden 未完成。 | world-space Trail、camera/parent 组合与 Windows orientation golden。 |
| R10 Sprite Sheet UV | renderer 按 TEX atlas frame 的 origin/axes 取样。 | `L3` | [RUN] [GPU] [SAMP] [T-GPU] | UV>1 可随 TEX repeat sampler 回绕，不再 clamp 成边缘条；sidecar nominal frame size/aspect、rotated/trimmed 与多纹理 atlas 未接。 | frame aspect、rotated/trimmed frames 与 Windows sampling pixel 门。 |
| R11 Rope segments/subdivision | Rope 用 segments/subdivision 控制曲线细分。 | `L1` | [DEF] [PAR] [T-DEF] | 字段保留但无 geometry consumer。 | 数量、拓扑和 GPU buffer 上限测试。 |
| R12 Rope UV scale/smoothing/scroll | Rope 保持连续 UV，并支持 scale、平滑和滚动。 | `L0` | [DEF] [PAR] [GPU] | 没有字段或 rope shader。 | typed UV contract + 时间驱动 pixel fixture。 |
| R13 Renderer selection failure | 没有可执行 renderer 时应 fail-closed 并给出可定位诊断。 | `L2` | [RUN] [T-DEF] | Rope/unknown 的拒绝分支存在，但没有 runtime 定向测试；含 unsupported shader 的 Sprite 仍可能误走自有 shader。 | renderer + shader 联合 fail-closed 负向门。 |
| R14 Layer/camera transform | 粒子 geometry 应继承 scene layer world frame，并与 cover/camera 一致。 | `L3` | [CAM] [RUN] [T-CAM] | 只覆盖当前 2D parent transform 和自有 particle camera。 | 深层 parent、parallax、multi-screen 和 Windows 门。 |

## 8. Control Points

官方入口：[Control Point](https://docs.wallpaperengine.io/en/scene/particles/component/control_point.html)。官方索引范围为 0...7。

| ID / 能力 | 官方语义摘要 | 等级 | 代码/测试证据路径 | 当前边界 | 下一验收门 |
|---|---|---|---|---|---|
| C01 Definition and index | 系统可定义最多八个具名索引 CP，供多个 component 引用。 | `L2` | [DEF] [PAR] [T-DEF] | typed 数组保留 id/flags/offset/angles，但未严格验证 0...7 和重复 ID。 | 0...7、越界、重复 ID 的 fail-closed parser 门。 |
| C02 Relative offset | CP 可相对系统 origin 设置 offset。 | `L2` | [DEF] [SIM] [T-DEF] | 只在 emitter origin 的静态 local 路径接线，测试未断言最终位置。 | 静态 offset 数值断言，再补多 emitter、动态 offset 和 parent transform 门。 |
| C03 Angles | CP 可带方向/angles，供 emitter/child/force 使用。 | `L1` | [DEF] [PAR] [T-DEF] | 字段保留但 simulator 不消费。 | axis/basis 转换和依赖 component fixture。 |
| C04 Lock to pointer | CP 可跟随 pointer 输入。 | `L1` | [DEF] [SUP] [T-DEF] [T-SIM] | flag 可解析并诊断 `pointerControlPointIgnored`。 | current/previous pointer、screen/canvas/local 坐标门。 |
| C05 World space | CP 可在 world space 解释 offset/angles。 | `L1` | [DEF] [PAR] [T-DEF] | flag 可解析，没有 space transform 或专门 runtime diagnostic。 | world/local 双 CP 和移动 parent fixture。 |
| C06 Copy from parent | child/system CP 可从 parent 复制。 | `L0` | [DEF] [PAR] [SIM] | 没有 parent identity/copy 字段。 | parent-child runtime 后做 copy lifecycle 门。 |
| C07 Copy raw value | 从 parent copy 时可选择 raw value，跳过部分空间处理。 | `L0` | [DEF] [PAR] [SIM] | 没有 raw-copy 标志或语义。 | raw/transformed 两组坐标数值门。 |
| C08 Editor gizmo visibility | 作者工具可显示/隐藏 CP gizmo；播放器不应误当运行效果。 | `L0` | [DEF] [PAR] | 当前播放器不保留 editor-only 字段。 | 明确为 playback no-op；若需 round-trip，再保真保存。 |
| C09 Static instance position override | layer instance 可给 CP 0...7 增加静态位置。 | `L2` | [DEF] [PAR] [SIM] [T-DEF] | parser 和 emitter 分支已接线，但没有最终位置断言；未覆盖 operator/children。 | 先补 emitter 数值门，再测同一 CP 被 operator/child 共享。 |
| C10 Static instance angle override | layer instance 可覆盖 CP 0...7 angles。 | `L1` | [DEF] [PAR] [T-DEF] | wrapper 可解析/Codable，runtime 不消费。 | fixed orientation 或 child binding 的端到端门。 |
| C11 Dynamic property/script CP | user property、Timeline 或 SceneScript 可逐帧修改 CP。 | `L1` | [DEF] [SUP] [T-SIM] | wrapper 能识别 dynamic 来源并明确忽略。 | typed target 写入同帧 snapshot、generation 和无重建更新。 |
| C12 Cross-space conversion | emitter/initializer/operator/collision/children 使用 CP 前必须显式转换 scene/object/particle/child 空间。 | `L0` | [SIM] [CAM] [T-CAM] | 只有 emitter 的 local offset 加法。 | 建立 typed space 和每个 consumer 的转换 golden。 |

## 9. Children 与事件

官方入口：[Children](https://docs.wallpaperengine.io/en/scene/particles/component/children.html)。

| ID / 能力 | 官方语义摘要 | 等级 | 代码/测试证据路径 | 当前边界 | 下一验收门 |
|---|---|---|---|---|---|
| CH01 Child resource graph | child path 指向另一个 particle definition，资源必须递归可达。 | `L3` | [DEF] [AST] [CHILD] [CHILD-EXPAND] [T-AST] [T-RUN] | 资源图递归发现 definition/material/texture；`b86db59` 起 runtime 实例化 strict child 至层级 2：depth-one 全部触发保持每声明一个 template，depth-two 仅 event 触发并按 parent asset path 去重展开一次（纹理/instance buffer 共享）；depth-three 目标与 depth-two static 声明 fail closed（`nestedDepthUnsupported`/`nestedStaticChildUnsupported`），合成正反门与 26 样本 census 门（maximumChildDepth 2、63 条 nested 声明）锁定。 | depth-two static 语义样本、更深层级真实样本与 teardown 压力门。 |
| CH02 Cycle/missing child guard | 递归引用必须有 cycle、missing definition 诊断，不能死循环。 | `L2` | [AST] [CHILD] [T-AST] | runtime 复用有 stable missing/cycle 诊断的资源图，但尚无 runtime-specific cycle ownership/lifecycle 断言。 | cyclic root 的 runtime 构建、零实例与 stop 门。 |
| CH03 Static child | 在 particle system authored local origin 创建一次 child system。 | `L3` | [DEF] [PAR] [CHILD] [CHILD-EXPAND] [RUN] [T-DEF] [T-RUN] | 显式 `type=static` 与 legacy 缺失 type 都只创建一次 strict child；允许有限 origin translation，但仍要求零 angles、单位 scale、无 CP mapping、probability=1、Sphere/Box + Sprite/Sprite Trail、非音频且纹理可加载。`b86db59` 起目标定义自身还有 event children 的 static 声明（matrix spawner 形状）不再被 nested 阻断，`2974757317` 的 43 条 head 声明是真实缓存正例、`2938612768` 作者默认关闭保持不创建；depth-two static 声明与非法 origin、angles/scale、非单位 probability、unsupported renderer、缺资源继续 fail closed；`3088601835` 的 `snowstormfog` 是真实缓存正例。 | visibility/stop teardown 压力门与 depth-two static 语义样本。 |
| CH04 Event Follow child | parent particle 创建 child，并持续跟随 parent。 | `L3` | [DEF] [PAR] [CHILD] [CHILD-EXPAND] [CHILD-LIFE] [RUN] [T-DEF] [T-RUN] | 仅 identity transform、无 CP mapping、Sphere/Box + Sprite/Sprite Trail strict child；depth-one 以 root 粒子 ID 建 owner，depth-two 以 (parent system, parent particle) 建 owner 并把 origin 折算为 parent system origin + 粒子位置，parent 粒子或 parent system 消失即回收；`2974757317` 的 matrix trail（43 列共享单 template）是真实缓存正例，maximumSystemCount 在 depth-two 按 parent system 作用域计数（从 depth-one 等价形状类推）。持续/混合/duration emitter 已执行，event transform/CP/value inheritance 和 Windows golden 未完成。 | event transform/CP/value inheritance 与合法 Windows 状态门。 |
| CH05 Event Spawn child | parent 创建时在其位置生成独立 child。 | `L3` | [DEF] [SIM] [CHILD] [CHILD-LIFE] [RUN] [T-SIM] [T-RUN] | deterministic birth queue 执行 identity transform、depth-one、instantaneous/continuous/mixed Sprite/Sprite Trail child；event 系统的 rate 发射窗口有界：authored duration 优先，否则以 child 自身粒子最大寿命为窗口（rate x lifetime 保住作者 burst 规模），窗口结束且粒子清空后回收，instantaneous burst 不受窗口影响。此前 rate-only event child 无限发射会在 `2998757800`（Rain_Splash/Flare_Sparks）累积到 depth 预算并把画面推向全白。`3768903841` 是真实 eventspawn 正例。 | 无 duration 窗口是本地近似，需 Windows golden 定精确值；parent value inheritance、非 identity transform、跨步 order。 |
| CH06 Event Death child | parent 正常结束或 delete event 时生成 child。 | `L3` | [DEF] [SIM] [CHILD] [CHILD-LIFE] [RUN] [GPU] [T-SIM] [T-RUN] | 只执行 natural lifetime death；生成的 strict child 持续到有限 duration 或粒子最大寿命窗口完成且粒子清空后回收（同 CH05 的有界窗口），`2131872317` layer 529/832 可见 burst，collision/delete/stop event 尚未进入队列。 | collision delete、显式 stop/delete、同帧递归限制和 Windows 状态门。 |
| CH07 Offset/angles/scale | child instance 可相对 event/origin 设置 transform。 | `L1` | [DEF] [PAR] [T-DEF] | 字段保留但不执行。 | parent/local/world transform 数值门。 |
| CH08 Maximum count | child 可限制同时存在的 child instance 数。 | `L2` | [DEF] [PAR] [CHILD] [T-DEF] [T-RUN] | runtime 已按 template 限制 active child system（depth-two 按 (声明, parent system) 作用域计数），且拒绝非 1...512；尚无 0/1/回收重生断言，depth-two 作用域为 depth-one 等价形状的类推、无 Windows golden。 | 0/1/超限和回收后再生成门。 |
| CH09 Probability | 每次 child event 可按 probability 决定是否创建。 | `L2` | [DEF] [PAR] [CHILD] [T-DEF] | event ID + template index 的 deterministic RNG 已接线，0 直接跳过；尚无中间概率固定分布测试。 | 0/1/中间值固定 seed 分布门。 |
| CH10 Set control points | child 可从指定起始索引设置/继承 control points。 | `L1` | [DEF] [PAR] [T-DEF] | 只保留 `controlPointStartIndex`；无 mapping/space runtime。 | parent-child CP mapping 和 raw/transformed 门。 |
| CH11 Inherit event value | child initializer/operator 可读取 parent event 的 color/size/alpha 等值。 | `L1` | [PAR] [SUP] [T-DEF] | component 名称可诊断；没有 typed event payload。 | typed payload + 每种可继承 channel 的 fixture。 |
| CH12 Child execution/budget | child 发射、更新、renderer 和清理进入同一帧顺序与预算。 | `L3` | [SIM] [CHILD] [CHILD-EXPAND] [CHILD-LIFE] [RUN] [GPU] [T-SIM] [T-RUN] | strict child 独立持有 simulator（depth-two 同 asset 共享 texture/instance buffer），有限 duration 结束且粒子清空后回收；depth-one systems 先推进并收集 per-system birth/death/particles，再喂 depth-two spawn/death/follow（事件跨层按帧串行传播）。每 system 最多 1,024 粒子，每 root runtime 每深度最多 64 systems，跨两层共 128 systems/131,072 capacity；depth-one 超限诊断 `aggregateSystemBudget`，depth-two 为 `nestedAggregateSystemBudget`，合成 80-follower 门锁定 64 截断。尚无 stop/switch 压力门。 | stop/switch 归零、teardown 压力门与 collision 阶段预算。 |

## 10. Instance Overrides

官方 General 允许作者暴露 instance override；动态值还可来自 User Property、Timeline 和 SceneScript。

| ID / 能力 | 官方语义摘要 | 等级 | 代码/测试证据路径 | 当前边界 | 下一验收门 |
|---|---|---|---|---|---|
| IV01 Wrapper parse/preserve | override wrapper 应保留 authored value 与 user/script/animation 来源。 | `L2` | [DEF] [PAR] [T-DEF] | numeric value 和来源标志可 Codable；未保存 script/animation 内容。 | 保真 binding IR 和 source precedence 测试。 |
| IV02 Alpha | 统一缩放新粒子的 alpha。 | `L3` | [DEF] [SIM] [T-SIM] | 仅创建时静态乘法；live 变化不更新存量粒子。 | new/existing particle 的官方更新语义门。 |
| IV03 Size | 统一缩放新粒子的 size。 | `L3` | [DEF] [SIM] [T-SIM] | 仅创建时静态乘法。 | live generation 与存量粒子语义 fixture。 |
| IV04 Lifetime | 统一缩放新粒子的 lifetime。 | `L3` | [DEF] [SIM] [T-SIM] | 仅创建时静态乘法；不重算存量 age。 | live 修改时剩余 lifetime 的 Windows 状态门。 |
| IV05 Rate | 缩放 emitter 的发射时间/速率。 | `L3` | [DEF] [SIM] [T-SIM] | 当前同时缩放 elapsed 和 authored rate，官方精确公式未核验。 | duration + rate override 的计数 golden。 |
| IV06 Speed | 缩放粒子速度来源。 | `L3` | [DEF] [SIM] [T-SIM] | 创建时缩放初始 velocity，并对每步非音频 Turbulence 力使用同一静态倍率；live 修改不更新存量粒子，其他 operator 是否消费仍未定义。 | live 修改与 emitter/initializer/operator 组合门。 |
| IV07 Count | 缩放每步生成数量。 | `L3` | [DEF] [SIM] [T-SIM] | 与 rate 相乘，分数累积使用自有 remainder。 | 0、分数、>1、instantaneous 的计数 golden。 |
| IV08 Brightness | 统一调制粒子颜色亮度。 | `L3` | [DEF] [SIM] [T-SIM] | 直接乘 color，可超 1；HDR/overbright 管线不存在。 | SDR/HDR、clamp 与 blend pixel 门。 |
| IV09 Color | 以作者色值覆盖/调制粒子颜色。 | `L2` | [DEF] [SIM] [T-DEF] | 分支存在，但运行测试只覆盖 normalized color；除 255 后平方的依据未核验。 | direct color 数值断言和官方 color/linear conversion golden。 |
| IV10 Normalized color | 以 0...1 色值覆盖/调制粒子颜色。 | `L3` | [DEF] [SIM] [T-DEF] [T-SIM] | 当前也平方；与 Color 的 precedence 已实现但未对 WE。 | 同时提供 color/colorn 的 precedence 与 pixel 门。 |
| IV11 Control point position | 静态覆盖 CP 0...7 的位置。 | `L2` | [DEF] [PAR] [SIM] [T-DEF] | 已解析并接到 emitter origin，但没有最终位置运行断言。 | emitter 数值门，再补 operator/children 同 CP 消费与空间门。 |
| IV12 Control point angles | 静态覆盖 CP 0...7 的方向。 | `L1` | [DEF] [PAR] [T-DEF] | 可解析但没有 consumer。 | fixed-axis/child/force 的端到端门。 |
| IV13 User Property binding | override 可由用户属性动态驱动。 | `L1` | [DEF] [PAR] [SUP] [T-DEF] [T-SIM] | key 可识别，runtime `dynamicOverrideIgnored`。 | typed particle target + 无 Scene 重建逐帧应用。 |
| IV14 Timeline binding | override 可由 animation/Timeline 动态驱动。 | `L1` | [DEF] [PAR] [SUP] [T-DEF] | 只记录 `hasAnimation`，不保留曲线。 | Timeline IR/evaluator 写入 particle snapshot。 |
| IV15 SceneScript binding | override 可由 SceneScript 动态驱动。 | `L1` | [DEF] [PAR] [SUP] [T-DEF] | 只记录 `hasScript`，没有 script target/runtime。 | typed handle、budget、exception isolation 和同帧写回。 |
| IV16 General allow gates | instance override 只有在 General 对应 allow 开关开启时才可应用。 | `L0` | [DEF] [PAR] [SIM] | 当前没有 allow gate，静态值会直接应用。 | 五类 allow/deny 负向门，防止不该启用的效果被套用。 |

## 11. Particle Material、纹理与 Blend

官方 General 将 albedo/normal、cutout、lighting、refraction、overbright 和 blend 都视为 Particle renderer variant 的一部分。

| ID / 能力 | 官方语义摘要 | 等级 | 代码/测试证据路径 | 当前边界 | 下一验收门 |
|---|---|---|---|---|---|
| M01 Material/pass resolution | 从 particle material 找到 pass、shader、纹理和 render state。 | `L3` | [AST] [RUN] [T-AST] [T-RUN] | 只挑一个 pass，随后降级到专用自有 pipeline。 | 多 pass/slot、missing/duplicate、完整 state fixture。 |
| M02 `genericparticle` shader family | 官方通用粒子 shader 按 material combo 决定 renderer variant。 | `L3` | [AST] [GPU] [T-AST] [T-GPU] | 仅识别名字并使用自写 Metal 近似；不执行官方 shader/combo。 | combo matrix 和合法 Windows pixel golden。 |
| M03 Non-generic/custom shader | 非通用 shader 只能在具备等价 executor 时运行，否则应 fail-closed。 | `L1` | [AST] [RUN] [T-AST] | 会诊断 `unsupportedShader`，但含 Sprite 时仍可能进入自有 pipeline，存在误渲染风险。 | runtime 阻断负向门，再逐 shader family 加 executor。 |
| M04 Albedo / texture slot 0 | 首纹理提供 sprite 的颜色与 alpha。 | `L3` | [AST] [RUN] [GPU] [SAMP] [T-AST] [T-GPU] | TEX container bit 0/1 分别映射 nearest 与 clamp，缺位分别为 linear 与 repeat；实际 mip 链随 minification 消费，直接 image/generated 回退 linear-clamp。bit mapping 由本地 container/sidecar corpus clean-room 交叉确认，clamp-border bit 仅降级 edge。 | clamp-border、alpha edge、颜色空间和 Windows sampling golden。 |
| M05 Additional texture slots | material 可同时使用 normal/mask/noise 等多个纹理槽。 | `L3` | [AST] [REFR] [RUN] [GPU] [SAMP] [T-AST] [T-GPU] [T-RUN] | strict REFRACT 只消费无 hole 的 slot 0 albedo + slot 1 normal，两者使用独立 sampler；background 固定 linear-clamp。其他 mask/noise、多槽和 user texture input 继续 fail closed。 | 反向 sampler 像素门及其他已验证 variant 的 8-slot identity、nullable hole、binding precedence。 |
| M06 Normal map | normal texture 参与 lighting/refraction 的表面方向。 | `L3` | [AST] [REFR] [RUN] [GPU] [T-GPU] [T-RUN] | 只在 strict REFRACT 中按 RG88 luminance-alpha 或 RGBA alpha/green 解码并建立投影切线；Lighting、Rope 与 Windows normal 数值未覆盖。 | Lighting/Rope 独立 profile、切线基和 Windows pixel 门。 |
| M07 Cutout | 按作者阈值丢弃低 alpha 像素，而不是仅做 translucent blend。 | `L0` | [DEF] [AST] [GPU] | 没有 cutout flag/threshold 或 discard 分支。 | threshold 0/0.5/1 正反 pixel fixture。 |
| M08 Lighting | 粒子可受 Scene light、normal 与材质参数影响。 | `L0` | [AST] [GPU] | 无 light snapshot、normal/PBR 输入或 lit variant。 | 先接 Scene lighting contract，再做 lit/unlit pixel 门。 |
| M09 Refraction | 粒子可采样背景并产生折射。 | `L3` | [AST] [REFR] [SNAP] [RUN] [GPU] [T-AST] [T-GPU] [T-RUN] | `e698c18` 只接受 pass 0、`genericparticle`、`REFRACT=1`、两槽、无 user binding、no-depth/no-cull、translucent/additive 的静态 profile；按作者 batch 顺序捕获此前 framebuffer，消费 amount/overbright 与 normal/albedo animation。全分辨率 BGRA snapshot 上限 64 MiB，超限、未知 combo/state/format、缺槽均 fail closed；这是 clean-room 近似，无 Windows 像素等价。 | Windows 固定背景/法线/amount golden、5K/多 batch 带宽预算、resize/多屏/8K fail-closed 门。 |
| M10 Overbright/HDR | 作者可让粒子颜色超过 SDR，并参与 bloom/HDR。 | `L0` | [GPU] [SIM] | brightness 可让 CPU color >1，但当前 target/material 没有正式 HDR contract。 | float target、bloom ordering 与 HDR screenshot 门。 |
| M11 Additive blend | 粒子颜色加到目标上，常用于光、火花。 | `L3` | [AST] [GPU] [T-AST] [T-GPU] [T-RUN] | 自有 blend factor；未与 WE premultiply/alpha 写入核验。 | 重叠 sprite 和非 1 alpha 的 pixel golden。 |
| M12 Translucent blend | 粒子按 alpha 与目标混合。 | `L3` | [AST] [GPU] [T-AST] [T-GPU] | 自有 premultiplied 路径；官方边缘像素未知。 | 透明边缘、叠层顺序和颜色空间门。 |
| M13 Other blend modes | 其他作者 blend 必须有明确映射或 fail-closed。 | `L1` | [AST] [T-AST] | 会诊断后回退 translucent，可能产生错误画面。 | 禁止无证据 fallback；每种模式独立 pixel 门。 |
| M14 Depth test/write/cull | perspective/world 粒子可需要 depth 和 cull render state。 | `L2` | [AST] [REFR] [T-AST] | pass state 已保真进入粒子 adapter，strict REFRACT 只准入 disabled/disabled/nocull；GPU 尚无通用 depth attachment/state consumer。 | typed state + depth attachment 正反门。 |
| M15 Material combos/constants | combo/constant 选择 shader variant 和参数。 | `L3` | [AST] [REFR] [RUN] [GPU] [T-AST] [T-GPU] [T-RUN] | strict REFRACT 消费 `REFRACT`、零值 `CUTOUT`/`LIGHTING`、静态 `g_Amount`/`g_Overbright`；未知启用 combo、动态/user shader value 失败关闭。 | Lighting/Cutout 等各自 strict variant key 与参数 buffer fixture。 |
| M16 File-backed TEX/PNG/JPEG | 合法本地 particle texture 可解码并上传 GPU。 | `L3` | [AST] [RUN] [TEX] [SAMP] [T-AST] [T-GPU] [T-RUN] | TEX container filter/address flags 与已上传实际 mip 链进入 sampler；R8 view 保留 levels，RG88 转 premultiplied RGBA 时逐级保留。sidecar sprite sequence/nominal geometry 仍不进入 runtime，PNG/JPEG 走 linear-clamp。 | TEX variants、clamp-border、sidecar frame geometry、color space 与损坏资源负向门。 |
| M17 Built-in texture identity | `particle/...` key 指向 Wallpaper Engine 内置粒子资产。 | `L2` | [TEX] [AST] [STOCK-ASSETS] [STOCK-RESOLVER] [T-AST] [T-RUN] | `SceneStockAssets.bundle` 保留内置粒子资源的官方相对路径；样本本地纹理优先，缺失时按官方相对路径解析。runtime 消费 TEX container flags 与实际 mip levels，但不读取 `.tex-json` sidecar 的 sprite sequence/nominal frame geometry；序列帧未完整播放，逐资产通道/atlas/像素 parity 未证明，因此只到 wired。 | 接通 sidecar spritesheet sequence/frame geometry，补通道、atlas、颜色空间和 Windows pixel 门后再升级。 |
| M18 Twenty-two generated built-ins | 二十二个高命中 key 可生成确定性替代纹理，形态按官方 `.tex` 解码后的 alpha 场拟合。 | `L3` | [TEX] [BUILTIN] [T-TEX] [T-RUN] | stock bundle 可用时优先直接读取对应 TEX；本 registry 只作为 bundle 缺失时的兼容回退。程序图形不是官方资产。尺寸对齐官方 `imageWidth`/`imageHeight`，非方形 key 不再按方形近似（`drop`/`beam_1` 32×128、`light_shafts_0` 256×512、`light_shafts_6` 128×512、`flare_1` 256×256）。八个静态 key 以本地解码的官方 alpha 为参照做网格拟合，归一化坐标 64×64 采样的引用次数加权 RMSE 为 0.0373：`halo_4` 0.0106、`flare_1` 0.0253、`light_shafts_0` 0.0359、`light_shafts_6` 0.0365、`halo_6` 0.0368、`beam_1` 0.0405、`drop` 0.0477、`star` 0.1118。序列帧 key 仍只生成单帧且为灰度。 | bundle TEX 已具备真实素材，以同路径 TEX 为主门；程序 fallback 保留确定性与安全 alpha 门。 |
| M19 Missing built-in fail-closed | 未支持 built-in 应报告 unavailable，不能静默用任意白块。 | `L3` | [AST] [RUN] [T-AST] [T-RUN] | 诊断明确且层不可用；尚无用户可见降级说明。 | 诊断聚合和 fallback policy 产品门。 |
| M20 Sprite atlas metadata | TEX frame origin/axes/duration 选择 atlas 子区域。 | `L3` | [RUN] [GPU] [SAMP] [T-GPU] | 当前 SpriteAnimation + repeat sampler 子集；sidecar nominal frame aspect、rotated/trimmed 与多 texture sequence 未接。 | frame aspect、rotated/trimmed/variable duration atlas pixel 门。 |
| M21 Premultiplied alpha contract | CPU 颜色、纹理和 blend factor 必须使用一致 alpha 合同。 | `L3` | [BUILTIN] [TEX] [GPU] [T-TEX] [T-GPU] | generated 与 RG88 每级 mip 有 premultiply 门；其他外部 TEX/PNG 和 WE blend 未全链核验。 | file/built-in 双来源的重叠 pixel golden。 |
| M22 Pixel-equivalent material result | 最终 sprite 颜色、边缘、HDR、lighting 与 WE 参考一致。 | `L0` | [GPU] [T-GPU] | 只有 Metal smoke/几何/状态测试，没有 Windows golden。 | 建立授权 Windows capture 和容差化图像比较。 |

## 12. 执行顺序、事件与生命周期

| ID / 能力 | 官方语义摘要 | 等级 | 代码/测试证据路径 | 当前边界 | 下一验收门 |
|---|---|---|---|---|---|
| X01 Emitter → initializer → operator | 每帧先推进 schedule/spawn，再对新粒子初始化，对存活粒子运行 operator。 | `L2` | [SIM] [T-SIM] | 阶段顺序已写入代码，但现有结果测试没有锁定同帧 birth/update 边界；也没有 collision/event/children 阶段。 | 同帧 birth/update 边界与 Windows 状态 golden。 |
| X02 Collision/death/spawn events | operator 后处理碰撞、死亡、spawn/follow 事件。 | `L3` | [SIM] [CHILD] [T-SIM] [T-RUN] | birth 与 natural-death queue 按 fixed step 收集 typed final state 并 drain；collision、delete、follow event 不存在。 | collision/delete 顺序、同帧递归限制和 fixture。 |
| X03 Child/control point update | 事件后更新 child systems 和动态 CP。 | `L3` | [SIM] [CHILD] [CHILD-EXPAND] [CHILD-LIFE] [RUN] [T-RUN] | strict child systems 分深度每帧更新并回收：depth-one 先推进并收集 per-system 事件，depth-two 随后消费（跨层事件按帧串行传播），Event Follow 分别以 root 粒子与 (parent system, 粒子) 更新 origin 并随 parent 消失回收；General world-space child 为每个 birth 固定当时 system origin，不再拖动旧粒子。动态 CP 与跨空间 mapping 未实现。 | 动态 CP、跨空间 mapping 与 Windows frame-order 门。 |
| X04 Renderer-specific geometry | 最后按 Sprite/Trail/Rope 类型生成不同 geometry。 | `L3` | [RUN] [GPU] [TRAIL] [T-GPU] | 只有 Sprite 和单 quad Sprite Trail；Rope 缺失。 | renderer 多输出和 Rope topology 门。 |
| X05 Scene render order | 粒子 batch 应遵守 Scene layer render order。 | `L3` | [RUN] [T-RUN] | 初始化时固定排序；live reorder 依赖重建。 | 动态 visibility/order 和 effect 前后关系门。 |
| X06 GPU instance-buffer lifecycle | 每帧更新实例数据，in-flight buffer 不得被覆盖。 | `L3` | [RUN] [GPU] [T-GPU] | 有 slot completion 门；没有长稳内存预算。 | 10 分钟压力、切换/resize 和峰值预算。 |
| X07 Frame delta clamp | 实时卡顿时 catch-up 必须有上限，避免无限模拟。 | `L2` | [PLAY] [SIM] [T-SIM] | 外层夹 0.25 秒但没有 clamp 定向测试，也未记录 dropped time。 | clamp 数值断言、telemetry、pause/discontinuity 与不同 FPS 门。 |
| X08 Maximum budget | `max count` 与全局硬上限约束 CPU/GPU 粒子数。 | `L3` | [SIM] [CHILD] [CHILD-EXPAND] [RUN] [T-SIM] [T-RUN] | 普通系统有单系统上限；root child runtime 每深度 64 systems、跨两层共 128 systems/131,072 capacity 聚合上限，depth-two 超限有独立诊断与合成门。仍没有 collision 阶段预算与 frame-time 退化策略。 | 退化策略和 frame-time 压力门。 |
| X09 Prewarm budget | prewarm 不能无界阻塞加载。 | `L2` | [SIM] [T-SIM] | 普通 prewarm 有测试，但 240-step 上限没有压力断言，大 duration 还会改变 step size。 | 固定 step + dropped prewarm 策略与加载耗时门。 |
| X10 Pause/sleep/display change | 暂停、睡眠和屏幕变化不得继续发射或突然追帧。 | `L0` | [PLAY] [SIM] | 没有 particle-specific lifecycle 状态机。 | host lifecycle 注入和 count/time 负向测试。 |
| X11 Wallpaper switch/stop cleanup | stop 后 simulator、child、texture 和 GPU buffers 应归零。 | `L2` | [RUN] [PLAY] [GPU] | 依赖对象释放和 Metal completion；无专门资源归零测试。 | 多次切换后的 active layer/buffer/texture/内存门。 |
| X12 Realtime/offline equivalence | 实时与离线 bake 应复用同一 simulator、seed 和 renderer。 | `L0` | [SIM] [PLAY] | 有 fixed step primitive，没有 offline adapter。 | 固定 clock/seed/input fixture 和逐帧 hash 门。 |
| X13 Audio/media determinism | 音频或外部 provider 必须以可注入 frame snapshot 驱动。 | `L1` | [SUP] [T-SIM] | 可注入 frame snapshot 已存在且有确定性门（同输入同输出），但粒子 simulation 尚未消费。 | 接入时须明确：每个 fixed simulation step 读取该帧开始时的快照，同帧内所有 step 用同一值、跨帧不插值，否则 determinism 门不成立。 |

## 13. 当前统计与使用规则

- 本台账共覆盖 `171` 个粒子能力项：General 18、Emitter 17、Initializer 18、Operator 29、Renderer 14、Control Point 12、Children 12、Instance Override 16、Material 22、执行/生命周期 13。
- 等级分布为 `L0 23 / L1 43 / L2 26 / L3 79 / L4 0`；该数字按表内 171 个能力行重新计数，I17 本批由 `L1` 移到 `L3`。`L3` 主要集中在 Sphere/Box、常见 exponent-biased random initializer、基础 movement/change/lifetime Alpha/Size oscillation、非音频 Turbulence、Sprite/Sprite Trail、strict static/event child、已测试的静态 override、TEX sampler/mip、两种 blend 和 strict REFRACT 双槽子集。
- 当前固定矩阵的“可见粒子 76/76”、完整矩阵的“127/130”、`3088601835` 的“19/19”与 `3750813609` 的“9/9”只是 root layer 样本运行门，不是上述 171 项的兼容率；完整门另有 13 个初始 REFRACT root batch，`2131872317` 的 event-death child REFRACT 由延迟 runtime 门计证。剩余 3 个 full45 root 缺口均为 Rope/RopeTrail；动态 world-space、depth-three 或其他 fail-closed declaration 不能计为可播放。
- `7b1d36f` 的 Turbulence 定向门覆盖 5 个隔离真实样本、此前 19 个当前加载缺口中的 14 个图层；`d19e76b` / `d792296` / `f4e8a0c` 的 sampler/distribution/mip 门覆盖 E-PARTICLE 所列定向样本。它们都没有重跑 fixed13/full45，因此不能把 `8f4cd30` 的两层统一门写成新实现的回归结论。
- 开发批次应优先消除公共断点：复用现有 per-surface typed snapshot 接入动态 Control Point 与 author allow gates，再补 Layer Image、剩余 Children/Event、Collision 和 Rope，最后扩展动态 world-space、audio/material/lighting。逐样本 hardcode、把 unsupported 静默回退成 Sprite/translucent、或把程序纹理称为官方资产，都不允许升级等级。
- 任一条目升级时，必须同时更新本表的等级、边界、证据路径和下一验收门；只有跑过对应正向、负向、生命周期测试后才能从 `L2` 升到 `L3`。
