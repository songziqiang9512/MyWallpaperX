<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->
<!-- cutoffDate: 2026-10-03 -->
<!-- uniqueValue: 本批 named graph资格、specialized nil candidate 与普通视觉失败的设计及审查纠偏。 -->
<!-- retirementCondition: 原 atlas named 失败输入恢复真实输出，局部视觉失败与资源生命周期反例通过独立终审后，将稳定职责移交 runtime-architecture、执行证据归档并删除本设计登记。 -->

# Named image graph 输出的准入与失败半径

> **历史证据 — 非现役入口**。实施验证及最终裁决见[本批记录](rf02-atlas-named-output-implementation-2026-10-03.md)，稳定职责见[架构](../../scene/design/runtime-architecture.md)。

基线 `942f1cca`。本设计承接[现役路线](../../scene/scene-compatibility-roadmap.md)中 RF02 A 集成暴露的首帧失败；它不批准[公开纹理 companion B](../../scene/design/authored-texture-coordinate-design.md)。证据来源是 `MyWallpaperX-current-evidence` 与既有[架构合同](../../scene/design/runtime-architecture.md#33-保留事务安全不扩大视觉失败半径)，不需要私有算法或新的官方数值推断。

## 目标合同

合法正轴 atlas 图像已经能经原基础图像捕获及 effect graph 出图，其 graph-final 必须能通过现有 named provider 发布给消费者，消费 prepared graph 的真实尺寸并只映射一次。不能以原底图不满足 raw image 捕获的零起点规则，拒绝已经准备好的 graph 输出。

未支持的合法视觉映射只影响已证明可以安全回退的 effect，保留 effect-entry current 和健康邻层；identity、purpose、无效GPU范围、epoch、reservation、hazard及资源预算破坏仍拒绝最小 unsafe unit。仅恢复首帧的永久降级不算本批完成；原 atlas graph-output 正例也必须真实出图。

## 当前事实与首断点

以下源码路径相对 `MyWallpaperX/Core/SteamWorkshopScene/`，行号以基线为准。

| 当前事实 | 证据 |
|---|---|
| imageLayerBlend 与 visibleImageGraphOutput 共用原底图资格检查，随后才采用 preparedOutputExtent | `Rendering/Dependencies/SceneDependencyFrameRuntime+Geometry.swift:244-259` |
| exact image profile 要求 candidate 对应真实 texture、resolved purpose/content/sampling，并要求零起点的 mapped scale | 同文件 `:366-383`；`Resources/Textures/SceneTextureCandidate.swift:231-259` |
| graph 输出尺寸来自原计划 required-provider 集与该 provider prepared fullFramePair，非随意传入的作者尺寸 | `Rendering/Frame/SceneResolvedMaterialFramePreflight+AggregateReservation.swift:108-119` |
| 原 reservation 验证 plan binding、epoch、target extent、source extent、geometry generation 与物理资源；失败返回 nil 与 reason | `Rendering/Dependencies/SceneDependencyFrameRuntime+Geometry.swift:47-166` |
| missing source 已降为 providerSourceUnavailable，但 reservation 的任何 nil 都升级整帧 invalid | `Rendering/Frame/SceneResolvedMaterialFramePreflight.swift:571-597`；`Rendering/Frame/SceneMetalRenderer.swift:257-262` |
| 既有局部回退仅有 externalPrimary、单 effect、无私有 render target、每依赖槽唯一 material 节点的证明 | `Compilation/Material/SceneResolvedMaterialExecutionCapability+ProgramFirstStages+InputContracts.swift:91-125`；`Rendering/Graph/SceneResolvedMaterialGraphExecutor+VisualFailurePassthrough.swift:26-40`、`:274-284` |
| graph-final publication 验证 reservation、当前 epoch/source/extent/content，再执行原 copy；源不是原 atlas | `Rendering/Dependencies/SceneDependencyFrameRuntime.swift:676-824` |

已执行失败在[RF02 A 实施证据](rf02-authored-sampling-implementation-2026-10-03.md)：自有五面板输入，前四项为 atlas/padding 基础图像及 effect，第五项读取 atlas effect。冻结 App 报 image-provider-invalid，145次尝试全部 dropped、0 rendered，未出PNG。改第五项读 padding effect 后原ROI与色值门通过。这是修后冻结 App 的真实反例，不是旧HEAD动态复现，不得把 padding 正例当作 atlas named 已支持。

原失败输入及预登记保留在 `/private/tmp/mwx-rf02/app-integration-v1/` 和 `/private/tmp/mwx-rf02/app-integration-preregistration-v1.json`。既有静态两次截图不证明动画更新相位或严格相邻帧绑定。

## Owner、选型与实施范围

保留单链：authored dependency → prepared graph/extent → 原 dependency reservation → provider effect 执行 → 原 publication → named consumer → 唯一 terminal compositor。普通帧不新增 source 分析、反射、hash 或 registry。

1. **现有 extent/reservation owner 分开两种资格。** raw source 捕获继续使用原窄 mapping profile。实际计划要求 graph-final、且其 prepared extent 已存在时，按该 graph 输出预留，不让原底图零起点规则决定 graph 输出准入。provider 身份和实际 texture 的 type/sample/usage 仍校验。Candidate 存在时，raw 与 graph 两路均保留 texture/candidate 对应、purpose/content/sampling 及 physical/mapped 有限、正整数、mapped 不大于 physical、physical 与真实 texture 尺寸一致的完整性条件；合法映射还须 UV 有限、正轴且在纹理范围内。现 specialized atlas 加载器合法返回 texture、sprite/sampling 而 candidate 为空（`Resources/Textures/SceneBaseImageTextureLoad.swift:404-414`）；prepared graph 已由同轮 source request/uniforms 及后续 graph publication 验证，所以该路不以原底图 candidate 存在为前提，不伪造 candidate。raw 路缺 candidate，或合法 candidate 不满足零起点/比例 profile，均为普通视觉不支持；存在却损坏的 candidate 仍硬拒。reserve owner 必须核非空 prepared extent 与 requiredGraphOutputProviderLayerIDs 的计划关联，static captureExtent 不能凭非空 extent 自行授权。required 集仅表示描述符含可见 effect，并不证明本帧存在可执行 prepared graph；extent 为空时保留原 raw/geometry/utility source fallback 资格，不能仅因 required 集包含该 provider 就拒绝整帧。可复用既有元数据校验，但 SceneTextureSlotBinding 另有面积阈值与更窄内容规则，不能未经证明把它套到原 raw 成功路径造成退化；也不得改 B producer 的阈值或复制一套 validator 家族。
2. **把普通视觉不支持与完整性失败区分。** 对既有 specialized 来源缺普通 candidate 或合法 raw mapping 不支持的输入产生精确 ordinary reason。Preflight 仅把这个 reason 转交现有 typed providerSourceUnavailable，并只在现有 rollback proof 成立的拓扑中保留 previous-current；其它 nil 原因保留硬拒。没有证明的 aggregate、history、clear 或复杂依赖不随本片扩大。
3. **原发布路径保持完整。** 采用 prepared graph-output 准入时，最终 source 必须是本帧 graph-final；不能用 raw atlas 冒充输出。无可执行 Program 时仍由既有 source fallback owner 按原资格发布，不冒称执行了 graph。reservation/publication/target 的 owner、epoch、format、extent、content、usage、非alias与完成生命周期不放宽。两个消费者共享原 provider 资源，帧更新继续由原 source/update owner 提供。

最小产品 owned paths 为 `Rendering/Dependencies/SceneDependencyFrameRuntime+Geometry.swift` 与 `Rendering/Frame/SceneResolvedMaterialFramePreflight.swift`。若真实反例要求触达原 publication 文件，应先给本设计补明确职责，不预批整个 dependency 家族。资源 Candidate/Loader/Catalog/reader 四个 B producer 保持只读；不全局改 axisAlignedMappedUVScale。

备选“所有 reservation nil 都降级”会吞掉 stale identity、budget 和 target 错误，不采用。备选“放宽全局 candidate profile”牵连其它 raw consumer，不采用。新建跨全部调用者的 reservation wrapper/registry 不能增加本片价值，优先复用现有 reason 与 typed unavailable；若现有结构不能保完整性，应先用反例说明必要的 owner 修改，不能靠字符串兜底吞错。

## fallback、纠正门与退役

安全回退由原 GraphExecutor 对已证明的单 effect 保留入口 current；其余原帧/资源拒绝路径不变。本片不增加运行开关、双执行、替代 compositor 或专用样本算法。

验收在实现前冻结输入、期望与容差：

- 原 v1 project/pkg 字节不变重放：五面板原ROI/预期恢复；真实 effect、atlas graph-output publication、consumer binding、terminal PNG、GPU completion 与 drain。不得改为读取 padding。
- 独立 raw atlas 未支持控制：保留四个健康面板，移除 provider effect 以触发原 raw 捕获限制。消费者保留未置换的 entry current，后续帧正常；不得记录虚假成功 publication。保留复杂/history/clear 不安全回退反例。
- 原 padding v2、普通 named source 非回归；计划含可见 effect 但无 prepared graph 时，合法 raw source fallback 仍能预留、发布和消费；新增第二消费者检查同一 provider publication 共享。改变自有 atlas 内容/帧，证明新内容进入 named 输出；静态两图不替代更新证据。
- 原生真实 owner 门：prepared graph extent 与 base physical 不同；相同epoch重复consumer；resize/new target；在飞旧资源保留；取消/重试；真实受限预算。错误texture identity、stale epoch、错reservation extent、source/target hazard仍拒绝。另测非法/非整数/过界 physical与mapped尺寸、非有限/越界UV、未计划provider伪造prepared extent；原极小正比例raw成功路径不得因新metadata门退化。
- 按失败半径执行原生与App模块、Debug build、code-health、scene-defense、design-gate。继承库存超额与本片增量分开报告，不直接抬预算。新增guard须指名违反它的真实输入或故障注入边界。
- 精确冻结产品、测试、App与证据，独立终审后窄提交。原 v1 恢复、局部失败与安全/生命周期门均完成才退役本设计；B companion、aggregate/history和官方全profile parity不随本片关闭。
