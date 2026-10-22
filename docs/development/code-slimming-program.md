# 代码精简专项

<!-- document-role: active-plan -->

复核日期：2026-10-22。负责人：repository-maintainer。调查基线：`557ac8a1b398`。

## 目标与边界

减少没有产品消费者的实现、状态和维护分支，收敛重复计算，保持现有用户操作、作者内容、持久化、IPC、失败半径与输出不变。本文拥有本专项候选、分批顺序和验收记录；引擎职责仍归[技术栈合同](../architecture/technology-stack-boundaries.md)，当前运行能力仍归各专题，不另建能力台账。

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

以下是调查线索，不表示已批准实施或已证运行缺陷。每批重查实际消费者和最近反例后再选范围。

| 类别 | 候选 | 后继验收/判定 |
|---|---|---|
| 旧接口 | 旧 SQLite 加载/迁移支链、信息弹窗文本、在线下载描述模型及其他无调用薄接口 | 保留实际加载、退出合并、删除及 Inspector 行为 |
| 测试独占链 | SceneEffectTextureBinding、LatestValueHandoff、旧材质 assemble/derive、粒子 runtime 级快照 | 先将有价值断言迁到当前 prepared/transaction owner；Simulator 快照仍有真实消费者 |
| 测试独占恢复 | helper 超长帧 resync | 统一当前有界关闭合同，保留超长拒绝；不扩大协议错误恢复 |
| 重复计算 | shader 多次 lex/parse；在线列表全量元数据重读与比较器属性查询；视频搜索/导航重复排序 | 同语义上下文复用，文件 revision 和稳定排序反例；收益须实测 |
| 小型算法 | Web 重复小写/正则和 BFS 队列、下载计数排序、失败历史重复扫描、协议 buffer 复制 | 相同输入/输出/失败边界；不引入多余缓存或 owner |
| 冗余构造 | 音频服务二次初始化、串行缩略图队列内 semaphore、状态栏无消费者采样 | 初始化、取消、差分采样及真实 demand 回归 |
| 构建 | Steam restore/publish/签名和 stock assets 全量扫描 | 完整输入身份、资源增删、配置与签名失效；不能只关闭 alwaysOutOfDate |
| 内容判定 | 暗色视频被当作缩略图失败 | 暗色仅评分，保留真实解码 fallback；暗场/损坏/负缓存反例 |
| 数据策略 | 暂不可用文件自动删除索引 | 区分外接卷未挂载与确认删除，先设计数据保留与恢复 |
| 兼容合同 | Web 声明入口与回退矛盾、本地跨文档导航、粒子省略默认值 | 先取得语义与区分证据；不得直接移除 guard 或猜默认值 |

已排除直接删除：WebM parser、旧 Steam 数据迁移器、实际 Simulator 事务快照、必要身份/generation/GPU range/路径授权与生命周期检查；独立工具和作者 API 不因没有按钮而退役。Boids 有界规模、.NET trimming 和第三方资源目前没有足够的安全精简依据。

## 第一批实施与证据

状态：B1-A～E 完成交叉审查，已获用户授权本地提交；专项后续候选仍未实施。20 个 Swift/C# 产品文件合计增加 6 行、删除 1152 行，净减少 1146 行。删去 3 个文件，其余沿原 owner 收敛；未修改生产校验、授权、协议字段、资源范围或生命周期防护。此计数只描述源码体积，不表示性能、包体或能耗收益。

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

## 退出

候选按用户价值、证据与风险选择，达到验收或收益递减时停止该批，不扩成无界清理。专项完成或用户终止后，把稳定职责留在原合同，本文归档为历史证据并退出设计登记；不长期维持第二套引擎路线。
