<!-- document-role: current-state -->

# Scene 静态审计：当前剩余问题

> 2026-10-16 复核；代码起点 `680e54846`。本页替换 2026-10-09 的审计快照，只保留现役代码仍能定位的缺口与问题，不再维护旧 243 样本统计、完整/部分能力评分或修复数量。

选序服从[兼容路线](scene-compatibility-roadmap.md)：**画面正常合成与播放 → 有证据的性能问题 → 属性调节热接入 → 其他能力**。[断点队列](scene-open-breakpoint-queue.md)拥有实际用户现象和运行待办；本页只补跨专题的静态首断点，不建立第二份样本状态。完整能力边界分别归[渲染图与 shader](../capabilities/render-graph-shader-coverage.md)、[粒子](../capabilities/particle-component-coverage.md)、[高级对象](../capabilities/advanced-object-coverage.md)和[SceneScript API](../capabilities/scenescript-api-coverage.md)。

## 判据与证据边界

- 保留：当前明确的准入拒绝、缺失 producer/consumer，或可由同一输入构造的职责/状态不一致；写清范围与首 owner。**静态可证能力缺口不等于真实样本故障或可见恢复。**
- 不保留为当前缺陷：仅因没有专用 effect 派发键、出现 unsupported 字样、字段只被保真、旧代码退役或旧截图异常而得出的结论；generic Program、editor-only metadata 和合法局部回退须分别核对。
- 初次静态复核只查生产代码、现役合同和已有中性收据，未重新普查原包或读取作者 JS/GLSL；后继已修项按其合同和实际验收退出。本页不产生最新全样本覆盖数，也不把下表的待验证门写成已执行结果。
- 2026-10-09 原报告及逐样本附录可由 `git show 680e54846:docs/scene/roadmap/scene-full-sample-static-audit.md`追溯；后继真实运行归[运行证据](../capabilities/runtime-evidence-current.md)及对应 history。旧计数、严重度和不可回源的审查 totals 不继续参与当前判定。

## 画面合成与播放

| 当前问题 | 现役首断点与已支持边界 | 最小验证/退出条件 |
|---|---|---|
| **resolved effect 的非 overwrite render state 尚未执行**（原 G21） | [typed state](../../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneMaterialRenderState.swift)保留 `translucent/additive`等枚举，但[pass encoder](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPassEncoder.swift)仍只准入 normal、depth/write disabled、nocull、alpha unspecified/enabled 的 fullscreen overwrite。不能外推为所有 additive/translucent 都失败：粒子和模型有各自已支持消费者。 | 314当前source50的早拒VERSION已退出，但仍缺neutral output proof而保留原视频；不是G21 effect混合的合格消费者，未证可见损失。先取得真实 active pass 的精确 state/输出用途，再补同一 Program 的像素门；factor、alpha convention、`alphawriting=default`未定时不放宽。权威边界见[render state](../capabilities/render-graph-shader-coverage.md)。 |
| **动态特殊资源创建仍有明确拒绝面** | [createLayer](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSLayerSceneHost.c)对 Puppet 的 `animations/puppetAnimationLayers/effects`配置仍局部拒绝；prepared 默认 Puppet 与 text/image 实例已存在。空composition已沿同一prepared kind创建，正交childless背景采集可平面采集/透视回绘；成员/effect/config及更广capture未开放，不可扁平化成普通image。 | 以实际 constructor 请求和已准备资源为准，先区分默认实例、额外配置与资源未准备；[已准备 Puppet](../history/prepared-puppet-default-instances-2026-10-15.md)和[composition后继边界](../history/composition-local-perspective-2026-10-16.md)保留，288音频可见ROI未证。没有新的真实收益时不重开空 composition 或已验 clone 窄片。 |
| **static model 的任意 custom shader 与非首 material pass 未准入**（原 G11 的明确剩余部分） | [static-model binding compiler](../../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneStaticModelMaterialBindingCompiler.swift)把受证接口降到现有模型材质，限定 pass 0，并明确不执行任意 custom shader。已支持的 static geometry、材质值脚本、named albedo 与发光不能列作缺失；不能将此门泛化为 model/geometry 整体不可用。其余完整 runtime 范围归[高级对象](../capabilities/advanced-object-coverage.md)。 | 先取得 active model 的实际 pass/interface 首错，复用 prepared geometry/material 与唯一 compositor；`.dxs`文件存在或旧 blob 数量不足以证明该样本当前缺图。 |
| **Puppet rotation/gravity/IK 物理 profile 明确拒绝**（原 G15 的剩余部分） | [rig reader](../../../MyWallpaperX/Core/SteamWorkshopScene/Format/SceneMdlPuppetRigReader.swift)的平移 spring/rigid profile 对启用 rotation/gravity/IK 拒绝。LBS、挂点、平移回弹与骨写已支持，不能再称 Puppet 整体无 physics。 | 须先有独立输入合同与有界 observable，[高级对象](../capabilities/advanced-object-coverage.md)拥有具体范围。U40 官方载体资格 STOP 不因本表重启，未知 impulse 不以 no-op 补齐。 |
| **point volumetric 与 2D lit directional consumer 缺失**（原 G6/G7） | [SpotLightPlan](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Lighting/SceneSpotLightPlan.swift)仅准入 bounded `lspot` cone；[2D light payload](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Metal/SceneLitImageLayerPipeline.swift)只打包 point/spot/ambient，无 directional 槽。现有静态模型 directional 与 2D point/spot 不受此结论否定。 | 各取实际 visible consumer，分别锁 point volume 与 2D directional 输入/输出；方向、能量和空间合同未定时不套用其他灯型参数。精确数值研究归[光照边界](../capabilities/advanced-object-coverage.md)。 |
| **粒子 periodic 最大每周期数量尚未支持**（原 G5） | [periodic admission](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticlePeriodicEmission.swift)仍要求 `maximumEmissionCount == nil`；合法 `maxtoemitperperiod`进入当前 profile 也会被拒，不能用普通 duration/delay/rate/count 已支持关闭此项。 | 10-16真实consumer核为3749463715的405/412→thunderbolt，非3750813609；alpha在frame790/fps90才到1，cap32之外另缺mapsequencebetweencontrolpoints与maintaindistancebetweencontrolpoints。未启动单项cap实验，不承诺解除该门就恢复雷电。沿原schedule/出生owner补完整依赖与数值合同，验证fixed-dt、seed、数量及回滚，不猜倍率/重置或扩大预算。资格：`.artifacts/scene-evidence/runs/open-consumer-qualification-20261016/`内`particle-period-cap/qualification.json`（静态资格，无新运行）。[粒子合同](../capabilities/particle-component-coverage.md)拥有数值 unknown。 |

## 性能

[性能卡](performance-convergence-card.md)独占成本证据与继续/停止决策。旧 R1–R53 的结构重复、读盘次数、缓存域数及推算成本不在本页继续作为当前性能缺陷；其中 R40 的播放状态问题已由[共享角度消费](../capabilities/advanced-object-coverage.md#standalone-spot-playback)闭合并退出，不继续作为重复求值优化排期。声明准备、排序、working-view、capture/identity 等 NO-GO 不因旧报告仍能找到类似代码而重启。没有新的普通配置大成本与唯一 owner 证据时，继续画面/播放功能。

## 属性与其他接口

| 当前问题 | 现役首断点与已支持边界 | 最小验证/退出条件 |
|---|---|---|
| **粒子绝对 color 的 direct user-property target 未映射**（原 G24） | [TargetMapping](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/ScenePropertyBindingCompiler+TargetMapping.swift)的 particle `.color`仍返回 nil，`.normalizedColor`已有 typed route。 | 先有实际合法定义和颜色单位合同，再复用同一 typed instruction/出生 consumer。当前逐通道平方是否符合官方不能仅由静态代码判错；不要把此输入缺口扩成全部粒子颜色错误。 |
| **公开 font String 与当前 handle ABI 不一致** | [固定公开声明](../development/reference/lib.sceneScript-v2.8.d.ts)的 `ITextLayer.font`是 String path；[C getter/setter](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSLayerValueHost.c)却返回/要求 registered asset handle。[typed font mutation](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptDynamicLayerRuntime.swift)及 descriptor/CoreText consumer 已有，缺口在公开值类型边界。 | 344同身份读源发现目标102与邻例391有registerAsset生产者，但相关font变量/计算成员的实际分支及runtime类型未执行；不能把38次词法font写当String被拒。102 authored隐藏、outer newproperty8是textinput，真实font selector仍unknown。下一门只在默认初始all-key callback观察exact owner/JS类别/asset-class/journal；handle已接受、更早prepare失败或未进入callback即STOP。String资源授权、旧handle及整包回滚沿原owner。资格：`.artifacts/tmp/font-string-consumer-qualification-20261016/qualification.json`。 |
| **usershortcut 执行未接入**（原 G3 的剩余部分） | [property kind](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneUserProperty.swift)无可执行 shortcut kind；未知类型现由原面板只读展示，旧“EmptyView静默丢弃”已经不是当前事实。SceneScript `openUserShortcut`尚无执行入口。 | 先取得真实用户动作与 macOS 产品授权/取消合同，再沿原 property/交互入口实现；不因缺类型而隐藏定义，也不补无人调用的空 API。权威边界见[属性卡](properties-panel-card.md)与[API表](../capabilities/scenescript-api-coverage.md)。 |

## 未知项与后继维护

下列事项继续由原权威持有，本页不重复标成已证错误：

- 样本姿态/布局/光束/输入观感、精确光照与粒子 color/colorn 数值、Rope world/负细分及 Vec 字符串 edge：归[断点队列](scene-open-breakpoint-queue.md)和对应 capability；旧声明、旧截图、近似代码或尚未完成官方对照不能证明当前错误。
- texture-animation wrapper 的保真与[未授权 executor](../../../MyWallpaperX/Core/SteamWorkshopScene/Format/SceneScriptBindingDefinition.swift)不独立证明播放缺陷；实际字段、返回值合同和可达 producer 尚须资格，普通 TEX 自动播放与 handle 控制另有现役链。Puppet [optional vec3 suffix](../../../MyWallpaperX/Core/SteamWorkshopScene/Format/SceneMdlPuppetMeshReader.swift)仅被校验/跳过，其含义仍未知，不据此认定 painted depth/extrusion 首错；公开能力的研究边界归[高级对象](../capabilities/advanced-object-coverage.md#op-puppet-perspective)。
- 原多 renderer/child RopeTrail 聚合项退出当前缺陷表：selector 只选一项不能独立证明应同时执行多个 authored renderer，本轮也未取得真实 child RopeTrail 请求。具体未准入组件归[粒子专项](../capabilities/particle-component-coverage.md)，须先取得精确输入和输出合同，不能靠 unsupported 数量升级；[depth-one static child Rope](../history/static-child-rope-2026-10-16.md)的正 XY 等比、独立正 Z、无 nested/world-space movement 缩放已支持，不能继续整族误报。
- [SceneScriptValueRuntime.initialize](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptValueRuntime.swift)仍有依赖 `invalid Vec3`文本的 angles兼容分支（原 M6）；当前存在性可证，但不能单凭分支存在认定其兼容语义错误。任何收敛须核[SceneScript合同](../capabilities/scenescript-runtime-implementation-contract.md)、当前有效作者模式与失败事务反例，不删除必要路径消除审计条目。
- MDLA keyed auxiliary scalar、Timeline smoothing/stiffness/events 与 effect editor metadata：保真或未解释事实不自动等于播放缺失；尚无 runtime-required合同或可达非空输入的，不升级为当前故障。

每次更新只替换相应残余行：静态边界变更须核当前 caller与consumer；关闭用户现象须有同身份实际输出和相邻反例；涉及性能则遵守性能卡。测试通过、ready或一张正常图各只证明其覆盖范围，不升级为全样本正确、官方parity或专项完成。
