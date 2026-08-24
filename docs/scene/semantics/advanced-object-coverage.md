# Scene 对象、Puppet、3D 与产品能力覆盖表

> 状态：现役专项表
>
> 最近核对：2026-08-25
>
> 实现基线见 [运行证据索引](runtime-evidence-index.md)；本表不复制基线 commit，文内 commit 号是各能力的历史落地提交。
>
> 运行事实与签名 App 身份统一见 [运行证据索引](runtime-evidence-index.md)。本表只展开高级对象能力，不定义平行开发顺序；Puppet、lighting/HDR、3D、RGB 和离线能力统一归入[现役路线](../scene-compatibility-roadmap.md)的 V5，且不阻塞 V0 普通 authored effect 首次出画面。

本表覆盖基础对象之外容易被笼统描述掩盖的能力：utility composition、sound、Puppet Warp、3D model、lighting/HDR、性能策略、RGB 和离线烘焙。等级口径见 [`coverage-ledger.md`](coverage-ledger.md)，逐页官方归属见 [`official-page-map.md`](official-page-map.md)，16 组导航见 [`official-page-crosswalk.md`](official-page-crosswalk.md)。

## 1. 文件、资源和基础对象

| 能力 | 等级 | 当前证据 | 当前边界 / 下一门 |
|---|---|---|---|
| loose Scene/project ingest | `L3` | [`SceneProject.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Format/SceneProject.swift)、[E-INGEST](runtime-evidence-index.md#e-ingest) | 私有 schema 版本和异常字段继续 fail-closed |
| PKGV index/extraction | `L3` | [`ScenePkgReader.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Format/ScenePkgReader.swift)、[E-INGEST](runtime-evidence-index.md#e-ingest) | case/symlink/duplicate/压缩边界和 VFS golden |
| TEX common decode | `L3` | [`SceneTextureLoader.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneTextureLoader.swift)、[E-INGEST](runtime-evidence-index.md#e-ingest) | 全容器/format/mip/color-space 边界 |
| resource identity and missing diagnostics | `L3` | [`SceneResourceReferenceIndex.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneResourceReferenceIndex.swift)、[E-INGEST](runtime-evidence-index.md#e-ingest) | 统一 VFS、alias/case 规则与依赖版本 |
| image layer | `L3` | Metal compositor、180/181 固定矩阵结构计数、[E-BASE](runtime-evidence-index.md#e-base) | 通用 material/effect/provider 和 WE pixel golden |
| solid layer | `L3` | typed solid、1x1 white texture、author color；纯 solid color 已由现有 per-surface snapshot live 消费；[E-BASE](runtime-evidence-index.md#e-base)、[E-LIVE-PROPERTY](runtime-evidence-index.md#e-live-property) | non-solid/mixed color、HDR/light |
| text layer | `L3` | CoreText 静态纹理、direct property 动态重栅格、79/108 结构门、[E-TEXT](runtime-evidence-index.md#e-text) | time/SceneScript/system/media 值与 Windows typography |
| particle layer | `L3` | 固定门 18/27、完整门 83/131 可见层进入受限 runtime（REFRACT 材质 fail closed）；[E-PARTICLE](runtime-evidence-index.md#e-particle) | 逐组件状态见 [粒子表](particle-component-coverage.md) |
| container/parent hierarchy | `L3` | source order、parent transform/visibility/parallax propagation、[E-BASE](runtime-evidence-index.md#e-base) | composition、动态 reparent、复杂 component |
| sound layer | `L0` | 无 sound content IR/player | asset/stream、volume、loop、pause/stop、property/script target |
| Puppet layer | `L3 executed-degraded` | MDLV bind-pose 重组（`8bac86e`）+ 静态 MDAT attachment（`49ee89a`）+ 严格单 clip（`f1ee79b`）+ bind-referenced/disjoint-bone additive clips 与 typed visibility（`0892e74b`）；[E-PUPPET-BC](runtime-evidence-index.md#e-puppet-bc) | 插值、冲突 mixing/权重、非 1 rate/blend、动画 attachment follow、constraints/IK/physics/channels/clipping、更多版本与 Windows golden |
| 3D model layer | `L0` | model/material link 不等于 3D runtime | loader/scene graph/camera/PBR/animation |
| light object | `L0` | 无 light IR | 类型、坐标、排序、shadow 和 lifecycle |

“某资源被 catalog 发现”最多是 `L1`；只有对象类型进入 IR 和 renderer 路由才是 `L2`，有受控执行和门才是 `L3`。

## 2. Object 与 Utility composition

| 能力 | 等级 | 当前能力 | 下一门 |
|---|---|---|---|
| source order | `L3` | render order 固定为 scene object 顺序；[E-BASE](runtime-evidence-index.md#e-base) | dynamic topology 与 official golden |
| parent transform | `L3` | origin/size/scale/angles 合成；[E-BASE](runtime-evidence-index.md#e-base) | 3D、shear、动态 target 和数值 golden |
| effective visibility | `L3` | parent/child/effect/particle gating；[E-BASE](runtime-evidence-index.md#e-base) | live topology invalidation |
| layer alpha/color/blend mode | `L3` | 静态 descriptor/compositor 子集；layer alpha 与纯 solid color 已由现有 per-surface snapshot live 消费；[E-BASE](runtime-evidence-index.md#e-base)、[E-LIVE-PROPERTY](runtime-evidence-index.md#e-live-property) | visibility/topology、non-solid/mixed color、完整 blend/premultiply/color space |
| dependency layer IDs | `L3 bounded` | 可保留并进入 dependency plan；classic primary named-provider 的单 backward composition dependency由共享`.resolvedMaterial` binding与普通GraphExecutor执行，旧exact Clipping owner已删除；当前又支持由可见 image consumer 反向可达的隐藏 image provider closure，其中 effectful provider 的最终 GraphExecutor 输出复制到独立 primary named reservation 后再供下一层消费；pre-encode ordinary capture miss可沿该bounded closure逐层typed撤销并保留独立successor | secondary、forward/cycle、child、非 image provider、多个依赖、多个 provider reference、history、encode后publication失败与更深/混合 topology |
| typed composition/project/fullscreen layer | `L3` | 有限 current-frame capture/geometry；classic primary `Clipping Mask` / `Clipping Mask -> static Opacity`的bounded结构经普通MaterialProgram执行，不再按effect path/hash选择专用实现；[E-UTILITY](runtime-evidence-index.md#e-utility) | 完整子场景边界、嵌套、其他named profile和target ordering |
| current-frame capture | `L3` | bounded provider、clipping、GPU completion；composition dependency capture 与 named binding 共用完整-chain consumer 集合；[E-UTILITY](runtime-evidence-index.md#e-utility) | 通用 capture mask/format/extent 与 SceneScript/dynamic alpha |
| named primary `_a` target | `L3` | bounded producer/consumer 和预算池；`2974757317` 只捕获 `912/57382` 并绑定 `956/57098`；[E-UTILITY](runtime-evidence-index.md#e-utility) | 通用 authored identity、copy/swap/compose |
| named secondary `_b` identity | `L2` | registry 区分完整 variant | producer/consumer 数据流 |
| RGB composition semantics | `L0` | current-frame capture 不能冒充 RGB camera | 独立 subtree capture、device output 和 author-off |
| nested/effectful provider | `L3 bounded` | primary `_a`、backward、acyclic、hidden image provider closure 已闭合两级 effectful provider 链；另以 raw provider 前缀形成`91 -> 92 -> 104 -> 1104`，证明pre-encode ordinary capture miss只级联撤销真实下游、独立Program仍同帧composite并在下一帧恢复全链。provider graph final复制到独立named reservation，中间 provider 不持有 compositor | secondary、forward/cycle、child、非 image、multi-dependency/reference、history/resize/device-loss、encode后publication失败与任意深度/更深混合链 |

Utility composition 已是极窄的 `L3` 子集，不再写成完全缺失；另一个独立的 hidden-image provider closure 现只闭合 primary `_a`、backward、acyclic、effectful nested chain。`2974757317:914` 的 SceneScript alpha、`3768229922` 的 9 个隐藏 weighted profile、child/non-image/multi-dependency provider、任意 composition、RGB Composition 与 `_b` history 仍没有因此闭合。

<a id="3-puppet-warp"></a>
## 3. Puppet Warp 官方页面覆盖（13）

本节逐页记录官方公开的作者行为和播放器必须消费的导出结果。Geometry 自动生成、权重绘制、Character Sheet 制作等属于编辑器工作流；MyWallpaperX 不需要复刻这些工具，但 Puppet IR 必须逐步保留其导出的 mesh、bone、weight、depth order、channel、constraint 和 animation 数据。官方页面没有公开 mesh/weight 序列化、deformation、IK、constraint、clipping 或 animation mixing 的数值算法，均保持 `algorithm unknown`，不能凭视觉近似写成已验证合同。

### 3.0 Puppet 动画证据边界（2026-07-25 核对）

Puppet Warp 的核心是骨骼驱动网格变形。官方页面说明 bone hierarchy、weight painting、Timeline animation/mode 和 animation-before-SceneScript 顺序，但没有公开 MDLS/MDLA 二进制 schema、矩阵乘法顺序、skinning 数值算法或 mixing 冲突规则。编辑器教程以旋转关节为主要创作方式，不等于运行时格式禁止 translation/scale；三份独立真实 MDLA0006 资产的逐帧记录都包含变化的 translation 和 scale，因此 IR 必须保留完整 TRS。

当前可执行合同来自真实资产的假设-验证循环，而不是把编辑器建议改写成官方 schema：

1. MDLA0006 每个 bone track 保存 `frameCount + 1` 个完整 TRS sample；reader 只接受已核验的 `loop` 形状和有限预算。
2. 真实 bind frame 对照锁定局部矩阵为 `T * Rz * Ry * Rx * S`；`身体_puppet.mdl` 最大误差 `8.61e-6`，错误的 `R * T * S` 次序误差约 `758.8`。
3. evaluator 按 MDLS parent 顺序求 bind/animated world，再以 `animatedWorld * inverse(bindWorld)` 和 normalized four-weight linear blend skinning 计算顶点。
4. 产品播放接单个 non-additive clip，或一组全部 additive、首帧与 bind pose 对齐且实际驱动 bone 集两两不相交的 clips；两者都只接 blend/rate=1、无 blend-in/out，并按 source FPS 离散 loop。property-bound visibility 只通过现有 typed User Property snapshot 消费。
5. 重叠 bone、非 bind reference、混合 opaque/additive、非 1 rate/blend 与缺失动态值均 fail closed；未验证的冲突权重、插值与 independent-rate mixing 不做近似。
6. 官方公开的 animation-before-SceneScript 顺序仍保留；当前没有 SceneScript bone override、constraint/IK/physics merge 或动态 attachment follow。

#### 与其他系统的边界

- **Attachment（MDAT）**：静态 bind 矩阵定义挂点位置；动画跟随还需要 attachment 消费当前 animated bone world，已有 MDLA mesh 播放不会自动完成这条链
- **Physics/Constraints**：Spring/Rigid/IK 会修改骨骼角度，与 animation 合并（算法未公开）
- **Blend Shapes**：morph target 与骨骼变形是独立系统，执行顺序未公开

| 官方页面 | 分类 | 官方合同与分类边界 | 当前等级 / 最小升级门 |
|---|---|---|---|
| <a id="op-puppet-introduction"></a>[Introduction](https://docs.wallpaperengine.io/en/scene/puppet-warp/introduction.html) | `runtime-required` + `editor-export` | 播放器消费透明 source、deformable geometry、bone/root hierarchy、weights、一个或多个 Timeline animation；image effect 只能作用在作者配置的 mesh/padding 范围。自动切图、建 mesh、画权重是 editor-only。 | `L3 executed-degraded`：MDLV bind-pose 重组、受限 MDLS hierarchy/weights 与严格单 loop clip LBS 已执行；Mirror/Single、插值/mixing、channels/clipping/physics 仍未执行。 |
| <a id="op-puppet-charactersheet"></a>[Character Sheet](https://docs.wallpaperengine.io/en/scene/puppet-warp/charactersheet.html) | `editor-export` | 多个身体/衣物部件位于同一 texture，bone parent order、depth order、weights 与 reference pose 把分离部件重组；播放器消费导出结果，不负责切图或 overlay 辅助。 | `L3`：mesh UV/position 重组 bind pose；受限 80/84-byte records 的四权重已供单 clip LBS 消费。depth order 与更多 vertex layout 仍未单独验证。 |
| <a id="op-puppet-extending"></a>[Extending](https://docs.wallpaperengine.io/en/scene/puppet-warp/extending.html) | `editor-export` + `ingest-boundary` | 扩展 sheet 时原部件像素位置保持不变，新区域加在右侧/底部或既有空隙；locked geometry 不自动补 mesh，1.7 及更早项目可能不兼容。运行时只消费更新后的 asset/version，不自行扩图。 | `L0`：无 Puppet schema/version gate；需 old/new asset identity、locked geometry、missing bone/weight 和版本失败关闭 fixture。 |
| <a id="op-puppet-attachments"></a>[Attachments](https://docs.wallpaperengine.io/en/scene/puppet-warp/attachments.html) | `runtime-required` | named attachment 属于具体 bone/local point；作为 child 的任意 layer 跟随全部 Puppet animation。effect/asset 的 point property 也可绑定 attachment，绑定只在运行时生效。 | `L3 executed-degraded` 静态 bind 子集（`49ee89a`）：MDAT `u16` 绑定 MDLS bone并按 `parent * attachment * child local` 定位。虽然 parent mesh 可播放 MDLA，attachment 仍只用 bind frame；动画 follow、point property attachment 与其他版本未执行。 |
| <a id="op-puppet-clipping-masks"></a>[Clipping Masks](https://docs.wallpaperengine.io/en/scene/puppet-warp/clippingmasks.html) | `runtime-required` | 被 clip 的 limb 默认不可见，只在与指定 limb/mask 重叠时出现；支持 nested mask，反向互相引用等 cycle 非法，depth order 影响 shadow/shading。官方未公开 overlap raster/edge 算法。 | `L0`：无 clip graph；需 acyclic nested graph、deformed geometry overlap、depth/alpha/order、cycle 失败和 pixel fixture。 |
| <a id="op-puppet-texture-channels"></a>[Texture Channels](https://docs.wallpaperengine.io/en/scene/puppet-warp/texturechannels.html) | `runtime-required` | channel 与 base texture 分辨率完全相同，可按作者顺序叠加多个 channel；Timeline 以 `0...1` opacity 混合，`Alpha writing` 决定是否写 silhouette alpha。它不是 GIF/frame sequence，官方 data limit 未公开。 | `L0`：无 Puppet channel IR；需 equal-size validation、ordered opacity mix、alpha-write on/off、limit failure 和 color/alpha pixel 门。 |
| <a id="op-puppet-bone-constraints"></a>[Bone Constraints](https://docs.wallpaperengine.io/en/scene/puppet-warp/boneconstraints.html) | `runtime-required` + `research-boundary` | Spring、Rigid 与 kinematic-chain Rope 可模拟 rotation/translation、stiffness/friction/inertia、gravity、mass、tip、limits、torque、wind；animation motion 与 physics 合并。官方明确结果会随 max FPS 变化，但未公开 integrator/iteration order。 | `L0`：无 solver；需 typed constraints、fixed/variable FPS 对照、animation+physics ordering、pause/discontinuity、deterministic reset 和 budget 门；不得发明 WE 数值算法。 |
| <a id="op-puppet-inverse-kinematics"></a>[Inverse Kinematics](https://docs.wallpaperengine.io/en/scene/puppet-warp/inversekinematics.html) | `runtime-required` + `research-boundary` | IK 通常配置在 limb 末端，沿 parent chain 求解；target controller 控制整条 limb，orientation controller 决定弯曲方向，forward alignment/limit 约束结果。精确 solver、迭代和 overstretch 算法未公开。 | `L0`：无 IK IR/solver；需 chain/target/orientation identity、limit/overstretch、Loop wrap、determinism 与合法 Windows golden。 |
| <a id="op-puppet-interactive"></a>[Interactive](https://docs.wallpaperengine.io/en/scene/puppet-warp/interactive.html) | `runtime-required` + `SceneScript` | SceneScript 可按 name/index 读写 bone transform；官方明确每帧先执行所有 layer animation，再执行 scripts，脚本可覆盖 animation 结果；Spring 可在 release 后把 bone 拉回。 | `L0`：无 Puppet handles 或 SceneScript runtime；需 animation -> script 顺序、local/world transform、drag/release、physics merge、invalid handle 和每屏 teardown 门。 |
| <a id="op-puppet-perspective"></a>[Perspective](https://docs.wallpaperengine.io/en/scene/puppet-warp/perspective.html) | `runtime-required` | 2D Puppet mesh 可带 painted depth/extrusion scale；X/Y bone angles 或 layer Perspective 显示 extrusion。`Normal` culling 隐藏背面，`No cull` 镜像 texture 到背面；这不是 3D Model runtime。 | `L0`：无 depth/extruded mesh；需 depth attribute、X/Y rotation、cull/no-cull、clip/effect bounds 与 perspective pixel 门。 |
| <a id="op-puppet-blend-shapes"></a>[Blend Shapes](https://docs.wallpaperengine.io/en/scene/puppet-warp/blendshapes.html) | `runtime-required` | blend shape 是锁定 topology 上的 alternate vertex arrangement；Expression 是多个 shape weight 的组合，Timeline 动画 expression。官方未公开 shape 混合、bone deformation 与 clipping 的内部顺序。 | `L0`：无 morph target；需 topology identity、shape/expression weights、mix-order fixture、bounds 和 Timeline consumer。 |
| <a id="op-puppet-blend-rules"></a>[Blend Rules](https://docs.wallpaperengine.io/en/scene/puppet-warp/blendrules.html) | `runtime-required` + `research-boundary` | bone 可通过 `0...1` 动画权重在原 parent 与 alternate bone 间切换；多个 blend rule 可把对象置于多个 bones 之间。确切 transform interpolation/conflict order 未公开。 | `L0`：无 rule evaluator；需 stable bone identity、0/1/intermediate/multiple rule、parent cycle、animation order 和 Windows transform golden。 |
| <a id="op-puppet-animation-mixing"></a>[Animation Mixing](https://docs.wallpaperengine.io/en/scene/puppet-warp/animationmixing.html) | `runtime-required` + `research-boundary` | 同一 Puppet 可同时启用多个 animation，并分别设置 duration/rate；官方运行时把它们合并。相同 bone/property 的冲突、blend weight 与 merge algorithm 未公开。 | `L3 bounded`：v25 保存 layers；`0892e74b` 执行 bind-referenced 且驱动 bone 集不相交的 additive clips，并实时消费 typed visibility。重叠 bone、权重/插值、independent rates、非 1 blend/rate、pause/seek、script override 仍失败关闭并需要合法 golden。 |

Puppet runtime 必须把 authored pose、animations/mixing/rules、constraints/IK/physics、SceneScript bone override、deformation/channels/clipping 和 layer effects 建成可区分的阶段。只有 "animations before scripts" 是官方公开顺序；physics、IK、blend、deformation、clipping 与 effect 的相对次序在获得合法样本或官方证据前均保持 `order unknown`，不得先用箭头固化。

### 3.1 当前实施合同：静态 MDAT、严格单 clip 与 disjoint-bone additive MDLA

以下合同基于 `8bac86e` 的 mesh 分析、`49ee89a` 的 attachment 执行、`ca6d841`/`56f92a2`/`2be2b44` 的 MDLA/rig/full-TRS IR 与 `f1ee79b` 的播放执行；块布局细节见 [场景格式与 Render Graph 第 11 节](scene-format-and-render-graph.md)。

**MDAT attachment 定位（`49ee89a` 已完成的受限静态子集）**

- 已核验事实：MDAT0001 位于 MDLS 与 MDLA 之间；条目是 `u16 boneIndex + name\0 + 列主序 4x4 attachment-local matrix`。最终模型 bind frame 是层级 MDLS bone world matrix 与 attachment-local matrix 的乘积；转入 Scene 坐标使用 `F * M * F`，其中 `F = diag(1,-1,1,1)`。
- 已淘汰候选并确定组合顺序：child world 是 `parentWorld * attachmentSceneBind * childLocal`，child origin 仍作为相对 attachment 的 authored local transform。`3769688830` 三个 Scene bind 平移为 `aaaaaaaaa (-807.9761, 223.3849)`、`orb (-205.5704, -45.2606)`、`Attachment (-39.8856, 300.5312)`。
- 受限执行边界：只解析已验证的 `MDLV0023 + MDLS0004 + MDAT0001` 形状；marker/bounds/count/parent/bone/name/affine matrix 任一非法时整组 fail closed。child 没有合法 parent、parent model 没有同名 attachment 或 frame 非 16 个有限 float 时保留普通 parent transform，并以 `attachment=<name>:unavailable` 诊断；没有样本 ID 特判。
- 验收：隔离 `3769688830` 定向门中 ahriarm 从画面最右回到肩部、ahriorb 回到右上挂点；三个 attachment 进入 interpretation。当前不可执行的 `Water droplets` 只保留 bind IR，不伪装成已渲染；动画播放器也没有把静态 attachment 升级为动态 follow。

**MDLA 动画（`f1ee79b` 严格单 clip；`0892e74b` bounded additive 子集）**

- v25 保存 animation layer 的 id/clip/additive/blend/blend-in/out/time/rate/static-or-bound visibility；缺失或畸形可选数值返回 `nil`，不会递归崩溃。
- loader 只对已验证 MDLV0023/MDLS0004/MDLA0006 建立 persistent target 与三份 persistent vertex buffer；每帧 CPU 求 source-FPS 离散 LBS，并在正常 frame command buffer 中先更新 target、再供 compositor 采样，没有 per-frame `waitUntilCompleted`。
- bounded additive selector 要求全部 clip 为 additive、首帧逐 bone 与 bind pose 最大差值不超过 `0.001`，用相对首帧 `0.0001` 阈值识别 driven bones，并要求集合两两不相交；激活 clip 对自己 driven bones 提供完整 local TRS，其余骨骼保留 bind。重叠、重复 animation、非 bind reference 或 mixed opaque/additive 整层回退 bind pose。
- `animationlayers[].visible` 的 property binding 编译为稳定 `(layerID, animationLayerID)` typed bool target；每帧 snapshot 缺失或类型错误时该 clip 不激活，不执行任意 SceneScript。
- `3747492842` 继续证明严格单 clip；`3769688830` 定向门证明 7 个 Puppet layers / 17 clips，其中 6 个 disjoint-additive layers 实际播放。旧 fixed13/full45 中该样本的 bind-pose 回退结论只属于 `0892e74b` 前历史基线，本批未重跑两门。
- 旧 v24 同样本对照仍有 effect 运动，因此 whole-frame 增量只是方向性证据。没有 Windows WE golden 时，不把当前离散采样、矩阵或 LBS 写成 `L4`，也不宣称 interpolation、冲突 mixing/权重或 attachment follow。

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

<a id="5-lightinghdr-与全局后处理"></a>
## 5. Lighting 官方页面覆盖（2）与 HDR 边界

### 5.0 Lighting 系统硬限制（官方合同，2026-07-25 补充）

Wallpaper Engine 的 2D lighting 系统有明确的**性能约束和使用限制**，这些是产品级硬约束，实施时必须遵守，不能按"尽量支持"设计。

#### 硬限制（官方明确）

1. **最多 4 个光源/场景**
   - 官方文档明确："for performance reasons, you can only use a **maximum of four light sources per wallpaper**"
   - 超过 4 个光源时必须拒绝或降级，不能静默忽略
   - 这是 GPU 性能约束，不是任意可配置的值

2. **优先使用环境光（Ambient Lighting）**
   - 官方建议："Instead of adding many individual lights, try using **ambient lighting** in the scene options"
   - 环境光对性能影响小于点光源
   - 多光源场景应先尝试用环境光 + 少量点光源

3. **非必要不启用 lighting/reflections**
   - 官方警告："try to **not enable both** if you do not really need them to keep the performance impact as low as possible"
   - Lighting 和 Reflections 可以共存，但会显著增加 GPU 负载
   - 默认应关闭，只在作者明确启用时执行

4. **仅适用于显式启用的 image layers**
   - 光照效果**不自动应用**到所有层
   - 每个 image layer 必须显式启用 `Lighting` 或 `Reflection` 选项
   - 未启用的层不参与光照计算

#### 材质系统要求

**Normal Map（必需）**：
- 光照系统依赖 normal map 模拟 3D 表面
- 官方提供 normal map 生成工具（从 image layer 生成）
- 没有 normal map 的层无法正确响应光照

**材质贴图（可选）**：
- **Metallic map**：金属度
- **Roughness map**：粗糙度（0-255，不建议极值）
- **Reflection map**：反射强度
- 可手绘或用滑块控制（留空时）

#### 场景配置

- **Ambient lighting**：场景级环境光设置
- **Background color**：影响渲染，建议黑色 `#000000`
- 两者都在 scene options 中配置，不是 per-layer

#### 实施约束

Generic 2D lit-material lighting 仍为 `L0`；`b856f4ee` 的 bounded standalone `lspot` 不改变这一等级。下一批次扩展完整系统时必须：

1. **硬编码 4 光源上限**：超过时拒绝或明确降级，记录诊断
2. **Author enable gate**：只处理显式启用 lighting 的 image layers
3. **Normal map 前置检查**：缺失 normal map 时 fail closed
4. **与 ambient 的正确合成**：环境光 + 点光源，不是二选一
5. **性能预算**：lighting 开启时必须记录 GPU 成本，纳入性能门

#### 与其他系统的边界

- **2D lighting** ≠ **3D lighting**（不同 pipeline）
- **2D lighting** ≠ **Official Scene Bloom/HDR**（独立后处理）
- **2D lighting** ≠ **Workshop layer Bloom approximation**（当前 `L3` 受限实现）
- **2D lighting** ≠ **Workshop image-effect Shadow**（当前 exact profile）

不得用现有 layer Bloom、Workshop Shadow 或通用 compositor 冒充 2D lighting。

| 官方页面 | 分类 | 官方合同与分类边界 | 当前等级 / 最小升级门 |
|---|---|---|---|
| <a id="op-light-introduction"></a>[Introduction](https://docs.wallpaperengine.io/en/scene/lighting/introduction.html) | `runtime-required` | 2D image material 只有作者启用 `Lighting` 或 `Reflection` 才响应；normal map 提供表面方向，metallic、roughness、reflection map/slider 控制反射。Scene ambient/background 参与结果，官方限制每 scene 最多四个 light。normal-map generator 与 mask painting 是 editor-only。 | `L0`：无 2D lit material/light IR；需 author enable/off、四灯上限、normal/metal/rough/reflection channel、ambient/background、color space 和 pixel fixture。 |
| <a id="op-light-lights"></a>[Lights](https://docs.wallpaperengine.io/en/scene/lighting/lights.html) | `runtime-required` | Point 用 radius/intensity；Spot 用 height/direction/inner/outer cone；Tube 用可动画 start/end；Directional 无位置、只按方向覆盖全场。Spot 可投影 image/video/带完整 effects 的 layer；投影 source 在 2D Scene 可隐藏。Origin/intensity 可由 Timeline/SceneScript/audio 驱动，light Z/height 有意义，cursor script 只替换 X/Y 应保留 Z。 | 整体仍 `L0`。`b856f4ee` 仅把 standalone、无 provider/effect/script 的 exact volumetric `lspot` + relative Mirror angle Timeline 做成 `L3 bounded` direct draw；它不使 image material 响应光照。四类 typed light、surface-local coordinates、projected provider/effect graph、live target/audio/cursor、hidden-source 与 author-off 仍缺。 |

2D lighting、3D lighting、official Scene Bloom/HDR、Workshop layer Bloom 与 exact Workshop image-effect Shadow 是彼此独立的执行链。当前 Workshop layer Bloom approximation 为 `L3`（[E-EFFECT-INLINE](runtime-evidence-index.md#e-effect-inline)），`809b75e` 另执行一个 exact Workshop single-pass Shadow profile；后者不是 light/object shadow map，也没有建立 lighting 或 generic shader。`b856f4ee` 的 standalone volumetric `lspot` 同样只是无 lit-material interaction 的 bounded projector cone（[E-SPOT-LIGHT](runtime-evidence-index.md#e-spot-light)），不升级 generic 2D lighting。official Scene Bloom target identity 为 `L1`，其 HDR target、tone mapping、Ultra HDR、per-layer HDR brightness、lighting shadow/reflection runtime 均为 `L0`。不得用现有 layer Bloom、Workshop Shadow、standalone cone 或 2D compositor 冒充完整 lighting/HDR 系统。

## 6. Shader 与高级 Effect 边界

| 能力 | 等级 | 当前边界 | 权威细表 |
|---|---|---|---|
| effect/material/pass IR | `L2` | 字段可保存并建图 | [Graph/Shader 覆盖表](render-graph-shader-coverage.md) |
| bounded graph executors | `L3` | precise/default Blur与exact Workshop Shadow保留各自现役边界；stock Local Contrast的strict owner已撤销，exact四节点图现由普通MaterialProgram/GraphTargets/GraphExecutor以generic-only执行。首条历史strict链为`3724289844:20`的`Blur Precise -> Shadow`；当前Local Contrast见[E-V1-LOCAL-CONTRAST-SHARED-OWNER](runtime-evidence-index.md#e-v1-local-contrast-shared-owner)，旧[E-EFFECT-LOCAL-CONTRAST](runtime-evidence-index.md#e-effect-local-contrast)只作provenance | [Effect 执行表](effect-execution-coverage.md) |
| arbitrary authored shader | `L0` | 自有 Metal 近似不等于作者 shader | [Graph/Shader 覆盖表](render-graph-shader-coverage.md) |
| history/copy/swap generic runtime | `L3 bounded` | 共享GraphExecutor/GraphTargets已执行一个effect-scoped RGBA/BGRA的2 material + 1 copy persistent history、同effect双copy及两个descriptor-identical copy/swap组合；生命周期还闭合同输入、same-identity/different-authored-state及一次same-identity/different-target-topology正式scene switch、surface stop/relaunch和pause/resume。其他topology/format/provider、seek/device loss/multi-surface与官方parity不外推 | [Graph/Shader 覆盖表](render-graph-shader-coverage.md) |

通用执行不等于把所有对象塞进一个巨型 renderer。Puppet deformation、2D/3D lighting、model animation/physics、RGB output 和 offline bake 可以拥有各自凝聚的解析、simulation/evaluator 与 geometry 子系统；它们仍必须把结果降低到共享 identity、frame snapshot、resource/provider generation、Program/material、graph/target/publication 和 compositor output。不得因为存在专用子系统就建立按完整对象/样本名称选择视觉答案的第二条产品主链，也不得提前把 2D bounded executor 宣称为高级对象支持。

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
| screen resize/reconfigure | `L2` | surface 可重建且共享 clock 不重置；embedded video registry 按 launch/device/source 保留连续 provider，过期 source 在 rebuild 后停止 | display hot-plug/Space/scale transition 真实运行门 |
| pause/sleep/lock | `L2` | 统一播放控制已接 Scene clock/frame driver/video provider；纯状态门证明冻结、resume 不补长帧和 provider suspend/resume | focus/fullscreen/sleep/lock 的真实系统事件门，粒子/effect/video 可见连续性 |
| target FPS / refresh-rate driver | `L0` | 固定 60 Hz Timer | per-display refresh、frame pacing、low power |
| quality tiers | `L0` | 无统一 policy | effect/particle/RT 降级必须可诊断 |
| texture resolution policy | `L1` | 有有限 decode/RT budget，但无产品级统一策略 | logical/mapped/physical size、POT padding、mip、memory pressure |
| shared decode/GPU resource reuse | `L1` | 同 Metal device 的 embedded video source 可跨 surface 复用；普通 image/renderer/decode/upload 仍多屏重复 | immutable asset cache + 完整 per-device ownership |
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

RGB 不阻塞 V0-V4；在 macOS 没有明确设备 adapter、授权和产品策略前保持 `L0` fail-closed。

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

WaifuX 的可借鉴点是实时和 bake 共用核心，不是复制其实现。现有 live-value 的 alpha/solid color/Local Contrast strength 子集已成立；离线能力仍需复用同一 provider、fixed-time、deterministic input replay 与 producer/consumer 合同，但这些发行向能力不阻塞 V0 的实时普通 effect。

## 10. 高级系统共享接入点

下表描述高级子系统接入现有主链时必须复用的 owner，不是要求“先完成全部公共平台”才能开始高级能力。每项都可以从一个真实内容的最小纵向切片进入，并只实现该切片实际需要的共享对象。

| 高级系统 | 可保留的专用职责 | 必须复用的共享运行对象 |
|---|---|---|
| Puppet mesh/animation | mesh/bone/channel IR、deformation、clip evaluator、constraint/physics | stable asset/bone identity、frame/mutation order、texture/material Program、graph target/publication、compositor output |
| 2D lighting/HDR | light selection、lit-material inputs、shadow/volume/HDR stages | layer/light identity、frame inputs、resource generation、Program/render state、graph target 与 scene post output |
| 3D model/animation | model/node/skeleton/camera IR、animation/physics、3D geometry | VFS/resource identity、shared clock/frame snapshot、material Program、graph/target/publication、唯一 compositor handoff |
| RGB output | source selection、downsample/device adapter | scene/layer identity、已提交 frame、独立 publication、生命周期与无设备 fallback；不得另跑一套 wallpaper renderer |
| offline bake | fixed clock、input replay、encoder adapter | 与 realtime 相同的 IR、Program、graph、provider、particle/script state 和 compositor output |

[能力依赖图](capability-dependency-map.md)继续用于定位共享 owner 和影响面，不是 V5 前的串行阶段门。

## 11. 与唯一现役路线的关系

1. V0 先闭合普通 authored material/shader 到现有 GraphExecutor/compositor 的可见链；任何 Puppet、lighting、3D、RGB 或 offline 完整平台都不是 V0 前置。
2. 本表高级能力归入 V5。只有真实 corpus 价值或用户结果足以提升优先级时，才从该能力的首断点建立一个可回滚纵向切片；不得沿用旧批次编号、样本 ID 排序或“先搭完整平台再出画面”的顺序。
3. 专用 evaluator/simulator/geometry 可以存在，但输入必须来自作者数据和共享 primitive，输出必须回到统一 Program/graph/publication/compositor；不能按完整 effect/object/sample identity 选择固定视觉算法。
4. 未实现的 optional stage 只停用最小对象或 pass；路径、GPU range、handle generation、target/publication 与生命周期破坏仍硬拒绝对应执行单元。
5. 能力升级只同步本表受影响行和实际证据。首个可见切片不以完整结构平台、全 corpus、发行性能或 Windows parity 为前置；若声明完整视觉/发行能力，仍必须补相应数值、像素、teardown、压力与产品门。
