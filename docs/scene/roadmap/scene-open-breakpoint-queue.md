# Scene 当前开放问题

<!-- document-role: active-plan -->

本页维护未闭问题、输入定位和下一步。按画面合成/正常播放、可证性能成本、属性接线、工具资格排序。架构归[当前主链](../architecture/runtime-architecture.md)，领域合同归[能力入口](../capabilities/README.md)，冻结身份与覆盖范围归[运行证据](../capabilities/runtime-evidence-current.md)。

2026-11-07 按已知问题定位与新增目录复测：176个已知作者定位和115个新增目录不重合；291个定位中2项已移除、2项仍缺输入，287个合法输入均已实际运行。该R0中285项取得Ready、终端PNG与GPU排空；3808922316准备超时、3834591400首帧失败均同输入串行复现，后续单项修复不倒改此分母。当前统计与非默认条件结果归[运行证据](../capabilities/runtime-evidence-current.md#coverage)，原始CHECK不作缺陷数。先处理本表前列的实际播放阻断与活动局部拒绝；结构健康不关闭原视觉反馈。

后续先保证每个样本主画面、主要图层和基本交互正常，再追细节、算法参数及尚无画面归因的边界。330628当帧读回、330头部reference-track及380创建/预热单位仍保具体停止线，不重复原失败方法；338211已有有界供值停止线；下一项先核286多renderer整体误拒绝的真实输出职责。已闭项退出本表，结果只归[运行证据](../capabilities/runtime-evidence-current.md)。没有可行动首错就重排，不继续堆测量。2026-11-07补报13个作者定位与图1–5；8项曾进入本轮默认App运行、5项仅有本轮census，均不由rawPASS或静态粗筛否定动态、点击、音频反馈。新增反馈不倒改上段冻结复测分母。原图完整3024×1964及逐项对账保于`.artifacts/scene-user-feedback-20261107/`。

样本ID和layer仅用于复现，不选择算法。隐藏、空媒体、延迟和未触发分支不直接判缺图；Program准入、实际绑定、CPU求值、GPU执行、局部tail消费和最终像素贡献分别记录，未知保持未知。

<a id="implementation-gaps"></a>
## 本轮实测的通用断点

| 定位 | 当前事实与下一步 |
|---|---|
| 多renderer整体拒绝 · 2868108515 | 46个活动粒子层中544470/591910共用sprite+ropetrail+spritetrail定义，在单项renderer选择前因集合count=3整体nil，实际只加载44层。缺省length=1不是首错；后续资源及各renderer像素贡献未知。沿原prepared模拟状态与renderer消费者明确多输出职责，不重复模拟、仅选一种冒充完整结果或扩大名称许可。 |
| REFRACT材质准备拒绝 · 新增四作者 | 3580724885、3590684440、3602874264、3663269553共14个启动有效可见粒子层实际`refractionUnsupported:unsupportedMaterialProfile`，主景及终端仍成立。先在原材质准备核具体未消费输入与最小失败范围；这是共同拒绝边界，尚非同一根因或14个独立缺陷，不借下方官方normal单位未知归因，也不忽略材质输入换取加载数字。 |
| 超长预热 · 3808922316 | 原project/pkg/tree不变，同4秒观察/90秒准备额度仍超时；短栈处于粒子预热，同App关闭首事实观测仍超时。原隐藏星场1333 starttime=100000按当前固定步请求约600万更新，是源码工作量而非完成计数。固定官方默认控制最终出图、精确完成及90秒资格未定，见[有界研究](../capabilities/runtime-evidence-current.md#coverage)。预算与隐藏状态沿[原预热合同](../capabilities/particle-component-coverage.md#prewarm-work)，不能直接跳过。先保完整状态，待原创建需求/单位/等价优化的可判证据；当前转先修基础画面，不原样延时、加预算或凭cache末日志改代码。 |
| 通道与操作推导 | 完整向量输入已退次数许可，实际颜色采样/显隐见[运行证据](../capabilities/runtime-evidence-current.md#whole-vector-color-input)。剩余alpha-only/packed、有序signal和无typed颜色兼容仍有有界source事实。终端storage可继承未读data-FB声明，未注解资产raw意图未证，不能由output=data推输入解码。沿原冷准备汇合component/资源角色，保data、独立alpha与mixed-role反例，不追加效果名单。 |
| source fallback 的路径/摘要许可 | `SceneAuthoredXRayPlanner+StockIdentity`仍以固定路径、UI字段及两个摘要profile授source-passthrough豁免；`SceneImageLayerDrawRequest`仍以Pulse/Blur/Waterwaves路径、pass/slot/combo形状判source coverage。两者影响源图降级，不是通用Program执行许可，尚无当前作者被误挡的画面归因。沿原prepared Program的coverage、颜色边界及发布依赖事实替换并退役旧许可；核等价资源改名、真实alpha改变、PMA、mask与named发布反例，不能直接通放base source冒充效果结果。 |
| material default动画入口 | 该存储位执行语义尚无作者/官方正例，不能仅凭AssetCatalog未parse认定冻结缺陷。先取合法default动画行为正控，再由原descriptor冷准备汇合material/instance有效值与definition-only pass identity，不让TargetCompiler重解资源或另建owner。 |
| Bool回调的剩余阶段边界 | 分离属性/媒体前缀、同C entry中due timer到真实值回调，以及直接值入口的隐式init到update已沿[原owner](../capabilities/scenescript-api-coverage.md#boolean-callback-order)交接；无update保真实事件setter。实际App与native范围归运行证据，不外推为所有阶段已隔离。cursor/media等事件自身先读getter仍未取得pending-init供货；Puppet/video-ended混合返回、嵌套回调完整次序及真实video EOF身份仍未闭。沿实际调用与typed消费者核首错，不重放旧setter或添加持久显隐副本；尚无这些剩余边界的精确作者活动资格。 |
| named供货 · 2972071249/313e9→234 | 234 hidden/childless，两effect visible=true且有真实两节点authored图；inactive来自layer-hidden route，313前九段健康、e9=`dependency-stage-reference-unavailable`。常量effect载体的普通蓝/红/绿颜色正控已成立；随后一场省略/true/false配置的三个消费者都绿，控未分，见[官方prefix资格](../capabilities/runtime-evidence-current.md#prefix-source-qualification)。不解默认、背景截点、epoch或实际sampler/provider身份，不能raw source冒充效果结果；本次按停止线收口，不原样延时或续跑矩阵。 |
| named 冷准入与来源边界 | 潜在lower背景已退出冷候选的执行准入，typed实例资产覆盖的实际合成与拒绝边界见[运行证据](../capabilities/runtime-evidence-current.md#coverage)；未授无注解资产用途或精确作者缺图。剩余cold candidate仍用原始renderOrder，实际执行已消费utility展开顺序与trigger；background consumer仍排graph provider，同trigger后普通provider→utility组合未接入。沿已选Program、真实来源位置与原资源消费者补齐，不追加member、效果或路径许可；任意utility/模型/局部画布组合仍需资格。 |
| Childless utility 的显式背景来源 | 当前Project false取main、Composition false取isolated空源，仅为SourceRoute/原生结构事实。[正控](../capabilities/runtime-evidence-current.md#childless-source-qualification)停在PNG与native采集不一致，三场及Mac未跑，stock清alpha也未证copyflag映射。先恢复同窗采集，再核真实source/最终取样，不由旧路由或单路图预选修复。 |
| 模型动态准备的剩余组合 | 父组热显隐、冷 Bool 与外部 Script setter 的原 source/Program/tintback 已沿[原模型消费者](../capabilities/advanced-object-coverage.md#model-subtree-raster)取得有界实际资格；初始关闭 effect、任意 utility/材质组合仍未由此覆盖。外部非 Bool 材质 writer 的 layer-access 需求仍未汇合到原 Document/RuntimeInput/Launch 的全场景准备判定，这只是静态来源边界，尚无作者首错资格。沿实际需求补原 owner，保 child false、局部坏模型、source/Program 与同 key 事务；不重开已退单 leaf 例外、另建 ready 状态或把冷颜色链授为深度/官方像素。 |
| REFRACT 官方采样与单位 | 当前粒子映射保本引擎 canonical 全局 screen-UV amount，宽窄画布与物理 extent 有内部资格。官方 top-level 控制已取得真实色带背景与省略/null 卡片的调制边界，合法 normal 仍只有匀色卡片，采样位移正控未知；composition 内隐藏背景 scope 也未资格。恢复研究需能定位的实际 normal 位移与背景消费者，不能由现有 J 数学推为官方像素一致。 |
| framebuffer需求记账 · 3292370168/505 | 505 dormant/currentHidden、无named target且无当帧capture plan；SceneDrawing先将全部未requested的framebuffer source加入unavailable并记encoded=false，实际EffectExecution已过滤无target plan，505没有执行捕获。当前CHECK来自无需求被记失败；沿原drawing owner区分排除与真实preflight/capture失败，保visible depth拒绝、活动需求和hidden named，不以总数抵消失败。不能将该记账修正称GPU或可见画面恢复。 |
| Child控制点绑定与声明位义 | 无CP读取的leaf走[原事件消费者](../capabilities/particle-component-coverage.md#child-declaration-options)；非零未解释声明flags遇到真实reader或子树时仍只拒对应template，不回退默认CP。官方CP分支白/蓝目标重合，parent-particle供给与declaration位义未资格，不能套root General world位或由无CP等价宣全部flags无效。沿原typed需求和绑定源补消费者，保父/健康peer与现有static raw-parent copy；不新增flags组合许可。 |
| Rope A2C可见轨迹 · 3807668787/958 | 原作者实际A2C/GPU与弱端点信号保持，完整轨迹未资格。新的[同批生产诊断](../capabilities/runtime-evidence-current.md#rope-958-sampling)已区分几何转发、横向UV、少量lower-mip与原mask/alpha；该受控batch首次实证纵向域压缩及末端截短，符合原Plan先index-q、后位置去重保first的链。有序重复出生producer尚未资格；只有输入可核时才用显式uvsmoothing=false和opaque纵向色带区分UV归属，省略默认独立保unknown；否则重排其他可行动项。不预选last-q、去重后全域归一或弧长。官方正确端域/重复点曲线及precoverage仍未知；不重跑旧相位alpha/LOD矩阵或按名称增MSAA/resolve，不授作者轨迹恢复。 |
| 满容量的自然调度 | 官方maxcount2、两个life4初始fillers、rate.4周期发射在T8.2只有约6.5出生；容量64对照约5/7.5。无上限本身也延后，原5/7.5判别前提失败，周期quota按请求或接纳计费尚未知。沿原Simulator核满槽期间fraction/窗口与死亡释放顺序；不以这个未知拒绝普通或capped发射，不增加调度owner。 |
| 显式命令与自然相位 | 官方rate.4、on10/gap10、cap2，约t1 emit1后可见出生1/5/7.5；约t6 emit1后为2.5/5/6。显式在自然额度耗尽后仍贡献，但早期命令会改变后续自然出生相位，不能宣称与调度完全独立。沿原exact-n命令/EmitterState核交互，不挂共用appendBirth扣自然quota，不把未知变成整组play/pause/stop的禁令。 |
| 普通粒子材质语义 | AssetGraph仅核genericparticle basename；no-depth普通路径的额外CUTOUT/LIGHTING/UNKNOWN combo和user texture/value没有通用shader消费者，固定sceneParticleFrag仍输出原纹理×tint。RenderStateCompiler已将普通材质输入与几何许可分离，但其profile仍用于camera选择及当前depth/A2C输入限制，不能代替材质编译。沿原材质准备/实际shader或typed操作接入，区分已消费与未实现输入；不能以效果名或源码形状白名单扩张许可，也不能盲目忽略未消费输入。当前额外材质输入为代码链事实，尚无逐作者画面资格。 |
| Child parent 控制点映射的消费诊断 | `rawParentControlPointOverride` 的 hasKnownConsumer 只看单CP字段，未纳入 Between/Maintain 的 start/end；rawflags0、parent字段及零位置可能被记为 ignoredUnused。该形状的 parent 位置语义尚未资格，不能凭旧 guard 增加整 child 拒绝，也不能把该诊断当成新组件已正确消费父映射。定位 copy bit、原始/解析位置与实际消费者，补有位移父点及不复制邻例后决定最小修正。 |
| 粒子 Remap、约束与子束链 | 三个作者root的operator10仍`prepared-plan-unavailable`，时间→sine→opacity缺真实消费者。独立静态范围与晚EventDeath输入已有有界资格，但sine首对落未预登记模型，依原停止条件收口；实际读数与旧N/W/D限制归[运行证据](../capabilities/runtime-evidence-current.md)，当前实现归[组件合同](../capabilities/particle-component-coverage.md#operators)。保留未知数学与作者缺省参数，后续用可区分证据沿原owner补消费者，不按效果/输入输出/flags组合追加许可。beam child另缺transform/CP及initial-value供货；3527426897的map-sequence另需flags/空间输出资格。 |
| 粒子球体与画布碰撞 | 静态Sphere消费者见[组件合同](../capabilities/particle-component-coverage.md#sphere-collision)；首次接触顺序、精确轨迹/size裕量、CP锁定位及缺省数值仍未资格，不能由3773747576/183的CP333或CP1同位推断开关规则。Bounds的3780119725/891 operator2仍`unknown-operator-kind`，只有name/id；缺实际wallpaper边界经当前变换到粒子空间的供货和缺省响应，不能用drawable或发射盒代替。沿原碰撞/空间/Simulator补消费者，不把正常batch/GPU或退出授为完整碰撞能力。 |
| 双控制点的弧向与周期序列 | Between仍未消费arc参数；三个闪电root为arcamount.1/flags23，未请求0x20，现partial也不包含这些arc字段。官方默认/存储已取证，本次有界静态仍无Position消费者；原报告尺寸缺省更正为.9，截断伪码不作全函数排除。新零噪声Q仅到资格场：PNG有预览而原生观察不一致，按首错停止，未授40中心/运动、未生成A或推弧启用/关闭。输入、原PNG、完整guest新文件及独审保于`.artifacts/scene-arc-qualification-20261107/evidence.zip`；采集先合格才重启语义研究，否则换项，不续旧两粒/弱端点矩阵。mask32旧周期输入显示新窗回首端，落实仍须原emitter状态/跨窗出生定义；不用particleID猜多emitter/显式交错。自然新生与存量边界已测，CP同cadence显式新生/后续Maintain顺序仍待有界对照，不加整链许可。 |
| 发射器Directions数值域 | `SceneParticleEmitter.hasBoundedDirectionsAndSign`仍把有限Directions限制在abs≤1e6；原Sphere/Box消费及最终新生Float检查没有同名语义上限。应分别核零半径、有效大值、实际乘积溢出和健康peer后，清理无用的幅度许可。现有作者运行证据未见该幅度门独立活动拒绝，不以它解释其他birth失败。准备期另有静态反例：Directions=(1e200,1e200,0)、固定radius=1e-200时，二维`pow(radius,2)`下溢0；若直接放域会出生在origin，最终Float有限检查抓不到错误零。先沿原径向准备/抽样明确数值语义，不再堆幅度名单或为极罕见输入新增运行防线。 |
| 无实际屏准备间的更新与终态回流 | 用户贴图已退出actual非空误拒绝，同Session保存结果并由新View采用，实际PNG空窗与原生prime/reset边界见[当前证据](../capabilities/runtime-evidence-current.md#display-user-textures)。其余visibility/direct-model混绑仍依真实消费者；沿原请求核其余标量/暂停更新与无新输出后的stop终态回流，不造幽灵屏或重发launched，范围见[显示空窗状态](#display-live-state)。 |

<a id="display-live-state"></a>
### 显示空窗状态

新增/混合职责归[显示配置和屏实例](../architecture/runtime-architecture.md#display-reconciliation)，用户纹理请求归[原Session资源合同](../architecture/runtime-architecture.md#display-user-texture-updates)。已验证用户贴图与[raw空解析控制边界](../capabilities/runtime-evidence-current.md#display-no-output-control)由运行证据维护；后者未取得有效图片、自然拓扑或Client/UI资格，不据此新增故障协议。下一步须先取得这些实际消费/原请求回流证据，再决定修法；其余actual暂空的属性/暂停回执仍待核。不用合成消费者、保非目标窗、重发launched或另造显示许可解决，保 `.stopped` 用户command合同。Host/client同值过滤保持，无新事件时晚到ID自动恢复、真实多屏/物理backing/HDR、严格RNG、App媒体decoded连续与最大帧隙仍各有证明上限。

## 内容与观测资格

| 定位 | 当前事实与下一步 |
|---|---|
| 音频composition · 3039882306/772 | 本轮受控PCM/静音均有772的typed左右32数组消费及所选material→group→tail绘制；旧无consumer边界已退出，但两侧均绘制，不能归因PCM激活。精确音频幅度与目标ROI贡献未资格，隐藏1084的fallback另记；详细资格见[当前复测](../capabilities/runtime-evidence-current.md#coverage)。 |
| 粒子短窗触发 · 2866723317 | 当前四秒selected186/GPU完成，无particle draw；334/400/210/106均未进入自然constructor，accepted与construction-rejected均0。前三层确有选频非零供货，但bounds后幂响应与积分没有逐步读值，峰值非零不能断言应出生。106的rate.2及instance.rate.2使10秒预热加4秒live仅约.56个请求，尚不足整数出生；无delay，不改公式或盲延等待。后续按真实root及足够正输入核首次出生/实际batch，不能把该短窗归为构造拒绝。 |
| effect执行阶段读口 · 3292370168/239e0 | 当前parent named来源已接通；frame0/1在视频首帧pending时局部未供，frame10/11实际执行并GPU完成，selected23有151→e0→e1→main/seal全链。现reader将不同帧同identity的失败/成功聚为矛盾并报unexpected recovery，整样本CHECK4还含505。沿原execution/frame读口区分时间阶段、当前selected结果与持续失败，保原失败事实及同帧真实冲突；不能为消报告改渲染或将短窗恢复授视频更新/全像素。 |
| 必需binding · 3556263543 | 五个文字psyhue e0真实采样slot2缺authored/default binding而持续旁路，e1与终端健康。缺省语义仍未知；自有官方对照修正基底后，完整无损采集仍未资格，未跑改名/slot变体。原失败与归档限制保于`.artifacts/scene-sampler-absence-20261107/evidence.zip`；重新研究先资格完整采集与正控，不续旧矩阵，不随意填纹理或把copy算原effect执行。 |
| shader分支与活动局部降级 | 2887099508/257e0的g_Point1 attachment、2932157836/299e1 node1/slot0 binding及2857410102/91e3仍无对应活动资格。本轮3042492564受控media后339/e3实际`library-compilation`、363/e0为`variant-envelope-texture-binding`，输入链已到，不能再统称never-visible；精确shader/绑定首错与ROI分开定位，保局部fallback，不拿终端健康授效果正确。 |
| 作者脚本与VM边界 | 本轮默认目标中34个样本有typed Script事件；当前逐subject索引为归档的`task/r0-script-event-index.json`，不能按异常类批量归作者或引擎。2890473419四个origin脚本仅声明shadowLayer即写visible、2982559622把Vec3返回给alpha为已证输入问题。3504669359的166/720/718/716缺prepared Puppet metadata：clip700在bounds前的双曲线与后方MDMP字段关联，七骨TRS恒定，现无morph消费者；不能将扩Reader或补metadata称作眼睛动作恢复。372/373/336的init读取`thisLayer.position.y`，公开属性为origin，三层默认hidden；官方runtime别名未知，不造默认值。其余沿原log逐target核上下文、producer、API及回调次序，不以新计数和旧635全量作趋势比较。 |
| 缺输入 · 3736952187、3763323436 | project.json不存在，未启动App；补合法输入后再跑，不作引擎失败。 |
| named demand · 2069136288、3395777145、3829467967 | 默认未达静态planned的目标没有当前active consumer；本轮3557068717/420 authored=false、3476868923/533 effect inactive亦分开保留。先取得真实writer/活动需求，不要求默认帧执行所有潜在capture，也不以此解释主景像素。 |
| activation读口 · 3639999624/84e1 | 实际`activation-passthrough:inactive-dependency-preproof-mismatch`被reader判malformed/missing；作者visible=false，有GPU完成及后续e2消费。对齐原producer/reader分类并保inactive资格，不能改渲染消报告；此问题与hidden provider的exact身份命名空间分开。 |
| 粒子预热CP · 3799613625/321 | 失败归static child0/system1 red_fire emitter0预热，非root。当前开启cursortrail并供inside pointer后，同consumer live出生及所选child Sprite/main/GPU已成立，见[运行证据](../capabilities/runtime-evidence-current.md#coverage)；冷缺历史pointer不授持续播放失败，不删除CP有效性边界。只有outside后PNG，逐像素轨迹与完整交互仍未资格；不据旧预热诊断继续扩修。 |
| 来源阶段读口 | 本轮source-not-ready首断点均在Ready前，后继同layer恢复或1045转hidden的实际资格归[当前复测](../capabilities/runtime-evidence-current.md#coverage)。沿原reader保时间/需求边界与原失败，不把不同阶段聚为持续错误；同layer成功仍不证明同slot或逐像素恢复。 |
| 纹理关联与最终贡献 | 全部声明有索引，但ordinary/geometry/particle部分实际draw未携带asset provenance，graph/provider引用也有未闭关联。不得解析Swift描述字符串猜identity；沿已存在Candidate/Resource carrier补最小typed映射。本轮3788897599的291/259 composition行`rendererKind=unknown`，定位`SceneParticleMetalPipeline+Frame`的可选debug字段及原component observation供货；复测先核现有按需观测输入，不由路径猜种类，也不将此元数据缺口判为绘制失败。单帧bind/GPU/tail不证明全部实例或最终可见像素，动态输入、材质与render-target的未观测阶段仍保unknown。 |
| 着色器类型回归预期 | `test_scene_shader_global_scope.test_float2_arithmetic_does_not_cross_unproven_expression_boundaries` 的 user-call/normalize 仍期待不补`.xy`，与现有typed复合求值后窄化合同冲突；同输入旧/新产品都补`.xy`。其余9方法通过、GPU独立项1skip；按真实类型与编译/像素修订这两条旧预期，不能撤回合法转换迎合测试。 |
| 粒子回归夹具体量 | `script/tests/test_scene_particle_simulator.py`仍超过1000行，内嵌Swift准备/运行与多类组件断言共用大夹具；当前未达到自有代码行数与职责要求。按真实组件输入、共享准备与行为断言梳理现有fixture职责，保同一生产实现及独立失败反例，不靠wrapper、源码搬迁或复制模拟算法凑行数。 |
| 全仓链接门 · 非Scene文档 | `docs/architecture/steam-workshop-acquisition-contract.md`与`docs/history/cross-topic/steamkit-migration-completed-2026-10-16.md`指向`SteamWorkshopLegacyAcquisitionRetirement.swift`的源码链接解析失败；`docs/history/cross-topic/code-slimming-r1-r26-2026-11-01.md`指向`main-window-playlists-redesign.md#93-正式个人设置导入导出兼容`的锚点解析失败。相关正文均与HEAD一致；沿各自文档owner修正真实链接。该全仓门当前失败，本批Scene文档的局部链接及角色/导航另核。 |
| 连续PNG读口 · 3577990983片头 | 7秒/.6秒捕获实际写出4PNG，另6项superseded、1项teardown，整次保CHECK。等待lane时pending request仍挂逐帧composition，CB地址可复用；两次actual capture有多个request/CB候选，现reader以len1拒绝。当前按encoded行→同CB completed记录及同帧uniform有界核对；自动读口应沿原reader保编码/事件顺序或原DEBUG传frame/stream/generation，不能取首个request匹配，导出背压原因另核。 |
| 条件/周期分支 | 3768303048本轮manual day/night的122/109及夜雪59有效显隐已成立，day sticky unavailable59对应隐藏，不能判活动粒子失败；真实时钟与pointer未资格。3042492564原树click父链隐藏，派生media条件已供货且有click后738绘制，仍缺首次出生回执/无click对照，不授点击因果。3764725758/3830665420第二轮仍未知，长窗不代完整事件。 |

## 需定向扩域的能力入口

下列是尚无充分当前输入资格的边界，不是默认短窗已证缺图；具体合同仍由能力文档拥有。

| 定位 | 下一步 |
|---|---|
| hidden/forward父graph named输出 | 可见、已可满足的普通image graph-final已有transform children时可复用原graph发布；hidden FX父仍在image来源谓词保leaf范围，forward可见来源仍受原执行期限准入。hidden claim/execute/named-only消费者已存在，需独立父子/多reader及生命周期对照；forward沿实际source独立性与作者位main期限核，不能由新visible正例裸开utility/Puppet或用raw替身。当前最新静态parent筛选无精确作者命中，保能力边界，不造默认缺图归因。 |
| composition · 2731896598 | childless透视与三维angles组合需真实几何/Camera/回绘资格，不以false-only代作者输入。 |
| source material · 3616476797/113、3679907516/71/74/83、3141464346 | 逐pass核source-only state/lookup/活动purpose；314重点232/277/321/386/416/420/481/719，不从VERSION2或translucent推通用接口。 |
| static model / resolved render state | 任意shader、多pass与更广blend/depth/cull须原binding compiler和fullscreen/output用途资格；保深度、淡出与PMA。 |
| Puppet · 3577990983、3822822401、3779107475 | auxiliary/reference、非中性通道、dense state1及多contributor姿态按真实reference/attachment坐标基资格，Reader识别不等于evaluator执行。 |
| point volume · 3047405322、3437487219、3477054430 | 需实际volume consumer；现有spot plan和point表面光照不能代验。 |
| Script动态特殊资源与typed callback | 特殊Puppet/composition创建字段、3028048463的531.alpha空数组/506.origin、3603711180跨callback Sound分别核prepared catalog及实际producer，不造空实例或无差别容错。 |
| Script粒子instance数值字段 | `SceneQuickJSParticleInstanceHost`仅注册`instance.alpha`并封闭对象；公开的`rate`/`count`尚无native getter/setter，严格module中的赋值会失败。粒子自身`instanceoverride.rate`脚本已有ScalarProgram→typed snapshot→模拟时钟消费者，不能据此授跨层host API。沿原typed target、journal与事务接入实际读写，不能开放成不生效的普通JS属性；当前是代码边界，未授逐作者画面影响。 |
| sampler宏声明接口 | canonical g_TextureN声明配宏采样read已准备通过；自有slot0将声明改为宏别名时，raw SchemaSeed未展开，unconditionalSamplers报authoredSamplerSchemaInvalid。当前没有作者缺图资格。沿原冷预处理/接口事实统一Schema，保真实slot/metadata，不新增别名许可表或忽略用途；后续资源目的仍需独立资格。 |
| effect显隐错型 | Color key同时绑定effect.visible会保原重建要求；layer visibility已有的忽略规则不能代此入口。尚无作者运行资格。需按真实Bool fallback、启动投影、准备状态与合法Color热更核对，不能直接扩大ignored集合或绕开原事务；数值effectConstant的固定fallback职责不代显隐资格。 |
| RopeTrail其余renderer字段 | 公共Worldspace与整数subdivision已沿原消费者接通，资格见[组件合同](../capabilities/particle-component-coverage.md#rope-trail-world-subdivision)。显式非正length仍拒绝；固定客户端静态最小值钳制尚无作者/运行资格，不能据此授完整history单位。非screen朝向、动画、size fading及UV字段各需实际消费证据，不以原flags误拒保留它们的整renderer许可。 |
| 粒子其他资格 | CP/child空间、Mirror、nested/event、HSV缺省（3585542943/253/257、3761159935/453/457）、Vortex flags2及absolute color字段各用出生/轨迹输入；normalizedColor不是absolute color。 |
| dormant视频与输出扩域 | hidden仍被named采样与实际source停止分开；物理HDR/EDR、lighting/receiver、文字backgroundbrightness和HDR8bit裁剪分别资格。 |

<a id="user-feedback"></a>
## 用户反馈与定向视觉资格

以下位置均不能由默认短窗截图裁决；复核时固定属性、声源、pointer、时间/相位、viewport 与 App。终端存在、主画面成立和具体 ROI 正确是不同资格，先找真实 consumer 与首个不同 stage。

### 基础画面与基本交互优先

| 输入 | 精确待核位置 |
|---|---|
| 3306942838 · 图2 | 头部运动时偏移过大，原静态粗筛未识别。head24/body28为独立root，只有particle642引用body attachment；body clip1606实际未准备、bone52物理降级是有界线索，非根因结论。先核同相位头/体pose与最终geometry，不降低运动幅度拟合截图或套329的重复名修法。 |
| 3306282639 · 图3 | 人物周身文字外圈出现多余放射线，R0原图亦可见。compose3192/2921的circular_text slot1实际消费hidden text2917的named供货；同尺寸graph→named走原CB全域blit，不能凭纹理token或代次差判转色/陈旧。两次有界调试均未取得作者当帧像素，后次在Swift表达式读取失败，未进入GPU读回；独立RGBA/BGRA读回正控通过不代作者资格。保`.artifacts/scene-circular-text-20261107/`，暂转其他基础画面项；重启须能取得同帧实际边缘RGBA、slot/variant/uniform与采样结果，再区分边缘延伸/上游生成，当前不改clamp、padding、PMA或作者参数。 |
| 3382111183 /3383210272 | 338211六个活动beam emitter（115/178/335/173/167/170）的exponent100被≤16计划门拒绝；但现有真实频谱供货最高.96，即使删门，按当前bounds.5…1/公式响应也≤.92^100≈.0002392，从空累计首粒约千秒，短窗不可见。仅删门的候选设计/测试未运行、未入产品，保`.artifacts/scene-particle-audio-exponent-20261108/`。先停在实际particle聚合/单位及供值域，重启须有可区分的官方数值/同声源consumer或用户目标ROI证据；不重跑同PCM，不改gain/bounds/pow或强注入1凑图。[官方AudioBuffers](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/AudioBuffers.html)的可超1属Script域，不直接授particle公式。338321的323/124/369/391四emitter已消费非零16-band，零出生仍须核实际门槛/birth/color，不重判音频断线或以此关闭完整FX/光照反馈。 |
| 3617449489 | 音频环缺失，本轮仅census。先定位环的真实layer/Program/Script与音频供值、活动状态和绘制，不因声明音频能力就转为频率调参。 |
| 2814167871 /2835398595 | 随音频眼睛闪动不明显，两项本轮仅census。先分别核眼部目标与实际band读值、回调和像素响应，再判作者频段/门槛；“链路正常可能是频率”保用户假设，不预设为已连通或引擎错误。 |
| 新增粗筛 · 3557068717及条件项 | 355默认主景近黑仅见小亮点，原named CHECK没有活动需求，不能用它解释像素；3455121165/3453730450的时钟、3618302662构图、3657295614人物、3360178853牙口与2868108515条纹均待viewport/时相/显隐/source资格。新增113对图像粗筛不授完整视觉通过；329挂点已闭，结果归运行证据，不从其他rawPASS关闭反馈。 |
| 2887099508 · 图5 | 旧矩形取景/人物越右与本次线索相关，新增开场运镜使整个画布背景移动、最初数秒下半区黑纹从左往右横扫、右侧文字点击均无响应，按三个subject分别定位。先核camera/画布/source的同帧变换及真实点击命中/回调；旧LLDB未arm的失败方法不原样重跑，不猜UV、padding或general.zoom，不因主图供货正常关闭。 |
| 2999907577 | 旧终端主体完整，大片背景灰与有效默认tint相符；876e6流体的执行不授像素贡献。后续只在需要时用现有selector7→8(None)定位白弧/流体贡献，不按preview判缺纹理；3003318777的后启动阶段已由[运行证据](../capabilities/runtime-evidence-current.md#coverage)资格，不再沿旧四秒失焦实施修复。 |
| 3436945972 /3463406101 /3443450456 | 分别偏暗、暗绿配色及灰白底黑字；同亮度、遮罩、配色/时段与音频输入后定位writer，不从preview归tone-map/blend。3382111183另并入本次主要效果可见性优先项。 |
| 3498814983 /3605722997 /3827673174 | 前后两项当前目录已移除，保原反馈为输入不可用；360572当前可运行。头脸取景仍须固定横屏camera/cover/平移与作者画布，portrait preview不能证明投影错误。 |
| 3504669359 /3767460992 | 350默认四秒旧强白圆未重现，固定圆核及当前材质/终端边界见[运行证据](../capabilities/runtime-evidence-current.md#coverage)；不据此修产品，媒体/光效全相位、发布copy物理边及selected pose仍未知。376中央白X已有当前作者fallback供货；真实媒体事件、封面替换及显隐仍需资格，不能从预览差异判纹理漏载。 |
| 2982559622 | 默认短窗主画面成立；103.alpha返回Vec3、effect.visible组合wrapper分别核作者字段与准入；同输入完整视觉仍待资格。 |
| 3034166869 /3223543799 | 其余 effect、媒体与完整画面；常开音条与条件隐藏分开，不凭短窗结构状态实施。 |
| 3141464346 | Puppet 同 phase 位置、右下音频环与 shader 链；188/332蒸汽不能代音频环。 |
| 2957870426 | PCM/静音已供，目标audio消费者仍未资格。中央竖光、birth Color Random/colorn与ROI须真实出生及颜色单位，不凭bus非零关闭；3383210272并入本次主要效果可见性优先项。 |
| 3586308277 | SDR原色已恢复；待核原动画扫描时间、方向与可见度，官方像素未获资格。 |
| 3351179520 | 文字环位置/尺度/旋转；需同帧 slot1、MVP、g_Time 与可归属 glyph，而非强制各TRS同心同速。 |

### 其他待核

| 输入 | 精确待核位置 |
|---|---|
| 3022080536 | 移动烟雾偏红、颜色继承/ColorChange 与显式 audio child；先确定颜色单位。 |
| 2919854127 /2927205881 | 蓝环可见性与曲线右短段，同声源 band 与实际触发条件。 |
| 3577990983 | 远距离 hover 提前放大；真实 pointer 与作者半径/投影。 |
| 2887542690 | 图框内音频 ROI、黑遮挡/字体及片区布局，先取得可重复输入。 |
| 2134765860 | Night选项字符串4已实际供货；右黑矩形仍需区分作者画布、媒体与独立mask，不由属性接纳判像素归属。 |
| 3768903841 | 横向云片/烟花色彩；238.angles 的 screen localStorage 身份异常另查 Script 入口，不推断为粒子根因。 |
| 3226487183 | 1028手部同 phase 形变与 source/reference/effect 链。 |
| 3809618616 /3791967416 | 前者布局裁切/音频，后者局部合成及眼部完整周期。 |
| 3789316755 /3211615441 | 频谱形状/幅度/全柱活动；321另保图片切换、首焦点、持续按住与多步跟随。 |
| 3788467391 | 漩涡方向、速度、形态与长预热的可比相位。 |
| 1315486372 /3769761761 | 光线宽软/渐隐/水波位置与头发上方斜带；376的`.01`属于instanceoverride，需完整可归属光束贡献。 |
| 3113287126 | 小提琴粒子方向与密度，固定发射/运动相位。 |
| 3437487219 | Earth亮侧/云层光色；Cloud Chroma MR/specular/pigment及coverage，另分闪烁与collision。 |
| 3743305891 | 十字流星尺寸，分别核父world与子local scale，不预设重复乘。 |
| 3768229922 /3770444459 | 溅水滴黑色、主体/眼部完整过渡需实际source/同相位合成ROI；不把片头静帧当持续缺图。 |
| 3768724269 /3287715210 | 光束范围/根部/右上渐变；眼周亮度/渐变与横移细竖纹分别定位。 |
| 3750813609 /3363252053 | 相机过强/纵向反转的同输入体验；375另核时钟颜色、雨量与雷电。 |
| 3662790108 | 球体/曲率、点击；effect517/pass0 `[P1] Data`读取p1_longNode须先区分作者数据和实际消费。 |
| 3589454154 /3747492842 | Bloom/细线微颗粒/轮廓；闪烁/光束位置/crop/文字构图。 |
| 3248220186 /3337494481 | 前者运动/密度/亮度；后者跨面文字、扁盒/粉顶、遮挡与solid亮度。 |
| 2938612768 /2775915974 /3712499998 | 时钟后期裁切、顶部灰边、重复文字/样式，分别确认真实图层和布局。 |
| 3477054430 | 显示完整性、月亮/球体/文字、低频与猫受光，逐ROI定位。 |
| 3764725758 /3549827466 /3581882134 | 左斜光/眼睛漂动、缺光ROI与暖亮/冷暗来源。 |
| 3723344874 /3793998447 /3792249095 | 人物后烟雾涡动、音频属性差异、外圈样式及内外位置。 |
| 3042492564 /2932157836 /3299228616 | 光束/右裁切/blur/布局/媒体交互、精确spin及媒体仲裁、hover水波强度。 |
| 3233141951 | 脸/龙/小人/刀轨迹与双色音频；403请求513的Bool seed类型另核。 |
| 3807668787 /3420215721 /2684431262 | 958 A2C/pointer轨迹、中央环亮度、发光与整体合成。 |
| 3470948192 /3264246690 /2131872317 | 水滴亮边/拖尾与反射、人物边缘AA/警戒带运动、蓝烟花上升/逐子出生空间。 |
| 3769688830 /3780119725 /3769364482 | 玩偶往返与黄球UV Spin、人物地面/摩托中层pointer及光照、Shake Breathing与发光突现。 |
| 3219398263 /2932631210 | 漩涡方向与背景，分别固定ROI，不能共改符号。 |
| 3028090166 /2419444134 /3113554287 /2304304373 | 光束、白点密度、顿挫、雾气叠加；低优先，先补当前输入。 |

<a id="performance"></a>
## 性能反馈：待同条件测量

| 输入 | 当前待测问题 |
|---|---|
| 密集预热 · 3337494481 | 完整300秒输入在普通Debug/可选组件观测下90秒未首帧；现有优化诊断配置同输入完成，单次particle-prewarm约59.15秒、Ready约64.27秒。短CPU样本落在真实预热、Turbulence及可选first-fact观测哈希；先分离诊断成本与正常播放配置，再核可比瓶颈，不删内容、提预算或把跨配置结果算优化。 |
| 整体CPU高温 / GPU满载 | 先固定设备、构建、输出与真实workload，联合归因，不以历史温度或局部代码变化代替当前测量。 |
| 3476868923 /3507496797 /3662790108 | 重型内容冷准备与首帧成本；同输入区分model、shader、资源及首Surface装配，不延时限或减少内容冒充优化。 |
| 3805547608 /3372715909 | 视频越播越卡与热切后AV对象驻留，需当前普通播放、精确source退出和可比时序。 |
| 3749463715 /3420215721 | 观感低帧率、实际提交/呈现率与drop原因分别核对，不从旧计数判断当前预算。 |
| 3471294034 | 需同输入、同优化配置测实际呈现与瓶颈；本轮并行诊断短窗不作60 FPS或能耗资格。 |
| 轻重切换 / 多Surface | 同PID资源驻留与第二屏准备成本；先找真实持有owner和重复工作，不预建共享cache。 |

测量与退出规则只归[性能方法](performance-convergence-card.md)，本表不沿用旧实验数值或认领收益。

<a id="properties"></a>
## 属性与工具资格

本轮证据位于当前worktree的`.artifacts/scene-problem-retest-20261107/`；旧635集合只用于差集和原条件对账，来源由本轮selection/input-drift收据维护。当前746个可解析输入不等于全库已播放验收，目标外目录及未资格的属性、周期、ROI仍保未知。

| 定位 | 下一步 |
|---|---|
| 属性面板 | 总打开/编辑延迟、长Combo完整显示、系统键盘路径与更多locale需实际可达控件。保原始key/value/条件，翻译只改展示；完整段落、只读说明和reset入口不能因优化丢失。 |
| effect 显隐 / history | 关闭后保history再重新启用的首帧与实际输入待核；沿原activation/previous-current，不增另一history owner。 |
| text size | VM catalog size与排版logical extent是不同事实；setter后可见时机与padding/装饰需真实行为，不另建排版owner。 |
| 预处理成员 · 2819633264 | 未知成员按0的当前实现与横/竖分辨率、宏成员/空白等价行为需区分输入。 |
| console.warn · 3605722997 | 先确认实际 callee/堆栈与可达调用，再判断API缺口。 |
| 3028048463/531.alpha、3280903509/225.alpha | 空数组与Vec3返回scalar分别核作者配置、时序与字段归属；不静默强转。 |
| presented / performance 记录 | 实际GPU完成与系统呈现分开；沿present callback和stream身份资格普通窗口/多Surface，终端PNG不代呈现率。 |
| 失败收据的可选路径 | 3808922316等未Ready时，collector仍写未创建的preview_log及runtime_evidence占位`-`，使现有promoter拒整份报告。本轮原报告原字节保留，保留投影显式记缺失项后只复制实际文件；Debug独立dylib也未被benchmark staging复制，原stub会在dyld退出；本批用明确单executable的Debug候选运行，非同身份旧Debug重试。后续在原collector/staging入口准确承接真实载荷与可选路径，不造空日志、改原失败或删除真正captured文件的完整性检查。 |
| 自有ABI与验证载体职责 | `SceneQuickJS.c`仍2801行，是自有适配而非第三方源码；既有domain/owner、输入和typed调用职责须收敛，不能以第三方豁免、搬行或新增wrapper宣称达标。`test_scene_generic_shader_program_artifact.py`、`test_scene_dependency_graph_output_runtime.py`及`test_scene_particle_simulator.py`也仍超1000行，混有内嵌Swift壳、legacy与跨主题probe。沿真实结果生产职责退重复和失效部分，保ABI、原字节和像素oracle；当前CodeHealth只覆盖Swift，不能授C/Python全语言合规。局部门及时输出编译失败，不等待长suite结束。 |
| capture · 3766415113 | 普通capture需实际窗口frame/时机资格；本轮Metal终端PNG不覆盖普通截图入口。 |
| 自有9000000015 | 90/91/92健康peer须有真实texture source及可区分ROI，先资格夹具，不能借主文字/clone输出代peer。 |

属性接口归[输入与属性](../capabilities/runtime-input-property-coverage.md)，工具按当前实现与输入资格复现。更新队列时只删已解决的具体子问题；没有当前复现则标待核，不复述旧实验流水或维持旧 verdict。
