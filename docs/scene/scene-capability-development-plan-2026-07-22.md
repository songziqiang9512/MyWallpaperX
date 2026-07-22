# Scene 播放能力开发计划

> 建立日期：2026-07-22
>
> 最近更新：2026-07-23（file-backed sceneTexture 第一切片、限时 bookmark 授权及最终 13 样本证据）
>
> 作用：定义 MyWallpaperX Scene runtime 从当前可审计子集向 Wallpaper Engine 常用能力逼近的实施顺序、样本门和验收标准。作者/执行语义先查 [`semantics/README.md`](semantics/README.md)；当前能力结论仍以 [`../reviews/web-scene-current-state-roadmap-2026-07-19.md`](../reviews/web-scene-current-state-roadmap-2026-07-19.md) 与最新运行证据为准；历史 memo 不反向覆盖本计划。

## 1. 目标与边界

目标不是宣称私有格式 100% 兼容，而是让常见 Windows Wallpaper Engine Scene 壁纸在 macOS 上达到可播放、可交互、可配置、可诊断和可持续回归的工程状态。

实现优先级由四项共同决定：

1. 真实 Workshop 样本命中频率；
2. 对首帧和主要视觉构成的影响；
3. 能否建立确定性自动验收；
4. 实现的来源、维护成本和安全边界。

不采用以下捷径：

- 不把 Scene 转成 Web 播放；
- 不按单个样本 ID 硬编码；
- 不把 route-only、占位 shader 或静态截图写成“效果已支持”；
- 不执行未知 SceneScript，也不直接加载来源不明的预编译 DirectX shader；
- 不直接修改真实 Workshop 样本。

## 2. 2026-07-23 当前代码事实

### 已真实进入运行链

- `project.json` / entry 同名 `gifscene.json` 识别、PKGV 索引、受控缓存解包、路径校验和 interpretation format 17；v17 在 v16 authored graph 语义上增加 provider/resource metadata，不改变既有 graph identity；
- PNG/JPEG、raw RGBA/RG/R8、BC1/BC2/BC3/BC5、LZ4、MP4 payload 和 TEX sprite sequence；
- Metal image/solid/text/particle 合成、父子 transform、有效可见性、source order、alpha、正交/透视粒子相机和桌面多屏宿主；
- cover 投影；Camera Parallax 服从 Scene options、显式逐层 depth、传播和属性 override；包括 composition 在内，缺失或零 depth 不产生逐层位移；
- legacy coarse blur 仍只服务尚未迁移的受限路径，采用全尺寸 RT + 4 倍 texel step 近似；v16 graph 已分别把 precise Blur 严格选路到固定两遍近似 kernel，并把 stock standard Blur 的默认 profile 选路到真实 4-pass、2 个 quarter RT、alpha-aware downsample、13-tap Gaussian 与默认 combine。标准 Bloom、normal-map waterripple、perspective+opacity、mode 9 additive，以及 water/cursor/chromatic/iris 等仍是明确标注的受限实现；
- 单个 built-in UV Foliage Sway 已读取作者 strength/speed/phase/power/noise/ratio/direction 和 mask 映射；多 foliage 栈与 vertex/workshop 变体不会误套该近似实现；
- 静态 text 当前以 authored `pointsize * 4` 近似 300 DPI point raster、处理 vector padding、包内字体、系统字体别名和缺失字体诊断；`* 4` 是样本验证近似，不是完整官方换算合同；
- 作者包内 2D sprite 粒子的 definition/resource graph、sphere/box、rate/burst/prewarm、常见 initializer/operator、sequence/random frame、additive/translucent、朝向、静态 override、CPU simulation 与 Metal instancing；已增加受限 built-in `particle/drop` 纹理和按速度对齐、按作者 length/min/max stretch 的 Sprite Trail；
- 用户属性定义、group/display condition/options、默认值/override、visibility/text/camera 与部分 effect target、按壁纸持久化、活动 Scene 受控重建和独立属性窗口；
- 当前实际执行的 `sceneTexture` key 支持 PNG/JPEG picker、按 wallpaper/property bookmark、同步 security-scope 解码、逐屏 Metal 上传、恢复作者默认和失败回退；隐藏但可通过其他属性显示的受支持 consumer 也会进入能力发现，播放时仍只执行当帧可见层；
- typed `composition/project/fullscreen` 与 generic dependency layer ID；对满足严格边界的 utility layer 执行当前 framebuffer 前缀捕获，并支持 `_rt_imageLayerComposite_<id>_a` named target 的有预算发布与 clipping consumer 绑定。`2902406982` 的 6 个 provider / 7 个 consumer binding 已闭合，原白色三角缺口不再由缺失 named target 产生；
- effect/material pass 的 typed user texture input 已保留；material resolver 对每个 sparse slot 按低到高优先级保存 `material asset -> material usertexture -> instance asset -> instance usertexture -> explicit graph bind` 候选链，现有 strict graph backend 仍取末项作为最高优先级 source。只有显式构造为“首选 -> fallback”的 frame selection 才由 registry 选择首个 ready provider；通用 material-to-registry 桥尚未实现。该顺序是当前样本约束下的实现合同，不是官方公开的通用优先级；
- 首个逐帧 typed texture registry 已区分 layer source、带 variant 的 named layer target、user property 与 system identity，并记录 ready/pending/unavailable、generation 与 authored fallback。`2938612768` 已支持属性纹理未绑定时回退作者 image provider，static image blend 由 layers `239/657/1509` 扩至 `239/657/775/875/1509`；layer `775` 仅使用脚本包装器中的 authored-initial alpha，不代表 SceneScript 已运行；
- v15 已保真保存 EffectDefinition/FBO/ordered pass/bind/compose/command/condition/function/unknown fields，并按 material-pass ordinal 关联实例 pass；copy/swap command 不消耗 material ordinal；
- v16 已按作者 source/effect/pass order 编译 CPU authored graph，保留固定 effect input `previous`、effect-instance RT identity、raw `unique`、copy/swap、blocker 和逐样本 canonical SHA；v17 descriptor/cache 在此基础上保留 material usertexture、property key 与运行时 provider 引用；combo/constant 仍由实例覆盖 material；
- renderer 已消费两个严格注册的 Blur 子图：precise 仅接受单 effect、两 material node、一个 input-extent `rgba_backbuffer` RT；standard 默认 profile 仅接受单 effect、四个有序 material node、两个 scale=4 的非 unique `rgba_backbuffer` RT，以及已核验的 shader/state/combo/binding/default constant。两者均为 `executed-degraded`，不是任意 authored shader 或 WE 像素等价；
- 签名 Debug App、隔离 sample root/HOME、Metal ready/after 双帧、语义合同和 stop 后 surface=0；最新正式矩阵 **13/13 通过**。结构基线仍为 **106 definitions / 182 passes / 179 material passes / 50 FBO** 与 **197 layer plans / 300 effects / 411 nodes / 76 RT**；graph GPU 成功层仍为 `2902406982:[530]`、`3724289844:[28,36]`、`3765760121:[68,76,82]`，失败为 0。`2938612768` 的 static image blend 为 **5/5**，隔离副本向 `newproperty25/26` 注入两张用户纹理后同链路保持 5/5、image 44/44。`3724289844:[20]`、`3723344874:[348]`、`3750813609:[358]` 的不完整或非默认 Blur 图继续阻断 legacy fallback。最终报告：`.codex/scene-user-texture-final13-r2-20260723/report.json`；Scene 测试共运行 **134 项**，其中 **133 项通过、1 项跳过**。

### 仅解析/诊断或部分实现

- authored graph 只有上述 precise 与 standard 默认 profile 两个严格 Blur 子集进入 renderer；named target、静态 image blend 和其余手写 effect 仍是受限执行器，child/nested target、effectful/media provider、任意 target 链和通用 mask/composite 尚未实现；
- 首个 typed frame texture registry、authored fallback 和 PNG/JPEG property file/bookmark/decode 已进入 runtime，但只服务当前严格静态 image-blend consumer；`$mediaThumbnail`、Texture Variants、video frame、通用 material property consumer、effectful/nested provider 与 history/copy/swap 尚未接入；resolver 也没有 shader annotation/default 解析或任意 shader/pass executor；
- Timeline 只有数据模型空壳，没有关键帧、Loop/Mirror/Single、Bézier、wrap-loop、pause 或 target 写回；
- SceneScript 只检测 inline script / `.js`，没有 ECMAScript runtime、`init/update`、事件、globals、Date/Math live value 或属性写回；
- 用户属性 parser 已把官方 `texture` 与样本 raw `scenetexture` 归一为内部 texture-provider 类型并保留原始 runtime type；PNG/JPEG 文件选择/授权/加载已闭合首个静态 consumer 子集，Texture Variants、media/video texture、transform、动态 alpha、particle/audio/puppet target 和 `applyUserProperties` 仍未闭环；
- child particle graph 可遍历但不实例化；除 `particle/drop` 外的 built-in particle、rope/rope trail、world-space、control point、collision、音频和动态 override 未实现；Sprite Trail 当前只覆盖 2D sprite velocity-aligned stretch 子集；
- particle exponent 已进入解析模型，但 simulation 尚未消费，不能记为已支持；
- 多 foliage 栈、vertex sway 与 workshop 自定义 sway 未实现；它们当前保持静态或进入明确诊断，不用单层 UV 近似替代；
- Scene 音频/媒体未接现有系统服务；动态时间/日期/媒体 text、puppet/mesh/3D/lighting、自定义 shader 均未实现；
- pause/resume、fullscreen/battery、目标 FPS、CPU/GPU/显存预算和 soak 尚未闭环。

13 样本 PASS 不能解释成 Wallpaper Engine 视觉兼容率：正式矩阵只证明当前声明的解析、GPU 完成、非黑画面、能力计数和释放门通过。`2902406982` 的 named target 主缺口与 `2938612768` 的首个静态背景依赖已经关闭，但两者仍有字体、时序、媒体、后续 effect 和粒子差异；`3750813609` 仍缺动态时钟、cloud effect、其他雨粒子系统和完整合成。21 样本首轮分级仍只是历史截图基线，必须在下一轮统一视觉重跑后才能重新分级。

## 3. 官方资料核验后的契约边界

[Wallpaper Engine Scene 能力参考](wallpaper_engine_scene_compatibility.md) 的能力地图总体成立；底层开发合同现统一放在 [Scene 语义手册](semantics/README.md)。官方资料描述编辑器/官方运行时行为，没有公开稳定的 Workshop 序列化格式。实现必须标注“官方行为、样本实例、WE-compatible asset 观察、第三方播放器解释、MyWallpaperX 现状”五类证据，不能把后两类反向写成官方规则。

当前直接影响架构与验收的官方契约：

1. [Camera Parallax](https://docs.wallpaperengine.io/en/scene/parallax/introduction.html) 必须由 Scene options 开启，并逐层尊重 parallax depth；0 表示该层关闭。[Depth Parallax](https://docs.wallpaperengine.io/en/scene/effects/effect/depthparallax.html) 是独立 effect，还要求 Camera Parallax 开启且当前层普通 depth 为 0。
2. [Timeline](https://docs.wallpaperengine.io/en/scene/timeline/introduction.html) 包含 Loop/Mirror/Single、start paused、默认 Bézier、左右切线和 wrap-loop。动画事件通过同层 SceneScript `animationEvent` 触发，不直接操作声音或图层。
3. [SceneScript](https://docs.wallpaperengine.io/en/scene/scenescript/reference.html) 是属性绑定型 ECMAScript 运行时；动画先求值，脚本再更新并可覆盖结果。不能先造一个与 layer/effect/text/particle target 脱节的通用 JS 执行器。
4. [User Properties](https://docs.wallpaperengine.io/en/scene/userproperties/overview.html) 的控件、默认值、直接绑定、条件显示与持久化应先于脚本回调；`applyUserProperties` 首次加载后只携带变化键。
5. [SceneScript AudioBuffers](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/AudioBuffers.html) 为 16/32/64 可选频段，提供 left/right/average 并每个渲染帧更新；不能直接套用 Web 固定 64+64、约 30Hz 回调合同。
6. [Bloom](https://docs.wallpaperengine.io/en/scene/effects/bloom.html) 区分标准 Bloom 和 Ultra HDR，并有逐层 HDR brightness；自定义 shader/3D/Puppet 的能力虽强，但没有当前 2D 主构图资源链优先。
7. [RGB Composition](https://docs.wallpaperengine.io/en/scene/rgb/introduction.html) 明确像相机一样记录其下方图层；[Effects](https://docs.wallpaperengine.io/en/scene/effects/introduction.html) 和 [Blend](https://docs.wallpaperengine.io/en/scene/effects/effect/blend.html) 允许链接动态 layer。官方没有公开 Workshop named-target 名称、dependency DAG 或 `projectlayer` 稳定格式，这些只能由隔离样本建立内部合同。
8. [Foliage Sway](https://docs.wallpaperengine.io/en/scene/effects/effect/sway.html) 区分 UV 与 Vertex 模式，并由 mask 和作者参数限定作用区域。当前只把单个 built-in UV 变体计为受支持，多 effect 栈、Vertex 和 workshop shader 必须继续 fail closed。
9. [Shader Variables](https://docs.wallpaperengine.io/en/scene/shader/variables.html) 中 `g_TextureNResolution.xy` 表示物理纹理尺寸、`.zw` 表示映射尺寸；mask/effect UV 需要保留这两套尺度，不能假设 source 与 mapped size 相同。
10. [Particle Renderer](https://docs.wallpaperengine.io/en/scene/particles/component/renderer.html) 定义 Sprite Trail 按粒子速度方向对齐，并按 speed、length 与 min/max stretch 控制长度。当前实现仅复用 2D sprite quad 覆盖该子集，不据此宣称 rope、child 或完整粒子 renderer 兼容。
11. [Shader Variables](https://docs.wallpaperengine.io/en/scene/shader/variables.html) 公开 `g_Texture0...7`，但 slot 含义由当前 material/shader annotation 决定；nullable texture slot 不得压缩，也不存在通用的“slot 1 永远是 mask”。
12. WE-compatible effect definitions 与可审计播放器共同证明 `target`、`bind`、`compose`、`command:copy/swap`、RT scale/format/unique 是执行字段；`unique` 只声明实例唯一性，不能单独推导跨帧 history，history 必须由读前写、copy/swap 和生命周期数据流判定。raw schema 并非官方公开合同，新增执行语义仍要由合法官方 assets 或真实样本交叉验证。

## 4. 重新排序后的实施路线

### S0：可重复基线与作者语义门（已完成）

- 隔离 runner、签名身份、Metal 双帧、13 样本语义矩阵和 surface 释放门已落地；
- cover、Camera Parallax、effect/particle visibility 均按作者声明执行；
- 未声明或默认关闭的效果必须继续作为负向门，不能用“能力存在”替代启用条件。

### S1：首帧主构图基础闭合（受限完成）

按依赖顺序实施：

1. **已完成** `models/util/solidlayer.json` 与 model JSON `solidlayer:true` 程序化色块：保留作者 color，复用 1×1 白纹理，只对 solid 在通用 fragment 中乘 layer tint；提交 `c8c463b`。
2. **已完成 S1.2a**：typed utility、受支持 effect 的 current-frame prefix capture、受限离屏池、mask fail-closed 与 GPU completion telemetry；提交 `1517f4a`、`1f8f148`。
3. **已完成 S1.2b 受限子集**：`_rt_imageLayerComposite_<id>_a` named target、独立预算池、clipping consumer 绑定与 GPU completion 门；`2902406982` 为 6 provider / 7 binding，提交 `d881bb1`。
4. **已完成 S1.2c 受限子集**：wrapped alpha、typed user texture input、单 hidden ordinary image provider 的 static normal blend；`2938612768` 的首个彩色背景依赖恢复，提交 `375c3ca`、`b75a20f`、`f1493b2`。
5. **已完成高命中视觉子集**：coarse blur 像素尺度修正、单 built-in UV Foliage Sway、built-in `particle/drop`、2D Sprite Trail，提交 `f223bd1`、`c2fd29b`、`ddd87e1`、`064c2e7`。

### S2：主构图与高命中效果闭合（当前 P0）

1. **Effect-definition IR（已完成保真阶段）**：v15 保留 effect FBO、ordered pass、`target`、`bind`、`compose`、copy/swap、scale/format/raw unique/UV/condition/function 和未知字段；这不等于 effect 支持完成。
2. **Authored graph planner（已完成结构阶段）**：v16 区分 effect input `previous`、effect-scoped RT、material/command ordinal、copy/swap 和 blocker，并用 canonical SHA 锁定逐样本图身份。当前 5 个 condition/function blocker 均 fail closed。
3. **S2.3a precise-blur graph backend（已完成受限阶段）**：统一 resolver 与严格 topology/state/resource gate 驱动 5 个可见层进入固定近似 Gaussian；不满足合同的 layer 20 不再回退旧文件名模糊，隐藏层不执行，RT 被预算缩放时拒绝。
4. **S2.3b standard Blur graph backend（默认 profile 已完成）**：以 `2902406982` layer `530` 的真实 4-node、2 个 quarter RT 图为门，完成 alpha-aware downsample -> 13-tap horizontal/vertical Gaussian -> default previous combine；不支持的 KERNEL1/2、COMPOSITE1-3、MASK、BLURALPHA0 与混合图继续 fail closed，不回退 legacy coarse blur。
5. **资源提供链与更广 graph executor（identity/fallback 与 file-backed property 第一切片已完成）**：typed frame registry、provider 状态/generation、逐 slot 候选链、属性未绑定时 authored fallback，以及 PNG/JPEG `sceneTexture` 的 picker/bookmark/decode/Metal 上传已落地；下一步接 media `$mediaThumbnail`、Texture Variants、video、通用 material property consumer、effectful/nested provider，再扩 copy/swap、compose、更多 render state 与 shader backend。缺失时必须沿候选链回退或明确 fail closed，不能把绝对路径、pending provider 或空白纹理冒充成功。
6. **语义正确的高命中批次**：优先迁移 Shake/Swing/Foliage、Water Flow/Waves/Ripple、Depth Parallax、Blend/Opacity、God Rays/Shine/Motion Blur；每项按 [Effects 语义全集](semantics/effects-reference.md) 的局部空间、mask、slot 和 pass 合同实现，不再调一个全局近似覆盖多种 effect。
7. **视觉门**：先定向复核 `2902406982`、`2938612768`、`3750813609`，再重跑 21 样本 cover 对比；验收同时要求主构图、局部运动区域、字体/alpha 和关键粒子接近封面或 Windows 官方运行证据。

### S3：统一 live-value runtime（P1）

1. 建立 layer/effect/text/particle 的 typed target setter 和每帧值快照；属性、Timeline、SceneScript、音频只能经此层写值。
2. Timeline 实现 keyframe、duration/FPS、Loop/Mirror/Single、start paused、Bézier、wrap-loop 和多属性同步；动画事件在脚本核心可用后接入。
3. SceneScript 以官方属性绑定契约为边界，实现 `init/update`、Vec/Mat、Date/Math、`engine` 基础字段、`thisScene/thisLayer/thisObject/shared` 和确定执行顺序，再加入 user/cursor/audio/media 事件。
4. 动态时钟/日期/媒体 text、transform/alpha/effect/particle property target 与无重建热更新复用同一 live-value 层。

### S4：粒子图谱扩展（P1 后段）

- 先按正式矩阵缺失频率增加其他 built-in particle texture 和常用 renderer/operator；当前正式覆盖只有 **6/27**；
- 再实现 child/rope/rope trail、world-space、control point、collision 和动态 override，每项单独建立 fixture、GPU 像素门与真实样本门；
- 不把 `particle/drop` 或 Sprite Trail 的单一子集推断为全部雨、绳索、child graph 或粒子系统兼容。

### S5：音频、角色、高级兼容与发布门（P2-P3）

- Scene 音频桥按脚本选择提供 16/32/64 left/right/average，并按渲染帧更新；媒体桥提供可注入测试源；
- 标准 Bloom 完整参数、颜色空间/预乘 alpha、Puppet、实时 2D lighting/HDR、3D、自定义 shader translation 和 RGB 按样本收益后置；
- 每个阶段持续记录加载时间、纹理内存、粒子上限、帧时和降级原因；
- 最终建立固定/扩展/新下载三层矩阵、30 分钟交互、2 小时 soak、系统生命周期和发布 checklist。

### 已完成：S1.1 solid layer

- 固定 built-in 路径和 model JSON `solidlayer:true` 实例统一进入 typed `solid`；缺失作者 color 在 descriptor 中保留 `nil`，渲染时才回退白色。
- 共享 1×1 白纹理随 `SceneMetalView` 创建一次；color/alpha/effect/mask/blend 继续走现有 compositor，没有伪纹理、样本 ID 或普通 image/text 全局乘色分支。
- 定向 `3122339805 / 3750813609 / 3765760121` 为 **3/3**；正式 11 样本为 **11/11**，solid `34/34`，image/solid `106/113`。`3122339805` 为 `90/90`，中性灰底像素由 45.96% 降至 0.33%。
- 历史验收由上述计数和提交 `c8c463b` 保留；重复的阶段性 runtime 副本可回收。

### 已完成：S1.2a utility current-frame capture

- `composelayer/projectlayer/fullscreenlayer` 已进入 typed descriptor；generic dependency ID、局部 composition geometry 与 project/fullscreen 全画布 geometry 均有确定性合同。
- 当前只对作者可见、无 child/dependency consumer、所有可见 effect 均受支持且不缺 mask 的 utility layer 执行捕获。未支持、部分支持、隐藏、无 effect 和带缺失 mask 的层均明确跳过，不把能力默认套给样本。
- source copy 与 effect encoder 失败均 fail closed；离屏纹理限制为最大 2048 维、96 MiB 预算，capture 成功只在 Metal command buffer 完成后上报。
- 定向 4 样本 **4/4**：42 个 utility candidate 中 2 个 capture，layer `410/530` 均 GPU succeeded，0 failed；正式矩阵 **12/12**，17 candidates / 2 capture / 8 dependency edges / 6 named-target gaps。
- 历史验收由上述计数和提交 `1517f4a`、`1f8f148` 保留；该阶段截至后续 S1 提交时以 format 14 矩阵复核，当前状态仍以第 2-4 节的 v17 证据为准。

### 已完成：S1.2b-S1.2c named target 与静态 image dependency blend

- `d881bb1`：发布受预算约束的 named render target，并把真实 clipping consumer 绑定到声明的 layer-ID target；`2902406982` 为 6 个 provider / 7 个 binding，GPU capture/binding 均纳入 benchmark 门。
- `375c3ca`：递归读取 `{value: ...}` 包装数值，修复 `2938612768` 中 authored alpha 0 被当成不透明的黑色覆盖层。
- `b75a20f`：在 interpretation 合同保留 typed effect user texture input，区分 layer target、system/media 与普通文件输入。
- `f1493b2`：执行单个 hidden ordinary image provider 到可见 consumer 的 static normal blend；`2938612768` 的彩色背景恢复，但 `$mediaThumbnail`、blendgradient、effectful provider 与完整后续 DAG 明确不在本子集。
- `f223bd1`：coarse blur 保留作者像素单位，但实现实际是全尺寸 RT + 4 倍 texel step；它修复了已观察到的重复/层叠背景和多重轮廓，却没有实现 WE 的 4-pass quarter-RT downsample/combine/mask/combo 合同。
- `c2fd29b`：单 built-in UV Foliage Sway 读取作者参数和 mask 映射；多 foliage 栈、Vertex/workshop 变体保持未实现，不再把统一晃动默认套给所有样本。
- `ddd87e1`：为已证明的 built-in `particle/drop` 提供受控软粒子纹理，未知 built-in fail closed。
- `064c2e7`：按速度方向和作者 length/min/max stretch 渲染 2D Sprite Trail；rope、child 和其他 renderer 继续未实现。
- 后续 `b5a33f1`、`4ceb94d`、`687b45a` 完成数字 binding、严格 gradient-clipping 和静态 blend 默认值；这一阶段截至对应提交仍为 format 14，报告 `.codex/scene-static-fallback-formal13-20260722/report.json` 只作为历史能力与生命周期证据，不反向覆盖当前 v17。

### 已完成：S2.1-S2.2 EffectDefinition IR 与 authored graph planner

- `6eadcf8` 将 interpretation 升至 v15，保真保存定义和实例关联；13/13 报告 `.codex/scene-effect-ir-formal13-final-20260723/report.json` 为 106 definitions / 182 passes / 179 material passes / 50 FBO，diagnostics 0。这里的 0 只表示当前识别字段没有保真诊断，不证明私有 schema 完整或 pass 已执行。
- `c7a0745` 将 interpretation 升至 v16，结构化编译 197 layer plans / 300 effects / 411 nodes / 76 RT；copy/swap、固定 `previous`、effect-scoped identity、raw unique 和 blocker 已进入图合同。当前 5 个 blocker 全部可解释，逐样本 canonical SHA 在独立复跑中稳定。
- 迁移策略：有正负样本约束的 bounded executor 暂时保留，禁止继续扩大 effect path 分支；只有通用 graph GPU 路径取得等价像素/golden 证据后，才删除对应旧执行器。

### 已完成：S2.3a precise-blur graph backend

- 当前 v17 runtime 继续消费 v16 建立的 authored plans；resolver 保留 8 个 sparse texture slot，记录 material/instance/user texture/explicit bind 来源，并合并 combo、constant 和 render state。
- backend 只接受已验证的两 pass full-resolution precise topology。缺失、动态 binding、大小写冲突、负数/越界 `scale`，未知 shader/state/combo/binding、非精确 RT extent 或混合 effect 都 fail closed；graph 编码/分配失败不会静默回源。
- `3724289844` layers `28/36` 与 `3765760121` layers `68/76/82` GPU succeeded，失败 0；layer `20` 因 precise+shadow 图不完整而阻断旧 fallback；`3723257973` 的 5 层和 `3765760121` 的 3 层因有效不可见未执行。
- 定向报告为 `.codex/scene-authored-precise-failclosed-related-20260723/report.json`，最终 13/13 报告为 `.codex/scene-authored-precise-final13-20260723/report.json`。App 为 `2.0.8 (268)`、Team `H9QWU9XN8R`；118 项 Scene 测试通过，1 项跳过。preview 明确输出 `authoredEffectGraphSupportLevel: executed-degraded`，矩阵同时锁定成功、失败和 legacy-blur blocked layer ID。
- precise backend 使用固定 9-tap 近似 kernel，未执行 authored shader，也未验证 shader annotations/defaults 与完整 alpha/采样合同，不能提升为 `semantics-verified`。

### 已完成：S2.3b standard Blur 默认 profile graph backend

- planner 只接受 stock standard Blur 的已核验默认图：单 effect、四个有序 material node、两个不同的 scale=4 非 unique `rgba_backbuffer` RT、严格的 source -> A -> B -> A binding 链，以及固定 shader role、render state、KERNEL0、COMPOSITE0、BLENDMODE0、COMPOSITEMONO0、BLURALPHA1、MASK0 和默认 combine constant。任一条件不满足即 fail closed，并阻断同层 legacy blur。
- runtime 为该图原子分配 2 个 full-size 与 2 个真实 quarter-size 非别名纹理；先做 alpha-aware 四点 downsample，再按官方 asset 观察到的 13 个权重做横纵 Gaussian，最后执行默认 combine，并把 stock straight-alpha 输出显式转回宿主 premultiplied 约定。显存预算不足时整组失败，不部分执行；precise 的 exact-input-extent 拒绝合同保持不变。
- `2902406982` layer `530` GPU succeeded；定向报告 `.codex/scene-standard-blur-alpha-290-20260723/report.json` 显示 utility capture `[410,530]`、authored graph `[530]`、失败和 blocked 均为空。截图中全背景模糊已替换旧 coarse 近似，三角内容仍保留；preview 仅用于方向性复核，不是像素金标准。
- 负向报告 `.codex/scene-standard-blur-alpha-negative-20260723/report.json` 锁定 `3723344874:[348]` 与 `3750813609:[358]` 不误走 legacy blur；最终 `.codex/scene-standard-blur-alpha-final13-20260723/report.json` 为 **13/13**，graph GPU 成功 6 层、失败 0、legacy blur blocked 3 层。Scene 测试 **123 项通过、1 项跳过**，并包含半透明 premultiplied 输入贯穿 capture、4-pass 与最终 composite 的像素门。
- 当前只闭合 default profile。奇数尺寸下采样取整、颜色空间、sampler 边界、空间变化 alpha 的 WE 像素等价，以及 KERNEL1/2、其他 composite/blend/mono/alpha/mask 组合仍未完成；planner 也只验证 graph 与 shader 路径，尚未验证同路径 asset 的内容哈希。因此能力仍是 `executed-degraded`。后续已转入下一节的 registry/provider 第一切片；legacy coarse 分支不再扩写。

### 已完成：S2.4a typed texture provider identity 与 authored fallback

- interpretation 升至 v17，在不改变 v16 authored graph/canonical SHA 语义的前提下保存 material pass `usertextures`、运行时 provider 引用计数和 texture property keys；合法 `_rt_imageLayerComposite_<id>_<variant>` 引用独立分类，不再作为磁盘文件误报缺失。
- `SceneFrameTextureRegistry` 以逐帧 generation 管理 layer source、完整 named target、user property 和 system identity；同名 target 的 A/B variant 不串用，pending/unavailable provider 会按作者顺序尝试下一候选，下一帧未重新发布的资源不会残留。
- `2938612768` 的空 `scenetexture` 属性不再截断 authored provider：layers `775/875` 分别回退 layer `890/1174`，最终 static image blend 为 `[239,657,775,875,1509]`。775 的脚本包装 alpha 只读取作者初始值；事件、媒体封面和逐帧 SceneScript 更新继续未实现。
- 定向报告 `.codex/scene-texture-fallback-293-v3-20260723/report.json` 为 5/5，`2902406982` 回归报告 `.codex/scene-texture-fallback-290-20260723/report.json` 通过；最终 `.codex/scene-texture-registry-final13-20260723/report.json` 为 **13/13**，所有样本 stop 后无 residue，Scene 测试 **128 项通过、1 项跳过**。
- 截图只证明 `2938612768` 中央播放器/静态封面已出现；背景仍被现有 waterwaves 近似严重扭曲。property file/security-scoped bookmark、`$mediaThumbnail`、Texture Variants、effectful/nested provider、通用 shader executor 与动态脚本仍是后续独立切片，不能把本阶段写成 sceneTexture 已完整可用。

### 已完成：S2.4b file-backed `sceneTexture` 第一切片

- 属性面板只为当前 render plan 实际可执行的 texture property key 提供 PNG/JPEG picker；能力发现扫描全部 authored layer，避免由其他属性控制的隐藏层永远没有控件，播放时仍按当前有效可见层筛选实际 consumer。
- 文件选择保存按 wallpaper/property 隔离的 bookmark。安全作用域只覆盖同步 Scene 通知、各屏 `MTLDevice` 解码上传、宿主启动及屏幕参数变化后的 surface 重建，随后立即释放；显示文件名、切换壁纸和长期播放不持有 scope。坏 bookmark、删除文件、坏图或不支持扩展名均清理或 fail closed，不保留旧纹理。
- `SceneMetalView` 为每屏设备生成并持有实际 `MTLTexture`，沿现有 `SceneFrameTextureRegistry.userProperty` 候选进入 renderer；没有用户文件时继续使用 authored fallback。Debug 注入只接受隔离 sample root 内、解析 symlink 后仍在根内的 PNG/JPEG。
- `2938612768` 隔离副本向 `newproperty25/26` 注入 200×200 PNG 后两张纹理均加载，五个 static image blend consumer 继续 5/5、image 44/44；最终 `.codex/scene-user-texture-final13-r2-20260723/report.json` 为 **13/13**，Scene 测试共运行 **134 项**，其中 **133 项通过、1 项跳过**；签名 App 身份和 stop 后资源释放门通过。
- 当前只闭合静态 PNG/JPEG 和受限 image-blend consumer；真实 NSOpenPanel 选择后的跨重启恢复、沙盒构建和物理显示器热插拔仍需产品回归。system/media、current/previous thumbnail、Texture Variants、视频、任意 material property consumer、effectful/nested provider、动态 alpha 和 SceneScript 仍未实现，不能写成完整 `sceneTexture` 支持。

## 5. 样本规范

- Steam App ID 固定为 Wallpaper Engine `431960`；记录 Workshop ID、下载日期、标题、文件 SHA-256 和下载方式；
- SteamCMD 必须运行在 `.codex` 可写副本，不能让自更新改动签名 App bundle；
- Steam 下载缓存只作为来源，测试前移动或复制到 `.codex/scene-representative-samples-<date>/Scene/<id>`；
- 真实 `~/Movies/MyWallpaperX/创意工坊` 始终只读；benchmark 使用隔离 sample root 和临时 HOME；
- 样本二进制不提交 Git，仓库只提交矩阵、来源、哈希和能力标签。

## 6. 开发规范

- 修复前记录预期、实际、根因假设、影响文件、样本范围和验收标准；
- 公共 parser/renderer 修复优先于样本绕过；
- 一个独立能力一个提交，完成目标样本和相关样本验证后才提交；
- `SceneRenderDescriptor` 合同变化必须 bump interpretation format 并同步 reader；
- 坐标改动同时复核 texture、model、projection、cursor 与 child transform；
- GPU 资源必须有所有权、上限和释放路径；不在每帧创建 pipeline、texture cache 或无限增长的 buffer；
- 新 Swift 文件不超过 400 行，历史超限文件只减不增；修改 Swift 后按项目规则运行代码健康门；
- 诊断必须区分 unsupported、resource missing、decode failure、pipeline failure、no drawable 和 lifecycle failure。

## 7. 测试金字塔

### 单元层

- PKGV/TEX/scene JSON fixture；
- EffectDefinition raw IR、实例 material ordinal、command ordinal、graph identity 与 canonical SHA；
- material 低到高 precedence、sparse slot、combo/constant 冲突、graph topology/state/binding 与 fail-closed legacy 路由；
- frame texture identity、ready/pending/unavailable、generation、A/B variant 隔离和 property -> authored fallback；
- property/timeline/particle 数据模型；
- transform、插值、资源路径和评分规则。

### GPU/集成层

- 小尺寸离屏纹理输入，验证输出像素、alpha 和 mask；
- authored graph exact-ID GPU completion、RT extent 不被预算静默缩放，以及 rejected graph 不执行旧 effect heuristic；
- Debug runner 启动真实 Scene，确认解释文件和纹理加载；
- 截取 ready 与 after-interaction 两帧，验证非黑、运动和窗口归属；
- stop 后确认 surface/timer/video source 清零。

### 样本矩阵层

- 目标样本：验证本次能力；
- 相关样本：覆盖相同 parser/effect/texture 路径；
- 固定矩阵：公共 runtime、resource、effect 或 lifecycle 改动后运行；
- 长批次失败不能用单样本重试替代，只能作为独立诊断证据。

## 8. 首轮实施

> 第 8-14 节是已完成阶段的证据记录，不再决定当前优先级；当前执行顺序以第 2-4 节为准。

### 问题（实施前）

实施前没有可自动启动和评估 Scene 的正式回归门；`3723344874` 的 blur/fluidsimulation/glitter/godrays layer 虽进入 offscreen skeleton，但 identity bounce 不产生对应视觉效果。

### 根因假设

1. Scene 播放只从 Steam UI 通知进入，测试无法指定隔离根；
2. offscreen pipeline 没有 typed post-process pass，renderer 只做一次无效果的复制；
3. 旧预览日志把“进入骨架”记录出来，但没有区分 route-only 与真实效果支持。

### 修改范围

- `App/DebugScenePlaybackRunner.swift` 与最小 AppDelegate 接线；
- `script/scene_wallpaper_benchmark.py`、矩阵 JSON 和脚本测试；
- typed blur pass、Metal shader 与 renderer 路由；
- Scene 状态文档和样本来源记录。

### 验收

- SteamCMD 样本 `3723344874` 在隔离根和临时 HOME 下启动；
- runner 日志确认 descriptor、image layer、loaded texture、surface 与 teardown；
- benchmark 对 ready/after 帧执行非黑和动态检查；
- blur pass 有确定性 GPU/像素或截图证据，不再标记 route-only；
- 相关非 blur image/mask 路径无回归；
- 脚本测试、代码健康和 Debug build 通过；每个独立问题单独提交。

## 9. 2026-07-22 首轮结果

- `DebugScenePlaybackRunner` 可从隔离 root 直启 Scene，并拒绝真实 Workshop 路径；Debug evidence 模式使用当前 Space 的可捕获窗口，不改变生产 desktop-level 窗口语义。
- `scene_wallpaper_benchmark.py` 会隔离复制签名 App、样本和 HOME，校验样本 SHA-256、App 身份、ready、纹理加载率、非黑双帧、像素变化和 stop 后 surface=0。
- SteamCMD App ID `431960` 下载并固化两个初始代表样本：`3723344874`（复杂多层/effect）与 `3724095562`（单图层直绘），二进制只保存在 `.codex`。
- 初始两样本矩阵 **2/2 通过**。`3723344874` 为 35 layers / 24 image layers / 29 effects，20/24 主纹理加载，1 层真实 gaussian blur、2 层 route-only，两帧 changed ratio 10.60%；`3724095562` 为 1/1 主纹理、静态两帧一致。
- 当时 App 身份为 Team `H9QWU9XN8R`、CDHash `17d3751df90e55868ae1d2e0500682746026b665`、版本 `2.0.8 (268)`、可执行文件 SHA-256 `650da4e5ece48cd464c30ce6896aed908844aa0eef44474f546e5527a2bdc858`，运行前后验证一致。
- 下一步见下一节的扩充结果和当前优先级。

## 10. 2026-07-22 第二轮样本扩充与 Bloom 结果

- 新增 SteamCMD 隔离样本 `3722933264`、`3723230275`、`3723257973`、`3724289844`、`3724553795`；加上初始两项，正式矩阵现为 7 个真实样本。候选 `3722249669` 和两个当前热门候选在匿名 SteamCMD 下不可下载，没有混入运行失败统计。
- 新矩阵覆盖 1 到 126 层、0 到 66 个 effect、MP4 payload、particle layer、103 个 inline-script layer、音频响应声明、单图直绘和复杂 mask/offscreen 路径。样本二进制与运行副本均在 `.codex`，真实 Workshop 根保持只读。
- `3723230275` 的主图包含真实纹理和 16-pass Workshop Bloom；旧实现只做 identity ping-pong。现在 `SceneBloomPipeline` 执行 threshold、separable gaussian blur、tint/intensity composite，并保留此前 foliage 等内联效果结果。
- 正式矩阵 **7/7 通过**。纹理加载率依次为 `100% / 50% / 12.12% / 83.33% / 100% / 100% / 50%`；六个动态样本 changed ratio 为 `7.38% / 38.88% / 44.29% / 10.72% / 12.66% / 18.52%`，静态样本为 `0%`。Bloom runtime 命中 1 层，Gaussian runtime 命中 1 层，所有样本 stop 后 surface 为 0。
- 当时 App 身份为 Team `H9QWU9XN8R`、CDHash `7e77a8aad22a6a94353394971a95d5973001556f`、版本 `2.0.8 (268)`、可执行文件 SHA-256 `5605fb190f8f66d68051800fa5d2295ea27c224bcf3cc1fb2f57cb9fa8ca7e5b`。
- 低加载率样本是有意保留的兼容缺口证据，不是全能力通过。后续优先通用 effect/pass 合成、built-in 资源与 container 语义；样本只作为能力验收，不增加 ID/名称适配分支。

## 11. 2026-07-22 文本与相机语义结果

- 新增 typed text style 与 CoreText 纹理链，使用包内 TTF/OTF、point size、颜色/亮度、背景、padding 和对齐默认值；有效父链下 `3723230275` 为 3/3、`3723257973` 为 10/10、`3723344874` 为 4/4、`3724289844` 为 3/3。interpretation contract 升至 v5。
- 文字目前渲染 descriptor 的静态 `value`，不执行未知 SceneScript；时钟、日期、属性绑定和音频驱动仍不会动态更新，不能据此声明脚本兼容。
- 正交相机由 letterbox 改为 cover；对非零 camera center 保留作者构图，同时限制可见矩形在 Scene 边界内。静态样本 `3724095562` 的灰色边带消失，ready/after 变化率为 0，边缘单色占比从修复前 82.70% 降至 25.48%。
- parallax 不再默认套用。正式矩阵逐项验证 `3723230275`、`3723257973` 为启用，其余五项为关闭，并记录 amount 与 mouse influence；静态样本增加最大动态像素门。
- 最终 7 样本矩阵 **7/7 通过**。当时 App 身份为 Team `H9QWU9XN8R`、CDHash `a43628baf354f21e6c8bfdbc629ef779d0d95816`、版本 `2.0.8 (268)`、可执行文件 SHA-256 `f7f0c5973a0d69412ecbfd63603671f35f6279da078a9cf1f4f0d1f5043f4a71`。
- 下一阶段先推进通用 shader/effect pass 顺序、blend/composite 与 mask 语义，再处理动态属性和脚本子集；不得把所有效果默认打开，也不得按样本 ID 修图。

## 12. 2026-07-22 precise blur 与复合水波层结果

- `blurprecise` 已接入与 coarse blur 共用的两遍 Gaussian GPU 路径；作者 `scale` 按像素半径解释，再按实际离屏纹理宽高归一化。`3724289844` 三个可见文字层分别读取 `0.43 / 1.33 / 1.28`，运行日志命中 3 层，不再记为 route-only。
- `3723230275` 原有逻辑会按层名 `ripple` 和包含不可见 pulse 的效果列表跳过整层。直接取消跳过会暴露两张黑底纹理，因为该链还依赖未完整实现的 waterflow、waterripple、perspective 和 opacity 合成。
- 中间版本先改成只检查可见 pass 的 capability gate；随后补齐 layer `colorBlendMode`、真实 projective UV+opacity replacement pass 和 mode 9 additive final composite。两层现在均进入 runtime，`unsupported composite skipped` 从 2 降为 0，黑矩形消失。
- 最新正式矩阵 **7/7 通过**；coarse blur 1 层、precise blur 3 层、Bloom 1 层、perspective-opacity 2 层、color blend mode 9 两层，fallback 为 0。
- 最新签名 App 身份为 Team `H9QWU9XN8R`、CDHash `7d2a5032b6cf1aa31ae9cb1b26cce8d976dcff04`、版本 `2.0.8 (268)`、可执行文件 SHA-256 `7a2689fd9cabc9f8610d1846538afb83e5a5ea97fd55e42c7ccfb3856f6d4bc5`；81 个脚本测试、签名 Debug build 和代码健康门通过。

### 当时产品判断（历史）

这一阶段曾按 7 样本与 v6/v7 renderer 估算完成度，并把 water/effect 精修排在前面。属性、基础粒子、文字和 11 样本语义门落地后，该估值与顺序已经失效；当前判断和 S1-S5 顺序以第 2-4 节为准，不再维护无统一量尺的百分比。

## 13. 2026-07-22 pass 元数据合同结果

- effect 实例 pass 与 material pass 现在同时保留有序 `textureSlots: [String?]` 和 `combos: [String: Int]`；原有去空的 `texturePaths` 继续存在，当前纹理加载和渲染路径没有行为变化。
- interpretation 升至 v7。固定 SHA 的 `3723230275` 精确验收为 effect 37 槽/20 空洞/17 combo 条目、material 24 槽/8 空洞/12 combo 条目；`waterripple` 的 `[null, null, normal]` 与 `ripple.json` 的 `VERSION=2` 均已进入 renderer descriptor。
- 最新正式矩阵 **7/7 通过**。签名 App 为 Team `H9QWU9XN8R`、CDHash `64879014f3bf56763b127d0b5075cfeb0c468a30`、版本 `2.0.8 (268)`、可执行文件 SHA-256 `d9543c624e35e010a931acfe2ab12ee5664b2a799deeb2d62d22944678120b5a`；83 个脚本测试、签名 Debug build 和代码健康门通过。

## 14. 2026-07-22 normal-map waterripple 结果

- 新 runtime 按同一可见 waterripple pass 的 `textureSlots[2]` 绑定 normal map，使用作者 shader 的两组 UV、相反动画相位、方向滚动、source aspect、ratio 与 `ripplestrength²` 数学；normal 采样 repeat，source 采样 clamp。
- 新 pass 激活时移除旧 `.waterwaves` 正弦 flag，执行顺序为 source → normal ripple → perspective+opacity → final blend，避免双重扰动或 perspective 重新读取旧 source。T1 mask 或 `MASK/SPECULAR=1` 尚未实现时不冒充支持，保留 legacy 路径。
- 最终矩阵 **7/7 通过**。`3723230275` 两层均加载 `256×256` normal，normal runtime 2、legacy 0、perspective-opacity 2、mode 9 两层、fallback 0；`3724289844` 的 T1 mask 变体保持 normal runtime 0、legacy 1，precise blur 仍为 3。
- 最终签名 App 为 Team `H9QWU9XN8R`、CDHash `1dcb8d87465cc9fd241bd10e6581694861267aa1`、版本 `2.0.8 (268)`、可执行文件 SHA-256 `5c47f37d35a370a0232a5a796e4e1d2403acd6cf2e92bb51132ef3f5026caac8`；83 个脚本测试、签名 Debug build 和代码健康门通过。`SceneMetalView` 已从历史 419 行降至 300 行并退出 legacy baseline，`SceneMetalRenderer` 基线从 454 收紧到 418。
