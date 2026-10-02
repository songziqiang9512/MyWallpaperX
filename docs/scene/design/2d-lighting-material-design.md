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

## F3 — slot2材质贴图与静态自发光（独立设计审查已批准）

本片已通过独立产品/实际App/有界真实材料验收，冻结身份及原场景未恢复边界见[执行记录](../../history/scene/d3-pbr-map-emission-implementation-2026-10-02.md)。稳定slot2职责由架构接管，窄登记同批退役；下述设计仍限定开放范围。

基线`3f13619c`。五判据1/2/4/5命中，3不新增；本节已获独立设计审查ACCEPT，按以下九个既有产品owner释放实施；设计批准不等于运行验收。root与实现者均未接收原始静态表达。

### 结果与取舍

一次闭合作者 slot2 普通资产 → 既有 data 资源与逐帧 candidate → 同一 lit producer 的可见结果：已启用的 metallic/roughness 分量改变现有独立 BRDF，已启用的 emissive 分量贡献不依赖场景灯的作者颜色。共用一次 map 采样、现有资源预算、FrameProvider、registry 和最终 compositor。选择 MR 与静态 emissive 同批，因为真实三项 LIGHTING1 材料均是 emissive-only；只做 MR 不能宣称它们受益。两 sun 的 literal/static 输入是本批真实验证目标，Universe 的材料用户属性输入按下述限制报告。

不新增 renderer、PSO、registry、provider、clock、camera 或独立缓存；不接 reflection/环境资源，不改变原 REFLECTION-only 材料 LIGHTING，不扩大 LIGHTING0 emissive。不等待官方私有 BRDF/emissive 公式；数值策略明确属于项目独立实现，官方 native 动态/像素 parity 保持 not-run。

### 输入依据与边界

输入档案见[贴图中性合同增量](../../history/scene/d3-pbr-map-input-neutral-contract-2026-10-02.md)。已独审中性 v6 SHA `09ba8a3a61e8d0277c9681e9c2b8e0ba266c8565a68e2356f7372af984592de4`、v7 SHA `1192938f70c4320cb229583f7a8ea1a15355eb299871e90d1669b41ce197608e`，以及已批准 v3 归档提供：固定 builtin genericimage2/4 零基 slot2 为 PBR masks；component 顺序与 header bits20…23 对应 metallic/roughness/reflection/emissive presence；逻辑采样结果 R/G 分别替代 metallic/roughness 输入，emissive 使用 A 并共同消费 emissivecolor/brightness。v7 只补固定第三方 helper 保持 sample-result 分量，不证明各种物理字节顺序或官方 native backend。项目沿自身已验证的解码器取得 RGBA 采样结果，不手读 payload，不从上述索引反推 raw byte 布局。

首片使用现有 loader 支持的普通静态或既有动画 TEX asset，解码后的 GPU 格式限 `.rgba8Unorm`、`.bc1_rgba`、`.bc2_rgba`、`.bc3_rgba`；每种以真实 loader 自有 RGBA 输入验证。BC1 的已解码 alpha 行为由项目格式验证，不以格式名制造新的 alpha 值。单/双通道、signed normal、浮点或 sRGB GPU 格式本片不当作四通道 map，局部 unsupported；不人为重建缺失分量。PNG/其它普通图可沿现 loader 解析，但无 TEX header 时不能自动产生本片 component presence；显式1也不制造 presence。

`emissivecolor` 为已有 typed 三分量颜色，缺省 white；`emissivebrightness` 为已有 typed 单值，缺省1。有效值须非负且能安全表示为现有 shader 数值；显式0合法。typed输出缺数值、维数错误、负值、非有限或不可表达值只关闭 emission，不关 MR/normal/整层。字段缺省不同于这些显式坏输入，不能将坏输入吞成“已解析默认”。本片不承诺原始词法严格性：当前`Format/SceneDocument.swift:383–453`与`Resources/Assets/SceneAssetCatalog.swift:297–349`的数字串投影会略过不可解析词，数值入口也存在JSON Boolean桥接待核边界；profile不能恢复已丢失的信息，不在帧内重解析raw。真实parser到profile门必须标出这个上限，不用手造ShaderValue冒充作者级拒绝。后继严格化应在这两个准备期producer收敛并验证相邻consumer，不把旧宽松行为确立为目标规范。不以 editor brightness0…10冒称播放器 clamp；合法大于10可进入项目 HDR 边界。

### 准入及 presence 策略（项目保守裁决，非官方 precedence）

仅当前单 pass、已证 explicit genericimage2/4、effective LIGHTING=1 的 image-renderable receiver 准入。保留现 custom/multipass/无world mapping行为。REFLECTION 不成为 direct/emissive AND 条件，也不在本片产生环境响应。

material combos 为 default，静态 instance 同键覆盖；slot2 非空 instance 覆盖、null/省略继承，沿已用第三方职责形成的项目策略，不宣称官方 reset。本片保守按slot2分别检查material和instance：任一包含非nil typed user/system/property/path/unknown输入，则该map为unsupported；静态instance path、instance usertextures空数组或全nil不能清除既有material provider声明。整体PBRMASKS=0优先disabled且不因本片加载该map；无slot2 provider声明时才按静态path覆盖。其它槽provider不阻断本map。该裁决只属于map局部，不复制normal整数组选择，不重定义既有provider或未知reset。源路径在 profile 编译成既有 VFS asset identity，非法路径局部 invalid，不在帧内重解析路径。

三个状态分别保留：声明请求/关闭、header component presence、资源 availability。

| 输入情形 | 本片行为 |
| --- | --- |
| effective `PBRMASKS=0` | 关闭整个 slot2 输入，不加载仅为本片所需的资源，MR仍用scalar，emission为0 |
| 对应 effective `METALLIC_MAP/ROUGHNESS_MAP/EMISSIVE_MAP=0` | 只关闭该分量；不影响其它分量 |
| combo缺省或明确1，且对应真实header bit为1 | 可采用该分量；combo1只是允许，不补造metadata |
| combo1但header bit为0；或headerless asset | 该分量保留scalar/无emission，记录有界冲突或无metadata状态；不用整张图存在替代presence |
| 非0/1显式combo值 | 对应整体/分量局部 unsupported，采用同一保守关闭结果，不猜真值 |
| header仅emissive | metallic/roughness scalar/default完整保留；只可能增加emission |
| reflection bit存在 | 本片不消费B；不能借此制造MR/emission |
| 启用分量的采样值为0 | 0是合法值；MR替代为0、emission贡献0，不能回scalar/default |
| map请求但缺失/损坏/候选拒绝 | availability失败，MR回各自已准备scalar，emission为0；保持声明请求状态而非伪造presence=absent |

显式 combo 与 header 冲突仅拒绝该分量；整体 explicit0 拒绝整个map。即使所有分量后续不可用，仍不得借原图另一个通道补救。

### 自有可见数值行为

每fragment先以 slot2 自己的 logical-UV convention、完整 origin/axes 和 sampler 采样一次。只对准入分量提取已解码 R/G/A：MR直接替代对应已准备scalar，保持现有 GGX/Smith/Schlick、roughness数值下界、相机/normal方向、ambient与灯单位。

Emission采用项目独立策略：有效map调制作者 emissivecolor 与 emissivebrightness，作为与 ambient/direct分开的正辐射贡献一次加入同一结果。该贡献不随 N/L/V、灯数量/强度或是否有灯改变；不额外乘 albedo RGB。保留现 layer RGB tint 作为整层颜色调制，透明覆盖取现 albedo alpha，并与 layer opacity/tint alpha 的既有合成约定一致；最终 alpha与未加emission时完全相同。RGB coverage/opacity只应用一次，不先饱和再覆盖；保留HDR大于1，最终有限rgba16f存储上限遵守现65504约束。这是设计选择而非恢复私有公式。

典型无灯反例：显式黑ambient、zero lights、非零map/color/brightness必须可见；brightness0或该map0必须无emission；只改normal/灯位置不能改变emission项。不能用普通BRDF增亮冒充自发光。有效但很大的有限作者值与很小覆盖组合沿现lit存储算术处理，防止中间overflow/inf乘0；不扩通用数值框架。

### Owner、最小改动范围与普通帧

前缀 `MyWallpaperX/Core/SteamWorkshopScene/`，预计9个原有产品路径：

1. `Compilation/Material/SceneBaseMaterialLightingProfile.swift`：load/generation准备slot2 typed source、effective分量意图、MR fallback、emission值与有效性；presence不等availability。
2. `Runtime/Session/SceneDesktopWallpaperHost+Launch.swift`：把实际可能消费的slot2 `.mask` identity加入同catalog需求Set，与normal/graph需求去重。
3. `Rendering/Frame/SceneResolvedMaterialFramePreflight+LitCapture.swift`：按prepared identity读取current registry状态，产生该帧typed map binding/局部结果，与normal独立。
4. `Rendering/Metal/SceneLitImageLayerPipeline.swift`：同一payload携带map fullUV/sampler/component状态和emission值；同target-aware边界处理可选map；同draw绑定texture2。
5. `Rendering/Composition/SceneLitImageLayer.metal`：一次sample、MR输入选择、一次emission贡献；复用现辐射存储策略。
6. `Rendering/Composition/SceneOffscreenEffectRenderer+Capture.swift`：现plain/source capture传递同payload/map。
7. `Rendering/Graph/SceneGraphResourcePassEncoder.swift`：现graph source capture传递同payload/map。
8. `Format/SceneDocumentObject.swift`：在现typed instance常量投影加入emissivecolor/brightness，按实际维数保留，不读取帧raw。
9. `Format/SceneDocument.swift`：现startupValuePaths provenance按这两个key贯通instance；有效已解析值或原resolver合法保留fallback才有启动成功身份，不能看值是否改变来猜。

不需扩 candidate/loader/registry/FrameProvider：`SceneTextureSampling.rawFlags` 已保留header，animated candidate复制它，publication.sameAtom单独比较rawFlags；physical/mapped/UV/sampler/epoch/purpose同属现candidate。`.mask`为现有load purpose，content为`.data`，source channels保留，无sRGB或alpha预乘。逐帧只有typed状态解析/bitmask选择和uniform打包，不文件IO、JSON解析、编译/建图、完整hash或新增资源缓存。

### 启动属性及真实样本上限

literal material常量已由catalog保留；literal/已解析静态instance值沿上述两Format owner接入。未解析 script/Timeline/user wrapper只关emission并给有界原因，不能将raw fallback冒充已解析默认。

F3未接通Universe的material用户属性：catalog wrapper未经scene-root resolver、compiler仅准staticModel。后继F4沿唯一property Program补齐此producer与同帧consumer，具体范围和优先级以下节为准；不能借公开默认1绕过明确wrapper。

真实验证先选3662790108中的sun-4/sun-1两项：保留原material/scene作者内容，在隔离副本运行，确认header只有emissive、MR scalar/default仍在、literal/defaultemission进入输出。保存原/后源码App/input身份、图层source/组件状态、completion/terminal/nextframe与可辨ROI；其它效果或既有失败单独归因。未改变LIGHTING的两项reflection-only样本不是本批受益对象。官方blackbox未运行；有本机输出不等于官方parity。

### Failure、预算和新增guard的实际producer

- 缺图/坏TEX/loader拒绝：现catalog unavailable。局部MR fallback+无emission，合法normal与健康邻层继续；不重试另一路图。
- 非法path：既有VFS identity拒绝该map；不能扩大到整个scene。
- headerless/冲突/非0或1combos：真实PNG、作者显式0/1/其它Int与TEX flags是producer；在prepared意图/typedmetadata边界裁决，不按像素扫描。
- format/UV/sampler unsupported：真实loader可产出RG/signed/不支持border等形态，继承canonical binding验证和该片格式范围，拒该map。
- stale/identity/purpose/epoch/range：现registry/publication/binding拒绝最小unsafe candidate；不要再加无可达producer的requestidentity/purpose重复检查。
- target别名/foreigndevice：最终target-aware验证拒map，保留安全scalar/normal；若albedo/target自身unsafe，原整层capture拒绝保持。这类map故障门须标API注入，不假称普通asset自然复现。
- 预算：沿现shared decode/resource预算、upload queue、catalog持有与释放；同path同purpose需求Set去重，不建PBR cache。decode-cache预算仅管可重建bytes，拒绝cache准入仍允许合法加载，不能误改为整资源失败；应检查rejection增加而cache resident不增、释放回基线。真正GPU allocation由现SceneResourceBudget/SceneResourceAllocation先reserve，配额不足则不allocate并局部MRfallback/emission0。独立harness可预备target/邻层，再精确预留shared剩余配额，用fresh loader加载未缓存source证明拒绝；defer释放所注入额度，重试成功且最终占用回原基线。该证据是配额账本注入，不称物理OOM或自然内存耗尽。data over-cap不借color resample隐藏失败。
- emission坏常量/wrapper：真实typed ShaderValue/实例作者输入是producer，仅关闭emission，不让默认值掩盖明确错误。

### 纠正门与交付门

**先红。** 用冻结F2 App和自有TEX RGBA+header：保持灯/normal/scalar，其它条件不变，仅改Metallic或Roughness map；另用黑ambient/无灯的emissive-only图证明旧输出无响应。输入、独立预期、原App/test身份先冻结，不能把旧scalar red当map red。

**CPU/typed。** 真实parser/profile/launch需求：两个builtin、LIGHTING0/custom/multipass、各combo0/1/缺省/冲突、单component/全zero/map-onlyemissive/headerless、静态instanceasset和literal常量、null继承、合法startupproof与未解析/非法wrapper、合法0/非法类型/负数/不可表达数。补明确对照：pass slot2 typed user加instance静态path、同例instance usertextures空数组都维持MRfallback/emission0；没有pass provider且instance全nil则静态准入；其它槽provider不阻断slot2。离散purpose/slot/metadata必须exact。只断行为，不源码字符串。

**实际GPU。** 自有RGBA8及BC1/2/3解码channel blocks，R/G/A单变量与毒化其它分量；map替代scalar和zero值；samepath color/data用途分离、透明RGB及错误sRGB差分；独立double BRDF oracle和无灯emission oracle，不放宽上批方向/HDR容差。各alpha0/.25/1、largebrightness、极小coverage/tint、no-lights、normal反向、健康peer。map独立fullUV非零origin且与albedo/normal取不同块，nearest/linear给精确预期；actual FrameProvider同texture换frame、discard/retry/epoch和metadata变化；missing/corrupt/unsupported/alias/foreigndevice分别回安全结果。cache拒绝但合法加载与真实GPU配额拒绝/释放分别验证，不以手造nil替代。

**实际App最小集。** plain MR两个独立单变量，nonidentity effect MR；无灯emissive0/1/2、彩色、effect；emissive-only保持MR fallback；instance不同map/静态常量；动画map ready/after；missing/corrupt保normal/邻层；两个sun原作者材料的隔离代表运行。CPU/GPU/App脚本与产品先freeze，运行中不改模块；每门有实际completion/publication/terminal/nextframe，ROI配独立oracle。Universe只报告已知输入限制，不冒称第三个绿色收益。

复用 `test_scene_pbr_scalar.py`、base-material-profile门、lit/normal实际harness及graph capture邻接；新增聚合`test_scene_authored_pbr_map.py`适合清晰承载新loader/component/App门。按实际ABI/source-list失败半径选择现模块；checkpoint Debug build、code-health、scene-defense、design-gate；精确产品/test/Appmanifest交独立终审，不以build或module选择计划当完成。

### 退役与剩余

本片独审通过、所有实际纠正门达标并窄提交后，删除对应MR+静态emissive窄gate登记，稳定owner合同归现架构，执行身份/红绿/上限归历史记录。退休的是当前“slot2无prepareddata consumer/静态emissive无输出”断点，不退休官方parity、完整LIGHTING/REFLECTION gate、reflection环境资源、Universe材料动态属性或其它未验证格式。没有未消费的futurepayload、wrapper或临时旁路留给下一批。

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


<a id="f4-material-user-emission"></a>

## F4 — 2D material 自发光亮度用户属性（独立设计审查已批准）

基线`769d8a5e11daa8da4c38c33a92bb6418f1c97b55`。五判据①跨属性编译、资源准备、实时更新与渲染consumer，②触唯一property identity/事务及资源需求合同，命中设计前置；③不改持久格式，④不新增结构家族，⑤沿已批准作者输入与独立F3输出策略，无新私有公式需求。登记`scene-2d-material-property`批准前不写产品。

### 可见目标与选择

优先闭合 material 文件里的合法 `emissivebrightness={user:"constellations",value:2.3}`：属性启动值与0→1→0实时修改进入原共享 lit producer，plain 和 effect 两路同结果，不重建Scene/Program/纹理。Universe 3437487219 的 project slider 默认1/range0…1、三层146/135/143共用models/Universe.json、无instance override；scout提供material SHA `4fc65fa8a29edccefbe94fb0fed2ea0fc45c87e2607d5b91e2fbb34d804d2cd3`。作者输入与修前反例、修后运行身份均见[本片执行记录](../../history/scene/d3-material-user-emission-implementation-2026-10-02.md)，此处定义目标范围。

选择首片仅扩已准入 builtin genericimage2/4、LIGHTING=1 且现lit producer可消费的普通image接收者的 catalog emissivebrightness 无条件直接user绑定，保留静态 emissivecolor及现slot2合同。已有Puppet geometry会在LitCapture读取亮度前返回geometryUnsupported（`SceneRenderDescriptor.swift:92,195`、`SceneMetalView.swift:310–335`、`SceneResolvedMaterialFramePreflight+LitCapture.swift:54`）；本片不得为此产生虚假可消费的新instruction，原alpha与静态/3D路径保持原职责。Puppet受光保留后继能力，并不因本片准入边界而退役。复用现material属性compiler与同一个property Program/snapshot，不开第二解析或更新通道；不改Metal ABI/BRDF/资源provider。metallic/roughness/emissivecolor的动态属性、material script/Timeline、动态纹理或combo仍不从此片推出。相比先补“启动wrapper静态值”，完整live纵向能避免UI每次改值仍relaunch而且再次读不到catalog值的无效fallback。

### 修前真实首断点（基线）

路径以下相对 `MyWallpaperX/Core/SteamWorkshopScene/`：

1. `Format/SceneDocument.swift:111–117` resolver只处理scene root；`Runtime/Frame/SceneRuntimeSourceFacts`随后加载catalog。`Resources/Assets/SceneAssetCatalog.swift:226–239,290`保留material wrapper typed ShaderValue，未通过scene-root resolver。
2. `Systems/Properties/SceneStaticModelMaterialPropertyBindingCompiler.swift:19`只选择layer.staticModelPath；普通imagePath的合法material wrapper未形成property binding。
3. `Runtime/Frame/SceneRuntimeModel.swift:92–103`将此compiler输出合并到唯一ScenePropertyBindingCompiler，因此漏binding后没有对应definition/instruction/snapshot值。服务 `Modules/SteamWorkshop/Scene/SteamWorkshopSceneService+SceneProperties.swift:144,343`复用同compiler裁actionableKey，UI准入也遗漏。
4. `Runtime/Session/SceneDesktopWallpaperHost+LiveConsumers.swift:108–120`只激活preparedStaticModelLayerIDs的materialConstant，即使仅补编译也仍拒live。
5. `Compilation/Material/SceneBaseMaterialLightingProfile.swift:76–88,113–120`拒未解析user wrapper，emission=nil并移除allowed bit8；emission-only材料不产生map需求。合法literal brightness0仍有效并保需求，不是当前遗漏。
6. `Rendering/Frame/SceneResolvedMaterialFramePreflight+LitCapture.swift:119–127`只使用不可变profile.emission；plain `SceneMetalRenderer.swift:603`与graph `SceneResolvedMaterialFramePreflight.swift:825`虽都有同帧frameContext.dynamicValues，却未传给该consumer。

### 唯一身份、启动与优先级

复用现 `.materialConstant(layerID, passIndex:0, name:"emissivebrightness", materialPath:canonicalPath)`，共享material资产的每层仍为独立目标。`ScenePropertyBindingCompiler+TargetMapping.swift:50–66`已规范化material path；不要新造key或以sample/layerID切算法。

将现StaticModelMaterialPropertyBindingCompiler原地职责迁移并更名为SceneMaterialPropertyBindingCompiler，作为唯一material属性投影owner，保留3D已有字段及准入。本片只为2D新增上述一个已消费字段。入口应同时拿到descriptor与现typed instances，按每层最终有效作者来源选择：

- instance明确提供该key（包括0、非法值或合法scene-root启动投影）时，抑制底material binding；非法instance不得借旧material值伪装继承。
- instance未提供该key时继承material；共用material不意味着合并layer target。
- 有效startup instance wrapper已经由 `SceneDocument.swift:126` 的精确provenance、`SceneDocumentObject.swift:69–75`剥除user后投影为静态值，尊重该现事实。本片不声称它获得新的实时instance绑定。
- 材料wrapper沿原compiler对exact user/value、string合法key、有限一分量fallback的typed验证；script/Timeline/条件wrapper/非法shape不读raw fallback假装支持。
- 静态instance suppress与binding选择必须在编译前完成，不能同时发布两个writer再用帧调用顺序覆盖。现scene-root instance wrapper的unsupported/rebuild-required策略不暗中删除；与新material绑定共用属性key时，仍服从整个property Program的原原子/重建裁决。若要扩instance实时链，应另明确相应path owner，而非本片偷读rawValue。

启动值与fallback归唯一Program：`ScenePropertyBindingProgram.swift:509–555`生成作者fallback definition与validated instruction；`:95`起evaluate选effective user值；`SceneDynamicSnapshot.swift:625`起以authored definitions为底再应用typed user。Universe默认1应胜过wrapper fallback2.3，不将UI最大1错误地夹掉合法authored fallback。缺失/无效effective值沿原Program/snapshot fallback；consumer不重新查catalog或解释wrapper，也不在profile另冻一份fallback。

“已支持绑定”和“当前值”分开：准备期必须有通过原Program校验的目标才能标为2D动态consumer；没有definition/instruction不能因只见user字符串就准入。静态合法color是本片新增brightness binding的准入前提：compiler与profile复用同一静态分量来源/验证，显式非法或未解析color使该emission分量无consumer时，不得先生成不可消费的brightness instruction而连带拒绝同key已有alpha更新。缺省color仍按F3合法默认，不能把显式错误伪造成默认。合法color下缺/坏map或作者关闭map组件仅影响输出，prepared亮度target仍由同帧consumer读取；原slot2/metadata/provider规则不变。profile保存现typed目标与静态color所需的最小准备结果；帧内只读snapshot并形成现emission payload。

### 资源需求与live事务

有合法可执行brightness binding时，slot2需求由prepared能力决定，不由当前值是否为0或当前emission输出决定；0仍加载同一资源，以便0→1不用新资源通路。若当前snapshot值到最终consumer后因负数或不可表示Float等已存在输入边界使emission无效，最小关闭emission，保MR/normal/albedo；已准备的合法binding与map需求保留，后续合法值可恢复。此处不改变Program对非法用户修改的拒绝/fallback：live invalid一般先被原owner拒绝，不能将它说成成功更新后“局部关灯”。缺/坏/非法map仍沿F3原局部fallback。

`Host+Launch.swift:482–490`已有profile→lightingDemands→同catalog加载；应给profile compiler传入同一已编译property Program/typed支持目标，在该处准备可恢复需求，不能每帧load或profile新增JSON解析。

Host live admission将实际准备的2D brightness目标与已有model目标合并，不因layer是image就放行所有materialConstant；仍通过统一activeConsumerTargets检查。`ScenePropertyLiveUpdateState.swift:58`全兄弟目标先验证、构造candidate并一次提交；`SceneDesktopWallpaperSession.swift:225–287`先candidate、consumer canApply后替换context；recordID不符在:221拒绝。复用这些owner，不引入新commit/clock/revision。

`Session+FrameDriver.swift:266–271`将同一liveState.userValues送唯一snapshot。plain/graph两caller都把frameContext.dynamicValues交同一LitCapture；consumer按prepared target读取这一个snapshot，校验已有有限非负及Float表示边界，输出原emission SIMD/payload，Metal无变化。snapshot身份/priority由现frameContext保证，不加无producer stale guard。后续任何取消、错误类型、未知key、无法消费兄弟target均遵原atomic拒绝且旧liveState/revision/画面保留；暂停时先值提交，下个真实frame采用，不另开定时器。

### 最小owned候选（约10个existing职责）

1. `Systems/Properties/SceneStaticModelMaterialPropertyBindingCompiler.swift`（更名同owner）：泛化layer source选择与2D字段投影，保3D。
2. `Runtime/Frame/SceneRuntimeModel.swift`：传typed instance，编译唯一Program。
3. `MyWallpaperX/Modules/SteamWorkshop/Scene/SteamWorkshopSceneService+SceneProperties.swift`：同compiler的UI actionable与target支持。
4. `Compilation/Material/SceneBaseMaterialLightingProfile.swift`：已批准动态target与静态color/当前emission分离、结构需求。
5. `Compilation/Material/SceneBaseMaterialProviderBindingCompiler.swift`：传准备期typed property能力到同profile。
6. `Runtime/Session/SceneDesktopWallpaperHost+Launch.swift`：统一Program准备输入与activeConsumer目标贯通。
7. `Runtime/Session/SceneDesktopWallpaperHost+LiveConsumers.swift`：仅实际prepared2D目标激活。
8. `Rendering/Frame/SceneResolvedMaterialFramePreflight+LitCapture.swift`：同帧snapshot→原emission。
9. `Rendering/Frame/SceneMetalRenderer.swift`：plain caller传snapshot。
10. `Rendering/Frame/SceneResolvedMaterialFramePreflight.swift`：graph caller传snapshot。

具体接口由实现压缩；避免compiler/profile各复制一套材质关联/准入逻辑，准备期选择应有一个canonical owner。无须新增registry/provider/Metalpipeline/全局fallback。若rename，需要root精确layout/validation paths收敛，不能盲加别名wrapper。不预授权现property owner改语义或把未知动态instance纳入本片。

### 修前真实红与纠正门

以下门的实际结果归[执行记录](../../history/scene/d3-material-user-emission-implementation-2026-10-02.md)；必须先冻结RF11 immutable App与自有输入/test/oracle，再执行：

- CPU真实project→scene/catalog→descriptor→compiler→Program→profile：三个同model image层、default1/fallback2.3，期待三个唯一layer target、current emission1及实际map需求。旧实现应无三个binding且emission-only map未需求。不是Python模拟或source字符串assert。
- CPU material共享fanout与优先级：一层static instance0、一层无override、一层static正值；只继承层有material producer；合法startup instance照现投影；无静态字段不能混成0。保3D已有绑定与custom/multipass/Lighting0/非法wrapper负控。
- CPU原live-state事务：0→1→0、同值no-op revision稳定、合法缺effective fallback、错误类型/超range/同key一个unsupported sibling/recordID stale时全拒且旧值/版本不变。若构造consumer-only负值注入，明确非自然UI通路。
- GPU consumer/API门：相同prepared map/normal/albedo资源，读取两帧snapshot brightness0/1及旧snapshot重放，plain/effect同emission结果；black ambient/no lights仍响应，alpha/normal/MR不回归。错误类型/缺目标遵原fallback，不能绕typed Program。
- 真实自有App：三层fanout、plain与nonidentity effect、0→1→0可判别ROI、实际property-update accepted=true、same session/no relaunch、健康邻层、frame completion/publication/terminal及next-frame。启动0也保map需求；invalid live回滚保持旧图。所有runner/test冻结后才启动，执行期间不改模块。
- Universe完整原21对象包：先记录旧不可见/无响应的确切firstbreak；修后用同原输入、默认与合法user覆盖运行。若其它loader/准入/VM等阻断，明确原包未恢复，再用原material+资产独立presentation证明本consumer贡献；不删原脚本后声称原包收益。

复用 `test_scene_static_model_material_properties`、`test_scene_property_live_update_state`、`test_scene_authored_pbr_map`及现pbr_scalar的actual behavior harness；更新必要source-list/stubs，不添加shape tests。执行失败半径先CPU再checkpoint build，再冻结App与GPU；code-health/defense/design必跑，原3D邻接不可因泛化漏掉。


### 同会话纠正门补充（独立设计审查已批准）

现`MyWallpaperX/App/DebugScenePlaybackRunner.swift:507–530`只在ready后调度一次live dictionary；`DebugScenePlaybackRunner+Arguments.swift:117–136`只解析单次dictionary。单独两进程的0→1与1→0不能冒称同会话完整cycle。为执行本批已批准的可见门，扩现DEBUG runner两文件，新增顺序dictionary数组参数`--mwx-debug-scene-live-property-sequence-json`；无此参数时保持原single flag行为，显式sequence优先于single。每步沿现ready后的2秒间隔顺序调用原`runtimeHost.applyUserPropertyValues`，保留同record/session/window，逐步记录序号和accepted；原live-property-update整行保持兼容，序号单独记录在sequence-step事件，避免旧consumer的连续字段及keys尾字段被破坏。复用现periodic snapshot验证中间亮帧与最后暗帧，不新增产品property state、clock或观察常驻路径。

序列复用现strict dictionary值/key/总输入大小验证；整个数组验证后才调度，坏元素不能留下已执行前缀，明确诊断且不执行该序列。输入producer就是显式debug CLI JSON。场景关闭后不再发后续步，沿原isClosing边界；不改普通播放或原host事务。此诊断输入有本批App用例实际调用，不留无人调用入口。两App文件由单一实施者持有，设计释放前不写。

合法原Universe的同key还绑定三层alpha（scene objects[1..3]，层146/135/143）；旧运行证据已有三个alpha instruction，key不在rebuildRequired列表。146/143初始隐藏但已有alpha consumer。F4须验证新增三个emission target与三个alpha target共同原子更新，不能只激活可见层导致隐藏兄弟拒绝整key。完整原包0/1全图差异本来也可由alpha造成，emission因果须由固定alpha的presentation及typed消费门证明，再核原包六target同帧、无relaunch及next-frame。此补充不新增材质准入profile，也不把文本命中当运行consumer。

### 方案裁决、纠正与退役

本片选择catalog中`emissivebrightness`完整启动及实时链，因为真实作者声明已明确，原Program、snapshot及lit payload能承载，无需另造解析器或shading。只剥startup wrapper会保留更新后重启仍无结果的断点；逐帧解析raw会引入第二property权威，两者不选。暂不扩其它材质字段或instance实时绑定；这些保留后继，不能把本片小范围验收当D3完成。

现compiler更名为`SceneMaterialPropertyBindingCompiler`，迁移现调用/source lists，不留旧别名wrapper或重复compiler。路径清单只做这一个owner的替换；并行layout排序改动保持原样且不搭入本批提交。禁止增加新registry、property state或计时器；新增guard须指明实际typed输入producer，终审逐项核对。

普通视觉输入缺失只关闭该emission分量，MR/normal/albedo和健康邻层按既有合同保留；stale record、类型/range不合和不可消费同key兄弟目标仍由原属性事务拒绝、旧revision及输出保留。shader ABI与Metal数值策略保持F3；若真实红证显示其它必需改动，先修订本设计再释放。

纠正门包括上述真实解析/transaction/GPU/App和原包首断点，并要求Debug构建、code-health、scene-defense、design-gate及独立终审绑定精确源码/test/App身份。当前合法scene-root instance投影、已有3D材料属性须回归。成功后稳定owner合同移交架构、执行身份和上限归历史、窄gate删除；退役的是catalog亮度无producer/consumer与结构需求漏接，不退役其它动态材质能力、原包剩余缺口或官方parity。


<a id="f5-reflection-environment"></a>

## F5 — reflection-only 环境输入与表面响应（N3研究中，产品设计未批准）

基线`6a95278f`。本批闭合普通builtin genericimage2/4的REFLECTION1、LIGHTING0材料：法线、roughness、reflectivity及slot2 B影响实际反射，保持direct独立、现alpha/HDR和唯一terminal。方法与数值由本项目独立实现，不等待或复制官方公式。五判据①跨material/资源/graph/consumer，②触及唯一target/publication生命周期，⑤外部输入语义，故登记`scene-2d-reflection-environment`，来源/顺序和最小产品设计批准前不写产品。

**当前事实。** 以下路径相对Scene根：`Systems/Properties/SceneMaterialPropertyBindingCompiler.swift:64`和`Compilation/Material/SceneBaseMaterialLightingProfile.swift:56`仅以LIGHTING准入；profile`:100`及`Rendering/Metal/SceneLitImageLayerPipeline.swift:163`未消费Reflection bit4。`Runtime/Session/SceneDesktopWallpaperHost+Launch.swift:489`只准备normal/map，无env producer；`Resources/Textures/SceneTextureProviderPublication.swift:314`的sameFrameSceneBackground是作者顺序前缀、单mip，不能未经定案冒称环境。显式系统RT则在`Compilation/Material/SceneResolvedMaterialTemplateCompiler.swift:193–201`另受准入限制。此为静态首断点，旧App缺响应反例待实际运行，不先写已复现。

**已有输入与真实候选。** [官方公开合同](https://docs.wallpaperengine.io/en/scene/lighting/introduction.html)规定Lighting/Reflection独立、roughness控制模糊、Reflectivity整体强度及Reflection map局部权重；[已审中性声明](../../history/scene/d3-pbr-input-neutral-contract-2026-10-02.md)和[通道合同](../../history/scene/d3-pbr-map-input-neutral-contract-2026-10-02.md)已定reflectivity默认1和B职责。合法3780119725的普通层276材料声明LIGHTING0/REFLECTION1、reflectivity4、roughness0.53、normal及slot2，无instance/effect；同包层308有effect，可作后继正例。它们没有显式env输入，不能据名称或第三方planar路径推断隐含来源。作者字段只作回归输入，不作dispatch键。

**N3唯一研究问题。** builtin REFLECTION消费何种颜色资源、何时生成、是否纳入接收者自身？先在旧App/实际builder记录缺少profile/资源消费，再由隔离research-only上下文按[官方取证工作流](../semantics/official-client-behavior-research-workflow.md)读取最小作者声明：sampler角色/default、2D或cube类型、presence、reflectivitydistance输入角色。只交中性字段/顺序/lifecycle，不交shader行、函数体、伪码、payload或公式；已有声明充分时不反编译。

候选为本帧前缀、本帧完整场景、previous frame或静态环境。官方黑盒先用普通image可见正控制确认输入身份/viewport，再用红绿环境板置于接收者前后及一次magenta脉冲，区分内容范围和延迟；第二接收者观察自反射反馈；clear边缘及normal/view移动只定输入坐标/alpha职责。每次只变一个变量。沿既有Parallels合法客户端入口；上次D1未取得effect正控制，不等于客户端不能运行。若运行条件不足，只将官方parity记not-run，继续经审查静态中性合同下的独立有界实现；不能拿无正控制截图裁决资源来源。

**方案/owner。** 输入定案后由原profile准备有效intent/静态值和需求，原graph/target池分配并发布typed env，原registry验证generation/epoch，plain/effect共同lit producer消费。normal/view决定自有取样方向、roughness控制有界模糊、metallic与reflectivity及B决定反射份额；具体独立方法在资源合同确定后设计评审。反射与direct分开启用，不改作者LIGHTING来借通路，不建第二registry/clock/compositor。若需history/mips，必须扩原资源descriptor/预算/在飞生命周期，不能裸texture别名或仅开mip标志。planar camera、3D和完整RT词汇不捆绑本片。

**fallback与纠正门。** 可选env缺失只关反射并保原层/邻层；identity、hazard、generation、真实预算等unsafe仍拒最小单元。自有红绿空间环境区分反射与整体增亮，normal翻转、REFLECTION0/reflectivity0、roughness对比度、B分区、alpha/HDR和下一帧脉冲均须可判别；plain与非identity effect共用消费，实际allocation→encode→completion→publication→terminal→next-frame留证。资源切换/resize/失败按选定输入合同验证，未测明确列出，不以官方公式缺失或单图非黑收口。

**退役。** N3中性合同经独审后替换本节的unknown和研究动作，批准最小产品设计再实施；产品/App及独立终审通过后将稳定资源职责移交架构、执行记录归历史、删除窄gate。未来Puppet/planar/动态材质字段保持独立后继，不由本片代验。
