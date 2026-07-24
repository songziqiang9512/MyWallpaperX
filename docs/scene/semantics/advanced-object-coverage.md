# Scene 对象、Puppet、3D 与产品能力覆盖表

> 状态：现役专项表
>
> 最近核对：2026-07-25
>
> 实现基线：`8bac86e`
>
> 当前两层运行门、签名 App 身份及聚合缺口统一见 [运行证据索引](runtime-evidence-index.md)。exact stock Opacity direct alpha 已闭环；本表高级对象仍按各自前置单独升级。

本表覆盖基础对象之外容易被笼统描述掩盖的能力：utility composition、sound、Puppet Warp、3D model、lighting/HDR、性能策略、RGB 和离线烘焙。等级口径见 [`coverage-ledger.md`](coverage-ledger.md)，逐页官方归属见 [`official-page-map.md`](official-page-map.md)，16 组导航见 [`official-page-crosswalk.md`](official-page-crosswalk.md)。

## 1. 文件、资源和基础对象

| 能力 | 等级 | 当前证据 | 当前边界 / 下一门 |
|---|---|---|---|
| loose Scene/project ingest | `L3` | [`SceneProject.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Format/SceneProject.swift)、[E-INGEST](runtime-evidence-index.md#e-ingest) | 私有 schema 版本和异常字段继续 fail-closed |
| PKGV index/extraction | `L3` | [`ScenePkgReader.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Format/ScenePkgReader.swift)、[E-INGEST](runtime-evidence-index.md#e-ingest) | case/symlink/duplicate/压缩边界和 VFS golden |
| TEX common decode | `L3` | [`SceneTextureLoader.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneTextureLoader.swift)、[E-INGEST](runtime-evidence-index.md#e-ingest) | 全容器/format/mip/color-space 边界 |
| resource identity and missing diagnostics | `L3` | [`SceneResourceReferenceIndex.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneResourceReferenceIndex.swift)、[E-INGEST](runtime-evidence-index.md#e-ingest) | 统一 VFS、alias/case 规则与依赖版本 |
| image layer | `L3` | Metal compositor、180/181 固定矩阵结构计数、[E-BASE](runtime-evidence-index.md#e-base) | 通用 material/effect/provider 和 WE pixel golden |
| solid layer | `L3` | typed solid、1x1 white texture、author color；纯 solid color 已由 B0 snapshot live 消费；[E-BASE](runtime-evidence-index.md#e-base)、[E-LIVE-PROPERTY](runtime-evidence-index.md#e-live-property) | non-solid/mixed color、HDR/light |
| text layer | `L3` | CoreText 静态纹理、direct property 动态重栅格、79/108 结构门、[E-TEXT](runtime-evidence-index.md#e-text) | time/SceneScript/system/media 值与 Windows typography |
| particle layer | `L3` | 固定门 15/27、完整门 52/68 可见层进入受限 runtime；[E-PARTICLE](runtime-evidence-index.md#e-particle) | 逐组件状态见 [粒子表](particle-component-coverage.md) |
| container/parent hierarchy | `L3` | source order、parent transform/visibility/parallax propagation、[E-BASE](runtime-evidence-index.md#e-base) | composition、动态 reparent、复杂 component |
| sound layer | `L0` | 无 sound content IR/player | asset/stream、volume、loop、pause/stop、property/script target |
| Puppet layer | `L3` bind pose（`executed-degraded`） | MDLV mesh block 解析 + 加载时图集重组为 bind-pose 纹理（`8bac86e`）；[E-PUPPET-BC](runtime-evidence-index.md#e-puppet-bc) | warp 动画、骨骼播放、attachment 定位、独立 content kind |
| 3D model layer | `L0` | model/material link 不等于 3D runtime | loader/scene graph/camera/PBR/animation |
| light object | `L0` | 无 light IR | 类型、坐标、排序、shadow 和 lifecycle |

“某资源被 catalog 发现”最多是 `L1`；只有对象类型进入 IR 和 renderer 路由才是 `L2`，有受控执行和门才是 `L3`。

## 2. Object 与 Utility composition

| 能力 | 等级 | 当前能力 | 下一门 |
|---|---|---|---|
| source order | `L3` | render order 固定为 scene object 顺序；[E-BASE](runtime-evidence-index.md#e-base) | dynamic topology 与 official golden |
| parent transform | `L3` | origin/size/scale/angles 合成；[E-BASE](runtime-evidence-index.md#e-base) | 3D、shear、动态 target 和数值 golden |
| effective visibility | `L3` | parent/child/effect/particle gating；[E-BASE](runtime-evidence-index.md#e-base) | live topology invalidation |
| layer alpha/color/blend mode | `L3` | 静态 descriptor/compositor 子集；layer alpha 与纯 solid color 已由 B0 per-surface snapshot live 消费；[E-BASE](runtime-evidence-index.md#e-base)、[E-LIVE-PROPERTY](runtime-evidence-index.md#e-live-property) | visibility/topology、non-solid/mixed color、完整 blend/premultiply/color space |
| dependency layer IDs | `L2` | 可保留并进入 dependency plan | 通用 nested/effectful/child provider |
| typed composition/project/fullscreen layer | `L3` | 有限 current-frame prefix capture 与 geometry；[E-UTILITY](runtime-evidence-index.md#e-utility) | 完整子场景边界、嵌套和 target ordering |
| current-frame capture | `L3` | bounded provider、clipping、GPU completion；[E-UTILITY](runtime-evidence-index.md#e-utility) | 通用 capture mask/format/extent |
| named primary `_a` target | `L3` | bounded producer/consumer 和预算池；[E-UTILITY](runtime-evidence-index.md#e-utility) | 通用 authored identity、copy/swap/compose |
| named secondary `_b` identity | `L2` | registry 区分完整 variant | producer/consumer 数据流 |
| RGB composition semantics | `L0` | current-frame capture 不能冒充 RGB camera | 独立 subtree capture、device output 和 author-off |
| nested/effectful provider | `L0` | 当前拒绝或缺失 | 同一 graph/provider contract 与循环检测 |

Utility composition 已是极窄的 `L3` 子集，不再写成完全缺失；但这不代表任意 composition、RGB Composition 或 `_b` history 已闭合。

## 3. Puppet Warp 官方页面覆盖（13）

本节逐页记录官方公开的作者行为和播放器必须消费的导出结果。Geometry 自动生成、权重绘制、Character Sheet 制作等属于编辑器工作流；MyWallpaperX 不需要复刻这些工具，但必须在未来 Puppet IR 中保留其导出的 mesh、bone、weight、depth order、channel、constraint 和 animation 数据。官方页面没有公开 mesh/weight 序列化、deformation、IK、constraint、clipping 或 animation mixing 的数值算法，均保持 `algorithm unknown`，不能凭视觉近似写成已验证合同。

| 官方页面 | 分类 | 官方合同与分类边界 | 当前等级 / 最小升级门 |
|---|---|---|---|
| <a id="op-puppet-introduction"></a>[Introduction](https://docs.wallpaperengine.io/en/scene/puppet-warp/introduction.html) | `runtime-required` + `editor-export` | 播放器消费透明 source、deformable geometry、bone/root hierarchy、weights、一个或多个 Timeline animation；image effect 只能作用在作者配置的 mesh/padding 范围。自动切图、建 mesh、画权重是 editor-only。 | `L0`：只有资源路径 discovery；需独立 Puppet content IR、mesh/bone/weight round-trip、GPU deformation、effect bounds 和 Loop/Mirror/Single 门。 |
| <a id="op-puppet-charactersheet"></a>[Character Sheet](https://docs.wallpaperengine.io/en/scene/puppet-warp/charactersheet.html) | `editor-export` | 多个身体/衣物部件位于同一 texture，bone parent order、depth order、weights 与 reference pose 把分离部件重组；播放器消费导出结果，不负责切图或 overlay 辅助。 | `L0`：无 reference-pose/part identity；需分离部件、重叠顺序、reference pose 和 seam/weight fixture。 |
| <a id="op-puppet-extending"></a>[Extending](https://docs.wallpaperengine.io/en/scene/puppet-warp/extending.html) | `editor-export` + `ingest-boundary` | 扩展 sheet 时原部件像素位置保持不变，新区域加在右侧/底部或既有空隙；locked geometry 不自动补 mesh，1.7 及更早项目可能不兼容。运行时只消费更新后的 asset/version，不自行扩图。 | `L0`：无 Puppet schema/version gate；需 old/new asset identity、locked geometry、missing bone/weight 和版本失败关闭 fixture。 |
| <a id="op-puppet-attachments"></a>[Attachments](https://docs.wallpaperengine.io/en/scene/puppet-warp/attachments.html) | `runtime-required` | named attachment 属于具体 bone/local point；作为 child 的任意 layer 跟随全部 Puppet animation。effect/asset 的 point property 也可绑定 attachment，绑定只在运行时生效。 | `L0`：无 attachment handle；需 bone-local -> world matrix、child/effect point binding、动画跟随、missing owner 和 teardown 门。 |
| <a id="op-puppet-clipping-masks"></a>[Clipping Masks](https://docs.wallpaperengine.io/en/scene/puppet-warp/clippingmasks.html) | `runtime-required` | 被 clip 的 limb 默认不可见，只在与指定 limb/mask 重叠时出现；支持 nested mask，反向互相引用等 cycle 非法，depth order 影响 shadow/shading。官方未公开 overlap raster/edge 算法。 | `L0`：无 clip graph；需 acyclic nested graph、deformed geometry overlap、depth/alpha/order、cycle 失败和 pixel fixture。 |
| <a id="op-puppet-texture-channels"></a>[Texture Channels](https://docs.wallpaperengine.io/en/scene/puppet-warp/texturechannels.html) | `runtime-required` | channel 与 base texture 分辨率完全相同，可按作者顺序叠加多个 channel；Timeline 以 `0...1` opacity 混合，`Alpha writing` 决定是否写 silhouette alpha。它不是 GIF/frame sequence，官方 data limit 未公开。 | `L0`：无 Puppet channel IR；需 equal-size validation、ordered opacity mix、alpha-write on/off、limit failure 和 color/alpha pixel 门。 |
| <a id="op-puppet-bone-constraints"></a>[Bone Constraints](https://docs.wallpaperengine.io/en/scene/puppet-warp/boneconstraints.html) | `runtime-required` + `research-boundary` | Spring、Rigid 与 kinematic-chain Rope 可模拟 rotation/translation、stiffness/friction/inertia、gravity、mass、tip、limits、torque、wind；animation motion 与 physics 合并。官方明确结果会随 max FPS 变化，但未公开 integrator/iteration order。 | `L0`：无 solver；需 typed constraints、fixed/variable FPS 对照、animation+physics ordering、pause/discontinuity、deterministic reset 和 budget 门；不得发明 WE 数值算法。 |
| <a id="op-puppet-inverse-kinematics"></a>[Inverse Kinematics](https://docs.wallpaperengine.io/en/scene/puppet-warp/inversekinematics.html) | `runtime-required` + `research-boundary` | IK 通常配置在 limb 末端，沿 parent chain 求解；target controller 控制整条 limb，orientation controller 决定弯曲方向，forward alignment/limit 约束结果。精确 solver、迭代和 overstretch 算法未公开。 | `L0`：无 IK IR/solver；需 chain/target/orientation identity、limit/overstretch、Loop wrap、determinism 与合法 Windows golden。 |
| <a id="op-puppet-interactive"></a>[Interactive](https://docs.wallpaperengine.io/en/scene/puppet-warp/interactive.html) | `runtime-required` + `SceneScript` | SceneScript 可按 name/index 读写 bone transform；官方明确每帧先执行所有 layer animation，再执行 scripts，脚本可覆盖 animation 结果；Spring 可在 release 后把 bone 拉回。 | `L0`：无 Puppet handles 或 SceneScript runtime；需 animation -> script 顺序、local/world transform、drag/release、physics merge、invalid handle 和每屏 teardown 门。 |
| <a id="op-puppet-perspective"></a>[Perspective](https://docs.wallpaperengine.io/en/scene/puppet-warp/perspective.html) | `runtime-required` | 2D Puppet mesh 可带 painted depth/extrusion scale；X/Y bone angles 或 layer Perspective 显示 extrusion。`Normal` culling 隐藏背面，`No cull` 镜像 texture 到背面；这不是 3D Model runtime。 | `L0`：无 depth/extruded mesh；需 depth attribute、X/Y rotation、cull/no-cull、clip/effect bounds 与 perspective pixel 门。 |
| <a id="op-puppet-blend-shapes"></a>[Blend Shapes](https://docs.wallpaperengine.io/en/scene/puppet-warp/blendshapes.html) | `runtime-required` | blend shape 是锁定 topology 上的 alternate vertex arrangement；Expression 是多个 shape weight 的组合，Timeline 动画 expression。官方未公开 shape 混合、bone deformation 与 clipping 的内部顺序。 | `L0`：无 morph target；需 topology identity、shape/expression weights、mix-order fixture、bounds 和 Timeline consumer。 |
| <a id="op-puppet-blend-rules"></a>[Blend Rules](https://docs.wallpaperengine.io/en/scene/puppet-warp/blendrules.html) | `runtime-required` + `research-boundary` | bone 可通过 `0...1` 动画权重在原 parent 与 alternate bone 间切换；多个 blend rule 可把对象置于多个 bones 之间。确切 transform interpolation/conflict order 未公开。 | `L0`：无 rule evaluator；需 stable bone identity、0/1/intermediate/multiple rule、parent cycle、animation order 和 Windows transform golden。 |
| <a id="op-puppet-animation-mixing"></a>[Animation Mixing](https://docs.wallpaperengine.io/en/scene/puppet-warp/animationmixing.html) | `runtime-required` + `research-boundary` | 同一 Puppet 可同时启用多个 animation，并分别设置 duration/rate；官方运行时把它们合并。相同 bone/property 的冲突、blend weight 与 merge algorithm 未公开。 | `L0`：无 clip mixer；需 independent rates、disjoint/same-target conflicts、pause/seek/loop、script override 与合法 golden。 |

Puppet runtime 必须把 authored pose、animations/mixing/rules、constraints/IK/physics、SceneScript bone override、deformation/channels/clipping 和 layer effects 建成可区分的阶段。只有 “animations before scripts” 是官方公开顺序；physics、IK、blend、deformation、clipping 与 effect 的相对次序在获得合法样本或官方证据前均保持 `order unknown`，不得先用箭头固化。

## 4. 3D Models 官方页面覆盖（8）

现有 `modelMaterialLinks` 只保存资源关系，不能把 3D model 记为 routed 或 rendered。官方 stock model shader 与任意 Workshop custom shader 是两类能力：本节只记录官方页面公开的 Fur、Vegetation、Chroma material 行为，不把它们写成 custom shader，也不推测其私有 shader source、参数序列化或数值算法。

| 官方页面 | 分类 | 官方合同与分类边界 | 当前等级 / 最小升级门 |
|---|---|---|---|
| <a id="op-model-introduction"></a>[Introduction](https://docs.wallpaperengine.io/en/scene/models/introduction.html) | `runtime-required` + `editor-import` | FBX 支持 model/animation/texture，OBJ 只适合基础静态模型；2D/3D Scene 都能放 model，但 camera/perspective/editor mode 不同。导入约定为 `-Z` forward、`+Y` up，scale 会尝试 normalize；material 可有 albedo、normal（X/Y flip）、metallic、roughness、reflection、emissive（红通道）、tint mask、rim/toon。 | `L0`：asset link 不是 model IR；需 axis/handedness、mesh/index/node、material channel/color space、2D/3D scene mode 和 malformed asset fixture。 |
| <a id="op-model-camera"></a>[Camera](https://docs.wallpaperengine.io/en/scene/models/camera.html) | `runtime-required` | asset list 中最底部的 visible camera 生效；可用 visibility/property/script 切 camera。path 可 random/sequential；Single 完成后进入下一 path，Loop/Mirror 不结束。camera path 使用 `Center/Eye/Up` 与 FOV，而非普通 origin/angles/scale。 | `L0`：2D camera 不等价；需 visible-camera selection、Center/Eye/Up interpolation、path queue/modes、resize 和 invalid vector 门。 |
| <a id="op-model-animation"></a>[Animation](https://docs.wallpaperengine.io/en/scene/models/animation.html) | `runtime-required` + `editor-import` | imported animation 可按 start/end frame 切 clips并设 frame offset；额外 FBX 必须与 base 共用相同 bone hierarchy。Motion root 可把 clip 位移应用到 model，长时间循环可能 drift。 | `L0`：无 skeleton/clip evaluator；需 clip/hierarchy validation、offset/loop/rate、root motion accumulation/reset、mix 与 SceneScript bridge。 |
| <a id="op-model-attachment"></a>[Attachment](https://docs.wallpaperengine.io/en/scene/models/attachment.html) | `runtime-required` | named attachment 绑定 model bone，并带 local origin；作为 model child 的任意 asset 跟随 model animation/movement。 | `L0`：无 model attachment；需 bone-local/world matrix、child order、missing bone、animation follow 和 teardown 门。 |
| <a id="op-model-fog"></a>[Fog](https://docs.wallpaperengine.io/en/scene/models/fog.html) | `runtime-required` | distance fog 相对 camera，用 start/end distance 与 start/end density；height fog 相对 scene global height 0，用同类参数；二者可同时启用，material 可 opt out。具体插值/颜色空间未公开。 | `L0`：无 fog IR/post；需 distance/height simultaneous、per-material disable、camera/depth/order 和 Windows pixel golden。 |
| <a id="op-model-lighting"></a>[Lighting](https://docs.wallpaperengine.io/en/scene/models/lighting.html) | `runtime-required` | model 与 light 两侧分别控制 shadow；官方页面列出 point/spot/directional shadow。Volumetric 只对 point/spot，Bloom/Ultra HDR 可增强但不是启用前提；官方明确 volumetric 昂贵。 | `L0`：无 light/depth/volume pass；需 per-model/per-light gates、shadow map/bias、point/spot volume、author-off 和 performance budget。 |
| <a id="op-model-shader"></a>[Stock Model Shaders](https://docs.wallpaperengine.io/en/scene/models/shader.html) | `runtime-required` + `stock-only` + `research-boundary` | **Fur**：albedo alpha mask、alpha-to-coverage、quality/detail/distance/occlusion。**Vegetation**：叶/干 material 分离、alpha-to-coverage、可选 no-cull/double-sided light、UV direction/mapping、wind/phase/speed/strength/tree size debug。**Chroma**：metallic/roughness、specular tint、front/back tint、pigmentation/exponent，可用 albedo alpha 排除 tint。页面未公开三个 stock shader 的算法/source/schema。 | `L0`：不得映射成 arbitrary custom shader；需三个独立 typed stock profile、完整 parameter/state/texture contract、unknown profile fail-closed 和合法 Windows pixel golden。 |
| <a id="op-model-simulation"></a>[Simulation](https://docs.wallpaperengine.io/en/scene/models/simulation.html) | `runtime-required` + `research-boundary` | model bone 可用 presets 或 advanced constraints；示例 Bouncy Position 让 bone 跟随 animation motion 后回到 initial position，官方确认 simulation 与 animation 混合。solver、step、sleep 和混合顺序细节未公开。 | `L0`：无 3D solver；需 typed constraints、animation interaction、fixed/variable step、pause/reset、collision/sleep 和 deterministic fixture。 |

## 5. Lighting 官方页面覆盖（2）与 HDR 边界

| 官方页面 | 分类 | 官方合同与分类边界 | 当前等级 / 最小升级门 |
|---|---|---|---|
| <a id="op-light-introduction"></a>[Introduction](https://docs.wallpaperengine.io/en/scene/lighting/introduction.html) | `runtime-required` | 2D image material 只有作者启用 `Lighting` 或 `Reflection` 才响应；normal map 提供表面方向，metallic、roughness、reflection map/slider 控制反射。Scene ambient/background 参与结果，官方限制每 scene 最多四个 light。normal-map generator 与 mask painting 是 editor-only。 | `L0`：无 2D lit material/light IR；需 author enable/off、四灯上限、normal/metal/rough/reflection channel、ambient/background、color space 和 pixel fixture。 |
| <a id="op-light-lights"></a>[Lights](https://docs.wallpaperengine.io/en/scene/lighting/lights.html) | `runtime-required` | Point 用 radius/intensity；Spot 用 height/direction/inner/outer cone；Tube 用可动画 start/end；Directional 无位置、只按方向覆盖全场。Spot 可投影 image/video/带完整 effects 的 layer；投影 source 在 2D Scene 可隐藏。Origin/intensity 可由 Timeline/SceneScript/audio 驱动，light Z/height 有意义，cursor script 只替换 X/Y 应保留 Z。 | `L0`：无 light/provider consumer；需四类 typed light、surface-local coordinates、projected provider/effect graph、live target/audio/cursor、hidden-source 与 author-off 门。 |

2D lighting、3D lighting、official Scene Bloom/HDR、Workshop layer Bloom 与 exact Workshop image-effect Shadow 是彼此独立的执行链。当前 Workshop layer Bloom approximation 为 `L3`（[E-EFFECT-INLINE](runtime-evidence-index.md#e-effect-inline)），`809b75e` 另执行一个 exact Workshop single-pass Shadow profile；后者不是 light/object shadow map，也没有建立 lighting 或 generic shader。official Scene Bloom target identity 为 `L1`，其 HDR target、tone mapping、Ultra HDR、per-layer HDR brightness、lighting shadow/reflection/volumetric runtime 均为 `L0`。不得用现有 layer Bloom、Workshop Shadow 或 2D compositor 冒充上述官方系统。

## 6. Shader 与高级 Effect 边界

| 能力 | 等级 | 当前边界 | 权威细表 |
|---|---|---|---|
| effect/material/pass IR | `L2` | 字段可保存并建图 | [Graph/Shader 覆盖表](render-graph-shader-coverage.md) |
| strict known graph executors | `L3` | precise/default Blur、stock Local Contrast、exact Workshop Shadow 及全支持 ordered strict chain；首条真实链为 `3724289844:20` 的 `Blur Precise -> Shadow`；[E-EFFECT-BLUR](runtime-evidence-index.md#e-effect-blur)、[E-EFFECT-LOCAL-CONTRAST](runtime-evidence-index.md#e-effect-local-contrast)、[E-EFFECT-CHAIN](runtime-evidence-index.md#e-effect-chain) | [Effect 执行表](effect-execution-coverage.md) |
| arbitrary authored shader | `L0` | 自有 Metal 近似不等于作者 shader | [Graph/Shader 覆盖表](render-graph-shader-coverage.md) |
| history/copy/swap generic runtime | `L0` | IR 保留不等于跨帧执行 | [Graph/Shader 覆盖表](render-graph-shader-coverage.md) |

Puppet、3D 和 lighting 必须复用同一 target/provider/render-graph 基础，但不得因此提前把 2D bounded executor 宣称为高级对象支持。

## 7. Performance 官方页面覆盖（3）与生命周期

官方 Performance 页面同时包含作者建议、发布警告和播放器必须正确处理的 texture memory 事实。推荐值不是硬拒绝阈值；Wallpaper Engine 接受任意 project resolution，MyWallpaperX 也不能因“不在常见列表”拒绝合法 Scene。

| 官方页面 | 分类 | 官方合同与分类边界 | 当前等级 / 最小升级门 |
|---|---|---|---|
| <a id="op-performance-optimization"></a>[Optimization](https://docs.wallpaperengine.io/en/scene/performance/optimization.html) | `editor/publish-policy` | 发布阶段会按实际 asset path 提示高 VRAM layer；作者可把 `RGBA8888` 改为 `DXT5` 或 `DXT1` 降低占用。播放器只需正确解码/计量，不负责静默重编码用户 asset。 | `L1` policy：常见 BC1/BC3 已可解码，但无逐 layer VRAM attribution、publish warning 或 format recommendation；需 format-aware bytes 与 source-path report。 |
| <a id="op-performance-resolution"></a>[Resolution](https://docs.wallpaperengine.io/en/scene/performance/resolution.html) | `editor/publish-policy` + `runtime-input` | 官方建议 project/background 匹配真实 display resolution/aspect；任意分辨率仍可接受，只会归为 `Other Resolution`。方形等错误 aspect 会被 cover crop、增加 GPU/file cost；common/multi-monitor/portrait 列表是发布分类，不是 runtime whitelist。 | `L2`：authored canvas/cover 可路由；需 multi-monitor/portrait/odd aspect crop golden、physical screen mapping 和“不在列表仍加载”负向门。 |
| <a id="op-performance-texture"></a>[Texture](https://docs.wallpaperengine.io/en/scene/performance/texture.html) | `runtime-required` + `product-policy` | 官方建议约 `300 MB` VRAM 或更低，低于 `500 MB` 仍可接受但应尽量不超过；layer texture 应裁到必要尺寸，padding 只为越界 effect 保留。`DXT1/DXT5` 约为 RGBA8888 的四分之一；压缩 texture 需要 power-of-two physical extent，运行时会透明补 invisible pixels，因此必须区分 logical/mapped size 与 physical allocation。 | `L1` policy：有局部 decode/RT budget，无全局 VRAM owner；需 per-device physical bytes、POT padding/mapped-size metadata、memory pressure、quality downgrade、300/500 MB warning 和 leak/recovery 门。 |

| 产品能力 | 等级 | 当前事实 | 下一门 |
|---|---|---|---|
| stop 后 surface teardown | `L3` | 固定矩阵要求 `surface=0`；[E-LIFECYCLE](runtime-evidence-index.md#e-lifecycle) | GPU texture/heap/VM/provider 全资源计数 |
| wallpaper switch lifecycle | `L3` | Host 重建与资源释放有运行门；[E-LIFECYCLE](runtime-evidence-index.md#e-lifecycle) | 反复切换 soak、峰值内存门 |
| screen resize/reconfigure | `L2` | surface 可重建且共享 clock 不重置 | display hot-plug/Space/scale transition |
| pause/sleep/lock | `L0` | Scene clock 与 simulation 未接系统暂停 | 冻结/恢复、无补帧、provider suspend |
| target FPS / refresh-rate driver | `L0` | 固定 60 Hz Timer | per-display refresh、frame pacing、low power |
| quality tiers | `L0` | 无统一 policy | effect/particle/RT 降级必须可诊断 |
| texture resolution policy | `L1` | 有有限 decode/RT budget，但无产品级统一策略 | logical/mapped/physical size、POT padding、mip、memory pressure |
| shared decode/GPU resource reuse | `L1` | 多屏仍重复 renderer/decode/upload | immutable asset cache + per-device ownership |
| CPU/GPU/frame-time budget | `L0` | 无长期阈值 | representative matrix + 30 min interaction + 2 h soak |
| memory/VRAM/leak budget | `L0` | 只有部分释放结果 | peak/steady/recovery metrics |
| diagnostics/fail-closed | `L3` | unsupported/resource/graph/runtime 报告存在；[E-LIFECYCLE](runtime-evidence-index.md#e-lifecycle) | 所有新增系统沿用统一 code/count/evidence |

官方性能页面是运行合同和产品策略，不只是编辑建议。达到日常可用前至少需要 pause、frame pacing、资源复用和长期预算门。

## 8. RGB 官方页面覆盖（1）与平台策略

<a id="op-rgb"></a>

### [RGB Introduction](https://docs.wallpaperengine.io/en/scene/rgb/introduction.html)

分类为 `platform-decision`，当前整体 `L0`。官方默认把 wallpaper 颜色镜像到兼容设备；作者也可在 image、solid 或 composition layer 上启用 `Limit iCUE & Chroma to this layer`，由单层独占 RGB 输出。该 source layer **不需要在最终 wallpaper 中可见，也不要求位于最上方**，但必须处于所有 aspect/resolution 都会渲染的 viewable area。若多层启用，只有 asset list 中 **topmost enabled layer** 生效。

Composition 作为 RGB source 时像 camera 一样捕获它下方的所有 layers；其尺寸/分辨率应尽量小。这里的 output selection 与 wallpaper 可见合成是两条不同结果，普通 utility current-frame capture 不能冒充 RGB composition，更不能把 invisible RGB-only layer 从 render dependency graph 中裁掉。

| 能力 | 等级 | 当前策略 | 升级门 |
|---|---|---|---|
| default wallpaper mirror | `L0` | 无 RGB frame/output adapter | 固定 downsample/color contract、author-off、无设备和 deterministic emulator fixture |
| topmost enabled source selection | `L0` | 不识别 RGB author flag | visible/invisible、层顺序、多 enabled、viewable-area 与 aspect fixture |
| image/solid source | `L0` | 普通 layer render 不发布 RGB output | 独立 small output target、effect 后颜色、generation 和 teardown |
| composition source | `L0` | current-frame capture 不能冒充 RGB camera | 精确捕获下方 layers、source bounds/resolution、循环检测和 GPU budget |
| device discovery/output | `L0` | macOS 无 iCUE/Chroma adapter | 明确支持设备/SDK/授权、disconnect/reconnect 和 rate limit |
| no-device fallback | `L0` | 尚无产品设置 | 默认关闭；不得改变 wallpaper render、阻塞 frame 或保留资源 |

RGB 不阻塞 Scene Lite；在 macOS 没有明确设备 adapter、授权和产品策略前保持 `L0` fail-closed。

## 9. 实时与离线烘焙

| 能力 | 等级 | 当前事实 | 下一门 |
|---|---|---|---|
| Debug PNG readback | `L2` | benchmark 可抓 GPU frame | 仅测试证据，不是产品 bake |
| shared realtime/offline Scene core | `L0` | 无 offline adapter | 同一 IR/evaluator/renderer entry |
| fixed frame clock | `L0` | SceneClock 只接实时 host time | 可注入 fps/frame index/scene time |
| deterministic seed | `L2` | 粒子子系统有固定 seed 子集 | 所有 random/script/effect 共用 seed policy |
| cursor/audio/media replay | `L0` | 无 provider recording/injection | fixture timeline 与缺失输入策略 |
| sequence/video encoder | `L0` | 无产品输出 | PNG sequence 后再接编码/取消/进度 |
| realtime-offline equivalence gate | `L0` | 无同输入 pixel comparison | 固定 sample/property/time/seed 阈值 |

WaifuX 的可借鉴点是实时和 bake 共用核心，不是复制其实现。B0 live-value 的 alpha/solid color/Local Contrast strength 子集已成立；离线能力仍要等 Provider Core、fixed-time、deterministic input replay 与其余 producer/consumer 合同成立后进入产品层。

## 10. 高级系统公共前置

| 高级系统 | 必须先完成的公共层 | 原因 |
|---|---|---|
| Puppet mesh/animation | [D0-D3](capability-dependency-map.md)、[D5](capability-dependency-map.md#d5)、[D7-D8](capability-dependency-map.md#d7) | 需要稳定 asset/bone identity、clock/evaluator、texture/material 和 local/world space |
| Puppet physics/interaction | [D2-D4](capability-dependency-map.md#d2)、[D8](capability-dependency-map.md#d8) | fixed step、event queue、pointer/control target 和 deterministic reset |
| 2D lighting/HDR | [D5-D8](capability-dependency-map.md#d5) | PBR texture metadata、RT graph、material/state、world coordinates |
| 3D model/animation | [D0-D3](capability-dependency-map.md)、[D5-D8](capability-dependency-map.md#d5) | VFS/schema、stable nodes、clock、provider、graph/shader 和 handedness |
| RGB/offline | [D1-D10](capability-dependency-map.md#d1) | 必须复用同一 scene graph、evaluation、provider、renderer 和 lifecycle |

## 11. 开发顺序

1. B0 live target program 已覆盖 layer alpha、纯 solid color、direct text、strict Local Contrast/Opacity 与受限 X-Ray target；这些 consumer 不升级 SceneScript、lighting 或高级对象。Timeline/SceneScript source IR 和其他 target 继续复用同一 per-surface transaction/snapshot。
2. 下一批先闭合新增样本暴露的公共 blend/composition 与 Fire effect，再处理多余粒子和全局比例/裁切；generic compose、真实 history consumer 和高命中 effect 继续按共同依赖推进。
3. 再做 Puppet 的 mesh/bone/animation 最小闭环，然后 lighting/HDR；每项必须沿现有 author-enable 和 fail-closed 规则。
4. 3D、自定义 shader、RGB 和 offline encoder 后置，但基础时钟、target、provider 和 graph 不能封死这些输入。
5. 每个系统从 `L0` 升级时同时增加结构、执行、author-off、失败、teardown 和性能门，不能只新增 parser 字段。
