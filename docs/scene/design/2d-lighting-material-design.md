<!-- document-role: active-plan -->
<!-- retirementCondition: 材质受光和各可选光照子能力分别通过合同门并进入稳定架构后归档，未完成 profile 保持明确准入限制。 -->

# D3 — 2D 材质光照、PBR 与阴影

> 复核基线：2026-10-02（首片输入/坐标合同补全），原设计基线：2026-10-01，独立工作树 `93b1b85a`。本文是设计裁决，不是当前能力或运行验收；已合入 `codex/engine-refactor-program`；实施时按其最新代码重新核对所列 owner，除明确标注后继基线的段落外，行号仍指向原设计基线。`approved` 仅表示本设计完成，阶段性 unknown 仍受本文准入门约束。

## 目标合同与设计判据

只有作者启用 lighting/reflection 的 image material 接收光照；plain image 不因场景存在灯光而改变。lpoint/lspot/ltube 的动态状态由统一 light snapshot 传至材质 producer，再进入既有 effect/geometry/compositor。跨 material frontend、光照、资源与 graph，须先定义唯一 light/material 权威。

五判据：横切多个 owner 或主链节点=是；触碰唯一权威合同=是；用户可见且难逆的 API/数据/发布合同=否；触碰机器冻结结构家族=是；依赖官方或平台外部证据=是。

## 当前事实与证据

- `docs/scene/semantics/coverage-ledger.md:1289` 将 2D PBR maps 列为 L0，`:1290` 区分 standalone lspot 与 material interaction，`:1292` 将通用 shadow/reflection/light volume 列为 L0。
- `MyWallpaperX/Core/SteamWorkshopScene/Rendering/Lighting/SceneLightSnapshot.swift:5` 已定义共享 snapshot；`:6` 上限为四灯，`:31` 已含 directional/point/spot；`:68` 读取 typed dynamic intensity，`:121` 从作者执行顺序筛选灯。
- 交接的 `E-2026-09-28-POINT-LIGHT-ROI` 在此基线未找到，不能据此声称当前 2D 材质已受光；既有静态模型 consumer 与此设计分开验收。
- [官方 Lighting & Reflections](https://docs.wallpaperengine.io/en/scene/lighting/introduction.html) 公开规定 image material 的启用开关及 normal/metallic/roughness 等映射方向（2026-10-01 复核），不提供私有 shading 算法。

2026-10-02 首片补证的来源边界：

- `official-public-contract`：再次读取上述官方页面，材料开关决定 receiver、normal map 提供深度观感、light 数量最多四个。页面未规定缺 normal 必須硬拒绝，也未公开序列化键或 shading 数学；flat-normal fallback 是本设计的项目策略，不能写成官方像素结论。
- `authored-corpus-observation`：只读合法 Scene 包中的 JSON，`2815826216/materials/98367037_p5.json` 为 `genericimage2 + LIGHTING=1`、单 albedo；`3662790108/materials/sun-4.json`、同包 `sun-1.json` 与 `3437487219/materials/Universe.json` 为 `genericimage4 + LIGHTING=1`。启用键位于 material pass，不能只检查 `objects[].instance`；本轮未读取任何私有 shader/算法。以上证明作者数据可达性，不证明 PBR 或官方显示结果。
- `MyWallpaperX-strategy`：首片采用世界空间距离衰减、法线与入射方向夹角及 spot 锥体权重的有界漫反射，保留 albedo、环境光、光色和强度各自的职责，仅为独立项目实现；reflection/PBR/emissive/shadow/ltube 保持后继 profile。只有灯位置的真实 Z 参与 N·L，不能用固定抬升常量掩盖坐标问题。共享 snapshot 保留作者明确 black ambient，纠正原 `SceneLightSnapshot.make` 在无灯时将显式 zero 升成 white 的产生者错误；ambient/skylight 均缺省时保留既有兼容默认，3D 默认规则尚未取证，不因本片扩大解释。`LIGHTING=0` 图层仍使用原 unlit producer。

## owner

Compilation/Material 与 ShaderFrontend 归一化 authored material feature 和 slots；Resources 沿唯一 texture/publication 提供颜色或 data；SceneLightSnapshot 是帧灯光唯一输入；image material producer 消费它。阴影/反射仅是既有 graph 的资源与 pass。`SceneLitMaterial`、`SceneShadowMap`、`SceneLightVolume` 不代表新增 renderer。

## 方案设计与选型

选择**forward material lighting + graph shadow target**。全屏后处理光照缺少每材质法线与接收开关；另建 deferred renderer 会扩大 G-buffer 与透明排序职责，第一阶段不采用。屏幕空间阴影不能表达离屏投影者，不能作为通用阴影默认。

1. prepare 为 material 建立 bounded feature profile：lighting enabled、reflection enabled、normal、roughness、metalness、emissive 与可用遮挡数据。首片由 `passes[].combos.LIGHTING == 1` 的内建 `genericimage2/4` 材质默认值启用，layer instance 同键显式值覆盖；内建身份与 ShaderContract 的 source 分类共享 owner。自定义 authored shader 沿既有 frontend 执行，不叠加内置光照，多 pass/未知 tier 不猜测。slot 存在不自动启用功能。
2. albedo/emissive 使用明确颜色解码；normal/roughness/metalness 为 data，禁止 sRGB decode。缺省 normal 使用项目平面法线；其余缺省值仅在公开声明/合法 authored 数据可确定时开放，不猜私有打包通道。
3. 光照在 base material producer 完成、layer effects 之前执行。graph claim 使用其 source capture；无 effects 的普通 receiver 使用同一材质 fragment，经现役 compositor 的 offscreen source capture/target 再进入唯一最终合成，不建立假 effect 或第二 graph。世界位置按 unit quad 的上方对应纹理首行约定与完整 model matrix 计算；世界距离/spot 锥角不随矩形尺寸、旋转或非均匀 scale 扭曲，法线用同帧逆转置 basis。缺 map 与中性 map 均计算同一 N·L，不添加虚构 z lift；首片的 stock normal 限制由下节“作者 normal 后继”接替；其当前开放范围与终审状态见[作者 normal 实施证据](../../history/scene/d3-authored-normal-input-implementation-2026-10-02.md)。typed light snapshot 由 renderer 每帧只发布一次，所有 consumer 使用同一份；lit PSO 在 launch preparation 完成，普通帧只读。Puppet/mesh 的变形后世界位置不能由 source atlas unit quad 推出，首片对此局部保持 unlit 并报告 `receiver-geometry-unsupported`，退役门为 geometry owner 提供同帧变形后 receiver mapping。结果仍保留原 alpha/几何，HDR 接 [D2](hdr-tonemap-edr-design.md)。不把 standalone 可见光束当受光证据。
4. 首片为已有 point/spot 的无阴影受光。ltube 必须先补公开/自有行为 profile，不能伪装成一个 point；灯数量沿既有预算，超额灯的选择遵守作者顺序并记录 bounded 限制。
5. 阴影采用显式 caster/receiver 与 graph-owned depth/visibility target。首个阴影 profile 限一个 spot shadow、一个不超过 2048×2048 的 depth target，实际字节按格式计入现役 resident budget；point 全向和 ltube 阴影暂不开放，不把一张平面图伪装成全向遮挡。这些是项目实施预算，不是官方上限，prepare 时验证峰值并允许按用户质量选更低分辨率；没有可证明的深度/遮挡输入时关闭该 material 的 shadow 分量，不从图片颜色推断高度。
6. Reflection 与 light volume 分为后继独立 profile：前者复用 graph/camera/target，后者仍由现役独立几何绘制但可消费相同遮挡 publication；两者不由受光上线自动准入。

## 作者 normal 后继（2026-10-02 独立设计审查已批准）

**目标与依据。** 固定builtin genericimage2/4的作者normal进入既有资源与受光链，plain image不因场景有灯而改变；不复制参考算法。[中性交接](../../history/scene/d3-normal-input-neutral-contract-2026-10-02.md)确认零基slot1为normal、slot2为PBR、NORMALMAP表示presence且声明无default。官方未公开的通道/方向数学不成为停工前置：下述方向处理是独立项目策略，须有自有反例，不宣称官方像素一致。五判据①跨prepare/load/frame/Metal、②资源/发布唯一权威、④ABI与冻结家族、⑤作者语义外证命中。

**实施前事实（ced0d1ff基线）。** `Compilation/Material/SceneBaseMaterialLightingProfile.swift:33–38`只在所有槽扫描stock路径，可能误收slot2并丢弃material的normal；`Resources/Assets/SceneStockTextureSemanticRegistry.swift:29–41`仅登记一个normal路径。`Runtime/Session/SceneDesktopWallpaperHost+Launch.swift:482–496`先用graph assetDemands造catalog、后编lighting profile，无effects的base normal不能独立贡献需求。`Rendering/Frame/SceneResolvedMaterialFramePreflight+LitCapture.swift:62–66`把registry resource降为裸texture；`Rendering/Composition/SceneLitImageLayer.metal:130–141`只读RGB并用裸local UV。这些是源码反例，实际修前App另验，不能将静态结论冒充运行证据；本段路径均以 `MyWallpaperX/Core/SteamWorkshopScene/` 为前缀。

**输入与owner。** 现base material profile/compiler负责fixed builtin slot1和最终LIGHTING选择；NORMALMAP显式0关闭normal，缺省则由非空作者slot1产生presence，1但缺图不虚构default。instance非空同槽值覆盖material，null/省略继承material是本项目依据第三方职责采用的有界策略，不宣称官方reset语义；显式关闭用最终NORMALMAP=0。slot2绝不因路径名或已登记stock用途转为normal；custom shader继续由现schema解释，不能额外叠加builtin受光。无receiver consumer不预载normal。

准备在唯一catalog创建前汇总 `.asset(path, purpose: .normal)`，同路径颜色/normal保持不同purpose identity。复用现loader、cache、FrameProvider与registry，不建normal专用资源表。每帧consumer保留candidate的purpose、generation、physical/mapped、UV/frame与sampling；既有slot binding/纹理解析API优先复用，不能再次退化为裸texture而丢掉其余身份。plain与effects两路共享现lit producer。

**独立方向与采样策略。** 初始sample合同如下，解释只由现lit方向处理owner完成；loader保留原通道，不重复补全。编码来自typed candidate的实际pixelFormat与normal用途，不能凭路径或format5枚举名猜测。

| 实际存储 | 本项目方向合同 |
|---|---|
| RGBA8 UNORM及现有BC1/2/3 RGB UNORM | 三个采样通道还原有符号方向，保留完整XYZ后归一化，不重建Z；BC采样须与现loader一致。 |
| RG8 UNORM | 无符号RG还原有符号XY，补成面向层正法线半空间的方向，再归一化。 |
| 当前loader的BC5 RG SNORM | 直接使用Metal已给出的有符号XY，不能再次做UNORM的值域转换；其余半空间合同同RG8。 |

XY超出单位圆时，方向落在正半球赤道并归一化，缺失Z取零。RGB过滤后恰为零方向时取flat方向：真实产生者是相反编码方向的线性采样抵消，须自写反例，不能产生NaN。局部+X/+Y沿现有normal basis，RG与RGB方向约定相同；这是独立项目选择，非官方Y/packing裁决。初始格式之外的合法存储只使normal分量flat并说明原因，不把R8、浮点或signed RGB混入UNORM分支。中性oracle优先使用可准确表示的BC5零XY及独立CPU参考，不能为测试新增无人产品消费者的float-normal入口。BC5自写块先验证实际loader pixelFormat与负/零/正采样，再把受光ROI计为方向证明。


每槽采自己的完整frame（origin及两轴）和sampler，不能借albedo atlas区域；现axisAlignedUVScale要求零origin，不可拿它直接准入非零origin帧。沿既有逻辑UV/addressing约定后应用该槽完整变换一次，不能再叠加mapped/physical缩放；先覆盖现loader已支持的plain与axis-aligned frame，不新造sprite clock。可由现FrameProvider发布的下一帧候选进入同一registry，consumer应消费当帧metadata，不能仅以texture对象不变跳过frame变化。unsupported旋转打包、额外动态provider合同或reset保持明确边界；不因为这些未知而拒绝所有普通作者normal。每帧只消费prepared profile与typed frame，不重新解析或编译。

**法线空间纠正（v1反例，独立补充审查已批准）。** 实际App中含非零Z的相反倾斜RGB法线只产生102/98灰值，effect后为51/49；不能用这一弱差异作为目标通过。当前 `Rendering/Frame/SceneMetalRenderer+LayerTransforms.swift:17–23,48–52` 把固有renderSize加入unitquad位置model，而 `Rendering/Metal/SceneLitImageLayerPipeline.swift` 对完整位置model取normal basis，将64像素尺寸错误当作材质方向的作者缩放。位置仍使用完整model，表面方向必须使用同帧作者world linear transform与既有image-card Y朝向，排除固有renderSize、pivot、projection与parallax平移；保留作者及父层的rotation、reflection、nonuniform scale。这是项目独立方向合同，不宣称官方算法。

现 `SceneMetalRenderer` plain caller复用frameWorldFrames，现 `SceneResolvedMaterialFramePreflight` graph caller复用已验证的worldFramesByLayerID；共同 `makeLitCapturePayload` 接收该world和usesPerspective，沿现 `SceneCameraProjection.imageCardYDirection` 构造方向transform，`packLights` 分别消费位置model与方向transform。不得从完整model列长猜测固有尺寸、重新解层级或另造transform owner；无需新增helper或修改LayerTransforms位置行为。两个caller因此纳入本窄片owned范围。完整normal变换奇异/非法仍沿原受光payload失败，不能吞掉作者scale问题。

纠正门在最终候选上增加：非零Z的倾斜法线、固定world取样点而改变32/64/128及长方形固有尺寸时方向不变；单独改变作者/父层scale、旋转、镜像时按独立方向oracle变化。plain与effect实际App都需强区分正反方向，保留原弱v1反例；不得以纯X或Z近零fixture掩盖压扁，也不得把CPU重复完整model逆变换当正确性oracle。两路world与frame身份继续来自原owner。

**备选与选型。** 拒绝只加stock路径、只改slot选取而不汇总demand、所有map共用albedo UV、loader与shader双重方向补全、另开normal registry。选择沿当前profile→catalog→registry→lit producer补缺失边，编码解释和空间变换分别由资源数据/现有normal basis拥有。RGB与两通道都以自写方向门决定是否达到本片交付，不能把方法未知直接登记为永久不支持；若具体格式实验失败，记录实际首断点并修复同一owner。

**失败合同与产生者。** 合法可选normal缺文件时catalog给absent，decode/upload失败给unavailable；lit仅退回已有flat分量，保留albedo/effects/邻层。现generic resolver的optionalVisualReference不含normal，不能把它直接当required slot复用并扩大失败半径。normal purpose/content/identity/epoch/frame/range或hazard错误的最小unsafe unit明确为该normal候选：拒绝且绝不绑定或借旧normal，保留typed invalid-normal诊断；若albedo、geometry、light、frame与target各自已合法，则继续构造无normal的有效flat-lit payload。无绑定/禁用、普通absent/unavailable/合法但未支持编码、invalid normal三类结果分别记录，后两者都不可误走现.miss分支而变成unlit。两个caller仍消费有效.payload，现.miss只保留整个lit producer不可用时的既有unlit降级。非法的是albedo/target/light或全帧epoch时沿原owner拒对应unsafe unit，不能用normal-flat掩盖。最终encode由现 `SceneOffscreenEffectRenderer+Capture` 与 `SceneGraphResourcePassEncoder` 消费同一payload；target/albedo本身非法仍按原合同拒绝，只有normal候选不兼容时去掉该绑定并继续flat-lit，不以整payload布尔失败误退unlit。此检查由现payload/encoder拥有，故障注入须区别于catalog自然可达输入。验证沿现profile→catalog request identity、FrameProvider/registry publication、slot/frame adapter及encode时target检查，不复制private resolver helper或重复校验；每个新增guard须指名上述真实producer。未证明normal格式或非支持geometry的视觉miss不伪装成identity错误。预算仍由唯一cache/residency承担。

**纠正门。** 修前证明普通slot1未加载/未改变输出、slot2不会被误认、instance只改albedo不丢normal；离散binding/purpose必须exact。自写RGBA、RG8与可控BC5方向块，以左右及上下灯位、neutral/缺图、旋转90度/非均匀scale区分通道解释；错误sRGB输入必须被差分分辨。中性图量化误差在运行前冻结（精确方向另用可准确表示输入作oracle），不得失败后放宽。LIGHTING=0逐像素不变；NORMALMAP=0、缺失/损坏normal仅flat且健康邻层继续；同路径兼作color/data验证purpose不串用。albedo与normal不同区域/尺寸、normal独立frame及下一帧方向变化验证metadata被实际消费；plain与带effect两路均到唯一terminal，记录输入/App、完成/发布/terminal/next-frame及ROI。已有三包无slot1正例，不冒称真实样本受益；自写门与新增找到的合法正样本分别登记。

**退役。** 本片通过实际反例、真实App/资源门及独立终审后，input/purpose/frame/方向解释由现有稳定owner接管并删除窄登记；PBR、阴影、reflection、官方Y/packing/atlas parity与reset仍各自后继，不能因normal上线宣布D3完整完成。

## F2 — 普通instance底图选择纠正（独立设计审查已批准）

实际App纠正门及独立产品终审已完成，见[执行记录](../../history/scene/d3-instance-base-texture-implementation-2026-10-02.md)。稳定职责移交架构，临时F2登记同批退役；以下保留设计边界，不扩大为动态instance能力。

**目标/已有合同。** 落实上文已有的同槽覆盖和“instance只改albedo不丢normal”：同model的两个图层可以分别选择自己的静态slot0，normal仍按slot1独立继承，plain及effects实际消费相同的选中来源。本片修真实底图身份，不增加provider、loader或运行时instance mutation能力。

**当前事实与反例（a32e814f）。** `Format/SceneDocumentObject.swift:8–59`已保存instance的静态槽和typed user输入；`Runtime/Frame/SceneRenderDescriptor.swift:131–139`尚未投影实例底图，`Resources/Textures/SceneTexturePathResolver.swift:41–53`只按imagePath→model→material首pass选纹理。准备期`Runtime/Session/ScenePreparedDeviceResources.swift:128`与安装期`Rendering/Frame/SceneMetalView.swift:257`复用这个resolver，故都选错源。以上路径以`MyWallpaperX/Core/SteamWorkshopScene/`为前缀。已冻结[真实反例](../../history/scene/d3-pbr-scalar-implementation-2026-10-02.md#补强测试发现的普通实例底图漏接)：请求灰64的instance图却加载原灰128，保留BC5法线后的ROI36.55，而独立预期21.37979±2。失去normal另为37.19426，不能改容差混过。

**owner与选择。** 在现Layer保留一个可向后解码的optional prepared静态slot0路径，由现descriptor builder在load/generation从typed instance投影一次；现SceneTexturePathResolver(for:layer)为准备、安装和相关base loader提供同一选择。保持既有imagePath入口前提，modelPath-only resolver继续服务原model/dynamic资源用途，不附着任意图层的instance。不得修改共享materialPasses/model link、逐帧读raw或重建asset需求扫描。

合法instance的非空静态slot0覆盖该图层的material默认；null/省略/已归一化空值继承material。没有typed user输入（usertextures省略、合法空数组或userTextureInputs全nil）仍是静态选择；nil仅复用现parser对NSNull/空字符串的投影，不能另按value.isEmpty把非nil的property声明当空项。任何非nil typed user/system/property/path/unknown输入留给已有provider准入，本片不重定义其fallback匹配与失败路。非法集合形状沿原Format记录，不因为新增静态字段获得准入。没有slot0覆盖时完全走现model默认；旧descriptor缺新optional字段等价于无覆盖。未知作者reset和动态instance改写不从此静态投影推出。

选中的resource URL/sourceKey、纹理pixel/mapped extent、采样与动画FrameProvider metadata必须来自同一来源，不可仅换MTLTexture而借旧material尺寸/UV。作者显式size或model声明尺寸仍由原几何owner决定，不能将换纹理误作作者几何重设。既有动态image provider的合法publication仍在frame assembly覆盖初始base；共享model-keyed动态资源准备保持原义，没有第二套动态选择。

**备选/失败。** 拒绝在provider compiler、最后draw或共享material表里插入静态特例：分别会混淆provider权威、导致准备/安装身份不一致或串扰同model图层。选择既有descriptor→resolver链。显式非空来源一旦选中，文件缺失/解码失败遵从原base loader最小layer/source失败，不退回另一张material图假装成功；路径逃逸交原VFS拒绝。合法无覆盖才继承默认。后续unsafe range/ABI/target/publication仍原owner负责。本片不新增格式或专用占位资源。

**纠正门。** 复用冻结source-v2的真实红与test-v3，不重复制造弱同图门。真实descriptor/resolver验证同model两层不同slot0、共享pass未改、null/empty继承、全null user与有provider区分、旧descriptor解码、missing/escape无二次选源。实际App在同一身份验证灰64+继承BC5、normal关闭负控、非identity effect、同model无override邻层和后帧；非方形/不同尺寸源区分纹理metadata与作者尺寸。动画资源验证选中源的FrameProvider/UV更新，dynamic/provider邻接门验证已发布动态源优先级及model-only解析未变。source/App/input、completion、publication/terminal与ROI各有相称证据；只读选择测试不冒充实际显示。

**判据/退役。** 五判据1/2/4命中（prepared descriptor、base资源唯一选择、序列化/机器验证家族），3/5不新增：采用已有D3静态同槽合同，不裁新官方reset/私有算法。design-gate在本节独立批准前阻止上述三产品路径实施。真实红→绿、资源/邻层门及独立终审完成后移交稳定架构的base来源职责，同批删除窄登记；D3 PBR后继保持active。

## RF10 — slot2 直射材质响应（标量切片按独立审查意见修订后批准；贴图补证并行）

**目标。** 普通2D builtin genericimage2/4中已明确作者输入的材质分量，在既有point/spot灯下产生可区分的金属度、粗糙度响应；与normal、作者transform及同帧view共同决定高光，随后沿原effect和唯一terminal显示。无需还原官方私有算法。本片不是环境反射、完整PBR或官方parity。

**当前事实。** 1548aad4基线，`Compilation/Material/SceneBaseMaterialLightingProfile.swift:36–63`只消费LIGHTING/NORMALMAP/slot1；`Runtime/Session/SceneDesktopWallpaperHost+Launch.swift:482–493`只为normal补充资源需求；`Rendering/Composition/SceneLitImageLayer.metal:28–58`没有PBR/view输入，现输出只漫反射。`Format/SceneDocumentObject.swift:8–65`只投影instance纹理/combo，scalar仍在loss-preserving原始值中。以上以`MyWallpaperX/Core/SteamWorkshopScene/`为前缀。五判据1/2/4/5命中，3否。

**作者输入与准入。** [中性v1](../../history/scene/d3-pbr-input-neutral-contract-2026-10-02.md)已独立审查（SHA-256 `94e2dfaee39c7206484dd86e2fe4fe25ec8dda2c885f01a07bf4bafa1be49480`），确定material key `metallic`/`roughness`及genericimage2默认0.5/0.5、genericimage4默认0/0.7；声明editor range均为0…1。公开合同规定map空时使用对应slider。本片对有限超range值选择夹至材质物理域、非法/非finite分量局部回该tier默认，这是项目策略，不把editor range当官方播放器限制。零值不能当缺省。Format复用现ShaderValue解析；静态instance同键覆盖material、未提供键继承material，明确值最终来自现属性解析投影。null/reset与后续动态更改不冒称官方规范，不在帧里读raw JSON。只新增实际消费的两个标量，不顺带解析未来reflection/emissive字段。 支持的启动时用户属性值由现typed解析/失效owner提供：`SceneUserPropertyResolver`在实际写入有效用户值，或对合法无条件引用明确保留作者fallback时，通过既有`SceneUserPropertyResolution`发布该路径的typed启动值结果，再按原scene/object/instance路径传至对应scalar。后者不增加原resolvedBindingCount；合法作者fallback由原owner保留，不能二次改成tier默认。缺失/非法fallback仍局部分量回tier默认。不能靠user字段是否消失、数值是否变化或无diagnostic反推解析成功。material catalog未经该resolver处理的wrapper以及非法user形状不因此获准；未解析的连续script/Timeline wrapper不由本片读取或冻结raw value，局部分量用默认并保持明确unsupported边界，不新增动态属性通路。

| 输入 | 本片直射响应 |
| --- | --- |
| single-pass builtin2/4，effective LIGHTING=1，无slot2 | 使用有效scalar或该tier声明default；不要求显式scalar或另造PBR总开关 |
| 同上，REFLECTION为0、1或缺省 | direct合同相同；REFLECTION不是额外AND条件，也不启用环境反射 |
| LIGHTING=0/缺省，即便REFLECTION=1或有map | 不因此启用direct，原unlit/其他owner保留 |
| custom/source-backed、多pass、现不接纳geometry receiver | 保留既有route，不叠加本片 |
| 已请求slot2，但具体分量解码尚未获批准或资源不可用 | 可选map分量局部未生效，仍以有效scalar/default提供有界材质响应；不是把presence改成absent或声称真实贴图已支持 |

**贴图继续补证。** slot2作者组件与presence键已定，尚需component index到stored channel以及map-vs-scalar关系的证据；研究与标量实现并行，未审查前不猜RGBA、不借当前model alpha假证。本片没有复制私有数学；direct微表面响应及fallback是项目自有有界策略，N2没有官方像素实测，不能称官方shader内部gate已证。`reflectivity`、emissive及环境输入在对应合同获证后接入，不能用其editor0…1范围改写合法语料中reflectivity=3。

**owner/生命周期。** Format沿现ShaderValue解析投影静态有效instance值，profile在load/generation归一化feature/constants。贴图后继获批后才贡献其data purpose需求和asset identity；标量片不新增未消费的slot2字段、资源需求或绑定。现normal等资源仍由唯一catalog/cache/FrameProvider/registry加载和发布逐槽candidate。common lit capture逐帧只消费typed prepared material、同帧camera/light和current candidate；slot2使用自己的frame、origin/axes、sampler、generation，不能借用albedo/normal坐标。两条plain/graph capture使用同一payload与fragment；PSO仍prepare-once。没有第二registry、camera、graph、compositor。

**相机与方向。** 接入已有SceneParticleCameraFrame，按现resolvesPerspective判定每层投影。透视从同帧eye与真实world receiver求view；正交沿SceneCameraProjection当前固定朝-Z视图取平行toward-viewer，不受native perspective basis或虚构有限eye干扰。位置继续完整model；normal继续size-free作者world basis；图片固有尺寸不得改变normal方向。相机平移、视场与resize沿当前frame owner更新，普通帧不解析JSON。

**独立方案及备选。** 采用公开microfacet模型的GGX分布、Smith可见性和Schlick角度反射行为，由本项目独立编写；公开理论入口[Filament材质模型](https://google.github.io/filament/main/filament.html#materialsystem/specularbrdf)，不复制源码或私有数学。粗糙度决定高光宽度，金属度改变漫反射份额和镜面颜色；具体作者系数合成由N1/N2约束。选择height-correlated Smith可见性，包含其分母职责，受光余弦只乘一次。既有漫反射没有标准化因子，镜面项在原灯单位中对应校正一次，不能把旧灯强度改成另一套单位。微表面粗糙度下限为0.01，对应感知粗糙度不超过0.1的有限光斑；这是作者零值的项目数值策略，endpoint必须实际验证，不冒称官方。灯距离、强度和spot锥体保留既有owner。本片不改全局颜色政策。介电正对反射率采用项目固定0.04，金属镜面颜色由straight albedo混合；direct漫反射同时按非金属份额和该角度未被反射的能量份额减少，镜面响应单独累加（沿实施前独立方案，不保留纯diffuse的双计能量）；只有作为反射率输入的albedo限制在0…1，原diffuse/ambient的HDR源亮度不因该局部域截断，属于项目HDR扩展而非全链能量守恒声明。ambient保持旧近似，不随金属度压制、不当IBL。背向view或light、eye/light与receiver重合形成零方向时，镜面贡献为零，无法定义半向量时以正对反射率分配可定义的direct漫反射，ambient与normal保留，不拒整层。备选全屏后处理缺材质normal/enable/coverage；另建deferred或PBR框架增加无消费者职责，均不采用。环境资源只在后继有明确typed输入时引入。

**alpha/HDR。** 当前source为premultiplied颜色；材质运算需要straight albedo时在非零coverage下取回，输出再覆盖一次，透明texel输出精确零。tint/作者opacity只施加一次。普通高于1的结果保留至既有D2映射。仅最终含coverage、tint和opacity的非负通道写入值超出RGBA16F有限域时饱和至65504，这是本producer的存储表示域裁决，不是clamp1或新增tonemap；不在乘coverage之前夹裸radiance。零贡献在可能溢出乘法之前成为零，稳定计算须区分正溢出与真正非法值，不能把NaN当亮值。RGBA16F溢出会在既有D2非finite处理变黑，是本裁决的实际风险产生者。独立oracle包含正对最光滑金属、近距离强度30的单灯及四灯、alpha0/0.25/1、零tint/opacity和finite极端强度配低coverage；禁止降低灯强使门变绿。无map builtin的旧纯diffuse由上述有效默认接管；Lighting0/custom/未准入route保留原行为。normal方向、格式、逐槽frame和尺寸独立性测试保留，新亮度须由独立材质oracle解释，不靠放宽容差迁就。

**fallback/route。** 缺失、坏图、不支持的可选slot2不夺取整层或健康邻层输出；按上表使用合法scalar/default，不能因坏map关闭合法normal或整套受光。已拒candidate不绑定GPU，normal继续独立工作。albedo/target/range/hazard、identity与publication破坏仍由原owner拒最小unsafe unit；不因PBR可降级放松。Puppet/变形receiver没有world mapping时保持原局部unlit。新增guard必须逐项指名作者数值、透明texel、资源failure/alias等真实产生者，不重复registry保证。

**纠正门。** 标量片先闭合修前真实App双输入无响应反例、scalar one-variable反例；独立double oracle覆盖倾斜N/L/V、非零Z、roughness峰值和离轴宽度、金属颜色/漫反射份额，区别普通增亮。覆盖禁用、缺省、显式零与instance，以及未知slot2仍用scalar的局部边界；alpha0/partial/1、HDR>1、tint、normal反向与parent非均匀scale；正交平移不造透视高光、透视eye移动真实改变。贴图解码获批后另闭合逐通道、全零map、missing/corrupt、实际FrameProvider同texture换frame/取消重试、slot2独立UV/sampler及color/data用途隔离，不能用标量验收代替。标量片plain与非identity effect经过completion/publication/terminal/next-frame并有健康邻层。测试/App/源码身份先冻结再运行，原失败保留；自有oracle不冒充官方golden。

**退役。** 标量片先完成可见门与独立终审并按职责提交；窄登记在贴图输入/解码后继也闭合、稳定输入/owner移交架构后删除。D3整体登记保留，贴图之后推进明确环境资源的reflection与有合法caster/depth的shadow。未知某个分支只限制该分支，不以缺官方公式停止整个能力。

## fallback / route

按 feature 精确降级：normal map 不可用时可走已声明 flat-normal；可选 shadow/reflection 缺失保留已验证直射与 base material；完整 lighting shader 失败保留安全 unlit base current，并报告局部 miss。非法 GPU range、预算或 stale light/target hard reject 最小 unsafe unit。`prefer-generic` 只选一条 material 输出，完成后 `generic-only`。

## 纠正门

- 同场景同灯：receiver 有响应，未启用 receiver 逐像素保持；移动灯、旋转法线、强度归零/恢复、四灯到超额及不同作者顺序分别检查 ROI。
- 矩形 200×100/80×320、旋转和上下灯位使用独立世界坐标 oracle；缺 map 与中性 map 逐像素相等，正对平面的 -Z spot 必须可执行。无 effects receiver 与 claimed effects receiver 都须从作者 pass 键贯穿最终合成。
- 法线 data 错按 sRGB、光强被应用两次、透明边缘颜色泄漏均须有失败反例。point/spot/ltube 不以一个样本互相代验。
- 阴影测试移动 caster、离屏 caster、无深度、target resize、GPU failure；只影响 shadow 分量且下一帧恢复；reflection/volume 各自另设 ROI。
- 每个 profile 记录输入/执行身份、light snapshot generation、GPU completion、publication、terminal compositor 与 next-frame；官方对照未做时只记项目有界实现。

## 退役条件

稳定架构接管 material/light/target 边界，已开放 profile 验收且旧重复受光路径撤权后归档。设计批准不等于 PBR、shadow、reflection、ltube 已支持。
