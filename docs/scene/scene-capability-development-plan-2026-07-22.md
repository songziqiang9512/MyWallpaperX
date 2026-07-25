# Scene 播放能力开发计划

> 建立日期：2026-07-22
>
> 最近更新：2026-07-25（实现基线 `928acca`；interpretation v25；十一类 strict effect backend、Puppet bind-pose/静态 MDAT/严格单 clip MDLA CPU LBS、strict depth-one eventspawn/natural-eventdeath/eventfollow child，以及非音频 turbulent velocity 是当前执行子集；Event Follow 只接受 identity/no-CP/瞬时 Sprite child。`particle/light/light_shafts_0` 已把程序化 built-in registry 扩到 15-key。BC1/2/3 颜色纹理在单 image 16M 像素预算内走 CPU premultiply，超预算或多 image 载荷走 GPU premultiply；跨 image sprite 当前只裁出 authored 首帧作静态 fallback，不执行完整动画。REFRACT 粒子材质 fail closed。`a5a951f` 的完整 45 样本快照门 45/45、particle 91/131；`928acca` 的固定 13 样本门 13/13、particle 18/27）
>
> 作用：定义 MyWallpaperX Scene runtime 从当前可审计子集向 Wallpaper Engine 常用能力逼近的实施顺序、样本门和验收标准。作者/执行语义先查 [`semantics/README.md`](semantics/README.md)；当前能力结论仍以 [`../reviews/web-scene-current-state-roadmap-2026-07-19.md`](../reviews/web-scene-current-state-roadmap-2026-07-19.md) 与最新运行证据为准；历史 memo 不反向覆盖本计划。已完成批次的逐项验收记录收敛到第 8 节索引与 [运行证据索引](semantics/runtime-evidence-index.md)，不再在本文正文逐段展开。

## 1. 目标与边界

目标不是宣称私有格式 100% 兼容，而是让常见 Windows Wallpaper Engine Scene 壁纸在 macOS 上达到可播放、可交互、可配置、可诊断和可持续回归的工程状态。

实现优先级由四项共同决定：

1. 真实 Workshop 样本命中频率；
2. 对首帧和主要视觉构成的影响；
3. 能否建立确定性自动验收；
4. 实现的来源、维护成本和安全边界。

当前采用 **coverage-first** 迭代：先让官方语义表中的主要系统各自拥有可运行、可诊断、fail-closed 的最小闭环，使跨系统依赖和冲突尽早暴露；随后再按共享根因和视觉收益打磨精度。这里的"覆盖"不等于放宽支持口径：状态统一分为 `recognized`、`graph-built`、`executed-degraded`、`semantics-verified`，只有最后一档可以宣称语义已验证。

不采用以下捷径：

- 不把 Scene 转成 Web 播放；
- 不按单个样本 ID 硬编码；
- 不把 route-only、占位 shader 或静态截图写成"效果已支持"；
- 不执行未知 SceneScript，也不直接加载来源不明的预编译 DirectX shader；
- 不直接修改真实 Workshop 样本。

## 2. 2026-07-25 当前代码事实

### 已真实进入运行链

- `project.json` / entry 同名 `gifscene.json` 识别、PKGV 索引、受控缓存解包、路径校验和 interpretation format 25；v25 在 v24 static attachment frame 之上增加 authored Puppet animation layer 声明；
- PNG/JPEG、raw RGBA/RG/R8、BC1/BC2/BC3/BC5、LZ4、MP4 payload 和 TEX sprite sequence；**BC1/2/3 颜色载荷现在统一满足 premultiplied 合同**：单 image、16M 像素预算内由 CPU 解码并裁剪 padded 存储（`8bac86e`），超预算或多 image 容器先原生 BC 上传，再由 `MPSImageConversion` 在 GPU 上 straight->premultiplied（`18d0056`）；跨 image sprite 只裁出可表达的 authored 首帧作静态 fallback，旋转/越界首帧 fail closed，尚不播放跨 image 动画。`3768903841` 的 5-image/140-frame BC3 资源因此从整张 `7680x7560` atlas 降为每层 `1920x1080` 首帧，消除整 atlas 与 straight-alpha matte；BC5 法线载荷保持 GPU 原生直通；行级并发解码保证未优化 Debug 构建 4K 纹理亚秒级加载；
- **Puppet bind-pose、静态 MDAT 与严格单 clip MDLA**：`8bac86e` 重组 MDLV0021/0023 bind pose；`49ee89a` 按 `parentWorld * attachmentBind * childLocal` 定位 MDAT child；`ca6d841`/`56f92a2`/`2be2b44` 保存 MDLA0006 full TRS、MDLS hierarchy 与 80/84-byte vertex weights；`f1ee79b` 以 `T * Rz * Ry * Rx * S`、hierarchical world、`animatedWorld * inverse(bindWorld)` 和 normalized four-weight CPU LBS 播放单个静态可见 loop clip。当前按 source FPS 离散采样；mixing、插值、非 1 rate/blend、动态 visibility、动画 attachment follow、constraint/IK/physics 保持 fail closed；
- Metal image/solid/text/particle 合成、父子 transform、有效可见性、source order、alpha、正交/透视粒子相机和桌面多屏宿主；
- 宿主级单一 60 Hz frame driver 与 `SceneFrameTiming` / `SceneFrameContext` 第一阶段：所有屏幕共享一次采样的 frame index、host time、scene time、frame delta 和 wall date；shader、视频帧、粒子 simulation 与 parallax smoothing 已迁移，屏幕尺寸和 pointer 仍按 surface 独立保存；
- B0 live-property runtime 已合龙：`SceneDynamicValue` 覆盖 bool/scalar/vector2/vector3/vector4/string，target 覆盖 scene/camera/layer/effect/text/particle/script instance，resolver 固定按 `authored -> userProperty -> Timeline -> SceneScript` 覆盖并拒绝重复、错类型和非有限值；binding program 包含 layer alpha/color、direct text content/point-size/color、exact stock Local Contrast pass 3 `strength` 与 exact stock Opacity `alpha` target；Host 为每个 surface 独立求值 per-surface snapshot 并持有 generation，属性更新经原子 live state 路由到 renderer；
- 当前 live consumer 严格限定为 image/solid/text 和 `shouldCapture` utility 的 layer alpha、solid layer color、有效可见 text layer 的 direct content/point-size/color，以及已通过 strict planner 的 Local Contrast `strength`、Opacity `alpha` 与 X-Ray visibility/size/multiply/texture target。文本只重栅格化变化层，重复值不生成，旧 generation 和失败结果不能覆盖最后可用纹理；hidden/no-consumer、SceneScript/time/media、particle、container、non-solid color、其他 effect constant、mixed 或 unsupported key 返回整场 `requestSceneRender`；
- cover 投影；Camera Parallax 服从 Scene options、显式逐层 depth、传播和属性 override；包括 composition 在内，缺失或零 depth 不产生逐层位移；
- legacy coarse blur 仍只服务尚未迁移的受限路径；authored graph 已分别把 precise Blur、stock standard Blur、exact Local Contrast、Shake、Water Waves、Water Flow、Foliage Sway、Water Ripple 与 X-Ray 选路到完整 fingerprint 约束的项目自有 MSL backend。非 exact 声明仍只在既有 inline 边界内执行；unsupported mixed/repeated 声明继续 fail closed。标准 Bloom、perspective+opacity、mode 9 additive，以及其他 water/cursor/chromatic/iris 等仍是明确标注的受限实现；
- pointer 由桌面宿主以每 surface 状态送入 renderer，X-Ray 使用 layer-local pointer、组合区域 source capture、authored blend/halo/opacity texture 与受限 live target。`2998757800`、`3747492842`、`3757555836` 已由用户在真实桌面壁纸路径确认鼠标遮罩正常；
- text 以 authored `pointsize * 4` 近似 300 DPI point raster、处理 vector padding、包内字体、系统字体别名和缺失字体诊断；direct user property 的 content/point-size/color 已按变化 layer 异步重栅格化；
- 作者包内 2D sprite 粒子的 definition/resource graph、sphere/box、rate/burst/prewarm、常见 initializer/operator、sequence/random frame、additive/translucent、朝向、静态 override、CPU simulation 与 Metal instancing；现对 `particle/drop`、`particle/chromaticdot`、`particle/fire/fire1`、`fog1`、`leaves7/8`、`light_shafts_0/6`、`lightning3`、`halo/halo_2/halo_4`、`ripple_single`、`rosepetals`、`beam_1` 十五个精确 key 提供项目自行生成的确定性预乘纹理，并支持按速度方向和作者 length/min/max stretch 绘制 Sprite Trail；child particle 的 eventspawn 触发、trail 渲染与粒子预算已进入受限执行（`f4173ea`、`7d53c10`）；这些程序纹理是 `executed-degraded`，不是官方纹理副本或像素等价实现；
- **REFRACT 粒子材质 fail closed**（`8bac86e`）：折射粒子携带 blank 颜色纹理 + normal map，无法当作颜色 sprite 绘制；此前被画成白色方块（`3769688830`/`3722933264`/`3723230275` 的"雨滴折射"层），现按 `refractionUnsupported` 诊断整层不实例化，直到真实 refraction pass（background capture + normal 折射）存在；
- 用户属性定义、group/display condition/options、默认值/override、visibility/text/camera 与部分 effect target、按壁纸持久化、活动 Scene 受控重建和独立属性窗口；`sceneTexture` PNG/JPEG picker、按 wallpaper/property bookmark、同步 security-scope 解码、逐屏 Metal 上传、恢复作者默认和失败回退；
- typed `composition/project/fullscreen` 与 generic dependency layer ID；对满足严格边界的 utility layer 执行当前 framebuffer 前缀捕获，并支持 `_rt_imageLayerComposite_<id>_a` named target 的有预算发布与 clipping consumer 绑定；
- effect/material pass 的 typed user texture input、typed texture registry（resource generation 与 named frame epoch 双代）、v15 EffectDefinition IR、v16 authored graph planner、v17 provider identity、ShaderContract IR v1、`rgba8888` target format、ordered strict effect-chain scheduler、effect-chain target allocation 事务、同帧 copy/swap command、受限 history seed/clear、Precise Blur material-command interleave 与 exact legacy compose 归一化——逐项边界见第 8 节历史索引与对应 semantics 表；
- 签名 Debug App、隔离 sample root/HOME、Metal ready/after 双帧、语义合同和 stop 后 surface=0；`a5a951f` 的完整快照门 `.codex/scene-lightshafts0-full45-20260725/report.json` 为 **45/45**、particle **91/131**，报告/矩阵 SHA-256 为 `44d299f0c6757ae46e59e9486bbf5ee423f7dc908d9fa6ddbae72b8c90578c38` / `b005da924cfefbcd08410d298f8795af67086f62c7df95ca802988fcfabea38e`；45 门 strict 为 stage 91、chain 15、failed 0。`2f897bc` 的固定回归门 `.codex/scene-continuous-child-final-fixed13-20260725/report.json` 为 **13/13**、particle **18/27**，报告/矩阵 SHA-256 为 `19135b84d74082f0cdcd5474157e0d1cbc8324379d8d706ae089236ad2d8433e` / `479b794d64b48369348b4b8e6583599e5ac70161a4f670102332f5cd1e2d653c`；Flare 定向门 `.codex/scene-continuous-child-final-flare-20260725/report.json` 为 **1/1**，报告 SHA-256 `3ca3c4919b3ed2d5aa6142775e27a809090a49bc0cd5ba9b9008ce832726b2e5`，particle 仍为 `8/15`。当前固定/定向 App 为 `2.0.8 (268)`、Team `H9QWU9XN8R`、CDHash `fe2036eabd4d4093340dd372565a1d95e98c1f72`、可执行文件 SHA-256 `3ebc20173bb8a942765078c16eb0dc288b9843145f974596eab8c2cc8779f308`；完整 Scene suite 为 **376 项：373 通过、3 跳过**，代码健康为 442 Swift files。完整聚合缺口见 [运行证据索引](semantics/runtime-evidence-index.md)。

### 仅解析/诊断或部分实现

- authored graph 只有十一类 strict backend 进入 renderer；named target、静态 image blend 和其余手写 effect 仍是受限执行器，dynamic variants、child/nested target、effectful/media provider、真实 history consumer、generic compose/scene-background、history 的跨帧语义、condition/function、其他 topology 和通用 material/shader 尚未实现；
- Puppet 已执行 bind-pose、受限静态 MDAT 与严格单 clip MDLA/LBS；挂点 child 仍只处于 bind frame，不随骨骼动画跟随，mixing/插值/constraint/IK/physics/channels/clipping 也未执行；`Water droplets` 虽保留 attachment frame，粒子层本身仍 unavailable；
- typed frame texture registry、authored fallback 和 PNG/JPEG property file/bookmark/decode 已进入 runtime；通用 provider metadata/status/cancel、`$mediaThumbnail`、Texture Variants、video frame、通用 material property consumer、effectful/nested provider 与真实 persistent/history consumer 尚未接入；
- Timeline 没有正式 target/keyframe/mode/tangent/event IR；SceneScript 只发现 `.js` 资源和 inline `script` presence，没有 ECMAScript runtime、`init/update`、事件、globals、Date/Math live value 或属性写回；
- 用户属性的 Texture Variants、media/video texture、transform、non-solid/mixed color、其他 effect constant、particle/audio/puppet target 和 SceneScript `applyUserProperties` 仍未闭环；
- 除 13 个精确 key 外的 built-in particle（如 `rain_drops_sheet`）、rope/rope trail、world-space、control point、collision、音频和动态 override 未实现；particle exponent 已解析未消费；
- 多 foliage 栈、vertex sway 与 workshop 自定义 sway 未实现；Scene 音频/媒体未接现有系统服务；SceneScript/系统时间/日期/媒体驱动的 text、Puppet mixing/advanced deformation、3D/lighting、自定义 shader 均未实现；
- Frame Context 尚缺 pause/resume、长帧 delta clamp/dropped-time、fixed timestep、audio/media producer 和离线 adapter；fullscreen/battery、目标 FPS、CPU/GPU/显存预算和 soak 也未闭环。

固定 13 样本门 PASS 不能解释成 Wallpaper Engine 视觉兼容率：它只证明矩阵声明的解析、GPU 完成、非黑画面、能力计数和释放门通过。`3769688830` 的主体构图、静态 attachment、严格单 clip MDLA 与受限樱花/光束粒子已恢复，但 Puppet 插值/mixing/动画 attachment follow、官方粒子纹理像素等价与折射雨仍缺；`2131872317` 的 natural-eventdeath 烟花已在延迟门可见，`3750813609` 的动态时钟、完整 Clouds/Blur、world-space 雨滴溅射等差距不变。

## 3. 官方资料核验后的契约边界

[Wallpaper Engine Scene 能力参考](wallpaper_engine_scene_compatibility.md) 的能力地图总体成立；底层开发合同现统一放在 [Scene 语义手册](semantics/README.md)。官方资料描述编辑器/官方运行时行为，没有公开稳定的 Workshop 序列化格式。实现必须标注"官方行为、样本实例、WE-compatible asset 观察、第三方播放器解释、MyWallpaperX 现状"五类证据，不能把后两类反向写成官方规则。

当前直接影响架构与验收的官方契约：

1. [Camera Parallax](https://docs.wallpaperengine.io/en/scene/parallax/introduction.html) 必须由 Scene options 开启，并逐层尊重 parallax depth；0 表示该层关闭。[Depth Parallax](https://docs.wallpaperengine.io/en/scene/effects/effect/depthparallax.html) 是独立 effect，还要求 Camera Parallax 开启且当前层普通 depth 为 0。
2. [Timeline](https://docs.wallpaperengine.io/en/scene/timeline/introduction.html) 包含 Loop/Mirror/Single、start paused、默认 Bézier、左右切线和 wrap-loop。动画事件通过同层 SceneScript `animationEvent` 触发，不直接操作声音或图层。
3. [SceneScript](https://docs.wallpaperengine.io/en/scene/scenescript/reference.html) 是属性绑定型 ECMAScript 运行时；动画先求值，脚本再更新并可覆盖结果。不能先造一个与 layer/effect/text/particle target 脱节的通用 JS 执行器。
4. [User Properties](https://docs.wallpaperengine.io/en/scene/userproperties/overview.html) 的控件、默认值、直接绑定、条件显示与持久化应先于脚本回调；`applyUserProperties` 首次加载后只携带变化键。
5. [SceneScript AudioBuffers](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/AudioBuffers.html) 为 16/32/64 可选频段，提供 left/right/average 并每个渲染帧更新；不能直接套用 Web 固定 64+64、约 30Hz 回调合同。
6. [Bloom](https://docs.wallpaperengine.io/en/scene/effects/bloom.html) 区分标准 Bloom 和 Ultra HDR，并有逐层 HDR brightness；自定义 shader/3D/Puppet 的能力虽强，但没有当前 2D 主构图资源链优先。
7. [RGB Composition](https://docs.wallpaperengine.io/en/scene/rgb/introduction.html) 明确像相机一样记录其下方图层；[Effects](https://docs.wallpaperengine.io/en/scene/effects/introduction.html) 和 [Blend](https://docs.wallpaperengine.io/en/scene/effects/effect/blend.html) 允许链接动态 layer。官方没有公开 Workshop named-target 名称、dependency DAG 或 `projectlayer` 稳定格式，这些只能由隔离样本建立内部合同。
8. [Foliage Sway](https://docs.wallpaperengine.io/en/scene/effects/effect/sway.html) 区分 UV 与 Vertex 模式，并由 mask 和作者参数限定作用区域。当前只把单个 built-in UV 变体计为受支持，多 effect 栈、Vertex 和 workshop shader 必须继续 fail closed。
9. [Shader Variables](https://docs.wallpaperengine.io/en/scene/shader/variables.html) 中 `g_TextureNResolution.xy` 表示物理纹理尺寸、`.zw` 表示映射尺寸；mask/effect UV 需要保留这两套尺度，不能假设 source 与 mapped size 相同。BC 颜色纹理解码后裁剪到 image 尺寸使两套尺度在这些纹理上重合，但 TEX 直通路径（PNG/JPEG/BC5）仍必须保留 mapped UV scale。
10. [Particle Renderer](https://docs.wallpaperengine.io/en/scene/particles/component/renderer.html) 定义 Sprite Trail 按粒子速度方向对齐，并按 speed、length 与 min/max stretch 控制长度。当前实现仅复用 2D sprite quad 覆盖该子集，不据此宣称 rope、child 或完整粒子 renderer 兼容。官方 General 把 refraction 列为 renderer variant 之一；REFRACT 材质在真实 refraction pass 存在前必须 fail closed，不能用颜色 sprite 冒充。
11. [Shader Variables](https://docs.wallpaperengine.io/en/scene/shader/variables.html) 公开 `g_Texture0...7`，但 slot 含义由当前 material/shader annotation 决定；nullable texture slot 不得压缩，也不存在通用的"slot 1 永远是 mask"。
12. WE-compatible effect definitions 与可审计播放器共同证明 `target`、`bind`、`compose`、`command:copy/swap`、RT scale/format/unique 是执行字段；`unique` 只声明实例唯一性，不能单独推导跨帧 history，history 必须由读前写、copy/swap 和生命周期数据流判定。raw schema 并非官方公开合同，新增执行语义仍要由合法官方 assets 或真实样本交叉验证。
13. Puppet `.mdl`（MDLV0021/0023）没有官方公开格式。mesh/MDLS/MDAT/MDLA 合同来源是**第三方播放器解释 + 三来源真实 Workshop 资产交叉验证**，不是官方规则；静态 attachment 只接受已验证的 MDLV0023/MDLS0004/MDAT0001，动画只接受 MDLV0023/MDLS0004/MDLA0006、80/84-byte weights、loop 与 strict single-clip profile。真实 MDLA 会变化 translation/scale，不能按编辑器建议丢弃；任何超出已验证形状的数据必须 fail closed。

## 4. 实施路线

所有未完成阶段受 [公共能力依赖图](semantics/capability-dependency-map.md) 约束。研究和 fixture 可以并行，产品执行按 `D0-D8 -> D9-D10 -> D11` 推进；后续某个样本再显眼，也不能绕过 host/surface scope、identity、provider、graph、shader contract、coordinate space 或 lifecycle 建旁路。

阶段划分与已完成边界：

- **S0 可重复基线与作者语义门**、**S1 首帧主构图基础闭合**、**S2.1-S2.4 效果图谱与 strict backend 系列**、**S3 B0 live-property 主链**、**S4 第一批程序化粒子纹理**均已完成，逐项能力、提交与边界见第 8 节历史批次索引；
- **S2（进行中）**：在现有 strict profile 上提取共享 material pass executor、stock shader registry 和 preprocessing IR；generic compose、真实 history consumer 与 typed shader defaults/built-ins/state 仍未完成。高命中 Effect 批次继续只能通过新增共享 graph/shader/provider/space primitive 或注册完整匹配且 fail-closed 的 strict profile 实现，不得扩大 effect-name/path-substring 手写近似；逐项门见 [Effect 执行覆盖表](semantics/effect-execution-coverage.md)；
- **S3（进行中）**：Frame Context 补 pause/resume、raw/simulation delta、discontinuity、fixed-time test adapter 和目标 FPS；Timeline 先完整保留 keyframe/mode/tangent/event 数据再接播放；SceneScript 先保存 source/binding IR，再接 sandbox VM、lifecycle、typed write 和 budget；
- **S4（进行中）**：strict depth-one eventspawn/natural-eventdeath/eventfollow 已复用 fixed step + deterministic event queue + child owner/budget 执行，持续/混合/duration child emitter 与 root child aggregate budget 已闭合，`rosepetals`/`beam_1` 已补入高频 built-in texture；粒子下一步扩 Flare 三张 built-in 纹理、static/collision/delete、event transform/CP/value inheritance、跨层/递归 total budget。rope/rope trail 仍需独立 geometry/material renderer，audio response 仍需 injectable audio snapshot；前置未完成时只补 IR/fixture，不提前接产品执行；
- **S5**：音频、角色、高级兼容与发布门。Scene 音频桥按脚本选择提供 16/32/64 left/right/average；stock WE-compatible shader source/annotation/combo/built-in/state contract 属于 S2 Graph 前置，任意 Workshop custom shader 的通用翻译、安全、缓存与分发产品化才属于 S5；每个阶段持续记录加载时间、纹理内存、粒子上限、帧时和降级原因；最终建立固定/扩展/新下载三层矩阵、30 分钟交互、2 小时 soak、系统生命周期和发布 checklist。

### 当前批次优先级（2026-07-25 起）

`8bac86e`/`dd85dcf` 已关闭 Puppet 图集重组、预算内 BC 颜色 premultiply、REFRACT fail-closed；`49ee89a` 关闭静态 MDAT attachment；`ca6d841`/`56f92a2`/`2be2b44`/`f1ee79b` 关闭三来源 MDLA IR、full TRS、rig/weights 和严格单 clip fixed-step CPU LBS；`c654571`/`f02f41d`/`a5a951f` 将 built-in registry 扩到 15-key；`18d0056` 关闭超预算/多 image BC1/2/3 的 GPU premultiply 与静态 authored 首帧 fallback；`4a17ee6` 关闭非音频 Turbulent Velocity Random 的受限执行，audio 继续 fail closed；`928acca` 关闭 identity/no-CP Sprite child 的 Event Follow owner、逐帧位置更新与父死亡回收；`2f897bc` 关闭持续/混合/duration child emitter、每 system 1,024 粒子与 root child runtime 64 system/65,536 capacity aggregate budget。按样本收益与公共依赖排序的下一批候选：

1. **Flare 三张 built-in 粒子纹理**：`2998757800` 的 non-audio turbulent velocity、strict Event Follow owner、持续/混合/duration child emitter 与 root aggregate budget 已由自动门闭合；同一 Flare 当前只剩 `particle/halo_3`、`particle/fog/fog3`、`particle/light/flare_1` 三张 built-in 纹理阻断 layer 260。下一步实现项目自建确定性低能量遮罩，以 Metal 像素/预乘门、真实 Flare 隔离门、固定 13 门和可见截图共同验收；Flare 当前仍为 `8/15`，不能提前写成可见恢复；
2. **`2998757800` 构图边界**：`fog1` 低能量及全透明隔离门都未改变右下亮边，当前证据更支持底图或 cover 裁切边界，不提交 fog 调暗或样本 ID 比例特判；后续必须用 layer/camera 合同或合法 Windows WE 输出继续裁决。

`f4173ea`/`7d53c10` 已关闭 strict depth-one eventspawn/natural-eventdeath 最小闭环，`928acca` 已关闭严格 Event Follow owner，`2f897bc` 已关闭持续/混合/duration child emitter 与 root aggregate budget；`2131872317` 延迟签名 App 门可见两簇烟花。static/collision/delete/nested child、event transform/CP/value inheritance、跨层/递归总预算与 Windows golden 仍未完成。`3768903841` 的 5-image/140-frame sprite 仍只有静态首帧 fallback，完整跨-image animation 继续 fail closed，不得将本批写成 sprite animation 兼容。

视觉判断先以样本自带 preview 约束构图、色调和明显效果，WaifuX SceneBake 只作辅助动态参考，最终仍需合法 Windows WE 输出。

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

- PKGV/TEX/scene JSON/MDL mesh/BC block fixture；
- EffectDefinition raw IR、实例 material ordinal、command ordinal、graph identity 与 canonical SHA；
- material 低到高 precedence、sparse slot、combo/constant 冲突、graph topology/state/binding 与 fail-closed legacy 路由；
- frame texture identity、ready/pending/unavailable、generation、A/B variant 隔离和 property -> authored fallback；
- property/timeline/particle 数据模型；
- transform、插值、资源路径和评分规则。

### GPU/集成层

- 小尺寸离屏纹理输入，验证输出像素、alpha 和 mask；
- 5-6 个关键样本使用封面自身比例的固定画布生成并排图，检查主构图、主体位置、色调/亮度和明显效果范围；当前已落地为非阻断门，只做同样本前后比较，不把封面当动态时序或像素 golden。WaifuX SceneBake 只作辅助动态参考，冲突时以样本 preview 约束当前方向；
- authored graph exact-ID GPU completion、RT extent 不被预算静默缩放，以及 rejected graph 不执行旧 effect heuristic；
- Debug runner 启动真实 Scene，确认解释文件和纹理加载；
- 截取 ready 与 after-interaction 两帧，验证非黑、运动和窗口归属；
- stop 后确认 surface/timer/video source 清零。

### 样本矩阵层

- 目标样本：验证本次能力；
- 相关样本：覆盖相同 parser/effect/texture 路径；
- 固定矩阵：公共 runtime、resource、effect 或 lifecycle 改动后运行；
- 长批次失败不能用单样本重试替代，只能作为独立诊断证据。

### 视觉验收阶梯

"接近官方播放显示效果"按四级度量推进；每级只在自己的证据边界内下结论，不替代上级，数值只做同一样本跨提交比较、不跨样本排名。

| 级别 | 度量 | 现状与工具 | 边界 |
|---|---|---|---|
| V1 构图正确 | preview 比例中心裁切并排图，人工确认主体位置、色调、明显效果范围 | 已落地（`3194ac5`，固定门自动生成） | preview 是单帧宣传图，不含动态/交互 |
| V2 静态区域指标 | 同样本跨提交的空间色彩/亮度相似度趋势 | 已落地（非阻断分项指标） | 不设绝对阈值；构图差异大的作者 preview 会产生低分假信号 |
| V3 动态时序对照 | WaifuX SceneBake MP4 同时刻帧序列的方向性 SSIM（`3028090166` 已试点 约0.79） | 部分落地；下一步扩展为固定子集多时刻帧对照并进入非阻断报告 | SceneBake 是第三方烘焙，非官方输出；与 preview 冲突时以 preview 约束方向 |
| V4 官方 golden | 合法 Windows WE 同配置、同属性默认值录屏差异门 | 未建立 | 是宣称"接近官方效果"或任何 parity 声明的唯一依据 |

推进规则：每个能力批次至少提供 V1 证据；涉及动态效果（水波、粒子、动画）的批次补 V3 同时刻对照；V4 在发布门阶段（S5）建立固定采集流程后启用。任何级别的数值改善都不能越级解释成上级结论。

## 8. 历史批次索引

已完成批次按提交排序；逐项运行报告、矩阵 SHA 与签名身份见 [运行证据索引](semantics/runtime-evidence-index.md)，实现细节以对应提交与 semantics 覆盖表为准。历史小节原文可在 git 历史（本文件 `8bac86e` 之前版本）中查阅。

| 批次 | 关键提交 | 能力与边界 |
| --- | --- | --- |
| S0 隔离基线 | `2026-07-22 首轮` | Debug runner、隔离 root/HOME、签名验证、非黑双帧、surface 释放门；SteamCMD 代表样本固化 |
| S1.1 solid layer | `c8c463b`、`95e0d58` | typed solid + 1×1 白纹理 + tint；纯 solid color live |
| S1.2 utility/named target/静态 blend | `1517f4a`、`d881bb1`、`f1493b2` 等 | 受限 current-frame prefix capture、`_rt_imageLayerComposite` named target、单 hidden provider 静态 normal blend |
| S1 高命中视觉子集 | `f223bd1`、`c2fd29b`、`ddd87e1`、`064c2e7` | coarse blur 尺度修正、单 UV Foliage Sway、`particle/drop`、2D Sprite Trail |
| S2.1-2.2 效果 IR 与 graph planner | `6eadcf8`(v15)、`c7a0745`(v16) | EffectDefinition 保真 IR；authored graph 结构编译 + canonical SHA；condition/function blocker fail closed |
| S2.3 precise/standard Blur backend | `4f13daf` 前系列 | 两类 strict Blur profile；KERNEL/COMPOSITE/MASK 变体 fail closed，不回退 legacy |
| S2.4a-d provider/registry/target 基础 | `c86491e`、`38e238d`、`73f415b` | typed registry 双代、effect-instance target plan/table、预算事务 |
| S2.4f-h ShaderContract 与 Local Contrast | `8474ace`(v19)、`228cdde`、`136d35c` | ShaderContract IR v1（L1 保留）；`rgba8888` target；exact stock Local Contrast strict profile + strength live |
| S2.4i-k chain scheduler/Shadow/Opacity | `b541867`、`809b75e`、`b8842d8` | ordered strict effect-chain scheduler；exact Workshop Shadow 首条真实 chain；exact stock Opacity + live alpha |
| S2.4l direct dynamic text | `1762743`(v22) | direct content/point-size/color 异步重栅格化 + per-layer generation |
| S2.4m-p command/history/interleave/compose | `f1c6a10`、`dcedc2e`、`ebf44a9`、`4f13daf` | 同帧 copy/swap、受限 history seed/clear、Precise Blur interleave 白名单、exact legacy compose 归一 |
| S2.4q-r Shake/WaterWaves/WaterFlow/Foliage/Ripple/X-Ray | `e505a9e`、`31ae557`、`94aebc5`、`3baf1fc` | 六类 exact stock 动态形变 strict profile 进入 ordered chain；pointer-driven X-Ray 与组合区域捕获 |
| S4.1-4.2 程序化粒子纹理 | 系列、`c06b0fb` | 11 个精确 built-in key 确定性预乘纹理；Color Random 纠偏；45 样本快照扩展 |
| S4.3 particle child 触发 | `f4173ea`、`7d53c10`、`4e64232` | strict depth-one eventspawn/natural-eventdeath child、child trail、1,024/system 预算；`3768903841` 真实 eventspawn 缓存门、`2131872317` 第 233 帧离屏 burst 与 4.5 秒签名 App 可见烟花；其余 child 类型保持 fail closed |
| S4.4 高频 built-in 粒子纹理 | `c654571` | `rosepetals` 64×64 单花瓣与 `beam_1` 128×128 软光束确定性预乘遮罩；完整门新增 4 层至 `83/131`，固定门 `3724289844` 新增 5 层至 `18/27`；默认隐藏层保持不创建，程序图形不等于官方资产 |
| S4.5 Fire built-in 粒子纹理 | `f02f41d` | `particle/fire/fire1` 128×128 低能量火焰确定性预乘遮罩；`3769364482:446/453` 与 `3757555836:98` 进入受限执行，完整门升至 `86/131`；turbulence、torch ember child 与官方纹理像素等价仍缺 |
| S4.6 Light Shafts 0 built-in 粒子纹理 | `a5a951f` | `particle/light/light_shafts_0` 128×128 低能量双光束确定性预乘遮罩；五个真实层进入受限执行，21 样本 census 的 `builtInTextureUnavailable` 从 11 降至 9，完整门升至 `91/131`；程序遮罩不等于官方资产，Flare 的 turbulent/eventfollow/非瞬时 child 合同在该阶段仍缺 |
| S4.7 非音频 Turbulent Velocity | `4a17ee6` | 自建确定性 3D gradient noise 消费 forward/right/up、phase、scale、time 与 speed range；audio fail closed；不是 WE 数值或像素等价 |
| S4.8 Event Follow child | `928acca` | identity/no-CP/depth-one/瞬时 Sprite child 以 parent particle ID 建 owner，逐帧更新 origin 并在 parent death 回收；合成 spawn/follow/death 门通过，持续 emitter 与真实 Flare 仍未执行 |
| S2/S4 合成正确性批次 | `8bac86e`、`dd85dcf`、`18d0056` | puppet bind-pose mesh 重组（v23）；BC1/2/3 单 image 16M 像素预算内 CPU 解码/premultiply，超预算或多 image 载荷 GPU premultiply；跨 image sprite 仅裁 authored 首帧作静态 fallback，完整动画未实现；REFRACT 粒子 fail closed；45/13 两门按新口径刷新 |
| Puppet 静态 attachment | `49ee89a` | 受限 MDLS0004 hierarchy + MDAT0001 named bind frame；`parent * attachment * child local` 静态定位；interpretation v24；MDLA/deformation/动画 follow 仍 fail closed；13/45 两门通过 |
| Puppet MDLA 严格单 clip 播放 | `ca6d841`、`56f92a2`、`2be2b44`、`f1ee79b` | 三来源 MDLA0006/full TRS/MDLS weights；source-FPS 离散 loop + CPU LBS；interpretation v25；mixing/动态 visibility/attachment follow fail closed；13/45 两门通过 |
