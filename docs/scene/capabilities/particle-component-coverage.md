# Particle 当前组件与执行边界

<!-- document-role: current-state -->

<a id="simulation"></a>
## 准备、模拟与空间

DefinitionParser 保作者顺序和未知字段；原组件 owner 准备 emitter/initializer/operator、control point、child 和 renderer 计划。每屏 PlaybackState 拥有模拟器、RNG、活动实例和轨迹历史，Session cadence 推进一次；View/GPU 重试不重新出生、执行事件或模拟。

root local/world、layer/world/camera、attachment 与 child space 分别保身份。共享 canonical world/camera 供 emission 和 draw 使用，不能每粒子重解层级、把 Pointer force 的 reference origin 混作发射源，或用 abs/clamp 猜坐标。

执行按准备好的作者顺序处理发射、初始化、操作、运动/死亡和 child，再产实例值与 draw batch。prewarm 执行真实模拟，不只移动 clock。snapshot/restore 属于原 CPU state，不复制 GPU 上传状态。

源码：[Runtime](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRuntime.swift)、[PlaybackState](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticlePlaybackState.swift)。

<a id="components"></a>
## 当前组件面

| 组件 | 已有执行路径 | 限制 |
|---|---|---|
| Emitters | 已准入的有序发射/连续与一次性出生，Sphere/Box 等原 emitter 计划 | flags、空间、audio、CP 和 instance override 必须满足该计划，不能从组件名推全参数支持 |
| Initializers | 位置、速度、旋转、尺寸、寿命、颜色、sequence 等 typed writer | 后写者及 General override 保作者顺序；未知字段只影响相关组件；HSV/Mirror/Position Around 等仍有未资格组合 |
| Operators | movement、gravity/力、颜色/alpha/size/旋转、noise、Remap、Vortex、Plane Collision 等原计划 | 不支持操作不假装执行；与 child、CP、世界空间和 lifecycle blend 分别限定 |
| Control Points | 0…7 typed identity、已接入的静态/动态位置与 emitter/force consumer | 按 authored ID 而非数组位置；CP0/system origin 与其他 world source 不混用，未知 flags/angles/parent 不猜 |
| Instance overrides | 已有颜色、发射、速度、播放及 typed 动态输入 | 新生 writer 与存量粒子不同；不以新属性自动改写既有粒子 |

<a id="operators"></a>
## 需要保留的数值边界

- Remap 复用原 `SceneParticleRemapValue`：有界 velocity/simplex 与 scalar-speed/fbm 路径分别准备；显式输入通道、其他操作和生命周期 blends 不借已有路径开放。
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

CPU batch 不持可写 instance buffer。原 ParticleMetalPipeline 按 root/child-template key 拥有上传 slot，形成 frame-local PreparedBatch；prepare/upload/draw/arm/cancel 由同一 GPU owner 管理。在途 buffer 与 depth/refraction pin 随真实 command 终态释放。

Surface 采用新 topology 才退出死 root/child GPU key；重建构造前过滤 committed 死 root。未提交取消释放其 slot，已提交不能用 CPU 回滚撤销。hidden 不等于退休，peer key 可复用。

材质剔除由原 Metal raster 状态消费：`normal` 编译为 back-cull，`noCull` 保双面，共用已有三角绕序与 vertex。其资格不依赖 renderer 名称或 REFRACT 组合，不改变相机、basis、尺寸与变换、纹理 UV、snapshot 或输出 owner。镜像是否翻面按实际几何投影决定，不改 front-facing 补偿作者变换。

alpha-to-coverage、原生相机继承、只读深度和 REFRACT 均有各自实际 material/geometry 资格；深度仍由原 camera/attachment owner 决定，不支持的组合局部不可用，不能伪造 blend、normal 纹理槽、资源或深度屏障。

<a id="playback"></a>
## 播放命令

`play/pause/stop/isPlaying/emitParticles` 沿原 typed handle 和 PlaybackState 生效。pause 保实例，stop 清其活动播放/出生；显式 emit 的参数与 transform 取调用点，不能被稍后的 callback 返回值追改。同 cadence 的命令、GPU deferred 和缺 drawable 不得重放出生。

新 Surface、重建、暂停恢复、退出与失败延续原 Scene clock/transaction，不另建粒子播放时钟。完整 Sound/media/UI 不属于 Particle 的输出 owner。

<a id="limits"></a>
## 当前缺口与回归

mapsequencebetweencontrolpoints、更多 CP 约束、Mirror、复杂 nested/event/非均匀 child 变换、Collision Bounds 与部分 Vortex/HSV/Position Around 数值仍有未实现或待资格边界。不能以非空 batch 或门禁通过替代方向、数量、相位和官方像素。普通粒子额外 combo 与用户材质输入尚无通用 shader 执行合同；通过 raster 状态编译不能作为这些输入已被消费的证据。

最近行为入口：[真实 CPU runtime](../../../script/tests/test_scene_particle_runtime.py)、[事务](../../../script/tests/test_scene_particle_playback_transaction.py)、[Metal renderer](../../../script/tests/test_scene_particle_rendering.py)、[App 生命周期](../../../script/tests/test_scene_particle_playback_integration.py)。具体下一资格见[队列](../roadmap/scene-open-breakpoint-queue.md)。
