# 代码精简专项

<!-- document-role: active-plan -->

复核日期：2026-10-22。负责人：repository-maintainer。调查基线：`557ac8a1b398`。

## 目标与边界

减少没有产品消费者的实现、状态和维护分支，收敛重复计算，保持现有用户操作、作者内容、持久化、IPC、失败半径与输出不变。当前用户授权每批在独立审查与对应回归无误后直接本地提交、整合回原分支并开始下一批；保留并行改动，不推送。本文拥有本专项候选、分批顺序和验收记录；引擎职责仍归[技术栈合同](../architecture/technology-stack-boundaries.md)，当前运行能力仍归各专题，不另建能力台账。

“无调用”须排查 selector、协议回调、独立进程、作者脚本、动态资源及调试工具；测试、文档或结构登记出现名字不等于产品调用。第一批只删除已确认不可达的链路，不以行数作为收益或验收目标。

## 第一批设计与停止条件

第一批最小结果：下列旧链整体退役，实际 AppKit、播放、查询、属性与系统指标消费者保持原实现；既有行为门和 Debug 构建通过，合同及登记同步。按用户授权，交叉审查无误后本地提交，不推送。发现真实消费者、行为依赖或失败反例时，停止删除该单元并记录原因，不添加兼容 wrapper 维持旧入口。

| 编号 | 删除范围 | 保留的真实职责 | 验收 |
|---|---|---|---|
| B1-A | 卡片交互标记、延迟复位和无人读取接口；Inspector SwiftUI 桥；旧 SwiftUI 详情组件 | AppKit 选择、详情、拖选、播放及共享 presentation 模型 | UI 投影、图库交互、详情与 AppKit 门 |
| B1-B | 无入口 SMC 温度采集、格式化、常量及 ABI 结构 | 状态栏 CPU/GPU/内存/网络采集与显示 | 状态栏投影门、Debug 构建 |
| B1-C | 未接入的 Web runtime model 组装、类型、专属缓存、签名及失效分支 | descriptor → playback context → 当前 Web host；属性、授权、诊断和磁盘缓存 | Web 属性、缓存、launch profile、资源授权及现役 WK 行为门 |
| B1-D | 旧 Steam detail scheduler、未消费的 suspicious-cache 状态、旧认证枚举和错误类型；C# 零消费者协议便利 API | 当前查询限流、预览失败退避、登录/下载及 wire 协议 | scheduler 剩余行为、Steam 查询/协议/预览门及 helper 构建 |
| B1-E | 无消费者 SceneTextureMappedUVScale 及其文件登记 | SceneTextureCandidate 的实际映射、纹理安全与渲染 | texture candidate、结构/防御面门、Debug 构建 |

数据流不新增 owner：用户动作仍进入当前 AppKit 和服务；Web 直接消费已准备 descriptor/context；Steam 继续使用当前 Swift 请求与 C# 查询限流；Scene 继续使用 typed candidate。既有数据和缓存格式、协议字段、授权、shader、逐帧执行和最终输出均不在第一批修改范围。

验证前冻结本批文件并记录内容身份；构建与运行串行进行。移除旧测试载体时，先确认其只覆盖退役实现，保留同文件中服务真实 owner 的断言。源码删除不会自动证明视觉、性能、真实 Steam 或完整兼容验收。

## 后续候选

以下是调查线索，不表示已证运行缺陷。已纳入某批的范围以本文对应章节为准；其余每批重查实际消费者和最近反例后再选范围。

| 类别 | 候选 | 后继验收/判定 |
|---|---|---|
| 旧接口 | 旧 SQLite 加载/迁移支链、信息弹窗文本、在线下载描述模型及其他无调用薄接口 | 保留实际加载、退出合并、删除及 Inspector 行为 |
| 测试独占链 | SceneEffectTextureBinding、LatestValueHandoff、旧材质 assemble/derive、粒子 runtime 级快照 | 先将有价值断言迁到当前 prepared/transaction owner；Simulator 快照仍有真实消费者 |
| 测试独占恢复 | helper 超长帧 resync | 统一当前有界关闭合同，保留超长拒绝；不扩大协议错误恢复 |
| 重复计算 | shader 多次 lex/parse；在线列表全量元数据重读与比较器属性查询；视频搜索/导航重复排序 | 同语义上下文复用，文件 revision 和稳定排序反例；收益须实测 |
| 小型算法 | Web 重复小写/正则和 BFS 队列、下载计数排序、失败历史重复扫描、协议 buffer 复制 | 相同输入/输出/失败边界；不引入多余缓存或 owner |
| 冗余构造 | 音频服务二次初始化、Steam 下载缩略图串行队列的外层 semaphore、状态栏无消费者采样 | 初始化、取消、差分采样及真实 demand 回归；Video 队列并发，现役限流保留 |
| 构建 | Steam restore/publish/签名和 stock assets 全量扫描 | 完整输入身份、资源增删、配置与签名失效；不能只关闭 alwaysOutOfDate |
| 内容判定 | 暗色视频被当作缩略图失败 | 暗色仅评分，保留真实解码 fallback；暗场/损坏/负缓存反例 |
| 数据策略 | 暂不可用文件自动删除索引 | 区分外接卷未挂载与确认删除，先设计数据保留与恢复 |
| 兼容合同 | Web 声明入口与回退矛盾、本地跨文档导航、粒子省略默认值 | 先取得语义与区分证据；不得直接移除 guard 或猜默认值 |

已排除直接删除：WebM parser、旧 Steam 数据迁移器、实际 Simulator 事务快照、必要身份/generation/GPU range/路径授权与生命周期检查；独立工具和作者 API 不因没有按钮而退役。Boids 有界规模、.NET trimming 和第三方资源目前没有足够的安全精简依据。

## 第一批实施与证据

状态：B1-A～E 完成交叉审查，已本地提交 `4749df8f7`，未推送。20 个 Swift/C# 产品文件合计增加 6 行、删除 1152 行，净减少 1146 行。删去 3 个文件，其余沿原 owner 收敛；未修改生产校验、授权、协议字段、资源范围或生命周期防护。此计数只描述源码体积，不表示性能、包体或能耗收益。

同步现役 AppKit 迁移状态、4 份 Web 合同/状态文档、文档入口及职责索引；移除退役 Scene 文件登记和旧 scheduler 测试载体，保留 Online 调度断言。最近测试关联补入现役消费者；关联只说明测试选择，不等于完整覆盖。第一批窄设计登记已按退役条件移除，本文继续拥有后续候选。

| 验证 | 结果与范围 |
|---|---|
| App Debug | `bash script/run_checkpoint_build.sh` 冷构建成功，含 Steam helper 嵌入；20 个产品文件与验证前冻结内容一致。默认隔离 DerivedData/App 已由脚本清理 |
| AppKit/图库/系统投影 | `test_ui_projection_efficiency`、`test_ui_library_algorithms`、`test_library_toolbar_behaviors`、`test_video_inspector_preview_reload`、`test_status_bar_icon_projection`、`test_steam_detail_layout`、`test_steam_appkit_interaction`、`test_steam_property_window`、`test_grid_card_lifecycle` 通过 |
| Steam | `test_ui_request_schedulers`、`test_steam_preview_lifecycle`、`test_steam_protocol_golden`、`test_steam_helper_offline`、`test_steam_queries` 通过；helper 包含 Debug/Release 离线行为，不涉及真实账号 |
| Web/属性 | `test_web_runtime_cache`、`test_web_launch_profile`、`test_web_resource_grants`、`test_web_display_conditions`、`test_web_playback_pause`、`test_web_compat_parity`、`test_scene_user_shortcut_properties` 通过；其中播放/暂停及兼容门运行真实 WKWebView |
| Scene/发布边界 | `test_scene_texture_candidate`、`test_release_diagnostic_isolation` 通过；未扩展 Scene 算法或提交权限 |
| 选择与治理 | 测试编排/路由 104 项、文档链接 6 项通过；代码行数、防御面、依赖、断言信号、设计、文档登记/健康、产物/残留及 diff 空白检查通过 |

23 个去重后的行为模块用 `python3.12 -B script/run_scene_tests.py -j 1 --module <模块>` 串行执行，构建不与运行并发。首次回归暴露两处既有夹具陈旧：Toolbar probe 缺少生产已有的 thumbnail demand 回调，现补齐并增加“只在快照完成后投递”断言；Scene 未知属性用例仍把已支持的 `usershortcut` 当未知类型，现只替换未知类型载体，原断言保留。修复前相关产品/夹具输入与 HEAD 相同。卡片回归曾因应用失焦失败；用户确认测试时可能抢焦点，所有为此试加的夹具逻辑已撤销，最终原始夹具与 HEAD 逐字节一致并复跑通过。

全局 Scene 结构门仍有既有失败：目录合同缺 6 个现役文件登记，`shape-derived-analyzer-fleet` 比基线多 1 个文件/1 次命中，导致 authority/completion 各 2 条错误。用导出的原始 HEAD 与候选分别检查，错误集合完全相同；本批没有新增结构错误，也没有放宽这些基线。此门不得记为通过，后续由原结构/能力 owner 核对登记与扫描含义。

覆盖限制：状态栏门证明图标投影，系统采样器的保留方法另经差分复核与 App 编译，未作 CPU/GPU/内存/网络硬件采样实测；未执行全 App 人工操作、多屏、真实 Steam 登录下载、全量 Scene 内容/完整 Web 兼容及性能对比。现有回归未发现本批功能退步，不将有限验证表述为绝对兼容保证。

2026-10-22 再次由 3 个独立子代理分别交叉审查 App/图库、Web/Steam、Scene/全部变更测试。均未发现误删现役消费者、功能回退或断言削弱；另逐项核对旧 Steam actor 的专属断言仅覆盖退役 owner，3 组 Online 断言逐字保留，未知属性与 Toolbar 原断言完整保留，Grid 夹具逐字等于 HEAD。本次产品、测试、构建/选测输入身份与上一轮完全一致，复用既有 Debug/23 模块结果；只重验文档收尾所影响的门。静态独审仍不替代上述未覆盖运行范围。

本机必要证据保留在忽略目录 `.artifacts/code-slimming-b1-20261022/`，包含源码身份、命令/结果、初次失败与最终复跑、构建摘要及 HEAD/候选结构对照；交叉审查身份和收尾记录在 `.artifacts/code-slimming-b1-crossreview-20261022/`，均保留 14 天至 2026-11-05。原始构建日志提取摘要后删除，本轮临时导出、HOME、缓存和构建目录清理；其他会话的缓存与证据不动。一般维护证据没有 Scene 样本身份，不伪造样本套用 runtime-sample 提取器。Git 提交按本次用户授权执行，不推送。

## 第二批范围与停止条件

基线：`4749df8f7`。状态：实现、对应回归与再次交叉审查完成，已本地提交 `7ff397f5a`，按授权整合原分支，不推送。比较继续删除旧接口、精简只读下载投影和优化 Web 依赖扫描后，本批选择后两者：输入输出和现役消费者明确，无须更改用户数据、准入或失败策略；索引恢复、导航校验和缓存判定另行论证。

| 编号 | 局部修改 | 保持的语义与最近验证 |
|---|---|---|
| B2-A | Web 开发校验报告和运行缓存签名的有界 BFS 用两个本地数组逐层交换，不反复移除首元素 | 保持入队/访问顺序、重复与环处理、路径解析、缺失/读错、120/200 文件与时间上限、截断和诊断输出；用真实生产方法检查图遍历、预算及冷/热缓存 |
| B2-B | Steam 未完成计数直接筛选计数；只读计数/失败查询使用惰性序列，避免无用排序与数组 | 保持账号、状态、空账号、首个同时间失败、排序展示和记录身份；用任务投影、JobStore、下载页计数及相邻历史/队列门验证 |

只在现有方法内调整迭代方式，不新增缓存、队列 owner、持久格式、授权或回退。常规局部算法简化由本文记录范围，不新增能力设计登记。源码行数不作为此批收益；只陈述移除的操作和复杂度，不预支 App 性能/能耗结果。若输出、顺序、界限或账号隔离出现差异，先修复或撤回该单元；不修改旧预期来适配新算法。构建/运行与另一文字渲染会话协调串行；收尾转入独立 worktree，原 checkout 的共享 JSON、Scene 文件与 index 均由另一会话独占。

预审收窄：静态 summary 没有总文件数上限，单纯游标会使已处理、重复入队的 URL 保留至扫描结束；120/200 也只约束唯一文件数，不约束重复入队元素数。因此 summary 原实现不改，两个有界扫描使用本地当前层/下一层数组，层结束即替换旧层，避免累计全部已消费前缀。层内顺序及每元素的去重、预算、时钟检查位置不变；用长链、高重复度与边界图检查。若局部替换不能保持原合同，撤回 Web 片，不引入阈值、通用队列或额外 owner。

执行与证据：新增任务查询与 Web 遍历回归先在原始 `4749df8f7` 产品上通过，再 overlay 冻结的 5 个产品文件运行 10 个最近模块，全部通过。模块为 `test_steam_download_tasks_popover`、`test_steam_download_history`、`test_steam_library_transaction`、`test_steam_library_interactions`、`test_library_toolbar_behaviors`、`test_web_dependency_traversal`、`test_web_runtime_cache`、`test_web_static_content_signals`、`test_web_launch_profile`、`test_web_resource_grants`。新增用例没有为新算法另改预期，原缓存、历史、排序和失败反例保留。

`bash script/run_checkpoint_build.sh` 默认隔离冷 Debug 构建通过，构建与测试串行。构建来自固定 `4749df8f7` 导出加本批精确 overlay，不包含另一会话在途的文字实现；冻结的 7 个候选产品/测试输入在独审、候选运行与构建前后一致，基线使用原 B1 产品及同两份增强测试。再次由 3 个子代理独立复核控制流、扫描边界、预算/时钟、空间保留、账号、状态与断言，未发现产品或测试阻塞；修正文中候选与基线身份的混淆。代码健康、设计、断言信号、产物与残留检查通过；最近测试关联已补齐，选测未映射/失效项为零，路由/链接 110 项及文档登记/健康检查通过。关联只说明最近测试选择，不代表完整功能覆盖。

源码没有新增 runtime 状态或逐帧工作。只确认移除了计数排序/中间数组和队列头部搬移；没有进行 App 性能、能耗或包体对比，不将算法简化表述为实测收益，也不认领完整 UI、真实 Steam 或全量内容兼容。Web 新门的时钟只在测试叶注入，产品时钟与预算不改。

第二批在独立 `code-slimming-b2` worktree、分支 `MWX/code-slimming-b2` 收敛，7 个产品/测试文件在转移前后逐字一致；原 checkout 的本批副本精确恢复，第一批提交及并行 Scene 工作保留。第一批本机证据留原 checkout，第二批必要证据在本 worktree 的 `.artifacts/code-slimming-b2-20261022/`，期限至 2026-11-05。本轮固定导出、临时 HOME/缓存和原始构建日志提取后清理，checkpoint DerivedData/App 已自动清理；其他会话缓存与材料不动。整合保留并行 Scene 提交 `d6d500009` 的全部产品、测试、文档及共享登记；固定组合候选的 11 个模块（上述 10 个及 `test_scene_text_native_bounds`）和隔离冷 Debug 构建再次通过，路由/链接 110 项、断言、文档健康与登记门通过。组合验证只补强相应范围；未扩大 UI、真实 Steam 或全量内容声明。合并身份以 Git 记录为准，不推送。

## 第三批范围与停止条件

基线：整合提交 `2915823cf`。状态：实施、对应回归及再次三路交叉审查完成，按用户授权本地提交并整合原分支，不推送。比较旧接口退役、音频/缩略图调度和 Web 文本重复扫描后，本批选择已能完整证明消费者的旧接口；另两类涉及并发或内容判定，继续保留候选。最小结果为删除以下无人调用支链，并通过现役持久化、Inspector、工具栏与库算法回归和 Debug 构建；出现实际消费者或反例即撤回相应删除。

| 编号 | 退役范围 | 保留职责与验证 |
|---|---|---|
| B3-A | Manager 旧 SQLite 读取/迁移 wrapper、只为其服务的已持久化判断/行数查询、无消费者的旧异步读取 | `loadInitialIndex`/异步启动、完整 SQL 读取、失败恢复、UserDefaults 迁移、退出合并及保存；现役 ordered-save 门断言逐字保留，仅去掉无调用声明的提取 |
| B3-B | `UIActionHelper.presentInfo → wallpaperDetailInfoText → infoText` 旧信息弹窗链及仅为它准备的文件名字段 | 菜单/卡片仍进入现役 Inspector，可取消 metadata Task、全部仍显示字段及预览生命周期；工具栏、Inspector 和库算法门 |

静态追踪包含全仓调用、selector、菜单、卡片、资源和测试。Online 下载 Inspector 的 Snapshot/Views 有完整用户入口，整条保留；同步 SQLite 读取仍用于真实 SQL 回归，不因测试专用就移除。初始化、授权、路径/文件扫描边界、缺失文件清理策略和数据格式均不在本批修改范围。只在现有 owner 删除退役声明，不加 wrapper 或新的测试算法；文档继续由本文拥有专项状态。

实施结果：4 个产品文件净减少 92 行。保留的方法与基线逐字核对，仅调整两处已陈旧的 Store 注释；metadata loader 只去掉无人读取的文件名构造参数，其余字段、取消检查和 MainActor completion 保持原样。两个实施子代理分工修改后，另一个独立子代理交叉检查完整 diff、真实入口与全部测试断言，未发现产品或测试阻塞。

验证：固定 `2915823cf` 导出的 `test_video_index_ordered_save` 先通过；固定候选的 `test_video_index_ordered_save`、`test_video_inspector_preview_reload`、`test_library_toolbar_behaviors`、`test_ui_library_algorithms`、`test_playback_policy`、`test_playback_policy_delivery` 六模块串行通过，随后隔离冷 Debug 构建通过。6 个产品/行为测试输入在运行和构建前后哈希一致。持久化真实 SQL、失败/中断、回退、迁移、退出与重启断言完整保留；Inspector 门仍证明预览/迟到回调，metadata 实现的保留另经静态差分与 App 编译，未声称完整人工 UI 或真实用户库迁移实测。

最近测试关联补齐 IndexStore/恢复 owner 和共享详情载体。原路由测试把 Persistence 精确限定为两项 policy 门；加入实际 ordered-save 门后，同步精确集合为三项，并新增 IndexStore、InitialIndex 与 fixture 只选择 ordered-save 的反例，未改为宽松包含判断。111 项路由/链接门通过，4 个产品路径均有最近关联，无失效/未映射项；关联仍不代表完整覆盖。代码健康、断言信号、设计、依赖、Debug 布局及文档门通过。

全局 Scene 结构门 15 项中仍有 3 个既有失败（目录登记、authority 和 completion）；固定基线与候选的这三项断言消息逐字相同，12 个其他结构项通过。未修改相关白名单、ratchet、扫描范围或 Scene 产品；不得把此门报为全绿。本批不认领性能、包体、能耗、全 App 交互或全量内容兼容。

再次由三个独立子代理分别复核持久化、Inspector 和完整测试/登记，未发现真实调用误删、功能回退或断言削弱。10 个文件及既有证据 manifest 身份一致，六个行为输入与已通过的构建/回归相同，按工作流复用这些结果；本轮重跑 111 项路由/链接与断言门，补跑并归档此前未入包的设计门输出。原分支未出现产品整合漂移，不额外占用并行 Scene 诊断窗口；纯文档状态修订只重验文档门。

证据保留在复用 worktree 的 `.artifacts/code-slimming-b3-20261022/` 及本轮 `.artifacts/code-slimming-b3-crossreview-20261022/` 至 2026-11-05；包含输入身份、基线/候选与构建摘要、独审、路由及既有结构失败对照。默认 checkpoint DerivedData/App 自动清理，固定导出和临时 HOME/缓存当轮清理，第一/二批证据与其他会话材料保留。本批从 `2915823cf` 在隔离分支收敛，提交/整合身份以 Git 记录为准，不推送。

## 第四批范围与停止条件

基线：第三批提交并快进整合后的 `a3e55663c`。状态：实施、对应回归/构建及再次三路交叉审查完成，按用户授权本地提交并整合原分支，不推送。比较继续退役旧接口、音频二次构造和 Web 重复文本扫描后，选择消费者可完整追踪的接口/载体简化；音频和内容扫描继续保留，避免混入生命周期或准入语义变更。

| 编号 | 修改 | 保留职责与验证 |
|---|---|---|
| B4-A | 删除无消费者的 `SILService.detailInfoText` 和 `wallpapers(forSILTag:)` | 现役 Inspector、`sortedWallpapers(forSILTag:)`、选择与元数据读取；SIL 元数据、投影及工具栏门 |
| B4-B | 删除无调用的 `loadDownloadedFiles`；现役删除直接消费原 URL，去掉仅作参数包装的 `OLLocalFile` 和虚构大小/时间构造 | `deleteLocalFile` 删除与 downloadedIDs 更新、网格批量完成/重载、真实 `loadEntries` 扫描及 Online Inspector；增强工具栏的选中 URL 精确集合，先跑原实现基线再跑候选 |

`OLLocalFile` 的删除调用是真实消费者，不能直接连同删除 owner 退役；本批只把既有 `file.url` 传递改为同一 URL 参数，错误处理、文件名 ID 解析和发布时间保持原行为。真实下载列表的文件筛选、顺序、扫描边界和 metadata 准入逐字保留，不借删除旧扫描方法改变当前策略。保留所有既有断言，URL 目标反例只增加约束；若发现其他载体消费者、输出变化或真实扫描差异，撤回该片。先静态实施，待并行 Scene 诊断结束后串行运行近邻回归和 Debug 构建。

实施结果：4 个产品文件净减少 78 行。两个实施子代理精确分工，另一个独立子代理复核完整 8 路径、全仓消费者、断言与登记，未发现阻塞。真实 Grid 除两行参数传递外与基线逐字一致；`deleteLocalFile` 归一化参数后函数体逐字相同，完整扫描、排序、Inspector、metadata 和批量重载保留。工具栏夹具移除镜像包装类型，原有全部检查保留，增加不同条目 URL 与精确选中集合约束，不依赖 Set 遍历顺序。

验证：原 `a3e55663c` 产品加增强夹具先通过 `test_library_toolbar_behaviors`；固定候选的同一模块、`test_ui_projection_efficiency`、`test_sil_metadata_loading`、`test_online_grid_thumbnail_demand` 四模块串行通过，随后隔离冷 Debug 构建通过。5 个产品/行为夹具输入在静态复审、候选运行与构建前后身份一致；旧接口基线保留原 API，仅增加 URL 约束。与并行会话协调后才启动验证，结束立即释放窗口。

111 项路由/链接门、代码健康、断言信号、设计、依赖与文档门通过。只给既有工具栏组补入真实关联的三个路径，4 个产品路径均有最近门，无失效/未映射模块；未改扫描实现、Scene 结构规则或棘轮。第三批已记录的 3 个全局 Scene 结构失败仍为未解决债，本批不认领修复或全局全绿。

覆盖限制：工具栏门证明 Grid 向 service spy 投递精确 URL 与批量 UI 完成，其余近邻门证明 SIL 元数据/列表投影和 Online demand 生命周期；真实文件删除失败和 downloadedIDs 时序由未变的规范化函数体与 App 编译支撑，未作真实用户文件删除实测。未运行完整人工 UI、全量内容、性能/能耗或包体比较，不预支收益。

再次由三个独立子代理复核 Online、SIL/断言和完整登记/证据，未发现误删真实调用、功能退步或断言削弱。8 路径及证据 manifest 与上一轮一致，复用相同产品/夹具的基线、4 模块候选及冷 Debug 结果，本轮重跑 111 项路由/链接与断言门。路由预览不当作已执行门，Scene 依赖门也不冒充 Online/SIL 完整依赖审计；消费者和参数传递另经源码复核。

证据在复用 worktree 的 `.artifacts/code-slimming-b4-20261022/` 及本轮 `.artifacts/code-slimming-b4-crossreview-20261022/` 保留至 2026-11-05。固定基线/候选导出、临时 HOME/缓存当轮清理，成功构建原始日志提取摘要后删除，checkpoint DerivedData/App 自动清理；前三批证据和其他会话材料保留。整合按 key 保留并行 `6fd3faf56` 的两份 Scene 文档及两个文档预算收紧；该提交不改变产品/夹具/构建输入，文档组合另验，不额外重建产品。提交/合并身份以 Git 记录为准，不推送。

## 第五批范围与停止条件

基线：第四批 `59590f7a1` 与并行 `6fd3faf56` 已通过 `02188e5db` 整合。状态：实施、对应回归、构建及再次三路交叉审查完成，按用户授权窄提交并整合原分支；提交与合并身份以 Git 记录为准，未推送。比较 Web/Online 文件元数据重复读取、音频重复构造和缩略图无效同步后，选择后两项；前者的文件变更与排序快照语义需另论证，不与本批混改。

| 编号 | 简化 | 保留职责与验收 |
|---|---|---|
| B5-A | `WallpaperEngine` 不先创建无回调音频占位实例；用同一个局部 `PlaybackSpectrumDelivery` 立即创建唯一正式实例，工厂显式接收 delivery | 保持 eager 初始化、三个回调、需求驱动采集、scope/generation、pause 与恢复；真实 initializer/工厂装配回归、现役音频/IPC/切换门与 Debug 构建 |
| B5-B | 删除 Steam 下载缩略图私有串行队列内 `generationLimiter(value: 2)` 及 wait/signal | 同队列执行串行性、合并/缓存/失败、主线程 completion 和实际异步取帧等待均保留；现役缩略图门与 Debug 构建 |

Audio 仍只有原服务与 delivery owner，不改成 lazy/optional，不把设备采集提前到初始化；正式服务在原占位构造阶段创建，采集仍由 `setConsumers` 驱动。Steam 只移除同一串行闭包内无法竞争的外层信号量；`generateCGImage` 的零值等待用于异步回调，Video 缩略图队列本身并发，两者均不得顺带删除。没有权限、路径、数值或身份防护退役。新增装配检查直接使用生产 initializer 与工厂，不复制回调算法，原有断言保留；若出现提前采集、回调错误、重复 owner 或并发变化，撤回该片而不追加兜底。

实施：三个产品文件只收敛构造与同步。音频工厂三个回调体、需求/暂停/scope/generation 与采集服务内部不变；Steam 除三行外逐字保留。收益只陈述少建一次占位服务、少一次无效 permit 配对，不认领代码体积、性能、包体或能耗实测。两个实施子代理分工后，由另一个独立子代理审查完整改动、真实初始化/调用及新旧断言，未发现阻塞。

新增 `test_system_audio_spectrum_owner` 使用真实字段、完整 initializer、工厂、frame/token 和记录叶：原基线实际观察到两次构造，4 项构造/身份不变量失败，候选为一次构造，三个回调、六数组/两种 token 和 delivery 身份均通过。原服务初始化只建缓冲、分析器与 dispatch source，不启动 tap；这一点由真实初始化源码与现役恢复门核对，记录叶本身不证明硬件采集。

新增 `test_steam_download_thumbnail_pipeline` 使用真实完整 pipeline、helper/cache、ffmpeg 自有小视频及隔离 HOME；仅在抽帧入口加观测和首请求闸门，不替代生成/缓存算法。原基线和候选均通过 12 项冷帧、同 key 合并、不同 key 完成、内存/负缓存、坏/缺失文件、JPEG 落盘和主线程 completion 检查，生成最大并发为 1。复用现役 isolation flags，并启用 warnings-as-errors；原有近邻门只编译该 pipeline，不能反称已覆盖冷抽帧。

验证按冻结身份累计闭合 8 个模块：两个新门、`test_playback_switch_endpoints`、`test_system_audio_spectrum`、`test_system_audio_spectrum_recovery`、`test_scene_audio_capture_scope`、`test_playback_process_isolation`、`test_thumbnail_return_reuse`。首次候选 7 项通过，endpoints 因媒体订阅替身缺少生产已有 `needsWebArtwork` 参数编译失败；在原始 `02188e5db` 产品及原测试上复现相同两项失败后，只补替身参数，保留原全部断言，单独复跑 endpoints 通过。其余 5 个代码输入身份未变，复用已通过结果；最终 6 个代码输入均与隔离冷 Debug 构建前后相同，构建通过。不表述为一次 8/8 全绿。

选测只追加两个现役职责组；3 个产品路径均映射，无失效/未映射项。111 项路由/链接、代码健康、断言信号、设计、依赖及文档门通过。专项全文增长触发首读 150 行上限后，首读仅定位现有第五批章节，完整记录仍由同一文档及正文预算管理；150/600 上限、扫描脚本和旧路由均不放宽。既有 3 个全局 Scene 结构失败未在本批修复，本批未重跑完整结构组，不报全局全绿。

覆盖限制：装配门的服务/外部观察是记录叶；真实 service 恢复、scope/IPC 门与冷视频门分别承担对应行为，不将其合成真实硬件采集、全 App UI 或全媒体兼容验收。未作真实音乐、多屏或长期并发性能测量。必要证据在复用 worktree 的 `.artifacts/code-slimming-b5-20261022/` 至 2026-11-05；保留初次失败、基线同错和修复复跑，成功原始构建日志提取摘要后删除。临时导出、视频、HOME/缓存当轮清理，checkpoint DerivedData/App 自动清理；其他会话材料不动。再次三路静态复核未发现真实调用丢失、行为回退或断言削弱；6 个代码输入与既有回归/冷 Debug 身份一致，复用该结果。整合保留并行 `52adbf5a7` 的三份 Scene 正文、三个收紧预算及 runtime 导航收据，组合文档与 111 项路由/链接另验。

## 第六批范围与停止条件

基线：第五批 `da39b6d94` 与并行文档 `52adbf5a7` 已通过 `bb71bd5` 整合。状态：实施、互审、回归与构建完成，按用户授权窄提交并整合原分支；提交及合并身份以 Git 记录为准，未推送。比较缩略图无消费者入口、下载失败历史重复扫描和视频搜索排序后，选择第一项；后两者涉及账号/历史快照与排序语义，本批不混改。

最小结果：退役 `ThumbnailCache` 的 legacy prefetch、image-data prefetch、raw-data prefetch 和同步 cached-or-disk 便利入口，以及 Steam 下载缩略图的仅测试读取入口。删除前排查产品、独立进程、协议/selector、工具与夹具；任何真实产品消费者或行为依赖出现即保留该入口。缓存 owner、namespace、持久格式、调度、需求优先级、取消、限流、失效与主线程完成均不改。

测试独占的 raw prefetch 调用迁到现役 `loadRawDataAsync(priority: .prefetch)`；该夹具创建空 namespace，不依赖旧入口的内存已命中短路，原四条旧写不得覆盖新数据断言保留。Steam 冷视频门的同步读取断言改为从真实 request 回调验证同一缓存对象与负缓存不重复生成；保留原 12 项输入/输出与完成语义，不为删除接口删去缓存行为验收。两份迁移夹具先在未改产品上验证，再运行固定候选；独审、缩略图相关门和隔离 Debug 构建均通过。本批不改 Scene 产品与并行会话材料，不认领性能或能耗实测。

实施：两个产品文件共删除 51 行、6 个零产品消费者便利入口，现役 load、调度、取消、持久化、失效、限流和完成主体逐字不变。全 tracked 调用排查并核对无 NSObject/@objc 或协议动态入口；Online 的同名 prefetch 属另一个真实 owner，保留。两个实施子代理随后互查对方改动，另一代理复核完整四条代码/测试路径，未发现误删调用、回退或有效断言削弱。

验证：固定 `bb71bd5` 加相同两份迁移夹具的 `test_thumbnail_cache_leases`、`test_steam_download_thumbnail_pipeline` 先通过；固定候选串行一次通过这两项及 `test_thumbnail_demand_scheduling`、`test_thumbnail_return_reuse`、`test_video_thumbnail_prefetch`、`test_video_inspector_preview_reload` 共六模块。基线/候选 45 项 shared-cache 与 12 项冷视频检查均全真，候选另有 75 项需求调度检查全真；冷视频均为最大生成并发 1、总生成 3、结束 active 0。随后隔离冷 Debug 构建通过，4 个产品/测试内容身份在回归与构建前后一致。

已有测试映射覆盖两个产品路径，无未映射或失效模块；没有修改映射、扫描或棘轮。111 项路由/链接、代码健康、断言信号、设计、依赖及文档/产物/残留门通过；依赖门仍只证明其明示的 Scene/测试扫描范围，不冒充全库完整依赖审计。保留并行 `52adbf5a7` 的三份正文、三个 bodies 和 runtime 导航收据及所有其他预算；仅更新本专项正文预算与首读章节。既有三个全局 Scene 结构失败本批未修复，未重跑完整结构组，不报全局全绿。未做完整人工 UI、真实账号或全媒体兼容及性能测量。

必要证据在 `.artifacts/code-slimming-b6-20261022/` 保留至 2026-11-05；固定导出、合成媒体、临时 HOME/缓存当轮清理，成功原始构建日志提取摘要后删除，checkpoint DerivedData/App 自动清理。复用 worktree 为后续批次及前批证据保留，其他会话材料不动。本轮提交前四个产品/测试身份及证据 manifest 与上轮一致，复用相同输入的六模块与冷 Debug；仅重验状态文字涉及的文档/路由和暂存面。

## 第七批范围与停止条件

基线：第六批 `130104469` 已通过 `1cf295807` 整合；并行 Scene 最新文档、预算与导航收据来自 `52adbf5a7`，均保留。状态：实施、互审、回归与构建完成，按用户授权窄提交并整合原分支；提交及合并身份以 Git 记录为准，未推送。比较失败历史重复扫描、Video Quick Look 的排序取首和搜索前置过滤后，选择第一项；计数已在第二批完成，Quick Look 收益较小，搜索排序需另证相等键及反向排序语义，本批不混改。

最小结果：在下载合成与可见筛选的每次同步调用内，首次需要重试历史判定时按现役账号提取 failed itemID 集合，后续查集合，退出调用即释放。不引入跨调用缓存、新 owner 或历史订阅；保留 JobStore 的账号/历史权威、保留期与刷新重入合同。两个调用均在 MainActor 无 await 的同步路径中，原 mode/adult/knownID/account/state 守卫、ready 优先、重复 job 单卡、任一 failed 历史命中与排序保持不变。没有可见 retry、账号为空或被前置过滤时不增加历史读取。

保留原 toolbar 全部断言，在真实生产投影与记录叶上补多 retry、混合账号/outcome、后续成功不抵销旧失败、历史清空/新增/换号后的下一次调用等反例；history getter 计数只验证调用期复用，不代替输出断言。相同增强夹具先在原实现运行，新增成本检查预期暴露重复读取，其余行为必须通过；候选全部通过后，再跑历史、库交互、排序及任务弹窗近邻门与隔离 Debug。发现输出/守卫/重入变化即撤回本片，不添加长期缓存兜底。历史最多 100 条，本批只认领重复工作移除，不认领性能、能耗、体积实测；按当前执行授权在审查与验证无误后本地提交并继续下一批。

实施：只改 `SteamWorkshopService+DownloadFiltering.swift` 的两次同步投影与其唯一两调用的 helper。调用方各自持有 `Set<String>?`，首次有账号且到达原 retry 判定点才构建集合，空集合也复用；调用返回即释放。产品净增 7 行，不认领代码体积减少。原排序、去重、失败记录构造、JobStore、认证、刷新和订阅主体不变。两个实施子代理互查对方改动，另一代理复核完整代码/夹具/原样 runner，未发现真实调用丢失、回退或断言削弱。

验证：原 48 项 toolbar 检查及顺序逐字保留，追加 16 项（10 项行为与 6 项读取边界），共 64 项；输入和预期为显式 ID/状态/身份，真实投影、合成与 helper 从生产源码抽取。固定 `1cf295807` 加相同增强夹具的原基线恰有 4 项新增读取上限失败，其他 60 项通过；多 retry 筛选/合成分别读历史 6/7 次，空/仅外账号历史的多 retry 各读 3 次。固定候选 64 项全真，相同场景各读 1 次，无 eligible retry 或无账号路径均保持 0 次，历史增删/换号后的下一次调用反映新输入。成本反例是原实现重复读取的证据，不记为未解决产品回归，也不把原基线记为全绿。

候选一次串行通过 `test_library_toolbar_behaviors`、`test_steam_download_sorting`、`test_steam_download_execution`、`test_steam_download_history`、`test_steam_library_interactions`、`test_steam_download_tasks_popover` 六模块，随后隔离冷 Debug 构建通过。产品、夹具与原样 runner 三份内容身份在回归及构建前后不变。现有映射覆盖该产品路径，无未映射/失效模块；111 项路由/链接、代码健康、断言、设计、依赖和文档/产物/残留门通过。未修改门映射、扫描或棘轮；依赖门只证明其明示的 Scene/测试范围。并行 Scene 正文、其他预算及 runtime 导航收据仍逐项保留。既有三项全局 Scene 结构失败本批未修复，未重跑完整结构组，不报全局全绿。

读取计数只证明历史输入访问减少，不证明元素比较总量、CPU、耗时或能耗改善；首次查询从可提前命中的 contains 改为全量构建 Set，存在分配与单项查询成本取舍。两个函数及刷新重入各有自己的调用期集合，不声称整轮刷新只读取一次。未做真实账号或完整人工 UI 验收。必要证据在 `.artifacts/code-slimming-b7-20261022/` 保留至 2026-11-05；固定导出、临时 HOME/缓存当轮清理，checkpoint DerivedData/App 自动清理，成功原始构建日志提取摘要后删除。复用 worktree 为审核及前批证据保留，其他会话材料不动。

## 第八批范围与停止条件

基线：第七批 `c0673f65d` 已通过 `58d71c9e7` 整合；保留并行 `52adbf5a7` 的 Scene 正文、预算与 runtime 导航收据。状态：在独立分支 `MWX/code-slimming-b8` 完成实施、双路独审、回归与构建，按当前授权本地提交并整合；身份以 Git 记录为准，未推送。比较 Quick Look 排序取首、搜索前置过滤和其他无消费者链后，先选前者；网格 source 仍供搜索隐藏选中项的右键操作回退，不把全 source 换成过滤数组，箭头导航排序另批研究。

最小结果：`selectedWallpaperForQuickLook` 多选分支用 `selectedWallpaperIds.min()` 代替完整排序取首；保持 String 字典序、空集合、单选槽独立、最小失效 ID 返回 nil、不跳至其他有效 ID、重复模型取库中第一条与读取无副作用。Space、菜单、Shell 同步和预览内箭头仍走同一 getter，不新增选择 owner 或缓存。不把算法工作减少表述为 CPU、内存峰值或能耗实测。

现役 UIProjection harness 抽取完整真实 getter，补上述正反例，全部旧检查保持。相同增强夹具先验证原实现，再验证候选；最近 UI/库行为门、独立交叉审查与隔离 Debug 构建通过后本地提交、整合原分支并开始下一批，不推送。任何输出或真实消费者变化即撤回本片，不增加兜底逻辑。

实施与验证：产品仅替换一处完整排序取首，现役 runner 抽完整真实 getter。原 UIProjection 40 项检查/时序及执行配置逐字保留，追加 12 项 Quick Look 正反例，共 52 项；没有复制 min/sorted 算预期。固定 `58d71c9e7` 原产品配同一增强夹具全部通过；固定候选的 `test_ui_projection_efficiency`、`test_library_toolbar_behaviors`、`test_video_inspector_preview_reload` 三模块串行一次通过，原基线与候选 52 项同键同真，随后隔离冷 Debug 通过。三份产品/runner/fixture 身份在独审、回归和构建前后一致。两独立代理复核全部调用及差分，未发现回退或断言削弱。

现有测试映射覆盖该产品路径，没有新增/修改扫描、映射或棘轮；111 项路由/链接、代码健康、断言、设计、依赖及文档/产物/残留门通过。依赖门只证明其明示的 Scene/测试扫描范围，既有三项全局 Scene 结构失败未修复、未重跑完整结构组。真实 Quick Look 面板操作、全 App UI 与性能未在本批验收；这里只证明 getter 语义与最近消费者门，不外推完整窗口表现。必要证据在 `.artifacts/code-slimming-b8-20261022/` 保留至 2026-11-05；固定导出、临时 HOME/缓存与成功原始构建日志提取摘要后清理，checkpoint DerivedData/App 自动清理。其他会话材料保留，原分支整合不暂存并行 Scene 实施路径。

## 第九批范围与停止条件

基线：第八批 `a03b24a8c` 已通过 `715f09328` 整合。状态：在独立分支 `MWX/code-slimming-b9` 完成实施、交叉审查、回归及构建，按当前授权本地提交并整合；身份以 Git 记录为准，未推送。目标只是在 `moveSingleSelectionByArrowKey` 中先过滤搜索结果、再沿原 owner 排序，减少窄查询的排序输入。不改 Shell/Grid 的完整 source：该数组还为搜索隐藏选中项的右键设壁纸/Finder 回退服务，直接替换会造成真实功能回退；也不改网格过滤后去重或原导航不去重的差异。

保留 source context、全局/列表排序选择、String/localizedCompare、nil size、lastUsed 语义、先升序再整体 reversed 的降序 tie 顺序、查询规范化与 title/tags 搜索。保留四方向 clamp、列数归一、多选/search focus/unsupported/empty 守卫及 Quick Look 的 ignoreSearchFieldState 入口。只重排两项纯派生操作，无新 cache/helper/owner；出现完整值/事件/边界变化即撤回本片。

独立导航 fixture 编译真实模型、抽取完整 context/sort/filter/arrow 与选择写入 owner；旧 sort-then-filter oracle 加字面反例校验顺序和状态，不扩张现有 UIProjection 大文件。观察真实排序输入和比较次数，空查询仍同路径，窄查询只排序命中子集；不表述为全 Shell 搜索、CPU、耗时或能耗改善。相同增强测试先跑原实现，行为均须通过，仅新增工作量边界可预期失败；候选全过、近邻行为门与 Debug、交叉审查无误后本地提交整合并继续，不推送。

验证：固定原基线配相同新门，22 项检查仅两项排序工作量边界预期失败，其余 20 项通过；候选全部 22 项通过，覆盖 5376 步导航矩阵及字面顺序、状态写入和守卫反例。1024 行窄查询的排序输入从 1024 降为 4，比较次数从 3542 降为 6；无命中查询从 3542 降为 0，空查询仍为 3542。只证明所测排序工作减少，不把原成本反例记为未解决产品回归或声称原基线全绿。

候选导航、UIProjection、toolbar、Inspector 四模块串行通过，旧检查未削弱；隔离冷 Debug 99.44 秒通过，10 个产品/测试输入在回归及构建前后身份一致。独审未发现误删调用链或功能回退。现役 video-selection-presentation 映射仅追加新门及夹具，原模块、扫描范围和其余门保持。既有 111 项路由/链接及代码健康、断言、设计、依赖和文档/产物/残留门通过；追加历史权威登记组 55/56 通过，唯一失败是原基线同样存在的 composition-background-bounds 历史 README 漏行，已交还并行 Scene 文档 owner 收尾，不修改断言。依赖门仅证明其明示范围，既有三项全局 Scene 结构失败本批未修复、未重跑完整结构组，不报全局全绿。

未做完整人工 UI 或运行性能验收。必要证据在原工作区 `.artifacts/code-slimming-b9-20261022/` 保留至 2026-11-05，成功构建日志提取摘要后删除，固定导出与临时缓存当轮清理，checkpoint DerivedData/App 自动清理。按用户最新要求，临时工作树在本批提交合并、必要证据迁出后删除；后续每批沿用此收尾顺序，不留已完成批次的临时 checkout，保留原工作区及并行会话改动。

## 退出

候选按用户价值、证据与风险选择，达到验收或收益递减时停止该批，不扩成无界清理。专项完成或用户终止后，把稳定职责留在原合同，本文归档为历史证据并退出设计登记；不长期维持第二套引擎路线。
