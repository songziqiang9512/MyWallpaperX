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

<a id="intrinsic-argument-conversion"></a>
### Intrinsic 参数转换

两 backend 共用原 `BuiltInVectorConversion` 的准备期转换：按语言 intrinsic 签名、词法 binding 和已声明类型形成显式参数转换，不按效果或表达式写法授权。浮点同形参数取非 scalar 向量的最小宽度，scalar 广播到该形状；`dot` 返回 scalar，逐分量 intrinsic 返回共同形状。构造器的固定结果类型及无歧义 helper 的声明返回类型可供外层消费，内部是否合法仍由真实编译器判断。用户同名 overload、value/member 影子及未知类型保留编译器所有权，不猜类型或删除调用。

窄化必须包住已完成的实参：`dot(normalize(vec4(...)), vec3(...))` 先完成四维 normalize，再取前三分量，不能把截断推进子调用。转换不重复求值，不改写 helper 的 out/inout 实参。typed 整数/布尔向量及矩阵不借本浮点规则强转；整数字面量需要浮点签名时显式构造，保留八进制等原值。原四次广播分析、简单 mix 端点和复合 mix 的分散职责由一次分析/转换计划取代；其他 owner 所需的表达式类型查询保留；raw frontend复用同一计划中可完整编码的窄化，保原直接编译能力，不重新lex或创建另一套规则。不增加完整编译器、运行状态或帧内工作。

方言依据为 [Wallpaper Engine 的 HLSL/GLSL 映射](https://docs.wallpaperengine.io/en/scene/shader/mobile.html)及 [Microsoft intrinsic 声明](https://github.com/microsoft/DirectXShaderCompiler/blob/ea3489109cc8a968b36e36ca20a698a68b516d32/utils/hct/gen_intrin_main.txt)；普通 arithmetic 的 [HLSL 转换规则](https://microsoft.github.io/hlsl-specs/specs/5-Expr.html)不能单独代替 intrinsic 资格。验收覆盖不同宽度、scalar、嵌套构造、完整复合求值、改名/alias/helper、用户 overload 和局部失败，经真实双 backend Metal 数值、作者内容与独立邻例验证。官方固定客户端的最终像素一致性另需对照，编译资格不作 parity 声明。 行为门见[双backend数值](../../../script/tests/test_scene_shader_scalar_vector_builtin_canonicalization.py)、[作用域与复合参数](../../../script/tests/test_scene_smoothstep_vector_broadcast.py)和[uniform逐draw更新](../../../script/tests/test_scene_uniform_invariant_shader_constants.py)。

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

<a id="source-channel-layout"></a>
### 数据图片的源通道布局

数据用途由实际 sampler 决定，图片布局由解码结果决定；不能要求 mask、normal、noise 等输入先具有颜色图片的 RGB/四通道形状。原 `SceneImageTextureUploader.sourceRGBA` 在资源准备入口消费实际 packed 8-bit RGB/RGBA、灰度/灰度加 alpha 及既有 padding/字节序，直接写入原 RGBA8 上传数据：灰度复制到 RGB，无 alpha 补 255，实际 alpha 与透明 RGB 保留。此转换不经 ICC、颜色 raster、反关联或重新解码，不为效果名、文件名或作者样本选路；复用原 mip uploader、Candidate、Catalog 和 sampler，无新增 owner、纹理副本或普通帧工作。

只替换原固定通道数量及灰度颜色用途限制；保持实际格式、stride/载荷边界、decode table、premultiplied、float、数据 resize 与未实现精度的消费边界。一个 authored mip 无法消费时仍不发布部分纹理，健康其他资源和后继保原局部失败。16-bit straight-albedo 的已有转换不扩大为数据精度资格。

验收使用原 loader 的混合灰度 JPEG/RGB mip 链、每级实际 GPU 读回、资源改名、透明 GA/RGBA 与 RGB/灰度及坏后续 mip；随后核原作者失败槽恢复真实材质、publication、下游采样和 terminal，另用受控 mask 值及独立作者邻例验证可见输出。输入布局转换成功不授全部颜色格式、任意特效或逐资产最终贡献。

<a id="named-input-ownership"></a>
### Named 输入与发布

多来源输入由实际 prepared 资源接口决定。作者声明保原 effect/pass/slot 顺序；所选模板与已准备变体的实际 sampler、Resolution 等资源需求决定外部输入，graph `previous` 覆盖的 provenance 和变体死槽不额外获得 provider owner。准备与热更新沿原 Catalog、Program fold 和 DependencyPlan，不新增许可 token、registry 或第二次完整编译。

输入接口的槽位与名称和变体内的通道用法分别归属。PMA、straight 与数据变体可以有不同的已编译通道事实；相同资源接口不能因这些事实不同而整体拒绝。颜色适配与局部失败证明消费实际生效的 typed ABI，不以编译 profile 名称或未被实际 emitter 采用的旧标志授予许可。

定义 material 的输入与 instance override 共同形成实际绑定；没有 override 不表示没有 pass 或 named 输入。原 prepared graph/material 保定义 pass 的来源，候选资源准备沿同一 typed 引用形成，实际编译再收敛需求，不能要求作者重复填写 instance textures 才能获得 provider。

- 材质编译负责 shader、combo、颜色/数据角色、uniform 与真实采样；资源计划只负责精确 provider、投影/来源能力、依赖顺序和循环。可执行的普通 solid/image 与 utility 消费同一有序资源向量，不按效果名、blend combo、固定槽数或 pass0/slot1 放行。同一 provider 多槽保每个 consumer 身份，共用原 publication；前向隐藏 graph 读取同一上游的多个 primary 槽也沿原有序 Binding 和供货闭包执行，不再以引用数一为条件。单来源的既有直接合成语义不能被当作任意 shader 的执行替身。
- Aggregate 在准备入口形成唯一有序 Binding 数组，slot 留在各 Binding 中；不另存作者顺序数组，不在每帧重建 Dictionary/Set 认证静态结构。Program fold 按实际 stage/slot 消费多个输入，成功 stage 与局部旁路分别形成当前需求；失效输入不能借首 provider、错误槽或其他 publication 顶替。
- Runtime 只消费该准备结果，并在实际资源处核当前 activation、epoch、publication、纹理及 pin。缺供货使真正依赖它的 operation 局部保 previous-current，健康后继继续；跨帧/错误纹理不能进入普通视觉失败路径。现有 provider 尚无 source/graph 消费者、secondary、forward 依赖顺序或局部投影不成立时，保其具体缺口，不靠清除元数据假装支持。

原提交 ledger 在 named 输入预约到实际 publication 之间保本帧 request、原 targets、该层准备时的 previous tails 及原 pool/观测输入。正常帧仍只准备一次命令；只有实际供货缩成原向量的严格子集、存留资源身份未漂移且尚未编码时，才沿原 Executor 用同一 frame、Program、leases 和 clock 重准备本层，更新原 blueprint/tails。原 commit 保有 history 完整 swap 环的 pin，恢复只消费其覆盖的真实 token；不二次提交 allocation，不预生成备用命令或新建恢复 owner。上下文在原 ledger 编码/终态退出时释放。普通语义/失供货回退由实际入口的 typed 分类与已准备 rollback 拓扑决定，不用 failure 字符串名单重新认证。

Utility graph provider 在原 utility 触发点取 source、执行与发布，不再由普通 provider prepass 重复执行。原 compositor 的发布回调消费同一 graph ticket；当前可见输出继续主合成，隐藏输出只完成 named publication。发布统计的 named/visible 类别不改变取源时机。普通供货缺失沿既有局部 discard，错误 identity 仍拒绝；不以 alpha=0 代替隐藏，也不另存可见状态或恢复命令。

回归沿[依赖计划](../../../script/tests/test_scene_dependency_render_plan.py)、[真实 Metal 执行](../../../script/tests/test_scene_resolved_material_graph_executor.py)、[提交生命周期](../../../script/tests/test_scene_resolved_material_runtime_bridge.py)和[签名 App 输入贡献](../../../script/tests/test_scene_mixed_provider_abi_integration.py)分别核对准备、供货、执行与像素。绑定或非黑不足以证明每个输入贡献；实际覆盖与未取得的资格归[运行证据](runtime-evidence-current.md#coverage)。

<a id="independent-named-source"></a>
### 独立来源的 named 发布

来源是否依赖合成顺序，由它真正读取的内容决定。普通图片、文字、solid 的独立来源与 geometry 沿原捕获器发布；没有成员、没有效果的 composition 在 `copyBackground=false` 时拥有透明空来源。它不读取 enclosing attachment，按需直接清原 reserved named target 并发布，不造空 Program、graph ticket、group target 或第二份纹理。已预约的空来源只消费原 target 尺寸，不因局部画布与主屏投影不同而重算捕获尺寸。solid 消费 candidate 的真实颜色表示，straight RGB 在捕获时关联自身 alpha 后发布 PMA；已有 PMA 不重复关联，并保真实 source texture 与本帧 tint/alpha。不能因 provider 位于 consumer 后面就被 kind 白名单拒绝。effectful provider 仍消费实际 graph 输出，不能以清空或 base texture 冒充材质结果。

这些独立来源可由原 forward prepass 供货，实际顺序点再次遇到时复用原 frame epoch 的已发布 target，不二次捕获。读取 attachment prefix 或成员 subtree 的来源保原取源截点；不能为满足前向引用而挪到全局 prepass、借父组背景或使用上一帧。执行计划使用 utility 展开顺序与原捕获 trigger；cold candidate 的准入仍使用原始 renderOrder，二者的准入差异尚未统一。独立来源的提前准备不改变作者主合成顺序。

缺 source 或普通编码失败只使消费它的 operation 保 previous-current，健康后继继续；错误 epoch、resource、content、extent 与 pin 仍由原发布/资源入口拒绝。验收沿现有依赖计划、composition source 与签名 App 门：前/后置 solid 同像素，资源/ID/槽位改名、真实 alpha/tint、无效果透明来源与彩色 enclosing prefix 可区分，缺源及健康 peer 有正反例。无需求不分配或发布；原作者定向复验只授实际 source→publication→sampler→terminal 链，不外推背景前缀取时或逐资产最终贡献。

<a id="named-source-execution-cuts"></a>
### Named 来源的执行截点设计

来源的资源预约与内容就绪是两件事。读取 enclosing attachment 的 raw 来源只能在原作者捕获位置取得 prefix；独立图像、solid 和透明来源可以提前准备。目标是让 `O → U(prefix) → C → P(hidden)` 在 U 捕获后、C 编码前执行 P，而 `C → U → P → D` 中早 C 局部缺 P，晚 D 仍取得 P 的正确结果。不能为了早 C 提前执行并发布降级 P，污染后面的合法消费者。

原 DependencyPlan 与 FrameRuntime 缓存当前根可达的 prepared DAG，使用 utility 展开后的实际顺序、已选 Binding、当前可见 graph 和 model 需求；候选来源准备顺序不是提交或编码顺序。来源准备阶段一次取得原 source、尺寸、MVP/cursor 与 FrameInputs，沿原路径预约 group source 容量，但不创建 graph ledger、bundle 或命令；所有 activation 依原 policy 使用这个实际逐层 pointer 输入求值一次。原 StageCapability 的 prepared passthrough 事实与精确 slot 投影决定本帧不读取的依赖，不能把任意 false 或全局 pointer inside 当作局部取源证明。同一份 Decision 交 Executor 消费，不重新求值。取 ready publication 时也只消费同一份已准备的 binding/slot 选择；同 provider 的其他活跃槽已供货，不得使已停用槽重新进入向量。实际 epoch、纹理、内容或绑定漂移仍在原消费者拒绝，不以放宽一致性比较掩盖选择漏接。原 Coordinator 从唯一 prepared ledger 临时投影 slot 集合，经现有 Bridge/compositor facade 交普通 image、hidden graph provider 与 utility 的同一个 ready resolver；替换只表示全有/全无的 bypass getter。空集合表示当前可消费 ledger 没有预约外部输入，nil 表示没有当前可消费 ledger；不另存状态、不重求 activation，也不将 effect slot 投影应用于无该slot语义的 model albedo路径。实际截点计划同时给出 graph request/ledger 顺序、原预处理供货及每个作者位置前的供货列表，替代互相重叠的 preparation/global-forward 排序。普通 layer loop 只取本位置的列表，不做依赖遍历、source 分析或重复准备，不增加 phase registry、等待状态、第二份 graph 输出或历史分支。

计划只移除该消费者 Binding 的所有 referenceSlots 本帧均不被读取的边；同来源还有一个活跃槽就保留依赖。DAG 准备事实保持，实际截点 memo 比较这个小投影。计划先沿本帧无环绑定确定真实来源最早可用位置，再从消费者向上游传播可满足的请求。raw prefix 位置在 U 原捕获之后；没有合成顺序依赖的来源可用于预处理。可见 graph 自己的作者主位是执行期限，不能为等待更晚输入而推迟或丢弃其主输出；尚未可用的输入保持该消费者原局部失败语义。hidden graph 不为一个过早请求生成临时降级输出，保留给后续可满足的请求。model 的提前需求不能越过真实来源位置；独立 albedo 仍保原提前准备。

完成来源和 activation 准备后，才对实际选中的请求确定 shared/owned、预约外部输入并构建资源 bundle；未选中的候选不创建 ledger/命令。尺寸复用原 extent resolver 与 target policy，不以 desired size 冒充已接受 extent，不重复构建 graph。 同位置供货按原依赖顺序执行，ledger、tail 和实际 encode 使用同一顺序。只有实际 graph 提前执行而主合成在后的可见结果需要已有 owned pair；其他路径保原共享策略。原 raw 捕获器只在来源位置采样，提前列表不能读取空 prefix；较早消费者使用原 unavailable/strict-subset 路径，错误 epoch、纹理、pin 或回执仍由实际资源 owner 处理。正常晚到的同一预约纹理只填内容、一次执行，不触发重编译、二次 allocation 或重准备。准备期尚未到达的 graph 输入局部 unavailable，不以 provider 原图尺寸预约其未来 graph；已尝试但没有 graph plan 的来源仍保原 source fallback。aggregate 消费当帧层快照并保其他健康槽。

验收沿原 Plan、Coordinator 和签名 App 门：有 graph 的前景 O、U 后另一个改变当前背景的图层、早 C/晚 D、真实取时环、`copyBackground=false` 独立邻例及资源/ID 改名。固定 literal ROI 区分 U 的 prefix、全局空 prefix 与 C 当时背景，保健康后继；核 P 一次执行及最终 GPU/终端捕获。graph-background、utility 成员图的来源消费者及官方默认背景语义仍须各自取得实际资格，不能借调度设计放开它们。普通 provider 使用原 layer 前截点；utility 保原 trigger 后执行，同 trigger 后再运行普通 provider 的组合未接入。degraded member 的绘制跳过不跳过其已计划供货，供货只执行 offscreen 内容，成员继续原局部跳过。

<a id="forward-graph-output-consumption"></a>
### 图输出的供货与作者位合成

同帧 graph 结果完成 named 供货，不代表可见层已经完成作者位的主合成。原 Coordinator ledger 保留唯一 texture、content、ticket、history 与 pin；提前供货后的可见层在自己的作者位置借用该结果，沿原 final-composite 消费当前 placement、alpha、depth 和 fog。晚消费不重新 claim、解析依赖、取 layer source、执行 graph、分配或发布，不增加结果缓存、持久标志或第二输出 owner。原 `compositorConsumed` 区分主合成是否完成；晚到的主合成回执只接纳这一消费，不能用上游旧 candidate tails 覆盖已包含后继的 scheduled tails。

强引用和 submission pin 只保 GPU 对象寿命，不能阻止同 command buffer 的后继写入共享工作 pair。Preflight 复用 FrameRuntime 的候选 DAG，在实际来源与 activation 准备后解析唯一截点计划，并返回 SceneDrawing 供 layer loop 消费；仅实际提前执行、主合成在后的可见 graph 选择已有 owned pair，其余保持共享。原 `pairStorage` key、预算、memo、lease、回滚和 pin 承接这项寿命，不复制结果或新增缓存，也不把所有可见 graph 一律私有化。实际准备失败保原局部 fallback，不生成另一份执行排序。

静态 material 的 data 存储只描述成功输出，activation 或局部失败仍可保留之前的 color；分配前不能用它取消可见闭包的 owned 保护。最终内容在 Executor 准备完成后才确定，当前沿原有界 pair 分配保这一潜在消费，不增加扫描、内容缓存或后置复制。

可见 color 结果遇到普通 named publication miss 时，仍保已编码结果与原 lookup，供作者位合成；不伪称供货成功，也不沿 hidden discard 撤销有效主输出。hidden miss 保原局部回退，data 不进入颜色合成，错误资源或回执仍由实际 owner 拒绝最小不安全单元。供货可执行性取决于真实 source 截点；background/prefix、utility 或成员顺序依赖不能借本修复升级为全局 prepass 独立来源。

验收沿原 Coordinator/Bridge 门核 U→P→C 后的晚主消费、history/pin、普通供货失败及重复/过期回执；签名 App 用独立来源的 visible U、hidden P 和更早 C，核双 UV 贡献、作者位遮挡、单次 graph/主消费、改名与 hidden 邻例。先限定这个可复验结果，前缀正确取时和多上游调度仍分别留在原队列。

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
