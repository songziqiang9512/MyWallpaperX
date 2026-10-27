# UI正确性与调度审计结算

> **历史证据 — 非现役入口**

> 截止：2026-10-27。基于codex/engine-refactor-program的492a64dc7，在隔离树完成本轮已证问题与限定回归；验收时改动未提交、未合并。本文不定义下一项任务，也不代表全仓零缺陷或真实账号/桌面全量验收。
> 当前职责：[AppKit合同](../../architecture/appkit-migration.md)、[主界面视觉与交互](../../development/main-window-playlists-redesign.md)、[播放事务](../../architecture/playback-lifecycle-transaction-design.md)、[根规则](../../../AGENTS.md)。原URL保留为[永久导航](../../development/ui-quality-audit.md)。

> 后续整合授权（2026-10-27）：用户已明确要求三会话轮流提交并合入主仓 `codex/engine-refactor-program`；三方已确认启动专项→UI专项→新模块接入。本文的“未提交”等状态只指原验收时点；实际整合提交和验证按后续Git及整合记录核对。

本次整合以启动专项合入点 `480089e7d` 为基线：缓存沿单一请求复用已算出的磁盘 URL，保留取消消费者、失败结论及在飞清理；图片详情同步消费缓存交付，去掉多余主队列跳转及同栈重复取消检查。回归夹具提取实际缓存交付闭包，明确验证三次请求中的两次有效主线程交付与一次取消抑制，保留换源像素、共享租约和释放反例。两处 Optional 写法沿原 actor 上下文修正；JavaScript 夹具仅将无插值模板改为等价字面量，依赖门沿原算法删除一条已退役豁免。

整合验证：共享资源八组回归、实际 Inspector、导入 worker/回执/重置/混排及 Debug/Release Web 属性回放门通过；最终增量 Debug 26.265 秒、零警告、strict 验证通过，构建输入零漂移。独立静审无阻塞；文档登记/健康/全链接及代码、断言、依赖、产物门通过。未扩大为真实账号、整 App 逐页或完整桌面验收；提交与合入身份由 Git 记录，后续第三棒继续基于本批主仓 HEAD 整合。

## 结算范围

- 已证问题覆盖菜单重复/输入撤销、Inspector资源及元数据、异步反馈、CPU原位回绕、音量重复意图、状态栏封面、登录回放、属性同值提交及缓存失败恢复；UI-10/16未证收益或必要性，不引新产品层。
- 最新片真实菜单/恢复/设置、identity/adapter/cache/AV、实际Inspector/Grid/SIL/Steam/键盘菜单门均闭合；原失败、装配修正与部分凭据分别保留。最终Debug25.905秒，strict成功，声明输入零漂移；只证明相应范围。
- 未验：最新整App逐页手测、真实在线账号/网站、真实媒体删除、完整桌面/Release、多屏与真人硬件、完整性能/能耗。模拟叶不能代替这些验收。
- 现场保留：本工作树与一份增量DerivedData/最新候选，未暂存、未提交、未合并、未推送；没有修改他人App、真实媒体或机器生成记忆。

导航收尾另修10处既有失效链接：退役源码改为历史路径、本机忽略产物改为明文路径，保能力与历史结论，原测试门未放宽；登记和链接以最终文档凭据为准。

## 完整工作卡与证据边界

以下是冻结的本轮记录，其中原候选、失败与阶段说明只适用于当时。稳定职责已回AppKit合同，不从本页重开任务。

<!-- preserved-body:start -->
# 全仓 UI 正确性与调度审计

<!-- archived-original-role: active-plan -->

> 2026-10-27：已将隔离 UI 工作树从 2fb50b5f1 快进同步到主仓 `codex/engine-refactor-program` 的 492a64dc7，本轮审计已结算：已证问题、对应反例、独立复审及最终Debug均闭合；无证据的候选不加产品层。所有改动未经提交、合并或推送。本文维护本次覆盖、发现、工作卡与验证；视觉标准继续归[主界面方案](../../development/main-window-playlists-redesign.md)，来源能力归各专题，不建立第二套 UI 或播放真值。

<a id="scope"></a>
## 目标与执行边界

从真实用户入口追到动作、持久化或播放、反馈及下一次操作：检查全仓 UI 逻辑、前后台调度、菜单与按钮、异步撤销、功能完整性和视觉一致性。先修可确认的操作错误、错源/迟到事件、无消费者工作和重复入口，再处理有证据的交互与呈现问题。保持原有布局与交互合同，原生控件及系统强调色优先。

遵守根[AGENTS.md](../../../AGENTS.md)的用户原话：不新增无实际功能收益的校验、认证、重复计算和嵌套；发现现有此类代码主动清除。沿原 owner 精简，不为审计建立新 coordinator、认证层、后台轮询、永久副本或多层 fallback。取消、代次与资源边界只在真实消费处承担职责；不能以删除检查数量冒充提速。

当前采用三个独立只读面与 Root 整合：Shell/菜单与本地操作、在线来源完整链、设置/窗口/缩略图生命周期；随后按互不重叠的精确文件实施、交叉审查。Root 独占共享文档与 JSON，构建/测试/原生窗口串行。其他工作树与真实媒体不改动。

比较后的执行顺序：操作链错误能由事件与结果直接反证，先闭合；不可见消费者调度紧随其后；纯视觉细节以实际窗口判断。没有调用证据、反例或成本事实的猜测只记候选，不据此扩大代码。重要职责或持久化变化先修所属设计，既有合同内的局部修复直接实施。

<a id="coverage"></a>
## 覆盖矩阵

每个面检查入口→正常/失败/取消→切页/切选/关窗→再次操作；“静态已查”不等于真实功能验收。后续发现更新对应工作卡，未检查的范围明确保留。

| 面 | 检查范围 | 当前覆盖与边界 |
|---|---|---|
| 主窗口与路由 | 固定侧栏、三组、本地/下载/最近/喜爱/列表、返回、搜索/筛选/排序、缩放 | 入口静态及实际Toolbar/Grid/菜单门已验；未冒称最新整App逐页手测 |
| 菜单与输入 | 主菜单、右键、toolbar/overflow、快捷键、单选/多选、原生文本/模态输入域 | UI-01真实组合与Commands事务门过；UI-17/22完整恢复组合及原生菜单/输入门通过；菜单外观与真人硬件另验 |
| 关系与文件 | 导入、隐藏/移除、物理删除、列表成员、编辑封面、Picker、撤销、只读/重置 | 原Commands事务CLI通过；保来源与Store事务，真实媒体删除不执行 |
| 播放与反馈 | 所有卡片 play/pending/stop、详情、手动来源、顺序/随机/计时、错误回滚 | 已追原Manager/Workspace发布链；UI-09真实音量调用链及原Mux门通过，本轮未做四类型真实桌面验收 |
| Steam | 公开/个人/作者、搜索分页、返回、账号/订阅、下载/重试/取消、详情 | UI-02原生Toolbar门及UI-12原生22项门通过；UI-20独立fallback缓存清理及AV/服务原门通过，真实账号未使用 |
| Pixabay | 浏览/搜索、分页、下载、详情与已下载联合页 | UI-02原生Toolbar/UI-08详情及相关共享API/CLI已过；UI-18真实visible-first/暖旧hint/换源终态门通过，未冒认线上服务 |
| Wallhaven / Pixiv | 搜索/排行/作者、登录/API key、分页、原图/多页、下载、关系、恢复 | 492a新链已静态审计；UI-07真实菜单/下载busy CLI过，Auth服务门过；真实账号未验 |
| 卡片与详情资源 | 可见/预取/hover、GIF/视频预览、复用、切选、关闭、源变更/清缓存 | Video/SIL/Pixabay真实原生视图/AV交付/cache leases通过；UI-18错源旁路退出，真实首消费者/换源终态门通过 |
| 前后台 | App hidden、窗口最小化/遮挡/关闭、面板开合、计时与采样 | UI-04采样成本已测且发现UInt32差值错误；数值双配置门/图标门过，未认整App提速 |
| 设置与其他窗口 | 偏好、热键、导入导出、重置/缓存、更新/About/Help、状态栏 | UI-06原动作门、UI-09真实音量链、UI-11原生封面门通过；UI-19/21全清及负缓存恢复原门通过 |
| 呈现与可访问性 | 深浅、系统强调色、透明度/高对比、禁用/空/错状态、AX、尺寸与安全距 | 已查实际原生组件、像素/几何/生命周期/输入；完整整App逐页外观、真实AX/硬件仍未验 |

<a id="work-cards"></a>
## 工作卡

| 卡 | 事实 / 用户后果 | 实施边界与最小反例 | 状态 |
|---|---|---|---|
| A00 基线与规则 | 本树已同步 492a64dc7；根规则换成用户最新两段原话 | 保原提交与其他树；无提交授权 | 已同步；原话规则与代码均未提交 |
| UI-01 Steam 重复 Finder | 通用 Commands 已加 reveal，ready Steam 源菜单组合又加同名项；右键及更多重复 | 共享组合保一个 reveal；独立浏览源菜单仍有原能力；ready/非ready/多选/其他来源及固定目标 | 真实组合菜单/Commands事务门通过；默认独立源菜单能力保留 |
| UI-02 搜索延迟越页 | Steam/Pixabay debounce 未随离页/导航撤销，旧输入可在切列表/作者/个人后写新上下文 | 沿原 pending 工作取消与原导航身份收口，不加第二调度器；正常输入/快切/关闭/旧回包/新输入 | 实现及二次交审、真实原生toolbar门通过 |
| UI-03 无消费者预览 | Video/SIL Inspector 静态缩略图请求未传已有 cancellation，切选/关闭后仍保活 | 沿现 ThumbnailCache 消费租约撤销，保同键其他消费者与当前图；A→B/关闭/共享/迟到与暖命中 | 视频/图片原生视图、AV metadata/cache leases通过；无消费者/共享/A→B→A反例通过 |
| UI-04 CPU计数器 | Mach原生UInt32 ticks先扩成UInt64再差分，回绕值错误甚至总和溢出 | 先原位32位环绕差、再64位求和；无新guard/时钟，正常/单多回绕/失败/零差及初次语义 | 已实现，D/R真实CPU方法与图标门通过 |
| UI-05 SIL元数据 | 同ID图片补齐尺寸/最近使用后，详情只更新actions，元数据可能保持旧值 | 沿原updateLibraryActions差分刷新，预览源不变不重读；保详情位置/滚动 | 实际SIL视图元数据/echo/source/取消反例通过，未改原布局/滚动条 |
| UI-06 清理缓存反馈 | 设置重复清Steam预览namespace；在线actor清理未await即提示完成 | App动作清单交回原Steam owner；原动作async完成后提示，pending禁用同一按钮，关窗不留结果sheet | 实际动作/异步终态及原namespace门通过 |
| UI-07 在线图片菜单 | 下载中菜单仍启用两个开始动作，底层拒绝后用户无反馈 | 用已有busy进度禁用开始动作并保取消，不新增apply意图owner | 真实菜单busy/开始/取消CLI通过 |
| UI-08 Pixabay冷详情图 | 冷缓存开已下载详情仅快照取图，稍后补图无消费者更新 | 复用原缩略图producer一次可取消需求，原位换预览，不重建整面板 | 共享API/相关CLI及真实Inspector视图通过；UI-18另追既存visible旁路 |
| UI-09 音量重复意图 | 普通正值滑杆每次发送未改变的静音状态，触发第二轮volume IPC/同值持久化 | 仅UI入口在公共静音状态确变时发送mute，主volume/跨0/显式mute重投保留 | 真实UI→Manager→Mux→Video/Scene/IPC叶门与原Mux门通过 |
| UI-10 采样调度取舍 | 优化CLI真实read首3.09ms/暖1.46ms，GPU占1.42ms；其余约0.043ms/2s | 不为小收益加按需字段和重开priming；GPU异步仅作候选，保原唯一timer/Monitor与rate基线 | 未改调度，不称已测卡顿/提速 |
| UI-11 状态栏封面 | 完整content值比较使相同资源的title/tag/duration回声清图并重申请 | 只比较真实封面路径/顺序候选URL和原refreshToken；保ready发布时间/resourceRevision及原generation，不新增cache/常驻镜像 | 独审与实际native StatusPanel门通过12.142秒 |
| UI-12 Steam切号 | 已在线时show重新订阅phase，初始online回放关闭刚开的切号面板/误入完成页 | 窗口初始呈现与新认证终态分开，保其他初始phase与原attempt owner、真实成功关闭 | 独审及22项原生门通过12.209秒；另修旧network初值干扰新restore，凭据只查一次 |
| UI-13 帮助失配 | 中英Help仍写旧标签、分散下载页和必删源文件 | 以现真实入口/二次确认默认保源文件/当前页关系修正文案；同步真实筛选/排序/来源搜索，不另改布局 | 双语/二次交审、27/29个静态链接与Debug bundle逐文件SHA核对通过；未冒称Help Viewer渲染 |
| UI-14 属性重复提交 | Web未改文本end-edit仍保存/投影；Scene不同raw slider量化同值仍推进revision | 具体文本/量化消费处退出同值；原target保typed基线与单次UTF8原串比较，保取消/IME/规范等价但字节不同的真改字、文件授权和显式重投，不加project重读 | 独审及五项原生方法分批通过；原串/typed/取消/IME/文件重选反例保留 |
| UI-15 属性窗宽 | Window跟随Steam356/Video368锚宽，content另有required360形成重复尺寸owner；原门只测360 | 移除根content固定宽，保Window原min/max和锚尺寸；原门扩356/368/360 frame/约束反例 | 独审与356/368/360几何/原header/loading/ownership门通过2.258秒 |
| UI-16 热键反馈 | Carbon注册失败静默return，设置仍可能显示启用 | 先用受控Carbon冲突确认；若成立，由原成功登记表携带shortcut提供只读状态、App依赖注入，原生UI反馈。不另建failed镜像/服务/轮询或回滚用户偏好 | 同进程原API探针通过并清理；producer被现设置排除，未证日常失败，本轮不加产品层 |
| UI-17 在线恢复菜单 | local unavailable重新下载时，通用Commands已有取消项，在线菜单又加一次 | 本地内容由原通用菜单拥有取消，纯远端由原在线菜单拥有；两来源/本地缺失+busy真实组合反例，保固定目标/输入域，不按标题去重 | 实际完整菜单组合门通过10.772秒；含UI-22真实Recovery，原有效反例保留 |
| UI-18 下载预览旁路 | visible卡片直接向cache注册未保护loader；A排队后源换B，B像素可写A key并被其他消费者加入 | 退役可见直连producer，统一现loadThumbnail；保可见live fingerprint，不能用旧scan hint暖图冒充当前源。暖图无重解码，变化/冷图共享既有读前后边界，visible先行/共用/取消/同路径覆盖/暖旧hint均补反例 | 身份/Adapter/onlinegrid CLI及真实Inspector43.299秒/Grid45.848秒通过；首消费者/暖旧hint/换源终态已验 |
| UI-19 显式清理负缓存 | OL下载真实AV暂时nil后写failureCache；设置只清image/disk，权限恢复且key未变时清缓存也无法重试 | 原ThumbnailCache一个原子全清动作替换4组总成对旧接口，清image/failure/disk并禁旧inflight回填；single-key失效清其完整结论，真失败在未清时仍免重抽 | 原两API退役；demand/return/leases门及Settings门通过，保负缓存/在飞/namespace与disk-return反例 |
| UI-20 Steam fallback缓存 | 原Steam视频缩略图pipeline另持内存/负缓存，Steam显式清理仅删磁盘及另一preview cache | 独立核原pipeline caller/清理与inflight，不能用UI-19冒称覆盖；先以同key失败→显式清理→成功反例确认，沿原owner处理 | 实际pipeline四模式13.128秒、原service清理顺序/重载门4.572秒通过；未扩大AV兼容结论 |
| UI-21 SIL失败签名 | 图片provider另持长期失败签名，设置只清sharedCache；现真实ImageIO反例修复同size/mtime源后即使全清，原provider重取仍被旧集合拒绝（Inspector成功补图可能恢复） | 原缓存与签名职责需合一；保暖图同步零IO、失败免重复抽图、同源修复后显式清理恢复和旧完成不可回填，不引通知/轮询/第二epoch | 独审及实际SIL门20.431秒、原metadata/layout门13.287秒通过；原断言保留 |
| UI-22 缺失在线项网页重复 | Wallhaven/Pixiv已入库但缺源时，原Recovery菜单已有网页，在线组合又加同目标网页；UI-17桩Recovery为nil漏覆盖 | 组合处明确网页唯一归属，通用资料库保原恢复网页，在线页保一个当前artwork网页；不按标题扫描去重，改用实际Recovery门反例 | 实际完整Recovery组合菜单、通用Recovery及原Steam菜单门通过，默认入口与撤销反例保留 |
| UI-23 设置异步结果换宿主 | 导入/导出await后重查preferredHostWindow，原设置关闭后会把结果sheet挂到用户当前其他App窗口 | 原操作接受时固定宿主，终态仅回原仍可见窗口；已授权文件/导入事务继续，按钮defer复位，不另加Task/全局状态 | 原Settings门9.673秒通过，真实handler原host/成功失败/按钮复位/第二次操作已验；chooser/alert为受控叶 |
| A01 全面查漏 | 上述具体问题不代表全仓审计完成 | 当前覆盖内已证问题/首错点/owner/反例均闭合；未验范围分列 | 本轮结算，无新增可行动问题 |
| A02 交审与停止 | 对修改后的完整调用链复审，保长期有效断言 | 找不到当前证据支持的可行动问题才收束；真实账号/硬件输入/桌面等未验项分列，不能宣称零 bug | 独立静审及对应运行闭合；最终Debug25.905秒+strict/零漂移通过，本轮停止扩展 |

## 验证与失败处理

最近门从原 registry/gate 路由选取，并核对是否实际编译原方法及事件/输出反例。Swift 产品改动做 Debug build；可见变化补隔离 AppKit/真实 Debug 操作，生命周期改动补关窗、迟到和第二次操作。保有效断言，退役源码形状只在其行为覆盖仍存在时同步棘轮。

本批预期最近门：Steam item menu、Commands transactions、remote toolbar/navigation/queries，Video Inspector preview、thumbnail leases、实际 Inspector lifecycle；精确方法随修改记录。构建成功仅证明构建，fixture 不替代真实账号、完整网站服务或桌面画面；未使用用户凭据或改动真实媒体。

失败先区分产品、测试装配和运行环境，修根因后只补受影响门。测试失去前台不增加产品抢焦点逻辑。发现需要改变现有公共职责时先修对应设计；普通重复/无消费者链直接在原 owner 退出，不用包一层来保旧链。

<a id="evidence"></a>
## 结果与产物

截至第三片，UI-01～15的相称最近门已通过；UI-16受控Carbon探针只证同进程重复登记被拒，现设置已排除此producer，未证日常失败，本轮不新增产品状态层。UI-17～20属于随后静态片，尚未编译或运行，不能引用旧候选当作新片证据。原生门取得真实AppKit事件/视图结果，服务叶受控的门只证明对应入口与事件，不代表真实账号、线上网站、硬件或四类型桌面全量验收。

| 结算 | 必要结果与凭据（均在本机产物根下） |
|---|---|
| 第一、二片 | 真实菜单/Commands事务、Settings原异步动作、cache leases、在线busy/Auth服务、真实AV metadata、CPU D/R及图标、音量UI→Manager→Mux→Video/Scene/IPC叶、下载内容/身份/Artwork/CellAdapter/Transfer通过；详见state.json逐门凭据 |
| 原生输入/资源 | Toolbar27.071秒、Video Inspector24.367秒、图片/Pixabay实际视图13.494秒；batch3-native-window与batch3-native-retry均为部分凭据，不把其失败/未运行项算通过 |
| 窗口/属性 | 属性窗356/368/360几何2.258秒、状态栏封面12.142秒；Scene/Web五项原生方法分批通过，最后共享属性项13.228秒。batch3-native-other/property-flags/property-grid区分原门成功与夹具装配失败 |
| 登录/Grid | 旧network failure初值干扰新restore已修，凭据只查一次；原22项登录12.209秒。原HEAD冻结Grid15.931秒、当前诊断17.122秒均过后，将固定30ms等待改为原eventually等同一精确结果及同cell，隐藏取消断言不变；独审后13.256秒，batch3-login-grid-final |
| Debug/strict | batch1-debug-build64.743秒、batch2-debug-build28.992秒、batch3-debug-build211.042秒，各声明输入前后零漂移；第三片包含Help。均为对应片历史构建，UI-17～20不在其证明范围 |
| Help | en/zh-Hans静态27/29条链接无缺失或重复ID，源与第三片Debug bundle逐文件SHA相同；help-static-facts.json，不代表Help Viewer渲染 |

失败与修正均保反例：新夹具补齐实际产品类型/隔离flags、metadata旧65秒预期修为真实格式；Inspector绿色calibrated→deviceRGB不能用channel<0.3判断，改为同空间与真实源逐RGBA比较且仅容8bit量化，保需求/取消/迟到/布局断言。Scene夹具重名仅修装配。Grid完成条件不是性能阈值；登录失败是真实生命周期错误，未增加焦点补偿。属性门保IME原preview次数/payload、typed数值返原、UTF8不同原串、取消恢复及文件重授权反例；没有以同值优化吞掉真实编辑。

本机证据在忽略的 `.artifacts/ui-quality-audit-20261027/`，默认14天/单包32MiB。连续迭代仅保留 `/private/tmp/mwx-main-window-ui-debug-4hopmbb7/DerivedData` 一份增量缓存；当前没有本轮运行中的测试App，未退出/替换正式安装版。compiler/native/AV已明确交给新来源会话，其间只做静态代码/文档，空锁和时间经过不构成归还。新来源会话的Quick Look及在线浏览改动保其唯一职责；重叠的在线busy菜单、下载CellAdapter warm语义已逐项沟通，无提交或合并。

所有修改未提交、未暂存。主仓仍为codex/engine-refactor-program的492a64dc7；主仓独立AGENTS原话改动保留。本计划在审计关闭或用户终止后归档，不替代主界面视觉合同。

UI-18取舍：优先让可见卡、Inspector、预取沿同一个现有producer；当前源key在原后台入口取得一次，保既有异步读前/后源替换约束，不在UI堆额外认证、hash、代次或第二缓存。可移除会绕过当前源语义的scan-hint暖图捷径，暖命中只读现文件事实并取内存，不重新AV抽帧；现有调用方避免重复需求的规则保留。若需保留调用方已取得的live key，必须证实它可省同次重复IO且无新可用性owner，不能增加多层fallback或以调度priority决定身份正确性。退出条件是旧visible直连完全退出、所有真实caller/测试引用同步、实际visible先行与暖旧hint反例通过、其他消费者/原布局与回收不退步。

UI-18交审补到可见首消费者未离开的终态：producer源换代不能借首consumer.cancel表示，这会使真实cache删除其completion，卡片永久停在加载中。源不再匹配时只使该key当前请求不可缓存，并沿原完成通道向仍活跃消费者交付nil；真正离屏/关闭/复用的consumer仍由自己的lease撤销。保错误像素不交付、旧key不记失败缓存、当前卡片结束loading及下一次实际需求可重试；不新增轮询/自动重试平台。下载near按原cache的真实结论（图像或已缓存失败）定义warm，无缓存的换源nil保持可重入，真decode失败不能随每次viewport重复stat/生成；必要时仅由原cache提供只读O(1)查询，不建失败镜像、不再次读文件。若取消非nil重入分支因退出这项错误取消而失去真实producer，一并退役，沿原token==nil语义，不留防已不存在风险的分支。旧“换源必须取消首consumer/无回调”的测试仅保其拒绝错误像素含义，补明确nil终态/用户撤销仍无回调反例，不能通过吞终态来守旧断言。

UI-19改前事实与设计：共享ThumbnailCache产品只有Settings的Video/SIL/OL三组，以及Steam BrowseStateRecovery预览一组，全部成对调用removeAll+clearDiskCache，无独立memory-only/disk-only消费者。让原owner提供一个真实原子clearAll：同一次现有lock内禁止旧inflight回填、清图像和失败内存结论、删并重建自己的namespace；两个旧入口及其4组调用退役，不保兼容wrapper，不跨namespace删目录，也不取消仍应收到结果的消费者。single-key remove同锁清该key图像/负缓存/磁盘与原cacheable标志。既有测试有5组刻意memory-only驱逐，改为仅测试副本观察原decoded owner进行驱逐，保disk-return/暖图/可见图保留断言，不能用全清掩盖返回链。验收含真实失败缓存未清仍去重、显式全清/单key后同key能成功、清理中的旧完成不回填、其他namespace与既有消费者不受影响；原Settings完成反馈仍等待唯一动作实际结束。该片不引TTL、认证、轮询、失败镜像或新清理服务，未测同步磁盘耗时前不宣称后台提速。

UI-20设计取舍：原pipeline保有三次时间点抽帧/可疑帧选择、256MiB磁盘预算、既有文件布局及异步主线程回调。可选方向一是在此原owner增加明确的缓存失效并统一结果发布；方向二迁移到通用ThumbnailCache，可减缓存机制重复，但需同时调整cached-frame decoder、预算/目录及回调时机。当前先按方向一闭合显式清理功能，不并建第二pipeline。复用原lock/inFlight表，必要时把现回调数组收成同一请求的回调与cacheable标志；显式失效先禁旧请求回填并清memory/failure，Steam原清理owner再删除其已拥有的磁盘根，磁盘不重复删除。队列任务保原结果回调，不取消消费者、不新增全局代次或调度器。磁盘解码与JPEG准备/写暂存保持原后台队列，最终cache/rename在原锁下消费一次cacheable状态，清理后旧任务不重建缓存；大编码/淘汰扫描不得搬进主线程或长时间持锁。验收包含真负缓存免重试、失效后同key恢复、在飞成功/失败各完成一次且无memory/failure/disk回填、服务实际清理顺序和新内容正常缓存；不把这一片当作源文件换代或实际AV兼容结论。

UI-22/23实施边界：在线组合明确请求通用Commands的恢复菜单省略原网页，由在线组合保一个原网页；默认通用调用不变，未找到恢复动作或临时不可编辑时也不得丢在线网页。Recovery保重新下载及原固定reference/epoch/page输入域，测试编译实际恢复组合，不能继续用恒nil桩掩盖重复。设置导入/导出在原操作接受处捕获原host，异步成功和失败各只检查该host的可见性并交付；不因用户转到另一窗口把反馈迁过去，也不取消文件/导入事务，保原defer按钮恢复及再次操作。沿UI-06现有完成交付语义，不新建通用反馈服务。

UI-21设计取舍：不把设置连到Adapter/Artwork两个实例，不新增清理通知/observer/epoch；完整把失败源身份搬入通用cache会扩大admission→finish合同，当前先局部修。原SIL sharedCache启用既有有界失败缓存；Provider仅保path→源signature身份，是否仍失败只看原cache真实负结论，不能由旧memo自己返回不可用。清理、单key失效和旧请求不可缓存均沿UI-19原owner；未知producer身份最多按原provider局部语义重新尝试，不把当前源猜成旧失败。只对实际失败path后台检查signature，删除全局任一失败导致所有冷图stat的旧路径；暖图仍同步零IO。现跨队列签名载体有真实消费时保留，不为缩行强拆。Inspector原本不参与Provider失败抑制，须维持其独立实际需求可重试：沿现loadSynchronously已有cachesFailure策略开放最小调用选项，Inspector显式关闭负结论的读写，不新开缓存或改800px解码；普通调用默认策略不变。反例包括真实ImageIO失败/修复保size/mtime→clearAll与single-key→同provider可恢复、在飞失败全清后不能靠旧memo永久封锁、多provider未知身份、既存精确mtime替换/失败免重复/取消/暖图零IO，以及Inspector先失败再恢复不回退。此片不声称跨provider失败绝对只解一次，不新增内存镜像作为第二失败owner。

UI-21成功结果覆盖原负结论：原finish仅在allowsCaching的成功发布分支清同key旧failure；否则Inspector绕过旧负结论成功后，一旦decoded memory驱逐，旧failure会重新阻断磁盘成功图。此处不加第二检查或状态，旧不可缓存job仍不能改新缓存；真实门保未清失败去重，并增加false策略成功→只驱逐内存→普通请求恢复磁盘成功图。

最后静态交审：UI-20/22/23均无阻断；UI-22恢复与在线组合测试已改为实际完整Recovery，保原47项有效菜单反例并补网页唯一归属，外部打开仅记录叶。UI-23实际三个处理器控制chooser/异步/alert叶，原清理反例全保留；真实系统选择器与弹窗呈现不由该受控门证明。UI-21静态实现与独审也已完成。静态代码/断言信号/设计门通过不等于这些新片运行通过。已删除本轮停用的18份原HEAD冻结source副本（无打开句柄），保其base/输入SHA/结果与清理凭据可从Git复建；唯一增量缓存继续复用。

第四片已运行：真实菜单10.772秒；通用Recovery10.408秒、Settings9.673秒、Steam菜单1.414秒；Cache前8门全过，Video旧夹具漏产品既有isSwitching字段，仅补该默认false字段并独审后8.592秒通过。真实Inspector43.299秒与Grid45.848秒通过。SIL门因旧assembler漏492a新增在线来源依赖在编译时停止，正在补其记录叶/实际model依赖，不改SIL/Adapter算法或断言；SteamPreview/MainMenu及最终Debug尚未运行。初次outer/inner构建锁自等待由本轮执行脚本改成单层持锁，首菜单pass仍保留，原门本身未改；只终止本轮两个进程并清其13份停用临时source，保SHA/日志。凭据batch4-actions/actions-retry/cache/video-retry/native区分部分与全过，不能合称整份Native通过。设备已明确短借启动专项，Root静态修装配，等待归还后补余下门。

最终结算（2026-10-27）：SIL装配只补实际在线model/projection、现有app stub与共用记录叶/实际applyTransfer，独审通过；原SILDemand20.431秒、SILMetadataLoading13.287秒、SteamPreview23.802秒、MainMenu20.195秒全过。最终Debug25.905秒、strict签名0、声明产品/工程/helper/Help输入前后零漂移，凭据batch4-debug-final；此后仅文档变化。UI-10/16是有依据的停止，不是欠实现；其他卡已证操作错误与冗余链已处理，最近独立复审无新增可行动问题，不声称全仓零缺陷。未做最新整App逐页手测、真实在线账号/网站、真实媒体删除、四引擎桌面播放、Release、多屏/真人硬件与完整能耗验收；源码/原生控件事件及受控叶各按原门边界理解。

先前40.041秒候选虽build/strict成功，日志复核仍有本轮memoryCost默认actor推断警告；已仅把纯位图字节计费helper标为nonisolated，锁/队列/函数体与UI回调不变，独审通过。原AV四模式再跑13.256秒通过，最新25.905秒Debug/strict/零漂移及零warning复核通过；不以编译注解冒称运行提速。

事实面：代码/组件运行为changed-and-verified；文档与规则按当前登记/链接/预算门核对，用户两段原话已在本树AGENTS，主仓另一会话的同样原话改动保留；记忆generated-read-only，未写入；部署/发布out-of-scope；工作区为未提交的审核现场。资源窗口已交还，未开关他人App。只保一份连续迭代DerivedData及最新候选供审核，工作树含唯一未提交改动，继续保留；本机证据包按14天/32MiB保留必要成功/失败日志和source指纹，不再留停用冻结source副本。后续只从当前AppKit/主界面合同维护，不从此记录自动重开工作卡。
<!-- preserved-body:end -->
