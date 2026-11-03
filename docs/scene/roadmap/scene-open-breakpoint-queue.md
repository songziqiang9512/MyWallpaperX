# Scene 当前开放问题

<!-- document-role: active-plan -->

本页维护未闭问题、输入定位和下一步。按画面合成/正常播放、可证性能成本、属性接线、工具资格排序。架构归[当前主链](../architecture/runtime-architecture.md)，领域合同归[能力入口](../capabilities/README.md)，冻结身份与覆盖范围归[运行证据](../capabilities/runtime-evidence-current.md)。

2026-11-03 全量发现635目录，633有效输入均取得Ready、真实终端PNG和GPU排空，2目录缺project.json。默认观察Ready后4秒、约第3秒截图；稀疏/过场另补长窗。逐样本、逐声明阶段、原始失败与输入/App摘要保存在本机`.artifacts/scene-goal-full-sample-retest-20261103/`的`full-archive.json.gz`、`sample-results.md/json`与`task/`审查记录。33个初次运行CHECK不等于33个引擎缺陷，raw通过也不排除局部拒绘。

样本ID和layer仅用于复现，不选择算法。隐藏、空媒体、延迟和未触发分支不直接判缺图；Program准入、实际绑定、CPU求值、GPU执行、局部tail消费和最终像素贡献分别记录，未知保持未知。

<a id="implementation-gaps"></a>
## 本轮实测的通用断点

| 定位 | 当前事实与下一步 |
|---|---|
| shader重载 · 3042660491/127e0、3746066933/17e1 | 两例已获backend许可；实际为mix(vec4,vec3,scalar)与dot(vec4复合表达式,vec3)的stage-link/Metal失败。原BuiltInVectorConversion仅覆盖简单identifier，嵌套CAST3/dot和复合表达式未统一推导；在原typed intrinsic边界补通用参数转换，先资格混合宽度的作者方言语义，不按shader加正则。 |
| shader表示与许可 | 通用compiler仍有source形状colorTransfer补偿及unowned route门；已有typed colorBoundary时，ArtifactBuilder仍先生成专用MSL再丢弃该代码。沿原builder/typed ABI直接拥有lowering及metadata，保alpha-only、data/signal、输入/输出表示和实际接口约束；不把SourceAnalyzer识别名单扩成效果名单。 |
| linked timeline producer · 2999344788、3577990983 | bokeh的linked parent/children timeline在准备期报`dynamic-uniform-producer-unavailable`；原载荷未指出missing uniform，需沿BindingProgram/producer取得精确未接入字段。 |
| graph引用 · 2804817823、2972071249、3504669359 | secondary-self `_19_b`、forward `_234_a`、多provider `_91_a/_1030_a`被编译器拒绝。hidden辅助provider是否仍发布按真实consumer资格，不改成全局prepass或丢原作者顺序。 |
| subtree容器 · 3529515784/175、3825183869/187 | SourceRoute先拒container42及container403/402，后者下有15text/16solid。容器只承变换、不自产生draw；沿原parent闭包与render order跳过无绘制容器，不能按成员名单拒整个合法后代。 |
| subtree粒子 · 3465215190/2481、3781757083/133、3806222046/454、3809609151/42 | SourceRoute先拒子树particle成员；现layer main-pass能draw，但局部composition raster/camera消费尚未接入。补原粒子绘制的局部投影及target消费，不凭顶层可draw就裸放子树。 |
| subtree来源组合 · 3554161528/1111、3788897599/196 | 前者child411同时为dependency411，后者project带child291，均先被SourceRoute结构检查拒绝。与上两行共享错误码，不能统一归为后置dependency guard；分别核实际source/publication及project子树语义。 |
| 混合子树source · 3830727231/882 | 当前五个active effect（opacity、waterflow及3个shake）均`r5-no-runtime-owner`，同帧无882 sourceCapture/material/tail；children含composition93、particles202/206/209、solid790。原始与本次输入摘要一致、状态一致，首拒绝child尚未知；沿composition source接入核对，不能归为五个shader失败或用723 blur成功关闭它。 |
| Program阶段守恒 · 3086016320/430 | 明确`execution-stage-conservation`准备拒绝，原码由多个guard共用、具体缺项未知；沿ProgramFirstStages定位，保父426默认alpha=0的输入边界。 |
| uniform / provider · 3511024658/73、3759799379/319 | 前者`dynamic-uniform-unavailable`未给具体字段，不能直接称缺音频；后者dependency309报`dependency-provider-rejected`，需原composition projection/route首拒绝原因。 |
| source/模型 · 2804817823/28/32 | 9个资产已加载，两个Puppet source明确拒`MDLV0013`，不是两个纹理文件缺失。沿MDL/Puppet几何owner补格式/姿态资格。 |
| composition source · 3292370168/239、3039882306/772 | 前者active、无children/URL却引用151，持续未draw；hidden505另有utility capture失败。后者音频composition无对应CPU/graph/所选帧draw，需受控audio/source输入；hidden1084 pending失败、868 fallback不挪作当前可见层证明。 |
| world-space动态祖先 · 3448877775/15706 | parent15705有origin script/timeline，RopeTrail flags1在模拟前被`dynamicSystemTransform`拒绝。沿ParticleRuntime的当帧world变换消费扩域，不能改作者flags或只延长播放。 |
| REFRACT normal空槽 · 3566323704/552/141 | material显式`[particle/drop,null]`被要求非空normal的planner拒绝，尚未进入缺文件lookup；缺省normal语义待资格，不造纹理补洞。 |
| REFRACT cull · 3042623710/330 | RefractionPlan与RenderStateCompiler两层要求noCull，而MetalPipeline已有back-cull执行。沿原材质/几何编译收敛重复限制，以真实绕序、source capture/UV及反射像素验证normal cull；不另建REFRACT特例名单。 |
| RopeTrail参数 · 3337494481、3527426897 | 前者10个root先被flags1拒绝，负subdivision=-16为后续未资格形状；后者637/1323缺length被拒。分别核flags与隐式length语义，不取绝对值或猜默认。 |
| Rope A2C · 3807668787/958 | RenderStateCompiler将A2C绑定screenSprite的spriteProfile而拒Rope；现coverage vertex复用已有trail joins的particleVertex。把材质coverage与几何/相机资格分开，沿真实PSO/attachment需求及轨迹像素验证，不再按renderer名授许可。 |
| 周期发射上限 · 3564173599/1987、3749463715/405/412 | `maxtoemitperperiod=32`被nil gate拒绝，22秒长窗无对应出生/draw。Plan无cap、State无逐周期计数，活跃时长先合并多窗；instance.count是否缩放上限、出生消费点及fraction/触顶换窗语义尚未证。先做定窗/count2/非整fraction/短命容量1的区分实验，再沿原emitter与值快照补调度，不能仅删guard或末端min32；explicit不随自然发射扩大资格。 |
| 粒子算子实际unsupported | 3749463715/3564173599的distance-between-CP、3742497499的distance-to-CP、3527426897的map-sequence、3773747576的sphere collision、3780119725的bounds collision均有dispatcher事实（6样本10组件）。各原operator/initializer owner独立补语义；collision坐标与outside-born先取可区分输入。 |
| 粒子出生拒绝 · 3009275235/255、3248220186/2157、3746066933/85、3799613625/452 | 有真实`birth-construction-rejected`，当前首事实未细分最终失败字段，原因未知；先核出生构造的真实失败，不猜finite或作者错误。 |
| 粒子零接纳 · 2866723317 | 正rate/capacity下只有zero-admitted-count、未见所选帧draw；没有已证delay，需当前count/capacity/consumer定位，不能无依据扩大等待。 |
| 停止ledger · 3780119725 | 初次selected frame186成功，停止附近frame245有31个`lifecycle-cancellation-ledger-invariant-rejected`；22秒和10秒定向运行未复现。沿原submission/cancellation owner定位，保原失败，不因PNG正常宽泛忽略invariant。 |

## 内容与观测资格

| 定位 | 当前事实与下一步 |
|---|---|
| 必需binding · 3556263543 | 五个文字psyhue e0在真实采样slot2缺authored/default binding而持续旁路，e1与终端健康。缺项已证，隐式phase默认语义仍未知；不是census注释里的slot3。不得随意填纹理，也不能把copy的GPU完成算原effect执行。 |
| 隐藏分支shader | 3607684497/59e0的`v_TexCoordKernel`明确varying type/array拒绝；2887099508/257e0明确g_Point1 script attachment未资格；2932157836/299e1 node1/slot0、3745828537/1087e0 node0/slot1缺binding资格，2857410102/91e3仅有聚合purpose原因。均保never-visible边界；3042492564另有aa_gaussian/node3 stage-link失败，不能与blur slot0混因。 |
| 作者脚本与VM边界 | 初次32样本、含长窗33样本有实际script诊断；初次TypeError涉及21样本45个target，不能按异常类批量归作者或引擎。2890473419四个origin脚本仅声明shadowLayer即写visible、2982559622把Vec3返回给alpha为已证输入问题；3504669359实际触及prepared Puppet metadata unavailable。其余按`task/full-script-failure-recon.json`逐target核上下文/producer/API/回调顺序。 |
| 片头后的mutation · 3599986633/702.visibility | 长窗约Ready+7秒开始，5项layer mutation整批报`invalid authored layer destroy`并保previous-current，16秒窗重复557次。主体可见不证明callback成功；沿原SceneScript mutation/destroy边界核作者调用、退休对象及事务范围，不猜作者错或无差别吞错。 |
| 缺输入 · 3736952187、3763323436 | project.json不存在，未启动App；补合法输入后再跑，不作引擎失败。 |
| named demand · 2069136288、3395777145、3829467967 | 未达静态planned的269/395/946无当前active consumer；需property分支输入，不能要求默认帧执行所有潜在capture。 |
| activation读口 · 3639999624/84e1 | 作者visible=false，实际`activation-passthrough:inactive-dependency-preproof-mismatch`有GPU完成及后续e2消费，reader allowlist却判malformed/missing。对齐原producer/reader分类并保inactive资格，不能改渲染消报告。 |
| 来源阶段读口 | 17样本的19个source-not-ready subject均在Ready前，14样本后有同layer成功；2982559622/3800572533另有资源前置失败后同subject成功。只证layer后续成功，不证同slot恢复；2804817823/3186328539/3292370168无相同恢复，318的1045在frame1变hidden，不能要求必draw。 |
| 纹理关联与最终贡献 | 全部声明有索引，但ordinary/geometry/particle部分实际draw未携带asset provenance，graph/provider引用也有未闭关联。不得解析Swift描述字符串猜identity；沿已存在Candidate/Resource carrier补最小typed映射。单帧bind/GPU/tail不证明全部实例或最终可见像素，动态输入、材质与render-target的未观测阶段仍保unknown。 |
| 条件/周期分支 | 3042492564需click开关/父组，3768303048需day/night与pointer输入；延长秒数不能替代。3764725758的后续inactive事实、3830665420的10个鸟实例都不能证第二轮，首事实去重没有保完整周期回执；按实际模拟时刻/事件资格，不由墙钟授通过。 |

## 需定向扩域的能力入口

下列是尚无充分当前输入资格的边界，不是默认短窗已证缺图；具体合同仍由能力文档拥有。

| 定位 | 下一步 |
|---|---|
| composition · 2731896598 | childless透视与三维angles组合需真实几何/Camera/回绘资格，不以false-only代作者输入。 |
| source material · 3616476797/113、3679907516/71/74/83、3141464346 | 逐pass核source-only state/lookup/活动purpose；314重点232/277/321/386/416/420/481/719，不从VERSION2或translucent推通用接口。 |
| static model / resolved render state | 任意shader、多pass与更广blend/depth/cull须原binding compiler和fullscreen/output用途资格；保深度、淡出与PMA。 |
| Puppet · 3577990983、3822822401、3779107475 | auxiliary/reference、非中性通道、dense state1及多contributor姿态按真实reference/attachment坐标基资格，Reader识别不等于evaluator执行。 |
| point volume · 3047405322、3437487219、3477054430 | 需实际volume consumer；现有spot plan和point表面光照不能代验。 |
| Script动态特殊资源与typed callback | 特殊Puppet/composition创建字段、3028048463的531.alpha空数组/506.origin、3603711180跨callback Sound分别核prepared catalog及实际producer，不造空实例或无差别容错。 |
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

| 定位 | 下一步 |
|---|---|
| 属性面板 | 总打开/编辑延迟、长Combo完整显示、系统键盘路径与更多locale需实际可达控件。保原始key/value/条件，翻译只改展示；完整段落、只读说明和reset入口不能因优化丢失。 |
| effect 显隐 / history | 关闭后保history再重新启用的首帧与实际输入待核；沿原activation/previous-current，不增另一history owner。 |
| text size | VM catalog size与排版logical extent是不同事实；setter后可见时机与padding/装饰需真实行为，不另建排版owner。 |
| 预处理成员 · 2819633264 | 未知成员按0的当前实现与横/竖分辨率、宏成员/空白等价行为需区分输入。 |
| console.warn · 3605722997 | 先确认实际 callee/堆栈与可达调用，再判断API缺口。 |
| 3028048463/531.alpha、3280903509/225.alpha | 空数组与Vec3返回scalar分别核作者配置、时序与字段归属；不静默强转。 |
| presented / performance 记录 | 实际GPU完成与系统呈现分开；沿present callback和stream身份资格普通窗口/多Surface，终端PNG不代呈现率。 |
| capture · 3766415113 | 普通capture需实际窗口frame/时机资格；本轮Metal终端PNG不覆盖普通截图入口。 |
| 自有9000000015 | 90/91/92健康peer须有真实texture source及可区分ROI，先资格夹具，不能借主文字/clone输出代peer。 |

属性接口归[输入与属性](../capabilities/runtime-input-property-coverage.md)，工具按当前实现与输入资格复现。更新队列时只删已解决的具体子问题；没有当前复现则标待核，不复述旧实验流水或维持旧 verdict。
