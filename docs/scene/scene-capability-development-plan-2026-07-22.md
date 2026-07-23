# Scene 播放能力开发计划

> 建立日期：2026-07-22
>
> 最近更新：2026-07-24（当前实现基线 `e505a9e`；interpretation v22；B0 direct dynamic text、B2 同帧 copy/swap/受限 history、Precise Blur interleave/legacy compose 与 exact stock Shake 已通过合同门；六个 strict backend 是当前 GPU 执行子集。未修改 26 样本 strict stage 为 30、chain 为 3、legacy blocked layer 为 16；后续按完整链解锁与封面方向性视觉门推进）
>
> 作用：定义 MyWallpaperX Scene runtime 从当前可审计子集向 Wallpaper Engine 常用能力逼近的实施顺序、样本门和验收标准。作者/执行语义先查 [`semantics/README.md`](semantics/README.md)；当前能力结论仍以 [`../reviews/web-scene-current-state-roadmap-2026-07-19.md`](../reviews/web-scene-current-state-roadmap-2026-07-19.md) 与最新运行证据为准；历史 memo 不反向覆盖本计划。

## 1. 目标与边界

目标不是宣称私有格式 100% 兼容，而是让常见 Windows Wallpaper Engine Scene 壁纸在 macOS 上达到可播放、可交互、可配置、可诊断和可持续回归的工程状态。

实现优先级由四项共同决定：

1. 真实 Workshop 样本命中频率；
2. 对首帧和主要视觉构成的影响；
3. 能否建立确定性自动验收；
4. 实现的来源、维护成本和安全边界。

当前采用 **coverage-first** 迭代：先让官方语义表中的主要系统各自拥有可运行、可诊断、fail-closed 的最小闭环，使跨系统依赖和冲突尽早暴露；随后再按共享根因和视觉收益打磨精度。这里的“覆盖”不等于放宽支持口径：状态统一分为 `recognized`、`graph-built`、`executed-degraded`、`semantics-verified`，只有最后一档可以宣称语义已验证。

不采用以下捷径：

- 不把 Scene 转成 Web 播放；
- 不按单个样本 ID 硬编码；
- 不把 route-only、占位 shader 或静态截图写成“效果已支持”；
- 不执行未知 SceneScript，也不直接加载来源不明的预编译 DirectX shader；
- 不直接修改真实 Workshop 样本。

## 2. 2026-07-24 当前代码事实

### 已真实进入运行链

- `project.json` / entry 同名 `gifscene.json` 识别、PKGV 索引、受控缓存解包、路径校验和 interpretation format 22；v22 继承 exact stock Opacity、ShaderContract、provider/resource metadata 与 authored graph，并加入 direct text content/point-size/color binding program 合同；
- PNG/JPEG、raw RGBA/RG/R8、BC1/BC2/BC3/BC5、LZ4、MP4 payload 和 TEX sprite sequence；
- Metal image/solid/text/particle 合成、父子 transform、有效可见性、source order、alpha、正交/透视粒子相机和桌面多屏宿主；
- 宿主级单一 60 Hz frame driver 与 `SceneFrameTiming` / `SceneFrameContext` 第一阶段：所有屏幕共享一次采样的 frame index、host time、scene time、frame delta 和 wall date；shader、视频帧、粒子 simulation 与 parallax smoothing 已迁移，屏幕尺寸和 pointer 仍按 surface 独立保存；
- B0 live-property runtime 已合龙：`SceneDynamicValue` 覆盖 bool/scalar/vector2/vector3/vector4/string，target 覆盖 scene/camera/layer/effect/text/particle/script instance，resolver 固定按 `authored -> userProperty -> Timeline -> SceneScript` 覆盖并拒绝重复、错类型和非有限值；v22 的 binding program 包含 layer alpha/color、direct text content/point-size/color、exact stock Local Contrast pass 3 `strength` 与 exact stock Opacity `alpha` target；Host 为每个 surface 独立求值和持有 generation，属性更新经原子 live state 路由到 renderer；
- 当前 live consumer 严格限定为 image/solid/text 和 `shouldCapture` utility 的 layer alpha、solid layer color、有效可见 text layer 的 direct content/point-size/color，以及已通过 strict planner 的 Local Contrast `strength`/Opacity `alpha`。文本只重栅格化变化层，重复值不生成，旧 generation 和失败结果不能覆盖最后可用纹理；hidden/no-consumer、SceneScript/time/media、particle、container、non-solid color、其他 effect constant、mixed 或 unsupported key 返回整场 `requestSceneRender`；
- cover 投影；Camera Parallax 服从 Scene options、显式逐层 depth、传播和属性 override；包括 composition 在内，缺失或零 depth 不产生逐层位移；
- legacy coarse blur 仍只服务尚未迁移的受限路径，采用全尺寸 RT + 4 倍 texel step 近似；authored graph 已分别把 precise Blur 严格选路到固定两遍近似 kernel，把 stock standard Blur 默认 profile 选路到真实 4-pass、2 个 quarter RT、alpha-aware downsample、13-tap Gaussian 与默认 combine，把 exact stock Local Contrast 选路到 4-pass、2 个 FBO `scale=4` quarter RGBA RT、alpha-weighted downsample、13-tap Gaussian X/Y 与线性 contrast combine，并把 exact stock Shake 选路到 RG8 flow、可选 R8 phase/white fallback 和 scene-time UV displacement。标准 Bloom、normal-map waterripple、perspective+opacity、mode 9 additive，以及 water/cursor/chromatic/iris 等仍是明确标注的受限实现；
- 单个 built-in UV Foliage Sway 已读取作者 strength/speed/phase/power/noise/ratio/direction 和 mask 映射；多 foliage 栈与 vertex/workshop 变体不会误套该近似实现；
- text 以 authored `pointsize * 4` 近似 300 DPI point raster、处理 vector padding、包内字体、系统字体别名和缺失字体诊断；direct user property 的 content/point-size/color 已按变化 layer 异步重栅格化，`* 4` 仍是样本验证近似，不是完整官方换算合同；
- 作者包内 2D sprite 粒子的 definition/resource graph、sphere/box、rate/burst/prewarm、常见 initializer/operator、sequence/random frame、additive/translucent、朝向、静态 override、CPU simulation 与 Metal instancing；除 `particle/drop` 外，现对 `fog1`、`leaves7/8`、`light_shafts_6`、`lightning3`、`halo/halo_2`、`ripple_single` 精确 key 提供项目自行生成的确定性预乘纹理，并支持按速度方向和作者 length/min/max stretch 绘制 Sprite Trail；这些程序纹理是 `executed-degraded`，不是官方纹理副本或像素等价实现；
- 用户属性定义、group/display condition/options、默认值/override、visibility/text/camera 与部分 effect target、按壁纸持久化、活动 Scene 受控重建和独立属性窗口；
- 当前实际执行的 `sceneTexture` key 支持 PNG/JPEG picker、按 wallpaper/property bookmark、同步 security-scope 解码、逐屏 Metal 上传、恢复作者默认和失败回退；隐藏但可通过其他属性显示的受支持 consumer 也会进入能力发现，播放时仍只执行当帧可见层；
- typed `composition/project/fullscreen` 与 generic dependency layer ID；对满足严格边界的 utility layer 执行当前 framebuffer 前缀捕获，并支持 `_rt_imageLayerComposite_<id>_a` named target 的有预算发布与 clipping consumer 绑定。`2902406982` 的 6 个 provider / 7 个 consumer binding 已闭合，原白色三角缺口不再由缺失 named target 产生；
- effect/material pass 的 typed user texture input 已保留；material resolver 对每个 sparse slot 按低到高优先级保存 `material asset -> material usertexture -> instance asset -> instance usertexture -> explicit graph bind` 候选链，现有 strict graph backend 仍取末项作为最高优先级 source。只有显式构造为“首选 -> fallback”的 frame selection 才由 registry 选择首个 ready provider；通用 material-to-registry 桥尚未实现。该顺序是当前样本约束下的实现合同，不是官方公开的通用优先级；
- typed texture registry 已区分 layer source、带 variant 的 named layer target、user property 与 system identity，并记录 ready/pending/unavailable 与 authored fallback。`c86491e` 将静态 layer/property/system 的 resource generation 与 named target 的 frame epoch 分离：连续帧同资源可复用，替换或缺席后重现换代，named 当帧重写仍逐帧失效。`2938612768` 的 static image blend 为 layers `239/657/775/875/1509`；layer `775` 仅使用脚本包装器中的 authored-initial alpha，不代表 SceneScript 已运行；
- v15 已保真保存 EffectDefinition/FBO/ordered pass/bind/compose/command/condition/function/unknown fields，并按 material-pass ordinal 关联实例 pass；copy/swap command 不消耗 material ordinal；`4f13daf` 只把 exact `KERNEL=0` Blur Precise legacy `compose:true` 两遍语法归一为 synthetic full-size FBO，不改变 generic compose 的 `L2` 等级；
- v16 已按作者 source/effect/pass order 编译 CPU authored graph，保留固定 effect input `previous`、effect-instance RT identity、raw `unique`、copy/swap、blocker 和逐样本 canonical SHA；v17 descriptor/cache 在此基础上保留 material usertexture、property key 与运行时 provider 引用；combo/constant 仍由实例覆盖 material；
- renderer 已消费六个严格注册的 backend：precise Blur、stock Blur 默认 profile、exact stock Local Contrast、exact Workshop Shadow、exact stock Opacity 与 exact stock Shake。Shake 只接受精确 definition/material/shader fingerprint、单 material stage、`MASK=0/AUDIOPROCESSING=0/NOISETEXTURE=0`、RG8 flow 与 R8 phase 或 authored white fallback；动态 speed/audio/noise/direction 保持关闭。六者均为 `executed-degraded`，不是任意 authored shader 或 WE 像素等价；
- `b541867` 建立 ordered strict effect-chain scheduler：外层 graph 必须无 blocker，effect/node/target identity 唯一且顺序连续，第一段输入 layer source，后续段必须精确消费前段 effect output；任何 stage 无严格 backend 时整链不进入 catalog。整链在同一 command buffer 顺序执行，只让最终 stage 合成到主画面；首段应用原 masks/UV/alpha，后续段 neutral recapture，每个 Local Contrast stage 独立读取完整 per-surface snapshot；`e505a9e` 继续把真实 scene time 传入 Shake，并验证 Shake 位于 Precise Blur 前后两种作者顺序；
- `809b75e` 在该 scheduler 上加入 exact Workshop Shadow backend，使 `3724289844` layer `20` 的 `Blur Precise -> Shadow` 成为首条真实 fully-supported strict chain。Shadow 只按完整合同准入，不按样本 ID 或 layer 名称分派；它只提升这一个 exact Workshop profile 到 `L3`，不提升官方 45 项 Effect 表中的通用 Shadow，也不获得 generic shader 执行能力；
- effect-chain target allocation 先在候选态完成所有 stage plan/table、预算与 LRU victims，再一次提交 cache/resident bytes/access counter；失败不刷新部分命中的 LRU，也不留下半条链。singleton strict plan 复用同一事务，旧直接测试入口保留；
- `8474ace` 完成 D7 ShaderContract IR v1：完整 UTF-8 source、raw SHA-256、stage path/kind、include、JSON annotation、uniform/attribute/varying declaration、diagnostic 和 canonical SHA 进入 v19；绝对/穿越路径、shader root/stage/include symlink escape、无效 UTF-8、缺失 stage、畸形 annotation 和重复 identity 均 fail closed。generic D7 仍只达到 L1 识别/保留；`136d35c` 仅把 exact Local Contrast 的 identity/canonical/stage/raw source hashes 用作 strict 准入门，实际执行项目自有 Metal pipeline，不预处理、翻译、编译或执行 authored shader source；
- `228cdde` 完成 Local Contrast 的资源格式前置：graph plan/table 新增 `rgba8888 -> .rgba8Unorm`，input/output 与 `rgba_backbuffer` 保持 `.bgra8Unorm`；两种格式均按 4 B/px 计费，格式变化原子替换 cache，未知格式继续 fail closed。该提交当时尚无执行层，随后 `136d35c` 已让 exact stock Local Contrast 消费该格式；
- 签名 Debug App、隔离 sample root/HOME、Metal ready/after 双帧、语义合同和 stop 后 surface=0；当前完整快照门 `.codex/scene-shake-20260724/full26-final/report.json` 为 **26/26**，报告 SHA-256 `112f3d50a63f2dd20002ca2c2f1d177fc86abaf82510f5dd85c7e5b8c0822f65`，仓库矩阵 SHA-256 为 `9a44707e9c84069ce3dc5ffa8c93c001c5fc54cf4b02eba89e53a3daeb8cfb75`。同一签名 App 的固定回归门 `.codex/scene-shake-20260724/fixed13-final/report.json` 为 **13/13**，报告 SHA-256 `fe389f155ef7147e5246b65fe19a953fe64492753e32932b3569d41064149bbe`，矩阵 SHA-256 `fbb252a64018cf785e20b2200db5966a300e9351a994b4a36f1fe9565c5b354c`。当前 26 门为 strict stage 30、failed 0、chain 3、Shake 3、legacy blocked 16、route-only 64；固定 13 门继续保护 stage 14、真实 chain 1、Opacity 4、Workshop Shadow 1、failed 0。全量 Scene 共 **292 项，其中 289 项通过、3 项跳过**。签名 App 为 `2.0.8 (268)`、Team `H9QWU9XN8R`、CDHash `0d7efcabf4b99a101a3341e64fb10d80ef8a4020`、可执行文件 SHA-256 `7cdb04292a891e7787d0fa489c8fbeb5337332e436bc0ea2de1b9827a135cbca`，运行前后签名均验证。完整聚合缺口见 [运行证据索引](semantics/runtime-evidence-index.md)。

### 仅解析/诊断或部分实现

- authored graph 只有 precise Blur、stock Blur、exact stock Local Contrast、exact Workshop Shadow、exact stock Opacity 和 exact stock Shake 六个 strict backend 进入 renderer；当前完整 26 门有 `2802243144:[41,64,115]` 三条 Blur/Shake chain，固定 13 门有 `3724289844:20` 的 Blur/Shadow chain。同帧 copy/swap 已进入 Precise Blur 两种完整白名单 material-command topology，exact legacy Blur Precise compose 可归一到同一 executor，显式 `unique:true` FBO 已进入受限 history seed/clear 路径；named target、静态 image blend 和其余手写 effect 仍是受限执行器，dynamic Shake、child/nested target、effectful/media provider、真实 history consumer、generic compose/scene-background、history 的跨帧语义、condition/function、其他 topology 和通用 mask/material/shader 尚未实现；
- typed frame texture registry、resource/frame 双代、authored fallback 和 PNG/JPEG property file/bookmark/decode 已进入 runtime；dynamic text 已提供 per-layer generation、串行异步栅格化、stale cancellation 和 last-ready fallback。通用 provider metadata/status/cancel、`$mediaThumbnail`、Texture Variants、video frame、通用 material property consumer、effectful/nested provider 与真实 persistent/history consumer 尚未接入；当前 history 只记录显式 unique target 的 seed 状态并在首次消费时清零；
- Timeline 没有正式 target/keyframe/mode/tangent/event IR；部分粒子动态 wrapper 只保留 presence/诊断，不能记为 Timeline 数据模型；
- SceneScript 只发现 `.js` 资源和 inline `script` presence；inline/source 内容、owner/property binding 和返回类型会丢失，也没有 ECMAScript runtime、`init/update`、事件、globals、Date/Math live value 或属性写回；
- 用户属性 parser 已把官方 `texture` 与样本 raw `scenetexture` 归一为内部 texture-provider 类型并保留原始 runtime type；PNG/JPEG 文件选择/授权/加载已闭合首个静态 consumer 子集，layer alpha、纯 solid layer color、direct text content/point-size/color、exact stock Local Contrast strength 与 stock Opacity alpha 已无重建 live；Texture Variants、media/video texture、transform、non-solid/mixed color、其他 effect constant、particle/audio/puppet target 和 SceneScript `applyUserProperties` 仍未闭环；
- child particle graph 可遍历但不实例化；除上述 9 个精确 key 外的 built-in particle、rope/rope trail、world-space、control point、collision、音频和动态 override 未实现；Sprite Trail 当前只覆盖 2D sprite velocity-aligned stretch 子集；
- particle exponent 已进入解析模型，但 simulation 尚未消费，不能记为已支持；
- 多 foliage 栈、vertex sway 与 workshop 自定义 sway 未实现；它们当前保持静态或进入明确诊断，不用单层 UV 近似替代；
- Scene 音频/媒体未接现有系统服务；SceneScript/系统时间/日期/媒体驱动的 text、puppet/mesh/3D/lighting、自定义 shader 均未实现；
- Frame Context 尚缺 pause/resume、长帧 delta clamp/dropped-time、fixed timestep、audio/media producer 和离线 adapter；property producer 与 per-surface changed-payload generation 已进入 B0，pointer/script/provider 的 local generation 隔离仍待对应 runtime 接入；fullscreen/battery、目标 FPS、CPU/GPU/显存预算和 soak 也未闭环。

26 样本当前完整快照门和 13 样本固定回归门 PASS 都不能解释成 Wallpaper Engine 视觉兼容率：它们只证明各自矩阵声明的解析、GPU 完成、非黑画面、能力计数和释放门通过。`2902406982` 的 named target 主缺口与 `2938612768` 的首个静态背景依赖已经关闭，但两者仍有字体、时序、媒体、后续 effect 和粒子差异；`3750813609` 已出现雾、叶片与光束等新增粒子，但仍缺动态时钟、完整 Clouds/Blur、child、world-space 雨滴溅射、control point/turbulence 和最终合成精度。21 样本首轮分级仍只是历史截图基线，必须在下一轮统一视觉对照后才能重新分级。

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

所有未完成阶段受 [公共能力依赖图](semantics/capability-dependency-map.md) 约束。研究和 fixture 可以并行，产品执行按 `D0-D8 -> D9-D10 -> D11` 推进；后续某个样本再显眼，也不能绕过 host/surface scope、identity、provider、graph、shader contract、coordinate space 或 lifecycle 建旁路。

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

### S2：主构图与高命中效果闭合（受限执行，继续横向覆盖）

1. **Effect-definition IR（已完成保真阶段）**：v15 保留 effect FBO、ordered pass、`target`、`bind`、`compose`、copy/swap、scale/format/raw unique/UV/condition/function 和未知字段；这不等于 effect 支持完成。
2. **Authored graph planner（已完成结构阶段）**：v16 区分 effect input `previous`、effect-scoped RT、material/command ordinal、copy/swap 和 blocker，并用 canonical SHA 锁定逐样本图身份。当前 5 个 condition/function blocker 均 fail closed。
3. **S2.3a precise-blur graph backend（已完成受限阶段）**：统一 resolver 与严格 topology/state/resource gate 驱动 5 个可见层进入固定近似 Gaussian；不满足合同的 layer 20 不再回退旧文件名模糊，隐藏层不执行，RT 被预算缩放时拒绝。
4. **S2.3b standard Blur graph backend（默认 profile 已完成）**：以 `2902406982` layer `530` 的真实 4-node、2 个 quarter RT 图为门，完成 alpha-aware downsample -> 13-tap horizontal/vertical Gaussian -> default previous combine；不支持的 KERNEL1/2、COMPOSITE1-3、MASK、BLURALPHA0 与混合图继续 fail closed，不回退 legacy coarse blur。
5. **Provider Core 与 Graph Resource Runtime 分开闭合**：typed frame registry、resource/frame 双代、逐 slot 候选、authored fallback、PNG/JPEG `sceneTexture` 第一切片、effect target table、ShaderContract IR v1、`rgba8888` target format、六个 strict backend、ordered strict effect-chain scheduler、真实 Blur/Shadow 与 Blur/Shake chain、同帧 copy/swap command foundation、受限 history seed/clear、Precise Blur 两种 material-command interleave 与 exact legacy compose 归一化已完成。dynamic text 已成为首个 per-layer generation/stale-cancellation/last-ready consumer；generic compose、真实 history consumer 与 typed shader defaults/built-ins/state 仍未完成。`2134765860` dynamic Shake 与 `2938612768` mixed chains 是整链 fail-closed 负向门；route-only 不作为完整 gap census。
6. **高命中 Effect 批次有硬前置**：Swing/Foliage、Water、Depth Parallax、Blend/Opacity、God Rays/Shine/Motion Blur 继续是候选；Shake 只完成 exact 静态 stock profile。候选只能通过新增共享 graph/shader/provider/space primitive或注册完整匹配且 fail-closed 的 strict profile 实现。不得继续扩大 effect-name/path-substring 手写近似；逐项门见 [Effect 执行覆盖表](semantics/effect-execution-coverage.md)。
7. **视觉门**：先固定 `2802243144`、`2902406982`、`2938612768`、`3750813609` 等 5-6 个关键样本，在封面自身比例的固定测试画布上比较主构图、主体位置、色调/亮度和明显效果范围；封面不能验证动画速度、Shake 相位、粒子轨迹、音频响应或像素等价。真实样本增加、完整矩阵合同变化或里程碑收口时，再重建隔离副本并重跑当前完整快照门。

### S3：Runtime Kernel 与统一 live-value（B0 property 主链已闭环）

1. **Frame Context 第一阶段已完成**：宿主统一 frame driver 与时间采样，现有 shader/video/particle/parallax 消费同一帧；下一步补 pause/resume、raw/simulation delta、discontinuity、fixed-time test adapter 和目标 FPS。
2. **B0 per-surface snapshot 已完成**：`HostFrameInputs -> SurfaceFrameContext -> Surface EvaluationTransaction -> SurfaceDynamicSnapshot` 已用于 property producer；双屏共享时间/属性输入，但最终 snapshot 和 generation 按 surface 隔离。
3. **B0 TargetContract 与 binding program 已完成首个产品闭环**：v22 编译并持久化 alpha/color、direct text content/point-size/color、exact stock Local Contrast `strength` 与 exact stock Opacity `alpha`；mixed/invalid/unsupported/SceneScript key 保留 rebuild fallback，已登记 target 均有真实 consumer。
4. **B0 原子 live routing 已完成**：Host/Service/属性窗口更新与 reset 先尝试 atomic live state；image/solid/text 和 `shouldCapture` utility 的 alpha、纯 solid color、strict Local Contrast strength 成功时不重建，particle/container/non-solid color、其他 effect constant、mixed/unsupported/no-consumer 失败时才调度整场重建。事件、Timeline 和 SceneScript 以后按既定 transaction 顺序接入。
5. Timeline 先完整保留 keyframe/mode/tangent/event 数据，再接 Loop/Mirror/Single 与线性/Bézier；SceneScript 先保存 source/binding IR，再接 sandbox VM、lifecycle、typed write 和 budget，不能从嵌入 VM 直接跳到 renderer setter。
6. 动态 text、cursor/audio/media 输入与 transform/effect/particle target 按各自 provider、space、event 和 generation 前置接入，不再作为一组无依赖的“同时打通”任务。

direct text 三类 target 与 B1 generation/stale cancellation 已由 `1762743` 完成首个闭环，同帧 copy/swap command foundation 已由 `f1c6a10` 完成，`dcedc2e` 已完成显式 unique FBO 的受限 history seed/clear，`ebf44a9` 已完成 Precise Blur 两种 material-command interleave，`4f13daf` 已完成 exact legacy compose 归一化，`e505a9e` 已用 exact stock Shake 让未修改样本新增 6 stage、3 条 chain。下一切片继续按未修改样本新增 stage、解除完整 effect chain、封面方向性画面改善和实现成本四项重排 history、SceneScript、effect backend、shader 与 provider 路线。以后所有属性能力继续要求 compiler target、活动 consumer、per-surface snapshot、原子失败/fallback 和 surface/window identity 同批验收。

### S4：按公共依赖扩展粒子图谱（分层推进）

- 第一批高命中程序化 built-in texture 已完成，正式可见粒子运行层由 **6/27** 提升至 **14/27**；剩余静态遮罩与 sprite-atlas/multi-texture 必须先复用 Provider Core 与 material contract，不用通用圆点冒充；
- dynamic override/control point 等 TargetContract + binding program + local/world space；Layer Image 等 provider generation + dynamic text；world-space 等完整 parent/world/camera matrix；
- child/collision 等 fixed step + deterministic event queue + owner/budget；rope/rope trail 等独立 geometry/material renderer；audio response 等 injectable audio snapshot。上述前置未完成时只补 IR/fixture，不提前接产品执行；
- 不把程序化 built-in texture 或 Sprite Trail 子集推断为官方纹理等价、全部雨、绳索、child graph 或粒子系统兼容。

### S5：音频、角色、高级兼容与发布门（P2-P3）

- Scene 音频桥按脚本选择提供 16/32/64 left/right/average，并按渲染帧更新；媒体桥提供可注入测试源；
- stock WE-compatible shader source/annotation/combo/built-in/state contract 属于 S2 Graph 前置；任意 Workshop custom shader 的通用翻译、安全、缓存与分发产品化才属于 S5。标准 Scene Bloom/HDR、Puppet、实时 2D lighting、3D 和 RGB 按公共依赖与样本收益后置；
- 每个阶段持续记录加载时间、纹理内存、粒子上限、帧时和降级原因；
- 最终建立固定/扩展/新下载三层矩阵、30 分钟交互、2 小时 soak、系统生命周期和发布 checklist。

### 已完成：S1.1 solid layer

- 固定 built-in 路径和 model JSON `solidlayer:true` 实例统一进入 typed `solid`；缺失作者 color 在 descriptor 中保留 `nil`，渲染时才回退白色。
- 共享 1×1 白纹理随 `SceneMetalView` 创建一次；color/alpha/effect/mask/blend 继续走现有 compositor，没有伪纹理、样本 ID 或普通 image/text 全局乘色分支。
- `95e0d58` 将 solid color 接入统一 live snapshot；73 条 color 指令中 25 条属于纯 solid key 可 live，`3122339805:basecolor` 的 48 条因同键还含未支持目标继续整场重建。GPU 门证明相同 tint 对 solid 生效、对普通 image 无效。
- 定向 `3122339805 / 3750813609 / 3765760121` 为 **3/3**；正式 11 样本为 **11/11**，solid `34/34`，image/solid `106/113`。`3122339805` 为 `90/90`，中性灰底像素由 45.96% 降至 0.33%。
- 历史验收由上述计数和提交 `c8c463b` 保留；重复的阶段性 runtime 副本可回收。

### 已完成：S1.2a utility current-frame capture

- `composelayer/projectlayer/fullscreenlayer` 已进入 typed descriptor；generic dependency ID、局部 composition geometry 与 project/fullscreen 全画布 geometry 均有确定性合同。
- 当前只对作者可见、无 child/dependency consumer、所有可见 effect 均受支持且不缺 mask 的 utility layer 执行捕获。未支持、部分支持、隐藏、无 effect 和带缺失 mask 的层均明确跳过，不把能力默认套给样本。
- source copy 与 effect encoder 失败均 fail closed；离屏纹理限制为最大 2048 维、96 MiB 预算，capture 成功只在 Metal command buffer 完成后上报。
- 定向 4 样本 **4/4**：42 个 utility candidate 中 2 个 capture，layer `410/530` 均 GPU succeeded，0 failed；正式矩阵 **12/12**，17 candidates / 2 capture / 8 dependency edges / 6 named-target gaps。
- 历史验收由上述计数和提交 `1517f4a`、`1f8f148` 保留；该阶段截至后续 S1 提交时以 format 14 矩阵复核，当前状态仍以第 2-4 节的 v22 证据为准。

### 已完成：S1.2b-S1.2c named target 与静态 image dependency blend

- `d881bb1`：发布受预算约束的 named render target，并把真实 clipping consumer 绑定到声明的 layer-ID target；`2902406982` 为 6 个 provider / 7 个 binding，GPU capture/binding 均纳入 benchmark 门。
- `375c3ca`：递归读取 `{value: ...}` 包装数值，修复 `2938612768` 中 authored alpha 0 被当成不透明的黑色覆盖层。
- `b75a20f`：在 interpretation 合同保留 typed effect user texture input，区分 layer target、system/media 与普通文件输入。
- `f1493b2`：执行单个 hidden ordinary image provider 到可见 consumer 的 static normal blend；`2938612768` 的彩色背景恢复，但 `$mediaThumbnail`、blendgradient、effectful provider 与完整后续 DAG 明确不在本子集。
- `f223bd1`：coarse blur 保留作者像素单位，但实现实际是全尺寸 RT + 4 倍 texel step；它修复了已观察到的重复/层叠背景和多重轮廓，却没有实现 WE 的 4-pass quarter-RT downsample/combine/mask/combo 合同。
- `c2fd29b`：单 built-in UV Foliage Sway 读取作者参数和 mask 映射；多 foliage 栈、Vertex/workshop 变体保持未实现，不再把统一晃动默认套给所有样本。
- `ddd87e1`：为已证明的 built-in `particle/drop` 提供受控软粒子纹理，未知 built-in fail closed。
- `064c2e7`：按速度方向和作者 length/min/max stretch 渲染 2D Sprite Trail；rope、child 和其他 renderer 继续未实现。
- 后续 `b5a33f1`、`4ceb94d`、`687b45a` 完成数字 binding、严格 gradient-clipping 和静态 blend 默认值；这一阶段截至对应提交仍为 format 14，报告 `.codex/scene-static-fallback-formal13-20260722/report.json` 只作为历史能力与生命周期证据，不反向覆盖当前 v21。

### 已完成：S2.1-S2.2 EffectDefinition IR 与 authored graph planner

- `6eadcf8` 将 interpretation 升至 v15，保真保存定义和实例关联；13/13 报告 `.codex/scene-effect-ir-formal13-final-20260723/report.json` 为 106 definitions / 182 passes / 179 material passes / 50 FBO，diagnostics 0。这里的 0 只表示当前识别字段没有保真诊断，不证明私有 schema 完整或 pass 已执行。
- `c7a0745` 将 interpretation 升至 v16，结构化编译 197 layer plans / 300 effects / 411 nodes / 76 RT；copy/swap、固定 `previous`、effect-scoped identity、raw unique 和 blocker 已进入图合同。当前 5 个 blocker 全部可解释，逐样本 canonical SHA 在独立复跑中稳定。
- 迁移策略：有正负样本约束的 bounded executor 暂时保留，禁止继续扩大 effect path 分支；只有通用 graph GPU 路径取得等价像素/golden 证据后，才删除对应旧执行器。

### 已完成：S2.3a precise-blur graph backend

- 当前 v22 runtime 继续消费 v16 建立的 authored plans；resolver 保留 8 个 sparse texture slot，记录 material/instance/user texture/explicit bind 来源，并合并 combo、constant 和 render state。
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
- `SceneFrameTextureRegistry` 最初以单一逐帧 generation 管理 layer source、完整 named target、user property 和 system identity；`c86491e` 已纠正为静态 resource generation 与 named frame epoch 双代。同名 target 的 A/B variant 不串用，pending/unavailable provider 会按作者顺序尝试下一候选，下一帧未重新发布的资源不会残留。
- `2938612768` 的空 `scenetexture` 属性不再截断 authored provider：layers `775/875` 分别回退 layer `890/1174`，最终 static image blend 为 `[239,657,775,875,1509]`。775 的脚本包装 alpha 只读取作者初始值；事件、媒体封面和逐帧 SceneScript 更新继续未实现。
- 定向报告 `.codex/scene-texture-fallback-293-v3-20260723/report.json` 为 5/5，`2902406982` 回归报告 `.codex/scene-texture-fallback-290-20260723/report.json` 通过；最终 `.codex/scene-texture-registry-final13-20260723/report.json` 为 **13/13**，所有样本 stop 后无 residue，Scene 测试 **128 项通过、1 项跳过**。
- 截图只证明 `2938612768` 中央播放器/静态封面已出现；背景仍被现有 waterwaves 近似严重扭曲。property file/security-scoped bookmark、`$mediaThumbnail`、Texture Variants、effectful/nested provider、通用 shader executor 与动态脚本仍是后续独立切片，不能把本阶段写成 sceneTexture 已完整可用。

### 已完成：S2.4b file-backed `sceneTexture` 第一切片

- 属性面板只为当前 render plan 实际可执行的 texture property key 提供 PNG/JPEG picker；能力发现扫描全部 authored layer，避免由其他属性控制的隐藏层永远没有控件，播放时仍按当前有效可见层筛选实际 consumer。
- 文件选择保存按 wallpaper/property 隔离的 bookmark。安全作用域只覆盖同步 Scene 通知、各屏 `MTLDevice` 解码上传、宿主启动及屏幕参数变化后的 surface 重建，随后立即释放；显示文件名、切换壁纸和长期播放不持有 scope。坏 bookmark、删除文件、坏图或不支持扩展名均清理或 fail closed，不保留旧纹理。
- `SceneMetalView` 为每屏设备生成并持有实际 `MTLTexture`，沿现有 `SceneFrameTextureRegistry.userProperty` 候选进入 renderer；没有用户文件时继续使用 authored fallback。Debug 注入只接受隔离 sample root 内、解析 symlink 后仍在根内的 PNG/JPEG。
- `2938612768` 隔离副本向 `newproperty25/26` 注入 200×200 PNG 后两张纹理均加载，五个 static image blend consumer 继续 5/5、image 44/44；最终 `.codex/scene-user-texture-final13-r2-20260723/report.json` 为 **13/13**，Scene 测试共运行 **134 项**，其中 **133 项通过、1 项跳过**；签名 App 身份和 stop 后资源释放门通过。
- 当前只闭合静态 PNG/JPEG 和受限 image-blend consumer；真实 NSOpenPanel 选择后的跨重启恢复、沙盒构建和物理显示器热插拔仍需产品回归。system/media、current/previous thumbnail、Texture Variants、视频、任意 material property consumer、effectful/nested provider、动态 alpha 和 SceneScript 仍未实现，不能写成完整 `sceneTexture` 支持。

### 已完成：S2.4c provider resource/frame 双代

- `c86491e` 将 `frameEpoch` 与 `resourceGeneration` 分离；连续帧同 identity、同 `MTLTexture` 的 layer/property/system publication 保持内容代数，替换或缺席后重现换代，named target 继续按帧换代。
- 这使 `SceneImageBlendRuntime` 的既有缓存键真正代表 provider 内容变化，避免 `2938612768` 五个静态 consumer 在 60 Hz 下每帧重复 offscreen blend；不改变 B0 snapshot、Renderer 或 View。
- registry/image-blend/GPU 合同通过；隔离 `.codex/scene-provider-generation-293-20260723-1035/report.json` 保持 5/5，`.codex/scene-provider-generation-290-20260723-1036/report.json` 保持 named capture 6/6、binding 7/7。全量 Scene 测试 201 项、200 项通过、1 项跳过。
- 当前对象身份只适用于已验证的静态 publication。system/media/video 后续必须由 producer 显式提交内容 generation 与 metadata；异步取消、Texture Variants 和通用 material consumer 仍未完成。

### 已完成：S2.4d effect-instance target plan/table 基础

- `38e238d` 新增 `SceneGraphRenderTargetPlan`：从已获 strict execution 资格的单 effect/material 图解析完整 input/output/FBO identity、input/scale 像素尺寸与 first/last read/write lifetime；首写前读取明确返回 `historyRequired`。
- `SceneGraphRenderTargetTable` 在任何 Metal allocation 前完成 checked byte cost 和预算门，随后只在整组纹理全部创建且互不别名时返回；input/output 与 authored FBO 均按完整 effect-scoped identity 解析。
- Plan/Table 专项 10/10、全量 Scene 211 项中 210 项通过、1 项跳过，unsigned Debug App 构建通过。该提交尚未接入 pool/compositor，不改变现有 Blur 输出，也不构成通用 graph executor。
- 该基础随后由 `73f415b` 接入 strict Blur；本条保留为历史基础证据。history、copy、swap、compose、condition/function 继续 fail closed。

### 已完成：S2.4e strict Blur graph-target consumer

- `73f415b` 让 precise/standard strict Blur 都从 execution plan 携带原始 authored graph，并统一消费 `SceneGraphRenderTargetTable` 的 input/output/FBO identity；旧 `StandardBlurTargets` 路径已移除。
- pool 按完整 effect identity 缓存同 plan/extent 的表；跨 effect 不共享，同 effect resize 先完整创建候选再提交替换，失败保留旧 cache 与驻留记账。96 MiB 是提交后的 resident cache budget，不是瞬时 VRAM 硬上限。
- 非均匀 mixed-alpha GPU harness 逐阶段验证 precise 两遍与 standard downsample/横纵 ping-pong/combine；pool 专项覆盖稳定复用、隔离、LRU、resize、失败原子性、clamp、reset 与 legacy Pair 预算。
- 全量 Scene 218 项中 217 项通过、1 项跳过；正向与负向隔离矩阵各 3/3。strict Blur 仍为 `executed-degraded`，没有新增 profile 或可见成功层；generic scheduler、ShaderContract、history/copy/swap/compose/condition/function 在该提交时尚未完成。

### 已完成：S2.4f D7 ShaderContract IR v1

- `8474ace` 新增 `SceneShaderContract` 与安全 loader，将 authored vertex/fragment source、raw SHA-256、相对 stage path、include 引用及行号、JSON annotation/raw/marker/line、uniform/attribute/varying declaration、diagnostic 和 canonical SHA 持久化到 interpretation v19；精确 host built-in identity 使用无 stage 的显式合同。
- loader 对绝对路径、`..`、shader root/stage/include symlink escape、无效 UTF-8、缺失/不可读 stage、畸形 annotation 和重复 identity fail closed。benchmark 同时核对 wire 必填字段、source/raw hash、stage kind/path、nested arrays、diagnostic schema、host built-in 空 stage 与 canonical SHA，避免结构残缺的假绿。
- 正式 `.codex/scene-shader-contract-final13-v2-20260723/report.json` 为 **13/13**：173 contracts（143 authored + 30 host built-in）、286 stages、0 diagnostics；source 与 IR 的 include/annotation/declaration 数完全一致，为 `155/1523/2660`。全量 Scene **223 项、222 项通过、1 项跳过**；签名身份为 `2.0.8 (268)`、Team `H9QWU9XN8R`、CDHash `033bc40a5ee8dbf0d6bd0e478e9a8c5a875b90b4`、executable SHA-256 `2b6a8d6ee9863de41fd91792f682c2ff0c49ecf1dd15a9909d3d6e924f76bab8`。
- `8474ace` 阶段只完成 L1 source contract，不进行 include expansion、macro/permutation preprocessing、translation、stage link、compile、uniform upload 或 authored shader GPU execution，D7 整体仍未闭合；该阶段计划的下一切片是以 source contract identity 约束 stock Local Contrast 默认单效果 profile，随后已由 `136d35c` 完成。generic D7 的上述边界至今不变。

### 已完成：S2.4g `rgba8888` graph-target format

- `228cdde` 将 `SceneGraphRenderTargetPlan.TextureFormat` 扩到精确的 `rgba_backbuffer` 与 `rgba8888` 两项；table 分别分配 `.bgra8Unorm` 与 `.rgba8Unorm`，synthetic input/output 始终保持 BGRA。没有顺带开放 parser 已识别但尚无执行合同的 R/RG/float formats。
- 两种现有格式都是 4 B/px，继续走 checked resident budget；完整 plan equality 包含 format，因此同 effect/extent 的格式变化会先创建候选再原子替换，失败仍保留旧 cache。旧 backbuffer framebuffer、RGBA framebuffer、storage/usage、预算、别名、LRU、resize/reset 均有直接门。
- plan/table/pool 与 authored Blur/Metal framebuffer 相关 38 项通过；全量 Scene **225 项、224 项通过、1 项跳过**，代码健康和签名构建通过。签名身份为 `2.0.8 (268)`、Team `H9QWU9XN8R`、CDHash `6fc75d86b05d665138f8d7080cdf7e149522a10e`、executable SHA-256 `d237711dbd6f92628303431db10c5ecf8b8fdf0088789e1118b98048d518410d`。
- `228cdde` 阶段只提供 Local Contrast 所需的 quarter RGBA RT，不包含 pipeline、combine/alpha 算法、planner 或新 GPU layer，因此当时没有重跑无信息视觉矩阵；该阶段计划的下一步是 `2902406982` layers `167/177` 的 strict profile，随后已由 `136d35c` 完成，`2938612768` 的 mixed chains 仍继续失败关闭。

### 已完成：S2.4h exact stock Local Contrast strict profile

- `136d35c` 只接受精确的 `effects/localcontrast/effect.json` 单效果图：四个有序 material node、两个 FBO `scale=4` 的非 unique `rgba8888` quarter RT、固定 source -> A -> B -> A 绑定、normal/no-depth/no-cull state、`KERNEL0`、`GREYSCALE0`、`MASK0`，Gaussian 常量显式为 `scale=(1,1)` 或使用官方缺失默认值。planner 还要求 Local Contrast 三组 shader contract 的 identity、canonical SHA、stage path/kind 与 raw/source SHA 全部精确匹配，任一差异都 fail closed。
- 项目自有 Metal pipeline 执行 alpha-weighted 4-tap downsample、13-tap Gaussian X/Y，再按 `albedo + (albedo - blurred) * strength` 合成并保留原始 alpha；source/output 为 BGRA，两个 quarter target 为 RGBA。shader 指纹只用于准入，不编译或执行 authored source，也没有因此获得 generic shader translation 能力。
- `strength` 仅接受有限 `0...5`，缺失时使用默认 `1`；直接属性 binding 编译为 pass 3 `effectConstant`，由 host 活动 consumer 集合、per-surface snapshot 和 renderer 每帧消费。定向矩阵向 `2902406982:brcontraststrength=3.0` 注入后 `accepted=true`，surface/window identity 不变，changed ratio 为 `0.7588325436`；正式矩阵对应值为 `0.7587968185920577`，证明可见变化而非整场重建。
- 定向报告 `.codex/scene-local-contrast-targeted-20260723/report.json` 为 **2/2**：`2902406982` layers `167/177` 与既有 Blur layer `530` 均 graph succeeded、failed 为空、Local Contrast count 为 2；`2938612768` 的可见 4/5-effect mixed chains 保持 Local Contrast count 0，既有 static image blend 为 `[239,657,775,875,1509]`。两样本退出均为 `surface 1 -> 0`。
- 正式报告 `.codex/scene-local-contrast-final13-20260723/report.json` 为 **13/13**：graph GPU 成功层合计 8、失败 0、Local Contrast 2、legacy blocked 3、route-only 35。全量 Scene 共 **239 项，其中 238 项通过、1 项跳过**；代码健康与签名构建通过。App 为 `2.0.8 (268)`、Team `H9QWU9XN8R`、CDHash `f1fb8e1a4f65f64e869d82c064f4f31f9f5faae5`、executable SHA-256 `54b2b8e56c4ed7deda640caddfbd379c366a54335cf1253291956f3d24a608fe`。
- 当前边界仍是 `executed-degraded`：不接受 mask、greyscale、非默认 kernel、非默认 Gaussian `scale=(1,1)`、mixed chain 或通用 authored shader；Metal 实现按已核验的非 `HLSL_SM30` 语义运行，没有套用 HLSL_SM30 的 `0.75 / resolution` offset，也没有 Windows 官方像素 golden。运行证据证明属性被接受、identity 不变和画面变化，snapshot/GPU 单测证明消费路径，但尚无“实际上传 `3.0` uniform”的独立 telemetry。

### 已完成：S2.4i ordered strict effect-chain scheduler

- `b541867` 将 execution catalog 从单 plan 扩为按 layer 持有完整 chain；planner 保留作者 effect 顺序和全局 node index，验证 layer source -> effect output 的连续输入、唯一 effect/node/target identity、最终 output 与所有 stage 的 strict backend。任一 blocker、断链、重复/额外资源或 unsupported stage 都让整链失败关闭；singleton accessor 只为既有兼容入口服务。
- `SceneOffscreenTexturePool` 为整链预建所有 target plans/tables、计算完整 resident cost 与 LRU victims，成功后一次提交；预算、extent、format 或任一 allocation 失败均不改 cache、resident bytes、access counter 或 LRU。三阶段超预算且首段 cache hit 的测试直接锁定该回滚合同。
- `SceneAuthoredEffectChainRenderer` 在同一 `encodeOffscreen` command buffer 中按 stage 顺序执行，只在全部成功后把末段输出合成到 main pass。首段应用原 layer uniforms/masks/UV/alpha，后续 stage 使用 neutral uniforms/empty masks，避免重复 alpha 和局部效果；每个 Local Contrast stage 从完整 frame snapshot 单独解析 strength。
- synthetic 两段 Blur GPU 门锁定 first output -> second input、第二段可见处理、final -> main 和后段失败不泄漏前段画面。该阶段正式矩阵 `.codex/scene-effect-chain-gated-final13-20260723/report.json` 为 **13/13**；七个 effect-graph 代表样本锁定 chain/stage 精确计数，当时真实 multi-effect strict chain 为 0。该阶段全量 Scene **251 项、250 项通过、1 项跳过**；签名身份为 `2.0.8 (268)`、Team `H9QWU9XN8R`、CDHash `61fc420b6dc3c014d1e18f2cdf16fef1d127d5ec`、executable SHA-256 `629ae6daf23a6e62f2d9502042dc94b69a54419749e801b26c4743651bc12758`。
- 该阶段边界（历史）：scheduler 当时只连接已严格准入的 material-only stage，不执行 copy/swap/compose/history/condition/function，不解释任意 authored shader，也还没有真实 multi-effect 正向样本。随后 `809b75e` 已用 exact Workshop Shadow 关闭首条真实 chain；上述通用边界至今不变。

### 已完成：S2.4j exact Workshop Shadow 与首条真实 strict chain

- `809b75e` 只接受本地 Workshop 资产中完整核验的单 pass Shadow profile：唯一 definition/material/ShaderContract identity、固定 graph/node/output、normal/no-depth/no-cull render state、`BLENDMODE=0`、`MASK=0`，以及有限静态 `alpha/shadowColor/shadowDrawBorder/shadowOffset`。任何额外纹理、binding、RT、combo、动态 user binding、shader/hash 或结构差异都 fail closed；准入不读取样本 ID 或 layer 名称。
- 项目自有 Metal pipeline 在整链中消费前一 stage 输出，并在全部 stage 成功后才提交最终主画面。该路径只把 exact Workshop Shadow profile 记为 `L3 executed-degraded`；`common_blending` mode 0 没有官方像素 oracle，当前算法没有 Windows golden，因此不得宣称 WE 像素等价，也不得把官方 45 项 Effect 表的通用 Shadow 或 generic authored shader 提升为已支持。
- 定向报告 `.codex/scene-workshop-shadow-targeted-20260723-1536/report.json` 为 **1/1**；正式报告 `.codex/scene-workshop-shadow-final13-20260723-1540/report.json` 为 **13/13**。四个 strict backend 合计 stage 10、真实 chain 1、Workshop Shadow 1、GPU failed 0、legacy blocked 2、route-only 34；`3724289844` succeeded `[20,28,36]`、failed/blocked `[]`、stages 4、chains 1。
- 全量 Scene **258 项、257 项通过、1 项跳过**；签名身份为 `2.0.8 (268)`、Team `H9QWU9XN8R`、CDHash `e4c25d85cb1b878019ec6a7b9e334fd6caaef098`、executable SHA-256 `bd02f455de2e5e11cbc365dabee5063afa4c32ab28d959abcd8c8bb77746a8c0`。该阶段当时的下一切片是 stock Opacity `MASK=0`，随后已由 `b8842d8` 完成。

### 已完成：S2.4k exact stock Opacity 与 live alpha

- `b8842d8` 只接受 stock `effects/opacity/effect.json`、exact material raw SHA 和 vertex/fragment ShaderContract fingerprint、单 effect/单 material stage、`MASK=0`、无额外纹理/命令/condition，以及有限静态 alpha 或直接 user-property binding。SceneScript 值、MASK1、未知字段/hash/combo/state 和 unsupported mixed chain 均 fail closed；准入不读取样本 ID 或 layer 名称。
- Opacity alpha 由既有 binding program/per-surface snapshot 每帧解析，renderer 在预乘宿主边界统一缩放 RGBA。snapshot -> ordered chain -> GPU 像素门验证 alpha `1.0 -> 0.2`；错误或无 consumer 的 key 继续走整场重建，不新增属性旁路。
- 定向报告 `.codex/scene-opacity-targeted-290-final-20260723-1722/report.json` 验证 `2902406982` layers `[365,372,647,664]` 与 `newproperty50=0.2`；负向 `.codex/scene-opacity-failclosed-293-final-20260723-1725/report.json` 验证 `2938612768` candidates `[165,454,626,629,924]` 因 SceneScript 保持 Opacity/stages 0。正式 `.codex/scene-opacity-final13-20260723-1730/report.json` 为 **13/13**，矩阵 SHA-256 `47d01b05a60368cddc679393fb5dd11d562cd4b69cc9d4bd1f559c179fff4e23`；五个 strict backend 合计 stages 14、chains 1、Opacity 4、failed 0、legacy blocked 2、route-only 30。
- 全量 Scene **269 项、267 项通过、2 项跳过**；签名身份为 `2.0.8 (268)`、Team `H9QWU9XN8R`、CDHash `6e70e547f61dcc6821009a4ebbd97af156fb5916`、executable SHA-256 `0cbaff3bd989e5cb9f8807236fd270feec19ca1f18548c122ca3ccb74033774a`。293 仍有明显 unsupported effect 视觉偏差，不能把运行门升级为 WE parity。

### 已完成：S2.4l direct dynamic text 与首个异步 generation consumer

- `1762743` 将 interpretation 升至 v22，为 direct `textinput` content、slider point-size 和 color 编译稳定 text target；Host 只把有效可见且可栅格化的文本层登记为活动 consumer，隐藏层、conditional binding、静态 `text` label、SceneScript/time/media 继续 fail closed 或重建。
- `SceneDynamicTextTextureStore` 按 layer signature 去重，在串行后台队列重栅格化；per-layer generation 拒绝 A->B->C 中迟到的 B，失败保留 authored/last-ready texture，空字符串生成透明纹理，stop/deinit 不保留可提交状态。`SceneMetalView` 每帧只合并 ready texture，不替换 surface/window。
- 定向报告 `.codex/scene-dynamic-text-targeted-213-final-20260723-1907/report.json` 在隔离 `2134765860` 先用 `text=2` 启用作者 Custom 模式，再同时 live 更新 `customtext/textcolor/textsize`：accepted=true、surface `1 -> 1`、window `[94398] -> [94398]`、changed ratio `0.003541478640192539`、text `6/6`。正式 `.codex/scene-dynamic-text-final13-20260723-1915/report.json` 为 **13/13**，矩阵 SHA-256 `fbb252a64018cf785e20b2200db5966a300e9351a994b4a36f1fe9565c5b354c`，原 strict graph 指标保持 14 stage/1 chain/0 failed，sample root residue 为 0。
- 全量 Scene **273 项、271 项通过、2 项跳过**；签名身份为 `2.0.8 (268)`、Team `H9QWU9XN8R`、CDHash `25f1e84ab81ee23d270ea1e436de0e47ccd34489`、executable SHA-256 `85634666c237a9026ac89b04bc33815963f24fd77b339c1520f6cb20ae29f5d6`。这不等于 SceneScript clock/date/media 已执行，也不证明 Windows 字体/布局像素一致。

### 已完成：S2.4m 同帧 copy/swap command foundation

- `f1c6a10` 让 `SceneGraphRenderTargetPlan` 按作者 node 顺序编译 `copy/swap`，以声明过且已写入的 logical RT 为前提，拒绝未声明、读前写、尺寸/格式不一致、condition/compose、同物理纹理 alias 和未知 command。command 不消耗 material ordinal。
- `SceneGraphCommandRuntime` 在同一 Metal command buffer 中以 blit copy 完整纹理，并通过交换 logical identity 到 texture 的映射实现 swap；测试直接验证 copy 后字节一致和 swap 后映射交换。这是资源命令基础，不是通用 material-command scheduler。
- 隔离定向门 `.codex/scene-copy-swap-targeted-372-20260723-1945/results-pass/report.json` 为 1/1；`3723344874` 观察到 copy definition 1、swap definition 2、graph swap node 2，但仍因 function/condition blocker 保持 stage/chain 0。正式 `.codex/scene-copy-swap-final13-20260723-1955/report.json` 为 13/13，原 strict graph 指标不变，sample root residue 0。
- 全量 Scene **275 项、273 项通过、2 项跳过**；签名身份为 `2.0.8 (268)`、Team `H9QWU9XN8R`、CDHash `c0940f2da38e653e338d829663ad3a0596c73b50`、executable SHA-256 `fe940c3d6706655d0a07556ef7570ab581c9ee000c5ec62344bd0df92c6d9827`。在该历史提交时尚未实现 history/persistent reset、compose、condition/function 或真实 Fluid/Motion Blur GPU stage；后续由 `dcedc2e` 补入受限 history seed/clear 生命周期。

### 已完成：S2.4n persistent history target seed/clear

- `dcedc2e` 将 `SceneGraphRenderTargetPlan` 的读写生命周期扩展为受限 history 判定：非 unique FBO 的读前写继续返回 `historyRequired`，显式 `unique:true` FBO 才能通过，并在 logical target lifetime 记录 `requiresHistorySeed`。该判定只建立资源生命周期前提，不把 `unique` 推断为跨帧 history 语义。
- `SceneGraphRenderTargetTable` 在 pool 复用的 table 首次消费时，为所有需要 seed 的 target 编码一次透明 GPU clear；只有 command buffer 成功完成后才提交 initialized 状态，GPU 失败可重试。现有 effect/plan cache 继续负责跨帧复用，reset/resize/switch 丢弃旧 table 并重新初始化；compositor 与 strict effect-chain renderer 都经过同一初始化入口。
- 专项 graph/Metal 测试 **14 项通过**；最终签名 Debug App 在隔离 sample root/HOME 下复制当前真实 Workshop `Scene` 目录 26 个样本，报告 `.codex/scene-history-full26-final-20260723-2332/results-pass/report.json` 为 **26/26**、residue `0`，strict stage 24、failed 0、chain 0、Opacity 4。真实目录保持只读；26 个样本没有合法的正向 history consumer，因此本批只证明 table 初始化和既有样本无回归。
- Scene 全量测试 **279 项、277 项通过、2 项跳过**；签名 App 为 `2.0.8 (268)`、Team `H9QWU9XN8R`、CDHash `557e57e3c6f55ee73a147787f84251e099092256`、executable SHA-256 `337327019eff96866a2bb493ff1cf379dfaee14f849a4fb6dcf0e7b4b3415193`。该能力当前为 `L2 wired/routed`，不宣称 Motion Blur/Fluid 执行、跨帧 logical swap、seek/pause/fixed-step history、compose、condition/function 或 Wallpaper Engine parity。

### 已完成：S2.4o Precise Blur material-command interleave

- `ebf44a9` 新增 `SceneGraphNodeScheduler`，按 authored `nodeIndex` 合并调度 material 与 copy/swap，并把当前 logical texture mapping 传给 material encoder；swap 后的后段 material 因此读取交换后的物理 texture。scheduler 复用既有 plan/table/command runtime，不复制资源身份或生命周期状态。
- Precise Blur strict planner 只新增两个完整白名单拓扑：`material0 -> copy -> material1` 要求两个 descriptor 匹配的非 unique BGRA target；`material0 -> swap -> material1` 要求 destination `unique:true`。late command、compose、未知 topology、资源不匹配和既有 blocker 继续整图失败关闭；其余四个 strict backend 没有扩宽。
- 定向 graph/runtime/Metal/semantics 测试 **72/72**；Scene 全量测试 **282 项、280 项通过、2 项跳过**。synthetic GPU 门证明 pure material、copy interleave、swap interleave 输出在阈值内一致、非空并保持 premultiplied alpha。
- 当前真实目录 26 个只读来源复制到 `.codex/scene-command-interleave-20260724-003051/sample-root`，manifest 复核零差异；最终完整门 `full26-results-pass2/report.json` 为 **26/26**、residue 0、strict stage 24、failed 0。固定门 `final13-results-pass/report.json` 为 **13/13**、residue 0、stage 14、chain 1、failed 0。`3723344874` 仍因 function 1/condition 4 保持 stage/chain 0；当前真实集合没有正向 interleave sample。
- 签名 App 为 `2.0.8 (268)`、Team `H9QWU9XN8R`、CDHash `9dbff1cfcdff7bba12d0c8b69d5f58722a938337`、executable SHA-256 `8ccf1804bf11c3f0933abf9f55dc94295b2fc618378e19efb53cf72d2bf87e31`。只有 Precise Blur 两个 profile 达到 `L3 executed-degraded`；generic FBO command graph 仍为 `L2`，不宣称跨帧 logical swap、真实 history consumer、compose、condition/function、Motion Blur、Fluid 或 WE parity。

### 已完成：S2.4p exact Blur Precise legacy compose normalization

- `4f13daf` 只接受 exact `KERNEL=0` Blur Precise 的 legacy 两遍定义：第一 material 带 `compose:true`，第二 material 为 Gaussian Y。planner 合成 `_rt_FullCompoBuffer1`，横向 pass 从 `previous@0` 写该 target，纵向 pass 从 target slot 0 写 effect output；显式 authored FBO profile 的 exact extent 门不放宽。
- 定向 planner/GPU 测试 **34/34**；4K legacy profile 可使用 2048 offscreen cap，但 blur offset 继续按原始 source extent 归一。generic compose、Refraction、scene-background capture、mixed shape、非 `KERNEL=0` 和任意 kernel 继续失败关闭。
- 当前完整门 `.codex/scene-legacy-compose-20260724/full26-results-pass3/report.json` 为 **26/26**、residue 0，graph target 153、blocker 0、strict stage 24、failed 0、legacy blocked 19、route-only 67；固定门 `.codex/scene-legacy-compose-20260724/final13-results/report.json` 为 **13/13**、stage 14、chain 1、Opacity 4、Workshop Shadow 1、failed 0。原始 `2067939514` 与 `2802243144` 的 graph blocker 分别 `32 -> 0`、`6 -> 0`，但 strict stage 都仍为 0，完整链继续被 unsupported sibling 阻断。
- 正向隔离门 `.codex/scene-legacy-compose-20260724/positive-results-pass/report.json` 只在 `2802243144` 副本中关闭 layer 41 的无关 Shake sibling，保留原 Blur definition/material/shader/参数；结果 1/1、layer 41 stage 1、failed 0。它证明 executor 可运行，不是原始样本视觉改善证据。
- Scene 全量测试 **286 项、284 项通过、2 项跳过**；签名 App 为 `2.0.8 (268)`、Team `H9QWU9XN8R`、CDHash `b82bb2a7ac697b34acf4ec491b0a9841224027c4`、executable SHA-256 `cf477e7b10b26e67144d0bc80a79f62de748229486742b2936422d4e4e2411bb`。本批没有增加原始 26 样本 strict stage 或减少 legacy blocked layer，因此完成后暂停实现并进入可见收益路线复盘。

### 已完成：S2.4q exact stock Shake 与未修改样本 Blur/Shake chain

- `e505a9e` 新增 exact stock Shake planner/pipeline/renderer，只接受精确 definition/material/raw shader fingerprint、单 material stage、`MASK=0/AUDIOPROCESSING=0/NOISETEXTURE=0`、RG8 flow 与 R8 phase 或 authored white fallback；scene time 沿 ordered chain 传入 GPU。动态 speed/audio/noise/direction、MASK1、未知 combo/state/fingerprint 和 unsupported sibling 继续整链失败关闭。
- 定向 `.codex/scene-shake-20260724/targeted-contract-final/report.json` 为 **2/2**。未修改 `2802243144` 的 layers `[41,64,115]` succeeded、failed `[]`、Shake 3、chains 3、stages 6，覆盖 `Blur Precise -> Shake` 与 `Shake -> Blur Precise` 两种作者顺序；warm-run changed ratio 稳定在约 `0.00977...0.01031`。`2134765860` 的动态 audio/speed variant 保持 Shake/stage 0。
- 当前完整门 `.codex/scene-shake-20260724/full26-final/report.json` 为 **26/26**：stage 30、chain 3、Shake 3、failed 0、legacy blocked 16、route-only 64；固定 `.codex/scene-shake-20260724/fixed13-final/report.json` 为 **13/13**：stage 14、chain 1、Opacity 4、Workshop Shadow 1、failed 0。两门不能互相替代。
- Scene 全量测试 **292 项、289 项通过、3 项跳过**；两个 cross-device 测试因没有第二块 Metal GPU 跳过，既有 particle runtime 测试因旧 `.codex` fixture 不存在跳过。签名 App 为 `2.0.8 (268)`、Team `H9QWU9XN8R`、CDHash `0d7efcabf4b99a101a3341e64fb10d80ef8a4020`、executable SHA-256 `7cdb04292a891e7787d0fa489c8fbeb5337332e436bc0ea2de1b9827a135cbca`。
- 这是最近批次首次让未修改真实样本的 strict stage、chain、blocked 和动态像素同时改善，证明“按完整链缺失 backend 选项”比只减少 graph blocker 更接近可见收益。封面可作为固定画布上的主构图/色调/明显效果范围参考，但不替代 Windows WE 动态或像素 golden。

## 5. 样本规范

- Steam App ID 固定为 Wallpaper Engine `431960`；记录 Workshop ID、下载日期、标题、文件 SHA-256 和下载方式；
- SteamCMD 必须运行在 `.codex` 可写副本，不能让自更新改动签名 App bundle；
- Steam 下载缓存只作为来源，测试前移动或复制到 `.codex/scene-representative-samples-<date>/Scene/<id>`；
- 真实 `~/Movies/MyWallpaperX/创意工坊` 始终只读；benchmark 使用隔离 sample root 和临时 HOME；
- 样本二进制不提交 Git，仓库只提交矩阵、来源、哈希和能力标签。

## 6. 开发规范

- 修复前记录预期、实际、根因假设、影响文件、样本范围和验收标准；
- 公共 parser/renderer 修复优先于样本绕过；
- 一个独立能力一个代码提交，完成目标样本和相关样本验证后才提交；同一能力链的 2-4 个代码提交可在批次结束后统一做一次文档提交。能力等级、现役报告/签名、wire/schema 或路线结论变化时必须立即同步；
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
- 5-6 个关键样本使用封面自身比例的固定画布生成并排图，检查主构图、主体位置、色调/亮度和明显效果范围；不把封面当动态时序或像素 golden；
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
