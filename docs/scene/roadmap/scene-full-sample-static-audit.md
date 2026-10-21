<!-- document-role: current-state -->

# Scene 静态审计：当前剩余问题

> 10-16基线 `680e54846`，后继按有界后验退出已修首门。10-21新增24项诊断补控制点距离约束准入缺口，并退出已实现的usershortcut旧条目；固定float数组32已由[后验](../capabilities/runtime-evidence-current.md#generic-varying-array-20261021)有界退出，不再列为未资格首门；未重审旧全集。本页不维护旧243统计、评分或修复数量。

选序服从[兼容路线](scene-compatibility-roadmap.md)；用户现象与运行待办归[断点队列](scene-open-breakpoint-queue.md)，此处只保跨专题静态首owner。合同分别归[shader/图](../capabilities/render-graph-shader-coverage.md)、[粒子](../capabilities/particle-component-coverage.md)、[高级对象](../capabilities/advanced-object-coverage.md)和[SceneScript](../capabilities/scenescript-api-coverage.md)。

## 判据与证据边界

- 保留：当前明确的准入拒绝、缺失 producer/consumer，或可由同一输入构造的职责/状态不一致；写清范围与首 owner。**静态可证能力缺口不等于真实样本故障或可见恢复。**
- 不保留为当前缺陷：仅因没有专用 effect 派发键、出现 unsupported 字样、字段只被保真、旧代码退役或旧截图异常而得出的结论；generic Program、editor-only metadata 和合法局部回退须分别核对。
- 初审只核生产代码、合同和中性收据；后继按真实验收局部更新，不产生全样本覆盖数或把待验证门写成已执行。旧报告可由 `git show 680e54846:docs/scene/roadmap/scene-full-sample-static-audit.md`追溯；旧计数/严重度退出当前判定，实际后验归[运行证据](../capabilities/runtime-evidence-current.md)。

## 画面合成与播放

| 当前问题 | 现役首断点与已支持边界 | 最小验证/退出条件 |
|---|---|---|
| **direct MDL余下动画输入与channel** | 原80B模型已复用共享Selector/clock/pose并以XYZ stream输出，329默认34实际恢复盒顶区域舞姿；旧“无默认骨架动画接线”退出。direct条件对象已成功准备/热切换，退出此静态缺口；rate Number脚本已沿原播放消费者贯通；非中性alpha/aux/morph、非空direct附件及多part动画未资格，继续typed bind降级。 | 沿原属性/脚本typed动画控制或现channel owner取得合法消费者，不新建clock/LBS、不跳坏record。已闭范围归[动画合同](../capabilities/direct-model-skeletal-animation.md)及[运行证据](../capabilities/runtime-evidence-current.md#direct-model-skeletal-animation-20261019)，边缘色块已由公共截面后继单独修复，未完成项不升全样本失败或成功。 |
| **现代MDLA dense state1的非neutral profile仍未覆盖** | 原reader/evaluator已支持全帧常量、九lane齐全且与bind等价的neutral state1，339两model动画与查询首门已恢复，不再列其整个state1缺失。非neutral/非恒定或未证参考姿态仍拒绝；与下行auxiliary/scalar为不同首门。 | 不重开339已闭首门；只有新active非neutral消费者和可归因姿态ROI才续接参考姿态/变换合同。固定官方单header正反的局部眼部变化仍反证“把任意state1当state0”。[现役neutral资格及边界](../capabilities/runtime-evidence-current.md#constant-dense-state1-20261018)。 |
| **Puppet动画auxiliary profile仍有拒绝面** | 多target裁剪已让357人物恢复；animation1678仍被固定tag门拒，伴MDMP与scalar依赖而保持bind-pose；四clip已逐record核完，均有79/80骨约0.7的非一alpha；1678/258另有非零逐骨scalar，混合规则未证。stride84 position.w的19个ordinal已证，旧参考reader多读4B已纠正；packed位移/第二通道及曲线混合仍未知。已支持LBS/挂点/clipping及其他版本动画不能一并报缺失；格式准入也不等于本条播放已修。 | 先做morph/scalar消费者与混合顺序设计，核准真实MDLA/auxiliary边界及producer语义，沿原evaluator/pose补通用profile；不可跳track、吞坏数据或另建变形器。须原包真实姿态推进及健康/失败邻例。 |
| **prepared effect输入与source cohort仍有拒绝面** | 358部分RGBA slot用途proof未接：slot1读RGB+A权重，slot2才读红mask，暂无可归因ROI；357 effect/pass Combined超出现有组，跨pass官方正控失败，clock/alias仍UNKNOWN；363765有child，Blur772被whole-stage childless门拒，缺图ROI未证。 | 沿原值类别、纹理用途与来源闭包扩展，不按effect名补参数、统一RGBA转红mask或挑首root。357233原范围不由[Combined资格](../capabilities/runtime-evidence-current.md#effect-combined-qualification-20261018)放开；382旧noise需求门已[修复](../capabilities/runtime-evidence-current.md#sampler-presence-requirements-20261017)。 |
| **动态world-space完整affine与空间consumer仍有拒绝面** | 有界root origin-only普通Sprite已按[唯一合同](../capabilities/particle-component-coverage.md#root-world-translation)接通，296的准备/播放首门退出；Z/rotation/scale、parent/attachment/child、native/perspective、Trail/Rope及外部空间CP/force仍不进入新profile。旧static层未声明peer移动仍可能拖动旧粒子。359777 Bird的零origin world force已按[独立源空间合同](../capabilities/particle-component-coverage.md#control-point-force-的源空间与缺省距离)接通；非零operator origin及鸟群可见结果仍未闭合。 | 先取实际active consumer与可归因ROI，沿现空间/出生/绘制owner扩展，不复制坐标链或只删guard；无新可行动证据时不惯性细化平移。 |
| **resolved effect 的非 overwrite render state 尚未执行**（原 G21） | [typed state](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneMaterialRenderState.swift)保留 `translucent/additive`等枚举，但[pass encoder](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPassEncoder.swift)仍只准入 normal、depth/write disabled、nocull、alpha unspecified/enabled 的 fullscreen overwrite。不能外推为所有 additive/translucent 都失败：粒子和模型有各自已支持消费者。 | 314当前source50的早拒VERSION已退出，但仍缺neutral output proof而保留原视频；不是G21 effect混合的合格消费者，未证可见损失。先取得真实 active pass 的精确 state/输出用途，再补同一 Program 的像素门；factor、alpha convention、`alphawriting=default`未定时不放宽。权威边界见[render state](../capabilities/render-graph-shader-coverage.md)。 |
| **动态特殊资源创建仍有明确拒绝面** | [createLayer](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSLayerSceneHost.c)对 Puppet 的 `animations/puppetAnimationLayers/effects`配置仍局部拒绝；prepared 默认Puppet、text与ordinary image实例已存在；[动态图片默认材质](../history/dynamic-image-default-material-2026-10-16.md)已接strict builtin静态LIGHTING/标量，未知combo/动态provider、多pass及optional材质资源仍拒绝。空composition已沿同一prepared kind创建，正交childless背景采集可平面采集/透视回绘；成员/effect/config及更广capture未开放，不可扁平化成普通image。 | 以实际 constructor 请求和已准备资源为准，先区分默认实例、额外配置与资源未准备；[已准备 Puppet](../history/prepared-puppet-default-instances-2026-10-15.md)和[composition后继边界](../history/composition-local-perspective-2026-10-16.md)保留，288音频可见ROI未证。没有新的真实收益时不重开空 composition 或已验 clone 窄片。 |
| **static model 的剩余 material render state 未完整执行** | 颜色路径已消费显式 normal 的独立 RGB/几何 coverage，translucent 保原透明覆盖；但typed additive仍落既有source-over，raw depthtest未由模型颜色draw完整消费，任意原生RT的作者A/alphawriting尚无完整消费者合同；隐式geometry隔离已退休为[共享场景域](batch2/2d-lighting-material-design.md#model-scene-depth-domain)，不据此称余项已支持。不能把 normal 修正称为全部材质 state 已支持。 | 先定位真实 active part 的独立可见损失，再沿同一 prepared state/颜色 draw 扩展；保持图层淡出、纹理 coverage、depth 与唯一 PMA 输出。[有界策略](batch2/2d-lighting-material-design.md#static-model-normal-coverage)。 |
| **static model 的任意 custom shader 与非首 material pass 未准入**（原 G11 的明确剩余部分） | [static-model binding compiler](../../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneStaticModelMaterialBindingCompiler.swift)把受证接口降到现有模型材质，限定 pass 0，并明确不执行任意 custom shader。已支持的 static geometry、材质值脚本、named albedo 与发光不能列作缺失；不能将此门泛化为 model/geometry 整体不可用。其余完整 runtime 范围归[高级对象](../capabilities/advanced-object-coverage.md)。 | 先取得 active model 的实际 pass/interface 首错，复用 prepared geometry/material 与唯一 compositor；`.dxs`文件存在或旧 blob 数量不足以证明该样本当前缺图。 |
| **Puppet rotation/gravity/IK 物理 profile 明确拒绝**（原 G15 的剩余部分） | [rig reader](../../../MyWallpaperX/Core/SteamWorkshopScene/Format/SceneMdlPuppetRigReader.swift)的平移 spring/rigid profile 对启用 rotation/gravity/IK 拒绝。LBS、挂点、平移回弹与骨写已支持，不能再称 Puppet 整体无 physics。 | 须先有独立输入合同与有界 observable，[高级对象](../capabilities/advanced-object-coverage.md)拥有具体范围。U40的setter正控、视觉脉冲及query分道观察见[唯一资格记录](../history/repeated-puppet-drag-qualification-2026-10-16.md#official-pose-query-observation)；query/render局部translation首门已修，后继只澄清实际释放impulse及顺序/一次提交合同，不以早期2/2 STOP否定新观察，也不以有界观察开放未知impulse或更广物理profile。 |
| **point volumetric 与 2D lit directional consumer 缺失**（原 G6/G7） | [SpotLightPlan](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Lighting/SceneSpotLightPlan.swift)仅准入 bounded `lspot` cone；[2D light payload](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Metal/SceneLitImageLayerPipeline.swift)只打包 point/spot/ambient，无 directional 槽。现有静态模型 directional 与 2D point/spot 不受此结论否定。 | 各取实际 visible consumer，分别锁 point volume 与 2D directional 输入/输出；方向、能量和空间合同未定时不套用其他灯型参数。精确数值研究归[光照边界](../capabilities/advanced-object-coverage.md)。 |
| **粒子 periodic 最大每周期数量尚未支持**（原 G5） | [periodic admission](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticlePeriodicEmission.swift)仍要求 `maximumEmissionCount == nil`；合法 `maxtoemitperperiod`进入当前 profile 也会被拒，不能用普通 duration/delay/rate/count 已支持关闭此项。 | 10-16真实consumer核为3749463715的405/412→thunderbolt，非3750813609；alpha在frame790/fps90才到1，cap32之外另缺mapsequencebetweencontrolpoints与maintaindistancebetweencontrolpoints。未启动单项cap实验，不承诺解除该门就恢复雷电。沿原schedule/出生owner补完整依赖与数值合同，验证fixed-dt、seed、数量及回滚，不猜倍率/重置或扩大预算。资格：`.artifacts/scene-evidence/runs/open-consumer-qualification-20261016/`内`particle-period-cap/qualification.json`（静态资格，无新运行）。[粒子合同](../capabilities/particle-component-coverage.md)拥有数值 unknown。 |
| **粒子到控制点的距离约束未准入** | 新增3742497499声明`maintaindistancetocontrolpoint`及controlpoint/distance/variablestrength，现parser无该operator case；与`maintaindistancebetweencontrolpoints`不同，不能按名称互换。 | 先定位实际active renderer、约束前后粒子轨迹及合法数值合同，沿原operator/CP owner接入；静态声明与准入缺口不证明可见缺失。新增`inheritinitialvaluefromevent`已有有界消费者，不一并报缺失。[本轮诊断](../capabilities/runtime-evidence-current.md#intake-20261021)。 |

## 性能

[性能卡](performance-convergence-card.md)独占成本证据与继续/停止决策。旧 R1–R53 的结构重复、读盘次数、缓存域数及推算成本不在本页继续作为当前性能缺陷；其中 R40 的播放状态问题已由[共享角度消费](../capabilities/advanced-object-coverage.md#standalone-spot-playback)闭合并退出，不继续作为重复求值优化排期。声明准备、排序、working-view、capture/identity 等 NO-GO 不因旧报告仍能找到类似代码而重启。没有新的普通配置大成本与唯一 owner 证据时，继续画面/播放功能。

## 属性与其他接口

| 当前问题 | 现役首断点与已支持边界 | 最小验证/退出条件 |
|---|---|---|
| **粒子绝对 color 的 direct user-property target 未映射**（原 G24） | [TargetMapping](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/ScenePropertyBindingCompiler+TargetMapping.swift)的 particle `.color`仍返回 nil，`.normalizedColor`已有 typed route。 | 先有实际合法定义和颜色单位合同，再复用同一 typed instruction/出生 consumer。当前逐通道平方是否符合官方不能仅由静态代码判错；不要把此输入缺口扩成全部粒子颜色错误。 |

旧usershortcut执行缺口退出：现有typed配置、真实面板和`openUserShortcut`已接入，用户确认目录、图片、音乐及App可正常打开；宽hover反馈仍归队列通用鼠标资格，不由此重开执行缺口。证据归[实际入口后验](../capabilities/runtime-evidence-current.md#user-shortcut-native-20261020)与[属性卡](properties-panel-card.md)。

## 未知项与后继维护

下列事项继续由原权威持有，本页不重复标成已证错误：

- 样本姿态/布局/光束/输入观感、精确光照与粒子 color/colorn 数值、Rope未准入atlas/world/负细分及 Vec 字符串 edge：归[断点队列](scene-open-breakpoint-queue.md)和对应 capability；旧声明、旧截图、近似代码或尚未完成官方对照不能证明当前错误。
- texture-animation wrapper 的保真与[未授权 executor](../../../MyWallpaperX/Core/SteamWorkshopScene/Format/SceneScriptBindingDefinition.swift)不独立证明播放缺陷；实际字段、返回值合同和可达 producer 尚须资格，普通 TEX 自动播放与 handle 控制另有现役链。Puppet [optional vec3 suffix](../../../MyWallpaperX/Core/SteamWorkshopScene/Format/SceneMdlPuppetMeshReader.swift)仅被校验/跳过，其含义仍未知，不据此认定 painted depth/extrusion 首错；公开能力的研究边界归[高级对象](../capabilities/advanced-object-coverage.md#op-puppet-perspective)。
- 原多 renderer/child RopeTrail 聚合项退出当前缺陷表：selector 只选一项不能独立证明应同时执行多个 authored renderer，本轮也未取得真实 child RopeTrail 请求。具体未准入组件归[粒子专项](../capabilities/particle-component-coverage.md)，须先取得精确输入和输出合同，不能靠 unsupported 数量升级；[depth-one static child Rope](../history/static-child-rope-2026-10-16.md)的正 XY 等比、独立正 Z、无 nested/world-space movement 缩放已支持，不能继续整族误报。
- [SceneScriptValueRuntime.initialize](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptValueRuntime.swift)仍有依赖 `invalid Vec3`文本的 angles兼容分支（原 M6）；当前存在性可证，但不能单凭分支存在认定其兼容语义错误。任何收敛须核[SceneScript合同](../capabilities/scenescript-runtime-implementation-contract.md)、当前有效作者模式与失败事务反例，不删除必要路径消除审计条目。
- MDLA keyed auxiliary scalar、Timeline响应/events与effect editor metadata：保真或未解释事实不自动等于播放缺失。10-18非空响应的合法Single变换组已沿唯一owner取得[基础关键帧近似及真实姿态恢复](../capabilities/runtime-evidence-current.md#single-timeline-response-fallback-20261018)，不再列U09整组冻结；平滑数学、精确phase和其他模式保持未实现/未证范围，不把这些边界改写成完整播放已支持。

每次更新只替换相应残余行：静态边界变更须核当前 caller与consumer；关闭用户现象须有同身份实际输出和相邻反例；涉及性能则遵守性能卡。测试通过、ready或一张正常图各只证明其覆盖范围，不升级为全样本正确、官方parity或专项完成。
