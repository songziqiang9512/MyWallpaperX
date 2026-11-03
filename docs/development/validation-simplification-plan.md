# 全仓校验与链路精简

<!-- document-role: active-plan -->

主动删除对实际功能无帮助的校验、认证、重复计算和嵌套，使链路直接、按需、轻快。用户原话与必要边界由顶层 [AGENTS.md](../../AGENTS.md)约束；不能拿旧实现、旧测试或“更严谨”反向保留无用工作。

## 审查方法与完成条件

沿真实生产者到实际消费者检查每项工作的阶段、频度、直接避免的错误、重复读取/计算/等待和失败范围。先查已有上下文能否直接使用；在实际读文件、消费资源或提交异步结果处保必要边界，同步纯计算之间不反复证明同一事实。普通视觉或可选缓存失败只影响最小单元，失效沿原读取/解析链重建。不能为了证明“安全”新增许可、wrapper、多层 fallback 或第二 owner。

完成需同时满足：下表全部范围有当前源码审查；有依据的发现已修复，或由实际消费/成本实验明确撤回；改动经过最近行为门、适用构建和必要代表运行；独立复查没有未处理的同类问题。少数样本、构建或测试数不能代表全仓完成。旧额外指标若既无具体回退风险、也非本轮要宣称的收益依据，应说明原因退出，不把可想象的验收无限升级为硬门。

所有前后数字绑定相同真实输入、代码与执行边界；方法次数不是 syscall、物理复制、耗时或首帧提升。UUID/日期先在每臂验证身份及引用关系，再比较功能投影。当前构建和原始失败均保留，修夹具不放宽产品结果。每批报告实际改变、前后对比、回归与未覆盖范围；Git 操作按用户当前授权，三会话串行整合、不推送。

## 顺序与覆盖

| 范围 | 当前已证事实 | 仍需完成或保留的边界 |
|---|---|---|
| 0：误拒播及当前产品 |正常身份作者 Web 的实际音乐响应、暂停/恢复和普通退出通过。| P27 Release 是当时源码的构建；当前 P29 运行是 Debug。不据此宣称全作者视觉或稳定提速 |
| 3：Web 模型、授权、宿主、桥、媒体、帧、缓存、进程提交 |P29 空 options 读取 2→0、需求短路及 Release 纯音频日志退出经最近门。| 可见音乐响应由用户直接确认；歌曲封面仍有局部 `[object Object]` 资源错误，保留问题，不冒称完整兼容 |
| 4：Video、共享音频、IPC、获取与存储 | 完成帧直达频谱、按需频带、Release 诊断剥离、原文件/分片/票据边界和旧库发现均有逐批行为证据；P22 实际 helper/静帧/取消门通过；P31 恢复时未消费 SHA 退休，真实 receipt 相同；P32 校验临时构造退出、四个实际授权点保留 | 只补当前变更影响的整合边界，不把旧系统恢复/长运行全部再跑一遍 |
| 5：全仓、图库与工具 | P23–P28 图库减工及旧入口退休已有对应行为/成本证据；P29 删除普通建库连接的全库 quick_check，45 项 Store 原行为一致，v1/事务/故障门通过；作者快照工具不再携带安装 marker；P31 设置导入局部复用与在线目录无消费者预取退休均经实际最近门 | 全仓实际消费者复查完成，最后工具与协议项见 P34/P35。UI 专项布局/交互由其 owner 维护 |

## 执行职责与稳定合同

来源 revision 在独立请求实际消费处取得；已完整读取的不可变 snapshot 不在后续纯计算中重新 stat/认证作者文件。真正继续读的 FD、chunk、segment 仍保范围、短读/读中变化、取消和路径授权；私有完成输出保原域、预算和强 lease。下一请求仍取得当前 revision，不引入长期免失效凭证。

已捕获的派生 hint 可异步保存，读取端失效只 miss；保存前不再扫描全部依赖，不授予权限或阻塞播放。

下载完整性归原获取/复制/发布事务，不把旧摘要变成日后播放许可；普通本地播放不重验整目录或全部包条目，见[获取合同](../architecture/steam-workshop-acquisition-contract.md)。跨引擎切换、取消、提交与最后资源退出沿[现有事务](../architecture/playback-lifecycle-transaction-design.md)。实际服务、frame/clock、资源与输出各有唯一 owner，不能为精简再造第二套权威。

## P28：同次导入复用已读取元数据，已验证

已证重复：原 worker 为每个展开输入构造模型并读 stat/ImageIO，主线程才去重；`[a, alias, a]` 仍读三次。只在该 worker 局部按原始路径 UTF8 字节复用首次 fileSize/width/height；原模型同一构造入口每次仍产生独立 UUID/addedAt/path/title，原 candidate/输入顺序、exists/isDirectory/isReadable 与每输入回执全部保留。不同 alias 不合并；不把旧库行或入口快照当当前来源，不增加主队列往返、持久缓存或 owner。

元数据只服务信息/排序，实际播放仍消费当前行路径。一次请求内的 first-metadata 语义不冻结文件 bytes 或授权，独立下一请求重新读取。普通单文件的一次准备仍可能成为最终新行的元数据；提前按库快照跳过会改变实际 cleanup/load/reset 与当前提交语义，额外多阶段补救方案不采用，不能把这一次准备也计成已消除。

本批先保持原导入/JSON/ACK、当前库/epoch 与发布/modal 语义，单独观测真正 stat/header 入口，不能用模型构造数冒充读取数。核重复/重叠目录、别名、文件变化、每输入可用性和新身份；前后完整行/回执/持久化结果先一致，再报告减工。沿现有 mixed-import/metadata 最近门和一次适用 Debug 验证，旧已过源码不重复跑；若实现需要新的阶段或缓存权威，撤回该扩张。

结果：同一实际夹具、同编译选项、每臂一次编译，原 11 组 stat/header 各 14→12；新 3 组分别 6→3、2→1、4→4，模型构造数及原六项发布/保存/epoch 等计数逐组不变，输出/持久化/回执/事件投影相同。3 个导入方法、1 个下载最近门通过，Debug 31.527 秒、严格签名成功且源无漂移；构建耗时不是播放性能。退休的 preload 测试字段、方法和断言已删；下载夹具首次因既有 Web 缓存协作者装配缺失而未编译，补齐原受控叶后通过，未放宽实际断言或恢复退休字段。独审绑定原始两臂结果；未宣称实际 App 首帧、物理 IO 或内存提速。

## P29：常规打开与实际消费者之间的重复工作

本批回查发现：关系库每次普通打开仍执行整库 `PRAGMA quick_check(1)`，包含当前快照不消费的封面数据页。Web 空 options 的编辑事件仍准备定义和值，读取解析 project。部分 Web 音频代码仅为布尔需求分配数组，或在 Release 注入无日志消费者的调试分支。沿原 owner 直接移除这些工作，不增加长期缓存、准入凭据、wrapper 或新的阶段。

关系库保 SQLite 实际错误、schema/application ID、事务、当前行/alias/epoch 检查及 v1 升级事务内的完整性检查，普通已建库打开不再扫未消费页；封面读取保自己的数据边界。目录 fsync 候选已撤回：原发布失败后仍需完成目录持久化，直接删除会破坏实际恢复语义，为省一次同步另造凭据反而加重链路。用最近行为门、读取/SQL 入口对照及一次 Debug 验证，再补当前 App 代表播放，完成前不写为已通过。

结果：45 项原 Store 行为断言两臂全真且一致，实际 prepare 入口的 quick_check 10→0（多个 Store 各首次连接，不是每 snapshot）；原 v1 升级/封面/回滚、发布恢复和 SQLite 故障三门通过。空 options 同一真实 Web 夹具读项目 2→0，非空默认值、覆盖值和磁盘变化保持。Startup Debug 27.862 秒、正常身份 Debug 12.352 秒及严格签名通过，构建不是运行提速。首次 lazy 闭包缺 self 的编译失败、DYLD 观察探针 SIGBUS 和脚本装配失败均保原值，只修受影响部分。

普通 App 验证使用正常身份、独立 HOME/私有设置 suite；用户确认真实音频柱响应，并分步暂停保持、继续。记录证明同一 request/活跃子进程暂停后页面频谱归零、采集停止，恢复后真实非静音回调再现，最后普通 Cmd+Q 退出全部已观测子进程。正式偏好原值已核对恢复，再打开原安装 App。旧 Startup 专用身份拒绝普通入口和首次 240 秒观察超时不计为播放/普通退出通过。

## P30：目标元数据直读与共享读取复用，已验证

单条 `publishedMetadata` 目标查询不再先枚举和排序全目录：在原 index FD 下选择一个实际 basename，立即 openat 捕获 errno，仅目标打开时的 ENOENT 作缺失；已打开后的类型、硬链接、4MiB、读中变化与取消仍由原 readData 消费边界检查。全库发现/GC 保原枚举、排序与预算。ID/filename 两筛选仍取交集，显式 filename 保旧独立视频名支持。文件名只要求元数据后缀、无斜杠/NUL，不把相对资源路径 parts 的冒号/反斜杠政策或任意 255 UTF8 字节上限套到真实目录项；本机已复现合法冒号、字面反斜杠及 305 字节中文名，原路径限制会误拒或误读它们。

直接读取在现函数内完成，不扩全局异常模型或另造 helper/cache；原 openFile 预读 info 与 readData 的首个 info 重复，元数据读取仅保实际 readData 前后检查。相邻共享项沿原 owner 复用 OnlineImageStore 同一次解析已得的目标叶属性，缺失祖先的属性不能当目标存在；SystemMedia 七字段 UTF8 长度直接计数，不为 count 构造 Data。用既有最近门和同输入 FD/读取入口对照，冻结后一次 Debug；P29 无关的音乐/系统恢复不再重做。

结果：实际原 owner 两臂读取同一 135 项目录，3 类已有目标查询 readdir 入口均 138→0、排序项 135→0，实际 openat/pread 各 1→1，regular-info 3→2；目标缺失从枚举后不打开改为直接尝试一次失败打开，仍免全目录发现。无筛选查询保持原枚举/排序和两份读取，regular-info 6→4；五组返回字节完全一致。这里是实际入口调用数，不能当内核 syscall、物理 IO 或 App 首帧耗时。另两项只报告源码明确删除的重复属性查询和临时 Data，不宣称测得内存或墙钟收益。

11 个最近回归方法零跳过通过，覆盖目标名/缺失/错误、真实文件叶边界、原发布回滚/当前删除、播放租约、在线图片发布/取消和媒体 UTF8/原子快照。合法冒号、字面反斜杠和长中文名实际创建/读取成功；symlink、directory、hardlink、超限文件和残留 errno 不被误作缺失。正常身份 Debug 38.446 秒、严格签名成功，6202 项源码前后零漂移；未启动新 App 或改正式偏好。两项独审无阻塞；新夹具没有注入读中并发变化或取消，不升级为所有 FD 并发情形证明。

## P31：下载恢复和显式导入，已验证

下载恢复对已有 chunk 计算从不消费的 SHA256，仅 Adler 结果参与判定。个人设置导入同一请求重复解析相同路径。在线下载目录为所有文件预取属性，实际选中后又丢弃这些属性并重新读取。先核各自唯一生产者和实际副作用，沿原 owner 删除或复用；不新增许可、stamp、长期缓存或第二权威。均已核唯一生产者和真实消费者，不引入新 owner。

下载保原读取、取消、Adler 和最终真正消费的 receipt SHA256。导入沿原局部 normalized 表复用同一准备快照，下一次导入仍重新解析，原缺失计数、别名和恢复事务不变。在线目录仅去掉全目录属性预取，选中文件仍清缓存后 fresh 读取，AV 后仍核当前 identity；正常行为不依赖先取得再丢弃的值。

新增导入反例走原 SQLite/源 owner，重复路径与不同 alias 保持，独立下一次导入重新捕获已 retarget 的 alias。在线目录门首次因既有夹具缺少当前 expectedBytes 参数而未编译，只补该受控叶签名，原实际断言保持，再单跑通过；原失败保留。

同输入 hash 对照：4 个已有 chunk 的有效恢复原喂给 SHA256 131091 字节、现在为 0；真正最终 receipt 仍喂入相同 131091 字节并得独立 Python 算法核对的相同 digest。坏 checksum/截短结果一致，原取消门保留。减少的是未消费 SHA 工作，文件读取和 Adler 没减少，不当作物理 IO 或启动百分比。两次真实导入的路径解析入口 10→6，完整行/locator/summary/checks 相同，独立下一导入重新解析 alias。cold/warm 仅为每臂独立进程与私有 cache 范围，不是 App 冷暖启动。优化两臂实际编译耗时长于估计，原运行保留、没有重复编译；两 wrapper 源零漂移，结束明确归还窗口。这里只报告原入口工作量，不据此宣称硬件指令、CPU率、RSS、物理IO或App速度。

## P32：查询校验减工，已验证

WorkshopQueries 的 ValidateAccountLocked 直接比较当前账号字段，保原 Epoch/login/TryParse 三谓词，再单独求当前 token，最后比较 Connection/SteamId/token，避免短路改变原 getter 异常顺序。真正入队 Capture、锁与四个 chunk 授权检查点不改，不新增凭据或跨 await memo。另删 MapItems 的 fileType/hcontentFile 两个无 Swift 消费者的输出列；只触及 browse/details/author/subscriptions 四类行投影，SDK raw、Probe 和实际下载仍保原字段。旧 JSON 额外列不构成客户端功能，退出无须迁移状态机或协议新层。

前后编译使用相同优化/WMO选项减少任务自身重复前端工作，不重跑 P31 旧完整计数或无关系统恢复。源码冻结后一次适用 Debug，失败只修真实错误；实现前的设计与独审见本机 p32 证据。本轮没有 App 启动/退出或正式偏好写入。

账号对照仍有 3 个原 CDN 检查 callback 和 1 个原锁内 Send，真正 admission 构造 1→1，校验的 Capture 构造入口 4→0；六个等值/拒绝 predicate 一致。同一实际 ProtocolWriter 单行响应 658→618 UTF8 字节，仅剥两退休键后全 frame 相同；SDK raw 与实际下载不改。这是原表达式/构造入口与 wire 字节，不等于GC分配、CPU率或 App 冷暖耗时。cold/warm 是每臂独立夹具进程/cache，未重跑 P31 旧门或系统恢复。三份实际结果/产品独审无阻塞。

## P33：退出未消费登录载荷与最终范围审查，已验证

当前实际恢复链只消费 refreshToken、真实 accountName 与账号身份。helper 的 result AccessToken/NewGuardData 仅给成功终态 private 输出；Swift 不读前者，后者只转存到 Keychain、从不恢复。沿原 SteamSession→AccountSession→AuthRoute→TokenStore 四 owner 删除这两项无用传输、tuple 成员和 guardData 持久字段，保原 refresh 登录、真实账号名、attempt/epoch/terminal、记住/撤授权与保存失败语义。SDK 的 LogOnDetails.AccessToken 实际承载 refreshToken、PICS/raw 与 Probe 的研究数据有不同职责，均不混删；隐私脱敏和旧格式反例保留。

旧 helper 的额外键与旧 Keychain JSON 按原解码规则忽略，无协议升级、迁移状态机或主动读取重写。只在现有离线 helper 和 client lifecycle 夹具补真实成功帧/旧新载荷、mock persistence 与内存 codec 反例，不接真实账号或 Keychain。原保存次数不变；本项只报告未用字节/字段退出，不能称减少一次保存或 App 启动提速。源码冻结后最近门和一次 Debug，同时由独立审查收口 Web 与全仓剩余实际消费者；原 client 生命周期与 helper 离线门零跳过通过，含真实 BeginAttempt/FinishSuccess/Writer 的成功、旧/重复终态，以及旧额外 private 键/新最小载荷、mock persistence 保存次数和旧 Payload string/null guardData 的纯内存 codec。另 15 项协议 golden 通过；Debug 32.316 秒、严格签名成功，全源零漂移。未读取真实凭据、执行登录或调用 Keychain。实际 SDK refresh 登录、PICS/Probe 与隐私 redactor 保留。工具误拒与 marker 残留由 P34 处理。

## P35：协议 ID 只解析一次，已验证

`queryDetails/querySubscriptionStates` 的合法 ID 原先先 `TryParse`、再 `Parse` 同一字符串，后一次没有独立消费者。沿原 `PayloadULongArray` 直接收集首次成功结果，每个合法 ID 解析 2→1；保持原过滤、culture、顺序、重复、零和 UInt64 边界，不新增缓存或准入政策。原协议自检已补两实际命令的混合输入、空载荷及 culture 边界；原 helper 离线门零跳过通过，protocol 35/35、auth 48/48，原 manifest/staging/download/query 及 Release 开发入口/元数据隔离全部通过。Debug 14.115 秒、严格签名成功且全源零漂移。本项是同值解析减工，不宣称可见首帧提速。

## Web 请求与发布

Web：正常属性投影不提前构造未用备用 JSON，同次 value/binding 直接共用，不为只取类型而重解路径/书签。初始夹具 binding 入口 6→4、备用序列化 1→0；预览/提交各 4→3，完整属性 JSON 相同，独立授权请求仍取得当前事实。取消按 URL 名称/后缀拒媒体；换源清除旧失败标记，迟到 A 失败不能暂停或清除 B。追加 `<source>` 后立即 `play()` 时，空 currentSrc 只代表浏览器尚未选源；删除该提前返回，让原生完成选择或报告无源失败，不复制选源算法。真实值清空、当前实际失败、作者暂停、授权根、FD 与请求边界保留。

Web 退出 DCL 第二层播放 URL 许可与删除空 source 节点的全树扫描，保作者 play/pause 意图，交原生选源；作者保留的空节点可在 DCL 后正常赋值。退役父端只空消费的 prepared/committed 两消息、DTO 和空分支；真实 cohort、activationConfirmed、visibility/ACK 和取消退出不变。双方每次从同 Bundle 启动独立 pipe，不引入旧子进程迁移层。两 play wrapper 合并候选撤回：DCL 层承接解析期作者重写的方法，直接移到 document-start 会改变行为。

Web 同次 resolve 在原函数内只解码一次请求路径，cache key 和冷解析共用该局部值，唯一无外部消费者的 resolveCacheKey helper 同批退出。冷 miss/显式刷新解码 2→1、暖命中 1→1；loopback 404 的可选媒体分类只有 Debug 日志消费者，整段归 DEBUG，Release 分类 1→0、Debug 1→1，sendError 原样。数字由实际源调用链确定，不是计时或物理 IO 测量。精确 URL 解码、缓存键字节、授权根变更、实际 FD/range/metadata、symlink/escape、取消/旧代次、404/416 与停止后的迟到完成边界继续由原 consumer 维护。

Web publication 活 slot 命中先返回，miss 新增前仍清死 key。同步 service 删除原先在同一 MainActor 栈先 invalidate、再同 key invalidate+unlink；现直接清 memo，只在最终原 Slot lock 内一次撤权并删双文件，唯一旧 helper 同批退出。旧 writer 先得锁可完成后被删，删除先得锁则旧 ticket CAS 不得 rename；publish Bool 无产品回调/结果消费者，不增 stamp/锁/owner。侧车 SHA 有防坏但可解析的 namespace 隐藏真实资源的功能，明确保留；不是作者播放许可。

Web 媒体端点不再先取完整 Array 再逐项比对象，直接用原 registry 的 token→对象身份查询；原 request/screen/lease 与异步代次保持。网络回包只去掉固定生产域的重复 JSON 扫描：七个实际调用只写 Bool/Int/String 和 String header，远程 body 先 base64 成 String；不把任意 Any 或解析所得 JSON 当作同一安全域。surface 的原 DEBUG 界移到整个延迟诊断回调之外，Release 不再安排一秒后的空回调，Debug 原诊断保留，关闭/释放路径不变。相同六种真实 WK 场景每臂均通过，完整 general 输出深等，三次完整网络回包断言保持；实际媒体身份查询 121 次中的 Array 构造/线性查询 121→0，改用原索引；网络回包 validity 3→0。

Web resolvedWebResourceBinding 不再先无条件计算 pathlike fallback 再由 file/directory 覆盖类型；原表达式直接归入 fallback else-if。相同 11 输入的完整 Codable binding、实际 payload JSON 和 grants 深等，原书签精确文件/邻居越权、根顺序及权限/代次边界保留。外围 payload/grants 若有自己需要的读取仍在，不把直接绑定减工说成整条链零读取。
