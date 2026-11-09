# 模型、Puppet 与光照

<!-- document-role: current-state -->

<a id="models"></a>
## 模型与几何

Direct MDL 与 Puppet 共用 typed 资源、canonical world/camera、材质、GeometryProduct、依赖发布及唯一 compositor；不能以图片 atlas quad 代替无法读取的真实 mesh。

Direct bind 几何沿原 MDL reader、准备资源和 StaticModel draw。不同 part/submesh/material/stream 只在实际 consumer 已接入时执行。

<a id="model-named-albedo"></a>
模型材质的 named albedo 由原 dependency plan 准备。隐藏 raw source 须独立供货，隐藏 effect 可消费同一计划排在前面的 primary named 输出。模型的有效需求沿准备好的图边激活上游，依序发布当帧纹理，沿现有 pin 交给原 StaticModel draw。缺失、循环、未准备或要求作者位背景的输入按原图合同隔离。模型专用供货层因缺直接上游而旁路失败时，沿原 ticket 结束发布，不能把入口颜色供给模型。退休模型入口对合格 effect 上游的整类拒绝，普通帧沿现有颜色、采样域与纹理生命周期。实际颜色、改名、上游退出和独立作者模型见[验证](runtime-evidence-current.md#nested-model-albedo).

动态骨骼输出由原 mesh owner 提供按 layer/surface 隔离的有界 vertex slots；index/material 可共享，可写 pose stream 不按 path 共享。color 与 shadow 消费同一 frame binding；编码开始后不能偷偷更换 pose。未准备、lease/encode 失败跳过受影响 draw，不能读取未持有旧 buffer。

源码：[静态模型资源](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/ScenePreparedStaticModelResources.swift)、[DirectModel playback](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Puppet/ScenePuppetPlaybackState+DirectModel.swift)。

<a id="static-model-screen-reflection"></a>
### 静态模型的屏幕反射

内置 `generic4` 的 `REFLECTION` 可用原 mesh 世界法线、视向和主画布片元位置读取场景反射。材质准备保留本路径实际消费的静态 reflectivity、roughness 与 metallic。采样以屏幕偏移、边界淡出和粗糙度 mip 表达，再按材质视角响应加入 HDR 亮度、雾及覆盖所在的原终端顺序。先接主画布的几何法线和标量材质，法线/分量图、外部反射纹理、绑定值及局部组反射分别保留待证。光照和反射独立，缺反射输入时继续原模型颜色与深度。

反射沿现有 Surface 的 ReflectionFrame 读前一完成的主画布颜色，复用同一 mip 纹理、预算、失效与提交 pin。只有可见且已准备的接收者触发需求。命名颜色仍在原图层位置供货。若当前只有主模型深度域，后到的命名颜色可与已确定可画的反射模型共用这一域。保护既有必需终端及捕获容量后再取得可选 history，部分证明不发布完整模型 draw set。组、深度写粒子、未保留容量的命名供货和命名 shadow 留原容量顺序。首帧、尺寸/代次更换或容量不足只缺本帧反射。

用同一原生帧的反射开关、遮挡与背景控制区核实际模型像素，覆盖同帧上游命名颜色晚供货、首帧和稳定帧。独立样本保原反射消费者与无反射模型。真实作者水滴以固定取景核边缘及尖端，官方开关对照区分材质反射和全屏后处理。


<a id="model-subtree-raster"></a>
## 模型的局部合成

目标是让 composition/project 的实际模型颜色进入原组 source、父 Program 和唯一 compositor，沿原 StaticModel draw 直接承接，不引入 renderer、depth owner、资源、缓存或 GPU ABI。

`authored MDL/material → prepared model/typed frame → shared world/normal/light → nearest MainPass 的 rasterClipProjection(reverseDepthVP) → 原 model color/depth → group source → parent Program/main`。MainPass 只改 clip XY，保原 Z/W；同一 XYW 平面映射的 XY determinant 决定 color raster 的 frontFacing，使镜像组仍按原世界投影选择正反面。VP 与绕序每 layer/pass 只求一次，各 part 复用；不关闭材质 cull，不把 child/world 负缩放当作画布反转。world/normal、camera position、lighting/shadow 继续原世界空间。无局部 map 复用原 VP/CCW。模型和同 pass 的合格 terminal 沿既有按 pass 分域的 reverse-depth target、首清与 lease/pin；不同组不得共享 depth，资源失败局部处理，不用平面 image MVP 改深度。

SourceRoute 不再整类拒绝 model，不追加材质/效果/几何名单。typed snapshot 与当前 visibility 继续决定实际 draw，不创建新的激活状态；只核现已消费的 model tintback producer，未消费材质/光照 writer 仍沿原边界。当前资格含静态初始可见组、已准备 model 自身显隐，以及 composition 父组热显隐和冷 Bool/Script 开启的实际 source、父 Program 与 tintback；child false 保留。冷父自身 visibility 回调和外部图层 setter 分别取证，不由 warm 成功外推其他准备组合，也不以初始 visible 作为播放许可。

父组 visibility 沿原结构需求、RuntimeModel producer 准备、Launch 资源/Program 准备及原消费链收敛：无 layer effect/dependency 的稳定 model leaf 是结构准备需求，替换只接单个 prepared leaf 的例外；实际 leaf 消费仍要求原 GPU Entry。原 mapper 从已解析 property binding 取得潜在 Bool visibility 目标，所需 kind 必须与唯一实际属性 kind 一致，再与 structural vector 目标及原 script layer access 规则共同经过结构准入。准备阶段仅将这些 roots 的 typed visibility 视作 true，复用原 snapshot/visibility memo 取得可被揭示的成员，再沿现有颜色 consumer 分类构造后代 producer；不以 model 全名单构造 VM，不重复编译整套 property program。CandidateCatalog 消费该需求，退出另一处初始 visible 限制。临时准备 snapshot 不发布到 domain 或普通帧，UI 和 Script 共享同一实际 producer；不增加仅 UI 有效的动态 back gate、Launch 需求表或逐帧检查。

必要供货只包括这些 roots 能揭示的成员，后代继续用原 display authority，保 child 和中间组自己的 false；只有其自身也是合法可写 root 时才准备它的未来消费者。祖先 hidden 的合格后代由同一需求供给实际 back owner，不能仅在 UI 拒绝后让 Script 显示旧色。utility 的实际 source/Program 容量仍由原 execution capability、utility plan 和执行者承接；LiveConsumers 复用相同准备事实，hidden 但已准备的 source 仍可 capture，原 local-source 无 effect raster 与合法无输出分支不要求虚构 Program。保既有 cold image/particle、producer 失败的原局部 fallback 和 property transaction，不新建 ready 状态。坏 child 没有 Entry 仍沿原局部跳过，不能要求父组每个 authored child 都有 GPU ID；独立坏 leaf 与其他目标同 property key 的原事务拒绝保持。结构错配、cycle、未支持 utility 和未消费 writer 不借隐藏或 model 放宽；结构准备不等于执行许可。旧 leaf 准入分支及失效全拒断言在替换时退出。

验收用现有原生 App 门的自有 MDL：普通 transform parent 与局部 composition/project 的对应像素，父颜色 Program 和 source→父输入→main/seal/GPU，同组 near/far opaque 与 nonwriting translucent 交叠、独立组 depth、非均匀父 TRS、镜像画布与双负模型的单面正反例及改名，已准备 model 自身和父组 `true → false → true` 不残留、真实 tintback、child false、坏模型/健康 peer。保祖先 hidden 的 Script/UI producer 供货、source 有效但活动 Program 未准备及同 key 独立坏 leaf 的反例，并回归已有 hidden image/particle 准备；准备事实不代替实际 cold 画面资格。沿现有行为门核 pass depth/失败与 root nil-map，不复制渲染算法进测试；独立作者模型核普通路径回归，不称作者 composition 恢复或官方像素一致。若需新状态、重设深度、另一投影/owner 或未知材质语义，回到本设计，不以新白名单掩盖。

<a id="perspective-image-terminal-depth"></a>
### 普通透视贴图的终端深度

原生透视场景明确启用 `general.transparentsorting` 时，先在同一主画布绘制不透明模型，再合成可重排的局部透明图像效果。效果仍使用原 source、graph 与世界投影，终端读共享深度并停写深度，防止空白纹理矩形把后绘的星空挡掉。先接入无外部供货、环境或画布输入的普通透视 image。它不进入 placement 重放，退出用重放能力位跳过该终端状态的分支。关闭排序和其他终端沿各自原路径。

在既有帧顺序内，只重排由合格效果、不透明写深度模型和无绘制项组成的区间。效果按相机深度远到近，同深保作者顺序。实绘但未接入的层、组、供货及画布观察都截断区间。资源准备和实际编码消费同一顺序，命名供货及观察点的位置保持原相对顺序。该范围不接入跨组、透明模型、粒子或依赖当前画布的效果重排。

原 MainPass 的 reverse-depth 域由模型和贴图绘制共享。命名模型颜色尚未发布时，按作者顺序准备已确定的必需深度，推进至第一个主域模型，普通终端可借其中已取得的主域。未准备的模型继续在原作者位置解析颜色，前缀不发布为完整 draw set。Framebuffer source 继续要求完整准备。组、粒子及其他域保原资源优先级，首个实际 encoder 清零，后继读取同一 lease。

普通终端的写深度在实际合成片元上判定覆盖。来源已沿原 straight/PMA 语义、遮罩和透明度形成最终颜色，四通道精确为零的片元退出光栅，不挡住后来图层或模型。极弱覆盖和零 alpha 的非零关联 RGB 保留作者深度策略。仅为现有写深度模式准备同一 fragment 的覆盖变体，读深度、无深度、来源捕获及效果重放沿原管线。无阈值、图层重排或额外深度资源。

验收覆盖透视效果的遮挡区和露出区、明确关闭深度、后绘模型和透明空白区、排序关闭对照、重放邻例、待供货模型、首次清零和容量失败。用同机位的作者地球与关闭 Bloom 的可区分对照，并用原包核对轨道、行星与星轨标签恢复，以及独立世界样本的星空背景和恒星光晕。

<a id="legacy-bind-mesh"></a>
### 旧版 Puppet 的网格与动画

MDLV0013 的 52 字节顶点布局与已有 position/UV bind mesh 消费者相容；沿原 MeshReader 读取真实顶点、UV 与索引，再经原 LayerLoad、GeometryProduct、effect graph 和 compositor 输出。版本描述只选择已知存储布局，不以资源名、样本或摘要许可绘制；不增加第二 importer、资源 owner 或逐帧解析。

网格与动画分别准备：MDLV0013 配对 MDLS0001 的 bind-local 矩阵、父索引与四路权重，以及 MDLA0001 的完整 TRS 轨道、frameCount+1 采样和四字节零尾；沿原 Reader、Selector/Evaluator、AnimationPlaybackRuntime 及 Surface geometry 执行。空骨名保数值骨索引，不伪造名称或重排。无 reference、alpha、event 或 morph 数据时不另建通道；各版本仍消费自己的实际 trailer，不用旧版四字节放宽其他格式。

坏 mesh 保对应 draw 失败；坏权重/rig/clip 由原 LayerLoad 保独立 bind mesh 与明确原因，不发布假动画 metadata 或 atlas quad。验收覆盖原 Reader 的改名/偏移、矩阵/权重、轨道/下一 clip 与截断/错配反例，实际不同 phase 的 pose、动态 geometry 及所选帧最终贡献；纯 bind 正例不代替动画资格，更广旧格式和官方像素一致仍需独立验证。

<a id="puppet"></a>
## Puppet 动画与当前 pose

Reader 保 mesh/rig、weights、clips、TRS、alpha、events、reference 与 auxiliary presence；Selector/Evaluator 决定实际可执行通道。会话 AnimationPlaybackRuntime 唯一持 clip 位置、rate、blend、命令和事件；每屏 Surface 持 pose/physics、骨骼写入和成员。

- 同 cadence 先同步 committed 成员、采样动画，准备 pre-script pose，执行 VM，应用骨骼写入，完成 skinning/attachment 并冻结。暂停、无 drawable 和 GPU retry 只消费该帧。
- 新 rate 保当前 phase 后重锚，不按 `sceneTime × 新rate` 从头计算。已准备的合法参数 Timeline 与 String 条件选择使用原 typed producer，当前坏值不覆盖上一健康播放。
- 一个实际 active 的 non-additive clip 使用其完整 absolute pose 和真实 blend；额外准备的隐藏 clip 不改它的算法。translation/scale 线性插值，rotation 用现 quaternion 最短弧，不能线性插 Euler 导致跨界绕远路。
- additive 与多个 opaque/reference contributor 受现选择和 evaluator 范围限制；bind-equivalent reference 不等于所有独立 reference 都已支持。
- 骨 alpha 是该骨的实际贡献，不沿 parent 重复相乘。DirectModel 的非中性 alpha、未消费 auxiliary/shape 和非空 attachment 仍可触发 typed bind-only 降级；必需 mesh/rig 坏数据不能被当作可选动画缺席。

Surface 退休已销毁成员的 CPU/GPU/clock 引用，重建不复活；准备模板与共享资产保留。Puppet geometry storage 与 paint/PSO 准备分开，出生只读准备结果，不重新读取 paint 或编译 clipping pipeline。

源码：[Selection](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Puppet/ScenePuppetAnimationSelection.swift)、[Evaluator](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Puppet/ScenePuppetAnimationEvaluator.swift)、[Surface 装配](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+SurfacePuppets.swift)。

<a id="puppet-attachments"></a>
### 有序挂点与名称绑定

目标是让子层持续跟随父 Puppet 的实际挂点，保原图层层级、动画与唯一 world/output。MDAT 是有序记录，名称重复不使整表失效；名称绑定选该名称的首条记录，后续同名记录仍保原 ordinal、骨索引与矩阵，不能重排、覆盖首条或伪造名称。现有 Reader 在入口完成结构、骨索引和有限仿射矩阵检查，并用已有名称 Set 的插入结果保存每条记录不可变的 `isNamedBinding`；这是解析事实，不增加缓存、名称 owner 或逐帧去重。

`MDAT → typed attachment records → 原 Catalog/Descriptor 的 bind frame 与 PreparedPuppet 的 live frame → Surface 当前 pose → 原 LayerWorldFrameResolver(parent × attachment × child) → geometry/compositor`。冷、热两个消费者都只采用选中记录；退出 Reader 的重名抛错、Descriptor 对未筛选重名的 unique-key 构造及 live 投影的重名整表拒绝。两张结果表分别属于准备期 bind 与当前 pose，不合并成第二状态源；普通帧不重读 MDL、不重新决定名称。保原 model→Scene 的 Y 共轭：骨姿态和 MDAT 保模型域，父/子 layer 与最终 geometry 的坐标边界共同完成投影，公开作者 API 的相对平移不能单独授权删除反射。

坏结构/骨/矩阵仍沿原资源局部失败与 bind/parent fallback，不能因允许重名而吞掉坏记录。未找到名称继续使用原 fallback；独立健康模型和层不受影响。本批不新增数字挂点 Script API、不改 BoneCatalog 的名称规则、不解其他样本运动幅度，也不迁移矩阵 owner。首条规则的官方依据限定为固定客户端的同名记录、顺序互换及名称/资源改名对照，资格与未覆盖版本归[运行证据](runtime-evidence-current.md#puppet-attachments)。

验收复用真实 Reader/Descriptor/PoseProjection/WorldResolver：唯一名不变、首尾重名保序、交换后跟新首条、改名及等价父子仿射表达式、缺名与坏记录反例；cold bind 和不同动画 phase 的 live 投影采用同一记录，父 TRS 与原 Y 基闭合。再核原作者头部的实际几何与最终画面，以及未参与修复的唯一名挂点作者。若必须改坐标或引入新准备状态，先修订本设计，不能按名字、资源、偏移或截图选择算法。

<a id="clipping"></a>
## 部件裁剪

当前 MDLV0023 已接入有序 draw-part ranges 与 counted target/source ordinal 数组；空 part 保 ordinal。未知 flags、越界、截断或重复 target 拒绝该 mesh，不压缩 part 表或跳坏 record。

原 `ScenePuppetClipping` 在准备期去重 source、排除当前 target/self 与空 part，建立 nested coverage 顺序；cycle 及真实下游局部不可用，独立分量保持。普通帧只准备当前变形后的 coverage，不重读格式/paint 或重建关系。

main/named consumer 分别按实际 extent/MVP、target bounds 和采样密度取得 R8 coverage，保透明边界。opaque source 重叠采用当前 max coverage、paint red 与 nested coverage 相交；source vertex coverage 非一的合并语义未完整资格。target alpha 与裁剪 coverage 在原 mesh 合成中只乘一次，后继普通 draw 关闭裁剪状态。

每个 target 使用自己的 ROI；pose 相同不能授权跨 consumer 复用 mask。R8 lease/pin 由原 pool、预算和 submission 保留；缺 paint、预算或 encoder/ROI 失败只隐藏相关 target/下游，不用无裁剪画面回退。

源码：[Clipping](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/ScenePuppetClipping.swift)。

<a id="lighting"></a>
## 光照、材质与显示

`SceneLightSnapshot` 从当前 topology/world/typed 值准备 point、spot、directional，按当前预算接纳最多四灯；tube 不能伪装为 point。所有 receiver 消费同帧 light/camera，而不是各自解另一份场景。

- 只有实际启用 lighting/reflection 的材质参与对应 producer；plain image 不因场景有灯而自动受光。
- base material 光照在 layer effects 之前完成，graph 捕获该真实 source。albedo/emissive 与 normal/PBR data 分用途读取；normal、radius、锥角与世界距离使用 canonical 坐标，不随 card 非均匀 scale 错变。
- 2D image 与变形后 mesh 的 receiver mapping 不同；不能从 source atlas unit quad 推出 Puppet/模型的世界位置。未支持 receiver 局部保 unlit，并保原 alpha/geometry。
- 模型 directional/spot/point 阴影沿现 typed light、真实 geometry、target 与 submission；可见光束、受光和投影是三种消费者，不能互作证明。
- 现代点光 `lpoint` 的径向项由作者 `exponent` 决定。Format 保留有限非负的显式值，共享 light snapshot 将缺省解析为 2，StaticModel 和 LightingV1 图像消费同一世界距离衰减。平方保乘法，0 在半径内无衰减，半径外沿现有截止。各自现有 GPU 参数末尾追加一个四灯指数向量，保持颜色和强度分立以保浮点动态范围。退出两条现代点光的固定平方，保 legacy `point` 平面距离、spot 与阴影投影。固定官版字段与 stock shader 支持正指数和缺省值，零指数的官版半径外像素仍待核。
- reflection 只在已有 profile 中取得合适的 scene/environment 输入；模型镜面、所有光源/遮挡与图依赖组合仍不完整。
- HDR scene color/Bloom 与终端 SDR/EDR 映射分开；像素 PNG 不能证明显示器实际 EDR 高光。

源码：[LightSnapshot](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Lighting/SceneLightSnapshot.swift)、[2D lit material](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneLitImageLayer.metal)。采样/颜色合同见[Shader/Graph](render-graph-shader-coverage.md#color)。

<a id="limits"></a>
## 当前缺口与最近门

MDLA6 `modernBoundsAuxiliary` 的 framing/presence 被 Reader 保留，但未消费的 scalar/shape 仍由 Selection/Evaluator 拒绝；某个恒定数值不能证明它是深度或绘制顺序。bounds 前的 timed morph 曲线与 MDMP 几何尚无 prepared/evaluator 消费者，不能丢弃曲线后把静态 TRS 视为完整动画。更广 dense/reference composition、多 opaque alpha、Direct attachment/多 part 动画、fractional source clipping、未知 MDL profiles、全部光照/物理/阴影组合仍有边界。

最近行为入口：[bind 几何](../../../script/tests/test_scene_direct_model_bind_geometry.py)、[动画消费者](../../../script/tests/test_scene_direct_model_animation_live_consumers.py)、[裁剪 GPU](../../../script/tests/test_scene_puppet_clipping_render.py)、[普通 effect 受光](../../../script/tests/test_scene_ordinary_effect_lighting.py)。未闭项的下一资格见[队列](../roadmap/scene-open-breakpoint-queue.md)。

<a id="spot-light-frame"></a>
## 可见 SpotLight 的准备与帧消费

可见 volumetric `lspot` 光锥沿共享帧进入普通父层、composition/project 的局部 source 和最终合成。原 light plan、共享 world frame、MainPass 和 cone pipeline 各保原职责；model 的逆深度、一般体积散射及官方精确公式分别取证，不用已有错误实现定义新合同。

- **数据流与退出**：`authored light → 原 Plan 准备有限参数/几何比例 → 同一 typed snapshot 与共享 worldFrame → nearest MainPass 的 clip XY 映射 → 原 cone draw → group source → 父 Program/tail → unique main`。Pipeline 直接消费完整 worldFrame，保父/自身平移、旋转、缩放、镜像及剪切；角度已由共享 Timeline/Script/world resolver 合成，不再从 worldOrigin 与私有 currentAngle 重建。退役 Plan 的 parent/leaf/无依赖许可、baseAngles/currentAngle 和单一 relative-mirror Timeline 形状门；effect 尚无本绘制消费者，保持局部未支持。
- **准备与读口**：Plan 不再按样本数值上限拒绝可消费的 cone。只保 finite/color 域、非负强度/radius/density/exponents、合法内外锥角及实际可表示的派生几何；半角 trig 与不随帧改变的比例在原 Plan 一次准备，帧不重复计算。零强度/半径/密度沿真实消费者得到无贡献。当前 typed TRS/color/intensity/alpha 与外层 visibility 是实际读口；alpha 沿原 normalized reader 进入既有 color uniform 的 A，保持 PMA。Script 源覆盖只在原准备入口核真实 object/field 身份、已实例化 scalar/vector target 与上述消费集，退出单 intensity/count/源码写法许可；未知、nested 或未消费 radius/density 等 writer 不能静默冻结。共享 Timeline 编译器继续拥有各 host/模式的执行边界，不另建光锥时钟或重放。
- **局部投影与层级**：原 MainPass 从同一 rasterClipRows 提供保 Z/W 的投影矩阵，供既有 cone MVP ABI；无 map 直接复用原 VP。图像的平面矩阵不能用来抹掉新 worldFrame 的近远裁剪。该小方法表达原 owner 的 clip 投影概念，避免在灯光或未来几何消费者复制矩阵规则；不新增 map/cache/状态。SourceRoute 退役已接通实际消费者的整类拒绝，模型的独立合同见[局部合成](#model-subtree-raster)。RuntimeModel 的原颜色 producer 集合准备实际 volumetric cone 消费，不再依赖另有可见 static model，也不因祖先初始隐藏冻结该 cone 的 producer；实际帧仍沿原 visibility 控制 draw。Session 直接汇合已有 scalar/vector definitions 的 target，不重跑绑定解析或认证。
- **失败半径**：未实现 effect/writer、坏数值及实际矩阵乘积溢出只使该 cone 不供货，健康同组成员、父级与后继按原生命周期继续；GPU 边界只核最终可提交矩阵，不层层重验同一输入。资源、visibility、group clear/target、pin、publication 与 compositor 不新增 owner。native 世界中旧独立负角/忽略 Z、XY 角及 scale 的行为由共享 TRS 替换；不能声称这些旧 root 全像素保持。

验收先用真实 Plan/typed writer/Timeline/world resolver 与 production Metal，核 root/parent、绝对/循环/静态、scalar/vector/多 writer、未消费与错身份反例，真实 ABI、alpha/PMA、near/far 与有限乘积溢出。完整 App 比较同 TRS 普通 container 与局部 group，配字面父90°/scale2方向和边界，防两端共同丢父轴；再核非均匀×自身角的 shear、资源/ID/变量改名、父颜色变换、初始隐藏→开启及开启→隐藏无残影，闭合 cone target→父输入→Program→main/seal/GPU。无组和 viewport map=nil 用同身份基线复用；独立真实作者逐层核实际 cone/model 与终端，只把实际改变的字段/画面列为恢复。自有分组、独立作者及未覆盖范围由[运行证据](runtime-evidence-current.md#spot-light-frame)维护；新消费者需要另一 renderer/clock 或未解体积语义时，回到原职责设计，不扩到 model 或改 fallback。
