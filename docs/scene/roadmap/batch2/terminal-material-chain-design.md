<!-- document-role: active-plan -->
# 多段材质链的输入尺寸与终端显示

目标：修正普通 solid 特效把屏幕尺寸当作源纹理尺寸造成的重复采样，同时保留末尾效果停用时前一有效材质的屏幕细节。沿用唯一 graph、Program、pool、submission 与 MainPass，不增加样本分支或第二输出链。

## 行为与范围

官方 2.8.0.42 自有实验（2026-10-11）确认：120×60 solid 经 identity 后，下一段 g_Texture0Resolution.xy/zw 仍为 120×60，不随世界缩放及窗口尺寸改变；10×10 solid 生成64周期条纹，末段 identity 停用时为屏幕密度，启用时经历小尺寸中间采样。固定输入、二进制和像素测量保存在 `.artifacts/tmp/effect-texture-extent-20261011/`，失败探针不作为合同。真实纹理替换的尺寸比例问题是该能力的消费者，不是准入键。

首批限定可见、非 provider 的简单 color 链、普通 source-over、target-pixel 顶点、无 FBO/history/function/compose/几何网格；保留现高级混合职责。2026-10-12 补充：普通正交文字的单 stage 链复用同一证明与 terminal receipt，保留文字源尺寸、padding、pivot 和动态纹理 generation；作者顶点越过原矩形时直接进入既有 MainPass，不先采已裁的 graph-final。文字高级混合、透视及跨图输出暂不扩域。先验证无外部依赖，再依据同一资源生命周期合同接入已准入的外部只读输入。未验证的跨图 provider 与复杂图保持原路径。

## 外部只读输入扩域（2026-10-12）

已证首错是consumer工作纹理使用placement放大尺寸，named provider和Resolution编码已传递真实资源尺寸；不修改作者shader、采样器或uniform数值。扩展同一prepared资格，使原依赖owner已准入的精确externalPrimary在可见、非provider、简单color链及target-pixel顶点证明成立时使用同一源尺寸/terminal链；保留`!requiresGraphOutputProvider`：本片不要求provider graph output；binding仍由原owner准入，不能直接删除全部dependency守卫。外部text、透视solid、高级混合、aggregate、同层/secondary、几何placement特殊合同与复杂图不据此扩大。

原FrameInputs依赖证据、PreparedLedger与GPU submission共同保留provider/slot/epoch/object/content及实际texture；terminal replay只消费已经验证并编码的同帧资源，冻结Program输入不再解析/捕获。最终消费仍通过唯一ticket、MainPass和completion pin，不能为named输入新增尺寸表、资源缓存或输出入口。真实写后读冲突继续原输入副本机制；普通缺图沿原局部passthrough；陈旧/被覆盖资源拒绝当前不安全单元，不能回放旧帧。

验收补充：尺寸不同的named provider与consumer、scale/viewport改变、末段active/inactive/失败、多段覆盖保留、错误provider/slot/epoch/object/content、同buffer/重复消费、取消与完成前pin。官方named实验须先通过内容正控；历史失败探针不作数值合同。原始376截图必须实际减少矩形重复，保留头部deformer独立缺口及其他样本回归，不以效果节点执行成功代替画面收益。

## 职责与数据流

1. Capability 用已有 prepared graph/material/variant 事实证明所有可能成为终端的材质；纯停用或局部失败阶段可透传，不独立发明材质。
2. FramePreflight 使用真实静态源 mapped extent；无静态源的程序化 solid 使用作者尺寸。Resolution uniform 始终来自真实资源 descriptor，不伪造 Candidate 或修改 shader 数学。
3. GraphExecutor 仍准备和执行完整小尺寸 graph。最后成功 active material 的冻结 Program 通过现 PassEncoder 派生 terminal pass；后续透传不抹掉它。
4. 若后续阶段会覆盖该 pass 所读的 pair 输入，现 pool 按层及纹理槽保留同 descriptor 的临时副本，现 resource encoder 在该阶段完成后、覆盖前追加一次精确 copy。PassEncoder 仅将相同 descriptor 的物理绑定换为副本，采样器、uniform、Program 和 epoch 不变。无覆盖不用副本，无成功材质不用 replay。不得每段复制或新增 registry publication。
5. 副本 pin 由 PreparedGraph 随原 submission ledger 保持至 GPU completion；未编码失败立即释放，编码后取消沿现 ledger terminalizer。无独立生命周期 owner。最终仍由同一 MainPass 在原层顺序消费一次 terminal receipt。

## 取舍、失败与退出

仅缩小所有 RT 会破坏停用尾段的细线；伪造 resolution 会破坏物理资源合同；只回放最后声明阶段会丢失最后有效阶段。这三种捷径不采用。副本只在真实写后读冲突时出现，代价是一张源尺寸纹理和一次拷贝。副本分配或准备失败不得回放被覆盖输入，可局部使用真实 graph 输出（细节降级），不得丢帧或读取陈旧句柄。未知图不扩大准入；新设计没有新的 renderer、clock、资源注册表或提交器。通过后删除单 stage 限制，未证明复杂图继续保留现受限路线。

## 验收

真实 GPU 正反例：末段 active / inactive / 局部失败，细线密度、精确输入颜色、一次必要 copy、无冲突零 copy、同 buffer / stale / one-shot 守恒与完成前 pin。文字补充正负倾斜越界像素、identity 与 alpha、动态日期/时间末字边缘，停用回原 graph 路线。Debug build；原生同一官方自有尺寸及条纹输入对照；原始真实样本短跑与截图。外部依赖、全样本、桌面产品入口、长期性能不得由这些门代替。实现结果与剩余边界归现有队列；完成过程归档，稳定职责归运行架构。

<a id="procedural-solid-local-source"></a>

## 无静态纹理的程序化 solid 源域（2026-10-18，有界已实施）

目标是让局部 effect 的采样域独立于最终放置，关闭固定路径被显示比例带动旋转的问题。新片限定原 capturedLayer 的普通正交可见 solid、无真实 texture Candidate、显式合法作者尺寸；须同时满足现 prepared source-sized simple color claim、dependency.none、非 graph-output provider、无显式 RT/history/function/copy/swap/compose。上述资格在原准备/计划 owner 确定一次，draw/scratch 消费同一选择，不能仅据 layer 类型与 nil Candidate 各自判定。复用原 `SceneLayerEffectSourceExtent.resolveSolid` 作为作者源尺寸权威，graph preflight、draw request 和 scratch reservation 消费同一结果。现投影 AABB 两轴分别取大污染了局部宽高比，该分支退出；不另造密度算法或尺寸缓存。作者尺寸缺席时保原投影 fallback，显式非法在预留前局部拒绝，不能降级绕过；新早分支保原正尺寸资格；0→1像素仍留原 fallback/resolveSolid 边界，不扩大该早分支。真实 Candidate、精确 atlas、native/perspective、外部 provider 与显式 FBO 保各自原来源和资源门。

高级混合除[模式31终端后继](#additive-terminal-density)外仍按完整 graph-final → 原 compositor 输出；不伪造 Candidate 或 `g_TextureNResolution`。graph publication 继续以真实 descriptor 和实际 UV 发布 physical/mapped；固定作者源域经原等比预算处理，最终 canonical world/MVP 独占显示的 scale/angle。保旧普通 source-over、局部失败/停用末段、graph/history/resize、取消与 completion pin；若需新的 logical/physical 类型、采样质量策略或跨图来源，停在相应合同，不借本片改 metadata 含义。

最低验收：自有局部圆与沿环标记，静态非等比外部放置，多个时间点的主轴/轴比保持而标记继续移动；改名及等价变体、viewport/世界scale变化、合法矩形源和缺席/非法尺寸反例。沿实际 preflight→graph descriptor→uniform→GPU→末合成验证，不能只断言helper或冻结clock。原380受控静音多相位对照用户固定路径观察，再用未参与修法的真实样本检查输出/退出；一次有效Debug及独审。不承诺全样本、精确官方音频/相位或性能收益，成本变化另遵循性能卡。

实际原包静音三相位、非零PCM与独立样本后验归[运行证据](../../capabilities/runtime-evidence-current.md#procedural-solid-local-source-20261018)；只关闭固定路径自转反馈，不认完整官方相位/速度、音频幅度或性能通过。

<a id="background-terminal-density"></a>

## 无成员背景采集的终端密度（2026-10-19，有界实现）

目标是避免把巨大屏外画布压到工作纹理后放大。原型只按屏幕密度重放末材质，实际284仅末弧清楚，后继背景capture仍低清先前弧，已撤回；必要证据 `../../../../.artifacts/scene-evidence/runs/arc-density-qualification-20261019/current/report.json`保留，不从单pass或回执计数认三弧修好。

后继沿现 Compiler/ArtifactBuilder→Program→pool/GraphExecutor→唯一MainPass保住背景与新细节。共享SyntaxUnit/binding facts证明canonical quad仅经原MVP、原UV的xy无改写、slot0全部普通2D采样读取原xy；改名、括号与恒等向量构造不改变资格。未知坐标/offset/LOD/helper传递/条件改写/vertex warp拒绝可选入口；targetPixels及prefix-link不能替代证明。先限单个resolved color stage、无成员capturedMain、普通正交、无provider/依赖/显式FBO、最终alpha=1及原完整输出合同；slot0精确ingress复用现capturedMainTargetSourceSlot，不以node.bindings遗漏合法材质alias。不能用当前背景偷换前序active效果，未准入的多段链保原图。

选择在现ArtifactBuilder完成普通MSL、反射、uniform布局和颜色lowering后结构化派生可选完整terminal MSL：精确反射binding0→fragment entry参数，inventory其全部使用，仅允许entry内普通两参数sample，以避冲突的color(0)参数替换完整sample子表达式；外围输入/输出颜色转换及作者运算逐字保留。复用现token/call边界，不以作者源码或生成函数形状匹配算法。未知helper/alias/其他method/参数/资源使用令变体缺席，普通artifact不变。另编GLSL subpass会增加link/反射并重复颜色边界，SPIR-V改写需新工具依赖，均不作为本片路径。

同一artifact/frontend/Program携带版本化proof、可选source SHA/入口与物理texture槽；普通逻辑slot0/Resolution仍来自真实graph descriptor，terminal仅省texture0，保其它槽共享的sampler0及原资源pin。遵循既有build producer identity，同producer请求只给合资格源追加能力版本；变体源计入原缓存预算，PSO/archive均区分变体SHA。launch按实际资格预热，普通帧不分析或编译。现CaptureGeometry比较sourceUV与经实际enclosing-pass raster变换的outputMVP：有限且w恒定非零，四角误差每轴不超1/16目标像素，不随屏外坐标放宽。坐标/目标/PSO不支持保原graph-final；typed role/ticket核对一次消费、当前目标及completion pin，仍用原颜色表示的混合合同。不直接采样正在写的纹理、不放宽framebufferOnly、不增输出owner。

先以自有非平凡alpha背景及连续三draw实际验证BGRA8/RGBA16Float attachment读取、普通冻结texture反例；本机signed cross的MSL2.0拒fetch、2.3才产生color(0)，不能声称原后端版本无条件支持。随后验共享proof改名/等价及邻反例、ordinary artifact不变、颜色转换一次、物理绑定/映射拒绝、停用/失败/stale/重复消费，再用原284三弧与独立样本实际出图。可选能力失败只保原图；如任一前弧再次低清，撤回route，不以末弧或回执计数结案。保2048预算、原uniform及UV，不伪造Candidate/Resolution、不偷换不同extent副本；未覆盖组合及整体性能仍开放。

<a id="additive-terminal-density"></a>

## 加法终端密度（2026-10-19，有界实现）

当前 source-sized 程序化 solid 的高级混合会将小 graph-final 放大，最后一遍连续细线也丢失。先限定项目已有模式31的通用合同 `background + straightSource * alpha`：源为 PMA 时 RGB 系数 one，为 straight 时 sourceAlpha，目标 RGB 系数 one；alpha 保背景值。该模式可由 Metal 固定混合直接消费既有 terminal Program，不需要 framebuffer fetch、另建 scratch、提高全图预算或改作者 shader。其他模式不从此开放。

沿原 capability 的 simple color、全终端变体 target-pixel 及输入保存证明；仅普通正交可见 solid、无依赖/provider/geometry、合法原源尺寸和现有最终覆盖资格。FramePreflight 通过原 frame request 传递模式，GraphExecutor/PassEncoder 派生 typed 加法 pass role，role 进入既有 cache key 和 launch warmup；ordinary frame 不编译。Compositor 与原 submission ticket 同时核对外层模式和 pass role，再在原 MainPass 原层序恰好消费一次；中间 extent/Resolution/UV、activation、失败后前一成功材质与 completion pin 均保持。准备不支持时保真实 graph-final，不能把已消耗的 ticket 再走另一输出。元数据记录实际 blend 资格，避免为所有普通层预热无用加法 PSO。

验收复用连续细线/非平凡源：同 Program 源 extent 不变、实际加法输出细节、straight/PMA/opaque 与背景非1 alpha，以及同 pixel 普通混合相邻反例；末段停用/失败、被覆盖输入、stale/重复消费、改名及等价表达式。GPU 门与 Debug 后，原293对照圆环重复亮段消除、人物/粒子保持，另验未参与修法的真实加法样本。透明边界、HDR/SDR、resize 与取消沿原约束；未覆盖组合保持开放。收益必须来自实际清晰度和可比开销，不从256²不变或通过测试推性能结论。

实际运行与剩余边界归[当前证据](../../capabilities/runtime-evidence-current.md#additive-terminal-density-20261019)；284三弧仍开放，不由293连续环或单pass回执代验。

<a id="image-terminal-placement"></a>

## 普通图片末材质的放置坐标（2026-10-21，有界实施）

原生原包的局部揭露在 cover 裁切后偏离可见目标，而官方人工观察贴着鼠标；精确官方端点序列尚未取得。当前普通 image 始终将完整 graph-final 贴到输出卡，最后材质所见 ordinary MVP/inverse 仍是局部工作纹理空间。现终链 owner 让合资格图片的最后有效材质观察最终放置空间，不修改全局 pointer、作者 shader、Resolution 或单独的 inverse。中间效果的坐标域、物理 AppKit/DPI、脚本 hover 及全局倍率不由本片结案。

沿现 capability → FramePreflight → GraphExecutor/PassEncoder → ticket → 唯一 MainPass 扩域：仅可见正交普通 image、capturedLayerTexture、普通 source-over、无 provider/dependency/geometry，仍须原简单 color 链及全部潜在终端变体准入。继续原非 solid capture extent、源捕获、纹理帧/UV、alpha/tint/lighting 和完整前序 graph；末材质消费冻结的真实前序输出，不能改采原图或当前 attachment。仅同一最终 Program 的 ordinary MVP/inverse 配对替换为实际输出卡变换，原 renderSize、采样对象/尺寸、uniform、颜色和资源生命周期不变。

准备期追加一个通用 replay 资格：实际 MVP/renderSize ABI 存在且合法，并明确不读取 fragment raster position。两种 frontend 在各自既有准备阶段产生这一事实，artifact 缺少事实视为未资格；不在普通帧重新分析源码。现 `targetPixels` 仅说明顶点输入单位，不能单独保证上述性质。新的 image 入口消费同一 prepared 结论；旧 solid/text/background 资格不借此扩张或退役。额外 outer material/depth/fog、非1最终合成 alpha、高级混合、provider/复杂图仍沿原图；不因最终 consumer 拒绝而丢失本来可显示的图片。

新增 image 路径的可选 terminal Program/PSO 编译或函数准备失败，在任何终端写入前保留真实 graph-final；既有快照预算不足仍沿原有界回退；身份/资源不安全错误仍拒最小不安全单元，已开始终端编码不再双重合成。最后有效材质与被后继覆盖的输入仍由原 executor/pool 保全，同一 receipt 一次消费并 pin 至 GPU completion。若实际画面未改善或前序采样/颜色回退，撤回 image 入口，不用调整鼠标倍率、源尺寸或放宽视觉指标挽救。

最低验收：先用自有非平凡前序效果与局部 pointer shader，通过真实 image 准入和终端 consumer，验证 cover/不同尺寸放置下响应位置、前序颜色、冻结输入/Resolution、只变 MVP pair；改名/等价变体与 fragment raster read、缺 ABI、provider/高级混合/透视/几何等相邻反例。复用 active/inactive/失败末段、快照失败和一次消费门；在非不透明背景验证 straight/PMA alpha。有效 Debug 后，原199默认ROI需由旧偏移点响应改为可见目标点响应，并以未参与修法的真实 image 链检查画面与退出。人工官方观察仅支持功能方向，不声明精确官方像素一致；性能收益另测。

实际结果、构建身份与原图由[本批后验](../../capabilities/runtime-evidence-current.md#image-terminal-placement-20261021)唯一维护。原199默认揭露位置、自有变体与独立真实图片链完成有界验收；PMA专项夹具未取得真实Program资格，未冒通过，完整alpha/profile与物理输入域仍待扩验。

<a id="builtin-image-additive-rgb"></a>
## 内建图片材质的加法 RGB（2026-10-22，有界落地）

普通图片将已声明的 additive 材质丢为 nil，末合成退到 source-over，发光源因而遮暗背景。官方纯图片自有板已区分两者：双非黑背景、texture A0/0.5/1、layer alpha0.9下，translucent正控一致，additive保完整背景差且源coverage只乘一次；default/省略alphaWriting的RGB相同。两轮含未资格自有effect的污染板不提供语义结论；opaque PNG不能证明最终A写入，保留该未知。

沿现 RenderDescriptor 单次准备 host-builtin genericimage2、显式VERSION2、唯一普通slot0的无lighting材质；只增加additive、无depth、nocull、alphaWriting缺省/default、普通image/quad、无instance/provider/utility/geometry且layer colorBlendMode0的终端资格。正交与透视共用这一无depth片，旧透视translucent/depth资格保持。仅退出本资格被丢为nil的分支，不把任意basePass状态转给外层；原source raw overwrite及冲突拒绝不变。

同一typed state进入现frame索引、SceneDrawing请求与唯一MainPass。仅确有该需求时在原image pipeline准备一个PSO；普通帧不解析/编译或新建缓存。它使用原普通image片元与straight/PMA关联，仅目标RGB因子改one；源RGB、Alpha因子及write mask保持，因此相同输入的A结果不变，不宣称default A官方一致。不得复用directDraw额外coverage的alphaWeightedAdditive，也不与高级模式31合并。

源捕获继续不带terminal state的原bind；存在外层state时保原replay拒绝，完整前序graph和真实graph-final仍执行，末图仅合成一次。只在实际MainPass选择新PSO，group/任意透明RT不扩。可选PSO失败沿原source-over安全输出，不丢整层或启动；安全句柄/epoch失败仍严格拒绝。shape、custom/multi-pass、LIGHTING、其他state和高级混合维持原边界。

实际动态createLayer材质Catalog仍只准translucent；本片未扩，手工prepared模板投影不等于真实动态创建支持。

验收复用纯图片官方RGB板，补prepared准入/手工模板投影、非白straight/PMA与A0/0.5/1、layer alpha0/0.5/1、原Alpha结果不变、source bind不变及depth/cull/未知字段反例；有前序效果的图须证完整graph-final到末合成。改名/等价输入不改变资格。Debug后核原炫光默认/关闭亮度变化的实际颜色、三effect/GPU/次帧与健康独立样本；无实际改善或邻例回归即修正或撤回，不调作者亮度。HDR/SDR有限值沿原片元与目标，未做全HDR/任意RT/官方A或性能验收不认领。

实际原图、数值、构建与失败边界由[本批后验](../../capabilities/runtime-evidence-current.md#builtin-image-additive-rgb-20261022)维护。

<a id="authored-direct-draw-domain"></a>
## 作者 direct-draw 四点域（2026-10-23，已实施，有界验收）

无源 quad 的真实几何、shader 输入域与最终放置已由同一 prepared 链贯通，恢复越界光束的覆盖；光强、作者 origin 和 Linear/Radial/Corner 的效果数学继续归原作者 Program。不同光线/受光样式与声明归[光照样本清单](../../capabilities/lighting-sample-inventory.md)，执行顺序归现役队列。本节的官方输入、测量、候选失败与修后运行统一归[四点域证据](../../history/authored-direct-draw-domain-2026-10-23.md#authored-direct-draw-domain-20261023)。

原单位方形载体会裁掉越界四点域。官方自有 R3 板证明单位、越界矩形和越界凸四点的 polygon 覆盖，raw UV/position 的相对变化支持画布高度 H 尺度；本项目保留既有居中顶点合同 `L(p)=H*(p.x-.5,.5-p.y)`。官方与本项目窗口比例不同，CUA 原图含 ICC/JPEG，direct-draw 颜色也有共同偏移，绝对位置截距与 RGB 不据此认定为 ±2 数值一致或官方 parity。R1 缺依赖失败不作语义证据；R2 缺活跃 p0 的 UV/position 歧义由只补 witness 的 R3 消歧，不据此认领凹四边形、任意顶点位移或非仿射插值拓扑。

准备期从 `EffectPerspectiveUV` 的 p0…p3 材质角色、唯一 source-emitting material node、所有 variant 一致的活跃 float2 producer、新属性 ABI 与 identity-MVP footprint proof 构成 typed 几何绑定，不按 uniform 名、shader/effect 路径或样本猜角点。角色无效或竞争、多 emitter、点被优化而未活跃、绑定/profile 未证只是不获新域资格：沿原 graph/stage 准入保留 unit，准备报告携带 `role-invalid`、`source-ambiguous`、`point-bindings-unproven` 或 `vertex-input-unqualified` 原因，不新增帧日志或猜首个。该 fallback 不放宽原 image-filter/graph-input 准入。已绑定新域后的非有限数、退化/自交与 frame/generation 失配仍拒绝最小不安全单元。动态值复用同一 DynamicSnapshot 和原 uniform resolver，不缓存初值、帧内不解析 JSON 或编译。

通用顶点 ABI 的两组 packed float4 坐标有唯一 unit 默认值；generic normalizer 与 bounded Swift wrapper 都按原 strip 顺序 p3,p2,p0,p1 构造属性，随后执行未改的作者 vertex body。字段是 host 保留语义，布局与 artifact/cache 身份同步区分新旧 ABI，真实点值不是编译 key。`vertexInputSize` 仅给源生成节点提供 H×H；物理 target/renderSize 与 texture Resolution 保持实际尺寸。effect-model、effect-MVP 的 pixelsToUnit 使用相同逻辑顶点单位，保留原 H-square world/clip 基准。

同帧 plan 保存四点、原 square basis、AABB 与 capture/terminal MVP。真实 polygon 经正交 capture MVP 绘入透明清空的有界 RTT；末 compositor 仍消费该 AABB 纹理一次，未覆盖区域为 RGBA0。只有 prepared source material key 取得四点与 capture MVP；其他节点保单位属性/fullTargetMVP，现有 source/chain 能力边界不变。原 world/parent/parallax 与唯一 camera、allocator、ledger、compositor 继续持权，不新增光线 renderer。

nominal-output owner 现在同时表达已证 opaque 与 `.premultipliedAlpha`，signal passthrough 和 color boundary 仍优先，其他未知内容仍为 nil；这只补齐已证输出事实，不新增 shader 分类。fragment opaque 只证明覆盖内 A=1，现 attachment-storage owner 将透明 clear0 的部分覆盖颜色附件推导为 PMA；straight/PMA 表示保持，data/独立 alpha 不因此取得扩域资格。每帧沿原 clear、lease 与 publication 生命周期消除旧覆盖，物理范围/预算/旧 token 检查保持。

修后同一候选 App 的四项运行已完成：R3 自有常量/UV/position 的 U/E/N 域通过真实 prepared source 到终端，R2 六格缺活跃 p0 保健康 unit 并有 typed 原因，三种方向的自有 Color 板均可见；332 layer292 实际加载 v3 几何并出现左上斜入的光束。两后端属性与透明留白、CPU 数学/准备反例及构建证据的范围由正式证据 owner 列明。原332仍有其他未准入项；独立 holdout、完整 Gradient/mask、动态点、后续过滤链、全 HDR、官方绝对 RGB/位置及性能须继续分别验收，视频和整场景状态不由本节改变。

<a id="prepared-frame-uniform-query"></a>
## Prepared 帧输入与统一数值查询（2026-10-23，已实施、有界回归）

原DirectDraw几何消费不可变帧输入，却直接依赖可变Capability Catalog及ProgramFinalizer内部查询；这两条边现已退出。目标是让几何与shader继续消费同一prepared身份、数值与失败合同；本片是职责迁移，不改变画面算法、作者能力或宣称性能收益。相机setter候选的两源App冻结对照独立保留，本片不能混入该对照身份。

将原FrameInputContract、其material key、PreparedUniformBinding及四字段Uniform schema的**实际值定义**移到一个中性prepared帧输入职责；compiler只构造这些值，Catalog保有准入/variant/cache权威。原名称所需typealias只指向迁出的唯一值定义，不将Catalog/Finalizer登记为公共接口。原完整authored-uniform解析（source/fallback/range/scalar-splat/ABI）移到既有Program的同一数值查询，几何Float2投影与shader finalize都调用它；删除旧实现，不留转发facade或第二算法。编码继续复用原UniformEncoder/Projection，template/graph/snapshot、资源与最终输出owner不变。

选择先做等价迁移，而不同时预计算新policy或缓存ActiveUniformIdentity：当前采样仅证明部分frame准备caller，不能把整个prepare成本归给schema。HostSchema的frame重复另在ProgramDerivation；只改Dynamic不算关闭它。后继优化须单独冻结协议并证明收益。本片不新加payload flags、cache identity、clock、资源/graph重建或更宽准入；当前值、resolved source、fallback字节、live authored值/属性范围及frame/generation照常校验，非法fallback不能提前拒绝原本合法的live值。

验收复用真实Finalizer/Derivation正反门，补同一prepared四点binding/snapshot的几何Float2与Program uniform字节相等、wrong ABI/source、range/fallback及非有限反例；变量/资源改名不影响结果。依赖门须真实消掉两边，不调public白名单或todo上限。一次Debug、既有四点域/几何最近门和未参与修法样本实际输出/stop排空；共享设备未释放前仅记CPU/结构结果。任一原数值、失败码、Program/variant身份或生命周期回退即撤回迁移；不以目录移动、build或样本非黑冒验收。

当前五个实际值定义已迁出，完整数值核由Program唯一拥有；依赖门45 todo边通过，只删一条真实退出的Projection旧登记，未扩公共白名单/预算。真实prepared四点与Finalizer独立字节/错误oracle的4方法34事实、相邻几何与路由69方法通过；数值核与DTO交叉独审无must-fix。固定5436输入无漂移、优化Debug及严格签名通过，App`d20c964f…3dc7402`。原332仍以geometry-v3/authored-quad加载292、实际encoded-output/GPU完成且左上斜光、人物视频与文字保持；独立311小提琴人物/星空/粒子保持。两原包各12s、静音/中心pointer/30FPS、3024×1964，矩阵PASS/App0/stop1→0/GPUdrain，原件/App/owned输入无漂移。执行观察关闭，不声称逐层compositor观察、官方同phase或新视觉能力；全部Finalizer/Derivation设备门、Release/HDR/多屏与性能未验。身份/必要原图、CPU失格首轮和最终4/34、69门、交叉及实际终审归`.artifacts/scene-evidence/runs/prepared-frame-uniform-query-20261023/`（普通14天），不把迁移数量计作收益。
