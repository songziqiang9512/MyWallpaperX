# Scene 当前开放问题

<!-- document-role: active-plan -->

本页只保未闭问题、可续跑的输入定位和下一步。优先顺序为画面合成/正常播放、当前有证性能成本、属性接线、合同与工具资格。架构归[当前主链](../architecture/runtime-architecture.md)，领域边界归[能力入口](../capabilities/README.md)，性能使用[测量方法](performance-convergence-card.md)。

样本 ID、layer 和参数用于复现，不选择产品算法。“待复核”表示尚未有当前固定输入的充分证据，不认定当前产品故障；隐藏、延迟、空媒体、未触发或缺参考不能直接列为缺图。未实现能力与可见差异分开，先定位真实 consumer，再修原 owner。

<a id="implementation-gaps"></a>
## 代码边界与通用缺口

| 定位 | 当前问题 / 下一步 |
|---|---|
| composition 透视 · 2731896598 | childless passthrough 的 perspective 与三维 angles 组合待资格。沿 `SceneUtilityLayerSourceRoute`/Camera/回绘核实际几何，不以 false-only 代替作者输入。 |
| named 多槽 · 3086016320 / layer430 | 封面转场的 execution-stage conservation 与 selected/potential 依赖向量待复核；父426默认 alpha=0，先取得可见输入，沿原 dependency ownership。 |
| forward background · 2972071249 / 313→234 | 后置隐藏 composition 的 copy-background 与作者前缀依赖待资格；不能用全局 prepass 丢弃原顺序。 |
| source material · 3616476797/113、3679907516/71/74/83、3141464346 | source-only render state、lookup 与活动 purpose 待逐 pass 定位；314重点232/277/321/386/416/420/481/719。沿 Schema/RuntimeCatalog，不把 translucent/VERSION2 当通用接口证明。 |
| 活动 sampler / 前端 · 357/3632522893、2804817823、3800572533 | `texture-purpose-unproven`、secondary composite 和 texture binding 须取得精确 slot、来源与活动接口。357/233的Combined、363的765→785/Blur772及2857410102/91预设2 noise override分开核来源；保原局部 passthrough，不按效果名补算法。 |
| resolved effect render state | Template admission 当前受 `supportsResolvedMaterialFullscreenOverwrite`约束；更广 blend/depth/cull 需精确输出用途与像素输入，不能泛化到普通图片/模型。 |
| static model material | 当前 binding compiler 仍要求 pass0 和可证明的固定接口；任意 shader、多 pass 及更广逐 pass state 未形成通用执行。沿 model material/geometry owner 扩，保深度、淡出与 PMA。 |
| Puppet animation · 3577990983 /3822822401 /3779107475 | auxiliary/reference、非中性通道、更广 dense state1 与多 contributor 姿态待资格；Reader 识别不等于 evaluator 支持。保真实 reference/attachment 坐标基。 |
| point volumetric · 3047405322 /3437487219 /3477054430 | 需实际volume consumer和输入/输出资格；当前spot plan不能代point volume，ordinary point表面光照也不能代验。 |
| 动态特殊资源 | `SceneQuickJSLayerSceneHost`拒绝部分 Puppet animations/effects、composition parent/children/dependencies 等创建字段；默认 material recipe 也有有界接口。沿 prepared catalog 扩真实消费者，不造空实例或复活旧容量门。 |
| 粒子算子 / 空间 | CP distance、map-sequence、Mirror、nested/event、非均匀 child 变换等按[算子边界](../capabilities/particle-component-coverage.md#operators)逐项补；3742497499区分 distance-to-CP 与 distance-between-CP，359777类 affine/CP force 先核实际空间。 |
| 粒子参数资格 | HSV 缺省（3585542943/253、257；3761159935/453、457）、3337494481 world/负 subdivision、Vortex flags2仍需对应出生/轨迹输入；不猜 clamp、取绝对值或颜色单位。 |
| collisionbounds | 未实现 / blocked：scaled、outside-born及碰撞边界坐标合同未确定，不能用 emitter 出生域、普通 affine 反弹或样本阈值代替；先取得可区分输入，再决定模拟消费。 |
| REFRACT normal hole · 3566323704/552、141 | 显式空槽的 authored 缺省与真实读取待资格；不制造 normal 或扩大其他材质资格。 |
| particle direct color | `ScenePropertyBindingCompiler+TargetMapping`的 absolute `.color`仍返回 nil；先确定合法定义和单位，再接同一 instruction/出生 consumer。normalizedColor 是不同目标。 |
| 隐藏 / 离屏视频 | backend dormant策略仍待资格；显示隐藏、资源仍被named采样与实际source停止分开，不能以hidden统一停decoder。 |
| typed event / callback 时序 | 3028048463的531.alpha空数组、506.origin；3603711180的跨 callback Sound 查询；event-only Vec/numeric String 的控制归属分别待核。保作者当前值失败策略，不无差别容错。 |
| 版本 / 显示输出扩域 | 物理HDR/EDR、lighting/receiver及未知模型/粒子profile待资格；文字backgroundbrightness、HDR8bit裁剪待核：TextDescriptor/TextureLoader。 |

上述范围的实现依据分别为[Script](../capabilities/scenescript-api-coverage.md)、[effect/composition](../capabilities/effect-execution-coverage.md)、[graph/shader](../capabilities/render-graph-shader-coverage.md)、[模型/Puppet](../capabilities/advanced-object-coverage.md)和[粒子](../capabilities/particle-component-coverage.md)。

<a id="user-feedback"></a>
## 用户可见反馈：待当前输入复核

以下保留输入和症状，不沿用旧运行胜负或推定根因。复核时固定属性、声源、pointer、时间/相位、viewport 与 App；先输出，再定位首个不同 stage。

### 优先复核

| 输入 | 精确待核位置 |
|---|---|
| 2982559622 | 103.alpha为作者Vec3错挂；待核effect视频→utility首帧、effect.visible组合准入。 |
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
| 3768229922 /3770444459 | 完整默认开场/主体过渡；溅水滴黑色需实际source/合成ROI。 |
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
| 3471294034 · 未优化 Debug | 当前候选8秒短窗的呈现间隔中位数为125ms；需同输入、同优化配置基线与归因，functional PASS 不代60 FPS资格。 |
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
| presented / performance 记录 | `presentation stream count does not match surfaces`与实际GPU完成分开；沿benchmark、present callback及stream身份定位，不能为消报告改渲染或伪报PASS。 |
| capture · 3766415113 | 普通capture的1×1输入需当前窗口frame/时机；诊断Metal截图不能冒充普通capture修复。 |
| 诊断分母 / 显隐 · 3280903509 /3303319749 /3347416586 /3350026230 /3357689320 | instanced solid、hidden/dormant/retired与真实active outcome分开；不把load-incomplete标签直接写成缺图。 |
| 资源/graph观测 · 3039882306 /3292370168 /3186328539 /3763323436 | 先核active consumer和实际完成；318的1045未ready/hidden不直接判缺图，376缺project先补输入。 |
| 自有9000000015 | 90/91/92健康peer须有真实texture source及可区分ROI，先资格夹具，不能借主文字/clone输出代peer。 |

属性接口归[输入与属性](../capabilities/runtime-input-property-coverage.md)，工具按当前实现与输入资格复现。更新队列时只删已解决的具体子问题；没有当前复现则标待核，不复述旧实验流水或维持旧 verdict。
