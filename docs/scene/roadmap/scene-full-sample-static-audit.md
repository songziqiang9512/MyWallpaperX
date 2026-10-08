# Scene 全样本能力静态审计报告

- 审计日期：2026-10-09
- 审计对象：`/Users/songziqiang/Movies/MyWallpaperX/创意工坊/Scene` 全量 243 个样本 × 本仓库当前工作树（分支 `codex/engine-refactor-program`，含约 71 个并行会话在途改动文件，按现状审查、不与 HEAD 对比）
- 审计性质：纯静态只读。未构建、未运行 App/测试/`script/run_scene_tests.py`、未运行任何 `scene_capability_census*.py`
- 输入材料：三路审查（十个能力域链路结论、六个管线阶段并存逻辑结论）、census 基线（快照 mtime 2026-10-08 02:12，清单文档提交 015ff8d6）、8 个分片逐样本重建清单（`.artifacts/scene-audit-2026-10-09/shard-1.json` … `shard-8.json`）
- 本报告位置：`docs/scene/roadmap/scene-full-sample-static-audit.md`（2026-10-09 入库；生成原址 `.artifacts/scene-audit-2026-10-09/` 与 8 个分片 JSON 属会话产物、受保留策略清理，逐样本数据已内联附录、报告自包含）
- 消费方式：作为后续待修批次的缺口/错误执行/冗余证据基线，修复选序服从兼容 P 路线；current capability 结论仍以 coverage-ledger 与各专项表为权威，本报告不修改任何登记
- 修订记录：v1.1（2026-10-09，同日修订轮）——修正 §6 合计统计（waste 37/duplicate 15/gap 1；high 3/medium 25/low 25；verified 51）、§8.4 puppet 引用合计（114，v1 误写 176）、G12 片7 样本判定口径冲突、M9 在途文件时点、§9.8 无支撑数字；补充 §2.2 输入可追溯性、§3 #2 solidlayer 可核对样本面（19 样本）、§3 #28 refraction 口径缺口、§7.7 两项未编号记录定位、§7.8 三元组含义、§7.5 新增 solidlayer/util 复算行、R9 差异展开、M2 验证路径、§1 断点清单补全（U01②/U17①/U33）与性能指引覆盖 §6.4、§1/§6 rg 核验命令留痕；全部修订均以本轮亲自执行的只读验证为据（命令内联于相应章节）

---

## 1. 执行摘要

本次对 243 个 Scene 样本（census 快照 243 = 样本库 243 = 分片重建 243，三者 id 双向差集为空，**任务所述"census 未覆盖的约 35 个新样本"在当前样本库不存在，核对结果为零新样本**）做了全量静态能力审计，汇合了能力域审查、管线阶段审查与 census 对账三路证据，并对汇总数字做了独立复算。

能力面结论：矩阵共 **54 条能力族**（对账 totals 报 53，差异见 §7.6），其中 **完整 18、部分 25、缺失 9、存疑 2**。主链健康度高于缺口面：authored 数据 → prepared Program/graph/resources → typed frame update → Metal encode → 唯一 compositor/输出的单一 owner 架构在图层、材质、脚本、时间线、渲染图、输出、Puppet 五段链上均成立，未发现按样本/路径/hash 选择视觉算法或新旧双执行 owner。问题集中在族级缺失与静默丢弃。

最重要的五条结论（给下一位修复 Agent）：

1. **9 个官方效果族无执行路由，影响 37 样本**：cloudmotion/swing/blurradial/blendgradient/nitro/reflection/refraction/skew/edgedetection 无族级派发键，无 runtime subject 时统一 `notAdmitted`（`SceneEffectStageAdmission.swift:177`）。其中 blendgradient 20 样本最广（2067939514、2134765860、2902406982 等）。cloudmotion 有例外：3748311238 派生输入链有已证执行（族级仍 L1）。我独立复算分片并集恰 37 样本，各族计数与对账一致。
2. **Perspective 的 coverage 表行声明的是退役代码**：`docs/scene/capabilities/effect-execution-coverage.md:214` 标 L3 inline-profile，但 inline owner 已随 87d254c8（基础设施）与 6b7c3fae（专用 pipeline）删除，全库无 Perspective→Opacity 四点映射；现行为 fail-closed（`SceneResolvedMaterialRuntimeCatalog.swift:383-386`），15 样本引用全部被拒。这是文档-代码漂移，修复前先改文档口径。
3. **三处"声明即静默丢弃"的整族缺失**：usershortcut 用户属性（2 样本 37 条，面板 EmptyView）；Animation Events（解析器不读 `options.events`，`animationEvent` 全仓零实现，语料唯一声明 3448877775 为空数组）；`maxtoemitperperiod` 使 3749463715 的 4 处雷电声明整 periodic profile 拒绝、零发射（`SceneParticlePeriodicEmission.swift:251`）。
4. **最高风险错误执行是 varying 死声明误删**（`SceneGenericShaderSourceNormalizer.swift:174`，high）：同名局部/参数遮蔽时可能把仍被 main 读取的全局 varying 从链接接口删除，导致 generic 编译失败回退降级；同类 scope 证明债在 `SceneAuthoredShaderGlobalReferenceAnalyzer.swift:58`。两者均队列已登记未修。
5. **性能主项在加载/编译链不在帧路径**：一次冷 variant 编译同一 fragment 源全量解析 20-30 次（`SceneResolvedMaterialGenericShaderPreparationCoordination.swift:490`，high）；GPU 纹理缓存按 loader 实例分裂约 4 个独立域（`SceneMaterialAssetTextureCatalog.swift:172`，high）；PKG 缓存命中路径验证成本接近重新解包（约三倍解包字节）。帧热路径无重解析一项本报告撰写者已亲自复跑（2026-10-09 当前工作树）：`rg -n 'JSONSerialization|Data\(contentsOf' MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/ MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/` 退出码 1（零命中）；"无每帧 PSO 编译/建图/整图哈希"的其余三条核验沿用输入材料管线阶段 4/5 审查记录（原文未附命令，Composition 目录下 `makeRenderPipelineState` 命中均为 pipeline 对象 `init?` 构造期、由懒加载仓库持有，本报告未逐一复跑消费面）。

清单规模：缺口 27 条（high 5）、错误执行 11 条（high 1）、重复/低效/多余链路 53 条（对账 totals 报 49，其中 1 条为 kind=gap 的缓存键正确性风险，见 §7.6）。census 侧 `runtime_evidence_state` 243/243 = not-joined：**本报告全部为静态结论，不蕴含任何运行验证**。

修复优先级建议：先纠正文档漂移（perspective 表行、effect-execution-coverage 表与头部两套事实、coverage-ledger 时点），再做九族执行路由的顶层设计（37 样本影响面最大、需按 §4.1 先立设计），性能项分两处收敛——launch/编译链（§6.2/§6.3 的缓存统一，含 high 级 R11）与纹理资源域（§6.4，含 high 级 R31/R32），样本级断点（U01②/U06/U16/U17①/U19/U25/U33/U40/U41，即 M9/M10/M11 与 G22/G23 点名的全部开放项）需运行复验后逐个关闭。

---

## 2. 方法、范围与边界

### 2.1 纪律与执行方式

- 只读静态审查：全部结论来自当前工作树代码行（`path:line`）、样本库与分片 JSON 的只读解析，以及输入材料中的域审查/复核记录（每条均带 confirmationNote 复核状态）。
- 未执行：任何构建（xcodebuild/swift build）、App/测试/`script/run_scene_tests.py`、`script/scene_capability_census*.py`（禁项）。census 快照的守恒结论来自只读解析其 `validation` 节，非 verify 子命令。
- 未做任何 git 写操作；工作树约 71 个在途改动文件按现状审查，未与 HEAD 对比。
- 样本库 `/Users/songziqiang/Movies/MyWallpaperX/创意工坊/Scene` 只读；涉及解包核验的复核（域审查者）均使用 /private/tmp 临时副本并已删除。
- 本报告撰写者（报告 Agent）的独立复算：用 `python3` 只读解析 8 个分片 JSON，复算了 kind 样本分布、九族/transform/perspective/workshop 引用并集、puppet 声明、script/timeline/user-property 计数、附录 puppet 引用合计与 §6 类型/严重度分布（结果与差异见 §7.5 对照表及 §8.4；修订轮新增的复核命令均内联于相应章节文字）。复算脚本为会话内 heredoc 一次性执行、**未留档**（本次任务仅授权写入报告这一个文件），判定逻辑以文字记录：effects 字段按片适配 files/unique_files/distinct_files/instance_files/effect_file_unique/effects_unique 六种键、layers 按片区分 by_kind 嵌套与 flat 计数（部分片显式列出值 0 的 kind 键，须用 >0 过滤）、puppet 判定字段按片号为 puppet_model_refs_unique/puppet_models/puppet_key_occurrences/models.puppet_models（片 1/6/7 无专属判定）。

### 2.2 输入材料可追溯性（修订补充）

- **可回溯到文件的输入**：8 个分片清单（`.artifacts/scene-audit-2026-10-09/shard-1.json`…`shard-8.json`）；census 快照 JSON（`.artifacts/scene-evidence/census/scene_capability_census_snapshot.json`，路径由输入复核记录间接给出、未入库 git）与清单文档（`docs/scene/capabilities/scene-corpus-capability-inventory.md`，最后提交 015ff8d6）；断点队列 `docs/scene/roadmap/scene-open-breakpoint-queue.md`；各 capability coverage 文档（正文以 path:line 引用）。
- **无法回溯到文件的输入**：三路审查结论（十个能力域链路结论、六个管线阶段并存逻辑结论）、对账汇总（矩阵与三张清单，含 totals）以及每条发现的 confirmationNote 复核记录，均以任务内嵌 JSON 文本提供、未附落盘路径——本报告对其的一切引用（含 §7.6 的 totals 差异）只能回溯到该内嵌文本本身，无法进一步回源。分片 JSON 是三路之外唯一可独立复核的逐样本数据源，本报告的独立复算（§7.5）均基于它。

### 2.3 样本口径

- 样本基数：243 个目录（`ls` 实测，仅 `.DS_Store` 一个非目录文件）= census 快照 243 = 8 片重建 243 id（python3 逐 id 比对，双向差集均为空）。
- 容器形态：PKGV0001×8 至 PKGV0025×23（任务描述"PKGV0001"不准确，全库跨 25 个版本）；3766415113 主包为 `gifscene.pkg`（census.py:157-159 同口径）。
- census 基线时点：快照 JSON 无内嵌时间戳，锚点为文件 mtime 2026-10-08 02:12 与清单文档提交 015ff8d6（2026-10-08 02:33:53 +0800）。台账 `coverage-ledger.md` 系统总表是另一时点（2026-09-01 核对），两文档数字不可直接互对。
- 8 片分片 schema 各不相同（dict/list/嵌套/计数四种形态，片 5/7 无 parse_state、片 7 无 condition 计数、片 1/6/7 无 puppet 专属判定），本报告附录已逐片适配；schema 不统一本身是后续对账风险。

### 2.4 边界（静态不可判定项）

- 运行态完全未 join：census 243/243 `runtime_evidence_state=not-joined`、`first_blocker=unknown`；样本是否可运行、视觉是否正确不在本报告裁决范围。
- pkg 为压缩容器：2D lit 受光样本量、多 renderer 系统数、render-state translucent/additive 样本级量、rgba16f 引用等未全量解包扫描（部分域审查者做了局部临时解包）。
- 声明 ≠ 运行支持：observed/resolved/文件存在/repair_state 均不等于 renderer 已支持（inventory §2 口径）。
- 全部"verified/unconfirmed"状态沿用三路审查的复核结论，本报告不将 unconfirmed 升级为 verified。

---

## 3. 能力覆盖矩阵

54 条能力族（对账 totals 记 53，差异登记于 §7.6）。状态列：**完整**=端到端执行链闭合；**部分**=有执行链但存在登记缺口/降级面；**缺失**=声明后无执行路径；**存疑**=静态无法判定。复核列指域审查后的独立复核状态（confirmed=已复核成立；如无则为汇总口径）。

| # | 能力族 | 准入/解析证据 | 样本口径（census/分片） | 执行证据 | 状态 |
|---|---|---|---|---|---|
| 1 | layer.image-static-compose | SceneDocument 解析 objects[]→contentKind 判定（`SceneRenderDescriptor.swift:328-365`） | 243 样本/3068 对象（快照 object_kind_counts，与分片逐项一致） | encodeImageLayer→SceneLayerColorBlendRenderer，唯一 compositor `SceneImageLayerCompositor.swift:81` drawOutcome | 完整 |
| 2 | layer.solid（作为 image 源形态） | census 8 类对象 kind 不含 solid；solid 以 image 层引用 stock `models/util/solidlayer.json` 形态出现 | 0 独立 kind（solidlayer 以 stock model 引用计入 resource 域）。**可核对样本面（修订补充，我复算片4）**：引用 `models/util/solidlayer.json` 19 样本/17 处（3395777145、3396722575、3420215721、3437487219、3448845950、3448877775、3470948192、3472940912、3509243656、3554161528、3563038726、3581882134、3587571382、3589454154、3601964477、3603711180、3610154602、3612199597、3612795410），另有 solidlayer_depthtest 5 处；util stock model 整体（含 composelayer/fullscreenlayer）23 样本——输入记"22 样本引用 util stock model"，与我的 23 差 1，如实登记。附录未逐行标出 solid 形态（分片仅片4 记录该口径），本行 id 清单即其可核对面 | 与 image 同链（ColorBlend compositor） | 完整 |
| 3 | layer.text-coretext | text contentKind（`SceneRenderDescriptor.swift:328-365`） | 126 样本/1086 对象 | `SceneTextTextureLoader.swift:333-378` 栅格化（outline/dropShadow/background）+动态属性重栅格 | 部分（U16 3122339805/U25 3351163962 布局断点开放，断点队列 :97,:106） |
| 4 | layer.sound-playback | `SceneSoundPlaybackProgram.swift:135-168` admission（paths/playbackmode/startsilent/volume/spatialization） | 81 样本/114 对象 | 唯一 AVQueuePlayer registry，FLAC/MP3/WAV loop/single+音量热更 | 部分（muteInEditor/mintime/maxtime 解析后无消费，114 层全声明） |
| 5 | layer.utility-composition | `SceneUtilityLayerRuntimePlan.swift:128` 等三处 gate（passthrough 仅作拒绝条件） | 39 样本/701 对象 | capture/group runtime→graph/compositor（composition/fullscreen/project） | 完整（passthrough 语义无执行但语料 160 层全 childless，影响 0） |
| 6 | layer.shape-quad | `SceneRenderDescriptor.swift:361-364` 仅 shape=="quad" 判 quad contentKind | 16 样本/22 对象（22/22 全 quad） | resolved-material direct draw | 部分（非 quad 值静默折叠 container，语料 0 层实际影响） |
| 7 | layer.camera-path | camera descriptor 共享帧（唯一 default-camera 权威） | 12 样本/12 对象 | bounded 2D origin/zoom Combined + perspective FOV | 完整（bounded） |
| 8 | layer.light 四类灯 | `SceneLightSnapshot.make` 唯一准入（`SceneMetalRenderer+SceneDrawing.swift:83`，lightconfig 按类门控+四槽预算） | 8 样本/19 对象 | `SceneStaticModel.metal` / `SceneLitImageLayer.metal` / `SceneSpotLightPipeline` 三条执行路 | 部分（point volumetrics、白名单外灯型缺） |
| 9 | static-model.direct | `SceneMdlStaticModelReader.readParts`→`ScenePreparedStaticModelResources.swift:82-88` 准备 GPU mesh/材质 | resource 域 243 样本；8 片 243/243 记录 image→model 引用 | `SceneStaticModelPipeline.draw/shadow`（仅 passIndex==0 材质 pass） | 部分（自定义 shader L0、方向光响应线性近似） |
| 10 | layer.particle | `SceneParticleAssetGraph` 材质/genericparticle/render-state/纹理准入 | 164 样本/761 root layer（=cap.particle.runtime 164，分片复算一致） | `SceneParticleSimulator` 固定 1/60→`SceneParticleMetalPipeline` 单管线 | 部分（collision/多 renderer 等多族 L0/L1） |
| 11 | light.model-lit(directional/point/spot+shadow) | `SceneLightSnapshot.swift:131-161`（lightconfig 门控+四灯预算，visible 不再过滤灯） | 19 occ/8 样本 | `SceneStaticModel.metal:376-425`（k=0.30 线性 NdotL+三类阴影）；角度/衰减公式源自官方黑盒对照（`docs/scene/history/static-model-light-input-semantics-2026-10-06.md:11`） | 部分（方向光凸增曲线等精确子项待复验，断点队列 :144） |
| 12 | light.2d-lit(point/spot 受光) | `SceneLitImageLayerPipeline.swift:231-244` packLights（签名仅 point/spot/ambient） | 受光 2D 图样本量 pkg 压缩未证实（灯光域自记 8 样本口径） | `SceneLitImageLayer.metal:323-335`（2D 点光 k≈1.85 平面衰减+spot+PBR/反射） | 部分（directional 零输入；2D spot/ambient 官方合同未探） |
| 13 | light.volumetric-cone(lspot) | `SceneSpotLightPlan.swift:24-27` 严格 standalone lspot 准入（数值守卫） | castvolumetrics 5 层语料：lspot 4 层/1 样本 + point 1 层 | `SceneSpotLightPipeline.swift:129-145`（内联 shader JIT 编译） | 部分（point/lpoint 声明无任何路径，见缺口 G6） |
| 14 | light.ambient-skylight-fog | `SceneDocument+General.swift:108-117` 解析→`SceneLightSnapshot.swift:229-230` 打包 | 凡带模型 207 样本 author ambient/skylight（`static-model-light-input-semantics-2026-10-06.md:13`） | `SceneStaticModel.metal:476-482`（ambient 斜坡+距离雾，仅静态模型消费） | 部分（2D 图层/粒子不受雾；ldirectional 级联阴影键无解析面） |
| 15 | particle.emitter(shape/schedule/input) | `SceneParticleDefinitionParser` loss-preserving 解析+AssetGraph 准入 | particle 域 164 样本/21256 occ/788 family | Simulator.emit（bit2/bit4 flag 消费；普通路径不查未知 flag 位） | 部分（maxtoemitperperiod 拒绝整 periodic profile，见缺口 G5） |
| 16 | particle.initializer | `Parser.swift:102-121` initializer switch | 同 particle 域 | 出生路径按作者顺序执行 | 部分（inherit CP velocity/mapsequence/remapinitial 仅诊断 L1） |
| 17 | particle.operator | `Parser+Operator.swift:10-37` operator switch 18 case | 同 particle 域 | Simulator 执行 movement/alphafade/oscillate/turbulence/vortex/boids/collisionplane-bounce 等 | 部分（collision 整族/maintaindistance 系 L0/L1） |
| 18 | particle.renderer(sprite/trail/rope/ropetrail) | `SceneParticleRuntime+Support.swift:111-172`（仅 Rope/RopeTrail 单 renderer 强制门） | 204 显式 renderer record（`particle-component-coverage.md:385`） | Sprite/Trail/Rope/RopeTrail/REFRACT/depth 共用 `SceneParticleMetalPipeline` | 部分（多 renderer 只执行第一个，sibling 无诊断丢弃） |
| 19 | particle.children+controlpoint | `SceneParticleChildTemplateSupport.swift:193-215` child 版选择器（与 root 双实现） | 同 particle 域 | child batch 装配（depth≤2/事件 spawn/death/follow；pointer 0-7 CP） | 部分（child 无 RopeTrail、失败静默 continue） |
| 20 | particle.override+audio16band | `Parser+InstanceOverride.swift:22` 解析（static/user/timeline/script-scalar） | IV13：28 条 binding/8 样本 | `Simulator+InstanceOverride.swift:22-26` 出生路径+16-band evaluator（emitter rate/turbulent phase/vortex speed） | 部分（color/colorn 平方语义未对官方核验） |
| 21 | puppet.bind-mesh+rig-lbs | `SceneMdl*` 四版本 reader→`ScenePuppetLayerLoad.swift:35` 准入 | ≥31 样本声明（片2/3/4/5/8 专属口径 150 样本中 31，我复算一致；二进制级复核 57 样本含 MDLV） | `ScenePuppetAnimationEvaluator` LBS（四权重归一，T*Rz*Ry*Rx*S） | 完整（bounded） |
| 22 | puppet.animation(clip/mix/alpha/mdla) | `ScenePuppetAnimationSelector.swift:63-64`（blendIn/Out 准入门） | 同 puppet 集 | Evaluator+PlaybackState（单 clip/静态权重分层混合/逐骨 alpha/play-pause-stop-setFrame 句柄） | 完整（MDLA0006 keyed auxiliary 丢弃，见缺口 G16） |
| 23 | puppet.attachment-mdat | `SceneMdlPuppetAttachmentReader.swift:89` 逐帧 current+bind 回退 | 同 puppet 集 | `ScenePuppetAttachmentPoseProjection.swift:46-47`（F*M*F 投影） | 完整（Y 轴共轭双实现，见冗余 R47） |
| 24 | puppet.physics | `SceneMdlPuppetRigReader.swift:46-48`（r/ge/ik 即 throw→该骨 physics=nil 本地降级） | 同 puppet 集；断点队列 :141 开放 | `ScenePuppetPlaybackState.swift:426-452` 仅平移 spring/rigid 闭式积分 | 部分（旋转/重力/IK/applyBonePhysicsImpulse L0） |
| 25 | puppet.part-clipping | `ScenePuppetClipping`（ordinal/index/mask 约束） | 同 puppet 集 | draw-part/clip-record+R8 paint，nested 拓扑 | 完整 |
| 26 | puppet.perspective-extrusion | `SceneMdlPuppetMeshReader.swift:283-294` 校验 byteCount 后跳过（opaque） | puppet 样本全集；带 vec3 后缀流的资产未从二进制判定 | `ScenePuppetAnimationEvaluator.swift:109` bindPoint z=0；`advanced-object-coverage.md:81` L0 | **缺失** |
| 27 | effect.generic-34 族（L3 有界 profile） | `SceneResolvedMaterialExecutionCapabilityCatalog.compileStages`：48 generic route profile（`SceneResolvedMaterialGenericShaderRouteAuthority.swift:6-59`：46 generic-only+1 prefer+1 observe） | effect 225 样本/5071 实例；34 族文件引用 216 样本（分片并集） | `SceneResolvedMaterialGraphExecutor.encode` 唯一编码+boundedSwift 前端回退，失败 effect-local passthrough | 完整（有界 profile） |
| 28 | effect.L0/L1 九族（cloudmotion/swing/blurradial/blendgradient/nitro/reflection/refraction/skew/edgedetection） | `SceneEffectStageAdmission.swift:177-184` 无 runtime subject 即 notAdmitted/unified-capability-unavailable；引擎无族级派发键 | census 可见口径：reflection 22 occ/3 样本、blendgradient 14/4、swing 7/6、blurradial 4/3、nitro 3/2、cloudmotion 2/2、skew 2/1、edgedetection 0 可见；**输入未提供 refraction 的可见口径（是否为 0 未说明），54 occ 的构成无法完整核对**；断点队列 :159；**分片文件引用并集 37 样本（我复算一致：refraction 2 样本）** | 无族级执行；cloudmotion 例外：3748311238 派生输入有已证执行（族级仍 L1） | **缺失** |
| 29 | effect.transform | `SceneScriptVectorCandidateCatalog.swift:802-813` passVectorProjection→provisionalSceneScriptValueTargets（`Host+Launch.swift:312-315,440-443`） | census 35 可见引用/4 样本；分片官方 transform 族文件引用 **7 样本**（我复算，对账记 8，见 §7.5） | QuickJS typed Vec2 owner：2067939514 的 25 个 scale attachment 全成 owner（`coverage-ledger.md:57` 权威口径） | 完整（复核推翻"全部被拒降级"旧口径） |
| 30 | effect.perspective | `SceneResolvedMaterialRuntimeCatalog.swift:383-386` 声明 perspective 即 reject shape-unsupported（fail closed） | census 24 可见引用/7 样本；分片文件引用 15 样本（我复算一致） | 无：inline owner 已随 87d254c8 删除，全库无四点映射；coverage 表行 L3 为漂移 | **缺失** |
| 31 | effect.workshop 跨作品引用 | effect.json 加载缺失/失败即 fail-closed（unknownFieldPaths 硬 blocker，不静默） | census 快照不区分本地/跨作品引用（口径缺口）；分片 workshop 路径引用 134 样本（我复算，对账 corpusSamples=133，见 §7.5） | 视包内是否存在：如 2067939514/2134765860 引 workshop/2084198056 Simple_Audio_Bars 等本地不存在（分片1 unresolved） | 存疑（跨作品依赖不在样本包内，实际执行面未定） |
| 32 | material.ordinary-shader(48 profile) | `SceneAuthoredMaterialResolver.swift:126-141` 固定 8 槽合并→TemplateCompiler typed 编译 | material 域 243 样本/9354 occ/52 family | generic artifact（签名 glslang→SPIRV-Cross 子进程）+bounded Swift 前端回退，同一 program 不双编译 | 完整 |
| 33 | material.source-material(单 pass 源材质) | 两条准入链按 authored blending 分流：`SceneBaseMaterialColorModulationCompiler.swift:87-92`（translucent lowering）与 `SceneResolvedMaterialRuntimeCatalog.swift:442-456`（normal 才放行 Program） | 同 material 域 | compositor tint lowering / source-material→Program（T1 登记的有意分流，无重复求值） | 部分（translucent/normal 两半互斥，各自受限） |
| 34 | material.render-state(GPU 下放) | `SceneMaterialRenderState.swift:97-103` supportsResolvedMaterialFullscreenOverwrite 谓词（5 处强制） | shader 229 样本；stock 非 preview 材质 197 additive/207 translucent/205 normal（rg 只读扫描） | 谓词外（translucent/additive/enabled depth 等）renderStateRejected 整链拒绝（`SceneResolvedMaterialPassEncoder.swift:515-517`），L2 登记（`render-graph-shader-coverage.md:508`） | 部分 |
| 35 | material.3D-model-custom-shader | `SceneStaticModelMaterialBindingCompiler.swift:3`（注释自认不执行 custom shader program；仅三接口进固定通道） | 分片8：3589454154 24 个 .dxs、833227004 5 个 .dxs（loose blobsSM40，我 ls/file 复核计数一致） | 无：`ScenePreparedStaticModelResources.swift:109-112` 仅 passIndex==0 固定通道；.dxs 仅计数警告（`SceneDiagnostics.swift:84`） | **缺失** |
| 36 | material.texture-sampling-tokens | `SceneGenericShaderTextureSamplingNormalizer.swift:82-87` 仅 4 条 #define | shader 229 样本；官方语料 compare 27 occ、texSample3D 2、backbuffer 1、clip 7（prelude §2 口径，引自输入材料） | Compare/3D/BackBuffer/clip 无展开，含该 token 的 shader glslang 阶段失败关闭 | 部分（token 族 L0） |
| 37 | scenescript.value-owners(scalar/bool/vec2/vec3/string) | 四族投影仅认 object/effect/pass/animationLayer owner（`SceneScriptVectorCandidateCatalog.swift:331-764`、`ScalarProgram+Projection.swift:85/168`、`StringProgram.swift:708`、`CursorProgram+Construction.swift:286`） | script wrapper 141 样本/3895 occ（分片复算一致） | QuickJS-NG 单域四族 owner（journal/surface commit、OOM 整域拒绝、exact-once teardown） | 完整（bounded；Vec4/matrix L1） |
| 38 | scenescript.scene-general 脚本 | `SceneScriptBindingDefinition.swift:254-273` 解析 owner.kind==.scene 进 IR | 分片唯一已知 scene 级声明：2134765860 有 1 处 objects 之外 script 键（scene 级总量未从分片分离） | 无：四族投影不消费 scene owner，仅 `SceneScriptSourceEvidence.swift:4` 留溯源（'never grants execution'） | **缺失** |
| 39 | scenescript.events(19 官方 slot) | `SceneScriptValueRuntime.swift:181-208` 构造期探测（media4+applyUserProperties+init/update/destroy+cursor6） | 同 script 域；mediaStatusChanged/hitBox/buttonIndex 语料 0 引用 | `SceneQuickJSMediaEventHost.c:523-719` 按名派发已实现事件 | 部分（resizeScreen/applyGeneralSettings/animationEvent/mediaStatusChanged 永不派发） |
| 40 | scenescript.handles(layer/effect/animation/texanim/video/particle/puppet-bone) | module 期注册（`SceneQuickJSLayerHost.c` 等） | 同 script 域 | typed handle 执行（mutations/播放控制/emitParticles/bone io） | 完整（bounded） |
| 41 | scenescript.texture-animation-wrapper | `SceneScriptBindingDefinition.swift:53-71` 全保真解析（doc comment：inert） | 分片未分离该 wrapper；域审查自记样本数未测 | 仅 presence 消费：`SceneDesktopWallpaperHost+DeferredBaseImages.swift:30`、`SceneParticleLayerImageEmitterCompiler.swift:81` 的 isEmpty | **缺失**（wrapper 通道；API handle 链独立完整） |
| 42 | timeline authored 动画(layer-transform/effect-constant/particle/text/camera/lspot) | `SceneTimelineTargetCompiler.swift:63-87`+`Scene2DCameraTimelineCompiler`（fail-closed 逐条诊断） | timeline wrapper 70 样本/475 occ（分片复算 70 一致） | `SceneTimelinePlaybackRuntime` 唯一状态机+Evaluator（Bézier/single/loop/mirror/wraploop）→动态快照→typed consumer | 完整 |
| 43 | timeline options(events/name/magic/smoothing) | parseOptions 不读 events/name（`SceneTimelineAnimation.swift:209-245`）；tangent.magic/smoothing/stiffness 解析或保留后无消费 | events 1 处（3448877775 空数组）、name 32 处、magic 1830 处、非空 smoothing/stiffness 9 处（3797217144） | 无：animationEvent 全仓零实现；断点队列 :163 登记 | **缺失**（Animation Events 整族） |
| 44 | timeline.general-bloomstrength | `SceneDocument+General.swift:141` floatValue 对 dict 只读 value 键（动画子对象无解析方） | 1 样本（3810943704） | 常量 bloom（`SceneRenderDescriptor.swift:381` 消费基值；该样本基值 0，呼吸动画整体退化） | **缺失**（动画静默丢弃） |
| 45 | texture.resource+animated-sprite | `SceneTextureLoader` 多实例域加载（六处构造点，缓存域分裂见冗余 R31） | texture 242 样本/18753 occ；包内 TEX 3947（animated 52/video-mp4 4）；slot hole 3800/missing 71 | 静态/animated TEX 声明播放（`SceneTextureAnimationPlaybackRuntime.swift:1-5`）+SceneScript API 控制；内嵌 WebM 视频 TEX 不能出帧（U06，断点队列 :87） | 部分 |
| 46 | user-property 六类型(bool/slider/color/combo/textinput/texture) | `SceneUserPropertyDefinitionParser.swift:27-31`+`SceneUserPropertyBindings`→typed target | project-property 243 样本/4887 occ；分片：color 243/slider 116/bool 154/combo 59/text 45/group 40/textinput 37/scenetexture 21 | `ScenePropertyBindingCompiler`→live/重建分治→帧快照→真实消费方（GraphExecutor effectConstant:604、Bloom、Sound、Light、camera） | 完整 |
| 47 | user-property.usershortcut | `SceneUserProperty.swift:4-14` 枚举无 case→解析落 .unsupported | 2 样本/37 条（3589454154×17、3662790108×20）；`coverage-ledger.md:262` L0 | 无下游：面板 EmptyView（`SteamWorkshopScenePropertyEditorView.swift:97`），无 openUserShortcut/isbound/file/icon | **缺失** |
| 48 | user-property.texture 替换(视频入口) | `SceneUserPropertyTextureLoader.swift:77` supportedFileExtensions=[png,jpg,jpeg] | 21 样本/87 处声明（域审查口径）；分片 scenetexture 21 样本/31 处（不含 'texture' 拼写变体，口径差） | PNG/JPEG 替换+base-material slot0+script property；视频无路径（:176 video payload 拒绝） | 部分（U41 开放，断点队列 :122） |
| 49 | media/audio(events/thumbnail/live-source/spectrum) | requiresSystemMedia 需求驱动 acquire（`SceneDesktopWallpaperSession.swift:196-204`，Apple Music+SceneMediaObserver 偏好门控） | audio-declaration 184 样本/2092 occ（editor 标记 128/静态意图 86/runtime-confirmed 0） | 4 media 事件+封面 current/previous 双消费+16/32/64 频谱 host 快照（Program uniforms+QuickJS AudioBuffers） | 完整（静态口径；mediaStatusChanged L0、运行态未 join） |
| 50 | pointer-cursor-camera(parallax/shake) | `SceneDesktopWallpaperSession+PointerEvents.swift:27-29`（仅左键 mouseMoved/leftMouse* mask） | cursor worldPosition 267 处/36 样本；cameraparallax=true 36 样本（域审查） | 6 cursor 回调+capture-click 状态机+视差（depth 传播+smoother）；hitBox/buttonIndex/右键缺 | 部分 |
| 51 | render-graph(FBO/copy/swap/compose/previous/clear/unique) | `SceneAuthoredEffectRenderPlanner` 结构准入+`SceneGraphAdmissionCompiler.swift:209` 条件剪枝（缺证明 fail closed） | render-graph 225 样本/6302 occ/28 family；render-target 113 样本/804 occ/8 family | `SceneGraphExecutionState` 事务（hazard 检查）→`ResourcePassEncoder` blit/一次性 clear/lit-unlit capture；官方 previous/compose/copy/swap/clear/unique 语义落地 | 完整（rgba16f 显式格式字符串拒绝，语料引用未证实） |
| 52 | render-output(sceneColor→bloom→display mapping→drawable) | sceneColor→display scratch 唯一路由 | 输出链全局生效；bloom/hdr 声明样本未全片统计（片5：31/31 含 bloom/hdr general flag） | encodeTerminalColor（`SceneMetalRenderer+ClearColor.swift:153`）：bloom→display mapping→sceneColor 导出 | 完整 |
| 53 | output.color-continuity(透明RGB) | effect 段已落 straightAlpha/premultiplied/signal 三表示（`SceneResolvedMaterialProgram+ColorDerivation.swift:268-630`，commit 9ecbea35） | effect graph 225 样本；U19 3807668787 点名 | 部分：源上传/capture 仍 PMA（`SceneImageTextureUploader.swift:244-252` premultipliedLast；并行在途改动已开始把普通加载改 straightAlbedo——`SceneBaseImageTextureLoad+Ordinary.swift:9`）；U19 灰冠开放（断点队列 :34,:100） | 部分（第二卡在途） |
| 54 | audio-declaration(material audio bars 静态意图) | transform 24 可见引用走 source-material 准入（无族级 owner） | 静态 consumer 意图 86 样本；runtime-confirmed 0 | audio-stage-uniform profile（audio bars）+16/32/64 host 快照链路存在；逐样本运行证据未 join（census boundaries） | 存疑（静态链在、运行态未证） |

矩阵合计：完整 18（#1,2,5,7,21,22,23,25,27,29,32,37,40,42,46,49,51,52）、部分 25、缺失 9（#26,28,30,35,38,41,43,44,47）、存疑 2（#31,54）。

---

## 4. 加载/执行缺口清单（27 条）

格式：编号 | 能力族/问题 | 影响面（样本数与举例 id） | 缺失环节 | 证据 | 严重度 | 复核状态。复核状态沿用三路审查独立复核结论；影响面数字以复核修正后口径为准（与原始发现不一致处在备注说明）。

### 4.1 高严重度（5 条）

| # | 能力族/问题 | 影响面 | 缺失环节 | 证据 | 严重度 | 复核 |
|---|---|---|---|---|---|---|
| G1 | 9 个官方效果族无族级执行路由 | 分片文件引用并集 37 样本（我复算一致：blendgradient 20（2067939514/2134765860/2902406982 等）、swing 8（含 3810943704）、blurradial 4（3420215721 等）、reflection 4（2813231542/3299228616/3363252053/3396722575）、refraction 2（3662390671/3792249095）、nitro 2（3788467391/3792400801）、cloudmotion 2（3448845950/3748311238）、skew 1（3264246690）、edgedetection 1（3603711180））；census 可见口径约 54 occ/21 样本（复核仅能部分复现，见 §7.5） | 无 subject 即 notAdmitted/unified-capability-unavailable；族级派发键不存在 | `SceneEffectStageAdmission.swift:177`、`SceneResolvedMaterialExecutionCapability+Stages.swift:20-27`、`docs/scene/capabilities/effect-execution-coverage.md:96`、断点队列 `scene-open-breakpoint-queue.md:159` | high | verified（复核 rg 七族名零命中、reflection/refraction 命中均为无关域；例外 cloudmotion 3748311238 派生链已证执行） |
| G2 | Perspective 效果 inline owner 已删除，coverage 表行 L3 声明退役代码 | 分片 perspective 文件引用 15 样本（我复算一致：2134765860、3747492842、3788897599、3796588443 等）；census 24 可见/7 样本 | 全库无 Perspective→Opacity 四点映射实现；现行为 fail-closed（usesPerspective!=true 即 reject shape-unsupported） | `docs/scene/capabilities/effect-execution-coverage.md:214` 对照 git 87d254c8（删 EffectExecution 基础设施）+6b7c3fae（删专用 pipeline，复核归因修正）；`SceneResolvedMaterialRuntimeCatalog.swift:383-386` | high | verified（复核 git show 两提交、rg 全库、分片 15 样本精确复现） |
| G3 | usershortcut 七类用户属性中唯一整族丢弃 | 2 样本/37 条（3589454154×17、3662790108×20）；分片 prop 统计同得 2 样本 | 无 kind case（枚举仅 bool/slider/color/combo/textInput/text/group/sceneTexture/unsupported）、无 openUserShortcut host API、面板 EmptyView | `SceneUserProperty.swift:4-14`、`SceneUserPropertyDefinitionParser.swift:28-30`、`SteamWorkshopScenePropertyEditorView.swift:97`、`docs/scene/roadmap/scene-open-breakpoint-queue.md:163` | high | verified（复核含语料复算 2 样本/37 条与 rg openUserShortcut 零匹配） |
| G4 | Animation Events 整族缺失 | timeline 70 样本；唯一声明 3448877775（events=[] 空 payload，scene.json objects[68].color.animation.options），现存语料零实际触发 | 解析器不读 options.events；animationEvent 回调全仓零实现（QuickJS 宿主回调为封闭名单，无数据驱动派发） | `SceneTimelineAnimation.swift:209-245`（parseOptions 只取 mode/fps/length/parent/children/startpaused/wraploop/smoothing/stiffness）、`docs/scene/capabilities/runtime-systems-reference.md:281` 官方合同、断点队列 :163 | high | verified（复核含 242 pkg 全量只读扫描 events 键恰 1 处） |
| G5 | maxtoemitperperiod 即拒绝整个 Random periodic profile，emitter 零发射 | 1 样本 4 处声明（3749463715 根 405/412+两深层 child），整层（雷电发射层）零发射；复核修正原"≥2 样本"口径 | per-period 数量上限只有拒绝语义、无执行路径；scheduledActiveDuration 归零、emitExplicitly 同被阻断 | `SceneParticlePeriodicEmission.swift:251`（guard 要求 maximumEmissionCount==nil 否则 .unsupported）、`SceneParticleSimulator.swift:584-587`、`SceneParticleDefinition.swift:60`、断点队列 :140、`runtime-evidence-batches-through-2026-10-03.md:290` | high | verified（复核含只读解包 3749463715 逐条核对 guard 链；注：两深层 child 的 delay=9999 同时违反 3600s 上界，队列 :133 另列独立缺口） |

### 4.2 中低严重度（22 条）

| # | 能力族/问题 | 影响面 | 缺失环节 | 证据 | 严重度 | 复核 |
|---|---|---|---|---|---|---|
| G6 | point/lpoint 光的 castvolumetrics/solid 静默丢弃 | point/lpoint 子集 1 层（3287715210 objects[5] id=85 light=lpoint castvolumetrics=true）；3768903841 的 4 个 lspot 有链不受影响；全语料 castvolumetrics 5 层（1 lpoint+4 lspot） | 解析进 typed definition 后无任何产品消费方（SceneLightSnapshot.Point 结构无该字段；唯一消费 SceneSpotLightPlan 仅 lspot） | `ScenePointLightDefinition.swift:29,31`、`SceneLightSnapshot.swift:17-28,345-366`、`SceneSpotLightPlan.swift:26-27` | medium | verified |
| G7 | 2D lit image 完全不消费方向光 | light 8 样本中带 LIGHTING 材质 2D 图+l_directional 的子集（pkg 压缩未证实） | packLights 签名仅 point/spot/ambient；LitCapture 不传 directional；MSL 端 payload 镜像无 directional 槽位（ABI 级缺失） | `SceneLitImageLayerPipeline.swift:231-244`、`SceneLitImageLayer.metal:28-67`、`SceneResolvedMaterialFramePreflight+LitCapture.swift:102-136`、`2d-lit-image-light-contract-2026-10-06.md:37` 官方合同未探 | medium | verified（含全消费链 rg 穷尽） |
| G8 | general.bloomstrength 上的作者 Timeline 静默丢弃 | 1 样本：3810943704 bloom 呼吸动画（三关键帧 loop，峰值 1.36）整体退化为常量 0，等效 bloom 不可见 | floatValue 对 dict 只读 value 键，animation 子对象无解析方；Timeline 解析入口三处均不含 general 节点 | `SceneDocument+General.swift:141`、`SceneDocument+NumericParsing.swift:28`、`SceneRenderDescriptor.swift:381` | medium | verified（含只读解包确认 c0 三关键帧） |
| G9 | scene general.* 脚本 wrapper 解析进 IR 后无消费者 | 分片唯一已知 scene 级声明：2134765860 有 1 处 objects 外 script 键（/general/bloomstrength，audio 脚本 wrapper）；scene 级总量未从分片分离 | 四族投影只认 object/effect/pass/animationLayer；scene owner 仅取证收集器留溯源（'never grants execution'） | `SceneScriptBindingDefinition.swift:254-273`、`SceneScriptScalarProgram+Projection.swift:78-83`（guard objectIndex 非空）、`SceneScriptSourceEvidence.swift:25`、`scenescript-api-coverage.md:291-300` | medium | verified（含 2134765860 解包复算：全文档 32 script 键、objects 外 1） |
| G10 | texture-animation wrapper 脚本仅 presence 消费 | 所有用脚本 wrapper 驱动纹理动画的层；API handle getTextureAnimation 是另一条已实现链；分片未分离该 wrapper，样本数未测 | 全保真解析后仅两处 isEmpty 判断；无字段级消费、无执行器 | `SceneScriptBindingDefinition.swift:45-86`、`SceneDesktopWallpaperHost+DeferredBaseImages.swift:30`、`SceneParticleLayerImageEmitterCompiler.swift:81` | medium | verified |
| G11 | 3D 模型自定义材质 shader 无执行链 | 2 样本：3589454154 shaders/blobsSM40 24 个 .dxs、833227004 5 个 .dxs（loose，ls/file 复核计数一致） | 仅 g_TintAlpha/g_TintColor/g_Brightness 三接口降到固定模型 renderer；.dxs blob 不转译（仅分类+警告"Metal 转译尚未实现"） | `SceneStaticModelMaterialBindingCompiler.swift:3-4`、`ScenePreparedStaticModelResources.swift:109-112`、`SceneResourceIndex.swift:87`、`SceneDiagnostics.swift:84`、断点队列 :68 | medium | verified |
| G12 | Puppet perspective/extrusion 整体未执行 | puppet 声明样本≥31（分片可判定口径 31，见 §8.4；域审查自记清单为 2797913147/2804817823/2917306763/2959875782/3723344874×17/3787382101/3791967416/3806337293/3807668787/3810943704×7/3811154012）。**口径冲突说明**：3787382101、3791967416 位于片 7（无 puppet 专属判定，附录标 pup?），且本报告修订时查其片 7 model_refs 无 puppet 命名文件（3787382101 为 背景/巨剑/composelayer/人物 等，3791967416 为 solidlayer/composelayer/背景花 系列），这两个 id 的声明依据仅来自域审查自记、无法从分片复核；两清单并集 ≥33 样本，"≥31 为下界"仍成立；带 vec3 后缀流资产未从二进制判定 | MDLV0023 optional vec3 流读 byteCount 校验后跳过（opaque）；蒙皮时顶点 z 硬编码 0 | `SceneMdlPuppetMeshReader.swift:283-294`、`ScenePuppetAnimationEvaluator.swift:109`、`advanced-object-coverage.md:81` | medium | verified（含二进制级 57 样本/255 MDL 复算；注：分片引用乘数与唯一 mdl 数口径不一，如 3723344874 引用 17/唯一 9） |
| G13 | sound 层 muteInEditor/mintime/maxtime 解析后无消费 | 81 样本/114 sound 层全声明；例 3603711180（7 层）、3088601835（多音轨） | admission 只消费 paths/playbackmode/startsilent/volume/spatialization；三字段全仓消费点为零，均无诊断静默保真 | `SceneDocumentObject.swift:90-94`、`SceneSoundPlaybackProgram.swift:148-151` | low | verified（图层域；断点队列无对应条目，属本次新发现） |
| G14 | timeline 序列化字段静默丢弃 | 随包 name 32 处、magic 1830 处、非空 smoothing/stiffness 9 处（3797217144） | parseTangent 只读 x/y/enabled；smoothing/stiffness 解析后求值器零消费且注释过时（:65 仍称全 null） | `SceneTimelineAnimation.swift:64-66,327-354`、断点队列 :163 | low | verified（动画域，样本统计独立复现） |
| G15 | 骨骼物理仅平移 spring/rigid | 同 puppet 样本集；原包运行记录 TypeError: not a function（runtime-evidence-batches:448） | r/ge/ik 启用即该骨物理 fail-closed（physics=nil 本地降级，骨骼保留蒙皮——复核修正"拒物理非拒整骨"）；旋转/重力/IK 与 applyBonePhysicsImpulse 无实现 | `SceneMdlPuppetRigReader.swift:43-48`、`ScenePuppetPlaybackState.swift:426-452`、断点队列 :141 | medium | verified |
| G16 | MDLA0006 keyed auxiliary 标量轨道校验后丢弃 | MDLV0021/MDLV0023+MDLA0006 且携带该轨道的资产（数量未普查） | 逐值校验 0…1.0001 后仅 cursor += expectedBytes；IR 无对应字段 | `SceneMdlPuppetAnimationReader.swift:392-414`、`SceneMdlPuppetAnimation.swift:8-16` | medium | verified |
| G17 | 粒子整族 L0/L1 缺口 | 164 粒子样本（3780119725 1007 组件、3299228616 690、3396722575 567 等） | collision response 仅 Plane bounce；sphere/bounds/quad/model collision、Remap Initial、Inherit CP Velocity、Position Between CPs、Maintain Distance 系、CP world-space、Layer Image 颜色/运动继承与动态 bitmap 更新均无执行路径 | `SceneParticleDefinitionParser+Operator.swift:10-37`、`Parser.swift:102-121`、coverage E16/E17/I08/I14/I15/O12-O25 | medium | verified（全仓 rg 零匹配排除绕过路径） |
| G18 | 多 renderer 系统只执行第一个 supported renderer | 164 粒子样本；分片不记录 renderer 组合，无法给出样本 id（静态盲区）；coverage §13：语料 204 个显式 renderer record | sprite/spriteTrail 分支 if supported==nil 丢弃后续 supported sibling，无 addDiagnostic；trailRendererIgnored 无产生点 | `SceneParticleRuntime+Support.swift:111-116`、coverage R05 自认 fail-closed 非双输出能力 | medium | verified |
| G19 | shape 对象类型只识别 quad | shape 16 样本/22 层全部 quad（分片+域审查 244 pkg 扫描一致），当前语料 0 层实际影响 | 非 quad 声明静默折叠为 container，无诊断无绘制 | `SceneRenderDescriptor.swift:361-364` | low | verified |
| G20 | 采样/内建宏只覆盖 4 种 | shader 229 样本域；官方语料 compare 27 occ、texSample3D 2、backbuffer 1、clip 7（prelude §2 口径，引自输入材料，未独立复扫） | texSample2DCompare/texSample3D/texSample2DBackBuffer 与 clip 无展开，含这些 token 的 shader 在 glslang 阶段失败关闭 | `SceneGenericShaderTextureSamplingNormalizer.swift:82-87`、`SceneGenericShaderSourceNormalizer.swift:360-395` | low | verified |
| G21 | authored blending=translucent/additive 的 effect 材质 pass 无 resolved Program 执行路径 | stock 非 preview 材质 197 additive/207 translucent（rg 只读扫描）；样本级量未统计（pkg 压缩） | 全屏 overwrite 谓词只收 normal/disabled/nocull；谓词外 renderStateRejected 整链拒绝（同一谓词 5 处强制） | `SceneMaterialRenderState.swift:97-103`、`SceneResolvedMaterialPassEncoder.swift:515-517`、`render-graph-shader-coverage.md:508` L2 登记 | medium | verified（渲染图+材质双重复核；粒子链与模型 tint lowering 另覆盖部分 translucent） |
| G22 | 用户纹理属性替换只支持 PNG/JPEG，无视频入口 | 21 样本/87 处 texture 属性声明（域审查 project.json 口径）；U41 点名 3357627941（2 处） | supportedFileExtensions=[png,jpg,jpeg]；.texContainsVideoPayload 判 unsupported；面板 allowedContentTypes=[.png,.jpeg]；官方文档允许 image/video | `SceneUserPropertyTextureLoader.swift:77,176`、断点队列 :122 | medium | verified（含官方文档 WebFetch 对照） |
| G23 | 内嵌视频 TEX（TEXB0004 WebM/VP9）不能出帧 | 包内 4 个（census video-mp4 4）；U06 点名 3662390671（layer185） | 原 WebM 报 AVFoundation -11828、remux MP4 报 -11833 且 0 frame；解码职责选型未定 | `docs/scene/roadmap/scene-open-breakpoint-queue.md:87` | medium | **unconfirmed**（队列登记在案；本次静态审查无域覆盖该解码职责，运行表现未复验） |
| G24 | 粒子 instanceoverride 绝对 color target 编译映射为 nil | 语料 instanceoverride 绝对 color 直连绑定作者（数量未单独 census；有 unsupportedTarget 诊断非完全静默） | .particle(field:.color) 在 TargetMapping case .color: nil → 不形成 instruction，要求整 key 重建 | `SceneUserPropertyBindings.swift:348`、`ScenePropertyBindingCompiler+TargetMapping.swift:132` | low | verified（normalizedColor 路径已支持） |
| G25 | 保真字段无运行时消费 | 13 个官方 stock 定义带 gizmos（python3 只读扫描）；所有 effect definition 均带 dependencies；全部产生 script 解析诊断的场景 | gizmos 唯一读者是 XRay 身份断言；dependencies 唯一消费同；SceneScriptBindingDiagnostic 全仓无读者 | `SceneEffectDefinition.swift:53,97`、`SceneAuthoredXRayPlanner+StockIdentity.swift:87`、`SceneDocument.swift:163` | low | verified（按设计多为 editor no-op，登记为"解析但无执行消费"事实） |
| G26 | cursor/可见性脚本无人认领窗口 | 非 composition utility 层及 solid/container/particle 层带 cursor/可见性脚本的绑定；样本数未测 | cursor lane 白名单 image/text/composition 与 vector 白名单 image/solid/text/container/composition/particle 的差集即无人认领，且无失败记录 | `SceneScriptCursorProgram+Construction.swift:303`、`SceneScriptVectorCandidateCatalog.swift:654,702-709` | low | verified |
| G27 | cameraparallaxmouseinfluence=0 时层仍随相机移动 | cameraparallax=true 36 样本中声明 mouseinfluence=0 的子集（域审查口径） | offset 公式含静态深度项不乘 mouseInfluence；官方"0=鼠标完全不影响"语义未裁决 | `SceneLayerParallax.swift:78,82-83`、`runtime-input-property-coverage.md` §3 自记 L2 | low | **unconfirmed**（是否违背官方行为需官方反例，coverage 已列下一门） |

> 严重度分布合计：high 5（G1-G5）/ medium 14（G6-G12,G15-G18,G21-G23）/ low 8（G13,G14,G19,G20,G24-G27），共 27 条，与对账 totals.gaps=27 一致。复核状态：verified 25、unconfirmed 2（G23、G27）。

---

## 5. 错误执行清单（11 条）

格式同 §4。错误执行=代码有执行路径但语义与官方/作者意图存在偏差或样本级缺陷开放。

| # | 能力族/问题 | 影响面 | 错误环节 | 证据 | 严重度 | 复核 |
|---|---|---|---|---|---|---|
| M1 | 静态模型方向光响应为线性 clamp(NdotL)×0.30 | 全部带受光静态模型场景（约 207 样本 author ambient/skylight）；土星 3589454154 受光侧 0.44× 可见差距 | 官方黑盒为带 0.157 地板的亚线性凸增（中段高 6-25%）；角度公式与 (1−d/r)² 衰减已源自官方对照，开放的仅队列 :144 列举的精确子项 | `SceneStaticModel.metal:376-378`、`SceneStaticModelPipeline.swift:771`（staticModelLightEnergyScale=0.30）、`static-model-light-input-semantics-2026-10-06.md:16`、断点队列 :144 | medium | verified |
| M2 | fragment varying 死声明误删致 generic 编译失败回退 | 含同名局部遮蔽 varying 声明的作者 shader；**实际样本命中未量化——本审计未对 243 样本做逐样本 shader 源提取扫描（pkg 压缩、shader 源内嵌于 effect/material JSON），无命中样本 id；"反例"为输入复核者以 python3 模拟该正则构造的验证（输入记录，无 shader 文本留档，本报告无法附反例原文）**。修复后建议的静态验证路径：解包全语料 effect/material JSON 提取 fragment 源，扫描 `varying` 声明名与函数体局部/参数名同名的样本（得到确定的影响面清单），再以命中样本做编译回归 | 条件 continue 跳过 shape 登记；hasLocalDeclaration 仅词法正则无 scope 区分；局部存在且 main 仍读全局时同样触发删除 | `SceneGenericShaderSourceNormalizer.swift:174-178,678-689`、断点队列 :35 | high | verified（复核方式为 python3 模拟正则验证反例；含 glslang 失败→generic 降级链；样本级命中面未扫） |
| M3 | 共享引用分析 scope 证明债 | boundedSwift 后端所有带同名遮蔽声明 shader 的 uniform/varying ABI 判定；队列 §4 自记样本影响未量化 | initializer 内/非 block if 后同名全局被误判为局部，直接决定 bounded 前端哪些全局进入 ABI/Metal 重写；工作树该文件与红证 SHA256 一致（未修） | `SceneAuthoredShaderGlobalReferenceAnalyzer.swift:58-71`（消费方 `SceneAuthoredShaderMetalEmitter.swift:79/129`、`SceneGenericShaderStageUniformAnalyzer.swift:41`）、断点队列 :136 | medium | verified（含 GLSL 4.5 spec §4.2 语义依据） |
| M4 | instance color/colorn 覆盖逐通道平方 | static/direct user property/SceneScript Vec3 colorn 覆盖的粒子系统（coverage IV13：28 binding/8 样本） | particle.color *= normalized*normalized / color*color；官方 colorn（0…1）语义未核验，平方系统性压暗中间调 | `SceneParticleSimulator+InstanceOverride.swift:22-27`、coverage IV09/IV10（`particle-component-coverage.md:322-323` 自认未核验）、`lib.sceneScript-v2.8.d.ts:1693` | medium | verified（执行路径唯一性 rg 验证；"官方为线性"前提无法静态验证） |
| M5 | Rope renderer world-space flag(bit0) 不拒绝也不构造 world | 带 renderer flags=1 的 Rope 系统（注释称语料 pointer-trail 家族 6 形态）；静态仿射下等价，动态差异未验 | 放行 bit0 无 world 构造路径，按 layer-local 渲染（以 Catmull-Rom 仿射不变性近似） | `SceneParticleRopePlan.swift:41-45`、coverage R09/R13 开放 | low | verified |
| M6 | init 阶段 angles 目标 BAD_RETURN 静默豁免 | object angles 绑定且 init 返回非 Vec3 的脚本；同一坏返回在 init/update 两路径行为不对称 | 按 diagnostic.contains("invalid Vec3") 把 BAD_RETURN 强转为 OK，净效果静默跳过，绕过统一 failure 记录；C 端 update 惰性 init 同场景会记 failure | `SceneScriptValueRuntime.swift:369-375`、`SceneQuickJS.c:1874-1879`、对照 `SceneScriptVectorProgram.swift:465-471` | medium | verified |
| M7 | registerAsset/createScriptProperties 行为是项目自有最小子集 | 调用这两个 API 的作者脚本；影响为覆盖表失真非视觉错误 | register_asset 仅路径校验返回 opaque handle 无注册表；createScriptProperties 只收集 {name:value}；coverage §11/contract §6 仍记 L0/零覆盖（文档-代码漂移） | `SceneQuickJSLayerHost.c:919-960`、`SceneQuickJSValueHost.c:187-192` | low | verified |
| M8 | Vec2/Vec3 字符串构造与官方数值合同不同 | 用字符串构造向量或带逗号/残缺分量的脚本；coverage §10.2 已列 edge golden 缺口 | 项目实现 trim+/[\s,]+/ split+Number()、分量不足抛 TypeError；官方合同按单空格 split+parseFloat、分量不足 NaN | `SceneQuickJSValueHost.c:128-162`、`scenescript-runtime-implementation-contract.md` §5.1 | low | verified（逐字符比对 C 分支与 contract 表） |
| M9 | 断点队列 5 个 Puppet/交互域视觉缺陷仍开放 | 5 个点名样本（3226487183 手臂侧脸错位、3764725758 U01②眼飘、3233141951 U17①脸不动、3769688830 U33 单向转、3749463715 U40 拖拽仅一次）及同族姿态/挂点样本 | 无修复痕迹。**口径与时点说明（修订补充）**："在途 21 文件"是域审查复核时点的 git status 记录（输入材料，时点不明）；本报告头部"约 71 个在途文件"是本会话开始时快照；修订轮亲自复核（2026-10-09）：`git status --short -- MyWallpaperX/Core/SteamWorkshopScene/Systems/Puppet/` 为 **0 个在途文件**、全仓在途 14 个文件（并行会话持续演进）——三个数字为三个时点/口径，不构成矛盾；Systems/Puppet 在当前时点仍无改动，M9 结论成立。运行根因静态不可判 | 断点队列 :52,82,98,114,121 对照 `Systems/Puppet/` 现状 | medium | verified（文档+git+rg 三层；根因未定） |
| M10 | 透明 RGB 颜色连续性 source/capture 段未接 | 含透明区域且 RGB 需跨 effect 保留的样本（至少 U19/3807668787；官方同输入对照已证差异） | 源上传仍 PMA 栅格化（premultipliedLast 把 alpha=0 处 RGB 清零）；effect 段三表示已落（9ecbea35）；并行在途改动已开始第二卡（普通加载改 straightAlbedo） | `SceneImageTextureUploader.swift:244-252`、`SceneResolvedMaterialProgram+ColorDerivation.swift:268-630`、断点队列 :34+:100、`authored-color-continuity-2026-10-09.md:20` | medium | verified |
| M11 | text 布局两个样本级断点开放 | U16/U25 各 1 样本文字 ROI（3122339805 文字/关闭按钮偏移、3351163962 时间文字跑出圆环） | 现有 pivot/alignment/padding 链（runtime-input-property-coverage.md:403，L3/S4 单样本）未覆盖该断点 | 断点队列 :97,:106（队列 :161 文字专项亦列） | low | **unconfirmed**（需运行复验文字 ROI，静态审查无法裁决；附带发现 coverage-ledger.md:90"text outline/shadow 仍缺"表述滞后于 `SceneTextTextureLoader.swift:333-378` 已消费现状，属文档漂移非引擎缺陷） |

---

## 6. 重复、低效与多余链路清单（53 条）

按管线阶段分组编排（R1-R53，对账 totals 记 49，差异见 §7.6）。类型：waste=多余开销、duplicate=重复实现/重复计算；量级列标注触发频率。帧热路径无重解析一项经本报告撰写者复跑 rg 核验（命令与结果见 §1 第 5 点：`Runtime/Session/`、`Rendering/Frame/` 两目录 `JSONSerialization|Data(contentsOf` 零命中），其余帧路径合同项（PSO/建图/哈希）沿用输入材料记录，下列各项全部是结构性重复或 launch 期成本。

### 6.1 阶段一：加载与解析链（R1-R7）

| # | 类型 | 量级 | 问题 | 证据 | 严重度 |
|---|---|---|---|---|---|
| R1 | waste | 每次加载×屏数×pkg | PKG 缓存命中路径验证成本接近重新解包：无条件读全包+哈希，命中仍逐缓存文件二次 SHA256，目录全枚举（复核：约三倍解包字节） | `ScenePkgCacheExtractor.swift:27,30,99-105,134-160` | medium |
| R2 | waste | 每次加载 | 同一目录树重复全量枚举：project root≥2 次、pkg 缓存树≥3 次（含 validCache 枚举）、stock bundle 1 次；单包缓存可达 1172 文件 | `SceneRuntimeSourceFacts.swift:24`（build）与 :35（SceneResourceView.swift:63 再 build）、`SceneParticleAssetGraph.swift:110` | medium |
| R3 | duplicate | 每次加载每静态模型层 | 同一 .mdl 读盘解析两遍：facts 取材质路径走 readParts 全量顶点校验（非廉价头部解析）+prepare 完整解码 | `SceneRuntimeSourceFacts.swift:121-126`、`ScenePreparedDeviceResources.swift:82-88` | medium |
| R4 | duplicate | 每次加载每 puppet 层（多屏翻倍） | 同一 puppet .mdl 一次 launch 读盘 3 次、mesh/rig/attachments 解析 2 次，多屏各自重做含 GPU 上传 | `ScenePuppetLayerLoad.swift:35-37,113-124,159-164`、`SceneMdlPuppetRigReader.swift:174`/`AttachmentReader.swift:89`/`AnimationReader.swift:135`（各自 range(of: skeletonMarker)） | medium |
| R5 | waste | 每次打开面板/检查/诊断 | 属性面板/检查/诊断/DEBUG runner 四个二级入口各自独立重建整条加载链（pkg 验证+scene.json 重解析+catalog/descriptor 重建），与 daemon 侧不共享 | `SteamWorkshopSceneInspectionController.swift:245-253`（identity 含 propertyOverrides :329-336）、`SceneDiagnostics.swift:48`、`DebugSceneDaemonClientRunner+UserTextures.swift:28` | medium |
| R6 | waste | 无运行时影响 | 不可达的外部解包工具死分支（主链唯一调用点硬编码 toolURL: nil） | `ScenePkgExtractionReport.swift:55`、`SceneRuntimeSourceFacts.swift:27` | low |
| R7 | waste | 每次加载 | scene.json 归一化为整树及每 object/effect/pass 构建 SceneJSONValue authored 拷贝：产品代码零读取（复核反证"无读者"——`script/tests/test_scene_timeline_document.py:287-307` Swift harness 读取全部四字段且为活门禁，属受回归保护的前瞻保留，降级登记） | `SceneDocument.swift:39,146,203,280,295`、`SceneDocumentObject.swift:273` | low（unconfirmed） |

### 6.2 阶段二/三：分析与编译缓存链（R8-R16）

| # | 类型 | 量级 | 问题 | 证据 | 严重度 |
|---|---|---|---|---|---|
| R8 | duplicate | 每次加载每材质节点 | 变体编译链 launchValidated 完全绕过需求分析链缓存，同一 template 同一事实族两条链各算一遍（对照需求链已有 single-flight+持久缓存） | `SceneResolvedMaterialExecutionCapabilityVariant.swift:86-98` 对照 `SceneResolvedMaterialRuntimeCatalog.swift:473-500` | medium |
| R9 | waste | 多屏每次 launch×（屏数-1） | 第 2+ 屏 source material 变体整套重建：take() 一次性消费后走 fallback，新 VariantCache/entries 全空+PSO warmup，跨表面零共享。**"行为另有差异"展开（修订补充）**：输入记录 fallback 调用（`Launch.swift:70-76`→:499-567）未传 visibleExecutionRootLayerIDs（:485 默认 `[]`），即重跑的编译/准入范围不含"可见执行根层"过滤，与首屏路径的裁剪行为不同；输入未描述该差异的具体视觉/性能后果，亦未单独立 G/R 条目，本报告按原样转述、未能进一步定性 | `SceneDesktopWallpaperSession.swift:441-464`、`ScenePreparedDeviceResources.swift:723-729`、`Launch.swift:70-76,485,499-567` | medium |
| R10 | waste | 每次启动每反馈节点×2 | feedback 拓扑 fallback 分支双份变体编译：同一 template 先后两次（仅 outputStorage 不同），keyDigest/分析加载/artifact 落盘各两遍，第一套已编译变体被丢弃 | `SceneResolvedMaterialExecutionCapability+Stages.swift:586,594,610,631` | medium |
| R11 | waste | 每次冷 variant 编译 | computeAnalysis 对同一 fragment 源约 15 个 analyzer 各自完整 lexer+parser，一次冷编译同源全量解析 20-30 次（复核实测 25+ 次，被低估而非高估） | `SceneResolvedMaterialGenericShaderPreparationCoordination.swift:443-708`（:490 起） | **high** |
| R12 | duplicate | 每次启动每 variant | 同一 canonical 源的分析事实被两套并行持久链重复计算并存储（SceneVariantAnalysis-v14 与 SceneGenericShaderAnalysis-v14 键域不同互不覆盖） | `SceneResolvedMaterialVariantAnalysisCache.swift:141-187`、`PreparationCoordination.swift:57-118`、`Variant+Artifact.swift:73-76` | medium |
| R13 | waste | 每次启动每失败 variant | fallback/失败链每次进程完整重走：observe-only/禁用路由或编译失败每次启动重跑 analyzer family，失败编译重新 spawn 子进程（约 9 个，磁盘无失败负缓存，类文档自述有意允许重试） | `SceneResolvedMaterialGenericShaderPreparationCoordination.swift:365-368`、`SceneGenericShaderArtifactCache.swift:329-346,420-425` | medium |
| R14 | waste | 每次启动每 variant | artifact 命中后无条件重跑 FragmentOutputAnalyzer+重复读盘解码；resolution cache 键为 34 字段全量 Input 而产物身份是更窄 requestKey（宽键致同 artifact 重复读盘） | `SceneGenericShaderArtifactCache.swift:329,382-385,394-396`、`PreparationCoordination.swift:242-250,300-335,631-634` | medium |
| R15 | waste | 每个冷编译请求 | 重复支付工具链固定开销：Bundle.resolve 重读 manifest+SecCode 签名校验无 memoize；每次编译前重跑 glslang/spirv-cross 版本探针（每请求 9 次 spawn） | `SceneGenericShaderCompiler.swift:38-40,91-119` | low |
| R16 | waste | 每次启动每 variant | variant 分析缓存命中路径仍有一处无条件全量重解析（rgbBlendScalarAlphaFact 缓存内外都执行完整 lex+parse） | `SceneResolvedMaterialExecutionCapabilityVariant+ColorAnalysis.swift:26-37,67-70` | low |

### 6.3 阶段四/五：图执行与帧热路径（R17-R30）

| # | 类型 | 量级 | 问题 | 证据 | 严重度 |
|---|---|---|---|---|---|
| R17 | waste | web 壁纸每次会话 | web 运行时也孵化 scene daemon，会话期间零消费者常驻（注释声明有意覆盖 scene 切换） | `AppDelegate.swift:146-156`、`SceneDaemonClient.swift:414-419` | low |
| R18 | waste | 每帧×authored dynamic uniform 数 | uniform 解析对 authored dynamic uniform 重做 fallback 等价校验再逐字节比较（launch 期不变量可预备常量） | `SceneResolvedMaterialProgramFinalizer.swift:573-588`（:863-894） | low |
| R19 | waste | 每帧×每 claimed 层×每活跃 stage | 从 launch 不变的图重建两个索引字典（Dictionary(uniqueKeysWithValues:)）+copy/swap 命令 O(n) 扫描，节点上限 512 时 O(n²) 放大 | `SceneResolvedMaterialGraphExecutor+Preparation.swift:136-141,652-655`、`SceneGraphExecutionState.swift:12` | medium |
| R20 | waste | 每帧×每 material 节点 | 无条件 overlay 纹理注册表，全量字典 COW 拷贝（digest 是 O(changed) 增量折叠，浪费核心在字典拷贝） | `SceneResolvedMaterialGraphExecutor+Preparation.swift:199-203`、`SceneTextureProviderPublication.swift:834` | medium |
| R21 | waste | 每帧（透视/动态 frame 下 solid 层） | solid 层 frame-target memo 键随相机/parallax 抖动必 miss（缺 image/text 分支的 128px 量化；1px 变化即换键触发新尺寸纹理对分配；miss 重跑 persistentTargetPlans 全链，帧路径 adm 段 25.5ms 主项）。复核限定：正交纯 parallax 平移不 miss，"parallax 必 miss"仅透视层成立 | `SceneResolvedMaterialFramePreflight.swift:330-336`（对照 :272-286 image/text 量化）、`SceneOffscreenTexturePool.swift:420-428` | medium |
| R22 | waste | 每帧×每 claimed 层 3-4 次 | 同层同帧 imageModelMatrix 重复计算 3-4 次（三处独立推导，同帧输入不变且无帧内 memo） | `SceneResolvedMaterialFramePreflight.swift:259-269,534-537,704-707`、`SceneMetalRenderer+ImageLayerEncoding.swift:62-79` | low |
| R23 | waste | 每帧每层最多 5-6 次 | baseMaterialTextureSelection 帧内缓存只覆盖 preflight（缓存 inout 局部、返回即丢），层循环/容量遍历/阴影准备各自重解析（复核另发现 3 个未列调用点，重复面只多不少） | `SceneResolvedMaterialFramePreflight+Admission.swift:34,172`、`SceneMetalRenderer+OrderedLayerEncoding.swift:109,112`、`SceneMetalRenderer+StaticModels.swift:188,339`、`SceneBaseMaterialTextureResolver.swift:113-163`（无 memo） | medium |
| R24 | waste | 每帧×2 次 | shadowDrawCandidates 同帧以完全相同参数完整计算两次（守卫无互斥，无缓存；第二次结果实质被 state.prepared 丢弃） | `SceneMetalRenderer+SceneDrawing.swift:169-171,213-215`、`StaticModels.swift:66-108` | medium |
| R25 | waste | 每帧最多 3 次 | prepareFramebufferSnapshotCapacity 每次全量遍历并对 blend 消费层重做纹理选择（HDR/图消费场景常见） | `SceneDrawing.swift:194,222,255`、`StaticModels.swift:187-190,230-237` | medium |
| R26 | waste | 每次脚本发射回调 | particleEmissionContext 每回调完整重算帧上下文+全层世界投影+相机帧（与 updateSimulation 每帧计算零共享；chargeParticleWork 只计费不去重） | `SceneMetalView+ParticlePlayback.swift:24-32` | medium |
| R27 | waste | 每帧最多 2 次 | prepareMandatoryDepth 重复（幂等保护存在，重复成本为遍历本身） | `SceneMetalRenderer+StaticModels.swift:260-265`、`SceneDrawing.swift:216-219` | low |
| R28 | waste | 每帧 | 组帧纹理快照复制全量字典+全量过滤（var textures=base.textures 立即写入触发实拷贝） | `SceneFrameLayerTextureAssembly.swift:13`、`SceneBaseImageTextureLoad.swift:227-229` | low |
| R29 | waste | 每帧 | beginFrame 每帧清空重建注册表并对每个 layerSource 双重发布；baseline 构造复制 3 个完整字典（帧作用域隔离为安全设计，重建成本可量化） | `SceneFrameTextureRegistry.swift:172-177,180-207` | low |
| R30 | waste | 每帧（仅 HDR surface） | renderFrame 每帧无条件 refreshDisplayOutput，HDR 下每帧两次 NSScreen EDR 查询（已有通知可驱动失效） | `SceneMetalView.swift:737,205-213`、`SceneMetalView+Geometry.swift:36-45` | low |

### 6.4 阶段六：资源生命周期与纹理（R31-R36）

| # | 类型 | 量级 | 问题 | 证据 | 严重度 |
|---|---|---|---|---|---|
| R31 | duplicate | 每次加载同文件跨子系统 | GPU 纹理缓存与解码缓存按 loader 实例分裂：约 4 个独立缓存域（复核修正：粒子/静态模型与基础图像实际共享实例），同文件双倍解码+双份 GPU 驻留；TextureKey 含 purpose 跨实例无复用 | `SceneMaterialAssetTextureCatalog.swift:172-175`、`ScenePreparedDeviceResources.swift:76,110`、`SceneUserPropertyTextureLoader.swift:102`、`SceneTextureLoader.swift:157` | **high** |
| R32 | waste | 每次加载 color 用途 png/jpg | premultipliedColor 无容器路径二次解码整个文件只为查 alpha，已缓存 CGImage 未复用（复核注："全图像素解码"无法静态证实，ImageIO 惰性解码，但结构浪费成立） | `SceneTextureLoader+Candidate.swift:159,265-268` | high |
| R33 | waste | 每次纹理加载 4-7 次文件系统往返 | 一次 tex candidate 加载对同一 URL 最多 7 次 sourceKey(for:) 重复 file-changed 校验（每次 resolvingSymlinksInPath+lstat；复核修正：png 冷加载实为 3 次、命中 4 次） | `SceneTextureLoader.swift:406-427`、`Candidate.swift:71,201`、`Loader.swift:249,380,383` | medium |
| R34 | waste | 每帧每层 1-3 次 pin 释放 | releasePin 对 resident 表 O(N) 线性扫描定位 pin（签名只收 UUID 无 key，持锁，放大锁争用）；pin 每次 compositionTarget 获取新建 | `SceneOffscreenTextureAllocationCache.swift:239-255`、`SceneOffscreenTexturePool.swift:114-122` | medium |
| R35 | waste | DEBUG evidence window 开启时长 | typedUniformPublicationIdentities 只增不减（含用户属性值 bitPattern），跨 reset 累积无界增长；Release 经 usesExecutionObservationCapture 关闭 | `SceneResolvedMaterialGraphExecutor.swift:134,563-569,639`、`SceneDesktopWallpaperHost.swift:181-190` | medium |
| R36 | waste | 每帧每 image layer 2-3 次 | resolvedBaseTextureSample() 重复完整校验链（无请求级缓存） | `SceneImageLayerDrawRequest.swift:275`、`SceneLayerSourcePassthroughPlan.swift:157,193`、`SceneImageLayerCompositor+Uniforms.swift:42`、`SceneBaseImageTextureCandidateSupport.swift:20-54` | low |

### 6.5 结构冗余、双实现与死代码（R37-R52）

| # | 类型 | 量级 | 问题 | 证据 | 严重度 |
|---|---|---|---|---|---|
| R37 | duplicate | 每帧每 draw | SceneImageLayerMainPassRenderer 是零增值纯转发 wrapper（全参数原样转发 ColorBlendRenderer.draw，compositor 五处经此入口） | `SceneImageLayerMainPassRenderer.swift:16-27`、`SceneImageLayerCompositor.swift:331,480,513,557,598` | low |
| R38 | duplicate | 每次加载构建 4 份 | 同一 authored dependency 图 launch 期独立构建 4 份（入参视角不同、图主体重复推导） | `SceneDependencyFrameRuntime.swift:141`、`SceneResolvedMaterialExecutionCapabilityAdmission.swift:300`、`SceneDirectBoolEffectVisibilityRouteAdmission.swift:29`、`SceneUtilityLayerRuntimePlan.swift:86` | low |
| R39 | waste | 每次启动每 effect 一次 | SceneGraphAdmissionProduct 的 composeTransitions（SHA256 digest）与 conditionSnapshot 产品路径零消费，仅为 Python 测试面保留（测试钩子产物，非视觉丢弃） | `SceneGraphAdmissionCompiler.swift:44,209,213` | low |
| R40 | duplicate | 1 样本 4 条（3768903841 lspot angles） | 同一 lspot angles Timeline 双链执行：generic binding 进光照快照（frame.columns.2 含全轴）+ SpotLightPlan 独立求值锥体旋转（只取 baseAngles.z+values[2]，丢 y 基值且不响应 play/pause/stop） | `SceneTimelineTargetCompiler.swift:297-298`、`SceneLightSnapshot.swift:375-379`、`SceneSpotLightPlan.swift:104-115` | medium |
| R41 | waste | 每次启动含 lspot 场景一次 | 灯光域两条 shader 交付路径并存（内联 JIT makeLibrary(source:) vs bundle makeDefaultLibrary；均为唯一 owner，职责分离合法的平行机制） | `SceneSpotLightPipeline.swift:86-89`、`SceneLitImageLayerPipeline.swift:340-344` | low |
| R42 | waste | 每帧每 spotLight 层 | spotLight case 内重复同帧可见性 guard（外层已 guard 同一集合，恒真死代码） | `SceneMetalRenderer+OrderedLayerEncoding.swift:196,292-293` | low |
| R43 | duplicate | 所有含 child 声明粒子层 | root 与 child 各维护一套 renderer 选择实现且语义漂移：child 版无 RopeTrail、首个匹配即 return、malformed 静默 continue 无诊断 | `SceneParticleChildTemplateSupport.swift:186,193-215` 对照 `SceneParticleRuntime+Support.swift:85-172` | medium |
| R44 | duplicate | root 层与全部 child 模板纹理准备路径 | refraction/普通纹理加载双分支编排同构复制两处（含相同失败 detail 字符串），维护面翻倍（行为当前一致） | `SceneParticleRuntime.swift:812-852`、`ChildGraphExpansion.swift:279-309` | low |
| R45 | waste | 仅旧 harness/聚焦测试调用面 | 为旧 harness 保留的双实现兼容入口（非 plan/prepared 版本 turbulentVelocity 与 control point force） | `SceneParticleSimulationSupport.swift:121-133`、`SceneParticleControlPointForce.swift:358-365` | low |
| R46 | duplicate | 文档消费者 | coverage 表与自身头部更正/代码两套事实并存（Clouds/Fire 表行 L1 vs 头部执行证据；route census 43/44 vs 代码 46，复核逐项清点确认 46）——冻结时点漂移，不判定何者语义错误 | `docs/scene/capabilities/effect-execution-coverage.md:188,198`、`SceneResolvedMaterialGenericShaderRouteAuthority.swift:8-58` | medium |
| R47 | duplicate | 所有带 MDAT 挂点 puppet | attachment 模型→Scene 的 Y 轴共轭两份独立实现（逐元素符号表 vs simd F*M*F；数学等价、当前数值一致仅漂移风险、无共享 owner） | `SceneMdlPuppetAttachmentReader.swift:9-16`、`ScenePuppetAttachmentPoseProjection.swift:46-47` | low |
| R48 | duplicate | 纯死代码 | 旧 owner 死代码：SceneTimelineRuntime.mergedDefinitions/values(program:) 全仓零调用（现役合并方 SceneDynamicDefinitionMerger.swift:4-18） | `SceneTimelineRuntime.swift:14-34` | low |
| R49 | waste | 维护成本级 | Puppet extent API 死代码（compositor 已改为不计算 size∪bind-pose coverage；evaluator 内 2 个无主 API 约 100 行） | `ScenePuppetAnimationEvaluator.swift:413-473`、`advanced-object-coverage.md:105` | low |
| R50 | duplicate | 每帧（多数样本） | 域内三条并行脚本值执行链（QuickJS generic/SceneSharedLayerAlpha incumbent/SceneText AST subset）每帧三路求值后 merge（分区守卫冲突即抛，文档化 deliberate 共存非重复执行） | `SceneDesktopWallpaperSession+FrameDriver.swift:228-252`、`SceneDesktopWallpaperHost+Launch.swift:368-430` | medium |
| R51 | duplicate | 每帧两条执行入口 | source capture 编码两份近似平行实现（graph pair base capture 与 compositor offscreen capture 逐行对应，差异仅 census 标签与 pixelFormat 校验；均为现役产品路径） | `SceneGraphResourcePassEncoder.swift:169-214`、`SceneOffscreenEffectRenderer+Capture.swift:23-60` | low |
| R52 | waste | release 每命令每帧一次系统日志 | 播放命令 next-frame 观察 NSLog 无 DEBUG 门控（对照同文件 textureAnimation/puppet 分支有 gate）——本次新发现，断点队列无对应条目 | `SceneTimelinePlaybackRuntime.swift:96-103`、`FrameDriverLifecycle.swift:117-121` | low |

### 6.6 缓存正确性风险（随冗余链登记，R53）

| # | 类型 | 量级 | 问题 | 证据 | 严重度 |
|---|---|---|---|---|---|
| R53 | gap | 同一 shader 合同被多 effect 以不同 framebuffer identity 实例化的样本 | demand 分析缓存键只存 hasImplicitFramebuffer 布尔，分析输入含完整 identity（identity 参与可达性判定）——不同 identity 材质节点可能错共享条目；键不对称是代码可见事实，错命中场景未运行验证（未在样本复现） | `SceneMaterialDemandAnalysisPersistentCache.swift:39,67`、`SceneResolvedMaterialRuntimeCatalog.swift:484-487`、`SceneResolvedMaterialShaderSchema+Reachability.swift:212-219` | low（unconfirmed） |

> 合计 53 条（按各表类型列实际统计：waste 37、duplicate 15、gap 1），severity：high 3（R11/R31/R32）、medium 25、low 25。对账 totals 记 49（差异见 §7.6）。复核状态：verified 51、unconfirmed 2（R7 复核反证后降级登记、R53 键不对称未运行验证）。

---

## 7. 与仓库现有清单的对账差异

### 7.1 样本基数：census 243 即全量

- 我实测：样本库恰 243 个目录（`ls` 实测，仅 `.DS_Store` 一个非目录文件）= census 快照 243 = 8 片重建 243 id（python3 逐 id 比对，双向差集均为空）。
- 任务所述"census 未覆盖的约 35 个新样本"在当前样本库不存在——核对结果为**零新样本**，如实报告。
- tracked full-matrix baseline 仅 45 个历史成员（matrix_coverage_state='pending-expansion'），45+198 added_since_matrix=243；快照自述扩容建立运行期待前不得称为完整快照门。

### 7.2 重建 vs census 漂移（分片对账汇总）

- 8 条 title 空白折叠（3113554287/3232289987/3363252053/3437487219/3563038726/3587571382/3601964477/3791905266）：census 按 `script/scene_capability_census.py:191` 把连续空格折叠为单空格，与源 project.json 原文不符。
- 4 条 user binding 口径差（3787382101 重建 33 vs census 32、3788645041 7 vs 2、3797217144 9 vs 8、3800356808 28 vs 24；差异在 effects constantshadervalues/visible 级 wrapper 是否计入）。合计重建 user_bindings 5969 vs census 5950（+19）；condition 1107 vs 1117（-10，shard-7 未提供 condition 计数，样本数 58 vs 61）。
- 一致项（我复算）：8 类 layer 对象数逐项一致（image 243/3068、text 126/1086、sound 81/114、utility 39/701、light 8/19、camera 12/12、shape 16/22、particle 164/761，总 5783）；effect 实例 5071；script wrapper 141 样本/3895；timeline 70/475；4 条 package 诊断（duplicate-package-path×2：3768724269/3807013762；package-json-malformed×2：3723344874 entry32/3749463715 entry72）与 census package_anomaly_count=4 完全对应；model 引用 243/243。
- census 覆盖缺口：loose shaders/ 目录不在 census package-resource 统计内（片5：16/31 样本带 pkg 外 loose shaders/；片8：833227004 带 blobsSM40 5 个 .dxs）；census 未按 puppet/非 puppet 分列 model 引用。

### 7.3 census 内部口径提醒（沿用基线复核）

- 两个相近 unknown 计数并存易误读：generic_or_unknown_family_count=6 与 capability_mapping.unknown_family_count=7 口径不同（后者多含 project-property-kind-empty 1），3472+7=3479 family 守恒。
- 快照 JSON 无内嵌时间戳，时点靠 mtime 2026-10-08 02:12 与提交 015ff8d6 锚定；`.artifacts` 快照未入库。
- 12 大类 occurrence 是多视角 typed 登记口径（同一 authored 形态在相邻 domain 平行成 family），加总 101675 是守恒登记总数，非唯一语义实体数。
- 全部 243 样本 first_blocker='unknown'、runtime_evidence_state='not-joined'：第一 blocker 不得从静态形态猜测。

### 7.4 口径差（非数据冲突，不可混用）

- 分片 effect 族计数=『引用该族文件的样本数（含非 active）』，census effect census=『可见引用』：blendgradient 20 vs 4 样本、transform 7 vs 4、perspective 15 vs 7、swing 8 vs 6、reflection 4 vs 3、edgedetection 1 vs 0 可见。
- 任务描述称容器为 PKGV0001，实际全库分布 PKGV0001×8 至 PKGV0025×23；3766415113 主包为 gifscene.pkg。

### 7.5 本报告撰写者的独立复算差异（python3 只读解析 8 片）

以下为本 Agent 本次亲自执行的复算（命令：python3 解析 `shard-1..8.json`，逐片适配五种 effects schema 与 by_kind/flat 两种 layers schema）：

| 项目 | 对账口径 | 我复算 | 判定 |
|---|---|---|---|
| 8 类 layer 对象总数 | census 5783 逐项 | 逐项一致 | 一致 |
| 8 类 layer 样本数（>0 口径） | census 243/126/81/39/8/12/16/164 | 完全一致（注意：分片部分片显式列出值 0 的 kind 键，须用 >0 过滤） | 一致 |
| 九族引用并集 | 37 样本 | 37（各族 2/8/4/20/2/4/2/1/1 全一致） | 一致 |
| perspective 引用 | 15 样本 | 15 | 一致 |
| puppet 声明（5 片可判定口径） | 31/150 | 31/150（31 个 id 全列于附录） | 一致 |
| transform 官方族文件引用 | 8 样本 | **7**（2067939514/2419444134/2932157836/3042492564/3238423642/3264246690/3662390671 均引 effects/transform/effect.json）；宽匹配含 workshop geometric_transform 变体为 11 | **差 1，无法精确归因**——对账的 8 与官方族 7、宽口径 11 均不吻合，附录按官方族 7 标注 |
| workshop 路径引用 | corpusSamples=133 | **134**（分片 effect 路径含 workshop/ 口径） | 口径差 1：133 是"视包内是否存在"口径，134 是路径引用口径，附录按 134 标注并注明 |
| census 可见九族口径 | 约 54 occ/21 样本 | 域复核仅能复现 54 occ/10 样本（权威快照 effect domain 15 个 authored-graph family 正文 grep 九族名为 0） | 部分复现，21 样本口径未证实（不影响 37 并集主结论） |
| script/timeline/user-prop 样本数 | 141/70/243 | 141/70/243 | 一致 |
| solidlayer 引用（layer.solid 样本面） | 片4"22 样本引用 util stock model" | solidlayer.json 19 样本/17 处、solidlayer_depthtest 5 处、util stock model 整体 23 样本（composelayer 18 处/fullscreenlayer 8 处） | **差 1**（util 整体 23 vs 22）：以我复算 23 为准，id 清单见矩阵 #2 |

### 7.6 totals 数字差异（如实登记）

- **capabilities：对账 totals 记 53，矩阵逐条实为 54**（§3 表 #1-#54）。差异疑似 audio-declaration（#54）与 media/audio（#49）在 totals 中被并计；本报告按 54 条逐条列出不裁并。
- **redundancies：对账 totals 记 49，清单逐条实为 53**（§6 R1-R53），其中 R53 在输入中 kind=gap（缓存键正确性风险随冗余链登记）。差异疑似部分"两路发现合并"条目在 totals 中按合并前口径计数；本报告按 53 条列出。
- gaps=27、misexecuted=11 与逐条清点一致，无差异。

### 7.7 与断点队列（scene-open-breakpoint-queue.md，221 行）的关系

- 抽查行 :21/32/34/35/52/68/82/87/97/98/100/106/114/121/122/135/136/139/140/141/144/159/161/163 全部存在且与域审查转述一致。misexecuted 主干全部是队列已登记开放条目的代码现状核实（:144 光照合同、:35 varying 误删、:136 scope 债、:34+:100 透明RGB/U19、:140 maxtoemitperperiod、:159 九族、:163 Animation Events/usershortcut/动画name、:141 bone physics、:52/82/98/114/121 五个 Puppet/样本级缺陷、:122 U41、:87 U06、:161 文字布局）。
- **队列未排队而本次新发现的缺口**（多数在 capability coverage 文档已有 L0/L1/L2 登记，属"文档已知、队列未排队"）：sound muteInEditor/mintime/maxtime 无消费（G13）、smoothing/stiffness 非空丢弃（G14）、tangent.magic、general.bloomstrength 动画丢弃（G8）、point/lpoint castvolumetrics 静默丢弃（G6）、shape 非 quad 折叠（G19）、gizmos/dependencies/scriptBindingDiagnostics 无消费（G25）、多 renderer sibling 无诊断丢弃（G18）、粒子 color 平方（M4，coverage IV09/10 自认）、MDLA0006 keyed auxiliary（G16）、texture-animation wrapper 仅 presence（G10）、scene general 脚本（G9）、4 个事件 slot 永不派发、angles init 豁免（M6）、Vec2/Vec3 构造偏离（M8）、cursor lane 窗口（G26）、NSLog 无门控（R52）。
- **两项仅以一句话记录、未能纳入清单定位的新发现**（修订时补充说明，原文口径冲突的遗留）：
  - "startsilent 缺省整层拒绝"：仅存在于对账汇总 censusConflicts 的一句话，无证据行号与影响面，无法编入 27 条缺口清单。与矩阵 #4 的关系：#4 记录的是 `SceneSoundPlaybackProgram.swift:135-168` admission **已消费** startsilent 字段的正常面；该记录指的是未声明 startsilent 时整层被拒的缺省边界行为——两者不矛盾，但后者本报告未能独立定位到具体 guard 行，按"未经复核的一句话记录"处理。
  - "ldirectional 级联阴影键无解析面"：来自域审查图层域链路结论（原文"ldirectional 的 radius/density/exponent/cascadeddistance*/volumetricsexponent/lightsourcesize 连解析面都没有"），矩阵 #14 仅以括号提及（"ldirectional 级联阴影键无解析面"），无独立 G 编号、无逐键影响面；语料内 ldirectional 声明样本数未从分片分离。修复时以 `SceneDirectionalLightDefinition.swift`（域复核曾引 :30 的 kind 解析）为入口核对键集。

### 7.8 与台账/coverage 文档的时点漂移与域结论修正

- coverage-ledger.md 系统总表核对时点 2026-09-01（:25）落后于 census 2026-10-08；Audio declarations 行（:84）仍是 172 语料口径 vs census 243 口径——**两组三元数字的各位含义（修订补充标注）**：均为"occurrence 数/声明样本数/静态 consumer 意图样本数"，即 172 语料重算为（1,499/129/56）、census 快照为（2,092/184/86）。注意 editor 标记（census 基线记 128，见矩阵 #49）是另一维度，与三元组第二位"声明样本数"（129/184）不是同一字段，两组数字不可互相替换对表；:90"text outline/shadow 仍缺"滞后于 `SceneTextTextureLoader.swift:333-378` 已消费现状——台账与 census 数字不可直接互对。
- 域审查结论经对账修正（以复核口径为准）：①Transform"authored 动态 vector2 全部被拒降级"被推翻——现役 pass-owned vector2 有完整 QuickJS typed Vec2 owner 链（coverage-ledger.md:57 权威，effect-execution-coverage.md:217 为过期口径）；②灯光"项目自有有界近似"被部分反证——角度公式与 radial²·diffuse 均源自官方黑盒对照，仅断点 :144 精确子项开放；③authoredRoot/authoredValue"全仓无读者"被推翻（测试 harness 读取，受门禁保护的前瞻保留）；④cloudmotion 从"无已证执行路由"降级为"族级 L1、3748311238 派生输入有已证执行"；⑤TextureLoader"6 处实例"修正为约 4 个独立缓存域；⑥maxtoemitperperiod 受影响面"≥2 样本"修正为 1 样本（3749463715）4 处声明。
- perspective 表行漂移（G2）与 route census 46 vs 文档 43/44（R46）为最需要先行纠正的文档项。

---

## 8. 逐样本附录（243 样本 × 能力 × 状态标记）

数据来源：`.artifacts/scene-audit-2026-10-09/shard-1.json` 至 `shard-8.json`（本报告撰写者以 python3 只读解析、逐片适配 schema 后生成；片号=样本所在分片）。

### 8.1 图例与口径

**能力缩写与全局状态**（状态来自 §3 矩阵，样本级适用=该样本声明了对应形态）：

| 缩写 | 能力族（矩阵#） | 标记 | 说明 |
|---|---|---|---|
| img | layer.image-static-compose / layer.solid（#1/#2） | ✅ | image 对象>0 即适用 |
| txt | layer.text-coretext（#3） | ◐ | U16/U25 两样本另见备注 |
| snd | layer.sound-playback（#4） | ◐ | muteInEditor 等无消费（G13） |
| utl | layer.utility-composition（#5） | ✅ | |
| shp | layer.shape-quad（#6） | ◐ | 语料 22/22 全 quad，0 层实际影响（G19） |
| cam | layer.camera-path（#7） | ✅ | |
| lgt | layer.light 四类灯（#8） | ◐ | 体积光/方向光缺口（G6/G7/M1） |
| par | layer.particle 及粒子族（#10/#15-20） | ◐ | 粒子域 L0/L1 族（G5/G17/G18 等） |
| pup | puppet 族（#21-26） | ✅(n) | n=分片 puppet 模型引用数；**pup?=该片（1/6/7）无 puppet 专属判定**（片1 的 models_puppet 字段为普通 image model 引用，不作判定）；puppet 域内 physics ◐（G15）、extrusion ❌（G12） |
| eff | effect.generic-34 族（#27） | ✅ | effect 实例>0 |
| n9❌ | effect.L0/L1 九族（#28） | ❌ | 括号内缩写：cm=cloudmotion、sw=swing、br=blurradial、bg=blendgradient、ni=nitro、rf=reflection、fr=refraction、sk=skew、ed=edgedetection（G1） |
| tr | effect.transform（#29） | ✅ | 官方 transform/effect.json 族引用 |
| pe | effect.perspective（#30） | ❌ | fail-closed（G2） |
| ws | effect.workshop 跨作品引用（#31） | ❓ | 分片路径引用口径 134 样本；实际可得性视包内是否存在（对账 133 为另一口径，见 §7.5） |
| scr | scenescript value-owners/handles（#37/#40） | ✅ | has_script；域内 events ◐（G4/G9/G10 相关面见备注） |
| tl | timeline authored 动画（#42） | ✅ | timeline wrapper>0；域内 options ❌（G14/G8） |
| prop | user-property 六类型（#46） | ✅ | usershortcut ❌（G3）另见备注 |

**全局适用不逐样本列**：static-model.direct ◐（8 片 243/243 记录 image→model 引用）、material.ordinary-shader ✅（243 样本/9354 occ）、material.render-state ◐（#34）、material.texture-sampling-tokens ◐（#36）、texture.resource ◐（#45）、render-graph ✅（#51，225 样本显式 graph）、render-output ✅（#52，输出链全局）、output.color-continuity ◐（#53）、媒体/指针域（#49/#50/#54）按声明未逐样本分列（分片无统一字段）。

**—**=该样本未声明该能力。**备注列**=§4/§5 点名的样本级事实（gap/misexecuted 例证）。标题截断 14 字符。

### 8.2 逐样本表（片 1-4，样本 1-124）

| 样本 id | 片 | 标题 | 图层 | 粒子 | Puppet | 特效引用 | 脚本 | 时间线 | 用户属性 | 备注 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1195626192 | 1 | Gaze | img✅ | par◐ | pup? | — | — | — | prop✅ |  |
| 1300076567 | 1 | 阳光少女 | img✅ | par◐ | pup? | — | — | — | prop✅ |  |
| 1315486372 | 1 | 貂蝉拜月 | img✅ | par◐ | pup? | — | — | — | prop✅ |  |
| 1439846152 | 1 | 腿 | img✅ | par◐ | pup? | — | — | — | prop✅ |  |
| 1480826543 | 1 | Emilia X-ray N | img✅ | par◐ | pup? | — | — | — | prop✅ |  |
| 1507413154 | 1 | 百褶裙 | img✅ | par◐ | pup? | — | — | — | prop✅ |  |
| 1507593643 | 1 | 蕾丝吊带 | img✅ | par◐ | pup? | — | — | — | prop✅ |  |
| 1511889295 | 1 | 死库水 | img✅ | par◐ | pup? | — | — | — | prop✅ |  |
| 1553008362 | 1 | [Jidan Hua] Ic | img✅ | — | pup? | — | — | — | prop✅ |  |
| 1636394814 | 1 | [Jaku Denpa] S | img✅ | — | pup? | — | — | — | prop✅ |  |
| 1926190458 | 1 | Morning_4k | img✅ snd◐ | par◐ | pup? | — | — | — | prop✅ |  |
| 1937925563 | 1 | Tropical Parad | img✅ | par◐ | pup? | — | — | — | prop✅ |  |
| 1989767609 | 1 | Black tights（透 | img✅ | — | pup? | — | — | — | prop✅ |  |
| 1994794519 | 1 | D.VA_OVERWATCH | img✅ | par◐ | pup? | — | — | — | prop✅ |  |
| 2067939514 | 1 | Windows Visual | img✅ txt◐ | par◐ | pup? | n9❌(bg) tr✅ ws❓ | scr✅ | tl✅ | prop✅ | transform✅25个scale owner；workshop跨作品❓ |
| 2069136288 | 1 | [R18] Lexaidue | img✅ | — | pup? | — | — | — | prop✅ |  |
| 2112262451 | 1 | [R18] Sakimi C | img✅ | — | pup? | — | — | — | prop✅ |  |
| 2131872317 | 1 | Night Market b | img✅ snd◐ | par◐ | pup? | — | — | — | prop✅ |  |
| 2134765860 | 1 | Bunk | img✅ txt◐ | par◐ | pup? | n9❌(bg) pe❌ ws❓ | scr✅ | tl✅ | prop✅ | scene级general脚本❌；workshop跨作品❓ |
| 2163522240 | 1 | [18+] jk x-ray | img✅ | — | pup? | — | — | — | prop✅ |  |
| 2179185481 | 1 | Azur Lane / 18 | img✅ | — | pup? | — | — | — | prop✅ |  |
| 2181251652 | 1 | Mio Tokisaki ( | img✅ | — | pup? | — | — | — | prop✅ |  |
| 2231088993 | 1 | Ahri X-Ray | img✅ | — | pup? | — | — | — | prop✅ |  |
| 2241938645 | 1 | KDA Akali [4k  | img✅ | par◐ | pup? | — | scr✅ | — | prop✅ |  |
| 2269193950 | 1 | WLOP - Nap | img✅ | par◐ | pup? | — | — | — | prop✅ |  |
| 2304304373 | 1 | Don't Die | img✅ txt◐ snd◐ | par◐ | pup? | — | scr✅ | — | prop✅ |  |
| 2347762662 | 1 | 18+ X-Ray │NSF | img✅ | — | pup? | — | — | — | prop✅ |  |
| 2356604986 | 1 | 1265079-132260 | img✅ | — | pup? | — | — | — | prop✅ |  |
| 2419444134 | 1 | Nier Reincarna | img✅ snd◐ | par◐ | pup? | tr✅ | scr✅ | — | prop✅ |  |
| 2470144420 | 1 | 女孩独享的宁静傍晚 | img✅ snd◐ | par◐ | pup? | — | — | — | prop✅ |  |
| 2473638329 | 1 | Genshin Impact | img✅ | par◐ | pup? | — | — | — | prop✅ |  |
| 2505351195 | 2 | Nier Automata  | img✅ | par◐ | — | eff✅ | — | — | prop✅ |  |
| 2524111047 | 2 | Liu Meryl Wei  | img✅ | — | — | eff✅ | — | — | prop✅ |  |
| 2607203340 | 2 | Tomb Raider +1 | img✅ | par◐ | — | eff✅ | — | — | prop✅ |  |
| 2616828675 | 2 | 【R18】别看了，快点啦~# | img✅ snd◐ | par◐ | — | eff✅ | — | — | prop✅ |  |
| 2684431262 | 2 | 麻匪 炫酷音频律动 Wind | img✅ snd◐ | par◐ | — | eff✅ pe❌ ws❓ | scr✅ | — | prop✅ |  |
| 2775915974 | 2 | R18*JK(escalat | img✅ | — | — | eff✅ | — | — | prop✅ |  |
| 2794098047 | 2 | 麻匪 是姐姐还是妹妹 win | img✅ txt◐ snd◐ utl✅ | par◐ | — | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 2797913147 | 2 | 【R18】连体黑丝#4K#视 | img✅ | — | pup✅(1) | eff✅ | scr✅ | — | prop✅ |  |
| 2802243144 | 2 | 冰公主-by Wlop 时间 | img✅ txt◐ snd◐ | par◐ | — | eff✅ | scr✅ | — | prop✅ |  |
| 2804817823 | 2 | Yor Forger ／ S | img✅ | par◐ | pup✅(2) | eff✅ | — | tl✅ | prop✅ |  |
| 2808874251 | 2 | youer | img✅ | par◐ | — | — | — | — | prop✅ |  |
| 2811643059 | 2 | 原神 | img✅ | — | — | eff✅ | — | — | prop✅ |  |
| 2813231542 | 2 | 清新美女 R-18 | img✅ txt◐ | par◐ | — | eff✅ n9❌(rf) ws❓ | scr✅ | — | prop✅ |  |
| 2815826216 | 2 | 麻匪 约尔·福杰 间谍过家家 | img✅ txt◐ snd◐ lgt◐ | — | — | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 2824109832 | 2 | Yor Forger - N | img✅ txt◐ | par◐ | — | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 2834973884 | 2 | 麻匪 wlop-鬼刀 重置版 | img✅ snd◐ | par◐ | — | eff✅ n9❌(sw) ws❓ | scr✅ | — | prop✅ |  |
| 2837223712 | 2 | 李擎洲：阿狸[4K] | img✅ txt◐ snd◐ | par◐ | — | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 2849382252 | 2 | 麻匪 死亡笔记 L·Lawl | img✅ snd◐ | par◐ | — | eff✅ n9❌(sw) ws❓ | scr✅ | — | prop✅ |  |
| 2884628849 | 2 | 麻匪 小姐姐 | img✅ txt◐ snd◐ | — | — | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 2896873092 | 2 | Genshin Impact | img✅ | — | — | eff✅ | — | — | prop✅ |  |
| 2902406982 | 2 | 麻匪 月半与鬼哭 所有元素自 | img✅ txt◐ snd◐ | par◐ | — | eff✅ n9❌(bg) ws❓ | scr✅ | tl✅ | prop✅ |  |
| 2917306763 | 2 | [4K/动态/R18/衣服透 | img✅ txt◐ | — | pup✅(3) | eff✅ ws❓ | scr✅ | tl✅ | prop✅ |  |
| 2932157836 | 2 | [4K ／ 可自定义] 星浴 | img✅ txt◐ | par◐ | — | eff✅ n9❌(bg) tr✅ pe❌ ws❓ | scr✅ | tl✅ | prop✅ |  |
| 2932631210 | 2 | 欧派-音乐乱动 | img✅ | par◐ | — | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 2938612768 | 2 | 麻匪 音频识别 Media  | img✅ txt◐ | par◐ | — | eff✅ n9❌(bg) ws❓ | scr✅ | tl✅ | prop✅ |  |
| 2942486721 | 2 | R18 Ishtar And | img✅ | — | — | eff✅ | — | — | prop✅ |  |
| 2949019513 | 2 | [4K ／ 可自定义] A. | img✅ txt◐ snd◐ | par◐ | — | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 2959875782 | 2 | [R18] Lexaidue | img✅ | — | pup✅(8) | eff✅ | scr✅ | — | prop✅ |  |
| 2974757317 | 2 | 麻匪 音频识别 悬浮窗 Me | img✅ txt◐ | par◐ | — | eff✅ n9❌(bg) ws❓ | scr✅ | tl✅ | prop✅ |  |
| 2981249186 | 2 | 4K SCI-FI Blac | img✅ txt◐ snd◐ | par◐ | — | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 2983846453 | 2 | 麻匪 自定义双背景开关 -  | img✅ txt◐ snd◐ | — | — | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 2986218263 | 3 | Tokisaki Asaba | img✅ | par◐ | — | eff✅ | scr✅ | — | prop✅ |  |
| 2998757800 | 3 | 碧蓝航线-利托里奥【R18版 | img✅ txt◐ snd◐ | par◐ | pup✅(4) | eff✅ | scr✅ | tl✅ | prop✅ |  |
| 3002649614 | 3 | 纯欲少女 | img✅ txt◐ | — | — | — | scr✅ | — | prop✅ |  |
| 3021013015 | 3 | 赛博color-墨侠客行 | img✅ snd◐ | par◐ | — | eff✅ ws❓ | — | — | prop✅ |  |
| 3025969015 | 3 | 黑龙闹海 | img✅ snd◐ | par◐ | — | eff✅ | — | — | prop✅ |  |
| 3028090166 | 3 | WLOP [Tian Nan | img✅ txt◐ | par◐ | pup✅(1) | eff✅ | — | tl✅ | prop✅ |  |
| 3042492564 | 3 | [4K ／ Customiz | img✅ txt◐ utl✅ cam✅ | par◐ | pup✅(9) | eff✅ n9❌(bg) tr✅ ws❓ | scr✅ | tl✅ | prop✅ |  |
| 3078285611 | 3 | 麻匪 金克丝 jinx 音频 | img✅ txt◐ snd◐ utl✅ | par◐ | pup✅(1) | eff✅ n9❌(bg) ws❓ | scr✅ | tl✅ | prop✅ |  |
| 3088601835 | 3 | Winter Wandere | img✅ snd◐ | par◐ | — | eff✅ | — | — | prop✅ | sound多音轨 |
| 3113287126 | 3 | Dome 4k {Artwo | img✅ txt◐ snd◐ | par◐ | pup✅(2) | eff✅ n9❌(bg) ws❓ | scr✅ | tl✅ | prop✅ |  |
| 3113554287 | 3 | 【可随时间变化】窗旁の伊蕾娜 | img✅ txt◐ | — | — | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3115163440 | 3 | Shadow Garden  | img✅ | — | — | eff✅ | — | — | prop✅ |  |
| 3122339805 | 3 | Pixels | img✅ txt◐ | — | — | eff✅ ws❓ | scr✅ | — | prop✅ | U16文字/关闭按钮偏移◐ |
| 3141421197 | 3 | GraspOfTheAbys | img✅ | — | — | eff✅ | — | — | prop✅ |  |
| 3146507587 | 3 | こきん【吉罗】 | img✅ snd◐ | par◐ | — | eff✅ ws❓ | — | tl✅ | prop✅ |  |
| 3147346398 | 3 | ⛏🧱Minecraft Lo | img✅ txt◐ snd◐ | — | — | eff✅ ws❓ | scr✅ | tl✅ | prop✅ |  |
| 3167210190 | 3 | [Blue Archive] | img✅ | — | — | eff✅ | — | — | prop✅ |  |
| 3211615441 | 3 | 捆绑悬挂 ／ Bind &  | img✅ txt◐ | — | — | eff✅ n9❌(bg) ws❓ | scr✅ | — | prop✅ |  |
| 3219398263 | 3 | Acheron Black  | img✅ | par◐ | — | eff✅ | — | — | prop✅ |  |
| 3226487183 | 3 | 麻匪 花火 五角色自定义 崩 | img✅ txt◐ snd◐ | par◐ | pup✅(8) | eff✅ n9❌(bg) ws❓ | scr✅ | tl✅ | prop✅ | Puppet手臂/侧脸错位(队列开放) |
| 3232289987 | 3 | 【4k 高度自定义】流萤&萨 | img✅ txt◐ snd◐ utl✅ | par◐ | pup✅(9) | eff✅ ws❓ | scr✅ | tl✅ | prop✅ |  |
| 3233141951 | 3 | 熠烛 御剑驭龙-红鸾樱落 高 | img✅ txt◐ snd◐ utl✅ | par◐ | pup✅(6) | eff✅ ws❓ | scr✅ | tl✅ | prop✅ | U17①脸不动(队列开放) |
| 3238423642 | 3 | Katana Girl wi | img✅ txt◐ | par◐ | pup✅(2) | eff✅ n9❌(sw+bg) tr✅ ws❓ | scr✅ | tl✅ | prop✅ |  |
| 3264246690 | 3 | 麻匪 wlop 鬼刀 月牙儿 | img✅ txt◐ snd◐ utl✅ | — | pup✅(1) | eff✅ n9❌(sk) tr✅ ws❓ | scr✅ | tl✅ | prop✅ |  |
| 3287715210 | 3 | 发光少女 4K动态壁纸 | img✅ txt◐ snd◐ shp◐ lgt◐ | par◐ | — | eff✅ ws❓ | scr✅ | — | prop✅ | lpoint castvolumetrics❌ |
| 3290491250 | 3 | frieren | img✅ txt◐ | par◐ | — | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3299228616 | 3 | Lonely Cat: Au | img✅ txt◐ snd◐ utl✅ shp◐ | par◐ | — | eff✅ n9❌(rf) pe❌ ws❓ | scr✅ | — | prop✅ |  |
| 3323988600 | 3 | Hentai Goddess | img✅ | par◐ | — | eff✅ ws❓ | — | — | prop✅ |  |
| 3351163962 | 3 | [高度自定义] 樱花庄的宠物 | img✅ txt◐ snd◐ utl✅ | par◐ | — | eff✅ n9❌(bg) ws❓ | scr✅ | tl✅ | prop✅ | U25时间文字跑出圆环◐ |
| 3357627941 | 3 | 麻匪 开门见喜 鼠标交互 自 | img✅ txt◐ | par◐ | — | eff✅ ws❓ | scr✅ | — | prop✅ | U41纹理替换仅PNG/JPEG◐ |
| 3363252053 | 3 | 【Parallax视差】Ha | img✅ txt◐ snd◐ utl✅ cam✅ | par◐ | pup✅(1) | eff✅ n9❌(rf) ws❓ | scr✅ | tl✅ | prop✅ |  |
| 3389974179 | 4 | 落日与白皙的大腿 | img✅ txt◐ | — | — | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3395392965 | 4 | 请叫我帅锅-小姨定制 | img✅ | — | — | eff✅ | — | — | prop✅ |  |
| 3395777145 | 4 | 麻匪 光 音频识别 Medi | img✅ txt◐ utl✅ | — | — | eff✅ n9❌(bg) ws❓ | scr✅ | tl✅ | prop✅ |  |
| 3396722575 | 4 | 麻匪 NIXEU 黄泉 超多 | img✅ txt◐ snd◐ utl✅ | par◐ | — | eff✅ n9❌(bg+rf) ws❓ | scr✅ | tl✅ | prop✅ |  |
| 3420215721 | 4 | 麻匪 圈 媒体识别交互壁纸  | img✅ txt◐ utl✅ | par◐ | — | eff✅ n9❌(br+bg) pe❌ ws❓ | scr✅ | tl✅ | prop✅ |  |
| 3437487219 | 4 | 3D Earth - Clo | img✅ txt◐ utl✅ shp◐ lgt◐ | par◐ | — | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3446316682 | 4 | 【完美世界】柳神 无敌道 | img✅ snd◐ | par◐ | — | eff✅ | — | — | prop✅ |  |
| 3448845950 | 4 | 麻匪 媒体音频标签【148项 | img✅ txt◐ utl✅ | par◐ | — | eff✅ n9❌(cm+bg) ws❓ | scr✅ | tl✅ | prop✅ |  |
| 3448877775 | 4 | 【Time Variatio | img✅ txt◐ snd◐ utl✅ cam✅ | par◐ | — | eff✅ ws❓ | scr✅ | tl✅ | prop✅ | 唯一events声明(空数组)❌ |
| 3470948192 | 4 | 水滴 三体 ／ Drople | img✅ txt◐ snd◐ utl✅ cam✅ lgt◐ | — | — | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3472940912 | 4 | -Tsukatsuki Ri | img✅ | — | — | eff✅ n9❌(sw) | — | — | prop✅ |  |
| 3477054430 | 4 | Cat with headp | img✅ txt◐ utl✅ cam✅ lgt◐ | — | — | eff✅ ws❓ | scr✅ | tl✅ | prop✅ |  |
| 3487629864 | 4 | 云曦老婆 (18+) | img✅ txt◐ | par◐ | — | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3509243656 | 4 | 三体实时演算 ／ Three | img✅ txt◐ snd◐ utl✅ cam✅ | par◐ | — | eff✅ n9❌(br) ws❓ | scr✅ | — | prop✅ |  |
| 3549827466 | 4 | 【完美世界 火灵儿】盛典妆容 | img✅ snd◐ | par◐ | — | eff✅ | — | — | prop✅ |  |
| 3554161528 | 4 | Blue Archive-S | img✅ txt◐ snd◐ utl✅ cam✅ | par◐ | — | eff✅ ws❓ | scr✅ | tl✅ | prop✅ |  |
| 3562021804 | 4 | 【完美世界】石昊 以身为种 | img✅ snd◐ shp◐ | par◐ | — | eff✅ ws❓ | — | — | prop✅ |  |
| 3563038726 | 4 | 【凡人修仙传】梅凝  乖巧可 | img✅ snd◐ | par◐ | — | eff✅ n9❌(sw) ws❓ | — | — | prop✅ |  |
| 3566880847 | 4 | 【凡人修仙传】紫灵 白色限定 | img✅ snd◐ shp◐ | par◐ | — | eff✅ n9❌(sw) ws❓ | — | — | prop✅ |  |
| 3581882134 | 4 | 【凡人修仙传】紫灵 冰清玉洁 | img✅ txt◐ snd◐ cam✅ | par◐ | — | eff✅ ws❓ | scr✅ | tl✅ | prop✅ |  |
| 3585542943 | 4 | 【凡人修仙传】元瑶 灵泉沐浴 | img✅ txt◐ snd◐ | par◐ | — | eff✅ pe❌ ws❓ | scr✅ | tl✅ | prop✅ |  |
| 3585875739 | 4 | Miku Monitorin | img✅ | par◐ | — | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3587571382 | 4 | 【凡人修仙传】宋玉  璀璨夺 | img✅ txt◐ snd◐ shp◐ | par◐ | — | eff✅ ws❓ | scr✅ | tl✅ | prop✅ |  |
| 3589454154 | 4 | 土星 ／ Saturn -  | img✅ txt◐ snd◐ utl✅ cam✅ lgt◐ | par◐ | — | eff✅ ws❓ | scr✅ | — | prop✅ | usershortcut×17❌；blobsSM40 24个.dsx模型shader❌；土星受光侧0.44×差距◐ |
| 3601964477 | 4 | 千咲 ／／ 鸣潮  ／／ 枫 | img✅ txt◐ | par◐ | — | eff✅ pe❌ ws❓ | scr✅ | tl✅ | prop✅ |  |
| 3603711180 | 4 | 【凡人修仙传】慕沛灵 金屋藏 | img✅ txt◐ snd◐ cam✅ | par◐ | — | eff✅ n9❌(br+bg+ed) ws❓ | scr✅ | tl✅ | prop✅ | sound 7层 |
| 3609108600 | 4 | 千咲 ／／ 鸣潮 ／／ 4K | img✅ txt◐ | — | — | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3610154602 | 4 | 千咲 ／／ 鸣潮 ／／ 高塔 | img✅ txt◐ | par◐ | — | eff✅ pe❌ ws❓ | scr✅ | tl✅ | prop✅ |  |
| 3612058080 | 4 | 吞噬星空-星幻王 | img✅ | — | — | eff✅ | — | — | prop✅ |  |
| 3612199597 | 4 | 千咲 ／／ 鸣潮 ／／ 与千 | img✅ txt◐ | par◐ | — | eff✅ pe❌ ws❓ | scr✅ | tl✅ | prop✅ |  |
| 3612795410 | 4 | 千咲 ／／ 鸣潮 ／／ 与千 | img✅ txt◐ | par◐ | — | eff✅ pe❌ ws❓ | scr✅ | tl✅ | prop✅ |  |

### 8.3 逐样本表（片 5-8，样本 125-243）

| 样本 id | 片 | 标题 | 图层 | 粒子 | Puppet | 特效引用 | 脚本 | 时间线 | 用户属性 | 备注 |
|---|---|---|---|---|---|---|---|---|---|---|
| 3629927359 | 5 | 奶牛大鸭鸭 2 | img✅ | — | — | — | — | — | prop✅ |  |
| 3655958892 | 5 | R18 Acheron &  | img✅ txt◐ | — | — | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3662390671 | 5 | 【Angels of Del | img✅ txt◐ utl✅ | par◐ | — | eff✅ n9❌(bg+fr) tr✅ ws❓ | scr✅ | tl✅ | prop✅ | WebM视频TEX❌U06；944处script键 |
| 3662790108 | 5 | 实时太阳系 Live Sol | img✅ txt◐ snd◐ utl✅ cam✅ lgt◐ | — | — | eff✅ ws❓ | scr✅ | — | prop✅ | usershortcut×20❌ |
| 3663810817 | 5 | 鎏金狮影映娇颜 | img✅ txt◐ snd◐ utl✅ | par◐ | pup✅(1) | eff✅ ws❓ | scr✅ | tl✅ | prop✅ |  |
| 3665307769 | 5 | 爱弥斯1 ／／ 鸣潮 ／／  | img✅ txt◐ | par◐ | pup✅(2) | eff✅ pe❌ ws❓ | scr✅ | — | prop✅ |  |
| 3690859128 | 5 | 爱弥斯2 ／／ 鸣潮 ／／  | img✅ txt◐ snd◐ | par◐ | pup✅(1) | eff✅ | scr✅ | — | prop✅ |  |
| 3694697894 | 5 | 星街すいせい 星街彗星（第二 | img✅ txt◐ | par◐ | — | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3699213569 | 5 | 碧蓝航线Azurlane-斯 | img✅ | — | — | eff✅ | — | — | prop✅ |  |
| 3703104370 | 5 | Rio&菲比-adoc(涟) | img✅ | — | — | eff✅ | — | — | prop✅ |  |
| 3712499998 | 5 | 鸣潮 ／／ 3.3pv ／  | img✅ txt◐ | par◐ | — | — | scr✅ | — | prop✅ |  |
| 3721456868 | 5 | 绯雪1 ／／ 鸣潮 | img✅ txt◐ snd◐ | par◐ | pup✅(1) | eff✅ | scr✅ | tl✅ | prop✅ |  |
| 3723344874 | 5 | 【凡人修仙传】玄骨 借尸还魂 | img✅ txt◐ snd◐ | par◐ | pup✅(17) | eff✅ ws❓ | scr✅ | tl✅ | prop✅ | pkg entry32 malformed；puppet引用×17 |
| 3738202317 | 5 | Albedo. | img✅ | — | — | eff✅ | — | — | prop✅ |  |
| 3742133044 | 5 | 凌霄·双司镇命·无常<1>- | img✅ | par◐ | — | eff✅ | — | — | prop✅ |  |
| 3743305891 | 5 | 战双 | img✅ txt◐ snd◐ | par◐ | — | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3747190633 | 5 | 【凡人修仙传】银月 惹人怜惜 | img✅ txt◐ snd◐ utl✅ | par◐ | pup✅(2) | eff✅ ws❓ | scr✅ | tl✅ | prop✅ |  |
| 3747492842 | 5 | [4k]Leon S Ken | img✅ txt◐ shp◐ | par◐ | pup✅(6) | eff✅ pe❌ ws❓ | scr✅ | — | prop✅ |  |
| 3748311238 | 5 | 大 | img✅ snd◐ | — | pup✅(1) | eff✅ n9❌(cm) ws❓ | — | tl✅ | prop✅ | cloudmotion族级❌但派生链有已证执行 |
| 3749463715 | 5 | 还能在大 ∑ 2 | img✅ shp◐ | par◐ | pup✅(4) | eff✅ ws❓ | scr✅ | tl✅ | prop✅ | maxtoemitperperiod❌雷电4声明零发射；pkg entry72 malformed；U40 |
| 3750342273 | 5 | Night snowy mo | img✅ txt◐ snd◐ | par◐ | — | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3750813609 | 5 | Asian Temple i | img✅ txt◐ snd◐ | par◐ | — | eff✅ | scr✅ | — | prop✅ |  |
| 3754630802 | 5 | WLOP [ChineseN | img✅ shp◐ | par◐ | pup✅(5) | eff✅ ws❓ | — | tl✅ | prop✅ |  |
| 3754639143 | 5 | WLOP 银月 | img✅ | par◐ | — | eff✅ ws❓ | — | tl✅ | prop✅ |  |
| 3757555836 | 5 | 名将杀【兰汤春酽_赵姬】限制 | img✅ | par◐ | — | eff✅ | — | — | prop✅ |  |
| 3761159935 | 5 | 【诛仙】陆雪琪 等待的沉默 | img✅ txt◐ snd◐ utl✅ | par◐ | — | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3762312138 | 5 | Elf x Goth | img✅ | — | — | eff✅ ws❓ | — | — | prop✅ |  |
| 3763323436 | 5 | 补 碧蓝航线 拉菲 Azur | img✅ | par◐ | — | eff✅ | — | — | prop✅ |  |
| 3763428294 | 5 | 秧秧·玄翎1／／穗穗／／舟行 | img✅ txt◐ | par◐ | pup✅(3) | eff✅ | scr✅ | tl✅ | prop✅ |  |
| 3764725758 | 5 | Lumine_HuuOliv | img✅ txt◐ | par◐ | pup✅(2) | eff✅ | scr✅ | tl✅ | prop✅ | U01②眼飘(队列开放) |
| 3765760121 | 5 | 【4K】三色堇与她 | img✅ txt◐ | par◐ | — | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3765904723 | 6 | 调月莉音 | img✅ txt◐ | — | pup? | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3766387484 | 6 | ARKNIGHTS ENDF | img✅ txt◐ snd◐ shp◐ | par◐ | pup? | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3766403294 | 6 | 仪玄(AI) | img✅ txt◐ | — | pup? | eff✅ | scr✅ | — | prop✅ |  |
| 3766415113 | 6 | The last pour | img✅ | — | pup? | — | — | — | prop✅ |  |
| 3767232084 | 6 | 谬因 | img✅ | par◐ | pup? | eff✅ | — | — | prop✅ |  |
| 3767343314 | 6 | Universe Abstr | img✅ | par◐ | pup? | eff✅ ws❓ | — | — | prop✅ |  |
| 3767460992 | 6 | Magic mushroom | img✅ txt◐ | — | pup? | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3768020435 | 6 | Silver Wolf wi | img✅ txt◐ utl✅ | — | pup? | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3768229922 | 6 | 麻匪 赤芒 音频互动 | img✅ snd◐ utl✅ cam✅ | par◐ | pup? | eff✅ n9❌(br) ws❓ | scr✅ | tl✅ | prop✅ |  |
| 3768724269 | 6 | ARKNIGHTS ENDF | img✅ txt◐ snd◐ utl✅ shp◐ | par◐ | pup? | eff✅ ws❓ | scr✅ | — | prop✅ | duplicate-package-path |
| 3768903841 | 6 | Naha Gaze at F | img✅ txt◐ snd◐ shp◐ lgt◐ | par◐ | pup? | eff✅ ws❓ | scr✅ | tl✅ | prop✅ | lspot×4体积锥◐；angles动画双链 |
| 3769364482 | 6 | 戴拿奥特曼 强壮型【Ultr | img✅ txt◐ snd◐ | par◐ | pup? | eff✅ ws❓ | scr✅ | tl✅ | prop✅ |  |
| 3769688830 | 6 | Spirit Blossom | img✅ txt◐ | par◐ | pup? | eff✅ ws❓ | scr✅ | tl✅ | prop✅ | U33单向转(队列开放) |
| 3769761761 | 6 | Yoru and Mitak | img✅ txt◐ snd◐ | par◐ | pup? | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3770444459 | 6 | 三国杀【节气 夏至 2026 | img✅ | par◐ | pup? | eff✅ | — | — | prop✅ |  |
| 3770462923 | 6 | gt3rs@d4rk | img✅ txt◐ | — | pup? | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3775355045 | 6 | 交错战线_DAIBLOS C | img✅ | — | pup? | eff✅ | scr✅ | — | prop✅ |  |
| 3775373546 | 6 | 交错战线_DAIBLOS C | img✅ | — | pup? | eff✅ | scr✅ | — | prop✅ |  |
| 3777761326 | 6 | I do Anything | img✅ utl✅ | par◐ | pup? | eff✅ ws❓ | — | — | prop✅ |  |
| 3779026256 | 6 | [魔法少女的魔女审判] 月代 | img✅ txt◐ snd◐ | par◐ | pup? | eff✅ ws❓ | scr✅ | tl✅ | prop✅ |  |
| 3779904456 | 6 | 尤诺2 ／／ 鸣潮 | img✅ txt◐ | par◐ | pup? | eff✅ | scr✅ | — | prop✅ |  |
| 3780119725 | 6 | in the rain V  | img✅ txt◐ snd◐ | par◐ | pup? | eff✅ n9❌(sw) pe❌ ws❓ | scr✅ | tl✅ | prop✅ |  |
| 3780391264 | 6 | Agnes Tachyon  | img✅ txt◐ | par◐ | pup? | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3780940857 | 6 | 枕澜 蒂法 电脑动态壁纸 最 | img✅ snd◐ | — | pup? | eff✅ | — | — | prop✅ |  |
| 3781307553 | 6 | Look this | img✅ | — | pup? | eff✅ | — | — | prop✅ |  |
| 3782650329 | 6 | 我们三 X-ray | img✅ | — | pup? | eff✅ | — | — | prop✅ |  |
| 3782740481 | 6 | WLOP Violet 紫 | img✅ snd◐ | par◐ | pup? | eff✅ ws❓ | — | tl✅ | prop✅ |  |
| 3784012236 | 6 | >R-18< 蔚蓝档案 Bl | img✅ | — | pup? | eff✅ | — | — | prop✅ |  |
| 3786048634 | 6 | 2B and A2 | img✅ | — | pup? | eff✅ | — | — | prop✅ |  |
| 3786185473 | 6 | ELF PARADISE～欢 | img✅ | — | pup? | eff✅ | — | — | prop✅ |  |
| 3786641495 | 6 | Albedo - Look  | img✅ | — | pup? | eff✅ | — | — | prop✅ |  |
| 3787355076 | 7 | 维琳娜-申请入股 | img✅ | — | pup? | eff✅ | — | — | prop✅ |  |
| 3787382101 | 7 | 清宵 ／／ 万剑 ／／ 鸣潮 | img✅ txt◐ | par◐ | pup? | eff✅ ws❓ | scr✅ | tl✅ | prop✅ |  |
| 3788066613 | 7 | [Hajily-1825][ | img✅ txt◐ utl✅ | par◐ | pup? | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3788467391 | 7 | Miku and Monst | img✅ | par◐ | pup? | eff✅ n9❌(ni) ws❓ | — | — | prop✅ |  |
| 3788645041 | 7 | 奥黛塔(破洞版) | img✅ | — | pup? | eff✅ | — | — | prop✅ |  |
| 3788698200 | 7 | NFFA画风 维琳娜2（可去 | img✅ txt◐ | par◐ | pup? | eff✅ | scr✅ | — | prop✅ |  |
| 3788734811 | 7 | 庄方宜-1 | img✅ | par◐ | pup? | eff✅ | scr✅ | — | prop✅ |  |
| 3788897599 | 7 | ArT丨R18丨4K丨Red | img✅ txt◐ utl✅ | par◐ | pup? | eff✅ pe❌ ws❓ | scr✅ | — | prop✅ |  |
| 3789316755 | 7 | Fern_Frieren | img✅ txt◐ | par◐ | pup? | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3790631363 | 7 | 三国杀【水殿香来 曹金玉】限 | img✅ | par◐ | pup? | eff✅ | — | — | prop✅ |  |
| 3790726145 | 7 | 周于希54 | img✅ | par◐ | pup? | — | — | — | prop✅ |  |
| 3790806929 | 7 | Winter Artoria | img✅ | par◐ | pup? | eff✅ | — | tl✅ | prop✅ |  |
| 3790956325 | 7 | 骚暖暖 | img✅ | — | pup? | eff✅ | — | — | prop✅ |  |
| 3791905266 | 7 | Dohrn's  Visio | img✅ | par◐ | pup? | eff✅ ws❓ | — | — | prop✅ |  |
| 3791967416 | 7 | 麻匪 虎符电竞 兰 16:9 | img✅ txt◐ utl✅ | — | pup? | eff✅ ws❓ | scr✅ | tl✅ | prop✅ |  |
| 3792249095 | 7 | Beth's Wallpap | img✅ txt◐ | par◐ | pup? | eff✅ n9❌(fr) ws❓ | scr✅ | — | prop✅ |  |
| 3792400801 | 7 | Girl ／ Dark Ba | img✅ txt◐ | par◐ | pup? | eff✅ n9❌(ni) ws❓ | scr✅ | — | prop✅ |  |
| 3792817546 | 7 | 小羊不吃草 (地雷系)#滕子 | img✅ txt◐ | par◐ | pup? | — | scr✅ | — | prop✅ |  |
| 3793328876 | 7 | 大凤Taihou&白凤Hak | img✅ | — | pup? | eff✅ | — | — | prop✅ |  |
| 3793978239 | 7 | 埃吉尔掰穴 | img✅ | — | pup? | — | — | — | prop✅ |  |
| 3793998447 | 7 | 枕中梦 | img✅ snd◐ | — | pup? | eff✅ ws❓ | — | — | prop✅ |  |
| 3796588443 | 7 | ZZZ 薇薇安 法厄同 Vi | img✅ txt◐ shp◐ | par◐ | pup? | eff✅ pe❌ ws❓ | scr✅ | — | prop✅ |  |
| 3797217144 | 7 | 迪迦奥特曼 出场动画 镜头视 | img✅ txt◐ snd◐ | par◐ | pup? | eff✅ n9❌(bg) ws❓ | scr✅ | tl✅ | prop✅ | smoothing/stiffness 9处不消费 |
| 3800075350 | 7 | 三角洲三小只-RX | img✅ txt◐ | par◐ | pup? | — | scr✅ | — | prop✅ |  |
| 3800356808 | 7 | Warmth Valley  | img✅ txt◐ snd◐ | par◐ | pup? | eff✅ ws❓ | scr✅ | tl✅ | prop✅ |  |
| 3800572533 | 7 | [4K ／ Day/Nigh | img✅ utl✅ | — | pup? | eff✅ | scr✅ | — | prop✅ |  |
| 3800728730 | 7 | 浮士德ego穴 | img✅ snd◐ | — | pup? | — | scr✅ | — | prop✅ |  |
| 3801294161 | 7 | Reze - Let's t | img✅ | par◐ | pup? | eff✅ ws❓ | — | — | prop✅ |  |
| 3801984224 | 7 | 粉红护士 | img✅ | — | pup? | — | — | — | prop✅ |  |
| 3802005866 | 7 | 绝区零 维琳娜 西域风 Ze | img✅ txt◐ | — | pup? | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3803087940 | 7 | 原神 少女黑丝玉足 X -  | img✅ | par◐ | pup? | eff✅ | — | — | prop✅ |  |
| 3803482159 | 8 | Black Morpho | img✅ | par◐ | — | eff✅ | — | — | prop✅ |  |
| 3803576671 | 8 | NFFA画风 冰雪公主（可去 | img✅ txt◐ | par◐ | — | eff✅ | scr✅ | — | prop✅ |  |
| 3804441338 | 8 | Misty Summit 2 | img✅ txt◐ snd◐ utl✅ | par◐ | — | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3804906814 | 8 | 瞳中星火 新约能天使 明日方 | img✅ txt◐ snd◐ | par◐ | — | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3804971850 | 8 | Mobius梅比乌斯4 | img✅ txt◐ | par◐ | — | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3805449677 | 8 | 御图网-浅雾藏山语 | img✅ | par◐ | — | — | — | — | prop✅ |  |
| 3805547608 | 8 | 碧蓝航线 金鹿号【R18版/ | img✅ txt◐ snd◐ utl✅ | par◐ | — | eff✅ ws❓ | scr✅ | tl✅ | prop✅ |  |
| 3806006894 | 8 | 三角洲行动露娜天际线_LUN | img✅ txt◐ | par◐ | — | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3806016969 | 8 | 三角洲行动红狼蚀金玫瑰_黑金 | img✅ txt◐ | par◐ | — | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3806202923 | 8 | Azur Lane 碧蓝航线 | img✅ txt◐ utl✅ | par◐ | — | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3806337293 | 8 | 初音未来 hatsune m | img✅ txt◐ | — | pup✅(1) | eff✅ ws❓ | scr✅ | tl✅ | prop✅ |  |
| 3807013762 | 8 | Frieren | img✅ txt◐ utl✅ shp◐ | par◐ | — | eff✅ ws❓ | scr✅ | — | prop✅ | duplicate-package-path |
| 3807121855 | 8 | 鸣潮今汐-桃花鸢 | img✅ snd◐ | par◐ | — | — | — | — | prop✅ |  |
| 3807151772 | 8 | MyGO 长崎素世 Soyo | img✅ txt◐ | par◐ | — | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3807239614 | 8 | 清霄&心 | img✅ txt◐ | — | — | eff✅ | — | — | prop✅ |  |
| 3807436394 | 8 | Ronova | img✅ snd◐ | par◐ | — | eff✅ ws❓ | — | — | prop✅ |  |
| 3807553861 | 8 | Albedo - After | img✅ | — | — | eff✅ ws❓ | — | — | prop✅ |  |
| 3807668787 | 8 | 霜翼剑使 | img✅ txt◐ snd◐ shp◐ | par◐ | pup✅(1) | eff✅ ws❓ | scr✅ | tl✅ | prop✅ | U19透明RGB灰冠◐ |
| 3807861954 | 8 | 鬼方 カヨコ | img✅ txt◐ snd◐ | par◐ | — | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3809541486 | 8 | Moon Princess | img✅ shp◐ | par◐ | — | eff✅ | — | — | prop✅ |  |
| 3809609151 | 8 | League of Lege | img✅ txt◐ utl✅ | par◐ | — | eff✅ ws❓ | scr✅ | — | prop✅ |  |
| 3809618616 | 8 | 芒果青青 | img✅ txt◐ | — | — | eff✅ ws❓ | — | — | prop✅ |  |
| 3810943704 | 8 | Empress of Gra | img✅ txt◐ | par◐ | pup✅(7) | eff✅ n9❌(sw) ws❓ | scr✅ | tl✅ | prop✅ | bloom呼吸动画❌(基值0不可见)；puppet×7；U40拖拽仅一次 |
| 3811154012 | 8 | 麻匪 Uncle Panda | img✅ utl✅ | par◐ | pup✅(2) | eff✅ | scr✅ | tl✅ | prop✅ |  |
| 3812249745 | 8 | 完美世界-九劫柳神 | img✅ | — | — | eff✅ | — | — | prop✅ |  |
| 833227004 | 8 | 星云变换t001 | img✅ | — | — | — | — | — | prop✅ | blobsSM40 5个.dsx(loose)❌ |

### 8.4 附录统计小结（本报告撰写者复算）

- 表行 243（片 1-8：31/31/31/31/31/31/31/26），与分片文件、census 样本基数一致。
- 适用计数：img 243、txt 126、snd 81、utl 39、shp 16、cam 12、lgt 8、par 164（全部与 census kind 样本数逐项一致）；scr 141、tl 70、prop 243、eff（generic 实例>0）见各行。
- 九族引用 37 样本（各族：bg 20/sw 8/rf 4/br 4/ni 2/cm 2/fr 2/sk 1/ed 1）；pe❌（perspective 引用）15 样本；tr✅（官方 transform 族）7 样本；ws❓（workshop 路径引用）134 样本。
- pup✅ 判定 31 样本（片 2/3/4/5/8 可判定口径；分片引用合计 114：片2 4 样本/14 引用、片3 11/44、片5 12/45、片8 4/11——修订时逐行复算附录 31 行确认，v1 初稿误写 176 系沿用早期口径混算的残留，已废）；二进制级复核为 57 样本/255 个 MDL，引用口径与唯一 mdl 口径不可混（如 3723344874 引用 17/唯一 9）；pup?（片 1/6/7 未判定）93 样本——其中 3769688830 经二进制复核确含 puppet（U33 点名），故 31 为下界。
- 带点名备注 26 行（§4/§5 例证样本 + 4 条 package 诊断样本）。

---

## 9. 未覆盖与不确定性

以下为本审计（及全部三路输入审查）未覆盖或无法在静态只读纪律下裁决的事项，修复 Agent 不得将本报告结论外推到这些范围：

1. **运行时验证整体缺席**：census `runtime_evidence_state` 243/243 = not-joined；9 个 particle-layer-load-incomplete 归档样本、Graph 执行门 30 项 false（断点队列 :135 测试债）、U 系列视觉断点根因（U06/U16/U25/U33/U40 等）、HDR/EDR 实际输出、多屏实测均未运行复验（硬性纪律禁止构建/运行）。本报告所有"完整/部分"均为静态链路判定，非运行结论。
2. **shader 编译链未实跑**：glslang/SPIRV-Cross/bounded 前端的实际编译产物、失败率、"首断点在 ShaderPreparation source-proof"均为方向性推断（特效域复核与原审查均未构建）。
3. **pkg 压缩容器语料盲区**：2D lit 受光样本量、多 renderer 系统数、render state translucent/additive 样本级量、rgba16f 是否被引用、ltube 灯型是否存在于 19 个 light 对象——均未解包全量扫描（部分域审查者做了局部临时解包，灯光域自认未做）。
4. **分片重建口径空洞**（8 片 schema 不一致的后果）：shard-7 无 condition wrapper 计数（-3 样本）；shard-1/6/7 无 puppet 专属判定（附录 pup? 93 样本）；shard-5/7 无 parse_state；supportsaudioprocessing 无统一字段；texture-animation wrapper 未从 wrapper 统计分离；scenetexture 与 'texture' 拼写变体合并口径未统一（31 vs 87 处）。
5. **census 快照细目未逐条核对**：93 条 unclassified（仅抽查首条 particle-controlpoint null 形态）、7 个 unknown family 的样本级归属、纹理 slot hole 3800/missing 71 的分布、visible_occurrence_index 与分片可见性口径对账均未做；census verify 子命令未运行（纪律禁止）。
6. **引擎区域未被任何车道覆盖**：QuickJS C 桥实现（SceneQuickJS*.c 仅 SceneScript/媒体域局部读取）；shadow atlas/point light shadow 执行细节；AVAudioEngine 频谱采集管线；App 侧属性面板 UI 层；Reference Project C++ 对照资产；TEX 内嵌 WebM 解码职责选型；localStorage/Preferences 持久层。
7. **帧时序行为只能代码推断**：previous/compose 跨帧序列、swap mapping 跨帧持久、暂停恢复、effect-local passthrough 的实际视觉表现无运行观察。
8. **性能/能耗影响未量化**：§6 全部 waste/duplicate 为代码结构结论，实际耗时占比未实测（输入材料管线阶段 2 的复核注曾提及某次变体编译链测量中主导成本出自未签名 Debug 回退路径、生产签名构建大部分不存在——该测量为输入记录的一次性观察，无命令与样本可追溯，本报告不引用其具体数值）。
9. **跨作品 workshop effect（134 样本路径引用）的实际可得性**：依赖样本包外的创意工坊目录状态，静态无法判定运行时哪些可加载（故矩阵 #31 为存疑）。
10. **断点队列与 coverage 文档完整性未审**：本次仅抽查被引用行号（:21/32/34/35/52/68/82/87/97/98/100/106/114/121/122/135/136/139/140/141/144/159/161/163），队列全文 221 行与各 capability coverage 文档其余条目未逐条复核；coverage-ledger（2026-09-01 时点）与 census（2026-10-08）之间可能存在本报告未发现的进一步漂移。
11. **对账数字残留差异**：transform 官方族引用 7 vs 对账 8（差 1 无法归因，§7.5）、workshop 134 vs 133（口径差）、census 可见九族"21 样本"口径未复现（仅 54 occ/10 样本）、totals capabilities 54 vs 53 与 redundancies 53 vs 49（§7.6）——均如实登记，未强行调和。

---

*报告完。本文件为本次审计唯一指派输出，位于 `.artifacts/scene-audit-2026-10-09/scene-full-sample-static-audit-report.md`；生成过程未修改任何仓库受版本控制文件、未构建、未运行测试与 census 脚本、未触碰样本库内容（仅只读解析其目录清单与分片副本数据）。*




