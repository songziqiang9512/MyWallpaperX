# 主窗口与播放列表基础改造记录 · 2026-10-25

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**

截止日期：2026-10-25。保存基础改造前源码快照、原 P0–P7 施工安排、W01–W22 有界记录、B1–B5 证据、共享卡片提取步骤及本轮只读审计/初版实施安排；原文中的“当前”“下一步”“唯一完成状态”只描述各自记录时点，不产生现役任务。

当前规范、待实施 U/A 要求、R0–R4 状态与 W22 未验收边界只查[主界面改造方案](../../development/main-window-playlists-redesign.md)。B1 的用户验收不等于整个专项验收，B5 的构建/签名/代表媒体运行也不等于全部作品兼容、性能、远端账号写入或最新视觉目标验收。

以下载荷保留迁出段落原文，仅修正相对链接的基准目录；归档前载荷与迁移后载荷各自的身份登记在 document_health 基线。重复的历史规范只用于解释当时决定，不替代当前方案。

<!-- preserved-body:start -->
### 原方案取舍表

| 方案 | 收益 | 代价 / 裁决 |
|---|---|---|
| A：只改侧栏文案和排列 | 改动小 | 仍是视频标签与图片标签两套数据，混合收藏/历史/列表无法成立；不采用 |
| B：共享内容引用与用户关系，复用原服务和 Steam 卡片 | 能统一组织和交互；播放器与下载仍独立；可逐片迁移 | 需完成关系迁移、来源别名和命令适配；**推荐且作为本文主方案** |
| C：重写完整媒体库、所有下载器和播放器 | 表面上全统一 | 侵入现役 Scene/Web/Video、迁移和回归面过大；不采用 |

### 2.2 2026-10-24 源码核对结果

侦查基线 `ae0ac798c`，开始时工作树干净。下表记录改造前静态事实；链接指向当前接替 owner，已退役文件仅保留历史名称。最新实施与有界运行证据以工作卡和文末为准。

| 当前事实 | 实际起点 | 本次应改变 / 应保留 |
|---|---|---|
| 侧栏有库、标签、图像、Steam、在线等分组，选择值携带视频 tag / silTag | 原 AppKitSidebarNode 已退役，现[节点构建](../../../MyWallpaperX/Shell/WallpaperLibrarySidebarController.swift)、[PageID](../../../MyWallpaperX/Models/WallpaperLibraryPage.swift) | 改为页面与 PlaylistID 路由，名称不再作为 identity |
| DetailHost 按来源创建不同网格；模块身份同时参与工具栏和菜单 | [DetailHost](../../../MyWallpaperX/Shell/AppKitDetailHostViewController.swift)、原 ModuleRouting 已退役，现[装配](../../../MyWallpaperX/App/WallpaperLibraryWindowComposition.swift)、[菜单](../../../MyWallpaperX/App/MainWindowMenuCommands.swift) | 新混合页不能假装成视频库；显式页面命令能力替代来源布尔组合 |
| VideoWallpaper 持有 favorite、tags；SILWallpaper 有 tags、lastUsed，无 favorite | [视频模型](../../../MyWallpaperX/Models/VideoWallpaper.swift)、[图片服务](../../../MyWallpaperX/Modules/StaticImageLibrary/Core/SILService.swift) | 用户关系统一存储；来源服务继续拥有文件、索引与元数据 |
| 最近使用只存 VideoWallpaper 快照，上限 25，按路径去重，在发起 setAsWallpaper 时更新 | [Manager](../../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager.swift)、[最近持久化](../../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+Persistence.swift)、[发起播放](../../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+WallpaperApplication.swift) | 改为混合引用、50 条、成功提交后更新；不能仅把常量改成 50 |
| 图片 lastUsed 尚未在应用成功后完整记录，工具栏主动隐藏该排序 | [图片工具栏](../../../MyWallpaperX/App/WallpaperLibraryWindowToolbar.swift)、[静态应用](../../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+RuntimeSwitching.swift) | 接入统一成功事件；不拿导入时间冒充最近使用 |
| Steam 下载与 Pixabay 下载各有页面、选择和详情；Pixabay 当前是视频源 | [Steam 下载](../../../MyWallpaperX/Shell/WallpaperLibraryGridController.swift)、[Pixabay 下载](../../../MyWallpaperX/Shell/WallpaperLibraryGridController.swift)、[Pixabay 服务](../../../MyWallpaperX/Modules/OnlineLibrary/Core/OnlineLibraryService.swift) | 统一页面，不扩建 Pixabay 图片搜索能力，不移动真实下载目录 |
| Steam 卡片内有玻璃 bar、标题、播放/下载/进度状态，心形实际是订阅 | [现役卡片](../../../MyWallpaperX/Modules/SteamWorkshop/UI/AppKitSteamWorkshopBrowserItem.swift)、[呈现](../../../MyWallpaperX/Modules/SteamWorkshop/UI/AppKitSteamWorkshopBrowserItem+Presentation.swift)、[玻璃 bar](../../../MyWallpaperX/Shared/Components/WallpaperCardSupportViews.swift) | 提取真实呈现职责；心形改为喜爱，订阅单列；不把整个 Steam service 搬进 Shared |
| 主工具栏在 Video 控制器内创建，各模块保存/恢复不同 item 数组 | [Video 工具栏](../../../MyWallpaperX/App/WallpaperLibraryWindowToolbar.swift)、[Steam 布局](../../../MyWallpaperX/Modules/SteamWorkshop/Toolbar/SteamWorkshopToolbarController+Layouts.swift)、[在线工具栏](../../../MyWallpaperX/Modules/OnlineLibrary/Toolbar/OnlineLibraryToolbarController.swift) | Shell 统一装配一份 toolbar，模块提供状态和动作；迁移时撤销旧数组恢复协议 |
| 全局上下张已有 Video + 工坊 Web/Scene 环形序列，工坊视频因导入 Video 而避免重复；不含图片/播放列表 | [跨引擎导航](../../../MyWallpaperX/App/CrossRuntimeWallpaperNavigator.swift) | 迁移该序列 owner，不能再加第二套全局导航 |
| 自动 timer 目前要求 Video active/requested，Web/Scene 提交会停止它 | [播放设置](../../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+PlaybackSettings.swift)、[提交出口](../../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+RuntimeSwitching.swift) | 扩展同一轮换调度职责，不能只在新 UI 加四类型按钮 |
| 产品切换已经是 Manager 唯一事务；三类型进程、静态系统应用各有执行 owner | [生命周期设计](../../architecture/playback-lifecycle-transaction-design.md)、[装配](../../../MyWallpaperX/App/MainWindowCoordinator+PlaybackRouting.swift) | 保持唯一切换权威、失败回滚、实际可交接标准和资源租约 |
| 个人设置 schema5 导入/导出是正式用户功能，包含 Video 喜爱/标签和 SIL 标签；清缓存与重装级 reset 另有入口 | [设置装配](../../../MyWallpaperX/App/SettingsWindowController.swift)、[个人设置](../../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+ProfileSettings.swift) | 协议、入口、缺失引用和恢复须一起迁移；不能降格为开发工具 |
| 原初载会清理缺失文件并回写；Video 还有完整 fallback、启动编辑日志和 WAL SQLite | [初载合并](../../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+InitialIndexLoad.swift)、[持久化](../../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+Persistence.swift)、[索引](../../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperIndexStore.swift) | 首次迁移在破坏性清洗前捕获一致输入，不能只等初载完成或复制主数据库 |

## 10. 分批执行、工作卡与停止条件

以下按依赖关系分批实施。替代链闭合后逐一删除旧调用者/入口/死辅助代码，不能为旧测试残留产品无调用API；共享规则须有真实消费者，页面操作链需覆盖详情、菜单、快捷键和异步固定目标。P2 的独立呈现片可先于 P1 开始：只共享原生玻璃、标题和尺寸规则，将既有视频卡改为方形并保留原播放/收藏 owner；不提前开放新关系或混合路由。P1 迁移与 P6 播放仍须各自验证。每片先固定输入与 owned paths，再实现、补最近门、隔离 Debug 构建和必要 UI 操作；共享 JSON 由同一整合者写，保留并行 Scene 会话最新改动。存在并行源码修改时从固定提交 + 精确 owned diff 的隔离源验证，不能混入无法归属的构建输入。

| 阶段 | 可供用户观察的最小结果 / 责任面 | 前置、验证与回退 / 停止条件 |
|---|---|---|
| P0 设计冻结 | 本文、已确认交互选择、所有页面工具栏/卡片/迁移规则齐备 | 用户已授权实施；登记改为 approved，不改变已批准旧能力 |
| P1 引用与迁移 spike | 离线隔离数据中，视频/图片同名标签得到一个混合列表；规范 alias/喜爱/最近可查询 | 先用旧索引副本与 fixture；验证可重入、失败原子性、空标签/孤立关系/同数跨来源；不能证明不丢关系即停，旧产品 UI 仍可用 |
| P2 共享卡片单纵片 | Steam 自身先改用提取后的 Shared 呈现，外观/bar 与当前一致；新心形语义先在受控夹具验证 | 先冻结原 bar 全状态，含旧版可播+更新失败/进度和批量重试；订阅不冒充 favorite 字段；原关系/详情接线未迁好前不单独上线新心形语义 |
| P3 统一页面骨架 | Shell 唯一 toolbar、PageID、页面命令目标和三组侧栏；旧内容服务仍通过适配工作 | 菜单、快捷键、选择、搜索/缩放/滚动回到同页面；先保留内部旧路由适配，不同时跑两份 toolbar 恢复逻辑 |
| P4 用户关系与混合页组织验证 | 目录、列表/喜爱组织、详情、正式设置导入导出可在隔离受控入口验证；新关系库唯一写 | 新旧组织按钮/菜单全部接同一 owner，覆盖清洗前迁移、profile、reset 与 alias；混合页正式播放入口等待 P6，不让旧 Video-only 调度接手新混合来源 |
| P5 下载与浏览整合 | 我的下载联合两来源；原 Steam 工具栏骨架、统一方卡与原 Pixabay 详情 | 原 Pixabay owner 先补真实删除结果；保留失败可见边界、账号权限、更新双状态/重试能力；不造第二下载器/扫描器，不靠集合消失宣告物理成功 |
| P6 混合轮换与成功历史 | 一份来源状态/轮换时钟驱动四类型；最近成功去重 50；P4/P5 新页正式播放一起放行 | pending/committed 来源、typed cause/原导入 gate、Stop撤权、静态toggle、恢复关闭和所有失败后继先闭合；12 个有向切换及独立运行通过才撤原调度权，不能双运行或漏旧 fallback |
| P7 验收与退役 | 用户确认整体效果；旧 tag/silTag UI/重复卡片/旧数组 toolbar 协议和无消费者关系代码退出 | 全页面/迁移/真实代表媒体矩阵和独立最终审查；文档/调用/测试登记同步；不削弱旧有效断言，不以 UI 通过替代播放证据 |

P3–P5 可在隔离开发路线验证布局/组织，但新的混合页面播放、心形单写链和最终侧栏切换须与 P6 形成同一完整试用构建后开放；旧产品入口在此之前保持原可用路径，不以禁用用户自动切换、让混合视频落回旧 Video-only timer 或展示假入口绕过依赖。受控路由只有一个产品输出决定，验收后按 P7 撤旧路由；不是长期双实现。公共卡片/关系与 toolbar 合同由单一整合者维护，独立 provider/夹具可并行，不能同时改共享 store/schema、bar 和菜单 owner。

不预先承诺总工期或“必然减少多少行/提升多少 FPS”。P1 先确认真实旧数据与 alias 完整度，P2 确认共享卡片能保持状态边界，再评估剩余成本；若需要重写 runtime、长期双存储或每次查询全磁盘扫描才能推进，停止扩大改造并回到本文调整设计。达到用户既定页面与验收结果即收束，不自动开启下一批 UI 扩展。


### 持续执行工作卡（唯一完成状态）

基础实现 goal 已完成；下列 W 卡保存截至 B5 的有界实现与回归记录，不以代码落地代替最终用户验收。B1 已验收，不重复实施。2026-10-25 新的七项反馈与审计缺口见 §13；它们尚未实现，原 W08–W14/W21 的通过不能覆盖这些新目标或静态风险。W22 仍待最终验收。本轮只审计与修订文档，继续使用隔离分支，不暂存/提交，不启动 App。

| 卡片 | 交付与对应规范 | 状态 / 完成依据 |
|---|---|---|
| W01 | §7.2 规范引用、列表/成员/locator/alias/快照值合同 | 已完成：基础值与不透明UTF8 identity门通过、独立复审接受 |
| W02 | §7.2 关系 SQLite 单写、原子命令、顺序/喜爱/最近50、别名合并与reset代次 | 已完成与独审：SQL/故障/别名、最近、expected-state撤销、profile/reset35行为通过；实际四类型批量喜爱与Undo→Redo通过 |
| W03 | §9.1 清洗前一致快照、完整 fallback 优先、WAL 与有序启动日志 | 捕获19模式/启动11模式及独立复审通过；App已在原服务构造前准入，失败只读防护及最终隔离Debug启动已验证 |
| W04 | §9.1 同名/空/孤立标签迁移、离线引用、可重入发布与故障恢复 | 已完成：映射6/发布14模式、冻结呈现seed边界与启动恢复通过；旧关系写已退，重跑仅用冻结输入，不重读live旧源 |
| W05 | §7.1–7.3 四来源 provider、可用性/可信alias/失效投影 | 已完成与独审：四来源live/可信backing、扫描/动作前投影、未知/成功空门通过；缺失本地定位32与下载恢复28反例闭合（含可信backing/缺locator），实际Video/SIL定位及重启保关系通过；Pixabay远端写操作未执行 |
| W06 | §7.4 视频方卡、玻璃/标题/尺寸共享纵片 | 完成并由用户验收；B1 记录见文末，23项定向回归与 Debug 通过 |
| W07 | §6/7.4 图片/Pixabay/Steam 完整共享卡与唯一心形语义、订阅分离 | 已完成与独审：四来源方卡/共享bar、Adapter27、心形新Store与独立订阅已接；实际四类型批量喜爱通过；静态图三态三项native门与实际App“已应用，点按重新应用”通过 |
| W08 | §4/5 Shell 页面ID、三组侧栏、状态恢复与唯一工具栏骨架 | 已完成与独审：唯一Shell/toolbar、呈现69及冻结sort/zoom→UUID seed29通过；十类页面/目录数量与正常Debug已实际检视；最新App三种远端页AX未知不报0已核 |
| W09 | §5 我的视频/我的图片与原工具栏、导入/搜索/排序/缩放/详情接线 | 已完成：导入/查询/搜索/排序/缩放及旧时间/profile排序门通过；显式图片导入由原JSON owner确认持久化后发成功，写前失败和写后同步未确认分开，原actual-worker24行为通过；实际本地页/原详情/QL及Video/SIL原生定位通过 |
| W10 | §5 联合我的下载、原 Steam 工具栏与 Pixabay 原详情、真实批删结果 | 已完成：联合页按原Steam工具栏装配账号/任务/筛选/排序/删除与逐项回执；账号/陈旧任务/清cache门及独审通过，实际下载页两项可见；Pixabay原详情以原门限定，未做远端下载写入 |
| W11 | §5 创意工坊/订阅/Pixabay 浏览与原筛选/下载/账户/重试入口 | 已完成：原发现/个人订阅/Pixabay分类、排序、搜索、账户和下载链保留，实际浏览页与未登录提示已检视；已下载Steam浏览组织菜单独审及3门通过，不执行远端订阅/下载写操作 |
| W12 | §5/6 所有列表目录、新建/改名/排序/侧栏显隐/列表封面 | 已完成与独审：原目录fold/drop/anchor/native拖排门与Artwork25通过；实际中文emoji新建→重命名→四类型复制→删除返回目录通过，固定首卡/数量及原资源保留已核 |
| W13 | §5/6 混合列表/特别喜爱、成员组织/多选/拖放/删除语义 | 已完成与独审：共享Grid/列表头/添加/侧栏拖入/删除及导入alias门通过；实际四类型一次加入/批量喜爱及Undo→Redo通过；外拖固定页/epoch/只读72行为、原生网格、非阻断提示门通过；最新App从内容新建留页→提示打开→删测试列表通过 |
| W14 | §6/7.3 原菜单/快捷键/文本优先/Quick Look/Inspector固定目标及撤销 | 已完成：稳定ID/文本优先27、固定动作/真实Undo10、Inspector/QL25+原面板11通过；实际图片原详情/QL及喜爱Undo→Redo通过，远端主菜单固定目标补齐并独审 |
| W15 | §8 统一候选与 pending/committed 来源、原票据关联、成功事件 | 已完成与独审：实际Manager51/导入准入29通过；普通桌面12方向逐条核txn与sequence同票据/source/cursor、实际窗口与旧PID退出；代表内容边界见B5 |
| W16 | §8 图片/视频/Web/Scene 顺序随机轮换、单调时钟、失败保旧/来源约束 | 已完成实现与有界运行：Sequence/Deadline110及原单timer/pause/ended/lost门通过；普通12方向与8秒四类型顺序自动循环已观察；修后原Inspector Video Stop退出/ACK清空已实测 |
| W17 | §8/9.1 成功去重最近50与旧恢复/导入 gate/全局前后切换等价接线 | 已完成与独审：唯一恢复40、旧视频后备/新版四来源恢复和全局导航已接；实际反复轮换后最近仅4个规范引用，50上限/失败与恢复不计由原门反证 |
| W18 | §9.3 schema6 设置导入导出、v1–5兼容与跨owner可恢复应用 | 已完成与独审：正式schema6/v1–5恢复55及Videos sort35、精确ReferenceDate/跨存储故障和epoch续作通过；实际设置入口可达，未对真实用户执行导入或reset |
| W19 | §9.4 cache/reset/退出flush，迟到任务撤权、重置不复活 | 已完成与独审：reset/退出撤权、真实Store/quit先flush后teardown门通过；正常退出/helper清空已测，Stop后持续浏览/组织未复活；真实用户reset未执行 |
| W20 | §9.2/P7 退役旧关系写与旧tag/重复呈现/路由，无长期双 owner | 已完成并独立交叉审：旧四来源壳/源关系写/Steam selection-display-sort退役；索引21/删除12+69/49、慢文件单flight/账号瞬态/清cache重载/陈旧清理通过；旧有效测试迁共享worker40及键盘15行为，原Catalog断言保留 |
| W21 | §11 A–R 全页面/迁移/四类型交接/失败反例回归与稳定合同同步 | 已完成独审与有界回归：迁移/来源/设置/原卡、菜单/三态native、普通12方向与自动轮换至epoch20、十类页/组织/QL通过；最终补闭外拖/成功反馈/本地定位/下载恢复及SIL ACK；最新Debug实际两来源定位、喜爱/成员保留、视频桌面播放→Stop清空及exit0/重启通过 |
| W22 | 最终隔离 Debug、签名/源码身份/实际UI确认、产物清理与统一用户验收 | 基础 Debug 已交付，**未最终验收**：1219输入冻结、构建/严格签名及隔离退出重启证据仍只覆盖 B5。随后按用户指令让出另一会话测试窗口；U01–U07 与 §13 审计项待后续空窗实施/验证，不能标为整体完成。保一缓存，无暂存提交；本轮不构建、不测试、不启动 App |

设计审查已完成范围：独立子代理交叉核对来源调用、原功能入口、用户选择一致性、迁移和生命周期反例，修订后再复查方案与索引/链接/预算/设计登记。它证明设计缺口被审查和补全，不证明尚未实施的产品已通过回归。此前设计审查未做产品构建或运行；实施与验证状态记录如下，不将设计通过当作产品通过。

### 已验收：B1 视频方形卡与共享呈现

- 基线：`ae0ac798ca712e724a82fb1d06e1e148565b8a6e`；隔离分支 `MWX/main-window-playlists`。原工作区及并行会话改动保留。
- 本批：提取既有 Steam 玻璃 bar、滚动标题、进度语义色与 bar 尺寸规则到 Shared；Steam 保持原呈现/业务接线；视频库采用等比填充方形封面、同材质内部 bar、原本地收藏和播放/停止。元数据保留在提示与原详情面板。
- B1当时未开放新侧栏、联合下载、标签迁移、新关系库、混合轮换与Steam心形切换；后续当前状态以工作卡为准。
- 已验证：本批卡片/进度/详情/订阅入口等 12 个定向测试通过；另有视频导航、滚动与播放状态发布共 11 个测试通过（视频卡片门另计，避免重复）。视频完整卡片含 31 条行为结果与命令适配 7 条反例；保留原断言并新增快速 hover 重入、浅色白描边、原生按钮/复用固定目标及横竖图裁切。Steam 原测试在基线也因窗口未激活/真实鼠标不命中而失败；测试夹具增加真实 App 激活与可控指针，原 CLI 返回码与动画断言保留，原按钮矩阵通过 LaunchServices 补跑；产品不增加抢焦点逻辑。
- 治理验证：文档角色/链接/精确预算、设计门、代码健康与工作区残留检查通过；验证路由和设计门的 70 个现有测试通过。9 个变更 Swift 路径均有现役定向测试映射；映射不等同完整运行所有关联模块。
- Debug：首次完整与最终增量构建均成功；最终源码哈希复核一致，签名深度验证通过。实际启动最终 App（PID 99914），确认方卡与内部 bar 可见，资料库为独立 HOME 内的 12 份视频副本；未运行新混合轮换、全库性能或新侧栏验收。既有 `InspectorBadgeView.borderType` 弃用告警不属本批改动。
- 试用 App：`/private/tmp/mwx-main-window-ui-debug-4hopmbb7/DerivedData/Build/Products/Debug/MyWallpaperX.app`；同根 `RuntimeHome` 为隔离资料库（约 198 MiB 媒体）。仅保留这一份增量构建缓存和在用 App/副本，供后续批次复用；本批日志/输入哈希在忽略的 `.artifacts/main-window-redesign/b1/`。未暂存、未提交，原分支工作区不改动。

### 基础实施记录：B2 关系基础与 B3 呈现铺开（2026-10-25）

- B2 独立关系链已支持事务命令、可信别名归并、成功去重50条、reset撤权；清洗前捕获保完整 fallback（含空）、WAL一致备份、原有序日志与9键无凭据偏好白名单。损坏且被完整fallback替代的SQLite仅保原始字节并明确非一致逻辑备份，权限错误不能按空库处理。
- 迁移UUID映射持久化后原子发布；checkpoint/目录sync失败、亚微秒Date往返、丢映射、已有坏/新schema final等反例已补。不会覆盖已发布库及后续用户编辑。B2当时尚未接入App启动；B4准入接线见下，不冒充已升级真实资料库。
- 混合查询保不可用成员/locator、规范身份与来源命令身份，未知字段始终置末，最近先取50再筛选；统一成功时间排序不借用旧导入时间，支持中文来源和列表名搜索。
- B3 SIL采用原生Flow方格与共享玻璃bar，原图/Quick Look不裁；原缓存、取消、详情/多选保留。独立审查确认瀑布流专用oracle退出后，元数据/无重复invalidate/缩略图断言保留并补真实方格与按钮命中。Video同形描边挡按钮也已修复并补真实窗口hitTest。Pixabay已独立复审，旧扩展播放热区已退役，标题/提示真实控件断言及离屏动画停止/恢复已补；Video/SIL同形链也已完整退役手写播放命中/索引分发，仅保原生按钮固定ID回调；两来源跑马灯随原显示需求停/恢复，后台更新不重启。
- 最终关系/捕获/迁移/投影/查询/Controller组合13项通过（发布含13模式、查询30行为、Controller17行为）；SIL四模块及Pixabay16项独立门通过。同票据导入16行为与原autoplay/导航/资源Lifetime/网格发布门通过。首次与最后1201份源码固定的签名Debug增量构建均通过；最终App已实际启动(PID21799)，隔离HOME中12视频副本及5生成图片，方格/图片选择与原Inspector已实际检查。关系启动接线/联合下载/新侧栏/混合轮换未开放，不作整体验收。
- 本专项继续在原隔离工作树推进；当时未与其他会话联系，现按最新授权协调构建/测试窗口；所有修改未暂存、未提交。沿用 B1 同一增量缓存/隔离HOME（新增约283KiB生成图片）；B2/B3最终日志/源码身份/启动收据留在忽略的专项产物目录，已清本轮过时重试输出，随任务结束清理；工作卡的未接线边界仍为待办。

### 基础实施记录：B4 启动准入与页面/目录接线基础

- 关系库先于全部旧服务构造准入；已发布final（含reset）不再读取旧源，saved input/map续作保UUID；捕获先持久输入后标完成。失败阻止旧索引/图片/偏好导入及异步清洗回写，仍可播放已入库项；这些旧链过渡gate随W20退役，不作新永久双owner。
- B4当时共享查询解析器服务目录与内容页；单一Published呈现值保页面/query/selection一致，resetEpoch撤销所有旧回执。来源适配低频解析原事实，无query/progress逐项磁盘探测；当时未接的Pixabay记录与可信backing已在B5闭合；Scene保原低频主线程验证，不宣称完全后台或性能提升。
- 目录采用原生Flow/ClickGesture/AX，固定首卡不参与排序/计数；真实窗口点击、双击、键盘、菜单UUID、native drag、删焦点和提交前后reset均验证。共享组织sheet只拒空名，原子副本保四类型离线成员/顺序/locator且不动媒体或其他关系。实际主Shell仍沿旧入口，目录/新页面尚不当作整体验收。
- 定向与独立审查已通过：启动11/发布13/捕获19模式，原索引17+3失败只读，导入22、呈现43及原查询30行为；目录/Controller原断言保留并补四类型离线复制和reset变异拒错。1210份源码冻结的最终签名Debug构建/启动通过（PID34559），隔离库schema1/revision1、3列表/5成员/1喜爱/17locator均已实际只读核对，窗口切页正常；无新编译告警。最终日志/身份收据在忽略的b4产物目录，继续沿同一缓存；未暂存、未提交。

### 基础交付记录：B5 统一网格、来源/播放与主窗口装配（尚未最终验收）

- 原生Grid/四来源Adapter、唯一Store/Query/Presentation/Commands与原Inspector/QL已接，旧壳/关系写/源display-selection-sort和3个零产品caller包装已退，账号/陈旧任务边界经独审。共享AX/标题/复用三门、Steam菜单3个headless及2个native、静态“已应用”三态3个native通过；三远端页AX未知不报0已实测。最终对抗审补外拖72行为（原57保留）、原生网格/非阻断创建反馈、本地定位32/原导入24/下载恢复28反例；原生创建留页→提示打开、Video/SIL移索引→占位→原生定位→成员/喜爱保留及重启已实测。SIL写后ACK失败不伪称磁盘回滚；Steam可信backing可恢复，独立video不猜作品号；Pixabay冷缺原元信息仅原网页，不造下载URL。最终1219输入冻结增量Debug/严格签名通过，产品源码未再变化。
- 普通隔离App的Video2、生成图、自编Web/双色Scene四成员已跑12方向，逐条核ticket/source/cursor、实际桌面窗口和旧PID退出；8秒自动循环采样至epoch20，无Stop断点命中。此前一次菜单自动化后停止原因未定，保最小记录，不作显式Stop证明；另实际原Inspector Video Stop后txn/sequence/退休/端点/执行/timer全清、不复活，负控4失败/修后组合10行为通过；最新定位后视频也实际桌面播放、Stop清空与正常exit0，重启12视频/5图/5喜爱/混合4成员/目录4列表持久保留。十类页/四类型批量组织、中文emoji增改复制删除、图片QL及Undo→Redo已测。仅代表副本/生成内容，不代表全作品兼容、性能或远端账号写入。工具曾意外无隔离重开，已退出并核真实源1113记录旧字段/引用与备份一致，仅全NULL新时间列及关系/恢复元数据；原备份保留，退出后不读AX。原桌面已恢复；保同一缓存/RuntimeHome、必要有界证据与最终隔离App供用户验收，调试器/测试helper已退出；不暂存提交。


### 13.1 本轮边界、证据与两条独立清单

**本节记录已完成的只读审计阶段。** 该阶段只改本方案与精确正文预算，没有构建、运行产品/单元/native/文档门、启动 App、操作 UI、采集新截图或改产品/测试代码。三名独立子代理分别检查视觉/布局、工具栏/缩放、产品入口/共享边界，由整合者复核后修订；两份材料已分开交付。后续实施按 §13.5 记录，不把新的实施事实倒灌成当时已有证据。

证据分级：U 表是用户刚刚实测报告的要求；A 表区分“当前源码链已见缺口”“静态风险待运行反证”“视觉细化建议”。本轮没有新的运行证据。用户最初提供的两张 Music 图是目标参考；B5 的 `runtime/screenshots/final-main-window.png` 仅是历史目录外观参考，不能证明本轮现象、深浅切换、hover、键盘或窄窗表现。其他页面无同状态新截图，不凭空判定其像素效果。B1/基础 W 卡的既有回归仍有其原范围，但不覆盖本节新要求；最终是否保留视觉微调由用户观察裁决。

保留的优点：原生三组 source list、方形媒体封面、卡片 bar、系统强调色、四来源共用关系/播放合同已经形成；此次细化应修层次、度量和入口投影，不重写数据迁移、下载器或播放事务。优先选择“共同度量与状态投影 + 小范围原生布局修正”；相比逐页补数值，避免再次分叉；相比重写全窗口，验证面更小。不新增首页、底部播放条、推荐内容、全局搜索或颜色偏好面板。

### 13.4 后续实施顺序、共享合同与停手条件

**本节定义空窗后的执行顺序，不表示各项已经通过。** 两条清单分别推进/勾选，批次可以共用同一真实 owner 的修改，完成状态仍逐项回写 U/A。只读材料已交付，后续在明确协调到空窗后推进，不占用另一会话未释放的构建/测试窗口；实际进展见 §13.5。

| 后续批次 | 最小可见结果 / 对应清单 | 后续必要验证与停止条件 |
|---|---|---|
| R0 当前输入域反例 | A01：先确认 sheet 与主菜单是否会误作用背后页面 | 在隔离库用真实菜单 keyEquivalent 反证，不能以直接 Grid.keyDown 通过代替。若证实缺口则最小修域，若系统原生机制已阻断则记录证据、不惯性加防护；之后才继续测 picker 的选择/导入/缩放。主窗文本、设置及真正全局导航不回退 |
| R1 统一网格与密度 | U02/U04/U07：全页同 Steam 度量、默认 5 列/3–6、缩放方向与顶部恢复一致 | 先改纯共享 metrics 和页面呈现偏好，再让统一/Steam/OL/目录/picker 消费同一结果，退出旧两种计算。保留预取/GIF/拖排/分页与原断言；宽度×列数、偏好兼容、首行/中途锚点、键盘行跳、原生滚动回归后增量 Debug。任何双算宽度、卡片溢出或首次点击不变化先修，不扩展成新布局引擎 |
| R2 侧栏与列表封面层次 | U01/U05/U06；同职责可合 A06/A08/A10：侧栏染色可见、紧凑头、堆叠媒体卡、名称对齐 | 原取色来源/0.75 s/原生中性选中与无障碍回退保持；头部 fitting、深浅/长名/空和1–4图/异步复用实看。只更新原 Artwork/Shared/Shell owner，不新缓存；若改变预览/引擎调用则回退超范围部分 |
| R3 工具栏与真实命令域 | U03；A04/A05/A07/A09/A12：职责分组、原生 overflow、动作文字/目标准确、补已下载 Pixabay 组织入口 | 保持 R0 已证的输入域边界，不用焦点 hack。十类页最小900宽/普通1200/大窗1440、不同sidebar宽、每个overflow与文本快捷键逐项操作；远端账户写入仍需本轮明确范围，不为测入口盲目订阅/下载 |
| R4 状态反馈与最终视觉复核 | A02/A03/A11；A13/A14先看再决定：错误不是加载、无结果不是空库、已有成员和当前目标清楚 | 首扫失败/暖快照失败/重试成功、目录0匹配/只读/未知schema，保原数据。全页同窗口前后图、深浅/非红强调色/减少动态与透明度/6列文字命中验收；恢复输入域正确后再测功能。文档预算/链接等门也在窗口后执行，旧测试断言不削弱 |

工具栏分组目标如下，`｜`表示原生组间空隙，不是手画分割线。每页保留 §5.1 已列的全部来源功能；必要时将低频组织动作放稳定 More，不能删除真实入口来缩短 toolbar。移除图标随语义：列表/最近为关系移除，喜爱为取消喜爱，本地/下载文件管理沿原政策，不全部用 trash 暗示删文件。

| 页面 | 左导航和标题之后的组序（右侧最后为搜索） |
|---|---|
| 我的视频 / 我的图片 | 导入 ｜ 选择、上下张 ｜ 移除、喜爱、添加列表、更多 ｜ 排序 ｜ 缩放两段 ｜ 搜索 |
| 我的下载 | Steam账号、下载任务 ｜ 选择、删除本地下载、更多 ｜ 来源/类型/状态筛选、排序 ｜ 缩放两段 ｜ 搜索 |
| 最近使用 / 特别喜爱 | 播放、随机 ｜ 选择、关系移除/取消喜爱、添加列表、更多（最近另保喜爱；喜爱页不重复一颗相反含义心形） ｜ 筛选、适用的排序 ｜ 缩放两段 ｜ 搜索 |
| 自建列表 | 选择、从列表移除、喜爱、添加列表、更多 ｜ 筛选、排序 ｜ 缩放两段 ｜ 搜索；播放/随机/添加壁纸仅头部一份 |
| 所有播放列表 | 新建列表 ｜ 排序 ｜ 缩放两段 ｜ 搜索；改名/复制/删除仍固定目标右键或键盘 |
| 创意工坊 / 工坊订阅 | 账号、下载任务 ｜ 适用的作者返回/个人列表/热度时间窗 ｜ 原排序、筛选 ｜ 缩放两段 ｜ 搜索 |
| Pixabay | API设置、刷新 ｜ 分类 ｜ 原排序 ｜ 缩放两段 ｜ 搜索 |

密度只有一个**规则**和每页一个**偏好**，不是一个所有页共享的可变值。建议由原 Presentation 持久化主页面 `preferredColumns`，App 将值/改变命令注入来源 Grid/Toolbar；模块继续拥有远端查询/分页，Shared 只算纯度量，不查 `.shared` 或递归遍历全窗口猜当前网格。内嵌 picker 复用规则，初始5列，其临时选择/缩放不覆盖主页面偏好；临时缩放入口与 A11 在 R4 同批接入，沿 R3 的共享原生两段控件，之前不能把 U04 标为全范围完成。Inspector 是 overlay，实际 clip 宽不因其出现重复扣减。

替代消费者接好后，逐一退役旧 Steam/OL 的 zoomOffset 发布/写入与原 GridLayoutHelper 的宽度基础列数消费者；特别是 `onlineLibrary.gridZoomOffset` 不能再驱动新 Grid/Toolbar。旧原始偏好键可作为兼容审计输入保留，冻结迁移快照不动，但不得形成第二个现役密度 owner；无其他产品消费者的缩放辅助/订阅/旧测试形状同时退出，仍有独立职责的纯算法不为删名字硬拆。模块的远端筛选/分页/账号状态不迁到 Shared。

审计起点的 `wallpaperLibraryPresentation.v1` defaults key 和 synthesized QueryState Codable 是具体兼容边界：新增有默认值的非 optional 字段仍可能令旧 JSON 整体解码失败。后续在同一 Presentation owner 显式 `decodeIfPresent`，缺新密度键仅设5、已知 v1 读入后在**同一个 key**一次写 known v2；原 page、search、provider、kind、status、sort、ascending、legacyTimeOrder、scrollAnchor、目录anchor逐字段保留，不清整份 query、不重跑关系迁移。旧 offset 含随宽度基础列数/目标宽两种相反语义，不能盲目相加；本次明确新的默认5，只退役旧密度字段，冻结旧迁移输入不动。损坏/未来版本仍保原字节、按原只读恢复，不借 v2 覆盖。个人设置 schema6、UUID/alias、播放状态、远端账号/API 凭据不因 UI 密度调整而改变。

窄窗规则：请求6但实际只容5时保留请求；放大命令从**有效5列→4列**，不能先把请求6改5而画面不动；缩小仅在有效列数还能增加时可用。resize只更新有效度量，不写回偏好；一次命令后再按同一规则更新可用性/AX。主窗口支持范围内至少容3张100 pt卡；临时零宽/未挂载不参与判定。

滚动值仍归原 Presentation/query 与目录原 owner，在 known v2 兼容扩展为“真顶”或“引用/目录UUID + 相对视口偏移”，不是第二状态树。旧v1没有偏移，明确迁移约定为 nil/当前第一项引用按真顶，其余按引用+0恢复；这是有损旧呈现信息的确定性解释，不能声称还原旧未保存位置。新值能区分头部已滚走与完整顶部；旧首项已删除/重排时遵守原可见锚点后备，不猜媒体或改成员顺序。原远端浏览锚点与分页仍委托来源，仅接入相同顶部安全距合同，不把关系页的引用结构强塞给远端结果。

完成与停止：每批先写入实际状态，再做独立交叉审查；改代码后用精确来源的增量 Debug 与隔离库试用，报告用户可见前后差异，不把源码减少/构建成功当成美观或流畅已证。只读阶段未运行任何门；窗口释放后按影响面串行复用最近门，状态见下节。所有U项与必要A项闭合、用户实看满意后才更新W22；可选A08/A13/A14若收益不明确可记录不采用及原因。继续不暂存、不提交；保留并行会话改动，不在本批修改 Scene/Web/Video 执行语义。

本轮材料复审：三名子代理独立复读修订方案后，已纠正外框/前图度量混淆、旧滚动信息不可逆、异步封面缺失败收口、Pixabay 与 Steam 权限混用、无真实选择时的主菜单假目标、手动拖排作用域、旧缩放消费者退出、Codable/偏好键兼容及错误交叉引用。仅表示设计文字完成交叉审查，不代表这些待改项已修复或任何测试已运行。预算登记只覆盖此文的实际正文，原文档门待后续空窗补跑。

### 7.4 提取 Steam 卡片的具体方法

先把现卡片的输入、输出和状态测试冻结，再把**真正可共享的视图**移到 Shared：方形 preview 容器、白色描边、选择标记、玻璃 bar、标题呈现、进度、状态按钮与 hover 接口。Source adapter 继续持有 SteamWorkshopPreviewState、账号订阅和下载进度观察，向卡片投递值与回调；Video/SIL/在线 adapter 使用原缩略图 owner。

一份 `CardPresentation` 提供 title、thumbnail handle、favorite、selection、publishedAvailability、独立 acquisition/updateState、primary/secondary actions 和各自 progress；点击只上送 typed command。来源特有“书签订阅/查看作者/属性”作为可选动作描述，不塞入通用的 Steam 字段。通用卡片不得 import SteamWorkshopService、SILService 或 WallpaperManager；来源 preview state 不在 Shared 里冒充第二图像缓存。播放/停止命令还须在 App 边界核对规范引用及当前 ticket，过期卡片的 Stop 不能停掉后来提交的新壁纸。

“可组织”与“可播放”分开：已有本地发布记录但暂不支持播放的内容仍可喜爱/加入列表，避免以启动校验过严限制用户组织；尚未完成本地发布或文件已丢失的引用不能新加入，只保留此前关系。Steam 作者标签、分类和远端筛选字段继续由原服务持有，不因本地“标签”改名而迁成播放列表。

玻璃 bar 已使用 macOS 26 的 [NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview)，项目部署目标也是 26.0；沿用系统能力，不叠手写模拟玻璃。保留现进度填充和必要标题呈现直到实际比对证明可由原生替代；此次不为了“原生”删掉已有交互。Shared 卡片迁移完成后，原 Steam 的同职责视图退出，旧/新只允许切换路由，不能长期保留两份 UI owner。

<!-- preserved-body:end -->
