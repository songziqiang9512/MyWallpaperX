# 主窗口 UI16 / UI17 完成记录 · 2026-10-27

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**

保存99ba1fa85隔离树前两批实现/交叉审与有界验证；仍未提交、用户验收继续。当前规范及新反馈只查[主界面方案§22](../../development/main-window-playlists-redesign.md#ui-feedback-thirteen)。原文“当前/完成/本轮”均指当时；新要求优先。

<!-- preserved-body:start -->

<a id="ui-simplification-sixteen"></a>
## 20. 全仓UI简洁与通用下载专项（M01–M16）

本轮以 `99ba1fa85` 为基线，仅独立树实施，不提交/推送。本文同时拥有设计与工作卡，完成每项后填写实际代码/近门/未验边界；旧表中的“通过”不能作为新代码的验收。用户明确要求删无用校验、认证、重复计算和嵌套，不新增无收益关卡；请求取消、账号资源访问、播放目标及释放只在实际消费边界保留。

### 20.1 共享职责与取舍

新增职责只覆盖实际新能力及现有多消费者；不为了过行数门拆薄wrapper，不增加通用下载执行器、第二选中/播放真值或全局主题管理器。每片实施核对被替代的字段、handler、测试装配与旧文件退出；缺口在原owner修正，连续补丁开始复制状态/算法时先收敛根因，不继续往错误结构叠层。

- 保原App NSToolbar、WallpaperLibraryCatalog/Presentation与来源服务。卡片bar只呈现两个动作，来源adapter注入详情与当前主动作；不复制播放意图、下载队列或Inspector身份。所有媒体网格和来源浏览都执行同一两键规范，播放状态沿既有Manager pending→ready→stop事件及时投影；失败回可重试状态，不等重进列表/重新hover。
- 空格仍由原Grid/Commands/InspectorCoordinator操作QLPreviewPanel。Wallhaven/Pixiv先由原source client解析所选asset的原图URL/请求头，在可取消请求中临时下载原字节并交QL；不经缩略图降采样/重编码，不写manifest/关系/下载目录/任务历史。关闭、换图、切页、账号变化与结束控制释放旧请求和临时文件；异步回包只在原请求消费点判断，失败显示原错误，不能把缩略图冒作高清原图。
- `Modules/Downloads`负责通用历史、投影和面板；`App/DownloadTasksController`仅连接原三套source，主Toolbar注入同一manager，避免模块之间相互依赖。Steam仍以原JobStore拥有任务/历史，Pixabay与OnlineImageLibrary保原下载/发布owner；不新增执行队列。活跃行只读原task/progress，非Steam历史由一个轻量终态ledger接受真实成功/失败/取消事件；历史不是播放许可，不保存凭据/临时CDN/路径授权。旧成功项只在原非Steam本地scan/manifest就绪后导入一次。历史载荷用一个`legacyImported`事实处理初扫尚未完成时先有terminal/清历史的真实顺序：早terminal照常保存，导入合并后置true，clear直接置true；历史导入不新增下载等待，保留来源原初扫去重等待；不加pending队列/迁移runner，不以空文件存在误当导入完成，也不每次开面板回填复活。查看/清理本机历史与显示文件无登录门槛；重试/暂停/取消/放弃原任务仍按captured账号及原source准入，不能借当前账号操作另一任务。
- 各来源取消/重试在原owner落地。Pixabay保存原下载Task句柄及attempt身份，只有该slot消费进度/终态；同id取消未完成前不重入。在线图片沿原active/waiting FIFO，commit后才取消仍是成功，不能覆盖已发布事实。重试不依赖浏览页当前items、不改变查询/滚动：Pixabay官方视频API支持固定`id`查询；Wallhaven/Pixiv重新解析详情/asset获取当前URL，再走原下载入口。[Pixabay API](https://pixabay.com/api/docs/#api_search_videos)
- 所有刷新UI改为macOS27的NSRefreshController；安装在原共享scroll owner，来源继续负责请求及真实终态，不靠延迟或下一无关catalog事件关spinner。macOS26没有手动刷新UI，不模拟滚轮/下拉；自动初载、分页、文件监听与本地Finder能力保留。Steam离页只暂停可见需求，回页恢复原browseContext/滚动，不再先returnToDiscoveryBrowse；用户点击返回才退出作者/个人上下文。
- 仅Pixabay专属`OnlineLibrary`/`OL`源码、目录及测试入口改名；真实多来源`OnlineImages`不改成Pixabay。现持久化API key、Inspector原raw identity、`online_<id>.mp4`及磁盘cache namespace保原字节并注释兼容用途，Pixabay专属代码符号统一Pixabay；原共享缩略图transport已供三来源使用，归Shared/UI/OnlineImageThumbnailPipeline同一owner，不加别名wrapper/启动迁移层。所有活跃路径/测试路由/项目布局同步；历史正文保当时名词，移动源码的链接目标改当前路径并保归档身份。
- 背景仅改设置名称为“界面主体色调”，选项“按列表取色/macOS原生”；沿原默认列表取色及原raw保存值，不改变原生材质算法。原生模式不叠背景染色、不取缩略图色，退误加的系统强调色投影与监听。卡片单击设置只有一个WallpaperSettings枚举：默认“仅选中”，另一项“打开详情”；显式详情按钮/菜单、既有双击/Return/AX语义、方向键替换已打开详情、空格预览及多选语义不变。
- 普通确认仍NSAlert。Editor/Picker/Steam/Pixiv/API Key等内容保现排版和玻璃表面；原生sheet优先负责模态与调暗，不为仿系统重写表单。若原生sheet实测破坏现布局，只在原ModalPanel补统一调暗；点击、scroll、拖动、快捷键不泄漏下层，Esc/默认按钮/嵌套OpenPanel/关闭cleanup沿原owner恰一次。用户切其他App时不抢回焦点。

### 20.2 工作卡

| 卡 / 用户项 | 具体结果与验收反例 | 当前状态 |
|---|---|---|
| M01 / 1 空态 | 所有列表空态只保图标/提示；工具栏导入/新建入口可达，搜索无结果文案不冒作空库 | 完成；空态/文案/布局/模态输入门与实际空图片库检查通过 |
| M02 / 2 工具栏播放 | 退所有主工具栏play/random/previous/next，含overflow孤儿命令；卡片/现列表内容头、菜单/快捷键播放能力保留 | 完成；工具栏/overflow/主菜单回归与实际App检查通过 |
| M03 / 3 空格原图 | 退所有bar眼睛；空格在本地走本地QL，在Wallhaven/Pixiv临时拉高清原字节，不入库；取消/切图/账号/失败反例 | 完成；原图字节/固定页/作用域/取消/QL接管及真实重挂像素门通过 |
| M04 / 4 两键bar | 全类型bar左详情、右download/play/hourglass/stop互斥；点击立即反馈，完成/失败/停止原位回声，文字深浅自适应 | 完成；六类实卡与Adapter绑定反例通过，PB再显重绑已补，深浅/事务门通过 |
| M05 / 5 聚合下载页 | 退出Steam专属toolbar/账号装配，独立Downloads管理模块；原四来源发布项/删除/搜索/筛选与专属详情保留 | 完成；聚合装配/持久化/发布、浮层原生门及未登录App检查通过 |
| M06 / 6 通用任务面板 | 原队列+终态历史聚合，未登录可看本机历史；取消/重试/清历史/查看文件真实可用，无来源筛选/第二任务队列 | 完成；历史/四源执行与取消/浮层生命周期门通过，本机历史无登录门槛 |
| M07 / 7 作者工坊保持 | Steam作者页→其他列表→工坊恢复原作者/查询/锚点；显式返回才回上级，登出/失效上下文按原规则 | 完成；作者/个人页查询和滚动上下文原门通过；真实账号实网未验 |
| M08 / 8 下拉刷新 | 所有toolbar刷新退出；27原生下拉单次请求/真实终态/取消与错误，26无手动刷新且自动加载不回退 | 完成；27原生stock/请求/真实终态与取消负控通过；26无刷新，物理手势未验 |
| M09 / 9 返回统一 | Steam/Wallhaven/Pixiv作者及自建列表返回均功能区第一、独立图文胶囊，保原返回目标/查询/锚点与overflow | 完成；目录/图站/Steam原生返回与overflow门通过，App目录返回已实测 |
| M10 / 10 单击偏好 | 原设置增加“卡片单击操作”：仅选中(默认)/打开详情；重启/导入导出、多选、方向键和显式详情不混淆 | 完成；默认/导入恢复/全部Grid偏好门及App真实鼠标单击检查通过 |
| M11 / 11 图片站下载入口 | Wallhaven/Pixiv toolbar同一通用下载按钮；不复制source登录/Task面板 | 完成；统一按钮/DI/浮层门通过，App Wallhaven下载入口已实测 |
| M12 / 12 主体色调 | 仅改名原背景设置为“界面主体色调”，选项“按列表取色/macOS原生”，恢复原材质/默认值/持久化raw，不引入背景系统色算法 | 完成；默认/旧raw/导入/原生清色及停采样5项门通过，Debug与App选项/材质已复验 |
| M13 / 13 About | 宽度原值×0.75，底部两按钮相应变窄；文案“删繁就简，轻松上手。\n为MacOS设计的原生壁纸管理应用”，保版本/链接/更新及长英文 | 完成；Debug与App实看450pt窗口、两行文案及按钮均适配 |
| M14 / 14 Pixabay Key | 工具栏纯key图标；保tooltip、AX、overflow可读名称及原API Key编辑动作 | 完成；纯key图标/tooltip/AX/overflow及原生API Key输入/保存/取消门通过 |
| M15 / 15 名称规范 | Pixabay专属目录/类型/变量/工具及测试改名；旧用户数据与raw标识字节不变；全仓二次搜索及原回归/构建 | 完成；命名迁移/9项原门/补充消费者/Debug通过，持久化raw字节不变 |
| M16 / 16 统一模态 | Editor/Picker/各来源登录与设置面板系统sheet玻璃/调暗；保排版，不允许下层点击/scroll/快捷键，取消/嵌套/关闭不残monitor | 完成；原生模态/Login/Editor/Picker/Form门及App新建、输入、添加检查通过 |

### 20.4 最终验证与交付边界

- 基线`99ba1fa85`；不提交、不合并、不推送。上一候选Debug增量26.03秒通过，5665个观察文件在构建期零漂移；M12背景恢复后的Debug/原生复验见本节末项。独立`com.songziqiang.MyWallpaperX.Debug.UI16` App签名校验通过，保留于本树`.build-cache/ui16-debug/Build/Products/Debug/MyWallpaperX.app`。
- 设置/取色/个人设置、共享bar、历史/四源下载/发布与命令原门通过；46模块、29模块补充及最终14组受影响回归完整执行，失败项修正后定向复验通过，Video只重跑受改方法。Chrome按真实终态调用检旧任务零干扰、新任务完成恰一次；编译副本去取消guard的负控准确失败。原生stock对照不冒认外部VoiceOver或物理下拉手势覆盖；成败日志与输入身份均保`.artifacts/ui16-20261027/`。
- 上一候选实际App已核设置唯一入口/两模式切换（其背景系统色行为已按用户纠正撤回）、鼠标单击仅选中/显式详情、空态与工具栏导入、未登录通用下载、Wallhaven下载入口、新建/添加sheet、目录返回及About排版。首次仅写临时HOME偏好文件未被cfprefsd采用，曾播放隔离库内置视频，已退出并按原测试方式校正独立UI16标准偏好域；最终运行无播放/helper，只留合成图片和UI16列表。真实账号实网下载、真实媒体删除、整桌面、Release与性能收益未宣称已验。
- 已退旧bar动态handler、Adapter空收藏准备、通用历史Store无消费者ObservableObject/Published与重复通知；真实收藏和下载执行仍归原owner。源码/测试/文档门分别通过；本机保一份增量缓存和当前App/隔离HOME供验收，终止的fixture临时目录由原门清理，不清未知或并行产物。

- M12纠正：只改设置文案，退误加背景系统色投影/监听并恢复原macOS原生样式与默认列表取色；保存raw不变。设置/取色/个人偏好5项门通过，增量Debug26.99秒、1192个Swift/项目输入无漂移、签名通过；隔离UI16实核仅“按列表取色/macOS原生”、原生已选及主窗材质，当前App保留供验收。新收据在原产物目录`native-background-correction/`，覆盖前候选M12的行为结论；未提交。

<a id="ui-refinement-eleven"></a>
## 21. 分页、详情与网格交互专项（N01–N11）

本轮继续原隔离树，保留M01–16及macOS原生背景纠正；不提交/合并。§21取代旧hover不放大、在线底栏、目录toolbar新建/排序等冲突规范。各工作卡完成即更新；没有真实运行证据不记完成。
共享边界：原Collection布局拥有末行footer，原来源服务拥有分页真值；不按图片完成另造发布队列、不截断结果。缩略图仍由原pipeline合并/取消/缓存，详情复用网格同请求同像素档，不增高清请求。先核实自动分页和可见优先的排队原因，优先修正预取窗口/触发，不盲增并发或复制缓存。失败/空作者页保真实终态且下次自然触发可重试。
Hover由现tracking/scroll phase驱动，Shared只投影以缩略图中心1.025等比放大（0.18s进入/0.16s退出）；不改collection布局、selection/drag/按钮命中，不增加timer/鼠标monitor。滚动开始即复位并退tracking，结束按可见卡恢复；复用/隐藏/减少动态归一。

| 卡/用户项 | 结果与回归反例 | 状态 |
|---|---|---|
| N01 / 1 | Wallhaven/Pixiv原底栏退出，原网格尾行居中仅文案；加载/计数/作者无更多真实终态，Steam退加载按钮；自动分页仍可达 | 完成；对应行为门通过；最终实机/Debug结算见本节 |
| N02 / 2 | 在线详情底栏仅下载图片/设为壁纸互斥主动作、同宽作者名尾截、原尺寸浏览器；总宽等预览，页码切换靠左；退重复下载/收藏/列表UI | 完成；对应行为门通过；最终实机/Debug结算见本节 |
| N03 / 3 | 详情预览复用对应网格thumb缓存与请求档，无高清二次拉取；异页/迟到/取消/账号scope不串图 | 完成；对应行为门通过；最终实机/Debug结算见本节 |
| N04 / 4 | 在线图片/Steam无图显示“加载中”，无占位spinner；坏图/真下载进度与GIF保原语义 | 完成；对应行为门通过；最终实机/Debug结算见本节 |
| N05 / 5 | 查清连续分页/预取导致空卡积累链，修现owner触发/可见优先和有界近邻，保完整分页结果、反向滚动/取消/失败重试 | 完成；对应行为门通过；最终实机/Debug结算见本节 |
| N06 / 6 | 所有toolbar排序line.3.horizontal.decrease、筛选line.3.horizontal.decrease.circle；名称/tooltip/overflow可达 | 完成；对应行为门通过；最终实机/Debug结算见本节 |
| N07 / 7 | 壁纸及目录卡同一轻微中心放大规则，无按下缩放；滚动无逐卡鼠标采样，恢复/复用/拖动/减少动态反例 | 完成；对应行为门通过；最终实机/Debug结算见本节 |
| N08 / 8 | 视频/图片/最近退toolbar添加到列表，保更多/右键真实添加及多选完成退出 | 完成；对应行为门通过；最终实机/Debug结算见本节 |
| N09 / 9 | 首组视频/图片无标题；第二资料库下载/最近；浏览/播放列表后续；原选择、目录及拖入/拖排语义不变 | 完成；对应行为门通过；最终实机/Debug结算见本节 |
| N10 / 10 | 搜索统一现Wallhaven/Pixiv的220pt，窄窗原生overflow/⌘F保可达，无逐来源宽算法 | 完成；remote原生几何门通过，local末次完整门受前台干扰；App实测220pt/⌘F已补 |
| N11 / 11 | 目录toolbar退新建/排序及孤儿命令；固定新建卡、真实菜单及手动拖排保留 | 完成；对应行为门通过；最终实机/Debug结算见本节 |

验证按真实owner近门（分页/取消/空作者、cache共享/请求档、详情动作与等宽、hover滚动/拖动、toolbar/侧栏/菜单）统一冻结输入执行，再增量签名Debug、独立交叉审查、隔离App实际操作。机器独占窗口与启动专项协调；真实账号实网、吞吐/FPS及Release无证不宣称。

- 结算：三子代理分工/交叉审已闭合，已证问题原owner修复；退按钮/handler/目录排序旧链、缩略图spinner及MainActor私有分页入口重复Thread/dispatch检查。实际发现native search建议宽仍拉长，补同一field真实220pt约束；详情footer短作者时NSStack默认gravityAreas不伸展，显式fill并补短名/无作者边界；新增footer用NSCollectionViewElement正式协议，未另加视图owner/状态机。
- 验证：20组最新记录及短作者/无作者footer补门通过（含定向复验，原失败日志保留），交付Debug26.34秒、1192产品输入无漂移并严格验签；local完整toolbar门末次被VSCode抢前台挡initial-key，未声称通过，实际App已补本地220pt/物理⌘F、侧栏分组、目录工具栏和Wallhaven详情三键。GUI验收App已重启保留，收据`.artifacts/ui17-20261027/`；只留原一份`.build-cache/ui16-debug`缓存及隔离HOME，不提交/合并/推送。
- 边界：分页原响应量不变（Wallhaven24、Pixiv作者24、Steam30；ranking原服务页），没有截掉结果或新增图片发布队列；修触发/同档预取/空槽利用后慢网单页仍可能显示加载中，不宣称消灭黑卡/FPS收益。真实账号写入、真实媒体删除、Release及并行主仓新HEAD未在本批验收，主仓仍由其会话维护。

<!-- preserved-body:end -->
