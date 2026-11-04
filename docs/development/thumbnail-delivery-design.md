# 全模块缩略图交付与复用

<!-- document-role: active-plan -->

复核日期：2026-11-05。负责人：repository-maintainer。

<a id="overview"></a>
## 当前结论与范围

**用户感知的连续、清晰呈现优先，其后才是资源平衡。** 主网格、收藏与混合列表、picker、详情、列表封面、下载任务行及状态面板采用同一请求与复用规则；本地读取、网络与账户、视频取帧只保留必要的来源差异。代码复用也属于验收，不能在几个模块各留一套相似实现。

当前验证、失败和未解项唯一归[批次结算](code-slimming-program.md#代码精简专项)。R114–R121请求/缓存/队列策略与R122稳定操作条保持，Steam、Artwork/Status、下载行与App屏保小图的未迁职责仍在。未暂存/未提交，Scene引擎不在范围内。

R122稳定bar留在原卡片Root，保封面hover、命令、alpha、卸载、租约及Steam位移；操作条不再跟随放大，原软阴影自然显示。原生事件门须同步受控指针，窗口尺寸变更须重核点击点，不靠扩命中区或隐藏失败。完整拖拽超时单列，限定控件/重排门不证明所有输入或性能。详情未打开仍无响应不能归于遮罩，pending规则保持；关闭态偶发吞击、冷返程空卡与Photos级仍未结。

本轮资源与交互收敛设计：同值选择在Presentation唯一准入处验证旧session后直接复用，不再构造整页Set/发布快照；Grid保原回调与拒绝恢复，只省接受后无变化的原生选择/可见cell投影。没有新索引、缓存或owner，首次选择、源/过滤变化和失效租约仍走原链。缓存检查区分共享像素与每消费者取消句柄，不能把轻量provider实例当作重复解码。

详情bar采用原生responder chain：共享操作条只声明详情按钮与原打开动作能力，Shell依据现有overlay active状态决定发原关闭通知或调用原打开动作；遮罩仅放行真实、可用的详情按钮，背景/滚动与其他控件仍沿原关闭规则，关闭在途即释放命中并可反向。选择此法以复用所有来源的原callback、token/挂载与内容，而不另传toggle状态或为每个来源建开关。无Shell的独立控件仍调用原动作。验收覆盖实际按钮命中、打开/关闭在途连续反向、跨来源/过期回调及关闭后内容释放，不把属性采样说成像素/FPS。

工具栏所有页面共用的标题增加8pt前导间距，Pixabay改为排序→筛选；标题真正换值时做系统短淡化，首装和减少动态效果保持即时。只动小标签，不对网格截整页图或增加加载等待；保标题AX/tooltip、宽度和overflow行为。资源主线优先于更多装饰动画。

尺寸需求补齐裁决（2026-11-05）：混合页/Picker的Steam预取改用既有实际request对应的256/512/800档，并把该档纳入原需求身份；同档几何变化不重启，保原来源、版本、fallback及取消。Pixabay下载卡/详情把实际request交原store，按同一AVAsset的真实旋转尺寸生成未裁母版，仍取0.5秒；像素构图、兼容复用、磁盘与负缓存继续归原ThumbnailCache。复用原Pixabay元数据尺寸读取，不新增媒体/任务聚合owner；改变目标时保留同源当前图，换源沿原撤销。旧nil入口保520×300行为，旧磁盘小图不足时沿原生成链升级；大目标可更清晰也更耗像素，预算不扩大。不同目标同时冷请求仍可能各自取帧，先不加跨请求聚合状态。Video缩略图候选帧及桌面0秒静帧用途不同，退出直接共用文件的候选；隐藏动画是否消耗CPU另需运行证据，不能只凭animates标志加观察者。验收覆盖真实目标传递、暖复用/变档、native小源/旋转、源替换/clear与取消，并保帧选择及原交互；计数不外推全App FPS。

Steam资源寿命裁决：非显示预取在同一State中完成原image→fallback→video与有界重试，成功交付缓存后解除取消闭包对临时State的强持有，原展示State仍保图。真实多图、缓存淘汰及显示State验证回收；不增加预取模式或新cache/任务owner，也不直接迁入缺video/retry/reload语义的旧PrefetchController。保当前Steam完成后的best-effort兴趣，不在每次viewport里强补全部已淘汰项；未约束字节与方向预算时，大于cache容量的近邻集可能循环解码。来源/档位/reload token变化仍由原assets撤旧。

列表封面寿命：Artwork显示独立方图，未裁源图仅供同实例回执去重，弱持有；弱源归零后nil回执仍清现图。保构图、alpha、取色、来源身份与实际消费者寿命。Steam liveLoader的单次临时State不启用动画、不再configure/reload，首个成功后局部保image、清onChange并reset，再交原completion；失败/pending继续原fallback/重试，外层Identity变化重建，取消仍可撤未完成需求。真实State/cache须验证同步暖借图、异步/视频fallback、失败不提前清、取消/迟到/回调重入与输出不变；只退无消费者源图，不加owner/cache/模式，也不全局缩小方图。封面backing需求汇总另评。

下载行尺寸补齐：48pt图框以同一常量定义布局和需求，Row首次挂到真实window后按其backing生成fit请求，经原Bindings交Controller和来源cache；Steam仍用原256/512/800档，其他来源接原ThumbnailRequest。唯一已申请目标替换重复thumbnailKey字段，来源身份读现有row。初次configure可先绑定进度；挂窗/backing变化只准备图片，同值退出；同源变目标保图，换attempt/key沿原占位，回执核原attempt/key/目标。Popover重排临时离窗不撤租约，最后关闭仍由原unbind撤销，不加挂载状态、cache或任务owner。验收须覆盖真实挂窗、backing、重排、暖/冷及迟到；小目标不代表所有暖母版都缩小，SIL仍保512冷解码下限。

任务面板行复用时，图片与进度状态沿[主界面设计](main-window-playlists-redesign.md)迁出重型视图，由原面板生命周期保留，替换每行UIView内的同一租约/当前图片。原全历史图片准备及已就绪图片保留不变，本轮先缩减控件与约束；不另建图片cache，也不把取消离屏取图当作已保证回返无加载。共享Source/ThumbnailRequest与暖借规则不变。

Steam暖复用同时补齐：已就绪较大档可直接满足较小档，不能因任务行改256而把现成800暖图变冷等待。原静态入口与预取就绪判断共用同一兼容查询，先精确档、再较大档；源指纹只准备一次，不复制位图、不建尺寸别名或扩大预算。较小图不能满足较大需求，取消、失效及来源变化保持；预取借到大图后也必须能识别就绪，避免无256物理条目而反复请求。确切物理key的诊断与“可显示就绪”要分开验证。

静态动画结论候选已拒绝：本机对生成的两帧GIF截断前缀，CreateWithData和CreateIncremental+final=true均可报告一帧且Complete；[ImageIO状态API](https://developer.apple.com/documentation/imageio/cgimagesourcegetstatus%28_%3A%29)的返回不能直接当本输入的完整性证据。未可靠区分完整单帧与失败，不保终态、不换factory迎合测试，已逐字退回本批前动画实现/夹具并保失败恢复。没有新格式名单、负缓存、解析器或文件监控；有新的真实来源合同或反例前不重试该候选。输入统计与拒绝过程归当批本机证据，不外推所有格式/系统版本。

R123裁决：pending发布同步进入整页render后才dispatch；票据变化不应重建无关的目录解析、下载映射、列表名与页面播放快照。保同轮反馈、订阅/Inspector顺序及Grid刷新，来源输入未变时只更新原CardStateProjection的播放字段。当前committed/pending按关系解析，最多保留两个raw/canonical身份和pending有效位，不能把页内映射缺项当canonical，也不累积历史引用；初建一次解析后，仅从长期来源映射移除播放独有键。页面、内容、catalog/projection/关系revision、reset变化或上次失败仍完整准备，失败仍清理并报告。复用原owner，无新缓存或调度层；产品小幅增长用于来源/播放职责拆开与原别名语义。验收用真实prepareCardState、页外/alias/错票据/停止、初始播放别名退役、源变化及原pending-before-dispatch门；工作次数不代表FPS或全部点击/动画修复。实际按钮中心仍待查；不变可见性合并的取舍见下文。

R124元数据裁决（已实施）：视频详情构造在postOpen之前同步读取attributes并创建DateFormatter，原Task仍继承MainActor。保原两次completion、完整行/section模板及唯一取消句柄，把真实stat/日期与AV准备迁同文件@concurrent函数，纯结果跨回原Task交付；使用现模型大小作初值，缺失大小与真实文件创建日期暂占位，最终仍读原文件，不以导入日期替代。选择仓库已有@concurrent模式，退出原Main同步准备，不引入detached第二任务/取消转发或新缓存；View原缺失提示fileExists另有消费者，本批不宣称所有IO退出Main。验收须观察真实stat/AV调用线程、同轮/交付前取消、最终文件事实及原View卸载/换源。另查普通未播放hover卡在原生追踪期间遇到真实layout/update的反例，并以隔离完整App检验实际入口；没有复现不改焦点、遮罩、pending或按钮跟踪逻辑。两项证据不能互相冒充，也不证明SIL首开空档或动画/FPS已结。

详情动作选择共用已呈现页面来源，避免另建一份与UI不一致的播放序列；没有快照按原本地page/远程single回退，Stop沿当前票据。具体旧action与后续render语义归[Inspector当前职责](../architecture/appkit-migration.md#inspector)，运行数字与采样上限只归批次结算。

R125选定：单项查询在原Resolver内只准备目标展示值与索引，不直接相信旧DTO，也不引入常驻索引及revision状态。仍扫描全部源与locator的canonical身份，保原别名错误范围、canonical-owner优先与locator后项覆盖；多项和空请求沿原全量路径。这样先减少已证点击链的派生工作，代价是仍O(N)扫描且全量路径每项多一次nil短路。验收用同一真实Query的5000项尾部/缺项、覆盖/重复/更新和错误反例，以及真实构造/写入计数；不以计数推算帧率或声称按钮偶发失效已修。

R130静帧职责：保原预览入口、缩略图通知/回调和静帧1.5秒排程；UI冷请求/冷却回退传原StaticFrame owner的thumbnailFallback(request)临时需求，warm直接返回。静帧worker真正运行时，若已生成的缩略图header和像素覆盖本轮目标，就退出完整静帧生成/模型发布；坏header、尺寸不足或仍缺图则按原时间继续备用静帧，不等缩略图所有尝试终态。明确full需求保默认，真实导入/桌面同步及已有静帧复用不改，原Set足够，不加owner/字段/Task/intent表。native尺寸未知时保守不省该帧，不另读AV元数据。退出的是普通浏览附带的可选播放fallback预制，正常两阶段播放不以它为ready条件；不能报告任意路径完全零行为变化。原真实静帧worker/生成/clear/合并/尺寸/导入门验证输入和调用，调度计数不等于动画/FPS。真正metadata回填的正文拆建及各下载来源继续按实际证据处理，不叠key/模板状态。

R131实施决定（详情回填）：Video详情第一次同步placeholder仍构造完整正文；挂载后保留原预览、标题、摘要、文件位置及滚动容器，仅更新实际字段。已有Style的facts工厂提供同步可选value绑定；固定标签结构只赋值，真实标签结构变化只替换facts子树，播放列表变化只替换其内容。原缺失文件提示在每个原刷新点重新检查并控制现有section，不缓存可用性。取消、预览请求、footer动作、元数据任务和Host侧滑owner保持；同轮currentWallpaper取一次局部，不新建模型快照、display key、持久缓存或调度层，旧整套rebuildContent同批退役。代价是持有少量实际UI引用及对局部结构变化的直接更新；不得以稳定身份或计数声称完整网格FPS。验收复用原预览门，并以真实Video View/Host的原生窗口，先稳定测试窗口首绘，在5000模型尾项的侧滑中回填metadata并发布非当前项变化，观察身份、动作、布局与presentation中间值；图片解码独立完成，不以IO赶在动画结束前作为合同；5000模型加单图不是持续大量解码压力。Steam下载的呈现前同步JSON及无关发布强制重建另行验证，不把Video结论外推所有来源。

周期可见性（R126/R129）：无变化不发布；挑源/DTO合并在原Catalog单任务的两个@concurrent函数处理。Main只对同一模型快照提IDs、按返回indices取模型，原服务/文件worker、独立Video repair及随后最新Image保持。没有现成实时索引，选择线性ID拷贝、后台扫描、临时数组和执行器切换，避免新增常驻索引/失效链。入口rev/pub跳过旧轮，await后核取消/视口代次，原publish唯一接纳source revision；保first-wins/重复行/来源状态，pub未就绪不抑repair。验收看真实后台线程、持有回执时换源重排/关闭及完整原行为；不以线程位置推算总CPU/FPS或按钮已修。

首轮订阅裁决：Online详情沿原observeLibrary承接订阅就绪后的同步正文，只退出snapshot首值，保后续同值/新值、progress/session发布。ctor保preview先于detail；仅重挂载先恢复resolving再同步读取当前来源，旧error优先级仍保到成功。这样退出首值整套facts/约束重建，并及时呈现重挂载内容，无第二状态或去重cache；真实详情完成仍按原值回填。两现役夹具用持有详情与Main哨兵证明工作/后续发布，不能据此声称首帧动画或中心偶发失效已解决；后继以当前App动作采样决定下一处修改。

本页拥有后续跨模块目标、取舍和迁移验收；启动先呈现与R112既有实现事实仍归[本地资源设计](local-library-loading-design.md)。不要将局部门通过写成全局完成。

## 已证断点

| 入口 | 已证断点与当前处置 |
|---|---|
| 原Grid、Adapter、picker | Steam混合/Picker预取已接显示同档及跨档撤销，成功退役临时State；Pixabay下载卡/详情已接实际request、Core旋转尺寸与同源保图。Steam跨档/动画/视频缓存仍沿原owner；不是全模块资源整合完成。 |
| Wallhaven/Pixiv浏览页 | R114已由原viewport/preheat owner将本地SIL当前目标贯穿，远端获取仍保原预算；远端真实几何迁移待续。 |
| SIL/Video详情、封面、状态面板 | R114已退出R112方图/nil互斥，并复用已有未裁母版及兼容就绪图；冷态不同目标仍保独立需求身份，不能宣称所有来源准备已合并。活View持图和原全局预算保留。 |
| Steam/在线图片 | Online的尺寸key、16:9假设及独立图像owner已由R115退出，实际request和兼容就绪图走共享实现；网络/账户与原raw缓存保留。Steam的尺寸key/原静帧及视频fallback仍待迁，不能把再次解码当成再次下载。 |
| 小列表、封面及通用URL分支 | 48pt任务行已按真实backing/fit透传，Steam暖借大档及预取ready共用查询；封面额外强持源图的链已退出。Steam封面State、封面实际尺寸汇总及通用URL的namespace仍需沿调用核对。 |
| 视频状态面板 | R113已移除nil后自行generate/reload的旧分支，生成期间的ready由当前Provider最终交付；空闲时外部资产就绪仍可刷新。通用图片来源路由和实际尺寸仍待统一。 |

入口：[Grid/Adapter](../../MyWallpaperX/App/WallpaperLibraryCellAdapter.swift)、[缓存](../../MyWallpaperX/Shared/UI/ThumbnailCache.swift)、[在线管线](../../MyWallpaperX/Shared/UI/OnlineImageThumbnailPipeline.swift)、[Steam来源](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopPreviewSource.swift)、[Pixabay下载图](../../MyWallpaperX/Modules/Pixabay/UI/AppKitPixabayDownloadsItem.swift)。

R113对R112原始时线的复核还证明：六页跳跃约跨103项，96项连续近邻的前64/后32均未覆盖下一落点；返程91次无图中85次在返程才遭淘汰，而返程起点491个驻留位已有229个登记可见项。盲扩预取会继续用未显示的中间项挤出回访图，不能只调缓存容量。这里的可见登记和nil回调不是屏幕呈现证明。

R113首次own-window SCK能启动，但CUA滚轮被输入服务拒绝；进程、AX和截图可访问，单次公开AX翻页只有位移，没有滚轮事件。1800条记录在有效滚动前耗尽，最终超时，不能认作滚动、空白帧或FPS验收。保留失败入口，不修改产品去迎合探针。

R113状态面板的真实Provider/Core/AV与原ready订阅切片验证：同一清理场景旧load 3→1、真实AV 2→1，失败场景旧ready反馈达到测试截断8次→一次nil终态；这是退出旧重试链的收益，不是网格滚动证据。新17控制/10检查、原视频交付44控制/16检查及完整面板夹具均通过，Debug与strict/deep签名通过；完整用户库、窗口呈现及线程/泄漏工具仍未验收。新增测试复用原生成夹具，未另建生成或缓存实现。

## R114验证与尚未闭合范围

本批产品23文件增577/删448，净+129行；新增51行纯值请求以及输入/像素/构图事实，替代旧角色判断、重复ImageIO和View生成链，不新增缓存owner、任务图或永久来源表。测试43文件净+421行，主要接入同一真实实现并补跨消费者、舍入和无重复JPEG反例；最长Swift998行，代码健康门通过。

共享decoder/缓存/调度/租约、实际AV自适应与清理、状态面板、生成交付、旧nil路径、adapter、在线actor/本地viewport、picker及两类原生详情通过。R114私有候选的576px fit舍入反例曾触发2039次AV，修正后为1次，实际像素仍记575×324；这是候选回归修正，不算旧App性能收益。同JPEG矩形需求不新提帧。原图片回访20张驻留图在同轮可用、不再解原图；这些是限定入口计数，不是屏幕帧率或任意用户库结论。

网格topology/animations模式通过；完整continuous-drag及legacy模式在原生drag进入后超时，SIL完整交互选择集在card-interactions超时，后续reflow未执行。失败入口及输出保留，不以先前某个断言通过覆盖整组失败，也未确定为产品或宿主根因。Debug30.496秒及strict/deep签名通过，5924构建输入未变化；增量输出只含一个原Scene capture诊断的两处渲染，无新增诊断，未修改Scene。产品及测试74个owned文件在主仓与已验Source逐字节一致。

下一步先贯通Steam/在线实际几何和共享解码/就绪复用，保HTTP/账户/动画/原帧选择；再收敛原预取owner的快跳落点和回访污染。详情、picker、任务行及poster均按本页完整范围验收，未迁消费者不另留长期平行实现。真实触控板、工具栏透视区呈现、FPS与完整用户库仍待有效输入/像素证据和人工体验。

## R115验证与剩余职责

产品16文件增398/删406，净删8行；测试19文件净+372行。原ThumbnailCache内增加已取得Data的短准备、一次内容身份与source成功动作，保原线程/字节预算；不新建全局中心、来源索引或永久兼容层。Online/Pixabay网格预取与可见图共用同一实际square.fill；图片详情按预览框bounds/backing.fill，退出8档ready扫描和尺寸透传；Tint仍全帧fit。Pixabay下载详情删除重复渐变/crop预览类，保film.stack和AX文案，失败保当前有效预览。

17个最近方法取得通过结果，覆盖真实HTTP/账户、clear/late/cancel、同Data加入与不同Data隔离、坏raw回退、原缓存/回访、在线分页/预热、详情布局/关系动作、6种卡片生命周期/几何模式及Tint。在线actor/cached路径保持原raw磁盘，准备不重复写派生JPEG。旧PDF真实入口也为nil，已撤错误的新能力期待，未增加PDF renderer。最终Decoder的原生尺寸/实际raster/render内核未变，对应4个已绿共享门复用其限定证据；末次Decoder门验证最终完整源码。原Source输入与实际编译输入均稳定，具体计数不能代替屏幕呈现。

签名Debug27.830秒、strict/deep通过，末次增量构建0警告/错误；前次新出现的两项unused weak capture已随旧透传退出。测试中一个原有weak观察变量诊断保留，生命周期断言不变。代码健康1671个Swift文件均在1000行内，最大测试999行。主仓92个owned产品/测试文件与已验Source一致，未暂存/未提交。R114拖拽/legacy及SIL card-interactions超时、R113无效CUA滚轮入口未重跑，仍未验收。

## R116即时反馈与呈现边界

真实SIL Card已有size/placeholder布局比较，但图片终态无条件清key使暖图也重走整卡几何和主题。改为统一更新image/nil的frame，保比例变化和失败清图，再由原比较决定整卡布局；selection主题从原queued叶前移至selection owner同步处理，badge/frame仍依赖下一turn几何。产品仅+2/−2，无新owner/state/helper。原同source/path/取消/延迟loading/复用保持；明确改善的是选中主题不再等图片完成或下一Main，不宣称旧版已证屏幕闪烁。

同最终真实夹具旧/新：18项卡片事实中4项即时反馈由false→true，其余保持；5个无须整卡的阶段body各1→0，resize仍1，stale仍0。计数在实际guard后；暖图用真实Cache/Provider，其他终态以受控reply交付。原11项离屏目标重授予/未裁详情复用过，6049来源及4实际子过程输入稳定。新增测试125行Swift+50行Python，原门/断言保留；不重跑已超时的card-interactions。Debug26.163秒/5924输入稳定、strict/deep过，只有构建工具AppIntents元数据跳过提示，未更动链接配置或Scene。

公开输入资格化两臂未通过：NSApp.postEvent的6个事件在local monitor可见，但window=0，原scrollWheel与位移均0；own-PID Quartz投递也为0。随后受控直接scrollWheel虽收到60次、SCK有135条记录，却仅移动40pt，PNG固定index均未选到complete帧，仍不作跨行验收。首次探针的momentum continue已按SDK改为continuous，只修编译。以上正常退出不等于输入通过，最小失败入口保留，不修改产品迎合探针。

改用公开NSClipView.scroll(to:)/reflect的程序轨迹，复用真实Grid/Adapter/SIL/Provider/cache，80张自建PNG在原预算内暖缓存；不强制publishViewport、不清cache。60步实际clip从−66→1134→−66，跨1200pt往返；SCK在ready后开始，112条=110 complete+2 started、无错误/截断，3张PNG由Root逐张看过，图片及玻璃工具栏下内容均已呈现，这三张未见空白卡片。1445次visible方法返回image非nil仅是属性观察，不替代像素。探针修正了自身child高度与PNG选择，产品字节未变；输入与编译来源稳定。此轨迹不经过wheel/momentum/原滚动抑制状态，不能证明触控板、FPS、超预算回访或全部帧无黑卡；只复用既有SCK与真实夹具，私有探针随本批归档。

后续先查真实滚动呈现、详情进出及列数变化动画的等待/打断，按用户可见收益选改；Steam静态/动画/视频fallback及小图继续同一契约，保原帧选择。任何预算增加须有界并沿原owner回收，不以多包一层Binding代替收益。真实用户库、触控板/FPS和工具栏透视区仍待人工与有效呈现证据。

<a id="decision"></a>
## 方案取舍与选定方向

| 方案 | 优点 | 代价与裁决 |
|---|---|---|
| 每源只保一张足够大的未裁图 | 各View自行fill/fit，结构简单，跨界面可直接共用。 | 宽图为方卡保留大量看不见的像素；R112测试源原716KiB对方图400KiB，不能只为形式统一退回较差驻留。保留为优先可兼容结果，不强制所有源如此。 |
| **共用来源、按需缓存完整质量结果** | 同文件的读取/提帧共用；已有更大且构图兼容的图直接复用，确实不能共用才生成必要结果。 | 需要覆盖尺寸与构图元数据，所有结果共用原总字节LRU；不能给每张图永久保一份母版位图加一份方图。**采用此方向。** |
| 保留方图/nil互斥及各模块固定尺寸 | 修改最少。 | 会继续角色互顶、尺寸不一致和重复准备，不是用户新要求的终态。 |

变体描述实际像素与构图，不描述“主窗口版/picker版/详情版”。同一请求只交付一次最终结果，不引入用户已否决的低清→高清渐进显示。不同View有不同真实需求时，可以持有各自正确的最终图；这不等于保几套加载代码。

可选派生文件与图片Ready分离（2026-11-05）：采用原ThumbnailCache、同一Request和原worker，先完成原字节的stage/rename及原sourcePublication准入，再在锁内发布有效display、移走当前回调、记录Request.publishedImage（同一display的引用），解锁交图；原PNG/JPEG编码和派生文件提交继续在同一worker内完成，原decode/source/generation槽到尾部才释放。没有第二写队列、bitmap backlog、cache或epoch，编码/磁盘格式不变；只缩短首次图片回调等待，不声称降低总CPU或提升吞吐。sourceDataKey为空时，原始data仍归原字节阶段，不能误当可选派生编码后移。

publishedImage是原worker本已持有的就绪结果，不另存像素或延长到worker之外：LRU暖命中保持原同步返回；内存压力/LRU淘汰而派生写尚未完成时，原请求的有效结果仍可同步复用，避免再次读raw/解码。就绪查询/普通加载共用这个入口，peek不触LRU。显式clear/remove撤权后或需要新hook时，新消费者不接旧tail，register创建新Request替换原Map，旧写依原对象身份与allowsCaching弃交，不能删除新Request。nil/失败仍在原负缓存结算、retire之后回调。raw-only remove不追溯清此前已Ready的derived，仍撤尚未提交的写；Steam全tier+raw失效与clear保持原消费者边界。Source回调不持cache锁，显示图不随可选写失败消失。

Ready只承诺图片，不承诺可选文件已落盘；首次交图后立即换到现有就绪图不能满足的更大尺寸/构图，在tail窗口可能沿原来源再准备一次，仍受原槽位约束。接受此窄窗取舍，不新增跨target母图缓存或等待链；同target有效结果可复用，真正落盘后的未裁母图回访仍不得重复取源，较小disk decode不得覆盖母图。磁盘回访测试先等实际finish/rename，再保持原像素、源次数和一次回调断言；另以阻塞tail明确验证不同target可正确交图、Ready之后取消不撤已发生的回调。

验收覆盖首图早于阻塞派生写、原bytes先可读、同key同步暖复用、回调内clear/remove并重载、LRU淘汰后仍复用未失效的原就绪结果、失效后新generation、旧写不能盖新、首次发布前取消/共享peer/失败重试、晚加入beforePublication与scope撤销，以及实际槽位/队列上限和图片像素。先用真实实现的旧新版对照，必要时同步改掉“阻塞可选写时尚未交图”的旧时序假设，不能删除发布前取消反例；出现重复/漏回调、串代、撤权后回填或无界持图即停止候选，不靠再叠状态补丁。

公开依据：[Apple ImageIO降采样](https://developer.apple.com/videos/play/wwdc2018/416/)、[PhotoKit按匹配目标预热](https://developer.apple.com/documentation/photos/phcachingimagemanager/startcachingimages%28for%3Atargetsize%3Acontentmode%3Aoptions%3A%29)、[Nuke官方管线的阶段合并](https://kean-docs.github.io/nuke/documentation/nuke/imagepipeline/)。只参考职责与行为，不引入该依赖、不照搬其任务图，也不据此推断Photos私有实现。

R118选定：先用原预取预算纠正本地落点，再修消费交接；不先扩大驻留，也不把可选写盘改成另一个后台事务。预测保留原clip-Y事实和真实方向，由现有原生几何owner查询经NSClipView约束的下一viewport；统一纯值选择器只分配“即时近邻→完整原生预测集合→剩余近邻”，只在原近邻不能覆盖预测集合、且预算容得下即时近邻与完整预测时替换成员，容量不足原样返回近邻。即时近邻保一个当前viewport数量，不截半个未来来换走回滑覆盖。首项index不变仍可能持续滚动，恒定point位移也会因行相位改变首项差与可见行数，不能仅用首项位移和固定span猜未来或叠补行阈值。现有WallpaperGridScrollView承接当前/预测layout索引查询，不维护第二时钟/坐标owner或全库扫描；Main Grid本地、Picker、混合/自建列表及图片浏览沿原96/point预算接入。在线24/两行与Pixabay18预算保持原近邻策略；真实原生门已证明小预算迁移预测会挤掉反向相邻行，因此本批退出Steam/Pixabay候选迁移及其测试适配，不保平行owner或新Core API。重排/换源、实际几何变化与隐藏撤旧坐标。在线已有预取lease进入可见区时保留到cell接手或离开需求，不为每个可见项另启预取。Video缓存回调已在Main时直接交付，背景暖命中仍切Main，最终取消检查保持。

取舍与退出：预测不减少真正冷图解码成本，R117的极端冷页吞吐不足仍未结；要分别测正常小位移、快跳/反向、首尾、重排/zoom、显示→隐藏与真实暖盘回访。复用原helper、Provider与原生门，比较同预算成员、实际准备/取消、到图时序和有界SCK像素，不能用仅索引命中证明流畅。高负载暖盘场景用5000键经原cache真实生成/写盘，内存仍192MiB并保真实淘汰，额外冷源制造排队；声明模拟已访问图，不假称5000次原图IO。若预测降低正常/反向覆盖或未见收益，修正/退出该成员算法，不保永久双策略或新调度层。可选编码的交付顺序依上文同worker裁决；精确尺寸render短路仍待像素反例，不叠候选。

R119已退Video同步消费后的订阅首值，后续包括同值发布保持；Online复用已算动作与原初页绑定，命令token/epoch核验保持。私有分段计时定位纯图片单槽ImageIO约29ms、JPEG约1ms，非与另一Cache实例AV争槽；可选写盘保持同worker尾写，不拆第二事务或叠小分支缓存。

R120实施：原`load`接收非optional `ThumbnailInput`，执行“注册/内存命中→短disk decode→冷source槽内ImageIO/render→交图及同worker可选编码/写入”。复用来源4槽/预取2、暖盘decode2、未知异步媒体generation1；迁SIL Provider/详情和Video Provider三入口，已知文件URL明确directory hint。退出零产品调用同步`loadImageData`、双入口`loadSynchronously`及无读者预算字段，不新增包装层、lane参数或平行API。Steam异步原字节、HTTP成功发布、请求合并/提级/取消、失败签名与clear/remove写入撤权保持；未知loader不提前执行猜类型。192MiB LRU只约束驻留位图，不限制多份ImageIO瞬时内存。

R120裁决：同真实调度145事实旧5红→新全真，13最近方法与签名Debug过；5000项同轨迹冷准备21.86→11.67秒，完成ImageIO272→627，单次完成span因竞争29.00→36.81ms。终身峰含准备/捕获，不是测量期峰/能耗承诺；共同预期几何落点中性色采样改善有限，缺精确paint锚点，不认产品串台或Photos级完成。完整单例边界归当前批结算及R120本机包。

R121选定：SIL正文/section复用本轮入口已解模型，退出单用getter；missing/active、完整State guard/footer及preview/命令各自最新源保持，不另造渲染cache。正常流程只解一次模型，下游接确定值；UI、数据与缓存策略不变。原生测量用起点真实active/key/occlusion与全步active/key准入，失焦臂拒作时耗A/B；sendAction协议不冒充物理输入。managed成员、Main几何/绑定/图片属性、presentation与屏幕像素分列；hitTest依superview坐标，缺锚点/截断不补成通过。该空档仍未归因；R122转向已证按钮错击，后继优先实际App中心点击与快速开关，不把整段交付等待直接归IO并开始缓存大改。方法归[UI验证参考](../../.agents/skills/mywallpaperx-maintainer/references/verification-and-handoff.md#appkit-与窗口)，当前数字/失败/验收上限唯一归批次结算。


## 唯一职责与交付规则

1. **来源身份归原来源owner。** 传消费者真正需要的当前文件/远端版本、帧选规则、账户scope；不把完整业务模型下传缓存，不在内部反复stat/hash。相同文件的调用者回到同一已有来源入口，不按面板另建命名空间或缓存。不同路径不做全文哈希去重。
2. **显示需求是二维backing像素及fill/fit语义。** 尺寸档只在共享入口计算一次，visible与prefetch用同一需求；方卡、矩形详情、48pt小行均显式传入实际需要，退出旧16:9假设和散落的256/520×300/800默认值。
3. **共同的准备只做一次。** 原`ThumbnailCache`及解码/LRU实现承接请求、合并、优先级、取消与发布；来源provider只做本地/网络/视频的必要获取。在线原owner保HTTP/账户/重试，但重复的解码、变体匹配、就绪缓存和预取算法应迁入共享实现，不能只在外面加wrapper。
4. **先复用兼容就绪图。** 源版本、有效像素和完整构图足够就同步交付；足够大的未裁图可给小方卡沿原UI裁切，已经裁掉边缘的方图不能假充宽详情。相同构图只保必要质量；完整图已覆盖方图时不额外常驻重复结果。
5. **不同最终需求共用来源工作。** 编码母版/原始字节仍由原磁盘owner复用；已有准备好的JPEG文件、原始图片文件、编码数据与就绪像素是不同输入，不能先全部转为JPEG或再复制一份已存在的派生文件。目标不同不能重新开启一整套读源/下载/AV。确实更大的需求才升级，不能承诺任意尺寸永远不再解码。升级保原有效结果，不把旧小结果当作新请求最终清晰图。
6. **本地与在线分获取预算，统一交付规则。** 在线保现有网络与账户边界；本地盘读、解码和AV保持后台有界。可见消费者提升同一任务，撤掉一个不影响其他；最后消费者退出时取消尚未开始的工作，正在解码的结果按原身份决定能否发布。
7. **预取服务真实浏览。** 在原需求owner内比较近邻、预计落点与反向回访；不再用被高速跳过的连续区填满预算。就绪成员查询与真正取图的LRU使用区分；不先加第二缓存或两套调度。调整须证明正常小位移、快跳、反向都未退化。
8. **失败与清理沿现owner闭合。** 显式clear/source替换撤回旧发布权；失败不变成每30ms重试。不得用单源整组remove充当一个预取消费者的取消。Core单源remove丢completion的候选须独立复现，不能让新异步桥接依赖缺少终态的入口。

同文件不一定是同一张图：现Video从1秒等候选取帧、Pixabay从0.5秒、Steam还有非黑候选规则。先保真实帧语义并复用相同工作；若统一帧选会改变部分封面，必须明确记录并验证，不能仅按path误合并。用户自选封面、动画原始字节也不是可任意合并的静态结果。

## 迁移与旧链退出

R115实施决定：在线actor继续独占HTTP/账户、压缩数据与原磁盘有效期，成功解码后才持久化；原`ThumbnailCache`承接已取得输入的短解码、兼容就绪图、取消与发布，退出在线Operation/DecodeKey/独立解码请求表与就绪cache。原始Data是已有输入，不再套一层来源槽、复制磁盘或新增revision表。单结果桥接沿[AsyncStream取消语义](https://developer.apple.com/documentation/swift/asyncstream/continuation/ontermination)，同步登记后再等待，clear/账户退出必须终止旧准备而使新需求可独立开始；本地原clear仍保既有consumer终态规则。实际显示request贯穿Online/Pixabay浏览网格及详情，成员探查不碰LRU；Tint保完整画面fit。已取得Data仅在冷准备入口计算一次32B内容签名，挂到原请求键和LRU Entry以免同URL不同Data误合并或旧大图吞新图；暖peek不哈希，不另建revision索引。Pixabay下载详情退出重复的渐变/crop预览类，复用现SIL预览面，保原占位symbol和AX文字；远端预览按实际bounds/backing请求。Steam原帧/动画与其余本地小图后续接同契约，不把本批在线完成当全模块完成。HTTP成功发布动作保留在原Request的SourcePublication，nil→required→published只升级一次；最终锁防晚加入遗漏，暖动作也纳入原退役表。缓存来源无raw写权，旧cached A不能回写新HTTP B；普通图片只在实际UI交付叶切Main，Stream直接交付。零产品调用的在线直接Data注入API及旧decoder解码包装随旧owner退出，测试改走真实来源入口，不能保测试专用产品路径。

- R114先贯穿共享缓存、SIL/Video、原Grid/Adapter/picker和两类详情。共用`ThumbnailRequest`只含实际二维backing像素和fill/fit，置于`Shared`值类型层，Core不依赖UI缓存；矩形比例不因两轴独立取档改变，原方卡64px档仍可用于方形需求。
- 覆盖匹配允许每轴1个整数栅格像素的舍入，仍如实记录实际像素；两像素不足拒绝，旧225派生不能据此冒原生上限。真实AV的576px fit目标曾返回575×324，严格比较使候选重复提帧；此规则修正实际舍入语义，不加重试上限掩盖问题。
- 首次需求由图像框自身[`setFrameSize`](https://developer.apple.com/documentation/appkit/nsview/setframesize%28_%3A%29)的实际尺寸变化通知原Inspector，先调用super；父层不轮询深层bounds，也不在每轮layout重复查模型。挂载/换屏沿原生命周期重授予，不加尺寸影子状态、不改约束或同步绘制。真实窗口首挂、拆挂、取消与不变模型读取预算已由两类详情原生门验证。
- 来源入口区分原图/编码数据、已有派生文件及现成未裁像素，解码和构图仍由原decoder/cache承接。原图在原ImageIO元数据读取时取得原生尺寸；Video只回传路径及本轮已知的native-size事实，不把派生JPEG尺寸当原生上限。已存在的视频JPEG不再为共享缓存重复编码和复制。
- 同源就绪结果按真实像素和保留构图匹配；必要变体共原LRU与原总字节预算，clear/remove撤销全部变体。足量未裁图可服务不同形状；方图不能满足宽详情。冷态不同目标仍保独立请求身份，复用既有Core合并与磁盘母版，不另建任务图，也不把它认领为Steam/在线跨尺寸获取已合并。
- LRU原`setObject`默认仍原子替换新值；只有`ThumbnailCache`确认同源准备的发布显式选择兼容结果保留。不能全局按像素保大而吞掉Online同URL/同epoch的新Data发布；它的DecodeKey确实包含Data，不等于不可变来源。两种发布意图共同一预算/匹配实现，不另建缓存或来源版本表。
- 现有其他来源可以在迁移时继续用同一cache的未裁输入；接入期间的签名适配不复制匹配或生成算法，消费者迁完即退役。Steam原字节/动画、在线HTTP/账户和Pixabay帧选择后续按同一契约接齐，全部接齐前不认领全模块完成。
- 尚未迁实际几何的在线入口暂以原目标尺寸调用公共解码数学，并保未裁构图；不能先裁方图丢掉宽详情边缘，也不能先把完整宽图解码到方卡短轴、增加驻留成本却声称只做API接线。其尺寸假设、尺寸key和重复解码owner仍须后续完整退出。
- 原Grid/Picker/Adapter继续拥有UI；原媒体索引和播放引擎不迁移。先确定共享请求/覆盖语义，再让所有消费者接入同一入口，不按某个页面验收后即宣称全模块完成。
- 同批退役R112的互斥角色匹配、按面板/固定尺寸拆开的旧key规则、重复尺寸算法及View内生成/重试；保必要动画、视频帧选择、文件版本和账户隔离，不能删功能换简洁。
- 保旧磁盘母版读取及清理职责，避免为缓存升级复制整库或让已有暖图全部失效；新变体缺失只重建真正需要的结果。不能增加永久兼容分支或第二份来源索引。
- 不新建全局“缩略图中心”转发所有已有类。若后续真实耦合证明必须迁移owner，先在本页说明旧owner完整退出点、具体收益及维护成本，再实施。
- 实施与回归使用隔离Source，串行构建/原生/AV；主仓只合入审核过的owned路径，保留其他会话和R112测试App。未经用户确认不提交。

<a id="acceptance"></a>
## 验收与停止条件

| 要求 | 必须取得的证据 |
|---|---|
| 跨网格/详情/picker/任务行复用 | 同文件、同版本，兼容结果仍驻留或同源准备仍在途时，真实消费者入口的读源/AV/解码计数不重复；同时挂载、拆挂和开关面板均测。不可兼容构图允许一次必要派生；真正淘汰后允许必要重建，单列回访成本，不为通过测试永久保图。 |
| 清晰度与构图 | 正方、横竖、全景、方向信息、透明/色彩；1x/2x、列数/窗口变化；像素足够且边缘内容与原View构图一致。 |
| 有界与退出 | 真实队列/缓存测visible提级、单消费者取消、最后消费者退出、源替换、clear/迟到；坏文件不忙重试，原生小源不无穷升级。 |
| 所有模块同步 | 本地视频/图片、混合列表、Steam本地与远端、Pixabay在线/下载、Wallhaven/Pixiv本地/在线、封面/状态/picker/详情及App屏保窗口poster预览有明确接线（不含原生私有宿主）；不得遗漏固定尺寸旧消费者。 |
| 感知连续呈现 | 隔离自身窗口的真实输入、屏幕像素及同钟时序；普通滑动、快跳、回滑、超驻留、工具栏透视区。无输入/截断探针不算，nil回调数与最终有图不代替呈现。真实触控板与用户库仍单列。 |
| 代码与验证 | 复用现有行为门，补跨消费者反例；Swift产品变更做Debug，签名/原生、点击双击/右键/拖拽/键盘及动画按影响补验；审查退役API和产品/测试/文档增删，不靠搬文件或wrapper过门。 |

只有上述完整范围取得相称证据，才认领统一策略落地；照片级流畅仍须用户真实库体验及有效呈现验证，不由设计、构建或单条路线替代。
