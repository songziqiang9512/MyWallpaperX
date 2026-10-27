# 全仓校验与链路精简

<!-- document-role: active-plan -->

目标：先全面审查 Scene、Web 的启动、资源、纹理、shader、渲染、特效、普通帧、缓存、IPC 和生命周期，再扩到 Video、音频、获取、图库、存储和工具。主动删除对实际功能无帮助的校验、认证、重复计算和嵌套，使链路直接、按需、轻快。用户原话与必要边界由顶层 [AGENTS.md](../../AGENTS.md)约束；不能拿旧实现、旧测试或“更严谨”反向保留无用工作。

状态：本次全范围审查、同类问题修正及回归已完成，Goal 结项。P10–P22 已合入主仓，当前工作树基于 `codex/engine-refactor-program` 的 `492a64dc7`；P23–P35 已完成；2026-10-27 用户授权按“引擎启动改进→UI改进→新模块接入”依次提交、合入该主仓分支，不推送。2026-10-27 用户要求的两段原话已同步主仓和工作树顶层规则，主仓除此未改产品或 HEAD。完整原方案、P0–P27 过程和失败原值转入[历史记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md)，不再从旧批次的“下一步”续接任务。

## 审查方法与完成条件

沿真实生产者到实际消费者检查每项工作的阶段、频度、直接避免的错误、重复读取/计算/等待和失败范围。先查已有上下文能否直接使用；在实际读文件、消费资源或提交异步结果处保必要边界，同步纯计算之间不反复证明同一事实。普通视觉或可选缓存失败只影响最小单元，失效沿原读取/解析链重建。不能为了证明“安全”新增许可、wrapper、多层 fallback 或第二 owner。

完成需同时满足：下表全部范围有当前源码审查；有依据的发现已修复，或由实际消费/成本实验明确撤回；改动经过最近行为门、适用构建和必要代表运行；独立复查没有未处理的同类问题。少数样本、构建或测试数不能代表全仓完成。旧额外指标若既无具体回退风险、也非本轮要宣称的收益依据，应说明原因退出，不把可想象的验收无限升级为硬门。

所有前后数字绑定相同真实输入、代码与执行边界；方法次数不是 syscall、物理复制、耗时或首帧提升。UUID/日期先在每臂验证身份及引用关系，再比较功能投影。当前构建和原始失败均保留，修夹具不放宽产品结果。每批报告实际改变、前后对比、回归与未覆盖范围；Git 操作按用户当前授权，三会话串行整合、不推送。

## 顺序与覆盖

| 范围 | 当前已证事实 | 仍需完成或保留的边界 |
|---|---|---|
| 0：误拒播及当前产品 | 历史摘要播放许可、旧迁移与 MDL 数量/路径政策已退役；P29 当前 Debug 的 Scene→Video→Scene 呈现/提交与两作者 Web 提交通过；正常身份作者 Web 的实际音乐响应、暂停/恢复和普通退出通过 | P27 Release 是当时源码的构建；当前 P29 运行是 Debug。不据此宣称全作者视觉或稳定提速 |
| 1：Scene 资源、读取、解码、模型、字体、媒体、纹理 | 单次 snapshot/MDL/粒子准备、引用闭包、Raw/BC 上传与已完成媒体复用经最近门和成本对照；P27 初始字体 7 个 raster 的字号、来源、上传字节与 fallback 通过 | 字体门是 CoreText 栅格/Metal 上传读回；不宣称全作者组合、官方一致性或内存收益 |
| 2：Scene shader、Program/graph、特效、普通帧、输出与生命周期 | 准备期静态事实直接进入 typed frame/encode，纯诊断退出 Release；P27 Puppet 原 18 方法通过；P29 去掉两处同栈重复 lighting 验证并验重入；P31 静态镜像退休、P32 forward 按消费者求逆经原 Finalizer 与实际 Graph GPU 门 | 保 resolve、device/target/alias 和动态字段真实检查；不重开无具体风险的全历史矩阵 |
| 3：Web 模型、授权、宿主、桥、媒体、帧、缓存、进程提交 | 原 descriptor/context/host owner 保持；P27 writer 减工已验；P29 空 options 读取 2→0、需求短路及 Release 纯音频日志退出经最近门；正常身份 Dashboard 同请求实音、暂停和恢复通过 | 可见音乐响应由用户直接确认；歌曲封面仍有局部 `[object Object]` 资源错误，保留问题，不冒称完整兼容 |
| 4：Video、共享音频、IPC、获取与存储 | 完成帧直达频谱、按需频带、Release 诊断剥离、原文件/分片/票据边界和旧库发现均有逐批行为证据；P22 实际 helper/静帧/取消门通过；P31 恢复时未消费 SHA 退休，真实 receipt 相同；P32 校验临时构造退出、四个实际授权点保留 | 只补当前变更影响的整合边界，不把旧系统恢复/长运行全部再跑一遍 |
| 5：全仓、图库与工具 | P23–P28 图库减工及旧入口退休已有对应行为/成本证据；P29 删除普通建库连接的全库 quick_check，45 项 Store 原行为一致，v1/事务/故障门通过；作者快照工具不再携带安装 marker；P31 设置导入局部复用与在线目录无消费者预取退休均经实际最近门 | 全仓实际消费者复查完成，最后工具与协议项见 P34/P35。UI 专项布局/交互由其 owner 维护 |

P27 的 Release 构建期间用户更新了 `AGENTS.md`，原全树 wrapper 的 `passed=false` 与唯一规则漂移原样保留。编译/严格签名成功，其余 6199 文件及 1186 个实际 Swift 输入未变；独审接受产品构建，不为规则文字重建。后续 Debug 已含新规则且零漂移。候选 App 仍是未发布的本机构建，正式 App 已重新打开；未声称精确恢复此前未捕获的壁纸状态。

## 执行职责与稳定合同

Scene 继续 `authored data → prepared Program/graph/resources → typed frame update → Metal encode → unique compositor/output`。普通帧不重新解析、编译、建图、整图序列化/哈希或维护无消费者诊断。目标与接线分别查[运行时架构](../scene/architecture/runtime-architecture.md)、[启动合同](../scene/architecture/scene-launch-responsiveness-contract.md)和[源码地图](../scene/architecture/runtime-as-built-map.md)。

来源 revision 在独立请求实际消费处取得；已完整读取的不可变 snapshot 不在后续纯计算中重新 stat/认证作者文件。真正继续读的 FD、chunk、segment 仍保范围、短读/读中变化、取消和路径授权；私有完成输出保原域、预算和强 lease。下一请求仍取得当前 revision，不引入长期免失效凭证。

按实际引用读取不等于忽略潜在资源。隐藏/动态层、材质脚本模型、根/子粒子及已解析 MDL 材质 links 沿原 loader 的同次闭包保留；真实歧义与 root/namespace 优先级保持，坏单元局部失败。不可变 Program/uniform/graph 事实只在原准备 owner 接受一次；实际 publication、device/epoch、texture hazard、物理资源生命周期在帧消费处检查。首次 helper 签名/路径边界保留，不反复为每个 shader 认证同一 Bundle。

Web 仍沿原 descriptor→runtime interpretation/context→唯一宿主/每屏 surface，授权根、navigation/bridge/音频及 request identity 在真实消费处维护，见[Web 模型](../web/web-project-json-runtime-model.md)、[准备设计](../web/cold-descriptor-parse-offload-design.md)和[宿主合同](../web/dedicated-host-process-design.md)。已捕获的派生 hint 可异步保存，读取端失效只 miss；保存前不再扫描全部依赖，不授予权限或阻塞播放。

下载完整性归原获取/复制/发布事务，不把旧摘要变成日后播放许可；普通本地播放不重验整目录或全部包条目，见[获取合同](../architecture/steam-workshop-acquisition-contract.md)。跨引擎切换、取消、提交与最后资源退出沿[现有事务](../architecture/playback-lifecycle-transaction-design.md)。实际服务、frame/clock、资源与输出各有唯一 owner，不能为精简再造第二套权威。

## P28：同次导入复用已读取元数据，已验证

已证重复：原 worker 为每个展开输入构造模型并读 stat/ImageIO，主线程才去重；`[a, alias, a]` 仍读三次。只在该 worker 局部按原始路径 UTF8 字节复用首次 fileSize/width/height；原模型同一构造入口每次仍产生独立 UUID/addedAt/path/title，原 candidate/输入顺序、exists/isDirectory/isReadable 与每输入回执全部保留。不同 alias 不合并；不把旧库行或入口快照当当前来源，不增加主队列往返、持久缓存或 owner。

元数据只服务信息/排序，实际播放仍消费当前行路径。一次请求内的 first-metadata 语义不冻结文件 bytes 或授权，独立下一请求重新读取。普通单文件的一次准备仍可能成为最终新行的元数据；提前按库快照跳过会改变实际 cleanup/load/reset 与当前提交语义，额外多阶段补救方案不采用，不能把这一次准备也计成已消除。

本批先保持原导入/JSON/ACK、当前库/epoch 与发布/modal 语义，单独观测真正 stat/header 入口，不能用模型构造数冒充读取数。核重复/重叠目录、别名、文件变化、每输入可用性和新身份；前后完整行/回执/持久化结果先一致，再报告减工。沿现有 mixed-import/metadata 最近门和一次适用 Debug 验证，旧已过源码不重复跑；若实现需要新的阶段或缓存权威，撤回该扩张。

结果：同一实际夹具、同编译选项、每臂一次编译，原 11 组 stat/header 各 14→12；新 3 组分别 6→3、2→1、4→4，模型构造数及原六项发布/保存/epoch 等计数逐组不变，输出/持久化/回执/事件投影相同。3 个导入方法、1 个下载最近门通过，Debug 31.527 秒、严格签名成功且源无漂移；构建耗时不是播放性能。退休的 preload 测试字段、方法和断言已删；下载夹具首次因既有 Web 缓存协作者装配缺失而未编译，补齐原受控叶后通过，未放宽实际断言或恢复退休字段。独审绑定原始两臂结果；未宣称实际 App 首帧、物理 IO 或内存提速。

## P29：常规打开与实际消费者之间的重复工作

本批回查发现：关系库每次普通打开仍执行整库 `PRAGMA quick_check(1)`，包含当前快照不消费的封面数据页；Web 空 options 的编辑事件仍准备定义和值，读取解析 project；两处 Scene 已解析 lighting 在同一同步栈又验证同一 target；部分 Web 音频代码仅为布尔需求分配数组，或在 Release 注入无日志消费者的调试分支。沿原 owner 直接移除这些工作，不增加长期缓存、准入凭据、wrapper 或新的阶段。

关系库保 SQLite 实际错误、schema/application ID、事务、当前行/alias/epoch 检查及 v1 升级事务内的完整性检查，普通已建库打开不再扫未消费页；封面读取保自己的数据边界。目录 fsync 候选已撤回：原发布失败后仍需完成目录持久化，直接删除会破坏实际恢复语义，为省一次同步另造凭据反而加重链路。Web 非空动态 options、Debug 诊断消费者、音频真实生命周期和 Scene 原 resolve/target/device/alias 检查保持。用最近行为门、读取/SQL 入口对照及一次 Debug 验证，再补当前 App 代表播放，完成前不写为已通过。

结果：45 项原 Store 行为断言两臂全真且一致，实际 prepare 入口的 quick_check 10→0（多个 Store 各首次连接，不是每 snapshot）；原 v1 升级/封面/回滚、发布恢复和 SQLite 故障三门通过。空 options 同一真实 Web 夹具读项目 2→0，非空默认值、覆盖值和磁盘变化保持；Scene 3 门、Web cache、音频需求和真实 Debug/Release 拼接 JS 门合计本批 9 个方法通过。Startup Debug 27.862 秒、正常身份 Debug 12.352 秒及严格签名通过，构建不是运行提速。首次 lazy 闭包缺 self 的编译失败、DYLD 观察探针 SIGBUS 和脚本装配失败均保原值，只修受影响部分。

同一候选实际 Scene→Video→Scene 和 Dashboard/Matrix 两种 origin 的提交、当前身份及子进程退出通过。普通 App 验证使用正常身份、独立 HOME/私有设置 suite；用户确认真实音频柱响应，并分步暂停保持、继续。记录证明同一 request/活跃子进程暂停后页面频谱归零、采集停止，恢复后真实非静音回调再现，最后普通 Cmd+Q 退出全部已观测子进程。正式偏好原值已核对恢复，再打开原安装 App。旧 Startup 专用身份拒绝普通入口和首次 240 秒观察超时不计为播放/普通退出通过。

首次受管 Scene 测试副本漏复制库根当前指针，实际在 daemon 之前拒绝；补一个对应索引、只重定位 legacyFolderURL 后，同 App 通过，原 commit/marker/作者字节未改。通用 `scene_sample_snapshot` 职责是作者快照，现直接排除 App 安装 marker，复制和树核验共用同一策略；原 create/verify 及相邻同前缀作者文件检查通过。受管库整合测试另保当前 pointer+marker 配套，不把通用作者工具改成安装库克隆器或新增认证平台。

## P30：目标元数据直读与共享读取复用，已验证

单条 `publishedMetadata` 目标查询不再先枚举和排序全目录：在原 index FD 下选择一个实际 basename，立即 openat 捕获 errno，仅目标打开时的 ENOENT 作缺失；已打开后的类型、硬链接、4MiB、读中变化与取消仍由原 readData 消费边界检查。全库发现/GC 保原枚举、排序与预算。ID/filename 两筛选仍取交集，显式 filename 保旧独立视频名支持。文件名只要求元数据后缀、无斜杠/NUL，不把相对资源路径 parts 的冒号/反斜杠政策或任意 255 UTF8 字节上限套到真实目录项；本机已复现合法冒号、字面反斜杠及 305 字节中文名，原路径限制会误拒或误读它们。

直接读取在现函数内完成，不扩全局异常模型或另造 helper/cache；原 openFile 预读 info 与 readData 的首个 info 重复，元数据读取仅保实际 readData 前后检查。相邻共享项沿原 owner 复用 OnlineImageStore 同一次解析已得的目标叶属性，缺失祖先的属性不能当目标存在；SystemMedia 七字段 UTF8 长度直接计数，不为 count 构造 Data。用既有最近门和同输入 FD/读取入口对照，冻结后一次 Debug；P29 无关的音乐/系统恢复不再重做。

结果：实际原 owner 两臂读取同一 135 项目录，3 类已有目标查询 readdir 入口均 138→0、排序项 135→0，实际 openat/pread 各 1→1，regular-info 3→2；目标缺失从枚举后不打开改为直接尝试一次失败打开，仍免全目录发现。无筛选查询保持原枚举/排序和两份读取，regular-info 6→4；五组返回字节完全一致。这里是实际入口调用数，不能当内核 syscall、物理 IO 或 App 首帧耗时。另两项只报告源码明确删除的重复属性查询和临时 Data，不宣称测得内存或墙钟收益。

11 个最近回归方法零跳过通过，覆盖目标名/缺失/错误、真实文件叶边界、原发布回滚/当前删除、播放租约、在线图片发布/取消和媒体 UTF8/原子快照。合法冒号、字面反斜杠和长中文名实际创建/读取成功；symlink、directory、hardlink、超限文件和残留 errno 不被误作缺失。正常身份 Debug 38.446 秒、严格签名成功，6202 项源码前后零漂移；未启动新 App 或改正式偏好。两项独审无阻塞；新夹具没有注入读中并发变化或取消，不升级为所有 FD 并发情形证明。

## P31：普通帧静态镜像、下载恢复和显式导入，已验证

本批沿四条真实调用链完成五处减工：Scene 每帧对同一编译结果的不可变 uniform 字段与其 map 产物再做整表比较；下载恢复对已有 chunk 计算从不消费的 SHA256，仅 Adler 结果参与判定；个人设置导入同一请求重复解析相同路径；在线下载目录为所有文件预取属性，实际选中后又丢弃这些属性并重新读取。按频度优先普通帧，再处理恢复与导入。先核各自唯一生产者和实际副作用，沿原 owner 删除或复用；不新增许可、stamp、长期缓存或第二权威。均已核唯一生产者和真实消费者，不引入新 owner。

Scene 保实际动态 uniform/字节、host/resource 和生命周期边界，失败详情仅在失败时生成；下载保原读取、取消、Adler 和最终真正消费的 receipt SHA256；导入沿原局部 normalized 表复用同一准备快照，下一次导入仍重新解析，原缺失计数、别名和恢复事务不变。在线目录仅去掉全目录属性预取，选中文件仍清缓存后 fresh 读取，AV 后仍核当前 identity；正常行为不依赖先取得再丢弃的值。

功能结果：Finalizer 原 34 方法、原 GraphExecutor 真实 GPU 门、helper 离线/Release 隔离门、导入 3 模式及在线目录门共 40 个方法零跳过通过；Debug 32.520 秒和严格签名通过，产品源码未漂移。新增导入反例走原 SQLite/源 owner，重复路径与不同 alias 保持，独立下一次导入重新捕获已 retarget 的 alias。在线目录门首次因既有夹具缺少当前 expectedBytes 参数而未编译，只补该受控叶签名，原实际断言保持，再单跑通过；原失败保留。

同输入 hash 对照：4 个已有 chunk 的有效恢复原喂给 SHA256 131091 字节、现在为 0；真正最终 receipt 仍喂入相同 131091 字节并得独立 Python 算法核对的相同 digest。坏 checksum/截短结果一致，原取消门保留。减少的是未消费 SHA 工作，文件读取和 Adler 没减少，不当作物理 IO 或启动百分比。补齐的两臂结果：相同原完整 Finalizer 夹具的 cold/warm 进程均为 166 次 resolvedUniforms 入口，字段实际比较 1893→0、bindingFactTokens 列表构造 183→0，完整功能 JSON 相同；两次真实导入的路径解析入口 10→6，完整行/locator/summary/checks 相同，独立下一导入重新解析 alias。cold/warm 仅为每臂独立进程与私有 cache 范围，不是 App 冷暖启动。优化两臂实际编译耗时长于估计，原运行保留、没有重复编译；两 wrapper 源零漂移，结束明确归还窗口。这里只报告原入口工作量，不据此宣称硬件指令、CPU率、RSS、物理IO或App速度。

## P32：正向矩阵按实际消费者计算与查询校验减工，已验证

Scene 逆矩阵是现有唯一输入，UniformInputs 的 forward 存储只有 Finalizer 从 inverse.inverse 构造、只给 forward host 读取。退役这份冗余字段和构造参数，沿原 UniformEncoder 的 forward 分支执行同一 Float 求逆；在原 resolvedUniforms map 内只复用首次成功的 float4x4 编码 Data，双 stage 仍一次计算，各字段仍独立校验字节数并发布原 offset。无消费者或 inverse-only 不求 forward；坏类型、array、奇异与非有限输入保原实际消费处失败。保 typed frame/preflight 与原几何精度；不用语义不同的 output MVP 代替，不增 flag、全表预扫或长期缓存。

WorkshopQueries 的 ValidateAccountLocked 直接比较当前账号字段，保原 Epoch/login/TryParse 三谓词，再单独求当前 token，最后比较 Connection/SteamId/token，避免短路改变原 getter 异常顺序。真正入队 Capture、锁与四个 chunk 授权检查点不改，不新增凭据或跨 await memo。另删 MapItems 的 fileType/hcontentFile 两个无 Swift 消费者的输出列；只触及 browse/details/author/subscriptions 四类行投影，SDK raw、Probe 和实际下载仍保原字段。旧 JSON 额外列不构成客户端功能，退出无须迁移状态机或协议新层。

沿原 Finalizer/GPU、Auth/Query/helper 和 Swift decoder 最近门补真正反例，原行为保留；同输入比较实际被请求的 forward 求逆入口与输出字节，不能用源表达式次数冒称硬件求逆或启动时间。前后编译使用相同优化/WMO选项减少任务自身重复前端工作，不重跑 P31 旧完整计数或无关系统恢复。源码冻结后一次适用 Debug，失败只修真实错误；实现前的设计与独审见本机 p32 证据。结果：原 Finalizer 35 方法、GraphExecutor 实际 GPU 门、helper 离线/Release 隔离及 Swift 查询门共 38 方法零跳过通过，另 15 个协议 golden 方法通过；Debug 33.626 秒、严格签名成功，全部实际产品输入零漂移。本轮没有 App 启动/退出或正式偏好写入。

两臂原完整夹具的 11 个具名实际 finalization case、13 项新检查与全部原功能输出一致。每个 no-forward/inverse-only case 的 effect inverse 表达式入口 1→0，forward/dual 仍 1→1，原 Float 编码字节、stage/offset 与错误结果保留。数组在真实 bounded Frontend 准备期拒绝；初始夹具错假设它能进入 Finalizer，由独审在运行前纠正，不扩大产品数组能力，也不声称缓存命中后的不可达错误 ABI 已跑过。直接 encoder 类型反例与原每字段大小检查保留。

账号对照仍有 3 个原 CDN 检查 callback 和 1 个原锁内 Send，真正 admission 构造 1→1，校验的 Capture 构造入口 4→0；六个等值/拒绝 predicate 一致。同一实际 ProtocolWriter 单行响应 658→618 UTF8 字节，仅剥两退休键后全 frame 相同；SDK raw 与实际下载不改。这是原表达式/构造入口与 wire 字节，不等于硬件逆、GC分配、CPU率或 App 冷暖耗时。cold/warm 是每臂独立夹具进程/cache，未重跑 P31 旧门或系统恢复。三份实际结果/产品独审无阻塞。

## P33：退出未消费登录载荷与最终范围审查，已验证

当前实际恢复链只消费 refreshToken、真实 accountName 与账号身份。helper 的 result AccessToken/NewGuardData 仅给成功终态 private 输出；Swift 不读前者，后者只转存到 Keychain、从不恢复。沿原 SteamSession→AccountSession→AuthRoute→TokenStore 四 owner 删除这两项无用传输、tuple 成员和 guardData 持久字段，保原 refresh 登录、真实账号名、attempt/epoch/terminal、记住/撤授权与保存失败语义。SDK 的 LogOnDetails.AccessToken 实际承载 refreshToken、PICS/raw 与 Probe 的研究数据有不同职责，均不混删；隐私脱敏和旧格式反例保留。

旧 helper 的额外键与旧 Keychain JSON 按原解码规则忽略，无协议升级、迁移状态机或主动读取重写。只在现有离线 helper 和 client lifecycle 夹具补真实成功帧/旧新载荷、mock persistence 与内存 codec 反例，不接真实账号或 Keychain。原保存次数不变；本项只报告未用字节/字段退出，不能称减少一次保存或 App 启动提速。源码冻结后最近门和一次 Debug，同时由独立审查收口 Scene/Web 与全仓剩余实际消费者；原 client 生命周期与 helper 离线门零跳过通过，含真实 BeginAttempt/FinishSuccess/Writer 的成功、旧/重复终态，以及旧额外 private 键/新最小载荷、mock persistence 保存次数和旧 Payload string/null guardData 的纯内存 codec。另 15 项协议 golden 通过；Debug 32.316 秒、严格签名成功，全源零漂移。未读取真实凭据、执行登录或调用 Keychain。实际 SDK refresh 登录、PICS/Probe 与隐私 redactor 保留。工具误拒与 marker 残留由 P34 处理。

## P34：作者工具按实际输入读取，已验证

产品现已支持完整 loose Scene，作者快照和两种隔离运行入口却仍把 PKG 存在当格式许可，导致合法 loose 输入在实际 reader 之前被拒。仅沿原 snapshot/lifecycle/sample-run 和 generator 身份投影退此前置条件；项目读取与实际 Scene 解析仍由原 consumer 处理。缺包时 package name/hash 如实为空，不伪装包或用 tree hash 冒充 package hash；loose 输入复用原 tree_manifest 身份，显式预期 package 的原比较继续报告不匹配，旧包结果保持。product-entry audio 保原只报告 hash 的语义，不加原本没有的准入层。

作者副本统一沿 snapshot 既有 exact DERIVED_NAMES 排除安装 marker 与派生文件，邻近 .author 名仍复制。管理库整合的 pointer+marker 配套另走原路径，不造克隆器或新 Root/parser。PKG 专用 census 按已声明职责保留，不强扩为通用输入平台。相邻 debug archive 在原两 JSON reader 内复用本次原 bytes 的 hash，保 UTF8 解码语义和原报告字段，不为同次身份另开文件读取。

最近原 Python 工具门核 snapshot/copy/manifest/generator/controlled process 与旧包投影；必要时补自有 loose 输入的有界产品入口，不能把受控进程当实际 Metal 证明。工具-only 变更不另造 App 构建。作者工具原 59 方法与归档原 2 方法零跳过通过；旧包完整 golden 不变，loose/source-tree、明确包摘要不匹配、marker/.author、生成矩阵身份与原 UTF8 错误/摘要/每文件读取一次均已验证。独立静审两组 13 路径无阻塞；这些证明 Python/受控进程，不升级为真实 Metal。P33 原生门及一次 Debug 已完成，窗口已归还；最后复查补获协议 ID 的同值二次解析，由 P35 在原方法内处理；Goal 最后裁决同时核本轮合同、源码、Git与产物。

## P35：协议 ID 只解析一次，已验证

`queryDetails/querySubscriptionStates` 的合法 ID 原先先 `TryParse`、再 `Parse` 同一字符串，后一次没有独立消费者。沿原 `PayloadULongArray` 直接收集首次成功结果，每个合法 ID 解析 2→1；保持原过滤、culture、顺序、重复、零和 UInt64 边界，不新增缓存或准入政策。原协议自检已补两实际命令的混合输入、空载荷及 culture 边界；原 helper 离线门零跳过通过，protocol 35/35、auth 48/48，原 manifest/staging/download/query 及 Release 开发入口/元数据隔离全部通过。Debug 14.115 秒、严格签名成功且全源零漂移。本项是同值解析减工，不宣称可见首帧提速。

## 当前裁决与停止项

TEX 已做实际 Reader→Metal 全字节资格：10 案例、28 消费者、200 层通过。常见 padding 尾仅 4B/22,369,620B，当前 owned 作者样本 0B；极端人工例 87,380B≈25%，仍无真实 occurrence。当前撤回常驻 purpose-cache/第二 Reader 改造；未来真实输入出现显著绝对尾字节及实际热点，再在原数据流裁决。请求 subdata 范围不等于物理 memcpy/RSS 或墙钟提速。

P21 整体冷暖计时未通过原噪声/漂移标准，继续保留失败原值，不报告稳定累计提速。局部方法/字节减少已验证，不据此折算 App 首帧百分比。完整官方 parity、跨屏首次字体共享、字体内存指标和 P25 两个前台卡片模式是各自能力/测量边界，没有当前具体风险时不升级为本专项硬门。

旧 `test_scene_particle_simulator.py` 4541 行属已知测试结构债，不是播放回归或精简收益；不为缩行数引入 wrapper/碎片编译。P18 自有 MPEG4 夹具的绿 JPEG 旧/新同现，唯一复现仍保留，不把它默默归为本次引入或已修复。已确认无消费者的测试退休残留可直接退出，原有实际断言和其它字段保留。

## 完成范围、证据与交接

Scene/Web 八范围及邻接 Video、音频、图库、存储、获取、发布、支持和工具已沿实际消费者复查；所有已证同类项已修正或依据实际消费/成本撤回。最后的登录未用载荷、作者工具 PKG 前置许可/marker、归档重复读取与协议重复解析均完成最近门和独立审查。必要的解析/读边界、账号/异步身份、真正提交/释放及发布签名继续保留。没有尚未处理的已证同类修正项；普通兼容缺口与未来新发现由后续维护处理，不宣称没有任何 bug。

P29 当前 App 的 Scene→Video→Scene、两作者 Web 提交、用户确认的真实音乐响应及分步暂停/继续、普通退出已完成。后续 P30–P35 未启动或退出 App，未重做无影响的 OS/长运行；P33/P35 只运行隔离离线夹具和 Debug，没有真实账号登录或 Keychain 操作。全部编译/native/AV 队列按明确交接串行执行，最后窗口已归还 UI 会话。正式偏好、用户媒体和其他会话进程未在本批修改。

本机 P23–P35 结果入口在任务目录 `d41-playback-validation/p23` 至 `p35` 的 `final-validation.json`，含原始失败、源身份、独审、行为及前后工作量对照。P29 另有实际运行/偏好恢复记录，P31/P32 保完整两臂对照；P33–P35 保旧新载荷、工具输出/读取次数及协议边界。最后逐要求完成审计为 `p35/completion-audit.json`。P21 噪声计时仍不作为稳定整体提速证据。

本轮 6 份临时测试环境和唯一约 3 GiB DerivedData 已核无进程/句柄后清理，构建身份和日志保留；旧批次已登记证据、未知归属与唯一未解决复现保持。P23–P35 按当前授权作为第一棒合入主仓；后两棒分别接入 UI 和新模块，重叠只保单一消费链。最新两段轻快链路原话纳入顶层规则，其余约束保留。主仓与编译窗口逐棒明确交接；最终组合由后续整合门验证，不把各分支独立通过当作组合通过。

## 文档职责与归档决策

本页继续是现役范围、顺序、完成条件的唯一权威；原设计、完整实施步骤、失败和历史时点原文保在同一份历史记录，唯一转换是相对链接随位置调整，全部原锚点保留或永久转接。历史里的“当前/下一步/暂停”不决定今天的任务。当前覆盖表只维护一次，稳定机制由原合同拥有，完成判定绑定逐要求审计和当前源码；三会话整合期间保留本页作为交接入口。规则、生成记忆和其它工作树不在此次文档迁移中重写。

## 历史锚点

<a id="mdl-一次读取与解析"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#mdl-一次读取与解析) <!-- archive-redirect -->
<a id="p10同次来源查询与无消费者工作最近回归与-debug-已过"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p10同次来源查询与无消费者工作最近回归与-debug-已过) <!-- archive-redirect -->
<a id="p11同次-shader-指针计算复用与纯诊断剥离回归成本与-debug-已过"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p11同次-shader-指针计算复用与纯诊断剥离回归成本与-debug-已过) <!-- archive-redirect -->
<a id="p12粒子纯运行诊断与无生产者载荷退役必要回归及双配置-app-已过"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p12粒子纯运行诊断与无生产者载荷退役必要回归及双配置-app-已过) <!-- archive-redirect -->
<a id="p13高频字符串顶点与出生固定工作的直接复用必要回归成本与-debug-已过"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p13高频字符串顶点与出生固定工作的直接复用必要回归成本与-debug-已过) <!-- archive-redirect -->
<a id="p14模型上传与资源路径回归原-owner回归对照与-debug-已过"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p14模型上传与资源路径回归原-owner回归对照与-debug-已过) <!-- archive-redirect -->
<a id="p15同次-shader-归一化结果直接交给编译器回归对照与-debug-已过"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p15同次-shader-归一化结果直接交给编译器回归对照与-debug-已过) <!-- archive-redirect -->
<a id="p16音频与媒体纯诊断工作归实际调试消费者双配置回归对照与-debug-已过"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p16音频与媒体纯诊断工作归实际调试消费者双配置回归对照与-debug-已过) <!-- archive-redirect -->
<a id="p17video-首启按需准备与诊断-ipc-退出-release回归减工对照与-debug-已过"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p17video-首启按需准备与诊断-ipc-退出-release回归减工对照与-debug-已过) <!-- archive-redirect -->
<a id="p18完成帧直达频谱分析按需频带与请求内缓存键复用回归对照与-debug-已过"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p18完成帧直达频谱分析按需频带与请求内缓存键复用回归对照与-debug-已过) <!-- archive-redirect -->
<a id="p19旧库发现按需短路模型材料准备单次索引与-video-首播重复工作退役回归减工对照与-debug-已过"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p19旧库发现按需短路模型材料准备单次索引与-video-首播重复工作退役回归减工对照与-debug-已过) <!-- archive-redirect -->
<a id="p20-mdl-policy-retirement"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p20-mdl-policy-retirement) <!-- archive-redirect -->
<a id="p20退役-mdl-部件数与路径长度政策保真实资源边界cpu材料gpu前后对照与-debug-已过"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p20退役-mdl-部件数与路径长度政策保真实资源边界cpu材料gpu前后对照与-debug-已过) <!-- archive-redirect -->
<a id="p21-app-startup-verification"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p21-app-startup-verification) <!-- archive-redirect -->
<a id="p21当前-app-实际播放与冷暖对照功能通过未接受稳定提速"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p21当前-app-实际播放与冷暖对照功能通过未接受稳定提速) <!-- archive-redirect -->
<a id="p22-host-row-and-video-request-work"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p22-host-row-and-video-request-work) <!-- archive-redirect -->
<a id="p22宿主仅准备实际依赖事实video-同请求直接复用验证完成goal-暂停交接"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p22宿主仅准备实际依赖事实video-同请求直接复用验证完成goal-暂停交接) <!-- archive-redirect -->
<a id="p23-asset-path-publication"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p23-asset-path-publication) <!-- archive-redirect -->
<a id="p23派生路径只在实际变化时发布已验证未提交"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p23派生路径只在实际变化时发布已验证未提交) <!-- archive-redirect -->
<a id="p24-import-request-work"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p24-import-request-work) <!-- archive-redirect -->
<a id="p24导入只准备实际消费者需要的路径与缓存键已验证未提交"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p24导入只准备实际消费者需要的路径与缓存键已验证未提交) <!-- archive-redirect -->
<a id="p25-shared-thumbnail-work"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p25-shared-thumbnail-work) <!-- archive-redirect -->
<a id="p25共享缩略图只算一次磁盘定位sil-预览直接消费回调已验证未提交"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p25共享缩略图只算一次磁盘定位sil-预览直接消费回调已验证未提交) <!-- archive-redirect -->
<a id="p26-import-owner-work"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p26-import-owner-work) <!-- archive-redirect -->
<a id="p26导入只发布实际变化旧选文件入口退役已验证未提交"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p26导入只发布实际变化旧选文件入口退役已验证未提交) <!-- archive-redirect -->
<a id="p27-current-engine-closure"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p27-current-engine-closure) <!-- archive-redirect -->
<a id="p27当前引擎验收与可选缓存写入减工已验证未提交"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p27当前引擎验收与可选缓存写入减工已验证未提交) <!-- archive-redirect -->
<a id="p3-实现只复用实际已经准备的值"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p3-实现只复用实际已经准备的值) <!-- archive-redirect -->
<a id="p4-普通模拟帧的固定事实cpu-已过clipping-可见门待验"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p4-普通模拟帧的固定事实cpu-已过clipping-可见门待验) <!-- archive-redirect -->
<a id="p4-设计资源按实际消费者读取最近行为门已过"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p4-设计资源按实际消费者读取最近行为门已过) <!-- archive-redirect -->
<a id="p5-最近验证结果"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p5-最近验证结果) <!-- archive-redirect -->
<a id="p6-最近验证结果"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p6-最近验证结果) <!-- archive-redirect -->
<a id="p7-合并构建结果与剩余验收"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p7-合并构建结果与剩余验收) <!-- archive-redirect -->
<a id="p7-最近验证结果"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p7-最近验证结果) <!-- archive-redirect -->
<a id="p7下载与旧目录迁移直接消费当前结果"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p7下载与旧目录迁移直接消费当前结果) <!-- archive-redirect -->
<a id="p8兼容命名空间的局部失败与单一读取链旧链已退役最近资源门与成本已验"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p8兼容命名空间的局部失败与单一读取链旧链已退役最近资源门与成本已验) <!-- archive-redirect -->
<a id="p9越界表项局部不挂载文件入口跳过裸包目录坏条目loose-与字体最近门已验"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#p9越界表项局部不挂载文件入口跳过裸包目录坏条目loose-与字体最近门已验) <!-- archive-redirect -->
<a id="全仓后继video-首播与共享音频"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#全仓后继video-首播与共享音频) <!-- archive-redirect -->
<a id="全仓后继事件分片与重复桥接"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#全仓后继事件分片与重复桥接) <!-- archive-redirect -->
<a id="全仓后继卡片投影与实际目标分离"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#全仓后继卡片投影与实际目标分离) <!-- archive-redirect -->
<a id="后继候选与实施边界"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#后继候选与实施边界) <!-- archive-redirect -->
<a id="后继只读发现与覆盖边界"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#后继只读发现与覆盖边界) <!-- archive-redirect -->
<a id="已实施不可变准备事实与实际动态检查分离"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#已实施不可变准备事实与实际动态检查分离) <!-- archive-redirect -->
<a id="已实施已完成视频文件的来源确认归请求入口"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#已实施已完成视频文件的来源确认归请求入口) <!-- archive-redirect -->
<a id="已实施纹理-snapshot-完成后不重查作者文件"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#已实施纹理-snapshot-完成后不重查作者文件) <!-- archive-redirect -->
<a id="已证问题与裁决"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#已证问题与裁决) <!-- archive-redirect -->
<a id="当前验证边界2026-10-26"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#当前验证边界2026-10-26) <!-- archive-redirect -->
<a id="本批合入与暂停边界2026-10-26"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#本批合入与暂停边界2026-10-26) <!-- archive-redirect -->
<a id="编译准备减工"></a> [归档记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md#编译准备减工) <!-- archive-redirect -->
