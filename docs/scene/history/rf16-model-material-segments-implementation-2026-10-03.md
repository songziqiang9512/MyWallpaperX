<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# RF16：通用有界多材质模型显示（2026-10-03）

> **历史证据 — 非现役入口**。 设计提交 `fcc0ea1f`；单产品 v1 已获独立终审 **ACCEPT**。证据根 `/private/tmp/mwx-rf16/`；稳定职责见[架构](../architecture/runtime-architecture.md)，下一批只由[兼容路线](../roadmap/scene-compatibility-roadmap.md)选择。

同页历史分节：[已退役设计裁决](#rf16-retired-design)。

## 实际改动与结果

原 MDLV0023 reader 将完整合法五段模型以“四段上限”整拒，导致全部材质段不能进入原资源和绘制链。本批只修改原 `SceneMdlStaticModelReader`：以每模型最多64段的明确工程工作预算替代裸4段 profile，并为超额声明增加独立 typed 错误。64不是官方格式最大值。MDLV0016仍单段，累计编码顶点64MiB、索引32MiB、路径/有限值/局部索引/末尾等安全门不变；格式或后段结构失败仍整模型拒绝。工作预算在第一条材质路径及逐段分配之前检查。

多段沿原完整 metadata → SourceFacts/descriptor → Resources.prepare → 原 mesh/material/纹理 → StaticModels 主循环 → Metal/唯一输出消费，保文件 part 顺序。资源或材质失败继续原 part 局部半径，不新增全模型事务、registry、持久缓存、普通帧解析或样本分派。没有新增需要失效的持久拒绝缓存；metadata与资源准备原两次完整验证保持。本次没有优化CPU峰值、扩大命名材质或上调几何预算。

独立自有输入证实5、8、64段均实际准备并逐段绘色；完整App证实五段投影和八段颜色。真实原包模型724的准备从0恢复为5个part，模型成功集合22→23；但它在本批取得的同帧采样中均位于视锥外，**不宣称原包可见或阴影恢复**。

## 反例、验证与证据身份

旧reader实编14输入的冻结反例见 `reader-baseline-v1/`：完整1/4段成功，完整5/7/64段因旧count界限失败。原包CPU首拒见 `reader-stage/result.json`：724为unsupportedMaterialCount(5)，479为vertexBudgetExceeded(150933888)。count5诊断只证明结构可读；实际材质/GPU/输出由后述门补足。中性参考只贡献完整part顺序与draw range职责，不贡献官方段数上限或私有算法。

最终 **19个唯一方法** 全通过，不累计聚焦重跑：

- Reader12方法覆盖51输入：完整4/5/8/64及混合索引宽度，65/巨大声明typed预算拒绝，legacy/零count格式拒绝，坏后段、全metadata、累计字节门。
- 实际builder1方法覆盖5/8/64与坏8段四个磁盘输入；完整材质链接/纹理slot进入descriptor，坏模型不给出成功前缀。全局catalog保留磁盘材料，不以坏模型为由清空。
- 实际原Resources.prepare及main-loop的4个native方法覆盖7行：每段独立geometry/material/texture与两帧ROI，64段完整消费；真实native配额只允许健康peer与前两段，后六段拒绝，释放后新prepare恢复8段，所有行驻留计费恢复基线；坏后段整模型拒绝而peer保留；红后绿的半透明覆盖得到约[64,128,0,255]。纹理transport/部分descriptor使用测试壳，实际图片解码及完整装载链由App另证。
- App2方法、3次执行：five-on/off的五个投影区RGB9对117，五个caster和健康区跨对照逐像素不变；eight的八个颜色均出现，含灰底上的黑段。各次不可变App/输入、实际frame1与next-frame2完成、drain、ready/after整图一致。

产品manifest `product-manifest-v1.json` SHA `d8ecf11e251253262bed4e352c26431cede6b837456406a9be1ce15acb3fe645`；Reader SHA `73d3b631f732b646689c8b5eb5ac1268d7a35941c1552597eaa6d2dfa315327e`。测试最终索引 `test-final-v1.json` SHA `15715328bc150389fd40ff280294a8baf57b3b1e6be9dfabc07295e5a50926e1`，842显式工件经独立复核；壳与证据边界见 `coverage-gap-map-final.md` SHA `e82b5c62b712987bb98ab715658bd84f822fbf297d81dead485e347906378ce1`。两测试源身份和事前App协议在 `test-protocol-final-v1.json`。

完整Debug、code-health、scene-defense、design-gate、文档门与App/helper签名检查通过，`build-v1/receipt.json`证明产品未变；code-health仍有240项既有警告，不是零警告。最终Reader精确路径登记两真实测试模块，避免旧format关键词选中无关模块却漏材质段回归；选择结果见 `selector-specific-result.json`。选择器自身64项测试有9项失败，使用HEAD原registry复跑得到相同失败，涉及既有design-gate期待与旧cursor分组；保留 `selector-check.log`、`selector-head-check.log`、`selector-head-failures.json`，不伪称全库测试绿，不在本批修改这些独立职责的期待。

## 原包同帧观测及诚实上限

原包724五个引用均为普通纹理材质，0与2复用相同材料内容，不称五个不同原资源。静态作者投影不能代表运行时：724父链有脚本变换；旧 runtime-evidence 只含装载输入，没有已提交world。故在隔离源码副本的原terminal readback和原capture请求处加入临时中性观测，经独立审查后编译诊断App；live产品不含这两个hook。原request ID将实际world/camera/visible/alpha/preparedCount与同command buffer completion、PNG导出绑定，没有第二VM、时钟或capture。

旧reader初始两capture在约1.26和3.38秒均无屏内候选。随后按事前60秒、5秒周期协议采样旧、新App，各13个已完成capture，约1.3至57.3秒；输入保持原包、未改资产/变换/脚本。新旧实际frame/time不同，各自只用同CB矩阵，不做假设像素对齐。冻结CPU工具对每part先裁剪投影包络，再独立裁剪实际三角；26个capture、130次part观测均在共同视锥半空间外，三角交集均0。新13条记录均prepared5，旧均0；所有记录effective visible=true、alpha1，但这不等于屏内可见。

最终原包报告 `captured-roi-old-new-report.md` SHA `9aa2c8bec63f960798cc6afbe7bf7de32eb9da45596b446fa35112c34748584e`；combined清单 `captured-roi-old-new-identity.json` SHA `ebe9ede4cd4c94131db8d297a3c9fecd38e2df9e02c0fe155b23147c36abc0b2`。原包两次60秒执行的精确索引各在 `world-baseline-late/index.json` 与 `world-new-late/index.json`，诊断App具有独立字节身份，不能冒充未插桩source-v1 App。

没有从新图片挑ROI；上述结论不覆盖采样间隙、完整播放或离屏模型可能产生的阴影。479仍不在准备集合，原顶点预算未改；不据成功计数直接扩预算。原始首个无插桩观察额外frame2日志断言失败保留；初次诊断runner又误以为Metal状态描述会输出completed，实际为rawValue4，本机SDK确认其值并以原capture导出门重新核对，原FAIL保留、单独sidecar订正，未重跑伪造成功。native首次错误要求坏模型使全局catalog也清空的断言同样保留后纠正，不计产品缺陷。

## 终审与移交

独立产品终审 `product-final-review-v1.md` SHA `0192bf2509174666323c305a3e694f827e7a0071946690d5cdcc63af78995095` 接受单Reader产品、冻结两测试及上述证据，无剩余阻断项。[前置设计](rf16-model-material-segments-implementation-2026-10-03.md#rf16-retired-design)归档，窄gate删除，稳定预算/分段职责移交架构；受保护能力台账、运行索引和工程档案均未修改，由其owner引用本记录。

本批未证明官方parity、性能提升、全模型格式、全场画面恢复或任意数量材质支持。下一主方向返回RF02公开Rotation/Translation companion：先固定官方可区分行为，再沿现有反射/typed uniform/实际sampler闭合。原479资源成本和724其它时域保留为有实际可见证据时再启动的独立后继，不以缺少私有方法为由永久跳过。

<a id="rf16-retired-design"></a>

## 已退役设计裁决

下文完整保留该阶段的历史裁决、证据身份和未验证边界；其中状态与后继顺序仅适用于原记录日期。

<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

<a id="rf16-retired-design--rf16-通用有界多材质静态模型设计2026-10-03已退役"></a>
### RF16 — 通用有界多材质静态模型设计（2026-10-03，已退役）

> **历史证据 — 非现役入口**。历史设计，基线 `4184d55b`，设计提交 `fcc0ea1f`。本批已通过独立产品终审并移交稳定架构；下文保留当时的方案裁决与验收要求，实际结果以同目录实施记录为准。上接[RF16工作卡](../roadmap/batch2/reference-evidence-implementation-cards.md#rf16-visible-model-admission)。中性证据根 `/private/tmp/mwx-rf16/`。解析与资源策略由本项目独立设计，不消费参考私有表达。

设计审查收据：`/private/tmp/mwx-rf16/design-review.md`，SHA `23c436843738408bc76eef5e1427b0e58f61b2b9202c1ea14da588b43be2f3b4`；绑定批准前文档SHA `85a603f25420b6ef9581e2220533b5a3f413a79ccab4f3c2c1cd98fe19356d4e`。该收据属于批准实施前的设计阶段；产品纠正门结果见本批实施记录。

<a id="rf16-retired-design--一目标与现有事实"></a>
#### 一、目标与现有事实

作者的一个合法静态模型可含多个独立材质段；每段保留自己的几何、局部索引、材质身份和原绘制次序，经现唯一模型管线进入最终画面。只要在明确资源/工作上限内且全部结构合法，准入不应因旧“最多4段”证据边界漏掉合法段。不能按场景、layer724、路径或声明5段分派，也不把5设成新的格式规格。

本项目已读证据（下文缩写Swift路径均相对 `MyWallpaperX/Core/SteamWorkshopScene/`，行号属于基线）：

- 原reader的CPU结果 `reader-stage/result.json`（SHA324503dbb87b0ad42e89496bec4bddbc2193591e181ed7992053384aec9febe1）：真实Document24模型候选，原readParts成功22，恰与历史App准备集合相同。479首拒为vertexBudgetExceeded(150933888)；724首拒为unsupportedMaterialCount(5)。
- count5诊断消融 `material-count-ablation/result.json`（SHAf4e131a591992b1982f37e6f78d69bdea0a792275e844c2e7c3c0b0a806a7c46）：只在/tmp把materialCount上限4→5，其余原guard不变，724完整readParts通过，5parts三角数12/17568/32/2320/456，5个材质引用文件均存在。原红保留；不是产品实现或GPU/显示绿。
- 当前RF15 source-v3不可变App原包观察 `/private/tmp/mwx-rf16/original-v1/report.md`：724与479均authored/effective visible true，但prepared缺失；frame0/1 completion、drain及App/输入身份保持。额外frame2日志断言失败已如实保留，不能写单次全绿。暂无724像素ROI。

现4段界限是本项目bounded profile：`SceneMdlStaticModelReader.swift:202`与自有提交0cc11184/5a779cbd；现原测试只有完整2段正例，count5负例只是单段fixture改声明（`test_scene_static_model_reader.py:220–238,395`），并非完整5段格式非法的证据。精确中性参考 [Mirage中性参考](../development/reference/miragewallpaper-rendering-reference.md)第254行 互证多material/submesh保留文件part顺序、按draw range顺序绘制、不能只捕获mesh0。它只贡献职责/作者顺序，不证明官方4/64上限、失败半径或具体算法。准入成本与失败策略仍由本项目原owner及实际证据设计。

479约143.94MiB顶点声明超过原64MiB，资源成本职责单独保留，本片不放宽。5段724不是“完整24模型完成”，也不能推出原包阴影或parity。

<a id="rf16-retired-design--二预算方案与选型裁决"></a>
#### 二、预算方案与选型裁决

<a id="rf16-retired-design--a采用显式每模型工作上限保现几何字节与gpu准入"></a>
##### A（采用）：显式每模型工作上限，保现几何字节与GPU准入

将裸的4段profile改成命名、设计可见的工程工作上限。采用上限 **64段**；该数是保守有限工作预算，不声称官方格式最大值，也不是从5段样本外推。原MDLV0016仍单段；其它版本/meshCount/format合同不变。

64的职责边界：每模型最多64个段循环、64组part/path元数据、最多128次mesh buffer分配尝试；每path原4096字节上限使路径输入总量≤256KiB。它与原累计vertex64MiB/index32MiB共同给出工作边界，防止巨大count+微小段制造约139万parts。count必须在开始逐段解码/分配前拒绝，保持早期O(1)拒绝；没有epsilon、压缩几何、跳段或提高总预算。

原几何byte上限按文件编码计费：48B/vertex，Swift Vertex实际stride64；u16 index也扩成UInt32。因而解码数组有效载荷最坏约85.33MiB顶点+64MiB索引，另有映射Data/allocator/路径/临时数据；这不是实际RSS严格上界。A维持已有几何可达范围，并把新增part元数据工作限制到小的显式范围，没有宣称shared.decoded已覆盖全部CPU成本。若64段边界实际工作反例推翻此预算，保留失败并回修设计与协议；不能测试后静默改期待。

优点：原reader一个产品owner即可闭合准入，GPU依旧按每个native buffer实际heap cost走shared budget；不新增registry、lease、跨owner缓存或完整第三次预扫描。成本：仍是保守有限段数准入，不是无限格式支持；必须在文档中将工作预算与格式合法性分开。当前geometry的既有CPU峰值不在本片重构。

<a id="rf16-retired-design--b复用现shareddecoded做完整临时工作容量预留"></a>
##### B：复用现shared.decoded做完整临时工作容量预留

沿原load/resource owner，在分配decoded arrays前计算并reserve现`SceneResourceBudget.Kind.decoded`，使用已有模型大小/段元数据的有界累计成本，完成消费/失败后释放；GPU buffers仍原native计费。为避免count本身成为CPU爆炸，仍需明确结构/循环工作界限，单靠剩余内存不能放开任意count。

该方案必须解决：计费应在数组分配之前；metadata与正式prepare两个调用的temporary lease如何归属；Data、扩张数组及路径成本怎么保守计；拒绝不能抢先改变健康GPU准备预算优先级。现reader是纯Format值生产者，不应直接依赖Metal默认device的shared budget。若新增独立preflight再完整decode，会额外第三次全模型扫描；若保存prepared decoded IR跨sourcefacts/renderer，则新持有期可能提高启动峰值。这些需要原owner明确交接，不能偷塞第二manager。

优点：可以更早按进程当前decoded余量拒绝，覆盖跨模型/缓存竞争。成本：至少reader/sourcefacts/resources三职责及动态预算时序，可能涉及typedIR生命周期路径；本片没有已证明shared.decoded压力下的真实错误，更难保持旧准备顺序。因此本片不选B。只有实际decoded压力反例推翻A边界时，才另核路径及生命周期后修设计。

<a id="rf16-retired-design--拒绝诊断应区分格式与工作预算"></a>
##### 拒绝诊断应区分格式与工作预算

在同一原reader error enum新增一个明确的“材质段工作预算超限”typed错误，用于已识别多段布局的声明count>64，保留拒绝数量作为中性诊断。count0、版本不支持多段等原结构/格式拒绝保持其原语义；不能继续把合法格式但超过工程工作限额统称unsupported material format。初始guard仍先验证基本结构/版本，再在任何逐段path/数组分配前检查64工作限额。无需公开protocol/新error mapper。

最低变更是原reader一个文件中的命名工作限额、typed error描述与header准入。备选是沿用unsupportedMaterialCount并只改描述，但它会继续混淆reader可读性与预算拒绝，不利于后继479这类资源问题归因；不推荐为了少一case保留该歧义。不是改成无限解码，也不把资源拒绝升级成全场景失败。

<a id="rf16-retired-design--三原owner与发布失败原子性"></a>
#### 三、原owner与发布/失败原子性

**格式整模型验证保持原子性。** `SceneMdlStaticModelReader.swift:114–178`验证所有段/所有索引/末尾后才返回，任何一段坏数据导致整个model的readParts失败，不发布前缀。总vertex/index预算不抬，路径规范/finite/range/index/trailer guard不放松；materialCount扩大不更改vertex格式。

**metadata不成为第二验证权威。** `RuntimeSourceFacts.swift:117–131`调用reader `readMaterialPathsMetadata`，而后者`:101–102`目前完整readParts再取路径。GPU准备在`ScenePreparedStaticModelResources.swift:86`再次readParts。A不新增第三次全模型预扫描、不新建decoded registry或完整缓存，也不为速度把metadata变成只看header后发布不合法模型材质。现有两次load校验的成本由上述总byte/段数界限约束；它不是普通帧重建。若后继有实际启动峰值/时间反例，可在同一reader结构walker中减少只为metadata构造的数组，但本片没有该测量，不为此复制parser或大改typed handoff。

**GPU/材质局部失败与结构验证分开。** `ScenePreparedStaticModelResources.swift:92–101` decoded.compactMap会在某part makeMesh失败时缓存成功子集；`:105–125`某part材质/底图失败同样继续其它part。真实producer是`SceneResourceBudget.swift:132`的native buffer quota或原material/texture miss。这是当前视觉局部fail-soft半径，不等价于完整模型成功，也不能因为显示目标包含“完整”就把所有健康parts一律撤销。

本片扩展的是分段结构及既有已准入材质链；`Rendering/Dependencies/SceneDependencyRenderPlan+StaticModel.swift:90`仍有单named链接准入，增加段数不自动扩大多材质named/provider合同。若真实目标模型在此后续consumer失败，必须沿当前纵向补设计修复，不能用这一边界提前跳过其完整显示目标。

本片保原资源失败半径，不顺手改成全模型GPU事务：成功路径须明确验证每个part最终draw与可见输出；坏结构仍整模型拒绝；分配/材质缺失按原part局部失败、保健康其它模型与安全输出。低quota门必须实际触发第二/后part拒绝，验证原budget/release与其它健康part/模型，而非把preparedLayerID存在当完整成功。只有该真实门暴露越界、泄漏、错误复用身份或成功条件下永久少part，才要求在原resources owner修复并让root补准入职责；“预算不足显示部分”本身不自动升级为产品bug。

因此，现partial geometry cache是需明确标记的证据上限，本设计没有声称它原子完整，也不要求未证的全模型rollback。reader成功、prepared部分、所有parts实际显示三者必须分别报告。

<a id="rf16-retired-design--四六维合同与五项前置判定"></a>
#### 四、六维合同与五项前置判定

| 维度 | 本片合同 |
|---|---|
| 目标 | 资源/工作界内多材质完整合法模型全部parts进入原画面 |
| 当前事实 | 724因旧4段界被整拒；count5诊断其余门通过；当前visible但无prepared，暂无ROI |
| owner | 唯一原StaticModelReader负责结构；原SourceFacts依赖、Resources准备、Pipeline/compositor消费不另建链 |
| fallback | 坏结构整模型拒绝；资源/材质视觉失败保原part局部半径；479预算拒绝保持 |
| 纠正门 | 真实首拒红→合法5/更多part CPU绿→实际GPU逐part→完整原包ROI/completion/next-frame |
| 退役 | 移除裸4段profile及以不完整count5fixture冒充格式上限的期待；诊断副本只留证据不进产品 |

五项设计前置判定：①跨Format→依赖→资源→draw可见结果，命中；②不新增身份/资源权威，仍需确认原owner交接；③不是持久用户数据改写，但用户可见缺模，须实际回归；④reader边界及既有测试/家族冻结，命中；⑤消费中性合法输入结构事实，命中，不消费私有方法。本设计与gate必须经审查变为approved后才实施；诊断消融不是产品验收。

<a id="rf16-retired-design--五拟-owned-产品路径与明确排除"></a>
#### 五、拟 owned 产品路径与明确排除

产品写范围只有：

- `MyWallpaperX/Core/SteamWorkshopScene/Format/SceneMdlStaticModelReader.swift`：命名工作上限及原header准入；其它结构/预算/错误权威不变。

需纳入只读核对而非默认修改的现owner：

- `MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneRuntimeSourceFacts.swift`：metadata全验证/多材质路径。
- `MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/ScenePreparedStaticModelResources.swift`：全部parts成功消费、局部资源失败。
- `MyWallpaperX/Core/SteamWorkshopScene/Rendering/Metal/SceneStaticModelPipeline.swift`：原mesh upload/draw。
- `MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneResourceBudget.swift`：沿用，不加预算/manager。

方案B需要至少前三个实际改动，可能另涉及SceneMdlStaticModel IR承载计费生命周期，不能未审就默认为更好。产品扩路径须指名反例。测试由独立lane负责，可扩原reader/material/rendering门或新单模块，不改RF15冻结验收来藏回归。正式docs/gate由root。

<a id="rf16-retired-design--六执行与纠正门"></a>
#### 六、执行与纠正门

1. **CPU结构正负门**：自有完整5、8、64段各保不同material身份、文件part顺序、局部索引和wide/u16混合；4段与legacy单段旧正控保持。声明65/UInt32max须typed工作预算早拒；未支持版本/布局仍是原typed格式拒绝。显式截断第5/末段、坏后段path/index/finite/trailer、累计vertex64MiB/index32MiB超界整拒，不能返回成功前缀。旧单段改count5的不完整fixture不再冒充五段格式边界；以完整合法五段正例及明确坏后段替代。保旧四段上限造成的修前红和临时消融身份，完整四段仍是成功控制。
2. **依赖与真实prepare/main-loop门**：实际builder由全validated paths建立每part依赖；每part材质和动态参数沿原identity，不采用仅fixture直接构造prepared数组作为完整证据。自有五段模型使用5个可辨材质/纹理/几何区域，经真实resource owner得到5个mesh与对应纹理/材质，原main-loop逐part消费并写唯一compositor；八段输入证明不是count5特例。按预登记输入位置/颜色给每part独立ROI，校验顺序覆盖、alpha/depth以及5段均参与原shadow caster/receiver；一个接收面应出现由五段真实几何决定的遮挡，独立cast-off或无遮挡对照保直接颜色。不得只检查preparedLayerID或假回调计数。64段CPU结构与native真实完整准备/消费需有界门，不能只证明header接受。
3. **真实资源失败门**：使用现真实global/native配额，令首part成功后后part分配拒绝；检查原成功子集/其它健康模型输出和resource释放，不伪造badrecord。此门定义证据半径，不以测试任意要求全模型消失。预算恢复/重新load后完整parts可准备，原479不被放行。
4. **实际完整输入门**：同不可变原包与原inputSHA，当前源App证实724 authored/effective visible但缺prepared，尚没有ROI。先以只输出中性世界bounds/相机投影/遮挡顺序的程序观测和旧图建立ROI预期，冻结后再执行新产品；不能从新产品画面倒推预期位置。预期结果是该ROI出现完整五part模型且周围健康22模型/背景保留，须真实验证，设计不提前承诺一定恢复。逐一核实际material/pass/texture准备和draw；若reader过关而某材质consumer仍失败，必须定位同一纵向首断点，root确认必要owner后修，不能宣称只reader成功等于恢复。记录terminal、实际completion及后帧；若构图被其它内容完全遮挡导致无可辨ROI，如实限定原包证据，不将其算可见收益，自有五/八段可见门仍不可省。
5. **验收边界**：原479超预算、23/24潜在进展与完整24/24区分；无当前shadow几何正交点/ROI就不记原包阴影收益；不称官方算法或parity。完整Debug/gates，独立review核精确产品身份与guard producer，批次窄提交。

<a id="rf16-retired-design--可回退route与待批准内容"></a>
#### 可回退route与待批准内容

沿原资源load route，reader结构或预算拒绝时该model不给出parts/material依赖，原其它模型和安全compositor继续；合法读出后原mesh/material局部失败保既有半径。没有新增legacy/generic双执行、重试无限循环、runtime特例开关或新fallback。若产品变更需撤回，按单职责窄提交回退reader工作上限/typed诊断即可，不涉及资产迁移或持久格式修改。

采用A64工作界与typed工作预算错误，保metadata双校验与资源part局部失败。最低owned产品仅原reader一文件，实际低quota/consumer门发现相关新断点后再扩原owner并复审；方案B不混入实施，479的原顶点预算保持。

<a id="rf16-retired-design--七退役条件"></a>
#### 七、退役条件

真实首拒与独立5/8/64段输入通过结构、依赖、GPU逐段与App可见门，超额/坏后段/资源失败保既定半径，独立终审接受后，稳定工作预算及分段合同移交架构和原owner，设计归档并删除窄gate。原包无可区分ROI时不能称样本恢复；保留后继受害确认，不退役479资源问题或其它未知格式。


## 重型启动与模型解码后继（2026-10-06）

基线 `ba9eccd7`。按用户反馈，从普通 App→SteamWorkshop→coordinator→client→daemon 入口跑完整隔离原包。三体 `3509243656` 约18秒首帧成功；太阳系 `3662790108` 的65秒测试截止仍在准备，延长观察后约76.5秒首帧成功。不能把测试取消写成硬启动失败，也不能以开场标题就认定完整模拟画面正确。运行采样的资源准备线程落在静态MDL顶点读取；其每个分量重复进入Data借用、校验，且每顶点创建临时数组。

修复限于原 `SceneMdlStaticModelReader`：每次公开读取只借用一次输入字节，在生命周期内同步解析；固定stride的顶点/索引块先检查完整长度，再读取块内各值。顶点全部分量的有限性/幅值/包围盒、索引范围、材质段、累计工作预算及尾部验证均保留，返回模型仍拥有独立存储；复用12分量临时数组，删除退役逐16位读法。不新增缓存或模型owner，不改变格式、几何、预算及可见性。

验证采用13项现役reader门，包括普通/非零Data slice所有合法及拒绝结果相同、空输入、混合索引、坏后段与累计预算。太阳系包内69个MDL在优化构建中旧新逐字段或错误描述全部一致；最终两个先后顺序的解码合计约915→119ms与495→124ms，仅是隔离reader测量，不能当整App或释放版加速倍数。早期只有borrowed cursor的实验反序耗时不稳定，未据该数字定论；中途括号编译错误已修复，最终Debug构建通过。

真实多材质GPU门曾4项失败；旧reader替换回同harness也4失败。独立复核确认测试纹理transport存储与查询使用了 `/var`、`/private/var` 或 `/tmp` 不同URL别名；原compiled probe仅规范输入后恢复5/8/64段、peer及quota前缀。最终测试在字典两端统一canonical文件身份，保留所有像素、顺序、预算和恢复断言。不是通过修改产品或放宽断言消除失败，原失败记录保留。

最终签名App太阳系同普通入口约69.1秒首帧成功，模型阶段约22.2秒、资源阶段约41.7秒；这是一次受限Debug前后观察，只有小幅总耗时收益，不声明发布性能或重型兼容完成。实际显示与交互、其它用户配置、三体模拟、太阳系部分材质/模型仍需从开场后继续核验；本片不抬高整样本正确率，不改变所有效果/纹理正确合成的终极目标。

最终真实多材质GPU4项通过，独立只读审查按3产品/测试路径SHA复核；代码健康、依赖、防御、设计、文档与断言门通过。证据根 `/private/tmp/mwx-heavy-startup-20261006`；有界 `runtime-evidence.zip` 保留至2026-10-20，含基线/失败、最终运行身份、比较及必要截图。已停止App、临时HOME、样本副本和编译probe清理；保留既有一份checkpoint构建缓存以继续重型可见性开发。原件只读，未推送。
