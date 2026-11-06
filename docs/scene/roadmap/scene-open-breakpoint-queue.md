# Scene 当前开放问题

<!-- document-role: active-plan -->

本页维护未闭问题、输入定位和下一步。按画面合成/正常播放、可证性能成本、属性接线、工具资格排序。架构归[当前主链](../architecture/runtime-architecture.md)，领域合同归[能力入口](../capabilities/README.md)，冻结身份与覆盖范围归[运行证据](../capabilities/runtime-evidence-current.md)。

2026-11-03 全量发现635目录，633有效输入均取得Ready、真实终端PNG和GPU排空，2目录缺project.json。默认观察Ready后4秒、约第3秒截图；稀疏/过场另补长窗。逐样本、逐声明阶段、原始失败与输入/App摘要保存在本机`.artifacts/scene-goal-full-sample-retest-20261103/`的`full-archive.json.gz`、`sample-results.md/json`与`task/`审查记录。33个初次运行CHECK不等于33个引擎缺陷，raw通过也不排除局部拒绘。

样本ID和layer仅用于复现，不选择算法。隐藏、空媒体、延迟和未触发分支不直接判缺图；Program准入、实际绑定、CPU求值、GPU执行、局部tail消费和最终像素贡献分别记录，未知保持未知。

<a id="implementation-gaps"></a>
## 本轮实测的通用断点

| 定位 | 当前事实与下一步 |
|---|---|
| 只读全局值的已声明helper消费 | `SceneGenericShaderRuntimeConstantNormalizer.readonlyValue`对callee自身的prototype仍在`globalDeclarations[name]`处退出，即使存在同名定义且实参仅按值读取；无关prototype形参不属于此问题。沿原function header、实际call与参数方向统一声明/定义资格，保重载未决、真实global值影子、out/inout及initializer纯度边界；不能仅删全部callee检查或以名字组合放行。当前没有作者命中资格。 |
| 通道与操作推导 | 无typed边界的颜色兼容、alpha-only/packed data及有序signal仍有有界source事实；vec4类型本身不说明通道意图。自有whole-vector复制在无注解/otherPigment时，slot0/3实际选同资产但purpose=nil，Finalizer真实报texturePurposeUnproven；明确albedo的typed输入不是该缺口恢复。沿原冷准备汇合component来源、真实输出/资源用途，保data FBO、独立alpha及mixed-role反例，不再为效果写法追加识别名单。 |
| source fallback 的路径/摘要许可 | `SceneAuthoredXRayPlanner+StockIdentity`仍以固定路径、UI字段及两个摘要profile授source-passthrough豁免；`SceneImageLayerDrawRequest`仍以Pulse/Blur/Waterwaves路径、pass/slot/combo形状判source coverage。两者影响源图降级，不是通用Program执行许可，尚无当前作者被误挡的画面归因。沿原prepared Program的coverage、颜色边界及发布依赖事实替换并退役旧许可；核等价资源改名、真实alpha改变、PMA、mask与named发布反例，不能直接通放base source冒充效果结果。 |
| material default动画入口 | AssetCatalog的material ShaderValue未调用TimelineParser，Resolver再用instance覆盖；无override的动画wrapper可能被当staticExact冻结。typed material timeline和definition-only pass还缺完整producer/pass identity；这是静态代码边界，尚无作者运行资格。沿原解析及有效material/instance源接入，不另建资源owner。 |
| named供货 · 2972071249/313e9→234 | 234 hidden/childless；作者两effect visible=true，真实两节点authored图存在；inactive来自layer-hidden execution route。313前九段Program/tail健康，e9=`dependency-stage-reference-unavailable`。copyBackground省略默认未官方资格；prefix普通资源/颜色未资格、取时未知，不能raw source冒充效果结果。 |
| named 冷准入与来源边界 | `providerGraphIsAuthoredOrderIndependent`仍限定单上游，并检查潜在而非最终选中的背景路径；多上游与死 lower candidate 仍可能误拒。cold candidate 使用原始 renderOrder，实际执行已消费 utility 展开顺序与 trigger，冷准入差异尚未统一；background consumer 仍整体排除 graph provider。同 trigger 后需要先运行普通 provider 再消费的 utility 组合尚未接入。沿已选 Program、真实来源位置与原资源消费者补齐，不追加 member、效果或路径许可。逐作者缺图归因、任意 utility/模型/局部画布组合仍需实际资格。 |
| Project 初始关闭的 effect 热准备 | `SceneDirectBoolEffectVisibilityRouteAdmission` 的 utility effect 入口仍限定 fullscreen/composition；Project 已接通的 layer visibility 不等于 effect inactive stage 已准备。沿原 prepared source、Program 和 activation 核实际 effect-visible 属性输入及失败边界，补 effect 初始关闭→开启→关闭、改名和健康 peer。当前没有该域作者活动输入或官方资格，不按种类、路径或效果形状追加许可。 |
| composition 其他绘制消费者 | `SceneUtilityLayerSourceRoute` 对 model/spotLight 仍整类拒绝；原绘制未消费局部 raster。核实际 nearest target 的投影、深度、光照及 viewport/local 模式，沿原 draw owner 接通，不以新组件/效果名单代缺失消费者。 |
| REFRACT 官方采样与单位 | 当前粒子映射保本引擎 canonical 全局 screen-UV amount，宽窄画布与物理 extent 有内部资格。官方 top-level 控制已取得真实色带背景与省略/null 卡片的调制边界，合法 normal 仍只有匀色卡片，采样位移正控未知；composition 内隐藏背景 scope 也未资格。恢复研究需能定位的实际 normal 位移与背景消费者，不能由现有 J 数学推为官方像素一致。 |
| framebuffer需求记账 · 3292370168/505 | 505 dormant/currentHidden、无named target且无当帧capture plan；SceneDrawing先将全部未requested的framebuffer source加入unavailable并记encoded=false，实际EffectExecution已过滤无target plan，505没有执行捕获。当前CHECK来自无需求被记失败；沿原drawing owner区分排除与真实preflight/capture失败，保visible depth拒绝、活动需求和hidden named，不以总数抵消失败。不能将该记账修正称GPU或可见画面恢复。 |
| 音频composition · 3039882306/772 | 当前无对应CPU/graph/所选帧draw，需受控audio/source输入；hidden1084 pending失败、868 fallback不挪作当前可见层证明。 |
| Child控制点绑定与声明位义 | 无CP读取的leaf走[原事件消费者](../capabilities/particle-component-coverage.md#child-declaration-options)；非零未解释声明flags遇到真实reader或子树时仍只拒对应template，不回退默认CP。官方CP分支白/蓝目标重合，parent-particle供给与declaration位义未资格，不能套root General world位或由无CP等价宣全部flags无效。沿原typed需求和绑定源补消费者，保父/健康peer与现有static raw-parent copy；不新增flags组合许可。 |
| RopeTrail参数 · 3337494481、3527426897 | 前者活动10root先被renderer flags1拒绝；对应20层definition flags0，负subdivision=-16仍未资格。另224/251的definition flags1是静态hidden，不归动态祖先拒绝。后者637/1323缺length被拒。分别核renderer输入与隐式length语义，不取绝对值或猜默认。 |
| Rope A2C可见轨迹 · 3807668787/958 | 原作者已进入实际A2C Rope，五个缩导出活动相位126/224/224/252/238段均编码并GPU完成，camera与几何沿原约定。另次原尺寸图仅两个pointer端点有弱色信号，完整轨迹仍未资格；缩图不能判原始像素缺失。静态核无重复alpha、后置opaque覆盖或TEX padding，sickle单图mask稀疏且mip峰值降低，实际LOD未知。alpha1/0仅私有诊断，不能改作者alpha或放大增益冒称修复。先用可区分的UV/LOD/coverage输入定位；官方precoverage数学与本机sampleCount1尚无同输入差异资格，不据名称新增MSAA/resolve。 |
| 满容量的自然调度 | 官方maxcount2、两个life4初始fillers、rate.4周期发射在T8.2只有约6.5出生；容量64对照约5/7.5。无上限本身也延后，原5/7.5判别前提失败，周期quota按请求或接纳计费尚未知。沿原Simulator核满槽期间fraction/窗口与死亡释放顺序；不以这个未知拒绝普通或capped发射，不增加调度owner。 |
| 显式命令与自然相位 | 官方rate.4、on10/gap10、cap2，约t1 emit1后可见出生1/5/7.5；约t6 emit1后为2.5/5/6。显式在自然额度耗尽后仍贡献，但早期命令会改变后续自然出生相位，不能宣称与调度完全独立。沿原exact-n命令/EmitterState核交互，不挂共用appendBirth扣自然quota，不把未知变成整组play/pause/stop的禁令。 |
| 普通粒子材质语义 | AssetGraph仅核genericparticle basename；no-depth普通路径的额外CUTOUT/LIGHTING/UNKNOWN combo和user texture/value没有通用shader消费者，固定sceneParticleFrag仍输出原纹理×tint。RenderStateCompiler已将普通材质输入与几何许可分离，但其profile仍用于camera选择及当前depth/A2C输入限制，不能代替材质编译。沿原材质准备/实际shader或typed操作接入，区分已消费与未实现输入；不能以效果名或源码形状白名单扩张许可，也不能盲目忽略未消费输入。当前额外材质输入为代码链事实，尚无逐作者画面资格。 |
| 控制点无关默认位置的错型聚合 | 带角度 emitter 的 definition offset 错型时，即使 dynamic/instance 提供了有效替代位置，`parseControlPoint` 的聚合 `hasMalformedFields` 仍会经 `boundedEmitterAngle` 拒绝。按实际消费字段区分错误；保角度、flags、parent 的必要语义，不因默认位置已不用而整体撤元数据检查。需有效覆盖/无覆盖、坏 angles/flags 与健康 peer 反例。 |
| Child parent 控制点映射的消费诊断 | `rawParentControlPointOverride` 的 hasKnownConsumer 只看单CP字段，未纳入 Between/Maintain 的 start/end；rawflags0、parent字段及零位置可能被记为 ignoredUnused。该形状的 parent 位置语义尚未资格，不能凭旧 guard 增加整 child 拒绝，也不能把该诊断当成新组件已正确消费父映射。定位 copy bit、原始/解析位置与实际消费者，补有位移父点及不复制邻例后决定最小修正。 |
| 粒子 Remap、约束与子束链 | 当前四秒读口中3564173599/1987、3749463715/405/412的operator10仍`prepared-plan-unavailable`；时间→sine→opacity缺真实消费者。无sine控制已否证含预热/rate模拟钟加缺省identity/线性范围的联合候选，严格source门仍unknown，不能直接复用simulationTime或选global；读数归[运行证据](../capabilities/runtime-evidence-current.md)，实现边界归[组件合同](../capabilities/particle-component-coverage.md#operators)。beam child另有transform/CP及initial-value缺口。3527426897的map-sequence需当前flags/空间输出资格；沿原owner补真实行为，不按效果名许可。 |
| 粒子球体与画布碰撞 | 静态Sphere消费者见[组件合同](../capabilities/particle-component-coverage.md#sphere-collision)；首次接触顺序、精确轨迹/size裕量、CP锁定位及缺省数值仍未资格，不能由3773747576/183的CP333或CP1同位推断开关规则。Bounds的3780119725/891 operator2仍`unknown-operator-kind`，只有name/id；缺实际wallpaper边界经当前变换到粒子空间的供货和缺省响应，不能用drawable或发射盒代替。沿原碰撞/空间/Simulator补消费者，不把正常batch/GPU或退出授为完整碰撞能力。 |
| 双控制点的弧向与周期序列 | Between的raw0x08、0x20及arc参数仍有未消费语义；partial只记录当前未知位/坏size选项，不包含flags23的arcamount，其余字段继续。固定官方周期输入的mask32显示新窗从首端恢复；落实需沿原emitter状态与跨窗出生批次定义序列，不能拿全局particleID减首ID猜多emitter/显式交错。arcamount/方向默认已取证，但非零arcamount尚无消费者，不能因flags23缺bit8便断言其无效；完整曲线、位关联与随机协议未资格；沿用当前组件证据包，补有效/零控制和改名邻例。自然本步新生与存量边界已执行，CP变化同cadence的显式新生/后续Maintain顺序仍需有界对照，不加整链许可。 |
| 发射器Directions数值域 | `SceneParticleEmitter.hasBoundedDirectionsAndSign`仍把有限Directions限制在abs≤1e6；原Sphere/Box消费及最终新生Float检查没有同名语义上限。应分别核零半径、有效大值、实际乘积溢出和健康peer后，清理无用的幅度许可。当前全量样本未见该幅度门独立活动拒绝，不以它解释其他birth失败。准备期另有静态反例：Directions=(1e200,1e200,0)、固定radius=1e-200时，二维`pow(radius,2)`下溢0；若直接放域会出生在origin，最终Float有限检查抓不到错误零。先沿原径向准备/抽样明确数值语义，不再堆幅度名单或为极罕见输入新增运行防线。 |
| 粒子预热完成度 · 3009275235/35、3448877775/1775 | 原warmUp已按实际初始化出生/参与模拟数量计价；当前300请求10秒仅模拟4.25秒/255步，344雪层1775请求15秒仅模拟7.6秒/456步，仍保`prewarmBudgetExceeded`且有后续draw。3745828537的51/65两层另请求200秒、实际9.1867秒/689步，当前短窗虽有输出且整场报告通过，预热仍为部分结果。它们是现预算内的真实部分结果；核实际准备成本与初始状态/密度，保RNG、事件排空和Trail历史，不只提高上限或把扩大播放窗当完成预热。成本与rate时钟合同见[预热工作预算](../capabilities/particle-component-coverage.md#prewarm-work)。 |

## 内容与观测资格

| 定位 | 当前事实与下一步 |
|---|---|
| 粒子短窗触发 · 2866723317 | 当前四秒selected186/GPU完成，无particle draw；334/400/210/106均未进入自然constructor，accepted与construction-rejected均0。前三层确有选频非零供货，但bounds后幂响应与积分没有逐步读值，峰值非零不能断言应出生。106的rate.2及instance.rate.2使10秒预热加4秒live仅约.56个请求，尚不足整数出生；无delay，不改公式或盲延等待。后续按真实root及足够正输入核首次出生/实际batch，不能把该短窗归为构造拒绝。 |
| effect执行阶段读口 · 3292370168/239e0 | 当前parent named来源已接通；frame0/1在视频首帧pending时局部未供，frame10/11实际执行并GPU完成，selected23有151→e0→e1→main/seal全链。现reader将不同帧同identity的失败/成功聚为矛盾并报unexpected recovery，整样本CHECK4还含505。沿原execution/frame读口区分时间阶段、当前selected结果与持续失败，保原失败事实及同帧真实冲突；不能为消报告改渲染或将短窗恢复授视频更新/全像素。 |
| 必需binding · 3556263543 | 五个文字psyhue e0在真实采样slot2缺authored/default binding而持续旁路，e1与终端健康。缺项已证，隐式phase默认语义仍未知；不是census注释里的slot3。不得随意填纹理，也不能把copy的GPU完成算原effect执行。 |
| 隐藏分支shader | 2887099508/257e0明确g_Point1 script attachment未资格；2932157836/299e1 node1/slot0缺binding资格，2857410102/91e3仅有聚合purpose原因。均保never-visible边界；3042492564另有aa_gaussian/node3 stage-link失败，不能与blur slot0混因。 |
| 作者脚本与VM边界 | 初次32样本、含长窗33样本有实际script诊断；初次TypeError涉及21样本45个target，不能按异常类批量归作者或引擎。2890473419四个origin脚本仅声明shadowLayer即写visible、2982559622把Vec3返回给alpha为已证输入问题。3504669359的166/720/718/716缺prepared Puppet metadata：clip700在bounds前的双曲线与后方MDMP字段关联，七骨TRS恒定，现无morph消费者；不能将扩Reader或补metadata称作眼睛动作恢复。372/373/336的init读取`thisLayer.position.y`，公开属性为origin，三层默认hidden；官方runtime别名未知，不造默认值。其余按`task/full-script-failure-recon.json`逐target核上下文/producer/API/回调顺序。 |
| 缺输入 · 3736952187、3763323436 | project.json不存在，未启动App；补合法输入后再跑，不作引擎失败。 |
| named demand · 2069136288、3395777145、3829467967 | 未达静态planned的269/395/946无当前active consumer；需property分支输入，不能要求默认帧执行所有潜在capture。 |
| activation读口 · 3639999624/84e1 | 实际`activation-passthrough:inactive-dependency-preproof-mismatch`被reader判malformed/missing；作者visible=false，有GPU完成及后续e2消费。对齐原producer/reader分类并保inactive资格，不能改渲染消报告；此问题与hidden provider的exact身份命名空间分开。 |
| 粒子预热CP · 3799613625/321 | 旧/新均有emitter的prewarm `control-point-frame-unavailable`；首断点在`SceneParticleSimulator` emitter frame消费。核准备期CP source与首帧writer顺序，并按同emitter/CP身份补live恢复资格，不以其他root452/child的健康draw代该层，也不凭预热诊断断言全程缺图。 |
| 来源阶段读口 | 17样本的19个source-not-ready subject均在Ready前，14样本后有同layer成功；2982559622/3800572533另有资源前置失败后同subject成功。只证layer后续成功，不证同slot恢复；2804817823/3186328539无相同恢复，318的1045在frame1变hidden，不能要求必draw。 |
| 纹理关联与最终贡献 | 全部声明有索引，但ordinary/geometry/particle部分实际draw未携带asset provenance，graph/provider引用也有未闭关联。不得解析Swift描述字符串猜identity；沿已存在Candidate/Resource carrier补最小typed映射。本轮3788897599的291/259 composition行`rendererKind=unknown`，定位`SceneParticleMetalPipeline+Frame`的可选debug字段及原component observation供货；复测先核现有按需观测输入，不由路径猜种类，也不将此元数据缺口判为绘制失败。单帧bind/GPU/tail不证明全部实例或最终可见像素，动态输入、材质与render-target的未观测阶段仍保unknown。 |
| 粒子回归夹具体量 | `script/tests/test_scene_particle_simulator.py`仍超过1000行，内嵌Swift准备/运行与多类组件断言共用大夹具；当前未达到自有代码行数与职责要求。按真实组件输入、共享准备与行为断言梳理现有fixture职责，保同一生产实现及独立失败反例，不靠wrapper、源码搬迁或复制模拟算法凑行数。 |
| 粒子QuickJS事务回归夹具 | `script/tests/test_scene_particle_playback_transaction.py`的`LaunchContext.Program` stand-in缺少真实`domain`，提取的`commitSceneScriptLayerPlan`因此无法编译，后续world projection的`.init`也失去类型上下文。本批前HEAD九个粒子产品文件的替换复现同一首错，记录在`.artifacts/scene-goal-particle-cp-distance-20261106/task/native-transaction-head-baseline-validation.json`。对齐夹具与现役typed Program/投影后重跑原事务行为；该门当前未取得执行资格。 |
| 全仓链接门 · 非Scene文档 | `docs/architecture/steam-workshop-acquisition-contract.md`与`docs/history/cross-topic/steamkit-migration-completed-2026-10-16.md`指向`SteamWorkshopLegacyAcquisitionRetirement.swift`的源码链接解析失败；`docs/history/cross-topic/code-slimming-r1-r26-2026-11-01.md`指向`main-window-playlists-redesign.md#93-正式个人设置导入导出兼容`的锚点解析失败。相关正文均与HEAD一致；沿各自文档owner修正真实链接。该全仓门当前失败，本批Scene文档的局部链接及角色/导航另核。 |
| 连续PNG读口 · 3577990983片头 | 7秒/.6秒捕获实际写出4PNG，另6项superseded、1项teardown，整次保CHECK。等待lane时pending request仍挂逐帧composition，CB地址可复用；两次actual capture有多个request/CB候选，现reader以len1拒绝。当前按encoded行→同CB completed记录及同帧uniform有界核对；自动读口应沿原reader保编码/事件顺序或原DEBUG传frame/stream/generation，不能取首个request匹配，导出背压原因另核。 |
| 条件/周期分支 | 3042492564需click开关/父组，3768303048需day/night与pointer输入；延长秒数不能替代。3764725758的后续inactive事实、3830665420的10个鸟实例都不能证第二轮，首事实去重没有保完整周期回执；按实际模拟时刻/事件资格，不由墙钟授通过。 |

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
| 粒子其他资格 | CP/child空间、Mirror、nested/event、HSV缺省（3585542943/253/257、3761159935/453/457）、Vortex flags2及absolute color字段各用出生/轨迹输入；normalizedColor不是absolute color。 |
| dormant视频与输出扩域 | hidden仍被named采样与实际source停止分开；物理HDR/EDR、lighting/receiver、文字backgroundbrightness和HDR8bit裁剪分别资格。 |

<a id="user-feedback"></a>
## 用户反馈与定向视觉资格

以下位置均不能由默认短窗截图裁决；复核时固定属性、声源、pointer、时间/相位、viewport 与 App。终端存在、主画面成立和具体 ROI 正确是不同资格，先找真实 consumer 与首个不同 stage。

### 优先复核

| 输入 | 精确待核位置 |
|---|---|
| 1695673397 | 原1280截图顶部约32px整幅浅灰带且下缘硬，粒子覆盖其上；先核source边界/画布与实际合成，preview不是同相位金标。 |
| 2887099508 | 原图清晰主画面约偏至(250,197)，人物大部超右界，后方为浅色模糊背景；需固定viewport、作者画布与source/output变换。 |
| 2999907577 /3003318777 | 前者除上方白弧外大片平灰背景，后者整幅明显虚焦；对照作者默认属性与原source/特效输入，尚未资格归因。 |
| 3382111183 /3436945972 /3463406101 /3443450456 | 分别整幅失焦、明显偏暗、暗绿配色及灰白底黑字；同焦距、亮度、遮罩、配色/时段与音频输入后再定位writer，不从preview直接归tone-map/blend。 |
| 3498814983 /3605722997 /3827673174 | 头脸超画面或仅见脚裙；固定横屏camera/cover/平移与作者画布，portrait preview的取景差不能证明投影错误。 |
| 3504669359 /3767460992 /3779026256 | 分别器具前强白圆片、中央白X占位、衣裙前不透明白方块；需可归属source/target和同媒体/光效相位。377手中发光菱形是独立元素，不能混作该白块。 |
| 2982559622 | 默认短窗主画面成立；103.alpha返回Vec3、effect.visible组合wrapper分别核作者字段与准入；同输入完整视觉仍待资格。 |
| 3034166869 /3223543799 | 其余 effect、媒体与完整画面；常开音条与条件隐藏分开，不凭短窗结构状态实施。 |
| 3141464346 | Puppet 同 phase 位置、右下音频环与 shader 链；188/332蒸汽不能代音频环。 |
| 2957870426 /3383210272 | 中央竖光白色、birth Color Random/colorn 的样式；需实际出生与有效音频输入。 |
| 3586308277 | SDR原色已恢复；待核原动画扫描时间、方向与可见度，官方像素未获资格。 |
| 3351179520 | 文字环位置/尺度/旋转；需同帧 slot1、MVP、g_Time 与可归属 glyph，而非强制各TRS同心同速。 |

### 其他待核

| 输入 | 精确待核位置 |
|---|---|
| 3022080536 | 移动烟雾偏红、颜色继承/ColorChange 与显式 audio child；先确定颜色单位。 |
| 2919854127 /2927205881 | 蓝环可见性与曲线右短段，同声源 band 与实际触发条件。 |
| 3577990983 | 远距离 hover 提前放大；真实 pointer 与作者半径/投影。 |
| 2887542690 | 图框内音频 ROI、黑遮挡/字体及片区布局，先取得可重复输入。 |
| 2134765860 | Night选项4与右黑矩形的具体归属；先区分作者画布、媒体与独立mask。 |
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
| 3351163962 | 新补报左上文字超环，需确切文本、属性、时刻和viewport。 |
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
| 整体CPU高温 / GPU满载 | 先固定设备、构建、输出与真实workload，联合归因，不以历史温度或局部代码变化代替当前测量。 |
| 3476868923 /3507496797 /3662790108 | 重型内容冷准备与首帧成本；同输入区分model、shader、资源及首Surface装配，不延时限或减少内容冒充优化。 |
| 3805547608 /3372715909 | 视频越播越卡与热切后AV对象驻留，需当前普通播放、精确source退出和可比时序。 |
| 3749463715 /3420215721 | 观感低帧率、实际提交/呈现率与drop原因分别核对，不从旧计数判断当前预算。 |
| 3471294034 | 需同输入、同优化配置测实际呈现与瓶颈；本轮并行诊断短窗不作60 FPS或能耗资格。 |
| 轻重切换 / 多Surface | 同PID资源驻留与第二屏准备成本；先找真实持有owner和重复工作，不预建共享cache。 |

测量与退出规则只归[性能方法](performance-convergence-card.md)，本表不沿用旧实验数值或认领收益。

<a id="properties"></a>
## 属性与工具资格

全量635目录测量的本机证据仍在 `~/.codex/worktrees/scene-architecture-governance/MyWallpaperX/.artifacts/scene-goal-full-sample-retest-20261103/`，当前主仓没有同名目录。后续整理按现有有界归档方法统一定位，保留原输入/报告/源码冻结和唯一失败证据，避免将正文的任务名直接当成当前主仓相对路径。

| 定位 | 下一步 |
|---|---|
| 属性面板 | 总打开/编辑延迟、长Combo完整显示、系统键盘路径与更多locale需实际可达控件。保原始key/value/条件，翻译只改展示；完整段落、只读说明和reset入口不能因优化丢失。 |
| effect 显隐 / history | 关闭后保history再重新启用的首帧与实际输入待核；沿原activation/previous-current，不增另一history owner。 |
| text size | VM catalog size与排版logical extent是不同事实；setter后可见时机与padding/装饰需真实行为，不另建排版owner。 |
| 预处理成员 · 2819633264 | 未知成员按0的当前实现与横/竖分辨率、宏成员/空白等价行为需区分输入。 |
| console.warn · 3605722997 | 先确认实际 callee/堆栈与可达调用，再判断API缺口。 |
| 3028048463/531.alpha、3280903509/225.alpha | 空数组与Vec3返回scalar分别核作者配置、时序与字段归属；不静默强转。 |
| presented / performance 记录 | 实际GPU完成与系统呈现分开；沿present callback和stream身份资格普通窗口/多Surface，终端PNG不代呈现率。 |
| 编译门组织 | `test_scene_generic_shader_program_artifact.py`有9343行；`test_scene_dependency_graph_output_runtime.py`有2594行，其中1789行是内嵌Swift共用壳，另混有legacy与真实native probe。沿compiler/ABI、被动夹具、资源与实际行为职责收敛，先退重复和失效部分，保调用API、原字节及像素oracle，不能只搬文件或压缩行数过门。现CodeHealth只覆盖Swift，不能据此称Python已达1000行上限。局部门及时输出编译失败，不等待长suite结束。 |
| capture · 3766415113 | 普通capture需实际窗口frame/时机资格；本轮Metal终端PNG不覆盖普通截图入口。 |
| 自有9000000015 | 90/91/92健康peer须有真实texture source及可区分ROI，先资格夹具，不能借主文字/clone输出代peer。 |

属性接口归[输入与属性](../capabilities/runtime-input-property-coverage.md)，工具按当前实现与输入资格复现。更新队列时只删已解决的具体子问题；没有当前复现则标待核，不复述旧实验流水或维持旧 verdict。
