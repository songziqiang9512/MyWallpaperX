# 主界面前轮 U/A 与 N01–N15 候选记录 · 2026-10-25

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**
> 保存本次新10项及补充模态裁决之前的完整方案/状态快照；旧堆叠封面、取消返回、Editor/Picker取色与小图标规则均已被替换，当前只查[唯一方案](../../development/main-window-playlists-redesign.md#user-ui-revision-10)。原文“运行”是当时记录：N15试用PID93644已于20:32:15以-5崩溃退出，不是验收通过或当前存活。未提交候选不等于用户接受。

<!-- preserved-body:start -->
<a id="ui-refinement"></a>
## 13. 2026-10-25 只读 UI 审计与后续视觉修订

### 13.1 本轮边界、证据与两条独立清单

U 表记录用户实测要求，A 表区分源码缺口、待反证风险和可选视觉建议。Music 两图是目标参考；B5 `runtime/screenshots/final-main-window.png` 仅作历史目录外观参考，不证明本轮深浅/hover/键盘/窄窗现象。此次保留原生三组侧栏、方卡/bar、系统强调色、原数据/下载/播放 owner，不扩首页、底部条、推荐、全局搜索或颜色面板；最终微调由用户实看裁决。

<a id="user-ui-corrections"></a>
### 13.2 用户明确的七项待修改（U 清单）

此表只记录用户报告，不把审计建议混入七项。**第二列保留最初审计快照，不能当作现源：R1/R2已覆盖其中部分，U03/U04共享控件R3及Picker/R4最近native门与聚合App限定检查已过候选；当前证据只查 §13.5，七项尚未整体最终验收。** 数值是首版标准；调整须同时替换 §4/5 和本表，不另添矛盾规则。

| 编号 / 用户问题 | 审计起点源码依据 | 修改标准、边界与验收 |
|---|---|---|
| U01 侧栏恢复随首张缩略图染色，现只有主背景会变 | [侧栏材质:43](../../../MyWallpaperX/Shell/WallpaperLibrarySidebarController.swift)采用 behindWindow；[Tint install/project:71](../../../MyWallpaperX/Shell/AppKitListBackgroundTint.swift)仍向根 layer 写色；[装配:70](../../../MyWallpaperX/Shell/AppKitMainSplitView.swift)已绑定两面。代码写入不等于材质实际可见，本轮不宣称已证合成根因 | 查清原侧栏材质承载点，让同一取色结果在 sidebar 内容底下可见，不另建取色器/全屏模糊或重复缓存；保留中性原生选择、系统按钮强调色、0.75 s 中断衔接、无障碍回退。排序/筛选改变首项后两面同源更新；空页/失败页不残留上一页颜色；不强制焦点 |
| U02 所有列表网格间距、卡片大小与 Steam 浏览页一致 | [统一页 Metrics:8](../../../MyWallpaperX/Shared/Components/WallpaperLibraryGridMetrics.swift)当前横 24/纵 28、边 24–40；[Steam 基准:16](../../../MyWallpaperX/Modules/SteamWorkshop/UI/SteamWorkshopGridLayoutSupport.swift)横 8/纵 10、边 8；原 Pixabay `OnlineLibraryGridLayoutSupport` 又是纵 8、item 高 +2（此重复辅助已在 R1 退役） | 共享 Steam 方卡度量：横 8/纵 10/左右 8；同 clip 宽、同列数的封面外框边长一致，堆叠前图可略小，不只图形看起来近似。覆盖十类主页面、列表目录、添加壁纸 picker；目录保留名称/数量的真实额外高度，行间留白按封面+文字整体计算。卡内 bar 和白色 hover 描边保留，不改媒体裁切/桌面缩放；远端 footer/分页高度独立 |
| U03 工具栏不要一个长胶囊，适当分组 | [统一 toolbar IDs:78](../../../MyWallpaperX/App/WallpaperLibraryWindowToolbar.swift)本地页连续 bordered items，原 Steam 布局已有 `.space` | 用系统 toolbar 分隔“来源任务 / 主动作与选择 / 内容组织 / 筛选排序 / 缩放 / 搜索”，每页省略无职责组；紧密成对才组合，不新增自绘玻璃层。每组保必要命令、禁用/选中语义和原生 overflow，具体页表见 §5.1 |
| U04 网格缩放控件像 Steam；默认每排 5 张，范围 3–6 | [新 toolbar:150](../../../MyWallpaperX/App/WallpaperLibraryWindowToolbar.swift)用两个独立 item、offset −2…4；[Steam:253](../../../MyWallpaperX/Modules/SteamWorkshop/Toolbar/SteamWorkshopToolbarController.swift)是左右两段 capsule；原 `GridLayoutHelper` 随宽度改基础列数（已在 R1 退役），Steam 的 plus 当前反而加列 | 全页沿 Steam 两段原生形态与左−右+位置，统一“缩小卡片→列数+1、放大→列数−1”，不能照抄其现有反向语义。默认请求 5 列，可选 3/4/5/6，端点禁用；按页保存。宽度仅决定卡边长和必要的最小卡宽降档，不再默认随窗口跳 3/4/5/6。控件、菜单、快捷键、键盘上下行、可见预取使用同一有效列数；迁移和窄窗例外见 §13.4 |
| U05 播放列表头部封面过大 | [Header:90](../../../MyWallpaperX/Shell/WallpaperLibraryPageChrome.swift)封面 112/80、标题 28；[装配:431](../../../MyWallpaperX/App/WallpaperLibraryWindowComposition.swift)固定 header 高 168 | 试 72/64 pt 封面、22 pt 名称、约 112 pt 普通头；长名/按钮按 fitting size 增高。保留播放/随机/添加三入口，不通过隐藏功能缩小；与网格左线一致并随同一 scroll 滚走。最窄窗口、长中文/emoji、两行名和按钮均不裁切，首行网格与头部不过度隔空 |
| U06 所有列表的封面呈堆叠效果，默认图标表达媒体而非音乐 | [目录:348](../../../MyWallpaperX/Shell/AppKitPlaylistDirectoryController.swift)、[侧栏:267](../../../MyWallpaperX/Shell/WallpaperLibrarySidebarController.swift)、[头部:142](../../../MyWallpaperX/Shell/WallpaperLibraryPageChrome.swift)、[组织菜单:142](../../../MyWallpaperX/App/WallpaperLibraryCommands.swift)各自仍有 music.note.list | 目录一张前封面+最多两张轻错位背板，装饰不超过当前封面框、不改变命中/拖动范围，不用 hover/press 缩放。前封面仍消费原 Artwork 结果；空列表共用媒体语义 SF Symbol 和系统底色，侧栏/头部/菜单保持同一含义，小尺寸不强塞三层细节。新建卡仍是 plus。具体图标核最低系统可用性，不复制相同 fallback 字符串到四处 |
| U07 切列表后网格顶部贴 toolbar，没有安全距 | [统一 Grid:193](../../../MyWallpaperX/Shell/WallpaperLibraryGridController.swift)跨页以 offset=0 把 anchor 卡 minY 滚到视口顶；[目录:135](../../../MyWallpaperX/Shell/AppKitPlaylistDirectoryController.swift)也按 item frame 恢复，可吃掉已有 section topInset。现源码有 28 pt，故不能仅判定缺少 inset | 首次进入且无有效中途锚点/明确“回顶部”恢复 document 真顶部，保留 8 pt 可见安全距；有列表头则头部完整显示。普通中途锚点恢复保引用及新存的相对偏移，不把每次切页都跳首张，不对非首行强加空白。旧状态只存引用，无法还原未记录偏移；明确约定旧首项引用按真顶，其余按引用锚点。分页 footer、通知和原生 content inset 只能各算一次。验证首次进入、A→B→A、目录→列表→返回、排序/缩放/重启后首项，不靠焦点或强制滚动修复 |

<a id="ui-audit-findings"></a>
### 13.3 初次审计记录与可选项

初次A01–A22的问题快照已归档；必要修复已形成R0–R4候选，A13/A14/A16/A18/A19/A22当时为可选项。新15项已明确的内容以后述N清单为准，不以旧可选裁决拒绝实施。

<a id="r0-r4-audit-snapshot"></a> [归档记录](main-window-playlists-ui-r0-r4-2026-10-25.md#r0-r4-audit-snapshot) <!-- archive-redirect -->

### 13.4 执行顺序与停手条件

R0–R4基础实施已形成候选；后续按§14的S1共享交互/呈现、S2列表元数据/封面、S3安全移除整链、S4整合交审与试用推进，独立写集可并行，测试/构建仍串行。十类页按900/1200/1440宽、不同侧栏及原生 overflow 逐项检验，不用焦点 hack；未经本轮授权不为测入口盲目订阅/下载，若改到预览/引擎执行则回退超范围部分。

替代消费者接好后，逐一退役旧 Steam/OL 的 zoomOffset 发布/写入与原 GridLayoutHelper 的宽度基础列数消费者；特别是 `onlineLibrary.gridZoomOffset` 不能再驱动新 Grid/Toolbar。旧原始偏好键可作为兼容审计输入保留，冻结迁移快照不动，但不得形成第二个现役密度 owner；无其他产品消费者的缩放辅助/订阅/旧测试形状同时退出，仍有独立职责的纯算法不为删名字硬拆。模块的远端筛选/分页/账号状态不迁到 Shared。

审计起点的 `wallpaperLibraryPresentation.v1` defaults key 和 synthesized QueryState Codable 是具体兼容边界：新增有默认值的非 optional 字段仍可能令旧 JSON 整体解码失败。后续在同一 Presentation owner 显式 `decodeIfPresent`，缺新密度键仅设5、已知 v1 读入后在**同一个 key**一次写 known v2；原 page、search、provider、kind、status、sort、ascending、legacyTimeOrder、scrollAnchor、目录anchor逐字段保留，不清整份 query、不重跑关系迁移。旧 offset 含随宽度基础列数/目标宽两种相反语义，不能盲目相加；本次明确新的默认5，只退役旧密度字段，冻结旧迁移输入不动。损坏/未来版本仍保原字节、按原只读恢复，不借 v2 覆盖。该密度批次不改个人设置schema6（当前元数据扩展至7见§14）、UUID/alias、播放状态、远端账号/API 凭据不因 UI 密度调整而改变。

滚动值仍归原 Presentation/query 与目录原 owner，在 known v2 兼容扩展为“真顶”或“引用/目录UUID + 相对未被工具栏遮挡的视口偏移”，不是第二状态树。旧v1没有偏移，明确迁移约定为 nil/当前第一项引用按真顶，其余按引用+0恢复；这是有损旧呈现信息的确定性解释，不能声称还原旧未保存位置。新值能区分头部已滚走与完整顶部；旧首项已删除/重排时遵守原可见锚点后备，不猜媒体或改成员顺序。原远端浏览锚点与分页仍委托来源，不把关系页的引用结构强塞给远端结果。Steam原current/pending/内存snapshot统一为未遮挡viewport的document.minY：真顶0、raw clip0对应topInset，恢复减topInset并按原生上下界限幅；键盘/分页距离成对用该viewport，预载阈值仍原raw clipHeight×2.5/至少720。snapshot不落盘，无磁盘迁移/新滚动owner。有效正宽/viewport前保pending，原布局完成重试；真实双publisher负控已证旧offset可先于新items消费新目标，且同IDs的ready40→failed52页脚也能提前限幅；恢复读当前pending并保原scheduled/applying守卫，仅有pending时核卡片IDs及原resolvedState页脚均与当前source一致，沿原完成回执重试，不新增导航计数或逐帧扫描。真顶读取系统实际inset，不能固定y=0；[AppKit自动内容内边距](https://developer.apple.com/documentation/appkit/nsscrollview/automaticallyadjustscontentinsets)默认开启，会处理重叠title/toolbar，读取原NSScrollView结果，不手写覆盖系统inset。

### 13.5 R0–R4基础候选（已实施，未最终验收）

R0命令域、R1统一密度/滚动与bar、R2双面染色/紧凑头、R3原生分组/查询/固定命令、R4共享反馈/Picker已完成候选与独审。原生Chrome35、Picker28、真实Grid旧源越界负控/修后短空投影、聚合Debug/验签和隔离App均有有界证据；完整失败/修复/未覆盖见归档。它们不证明新N项已实现，整体W22仍待用户验收。

<a id="r0-r4-validation-record"></a> [归档记录](main-window-playlists-ui-r0-r4-2026-10-25.md#r0-r4-validation-record) <!-- archive-redirect -->

### 13.6 共享实施边界

保原source/selection/query/relationship/Undo及播放事务权威；Toolbar与右键只生成固定目标命令，Shell不读来源单例。已退役的旧Grid、旧标签双写与重复owner不恢复。新N项的数据/样式/失败及验证边界统一见§14，不再把已完成R0–R4施工细节当新任务。

<a id="r0-r4-implementation-paths"></a> [归档记录](main-window-playlists-ui-r0-r4-2026-10-25.md#r0-r4-implementation-paths) <!-- archive-redirect -->

### 13.7 本轮视觉审计收敛与后续排期

两条任务分开交付：U01–U07保持用户原编号/标准，A01–A22为独立发现；当前实施与限定验证只查§13.5，不以先前只读审计或局部门通过误当全部完成。A21/Grid与A05弹层阻断已按真实负控/原生事件收口，R4反馈与Picker已按§13.5完成测试候选，整体W22仍待用户验收；A12范围复用summary，普通排序不清条件；A13标题/小卡字暂保Steam基本样式，A14暂保原菜单/拉刷新而不为对称加常驻按钮；A16/A18/A19/A22保留为用户可选视觉建议，本轮不自动追加改动或后续任务，不把源码差异当已证功能退步。核心布局与操作已完成代理限定实看，仍待用户整体试用，样式是否再收敛由用户选择，不为发现数量扩大引擎语义。
视觉方向采用Steam紧凑方格基底，通过原生toolbar分组、适度标题层级、统一选中与低对比背景接近Music；列表目录文字行保真实高度，封面回包不挪名称。最窄/常规/宽窗分别核五列默认、三至六列、长名/空封面、过滤与notice、主题/系统accent及隐藏Inspector滚动条；已有指定功能不为美观删除。比较须绑定同一最新候选/窗口/内容，本轮代理限定实看不能代替用户整体裁决美观、自然或流畅，未测性能不写提升。

<a id="user-ui-revision-15"></a>
## 14. 用户新15项调整：目标、职责与工作卡

本节先于本轮代码落库。用户截图只作原生级联、编辑表单和胶囊视觉参考，不引入音乐字段或底部播放条；N清单替换冲突的§4–7规则。上一轮完成/失败证据原文归档，不能当新N项完成。完成一项更新本表，验收绑定本轮候选，不删旧有效断言。

| 工作卡 | 当前状态 | 实施标准与必验反例 |
|---|---|---|
| N01 原生级联菜单 | 已实施，交审/回归通过；待用户验收 | 右键“添加到列表”等真正挂NSMenuItem.submenu，hover开子菜单且父级继续tracking；固定ref/page/reset与远端cell绑定，旧leaf不能改新目标，不重做递归popover平台 |
| N02 固定开启侧栏 | 已实施，交审/回归通过；待用户验收 | 移除toolbar/main-menu显隐和旧selector入口，canCollapse=false，恢复旧折叠autosave为开启；保200–320宽度拖动与原生tracking separator |
| N03 不透桌面且旧版轻染 | 已实施，交审/回归通过；待用户验收 | 旧版plain系统底色，现behindWindow是实际差异；同首图/外观对照，原采样与深.12/浅.09不先改，去桌面混色而保0.75s/原生中性选中与无障碍回退，不加滤色缓存 |
| N04 每层一张壁纸堆叠 | 已实施，交审/Artwork门通过、真App堆叠已看；待用户验收 | Artwork唯一owner给Shared/UI有序layer值，当前Header独立需求lease不依赖侧栏展开；自动前三个不同成员保固定slot（未就绪/失败留空），各占一层且后图不得顶替首图，首层无宫格，0/1/2/3/失败/逆序回包/复用严格核；自选封面各处统一，不拿同图凑不同壁纸；resetEpoch撤旧lease/像素，同UUID/assetID新epoch重读 |
| N05 空列表去重复按钮 | 已实施，交审/回归通过；待用户验收 | 保顶部添加；中央只说明不再添加按钮，其他来源空库导入/下载恢复/错误重试不受影响 |
| N06 Picker取色与胶囊 | 已实施，交审/回归通过；待用户验收 | 订阅主窗口同ListThumbnailTintSource，复用原采样算法/背景投影与主source/revision，不另建取色源或改主页面首图；每window仍独立可见lease/cache，初次淡入相位可不同，不声称只采一次；原生NSButton.borderShape=capsule、segmented capsule，保键盘/default/cancel/disabled和N-M-K |
| N07 编辑名称/封面/描述 | 已实施，交审/回归通过；待用户验收 | 右键编辑统一原生sheet，单个本地图片生成App拥有的最长边≤512/编码≤4MiB小副本，profile同合同并在解码前验实际尺寸，支持自动；可选描述trim为空不显、非空标题下最多三行；恢复自动不冒用旧custom图，未有自动图时媒体占位并说明保存后生成；取消/坏图/target删/reset/旧回包不写，保存一条事务/原Undo，背景镜像主source |
| N08 统一移除确认 | 已实施，交审/回归通过；待用户验收 | toolbar/菜单/快捷键/删除键同入口，trash+每次确认，默认off“删除磁盘的源文件”；关系页off仅当前关系（用户确认），库/下载off持久隐藏且不删文件，不可误用Steam removed墓碑触发GC；on原source逐项实际删除+真实回执，Video/SIL准入捕身份及最终busy/身份+unlink均原MainActor短段，fsync后台且不承诺非常规挂载延迟，部分失败保失败项/旧选择撤权 |
| N09 空选禁More/Trash | 已实施，交审/回归通过；待用户验收 | 原可用性同源投影，0项均disabled且overflow一致；旧菜单/异步回声不能借新选择，目录无壁纸选择不放假内容命令 |
| N10 详情原位换选 | 已实施，交审/回归通过；待用户验收 | Host可见期与content token分开：已打开时方向换选只替换内容，不hide/show或重置slide；跨provider保窗口/调宽，撤旧lease/按钮/迟到mount-close；真实host检查offset与显隐次数 |
| N11 列表头三胶囊 | 已实施，交审/回归通过；待用户验收 | 从左“随机”图标、“播放”图标+文字、“添加”图标；原生capsule及系统accent，完整AX/action，长名/描述/窄窗不裁切且按原height-for-width保滚动锚点 |
| N12 去重复角部心形 | 已实施，交审/回归通过；待用户验收 | 删除所有来源右上角喜爱view/约束/更新，只留bar心形；bar状态从既有favorite值而非旧badge.hidden推导，多选/playing/收藏Undo与复用不退步 |
| N13 toolbar重分组 | 已实施，交审/回归通过；待用户验收 | 视频/图片[导入,多选,添加到列表]｜[上一张,下一张]｜[移除,喜爱,更多]；最近/喜爱[播放,随机]｜[多选,添加]｜[移除,喜爱,更多]；自建列表[多选,添加]｜[移除,喜爱,更多]，目录不加假多选，下载保来源骨架；筛选排序/缩放/搜索仍职责分组，来源专属控件保全，窄窗原生overflow同动作 |
| N14 去列表返回 | 已实施，交审/回归通过；待用户验收 | 仅删自建列表toolbar返回；固定侧栏可达目录，Steam作者子路由返回保留，旧无调用action/ID一起退役 |
| N15 去卡片元数据hover | 已实施，交审/回归通过；待用户验收 | 所有壁纸卡及placeholder的title/size/duration/path等toolTip移除，复用后不能残留；VoiceOver语义/动作标签、菜单与详情元数据保留，不粗暴禁用无障碍 |

S1（N01/02/03/05/06/09/10/11/12/13/14/15）做共享原生输入/呈现，S2（N04/07）闭合元数据与封面持久化，S3（N08）闭合移除政策/来源回执，S4整合并由不写该片的子代理交审。各自独占文件，Model/Store/schema由单一writer；父代理拥有唯一方案、公共JSON、Composition与最终整合。运行窗口与对方明确交接，期间不跑任何门/App；达到15项必要实现与对应回归后停止扩大，增量Debug/签名/隔离界面试用，不暂存提交。

数据设计：沿唯一UserCollectionsStore升级SQLite v1→v2的原子DDL，列表新增nullable descriptionText/customCoverAssetID及受控immutable cover asset表，旧缺值=自动/无描述，UUID/rank/members/epoch/migration marker不变；普通snapshot不携全库图片bytes，Artwork按assetID需求读取。编辑捕expected metadata+reset epoch，一事务插副本/改字段/modifiedAt；名称变化不影响identity，成员回声不构成编辑冲突。duplicate共享不可变asset，Undo沿原30层organisation state；旧副本保到无引用/Undo安全点再由同Store清理：恢复成功、同epoch、允许编辑后入原FIFO回收，若本session已发出真实组织Undo则跳过，reset同事务清，不能新文件目录+DB双发布或新资源registry。

个人设置schema7携当前引用的受控封面副本/描述及明确库隐藏记录，补ReferenceDate数值精确键以保ISO8601 profile往返小数日期（兼容读旧Date键，原recovery已用默认数值codec，不宣称修复旧恢复精度），仍排除原壁纸媒体/历史/凭据/session；旧1–6读入缺新字段不能清已有元数据，v7显式自动可清。所有SQL读写/duplicate/恢复/迁移/Undo/profile出口整链覆盖，未来/无法识别格式拒写；已识别v1升级在COMMIT前完整验证，失败rollback原schema/关系/版本（不承诺WAL/SHM协调字节零变）；同assetID异bytes拒写并报错，不重跑旧关系迁移或调宽schema接受范围。

隐藏与删除分层：显式库隐藏记录归同一关系Store，Query仅在资料库/下载候选投影消费，保完整source事实给既有列表/喜爱/播放，不新增scanner或provider私有隐藏defaults。显式重新导入/重新下载成功或浏览页“重新加入我的下载”才解除隐藏，本轮不新增库隐藏Undo；扫描/mtime/播放不自行复活。原App运行期桥接在显式下载准入时从现有workspace捕获Store回执，不依赖主窗口或Commands存活；权限在准入时核，已准入成功结算沿原FIFO/profile CAS（不因后来的临时只读丢回执）；恢复捕原隐藏revision及epoch，晚到成功不能清之后的新隐藏，alias链接与条件clear同事务。物理删除只在用户勾选并确认后走原source的活动资源/owned-tree/权限与逐项结果；文件I/O和关系SQL不能假整体回滚，源删成功但关系提交失败须如实显示缺失并报告，旧page/reset/selection闭包不能清新目标。删除列表容器仍只删列表并确认，不让其批量删除成员文件。

验证：先正反例覆盖v1→v2保数据与COMMIT故障、profile1–7、封面取消/坏图/外部原图移除/复制/Undo/reset、隐藏重启/扫描/显式恢复、checkbox off真实文件bytes不变/on仅隔离副本逐项、菜单真实hover与固定叶、原Inspector host连续方向换选、5列/3–6/窄窗/空态/AX及所有现役卡复用。原生capsule取当前macOS26公开borderShape，不用自绘layer模拟button。最终只在获回窗口后做最近门、增量Debug及签名与真实隔离UI；未测真实账号/远端写入或全作品性能不外推。

N15候选收口（2026-10-25）：三名独立子代理交叉复核Native/Editor、Store/profile和来源删除链；发现并修复v1升级验证时点、封面解码前预算、最终busy/unlink竞态、Header封面需求、reset像素撤销及无窗口下载恢复。Metadata/Store/SQLite fault/Controller/profile/import/publication/startup/query、Artwork/目录/Header/Picker/Editor/Toolbar/Sidebar/Inspector/卡片、Commands/定位/源删除/Steam admission/execution/Pixabay扫描及混合序列/播放最近门已通过。新驱动使用真实产品方法/SQLite/原生窗口，各受控source叶与全App边界分开；Video旧stop颜色断言按已确定系统accent纠正，Inspector真窗尺寸及SIL真实hover事件修夹具，原忙碌/identity/取消/复用断言保留；退役仅测试调用的旧rename和旧索引删除API时迁移现役事务断言，不声称旧测试字节不变。

增量Debug `N15-final-debug`输入4132项前后SHA一致、build/strict codesign均0；`N15-user-trial` PID93644以同一隔离RuntimeHome/defaults-suite运行（退出以实际监督收据为准），不读写真实用户媒体。真App已看五列独立堆叠、旧底侧栏/同源轻染、空态无重复Add、空选禁用/toolbar分组、无返回及右键编辑sheet；后续检测用户输入即停止自动点击，未冒称实际hover级联、文件选择OK、连续方向换选或全来源删除UI均已手测，这些分别有原生/产品方法回归，完整视觉由用户验收。最终证据见本机忽略目录`.artifacts/main-window-redesign/u15/`及保留的一份`/private/tmp/mwx-main-window-ui-debug-4hopmbb7`连续构建/隔离试用缓存；旧失败保诊断、新通过不覆盖旧记录，不预支性能、真实账号/远端写入或OS矩阵结论。未暂存/提交/合并，其他工作树保留。
<!-- preserved-body:end -->
