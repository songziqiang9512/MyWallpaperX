<!-- document-role: active-plan -->

# Apple silicon 与全 App 性能优化执行方案

状态：2026-10-22 D17全模块网格需求调度实现、最近门、独审、两配置零警告及签名Release实际操作完成，新版已交用户测试；D16缩略图返回复用已完成实现与最近门，已通过独审、最近门与构建；D15网格共享滚动／复用与布局、在线图后台已解码呈现已完成独审、38功能用例与局部正向对照，签名Release已交用户体验；整App FPS未量化，不据局部数据外推。

<a id="深入实施-d1d62026-10-21"></a>
## 深入实施 D1–D17（2026-10-22）

来源：冻结 `039d164cb` 的优化Debug外部CPU/System/Metal采样、752组词法完整输出对照与75s真实Web音频端点退役反例；证据在忽略的 `apple-silicon-deep-analysis-20261021` 包。局部词法多线程收益不代表整App；GPU类别区间重叠，不相加为可省时间。方案经独立研究复核后获用户实施授权。

| 阶段 | 原owner内最小结果、退出与验收 | 状态 |
|---|---|---|
| D2 Web音频 |端点表独占需求归属，surface/主App只派生聚合；goodbye/导航/租约/拆屏撤销，旧ACK/回包不得恢复。设计见Web进程合同| 已保留：端点回收与75s原生验证通过 |
| D3 Range | 原scheme/loopback流式owner按有效区间seek+remaining分块；保授权/每块撤销/取消/短读/206/HEAD/416，loopback stop沿原owner关闭连接。有界内存与真实响应字节门，不能借此改路径/HTTP策略 | 已保留：真实scheme/TCP行为门通过 |
| D4 远程CSS | 先用可控延迟确认当前WebKit的@import关键路径，再决定是否调整。字体/级联/加载时序有兼容风险且无可证等价则保留现状；不得删字体换速度 | 候选实测停止 |
| D9 Video启动库结算 | 原Manager合并完整SQLite基线与启动期动作；未知基线失败时仅持久化有版本增量，退出／重试／reset不丢动作或覆盖未见库 | 已保留：18种mode／65检查、最终Debug／Release零警告及独审通过 |
| D11 Web物理Space | 同一最小WK二进制A／B只差reassert，另测真实WebDaemon C；同页、真实手动普通桌面切换、连续RAF／timer与原生事件，不能用模拟通知代替 | 已完成并独审：A4／B6／C5事件不支持reassert为主要停顿原因，停止该方向产品修改 |
| D15 全模块网格滚动 | 原AppKit视图保留；滚动态仅暂停hover/GIF，补原生item复用，按输入变化刷新布局，完善缩略图已解码呈现 | 实现与独审完成：38功能用例、106编排用例通过；同输入布局局部耗时下降，最新Debug／Release零warning；普通Release已交用户测试，完整实机矩阵／FPS不认领 |
| D16 缩略图返回复用 | 共用本地来源选择、派生静态图落盘、原预算内最近访问图保留、内存就绪直接呈现；保失效／取消与原动画 | 实现完成：29个返回复用检查、45个租约检查和相关原生UI／布局／详情门通过，固定源Debug零warning；独审通过，不认领整App FPS／全库常驻 |
| D17 网格需求调度审查 | 覆盖全部六类网格及复用分类，从请求、预取、取消、解码与交付定位下一批；沿现owner分阶段，不直接替换框架 | 实现、最近行为门、独审、Debug／Release零警告及六类容器实际操作完成；B3／跨档捷径STOP，整App滚动FPS／CPU／能耗未量化 |

每批列明owned源码/测试，构建和实际播放串行；子代理实现可并行，性能计量不与构建/测试重叠。Debug保现开发入口，Release无新增探针；真实媒体只读，用户偏好按精确任务值回收。保留低复杂度可靠局部收益，整体比例未知如实注明；性能或功能回归先修，不能机械追逐数值。阶段结果在本表更新，历史记录不覆盖新事实。

D4：实际WK自定义scheme的7臂资格中，恒假supports候选仍发原import请求；无恢复臂2请求/2响应、DCL1573ms，未跳过1500ms等待。有限最终字体/样式/层序相同不代表有收益；原FAIL及原数保留，未写产品，不外推真实HTTPS。D5新trace缺纹理内容版本/消费者证据；source capture含UV/颜色/PMA/tint/尺寸转换且建立publication，copy还承载固定pair/history/terminal preservation。未证明可省，不改GPU。D6暖调度无大Runnable积压；不升QoS/并发数，不重开旧缓存或另造任务平台。

D9：冻结`8de80eb6e2`后仅VideoLibrary索引链扩展。真实SQLite与产品Manager／完整导入producer的18种mode、65项检查通过。独审发现并闭合该no-op意图遗漏；最终Debug／Release均构建成功且零警告，前驱6条隔离警告已按MainActor owner修正。测试隔离文件可读性／提示UI／播放等叶端，未运行完整App导入选择和播放UI，不声称所有故障或整App性能比例；收益是启动期普通save不再等待初始SQLite读，且不丢用户动作／未见旧库。无新增timer或Release探针，稳态writer不变。

D11：A／B同二进制、同内联页、同正常desktop+1配置，B仅增加Space／activation时的窗口reassert；真实手动切换的4／6事件分别对应RAF停顿567／537／549／551ms与545／547／548／538／538／521ms。A没有reassert也会停约半秒，A／B原生heartbeat最大仅15.1／45.4ms；没有对应半秒主线程停顿。该单轮数据不支持通过删窗口重申解决此类停顿，B低8.5ms也不能称优化收益。三臂均单document、序列连续、零丢包；C经原WebDaemon v2可见确认→finalize→output-activity ACK后观察，5个匹配request的IPC Space事件对应RAF556／567／632／557／568ms；IPC接收时刻不是原生callback时刻，原summary／unified未采到该事件不等于未发生。C兼容脚本覆写hidden，不能以hidden=false证明原生WebKit未遮挡；activation高一档证据也不能当作finalize后的持续level。仅此macOS／WebKit、这一张无网络页、每臂一轮，未证明内部根因、作者样式／音频／主App最小化或所有设备；不做C减A的宿主开销估计。早期快捷键未引发真实Space的B01／C01仅保无切换数据，不算空间验证；有效人工轮无新增产品探针。此阶段不改进程隔离／窗口行为或增加运行时workaround。

D9–D11最终raw、工具与源身份、失败命令／收据、修正前后聚合及独审统一提取至忽略的`.artifacts/scene-evidence/runs/apple-silicon-storage-release-web-space-20261021/`（约1.6MiB，14天）。权限失败、未finalize的1.22GB ATRC不作归因数据；保原FAIL、三文件size／SHA及两份小metadata原文，其大载荷按已核范围清理，不宣称绝无可恢复数据。有效替代并非原trace完整等价副本。测试进程已退出；本轮临时App／DerivedData／样本／HOME／模块缓存按精确归属清理，不清理他人目录。

只有新证据证明同完整资源／用途／版本或同次不可变输入的昂贵重复，且不需第二owner、长期缓存、安全豁免或作者效果变化，才实施等价复用并验证反例与独立样本；保原取消／join／退役，冷暖对照按低复杂度总体正向取舍，不机械用旧百分比淘汰。若主链是必要编译／解码、只剩已STOP或数据无法定位可删工作，保留新证据并停止产品修改，不扩为全样本或后台预编译。每个实际产品小批完成最近门、隔离运行和独立审查后再提交；原并行pbxproj不入批。

D15实施细则（全模块网格）：目标是大量卡片在网络已热与首次加载时均减少滚动竞争，保原卡片样式、排序、详情、播放状态、键盘／点击／框选／滚动恢复。沿现有NSScrollView／NSCollectionView唯一UI投影实施：共享scroll view只持有自身手势／惯性滚动态，状态转变时通知可见卡片停止／恢复hover；普通滚动不逐帧遍历全库，不禁用点击／hit-test，不接管数据／播放／选择owner。原生live-scroll通知覆盖触控板及滚动条，手势／惯性结束与普通无phase滚轮统一120ms短收口，后续phase撤销旧收口以免指尖→惯性之间重启GIF，程序滚动／框选autoscroll不触发门；离窗／取消清理状态，无常驻timer、Release探针或全局鼠标开关。停止时仅按当前可见坐标恢复，不复活旧卡片／GIF。

D15按顺序落地：①六个网格共享滚动态策略、Steam tracking area只创建一次；②Steam浏览／下载与在线库浏览／下载用register＋makeItem复用，沿原prepareForReuse取消／ID准入，旧异步回包不得污染新卡；③各卡片几何、文字／字体／渐隐／symbol各按其实际输入变化更新，纯位置变化保必要anchor／frame，不把内容变化误当尺寸未变而跳过；④只修已定位的缩略图呈现缺口：在线图后台ImageIO下采样并立即解码，缓存键包含像素用途与原有来源身份、预算不增加；Video热路径保原缩略图失效验证，不让旧缓存复活。共享ThumbnailCache已有single-flight、取消、字节预算与Steam显式RGBA解码保留，不重写为第二缓存框架。收益不足或风险升高时收窄相应片段，禁止靠删除作者效果、降低壁纸精度、清有效缓存或放宽校验提速。

D15验收：最近门覆盖原生滚动始末／连续滚轮／离窗重入、复用后旧回包、热图首帧、相同尺寸改文字／状态／选择／外观、缩放与删除递补、键盘／框选／播放bar、GIF进出及详情复用；外部工具做有身份的冷／热代表滚动对照，鼠标在网格内／外及运行负载明确，观察主线程／图层与卡顿，不能凭平均CPU或一段动画报FPS收益。每阶段由独立子代理只读审查；最终固定源Debug构建和隔离代表窗口，Release不加诊断，启动最新完整App供用户测试。仅拥有Shared/UI相关工具、各模块网格／卡片、最近测试及此计划／设计登记／文档预算，其他并行改动不入批；本轮暂不提交、不推送，运行窗口另行协调。

D15已落地：六类网格共用每实例滚动态；Steam浏览／订阅／下载及在线浏览／下载补register＋makeItem，保原外观与交互owner。卡片按真实几何／文字／状态输入跳过重复布局，Steam card与icon tracking area各只建一次；同尺寸换heart／play等图标保symbol配置。复用补request／animation代次，拒绝A→B→A旧成功／失败及旧完成动画。在线ImageIO按用途像素档后台下采样并立即解码，保双轴／方向／透明度、原raw cache身份及预算；非ImageIO fallback保旧NSImage路径，不称全部格式已立即解码。Video原缓存失效检查未旁路。真实NSCollectionView证明visibleRect可超bounds，悬停准入最终用bounds∩visibleRect并保active／visible窗口条件。

D15验证：scroll 8例／54断言、真实Online卡片10例／203断言、真实图像20断言通过；13个既有UI模块19用例串行通过，含Steam实际卡片GIF、新卡正控、同尺寸symbol、布局重排、播放发布、键盘与点击、工具栏／删除选择状态、缓存lease等各自门的范围，合计38功能用例；两处注册表与设计编排相关门106例通过。裸CLI激活／clip前置失败如实保留，最终用隔离.app／LaunchServices、真实AppKit事件分发建立正反控，不伪造active或省去断言。两轮独立静态审查及测试／证据复核修正了symbol、失活窗口、双轴像素与测试坐标遗漏。全仓测试断言棘轮的非本批两条差异由并行owner在ef8f41cf修正后已通过；本批0新增源码形状断言，不修改其代码／基线。

D15局部收益：冻结2b7803b52基线与仅D15候选、相同-O／WMO／harness，离窗实际Steam卡隔离active差异，5对BC／CB交替、各7×1000相同输入布局；35点中位为12.353250→0.068667 ms／1000次（约99.44%局部工作下降），所查bar／card／image几何一致，tracking identity由每轮重建变为保留。不是FPS、整AppCPU、能耗或冷暖网络收益；取证harness两臂有相同3条既有stub／并发warning，不能把App零warning扩称所有工具。图像门验证1920×1080在512档为512×288及更小实际像素成本，不据此虚报全AppRAM。

视频初始布局及Steam已下载418项的较低滚动位置作有限可见检查；用户开始操作后停止抢占界面，不称完成所有模块手工矩阵、网络冷暖App A/B、真实显示器迁移或无卡顿证明。用户反馈较之前略有改善并要求收尾；同一Release已正常退出测试位置、深严格验签后替换`/Applications/MyWallpaperX.app`并由该路径重新启动，核对exe hash一致，旧版本备份在启动确认后删除，不改用户数据；临时staged重复App已删除。必要原文／失败／冻结差异／截图与独审收据有界保留于`.artifacts/scene-evidence/runs/apple-silicon-grid-scroll-d15-20261021/`（14天，AppKit证据，不是Scene兼容样本验收），已停止的隔离源码／DerivedData／HOME／取证binary提取后精确清理。本轮不提交、不推送。

D16实施细则（缩略图返回复用）：目标是滚回已浏览卡片时直接呈现可用图片，Steam订阅及在线浏览优先本地已下载预览，缺失／损坏才远程降级。沿现有ThumbnailCache、OnlineImageThumbnailCache和PreviewState唯一owner实施：①卡片／邻近预取共用本地来源选择，不扫样本目录，保原记录与文件版本身份；②Steam把按用途尺寸生成的静态PNG与原动画字节分键落盘，磁盘静态命中不再扫描GIF帧，悬停仍按需取原动画；③既有解码预算内以有界LRU保最近访问图、内存压力回收，不加第二缓存／常驻timer；④ready内存同步回显，不在成功回显前先发loading通知；Video保已生成缩略图存在性／失效校验。实际网格像素档决定Steam静态尺寸，详情保原800默认，放大换档可重读源而不降作者动画／壁纸效果。请求代次、最后消费者取消、显式清理／重试拒旧producer回写保持有效。冷盘／暖盘／暖内存、同ID本地替换、损坏本地→网络、无预览视频、GIF悬停、清理在途和A→B→A用最近行为门验证；分别统计网络loader／原图decoder／派生盘命中，不靠隐藏文案认领收益。

D16结果：订阅与在线浏览卡片、邻近预取共用ready记录的本地preview，缺失／损坏才沿原候选回退；下载队列封面也消费同一静态加载器。静态PNG按用途档分键，原动画字节独立保留，显式详情重试同步失效三档；小图按方向后的双轴计算并保原800最长边上限，因此极宽／长图超旧上限的清晰度限制仍存在。现有解码图owner在原128／64／50 MiB等各自预算内使用有界LRU和压力事件，不添常驻timer；共享派生磁盘图后台立即解码，Video原资产存在性校验未旁路。在线库可见／预取从联网前携带发布代次，清缓存后旧任务不能落盘或重新填内存。

8模块20功能用例通过，另详情2例、导航1例与调度1例补门通过。真实ImageIO、磁盘、HTTP的return fixture29项检查证明：12次内存淘汰后返回均读派生静态图，网络loader与原GIF解码各仍仅1次；丢失派生图由raw重建无需联网；原GIF完整多帧、方图／竖图／全景／旋转及1x／2x旧上限、在线旧epoch拒绝和新epoch正控通过（直接调用生产actor模拟迟到，不是实际卡片／Service延迟HTTP全链）。真实HTTP仅损坏／删除本地的两次回退各1请求，本地有效卡片与预取0请求；这不是实网Steam或整App负载测量。实际row／PreviewState生命周期另51检查通过，下载任务投影与两路由unit补门通过。lease45检查含第二raw暂存时失效／目录清理，两文件及内存均不复活、既有消费者正常完成。原生真实卡片／GIF／网格／详情覆盖各自门范围；旋转用例仅核尺寸与既有双轴门，不代画面方向验收；压力门调用显式释放而非真实系统事件。未实测OS内存压力触发、全量线上长会话、完整手工矩阵、FPS或整AppRAM／能耗。保留pinned共享请求既有完成语义，显式刷新不承诺强制重新联网。

D16失败边界如实保留：最初像素断言误要求全景短轴超出原800cap，修为不超旧解码量的正反控；原生clip／active一次末态未通过，补状态原文后定点及完整门均通过，未据此更改产品hover策略或宣称不存在外部焦点干扰。额外详情门发现旧fixture重复声明正常Release已有openProperties，改为外部面板叶stub，保真实详情实现。源码/测试先期编译接线错误修正后均重验；不把这些失败藏成产品速度收益。独立审查未发现新增产品阻断项，指出的双轴、在线代次、双文件门、两处路由和锁内删除合同口径已修正；code-health／设计／依赖／测试断言／产物／残留／文档路由静态门通过；全量文档健康仅并行material-video-assets未收口的预算／导航receipt报错，本批两篇范围通过，不改它。必要冻结身份、日志、失败及独审收据提取到`.artifacts/scene-evidence/runs/apple-silicon-thumbnail-return-d16-20261021/`（14天；目录numeric16仅UI工具槽，不是工坊ID／Scene验收），停止的隔离源码／DerivedData／HOME／重试输出精确清理，不替换用户正在运行的D15安装版，不提交、不推送。
沿已归档输入hash复核复用原功能／独审与Debug证据，再从该提交导出冻结树构建普通arm64 Release：3169个输入hash未变、0产品编译warning／error，Developer ID嵌套签名严格验证通过。安装至`/Applications/MyWallpaperX.app`并启动，主窗口及视频网格可见，保留实例供用户测试；没有用这次单窗启动替代完整手工滚动矩阵。可执行文件SHA256为`3e5c6035a829320c45292f7cb1c80e3487824b276dfc22a4b9763221ed365f50`。最终构建日志、输入身份、安装核对及一张界面图保留于忽略的`.artifacts/scene-evidence/runs/apple-silicon-grid-release-handoff-20261021/`，14天；numeric17仅UI工具槽，不是工坊ID／Scene验收。停止使用的冻结源码、DerivedData和旧安装备份清理；安装实例保留。未完成的整App FPS、实际系统压力与延迟HTTP全链仍不认领。

### D17：全模块网格／缩略图调度审查与下一批顺序

本次只读产品源码，覆盖Video（视频／收藏／最近／标签）、SIL图片、Steam浏览（主浏览／订阅／作者）、Steam已下载、Pixabay在线和下载共六类容器。D15/D16已改善滚动态工作与重复返回，但没有证明全部卡顿已消除。现有“按用途下采样 → 已解码内存图 → 磁盘静态派生图 → 原始动画独立保存 → 同键合并请求”应保留；优先补需求调度，不扩大所有图片常驻量、不后台全库预热、不删来源失效校验。以下为当前源码可证的工作路径／缺口，尚未归因其实际帧耗时。

| 顺序／范围 | 当前事实与用户可见风险 | 沿原owner的最小改法／边界 |
|---|---|---|
| A1 Video预取 | `AppKitLibraryGridView.scheduleViewportPrefetch`每次滚动重置60ms尾随任务，同时原生`NSCollectionViewPrefetching`也调用同一provider；`AppKitLibraryGridSupport.cancelPrefetch`为空操作。快速连续滚动可推迟手动预取，过期任务仍排队；去重不能代替撤销／提优先级 | 网格只维护一份当前需求集，原生回调与视口更新归并；可见项优先，近邻低优先；撤销不再需要的排队consumer。取消不得终止仍有可见consumer的共享producer，保资产路径验证和清缓存语义 |
| A2 Steam与在线预取范围 | `SteamWorkshopService+BrowseHydration.prioritizeVisibleBrowserItemIDs`取前后各12再`prefix(24)`；位于列表中部、12项可见时，可能只覆盖前12与可见12，前进方向零预热。Pixabay Service的前6／后12再取18也有前端截断偏置。Steam每次另建全列表ID索引，grid去重只看可见ID，不含像素档 | 先可见，再按距离与滚动方向选择近邻；有界小窗口、合并同次事件，列表变化才重建索引，ID／来源版本／用途像素档共同决定需求。方向改变撤销旧近邻；不按全库大小预热 |
| A3 在线任务寿命／解码 | `OnlineImageThumbnailPipeline.loadData`合并网络Task，但无consumer租约／可见提优先级；取消卡片Task不撤销共享下载。`cachedImage`／`storeAndDecode`在actor可重入处各开detached解码，同键未统一解码在途；网络有界并不等于磁盘解码有界。`AppKitPixabayBrowserItem`在联网＋解码后才再次检查取消 | 原pipeline内补同键解码合并、少量有界解码槽与消费者寿命；联网返回后、解码前检查需求；共享请求支持预取→可见提升。来源代次跨整个请求保留，旧epoch不得在清缓存后重新落盘／填内存。先比较1／2槽，不按CPU核数扩大并发 |
| B1 慢生成挡住暖图 | `ThumbnailCache`串行utility队列同时处理磁盘读与loader；`AppKitPixabayDownloadsItem.generateThumbnail`在其中信号量等待异步AV取帧。一次慢生成可能阻塞后续已存在的静态图读取；此处尚未复现永久等待 | 在同一cache owner内分开短磁盘读／解码与重生成的等待，使用AV异步完成与明确取消结算，仍有界。Video库既有两槽生成路径的V1 STOP不因另一个owner的风险自动重开；不改作者取帧容差或质量 |
| B2 首次交付与磁盘维护 | `ThumbnailCache.finishImageRequest`原子发布raw／still后先执行磁盘trim，再投主队列完成；暖图返回还可能经过多次队列切换。图片库、Steam已下载、Pixabay下载尚无相邻行的已解码预热 | 先验证可见完成是否能早于非关键trim，维护合并／延后，不引入每图timer。raw／still须维持可见一致性，不能因提前交付使紧随的GIF hover重复联网。缺少预取的三类网格只补一小段近邻，与当前可见需求共用队列／租约 |
| B3 主线程来源验证 | Steam来源key及在线下载key在卡片配置时读取文件属性，Steam多个调用点可能重复stat；Video内存命中前仍须后台确认派生路径有效。SIL已具备内存同步快路，miss仍有额外调度 | 先量实际主线程I/O，再由既有库owner提供不可变来源版本／指纹；本次加载仍保读前后后台一致性校验、删除／替换和clear代次。不仅用路径代替版本，不为内存快路绕过安全与外部文件变化 |
| C 呈现细节 | 不同模块像素档／固定尺寸不同；选择或元数据reload可能重新配置图片；部分卡片开始请求立即显示加载文案。增加RAM不能解决排队和失效重复 | 在同一作品且同来源版本时，允许已就绪的较小档先显示、后台升级目标档；无关条目绝不沿用旧图。只变选择／bar／文字时不重发相同图片需求。消除阻塞后再评估约80–120ms延迟显示加载提示，长期加载／失败仍明确呈现；此时间仅实验候选 |

行业对照：Apple的[Collection View预取协议](https://developer.apple.com/documentation/appkit/nscollectionviewprefetching)同时提供开始与取消入口；[图像最佳实践WWDC材料](https://devstreaming-cdn.apple.com/videos/wwdc/2018/219mybpx95zm9x/219/219_image_and_graphics_best_practices.pdf)说明按显示像素下采样、将解码移出滚动关键路径并复用已解码结果。[Nuke预取器](https://github.com/kean/Nuke/blob/b534d6994da1f34e600fc91d21a14f5efad82745/Sources/Nuke/Prefetching/ImagePrefetcher.swift)展示了低优先级有界预取、取消／暂停、内存与磁盘不同目的地和任务优先级更新；它是架构参考，不证明换库即可修复本项目。当前GIF静态首帧、源指纹、清缓存、local-first与AppKit生命周期均有产品语义，优先在原owner独立补齐这些缺口，不直接移植代码或整体替换图片框架。

Apple silicon执行约束：按[高效CPU调度](https://developer.apple.com/documentation/xcode/scheduling-cpu-work-efficiently)与[Apple silicon调优](https://developer.apple.com/documentation/apple-silicon/tuning-your-code-s-performance-for-apple-silicon)使用GCD／Swift并发表达紧迫性，让系统安排P／E核；不绑核、不自建按核心数固定扩张的线程池。可见关键读／解码与低优先预取、编码／trim分级，先取消无用工作再调并发；避免低优先producer挡住已可见consumer。内存预算先保持D16现值，后用实际解码字节、可见pin与动画持有核对跨owner总量；不把统一内存当免费纹理／图片常驻空间。现有可见路径2秒探测仍承担外部文件变化反馈，未测得开销前不机械删除；玻璃、圆角、阴影的GPU成本未归因，不用删样式换性能。公开资料核对日期2026-10-21。

实施时按A（先Video／Steam预取纠偏及在线解码寿命）→B（关键路径与缺失近邻）→C分小批，先在[AppKit合同](../architecture/appkit-migration.md)补请求寿命、优先级、失败／退出与旧路径退役，再注册最近行为门。共享的是需求语义，不另建第二cache／全局任务平台；低收益项可单独STOP，不能为走完表格扩大修改。每批验证真实生产owner：两个consumer仅撤一个、预取升可见、反向快滚／整屏跳转、同ID换档、清缓存迟到、替换／删除源、HTTP坏图／失败重试、GIF hover／离屏退役和选择／播放bar刷新；取消与失效反例先行，Debug构建及独立审查后，再用普通签名Release真实操作六类网格。

测量按相同数据／缓存／窗口／缩放与刷新率，分别看冷入、暖回、快速反向及长滚；用外部工具区分主线程帧耗时／hitch、磁盘读取、解码数量、排队时间、CPU／footprint与后台壁纸GPU负载。数据只用必要测试或外采，不给Release加常驻诊断；设备被用户或并行样本重负载占用时保留行为结果，性能轮标污染而非推定回归。验收是同身份有效图片更早就绪、陈旧工作减少，且内存有界、清缓存／动画／列表顺序／错误反馈不退步；不能只以加载提示变少宣称滑动提速。用户已授权实施A／B／C；按AppKit合同在既有owner内推进。

#### D17实施与验收（2026-10-22）

六类容器（Video、SIL、Steam浏览／订阅、Steam下载、Online浏览、Online下载）各持一份有界视口近邻，前向／反向最近优先，近邻进入可见时保留原租约，隐藏／换窗／最小化撤销未完成需求；公开`NSWindow.isVisible` KVO覆盖真实orderOut/in，不增轮询。
- Shared原cache分短读／解码2槽、媒体生成1槽、异步来源4槽（prefetch入场最多2）；已运行工作不可抢占，槽覆盖结果交接／发布，配额不随途中优先级变化退还。Online原HTTP owner逐consumer结算、末消费者取消底层任务，原cache新增同URL／档／代／数据的2槽解码单飞，ready/raw在唯一完成点先发布、后唤醒，非关键trim移出完成路径；预算不扩大。
- SIL补有界近邻；Online下载用原0.5s、520×300及原生NSImage构造的可取消AV异步桥替代等待；扫描键仅作ready提示，miss后台核当前键、取帧前后验来源，不把替换文件写入旧键。下载预取区分实际键、成功淘汰与失败终态，失败不随滚动热重试。各卡片短暖读延后100ms加载提示，失败仍及时可见；隐藏重配置不启动，显示只加载最新身份。
- 机制对照：人为占住慢生成时，旧cache暖图等254.74ms仍未返回；最终75项门中的新cache在释放慢生成前6.02ms返回。只证明解除队头阻塞，不是普通App平均加载时间、FPS、功耗或RAM比例。
- 最近门覆盖21个模块：Shared需求75／lease45／返回42项、Video17／Steam调度8、SIL37、窗口15及退化mutant精确2失败、Online真实HTTP／解码、来源替换6项、卡片12用例、自生成MP4真实AV取帧、GIF hover／黑首帧、列表布局／选择／播放bar、投影与文件探测。独审发现的生成图片积压、入场配额退还、隐藏恢复／configure、旧扫描键发布及测试假阳性均已关闭；不把受控叶fixture当完整线上行为。
- 两配置初轮构建成功，发现两类新actor声明警告；纯值priority改`nonisolated`、Loader明确`@MainActor`，相关门按产品Swift5／默认MainActor／六项并发推断及warnings-as-errors复验通过。最终Debug／Release均成功且零警告；CI等价inside-out签名、25个Mach-O含arm64（18个自有仅arm64）、权限与版本检查通过，实际Release无所选开发flag命中，未公证／发布。
- 普通签名Release 2.11.0（283）主binary `040490e23c27391de19a0ac07dfa07bc1f2728e148596865e8200eb5a1b1a1b4` 已替换并启动`/Applications/MyWallpaperX.app`。实际只读操作1032视频／90图片／419 Steam下载／11 Online下载，以及工坊／订阅／Pixabay浏览；滚动／反向／缩放／窗口恢复所见未见持续加载或新错位。用户开始手动切分类后停止UI控制；不做删除／订阅变更／真实数据清缓存。必要日志／源与App身份／截图登记至`.artifacts/scene-evidence/runs/apple-silicon-grid-demand-d17-20261022/`，保留14天；本轮可重建导出、构建与旧App备份收尾清理。
- B3主线程指纹整体迁移、跨档／同路径配置捷径STOP：现模型没有不可变内容版本，不能绕过外部替换／清缓存验证；不为小收益新增长期版本owner。Steam可选视频兜底保原有界AV owner，仅拒过期结果，不声称底层取帧已取消。未测OS真实内存压力、完整hitch分布／长时能耗，不声称全场景无缺陷。

## 目标、取舍与职责

用户目标是更快设置壁纸、属性准备更短、主窗口响应自然，以及长期播放资源消耗更低。保留独立播放进程、作者原效果、正常错误反馈、资源／路径／预算／生命周期安全校验；不做后台预编译、不增加 Release 常驻诊断、不默认提高 FPS、不降低图像质量、不引入第二缓存／资源总账／时钟／暂停真值。

保留判断按用户最新取舍：低复杂度、因果清楚、必要行为门与实际操作无回归、总体有正向收益的小修改可以保留，不机械要求每项都达到旧专项的某个百分比。安全和数据正确性是硬门；不可把稳定的非目标退步用其他指标平均抵消。正式稳定比例、尾部分布、功耗或全专项完成的声明仍需相应测量。噪声大时记录不确定性，修复测量条件，不抹掉已经证明的机制收益，也不把未测收益写成事实。

异步任务提交必须绑定原 request、generation、revision 与资源租约；晚到结果不得复活旧状态。项目默认 MainActor 隔离，`Task {}`、`nonisolated static` 或“后台队列存在”本身都不能证明耗时工作已离开主线程。

涉及持久化提交、跨进程协议、Activity 生命周期、显示时钟等变化时，实施前补齐所属现役设计的职责／数据流／失败／退出及 design gate；不能用本文的候选概述替代这些设计。局部数组复用、一次调用内值复用、等价算法顺序调整可按现合同直接做小修。

## 证据与这次采集到的数据

区分四类证据：**F** 为当前源码可证的触发／工作量；**H** 为历史冻结实验，注明输入与配置；**R** 为单一行为／真实操作验证；**P** 为可比较的优化产品性能结果。研究阶段的下表仅含 F／H；实施状态与新增验证见下节，不把计算次数当 profiler 测量值。

| 对象 | 本轮可证事实 | 解释边界 |
|---|---|---|
| 本机 | Apple M4、10 核（4P/6E）、16 GiB；macOS 27.0.1 `26A434`；Xcode 27.1 `27A9275` | 只读 `sysctl`、`sw_vers`、`xcodebuild -version`；不是 M1／8 GiB／最低系统验收 |
| 工程 | arm64；当前项目配置最低 macOS 26.0 | 发行实际嵌套二进制的架构、签名仍另验，不由配置推断 |
| Web 输入 | 事件 monitor 加 30 Hz pointer 兜底；被动位置去重分属两条路径 | 名义轮询周期约 33 ms；不是实际 JS 投递量或能耗 |
| Web 频谱 | 常规 128 值在每 endpoint 各格式化一遍；约 30 Hz 投递 | 无背压时理论为 `3,840 × endpoint 数` 次格式化／秒；已有 latest-only 背压 |
| 共享封面 | 带 current artwork 的新 media generation 会提交 Web 转换尝试；成功产物最长边512 px、PNG≤1 MiB | 当前无 Web 消费者时仍会尝试；非法／超限／解码失败会拒绝，成本未测 |
| 网格探针 | Video／SIL 活跃网格每 2 s 查可见路径；已有 300 ms leeway | 每个活跃实例名义 1,800 tick／小时，不代表 1,800 次全库扫描；切模块会退役旧网格 |
| 状态栏 | 每 2 s 在主队列采样并更新图标，菜单关闭也执行 | 是否形成可见工作、CPU 占比与功耗尚未量化 |
| Video 索引 | 250 ms 合并后，主调用者仍等 SQLite 全表替换事务 | WAL、事务、连接复用已经具备；不是“尚未后台队列化” |

源码核对覆盖 App、Web、Video、共享播放、UI 与存储；扫描文件数不是覆盖率或性能结果。

旧链接产物复用五对冷启动中位 `4869→4331 ms` 仅属原优化诊断配置；暖启动无确定收益。上一批合作取消缩短过期工作的占用，函数内 memo 减重复投影，均不能外推本轮新提速。

## Apple 官方指导如何落实

下列来源于公开正文／WWDC，访问日期 2026-10-19；短摘要只作本项目决策依据，不照搬平台不同的样例。

| 编号 | 官方来源 | 对本项目的约束／启发 |
|---|---|---|
| A1 | [Apple silicon 调优](https://developer.apple.com/documentation/apple-silicon/tuning-your-code-s-performance-for-apple-silicon/)；[大小核调度](https://developer.apple.com/news/?id=vk3m204o) | QoS 表达紧迫性；动态分配独立工作；不绑核、不把所有工作升到最高优先级 |
| A2 | [高效 CPU 调度](https://developer.apple.com/documentation/xcode/scheduling-cpu-work-efficiently) | 先省重复工作、复用对象、事件驱动，再考虑线程；不自建无界线程池 |
| A3 | [减少启动耗时](https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time) | 分开冷／暖、进程加载、首窗和内容真正可用；少显示一个 spinner 不算提速 |
| A4 | [提升响应](https://developer.apple.com/documentation/xcode/improving-app-responsiveness) | 绘制／cell 配置不做同步 I/O；主线程只提交 UI 所需状态 |
| A5 | [减少磁盘写入](https://developer.apple.com/documentation/xcode/reducing-disk-writes) | 用 File Activity 找实际写入，合并重复提交；持久化原子性与退出落盘不能牺牲 |
| A6 | [减少 Timer](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html)；[主动闲置／App Nap](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html) | 需求消失就停工；保有明确兼容职责的兜底，不因 timer 存在就删 |
| A7 | [App Activity](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/PrioritizeWorkAtTheAppLevel.html)；[Process QoS](https://developer.apple.com/documentation/foundation/process/qualityofservice) | assertion 随实际工作配对；主 App 前台不证明 renderer／compiler 的调度合适 |
| A8 | [Metal 存储模式](https://developer.apple.com/documentation/metal/choosing-a-resource-storage-mode-for-apple-gpus)；[load/store](https://developer.apple.com/documentation/metal/setting-load-and-store-actions/) | 统一内存仍有带宽与同步成本；先证明后继不消费，再省写回 |
| A9 | [Apple GPU 优化](https://developer.apple.com/videos/play/wwdc2020/10632/) | 检查真实 pass 依赖、读写和寄存器压力；不全局改 half、不关闭 hazard tracking |
| A10 | [CAMetalDisplayLink](https://developer.apple.com/documentation/quartzcore/cametaldisplaylink) | 可用显示同步回调替代不合适的周期驱动；仍保唯一场景时钟和每屏生命周期 |
| A11 | [管线二进制归档](https://developer.apple.com/documentation/metal/metal-binary-archives)；[编译并发](https://developer.apple.com/documentation/metal/mtldevice/shouldmaximizeconcurrentcompilation) | 重用已编译结果；更多编译线程有 CPU／内存代价，不默认开启最大值 |
| A12 | [Metal 4 编译](https://developer.apple.com/documentation/metal/using-the-metal-4-compilation-api) | 可渐进采用；不为 API 新旧全面重写，不预编译未知作者内容 |
| A13 | [GPU working set](https://developer.apple.com/documentation/metal/mtldevice/recommendedmaxworkingsetsize) | recommended 值是性能相关近似，不是 App 独占 RAM 配额 |
| A14 | [Accelerate](https://developer.apple.com/accelerate/)；[vDSP stride](https://developer.apple.com/documentation/accelerate/controlling-vdsp-operations-with-stride) | 已有 FFT/vector 路径继续使用；先省分配与复制，不将小 FFT 搬到 GPU／Neural Engine |
| A15 | [降低内存使用](https://developer.apple.com/documentation/xcode/making-changes-to-reduce-memory-use)；[图像内存讲解](https://developer.apple.com/videos/play/wwdc2018/416/) | 缩略图用 ImageIO 按显示用途下采样；不降低实际壁纸纹理／静帧精度 |
| A16 | [异步视频取图](https://developer.apple.com/documentation/avfoundation/creating-images-from-a-video-asset) | 有界派生任务可异步完成与取消；放宽取帧容差可能改变画面，须单独裁决 |
| A17 | [WKWebView 隔离](https://developer.apple.com/videos/play/wwdc2020/10188/)；[原生媒体暂停](https://developer.apple.com/documentation/webkit/wkwebview/setallmediaplaybacksuspended%28_%3Acompletionhandler%3A%29) | 网页内容本已独立进程；换宿主不是换渲染器，原生媒体暂停不能代替 JS／CSS 暂停 |
| A18 | [Swift 并发执行机制](https://developer.apple.com/videos/play/wwdc2021/10254/) | 不把阻塞等待塞入协作线程池；异步不等于取消／有界／离开 MainActor |
| A19 | [Metal 联合归因](https://developer.apple.com/documentation/xcode/analyzing-the-performance-of-your-metal-app) | 同时看 CPU／GPU／display／thermal，先区别 CPU 等待与 GPU 饱和；外部 Instruments 不要求产品新增周期诊断 |

更底层的 [CPU Optimization Guide](https://developer.apple.com/documentation/apple-silicon/cpu-optimization-guide) 需要开发者登录与额外协议，未读取受限全文。公开文档足够指导当前高层优化，不假称已据芯片内部延迟表调优。

## 候选总览与阶段

P1 优先取得可行动证据；P2 在规模或实际消费出现时推进；P3 只保留取证／备选。优先级不是已确认缺陷等级。以下为跨模块候选，每项仍须先确认当前代码和原 consumer 没有变化。

| 阶段 | 候选 | 最小结果与退出 |
|---|---|---|
| 0：冻结与联合取证 | 主线程 U1/U2；媒体 M1/M2 | 一次有身份的时间线和现有输入／输出基线，不先给全模块打补丁 |
| 2：UI／存储与批量派生 | U1/U2/U3/U5/U7/U8/V1 | 持久化先补失败／退出门，保数据与外部文件变化；大库有实际成本再扩大 |
| 3：播放节奏与暂停／输入 | W1/W2 | 原 owner 内完成状态设计，验证多屏／Space／恢复与下一次操作，再谈能耗 |
| 4：仅在新证据解锁后 | M3/W4 | 找不到实际 consumer／可省成本即停，不重跑旧 STOP 或扩缓存凑收益 |

没有硬编码“必须全改完”。每阶段完成最近门与真实操作后独立子代理审查；高风险项复审修订点。收益递减、两次有区分力实验不支持假设、或为微小收益必须增加明显复杂度时，保留证据并换方向。当前并行任务正在使用的帧／模型 owner 不抢改。

## 本轮执行状态（2026-10-20，冻结结项记录）

下表保存跨模块处置记录；下方候选说明保留研究／改造前基准，不应据旧行号或旧成本再次立题。停止不表示成本为零，保留不表示已经测得全 App／功耗比例；没有实施的项不能称“优化完成”。本轮覆盖已结项，未来只有重开条件成立或用户明确提出下一阶段才推进。

| 项 | 处置与证据／未扩范围 |
|---|---|
| M1 | **保留**。串行FFT复用工作区，84帧×6数组共18,816浮点严格等于基线；五组400次stereo分析均少2,400次分配请求／26,291,200累计请求字节。代价48k常见N4096驻留32KiB，最大128KiB；不声称RSS／能耗下降。 |
| M2 |**保留**。仅Web消费者需求派生PNG，独立Web revision与媒体epoch。真实Music经main→WebDaemon IPC→5监听，标题／PNG加载／进度成立。|
| W1 | **保留**。同surface原生event与30Hz poll共享被动坐标去重；真实方法原版重复RED→候选GREEN，遮挡／按钮／新surface反例通过。保真实hit-test和手势；benchmark的JS交互不作为原生全局monitor证明，本轮未作纯被动原生集成／能耗声明。 |
| W2 | **STOP本轮Activity改造**。暂停、prepared、activation、导航／拓扑与恢复须联合接纳，未测得稳定暂停持assertion的实际能耗；不增加token真值／恢复分支。 |
| W3 | **保留**。同一命令多个endpoint只格式化至多一次，全busy可零次；每endpoint序号／latest-only保持。另修退休／过期endpoint的旧completion继续flush，RED→GREEN且不污染同view新endpoint。单endpoint原本只格式化一次，现多一个短命引用对象，未声称普遍CPU提速。 |
| M3 | **STOP**。现poll≤1s还承担继承stdout子孙不EOF时的取消兜底；拉至remaining可把取消尾延至12s，需额外wake/reader owner，名义少唤醒不足以支持。静态反例，未冒充运行复现。 |
| V1 | **保留现后台有界路径**。已离主、2槽／精确帧／缓存合并；新async取消要job身份与精确generator结算，还跨U1清缓存寿命，无已证成本抵消复杂度。不修改取帧容差／质量。 |
| W4 | **保留已有策略**。一个空预热进程、30s TTL、压力退役已具备；无新真实命中节奏，不调TTL或扩预热。 |
| U1 | **保留稳态窄片，D9已补启动结算**。初始load前仅有版本增量，完整SQLite基线到达后由原Manager合并；失败不覆盖未见旧库。结算后immutable／一飞一最新pending，原SQLite队列／全事务／fallback；reset epoch与同步退出flush。有效fallback含[]优先旧DB，成功后才清；async返回不表示durable ACK。真实SQLite跨进程／读中断／失败／退出及显式导入反例通过。 |
| U2 | **保留旧metadata窄片**。JSON先发布、utility补缺header，generation／id／path及仍缺字段准入；同ID同列数的真实Waterfall／文字刷新、快照在途与reset反例闭合。23项行为与代表窗口通过。同步JSON／stat／save／格式保持，完整异步loader／writer STOP。 |
| U3 | **保留**。SIL single-flight、同viewport/id/path回包；Video/SIL最小化／离窗停原timer，恢复最多一次catch-up。34条真实NSWindow检查＋两probe门通过。orderOut通知不可靠的真实失败保留，普通隐藏保2s timer但零路径I/O／零发布，回显沿原cadence；不称全隐藏零唤醒。 |
| U4 | **保留相同图标复用**。相同GPU显示整数／外观不建NSImage、不赋button；首次／nil／外观反例通过。采样／菜单时序保持，采样迁移无归因不做，不称整机节能比例。 |
| U5 | **STOP本轮缓存迁移**。cell stat现状已核；未证明本地目录成本值得引入视口generation／外部增删校准。保现发现与最终存在性校验，不加常驻watcher。 |
| U6 | **保留**。复用已存在tag投影后排序，箭头结果／tie／搜索／边界与旧全库oracle一致；省无关比较，不加缓存，不外推App百分比。 |
| U7 | **STOP本轮异步cache迁移**。只读资格时23份cache总62,172B，中位2,118B、最大7,737B；不是延迟测量。没有已证等待，不给已修的stale呈现／作者返回再加消费代际或第二缓存；TTL／离线保持。 |
| U8 | **保留**。已合成阶段只筛一次，最终全值相等不发布，但每次清无效选择。真实didSet／merge／账号／失败历史门通过，删除意图同步，不延迟Web清理。 |

### 本轮验收与取舍边界

- 冻结产品输入为`55a13f4ec`（含最新并行提交）＋18份本轮产品文件SHA；最终提交文件逐一匹配。S1单独冻结于`f5d50dc4d`；不同窗口不拼成新旧App提速A/B。
- Debug `-O/WMO`与Release均BUILD SUCCEEDED；25个相关模块串行全通过，代码健康1328份Swift／1000行硬门通过。独立审查发现并修复U2晚到尺寸未通布局，以及snapshot在途的consumer缺口；原失败与修后门均保留。
此处有临时Debug阶段归因，不能当普通Release启动比例。
- Web：CWAV＋自有3-endpoint PCM矩阵两样本A／100；5秒晚注册、8秒子frame导航后频谱继续。真实Music无合成PCM的CWAV与受管理3793879750均A／100；自有5监听页有标题、可加载PNG及递增position。受管理输入首次遗漏publication索引的原F39保留，补齐同代索引仅重定位临时root后通过，未删marker／放宽安全校验。grade不是全兼容或官方parity。
- 三引擎正式owner／IPC由Debug driver驱动，33/33检查通过：六方向切换、main阻塞期间独立播放／实际PCM继续、失败保旧、取消与进程退出；不是Release全场景、物理多屏／Space／sleep验收。
- CUA实际窗口目视核对3种图片比例80×120、160×90、120×80与AX尺寸文案，未见错位。该UI只证明呈现：macOS CFPreferences未采用磁盘预置偏好，不能把临时HOME当完整`.standard`隔离；U1 fallback／重启由独立domain的真实SQLite门验。已仅按本轮路径前缀清除遗留的测试CurrentWallpaper，不猜测恢复未知历史值；真实媒体未改。
- 实际Release按既有CI inside-out Developer ID／hardened／timestamp签名后，25个Mach-O闭包含arm64、18个自有arm64-only、Apple Events／Steam JIT／Sparkle权限通过。原始本地Xcode签名带get-task-allow的拒绝收据保留；最终CI等价重签通过，不修改项目配置。主binary开发flag与指定diagnostic symbols均零命中；未公证、发布或推送。
未覆盖普通Release实际播放、物理多屏／最低设备／30min能耗、所有播放器和W1纯被动原生输入，不能写“全场景无缺陷”。

### 已提交的独立代码批次

| 批次 | 提交 |
|---|---|
| 路线／实施设计先行 | `55a13f4ec` |
| M1 FFT工作区 | `6d9860472` |
| U6 标签导航 | `49a3691ad` |
| U4 状态栏图标 | `7bacdc00f` |
| U8 下载投影 | `136be602f` |
| U3 网格探针 | `a4a0be6ba` |
| U1 索引保存 | `45144b9da` |
| M2／W1／W3 Web输入与媒体投递 | `e5da0385e` |
| U2 旧尺寸补齐与真实consumer | `62b24db57` |

冻结跨模块证据归入忽略的`.artifacts/apple-silicon-optimization-20261020/`。两包合计约19 MiB，均保留14天至2026-11-03；含原失败／配置／源与产物SHA／必要画面。字节及解压SHA核对后，清除本轮导出树、DerivedData、staged App、样本、HOME与无用探针；不保留构建缓存或测试实例。旧STOP重开条件见各项，不把此记录变成另一条活跃队列。

### M1｜P1：FFT 工作缓冲复用

- **F／owner**：[统一频谱分析器](../../MyWallpaperX/Core/Playback/SystemAudioSceneSpectrumAnalyzer.swift) 79 行复用 FFT setup，但 216–217 行每次分配 real／imaginary，输入窗也有临时准备。
- **最小改法／依据**：先用 allocation 计数及既有音频输入确认成本，在同分析器复用串行工作缓冲，仅尺寸变化时调整；不改变窗函数、频带、包络、输出数组所有权。A2/A14；不搬 GPU，不额外启动采集。
- **反例／验收**：T5；左右不对称、换采样率／窗尺寸、静音、停止重启，连续帧不能残留前帧数据；真实音乐对照 Video/Web 柱形与环形，作者样式不变。
- **停止**：缓冲共享引入竞态或保有内存明显抵消收益。局部少分配不称整体能耗完成。

### M2｜P1：按 Web 消费需求生成歌曲封面

- **F／owner**：[SystemMediaService](../../MyWallpaperX/Core/Playback/SystemMedia/SystemMediaService.swift) 390–405 行在新 media generation 且 current artwork 非空时提交 Web 转换尝试；当前订阅仅 needsMedia，无Web消费者 也会尝试。[WebArtwork](../../MyWallpaperX/Core/Playback/SystemMedia/SystemMediaWebArtwork.swift) 已有解码／合法性和512 px／1 MiB限制。
- **最小改法／依据**：原 subscription 区分是否需要 Web artwork；首个 Web 消费者晚到时对当前原图按需生成一次，无 Web 时省转换和额外 revision。转换回包另核当前 Web 需求租约／revision。。
- **反例／验收**：T6 补 converter 计数，无Web消费者 零 Web 转换；Web 晚订阅出当前封面；最后 Web 退出拒绝在途回包，重订阅不接收旧需求结果；换曲 A→B→A、清空、坏图、授权拒绝／恢复。真实 Music 与系统来源均验。
- **停止**：要新增长期缓存或第二媒体采集者。若跨进程需求类型变化，先补原媒体协议的兼容／清空设计。

### W1｜P2：Web 被动鼠标位置共享去重

- **F／owner**：[Monitors](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+InputForwardingMonitors.swift) 22 行起同时用事件和 30 Hz 轮询；[Forwarding](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+InputForwarding.swift) 12 行起两套位置／throttle 状态；轮询先做原生 hit test。
- **取证／最小改法**：计同一 surface 的原生采样和 JS 被动位置投递，先共享已投递位置，减少重复 JS；保按下／拖动／抬起、hover preheat 和兜底。依据 A6；首批不删／降 30 Hz。
- **反例／验收**：现测试缺原生两路径行为门，需补事件 harness，再真实验 Finder、覆盖窗口移动、外部拖入、多屏、Space、monitor 恢复。指针静止但窗口移到其下时仍必须清 hover；不能把坐标去重简单移到 hit test 前。
- **停止**：无法保持命中与手势安全或没有重复投递；不能用“少轮询”替代完整输入语义。

### W2｜P2：稳定暂停时的 Activity token 生命周期

- **F／owner**：[Lifecycle](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+Lifecycle.swift) 11–16、42 行持 userInitiated Activity，pause 243–246 行未释放；停止／surface teardown 才结束。
- **最小改法／依据**：先限定已完成准备、明确暂停且媒体门完成的状态，按既有生命周期配对释放／恢复前重获；保候选装载与激活期。A6/A7，不把“主窗口隐藏”视为壁纸没有需求，outputActivityAllowed=false 不自动等于 JS 已停。
- **反例／验收**：T7/T14，加真实 host token 状态门；暂停中导航、WebContent 重启、恢复连选、激活失败回滚、锁屏／Space；比较暂停 wakes、App Nap 与恢复首呈现。
- **停止**：恢复迟滞或可见输出／媒体退步；不全局禁用或强制启用 App Nap。

### W3｜P2：一次频谱推送只格式化一次共同数值

- **F／owner**：[FrameReply](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+FrameReply.swift) 118–140 行每 endpoint 对同一 128Float 重复格式化，已有每 endpoint 一个在飞和一个 latest pending。
- **最小改法／依据**：命令内惰性生成共同 immutable 数值 body，endpoint 保各自序号／定向包装；全忙时不提前格式化。只做短命值复用，A2，不改精度、不跨帧缓存。
- **反例／验收**：T7 加真实 FrameReply 多 frame／slow endpoint 数值、序号、清零屏障、导航拒收门；不能只发给 audio listener，因为还有公开 `wallpaper-audio-spectrum` 事件消费者。真实音乐长播和 iframe 内容均验。
- **停止**：单 endpoint 纯增成本或没有实际多消费场景；不宣称修复未知长播停顿。

### M3｜P3：歌曲 helper 等待循环的空唤醒

- **F／owner**：[SystemMediaSource](../../MyWallpaperX/Core/Playback/SystemMedia/SystemMediaSource.swift) 272 行起 poll 最多 1 s 返回一次，心跳 deadline 12 s；helper 常规约 2 s 一条。取消已有 terminate／0.5 s KILL 与 pipe EOF。
- **取证／最小改法**：先验证 EOF／取消可靠唤醒且确有空 poll，再用剩余心跳 deadline 等待；不弱化心跳／ACK／预算，不加第二 timer。依据 A6。
- **反例／验收**：T6 的 source 门，补 TERM 忽略、继承管道未关、部分帧、EINTR、cancel-launch 竞态；退出墙钟不得退步。
- **停止**：任何退出边界需复杂补偿或收益不可归因。它不是引擎启动／FPS 优化，不顺带改 Music PID 查询节奏。

### V1｜P2：视频派生图像的有界异步完成与取消

- **F／owner**：[CachePipeline](../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+CachePipeline.swift) 205 行在并发 utility 队列等二槽 semaphore，263–273 行异步取图后同步 wait；已有缓存、同路径合并与 generation。
- **最小改法／依据**：原派生 owner 维持二槽 admission，用 completion／异步取图释放等待线程，并取消不再需要的 generator；保候选时间、400 px 缩略图、4096 px 静帧和 cache key。A16/A18；不放宽静帧零容差、不降精度。
- **反例／验收**：现门缺该 helper 的行为覆盖，补可控 generator 的完成一次／取消／坏媒体／后备时间；删除重导入同路径不得写旧 cache，系统静态壁纸提交身份保持。隔离少量／批量导入比线程、完成时间和取消后写入。
- **停止**：需新建常驻 pipeline/cache 或正常小批量成本退步；不能声称改善稳态 Video FPS。

### W4｜P3 仅测量：已有空预热的净收益

- **F／owner**：[WebDaemonHostAdapter](../../MyWallpaperX/Core/SteamWorkshopWeb/Process/WebDaemonHostAdapter.swift) 151、213 行已有一个空 prepared process、30 s TTL，84–88 行 memory pressure 退出；没有 WebView／媒体需求／作者编译。
- **任务／依据**：记录真实切换节奏中的预热命中、空进程保有时间／内存与冷切换等待，评价现策略净收益；A3/A6。只在已有策略内调参需要另有对照，不默认延长 TTL 或重复补热。
- **反例／验收**：T14 加 TTL 精确边界、hello 前后接管、取消和压力退出；保下一次请求的 UUID 与进程退出闭环。
- **停止**：无新使用数据，维持现状。“加 TTL／压力回收”已实现，不能再作为新优化。

### U1｜P1：Video 索引事务不再让主线程同步等待

- **F／owner**：[Persistence](../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+Persistence.swift) 22–41 行合并 250 ms 后仍在 main 调 save；206–214 行同步 store／失败回退；[IndexStore](../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperIndexStore.swift) 113–128 行 queue.sync 全表 DELETE／INSERT 事务。
- **最小改法／依据**：MainActor 捕获值快照，交原 store 串行队列有序提交；失败回原 fallback，保存 revision 防旧失败覆盖新成功。首批不改增量 SQL、不换数据库。A4/A5；先补持久化提交／退出设计。
- **反例／验收**：T10 只是相邻门，必须新增真实 SQLite harness：A→B、A 迟到失败、reset 排序、不可写 DB、立即退出后重启。真实退出／reset入口使用 `WallpaperManager.flushPersistentState()`（Persistence 460–474行），其有序 flush 不能靠 fire-and-forget 替代。
- **规模／停止**：隔离 1k/10k 值索引看 main 等待、事务写量和交互；若小库成本可忽略，不扩到整套增量存储。数据丢失／旧回包复活是硬失败。

#### U1 实施细则（2026-10-20保存；2026-10-21 D9启动结算扩展）

D9修复此前明确保留的启动整库竞态，覆盖读取期间导入／删库／收藏／标签／个人设置／派生更新及退出。Manager仍是唯一库与用户动作owner，Store原串行队列仍是唯一SQLite执行owner；不增加timer、不禁用操作、不使普通save等待初始read。Store完整读取须终结于SQLITE_DONE，并在同次读取携带原library_initialized（含已初始化空库），不能把读失败当空库。完整可解码fallback（含[]）仍整体权威，坏fallback不冒充空库。

未知基线期间，Manager保存一次性的按规范化路径变化：新增记录作为“不在旧库时的候选”，只将明确编辑的字段覆盖同path旧项；SQLite已有项保稳定ID／未编辑字段。标签记录逐标签增删，保留未见的旧标签；全库标签改名／删除和清预览路径作为有序屏障，避免只修改已见记录。屏障之间同path变化合并为一份，删除保tombstone，删除后重加以较晚动作决定。初始化种子单独保存，仅未初始化库可采用；后台派生回写不把种子变成用户新增。当前快照恢复与真正新导入保各自来源，个人设置导入明确覆盖title／favorite及追加tags；路径命中后修正选择／current／pending引用到稳定ID，不重新发起播放。

未结算时autosave只保存version=1的启动变化到同UserDefaults owner的独立键（不伪装成完整Wallpapers fallback），并沿原Store重试一次读取；只有后续既有save／flush／下次启动触发重试，不循环或加timer。完整基线成功后主线程一次合并并发布，转回原有界writer；成功提交当前完整快照才清增量／fallback，失败则保完整fallback及原增量。加载generation独立撤销迟到回包；reset先撤generation／增量，再按原Store顺序清库并保存fresh状态。退出在原队列同步读完整基线、合并再全事务保存；读取仍失败则保旧DB并持久化变化，供下次恢复，不写半库。

recent在未知基线时不得按临时库裁剪；完整结算后再归一化。损坏或未知版本增量保留原始字节到一个有界隔离键并明确提示，不能解释为空动作或清空旧DB；可恢复完整DB与本次新动作，不承诺恢复不可解码的历史动作。格式仅承担尚未完成的启动恢复，不是长期第二索引；无未结算变化时不写空journal。最近门必须使用真实SQLite／产品合并方法，覆盖A+B、删后重加、同path字段与稳定引用、空库／种子、标签屏障、recent、读中断／失败重启、无主callback的退出及reset；保原有界writer／fallback回归。不据此宣称所有存储故障或性能验收。

稳态保存保留U1原合同：主线程捕获不可变快照与revision／reset epoch，至多一个在飞及一个最新pending，原utility串行队列执行原全表事务／WAL；结果只更新同epoch／当前revision的fallback，旧失败不覆盖新成功，旧成功不清新fallback。退出同步flush排在已有事务之后，不依赖主callback；reset撤pending并沿原队列reset→save。原SQLite事务回滚、有界合并、fallback含空库、旧回包和跨进程重启门继续保留。此前只保留稳态优化的阶段已结束，启动变化按上方D9合同结算，不再沿未结算临时数组全量保存。

### U2｜P1：SIL 首次装载和保存都沿唯一快照 owner

- **F／owner**：[DetailHost](../../MyWallpaperX/Shell/AppKitDetailHostViewController.swift) 23–26、89 行初始化即访问 SILService；[SILService](../../MyWallpaperX/Modules/StaticImageLibrary/Core/SILService.swift) 117–160 行同步 JSON／旧图片 metadata，177–191 行全路径 stat 和缺失后保存。后台补尺寸 save 闭包仍读 live wallpapers。
- **最小改法／依据**：现 JSON 格式不变，后台读取／补 metadata／检查后回 MainActor 以 load generation 加库状态 revision 提交，导入／删除／reset 均改变后者，晚到装载不得覆盖新修改；保存捕获 immutable 快照，由单个串行 writer 合并，reset／退出 flush 进入同一有序提交边界。先消除非图片首窗的同步 I/O；只延迟 singleton 订阅不足以解决首次打开图片库。A3/A4/A5。
- **反例／验收**：T10 外补真实装载／writer 门；旧缺尺寸库、装载中导入／删除／reset、慢卷／离线卷、保存失败／退出。异步不能把暂不可达文件错误视为用户删除；保原缺失提示与合法恢复语义，任何改变须明确设计。
- **规模／停止**：齐全／旧格式各 1k/10k 元数据，媒体用自有小 fixture／隔离副本；分别量首窗和首次进图片库。无实际等待时不迁移数据库或引入新缓存。

#### U2 实施边界（2026-10-20）

先资格测量现有 JSON／旧尺寸补全／路径检查的成本，再决定保存与首次装载分别是否值得异步化。异步 writer 若实施，捕获原格式的不可变值，使用一个串行提交 owner、有界最新 pending 与 reset epoch，必须把真实 App 退出和库 reset 接入有序 flush／remove；后台闭包不得读取 live wallpapers。首次装载不能仅因期间有用户修改就整份拒绝，也不能直接覆盖当前库：须合并期间的增删改，保个人设置导入按路径合并及标签语义；旧 metadata 只可补当前同 ID／path 的未修改字段。该合并复杂度超出已证等待收益则停止装载迁移，保留简单保存收益即可。缺失、权限／离线不可达须分开，不能为优化扩大删库范围。不借此变更 JSON 格式、SQLite 化或另造持久缓存。

U2本轮资格后只推进局部旧 metadata 补齐：JSON读取／解码与库发布保持原顺序，缺尺寸项捕获不可变(id,path,原尺寸)值后在utility读header，主线程只补同id/path且目标字段仍缺失的值，保留期间标题／标签／lastUsed等用户修改。一次准备generation在load/reset撤销；失败不删记录、不覆盖已有尺寸，回包后沿原save同步保存，普通save格式／退出语义不变。首次完整元数据库不建后台任务；该片不引入异步完整loader、writer、合并delta或新数据库，也不把资格中约709ms外推真实首窗收益。需要等全量后台metadata才能显示网格的方案禁止。

### U3｜P2：可见路径探针停启与 SIL single-flight

- **历史F（2026-10-20）**：旧 `AppKitLibraryGridView.swift` 885行、`SILGridContainerView.swift` 444行当时每2s后台查可见项，Video有在飞门、SIL缺；未按窗口可见性停表，离场释放。旧owner已退役；[当前统一网格](../../MyWallpaperX/Shell/WallpaperLibraryGridController.swift)须按现链重核，不据旧文件续做。
- **最小改法／依据**：SIL 补同 owner 在飞和完成身份复核；真正离窗／最小化时停现 timer，重新可见即时探测。全遮挡是否停先验证通知可靠性，不把桌面 renderer 也一并停掉。A6；不新建全库 watcher。
- **反例／验收**：T11 目前偏 Video，补 SIL、在飞离窗再回、同 ID 换路径、排序、外部删除／恢复。正常／慢卷观察 10 min 可见与最小化的批次数及叠加。
- **停止**：恢复反馈退步或只能靠新全局观察平台实现；2 s 是活跃检测周期，不能直接设长周期掩盖问题。

### U4｜P2：状态栏先省相同图标，再测采样体

- **F／owner**：[StatusBarController](../../MyWallpaperX/App/StatusBarController.swift) 56 行每 2 s 主队列 refresh／update；75–97 行同百分比仍新建图标；[SystemMonitor](../../MyWallpaperX/Core/System/SystemMonitor.swift) 66 行起采 CPU／VM／网卡／GPU registry。SMC 温度已不在高频路径。
- **最小改法／依据**：先按已显示百分比及外观状态省重复绘制；采样本体若有成本，再由原唯一串行采样 owner 离主采集、主线程发布。菜单打开仍完整更新；A2/A4/A6。
- **反例／验收**：需轻量采样／图标投影门；nil GPU、暗亮模式、网络差分首样、菜单打开的即时新鲜度、并发重入。固定播放 30 min 观察采样 CPU／wakeups／重绘次数。
- **停止**：只减少代码调用却没有实际绘制／开销，或后台采样引入差分竞态。先不做第二套“菜单／图标”监控器。

### U5｜P2：Online cell 只消费下载状态，不同步探盘

- **F／owner**：[OLBrowserGrid](../../MyWallpaperX/Modules/Pixabay/UI/AppKitPixabayBrowserGridView.swift) 246、267–272 行 cell 配置／刷新调用 isItemDownloaded，对未知 ID fileExists，命中还会发布集合变化。已有进度 throttle 与定向刷新。
- **最小改法／依据**：cell 消费服务现有 downloadedIDs；初次／页面进入／显式刷新，以及视口中新出现的未知ID，都由原服务合并后台校准，同一视口不反复探盘、不增加常驻watcher。提交绑定 generation 和下载集合本地修改 revision，扫描期间下载／删除事件须合并或重扫，旧集合不得覆盖新修改；真实点击播放仍最终核文件。A4，不能因缓存优化删存在性校验。
- **反例／验收**：T10 相邻门外补目录校准；页面保持打开，外部添加／删除后滚入、滚出再滚回；扫描A在飞时下载B完成，A不得移除B；另验搜索换代和旧点击。滚动未下载卡片时 main File Activity 不再反复 stat。
- **停止**：目录很小且成本无贡献，不增加持续 watcher；不让外部文件永远无法被发现。

### U6｜P2／极小：SIL 标签键盘导航先筛选再排序

- **F／owner**：[SILService](../../MyWallpaperX/Modules/StaticImageLibrary/Core/SILService.swift) 410 行方向键先 sortedWallpapers 再筛 tag；329 行已有 `sortedWallpapers(forSILTag:)`，网格已用。N 大、标签 K 小时做 N log N 而非 K log K。
- **最小改法／依据**：复用已有标签投影，不添缓存／导航 owner；A2。先验证 comparator 对并列项稳定，过滤与排序可交换的条件成立，再改一处调用。
- **反例／验收**：T10 加真实方向键输出，tag／search、同名／同排序值、首尾、跨列、无选中。不要顺手改删除后邻选的 `resolveNextSelectionID`。
- **停止**：排序不稳定导致相对顺序不同；先修或限定等价性，不能仅据复杂度公式认领 App 提速。

### U7｜P2：Steam 详情缓存 I/O 与呈现隔离

- **F／owner**：[DetailPresentation](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+ItemDetailPresentation.swift) 46 行冷详情读 cache；[DownloadSelection](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+DownloadSelection.swift) 177 行读 metadata/cache；[LibraryRecords](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+LibraryRecords.swift) 162 行同步 Data／JSON；网络完成后也同步保存。
- **最小改法／依据**：复用单一 cache，内存已知详情先显示，后台读写以 item／消费方／generation 提交；TTL、过期后台补全、离线展示、作者来源沿原常量和合同，不在此重设。A4/A5；nonisolated static 不等于异步。
- **反例／验收**：T12 的隔离 HOME 门补 A→B→A、关闭、下载／浏览详情互换、坏缓存／过期／网络失败保旧值；快速开 100 项时区分磁盘读与网络等待。
- **停止**：小 JSON 本已很快，或要增加第二长期缓存。已经修好的 stale 展示／作者返回不能回退为前台 loading。

### U8｜P3：Steam 下载列表一次提交只派生一次

- **F／owner**：[Service](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService.swift) 548 行合成 failed intents，随后 [DownloadFiltering](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+DownloadFiltering.swift) 12 行再次合成；didSet 有一次重入，displayed 数组相等未抑制发布。progress 已独立，失败历史最多 100。
- **最小改法／依据**：同 owner 内“已合成记录 → 筛选排序”私有阶段复用，最终相等不发布；必要时只合并同一 main turn 的派生。A2/A4，不延迟 downloads 删除意图本身，Web store 清理依赖它。
- **反例／验收**：T13；账号切换、失败重试、ready 不被旧失败覆盖、清历史、过滤／排序／搜索和选择消失。1k/10k 自有记录观察合成／排序次数与可见响应。
- **停止**：正常规模成本很低或抑制发布吞掉实际状态；不建持久索引，也不声称每个进度 tick 都全量排序。

## 已完成、停止或不建议的方向

以下不是 24 项待实施任务。重开须先有新的实际 consumer／成本证据，并引用原停止原因；不能把上下文遗失当新发现。

| 方向 | 当前事实／原结论 | 后续边界 |
|---|---|---|
| 共享上传 queue／批量 mipmap 与 BC conversion | 已按设备复用；批提交／32 未提交上限／完成失败 identity 已具备 | 不删完成 wait；新瓶颈需具体 conversion／提交证据 |
| IPC 背压／主界面逐帧驱动 | DaemonCommandBuffer 已 latest-only、控制屏障；接收量／单次 drain 有界，音频后台直投 | 没有传输瓶颈不改 XPC／合并 daemon；ProcessType 不机械套 AppKit renderer |
| 缩略图／GIF／diffable | ImageIO 最长边800、GIF静态候选最多8帧、动画激活租约、预算、同ID跳过结构snapshot与串行apply已具备 | 实际大量GIF峰值／scale问题出现再局部查，不重写全缓存／snapshot framework |
| 系统暂停与 Web shadow CSS 兜底 | 系统事件／idle deadline 已有；shadow animationstart 不冒泡，暂停期1 s扫描是[既有设计](../web/css-animation-freeze-redesign.md)取舍 | 没有等价覆盖不删；native media gate 不代替作者CSS／JS暂停 |
| fetchall 目录监听 | 事件＋10 s恢复兜底、0.5 s trailing debounce、后台枚举与revision拒收已具备 | 缺失目录恢复仍需要；不直接删补偿timer |
| 后台预编译／长期预热／Release探针 | 用户明确不采用后台预编译，Release开发入口已剥离；空Web预热有限寿命 | 研究工具只放隔离开发链，不能重新塞周期采样／selftest进发行版 |

### 冻结输入与避免并行污染

1. 每批从 Git 状态列出 owned 文件，基于确切提交＋owned 导出固定构建输入，排除并行改动；记录 App／主 binary／helper／优化配置／签名、样本与属性、窗口尺寸、目标 FPS、显示器、音频来源、系统状态及缓存目录。
2. 构建与性能运行串行使用仓库现有锁；锁只能约束合作方，无法排除另一个会话手动跑样本。观察同时活跃的 renderer／编译任务、热状态与时间段，污染窗口单列，不混入配对结果、不改并行任务的 App／媒体／进程。
3. 区分主 App 冷启动、renderer 冷进程、项目／编译缓存冷、OS文件页缓存冷热、已有daemon接管。
4. 主指标是点击／原请求发出到目标实际可见且原输出交接完成。属性准备另记请求到可操作控件，不与播放首帧混算。
5. profiler／详细截图／Debug 诊断另开资格窗口；普通优化产品的性能窗口不混进去。系统 CPU 时间先核单位，GPU allocated 与进程footprint分别报；局部阶段不能相加成总耗时，均值不能冒充分位数。

### 短筛、保留与正式声明

- 第一轮用受控输入／行为门、一次联合归因和少量交替 A/B 排除明显无效方向。证据应能说明“确省了哪份工作”，不是只看一段wall数字。
- 低复杂度局部修改：需要原输出／失败反例等价，真实操作通过，主要成本没有稳定负面变化；省调用／分配可如实标局部机制收益。噪声导致整体提速比例未知时保留未知，不为凑10%撤回可靠小改，也不直接认领稳定提速。
- 声称整体稳定收益：使用原专项相称的正式窗口。稳态通常每轮30 s预热＋至少60 s计量，至少3份有效基线与3份候选；启动冷／暖各至少5次交替比较，不用5个点声称p95/p99。必要的30 min稳态／20次轻重切换只在高风险生命周期或阶段收尾执行，不能每个小修重跑全矩阵。
- 任何功能／安全／用户数据回归先修；增加的排队、内存保有、状态数、冷失效成本与维护面必须列账。只有全面量化达到现役性能卡要求时才标正式专项验收，局部保留不是篡改原始门或完成全引擎优化。

### 最近行为门与明确缺口

所有以下模块文件已在本轮确认存在；列出入口不表示已执行或已有足够行为覆盖。实施前读断言和真实输入。统一运行形式：`python3.12 -B script/run_scene_tests.py --module <模块> -j 1`；只选本次涉及模块，不把整表当每批必跑。

| 门 | 可复用模块／仍需补的覆盖 |
|---|---|
| T3 frame | `test_scene_paused_frame_recovery`、`test_scene_surface_evaluation_transaction`、`test_scene_frame_context`、`test_scene_cursor_surface_routing`；S5仍需真实多屏时序 |
| T5 audio | `test_system_audio_spectrum`、`test_audio_spectrum_response`、`test_system_audio_spectrum_recovery`；补连续帧缓冲复用与尺寸切换 |
| T6 media | `test_scene_system_media_provider`、`test_web_system_media`、`test_scene_system_media_ipc`、`test_scene_system_media_source`；补Web封面需求／晚订阅与转换计数 |
| T7 Web | `test_web_playback_pause`、`test_web_compat_parity`、`test_playback_switch_endpoints`；未覆盖token原生生命周期、全部频谱endpoint背压，须补真实owner门 |
| T10 UI算法 | `test_ui_library_algorithms`、`test_ui_projection_efficiency`、`test_library_toolbar_behaviors`；不证明SQLite/SIL持久化、目录校准、视频generator正确，须各补行为harness |
| T11探针 | 原Video/SIL独立Grid已退；由`test_library_visible_source_lifecycle`、`test_wallpaper_library_catalog`与`test_grid_window_thumbnail_lifecycle`接管真实文件worker/单flight/窗口租约，`test_library_keyboard_navigation`补释放反例；不据此声称性能提升 |
| T12详情 | `test_steam_detail_navigation`、`test_steam_detail_layout`；保隔离HOME和实际cache消费者 |
| T13下载 | `test_steam_download_history`、`test_steam_download_sorting`、`test_steam_library_interactions`、`test_steam_grid_updates` |
| T14进程 | `test_daemon_process_transport`、`test_playback_process_isolation`、`test_daemon_process_lifetime`；预热TTL精确边界仍需补 |

Swift产品变更做Debug build；时钟／GPU／VM／IPC／持久化与可见变化做隔离代表运行，最终Release实际产物核无新增开发入口／周期诊断、签名及arm64。Debug内部runner只证明其路径，不能直接当普通Release性能或线上Steam验收。

### 实际工具入口

复用现有工具，不新增 benchmark 框架或常驻监控；以下参数已通过本轮 `--help` 核实。执行时先核当前版本，隔离目录由任务自行建立。命令是后续模板，本轮未运行它们；不得给真实媒体目录作为可写runtime root。

普通优化产品通过外部 Instruments 的 App Launch／Time Profiler／Thread State／File Activity／Allocations／Metal System Trace／Display 联合采样，先确认当前工具模板支持；不把iOS专属指标强套macOS，不要求Xcode Organizer线上聚合或新增埋点。实际Music验证固定同一片段／音量／输出设备／采集权限；合成正弦／静音只作可复现反例，不代真实音乐。画面截图与功耗窗口分开。

## 交付、记录与退役

每项开始时只在所属现役计划／合同记录当前owner、冻结身份、假设与最近门；完成后保存一份简短结果：改了什么、去掉的工作、实际数据与噪声、功能／失败反例、负面成本、保留／停止理由、未覆盖项及后继指针。失败或放弃的原数保留，不挑最好值；正文不不断追加campaign日志。

研究文档批次已提交；当前实施按每批真实 owned 文件界定范围。共享角色／设计／预算 JSON 逐项增量合并，不覆盖并行条目；产品与测试仅改本批 owner，未经核对不纳入他人源文件。此路线的实施细则只补职责、退出与验证，不复制既有能力台账。

各实现批次分别列 owned 文件、验证、独立审查、产物去留、Git 状态；本轮已获逐批提交授权，不推送。本文U1/U2实施边界仍由现设计登记引用；待稳定合同由原owner专题接管后整体归档，不为搬文档复制第二份当前事实。重开STOP必须满足本页记录的条件，或由用户明确授权新阶段。
