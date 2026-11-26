# Scene 当前开放问题

<!-- document-role: active-plan -->

本页维护未闭问题、输入定位和下一步。按画面合成/正常播放、可证性能成本、属性接线、工具资格排序。架构归[当前主链](../architecture/runtime-architecture.md)，领域合同归[能力入口](../capabilities/README.md)，冻结身份与覆盖范围归[运行证据](../capabilities/runtime-evidence-current.md)。

11-26 实库986件，124个新ID以 `3302e6d0` 默认跑4秒，123件有匹配GPU终帧、124件排空。串行确认4个产品断点与1个分母误报。3258021301的[动画缺图已修复](../capabilities/runtime-evidence-current.md#hidden-sprite-named-3258021301)。已复核124件project/pkg/tree全同，无新增待跑。索引归 `.artifacts/scene-author-intake-20261126/`；11-24的340件和11-25的3件归 `.artifacts/scene-new-author-intake-20261124/`、`.artifacts/scene-evidence/runs/scene-author-intake-delta-20261125/`。

11-24 的31项观察按首个可见断点复核。接续先对照页尾[已修复的用户反馈](#resolved-user-feedback)及[运行证据](../capabilities/runtime-evidence-current.md)。优先处理可复现的播放阻断、画面及交互差异，沿各行停止线推进。11-07补报13项中8项实跑、5项仅有census，定位与图1–5归`.artifacts/scene-user-feedback-20261107/`。

样本ID和layer仅用于复现，不选择算法。隐藏、空媒体、延迟和未触发分支不直接判缺图；Program准入、实际绑定、CPU求值、GPU执行、局部tail消费和最终像素贡献分别记录，未知保持未知。

<a id="implementation-gaps"></a>
## 本轮实测的通用断点

| 定位 | 当前事实与下一步 |
|---|---|
| Sphere 全零方向的出生可见性（待证） | [固定零半径初速](../capabilities/runtime-evidence-current.md#zero-radius-sphere-launch)已恢复。显式全零 Directions 的隔离 Sprite 官版无像素、本机有静点。现库860可读包及松散/库存的1,834个显式声明未见全零。重启须活动输入或子事件/占槽证据区分出生与可见性，保零速度和非零轴。 |
| 音频环形变 · 3612940332 | [分组末段缓释](../capabilities/runtime-evidence-current.md#author-spectrum-near-target-release)已恢复已测音乐左弧的主要形变。[1512×818 全环静态](../capabilities/runtime-evidence-current.md#author-ring-wide-fixed-361)同帧线宽与轮廓一致，无需复跑。原包人物/Bloom下动态右弧、小残差及其他画幅待有新可见证据再核。[44.1kHz](../capabilities/runtime-evidence-current.md#author-spectrum-endpoint-44100)需实际协商端点，当前复核仍48kHz。 |
| 粒子外圈 · 3653620838 | [近轴与像素相位](../capabilities/runtime-evidence-current.md#vortex-outer-pixel-phase-365)的静卡一致。继续须运动同亚像素或重复成熟群组，区分出光与覆盖。 |
| 3454689854 的相邻丝层 | [同画幅单丝、原包和实际预算](../capabilities/runtime-evidence-current.md#silk-capture-density-345)已闭两条SDR根丝密度。子层及多阶段保持原工作域，只有取得可归属的同相位残差再重启。原默认绕身文字两端均隐藏，条件另见[原包对照](../capabilities/runtime-evidence-current.md#author-silk-raster-345)。 |
| Puppet 约束的剩余时序与组合 | [原317和313已恢复主要播放](../capabilities/runtime-evidence-current.md#puppet-planar-constraints-native)。固定根解析投影在317额外+96对照的肘误差约2.17px，313极近伸直时官版定槽后仍收敛。待有原包可见差异再核有效根位移与收敛。复杂链、挂点及同链脚本与物理后写按实际消费者验证。 |
| 粒子筛查分母 · 3843644227、3842918581 | 前者288被父20隐藏，默认仅298绘制；后者183已载入，首帧脚本隐藏父22，sticky=1/1、当前0/1，仍出终图。以实际需求解释候选分母，取得父层活动见证再核两层绘制。 |
| 3589454154 环黑点/快速闪烁（部分修复） | [已修复半透明 generic4 错投定向影](../capabilities/model-runtime-evidence.md#model-shadow-coverage)，正常投影、颜色和受影保留。合法碎石仍见。余闪须新版本实际像素与获胜子域；沿[原相邻反例](../capabilities/model-runtime-evidence.md#model-shadow-fragment-taps)保宽主影、播放成本和N2停止线。 |
| 同输入天空背景点位差异（观察） | 3589454154原生/官方对照中的天空点位差异尚未归因，未认定产品缺陷。保留已有同输入画面，待环闪主问题收稳后再定位；本轮不开展新矩阵或按星点位置改算法。 |
| 模型用户视频与其它贴图slot（待证） | [用户静图slot0已接通](../capabilities/model-runtime-evidence.md#model-user-albedo)；现用户视频仅PMA，模型straight需求会拒绝同key视频并保旧，尚无作者选视频像素证据，不按后缀放宽用途。静图现仍沿旧declared-key兜底准备PMA与straight两用途，后续核实际消费者和物理纹理是否冗余再裁剪，不把ready计数当驻留量。其它slot的provider/动画仍需实际消费者与独立样本，不由slot0静图推广。 |
| 3662790108 全镜头与开场 | 默认开场随Date.now()，主过渡20秒、部分元素到25秒，复测自然播放至少30秒并区分远近镜头。[TRS同帧](../capabilities/model-runtime-evidence.md#current-authored-transforms)、[透明模型深度](../capabilities/model-runtime-evidence.md#model-translucent-camera-depth)、[普通图像冷深度](../capabilities/runtime-evidence-current.md#world-orbit-labels)和[零指数径向](../capabilities/model-runtime-evidence.md#spot-radial-falloff)已分别处理切镜头错相、地球斜纹、第二段说明和远端矮行星。焦点选帧与六个航天器两侧近景只授[模型证据](../capabilities/model-runtime-evidence.md#solar-model-views)范围，未见新模型缺片；Hubble高光细节与JWST暗面受光仍未知。余15卫星B及17有MDL航天器两侧已补实际49目标选帧/独审，未见新明确缺片；Charon眩光、Triton/Proteus窄相、北斗高光和三体水滴B细节仍未知，9作者占位不是缺图。[太阳标签与盘面双击](../capabilities/model-runtime-evidence.md#solar-label-double-click)已通过AppKit窗口定向Quartz输送验证总览→近景→返回；桌面global路由、遮挡与完整过渡仍开放；黄色/蓝色完整3秒切换仅原小Saturn可辨，不能由HOLD正常授全部运动。旧钟/胶囊缺片观察已纠正，实际面板重叠见文字行。347已用户验收，不再把旧转向顺序当硬前置。 |
| Direct模型HDR与相邻材质语义（待证） | [直绘组合基线](../capabilities/model-runtime-evidence.md#model-hdr-combo-baseline)确认当前只消费General且近期原包未见覆盖。等活动显式声明或官方固定输入区分优先级后再改，保HDRoff/E1及反射A1/E4/B1对照。前置A的max/add、CombineLighting和generic2直接光各需真实可区分控制。347现已验收。 |
| 文字透明排序的跨前缀边界 | 主画布最后一个独立区间已接文字透明排序与只读深度。[3455121165 的实际背景截点](../capabilities/runtime-evidence-current.md#native-composition-audio-prefix)开排序时先见合格实体84，296回绘的钟下音条留在终图，关时保作者顺序。早段字形 writer 仍待有覆盖字形的独立见证，较近实体遮挡 Composition 也待对照。366的Haumea A/Ganymede B已复核钟HH:mm完整。[面板重叠](../capabilities/model-runtime-evidence.md#solar-ui-layout)与作者固定Y及像素缩放相符。官方预览若有外框，先匹配client域再作读回。 |
| 模型HDR数值与属性种子的剩余域 | opacity冷归一及健康caster、Float颜色/PMA/coverage和[HDR关闭的无用亮度许可](../capabilities/model-runtime-evidence.md#model-hdr-disabled-brightness)均已按各自实际读回闭合；三灯采样边界旧已健康，不列假缺口。HDR开启及其余hostBuiltin emission/color/tint仍有raw Double→Float缩窄路线，只属剩余源码边界；不按字段续加guard或重跑已闭输入。重启须新的真实consumer红例，再按原需求/运算域决定，不统截HDR为1、不以maxFloat声称一般代数健康。RGBA16动态范围/极小alpha、一般Float32乘积及property/script巨seed回流未解，不授任意静动态等价。原raw UV zero/NaN仅属故障夹具，无生产typed可达证据，Spot/Point保实际失败生命周期，不当作待通放许可。 |
| 模型纹理border采样 | 源码确认TEX flag8被Loader/Catalog/publication/SlotBinding保留，但共享knownmask仍排8，模型颜色/shadow随后重复拒fallback；共享sampler只有edge/repeat四态，尚无border消费者，不能只删门把edge冒border。定向五星球包383个TEX header未命中8，只读index/首64B不授stock/loose/活动作者命中；当前不按这些样本继续重跑。若后续补通用能力，先按原owner准备明确透明黑border采样，核真实TEX/改名与相邻edge/repeat反例，并分别资格atlas局部边缘与fixed-image compact ABI，不新建PSO/fragment fallback或资源owner。 |
| 模型lookup与rim的用户输入 | 渐变slot4沿静态文件链供货，明确userTextureInputs[4]而无文件时只局部缺lookup，不能由stock默认冒充；当前未接用户provider或完整user/file优先级。后续沿原候选/ready与typed资源/条件热更新消费者接入，不复制provider排序、不把本批静态正常图授为动态资格；rim动态值目前只局部关闭该项；用户provider/热更新尚无活动作者首错，不抢已证世界模型消费者。 |
| Shader 双 stage 同名值边界 | 自有真实编译反例：vertex varying carried 与 fragment uniform carried 各自合法，但原 GenericSourceNormalizer 将统一 uniform block 注入 vertex，实际 strict link 为 redefinition；本批隐式 varying 链接保原声明，不授两后端健康。沿原 stage resource/ABI 投影区分作用域，保共享 uniform 的类型/布局合同，以 actual authored link 与 normalized/Metal 正反例纠正；未得活动作者命中，不抢世界模型可见缺口。合法声明与函数放同一行另触原 declarationUnsupported，不能将换行当语言许可；两项各由原声明/资源投影纠正。失败归 `.artifacts/scene-model-phase-20261114`。 |
| REFRACT直接光照 · 3590684440四层 | 392/526/809/830 的同帧两盏现代点灯已供，hidden534 不计活动分母；无模型 caster 需求不授官方无阴影。四层实际为正交 worldSpace SpriteTrail，shader eye/right 未资格；view 逆原点受裁剪深度影响，几何 across 也不等于已证 source right，故停止放行与 shader 迁移。Mirage 仅作线索；先取得可区分的官方 host/normal 基与直接光、shadow 供货，沿原 LightSnapshot/材质消费者接入，不重调旧四区灯/法线。已闭 ambient/CUTOUT 归[原证据](../capabilities/runtime-evidence-current.md#particle-cutout-coverage)，本次候选和停止线在 `.artifacts/scene-particle-lighting-next-20261108/`。 |
| 启动仍慢 · 3808922316 | 90秒超时及死亡搬移、无消费者payload、无writer reset、算子重复工作、raw initializer热复制已退出待办。默认隐藏主题仍完整预热；现同输入优化诊断App预热18.12s、Ready24.05s，资格归[预热热路径](../capabilities/runtime-evidence-current.md#particle-prewarm-hotpath)。随机区间算术成本不足；raw Operator ordinal候选未过交错计时收益门；归一寿命bulk LazyMap候选在唯一编译中新增每步56B heap closure，按预定ASM门撤回，0计时/0测试/0App，原49输入及产品已恢复。三方向无新证据不续做，不以ASM/行数减少授收益。重启仅看当前优化机器码/阶段采样的新可移除完整工作或新官方活动创建事实，不跳隐藏/root、不减时长/步数或改RNG，不重开已退双链。 |
| 通道与操作推导 | 完整向量输入已退次数许可，实际颜色采样/显隐见[运行证据](../capabilities/runtime-evidence-current.md#whole-vector-color-input)。剩余alpha-only/packed、有序signal和无typed颜色兼容仍有有界source事实。终端storage可继承未读data-FB声明，未注解资产raw意图未证，不能由output=data推输入解码。沿原冷准备汇合component/资源角色，保data、独立alpha与mixed-role反例，不追加效果名单。 |
| source fallback 的路径/摘要许可 | XRay固定路径/UI/摘要与Masks的Pulse/Blur/Waterwaves路径门仍有真实降级消费者；尚无当前作者被误挡的画面归因。现分支只接unclaimed且无frame target，不能借已认领Program许可；颜色来源/PMA不证明alpha与空间覆盖，归一blur即反例。本次停止实施；若续查只先资格Masks真实unclaimed的等价改名画面及source-coverage阻断，再决定原冷owner能否供完整事实并退旧门，XRay不并批。不造新coverage系统、通放base或补路径名单。正反例与停止线在`.artifacts/scene-source-coverage-20261108/`。 |
| material default动画入口 | 该存储位执行语义尚无作者/官方正例，不能仅凭AssetCatalog未parse认定冻结缺陷。先取合法default动画行为正控，再由原descriptor冷准备汇合material/instance有效值与definition-only pass identity，不让TargetCompiler重解资源或另建owner。 |
| Bool回调的剩余阶段边界 | 分离属性/媒体前缀、同C entry中due timer到真实值回调，以及直接值入口的隐式init到update已沿[原owner](../capabilities/scenescript-api-coverage.md#boolean-callback-order)交接；无update保真实事件setter。实际App与native范围归运行证据，不外推为所有阶段已隔离。cursor/media等事件自身先读getter仍未取得pending-init供货；Puppet/video-ended混合返回、嵌套回调完整次序及真实video EOF身份仍未闭。沿实际调用与typed消费者核首错，不重放旧setter或添加持久显隐副本；尚无这些剩余边界的精确作者活动资格。 |
| named 冷准入与图来源 | 2972071249/313e9读默认隐藏的234效果图失败，前九段健康。[官方prefix](../capabilities/runtime-evidence-current.md#prefix-source-qualification)的省略/true/false均绿，待可区分provider/epoch，保当前STOP。冷候选用renderOrder，utility执行用展开顺序与trigger，background consumer排graph，同trigger普通来源→utility未接。其余沿实际活动slot/来源和ROI起证；已有范围见 `.artifacts/scene-named-candidate-next-20261109/`。 |
| Childless utility 的显式背景来源 | 当前Project false取main、Composition false取isolated空源，仅为SourceRoute/原生结构事实。[正控](../capabilities/runtime-evidence-current.md#childless-source-qualification)停在PNG与native采集不一致，三场及Mac未跑，stock清alpha也未证copyflag映射。先恢复同窗采集，再核真实source/最终取样，不由旧路由或单路图预选修复。 |
| 模型动态准备的剩余组合 | 父组热显隐、冷 Bool 与外部 Script setter 的原 source/Program/tintback 已沿[原模型消费者](../capabilities/advanced-object-coverage.md#model-subtree-raster)取得有界实际资格；初始关闭 effect、任意 utility/材质组合仍未由此覆盖。外部非 Bool 材质 writer 的 layer-access 需求仍未汇合到原 Document/RuntimeInput/Launch 的全场景准备判定，这只是静态来源边界，尚无作者首错资格。沿实际需求补原 owner，保 child false、局部坏模型、source/Program 与同 key 事务；不重开已退单 leaf 例外、另建 ready 状态或把冷颜色链授为深度/官方像素。 JSON image已解析但kind.model且无.json后缀的名字不在原初始候选数组，本批只补kind!=model成功名；尚未核原Script analysis是否消费此域，不授全部Script-only模板发现，也不为猜测加名字索引。 |
| 分组临时目标的在途复用（源码边界） | [通用临时纹理](../capabilities/model-runtime-evidence.md#depth-submission-order)已按真实队列/逐pin供货减少样本池峰；独立compositionGroup入口仍维持原同CB判定，本批未授跨CB复用。后续须该入口的实际分配/消费者证据，再沿原Entry归并，不全局放宽Context.accepts或新增缓存。 |
| Composition 内 REFRACT 取样域（待证） | [2860569355 的普通混合波纹已修复](../capabilities/runtime-evidence-current.md#particle-refraction-normal-2860569355)。根层正反向 screen-UV 色卡已对照。组内需要可区分的背景范围及透明目标 alpha 对照再改；官版现有 alpha 读回校准失败。 |
| Child控制点绑定与声明位义 | 无CP读取的leaf走[原事件消费者](../capabilities/particle-component-coverage.md#child-declaration-options)；非零未解释声明flags遇到真实reader或子树时仍只拒对应template，不回退默认CP。官方CP分支白/蓝目标重合，parent-particle供给与declaration位义未资格，不能套root General world位或由无CP等价宣全部flags无效。沿原typed需求和绑定源补消费者，保父/健康peer与现有static raw-parent copy；不新增flags组合许可。 |
| Rope A2C可见轨迹 · 3807668787/958 | 重复同位采样的共享单UV已按[逐span官方对照与实际App](../capabilities/runtime-evidence-current.md#rope-958-sampling)修复并退出待办，非重复控制不变；两个真实root同帧main-color/GPU与局部FX均通过。原作者A2C/弱端点信号仍不足完整轨迹资格，378含child的可见线也不授parent专属像素。后续只凭可区分的作者precoverage/活动输入证据续查；省略默认、官方曲线仍unknown，不重跑旧端色、相位alpha/LOD矩阵或增MSAA/resolve，不将本次UV修复说成完整作者轨迹恢复。 |
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
| 条件脚本需求 | 2932157836/299e1、2857410102/91e3仍未取得活动需求，默认hidden/未触发不能判执行故障；先取得真实writer或官方活动条件，不重跑未活跃metadata。已闭合的288 Property事件、材质输入、Single创建与Cursor运输退出待办，当前资格及完整翻页/默认参数上限仅归[运行证据](../capabilities/runtime-evidence-current.md#image-single-animation)。官方Single窗口native捕获已STOP；通路未恢复前不重复同失败实验，不据shader产物调算法。 |
| 活动shader局部降级 · 3042492564 | 既有受控media+mclick_interaction=true的旧诊断App中，339/e3为AA编译失败：作者两个`<=640`分支内缺分号，上游实际640²，补Resolution成员仍不能避开，目标dialect未资格，不补作者源或定论作者错误。363/e0首pass两个hidden sampler无binding/default，BLURALPHA0实际读1.alpha，旧门先拒slot0；[唯一官方控制](../capabilities/runtime-evidence-current.md#unbound-sampler-control)的A/C/D及probe标记均失败，缺省来源保持UNKNOWN，不追加第二版、不放通all-hidden/白图/零图。重启先有合格source/effect载体与可区分绑定，保局部fallback；资料在`.artifacts/scene-active-shader-304-20261108/`及`.artifacts/scene-unbound-input-control-20261108/`。 |
| addColor String seed · 3662390671/793 | `textColor`的builder与wrapper都是String，setter读取x/y/z失败；默认showfpscounter=false且R0没有该层末帧消费。RGB255的有限Vec3修复不改变此类型；待官方String-seed正例或合法Vec3输入后重启，不按addColor名称强转、补默认值或重复PCM/旧矩阵。输入与停止线保于`.artifacts/scene-script-color-next-20261108/`。 |
| 作者脚本与VM边界 | 逐subject证据见 `task/r0-script-event-index.json` 及新增筛查。2890473419写未赋值目标、2982559622把Vec3返回alpha；372/373/336默认hidden，`thisLayer.position`别名未知。3605722997合法delay已通过。3610154602、3685613416播放器脚本引用未提供的图层或祖先；3779026256待裸scriptProperties的官方factory合同。3776234514/3776265228共用脚本向自身文本层取动画，3124752752异常来自默认隐藏文本。3799916029/3813261294/3816114461/3844234486共用alpha脚本，写visible后返回Bool。本机拒绝返回并丢该owner写入，官版[标量合同](../capabilities/scenescript-api-coverage.md#contract)仅确定保alpha。以相同显隐setter配Bool/undefined/Number核实际显隐。 |
| 缺输入 · 3736952187、3763323436 | project.json不存在，未启动App；补合法输入后再跑，不作引擎失败。 |
| named demand · 2069136288、3395777145、3829467967 | 默认未达静态planned的目标没有当前active consumer。3476868923/533 effect inactive。先取得真实writer/活动需求，不要求默认帧执行所有潜在capture，也不以此解释主景像素。 |
| 粒子预热CP · 3799613625/321 | 失败归static child0/system1 red_fire emitter0预热，非root。当前开启cursortrail并供inside pointer后，同consumer live出生及所选child Sprite/main/GPU已成立，见[运行证据](../capabilities/runtime-evidence-current.md#coverage)；冷缺历史pointer不授持续播放失败，不删除CP有效性边界。只有outside后PNG，逐像素轨迹与完整交互仍未资格；不据旧预热诊断继续扩修。 |
| 来源阶段读口 | 3820309850、3843933474 的17层在首帧 `layer-source-not-ready`，随后同层GPU完成。其余恢复或转hidden见[复测](../capabilities/runtime-evidence-current.md#coverage)。重启须具体活动slot持续失供或画面证据。 |
| 纹理关联与最终贡献 | 全部声明有索引，但ordinary/geometry/particle部分实际draw未携带asset provenance，graph/provider引用也有未闭关联。不得解析Swift描述字符串猜identity；沿已存在Candidate/Resource carrier补最小typed映射。本轮3788897599的291/259 composition行`rendererKind=unknown`，定位`SceneParticleMetalPipeline+Frame`的可选debug字段及原component observation供货；复测先核现有按需观测输入，不由路径猜种类，也不将此元数据缺口判为绘制失败。单帧bind/GPU/tail不证明全部实例或最终可见像素，动态输入、材质与render-target的未观测阶段仍保unknown。 |
| 着色器类型回归预期 | `test_scene_shader_global_scope.test_float2_arithmetic_does_not_cross_unproven_expression_boundaries` 的 user-call/normalize 仍期待不补`.xy`，与现有typed复合求值后窄化合同冲突；同输入旧/新产品都补`.xy`。其余9方法通过、GPU独立项1skip；按真实类型与编译/像素修订这两条旧预期，不能撤回合法转换迎合测试。 |
| 粒子回归夹具体量 | `script/tests/scene/test_scene_particle_simulator.py`仍超过1000行，内嵌Swift准备/运行与多类组件断言共用大夹具；当前未达到自有代码行数与职责要求。按真实组件输入、共享准备与行为断言梳理现有fixture职责，保同一生产实现及独立失败反例，不靠wrapper、源码搬迁或复制模拟算法凑行数。 |
| 条件/周期分支 | 3768303048本轮manual day/night的122/109及夜雪59有效显隐已成立，day sticky unavailable59对应隐藏，不能判活动粒子失败；真实时钟与pointer未资格。3042492564原树click父链隐藏，派生media条件已供货且有click后738绘制，仍缺首次出生回执/无click对照，不授点击因果。3764725758/3830665420第二轮仍未知，长窗不代完整事件。 |
| <a id="legacy-gate-debt"></a>存量回归夹具与产品源漂移 | `test_scene_renderer_submission_stage` 的抽取夹具缺四个 composition trace API，冻结HEAD和当前五个源字节一致，实际同错编译，整门不计通过。`test_scene_preserved_channel_frame_local_unique` 的 `composition-consumer-external-refused` flag、`test_scene_resolved_material_pass_encoder` 的9项binary-archive、negative-cache及uniform-mismatch断言（同冻结Harness/工具链的HEAD实际对照与当时候选逐项同红，未改golden；独立N2 terminal9项实际全真后随候选退役，不能将聚合门标PASS）、`test_scene_external_primary_visual_failure_passthrough` harness 的 `providerResource`/`providerTexture` 标识符改名、`test_scene_resolved_material_program_derivation` 5 个 prepared-assembly flag——均需按真实产品入口/提交证据重定期望，非源集缺失；`test_scene_material_program_census` 在补 `PackageBacking` 闭包后仍会被 harness 内与产品重复的 `SceneResolvedMaterialProgram.PreparedAssembly`/`SceneTextureLoadPurpose` stub 顶住（本轮尝试已回退），需专门整理 census harness 与产品源边界；`test_document_registry`/`role_index` 曾因 Scene 引擎早期设计稿未登记而红，该文档已归档为历史证据；`test_scene_dependency_graph_output_runtime.py`原2680行内嵌Harness仍是存量长文件，本批发现但未改其业务，未收敛其职责；`test_scene_static_model_shading_gradient`两条旧depth>0/near-far比较在同输入old973f与候选985a均红，56行RGBA/depth精确相同，不能把它们报PASS或为过门改遮挡；沿原fixture相机/深度期望修订；后续按真实Harness归属整理，不以压行或门未覆盖Python冒已达标；保原提案，不擅升现役架构，也不为过门删除。依赖 gate 的 `SceneResolvedMaterialUniformProjection→DirectUserBindingContract` 边仍 open（搬迁实验会波及 fixture/source-set 清单，已回退；ratchet 拒绝 baseline 扩张），需专门设计批次；本批原scan复核HEAD/current同5边，两个相关源SHA相同，不重开搬迁实验。目录门本批实报`SceneTubeLightDefinition.swift`（Format）和`ScenePreparedDeviceResourcesTask.swift`（Runtime/Session）两项名称不在目录合同，相关源/布局/checker均与当前HEAD相同；后续沿原source-map owner修正命名或合同，不以局部模型修复授全门通过。DEBUG product-entry在全新隔离域附非空启动override曾issued=true却0daemon/首帧；无override沿实际诊断意图已成功，需复核debugRequestSceneRender对libraryPending/初始意图的交接，不判正常UI启动失败。366等比resize的4项FAIL已分为旧epoch allocation-reprepare取消与validator跨epoch基线错位；23/23图在新epoch同Program恢复，固定小图须重prepare不授真实新分配量；未采取消帧像素，保原失败，不称绝无闪断。沿真实入口逐个修或删除无独立价值断言，修后重跑对应 focused 组。 `test_scene_paused_text_integration` 的延迟栅格两屏门，文字setter修复前后签名Debug同一帧白像素51380，静态对照126191且三项完全同红。沿暂停的ready捕获和后续重绘时序追因，不改本轮setter验收。 |
| 缩放观测epoch · 3470948192 | 代表稳态model/main/export/seal/GPU与排空已健康；整轮仍保diagnostic、failed outcome、allocation reprepare和allocation identity四项resize观测失败。沿测量器实际epoch/storage身份修正，保真实错配负例，不从完整画面改报PASS；当前不是水滴视觉阻断。 |

## 需定向扩域的能力入口

下列是尚无充分当前输入资格的边界，不是默认短窗已证缺图；具体合同仍由能力文档拥有。

| 定位 | 下一步 |
|---|---|
| 管状灯的扩域与官方CP | 真实361罐体的stock g4/c4直接受光已由[实际像素](../capabilities/model-runtime-evidence.md#tube-light)闭合；当前局部CP有限线段是自有算法。官方仅Point正控即崩溃且无合格can画面，重启先修输入计数/包头资格及有效相机，不重跑原黑帧或据源helper授坐标。Tube阴影/体积/旧材质/Generic/image需各自真实消费者证据，不是本次直接光的硬前置。 |
| hidden/forward父graph named输出 | 可见、已可满足的普通image graph-final已有transform children时可复用原graph发布；hidden FX父仍在image来源谓词保leaf范围，forward可见来源仍受原执行期限准入。hidden claim/execute/named-only消费者已存在，需独立父子/多reader及生命周期对照；forward沿实际source独立性与作者位main期限核，不能由新visible正例裸开utility/Puppet或用raw替身。当前最新静态parent筛选无精确作者命中，保能力边界，不造默认缺图归因。 |
| source material · 3616476797/113、3679907516/71/74/83、3141464346 | 367原R0三层冷拒但TEX已到ordinary/effect→main，静态cover推算在左侧外、无当帧MVP/非等价ROI；重启须可见source及拖动/media相位错配，不由VERSION2/translucent推语义，原STOP在`.artifacts/scene-source-material-367-next-20261109/`。361/113为静态Media Area，不能混作130 thumbnail；314的277/719已有TEX→main、416/420已有source/effect→tail，232/321/386/481 authored隐藏。九层source state拒绝不授缺图；重启须对应活动pass/source与可见ROI非等价，不先放state或新跑，薄事实在`.artifacts/scene-source-material-next-20261109/`。 |
| static model / resolved render state | 任意shader、多pass与更广blend/depth/cull须原binding compiler和fullscreen/output用途资格；保深度、淡出与PMA。限定343/345/3477054430/355/358的44模型实例、25MDL、35实际引用材质均单pass，未证first-pass gate漏绘；多材质段已有逐段consumer，不把它作多pass缺图，也不重开已闭additive/透明caster。 |
| Puppet · 3577990983、3822822401、3779107475 | auxiliary/reference、非中性通道、dense state1及多contributor姿态按真实reference/attachment坐标基资格，Reader识别不等于evaluator执行。 |
| Script动态特殊资源与typed callback | 特殊Puppet/composition创建字段、3028048463的531.alpha空数组/506.origin分别核prepared catalog及实际producer；标量返回合同见 [SceneScript 能力文档](../capabilities/scenescript-api-coverage.md#contract)，空数组来源仍待 producer 证据，不造空实例或无差别容错。 |
| Script粒子scalar回调交接 | 相反自身setter/返回与隐式init后输入/getter次序尚无官方资格。原alpha探针已分清即时journal、附着返回和下一preliminary两路，不把本次input自动当getter基线；重启须官方顺序或明确的项目回调合同，再在原primitive/merge修正，不重跑已闭字段运输/模拟门。[`instance.size` 已接通](../capabilities/runtime-evidence-current.md#particle-instance-size-handle)，同回调与相邻update的显式出生分别验证，回调内getter即时；其他owner或init/timer的交接仍待证。原四case与STOP在`.artifacts/scene-particle-instance-fields-next-20261109/native/`，已接字段合同归[Particle instance](../capabilities/scenescript-api-coverage.md#particle-instance-scalars)。 |
| sampler宏声明接口 | canonical g_TextureN声明配宏采样read已准备通过；自有slot0将声明改为宏别名时，raw SchemaSeed未展开，unconditionalSamplers报authoredSamplerSchemaInvalid。当前没有作者缺图资格。沿原冷预处理/接口事实统一Schema，保真实slot/metadata，不新增别名许可表或忽略用途；后续资源目的仍需独立资格。 Generic host另缺MipMapInfo绑定；自有image探针local尺寸/采样正控成立，RT/default及两分辨率同码仍未授实际RT/mip/sourcecut，不作模型缺图归因。 |
| RopeTrail其余renderer字段 | 公共Worldspace与整数subdivision已沿原消费者接通，资格见[组件合同](../capabilities/particle-component-coverage.md#rope-trail-world-subdivision)。child尚无RopeTrail历史消费者，仅局部拒该输出，root多输出不授此能力。显式非正length仍拒绝；固定客户端静态最小值钳制尚无作者/运行资格，不能据此授完整history单位。非screen朝向、动画、size fading及UV字段各需实际消费证据，不以原flags误拒保留它们的整renderer许可。 |
| 粒子其他资格 | 2812808677 的classic Vortex 60/98/129缺参且已实拒，106四参有界，已出粒子绘制。用官版省略/显式/删算子同龄轨迹核缺省。另保CP/child空间、Mirror、nested/event、HSV缺省、Vortex flags2及absolute color各自资格。 |
| dormant视频与输出扩域 | 单可旁路effect的材质视频无用取图已归[现役合同](../capabilities/material-video-assets.md#inactive-material-frame-acquisition)，不重做。共享/named活跃需求与后台AV解码停用仍分别资格；重启须具体空需求开销及保持首个可见PTS/EOF的同链证据。物理HDR/EDR、lighting/receiver、文字backgroundbrightness与HDR8bit裁剪各保独立资格。 |

<a id="user-feedback"></a>
## 用户反馈与定向视觉资格

以下位置均不能由默认短窗截图裁决；复核时固定属性、声源、pointer、时间/相位、viewport 与 App。终端存在、主画面成立和具体 ROI 正确是不同资格，先找真实 consumer 与首个不同 stage。

### 世界模型优先复现

按可复现画面先查星球前后遮挡与主光照，随后核星轨文字。至少固定作者属性、时刻、相机及画幅，记录场景深度、遮挡体和发光体的实际 pass，区分看见背面发光体、Bloom 在屏幕上的扩散、星球没有受光和星轨文字未出图。

| 输入 | 当前起点 |
|---|---|
| 3437487219 | Cloud共同MR、颜色/HDR与pigment的自有受光合同已沿[模型正文](../capabilities/advanced-object-coverage.md#model-chroma-surface)接通，冻结云资产有可见贡献，退出这些具体缺口。旧精确受光、闪烁/collision反馈仍待同条件ROI/活动producer，不由noise或默认完整图关闭，不按旧参考调灯。 |
| 3455121165 | 107关闭深度的官/本差异仍需能覆盖字形的前缀见证，保留 opacity 与近远观察。[条件资格](../capabilities/runtime-evidence-current.md#authored-text-depth) |

### 基础画面与基本交互优先

| 输入 | 精确待核位置 |
|---|---|
| 条件 TEX · 剩余消费者（待证） | [作者基图及Puppet](../capabilities/runtime-evidence-current.md#author-conditional-mask-376)和[材质附属图](../capabilities/runtime-evidence-current.md#author-conditional-material-xray-374)的已测冷热选择已修复。动态构造和发射源需各自活动消费者，重叠条件次序及半透明图块细节待有可区分输入。 |
| 3187857248 | [原包单/双Surface拖动](../capabilities/runtime-evidence-current.md#puppet-drag-surface-318)已恢复双Surface脚本拖动，作者命中范围与小幅变形保持。若物理单屏仍间歇失败，先取原生真实按下点/当前骨位置、持有与释放，再核命中、骨写与末端。官版按键传输未获资格。 |
| 3781003282 | 中央白方[未重现](../capabilities/runtime-evidence-current.md#pointer-halo-378)。重启须可复现位置、画幅或桌面版本，再判888采样与独立395/e16。 |
| Puppet 后置标量轨 | [384与独立377的普通骨轨已恢复](../capabilities/runtime-evidence-current.md#puppet-post-bounds-trs)。同相位标量替换未证主要遮挡差。重启须有单骨/同位置的可见交叠对照，再分纯绘制顺序、骨权重或几何作用。 |
| 3383210272 / 3463406101 | [338321主束已出](../capabilities/runtime-evidence-current.md#floor-beam-continuous-emission)，角度、色相、节拍待锁相。[346双音回亮仍慢](../capabilities/runtime-evidence-current.md#forefront-recovery-346)，单音释放已核。续查同侧稳态混合和共同目标。 |
| 2814167871 /2835398595 | 眼部为132/e1与98/e0的pulse RGB增亮，16档band0/1均值跨.5才响应；281强度属性默认1、283常量.51。[默认PCM前5秒](../capabilities/runtime-evidence-current.md#eye-audio-input)无跨线正控；后续同作者WAV的281两App静帧已有真实16档消费，但不能判眼部闪动或闪烁。粗档候选已撤回，283不追加矩阵。重启须可裁决实际供值/首错，再核同帧pulse→tail→眼RGB；不调gain/作者参数、不强注入1，不由bus非零关闭。 |
| 3603711180 | [播放媒体的原包与两端实帧](../capabilities/runtime-evidence-current.md#author-player-text-current-360)恢复标题、艺人、剩余时间和实际封面。已测画幅首行同在左框外，观察其他比例/第二行与字体差异须用同视口同媒体复取；按原屏幕锚与字形范围核对。 |
| 2887099508 · 图5 | [黑纹](../capabilities/runtime-evidence-current.md#basic-interaction-288)未重现，待同相位ROI或具体版本。原生持续悬停待合格输入，仅在出现可重复的命中问题时复核。 |
| 2999907577 | 旧终端主体完整，大片背景灰与有效默认tint相符；876e6流体的执行不授像素贡献。后续只在需要时用现有selector7→8(None)定位白弧/流体贡献，不按preview判缺纹理。 |
| 3436945972 /3463406101 /3443450456 | 分别偏暗、暗绿配色及灰白底黑字；同亮度、遮罩、配色/时段与音频输入后定位writer。 |
| 3498814983 /3605722997 /3827673174 | 前后两项当前目录已移除，保原反馈为输入不可用；360572当前可运行。头脸取景仍须固定横屏camera/cover/平移与作者画布，portrait preview不能证明投影错误。 |
| <a id="puppet-morph-peer-fallback"></a>3504669359 | 默认四秒旧强白圆未重现，固定圆核及材质/终端边界见[运行证据](../capabilities/runtime-evidence-current.md#coverage)。身体166的三个普通叠加槽已从共同解析失败中恢复实际骨骼动作，见[原包与固定相位对照](../capabilities/runtime-evidence-current.md#puppet-prebounds-curve-evidence)。clip700接入后已在实际合成重现闭眼与睁眼，[固定相位和独立作者](../capabilities/runtime-evidence-current.md#puppet-mdmp-oracle)通过。形变扩域按[能力边界](../capabilities/advanced-object-coverage.md#puppet-mdmp-morph)等活动输入。 |
| 2982559622 | [竹林→池塘](../capabilities/runtime-evidence-current.md#coverage)已出图。两次[首次激活](../capabilities/runtime-evidence-current.md#initial-material-video-ready-298)都已消费111的原视频，早期未供退出待办。103.alpha的Vec3错误返回及111/94冷准入仍开放，重启须合法附着回调/视频句柄或新可见失败。 |
| 3034166869 /3223543799 | 其余 effect、媒体与完整画面；常开音条与条件隐藏分开，不凭短窗结构状态实施。 |
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
| 1315486372 | 光线宽软、渐隐及水波位置。 |
| 3769761761 | [持续力](../capabilities/runtime-evidence-current.md#particle-continuous-turbulence-field)及[振荡](../capabilities/runtime-evidence-current.md#particle-scalar-oscillation)已修复。[同龄复核](../capabilities/runtime-evidence-current.md#ember-mature-trail-luminance)已核静止Box、未裁轨迹方向和高速短Trail限长。右区非零面积相近，亮段分布仍异。续查须共同位置/权重下的首错。 |
| 3113287126 | 小提琴方向/密度反馈仍开。原R0五活动root均到main/GPU、无child，全随parent500；Directions普通量/默认，旧bounded不作缺图，当前未见可证重复world转换。重启须明确root/ROI、发射与父Puppet同phase及当帧pos/vel→attachment/model/VP，不能由单图或几何实例数调count/speed；薄事实在`.artifacts/scene-violin-311-next-20261109/`。 |
| 3743305891 | 原R0活动十字为child1的22个Sprite几何实例；root/child各取自身size空间flags，child2.5与父layer10是不同声明，当前静态消费链未见同一scale重复乘。缺同phase尺寸oracle与当帧instance.size/MVP，反馈仍开；重启须官方子world继承资格或可归属size/空间→像素错配，不调size拟合或无差别重跑。原输入、三batch/main/GPU及链路在`.artifacts/scene-cross-size-374-next-20261109/`。 |
| 3768229922 /3770444459 | 376原R0的4秒片头与16秒后续均未定位黑滴ROI；1103/1144玻璃各30实例、color/normal/background→main与GPU已有实际供货，不判完全未执行。反馈仍开，重启须明确哪颗/哪个ROI、相位和对应活动source，不追加无差别第三场或由名称推PMA/混合；薄事实在`.artifacts/scene-droplet-3768229922-next-20261109/`。377主体/眼部完整过渡仍须同相位合成ROI。 |
| 3768724269 /3287715210 | 前者的光束范围/根部/右上渐变仍需定位；后者旧眼周/横移细竖纹尚无同条件native差异。[328体积开关STOP](../capabilities/runtime-evidence-current.md#point-volume-328-stop)未给出明确可逆贡献，85不再列优先归因；不由旧反馈扩正交/阴影合同，不原样补跑，待新的明确ROI/贡献。 |
| 3750813609 /3363252053 | 相机过强/纵向反转的同输入体验；375另核时钟颜色、雨量与雷电。 |
| 3747492842 | 闪烁/光束位置/crop/文字构图。 |
| 3248220186 /3337494481 | 前者[官版深度语义及文字叠加](../capabilities/runtime-evidence-current.md#author-clock-sprite-depth-324)已恢复，背景色、光晕强度和相位待同条件对照。后者[侧字透盒已恢复](../capabilities/runtime-evidence-current.md#author-box-text-occlusion-333)，扁盒、粉顶与solid亮度分别待画面对照。 |
| 2938612768 /2775915974 | 293默认裁屏已沿[原文字与画幅](../capabilities/runtime-evidence-current.md#text-screen-anchor-viewport)定位，重启须点击/更晚相位的具体新差异，不重复默认移位对照或改anchor；277顶部灰边仍须实际画幅/图层与相位资格。 |
| 3712499998 | 作者明确声明21→22、28→29、33→34三对文字，子层有独立近邻位置及压缩Y scale；原R0六层均有效visible，不能将副本文字直接判引擎重复draw或删child。样式反馈仍开，重启须具体glyph/geometry/样式差异及同viewport/phase消费者或官方参考，不重跑原默认短窗；薄事实在`.artifacts/scene-text-pairs-371-next-20261109/`。 |
| 3477054430 | [本轮短窗](../capabilities/runtime-evidence-current.md#rescreen-recent-inputs)月亮、猫、耳机与楼体完整；紫月边对应默认moonlightcolor及同帧u_Color，不立配色缺陷。完整运动、低频响应与受光仍待明确同条件ROI，不重复默认整景。 |
| 3764725758 /3549827466 /3581882134 | 左斜光/眼睛漂动、缺光ROI与暖亮/冷暗来源。 |
| 3723344874 /3793998447 /3792249095 | 人物后烟雾涡动、音频属性差异、外圈样式及内外位置。 |
| 3042492564 /2932157836 | 光束/右裁切/blur/布局/媒体交互、精确spin及媒体仲裁。 |
| 3233141951 | 脸/龙/小人/刀轨迹与双色音频仍需同phase、具体ROI和对应活动producer；不由单条动画选择恢复关闭其余反馈。 |
| 3807668787 /2684431262 | 958 A2C/pointer轨迹、发光与整体合成。 |
| 3264246690 /2131872317 | 人物边缘AA/警戒带运动、蓝烟花上升/逐子出生空间。 |
| 3780119725 /3769364482 | 人物地面/摩托中层pointer及光照、Shake Breathing与发光突现。 |
| 3219398263 /2932631210 | 漩涡方向与背景，分别固定ROI，不能共改符号。 |
| 3028090166 /2419444134 /3113554287 /2304304373 | 光束、白点密度、顿挫、雾气叠加；低优先，先补当前输入。 |

<a id="performance"></a>
## 已实测的性能问题

| 输入 | 当前证据与重启条件 |
|---|---|
| 密集预热 · 3337494481 | [原包交错实测](../capabilities/runtime-evidence-current.md#particle-turbulence-borrow)确认签名优化态可启动，普通Debug超时仅限该取证配置。单root去隐藏轨迹的隔离计时重叠，候选退出。实际首屏仍以完整预热为主；继续依据可移除的工作，保作者时序、随机、历史和首帧。 |
| 3749463715 | [现役历史结算唤醒](../capabilities/runtime-evidence-current.md#gpu-admission-wake-374)已降低等待。[末端消融](../capabilities/runtime-evidence-current.md#terminal-main-ablation)每帧去掉五个离屏材质，实呈与GPU时间持平，候选已撤回。后续只追有新证据的显著成本，保跨帧历史与回滚；不重跑末端消融、不放宽容量或按重叠时戳删材质。 |
| 3420215721 | [同包实测](../capabilities/runtime-evidence-current.md#scene-playback-triage-342)确认 GPU 超预算，稳定帧 history split 已减少 seed copy。[运行时失败反例](../capabilities/runtime-evidence-current.md#stale-history-seed)补查历史保持；后续只补同 scene-time 像素 A/B、真实 descriptor/reset 与 activation 切换的未覆盖范围，不重复已有效的构建和稳定帧测量，不增 pin 或 history owner。 |
| 3673609113 | 续等、零覆盖、HDR末段及[截取合并](../capabilities/runtime-evidence-current.md#shared-capture-material-pass)已验。GPU仍超预算，保两级作者历史。 |

测量与退出规则只归[性能方法](performance-convergence-card.md)，本表不沿用旧实验数值或认领收益。

<a id="properties"></a>
## 属性与工具资格

11-07定向复验归`.artifacts/scene-problem-retest-20261107/`，该轮746个可解析输入及旧635集合的差集由selection/input-drift收据维护。未触发的属性、周期及ROI仍待资格。

| 定位 | 下一步 |
|---|---|
| 注解材质与被忽略的直接绑定 | 同属性还写有效目标时，未选GLSL名会阻断热更新。以合法双写验证保窗口和实际准备失败。3833869818未定义对应面板键，[玻璃已修复](../capabilities/runtime-evidence-current.md#material-annotation-keys-3833869818)。 |
| 全屏具名依赖显隐 · 3842633043 | [启动与默认闪电已修复](../capabilities/runtime-evidence-current.md#utility-capture-admission-3842633043)。播放中关闭 `lightning` 被拒，604的visibility未准备。沿原显隐owner取得已接两路具名输入的关闭与恢复，核同窗GPU及两路按需供货。 |
| 属性面板 | 总打开/编辑延迟、长Combo完整显示、系统键盘路径与更多locale需实际可达控件。保原始key/value/条件，翻译只改展示；完整段落、只读说明和reset入口不能因优化丢失。 |
| effect 显隐 / history | 同 scene-time 像素 A/B、真实 descriptor 变化与 349 类 activation 切换仍需实际 App 资格。运行时材料失败的已提交历史保持、首帧/reset 与 capability-level 反例归[运行证据](../capabilities/runtime-evidence-current.md#stale-history-seed)，职责归[history 合同](../capabilities/render-graph-shader-coverage.md#history-read-write-split)；不把重建透明内容当成历史保持，不另建 owner。 |
| text size | VM catalog size与排版logical extent是不同事实；setter后可见时机与padding/装饰需真实行为，不另建排版owner。 |
| 预处理成员 · 2819633264 | 未知成员按0的当前实现与横/竖分辨率、宏成员/空白等价行为需区分输入。 |
| presented / performance 记录 | 实际GPU完成与系统呈现分开。3822608807、3842434470的后台短窗有合格鼠标帧，普通检测分别缺呈现流数量与interval身份而整轮CHECK。沿present callback核短窗/多Surface呈现；独立视觉任务须能单报画面结论，终端PNG不能授权性能对照。 |
| 自有ABI与验证载体职责 | `SceneQuickJS.c`仍2801行，是自有适配而非第三方源码；既有domain/owner、输入和typed调用职责须收敛，不能以第三方豁免、搬行或新增wrapper宣称达标。`test_scene_generic_shader_program_artifact.py`、`test_scene_dependency_graph_output_runtime.py`及`test_scene_particle_simulator.py`也仍超1000行，混有内嵌Swift壳、legacy与跨主题probe。沿真实结果生产职责退重复和失效部分，保ABI、原字节和像素oracle；当前CodeHealth只覆盖Swift，不能授C/Python全语言合规。局部门及时输出编译失败，不等待长suite结束。 |
| capture · 3766415113 | 普通capture需实际窗口frame/时机资格；本轮Metal终端PNG不覆盖普通截图入口。 |
| 周期终端截图与收尾 | 366首15 A有8次superseded，后续四矮行星B在teardown拒绝series-0011/request14，均使整轮采集FAIL；已选各目标HOLD内的成功帧不受此自动否定，也不能将整轮改记PASS。沿原截图请求owner核周期请求与结束排空，只在有实际目标缺帧时补对应目标，不为采集失败改播放或延时重跑全轮。 |
| 官方原生采集 | [原作者窗](../capabilities/runtime-evidence-current.md#beam-contribution)已复核刷新，当前仅定性。量测仍须沿[采集方法](../../../.agents/skills/mywallpaperx-maintainer/references/parallels-official-oracle.md)取得有效同窗像素或实际draw数值；黑图和相机getter不能授几何资格。另零指数×10/真实改名控制在本地保完整球与peer，官版却放大填满窗口，未取得同投影/完整载体；该case退出官方尺度对照，改用同geometry的纯改名控制，不据此判相机产品错误。 |
| 自有9000000015 | 90/91/92健康peer须有真实texture source及可区分ROI，先资格夹具，不能借主文字/clone输出代peer。 |

属性接口归[输入与属性](../capabilities/runtime-input-property-coverage.md)，工具按当前实现与输入资格复现。已解决的反馈子项移到页尾。

<a id="resolved-user-feedback"></a>
## 已修复的用户反馈

11-24 反馈以现象为单位标记。下列已验证项默认跳过，有新同条件回归证据再重开。同样本剩余问题沿上方队列，截图、身份和验证边界沿链接。

| 样本 | 状态与已验证范围 |
|---|---|
| 3653620838 | 已修复内圈运动、轴向/半径、初速、尾迹、HDR出生亮度及 Project 光效栅格。外围和时相仍开。[运动](../capabilities/runtime-evidence-current.md#vortex-axis-world-365) · [合成](../capabilities/runtime-evidence-current.md#project-framebuffer-resolution-365) |
| 3612940332 | 部分修复。已修复静态几何宽度、末材密度、已测环周反差、共同起音、强档限步及所测音乐左弧的主要形变，已核1512×818固定输入全环。余量与复验范围见上方。[合成](../capabilities/runtime-evidence-current.md#author-ring-project-prefix-blend-361) · [供值](../capabilities/runtime-evidence-current.md#author-spectrum-near-target-release) |
| 3822067395 | 已修复。原包可启动，首帧及相关效果已实绘。[首帧](../capabilities/runtime-evidence-current.md#tex-alpha-channel-priority-author) |
| 3174321827 | 已修复。部件回到正确组装姿态，双臂和武器在胸前，细微姿态残差有独立证据。[组装](../capabilities/runtime-evidence-current.md#puppet-counted-reference-317) |
| 3823864170 | 已修复。拖尾跟随鼠标，默认与可选尾迹通过跟踪、颜色对照。[运动](../capabilities/runtime-evidence-current.md#pointer-zero-angles-author) · [颜色](../capabilities/runtime-evidence-current.md#neutral-mask-trail-382) |
| 3453730450 | 已修复右箭头和雾的深度及出生。灰纹随月球转动，两端都有固定点灯光晕。[箭头](../capabilities/runtime-evidence-current.md#moon-arrow-and-veil-345) · [灰纹与雾](../capabilities/runtime-evidence-current.md#moon-surface-pattern-345) |
| 3454689854 | 部分修复。主薄丝对比已恢复，默认不显示环字与官版一致。其余丝层另核。[薄丝与环字](../capabilities/runtime-evidence-current.md#silk-capture-density-345) |
| 3248220186 | 已修复。球内时钟合成恢复官版残显，球体正确遮住钟旁粒子。[文字与球体](../capabilities/runtime-evidence-current.md#author-clock-sprite-depth-324) |
| 3603711180 | 已修复。实际媒体标题、艺人与剩余时长已接入文本，真实系统封面已同帧验收。其它画幅另核。[播放器](../capabilities/runtime-evidence-current.md#author-player-text-current-360) |
| 3228084178 | 已修复音条周期性近熄，静音保无柱。196散景恢复双侧。[音条](../capabilities/runtime-evidence-current.md#author-led-placement-tail-322) · [散景](../capabilities/runtime-evidence-current.md#box-birth-distance) |
| 2868108515 | 已修复。锁链左侧规则叠影已消除，链条和正常雾层保留。[局部光效](../capabilities/runtime-evidence-current.md#author-chain-godrays-local-grid) |
| 3141464346 | 已修复工作栅格和弧线曲向；原摆位裁切一致。已验证同宽谱双环随声出现、静音退场。若再见细节偏差，须同相位的实际振幅与末端画面，无需复跑已测几何与显隐。[双环](../capabilities/runtime-evidence-current.md#ring-cover-314) · [声音对照](../capabilities/runtime-evidence-current.md#ring-audio-response-314) |
| 3382111183 | 已修复缺条及普通 SDR 材质增亮过量。原曲六层实绘，已测条纹反差与官版接近。密度与节拍仍开放，续查须同相位图及实际 emitter，不复做出生或增亮矩阵。[出生](../capabilities/runtime-evidence-current.md#floor-beam-continuous-emission) · [材质亮度](../capabilities/runtime-evidence-current.md#particle-material-gain-sdr) |
| 3673609113 | 部分修复。空跑、HDR末段与截取冗余已修，GPU仍超预算。[残影](../capabilities/runtime-evidence-current.md#author-motion-history-367)属作者合成。 |
| 3187857248 | 部分修复。双Surface拖动失效已修复，物理指针若仍间歇须新输入证据。[拖动](../capabilities/runtime-evidence-current.md#puppet-drag-surface-318) |
| 3766299002 | 已修复。面具属性正确选择纹理并保持眼部同步，两主题均验。[面具和眼部](../capabilities/runtime-evidence-current.md#author-conditional-mask-376) |
| 3747492842 | 已修复 X 光样式的初始选择与实时切换。官版和本机同点心→圆→回心，星形及闪光形本机已实绘。闪烁、光束、裁剪及文字构图仍见上方各自条目。[实际画面](../capabilities/runtime-evidence-current.md#author-conditional-material-xray-374) |
| 3586705329 | 已修复。拼贴右缘错误回卷，两档镜头缩放均验。[拼贴](../capabilities/runtime-evidence-current.md#author-collage-edge-358) |
| 3708363772 | 已修复[封面与实体错动](../capabilities/model-runtime-evidence.md#model-composition-cover-370)、[同色壳体受光](../capabilities/model-runtime-evidence.md#legacy-generic2-model-lighting)及[封面多色排序与缺位](../capabilities/runtime-evidence-current.md#media-palette-hue-ranking)。同PNG五角色和原包156消费已核，独立作者状态字变蓝。重启须有解码/重采样引起的新可见差异。 |
| 3337494481 | 已修复。盒体侧背文字不再错误透出。[文字遮挡](../capabilities/runtime-evidence-current.md#author-box-text-occlusion-333) |
| 3509243656 | 已修复。轨迹打开后进入原作者发射和绘制，关后停止，再开恢复。[属性热切](../capabilities/runtime-evidence-current.md#author-normal-depth-trails-350) |
| 3769761761 | 部分修复。已修复斜光主要缺失、预热、缺省初速、出生方向、持续空间力及透明度振荡。成熟右带亮段分布待查，范围见上方。[出生](../capabilities/runtime-evidence-current.md#ember-birth-scene-simplex) · [同龄复核](../capabilities/runtime-evidence-current.md#ember-mature-trail-luminance) |
| 3842265910 | 已修复双瞳缺失及身体普通骨轨。后置标量仍开放。[双瞳](../capabilities/runtime-evidence-current.md#puppet-pupil-color-order-384) · [身体](../capabilities/runtime-evidence-current.md#puppet-post-bounds-trs) |
| 3372715909 | 已定位。原包时间和日期被作者重建的全屏视频覆盖，测试副本调层序后恢复。官版原包此次无对照画面。[时钟与层序](../capabilities/runtime-evidence-current.md#author-clock-video-order-337) |
| 3306942838 | 已修复头肩主要脱节。官版与本机同画幅同相位实绘，正向横移差≤1.1 px。[头肩](../capabilities/runtime-evidence-current.md#puppet-head-phase-330) |
| 3455121165 | 已修复。11-25 修正只读加色粒子隔断背景排序造成的回归，原包默认排序下钟下音条恢复。[实绘与官版排序对照](../capabilities/runtime-evidence-current.md#native-composition-audio-prefix) |

已核官版表现也可复用。3769688830 默认玩偶会持续自转并随父层摆动，属性可关闭自转。3351163962 在已测相同较窄画幅两端时钟均出圈。3617449489 的白色音频环在现行原包两端均未见。3781003282 的红尾两端均跟随，中央白块未复现。这些现象有新触发证据再查。[玩偶](../capabilities/runtime-evidence-current.md#orb-spin-parent-motion-376) · [时钟画幅](../capabilities/runtime-evidence-current.md#text-screen-anchor-viewport) · [白环](../capabilities/runtime-evidence-current.md#preview-ring-361744) · [鼠标拖尾](../capabilities/runtime-evidence-current.md#pointer-halo-378)
