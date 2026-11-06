# 模型、Puppet 与光照

<!-- document-role: current-state -->

<a id="models"></a>
## 模型与几何

Direct MDL 与 Puppet 共用 typed 资源、canonical world/camera、材质、GeometryProduct、依赖发布及唯一 compositor；不能以图片 atlas quad 代替无法读取的真实 mesh。

Direct bind 几何沿原 MDL reader、准备资源和 StaticModel draw。不同 part/submesh/material/stream 只在实际 consumer 已接入时执行。模型消费隐藏 effect 的 named 输出时，沿原 dependency plan 取得独立 publication，保真实内容、采样域、pin 和失败半径，不创建第二渲染图。

动态骨骼输出由原 mesh owner 提供按 layer/surface 隔离的有界 vertex slots；index/material 可共享，可写 pose stream 不按 path 共享。color 与 shadow 消费同一 frame binding；编码开始后不能偷偷更换 pose。未准备、lease/encode 失败跳过受影响 draw，不能读取未持有旧 buffer。

源码：[静态模型资源](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/ScenePreparedStaticModelResources.swift)、[DirectModel playback](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Puppet/ScenePuppetPlaybackState+DirectModel.swift)。


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
- **局部投影与层级**：原 MainPass 从同一 rasterClipRows 提供保 Z/W 的投影矩阵，供既有 cone MVP ABI；无 map 直接复用原 VP。图像的平面矩阵不能用来抹掉新 worldFrame 的近远裁剪。该小方法表达原 owner 的 clip 投影概念，避免在灯光或未来几何消费者复制矩阵规则；不新增 map/cache/状态。SourceRoute 仅退役已经接通的 spotLight 整类拒绝，model 仍等其 depth 消费者。RuntimeModel 的原颜色 producer 集合准备实际 volumetric cone 消费，不再依赖另有可见 static model，也不因祖先初始隐藏冻结该 cone 的 producer；实际帧仍沿原 visibility 控制 draw。Session 直接汇合已有 scalar/vector definitions 的 target，不重跑绑定解析或认证。
- **失败半径**：未实现 effect/writer、坏数值及实际矩阵乘积溢出只使该 cone 不供货，健康同组成员、父级与后继按原生命周期继续；GPU 边界只核最终可提交矩阵，不层层重验同一输入。资源、visibility、group clear/target、pin、publication 与 compositor 不新增 owner。native 世界中旧独立负角/忽略 Z、XY 角及 scale 的行为由共享 TRS 替换；不能声称这些旧 root 全像素保持。

验收先用真实 Plan/typed writer/Timeline/world resolver 与 production Metal，核 root/parent、绝对/循环/静态、scalar/vector/多 writer、未消费与错身份反例，真实 ABI、alpha/PMA、near/far 与有限乘积溢出。完整 App 比较同 TRS 普通 container 与局部 group，配字面父90°/scale2方向和边界，防两端共同丢父轴；再核非均匀×自身角的 shear、资源/ID/变量改名、父颜色变换、初始隐藏→开启及开启→隐藏无残影，闭合 cone target→父输入→Program→main/seal/GPU。无组和 viewport map=nil 用同身份基线复用；独立真实作者逐层核实际 cone/model 与终端，只把实际改变的字段/画面列为恢复。自有分组、独立作者及未覆盖范围由[运行证据](runtime-evidence-current.md#spot-light-frame)维护；新消费者需要另一 renderer/clock 或未解体积语义时，回到原职责设计，不扩到 model 或改 fallback。
