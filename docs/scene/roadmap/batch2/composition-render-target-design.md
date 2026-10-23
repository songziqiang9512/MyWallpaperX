<!-- document-role: active-plan -->
<!-- retirementCondition: 获批composition采集profile完成并移交稳定架构；剩余passthrough/变换裁切有明确后继且无无依据source分派后归档。 -->

# D1 — composition 采集范围、source 与目标生命周期

> 状态：普通 composition 的 parent/根位置/copybackground 已[有界验收](../../history/d1-composition-authored-order-implementation-2026-10-04.md)；2026-10-18正交透明源及10-19 native childless framebuffer source Program 边界见本卡，实际结果归[运行证据](../../capabilities/runtime-evidence-current.md#native-framebuffer-source-20261019)。其余特殊形态及完整官方parity仍未开放；当前执行顺序只由[兼容路线](../scene-compatibility-roadmap.md)维护。

## 目标合同与判据

恢复作者 composition 的真实输入、效果与最终输出，沿现有 authored → prepared graph/resources → typed frame source → Metal → 唯一 compositor 执行。父子成员、作者根位置与背景模式按已证 profile 决定；素材名、样本、截图和旧实现不能决定视觉算法。跨 compilation/rendering/resource、唯一输出 owner、结构家族与作者语义命中顶层设计门。

## 2026-10-04 有界行为裁决与实施

**已有裁决。** 官方 2.8.42 自有黑盒覆盖 parent child、根前后位置、非 child 前后移动、copybackground 三态与空组，具体结果和身份见上方执行记录。成员随 parent 分组，根按作者位置合成；copybackground 缺省/true 采集当时 enclosing 背景，false 透明。不得恢复 prefix 或末后代触发的旧推断。

**现役链路。** SourceRoute/RuntimePlanner 在 descriptor/topology revision 准备成员和唯一执行顺序，graph preparation 与 encode 共用；组纹理由原 pool 预留/pin，真正写入时才复制 enclosing 背景或 clear，嵌套组仍只合成一次。普通帧不重建 parent 闭包；资源/generation/hazard/completion 延续原裁决，局部效果失败不增加第二套 registry/history/compositor。多 sibling/嵌套属项目一致性推广，尚非官方逐项对照。

## 组合层实时显隐实施决定（2026-10-04）

真实326的时钟与分组开关被热更新准入拒绝，而同场景月亮开关可接受；产品可回退重载，这不是整样本无法显隐的证明。本批使已有合法固定分组在同一窗口内切换，避免为可见性变化重建场景。复用 SourceRoute 对普通 composition 成员的裁决，原 visibility 准入/准备闭包覆盖合法 composition 祖先及后代；无环、唯一身份、父子索引一致仍必需，passthrough、依赖型组与未支持成员仍保留原边界。无子层的背景采集 composition 同样沿既有 source route 准备，不因嵌套而遗漏。初始隐藏的子图、图片及文字进入既有 launch preparation，已准备组保留 capture 计划；无局部源资格的无 effect 组仅保留顺序，实际分配、编码和输出仍由当前 typed visibility 集决定。drawable 可读用途在启动时涵盖潜在高级混合层，不能用初始隐藏撤销后续采样所需能力。不新增树、时钟或 compositor owner，不在普通帧重建闭包。

验收包含初始隐藏→显示→隐藏→恢复、嵌套组、子层自身 false、子 effect/文字、健康邻层与静态显隐像素对照，以及畸形层级反例、Debug build 和真实326同输入开关。普通视觉资源失败继续局部降级；非法结构拒绝目标，整键原子准入不拆分。完成此固定分组闭环即收口，不借机扩大 passthrough、变换裁切或官方 parity；启动准备可能增加，实际热更新是否避免重载及画面是否恢复分别验证。

## 成员闭包扩展到完整 parent 级联（2026-10-07）

真实322 的组员是带 transform 父子链的 image/text（中间成员自带效果、叶子可再挂子层），现行守卫要求 image/solid/text 成员 childless，导致两组被 `execution-route-utility-composition-subtree-shape` 整体拒绝、组捕获与组级效果全部缺失。成员语义按本卡既裁决「成员随 parent 分组」推广：成员闭包=完整 parent 闭包，中间 plain 成员允许拥有子层（深层成员沿既有 world frame 父链合成进入同一组目标），成员类型约束不变——模型/粒子/灯、非组合 utility、passthrough、依赖型组维持原排除，父子索引一致与无环必需不变。成员效果在组目标内的执行、嵌套组合成一次、pool/pin/generation/completion 全部沿用现役机制，不新增 owner、不在普通帧重建闭包。成员级 `dependencyLayerIDs`/`authoredDependencies` 的准入在扩展前后保持一致（本批不新增成员级依赖检查，官方成员级依赖语义未证前维持现状，留待组合 parity 批裁决）。

验收：真实322 两组获准捕获且零新增 passthrough，原包三视图构图与组级色差可见改善；既有组合 App 门（authored order 十案、visibility、effect visibility）零回归；成员含模型/粒子的负例仍整组拒绝。

## 初始关闭效果的实时激活决定（2026-10-05）

真实339的独立composition可在启动前开启CRT、色差和示波器模式，但运行中同键被拒绝。首断点是inactive effect准备准入漏掉composition，不是shader能力缺失。把现有standalone fullscreen准备规则推广到SourceRoute已支持的无父子、无依赖composition；保留原effect Program、activation passthrough、capture计划和唯一compositor。普通值更新只发布typed snapshot，不重编或重建场景。provider、named消费、passthrough、父子及未知source形态不借此开放；脚本候选也不能绕过utility依赖限制。

完整图与真实资源准备成功才声明live consumer，缺shader或同键任一目标缺能力时原子拒绝且保留旧画面。先用原产品同输入红例，再验自有composition效果开关/健康后方层像素、缺shader负门、真实339三个开关的graph/GPU/合成及同窗口恢复。与启动时同选项对照，完成这条现有链的准备遗漏即收口；不新增运行owner，不据执行计数声明官方全图一致。

## 无子层 composition 的透视回绘决定（2026-10-16）

真实288的286无parent、成员或依赖，默认copybackground=true，两项已有effect；init显式写perspective=true，并创建不继承effect的空composition。固定官方2.8.0.42自有1210×786正控制使用非零z、Y倾角、反色和不对称标记。false为矩形，true为四角各自可定位的梯形，内部横线随输出倾斜；这反证屏幕对齐projective pullback，支持平面采集后透视回绘的有界profile。正式测量与身份由本批证据持有，不能把同一对照外推成员、native-camera、passthrough或官方cursor parity。

**职责。** 原CameraFrame只对无parent/成员/依赖、非passthrough且copybackground=true的composition接纳现有静态/typed perspective；其他utility沿旧策略。原imageModelMatrix分别按平面/输出策略求同一world frame的card，原CaptureGeometry以captureMVP决定affine sourceUV和source extent，以outputMVP决定最终quad。平面路径复用同一矩阵，不增普通帧解析/缓存；capture仍经原readable pass、pool、prepared graph和唯一compositor。cursor/effect投影使用最终输出MVP；不增加homography算法或第二相机。group的viewport源/1:1回绘不借此改变，未知形态的setter保持原bundle拒绝。

**失败与验收。** 数值/资源安全沿原最小拒绝，普通effect失败沿原局部回退；创建/回滚与退休仍属DynamicLayerRuntime。先验false/true的四角、非零深度倾角、内部标记及同MVP cursor反投影；保fullscreen、group、project/依赖、native相机和健康peer反例，再做Debug及实际288控制/画面和独立原包。若原包仍无可见收益则不保留空创建基础设施，按队列重选；此设计不预报修复、性能或完整parity。

**native-world 后继资格（2026-10-16）。** childless `composelayer_depthtest` 尚未开放。两轮官方自有 native-camera 载体均缺背景网格与独立 world 四角正控，不能裁定采集或深度语义；到此停止载体重试，不增加矩阵或产品别名。现有仿射 sourceUV 不能直接外推 native 透视；后继须先建立可见源与独立几何，再区分采集和最终遮挡。深度仍应由原 StaticModelFrame 管共享 lease/首次 clear，source/graph 保色彩路径，最终 quad 才只读 scene depth；真实首 pass 依赖主源，保留 captured-main consumer 准入，不转无源绘制。未改变产品能力，资格及失败输入见限量证据 `../../../../.artifacts/scene-evidence/runs/native-world-capture-qualification-20261016/manifest.json`。

### 有序 framebuffer source Program 后继（2026-10-19）

目标是让 native 场景中的合法平面先读取当时背景、执行作者材质及效果，再受场景遮挡回绘；不据此承诺盒体透明或全屏背景反馈同因。采用完整 source Program，避免为 stock shader 另造投影公式或固定源码形状证明。旧官方载体仍为 STOP_UNKNOWN，不借其失败裁定算法；合法作者输入与独立实现的可证伪像素门支持本片设计。

原 AssetCatalog 保真 model 的 passthrough 声明，DescriptorBuilder 沿唯一已加载 model/material、明确 framebuffer 输入及 render state 提名 typed source role；不按资源名选算法。首片限 native、无成员、无依赖、无实例覆盖的平面，显式 translucent/nocull、depthtest enabled、depthwrite disabled；其余形态保持局部拒绝。Program 的完整 variant envelope、输入绑定及颜色合同必须准备成功，未知 shader 不借 flags 替换成固定采样。改名、局部变量改名和等价表达式仍交同一 compiler 执行。

复用原 source-material compiler/variants/PassEncoder，新增 captured-main 输入域；原 GraphExecutor 的 base command 可消费该已准备材质，而不是固定 affine source copy。准备阶段只预留原 full-frame pair、冻结当帧矩阵及同帧主源身份，不编码或发布。真正编码仍在原 utility 的作者顺序截点；不得挪到层循环前的 asset source-material 批处理，也不复用历史 framebuffer。作者顶点/片段 Program 决定本地源像素，canonical world/model 与现 target-pixel ABI 决定输入坐标；effects 继续消费同一 graph 源，普通 affine 路径不增加像素除法或额外 PSO。

终端只读深度沿原 StaticModelFrame 的共享 acquisition、首次 clear、pending deferral 和 completion；reverse-depth MVP/compare 同模型，禁止 source/effect 中途清场景 depth 或写 depth。深度绑定显式到唯一 compositor 的最终 draw，不能提前绑定后又被普通 encoder() 解除；不新增 plan、pool、Candidate、历史或输出 owner。isolated 模型仍保既有边界，不虚称全部模型已参与共享遮挡。失败先于本层编码拒绝，普通视觉失败局部保原回退，身份/陈旧资源沿现失败合同；pending 只复用现 mandatory-depth 延后提交，不能呈现漏层帧。

共享 depth 的 optional consumer 资格先于 graph admission：先按原可见、normalMatrix 与完整材质输入资格尝试 model/particle mandatory depth，再由同一 StaticModelFrame 申请共享 lease；普通 isolated part 失败不抹掉已有效的 shared depth。仅当前可见且取得资格的新 role 可创建 candidate，其他本帧 preparation 输入排除，不创建 bundle/candidate/ledger；busyOtherFrame 仍整帧取消并等待。late named model 输入未齐时只排除本帧新 consumer，保原晚绑定模型链；同一 StaticModelFrame 按 layer/原 part index 持有唯一 depth 结果（含失败），独立于可清空/晚刷新的 draw payload，ordered 提前退出也不丢后层 reservation，particle lease 亦复用。通过资格后 binding 再失效属于身份/生命周期错误，沿原失败合同拒绝，禁止晚 continue 留下 allocationCommitted ledger 或无深度回绘。

验收先用自有非对称网格、native transform parent、source Program 和健康后层证明采集/投影；前置 MDL 半遮挡证明终端只读 depth，含无先行 writer、resize/取消/陈旧资源及 pending 恢复。普通 source/组合反例保持。随后固定非零 typed audio、相机与提示属性，要求真实目标有可归因新增像素及独立样本画面保持；只有执行计数或目标被遮挡不能关闭 N03。source/几何/遮挡正控任一失败即停并重评，不调作者位置、亮度或 cull 追图；无实际收益撤回产品准入。

### 普通原生图层的材质深度状态（2026-10-19）

目标是让已准备的普通世界平面服从作者显式 depthtest/depthwrite/cull，而非永远覆盖先画模型。单个 opaque MDL 的自有正控已排除 near-coincident：普通 image 的 enabled/disabled 两 arm 均穿透，材质声明、前模型、后图外侧及 screen overlay 均已资格。本片先恢复明确状态，不从资源名推断，更不把 text 或省略 state 的默认政策猜成 enabled。

准备阶段沿原 AssetCatalog→Descriptor 保真材料，并用既有 MaterialRenderState 归一有限政策；当前 builtin quad 消费资格与材质/几何来源必须明确，未知 Program/多pass/几何产品沿原局部处理。已有 solid 材料漏收须在原catalog修，不能在renderer按stock路径补状态。状态进入原prepared层/模板投影，普通帧不解析字符串或扫描材料。原生相机及当帧perspective决定消费；明确disabled、screen-space与不相关二维路径保持原合成。

纯 typed `SceneMaterialRenderState` DTO 与查询归 Runtime/Frame，作者字符串解析仅留 Compilation/Material 的唯一 extension；Rendering 只消费准备值，拆分后退休该混合 namespace 的旧依赖 todo，不扩大公共算法边界。

StaticModelFrame继续独占共享depth申请、首次clear、busy/完成与取消。普通平面和原framebuffer-source复用这份能力；需求在原帧准入中取得资格，mandatory model/particle优先，不能晚分配后遗留graph ledger或呈现漏层pending帧。普通不可用只降级相应层，陈旧/错pass等安全错误拒绝最小不安全单元。模型隔离政策不在本片顺带改动，不以shared source成功代表所有模型互遮。

唯一compositor的terminal draw消费准备好的读/写/剔除政策与同模型reverse-depth，source/effect仍用原空间/颜色ABI；不能把全屏copy或中间graph pass写入scene depth。ImagePipeline复用有限PSO/DepthStencil状态，不造第二depth pool/输出owner，没需求不新增常驻准备。原source只读/nocull约束保持，普通输出不因绑定能力存在而擅改作者状态。

最低验收为单前模型遮后image、disabled和外侧/overlay正反控；再以有无depthwrite区分后继更远层、背向normal/nocull区分剔除，含无先行模型、alpha覆盖、改名/等价字段别名、wrong-pass/取消/busy及健康后层。Debug后核真实333的可归因遮挡贡献和独立原包；text/省略默认仅在固定官方自有正控合格后另行接入。公共显式状态已由自有App像素红绿验收；真实333未有可归因改善，停止向text/省略默认或terminal replay扩策略，转查模型实例隔离。独立358构图保持、sun收益未证；[有界后验](../../history/ordinary-native-image-depth-2026-10-19.md)保各身份及失败。整盒遮挡、背景与性能仍须各自实证，不按截图调位置、材质/透明度或全局depth。

## 无子层透明源与 named 输入的职责修正（2026-10-18）

`copybackground=false` 的无子层 composition 使用透明源；另一个 sampler 的 named provider 不构成复制 enclosing 背景的请求。现 SourceRoute 因声明依赖而改走 readable-main，真实393随后把背景与文字一起变形。修正只在原 SourceRoute 分离这两种输入职责；named 解析、准入、预留、publication 与 epoch 仍归现有 dependency/graph owner。有子层且带外部依赖的未知形态不借此开放，唯一身份、父子索引和无环检查保持。

无成员 composition 的 source UV 与最终 quad 归原 CaptureGeometry，沿当前 layer/parent model；有成员的 viewport source 才按 1:1 回绘。preflight 与 encode 共用同一几何，不据纹理是否隔离选择坐标。空透明源有合法 authored size 时取本地 extent；缺尺寸保原回退，非法尺寸局部拒绝。复制背景的无成员 affine quad 则沿各自局部 X/Y 投影边长分配像素，不能用屏幕 AABB 将旋转变成输入轴交换；原 enclosing 背景采样、最终变换、pool/graph 与失败职责保持，projective quad、有成员组、fullscreen/project、材质源及 named 坐标不借此扩张。沿唯一尺寸 owner 验改名、旋转/镜像/父scale、非法数、非affine/有成员反例、原374831与独立真实样本。清晰度、遮罩与停止/取消保持，不从分配尺寸认性能收益。

隐藏 composition 仍可作为可见 consumer 的已准入 graph provider，不能只按最终显隐决定其输入是否存在。组源预留从 `makeScenePass` 移至原 frame preflight，在既有 dependency demand 得出后、graph preparation 前执行一次；原 GroupRuntime 仅对被 demand 的**无成员、不复制背景的不可变透明源**补预留，其他隐藏组保原降级。显隐仍只决定 authored 最终合成，不新增 demand/资源/输出 owner，不使隐藏 provider 出现在主画面。pin、清空、取消与 GPU completion 沿原生命周期。

验收包含改名后的透明源与 named sampler 共存、true/缺省的主源反例（childless passthrough 的 false 优先修正见下节）、畸形成员拒绝、可见 consumer→隐藏透明 composition→named provider 的完整供图，以及未被 demand 的隐藏源不分配。真实335须保圆形文字/封面并恢复连续地面，独立347的缺省背景复制及网格保持。未取得这些结果前不记反馈关闭；不改四角、相机、作者位置或隐藏内容补画面。已取得源/几何修正的有界结果，实际图、分阶段门及仍开放文字精确对齐归[后验](../../capabilities/runtime-evidence-current.md#composition-local-source-20261018)。两自有完整hidden App夹具未通过前置资格，保原失败、不算该链通过；已有demand/清空/pin门成立。该修正不是性能验收，也不扩有成员隐藏 provider、passthrough 或全部 composition parity。

## 有成员组合的局部源边界资格（2026-10-18）

U08 当前原包的无效果 composition 声明了本地尺寸，其蓝图与嵌套 passthrough 音频均有实际 Program/GPU/末合成，蓝图却越出独立白框。白框是普通素材，不能据此创建裁切合同；需要裁决的是非 passthrough composition 自身的源边界。现 planner 对无 effect 组只保顺序，SourceRoute 又排除 passthrough 后代，两个边界分别处理。旧 viewport/1:1 路径是当前实现，不据其存在否定 authored-local 需求，也不在行为未证时直接替换。

首轮自有无音频四卡已通过独立 R×S 几何、内点和 anchor 正控，证明无 effect、copybackground=false 正交父组的本地水平可见边界；旋转外点位于屏幕 AABB 内却回到背景，排除单纯 AABB 截断。serialized passthrough=true 两卡同样有界，其区别仍 UNKNOWN。此结果不证明内部 RT、裁剪时机、上下界或 effect extent。后继纵向/嵌套 r3 使用同一冻结输入、仅更换运输调用入口，健康四卡通过；100×100 外组经恒等变换、无效果的 200×200 passthrough 中间组，仍按外组局部纵界约束。此前漏 parent 与运输失败分别保留，不能写成官方嵌套不支持。没有健康正控即停止，不转到真实壁纸调位置；本节不声明产品实现或 U08 修复。限定证据暂存 `.artifacts/tmp/composition-local-bounds-20261018/official/`，纵向资格见 `.artifacts/tmp/composition-local-bounds-vertical-r3-20261018/official/qualification.json`；失败载体另存对应 vertical/r2 任务目录。

在取得相应父本地边界资格的 profile 内，项目优先选择局部 source 实现；这是本项目的架构选择，不是官方内部 RT 推断。现 SourceRoute/RuntimePlanner 准备唯一 source-space 与逻辑 extent，source 需求独立于有无 effect；原 GroupFrameRuntime、CaptureGeometry 和 pool 在同一事务内完成成员采集、graph 输入与最终一次 world 输出。取消该 profile 的无效果直通与 viewport/1:1 权威，避免把已应用 camera 的像素再变换；嵌套 passthrough 只能在证明其 source/顺序后沿原成员链接入。只在最终输出按框裁图不满足 effect、named 或 history 的源语义，不作为局部源方案的替代。

首批范围由行为证据决定，不按样本、效果名或路径选择。必须保持父子顺序、变换、透明/PMA 与 HDR/SDR、背景选择、named publication、history 的 identity/generation、resize 在飞 pin、取消/隐藏及局部失败能力；缺失源空间事实局部拒绝，不能新增相机、graph、资源账本或 compositor。验收先比较有界源/非目标透传的实际像素和资源退出，再验 U08 真实蓝图/音频、变体及未参与修法的组景；无可归因画面收益即重新选题，不把 GPU 完成或更小分配写成正确性/性能收益。

### 无子层 passthrough 的背景选择修正（2026-10-18）

U15 原包的空组合显式 copybackground=false、passthrough=true，现 SourceRoute 却因 passthrough 走 readable-main，scroll 把背景小片重新滚动；仅关闭该层时竖块退出且时钟/频谱保持。固定官方2.8.0.42自有四卡已证：同一保alpha的RGB反色效果中，copy=false两卡均透明，copy=true两卡均读取背景，与 passthrough 值无关；两个原图及固定ROI健康，R1/R2夹具变换/构造语法失败另保留，不转记产品失败。

只在现 SourceRoute 去掉 childless 的 passthrough 背景推断，并允许这类空组进入既有透明 source、extent、pool/pin及唯一 compositor；有子层 passthrough、perspective、依赖/身份安全和其他utility保持现边界。true/缺省仍读取背景，named sampler不决定主源；初始隐藏但已准备的新空组保留原capture计划，后续typed显隐及hidden供图不丢source身份。验收使用真实SourceRoute四flag/改名依赖与结构反例、实际Planner到共享透明输入/生命周期、一次隔离Debug构建、原U15 HDR/resize后无竖块且邻层保持，以及独立真实背景复制样本。无新增算法/资源owner；官方资格不外推成员、变换或全场景parity。若上述首错或健康门被反证，撤回本次route delta，不用改作者位置/增益补画面。

### 局部 source 实施决定

首个交付闭环是正交、非 passthrough、透明背景且有成员的 composition：让 authored 宽高成为成员源边界，无效果与有图效果共用同一源。完整矩形是本项目对 authored 二维画布的实施策略，官方直接证明 X/Y 父局部可见边界及恒等、无效果中间组；真实 childless passthrough 的效果源也由 copybackground 决定：true/缺省读取 enclosing，false 复用共享透明空源；有子层 passthrough 仍不扩张，不据边界推断 effect 内部实现。native/perspective 成员及需要重新投影背景的嵌套非 passthrough 背景组保留现行可执行 profile，不能在迁移中丢掉原内容；其余成员准入不因本决定自动扩大。

既有 SourceRoute 在 descriptor/topology revision 决定局部源资格、成员与唯一顺序；每帧仅对这些 root 用当前 world/camera 生成一次 typed 源几何，含逻辑 extent、attachment extent 与 global-clip→source-clip 映射。复用现可逆矩阵工具，不新增 camera、pointer 或 world owner。GroupFrameRuntime 在同一 pool/epoch 内按现 poolLimit 比例政策预留 attachment（普通尺寸精确，超上限画布保逻辑 extent 并等比限物理尺寸），把不可变映射交给 MainPass；MainPass 不推导作者几何。唯一 MainPassRenderer 在高级 blend/geometry prepare 之前映射 raster MVP，终端材质重放显式消费同一 raster 事实；named 发布到独立目标时保留原世界放置，不套当前 attachment 变换。cursor、effect projection、lighting/fog 始终用原 world MVP。

CaptureGeometry 的源采样使用 enclosing attachment 的相同映射与实际 extent；局部组输入是完整本地 source，最终用 root world MVP 输出一次。合法无效果组也保留预留、clear、成员抑制与 root 输出，但直接复用原 compositor 的无 graph draw，不伪造 Program。source 几何不可逆、尺寸非法或分配失败时沿现 degraded group 拒绝整组最小不安全单元，禁止成员回漏到 parent。原 copy-background viewport 组、空透明组及 childless capture 的已证路径保持各自语义，替换 profile 退出旧 no-effect 直通/viewport 输出。

验收必须实际执行 planner→membership、局部 source 的像素越界排除及最终单次输出，覆盖平移/旋转/非均匀 scale、改名换序、健康邻层、嵌套不同尺寸、效果采集、高级混合、终端重放、HDR/SDR、resize/在飞 pin 与取消。passthrough 后代由相应源/顺序资格决定：childless copybackground=true/缺省继续读取 enclosing pass；false沿现空源 root，不因 passthrough 另建源 owner；不把删除类型 guard 当成全部 passthrough 语义已实现。真实 U08 与未参与修法的组景需要观察可见收益，CPU/GPU/内存收益另测，不能由目标尺寸推算。

## 现有资源合同与历史依据

### 无作者根效果的背景局部源（2026-10-22，设计与有界实施）

新增378的五个无效果组合根省略copybackground，现解析为true，却只保次序、未裁切宽于父画布的子图。官方2.8.42自有双子重叠板的独立普通/效果/半透明与四角正控合格后，无效果普通组在X/Y越界点均保背景，内部半透明RGB符合背景顺序合成；省略背景字段不取消局部边界。非线性根效果的RGB仍不能区分完整分组算法，故本片只推广**正交、非passthrough、有成员且根authored effects为空**的背景组；子图自己的效果不移除。含隐藏根效果、未知passthrough、透视及原未准入成员/依赖保持原路径；不以当前效果显隐切换源空间。

原SourceRoute/Planner准备唯一成员与localSource资格，退出该profile旧skippedNoEffect直通。原SourceGeometry保存已算root世界MVP；原GroupRuntime在首次实际写入、根的作者顺序截点初始化背景。使用实际enclosing pass的raster映射和现CaptureGeometryResolver取得背景UV，经renderer注入的同一captureSource/imagePipeline填入局部目标，随后成员load保留背景。透明局部组仍clear，其他背景组仍原viewport blit；预留先于graph preparation且不提前采背景。root alpha由既有最终compositor消费，补齐无offscreen直绘遗漏的finalCompositeAlpha，背景采样使用中性PMA输入，不重复调制。不新增shader、相机、pool、graph或输出owner。

尺寸/映射非法、源目标身份/格式错误、采集或分配失败沿原degraded group抑制成员，pin/epoch、取消与GPU completion保持。验收为同输入修前/修后局部背景标记、X/Y裁切、半透明重叠/健康后层及改名/变换反例，最近资源/顺序/显隐门、Debug构建、378实际画面及独立原包。背景边界外采样、全部alpha/变换/嵌套、HDR官方数值与带根效果算法不据此宣称一致；无可归因改善或出现旧路径回归即撤新资格，不改作者位置或颜色补图。

<a id="ordinary-root-effect-local-boundary"></a>
### 普通组合根效果与局部边界（2026-10-23，有界实施）

344的原包声明5120×1440正交画布，组合669有普通子层及一个关闭的根效果，旧`skippedNoEffect`排序让90→627越出父画布、形成左上白卡。稳定作者B姿态的三臂已完成归因；未改变作者位置或隐藏白卡。既有官方双子板中，根效果开启卡110和无效果卡210均有独立正控、两帧X/Y越界回背景的证据；声明效果关闭板未运行，非线性RGB顺序、官方内部extent/UV仍未知。

公共语义是：**合法正交组合的父局部输出边界不因根效果的声明或显隐而消失**。原SourceRoute现为获准普通二维成员固定局部source政策，使用原Planner、SourceGeometry、GroupRuntime、Program及唯一compositor；效果准备仍独立准入，关闭时由原source路径回绘。退出该profile旧skippedNoEffect/viewport选择，不按当帧visible切换空间，不增scissor、mask或资源/输出owner。原透视、native-camera、模型/粒子成员、依赖与嵌套背景限制不扩张；已准入passthrough保持原分支。

组合范围须准确披露：普通背景根声明效果后，其无根效果的嵌套passthrough后代现在可沿同一外组成为结构成员；这与已准入的透明源+根效果、背景源+无根效果组合一致。嵌套层自身不取得第二source/output；嵌套passthrough自带根效果仍拒，普通嵌套背景组仍保原viewport限制。此闭包通过实际Planner事实验收，不能仅由outer准入推断内部执行。

局部source是本项目已有独立实现，不据边界证据声称官方内部RT一致。实际App的96×80非居中源，以UV .25/.75红绿标记及水平镜像Program验证局部采样，X/Y外点回背景、健康后层保持；旧版红、候选OFF/ON绿并核同帧GPU完成。源/Planner变体与相邻拒例、344原包默认/B、独立322静音A/B及用户最新普通App反馈的有界结果归[后验](../../history/composition-root-effect-local-source-2026-10-23.md)。声明OFF官方板未补跑，既有半透明/背景顺序证据仅继承，不把新opaque镜像门外推全部alpha、LOD/边缘采样、像素步长或非线性RGB；input Resolution改变属于本次范围，不能声称所有根效果parity。

原源预留、pin/epoch、取消/GPU退出、最小失败和degraded组成员抑制保持。无实际收益、相邻画面反证或source/身份首错时撤回新资格并重评；不改作者位置/增益追图。322白频谱/白环受作者音频门控制，静音与非零PCM分开记录，手部与子系统预算余项不因本批关闭；没有性能收益结论。

### 有成员 passthrough 的局部效果（2026-10-22，设计与有界实施）

370/377的组合根有作者宽高和子图，却因config.passthrough在SourceRoute首拒，根的pixelate/VHS/pulse未进入Program。组合定义的明确画布尺寸、成员合为单纹理及原背景采样坐标分工，支持沿已有局部source实施；不需要恢复官方内部FBO。RGBA正控只证通道响应；空间板的两轮STOP分别保留小角标颜色及参考X边混色失败，未读语义，不能据此声称官方物理extent、精确grid或overflow一致。

本片只新增**顶层passthrough、有普通成员且无utility后代、既有正交二维profile**，让根效果消费作者逻辑宽高的局部输入；嵌套passthrough保持结构成员身份，不新建source/output；旧非passthrough背景+根效果的viewport路径本片不迁移。仍由SourceRoute准备唯一成员/源政策，SourceGeometry与GroupRuntime在原顺序截点采实际enclosing背景和成员，原Program/graph消费同一attachment，最后按root world MVP合成一次。物理附件extent及UV按本项目实际资源发布，不借TV容器头伪造尺寸；无效果与隐藏效果保持同一源边界，不能按显隐改空间。新增profile继续拒绝透视、模型/粒子成员、外部依赖和utility后代（含结构passthrough），保旧嵌套组路径，不新增shader、clock、资源或输出owner。

隐藏根效果的准备沿原DirectBoolEffectVisibility/ExecutionCapabilityAdmission复用同一合法source route，仅扩上述组合的现有typed显隐链；必须取得实际Program，不能以source-only计划代替。非法几何、分配、准备及取消仍由原最小组失败/抑制成员和pin/epoch退出，不让子层回漏。验收先跑改名/换序/变换与不应准入的邻例，再验实际背景+成员+根空间效果、初始隐藏及往返显隐、健康邻层和取消/resize；同构建运行370/377与独立组景，确认原缺失效果产生可归因画面收益。全部alpha/tint、任意溢出/嵌套、HDR官方数值和整景parity保持未验；若实际结果无收益或回归则撤回新profile并重排，不调作者位置、尺寸或增益补画面。

资源/source 窄片已经独立实施：compositionGroup key/分配一致，exact extent，source 在 graph preparation 前预留并 pin，准备、写入、采样是同一有效 generation 的纹理。GPU completion/cancel 释放、resize 在飞占用、无历史的透明初始化和同帧保留由[架构§3.3](../../architecture/runtime-architecture.md#33-保留事务安全不扩大视觉失败半径)接管。本次改变输入内容与顺序，不重建资源系统。旧反例、首次错源与实际 App 修复见[执行记录](../../history/d1-composition-source-implementation-2026-10-02.md)。

[首轮成员实验](../../history/d1-composition-membership-attempt-2026-10-02.md)未获得有效效果启闭正控制，不能裁决成员；本轮有效控制补上这一缺口。[经审查的中性合同](../../history/d1-composition-neutral-contract-2026-10-02.md)提供字段存在性、source/target 与生命周期候选，不作为官方语义或代码来源。官方[RGB composition 说明](https://docs.wallpaperengine.io/en/scene/rgb/introduction.html#extra-notes-on-composition-layers)支持采集先前场景内容的方向，具体父子/flag由本轮自有黑盒区分。

## 尚未证明与退役

本轮官方直接覆盖单个 parent child、根前后数组位置、一个非 child 前后移动、copybackground 三态和空 child 组；没有证明所有 transform/clip、passthrough、alpha 混合或动态 topology 与官方等价。used-input 完整哈希属于运行后 guest 收据，不能回填成事前全输入冻结；Scene/fragment 和窗口身份在实际捕获时登记。私有资源仅由官方客户端正常加载，不读取实现表达；自写片段与项目算法独立。

有界实现、真实正反例及独审完成后，将稳定输入/顺序/失败合同交回架构，结果只保存在运行证据。剩余模式保留明确 unknown 和可证伪后继，不能从局部 PASS 宣称 Scene 全兼容，也不能永久保留已证错误的 prefix/末后代 route。
