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
- uniform 派生只读常量由原 frontend/normalizer 沿[词法身份合同](#uniform-derived-global-scope)降低。实际资源、类型、反射及 ABI 仍在原入口验证，不能用 metadata 推出整段 shader 已可执行。

Generic 的固定一维 varying 数组沿真实双 stage 完整匹配和组件预算准备，不以float/向量元素类型或16/32项数量授播放许可；大于16项接口保原124分量预算，bounded 的类型、索引和展开限制独立。未支持的语法局部拒绝，不交另一个 backend 猜执行。

<a id="shader-value-numeric-arrays"></a>
### 数值数组的单次输入归一

目标是让同一作者数值以JSON数字数组或现有数字字符串表达时，模型材料及通用uniform收到等值分量。原SceneDocument与AssetCatalog两份值层投影由现Format的SceneDocument+ShaderValue承接一次；两caller保各自wrapper元数据及Timeline职责，Catalog不借此接入Timeline。Document原有nested scalar/string解包仍归原caller，Catalog不新增该形状，两者不接nested数组。两处重复数值/字符串投影退出，消费者不新增raw解码或数组分支，原完整scalar证明保留。

裸数组与wrapper.value数组只接真实有限数值元素，保完整顺序与项数；布尔、字符串、对象或null混入时整项无components，不compactMap拼出错值。单项归number、多项归vector，wrapper仍binding，不新增array valueKind；raw以数字token空格连接，单项保现scalar完整证明。空/错型及未知wrapper.value可保诊断文本但不得从字典调试描述抽数字。既有数字字符串语义、user:null、script/scriptproperties/bindingKeys和Document Timeline保留，不放宽动态资格或消费者形状合同。

只在原冷入口处理，无新owner/缓存/ABI/普通帧工作；原Format/Assets语义构建身份自然失效缓存，不加版本迁移或运行时清库。验收扩实际Document、Catalog及模型材料门，核裸/包装、1/3/5/16项完整分量及坏项的健康peer、元数据和相邻动态门；真实球资产固定相机/灯/几何仅color数组与等值字符串作旧新实际Metal/终端对照，独立作者保持。超过4项在入口完整保存，不借测试自行打包UBO授产品uniform供货；原消费者类型/维数合同保持，最小完成范围是两入口与实际模型颜色，不授一般uniform数组、新动态数组target、矩阵GPU、任意嵌套形状或官方像素。 两入口与真实模型颜色已闭合，当前资格见[模型运行证据](model-runtime-evidence.md#model-numeric-arrays)。

<a id="script-timeline-uniform"></a>
### Script 与 Timeline 的材质值通道

同一数值target上的Timeline是Script回调输入，也是Script本帧未产值时的合法来源；脚本被准入不等于每帧一定写值。原Template的`valueContributors`保留已声明且冷准备可供货的Timeline→SceneScript顺序，由原DynamicUniform给出单来源或该已证明组合的主身份；其他多来源/重复writer和未知Script附件仍沿原局部拒绝，不从源码中的回调名、数值相等或样本推断值角色。原producer catalog分别确认真实Timeline definition与Script target，不新增来源registry或值副本。

Program仍准备一个数值binding，主身份供原ABI/语义身份、直user投影和pass Script实例化；本帧值与来源由原DynamicSnapshot按现有优先级唯一决定。原uniform消费者接纳该声明内的实际Timeline或Script来源，保精确target、类型/有限值/Float编码、authored fallback、direct-user范围及资源/变体边界，不把未知来源通放。原DEBUG读口只报告已成功消费的实际来源。冷期退出sole-contributor假设和材质classifier的media回调源码特判；scalar Program尚有独立的旧控制识别消费者，本批不改其生命周期或发布角色。无新clock、owner、缓存、逐帧解析或一般多writer合并。

验收复用原TemplateCompiler/Classifier与prepared-query/Finalizer门，分别标明两fixture的handoff上限；核Timeline供值、Script真值、init后闲帧回Timeline、事件setter来源、变量/字段改名，保无Timeline却收到Timeline、未知附件、user冲突、错型/溢出/缺target和健康peer。真实QuickJS角色证据在输入源未变时复用；签名App以未改作者的同一成熟点击核实际uniform字节、material→main/seal/GPU及白块消除，再补独立真实交互。后续animationEvent供货与完整翻页各自验收，不借此授予。

<a id="sampler-presence-zero"></a>
### 未绑定纹理的显式零 combo

原 VariantResolver 分别持有作者宏定义与实际纹理 readiness。[官方 paint texture 合同](https://docs.wallpaperengine.io/en/scene/shader/variables.html#visible-texture-with-painting)允许未绑定时 combo 为0；显式整数0与真实 false 兼容，不因其宏定义不同于省略时的 undefined 而拒绝。只在原 readiness 比较处接纳这一情况，保 `.defined(0)`、explicit provenance 和原 validated slots；省略值仍沿原 undefined。退出“纹理 absent 必须连作者宏也未定义”的误拒，不新增资源、owner、解析或普通帧工作。

零值与未定义不合并：`#if COMBO` 关闭，而 `#if defined(COMBO)`/`#ifdef` 仍看到该定义，`#ifndef` 不成立。unknown readiness、共享槽冲突、true+0、false+1与其他不匹配显式值保原错误；实际活采样缺源仍由原 Program/TextureResolver 拒绝，不生成白纹理或假 ready。范围只授已知 false 的显式零，不改变 optional 资源的未来可达状态政策。

验收复用真实 Resolver→Preprocessor→Program/资源门，覆盖宏/资源改名、paint 与普通 sampler、definedness/provenance、上述冲突及活读缺源；同一冻结 App 输入核无纹理的数值分支和实际多 pass/终端像素，另跑独立真实作者邻例。原属性动画 scope 对照的载体失败单独保留，不能据此宣称 named lookup、wrapper 或作者翻页已恢复。

<a id="implicit-fragment-varying"></a>
### 省略片元声明的 stage 输入

目标是让作者片元函数实际读取顶点已声明并生产的 varying 时，省略重复声明不再使材质旁路。此处采用本项目明确的自有链接规则，不据单个变量名、资源路径或截图选算法。原 BackendCanonicalizer 在其它类型转换及 dead-varying 投影前，复用原 Syntax/GlobalReferenceAnalyzer 的一次双阶段声明、词法 binding 与 token 角色事实，补成双方共享的 compiler 输入；strict 与 bounded 后端继续检查真实类型、接口和 Metal 能力。

只补顶点唯一、完整的原生数值型 varying 声明，保原类型及固定数组长度；带未建模 qualifier 或不明确声明保原源码。片元候选必须没有同名顶层值、storage、函数或类型，其精确引用均为函数体内未被形参/局部/成员遮蔽的值使用；callee、函数签名、全局初始化及未知引用不猜作输入。显式声明和不一致接口不改，缺生产者不补零值，真实局部作用域同名允许与另一函数的自由引用共存。原作者源码、diagnostic 身份和准备缓存 owner 保持，不增 parser、Program 字段、资源/store、缓存或普通帧工作；失败仍只影响当前 shader/effect。

验收先用相同输入取得旧编译/执行失败，再核两后端实际 Metal 相位像素；覆盖完整变量/资源改名、等价表达式、helper/混合作用域及固定数组，相邻局部/形参/成员、内建 callee、同名 uniform/函数/类型、重复声明和缺生产者保各自原结果或实际编译失败。签名 App 须确认原424→420→237供货及模型可归因像素，独立真实样本保持；不以编译成功或夜光存在代替相位执行，不预设整体更亮，不授官方像素与性能。

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

<a id="uniform-derived-global-scope"></a>
### uniform派生全局值的词法身份

目标是让无关函数的形参、局部值或struct成员与全局uniform/只读派生值同名时，仍按实际绑定执行原常量降低。原GenericShaderRuntimeConstantNormalizer只移除已证明可在每次调用初始化的存储qualifier，保作者initializer及顺序；SourceNormalizer、glslang、SPIR-V/MSL、Program、uniform ABI与PSO继续各自原职责。准备失败只影响当前shader/effect，健康后继保持。

初始化及具体读写/调用点复用原Syntax/GlobalReferenceAnalyzer的一次词法声明和binding事实；prototype形参和局部影子不作全局重复声明，callee prototype仅在与唯一函数定义的返回类型、参数类型及方向一致时归同一声明，真实值影子、未决重载及out/inout消费保原限制。case-label等编译期表达式由mandatory编译器检查，Swift不另存资格状态或以整个函数含case否决。退出全文value-name许可、exact引用之后的同名token计数及无关作用域否决；沿原functionHeader和参数语义形成同次binding事实，不复制parser、声明表、内建名单、Program/cache或普通帧工作。

真实全局值/作者函数对内建的覆盖、未知绑定、数组及写入/成员写/递增、out/inout、采样/derivative/有副作用helper和compile-time消费者保原语言/纯度限制；证明不足保留原source交原编译器，不静默放行非法类型或猜默认。语言合法的局部影子按其自身作用域判断，不能因另一个作用域存在同名值而拒绝全局值的正常读取。

验收先在现源取得真实strict compiler失败，再由同输入的实际编译、反射/MSL及同一PSO的A/B/A数值与RGBA验证修复；覆盖uniform、派生值、内建/用户函数的同名形参/局部/成员、改名与等价括号，并保上述负例。签名App自有effect控制核真实Program→effect→终端、健康peer和局部失败，独立作者邻例保原结果；未找到作者命中时明确不授该作者恢复。完整backend语言能力、官方像素或性能不由本切片取得。

<a id="intrinsic-argument-conversion"></a>
### Intrinsic 参数转换

两 backend 共用原 `BuiltInVectorConversion` 的准备期转换：按语言 intrinsic 签名、词法 binding 和已声明类型形成显式参数转换，不按效果或表达式写法授权。浮点同形参数取非 scalar 向量的最小宽度，scalar 广播到该形状；`dot` 返回 scalar，逐分量 intrinsic 返回共同形状。构造器的固定结果类型及无歧义 helper 的声明返回类型可供外层消费，内部是否合法仍由真实编译器判断。用户同名 overload、value/member 影子及未知类型保留编译器所有权，不猜类型或删除调用。

窄化必须包住已完成的实参：`dot(normalize(vec4(...)), vec3(...))` 先完成四维 normalize，再取前三分量，不能把截断推进子调用。转换不重复求值，不改写 helper 的 out/inout 实参。typed 整数/布尔向量及矩阵不借本浮点规则强转；整数字面量需要浮点签名时显式构造，保留八进制等原值。原四次广播分析、简单 mix 端点和复合 mix 的分散职责由一次分析/转换计划取代；其他 owner 所需的表达式类型查询保留；raw frontend复用同一计划中可完整编码的窄化，保原直接编译能力，不重新lex或创建另一套规则。不增加完整编译器、运行状态或帧内工作。

方言依据为 [Wallpaper Engine 的 HLSL/GLSL 映射](https://docs.wallpaperengine.io/en/scene/shader/mobile.html)及 [Microsoft intrinsic 声明](https://github.com/microsoft/DirectXShaderCompiler/blob/ea3489109cc8a968b36e36ca20a698a68b516d32/utils/hct/gen_intrin_main.txt)；普通 arithmetic 的 [HLSL 转换规则](https://microsoft.github.io/hlsl-specs/specs/5-Expr.html)不能单独代替 intrinsic 资格。验收覆盖不同宽度、scalar、嵌套构造、完整复合求值、改名/alias/helper、用户 overload 和局部失败，经真实双 backend Metal 数值、作者内容与独立邻例验证。官方固定客户端的最终像素一致性另需对照，编译资格不作 parity 声明。 行为门见[双backend数值](../../../script/tests/scene/test_scene_shader_scalar_vector_builtin_canonicalization.py)、[作用域与复合参数](../../../script/tests/scene/test_scene_smoothstep_vector_broadcast.py)和[uniform逐draw更新](../../../script/tests/scene/test_scene_uniform_invariant_shader_constants.py)。

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

<a id="small-atlas-frame-uv"></a>
### 图集小帧的非退化UV

typed slot的UV有效性按实际映射判断：现SlotBinding保有限origin/两轴与有限非零行列式，不用归一化面积的任意下限决定播放。4096² atlas中的1² frame两轴为1/4096、面积约5.96e−8，仍是完整一个源像素；阈值1e−7会在共享binding入口因图集分辨率误拒，实际依赖该binding的发布与绘制随之局部失去纹理。同一阈值也在StaticModel颜色/阴影的raw textureFrame入口拒绝整次draw。本批一并退这两条同源面积许可，保原尺寸/用途/纹理兼容及真实零面积/非有限值的拒绝，不改抽样、geometry或物理资源额度。原模型Frame在真正坏raw frame使drawShadow拒绝时撤整map，现失败范围另列队，不借本批宣单caster局部隔离。

原UV数据继续由Loader/同candidate/frame provider传播，现纯数据SceneTextureUVTransform拥有一份有限/非退化谓词，原SlotBinding与模型颜色/阴影入口共用；SlotBinding的private UV/area helpers与模型private isValid同批退出。两入口各自仍可收到raw frame，保各自原检查次数，不新增owner、字段、cache、wrapper或帧内额外运算。本小帧验收当时未包含仿射；当前几何与消费者边界由[完整源帧合同](#material-affine-frames)定义，不能由本节的面积修复单独推导所有输入已获资格。Textures已属原构建语义身份，不新建缓存版本或播放清库。

验收在最近候选/材质门用真实4096² TEX与1² frame经过Loader→frame provider/publication→binding→实际Metal，和独立小图逐像素等值；保相邻正常frame、资源改名、零面积/非有限和健康peer。原模型Frame/Metal门另核相同tiny UV的颜色与三灯shadow、身份frame等值及真实退化拒绝，不能以image通过代替模型。App沿同自有输入做旧新贡献控制并复用有效同身份控制，独立作者保原播放；不以metadata ready代替实际采样，也不授活动作者命中、更多UV形状或性能。 共享小帧与模型颜色/投影已按此闭合，范围见[模型运行证据](model-runtime-evidence.md#small-atlas-frame-uv)。

<a id="material-atlas-source-frames"></a>
### 材质图集的源帧准备

静态单帧与Catalog动画资产共用原Loader的preparedMaterialFrames源事实：原Admission三态在本文件内携valid([SpriteFrame])/metadataInvalid/unsupported，不新增owner/cache/clock/持久字段。Format container.spriteFrames保持按首mip表归一的原解析事实；Loader一次取首mip与已有embedded尺寸，同域直接复用原frame数组，异域一次比例、逐帧冷投影到实际decoded源并核实际范围。static只接恰一frame，animated接原N frames；makeCandidate退出单帧专属坐标计算，仅构造相同来源/geometry/用途/采样的候选。prepared animated frames由原Definition保存，Provider沿原time/commit-discard只选/搬值，不叠base padding UV，不逐帧解析/投影或以最终缩小后的GPU尺寸作分母。

Reader已在真实字节入口保证imageIndex有效、duration有限非负及六坐标有限；原单image结构令index唯一，Loader不再重复这些检查。原Loader用Float累计duration并据溢出拒绝无实际消费者：原Catalog以Double生成同一durations/total，Reader最多65536帧且各duration为有限Float，正总时长在Double表示域内；0仍由原provider准备按1/60替代。不增新校验/长duration状态或时钟，退该虚假溢出门，以真实长duration两帧的选中/wrap验收；非法非有限/负duration仍由Reader拒。原image/animated/nonvolume/正尺寸仍是Loader结构边界；frame几何见下节四角与非退化合同，跨image不扩大。

Catalog退出先materialAtlasAdmission、再loadAnimated重复整帧扫描；原AnimatedLoadOutcome仅新增typed metadata失败分支，Catalog直接保原effectLocalUnavailable分类。结构不支持仍原unavailable；读取revision/取消/资源I/O失败沿原throw或failed传播，不过滤单个坏frame、吞实际读取失败或偷取frame0。实际源中不存在的frame按同一metadata失败局部拒整个asset，保持原时长/索引/健康peer。

验收复用模型静态单帧的原输入/原输出；最近候选源shader门补真正Catalog两frame、mip8×4/decoded4²的straight/PMA与独立crop逐像素、资源改名、duration0/长duration、同域raw/压缩及实际源越界/坏frame/健康peer；原事务/修订门按影响补测。完整App沿已有companion-frame Generic owner显式消费Rotation/Translation，固定两sceneTime，各自产生非恒颜色/alpha图，与同过滤的独立crop严格等值并到同main/seal/GPU；不是metadata ready替代采样。另保独立原作者。模型slot0当前沿[统一资产链](advanced-object-coverage.md#model-albedo-frames)，不新建动画owner；其余消费者资格仍逐域保留。

<a id="material-affine-frames"></a>
### 完整仿射源帧与真实消费者

目标是让合法旋转、镜像和skew frame沿原Loader/Catalog供给世界模型及固定Lit shader，颜色、alpha孔与阴影共享原双轴；同时允许作者Generic shader表达完整矩阵采样。原Loader用正轴许可误拒资源，原LitInput重复限制六坐标；原Generic Derivation也把正轴当assembly许可而无后续数学依赖，若只放宽Loader将把合法ready资源变成invariant整Frame drop，不能留下这个退出半径。

原preparedMaterialFrames保持image/animated/nonvolume结构与embedded源投影，在投影后的实际source域以既有SceneTextureUVTransform有限/非零det谓词及完整四角bounds代替正轴/双端点检查；四角用origin+每轴分量min/max计算，不分配临时数组，保原1e-6边界容差，不clamp坐标。Reader只在字节入口校验raw index/duration/六坐标finite；消费处核投影后的几何，不再重解原字段。不引面积阈值、purpose/path许可、源纹理副本或新帧状态。

Lit TextureInput在原SlotBinding已准备完整双轴后仅保原sampler/format边界，退错位正轴门。Generic两backend按作者raw UV sample，宿主不偷偷应用frame；原UniformEncoder已给sprite完整Rotation4/Translation2以及原physical/mapped Resolution，exact identity也携六坐标。Derivation的正轴检查仅当布尔许可使用，直接退役，不搬到Resolver或新增fallback分类；同guard中publication.isComplete已验证同candidate，activeSlots已证0…7，因此重复SlotBinding重验也退出。身份、用途、发布完整性、sampler、graphInput及其它真实assembly invariant继续各自原合同，不普遍软化invariant。

剩余SourceMaterial/DependencyGeometry实际有矩形或exactscale消费者，原axis限制继续在其消费处；BaseImage sprite走独立specialized loader，不把其健康当本共享链证明，refraction/背景原精确mapping也不放宽。原materialProgramUVTransform改名axisAlignedSourceUVTransform并换两处来源调用，不留兼容alias，避免把局部来源域重新当Generic许可；这三处是职责更名，几何行为不变。无新shader、ABI、PSO、clock、cache或owner。

验收沿原Candidate/Catalog真实TEX单/多帧：90°、mirror、skew、改名及legacy实际源投影，对零det/NaN/第四角越界局部拒绝和健康peer。原PBR固定Lit门核多色MR/A或normal实际采样；真实model对独立像素排列的颜色/孔/投影结果，不以ready/profile代画面。Generic同时验显式companion矩阵采样与故意raw UV的完整atlas控制，证明未自动改坐标、未整Frame drop；原wrong publication/purpose/identity等invariant仍硬失败。另保真实作者回归。无活动作者affine命中，不授所有作者shader自动映射、任意fractional线性footprint隔离或padding等价；达到上述输入/消费者实际像素合同即退出该队列。

<a id="material-atlas-source-frame-evidence"></a>
当前核对（2026-11-15）：两产品净减16行，Format/Provider/Metal/ABI/clock/cache均未改。真实Catalog源shader门38合同与30采样全过：legacy TEXB0002的mip8×4/PNG4²、实际改名及PNG5×3非二倍比例，straight/PMA各三相位逐像素等独立crop；同域四用途12行保持，真实源越界保整个asset的metadata局部失败，坏duration仍Reader拒。0/1.5Float.max/2Float.max实际像素依次[32,64,128,255]、[255,0,0,255]、首图，generation1/2/3；旧22合同红，完整原生三十行与失效范围单列观察/推断，不把旧bad-source像素未知写成已读。前批模型单帧11份TEX字节/123原payload/23合同和本批old/new均逐值同；原Catalog生命周期门保留22项原行为，退1人工volume私有API断言，新增2合法长周期项后24项通过。首次载体空白语法失败零GPU，以及首次新版旧文案镜像误报均留原报告；文案helper改测实际decodeFailed，不改输入、产品或像素容差。

普通Debug29.907s、两产品/project/锁文件前后一致，strict deep与原helpers通过；exed2ae6db3…920fb、dylib2a5ff8d9…ceefb、metallib仍4957688f…83bf1。既有Generic companion门的两个固定sceneTime .25/2.25，slot1 atlas显式消费Rotation/Translation，独立crop直UV，straight/PMA均由原输出transfer只归一一次；原22case输入/协议逐字保持。旧两scene的crop/peer literal均合格而atlas重复列/选错区域；新两scene每个atlas的完整面板RGBA（1,143,072B）等独立crop，old/new crop严格相同，8项比较全过。全3024×1964 PNG的RGB变化各288036/571536像素，仅在两atlas面板，外部/crop/peer保持；每新scene ready/after PNG相同。after request2/F94的CB523008492416与535222731648中61实际UV为[0,0,.5,0,0,.5]与[.5,0,.5,0,0,.5]，实际source绑定→Program/tail/ordinary→main/seal/GPU、零截断及排空闭合；不把typed UV当GPU uniform反读。旧App由同身份签名clone保留，并非拿新构建冒作基线。

原3437487219自然5s、project/pkg摘要同矩阵，F142/request1/CB503145154304的112/114及135到main503154793344/seal/GPU并排空，完整地表/云/大气/时钟已看。没有活动作者embedded atlas命中、模型多帧、官方像素/性能或线性frame边缘等价资格。自有红绿/输入/源码/失败/整图/独审归`.artifacts/scene-material-atlas-source-frames-20261115`，原作者报告归`.artifacts/scene-evidence/runs/scene-material-atlas-source-frames-20261115`。最初非标准effect文件名未进入Program的独立角色断点，以及随后crop误用零sprite companion/重复PMA的载体失败均保留，不充作本坐标红例；前者另保最小未决包并列[队列](../roadmap/scene-open-breakpoint-queue.md)，本批合格App使用标准effect布局。

<a id="graph-canvas-sampling"></a>
### 材质画布采样

已发布的单 mip Graph 画布以线性等向性取样，沿现有 clamp 或 repeat 寻址。材质 PassEncoder 在准备绑定时使用实际候选的 `.provider(.graph)` 身份，原发布入口已证明画布格式、单 mip 与采样合同。资源身份比逻辑槽号、引用名或 mip 数量更准确。每个 PassEncoder 复用两种寻址状态，沿原 sampler 描述器构造；资产、独立 named 发布及其他来源沿原状态集保留 nearest 或线性各向异性。

退出共享 16× 对真实 Graph 画布的绑定，保作者坐标、显式 LOD、地址模式、纹理与 shader ABI。带 `fract` 的有效材质在边界可把隐式 footprint 扩展到相邻行；修改作者导数或全局降低各向异性会扩大语义和影响面。普通绘制与 terminal replay 共用同一绑定决定，附件读取转换及精确快照继续保已选 sampler。初始化失败沿原 PassEncoder 准备失败处理，无帧内创建、重试或发布改动。

验收用同输入的原文字环核圈外放射线与内环，实际 Graph 的 clamp/repeat 与非画布线性/nearest/mip 作为相邻输入和反例，再验独立作者画布与已验证的斜视多 mip 模型。具体画面和证据边界归[运行证据](runtime-evidence-current.md#circular-text-edges)。

<a id="source-channel-layout"></a>
### 数据图片的源通道布局

数据用途由实际 sampler 决定，图片布局由解码结果决定；不能要求 mask、normal、noise 等输入先具有颜色图片的 RGB/四通道形状。原 `SceneImageTextureUploader.sourceRGBA` 在资源准备入口消费实际 packed 8-bit RGB/RGBA、灰度/灰度加 alpha 及既有 padding/字节序，直接写入原 RGBA8 上传数据：灰度复制到 RGB，无 alpha 补 255，实际 alpha 与透明 RGB 保留。此转换不经 ICC、颜色 raster、反关联或重新解码，不为效果名、文件名或作者样本选路；复用原 mip uploader、Candidate、Catalog 和 sampler，无新增 owner、纹理副本或普通帧工作。

只替换原固定通道数量及灰度颜色用途限制；保持实际格式、stride/载荷边界、decode table、premultiplied、float、数据 resize 与未实现精度的消费边界。一个 authored mip 无法消费时仍不发布部分纹理，健康其他资源和后继保原局部失败。16-bit straight-albedo 的已有转换不扩大为数据精度资格。

验收使用原 loader 的混合灰度 JPEG/RGB mip 链、每级实际 GPU 读回、资源改名、透明 GA/RGBA 与 RGB/灰度及坏后续 mip；随后核原作者失败槽恢复真实材质、publication、下游采样和 terminal，另用受控 mask 值及独立作者邻例验证可见输出。输入布局转换成功不授全部颜色格式、任意特效或逐资产最终贡献。

<a id="tex-alpha-channel-priority"></a>
TEX bit19 是 `alphachannelpriority` 的打包元数据。现有 `SceneTextureSampling` 保留原始位，将 bit19 与已知通道元数据一起准入。实际像素格式继续归原解码，过滤与寻址继续由实际采样位决定。未知位和未支持的边界寻址保原失败范围。用同一 RG88 纹理的单 bit 正反例、改名引用、真实 Light Shafts 两个消费者的首帧与终端验证，另验相邻健康作者。

<a id="framebuffer-source-declarations"></a>
### Framebuffer 来源与声明依赖

RenderDescriptor 提名声明 passthrough、单一 source pass 和 typed framebuffer 输入的模型；RuntimeCatalog 将 source Program 的候选限定为本层 slot0 `sceneBackground`。主画布的 PMA 传输与着色器的直色读取独立。已准入的独立 source 在冷变体保留候选的 PMA 用途，颜色边界按实际 publication 适配，准备直接消费该变体结果。效果背景、数据、普通资产、命名层与其他来源各保原役；同层、帧和纹理身份在借用处核。原几何、render state、子层及透视范围保持。

图层的 `dependencyLayerIDs` / `authoredDependencies` 不替换 source material 的输入，非空声明不能独立取消合法 source。effect 真正采样的 named 输入继续由已选 Program/DependencyPlan、当帧预约、供货及局部失败承接；不把当前 main prefix 冒充某个命名层的最终输出。声明指向较晚层也不移动本层 source 的作者捕获点。Descriptor 与 Catalog 的两处空依赖许可退出，其余准备、资源与实际读取仍归原 owner，不新建状态或普通帧校验。

验证沿原角色解析门和 native-world App：无依赖、只声明早层、只声明晚层及资源改名保持 source/effect/父变换/深度像素和健康 peer；错用 named 资源保自身输入语义。独立 Metal 门向真实主纹理写非满 alpha 的 PMA，核 source 输出、effect 及错帧/错消费者/错纹理；保数据反例和独立真实作者。热显隐沿各自现役入口。

<a id="shared-source-image-scroll"></a>
### 共享图片源材质的滚动与作者值

经现有接口证明的单纹理调色材质，有限的静态 UV 滚动值交给完整 source Program，以原时钟、采样和颜色参数生成共享来源。只有零滚动且其他参数中性时才可降为直接合成。完整 Program 中，解析后的属性目录未定义直接属性时使用已验证的作者值，颜色脚本仍以该值为输入。已声明的属性沿现 typed writer，错型、冲突、缺作者值和不支持的动态滚动保局部拒绝。

先由原材质与属性准备确定 writer，再由原 Program 与资源模板把同一来源交给静态层和动态实例。撤掉完整 Program 的零滚动门，保留直接合成的限制。不以已载入的纹理代替材质，不新增运行期资源或缓存。验收核非零滚动与重命名、合法 live writer、缺定义 fallback、坏声明、零滚动邻例及同素材独立作者；官版原包 16:9 预览用于确认内圈位置和可见性，逐像素与滚动相位另需匹配输入。

已有 SceneScript 创建需求的完整源材质，允许用初始隐藏的合法作者层作为共享材质原型。原型的可见性不决定资源是否可准备。按同一 scoped 模型、首个作者层和现有材质形状完成编译与模板发布，供原 init 构造独立层；作者层显隐和各实例自身显隐分别沿原 typed 值消费。直接合成及无创建需求的隐藏来源保原边界，不重试 init、增加热编译或把创建者的显隐附加给独立实例。验收对照有音频的官版默认及两次热更、真实本机创建与同 Surface 更新、改名和无需求反例，并保原已显示的共享材质。

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

回归沿[依赖计划](../../../script/tests/scene/test_scene_dependency_render_plan.py)、[真实 Metal 执行](../../../script/tests/scene/test_scene_resolved_material_graph_executor.py)、[提交生命周期](../../../script/tests/scene/test_scene_resolved_material_runtime_bridge.py)和[签名 App 输入贡献](../../../script/tests/scene/test_scene_mixed_provider_abi_integration.py)分别核对准备、供货、执行与像素。绑定或非黑不足以证明每个输入贡献；实际覆盖与未取得的资格归[运行证据](runtime-evidence-current.md#coverage)。

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

<a id="named-geometry-local-raster"></a>
### Named 来源的局部色图

Geometry 的 primary named 输入表示 provider 自身的 authored-local 色图：当前 pose/mesh 采原 graph-final 色源，在 `authoredSize` 居中的矩形内沿原 Y 方向和覆盖规则绘制，透明区保留。world、camera、parallax 与 consumer placement 不进入这张共享图；provider 与 consumer 的作者位主合成仍各自消费原变换。作者 Program 用自身 UV、纹理 Resolution 及作者 offset/scale 等参数采样，不隐式要求两层世界矩阵相等，也不自动做世界重投影。

普通非solid图层的 graph-final named 来源同样按已解析的 layer-local source extent 准备效果目标。原 FramePreflight 用已有 requiresGraphOutputCapture 事实区分共享供货与普通显示：前者不把 world 矩阵列长、camera 或 parent 缩放混入纹理长宽；后者保原量化向上取整的显示密度，避免已有可见字符放大后模糊。保原 source extent/Resolution、captured matrix、Program、唯一 graph/named 发布与最终 compositor placement，2048等比限额不变。不新增每消费者纹理或缓存；退出命名图像先按世界尺寸拉宽再等比压成薄条的旧目标选择。真实分配失败仍走原局部失败，坏epoch/来源不放行。

预约与实际 publication 复用原 provider/epoch 唯一 target。沿既有 named 资源约定，physical 与 mapped 均为实际 raster 像素尺寸，UV 为 identity；超过 pool 的2048边长时等比缩小 target，投影仍用 authoredSize，不能用 target 像素重新缩放 mesh。所选 candidate 在预约和发布时提供相同 metadata；本条不改变全局 Resolution、reduction 或作者参数单位，也不把 raw atlas 冒充已执行 geometry/FX 的色图。

原 GeometryProduct、FrameRuntime、Program 与唯一 compositor 分别承接 source/pose、预约发布、取样和作者位输出，不新增坐标 owner、consumer 专属 target 或缓存。退役仅供旧 exact-placement 准入使用的两套世界 MVP 比较及传递/计算；owner、安装 generation/atlas、有效 authored extent、当前 pose、frame epoch、graph 色源尺寸与真实 encode/资源寿命边界保留。缺源或普通视觉失败沿原局部降级；错误身份不能借此通放。

普通graph供货另用真实隐藏provider→effect→named→模型的非恒条带，核直接缩放与等价父层缩放/ID/资源/变量改名后，纹理extent及模型像素保持；健康后缀/阴影和raw无效果供货不变，非named普通图层仍保原显示密度。实际水滴93必须由3840×1920源得到2048×1024 graph/named并供115恢复细线；不改作者scale、素材、调色或算法参数。独立作者另核主合成与GPU，不由尺寸恢复自动授官方RGB一致或尖端发光已修。

验收复用原 native/Metal 门，核局部 raster 的 within/over-cap 尺寸、共享 target、可区分 graph 与 atlas 的像素及不同 consumer placement，保坏 owner/source/generation/extent、过期帧与 pose/encode 失败反例。签名 App 必须看到真实 provider publication→所选 Program sampler→主合成/GPU/PNG/排空，另核资源/变量改名与独立作者；Ready 或退掉消费层不算该链恢复。任意世界重投影、局部范围外几何及官方逐像素一致不由本条授予。

<a id="childless-composition-local-effect-raster"></a>
### 无子 Composition 的局部效果栅格

带局部尺寸的无子 Composition 读取作者位当时的主画布。读取位置由原捕获 UV 和投影决定，效果工作纹理由作者局部尺寸决定。世界旋转、非等比缩放和窗口尺寸只用于取源或放置，退出按投影轴像素数决定这一离屏图的长宽。实际 Metal 纹理和 `g_TextureNResolution` 的物理/映射尺寸继续一致。

原 FramePreflight 只为已准备、正交、无成员、读取主画布的普通 Composition 选择原 `SceneLayerEffectSourceExtent`。确实走离屏的 graph pair 与首来源用同一个尺寸和原目标限额，仍按原 UV 采一次背景、在原截点执行 Program，并由唯一 compositor 沿原 quad 回绘。缺合格作者尺寸仍沿现有投影尺寸。保留显式 framebuffer source、组/子树、具名供货、透视和已获资格的 attachment-read replay。复用原分配和发布，不引入副本、缓存、宽高比特例或改变纹理尺寸 ABI。

先以官版方形与同角点的非方形输入核工作尺寸。近门用非等比放置、背景读前后次序、原名/改名及透明邻例验证同帧实际槽和像素，再沿原包 314 的两道弧、平移对照、保持开启的 Spin 与独立已有真实场景核画面。同一采样域只随作者尺寸改变，不由无声/裁屏冒充效果恢复。绝对帧率与其他来源尺寸另有各自证据。

<a id="solid-background-local-effect-raster"></a>
### 读取当前主画布的固体局部效果链

顶层正交、普通混合固体的连续颜色链以作者显式局部尺寸分配工作纹理。纯色底的单像素供货只提供颜色。效果从 `SceneLayerEffectSourceExtent` 得到真实捕获和 graph pair 尺寸，纹理 Resolution 沿原选中资源填写。摄像机、缩放和最终合成四角仍由原放置链提供。已准备的只读主画布 companion 在作者截点绑定原附件。

冷准备复用普通颜色链的单段材质、无历史目标、无清除与合成节点等事实，含已经确认只复制当前内容的关闭阶段。具有此背景输入的独立固体采用作者工作尺寸，经原离屏 graph 和唯一 compositor 输出，末材另按[放置空间同像素合同](#solid-background-same-pixel-tail)判定。原分配、颜色表示、失败和资源归还职责保持原 owner。具名、显式 FBO、已有基础材质供货、非纯色、组成员、透视及异常尺寸沿原路径。

验收以同覆盖四角的256²/384×192、固定圆线、真实 PCM 与当前主画布输入实测。核实际源/工作纹理、两个输入同帧供货及完整画面，另查带尾部关闭阶段的独立作者和读背景的普通图片反例。32档供值归[共享音频设计](../../architecture/system-audio-spectrum-design.md)。

<a id="solid-background-same-pixel-tail"></a>
### 固体末材读取主画布的同像素前缀

普通正交固体继续在作者尺寸执行前段。最后一个实际颜色材质若只在当前输出像素读取主图前缀，可复用原 `placementTail` 直接合成。冷准备从唯一已解析的背景槽取得输入，要求所有该槽采样都是同一无偏移投影式。顶点供给同一位置的齐次裁剪坐标，片元透视除法、Y 方向和到0…1的映射与主附件 viewport 一致。该证明独立于材质、资源路径、变量名及槽号。正常选中版本用原通用 Program，已证版本派生原附件读取入口。已有普通编译缓存可用，只在需要判断的背景输入上准备派生。

实际目标为同一帧 MainPass，顶点放置矩阵和背景投影矩阵须相同。源身份保留给逻辑 Resolution 与提交检查，物理读通过已有 Metal `color(0)` 输入，只替换该槽的已证采样。其它槽仍按原绑定与别名规则校验，前级输入继续读上一阶段的局部纹理。原 Graph 及一次性票交由唯一 compositor 消费，退出末材离屏写和普通回绘。该路径复用现有的前缀和附件。非同像素、早段读背景、多个背景来源、后继依赖、具名、组、透视、关闭末材或准备失败均使用现有局部输出。

验收以同物理画幅的官方及本机原帧，核不同局部尺寸的导数、真实槽、主色前绘和独立后绘、一次终端写及 GPU 完成。改名、投影等价表达式、位移或过滤反例及独立作者沿实际路径验证。取样替代只在支持现有 attachment ABI 的 GPU 生效。比较原 GPU 阶段及主目标成本，分开截图与性能计时。整张主图复制可作为对照，采用前须证明可见收益与成本。

<a id="isolated-image-source-density"></a>
### 独立图像末材的来源密度

普通根图像的单段颜色 Program 若已能在放置空间重放，从真实图像捕获的工作纹理可优先保留来源的映射采样网格。这个网格给单级捕获保存原有局部覆盖。原画布四角、材质参数、颜色表示和 UV 仍由现有消费者解释。标准链会缩小含 mip 的来源，且映射网格不超过标准档平方像素数时，SDR 可提出这一尺寸。几何图集、具名供货、背景输入、前后材质、历史、独立下游及后续生成的 base material 来源沿原分配。

FramePreflight 在当帧材质启用后从作者顺序选一个可共享的优选工作尺寸。真实图像仍通过原 sourceCapture、配对纹理、Program 和唯一 compositor 消费。已有池负责完整准入，一帧只使用成功的计划和配对纹理。优选档不合格或遇到容量压力时使用原标准档，保完整图与健康相邻消费者。未获选的工作尺寸、HDR、多阶段、关效果、组和模型图集沿原政策。尺寸由已准备的真实来源决定，复用池的目标和回收语义。

验收同时检查单段 Waterwaves 正常及零位移时的丝线对比、宽度和位置。关材质和关图层各有独立对照。改名、实际属性热切、另一作者的可见输出，以及标准档在紧预算下仍能保健康后继，都沿实际图和 GPU 收据验证。同步记录两档在原包的实呈与工作目标驻留。

<a id="root-quad-current-color-blend"></a>
### 普通四边形的主色混合

普通高级混合的末端原本以片元位置整数坐标读取冻结的同像素主色。根主画布上的标准四边形，若放置为恒定正齐次 W、来源与主附件存储分离，且颜色附件为现有支持的单采样格式，可在原作者截点由可选 PSO 直接读取 `color(0)`。两片共享一条光栅边，每一层最多覆盖一个片元。无子项的局部 Composition 工作输出与普通图片使用同一终端资格。

原主画布 owner 完成前序 encoder 后，主终端以原 clear/load 生命周期读取当前附件。两种背景入口共用混合、颜色表示、雾、覆盖和背景 alpha 的原片元计算，源纹理继续经 slot0；实际写入只有一次。直接路径退出当前 `background-copy` 和对应物理背景绑定，原图层 source capture、具名/历史纹理、组、网格、折射及未取得可选 PSO 的路径各保原来源和冻结快照。复用设备资格、原 PSO 仓库和主合成入口。

验收先比普通及 HDR 的整图 RGB/alpha，并覆盖相邻有重叠的不同四边形、边界像素、清屏、透明输入和非合格网格。真实作者同截点核作者历史、前后绘和终端主图，并独立测复制计数、GPU 时间、实际呈现与目标分配。附件读遵循 [Metal 隐式 imageblock](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf)。

<a id="placement-only-composition-tail"></a>
### 透明 Composition 的末材放置栅格

顶层正交、无成员且关闭背景复制的透明 Composition，原作者尺寸继续供应 source、前段和各自的 FBO。最后一个实际作者阶段若只有一段能在放置空间绘制的普通颜色 Program，且没有命名发布者或同附件采样，冷准备标记其输出职责为直接合成。正常与 Additive 沿原终点的颜色表示/混合状态，当前透明底、纹理 Resolution、作者参数和放置四角沿原消费者。一般主画布来源仍区分真正同附件输入和透明局部来源；来源路由名不决定末端采样类型。

编译与 Graph 各承担一次阶段选择。只准备标记的末材，输出输入是前一阶段真实 pair 与其他已准备资源，目标为当前 MainPass。末材经原一次性 ticket 写入 compositor 后才完成。启用时退出末材离屏写和相应的普通颜色回绘，不引入中间复制、第二次执行、目标池或缓存。前段已有目标、资源 pin 和历史提交保持原 owner。直接输出没有可供其它层读取的末段色纹理，依赖目录和运行诊断按实际输出建模。真正使用记录纹理的图继续发布原产物。

失去资格、作者热关、缺资源或末材不支持时沿原局部链执行，前段结果保留。保原透明和深度邻例及捕获截点；渲染开始后失败服从当前主图提交边界。验收同一固定输入下用实际 Resolution、UV导数和同坐标LOD核独立的工作与放置尺寸。实测带前置半尺寸 FBO 的末段正常滚动，末材只编码一次；同时验证关末段、改名、真实独立 Composition、普通透明叠加以及当前画布/具名/历史的真实输入反例。

<a id="background-capture-addressing"></a>
### 画布捕获的边缘寻址

按现有 UV 从实际当前附件复制局部背景时，附件自身的有限范围使用 clamp-to-edge。离屏 quad 的坐标保持，越界区域延伸该次捕获的边缘。作者图层与 Program 保留声明的过滤、重复和效果局部坐标，Scroll 继续按自身周期取样。原 FramePreflight 在固定 source capture 绑定时选择边缘寻址，显式 framebuffer material 的采样继续由其 Program 处理。复用同一源、目标和提交，退出把普通图层 repeat 沿用于附件复制的旧边界。

用两侧不同的主画布核越界采样经作者 Program 又回到可见区，保改名、过滤、常规来源、组和透视邻例。原包以同 zoom、固定 Scroll 和 off 的实际末端区分左缘回卷、右缘延伸及完整作者画布预测。

<a id="named-source-execution-cuts"></a>
### Named 来源的执行截点设计

来源的资源预约与内容就绪是两件事。读取 enclosing attachment 的 raw 来源只能在原作者捕获位置取得 prefix；独立图像、solid 和透明来源可以提前准备。目标是让 `O → U(prefix) → C → P(hidden)` 在 U 捕获后、C 编码前执行 P，而 `C → U → P → D` 中早 C 局部缺 P，晚 D 仍取得 P 的正确结果。不能为了早 C 提前执行并发布降级 P，污染后面的合法消费者。

冷准备的前向独立性按完整 primary 输入集合判定，不按上游数量授许可。较早 C 读取普通 hidden image graph P，P 的每条已选 reference 仍须属于实际 effect/pass/slot、指向原 active dependency 集合中的 primary provider，所有来源由原完整 ownership 闭包接纳。多边拓扑、来源最早位置和同截点排序复用原 Plan，缺一来源仍沿原局部 previous-current 处理；真实 self/cycle、未知 provider、secondary及可见 graph 作者位期限保持。

潜在 Binding 只表达现有来源可准备，不能把 material default 与 instance override 的候选并集当作实际背景读取。原冷候选入口只保已有来源种类、primary结构和前向期限；已支持的可见 graph 不因有活动效果而失去 carrier，退出把可见性作为前向整项禁令的旧关卡。最终 ProgramFirstStagesBackground 消费原 Loader/Finalizer 选中的 launch-active slot/candidate，决定 graph provider 是否真读背景；原完整依赖闭包、来源独立性及实际截点继续约束main/prefix时序，保secondary、自引用及cycle的拒绝。被更高优先实例资产替换的 `_rt_FullFrameBuffer` 不产生实际顺序依赖；真正选中它的 graph provider 继续局部拒绝。原 raw aggregate仍在相同结构 Binding 之后核完整 authored-order 独立性，legacy/staticModel、raw renderOrder、utility和background graph执行范围保持。不加阶段开关、第二套候选选择、持久状态或普通帧计算；原 activeTexturePaths并集及其重复准入退出。

验收沿原 Plan、真实 Loader/Finalizer、Metal 与签名 App：两源各自清零和交换、三项 primary 闭包、ID/资源/变量/槽位改名与上游顺序互换，核 A/B→P→C 单次执行及可区分像素。死 lower background另核显式albedo实例资产胜出与等价改名；真正选中背景、缺源、循环、跨层secondary及raw aggregate反例保持。健康suffix/peer与独立真实样本保回归，只得到potential/ready不算恢复。未找到精确作者命中时，仅授自有作者图实际合成，不宣称作者缺图恢复、官方像素或性能。

原 DependencyPlan 与 FrameRuntime 缓存当前根可达的 prepared DAG，使用 utility 展开后的实际顺序、已选 Binding、当前可见 graph 和 model 需求；候选来源准备顺序不是提交或编码顺序。来源准备阶段一次取得原 source、尺寸、MVP/cursor 与 FrameInputs，沿原路径预约 group source 容量，但不创建 graph ledger、bundle 或命令；所有 activation 依原 policy 使用这个实际逐层 pointer 输入求值一次。原 StageCapability 的 prepared passthrough 事实与精确 slot 投影决定本帧不读取的依赖，不能把任意 false 或全局 pointer inside 当作局部取源证明。同一份 Decision 交 Executor 消费，不重新求值。取 ready publication 时也只消费同一份已准备的 binding/slot 选择；同 provider 的其他活跃槽已供货，不得使已停用槽重新进入向量。实际 epoch、纹理、内容或绑定漂移仍在原消费者拒绝，不以放宽一致性比较掩盖选择漏接。原 Coordinator 从唯一 prepared ledger 临时投影 slot 集合，经现有 Bridge/compositor facade 交普通 image、hidden graph provider 与 utility 的同一个 ready resolver；替换只表示全有/全无的 bypass getter。空集合表示当前可消费 ledger 没有预约外部输入，nil 表示没有当前可消费 ledger；不另存状态、不重求 activation，也不将 effect slot 投影应用于无该slot语义的 model albedo路径。实际截点计划同时给出 graph request/ledger 顺序、原预处理供货及每个作者位置前的供货列表，替代互相重叠的 preparation/global-forward 排序。普通 layer loop 只取本位置的列表，不做依赖遍历、source 分析或重复准备，不增加 phase registry、等待状态、第二份 graph 输出或历史分支。

计划只移除该消费者 Binding 的所有 referenceSlots 本帧均不被读取的边；同来源还有一个活跃槽就保留依赖。DAG 准备事实保持，实际截点 memo 比较这个小投影。计划先沿本帧无环绑定确定真实来源最早可用位置，再从消费者向上游传播可满足的请求。raw prefix 位置在 U 原捕获之后；没有合成顺序依赖的来源可用于预处理。可见 graph 自己的作者主位是执行期限，不能为等待更晚输入而推迟或丢弃其主输出；尚未可用的输入保持该消费者原局部失败语义。hidden graph 不为一个过早请求生成临时降级输出，保留给后续可满足的请求。model 的提前需求不能越过真实来源位置；独立 albedo 仍保原提前准备。

完成来源和 activation 准备后，才对实际选中的请求确定 shared/owned、预约外部输入并构建资源 bundle；未选中的候选不创建 ledger/命令。尺寸复用原 extent resolver 与 target policy，不以 desired size 冒充已接受 extent，不重复构建 graph。 同位置供货按原依赖顺序执行，ledger、tail 和实际 encode 使用同一顺序。只有实际 graph 提前执行而主合成在后的可见结果需要已有 owned pair；其他路径保原共享策略。原 raw 捕获器只在来源位置采样，提前列表不能读取空 prefix；较早消费者使用原 unavailable/strict-subset 路径，错误 epoch、纹理、pin 或回执仍由实际资源 owner 处理。正常晚到的同一预约纹理只填内容、一次执行，不触发重编译、二次 allocation 或重准备。准备期尚未到达的 graph 输入局部 unavailable，不以 provider 原图尺寸预约其未来 graph；已尝试但没有 graph plan 的来源仍保原 source fallback。aggregate 消费当帧层快照并保其他健康槽。

验收沿原 Plan、Coordinator 和签名 App 门：有 graph 的前景 O、U 后另一个改变当前背景的图层、早 C/晚 D、真实取时环、`copyBackground=false` 独立邻例及资源/ID 改名。固定 literal ROI 区分 U 的 prefix、全局空 prefix 与 C 当时背景，保健康后继；核 P 一次执行及最终 GPU/终端捕获。graph-background、utility 成员图的来源消费者及官方默认背景语义仍须各自取得实际资格，不能借调度设计放开它们。普通 provider 使用原 layer 前截点；utility 保原 trigger 后执行，同 trigger 后再运行普通 provider 的组合未接入。degraded member 的绘制跳过不跳过其已计划供货，供货只执行 offscreen 内容，成员继续原局部跳过。

<a id="forward-graph-output-consumption"></a>
### 图输出的供货与作者位合成

前向可见来源复用本节原 ticket、cut schedule 与 owned pair，在真实消费者前只执行一次graph/named供货，仍在自己的作者位主合成；Geometry沿[局部色图](#named-geometry-local-raster)取同CB预先供好的pose，不另推进动画或用raw atlas顶替。早消费者、晚同来源消费者和provider主画必须核同epoch/texture及一次执行，保后继图对shared scratch的覆盖、选中main背景、真正缺源与cycle反例；已有不同空间的clipping准备继续由原submission释放，不为减少计数错误复用。

同帧 graph 结果完成 named 供货，不代表可见层已经完成作者位的主合成。原 Coordinator ledger 保留唯一 texture、content、ticket、history 与 pin；提前供货后的可见层在自己的作者位置借用该结果，沿原 final-composite 消费当前 placement、alpha、depth 和 fog。晚消费不重新 claim、解析依赖、取 layer source、执行 graph、分配或发布，不增加结果缓存、持久标志或第二输出 owner。原 `compositorConsumed` 区分主合成是否完成；晚到的主合成回执只接纳这一消费，不能用上游旧 candidate tails 覆盖已包含后继的 scheduled tails。

强引用和 submission pin 只保 GPU 对象寿命，不能阻止同 command buffer 的后继写入共享工作 pair。Preflight 复用 FrameRuntime 的候选 DAG，在实际来源与 activation 准备后解析唯一截点计划，并返回 SceneDrawing 供 layer loop 消费；仅实际提前执行、主合成在后的可见 graph 选择已有 owned pair，其余保持共享。原 `pairStorage` key、预算、memo、lease、回滚和 pin 承接这项寿命，不复制结果或新增缓存，也不把所有可见 graph 一律私有化。实际准备失败保原局部 fallback，不生成另一份执行排序。

静态 material 的 data 存储只描述成功输出，activation 或局部失败仍可保留之前的 color；分配前不能用它取消可见闭包的 owned 保护。最终内容在 Executor 准备完成后才确定，当前沿原有界 pair 分配保这一潜在消费，不增加扫描、内容缓存或后置复制。

可见 color 结果遇到普通 named publication miss 时，仍保已编码结果与原 lookup，供作者位合成；不伪称供货成功，也不沿 hidden discard 撤销有效主输出。hidden miss 保原局部回退，data 不进入颜色合成，错误资源或回执仍由实际 owner 拒绝最小不安全单元。供货可执行性取决于真实 source 截点；background/prefix、utility 或成员顺序依赖不能借本修复升级为全局 prepass 独立来源。

验收沿原 Coordinator/Bridge 门核 U→P→C 后的晚主消费、history/pin、普通供货失败及重复/过期回执；签名 App 用独立来源的 visible U、hidden P 和更早 C，核双 UV 贡献、作者位遮挡、单次 graph/主消费、改名与 hidden 邻例。先限定这个可复验结果，更广前缀来源、utility/model与其他组合仍沿原队列分别资格。

<a id="color"></a>
## 颜色、数据与显示

source identity、采样用途、颜色表示及物理格式是不同事实。颜色与数据、二维与volume不能因存储相似而互换。

<a id="scalar-data-read"></a>
已证明只读红通道作phase权重的shader接纳非volume二维data。ShaderSchema在准备期区分读取角色与资产用途，保选中noise、normal等原purpose；TextureSlotPurpose复用该关系验证candidate链后直接生成事实，退出无source proof的继承检查。其他source proof保持原合同，颜色/volume冲突局部拒绝；后续Program、selection与binding仍消费精确purpose、publication和二维data表示，普通帧不重新证明。回归见[标量数据GPU](../../../script/tests/scene/test_scene_scalar_mask_data_purpose.py)。

Program 只对已证明的颜色槽做 PMA/straight 适配；data/signal 保原通道。有限 HDR RGB 保留到作者运算与终端，不能提前裁到 0–1；零 alpha 和输出 coverage 沿现表示合同。作者显式饱和仍执行。

独立顶层可见文字的首个 effect 若直接把 layer source 写入后续读取的 framebuffer，准备期可选择保留文字下方当前背景的 RGB：source capture 使用 `glyphRGB + prefixRGB × (1 − glyphAlpha)`，alpha 仍为 glyph coverage。该资格只用于 captured-layer source；图 provider、parented text、image、无后续读取或被覆盖的 target 均沿原路径。SDR/HDR 使用同一颜色合同，不把背景 alpha 混入字形 coverage。

仅红通道 scalar 或 alpha-only 读取有各自准备证明，不能从一条 swizzle 推出整张纹理是 mask。未知用途、混合颜色/数据流或反射不守恒保持局部拒绝。R/A preserved-channel 路径不能外推所有 `.xw` generic artifact 已有完整输出证明。

HDR 合成与显示 EDR 分开：scene color/Bloom 先保浮点范围，唯一终端进行 SDR 裁剪或当前显示 headroom 映射。normal/roughness 不做显示变换。截图导出是普通预览，不能证明物理 EDR 高光。当前 light/receiver 范围见[光照](advanced-object-coverage.md#lighting)。

<a id="hdr-bloom-extraction"></a>
HDR Bloom 的亮度阈值作用于已完成 source 的物理像素，随后才做空间降采样；同一峰值不能因高光变窄或移动一个像素而先被均值降到阈值下。输入保持当前项目颜色域，不插入未经验证的 gamma 转换。首级半尺寸 pass 按每个目标像素覆盖的源像素面积，平均逐源像素的 soft-threshold 贡献；常规尺寸为2×2，奇数尺寸最多3×3，完整覆盖末行列。它替换旧的先 tent 均值再提取，不叠加补偿增益；后续金字塔、重建权重、作者 threshold/feather/strength/scatter/iterations、alpha 与唯一终端保持原职责。

该修正留在现有 `SceneBloomPostProcess`/Metal 首级pass，不新增全尺寸纹理、pass、PSO、uniform ABI、缓存或质量owner。中间失败不写回source，零strength不编码，非HDR保原算法。原[真实Bloom门](../../../script/tests/scene/test_scene_bloom_post_process.py)保宽块/细线、相位、奇数边界、软阈值、alpha及局部失败；13项旧均匀场原始采集质量仍unknown，仅作历史回归，不授整组Ultra身份或限制默认Ultra目标。新6组明确Ultra控制中，5个已有对应量化点与Native相同，另一个低亮关闭正控单列；不是给旧13补造身份。当前Ultra宽块off/on/off-repeat的近中远轮廓与Native接近，细线/单点受JPEG低码与串光限制，未给改变当前空间重建的明显反证。总响应仍不能唯一确定各层权重/核；替代空间重建提案已撤回且无产品实现，现有owner/算法不变，不继续靠泛光调参补偿水滴。后继沿模型反射、辐射与分辨率的真实消费者取得可区分证据；未授官方精确HDR浮点、空间核、全水滴或性能一致。

<a id="history"></a>
## Target、copy 与 history

Prepared target/transition 保有序读写；pool 租约、publication 与 completion 绑定实际 command buffer。unique history 的 seed、reused、失败与取消由原 Coordinator 管理，不靠普通帧重建或全图哈希恢复。

<a id="history-read-write-split"></a>
### 历史目标读写分离（未完成）

unique 历史目标由材质读取后经作者 copy 写回，成功帧直接读取上一帧已提交 publication，避免先整纹理 seed 再读。旧 token 沿原 history pin 保持到本帧 command buffer 完成，`.history` entry 不驱逐/复用；分离读取与 seed 同源，不新增 pin 或 allocator/target owner。

启用条件：沿用 `SceneGraphExecutionState` 与作者图做读写分离——首访必须是材质读、作者 copy 写回同一闭包 identity、copy 源只能在作者 copy 恢复之后读取；`lifecycleIsValidLocked` 接受 `historyRehydrateCopyCount==0`（由 `transaction.intents` 证明闭包由作者 copy 恢复、无 `.initialize`）；`State.reduce` 首读、`publishRehydratedHistory` 与 `materialPublications` 使用 prior publication；有 authored clear 或 material-function clear 的历史不进入 split。本帧任一 stage 的激活判定非 active（inactive/rejected）或 execution 为 capability-level visual-failure/initially-inactive passthrough 时，本帧也不进入 split，保留 seed copy 与已提交 history。成功的 split 帧不复制 seed；运行时材料局部失败时，沿 allocator 已提供的旧历史来源按需准备 seed copy，将本帧 lease 的映射重建为已提交内容，再撤销未执行的作者写入。旧历史仍由原 Coordinator 的 pin、publication 与 command-buffer completion 管理，不新增资源或状态 owner。首帧、reset 或描述符失效不得借此恢复失效内容；没有上一帧逻辑映射时，忽略 stale seed copies 并按 plan 首帧初始化（authored clear 或 transparent history seed）。准入不成立时保留 seed copy/透明初始化；State/publish 校验失败仍走整帧 `framePreparationFailureLocked`（frameRequiresDrop），不得放宽 read-before-write。

验收以[当前运行证据](runtime-evidence-current.md#stale-history-seed)及[同包性能证据](runtime-evidence-current.md#scene-playback-triage-342)为准；最近行为门覆盖 State 读绑定、copy-source、activation/passthrough、运行时材料失败后的内容保持和首帧/reset。实际 App 的同 scene-time 像素 A/B、descriptor 变化与更广的 activation 切换仍需资格，不据纯 reducer 或 fresh token 授真实 pin 生命周期。

<a id="composite-input-admission"></a>
前级双输入合成沿[全效果统一合同](../../architecture/technology-stack-boundaries.md#31-swift-拥有产品状态语言运行时拥有语言语义)准备。Layer admission持源route，Graph计划持有序读写、target和history；Variant按活跃采样槽、选中用途及producer内容形成颜色边界，Program/Finalizer持uniform、purpose/表示和publication，MSL lowering与PSO检查实际接口。Pass数量、target数量、kernel、方向、scale或静态tint不另授执行许可；失败只影响真实不兼容单元并保previous-current。已定义的透明clear可作输入，缺失的实际纹理不能伪装ready。

没有typed边界的兼容改写及尚未表达的通道推导仍有有界source/MSL分析，属于[待通用化边界](../development/development-workflow.md#compatibility-exceptions)。沿原compiler/typed ABI补真实缺口，不增加效果族名单、source许可token或第二套资源/输出owner。具体输入和资格归[运行证据](runtime-evidence-current.md#coverage)。

<a id="typed-color-compilation"></a>
### Typed 颜色编译

`SceneShaderColorBoundary`直接支配普通颜色Program及既有ordinary编译路线。ArtifactBuilder按该边界对实际编译MSL适配采样/返回，产物解码与Program消费相同边界；准备期不再先执行另一段会被丢弃的专用改写或整族source分析。动态颜色沿原uniform producer、当前值与ABI编码，不需要static许可。

普通颜色metadata以该边界的straight、opaque或PMA输出为权威；alpha-only、packed data、独立signal、有序signal/underlay及其storage/loop事实保原typed语义。Passthrough保精确signal槽，数据通道不做颜色适配。已准备的graph ingress事实仅按真实活跃slot投影，不能从输出颜色标签重推身份；仍有实际依赖语义的previous shadow保持。实际接口、uniform字节、选中publication、target/hazard及生命周期错误各在原consumer局部失败。两个backend消费同一边界，普通帧不做source分析或编译。

回归沿真实builder→Program→Metal门核helper/条件/多sample、改名、动态uniform及PMA/straight/alpha/HDR，另核合法data/signal与错误供货/表示/身份。源码模式命中不作验收；未支持的MSL操作和未表达角色按具体失败入队，不以效果模式绕过。

<a id="whole-vector-color-input"></a>
完整向量的颜色输入由原 `ColorMixGraphAnalyzer` 冷准备图追踪实际采样、局部别名、builtin mix 与 RGB 标量写，再由 ShaderSchema/TextureSlotPurpose 交原 Program。已闭合的颜色传递不要求恰有一次 RGB 写：直接复制、乘一和多次合法标量写不因次数或编辑器材质 key 改变输入用途；退出旧次数许可及其无消费者 Set，不新增识别器、owner、缓存或帧内工作。原图仍须闭合每个返回槽的全部 sampler 引用、carrier 读写并排除 vertex 采样；额外活动槽各自取得实际用途。将 mix 解释为 builtin 时必须消费原 syntax 的函数身份，同名 authored helper 不因拼写获得颜色数学证明；证明不足只撤该图事实，不拒整份 shader。

本项只补输入角色，保原 mode、default、注册资产与 candidate 链的冲突边界。Passthrough 继续从选中 publication 取得实际表示；whole-mix、PMA/straight、data FBO、alpha-only/packed signal 与终端 owner 各沿原合同，不能因 vec4 到达输出就把数据改成颜色。验收先在旧 App 核中性乘一正控，再以同字节输入核任意 key 的 alias copy、无注解改名 slot3 的直接复制、原子显隐与健康 peer，经真实资产→子 Program→父 source/Program→main/seal/GPU和原像素门；原生门核多次合法写、同名 helper 把 R 用作 alpha、额外读和实际 data/PMA 供货反例。正控或表示门不成立即停在首错，不换标签、输入或阈值求通过；无精确作者正例不称作者恢复或官方像素等价。

Surface 采用已提交销毁成员时，原 Coordinator 过滤该层 committed 及 pending final tails，保已编码 ledger/pins 到原终态。活 named consumer 的独立 copy、hidden provider、consumer 自身 tail 与 scene color 按真实引用保留。

<a id="terminal"></a>
## 终端材质重放

终端 replay 是同一 GraphExecutor 内的可选优化，保源尺寸采样、冻结输入、真实输出投影与唯一 MainPass。后继 passthrough 不丢最后有效材质；后继成功材质替换候选。只有真实写后读冲突才创建同 descriptor 副本，并沿原 submission 保留。

当前简单 color/placement、部分文字及 captured-main 路径有各自准备资格。复杂 FBO/history/function/geometry 等未取得优化资格时继续原 graph 路线；不能把优化条件升级为所有合法内容的永久门。写入主 pass 后的失败拒绝不安全提交，不能再次合成 graph-final。

<a id="inactive-terminal-source-capture"></a>
### 停用单阶段的末端捕获

普通 layer texture 的唯一 graph 阶段已由原 activation 判为旁路且没有显式目标时，原源捕获可直接写同规格的固定末端 pair member。源采样、色彩表示、末端 publication、提交与 main 保留，省去该帧的中间写入和同规格复制。判定在原 Executor 接受旁路处完成，沿原 ResourcePassEncoder 替换尚未编码的捕获目标。原计划仍为热启用提供完整 pair。实际源与目的相撞、带前缀或依赖附件的捕获、多阶段、显式目标以及错误旁路保原路由；独立的 named 发布继续使用实际末端。无需新 owner、状态或缓存。

验收核普通视频原 PTS、source capture→固定末端→主合成、复制计数与 GPU 排空，保热启用实际材质和显式 FBO/history 反例。数值/画面先核等价，只用同范围计数说明省掉的 GPU 指令，不从计数估算能耗。

<a id="limits"></a>
## 当前边界与回归

任意 Shader 方言、所有数组/动态控制流、全部 sampler/provider/颜色组合、LUT 材质 consumer 与完整 HDR/官方像素等价未覆盖。具体未闭项归[队列](../roadmap/scene-open-breakpoint-queue.md)。

最近行为入口：[PassEncoder/GPU](../../../script/tests/scene/test_scene_resolved_material_pass_encoder.py)、[copy/history](../../../script/tests/scene/test_scene_material_copy_history_rendering.py)、[准备取消](../../../script/tests/scene/test_scene_source_preparation_cancellation.py)。这些门分别验证其真实输入，不能相互代验全部语言或画面。

<a id="material-affine-frame-evidence"></a>
### 完整仿射源帧的运行范围

2026-11-15按[完整源帧合同](#material-affine-frames)，Loader对源投影后full basis用原有限/非零det与四角bounds，退正轴许可；Lit及Generic Derivation退无数学需求的轴门，Derivation同guard里publication已涵盖的SlotBinding重复重验退出。Source捕获的轴域helper整体更名、两处调用行为不变，无alias。六产品净−9行，无新shader/ABI/PSO/owner/clock/cache或fallback类型。Generic仍按作者UV采样，宿主只送完整companion，不偷偷改坐标；真正publication/purpose/identity及其它invariant不降级。

真实Candidate/Catalog同36份TEX，新增14个合法single/phase中心观察与8个失败分类（rot/mirror/skew、改名、legacy非等比源投影、共线det/NaN Reader/第四角及实际源越界）全部通过；方向不由1×1中心代证。原Candidate完整字段/旧源帧合同与像素逐值同。固定Lit的37原vectors/67份输入/56保留独立合同及smallAtlas保持，退原skew禁令；8组2×2 mapA/normal的实际RGBA与独立排列纹理严格等值。两backend各6个新增Generic观察完成GPU，显式companion与raw取样符合作者表达；旧组、MSL及schema逐值/逐字同。standalone既有process-private UUID使request/artifact字节跨进程不同，原值与30组差异已保，不宣这些artifact字节复用。

最近原Finalizer同class五方法96.065s通过、源码稳定：保持purpose/semantic/exact/real assembly/mapped-resolution；六个分类断言中五个invariant、一个texture/resourceSnapshotUnresolved，不一概称assembly错误。Native原十方法的before实际旧功能红，after十方法116.201s全过。最初before系统Python3.9不支持原helper zip(strict)、旧program-rejected后附带KeyError及literal half精度过严均原样保留；CPU以既有Python3.12复评、literal沿原1 half-ULP合同，实际affine==independentCrop仍严格相等，未改TEX/UV/原像素oracle或产品。

普通Debug31.689s、六产品/project/锁文件前后稳定，strict deep/原helpers通过；exe ec6f311e…ddb7d、dylib33e5211f…9f5b2，metallib仍9062517f…0864d。完整Generic App两场，每场四effect panel及健康peer，比较显式Rotation/Translation的affine、独立crop、故意不声明companion的raw affine与无frame完整atlas参考。旧独立控制健康、affine为真实entry copy基底[13,29,47]，在预声明[0,128,0]处像素红；新版所有literal颜色/alpha、panel范围与两对完整像素等值通过，raw与crop明显不同。每次4层实际Generic→material/tail/main/seal/GPU完成、零截断并排空。原24组Generic fixture/协议与原测量输出不变；原13组model fixture也不变。模型实际颜色/孔/投影及独立作者归[模型证据](model-runtime-evidence.md#model-affine-frames)，不在此重复。

原生与App输入/红绿/失败/源码及范围、独审归`.artifacts/scene-model-affine-frame-20261115`；作者原报告归`.artifacts/scene-evidence/runs/scene-model-affine-frame-20261115`。没有活动作者affine命中；不授所有shader自动应用frame、任意fractional线性footprint隔离或source padding域扩大。BaseImage独立sprite路径及refraction/exactscale本地合同继续各自原边界。
