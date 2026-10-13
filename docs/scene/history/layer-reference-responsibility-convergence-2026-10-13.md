<!-- document-role: historical-evidence -->

# 图层引用与 host 职责收敛（2026-10-13）

> **历史证据 — 非现役入口**。稳定边界归[API覆盖表](../capabilities/scenescript-api-coverage.md)与[实际代码地图](../architecture/runtime-as-built-map.md)；未完成项归[属性卡](../roadmap/properties-panel-card.md)、[性能卡](../roadmap/performance-convergence-card.md)与[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

## 已完成的通用语义

已配置的原生 authored layer 引用保持原 referent，由当前合法 actor 的能力门和原 journal 读写普通字段。显式 access scope 只向匹配的同 Domain native receiver 开放这条路径；plain/detached/inherited fallback、hierarchy/transform、topology、bone、媒体/动画及粒子实例继续 owner-bound。retained callable 用已有 Domain + 单调 creator identity 解析原 active/module owner，不再解引用退休 raw owner。没有第二 registry、generation 或 journal；creator 退休后保留普通静态字段是本项目策略，不是 Windows parity。没有样本、路径、hash 或固定源码形状例外。

旧 4506 行 LayerHost 按完整操作迁入七个自然 C 编译单元，粒子实例归原 ParticleInstanceHost；旧定义退出。156 个函数体在 linkage/name 归一后相同；34 项变更为引用范围和安全 callable，删除旧 raw-owner helper、复用四个 helper。HandleHost 最长980行。旧4811行内嵌C回归fixture迁至12个案例/support单元与一份共享header，保17族、116个owner清理顺序和所有断言，不按字符串任意切块。

## 验证身份与实际画面

最终产品41输入 SHA 聚合 `ca86eff16694fd7160390d6c82cc98e419b102435bb010441e075e2f44ff7f56`；reference fixture SHA `1e92cc13fc3a6129701ede840bfe2c5fffac871db9cdff45575aefd435d44b40`。改名/别名/等价访问、不同owner generation、原referent、actor journal、value-only、未配置/foreign/退休dynamic、detached/inherited、附属权限、caught/uncaught rollback、creator退休及allocator替换反例1271 checks正常与ASAN通过，ASAN stderr为空；最近property/预算/media 34项、bone8项及主QuickJS门通过。

fixture最终身份 `76e93653d44df04292a1ed3e69d2be7e5b0c809268ca1af0a1652d9eb2836fc8`，包导入/direct fallback与最新ca86主门通过；收尾清除11个C文件的EOF额外空行，所有非newline字节不变，主门再次通过。旧/迁677有序check及11行stdout等价只属于已撤回c72c产品，证明搬移等价，不能替代ca86验收。c72c曾实际重现退休callable UAF和地址复用误接纳；1d446曾重现nullable thisScene首次访问崩溃，二者均撤回，最终ASAN与相邻反例已修闭。

Developer ID签名Debug显式-O App SHA `732041bcc9f69ba59e0a02226e12b8d0c9e4a2f5b38bae459fe52a980036915d`，正常AppKit→client→daemon→桌面链；3042492564 before缺失的大时钟after实际显示11:07，日期、人物、星星和光束仍显示。未参与本批修法的2932157836人物、水纹、星星和媒体封面继续播放；FrontAVR两次off/on后未新增startup、同桌面window22783，检查实际画面。未控制实时音频/媒体，不能量化音频幅度或媒体来源完整适配。

**未关闭边界。** 304云朵编辑仍发生accepted→launched约8.634s整场景重建，颜色544 `ReferenceError: event is not defined`、1128非有限origin及封面裁切未闭；293两个时钟166/120仍 `TypeError: length of undefined`。完整consumer cohort未通过，不能宣称热更新或全样本完成。三份旧App的15秒编辑CPU/峰值基线已记录，无修后treatment；本批没有已证CPU、GPU、内存或启动改善。其后自有13种完整source→IR→candidate→owner→firstframe参数变体和同Domain多owner反例均通过，不能据此归咎作者；下一步中性观测实际首失败阶段，保完整cohort。

独立只读审查接受最终C权限/lifetime、fixture身份与实际像素边界。最终源、门与退役回执限量保留于 `.artifacts/tmp/property-hot-update-convergence-20261013` 的proof包；证据cache已到1GiB且没有到期包，promotion被预算门拒绝，不扩大预算或删除旧唯一材料；三份基线仅供后继同条件比较，不是收益。临时Swift/C数值probe原样退役，不纳正式源。

## 实施前设计与补充裁决（固定快照）

原设计文档SHA `d9783a9dca963f95443818f5d1729544404a23a0e58eea9bc6640a57ed115be6`。以下保留先设计后实施的方案取舍和两次安全修正，仅修归档后的相对链接；不作为未执行任务，实际范围由上文和现役权威接管。

# Scene Layer host 职责收敛设计

来源边界：仅当前项目自有 C/Swift 代码、公开 C ABI、自有 QuickJS fixture 与 parent 提供的中性事件。source-index 本次只用于 taxonomy/出处读界，不消费研究摘要推导 layer identity 或播放语义。

目标：普通属性编辑应通过已有 per-scene QuickJS → typed mutation → shared frame update 链更新，避免因可修复的启动 owner identity 失配而退回全场景 preparation。本批先由原 guard 的数值原因选择最早 producer 修复；不删消费者、不缩 whole-key cohort、不压制失败，也不把现有 C 静态 journal 重新实现为另一算法。

当前事实：SceneQuickJSLayerHost.c 4506 行混合了 JS handle identity/surface、typed property access、动态创建与拓扑事务、视频与texture animation命令、puppet bone数值、layer catalog和authored mutation baseline。Domain/Owner/LayerRecord 已是唯一状态存储，不能以拆文件再造 registry、owner或普通帧中间state。

数据流保持：prepared layer descriptor/catalog → owner target configure → callback active owner →原handle resolve →既有能力与权限校验 → owner journal →原typed C ABI → Swift owner bundle校验/commit → shared frame channel。layer referent 和当前执行者是不同的身份；如必须改变跨 owner 可用性，需要先明确公开行为合同，不能只去掉 equality。

职责拆分候选（按完整操作和生命周期，最终按调用关系核验）：

- LayerHost 保留 layer catalog、authored mutation staging/baseline和公开 mutation DTO读取；唯一Domain/Owner/record schema仍在Internal.h。
- LayerHandleHost 承担 handle class/finalizer、closure ownership transfer、lookup identity resolve、referent构造、hierarchy/transform读取与JS surface安装。
- LayerValueHost 承担 typed scalar/vector/text/font属性读写、有限值/能力门与对既有journal的委托。
- LayerJournalHost 承担动态值/creation baseline、拓扑序列、owner begin/commit/discard/retirement；包括原transaction participant及rollback边界。
- LayerSceneHost 承担thisScene lookup/order/enumeration/create/sort/destroy与配置解析；保留原leaf-removal admission和journal提交方式。
- LayerMediaHost 承担原video/texture animation对象与命令buffer读取、ended callback生命周期；语义不变，仅搬移既有实现。
- PuppetBoneHost 承担现有bone handle访问、矩阵/pose和mutation DTO；不扩张动画或数值算法。
- 如asset注册/规范化使完整Scene职责超出1000行，把完整asset注册、catalog和alias边界归LayerAssetHost，不能把单函数切块。

跨文件只公开实际被调用的内部函数，使用现有Internal.h；公共SceneQuickJS.h ABI不变。不新增每帧遍历、完整诊断或source/hash dispatch。现有的顺序/资源/handle lifetime guards保持短路次序；行为修复以独立小diff显式呈现，不混进播放/矩阵搬移。

方案取舍：一个巨型C文件能维持static linkage但违反当前体量及职责规则；include式切块不能建立真实职责；按上述完整操作拆编译单元保持同一state和ABI，代价是有限内部helper声明及显式harness source lists同步。选择后者，不创建第二host state或注册层。

失败与退出：拆分如改变allocation failure ownership、journal原子性、dynamic owner权限、顺序或当前输出则撤回该搬移，保留最小反例。旧LayerHost职责搬出后立即撤掉原定义，所有App与standalone compile清单只链接唯一实现。临时DEBUG数值probe在根因验证结束时去掉，由parent统一退役五处Swift probe。

验收：所有触达自有代码文件≤1000行；函数搬移清单和原实现比对；同owner direct/retained/getLayer/getLayerByID、rename/等价表达式变体、跨owner邻近反例、value-only能力限制、retired dynamic/unconfigured/stale generation、caught/uncaught failure及journal rollback；原QuickJS owner budget allocation fault、layer snapshot、retirement/动画/媒体最近门。parent负责唯一Debug App构建与隔离真实UI/IPC/GPU/时间证据；本批C fixture不声称官方parity或真实可见验收。

**设计裁决（2026-10-13）。** 批准上述按完整职责拆编译单元的迁移，复用原Domain/Owner/record、journal、C ABI与既有Swift发布；不是新增功能验收。普通产品实机数值已证启动时`handleOwner != activeOwner == callbackOwner`，紧接文字consumer原TypeError；该事实仅定位跨owner身份拒绝，尚未授权删除权限检查或改变owner_target含义。行为修法按下列公开合同、自有producer证据及相邻反例补充裁决实施。

**入口与退役。** 执行归[属性卡](../roadmap/properties-panel-card.md)；运行状态归[断点队列](../roadmap/scene-open-breakpoint-queue.md)，不另造路线。职责搬移、原ABI/lifecycle门、真实属性/画面及独审通过后，稳定边界归现有架构合同并归档本设计，撤销临时门禁条目。迁移与行为修法分别留审查身份；设计批准不等于运行正确性、性能或全样本验收。

## 已配置thisLayer引用与执行owner分离（2026-10-13）

来源仅官方公开API、自有当前Swift/C与本次中性数值。公开[Shared](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/Shared.html)与[IScene](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IScene.html)支持共享数据和layer引用；不使用作者Script或研究私有表达。

当前首断点进一步确定：合法getLayer/getLayerByID需callback_owns，唯一步入callback的函数先把epoch推进到非零，因此正常lookup生成epoch大于零；实机两次错误handle均index0、ownerTarget1、persistent1、epoch0，与owner handle安装期生成的thisLayer/thisObject layer字段accessor相符。不能因此推测作者如何保存该引用，也不能以lookup-only修复宣称实际属性重建已闭合。

目标：同Domain内，已configure的普通authored thisLayer/thisObject对象引用在共享后保留创建者配置的原层referent，并由当前执行owner的原journal及字段能力处理，等价于接收者按该referent重新lookup；不会重绑接收者的target。未configure的owner receiver、非persistent引用、retired/dynamic及能力拒绝保持原最小失败半径。官方公开资料支持shared跨scripts数据和layer reference，但没有规定native wrapper及creator退役的具体语义，本文是有边界的MyWallpaperX-strategy，不声明Windows parity。

方案比较：

1. Refcount referent cell：为所有字段closure共享一份creator target publication，configure更新一次，owner/closure共同retain。能保留原闭包形态，但新增allocation、refcount/failure出口和拷贝handle retain规则；粒子projection等所有复制点都要跟随，范围比本批必要更大。
2. 复用既有native layer object opaque identity（选择）：ordinary lookup已有SceneLayerHandle class+opaque LayerAccessHandle+class finalizer。让owner material_function_layer采用同一个class与同一identity结构，构造时保持unconfigured owner-target；configure无分配地把opaque identity发布成原catalog index的persistent concrete reference。普通field getter/setter从原生this receiver取这份identity，captured handle仍用于原owner-bound fallback及附属API。本批只增加每owner一份已有handle类型的allocation，没有新cell、registry、state owner或generation owner；无需为每字段再加分配。
3. 推迟layer字段安装/配置：C create ABI没有target参数，owner查询与unconfigured callback当前仍必须fail closed；字段已定义为不可配置，改为可配置再替换会改变JS property contract。把配置前置进create将改变C ABI/Swift全部调用，范围更大，不选。

producer/配置/生命周期：

- install_effect_handle创建owner的material_function_layer时调用完整native layer object factory；factory沿既有layer class的opaque/finalizer协议分配LayerAccessHandle，记录Domain和creator identity，owner_target=true以等待configure。JS object/opaque失败都由原owner construction失败出口释放，不遗留半安装owner。
- configure_layer_identity仍是唯一target publication入口；成功找到既有authored record且确认该原生identity后，原owner target和opaque handle在同一同步无callback配置步骤发布同index，opaque owner_target=false。该API一次配置，不能后续重定向。
- make_layer_handle的显式lookup一律从传入catalog index构造concrete reference，不因等于creator target改变含义；仅现有owner附属bone API表面保持它的已有本owner能力判定。
- 普通layer_get/layer_set优先从匹配同Domain layer class的this receiver取既有opaque identity；原captured accessor不删除，作为原生receiver缺失时的原owner-bound行为。thisObject若是layer本来即alias该material layer对象，使用同一identity。
- record resolution仍要求合法active callback和同Domain record configured/not-destroyed；persistent concrete authored reference可跨creator owner。dynamic、unconfigured late-bound和nonpersistent引用保留creator约束。setter能力与mutation journal按active owner，value-only仅自己非dynamic target visibility；不能按creator身份授予权限。
- 原class finalizer释放object opaque handle一次；owner_destroy释放自己的JS对象引用，shared/JS仍持有的configured静态对象自然由原VM对象生命周期保留；不存creator raw pointer，不查creator registry。所有闭包opaque仍由原CClosure finalizer释放，附属效果/动画/媒体wrapper跨owner不在本批扩能力。域销毁仍释放整个VM，dynamic layer原退休流程保持。
- owner级generation是原C更新入口的caller token，Domain没有generation authority；产品Candidate一次尝试通常向各owner传同参数，但公共ABI可同Domain建不同generation owners。本批不加creator/actor generation等式。receiver stale token仍由原API拒绝；引用安全按唯一Domain/record生命周期判定。

失败与退出：allocation failure、JS_NewObjectClass/SetOpaque失败、半安装owner清理、configure非法target都须无leak/无journal/无半发布；captured未配置thisLayer不能通过共享变成其他层；creator retired后静态字段引用保留是本项目strategy并由自有fixture覆盖，不能外推附属wrapper或官方退役行为。本批temp DEBUGprobe根因/lifecycle验证后删除；旧plain material layer构造退出，不留双receiver或第二state。

验收：真实epoch0自有thisLayer/thisObject共享反例升级为正证，creator target和receiver target不同且mutation ID始终原referent；explicit lookup本层/他层、name/ID/index、rename/alias/bracket/Object.assign变体；同Domain不同owner generations合法共享与receiver stale token拒绝；unconfigured receiver拒绝；foreign/retired dynamic不扩权；caught失败后有效prefix/uncaught whole journal rollback；value-only own visibility保留且foreign/其他字段拒绝；native allocation/closure failure释放与owner retirement反例；原API/bone/媒体/snapshot最近门。root独占App/GPU/UI/CPU测量，实际完整consumer cohort仍要验证，普通field fixture不冒充所有原生wrapper或全Scene兼容。

**补充决定。** 批准复用现native layer opaque identity的已配置authored引用策略和原actor journal；不新增cell/registry/generation owner。动态权限、预算、未配置与失效引用门保持，普通receiver/generic字段与附属wrapper范围明确区分。真实cohort、画面及可比性能另验；不是Windows parity。

**回归夹具职责。** 旧QuickJS单文件测试内嵌4811行C且同Domain留存116个owner；按完整API案例族迁至自然编译单元，保共享diagnostic/storage provider lifetime、执行及销毁顺序、每项行为断言。产品支持源只用现C_SOURCES权威；以同产品身份原/迁运行、逐族token与原Python断言比对验收，不任意切字符串或缩覆盖。

## Shared layer references: permission and callable lifetime supplement (2026-10-13)

This draft uses only project-owned public C ABI fixtures and current host source. It consumes no author Script, shader or private implementation expression. The scope remains a project strategy, not official Windows parity.

The frozen `c72c87a9294287046c2f0345bd0a64d43632c94f35f3f71517f264e5a26ca314` product is withdrawn for acceptance. Its shared native receiver ordinary fields remain the intended behavior, but a single broad record resolver unintentionally enlarged attached capabilities. Detached getter/setter calls on a plain receiver, inherited non-native receivers, lookup hierarchy/transform methods, media factory/playback calls and particle instance projection are reproduced as cross-owner accepted by the owned fixture. Captured video and texture resource wrappers already enforce their own creator identity and are refused.

The owned ASAN run independently reproduces a heap use after free at `SceneQuickJSHandleHost.c:105`, `callback_owns_owner`, reached from `get_effect_count` after creator retirement. A regular allocator run also demonstrates retired `getEffectCount`/`getEffect` being accepted by a replacement owner at a reused address. Captured raw owner pointers therefore cannot provide identity or lifetime safety.

The unique layer record resolver will take an explicit access scope. `owner-bound` preserves the former creator equality; `authored-reference` allows a persistent concrete authored referent in the same Domain. All existing callback, bounds, configured/destroyed, dynamic creator and epoch checks remain in that one resolver. Only generic field getter/setter calls with a matching same-Domain native layer receiver use `authored-reference`; the captured fallback of a plain/detached receiver remains `owner-bound`. Hierarchy and transform methods, layer arguments used by topology operations, bone methods, media/texture wrapper acquisition, playback and particle-instance projections use `owner-bound`. Fresh lookup by the active owner remains valid.

All owner-bound callables reachable through a retained object must capture the existing Domain plus monotonically assigned creator identity, and resolve only the Domain's active callback owner after matching both Context Domain and creator identity. They never dereference a stored retired owner pointer. This applies to material getEffect/getEffectCount, executeMaterialFunction, effect visibility accessors, and the complete thisScene namespace. The same bound callable resolver selects the existing module_owner only for the registerAsset operation and requires module evaluation with no active callback, preserving its original phase restriction. The existing `MWXSceneQuickJSLayerAccessHandle`, native closure constructor/finalizer and Domain active/module owner authorities are reused; no registry, refcount cell or generation owner is introduced. Existing executeMaterialFunction epoch checks, visibility journal and typed errors remain. Ordinary authored native fields can still survive creator retirement; attached capabilities reject safely.

Material/effect installation, catalog/public methods, references and visibility form one complete responsibility. If repairing that 990-line host exceeds 1000, move the whole responsibility into `SceneQuickJSMaterialHost.c`, leaving active handle dispatch, callback execution and owner-handle lifetime orchestration in `SceneQuickJSHandleHost.c`. The old material definitions exit immediately, one source authority lists the new unit, and no forwarding wrappers are added. This migration introduces no shader or media algorithm.

Acceptance: the existing positive shared fields and journal atomicity cases remain; detached/inherited and attached cross-owner negative cases reject without journaling or native media/emission calls; a fresh active-owner lookup still exercises these capabilities; retained raw-callable families reject both before and after creator retirement/replacement. The same complete owned fixture passes normally and with ASAN. Native allocation fault and nearest historical gates remain, followed by the root-owned ordinary App complete consumer-cohort and rendering checks. Construction failure releases the same existing opaque closure exactly once; Domain teardown owns all JS closure cleanup.

**安全裁决。** 批准以上唯一resolver的显式access scope及原Domain/identity绑定的安全callable；附属权限恢复原边界，creator退休字段正例保留，替换不安全raw pointer捕获。若体量确需迁移完整material职责，现scope纳入该编译单元；不得新registry/生命周期owner。c72c候选不作验收，安全修后以新身份重跑ASAN、最近门及真实cohort/性能。
