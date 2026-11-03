# Web 冷暖启动准备记录

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**

> 截止：2026-10-25。以下观察绑定各自输入与构建；当前 Web 状态见[Web 现役状态](../../web/current-state.md)。

<!-- preserved-body:start -->

## Web 启动测量

1. 冻结主 App/daemon/helpers、源码与工具链身份，准备只读媒体的隔离副本和独立 HOME/cache。记录普通产品配置与优化 Debug 观测配置，禁止混作同一分布。
selection 从实际设置入口开始，包含通知 daemon 前的租约/属性准备；观测只读且 DEBUG 显式启用，不新增产品计时 owner。
3. 记录包/entry/目录/依赖实际读取次数与字节、Metal 创建次数、worker PID/instance、Web store/origin、CPU 峰值与停止后驻留。嵌套/并行阶段按同一时钟和区间解释，不把各段机械相加。
4. 先取得有效基线，再按主链选题；若主要等待已转移，重排本专项阶段，不按静态可疑点强做缓存。

P0 沿原 daemon runner 每轮走 `setAsWallpaper`，绑定 ticket/request/execution 和真实 presented payload；prepared/finalize 观测仅 DEBUG。Web startup 显式保留产品 coordinator 并抑制重放/登录恢复/全库预热；schema 2 取原 `session.committedAt`，轮询仅作资格匹配及另列延迟，不承诺 20ms 上界。

**D11配对摘要纠正（已落地，计时与验收门不变）：** 同App/同已发布来源的一次A/A已显示，独立汇总中位数之差不等于同iteration配对差异中位数。零基线保毫秒差，百分比不可定义则显式缺失，不能丢点。保原分布/原点，不自动授性能验收；原5%噪声、配对降幅及非目标门均不放宽，不改历史D10结论。D12补真实Web形状，不改计时或重跑历史。

**P0b 窗口配置短修裁决：** 仅本任务 App 的外部只读几何轨迹确认连续缩放与过冲，快轮也可能在短暂正确的矩形处通过。先在现 Web `makeSurface` 首次显示前设置 `animationBehavior = .none`，关闭 AppKit 普通窗口展示动画；不改作者 CSS/JS 动画、窗口层级/Space/几何判据、媒体 ACK、旧输出屏障或重试间隔。以同输入短轨迹验证过冲是否消失，再做原 C0/C1/W0 交替对比及健康输入回归；无效则撤回该单一配置，不能改宽几何阈值。此修正只依赖已取得的 P0 成本依据，不等待 P1/P5 大重构。

**P0b 结算与下一断点：** 候选短轨迹的全部在屏观测保持目标矩形，交替批当前 activation 的几何 retry 由全部出现降为零，当前媒体 ACK 与旧输出屏障仍成立；真实作者音频持续到达页面。保留这项原生窗口配置及观测到的中位数改善。候选 W0 有一次 prepared 前长尾，预启动 daemon 已采用且之后几何/媒体确认正常；现证据不能判断它是新回归还是既有离散，更不能归给 IO/WebKit。原点、日志和噪声门完整保留，整体性能卡不通过。

**准备分段裁决：** 沿原 DEBUG observation 追加父端 launch enqueue、子端接受、各 surface 完整创建/load 发起/首次 ready 来源、当前 cohort 的 snapshot 与 policy 等待时间；在原 didPrepare 成功边界冻结 generation/surfaces，再随已匹配 activation 传回。整段 surface 创建不等同 WKWebView 构造，ready 可能来自 didFinish 或注入消息，policy 接受可能复用已有 ACK；这些时间均不证明作者异步资源全部完成。先分离父端准备/传输/导航与 snapshot，不扩成全资源 trace，不增加 ready/提交权威。

## 一次依赖准备

1. 在现 `SteamWorkshopService` 准备核中形成同次 immutable input：库版本、entry/root、属性来源、locale、overrides 与资源授权 revision；actor 只装配产品状态。作者依赖 key 与 execution 投影 key 分开，单纯 overrides/grants 变化不重做作者依赖发现，采用仍绑定当前修订。
2. 合并 execution 与 analysis 的廉价失配检查；均可能命中时执行一次依赖发现/签名，用同一结果判定两份清单。解析与保存复用该快照，不再各自 BFS 全文读取。
3. 先 P1a 让校验/保存复用同次事实，再 P1b 合并冷解析读取；内存 memo、磁盘 envelope 和冷解析共用原 descriptor 核。原签名仅 path/mtime/size，同会话 generatedAt 免扫和 memo 不能充当内容验证；要拒绝同大小同 mtime 修改，须记录已读 bytes 摘要并升级清单。single-flight 按完整作者输入合并；末个等待者撤销后停止领取/回填并 join。保文件数、单项/总字节和 deadline 预算，不声称可抢占阻塞读取。
4. 采用前核版本/资源 revision，重建当前 grants；源变动或截断走保守原重算/风险档位，不用成功缓存掩盖未知。
5. 首批保留 `await saveWebRuntimeCache`，保存消费同次签名；await 不阻止 actor 重入，同 key 旧保存不得覆盖后继版本，删除不得被迟到回填复活，沿原 owner 轻量核提交 generation。各清单分别原子发布，双文件不是整体事务；两者错配/缺失各自拒绝命中。旧“编码/写盘后移”屏选已否决，不能用后移 0.9–4.5ms 的历史局部数值声称 App 收益或强行新增队列。

**反例：** 跨启动仅一份清单命中、include/JS/CSS 依赖新增/删除、同大小修改、扫描中变动/截断、overrides/语言变更、书签撤权、A/B 交错与旧保存。缓存不存 grants；冷暖产出的 descriptor、payload 和档位须一致。

这里的来源是本请求已批准并持有租约的具体 folder/dependency generation；库发布新版本不强迫仍合法的旧版本请求改读 latest。快照自洽检查不能被表述为已核 canonical 最新版本，租约也不认证外部改写后的字节。当前授权仍在最后 await 后沿原 owner 重建；派生缓存发布失败不改变产品输出事务。

**P1a 实施修正：** 作者输入不仅是 entry 依赖，还包括 record/property-source 项目字节及 `sampleStructure` 实际消费的顶层目录名；跨根同名文件保规范来源身份。P1a 的单轮签名不等于全链文件只读一次，属性判定和冷 summary 仍有独立读取；其间观测到来源变动必须拒绝当前候选或至少拒绝回填，不能把解析 B 标成摘要 A。临时 FD/目录收据只用于变化检测，不持久化，不替代 P1b 对实际解析字节的绑定，也不能宣称未知文件系统的原子快照/所有外部改写已证明。派生发布先在锁外写唯一 staging，锁内只核 generation 并最终 rename；删除共享该边界，在途 ticket 结束后 slot 退出，不让主线程等待整份缓存写盘或积累历史 record 槽。

属性定义只需来源 ID、具体目录和可选 project URL，由原 property-source owner 返回轻量值；已 pin 的依赖版本不得重建整份库记录或改用 latest。目录存在而缺 project 的 inferred HTML host 仍保来源身份并返回空定义；目录消失则拒绝来源。

**P1b 实施裁决（实施前记录）：** 在原 service 内捕获具体 own/property-source 角色、规范路径、同次项目字节、原入口 resolver 实际选择及候选类型事实、依赖状态/sourceKind、顶层目录名与完整有序 `languageKeys`。原 JSONDecoder 声明入口与 JSONSerialization 属性解释消费同一份 Data，转换为 Sendable typed facts；不跨 actor 传裸字典，不以缺项为由重开作者 URL。实际 localization/definitions/display resolver 显式消费捕获的完整语言序列；memo、analysis/runtime 清单和 flight 绑定同一完整作者身份，不能只补 flight key 而磁盘清单仍漏依赖态或入口类型。清单升级拒绝旧版本，不只按首选宿主语言合并。

真实 `setAsWallpaper→canLaunchDownloadRecord→webLaunchEntryIsValid` 前门只核 record 已选入口的存在/普通文件类型与依赖可用，原准入 memo 使用 entry-only key，不选 property source 或同步 JSON 解码。声明入口和 fallback 合法性只在后台 capture 沿原 resolver 解释，失败仍返回本次准备反馈；不能让前门另一套 preferred-only 检查抢先否决原 resolver 的合法 fallback。同步 UI miss 同 turn 复用已选轻量 source，不能为签名与解析各发现一次。减工探针若未覆盖此前门，报告仍明确该范围。

缓存认证与冷 summary 是两个逻辑遍历、一个读取叶核：现签名最多120文件、单项4MiB/总16MiB/200ms，summary 没有文件数上限，已有205文件反例。认证期只保有界精简事实供 summary 复用，后续 summary 流式归约并释放 bytes；保原128KiB前后片段、≤1MiB service-worker 全文补扫，全文签名发现的中段引用不能扩张 summary 的原连边。超认证预算仅失去 cache/flight 资格，不能截断冷解析或让200文件之后的风险消失。读取内部继续核 FD/来源稳定与取消，退出 capture→parse→adoption/save 之间的重复打开检查；捕获 A 后磁盘变 B，解释仍消费 A，不声称 WK 页面资源或文件系统获得原子快照。

memo、analysis envelope 与冷核只提供同一种纯作者 parse product；不共享含当前 binding/preconditions/grants 的整份 descriptor。捕获的 preset/pathlike facts 经原 assembler 传到 preconditions、payload、bindings 和最后 grants；最后 await 后仍逐调用方取得当前 overrides、书签/安全域及路径存在性。同步 UI 走同一解析/读取核但不做启动认证或给未经认证结果授持久内容身份。

在原 service memo 职责内按完整实际消费事实摘要、own/source 角色路径、entry/root、完整语言序列及 parser/schema 合并在途纯解析；不完整身份不合并，完成后不另留一份免扫描缓存。每个等待者有独立 waiter identity、publication ticket 和当前投影；一个取消不影响其他等待者，最后一个退出关闭 admission、取消并 join producer，旧 flight 只能按自身 identity 清理。每个异步调用方（包括 preload）在同一无 await 的 actor admission 段选定实际来源、拒绝 record/source/dependency 正在删除，再沿原 library registry 对实际 managed roots 并集取得 lease：包括 own/source、entry/root、项目来源及有序授权 namespace，覆盖独立 capture worker 的 await/join 与后续 flight join；不能仅用 record 的 dependencyHost 字段近似无 pin 来源，或遗漏 own props 配 host entry 的组合。

产品外层 record lease 保早段准入；成功准备把实际 roots 的同一 token 随通知转交原 renderer，按原 ACK/退出释放，不让新 lease 在准备返回后消失、消费端却只持旧 record 双字段的 lease。失败/取消与无 renderer 的 preload 则在自身读取/join 后释放；纯 product、cache 和 flight 不持 token。采用/保存继续核已捕获来源的删除状态；legacy 无 managed identity 时不伪称已获租约保护，保原兼容失败边界，不另建 legacy lease registry。

产品 `setAsWallpaper` 在原 intent owner 保存准备 Task/generation，新选择立即 cancel 旧准备；本地 Video、静态图片与 stop 不经过该入口，故原 Manager 的 `beginPlaybackIntent` 在推进唯一产品 epoch 后，通过 App 注入回调撤销 service 的准备，不能只等最终 `isCurrent` 拒绝结果。Web 先取得原进程预备意图，再捕获 service generation，避免被自身 epoch 推进判旧；入口早退仍先撤上次准备。旧 Task 直至读取/flight join 后才释放自身 library lifetime，preload 以自身 lease 保留独立有效 waiter。同步取消入口不阻塞主 actor 等待，阻塞文件读取仍不能立即抢占；回调不建立第二产品提交或跨引擎协调器。 安装点保原 Manager 初始化时序：在既有 mute migration 之后、coordinator/configureRuntimeSwitching 的恢复播放之前设置；不能为接一条回调把 Manager 提前到 Service/桥接装配前。

原 preload 的 live-resource 跳过策略不在 lease 外解析作者定义：沿原 overrides/bookmark owner 只查已存书签存在或绝对路径 override，已知状态即保守跳过，否则进入统一 admission/capture。项目/依赖读取先非阻塞打开并确认普通文件，特殊 FIFO 不应让取消后的 join 永久等待；普通阻塞磁盘读取的不可抢占边界不变。

验收必须编译真实捕获/解析/装配核，覆盖 A→B/ABA 后仍消费 A、own/host 同名角色、pin/no-project/声明入口与 fallback、次选语言变化、205 文件及前后片段/中段连边反例、认证预算不影响冷播、override ABA/当前 grants、单/末等待者取消与旧 flight 不清新 flight；原 CAS 保存/删除门保留。缓存核替身门不能代替这些真实解析和产品取消入口行为。

[第二批实测](wallpaper-startup-p1-p2a-2026-10-24.md)未证明 P1a 整体提速。P1b 以收敛解释输入和退出临时重复检查为边界，不围绕轻输入签名继续做低收益微调；宿主创建、页面 ready、snapshot 的实际等待由 P5 原职责处理，不能跳过可见和提交检查换速度。冷条件 selection→hello 可包含与 service 准备重叠的空 daemon 等待，不能把 selection→launch enqueue 全归解析/缓存。

[第三批结果](wallpaper-startup-p1b-d1-2026-10-24.md)：三文件冷服务核读取API操作10→3/返回800→190B，不代表物理IO或完整启动比例。v3轻Web五组C0/C1/W0中位899.851→874.380、871.188→901.436、270.620→274.718ms；C1增3.472%，各条件噪声门未全过，整体卡不通过。v2原C1增约179ms与后续基线自身漂移均保留，装配顺序纠偏未证因果，不称已修复。停止围绕轻输入重复微调，后继按已证职责推进。

**退出/重开：** 同输入不再重复发现依赖且输出相同即闭合职责；耗时另验。只有新产品计时证明保存仍占关键路径，才在此处修订后移设计；需原 owner 的版本 CAS、取消与退出 flush，不恢复独立保存队列旧方案。

## 宿主退休与复用

1. **D12入口STOP：** 现W0在selection前已有hello，原空daemon预备已覆盖spawn/AppKit/IPC；fresh Host/view初始化未证可省成本。stop及弱引用诊断不证明目录/网络/JS/FD终态，复用还须迁移现version2请求和频谱身份。保单次daemon及空预备，不落闲置drain/协议基础；重开须先证同进程第二个fresh Host/view相对新预备daemon的净收益及可行清场，再实施以下条件设计。P5b公开清场不足仍停止。原adapter保持两槽，无第二池。
2. 拆开 transport 的 daemon instance 身份与每次 execution request/session generation。worker 的原请求不可改名；协议升版拒旧版，无双生产fallback。
3. 首片daemon-only只接原事务已允许退休的committed成功Session；失败/取消候选、重建和恢复仍精确退出。新候选可见后原事务退休旧active：先关输出/输入/音频、撤grants/endpoints/watchers、取消导航/资源/网络，再drain，不能等持续任务自然清空。后台Worker/Service Worker退场未证则退出，不保WebView。
4. child 回传 instance/request/sessionGeneration/reset nonce 全匹配的 ACK，父端在预期 retiring 状态才释放该 request 的 library lease；重复/迟到 ACK 无效，实际退出也能结清。ACK 前旧 scheme/Range/网络/目录任务与重开文件回调均已撤销/排空；每段有截止期，缺失/错误、超时、压力或父退出终止精确 worker。可再次 bind 还须原事务允许 endpoint 退休且无未决回滚/采用预约，不能仅凭资源 ACK 提前改名。
5. P5a全部surface/WebView/server/request销毁及drain ACK后才空闲。P5b还须证WebView成本，HostCompatibilityKey全匹配store/profile、authority/root、origin、bridge/config schema及screen；去旧handler/scripts并受控blank，但blank finish不证明BFCache/历史清空。公开API不能防旧文档恢复/旧generation写入即退P5a，无私有清理API。空闲无作者执行/授权/采集，不全清persistent store。
6. 新请求只采用已 reset 的空闲 worker，注入当前身份/grants 后按原导航、snapshot、媒体 completion、可见确认进入事务。active 不原地改页；reset 中新意图遇到两槽已满，终止该 reset worker 并等精确退出后冷起候选，期间保 active 和原 newer-wins，不借此开第三槽。
7. 退休warm与原预备共用槽及总峰值，保原空闲超时/压力/停止策略，不定时补进程。HTTP仅P5a；退出原总截止期内撤扫描/reset/预备，shutdown不补进程。

**反例：** A→B→A/同记录重设、不同 store/profile/屏幕、reset 期间新请求、迟到脚本/网络/媒体回包、同 store 两个 worker、取消/恢复、主进程死亡/阻塞、worker 崩溃、旧租约释放后更新/删除、cookie/localStorage 应保留而页面对象应清空。

**退出门：** 真实 ACK 后旧 request 无任务/授权/输入/采集，旧 lease 可回收；非兼容 key 全量重建；五次以上交替启动及最终长期切换门通过。P5b 无收益/清理不成立退 P5a；P5a 失败退单次 daemon + 空宿主预备，删除相应产品分支，不延 timeout 或减少 reset 验证。

## 本地响应与 origin

1. **D12首片：** 同host/Path=/固定名`mwx-access`会在同store双端口HTML间覆盖。改名绑定原不可变lease token，名字/值均核本server，保token路径或本cookie的OR准入；原surface teardown按创建时WK store精确删本name/domain/path，不清整个store、不取后继surface，不将异步删除冒充drain。保原token熵/SameSite/path/端口/root/grant/stop重启，不认跨端口文档隔离。真实共享WK store两端口先红后绿，核双向无前缀读取、停A后B及迟到响应；无cookie/错误token/旧固定名/陌生前缀和原Range/304/HEAD/撤权仍拒非法。只认连续性。转换cache无热点依据STOP；重开后沿原读取核按Data digest/kind/schema及实际输出投影有界复用，含token存中间表示再投影。不持grant/FD/lease，单项/总bytes受限；仍读全文取digest只认少转换，不认少IO。
2. 保留每次资源授权与规范路径检查、ETag/Last-Modified/304、HEAD/Range/取消及背压；`no-cache` 是重验证，不等于 `no-store`。普通媒体已有分块，不重新做整文件缓存。
3. loopback 保留现有两种准入：带本 lease token 前缀的路径，或无前缀但携本 lease cookie 的请求；不是每个请求都要求 token AND cookie。先覆盖同 store 的 active/candidate 并存：cookie 不按 port 隔离，见 [RFC 6265](https://www.rfc-editor.org/rfc/rfc6265#section-8.5)。cookie 名/删除按自身 lease 区分，不能覆盖后继凭据；这只解决冲突，不证明跨端口请求来自哪份文档，根/grants/token 的原安全边界不得放宽。
4. 首批不强行固定端口、不为稳定 URL 跨 author 合并 origin、不把同 origin 下多个活跃 grant 取并集。保持现有随机 token 路径与逐 session 授权；高兼容档跨重启的 storage/HTTP 缓存身份尚未解决。
5. 只有 P0 的真实缓存/存储反例确认 origin 变动为目标成本，才另修订本节确定单一 origin 授权 owner、双候选路由和端口冲突退出；在此之前不启用高兼容 WebView 复用，也不新增 broker/第三进程作为整个专项前置。

**退出门：** 同内容转换次数减少且当前 token/授权正确，源修改/依赖变化即时失效；跨 worker cookie 不干扰、撤权有效、媒体与框架加载相同。origin 稳定与 HTTP/Code Cache 实际命中另报未知，不能由 store UUID 稳定推断。

## 冷暖条件

| 条件 | 产品 cache | 进程与执行 | 用途 |
|---|---|---|---|
| C0 首次使用 | 隔离且为空 | 新主 App/对应 daemon，无本轮空宿主 | 完整首次成本；不声称 OS 页缓存真冷 |
| C1 跨进程暖 | 明确保留同一 HOME/cache/内容 | 新进程，记录 WebKit 实际 PID | 跨进程持久产物收益 |
| W0 同进程暖 | 保留同一份 cache | Web 记录 worker 采用/新建 | 同内容重设及 A→B→A |
| X0 跨引擎返回 | 保留 cache | Web/Video 互切，记录真实退出/复用 | 生命周期、回滚及实际产品等待 |

各条件单列单屏/双屏、轻/重、静态/脚本/视频纹理、standard/highCompatibility。每阶段用一个能触达目标的输入和一个未参与修复的健康输入短筛；最终覆盖上述代表集，不要求每次局部改动全量矩阵。资源/变量改名与等价依赖/属性变体应得到同结果，不能按样本/path/hash分派算法。

## 比较与声明范围

记录中位、范围与原始 run，不用五次宣称尾部分位数。先冻结噪声与非目标预算，超噪声先排干扰，不能删慢点或放宽门。

Web selection→匹配 commit 并单列 snapshot/窗口可见，不称物理呈现。。辅助指标包括主线程最大 stall、读取/写入字节、各缓存真命中、首次完整内容、峰值/稳态内存及停止后资源；准备期间旧 active 连续性同样验收。普通优化产品与诊断配置分别报告；Release 不新增详细观测。

Swift 产品改动需签名 Debug build；GPU/VM/资源/宿主改动需隔离真实输出和下一帧、暂停/恢复、失败/取消及 drain。最终执行至少 30 分钟稳态、20 次轻重切换/resize，并覆盖停止/退出、压力、睡眠/唤醒和显示器变化。缺最低设备、多屏或 Release 时明确未验，不扩大声明。

## Video 长跑观察

固定签名 Debug App 主二进制 SHA-256 为 `f075dca44ba637e5a23a28f9e95b2c160279f4e100fe93c81a59f31a6553ef68`。视频连续 awake 30 分钟，沿原工具观察端点截图、进程身份、资源采样和自然退出。该记录只证明有限稳定性，不声明全部帧间隔、无泄漏或性能对照。

<!-- preserved-body:end -->
