# 代码精简专项

<!-- document-role: active-plan -->

复核日期：2026-11-02。负责人：repository-maintainer。本轮起点：`af44ce421`；下文前批结算只对应各自基线。

开批速览（每批动手前先读这里，再核 Git 状态；按需查对应 owner 和下文，不顺读全文）：

- 已裁决至R80（R61按优先级后补）。个人设置导入弹窗消失/设置变暗已由 R55（`ad1f3142d`）修复；测试 App 已交付，原配置完整导入仅待用户实测，没有新复现不重新修复、构建或复跑。
- 近期已完成：R54 合并成员查询复用、R57 Web 快照暂存隔离、R58 已取消元数据任务提前退出、R59 成功状态一次发布、R60 在线图片卡片一次装配。详情见下文；已完成项不作为新候选。
- 保留/拒绝：R55 一次 Save 取消超时尚未归因；R56 绕过 TIFF 的候选因像素/尺寸差异已拒绝。较早 R23/R38/R43 的保护边界仍有效。
- R62已交付：[本地资源先呈现与缩略图回访](local-library-loading-design.md#overview)。先解决启动短暂不可用和本地网格滚回黑卡，覆盖视频、图片及自建列表；已完成实现、最近门、Steam消费者及签名Debug；保留三项原生限制，真实用户库体感待人工验收。R61冷态导航已完成验证，见下文；不重复本专项。

- 已结 B1–B12 / 原生 UI1–UI9 按[历史记录](../history/cross-topic/code-slimming-b1-b12-ui1-ui9-2026-10-23.md)回查；本页保留当前范围、未解决项和 UI10 已批准设计，不从旧候选续开任务。

后续范围（2026-11-02）：按goal持续审查、优化所有非Scene代码及对应分类文档，Scene引擎不修改；现有能力须以原行为门和反例保持，不能用删功能换精简。

开批先核本段、最近相关提交及工作区；查到已完成、已拒绝或已有证据的事项时，复用结论。仅在代码/输入改变、新失败或明确未覆盖范围需要验证时重跑，压缩上下文不构成重跑理由。批次结束同步这里，避免把历史“下一步”当成当前任务。

## 目标与边界

减少没有产品消费者的实现、状态和维护分支，收敛重复计算，保持用户操作、作者内容、持久化、IPC和输出。本文拥有精简候选、分批顺序与验收，引擎职责仍归[技术栈合同](../architecture/technology-stack-boundaries.md)；前批授权、状态和验证只属于当时记录，不自动续开旧候选。

本轮按用户固定流程循环：并行子代理在每份审查任务中携带用户固定prompt，核无功能收益的校验/认证/重复计算/嵌套、持续转发和补丁、过量实现与耦合；主agent审核问题和方案并决定是否修改，子代理实施，主agent复核真实行为/成本证据和最近门后决定窄提交，再开启下一轮。每批报告问题、当前影响、方案、功能变化及下一候选。当前目标授权主agent作修复和本地提交裁决，不授权推送；共享构建、原生窗口和GPU仍串行，其他会话改动保留。

最近产品验证：R80将Pixiv原safe-author排除移到artwork准备前，产品2增2删、净0，无新判断/state/helper；首两type排除、原AI语义、来源作用域/分页/身份/取消均保持。原89个expect调用点及全部原文保留，夹具35增补4个真实HTTP mixed safe/accountAllowed/ranking/search对照；同最终夹具旧/新门通过，公开stdout及非探针stderr相同，自动HTTP Set-Cookie桥接仍未证。实际完整DTO入口仅加单行日志作两臂私有观测：整门构造136→132，ID100的入口14→12、ID101的10→8，其他identity计数不变；不将聚合计数称每页、URL/日期解析次数或HTTP/耗时收益。两实际编译的DTO hash命中相同探针版，随后DTO精确恢复原字节再签名Debug24.168秒/5866输入稳定、strict/deep通过，仅原两条C#警告；独立静审接受。仅受控真实Client/HTTP与边界夹具，未验真实账号/native UI，R55/R62限制不变；在线来源入口补入[仓库图](../architecture/repository-map.md)，不另造索引页。

前批R79（bf56d172a）Pixabay原值模型直接Decodable，退役三同构DTO/toItem，产品净−36、无新状态。相同最终夹具旧/新39项页面/取消事实、6合并计数、4实际错误原文等值，真实传输门及签名Debug27.720秒通过；新增6 schema事实、测试净+42。只认退役类型/组装，不称内部DecodingError类型相同、JSON解析次数减少或分配/时耗收益。

前批R78（4ab229b38）Music仅补元数据时退出未消费封面准备，产品净+7、无持久状态，完整fallback和授权/身份/代次保持。原/新各35测试过，真实事务141→151检查，候选full 12阶段/1art、补充fresh/cached各11/0；Service Debug/Release各34次执行，签名Debug26.548秒过。两层为事件叶控制与来源替身，非端到端/真实授权/时耗；未消费封面失败不再连带丢albumArtist是明确行为改善，职责归[D6](../web/mediaremote-nowplaying-design.md#来源授权与失败)。

前批R77（826169c8b）退出HistoryStore同身份预过滤及Projection显式concat，产品净0、无新状态。原12条precondition及全部文本保留，新增5条/40行，同最终夹具旧/新真实JSON落盘重开、重复及日期并列检查均过；签名Debug27.781秒通过。不称offset数值相同、实际分配/IO/耗时或native面板验证。

前批R76（44b9ffc45）删除零消费者Debug ProbeReport三参Emit及unused导入，产品0增9删，单参输出/JSON选项/stdout锁/HTTP槽位保持。现役offline门9.579秒通过Debug六suite、Release诊断缺席/静默拒绝及正常stdin协议，Debug15.392秒/strict deep通过；未验报告器输出、真实账号或运行性能。

前批R75（377ad615b）Query两入口共用一次batch搜索成员表，产品净+10用于纯helper/最小值参数，无新持久cache/context。真实Query163项两臂等值，成员遍历18→6/24→6/18→6/18→6，空白/空页/remote仍0，Resolver次数不变，签名Debug24.639秒通过。成员准备前于exclusion canonical，当前同类alias-cycle错误无callout，conflicting alias原初始化先拒；不称内部次序全同、键入延迟/FPS或原生Picker实测。

前批R74（b93f175f8）组织恢复的原局部查重容器保position后按组验证，产品净0、测试净+81；代价每成员临时Int，无持久状态。原校验/expected-state/alias/epoch、SQL和rollback保持。真实SQLite58项两臂等值、数组读取请求6→2，Store45与CAPI故障11项及签名Debug24.461秒过；非物理复制/IO/全事务复杂度或原生UndoManager/用户DB验收。

前批R73（34854b1b3）App appendRoot已收录原始路径时提前退出，原canonical去重/别名/顺序保留，产品净0。原回收与四组真实目录业务两臂过，append计数4→1/4→3/6→4/1→1，签名Debug23.245秒通过；仅此行准备计数，不含getter/effectiveRoot，不承诺外部symlink并发观察或IO/时耗。WebKit使用原记录替身，实际用户持久store未验。

前批R72（645810c18）移除零消费者SIL mode声明/注释和两个false post，产品净-8，无新测试/state。原图片应用与Steam/Pixabay事件保持；具名/raw/动态/selector/桥接独审及签名Debug23.395秒通过。限仓库信号静态退役与编译，未动态执行两个post，不借菜单/Chrome门认领通知或UI修复。

前批R71（c300e1b6e）原同步首刷后，jobs/history各dropFirst；产品净0、夹具31增，原51项及3项新增业务两臂过，仅旧1初值成本红，候选55全真。真实initial合并2→0、jobs/history后继变化各2→2，签名Debug24.198秒通过。限真实Combine/refresh/projection受控输入，不是完整App init、JobStore落盘恢复或SteamAuth/helper验收，未量时耗。

前批R70（4d06623e5）Pixabay目录四键预取改[]，原fresh读/AV复用/跨await身份全保，产品净0。原54项旧/候选等值、69次实际枚举四键→[]，缩略图9项与签名Debug24.103秒通过；nil默认预取与[]语义已核官方，不称stat/IO/时耗改善。

前批R68（dedbd5ca3）已有firstDownloadedAt/旧commit日期时跳过本地日期回退准备，产品净+5，无新helper/状态；原回退表达式和发布身份/播放租约/回滚尾部保留。六模式业务旧/候选均过，四项回退1→0、local/符号链接两项1→1，另6方法8次执行及签名Debug24.359秒通过。限稳定输入，不认领IO/时耗；仅fetchedAt与本地日期并存未单独动态覆盖。

前批R67（0254e2ae）先原rel/属性/type排除再准备纯字体URL，产品净+2，无新验证/状态/helper，原重写与作者handler保持；16项实际helper观测中10排除项1→0，其余6不变，旧/候选原HTML业务均通过、候选预算全过，签名Debug25.803秒。只属固定HTML工作次数，不是页面CPU/FPS；原Darwin临时Swift部分仅留hash，后续私有捕获驱动已独立修正验证，不倒称原源码全留。

前批R66（fe97b35e）作者ID直接排序已唯一JSON键，净0，真实HTTP/DTO双向分页门及Debug通过；自动Set-Cookie桥接未证。R65（eb6fb891）同份在线图片快照一次Catalog安装，净+10，118项及3邻门、签名Debug通过；半更新通知退出，合同归主界面§7.3，未测查询/FPS。R64（f6ceefb2）按消费分支准备候选字典，净+2，旧/新序列109等值、Manager128及签名Debug通过。R61（367840fc2）冷态导航退出filter中间数组，产品净0，旧/候选各128项通过（3个独立生成playlist UUID标签的限定归一化差异已记录），签名Debug通过。R62（27d836e50）实现与证据归[本地加载专项](local-library-loading-design.md#overview)，真实用户库体验和三项原生限制仍待验，测试App保留；不重开R55或重跑已验项。R60（9642abbc2）一次配置controls/visibility已验。

前批裁决与待验保留：R54（65522bee6）事务内复用resolved UUID追加位置，25成员/6物理列表的MAX查询25→6仅属连接级计数。R55选择器退出后再显示反馈，原配置完整导入与未归因Save取消超时保持待验。R56拒绝绕过TIFF候选，保留原编码。R57（b761fdb80）独立暂存、原main守卫后rename至原stable，保Scene/编码/copy fallback/所有权；受控5秒utility/文件探针与122项检查、Debug通过，未证自然频率或真实Web/NSWorkspace。R58（9be599202）已取消metadata Task的AV准备1→0，保同步模板和后两异步检查，不当性能/真实UI证明。R59（87c27c3e3）成功尾部一次发布完整状态，54组4→1、216→54，其他阶段相同；保89项、新增6项typed终态/reset回调及20项视口检查通过；原73/73只属reset调用点note。内部同步中间通知明确退出，不承诺任意同步订阅者等价。较早保护边界和精确证据仍归各批记录及提交，不在这里追加过程流水账。

已完成R63（9499365）方法纠偏：[产物保留规则](../../.agents/skills/mywallpaperx-maintainer/references/artifact-governance.md)是证据保留/清理的唯一说明。下一只读方向：非Scene文件传输/删除规划与App更新版本解析，先查近提交/原合同和真实消费者，不为假设竞态撤销所有权/异步边界检查。其他来源每响应已有单次整体JSON解码；Pixiv兼容DTO承担实际类型/URL/字段归一化，不能套用R79机械退役。R3/R59、下载UI/租约/恢复及R73根目录去重不重开。

近期审查保留项（本轮未修改，验证范围见对应批次；不因压缩上下文重复开批）：

- 视频屏保：播放器/海报/租约有复用；重复resize仅宿主acquire，不为低频事务调整接口或新增电源缓存。
- Video IPC：边界事件单次解码，光谱多屏前已一次编码；cohort/session/request与activation/generation/可见证据检查职责不同，保留。Release日志trim无频度证据，不改。
- Video持久化：全表save的0.25s合并、单inflight/pending和rollback/退出屏障有消费者；currentWallpaper旧值订阅仅可能多做单模型encode/defaults读取，已有字节去重，不称重复磁盘写，涉及派生路径更新及重入时机，低收益候选暂缓。metadata连带预览/静帧有暖缓存和系统同步消费者，当前不拆。
- 下载/导入：在线图片可解码准入与原子Store发布属于不同边界；Video导入磁盘检查跨后台排队，缩略图与桌面静帧也有各自消费者，保留。Steam fresh publish/签名若跳过需覆盖源码、依赖、配置与权限失效，当前不新增缓存认证链。
- 设置/初始化：双向同步回声位解决Published willSet，登录项查询已有Key周期缓存；SIL相等补丁同步ACK及恢复清理开关有真实事务消费者，保留。App启动路径重复组装少量URL不足以支持新增缓存或状态。
- Query目录计数已一次分组；单次过滤不另加索引，目录/Artwork有不同搜索和更新职责。Steam主产品协议只Parse一次，Clone服务JSON文档释放后的所有权，Writer只Serialize一次且options已复用，保留。
- 非Scene枚举只读复核：Video导入/内置库的预取键、OnlineImage原图清理日期均有消费者；SIL递归nil预取省工证据不足，维护路径浅层枚举无频度证据，不另开批或新增测试。

<a id="completed-r1-r26"></a> [归档记录](../history/cross-topic/code-slimming-r1-r26-2026-11-01.md#completed-r1-r26) <!-- archive-redirect -->

每批先确认真实生产者与消费者、实际影响和最小方案，再按影响面执行最近行为门、适用 Debug 构建及必要代表运行。证据绑定本批源码、输入与执行边界；受控入口、构建或方法次数不代表完整 App、真实账户/媒体、稳定性能或发布验收。发现实际消费者或行为回退时停止该项删除；收益递减时撤回或换方向，不追加假设防御与兼容层。

现役首读只保当前范围、循环授权、最近验证、未解决项和下一候选；已结过程按周期归档，保原文、链接和调整链，不逐批追加流水账。已结 B1–B12 / 原生 UI1–UI9 仅保永久历史锚点，UI10 已批准设计仍留本页。

后继候选先沿真实消费链给出具体问题、方案及反例，由主agent裁决；私有候选不等于验证结项，不从历史“下一步”直接实施。R23 只有在标准宿主激活与事件流取得新证据后再考虑重开。

R23（4ba9e1b23起）：复核原生自动sender；当前原夹具编译无诊断但native40秒超时。标准NSApp.run候选到达真实outline begin，随后local mouseUp观察不返回；单waiter提前注册begin/end、async Timer让出actor的后继版本在active/key前置失败，未进入drag，不能据此判定产品或权限根因。按收益递减停止，已将两个测试路径精确恢复HEAD，全部原业务/成本断言保持，无产品改动或新增测试框架；候选未提交，自动门仍未通过，不以R22真实桌面替代验证宣称修复。最小失败证据保护保留，后续须先证明标准宿主激活和事件流再选方法，不继续加状态、延时或权限补丁。

“无调用”须排查 selector、协议回调、独立进程、作者脚本、动态资源及调试工具；测试、文档或结构登记出现名字不等于产品调用。退役时只删除已确认不可达的链路，不以行数作为收益或验收目标。

<a id="第一批设计与停止条件"></a> [归档记录](../history/cross-topic/code-slimming-b1-b12-ui1-ui9-2026-10-23.md#第一批设计与停止条件) <!-- archive-redirect -->
<a id="后续候选"></a> [归档记录](../history/cross-topic/code-slimming-b1-b12-ui1-ui9-2026-10-23.md#后续候选) <!-- archive-redirect -->
<a id="第一批实施与证据"></a> [归档记录](../history/cross-topic/code-slimming-b1-b12-ui1-ui9-2026-10-23.md#第一批实施与证据) <!-- archive-redirect -->
<a id="第二批范围与停止条件"></a> [归档记录](../history/cross-topic/code-slimming-b1-b12-ui1-ui9-2026-10-23.md#第二批范围与停止条件) <!-- archive-redirect -->
<a id="第三批范围与停止条件"></a> [归档记录](../history/cross-topic/code-slimming-b1-b12-ui1-ui9-2026-10-23.md#第三批范围与停止条件) <!-- archive-redirect -->
<a id="第四批范围与停止条件"></a> [归档记录](../history/cross-topic/code-slimming-b1-b12-ui1-ui9-2026-10-23.md#第四批范围与停止条件) <!-- archive-redirect -->
<a id="第五批范围与停止条件"></a> [归档记录](../history/cross-topic/code-slimming-b1-b12-ui1-ui9-2026-10-23.md#第五批范围与停止条件) <!-- archive-redirect -->
<a id="第六批范围与停止条件"></a> [归档记录](../history/cross-topic/code-slimming-b1-b12-ui1-ui9-2026-10-23.md#第六批范围与停止条件) <!-- archive-redirect -->
<a id="第七批范围与停止条件"></a> [归档记录](../history/cross-topic/code-slimming-b1-b12-ui1-ui9-2026-10-23.md#第七批范围与停止条件) <!-- archive-redirect -->
<a id="第八批范围与停止条件"></a> [归档记录](../history/cross-topic/code-slimming-b1-b12-ui1-ui9-2026-10-23.md#第八批范围与停止条件) <!-- archive-redirect -->
<a id="第九批范围与停止条件"></a> [归档记录](../history/cross-topic/code-slimming-b1-b12-ui1-ui9-2026-10-23.md#第九批范围与停止条件) <!-- archive-redirect -->
<a id="第十批范围与停止条件"></a> [归档记录](../history/cross-topic/code-slimming-b1-b12-ui1-ui9-2026-10-23.md#第十批范围与停止条件) <!-- archive-redirect -->
<a id="第十一批范围与停止条件"></a> [归档记录](../history/cross-topic/code-slimming-b1-b12-ui1-ui9-2026-10-23.md#第十一批范围与停止条件) <!-- archive-redirect -->
<a id="第十二批范围与停止条件"></a> [归档记录](../history/cross-topic/code-slimming-b1-b12-ui1-ui9-2026-10-23.md#第十二批范围与停止条件) <!-- archive-redirect -->
<a id="原生-ui-等价精简第一批"></a> [归档记录](../history/cross-topic/code-slimming-b1-b12-ui1-ui9-2026-10-23.md#原生-ui-等价精简第一批) <!-- archive-redirect -->
<a id="原生-ui-等价精简第二批"></a> [归档记录](../history/cross-topic/code-slimming-b1-b12-ui1-ui9-2026-10-23.md#原生-ui-等价精简第二批) <!-- archive-redirect -->
<a id="原生-ui-第三批系统强调色与原生侧栏选择"></a> [归档记录](../history/cross-topic/code-slimming-b1-b12-ui1-ui9-2026-10-23.md#原生-ui-第三批系统强调色与原生侧栏选择) <!-- archive-redirect -->
<a id="原生-ui-第四批steam-卡片按钮交回-nsbutton"></a> [归档记录](../history/cross-topic/code-slimming-b1-b12-ui1-ui9-2026-10-23.md#原生-ui-第四批steam-卡片按钮交回-nsbutton) <!-- archive-redirect -->
<a id="原生-ui-第五批无渐隐面板使用原生滚动容器"></a> [归档记录](../history/cross-topic/code-slimming-b1-b12-ui1-ui9-2026-10-23.md#原生-ui-第五批无渐隐面板使用原生滚动容器) <!-- archive-redirect -->
<a id="原生-ui-第六批跟踪区域交由-appkit-视口维护"></a> [归档记录](../history/cross-topic/code-slimming-b1-b12-ui1-ui9-2026-10-23.md#原生-ui-第六批跟踪区域交由-appkit-视口维护) <!-- archive-redirect -->
<a id="原生-ui-第七批详情分隔线交回原生-nsbox"></a> [归档记录](../history/cross-topic/code-slimming-b1-b12-ui1-ui9-2026-10-23.md#原生-ui-第七批详情分隔线交回原生-nsbox) <!-- archive-redirect -->
<a id="原生-ui-第八批详情徽章使用原生-nsbox-与系统语义色"></a> [归档记录](../history/cross-topic/code-slimming-b1-b12-ui1-ui9-2026-10-23.md#原生-ui-第八批详情徽章使用原生-nsbox-与系统语义色) <!-- archive-redirect -->
<a id="原生-ui-第九批steam-详情标签交回原生绘制"></a> [归档记录](../history/cross-topic/code-slimming-b1-b12-ui1-ui9-2026-10-23.md#原生-ui-第九批steam-详情标签交回原生绘制) <!-- archive-redirect -->
<a id="第九批试用后调整恢复标签半透明底色"></a> [归档记录](../history/cross-topic/code-slimming-b1-b12-ui1-ui9-2026-10-23.md#第九批试用后调整恢复标签半透明底色) <!-- archive-redirect -->

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
