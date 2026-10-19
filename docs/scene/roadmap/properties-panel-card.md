<!-- document-role: active-plan -->

# Scene 壁纸属性面板工作卡

本卡与[性能卡](performance-convergence-card.md)改善打开、滚动和编辑响应，追合法定义显示及热更新；复用原typed链，减少整场景重建。

**排查顺序。** 本卡拥有属性专项选序，服从[兼容路线](scene-compatibility-roadmap.md)的合成/播放、性能、属性热更新、其他总顺序；[顶层设计](engine-refactor-program.md)只规定边界。先筛选明确用户收益，沿[分级验证与复用](../../development/repository-workflow.md#并行与验证)交付，局部修订不重启全部验收。

1. 用真实属性较多的壁纸复现打开/滚动/编辑卡顿，区分主线程解析、控件/布局重复创建、同步I/O、事件风暴与播放链争用；保样本、App与操作身份。
2. 追作者property定义→导入/归一化→面板模型→可见条件/本地化→控件→保存/事件→engine update，逐项记录在哪个责任首次丢失；未知类型须有明确状态，不能静默吞掉。
3. 按现有consumer能力分类更新影响：普通scalar/color/Bool/文字，资源替换，combo/拓扑或几何变化。只更新必要value/resource/variant/graph，保持跨surface事务及clock；需要结构重建的真实情况保留。
4. 核所有当前已出现类型的默认值、范围、选项、条件显隐、路径/媒体选择和作者标签；区别中文资源缺失、翻译映射、合法定义被过滤与实际功能缺口。

**首轮最小交付。** 定位并修复一个可复现的主线程热点或可避免的整场景重建，再核同类属性和独立壁纸。优先复用现property store、prepared model、typed frame/resource update及已有control，不增加另一套属性解析、缓存、通知或renderer。

<a id="detail-display-invalidation"></a>

**详情失效现役合同。** 原DetailSheet仅在activeRecordID匹配的ready Scene、raw sourceVideoURL/exportedVideoURL均nil时比较内存展示输入；Web/Video/非active/非ready/不明确fallback保原重建。比较resolved item/raw latest record及下载/依赖任务、进度presence/phase、刷新/错误、预览token和账号订阅，不调用playable/videoURL等I/O getter。只过滤Service普通通知，保每次属性保存/事件；WallpaperManager、launch、auth、subscriptions及显式configure/inspection/诊断保强制刷新，原coalescer累计force、执行前清位。只在真实rebuild后记rendered状态，保最终值与重入；持久preview唯一height约束重挂可重激活。不得读/哈希媒体、准备Scene或另建事件/store/cache。详见[实现与证据](../history/property-detail-invalidation-convergence-2026-10-15.md)。

**当前范围。** 已完成切片从待办退出：条件/准备复用、原生列表、回调局部恢复与[永久删除后的事件退订](../history/property-callback-recovery-2026-10-14.md#retired-property-callback-consumers)、属性展示本地化、文字/颜色/brightness/背景色、资源选择/reset、FOV、JPEG方向/尺寸、视频入口、Sound mixed/named输入等的实际边界归[输入覆盖](../capabilities/runtime-input-property-coverage.md)、[SceneScript覆盖](../capabilities/scenescript-api-coverage.md)及其证据链接。不能从一次接线推导整个面板、全部离散选项或完整视觉已通过，也不重复这些批次的收尾。

**整数元数据安全。** `order/index/precision`沿唯一定义parser向零截断并安全转换，超出Int范围走原字段fallback，不丢整份定义或影响健康邻项。自有越界JSON在旧parser触发SIGTRAP，修后边界/改名/相邻合法输入门3/3通过，签名Debug构建通过且输入无漂移；未证明真实包曾崩溃，也不计性能收益。最小证据：`.artifacts/tmp/property-integer-metadata-20261016/implementation-freeze.json`及同目录`debug-build.json`。

**开放项与选择。** 本卡按全局第三档处理属性调节热更新；影响合成/播放的输入故障回[断点队列](scene-open-breakpoint-queue.md)，成本归[性能卡](performance-convergence-card.md)。只对真实可达且尚无正确consumer/更新职责的项实施，不因未验golden重复扩已支持profile。

| 余项 | 已知边界与最小下一步 |
|---|---|
| 定义/条件/type | 未知或缺类型已只读显示，不等于支持运行类型。按实际缺失定义、条件controller与typed consumer核可达性，再复用现解析/控件/store；无consumer且只有声明的项不伪造运行能力。 |
| 动画层余下输入 | direct model条件对象已沿成功Bool Program准备8请求；旧Service筛选丢动作Combo已修，正常App原生“视差”1…8出现，用户确认动作切换有效。Root实际选2保存/关闭重开仍2、reset回1并删除override；旧内部1→2→1与当前正常面板证据分列。音频rate脚本仍须沿script→typed control→原PlaybackRuntime续接；image对象条件、App重启持久化、全部8模式与多surface实际画面尚未验。见[条件合同与有界后验](../capabilities/direct-model-skeletal-animation.md#conditional-animation-properties)。 |
| 原生编辑闭环 | effectful图片Color的完整原生调色板、更多Combo/字体/离散选项及部分失败后的reset仍缺对应验收；原生clock颜色或CLI热改不替代这些consumer。先锁一项实际画面/存储差异，保关闭重开/reset。 |
| 本地化与访问 | 作者查表优先和有限标准词回退已存在；其他token/locale与语言切换、完整系统键盘chrome及长Combo显示尚未系统复核。只按真实显示反例补共享展示层，不猜英文语义或把未知token删掉。 |
| 资源/组合更新 | 已验证单资源换图、全reset和有界本地视频；更多slot/purpose/alpha/format、deferred组合及多surface仍未覆盖。先证明原typed resource/variant链首错，保坏资源、取消、迟到回执及旧画面。 |
| 交互成本 | 原生列表操作/暖准备与部分编辑窗CPU有收益，但整个打开/编辑总延迟、系统键盘环和复杂面板长稳未闭。未播放时首次仍需完整 source/模型材质分析；已复现 Debug 冷分析忙而主线程仍响应，暖准备快不代表首次成本已解决；保留[MDL STOP](../history/native-cpu-allocation-screen-2026-10-15.md#mdl-validation-followup-20261019)，不跳校验或重开旧缓存方案。按当前回归或主线程栈选择热点；不重复旧列表/准备优化或无差别重建整个面板。 |

[详情失效收敛](../history/property-detail-invalidation-convergence-2026-10-15.md)与[迟到回执](../history/property-callback-recovery-2026-10-14.md#delayed-launched-intent)的过滤/epoch合同保持；SourceMaterials→RuntimeCatalog旧职责边由[依赖边界](../architecture/scene-dependency-boundaries.md)跟踪，不为属性项扩大baseline。文字maxwidth脚本的旧293资格缺文字可达正控，仍STOP/unknown；不要据静态接线缺口强开visible或另造文字owner。

<a id="authored-property-presentation"></a>

**作者展示维护。** 属性身份、原始值/选项及条件表达式保持原样，翻译只作用于展示。Scene 标题/说明保留完整段落，不能借 Web 摘要前两段裁掉作者中文；作者自己合写的双语原文保留，不猜测、拆译或静默删除其中一种语言。标准 `ui_*` 词由自有有限词表补齐，作者查表优先。声明文字但省略类型的元数据按只读说明展示；未知显式类型仍明确只读，不凭控件出现宣称消费能力。现有可调属性可达性和隐藏条件不扩域。Scene/Web 共用原生行布局、可滚动的首行恢复默认和隐藏滚动条的展示组件；首行恢复默认按完整受支持控件集决定是否显示，即使条件隐藏了全部控件也保留恢复入口；无可调定义时不显示，标题区不占按钮高度，并保留作品名称下方的固定分隔线；编辑器填满剩余窗口高度；作者说明中的 `<hr>` 按前后顺序以原生横线展示，纯横线说明也保留，各自保留属性解析、条件、保存和事件 owner；Web 下拉选项翻译只作用于菜单文字，不改条件使用的原 label/value。面板以长标题完整换行、Bool/颜色右对齐、Combo 左标题右选择框（不超过半行且最大 180pt）、Slider/文本输入/资源上下排列，统一测量与实际宽度，保虚拟化、编辑会话、重置及键盘路径。验收覆盖参数多的真实 metadata 展示与正反 fixture；展示测试不代替真实引擎属性生效。

**验收。** 同条件记录打开/滚动/编辑响应与engine重建/资源更新事实，验证实际画面立即/下一帧变化、连续多次编辑、关闭重开及保存恢复。资源替换还须检查取消、缺失/坏资源与旧画面保留；条件显示、重置、依赖属性、脚本回调及多个surface保持一致。不能只断言未重建：值和事件必须真实到达consumer。

热更新与缺口按通用property语义修复，变量/属性键/资源改名和相邻不应命中反例加入验证；不按样本ID或固定作者键选择行为。测量面板响应时保播放与诊断条件一致，不以隐藏控件、丢定义、关闭特效或合并应独立的事件换顺滑。

**职责与退出。** AppKit控件/布局、导入模型、property store与Scene engine各修最早失败owner；跨职责重要策略先修对应设计。每批独审、提交并汇报画面/交互收益、受益类型、当前专项进度与下一项。已完成记录归history，未执行定义/type问题留本卡或原队列，不复制两套状态；用户结束专项或已证类型与交互矩阵闭合后退役。
