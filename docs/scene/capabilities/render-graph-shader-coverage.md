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

Generic 的固定一维 varying 数组沿真实双 stage 完整匹配和组件预算准备，不以float/向量元素类型或16/32项数量授播放许可；大于16项接口保原124分量预算，bounded 的类型、索引和展开限制独立。未支持的语法局部拒绝，不交另一个 backend 猜执行。

<a id="generic-varying-array-budget"></a>
### 固定数组接口的准入设计

原 Generic SourceNormalizer、glslang 联合链接与 SPIR-V→MSL→Metal 承接合法固定数组，以真实接口能力准入。作者接口有完整活读的 `vec2[49]` 与独立 `vec2`，共100个浮点分量；保全部邻域，不缩数组前缀。该层默认隐藏，原源码恢复准备不等于默认画面恢复。

现有大于16项的扩展路径不设独立的元素数量许可；保持双阶段同名、同元素类型、同维度与同长度，由原 Shape 表与组件预算核实际完整接口。原解析入口仍限制固定一维数组及有界输入，扩展路径沿原124分量预算计价，真实编译与 Metal 库/管线仍决定后端执行能力。原不大于16项路径保持，不为此次扩展增加普通帧检查、shader重写、展开器、ABI字段、缓存或第二接口owner。非浮点插值的限定符和其他语言能力不由本批预支。

验收包括 `vec2[49]` 的全部元素、动态索引/插值与多点独立数值，改名及等价循环、标量/向量相邻输入、双阶段不匹配、越预算与真实编译失败反例；经原 Program→Executor→Metal 或签名 App 核最终像素，不能以 normalizer 通过代后端支持。真实作者原 contract 使用同输入准备并保实际激活边界，另取未参与修复的活动样本核播放。新增规则失败局部沿原 effect 旁路，bounded 限制不反向成为 Generic 许可。

源码：[Shader preparation](../../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneAuthoredShaderPreparation.swift)、[frontend](../../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderFrontend/SceneAuthoredShaderFrontend.swift)、[TemplateCompiler](../../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialTemplateCompiler.swift)。

<a id="prepared-dead-fragment-sampling"></a>
### 准备期无输出消费者的采样

资源需求来自本变体真正保留的计算。对 main 顶层、初始化无副作用且结果没有任何存留消费者的局部值，原冷编译投影可沿已有逆序局部闭包删除其纯采样和中间计算；emission、sampler/uniform ABI 与资源需求必须同源退出。不能只放宽缺绑定检查、删除某个纹理参数或按 shader、material 属性名、路径、样本识别，不能为隐藏 sampler 猜 background/previous 或补默认纹理。

复用 DeadBindingAnalyzer 的 statement、binding 与副作用事实，在 BackendCanonicalizer 的共同 vertex/fragment 输入和有界 frontend emitter 承接同一删除结果；保原作者源码、身份与诊断位置，不建另一套 IR/SSA、Program 字段、native probe、状态或普通帧分析。只是物理纹理接口缺席仍不足以取消 Resolution、vertex/varying 或 attachment 的逻辑输入。已有顶点死 varying 投影和相邻准备语义保持。

采样结果若到达颜色/alpha、position、varying、discard/控制条件或其他活读，其来源仍必需。初始化含 mutation、out/inout、全局写、未知/被遮蔽的调用、宏或无法证明的控制流时保原语义与需求，不为证明不足新拒 shader；纯性必须识别实际语言内建和作用域，不能把同名作者函数当内建。非法写入、类型/调用与源位置边界不因删除优化绕过原语义检查。

原 dead-binding 行为门覆盖改局部/资源/槽位名、等价纯表达式及死值链，同时核两 backend 的 emission 和 ABI；活读、alpha-only、Resolution-only、vertex/varying、branch/discard、坐标副作用及 helper/global 写保持原语义。bounded 不支持的 discard 仍保原边界；非法调用分别核 AST/发射与实际 Metal 库编译，不能以存在接口当完整接纳。签名 App 的 source 与 effect 死采样控制已核可区分像素，活缺资源仍只回退当前 effect 并让健康后继完成。具体作者断点与验证范围由[运行证据](runtime-evidence-current.md#coverage)维护，不授任意控制流 DCE、官方像素或性能。

<a id="unbound-texture-resolution"></a>
### 未绑定可选纹理的 Resolution

实现合同：可选 sampler 未设置来源且当前变体不采样时，Resolution 的数值消费不得被当成必需 GPU 纹理。`material` 是作者纹理键，不能按 textbuffer 等名称猜文字或 previous 来源。[官方纹理合同](https://docs.wallpaperengine.io/en/scene/shader/variables.html#optional-visible-texture)只定义绑定资源尺寸；固定客户端的未绑定数值观察及边界归[运行证据](runtime-evidence-current.md)。

当前修正采用原准备链上的常量降低：原 Schema/Template 一次确认没有 authored candidate、shader default 或 graph/current 来源，真实 readiness 关闭且没有采样后，将该槽的 `vec4 Resolution` 降为已资格的 `vec4(2)`，保留作者后续计算。共同 compiler 输入供 bounded/generic 使用，不建第二 metadata/store/clock，不伪造纹理，也不加普通帧分析或 nil-resource fallback。该规则适用于多个槽及任意合法表达式，不再要求固定 UV 乘除形状。已声明但文件缺失、pending、default、named、graph/current 和真实采样继续原资源选择与失败半径；不能将它们压成“未绑定”。

复用现有准备身份和缓存版本退出旧分析，保作者原始源码与诊断身份。被替代的中性 UV AST 许可及无消费者的 fact/cache/frame 透传同批退出；若尚有独立消费者，只保其原范围并明确后续退出条件，不能为新表达式追加白名单。

验收使用直接 x/y 与等价表达式、改变量/资源名及多未绑定槽，核两 backend 和实际 Metal/终端像素；真实资源/default/named 尺寸、缺文件与 pending 以及活跃缺采样保反例。作者 1087 的拒绝消除须由原 Program 实际执行与最终命名消费者确认；准备通过不能代替画面恢复，不授全字体、完整圆环或性能一致。

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

<a id="framebuffer-source-declarations"></a>
### Framebuffer 来源与声明依赖

source 的角色由模型、材质及实际编译输入决定。已声明 passthrough、单一 source pass 和 typed framebuffer 输入的模型，由 RenderDescriptor 提名沿原 framebuffer source 路径准备；RuntimeCatalog 仍编译原 source Program，并要求它实际保留的候选只能是本层的 slot0 `sceneBackground`。普通资产、named layer、其他 framebuffer 或动态来源不能被当成本层当前主附件。原形状、render state、透视与 child 范围不因本条扩张。

图层的 `dependencyLayerIDs` / `authoredDependencies` 不替换 source material 的输入，非空声明不能独立取消合法 source。effect 真正采样的 named 输入继续由已选 Program/DependencyPlan、当帧预约、供货及局部失败承接；不把当前 main prefix 冒充某个命名层的最终输出。声明指向较晚层也不移动本层 source 的作者捕获点。Descriptor 与 Catalog 的两处空依赖许可退出，其余准备、资源与实际读取仍归原 owner，不新建状态或普通帧校验。

验证沿原角色解析门和完整 native-world App：无依赖、只声明早层、只声明晚层及资源改名保持同一 source/effect/父变换/深度像素和健康 peer；实际改成 named source 的材质必须保持自己的输入语义，不能借声明等价取得 framebuffer 身份。已有 named/late-miss 门各保自身供货范围，不能代 native-world 与任意 named 组合资格。带依赖 utility 的 effect 热显隐仍有原准入门；layer 显隐使用原消费者，本条不授 native-world 与声明依赖组合的热切换资格。

<a id="named-input-ownership"></a>
### Named 输入与发布

多来源输入由实际 prepared 资源接口决定。作者声明保原 effect/pass/slot 顺序；所选模板与已准备变体的实际 sampler、Resolution 等资源需求决定外部输入，graph `previous` 覆盖的 provenance 和变体死槽不额外获得 provider owner。准备与热更新沿原 Catalog、Program fold 和 DependencyPlan，不新增许可 token、registry 或第二次完整编译。

输入接口的槽位与名称和变体内的通道用法分别归属。PMA、straight 与数据变体可以有不同的已编译通道事实；相同资源接口不能因这些事实不同而整体拒绝。颜色适配与局部失败证明消费实际生效的 typed ABI，不以编译 profile 名称或未被实际 emitter 采用的旧标志授予许可。

定义 material 的输入与 instance override 共同形成实际绑定；没有 override 不表示没有 pass 或 named 输入。原 prepared graph/material 保定义 pass 的来源，候选资源准备沿同一 typed 引用形成，实际编译再收敛需求，不能要求作者重复填写 instance textures 才能获得 provider。

冷启动关闭的普通 effect 沿[输入准备合同](runtime-input-property-coverage.md#properties)保留真实 Program 与 Binding，不再因 DirectBool 来源加一层整层 named consumer/声明依赖禁令。准备仍以实际 graph 和停用拓扑为准；本帧需求沿[唯一 activation 与 slot 投影](#named-source-execution-cuts)选择，潜在输入不取得执行权，其他活动 slot 也不能使停用 slot 重入。standalone utility 与 provider 的现有准备边界保持；真实入口与 off/on/off 像素结果归[运行证据](runtime-evidence-current.md)。

隐藏、无子层、无 utility 且无声明依赖的普通 text 保留自身 named 来源，不因存在活动效果取消 carrier。复用现有 imageLayerBlend 与实际 active effect 推导的 requiredGraphProvider 集合：有 FramePlan 时经原 Program 执行并发布 graph-final，不能以 raw glyph 捕获冒称效果执行；没有 Program 时的精确 base-source fail-soft 与图内局部旁路仍沿原 owner，保留实际降级事实。text 的 ready source、PMA、已接受 graph extent、frame epoch 与 ledger/publication 生命周期保持，visible effectful text 和其他来源域不随此范围开放。可区分着色效果、改名及缺资源/补资源的真实输出见[运行证据](runtime-evidence-current.md)；material 纹理键不授隐式文字资源；未绑定可选输入的 Resolution 数值由[原 shader 准备合同](#unbound-texture-resolution)处理，作者当前执行与画面资格归运行证据。

- 材质编译负责 shader、combo、颜色/数据角色、uniform 与真实采样；资源计划只负责精确 provider、投影/来源能力、依赖顺序和循环。可执行的普通 solid/image 与 utility 消费同一有序资源向量，不按效果名、blend combo、固定槽数或 pass0/slot1 放行。同一 provider 多槽保每个 consumer 身份，共用原 publication；前向隐藏 graph 读取同一上游的多个 primary 槽也沿原有序 Binding 和供货闭包执行，不再以引用数一为条件。单来源的既有直接合成语义不能被当作任意 shader 的执行替身。
- Aggregate 在准备入口形成唯一有序 Binding 数组，slot 留在各 Binding 中；不另存作者顺序数组，不在每帧重建 Dictionary/Set 认证静态结构。Program fold 按实际 stage/slot 消费多个输入，成功 stage 与局部旁路分别形成当前需求；失效输入不能借首 provider、错误槽或其他 publication 顶替。
- Runtime 只消费该准备结果，并在实际资源处核当前 activation、epoch、publication、纹理及 pin。缺供货使真正依赖它的 operation 局部保 previous-current，健康后继继续；跨帧/错误纹理不能进入普通视觉失败路径。现有 provider 尚无 source/graph 消费者、secondary、forward 依赖顺序或局部投影不成立时，保其具体缺口，不靠清除元数据假装支持。

原提交 ledger 在 named 输入预约到实际 publication 之间保本帧 request、原 targets、该层准备时的 previous tails 及原 pool/观测输入。正常帧仍只准备一次命令；只有实际供货缩成原向量的严格子集、存留资源身份未漂移且尚未编码时，才沿原 Executor 用同一 frame、Program、leases 和 clock 重准备本层，更新原 blueprint/tails。原 commit 保有 history 完整 swap 环的 pin，恢复只消费其覆盖的真实 token；不二次提交 allocation，不预生成备用命令或新建恢复 owner。上下文在原 ledger 编码/终态退出时释放。普通语义/失供货回退由实际入口的 typed 分类与已准备 rollback 拓扑决定，不用 failure 字符串名单重新认证。

Utility graph provider 在原 utility 触发点取 source、执行与发布，不再由普通 provider prepass 重复执行。原 compositor 的发布回调消费同一 graph ticket；当前可见输出继续主合成，隐藏输出只完成 named publication。发布统计的 named/visible 类别不改变取源时机。普通供货缺失沿既有局部 discard，错误 identity 仍拒绝；不以 alpha=0 代替隐藏，也不另存可见状态或恢复命令。

回归沿[依赖计划](../../../script/tests/test_scene_dependency_render_plan.py)、[真实 Metal 执行](../../../script/tests/test_scene_resolved_material_graph_executor.py)、[提交生命周期](../../../script/tests/test_scene_resolved_material_runtime_bridge.py)和[签名 App 输入贡献](../../../script/tests/test_scene_mixed_provider_abi_integration.py)分别核对准备、供货、执行与像素。绑定或非黑不足以证明每个输入贡献；实际覆盖与未取得的资格归[运行证据](runtime-evidence-current.md#coverage)。

<a id="named-parent-base"></a>
### 普通父层的自身 named 输出

普通 image 的 primary named 输入表示该层自身的本地输出，transform 子层不自动成为它的纹理成员；父子变换边与 shader 读取边分别归属。原准备链已确定可独立读取的无效果 image base，不因持有子层而失去来源。可见 image 的实际 effect 输出也由原 graph 发布，不能退回原图；普通 image、Puppet、utility composition 和显式 subtree 各沿自己的实际 source 消费者。

冷准备在原 DependencyPlan 的来源谓词与 Binding 选择承接此区别。普通 base 及已有可消费 graph-final 的可见 image 不受 leaf-only 限制，generic 与 legacy 使用同一来源结论；其他来源只按自身实际消费者判定，不按父子数量建立许可，不新增来源类型、状态、renderer 或子树遍历。保真实 shader 自引用/依赖循环与 secondary、缺供货及不匹配资源边界。Runtime 复用同一 provider reservation、当帧 selected candidate、UV/sampling/颜色表示及原捕获/发布；只捕获父自身一次，父主合成及子层继续原作者次序，不重入读取父层的 child。视频由当前 candidate 内容代次供货，不额外复制视频池或重启播放。graph 来源使用原 required-provider 集合和 source route，raw 捕获入口不得代它供货；原 compositor 将同一 ledger 的最终输出发布到已预约 named target 后完成作者位主合成，不重复执行 graph，不从纹理别名推断无复制。首次范围为已可满足的可见来源；forward 可见期限、hidden graph、真实父图依赖及 utility/Puppet 域分别验证，不能因本条顺带改准入。

验收沿原依赖计划、真实 publication 与 App 门，覆盖含健康 child 的父层、child 与外部 reader、ID/资源/槽位改名、真实循环/缺源、原 leaf 邻例及健康后继；graph 使用非 identity 颜色变换及同来源双槽不同 UV，区分 raw 替身、子层混入和单槽偷代。核单次父 graph、作者位 main 及实际 publication→sampler；父 main 消费后工作 target 可合法复用，不以所有 target 必须不同作为权限。作者样本核实际纹理→sampler→main/GPU，动态视频另核当前帧更新。官方自有静态场景的无效果/颜色置换对照只授自身输出排除独立子层的范围，不授 alpha/tint、任意 graph-parent、utility subtree、视频时序或逐像素一致；实际结果由运行证据拥有。

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
