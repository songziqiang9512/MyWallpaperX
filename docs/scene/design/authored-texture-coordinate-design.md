<!-- document-role: active-plan -->
<!-- retirementCondition: 作者采样坐标与公开 companion 值分别完成本文纠正门，最终职责进入 runtime-architecture 后归档；未证的尺寸与动画 profile 不随前一批隐式批准。 -->

# RF02 — 作者纹理坐标与公开 companion 的职责

本文是 [RF02 工作卡](reference-evidence-implementation-cards.md#rf02-companion)的设计裁决，不改变[兼容路线](../scene-compatibility-roadmap.md)的主任务。复核基线为 `07d45f4a`。设计登记分为两个准入项；第一项的证据不能自动批准第二项。

## 目标合同与证据范围

作者传给二维采样操作的坐标由作者决定。编译器不得在每次采样时额外应用资源的 atlas／padding 变换；作者已经执行的变换不得再次执行。没有作者 shader 的基础图像仍由既有图像合成路径映射纹理帧，effect 已生成的完整输出仍以单位映射进入最终合成。

依据属于 `official-public-contract`：[Shader Syntax](https://docs.wallpaperengine.io/en/scene/shader/syntax.html#preprocessor)定义采样操作接收作者提供的二维坐标，[语言兼容表](https://docs.wallpaperengine.io/en/scene/shader/mobile.html#functions)将 `texSample2D`／`texSample2DLod` 对应到原生采样操作。公开 [Texture variables](https://docs.wallpaperengine.io/en/scene/shader/variables.html#texture)另规定 0…7 槽位的 Resolution、Rotation、Translation 类型和作者用途；公开文档没有给出 companion 的完整数值布局及动画相位。

自有 slot1 探针的官方单次呈现得到 literal 与 active companion 两程序相同的 A/B/C 序列，六个同程序颜色基准分别一致。这支持本次 profile 中没有额外应用同一变换，但不是全部 profile、重复性或动画的动态验收。五组 companion 数值区间与输入身份见[独立复核的观察记录](../../history/scene/rf02-companion-uniform-observations-2026-10-03.md)。动态观察只补强公开合同，不替代它，也不把内部默认顶点代码作为实现来源。

## 当前事实与首断点

下列代码路径均相对 `MyWallpaperX/Core/SteamWorkshopScene/`，行号对应上述基线。

| 事实 | 证据 |
| --- | --- |
| bounded frontend 包装每个作者采样坐标；generic normalizer 同样包装二维与显式 LOD 采样 | `Compilation/ShaderFrontend/SceneAuthoredShaderMetalEmitter.swift:475`；`Compilation/ShaderPreparation/SceneGenericShaderTextureSamplingNormalizer.swift:93` |
| 每个 active sampler 被加入两项 synthetic transform 字段，并按此验证 Program／编译工件 | `Compilation/ShaderFrontend/SceneAuthoredShaderTextureTransformABI.swift:31`、`:66`；`Compilation/Material/SceneResolvedMaterialProgram+Derivation.swift:62` |
| host 编码取 candidate 变换；同槽坐标形状事实可把 synthetic 值换成单位值 | `Rendering/Bindings/SceneResolvedMaterialUniformEncoder.swift:117` |
| 当前公开 Rotation／Translation 没有 host 生产者；Resolution 已有 | `Compilation/Material/SceneResolvedMaterialHostUniformSchema.swift:34`、`:59` |
| 资源帧 producer 已在一个 candidate 中发布纹理、尺寸、采样规则、帧变换和 generation | `Resources/Textures/SceneMaterialAssetTextureCatalog.swift:111`；`Resources/Textures/SceneTextureCandidate.swift:172` |
| 非轴对齐帧目前在 loader 和 material Program 两处拒绝，不能因这批采样修正顺带放开 | `Resources/Textures/SceneTextureLoader+Candidate.swift:235`；`Resources/Textures/SceneTextureCandidate.swift:214` |
| 作者 shader 必须有两 stage；不存在缺失作者顶点阶段时自动补默认 stage 的准入 | `Compilation/ShaderContract/SceneShaderContractLoader.swift:78`；`Compilation/ShaderPreparation/SceneAuthoredShaderPreparation.swift:664` |
| hostBuiltin image 在既有 compositor shader 中使用纹理帧；effect 完整输出最终用单位映射 | `Rendering/Composition/SceneImageLayer.metal:82`；`Rendering/Composition/SceneImageLayerCompositor+Uniforms.swift:40`；`Rendering/Composition/SceneImageLayerCompositor.swift:433` |

本机原生诊断在真实 bounded frontend／Program／Metal pass 路径测得：同一常量采样点，单位 candidate 取 A，axis candidate 取 B，下一 generation 恢复单位 candidate 后又取 A；三次 command completion 成功，pipeline 编译次数始终为一。这个反例使用自有简化顶点及片段程序和测试构造的 typed publication，不是整个 App、generic compiler 或官方同程序 parity 的证据。原始工件位于本机 `/private/tmp/mwx-rf02/native-sampling-counterexample-v2/`，最终独审身份在批次报告固定。

## Owner 与方案裁决

唯一链仍为作者 source → prepared Program／反射 → typed frame inputs／资源 publication → Metal encode → 既有 compositor。

1. **先修作者采样入口。** 两个现有 compiler lowering owner 原样保留作者坐标，保留原 sampler、LOD、通道和颜色边界。退役专用于隐式变换的 synthetic ABI 字段、注入、host 编码与验证；反射和 Program 仍验证实际存在的作者字段。两 backend 必须同批一致，不能靠切换路由藏住另一条路径。
2. **收缩补丁机制。** 取消同槽坐标形状事实对采样语义的控制。追踪其全部消费者，删除仅为抵消隐式变换而存在的 analyzer、元数据和缓存字段；若还有独立职责，逐调用点证明并保留那部分，不保留空入口。对应结构／防御预算同批下降。不能新增“是否声明 companion” matcher 或另一套坐标 registry。
3. **保留基础图像职责。** `SceneImageLayerCompositor` 的固定基础图像采样继续消费同一 candidate 的纹理帧；不改其合法一次映射，不给资源发布值整体置单位值。作者顶点 main 的执行和既有几何输入保持原 owner。完整 effect 输出继续只经唯一 terminal compositor。
4. **随后补公开 companion。** 数值合同冻结后，在现有 HostUniformSchema／typed HostUniform／UniformEncoder 中独立绑定公开 Rotation 与 Translation，值来自正在绑定的同一 candidate。它们不是 synthetic 字段的别名，也不能因作者显式使用它们就改写采样函数。沿原帧 provider 的 generation、commit／discard 机制更新，不能建立第二个动画时钟。

备选“只给新 uniform 填值”会留下重复采样变换；“发现 companion 就返回单位内部矩阵”依赖声明猜算法，且不能修复不读 companion 的常量采样；“所有 candidate 变成单位矩阵”会破坏基础图像的正确映射。三者均不采用。选择移除错误注入并保留真实 owner，既恢复公开语义，也减少结构和每帧无用字段。

## 两项准入、fallback 与缓存

**A：作者采样坐标。** 公开合同和原生反例足以进入本项设计审查，不等待全部 companion profile 的黑盒重复采样。它不批准非轴对齐资源、修改 sprite reader 或扩大 texture admission。现有合法 axis／padding candidate 必须可以绑定 raw sampler；若旧准入条件仅服务已退役内部 ABI，只移除已证明无消费者的部分，其余 GPU range、purpose、identity、publication 完整性门保留。

**B：公开 companion 值。** 当前保持 `blocked-pending-design`。必须补齐不相等 physical／mapped 尺寸的响应与 Resolution 交叉验证、动画帧与实际采样一致的更新相位，并明确非 sprite／provider、stage、数组与错误类型的处理。现有 axis/off-diagonal 数值只约束各自已测 profile。不能在实施 A 时顺手决定这些值；未定案的视觉能力继续局部拒绝并保留 previous-current。

改变采样代码、uniform layout 和缓存解释后，所有会复用旧语义的 prepared analysis、编译工件、持久化 Program 缓存均须明确失效。逐个实际读写入口确定版本退役，不以只 bump 一个分析版本代替下层工件退役。冷／热启动都要证明旧工件不被复用，普通帧不新增 source 分析或摘要计算。

不增加新产品 route，继续现有 `generic-only` 主路由及其显式共享 fallback；两个 compiler 都执行同一目标语义。shader 视觉失败按现有最小 pass／effect 降级；stale generation、ABI、非法 GPU range、target hazard 仍硬拒绝最小 unsafe unit。回退不得静默恢复已证错误的额外坐标映射。

## 纠正门与交付

- A 的修前红例：同一 literal coordinate 在单位／axis candidate 下取相同源 texel；作者显式映射一次只产生一次结果。先记录真实 GPU 反例，再在两 backend 跑同源输入、不同槽位、非方形纹理、显式 LOD 和下一 generation。观察 output／completion，不断言生成源码形状。
- 基础图像正证：无作者 shader 的 atlas／padding 映射仍正确；带作者 vertex 的 raw varying 与显式映射分别符合输入语义；effect graph 输出最终不重映射。用隔离内容验证 publication、terminal compositor、下一帧和局部失败保留安全输出。不得用测试构造 publication 冒充真实 producer 验收。
- ABI／缓存反例：旧工件、错误类型、数组／stage 冲突、slot hole、stale resource generation 不可通过；真实缺省／反射字段和 cold/warm 编译行为一致。不能以关闭缓存通过此门。
- 执行对应 compiler／material／texture／provider／compositor 模块、Debug build、code-health、scene-defense、design-gate 与实际结构 ratchet。每项新增 guard 都指明违反它的生产者；只对 A 实际触及的职责选择检查。
- 精确冻结 owned diff、输入和执行证据，独立终审后按职责提交。A 验收不改 B 的 blocked 状态，不宣称官方全 profile parity。B 另按其冻结合同完成 producer→消费者→可见输出正反门。

## 退役条件

A 的实现和实际输出纠正门通过后删除对应临时设计门登记；B 的数值／生命周期职责验收后同样退役。稳定职责交接 [runtime-architecture](runtime-architecture.md)，本计划归档。证据不足不算能力完成；协议或诊断脚手架在用途结束后不进入普通播放路径。并行文件只保留其他作者的改动；结构 ratchet 必须以本批精确增删更新，不宽泛覆盖工作区。
