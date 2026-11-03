# Shader、材质与 Graph 执行

<!-- document-role: current-state -->

<a id="ingress"></a>
## 源码与准备入口

作者 shader 沿现有 GLSL-like normalization → glslang → SPIR-V → SPIRV-Cross → MSL 编译链准备；有界 Swift frontend 是具有明确输入范围的共享回退。两者复用源身份、uniform/sampler、颜色事实及 Program，不按效果名创建 renderer。

准备阶段完成 include、宏、combo/pass、语法、活跃接口、变体、uniform layout 和 PSO 预热。普通帧只能选择已准备变体并绑定当前值；缺 key 返回 typed failure，不回到编译器。

- shader 注解保留源行、原声明和诊断。仅被现入口分类为纯注释 COMBO 损坏记录的情形可跳过该条 metadata；不伪造 annotation/default，也不吞代码、inline 声明或来源完整性错误。
- `VERSION`/`SHADERVERSION` 没有可信客户端版本 provider。未消费记录不阻止无关源码，但不能注入宏或授权实际版本分支；活跃读取仍拒绝。
- sampler 的 editor `require` 不代替运行 readiness。实际声明、候选绑定与编译后的接口决定资源需求。
- backend 已删除的纹理参数只有在实际 MSL 接口缺席且没有 Resolution 活读时才退出绑定。fragment-dead varying 的纯顶点计算按既有数据流证明投影；live `gl_Position`、副作用、歧义和实际 inverse 消费不能被删或补 identity。
- uniform 派生只读常量由原 frontend/normalizer 降低。实际资源、类型、反射及 ABI 仍在原入口验证，不能用 metadata 推出整段 shader 已可执行。

Generic 当前有固定 float varying 数组的有界路径，较宽数组要求双 stage 完整匹配并受实际接口预算；bounded 的类型、索引和展开限制独立。未支持的语法局部拒绝，不交另一个 backend 猜执行。

源码：[Shader preparation](../../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneAuthoredShaderPreparation.swift)、[frontend](../../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderFrontend/SceneAuthoredShaderFrontend.swift)、[TemplateCompiler](../../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialTemplateCompiler.swift)。

<a id="execution"></a>
## Prepared 到每帧

`RuntimeCatalog` 准备模板及资源需求，执行能力构造器准备 graph/material 能力、变体与 frame-input 合同；运行 catalog 只保消费者所需声明及 claim。`MaterialCapability.bindFrame` 选择已准备结果，Finalizer 解析本帧资源与值，PassEncoder 查询预热后的 PSO，GraphExecutor 编码。

源码：[Finalizer](../../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialProgramFinalizer.swift)、[PassEncoder](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPassEncoder.swift)、[GraphExecutor](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialGraphExecutor.swift)。缓存边界见[启动合同](../architecture/scene-launch-responsiveness-contract.md#cache)。

<a id="sampling"></a>
## 资源来源与采样

Material、instance、user texture、effect 显式 binding 及 shader default 保留各自候选链与 provenance。显式 FBO 由准备好的 graph identity 接入；没有真实角色的 slot0 不自动变成 framebuffer。闲置 default 不能否定已经胜出的合法候选，缺失候选也不能被伪装为 ready。

`_rt_` 名在原 `SceneRenderTargetVocabulary` 入口转成 typed identity；显式作者 FBO、同层 composite、跨层 named 与未知名字分别处理。普通帧不重复解析 token。

- UV、显式 LOD、wrap/filter、physical/mapped extent 与 TEX frame transform 沿同一 candidate 传播，不能在 loader、host uniform 和 shader 中重复施加 atlas/padding 变换。
- Sprite 的 Rotation/Translation 取原 frame 轴和原点；Resolution 取同一 candidate 的物理与映射尺寸。已完成映射的 non-sprite 输出按当前 companion 合同编码，不把此策略推广成所有官方 provider 的默认。
- 真实空槽 Resolution 的名义 `[2,2,2,2]` 只用于已证明精确成对归一化、无 default 且 template/frame 都为空的路径；pending/nonempty 槽不能套用此值。
- 纹理 reduction 改变工作采样域，不改变最终放置与原材质语义；source-sized raster、camera projection 与 terminal placement 分别消费各自准备事实。

<a id="color"></a>
## 颜色、数据与显示

source identity、采样用途、颜色表示及物理格式是不同事实。颜色与数据、二维与volume不能因存储相似而互换。

<a id="scalar-data-read"></a>
已证明只读红通道作phase权重的shader接纳非volume二维data。ShaderSchema在准备期区分读取角色与资产用途，保选中noise、normal等原purpose；TextureSlotPurpose复用该关系验证candidate链后直接生成事实，退出无source proof的继承检查。其他source proof保持原合同，颜色/volume冲突局部拒绝；后续Program、selection与binding仍消费精确purpose、publication和二维data表示，普通帧不重新证明。回归见[标量数据GPU](../../../script/tests/test_scene_scalar_mask_data_purpose.py)。

Program 只对已证明的颜色槽做 PMA/straight 适配；data/signal 保原通道。有限 HDR RGB 保留到作者运算与终端，不能提前裁到 0–1；零 alpha 和输出 coverage 沿现表示合同。作者显式饱和仍执行。

独立顶层可见文字的首个 effect 若直接把 layer source 写入后续读取的 framebuffer，准备期可选择保留文字下方当前背景的 RGB：source capture 使用 `glyphRGB + prefixRGB × (1 − glyphAlpha)`，alpha 仍为 glyph coverage。该资格只用于 captured-layer source；图 provider、parented text、image、无后续读取或被覆盖的 target 均沿原路径。SDR/HDR 使用同一颜色合同，不把背景 alpha 混入字形 coverage。

仅红通道 scalar 或 alpha-only 读取有各自准备证明，不能从一条 swizzle 推出整张纹理是 mask。未知用途、混合颜色/数据流或反射不守恒保持局部拒绝。R/A preserved-channel 路径不能外推所有 `.xw` generic artifact 已有完整输出证明。

HDR 合成与显示 EDR 分开：scene color/Bloom 先保浮点范围，唯一终端进行 SDR 裁剪或当前显示 headroom 映射。normal/roughness 不做显示变换。截图导出是普通预览，不能证明物理 EDR 高光。当前 light/receiver 范围见[光照](advanced-object-coverage.md#lighting)。

<a id="history"></a>
## Target、copy 与 history

Prepared target/transition 保有序读写；pool 租约、publication 与 completion 绑定实际 command buffer。unique history 的 seed、reused、失败与取消由原 Coordinator 管理，不靠普通帧重建或全图哈希恢复。

<a id="composite-input-admission"></a>
前级双输入合成沿[全效果统一合同](../../architecture/technology-stack-boundaries.md#31-swift-拥有产品状态语言运行时拥有语言语义)准备。Layer admission持源route，Graph计划持有序读写、target和history；Variant按活跃采样槽、选中用途及producer内容形成颜色边界，Program/Finalizer持uniform、purpose/表示和publication，MSL lowering与PSO检查实际接口。Pass数量、target数量、kernel、方向、scale或静态tint不另授执行许可；失败只影响真实不兼容单元并保previous-current。已定义的透明clear可作输入，缺失的实际纹理不能伪装ready。

没有typed边界的兼容改写及尚未表达的通道推导仍有有界source/MSL分析，属于[待通用化边界](../development/development-workflow.md#compatibility-exceptions)。沿原compiler/typed ABI补真实缺口，不增加效果族名单、source许可token或第二套资源/输出owner。具体输入和资格归[运行证据](runtime-evidence-current.md#coverage)。

<a id="typed-color-compilation"></a>
### Typed 颜色编译

`SceneShaderColorBoundary`直接支配普通颜色Program及既有ordinary编译路线。ArtifactBuilder按该边界对实际编译MSL适配采样/返回，产物解码与Program消费相同边界；准备期不再先执行另一段会被丢弃的专用改写或整族source分析。动态颜色沿原uniform producer、当前值与ABI编码，不需要static许可。

普通颜色metadata以该边界的straight、opaque或PMA输出为权威；alpha-only、packed data、独立signal、有序signal/underlay及其storage/loop事实保原typed语义。Passthrough保精确signal槽，数据通道不做颜色适配。已准备的graph ingress事实仅按真实活跃slot投影，不能从输出颜色标签重推身份；仍有实际依赖语义的previous shadow保持。实际接口、uniform字节、选中publication、target/hazard及生命周期错误各在原consumer局部失败。两个backend消费同一边界，普通帧不做source分析或编译。

回归沿真实builder→Program→Metal门核helper/条件/多sample、改名、动态uniform及PMA/straight/alpha/HDR，另核合法data/signal与错误供货/表示/身份。源码模式命中不作验收；未支持的MSL操作和未表达角色按具体失败入队，不以效果模式绕过。

Surface 采用已提交销毁成员时，原 Coordinator 过滤该层 committed 及 pending final tails，保已编码 ledger/pins 到原终态。活 named consumer 的独立 copy、hidden provider、consumer 自身 tail 与 scene color 按真实引用保留。

<a id="terminal"></a>
## 终端材质重放

终端 replay 是同一 GraphExecutor 内的可选优化，保源尺寸采样、冻结输入、真实输出投影与唯一 MainPass。后继 passthrough 不丢最后有效材质；后继成功材质替换候选。只有真实写后读冲突才创建同 descriptor 副本，并沿原 submission 保留。

当前简单 color/placement、部分文字及 captured-main 路径有各自准备资格。复杂 FBO/history/function/geometry 等未取得优化资格时继续原 graph 路线；不能把优化条件升级为所有合法内容的永久门。写入主 pass 后的失败拒绝不安全提交，不能再次合成 graph-final。

<a id="limits"></a>
## 当前边界与回归

任意 Shader 方言、所有数组/动态控制流、全部 sampler/provider/颜色组合、LUT 材质 consumer 与完整 HDR/官方像素等价未覆盖。具体未闭项归[队列](../roadmap/scene-open-breakpoint-queue.md)。

最近行为入口：[PassEncoder/GPU](../../../script/tests/test_scene_resolved_material_pass_encoder.py)、[copy/history](../../../script/tests/test_scene_material_copy_history_rendering.py)、[准备取消](../../../script/tests/test_scene_source_preparation_cancellation.py)。这些门分别验证其真实输入，不能相互代验全部语言或画面。
