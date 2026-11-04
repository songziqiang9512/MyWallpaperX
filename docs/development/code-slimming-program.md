# 代码精简专项

<!-- document-role: active-plan -->

复核日期：2026-11-05。负责人：repository-maintainer。专项起点：`af44ce421`；下文前批结算只对应各自基线。

开批速览（每批动手前先读这里，再核 Git 状态；按需查对应 owner 和下文，不顺读全文）：

- 最新缓存交付批：有效图先交付，可选PNG/JPEG仍在原worker有界尾写；原bytes/hook先交、失效与同target回访保留。调度/租约、实际冷暖像素与签名Debug已验，详见下文。首图后立刻换不兼容尺寸可能再准备源；不称总工作或FPS降低。
- 前批Steam封面：单次临时State成功后退出cache外原图持有；96图、真实State/Artwork及签名Debug已验，不重做。派生缓存保留，直接改raw暖返及强制PNG filter已由当前批反例退出。
- 前批长历史：下载任务改原生Table复用可见控件，原图片准备/回访保图及进度迁到唯一轻量呈现状态；100/1000行的原生行为、释放和签名Debug已验，下文结算。前批48pt/backing与Steam暖借图保持，不重做；编码成本已由当前批承接，不等于整App RSS/FPS结论。
- 前批封面寿命：Artwork方图生成后弱持去重源图，cache退出后不再额外长期保原图；显示方图、颜色和租约已验。Steam临时State由当前批收尾，真实尺寸汇总另评，不重做这条弱源回收链。
- 前批预取寿命：Steam非显示预取成功即释放临时State，显示State、fallback和重试保留；不盲加每viewport补热。静态动画终态缓存候选因截断GIF反例已拒，不重开；源码职责归[统一设计](thumbnail-delivery-design.md#decision)。
- 前批尺寸资源已完成：Steam混合/Picker预取与显示同档；Pixabay下载卡/详情接真实尺寸、同源升级保图。真实AV/ImageIO、最近门及旧版对照已做，完整拖拽旧新同阶段超时仍未结；不重复尺寸批或盲扩预热预算。
- 前批资源/交互已完成：同值选择退出整页Set/状态发布及可见卡片重复投影；详情bar可打断开关，标题右移8pt，Pixabay排序→筛选及标题短淡化。不重做R131、共享Inspector动画及个人设置导入R55（`ad1f3142d`）。持续解码高压、Steam/混合列表完整体验及关闭态中心偶发失效仍未结；没有新复现不重修已结事项。
- 近期已完成：R105 Pixabay搜索入口收窄；R104日期回退按需准备；R103网格顺序比较退出数组；R101/R102媒体需求与速率字符串复用。R89–R99结案见[历史记录](../history/cross-topic/code-slimming-r89-r99-closeouts-2026-11-03.md#completed-r89-r99)，验证范围以该记录为限；已完成项不作为新候选。
- 保留/拒绝：R55 一次 Save 取消超时尚未归因；R56 绕过 TIFF 的候选因像素/尺寸差异已拒绝。较早 R23/R38/R43 的保护边界仍有效。
- R62已交付：[本地资源先呈现与缩略图回访](local-library-loading-design.md#overview)。先解决启动短暂不可用和本地网格滚回黑卡，覆盖视频、图片及自建列表；已完成实现、最近门、Steam消费者及签名Debug；保留三项原生限制，真实用户库体感待人工验收。R61冷态导航已完成验证，见[对应记录](../history/cross-topic/code-slimming-r61-r88-closeouts-2026-11-02.md#completed-r61-r88)；不重复本专项。

- AppKit、Web、Steam 精简与原生 UI1–UI9 的历史验收见[历史记录](../history/cross-topic/code-slimming-b1-b12-ui1-ui9-2026-10-23.md)。本页保留当前范围、未解决项和 UI10 已批准设计；UI10 试版与验收见[独立历史](../history/cross-topic/code-slimming-ui10-trials-2026-10-23.md)。

后续范围（2026-11-03）：按goal持续审查、优化所有非Scene代码及对应分类文档，Scene引擎不修改；现有能力须以原行为门和反例保持，不能用删功能换精简。

当前执行方式：本轮按用户新优先级审查资源重复工作，并处理指定交互；沿真实owner以旧版对照和最近行为门验证。涉及帧率/可见卡顿仍须完整App同负载动作、Main调用栈和呈现证据；组件计数、构建、presentation属性不代替屏幕帧率或用户验收，不按局部代码气味连续产出微优化。

当前缓存交付批（2026-11-05）：原ThumbnailCache把最终图交付排在派生PNG/JPEG编码、stage/rename之后，冷图已可显示仍等待可选落盘。沿[统一设计](thumbnail-delivery-design.md#decision)，先完成原bytes/hook准入、发布display与一次回调，再由同Request/worker完成原编码/写；原槽保到尾部。LRU淘汰且tail未完时同步借原worker的publishedImage同引用，不填LRU或复制像素；clear/remove、新hook及新generation使旧tail弃交，nil仍先负缓存/retire再回调。产品唯一Cache 889→927行，净+38用于发布/持久化分阶段与原结果复用；没有新owner、队列、格式、缓存或持久状态。

同两种合成1600² JPEG和3帧GIF、256/512/800档各3次，旧新各36组×4阶段（144请求）：全部输入hash、帧数、原bytes及RGBA像素相同，编码/loader/写次数与字节量相同，两暖盘阶段零loader/编码/写。800档复杂JPEG首callback中位70.215→20.545ms、平滑JPEG15.856→3.925ms，复杂JPEG暖盘11.228→10.406ms；GIF首图仍须原帧扫描，改善有限。只证明该组件首图等待缩短，不是用户库分布、总吞吐、RSS、FPS或Photos体验。raw重建GIF约33–38ms而PNG暖返约0.7–2.7ms，因此不删派生缓存；公开PNG filter比较无稳定收益，不改编码器或按样本加分支。

首callback不再承诺可选文件已落盘：立刻换不兼容target时，tail窄窗可能沿原来源再准备，原槽仍有界；不为此新增跨target母图owner。原回访门的盘复用断言改等实际finish/rename，保零源增量、未裁像素、一次回调及小图不得覆盖母图；另明确held-tail不同target的正确早交与两次输入准备，Ready后取消不能撤已交回调。首次发布前loader/decode/raw stage取消反例保持。调度182项、租约63项、回访124项、真实AV14项、在线8组及Artwork72项已过；同最终夹具旧调度19项、旧租约2项仅新早交/持图事实红。提交前已复核全部工作区差异，修正盘回访夹具的Ready/落盘前提与过期观察入口，保留原像素、AV次数和取消断言；补齐新请求/夹具到现有门的映射。原生host初轮在启动几何未稳、进场只余4.9px才释放回填，时限断言失败；改等真实pending/稳定几何并要求明确早段，原完成时限不放宽，最终19项通过。独立host集成场景与direct-preview分文件，共用原helper，无产品改动。相关源输入稳定，签名Debug29.702s、1192 App Swift同主仓、零编译错误/警告、strict/deep通过。证据归本机`.artifacts/cache-variant-comparison-20261105`；完整App高压交互、连续尺寸升级频率及关闭态偶发吞击仍未验收。

前批Steam封面临时State已结：原单次State成功后清onChange/reset再交局部图，净+3行；96张800²暖源在128MiB LRU清后旧仍持245760000B、新为0，独立方图像素SHA不变。24真实State+48原Artwork、取色64、屏保缩略图11和签名Debug通过；真实成功视频文件回退、完整屏保宿主未测，不外推RSS。必要证据归`.artifacts/resource-cost-review-20261105`，不重开其源寿命链。

前批下载长历史（2026-11-05）：原NSStackView为全部活动/历史创建完整RowView，通用下载历史不截断，屏幕外也持控件与约束。按[任务面板设计](main-window-playlists-redesign.md#page-catalog)，以原生NSTableView/Diffable/makeView复用可见控件；原行身份、图/租约、进度和速率样本迁至唯一DownloadTaskRowPresentation，替换原View内状态。图片仍按原顺序全量准备并保留，远跳/回访不重绑；删除/关闭才撤模型，回收仅解绑视图。未新增图片缓存、下载队列或持久化owner，来源与动作不改；产品3文件净+188行用于原生复用与必要状态/控件分离，旧全量Stack及View内状态同批退出。

同一真实生产Row/Content、400×460原生NSWindow、受控pending取图的对照：100条构造+挂窗/布局约490→86ms，1000条约7153→86ms；1000条视图16016→125、约束86066→636，仍6条可见、1000次图片准备、终态进度订阅0、关闭取消1000。计时不含真实取图/整App业务，不等同RSS/FPS或Photos级体验。表格采用系统懒测行高，未为初次估算高度强算全表；原生远跳/回返与实际行几何另验。

最终100/1000压力门在首屏/远跳/回返分别125/151/137个视图、636/755/684条约束，图身份、速率、同值控件、完整批量重试、pending重排/删除/迟到与关闭旧按钮均通过；cache清后weak状态/图片全0。首轮新夹具漏MainActor、把占位符bounds当48pt对齐区、跨完整流程的autoreleasepool及测试强持旧Row，均保失败记录并以旧新同输入/逐turn drain修正，没有改产品迎合断言；420pt可交7个部分可见行，仍严格核原有限复用margin。实际行/长提示/21条来源路由、真实缓存Preview原direct90项和原生Toolbar111项通过；完整active-hover尾部及既有拖拽失败仍未销账。签名Debug29.861s、0编译错误/警告、strict/deep通过，1192 App Swift输入稳定且与主仓一致。证据归本机`.artifacts/task-history-resource-audit-20261105`。

前批48pt下载需求保持：真实window backing/fit交原Controller/provider；同值不重载，跨backing保图，重排离窗不撤租约，旧id/key/目标拒绝。SteamSource与Hydration共用精确优先/较大ready图借用，不复制小图别名；冷母版和较大暖图策略不变。ImageIO实测Steam800²/2560000B→256²/262144B；sourceFile512×341/698368B→96×64/24576B；4K AV的Pixabay520×292/616704B→96×54/20736B，仍后台0.5秒帧且暖返不取帧。这些是交付像素，不是AV内部成本/RSS。前批21路由、复用114、AV14、租约63、Toolbar111与Preview direct90及签名Debug证据归`.artifacts/download-row-thumbnail-demand-20261105`，不重跑未受影响的源/媒体全门。

缓存交付与Steam封面State已完成本轮收敛；入口准入、clear/remove撤销和有界图寿命继续保留。下一先评真实连续尺寸升级是否抵消早交收益；Artwork实际需求汇总及持续解码高压另评，不直接新增跨target聚合。指定标题缩进、Pixabay排序→筛选、可打断详情bar及标题淡化沿前批实现，不重复；完整App交互/FPS与关闭态中心偶发无响应仍需真实复现，不认领根治。

前批封面寿命（2026-11-05）：Artwork已同步绘制独立方图，Cover.sourceImage仅供同对象回执去重，却额外强持未裁原图。改弱引用，并保弱源归零后nil回执清已有方图；来源准入、构图、alpha、取色、同实例echo及最后消费者撤租约不变。不在成功时提前取消，不改Steam liveLoader，不增cache、Task或持久状态；产品3增2删净+1行。

真实96张独立800² JPEG由ImageIO解码，受控来源交原Artwork和实际128MiB DecodedThumbnailMemoryCache：旧/新就绪原图96/52张，clear后96张245,760,000B→0；96张输出方图均保留201,326,592B，撤完需求归0，96个颜色/alpha采样旧新相同。这里统计弱存活NSImage及CG bytesPerRow×height，缓存/来源准备和整App RSS/FPS不可等同。输出在本机仍有较大像素成本，实际需求汇总另评，不能盲降色深或清晰度。

原/新增封面48项新全过；同最终夹具旧仅两个原图回收检查失败。初轮直接比较源色与lockFocus成图的断言在旧新均失败，改为释放前后成图采样，并核旧新一致，保原记录，不改产品色彩链迎合夹具。原生目录工具栏/需求31项与编辑器54项通过；目录夹具漏编ThumbnailRequest，补真实依赖后重跑，本批未跑其完整拖拽。签名Debug27.282s、0编译错误/警告、strict/deep通过，1191 App Swift输入稳定且与主仓一致。证据归本机`.artifacts/artwork-resource-lifetime-20261105`；无暂存/提交/推送。

48pt下载需求及长历史控件已分批完成。封面尺寸汇总及多列表同源重复方图仍需成本与消费者证据，不顺手加第二cache。指定UI改动沿前批实现，不重复；持续大量解码和完整App交互/FPS待验。

前批预取寿命（2026-11-05）：Adapter取消闭包长期强持非显示PreviewState及其就绪图，绕过cache淘汰寿命。现先安装取消，再configure，成功onChange仅以双弱引用解除临时持有；同步暖命中、加载/失败重试、image→remote→video与原取消保留，无新API、mode、cache或调度owner。Steam完成兴趣仍best-effort；未做字节/方向预算前，不加每viewport补热查询以免近邻集大于cache时循环解码。显示State与原UI不改。

同最终真实Adapter分支、State、ImageIO/cache及96张不同像素800² JPEG对照：旧就绪/clear后均96图245760000B（234.375MiB），新就绪52图133120000B，clear后只剩显示State的一图2560000B；消费者全退都0。观察只持weak NSImage并计实际CGImage行字节，统计的是对象持有对应位图，不是RSS/系统立刻归还或FPS。原源码仅新增回收断言失败，新全过；recording Adapter验证同步/异步、nil/取消/迟到与重复viewport不补热，Picker保持原生近门。批次证据归本机`.artifacts/steam-resource-lifetime-20261105`。

静态动画终态候选已撤：ImageIO对本机截断多帧GIF可报一帧Complete，替换为增量factory也无助，不能缓存这个含糊结果而影响恢复。候选及测试按本批before逐字退回，保继承修改，输入分布/哈希与失败夹具留证；不再为此堆解析器、白名单或新负缓存。候选期间原生Steam完整card-interactions超时，撤回后不拿其余事实说整门通过，也不改输入处理。共享原生launcher的证据复制移入finally，真实无窗App超时已验证stdout/stderr保留及精确PID结束，避免再次丢唯一现场。

最终产品仅Adapter +5/-1，净+4行；测试+178/-4，用于实际96图/弱观察、同步异步退役及超时证据，不以测试量替代产品收益。最终同夹具真实复用/持有、完整Adapter与原生Picker三门通过；签名Debug28.67s、零编译错误/警告，strict/deep通过，1191份App Swift与构建输入相同。未暂存/提交；整App高压/FPS/RSS、既有拖拽和关闭态吞击仍未结。后继Artwork/任务行候选已由随后两批承接，按当前速览继续，拒绝无证的动画负缓存候选。

当前尺寸资源批（2026-11-05）：已证混合页/Picker的Steam预取固定256，而显示按256/512/800，尺寸又在缓存key内，冷入屏会准备另一档；现由Adapter复用原像素分档、同档保租约，跨档才替换。Pixabay下载Store原固定520×300，Adapter与详情遗漏实际request；现沿原缓存承接真实尺寸，复用Core的旋转尺寸读取，保0.5秒、源版本前后检查、取消与nil旧入口。卡片同源升级保图、隐藏后再显示补未完需求，退出强置entry=nil的递归重配；已有图不再排加载提示定时器。详情共用一个request和原取消句柄，退出hasMounted及本地/远端重复触发分支。没有新缓存、跨源任务聚合或数据库格式。

真实4K/小源/90°旋转视频的AV与缓存12事实通过：64px卡片结果16KiB，旧实际520×292结果约602KiB；512px结果1MiB，随后小卡/fit复用不新取帧。旧磁盘派生升级、native cap、原帧时间、后台AV及clear均过。旧实现对照只补忽略新request参数的调用适配、保原生成与缓存正文，8个目标断言失败；Adapter旧/新用相同最终夹具，旧目标档断言失败、新门全真。真实Steam ImageIO证明同档邻近→可见共用图且只进一次decoder，不外推所有冷请求为一次。

22个相关测试方法通过；完整card-interactions旧/新均在online-downloads拖拽阶段超时，新栈为NSCoreDragManager等mouseUp，未认产品根因或拖拽通过。测试输出已改为finally保留，超时也不丢唯一现场。新增详情resize夹具先误改未约束子View，后改真实Host preferredWidth并等实际cache准入，错误过程保留。独立静审接受；签名Debug31.30s、零编译错误/警告，strict/deep通过，1191份App Swift与构建输入相同。证据归本机`.artifacts/thumbnail-demand-audit-20261105`；无新增整App持续解码压力、FPS或实际内存峰值结论，未暂存/提交。

前批持图候选已由当前寿命批量化并处理，不再把234MiB当作未测估算；显示/预取仍沿同一缓存，不重复相加。下一方向是Artwork/48pt任务行的实际目标及跨消费者复用，或实际变化选择的整页扫描；先查producer→consumer和真实反馈成本。静态动画终态候选已拒，完整拖拽及整App高负载呈现仍未结。

当前资源/交互批（2026-11-04）：Presentation旧实现同值选择仍构造整页引用Set并发布，Composition、工具栏和详情随之刷新；Grid接受同值回执仍扫描所有索引并重配可见项。现先拒绝旧session，再原地复用同值选择；Grid保留准入回调、拒绝恢复和焦点，只跳过接受后完整selection未变的投影。无新增缓存、索引或常驻状态。5000项真实Presentation的100次重复选择零发布；真实原生Grid的100次准入保留而不重配已出现卡片。相同最终夹具换旧实现，两门各仅新增成本断言失败；原引用裁剪、拒绝恢复和键盘行为保持。键盘夹具补等真实条目拓扑接纳，避免在原生删除动画尚未完成时发下一步输入，不改产品租约规则。

资源审查保留：Video的Grid/Picker/详情复用同一store，provider与取消句柄有独立寿命；SIL/在线本地图片复用像素缓存。在线压缩字节与就绪像素分别服务网络和显示，预算不是预分配内存。Pixabay与Video/桌面静帧的帧选择、版本和删除权不同，本轮退出直接共文件候选；实际变化的选择仍有整页扫描。未量化播放器/实际峰值，不声称全仓无浪费。

交互以[统一设计](thumbnail-delivery-design.md#decision)为准：共享bar调用Shell原生responder，保原来源打开动作与唯一token，遮罩只放行真实可用的详情按钮，其他命中/滚动规则保持。关闭仍发原通知，保Steam浏览页的关闭请求订阅；原生Host验证通知送达、进入关闭、关闭反向重开及同token/view，独立bar原动作和Video预览/释放门保持；不等于所有来源物理连点或关闭态吞击已解决。工具栏原生门覆盖所有来源标题的8pt对齐、AX/窄窗与真实Pixabay顺序；仅标题短淡化，不追加整页截图/网格动画。10个相关测试方法及文档/代码/设计门通过；最终签名Debug24.07s，零编译错误/警告，strict/deep通过，1191份App Swift与构建输入相同。保留产物和已纠正的夹具失败日志归本机`.artifacts/resource-ui-review-20261104`。

当前共享Inspector动画修复（2026-11-04）：5000份隔离视频文件、5000张不同像素JPEG的完整App中，旧约束`animator()`依赖Main逐帧插值，进入时Main存在选中重算、单项解析和布局的49–142ms忙段。active/key全程成立的位置采样中，三次进入的模型/呈现值相同，首次大幅追赶进度，只记录到58/89/87ms移动。仅将共享Host改为一次布局目标、`allowsImplicitAnimation`交层承载后，模型各设一次，呈现有16/18/17个中间位置（133/141/136ms）；原240ms时长、曲线、约束、挂载/取消及transition generation保持，无新owner、缓存、Task或持久状态，产品净+3行。

验证：同5000项App对照及短按连续切换最终内容/状态正确；原生Host原有身份、关闭、重开、来源替换与过期回调检查保持，新回归在Main忙80ms后以新事务读取呈现值，旧仅此移动断言失败，新全过。首次探针在同一事务取两次快照无效；一次旧对照在既有QuickLook等待阶段超时，均保留原记录，不作为产品红绿证据。签名Debug构建29.90s、0编译错误/警告，strict/deep通过，所有Main App Swift字节与构建输入一致。运行身份、动作、CPU/位置原数据和失败采集归本机`.artifacts/inspector-root-cause-20261104`；不据此认领像素连续呈现、FPS、持续解码高压、Steam/混合列表完整体验或偶发播放/详情吞击已修。

共享动画修复后的同值选择候选已由本轮承接；实际变化的选中索引、整页顺序比较和详情单项Query扫描仍未改。复用现有权威，不叠缓存/兼容owner；下载、混合列表和在线详情的来源重任务仍须各自完整App验证。

前批R131仍有效：Video首个同步placeholder安装完整模板，metadata/库发布只回填实际UI字段；facts标签结构与列表名称变化才替换局部，无新模型cache/Task。50个预览事实、17个原生检查和30个身份检查通过，旧仅正文成本/身份对照失败；签名Debug33.388s且无编译诊断。该组件夹具的5000模型/单JPEG及受控metadata并不代表完整网格压力。R132 Steam Manager刷新候选已停止、未整合，不发布该候选App；个人设置导入R55等已结项不重做。

前批定位：R130原StaticFrame worker用full/thumbnailFallback需求，在缩略图已覆盖目标时省多余AV/模型发布，显式full和坏/小图回退保持；实际4K与交付/repair门、签名Debug及无效LLDB探针的保护边界归R130证据包。R129周期筛选/合并移出Main、R128当前App动作采样边界仍归各包；不把组件计数当全App呈现证明。

近期完成项（不重复实施）：R112–R118单一目标、共享解码/有界缓存及交付复用；R119/R121初始化与模型复用，R120来源并发，R122稳定bar，R123播放派生复用，R124视频元数据后台/详情同页来源，R125单项Query，R126无变化轮询退出，R127在线首值唯一正文/同步重挂载。当前职责/取舍归[统一设计](thumbnail-delivery-design.md#decision)，执行数字归对应有界证据包，不在首读堆流水。R111渐进候选仍拒绝，R55/R62/R109不重做。

保留失败：R117真正冷页两页/33ms空卡、R118暖盘不代表冷页、R121首开/返程失败、R122完整Grid/Video拖拽超时与旧Grid同阶段复现，仍按原包保护；不能据限定控件/重排门说完整拖拽过，也未证明环境根因。状态面板的真实Provider切片与受控传输的完整UI门仍分列，不外推为完整App性能；具体当前方法归统一设计和UI验证参考。

开批先核本段、最近相关提交及工作区；查到已完成、已拒绝或已有证据的事项时，复用结论。仅在代码/输入改变、新失败或明确未覆盖范围需要验证时重跑，压缩上下文不构成重跑理由。批次结束同步这里，避免把历史“下一步”当成当前任务。

## 目标与边界

减少没有产品消费者的实现、状态和维护分支，收敛重复计算，保持用户操作、作者内容、持久化、IPC和输出。本文拥有精简候选、分批顺序与验收，引擎职责仍归[技术栈合同](../architecture/technology-stack-boundaries.md)；前批授权、状态和验证只属于当时记录，不自动续开旧候选。

本轮按用户固定流程循环：并行子代理在每份审查任务中携带用户固定prompt，核无功能收益的校验/认证/重复计算/嵌套、持续转发和补丁、过量实现与耦合；主agent审核问题和方案并决定是否修改，子代理实施，主agent复核真实行为/成本证据和最近门后报告窄提交建议，再开启下一轮。每批报告问题、当前影响、方案、功能变化及下一候选。Git按每轮用户授权执行；2026-11-05已明确授权本批收尾、全工作区复核后提交，未授权推送或下一轮自主优化。共享构建、原生窗口和GPU仍串行，其他会话改动保留。

前批R110产品验证：产品32增13删净+19，测试净+369（真实261行生成交付夹具复用原owner，3叶适配及Python装配）。同最终Swift门44controls/16checks旧仅A交付2与memory/disk新蓝4红→新全真，原validation21、nil21控制/3观察真；repair16在唯一方法装配提取真实normalizer后补过。联合门的repair编译失败保留，其余3绿门按未变helpers/方法/编译输入复用，非最终脚本全模块运行。6308/实际输入稳定；取消仅抑交付、clear无本请求递归重生、原独立2s repair边界保。生成切片6条已有装配actor诊断与Xcode产品分列：签名Debug26.657秒/5868输入稳定strict/deep过，仅原两C#警告，3产品最终字节相同。无窗口/DB/Catalog/FPS/Leaks/TSan全验收；三无位移wheel臂无效，禁止直接Window.sendEvent的03未跑。R108批量准备、R109透过区原生证据及未过完整目录CoreDrag边界仍见同设计，不重跑旧门。

前批R104后台localDownloadStatistics在firstDownloadedAt或commit日期已存在时不准备localCreationDate，产品2增1删净+1、fixture8增；原日期helper/return与bytes枚举次序逐字保，无新helper/state/API或Scene/存储格式变化。优先级仍first→commit→creation→有效fetched，非nil distantPast提示值、metadata nil/创建缺失回退保。原14事实全留，补真实stats的commit与fetched不能盖过磁盘creation两项；同最终夹具旧/新16项全真等值，实际localCreationDate入口10→6（四次已知日期场景）。外部不可变extract hook只在生成Swift加stderr入口标记，产品和永久测试源不插桩；未另跑未观测sorting门，不称物理IO/时耗。Legacy初/变各31功能+12工作事实、42记录身份和错误9项均过；resolver事件仅按实际command的cases目录前缀归一（各294/314叶）后相等，不归一或认领真实文件时间/整记录对象等值。各6306源码输入/8实际子过程稳定；签名Debug26.161秒/5867输入稳定、strict/deep过，仅原两C#警告，独立静审接受。

前批R103网格update原双map reference数组仅供orderChanged Bool；改count差异短路加elementsEqual原reference ==，产品2增1删净+1、测试0，无新state/helper。保provider+原始UTF8、位置/重复/空/数量与同序metadata语义；真实动画diff数组、queued/provider替换、gesture/viewport其他字节保。相同原animations模式旧/新各13个运行事实全真且解析JSON严格等值，各6306源码输入/2实际子过程稳定，无约束冲突；真实Controller的动画回调与Reduce Motion受控，不外推全交互/拖拽、R23宿主或性能。旧臂含共享锁等待，不用墙钟比速度。签名Debug25.517秒/5867输入稳定、strict/deep过，仅原两C#警告，独立静审接受。只认入口显式两数组退出，不称实际分配/FPS/时耗，原R62待验及三项宿主限制不变。

前批R102状态栏applyMetrics原为可见文本/AX重复取netUpString和netDownString；改两个局部let复用，产品6增4删净+2、测试0，无新state/helper/cache，值类型输入、格式算法及采样owner不改。源码getter读取4处→2处，仅面板刷新时的小收益，不称采样/IO或实测formatter次数、时耗/能耗。旧/新现役面板门编完整真实四文件和原动作片段，均6306输入/2实际进程稳定、PASS标记同且无约束冲突诊断；SystemStats为固定字符串叶，未测完整App计时器接线或真实格式化成本。签名Debug23.621秒/5867输入稳定、strict/deep过，仅原两C#警告，独立静审接受；UI文案、AX上传/下载对应、alignment和布局保持；仅两局部声明及四插值引用改变，不涉及Scene引擎/接口。

前批R101共享媒体producer的private consumers原compactMap→Set只供八处非空判断；改computed hasMediaDemand Bool，产品9增11删净−2、测试0，无新状态/helper。八处（6直接/2 self）仍原位新鲜读取，保同步publish重入、异步epoch/selection/授权、UUID/lease/fanout、web artwork及全部Scene/Web接口；不触Scene引擎。相同原provider完整class旧/最终各33方法、34模式×DEBUG/优化-O共68次用例，stdout无需归一化逐项全等，各6306源码输入/70实际子过程稳定；完整真实Service/Store/WebArtwork/Palette配受控平台来源和偏好，不称真实权限/音乐App或引擎渲染。Root分组计数误判导致的误标旧码臂已中止、排除并清理，正式最终臂绑候选SHA；未计作新码通过。签名Debug26.591秒/5867输入稳定、strict/deep过，仅原两C#警告，独立静审接受。只认显式中间集合准备退出，不认领实际分配、时耗或能耗。

前批裁决与待验保留：R54（65522bee6）事务内复用resolved UUID追加位置，25成员/6物理列表的MAX查询25→6仅属连接级计数。R55选择器退出后再显示反馈，原配置完整导入与未归因Save取消超时保持待验。R56拒绝绕过TIFF候选，保留原编码。R57（b761fdb80）独立暂存、原main守卫后rename至原stable，保Scene/编码/copy fallback/所有权；受控5秒utility/文件探针与122项检查、Debug通过，未证自然频率或真实Web/NSWorkspace。R58（9be599202）已取消metadata Task的AV准备1→0，保同步模板和后两异步检查，不当性能/真实UI证明。R59（87c27c3e3）成功尾部一次发布完整状态，54组4→1、216→54，其他阶段相同；保89项、新增6项typed终态/reset回调及20项视口检查通过；原73/73只属reset调用点note。内部同步中间通知明确退出，不承诺任意同步订阅者等价。较早保护边界和精确证据仍归各批记录及提交，不在这里追加过程流水账。

已完成R63（9499365）方法纠偏：[产物保留规则](../../.agents/skills/mywallpaperx-maintainer/references/artifact-governance.md)是证据保留/清理的唯一说明。本轮只读保留Overlay绘制原实现：颜色/横向几何已在配置/布局准备，逐帧仍消费频谱/elapsed，不为少量cornerRadius新增缓存；工具栏收藏动作读取当前源快照，界面投影异步更新，不能直接复用显示状态并冒称等行为，不另加缓存或新鲜度owner。Hotkey已由R86在输入/旧恢复比较处验证修复，不重跑原始截止诊断。Steam影子参数已由R87退役。共享完整Settings的三测试入口依赖已闭合，GATE_SOURCES承接PlaybackControl、其他Settings桩各有边界，RO未发现新坏门，不扩中央依赖框架或冒称全门通过。R88入口读取已验；App Coordinator同turn预检/save可能重复解析，但两引用会因同步回调不同，Task后resolve还拥有freshness/租约与security scope。低频动作不为这点准备新增API或缓存，RO收束保留，不把下层发布门冒称Coordinator验收。lease错码已由R89验证；Video索引、在线图片入库和下载历史各已在清理前保存/绑定原错误，RO保持不扩修改。Web暖memo/派生analysis及stat/dependency revision各有消费者，未把缓存当播放许可，RO保持且不冒称动态新门通过。Web同轮标题重复准备已由R90验证，获取消息组装已由R93只读收束保留，终态/导入边界本轮复核保留，历史显示包装已由R94收敛；Web目录模式已由R95退役，响应reader本轮只读保留，Web宿主频谱本轮只读保留，文档首读区间已由R97验证，下一只读方向为非Scene在线图片详情任务共享/取消与预览交付；字体/排序/slider已结项不重开，不触Scene或共享Scene API。R84已验结论、R55/R62待验与其他保护边界不重开。

近期审查保留项（本轮未修改，验证范围见对应批次；不因压缩上下文重复开批）：

- 视频屏保：播放器/海报/租约有复用；重复resize仅宿主acquire，不为低频事务调整接口或新增电源缓存。
- Video IPC：边界事件单次解码，光谱多屏前已一次编码；cohort/session/request与activation/generation/可见证据检查职责不同，保留。Release日志trim无频度证据，不改。Web每命令共享lazy频谱body，忙端点只保最新pending；序号/回调归各文档，IPC各目标requestID不同，均RO保留，不新增缓存/协议组装或重跑音频门。
- Video持久化：全表save的0.25s合并、单inflight/pending和rollback/退出屏障有消费者；currentWallpaper旧值订阅仅可能多做单模型encode/defaults读取，已有字节去重，不称重复磁盘写，涉及派生路径更新及重入时机，低收益候选暂缓。metadata连带预览/静帧有暖缓存和系统同步消费者，当前不拆。
- 下载/导入：在线图片可解码准入与原子Store发布属于不同边界；Video导入磁盘检查跨后台排队，缩略图与桌面静帧也有各自消费者，保留。Steam fresh publish/签名若跳过需覆盖源码、依赖、配置与权限失效，当前不新增缓存认证链。R94旁支只读保留：CDN安全文案/外层脱敏服务不同错误来源，worker保首异常并排空；图片终态回执与即时提示分工明确，Store清理后抛已捕获error，提交后取消只撤旧自动播放。未重跑这些旁支门，不把静审升级为网络/原生或故障实测。 LibraryRecords旁支单目录wrapper有Web旧依赖发现消费者，整库single-flight与限频detail sweep保；此次只改统计回退，R68已结发布入口不重做。
- Wallhaven入口只读保留：DTO承担URL/缩略图/作者/分级/尺寸归一并保部分页面成功；每响应一次解码/每条一次转换。凭据revision跨排队/限速/返回，浏览scope保护当前页，职责不同；429日期格式化不足以支持新增缓存。本轮未重跑HTTP门，不认领真实网络/账号。
- 系统事件/媒体只读保留：采样两秒供常驻GPU图标，网络/进程指标按面板可见读取；屏保activity租约/marker/EOF及generation/revision各有消费者。热键已有字段快照去重，音频监听安装失败沿原teardown清理。Web媒体pending/ack/封面key有JS回包消费；WeakSet只去重挂接，后续DOM/shadow/iframe控制仍须遍历以覆盖后来媒体和作者修改；异步暂停后的revision/策略/surface复核保。32px palette与512px Web PNG职责/缓存各异；本轮只静审这些旁支，不以provider门外推真实宿主或重跑其余原生门。
- App控制层只读保留：Inspector已去无关scroll/zoom并在无详情/预览时退出准备；关系/catalog/选择/播放/可用性仍各有消费者，不拼跨语义canonical map。状态栏仅开窗订阅并合并willSet，封面按来源/token去重，两秒指标有UI消费；设置回声位与互斥启动菜单装配保。所查Inspector metadata无uniqueKeys initializer，不把其他Grid/Web命中外推。本轮仅静审这些旁支，未重跑其原生门。 Picker版本/signature及R43多页准备已去重，accept异步后需重读成员/resolve/epoch，不能用显示快照替代；OpenWith查询各文件处理程序与共同默认值，少量refreshCount扫描无扩大状态收益。本片仅RO，未重跑sheet/key前提门。
- 设置/初始化：双向同步回声位解决Published willSet，登录项查询已有Key周期缓存；SIL相等补丁同步ACK及恢复清理开关有真实事务消费者，保留。App启动路径重复组装少量URL不足以支持新增缓存或状态。
- Query目录计数已一次分组；单次过滤不另加索引，目录/Artwork有不同搜索和更新职责。Steam主产品协议只Parse一次，Clone服务JSON文档释放后的所有权，Writer只Serialize一次且options已复用，保留。R93只读核：PayloadULongArray已由39d441528收敛为一次TryParse，字符串中间数组仍复用入口形状过滤；请求批次的低收益不足以支持另铺解析分支或收紧ID准入。DownloadProgressState的chunk进度先做原250ms合并，再为实际发布建Snapshot；阶段与末chunk仍直接发送。发送端消费六字段，计数/sequence锁边界保留，不合入writer。仅静审，未重跑现役C#离线门或认领网络sender全字段/时耗验证。
- Web属性批量只读保留：Editor每轮一次descriptor/effective values供筛选、各row值与选项；currentValue属单项delta分支（全量已提前return），非逐row decode。author await后一次current values供payload/grants；解析cache只存baseline/roots，不吞当前override/bookmark许可。preview不重建，commit下一turn需读新覆盖；reset独立于当前conditions可达，不从visible rows推导。此片只静审，未重跑属性展示/author门或认领defaults真实次数/完整集成。
- Web响应reader只读保留：全量路径消费HTML/CSS转换、小型GET与转换后HEAD长度；常规GET Range虽走stream，TCP HEAD仍可把按实际FD识别的非nil range交给reader。直接readToEnd会改变该边界的206长度；不为删少量分支另加HEAD补丁。HTML→binary换型加HEAD Range仅静态可达，本轮未专门运行复现或量频；不借R95三门称该组合已验。
- 非Scene枚举只读复核：Video导入/内置库的预取键、OnlineImage原图清理日期均有消费者；SIL递归nil预取省工证据不足，维护路径浅层枚举无频度证据，不另开批或新增测试。
- 文件/版本只读复核：删除prepare与unlink分属捕获/实际删除时点，inode/device、fsync结果、transfer取消/单回调/delegate存活有真实消费者；版本门核不同发布产物和远端时点，prepared build已复用，App仅消费Sparkle版本展示。保留，本片未跑门；不把发布成本说成启动热路径。

每批先确认真实生产者与消费者、实际影响和最小方案，再按影响面执行最近行为门、适用 Debug 构建及必要代表运行。证据绑定本批源码、输入与执行边界；受控入口、构建或方法次数不代表完整 App、真实账户/媒体、稳定性能或发布验收。发现实际消费者或行为回退时停止该项删除；收益递减时撤回或换方向，不追加假设防御与兼容层。

现役首读只保当前范围、循环授权、最近验证、未解决项和下一候选；历史记录只保留独立证据，不逐批追加流水账。UI10 已批准设计仍留本页。

后继候选先沿真实消费链给出具体问题、方案及反例，由主agent裁决；私有候选不等于验证结项，不从历史“下一步”直接实施。R23 只有在标准宿主激活与事件流取得新证据后再考虑重开。

R23（4ba9e1b23起）：复核原生自动sender；当前原夹具编译无诊断但native40秒超时。标准NSApp.run候选到达真实outline begin，随后local mouseUp观察不返回；单waiter提前注册begin/end、async Timer让出actor的后继版本在active/key前置失败，未进入drag，不能据此判定产品或权限根因。按收益递减停止，已将两个测试路径精确恢复HEAD，全部原业务/成本断言保持，无产品改动或新增测试框架；候选未提交，自动门仍未通过，不以R22真实桌面替代验证宣称修复。最小失败证据保护保留，后续须先证明标准宿主激活和事件流再选方法，不继续加状态、延时或权限补丁。

“无调用”须排查 selector、协议回调、独立进程、作者脚本、动态资源及调试工具；测试、文档或结构登记出现名字不等于产品调用。退役时只删除已确认不可达的链路，不以行数作为收益或验收目标。

## 原生 UI 第十批：当前列表首图轻度背景染色

本批从用户授权的新增视觉试版开始，现已完成用户试用并获准提交。第五至九批及原半透明恢复已窄提交5a0fd4b5d。目标只让主窗口侧栏与内容背景随当前列表排序/筛选后的第一张静态缩略图轻度染色；按钮、选中态、警告继续系统语义色，标签半透明保持。首版采用NSBox轻染，经用户试用后改为复用已有根view的backing layer并以系统颜色动画柔和衔接，移除两个额外NSBox；现有NSSplitView/网格bounds及safe-area结构保持，避免开启侧栏延展改变列数，不另加玻璃、材质、自绘或播放面。

### 职责与数据流

六类现役grid（视频、图片、在线浏览/下载、Steam浏览/下载）继续独占排序/筛选/快照，只有其最终orderedIDs.first发布首项身份和现有缩略图加载闭包。DetailHost只绑定当前mounted grid的通用source，不另排列表、不看首个可见cell；滚动和选中不换色。Shell窗口级背景controller独占请求取消、迟到结果/代次核验、有限颜色缓存和两背景更新。既有缩略图cache/解码/静态预览生产者仍唯一，取消只撤销本功能的消费lease；不取消卡片请求，不启动壁纸播放或额外媒体进程。

图像经低分辨率原生Core Image平均色处理，颜色计算离开主线程；主线程仅投影小结果。每页同首图复用，排序后重新确认首项，首项/路径/缩略图版本改变则更新；原路径图像就绪通知也可主动失效。快速切页/旧图片迟到必须校验source实例与request generation。窗口隐藏/最小化撤销当前消费，恢复按当前source重取；不根据焦点加逻辑。

### 视觉、失败与退出

侧栏和主内容使用各自已有根layer的背景色，不增加background view、split item、约束或命中层。固定低alpha色与原系统底色/侧栏材质合成，各host有效外观解析CGColor；系统提高对比或减少透明度时退回原背景，减少动态效果时不动画。空列表/无首图/失败回系统底色，不拿另一张代替，不把旧页颜色带到新页。不同列表首图相同可同色；不强制制造不同颜色。

若原生背景干扰原生侧栏材质、内容几何/命中或可读性，修正此背景层或撤回试版；不放宽旧断言。试用收益由用户肉眼判断，不以原生、平均色或构建成功宣称FPS/CPU/能耗提升；不扩到全控件动态强调色、视频/动图背景或第二套缩略图服务。

### 验收

先验证首项排序/空列表、同首项去重、同ID换图、A→B迟到回调、同步cache命中取消、窗口可见性和颜色采样正反例。实际六入口编译/接线、原卡片几何/选中/滚动/动作门保持；比较背景安装前后布局和按钮强调色，覆盖深浅/辅助功能。冻结owned输入后交独立子代理对抗审查，修复后复审；复用唯一Debug缓存增量构建/原权限签名，启动最新App供用户试用。长期测试断言真实输入/输出/事件，临时像素/布局探针仅留有限本机证据。

### 第十批试用调整：柔和过渡与背景层合并设计

用户已确认首图染色方向，并反馈切页瞬间闪烁及多层背景疑问。第一版只取色一次、两处共用，但refresh先立即clear再上新色，且侧栏/主内容各加一个NSBox。此轮退出两额外背景view，把同样低alpha色直接写入原先已存在的侧栏根view和主内容根view的backing layer；系统window底色与原生sidebar材质继续提供基础背景，不再叠独立取色背景层。main根仍为NSView，仅补window/appearance生命周期回调，原子视图、约束、safe area、hitTest与面板内容透明度不变。

过渡只交系统Core Animation插值backgroundColor，约0.75秒ease-in/ease-out；新目标从presentation当前呈现色衔接，不从模型终点重启，不截屏、不复制内容、不加玻璃/定时器/逐帧取色。clear与新图可相继重定向同一动画，异步加载和快速A→B→C仍校验当前source/revision/generation；失败/空页淡出回系统底色。隐藏/卸载、减少透明度/提高对比立即clear并停止自有动画；减少动态效果时即时投影。DisplayOptions是唯一系统策略读取leaf，默认实时读NSWorkspace，测试分别覆盖动画和即时两支。

验收在保留既有69项取色/源检查及原网格断言的基础上，覆盖无新增subview/原命中、presentation中间值、动画重定向、A→B→C迟到、空/隐藏取消及深浅/辅助功能恢复。已结试版与限定证据见下方历史记录；原试用安排不定义当前授权，也不代替当前能力验证。

### 第十批二次试用调整（当前）

用户反馈过渡偏快且侧栏点击出现强调色→灰色切换。本轮延长同一背景动画至0.75秒，不改alpha、最终颜色、视图层级及快速重定向；侧栏只把NSTableRowView.isEmphasized归一为false，setter仍转发super，选中底色、圆角及子视图背景适配继续由原生super.drawSelection提供。原生中性灰选中在侧栏/内容焦点间保持，键盘焦点与页面导航照常，不恢复手写路径/固定颜色，也不新增抢焦点或延迟转移逻辑。[原生emphasis语义](https://developer.apple.com/documentation/appkit/nstablerowview/isemphasized)决定alternate/secondary颜色；本轮只固定后者。

已结的0.75秒二次试用、0.38秒平滑版和首版验收见[历史记录](../history/cross-topic/code-slimming-ui10-trials-2026-10-23.md)，不代表当前源码重新验收。

## 退出

候选按用户价值、证据与风险选择，达到验收或收益递减时停止该批，不扩成无界清理。专项完成或用户终止后，把稳定职责留在原合同，本文归档为历史证据并退出设计登记；不长期维持第二套引擎路线。
