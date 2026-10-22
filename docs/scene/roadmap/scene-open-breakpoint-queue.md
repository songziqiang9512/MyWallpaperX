<!-- document-role: active-plan -->

# Scene 当前断点修复队列

> 更新：2026-10-23（局部后继）。本文排当前开放问题，并保留用户反馈退出的精简备注；顺序为**画面正确合成/正常播放 → 有证性能成本 → 属性热更新接线 → 其他合同与验证债**；专项选序服从[兼容路线](scene-compatibility-roadmap.md)。已修首断点退出，具体视觉余项单独保留；完整golden、全部交互或更多profile尚未验，不自动构成新缺陷。

以源码和同身份执行证据区分**运行复现**、**静态反例**、**能力缺口**与**待复验**；旧日志、声明数、默认隐藏/属性关闭和暂未ready不算可见故障。根因unknown不据同类样本、图层名或截图补算法。

样本、旧人工verdict与静态/运行/目录分母归[台账](../capabilities/scene-sample-acceptance-ledger.md)及[声明统计](../capabilities/scene-corpus-capability-inventory.md)；not-run不等于从未运行，376仅shaders不算启动失败。旧[N组](../history/new-scene-intake-2026-10-11.md)、[10-17增量](../capabilities/runtime-evidence-current.md#intake-20261017)与[新增322首诊](../capabilities/runtime-evidence-current.md#intake-3221354414-20261017)不自动刷新人工裁决。10-19[新增25](../capabilities/runtime-evidence-current.md#intake-20261019)只认默认短窗与已证执行缺口，全部视觉unreviewed。

10-21[新增24诊断](../capabilities/runtime-evidence-current.md#intake-20261021)均实际播放并正常退出；按以下公共类型合并，不以矩阵PASS/FAIL或静态family数裁视觉。官方图23份，337无截屏；请求after8但pointer路径先在约2秒写after，实际时刻依日志。374时钟拼合、382延迟蝴蝶已由用户解释为正常作者行为，退出缺图候选。

10-21[后继5包](../capabilities/runtime-evidence-current.md#intake-five-20261021)与10-22[新增17包](../capabilities/runtime-evidence-current.md#intake-20261022)均已实际播放、正常退出/排空；当前目录373。新增17包无官方“截屏”，默认20s、固定PCM/中心pointer，另核5/10/15s系列；未验真实点击/拖动、全属性或媒体播放。矩阵17PASS只属运行门，全部视觉unreviewed；默认隐藏分支、空媒体、作者预览与早截图差异不直接入缺陷。

## 1. 画面合成与正常播放：可定位的开放项

| 项目 | 当前证据与边界 | 最小下一门 / 停止条件 |
|---|---|---|
| Program前端及来源准入 · 3086016320 | 430仍报execution-stage-conservation/named binding；它属于父426下的封面转场/混合，默认父alpha0，不能当独立root1521底部频谱缺失根因。既有原1521双32band实际非零、原Program/GPU/末合成已完成。292 global const、314/370分组prefix首拒已闭，不重开。 | 后继先取430可见媒体正控与实际base/potential/selected依赖向量；302多槽合同可复用owner，不能跳过隐藏effectless forward259的作者顺序或照套anchor。无默认可归因ROI时不为修日志首错优先实现；292短曲线另归视觉资格。 |
| source材质/lookup余项 · 3616476797 /3679907516 | 361113及36771/74/83的source-only render-state首拒仍在（translucent/VERSION2等组合），不能泛化全部translucent/VERSION2或整layer缺失。361右下媒体面板/条实际在，无同控thumbnail；36771作者回调产黑、83初alpha0待thumbnail事件，74普通effect已实际Program/GPU/末消费。当前无source独占默认缺失ROI。367名称/祖父缺席异常另未证明缺host API。 | 优先低成本受控媒体资格；仅texture×g_Color4的native等价路径须证明一次调制/输出域，不为无新增像素扩raw接口。只有非等价source可见ROI才推进原sourceEvaluationState/typed Program；保父子/多receiver、straight/PMA、UV、资源身份与局部失败反例，不直接放guard或全局吞lookup错误。 |
| 动画metadata准入 · 3822822401 | 161→puppetAnimationLayer244.visible报prepared metadata unavailable，独立可见损失未定；**蝴蝶延迟正常**。281/299292的文字创建误拒已由下述后继退出，不再归缺asset。 | 核合法lookup与target prepared metadata的最早owner，只接原typed事务；先取得该回调可见作用，不吞异常或由本项宣称缺蝴蝶。 |
| forward copy-background composition · 2972071249 | 313引用后置隐藏composition234，首拒在dependency stage order；234隐式copyBackground使全局prepass不具作者顺序独立性。白色波形未归因234，不能据此闭合可见缺口。 | 先资格consumer边界prefix及跨consumer身份，再复用原graph执行/发布；官方自有单board的静态蓝slot1正控呈黄黑checker，已STOP_UNKNOWN，不能将其余两卡当语义结论，也不重复未资格载体。证据归[运行记录](../capabilities/runtime-evidence-current.md#forward-composition-prefix-20261019)。 |
| Puppet动画auxiliary profile · 3577990983人物仍停bind-pose | 多target裁剪已恢复中央人物，原四动画因首1678 auxiliary固定tag门未全部准备。四record现已按完整边界核准：1678/2078/258/3194均有骨79/80约0.7、其余84骨exact1的alpha，确有四份consequential贡献；1678/258另有非零逐骨scalar，只有1678带keyed shape曲线。stride84 position.w的19个ordinal、MDMP两blob边界已证，437/32767不作全局顶点index；packed位移/并行通道、scalar语义及混合顺序仍unknown，不能只放reader门。2078/3194虽无scalar/shape且结构可表达，但wire无独立record长度，不能catch首1678后扫ID续读；两者原additive alpha又同时命中Selector/Evaluator多contributor门，不构成独立默认恢复捷径 | 沿原AnimationReader/evaluator/pose补完整消费者；357仍需scalar与多clip alpha。376原650三臂的几何STOP仍为0派发；10-20另有一次公开shape API-only自有板，部分读回成立但P1后独立observer不符即停、P2未执行，完整0→1→0未通过，见[唯一资格边界](../capabilities/advanced-object-coverage.md#op-puppet-blend-shapes)。几何B仍未资格，不据此放MDMP/scalar或归因重置机制；后继先提供新的可区分证据及morph位移正控，不重做旧矩阵。原四请求、健康Puppet与几何失败回退保持，不跳track或吞错。 |
| active effect输入/来源准入缺口 · 358/357/363增量 | **358/357320、233仍开放。** 358七个slot1用途proof拒；其RGB颜色+A权重、slot2才是红mask，不可当mask放行，且无可归因明显缺图ROI。357的320另拒slot1，233 Combined仍被parent/children门拒；10-18官方三卡因跨pass根动态正控失败而STOP_UNKNOWN，未取得clock/alias合同。3632522893的765有子785，Blur772被whole-stage childless门拒，GPU完成属于passthrough；10-18未定位唯一缺失ROI。357210二维fallback/半透明dock已真实恢复，退出本行 | 357233须先证明5个Aperture、2个Opacity root的逻辑control身份，不能effect-wide挑首root或只接两pair；不重复无资格载体、不由literal0的零响应外推原完整动画副本。默认开场约4s，5s after不足验收；[本轮资格与停止](../capabilities/runtime-evidence-current.md#effect-combined-qualification-20261018)。358先定位明确ROI；363沿现group/source链证明source完成、pin与extent，不能直接删guard或新建Blur owner；资格`.artifacts/tmp/363-blur-whole-stage-qualification-20261018/qualification.json`。不把RGBA当红mask、扩大capture或按效果名旁路。 |
| N08 · world / 负subdivision RopeTrail | **仍拒绝、语义unknown。** 3337494481十个visible复制层unavailable；原hidden不计故障。旧20图只证-16可见；10-22容量正控因缓存包装未资格即STOP，后三臂未跑 | 须先取得空间/细分可区分证据；不重跑白线矩阵、不猜abs/clamp或删guard。static child Rope不关闭此项。[资格与停止边界](../history/rope-trail-profile-qualification-2026-10-15.md#cache-observer-20261022) |
| U40 · 3749463715、2998757800重复Puppet拖动 | **释放链未闭合。** 两包释放链均触及未接入的applyBonePhysicsImpulse；299无getAnimation变体。10-18方向观察与10-19 setter/低冲量顺序载体均不足裁定单位、gain、状态消费或顺序，后者缺运动像素正控，STOP_UNKNOWN；不能猜velocity/force或忽略异常。query/render分域及跨owner误序只闭各自范围。[唯一资格记录](../history/repeated-puppet-drag-qualification-2026-10-16.md) | 仅在取得可区分的持久状态/顺序证据后，沿唯一pose/motion与canonical父子顺序接入；不重复无区分矩阵。562/598动态挂点/XY缩放、省略启用字段、angular/reset及其他physics profile边界保持。新增3187857248 bone0/1实报`unsupported-enabled-physics`、沿作者姿态回退，归更广物理profile资格，不据此归因本行释放impulse或宣称人物不可用。两包分别验三轮响应、释放更新和健康邻居；低帧率另归性能段。 |
| N03 · 3337494481盒体遮挡与整体构图 | **五层主源已退出，整景未过。** 白音频条与模型共享深度已接通；侧clock/date跨面文字余项仍未闭。官方rim倒字/title黑影本就存在。 | [当前资格](../capabilities/runtime-evidence-current.md#native-text-depth-qualification-20261023)：未发现作者显式字段丢失；新自有板因前后image正控不成立，一次即STOP_UNKNOWN，不重试或猜默认深度/透明quad策略。旧10-20原证据已清理，仅保历史描述。末visible camera规则不改，扁盒/粉顶仍待同pointer/phase；effect CPU、229 fallback和黑背景未闭，Rope归N08。暂无可行动默认text合同时转其他明确缺口；普通显式image不代验text/748 replay。 |
| 普通unlit数值下溢 | **10-08自有GPU旧反例，未fresh复验、真实样本影响未证。** weighted输入source alpha=.5、vertex=.25、R8 clip=128/255仍把应约2.5098的RGB算成0；既有fast-math下溢未由溢出修复关闭 | 沿唯一颜色乘积/片元owner保有限结果及alpha，不全图压暗、加cap或换混合。先取得真实活跃消费者，分开数学反例与用户画面收益。[现有证据](../capabilities/runtime-evidence-current.md#e-2026-10-08-unlit-product) |

<a id="qv-visual-repairs"></a>
<a id="qf-2026-10-07-用户点名四样本公共主链修复"></a>


332默认639主时钟缺失已退出：实际字体在原生glyph-path段落中产生不可表达的字形坐标；同一准备链统一退回typographic排版，原包5/10/15s主时间完整可读，日期/星期与独立347文字/画面保留。旧“小碎片”主要是独立秒数，不能继续归因639。异常字体的精确ink限宽、post-scale/多语言与官方同状态未验；376空媒体颜色拒绝仍单列待事件资格，不吞数值检查。[有界后验](../capabilities/runtime-evidence-current.md#native-text-bounds-20261022)。

281/299292的Bool文字创建首拒已退出：合法nil-path文本不再被图片路径门误拒，原文字与隐藏副本沿同一typed事务；299默认字形有小幅姿态变化，精确X/Y未分离。仅把作者阴影选项Off改Static的受控副本已恢复可见偏移黑字，默认仍Off；281与独立302主体/文字保持，不升整景或官方parity。见[有界后验](../capabilities/runtime-evidence-current.md#boolean-dynamic-text-20261021)。

374的image font回调首拒已退出：官方自有载体证实合法String赋值不throw且前后文字继续；原层身份保有界JS-only值，文字仍沿原typed事务，未吞任意错误。原包450.visibility同输入异常由1→0；公开字体7→4热切在同surface/window生效，外露“周”由手写变粗黑描边。默认横屏日期仍在crop外，移入后部分受人物遮挡，不据此闭布局/整景；全部34字体未验。见[有界后验](../capabilities/runtime-evidence-current.md#image-font-script-state-20261020)。

302的216/328阶段守恒与命名绑定首拒已退出：同provider的visible graph-final多槽沿唯一Plan/Program/Runtime向量贯通，保原direct anchor/Program身份及一次publication。受控当前封面由白占位恢复可辨非均匀梯度，白边/标题/人物/星环保持；无媒体仍隐藏封面，独立381保持。216默认隐藏，只认准备首拒退出，不假称可见恢复；上一封面切换、全播放器、圆环宽形/官方同音频phase与整景仍未验。见[实际收益与反例](../capabilities/runtime-evidence-current.md#optional-graph-output-slot-vector-20261020)。

338的306/effect364启动与编译首拒已退出：有效prepared普通颜色边界不再被启动门无条件拒绝，数值类型和packed音频源码视图复用共享准备链；原Program实际GPU/合成及下一帧已完成。开关前后可见ink仍不能可靠归因，整景保unreviewed；不能把旧“dynamic producer回退”继续列为现役故障，也不记视觉完成。见[有界执行与未覆盖项](../capabilities/runtime-evidence-current.md#audio-packed-source-view-20261020)。

329默认骨架站位/静止反馈已退出：完整记录身份与共享XYZ姿态链恢复默认34，实看骷髅在下方盒顶区域连续变姿，未改作者origin；当前HEAD整合及独立static/Puppet健康邻例保持。只关闭此具体范围；后继[rate Number值源](../capabilities/runtime-evidence-current.md#puppet-animation-rate-script-20261020)已恢复原作者音频变速，面板余项归属性卡；direct条件选择已由[同session热切换后继](../capabilities/runtime-evidence-current.md#conditional-model-animation-20261020)关闭有界首门；默认437数组首拒及上方白波形已由[固定数组后验](../capabilities/runtime-evidence-current.md#generic-varying-array-20261021)有界关闭；边缘多色大片已由[公共截面后继](../capabilities/runtime-evidence-current.md#screen-displacement-ribbon-20261020)关闭具体反馈，不升整样本通过；[有界后验](../capabilities/runtime-evidence-current.md#direct-model-skeletal-animation-20261019)。

329默认单臂闪骨与动作控件缺失已退出：公共prepared Pose统一四元数时间采样，保完整骨贡献/identity/reference/blend；真实80采样与当前App原图、用户默认1连续观察均通过对应范围。成功条件Program进入实际Service筛选，原生“视差”1…8下拉框出现，用户确认动作更新；Root选2保存/重开和reset回1已验。普通Release视频/音频反馈亦已正常，不再列为播放回归；默认437首门/波形已另闭；旧Debug负载时序及全模式/官方时相仍保边界，不计整样本通过。见[当前有界后验](../capabilities/runtime-evidence-current.md#puppet-rotation-continuity-20261020)。

322的2522色散首门已退出：共享词法绑定及浮点公共宽度转换让原包点击后的非零Alpha进入作者Program，实际GPU/末合成与瞬态RGB分离、回清晰黑面具均已取得；局部vec4遮蔽不同类型global不再误拒。原命名点击、左眼/默认动画与脸颈组装修复保持；手部旧观察仍归第2节，完整同phase/viewport与全部互动不记通过。见[有界后验](../capabilities/runtime-evidence-current.md#shader-float2-consumer-width-20261017)。

382右上缺光已退出：sampler presence不再被editor `require`阻断；原包默认参数实际恢复两束蓝白光，Program/GPU/末合成及下一帧执行，独立376人物/背景与旧mask链保持。format条件未扩、完整同phase/viewport仍未验，无性能收益声明；见[有界后验](../capabilities/runtime-evidence-current.md#sampler-presence-requirements-20261017)。

357底栏16白块与210黑底板已退出：typed usershortcut保作者底图，16透明花叶恢复；后继二维fallback让210恢复半透明圆角dock，人物/栏杆可透见，独立361顶部8透明链环保持。10-20本机文件/目录/App配置与实际打开亦已用户确认；hover范围见上表，未知回退及aux/233/320仍保留，不升整样本。[底图后验](../capabilities/runtime-evidence-current.md#user-shortcut-authored-fallback-20261017)、[dock后验](../capabilities/runtime-evidence-current.md#shader-vec2-authored-fallback-20261018)。

3022080536背景缺失已退出：旧52B全文件选择/拒绝优先后，format9/20B静态mesh沿原bind/UV/world链准入；原包奶油纸底、书法和双红印实际恢复，主体18动画保持，独立WLOP legacy16/52画面保持。完整属性、互动及相同viewport/phase仍未验，不当作整样本PASS；见[有界后验](../capabilities/runtime-evidence-current.md#mdl-static-position-uv20-20261017)。

3577990983中央人物缺失已退出：counted target数组沿原reader与逐target ROI接入，原包默认Reze、手臂和身体已真实呈现，独立379 Puppet保持。人物动画auxiliary拒绝及233/320余项仍分列；210底板与底栏白块的后继已退出，不是完整播放/视觉通过。固定官方mask子门成立、标签辅助joint失败及native工具1/2均如实保留，见[限定后验](../capabilities/runtime-evidence-current.md#puppet-multi-target-20261017)。

3599986633的初始黑幕已退出：固定官方空effect集合lookup返回null后，原两handle入口对齐此合同，作者初始化能沿原alpha journal解除177过场遮挡；原包默认实图已恢复九凤主幅，独立335画面保持。702的destroy拒绝另保原运行观察，不当作初始缺图根因；完整背景选择/过场交互未验不自动新增缺陷。证据归[限定后验](../capabilities/runtime-evidence-current.md#empty-effect-lookup-20261017)。

317七条mix异常已退出：原包56标题按下/释放尺寸反馈恢复，纯hover保持；六标题、粒子131、全播放/parity未验，见[限定后验](../capabilities/runtime-evidence-current.md#wemath-mix-value-boundary-20261017)。

3610154602于10-16同身份复验并读源资格后，不再按“缺getTextureAnimation API”排实现：435.alpha/origin首错依赖当前缺席的播放器控件，423只存在一层parent却读取祖父；公开missing lookup/null及无父undefined合同已执行。其余动态创建/导入是否应提供缺席控件仍unknown，不记作者错误或样本完成；取得合法producer证据后再开共享首断点。人物、城市、时钟与橙色频谱实际呈现，非完整parity。限期证据：`.artifacts/scene-evidence/runs/texture-animation-owner-qualification-20261016/`。

3605722997的“只见裙摆脚部”已通过单次animation=false对照归为入场视频phase：默认after约在5.29s，作者18s后才淡出；关闭入场即恢复人物/建筑，camera descriptor逐值相同。该巨大取景观察退出相机故障排期，不关闭原入场时序或其余粒子/脚本缺口。169顶部灰带沿用已证同宽高比官方亦有的边界。302背景已按上文恢复；357底栏已实际恢复；同公共修复的3616389236顶部8白块经后继实际运行恢复透明链环并正常退出，已退出队列；不能从不同viewport/声源或未完整播放直接改颜色/相机。

3078285611的effect6/22/24 speed于10-16同身份读源资格后退出“缺API”修法：三者对整个scriptProperties容器做算术，健康effect5读取其中Number成员；现无原型容器不能primitive coercion，解释原toPrimitive首错。没有公开whole-container转Number特殊合同，改变原型或替换slider也未证明能产生合法速度；不认定作者错误、官方结果或样本已修。后继须取得能改变此类型判断的公共行为证据再开共享缺口，不重复numeric门。中性收据`.artifacts/tmp/307-speed-consumer-research-20261016/qualification.json`（SHA `ab21f208267dfc4ed8719cf87c338210c26e64196d1b657d4e0175e0cb158939`）。

2964778792的root动态origin准备与74.stop首门已退出；自有锚定及原包第一idle黑色Z已真实可见。范围与截图协议失败归[限定后验](../capabilities/runtime-evidence-current.md#particle-root-world-translation-20261017)，不再排“只放静态门”或称整样本/全部交互通过。

## 2. 具体视觉差异：保留观察，待当前身份复验

下表保存尚无关闭证据的具体差异，不表示当前HEAD均有缺陷。QV旧观察仅能追至原队列所链09-26—10-08证据；未注明更新日期者缺最新App、phase/属性/音源身份。先用当前链路复验；若不再出现或确认作者设计/关闭则退出，不为“完整parity未验”继续造任务。

2026-10-18用户补报已合并至原行或下表，不另建重复队列；均为**用户观察 / 待当前身份复验**，不是复现、根因或代码回归结论。用户于2026-10-20确认已清理大量本机缓存；[证据可用性](../capabilities/runtime-evidence-current.md#local-evidence-availability)区分历史来源与现存载荷，旧路径消失不撤销有界结论，新范围按同输入取证。混合模式、频谱高度cap等猜测与画面症状分别记录。

| 样本 / 旧观察 | 当前边界与下一关闭门 |
|---|---|
| 音频相关可见性 · 2919854127 /2927205881 /3175039950 | 291官方蓝环本窗未见但graph已消费；292曲线只见右短段；317白方块雪粒未见、两粒子层人口0且发射受音频控制。官方音源、时相与视口未同控，均保待复验。先同源PCM并锁实际作者输入、出生/像素正控，再定位第一断裂边；292编译拒绝已另闭，未证其导致短曲线。不能按“音频环/发光”名称共用修法、改阈值或用非零输入替代作者触发条件。278眼部响应已按下表独立有界核实，退出“完全缺失”修法。 |
| 物理鼠标输入与 hover 比例 · 3577990983待排查；199本视口已核正常 | 10-23真实鼠标下，自有圆标与原199揭露均由用户确认贴合，退出该固定视口比例错位排期；[实际入口边界](../capabilities/runtime-evidence-current.md#physical-pointer-ingress-20261023)不扩更多DPI/多屏/桌面或全部互动。357较远提前放大仍待同设置官方/原生对照；作者约602场景单位宽半径只解释部分观察，不调全局倍率或认与199共根。有可定位新偏差再沿唯一输入→投影链复开。 |
| 2887542690 · 音频ROI、黑遮挡/字体与片区布局 | 10-16 composition创建、286控制及限定透视回绘已接通，原visible-of-null退出；只证旧外悬蓝条同位置消失。固定pointer显隐消融未找到音频条的可重复正证，资格STOP，不能称图框内音频恢复；其他旧具体视觉与完整交互仍待当前可区分证据。[本批边界](../history/composition-local-perspective-2026-10-16.md) |
| 2134765860 · 右侧旧黑块 | 10-16默认日景及作者Night(Lights On) String选项4实图未定位独立右黑矩形；亮吊灯、书柜和地板可见，灰白海报与软阴影仍在。旧精确ROI、媒体和墙钟/viewport phase未齐，不写已修；移出当前已确认缺陷，先取同状态可区分复现再追source/effect/compositor，不据两条无归属mask诊断实施。夜景限期证据 `../../../.artifacts/scene-evidence/runs/213-black-region-night-qualification-20261016/manifest.json`；标题修复不重开。 |
| 3768903841 · 云形/烟花细节 | 旧Worley云形及烟花/色彩细节未取得同相位关闭。10-16 R40独立原包复验四束spot GPU成功、底部光束可见，实图仍有横向深色云片；只证明当前呈现，不据此判新根因或整样本通过。先同phase对齐实际source/Program与ROI，不因四束恢复关闭旧云形差异。[原边界](../history/runtime-evidence-index.md#e-spot-light) |
| 3226487183 · 手部余项 | 原1028手部观察未取得关闭，已证实际origin/reference/效果链正常，不按外观改坐标。10-18只读核原手部MDL的117顶点source Z全零；不能从狮子source XYZ修复推手部受益或据此重跑。缺眼/默认动画首门已[修复](../capabilities/runtime-evidence-current.md#puppet-mdla5-alpha-20261017)，本行只保手部；完整同phase/viewport、全部交互未验不算新的具体故障。 |
| 3809618616 · 布局/显示比例裁切、音频活动 | 旧柱/照片缺失已修；此处只保旧布局/裁切及音频活动复验，不再重开int compound/TEX照片入口。先确认仍有具体差异及当前状态。[最后整合身份](../history/committed-range-review-repairs-2026-10-07.md#整合验证) |
| 3791967416 · 眼部完整周期、局部图案/合成 | 最终eye105闭眼无虹膜已有有界证据；旧局部图案/整体合成差异未取得同phase关闭。复验完整周期和对应ROI，不重修已闭barcode/seek/bone alpha。[边界](../history/puppet-clipping-2026-10-08.md#跨样本app与最终冻结) |
| 3789316755 /3211615441 · 频谱形状/幅度/全柱活跃度 | 旧容量与连续PCM首门已修；需要同声源App A/B与静音/噪声反例，不能用峰值策略充当官方算法。[证据](../capabilities/runtime-evidence-current.md#e-2026-09-28-audio-band-peaks) |
| 3211615441 · 中央图片点击切换、首焦点、按住外观/多步跟随与位置 | 事件和三点跟随已执行，旧完整交互未闭；按住需跨帧，不能以同帧down/up验收。[证据](../capabilities/runtime-evidence-current.md#e-2026-09-28-effect-cursor-visibility) |
| 3788467391 · 漩涡方向/速度/形态与长预热 | 旧Rope纹理跨度修复保留；300秒预热被预算截断、原版轨迹仍待相位对照，不能旋转整背景补偿。[证据](../capabilities/runtime-evidence-current.md#e-2026-09-28-rope-trail-texture) |
| 1315486372 · 顶部光线、中部渐隐、水波位置 | 10-19当前原包3024×1964短播及独审：顶部/中段光束仍比目录官方宽、软，保留外观差异；52光卡/117雾均有实际GPU完成，12水纹Program及末合成执行。水纹大体限盆内，未定位旧gross错位；未锁相位/viewport、实际slot域字节，公共错误owner仍unknown。不重试已否定的轴/×2 size或按观感调gain。[当前资格](../capabilities/runtime-evidence-current.md#light-water-current-20261019) |
| 3769761761 · 缺左上向右下斜光 | 2026-10-18用户补报左侧向右下斜光仍缺，待当前身份复验。旧局部变换、默认trail及alpha、1/2/4倍size尝试均未恢复目标；粒子或shader来源仍unknown。先同viewport/phase分离实际来源，禁改作者参数。[最后诊断](../capabilities/runtime-evidence-current.md#e-2026-09-28-ray-source-diagnosis) |
| 3113287126 · 小提琴粒子方向/数量 | 10-22原包20s已复验：五系统均有输出；425的合法Count3.02被integer拒绝已由公共Number/连续环绕修复，[执行与边界](../capabilities/runtime-evidence-current.md#particle-fractional-count-20261022)。该初始化不减少出生计划，不能据此关闭数量或整体方向；琴/持弓手锚点保留。样本目录无官方截屏，同phase下发射、运动和可见密度仍待独立对照，不凭观感调参数。 |
| 3437487219 · 全屏间歇闪烁、夜侧/光色差异 | [深度域](../history/model-scene-depth-domain-2026-10-19.md)后地表/云层/蓝边/银河保持；用户确认候选全屏不闪，但序列superseded/teardown，偶发时序/负载未闭。[基色](../history/lit-image-emission-albedo-2026-10-19.md)恢复银河橙调、[零端点](../history/surface-zero-roughness-2026-10-19.md)消除Earth112圆白热点，仅两项退出。[低能sky/HDR](../history/surface-zero-roughness-2026-10-19.md#residual-low-energy-20261019)四臂否定环境候选，旧alias/PKG失败保历史。新原入口官/Native资源正控齐；官方全15默认map请求的timedate关/恢复仅证定向交付，首CLI4格式失败保留，不冒逐字段/HDR/phase资格。Native gain0仍合法authored/encoded、宽夜侧未见改善，停止emission宽夜侧归因、不改公式/不跑offVM。主资格见[当前证据](../capabilities/runtime-evidence-current.md#surface-zero-roughness-20261019)，off报告`.artifacts/scene-evidence/runs/earth-emission-contribution-20261019/current/report.json`；夜侧/色彩、偶发闪烁/collision仍开放，ownerUNKNOWN，不调gain。 |
| 3743305891 · 背景十字流星过大 | 10-19同原包受控PCM已复现并修复频谱缺失，白条非零出现/静音收回，退出该首门；[有界后验](../history/source-material-entry-2026-10-08.md#perspective-neutral-tint-20261019)。十字尺寸仍开放：26 world父与10 local子各有独立scale，当前没有重复乘证据；本窗未取得同phase可归属尺寸正控，不改作者scale/flags追图。 |
| 3768229922 · 开场标识/过渡复验 | 10-19独立邻例8s原包短窗已显示PSYCHE GEAR标识，App0/正常stop与GPU排空；旧Combined来源默认hidden，未覆盖主体及完整过渡，故保余项。center stationary的hover最低变化FAIL保留，不据此判作者交互错误。固定完整默认开场窗口再核，不从稳定帧缺标识反推故障；[有界后验](../capabilities/runtime-evidence-current.md#default-camera-single-20261019)。 |
| 3770444459 · 溅水滴黑色、用户称应白色 | 10-19原包短窗与独审未定位可归因黑水ROI；底图22自带水波，四层REFRACT完成仅证明执行。黑水反馈仍open、原因unknown；先锁source/材质/合成ROI，不按猜测改blend。有界观察 `../../../.artifacts/scene-evidence/runs/water-particle-current-20261019/original/report.json`。 |
| 3351163962 · 左上文字超出圆环的新观察 | 2026-10-18用户称官方文字在环内，待确认确切文本、属性/时刻与viewport；新观察保持开放。旧同默认908×590的hour/seconds/greeting≤1.643px对照只关闭其具体范围，不能代替此状态裁决；先同状态取证，不直接改anchor。[旧对照](../capabilities/runtime-evidence-current.md#u25-u35-current-qualification-20261018) |
| 3768724269 · 旧光束范围/根部及右上渐变观察待同状态复验 | 10-20用户观察近官方，仅作线索；当前原包实图亦未确认新的gross光照缺陷。12个effect均进入Program、14个作者脚本target均完成callback，但不代验完整交互/音频响应。另已证实并修复sunrays整key热更被quad结构门误拒：光束与粒子同代开关、startup-false恢复且无重建。旧范围/渐变不作确信缺陷，不按观感调gain；有新同状态ROI再定位。[有界证据](../capabilities/runtime-evidence-current.md#quad-visibility-live-20261020) |
| 3287715210 · 眼周过亮/渐变弱、横移细竖条纹 | 两个独立余项。10-08原包与gradient-only完成GPU，16F量化存在但未证是条纹根因；后继官方2.8.0.42自有phase4输入已取得8位PNG、52色/最长63列平台，只能证明终端量化，不能推出内部F16或328根因。物理呈现及整样本仍待同状态复验，不额外压暗、不重复优先消融Bloom。[颜色/精度证据](../capabilities/runtime-evidence-current.md#e-2026-10-08-gradient-storage-isolation) |
| 3750813609 /3363252053 · 相机过强/纵向反转 | 用户三轮未接受、曾要求挂起，保低优先同输入复验；默认2D camera后继不替这两个原报告作体验验收，不从不同viewport补偿布局 |
| 3662790108 JUNO · Data脚本、球体/曲率及交互 | 10-13开场/持续更新的heap首门已修；旧球体/曲率、点击观察未取得同条件关闭，10-14 layer517读取undefined的p1_longNode TypeError仍待当前复验。10-16冷运行未ready，不会执行证明该异常消失；旧8.8 FPS也不当当前性能结论。[最后CPU资格](../history/script-c-codegen-ablation-2026-10-14.md)、[heap边界](../history/scenescript-host-heap-admission-2026-10-13.md) |
| 3589454154 土星 · Bloom、亚像素细线/微颗粒、轮廓/布局 | 用户调序暂缓；已修模型/光照不关闭这些旧具体差异。保持合法屏外投影，不用视锥剔除消影。[原光照证据](../history/saturn-light-delivery-2026-10-07.md) |
| 3747492842 · 闪烁、光束位置、viewport裁切/文字构图 | 旧正交near-plane首错不重修；固定当前输入/phase比较首个不同stage，再判原因 |
| N07 · 3248220186运动/密度/亮度 | 世界Sprite准入/相机与GodRays首门已修；这里只保10-11旧运行所留的具体运动/密度/亮度差异，待同phase/音源当前复验，不再列“world Sprite不支持”。[运行边界](../history/particle-world-depth-2026-10-11.md) |
| N03 · solid亮度差异 | 原队列有比较观察，但缺本项当前target/状态身份；先补精确消费者和同状态对照，再判是否为颜色域/材质合同问题，不能全局删brightness |
| 2938612768 · 右下时钟裁切 | 10-14固定13基线/候选的两张后期图均在，23层执行集合相同。根因未定；先当前布局/输出ROI复验，不改矩阵期待掩盖。[同输入证据](../history/frame-texture-snapshot-convergence-2026-10-14.md) |
| 2775915974 · 顶部灰边 | 来自09-06/08旧人工观察，缺当前身份；方向/顶部事件已修不证明该边界消失，先复验其是否是作者画布露底 |
| 3437487219 · collision行为 | 旧人工裁决的collision未取得后继关闭证据；先复验实际碰撞输入/owner，日期/时间恢复不代替本项。不能仅因旧fail写当前碰撞缺陷 |
| 3448845950 · 旧布局余项 | 首帧锚点阻断已闭；10-21高亮颜色的缺失Vec3.equals首错也已退出，背景同窗青蓝→红→绿→青蓝且标签/时钟/封面保持，见[颜色后验](../capabilities/runtime-evidence-current.md#vec3-equals-color-20261021)。只保旧布局/重叠待同phase/viewport复裁；不再排该TypeError，不归font或重开资源链。 |
| 3712499998 · 重复文字/样式 | 来自旧人工观察，Vec构造首门与频谱已修；若当前仍重复，定位实际String/图层组合，不再补WEVector API |
| 3477054430 · 月亮/球体与文字布局 | U12雾/Bloom、光照和媒体入口等已有有界后验，但旧“画面显示不全”、月亮/球体与文字布局不能合并销账。月亮过亮、低频响应和猫受光另有明确未闭边界；先按当前原输入/声源/phase定位具体ROI，不从旧fail重开已修首门。[原报告及局部后验](../history/shared-shader-type-compatibility-2026-10-09.md#u12-真实-pcm-与系统采集后继) |
| 3775355045 /3775373546 · 遮罩下双视频可见卡顿/不同步 | 旧维护者观察为数秒后下层落后；09-14原包20秒实际解码/命令与provider时钟同步推进，差小于2ms，不能继续称同步API缺失。但未将旧可见卡顿逐帧对齐到同内容/phase，保有界余项，先查实际两层publication/graph完成，不泛化所有视频。[时钟后验](../capabilities/scene-sample-debug-ledger.md#video-command-generation) |

<a id="user-three-samples-20261017"></a>
### 近期用户指定优先复验

当前有明确首断点的修复批结束或收益递减重排后，先处理以下用户指定项，再选旧候选；380的新异常优先重新复现。尚无当前 App/属性/phase 同身份结论的观察，先以目录现有官方实机图核对具体差异，再复验定义→实际 producer→最终合成，不从截图猜算法或坐标补偿。

| 样本 | 用户观察 / 下一关闭门 |
|---|---|
| 3351179520 · 文字环精确位置/尺度与旋转漂移复核 | 巨大斜片、白环贴合与空透明源2000²首门已闭；文字精确对齐仍partial。10-21固定1500Hz自动播放正常退出，8张可见原图跨53.496s，文字/盘相位继续变化，固定左右弧带未见明显整圈平移或半径突跳；未取同帧slot1/最终MVP/g_Time，不能认精确整周期或官方贴合已闭。动态值收敛后的日志去重不作卡帧证据。三者有独立TRS，21与393各自Spin，缺字体合法替代；不强制同速同心或用glyph包围框补偿。仅有可区分的新几何/官方ROI证据时再开，不重复长窗；[最近资格](../capabilities/runtime-evidence-current.md#ring-motion-qualification-20261018)。 |

<a id="qv-cccea6c-user-report"></a>

### U组：2026-10-08用户报告的具体余项

按**待当前复验 / partial / 具体反馈已闭或已解释**分流。partial只保尚未关闭的具体现象；下方退出表记录已有实际证据的反馈，不把“完整parity/全部属性未验”另造故障。旧人工verdict原值和台账未join的`not-run`不覆盖后继实际运行，也不自动刷新成当前HEAD结论。

原观看身份为cccea6c1a8a738fd97889fda53e8c9cb0603908d，缺App二进制、属性、声源和时间；下表未注明新证据者均**待当前复验**，不是当前HEAD缺陷结论。已闭主现象的U行退出；U40归第1节，U22/U24提交率归性能段，U42归属性段。同一余项只保一处。

| 编号 / 样本 | 仍开放的具体观察 / 下一关闭门 |
|---|---|
| U01 · 3764725758 | ①左侧斜光；②眼睛飘动仍保留。10-18当前HEAD复验已证830/1706实际Program、GPU、末合成及next-frame，未见准入首拒；窗口与官方比例不同，未确定可归因光束ROI，不改增益/点位。眼部未作完整周期复验。[有界复验](../capabilities/runtime-evidence-current.md#open-visual-qualification-20261018)；后继成员源同最终App两组/上部构图保持，未关闭本行两项。[组源后验](../capabilities/runtime-evidence-current.md#composition-member-bounds-20261018) |
| U02 · 3549827466、3581882134 | 354于10-18复验1226真实完成143批/672实例，仍无同viewport可归因缺光ROI；358188后继原包113完成200批/786实例，人物/金带健康，但官方左上暖亮与native冷暗的差异未能分离来源/phase，保持UNKNOWN，不按族名调增益。另358554、360371旧笼统缺光已限定退出；360旧Blur数值首拒已由[零轴后继](../history/previous-blurred-composite-admission-2026-10-12.md#zero-axis-followup-20261019)退出，未辨细条收益不作新光照归因。[后继复验](../capabilities/runtime-evidence-current.md#u02-three-lighting-fresh-20261018) |
| U05 · 3723344874 | 人物背后烟雾/涡动仍开放。10-18单帧双Dye的R/A有效、历史copy/交换及后级读回成立；后继静态核实际末combine消费交换前Dye版本、R取gradient+A作权重、原UV与transfer，未发现绑定首错，stock gradient本身A全满。下一门须以合格同帧空间分布、实际uniform与可归因ROI区分；mask/历史可在发射区外贡献，不能凭一个预期质心判错。不重查是否生成、重复绑定审查或盲加时/增益。[内容及消费边界](../capabilities/runtime-evidence-current.md#u05-fluid-content-20261018) |
| U10 · 3793998447 | 默认头外白细环缺失在10-18原包混合PCM复验未再现，23/25与20/51已实际Program/GPU/末合成及下一帧。旧音频响应与具体属性差异仍待同输入定位；七项有源绑定不等于已验编辑，低频总量不代64[0]。不再排“整环Program不支持”；[当前资格](../capabilities/runtime-evidence-current.md#u10-active-ring-20261018)。 |
| U11 · 3792249095 | 2026-10-18用户补报外圈样式差异大，待当前身份复验。旧10-18原包主亮内三角在白月牙内侧，官方主亮圈在外侧，外围暗圈仍在。254-off与233-off均未去掉主体图案，前者改变全景亮度；底图本含图案，alpha0亦不等于关闭。三run实际执行/正常排空，但音源/phase未齐，不据此改相机、半径或涡旋系数。独立标尺已证基础square Sprite half符合官方，退出全局×2修法；晨晚输入未驱动目标环参数，非本反馈关闭。[当前资格](../capabilities/runtime-evidence-current.md#u11-visible-ring-20261018)。 |
| U13 · 3042492564 | 10-22已闭普通图片additive被丢为source-over的首门：默认炫光X核心粉暗→白亮，关闭Shine亦保持，原三effect/末消费正常；[有界后验](../capabilities/runtime-evidence-current.md#builtin-image-additive-rgb-20261022)。不能据此关闭光束形状、媒体封面右裁切/blur、布局及媒体交互余项；官方同phase/全属性未验。旧倍率输入及非有限origin已闭不重开；544作者ReferenceError:event不列host缺口。 |
| U14 · 2932157836 | 封面、时钟及named-user旋转首门已闭；10-18原包102/272跨owner取消异常及后续disabled也已退出。同媒体/八点快速轨迹继续接收事件并回收，另一次持续hover正控实际展开标题条、离开后收回，正常排空；不是完整来源/官方phase验收。这里只保旧blur/精确spin样式及媒体来源仲裁差异，不重修timer身份门。[取消后验](../capabilities/runtime-evidence-current.md#shared-timer-cancellation-20261018)、[named-user证据](../history/named-user-pass-scalar-2026-10-16.md) |
| U15 · 3299228616 | 只保hover水波弱的输入/内容差异，须实际pointer与可归因ROI，不抬gain掩盖。时钟上方矩形已按childless copybackground=false优先修正并退出：原包保留scroll实际执行而不再滚动背景，独立347默认背景复制/网格保持。[源选择后验](../capabilities/runtime-evidence-current.md#childless-passthrough-background-20261018)；未验完整交互/音频/字体与官方同phase。 |
| U17 · 3233141951 | 10-19当前原包20s已证52/482 origin/angles及45/119 origin六binding，在14.03–18.65s十次实际surface输入均为timeline，后两次回作者基值；旧“头发值未导出”退出。脸随头发/龙头/小人/刀的准确轨迹仍open，沿pose/world与官方同phase定位，不再补Timeline发布。242火焰的absolute alpha+relative origin/scale组已沿原owner准入，旧新原包25s肩颈火焰恢复按段淡出；只关此首拒，脸/龙/小人/刀轨迹不关闭。旧“零key锚点推整段静止”撤销，enabled handles有偏移。403原请求513仍因当前数值污染Bool seed而拒；单变量资格 `../../../.artifacts/scene-evidence/runs/u17-animation513-qualification-20261017/manifest.json`仅把该visible改原literal true后，clip458实际播放/105份geometry已证，共享atlas及无UV证据使左侧黑形像素归属和可见收益仍UNKNOWN，已停止此修法；重启需可归因ROI或新producer证据。双色音频旧观察仍待同声源；10-19原目录46文件无PNG/JPEG，仅preview.gif，用户所称官方截屏仍待定位，不作视觉结论。[Combined边界](../capabilities/runtime-evidence-current.md#combined-timeline-playback-20261017) |
| U19 · 3807668787 | 灰头冠/音频反馈已闭；958的A2C仍为能力首门，尚未证成当前可见缺图。10-18候选虽实际完成绘制，离散pointer图未确认拖尾；官方原包连续pointer的短白双线也未唯一归958。原型已撤回，保局部拒绝；先取得唯一ROI、实际几何/采样与有效时序，不以初始化色值或执行计数关单。[资格与停止](../capabilities/runtime-evidence-current.md#particle-coverage-qualification-20261018) |
| U24 · 3420215721 | freeze/封面依赖首门已闭；中央环官方亮度具体差异待当前复验。349/409 circular_text默认hidden且无激活证据，不计缺字，不改作者alpha补偿。[关闭首门及边界](../history/terminal-attachment-desktop-freeze-2026-10-10.md#u24-cover-dependency) |
| U28 · 2684431262 | 2026-10-18用户补报官方略有发光，待当前身份复验；并入原整体合成差异，先锁发光ROI及同状态官方输入。旧10-18原包fresh已见倾斜青环/白盘、代码和洋红圆粒子，未见旧巨大紫块；139原色本为洋红，239/355/405实际Program/GPU/末合成/下一帧，不能按颜色判占位。250²作者GIF非同viewport/phase/音源参考，不据此关闭原反馈或改参数。[本次资格](../capabilities/runtime-evidence-current.md#u28-visual-qualification-20261018) |
| U29 · 3470948192 | 默认35s已越过intro仍黑水滴、缺亮边/拖尾；115.scale非有限返回仍在，旧公式NaN不再开放。F5原型无可认收益已撤回；后继固定官方模型载体两OFF均未通过环境/健康正控，入口机械纠正也未闭合，反射空间/能量保持UNKNOWN，不重跑未资格载体或调距离/亮度追图。[原型停止](../capabilities/runtime-evidence-current.md#model-reflection-prototype-20261018)、[后继资格](../capabilities/runtime-evidence-current.md#open-visual-qualification-20261018) |
| U30 · 3750813609 | 当前原包时钟颜色差异已确认，按[Clock资格](../capabilities/runtime-evidence-current.md#clock-color-current-20261019)STOP_UNKNOWN；证据不足，未实施Text白源/模糊修改。雨弱待同phase复验，缺雷电仅用户不确定观察。10-16复核121→lightning2为普通Sphere/rate1、无periodic cap，未见root静态拒绝；旧405/412属3749463715，详[静态审计](scene-full-sample-static-audit.md)，不据此推视觉原因。 |
| U31 · 3264246690 | ①人物边缘锯齿；②警戒带运动仍待当前画面对照。旧头部出画/左肘缺块已有[稳定帧完整肢体后验](../capabilities/runtime-evidence-current.md#e-2026-09-13-puppet-world-geometry)，不再列待修。点击口罩已有before戴口罩→click露嘴及effect切换的[实际后验](../history/authored-layer-retirement-2026-10-07.md#project-visibility-complete-retirement)；pool误拒另修，不据这些关闭AA/运动或整样本。 |
| U32 · 2131872317 | 10-20当前Debug原包22s静音/中心pointer，只切blue、红橙保持：5次接受同surface1/window3072，root1375的四子模板均准备/0unsupported，实际GPU完成241帧、571批含25折射；原图有蓝放射短线→稀疏亮点阶段。仍未取得完整上升轨迹、逐子路径/出生空间和官方同phase正控；目录官方截屏无蓝爆炸，2s/200×200 GIF未资格。首错UNKNOWN，不记已修，不调重力/速度/RNG；后继先取得连续官方蓝色周期及同状态参考，不重跑同native短窗。[有界核查](../capabilities/runtime-evidence-current.md#blue-firework-qualification-20261020) |
| U33 · 3769688830 | 玩偶应左右循环转而现单向转的反馈保留。47黄球有合法单向Spin，同时从Puppet父21继承挂点运动；目录预览未覆盖黄球，当前目标ROI及整段运动尚未资格。须先分清内部UV转动与世界挂点往复，不能以Spin单向证明作者设计或新造摆动；不重开已STOP的aux morph载体。[最近资格](../capabilities/runtime-evidence-current.md#ring-motion-qualification-20261018) |
| U36 · 3780119725视觉余项 / pointer新观察重开 | 2026-10-18用户补报人物/地面/摩托中层仍不随鼠标、摩托发光过强，待当前身份复验。旧10-18缺席深度修复后，原包短pointer轨迹已见前摩托与人物响应；21/276及附属层prepared1,1，显式879=1.91保持，此有界证据保留。新范围重新开放，先锁具体层ROI、轨迹/属性与光照状态；不由基本响应外推delay2/gain或整景一致。脸部黑线/缺块、动画、光照/闪烁旧观察继续保留。[旧有界后验](../capabilities/runtime-evidence-current.md#visual-feedback-followup-20261018) |
| U37 · 3769364482 | 只保三Shake的Breathing及发光突现风格待可归因复验。10-18原包完整窗内rayintensity实编码负→0.45→负且红晕亮起/回落，五node GPU/末合成正常，退出基本loop/opacity缺失候选；常驻青Shine与人物不应随负信号消失。[实际资格](../capabilities/runtime-evidence-current.md#u37-scalar-loop-20261018) |
| U39 · 3219398263 /2932631210 | 321方向疑似相反、两者背景漩涡差异仍开放；293原人物恢复不闭背景。10-19仅其mode31静态环珠化低清有[有界恢复](../capabilities/runtime-evidence-current.md#additive-terminal-density-20261019)，不证方向/全variant/整样本。各ROI固定状态再裁决，不凭单帧改符号或共用根因。 |

低优先旧观察仍记录：3028090166光束、2419444134白点数量/密度、3113554287顿挫、2304304373雾气叠加，以及尚缺唯一sampleID的一般烟花/洋红/拖尾。按可见收益与可区分输入依次复验，不把旧观察无条件写成当前缺陷。3088601835雪雾用户已认为较正常、官方也过曝，保此降低优先级的反馈；没有新的具体差异不补调色修法，也不记全条件通过。[原用户观察与身份](../capabilities/runtime-evidence-current.md#e-2026-09-27-user-retest-priorities)

### 反馈退出 / 证据边界

下表仅对列明现象作有界备注；“原反馈已闭”只表示列明的历史现象有实际关闭记录，**不是整样本PASS，也不是当前HEAD重测**。同ID的新补报与其他余项仍保开放，不因旧主故障退出而销账；声源、phase或更宽profile未验本身不新建故障。

| 样本 / 状态 | 具体反馈与已有证据 |
|---|---|
| 3707474273 /3775655074 · 顶层组合根效果未接入已闭 | 10-22五根15个pixelate/VHS/pulse实际Program、GPU/末消费及次帧完成，TV马赛克、噪声与RGB彩边恢复，人物/背景保留。新profile限顶层正交普通成员、无utility后代；隐藏往返沿原typed准备且不重建窗口，旧nested及普通背景组保持。独立378分栏健康；仅关闭已证缺失，官方精确grid/alpha/HDR/全部属性及整景未验。[有界后验](../capabilities/runtime-evidence-current.md#compose-subtree-qualification-20261021)。 |
| 3782614820 · 分栏越界/接缝错位已闭 | 10-22原包同viewport/静音/中心pointer对照，五根由仅保顺序变为局部源，五人物切片接缝与四黑分隔线对齐，子图效果继续执行。无根authored效果的普通正交背景组复用现pool/源映射/唯一输出；终端直绘补一次根alpha消费。仅关闭这项公共裁切断点，目录无官方截屏，完整属性/时相/HDR及整样本parity未验。[原图与限定后验](../capabilities/runtime-evidence-current.md#composition-background-bounds-20261022)。 |
| 2784267518 · 眼部音频完全无响应本窗不成立 | 同签名Debug下原包强PCM及observer强/零、仅181关闭四窗：实际16档前两项左右四值稳态均值0.735466–0.737913、作者响应0.456448–0.463767，零臂全0。两对眼内轻微提亮，关181同强输入后减弱；181合法inactive旁路、相邻效果与image终端replay保持，附近非眼对照基本稳定。退出“完全缺失”修法；不声明额外halo/alpha变化、正常系统capture需求或官方同音源强度一致，具体新差异再开。[本窗证据](../capabilities/runtime-evidence-current.md#pulse-eye-response-278-20261021)。 |
| 1994794519 · 默认揭露投影/本视口物理偏差已闭 | 普通图片末材质消费实际放置的MVP/inverse，原包受控三点由目标无揭露恢复目标揭露，源/前序效果保持；10-23无注入实际鼠标左/中/右揭露获用户确认。仅闭本视口反馈，更多DPI/多屏/属性及整样本未验。[有界后验](../capabilities/runtime-evidence-current.md#image-terminal-placement-20261021)。 |
| 2999907577 · 默认7号流体背景缺失已闭 | 共享opaque辅助颜色边界及alpha-only旁读反馈资格修正后，原包金属流体与上方文字实际恢复，人物保持；7/7 layer capability、原20节点及后续帧执行、正常stop/GPU排空。仅关闭最大缺失，全部模式/参数、精细灯光、HDR与官方同状态数值未验。[有界后验](../capabilities/runtime-evidence-current.md#independent-signal-opaque-auxiliary-20261021)。 |
| 3766299002 · 面具开关失效本窗未复现 | 10-21 theme1初始true→live false、theme2初始false→live true，两条原226/370 visibility及脸/眼覆盖随定义变化，surface/window保持。仅这两个单向链，不是两主题完整往返、真实面板/持久化或官方全mask验收；用户笼统异常未取得更具体反例，暂不排产品修法。 |
| 3742497499 /3822822401 · 早截图视觉候选撤下 | 用户明确374需鼠标移右让两块时钟拼合，382蝴蝶延迟出现，既往测试正常；不再排“孤立02/缺蝴蝶”。独立粒子profile与metadata首错保留，不与已解释现象建立因果。 |
| 3448845950 · 本次无法启动已闭 | 原691依赖锚点错配导致零帧/首帧超时；共享compiler修后原包真实播放，独立302保持且正常排空。仅关闭启动阻断，局部脚本与旧布局余项仍归上表；[有界后验](../capabilities/runtime-evidence-current.md#named-dependency-direct-anchor-20261020)。 |
| 3745828537 · 外围花簇首断点关闭 | 普通Sprite coverage材质沿原准备/Metal链准入；同静音/中心pointer原包，51/65由模拟前拒绝到实际花簇铺回左右和四角，原人物/前景保持，默认particle 4/4。不是整样本PASS：预热200秒仍受344步预算，完整时相、属性和官方像素未验；旧Rope958未借此开放。[最终原图与独审](../capabilities/runtime-evidence-current.md#sprite-alpha-coverage-20261020) |
| 2849382252 · U26白线低清有界闭合 | [同pixel后继](../capabilities/runtime-evidence-current.md#background-terminal-density-20261019)中，原三弧在保2048²/原Program下恢复连续白芯，人物/遮挡保持，replay/GPU/末合成及下一帧成立；仅闭本反馈。旧末弧原型STOP保留，不扩其他视觉、官方phase/音频/HDR或整样本/性能。 |
| 3748311238 · 柱盖高端悬留有界闭合 | [轴域后验](../capabilities/runtime-evidence-current.md#utility-axis-domain-20261019)中，同动态宽频 PCM 修前/候选约2/6/8s实图显示高端平台退出、柱盖继续移动及圆角恢复，主体保持；用户最新App实测正常、撤回低/缺/卡观察；仅关闭本反馈，不扩全部音源/variant、精确phase、HDR、清晰度或整样本。 |
| 3554161528 /3581882134 /3603711180 · 开场镜头缺失已闭 | 10-19原355从修前始终全景恢复近→全，App0/无漂移/正常stop与GPU排空；本批报告 `../../../.artifacts/scene-evidence/runs/opening-camera-halfspan-20261019/current/report.json`保字段资格、首失败与实际原图。358/360原包近→全、358关闭Opening直接全景的旧[后验](../capabilities/runtime-evidence-current.md#default-camera-single-20261019)保持；358光照仍U02、360Blur余界分列。仅闭镜头缺失，非同phase/viewport/pixel、其他视觉或完整互动验收，不升级整样本。 |
| 3585542943 /3603711180 · 笼统缺光本窗未重现 | 10-18默认12s原包的series8原图分别可辨青绿扇状照明、左帘/发/肩光，目标粒子均有真实GPU完成；不同aspect/phase/音源，不判精确强度/光形或完整播放。358188暖亮/冷暗仍保U02；360旧Blur数值首拒已闭、细条收益未辨，三包开场缺失已独立闭合，不代验光照。[有界复验](../capabilities/runtime-evidence-current.md#u02-three-lighting-fresh-20261018) |
| 3754630802 · 狮头眨眼反馈已闭 | 10-18官方固定姿态仅源Z清零对照与旧native对应定位蒙皮前丢Z；同一Evaluator完整XYZ→四influence→XY恢复固定闭眼，原包实际两次开→闭→开，头部未整体跳位。Z0/平移/Rz邻例与改名/重排、最终溢出已验；不认领完整30s、所有动画/互动、官方数值或性能，整样本仍unreviewed。[有界后验](../capabilities/runtime-evidence-current.md#u27-lion-blink-qualification-20261018) |
| 2974757317 · 卡片下多余矩形反馈已闭 | 10-18原包两帧不再出现下方重复卡片矩形，主卡/title/artist/日期/背景保持；合法无回调Bool模块现留在最终共享域，三个origin首值保持作者屏外Y=-1850，旧376 invalidSource退出。官方同viewport原包与初始化标记实验、改名/等价式及失败域重建门分别支撑此链；独立3351163962布局保持。不修改AudioBars、mask或作者坐标，不认领全phase/音源、完整交互及整样本PASS。[有界后验](../capabilities/runtime-evidence-current.md#u25-u35-current-qualification-20261018) |
| 3351163962 · 默认hour/seconds/greeting旧范围已核对 | 10-18原包默认、同908×590官方A两帧与当前native相对环心的hour/seconds/greeting最大单轴差1.643px，低于预锁4px门；时分秒均在环内，问候均跨圆右侧，bbox相同。只保此范围的官方一致裁决；新补报左上文字超环归上表，待确切文本/状态，不称全部文字反馈已闭，也不据旧GIF改anchor/相机。[有界对照](../capabilities/runtime-evidence-current.md#u25-u35-current-qualification-20261018) |
| 3802005866 · 蓝色越界/框外音频细线反馈已闭 | 10-18同22输入原包显示中蓝条、底部框外白细线消失，框内非零频谱保持；修复的是正交透明成员组的父本地源边界，无effect也沿原pool/compositor输出一次，白框不作clip声明。named enclosing采集、终端重放、尺寸cap与安全邻例已验，独立原U01有界保持、最终独审无阻断；整景/官方同phase与HDR未扩。[有界后验](../capabilities/runtime-evidence-current.md#composition-member-bounds-20261018) |
| 3750342273 · 受控视差缺失未复现 | 10-18原省略深度首门修复保留；10-19当前0ea907d9a对应App原包、3024×1964、七点归一化输入，山体左右/上下移动并回中心、零深度文字固定，独审一致。退出“渲染链完全缺视差”的已确认缺陷排期；不是新修复。真实鼠标/桌面路由、多屏、官方精确gain/delay尚未验；若有可定位输入失败再开。原计划入口冲突失败与实际after时刻保留，不记整景PASS。[本次范围](../capabilities/runtime-evidence-current.md#parallax-depth-omission-20261018) |
| 3797217144 · 基础入场/横倒首反馈已闭 | 10-18原输入的Single angles→scale不再因响应选项而整组冻结：先保蓝环背景，再恢复完整转正人物。作者选项保留，未实现响应明确为基础曲线近似；固定官方原包及删键变体均见正向人物。精确平滑/phase与整样本未验，不另造已证视觉缺陷。[有界后验](../capabilities/runtime-evidence-current.md#single-timeline-response-fallback-20261018) |
| 3396722575 · 头发/身体动画首断点已闭 | 10-18原包两层modern dense常量中性轨道进入唯一准备/pose链，原nested lookup异常退出，实际init stop→event play、两目标frame推进及各144个不同几何GPU完成/末合成成立，三原图保持人物/发/身体与背景文字。未知state1 payload、独立reference/多opaque未开放，不记完整交互/官方同phase或整样本通过。[有界后验](../capabilities/runtime-evidence-current.md#constant-dense-state1-20261018) |
| 3617056047 · 位置/倒置反馈已闭 | 10-18原包罐体恢复正向并回虚线圆内，不再压底字；作者origin/scale与camera保持，原准备入口完成静态mesh顶点基适配。真实单面/背剔除、父级/负scale/native及三shadow通过，独立native原包有界呈现；不记全样本、精确亮度/同phase或全部互动通过。[后验](../capabilities/runtime-evidence-current.md#static-model-canvas-basis-20261018) |
| 3471294034 · 缺网格反馈已闭 | 10-18原包默认实机恢复背景菱形网格，人物/文字/花瓣及频谱保持；368沿原链只选159，371/373实际GPU及末合成成立。双候选切换/变体和相邻拒绝已验；仅关闭报告的缺网格现象，不记整样本/全部属性通过。[有界后验](../capabilities/runtime-evidence-current.md#selected-provider-admission-20261018) |
| 833227004 · 原反馈已闭 | 原流动缺失已有多帧source输出与留白消失的[实际后验](../history/source-material-entry-2026-10-08.md)；未称官方同时间parity。 |
| 2797913147 /3748311238 /2932631210 /2813231542 · 旧主体缺失已闭 | 原主体人物消失分别由[旧版mesh](../capabilities/runtime-evidence-current.md#e-2026-09-14-puppet-mdlv0014)、[精确atlas](../capabilities/runtime-evidence-current.md#e-2026-09-14-puppet-exact-atlas-effect-extent)与[三样本原图刷新](../capabilities/runtime-evidence-current.md#e-2026-09-14-missing-subject-refresh)关闭。374831柱盖另见本批有界闭合；293背景圆环/漩涡仍在上表，3788467391漩涡也保持partial，不记整样本通过。 |
| 3113287126 · 旧锚点反馈已闭，方向/数量开放 | 原红粒子从腿部移回琴/持弓手，人物动画后仍锚定该区域；[同输入前后实图](../capabilities/runtime-evidence-current.md#e-2026-09-27-puppet-legacy-attachments)只关闭该锚点。新补报方向/数量归上表，不外推密度、视差或长稳。 |
| 3122339805 · 原反馈已闭 | 两窗口持续显示/拖动、文字与X偏移有[实机及用户复核](../history/event-visibility-persistence-2026-10-10.md)；后继媒体进入后停帧有[真桌面关闭证据](../history/terminal-attachment-desktop-freeze-2026-10-10.md)。连续拖动/全部设置未验不另造故障。 |
| 3232289987 /3587571382 · 原反馈已闭 | 分别为[头发/五官回头部及右臂重接](../capabilities/runtime-evidence-current.md#e-2026-10-08-puppet-v21)、[原视差开启时额头裂缝消失](../capabilities/runtime-evidence-current.md#e-2026-10-08-inherited-parallax)，各有原包实际输出。 |
| 3238423642 · 头错位已闭，成本另判 | [原包布局/世界矩阵实图](../capabilities/scene-sample-debug-ledger.md#2026-09-13-3238423642-scenescript-world-matrix-与作者布局初始化)确认头部及角色组装；旧18.7 FPS未验收不能随视觉关闭写成性能已修，也不直接判当前掉帧。 |
| 3357627941 /3662390671 · 原入口/缺图反馈已闭 | [本地视频选择与最终前景可见](../history/user-property-video-2026-10-16.md)、[WebM人物/背景恢复](../history/embedded-webm-video-2026-10-10.md)分别有真实输入/输出；更宽媒体profile不是同一原报告。 |
| 3747190633 /3807151772 /3782740481 · 原缺条反馈退出 | 前两者[原条带可见并经GPU/末合成](../capabilities/runtime-evidence-current.md#e-2026-10-08-localized-graph-input)；3782740481在[16秒受控非零输入](../history/named-timeline-interaction-2026-10-10.md)三环均可见，原完全缺失未复现。仅此输入范围，不记外部音源/幅度parity。 |
| 3765760121 /3788734811 · 原倒置反馈已闭 | [退役用户反馈的实际截图裁决](../capabilities/scene-sample-debug-ledger.md#用户可见失败待办按当前复现更新不以公共修复代替逐项验收)分别确认默认鱼眼及perspective卡片恢复正向；整体验收原值不变。 |
| 3787382101 · 原mask反馈已闭 | [六组同构A/B](../capabilities/runtime-evidence-current.md#2026-09-13-3787382101-water-waves-作者-mask-同构-ab)证Water Waves只作用于对应mask；旧“影响人物全身”裁决已过时，不改整样本verdict为PASS。 |
| 3796588443 /3804441338 · 所列旧现象已闭 | 分别为[异常强网点/混合与频谱](../history/shared-shader-type-compatibility-2026-10-09.md#solid源尺寸后继)、[镂空两框及时间日期](../capabilities/runtime-evidence-current.md#e-2026-10-08-frame-declaration)的实际关闭；受控输入不升级整景/外部音源。 |
| 3806337293 · 灰层/过曝/缺环及路径自转反馈已闭 | 10-18当前原包先重现首段索引编译拒绝，修共享准备顺序后双环/人物恢复；用户后补官方无音频固定路径观察，原App静音14s多相位仍轴向变化。后继只修无Candidate程序化solid源域，保作者1024²，3/6/12s实图椭圆轴稳定、点列继续移动；非零PCM条目响应保持，两个末段GPU/末合成与下一帧、独立381实图及正常stop均成立。仅关闭所列反馈，非官方精确速度/幅度/同aspect全图或整样本PASS，见[原索引与后继源域证据](../capabilities/runtime-evidence-current.md#procedural-solid-local-source-20261018)。 |
| 1695673397 · 同aspect已解释 | [原生75px与官方约35–37px灰带](../history/default-2d-camera-inputs-2026-10-16.md#169露底资格与正常比例差异)在二倍尺寸同aspect下占比差不超过预设1个百分点；该比例非独有缺陷，不拉伸遮边，不推广所有比例。 |
| 3226487183 /3264246690 /3807668787 · partial | 322眼球/默认动画、侧脸脸颈及点击色散已由上方实际后验关闭，手部仍在；326旧头/左肘与口罩已闭，保AA/警戒带；380766头冠/音频已闭，保958 pointer轨迹准入。不能标这些样本全部反馈已闭。 |
| 3509243656 · 关闭裁决待补身份 | [旧用户反馈表](../capabilities/scene-sample-debug-ledger.md#用户可见失败待办按当前复现更新不以公共修复代替逐项验收)写“当前渲染正常、实机确认，旧记录过期”；具体App/输入/图片身份弱，先补链，不从旧fail重开开场/模拟画面或坐标文字故障，也不记HEAD通过。 |
| 3766387484 /3792817546 /3790726145 /2986218263 · 仅保验收边界 | 前者日期/星期/时钟旧首门、后三者CP/Rope/pointer准入已记恢复；剩“其他effect、原生输入、官方宽度/UV/颜色未验”不是新的具体故障。保台账/专项范围，新具体现象出现时逐项补证，不新增泛化任务。 |
## 3. 性能：先取得当前可避免工作的证据

3724289844的半帧率已限定到本轮未优化Debug条件；独立时间线确认在途延后与正常cadence空档，但同源码优化Debug普通窗达到目标帧率。本轮停止timer/clock/history修改，不认整体性能收益或温度根因；[资格与保留边界](../capabilities/runtime-evidence-current.md#water-cadence-qualification-20261021)。

专项阈值、有效基线与NO-GO/STOP只由[性能卡](performance-convergence-card.md)维护；本页不另建优化campaign。以下不是永久启动失败、泄漏或整引擎掉帧结论。

| 项目 | 最后信号 / 下一门 |
|---|---|
| 用户反馈 · CPU高温与GPU满载 | 用户报告CPU频率不高时温度仍接近100°C、GPU经常满载；当前未锁定对应设备、样本、配置与同窗成本，不记已修或直接判瓶颈。按[性能卡](performance-convergence-card.md)联合归因整进程CPU/GPU及实际工作，复核重复运算、主线程/后台争用和最贵pass；已有局部收益不关闭此整体反馈，温度/能耗未测不认领。 |
| N09 · 重型冷启动/准备 | 10-11的3476868923、3507496797首轮69秒超时，延时后153.425/93.820秒ready；10-16原3662790108冷120秒仍shader准备、无画面。prepare-catalog70.338s包含model-build43.313s，不相加。先定位当前唯一大成本与可省工作；不能再以延timeout、重开MDL/cache/排序或降低内容当优化。[最新归因与撤回](../history/shader-value-type-recognition-2026-10-16.md) |
| U22 · 3805547608视频越播越卡 | 10-08用户报告保留待当前普通App长稳复验；该包65/100秒双视频未见递减，只排除该短窗口。点击切背景首门已闭，不借此关闭长时成本，也不继续声称所有视频普遍递减。[有界运行](../history/named-timeline-interaction-2026-10-10.md) |
| 视频发布空档 / 动态视频实例 · 3372715909 | 10-22固定291临时观测原包20s：100非loop发布空档1.682s，578次prepare含144次hasNew=false、428新帧全部发布；copy/导入失败0、无秒级同步API阻塞。仅定位AVPlayer输出availability，内部解码/转换/队列UNKNOWN，不与旧3.180s算收益。旧包装因footprint退步撤回，不重复；120动态实例/dormant仍开放。输入、原图、独审/失败`../../../.artifacts/scene-evidence/runs/scene-source-diagnostics-20261022/`；[原设计](../capabilities/material-video-assets.md#video-consumer-demand)。 |
| 3749463715 · 观感帧率低 | 2026-10-18用户补报，待锁当前设备/App、属性、时间窗与实际提交/呈现率；观感不等于已测FPS或性能回归。重复胸部拖动仅首次的独立交互反馈归U40，不以性能检查替代。 |
| U24 · 未提交/提交率 | 10-10实际音频60秒931帧不再freeze，但旧1879未提交/提交率需当前有效分母与drop原因；不是已证当前预算不足。中央环亮度归U24视觉项 |
| 轻重切换后驻留上移 | 已缩到purgeable分配，实际持有owner未定；先补有效分配来源与退出平台，不重复无caller整轮切换，不把allocator驻留当泄漏。[当前证据](../history/scene-switch-residency-qualification-2026-10-15.md) |

旧323 ready后超时、322冷shader变慢与累计tombstone扫描，只在取得当前有效运行/可避免工作后进入上述启动或稳态项；旧FPS及源码复杂度不是新性能缺陷。已撤回的声明准备等方向不因队列整理重启。
## 4. 属性热更新与编辑重建

具体能力边界与选题只归[属性卡](properties-panel-card.md)、[输入覆盖](../capabilities/runtime-input-property-coverage.md)。已闭视频入口、普通图片brightness、named pass scalar和Sound mixed paused refresh不再列本页待修；其未验的全codec/所有组合不改称当前故障。

| 项目 | 当前边界 / 最小下一门 |
|---|---|
| U42 · 面板打开/编辑、长Combo与显示语言余项 | 原生列表/AX滚动及有限本地化已有有界验收；旧“浏览严重卡顿/中文都变英文”不能无条件沿用。打开/编辑总延迟、完整系统键盘chrome、长Combo完整显示及更多locale仍待当前实际资格；未审词汇不直接算错译。先单个可达控件和用户动作/成本，沿原Intent→store→consumer验证 |

显隐slider/缺定义、条件-only Combo、maxwidth script等旧声明/候选不等于缺热更新：先有同身份instruction/callback/rebuild及可见consumer资格。314 fireplacesound属Sound mixed，已修；304 clock_lang已有真实text模块applyUserProperties consumer，亦非condition-only；不另造condition evaluator或value-only旁路。

## 5. 其他有具体依据的合同/验证债

| 项目 | 证据边界与下一门 |
|---|---|
| text `size`更新时序 | **静态候选，非U25当前根因。** VM getter只读catalog size，实际文字排版另发布logical extent；text/font/pointsize待写值与size分离。公开合同仅称只读像素分辨率，setter后何时刷新、padding/装饰边范围仍未证；先取得行为资格，再决定复用唯一CoreText测量owner，避免getter/raster重复排版或把parent投影尺寸写回逻辑size。 |
| 跨owner sort的重复property dirty归属 | 3808922316的sort已写唯一topology journal，随后重复property DTO标脏与另一owner冲突，被误报mutation buffer exceeded；182层/每owner单次sort不构成容量证据。三次成功调用的最终顺序与旧首次成功相同，另外两owner实际隐藏，未证额外可见收益，暂缓实施。后继应退休sort的冗余property标脏，保原topology顺序/owner/rollback及普通property门；不扩大buffer或另建排序owner。资格 `../../../.artifacts/tmp/380-layer-sort-qualification-20261019/research/result.json`。 |
| Timeline event-only attachment归属 | **静态反例，无真实受影响target资格。** Vec2/Vec3或numeric String可能尚未获VM control owner，却被classifier仅凭event-only吞attachment；10-16三包只见已支持Number control，资格已停。后继必须先证target及proven control owner，再复用原Timeline值源；不扩API或继续宽搜。[当前API边界](../capabilities/scenescript-api-coverage.md) |
| 普通桌面captureFrame返回1×1 | 10-15的3766415113 daemon已呈现而ScreenCaptureKit仅1×1 JPEG，同输入Metal诊断可完整；待当前窗口frame/捕获时机复验，不把诊断替代图当普通capture已修。[原尝试](../history/shader-completed-cache-retention-2026-10-15.md#未完成边界与无效尝试) |
| 10-17新可达脚本/粒子首错 | 359777 Bird的省略距离与零origin world CP旧拒绝已按[源空间合同](../capabilities/particle-component-coverage.md#control-point-force-的源空间与缺省距离)退出；operator10非零world origin仍拒，当前默认窗口270无非空粒子/可见鸟群UNKNOWN，既有音频发射response原因未证；360的196/205单图atlas Rope旧拒绝已[退出](../capabilities/runtime-evidence-current.md#rope-whole-source-20261017)，只保49.visibility notfunction。360的49.visibility后继读源锁console.warn为静态候选，实际目标55是MP4-backed image，视频控制API已有；旧TypeError缺stack/初始available，callee仍未证。停止据标签补API/改media类型；窄资格 `../../../.artifacts/tmp/360-visibility-notfunction-qualification-20261018/qualification.json`。具体运行/输入只归台账，不把入场phase再排camera。 |
| 粒子剩余真实unsupported profile | static depth-one child Rope首门已闭，不再保getsuga Z=2缺口。新增3795384177的122/116默认`mapsequencearoundcontrolpoint`只写count5，现plan要求显式repeat/bounds/speedmin/speedmax，实际`positionAroundControlPointUnsupported`并跳过该initializer；两源仍有child/粒子，不等于整系统失败或已证光环缺失。省略值官方合同未取，沿原出生/CP owner资格后补接。mapsequencebetweencontrolpoints、控制点约束、nested/event、非均匀child变换及深层duration/9999 delay仍独立保留。[唯一profile合同](../capabilities/particle-component-coverage.md)、[已闭首门](../history/static-child-rope-2026-10-16.md) |
| 新增控制点距离/event色 · 3742497499 | 135默认活跃、有GPU输出，但距离算子未接。10-22自有官方板0/1半径均100，.1为129→126，零值不约束预设失败即STOP；静态只证reader，零值/时长仍unknown，不选公式或重跑矩阵。174事件色另拒，该名称已有有界owner，不泛化；与时钟无关。证据`.artifacts/scene-evidence/runs/particle-distance-cp-qualification-20261022/`。 |
| 源码目录合同漏登记 | 10-22固定4749df8f7与文字候选均有6个既存filename mismatch：Lighting输入、3个UserShortcuts、Puppet属性准备及shortcut dispatch；本批无新增目录违规。先按现役owner核准登记，不移动或删除合法代码消红；有界收据归`.artifacts/scene-evidence/runs/native-text-bounds-20261022/`。 |
| 全样本诊断工具边界 | 10-22 census raw373/parsed372完成后仍因旧376仅shaders缺`has_manual_screenshot`崩溃；本轮只由exact occurrence索引及实查目录补展示，保原失败。声明统计已分总览/373行清单，原writer尚未支持两页，不能直写现役页或称verify通过。pointer会提前写after；归一器还把378/381隐藏/特殊solid记load-incomplete、380隐藏分支异常记降级。保raw，人工限定，不把结构标签当可见缺陷；沿原生成/归一owner补失败行、两页写出及显隐反例。 |
| 光照数值合同余项 | point剖面差异、spot父级缩放及更广2D ambient/spot/directional的精确响应未取得完整公开控制；先分consumer、固定法线/位置/父变换的官方自有正控。已闭灯数/零点、shadow朝向和模型表面响应不重修；R40逐动画播放已闭，见[共享角度合同](../capabilities/advanced-object-coverage.md#standalone-spot-playback)。[光照范围](../history/2d-lit-image-light-contract-2026-10-06.md)、[模型合同](../history/static-model-light-input-semantics-2026-10-06.md) |
| RF05及真实跨层/跨屏、异步故障组合验收 | 原property→dependency/provider闭包→Session唯一evaluation→simulationFrame→各surface独立提交→唯一compositor已分别有界执行；[readiness后验](../history/rf05-named-provider-readiness-implementation-2026-10-02.md)不证明全部组合。物理多屏/clock、跨surface VM/粒子/Puppet cadence、late epoch/purpose、重建中拖动和异步故障仍未联验。先实际可达组合与取消/退休反例，不新增第二事务或每帧heap序列化。[输入/lifecycle范围](../capabilities/runtime-input-property-coverage.md) |
| 两条历史GPU门与hidden extent覆盖 | persistent_history_visual_failure_gpu的initial passthrough、preserved_channel_frame_local_unique的8项false只证固定f79088a5旧输入；hidden resolvedMaterial extent的Python桩P2也未取得fresh关闭链。先核当前真实harness/生产分支再判fixture或产品，不能据旧红声明HEAD故障。原271检查/32false已另行闭合，不再列作当前产品失败。[已闭graph债](../history/graph-color-purpose-reconciliation-2026-10-12.md) |

其余尚未覆盖profile按[材质/Graph](../capabilities/render-graph-shader-coverage.md)、[Effect](../capabilities/effect-execution-coverage.md)、[Puppet/3D与平台](../capabilities/advanced-object-coverage.md)维护：LUT/material、未证source/provider、alpha/nested clipping、Puppet mixing/ended、级联destroy、Vec4/matrix、未证歌词平台或物理HDR等，只有获得具体可达缺口/反例才进入本队列。family名、L0/L1、没有golden或某平台未测不单独排一个“当前缺陷”。Steam真实授权/签名安装任务归[获取合同](../../architecture/steam-workshop-acquisition-contract.md)，不从旧发布版本生成安装指令。

跨物理行函数宏的静态合同债已退出：同一展开owner沿连续active普通行处理调用与注释空白，保留来源行、token边界和早期预算；受控实际App由旧红/青恢复两侧纯红。独立347的网格/人物/文字等实际呈现保持，但冷启动占满原总时限而被截断，正常停止未验、原FAIL保留。没有已证受影响的真实作者样本，不刷新整样本verdict；[后验与边界](../capabilities/runtime-evidence-current.md#logical-macro-invocation-20261018)。

## 6. 进入、关闭与证据退出

- 每次只选有用户价值的共享首错；先固定输入/属性/时间/音源/viewport与App身份，标明运行反例或静态候选。缺资格先做最便宜的区分，不补样本算法。
- 保持authored→prepared Program/graph/resources→typed frame→Metal→唯一compositor；同一输入不可双owner。普通帧不新增解析/编译/整图序列化或哈希；资源安全失败拒最小不安全单元，普通视觉失败局部回退。
- 关闭需同语义正例、改名/等价输入及相邻反例、真实输出、健康独立样本与相称生命周期证据。按子现象退出，不能把局部修复写整样本完成；没有当前缺陷的作者关闭项不保“待修”。
- 旧人工verdict与全集运行关联仍由台账维护，未知保持原状；更新随有效代表批进行，不为刷绿重跑全corpus。报告必要截图/中性事实、失败尝试、drift、退出/资源回收；只在用户授权时提交/发布。
