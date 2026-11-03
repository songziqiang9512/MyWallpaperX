# 全仓校验精简 P0–P27 过程记录

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**

> 截止：2026-10-27，P27 完成后。以下内容保留当时完整方案、实现、原失败及有界验证，不产生新的任务或当前能力。

当前范围、顺序与完成条件见[现役精简方案](../../development/validation-simplification-plan.md#审查方法与完成条件)。

旧表中的“待验”可能已在后文被同一批次的后来结果关闭；P28 已在现役页集中校正。以下“当前/下一步/暂停”和命令只属于各段记录当时的上下文，不能当作今日指令。

下方完整保留归档前正文及所有失败/停止项，唯一转换是相对链接随归档路径调整。原文、归档载荷身份及可逆链接迁移在本批证据中核对；旧 URL 的历史锚点永久转接。

<!-- preserved-body:start -->
# 全仓校验与链路精简

<!-- document-role: active-plan -->

目标：按用户要求先审完 Web 两引擎，再扩到全仓，清退过度严格、重复、拖慢响应且无实际产品作用的校验、认证和附带结构。用户需要直接、轻量、按需执行的代码；历史合同、测试或“更严谨”的说法不能替代真实用途与成本证据。P10–P22 已按用户授权合入主仓，随后 UI 与在线图片模块整合完成。本工作树于 2026-10-27 快进同步 `codex/engine-refactor-program` 的 `492a64dc7`；用户已恢复 Goal，后续修改仍保持未提交供审核。已知重大产品故障优先处理，局部小问题与未覆盖验证明确留在本页。

## 审查方法与完成条件

沿当前实际调用链逐段审查。对每项检查记录其生产者/消费者、执行阶段与频度、直接避免的产品错误、重复读取/计算/等待以及失败范围。无消费者的状态和缓存删除；可选派生缓存损坏或失效回原链重建；下载完整性留在下载/发布事务；普通本地播放不重新证明整个历史目录。保留实际防止解析越界、播错内容、非法访问、异步串台和错误释放的检查，在实际消费处执行，避免层层重验。

完成须同时满足：下表范围均有当前源码审查记录；有依据的发现均已处理或经实验明确撤回无效候选；对应行为回归与必要构建/代表运行完成；修正后独立复审没有发现尚未处理的新同类问题。只报已核实范围和实际前后数据，不能以构建或少数成功样本宣布全仓无问题。发现新问题就继续处理，覆盖表不以文件数或测试数代替。

## 顺序与覆盖

| 顺序 | 范围 | 当前状态 |
|---|---|---|
| 0 | Web 重复扫描/缓存 | |
| 3 | Web：项目/属性/资源权限、宿主/JS桥、媒体/特效/逐帧、进程/可见提交 | P1 有构建及两份产品入口；P3/P5 的目录/hosts/datastore、单 FD、取消、timer、CSS/媒体减工和 Release JS 剥离最近门已过；P6 卡片/方向导航及 P7 作者 memo 暖复用 CPU 门、P7-v6 合并构建已过；P21 完整合并 App 两份真实 Web 的产品提交已过；实际首屏画面、音频完整性仍待验 |
| 4 | 全仓：Video、公共播放/音频/系统策略、图库/下载、存储/索引、UI/工具链 | 父生命周期/单次读取/旧迁移等已有最近门；P16–P19 完成音频诊断/完整窗减工、Video 按需首建/重复发布退役、两路缩略图键复用与旧库发现短路，含实际音频值与 AV/JPEG 前后对照。P22 宿主行投影与 Video 同次工作/无用路径回显校验已精简，完整字段、AV/JPEG、最近原生门与当前 Debug 通过；P23 清退同值派生路径发布/保存，P24 清退导入无消费者路径数组/同次缓存键重算，真实最近门/前后对照与当前 Debug 通过；SIL 原生负缓存及全仓余项继续审查 |
| 5 | 集成：删除死 owner/API/测试、同步现役合同、必要前后对照与独立复审 | 持续进行 |

## 已证问题与裁决

| 发现 | 当前裁决 |
|---|---|
| Web execution payload 清单读取/计算/保存后不被返回值使用 | 删除无消费者缓存；当前属性与授权每次按需组装 |
| Web 暖命中先全文 hash/完整摘要、重复 HTML 再发现、全库预加载 | 用既有实际依赖 revision 失效 analysis 缓存，退役重复发现、预加载及其共享 flight |
| Release 中纯日志媒体 listener/重复 observer；空 RAF/timeout；零 caller merge | 编译剥离或直接删除，无替代状态和缓存 |
| 每屏 DCL/didFinish 重做全部资源授权与目录扫描；用户属性更新又推不变 general 属性 | 请求/资源 revision 同步一次，ready/新 endpoint 重放现值；通用属性仅在自身值变化时推送 |
| 自动交互区域两份 signature 字段/精度不一致 | 统一使用实际 8 字段，未变不重扫/登记；子 frame 不做无用顶层扫描 |
| Web pipe 后台 decode 后，主线程再 decode 同份命令 | 原 mailbox 传同次 typed 值，按原始字节数限额，保留身份/版本/控制屏障 |

旧专项的 D37/D40 验收是历史输入/版本证据，不覆盖这次正式试用发现的回归和后继代码。

## 后继候选与实施边界

初始同屏多层文字沿原 load 已有 raster 的 sourceFont 复用，不新增字体缓存；失败未产生 raster 时后层仍独立解析。

Web listener 优先复用已有方法 hook 与 lease challenge，不加 Proxy/全局 Object 拦截；目录抽样优先消费原 DirectorySnapshot，若携带原目录路径，只在它与当前授权目录相同后使用，不增加第二份长期缓存。任何候选撤回须写清成本或行为原因，不因原方案列过就强行接入。

## 当前验证边界（2026-10-26）

以下 P0/P1/P3 是各固定版本的阶段证据，当前合并状态见文末。P0 最近 19 个模块已通过。P1 选定 CPU/JS、mailbox、资源/图计划/脚本/Release 隔离行为门已通过，优化 Debug 构建、严格签名及构建源快照零漂移已核实。代表 Metal 的 render-target table、offscreen pool、pass encoder、embedded data/image 与 prepared base-image 已通过；图执行/衔接等门的旧夹具补齐后只重跑失败项，不能先算完成。

单次优化 Debug 的入口至呈现/提交分别为：291：2222/982/217 ms；380：1642/859/183 ms。同份 291 输入在旧基线未进入呈现；它不是可计算提速比例的成功基线。上述结果只覆盖单次、两份输入、当前版本；首次 App 使用临时 HOME，并未清 OS 缓存，也未完成逐像素或全部效果验证。

首轮 33 项通过，余项修正测试接线/旧断言后复验通过；编译请求的 Swift/Python key 一致，旧 color-boundary golden 更新同时保留旧协议反例。各次固定源摘要核对无产品漂移，不把夹具修正当成产品提速。Debug/Release 合并构建、GPU 与代表运行仍须完成。两引擎首轮全链静态查漏已汇总，开始扩散到 Video/共享策略及库/下载；后继改动仍待构建和实际运行，持续 Goal 保持进行中。

本机证据集中于 `/private/tmp/mwx-startup-optimization-fbRhFY/d41-playback-validation/`，索引、各门报告及源文件摘要保留；App 与构建缓存不进入仓库。不以该临时目录作为长期合同权威。

### 全仓后继：Video 首播与共享音频

Video 首播没有实际淡入淡出，却等统一 crossfadeDuration 250 ms 才标记 transition complete，ready 又依赖此标记，期间每 50 ms 继续 WindowServer 查询。只将无动画首播分支在原 CATransaction 提交后立即交原 completeVideoTransition，真实可见/几何/Space/窗口归属确认仍走原 observer；已有画面间的实际动画及取消/身份保持。门须区分首播不等空动画、切换仍等真实转场，以及停止/被替换请求不迟到提交。

SystemAudioSpectrumService 的首次日志在 Release 仍每帧扫描 rectifiedMono.max()，静音可持续 30 Hz；hasLoggedCapturedData/captureGeneration 也仅诊断使用。整组观察和字段/reset 随原 DEBUG 编译边界剥离，保真实 captureResourceGeneration、token、PCM 分析及音频响应。用两配置编译与实际代码执行确认 Release 不再扫峰值，不能删除实际分析。

库/下载初审另定位卡片 cachedCanLaunch 的逐次 filesystem eligibility 和 project.json 同次双读取。继续追原字段/实际点击/热键导航/预览的消费者；便宜 UI 投影不应反复证明文件，实际候选和读取归原执行链，不能让外删文件在热键中反复卡住。未核清前不加另一缓存或新认证 owner。

库 project 预览准备沿原 SteamWorkshopProject 解码器只提取既有 preset 图像候选（按原优先级、只收字符串），删除第二次 project.json 读取和整份原始 JSON 投影。原 preferredPreviewRelativePath 统一完成作者/常规/preset/gif/旧 metadata 候选选择，目录 canonical path 同次只算一次；删除其后再次 stat 和绕过原入根判定的 project.preview 后门。无新增 cache/owner；非法可选 preset 值局部忽略，现有合法选择顺序保持，实际预览读取失败仍局部化。最近门用真实文件/实际解码和预览选择，计数同次读取一次并覆盖混合 preset、declared/gif/metadata 次序、缺失与根外路径。

### 全仓后继：事件、分片与重复桥接

Daemon 父生命周期沿原 process exit source 的 registration handler 在注册完成时再核一次父进程，覆盖安装竞态后删除永久 10 Hz getppid 轮询；保退出事件、stdin EOF 和硬退出期限。NDJSON buffer 只记原 storage 已扫描到的 offset，新 chunk 只扫新范围，消费/clear/reset 沿同 owner 更新，保长度限额和空行/分片/合包语义。Steam helper 回包用现有 decode(Data) 入口，删除 Data→String→Data 往返，原 JSON/字段/请求代际不变。状态栏初始化两次同步全采仅保一次；常驻采样与菜单新鲜度/网速基线另审，不盲删。CI 最终 validator 已深验同一未变 App，清掉紧邻前一份同参数 codesign verify；签名、Team/entitlements、公证和发布门不变，不执行发布。

### 全仓后继：卡片投影与实际目标分离

删除不能提供独立事实的 Web eligibility signature/cache。上一张/下一张先按原顺序作便宜投影，再仅沿选定方向逐候选使用原实际可启动判定，失效则继续、最多一圈；实际启动保原异步 request/prepare/FD 读取边界，避免外删文件卡住热键，也不全库 stat。与并行 UI 会话按 hunk 集成，保其混合列表、票据和最近成功接线。

频谱配置在原启动 seed 与音量/速率一起一次落入引擎，首个 Video play 带完整当前字段；真实设置变化仍沿现有差分投影。删除每次 setAsWallpaper 后再次全量配置/清零/IPC，以及仅补首次播种的 0.6 秒 timer，不增加签名去重器或另一设置 owner。最近门须覆盖首播、谱开关、Web 先启动、新进程/多屏及导入重置偏好，避免以少推消息漏实际配置。

P6 补查：声音包 snapshot 同样在独立请求入口确认当前 identity；原 readChunks 完成后和借用已完成私有输出时不再查作者文件，真实读取稳定性与私有输出 revision/lease 保留。下载事务不因可选 preview 无效而拒绝有效入口，预览选择仍在原入根读取链局部处理；实际文件清单、复制和发布完整性保持。在线缩略图 attributes/read 与视频 fallback 的 NSImage open 已会处理缺失，删除紧邻的 exists；不改缓存过期、实际解码失败和 fallback 画面语义。

### P7：下载与旧目录迁移直接消费当前结果

旧 v1 公开目录迁移只负责复制当前作者目录，旧路径继续供现有播放使用；它不应在复制后用旧 contentDigest 拒绝已新增缓存或改过内容的当前目录。沿原私有 prepareSource 将历史 expectedDigest 从迁移 caller 退役，正常下载仍必传 receipt 摘要；本次 FD 复制的路径、稳定性、字节预算、取消和元数据当前指针不变，新 commit 直接记录该次复制已计算的摘要，不先 hash 整树再重算。用旧摘要+新增文件/修改有效入口成功迁移、普通下载同样变化仍拒、读中修改与旧目录保留反例验证。

在线图库下载沿原模型一次选择同一 variant 的 URL/size，直接 GET，删只供进度预估的串行 HEAD；真实响应长度优先、未知长度保原不显示百分比语义。URLSession 回调内及时 move 临时文件接管所有权，删中间整份视频 copy 和对新 UUID 的先删除。发布沿原 owner 在目标目录准备本次自有 staging，再原子替换最终文件；不能先删旧文件再搬新文件，失败清本次 staging，旧文件保持可用，跨卷只承担实际必需的搬移。实际 HTTP 失败在该响应消费点返回错误，不能保存 404 正文为 mp4；不加探测请求、摘要或预认证。用本机受控 HTTP 记录 GET/零 HEAD，覆盖长度、重定向、错误/断流、所有权与取消，以及已有旧文件时发布失败仍完整保留，不访问用户媒体。

SIL 失败签名只在负缓存非空时前置计算，真正解码失败仍生成当前签名；保缺文件反馈。mtime 保原精度，修复同秒同大小合法替换被旧失败条目持续拒绝。在线缩略图定期维护沿原 Shared trim 的同次枚举用实际过期 cutoff 先删除过期 regular 文件、再按剩余大小做原 LRU，不再随后二扫；默认未传 cutoff 的其他调用不变，原初始化清理保留。最近门覆盖空负缓存正常读取、坏图抑制/有效替换恢复、过期优先/新鲜保留、LRU预算、限频与删除失败，不加另一清理 owner。

### P5 最近验证结果

固定 P5 产品源的 18 个 CPU/JS 模块和 9 组原生/GPU/AV/Web 邻近回归已通过，所有运行前后固定源核对零漂移。首轮 CPU 10 项、原生 8 组通过；余项均为测试来源重路径、旧 DTO/解包目录假设、大小写计数或 throwing-autoclosure 编译接线，修正后只重跑失败项，没有改产品来迁就夹具。

P5 未做合并 App Debug/Release 构建、实际冷暖启动多轮对照、字体 backing 内存测量，不能用上述模块结果替代产品验收。本轮测试进程均已退出，构建/原生窗口已明确交还 UI 会话；测试只用任务目录和只读用户样本副本。P6 后继产品改动不在此固定源中。

### P6 最近验证结果

固定 P6 产品源的 16 个选定纯 CPU 单元已全部通过，运行前后源摘要零漂移。首轮 15 项通过；新增导航 symlink 夹具误把临时目录原始路径当作引擎保存的 canonical path，按实际 Engine.normalizedPath 修正夹具后该模块两方法通过，产品没有为此改动。已实测父退出安装竞态/硬期限、增量分片、Steam 代次/UTF-8、纯字段卡片与方向候选、真实 Combine 频谱差分、Web准备/Release隔离、可选预览、在线磁盘缓存和原生 helper 分类一次/签名策略 mock。声音包完成后修改/取消、下一独立请求与读中变更的真实 FD 边界另门已过，未启动 App/GPU 或播放扬声器 PCM。

### P7 最近验证结果

固定产品源的 6 个选定 CPU 模块已全部通过：旧 v1 当前内容迁移/下载 receipt 反例、Shared 实文件过期与 LRU/限频/删除失败、在线调度/磁盘缓存、真实本地 HTTP 下载、Web 作者准备与缓存。HTTP 记录只有 GET、零 HEAD；同卷交接的真实 inode 保持，原子替换成功及最终失败保旧内容/inode、staging 清理、404/断流均过；取消在服务端仅发出 81920/4194304 字节时结束，不是收完后丢结果。跨卷仍承担实际搬移，不据此称任意设备零复制。

Web 属性更新、重置和 Combine 失败保留作者 memo，下一准备 0 作者字节读取/0 解析；override/bookmark/grants 仍重建，作者修改、坏缓存及删除发布 fence 反例保留。首轮下载临时路径与 Web 变量重名夹具修正后通过，产品未迁就夹具。零调用目录校验函数和普通图片重复 input/source 比较已删除；首次输入匹配、当前 revision、完整 snapshot 及实际读取失败门保留。固定源均零漂移，独立复审无阻塞。

### P7 合并构建结果与剩余验收

其余 14 个原生单元归 10 个编译组；其中五个 GraphExecutor 仅共享编译，仍各用新进程/缓存和原断言。驱动静态独审已过，尚未执行；局部清理失败误记成功已修正。字体成本/内存、SIL/其余 Metal、产品入口及交替冷暖对照未验。后继 P8/P9 不在本轮构建中，当前剩余范围见文末合入边界。

### 本批合入与暂停边界（2026-10-26）

本批 11 个相关产品路径相对 P7-v6 从 4438 减至 3915 行，净减 523 行；旧 extractor/report、整包 snapshot 和重复 alias 认证链已退役。该 App 未启动，标识沿现有 Startup 测试配置，当时正式 Release 尚未重建，后继整合基线与 P10 边界见下文。已完成的 P1/P3/P5/P6/P7 结果保留各自固定源边界，不称全部覆盖 P8/P9。

以下暂缓项不阻塞本批本地整合，也不等于已通过：

- 新 Root 的 Sound/MaterialVideo 实际 AV 借用/回收、用户属性视频，以及最新合并 App 的 Web/Video 出画面、切换与停止。
- P10 完整 Release App、最新产品冷暖启动交替对照及字体成本/内存观察未补；主仓 8f715 的已安装 Release 属整合基线，不能覆盖 P10。本页 SourceFacts 数字不能替代产品验收。
- 主仓其他工作树合入后的冲突收敛与受影响回归、长期全范围末轮复查；轻微问题沿此页原责任登记，不另立阻塞平台。

该批合入时保留主仓原有 UI 设计与四处登记，不随本专项暂存，并已通知 UI 专项依用户指定顺序合入。后续整合由相应会话完成；旧 UI seed 后经用户确认为过时副本并退役，不再恢复。当前已按用户授权同步主仓并恢复 Goal，只重验受影响边界。本地整合与交接不代表发布或长期 Goal 完成。

### P10：Web 目录观察与作者调度

Web 在原 owner 内清退三处无消费者工作：同一 canonical 目录的多个属性共用一份现有 watcher，逐属性快照和通知不变，最后一个属性移除才关闭；Release 不维护只供日志的 `reportedSkips` 和应用计数，真实作者 callback、逐属性容错和晚注册重放不变；自动交互区域只在主 frame 调度，子 frame 的真实媒体刷新与公共登记边界保留。不加第二套监听注册表或全局 hook。

Web 作者 RAF/timer 的 schedule 先取 `now()`，随后 arm 无条件覆盖；暂停中新建者也只在恢复 arm 后消费起始时间。原 entry 的初始 `started` 改为 0，真实计时仍由 arm 唯一赋值，省掉每次创建的无消费者时钟调用。用原调度脚本检查调用次数、暂停剩余时长与恢复/取消，再复用真实 WebKit 暂停门。

实际减工对照：同目录双属性现在只有 1 个真实 FD/source，原逻辑按属性各开 1 个；目录 metadata 完整路径解析由 2 次变 1 次。相同新观察夹具执行原 8f715 JS 与候选：每次运行中作者调度的时钟调用 2→1；子 frame 的 20 次刷新触发由 20 个空 RAF→0。Release 实际 Swift 拼接已排除属性日志去重表、计数及统计对象，双配置作者回调/晚注册/逐项容错/颜色兼容均通过。固定 v2 的优化 Debug 构建及严格签名检查通过，源码前后零漂移；430.700 秒只记构建成本。该候选未启动，已安装版本未替换；完整 Release App 和产品入口冷暖计时本批未重跑。

Web 主调用链已复查准备/缓存、IPC/切换、资源/网络、媒体/输入/暂停；下批小项为 RemoteStylesheets 的 Release 纯日志 3 秒 degraded timer，它不阻塞 3 秒，真实请求/重试/激活期限及 layer 恢复须保。声音含 ./、重复分隔符及 .. 的路径当前还受 indexed 入口同类限制，不能只删上层 guard 就声称恢复；须另按原选源 owner 裁决。其中同次 fragment 解析、成对指针求逆及文本 hash/声音 KVO/样式日志已在 P11 处理，结果见下文；其余候选仍未实施，不混入 P10 运行结论。完整全仓复查与前述暂缓验收仍未完成。

Web 主链的已证余项继续落地，同时扩展 Video/公共播放链只读审查，不等待细枝末节无限收尾。

### P16：音频与媒体纯诊断工作归实际调试消费者（双配置回归、对照与 Debug 已过）

Video 三项继续只读细化供后继，不能拿这些候选当已实施。

SystemAudioCapturedFrame 只携带真正分析消费的 signedChannels，rectifiedMono 字段与完整数组/逐窗归并在所有配置退出。首个有声 Debug 日志从本次相同声道按需求原整流均值峰值，不新增缓存、DTO、分析器或第二音频链；保持 Float 求和/除法顺序、阈值与原首次有声标记。这样不把已退出数据包成 Release 空数组，也不让 Debug 在已经记录后继续每窗工作。Factory 的真实 range、采样率、BufferFrameSize 设置和实际状态不变；仅 actualFrames 的纯日志读回进入原 Debug 分支。Service 的 scope、resource generation、连续环形 PCM、worker 快照、FFT/六组数组与静音屏障均沿原 owner。

SystemMedia 的 lastStatus、report 和全部调用/插值只在 Debug 存在；真实授权、PID/track/epoch、需求租约、系统 source 选择、清空、重试与 artwork 按需缓存维持，不删跨异步边界的当前身份判断。比保一个 Release 空 logger，更直接的是编译期撤掉调用点及其载荷。全仓其他检查仍须沿生产者/消费者裁决，本批不盲删真实权限、句柄或媒体格式边界。

验收沿真实 PCM/分析器、恢复/scope 与 SystemMedia/provider/Web/IPC 最近门，Debug 与 Release 运行同一组语义断言、完整有符号样本及公开频谱输出；已退役 mono 断言迁至实际 signed 输出，不能加空字段或伪造兼容值。CoreAudio 设置/读回仅在任务 I/O 边界统计，不能为门调用真实设备设置。Release 剥离应核真实编译输入/符号或输出，不能只检查日志字符串；保原 Debug 首次有声观察及源状态报告。任务片段单独对照完整输出与 -O/WMO 成本，不插产品计数、不声称整体能耗/RSS/启动提速；三路冻结后独审，一次必要 Debug 集成构建，若实际 Release 输入有变化补相称无 DEBUG 编译/门。正式 App、真实音乐/媒体与用户设置不动，不提交。

实际减工已由编译和执行分别确认：捕获帧两配置均只剩 signedChannels，旧 mono 字段/数组/整窗归并退出；Debug 首有声峰值保原运算顺序与阈值，已有日志后不继续计算。正常/Set失败的配置调用中，Release 纯日志 actualFrames Get 1→0，真实 range Get 和 Set 均维持 1；无效 rate/range 或 range 读取失败仍不设置。任务源只将原 Factory 的两属性 I/O 名称重定向，不调用真实设备配置。Media 的 raw SIL（-Onone、优化前）中，Release 不再有 lastStatus 存储、report 声明/调用及状态插值，Debug 正控制仍具备；不是仅用 NSLog 字符串缺失证明，也未用空 logger 隐藏载荷。

40 个唯一方法通过、无跳过。原媒体 Service 的 33 个方法在两配置均执行原语义断言，覆盖授权、来源/曲目 ABA、需求撤销、迟到回调、清空、重试、订阅租约与 artwork 转换；两臂 PASS 一致不表述为全部异步 snapshot 逐字相等。音频门实际比较双配置完整 signed 位模式、六组频谱及连续环形窗/独立快照，恢复门保 scope/配置/迟到资源拒绝。四产品及 owner 测试、任务探针和两个隔离门独审无阻塞。

片段成本使用完整旧/新 Buffer、同一未改 Analyzer 和同一 -O/WMO wrapper，不插计数、不读取旧 mono 强迫它保活，允许编译器自行消除无用工作。4 种 4096 帧双声道 PCM、6 轮交替 AB/BA 的每调用 wall 中位数：Float32 交错 20.967→17.481 微秒，Float32 平面 20.918→17.375 微秒，Int16 22.027→18.282 微秒，Int32 21.770→18.427 微秒，减少 15.4%–17.0%。完整 signed 字节与独立 Python oracle、六组频谱位模式、暖身/计时消费值逐臂相等才接受结果。计时是 decodedFrame 与共同 checksum，append、FFT、设备采集、App、RSS 和能耗均不在此片段内；移除一份 16KiB 逻辑数组不等于进程内存实降。

完整优化 Debug 构建和严格签名检查通过，407.549 秒只记录构建成本；全部产品、测试、项目与 helper/build 输入保持冻结，后写结果与治理索引不要求重建。CodeHealth 的 1506 个 Swift 文件通过，本批 8 个产品/测试代码文件均不超 1000 行。无 DEBUG 的真实音频/媒体门、原始 SIL 与恢复 Release 编译已覆盖本次剥离；完整 Release App、真实音乐/作者画面和整 App 冷暖首帧未重跑，不以片段结果替代。上批登记的六项中，本批完成三类共享诊断减工，Video 三项仍待实施；旧 P12 Release 不含 P13–P16，不能作为本批候选。

本机结果归 d41-playback-validation/p16/final-validation.json、behavior-validation.json 与 audio-buffer-cost-v1/report.json，两份独审绑定精确源码/探针清单；中间导出由 manifest/逐文件哈希差异重建，停止使用的二进制、模块缓存和临时 HOME 当轮退役。保留本批最终固定源、一份连续 DerivedData 和先前证据仍依赖的历史锚点，清单见 artifact-retirement.json。正式安装 App 与真实媒体/偏好原状保留，无暂存、提交或主仓库修改。Goal active，后继按已证 Video 最小职责继续，再扩散全仓余项；本批通过不代表全范围审查结束。

补充只读复查又确认音频后继候选：完整、连续、有限的 capture frame 到 Analyzer 后仍有第二次整窗 finite-map/复制/rolling，且没有独立产品 raw/partial 消费者；后继须收口原入口与真实测试输入，保 callback→worker 快照、时钟、格式重置、Double DC、padding 和 FFT 数值外溢。入口支配的重复迟到判断和已完成幅度的 finite 小项排后处理。这些只是已证调用关系的候选，尚未实施或计入本批收益，详见本机 audit-audio-followup.json；全范围仍按实际消费者继续审查。

### P17：Video 首启按需准备与诊断 IPC 退出 Release（回归、减工对照与 Debug 已过）

P16 已完成双配置减工，本批先闭合已证的 Video 三项：普通库条目不应为旧内置素材迁移先查真实文件；默认关闭的频谱不应在每屏 helper 首建时生成 56 个子层；launched/accepted 事件与只供 Debug Runner 的父端镜像不应由 Release 编码、投递和存储。相比继续扩大音频 DSP 改造，这三项 owner/消费者已清楚且直接涉及库加载或 helper 启动，三路并行实施后交叉审查。音频完整窗/频带余项继续保留为后继，不据本批关闭全仓目标。

旧素材迁移仍由原 BundledVideoLibrary.migratedURL 唯一识别：先用原标准化 URL 核旧文件名与 .app/Contents/Resources 形状，只有真实旧候选才沿原 raw path resolvingSymlinks/存在检查，且仅缺失源才能触发原 lazy prepare/videoURL。Manager 移除前置 normalizedSourcePathExists，保全部记录元数据及原缺源扫描。普通路径、现存旧源/符号链接和相邻不匹配路径不能触发解包，不引入 classifier/cache/新迁移 owner；归档签名、staging、替换及失败语义不变。

频谱只延后首次 materialize：setup 仍挂原容器，空 bar 数组是未建事实，不新增 flag。首次启用前配置/resize 只维护当前值，实际启用沿原 rebuild/layout 并恢复已接纳 levels；首次后的重复启用、count 改动、关闭 0.18s 淡出、峰值与重启生命周期保原路径。不能每次关闭就销毁子层，也不能首次建层把 pending levels 清掉。原 play 的 configuration→enabled→levels 顺序、共享采集需求和实际渲染均保持。

Video helper 的 launched/accepted 发端与父端对应镜像/处理只在 Debug；DTO/线格式不改，Release 沿原 default 忽略意外诊断事件。latestPrepared/latestCommitted 等零读者字段退出全部配置；真实 execution.requests/nextRequestID、latestFinalized、prepared/ready/failed/cancelled/activity ACK、代际和物理退出不变。同一已触 owner 内的零读者 resizedSpectrumLevels 可直接退役；currentActivityID 若全仓确认无读者则连同赋值退出，命令 activityID 存在与 ACK 关联仍保留。不能给 Release 留空镜像或用启动观测当播放准入。

验收走真实 Bundled 准备/迁移与 Manager 元数据、原 helper AV 双槽和新增真实 CALayer 生命周期、父端 typed switch/取消/延迟退休/assembly，以及 Debug/Release 实际 helper 事件。先核 count/实际对象、已选数据与 payload，成本探针不进产品，不把少 56 个层或少事件直接叫整体首帧提速。已接近 1000 行的父端门若需演进，可将完整独立可执行 Harness 自然归 fixtures，以复用真实双配置门，保持原断言与输入字节；不造产品兼容字段。三路冻结并独审后固定源、共享锁串行运行，一次必要 Debug 集成构建，Release 用实际无 DEBUG 门证实剥离；不改正式 App、真实媒体或偏好，不提交。

实际前后工作量对照已完成：同一组 1006 条普通记录的 resolvingSymlinks 与 fileExists 调用各由 1006→0，迁移后的记录逐项不变；现存旧源和活符号链接各仍为 1 次，且两臂均不触发 lazy prepare。计数只在任务源副本观察原调用位置，不进入产品；这是 API 调用次数，不是系统调用数或耗时。缺失旧源、坏符号链接、相邻不匹配路径、等价路径、无压缩包与包稍后出现的真实准备，以及全部元数据和持久化次数另由真实 Bundled/Manager/Model 门执行。

完整真实 helper 的 -O/WMO 前后对照中，默认关闭频谱的 bar/peak/总子层为 28/28/56→0/0/0，两臂原容器均已挂载；新链不为未建立的层推进 presentation clock。当前有/无 DEBUG 的真实 helper 均通过首次启用、pending levels、实际 CALayer 高度/颜色/当前布局、暖对象复用、0.18 秒淡出、caps、静音清零及柱数/resize 行为。stdout 的 launched/accepted 在 Debug 各出现 1 次、无 DEBUG 均为 0；两配置实际命令失败仍带 request/cohort/generation，活动 ACK 保精确 activityID，并拒绝缺失 ID 与旧 request。父端使用真实 Session 声明与实际 NDJSON 分帧/事件消费，核无 DEBUG 无四项诊断存储，prepared/ready/取消/失败/ACK 及实际 execution 身份继续执行。

15 个唯一行为方法通过、无跳过，重跑和编译配置不重复计数。原 AV 双槽、生成短片实际解码/暂停首帧、准备失败保留已提交 item、跨淡出迟到清理、真实窗口可见确认/回滚、父端切换/停止及受控进程退出回调的退休屏障、索引有序保存、频谱 seed/差分及 play 载荷和 IPC 分帧均有最近门。原生短视频使用显式任务根传给夹具，避免 Foundation 忽略 TMPDIR；旧轮唯一 UUID 临时文件已由 defer 删除。真实用户媒体和偏好没有参与写入。

首轮两处旧夹具在 setup 编译时暴露漂移：停止反例仍用已被真实 Session 替换的便捷构造，频谱设置门还持有混合播放列表合并前的请求/恢复接线。只修改夹具：停止反例接真实 Session/受控 transport；频谱门复用真实 Sequence/Admission/request/dispatch/Manager prepare，provider/native IPC 保原记录叶。已退役的 restore 回调和其假计数删除，直接验证配置后真实 play 字段及实际两次配置只 seed 一次；本门不声称 Workspace 启动恢复集成。保留原失败日志，只重跑受影响或尚未执行的门；其余已过输入不变的结果沿冻结清单复用，未给产品增加兼容字段、wrapper 或旧入口。

完整优化 Debug 构建和严格签名检查通过，501.818 秒只记录构建成本，不代表播放启动耗时。构建使用固定 v4 源，后写结果文档和治理索引不改变任何产品、测试、项目或 helper/build 输入，不为结果文字重建 App。CodeHealth 的 1508 个 Swift 文件通过，本批 16 个产品/测试代码文件均不超过 1000 行。产品、真实层/AV 夹具、迁移/计数探针与修正后的 owner 夹具均有绑定精确源码的独立审查，无阻塞。完整 Release App、真实作者壁纸全量兼容、整 App 冷暖首帧、RSS 和能耗未重测，不能用少对象/事件或构建时间替代这些结果；旧 P12 Release 不含 P13–P17，不能作为本批候选。

本机汇总归 d41-playback-validation/p17/final-validation.json、behavior-validation.json 与 work-counts-v1/report.json，失败和复验日志均保留。停止使用的二进制、临时 HOME/模块缓存和中间源码导出当轮退役；导出仍由原 manifest 与逐文件哈希差异重建，最终固定源、必要历史锚点与一份连续 DerivedData 保留，详见 artifact-retirement.json。正式安装 App、用户偏好和主仓库未修改，无暂存或提交，Goal active。

Video CachePipeline 和 Steam 缩略图同一次请求仍重算已捕获的路径/缓存键，原局部值即可传到原 helper，不引入另一缓存。真实原始边界、当前文件身份、worker 快照、scope/时钟/FFT 数值出口及代际仍须保留。Video 首播重复赋值/窗口操作与零调用动画函数记低优先余项。上述均为只读已定位的候选，尚未实施或计收益；依据归本机 audit-next-audio-v1.json、audit-next-library-v1.json 与 review-helper-v1.json。两引擎和全仓还会继续沿消费者审查，本批结算不宣称目标全部完成。

### P18：完成帧直达频谱分析、按需频带与请求内缓存键复用（回归、对照与 Debug 已过）

P17 后先闭合三项已有实际消费者证据的重复工作：共享音频完整窗的第二次扫描/复制和无需求投影，以及 Video/Steam 缩略图同一请求重算路径/键。本批改动 7 个产品文件，沿原 Analyzer/Levels、Manager 与 Steam pipeline 实施，没有新缓存证书、可信入口、wrapper 或生命周期 owner。

音频退役 raw/partial analyze 重载、第二份 PCM rolling history 及逐窗 finite-map/suffix/copy，真实部分回调语义回到唯一 CaptureBuffer/ring。原始格式/字节边界、非有限输入处理、worker 快照、processingGate、scope/generation、capture clock、格式重置、Double DC、padding 和 FFT 数值出口保留在原消费点。长期职责归[共享音频设计](../../architecture/system-audio-spectrum-design.md)。

完整实际 Buffer→Analyzer/Overlay/Web 的四类 PCM、三采样率共 12 组输入，signed bits、全部六组频谱及两路投影逐位相同。相同 -O/WMO、6 轮 AB/BA、每组 48 个计时窗：仅 Overlay/Web 时，12 组各自中位数的中位数为 32.313→16.431 微秒/窗。各组配对比值中位数分别 0.499/0.519。计时含实际需求投影和相同 checksum，PCM 解码在计时外；这是本机分析片段成本，不能替代整 App 首帧、采集成本、RSS 或能耗。

Video 在原请求内复用一次 normalized path/key/output，resolved 的内存/磁盘分支复用同次 key；旧 URL-key/output 重叠 API 与实际 StaticFrame/Removal 调用一起迁移。独立请求仍重新解析。真实完整 generator、相同 H.264 短片/运行路径/-O/WMO 前后共 22 项行为及首张 JPEG 字节一致：三次冷请求的路径规范化 11→3、键计算 8→3；内存命中 2/1→1/1；磁盘命中 4/2→1/1；resolved 磁盘查询 2/2→1/1。上述是原函数/API 调用数，不是系统调用或启动毫秒数。别名合并、重定向后的新请求、丢失输出修复、失败、generation/清理迟到结果、原两许可并发和正常回调主线程一次完成均通过；clear 仍沿原语义撤回已经注册的回调，夹具等待旧队列排空后才重请，未新增竞态保证。

Steam 入口捕获的新鲜 metadata key 直接用于原 memory/inFlight/failure/disk/persist，同次 private helper 消费同一 outputURL，下一独立请求仍查当前文件。真实冷/新进程磁盘/源变更三组门的 16/5/8 项检查通过，包括生成期间 mtime 变化、后续 inode/size 变化、坏媒体、负缓存、原串行后台队列与一次主线程完成。相同 H.264 的冷请求序列中，键与 metadata API 各 11→6，前后生成 JPEG 字节相同；比较保留原 12 项功能断言，基线未满足的“每请求只查一次”是减工目标，未伪称旧行为检查全绿。源在请求中途变化不是新增的原子文件快照保证。

最近 9 个模块中选定的 61 个独立测试方法通过、无跳过；双配置分支和重试不重复计数。普通 Debug 集成构建与严格签名通过，91.448 秒只记录构建成本；优化片段另以 -O/WMO 对照，不把普通 Debug 当 Release 测速。构建后只有测试/证据及结果文档变化，App 产品、项目、helper 与构建输入未变。1510 个受管 Swift 的 CodeHealth 通过，本批 18 个产品/测试代码文件均不超过 1000 行。三路冻结实现与最终夹具/探针经交叉独审，无阻塞。

验证中修正两类测试接线/材料问题，均未放宽产品边界或图像断言：400 样本的噪声块应沿真实 ring 连续拼窗，前 10 块无帧、后 14 个完整窗继续原阈值；原 testsrc2 MPEG4 在本机 AVFoundation 生成整绿 JPEG，ffmpeg 解码同文件正常，改前/改后 JPEG SHA 和四项图像失败完全相同。H.264 彩色素材在相同真实 owner 下通过，最终 Video/Steam 测试及计数均统一该输入；Steam 补已知彩色素材的颜色结构和纯绿/纯灰反例，避免仅尺寸正确就算图像正确。MPEG4 兼容问题仍未修，也未确定具体解码器原因，不能把更换夹具写成产品修复。

本机证据归 d41-playback-validation/p18/final-validation.json、各固定源门、audio-analysis-cost-v1、video-request-counts-v1、steam-thumbnail-counts-v3 和 video-codec-diagnosis-v1。保留最终源、哈希可重建的中间输入、失败/最终日志及必要图像；已停止的二进制、模块缓存、临时 HOME 和媒体副本按 artifact-retirement.json 逐项退役。连续 DerivedData 仍只留任务原一份。正式安装 App、真实媒体/偏好及主仓库未改，无暂存/提交。完整 Release App、当前合并 App 真实作者壁纸、整 App 冷暖首帧/RSS/能耗未重测；旧 P12 Release 不含 P13–P18。

旧工坊目录建记录时，即使已有 project/metadata/pkg 仍 eager 预扫 HTML/视频，后继优先核原 guard 短路；同次新 Steam 预取重复读取 videoURL 可再复用局部值。StaticFrame/Removal 的路径/键余项、Video 首播窗口操作及低收益 Inspector 提示重复投影继续按实际消费者排序，细项归本机后继审查记录；没有把只读候选算作已实施。Goal active。

### P19：旧库发现按需短路与 Video 首播重复工作退役（回归、减工对照与 Debug 已过）

P18 的实现、61 方法、值/图像/工作量对照、Debug 和独审已完成。Video helper 退役每次 play 重设 init-only window/gravity 及同次提交的重复状态/窗口发布，并清掉没有调用的旧动画家族。

LibraryRecords 只让现有 preflight 按原顺序短路，不删除整个候选存在边界；真正 preferred HTML/video、依赖、最终可用性、ghost suppression、当前来源/scan generation 均走原链。这样单个早命中仍只看原前缀，空/坏模型不建全表，避免用 eager 全表索引把小场景做慢；非法路径、后续 pass、重复别名和局部坏纹理维持原选择与失败范围，不预建纹理、不缓存动态资源、不另持 owner。Video 保初始化的实际黑底/不透明/层、display/frame 更新、fill-mode 几何动画、唯一提交点的 activation level/orderFront、取消回滚和可见证明；仅删被同栈或 init 支配且没有其他 writer 的操作，prepared-event 路径回声与 StaticFrame 余项不混入本批。

验收比较真实 installed-record builder 在 project/metadata/pkg、HTML/video-only、空/ghost、优先入口和依赖场景的输出与预扫调用。Video 走实际 helper 的首次/动画切换、取消回旧槽、fill mode 和 display 几何。任务探针只在源副本观察实际调用并先比输出，不向产品加计数器。三路冻结后交叉复审，固定输入、共享锁串行最近门和一次必要 Debug 构建。本批原生/构建沿共享锁串行，与 UI 专项协调后仅执行不抢前台的隔离门，保留其用户验收 App；正式 App、真实媒体/偏好、主仓库和 Git 提交不动。

实际旧库 builder 两重载在同一物理目录树上比较 21 组记录，初始及删源后的全部 24 个存储字段均相同，22 项语义和 9 项减工检查通过。初始 project/metadata/pkg 的 exists API 次数为 24/24/24→24/11/8，HTML/Video resolver 44/42→26/23；删源后为 25/25/25→25/12/9、45/44→27/25。计数包含真正建记录所需的后续入口解析，未删除实际 preferred entry、依赖或可用性消费；这是函数/API 入口数，不是系统调用或启动耗时。

Video 的相同完整 helper 夹具在两臂执行全部原生命周期断言和 9 项真实窗口/层/动画/解码与 resize 事实；新旧事实和原频谱事实相等。整段序列的四类固定 window/content 属性各 5→1，gravity 10→2，path/request 各 14→7，activation level 12→7，orderFront 14→9。以上是实际 setter/赋值入口数；零调用旧动画家族退出不计运行收益。原共同提交、动态 fill 几何、AV 可见准备和取消回滚仍由同一 owner 执行，没有新增可信入口、认证、缓存或 wrapper。

新 Video 动画断言在 Debug 通过而 Release 失败，具体失败子项无旧分解记录，只证实原夹具未同步产品读取的 presentation frame。夹具显式提交并有界等待真实布局、保留原动画/request/level 断言后，两配置通过；不把测试同步写成产品 bug 修复。三路产品与最终夹具均交叉独审，无阻塞。

旧库依赖 host 重复完整记录投影、Video prepared-path/StaticFrame 同次工作、低收益 Inspector 投影与更广全仓审查继续按实际消费者核实，不能只因类型就删掉 video/HTML 字段：图库封面/主题回退和依赖宿主仍有真实使用。P18 登记的本机 MPEG4 AV 绿图未修；完整当前 Release App、作者壁纸、整 App 冷暖首帧/RSS/能耗未重测，不据局部计数宣称整 App 快多少。Goal active，改动不提交。

普通 Debug 集成构建及严格签名通过，84.371 秒仅记录构建成本；App 未安装/启动，保留连续任务原一份 DerivedData。1512 个受管 Swift 的 CodeHealth 已通过，随后仅改两项测试接线/同步及结果文档；本批 11 个产品/测试代码文件均不超 1000 行。构建冻结源与最终输入的 App 产品、项目、helper 和构建工具逐文件相等，因此不因文档/测试修正重复构建。最近门与独审收据归本机 d41-playback-validation/p19/behavior-validation.json、comparisons-v1、debug-build-v1/build.json 及 final-validation.json；停止使用的二进制、模块缓存、临时 HOME/样本和中间源码导出按 artifact-retirement.json 退役，保留最终源及哈希可重建的必要输入。无暂存/提交，主仓库与 UI 用户验收 App 保留。

### P22：宿主仅准备实际依赖事实，Video 同请求直接复用（验证完成，Goal 暂停交接）

上一批完成当前产品入口验证，未证明稳定提速。本批选择已有真实消费者证据的重复工作：依赖边只用 host HTML/folder 却递归做完整 row 的 preview/date/整目录 size；Video 已捕获 path/key/output 后同一次同步调用又重算。相比新增长期 cache 或只按 Web 类型剪掉选源，直接在原 LibraryRecords 将现有选源/分类/准入与发布行投影分开，共用同一准备函数；实际 row 才做展示统计，递归边消费真实 admitted facts，不造部分假 record。库全字段及变更后的新一次读取结果必须前后相同。

Video 沿原 Manager 在本次同步操作传已取得的 normalized path/key/output；延时 1.5 秒或 worker 排队后仍新 resolve/exists，旧 A key 不能读 retarget 后 B 内容。独审确认 prepared 的 path 只是同一 VideoPreparation 原命令回显，不能补充文件事实；当前 cohort/session/request/display、candidate 与非取消已唯一关联后，连同该重复 path guard 直接退役，不换另一字符串认证。原 preparation 事件共用发端清掉无消费者 path 载荷；真正 AV ready/seek、VideoPreparation 的实际路径、独立 ended 路径和异步身份不变，不冒称文件没变。不新增资源凭证、缓存 owner 或认证层。若不能在原 owner 内自然表达，撤回对应候选，不用 wrapper 掩盖。

两路并行实现与交叉审查，根冻结改前/改后源码并串行运行最近库/Video 行为门、真实输入前后输出/调用次数对照和一次普通 Debug 构建。补共享/传递 host、无 HTML admitted/ghost、循环/选源/替换与已发布 row 全值；Video 覆盖内存/磁盘命中、迟到结果、清理/移除、排队 retarget 和实际生成回调。测试改动按自然 fixture 职责保持单文件不超 1000 行。达到当前行为/必要反例和独审后结算本批，不以计数当整 App 提速；实现与验证期间保留 UI App；现按用户授权收口提交并合入主仓。

库侧同一 -O/WMO、同一输入树的两阶段各 42 组案例（包括 nil/ghost）前后完整 24 字段相同。初始实际 preview 入口 57→35 次、目录 statistics 51→35 次；文件变更后的新读取分别 57→34、46→34。项目/Video/HTML/metadata/package 选源与准入入口次数均相同，共享 host 展示工作 2→1、传递 host 3→1。它们是实际方法入口次数，不是 syscall、扫描字节或整 App 时间；真实作者内容仅保旧版本证据。

Video 双臂同 H264 字节/路径与 -O/WMO，18 项实际 AV/ImageIO/JPEG、别名 retarget、清理代际、迟到发布、sync 与派生删除断言均通过，可比输出和 JPEG 证明相同。两次同步 schedule 的 normalize 4→2（hash 2 不变）；sync miss 和 derived removal 的 normalize/hash 各 2→1。排队后继续当前 resolve，不把旧 A key 授给 B 内容；已开始的旧 worker 仍可能写派生 JPEG，但不可回写旧 model/callback，不新增拦截。prepared 无路径也按原 current session/cohort/request/candidate/generation 推进，错误/陈旧身份仍拒绝。

选定 13 个唯一回归方法全部通过、无跳过，覆盖旧库发现/HTML/交互/重载合并、静帧/缩略图/源删除收据、父端切换/显式停止/实际 Engine 组装、真实 helper ready/seek/取消和原生可见回滚。首轮端点 fixture 给 wire 的 let 字段赋值导致编译失败，只改事件构造参数，保错误 request、缺 generation、foreign session/display、取消与无关 path 反例；固定源 v2 仅此测试不同，产品不动，复用七已过单元和独立 intent 方法，失败/未跑五方法复验通过。首轮失败与重试分别保留。调度前另将门内拿同 flock 的 explicit-stop 与其余三方法分开，无嵌套持锁；不为测试调度改产品。

一次普通 Debug 构建与严格签名通过，99.017 秒仅为构建成本；全部产品、项目/helper 输入与最后受测源相同，测试构造修正和结果文档不要求产品重建。CodeHealth 的 1515 个 Swift 通过，当前本批 16 个代码文件均不超 1000 行，新增真实静帧 fixture 归原测试模块；两路最终源、执行选择与失败修正独审无阻塞。本批没有完整 Release/App 冷暖重测、NSWorkspace 实际桌面设置或作者完整像素/音频验收，不把减少重复调用升级为已证明整体提速。

后继顺序（当前）：P23–P26 的发布/导入/缩略图/旧入口减工已完成。下一步是当前作者画面/音频与 App 整链证据、全仓最后复查，以及 SIL 重复导入 metadata 的成本裁决；入口快照/多 phase 不合适，不强加新链。P25 SIL 默认 46 项已过、两个前台交互未重跑。

交接：本机证据入口 `d41-playback-validation/p22/final-validation.json`，含改前/改后完整字段和 AV 原值、各次固定源、原失败、复验与独审。compiler/AV/native 窗口已归还，本批未操作 UI 试用 App；交接检查未发现旧 PID87290，已通知 UI 会话核对；正式媒体/偏好与其他工作树未修改。按用户本次授权提交本专项累积 P10–P22，并合入主仓 `codex/engine-refactor-program`，不推送。长期 Goal 保持 paused，不主动启动下一批；另外两会话由用户通知合并，等待其全部完成后再同步最新 HEAD 继续。

<a id="p23-asset-path-publication"></a>
### P23：派生路径只在实际变化时发布（已验证，未提交）

最新整合未改变这一断点：StaticFrame 缓存命中/生成完成 → updateWallpaperAssetPaths 将 row 以 inout 传入 → 即使 applyAssetPaths 返回 false，仍写回 @Published 数组 → 原 sink 重新排 250ms 保存；完成初载后提交全量 SQLite 替换，初载期间还会进入现有差量比较。同值更新不提供新资源事实；Catalog 已过滤相同投影，Inspector 按资产身份跳过重复预览，缩略图完成有原通知。本批优先修这条可达的重复链；相比 ImportProcessing/Shared hash/Inspector hop，它同时减少发布、主队列工作与持久化，不混入后排小项。

只在原 CacheAssets owner 把匹配 row 取成局部值，复用原 applyAssetPaths 的 didChange，仅变化时赋回原数组；不增新状态、cache、wrapper、接口或全数组相等比较。currentWallpaper 保独立更新，不因 row 未变或缺失早退；nil 参数仍表示不更新，空字符串仍按原值处理。规范化/首次匹配、真实变化、显式清缓存、初载/恢复只读、异步队列当前查找与存储的 revision/epoch 不变。

验证复用原 ordered-save/真实 SQLite 门，补真实 @Published、原 sink/schedule/CacheAssets 的最小模式，不能用已剥 Published 或静帧受控叶充数。真实变化/合并保存、同值及双 nil、已有待保存变化、current 独立补齐、移除/别名与初载边界给正反例；改前/改后同条件观测发布、保存入口及完整结果，不把 250ms 合并误报为每次发布都各写数据库。保原 ordered-save 与必要静帧/导入最近回归，固定实际输入、串行编译/原生，一次最终 Debug 构建；产品与测试冻结后独审，文档如实记录未覆盖。达到这条发布/保存纵切即结算本批，不借机重做全仓调查；本批不提交、推送或改主仓，原 Goal 继续其余范围。

实际结果：同一真实源组装、-O/WMO、夹具与绝对运行路径的改前/改后 11 组案例，完整行/current/database 值及最终 SQLite 全列/行/meta 投影相等。行发布/保存调度合计 15→9 次，原 SQLite 保存函数入口 10→7 次，current 发布 10→10 次。同值与双 nil 各从 1 次 row 发布/调度/保存变为 0；仅 current 缺资产时同样省掉库侧 1 次，current 仍补齐。真实两次变更保 2 次发布、合并为 1 次保存；pending 后的 no-op 不再替换/取消原定时项，必要的 1 次保存保留；初载发布 4→2，实际 2 次保存保留。它们是该输入下的实际方法入口/事件次数，不是物理写盘次数、时间、内存或全 App 提速证明。

两个最近回归方法通过、无跳过：原 ordered-save 的 22 组/27 个进程模式和原全部 case/断言保留；新增模式在 Debug 与无 DEBUG 的优化配置执行相同 11 组并得到相同完整结果。新测试使用真实 Published/ObservableObject、原 sink/schedule/save/load/delta 和 SQLite，真实观测 pending 定时项；测试专用计数不进入产品。复审在运行前发现 stored property 被旧 brace 提取器吞到后续 didSet，仅把 currentWallpaper 组装改为真实单行声明，产品及 Swift fixture 不变；修后再冻结并执行，未制造一轮无效编译。源码、测试组装、实际输出/计数分别独审无阻塞。

一次当前普通 Debug 构建和严格签名检查通过，80.117 秒仅为构建成本；原工作树有唯一编辑 owner，冻结 6200 文件身份，全部门和构建前后零漂移，避免再为本次单 owner 验证全树复制。当前产品仅 CacheAssets 原方法一处局部值/条件赋回，没有新 API、持久状态或认证层。CodeHealth 的 1551 个受管 Swift 通过，本批产品/runner/fixture 均不超 1000 行。首次实际后台 bounce、current 快照保存 sink、媒体/真实系统桌面和整 App 首帧/Release 未重跑；相应代码未改，不能把本夹具受控叶称为端到端验收。旧 AV/静帧门的更新叶是替身，不为本改动重复跑它来补假覆盖。

本机入口 `d41-playback-validation/p23/final-validation.json`；保原始两臂、生成源、输入身份、各门日志和独审，退役已退出的探针二进制/模块缓存/临时环境，继续保留一份 DerivedData。此次不安装/启动候选、不操作其它 App/正式媒体或偏好，主仓保持同步基线 `492a64dc7`。产品、测试和本页/精确正文预算修改均未暂存、未提交；Goal active。恢复后的其余候选按前述真实消费者裁决继续，原 Goal 不因这批通过而缩小或完成。

<a id="p24-import-request-work"></a>
### P24：导入只准备实际消费者需要的路径与缓存键（已验证，未提交）

真实入口已复核：Online/Steam 下载通知通过 ImportedVideoPlaybackObserver 不带 completion；混合批量导入/重新关联的 Coordinator 则需要完整逐输入回执。旧 ImportPresentation 的 importVideos 没有产品 caller，不拿它计算收益。本批只在原 processImportedVideos 的同一主队列提交点，completion 为 nil 时不构造无人消费的 orderedPaths；有回执时仍在原调用时点、summary/modal 之前按原 urls 规范化，保失败/重复输入的顺序。不能用 prepared entries/acceptedPaths 替代原完整输入回执。

原 prepareImportEntries 对有效且未重复的 URL 已拿到 normalizedURLPath，随后 existingThumbnailPath/existingStaticFramePath 各重做 normalize/key。仅该次同步迭代用已有路径算一份原 cacheKey，直接经原 thumbnail/staticFrame outputURL 各自 exists；不新增 API、缓存、凭证或验证层，不合并两命名空间，不把 key 传入之后的资产 worker/播放请求。保真实读取/类型准入、generation/indexEpoch、主线程当前库去重、modal 重入后的撤权、publication/自动播放与 resourceLifetime。

最近门沿原 mixed-import/实际worker/回执/关系提交及 ImportedVideoAdmission；先补它们现有 nil-cache 受控叶，让真实 normalize/key/output/exists 与命中路径被消费。改名前后/资源别名、命中/缺失独立组合、重复/失败/ordered receipts、nil completion、reset/迟到和 summary 重入给有意义的反例，队列后的新请求仍 fresh。双臂使用相同真实源/夹具，仅 ImportProcessing owner 不同，功能/事件/缓存路径相符后报告原 normalize/key 次数，随机生成身份与时刻不冒称可跨进程逐字相等。先冻结并独审，再串行跑必要行为门/对照与一次最终 Debug；无关完整 AV/App/作者视觉不重跑。完成这条原导入链减工即结算，不扩入后排 Shared/Inspector 小项；P23 未提交改动保留，主仓/正式媒体/偏好不动，本批仍不提交。

实际结果：两臂复用相同真实组装、-O/WMO、绝对运行路径与九组输入，仅 ImportProcessing owner 不同。normalize 入口合计 59→40 次，原 cacheKey 18→9 次；exists 29→29、thumbnail/staticFrame output 各 9→9，真实来源准入及两个输出仍分别检查。无回执 miss 的 normalize 4→1；带回执/alias/混合失败及重复输入保原顺序，不能用单个 case 推算整库耗时。缓存路径、事件/行/回执的功能投影前后相同；真实 UUID/时间及 receipt→row/ticket 关系先在每臂断言再投影，未声称跨进程随机原值逐字相等。queued alias 在 worker 开始前改向后选当前 B，summary 内改向仍保原参数求值时的 A 回执，epoch 重入撤权、reset 与缺失/独立 cache hit 均通过。存在的自有衍生文件只证明路径被消费，不冒称已验 JPEG/AV。

四个最近回归方法全部通过、无跳过：原 workspace/worker/reset/mixed-order 方法和完整 main 断言保留；新增 request-work 九组在 Debug/无 DEBUG 的优化配置得到同一功能投影；Admission 保原通知、Stop、迟到/导航/summary 等断言，并验证真实缓存命中路径进入 indexed/pending 同 ticket、后续 miss 不借旧路径。测试原 nil-cache 叶被原五个 cache 方法及独立 owned 目录替换，无新产品测试开关。产品/mixed/probe 与 Admission 相互独审，实际 raw 结果/输入/计数另审无阻塞。P23 两种组装的四份生成源及共享 Model 与原已执行输入逐字相同，保其结果而不重复运行；仅全文源身份变化不被当成行为变化。

一次当前普通 Debug 构建与严格签名通过，28.030 秒仅为构建成本；6200 文件冻结身份及各编译输入在门/构建前后零漂移，后写结果文档/精确预算不重建产品。CodeHealth 1551 Swift 通过，本批六个产品/测试代码文件不超 1000 行。未安装/运行完整 App、重测作者视觉/整 App 首帧/Release，也未测物理 syscall、字节或耗时，不能把减少方法入口当成稳定冷暖提速；真正播放/后续资产 worker 保原重新读取路径。

本机入口 `d41-playback-validation/p24/final-validation.json`，保九组原值、生成源/输入身份、四门日志和独审；已结束的探针二进制/模块缓存/临时 HOME 按精确清单退役，保一份连续 DerivedData。P23 五个原文件另存字节相同的受测状态，产品/测试内容保留；主仓仍为干净的 `492a64dc7`。累积修改未暂存、未提交/推送，Goal active，继续后继范围。

<a id="p25-shared-thumbnail-work"></a>
### P25：共享缩略图只算一次磁盘定位，SIL 预览直接消费回调（已验证，未提交）

沿原 Shared ThumbnailCache 请求 owner 到 SIL Inspector 做一条资源纵切。diskCacheRoot 是进程内静态 URL，namespace 是实例不可变值，diskCacheDir getter 只拼路径；同一生产请求在首次真实磁盘读取时求一次原 diskCacheURL，将局部 URL 传到原读/发布 helper，消除冷 miss 后 rename 再做 SHA256/32 次十六进制格式化。内存命中、加入已有请求不算 URL；derived 命中不提前算 raw URL，derived miss 才算原 sourceDataKey 的独立 URL。同步/异步 image、encoded image 与独立 raw 路径一起处理，不引入跨请求 memo、Request 新字段、公共 API 或新 owner。临时文件仍走原 staging，保 request identity、allowsCaching、取消/移除/clear、原 raw/derived 写入顺序与清理，异步期间目录被移除也只沿原可选缓存失败语义。

SIL Inspector 在已完成的视图树上消费缓存回调：原内存命中在调用栈内回调，原后台路径已统一主队列交付，唯一产品构造入口在 MainActor。去掉该视图的额外 main.async，保 weak self；不增加线程探测、fallback、状态或可变身份。暖命中在 init 返回前显示，后台结果直接交付到原视图，释放后的结果无操作。最近原生 Inspector 门补暖同步、延迟/动作更新与释放反例；实际 Shared 门验证真实交付线程，不能仅用同步替身证明后台契约。

验证先冻结实际输入并独审，再串行运行原 Shared 取消/并发/staging/raw-key 生命周期与命中回归、Inspector 最近门及原 SIL ImageIO/负缓存默认模式，保子秒同大小替换、损坏/缺失、取消反馈。SIL 完整前台卡片交互与本资源改动无关，不为本批重复抢焦点；若仅执行其原默认模式，明确不称整个复合方法通过。同一夹具/实际缓存代码双臂比较 hash 调用及完整功能结果，避免用方法减少推算整 App 首帧收益。一次最终普通 Debug/严格签名；测试计数仅在任务生成源中，不进入产品。完成这两处与原负缓存执行缺口即结算本批，保持 P23/P24 全部改动，不提交、不推送、不修改主仓与正式媒体/偏好。

实际结果：完整 Cache/DecodedMemory 与同一任务夹具、输入 PNG、优化配置的 12 组对照，功能/像素/raw 字节/回调结果一致；diskCacheURL 入口合计 20→12。五种 image/data/raw 冷生成各 2→1，derived/raw 双 miss 4→2、raw 命中补 derived 3→2；memory/join 保 0，单文件/derived 磁盘命中保 1。计数仅在生成源观测，不进入产品，不是 syscall、耗时或整 App 首帧证明。Inspector 同一实际视图/受控缓存夹具双臂，功能、固定来源、最新动作和 weak 生命周期一致；init/延迟回调返回时已有预览从 0/0→1/1，回调均 3 次，省原额外主队列等待。新增模式只查实际 placeholder/视图/动作；原有受控绿色像素/布局断言保留，真实 Shared 的后台主线程交付由另门证明。

五个唯一最近回归方法通过、无跳过，原取消/新同 key 请求、共享消费者、staging 中移除/clear、raw-key 撤权、磁盘/网络复用和 Inspector 原三方法完整保留。首轮弱释放夹具仍在 AppKit 同一 autoreleasepool 内断言，补显式 pool/RunLoop 边界后，在回调仍 pending 时弱引用为空，迟到交付无操作；产品不动，仅复验变化/未跑两方法。原 SIL 默认门首次编译暴露最新 OnlineImage 整合后组装依赖缺失，沿现有 Adapter 门补真实 Model/Projection、原录制叶/实际 applyTransfer 和既有 App stub，不删 case 或断言；修后 46 项与九个负缓存反例全通过。该模式保原离屏 NSWindow/可见性，未跑另两个 active 模式，不能称整个复合 unittest 通过。失败原值、v1/v2/v3 唯一源差异与独审保留。

一次当前 Debug 与严格签名通过，32.844 秒仅为构建成本；冻结 6200 文件，执行前后零漂移。之后只修原测试组装与写结果文档/精确预算，产品输入不变，不重复构建。P23/P24 九个产品/测试文件字节保持，沿用其已执行结果。未安装/启动候选，正式 App/媒体/偏好与主仓保留；未做整 App 冷暖计时、完整 Release 或作者视觉验收。本机入口 `d41-playback-validation/p25/final-validation.json`；退役已结束的探针/模块缓存/临时 HOME，保必要原值、生成源、日志及一份连续 DerivedData。累积修改未暂存、未提交，Goal active；后继范围按上方当前顺序继续。

<a id="p26-import-owner-work"></a>
### P26：导入只发布实际变化，旧选文件入口退役（已验证，未提交）

SIL 原 worker/JSON/回执 owner 不变。finishImport 的 staged 只追加新行，成功分支仅 added>0 时发布，避免全部重复或缺失输入重发同值数组；Catalog 已 removeDuplicates，收益只计原发布/整数组比较，不声称整下游重建。带 completion 的原 synchronize ACK 即使 existing-only 也保留，失败后的真实 JSON 回读/重同步、源事实与失败回执不改。摘要文字与原 modal 后代次检查整体放到 presentsSummary；两个现役 Coordinator 都传 false，不再构造无人消费的字符串。同一主线程纯局部循环前后的重复 epoch 校验退出：main.async 只解 weak self，统一由 finish 入口核当前代次；局部 index/候选循环与 pre-persist 不重核。复审确认合成 Codable/atomic write/synchronize 均无重入，不再保其后的重复读，也不为它制造测试 reset hook；保真正 Published 回调后及真实 modal 后的边界。无新许可、cache、状态机或 owner。

避免重复元数据读取的两种方案已比较：入口快照跳过会改变准备期间删除后的当前库语义，主线程分新项再回后台则增加往返和 membership 补救流程；本批不造多阶段链。请求内重复路径复用只能覆盖重叠选择，不能解决普通已有文件重导，仍作为未完成候选保留。先完成已证无消费者/同栈重复工作；同时删仅旧 readonly 测试调用的 importVideos、私有 makeImportOpenPanel 和失用 import，保真正仍有消费者的错误摘要与只读报告。原小门迁到实际 Commands canImport/importFiles、Coordinator permitsImport/chooseFiles，recording panel/worker 仅证明路由、拒绝与取消，不冒称真实面板或完整导入。

验证复用原实际导入 worker/JSON/回执/SQLite 与 Admission，补真实 Published 的 no-op/真变化、existing ACK、失败重同步、worker/reset、发布/summary 重入和当前库变化反例；同一夹具双臂先比完整行/持久化/回执/事件，再核实际 epoch/摘要/发布次数。保原全部断言，原旧入口三项只读含义转由真实入口无面板/无 worker/无写入加正常正例承担。独立复审、固定源串行最近门与一次当前 Debug，保 P23–P25 未提交改动；不为测试改产品 API，不运行正式 App/媒体或改主仓。完成本导入纵切即结算。

实际结果：同一真实 worker/JSON/回执、实际 Published 与同夹具优化双臂的 11 组，完整行/持久化/回执/事件功能投影一致；UUID/日期与引用关系先在臂内验证再投影，不称跨进程原值相同。epoch 读取 82→36，摘要构造 9→1，Published 事件 13→10；合计含夹具的 reset/membership 事件，实际只省 duplicates-only、missing-only、无回执重复三次同值发布，不是整界面重建/物理写盘或首帧提速。metadata 初始化 14→14、persist 入口 11→11、synchronize 6→6；existing ACK、真变化发布、写失败/同步不确定回读、worker/发布/modal 撤权、当前库变化均保持。计数只在生成源/夹具，产品无观测开关。旧方法与专用 panel 的产品/测试调用退出，仍有消费者的三段 presentation body 字节不变；新小门 14 项检查真实 Commands/权限/chooser，面板和下游只录制，未假称系统面板/完整导入。

五个最近方法全部通过、无跳过，原 mixed/default、Video request-work 与元数据回填断言保留；worker 同一已编译 binary 追加 image-work，不另编译一套门。一次当前 Debug/严格签名通过，37.907 秒只作构建成本；6200 文件执行前后零漂移，后写结果/精确预算不重建。设计/两路源码/实际双臂独审无阻塞，未安装/运行候选或操作正式 App/媒体/偏好与主仓。本机入口 `d41-playback-validation/p26/final-validation.json`；仅保必要源/原值/日志，退役已结束的执行环境，继续留一份 DerivedData。累积未暂存、未提交，Goal active；现版 Release/GPU 可见门及其余范围按上方顺序继续。

<a id="p27-current-engine-closure"></a>
### P27：当前引擎验收与可选缓存写入减工（已验证，未提交）

先闭合当前产品证据，再裁决收益。Web 只删后台保存已捕获 hint 前的 author.matches 全依赖元数据/解析器重验；保 isReusable、实际 load/memo 当前 revision/依赖匹配及 Task/发布 CAS/清理，旧 hint 在真实消费时 miss→原 parse。原 cache 门补 source 变化后旧 hint 可保存但不命中的反例，独立副本对同一未变化 author 的 save 计真实 revision/resolver 调用；不称后台减工为首帧提速。保 P23–P26 未提交内容与正式媒体；测试 GPU 窗口按既有临时退出/恢复授权协调，结果按真实覆盖收口，完整 Goal 仍保余项。

实际结果：Web 两臂完整 7/8 解析值一致，save revision/resolver 5/2→0/0，当前 consumer 保 5/2，过期 consumer 4/0 后 miss→重解析；原 cache 方法通过。当前正常 bundleID/arm64、实际 -O 无 DEBUG 的 Release 编译及严格签名通过，396.928 秒仅构建成本；全树 wrapper 因用户同期要求主仓/工作树 AGENTS 原话更新而报唯一规则漂移，保 raw false 与独立输入分类，其余 6199 文件未变，不为规则重建。随后含新规则的 Debug 28.709 秒、签名与源身份通过。正式 App 已重新打开，未声称此前壁纸状态逐字恢复或完成当前 App/作者整链运行。代码/测试/实际结果独审无阻塞，本机入口 `d41-playback-validation/p27/final-validation.json`；停用执行环境清理，保必要源/原值/日志与一份 DerivedData。主仓仅 AGENTS 按本次指令同步，全部改动未提交，Goal active。
<!-- preserved-body:end -->
