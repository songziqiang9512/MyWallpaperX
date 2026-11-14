# 模型运行证据

<!-- document-role: current-state -->

<a id="scope"></a>
本页是 Direct/StaticModel 的命名输入、材质、相机深度和局部合成运行范围的唯一证据正文。目标与当前能力归[模型合同](advanced-object-coverage.md#models)，待办只归[开放队列](../roadmap/scene-open-breakpoint-queue.md)；其它系统及通用限制见[运行证据索引](runtime-evidence-current.md)。每项结论绑定具体构建与输入，较早的限定运行不授当前未执行组合。

## <a id="nested-model-albedo"></a>模型两级颜色供货

3557068717 原project/pkg、3024×1964、当地18:57:13，旧签名exe `4b8b07a5…5da9` 与新 `6720e5d0…48fc` 的F972均完成、零截断并排空，metallib相同。旧237无draw，新424先供420，420发布并绑定237，选中帧237进入主目标。1280×831终端图的北美、南美区域暖色像素0→1982、0→603。日面见[点光衰减](runtime-evidence-current.md#point-falloff)。原生夹具的原名/改名、运行中退役直接上游与旧独立供货均通过，独立3470948192 F972保93发布、115绑定和draw。Debug构建、最近计划与自有shader四方法通过；相邻43项中两条几何/父层候选断言在未修改HEAD同样失败。Windows参考为18:57:00且画幅不同，仅作视觉参照。定格遮挡基线保留。收据归`.artifacts/scene-world-model-first-20261109/evidence.zip`。

## <a id="world-model-sample-triage"></a>星空样本定向复跑

3455121165原包普通预览 `a7b5879d…2f04` F953已编码107/199→main，GPU完成/零截断；296淡入uniform近1不证明glyph/投影。原收据归`.artifacts/scene-evidence/runs/scene-world-followup-normal-20261109/`。3453730450旧 `359404fb…c9e3` F967平灰；2026-11-14现役签名Debug `e4cc1a67…daf57` 唯一20s/after17低观测场，3024×1964的F964/request1捕获与seal同CB/纹理，GPU完成/零截断并排空，1280×831 PNG见受光月球、轨道、星点、标题与时钟。未授parity；证据/独审归`.artifacts/scene-terminal-345-20261114/`。

## <a id="model-screen-reflection"></a>静态模型屏幕反射

[材质及历史合同](advanced-object-coverage.md#static-model-screen-reflection)。3470948192原包、同画幅3024×1964及固定墙钟，签名exe `a7b5879d…2f04`→`316b1116…6959`，新metallib `5dac46d7…f8a2`。自然场景时间F970→F960，93先供115，模型14在同一主画布读取F959完成的环境颜色，GPU完成、零截断并排空。1280×831终端图上沿luma 0→20.56、尖端0.06→112.11、暗心0→2.42，星线仍被遮挡。独立3455121165 F972双跑，84反射强度为零且保持绘制，太阳397保持。原生开关、零强度、改名、尺寸切换首帧与稳定帧、模型深度和原图像历史邻例通过。官版2.8.0.42在原设置的一字节开→关→开证实灰紫轮廓随反射改变，输入相位和尖端强度未配对。收据归`.artifacts/scene-world-followup-20261109/evidence.zip`。

## <a id="model-startup-366"></a>静态模型接口冷准备 · 3662790108

原三摘要，签名优化App `b00688c6…384d7d`→`95c835c6…d3dca0`，metallib字节相同。旧准备线程采样743栈点中560在静态模型材质绑定编译（539在接口证明），顶点读取13。相同原包351个模型pass只用1份合同与8组完整combos。两对串行无采样实测，默认model-build 7.039→2.736秒、首GPU（从accepted）10.998→6.861秒、Ready 11.670→7.566秒。关闭作者片头的同设置对照分别7.493→2.690、11.540→6.687、12.202→7.348秒。四次570条material pass描述完全相同，含341接纳、10回退与8个默认slot0。原生绑定11项和取消门通过。相同SceneTime3，四次捕获均实际编码相同10个模型层，片头RGBA一致，正文仅右侧控件一条窄区不同。独立3589454154同原三摘要，11个模型材质接纳，土星环462与陨石479到main。五次按各自请求/Surface/CB核封口、GPU完成、零截断与排空。原采样在`.artifacts/scene-model-startup-3662790108-20261109/evidence.zip`，无采样、截图与绑定收据在`.artifacts/scene-model-interface-reuse-20261109/evidence.zip`。未测长稳FPS、能耗或交互。

<a id="model-subtree-raster"></a>
## 模型的局部 source、深度与父组显隐

[原局部合成合同](advanced-object-coverage.md#model-subtree-raster)沿 nearest MainPass 的保 Z/W VP、XY 绕序及 pass depth 执行，world/normal/light/shadow 与输出 owner 不变。父组动态准备退出单 prepared leaf 例外和重复初始 visible 门，普通帧无新增检查/状态。该批签名Debug CDHash4067ed05…ac05、exec5fc7e94e…b021、dylibfc01c2f7…94cb、metallibc83cb6aa…ca45，4413构建输入稳定。原完整身份、失败、收据与独审保于 `.artifacts/scene-model-parent-visibility-20261107/`。

五个同输入自有App控制的15张PNG/75固定ROI误差0，覆盖父组热显隐、ID/资源/等价表达式改名、冷Bool、父visibility回调及外部peer.origin setter；child false与健康peer保持。旧暖组关闭/冷Bool开启被拒，外部setter缺父source/Program/tail且为[204,25,51]；当前沿model→200×120组source→capture→e0/m0/n0/slot0→group/tail→main/seal/GPU为[102,153,51]，与独立字面reference一致。父自身回调旧已正确，只作回归。每场同window/Surface、一次激活，request/CB和stream/generation匹配，bracket≤.267124秒、零截断并排空；cold早期depth cohort为空，不授冷深度。67项最近原生方法与三场原model App的7图/71ROI通过，保near/far、nonwriting半alpha、独立组depth、局部坏child、Project非均匀/镜像单面与model自身显隐；坏model/image同key仍整笔拒绝，source无Program保真实容量拒绝。独立3437487219/3477054430同三摘要四秒回归均完整出图、实际模型到main/GPU并排空。这不授作者model-group正命中、全部cold/初始关闭effect、组内image终端共享depth、外部材质writer全场景、UI/IPC、官方像素或性能；其余组合归队列。

## 世界模型材质的实际消费 <a id="model-normal-map"></a>

2026-11-14按[原模型材质设计](advanced-object-coverage.md#model-normal-map)接通stock generic4静态surface的slot1，准备期保.normal/data、独立UV/sampler与typed TEX编码，实际TBN消费原切线/逆转置法线及镜像手性；退“有normal即拒reflection”，不改几何depth/caster/ambient方向。五产品净+89行，无新owner/cache/PSO；无图仍多32B uniform、varying和固定绑定，不授零成本或性能收益。普通Debug构建28.56s通过，五产品及project/锁文件构建前后一致；签名/原helper验证通过，exec6169cbdb…d1df、dylib6257b6c9…c099、metallibe451f575…2848。基础pipeline8项及相邻混合/发光/三灯阴影/来源15项通过，最终独审无阻断发现；新生产资源→原renderer/Metal门6方法、35实际GPU输入，覆盖五编码、相反方向、手性/镜像/旋转/斜切线非均匀、独立UV/采样、关闭/缺图/custom、环境、alpha/depth、反射色带与完整改名。原四轮载体编译/输入/相机失败保留，最终普通model的utilityLayer=nil及native投影资格成立；未放宽像素阈值。原包3453730450与3477054430修改前/后各5秒PASS：当前F143的53/77分别4096×2048 RG与1024² AG、F191的47为1024² RG实际绑定slot7→main/seal、同request/CB/Surface/GPU completed、零截断并排空。两张当前PNG可见月球/星空与猫/楼体，前后相位不同不授精确像素差。独立3437487219无normal保持完整地球/星空/时钟；3557068717晚相位156/270的2560×1440 AG及三反射进入main/GPU，但该构建424e0独立MSL varying编译失败，保两项CHECK，不记整景PASS；该断点后续资格见[相位供货](#model-mask-phase)。标准TBN/普通图片RGB为自有算法；动态MR、其它材质族/分量图与官方像素未授。App原报告/图/日志归 `.artifacts/scene-evidence/runs/scene-model-normal-20261114`，产品/载体失败与原生结果归 `.artifacts/scene-model-normal-20261114`；最终审查与相邻门结果同该包。

**加法颜色 <a id="model-additive-blend"></a>（2026-11-14）**：已解析additive沿原Frame选冷PSO的RGB one/one，alpha-over、depth/cull/caster不变；普通帧无解析/新pass。同payload旧三产品快照保8条像素失败，当前6方法/33GPU行通过：full红叠蓝由[255,0,0,255]→[255,0,255,255]，half由[128,0,128,255]→[128,0,255,255]，半蓝背景从[128,0,64,191]→[128,0,128,191]，深度逐值不变；改名、零覆盖、禁写及近挡远邻例保持。法线门6方法/36行通过，新增实际加法反射PSO在红64背景保R64/B23与原alpha/depth，未复制blend数学。首Debug构建检测源码漂移已作废；最终24.827s构建输入稳定，签名/原helpers通过，exece45781b8…98de、dylibb0b9e761…c5ec，metallib与上一法线批同字节。原包3477054430及独立3437487219各4秒PASS、PNG完整并排空；F190/request1的68实取32²颜色，以additive状态进入main/seal和CB532772587264/GPU完成、零截断，343 F153的112/114保translucent。星片实际为受光/雾后白色、alpha1，slot2空不授emissivebrightness10贡献；未配对逐星ROI，不认领黑天多数星点变化或整景增亮。反射和加法全场共存可连带准备一份未被具体part使用的组合PSO，固定有界，不称逐组合最小化。最终独审无阻断；源/8失败/69当前GPU行、无效构建及正式构建归 `.artifacts/scene-model-additive-20261114`，实际App原报告/图归 `.artifacts/scene-evidence/runs/scene-model-additive-20261114`；未授官方像素、性能或更多材质模式。

## 模型的测试与写深度 <a id="model-depth-state"></a>

2026-11-14按[原深度设计](advanced-object-coverage.md#model-depth-state)，Entry 冷准备独立 test/write，原 Frame/四 stencil 消费，no-test 模型截断透明 image 重排；真实 opaque 的体积 camera-depth 按颜色绘制顺序复用相同测试状态。四产品净+20行，仅新增一份 always/write stencil，不增 PSO、池、owner 或热解析；默认与旧 disabled/false/off/0 别名保留。旧同输入原生48行触发8条子断言失败；当前48行的9方法及 point-volume21行/6方法均通过。far write-only由红/nearDepth .51000011 变蓝/farDepth .48999989，no-test/no-write为蓝且保 nearDepth；alpha0、空/未知、改名及原混合邻例保持。真实 Frame 收集与 encodeVolumeOccluderDepth 的近/远原生相机控制中，远 no-test writer 的 color/camera depth 同为 .0000809322737；不写时两者保近 .000101142461，1e-7容差，非复制比较算法。PointVolume 的两新顺序控制同时验证实际散射截止，阴影灯空间比较不变。

旧 App 的两新方法分别因四区全红和错误重排而失败；候选两方法、四场实际 App 及8PNG通过。近红→四材质远蓝→中绿的四组合为 R/G/B/R，完整 model/material/texture/ID 改名相同；排序只切 model test，off 按511/512/513为[0,128,127]，on保合法512/513/511为[128,64,63]，均在事前 delta4 内。输入、源码与 App 身份固定，ready/after像素一致，同 request/CB/主目标/seal/GPU完成与排空逐图核对。普通 Debug 28.045s、四产品/project/锁文件前后一致，签名/原helpers验证通过；exec4525130e…c5a0、dylib907d2e01…9c5a，metallib仍e451f575…2848。作者3453730450/3437487219各5秒PASS，F165/CB532952090368和F156/CB533511734144的模型保持test/write=true、主景与同帧main/seal/GPU完整，零截断并排空，只授enabled原路径回归。独立产品/测试/图像审查无阻断；官方disabled语义、文字disabled排序、任意透明体积与性能未授。

自有输入、失败、原生/App像素、构建身份与独审保于 `.artifacts/scene-model-depth-state-20261114`；真实作者原报告、必要图与日志归 `.artifacts/scene-evidence/runs/scene-model-depth-state-20261114`。

## 夜光遮罩的相位供货 <a id="model-mask-phase"></a>

2026-11-14按[共享stage输入设计](render-graph-shader-coverage.md#implicit-fragment-varying)，原canonicalizer用顶点唯一数值型varying的完整类型/固定长度和片元精确函数体自由值引用补声明。顶层类型与局部类型在原binding facts区分，callee、uniform/全局值/函数冲突、显式接口及未知生产者保原结果；两backend共用准备输入，原诊断源码与缓存身份不变。两产品净+40行，新增的双stage词法分析只在冷准备，无新owner、Program、纹理或普通帧工作，不授准备期零成本。

旧源同输入5个phase变体均在真实strict link以未声明输入失败；当前8个CPU方法及4个GPU方法的分步有效结果覆盖完整12方法，5个实际纹理phase、2个局部/形参owner、3个原value-copy和6个原prefix共32条双backend Metal读回通过。四象限纹理的半宽移相得到字面交换结果，覆盖变量/helper/资源槽0→3及源文件名改名、等价式、混合局部作用域、局部struct类型与固定数组；14个边界维持真实compiler/原normalizer结果，不绑定旧错误码；原uniform词法身份与活varying资源ABI相邻两方法通过。首轮载体默认ES profile失败及旧stage-uniform同名失败保留；仅修载体profile/声明换行并重跑受影响方法，复用同一编译二进制。uniform边界保authored link成功、normalized link失败与bounded diagnostics/MSL事实，未授其Metal像素，后续归开放队列。

普通Debug 27.022s且两产品/project/锁文件前后一致，签名/原helpers通过；execbf6e2e9e…3678b、dylib20a03658…6a2c，metallib仍e451f575…2848。原3557068717两份原入口摘要相同，固定WallDate `2026-11-13T10:00:00Z`、SceneTime20和PhaseX=.416666667；前后均F95/request1，旧424copy变为真实material采样→named424→420 slot1红通道遮罩→named420→237模型到main/seal，同CB/GPU完成、零截断并排空。原3024×1964 PNG中相位产生可区分纹理变化，不能认领全体像素差或整景/夜侧增亮；自有纹理门独立证明相位数学。独立3477054430原包4秒PASS，模型、完整猫/楼体终端图与GPU排空保持。此前替换前的候选构建、目录参数错误和载体失败不计当前资格；官方像素、性能、结构类型varying及更多省略接口未授。

当前自有源/32读回、原作者同钟前后图/供货、构建身份与审查归 `.artifacts/scene-model-phase-20261114`；独立作者原报告与必要图归 `.artifacts/scene-evidence/runs/scene-model-phase-20261114`。

## 世界模型的分量贴图 <a id="model-material-map"></a>

2026-11-14按[模型分量设计](advanced-object-coverage.md#model-material-map)，原Entry的emissiveMask/三nullable draw参数退出，以单一typed数据binding消费slot2。原TEX位只供省略默认，显式0关/任意非零开、PBRMASKS0仅关map；M/R替换原响应标量、B乘反射、A乘发光，stock静态数值材质在unlit仍保profile及gain缺省1，legacy原缺省0/A路径保留。B0按实际有效reflectivity停止反射，避免既有pow floor在HDR下残留。五产品净+38行，无新owner、PSO、池、缓存或ABI字节；原data loader/UV/sampling只在准备消费，draw重复可空map校验退役。可选图无有效位时会先沿原加载链取得metadata再局部丢弃，不授冷准备零成本或性能收益。

当前5个map方法/60实际输入与6个原normal方法/36输入通过，同一编译Swift/Metal载体分两payload执行并逐次核source/support及binary/library身份。分区map与独立等值标量得到同RGBA/depth，覆盖四分量、0/1/2/-1、总开关、TEX省略/显式无header PNG、缺图、UV/filter/address/改名、normal/反射/HDR/alpha与legacy。B0/M1/brightness16与scalar0均严格[0,0,0,255]，同环境B1为[4,4,255,255]。当前五产品与NormalChecks匹配实际执行载体输入；共享测试transport中其它入口的修订未进入该96项调用链，不扩大其覆盖。 相邻发光6方法、编译/ABI/点灯计数/来源资格及资源分段6方法、点光/聚光阴影4方法的分步有效16方法通过；退役三段纯源码包含/排序镜像，保真实编译/读回并把断言信号基线148收紧至142。

普通Debug 24.862s、五产品/project/锁文件前后一致，签名/原helpers通过；exec7c89dd96…bc98、dylibc0cbfb1d…7348、metallibe4726416…6b48。原3453730450自然20s/after17，F853/request1/CB503263185536的53实际4096×2048 components3、77实际1024² components1到main503207287040/seal/GPU完成、零截断并排空；1280×831终端图有完整受光月面、轨道、星空与时钟。两场预启动固定SceneTime/Date只取得前后同灰幕，已撤出可见资格，不声称严格作者A/B像素或77逐part贡献。独立3437487219原包5秒PASS，F159的112取8192×4096 A图components8，同主目标/GPU并排空，完整地表/云/大气/时钟；3557068717原包5秒PASS仅授片头，F117的182取2560×1440 A图components8、亮星/远星体与GPU完整，不授后期地球夜光全貌。官方像素、任意动态MR/外部反射/命名map与性能未授。

另用真实53的原MDL几何与三张4096×2048 TEX组成无脚本自有scene，保相同相机、点灯、世界矩阵、源资产/App/场景SHA，仅四分量combo从省略切0。两场F94/request1均同次main/seal/GPU完成、零截断并排空，on绑components3及RG normal，off仅退map。整球颜色/背景排除并集167063像素中87539（52.3988%）改变，平均绝对RGB差.6481 byte、最大116；6个量化边缘像素改变排除mask归属，不授几何覆盖变化。此图R恒0等于标量，差异具体归因G粗糙度50…255替代scalar1；不授真实77金属逐part贡献或作者原景/官方像素。首次等长改材质目录导致catalog漏读的clear-only失败与该批内改basename的对照保留；此断点已沿[明确材质角色](#model-material-role)纠正，未调几何/灯/相机或纹理。

作者报告/必要图与日志归 `.artifacts/scene-evidence/runs/scene-model-material-map-20261114`；自有数据、源码/载体身份、边界、灰幕与退役断言失败、审查及构建收据归 `.artifacts/scene-model-material-map-20261114`。

## 明确材质引用不受目录提示限制 <a id="model-material-role"></a>

2026-11-14按[准备角色合同](advanced-object-coverage.md#model-material-role)，原Catalog用同一规范身份的queue索引与material位替换seen；MDL附加材料、JSON model.material、particle及effect pass的明确消费者调用同一loadMaterial，待处理hint原位提升、已处理hint只补一次。普通effect dependency仍为hint，未消费.other不读；保原来源选择、脚本、排序、取消/revision和局部坏材料。产品仅Catalog净+13行，无新parser、MDL读取、资源owner、持久cache或普通帧工作。

同输入旧Catalog的12方法保13条失败，当前12方法通过：原Catalog门11方法核7材料的改目录/后缀/大小写、pending/processed提升与单次读取、package优先、坏/缺材料及无消费者JSON零读取；原MDL→SourceFacts→Catalog→materialPass门的17现代/legacy/多part/PKG变体保同份PreparedSource及健康peer。替换只选测试编译输入，不复制材料或网格解析逻辑。普通Debug32.161s，Catalog/project/锁文件前后字节一致，签名与原helpers验证通过；exec3f76122a…5432、dylibd4f260c2…a7ca5，metallib仍e4726416…6b48。原分量/法线/深度GPU合同未改，复用其有效门；未授准备性能收益。

直接读取上一分量批冻结的真实月球资产失败变体及materials/等价载体，project/scene/pkg/材料与几何字节相同，仅MDL材质引用不同。相同固定Date/SceneTime、画幅与App，两场F94/request1分别CB517910315904、511535694720，layer53的albedo、RG normal与components3到各自main/seal/GPU完成、零截断并排空；输入、原protocol、App和Catalog前后SHA不变。旧外路径clear恢复167058月球像素；新外路径、新标准路径与上一构建标准路径三图均SHA7687586a…41f63，1280×831全部1063680像素零差异，无ROI裁剪或宽容阈值。资格为同真实资产自有scene的材料路由修复，不授作者整景或官方像素。独立3437487219原包5秒PASS，F120/request1/CB515864495872的112/114进入main515873918720/seal/GPU，地表、云、大气与时钟完整并排空。当前材料角色断点退出开放队列。

自有输入身份、同输入红绿/单次读取、两场实际图与收据、独审和构建身份归 `.artifacts/scene-model-material-role-20261114`；独立作者原报告、必要图和日志归 `.artifacts/scene-evidence/runs/scene-model-material-role-20261114`。未知未引用文件、真实坏JSON不被此次角色放行；动态材料、其它shader/多pass及官方像素仍按原能力边界。
