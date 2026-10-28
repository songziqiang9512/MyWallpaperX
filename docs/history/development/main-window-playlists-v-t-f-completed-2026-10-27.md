# 主窗口 V/T/F 完成记录 · 2026-10-27

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**

保存已合入99ba1fa85的前轮工作卡、裁决和有界证据。当前产品规范与M01–M16状态只查[主界面方案](../../development/main-window-playlists-redesign.md#ui-simplification-sixteen)。原文“本轮/当前/待验证”均指当时；与新要求冲突时以现役方案为准。

<!-- preserved-body:start -->

<a id="user-ui-revision-10"></a>
## 15. 新10项与补充模态裁决：实施工作卡

已获实施授权，隔离工作树保留既有改动；设备归还核验见`.artifacts/main-window-redesign/v10/d40-return-independent.json`。新图路径仍缺失，Editor预算取此前Music参考，最终用户实看裁决。源码结论、隔离近门和整App实看分别记录，交叉审查不等于视觉验收。

| 工作卡 / 用户序号 | 当前状态 | 本轮替换后的标准与后续落点 |
|---|---|---|
| V01 / 1 单张列表封面 | Artwork/Query/Presentation近门通过，整App待实看 | 目录取消全部堆叠/宫格，自选单图优先，否则规范成员顺序首项；空/不可用/加载中用同媒体占位，不按回包顺序借下一图。Sidebar/Header/目录同源，封面不参与鼠标缩放；保方形/名称/数量/5列与3–6端点 |
| V02 / 2 紧凑编辑面板 | 前轮原生证据保留；F02新尺寸待验证 | 前轮380×520/128图候选已退出；T08的270宽由F02修为285宽，保112图/60描述、按内容fitting，错误完整有界滚动，无固定大空白；与Picker/SteamLogin共用清透regular Surface，无取色填层 |
| V03 / 3 目录返回按钮 | 导航/数据及原生Toolbar近门通过，整App待实看 | 目录→列表时，右侧按钮区首位独立`chevron.backward`+返回，后有原生space；不放标题左。返回恢复目录原搜索/排序/密度/UUID锚点，捕page/reset/entry上下文；不停止壁纸、不改播放来源；保Steam作者返回独立业务 |
| V04 / 4 侧栏大图标 | 原生Sidebar门通过，整App待实看 | 前轮24 pt候选已被Q07替换：槽/封面22、符号和字体沿挂载后的原生source-list配置；保持强调色、标题基线、窄栏/长名，SF固有留白仍看真实绘制范围 |
| V05 / 5 侧栏让位 | 原生Sidebar/通用UI门通过，整App待实看 | 优先原生view-based Outline `.gap`验证让位且无线；不满足目标时才同原Outline做临时UUID顺序+moveItem，约0.12 s跟旧视觉并服从减少动态效果。固定两入口/组不可拖，hover不写Store，取消零写，drop一次原事务/Undo；壁纸拖进列表仍为添加关系的copy语义 |
| V06 / 6 目录让位且无闪 | 受控异步正负控已区分，185项通过 | 原Collection在hover按目标让位，纯UUID重排用move/batch保持item和图像身份；native index先按当前已安装entries转目标UUID，再作用到排队临时序，不能把未来queued顺序当真实index。新建卡固定第0格，排序/过滤不暗改；drop一次原事务，凭Store revision结算（可跳过自己echo直接到后续排序/Undo），失败恢复一次，不全reload清图 |
| V07 / 7 连续拖卡误多选 | 完整三模式167项通过，整App待实看 | 普通模式拖未选B前将原选A替换为B；拖选中同卡不切Inspector，显式选择模式保集合/框选但不启动原生拖动。原生mouseDown/selection委托在组装pasteboard前统一，不在drop结束补清，不加焦点或全局鼠标监听 |
| V08 / 8 确认 | 本轮P03替代旧自绘呈现 | 全App二次确认使用系统NSAlert；原居中自绘及专属像素oracle退出，业务取消/源文件checkbox/响应与嵌套语义继续验证；Editor/Picker专用窗口不在替换范围 |
| V09 / 9 详情预览位移 | 真实四来源/Host门通过，整App待实看 | 用户报告换选时先位移再回正。Host已复用不代表子预览稳定；记录真实Video/SIL/Pixabay/Steam首次layout、图片/详情回包、滚动恢复后的窗口坐标。保排版结构/隐藏滚动条，在现子视图更新事务消除中间错误几何；Video预留既有两行预算使单行留白略增，非旧终态像素一致；不以整panel淡入/延迟/强制置顶遮问题 |
| V10 / 10及补充 Picker统一材质/模态/按钮 | Editor/Picker/Toolbar/菜单近门及最终App实看通过 | Picker与Editor同详情/Steam登录材质；取消取缩略图背景色及其0.75 s/首帧快照新方案，主窗口轻染仍原规则。两者附主窗口模态出现并拥有输入，下层不可点击/拖动/收快捷命令；原生capsule优先，视觉达不到可共用最小自绘bezel，键盘/AX/禁用状态完整 |
| V11 / 拖动后标题灰矩形 | 已修并含于185项原生回归，整App待实看 | Directory的name.drawsBackground与灰色背景显式绘制是来源，非文本编辑；已退出这两行，标题始终无文本选底。保封面outline、native selection/highlight、AX、UUID与键盘行为；旧灰底正例按用户新裁决替换为无背景/无field editor，补真实拖动后检查；其他媒体bar用原CATextLayer未见同类producer |

**L01 轻量调用链（用户补充，已实施、交审及最近门通过）。** V01–V11及来源/模态/相邻命令近门通过后，回查本会话未提交产品改动；跨await目标/epoch、CAS、文件权限、UTF8身份、迁移持久输入、SQL/Undo完整性仍按实际消费边界保留。删guard数、静态复杂度和调用次数不冒充整App实测提速；不借本片扩成引擎/认证专项，另会话的Web文件检查与Navigator优化不重做。

已实施边界：PersonalSettings.plan用引用Set代替逐sourcePatch扫locators，保原值优先/顺序；Query按页面/搜索/有效排序构辅助表，alias-only不扫locator，保最近先去重限50再filter；Controller只为实际待清recent取上下文，FIFO空drain零读/零发布，无新调度flag。退役经全产品调用核验为0的Publication.publish(snapshot:)及配套旧capture入口，故障/持久化测试迁真实openOrMigrate/rawDefaults+inputURL。Adapter一次viewport内复用Source；同字体/图标尺寸不重建或清文字宽度；Workspace旧entry一次索引、已成立backing不交空事务；Composition按完整数据依赖复用派生、同render只更新一次Header，动作仍按新session生成。三组独立交审无阻断，Core/Workspace/Commands九门、控件/适配两门及共享卡片相邻门均已通过；Resolver插桩先严核marker及真实非零，不能恒0伪过。


### 15.2 具体实施边界、布局与完整操作链

**封面与排序。** V01先改Query.directory:246的“筛可用前4”及DirectoryEntry.coverReferences多值合同，从规范手动成员首项直接给唯一候选（先身份后可预览）；再改现Artwork owner从prefix(3)收至该首项，保持自选asset读取、取消/late回包/resetEpoch；退出Shared/UI多层layers、背图view/offset、sourceImages/多slot身份和对应独占无消费者辅助，不留只供旧fixture调用的兼容层。保现单图方形归一化，不清Store封面资产或schema/profile数据；旧“每层不同图”断言因用户取消功能而迁移为单图/无多余请求/尺寸/取消/复用反例，数据安全/真实旧断言不削弱。V05/06共用纯UUID目标顺序计算（确有双消费者再抽），Outline与Collection各自消费原生move，不造全局Drag manager。

目录预览仅在当前可编辑、手动无过滤时开始，捕drag UUID、resetEpoch、目录全体playlist UUID集合（非壁纸成员/可见子集）及一次性session；hover只变UI预览。accept且最终顺序确有变化时，现Controller串行一次reorderPlaylists写sidebarRank并register一次Undo；原位/往返hover后回原序drop为零写/零Undo，侧栏/目录同权威回声。原onReorder:Void优先改为原Actions的一次成功/失败终态，不以仅等目标order回声误判Store拒写；提交未结算不重入新drag，不建registry。普通封面/计数回声不得弹回或撤销预览；取消、窗外、reset/只读/集合变化撤预览，失败恢复最新权威一次。纯移动的数据源变化和native batch同事务，存活item的layout attributes不得nil，不能重演旧数组/原生计数裂口；禁用inter-item-gap可见indicator要与真实目标计算分开，不能拿dropOn假装before。移动期间需求在原可见性事务合并前后可见+drag项，结束结算真实集合；hide/close/reset即时撤权，不以全库常驻图片或延时重试消闪。框、图、名称和AX按同UUID一起移动。

**编辑布局与材质。** 按Q04/Q06建立的紧凑Editor布局经T08缩至270宽后，由F02修为285宽；保112方封面、描述60高，名称及封面动作与底部取消/完成同一紧凑栈；去520硬下限/底部spacer/空错误占位，真实fitting定高，长错误最多120高原生滚动、完整复制。三面板共用WallpaperLibrarySheetSurface的regular玻璃+边框，无整片palette alpha/不透明root，系统无障碍回退仍有效；不合并Editor草稿、Picker选择、Steam认证或Store owner，不连带改详情布局。选图NSOpenPanel归Editor嵌套，取消零写，保存仍原事务/Undo/epoch/expected metadata；已接受保存强持工作至入Store并完成，同turn host close不得丢工作，关闭后不导航。Picker保800×600/最窄680网格空间。

**模态和输入。** Q06前轮曾用owned child避免系统sheet灰罩；本轮§20 M16明确恢复与NSAlert相同的系统模态/调暗。沿MainWindowCoordinator解析真实主host，在原WallpaperLibraryModalPanel呈现点优先beginSheet/endSheet并删除已无消费者的child输入monitor；若原生sheet无法保现布局，才沿原owner补一份调暗，不另建registry/event tap/焦点轮询或抬高level。公开parent/child及native sheet关系仍唯一判域。初次makeKey，主host及背景兄弟child鼠标/hover/拖/scroll/key不接收，合法顶层panel/native descendants仍可输入；held菜单/toolbar/drag/QL动作核同一permitsInput。host不可用就报告，不浮出无归属普通窗。关闭同步撤nested sheet/QR、child/monitor，保原owner恰一次cleanup，用户离开App不抢焦点；普通失焦不使业务失效。文本/default/cancel、Picker搜索/缩放/选择按真实keyWindow，背景页/非文本上下张禁用；MainMenu旧允许sheet下切换的正例已按新目标换为阻背景、文本保行首/尾的反例。下载/导入/Store已准入异步结果沿原epoch/revision结算，reset/close清理不套新输入guard；不扩系统hotkey/状态栏或暂停壁纸。嵌套OpenPanel/确认、host关闭、reset/只读/目标删及迟到完成必须保完整操作链，不能只证静态child关系。

**控件和确认。** Apple WWDC25说明mini–medium默认圆角矩形，large以上默认胶囊；公开borderShape可覆盖NSButton/PopUp/Segmented，不能以设置.capsule就声称实际像素正确。Editor/Picker按钮共用原WallpaperLibraryControlStyle，以明确上下文/size配置调用，不让新面板样式默认改大Header/toolbar/原bar；来源selectOne四段及zoom momentary两段保原分组语义；先检查intrinsic size、controlSize、bezelStyle、borderShape和最终背景，必要时原生.glass；原生仍达不到目标才在现NSButton/Cell最小bezel绘制，继承原输入/默认/取消/AX与系统强调色，不另写按钮事件状态机、不加按下缩放，绘制正常/hover/pressed/disabled/key focus均有合同。允许自绘是后备实施授权，不预先自绘整套组件。

二次确认统一原生NSAlert的beginSheetModal/runModal，由系统拥有玻璃、图标/标题/说明/按钮布局；删除AppCenteredAlertPresentation与手排Panel，不为像素同轴重绘或遍历系统内部视图。首安全/单按钮保原Return，以原alert生命周期的裸Esc桥执行同一原生按钮；completion/host关闭/app-modal退出均立即移除，其他按钮用原keyEquivalent，无独立输入域或焦点逻辑。Editor/Picker保现专用玻璃窗口，其内的删除/放弃等确认仍挂当前顶层panel；无host沿原app-modal。保accessory/suppression/help、按钮顺序、响应值及completion一次；取消/保留/Esc零业务写，源文件checkbox默认off，物理删除partial仍报失败项。接受系统原生排版差异，不再要求手绘48pt图标/17pt标题/160pt正文几何。

**返回。** V03由现Presentation/App导航记录仅“从目录进入playlist”的有界返回上下文，不建任意栈或把播放来源当页面history；目录卡/其右键Open捕该上下文，侧栏直接选其他页、reset或目标删除清掉，普通编辑不清；新建/notice打开按真实来源显式决定，不借旧上下文。返回使用原目录PageID session恢复查询和UUID锚点，原目录已变化时找存活锚点/合理边界，不按旧index回滚；上下文/epoch失效的旧toolbar action不得导航新会话。按钮与原作者返回同公开样式、独立组及可执行overflow，不复活已退役的无上下文back入口。

**V09实施裁决（顶部锚定已由T01–T03替换）。** 保固定156预览和隐藏滚动条；全部详情文档从顶部安全距开始。Video原加载态缺少元数据/路径，AV完成会改变居中高度；现原helper在现有一次stat结果上同步给完整模板，AV仍异步补值，元数据及次要信息按已有两行上限预留高度。缺图提示保留文案，放到固定预览区域内，避免缺图/补图改变正文高度；补图仅更新同一surface。SIL同样原位补图，固定高度约束只安装一次。Pixabay直接读现有已准备快照，退出无I/O却人为Task两阶段重建；Steam同步布局后恢复原scroll origin，退出延迟一轮校正。Host同步完成新子内容实际宽度布局，无整面板淡入或延迟遮盖。AV/真实图变化须补坐标、身份和约束数门，不能以外壳记录视图代替。






<a id="inspector-playback-appearance-round"></a>
## 18. 详情、简洁确认与播放/背景规则（T01–T08）

| 工作卡 | 当前用户目标与唯一实现边界 | 状态 / 验证 |
|---|---|---|
| T01 顶部安全距离 | 共用Inspector滚动区的首图从统一顶部安全距起始，真顶不进入fade；滚离顶后才有原平滑过渡，footer和header不入mask | 共享181项真实滚动像素及四来源实际frame门通过（真顶/中段/底部/insets/短文档/resize）；顶部首图完整显示 |
| T02 Steam统一过渡 | Steam详情复用同一InspectorFadingScrollView及safeInset，不叠加新blur/背景/观察owner；无硬切，原预览与属性内容生命周期不变 | Steam实际Detail两门及共同fade门通过；保原同turn滚动恢复/预览生命周期，待最终App试用 |
| T03 统一顶部排版 | Video/SIL/Pixabay/Steam详情全部短内容也top锚定，退出文档内centerY；保外层浮动面板定位、隐藏滚动条和既有元数据/footer排版 | 四来源实际Host/短长内容/顶部8pt/补图前后frame与方向键原位替换门通过；入口/关闭竞态旧断言保留 |
| T04 简洁原生确认 | 删除/清空/重置/导入等常规说明至多两句，具体失败信息不截断；原NSAlert显式用app icon，文字按原生左排，源文件checkbox左排/default off，取消/响应/源文件作用域不变 | 原生NSAlert门32项及Commands事务门通过；App图标/left-checkbox default off、取消零写/partial/原响应不变；系统拥有文字/玻璃布局 |
| T05 当前列表轮换 | 手动从当前页播放后，自动timer/ended/随机/失败跳过始终使用该成功来源的有序候选；换浏览页不换来源，空/失效/删列表不自动退全库；无来源的显式导航政策保留 | 原产品来源绑定无需重复改写；真实Workspace→Manager Timer/advance→Sequence六本地页顺序/随机等30新增检查通过，换浏览/失败/来源不可用不退全库 |
| T06 图片退出恢复 | 原Manager桌面写入职责保存每display的原URL/options及最后App实际URL/options；成功应用静态图片后，退出时syncSystemWallpaper=false恢复仍由App占用的桌面，true不恢复；跨图/动态/开关变更不覆盖原备份 | 实现并通过Playback/Termination/Removal近门；含partial rollback自身失败、同URL外部options变更、两缓存出口保护；桌面API/屏幕为隔离transport，不改真实用户壁纸 |
| T07 背景二选一 | 当前规则由M12更新：原设置改名“界面主体色调”，按列表取色 / 系统强调色，未保存时默认后者；系统色轻染主区/侧栏并停止缩略图取色；复用原偏好/tint owner，不新增设置或主题管理器 | 原生设置/三取色门/Sidebar/Artwork/profile import+readonly门通过；旧journal兼容已修，B零采样与释放lease、迟到拒收；真实主窗材质待Debug试用 |
| T08 编辑列表窄窗 | 编辑列表信息窗口从360约缩至270pt（约25%）；保原112封面、名称/描述/选封面与恢复/保存取消，内容驱动高度，长名/错误不裁；不改变添加壁纸Picker宽度 | 原生Editor门通过（50项）；270宽、112封面、全部按钮/长中文emoji/长错误/键盘/保存与撤权；待最终Debug试用 |

实现取舍：详情只改现共享scroll与各文档top约束，mask按原viewport与实际溢出启闭，不加overlay层/第二layout owner。原生确认保系统玻璃/按钮布局，accessory仅公开尺寸与left alignment，不把icon居中变成私有view改造。T08优先原生fitting，遇按钮宽度不足可用同组垂直排布，不缩字/裁正文。

播放与恢复：T05是现Sequence唯一来源合同的核验，自动推进不得调用global后备；原library snapshot/alias/成员更新仍唯一权威。T06沿原desktop write的事务/退出收口：先撤在途写权再恢复；partial rollback自身失败时保原baseline和实际残留写值，未把失败播放冒作commit。只恢复实际写过且URL/options均未被用户外部改变的屏，URL/options为空/失效或屏已移除则局部跳过，不复制用户媒体、不扫描目录、不哈希文件、不重试抢桌面。普通动态同步的既有退出政策不扩大；静态图片触发的恢复资格由原Manager持有，退出时开关决定是否执行；备份仅在进程内，覆盖正常退出，不承诺崩溃或强制结束恢复。

背景职责与兼容（默认及系统色呈现以M12为准）：复用原AppSettings持久化与原Shell tint projection，字段缺失默认系统强调色，未来无效值只回退这个偏好；设置UI用原生双选项，不新增theme manager；已无产品调用的弹窗单区域取色install(main:)及转发helper退出，跨窗口生命周期/迟到采样断言移至仍在用的双区域接口。NSSplitViewItem已有原生侧栏材质，B只撤opaque覆盖；主区保持系统底色/材质。独立窄设置投影消费发布入参，避免settings willSet旧值与RenderSignature早退；目录tint-only封面lease随模式释放/重获，真实Sidebar/Grid预览需求不受影响。旧import-recovery日志未声明新背景字段时，两个原偏好CAS消费者共用字段兼容比较并保本地选择；声明过的新字段及其他字段冲突仍拒绝。三代理分责及交叉审查、Root串行近门已完成；审查修复partial rollback失败与旧journal新字段兼容，不留重复owner，原断言保持。先不提交。

前轮T01–T08候选（2026-10-26，仅旧代码证据）：同一缓存增量Debug 68.854s构建及签名验证通过，4375个产品构建输入前后及启动前均未变化，base为8f71545d8；已用W21隔离HOME/defaults/workshop参数启动PID65301。最终凭据在忽略的`.artifacts/ui-polish-20261026/`，保留一份原DerivedData与App供用户试用；无暂存/提交/合并，主仓未修改。真实系统桌面恢复、原生模式下方窗口模糊及用户视觉验收仍待，transport/AX/构建不替代这些结论；前轮既有Scene依赖baseline差异保留原证据，不改无关Scene门或泛称全仓全通过。该候选轮全仓文档链接门有10项基线既有失效（源文件与目标缺失均与8f一致）；该轮5份改动文档相对链接零错误，证明在旧凭据document-link-scope.json，未混改并行专题。

<a id="compact-input-subscriptions-round"></a>
## 19. 紧凑确认、输入外观与订阅入口（F01–F04，收尾）

| 工作卡 | 目标与唯一实现边界 | 实施 / 验证 |
|---|---|---|
| F01 紧凑删除确认 | 历史de3ef098e之前原NSAlert未手设宽；撤当前320pt accessory下限，保sizeToFit/left/default off/app icon，正文短两句保scope及不可撤销提示；资料库/关系/列表删除的两按钮缩成取消/移除，原.first响应不变，不恢复私有KVC或368pt手排Panel | 原生确认32项、Commands事务及Directory门通过；真实Debug约260pt宽、有App图标/取消/移除/未勾源文件，Esc取消后12项未变；未对真实媒体执行删除 |
| F02 Editor285 | 名称/封面/描述窗口270→285pt；保112封面、60描述和原fitting/完整错误；Picker不改 | 原生Editor52项通过，含几何/中文emoji/撤权/保存取消/嵌套选封面；真实Debug测得285pt、半透输入，取消未保存 |
| F03 表单轻透 | 提取Login现半透明浅暗底/轻圆角为一份共享表面，普通名称/描述、账号/密码/验证码、API Key/快捷网址及作者string字段复用；退出黑色cell/scroll重复不透明底，保原native编辑器/formatter/IME/undo/secure reveal/focus ring/AX及几何；search、数字Stepper/slider/combo和只读信息沿原语义 | native form、Login layout/modal、Scene属性5门通过；深浅/高对比/减少透明度、secure reveal、marked-text协议及原数据类型受检；硬件中文输入法与主观视觉仍待用户 |
| F04 订阅二级页 | 退侧栏/前往菜单独立订阅页与旧运行时case；头像仅登录后显示我的订阅，复用现Steam personal/discovery snapshots和作者返回：公开→个人→作者逐级返回，下载→作者原路不变。原搜索/排序/分段/分页/订阅能力不迁owner；登出清私有呈现回公开，不动正在播放来源 | prefs兼容、Steam导航/query/interactions/menu、remote/window toolbar、主菜单门通过；覆盖原服务快照/逐级返回/登出/迟到拒收及当前回调；真实侧栏入口已移除，真实登录账号/网络仍未验 |

F04兼容/撤权：旧Codable订阅case只读归workshop；旧SavedState同时有两页query时保已有workshop，缺workshop时迁旧订阅密度/锚点，不能归并后重复key使全prefs失效。折叠全局页后，同ID跨feed旧源菜单/primary/组织动作沿既有Steam navigationVersion捕获并拒迟到，同DTO续显消费该原publisher重配动作、无需重启缩略图；Downloads源菜单不绑浏览版次。无调用者的旧订阅通知退出，不另建session/auth owner；目录、OL与播放来源不受影响。
构建与边界：本轮核心及相邻近门已过，原候选Debug50.694s/strict签名通过，4376输入无漂移，PID87290已退出；最终整合Debug187.409s/strict签名通过，4427个声明产品/项目/helper输入前后无漂移。证据在忽略的.artifacts/ui-polish-20261026/compact-input-subscriptions/validation-new.json与final-integration-debug-build/receipt.json；保一份DerivedData/App供后续试用，不自动再启动。真实账号、硬件IME、真实桌面恢复与主观视觉不由fixture/构建代验。
交审与测试修正：原source菜单跨feed撤权/同DTO重配、旧query顺序无关合并及私有搜索不迁公开均闭合；退出旧订阅通知、Login专属field及重复外观数组。新fixture按原消费链先consume pending scroll再发布用户滚动，text即使default数字仍交原string；全局remote页减为两页后按来源逐项断言，未削弱旧断言。原生输入保stock NSAlert对照与handled=true keyEquivalent断言，Tab走原队列；测试激活失败不改产品焦点逻辑，真实Debug删除确认Esc已验。
整合结算：基于启动专项23a382c6a重放全部UI改动，保唯一静帧查询/一次缓存key及桌面恢复/保护职责；测试补真实clearUnprotectedStaticFrameFiles提取与空protected Set数据叶，Generator/StaticFrame双配置、删除回执、库Playback、Steam interactions通过，双方断言保留。五条启动文档登记完整保留，已退休的三个源码形状信号棘轮220→217，行为反例不减。独立最终复审无阻断，按用户授权以单个UI提交快进codex/engine-refactor-program，完成后通知“新模块接入”基于该HEAD并等待其用户安排；不碰main、不推送，停止后续任务。


<!-- preserved-body:end -->
