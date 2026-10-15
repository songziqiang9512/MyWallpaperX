<!-- document-role: active-plan -->

# Scene 壁纸属性面板工作卡

本卡与[性能卡](performance-convergence-card.md)改善打开、滚动和编辑响应，追合法定义显示及热更新；复用原typed链，减少整场景重建。

**排查顺序。** 本卡拥有属性专项选序；[顶层设计](engine-refactor-program.md)只规定边界。先筛选明确用户收益，沿[分级验证与复用](../../development/repository-workflow.md#并行与验证)交付，局部修订不重启全部验收。

1. 用真实属性较多的壁纸复现打开/滚动/编辑卡顿，区分主线程解析、控件/布局重复创建、同步I/O、事件风暴与播放链争用；保样本、App与操作身份。
2. 追作者property定义→导入/归一化→面板模型→可见条件/本地化→控件→保存/事件→engine update，逐项记录在哪个责任首次丢失；未知类型须有明确状态，不能静默吞掉。
3. 按现有consumer能力分类更新影响：普通scalar/color/Bool/文字，资源替换，combo/拓扑或几何变化。只更新必要value/resource/variant/graph，保持跨surface事务及clock；需要结构重建的真实情况保留。
4. 核所有当前已出现类型的默认值、范围、选项、条件显隐、路径/媒体选择和作者标签；区别中文资源缺失、翻译映射、合法定义被过滤与实际功能缺口。

**首轮最小交付。** 定位并修复一个可复现的主线程热点或可避免的整场景重建，再核同类属性和独立壁纸。优先复用现property store、prepared model、typed frame/resource update及已有control，不增加另一套属性解析、缓存、通知或renderer。

<a id="detail-display-invalidation"></a>

**详情失效现役合同。** 原DetailSheet仅在activeRecordID匹配的ready Scene、raw sourceVideoURL/exportedVideoURL均nil时比较内存展示输入；Web/Video/非active/非ready/不明确fallback保原重建。比较resolved item/raw latest record及下载/依赖任务、进度presence/phase、刷新/错误、预览token和账号订阅，不调用playable/videoURL等I/O getter。只过滤Service普通通知，保每次属性保存/事件；WallpaperManager、launch、auth、subscriptions及显式configure/inspection/诊断保强制刷新，原coalescer累计force、执行前清位。只在真实rebuild后记rendered状态，保最终值与重入；持久preview唯一height约束重挂可重激活。不得读/哈希媒体、准备Scene或另建事件/store/cache。详见[实现与证据](../history/property-detail-invalidation-convergence-2026-10-15.md)。

**当前进度与下一轮。** [条件依赖](../history/property-condition-reachability-2026-10-13.md)、[窗口准备复用](../history/property-preparation-convergence-2026-10-13.md)与[原生列表](../history/native-property-list-convergence-2026-10-14.md)已证格式入口、暖准备/面板操作CPU及原生滚动首尾，旧SwiftUI lazy AX职责退出。[回调局部恢复](../history/property-callback-recovery-2026-10-14.md)闭合云层整景重建触发；[普通同值重发](../history/property-callback-recovery-2026-10-14.md#ordinary-value-resend)已在实际Host避免结构键误拒绝，真实改值与资源重试仍走原准入；544作者颜色异常与原严格FAIL保留。[换图反馈与原生全reset](../history/property-texture-feedback-2026-10-14.md#native-full-reset)已证局部反馈、坏图持久值不变、背景ROI及单资源全reset同session；部分失败/更多资源仍待验，旧CLI取证边界保留，不计性能收益。未知/缺类型定义已沿原列表只读显示，含真实HDR作者提示；条件控制器全隐藏时保reset出口，不等于支持其运行类型。[未绑定普通Bool](../history/property-condition-reachability-2026-10-13.md#unbound-bool-live-update)已在原样314的真实详细行、保存重开/reset中保持单session；独立213原样渲染未见本批相关缺损，仅放行有明确类型事实且无运行consumer的Bool，不计性能收益。[迟到启动回执](../history/property-callback-recovery-2026-10-14.md#delayed-launched-intent)的普通/pending/资源fallback意图已沿原Client同步，受控IPC门通过；[effectful图片颜色](../history/effectful-image-property-color-2026-10-14.md)已证typed改色及条件行/alpha重开，该效果图片consumer的原生调色板完整编辑仍待验；[普通图片brightness](../history/effectful-image-property-color-2026-10-14.md#image-brightness)已证typed热变亮和原生行保存/重开/reset保持单session，饱和仅与旧静态表现吻合，不计性能或parity；独立213原样渲染未见本批相关异常。[回调独占普通属性](../history/property-callback-recovery-2026-10-14.md#prepared-callback-panel)已从active prepared事实接入原context，真实媒体Combo编辑、重开/reset保持单session，受控暂停媒体图标随模式隐藏，原效果FAIL仍开放。[展示本地化](../history/property-callback-recovery-2026-10-14.md#property-display-localization)已接共享语言/作者查表与15项原生词汇，真实293标题/条件行保存重开/reset、独立324面板及实图通过；Web保旧作者表条件语义，未知token保原文。清点尚有183个未审token，未达全本地化；[324字体](../history/property-callback-recovery-2026-10-14.md#callback-font-native)已证切换/重开/reset同session；语言切换、其他Combo/字体及完整粒子未验，不计性能。[嵌套String绑定](../history/property-callback-recovery-2026-10-14.md#nested-script-input-binding)已沿共享codec修terminal fallback和重复inner发现，真实304格式两次改值/重开/reset实际文字变化且不重建；未量化整进程成本。[Color脚本输入](../history/property-callback-recovery-2026-10-14.md#color-script-input-live)已修typed准入缺口，真实原生调色板两次改色、重开/reset均改变实际时钟且同session；原字符串/Vec2目标与非法/缺失consumer保原合同，未计性能百分比。[Scene背景色](../history/scene-clear-color-property-2026-10-15.md)已恢复合法Color行并闭合原生两次改实际背景/重开/reset同session；clear-off/脚本/动画及多屏未扩，未计性能百分比。[206辅助图片](../history/effect-texture-visible-screen-2026-10-15.md)已证既有链的PNG实际替图/逐key reset；冷两次选图与暖reset分开记各轮同session，exact slot/purpose/代次、准备次数与alpha未证，不再按旧表补第二链。a55ed7dd遗留SourceMaterials→RuntimeCatalog职责边仍待原owner收敛，不扩baseline。[详情失效收敛](../history/property-detail-invalidation-convergence-2026-10-15.md)已闭普通通知重复重建，保必要刷新及唯一高度约束；原生编辑/Stop及成本见记录。引擎准备性能进度与后继归[性能卡](performance-convergence-card.md#sampler-seed-preparation)，列表条件/准备复用及旧NO-GO保原结论；本卡续追未审展示语义/媒体入口，不另设准备性能选序。完整系统键盘访问chrome环、多surface及整面板延迟仍待验，不按局部结果计专项完成。

**后继。** [FOV热更新](../history/camera-layer-fov-live-2026-10-15.md)及[JPEG方向/尺寸](../history/jpeg-display-layout-2026-10-15.md)已闭所列真实编辑、重开/reset及独立画面边界，只计能力。JPEG复用共同decoder，不扩格式。[prepared文字实例](../capabilities/scenescript-api-coverage.md#prepared-text-clones)已接user/value输入与typed消费，后继随[兼容路线](scene-compatibility-roadmap.md)；[U41本地视频](../history/user-property-video-2026-10-16.md)已闭有界选择/重放、format metadata反例及最终App可见验收；后继[U40三轮资格](../history/repeated-puppet-drag-qualification-2026-10-16.md)已fresh复现释放异常后的失效，候选host依赖动态归因未证；官方载体2/2失败后停止、未发出impulse，参数/响应unknown，尚无交互修复，条件/type及编辑重建余项保留。性能只按[性能卡](performance-convergence-card.md)有证触发。

**验收。** 同条件记录打开/滚动/编辑响应与engine重建/资源更新事实，验证实际画面立即/下一帧变化、连续多次编辑、关闭重开及保存恢复。资源替换还须检查取消、缺失/坏资源与旧画面保留；条件显示、重置、依赖属性、脚本回调及多个surface保持一致。不能只断言未重建：值和事件必须真实到达consumer。

热更新与缺口按通用property语义修复，变量/属性键/资源改名和相邻不应命中反例加入验证；不按样本ID或固定作者键选择行为。测量面板响应时保播放与诊断条件一致，不以隐藏控件、丢定义、关闭特效或合并应独立的事件换顺滑。

**职责与退出。** AppKit控件/布局、导入模型、property store与Scene engine各修最早失败owner；跨职责重要策略先修对应设计。每批独审、提交并汇报画面/交互收益、受益类型、当前专项进度与下一项。已完成记录归history，未执行定义/type问题留本卡或原队列，不复制两套状态；用户结束专项或已证类型与交互矩阵闭合后退役。
