# MyWallpaperX 语言适配（本地化）标准

<!-- document-role: stable-contract -->

> 状态：现役规范。2026-11-23 订立，自本文件入仓起对新增与修改的用户可见文案生效。迁移实施状态、批次与当前差距归[语言适配迁移计划](localization-plan.md#current-state)，不由本文件承担。
>
> 适用范围：MyWallpaperX 主 App、系统动态锁屏/屏保扩展（`MyWallpaperXSystemWallpaper`）、`MyWallpaperXWallpaperDaemon`、SteamService helper，以及帮助书在用户界面上暴露的全部文案。
>
> 不在范围：仓库内部文档（`docs/`、`AGENTS.md`）保持中文；第三方内容（Steam 作品标题/作者/描述、Wallpaper Engine 场景内文字）是数据，不是界面文案。

<a id="goal"></a>
## 1. 目标与非目标

目标：英文作为源语言，其他语言（首份为简体中文）以译文资源提供；系统按用户首选语言自动选择，App 不提供语言下拉；新增一种语言只增加译文与登记，不修改产品代码；译文长短变化不得使界面截断、重叠或需要按语言分支布局；源码文案一旦修改，未同步的译文必须被自动发现而不是静默失效。

非目标：运行期热切换语言；按语言定制布局；翻译诊断日志与内容兼容字符串；自动机器翻译直接入仓；把 Xcode 图形界面作为唯一维护入口。

<a id="source-language"></a>
## 2. 源语言、支持语言与回退

- 源语言固定为 `en`（English）。源代码中的英文字面量即该文案的源值与查找 key，见[第 4 节](#api)。
- 工程 `developmentRegion` 与主 `Info.plist` 的 `CFBundleDevelopmentRegion` 都必须为 `en`，并显式写入 plist，不依赖构建设置默认值。
- 支持语言登记表是本标准的一部分，是"App 支持哪些语言"的唯一权威：

| 语言代码 | 名称 | 角色 | 完整度要求 |
|---|---|---|---|
| `en` | English | 源语言 | 资源表必须全量列出（值等于源码原文），见[第 3 节](#resources) |
| `zh-Hans` | 简体中文 | 译文 | 必须 100% 覆盖源表；缺失条目会让中文用户看到英文 |
| `de` | Deutsch | 译文 | 同上；德语平均比英文长约 27%，布局按它核对 |
| `fr` | Français | 译文 | 同上；法语平均比英文长约 30% |
| `ru` | Русский | 译文 | 同上；俄语平均比英文长约 12% |

- "英文是源语言"不等于"英文可以缺条目"：源表必须显式列出每个 key，因为 key 集合比对是[第 13 节](#sync)同步检查的基础，不得依赖"找不到就用 key"的隐式回退。
- `Info.plist` 的 `CFBundleLocalizations` 必须精确列出上表语言代码；新增语言先改本表，再改 plist。
- 匹配与回退规则：系统按用户首选语言列表逐项寻找 App 内的对应语言资源；**全部未命中时使用 `CFBundleDevelopmentRegion`**。因此任何未在上表列出的语言环境（法语、德语、日语等）显示英文。这是把英文定为源语言的直接收益；若将来把源语言改为中文，回退行为与翻译方向都随之变化，属于架构变更。
- 语言代码使用 BCP-47 形式（`en`、`zh-Hans`、`zh-Hant`、`ja`）。禁止 `zh`、`zh_CN`、`en_US` 等模糊或带下划线的代码；`en` 不区分地区，需要英式拼写时另立语言条目，不得共用一个代码。
- 语言切换发生在 App 启动时：修改系统语言或用「系统设置 > 通用 > 语言与地区 > 应用程序」为 App 单独指定语言后，需要重新启动 App 才生效。App 不得声称支持运行中热切换，也不得为此增加自研语言管理状态。

<a id="resources"></a>
## 3. 资源位置与格式

每个可执行产物拥有自己的本地化资源，不共享其他 bundle 的表：

| 产物 | 资源 |
|---|---|
| 主 App（`MyWallpaperX`） | `MyWallpaperX/Resources` 下的 `Localizable.xcstrings`、`InfoPlist.xcstrings` 和 Scene 画质运行读数 `SceneQuality.xcstrings`，共用 en/zh-Hans/ru/de/fr |
| 系统动态锁屏/屏保扩展 | `ScreenSaverSources/Resources/Localizable.xcstrings`、`InfoPlist.xcstrings`，随扩展 target 打包 |
| WallpaperDaemon | 当前无用户可见界面文案，不建资源；若将来出现，按本表另建 |
| SteamService helper | 不建资源；语义经错误码交给 App 生成文案，见[第 7 节](#diagnostics) |

资源采用 **String Catalog（`.xcstrings`）**，理由：

- 它是 Apple 现行标准格式，Xcode 27 新建本地化的默认；单一文件承载全部语言，新增语言只是增加一个 localization 键。
- 内建复数变体（`variations.plural`），不需要额外的 `.stringsdict`。
- 条目自带状态：`extractionState`（是否仍在源码中）与 `localization.state`（是否已翻译），这是[第 13 节](#sync)"源码改动 → 译文必须同步"检查可以直接读取的机器事实。
- 源码侧仍用 `String(localized:)`，由编译期提取与官方 `xcstringstool` 工具链处理，不依赖 Xcode 图形界面。

格式约束：

- `sourceLanguage` 必须为 `en`；每个 key 的 `en` 条目与源码字面量逐字节一致。
- 文件使用 UTF-8 JSON，key 按字符串排序，缩进与换行稳定，避免无意义 diff。
- 文件必须能被 `xcstringstool compile` 成功编译；编译失败等同于资源损坏。
- 翻译未完成时保留条目但不得标记为已翻译；不得用源语言文本冒充译文来"凑满"。唯一的例外是专有名词与非译词（见[第 10 节](#terminology)），它们由译文语言显式填写同一文本，并保持 `state` 为已翻译。

界面文案默认进 `Localizable`。Scene 画质的实际档位读数明确使用同 bundle 的 `SceneQuality`，运行读数独立于原设置选项文案。plist 可见键进 `InfoPlist`。源码检查分别解析默认表和字面量 `table:`，编译提取也按实际表对比。同名 key 在各自表里独立校验。不进表的内容见[第 5 节](#scope)。

<a id="api"></a>
## 4. 代码入口与 key 规则

代码中的界面文案唯一入口是 `String(localized:)`；plist 与帮助书不经过代码入口，见[第 3 节](#resources)与[第 14 节](#help-book)。

默认写法：`String(localized: "English text")`。此时 key 与源语言值都是这段英文原文。

```swift
label.stringValue = String(localized: "Settings")
status.stringValue = String(localized: "Loaded \(items.count) items.")
```

插值：编译器把插值按实参类型编译为格式占位符，key 就是带占位符的字符串。占位符对照（2026-11-23 用 Xcode 26 工具链实测，Xcode 27 行为一致）：

| 实参类型 | 生成的占位符 |
|---|---|
| `Int` | `%lld` |
| `UInt` | `%llu` |
| `Float` | `%f` |
| `Double`、`CGFloat` | `%lf` |
| `String`、`Substring` | `%@` |
| `NSObject` 及子类 | `%@` |

`Bool`、枚举与自定义结构体没有内置支持：直接插值会退化成 `String(describing:)` 的未本地化描述，占位符变成 `%@`，且触发编译警告。这类值必须先转成明确的展示文案，或按条件生成整条文案，不得直接插进 `String(localized:)`。

因此上例的 key 是 `Loaded %lld items.`；`zh-Hans` 的值为 `已加载 %lld 项。`。

占位符规则：

- 译文值中的占位符规格必须与源 key 完全相同（`%lld` 不得改成 `%d`、`%@` 不得改成 `%ld`），只允许追加上位置序号。
- 译文语序需要调整时，在译文值里使用位置参数，例如 `%1$lld`、`%2$@`；源 key 保持无位置的 `%lld`、`%@`。位置参数只允许出现在译文值中，不得写进源代码字面量。
- 值中需要输出字面百分号时写 `%%`。
- 参数个数、类型、顺序与占位符不匹配会在运行时崩溃或显示错值，属于阻断级错误，见[第 12 节](#gates)与[第 13 节](#sync)。

需要稳定 key 或同形异义时，使用分离 key/defaultValue 形式：

```swift
String(localized: "menu.file.open", defaultValue: "Open", comment: "File menu item, distinct from the Open button in the inspector")
```

- `menu.file.open` 是稳定 key，`Open` 是源语言默认值；所有语言的条目都用 `menu.file.open` 作 key。
- 该形式只允许在两种情况下使用：同一个英文词在不同语境需要不同译文；文案需要跨版本保持 key 稳定。使用处必须登记到[第 15 节](#exceptions)。
- 默认使用英文原文作 key，因为改文案即改 key，能被[第 13 节](#sync)的集合比对直接发现；稳定 key 会放弃这项自动发现能力，因此只在确有必要时使用。
- key 命名使用小写点分语义标识（`模块.对象.属性`），不得包含文案，不得包含空格。
- `comment:` 只在译员必须知道语境时提供，不复述文案内容。

禁止事项：

- 禁止使用 `NSLocalizedString` 及其变体：插值需要手写 `String(format:)`，编译期占位符提取不可靠，且会与 `String(localized:)` 形成两套写法。
- 禁止自建 `L()`、`localized()`、`tr()` 等包装函数隐藏 key：它会让静态检查无法确认"这条文案走了本地化入口"，也会让资源表与源码失联。
- 禁止在运行时拼接 key（如 `String(localized: "page." + rawValue)`），除非 key 来自受控常量集合且该处登记到[第 15 节](#exceptions)。

<a id="scope"></a>
## 5. 必须本地化与禁止本地化

判定标准只有一条：这段文本是否会以人类可读的形式呈现给用户，还是参与身份、匹配、协议或持久化。前者本地化，后者禁止本地化。

必须本地化：

- 窗口、面板、菜单、菜单项、工具栏按钮与溢出菜单、分段控件、标签、占位符、表头、页脚。
- 弹窗标题、正文与按钮、确认文案、错误提示、空状态、进度描述、状态行、提示条。
- tooltip、`NSImage` 的无障碍描述、`setAccessibilityLabel`、`setAccessibilityHelp`、`setAccessibilityDescription`。
- 源 `Info.plist` 中的权限用途描述及将来加入的 `CFBundleDisplayName` 等可见键。
- 系统设置里显示的扩展名称与帮助书正文。

禁止本地化（必须保持现状并登记到[第 15 节](#exceptions)）：

- 内容兼容匹配：Wallpaper Engine 场景属性键（`ui_editor_properties_*` 及中文别名）、场景项目 JSON 字段、内容分类字符串（`视频`、`场景`、`web`）。这些值来自第三方内容，翻译必然破坏兼容。
- 系统名匹配：`Finder`/`访达` 这类系统应用显示名，按多值集合匹配，不随 App 语言变化。
- 标识符与身份：bundle id、通知名、`UserDefaults` key、目录名、文件名、URL scheme、selector、菜单 identifier、持久化字段。
- 协议字段：SteamService helper 的 `code`；`message` 只作诊断文本，不参与判断，见[第 7 节](#diagnostics)。
- 诊断输出：`diagnostics` 文本、日志、抓包与调试探针。
- 测试夹具、样本数据、第三方许可证（`LICENSE`、`NOTICE.md`）。
- 第三方内容本身：Steam 作品标题/作者/描述、Pixiv/Pixabay/Wallhaven 返回值。它们在界面上原样显示，不做翻译。

<a id="plural"></a>
### 5.1 数量与复数

只要一条文案在任一语言中会因数量改变词形（英文的 `1 item` / `2 items`，中文不变），它就必须在 catalog 中使用复数变体，而不是固定文本。

```json
"Loaded %lld items." : {
  "localizations" : {
    "en" : {
      "variations" : {
        "plural" : {
          "one" : { "stringUnit" : { "state" : "translated", "value" : "Loaded %lld item." } },
          "other" : { "stringUnit" : { "state" : "translated", "value" : "Loaded %lld items." } }
        }
      }
    },
    "zh-Hans" : {
      "variations" : {
        "plural" : {
          "other" : { "stringUnit" : { "state" : "translated", "value" : "已加载 %lld 项。" } }
        }
      }
    }
  }
}
```

- 源语言 `en` 必须同时提供 `one` 与 `other`；中文只提供 `other`。
- key 仍是源码字面量 `Loaded %lld items.`，不因复数变体而改变。
- 不得用"共 N 项"这类回避词形的写法来绕过复数规则；判断依据是语言规则，不是开发者语感。

<a id="decouple"></a>
## 6. 文案与逻辑解耦

本地化文案不是稳定的程序常量。任何把文案当逻辑输入的做法都禁止：

- 不得对文案做 `==`、`!=`、`hasPrefix`、`hasSuffix`、`contains`、正则匹配或 `switch case`。
- 不得把文案存进字典当键、当作状态值、当作持久化字段或跨进程序列化语义。
- 状态、结果、模式一律用枚举或结构体表达；文案只在最终展示点生成。

跨进程边界（App ↔ SteamService helper）只认结构化字段：错误码决定语义，可选上下文参数携带可变信息；`message` 是诊断文本，可以显示，但不得用于判断。

模型层与界面层的分工：模型拥有 identity 与稳定标识，界面拥有展示文案。模型可以提供 `String(localized:)` 生成的展示投影（例如页面标题函数），但 identity 字段不得存本地化结果，展示名不得参与相等比较。

已在代码中存在的违规点及其清理批次归[迁移计划](localization-plan.md#decouple-inventory)；本文件只规定规则与例外分类，不维护当前代码行号。

<a id="diagnostics"></a>
## 7. 失败消息分层

同一条字符串不得同时承担"给用户看的提示"和"给开发者看的诊断"。

- 用户可见错误：实现 `LocalizedError`，`errorDescription`/`recoverySuggestion` 由本地化入口生成；界面只读取这些属性。
- 诊断：固定使用中文，不本地化，不写入界面；诊断文本里可以包含原始错误码与关键参数。
- 界面不得直接拼接底层错误字符串（例如 `"Failed: \(error)"`）；应按错误码选择本地化模板，再填入已经类型化的参数。
- 会显示在界面上的失败信息，如果来自 helper 或子进程，必须由 App 侧按错误码映射成本地化文案；helper 的 `message` 至多作为诊断补充，不能直接当界面文案。

<a id="layout"></a>
## 8. 字符长度与布局

英文是源语言，中文译文通常更短，但这不构成"英文不会变长"的理由：同一 key 将来还会进入德语、法语等更长的语言，且中文短不等于布局安全。界面必须按"译文可能显著变长"设计。

强制规则：

1. 承载文案的控件禁止使用固定宽度约束。`widthAnchor.constraint(equalToConstant:)` 只允许用于图标、缩略图、颜色块、分隔线等纯图形；用于标签、按钮、下拉框、分段控件即为违规。
2. 单行标签允许尾部截断，但必须同时提供 tooltip 或无障碍标签说明完整内容；不得静默截断。
3. 说明性文本、提示、错误正文允许多行：`maximumNumberOfLines = 0`、`lineBreakMode = .byWordWrapping`，并让高度跟随内容。
4. 按钮、分段控件、弹出菜单的宽度由内容与 `intrinsicContentSize` 决定；不得为省空间写死宽度。
5. 工具栏项必须允许溢出到系统 overflow 菜单，不因一项变长挤压其他项。
6. 设置行的标题与副标题使用比例约束或可伸缩约束，绝对宽度仅保留给图标与控件列。
7. 表格与列表列宽按内容或比例分配，不使用按字符数估算的固定列宽。
8. 不得通过降低字号、压缩字距、缩小行高来容纳译文；字号沿用现有界面字号。
9. 不得写"某语言专用"的布局分支。需要差异时，按内容测量结果自适应，而不是按语言代码判断。
10. 文案变化后必须重新核对约束优先级：可变宽度的控件要能压缩且不被要求同时满足两个必需约束。

实施时的高风险区域（既有固定尺寸较多，需逐项截图核对）：设置面板行、状态栏控制面板、主窗口工具栏、详情/信息面板标签列、Steam 登录与详情面板、下载任务行、屏保配置界面。

验收必须覆盖"比英文更长"的代表语言（例如德语或俄语的人工样张），而不是只验证英文；只验证英文不能证明布局对多语言安全。

<a id="formatting"></a>
## 9. 格式化、排序与区域

文案只是语言适配的一半；日期、时间、数字、大小与排序必须跟随系统区域，否则英文界面会出现中文格式，或中文系统下解析失败。

- 用户可见的日期、时间、时长、数字、文件大小与百分比必须使用跟随系统的格式化器（`DateFormatter`、`DateComponentsFormatter`、`ByteCountFormatter`、`MeasurementFormatter` 的默认 locale，或显式 `Locale.current`）。不得手写 `yyyy-MM-dd`、`%d minutes` 这类拼接来决定显示格式；带单位的文本本身仍按其来源本地化。
- 协议、缓存键、文件名与持久化中的时间必须固定使用 `Locale(identifier: "en_US_POSIX")` 与明确的 `dateFormat`/`timeZone`，不得使用 `Locale.current`。当前 HTTP 日期解析（`WebWallpaperLocalSchemeHandler+Resolve.swift`、`PixivClient.swift`、`WallhavenClient.swift`）已是该写法，必须保持。
- 面向用户的文本列表排序使用 `localizedStandardCompare`；identity、数值、ID 排序保持原有比较，不因本地化改写。
- 自然语言文本不得用 `uppercased()`/`lowercased()` 生成展示内容（其大小写规则与语言无关）；文件扩展名、技术标识等确定性字符串可以直接大写。
- 数字与参数不得手工拼接千分位、单位或正负号；使用格式化器，且格式化结果仍按[第 4 节](#api)的占位符规则传入 `String(localized:)`。

<a id="terminology"></a>
## 10. 术语与风格

英文是源语言，因此源码本身就决定英文术语。本表是**中文译文与其他译文**的唯一权威；源码中的英文拼写也必须与"英文"列一致，不得同一概念出现两种写法。

| 英文（源） | 中文译文 | 说明 |
|---|---|---|
| wallpaper | 壁纸 | 不译作 background / desktop picture |
| live wallpaper | 动态壁纸 | 仅在与静态壁纸对比时使用 |
| Steam Workshop / Workshop | 创意工坊 | 产品名保留大写 W |
| Scene | 场景 | 产品概念，保留大写；不译作 scenario |
| Video | 视频 | 模块名与类型名 |
| Web wallpaper | 网页壁纸 | 不译作 HTML wallpaper |
| playlist | 播放列表 | |
| Favorites / favorite | 收藏 / 收藏 | 中文按语境统一为"收藏" |
| Subscribe / subscription | 订阅 | Steam 订阅语义 |
| Downloads / download | 下载 | 区域与动作同名 |
| Properties | 属性 | 场景属性面板 |
| Wallpaper Engine | 壁纸引擎 | 第三方产品名，在中文里保留英文或使用既有中文名 |
| menu bar | 菜单栏 | macOS 的菜单栏，不译作状态栏 |
| menu bar panel | 状态栏控制面板 | 指菜单栏里的控制面板 |
| Settings | 设置 | macOS 13 起不写 Preferences |
| Preferences | 不再使用，统一为 Settings / 设置 | 源码与译文中的旧词一并替换 |
| screen saver | 屏幕保护 | |
| Fill Screen | 填充屏幕 | 屏保缩放选项 |
| unknown author | 未知作者 | 若仍作为展示文案；同时按[第 6 节](#decouple)改为状态值 |

风格规则：

- 英文源码文案遵循 Apple 英文风格：菜单项与按钮用 Title Case，句内说明用 sentence case；同位置存在系统原生文案时，以系统英文为准。
- 中文译文使用全角标点；其他译文使用目标语言标点，不得混用中文标点。
- 省略号统一 `…`（单字符），不写 `...`。
- 不得自创译名。出现新概念时先登记本表并说明依据，再进入代码。

<a id="add-language"></a>
## 11. 新增语言流程

1. 在[第 2 节](#source-language)的支持语言登记表增加一行。
2. 用脚本以源表（`en`）为基准生成新语言的条目骨架：key 与源表完全一致，`state` 为未翻译，值留空或源文占位（不得标记已翻译）。
3. 翻译全部条目；复数变体至少写 `one`/`other`，中文只写 `other`。
4. 在工程 `knownRegions` 与 `Info.plist` 的 `CFBundleLocalizations` 增加语言代码；catalog 的 `sourceLanguage` 保持 `en` 不变。
5. 运行[第 12 节](#gates)与[第 13 节](#sync)的校验，全绿后进入验收。
6. 用源语言、新语言各做一轮关键窗口截图核对布局（见[第 8 节](#layout)）。
7. 更新本表与迁移计划的对应行。

语言增量不得修改产品代码。若新增语言需要改代码（例如硬编码分支、按语言判断的布局），说明对应文案没有走标准入口，必须先修正入口，再继续加语言。

从右到左书写（阿拉伯语、希伯来语）与需要复杂断行的语言（泰语等）属于额外排版范围：它们仍只增加资源，但需要先单独评估镜像布局与断行，不在"只加资源、不改代码"的常规承诺内；评估结论进入本文档后再实施。

<a id="gates"></a>
## 12. 校验与门禁

以下检查由迁移计划落地为脚本与门禁；本文件定义"查什么、什么算失败"。数据来源与同步机制见[第 13 节](#sync)。

| 检查 | 失败含义 |
|---|---|
| 源码 key 有资源条目，编译器提取时再核对孤立条目 | 新文案缺资源，或有可移除的旧条目 |
| 各译文语言的 key 集合 = 源表 key 集合 | 缺条目会让用户回退到源语言；多余条目是失效翻译。阻断 |
| 同一 key 的占位符集合、类型、顺序一致（只允许位置序号差异） | 类型不匹配会在运行时崩溃；顺序不一致会显示错值。阻断 |
| catalog 无 `extractionState == stale` 条目 | 源码已删除该文案，表中仍有残留。阻断合入 |
| 所有已登记语言无未翻译条目（`state` 非 translated） | 目标语言会出现源语言文本。阻断合入 |
| `xcstringstool compile` 成功 | 资源损坏或结构非法。阻断 |
| 界面代码路径中的中文/英文硬编码字面量必须位于 `String(localized:)` 调用内 | 新增硬编码文案会悄悄绕开本地化。阻断合入 |
| 不得对文案做比较、前后缀、包含、`switch case` | 翻译后逻辑失效，且难以在运行时发现。阻断合入 |
| `InfoPlist` 表覆盖源 plist 中已登记的可见键 | 应用名、权限描述回退源语言。阻断合入 |
| 帮助书与支持语言的目录一致 | 语言切换断链。阻断合入 |

白名单只允许三类：诊断与日志、内容兼容匹配、测试与样本。白名单条目必须写明原因，不能按目录整体豁免。

<a id="sync"></a>
## 13. 源码文案变更与译文同步（检查模块）

这是本标准的强制机制，不是可选增强。它回答一个具体问题：**源码里的文案改了，译文怎么保证没有悄悄失效？**

### 13.1 为什么默认用英文原文作 key

改文案即改 key。这看起来"不稳定"，但正是同步检查的基础：改动会在 key 集合比对中立刻表现为"旧 key 消失、新 key 出现"，工具可以精确报出，而不是让旧译文继续套在新语义上。稳定 key（[第 4 节](#api)的分离形式）放弃这项能力，因此只在必要时使用，并登记例外。

### 13.2 三层检查与数据来源

| 层 | 比对什么 | 数据来源 | 运行时机 |
|---|---|---|---|
| A：源码 ⇄ 源表 | 源码实际引用的 key 集合与 `en` 条目是否一致 | 轻量静态解析源码中的 `String(localized:)` 字面量（插值归一化为占位符） | 每次提交、合入前 |
| B：资源表之间 | 各语言 key 集合、占位符、翻译状态是否与源表一致 | 直接读取 catalog JSON | 每次提交、合入前 |
| C：编译期权威 | 编译器实际提取的 key 与占位符类型是否与源表一致 | `xcodebuild -exportLocalizations` 导出的 XLIFF（内部使用编译期 stringsdata） | 里程碑、发布前、批次验收 |

- 层 A 覆盖字面量和插值位置。提交钩子 `--changed` 以 Git index 的源码和资源为准。CI 用 `--source --hardcoded --compile` 校验两个 target 的字面量及各自资源，实参类型仍归层 C。
- 层 C 是唯一能证明"占位符类型与源码实参匹配"的检查，代价是需要构建，因此不作为提交级门禁。
- 层 A 与层 C 结论冲突时以层 C 为准，并修正层 A 的解析规则。

脚本只读报告。新增 key 与译文在同一变更里写入对应 catalog。

普通构建关闭字符串提取。显式传 `SWIFT_EMIT_LOC_STRINGS=YES` 构建后，用 `check_localization.py --extraction <主 App 的 .stringsdata 目录>` 校验精确 key。XLIFF 导出可用于发布前补充核对。

### 13.3 检查模块必须报出的结论

1. `missing_keys`：源码有、源表无。通常是刚加入文案但忘记同步。
2. `orphan_keys`：源表有、源码无。通常是改了文案但旧条目没删，对应 catalog 的 `stale` 状态。
3. `missing_translations`：某语言缺条目或 `state` 不是已翻译。
4. `placeholder_mismatch`：同一 key 在源码与表之间、或不同语言之间的占位符规格不一致。
5. `hardcoded_text`：界面路径出现未走入口的文案字面量。

每项都必须给出文件、key、语言与差异，而不是只给计数；否则无法据此修复。

### 13.4 一次改文案的完整责任链

1. 修改源码英文文案 → key 变化。
2. 跑层 A 检查新增 key，按需用层 C 查验孤立条目。
3. 在同一提交内更新 `en` 条目（新增、删除旧条目）。
4. 同步更新所有译文语言；未完成的条目不得标为已翻译。
5. 层 B 全绿后合入。

任何一步缺失，门禁必须失败。不允许"先合入再补翻译"。

### 13.5 与 Xcode 图形界面同步的关系

Xcode 的 catalog 自动同步发生在 IDE 内。已核对 Xcode 27.2 的构建规格：`XCStrings.xcspec` 定义的命令行任务是 `xcstringstool compile`，只编译、不写回源文件；`SWIFT_EMIT_LOC_STRINGS` 的用途是本地化导出（`xcodebuild -exportLocalizations`），不是日常构建。因此本仓库不把"IDE 自动同步"当作事实，检查与同步由上述工具链与脚本显式完成，结果可复现、可审查。

### 13.6 检查模块的边界

- 它不判断译文是否"翻译得对"；语义质量靠人工审校（[迁移计划](localization-plan.md#open-items)）。
- 它不替代布局验收；文案变长导致的截断必须靠截图（[第 8 节](#layout)）。
- 它不检查第三方内容与诊断文本，这些按[第 5 节](#scope)不在本地化范围。

<a id="help-book"></a>
## 14. 帮助书

帮助书位于 `MyWallpaperXHelp/<lang>.lproj/index.html`，由系统按固定的 `CFBundleHelpBookName` 注册，显示标题来自该语言目录的 `InfoPlist.strings`。

- 每个支持语言必须有对应目录，语言切换链接指向对应目录，不得依赖重定向占位页。
- 帮助书正文的术语必须与[第 10 节](#terminology)一致，且与 App 界面同一事实只维护一处：界面文案变化导致帮助书失真时，同批修正帮助书。
- 仓库内部文档不翻译，也不与帮助书共享内容。

<a id="exceptions"></a>
## 15. 例外登记

例外分三类，出现时必须在此登记（路径 + 原因 + 退役条件），未登记不得新增。

| 类别 | 允许内容 | 退役条件 |
|---|---|---|
| 内容兼容匹配 | Wallpaper Engine 属性键、场景项目字段、内容分类字符串、系统应用显示名 | 上游内容格式变更时重评，不随 App 本地化变化 |
| 稳定 key | `String(localized:defaultValue:comment:)` 的使用点 | 该文案不再需要跨版本稳定或不再同形异义时，改回原文 key |
| 动态 key | 由受控常量集合构造的 key | 集合改为静态字面量时删除 |

初始登记（迁移批次 0 会补齐其余）：

| 位置 | 内容 | 类别 | 原因 |
|---|---|---|---|
| `MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialShaderSchema+SamplerPurpose.swift` | `case "ui_editor_properties_framebuffer", "上一个"` | 内容兼容匹配 | 匹配 Wallpaper Engine 作者脚本中的属性标识 |
| `MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopLibraryContentProjection.swift` | `case "video", "视频", "视频壁纸"` 等分类 | 内容兼容匹配 | 匹配第三方内容元数据 |
| `MyWallpaperX/Core/PlaybackControl/PlaybackDesktopInputAdmission.swift` | `ownerName == "Finder" \|\| ownerName == "访达"` | 内容兼容匹配 | 系统应用显示名随系统语言变化，按多值集合匹配 |

<a id="revision"></a>
## 16. 修订规则

- 修改本标准必须同批同步[迁移计划](localization-plan.md)中受影响的范围、批次与验收，以及 `docs/README.md` 入口说明。
- 术语变更须全表检索译文与帮助书，不允许只改一处。
- 增加、移除语言必须走[第 11 节](#add-language)流程并更新支持语言表。
- 源语言调整（例如改为中文）属于架构变更，必须先改本文件与工程区域设置，再谈迁移，不得在批次实施中临时变化。
- 本文档的复核证据记录在 `docs/document-role-index.json`；超过 60 天须实际复核对应范围。
