# 代码精简专项

<!-- document-role: active-plan -->

复核日期：2026-10-30。负责人：repository-maintainer。本轮起点：`af44ce421`；下文前批结算只对应各自基线。

## 目标与边界

减少没有产品消费者的实现、状态和维护分支，收敛重复计算，保持用户操作、作者内容、持久化、IPC和输出。本文拥有精简候选、分批顺序与验收，引擎职责仍归[技术栈合同](../architecture/technology-stack-boundaries.md)；前批授权、状态和验证只属于当时记录，不自动续开旧候选。

本轮按用户固定流程循环：并行子代理在每份审查任务中携带用户固定prompt，核无功能收益的校验/认证/重复计算/嵌套、持续转发和补丁、过量实现与耦合；主agent审核问题和方案并决定是否修改，子代理实施，主agent复核真实行为/成本证据和最近门后决定窄提交，再开启下一轮。每批报告问题、当前影响、方案、功能变化及下一候选。当前目标授权主agent作修复和本地提交裁决，不授权推送；共享构建、原生窗口和GPU仍串行，其他会话改动保留。

R1（af44ce421起）：身份标志改用现有别名接口，省去全catalog/locator解析；下载快照复用本次记录字典，省去逐行downloads扫描，无新缓存、长期状态或owner。身份门68项通过，旧源3项反例失败且完整解析器12→0次；原生toolbar门108项通过，旧源仅重复扫描/字节身份2项反例失败；新源首次active=false前置阻塞，同输入重试通过，旧helper测试仅适配签名。功能边界：无关坏catalog不再拖累当前身份标志；下载字典采用既有UTF-8精确键，正常ASCII行为与首条记录/预览回退不变；未验证真实预览图片IO或线上账户。两个代理实施、root与独立代理复核，隔离Debug构建通过（5854输入无漂移，155.26秒；仅ScreenSaver的既有AppIntents元数据提示），代码/断言/依赖/设计/文档/产物门通过。IPC只证编码/同步写出持会话锁，未测停顿，本批不改；后继核隐藏provider遍历与批量删除解析器复用，保实际文件、逐项失败和异步边界。

R2（cdb8e3fc1起）：单provider可见时跳过另一整库filter；源文件删除预检每操作复用一个既有Resolver（受控3→1次），仍逐项try?，三个索引保持private，不扩大请求错误半径。Catalog91项、真实worker40项及负例、Commands200项、Query101项、受控unlink/替换/reset23项均通过；精确旧源分别4项遍历反例、1项构造反例失败。隔离及3dbda8498整合Debug均通过（5854输入无漂移，两次日志0error/0warning），独立复核与代码/断言/设计/文档/产物门通过。测试仅校正Unicode原始路径、真实事务receipt等待、忠实提取discardableResult；原焦点/提示/文件断言保留，受控20ms排队窗口验证等待修正，正式产品无注入。最终列表/删除结果、owner/path/可用性与跨await重置边界保持；全下载根拒绝批次接受0→1次局部构造，不添lazy状态。产品净+3行，未验证完整App视觉、真实账户或性能幅度。下一轮核同快照预览fallback复用和同token可见集合；随后核Video初载批量发布及Web冷分析FIFO搬移。

R3（20d348aef起）：下载快照在原owner用一次调用期URL字典复用同reference的完整预览结果（含nil），省去active/history重复进入同步detail-cache读取；每次新快照与loadThumbnail仍读取当前值，同一同步快照统一首个结果。可见需求同token/local不变时直接返回，避免两次全consumer并集；新token同ref仍登记租约，最后释放/重开和generation/单worker原语义保留，不抑制viewport或预取。产品净+9行，无长期状态/owner；变化token多一次有界Set比较。当前原生111项、Catalog97项、真实worker40项及负例通过；旧源三个预览/两个union反例红，旧原生另两项取消最小化断言失败、原因未定，当前通过不等于修复该UI问题。隔离Debug通过（5854输入无漂移，0error/0warning），独立复核及代码/断言/设计/隔离文档/产物门通过；工作区全仓文档门被并行Scene文档正文/导航receipt暂未同步阻断，该WIP保留。测试只观测原真实方法，预览文件IO为受控叶，未测性能幅度或完整App；后继在原Video初载owner合并大小发布、以标准slice消费Web冷分析FIFO，暂缓书签binding跨API改造。

R4（524e06522起）：Video初载size回填在原Main回调复制当前数组，保epoch、首项id/path和仅补nil，最后有变化只发布一次；不新增索引/helper/数组全比较。受控两文件publication2→1、保存调度2→1，SQLite仍1次；旧/新Debug完整功能JSON一致，最终Debug/优化各16phase、67功能及7退出检查通过，旧优化/退出未执行。Web冷分析以局部ArraySlice/popFirst替换Array.removeFirst，保FIFO、去重/取消/读取与观察顺序，旧新traversal各12项（深链206读、宽图67读）顺序一致；最终author preparation70项含取消/join/token释放通过。产品净+3行，全部werror，隔离Debug通过（5854输入无漂移，0error/0warning）；交叉复核与固定快照质量/文档门通过。最终字段/读取/生命周期保持，只合并同回执的中间发布；slice可能本次遍历内保留底层buffer，不作耗时/能耗/内存结论，AV/UI未实跑。下一候选是无消费预取assets准备；Scene脚本/typed-frame抽查已在准备期/revision复用、检查有实际提交/撤销消费者，本轮不改，C层snapshot复制仅待观察线索。

R5（e00c83b9f起）：CellAdapter在原viewport source/seen分派内只求一次isNearby，非near且无既有lease时跳过随后无人消费的prefetchAssets资源签名；有旧lease仍比较当前assets/温度并按原逻辑保留或撤销，Video独立owner、预取方向、源当次缓存和离开viewport清理不变。产品净+2行，无新索引/长期状态/helper；不捆绑新Steam需求内videoURL二次读取的小候选。原门76项当前全绿，精确旧源仅visibleOnlyWithoutPrefetchLeaseSkipsAssetPreparation反例红；其他75项及四新增入口观察中其余三项旧源均过，原空viewport/lease断言保持独立。werror及5643输入/工作区SHA无漂移；隔离Debug通过（5854输入无漂移，0error/0warning），交叉静审与固定快照质量/文档门通过。getter/媒体为受控叶，只证真实helper入口不再执行，未测实际stat/解码/时耗或完整App视觉。下一轮核C snapshot对image font的无消费复制和GPU整表只取单键；状态栏隐藏时CPU/内存/网络已有消费门，GPU图标持续消费，采样生命周期不改。

R6（52e38ec26起）：QuickJS原snapshot owner仅在native font有提交消费者时复制该字符串，image_font_script_state保留JS record.font，省去完整runtime-field更新里最终只释放的native font副本；不是每个getter/静态reuse/整帧统一省一次。保原text、输入/数值校验与commit/abort/rollback/finalize，无新状态/helper/ABI，产品净+1行。App仅配置期设cap且签名包含它；不为无现役App caller的裸C pending期间切cap增加防御层，帧间cap切换仍保留。三层实际copy helper6→5、重复image2→1，native text/无cap仍2；旧产品六组713检查仅8项新复制计数红，原行为保持，最终及ASan均713/713，最近snapshot atomicity1方法通过；ASan无内存访问错误，不作泄漏或OOM故障注入声明。78输入及3文件SHA无漂移，werror、Debug构建（5854输入，0error/0warning）与固定快照结构/质量门通过。planner通用C底座关联62模块，本次按实际font分支选原六组、ASan和atomicity，未把宽选择当必跑覆盖数或GPU声明。GPU只读10对本机单service键/类型一致，但首对67/0无法区分动态/刷新窗口，低频候选暂保留原整表；不新增fallback。后继再从实际消费者选链，不扩font字段mask或快照缓存，未测渲染/帧率/时耗。

R7（b6d53be68起）：ThumbnailCache在原finish身份检查后才求值非逃逸encodedData；同步image生成只交image，原tuple的非nil Data仍优先，异步PNG表达式与raw/source字节不变。省去loader/decoder运行中最后consumer取消、请求已退役后的JPEG/PNG编码，不保证首guard之后取消也免编码。产品净-1行，无新状态/helper/owner/guard；peer/pinned、clear/remove仍交付且禁止回填、锁外编码、二次锁内身份核及队列slot保持。真实编码入口/finish返回探针仅在临时完整源副本，零计数等真实finish defer，去掉旧40ms等待；旧源108项只两项新取消编码反例红，最终108/108、相邻原字节/GIF/缓存返回46/46通过，均werror，6283导出输入与三源SHA无漂移。独立静审、隔离Debug（5854输入，0error/0warning）及固定快照质量/文档门通过；未测完整App、动画可见、耗时/能耗。静态图片桌面恢复与跨异步身份检查有真实消费者；SIL导入路径解析跨发布/弹窗重入，暂不合并。下一批核强制中断时无消费的暂停条件查询；不改低频GPU整表与Scene topology冷miss子层语义。

R8（6fe7ef94e起）：PlaybackPolicyController.refresh前移原timer取消/清空及interruption判断；锁屏/屏保/睡眠已强制暂停时只发布system pause，不读无人消费的idle/focus/fullscreen条件，battery原本已短路，不算新增收益。最后解除仍清fullscreen缓存并完整重算、恢复timer，manual/system独立位与OR保持。产品净+3行，无新状态/helper/observer；不捆绑零调用shouldMaintainSession或低频重复扫屏。固定b6d53be68旧/新真实policy门保原256组合/通知/持久化/manual/replay断言，新增14观察当前全绿；旧源仅3计数反例红，交叠中断累计Space读取1/2/3→0/0/0，最后解除两边仍1次，真实timer字段只在临时完整副本放开。werror、6283输入/直接编译依赖与两源SHA无漂移；独立静审、6fe7ef94e隔离Debug（5854输入，0error/0warning）及质量/文档门通过。现役同步pause订阅者无policy回调；不扩为任意自定义subscriber发布途中改中断的保证，不加假设重入状态。未测60秒idle唤醒、实际睡眠/多屏/AV播放或功耗。后继查音量/静音的真实入口归一化及跨层重复发布；material/compiler磁盘暖命中待并行owner释放后再核，不重复微调已保留链。

R9（2ef8945ea起）：个人设置来源owner在原准入后跳过无本provider补丁的全库写入，按[导入合同](main-window-playlists-redesign.md#93-正式个人设置导入导出兼容)保留相关相等补丁ACK、阶段日志/恢复与原待写生命周期。产品各+1行，无新状态/owner；旧数组赋值是COW，不把它计为物理复制。实际省Video全表替换和SIL全JSON编码/写入/synchronize，未声明来源的写入故障不再阻塞当前导入，原入口准入不变。固定2ef旧新增15项恰6预期红；最终四方法204项（15来源写、34路径复用、120 schema/恢复、35排序）全绿，werror及6284输入/五源SHA无漂移。主fixture976行、原117检查未动；新145行fixture独立表达来源writer行为，只在临时原源观测真实入口，故障也计attempt。首次新增JSON逐字节断言经三事实诊断证实仅键序不同，改模型相等；不是产品修复。原timer未被no-op撤销、真实pending/in-flight排空已测，timer被测试主动取消收尾，不称自然到点已测。独审及f17bca514整合Debug（5856输入，0error/0warning）、质量/文档门通过；未测完整App导入面板或真实用户库。显式save与debounce还负担timer/失败重试，暂不合并；后继核同值音量发布。

R10（2ef8945ea起）：WallpaperManager.updateVolume只在百分比不同才赋settings.volume，省同值@Published发布引发的规范化、保存调度和设置投影比较；previousAudibleVolume、共享音量、每次显式IPC及静音/零边界完整保留。产品净+2行，无新缓存/state/owner，未删各入口clamp。固定旧/新真实UI action门均25项trace（23原+2重放）通过；六项真实Combine发布观察当前全绿，旧源只4反例红，同值/舍入重复1/1/3/1→0/0/0/0，正常变化仍各3。fixture只计settings发布，不复制实际sink逻辑；记录IPC叶不证明真实传输/听感。初次原fixture漏toggleFavorite导致编译未入测试，只补未执行的记录叶后重跑，未把装配失败计旧红。werror、6283导出输入及实际编译依赖/三源SHA无漂移；独审、bb4b3992a整合Debug（5856输入，0error/0warning）与质量/文档门通过。并入f17后编入本门的perform未变，改动的quitApp不在本门消费面。未测完整App设置持久化或声音；静音首次false迁移落盘保留，音频未注册档扫描与SystemMedia小Set候选低收益/有错误语义取舍，暂不改。下一轮核Web完整属性分支的无消费值准备及非tracking slider重复preview/commit；shared媒体采集/封面复用与撤权链本轮只读保留。

R11（b80f81bc5起）：Web属性commit只在delta分支读取committedValue，完整分支已有全部有效值的唯一消费读取，省去提前产生却无人使用的单值准备；仅移动1行、净0，无新状态/helper/缓存。保存、书签、active与grant判断/发布顺序不改；不是普通帧优化。固定旧/新真实门均96项Swift检查（92原+4载荷/发布边界）通过，旧源只有两项full读取计数红4/4→3/3，delta5与inactive1保持；三份实际JSON载荷逐对象相等、发布次数及检查顺序一致。Swift6 strict+werror、6285导出及实际编译输入/两源SHA无漂移；记录叶保存/书签/active不证明真实Defaults/授权/IPC/页面。独审及隔离Debug（5856输入，0error/0warning）、质量/文档门通过；首轮被共享锁阻止启动，确认锁已释放后同SHA重试成功，未把锁阻塞计作编译错误。候选slider非tracking先preview再commit仅静态确认native/service重复工作，页面已有签名去重/合并，未证作者回调重复或视觉问题；未实施，键盘/AX、真实tracking与页面仍待验证。本轮按用户要求在本批收尾后暂停，后继候选只保留为线索。

“无调用”须排查 selector、协议回调、独立进程、作者脚本、动态资源及调试工具；测试、文档或结构登记出现名字不等于产品调用。第一批只删除已确认不可达的链路，不以行数作为收益或验收目标。

## 第一批设计与停止条件

第一批最小结果：下列旧链整体退役，实际 AppKit、播放、查询、属性与系统指标消费者保持原实现；既有行为门和 Debug 构建通过，合同及登记同步。按用户授权，交叉审查无误后本地提交，不推送。发现真实消费者、行为依赖或失败反例时，停止删除该单元并记录原因，不添加兼容 wrapper 维持旧入口。

| 编号 | 删除范围 | 保留的真实职责 | 验收 |
|---|---|---|---|
| B1-A | 卡片交互标记、延迟复位和无人读取接口；Inspector SwiftUI 桥；旧 SwiftUI 详情组件 | AppKit 选择、详情、拖选、播放及共享 presentation 模型 | UI 投影、图库交互、详情与 AppKit 门 |
| B1-B | 无入口 SMC 温度采集、格式化、常量及 ABI 结构 | 状态栏 CPU/GPU/内存/网络采集与显示 | 状态栏投影门、Debug 构建 |
| B1-C | 未接入的 Web runtime model 组装、类型、专属缓存、签名及失效分支 | descriptor → playback context → 当前 Web host；属性、授权、诊断和磁盘缓存 | Web 属性、缓存、launch profile、资源授权及现役 WK 行为门 |
| B1-D | 旧 Steam detail scheduler、未消费的 suspicious-cache 状态、旧认证枚举和错误类型；C# 零消费者协议便利 API | 当前查询限流、预览失败退避、登录/下载及 wire 协议 | scheduler 剩余行为、Steam 查询/协议/预览门及 helper 构建 |
| B1-E | 无消费者 SceneTextureMappedUVScale 及其文件登记 | SceneTextureCandidate 的实际映射、纹理安全与渲染 | texture candidate、结构/防御面门、Debug 构建 |

数据流不新增 owner：用户动作仍进入当前 AppKit 和服务；Web 直接消费已准备 descriptor/context；Steam 继续使用当前 Swift 请求与 C# 查询限流；Scene 继续使用 typed candidate。既有数据和缓存格式、协议字段、授权、shader、逐帧执行和最终输出均不在第一批修改范围。

验证前冻结本批文件并记录内容身份；构建与运行串行进行。移除旧测试载体时，先确认其只覆盖退役实现，保留同文件中服务真实 owner 的断言。源码删除不会自动证明视觉、性能、真实 Steam 或完整兼容验收。

## 后续候选

以下是调查线索，不表示已证运行缺陷。已纳入某批的范围以本文对应章节为准；其余每批重查实际消费者和最近反例后再选范围。

| 类别 | 候选 | 后继验收/判定 |
|---|---|---|
| 旧接口 | 旧 SQLite 加载/迁移支链、信息弹窗文本、在线下载描述模型及其他无调用薄接口 | 保留实际加载、退出合并、删除及 Inspector 行为 |
| 测试独占链 | SceneEffectTextureBinding、LatestValueHandoff、旧材质 assemble/derive、粒子 runtime 级快照 | 先将有价值断言迁到当前 prepared/transaction owner；Simulator 快照仍有真实消费者 |
| 测试独占恢复 | helper 超长帧 resync | 统一当前有界关闭合同，保留超长拒绝；不扩大协议错误恢复 |
| 重复计算 | shader 多次 lex/parse；在线列表全量元数据重读与比较器属性查询；视频搜索/导航重复排序 | 同语义上下文复用，文件 revision 和稳定排序反例；收益须实测 |
| 小型算法 | Web 重复小写/正则和 BFS 队列、下载计数排序、失败历史重复扫描、协议 buffer 复制 | 相同输入/输出/失败边界；不引入多余缓存或 owner |
| 冗余构造 | 音频服务二次初始化、Steam 下载缩略图串行队列的外层 semaphore、状态栏无消费者采样 | 初始化、取消、差分采样及真实 demand 回归；Video 队列并发，现役限流保留 |
| 构建 | Steam restore/publish/签名和 stock assets 全量扫描 | 完整输入身份、资源增删、配置与签名失效；不能只关闭 alwaysOutOfDate |
| 内容判定 | 暗色视频被当作缩略图失败 | 暗色仅评分，保留真实解码 fallback；暗场/损坏/负缓存反例 |
| 数据策略 | 暂不可用文件自动删除索引 | 区分外接卷未挂载与确认删除，先设计数据保留与恢复 |
| 兼容合同 | Web 声明入口与回退矛盾、本地跨文档导航、粒子省略默认值 | 先取得语义与区分证据；不得直接移除 guard 或猜默认值 |

已排除直接删除：WebM parser、旧 Steam 数据迁移器、实际 Simulator 事务快照、必要身份/generation/GPU range/路径授权与生命周期检查；独立工具和作者 API 不因没有按钮而退役。Boids 有界规模、.NET trimming 和第三方资源目前没有足够的安全精简依据。

## 第一批实施与证据

状态：B1-A～E 完成交叉审查，已本地提交 `4749df8f7`，未推送。20 个 Swift/C# 产品文件合计增加 6 行、删除 1152 行，净减少 1146 行。删去 3 个文件，其余沿原 owner 收敛；未修改生产校验、授权、协议字段、资源范围或生命周期防护。此计数只描述源码体积，不表示性能、包体或能耗收益。

同步现役 AppKit 迁移状态、4 份 Web 合同/状态文档、文档入口及职责索引；移除退役 Scene 文件登记和旧 scheduler 测试载体，保留 Online 调度断言。最近测试关联补入现役消费者；关联只说明测试选择，不等于完整覆盖。第一批窄设计登记已按退役条件移除，本文继续拥有后续候选。

| 验证 | 结果与范围 |
|---|---|
| App Debug | `bash script/run_checkpoint_build.sh` 冷构建成功，含 Steam helper 嵌入；20 个产品文件与验证前冻结内容一致。默认隔离 DerivedData/App 已由脚本清理 |
| AppKit/图库/系统投影 | `test_ui_projection_efficiency`、`test_ui_library_algorithms`、`test_library_toolbar_behaviors`、`test_video_inspector_preview_reload`、`test_status_bar_icon_projection`、`test_steam_detail_layout`、`test_steam_appkit_interaction`、`test_steam_property_window`、`test_grid_card_lifecycle` 通过 |
| Steam | `test_ui_request_schedulers`、`test_steam_preview_lifecycle`、`test_steam_protocol_golden`、`test_steam_helper_offline`、`test_steam_queries` 通过；helper 包含 Debug/Release 离线行为，不涉及真实账号 |
| Web/属性 | `test_web_runtime_cache`、`test_web_launch_profile`、`test_web_resource_grants`、`test_web_display_conditions`、`test_web_playback_pause`、`test_web_compat_parity`、`test_scene_user_shortcut_properties` 通过；其中播放/暂停及兼容门运行真实 WKWebView |
| Scene/发布边界 | `test_scene_texture_candidate`、`test_release_diagnostic_isolation` 通过；未扩展 Scene 算法或提交权限 |
| 选择与治理 | 测试编排/路由 104 项、文档链接 6 项通过；代码行数、防御面、依赖、断言信号、设计、文档登记/健康、产物/残留及 diff 空白检查通过 |

23 个去重后的行为模块用 `python3.12 -B script/run_scene_tests.py -j 1 --module <模块>` 串行执行，构建不与运行并发。首次回归暴露两处既有夹具陈旧：Toolbar probe 缺少生产已有的 thumbnail demand 回调，现补齐并增加“只在快照完成后投递”断言；Scene 未知属性用例仍把已支持的 `usershortcut` 当未知类型，现只替换未知类型载体，原断言保留。修复前相关产品/夹具输入与 HEAD 相同。卡片回归曾因应用失焦失败；用户确认测试时可能抢焦点，所有为此试加的夹具逻辑已撤销，最终原始夹具与 HEAD 逐字节一致并复跑通过。

全局 Scene 结构门仍有既有失败：目录合同缺 6 个现役文件登记，`shape-derived-analyzer-fleet` 比基线多 1 个文件/1 次命中，导致 authority/completion 各 2 条错误。用导出的原始 HEAD 与候选分别检查，错误集合完全相同；本批没有新增结构错误，也没有放宽这些基线。此门不得记为通过，后续由原结构/能力 owner 核对登记与扫描含义。

覆盖限制：状态栏门证明图标投影，系统采样器的保留方法另经差分复核与 App 编译，未作 CPU/GPU/内存/网络硬件采样实测；未执行全 App 人工操作、多屏、真实 Steam 登录下载、全量 Scene 内容/完整 Web 兼容及性能对比。现有回归未发现本批功能退步，不将有限验证表述为绝对兼容保证。

2026-10-22 再次由 3 个独立子代理分别交叉审查 App/图库、Web/Steam、Scene/全部变更测试。均未发现误删现役消费者、功能回退或断言削弱；另逐项核对旧 Steam actor 的专属断言仅覆盖退役 owner，3 组 Online 断言逐字保留，未知属性与 Toolbar 原断言完整保留，Grid 夹具逐字等于 HEAD。本次产品、测试、构建/选测输入身份与上一轮完全一致，复用既有 Debug/23 模块结果；只重验文档收尾所影响的门。静态独审仍不替代上述未覆盖运行范围。

本机必要证据保留在忽略目录 `.artifacts/code-slimming-b1-20261022/`，包含源码身份、命令/结果、初次失败与最终复跑、构建摘要及 HEAD/候选结构对照；交叉审查身份和收尾记录在 `.artifacts/code-slimming-b1-crossreview-20261022/`，均保留 14 天至 2026-11-05。原始构建日志提取摘要后删除，本轮临时导出、HOME、缓存和构建目录清理；其他会话的缓存与证据不动。一般维护证据没有 Scene 样本身份，不伪造样本套用 runtime-sample 提取器。Git 提交按本次用户授权执行，不推送。

## 第二批范围与停止条件

基线：`4749df8f7`。状态：实现、对应回归与再次交叉审查完成，已本地提交 `7ff397f5a`，按授权整合原分支，不推送。比较继续删除旧接口、精简只读下载投影和优化 Web 依赖扫描后，本批选择后两者：输入输出和现役消费者明确，无须更改用户数据、准入或失败策略；索引恢复、导航校验和缓存判定另行论证。

| 编号 | 局部修改 | 保持的语义与最近验证 |
|---|---|---|
| B2-A | Web 开发校验报告和运行缓存签名的有界 BFS 用两个本地数组逐层交换，不反复移除首元素 | 保持入队/访问顺序、重复与环处理、路径解析、缺失/读错、120/200 文件与时间上限、截断和诊断输出；用真实生产方法检查图遍历、预算及冷/热缓存 |
| B2-B | Steam 未完成计数直接筛选计数；只读计数/失败查询使用惰性序列，避免无用排序与数组 | 保持账号、状态、空账号、首个同时间失败、排序展示和记录身份；用任务投影、JobStore、下载页计数及相邻历史/队列门验证 |

只在现有方法内调整迭代方式，不新增缓存、队列 owner、持久格式、授权或回退。常规局部算法简化由本文记录范围，不新增能力设计登记。源码行数不作为此批收益；只陈述移除的操作和复杂度，不预支 App 性能/能耗结果。若输出、顺序、界限或账号隔离出现差异，先修复或撤回该单元；不修改旧预期来适配新算法。构建/运行与另一文字渲染会话协调串行；收尾转入独立 worktree，原 checkout 的共享 JSON、Scene 文件与 index 均由另一会话独占。

预审收窄：静态 summary 没有总文件数上限，单纯游标会使已处理、重复入队的 URL 保留至扫描结束；120/200 也只约束唯一文件数，不约束重复入队元素数。因此 summary 原实现不改，两个有界扫描使用本地当前层/下一层数组，层结束即替换旧层，避免累计全部已消费前缀。层内顺序及每元素的去重、预算、时钟检查位置不变；用长链、高重复度与边界图检查。若局部替换不能保持原合同，撤回 Web 片，不引入阈值、通用队列或额外 owner。

执行与证据：新增任务查询与 Web 遍历回归先在原始 `4749df8f7` 产品上通过，再 overlay 冻结的 5 个产品文件运行 10 个最近模块，全部通过。模块为 `test_steam_download_tasks_popover`、`test_steam_download_history`、`test_steam_library_transaction`、`test_steam_library_interactions`、`test_library_toolbar_behaviors`、`test_web_dependency_traversal`、`test_web_runtime_cache`、`test_web_static_content_signals`、`test_web_launch_profile`、`test_web_resource_grants`。新增用例没有为新算法另改预期，原缓存、历史、排序和失败反例保留。

`bash script/run_checkpoint_build.sh` 默认隔离冷 Debug 构建通过，构建与测试串行。构建来自固定 `4749df8f7` 导出加本批精确 overlay，不包含另一会话在途的文字实现；冻结的 7 个候选产品/测试输入在独审、候选运行与构建前后一致，基线使用原 B1 产品及同两份增强测试。再次由 3 个子代理独立复核控制流、扫描边界、预算/时钟、空间保留、账号、状态与断言，未发现产品或测试阻塞；修正文中候选与基线身份的混淆。代码健康、设计、断言信号、产物与残留检查通过；最近测试关联已补齐，选测未映射/失效项为零，路由/链接 110 项及文档登记/健康检查通过。关联只说明最近测试选择，不代表完整功能覆盖。

源码没有新增 runtime 状态或逐帧工作。只确认移除了计数排序/中间数组和队列头部搬移；没有进行 App 性能、能耗或包体对比，不将算法简化表述为实测收益，也不认领完整 UI、真实 Steam 或全量内容兼容。Web 新门的时钟只在测试叶注入，产品时钟与预算不改。

第二批在独立 `code-slimming-b2` worktree、分支 `MWX/code-slimming-b2` 收敛，7 个产品/测试文件在转移前后逐字一致；原 checkout 的本批副本精确恢复，第一批提交及并行 Scene 工作保留。第一批本机证据留原 checkout，第二批必要证据在本 worktree 的 `.artifacts/code-slimming-b2-20261022/`，期限至 2026-11-05。本轮固定导出、临时 HOME/缓存和原始构建日志提取后清理，checkpoint DerivedData/App 已自动清理；其他会话缓存与材料不动。整合保留并行 Scene 提交 `d6d500009` 的全部产品、测试、文档及共享登记；固定组合候选的 11 个模块（上述 10 个及 `test_scene_text_native_bounds`）和隔离冷 Debug 构建再次通过，路由/链接 110 项、断言、文档健康与登记门通过。组合验证只补强相应范围；未扩大 UI、真实 Steam 或全量内容声明。合并身份以 Git 记录为准，不推送。

## 第三批范围与停止条件

基线：整合提交 `2915823cf`。状态：实施、对应回归及再次三路交叉审查完成，按用户授权本地提交并整合原分支，不推送。比较旧接口退役、音频/缩略图调度和 Web 文本重复扫描后，本批选择已能完整证明消费者的旧接口；另两类涉及并发或内容判定，继续保留候选。最小结果为删除以下无人调用支链，并通过现役持久化、Inspector、工具栏与库算法回归和 Debug 构建；出现实际消费者或反例即撤回相应删除。

| 编号 | 退役范围 | 保留职责与验证 |
|---|---|---|
| B3-A | Manager 旧 SQLite 读取/迁移 wrapper、只为其服务的已持久化判断/行数查询、无消费者的旧异步读取 | `loadInitialIndex`/异步启动、完整 SQL 读取、失败恢复、UserDefaults 迁移、退出合并及保存；现役 ordered-save 门断言逐字保留，仅去掉无调用声明的提取 |
| B3-B | `UIActionHelper.presentInfo → wallpaperDetailInfoText → infoText` 旧信息弹窗链及仅为它准备的文件名字段 | 菜单/卡片仍进入现役 Inspector，可取消 metadata Task、全部仍显示字段及预览生命周期；工具栏、Inspector 和库算法门 |

静态追踪包含全仓调用、selector、菜单、卡片、资源和测试。Online 下载 Inspector 的 Snapshot/Views 有完整用户入口，整条保留；同步 SQLite 读取仍用于真实 SQL 回归，不因测试专用就移除。初始化、授权、路径/文件扫描边界、缺失文件清理策略和数据格式均不在本批修改范围。只在现有 owner 删除退役声明，不加 wrapper 或新的测试算法；文档继续由本文拥有专项状态。

实施结果：4 个产品文件净减少 92 行。保留的方法与基线逐字核对，仅调整两处已陈旧的 Store 注释；metadata loader 只去掉无人读取的文件名构造参数，其余字段、取消检查和 MainActor completion 保持原样。两个实施子代理分工修改后，另一个独立子代理交叉检查完整 diff、真实入口与全部测试断言，未发现产品或测试阻塞。

验证：固定 `2915823cf` 导出的 `test_video_index_ordered_save` 先通过；固定候选的 `test_video_index_ordered_save`、`test_video_inspector_preview_reload`、`test_library_toolbar_behaviors`、`test_ui_library_algorithms`、`test_playback_policy`、`test_playback_policy_delivery` 六模块串行通过，随后隔离冷 Debug 构建通过。6 个产品/行为测试输入在运行和构建前后哈希一致。持久化真实 SQL、失败/中断、回退、迁移、退出与重启断言完整保留；Inspector 门仍证明预览/迟到回调，metadata 实现的保留另经静态差分与 App 编译，未声称完整人工 UI 或真实用户库迁移实测。

最近测试关联补齐 IndexStore/恢复 owner 和共享详情载体。原路由测试把 Persistence 精确限定为两项 policy 门；加入实际 ordered-save 门后，同步精确集合为三项，并新增 IndexStore、InitialIndex 与 fixture 只选择 ordered-save 的反例，未改为宽松包含判断。111 项路由/链接门通过，4 个产品路径均有最近关联，无失效/未映射项；关联仍不代表完整覆盖。代码健康、断言信号、设计、依赖、Debug 布局及文档门通过。

全局 Scene 结构门 15 项中仍有 3 个既有失败（目录登记、authority 和 completion）；固定基线与候选的这三项断言消息逐字相同，12 个其他结构项通过。未修改相关白名单、ratchet、扫描范围或 Scene 产品；不得把此门报为全绿。本批不认领性能、包体、能耗、全 App 交互或全量内容兼容。

再次由三个独立子代理分别复核持久化、Inspector 和完整测试/登记，未发现真实调用误删、功能回退或断言削弱。10 个文件及既有证据 manifest 身份一致，六个行为输入与已通过的构建/回归相同，按工作流复用这些结果；本轮重跑 111 项路由/链接与断言门，补跑并归档此前未入包的设计门输出。原分支未出现产品整合漂移，不额外占用并行 Scene 诊断窗口；纯文档状态修订只重验文档门。

证据保留在复用 worktree 的 `.artifacts/code-slimming-b3-20261022/` 及本轮 `.artifacts/code-slimming-b3-crossreview-20261022/` 至 2026-11-05；包含输入身份、基线/候选与构建摘要、独审、路由及既有结构失败对照。默认 checkpoint DerivedData/App 自动清理，固定导出和临时 HOME/缓存当轮清理，第一/二批证据与其他会话材料保留。本批从 `2915823cf` 在隔离分支收敛，提交/整合身份以 Git 记录为准，不推送。

## 第四批范围与停止条件

基线：第三批提交并快进整合后的 `a3e55663c`。状态：实施、对应回归/构建及再次三路交叉审查完成，按用户授权本地提交并整合原分支，不推送。比较继续退役旧接口、音频二次构造和 Web 重复文本扫描后，选择消费者可完整追踪的接口/载体简化；音频和内容扫描继续保留，避免混入生命周期或准入语义变更。

| 编号 | 修改 | 保留职责与验证 |
|---|---|---|
| B4-A | 删除无消费者的 `SILService.detailInfoText` 和 `wallpapers(forSILTag:)` | 现役 Inspector、`sortedWallpapers(forSILTag:)`、选择与元数据读取；SIL 元数据、投影及工具栏门 |
| B4-B | 删除无调用的 `loadDownloadedFiles`；现役删除直接消费原 URL，去掉仅作参数包装的 `OLLocalFile` 和虚构大小/时间构造 | `deleteLocalFile` 删除与 downloadedIDs 更新、网格批量完成/重载、真实 `loadEntries` 扫描及 Online Inspector；增强工具栏的选中 URL 精确集合，先跑原实现基线再跑候选 |

`OLLocalFile` 的删除调用是真实消费者，不能直接连同删除 owner 退役；本批只把既有 `file.url` 传递改为同一 URL 参数，错误处理、文件名 ID 解析和发布时间保持原行为。真实下载列表的文件筛选、顺序、扫描边界和 metadata 准入逐字保留，不借删除旧扫描方法改变当前策略。保留所有既有断言，URL 目标反例只增加约束；若发现其他载体消费者、输出变化或真实扫描差异，撤回该片。先静态实施，待并行 Scene 诊断结束后串行运行近邻回归和 Debug 构建。

实施结果：4 个产品文件净减少 78 行。两个实施子代理精确分工，另一个独立子代理复核完整 8 路径、全仓消费者、断言与登记，未发现阻塞。真实 Grid 除两行参数传递外与基线逐字一致；`deleteLocalFile` 归一化参数后函数体逐字相同，完整扫描、排序、Inspector、metadata 和批量重载保留。工具栏夹具移除镜像包装类型，原有全部检查保留，增加不同条目 URL 与精确选中集合约束，不依赖 Set 遍历顺序。

验证：原 `a3e55663c` 产品加增强夹具先通过 `test_library_toolbar_behaviors`；固定候选的同一模块、`test_ui_projection_efficiency`、`test_sil_metadata_loading`、`test_pixabay_grid_thumbnail_demand` 四模块串行通过，随后隔离冷 Debug 构建通过。5 个产品/行为夹具输入在静态复审、候选运行与构建前后身份一致；旧接口基线保留原 API，仅增加 URL 约束。与并行会话协调后才启动验证，结束立即释放窗口。

111 项路由/链接门、代码健康、断言信号、设计、依赖与文档门通过。只给既有工具栏组补入真实关联的三个路径，4 个产品路径均有最近门，无失效/未映射模块；未改扫描实现、Scene 结构规则或棘轮。第三批已记录的 3 个全局 Scene 结构失败仍为未解决债，本批不认领修复或全局全绿。

覆盖限制：工具栏门证明 Grid 向 service spy 投递精确 URL 与批量 UI 完成，其余近邻门证明 SIL 元数据/列表投影和 Online demand 生命周期；真实文件删除失败和 downloadedIDs 时序由未变的规范化函数体与 App 编译支撑，未作真实用户文件删除实测。未运行完整人工 UI、全量内容、性能/能耗或包体比较，不预支收益。

再次由三个独立子代理复核 Online、SIL/断言和完整登记/证据，未发现误删真实调用、功能退步或断言削弱。8 路径及证据 manifest 与上一轮一致，复用相同产品/夹具的基线、4 模块候选及冷 Debug 结果，本轮重跑 111 项路由/链接与断言门。路由预览不当作已执行门，Scene 依赖门也不冒充 Online/SIL 完整依赖审计；消费者和参数传递另经源码复核。

证据在复用 worktree 的 `.artifacts/code-slimming-b4-20261022/` 及本轮 `.artifacts/code-slimming-b4-crossreview-20261022/` 保留至 2026-11-05。固定基线/候选导出、临时 HOME/缓存当轮清理，成功构建原始日志提取摘要后删除，checkpoint DerivedData/App 自动清理；前三批证据和其他会话材料保留。整合按 key 保留并行 `6fd3faf56` 的两份 Scene 文档及两个文档预算收紧；该提交不改变产品/夹具/构建输入，文档组合另验，不额外重建产品。提交/合并身份以 Git 记录为准，不推送。

## 第五批范围与停止条件

基线：第四批 `59590f7a1` 与并行 `6fd3faf56` 已通过 `02188e5db` 整合。状态：实施、对应回归、构建及再次三路交叉审查完成，按用户授权窄提交并整合原分支；提交与合并身份以 Git 记录为准，未推送。比较 Web/Online 文件元数据重复读取、音频重复构造和缩略图无效同步后，选择后两项；前者的文件变更与排序快照语义需另论证，不与本批混改。

| 编号 | 简化 | 保留职责与验收 |
|---|---|---|
| B5-A | `WallpaperEngine` 不先创建无回调音频占位实例；用同一个局部 `PlaybackSpectrumDelivery` 立即创建唯一正式实例，工厂显式接收 delivery | 保持 eager 初始化、三个回调、需求驱动采集、scope/generation、pause 与恢复；真实 initializer/工厂装配回归、现役音频/IPC/切换门与 Debug 构建 |
| B5-B | 删除 Steam 下载缩略图私有串行队列内 `generationLimiter(value: 2)` 及 wait/signal | 同队列执行串行性、合并/缓存/失败、主线程 completion 和实际异步取帧等待均保留；现役缩略图门与 Debug 构建 |

Audio 仍只有原服务与 delivery owner，不改成 lazy/optional，不把设备采集提前到初始化；正式服务在原占位构造阶段创建，采集仍由 `setConsumers` 驱动。Steam 只移除同一串行闭包内无法竞争的外层信号量；`generateCGImage` 的零值等待用于异步回调，Video 缩略图队列本身并发，两者均不得顺带删除。没有权限、路径、数值或身份防护退役。新增装配检查直接使用生产 initializer 与工厂，不复制回调算法，原有断言保留；若出现提前采集、回调错误、重复 owner 或并发变化，撤回该片而不追加兜底。

实施：三个产品文件只收敛构造与同步。音频工厂三个回调体、需求/暂停/scope/generation 与采集服务内部不变；Steam 除三行外逐字保留。收益只陈述少建一次占位服务、少一次无效 permit 配对，不认领代码体积、性能、包体或能耗实测。两个实施子代理分工后，由另一个独立子代理审查完整改动、真实初始化/调用及新旧断言，未发现阻塞。

新增 `test_system_audio_spectrum_owner` 使用真实字段、完整 initializer、工厂、frame/token 和记录叶：原基线实际观察到两次构造，4 项构造/身份不变量失败，候选为一次构造，三个回调、六数组/两种 token 和 delivery 身份均通过。原服务初始化只建缓冲、分析器与 dispatch source，不启动 tap；这一点由真实初始化源码与现役恢复门核对，记录叶本身不证明硬件采集。

新增 `test_steam_download_thumbnail_pipeline` 使用真实完整 pipeline、helper/cache、ffmpeg 自有小视频及隔离 HOME；仅在抽帧入口加观测和首请求闸门，不替代生成/缓存算法。原基线和候选均通过 12 项冷帧、同 key 合并、不同 key 完成、内存/负缓存、坏/缺失文件、JPEG 落盘和主线程 completion 检查，生成最大并发为 1。复用现役 isolation flags，并启用 warnings-as-errors；原有近邻门只编译该 pipeline，不能反称已覆盖冷抽帧。

验证按冻结身份累计闭合 8 个模块：两个新门、`test_playback_switch_endpoints`、`test_system_audio_spectrum`、`test_system_audio_spectrum_recovery`、`test_scene_audio_capture_scope`、`test_playback_process_isolation`、`test_thumbnail_return_reuse`。首次候选 7 项通过，endpoints 因媒体订阅替身缺少生产已有 `needsWebArtwork` 参数编译失败；在原始 `02188e5db` 产品及原测试上复现相同两项失败后，只补替身参数，保留原全部断言，单独复跑 endpoints 通过。其余 5 个代码输入身份未变，复用已通过结果；最终 6 个代码输入均与隔离冷 Debug 构建前后相同，构建通过。不表述为一次 8/8 全绿。

选测只追加两个现役职责组；3 个产品路径均映射，无失效/未映射项。111 项路由/链接、代码健康、断言信号、设计、依赖及文档门通过。专项全文增长触发首读 150 行上限后，首读仅定位现有第五批章节，完整记录仍由同一文档及正文预算管理；150/600 上限、扫描脚本和旧路由均不放宽。既有 3 个全局 Scene 结构失败未在本批修复，本批未重跑完整结构组，不报全局全绿。

覆盖限制：装配门的服务/外部观察是记录叶；真实 service 恢复、scope/IPC 门与冷视频门分别承担对应行为，不将其合成真实硬件采集、全 App UI 或全媒体兼容验收。未作真实音乐、多屏或长期并发性能测量。必要证据在复用 worktree 的 `.artifacts/code-slimming-b5-20261022/` 至 2026-11-05；保留初次失败、基线同错和修复复跑，成功原始构建日志提取摘要后删除。临时导出、视频、HOME/缓存当轮清理，checkpoint DerivedData/App 自动清理；其他会话材料不动。再次三路静态复核未发现真实调用丢失、行为回退或断言削弱；6 个代码输入与既有回归/冷 Debug 身份一致，复用该结果。整合保留并行 `52adbf5a7` 的三份 Scene 正文、三个收紧预算及 runtime 导航收据，组合文档与 111 项路由/链接另验。

## 第六批范围与停止条件

基线：第五批 `da39b6d94` 与并行文档 `52adbf5a7` 已通过 `bb71bd5` 整合。状态：实施、互审、回归与构建完成，按用户授权窄提交并整合原分支；提交及合并身份以 Git 记录为准，未推送。比较缩略图无消费者入口、下载失败历史重复扫描和视频搜索排序后，选择第一项；后两者涉及账号/历史快照与排序语义，本批不混改。

最小结果：退役 `ThumbnailCache` 的 legacy prefetch、image-data prefetch、raw-data prefetch 和同步 cached-or-disk 便利入口，以及 Steam 下载缩略图的仅测试读取入口。删除前排查产品、独立进程、协议/selector、工具与夹具；任何真实产品消费者或行为依赖出现即保留该入口。缓存 owner、namespace、持久格式、调度、需求优先级、取消、限流、失效与主线程完成均不改。

测试独占的 raw prefetch 调用迁到现役 `loadRawDataAsync(priority: .prefetch)`；该夹具创建空 namespace，不依赖旧入口的内存已命中短路，原四条旧写不得覆盖新数据断言保留。Steam 冷视频门的同步读取断言改为从真实 request 回调验证同一缓存对象与负缓存不重复生成；保留原 12 项输入/输出与完成语义，不为删除接口删去缓存行为验收。两份迁移夹具先在未改产品上验证，再运行固定候选；独审、缩略图相关门和隔离 Debug 构建均通过。本批不改 Scene 产品与并行会话材料，不认领性能或能耗实测。

实施：两个产品文件共删除 51 行、6 个零产品消费者便利入口，现役 load、调度、取消、持久化、失效、限流和完成主体逐字不变。全 tracked 调用排查并核对无 NSObject/@objc 或协议动态入口；Online 的同名 prefetch 属另一个真实 owner，保留。两个实施子代理随后互查对方改动，另一代理复核完整四条代码/测试路径，未发现误删调用、回退或有效断言削弱。

验证：固定 `bb71bd5` 加相同两份迁移夹具的 `test_thumbnail_cache_leases`、`test_steam_download_thumbnail_pipeline` 先通过；固定候选串行一次通过这两项及 `test_thumbnail_demand_scheduling`、`test_thumbnail_return_reuse`、`test_video_thumbnail_prefetch`、`test_video_inspector_preview_reload` 共六模块。基线/候选 45 项 shared-cache 与 12 项冷视频检查均全真，候选另有 75 项需求调度检查全真；冷视频均为最大生成并发 1、总生成 3、结束 active 0。随后隔离冷 Debug 构建通过，4 个产品/测试内容身份在回归与构建前后一致。

已有测试映射覆盖两个产品路径，无未映射或失效模块；没有修改映射、扫描或棘轮。111 项路由/链接、代码健康、断言信号、设计、依赖及文档/产物/残留门通过；依赖门仍只证明其明示的 Scene/测试扫描范围，不冒充全库完整依赖审计。保留并行 `52adbf5a7` 的三份正文、三个 bodies 和 runtime 导航收据及所有其他预算；仅更新本专项正文预算与首读章节。既有三个全局 Scene 结构失败本批未修复，未重跑完整结构组，不报全局全绿。未做完整人工 UI、真实账号或全媒体兼容及性能测量。

必要证据在 `.artifacts/code-slimming-b6-20261022/` 保留至 2026-11-05；固定导出、合成媒体、临时 HOME/缓存当轮清理，成功原始构建日志提取摘要后删除，checkpoint DerivedData/App 自动清理。复用 worktree 为后续批次及前批证据保留，其他会话材料不动。本轮提交前四个产品/测试身份及证据 manifest 与上轮一致，复用相同输入的六模块与冷 Debug；仅重验状态文字涉及的文档/路由和暂存面。

## 第七批范围与停止条件

基线：第六批 `130104469` 已通过 `1cf295807` 整合；并行 Scene 最新文档、预算与导航收据来自 `52adbf5a7`，均保留。状态：实施、互审、回归与构建完成，按用户授权窄提交并整合原分支；提交及合并身份以 Git 记录为准，未推送。比较失败历史重复扫描、Video Quick Look 的排序取首和搜索前置过滤后，选择第一项；计数已在第二批完成，Quick Look 收益较小，搜索排序需另证相等键及反向排序语义，本批不混改。

最小结果：在下载合成与可见筛选的每次同步调用内，首次需要重试历史判定时按现役账号提取 failed itemID 集合，后续查集合，退出调用即释放。不引入跨调用缓存、新 owner 或历史订阅；保留 JobStore 的账号/历史权威、保留期与刷新重入合同。两个调用均在 MainActor 无 await 的同步路径中，原 mode/adult/knownID/account/state 守卫、ready 优先、重复 job 单卡、任一 failed 历史命中与排序保持不变。没有可见 retry、账号为空或被前置过滤时不增加历史读取。

保留原 toolbar 全部断言，在真实生产投影与记录叶上补多 retry、混合账号/outcome、后续成功不抵销旧失败、历史清空/新增/换号后的下一次调用等反例；history getter 计数只验证调用期复用，不代替输出断言。相同增强夹具先在原实现运行，新增成本检查预期暴露重复读取，其余行为必须通过；候选全部通过后，再跑历史、库交互、排序及任务弹窗近邻门与隔离 Debug。发现输出/守卫/重入变化即撤回本片，不添加长期缓存兜底。历史最多 100 条，本批只认领重复工作移除，不认领性能、能耗、体积实测；按当前执行授权在审查与验证无误后本地提交并继续下一批。

实施：只改 `SteamWorkshopService+DownloadFiltering.swift` 的两次同步投影与其唯一两调用的 helper。调用方各自持有 `Set<String>?`，首次有账号且到达原 retry 判定点才构建集合，空集合也复用；调用返回即释放。产品净增 7 行，不认领代码体积减少。原排序、去重、失败记录构造、JobStore、认证、刷新和订阅主体不变。两个实施子代理互查对方改动，另一代理复核完整代码/夹具/原样 runner，未发现真实调用丢失、回退或断言削弱。

验证：原 48 项 toolbar 检查及顺序逐字保留，追加 16 项（10 项行为与 6 项读取边界），共 64 项；输入和预期为显式 ID/状态/身份，真实投影、合成与 helper 从生产源码抽取。固定 `1cf295807` 加相同增强夹具的原基线恰有 4 项新增读取上限失败，其他 60 项通过；多 retry 筛选/合成分别读历史 6/7 次，空/仅外账号历史的多 retry 各读 3 次。固定候选 64 项全真，相同场景各读 1 次，无 eligible retry 或无账号路径均保持 0 次，历史增删/换号后的下一次调用反映新输入。成本反例是原实现重复读取的证据，不记为未解决产品回归，也不把原基线记为全绿。

候选一次串行通过 `test_library_toolbar_behaviors`、`test_steam_download_sorting`、`test_steam_download_execution`、`test_steam_download_history`、`test_steam_library_interactions`、`test_steam_download_tasks_popover` 六模块，随后隔离冷 Debug 构建通过。产品、夹具与原样 runner 三份内容身份在回归及构建前后不变。现有映射覆盖该产品路径，无未映射/失效模块；111 项路由/链接、代码健康、断言、设计、依赖和文档/产物/残留门通过。未修改门映射、扫描或棘轮；依赖门只证明其明示的 Scene/测试范围。并行 Scene 正文、其他预算及 runtime 导航收据仍逐项保留。既有三项全局 Scene 结构失败本批未修复，未重跑完整结构组，不报全局全绿。

读取计数只证明历史输入访问减少，不证明元素比较总量、CPU、耗时或能耗改善；首次查询从可提前命中的 contains 改为全量构建 Set，存在分配与单项查询成本取舍。两个函数及刷新重入各有自己的调用期集合，不声称整轮刷新只读取一次。未做真实账号或完整人工 UI 验收。必要证据在 `.artifacts/code-slimming-b7-20261022/` 保留至 2026-11-05；固定导出、临时 HOME/缓存当轮清理，checkpoint DerivedData/App 自动清理，成功原始构建日志提取摘要后删除。复用 worktree 为审核及前批证据保留，其他会话材料不动。

## 第八批范围与停止条件

基线：第七批 `c0673f65d` 已通过 `58d71c9e7` 整合；保留并行 `52adbf5a7` 的 Scene 正文、预算与 runtime 导航收据。状态：在独立分支 `MWX/code-slimming-b8` 完成实施、双路独审、回归与构建，按当前授权本地提交并整合；身份以 Git 记录为准，未推送。比较 Quick Look 排序取首、搜索前置过滤和其他无消费者链后，先选前者；网格 source 仍供搜索隐藏选中项的右键操作回退，不把全 source 换成过滤数组，箭头导航排序另批研究。

最小结果：`selectedWallpaperForQuickLook` 多选分支用 `selectedWallpaperIds.min()` 代替完整排序取首；保持 String 字典序、空集合、单选槽独立、最小失效 ID 返回 nil、不跳至其他有效 ID、重复模型取库中第一条与读取无副作用。Space、菜单、Shell 同步和预览内箭头仍走同一 getter，不新增选择 owner 或缓存。不把算法工作减少表述为 CPU、内存峰值或能耗实测。

现役 UIProjection harness 抽取完整真实 getter，补上述正反例，全部旧检查保持。相同增强夹具先验证原实现，再验证候选；最近 UI/库行为门、独立交叉审查与隔离 Debug 构建通过后本地提交、整合原分支并开始下一批，不推送。任何输出或真实消费者变化即撤回本片，不增加兜底逻辑。

实施与验证：产品仅替换一处完整排序取首，现役 runner 抽完整真实 getter。原 UIProjection 40 项检查/时序及执行配置逐字保留，追加 12 项 Quick Look 正反例，共 52 项；没有复制 min/sorted 算预期。固定 `58d71c9e7` 原产品配同一增强夹具全部通过；固定候选的 `test_ui_projection_efficiency`、`test_library_toolbar_behaviors`、`test_video_inspector_preview_reload` 三模块串行一次通过，原基线与候选 52 项同键同真，随后隔离冷 Debug 通过。三份产品/runner/fixture 身份在独审、回归和构建前后一致。两独立代理复核全部调用及差分，未发现回退或断言削弱。

现有测试映射覆盖该产品路径，没有新增/修改扫描、映射或棘轮；111 项路由/链接、代码健康、断言、设计、依赖及文档/产物/残留门通过。依赖门只证明其明示的 Scene/测试扫描范围，既有三项全局 Scene 结构失败未修复、未重跑完整结构组。真实 Quick Look 面板操作、全 App UI 与性能未在本批验收；这里只证明 getter 语义与最近消费者门，不外推完整窗口表现。必要证据在 `.artifacts/code-slimming-b8-20261022/` 保留至 2026-11-05；固定导出、临时 HOME/缓存与成功原始构建日志提取摘要后清理，checkpoint DerivedData/App 自动清理。其他会话材料保留，原分支整合不暂存并行 Scene 实施路径。

## 第九批范围与停止条件

基线：第八批 `a03b24a8c` 已通过 `715f09328` 整合。状态：在独立分支 `MWX/code-slimming-b9` 完成实施、交叉审查、回归及构建，按当前授权本地提交并整合；身份以 Git 记录为准，未推送。目标只是在 `moveSingleSelectionByArrowKey` 中先过滤搜索结果、再沿原 owner 排序，减少窄查询的排序输入。不改 Shell/Grid 的完整 source：该数组还为搜索隐藏选中项的右键设壁纸/Finder 回退服务，直接替换会造成真实功能回退；也不改网格过滤后去重或原导航不去重的差异。

保留 source context、全局/列表排序选择、String/localizedCompare、nil size、lastUsed 语义、先升序再整体 reversed 的降序 tie 顺序、查询规范化与 title/tags 搜索。保留四方向 clamp、列数归一、多选/search focus/unsupported/empty 守卫及 Quick Look 的 ignoreSearchFieldState 入口。只重排两项纯派生操作，无新 cache/helper/owner；出现完整值/事件/边界变化即撤回本片。

独立导航 fixture 编译真实模型、抽取完整 context/sort/filter/arrow 与选择写入 owner；旧 sort-then-filter oracle 加字面反例校验顺序和状态，不扩张现有 UIProjection 大文件。观察真实排序输入和比较次数，空查询仍同路径，窄查询只排序命中子集；不表述为全 Shell 搜索、CPU、耗时或能耗改善。相同增强测试先跑原实现，行为均须通过，仅新增工作量边界可预期失败；候选全过、近邻行为门与 Debug、交叉审查无误后本地提交整合并继续，不推送。

验证：固定原基线配相同新门，22 项检查仅两项排序工作量边界预期失败，其余 20 项通过；候选全部 22 项通过，覆盖 5376 步导航矩阵及字面顺序、状态写入和守卫反例。1024 行窄查询的排序输入从 1024 降为 4，比较次数从 3542 降为 6；无命中查询从 3542 降为 0，空查询仍为 3542。只证明所测排序工作减少，不把原成本反例记为未解决产品回归或声称原基线全绿。

候选导航、UIProjection、toolbar、Inspector 四模块串行通过，旧检查未削弱；隔离冷 Debug 99.44 秒通过，10 个产品/测试输入在回归及构建前后身份一致。独审未发现误删调用链或功能回退。现役 video-selection-presentation 映射仅追加新门及夹具，原模块、扫描范围和其余门保持。既有 111 项路由/链接及代码健康、断言、设计、依赖和文档/产物/残留门通过；追加历史权威登记组 55/56 通过，唯一失败是原基线同样存在的 composition-background-bounds 历史 README 漏行，已交还并行 Scene 文档 owner 收尾，不修改断言。依赖门仅证明其明示范围，既有三项全局 Scene 结构失败本批未修复、未重跑完整结构组，不报全局全绿。

未做完整人工 UI 或运行性能验收。必要证据在原工作区 `.artifacts/code-slimming-b9-20261022/` 保留至 2026-11-05，成功构建日志提取摘要后删除，固定导出与临时缓存当轮清理，checkpoint DerivedData/App 自动清理。按用户最新要求，临时工作树在本批提交合并、必要证据迁出后删除；后续每批沿用此收尾顺序，不留已完成批次的临时 checkout，保留原工作区及并行会话改动。

## 第十批范围与停止条件

基线：第九批 `b21c1157e` 已通过 `03919b301` 整合，随后并行 Scene `646a2557d` 的产品、文档、导航与预算更新完整保留。状态：在新临时分支 `MWX/code-slimming-b10` 完成实施、三路交叉审查、回归及构建，按当前授权窄提交并整合，身份以 Git 记录为准，未推送。比较 HTML 入口完整排序取首、Video 候选排名与其他扫描合并后，选择第一项；Video 排名仍有按 preferred/文件名查找的真实消费者，不能删除，扫描合并涉及 I/O/一致性边界另行研究。

最小结果：只把 `resolveHTMLURL` fallback 的完整排序取首换成沿原比较闭包的 min，保入口优先级、路径深度、localizedStandardCompare 和相等键时同次枚举的第一候选。保 preferred 的 trim/backslash 规范化及有效直接返回、HTML/HTM/普通文件准入、canonical containment、隐藏/package fallback 枚举和符号链接边界。显式 preferred 的隐藏入口继续按现规则准入，不把 fallback 跳过隐藏项扩张成新安全策略。不新增 owner/cache/guard，也不改 Video 排名或真实入库链。

新增独立回归抽取完整真实 resolver 与 relativePath，只在真实候选形成后观察本次列表；旧排序 oracle 使用同次已准入数组，另用完整 URL 字面反例验证准入与优先级，不假设两次文件枚举顺序一致。原基线与候选行为均须通过；比较次数只陈述所测集合，不认领文件 I/O、整体入库 CPU 或能耗改善。独立交叉审查、近邻门及隔离 Debug 无误后提交整合，迁出必要证据并删除本批临时工作树；出现输出/边界差异即修复并补回归，不能削弱断言过门。

实施：产品仅两行，原比较器及前置流程逐字保留。真实链为扫描/启动重放 → scanBuildInstalledRecord → directEntryHTMLURL/ownEntryHTMLURL/entryHTMLURL → Web 播放与 Finder 定位，均未删除。旧测试未改；新门 35 项检查覆盖完整 URL、优先级/深度/自然序、preferred 提前返回、隐藏/package、普通文件及内外/同前缀兄弟目录/根符号链接和路径穿越。

交叉审查发现最初 tie 检查可能在只有一个不同 URL 时空真，已补强原断言：从未注入观测的生产 resolver 抽原样选择表达式，对 Entry/entry 两个不同 URL 的相等键正反顺序各验取首，前置更大键拒绝直接返回数组首项。此项只模拟大小写敏感卷的已准入值；本机真实枚举只观察到单个不同 URL 的最小键组，不冒充该卷准入实测。真实文件系统用例和原观察断言全保留。

最终相同增强门在固定原实现和候选均 35/35 通过，各有 30 次真实候选选择观察；候选 HTML、库交互、下载排序、下载执行及 toolbar 五模块串行全过，随后隔离冷 Debug 110.69 秒通过，5 个执行输入前后身份一致。所测 128 项集合的实际比较从原实现 1364 次降为 127 次；枚举和元数据 I/O 未减少，不外推整体性能。两实施代理互查他人代码，第三代理独审全部范围与补强断言；未发现剩余调用链、功能或断言回退。

映射只新增 HTML owner 组，原组、模块及扫描/棘轮保持；最近产品关联无未映射或失效项。90 项编排/路由/链接、14 项文档角色、代码健康、断言信号、设计、依赖及文档/产物/残留门通过；依赖门仅证明明示范围。既有全局 Scene 结构债本批未修改、未重跑完整结构组，不报全局全绿。未验收真实 Steam 账号/下载、完整 App UI、大小写敏感卷挂载或完整 Web 兼容。

必要证据迁至原工作区 `.artifacts/code-slimming-b10-20261022/` 保留至 2026-11-05；固定导出、临时 HOME/缓存当轮清理，checkpoint DerivedData/App 自动清理，成功原始构建日志提取摘要后删除。本批完成合并与证据迁出后删除临时工作树和已合并分支，保留并行改动，随后开始下一批调查。

## 第十一批范围与停止条件

基线：第十批 `d9ca74b32` 已通过 `eed9f9dd5` 整合；并行 Scene 的 `646a2557d` 产品、权威文档、导航与预算保持。状态：在独立分支 `MWX/code-slimming-b11` 完成实施、三路交叉审查、回归及构建，按授权窄提交整合并审查最终提交，身份以 Git 记录为准，未推送。比较测试独占纹理包装、LatestValueHandoff 与旧 material assemble/derive 后选择第一项：两个 Swift struct 共 100 行，当前仅旧专属测试构造，现役纹理事实已由 candidate、slot binding 和 frame registry 持有；其他两项仍需迁移真实 mailbox 或多个 GPU 回归，不混入。

最小结果：退役 SceneEffectTextureLoadResult/Binding 及唯一专属旧测试，精确移除 layout 文件和选测路径登记。现役资源 Swift、candidate/registry 回归和全部断言保持逐字不变。先核对旧 absent/unavailable/purpose/ready/generation/extent/pending/wrongPurpose 八项的有价语义在真实 owner 的输入/输出与反例断言；旧 wrapper 私有 matches 的 slash/case 规范化随其退役，不给现役 owner 新增该行为。发现真实产品/daemon/selector/协议/脚本/工具消费者或未覆盖且有独立价值的断言即停止删除。

先跑固定原实现的旧门和现役门，再在固定候选运行现役 candidate、registry、resource view 与隔离 Debug；Metal 门须实际执行，跳过不算通过。结构合同用原基线和候选比较，不能放松既有扫描或棘轮来过门，已知全局债须明确披露。独立审查完成后窄提交整合，再审最终提交身份；迁出必要证据后删除临时工作树/分支，不推送。之后按用户新要求开始第十二批：卡片去 hover/按压缩放并保白描边，清理不可见 Web/Scene 详情诊断入口链、保正常播放及开发调试；B12 不提交，最终用含并行未提交改动的最新完整代码构建 Release App 供测试。

实施与审查：只删 100 行 Swift 载体及 196 行专属测试；全部剩余产品源与长期测试共 5242 份输入逐字等于基线。真实链为 catalog loadCandidate → candidate → publication/registry → slot → encoder，不依赖旧结构；两值类型没有公开 ABI、ObjC/selector、协议、脚本或工具注册。八项有价机制已核对到现役输入/输出与失败反例，未改长期断言。旧 unavailable 与现役 incomplete 并非相同枚举；8×4/4×4/0.5×1 与现役多 mip 用例属于机制覆盖，不声称旧手建 mask+mips 组合逐字复刻。

固定基线的旧包装、candidate、registry 三模块 14 项通过；候选 candidate、registry、asset-catalog resource-view 三模块 16 项通过，无跳过，Metal 实际执行。观察器只记录原 subprocess JSON，不替换断言；两现役二进制的 123/81 项完整结果在原实现与候选相同。隔离冷 Debug 95.01 秒通过，5242 份输入在运行/构建前后保持身份。

layout 与 gate 各删一个失效路径；防御门实测 matches 定义从 8 降为 7，按既有工具同步收紧这一基线，扫描、其他 allowance 与 acknowledgement 全保留。历史旧测试链接改为退役路径字面，保留当时结果和锚点。90 项编排/路由/链接、14 项文档角色及代码健康、断言、防御、依赖、设计、文档与产物/残留门通过；关联无失效或未映射模块。固定原/候选的结构校验完全相同：目录仍有 6 个既有登记缺口，authority/completion 各 2 条既有错误，未放宽扫描或宣称全局通过。

本批不改变视觉算法或播放入口，不认领全 App 人工、多屏、全样本、性能、包体或能耗验收。必要证据迁至原工作区 `.artifacts/code-slimming-b11-20261023/` 保留至 2026-11-06；固定导出和临时 HOME/缓存清理，checkpoint DerivedData/App 自动清理，成功原始构建日志提取摘要后删除。完成合并与最终提交复核后删除临时工作树/分支，保留并行改动；B12 保持独立未提交范围。

## 第十二批范围与停止条件

基线：B11 最终提交 `289d70d32` 经两路实际 blob 复审后，以 `9a85e1950` 整合；并行 `b14979f65` 的文档与导航/预算收据完整保留，B11 临时工作树和分支已删除。本批直接在原工作区实施，以完整最新工作区冻结副本构建 Release App，包含并行会话届时已验证的未提交改动，不以旧提交导出覆盖它们。先交付测试，审查与用户试用后按最新授权提交完整任务文件；不推送、不发布，暂不开启后续批次。

用户指定结果：所有网格卡片保持普通大小，移除 hover 放大与按压放大/缩小，保悬停描边和原选择/点击/播放/拖拽/滚动/操作条/预览/下载反馈；独立完成徽章与按钮内部动画不自动删除。覆盖 Video、Steam 浏览/已下载、在线/Pixabay 浏览及已下载、StaticImage。精确退役仅供卡片缩放的状态、动画、按压延迟与无消费者帮助方法，布局去缩放预留参数但保基础间距、列数/缩放档位/viewport/宽高比合同。不能全局移除 transform 或为失焦加补丁。

详情诊断只清理原来挂在属性按钮隐藏 Debug 菜单上的 Web/Scene 面板链及其报告专属扫描/缓存/模型；Release 原已不编入该菜单。保留属性齿轮真实入口、Scene 属性准备唯一 owner 与缓存/epoch/版本/取消/窗口生命周期、Web 入口准入/descriptor/runtime 签名/静态摘要，以及真正 CLI、DebugApp、benchmark、GPU/FrameCapture/telemetry 和运行诊断 store。只有确证仅被退役详情报告消费的叶才可删除，不能按 Diagnostics 文件名成族删除。

两子任务独立实施并交叉审查，第三代理复核边界与现役断言。原生命周期、ABA/复用、hover 白描边/操作栏、selection/playing、预览及属性/启动/Web 缓存行为用最近现役门验证；仅与授权变更或已退役报告绑定的预期/测试载体可调整，其他断言保留。Swift 变更做 Debug；最终与并行 owner 核对代码写入窗口，冻结完整最新 source、未提交/删除/未跟踪输入及内容身份，编译实际 Release 并核 App/嵌套签名与版本。发现真实调用、范围误删或失败即修复补回归，不靠放松断言/安全边界通过。测试 App 是本机交付，不触发布自动化，不安装覆盖用户现有 App。

实施与独立审查：五类卡片、Steam 两展示上下文只退役整卡 scale、专属按压状态/定时器及布局缩放预留。Steam 保留 down/up 同卡身份，Video/SIL/Online 原点击、选择、拖拽与空白处理主体保留；原 hover 颜色策略、操作条与独立完成徽章动画保留。两路审查确认没有误删真实消费者；固定基础间距会改变部分卡片尺寸，不能声称所有 frame 不变。

详情只删除隐藏 Debug 菜单、面板及其专属报告叶。Scene 原独立属性 singleton 的 identity、source version、request UUID、cache epoch、窗口 token、取消/关闭/压力/locale/active-session 行为保留；Web 两个准入函数、descriptor signature、runtime 依赖扫描与缓存保持原语义。属性门原 37 个行为案例全部保留，详情 54→53 仅退役 façade callback 检查，Web 32→23 只退役九项报告专属输出；真实强制刷新与不限额摘要 BFS、120-file/0.20s runtime 签名边界未放松。

验证中新增真实整卡 hover/按放/移出/恢复检查，观测 root model/presentation transform、transform 动画和暗色白描边。测试输入必须落在 cardRoot 内，窗口指针与事件坐标一致，并让真实 AppKit 激活规则执行；不改产品谓词或为失焦添加逻辑。原 CLI 行为门与真实子进程退出码断言保留，新增活跃交互组使用原生 App 启动；LaunchServices 启动状态不等于 App 的实际退出状态。测试输出目录缺失在调用侧创建，不改变断言。

30 个最近回归模块通过，覆盖属性准备、详情/属性窗、Web 准入/遍历/缓存/授权、Scene 输入/异步启动/daemon 接线及卡片相邻选择/预览/缩略图。五类卡片、六展示上下文新增 54 检查实际通过；同门在原提交的两张完整在线卡片上保持有效指针与白描边，并准确拒绝旧 hover scale。229 项验证工具与文档测试通过。结构门仍为 B11 相同的 layout 六条、authority 两条、completion 两条既有错误，逐条比对一致，没有修改扫描、completion 声明或扩大 allowance。最近模块选择器仍暴露未登记关联，手工最近门、独立调用链审查与整 App 构建只证明相应范围，不宣称自动 closure_complete 或全仓全绿。

完整工作区快照包含并行 `c24f2173f` 的物理鼠标后验文档及全部 B12 未提交输入；复制前后身份一致。独立审查实读导出文件，确认 Debug/Release 的 4,366 个产品、项目和资源输入哈希与权限一致，Release 完整纳入 73 个本批路径、四项新增帮助文件及七项删除。隔离冷 Debug 114.61 秒、实际 Release 430.62 秒均通过；原生卡片最终门输入前后身份不变。

测试 App 为 `.artifacts/code-slimming-b12-20261023/Release/MyWallpaperX.app`，版本 2.11.0（283）。Developer ID、Apple 安全时间戳、25 项 Mach-O 的 arm64 闭包及嵌套严格签名/权限校验通过，保留 Steam JIT、Apple Events 和 Sparkle 原权限；本机代理导致的时间戳 502 以临时 loopback 转发真实 Apple TSA 解决，未改系统代理或降低签名要求。未公证、发布、覆盖安装或自动启动真实用户数据。用户已完成本轮试用并授权提交；不据此扩大多屏或全部壁纸验收范围，不推送，不再自主开启后续任务。

构建源副本、DerivedData、反例导出及成功原始构建日志在核验结果后清理，保留上述用户测试 App 和有界收据；非 App 证据默认保留至 2026-11-06。B11 及更早临时工作树已清理，B12 未建工作树；不清理并行会话未知归属材料。

## 原生 UI 等价精简第一批

本批按首次授权完成 AppKit 精简、保持现有布局与交互并交付未提交测试 App；用户试用确认无问题后，已授权本批窄提交。最终修改限定设置分隔线和详情滚动渐隐层；底部按钮仅作对照试验，未纳入交付；不更换菜单关闭语义、侧栏强调态、网格选择/框选、瀑布流、玻璃层级或进度条外形。

底部按钮原生化试验在拖出松开取消时未达到原交互等价，已逐字节恢复原实现，不为强行替换继续添加适配状态。新增对照仍覆盖原按钮，确保交付不夹带该试验。

- 设置分隔线由原生 `NSBox` 承载原 1pt 高度、左右 16pt 缩进和深浅色透明度；不用默认 separator 样式替换原外观。行隐藏时分隔线的显示规则保留。
- 渐隐层四个固定 stop 只在创建时写入，移除滚动回调重复写入；resize 时仍同步原 mask frame，保原 0/0.035 渐隐比例、滚动位置与惯性。

验收要求：同一原生窗口 fixture 分别运行冻结原实现和候选，比较按钮普通/悬停/禁用/进度/按压与释放截图、深浅色设置分隔线、点击/拖出取消/拖回释放、Space/Return、尺寸与 action sender，以及滚动/resize 后的渐隐参数；原最近详情布局、独立属性窗、预览与工具栏行为门保留。Swift 产品代码做 Debug 构建，最终测试 App 从完整最新工作区构建并启动；仅声称有界等价结果，不以删行数宣称 FPS 提升。具体回归、差异结果和交付身份在本批结束时记录。

实际结果：原实现与最终候选各 71 项检查全部通过，行为和尺寸输出一致；72 对控件离屏绘制截图逐像素相同，覆盖深浅色、设置行隐藏及滚动/resize。离屏绘制不等于 WindowServer 合成，渐隐另按实际 mask stop/frame/滚动输入核对。四个最近模块的五项测试及 118 项验证/文档单元测试通过，未修改既有断言或扩大基线。两个产品文件共增 10、删 46 行；按钮文件与原提交逐字节一致。

隔离 Debug 70.61 秒、Release 341.54 秒通过。完整工作区冻结输入构建的测试 App 位于 `.artifacts/appkit-native-ui-b1-20261023/Release/MyWallpaperX.app`，版本 2.11.0（283），Developer ID/Apple 时间戳、arm64 闭包、嵌套签名与原权限校验通过。已实际启动并通过 AX/截图确认主窗口及设置页；未覆盖安装版。用户已确认测试无问题，本批按最新授权本地提交，不推送；下一批独立保留未提交测试范围。保留运行中的测试 App、前后对照及有界收据至用户测试；构建源副本与 DerivedData 清理，非 App 证据默认保留至 2026-11-06。

## 原生 UI 等价精简第二批

第一批经用户试用确认后提交为 `1ac578a18`。本轮用户追加“小改动不作为单独提交”，将后续小项合并为同一待审范围；保持布局和交互，先不提交并启动测试 App。UI 效果优先用真实控件对照与增量 Debug，保留一份缓存，不要求每个小项重编完整 Release；不自动开启后续批次。

- 设置分组：原生 `NSBox` 动态 fillColor 接管手写背景类、appearance/重绘回调；保浅色 8% 混色、深色 0.02 白色透明度、连续 12pt 圆角及裁切。移除无独立职责的全尺寸内容容器，让现有 `NSStackView` 直接锚定相同几何边界；行计数复用有序 contentRows，保标题、行隐藏和分隔线规则。装饰背景显式不作为辅助功能元素。
- 共享详情按钮 hover：沿用原 `activeAlways / mouseEnteredAndExited / inVisibleRect` 选项，创建时只注册一次，由 NSView 持有、AppKit 跟随 visibleRect；去掉重复删除重建的 updateTrackingAreas override 与多余 area 引用。原鼠标跟踪循环、拖出取消、键盘、状态颜色、图标和进度填充不变；未添加失焦逻辑。
- 菜单关闭观察：复用原 stop 清理方法作为原生 selector 通知入口，移除闭包 token、显式移除和 MainActor.assumeIsolated；保 AppKit 主线程关闭通知、滚轮 monitor、原事件转发、同窗网格滚动关闭和详情滚动不关闭的规则。系统通知中心管理 selector 观察者失效，不引入新通知 owner。

停止试验：底部按钮原生追踪、原生 NSMenu 的关闭规则不纳入；菜单高度改用 fittingSize 的试验虽总高度相同，NSBox 对齐边距使内部行移位，已恢复原尺寸计算及 separator 规则。行按钮身份索引保留，旧行在 provider 刷新后仍不可触发失效操作。不为强行原生化增加补偿状态或放松断言。

验证以冻结原实现与最终候选的同窗深浅色往返、真实宽度约束、绘制 alpha、无标题维护分组、装饰辅助功能与设置行命中为准；菜单覆盖空/单行/混合/长标题/连续分隔线、勾选保持打开、动作关闭、禁用、重名和旧行失效；补通知停止与对象释放反例。保留原按钮点击/拖出取消/拖回释放、键盘及渐隐对照，并运行最近真实工具栏、详情布局和属性窗门。UI 图像是控件离屏 RGBA 对照，实际 App 另做可见检查，不认领 FPS、CPU 或能耗收益。结果与增量 App 身份在最终交付时记录。

实际结果：冻结原实现与最终候选各 155 项检查全部通过，保留首批 71 项并补设置颜色/宽度/命中、菜单边界/动作、观察者释放和按钮原生区域 resize/裁切反例；92 对离屏 RGBA 图像逐字节一致，完整尺寸与回调报告相同。四个最近模块的五项测试通过。三个产品文件共增 33、删 71 行；旧按钮真实跟踪循环、菜单尺寸规则及身份索引保留，未降低既有断言、扫描边界或预算。

用户要求增量后建立同一 Debug 缓存（初始化 78.78 秒），再纳入 hover 和并行五个 Scene 产品文件后的真实增量构建为 25.52 秒。最终运行 App 为 `.artifacts/appkit-native-ui-b2-20261023/Debug/MyWallpaperX.app`，2.11.0（283），本地 Debug Developer ID 签名、27 个 Mach-O 同团队/arm64 闭包和原权限来源通过校验。首次启动遗漏 Debug 专有 dylib 签名已在产物内补齐，未改代码或降低加载校验；随后真实启动并通过 AX/截图检查主窗口与设置页。App 包含并行尚未验收的 Scene lighting 候选，本轮 UI 结论不承担其渲染验收。

全局代码健康、断言棘轮（223 不变）、设计、产物、残留及文档角色 audit 通过；document health 仅报并行 2D lighting 设计正文尚未同步预算，既有 Scene 历史索引引用和 DirectDraw 依赖门问题另有收据，不以 UI 通过外推全仓验收。用户已确认本轮 UI 测试无问题并授权将合并小项本地窄提交，不推送；保留 Debug 测试 App 和一份 `/private/tmp/mwx-native-ui-b2-jk1i6go3/` 源码/DerivedData 缓存供下轮 UI 增量，其他已退役试验和未交付 Release App 清理；最终证据保留至 2026-11-06。详细前后感知、限制及身份在本机 `.artifacts/appkit-native-ui-b2-20261023/user-perception-report.md`，不替代本文的范围与验收权威。

## 原生 UI 第三批：系统强调色与原生侧栏选择

第二批已由用户试用确认并窄提交为 `c344a8f9b`。用户允许原生控件带来的轻微颜色/样式差异，新增要求尽量使用系统强调色；用户现已肉眼试用确认，本批按最新授权窄提交。比较仅清理 hover 引用、原生详情按钮和原生侧栏选择后，选侧栏与颜色精简作为可验收结果，不另提交细碎改动。

侧栏选中背景交回 `NSTableRowView`，允许随焦点使用系统强调/非强调色；登记原生 cell 的 textField/imageView，让系统处理选中内容。保 30pt 行布局、相同点击、菜单和拖拽期间隐藏选择的规则。详情主按钮的固定 systemBlue、Steam 任务进度和排队提示改用 controlAccentColor；图片/在线下载详情封面占位渐变的自定义浅蓝改用低透明度系统强调色。成功、等待、失败继续使用系统绿/橙/红；媒体与用户选择颜色不是界面强调色，不改其数据语义。

原生详情 NSButton/进度条候选在原点击、拖出取消及拖回触发门未通过，已经整体撤回，不添加手写 tracking 来修饰原生控件，也不放松断言。现役详情按钮的鼠标、键盘、禁用、进度和布局实现保持，仅替换颜色来源。原 155 个检查逐项保留，补 8 项侧栏选择/行高/拖拽抑制恢复回归；设置、菜单、渐隐和详情几何继续对照。按钮颜色和侧栏视觉差异有意保留给用户审核，不以像素完全一致为放行条件。沿用既有 Debug 缓存增量构建，不改变卡片布局、白描边或 Scene/播放算法。

实际结果：冻结原实现与最终候选各 163 项检查通过，原 155 项断言逐项保留，补 8 项侧栏选择/几何/拖拽抑制恢复。几何/回调报告一致，只有侧栏非强调态有意改变；100 对离屏 RGBA 中 64 对一致，36 对差异集中于主按钮强调色和侧栏。工具栏、Steam 详情布局/属性窗、视频详情预览、下载任务及卡片进度六模块全部通过。产品六文件净减 8 行，不以行数或离屏测试宣称 FPS/能耗改善。

复用一份缓存的 Debug 增量构建 22.98 秒通过；测试 App 为 `.artifacts/appkit-native-ui-b3-20261023/Debug/MyWallpaperX.app`，2.11.0（283），本地 Debug 27 个 Mach-O 同团队/arm64 闭包及原权限校验通过。包含并行提交 `ae334f7d7` 及构建快照时的两个 Scene 首帧在途产品改动，UI 验收不外推其渲染。代码健康、设计、断言信号（223 不变）、产物、残留和文档角色 audit 通过；全局文档健康仍有并行启动合同在途预算/收据项。保留 App 供用户观察与一份既有源码/DerivedData 缓存供增量，已退役按钮试验和探针清理；本轮必要收据与前后感知报告保留至 2026-11-06。用户已确认测试无问题，本批按最新授权窄提交，不推送；实际可见检查与完整前后变化留本机 `launch.json` / `user-perception-report.md`。

## 原生 UI 第四批：Steam 卡片按钮交回 NSButton

第三批经用户试用确认后提交为 `fb39966d4`，保留并行 Scene 提交 `02f4ede99`。用户已试用确认，本批按最新授权窄提交。比较原生属性滚动条、登录输入框和卡片透明按钮后，优先两个已有 NSButton 继承链的卡片图标按钮：其所有现役调用都把 normal/hover/pressed 背景、边框设为透明/零，手写 tracking 与样式状态没有可见职责；属性滚动条和登录输入框有真实布局/焦点边界，本批不改。

移除 `SteamWorkshopOverlayIconButton` 及专属透明背景/圆角/边框和图标 tint wrapper，改用普通无边框 `NSButton`，保持实际图标、矩形点击范围、target/action、可用性与辅助功能标签、bar/白描边及尺寸投影。保留主卡片 tracking、悬停 GIF、订阅/详情/下载/取消/播放/停止状态 owner 和进度动画。禁用变淡交给系统，允许随原生控件发生轻微外观差异；不更换或重画媒体。沿用系统强调色，不引入自定义色。

回归先在原控件运行相同增强夹具，再比较候选：保持下载进度与跑马灯不重启、pending 与多选、符号配置和订阅语义的原断言；退役仅约束已删按钮 trackingArea 对象身份的检查，替换为深浅色/三宽度的实际按钮边缘命中、布局稳定、命令 owner/投递和禁用再启用反例。冻结编译输入并保存几何/控件图像；再执行邻近 AppKit 交互、卡片、网格与预览回归，复用一份 Debug 缓存增量构建启动供用户试用。若命中、命令或状态反例失败，修复或撤回该单元，不弱化断言强推原生化。

实际结果：同一增强卡片回归在原实现和候选均通过，两按钮深浅色、三档宽度下的完整矩形边缘/中心命中、尺寸与重复布局、实际命令投递、禁用再启用检查通过。保留卡片 tracking 身份及原下载进度、跑马灯、pending/多选、订阅和符号配置断言；未放松预期。邻近 AppKit 交互、真实网格更新、列表缩略图动画、预览生命周期、UI 投影和卡片生命周期六模块全部通过；三个产品文件净减 126 行。离屏卡片图像未捕获按钮符号，不作为图标视觉等价证据；实际 App 已在 Steam 下载页观察到详情/播放图标与卡片布局、悬停描边正常，最终由用户肉眼试用确认。

复用既有唯一 Debug 缓存的增量构建 25.44 秒通过；测试 App 为 `.artifacts/appkit-native-ui-b4-20261023/Debug/MyWallpaperX.app`，2.11.0（283），本地 Debug 27 个 Mach-O 同团队/arm64 闭包和原权限校验通过。B3 测试 App 用正常退出命令关闭，主/子进程均已退出，再启动 B4 留给用户；不修改安装版。未增加颜色配置或改变 Scene/下载策略，保留并行会话提交与在途静态审计；对应产品/测试输入与构建快照一致。没有 FPS/能耗、真实账号订阅/下载/删除或全量 Scene 验收声明；用户已确认本批测试无问题，按最新授权窄提交，不推送。保留本轮有限收据、测试 App 与原一份源码/DerivedData 缓存供连续增量；其余已结束日志提取摘要后清理，其他会话产物不动。本轮必要结果和前后感知报告保留至 2026-11-06。

## 原生 UI 第五批：无渐隐面板使用原生滚动容器

第四批已由用户试用确认后窄提交 `41302a81a`，并行 Scene 改动保留。本批先不提交。属性与 Steam 详情容器原本 fadeRatio 为零，改由原生 NSScrollView 承担滚动，保留原 layer-backed 设置；退出无视觉用途的 CAGradientLayer 遮罩与渐隐 layout override。其他需要渐隐的 Video/图片/在线详情保持现役渐隐容器。

属性面板保留原来的视觉排版、hasVerticalScroller=true、零宽且强制隐藏的 PropertyScroller，以及原 Scene/Web 控件、行高、行宽与提交 owner。试验原生 hasVerticalScroller=false 时，已有 Scene 回归发现 324 宽/overlay 样式下复选框末端被遮挡，已撤回该片，原断言未修改。用户进一步明确滚动条必须隐藏以免误触，故不以可能短暂出现的系统滚动条替代；这段定制保留有可复验的职责。

整体视觉与操作目标不变，不新增颜色、滚动 owner、输入或焦点逻辑；起始顶部完整显示，属性与详情在所有位置均不新增渐隐。系统强调色继续沿用前批配置。两产品文件净增 4 行 layer-backed 初始化，但三类实例（Scene/Web 属性与 Steam 详情）退出无用途的遮罩及 layout override；必要的隐藏滚动条定制保留。

既有属性、详情和独立属性窗口 8 项行为回归全部通过；加强的 3 项在改前基线及候选分别通过，新增两系统样式下 flash/layout/wheel 后仍隐藏、首块内容完全处于初始视口检查。详情测试只将旧渐隐类的强制查找改为唯一内容滚动容器，原通知/重建/预览/进度/订阅断言保留，候选 63 项输出均通过。最近测试映射补入原遗漏的共享属性容器精确路径，未扩大扫描根或缩减模块。固定最新 `05fd3eecc` 加 B5 工作区输入，复用原唯一 Debug 缓存增量构建 24.66 秒通过；测试 App 为 `.artifacts/appkit-native-ui-b5-20261023/Debug/MyWallpaperX.app`。本轮没有 FPS/能耗、真实账号写入或全量引擎兼容结论，未提交、未推送。

## 原生 UI 第六批：跟踪区域交由 AppKit 视口维护

第五批用户已试用确认通过，小改动保留工作区与本批合并审核，先不提交。本批比较卡片跟踪区域、在线下载提示和输入框焦点装饰，选择已有 inVisibleRect 的跟踪区域：四类网格卡片已有原生区域且只在初始化注册，移除无消费者的额外引用和初始化中不可能触发的旧区域移除；在线下载提示原本每次 updateTrackingAreas 重建同一区域，改在初始化注册一次，交 AppKit 随可见区域调整。

保留 activeInActiveApp / activeInKeyWindow 的原策略、hover 进出/移动回调、白色描边、文字/按钮显示、点击与拖动、滚动期间 hover 抑制和复用恢复；提示的进入暂停自动消失、退出重新计时与设为壁纸/关闭动作继续由原 owner 处理。布局、颜色、强调色与焦点行为不变。只验证该管理权精简和邻近事件回归，不声称 FPS/能耗收益，候选有交互差异即撤回对应片。

五产品文件净删 21 行，原有 15 项 Online/SIL/Video 完整卡片行为回归通过，覆盖不缩放/白描边、滚动与复用及异步缩略图。新提示检查执行真实完整组件、两外观/三宽度、裁切与原生按钮动作，改前/后各 42 项通过且按钮几何一致；相同 update 序列观察到改前 24 个区域、改后 1 个区域。这只证明原生可见区策略、callback 和动作，未以模拟 callback 冒充物理指针事件或实际计时器验收。既有 163 项原生 UI 断言未改，新增精确产品/fixture 测试映射，未缩减既有门。

在原唯一缓存固定 B5+B6 与并行 Scene 输入，Debug 增量构建 25.16 秒通过；测试 App 为 `.artifacts/appkit-native-ui-b6-20261023/Debug/MyWallpaperX.app`，2.11.0（283）。B5 已经用户试用确认，后续第五、六批共同保持未提交，保留并行 Scene 所有改动。保留当前试用 App、有限收据与原缓存供连续迭代，前批替换后按精确进程检查清理 App；收据保留至 2026-11-06。

## 原生 UI 第七批：详情分隔线交回原生 NSBox

第五、六批用户均已确认试用通过，按要求共同保留工作区、不单独提交。比较输入框焦点面、进度圆环与详情分隔线后，本批选视频、图片、在线下载详情的三份 makeDivider：将手写 layer 及 separatorColor 的 CGColor 快照改为原生 NSBox.separator，由 AppKit 维护外观绘制；原有 1pt 高度、宽度、间距与周边布局保持。

只更换非交互分隔线，不改详情内容 owner、预览加载、按钮动作、颜色配置或渐隐/滚动策略。系统分隔线可能在当前外观/比例下更细或对比度略有差异，由用户肉眼决定是否保留。以改前/后相同输入的实际布局、非焦点与按钮事件回归以及最近详情回归验证，固定最新输入增量构建并启动 App；任何几何/交互差异撤回对应片，不改断言过门，不声称性能收益。

临时离屏对比覆盖三详情 × 两外观 × 三宽度，共 18 组/每版 108 项检查，改前/后对齐布局和周边标题/按钮 frame 一致，按钮命中、动作及隐藏后恢复通过。NSBox.separator 的原生透明 alignment inset 使原始 frame 高 5pt，但 Auto Layout 占位仍为 1pt；临时探针据此使用 AppKit alignment rect 验证同一数值约束，没有增加包装层。此低影响替换不新增长期测试文件或测试门，探针和有限结果留本机证据；既有 163 项原生 UI 断言、B5/B6 行为断言保持原样。Video 完整详情预览/资源替换/陈旧回调现有回归通过；SIL/Online 支持文件原有永久 focused mapping 缺口仍披露，临时对比覆盖本次三份实际工厂，不以构建补称自动门覆盖。

原唯一缓存固定最新 `136ecf994` 与 B5/B6/B7 产品输入，Debug 增量构建 20.03 秒通过；测试 App 为 `.artifacts/appkit-native-ui-b7-20261023/Debug/MyWallpaperX.app`，2.11.0（283）。本批产品净删 3 行，由原生控件承担绘制/外观更新，不以行数宣称流畅度收益。第五至七批均未提交，保留并行会话所有改动；当前试用 App、有限收据与原增量缓存供连续迭代，替换前批 App 时先查精确进程并清理，收据期限 2026-11-06。

## 原生 UI 第八批：详情徽章使用原生 NSBox 与系统语义色

第五至七批均已用户试用确认，按要求共同保留工作区、不单独提交。本批比较详情徽章、登录焦点面与进度环后，选择视频/图片标签及在线下载类型徽章的 makeBadge：将三份重复工厂退役，三个调用点直接创建同一个原生 NSBox 子类 InspectorBadgeView，不保留旧 wrapper。由 NSBox.custom 接替 CALayer 填充/描边，使用 controlBackgroundColor 和 separatorColor，交 AppKit 随外观绘制；原胶囊半径 13、高度 28、宽度上限 180、标签内距、字体与截断方式保留。

三入口已有实际消费者；只改非交互徽章容器，不改标签数据、详情内容 owner、按钮、焦点、滚动、属性排版/隐藏滚动条或 B7 分隔线。统一时发现 Video 原先显式尾部截断/单行，SIL/Online 使用原生 label 缺省策略，已由共享控件的 truncatesText 参数保留，只有 Video 传 true。底色/边线采用系统中性色，主操作继续沿用既有系统强调色；外观差异由用户试用决定，不以原生替换宣称性能收益。

实际原/新构造的临时离屏对比覆盖三入口 × 三类标签 × 浅/深/恢复浅色，27组几何与文本策略一致，每版162项检查通过；字体、原文、截断、不可聚焦、无障碍文本均保留。系统底色/边线随外观切换并恢复。既有完整 Video 详情门增加真实非空标签输入及投影断言，保留原全部预览/资源替换/迟到回调断言，并按新依赖编译共享组件；没有替换或削弱已有断言。新共享组件精确登记到该既有测试组，SIL/Online既有永久focused mapping缺口仍披露，由本轮共同组件对比及实际入口检查覆盖当前改动。

七产品文件相对已验收B7净变更 -46 行，三份旧工厂及其调用链全部退役，无遗留 wrapper；通过同一原生组件拥有元数据徽章的外观配置。第五至八批均保持未提交，保留并行 Scene 文档与review receipt。复用原一份增量缓存固定最新工作区，Debug 构建22.37秒通过；测试App为 `.artifacts/appkit-native-ui-b8-20261023/Debug/MyWallpaperX.app`，2.11.0（283）。增强的Video实际视图门在改前/后均通过，有限收据和临时探针留本轮目录至2026-11-06，不新增临时工作树。

## 原生 UI 第九批：Steam 详情标签交回原生绘制

第五至八批均已用户试用确认，按要求共同保留工作区、不单独提交。比较设置维护按钮、登录焦点面与 Steam 详情横向标签后，本批选择标签胶囊：由原生 NSBox.custom 接替手写 CALayer 填充/描边及外观回调，使用 controlBackgroundColor 和 separatorColor；保持原字体、全文宽度、胶囊尺寸、间距、隐藏滚动条与双轴滚轮转横向的规则。

只更换非交互标签的绘制 owner，不改详情布局、标签数据、下载/播放/属性动作或焦点。先以原/新相同标签、窄宽度及外观切换验证文字与胶囊几何，再跑现有真实详情/滚动回归，固定最新工作区增量构建并启动试用。若原生内容边距造成偏移，修正该局部布局或撤回，不放宽原断言；不以原生化宣称 FPS、CPU 或能耗收益。

实际原/新临时离屏对比覆盖四类标签（空、短、多项、超长）× 三宽度 × 浅/深/恢复浅色，共36组、每版216项检查；全文、字体、原生无障碍文本、隐藏滚动条、胶囊与文字几何完全一致，双轴/精确与普通滚轮倍率及两端夹取均通过。NSBox 边框内容 inset 初始产生0.7pt偏移；标签跨容器约束试验又影响原有 frame 排版，已撤回，最终沿用原排版，在原生内容布局完成后按控件坐标转换设置文字 frame，不硬编码额外负偏移。临时探针只用于本轮，不增加镜像实现的长期测试；原测试及断言未改。

现有 Steam 真实详情重建/预览、底部按钮长标题/窄宽度、属性窗口与 Video 预览回归共4项测试通过；真实详情夹具63项行为检查保留。产品路径原先没有 focused mapping，本批精确加入既有 inspector-native-presentation 组，由其现有三模块承担最近回归，不新增另一测试链。实际App已从创意工坊打开Shadow Fiend作品详情，观察到系统深灰标签胶囊、完整文字和原有详情/底部按钮布局；没有执行订阅、下载或设置壁纸。

本批一产品文件净删3行，退役手写CGColor快照及外观回调，滚轮实现与详情消费入口原样保留。复用原唯一缓存固定最新工作区（含并行Scene改动），Debug增量构建20.86秒通过；27个Mach-O的团队/arm64闭包、原权限和deep/strict签名校验通过。测试App为 `.artifacts/appkit-native-ui-b9-20261023/Debug/MyWallpaperX.app`，2.11.0（283），已启动供用户试用。第五至九批均未提交，保留并行会话全部改动与暂存；B8旧测试App确认无进程后清理，当前App、有限收据与一份增量缓存留作连续迭代，收据期限2026-11-06。不声称物理指针、真实账号命令、完整Scene或性能验收。

### 第九批试用后调整：恢复标签半透明底色

用户先撤销第五至九批的提交决定，要求先恢复半透明；最新授权为全部修改经独立子代理对抗审查、修复和复审无误后再窄提交，不推送。按最新视觉反馈，视频/图片/在线详情标签恢复原 black 12% 填充，Steam 详情横向标签恢复原 labelColor 4% 填充；保留 NSBox 原生绘制、当前系统分隔色描边和全部排版/交互。原第八、九批的不透明系统底色试验退出，不再作为当前视觉要求；第十批其他精简尚未展开。本轮按原始半透明基线与当前候选比较颜色和几何，验证相邻详情并复用唯一缓存增量构建启动，先由用户肉眼确认。

原生徽章27组/每版162项、Steam标签36组/每版216项临时检查通过，候选浅/深/恢复浅色的fill RGBA与原半透明实现逐项一致，几何与文本策略不变。首次直接给labelColor加alpha会在NSBox初始化时解析成旧外观颜色，已改用NSColor动态provider按传入appearance解析；没有恢复手写CALayer或外观observer。只调整两处原生fill配置，原系统描边及所有交互保留，原测试断言不改。既有Steam详情/按钮及Video预览三项回归通过，动态色修正后再验证受影响Steam详情门。不声称新性能收益或Scene验收；原唯一UI缓存继续供增量构建。最终Debug增量构建23.19秒、27个Mach-O闭包/原权限及deep/strict签名校验通过，已正常退出旧B9并启动半透明恢复版；未增加焦点逻辑。三位独立子代理覆盖全部15产品、7测试、专项正文和3共享JSON的UI叶，首轮未发现可达回归或断言削弱；随后交叉复核真实调用和边界。另补同一实例浅/深/浅外观下四入口12对实际绘制中心像素，与原半透明版本全等；只证明透明填充中心，非整控件或全屏像素等价。全部复审无发现后按最新授权共同窄提交，不推送。

## 原生 UI 第十批：当前列表首图轻度背景染色

本批从用户授权的新增视觉试版开始，现已完成用户试用并获准提交。第五至九批及原半透明恢复已窄提交5a0fd4b5d，保留并行Scene提交和工作区。目标只让主窗口侧栏与内容背景随当前列表排序/筛选后的第一张静态缩略图轻度染色；按钮、选中态、警告继续系统语义色，标签半透明保持。首版采用NSBox轻染，经用户试用后改为复用已有根view的backing layer并以系统颜色动画柔和衔接，移除两个额外NSBox；现有NSSplitView/网格bounds及safe-area结构保持，避免开启侧栏延展改变列数，不另加玻璃、材质、自绘或播放面。

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

验收在保留既有69项取色/源检查及原网格断言的基础上，补无新增subview/原命中、presentation中间值、动画重定向、A→B→C迟到、空/隐藏取消及深浅/辅助功能恢复；独立对抗复审后增量构建重启试用，仍先不提交。以下首版运行证据仅描述调整前版本，不冒充本轮动画或层级合并验收。

### 第十批二次试用调整（当前）

用户反馈过渡偏快且侧栏点击出现强调色→灰色切换。本轮延长同一背景动画至0.75秒，不改alpha、最终颜色、视图层级及快速重定向；侧栏只把NSTableRowView.isEmphasized归一为false，setter仍转发super，选中底色、圆角及子视图背景适配继续由原生super.drawSelection提供。原生中性灰选中在侧栏/内容焦点间保持，键盘焦点与页面导航照常，不恢复手写路径/固定颜色，也不新增抢焦点或延迟转移逻辑。[原生emphasis语义](https://developer.apple.com/documentation/appkit/nstablerowview/isemphasized)决定alternate/secondary颜色；本轮只固定后者。

验证保留既有断言：controller50/50、六投影21/21、真实窗口动画28/28通过，在原0.44秒结束点仍有中间色、0.82秒达到终态；原生UI177项与toast42项通过，原163项完整保留，新增深浅外观下强调态写入、内容/侧栏焦点往返及row.cacheDisplay绘制一致性。初次漏同步一处旧0.38秒时长期望后已改为0.75并复验，未放宽断言。cacheDisplay不能还原系统材质合成后的底色（拖拽隐藏前后PNG同样不显差异），不据此宣称最终选中色/文字肉眼验收。独立代理复核35个owned SHA及8路径增量，无产品/断言剩余问题。

完整最新工作区冻结快照包含并行Scene未提交输入，复用唯一缓存增量Debug构建21.77秒成功，27个Mach-O同Team/arm64、原权限及strict deep签名通过。新包`.artifacts/appkit-native-ui-b10-soft-20261023/Debug/MyWallpaperX.app`已启动；实际AX显示视频列表、200pt侧栏及网格焦点，主进程/SteamService/Scene daemon均核对新包绝对路径，4362项产品输入与构建快照一致。窗口输入/截图自动化连续超时，旧包精确PID正常TERM退出后才启动新包；不改产品焦点逻辑、不把启动等同最终合成画面验收。用户已确认0.75秒过渡与原生中性选中试用通过；未外推到整窗浅色/所有媒体或性能。旧0.38秒测试App退出且确认无句柄后清理，仅留当前包、必要收据与一份增量缓存。2026-10-23用户验收通过并授权提交本批UI；只纳入已复审owned路径，共享预算仅暂存UI叶，完整保留并行Scene提交与未提交改动，不推送。

### 第十批平滑版验收（0.38秒试用记录）

原48检查全部迁移保留，现controller50/50、六首项projection21/21、真实窗口动画27/27通过，原生UI等价2测试通过；两独立代理复审32路径冻结SHA无剩余发现。动画门读取真实CALayer.presentation中间值，覆盖异步接色、快速重定向、同目标不重启、隐藏/辅助功能即时取消和无新增view/layer/opacity/命中变化。约0.44秒可见色已严格到目标，动画metadata自然回收另外有界验证；本机最小native探针证明同turn重定向可延后key回收，不为此添加产品清理timer。

平滑版基于包括并行Scene80363360f等最新提交的完整工作区快照，增量Debug构建21.58秒成功且无warning/error，原权限及27个arm64/同Team Mach-O strict deep签名通过，2.11.0(283)已启动并保持供用户测试。实际视频→图片→视频入口命中和取色跟随正常；两页2360×1520截图保留200pt侧栏和五列，三个背景取样点与首版NSBox稳态色完全相同（主背景53/45/32、侧栏63/53/41和61/53/42），图片页变为冷色42/43/47及50/51/55。主背景和侧栏现在只有现有根layer承担新增染色，系统底色和原生sidebar材质仍是原基础；[Core Animation颜色插值](https://developer.apple.com/documentation/quartzcore/cabasicanimation)只作用backgroundColor，不淡化面板内容。

最新包/有期限报告在`.artifacts/appkit-native-ui-b10-smooth-20261023`；首版B10 staged App确认无进程/句柄后移除，保留必要历史收据/截图，临时native探针脚本及完整成功日志已清理，唯一增量缓存仍`/private/tmp/mwx-native-ui-b2-jk1i6go3`。本轮没有新工作树、暂存、提交或推送；保留全部并行改动。实际整窗仅覆盖当前深色视频/图片代表页，隔离原生动画证据不等于整窗浅色或所有媒体/网络验收，不宣称FPS/能耗提升，最终柔和程度继续由用户试用判断。

### 第十批首版实现与本机验收（过渡调整前）

14个产品路径实现六类最终首项source、两浏览wrapper可见状态转发、DetailHost当前挂载绑定与Shell唯一被动背景。复用Video/SIL/在线/Steam原缩略图consumer，新增Video优先级参数默认仍visible，本功能请求prefetch；Steam仍通过真实PreviewState走local→remote→video静态fallback。Core Image平均色后台计算，有限缓存只存24个小颜色，普通滚动、选中和下载进度不重算。系统辅助功能策略有单一默认读取点，减少透明度/提高对比时停止本功能消费并回原底色。

两独立代理审查全部31个owned文件并复审冻结SHA；修复Optional URL解包、owner销毁取消、辅助功能开启下测试误依赖采样和SIL fixture精确门登记。旧断言无删除/放宽。14个focused tests通过，其中新controller48/48、六投影21/21，既有Steam完整容器77/77、合并快照28/28、UI投影52/52保留；新门真实编译source/controller/sampler、六publish，Video另执行真实过滤去重，cache/network叶用记录边界。文档/设计52项、验证选择68项通过，owned31路径无unmapped，未扩Scene source root或豁免。

以包含并行Scene最新提交的当前全部工作区快照复用唯一缓存增量Debug构建，24.1秒成功且无编译warning/error，三个新Swift文件进入真实target；保持原App/SteamService权限，27个Mach-O均arm64/同Team，strict deep签名通过。2.11.0(283)测试App已启动，14产品文件与构建快照哈希完全相同。实际深色视频页前后截图均2360×1520，侧栏200pt、首行五列和卡片位置不变；黄色首图让主背景从RGB(29,27,28)轻染为(53,45,32)，侧栏同向轻染，原生工具栏玻璃自然映射下方背景，控件强调色仍系统提供。视频排序菜单切文件名称后真实首项已改变；随后观察到窗口已在Steam下载页，停止自动输入，不加入焦点补偿。

完整整窗肉眼验收目前仅深色视频代表页；深浅外观、辅助功能、迟到、隐藏/销毁、命中/布局与系统按钮强调色有隔离原生harness证据，不升级为六模块所有媒体/网络、真实整窗浅色或FPS/能耗证明。试用包与有期限报告保留在`.artifacts/appkit-native-ui-b10-20261023`，唯一连续增量缓存仍`/private/tmp/mwx-native-ui-b2-jk1i6go3`；旧translucent staged App确认无进程/句柄后移除，临时编辑脚本和完整成功构建日志已清理，仅留收据/末尾。没有新工作树，本批无暂存、提交或推送，等待用户视觉反馈。

## 退出

候选按用户价值、证据与风险选择，达到验收或收益递减时停止该批，不扩成无界清理。专项完成或用户终止后，把稳定职责留在原合同，本文归档为历史证据并退出设计登记；不长期维持第二套引擎路线。
