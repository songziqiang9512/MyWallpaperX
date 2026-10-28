# 状态栏控制面板改造专项

<!-- document-role: active-plan -->

日期：2026-10-26。设计初始基线：`ae0ac798c`；最终整合基线：`de3ef098e`。独立分支：`MWX/status-menu-design`，目标分支：`codex/engine-refactor-program`。

用户已确认概念图与约344×520点方案（按生成图比例微调为344×536点），2026-10-26授权实施。本专项只拥有状态栏呈现与入口，不接管播放、设置、资源或系统指标的真值；用户2026-10-26追加授权：待UI专项正式放行后，以其最新提交为基线接入主仓`codex/engine-refactor-program`，构建Release替换本机App；不推送。

## 用户结果与取舍

用户点开菜单即可认出当前壁纸、切换/暂停/静音、查看原有系统占用和网速。以封面和清楚的留白为视觉中心，保留轻量工具的体量。

后续封面过渡的实施与验收归[UI22工作卡](ui-quality-audit.md#ui22-scope)：原请求身份保留，换源不先清空已就绪图，尺寸与其余操作不变。

三个参考来源均为用户桌面图片：`截屏2026-10-26 01.13.36.png` 提供大预览与简短底栏的方向；`截屏2026-10-26 01.04.07.png` 提供层级和底部动作分区的方向；`截屏2026-10-26 01.03.59.png` 提供监控指标表达的方向。前两张借布局，第三张只保留指标的易读性，不搬入历史图、温度、频率、电池和每核图表。

采用已确认的大封面控制面板，按概念比例微调为344×536点；空态缩短，避免没有壁纸时保留大块空白。

## 当前实现与可复用边界

- `MyWallpaperX/App/StatusBarController.swift` 当前使用 `NSStatusItem + NSMenu`。菜单包含CPU/GPU、内存、上/下行速率、打开主界面、导入视频、下一张、暂停/继续、静音、设置和退出；无封面和名称。菜单栏自身显示GPU百分比，每2秒采样一次。这是实施前源码基线。
- 播放命令复用 `PlaybackCommandMultiplexer`；静音用 `PlaybackMuteState`，静音时滑块/百分比投影为0；解除静音显示原音量，保留真实保存增益。拖动到非零即解除静音并采用新值，拖到0沿原逻辑静音，再解除时用既有previousAudibleVolume恢复。音量用 `WallpaperManager.updateVolume` 与原有归一化状态。不得把壁纸音量接到系统音量或Apple Music音量。
- 上/下一张复用 `App/CrossRuntimeWallpaperNavigator.swift`。它委托唯一Library Sequence，沿当前已提交来源作相邻导航；空来源不在打开面板时扫描全库或自动建队列，未恢复播放前先用播放键恢复成功来源。
- 设置由 `SettingsWindowController` 装配；音量直接加入主面板。最新UI基线已统一四种媒体的来源序列、播放方式和轮换；本面板只分发相同设置，不重建Video专属队列。
- Web/Scene属性调节复用既有详情入口和共享属性面板。仅点击入口时准备属性，打开状态栏不得触发Scene解析、编译或截图。

## 推荐排版与尺寸

所有尺寸使用macOS逻辑点。下表为比例1.0的排版基准；当前按[UI20](main-window-playlists-redesign.md#ui-online-panels-twenty)统一使用0.88，正常视频面板303×472点、封面约275×155点，系统外边框、箭头和阴影不计入。字体、控件和间距同倍率，不能只放大外壳。

| 区域 | 设计 |
|---|---|
| 外壳 | 宽344点，默认高约536点，横向内边距16点；普通状态不滚动、不允许用户拉伸 |
| 顶部 | 28点高；左侧16点时段问候，右侧28×28房子图标，打开主界面 |
| 封面 | 312×176点，约16:9，圆角10点；复用已有静态缩略图，居中填充，只有这一处大面积图像 |
| 封面角标 | Web/Scene右上角28点属性按钮，图标为画笔；工具提示“属性调节”；无该类型能力时不占空位 |
| 名称和状态 | 名称15点semibold，一行截断＋完整标题工具提示；下方11–12点次要色显示“Scene · 正在播放”等真实状态 |
| 播放控制 | 40点高，居中的上一张／暂停或播放／下一张；中心按钮44点，其余命中区至少32点，图标16–18点 |
| 音量 | 24–28点一行：左侧静音图标、中间滑杆、右侧百分比；只保留一个静音入口 |
| 分隔 | 三条轻分隔线划分播放、监控、底栏；不把每项放进独立卡片 |
| 资源占用 | CPU、GPU、内存三列，基准12点标签、16/14点等宽数字；CPU/物理内存聚合App、已登记播放helper与可证子孙并去重（系统XPC归属缺口见[主界面规范](main-window-playlists-redesign.md#ui-feedback-thirteen)），GPU为系统范围，tooltip解释，不伪造单App GPU；独立网速行仍为系统上传/下载 |
| 底栏 | 32点；左侧无背景“打开设置”，沿用外箭头图标，右侧带电源图标的长条圆角“退出”按钮，直接进入既有退出确认 |

垂直节奏以8/12/16点为主。顶部约12点、底部约16点。SF系统字体与SF Symbols；监控主数值14–16点、网速13点等宽数字，避免数值刷新引起宽度跳动。图标使用统一symbol weight；仅中心播放按钮有明确填充，其他以静态轻底色或悬停态为主。

外壳直接采用macOS 26原生NSPopover提供的Liquid Glass，内容仅用透明NSView；按Apple指导移除叠在popover上的NSVisualEffectView，避免磨砂遮挡和双重材质，不重复嵌套NSGlassEffectView。系统适配深浅色与“降低透明度”，并决定外圆角与阴影。封面只裁切展示缩略图，不改变实际壁纸构图。主面板不增加频谱、动态封面、滚动标题或历史曲线。

左上角按本地时间选择用户确认的两句时段文案：05–08清晨、08–12上午、12–14午间、14–18下午、18–23晚间、其余深夜。“给作者点个星标吧”以约一成机会穿插且不连续出现。选定后至少保持一小时，仅在下一次打开且已满一小时时重新选择，避免紧邻重复；面板内指标、播放状态刷新不改变文案。只在既有视图保存上次文案和单调时钟选择时刻（ContinuousClock，包含睡眠经过的时间），日期只决定本地时段；不持久化、不加定时器或后台任务，系统校时不会提前切换。跨时段仍遵守这一小时保留期，应用重启后重新选择。

## 从设置中挑选哪些功能

首版直接加入音量滑杆；新增上一张、封面、壁纸名与属性调节入口。名称/状态右侧的无背景图标按钮在单循环／顺序／随机间互斥轮换，直接复用现统一设置；四种媒体均沿Library Sequence，不再保留Video专属模式投影。移除更多菜单和导入视频；底栏直接提供带电源图标的圆角退出按钮，继续使用现有确认流程。左下角“打开设置”进入完整设置。

自动切换的间隔编辑、播放速率、HDR、最高帧率、歌曲信息、频谱配置、节能策略与维护操作，首版继续留在设置。它们有类型限制、授权或低频编辑需求，不为了“功能全”撑高菜单；沿用产品现有轮换能力，不在状态栏另建轮换调度。若后续使用证明某项高频，再加一项而非搬入整页。

## 原生技术选择与数据流

保留 `NSStatusItem` 与GPU百分比入口；按钮打开单个AppKit `NSPopover`，容器透明、由NSPopover提供原生Liquid Glass背景和标准 `NSButton/NSSlider/NSTextField`。不用SwiftUI、WebView、新进程或自定义浮动窗口管理器。Apple默认建议菜单栏扩展使用菜单；本方案因静态预览、多个并排控制和连续音量滑杆，使用其允许的复杂交互例外。仍保留现有App主菜单、热键和主窗口入口。

状态栏只投影现有owner：WallpaperManager.playbackSwitch.committed＋switchSelections → 当前确认的Video/工坊记录/静态URL → 标题与缩略图候选 → 面板；命令回到现有navigator/multiplexer/设置动作。UI本地只有显示状态、正在请求的缩略图及其取消代次，不增加播放状态或设置的第二权威。已追查RuntimeSwitching的commit/finalize/prune：选择字典在提交和有效执行存续时保留，失败/丢失不把pending冒充current；静态URL也从同一已确认选择读取，不从系统桌面或UI选择猜测。

关闭面板或退出时撤销视图订阅和图片consumer，丢弃迟到UI结果；不取消引擎播放。打开先使用已有状态和缓存图，不等待同步采样；沿原2秒监控快照更新数字，不新增轮询、常驻采集、诊断或图表历史。首版不顺便重写SystemMonitor。导航启用只读已提交Sequence是否还有可用后继，点击后由原navigator准入；不扫描私有视频/工坊来源。展开期直接订阅原pauseSnapshots及catalog/playbackChanges，退出本专项旧通知；关闭时撤销订阅，不监听Scene逐帧统计。

面板显示前只装配原生控件和内存状态，不准备引擎或属性。封面版本键、共享缓存首次建目录/旧缓存维护先在按需utility队列执行；本地封面复用既有Steam解码缓存、版本键与800px静态解码，失败后仍交原远程请求/退避链，不新建缓存。Video同样先在后台首次访问既有缓存，再使用原provider；每次回到UI均检查代次和取消，关闭不会接收迟到封面。按钮只在点击后分发原动作，不在打开时解析恢复目标或作者属性。

按原生 `NSPopover.Behavior.transient` 处理点击外部，补验Esc和同一状态栏按钮再次点击。调音量、暂停、上/下一张后面板保持展开；进入主界面、设置或属性面板前关闭popover，再调用现有窗口入口，避免叠窗与抢焦点。不保留二级菜单。

## 上次播放记忆与启动开关

2026-10-26追加要求：无活动壁纸时也能点播放恢复上次成功播放的Video/Web/Scene，不必先打开主窗口。

整合基线`de3ef098e`已提供唯一`WallpaperLibraryPlaybackRestoration`和规范Library Sequence，本专项直接扩展该owner，不保留原独立LastPlaybackSelection键、SQLite成员查询或私有工坊恢复链。成功提交只由原Restoration写其source/query/reference/userPaused；状态栏仅在待机时从其rememberedReference及所属provider的已发布数组读名称、封面；活动状态不解析记忆、不调用全catalog resolver，不解析项目。

`restorePlaybackOnLaunch`只裁决自动恢复；手动播放调用同一owner的resumeLastSelection，再沿原restore→typed pending→原产品事务，保留来源/查询、代次、不可用与来源已删的原规则，不随机替代、不额外写最近。首次升级在同一envelope保留原成功快照与暂停意图，以显式migration位仅维持旧自动恢复准入，不插入已删库条目；真实commit或Stop清除迁移准入。关闭自动恢复及退出改写旧偏好键不能抹掉该成功记录。手动恢复同样等待原来源的provider和关系数据就绪，不能把尚未加载误认为来源已删或降为单项；失败使用原错误呈现入口。显式Stop将原envelope标为stopped并保留最后成功引用，重启仍不自动恢复；用户点播放才能接纳。reset清除同一envelope及legacy提示，不复活旧选择。

暂停直接投影multiplexer的独立用户/系统意图；系统暂停时仍允许设置用户暂停，继续只清用户暂停。活动静态轮换显示暂停/继续轮换，未轮换的静态图无假播放键；静态恢复仍可一键应用。音量只显示动态内容，模式统一使用现设置。没有新的播放、恢复、暂停或计时owner。

## 边界和失败表现

- **切换中：**工坊launchPending准备期、Video定向索引查询与播放事务pending共用既有事实投影；无活动内容时禁用重复恢复，不新建状态机或计时器。封面与名称表达当前已确认内容，单独显示“正在切换…”；新内容确认后成组替换。不因下一张已点击就先把它写成正在播放，也不把pending当失败。快速切换/关闭后，旧图片结果不得覆盖新身份。
- **用户暂停/系统暂停：**分别显示“已暂停”“系统已暂停”。播放图标反映实际状态；系统策略仍阻止播放时不声称点击即可越过策略。不得为显示一个按钮清除其他暂停原因。
- **无活动壁纸：**有记忆时展示可恢复封面/名称与播放按钮；没有记忆时使用280点高紧凑空态，44点图标与提示并排，保留系统数据和打开主界面入口；不保留大块空封面或播放控制。
- **静态壁纸：**展示可取得的真实静态身份；暂停和音量不伪装成图片功能。若现有产品未提供可信静态当前身份，明确显示“未播放动态壁纸”，不从网格选择或旧Video记录猜测。
- **无封面/坏缓存：**本地缩略图缺失时走原有有界图片链；Video确实缺派生图时按需调用原有限并发、单flight与失败冷却生成入口，不额外生成桌面静态图，关闭后迟到回调不再申请UI consumer；失败用低对比度占位；不抓网页、不启动引擎截图、不重新准备Scene。不得借另一壁纸的旧封面。
- **Web/Scene无作者属性：**点击后由现有属性面板显示真实空状态，不在打开状态栏时为隐藏按钮预解析整份项目。
- **GPU不可读：**显示“—”而非0%，与未采样/失败区分；不得为了状态栏再引入私有监控能力。
- **多屏/空间/全屏：**沿原全局命令语义，不自行选一个屏幕后悄悄更换命令作用域。popover锚定实际status item并遵守显示器可见区域，不移动播放窗口、不抢壁纸焦点。
- **小屏/长文本/辅助使用：**标题截断但完整可读；键盘Tab有明确焦点，所有图标有中文辅助标签/工具提示，状态不只依靠颜色。实际高度受visibleFrame约束，必要时缩短封面高度，优先保留控制和系统数据；最小动态高度360点可将封面收至0，属性入口移至名称右侧（与模式图标分槽排列），不裁底栏。

## 后续实施验收与停止条件

进入实施后先验正常播放/暂停/静音/恢复原音量、上一张/下一张的三引擎交接，再验封面迟到、快速切换、打开关闭、退出按钮、设置和属性窗口返回；检查Video模式互斥与设置同步、系统暂停、空库、静态内容、多屏、深浅色及降低透明度。Swift变更做Debug build；独立审查后在真实App中核对实际尺寸和交互。不改引擎、不扩展采样频率；成功播放记忆由原Restoration的同一存储维护，不承接活动播放真值；无法直接复用的次级能力先留在设置，不扩大本批。

概念阶段检查三张参考截图、当前源码与Apple公开指南；不把生成图作为产品截图或性能证据。生成图中的封面、名称和数值均为排版示例，不是实测截图；像素、原生材质、字体和交互以之后AppKit实现验收为准。

参考：[Apple Liquid Glass迁移指导](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)、[Apple 菜单栏指南](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar)、[Apple Popovers](https://developer.apple.com/design/human-interface-guidelines/popovers)、[NSPopover.Behavior](https://developer.apple.com/documentation/appkit/nspopover/behavior-swift.enum)。

## 实施职责与阶段

1. **侦查与设计：**已核对StatusBarController、SettingsWindowController、PlaybackCommandMultiplexer、RuntimeSwitching及静态/Video/Steam缩略图owner。先落本设计和索引，随后实施。
2. **呈现与接线：**StatusBarController只拥有status item/popover、展开期订阅、动作分发和原2秒监控时钟；StatusBarPanelPresentation只把现有事务和库记录读成UI快照；StatusBarPanelViewController/Controls负责原生布局、封面消费和控件。成功身份与手动恢复并入现Restoration，活动播放和引擎控制权不变。
3. **行为与界面：**原生harness检查正常/空态/静态布局、长标题、深浅色、按钮命中与键盘；状态投影反例覆盖pending不抢current、丢失、系统暂停、快速关闭和图片迟到。使用真实缩略图与原生屏幕截图对照概念比例；再通过实际App检查popover开关、退出确认和窗口交接。
4. **收尾：**Debug/Release构建、相关原有播放/属性门、独立审查与必要修正，记录实际完成与未覆盖边界，保留新版供用户测试；按用户新增授权整合并提交本专项；不推送。

旧NSMenu整表重建在新popover接线时退出；确认退出等保留动作经现有入口调用，状态栏的导入视频入口按用户要求移除。失败只影响面板：封面缺失不影响控制，面板关闭不影响播放；不为旧实现长期保留第二套菜单控制器。

### 文档登记与范围

本新产品面没有可承接的现役专用设计，因此新增本文件，并在docs/README、文档角色索引、design_gated_areas与document_health_baseline精确登记；预算新增仅对应本设计，不扩大其他文档。后续UI稳定且验收完成后转为稳定合同或合并至AppKit产品合同，退役本专项执行顺序。

### 执行记录

- 原生面板及用户确认的外观调整已完成；保留原采样策略，无二级菜单或额外常驻任务。
- UI专项放行`de3ef098e`后整合：删除本专项原独立LastPlaybackSelection/SQLite恢复实现与额外暂停通知；保留最新Library Sequence、typed pending、Restoration与pauseSnapshots唯一链。源导航、手动恢复、静态轮换和属性入口均调用现owner。
- 独立审查修正迁移记忆/暂停意图、部分来源加载、全catalog重复解析、小高度按钮重叠及同步/异步失败反馈；原owner回归覆盖Stop/重启、来源/查询保留和迟到/过期反例。
- 最终原生面板/Restoration、Library Sequence/产品事务、pause/icon门及Debug/Release构建通过；独立复核无新增可修问题。Release通过25个Mach-O的arm64闭包、同Team签名/必要权限/版本核验，已替换并启动`/Applications/MyWallpaperX.app`（2.11.0/283）。仅确认新版主窗口启动，状态栏实景与操作交用户测试；harness不代表实景、延迟或全样本验收。保留基线Scene隔离和旧控件警告，未混改。
- 临时HOME不隔离CFPreferences域；预览阶段已改用独立签名bundle标识与偏好域，正式安装仍保持产品身份。该测试处理不修改产品运行配置。

产品提交`43280edd2`以UI放行提交`de3ef098e`为父，快进整合到`codex/engine-refactor-program`；未触碰main、不推送。最终证据保留在忽略目录`.artifacts/status-bar-integration-20261026/`，旧预览、安装回退副本、临时样本及本轮DerivedData于安装启动验证后清理；正式安装App继续保留供用户测试。
