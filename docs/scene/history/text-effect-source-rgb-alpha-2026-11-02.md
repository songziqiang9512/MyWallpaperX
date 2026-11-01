# 文字离屏输入 RGB/alpha 与放射恢复（2026-11-02）

> **历史证据 — 非现役入口**。保存实施前设计及本批有界验收；长期职责归[运行架构](../architecture/runtime-architecture.md#text-offscreen-source-rgb-alpha)，未修项归[队列](../roadmap/scene-open-breakpoint-queue.md)。

## 事实、目标与资格

- 官方 raw-FBO 数值表明透明字区的 RGB 随实际下层 prefix 改变，alpha仍为0；clearblue、clearzero、opaque red prefix已区分，固定scene clear RGB方案不成立。`clearEnabled=false`的灰值仍为UNKNOWN，不模拟疑似未清内存。
- 已独立查看CUA原字节图`.artifacts/light-effects-triage-20261101/official-source-map-cua.jpg`：`MWX_TEXT_SOURCE_MAP_20261102`的C_RGB含下层巨大MMMM前缀及上层MWX，C_A仅有上层小MWX。此`owned_map`补齐hidden sampler metadata并用全UV观测；旧corner协议不承担glyph身份正控，`prlctl`全黑PNG失格，不作已证像素或geometry parity。
- 目标：已证需要作者离屏RT读写的文字输入，RGB取当前有序prefix与当前文字的预合成，A独立取该文字glyph coverage；保留direct/single-pass已有路径、前effect阶段及唯一最终compositor，不删末端PMA转换。
- 现`capturedLayerTexture`仅按contentKind归类，所有text Graph都会先capture；它与terminal replay均不是官方离屏需求资格，不能据此全量开启。
- 准备资格：真实顶层text（parentID=nil）、capturedLayerTexture、visible且非graph provider；首stage须resolved、输入等于pair base的layerSource。首活动source消费复用compiled ingress查询（含implicitMissingAlias），必须material写已声明framebuffer且该写入被后继活动typed消费者读取、此前未覆盖；command先读、死RT、effectOutput首读、仅后effect有RT均不启用。
- 资格存现`SceneBackgroundRequirement.capturesTextSourcePrefixRGB`，沿既有readable-main传递；不把捕获路由当资格。首stage可有现activationPolicy，但每stage只求值一次，沿原拓扑证明决定execute/旁路，不新增runtime门；前序effect输出不回退glyph、不提前注入prefix，无法判定的输入保持既有路径。

## 唯一数据流与最小载荷

- 沿原`FramePreflight → FramePreparationRequest/FrameInputs → GraphExecutor → GraphResourcePassEncoder`传最小typed需求与值；不下传完整descriptor，不新增plan、provider、registry、renderer、clock或最终输出owner。
- 最小载荷复用现requirement中的首消费identity/语义、glyph/source publication与同frame sceneBackground resource；capture只收共现的`prefix:(texture,modelViewProjection)?`，矩阵取现attachment replay MVP或effect output MVP。资格只launch计算，普通帧不重新解析、建图或哈希；无新FrameInputs字段、资源owner或revision副本。
- 复用`SceneResolvedMaterialGraphComposition`的readable-main通路：`mainPass.withReadableTarget`先确保初始化，再`endEncoding`；现main pass为`store`。当prefix支持shaderRead、sampleCount=1且与base target不同，同commandBuffer中可直接采样它并写既有base target，无需全屏snapshot/copy。
- prefix仅在当前层作者顺序到达时借用，不能在全帧preflight提前读取像素；完成该capture后方可让main继续写。若目标不具可读条件，沿现局部失败处理，不临时加全屏copy或读取当前写attachment。
- projected UV复用当前attachment空间的已准备placement/replay MVP，经clip/w及现坐标约定映射；不得把glyph局部UV当全屏UV。顶层平移缩放、旋转与perspective按此合同验证，group/local pass不准入；越界沿现采样/clip合同，不猜边缘色。
- 原resource capture同一pass写`RGB=prefix.rgb*(1-glyphCoverage)+alreadyPMAglyphRGB`、`A=glyphCoverage`；glyph沿原alpha/tint调制，prefix采现明确PMA的main RGB，其A不混入。复用secondary texture槽1及capture pipeline，禁止固定scene clear或仅凭变亮改变数学。
- 捕获结果明确发布straight color carrier，使alpha0的prefix RGB继续可读；保原文字raster的PMA声明，不伪造sourceSampling标记。随后信号/颜色Program、alpha处理、末端PMA与唯一compositor照现typed合同消费，不加GodRays特例。
- 复用同一image PSO，不新编译/缓存variant；sourceSampling capture位仅合格capture启用。现fragment uniforms末尾增加64字节投影矩阵、仍一次setFragmentBytes，无新draw/全屏copy；原PMA输入位不造假，不并存第二条文字执行链。

## 生命周期、失败与成本

- prefix与glyph均来自同一surface/frame的现发布；捕获command借用原资源到command completion，取消、切换、回滚沿现submission/lease owner释放，不建history或跨帧prefix缓存。
- stage准备只返回prepared、原旁路意图或真实failure；activation、4个visual failure与间接dependency出口收敛到外层一次passthrough消费，退役内部提前copy。理由/拓扑/integrity拒绝及诊断归原owner，normal stage与后stage不重准备，不递归或重图。
- 首stage旁路时，原source命令尚未encode：替换为ordinary capture，并用其真实representation重发同base/generation的entry atom与snapshot，再生成原passthrough一次；不保straight prefixCarrier冒充PMA glyph。后stage首次准备即见复原表示，末端PMA不变；正常执行保prefix carrier，无新增GPU copy。
- 身份/映射错误只拒当前不安全capture；已有entry publication的effect沿现effect-local previous-current，首capture尚无可发布输入则按原layer-local失败保上一有效输出，不伪造previous-current。保已提交prefix、前effect输出与无关suffix，不发布半套RGB/A、不重清main或重新提交前缀；GPU失败不冒充CPU回滚。
- SDR与HDR保原格式/能量，HDR prefix RGB>1不得UNorm饱和；alpha仍按coverage合同。group目标、MSAA、不可读drawable、lit/captured-main/direct-draw、复杂前effect链没有证据不得顺带扩展。
- 最终产品9文件`+289/-287`、净增2行，相对V2净减84行：删4套visual、2套activation长参copy调用和间接dependency wrapper，按短typed意图统一消费。Swift最大Executor976，Preparation749/VisualFailure470；FramePreflight988不改，无新owner/PSO/copy或重复activation求值。

## 产品落点、验收与停止

- 资格产品文件：`Compilation/Material/SceneResolvedMaterialExecutionCapabilityAdmission.swift`、`SceneResolvedMaterialExecutionCapability.swift`、`SceneResolvedMaterialExecutionCapability+ProgramFirstStagesBackground.swift`；从实际Graph事实承接，不用名称白名单。
- 帧与资源产品文件：`Rendering/Graph/SceneResolvedMaterialGraphExecutor.swift`、`SceneResolvedMaterialGraphExecutor+Preparation.swift`、`SceneResolvedMaterialGraphExecutor+VisualFailurePassthrough.swift`、`SceneGraphResourcePassEncoder.swift`；FramePreflight、GraphComposition、RuntimeBridge与SubmissionCoordinator沿原合同复用，无改动。
- GPU载体：`Rendering/Metal/SceneMetalPipeline.swift`与`Rendering/Composition/SceneImageLayer.metal`；沿现capture绑定/准备职责扩展，不新增光效renderer或另写compositor。
- 最小门复用source-color实际admission、generic Program与Graph capture：读prefix、capture RGB/A、publication representation及terminal；同屏红/白prefix、半alpha glyph、clearzero/clearblue、SDR/HDR>1，补direct、unused RT、command先读、仅后effect有RT、group不准入；首stage inactive/PSO失败时PMA白.5/A.5应保.5而非.25，后stage接续实际复原表示。
- 隔离运行核main结束/store后直接读、不同base写入、无新增全屏copy、次帧/取消/切换/局部失败；补SDR与HDR>1、viewport/缩放与非轴对齐投影、group不准入，再做Debug build和真实358通道/ROI。仅route、加载、非黑或变亮不算验收；失格黑PNG不进入正证。
- 停止条件：prepared资格可判、RGB跟随prefix而A仅跟glyph、direct及前effect不变、representation归一后官方通道成立、无新copy/owner且生命周期门闭合；否则保首失败与未定语义，暂停产品扩展。当前设计不承诺完整文字/光效family或官方几何parity。

<a id="bounded-result"></a>
## 有界结果

- 原358 Clock/Day/Date均执行两pass blur与五pass GodRays；原图明确黑放射/矩形，英文文字并非缺字体或整effect未消费。官方原样本参考仅证白亮样式，不据不同日期/鼠标/audio求全图像素相等。
- V1真实原包无改善：raw bindings为空，实际入口由compiled implicitMissingAlias提供；首effect visibility也有script producer，不能把未命中当数学反证。V2临时资格仅供区分实验，默认原包恢复白亮/黑块消失；其关闭/失败风险不被当作可提交实现。
- 最终实现把通道捕获与现按stage旁路收敛，删除旧重复出口；首stage关闭或准备失败恢复原glyph及真实表示，后stage只准备一次。产品9文件+289/-287、净增2行，无新owner、PSO或全屏copy；每个image uniform固定增加64字节，仅合格capture执行额外prefix采样/投影。
- source-color原方法一次通过并复用；新增25项覆盖implicit/改名/无用RT/顶层范围、非均匀prefix与A0/.5/1、偏移缩放、HDR>1以及首关闭/library/PSO失败和健康suffix，全为实际admission/Program/生产Metal读回。新fixture曾因effect内ordinal、误用active PASS、读取post-rotation逻辑input而失败；逐项修测试身份/观察点，RGBA预期与产品未随测试改动，原失败全保留。
- 静态NOISE-on/off载体38张成功序列跨5.301秒（PNG完成时间），on38种RGB、off逐字节恒定；25请求被替代，benchmark因window snapshot failed为FAIL。只证动态调制，未辨稳定右→中→左特征，不记官方方向/速度或扫描观感已完全一致。 用户随后更正：所报扫描光效属于3586308277；此板取358981原effect，仅保通道/时间正反例，不承担358630验收。
- 334当前原图及用户观察允许不再追调；不据主观微弱差异改作者gain/blend。保该有界记录，队列不再列作缺虹彩。
- 最终签名Debug构建32.981秒、4415输入无漂移，App `2ea97c14…9aae` / dylib `5e4aa3cb…c4f0d`。同原始默认输入/静音/中心pointer各短播5秒，358与独立347均报告PASS、exit0、stop1→0/GPU排空；根亲看最终原图，358白亮放射保持，347人物/网格/文字/红粒子保持。不以短窗计时作性能收益。证据与清理见下方归档。Release、实际HDR显示、多屏/group/MSAA/lit、完整字体/几何parity、性能/能耗均不作本批已证收益。

- 原图执行271项与资源命令门保持通过，连同原source-color方法共4个GPU方法。结构门发现现HEAD唯一main writer出现数已4、清单仍5，按三allowed源与HEAD一致的实际计数收紧为4；不计作本批削减owner或性能收益，原结构失败保留。

- 必要包：`.artifacts/scene-evidence/runs/text-source-rgb-alpha-20261102/metadata/samples/0/runtime_evidence.zip`，31,736,585B / 936文件，SHA256 `60add0a570e5f8a13f83bd8261aecf4355a3a3d9634a0959a4535f8bb8cc3081`，正式副本hash/CRC已核；含原失败、最终原图、官方sourceMap、源/测试身份及独审。38个off ROI逐字节一致，仅保一个并以alias表保全对应关系；不把去重算产品收益。
- 本文的执行期raw路径已清理，必要载荷以原相对名保存在上述zip；同时移除本批连续构建缓存，`du`口径共清理3,079,593,984B目录占用，未删用户样本/其他工作树。清理收据`.artifacts/text-source-rgb-alpha-20261102-cleanup.json`；官方实验预览由用户确认关闭，主客户端与VM保留。扫描反馈已更正至3586308277，包中静态载体不代其运行；按用户要求本批提交后暂停。
