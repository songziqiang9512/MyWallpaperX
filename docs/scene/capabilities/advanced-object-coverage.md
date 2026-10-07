# Scene 对象、Puppet、3D 与产品能力覆盖表

> 状态：现役专项表
>
> 最近核对：2026-10-02（本轮只收敛 2D lit-material 与作者 normal 的旧断言；normal 有界片已获独立产品验收，其余能力未重扫，仍以各自链接的权威为准）
>
> 实现基线见 [运行证据索引](runtime-evidence-current.md)；本表不复制基线 commit，文内 commit 号是各能力的历史落地提交。
>
> 运行事实与签名 App 身份统一见 [运行证据索引](runtime-evidence-current.md)。本表只展开高级对象能力，不定义平行开发顺序；Puppet、lighting/HDR、3D、RGB 和离线能力统一归入[现役路线](../roadmap/scene-compatibility-roadmap.md)的 V5，且不阻塞 V0 普通 authored effect 首次出画面。

本表覆盖基础对象之外容易被笼统描述掩盖的能力：utility composition、sound、Puppet Warp、3D model、lighting/HDR、性能策略、RGB 和离线烘焙。等级口径见 [`coverage-ledger.md`](coverage-ledger.md)，逐页官方归属见 [`official-page-map.md`](../development/reference/official-page-map.md)，16 组导航见 [`docs/scene/history/reference/official-page-crosswalk.md`](../history/reference/official-page-crosswalk.md)。

## 1. 文件、资源和基础对象

| 能力 | 等级 | 当前证据 | 当前边界 / 下一门 |
|---|---|---|---|
| loose Scene/project ingest | `L3` | [`SceneProject.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Format/SceneProject.swift)、[E-INGEST](../history/runtime-evidence-index.md#e-ingest) | 私有 schema 版本和异常字段继续 fail-closed |
| PKGV index/extraction | `L3` | [`ScenePkgReader.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Format/ScenePkgReader.swift)、[E-INGEST](../history/runtime-evidence-index.md#e-ingest) | case/symlink/duplicate/压缩边界和 VFS golden |
| TEX common decode | `L3` | [`SceneTextureLoader.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureLoader.swift)、[E-INGEST](../history/runtime-evidence-index.md#e-ingest) | 全容器/format/mip/color-space 边界 |
| resource identity and missing diagnostics | `L3` | [`SceneResourceReferenceIndex.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneResourceReferenceIndex.swift)、[E-INGEST](../history/runtime-evidence-index.md#e-ingest) | 统一 VFS、alias/case 规则与依赖版本 |
| image layer | `L3` | Metal compositor、180/181 固定矩阵结构计数、[E-BASE](../history/runtime-evidence-index.md#e-base) | 通用 material/effect/provider 和 WE pixel golden |
| solid layer | `L3` | typed solid、1x1 white texture、author color；纯 solid color 已由现有 per-surface snapshot live 消费；[E-BASE](../history/runtime-evidence-index.md#e-base)、[E-LIVE-PROPERTY](../history/runtime-evidence-index.md#e-live-property) | non-solid/mixed color、HDR/light |
| text layer | `L3` | CoreText 静态纹理、direct property 动态重栅格、79/108 结构门、[E-TEXT](../history/runtime-evidence-index.md#e-text) | time/SceneScript/system/media 值与 Windows typography |
| particle layer | `L3` | 固定门 18/27、完整门 83/131 可见层进入受限 runtime（REFRACT 材质 fail closed）；[E-PARTICLE](../history/runtime-evidence-index.md#e-particle) | 逐组件状态见 [粒子表](particle-component-coverage.md) |
| container/parent hierarchy | `L3` | source order、parent transform/visibility/parallax propagation、[E-BASE](../history/runtime-evidence-index.md#e-base) | composition、动态 reparent、复杂 component |
| sound layer | `L3 bounded / S4 representative composition visible`（状态权威为[能力台账](coverage-ledger.md) Sound 行与[输入覆盖表](runtime-input-property-coverage.md)，本行只链接不重复） | Sound IR、单一 FLAC/MP3/WAV + `loop` + `startsilent=false` + finite volume 的播放、typed property volume 与 pause/resume/stop 由唯一 launch-scoped player registry 执行；最终 identity 的真实 `3780119725` 严格 PASS；[E-V4-SCENE-SOUND-PLAYBACK](../history/runtime-evidence-index.md#e-v4-scene-sound-playback)、[E-V4-SCENE-SOUND-SHARED-SPECTRUM](../history/runtime-evidence-index.md#e-v4-scene-sound-shared-spectrum) | 多音源、startsilent/非 loop、`spatialization=true` 及缺布尔值但含 spatial 调参的歧义结构继续 unsupported；sound 空间化（changelog REV 4167/4168、editor 字符表 attenuation 字段族）当前没有任何消费路径，官方 sitemap 也没有 sound 专页，开放前必须先建证据，不得猜默认 |
| Puppet layer | `L3 executed / S4 bounded visible` | MDLV0014/0016/0017/0019/0023 bind geometry、后四族full-TRS LBS、严格单 clip与受限 layered mixing、世界空间 `GeometryProduct` 直绘；无MDLA/MDAT的`MDLV0014 + MDLS0002`复用同一bind/script pose链；`MDLV0023 + MDLS0004 + MDAT0001` named attachment 逐帧消费当前 bone world，child、SceneScript snapshot、cursor 与最终 skinning 共用有序 pose；[`MDLV0014`证据](runtime-evidence-current.md#e-2026-09-14-puppet-mdlv0014)、[动态attachment证据](runtime-evidence-current.md#e-2026-09-13-puppet-dynamic-attachment) | 非 1 blend、完整冲突 mixing/权重、MDLV0014动画/attachment、MDLA0003 auxiliary scalar、point-property attachment、其他 MDAT/version、旋转/重力/IK、channels/clipping 与 Windows golden |
| 3D model layer | `L3 bounded / S4 two real static slices` | bounded MDLV0023及direct-static MDLV0016 format15/u16或u32单mesh进入launch-prepared geometry、straight-albedo、独立UV/sampler的显式emissive-alpha mask、authored transform、reverse-Z depth与现役main pass/compositor；direct model material link以typed source fact发布，精确小写 `color/alpha` 优先于同材质中的编辑器默认 `Color/Alpha`，`LIGHTING=0` 保留base albedo/tint而只关闭场景光；exact `{user,value}` 的 `color/alpha/emissivecolor/emissivebrightness/brightness` 形成layer-scoped typed material target并可由同一surface snapshot live消费；pass 0 / slot 0 的primary named albedo由当前可见model consumer驱动隐藏image/solid provider，经既有target pool/frame registry进入同一draw，property texture override与动态color/alpha同样复用surface snapshot；`tintfront/tintback/tintwexponent`、tint-mask alpha及scripted back tint由共享材质/QuickJS owner消费；真实`3437487219`的Earth/Cloud双壳可见，真实native-perspective `3509243656`执行12个material property target，默认及custombg参数路由分别完成`433 → 436`与`589 → 331`；可选mask采样失败只关闭channel；[E-V4-STATIC-MODEL-BASE-COMPOSITION](../history/runtime-evidence-index.md#e-v4-static-model-base-composition) | display SceneScript完整轨道、其他MDL layout、node hierarchy、多mesh/material、normal/PBR、float HDR/bloom/tone-map、完整stock model shader、asset camera/skeleton/animation/physics与官方pixel golden |
| light object | `L3 bounded / directional user intensity S4 + point direct-model S3 + standalone spot` | scene ambient/skylight与directional/point/spot共用按当前作者render order和canonical frame visibility选取的**总计4灯**typed snapshot；三类direct-static light的exact `intensity`均进入同一`.layer(...,.intensity)` publication/consumer，启动期按全部light candidate预留color/intensity target，避免作者隐藏或隐藏父链在live显示后丢失消费资格。standalone volumetric spot cone逐帧读取同一typed color/intensity snapshot并服从frame visibility，未再冻结第二份launch值；其inline script须同时存在实际实例化的scalar intensity target与唯一顶层、小写exact source evidence，大小写变体、额外nested source及`color/visible`仍失败关闭。真实`3437487219`的directional user property已取得S4可见变化；真实`3662790108`逐帧建立1个point snapshot并让14个`receivesLighting`静态模型draw取得Metal completion。见[共享强度证据](runtime-evidence-current.md#e-2026-09-20-shared-light-intensity)与[当前点光证据](runtime-evidence-current.md#e-2026-09-20-point-light-static-model) | point SceneScript intensity仍被更早的QuickJS aggregate-source预算准入阻断；standalone spot的typed live变更尚缺真实样本事件/ROI复核。shadow/PBR、tube、完整 2D lighting、HDR/tone-map/volume、官方固定输入像素对照均未闭合；有界 2D lit-material 已有独立 consumer，作者 normal 的本批边界与终审状态见[实施证据](../history/d3-authored-normal-input-implementation-2026-10-02.md)；`3287715210`虽有point声明但没有static-model consumer。不得把本direct-model/standalone slice外推为通用lighting或整样本通过 |

“某资源被 catalog 发现”最多是 `L1`；只有对象类型进入 IR 和 renderer 路由才是 `L2`，有受控执行和门才是 `L3`。

## 2. Object 与 Utility composition

> Effectful forward provider 必须 authored-order-independent：自身 layer source、静态 asset、普通 frame input与同一plan已验证的单一primary上游可进入共享 graph；scene background、secondary、未声明named target与多依赖继续关闭。

| 能力 | 等级 | 当前能力 | 下一门 |
|---|---|---|---|
| source order | `L3` | render order 固定为 scene object 顺序；[E-BASE](../history/runtime-evidence-index.md#e-base) | dynamic topology 与 official golden |
| parent transform | `L3` | origin/size/scale/angles 合成；[E-BASE](../history/runtime-evidence-index.md#e-base) | 3D、shear、动态 target 和数值 golden |
| effective visibility | `L3` | parent/child/effect/particle gating；[E-BASE](../history/runtime-evidence-index.md#e-base) | live topology invalidation |
| layer alpha/color/blend mode | `L3` | 静态 descriptor/compositor 子集；layer alpha 与纯 solid color 已由现有 per-surface snapshot live 消费；[E-BASE](../history/runtime-evidence-index.md#e-base)、[E-LIVE-PROPERTY](../history/runtime-evidence-index.md#e-live-property) | visibility/topology、non-solid/mixed color、完整 blend/premultiply/color space |
| dependency layer IDs | `L3 bounded` | 可保留并进入 dependency plan；classic primary named-provider 的单 backward composition dependency由共享`.resolvedMaterial` binding与普通GraphExecutor执行，旧exact Clipping owner已删除；当前支持由可见 image consumer 反向可达的隐藏 image provider closure，以及带一个已验证primary上游的effectful forward hidden-image provider closure。effectful provider的最终GraphExecutor输出复制到独立primary named reservation后再供下游消费；pre-encode ordinary capture miss可沿已证backward closure逐层typed撤销并保留独立successor | secondary、cycle、child、非 image provider、多个依赖或provider reference、history、encode后publication失败与更深/混合 topology |
| typed composition/project/fullscreen layer | `L3` | 有限 current-frame capture/geometry；classic primary `Clipping Mask` / `Clipping Mask -> static Opacity`的bounded结构经普通MaterialProgram执行，不再按effect path/hash选择专用实现；[E-UTILITY](../history/runtime-evidence-index.md#e-utility) | 完整子场景边界、嵌套、其他named profile和target ordering |
| current-frame capture | `L3` | bounded provider、clipping、GPU completion；composition dependency capture 与 named binding 共用完整-chain consumer 集合；[E-UTILITY](../history/runtime-evidence-index.md#e-utility) | 通用 capture mask/format/extent 与 SceneScript/dynamic alpha |
| named primary `_a` target | `L3` | bounded producer/consumer 和预算池；`2974757317` 只捕获 `912/57382` 并绑定 `956/57098`；[E-UTILITY](../history/runtime-evidence-index.md#e-utility) | 通用 authored identity、copy/swap/compose |
| named secondary `_b` identity | `L2` | registry 区分完整 variant；同层 immediate-prior effect 的显式 `previous` graph binding 可证明低优先级 `_b` 只属 authored provenance，并由既有 graph identity 独占输入 ownership；[E-V1-EXACT-PREVIOUS-INPUT-SHADOW](../history/runtime-evidence-index.md#e-v1-exact-previous-input-shadow) | 真正 `_b` producer/consumer、history 与非 immediate 拓扑仍未执行 |
| RGB composition semantics | `L0` | current-frame capture 不能冒充 RGB camera | 独立 subtree capture、device output 和 author-off |
| nested/effectful provider | `L3 bounded` | primary `_a`、acyclic、hidden image provider closure 已闭合 backward 两级链与 forward `92→104→27`；后者把完整上游闭包按依赖优先放入transaction ledger与prepass，而最终compositor仍保持author order。`91→92→104→1104`另证明pre-encode ordinary capture miss只级联撤销真实下游、独立Program仍同帧composite并在下一帧恢复全链；所有provider graph final复制到独立named reservation，hidden provider不持有compositor | secondary、cycle、child、非 image、multi-dependency/reference、history/resize/device-loss、encode后publication失败与任意深度/更深混合链 |

Utility composition 已是极窄的 `L3` 子集，不再写成完全缺失；hidden-image provider 现已把 primary `_a` 的 backward acyclic nested chain与单上游effectful forward provider闭合在同一plan/runtime。`2974757317:914` 的 SceneScript alpha、`3768229922` 的 9 个隐藏 weighted profile、child/non-image/multi-dependency provider、任意 composition、RGB Composition 与 `_b` history 仍没有因此闭合。

<a id="3-puppet-warp"></a>
## 3. Puppet Warp 官方页面覆盖（13）

本节逐页记录官方公开的作者行为和播放器必须消费的导出结果。Geometry 自动生成、权重绘制、Character Sheet 制作等属于编辑器工作流；MyWallpaperX 不需要复刻这些工具，但 Puppet IR 必须逐步保留其导出的 mesh、bone、weight、depth order、channel、constraint 和 animation 数据。官方页面没有公开 mesh/weight 序列化、deformation、IK、constraint、clipping 或 animation mixing 的数值算法，均保持 `algorithm unknown`，不能凭视觉近似写成已验证合同。

### 3.0 Puppet 动画证据边界（2026-07-25 核对）

Puppet Warp 的核心是骨骼驱动网格变形。官方页面说明 bone hierarchy、weight painting、Timeline animation/mode 和 animation-before-SceneScript 顺序，但没有公开 MDLS/MDLA 二进制 schema、矩阵乘法顺序、skinning 数值算法或 mixing 冲突规则。编辑器教程以旋转关节为主要创作方式，不等于运行时格式禁止 translation/scale；三份独立真实 MDLA0006 资产的逐帧记录都包含变化的 translation 和 scale，因此 IR 必须保留完整 TRS。

执行范围以本页第 3.1/3.2 节为准，格式边界见[Scene 格式合同](scene-format-and-render-graph.md)。真实 bind frame 对照锁定局部矩阵为 `T * Rz * Ry * Rx * S`（已核验资产最大误差 `8.61e-6`）；evaluator 按 MDLS parent 顺序求 world，以 `animatedWorld * inverse(bindWorld)` 和 normalized four-weight LBS 变形。pre-script pose 供脚本查询，override 后的有效几何与 attachment 沿原播放链发布；旋转/重力/IK 物理仍未实现。

#### 与其他系统的边界

- **Attachment（MDAT）**：attachment-local matrix 在 generation 保留；每帧由当前 bone world 乘 local matrix生成 Scene frame。child world、脚本查询、cursor hit 与 mesh skinning按 animation/physics→script→final pose 顺序消费同一 typed pose 合同
- **Physics/Constraints**：Spring/Rigid/IK 会修改骨骼角度，与 animation 合并（算法未公开）
- **Blend Shapes**：morph target 与骨骼变形是独立系统，执行顺序未公开

| 官方页面 | 分类 | 官方合同与分类边界 | 当前等级 / 最小升级门 |
|---|---|---|---|
| <a id="op-puppet-introduction"></a>[Introduction](https://docs.wallpaperengine.io/en/scene/puppet-warp/introduction.html) | `runtime-required` + `editor-export` | 播放器消费透明 source、deformable geometry、bone/root hierarchy、weights、一个或多个 Timeline animation；image effect 只能作用在作者配置的 mesh/padding 范围。自动切图、建 mesh、画权重是 editor-only。 | `L3 executed-degraded`：MDLV0014/0016/0017/0023 bind geometry直接以world MVP绘制，受限 MDLS hierarchy/weights、严格单 clip LBS和受限layered mixing已执行；0014只验证无MDLA/MDAT的bind/script形状。channels/clipping 与平移之外的 physics 仍未执行。 |
| <a id="op-puppet-charactersheet"></a>[Character Sheet](https://docs.wallpaperengine.io/en/scene/puppet-warp/charactersheet.html) | `editor-export` | 多个身体/衣物部件位于同一 texture，bone parent order、depth order、weights 与 reference pose 把分离部件重组；播放器消费导出结果，不负责切图或 overlay 辅助。 | `L3`：mesh UV/position与原始atlas由世界空间网格组合；受限 MDLV0014/0016 52-byte与MDLV0017/0023 80/84-byte records的四权重已供bind或单 clip LBS消费。depth order 与更多 vertex layout 仍未单独验证。 |
| <a id="op-puppet-extending"></a>[Extending](https://docs.wallpaperengine.io/en/scene/puppet-warp/extending.html) | `editor-export` + `ingest-boundary` | 扩展 sheet 时原部件像素位置保持不变，新区域加在右侧/底部或既有空隙；locked geometry 不自动补 mesh，1.7 及更早项目可能不兼容。运行时只消费更新后的 asset/version，不自行扩图。 | `L0`：无 Puppet schema/version gate；需 old/new asset identity、locked geometry、missing bone/weight 和版本失败关闭 fixture。 |
| <a id="op-puppet-attachments"></a>[Attachments](https://docs.wallpaperengine.io/en/scene/puppet-warp/attachments.html) | `runtime-required` | named attachment 属于具体 bone/local point；作为 child 的任意 layer 跟随全部 Puppet animation。effect/asset 的 point property 也可绑定 attachment，绑定只在运行时生效。 | `L3 executed / S4 bounded visible`：受限 MDAT `u16` bone identity 与 local matrix 在加载时保留；逐帧 current frame=`boneWorld × attachmentLocal`，Scene child 为 `parentWorld × currentAttachment × childLocal`。真实 `3749463715` 的胸部、手部/手臂 attachment 和拖拽回弹闭环；point property attachment、其他版本及官方数值 parity未执行。 |
| <a id="op-puppet-clipping-masks"></a>[Clipping Masks](https://docs.wallpaperengine.io/en/scene/puppet-warp/clippingmasks.html) | `runtime-required` | 被 clip 的 limb 默认不可见，只在与指定 limb/mask 重叠时出现；支持 nested mask，反向互相引用等 cycle 非法，depth order 影响 shadow/shading。官方未公开 overlap raster/edge 算法。 | `L0`：无 clip graph；需 acyclic nested graph、deformed geometry overlap、depth/alpha/order、cycle 失败和 pixel fixture。 |
| <a id="op-puppet-texture-channels"></a>[Texture Channels](https://docs.wallpaperengine.io/en/scene/puppet-warp/texturechannels.html) | `runtime-required` | channel 与 base texture 分辨率完全相同，可按作者顺序叠加多个 channel；Timeline 以 `0...1` opacity 混合，`Alpha writing` 决定是否写 silhouette alpha。它不是 GIF/frame sequence，官方 data limit 未公开。 | `L0`：无 Puppet channel IR；需 equal-size validation、ordered opacity mix、alpha-write on/off、limit failure 和 color/alpha pixel 门。 |
| <a id="op-puppet-bone-constraints"></a>[Bone Constraints](https://docs.wallpaperengine.io/en/scene/puppet-warp/boneconstraints.html) | `runtime-required` + `research-boundary` | Spring、Rigid 与 kinematic-chain Rope 可模拟 rotation/translation、stiffness/friction/inertia、gravity、mass、tip、limits、torque、wind；animation motion 与 physics 合并。官方明确结果会随 max FPS 变化，但未公开 integrator/iteration order。 | `L3 bounded`：MDLS 平移 spring/rigid 的 stiffness/friction/inertia/max-distance 已由唯一 playback 消费，15/120 FPS fixture 与真实 release 回弹见 [B9](runtime-evidence-current.md#e-2026-09-10-b9-spring-closure)。旋转/重力/IK、parent-chain 动态耦合、pause/seek 长稳及官方数值 parity 尚无完成证据；不将项目积分器称为 WE 算法。 |
| <a id="op-puppet-inverse-kinematics"></a>[Inverse Kinematics](https://docs.wallpaperengine.io/en/scene/puppet-warp/inversekinematics.html) | `runtime-required` + `research-boundary` | IK 通常配置在 limb 末端，沿 parent chain 求解；target controller 控制整条 limb，orientation controller 决定弯曲方向，forward alignment/limit 约束结果。精确 solver、迭代和 overstretch 算法未公开。 | `L0`：无 IK IR/solver；需 chain/target/orientation identity、limit/overstretch、Loop wrap、determinism 与合法 Windows golden。 |
| <a id="op-puppet-interactive"></a>[Interactive](https://docs.wallpaperengine.io/en/scene/puppet-warp/interactive.html) | `runtime-required` + `SceneScript` | SceneScript 可按 name/index 读写 bone transform；官方明确每帧先执行所有 layer animation，再执行 scripts，脚本可覆盖 animation 结果；Spring 可在 release 后把 bone 拉回。 | `L3 bounded / S4 visible`：0-based name/index、真实 parent 与 world/local journal、先 animation/physics 后 script、callback/frame 回滚及真实拖动/回弹/区域外不捕获已接通；可见和终端证据见 [B9](runtime-evidence-current.md#e-2026-09-10-b9-spring-closure)。多屏、parallax-enabled 与完整 Mat4/parity 尚无完成证据。 |
| <a id="op-puppet-perspective"></a>[Perspective](https://docs.wallpaperengine.io/en/scene/puppet-warp/perspective.html) | `runtime-required` | 2D Puppet mesh 可带 painted depth/extrusion scale；X/Y bone angles 或 layer Perspective 显示 extrusion。`Normal` culling 隐藏背面，`No cull` 镜像 texture 到背面；这不是 3D Model runtime。 | `L0`：无 depth/extruded mesh；需 depth attribute、X/Y rotation、cull/no-cull、clip/effect bounds 与 perspective pixel 门。 |
| <a id="op-puppet-blend-shapes"></a>[Blend Shapes](https://docs.wallpaperengine.io/en/scene/puppet-warp/blendshapes.html) | `runtime-required` | blend shape 是锁定 topology 上的 alternate vertex arrangement；Expression 是多个 shape weight 的组合，Timeline 动画 expression。官方未公开 shape 混合、bone deformation 与 clipping 的内部顺序。 | `L0`：无 morph target；需 topology identity、shape/expression weights、mix-order fixture、bounds 和 Timeline consumer。 |
| <a id="op-puppet-blend-rules"></a>[Blend Rules](https://docs.wallpaperengine.io/en/scene/puppet-warp/blendrules.html) | `runtime-required` + `research-boundary` | bone 可通过 `0...1` 动画权重在原 parent 与 alternate bone 间切换；多个 blend rule 可把对象置于多个 bones 之间。确切 transform interpolation/conflict order 未公开。 | `L0`：无 rule evaluator；需 stable bone identity、0/1/intermediate/multiple rule、parent cycle、animation order 和 Windows transform golden。 |
| <a id="op-puppet-animation-mixing"></a>[Animation Mixing](https://docs.wallpaperengine.io/en/scene/puppet-warp/animationmixing.html) | `runtime-required` + `research-boundary` | 同一 Puppet 可同时启用多个 animation，并分别设置 duration/rate；官方运行时把它们合并。相同 bone/property 的冲突、blend weight 与 merge algorithm 未公开。 | `L3 bounded`：v25 保存 layers，typed visibility与静态权重按第3.2节执行；第3.3节执行单clip骨骼alpha。多clip alpha、动态blend/pause/seek及更广冲突parity未闭合；script override见Interactive。 |

Puppet runtime 必须把 authored pose、animations/mixing/rules、constraints/IK/physics、SceneScript bone override、deformation/channels/clipping 和 layer effects 建成可区分的阶段。只有 "animations before scripts" 是官方公开顺序；physics、IK、blend、deformation、clipping 与 effect 的相对次序在获得合法样本或官方证据前均保持 `order unknown`，不得先用箭头固化。

### 3.1 当前实施合同：动态 MDAT、严格单 clip 与受限 layered MDLA

以下合同基于既有 mesh、MDAT、MDLA/rig/full-TRS reader 与当前 `GeometryProduct`/playback 执行；块布局细节见 [场景格式与 Render Graph 第 11 节](scene-format-and-render-graph.md)。

**MDAT attachment 定位与逐帧跟随（受限执行子集）**

- 已核验事实：MDAT0001 位于 MDLS 与 MDLA 之间；条目是 `u16 boneIndex + name\0 + 列主序 4x4 attachment-local matrix`。reader 保留该 local frame；bind/current model frame 分别为对应 bone world 与 local frame 的乘积，转入 Scene 坐标使用 `F * M * F`，其中 `F = diag(1,-1,1,1)`。
- canonical 组合顺序为 `parentWorld * attachmentSceneCurrent * childLocal`，child origin/scale/angles仍是 attachment-relative authored local transform。pre-script animation/physics pose用于当帧 layer/bone snapshot和 cursor；脚本完成后的 final pose同时用于 LBS、attachment snapshot、world resolver与 encode，不允许各 owner独立重算另一套 hierarchy。
- 受限执行边界：只解析已验证的 `MDLV0023 + MDLS0004 + MDAT0001` 形状；marker/bounds/count/parent/bone/name/affine matrix任一非法时整组 fail closed。缺少合法 current frame 时只对该挂点保留已验证 bind frame；child 没有合法 parent、同名 attachment 不存在或 frame 非 16 个有限 float 时保留普通 parent transform并诊断。没有样本 ID 特判。
- 验收：既有 `3769688830` 静态定位正例继续成立；真实 `3749463715` 的 parent 464/1106 上 `Attachment / 2 / 4` 当前 frame驱动胸部、剑与手部 child，稳定帧保持组装。layer 562 的实际拖拽写入使 submitted geometry 最大偏移 `45.451706 px`，同帧 terminal compositor观察到变形，松手后恢复基线；见[当前证据](runtime-evidence-current.md#e-2026-09-13-puppet-dynamic-attachment)。point property attachment与其他MDAT/version仍未执行。

**MDLA 动画（`f1ee79b` 严格单 clip；2026-09-06 layered 组合与 loop/mirror/single interval 采样）**

- v25 保存 animation layer 的 id/clip/additive/blend/blend-in/out/time/rate/static-or-bound visibility；缺失或畸形可选数值返回 `nil`，不会递归崩溃。
- loader 对已验证且无MDLA/MDAT的MDLV0014/MDLS0002建立immutable bind-pose vertex/index buffer；动画只对MDLV0016/MDLS0002/MDLA0003、MDLV0017/MDLS0002/MDLA0004、MDLV0019/MDLS0002/MDLA0005 或 MDLV0023/MDLS0004/MDLA0006 version pair 建立三份 persistent dynamic vertex buffer。每帧 CPU 求 source-FPS LBS，把变形后的原始 mesh 像素位置写入下一 vertex buffer，再由正常 frame command buffer 直接绘制，没有 per-frame `waitUntilCompleted` 或中间纹理。MDLA0005 的 trailer 是 34 字节全零（无 auxiliary track），其他形状失败关闭。
- compositor 只计算一次 `cameraVP × parallax × authored world(origin/scale/hierarchy) × Y orientation × pivot`，直接作用于原始/变形 mesh 位置；不再计算 `size∪bind-pose` coverage、不把 mesh 归一到 quad，也不按 coverage 分配纹理。无 effect 时 mesh 采样原 atlas；有 effect 时普通 graph 先在 atlas mapped extent 内执行，mesh 再采样 graph-final 纹理。atlas/graph-final 不是已组合 layer source，Puppet 跨层命名 provider 在依赖计划编译阶段拒绝。
- selector 保留作者顺序与有限正 rate；重复 animation id、越界 frame 或非法 transform 失败关闭。loop/mirror/single 均进入 IR；相邻 authored pose 的 interval 携带 fraction 插值，mirror 保留末端 pose 与方向，single 停在末端。静态权重与组合见第 3.2 节；blend-in/out 仍未支持。
- `animationlayers[].visible` 的 property binding 编译为稳定 `(layerID, animationLayerID)` typed bool target；每帧 snapshot 缺失或类型错误时该 clip 不激活，不执行任意 SceneScript。
- 既有单 clip、layered、多层组装和清晰度回放见[当前运行证据](runtime-evidence-current.md)。whole-frame 变化含 effect 运动，不能单独证明骨骼数值正确；未完成官方对照的 interval、LBS、attachment 与多轨冲突保持 bounded 状态。

### 3.2 Puppet 静态权重与几何失败边界
2026-10-07 的先行设计落在本节，沿已有 IR → prepared animation → evaluator → 动态顶点/attachment/compositor 实施。旧 selector 的 `blend<=1`、首 additive 无权重 anchor、frame-0 reference 缓存和 extra clamp 退出；

- 接受能表示为有限 Float 的非负静态 blend，0 不贡献姿态。逐 bone 首个 opaque 相对 bind 加权，各 additive 统一相对 bind 叠加 T/S 差与局部旋转 delta；不再用动画第 0 帧作为权重基准。旋转权重使用最短半球归一化线性混合，时间插值仍沿现有 sampler；额外 opaque 顺序、动态 blend/seek API、非共轴多轨官方 parity 不由本批承诺。
- 固定官方 2.8.0.42 黑盒暂停帧控制证明 0/.5/1/1.3/2 的 base/extra/单 opaque T/S 外推，并排除球面旋转外推。非 bind 的 frame0 控制区分了参考基准；项目 nlerp 与控制的预设旋转容差为 0.002 rad，不声称恢复官方内部公式。完整输入与身份见[运行证据](runtime-evidence-current.md#e-2026-10-07-puppet-static-weight)。更广权重是本实现安全范围，不等于官方全域 parity。
- 非有限加权 pose、奇异 world 或最终 skinned vertex 失败时不上传部分几何。PlaybackState 首次未取得完整顶点时 named publication 与直接 draw 都拒绝；后续失败保留上一完整 vertex/attachment，DEBUG 只报告成功顶点。现有 VM getter 仅验证完整有限骨骼矩阵，最终顶点溢出的帧仍可能给脚本提供新骨骼 snapshot；本合同不宣称 VM/geometry 全链原子回滚。
- 最近门是 `test_scene_puppet_weights`、真实 Metal 的 `test_scene_puppet_buffer_publication`及原播放/骨骼发布门；覆盖非 bind reference、零/外推权重、非共轴 unit-weight 恒等、最短半球、scale、非法数值与首次失败/旧几何保留/恢复。眼部 auxiliary、脚本 seek 和最终合成差异归现役断点队列。


### 3.3 骨骼透明度动画

目标是让含逐骨骼 alpha 轨道的 Puppet 动画进入真实合成，修复新版 MDLA reader 将 present flag 当全零字段的问题。官方 2.2 更新日志公开了 bone alpha animation；固定 2.8.0.42 客户端同帧原始/全零/全一控制的骨骼矩阵相同，全零隐藏、全一显示，全骨骼 0.5 显示半透明，排除运行时重复累乘 parent alpha。先行设计已实施；固定输入、官方观察与产品验证见[运行证据](runtime-evidence-current.md#e-2026-10-07-puppet-bone-alpha)。

- reader 按版本边界读取并保留 `boneCount × (frameCount+1)` alpha，缺省为 1；保留 exact length、有限范围和 block end 验证。现代逐骨骼块与后续 keyed auxiliary 分开，不按样本或字段值猜块边界。
- 沿现有 FrameSample 与 prepared clip 采样 alpha；静态判断包含 alpha 变化。先闭合单 clip，按 `1+(sampleAlpha-1)*blend` 加权并限于合法 coverage，再用已准备的四骨骼归一化权重求顶点覆盖率，不再乘 parent。全一轨道无贡献，多 clip 非一 alpha 冲突在未有区分证据前明确拒绝该组合，不吞掉 consequential data。
- PlaybackState 在成功姿态与 alpha 都完成后发布同一顶点帧；首帧失败不绘制、后续失败保留旧完整几何。共享 image vertex 增加默认 1 的 coverage，所有同 ABI 消费者同步；普通和颜色混合两条既有 compositor 路径均对 premultiplied RGBA 同乘 coverage，不改变 effect graph、clock、layer alpha 或输出 owner。
- 验收包括现代/旧版格式、截断/畸形反例、纯 alpha 动画、混合骨骼权重、隐藏/恢复和真实 Metal RGBA；Debug build 与原始聚光灯隔离运行确认动画进入实际绘制。眼睛挂点重叠、遮罩和脚本 seek 独立核验，不将 parser 成功算作整样本正确。

## 4. 3D Models 官方页面覆盖（8）

现役direct static-model子集已经把bounded MDLV0023单mesh从资源关系推进到真实GPU执行，但仍不是完整3D runtime。它只接受format15/u16、一个material pass与straight albedo，使用作者layer transform、scene perspective override、reverse-Z self-depth和按当前作者顺序总计最多4个directional/point/spot diffuse light；同几何、同位置、尺度差不超过2%的近重合材质外壳按结构取得独立depth lease，避免破坏普通模型互相遮挡。官方 stock model shader 与任意 Workshop custom shader 是两类能力：本节只记录官方页面公开的 Fur、Vegetation、Chroma material 行为，不把它们写成 custom shader，也不推测其私有 shader source、参数序列化或数值算法。

| 官方页面 | 分类 | 官方合同与分类边界 | 当前等级 / 最小升级门 |
|---|---|---|---|
| <a id="op-model-introduction"></a>[Introduction](https://docs.wallpaperengine.io/en/scene/models/introduction.html) | `runtime-required` + `editor-import` | FBX 支持 model/animation/texture，OBJ 只适合基础静态模型；2D/3D Scene 都能放 model，但 camera/perspective/editor mode 不同。导入约定为 `-Z` forward、`+Y` up，scale 会尝试 normalize；material 可有 albedo、normal（X/Y flip）、metallic、roughness、reflection、emissive（红通道）、tint mask、rim/toon。 | `L3 bounded`：已执行一个MDLV0023 format15/u16或u32单mesh、single-pass straight-albedo子集并有malformed/index/ABI反门；node/multi-mesh、多material channel、完整axis/scene mode与官方golden仍缺。 |
| <a id="op-model-camera"></a>[Camera](https://docs.wallpaperengine.io/en/scene/models/camera.html) | `runtime-required` | asset list 中最底部的 visible camera 生效；可用 visibility/property/script 切 camera。path 可 random/sequential；Single 完成后进入下一 path，Loop/Mirror 不结束。camera path 使用 `Center/Eye/Up` 与 FOV，而非普通 origin/angles/scale。 | `L3 bounded static scene camera / asset camera L0`：无orthographic projection且Eye/Center/Up/FOV/near/far合法时进入唯一shared camera frame，省略layer override继承透视；不等于asset camera，仍需visible-camera selection、Center/Eye/Up interpolation、path queue/modes、live切换和官方golden。 |
| <a id="op-model-animation"></a>[Animation](https://docs.wallpaperengine.io/en/scene/models/animation.html) | `runtime-required` + `editor-import` | imported animation 可按 start/end frame 切 clips并设 frame offset；额外 FBX 必须与 base 共用相同 bone hierarchy。Motion root 可把 clip 位移应用到 model，长时间循环可能 drift。 | `L0`：无 skeleton/clip evaluator；需 clip/hierarchy validation、offset/loop/rate、root motion accumulation/reset、mix 与 SceneScript bridge。 |
| <a id="op-model-attachment"></a>[Attachment](https://docs.wallpaperengine.io/en/scene/models/attachment.html) | `runtime-required` | named attachment 绑定 model bone，并带 local origin；作为 model child 的任意 asset 跟随 model animation/movement。 | `L0`：无 model attachment；需 bone-local/world matrix、child order、missing bone、animation follow 和 teardown 门。 |
| <a id="op-model-fog"></a>[Fog](https://docs.wallpaperengine.io/en/scene/models/fog.html) | `runtime-required` | distance fog 相对 camera，用 start/end distance 与 start/end density；height fog 相对 scene global height 0，用同类参数；二者可同时启用，material 可 opt out。具体插值/颜色空间未公开。 | `L3 bounded distance only`：有限完整 distance 字段进入 IR→frame lighting→static-model Metal，按当前 camera 的径向距离做 bounded linear density/color mix，禁用/非法参数局部无雾 fallback。该插值为本项目有界实现，不是官方算法证明。`3477054430`远城恢复距离衰减；height/simultaneous、per-material opt-out、live fog user property、精确颜色空间及 Windows pixel golden 仍开放，见[样本证据](scene-sample-debug-ledger.md#e-347-distance-fog)。 |
| <a id="op-model-lighting"></a>[Lighting](https://docs.wallpaperengine.io/en/scene/models/lighting.html) | `runtime-required` | model 与 light 两侧分别控制 shadow；官方页面列出 point/spot/directional shadow。Volumetric 只对 point/spot，Bloom/Ultra HDR 可增强但不是启用前提；官方明确 volumetric 昂贵。 | `L3 bounded direct diffuse / overall lighting L0`：scene ambient/skylight与按当前作者顺序总计最多4个directional/point/spot进入同一direct-model consumer；point/spot只具项目有界radial diffuse，仍无shadow/specular/PBR/volume、per-model/per-light author-off门及官方衰减/像素等价。需shadow map/bias、volume、author-off与性能门。 |
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

**Normal map（表面方向）**：
- 官方公开页面说明 normal map 用于表面深度观感，normal-map generator 属于 editor-only；未规定缺图必须硬拒绝。
- 本项目 normal 未绑定、显式禁用或局部不可用时保留已验证受光链的 flat-normal 分量，不关闭整层受光；这是项目策略，见[2D 材质设计](../roadmap/batch2/2d-lighting-material-design.md#作者-normal-后继2026-10-02-独立设计审查已批准)。作者 normal 的实际开放范围与验证状态见[本批实施证据](../history/d3-authored-normal-input-implementation-2026-10-02.md)。

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

内建 genericimage2/4、作者 LIGHTING gate 的有界 2D diffuse 已进入既有 base material/source capture/compositor 链，见[首片实施证据](../history/d2-d3-bounded-output-implementation-2026-10-02.md)。作者 normal slot1 后继已接入同一资源与 lit consumer；本批编码、逐槽 frame 与局部 flat 的开放范围以[实施证据](../history/d3-authored-normal-input-implementation-2026-10-02.md)为准。standalone lspot 不代验 material interaction，normal 上线也不开放 reflection/PBR、阴影或完整 lighting。后继继续遵守：

1. **硬编码 4 光源上限**：超过时拒绝或明确降级，记录诊断
2. **Author enable gate**：只处理显式启用 lighting 的 image layers
3. **Normal 分量的局部失败**：未绑定、禁用或不可用时沿已声明 flat-normal 保留合法受光输出；normal 候选的 identity/frame/范围错误拒绝该候选，其他 unsafe unit 仍由其原 owner 拒绝
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
| <a id="op-light-introduction"></a>[Introduction](https://docs.wallpaperengine.io/en/scene/lighting/introduction.html) | `runtime-required` | 2D image material 只有作者启用 `Lighting` 或 `Reflection` 才响应；normal map 提供表面方向，metallic、roughness、reflection map/slider 控制反射。Scene ambient/background 参与结果，官方限制每 scene 最多四个 light。normal-map generator 与 mask painting 是 editor-only。 | 有界 2D diffuse 已实施，具体范围见[首片证据](../history/d2-d3-bounded-output-implementation-2026-10-02.md)；作者 normal slot1 已沿既有 catalog/typed frame/lit consumer 接入，编码、逐槽采样和局部 flat 的验收见[normal 实施证据](../history/d3-authored-normal-input-implementation-2026-10-02.md)。slot2 PBR、reflection、shadow、完整材质通道与官方像素等价仍是后继，等级以能力台账为准。 |
| <a id="op-light-lights"></a>[Lights](https://docs.wallpaperengine.io/en/scene/lighting/lights.html) | `runtime-required` | Point 用 radius/intensity；Spot 用 height/direction/inner/outer cone；Tube 用可动画 start/end；Directional 无位置、只按方向覆盖全场。Spot 可投影 image/video/带完整 effects 的 layer；投影 source 在 2D Scene 可隐藏。Origin/intensity 可由 Timeline/SceneScript/audio 驱动，light Z/height 有意义，cursor script 只替换 X/Y 应保留 Z。 | 完整2D lighting仍 `L0`。direct-static model的directional/point/spot已共用有界四灯snapshot和typed intensity；standalone exact volumetric `lspot`仍是`L3 bounded` direct draw，其draw逐帧读取同一typed color/intensity并服从frame visibility，inline SceneScript只允许实际scalar Program与穷尽source evidence共同证明的唯一顶层、小写exact `intensity`。`color/visible`、大小写变体和额外nested source继续失败关闭。有界 surface-local 2D diffuse 与作者 normal 的范围见[材质实施证据](../history/d3-authored-normal-input-implementation-2026-10-02.md)；Tube、完整 projected provider/effect graph、audio/cursor驱动、reflection/PBR、shadow与官方parity仍未闭合。 |

2D lighting、3D lighting、official Scene Bloom/HDR、Workshop layer Bloom 与 exact Workshop image-effect Shadow 是彼此独立的执行链。当前 Workshop layer Bloom approximation 为 `L3`（[E-EFFECT-INLINE](../history/runtime-evidence-index.md#e-effect-inline)），`809b75e` 另执行一个 exact Workshop single-pass Shadow profile；后者不是 light/object shadow map，也没有建立 lighting 或 generic shader。`b856f4ee` 的 standalone volumetric `lspot` 同样只是无 lit-material interaction 的 bounded projector cone（[E-SPOT-LIGHT](../history/runtime-evidence-index.md#e-spot-light)），不升级 generic 2D lighting。official Scene Bloom target identity 为 `L1`；`general.hdr` 自 2026-09-27 起在准备期统一选择 RGBA16Float（否则维持既有 BGRA8）并贯通 graph/source/pair、图片/粒子/模型/光照管线、依赖发布、Bloom 与最终 CAMetalLayer（[颜色精度证据](runtime-evidence-current.md#e-2026-09-27-scene-color-precision)），这是场景精度恢复，tone mapping、EDR、Ultra HDR、per-layer HDR brightness、lighting shadow/reflection runtime 仍为 `L0`。不得用现有 layer Bloom、Workshop Shadow、standalone cone 或 2D compositor 冒充完整 lighting/HDR 系统。

## 6. Shader 与高级 Effect 边界

| 能力 | 等级 | 当前边界 | 权威细表 |
|---|---|---|---|
| effect/material/pass IR | `L2` | 字段可保存并建图 | [Graph/Shader 覆盖表](render-graph-shader-coverage.md) |
| bounded graph executors | `L3` | precise/default Blur与exact Workshop Shadow保留各自现役边界；stock Local Contrast的strict owner已撤销，exact四节点图现由普通MaterialProgram/GraphTargets/GraphExecutor以generic-only执行。首条历史strict链为`3724289844:20`的`Blur Precise -> Shadow`；当前Local Contrast见[E-V1-LOCAL-CONTRAST-SHARED-OWNER](../history/runtime-evidence-index.md#e-v1-local-contrast-shared-owner)，旧[E-EFFECT-LOCAL-CONTRAST](../history/runtime-evidence-index.md#e-effect-local-contrast)只作provenance | [Effect 执行表](effect-execution-coverage.md) |
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
| stop 后 surface teardown | `L3` | 固定矩阵要求 `surface=0`；[E-LIFECYCLE](../history/runtime-evidence-index.md#e-lifecycle) | GPU texture/heap/VM/provider 全资源计数 |
| wallpaper switch lifecycle | `L3` | Host 重建与资源释放有运行门；[E-LIFECYCLE](../history/runtime-evidence-index.md#e-lifecycle) | 反复切换 soak、峰值内存门 |
| screen resize/reconfigure | `L2` | surface 可重建且共享 clock 不重置；embedded video registry 按 launch/device/source 保留连续 provider，过期 source 在 rebuild 后停止 | display hot-plug/Space/scale transition 真实运行门 |
| pause/sleep/lock | `L2` | 统一播放控制已接 Scene clock/frame driver/video provider；纯状态门证明冻结、resume 不补长帧和 provider suspend/resume | focus/fullscreen/sleep/lock 的真实系统事件门，粒子/effect/video 可见连续性 |
| target FPS / refresh-rate driver | `L0` | 固定 60 Hz Timer | per-display refresh、frame pacing、low power |
| quality tiers | `L0` | 无统一 policy | effect/particle/RT 降级必须可诊断 |
| texture resolution policy | `L1` | 有有限 decode/RT budget，但无产品级统一策略 | logical/mapped/physical size、POT padding、mip、memory pressure |
| shared decode/GPU resource reuse | `L1` | 同 Metal device 的 embedded video source 可跨 surface 复用；普通 image/renderer/decode/upload 仍多屏重复 | immutable asset cache + 完整 per-device ownership |
| CPU/GPU/frame-time budget | `L0` | 无长期阈值 | representative matrix + 30 min interaction + 2 h soak |
| memory/VRAM/leak budget | `L0` | 只有部分释放结果 | peak/steady/recovery metrics |
| diagnostics/fail-closed | `L3` | unsupported/resource/graph/runtime 报告存在；[E-LIFECYCLE](../history/runtime-evidence-index.md#e-lifecycle) | 所有新增系统沿用统一 code/count/evidence |

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

[能力依赖图](../architecture/capability-dependency-map.md)继续用于定位共享 owner 和影响面，不是 V5 前的串行阶段门。

## 11. 与唯一现役路线的关系

1. V0 先闭合普通 authored material/shader 到现有 GraphExecutor/compositor 的可见链；任何 Puppet、lighting、3D、RGB 或 offline 完整平台都不是 V0 前置。
2. 本表高级能力归入 V5。只有真实 corpus 价值或用户结果足以提升优先级时，才从该能力的首断点建立一个可回滚纵向切片；不得沿用旧批次编号、样本 ID 排序或“先搭完整平台再出画面”的顺序。
3. 专用 evaluator/simulator/geometry 可以存在，但输入必须来自作者数据和共享 primitive，输出必须回到统一 Program/graph/publication/compositor；不能按完整 effect/object/sample identity 选择固定视觉算法。
4. 未实现的 optional stage 只停用最小对象或 pass；路径、GPU range、handle generation、target/publication 与生命周期破坏仍硬拒绝对应执行单元。
5. 能力升级只同步本表受影响行和实际证据。首个可见切片不以完整结构平台、全 corpus、发行性能或 Windows parity 为前置；若声明完整视觉/发行能力，仍必须补相应数值、像素、teardown、压力与产品门。
