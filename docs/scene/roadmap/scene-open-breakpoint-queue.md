# Scene 当前开放问题

<!-- document-role: active-plan -->

本页维护未闭问题、输入定位和下一步。按画面合成/正常播放、可证性能成本、属性接线、工具资格排序。架构归[当前主链](../architecture/runtime-architecture.md)，领域合同归[能力入口](../capabilities/README.md)，冻结身份与覆盖范围归[运行证据](../capabilities/runtime-evidence-current.md)。

2026-11-07 按已知问题定位与新增目录复测：176个已知作者定位和115个新增目录不重合；291个定位中2项已移除、2项仍缺输入，287个合法输入均已实际运行。该R0中285项取得Ready、终端PNG与GPU排空。3808922316后续见下表；3834591400的同输入首帧失败[已恢复](../capabilities/runtime-evidence-current.md#forward-visible-program-input)。历史分母保持，原始CHECK不作当前缺陷数。当前统计与非默认条件结果归[运行证据](../capabilities/runtime-evidence-current.md#coverage)。

先处理有当前证据的播放阻断、画面和基本交互。选题时简看现有画面和[运行证据](../capabilities/runtime-evidence-current.md)，及时清除已修或已证为作者行为的条目。旧反馈若看不出具体问题，等新的可重复输入或明确差异再排，不延长试验或推测改法。仍开放的项目沿各行已有停止线。2026-11-07补报13个作者定位与图1–5；8项曾进入默认App运行，5项仅有census。原图及逐项对账保于`.artifacts/scene-user-feedback-20261107/`。

样本ID和layer仅用于复现，不选择算法。隐藏、空媒体、延迟和未触发分支不直接判缺图；Program准入、实际绑定、CPU求值、GPU执行、局部tail消费和最终像素贡献分别记录，未知保持未知。

<a id="implementation-gaps"></a>
## 本轮实测的通用断点

| 定位 | 当前事实与下一步 |
|---|---|
| REFRACT直接光照 · 3590684440四层 | 392/526/809/830 的同帧两盏现代点灯已供，hidden534 不计活动分母；无模型 caster 需求不授官方无阴影。四层实际为正交 worldSpace SpriteTrail，shader eye/right 未资格；view 逆原点受裁剪深度影响，几何 across 也不等于已证 source right，故停止放行与 shader 迁移。Mirage 仅作线索；先取得可区分的官方 host/normal 基与直接光、shadow 供货，沿原 LightSnapshot/材质消费者接入，不重调旧四区灯/法线。已闭 ambient/CUTOUT 归[原证据](../capabilities/runtime-evidence-current.md#particle-cutout-coverage)，本次候选和停止线在 `.artifacts/scene-particle-lighting-next-20261108/`。 |
| 启动仍慢 · 3808922316 | 原90秒超时已退出；[当前同配置原包](../capabilities/runtime-evidence-current.md#particle-alpha-fade-borrow)再缩短首屏，剩余主要是预热。后续须有可明显减少完整工作且保状态的新实测热点，或可区分活动创建/时长的新官版证据。沿[预热合同](../capabilities/particle-component-coverage.md#prewarm-work)，不重做已退出的数组访问、不原样重跑、加预算或跳隐藏。 |
| 通道与操作推导 | 完整向量输入已退次数许可，实际颜色采样/显隐见[运行证据](../capabilities/runtime-evidence-current.md#whole-vector-color-input)。剩余alpha-only/packed、有序signal和无typed颜色兼容仍有有界source事实。终端storage可继承未读data-FB声明，未注解资产raw意图未证，不能由output=data推输入解码。沿原冷准备汇合component/资源角色，保data、独立alpha与mixed-role反例，不追加效果名单。 |
| source fallback 的路径/摘要许可 | XRay固定路径/UI/摘要与Masks的Pulse/Blur/Waterwaves路径门仍有真实降级消费者；尚无当前作者被误挡的画面归因。现分支只接unclaimed且无frame target，不能借已认领Program许可；颜色来源/PMA不证明alpha与空间覆盖，归一blur即反例。本次停止实施；若续查只先资格Masks真实unclaimed的等价改名画面及source-coverage阻断，再决定原冷owner能否供完整事实并退旧门，XRay不并批。不造新coverage系统、通放base或补路径名单。正反例与停止线在`.artifacts/scene-source-coverage-20261108/`。 |
| material default动画入口 | 该存储位执行语义尚无作者/官方正例，不能仅凭AssetCatalog未parse认定冻结缺陷。先取合法default动画行为正控，再由原descriptor冷准备汇合material/instance有效值与definition-only pass identity，不让TargetCompiler重解资源或另建owner。 |
| Bool回调的剩余阶段边界 | 分离属性/媒体前缀、同C entry中due timer到真实值回调，以及直接值入口的隐式init到update已沿[原owner](../capabilities/scenescript-api-coverage.md#boolean-callback-order)交接；无update保真实事件setter。实际App与native范围归运行证据，不外推为所有阶段已隔离。cursor/media等事件自身先读getter仍未取得pending-init供货；Puppet/video-ended混合返回、嵌套回调完整次序及真实video EOF身份仍未闭。沿实际调用与typed消费者核首错，不重放旧setter或添加持久显隐副本；尚无这些剩余边界的精确作者活动资格。 |
| named供货 · 2972071249/313e9→234 | 234 hidden/childless，两effect visible=true且有真实两节点authored图；inactive来自layer-hidden route，313前九段健康、e9=`dependency-stage-reference-unavailable`。常量effect载体的普通蓝/红/绿颜色正控已成立；随后一场省略/true/false配置的三个消费者都绿，控未分，见[官方prefix资格](../capabilities/runtime-evidence-current.md#prefix-source-qualification)。不解默认、背景截点、epoch或实际sampler/provider身份，不能raw source冒充效果结果；本次按停止线收口，不原样延时或续跑矩阵。 |
| named 冷准入与来源边界 | cold candidate仍用原始renderOrder，实际执行用utility展开顺序/trigger，background consumer仍排graph provider，同trigger普通provider→utility组合未接。限定R0分组活动边均已有真实named消费，尚无可判误拒绝/非等价fallback；重启须具体活动slot/order/trigger→source/ROI首错，不造夹具补丁或无差别重跑，297与childless原STOP不变。薄范围与缺项在`.artifacts/scene-named-candidate-next-20261109/`；沿原冷准备与资源消费者接入，不加member/路径许可。 |
| Childless utility 的显式背景来源 | 当前Project false取main、Composition false取isolated空源，仅为SourceRoute/原生结构事实。[正控](../capabilities/runtime-evidence-current.md#childless-source-qualification)停在PNG与native采集不一致，三场及Mac未跑，stock清alpha也未证copyflag映射。先恢复同窗采集，再核真实source/最终取样，不由旧路由或单路图预选修复。 |
| 模型动态准备的剩余组合 | 父组热显隐、冷 Bool 与外部 Script setter 的原 source/Program/tintback 已沿[原模型消费者](../capabilities/advanced-object-coverage.md#model-subtree-raster)取得有界实际资格；初始关闭 effect、任意 utility/材质组合仍未由此覆盖。外部非 Bool 材质 writer 的 layer-access 需求仍未汇合到原 Document/RuntimeInput/Launch 的全场景准备判定，这只是静态来源边界，尚无作者首错资格。沿实际需求补原 owner，保 child false、局部坏模型、source/Program 与同 key 事务；不重开已退单 leaf 例外、另建 ready 状态或把冷颜色链授为深度/官方像素。 |
| REFRACT 官方采样与单位 | 当前粒子映射保本引擎 canonical 全局 screen-UV amount，宽窄画布与物理 extent 有内部资格。官方 top-level 控制已取得真实色带背景与省略/null 卡片的调制边界，合法 normal 仍只有匀色卡片，采样位移正控未知；composition 内隐藏背景 scope 也未资格。恢复研究需能定位的实际 normal 位移与背景消费者，不能由现有 J 数学推为官方像素一致。 |
| Child控制点绑定与声明位义 | 无CP读取的leaf走[原事件消费者](../capabilities/particle-component-coverage.md#child-declaration-options)；非零未解释声明flags遇到真实reader或子树时仍只拒对应template，不回退默认CP。官方CP分支白/蓝目标重合，parent-particle供给与declaration位义未资格，不能套root General world位或由无CP等价宣全部flags无效。沿原typed需求和绑定源补消费者，保父/健康peer与现有static raw-parent copy；不新增flags组合许可。 |
| Rope A2C可见轨迹 · 3807668787/958 | 原作者实际A2C/GPU与弱端点信号保持，完整轨迹未资格。新的[同批生产诊断](../capabilities/runtime-evidence-current.md#rope-958-sampling)已区分几何转发、横向UV、少量lower-mip与原mask/alpha；该受控batch首次实证纵向域压缩及末端截短，符合原Plan先index-q、后位置去重保first的链。有序重复出生producer尚未资格；只有输入可核时才用显式uvsmoothing=false和opaque纵向色带区分UV归属，省略默认独立保unknown；否则重排其他可行动项。不预选last-q、去重后全域归一或弧长。官方正确端域/重复点曲线及precoverage仍未知；不重跑旧相位alpha/LOD矩阵或按名称增MSAA/resolve，不授作者轨迹恢复。 |
| 满容量的自然调度 | 官方maxcount2、两个life4初始fillers、rate.4周期发射在T8.2只有约6.5出生；容量64对照约5/7.5。无上限本身也延后，原5/7.5判别前提失败，周期quota按请求或接纳计费尚未知。沿原Simulator核满槽期间fraction/窗口与死亡释放顺序；不以这个未知拒绝普通或capped发射，不增加调度owner。 |
| 显式命令与自然相位 | 官方rate.4、on10/gap10、cap2，约t1 emit1后可见出生1/5/7.5；约t6 emit1后为2.5/5/6。显式在自然额度耗尽后仍贡献，但早期命令会改变后续自然出生相位，不能宣称与调度完全独立。沿原exact-n命令/EmitterState核交互，不挂共用appendBirth扣自然quota，不把未知变成整组play/pause/stop的禁令。 |
| 普通粒子材质语义 | AssetGraph仅核genericparticle basename；no-depth普通路径的额外CUTOUT/LIGHTING/UNKNOWN combo和user texture/value没有通用shader消费者，固定sceneParticleFrag仍输出原纹理×tint。材质状态与逐renderer相机约定已分离，实际ordinary输入仍决定相机及当前depth/A2C限制，不能代替材质编译。沿原材质准备/实际shader或typed操作接入，区分已消费与未实现输入；不能以效果名或源码形状白名单扩张许可，也不能盲目忽略未消费输入。普通CUTOUT仍是静态consumer缺口；现存283份冻结R0材质只有366的REFRACT1+LIGHTING1+CUTOUT1，没有可独立修复的ordinary CUTOUT活动定位，故不造新fixture/补丁或外推全部748。其余额外材质输入仍无逐作者画面资格。 |
| Child parent 控制点映射的消费诊断 | `rawParentControlPointOverride` 的 hasKnownConsumer 只看单CP字段，未纳入 Between/Maintain 的 start/end；rawflags0、parent字段及零位置可能被记为 ignoredUnused。该形状的 parent 位置语义尚未资格，不能凭旧 guard 增加整 child 拒绝，也不能把该诊断当成新组件已正确消费父映射。定位 copy bit、原始/解析位置与实际消费者，补有位移父点及不复制邻例后决定最小修正。 |
| 粒子 Remap、约束与子束链 | 三个作者root的operator10仍`prepared-plan-unavailable`，时间→sine→opacity缺真实消费者。独立静态范围与晚EventDeath输入已有有界资格，但sine首对落未预登记模型，依原停止条件收口；实际读数与旧N/W/D限制归[运行证据](../capabilities/runtime-evidence-current.md)，当前实现归[组件合同](../capabilities/particle-component-coverage.md#operators)。保留未知数学与作者缺省参数，后续用可区分证据沿原owner补消费者，不按效果/输入输出/flags组合追加许可。beam child另缺transform/CP及initial-value供货；3527426897的map-sequence另需flags/空间输出资格。 |
| 粒子碰撞扩域 | 现役[Sphere](../capabilities/particle-component-coverage.md#sphere-collision)与[Bounds](../capabilities/particle-component-coverage.md#bounds-collision)各保已验证范围。后续只随实际作者输入核接触子步、尺寸裕量、CP锁定或其他响应和空间，不重复已闭的默认画布回弹。 |
| 双控制点的弧向与周期序列 | Between仍未消费arc参数；三个闪电root为arcamount.1/flags23，未请求0x20，现partial也不包含这些arc字段。官方默认/存储已取证，本次有界静态仍无Position消费者；原报告尺寸缺省更正为.9，截断伪码不作全函数排除。新零噪声Q仅到资格场：PNG有预览而原生观察不一致，按首错停止，未授40中心/运动、未生成A或推弧启用/关闭。输入、原PNG、完整guest新文件及独审保于`.artifacts/scene-arc-qualification-20261107/evidence.zip`；采集先合格才重启语义研究，否则换项，不续旧两粒/弱端点矩阵。mask32旧周期输入显示新窗回首端，落实仍须原emitter状态/跨窗出生定义；不用particleID猜多emitter/显式交错。自然新生与存量边界已测，CP同cadence显式新生/后续Maintain顺序仍待有界对照，不加整链许可。 |
| 无实际屏准备间的更新与终态回流 | 用户贴图已退出actual非空误拒绝，同Session保存结果并由新View采用，实际PNG空窗与原生prime/reset边界见[当前证据](../capabilities/runtime-evidence-current.md#display-user-textures)。其余visibility/direct-model混绑仍依真实消费者；沿原请求核其余标量/暂停更新与无新输出后的stop终态回流，不造幽灵屏或重发launched，范围见[显示空窗状态](#display-live-state)。 |

<a id="display-live-state"></a>
### 显示空窗状态

新增/混合职责归[显示配置和屏实例](../architecture/runtime-architecture.md#display-reconciliation)，用户纹理请求归[原Session资源合同](../architecture/runtime-architecture.md#display-user-texture-updates)。已验证用户贴图与[raw空解析控制边界](../capabilities/runtime-evidence-current.md#display-no-output-control)由运行证据维护；后者未取得有效图片、自然拓扑或Client/UI资格，不据此新增故障协议。下一步须先取得这些实际消费/原请求回流证据，再决定修法；其余actual暂空的属性/暂停回执仍待核。不用合成消费者、保非目标窗、重发launched或另造显示许可解决，保 `.stopped` 用户command合同。Host/client同值过滤保持，无新事件时晚到ID自动恢复、真实多屏/物理backing/HDR、严格RNG、App媒体decoded连续与最大帧隙仍各有证明上限。

## 内容与观测资格

| 定位 | 当前事实与下一步 |
|---|---|
| 音频composition · 3039882306/772 | 本轮受控PCM/静音均有772的typed左右32数组消费及所选material→group→tail绘制；旧无consumer边界已退出，但两侧均绘制，不能归因PCM激活。精确音频幅度与目标ROI贡献未资格，隐藏1084的fallback另记；详细资格见[当前复测](../capabilities/runtime-evidence-current.md#coverage)。 |
| 粒子短窗触发 · 2866723317 | 当前四秒selected186/GPU完成，无particle draw；334/400/210/106均未进入自然constructor，accepted与construction-rejected均0。前三层确有选频非零供货，但bounds后幂响应与积分没有逐步读值，峰值非零不能断言应出生。106的rate.2及instance.rate.2使10秒预热加4秒live仅约.56个请求，尚不足整数出生；无delay，不改公式或盲延等待。后续按真实root及足够正输入核首次出生/实际batch，不能把该短窗归为构造拒绝。 |
| 必需binding · 3556263543 | 五个文字psyhue e0真实采样slot2缺authored/default binding而持续旁路，e1与终端健康。缺省语义仍未知；自有官方对照修正基底后，完整无损采集仍未资格，未跑改名/slot变体。原失败与归档限制保于`.artifacts/scene-sampler-absence-20261107/evidence.zip`；重新研究先资格完整采集与正控，不续旧矩阵，不随意填纹理或把copy算原effect执行。 |
| shader与事件脚本的未活动分支 | 2887099508/257e0已冷接纳，但默认hidden、无实际消费；其Point1为vec2 timeline。g_Point1 warning无owner，共用shader的384是唯一未接纳plan，另含event-only Script+Timeline。旧pass wrapper/media事件例外、真实export角色、consumer保留与值发布未贯通；还需资格`thisObject.getAnimation('900')`，不能只删attachment guard宣翻页恢复。重启须作者真实触发及同subject绑定/GPU，不强制visible或猜world矩阵；事实在`.artifacts/scene-point-attachment-20261108/`与`.artifacts/scene-event-vector-20261108/`。2932157836/299e1与2857410102/91e3仍无活动资格。 |
| 活动shader局部降级 · 3042492564 | 既有受控media+mclick_interaction=true的旧诊断App中，339/e3为AA编译失败：作者两个`<=640`分支内缺分号，上游实际640²，补Resolution成员仍不能避开，目标dialect未资格，不补作者源或定论作者错误。363/e0首pass两个hidden sampler无binding/default，BLURALPHA0实际读1.alpha，旧门先拒slot0；[唯一官方控制](../capabilities/runtime-evidence-current.md#unbound-sampler-control)的A/C/D及probe标记均失败，缺省来源保持UNKNOWN，不追加第二版、不放通all-hidden/白图/零图。重启先有合格source/effect载体与可区分绑定，保局部fallback；资料在`.artifacts/scene-active-shader-304-20261108/`及`.artifacts/scene-unbound-input-control-20261108/`。 |
| addColor String seed · 3662390671/793 | `textColor`的builder与wrapper都是String，setter读取x/y/z失败；默认showfpscounter=false且R0没有该层末帧消费。RGB255的有限Vec3修复不改变此类型；待官方String-seed正例或合法Vec3输入后重启，不按addColor名称强转、补默认值或重复PCM/旧矩阵。输入与停止线保于`.artifacts/scene-script-color-next-20261108/`。 |
| 作者脚本与VM边界 | 34个默认样本有typed Script事件；逐subject索引为归档的`task/r0-script-event-index.json`，不能按异常类批量归作者或引擎。2890473419四个origin脚本仅声明shadowLayer即写visible、2982559622把Vec3返回给alpha为已证输入问题。3504669359的166/720/718/716缺prepared Puppet metadata：clip700在bounds前的双曲线与后方MDMP字段关联，七骨TRS恒定，现无morph消费者；不能将扩Reader或补metadata称作眼睛动作恢复。372/373/336的init读取`thisLayer.position.y`，公开属性为origin，三层默认hidden；官方runtime别名未知，不造默认值。3605722997有效delay="5"，49/193/206完成无warn/TypeError，55默认hidden；warn仅非法delay/video时长、缺video或禁用click。log/error符合[官方IConsole](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IConsole.html)，不据此条件分支修主景。3610154602的435.alpha请求不存在的playeroutlineanim，origin另请求缺失的时长/背景进度层；423的祖父为空。它们待合法目标，不重查动画metadata或补空句柄。3779026256四个裸scriptProperties未供，export factory生命周期未资格；默认112/33已画、248/322未画与原fallback相符，不自动执行factory或补true，待合法producer/官方合同。其余核原target；34为事件索引分母，非当前故障数。 |
| 缺输入 · 3736952187、3763323436 | project.json不存在，未启动App；补合法输入后再跑，不作引擎失败。 |
| named demand · 2069136288、3395777145、3829467967 | 默认未达静态planned的目标没有当前active consumer；本轮3557068717/420 authored=false、3476868923/533 effect inactive亦分开保留。先取得真实writer/活动需求，不要求默认帧执行所有潜在capture，也不以此解释主景像素。 |
| 粒子预热CP · 3799613625/321 | 失败归static child0/system1 red_fire emitter0预热，非root。当前开启cursortrail并供inside pointer后，同consumer live出生及所选child Sprite/main/GPU已成立，见[运行证据](../capabilities/runtime-evidence-current.md#coverage)；冷缺历史pointer不授持续播放失败，不删除CP有效性边界。只有outside后PNG，逐像素轨迹与完整交互仍未资格；不据旧预热诊断继续扩修。 |
| 来源阶段读口 | 本轮source-not-ready首断点均在Ready前，后继同layer恢复或1045转hidden的实际资格归[当前复测](../capabilities/runtime-evidence-current.md#coverage)。沿原reader保时间/需求边界与原失败，不把不同阶段聚为持续错误；同layer成功仍不证明同slot或逐像素恢复。 |
| 纹理关联与最终贡献 | 全部声明有索引，但ordinary/geometry/particle部分实际draw未携带asset provenance，graph/provider引用也有未闭关联。不得解析Swift描述字符串猜identity；沿已存在Candidate/Resource carrier补最小typed映射。本轮3788897599的291/259 composition行`rendererKind=unknown`，定位`SceneParticleMetalPipeline+Frame`的可选debug字段及原component observation供货；复测先核现有按需观测输入，不由路径猜种类，也不将此元数据缺口判为绘制失败。单帧bind/GPU/tail不证明全部实例或最终可见像素，动态输入、材质与render-target的未观测阶段仍保unknown。 |
| 着色器类型回归预期 | `test_scene_shader_global_scope.test_float2_arithmetic_does_not_cross_unproven_expression_boundaries` 的 user-call/normalize 仍期待不补`.xy`，与现有typed复合求值后窄化合同冲突；同输入旧/新产品都补`.xy`。其余9方法通过、GPU独立项1skip；按真实类型与编译/像素修订这两条旧预期，不能撤回合法转换迎合测试。 |
| 粒子回归夹具体量 | `script/tests/test_scene_particle_simulator.py`仍超过1000行，内嵌Swift准备/运行与多类组件断言共用大夹具；当前未达到自有代码行数与职责要求。按真实组件输入、共享准备与行为断言梳理现有fixture职责，保同一生产实现及独立失败反例，不靠wrapper、源码搬迁或复制模拟算法凑行数。 |
| 全仓链接门 · 非Scene文档 | `docs/architecture/steam-workshop-acquisition-contract.md`与`docs/history/cross-topic/steamkit-migration-completed-2026-10-16.md`指向`SteamWorkshopLegacyAcquisitionRetirement.swift`的源码链接解析失败；`docs/history/cross-topic/code-slimming-r1-r26-2026-11-01.md`指向`main-window-playlists-redesign.md#93-正式个人设置导入导出兼容`的锚点解析失败。相关正文均与HEAD一致；沿各自文档owner修正真实链接。该全仓门当前失败，本批Scene文档的局部链接及角色/导航另核。 |
| 条件/周期分支 | 3768303048本轮manual day/night的122/109及夜雪59有效显隐已成立，day sticky unavailable59对应隐藏，不能判活动粒子失败；真实时钟与pointer未资格。3042492564原树click父链隐藏，派生media条件已供货且有click后738绘制，仍缺首次出生回执/无click对照，不授点击因果。3764725758/3830665420第二轮仍未知，长窗不代完整事件。 |

## 需定向扩域的能力入口

下列是尚无充分当前输入资格的边界，不是默认短窗已证缺图；具体合同仍由能力文档拥有。

| 定位 | 下一步 |
|---|---|
| hidden/forward父graph named输出 | 可见、已可满足的普通image graph-final已有transform children时可复用原graph发布；hidden FX父仍在image来源谓词保leaf范围，forward可见来源仍受原执行期限准入。hidden claim/execute/named-only消费者已存在，需独立父子/多reader及生命周期对照；forward沿实际source独立性与作者位main期限核，不能由新visible正例裸开utility/Puppet或用raw替身。当前最新静态parent筛选无精确作者命中，保能力边界，不造默认缺图归因。 |
| source material · 3616476797/113、3679907516/71/74/83、3141464346 | 367原R0三层冷拒但TEX已到ordinary/effect→main，静态cover推算在左侧外、无当帧MVP/非等价ROI；重启须可见source及拖动/media相位错配，不由VERSION2/translucent推语义，原STOP在`.artifacts/scene-source-material-367-next-20261109/`。361/113为静态Media Area，不能混作130 thumbnail；314的277/719已有TEX→main、416/420已有source/effect→tail，232/321/386/481 authored隐藏。九层source state拒绝不授缺图；重启须对应活动pass/source与可见ROI非等价，不先放state或新跑，薄事实在`.artifacts/scene-source-material-next-20261109/`。 |
| static model / resolved render state | 任意shader、多pass与更广blend/depth/cull须原binding compiler和fullscreen/output用途资格；保深度、淡出与PMA。 |
| Puppet · 3577990983、3822822401、3779107475 | auxiliary/reference、非中性通道、dense state1及多contributor姿态按真实reference/attachment坐标基资格，Reader识别不等于evaluator执行。 |
| point volume · 3047405322、3437487219、3477054430 | 需实际volume consumer；现有spot plan和point表面光照不能代验。 |
| Script动态特殊资源与typed callback | 特殊Puppet/composition创建字段、3028048463的531.alpha空数组/506.origin分别核prepared catalog及实际producer，不造空实例或无差别容错。 |
| Script粒子scalar回调交接 | 相反自身setter/返回与隐式init后输入/getter次序尚无官方资格。原alpha探针已分清即时journal、附着返回和下一preliminary两路，不把本次input自动当getter基线；重启须官方顺序或明确的项目回调合同，再在原primitive/merge修正，不重跑已闭字段运输/模拟门。原四case与STOP在`.artifacts/scene-particle-instance-fields-next-20261109/native/`，已接字段合同归[Particle instance](../capabilities/scenescript-api-coverage.md#particle-instance-scalars)。 |
| sampler宏声明接口 | canonical g_TextureN声明配宏采样read已准备通过；自有slot0将声明改为宏别名时，raw SchemaSeed未展开，unconditionalSamplers报authoredSamplerSchemaInvalid。当前没有作者缺图资格。沿原冷预处理/接口事实统一Schema，保真实slot/metadata，不新增别名许可表或忽略用途；后续资源目的仍需独立资格。 |
| RopeTrail其余renderer字段 | 公共Worldspace与整数subdivision已沿原消费者接通，资格见[组件合同](../capabilities/particle-component-coverage.md#rope-trail-world-subdivision)。child尚无RopeTrail历史消费者，仅局部拒该输出，root多输出不授此能力。显式非正length仍拒绝；固定客户端静态最小值钳制尚无作者/运行资格，不能据此授完整history单位。非screen朝向、动画、size fading及UV字段各需实际消费证据，不以原flags误拒保留它们的整renderer许可。 |
| 粒子其他资格 | CP/child空间、Mirror、nested/event、HSV缺省（3585542943/253/257、3761159935/453/457）、Vortex flags2及absolute color字段各用出生/轨迹输入；normalizedColor不是absolute color。 |
| dormant视频与输出扩域 | 单可旁路effect的材质视频无用取图已归[现役合同](../capabilities/material-video-assets.md#inactive-material-frame-acquisition)，不重做。共享/named活跃需求与后台AV解码停用仍分别资格；重启须具体空需求开销及保持首个可见PTS/EOF的同链证据。物理HDR/EDR、lighting/receiver、文字backgroundbrightness与HDR8bit裁剪各保独立资格。 |

<a id="user-feedback"></a>
## 用户反馈与定向视觉资格

以下位置均不能由默认短窗截图裁决；复核时固定属性、声源、pointer、时间/相位、viewport 与 App。终端存在、主画面成立和具体 ROI 正确是不同资格，先找真实 consumer 与首个不同 stage。

### 基础画面与基本交互优先

| 输入 | 精确待核位置 |
|---|---|
| 3306942838 · 图2 | 头动偏移过大；head24/body28独立root，particle642只引用body attachment；1606未准备与bone52降级仍非根因。官方reader的[state1/零mask/TRS准备已证](../capabilities/runtime-evidence-current.md#puppet-attachments)，mask→pose仍UNKNOWN，330 STOP不解除。重启只补真实消费者，再核同相位头/体pose→geometry；不调幅拟合或套329修法。 |
| 3382111183 | 六个活动 beam emitter（115/178/335/173/167/170）的 exponent100 仍被现计划≤16拒绝。官方 reader/evaluator 与相对64→16投影已取得静态边界；共同音频候选未恢复338321目标且用户报闪烁，已撤回，不再重复消费端/指数研究。下一事实须是实际 provider 的绝对域/状态或合格同声源数值与 ROI；不由 Script AudioBuffers 可超1外推particle，不调gain/bounds或强注入1。原供值与候选停止线归[运行证据](../capabilities/runtime-evidence-current.md#instance-color)。 |
| 3383210272 | [原曲目](../capabilities/runtime-evidence-current.md#beam-shared-pcm)官版成双束、本机成熟帧各2颗。[同帧对照](../capabilities/runtime-evidence-current.md#particle-audio-prepared-fold)已将幅值差定位至准备64档，同帧16档支持取峰。暂收口供值研究，转可直接归因的开放项。重启须有可配对的运行端PCM、原始64谱与准备值，沿[设计](../../architecture/system-audio-spectrum-design.md)裁决分析窗及分域，再验原曲目宽双束、闪烁及相邻消费者。不重跑旧板/同WAV或单改取峰、增益和出生。 |
| 3617449489 | 尚未定位用户所指环。原project与旧census摘要相同，当前作者说明含“取消3D音频条”（不等同于环）；17对象无Script，两个leaves4粒子无audio，唯一Shake音谱分支AUDIOPROCESSING默认0、作者仅DIRECTION1，Sound不证明有环。保反馈待具体ROI/对应producer或输入版本，不先跑PCM/调频率；薄输入与停止线在`.artifacts/scene-audio-ring-20261108/`。 |
| 2814167871 /2835398595 | 眼部为132/e1与98/e0的pulse RGB增亮，16档band0/1均值跨.5才响应；281强度属性默认1、283常量.51。[默认PCM前5秒](../capabilities/runtime-evidence-current.md#eye-audio-input)无跨线正控；后续同作者WAV的281两App静帧已有真实16档消费，但不能判眼部闪动或闪烁。粗档候选已撤回，283不追加矩阵。重启须可裁决实际供值/首错，再核同帧pulse→tail→眼RGB；不调gain/作者参数、不强注入1，不由bus非零关闭。 |
| 新增粗筛 · 3557068717及条件项 | 355唯一18秒晚窗已见完整暗地球/时钟/星空，退出“仅小亮点”描述；亮度原因仍UNKNOWN。作者有10–12秒入场与实时太阳，R0四秒与当前时相不等；重启须同帧sun world/normal/material资格，不第三场延时或用无活动需求的420 named计数解释黑。当前结果归[运行证据](../capabilities/runtime-evidence-current.md#coverage)。3455121165/244的origin/scale、3470948192/115的scale早期坏return后均已有finite成功，不能判持续故障或凭日志顺序归shared调度；具体ROI仍待归因。3453730450时钟、3360178853牙口与2868108515条纹仍待各自条件/source资格；113对粗筛不授完整视觉，不从其他rawPASS关闭反馈。 |
| 2887099508 · 图5 | [黑纹](../capabilities/runtime-evidence-current.md#basic-interaction-288)未重现，待同相位ROI或具体版本。原生持续悬停待合格输入，仅在出现可重复的命中问题时复核。 |
| 2999907577 | 旧终端主体完整，大片背景灰与有效默认tint相符；876e6流体的执行不授像素贡献。后续只在需要时用现有selector7→8(None)定位白弧/流体贡献，不按preview判缺纹理。 |
| 3436945972 /3463406101 /3443450456 | 分别偏暗、暗绿配色及灰白底黑字；同亮度、遮罩、配色/时段与音频输入后定位writer，不从preview归tone-map/blend。3382111183另并入本次主要效果可见性优先项。 |
| 3498814983 /3605722997 /3827673174 | 前后两项当前目录已移除，保原反馈为输入不可用；360572当前可运行。头脸取景仍须固定横屏camera/cover/平移与作者画布，portrait preview不能证明投影错误。 |
| 3504669359 /3767460992 | 350默认四秒旧强白圆未重现，固定圆核及当前材质/终端边界见[运行证据](../capabilities/runtime-evidence-current.md#coverage)；不据此修产品，媒体/光效全相位、发布copy物理边及selected pose仍未知。376中央白X已有当前作者fallback供货；真实媒体事件、封面替换及显隐仍需资格，不能从预览差异判纹理漏载。 |
| 2982559622 | [竹林→池塘](../capabilities/runtime-evidence-current.md#coverage)已实际出图，退出该条件切换待核。103.alpha确为Vec3错误返回；111/94的条件+Script包装仍有冷准入边界，视频属于effect slot1。重启须合法附着回调/视频句柄及具体可见失败，不先放包装、不重跑默认或0→1。初始111短暂纹理未供与正常切换分开。 |
| 3034166869 /3223543799 | 其余 effect、媒体与完整画面；常开音条与条件隐藏分开，不凭短窗结构状态实施。 |
| 3141464346 | [裁切](../capabilities/runtime-evidence-current.md#ring-cover-314)已由原画幅及已有Windows图定位。保Puppet位置与共域彩弧细节，须有同viewport、同音源及相位的可区分差异，再核13/351的group尾与main，不重跑默认/静音对。 |
| 2957870426 | PCM/静音已供，目标audio消费者仍未资格。中央竖光、birth Color Random/colorn与ROI须真实出生及颜色单位，不凭bus非零关闭；3383210272并入本次主要效果可见性优先项。 |
| 3586308277 | SDR原色已恢复，扫描方向/可见度仍未知。[原作者两阶段](../capabilities/runtime-evidence-current.md#shimmer-phase)的Day430主字形均浅绿，未见可归属扫描变化；不能由所选4814近稳像素判冻结。冷常量/时钟链未见首错，g_Time实际上传未读回；现有两图不覆盖完整周期。此项收口，转其他基础播放；重启须可归属扫描ROI/实际phase或明确首错，不第三场延时、调方向/速度/颜色、重跑SDR或新增钩子。 |
| 3351179520 | [归档画面按主体配准](../capabilities/runtime-evidence-current.md#circular-text-alignment)后环位、可见轮廓与遮挡对应，本轮无几何首错。保已知 Atami 替代和动态相位边界；重启须同视口/声源的同字串偏差，再以同帧 slot1→422→399→799/main 区分字形、MVP 和 g_Time。无需再跑默认整景。 |

### 其他待核

| 输入 | 精确待核位置 |
|---|---|
| 3022080536 | 旧固定pointer只取得child0 smoke；[静态复核](../capabilities/runtime-evidence-current.md#instance-color)已定位作者红→暗红ColorChange，尚未取得运动Rope。重启须目标ROI/运动phase/producer，或同capture initialColor/age/上传tint与真实texture path；不重跑旧固定pointer、不由红色外观改operator/纹理或由出生赋色关闭反馈。显式audio child仍独立核对。 |
| 2927205881 | 原作者左端仍短。[固定速率与淡出](../capabilities/runtime-evidence-current.md#particle-rate-alpha-envelope)两档开场分离、稳态收敛，原AlphaFade对照保尾段渐隐，暂无足以修改公共算法的首错。此项收口；重启须原699同视口/同声源下的实际出生相位、活粒子龄或原sprite可见贡献，或有区分力的动态rate切换首错。避免重跑原整景早晚窗、固定rate板或调增益。 |
| 线性Movement大阻尼 | [同龄对照](../capabilities/runtime-evidence-current.md#particle-movement-half-life)的drag40在官版比本机多约15 px，drag20在容差内。暂保当前半衰模型。重启须有真实作者画面影响，先隔离实际更新步长与重力注入顺序；不用单个高阻尼点推出参数夹限。 |
| 正交 Sprite 侧转 | [十五轴板](../capabilities/runtime-evidence-current.md#particle-around-phase-frame)的精确90°画面差已到Sprite局部quad/VP；3827949716/28与3173418061/131实际flags4走透视，3577990983/1370仅复合近侧转。重启须同路作者可见缺失或能区分Screen朝向的官方对照，保固定平面、镜像和原透视。 |
| 3577990983 | [同原包六点](../capabilities/runtime-evidence-current.md#dock-hover-radius)的进/退尺度符合作者半径602.112，暂无越界首错。真实desktop或同条件官方边界仍待有具体反例再开；截图错相属有界采集，不加量重跑或调作者阈值。 |
| 2887542690 | 图框内音频 ROI、黑遮挡/字体及片区布局，先取得可重复输入。 |
| 3768903841 | 横向云片/烟花色彩仍待具体ROI/producer。原R0的238.angles completed、frame0 vectorFailures=0，232已消费其共享时段；238是Day/Night按钮而非烟花writer，未找到旧screen localStorage异常原收据。重启须精确新失败/屏身份/调用回执，不删screen guard或归因烟花；未点击，不授持久化，薄事实在`.artifacts/scene-cloud-238-next-20261109/`。 |
| 3226487183 | 1028手部外观仍开。Windows参考与本机取景/画幅不同；现有捕获中实际纹理经mask/wave→mesh→main，未定位首错。重启须同取景与pose/phase的手部ROI或阶段差；不重复默认短窗，不凭轮廓调wave/骨骼。收据在`.artifacts/scene-hand-322-next-20261109/`。 |
| 3809618616 /3791967416 | 前者布局裁切/音频，后者局部合成及眼部完整周期。 |
| 3789316755 /3211615441 | 频谱形状/幅度/全柱活动；321首焦点、持续按住的作者行为与多步跟随分别待验证。 |
| 3788467391 | 漩涡方向、速度、形态与长预热的可比相位。 |
| 1315486372 /3769761761 | 光线宽软/渐隐/水波位置与头发上方斜带；376的`.01`属于instanceoverride，需完整可归属光束贡献。 |
| 3113287126 | 小提琴方向/密度反馈仍开。原R0五活动root均到main/GPU、无child，全随parent500；Directions普通量/默认，旧bounded不作缺图，当前未见可证重复world转换。重启须明确root/ROI、发射与父Puppet同phase及当帧pos/vel→attachment/model/VP，不能由单图或几何实例数调count/speed；薄事实在`.artifacts/scene-violin-311-next-20261109/`。 |
| 3437487219 | Earth亮侧/云层光色；Cloud Chroma MR/specular/pigment及coverage，另分闪烁与collision。 |
| 3743305891 | 原R0活动十字为child1的22个Sprite几何实例；root/child各取自身size空间flags，child2.5与父layer10是不同声明，当前静态消费链未见同一scale重复乘。缺同phase尺寸oracle与当帧instance.size/MVP，反馈仍开；重启须官方子world继承资格或可归属size/空间→像素错配，不调size拟合或无差别重跑。原输入、三batch/main/GPU及链路在`.artifacts/scene-cross-size-374-next-20261109/`。 |
| 3768229922 /3770444459 | 376原R0的4秒片头与16秒后续均未定位黑滴ROI；1103/1144玻璃各30实例、color/normal/background→main与GPU已有实际供货，不判完全未执行。反馈仍开，重启须明确哪颗/哪个ROI、相位和对应活动source，不追加无差别第三场或由名称推PMA/混合；薄事实在`.artifacts/scene-droplet-3768229922-next-20261109/`。377主体/眼部完整过渡仍须同相位合成ROI。 |
| 3768724269 /3287715210 | 光束范围/根部/右上渐变；眼周亮度/渐变与横移细竖纹分别定位。 |
| 3750813609 /3363252053 | 相机过强/纵向反转的同输入体验；375另核时钟颜色、雨量与雷电。 |
| 3662790108 | 球体/曲率与点击仍需具体ROI。[P1] Data未被真实shader声明/消费，R0的OrbitA/B供值及517→tail/main已成立；不补shared别名或以未用脚本解释画面，待对应活动producer首错，薄事实在`.artifacts/scene-script-next-action-20261109/`。 |
| 3589454154 /3747492842 | Bloom/细线微颗粒/轮廓；闪烁/光束位置/crop/文字构图。 |
| 3248220186 /3337494481 | 前者运动/密度/亮度；后者跨面文字、扁盒/粉顶、遮挡与solid亮度。 |
| 2938612768 /2775915974 | 293默认裁屏已沿[原文字与画幅](../capabilities/runtime-evidence-current.md#text-screen-anchor-viewport)定位，重启须点击/更晚相位的具体新差异，不重复默认移位对照或改anchor；277顶部灰边仍须实际画幅/图层与相位资格。 |
| 3712499998 | 作者明确声明21→22、28→29、33→34三对文字，子层有独立近邻位置及压缩Y scale；原R0六层均有效visible，不能将副本文字直接判引擎重复draw或删child。样式反馈仍开，重启须具体glyph/geometry/样式差异及同viewport/phase消费者或官方参考，不重跑原默认短窗；薄事实在`.artifacts/scene-text-pairs-371-next-20261109/`。 |
| 3477054430 | 显示完整性、月亮/球体/文字、低频与猫受光，逐ROI定位。 |
| 3764725758 /3549827466 /3581882134 | 左斜光/眼睛漂动、缺光ROI与暖亮/冷暗来源。 |
| 3723344874 /3793998447 /3792249095 | 人物后烟雾涡动、音频属性差异、外圈样式及内外位置。 |
| 3042492564 /2932157836 | 光束/右裁切/blur/布局/媒体交互、精确spin及媒体仲裁。 |
| 3233141951 | 脸/龙/小人/刀轨迹与双色音频仍需同phase、具体ROI和对应活动producer；不由单条动画选择恢复关闭其余反馈。 |
| 3807668787 /3420215721 /2684431262 | 958 A2C/pointer轨迹、中央环亮度、发光与整体合成。 |
| 3470948192 /3264246690 /2131872317 | 水滴亮边/拖尾与反射、人物边缘AA/警戒带运动、蓝烟花上升/逐子出生空间。 |
| 3769688830 /3780119725 /3769364482 | 玩偶往返与黄球UV Spin、人物地面/摩托中层pointer及光照、Shake Breathing与发光突现。 |
| 3219398263 /2932631210 | 漩涡方向与背景，分别固定ROI，不能共改符号。 |
| 3028090166 /2419444134 /3113554287 /2304304373 | 光束、白点密度、顿挫、雾气叠加；低优先，先补当前输入。 |

<a id="performance"></a>
## 性能反馈：待同条件测量

| 输入 | 当前待测问题 |
|---|---|
| 密集预热 · 3337494481 | 剩余是正常配置的完整场景准备成本；[单root隔离收益](../capabilities/runtime-evidence-current.md#coverage)不授整场启动或Rope历史收益。旧普通Debug/可选观测90秒未首帧与优化诊断完成不同配置，不能作性能前后值。后续先核同配置普通播放/预热热点，分离Turbulence数学与可选观测，不重做已退出的大State参数、不删内容、提预算或原样长窗等待。 |
| 整体CPU高温 / GPU满载 | 先固定设备、构建、输出与真实workload，联合归因，不以历史温度或局部代码变化代替当前测量。 |
| 3476868923 /3507496797 /3662790108 | 重型内容冷准备与首帧成本；同输入区分model、shader、资源及首Surface装配，不延时限或减少内容冒充优化。 |
| 3805547608 /3372715909 | [380跨回绕](../capabilities/runtime-evidence-current.md#ordinary-video-loop-380)未见逐圈恶化；93复现的四次少供位于AV未给新缓冲，下一帧恢复，暂无同帧可见异常。暂收口，重启须可定位的播放停顿或可判别同帧差异；不重跑同窗、改时钟或增加轮询。337热切后AV驻留独立待核，须同PID精确source退出。 |
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
| 3028048463/531.alpha、3280903509/225.alpha | 空数组与Vec3返回scalar分别核作者配置、时序与字段归属；不静默强转。 |
| presented / performance 记录 | 实际GPU完成与系统呈现分开；沿present callback和stream身份资格普通窗口/多Surface，终端PNG不代呈现率。 |
| 3292370168普通Debug准备与505资格 | 读口跨帧误判和无需求记失败的生产逻辑已沿[观测证据](../capabilities/runtime-evidence-current.md#execution-observation-history)修正；原日志不改。当前`-Onone`/exe886b在4秒观察＋60秒准备监督期限未Ready，末记录first-surface-join4159ms，不能授505实际记账或归为11个播放故障。旧R0为`-O`诊断，不能跨配置判回退。先凭真实准备工作/栈或同配置证据定位，不原样重跑或加预算；`.artifacts/scene-startup-329-next-20261108/`保后继只读入口。 |
| 自有ABI与验证载体职责 | `SceneQuickJS.c`仍2801行，是自有适配而非第三方源码；既有domain/owner、输入和typed调用职责须收敛，不能以第三方豁免、搬行或新增wrapper宣称达标。`test_scene_generic_shader_program_artifact.py`、`test_scene_dependency_graph_output_runtime.py`及`test_scene_particle_simulator.py`也仍超1000行，混有内嵌Swift壳、legacy与跨主题probe。沿真实结果生产职责退重复和失效部分，保ABI、原字节和像素oracle；当前CodeHealth只覆盖Swift，不能授C/Python全语言合规。局部门及时输出编译失败，不等待长suite结束。 |
| capture · 3766415113 | 普通capture需实际窗口frame/时机资格；本轮Metal终端PNG不覆盖普通截图入口。 |
| 官方原生采集 | [原作者窗](../capabilities/runtime-evidence-current.md#beam-contribution)已复核刷新，当前仅定性。量测仍须沿[采集方法](../../../.agents/skills/mywallpaperx-maintainer/references/parallels-official-oracle.md)取得有效同窗像素或实际draw数值；黑图和相机getter不能授几何资格。 |
| 自有9000000015 | 90/91/92健康peer须有真实texture source及可区分ROI，先资格夹具，不能借主文字/clone输出代peer。 |

属性接口归[输入与属性](../capabilities/runtime-input-property-coverage.md)，工具按当前实现与输入资格复现。更新队列时只删已解决的具体子问题；没有当前复现则标待核，不复述旧实验流水或维持旧 verdict。
