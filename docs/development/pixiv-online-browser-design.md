# Pixiv 在线浏览接入方案

<!-- document-role: active-plan -->

更新日期：2026-10-27。最初侦查基线：`8f71545d8962e16d401c79c5866e97ca9ddc554b`；当前整合基线：`2fb50b5f14b53410a7479ce474c9999376b4e174`。
设计后已进入实施P0：匿名排行、搜索、详情、单/多页响应均取得200有效数据，三种CDN图片URL带Pixiv Referer的HEAD返回200。尚未进行真实账号登录及最终原生App验收；不能把匿名响应或fixture通过当成登录可用证明。

## 1. 产品结果与取舍

“浏览”新增独立Pixiv页，使用现原生网格与详情。首版支持经预检确认的排行榜、关键词搜索、作者作品、单页/多页静态插画及漫画图片页；下载到统一“我的下载”，然后沿原静态壁纸事务应用、加入本地喜爱/播放列表。

基础数据模型、共享UI/缓存/下载发布、来源持久化、个人设置和systemStill准入均引用[Wallhaven方案§4](wallhaven-online-browser-design.md#4-两个新来源的共享接入合同)，本文不再定义另一套。Pixabay视频和Scene/Web播放架构不因站点浏览发生变化。

推荐“原生浏览 + 隔离官方登录窗口 + 站内Web接口适配”。整页WKWebView不利于共享卡片和本地操作；复制第三方OAuth客户端或使用代登录/代理会引入另一套凭据及依赖，均不采用。Pixiv主页面不常驻WebView；仅登录或用户打开同会话官方设置时创建。

不接Pixiv收藏/关注/评论/投稿等写入，不做下载全作者作品，不在首版做ugoira帧包下载/转码。本地“特别喜爱”仍只写本地Store，不调用[Pixiv站点收藏](https://www.pixiv.help/hc/en-us/articles/235646967-What-are-Bookmarks)。

## 2. 事实、参考与不确定项

参考位于主仓忽略目录`Reference Project/WaifuX-main`。所见接口是站内Web AJAX，不能写成Pixiv承诺维护的公开第三方API；本轮未找到这些接口的第三方开发合同，也不据此声称Pixiv绝无任何公开API。

| 参考位置 | 本项目裁决 |
|---|---|
| `Services/PixivService.swift:36,116,250,273,344` | 观察到排行、搜索、详情、pages、作者接口；都须先做P0，不直接承诺参数/组合 |
| `Components/PixivLoginView.swift:43–80` | 仅识别几种首页URL且桥接前读共享Cookie，不足以判断登录 |
| `Services/PixivAuthService.swift:68–121` | 存在PHPSESSID/device_token等就宣告成功；公开作者profile/all也不是当前身份认证探针，不照搬 |
| `Utilities/WebViewCookieSync.swift:9` | 默认WebKit→全局cookie、模糊域匹配和缺少删除同步会串会话；采用隔离存储和精确同步 |
| `Services/PixivService.swift:86`、`Models/PixivModels.swift:79` | `next:false`被解为非nil，不能靠`next != nil`翻页，也不能用空页数量作除数 |
| `Services/PixivService.swift:273` | 多页从实际pages响应取URL；不只为漫画开启，多页插画同样支持 |
| `ViewModels/WallpaperViewModel.swift:1048,1716` | 作者ID快照/切片可借鉴；原图失败静默下载预览图不可照搬 |
| `Models/PixivModels.swift:463` | 缺分级默认0、遮罩默认false、多页默认1会误判；缺失必须保留unknown |
| `Services/PixivService.swift:483` | 不复制混合Safari/Chromium伪装头模板和响应日志，只发送经预检确认的必要头 |

官方帮助确认[登录可能因无活动或环境变化再次失效](https://www.pixiv.help/hc/en-us/articles/235583068-Why-am-I-asked-to-log-in-every-time)、[热门搜索属于Premium能力](https://www.pixiv.help/hc/en-us/articles/235583788-What-sorts-of-benefits-are-available-to-pixiv-Premium-members)，但未保证参考AJAX接口。网络验证、账号可见范围与具体字段仍是P0/真实账号验收项，不能以参考能编译替代。

## 3. 会话与登录设计

### 3.1 唯一会话owner

`Modules/Pixiv/Core/PixivSession.swift`负责登录有效性、账号作用域、独立Cookie桥接、专用URLSession及sessionEpoch；`PixivClient`只接受该owner提供的当前请求上下文。网格和设置只消费会话状态、发登录/注销命令，不再保存isLoggedIn第二权威。

利用当前最低macOS 26已有的[具名持久WKWebsiteDataStore](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/init%28foridentifier%3A%29)隔离Pixiv，UUID仅为普通配置。不会话共用壁纸Web引擎的store或`WKWebsiteDataStore.default()`，不会话共用Steam/Pixabay的Cookie；也不新建浏览进程守护器。

网络侧使用专用ephemeral URLSession的私有Cookie存储；WebKit是持久会话权威，URLSession只作受控镜像。Apple的[WKHTTPCookieStore](https://developer.apple.com/documentation/webkit/wkhttpcookiestore)与[URLSession Cookie配置](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/httpcookiestorage)提供桥接机制，但Pixiv是否接受桥接后的会话还需真实预检。密码、验证码均由用户在官方页面操作，不读密码、不注入表单、不导入浏览器Cookie。

### 3.2 登录、恢复与注销

1. 只有用户进入Pixiv或点击登录才按需检查；普通App启动/本地播放不创建WebView，不轮询认证。
2. 登录页完成导航或Cookie变化只发出候选信号。异步从实际WebKit store取快照，保留domain/path/secure/expiry等属性，按`(domain,path,name)`同步增删到专用URLSession存储；不固定sleep、不仅凭Cookie名/拆值猜账号。
3. P0先确认一个只读的“当前会话身份”请求及可信身份字段；不能预先把公开作者接口定为认证探针。成功才是authenticated；匿名、checking、expired及网络unknown需可区分。候选端点和响应字段的实际证据写回本方案，不硬编码未经验证的成功页。
4. 会话持久Cookie存在也不意味着有效。再次打开先用缓存内容，有需要时验证一次；请求重定向到登录、HTML挑战、JSON error与网络错误分开处理。单作品403不能一律登出或提示未登录，可能是年龄/地区/私有权限限制。
5. URLSession有效Cookie轮换必须回送同一WebKit store，防止两边长期分叉。公开同步、WK观察者和实际网络完成事件复用一个合并任务，以“上次一致快照、当前WK快照、当前私有网络Cookie”为三方输入；WK未变的键不回写网络，两边都变化时保留当前网络值再同步WK。只写真正差异，自己的观察者回响在下一轮无差异后停止，不设时钟或轮询。普通同账号轮换不重置整个列表。网络完成来自共享传输句柄唯一completion hook，不再依赖completion-handler task不会调用的session delegate完成方法。
6. 登录窗口沿现`WallpaperLibrarySheetPresentation`的owned child panel、模态输入边界和退出清理；不另造全局事件拦截/焦点恢复。取消关闭不宣称登录成功；下次可继续官方登录。
7. 注销先递增sessionEpoch并取消/撤销旧请求提交资格，再等待清理专用URLSession Cookie/缓存与Pixiv独立WebKit数据。释放使用中的WebView后再移除store，遵守[Apple的移除顺序](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/remove%28foridentifier%3Acompletionhandler%3A%29)。不清全局HTTP或其他站点数据。

域匹配用精确域或点分隔子域，不使用contains/suffix伪匹配。Cookie只按自身适用domain/path发往Pixiv请求；图片CDN请求头由同一会话transport最小提供，重定向不得携凭据到外域。原站source外链使用系统浏览器，不附加Cookie/Key。

### 3.3 账号切换、权限与缓存

账号/登录有效性/账号可见范围变更递增sessionEpoch；列表、详情、作者ID快照、图片需求和未提交下载都绑定当前作用域。缓存键用不可逆/不含凭据的作用域标识及资源版本，严禁原始Cookie进入URL、日志、磁盘名或设置导出。

注销/换账号撤销旧UI与缓存发布权，并清该账号作用域缓存；迟到回包只做底层释放，不能重新建立需求或发布下载记录。已成功发布的本地图片页、喜爱和列表保留，离线应用不重新问账号许可；用户可以另行通过既有文件删除命令清理它们。

## 4. 来源查询、分页和作者上下文

| 能力 | 站内候选路径与初版边界 |
|---|---|
| 排行 | `/ranking.php?format=json`；先验证日/周/月的静态作品模式。日期由首响应固定后续页，不能跨日拼接 |
| 搜索 | `/ajax/search/artworks/{word}`、漫画路径；先做经验证的最新排序，不给普通账号假装可用的人气排序 |
| 详情 | `/ajax/illust/{id}`；按点击生命周期请求，列表缺作者名不触发N+1 |
| 图片页 | `/ajax/illust/{id}/pages`；按真实页响应取得原图/预览/尺寸，不替换`_p0`猜URL和扩展名 |
| 作者 | `/ajax/user/{id}/profile/all`后按当前切片批量详情；公开作品数据不能证明当前登录身份 |

本轮已实测daily排行50项、搜索首/次页、单页151233234、多页151276944（42页）的detail/pages；类型和页数字段确有String/Int混用，搜索lastPage不能从total除页大小推导。匿名`/ajax/user/extra`返回400，未获得可信当前身份响应；Cookie只作为会话候选，不能宣称已认证。其余组合继续由focused反例和实际操作验证；不通过的接口不得以空数组冒充成功。站点局部改动只影响Pixiv adapter，不改变Catalog、Store和播放层。

排行continuation只接受明确有效的下一页值；null/false/缺失不是下一页。搜索、作者批量和过滤后空显示页仍按服务端继续标志处理；不自动递归抓到非空或遍历整站，可显示“此页无可显示作品”并保留继续加载入口。重复卡按作品ID合并元数据，不重排已有结果，也不以去重后数量判到尾。

作者页保留发起者页面、完整Query、已载结果、日期/分页token、缩放和锚点；返回恢复原页而非主页或另一个模块。同作者重复进入复用当前上下文；显式刷新才建新快照。作者ID集合只有实际访问时获取，按scope/query缓存，当前批乱序返回须按捕获ID切片重排，缺项局部显示而不挪用别的作品。

关键词编码使用URLComponents/明确path segment编码；中文、空格、`/`、`#`、AND/OR和排除词都做反例。官方[搜索语义](https://www.pixiv.help/hc/en-us/articles/235646387-I-would-like-to-know-how-to-search-for-content-on-pixiv)只说明用户侧语义，不证明猜测的AJAX参数。缓存/回访/取消/不重排采用共享合同，不再新加Pixiv定时刷新器。

## 5. 作品与图片页身份

作品壳`PixivArtworkID`用于排行/搜索/作者列表去重；图片资产必须有真实0-based页索引，本地引用为`.pixiv / "12345:p2"`。第一页是p0，与UI的“第1张”区分，不能将p0和p1混为同一资产。

列表对已知静态作品可用第一页坐标投影只读远端卡，作为作品代表；这是尚未发布的展示身份，不授予play/organize，不承诺原图已解析。未知/ugoira作品不构造假静态资产；可显示不支持提示和打开原站。若Grid需要作品壳适配，必须在来源投影里显式区分壳与页，不把它加入本地Catalog或创建alias。

详情确认pages后按真实页数提供紧凑上一页/下一页和“第N/共M张”；原Inspector尺寸不改，翻页只切当前图。底部仅保“下载图片/设为壁纸”和“打开原网页”两枚等宽半透明按钮；下载只处理当前页，不悄悄下载整部漫画。喜爱/加列表沿本地资料库菜单，不重复详情入口；本地记录保留作品名、作者、页号及来源页。

同作品下载p0、p2产生两个合法资产，重下p2仍对应同一引用。列表可显示“已下载2张”或当前第一页状态，不因任一页下载就把全部页当成本地已下载。下载/打开详情/本地同页复用现缓存，真正原图只在显式操作获取。

原图失败不静默换预览图；如果未来单独提供“下载预览图”，须明确文案和资产质量，不能污染首版原图成功记录。

## 6. 内容能力和用户可见限制

- `illustType/pageCount/xRestrict/restrict/isMasked`允许unknown，保留原值；不把缺失字段默认普通单页/SFW/无遮挡。未知类型不成为可播放资产；未知分级不默认当安全内容。必要详情只对用户选中项读取，不为全列表补字段。
- 默认请求站点允许的安全内容。敏感、R18、R18G、生日及地区分别按实际账号和接口能力处理；本地筛选只能收窄，不替用户提高站内权限，不复用Steam下载页成人开关。[作品评级](https://www.pixiv.help/hc/en-us/articles/39125149371289-What-are-work-ratings)、[年龄限制帮助](https://www.pixiv.help/hc/en-us/articles/235585288-I-would-like-to-view-age-restricted-contents-R-18-R-18G)、[地区限制帮助](https://www.pixiv.help/hc/en-us/articles/26578893289881-I-can-t-browse-certain-works-from-the-country-region-where-I-live)是用户行为依据，不等于第三方接口授权。
- 账号设置入口打开同一隔离会话的官方设置；用户返回后主动刷新可见作用域，不注入设置脚本。401/403/遮罩/作品删除、付费能力和网络失败分别给可理解的提示，不一律“加载失败”或全局注销。
- ugoira按官方[逐帧图片和时长定义](https://www.pixiv.help/hc/en-us/articles/235584628-What-are-Ugoira)处理为首版未支持能力；明确“动图暂不支持下载/应用”，可打开原站。封面JPEG不能冒充完整动图或GIF壁纸。
- 页面匿名可访问哪些内容由P0确认；登录是可选入口，不在未确认时强制屏蔽所有匿名浏览，也不假装匿名能取得受限内容。

## 7. 原生UI布局

| 位置 | 设计 |
|---|---|
| 侧栏 | 浏览下独立Pixiv，与Wallhaven同级；不因作者子页选到其他模块 |
| 工具栏 | 标题／返回（仅有上下文时）／账号／刷新／排行或已证排序／筛选／共享缩放／搜索；动态不适用按钮不出现，窄窗沿原overflow |
| 查询模式 | 无词默认经验证的排行榜，有词进入搜索；清词恢复原榜单上下文，不把排行榜类型当搜索参数硬拼 |
| 筛选 | 已证榜单/作品类型/安全内容/可用AI条件；未支持的组合禁用并解释，不显示虚假热门搜索 |
| 网格 | 沿共享方形卡片和需求调度，静态图，必要的页数徽标；没有常驻动画或图片原图预取 |
| 详情 | 沿InspectorHost，作品名/作者/标签/分级和当前页图片；作者可进入作者页，返回保原上下文 |
| 登录/错误 | 原生提示和官方登录窗口；已有内容时用轻量错误条，不遮掉全部缓存；没有内容时才用居中空/失败态 |

新入口不接入壁纸Web宿主、音频采集或图像帧时钟。未进入该页不检查登录、不请求排行；退出页面停止浏览需求，已发布本地图和正在播放的Scene/Web/Video不受影响。

## 8. 实施步骤与停止条件

| 阶段 | 最小交付与验收 |
|---|---|
| P0 先行可行性 | 用隔离store验证匿名排行/搜索、官方登录→明确身份确认→专用URLSession、缩略图/预览/原图三条路径、多页响应；只脱敏保存结构/状态，记录真实可用端点 |
| P1 来源client与会话 | 完成typed DTO/query、scope/epoch、取消/限流、登录取消/恢复/注销、只读查询和真实错误分类；不复制参考伪成功判断 |
| P2 原生浏览 | 接入W1同一共享会话/UI，排行/搜索/作者/返回、按需详情和多页切换；需要什么元数据才读什么 |
| P3 页资产闭环 | 接W2同一下载publication，选中一页原图→我的下载→systemStill→喜爱/列表；注销/重启后本地图片仍可离线应用 |
| P4 交叉审查 | Debug/Release、隔离账号操作和真实单/多页图片，回访/缓存/滚动/模态/失败反例，独立审查后收尾；明确未验证能力 |

P0若不能得到可靠身份确认、官方登录必须绕过挑战、需要复制私有OAuth客户端/第三方代理，停止这条登录/API路线；保留可用匿名能力及打开原站，不悄悄以整页网页嵌入替代原生设计。某个排序/榜单组合不成立仅关闭该组合，不拖累本地图片或其他来源。验证码由用户处理，不自动绕过。

W1/W2和P1可按明确文件归属并行；App/Shell/Models/共享pipeline/JSON注册由一个整合者串行，不能两边同时改。P2/P3复用同一公共合同，源接口结果反证了设计时更新这两份现役方案，不再叠第三份路线。

## 9. 必须覆盖的反例和交付边界

- 登录取消、已有但过期Cookie、Cookie存在但匿名、账号A→B、离线unknown、单作品403不误登出、注销后旧成功回包、两Cookie容器轮换回环及精确域边界。
- 登出/换账号清作用域缓存且阻止旧下载发布；已经本地提交的图片不丢；同scope图像可见与预取仍合并，Cookie不进日志/manifest/个人设置。
- 排行`next:false/null`、零条、跨日、搜索过滤后空页、不支持的热门排序、中文和特殊字符、作者页乱序/缺项、同作者重复进入与正确返回。
- 单页插画、多页插画、多页漫画、pageCount缺失、删页/不可见页、p0与UI第1张、同作品多页下载/重下/混合列表、ugoira/未知类型/未知分级和遮罩。
- 原图解析失败、CDN HTML/403/重定向、Referer需求、返回预览与真正原图不混淆、磁盘满/取消/原子发布失败；A下载中改播B/Stop及退出/reset。
- 原有Steam、Pixabay、SIL、Video、Scene/Web属性和音频功能无改动回退；新provider加入后，离线/未登录不能阻塞原来源恢复或全局轮换。

来源新增focused tests建议按`test_pixiv_session.py`、`test_pixiv_browse.py`、`test_pixiv_image_assets.py`分行为建Swift fixture，并扩展Wallhaven方案列出的现有共享门；名称仅为计划，不代表已建测试或通过。真正登录、站内字段/权限和原图质量必须实际操作，不能由fixture或构建代替。

## 10. 文档登记与退役

本文唯一维护Pixiv特有会话、接口预检、作品/页语义和执行顺序；共用部分只引用Wallhaven方案。design登记的approved表示设计边界可实施，不表示P0已通过或受限内容可用。Git提交与合并按用户当前授权执行，不推送、不替换已安装App。

当职责稳定且真实验收后，将共享长期合同移交既有AppKit/仓库地图，Pixiv站点接口事实留在对应来源文档；退役本专项执行顺序，不让参考源码成为永久事实权威。

## 11. 实施状态与待验收边界

2026-10-26当前：Pixiv client/DTO/typed Query、独立WebKit Cookie会话、官方登录child panel、多页Inspector及共享下载/本地播放接线已写入。首次会话准备由同一个在途任务合并；已登记的下载在准备完成后绑定实际scope，避免持久Cookie初始化把自己的首次请求撤销。重试沿同一下载入口，账号变化只撤销旧作用域；作者首页真正刷新才更新ID快照，分页继续复用它。

未安装未经实测的“当前账号身份”探针，默认不会声称authenticated；登录窗口不注入表单、不读密码，用户在官方页操作。匿名真实原图GET、ImageIO读取与离线记录重载已验证；真实登录、持久账号切换/失效、真实多页作品翻页和systemStill实际应用仍未覆盖；原生单页Inspector及作者返回已完成本批整合验证。单张解码成功不等于所有格式的视觉质量均通过，Cookie存在或匿名成功也不代表认证可用。

用户已恢复测试/验证，两专项合入后现已基于`2fb50b5f1`重新接线。保留新版Steam参照的网格、背景、切换状态与模态规则，Pixiv独立官方登录面板沿用同一共享材质和控件规范。首个整合快照的Debug/Release通过不代表随后候选或新UI已验收。共享阶段收据、测试纠偏、Git交接与剩余验收只维护于[Wallhaven方案§9](wallhaven-online-browser-design.md#9-当前实施收据与下一批入口)，此处不复制门结果或另造执行计划。

## 12. 后续完善的来源合同

2026-10-27从`492a64dc7`继续，公共范围和执行顺序归[Wallhaven方案§10](wallhaven-online-browser-design.md#10-492a64dc7-之后的功能完善)。

- Query增加最新/最早、AI显示/隐藏、安全/账号允许内容；只发送当前模式实际消费的参数。搜索继续使用服务端lastPage，已有匿名P0真实响应带该字段，不因猜测改用total推导。搜索match仅在请求格式有实据时开放。
- 作者列表沿现profile/all快照和24项批量读取，按ID新旧排序；类型、AI和分级仅收窄本次真实返回项，继续保留服务端续页，不自动遍历整位作者填满筛选结果。无符合项但还有next时明确提供继续加载。未知AI/分级不冒充非AI或安全内容。
- 账号只认官方主文档明确当前用户信息（如meta-global-data.userData），不认作品作者集合、Cookie存在、公共作者接口成功或URL跳转。null可确认匿名，缺字段/挑战/损坏只标记未知。当前主文档metadata随显式关闭移交：先撤销旧scope、同步Cookie，再保留这份已确认身份，不另请求首页；新导航清掉旧文档信息。缺少确认信息时，仅对会话候选后台按需恢复一次，不能让preparePixiv等待首页下载，不给每图/每页新增认证关卡。
- 当前账号信息只服务展示和显式账号切换缓存清理，不升级为图片浏览、下载或本地播放许可；真实权限继续由站点响应裁决。保留唯一Cookie三方合并、scope和传输退役owner，删除不再有消费者的身份注入接口或重复初始化，而非添加第二认证服务。
- 账号菜单复用可信name/id，提供本人作品与官网个人主页；显式刷新沿原身份metadata任务，网络失败保可信身份，不因普通打开菜单重新认证。筛选复用共享checkbox网格，内容范围仅在搜索/作者页出现；详情作者pill与两按钮排版、首屏加载标准归[UI20](main-window-playlists-redesign.md#ui-online-panels-twenty)。
- 必须补已登录/匿名/未知metadata、作者数据空类、筛选后空页仍有next、新旧排序、取消和旧scope回包反例。真实登录、会话持久化、受限内容及站点HTML字段仍需原生实际操作，不以合成fixture替代。

本轮主窗口控制规范及新实施队列统一见[UI专项M01–M16](main-window-playlists-redesign.md#ui-simplification-sixteen)：空格预览改原asset高清原字节临时文件，不入库；两键bar、返回/刷新、通用下载入口与sheet样式沿该唯一设计，本文仍拥有来源API/账号/发布边界。旧2048缩略图PNG预览的已验收结论不代表新原图链已验证。
