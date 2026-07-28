# 官方客户端 changelog 取证（REV 3943-4401）

审查日期：2026-07-26
取证快照：Wallpaper Engine 2.8.42 `ui/dist/scripts/scripts.js` 内嵌变更日志
审查方式：只读静态提取，459 个 revision / 741 条变更 / 45 KB 正文

> 官方在编辑器 UI 脚本里内嵌了逐版本变更日志：`assets/**` 只给出当前 build 的静态数据形态，changelog 给出「哪一版加了什么、改了什么、为什么改」。
>
> 它直接回答两个 `assets` 回答不了的问题：**某个字段缺席到底是作者没写还是官方主动删了**，以及**某个系统官方自己是怎么分解的**。

复现命令：

```bash
python3 script/extract_wallpaper_engine_client_evidence.py --client-root ~/Downloads/wallpaper_engine --output-dir <生成物目录>
```

输出 `changelog.json` 含每个 revision 的 headline、编号与逐条变更，并记录源文件 SHA-256 供版本变化比对。459 版 / 741 条的逐字全量已固化在 [changelog 全量附录](client-changelog-appendix.md)，查证个别条目时先查附录，无需回到官方客户端目录。

## 1. 结论先行

1. **SceneScript VM 是 V8，当前为 14.0**（REV 4260）。此前 [SceneScript 运行时实现层合同](scenescript-runtime-implementation-contract.md) §3 只能把 VM 选型收窄为「至少覆盖 ES2019 authoring surface」，并注明「JavaScriptCore 只是候选」；[Windows 官方客户端取证记录](../../reviews/windows-wallpaper-engine-2.8.42-scene-reference-audit-2026-07-25.md) §11 明确拒绝从 `scenescript32.dll` 已加载推断 VM。现在有 10 条独立条目（含 Android 平台 2 条）正面确认引擎侧就是 V8。
2. **官方会主动从 JSON 中删除等于默认值的字段**（REV 4148、REV 4366）。这意味着样本里字段缺席**不等于作者未声明**，parser 必须持有正确的默认值表；把「缺失」一律当「该能力关闭」会系统性偏离官方渲染结果。
3. **官方文字渲染是 MSDF（多通道有向距离场），不是位图栅格**（REV 4319-4367 共 19 条）。outline、drop shadow、blur 三类 text effect 都建立在 MSDF 之上。MyWallpaperX 当前的 CoreText 位图路径与官方是两套体系，这解释了字体保真为何难以对齐，也说明 outline/shadow 的 `L1` 不是「少写几行绘制代码」。
4. **shader pass / FBO / binding 的条件表达式共有四个比较运算符**：REV 4192 先落地 `ge`，REV 4193 补齐 `gt`、`le`、`lt`。项目 Graph 里 condition/function 一直只作为 blocker 存在，现在有了完整运算符集。
5. **REV 4256 不能被解读为「REFRACT 只降低不透明度、不是扭曲」**。它只说明：某些 profile 曾借 refraction feature 降低粒子不透明度而非制造位移，因此官方重新启用了 particle shader 的 framebuffer multiplication；同域 REV 4149/4252 及当前官方 Particle General 文档仍把 refraction 与 normal map/background distortion 关联。`e698c18` 因而实现 strict normal + framebuffer displacement 子集，同时保留未知 profile fail closed；精确乘法、位移和历史兼容分支仍需 Windows golden。
6. **粒子系统在 REV 4102-4112 被整体重构**，且 REV 4103 明确「changed new child config structure」。child 配置结构变过，跨版本样本可能带两种形态。
7. **static child 初始化必须计入 parent object transform**（REV 4120）。这条直接落在项目刚闭合的「有限 static origin translation」批次边界上。
8. 官方存在**按作品新旧分叉的行为开关**：REV 3967 的粒子颜色覆盖修复注明 "Only enabled for new wallpapers"，REV 3987 为「依赖旧 build 错误 eye z pos 的老作品」保留兼容。这与 [zcompat 取证](zcompat-backward-compatibility-forensics.md) 的 `maximumprojectid` 机制是同一类设计。

## 2. 语料与口径

| 项目 | 数值 |
|---|---:|
| revision 数 | 459 |
| 变更条目数 | 741 |
| revision 编号范围 | REV 3943 - REV 4401 |
| 正文字符数 | 45,353 |
| 过滤掉商店/工坊/移动端/构建脚本后的条目 | 677 |

**编号连续性**：459 个 revision 覆盖 3943-4401 的 459 个整数位，无缺号，因此这是该区间的完整记录，不是抽样。区间之外（REV 3942 及更早）的记录不在本地安装包内。

**口径警告**：changelog 陈述的是「做过什么改动」，不是完整算法规范。一条 "Added X" 证明能力 X 存在且在该版本引入，不证明 X 的参数域、默认值或数值行为。所有引用必须与 `assets/**` 的静态数据或运行门交叉验证后才能进入实现。

**证据等级**：A（正版安装中的结构化文件直接确认，标度同 [Windows 官方客户端取证记录](../../reviews/windows-wallpaper-engine-2.8.42-scene-reference-audit-2026-07-25.md) §2）。由 changelog 文字推断出的运行时语义为该标度的 C 级，本文逐条标注。

## 3. SceneScript 与 V8

| REV | 官方原文 | 对 MyWallpaperX 的含义 |
|---|---|---|
| 4260 | Updated V8 to 14.0. | VM 身份与版本的正面证据 |
| 4276 | Added v8 diff for windows. / Updated code for new v8 version compatibility. | 官方对 V8 打过补丁，不是原样嵌入 |
| 4288 | Added v8 script env to reduce string object overhead. | 每脚本独立 V8 环境 |
| 4283 | Optimized V8 interface usage. | — |
| 4312 | Improved V8 read vec/string binding speed. | Vec/字符串跨边界绑定是热路径 |
| 4399 | Enabled minidumps on breakpoint crashes from V8. | — |
| 4400 | Added manual synchronization for NewDefaultAllocator because this is messed up in v8's design. | 宿主自己管 V8 allocator 同步 |
| 4285 | Added definition of scenescript component lifecycle hooks. | component 级生命周期钩子是独立于 layer 的一套 |
| 4286 | Added script batch locking to many lifecycle hooks. | 生命周期钩子内的写操作被批量加锁，暗示同帧原子性合同 |
| 4195 | Added applyGeneralSettings script callback to read a couple of general settings in scene wallpaper scripts. | 该回调的引入点；[SceneScript API 覆盖表](scenescript-api-coverage.md) 已收录，其「当前主要是 language」的描述与 REV 4240 一致 |
| 4203 | Improved general settings scene event. | — |
| 4240 | Reduced general settings callback to language only. | `applyGeneralSettings` 的载荷后来被收窄到 language |
| 4290 | Added user property cache against misuse of engine.userProperties. | `engine.userProperties` 有缓存层，反复读不穿透到宿主 |
| 4290 | Added precache system for registerAsset. | `registerAsset` 有预缓存阶段 |
| 4308 | Added support for numbers in min/max for all script Vec classes. | `Vec.min/max` 接受标量，与 [实现层合同](scenescript-runtime-implementation-contract.md) 的标量广播行为一致 |
| 4283 | Added createModelData, updateModelData and destroyModelData script functions to create layers with custom geometry. | 脚本可创建自定义几何图层 |
| 4285 | Changed model data script interface to be part of modal data object. | — |
| 4355 | Disallowed IModelData.replace in update(). | 生命周期阶段限制：`replace` 不能在 `update()` 内调用 |
| 4364 | Renamed modeldata update/replace to applyData/replaceData. | API 更名，跨版本脚本可能用旧名 |
| 4361 | Added ability to create model data with shortcut without shapes array. | — |
| 4302 | Made it possible to create a model layer directly from a model data object. | — |
| 4287 | Adding vertexformat constants to IModelData. | — |
| 4301 | Cached some JS utility handles in createLayer. | `createLayer` 是官方 API |
| 4293 | Removed render target check on effectlayer causing texture map to fill up because this looks like a memory leak when spamming layers in a script. | 脚本可批量创建 effect layer，RT 生命周期必须能承受 |
| 4207 | Added system command user property to open custom files/application/websites from a scene wallpaper. | `usershortcut` 属性的能力面 |
| 4208 | Added security warning to text inputs for system commands. | 官方自己给这条能力加了安全警告 |
| 4213 | Renamed system command to user shortcut. engine.openUserShortcut for scripts and changed property type to usershortcut. | 属性类型名与脚本 API 的确切拼写 |
| 4227 | Added file member to user shortcut info in scenescript. | — |
| 4218 | Fixed user shortcut script scope closing too early when hitting multiple layers. | — |
| 4323 | Added scripted layer asset tag for any type of layer that has scripts. | 「含脚本的图层」是一个可查询标签 |
| 4117 | Fixed 3D cursor scene script position. | cursor 在 3D 场景有独立坐标合同 |
| 3989 | Fixed scene script storage to use absolute path for hash from virtual file system instead of local path. | 脚本持久化存储按 VFS 绝对路径哈希分桶 |
| 4327 / 4318 / 4299 / 4291 / 4321 | Updated script language defs. | 语言定义随版本演进，`lib.sceneScript.d.ts` 是快照不是恒定合同 |

**当前落差**：项目 SceneScript source/VM/API 全线 `L0`，`usershortcut` 为 `L0`。本节把 VM 选型问题从「候选」变成「已知目标」，但仍不解决沙箱、预算与 API 表面的实现工作。

## 4. 文字与字体：官方是 MSDF 管线

| REV | 官方原文 | 含义 |
|---|---|---|
| 4319 | Added msdfgen for advanced font rendering. | 引入 msdfgen 作为字形生成器 |
| 4344 | Added msdfgen license. | — |
| 4330 | Split color and mono fonts in font manager. | 彩色字体与单色字体走两条路径 |
| 4332 | Made color fonts skip msdf path and render in second color pass again. | 彩色字体不走 MSDF，改第二个颜色 pass |
| 4333 | Added approximate bitmap to msdf conversion fallback for color fonts. | 彩色字体有 bitmap→MSDF 近似回退 |
| 4334 | Progress on supporting color fonts with msdf through bitmap conversion trick. | — |
| 4335 | Improved font color buffer quality by scaling color texture resolution with font size approximately. | 颜色纹理分辨率随字号缩放 |
| 4336 | Made one msdf texture shared across multiple font sizes and added on-demand color textures based on scaling multiplier. | **单张 MSDF atlas 跨字号共享**，这是 MSDF 的核心收益 |
| 4337 | Added contour winding fix for user fonts in msdf. | 用户字体轮廓绕向需要修正 |
| 4339 | Added character bbox cache to speed up text generation on known characters. | 逐字符 bbox 缓存 |
| 4340 | Added outline rendering support to msdf fonts. | outline 建在 MSDF 上 |
| 4341 | Added stubs for font drop shadow. / Added font blur. | — |
| 4342 | Added drop shadow to msdf fonts. | — |
| 4343 | Implemented all msdf font effects. | outline/shadow/blur 成套 |
| 4348 | Fixed unused padding in msdf atlas. | atlas 有 padding 语义 |
| 4349 | Adjusted font fx limit values. | text effect 参数有上限 |
| 4350 | Renamed msdf font option. | 存在一个作者可见的 msdf 开关字段 |
| 4366 | Added drop shadow opacity. | drop shadow 有独立 opacity |
| 4367 | Made msdf font rasterization scaling dependent on global face size instead of character bbox. | **缩放基准是 global face size，不是逐字符 bbox** |
| 4346 | Split text padding into two axes. | padding 从单值变双轴 |
| 4347 | Added font x/y spacing customization. | 字距/行距可分轴自定义 |
| 4338 | Optimizing font manager. | — |

**当前落差**：项目 [coverage-ledger](coverage-ledger.md) 的 `outline/shadow/text effects` 为 `L1`，`baseline/alignment` 为 `L2`。本节说明官方这三类效果不是叠加在位图上的后处理，而是 MSDF 距离场的直接产物。项目若继续用 CoreText 位图，outline/shadow 只能做形似近似，且必须在文档中标为非官方算法；若要对齐，需要独立引入距离场字形生成。两条路都不是本批次能闭合的，本文只固定这个判据。

`padding` 双轴与 `x/y spacing` 是可以先于 MSDF 落地的字段级能力，与现有 `limitrows`/`maxwidth` 同属 CoreText 阶段可消费的范围。

## 5. Render Graph、FBO 与 compose

| REV | 官方原文 | 含义 |
|---|---|---|
| 4192 | Added complex condition support to shader passes, FBOs, bindings (only supporting ge operator for now). | 条件表达式作用于 **pass / FBO / binding 三处**，首版只有 `ge` |
| 4193 | Added gt, le, lt condition operators to passes etc. | 运算符集补齐为 `ge`/`gt`/`le`/`lt`；未出现 `eq`/`ne` |
| 4079 | Allow nameless FBO creation without insertion in map. | 无名 FBO 合法，且**不进入名字映射表**——不能假定每个 FBO 都有可引用的名字 |
| 4126 | Made it possible to control clamp uvs and no interp for render targets when bound to a different material. | RT 被别的 material 绑定时，clamp UV 与 no-interp 可独立控制 |
| 4237 | Fixed effect layer shared render target collisions with parents that use prerendering. | 存在 **prerendering** 概念：父层预渲染时 effect layer 会与之共享 RT |
| 4293 | Removed render target check on effectlayer causing texture map to fill up. | — |
| 4293 | Inherited interpolation flag to user textures. | 插值标志沿继承链传播 |
| 3996 | Added render target layer name to texture input. | texture input 可按 RT 图层名引用 |
| 3960 | Fixed compose layer without effects not rendering transparently with copy background disabled and children pre-rendered. | compose 层的三个正交开关：有无 effect、copy background、children 是否预渲染 |
| 3963 | Fixed precomposed children not rendering last effect pass with alpha writing enabled. | 预合成子层 + alpha writing 的边界 |
| 3964 | Disabled compose layer children alpha writing on compose layers with background copy. | **background copy 打开时子层 alpha writing 被关闭** |
| 3961 | Fixed compose layer condition to disable puppet support on them. | compose 层不支持 puppet |
| 4040 | Potentially fixed flipped rendering of complex composition setups. | 复杂 composition 有翻转问题史 |
| 3962 | Hide parallax settings on child layers since the parent element controls parallax in this case. | **子层不独立持有 parallax，由父元素控制** |
| 4245 | Added new g_LayerModelMatrix constant to access unmodified model transform in effects. | 新增 shader built-in：effect 内可取未经修改的 layer model 矩阵 |
| 4155 | Added stubs to make depth buffer readable in shaders. | — |
| 4052 | Added stubs for additional depth formats. | — |
| 4146 | Changed swap chain mode to flip sequential. | 呈现模式，非 Scene 语义 |
| 4055 / 4059 / 4069 | Reverse Z depth buffer（experimental → toggle → desktop 启用）。 | 3D 场景深度精度策略 |
| 4142 | Fixed z shadow projection switch for reverse depth in cascaded shadow maps. | 官方有级联阴影贴图 |
| 4027 / 4028 / 4036 / 4054 / 4056 / 3968-3997 系列 | nested clipping masks、compose 顺序、a2c prerender、alpha 边界优化。 | **clipping mask 是一套独立子系统**，项目完全未建模 |
| 3987 | Doubled z render range for orthogonal projection to fix old wallpapers that were relying on incorrect eye z pos on older builds. | 正交投影 z 范围曾翻倍，且是为兼容老作品 |

**当前落差**：项目 `Generic FBO command graph` 为 `L2`，condition/function 是明确 blocker。本节把 condition 的运算符集、无名 FBO 的合法性、compose 三开关正交性和 prerendering 概念固定下来，这些是 B2 批次继续推进 generic compose 时的直接输入。

## 6. Shader 编译与预处理

| REV | 官方原文 | 含义 |
|---|---|---|
| 4283 | Overhauled shader precompiler to run faster and handle certain complex directive setups more correctly. | 官方有独立的 shader 预编译器，且处理复杂指令组合 |
| 4284 | Further progress on improving shader precompiler. / Optimized hlsl translator. | **官方自己有 HLSL translator**，不是直接喂 D3DCompiler |
| 4357 | Added #undef support to custom preprocessor. | 自定义预处理器支持 `#undef`；不是标准 C 预处理器的完整实现 |
| 4286 | Disabled multiline comment flatten in texture and combo parser because this also runs on cached files and needs to be as fast as possible. | **texture/combo 注解解析器不做多行注释展平**，只按行处理——与项目按行解析 `[COMBO]` 注解的做法一致 |
| 4218 | Added ability to set custom property order for shader parameters in editor. | shader 参数有作者定义的显示顺序 |
| 4008 | Added material src exclude. | material 可排除源文件 |
| 3982 | Added masked default shader snippet to shader editor. / Added sampler generator to shader editor. | — |
| 4059 | Fixed variant conditions with combos not triggering texture reload based on current value. | combo 值变化会触发纹理重载 |
| 4352 | Refactoring all model shaders with normal matrix uniform and removing redundant normal vector transforms. | model shader 有独立 normal matrix uniform |
| 4329 | Fixed normal mapping tangent space on modular shaders. | 存在「modular shaders」 |
| 4296 | Fixed reflection map not working in chroma/veg/fur shaders. | chroma/veg/fur 是三类专用 shader |

**当前落差**：项目 `Shader source/include/annotation/declaration contract` 为 `L1`，无 include expansion、macro/permutation preprocessor。REV 4286 给了一条可直接采纳的实现判据：注解解析按行、不展平多行注释。REV 4284 说明官方跨后端方案是自建翻译器，与 [Shader source 前置合同](shader-prelude-and-backend-abstraction.md) 的跨后端假设一致。

## 7. 粒子系统

粒子是 changelog 中占比最大的域（111 条命中）。分子域列出。

### 7.1 架构与性能

| REV | 官方原文 | 含义 |
|---|---|---|
| 4093 | Added particle format system to improve performance by skipping unneeded particle components. | **particle format**：按声明跳过不用的组件。REV 4196 进一步说明「如果 particle format 没用到 rotation 就禁用碰撞旋转行为」——format 是运行时能力裁剪的依据 |
| 4102 | Began refactoring particle system classes to reduce JSON parsing and make child particles more lightweight. | 重构起点 |
| 4103 | Changed new child config structure. | **child 配置结构发生过变更** |
| 4104-4112 | Progress on particle refactor.（9 条） | 重构跨 9 个 revision |
| 4285 | Removed manual double buffering for particles. | — |
| 4305 / 4307 | Particle system optimization. | — |
| 3985 | Added JSON cache to improve child particle system instantiation time. | child 实例化曾是热点 |
| 4089 | Removed some json copies from child particle instantiation. | — |
| 4091 | Caching finished child particles for re-emission instead of creating new instances. | **child 死亡后被缓存复用，不是销毁重建** |
| 4119 | Added child particle precaching. | — |
| 4047 | Reverted particle system child preload attempt again. | 预加载尝试被回退 |
| 4172 | Limited framebuffer updates to one per particle system. | 每个粒子系统每帧最多一次 framebuffer 更新 |

### 7.2 时间步进与低帧率行为

| REV | 官方原文 | 含义 |
|---|---|---|
| 3968 | Changed acceleration/deceleration in particle operators to use dampened dt for more consistent behavior with low fps. | **operator 的加减速用阻尼 dt**，不是裸 dt |
| 3968 | Fixed particle drag becoming to large and inverting velocity under low fps. | drag 在大 dt 下会反转速度，官方专门修过 |
| 4300 | Fixed bone physics glitchyness with inconsistent frame times. | 同类问题在骨骼物理上的表现 |
| 3986 / 3972 | Fixed sprite trail fps length adjustment / length fps compensation. | **sprite trail 长度需要按 fps 补偿** |
| 4124 | Made rope uv scroll assume that emitter rate is limited to FPS when deciding if max length is reached. | rope UV 滚动假定发射率受 FPS 限制 |
| 4125 | Disabled uv smoothing on rope particles that emit more particles than expected each frame. | — |

**当前落差**：项目粒子已有 fixed simulation step 与 deterministic seed（`L3`），但 `Delta clamp/prewarm cap` 为 `L2`、缺定向预算断言。本节说明官方在低帧率下对 operator 做的是**阻尼 dt** 而非简单钳制，且 sprite trail 长度有独立的 fps 补偿——这两条都是项目现有实现未覆盖的数值语义。

### 7.3 Emitter

| REV | 官方原文 | 含义 |
|---|---|---|
| 4066 | Added particle initial emission delay. | `delay` 字段的引入点 |
| 4066 | Added particle emitter random periodic emission settings. | periodic 发射带随机化 |
| 4066 | Fixed particle emission duration only decreasing on emission frames. | **duration 只在发射帧递减** |
| 4114 | Fixed emitter duration not decaying when max particle count is hit. | 命中 maxcount 时 duration 的衰减行为 |
| 4125 | Made periodic emission reset instant particles. | periodic 周期会重置 instantaneous 粒子 |
| 4125 | Added option to limit periodic emission count for each period when rate emission is used. | 每周期计数上限 |
| 4142 | Made periodic emission limit scale with particle instance count. | 周期上限随 instance count 缩放 |
| 4148 | Fixed particle emission stopping when rate becomes 0 due to instance multiplier. | instance multiplier 可把 rate 压到 0 |
| 4162 | Improved sphere emitter cone control. | — |
| 4077 | Changed sphere emitter coords to allow cone angle adjustment along x axis. | sphere emitter 的 cone 沿 x 轴可调 |
| 4080-4085 | Layer image emitter：emission mask、offset、random velocity、inherit layer motion、model bind pose、child 支持。 | **Layer Image emitter 是完整能力**，项目当前为 `L1`（仅名称可诊断） |
| 4079 | Progress on effect layer particle emitter. | 另有 effect layer emitter |

### 7.4 Initializer

| REV | 官方原文 | 含义 |
|---|---|---|
| 4129-4133 | Remap initial value element（stubs → 完成）。 | remap 系列的引入 |
| 4135 | Added remap transform functions. / Added global variables to remap elements. / New 2D simplex SSE noise generator. | remap 有 transform function 与全局变量 |
| 4172 | Added clamp output value to remap elements. / Added random seed to remap noise transforms. | 输出钳制与随机种子 |
| 4295 | Fixed a bug in REMAP_VALUE_OPTION_SCALAR_POSITION_BETWEEN_TWO_CONTROL_POINTS. | 官方内部常量名，指示 remap 的一个具体选项 |
| 4143 / 4144 | Added color list initializer. / Added particle instance control for color list initializer. | `colorlist` 的引入与 instance 控制 |
| 4086 | Added random HSV color initializer. | `hsvcolorrandom` 的引入 |
| 4115 | Made HSV color initializer dependent on instance color. | HSV 初始化依赖 instance color |
| 4088 | Added inherit control point velocity initializer. | `inheritcontrolpointvelocity` |
| 4126 | Added fbm position offset initializer. | fbm 版本的位置偏移 |
| 4154 | Added inherit value from event initializer and operator. | `inheritvaluefromevent` 同时是 initializer 和 operator |
| 4153 | Added prototype for inherit event value initializer/operator. | — |
| 4142 | Added a flag to scale map initializers to scale with particle instance count. | map 系列有 instance 缩放开关 |
| 4125 | Changed map sequence initializers to match their number with instant emission count. | — |
| 4218 | Added proper default values for size random initializer in 2D scenes. | **2D 场景的 size random 有专属默认值** |
| 4099 | New particle default values for 3D scenes. | 3D 场景另有一套默认值 |

### 7.5 Operator

| REV | 官方原文 | 含义 |
|---|---|---|
| 4064 / 4065 | Particle boids operator（prototype → SIMD 实现）。 | — |
| 4153 | Changed boids speed cap to allow higher velocity if it was previously above cap. | 速度上限不回拉已超速粒子 |
| 4096 | Added cap velocity operator. | `capvelocity` |
| 4096 | Added operator blending to angular movement, oscillate pos, oscillate size, control point attract, turbulence, vortex. | **六个 operator 支持 blending**（对应字段 `blendinstart/end`） |
| 4139 | Added remap operator blending support. | — |
| 4137 | Finished remap operator. / 4138 Added min/max to remap vector component selection. | — |
| 4125 | Added maintain distance between two control points and reduce movement near control point operators. | 两个 CP 相关 operator 的引入 |
| 4151 | Improved vortex operator with ring shape, pull and maintain distance. | `vortex_v2` 的 ring 参数来源 |
| 4160 / 4163 | Fixed vortex operator infinite axis buffer setup / maintain distance with infinite axis. | vortex 轴可为无限 |
| 4092 | Improved control point attract deletion to be a bit more resilient for fast particles. | CP attract 带删除行为 |
| 4063 | Added control point auto deletion option when particle close to CP. | — |
| 4169 | Added lock distance to control point operator. | — |
| 4171 | Added particle movement operator option to apply gravity in worldspace. | movement 的重力可选世界空间 |
| 4021 | Added global scene gravity and wind settings. | **场景级重力与风**，不是逐 operator |
| 4049 | Fixed wind acceleration scaling. / 4023 Fixed wind 2d/depth vector construction. | 风有 2D/depth 分量构造 |
| 4098 | Added simulation skipping to boids and capsule collision operators to improve performance. | — |

### 7.6 Collision

| REV | 官方原文 | 含义 |
|---|---|---|
| 4067 | Added basic plane collision operator for particles. | 碰撞体系起点 |
| 4068 | Implemented multiple collision behaviors. | `collisionbehavior` 是多值枚举 |
| 4069 | Added particle sphere collision operator. / Added additional collision operator stubs. | — |
| 4070 | Added bounds collision operator. | `collisionbounds` |
| 4071 | Implemented collision quad operator. | `collisionquad` |
| 4096 | Added model capsule collider. | 胶囊碰撞体 |
| 4182 | Added basic static model particle collision based on geometry bounds. | 模型碰撞按几何包围盒 |
| 4176 | Added stop rotation on collision flag. | 碰撞可停止旋转 |
| 4196 | Fixed collision behavior not being applied through new template path for rotation controls. / Disabled collision rotation behavior if there is no rotation used by the particle format. | 碰撞旋转依赖 particle format 是否含 rotation |
| 4154 | Made collision plane and quad dependent on cp angles. | **plane/quad 碰撞体朝向由 control point angles 决定** |
| 4077 | Added lock to control point bindings to most particle collision operators. | 碰撞 operator 可锁到 CP |
| 4189 | Fixed plane collision visualization when control point is world space but system isn't. | CP 空间与 system 空间可以不一致 |
| 4116 | Reduced default model collision bounce. | 默认弹性系数变更 |

### 7.7 Control point

| REV | 官方原文 | 含义 |
|---|---|---|
| 4148 | Removed unmodified control points from particle config. | **未修改的 CP 会被写出流程删除**——样本里 CP 稀疏是官方行为，不是作者没配 |
| 4225 | Added default angles for control points. | CP 有默认 angles |
| 4154 | Added rotation support to control points. | CP 带旋转 |
| 4154 | Made emitters, vortex and map sequence around control point dependent on control point angles if applicable. | CP angles 影响 emitter、vortex、map sequence 三类消费者 |
| 4127 | Added option to inherit control point from parent system. | child 可继承父系统 CP |
| 4142 | Made control points of presets import relative to layer origin. | preset 导入时 CP 相对图层原点 |
| 4089 | Skip inactive control points in update functions. | CP 有 active 状态 |
| 4076 / 4155 / 4073 | CP 可视化与 gizmo 隐藏选项。 | 编辑器侧，非运行时 |
| 4382 | Fixed crash in particle control point parse. | CP 解析在 2.8.42 周期内仍在修 |

### 7.8 Child particle

| REV | 官方原文 | 含义 |
|---|---|---|
| 4120 | Fixed particle static child init not taking parent object transform into account. | **static child 初始化必须计入父对象 transform** |
| 4117 / 4122 / 4127 / 4141 | Improved/fixed child particle transforms（4 条）。 | child transform 是官方反复修正的区域 |
| 4127 | Added more options to disable various instance overrides for child particles. | child 可逐项禁用 instance override |
| 3948 | Added ability to disable color overrides on child particles. | — |
| 4117 | Made color modification re-evaluate for each child particle. | **颜色修改对每个 child 重新求值** |
| 4114 | Changed instance update to be applied to all allocated children and not dormant particles on revival. | instance 更新作用于已分配 child，不作用于复活中的休眠粒子 |
| 4175 | Fixed event particle restarting emission on inherited property change. | 继承属性变化不应重启发射 |
| 4004 | Fixed particle child prerender coordinate system for world particles. | world 粒子的 child 预渲染坐标系 |
| 4121 | Fixed child materials not reloading in main editor. | — |

**当前落差**：项目 child 执行为 strict depth-one 子集，static 要求零 angles、单位 scale、无 CP、probability=1。REV 4120 是与当前批次最直接相关的一条：官方 static child 初始化计入父对象 transform，项目当前只允许「有限 authored local origin translation」。REV 4103 的 child config 结构变更说明跨版本样本可能存在两种结构。

### 7.9 Renderer

| REV | 官方原文 | 含义 |
|---|---|---|
| 4172 | Added min length to sprite trail renderer. | `minlength` 引入点 |
| 4221 | Simpler description for sprite trail renderer. | — |
| 4148 | Fixed tangent space of sprite trail renderer. | trail 有切线空间 |
| 4061 | Fixed sprite renderer not working when sprite trail renderer has been added too. | **sprite 与 sprite trail 可同时存在** |
| 4101 | Changed particle rope renderer to use indices instead of moving data in vertex buffer around. | — |
| 4073 | Fixed geometry shader rope particle triangle winding. | rope 用 geometry shader（对应随包 `genericropeparticle.geom`） |
| 4059 | Fixed rope particle screen orientation per rope segment. | 逐段屏幕朝向 |
| 4108 | Fixed kinematics rope simulation not applying constraints in correct space to maintain lengths. | rope 是带约束的运动学模拟 |
| 4120 / 4123 / 4124 | Rope UV offset/scroll（自动 UV 偏移、动态偏移、max length 判定）。 | — |
| 4148 | Added uv scrolling option and uv multiplier to rope renderer. | `uvscrolling`/`uvscale` 引入点 |
| 4145 | Added normal mapping support to particle rope. | — |
| 4149 | Added refraction support to rope renderer. | — |
| 4164 / 4166 | Rope trail alpha and size fading for scrolling UVs（开始 → 完成）。 | `fadealpha` 语义 |
| 4140 | Added lighting support for particles. / Added two new basic particle normal maps for lighting. | 粒子有光照路径 |
| 4252 | Hide particle normal map texture without lighting/refraction. | **normal map 槽只在 lighting 或 refraction 开启时有意义** |
| 4150 / 4171 | Added cutout options to particle shaders. / Improved particle cutout shader option. | 粒子 shader 有 cutout 选项 |
| 4256 | Enabled shader framebuffer multiplication in particles again when refraction feature was used to reduce particle opacity instead of distortion. | 只证明“借 refraction feature 降 opacity”的 profile 需要 framebuffer multiplication；**不能反推全部 REFRACT 都没有 distortion** |
| 3956 | Disabled color override on fireworks refract particle to fix background tinting. | refract 粒子与颜色覆盖冲突 |
| 4152 | Changed example 3D particles to use translucent but not additive blending. | — |
| 4206 | Added hardware compression padding to texture sheets. | sprite sheet 有硬件压缩 padding |

### 7.10 颜色与 instance override

| REV | 官方原文 | 含义 |
|---|---|---|
| 3967 | Added fix to avoid applying particle user color override to initial color when any operators/initializers would already multiply the color. Only enabled for new wallpapers. | **按作品新旧分叉的行为**；颜色覆盖与 operator 乘法冲突时的官方裁决 |
| 3948 | Fixed some issues with particle color inheritance. | — |
| 4113 | Fixes for instance particle color and brightness. | — |
| 4117 | Disabled particle brightness inheritance when color modification is off. | brightness 继承依赖 color modification 开关 |
| 4179 | Disabled particle color override in hierarchy if root system doesn't apply override. | 层级中的覆盖依赖 root 是否应用覆盖 |
| 4086 | Fixed hdr brightness particle instance value sometimes not being applied on particle creation. | HDR brightness 是 instance 值 |
| 4159 | Fixed particle instance config not being applied on particle reload in editor. | — |

## 8. 纹理、资源与 Texture Variants

| REV | 官方原文 | 含义 |
|---|---|---|
| 3986 | Began working on texture variants. | Texture Variants 的引入点 |
| 3987 / 3988 / 3990 | Continued work / progress on texture variant implementation / blending. | variant 支持 blending |
| 3992 | Added video texture support to texture variant system. / Added texture replace function to texture variant UI. | variant 可含视频纹理 |
| 3994 | Disabled variant blend mode dropdown if format is unsupported. | variant blend mode 受格式约束 |
| 4018 | Made it possible to rename texture variant groups. | variant 有分组 |
| 4021 | Added error message when importing invalid variant texture. | — |
| 4045 / 4059 | Fixed texture variant not triggering reload when used with combos. | **variant 与 combo 联动触发重载** |
| 4059 | Fixed clean project function deleting texture variants. | — |
| 4205 | Fixed error texture for invalid external texture reference not being marked as missing anymore. | 无效外部引用有专门的 error texture 与 missing 标记 |
| 4177 | Added texture stubs to non-compiled texture loads. | 未编译纹理有 stub |
| 4254 | Fixed async texture loader not being able to handle 3D textures properly. | 存在 3D 纹理 |
| 4157 | Added 3d texture support to dxgi renderer. | 对应 `assets/materials/lut` 的 32³ LUT |
| 3965 | Changed async loader to block low priority tasks until scene main loader has processed all layers. | 加载优先级合同 |
| 3965 | Changed mip map streamer to load third detail level first. | **mip streamer 先加载第三级** |
| 4206 | Added hardware compression padding to texture sheets. | — |
| 4251 | Added clamp uvs option to texture import window. | — |
| 3948 | Added missing interpolation filter initialization for layers without reference texture. | 无参考纹理的图层需初始化插值滤波 |
| 4238 | Fixed handling of gif shortcut textures. | — |
| 4230 / 4242 | Media thumbnail 系列：uri thumbnail loading、自定义缩略图文件缓存、生成器锁定 256。 | `$mediaThumbnail` 的官方尺寸约束 |
| 4020 | Fixed light cookie texture being deleted while in use when media integration triggers a texture flush. | 媒体集成会触发纹理 flush |

**当前落差**：项目 Texture Variants 为 `L0`。本节给出该系统的完整能力面：分组、blending、视频纹理、combo 联动重载、格式约束。REV 4242 的「media thumbnail generator 锁定 256」是 `$mediaThumbnail` 尺寸的直接依据。

## 9. 场景后处理、颜色与 blend

| REV | 官方原文 | 含义 |
|---|---|---|
| 4157 | Added lut color correction to user post process image settings. | **LUT 色彩校正属于用户后处理设置** |
| 4158 | Added color correction user option to scenes. | 场景级颜色校正开关 |
| 4161 | Changed color correction to happen after basic color settings. | **顺序合同：基础颜色设置 → 色彩校正** |
| 4197 | Fixed lut options not being part of wallpaper defaults. | LUT 选项属于壁纸默认值 |
| 4198 / 4199 / 4200 | Added final LUTs / LUT materials。 | 对应 `assets/materials/lut` 的 28 个 3D 纹理 |
| 4201 | Added option to disable LUT back. | — |
| 4249 | Added neutral lut. | 存在中性 LUT |
| 4159 | Made luts compress to PNG to save space. | LUT 以 PNG 压缩存储 |
| 3983 | Added localization for blend modes. | blend mode 名称走 locale，见 [编辑器字符串表取证](editor-string-table-forensics.md) |
| 3982 | Added diffuse light blend mode to shader blend modes. | `Diffuse light` 是后加的模式 |
| 3995 | Added new blend modes to ogl. | — |
| 3996 | Fixed certain HSV blend modes in HDR. | HSV 系列 blend 在 HDR 下有特殊行为 |
| 4226 | Changed write alpha function in blend effects to perform proper alpha and color transition. | Blend effect 的 write-alpha 行为 |
| 4227 | Removed blendmode option from blend effects when writing alpha. | **写 alpha 时 blend mode 选项被移除**——两者互斥 |
| 4219 | Fixed blend transform not being scaled with texture reduction. | — |
| 3982 | added glitter effect. / 4019 Fixed glitter aspect ratio scaling. | Glitter 的引入与宽高比修正 |
| 4012 | Added new shimmer and cloud motion effects. | Shimmer/Cloud Motion 曾被重做 |
| 4013 / 4014 / 4015 | Added water caustics effect / 改进 / 更新 shimmer 与 caustics。 | Water Caustics 的引入 |
| 4041 / 4042 | Updated water flow effect（两次）。 | Water Flow 在 2.8.42 周期内改过两次 |
| 4040 | Cloud motion min values. / 4019 Fixed cloud motion angle. | — |
| 3958 | Fixed VHS effect mask. | VHS 有 mask 槽 |
| 4017 | Improved some effect value ranges. | effect 参数范围调整过 |
| 3982 | Added new perlin and uniform default textures. | 存在 perlin/uniform 默认纹理 |
| 4171 | Added new stock effects: vortex orb, color sparkle, rain splashes, water dripping/faucet/impact/droplets. | **新增 stock effect 名单**，对应 `assets/presets/water` 等目录 |
| 4187-4191 | Element preview videos、water/ember preset previews。 | 对应 `ui/dist/videos/previews` |
| 3998 | Changed light limit behavior to allow adding more lights and choosing light count and features based on distance. | 灯光按距离裁剪 |
| 3984 | Removed light limit and changed light system to render the closest lights only if light limit is reached. | — |
| 4175 | Fixed planar reflection rendering. | 存在平面反射 |
| 4029 | Added a snippet to generate new bokeh kernels. | — |

## 10. 视频纹理

| REV | 官方原文 | 含义 |
|---|---|---|
| 4254 | Added prototype for new dx11 video backend based on scene video texture system. | 视频后端建在 scene video texture 之上 |
| 4254 | Changed video textures to use keyed mutex. / use their own dedicated device and a shared texture for sync. | 跨设备共享纹理 + keyed mutex 同步 |
| 4254 | Updated video textures from scene thread instead of using a separate thread. | **视频纹理更新迁到 scene 线程** |
| 4254 | Added flip and lut wallpaper properties to video wallpapers. | — |
| 4388 | Close video texture update thread when paused. | 暂停时关闭更新线程 |
| 4387 | Added scene video present delay until first non fully black frame was received. | **首帧全黑时延迟呈现**——项目 embedded MP4 的首帧策略参考 |
| 4393 | Completely removed audio stream from video texture when audio disabled through custom source descriptor. | — |
| 4393 | Added async video restart on delayed open failure due to bad codecs in video. | — |
| 4255 | Added all known video extensions to user video texture loader. | — |
| 4236 | Fixed user shortcuts leading to video files being interpreted as user video textures. | — |
| 4258 | Changed dx11 video backend to keep render thread alive and process device loss logic inside render thread by entirely reloading the scene. | 设备丢失时整场重载 |

## 11. 音频

| REV | 官方原文 | 含义 |
|---|---|---|
| 4164 | Began working on sound spatialization. | — |
| 4167 | Implemented sound spatialization. | **Sound layer 有空间化** |
| 4168 | Added sound spatialization params. | 空间化带参数 |
| 4394 | Added new architecture to handle invalid audio streams in scene player and better fall back to other configurations asynchronously. | 音频流失败异步回退 |

**当前落差**：项目 `Sound layer` 为 `L0`，缺口写的是「补 sound content IR、播放、volume 和生命周期」。本节新增一项必须纳入的能力：空间化及其参数。

## 12. Puppet、模型与 clipping mask

| REV | 官方原文 | 含义 |
|---|---|---|
| 4020 / 4021 / 4022 | Rope IK simulation（实现 → 进展 → 完成）。 | Puppet 的 rope 是 IK 模拟 |
| 4009 / 4016 / 4005 / 4006 | IK 轴锁定、附加 IK 设置、blend rules。 | — |
| 4004 | Implemented support for multiple blend targets within a single expression. | 表达式可有多个 blend target |
| 4017 | Added origin only blend rule support. | — |
| 4057 | Fixed blend rules on generic kinematics bone chains. | — |
| 4010 | Added blend shape bone point and axis modulation. | blend shape 受骨点与轴调制 |
| 3974 | Added puppet depth auto generation using SDF. | **深度图可由 SDF 自动生成** |
| 3980 | Added depth factor to auto depth deformation generation. | — |
| 3971 | Moved shader bone animation data into separate buffer to only require single upload for entire model/puppet per frame. | 每帧单次骨骼数据上传 |
| 4312 | Optimized some remaining GLM matrix operations in skeletal animation system. / 4290 Improved performance of final skeleton composition after SIMD animation. | 骨骼合成在动画之后 |
| 3992 | Fixed puppet index range depth priority calculation during animation. | 动画期间的深度优先级 |
| 4002 | Made inverted masked puppet geometry draw in depth-order without pulling it down to the mask. | 反转遮罩几何的深度序 |
| 3967 | Fixed puppet texture blending texture scale correction for non-lighting pre-render case. | — |
| 3967 / 3968 / 3973 / 3975 / 3976 / 3984 / 3997 / 4026 / 4027 / 4028 / 4036 / 4054 / 4056 | Clipping mask 系列：实现、嵌套支持、渲染顺序、compose 系统、a2c prerender、alpha 边界优化、错误分析。 | **clipping mask 是独立子系统**，支持嵌套；项目完全未建模 |
| 3969 | Added additive blending option to clipping mask compositor. | — |
| 4037 | Added clipping mask pass count to stats. | — |
| 3973 | Fixed clipping mask render not using skinning. | 遮罩渲染参与蒙皮 |
| 4082 / 4098 | Added hitbox / capsule debug draw to puppets. | — |
| 4096 | Fixed model match loop angle precision due to faulty quaternion conversion in GLM. | 四元数转换精度问题史 |
| 3986 | Fixed default obj bone animation state when bones are scaled. | — |
| 4262 | Added more options for puppet warp animation baked smoothing. / 4248 experimental compiler puppet animations post smoothing. | 动画烘焙后平滑 |
| 4178 | Only load puppet ref if file exists on global file system. | — |
| 4283 | Added directories to asset window and ability to create custom materials (needed for dynamic models). | — |

## 13. 向后兼容与默认值裁剪

这一节是本文对 parser 影响最大的部分。

| REV | 官方原文 | 含义 |
|---|---|---|
| 4366 | Added some properties default removal rules from scene config to reduce json bloat. | **等于默认值的属性会被从 scene config 中删除** |
| 4148 | Removed unmodified control points from particle config. | 同一策略在粒子 CP 上的实例 |
| 3967 | ... Only enabled for new wallpapers. | 行为按作品新旧分叉 |
| 3987 | Doubled z render range for orthogonal projection to fix old wallpapers that were relying on incorrect eye z pos on older builds. | 为兼容依赖旧 bug 的作品而调整 |
| 3968 | Fixed default wallpaper properties being possible to be manipulated by pre-declaring them as user properties. | **作者曾能通过预声明同名用户属性劫持壁纸默认属性**；这是安全边界 |
| 4219 | Removed user shortcut properties from json sharing. | 用户快捷方式属性不进 JSON 分享 |
| 4197 | Fixed lut options not being part of wallpaper defaults. | — |
| 4369 | Fixed config version upgrade not setting old video player framework in correct location. | 存在 config 版本升级链 |

**对 MyWallpaperX 的直接后果**：

1. 「字段缺席」必须解释为「取默认值」，不能解释为「作者未启用」。项目现有的 `limitwidth: false` + `maxwidth: 500` 处理（只在开关打开时消费数值）正是这条规则的正确应用；其余字段需要逐项复核是否也存在「官方删默认值」导致的误判。
2. 项目 [开发硬规则](README.md#41-能力存在不等于启用) 的「能力存在不等于启用」仍然成立，但要与本条区分：**启用与否由显式开关决定，数值缺席则取默认值**。两者不是同一件事。
3. 官方存在按作品 ID / 发布时间的行为分叉，与 [zcompat](zcompat-backward-compatibility-forensics.md) 的 `maximumprojectid` 同源。项目若发现某样本行为与当前实现冲突，需要先判断是否属于这一类历史兼容，而不是直接改通用逻辑。

## 14. 本文不覆盖的域

以下条目在 741 条中占 64 条，与 Scene runtime 无关，不纳入取证：Steam 工坊/商店/播放列表 UI、CEF/Chromium 集成与补丁、Android/iOS/移动端、构建脚本与版本号、本地化更新、编辑器窗口布局与拖拽、桌面快捷方式图标解析、诊断与崩溃上报。

`ui/dist/scripts/scripts.js` 的其余部分是 AngularJS 编辑器逻辑。已实测：`depthtest`、`cullmode`、`pointsize`、`limitrows`、`maxrows`、`usershadervalues`、`constantshadervalues`、`eventspawn`、`inheritvaluefromevent`、`MDLV`、`TEXV` 等 Scene wire 字段在其中命中 0 次，因此**它不是 schema 校验或默认值的来源**，`getSharedDefaultProperties` 只返回 `alignment: 0`、`alignmentposition: 50`、`rate: 100`、`volume: 50`、`cameraparallax: true` 五个通用壁纸设置。这与 [SceneScript 实现层合同](scenescript-runtime-implementation-contract.md) §11 的「可能含属性 schema 校验与默认值」推测不符，该推测本文予以更正。

## 15. 不应从本文推出的结论

1. 不能因为某条 "Added X" 就认为 X 的参数域、默认值或数值行为已知；这些仍需 `assets/**` 静态数据或运行门确认。
2. 不能把 changelog 的实现顺序当作 MyWallpaperX 的实施顺序依据；官方顺序由其自身架构决定，项目仍按 [能力依赖图](capability-dependency-map.md) 推进。
3. 不能因为官方用 V8 就认为项目必须用 V8；这条只把「VM 至少要覆盖什么」变成「官方事实上是什么」，选型仍受 macOS 平台、安全沙箱与分发约束。
4. 不能因为官方用 MSDF 就把项目的 CoreText 路径记为错误实现；两者是不同取舍，但 outline/shadow 的等级和边界描述必须反映这个差异。
5. changelog 覆盖 REV 3943-4401，不代表这些能力的完整历史。更早引入的能力（如 Timeline、基础 effect 体系）不在区间内，缺席不构成任何结论。
6. 任何单条 changelog 都不能替代 Windows golden；本文不改变 [覆盖台账](coverage-ledger.md) 中任何一行的等级。
