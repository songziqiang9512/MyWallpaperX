# 全仓校验与链路精简

<!-- document-role: active-plan -->

目标：先全面审查 Scene、Web 的启动、资源、纹理、shader、渲染、特效、普通帧、缓存、IPC 和生命周期，再扩到 Video、音频、获取、图库、存储和工具。主动删除对实际功能无帮助的校验、认证、重复计算和嵌套，使链路直接、按需、轻快。用户原话与必要边界由顶层 [AGENTS.md](../../AGENTS.md)约束；不能拿旧实现、旧测试或“更严谨”反向保留无用工作。

状态：P0–P35 与三会话整合已有当时结算；本工作树从 `99ba1fa85` 续查的 P36–P43 实现、范围审查与必要验证完成，用户现已授权提交并合入 `codex/engine-refactor-program`，Git交接结果以实际分支和本轮回执为准；不推送。当前 Scene/Web 25 职责域、168 个产品路径已复核；P42 三个后继候选已在 P43 处理，没有新增有依据的待修同类项。最终 Goal 状态和产物去留以本批逐项审计/收尾回执为准，不自动续开旧候选或为假设风险增加关卡。顶层规则沿用原 owner 内替换、同批退役、最小跨层数据及产品/测试/文档分开核算。P0–P27 原方案与过程见[历史记录](../history/cross-topic/validation-simplification-p0-p27-2026-10-27.md)。

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

<a id="p36-engine-consumer-review"></a>

## P36：基于整合版本继续按实际消费者减工，已验证未提交

本批沿 Scene 的资源/纹理/模型/字体/媒体、shader/Program/graph/特效、普通帧/输出和生命周期，以及 Web 属性/授权、宿主/IPC/桥、DOM/媒体/帧和缓存复查实际消费者。已证项目沿原 owner 完成替换；三路交叉审查没有遗留未处理的本批同类发现，不把历史全仓结项或少量视觉结果冒称永久无缺陷。

Scene 帧/分配：退役 PreparedPass 仅供测试读取的 slots/sampling/字节数镜像及生成；同次 Lease 物理纹理枚举 3→1；显式材质函数调用不重建已编译确定的两份目标 Set，不为单 key 过滤整个 allocation。原 texture 查询已证明真实资源存在；精确函数查找已拒绝未注册名，不重复修剪编译期限制的名称。脚本 fallback 同一目标 Set 构造 2→1；每层 DrawRequest 的无人消费帧载荷及日历计算 1→0，实际 surface uniform 消费不变；native camera 沿逆序按需查找，先选 camera 再检查真实可见性。真实 sampler/uniform、目标/texture、epoch/device/hazard、提交与释放继续由原消费者维护。

Web：正常属性投影不提前构造未用备用 JSON，同次 value/binding 直接共用，不为只取类型而重解路径/书签。初始夹具 binding 入口 6→4、备用序列化 1→0；预览/提交各 4→3，完整属性 JSON 相同，独立授权请求仍取得当前事实。取消按 URL 名称/后缀拒媒体；换源清除旧失败标记，迟到 A 失败不能暂停或清除 B。追加 `<source>` 后立即 `play()` 时，空 currentSrc 只代表浏览器尚未选源；删除该提前返回，让原生完成选择或报告无源失败，不复制选源算法。真实值清空、当前实际失败、作者暂停、授权根、FD 与请求边界保留。

Scene 源：Puppet 沿原 author VFS 选实际资源，包缺目标可读有效 loose，已选坏包仍不改选，stock 不冒充作者 mesh；有效入根路径不受额外拼写政策阻拦。退役 shader 相对资源的 Windows drive 名称政策，保实际入根/范围/取消。R1 完整 contract 留在原层；向 R2 仅传同次既有 ResolvedFile 快照与 Handle，最多两个根 stage，不再传完整 Stage。R2 独立选根，只有 Root 对象相同且实际 Handle 路径 UTF8 精确相同时复用已读源、SHA、字节数和 includes；原 vertex-first、预算、选中坏源、图闭包与取消不变，不新增跨合同缓存或 owner。

同输入、同 `-O/WMO` 的 11 组 shader 完整 contract/graph JSON 一致：普通/PKG 两 stage 的原读与 parser 入口各 4→2，混合根 4→3，共用 include 5→3；大小写不同仍 4→4。本机 Unicode 外部拼写不同但实际 Handle 命中精确条件，4→2；不得据输入拼写推断 Handle 不同或放宽 UTF8 比较。数字是原方法/表达式入口，不是 syscall、物理 I/O、CPU、RSS 或 App 首帧提速。

最近 65 个 Swift/原生行为方法、3 个 Node 方法及 4 个结构/真实文档链接方法零跳过通过，包含实际 GPU 像素、四种采样、clear/lease、Puppet、脚本 VM、授权/FD 和 WK。额外实际 WK 代表证明：fresh source 未先 load 的输入，删除前卡住，删除后 readyState/播放时间推进；合法 null/index.html 名称、换源及迟到失败也通过。它使用静音 WAV 和受控失败通知，不代表真实系统音频或全作者视觉普查。最后 4 个原 WK 方法随删除空门复跑通过。Debug 整 App 70.093 秒成功，6215 文件冻结快照零漂移，未启动产品 App或改用户偏好；现有 UI 两处 SourceFacts actor 诊断及 callback facts 的 Equatable 隔离诊断如实保留，不冒称零警告。

产品 20 文件 +169/−211，净减 42 行；测试 9 文件净增 397 行，其中旧 camera Swift harness 从 Python 完整迁出为 756 行夹具，原 27 方法保留并补父层可见性等行为反例。净增长来自回归证据，不能当产品精简收益。首次测试变量重名、fixture Source 枚举误写、任务空 PKG 和 Unicode 错误计数预期的原失败记录保留，修测试装配/预期不放宽产品结果；旧镜像 API/生成链同批退役。最终日志、身份、独审及前后原值按产物规则提取，构建缓存和临时运行环境当轮清理。


<a id="p37-direct-consumption"></a>

## P37：固定事实直接消费与媒体委托，已验证未提交

长期 Goal 继续检查 Scene/Web 全链路，P36 原改动保持未提交。当前沿原 owner 处理：FBO publication 直接查唯一分配资源，不每次过滤全表及重建 token 唯一性 Set；媒体暖借用只取得请求 weak entry，不为单 key 扫全表并强持无关输出；MDL 同进程 Loader/GraphBuilder 已构造的不可变图不在 defaultAlbedo/compile 两消费者重新序列化摘要、哈希所有节点。真正动态 token/version/texture/descriptor/lease、选中输出 revision、独立 source 一致性、声明/宏/条件/歧义和读取预算保留。Scene IPC 输入是 root/source/overrides，不把 Codable 声明误当实际 decoded graph 入口。

粒子发射的同批角度先完成原 authored/dynamic/instance 选择与规范化，在现有 emitter Frame 内准备 sine/cosine，供 origin、每粒子 position/velocity 共用；替换旧 angles 载荷，不新增缓存或 owner。无 control point 使用原 sin(0)/cos(0) 常量；原 Double、XYZ 运算和乘加顺序不变，不做零角直接返回或 Float 窄化。每次发射重新建 Frame，不冻结下一批动态角度；实际入口计数与同输入完整输出比较区分源码工作和硬件调用。

Web 退出 DCL 第二层播放 URL 许可与删除空 source 节点的全树扫描，保作者 play/pause 意图，交原生选源；作者保留的空节点可在 DCL 后正常赋值。退役父端只空消费的 prepared/committed 两消息、DTO 和空分支；真实 cohort、activationConfirmed、visibility/ACK 和取消退出不变。双方每次从同 Bundle 启动独立 pipe，不引入旧子进程迁移层。两 play wrapper 合并候选撤回：DCL 层承接解析期作者重写的方法，直接移到 document-start 会改变行为。

原 publication、sound、MDL bindings、particle simulator/transaction、Web parity 和 switch endpoint 共 37 个原生方法零跳过通过；另原 Node 三方法与结构/真实文档链接四方法通过。实际 Metal/AV/WK/端点涵盖真实分配 alias、unknown token/descriptor/storage、选中文件变化/取消/最后借用退出、动态角度/暂停/rollback、作者晚赋空 source、可见 ACK/取消退出。旧 MediaObservers 在同新 WK 场景编译成功而运行失败“DCL must preserve the author's empty source node/reference”，候选保持节点并实际播放推进。独审无阻塞；Debug 72.116 秒成功，6217 文件冻结快照零漂移，未启动用户 App或改偏好，既有 actor 诊断不冒称修复。

同编译选项和完整源闭包的两臂对照：MDL 六组完整 contract 输入及 default→bindings 输出相同，普通图重复序列化 2→0、Data 摘要入口 4→0，include 图为 2→0、6→0；explicit/no-default 按实际路径如实计数，不冒称所有 case 都同次数。粒子原完整 default/periodic-overrides/birth-scalar-safety/simulation-rate 与新增含±0/非零XYZ、64+64 出生、动态换批、restore重试及 RNG/ID 的组逐位一致；default sin/cos 表达式入口各 61,683→81，新小组各 1,161→9。原 formal XYZ oracle 已随 API迁移，只对其计数对称排除，计算/输出保留。数字是原表达式/构造入口，不能换算 libm 物理调用、CPU/RSS 或 App 冷暖首帧收益。MDL任务 observer 最初 private 跨文件不可见，修任务声明后 v2 通过，失败原值保留，未改产品结果。

本批产品九文件 +14/−60，净减46行；测试十文件净增92行，含两个完整旧HARNESS自然迁出，全部原真实断言保留。旧手拼非法 lease 的 alias 反例迁到真正 Lease.make；固定 metadata 的拒绝镜像改测相同内容结果，真实 source 错配仍拒。旧4541行 simulator 测试只改四行 oracle、长度未增长，不为缩行数拆碎或保旧 wrapper。观察字段/重复认证/旧 IPC DTO和空消费者同批退役；任务计数不进入产品，产物按有界结果提取。history 同代快路、Release 仅诊断 program keys 等后继候选继续只读核实，长期 Goal 保持 active，不把这一批通过冒称全链路完成。


<a id="p38-prepared-graph-fast-path"></a>

## P38：历史快路与 Release 观察镜像退役，已验证未提交

同次 history preparation 只投影一次 readable mapping、验证一次当前 publication/纹理/内容/采样；同 allocation generation 且 copies 为空时在 descriptor 字典与 key Set 投影前沿原快路返回。把只服务该函数的两层重复验证合回原 owner，保 nil allocation/reset/readable-empty 的原行为；唯一字典的资源 key 覆盖可直接用 count 与实际 lookup 证明，不额外建 Set。改代 copy 只补 sourceTexture 实对象绑定，不再次认证已完成的同次资源事实；源 token 的精确集合与数量已经保证唯一性，不重复构造同 Set。State.reduce 仍在 encode 前拒同代不同 authoredResources，改代、resize/reset、copy/rehydrate、失败回滚与提交边界保持。仅把已经存在的快路移到无用计算前，不新增 stamp、缓存、状态或 owner；手拼非法同代 allocation 可在原 State 阶段拒绝，不为固定内部失败阶段保重复证明。

PreparedStage 的 programKeys 数组只供 Debug graph observation，普通 Release 却仍生成、传递、回滚与计数。沿原五个 owner 整链退役数组、inout、snapshot计数、fallback key 拼接和材料数镜像；保真实命令、PSO cache key、target/publication、终态与 rollback。Debug 由现 PreparedPass 仅保实际 key、沿现 commands 与原 fallback reason按需投影，观察端局部复用一次；不保 Release 空载荷，不复制 preparation 函数，不增长期状态或 owner。Debug 顺序/摘要和全部 fallback 原值保留，实编 Release 与实际执行门共同证明剥离，不能只靠源文本或链接 stripping。

结果：历史/State/Graph/资源恢复/失败 allowlist/诊断 subject 九个最近方法、实际 Debug/Release 隔离一个方法零跳过通过；结构/真实文档链接四方法及源码/依赖/防御/设计门通过。两配置都不定义 SCENE_GRAPH_TESTING，Release 不定义 DEBUG；实际 GPU 像素、原历史回滚/恢复、当前资源损坏、reset→stalePreparation 与终态不提交断言保留。实际 Debug observation 构造和 program 序列摘要通过；原始未优化 SIL 确认 Release 无 Program key 诊断字段/投影/sentinel，不能归功于链接剥离。独审无阻塞，Debug 整 App 71.587 秒成功，6217 文件冻结快照零漂移；既有 actor 诊断如实保留。

同输入六文件两臂的六次完整 2×2 GPU readback、14 项失败结果、六组正常/fallback/恢复 key 序列完全一致。同代恢复的 readable 筛选 2→1，两份 descriptor 投影各1→0；阶段总 FBO getter 3→2，不能宣称所有 getter 消失。跨代重灌的完整资源验证 2→1、readable 筛选 4→1，复制源实对象检查保留。数字是实际表达式/方法入口，不是分配量、FPS、libm 或 App 冷暖首帧耗时。两臂包含原 Program key 数组和新投影，避免只用新值验证自身。

产品六文件 +84/−127，净减43行；测试三文件净增218行，原大夹具未扩张。首次独立编译缺 Observation 所需的既有 Telemetry 扩展；补齐清单后，Debug 合法 stdout 日志又暴露测试 JSON 未分帧。两次修正仅改测试依赖与结果标记/解析，不改产品或放宽 GPU/元数据结果，原失败均保留。任务两臂脚本补仓库 import 路径及同依赖，临时计数不进入产品。P36/P37 改动保留，全部未暂存/未提交；长期 Goal 保持 active，材质 raw SHA 的 Debug-only 归属等后继继续核实。一份连续构建缓存供下一批增量验证；其余临时编译/运行环境当轮清理，结果限量保留。

<a id="p39-material-metadata-and-web-request-work"></a>

## P39：材质诊断摘要退出 Release，Web 请求直接复用，已验证未提交

MaterialAsset.rawSHA256 只经 MaterialPassDescriptor.materialRawSHA256 进入 Debug RuntimeEvidence/离线 census，实际播放不读取。沿现 loader/descriptor 原 owner 的四个 DEBUG 块退出 Release 原字节 SHA/hex、两处字段及逐 pass 投影；Debug 仍立即对同次已选 data 计算原摘要，未保整份 bytes、空载荷、额外缓存、flag 或新 owner。新增九行编译隔离用于保留真实 Debug 取证能力；实际 XRay 消费的 shaderPathIndependentSHA256 函数原字节、字段和投影均保持。Release 每个已加载材质少一次原始 SHA，原读取/解析和语义 hash 并未减少。

Web 同次 resolve 在原函数内只解码一次请求路径，cache key 和冷解析共用该局部值，唯一无外部消费者的 resolveCacheKey helper 同批退出。冷 miss/显式刷新解码 2→1、暖命中 1→1；loopback 404 的可选媒体分类只有 Debug 日志消费者，整段归 DEBUG，Release 分类 1→0、Debug 1→1，sendError 原样。数字由实际源调用链确定，不是计时或物理 IO 测量。精确 URL 解码、缓存键字节、授权根变更、实际 FD/range/metadata、symlink/escape、取消/旧代次、404/416 与停止后的迟到完成边界继续由原 consumer 维护。

最近 18 个原生方法及 3 个 census 输入/采样边界方法零跳过通过；结构/文档链接四方法与代码/依赖/防御/设计门通过。新增隔离门复用原真实受管发布、ResourceView/Catalog/Facts/Descriptor/Model：同一包/loose 冲突输入在 Debug 保精确选包 SHA，Release 的实际 Mirror 和 JSON 都无 raw 字段；剔除明确的 Debug 观察字段后，完整播放投影一致。两配置原始未优化 SIL 的实际 loadMaterial 直接 HashFunction.hash 调用 1→0，原语义 hash 调用保留，不依赖优化或链接 stripping。原 loader 六项 render-state/hash 断言保在 Debug；现有包/目录、当前修改、取消和旧包门保持。整 App Debug 24.943 秒成功，6212 项 Git 可见源码冻结零漂移；沿用唯一连续缓存，构建耗时不作壁纸性能。

离线 census 的 owned-graph 端到端方法未通过：未改的工具源清单漏 ResourceView.PackageBacking 所在源，另有既有 resource.url/旧提取命名空间漂移；该脚本和 ResourceView 均与本批开始 SHA 相同。原始失败保留，不计通过，不声称 census 端到端能力。本批不把无关工具修复扩大为播放重构；严格摘要输入合同未改，受影响的实际 Debug/Release 元数据另由真实 owner 门证明。后续按具体工具任务处理这一旧债。

产品五文件 +24/−27，净减3行；测试三文件 +136/−9，净增127行。首次新 Debug 装配缺未执行的 Bloom GPU timestamp 外部叶，以误调用即 fatalError 的已有夹具叶界补齐；随后 SIL 预期将协议 HashFunction.hash 误写为 SHA256.hash，只修测试符号名和失败前证据保存，产品未变。独审补获并修正可选 predecessor 比较的局部变量遗漏；仅退休原 raw 诊断投影，完整播放字段继续比较。两次原生失败及原有工具失败均保原值；源码/测试/文档全部未暂存未提交，P36–P38 保留。Goal active，三处 graph 固定镜像/局部复用与 Web cache 活命中前整表过滤等后继候选仍待实施；不把本批通过当全范围完成。

<a id="p40-immutable-facts-and-cache-publication"></a>

## P40：固定事实只在生产处接受一次，缓存删除保持一个提交点，已验证未提交

Graph 沿原 Lease.make→State.prepareExecution/compile/reduce 的唯一有效生产链，退出 preparation 的 visited/末尾整图 Set、material/copy/swap 的重复静态 kind/ordinal/target/pair 谓词及末尾固定 FBO count 扫描。失去消费者的 commandOrdinalsByNode 字段、构造和静态自检同批退役；materialTarget/validateCommand 只留实际消费参数与动态事实，不保空 wrapper。保 lookup、当前 pair/member、bindings/publication/content/texture/device、真实 copy/swap、function、history、失败 rollback 与 encode/commit 边界；缺失/多余 allocation 在原 prepared/raw reducer 都拒绝，不为固定内部失败位置保第二重证明。改代 history 共用一次同 lease 的局部 FBO resources，逻辑 key 与物理 token 两种 descriptor map 各保原用途，不加持久缓存/owner。

Catalog 模型的唯一生产者已在 enqueue 对实际 Handle 路径去重、loadModel 原样保存路径，descriptor 不再建 Set 重证同一模型集合唯一；作者 objects 的独立 ID 检查保留。EffectDefinition 的原字节 SHA 没有播放、IPC、图/持久缓存身份消费者，连同 import、字段、现 ctor 参数与 loader 计算完整退出所有配置，未添 DEBUG 分支/空值/兼容 ctor。保原解析字段、unknown extras、conditions/functions/gizmos/FBO 与旧额外 raw 键的既有 Decoder 忽略语义；Debug 整体证据 JSON/inputSHA 会如实变化，不能宣称证据字节不变或给它另做迁移许可。

Web publication 活 slot 命中先返回，miss 新增前仍清死 key。同步 service 删除原先在同一 MainActor 栈先 invalidate、再同 key invalidate+unlink；现直接清 memo，只在最终原 Slot lock 内一次撤权并删双文件，唯一旧 helper 同批退出。旧 writer 先得锁可完成后被删，删除先得锁则旧 ticket CAS 不得 rename；publish Bool 无产品回调/结果消费者，不增 stamp/锁/owner。stock 索引同时退休把合法 macOS 相对文件 C:/valid.tex 当 Windows drive 的政策；保真路径边界、尺寸、重复、locale、symlink 和损坏侧车 miss→枚举。侧车 SHA 有防坏但可解析的 namespace 隐藏真实资源的功能，明确保留；不是作者播放许可。

最近 52 个原生方法零跳过通过：State13、实际 Graph GPU2、effect5/planner16、catalog8、包输入3、stock namespace4、Web缓存1。实际三种 effect 原 loader/Codable 全字段输出，仅从 before 移除顶层 rawSHA256 后与 after 深等，原 raw hash 另记且确实不同；完整 before service 也通过相同最终断言。两臂原 history HARNESS 各实际执行，六次完整 2×2 GPU readback、14 项历史失败、六组实际 Program key 序列和原布尔投影全同。实际同代恢复 FBO getter/filter 2→1、跨代 rollback 5→3；该同代帧 visited 构造1→0、插入3→0、整图 Set/比较1→0。实际 Web slot 十二阶段的活命中/撤权 filter 1→0，500 次新 key miss 清理仍 500→500，全部行为/弱引用与死 key 有界断言保持。这些是实际方法/表达式次数，不是分配量、CPU、IO、FPS 或 App 冷暖首帧耗时。

代码/依赖/防御/设计与结构/文档四方法通过，静态两路交叉审查无未解决阻塞；最终独审绑定原始结果。整 App Debug 57.713 秒成功，6212 项 Git 可见源码冻结零漂移，沿用原唯一增量缓存。首次任务 probe 的公共源码副本早于最后 stock 修改，冻结检查在 native 启动前拒绝；保 v1 原值，另建 v2 当前快照后两臂一次通过，未改产品或重跑已过52方法。独审发现 invalid policy 表退休后的旧案例数未同步，静态期仅15→14，未冒称一次运行失败。既有离线 census 装配/API债仍单独保护，不计本批通过或修复；未启动产品 App、未改正式偏好或用户媒体，UI16 空闲验收窗口原样保留，编译/native窗口已交回。

产品八文件 +17/−93，净减76行，P36–P40累计净减210行；测试四文件 +89/−17，净增72行，没有新增产品 owner/状态链。全部未暂存未提交，P36–P39 保留；长期 Goal active。P41 的 registry/局部模型索引后继与 JSON 删除候选的实测撤回见下节；不以本批通过当全范围完成。

<a id="p41-key-order-and-minimal-metadata"></a>
## P41：排序缓存与模型索引直接消费，必要 JSON 防崩溃边界保留

原 registry 的六份排序缓存每次先构造 Set，再确认与上帧相同；现在原 cache 直接消费 Dictionary.Keys，只在 key 集合改变时更新原 Set/排序数组，不增加 owner、字段或持久状态。bare property 保原顺序，typed color 的本帧排除放实际发布循环；typed pending/absent/ready、同数量换 key、插入顺序变化与 reset 都走原快照。原 native/overlay 两臂的 8+17 份实际完整快照深等；同九帧 Set 构造 54→6、差集 9→0、排序 8→6，纯暖帧该六份 Set 构造 6→0。typed color 独立集合仍有真实消费者，未计作删除。

模型准备原先为同一组 model 分别建 crop/size/puppet 三份路径索引，现合为原函数内一份最小 tuple；同层沿原 puppet 查询位置取得一次 metadata，size 显式优先、nil/缺失与作者顺序不变，attachment map 保自己的独立用途。两次实际完整 Facts/catalog/descriptor 输出深等，32 层/24 模型/13 材质下索引构造 6→2、查询 186→62；包括缺失/空字段、全部可选 metadata 组合、未知材质字段与非有限数。材质 validity 与 semantic SHA 实计均 13→13。

Web 媒体端点不再先取完整 Array 再逐项比对象，直接用原 registry 的 token→对象身份查询；原 request/screen/lease 与异步代次保持。网络回包只去掉固定生产域的重复 JSON 扫描：七个实际调用只写 Bool/Int/String 和 String header，远程 body 先 base64 成 String；不把任意 Any 或解析所得 JSON 当作同一安全域。surface 的原 DEBUG 界移到整个延迟诊断回调之外，Release 不再安排一秒后的空回调，Debug 原诊断保留，关闭/释放路径不变。相同六种真实 WK 场景每臂均通过，完整 general 输出深等，三次完整网络回包断言保持；实际媒体身份查询 121 次中的 Array 构造/线性查询 121→0，改用原索引；网络回包 validity 3→0。

JSON 删除试验中捕获并修正真实候选回归：Foundation 写 NaN 会抛出 Swift try? 无法捕获的 NSException，本机 decoder 还接受 -1e309 为 -inf。因此属性/元数据三处、general、merge 与 private material 共六处原 validity 检查全部精确恢复 P41 前字节；它们直接防崩溃并维持 nil/最小属性/原 JSON 字节/空 SHA 回退，不能算无用认证。新增原生负例已通过；保留失败原值和静态独审撤回说明，没有另加有限数 wrapper、修复状态或第二编码链。

分阶段最近 49 个方法零跳过通过（48 个原生行为、1 个既有源码结构检查；修正后 Web 九方法重跑，Scene 以最终完整双臂输入及 Debug 再绑定），涵盖 registry、overlay、material loader/catalog、实际包输入、Puppet、Web 作者准备/合并/六种真实 WK 媒体与音频端点。两份旧 solid/world 独立夹具在 setup 编译失败，不计通过；solid 另以全部 P41 前输入实编译复现相同缺类型错误，world 七输入全与 P41 前一致。当前改动另经完整实际 source closure 的 descriptor 前后投影与适用 Debug，构建 22.959 秒且 6212 项源码零漂移；该构建时间不是播放提速。所有工作量对照都是入口/表达式次数，不冒充 CPU、物理 IO、内存、FPS 或 App 首帧收益。未启动产品 App、未改偏好/用户媒体，UI16 验收进程保留。

本批产品五文件 +27/−31，净减4行；测试六文件 +229/−20，净增209行，没有新增产品文件、owner 或状态。测试增长覆盖已抓到的真实异常、完整输出及动态键/端点失效反例，不以行数抵消产品复杂度。P36–P41 产品累计净减214行；全部未暂存未提交，长期 Goal active，后继只处理有实际消费与成本依据的发现，不重开已撤回的 JSON 删除或已记旧夹具债。

<a id="p42-material-uniqueness-and-web-fallback"></a>
## P42：材质唯一事实直接消费，Web 类型已知时不再重读备用分类

材质只由原 Catalog loader 创建，实际 Handle 经相同 slash+localizedLowercase identity 去重后只 append 一次；Descriptor 同步消费不可变数组，不从 IPC/缓存解码第二份 Catalog。因此删除 materialPassDescriptors 整批分组、count==1 与无实际生产者的 material-pass-ambiguous 分支；原 defaultAlbedo/绑定编译与取消调用保持，路径转换只在 pass0 的实际资格判断消费。使用额外 trim 的 sourceMaterials/sourceModels 歧义域不同，其真实检查保留；未添加 owner、状态、许可或新算法。

原 PackageSourceInput 方法增加 aliases/空白区别文件/无 MDL 图片三组真实输入，经 MDL→VFS→Catalog→Facts/ModelBuilder 跑原完整描述输出。两臂每组两次准备全字段深等：整批分组 2→0，group 行 2/4/2→0，路径转换 4/8/4→2/4/2，唯一性查询 2/4/0→0；实际 fixture 编译入口 2/4/0 均不变，多 pass 顺序及仅 pass0 绑定保持。该原 fixture 的 shader 叶是 unavailable stub，真实 shader/defaultAlbedo/歧义/条件编译语义另由原编译器 11 方法验证，不以 stub 声称真实 shader 或像素结果。

Web resolvedWebResourceBinding 不再先无条件计算 pathlike fallback 再由 file/directory 覆盖类型；原表达式直接归入 fallback else-if。依赖项目、无 bindingContext 的 file/directory/bookmark/selection 四例，直接绑定阶段的实际 project URL→Data 读尝试各 1→0；text/unknown/pathlike/preset 五例保持 1→1，两个 prepared-context 例保持 0→0。相同 11 输入的完整 Codable binding、实际 payload JSON 和 grants 深等，原书签精确文件/邻居越权、根顺序及权限/代次边界保留。外围 payload/grants 若有自己需要的读取仍在，不把直接绑定减工说成整条链零读取。

Debug ResourceReferenceIndex 不再把 raw Set 映射回 Array 后做最多五级线性匹配；原函数将 lazy normalized 名字保在一个局部 Set，仍用原五级优先序返回 normalized candidate。两臂原完整匹配/缺失/运行时引用结果全同，实际 membership 72 次从 Array 路径改用 Set；Release 分支逐字节不变，没有 Release、CPU、分配量或帧率收益声明。

分阶段 32 个原生最近方法零跳过通过：Scene 29（Catalog8、真实材质编译11、实际包输入4、模型依赖2、引用索引4）及修正夹具后的 Web3（缓存/绑定1、实际权限与异步撤权2）。三路实际前后对照通过，Debug 22.202 秒成功，6212 源输入前后零漂移。首次新增 Web 夹具把 /private/tmp 预期与产品返回的 /tmp 同位置路径混比，before/after 同一断言失败；实际诊断确认 kind 相同、仅 URL 规范形式不同，只在创建夹具前 canonicalize folder 后重跑失败 Web 与尚未跑的 grants，未改产品、未放宽原断言，Scene 已过部分未重复。v1 原值、诊断与 v2 修正均保留；未启动/退出产品 App、未改真实偏好或媒体，UI16 验收进程保留。

本批产品三文件 +15/−26，净减11行；测试三文件 +180/−1，净增179行，无新增产品文件/owner/状态链；文档与治理单独核算。P36–P42 产品累计净减225行，测试累计净增1294行，全部未暂存未提交。Scene/Web 全链复查继续，准备侧后继记录了 private typed Program 写缓存时重算相同 identity，以及 TEX 固定解析循环后再次检查已保证的 image/mip 非空；帧链另记录冷分配 issuer 刚铸造唯一 token 后的重复集合自检。三项尚需独审核实实际生产者、字段和读取边界，不因低收益直接跳过，也不为它堆新缓存/结构。长期 Goal active。

<a id="p43-producer-self-proofs-and-scope-closeout"></a>
## P43：同次生产结果不再重复自证，当前范围收口

Shader 准备只从 private preparedProgram 创建 accepted Program；memory hit 不执行计算闭包，磁盘 load 成功在 store 之前返回，唯一 store 仅接收同 key/contract 的新构造结果。因此删除 store 的重复 valid 与小 identity JSON/SHA 重算，并同批退休该 private store 的 contract 参数/唯一实参。磁盘读的 schema/key/payload digest/完整 valid 全保留，写出 payload SHA、原子发布、容量、single-flight 与失败不阻塞准备均保持；未增加“已验证”flag/凭证或第二缓存。

七种实际场景（拒绝、冷写、暖读、损坏、旧 schema、摘要正确但 stage 错误、缓存根是文件）两臂的原 ProbeOutput 编码字节、完整 typed Program 字节及全部缓存 JSON 字节一致，再核计数。冷写及各次重建/可选写失败的 store valid/identity 重算 1→0，原构造 hash 1→1；暖读仍 load valid/identity 1→1。checksum-valid 错 stage 仍先经 load valid 拒绝，再重建，当前文件回到原发布字节。新增原缓存门19行负例使用真实 typed payload digest，不能靠坏摘要提前 miss 冒充语义校验。

TEX Reader 的 image/mip 数已在读取处正数且有界，固定循环每轮 append 一个值或 throw，没有返回空列表的路径；删除末尾四行再次比较数量/扫描非空的自证。原输入、字节范围、解码预算、volume 与 sprite 检查保持。原三夹具产生的917个完整/坏输入及每个不完整前缀，全部解析字段、载荷字节、sprite Float bits 与 error 关联值深等；实际尾检查进入160→0、图片谓词访问162→0，未宣称上传、画面或计时收益。

冷分配 issuer 已先拒空/真实重复 ObjectIdentifier，并在同一锁内以固定 namespace、单代 generation 与不截断的唯一 Int index 铸 token；删除末尾再 Set(values) 计数。初始真实纹理唯一性、generation overflow 及消费端 device/epoch/alias/lifetime 保持。两臂真实 Metal 的10项身份/lease/顺序关系先各自验证，再仅规范化两个随机 UUID 比较全输出；issue5、generation4、mint12均保持，postmint scan3→0、参与该集合构造的元素12→0。现 publication 夹具补48行真实 issuer 正反例，未增加产品测试 API。

最近39方法零跳过通过（34原生行为+5源码结构）：实际四层缓存1、缓存结构5、TEX截断/预算/volume9、真实Metal publication2、graph state13、target table9。三路实际前后对照通过；Debug23.079秒成功、6212源输入前后零漂移。本批产品三文件+3/−11，净减8行；测试两文件+67/−0，没有新增产品文件/owner/state/分支或多算法。HEAD99实数复核：P36–P43产品+343/−576，净减233行；测试+3852/−2491，净增1361行，含三份原未跟踪fixture。文档/治理单独核算；这里的未提交状态属于P43验证时点，后续Git操作遵循用户最新授权。

P42的10准备域/7帧域/8Web域和168唯一产品路径已刷新，165与原审查SHA相同，仅上述三候选变更，Web89文件全部不变；三项经生产者独审、实际门及结果交叉审后闭环，未发现额外有依据的待处理项。必要读取/当前 revision/授权/异步/实际 GPU 资源边界及P41非有限JSON防崩溃检查保留。旧solid/world夹具装配、census债与普通作者封面兼容另记，不计本轮通过，也不把它们改名成此成本审查的新增硬门。当前收口不宣称永久无bug、全作者/官方视觉一致、App冷暖首帧或CPU/RSS/FPS提升；没有为此重复OS恢复/长运行或引入新微队列。

UI会话先完成自己的验证再归还窗口，本批原生/Metal/Debug按原共享锁执行，结束已明确归还。未启动或退出产品App、未操作正式偏好和作者媒体；本批运行环境按收尾回执核进程/句柄后清理，最终有界证据保留14天，一份现有增量缓存暂留供未提交改动的用户审核/后续整合复验。完成条件逐项核对与最终Git/清理状态由本批证据回执登记，不以单个green、测试数或无搜索命中代替完成。

## 当前裁决与停止项

TEX 原 Reader→Metal 门通过10案例、28消费者、200层；常见尾仅4B/22,369,620B，owned作者样本0B，极端人工例87,380B≈25%但无真实 occurrence，因此撤回常驻 purpose-cache/第二 Reader。真实尾字节成为热点再议，subdata范围不冒充物理复制/RSS/提速。P21 冷暖噪声/漂移原值保留，不报告稳定累计首帧收益；官方 parity、跨屏字体共享/内存与P25前台卡片各守原证据边界，不升为无具体风险的硬门。

旧 `test_scene_particle_simulator.py` 4541 行属已知测试结构债，不是播放回归或精简收益；不为缩行数引入 wrapper/碎片编译。P18 自有 MPEG4 夹具的绿 JPEG 旧/新同现，唯一复现仍保留，不把它默默归为本次引入或已修复。已确认无消费者的测试退休残留可直接退出，原有实际断言和其它字段保留。

2026-10-27 组合Debug暴露既有 `SteamWorkshopSceneInspectionController:354` 对 `SourceFactsBuilder` init/build 的两处默认MainActor诊断。仅给Facts/Builder加 `nonisolated` 又暴露ProjectLoader等7处helper诊断，已撤回这两声明；CPU/FD准备仍归原后台worker。后续须按整条CPU依赖边界审查，不重复该两行试验，不迁回主线程或关闭检查。Badge无效borderType与同栈重复weak另以两处小修收口；属性交付、图片/Pixabay及Video详情4门通过，组合Debug成功，不声称零警告。

## 完成范围、证据与交接

P0–P35 交接时，Scene/Web 八范围及邻接 Video、音频、图库、存储、获取、发布、支持和工具已沿实际消费者复查，当时已证同类项已修正或依实际消费/成本撤回；登录未用载荷、作者工具 PKG 前置许可/marker、归档重复读取与协议重复解析完成最近门及独审。必要的解析/读边界、账号/异步身份、真正提交/释放及发布签名继续保留。该历史交接不替代本轮审查：P36–P43 当前范围已验证，用户后续已授权提交并合入目标分支；P41 不安全 JSON 删除已撤回，P42 三个后继自证在 P43 完成处理，广域刷新与交叉审无额外有依据的待修项；离线 census 与 solid/world 旧夹具债另记，最终结算以 P43 逐项审计和产物回执为准；普通兼容缺口另记，不宣称没有任何 bug。

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
