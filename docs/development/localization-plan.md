# 语言适配迁移计划

<!-- document-role: active-plan -->

> 状态：主体已实施（2026-11-23），残余项与验收证据见[迁移结果](#current-state)。标准已于 2026-11-23 订立并生效（英文源语言、String Catalog、同步检查）。
>
> 复核日期：2026-11-23。配套标准：[语言适配（本地化）标准](localization-contract.md)。标准规定"必须怎么做"，本文规定"先做什么、做到哪算完"；两者冲突时以标准为准，并同批修订。

<a id="goal"></a>
## 1. 目标与停止条件

目标：把界面文案改为英文源语言并全部走 `String(localized:)`，以 String Catalog 承载英文源与简体中文译文；系统语言自动生效；源码文案变更时，未同步的译文由检查模块自动阻断；新增语言只增加译文，不改产品代码。

完成判据：中文界面零回归；英文界面无中文残留；占位符、复数、`InfoPlist`、帮助书一致；关键窗口在英文、中文与一份"更长语言样张"下无截断、重叠、错位；检查模块进入常规验证并能拦住"改文案不改翻译"；临时语言演练证明不改代码即可加语言。

<a id="current-state"></a>
## 2. 迁移结果与残余

2026-11-23 实施结果（同一 checkout 实测）：

| 项 | 现状 |
|---|---|
| 支持语言 | `en`（源）、`zh-Hans`、`ru`、`de`、`fr`；`knownRegions`、`CFBundleLocalizations`、`CFBundleDevelopmentRegion` 已同步 |
| 资源 | `MyWallpaperX/Resources/Localizable.xcstrings` 1460 条 key × 5 语言；`InfoPlist.xcstrings` 1 条；屏保扩展独立 `ScreenSaverSources/Resources/Localizable.xcstrings` 2 条 |
| 界面文案 | 1993 处中文字面量改为 `String(localized:)` 英文源文案；中文、俄文、德文、法文译文写入 catalog |
| 结构解耦 | 账号不一致改为 `accountMismatch` 错误码；登录提示改为 `browsingNeedsSignIn` 状态；`未知作者`/`未知大小` 哨兵改为空值判断；Pixabay 元数据改为可选字段；`创意工坊` 与用户媒体目录保持路径字面量 |
| 检查模块 | `script/governance/check_localization.py`：catalog 完整性/占位符/复数、`--extraction` 对比编译期 `.stringsdata`、`--hardcoded` 检测、`--compile` 校验 catalog 可编译 |
| 构建 | Debug checkpoint 构建通过（0 error）；产物含 5 个 lproj，扩展资源独立打包且主 App 无重复条目 |
| 场景属性名 | `WorkshopPropertyDisplayStrings.json` 增加 `ru-ru`、`de-de`、`fr-fr` 各 225 条 |
| 帮助书 | 保留原有内容与结构，配色改为 macOS 原生语义色（跟随浅色/深色）。内容按当前代码补齐：工具栏章节按页面重写，新增「系统与屏保」章节，补齐 Wallhaven/Pixiv，修正过时命名。Steam 登录与下载按 SteamKit 重写：双入口（二维码/密码）、手机确认设备名 `MyWallpaperX SteamService`、去掉不存在的 `InvalidPassword`、超时归入 `network`、补充免登录可浏览范围；下载补充 CDN 客户端、manifest 上限 8 GiB/20 万文件、3 次重试与 403 重新鉴权。样式与脚本以 `script/help-assets/` 为单一源，由 `script/governance/inline_help_assets.py` 注入五份页面，`check_help_bundle.py` 校验一致 |
| 中文回归 | catalog 的 1460 条 `zh-Hans` 全部可追溯到迁移前源码原文；3 条因扫描器无法解析嵌套插值/转义引号而人工核对一致，未发现改写导致的文案变化 |
| 布局静态审查 | 58 处固定宽度约束逐条判定：邻近文案控件的 28 处均为图标、缩略图、数值标签或输入框，没有"固定宽度装文案"的违规。译文相对英文长度实测：中文 0.35×、俄语 1.12×、德语 1.27×、法语 1.30×，单条最大 2.70×（德语 `Connecting`）；布局按德语/法语核对，最大膨胀集中在自适应菜单项。已把三处承载长文案的单行标签改为可换行（Steam 扫码提示两处、Pixabay 空状态）；设置行副标题改为最多三行换行、宽度上限 430pt，标题与副标题都带 tooltip 兜底。另用 AppKit 离屏渲染了五语言面板样张（同一批真实文案在 760pt 宽度下的排版），英文/德文/俄文/法文均无截断、长说明正确换行 |
| 复数 | 21 条含单一数量占位符的高频文案已加复数变体：英文/德文/法文 `one`+`other`、俄文 `one`/`few`/`many`/`other`、中文只 `other`；编译产物为 5 份 `Localizable.stringsdict`（每条含 `NSStringPluralRuleType`） |
| 复数限制 | 约 8 条含多个数字占位符的文案（如 `Showing %lld of %lld wallpapers`）无法交给 String Catalog 的复数机制——`xcstringstool` 明确警告无法推断复数作用于哪个参数。它们保留单一形式，数量为 1 时英文会出现 "1 wallpapers" 这类语法瑕疵；要修必须改写源码文案（把第二参数拆出），属于后续批次 |
| 术语一致性 | 统计关键概念译法：德文壁纸统一 `Wallpaper`（164 次，无 `Hintergrundbild`）、法文 `fond d’écran`（117 次）、俄文 `обои/обоев` 词形变化一致；playlist、Workshop、Settings 各语言均统一。修正了两处不一致：法语 `parcourir le Workshop` → `l’Atelier`，英文源 `Preferences changed…` → `Settings changed…`（旧术语已在标准中废止） |
| 译文自查 | 俄语条目中保留拉丁词的 99 处全部为技术术语或专有名词（Scene 属性名、API、HTTP、Steam、GitHub 等），无整段漏译；德语/法语没有出现含两个以上英文功能词的残留；长文案与短标签抽样 14 条质量合格。母语审校仍未做 |
| 真实窗口走查 | 用改过 bundle id、ad-hoc 重签的测试副本分别以 `-AppleLanguages` 启动 en / de / ru / zh-Hans：菜单栏（File/Edit/View…、Ablage/Bearbeiten/Darstellung…、Файл/Правка/Вид…、文件/编辑/显示）、窗口标题、侧边栏分组与条目、搜索框占位全部显示对应语言，无中文残留、无溢出；用户自己的播放列表名保持原样（属数据，不翻译）。测试期间原壁纸与已安装正式版实例均未受影响，测试副本与含桌面的截图已删除 |
| 失败消息分层 | 复查发现 `helperError.errorDescription` 直接把 helper 的中文 `message` 当用户文案返回——英文/俄德法用户会看到中文错误。已改为按错误码映射：network、accessDenied、authExpired、accountMismatch、helperUnavailable、integrity、unsupportedContent、cancelled、protocolMismatch、rateLimited 加默认共 11 条本地化文案，`message` 只保留作诊断 |
| 验收演练 | 门禁：注入占位符漂移与缺翻译 fixture，检查器分别报出 `placeholder mismatch` / `untranslated` 并返回退出码 1。新增语言：只给 3 条 key 加意大利语资源、不改任何代码，重建 bundle 后运行时正确显示 `Impostazioni` 等，未翻译条目回退英文。回退：bundle 只有 `en` 时，中文系统显示英文。三项均符合标准预期 |
| 运行时验证 | 用只装载单一语言的测试 app bundle（`Bundle.main` 指向产物 lproj）逐语言实测：`Settings`、`Check for Updates…`、`Unknown size`、验证码错误、`About %@`、`%lld wallpapers` 的 1/3 取值、`Showing %lld of %lld wallpapers` 在 en/de/ru/fr/zh-Hans 下全部返回预期译文；俄语 `one`/`few`/`many`、英德法 `one`/`other` 规则均生效，证明 `CFBundleLocalizations` 与 stringsdict 在真实 main bundle 下工作 |
| 门禁 | `localization` 已注册到 `script/data/scene_validation_gates.json` 并接入 `verify_scene_change.py`：CI 检查 Swift 字面量和 catalog，暂存钩子核对同一 Git index 的源码与资源，帮助书单独校验标识和页面。命令见[本地化标准](localization-contract.md#sync) |
| 已知残余 | 译文人工审校（母语润色）；约 8 条多占位符文案的复数改写 |

迁移前的差距记录保留在下方，作为对照，不再代表现状。

<details>
<summary>迁移前实测（2026-11-23 改动前）</summary>

| 项 | 迁移前事实 |
|---|---|
| 本地化资源 | App 内 0 个 `.lproj`、0 个 String Catalog、0 处 `NSLocalizedString`/`String(localized:)` |
| 工程区域 | `knownRegions` 含 `en`、`zh-Hans`；`developmentRegion = en`；`CFBundleLocalizations` 两种语言；无 `CFBundleDevelopmentRegion` |
| 界面文案 | 非注释行含中文字面量约 2035 处，疑似界面文案约 693 处 |
| 失败消息 | `fail(message:)` 等同一条字符串同时进界面与诊断 |
| 文案参与逻辑 | 扫描命中 12 行把字面量用于比较或文本匹配 |
| 布局 | 58 处固定宽度约束、74 处固定高度约束 |
| 检查机制 | 无本地化校验脚本与门禁 |

</details>

已知验证缺口：设计门 `immersive-main-window-ui`（状态 `blocked-pending-design`）的 path 模式覆盖几乎所有 UI 文件，会把纯文案改动判成实施迹象。按[仓库工作流](repository-workflow.md#设计判定与记录)，文案调整不要求新设计，本次属该条目匹配过宽造成的误报；需由其 owner 收窄模式或在设计获批后解除，本计划不自行修改他人设计状态。

迁移的硬约束保持不变：中文是既有用户的语言，任何英文源文案改动必须在同一提交更新 `zh-Hans` 译文；catalog 缺条目时中文界面会回退英文，检查模块会阻断。

<a id="decouple-inventory"></a>
## 3. 文案耦合清单（批次 0 必须清零或登记）

必须改为结构化状态的：

| 位置 | 当前写法 | 目标 |
|---|---|---|
| `MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService.swift:230` | `message.contains("不一致")` | helper 返回错误码，App 按码判定账号不一致；`message` 仅诊断 |
| `MyWallpaperX/Modules/SteamWorkshop/Toolbar/SteamWorkshopToolbarController+Configuration.swift:30` | `statusMessage.hasPrefix("需要登录")` | 服务暴露登录状态枚举，工具栏按状态取图标与 tooltip |
| `MyWallpaperX/Modules/SteamWorkshop/Toolbar/SteamWorkshopToolbarController.swift:141` | `$0.hasPrefix("需要登录")` | 同上 |
| `MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+SteamKitBrowse.swift:231` | `statusMessage = "需要登录，请使用工具栏的「登录 Steam」。"` | 状态 + 参数，文案在展示点生成 |
| `MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopDetailRefreshSupport.swift:11` | `name != "未知作者"` | 作者名改为 `Optional` 或未知状态 |
| `MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+ItemDetailPresentation.swift:288` | `author == "未知作者"` | 同上 |
| `MyWallpaperX/Modules/SteamWorkshop/UI/SteamWorkshopItemDetailSheet+Observation.swift:15` | `record.sizeText != "未知大小"` | 大小改为数值 + 未知状态 |
| `MyWallpaperX/Modules/Pixabay/UI/PixabayDownloadsInspectorView.swift:114、130、145、146` | `!= "未知"` | 元数据字段改为 `Optional`，缺失由界面决定是否显示 |
| `MyWallpaperX/Modules/VideoLibrary/Core/WallpaperLibrarySupport.swift:90、112、124、163、168、173、182` | `"未知"` 作为返回哨兵 | 展示文案生成与"缺失"状态分离 |
| `MyWallpaperX/App/Debug/DebugWebFailureStateRunner.swift:137` | `payload?["message"] == "Web 宿主反复退出"` | 调试运行器按错误码断言 |

按标准登记为兼容匹配、不翻译的：

| 位置 | 内容 | 处置 |
|---|---|---|
| `MyWallpaperX/Core/PlaybackControl/PlaybackDesktopInputAdmission.swift:28` | `Finder`/`访达` 系统名 | 保留多值集合 |
| `MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialShaderSchema+SamplerPurpose.swift:198` | `ui_editor_properties_*`、`上一个` | 保留，内容兼容 |
| `MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopLibraryContentProjection.swift:66-68` | `视频`/`场景`/`web` 分类 | 保留，内容兼容 |

判定口径：扫描直接命中 12 行（9 行比较、3 行文本匹配），其中 11 行列入上表并归并为 8 条，1 行为系统名兼容匹配。`WallpaperLibrarySupport` 与 `SteamKitBrowse` 两行不直接命中该模式，但分别是上表哨兵与"需要登录"前缀的来源，因此同批处理。

`statusMessage` 的字符串拼接（`+= " 搜索仅作用于已加载作品。"` 等）不构成逻辑判定，但会把同一状态拆成不可翻译的碎片。批次 0 把它改为"状态 + 参数"的结构化表示，展示点在需要时组装文案。

<a id="responsibility"></a>
## 4. 职责与数据流

```
界面展示点（唯一文案 owner，英文源）
    String(localized: "English text")  ──►  Localizable.xcstrings
                                             ├─ en（源，值 = 源码原文）
                                             └─ zh-Hans 等译文
系统语言 ──► 选择语言资源 ──► 运行时返回译文（未命中回退 en）

Info.plist 可见键 ──► InfoPlist.xcstrings
帮助书 ──► MyWallpaperXHelp/<lang>.lproj/index.html
SteamService helper ──► 错误码 + 诊断 message ──► App 映射为本地化文案

检查模块（标准第 13 节）
    源码 key 集合 ──► 与 en 表比对 ──► 与各译文表比对 ──► 门禁
    编译期提取（exportLocalizations / stringsdata）──► 权威校验
```

- 文案 owner 是界面展示点；模型层只提供 identity 与类型化数据，例外是页面/枚举的标题投影函数（如 `WallpaperLibraryPage.title(playlistName:)`），它调用本地化入口但不参与比较。
- 诊断由产生方负责，固定中文，不进界面。
- 检查模块只拥有"源码与资源是否同步"的判断，不拥有译文质量与布局结论。

<a id="batches"></a>
## 5. 批次

### 批次 0：地基（已完成）

范围：拆解[第 3 节](#decouple-inventory)的耦合点；`statusMessage` 改为状态；helper 错误码化；建立 `Localizable.xcstrings` 与 `InfoPlist.xcstrings` 骨架（`en` 源表就位，`zh-Hans` 条目一并生成）；写入 `CFBundleDevelopmentRegion`；落地[标准第 13 节](localization-contract.md#sync)的检查脚本与门禁；登记例外。

停止条件：中文界面与行为完全不变；编译通过；耦合清单清零或已登记；检查模块能对当前代码给出稳定结论（此时代码尚未接入入口，应报告"待迁移"而不是大量假阳性）；用一条人为改文案的演练证明门禁能报出"新 key 缺失 + 旧 key 孤儿"。

### 批次 1：主 App 壳层（已完成）

范围：主菜单与快捷键（`MainMenuBuilder`、`WallpaperLibraryCommands`、`MainWindowMenuCommands`）、设置窗口（`Shared/Settings`）、状态栏控制面板（`StatusBarPanelView`、`StatusBarPanelPresentation`）、库窗口与工具栏（`WallpaperLibraryWindowToolbar`、`WallpaperLibraryWindowComposition`、`WallpaperLibraryCellAdapter`、`WallpaperLibraryPage`）、命令与导入流程、关于面板。

每一条文案：改写为英文源码 → 写入 `en` 条目 → 写入 `zh-Hans` 译文（值等于迁移前的中文）。停止条件：这批路径的界面文案全部走入口；中文界面与当前逐字一致；检查模块全绿。

### 批次 2：业务模块（已完成）

范围：SteamWorkshop（浏览、登录、详情、下载、属性编辑器）、Pixabay、Pixiv、Wallhaven、VideoLibrary、StaticImageLibrary、Downloads、`Shared/UI` 与 `Shared/Components`。

停止条件：同批次 1；错误提示与空状态一并覆盖。

### 批次 3：长尾（已完成，布局与截图见残余）

范围：错误与恢复建议、无障碍标签与 tooltip、`InfoPlist` 可见键、系统动态锁屏/屏保扩展（`ScreenSaverSources`，含屏保显示名）、Daemon 若有可见文案、帮助书与新文案对齐。

停止条件：全仓界面路径无未接入的硬编码文案；`InfoPlist` 表覆盖所有源 plist 可见键。

### 批次 4：译文审校与布局适配（译文已写，审校与截图待做）

范围：英文源文案审校（拼写、术语、大小写）；`zh-Hans` 全量复核；复数变体补齐；按[标准第 8 节](localization-contract.md#layout)逐处核对固定宽度，按[标准第 9 节](localization-contract.md#formatting)核对区域格式；英文、中文、一份更长语言样张三组关键窗口截图。

停止条件：英文界面无中文；中文界面无回退英文；数量文案在 0/1/2 三个取值下正确；三组截图无截断、重叠、错位；术语与标准表一致。

### 批次 5：验收与收尾（待做）

范围：全路径人工核对；检查模块进入常规验证；临时语言演练；文档角色转换。

停止条件见[第 9 节](#retirement)。

每批独立可回退：译文缺失只会回退到英文源文案，不会改变产品行为；结构改动（批次 0）单独成批，便于定位回归。

<a id="acceptance"></a>
## 6. 验收

- 语言矩阵：英文（源）、简体中文、一份人工样张（比英文更长的语言，如德语）各一轮；每个关键窗口截图：主窗口与网格、工具栏、菜单、设置各分区、状态栏面板、Steam 登录/浏览/详情/下载、Pixabay/Pixiv/Wallhaven 面板、视频与静态图详情、错误弹窗、屏保配置。
- 中文零回归：逐屏与迁移前对比，看不到文案变化；唯一允许的变化是标准术语表要求的替换（如旧「偏好设置」统一为「设置」）。
- 复数：含数量的文案分别用 0、1、2 验证。
- 同步检查：修改一处英文文案但不同步译文，门禁必须失败并报出具体 key；补齐后通过。这是[标准第 13 节](localization-contract.md#sync)的核心验收点。
- 占位符：构造参数类型不匹配的译文，门禁必须阻断；确认运行时不会因格式串崩溃。
- 回退：移除 `zh-Hans` 条目后，中文环境应显示英文而不是空白或 key；确认这是可观察的回退而非静默错误。
- 新增语言演练：按[标准第 11 节](localization-contract.md#add-language)用临时语言走完整流程，证明不改代码即可让界面出现该语言；演练后删除。
- 布局：对 58 处固定宽度约束逐条判定"是否承载文案"，承载文案的改为内容驱动；截图证据保留在批次产物中。

<a id="open-items"></a>
## 7. 未定项

- 是否追加繁体中文（`zh-Hant`）与日语（`ja`）：结构已支持，取决于翻译与排版投入，不在本计划默认范围。
- 译文审校人与流程：机器初稿必须经人工审校后才能标为已翻译；审校责任人在批次 4 前确定。
- 更长语言样张的具体语言：批次 4 前从德语、俄语、法语中选定一份，用于布局验收。
- `Localizable.xcstrings` 的编辑方式：由脚本生成/更新 key 结构与状态，人工只改译文文本；是否允许 IDE 直接编辑并提交，取决于批次 0 的脚本落点。
- 检查脚本的落点与门禁接入方式：见下节。

<a id="parallel-boundary"></a>
## 8. 并行边界

本计划执行期间，仓库 `script/tests/` 目录正由另一任务整理。为避免冲突：

- 本批（标准与计划）只新增文档并登记索引，不修改 `script/tests/**`、不移动脚本。
- 检查脚本与门禁条目已落地为 `script/governance/check_localization.py`、`scene_validation_gates.json`（`localization`）与 `verify_scene_change.py` 的触发条件；若并行任务重构 `script/` 结构，合并时以对方的新结构为准迁移这三处，不保留旧位置副本。
- 共享 JSON（`docs/document-role-index.json`、`script/data/design_gated_areas.json`、`script/data/document_health_baseline.json`）由本计划单点写入并复核，不与其他任务并行修改同一文件。

<a id="retirement"></a>
## 9. 退出条件

满足全部条件后，本文转为历史证据（`docs/history/cross-topic/`），稳定职责只留[标准](localization-contract.md)：

1. 全仓界面路径的文案均经本地化入口，硬编码检测门在常规验证中通过。
2. `en` 源表与 `zh-Hans` 译文完整，占位符、复数、`InfoPlist`、帮助书一致。
3. 检查模块在常规验证中运行，且"改文案不改翻译"能被稳定拦住。
4. 关键窗口在英文、中文与更长语言样张下截图验收通过；承载文案的固定宽度约束已清零。
5. 临时语言演练完成，证明新增语言只改资源。
6. 批次 0 的结构改动（错误码、状态枚举、哨兵值）已在后续批次中稳定，无回退需求。
7. 完成一个发布周期的线上观察，未出现因文案、格式串或回退导致的崩溃与误判。
