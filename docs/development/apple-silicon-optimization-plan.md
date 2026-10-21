<!-- document-role: active-plan -->

# Apple silicon 与全 App 性能优化执行方案

状态：2026-10-21 D14分配栈／持有链实证与独审完成、未定位可修冗余owner而STOP产品修改；D13同次颜色分析复用完成完整输出对照、局部计时及同配置App冷暖资格／独审（暖轮未证收益，全仓存量两门另列）；D12词法快路完成行为门、冷暖资格与独审（全仓两门存量FAIL另列）；D9启动库结算完成最近门、最终构建与独审；D10普通Release归因及D11手动Space对照已采集并经独审收口；仅保已证范围，不据未归因数据改产品；D1–D3、D7–D8保留，D4–D6原处置不变；D7同次采样器分析复用、D8准备批次取消已完成最近行为门、隔离原生运行和独立审查。原24项与STOP继续有效。正向成果分批提交，不推送；D1–D6基准 `039d164cb048787557068a2412335937db809bc5`，D7–D8基准 `e76a1e58a`。

本计划独占原24项及本次D阶段的执行顺序、状态与取舍；[Scene 性能卡](../scene/roadmap/performance-convergence-card.md)保留专项历史和正式测量口径，不另开下一步队列。本轮不因旧卡的选序切回兼容待办。[技术栈合同](../architecture/technology-stack-boundaries.md)、[播放切换事务](../architecture/playback-lifecycle-transaction-design.md)与各引擎合同继续规定正确性；[Web 当前状态](../web/current-state.md)等只记录各自事实。重要变更先在原所属设计补实施细则，再接入原设计登记，不另建重复owner。

<a id="深入实施-d1d62026-10-21"></a>
## 深入实施 D1–D14（2026-10-21）

来源：冻结 `039d164cb` 的优化Debug外部CPU/System/Metal采样、752组词法完整输出对照与75s真实Web音频端点退役反例；证据在忽略的 `apple-silicon-deep-analysis-20261021` 包。局部词法多线程收益不代表整App；GPU类别区间重叠，不相加为可省时间。方案经独立研究复核后获用户实施授权。

| 阶段 | 原owner内最小结果、退出与验收 | 状态 |
|---|---|---|
| D1 公共词法 | ASCII标识符直接判定，Unicode回原CharacterSet；不放宽token/source预算、不增cache。完整token/诊断等价，最近frontend门、整App冷暖与独立样本；先不叠加sampler扫描复用 | 已保留，`9042ed143` |
| D2 Web音频 | 端点表独占需求归属，surface/主App只派生聚合；goodbye/导航/租约/拆屏撤销，旧ACK/回包不得恢复。多消费者、重新注册、真实音频退役和现Scene路径回归。设计见Web进程合同 | 已保留：端点回收与75s原生验证通过 |
| D3 Range | 原scheme/loopback流式owner按有效区间seek+remaining分块；保授权/每块撤销/取消/短读/206/HEAD/416，loopback stop沿原owner关闭连接。有界内存与真实响应字节门，不能借此改路径/HTTP策略 | 已保留：真实scheme/TCP行为门通过 |
| D4 远程CSS | 先用可控延迟确认当前WebKit的@import关键路径，再决定是否调整。字体/级联/加载时序有兼容风险且无可证等价则保留现状；不得删字体换速度 | 候选实测停止 |
| D5 GPU | 审核连续inactive copy及同帧source capture能否在现版本/历史/发布语义内省略；先设计，不能删copy伪造发布或重开旧跨帧缓存。风险超过收益则记录STOP | 本阶段停止产品修改 |
| D6 调度与普通帧 | 暖窗口未见大Runnable积压，保持QoS/worker上限；只跟随新调用证据考虑循环取消/任务分配/普通帧重复工作，不为完成表格扩大修改 | 保持现状 |
| D7 采样器分析 | 同次activeSamplers仅对当前analysis覆盖／prepared源码做一对严格syntax解析，通道／用途证明共享局部Unit；不跨调用缓存、不借compiler规范化源码。同输入行为投影对照、最近用途门及代表实际播放 | 已保留：47项门、5对冷暖及代表运行通过 |
| D8 取消响应 | 原token接入capability layer／stage／material批次；完整join后传播取消，不进Rejection／负缓存，不取消共享producer，不动worker上限。先合同、真实叶取消反例，再隔离运行 | 已保留：9项门、组合播放与同daemon切换通过 |
| D9 Video启动库结算 | 原Manager合并完整SQLite基线与启动期动作；未知基线失败时仅持久化有版本增量，退出／重试／reset不丢动作或覆盖未见库 | 已保留：18种mode／65检查、最终Debug／Release零警告及独审通过 |
| D10 Release资源归因 | CI等价严格签名、无get-task-allow的原生生产daemon；先L资格，再唯一sample替代L→H→L，按实际端点分开CPU／VM／Metal与工具失败 | 已完成并独审：仅到owner／VM类别，无安全可删工作或retainer证据，不改预算／trim |
| D11 Web物理Space | 同一最小WK二进制A／B只差reassert，另测真实WebDaemon C；同页、真实手动普通桌面切换、连续RAF／timer与原生事件，不能用模拟通知代替 | 已完成并独审：A4／B6／C5事件不支持reassert为主要停顿原因，停止该方向产品修改 |
| D12 Scene资源关键路径 | 先沿既有Debug阶段日志＋启动外采样拆清launch／device／first-surface三链与真实join；有昂贵重复且完整身份等价才在原owner内小修、冷暖验证 | 已保留：562完整输出等价、5对局部／3对启动、独立L及最近行为门／独审；全仓两门存量失败另列，旧STOP不变 |
| D13 同次颜色分析 | 从最新2da624b21冻结，先量同canonical fragment的strict解析重复；一次不可变fragment／main／outputUses供原证明函数使用，上游颜色结论优先，失败仍原nil／false／unresolved | 已保留：56完整事实／90完整分析等价、5对局部材质分析约−12%、3对优化Debug首次H小幅改善；暖轮未证收益，独立L／独审通过，存量失败另列 |
| D14 切换后内存持有者 | 先验证外部分配栈／引用图正反控，再由实际L/H/L追踪allocation／retain owner；只修已定位冗余持有，保原总账、在途pin与有效暖缓存 | 取证／独审完成，0产品改动：所选旧H对象退役、暖缓存有界；剩余分配未证冗余owner，不重复总量测试、不清有效缓存、不新增Release诊断 |

每批列明owned源码/测试，构建和实际播放串行；子代理实现可并行，性能计量不与构建/测试重叠。Debug保现开发入口，Release无新增探针；真实媒体只读，用户偏好按精确任务值回收。保留低复杂度可靠局部收益，整体比例未知如实注明；性能或功能回归先修，不能机械追逐数值。阶段结果在本表更新，原24项历史不覆盖新事实。

D1：ASCII候选与前轮752组完整输出比较的源码逐字节相同；新门及frontend共78项（77通过、1项缺隔离fixture跳过），签名优化Debug、2938612768共20次启动/drain及独立3173418061截图/实际运行通过，独审闭合。5对冷/5对暖观察均同向，中位ready为−16.63%/−10.34%、主PID累计CPU为−31.06%/−14.31%；另一个Scene renderer最高392%CPU污染，不能称稳定整App或Release收益。主PID不含compiler helper，冷仅本任务编译缓存，原startUTC字段实为结束记录时刻；原数全保留，不筛掉不利配对。独立固定工作量实验仍支持低复杂度保留。

D4：实际WK自定义scheme的7臂资格中，恒假supports候选仍发原import请求；无恢复臂2请求/2响应、DCL1573ms，未跳过1500ms等待。有限最终字体/样式/层序相同不代表有收益；原FAIL及原数保留，未写产品，不外推真实HTTPS。D5新trace缺纹理内容版本/消费者证据；source capture含UV/颜色/PMA/tint/尺寸转换且建立publication，copy还承载固定pair/history/terminal preservation。未证明可省，不改GPU。D6暖调度无大Runnable积压；不升QoS/并发数，不重开旧缓存或另造任务平台。

D7局部资格：同一fixture的1／4／8槽，优化Swift下每400次投影wall-clock中位133.59／587.86／1679.14→28.42／62.78／116.10ms（各5交替对）。新增覆盖字典逐字节等价，相邻用途47项通过；不把局部耗时称CPU率或App提速。旧blur语义副本已退役，门直接编译真实purpose投影。

D7启动资格：受并行样本干扰的原记录单列保留；与另一会话协调停止App／构建后，签名优化Debug在2938612768上完成5对交替冷暖、20次正常退出，项目／包11份SHA一致，运行前后App身份一致。配对中位ready耗时冷／暖−4.44%／−7.35%，ready日志后主PID累计CPU快照−12.79%／−11.48%，所有配对同向；暖基线一轮明显偏高，仍不称正式稳定比例、Release／能耗／稳态或全进程CPU收益。冷仅本任务编译缓存，OS页缓存未清；三个时点未发现另一匹配App不等于全机连续隔离。

D8行为资格：9项测试通过，含两级join／后继批次停止／原错传播12检查、原source取消20检查，以及原视觉失败和真实属性consumer。取消只在准备批次边界生效，不进入variant负缓存／共享producer，也不能抢占已进入的单次编译／等待。旧测试装配4次前置编译FAIL保留，补真实依赖而非stub。组合Debug（-Onone）在2938612768／3173418061完成代表播放、零失败帧、正常GPU drain；75s同daemon测试两请求／两首呈现／单PID、最终launched、无failure并正常退出。30s未完成记录与临时driver误把终态写成ready的断言FAIL均保留；实际结果按真实launched枚举复核，不重跑掩盖。不据此宣称完整兼容、实际取消延迟或稳态性能。

D7性能App在D8复制／组合构建前已完成前后身份校验，不能拿后来的candidate源码树／-Onone产物归因D7。最终证据保留于忽略的`apple-silicon-sampler-cancellation-20261021`包；不在Release新增诊断、不放宽安全校验、不改作者样式。D6补查仍缺可归因self-cost，14标量桥接及短数组／字符串转换不另建缓存，原STOP不重开。

D9：冻结`8de80eb6e2`后仅VideoLibrary索引链扩展。真实SQLite与产品Manager／完整导入producer的18种mode、65项检查通过；故意移除两条existing-path context记录后，4项收藏／标签反例为false、8项对照仍true。独审发现并闭合该no-op意图遗漏；最终Debug／Release均构建成功且零警告，前驱6条隔离警告已按MainActor owner修正。测试隔离文件可读性／提示UI／播放等叶端，未运行完整App导入选择和播放UI，不声称所有故障或整App性能比例；收益是启动期普通save不再等待初始SQLite读，且不丢用户动作／未见旧库。无新增timer或Release探针，稳态writer不变。

D10：`4146aa75d`产品源码对应的最终Release（UUID `9577DD1D-88E5-3ADC-87E2-B8CCBDA088D9`）经CI等价嵌套签名／权限校验，普通生产Scene v2入口；主Instruments权限失败、限时退出后缺template，原FAIL保留，不能认领其CPU／Allocations表。唯一替代3次sample／vmmap及正常GPU drain／退出通过。L0→H→L1名义5s观察中，各5个rusage点按C postRead Mach参考端点换算跨度4.098／4.106／4.069s（保pre／post读取括号，不称内核精确记账瞬间）；daemon CPU为58.39／911.00／68.24ms/s、footprint238.91／838.20／381.94MiB（不含父App／compiler helper）。随后6s sample及后验VM单独计时，不替代先前稳态窗口；后验malloc dirty／fragmentation上升、GPU VM大致回落，只有类别线索，无分配来源／持有者证据。Metal有真实帧和3024×1964配置，但H／返L计时全0须标缺测，不能称GPU零成本。H request→prepared16.435s，最大可见resources→surfaces区间11.956s，含并行task／join和异步进度；新HOME中H首次，不是整机冷或全H miss，未采启动栈，不归因纯纹理解码／PSO。持续材质图／cursor／粒子调用有真实consumer，未证明可删，不重开旧STOP。下一次若推进，先拆清该资源区间原有两task／join，沿既有Debug阶段入口取证，不外推Debug比例到Release。

D11：A／B同二进制、同内联页、同正常desktop+1配置，B仅增加Space／activation时的窗口reassert；真实手动切换的4／6事件分别对应RAF停顿567／537／549／551ms与545／547／548／538／538／521ms。A没有reassert也会停约半秒，A／B原生heartbeat最大仅15.1／45.4ms；没有对应半秒主线程停顿。该单轮数据不支持通过删窗口重申解决此类停顿，B低8.5ms也不能称优化收益。三臂均单document、序列连续、零丢包；C经原WebDaemon v2可见确认→finalize→output-activity ACK后观察，5个匹配request的IPC Space事件对应RAF556／567／632／557／568ms；IPC接收时刻不是原生callback时刻，原summary／unified未采到该事件不等于未发生。C兼容脚本覆写hidden，不能以hidden=false证明原生WebKit未遮挡；activation高一档证据也不能当作finalize后的持续level。仅此macOS／WebKit、这一张无网络页、每臂一轮，未证明内部根因、作者样式／音频／主App最小化或所有设备；不做C减A的宿主开销估计。早期快捷键未引发真实Space的B01／C01仅保无切换数据，不算空间验证；有效人工轮无新增产品探针。此阶段不改进程隔离／窗口行为或增加运行时workaround。

D9–D11最终raw、工具与源身份、失败命令／收据、修正前后聚合及独审统一提取至忽略的`.artifacts/scene-evidence/runs/apple-silicon-storage-release-web-space-20261021/`（约1.6MiB，14天）。权限失败、未finalize的1.22GB ATRC不作归因数据；保原FAIL、三文件size／SHA及两份小metadata原文，其大载荷按已核范围清理，不宣称绝无可恢复数据。有效替代并非原trace完整等价副本。测试进程已退出；本轮临时App／DerivedData／样本／HOME／模块缓存按精确归属清理，不清理他人目录。

D12实施顺序：从`8aaca3336`冻结导出树构建优化Debug（明确-O／wholemodule及DEBUG，不能外推普通Release比例），隔离H／L输入、HOME和应用shader缓存，先重用现LAUNCH-STAGE／管线计时及同一生产Scene v2入口。模型阶段与资源阶段独立；旧3662790108的descriptor约7s不解释本次H=3042492564资源区间。原launch worker与两个各自串行GCD队列／NSCondition并行，device等待QuickJS资源需求规划；现device-join／first-surface-join日志还含join后处理，不当纯等待时间。先一轮H冷／同进程暖作归因资格；必要时仅补最短缺口的DEBUG计时，Release无新诊断。外sample若覆盖启动须记录采样重叠／工具开销，不能把inclusive栈计数当CPU比例。

D12局部实施：原始512KiB预算检查后，无CR源码复用原String；extractDirectives在完全无`#`时直接返回原源码及空指令结果，仍执行原tokenizer的注释／Unicode／位置和token预算逻辑。有CR保留原双替换，无CR复用原String；有`#`保留原指令扫描，无`#`跳过该扫描，两条件独立，不扩cache或改变解析／admission。先完整lexer输出A／B（含source、token、define、诊断全文），覆盖换行／注释／Unicode／指令／预算正反例并测固定工作量，再整App冷暖和独立作品实际运行。

只有新证据证明同完整资源／用途／版本或同次不可变输入的昂贵重复，且不需第二owner、长期缓存、安全豁免或作者效果变化，才实施等价复用并验证反例与独立样本；保原取消／join／退役，冷暖对照按低复杂度总体正向取舍，不机械用旧百分比淘汰。若主链是必要编译／解码、只剩已STOP或数据无法定位可删工作，保留新证据并停止产品修改，不扩为全样本或后台预编译。每个实际产品小批完成最近门、隔离运行和独立审查后再提交；原并行pbxproj不入批。

D12定位结果：优化Debug基线首次resource累计11040ms，其中catalog-decode23ms、capability至8835ms、first-surface-join至10825ms；同daemon第二次resource2527ms。8s／10ms的sample调用树指向capability内的词法／语法／源码规范化及helper等待，device在等脚本规划；并行variant累计时间不能相加作wall或CPU占比。初始HH及外采前快照实际有安装版App活动，保留原数仅作路径定位，不能称独占性能；外采结束观察还含符号处理，不把整个命令包络当采集时长。对照前按既有授权退出安装版与子进程，之后构建／局部测量／播放串行，正式六臂preflight／resume／exit快照未见另一匹配App／构建／sample，不代表全机连续隔离。

D12局部结果：H缓存294条record的588个canonical字段（88个独特字符串）中587个无`#`、全部无CR，仅为输入普查而非调用计数。562组两stage完整lexer投影（source、token全部字段、defines及诊断stage／code／message／位置／null）逐字段、完整压缩内容SHA一致；含真实源码、Unicode与相邻异常、CR／CRLF／LF、指令／注释、字节及分号token预算边界。原HEAD的identifier／number early-continue预算缺口是存量，本批不改变它，分号门不证明所有token类别的100k上限。五对交替优化Swift固定工作量：无指令组142.936→80.991ms、配对中位−43.34%；含`#`邻居组84.925→82.992ms，基线波动达8.73%，仅认未见明显退步。时间含lexer与checksum，非CPU率、App百分比或能耗。

D12启动资格：冻结`8aaca3336`与仅lexer变化候选，两个Debug产物同为-O／wholemodule、无debug dylib，构建零警告；现有签名／权限不更改，不冒称发行Release。三对BC／CB／BC、每臂新HOME及应用shader-cache、同daemon两次H：request→prepared首次中位12192→10922ms（配对−29.22／−11.48／−9.14%），再次4063→3866ms（配对+3.19／−4.86／−6.71%，不隐去较慢轮）；首次呈现中位12249→10979ms、再次4110→3935ms。输入页／OS／驱动缓存未清，第二H准备与旧H播放并存，只有此设备／输入／优化Debug的小规模资格，不能称稳定Release比例或纯cache收益。六臂12请求均首呈现、旧UUID资源退役、GPU drain／实际退出及App／输入前后身份通过；已存在的16条launch／source降级原因集合完全相同，不称样本完整兼容或零视觉失败。独立L=3766415113候选实际启动／呈现／drain通过。4项lexer门通过，frontend／dead-binding共88项中86通过、2项因缺隔离3141421197／retained requests fixture跳过，不把新562组投影代称这两个fixture。无新增缓存、线程、Release诊断或作者语义变化；其余同源analysis跨接口复用候选暂不叠加，保留本批低复杂度收益。

D12全仓门边界：carrier CPU门通过；目录／职责15项中3项失败，冻结8aaca导出树同3项及相同validators逐项复现（5个原文件未登记、同一UserShortcut职责计数／路径未同步）。测试断言门的2条报告亦在冻结基线652份tracked Python测试中复现，两树完整inventory一致；本批未引入，未修改这些旧登记或他人文件。依赖／产物／残留／代码健康／防御／设计／文档登记与预算／diff检查通过，不宣称全仓全绿。原FAIL、基线复核和独审同保。

D12最终原数、完整投影、失败／修正收据、工具与源码身份提取到忽略的`.artifacts/scene-evidence/runs/apple-silicon-scene-lexer-d12-20261021/`，14天有界保留。仅保必要结果，不保可重建App／DerivedData／HOME／shader和模块缓存；本任务进程退出后精确清理隔离根，不触碰原样本／并行pbxproj。

D13实施细则：本批先在原ColorTransferAnalyzer内复用同一fragment、默认strict参数／空runtime bounds的解析结果；原字符串入口仍仅计算各自证明，computeAnalysis局部共享fragment／main／outputUses，生命周期止于此次调用。上游input.sourceColorTransfer（可含runtime loop等已证事实）始终优先，局部解析失败不得降级／覆盖它；其他证明保各自原nil／false／unresolved。原证明正文保持唯一，不把通用compiler规范化后的不同输入、D7 prepared sampler语法或不同loop bounds混用；不加长期cache、owner、Release探针或改变持久cache schema。先冻结当前基线和完整颜色事实输出／异常邻居，再测固定工作量；有正向工作量收益且接口成本可控再构建同配置App，串行对照应用缓存冷／暖并做独立代表运行与独审。收益递减或语义风险增大则收窄，不重开旧STOP。已协调另一会话静态／运行窗口，所有build、test和sample计时串行；其BooleanVisibilityValidation／textclone及状态文档不入批。

D13结果：冻结2da624b21，仅覆盖3份owned Swift；并行9e9c03dda未带入构建／本批。56组完整颜色事实、90组完整生产computeAnalysis输出与基线逐值相同，所有证明有正反例；37个nil回退、37个非nil unresolved及16个其他上游结论的优先级不变，strict与有proven bounds结果仍分开。8段实际作者canonical fragment及8个Unicode注释／CRLF邻居，材质flags明确为合成矩阵，不冒称真实材质调用分布。每组8源码×8轮、5对BC／CB交替，含JSON投影和checksum：真实fragment选定颜色入口215.519→45.213ms（配对中位−79.13%），完整材质分析1678.396→1482.206ms（−12.08%）；邻居分别−80.94%／−12.67%。这不等于全App CPU、启动或能耗比例。

D13 App资格：同签名配置、-O／WMO／DEBUG、关闭debug dylib的两份隔离App，3对BC／CB／BC，H=3042492564同进程H,H、每臂全新HOME／应用shader cache；首呈现两臂中位10.734／10.595秒，配对−6.36%／−1.60%／−1.30%。暖轮−2.29%／+0.81%／+0.13%（后两轮慢约30／5ms），不认暖启动收益；数据页经身份哈希预热，非OS／driver冷启动。12个H请求及独立L=3766415113两臂均完成prepared／firstPresent、旧资源释放（第二H）、GPU drain／code0、实际退出／PID消失和原件／副本未变。H每臂原有2条launch／30条source failure逐条相同；L两臂各同一条source-domain-variant-dependent。不能称零视觉失败、完整兼容、普通Release、完整主App点击延迟或稳定启动比例。

D13验证与收尾：最近颜色合同／typed input／frontend／持久缓存／carrier CPU两组50＋85项执行通过（新增4项重复复验，1项缺3141421197隔离fixture跳过）；Debug两臂构建零warning。结构15项的3个失败（6个既有目录登记及UserShortcuts analyzer fleet）与test-assertions两条既有literal库存失配在冻结基线复现，不改并行来源或放宽门禁。依赖／职责防御／code health／设计／产物门通过；未跑广域无关GPU／图路由全部测试。静态和局部／App证据经同一独立审查者复核，保原失败和暖慢轮；必要日志、工具、完整投影、身份与失败收据提取至忽略的`.artifacts/scene-evidence/runs/apple-silicon-scene-color-analysis-d13-20261021/`，14天有界保留，停止后的隔离App／DerivedData／HOME／样本副本／缓存精确清理。下一批再判断分析／compiler规范化复用及切换后内存持有，旧STOP继续有效，不在本批顺带实施。

D14实施细则：沿S8与D10已知缺口先做工具资格，不把旧footprint升高认作泄漏。独立小型可调试fixture以明确分配caller、根→holder→buffer及释放caller作正反控，验证malloc_history／leaks memgraph的实际输出、退出、文件身份；工具参数以本机help及Apple内存分析指导为准。通过后再冻结最新已提交树，签名优化Debug保dSYM、使用进程启动时的外部MallocStackLogging环境，不向Release加产品诊断入口；与无stack logging的性能窗分开，记录工具对运行的扰动，不用诊断运行认领速度／footprint收益。只有原生产Scene v2请求准备、首呈现、finalize及旧资源释放后，才对L/H/L的具体地址、分配栈和引用链定位，区别既有有界CPU Program缓存、allocator驻留、GPU在途pin和旧Session／资源owner。先证明工具可用，拿不到caller即保FAIL停工；不重跑无归因总量循环，不全清缓存或修改资源／完整性预算。最小实现与反例在定位后再确定；有产品改动才补最近行为门、固定源Debug、隔离实际切换／drain及无诊断冷暖对照，阶段由独立子代理审查后窄批提交、不推送。设备窗口先协调，构建／采集串行，真实媒体只读，临时环境放任务隔离根；本批先拥有此计划及document_health_baseline对应单条调整，不动并行SourceNormalizer／varying与设计文件。


D14工具与运行资格：独立C正反控先保留MallocStackLogging=1默认为lite而不能导出full history的原始FAIL，显式full后证明分配caller、根→holder→buffer、释放caller与退出；实际Swift App再单独通过live分配栈／strong字段链资格。冻结4fc8e7cf7、匹配签名优化Debug与dSYM、构建零warning，以外部lite采集原生产Scene v2；它没有释放历史且较早分配缺栈，不能代表普通Release性能。首次L/H全callTree文本达16 MiB工具上限，失败记录及正常drain／退出保留；离线验证Session限定callTree后再完成L/H/L，未减少完整heap／类型地址／引用图采集。三阶段均在首呈现和finalize后采集，H及返L另等待匹配旧UUID资源释放，输入未变、GPU drain／code0／实际退出通过。此为单次诊断序列，不是普通Release冷暖或视觉对照。

D14持有者结论：完整heap分类逐阶段精确合计原生All zones；所选11个旧H关键地址在返L时均不再以同类型出现，包括Session、Surface、窗口、MetalView、两个loader、base images、脚本domain／handle、pass encoder与offscreen cache。Session／View／Domain等数量均1→1→1，资源lease为2→249→2；仅证明该范围退役，不宣称全部GPU／heap释放或无泄漏。采样source-map和字符串有实际preprocessor分配栈，根为既有preparationCache，受64 MiB／256项预算约束；不能外推全部字符串增量。最大purgeable组28,737,536 B（27.4 MiB）在H和返L均仅64 KiB resident／dirty；关联256 B RIP metadata的caller可追到纹理栅格化，但payload本身无栈，38条保守路径含假边，未证唯一强owner或冗余持有。诊断LiteZone明显增加驻留／碎片，不能据此解释D10普通Release返L的143 MiB增量。

D14收口：工具资格、实际Swift gate和最终L/H/L经同一独立子代理分别审查，无可行动产品缺陷；保留缺栈、Session限定callTree、lite无释放历史及所选地址范围限制。停止产品修改，不再跑只有总量的循环、不清有效暖缓存、不动预算／在途pin；0产品改动、0新增运行时开销，不认领内存或启动收益。必要memgraph、原生原文、工具正反控与失败、身份／输入清单及独审记录有界提取至忽略的`.artifacts/scene-evidence/runs/apple-silicon-scene-memory-holders-d14-20261021/`，14天保留；停止的隔离App／DerivedData／HOME／样本副本／缓存提取后精确清理。只提交本计划与对应文档预算，不带入并行源码／合同；后续仅有新的具体holder证据才重开S8。

## 目标、取舍与职责

用户目标是更快设置壁纸、属性准备更短、主窗口响应自然，以及长期播放资源消耗更低。保留独立播放进程、作者原效果、正常错误反馈、资源／路径／预算／生命周期安全校验；不做后台预编译、不增加 Release 常驻诊断、不默认提高 FPS、不降低图像质量、不引入第二缓存／资源总账／时钟／暂停真值。

保留判断按用户最新取舍：低复杂度、因果清楚、必要行为门与实际操作无回归、总体有正向收益的小修改可以保留，不机械要求每项都达到旧专项的某个百分比。安全和数据正确性是硬门；不可把稳定的非目标退步用其他指标平均抵消。正式稳定比例、尾部分布、功耗或全专项完成的声明仍需相应测量。噪声大时记录不确定性，修复测量条件，不抹掉已经证明的机制收益，也不把未测收益写成事实。

代码改动沿现 owner 完成：主 App 持有用户意图、持久化与共享媒体需求；播放进程持有桌面窗口／输入／执行；Scene 保持 authored → prepared Program/graph/resources → typed frame → Metal encode → 唯一 compositor。异步任务提交必须绑定原 request、generation、revision 与资源租约；晚到结果不得复活旧状态。项目默认 MainActor 隔离，`Task {}`、`nonisolated static` 或“后台队列存在”本身都不能证明耗时工作已离开主线程。

涉及持久化提交、跨进程协议、Activity 生命周期、显示时钟等变化时，实施前补齐所属现役设计的职责／数据流／失败／退出及 design gate；不能用本文的候选概述替代这些设计。局部数组复用、一次调用内值复用、等价算法顺序调整可按现合同直接做小修。

## 证据与这次采集到的数据

区分四类证据：**F** 为当前源码可证的触发／工作量；**H** 为历史冻结实验，注明输入与配置；**R** 为单一行为／真实操作验证；**P** 为可比较的优化产品性能结果。研究阶段的下表仅含 F／H；实施状态与新增验证见下节，不把计算次数当 profiler 测量值。

| 对象 | 本轮可证事实 | 解释边界 |
|---|---|---|
| 本机 | Apple M4、10 核（4P/6E）、16 GiB；macOS 27.0.1 `26A434`；Xcode 27.1 `27A9275` | 只读 `sysctl`、`sw_vers`、`xcodebuild -version`；不是 M1／8 GiB／最低系统验收 |
| 工程 | arm64；当前项目配置最低 macOS 26.0 | 发行实际嵌套二进制的架构、签名仍另验，不由配置推断 |
| Scene 启动 | layer、stage、PSO 三处最多 4 worker 固定 stride；总 stage 预算已有约束 | 可证明分工方式，不能证明 4 槽不足或每次发生长尾 |
| 管线缓存 | miss 后先完成 PSO，再同步 archive add／serialize／发布，最后返回 ready cache | 位于启动汇合路径；耗时和占比未知 |
| Web 输入 | 事件 monitor 加 30 Hz pointer 兜底；被动位置去重分属两条路径 | 名义轮询周期约 33 ms；不是实际 JS 投递量或能耗 |
| Web 频谱 | 常规 128 值在每 endpoint 各格式化一遍；约 30 Hz 投递 | 无背压时理论为 `3,840 × endpoint 数` 次格式化／秒；已有 latest-only 背压 |
| 共享封面 | 带 current artwork 的新 media generation 会提交 Web 转换尝试；成功产物最长边512 px、PNG≤1 MiB | 当前无 Web 消费者时仍会尝试；非法／超限／解码失败会拒绝，成本未测 |
| 网格探针 | Video／SIL 活跃网格每 2 s 查可见路径；已有 300 ms leeway | 每个活跃实例名义 1,800 tick／小时，不代表 1,800 次全库扫描；切模块会退役旧网格 |
| 状态栏 | 每 2 s 在主队列采样并更新图标，菜单关闭也执行 | 是否形成可见工作、CPU 占比与功耗尚未量化 |
| Video 索引 | 250 ms 合并后，主调用者仍等 SQLite 全表替换事务 | WAL、事务、连接复用已经具备；不是“尚未后台队列化” |
| 缓存／预算 | Scene 总账 `min(recommended/4, 3 GiB)`；decoded 同受总账约束；上传未提交 CB 上限 32 | 不能把 decode、pool 各名义上限相加，也不能删 GPU 完成等待 |

源码核对覆盖 App、Scene、Web、Video、共享播放、UI 与存储；扫描文件数不是覆盖率或性能结果。工作区存在并行 StaticModel／Puppet／shader 变更：涉及 `SceneMetalRenderer*`、`SceneMetalView*` 及其新文件的观察不得归入本轮成果；实际实验先冻结 owned 输入或等职责交接。

已核对[准备链收敛归档](../history/cross-topic/playback-preparation-convergence-2026-10-19.md)、[Scene 性能卡](../scene/roadmap/performance-convergence-card.md)及明确相关历史。旧链接产物复用五对冷启动中位 `4869→4331 ms` 仅属原优化诊断配置；暖启动无确定收益。上一批合作取消缩短过期工作的占用，函数内 memo 减重复投影，均不能外推本轮新提速。

## Apple 官方指导如何落实

下列来源于公开正文／WWDC，访问日期 2026-10-19；短摘要只作本项目决策依据，不照搬平台不同的样例。

| 编号 | 官方来源 | 对本项目的约束／启发 |
|---|---|---|
| A1 | [Apple silicon 调优](https://developer.apple.com/documentation/apple-silicon/tuning-your-code-s-performance-for-apple-silicon/)；[大小核调度](https://developer.apple.com/news/?id=vk3m204o) | QoS 表达紧迫性；动态分配独立工作；不绑核、不把所有工作升到最高优先级 |
| A2 | [高效 CPU 调度](https://developer.apple.com/documentation/xcode/scheduling-cpu-work-efficiently) | 先省重复工作、复用对象、事件驱动，再考虑线程；不自建无界线程池 |
| A3 | [减少启动耗时](https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time) | 分开冷／暖、进程加载、首窗和内容真正可用；少显示一个 spinner 不算提速 |
| A4 | [提升响应](https://developer.apple.com/documentation/xcode/improving-app-responsiveness) | 绘制／cell 配置不做同步 I/O；主线程只提交 UI 所需状态 |
| A5 | [减少磁盘写入](https://developer.apple.com/documentation/xcode/reducing-disk-writes) | 用 File Activity 找实际写入，合并重复提交；持久化原子性与退出落盘不能牺牲 |
| A6 | [减少 Timer](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html)；[主动闲置／App Nap](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html) | 需求消失就停工；保有明确兼容职责的兜底，不因 timer 存在就删 |
| A7 | [App Activity](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/PrioritizeWorkAtTheAppLevel.html)；[Process QoS](https://developer.apple.com/documentation/foundation/process/qualityofservice) | assertion 随实际工作配对；主 App 前台不证明 renderer／compiler 的调度合适 |
| A8 | [Metal 存储模式](https://developer.apple.com/documentation/metal/choosing-a-resource-storage-mode-for-apple-gpus)；[load/store](https://developer.apple.com/documentation/metal/setting-load-and-store-actions/) | 统一内存仍有带宽与同步成本；先证明后继不消费，再省写回 |
| A9 | [Apple GPU 优化](https://developer.apple.com/videos/play/wwdc2020/10632/) | 检查真实 pass 依赖、读写和寄存器压力；不全局改 half、不关闭 hazard tracking |
| A10 | [CAMetalDisplayLink](https://developer.apple.com/documentation/quartzcore/cametaldisplaylink) | 可用显示同步回调替代不合适的周期驱动；仍保唯一场景时钟和每屏生命周期 |
| A11 | [管线二进制归档](https://developer.apple.com/documentation/metal/metal-binary-archives)；[编译并发](https://developer.apple.com/documentation/metal/mtldevice/shouldmaximizeconcurrentcompilation) | 重用已编译结果；更多编译线程有 CPU／内存代价，不默认开启最大值 |
| A12 | [Metal 4 编译](https://developer.apple.com/documentation/metal/using-the-metal-4-compilation-api) | 可渐进采用；不为 API 新旧全面重写，不预编译未知作者内容 |
| A13 | [GPU working set](https://developer.apple.com/documentation/metal/mtldevice/recommendedmaxworkingsetsize) | recommended 值是性能相关近似，不是 App 独占 RAM 配额 |
| A14 | [Accelerate](https://developer.apple.com/accelerate/)；[vDSP stride](https://developer.apple.com/documentation/accelerate/controlling-vdsp-operations-with-stride) | 已有 FFT/vector 路径继续使用；先省分配与复制，不将小 FFT 搬到 GPU／Neural Engine |
| A15 | [降低内存使用](https://developer.apple.com/documentation/xcode/making-changes-to-reduce-memory-use)；[图像内存讲解](https://developer.apple.com/videos/play/wwdc2018/416/) | 缩略图用 ImageIO 按显示用途下采样；不降低实际壁纸纹理／静帧精度 |
| A16 | [异步视频取图](https://developer.apple.com/documentation/avfoundation/creating-images-from-a-video-asset) | 有界派生任务可异步完成与取消；放宽取帧容差可能改变画面，须单独裁决 |
| A17 | [WKWebView 隔离](https://developer.apple.com/videos/play/wwdc2020/10188/)；[原生媒体暂停](https://developer.apple.com/documentation/webkit/wkwebview/setallmediaplaybacksuspended%28_%3Acompletionhandler%3A%29) | 网页内容本已独立进程；换宿主不是换渲染器，原生媒体暂停不能代替 JS／CSS 暂停 |
| A18 | [Swift 并发执行机制](https://developer.apple.com/videos/play/wwdc2021/10254/) | 不把阻塞等待塞入协作线程池；异步不等于取消／有界／离开 MainActor |
| A19 | [Metal 联合归因](https://developer.apple.com/documentation/xcode/analyzing-the-performance-of-your-metal-app) | 同时看 CPU／GPU／display／thermal，先区别 CPU 等待与 GPU 饱和；外部 Instruments 不要求产品新增周期诊断 |

更底层的 [CPU Optimization Guide](https://developer.apple.com/documentation/apple-silicon/cpu-optimization-guide) 需要开发者登录与额外协议，未读取受限全文。公开文档足够指导当前高层优化，不假称已据芯片内部延迟表调优。

## 候选总览与阶段

P1 优先取得可行动证据；P2 在规模或实际消费出现时推进；P3 只保留取证／备选。优先级不是已确认缺陷等级。以下共 24 项，每项仍须先确认当前代码和原 consumer 没有变化。

| 阶段 | 候选 | 最小结果与退出 |
|---|---|---|
| 0：冻结与联合取证 | 启动 S1–S4；主线程 U1/U2；媒体 M1/M2 | 一次有身份的时间线和现有输入／输出基线，不先给全模块打补丁 |
| 1：启动优先、低复杂度伴随项 | 先 S1、S2，再按成本决定 S3；可穿插 M1/M2/W3/U6/U4 | 每次只改一个因果点；不把 UI 小修拖成引擎改造前置，不同时叠加 S1/S4 |
| 2：UI／存储与批量派生 | U1/U2/U3/U5/U7/U8/V1 | 持久化先补失败／退出门，保数据与外部文件变化；大库有实际成本再扩大 |
| 3：播放节奏与暂停／输入 | S5/W1/W2 | 原 owner 内完成状态设计，验证多屏／Space／恢复与下一次操作，再谈能耗 |
| 4：仅在新证据解锁后 | S4/S6/S7/S8/M3/W4 | 找不到实际 consumer／可省成本即停，不重跑旧 STOP 或扩缓存凑收益 |

没有硬编码“必须全改完”。每阶段完成最近门与真实操作后独立子代理审查；高风险项复审修订点。收益递减、两次有区分力实验不支持假设、或为微小收益必须增加明显复杂度时，保留证据并换方向。当前并行任务正在使用的帧／模型 owner 不抢改。

## 本轮执行状态（2026-10-20，冻结结项记录）

此表是24项的唯一处置记录；下方候选说明保留研究／改造前基准，不应据旧行号或旧成本再次立题。停止不表示成本为零，保留不表示已经测得全 App／功耗比例；没有实施的项不能称“优化完成”。本轮覆盖已结项，未来只有重开条件成立或用户明确提出下一阶段才推进。

| 项 | 处置与证据／未扩范围 |
|---|---|
| S1 | **实测后STOP**。99个去重PSO，原四worker；冷／暖warmup1213.937／21.759ms。有未开始任务时空槽累计仅1.816／3.061 worker-ms，未见可行动分组长尾。不改调度，未运行的CPU草稿已删。  临时Debug资格；冷matrix的runtime schema误填原FAIL保留，暖为同App／HOME direct runner重放，非双benchmark PASS；原收据见结项证据包`s1/`。 |
| S2 | **保留现状**。未取得System Trace runnable等待证据，不凭reader的utility QoS推定优先级反转；10ms保护循环与限额／取消保持。 |
| S3 | **实测后STOP延后归档**。第二个隔离资格窗：应用archive冷0/99 hit、warmup183.212ms，暖99/99 hit、21.988ms；serialize冷累计651.727 worker-ms，不是可省0.65秒墙钟。完整ready7716.029／2695.736ms，未隔离系统driver缓存，非整机冷／暖A/B。约0.17秒量级理想局部包络尚无消融；跨首帧保99个opaque archive与有界排队／取消寿命不合算，保原暖命中。 |
| S4 | **保留现状**。已有MSL single-flight；没有新证证明Metal内并发受限，不叠加最大并发或新Metal4后端。 |
| S5 | **保留现时钟**。原S1短窗195 submitted／194 presented、drawableMiss0、p95 33.333ms只证该窗；无新pacing故障。不为此加多屏leader／display-link协调状态，唯一VM／clock／history准入不改。 |
| S6 | **保留现状**。无新普通帧分配热点或prepared无consumer证据；旧world／overlay／MDL／material载荷STOP不重开，不加跨帧缓存。 |
| S7 | **保留现depth语义**。后继仍可能load共享depth，无末次liveness证明；不以store源码形状删写回或改memoryless。 |
| S8 | **已有保护，未重复实施**。单总账min(recommended/4,3GiB)、decoded子额及准备尾释放已在现代码，pool仍竞争总额；未发现可归因的长期holder，不升预算／全清暖缓存。 |
| M1 | **保留**。串行FFT复用工作区，84帧×6数组共18,816浮点严格等于基线；五组400次stereo分析均少2,400次分配请求／26,291,200累计请求字节。代价48k常见N4096驻留32KiB，最大128KiB；不声称RSS／能耗下降。 |
| M2 | **保留**。仅Web消费者需求派生PNG，独立Web revision与媒体epoch；Scene-only不转Web图，晚订阅／ABA／撤销不重启Scene源。真实Music经main→WebDaemon IPC→5监听，标题／PNG加载／进度成立；Scene原图与授权源保持，更多播放器未覆盖。 |
| W1 | **保留**。同surface原生event与30Hz poll共享被动坐标去重；真实方法原版重复RED→候选GREEN，遮挡／按钮／新surface反例通过。保真实hit-test和手势；benchmark的JS交互不作为原生全局monitor证明，本轮未作纯被动原生集成／能耗声明。 |
| W2 | **STOP本轮Activity改造**。暂停、prepared、activation、导航／拓扑与恢复须联合接纳，未测得稳定暂停持assertion的实际能耗；不增加token真值／恢复分支。 |
| W3 | **保留**。同一命令多个endpoint只格式化至多一次，全busy可零次；每endpoint序号／latest-only保持。另修退休／过期endpoint的旧completion继续flush，RED→GREEN且不污染同view新endpoint。单endpoint原本只格式化一次，现多一个短命引用对象，未声称普遍CPU提速。 |
| M3 | **STOP**。现poll≤1s还承担继承stdout子孙不EOF时的取消兜底；拉至remaining可把取消尾延至12s，需额外wake/reader owner，名义少唤醒不足以支持。静态反例，未冒充运行复现。 |
| V1 | **保留现后台有界路径**。已离主、2槽／精确帧／缓存合并；新async取消要job身份与精确generator结算，还跨U1清缓存寿命，无已证成本抵消复杂度。不修改取帧容差／质量。 |
| W4 | **保留已有策略**。一个空预热进程、30s TTL、压力退役已具备；无新真实命中节奏，不调TTL或扩预热。 |
| U1 | **保留稳态窄片，D9已补启动结算**。初始load前仅有版本增量，完整SQLite基线到达后由原Manager合并；失败不覆盖未见旧库。结算后immutable／一飞一最新pending，原SQLite队列／全事务／fallback；reset epoch与同步退出flush。有效fallback含[]优先旧DB，成功后才清；async返回不表示durable ACK。真实SQLite跨进程／读中断／失败／退出及显式导入反例通过。 |
| U2 | **保留旧metadata窄片**。JSON先发布、utility补缺header，generation／id／path及仍缺字段准入；同ID同列数的真实Waterfall／文字刷新、快照在途与reset反例闭合。23项行为与代表窗口通过。同步JSON／stat／save／格式保持，完整异步loader／writer STOP。 |
| U3 | **保留**。SIL single-flight、同viewport/id/path回包；Video/SIL最小化／离窗停原timer，恢复最多一次catch-up。34条真实NSWindow检查＋两probe门通过。orderOut通知不可靠的真实失败保留，普通隐藏保2s timer但零路径I/O／零发布，回显沿原cadence；不称全隐藏零唤醒。 |
| U4 | **保留相同图标复用**。相同GPU显示整数／外观不建NSImage、不赋button；首次／nil／外观反例通过。采样／菜单时序保持，采样迁移无归因不做，不称整机节能比例。 |
| U5 | **STOP本轮缓存迁移**。cell stat现状已核；未证明本地目录成本值得引入视口generation／外部增删校准。保现发现与最终存在性校验，不加常驻watcher。 |
| U6 | **保留**。复用已存在tag投影后排序，箭头结果／tie／搜索／边界与旧全库oracle一致；省无关比较，不加缓存，不外推App百分比。 |
| U7 | **STOP本轮异步cache迁移**。只读资格时23份cache总62,172B，中位2,118B、最大7,737B；不是延迟测量。没有已证等待，不给已修的stale呈现／作者返回再加消费代际或第二缓存；TTL／离线保持。 |
| U8 | **保留**。已合成阶段只筛一次，最终全值相等不发布，但每次清无效选择。真实didSet／merge／账号／失败历史门通过，删除意图同步，不延迟Web清理。 |

### 本轮验收与取舍边界

- 冻结产品输入为`55a13f4ec`（含最新并行提交）＋18份本轮产品文件SHA；最终提交文件逐一匹配。S1单独冻结于`f5d50dc4d`；不同窗口不拼成新旧App提速A/B。
- Debug `-O/WMO`与Release均BUILD SUCCEEDED；25个相关模块串行全通过，代码健康1328份Swift／1000行硬门通过。独立审查发现并修复U2晚到尺寸未通布局，以及snapshot在途的consumer缺口；原失败与修后门均保留。
- 实际Scene 2938612768应用archive冷benchmark PASS，暖同staged App／HOME新进程runner exit0，均ready、停止1→0、GPU排空。此处有临时Debug阶段归因，不能当普通Release启动比例。
- Web：CWAV＋自有3-endpoint PCM矩阵两样本A／100；5秒晚注册、8秒子frame导航后频谱继续。真实Music无合成PCM的CWAV与受管理3793879750均A／100；自有5监听页有标题、可加载PNG及递增position。受管理输入首次遗漏publication索引的原F39保留，补齐同代索引仅重定位临时root后通过，未删marker／放宽安全校验。grade不是全兼容或官方parity。
- 三引擎正式owner／IPC由Debug driver驱动，33/33检查通过：六方向切换、main阻塞期间独立播放／实际PCM继续、失败保旧、取消与进程退出；不是Release全场景、物理多屏／Space／sleep验收。
- CUA实际窗口目视核对3种图片比例80×120、160×90、120×80与AX尺寸文案，未见错位。该UI只证明呈现：macOS CFPreferences未采用磁盘预置偏好，不能把临时HOME当完整`.standard`隔离；U1 fallback／重启由独立domain的真实SQLite门验。已仅按本轮路径前缀清除遗留的测试CurrentWallpaper，不猜测恢复未知历史值；真实媒体未改。
- 实际Release按既有CI inside-out Developer ID／hardened／timestamp签名后，25个Mach-O闭包含arm64、18个自有arm64-only、Apple Events／Steam JIT／Sparkle权限通过。原始本地Xcode签名带get-task-allow的拒绝收据保留；最终CI等价重签通过，不修改项目配置。主binary开发flag与指定diagnostic symbols均零命中；未公证、发布或推送。
- Debug／Release各仍有冻结基线5条Scene并发警告（PreparedStaticModelResources:133、SceneDaemonProtocol:129/147、FrameDriver:433、PuppetAnimationPropertyPreparation:56），本批未新增，未抢改并行owner。未覆盖普通Release实际播放、物理多屏／最低设备／30min能耗、所有播放器和W1纯被动原生输入，不能写“全场景无缺陷”。

### 已提交的独立代码批次

| 批次 | 提交 |
|---|---|
| 路线／实施设计先行 | `55a13f4ec` |
| M1 FFT工作区 | `6d9860472` |
| U6 标签导航 | `49a3691ad` |
| U4 状态栏图标 | `7bacdc00f` |
| U8 下载投影 | `136be602f` |
| U3 网格探针 | `a4a0be6ba` |
| U1 索引保存 | `45144b9da` |
| M2／W1／W3 Web输入与媒体投递 | `e5da0385e` |
| U2 旧尺寸补齐与真实consumer | `62b24db57` |

冻结跨模块证据归入忽略的`.artifacts/apple-silicon-optimization-20261020/`；原Scene冷报告及其画面／运行证据由既有工具登记在`.artifacts/scene-evidence/runs/apple-silicon-optimization-20261020-s3/`。两包合计约19 MiB，均保留14天至2026-11-03；含原失败／配置／源与产物SHA／必要画面。字节及解压SHA核对后，清除本轮导出树、DerivedData、staged App、样本、HOME与无用探针；不保留构建缓存或测试实例。旧STOP重开条件见各项，不把此记录变成另一条活跃队列。

## Scene：8 项

### S1｜P1：有界 worker 动态领取独立启动任务

- **F／owner**：[PSO warmup](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPassEncoder+Warmup.swift) 98–113 行固定四组 stride；[layer 准备](../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability.swift) 373–399 行与 [stage 准备](../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability+ProgramFirstStages.swift) 61–67 行相同模式，已有共享预算。
- **取证／最小改法**：先只测 PSO 分组任务起止、剩余独立工作和空槽重叠。成立后由原四个 worker 领取下一个 index，保去重、结果锁、排序、负缓存、取消；后续 layer/stage 扩展另核全局预算，不新增线程池或就绪波次状态机。依据 A1/A2。
- **反例／验收**：少于四项、单个超重 shader、共享 library、同 key 失败、取消在途、已有壁纸播放；T1 与真实冷暖启动，比较总首呈现、编译 CPU／峰值及旧输出尾部。
- **停止**：不存在分组长尾，或领取开销抵消收益。旧 ready-request 调度曾使两次冷启动 `23778→30811 ms`、`25524→32075 ms`，已撤；此项不得恢复旧方案，须有不同机制证据。

### S2｜P1：编译子进程与管道 reader 的任务优先级

- **F／owner**：[CompilerProcess](../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneGenericShaderCompilerProcess.swift) 61–91 行 Process 未显式 QoS，reader 为 utility；[启动任务](../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/ScenePreparedDeviceResources.swift) 597–599 行为 userInitiated。不能据此认定 helper 在 E 核或发生反转。
- **取证／最小改法**：System Trace 看实际运行／可运行等待，再单独比较显式 userInitiated 的 helper 和必要 reader；不调 raw priority、不绑核，不提高常驻播放全部任务。依据 A1/A7。
- **反例／验收**：T2 的成功、拒绝、signal、timeout、诊断／驻留超限；旧壁纸同时播放与取消后无孤儿。比较 wall 与 CPU，不能以更高占用冒充优化。
- **停止**：无可归因调度等待或旧输出变差。10 ms semaphore 等待还执行资源保护；不得删除或拉长预算检查来省唤醒。工具链资格缓存的旧 STOP 不重开。

### S3｜P1：首次可用 PSO 与缓存落盘解耦的资格

- **F／owner**：[PassEncoder](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPassEncoder.swift) 624–630 行 make PSO 后同步 recordReadyOutcome；[archive](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPipelineBinaryArchive.swift) 106–125 行 add／serialize／移动／prune 后才返回 warmup。UI 未必阻塞，启动汇合仍会等。
- **取证／最小改法**：分开量 load、PSO、add、serialize 与发布。若确占关键链，在同 launch owner 内先登记可用 PSO，把有限缓存发布延到首呈现后；保持条目／字节上限、原 key、损坏回退与取消退出。没有显著等待就不引入队列。依据 A3/A5/A11。
- **反例／验收**：T1 补发布失败／退出／取消；下一次暖命中、损坏自动重建、同源并发发布和无临时文件泄漏。落盘失败只损下次命中，不能影响当前画面；延后工作不得重新编译作者内容或在主线程 drain。
- **停止**：写出不在关键链，或短收益需要长期后台状态／显著 archive 峰值。当前没有此项 A/B，不能承诺固定提速。

### S4｜P2：Metal 内部编译并发与外部四槽的叠加

- **F／owner**：当前未设置 `shouldMaximizeConcurrentCompilation`；[MSL library single-flight](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPassEncoder.swift) 674–721 行已经缓存完整 MSL 成功／失败并等待同源结果。
- **取证／最小改法**：先确认 Metal 编译占比；仅在隔离候选进程比较默认与开启，记录 `maximumConcurrentCompilationTaskCount`、RSS、CPU、首呈现及旧输出。一次只变 Metal 选项，不提高外层 worker 数；不在共享 active device 上临时来回切设置。依据 A11/A12。
- **反例／验收**：T1，冷暖缓存与重材质／轻场景。不得再加 library cache 或引入全量 Metal 4 迁移。
- **停止**：编译占比低、争核／内存更重、只有局部 compile 更快但用户等待无改善。

### S5｜P2：显示同步帧驱动

- **F／owner**：[FrameDriver](../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift) 13–19、121–132 行为 30/60 FPS 单次 Timer，busy 间隔为目标周期的 1/8。该事实不证明当前抖动。
- **取证／最小改法**：先联合看 callback、busy、drawable wait、GPU 与 actual present。需要时在原 Session 接入 CAMetalDisplayLink 的一次共享 admission，保持唯一 sceneClock／VM／粒子推进，各屏消费同状态。依据 A10/A19；先修订原 frame-admission 设计。
- **反例／验收**：T3；30/60 FPS、60/120 Hz、不同刷新率多屏、拔屏、Space、sleep/wake、暂停首帧有限重试、缺 drawable 恢复、history 单帧在途。检查结束后下一次启动无残回调。
- **停止**：现节奏已足够，或新显示 leader／多屏协调状态成本超过收益。不能按每屏回调重复推进世界时钟，也不能放松 GPU 完成与历史门。

### S6｜P3：只有真实热点成立才省帧内投影／短命容器

- **F／owner**：[FrameDriver](../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift) 207、261–280 行构造／合并帧表；[纹理组装](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneFrameLayerTextureAssembly.swift) 13 行起叠加动态来源。部分粒子 parent 表已有 consumer 需求门，不能重复做。
- **取证／最小改法**：先定位当前普通优化配置中的分配 caller／CPU 占比。仅由 prepared demand 证明没有消费者时跳过投影，或做同调用内复用；依据 A2/A18，不建立跨帧 publication cache。
- **反例／验收**：T3/T4 与动态资源、属性、JS 引用 identity、事务失败回滚；实际 renderer 消费必须被触达。每帧表数量不能代替整进程成本。
- **停止**：只有旧累计分配数字或需要改变值 identity／回滚基线；overlay 容器、旧材质帧载荷等 STOP 未取得新资格不重开。此处只是取证任务。

### S7｜P3：末次 depth 写回是否确无消费者

- **F／owner**：[MainPassEncoder](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneMainPassEncoder.swift) 106–115 行 color/depth store，后续重开会 load；模型帧路径当前由并行任务修改，暂不实施。
- **取证／最小改法**：从实际命令与资源依赖证明“末次 depth 无后继读取”，再筛末 encoder 的 dontCare；先不改变 allocator／storage mode。依据 A8/A9。
- **反例／验收**：T4；offscreen 插入、主目标重开、背景 capture、模型／图像共深度域、shadow、下一帧 history。Color 中间结果和需要后续 load 的 depth 必须保留。
- **停止**：没有真实 liveness 证明或是旧“空 main pass”观察。空重开旧筛未命中真实无 draw consumer；不能全局改 memoryless／store 或重排作者 pass。

### S8｜P2 取证：切换后的内存持有者与统一预算

- **F／H／owner**：[总账](../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneResourceBudget.swift) 10–35 行约束 GPU 与 decoded；[目标池预算](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneOffscreenTextureResidentBudgetPolicy.swift) 16 行起另限 pool。历史轻重切换返回轻场景 footprint 上移约 25.4/47.9 MB，但 GPU allocated 恒约 94.3 MB，不能直接认定泄漏。
- **取证／最小改法**：依据 A13/A19，先定位 allocation／retain caller，区分在途 pin、有效 cache、allocator 驻留、compressor 和真实遗留 owner。只修已定位持有者，复用原总账和 memory-pressure 路径。
- **反例／验收**：T4；退出 drain、pin 归零、cache 平台、内存压力、失败准备和多次轻重切换，保有效暖启动收益。三引擎交接期间两个进程的峰值要一起观察。
- **停止**：无 caller 证据；不重复整轮无归因切换，不清空所有 cache、不调大安全预算、不把 recommended 工作集当独占 RAM。

## 共享媒体、Web、Video：8 项

### M1｜P1：FFT 工作缓冲复用

- **F／owner**：[统一频谱分析器](../../MyWallpaperX/Core/Playback/SystemAudioSceneSpectrumAnalyzer.swift) 79 行复用 FFT setup，但 216–217 行每次分配 real／imaginary，输入窗也有临时准备。
- **最小改法／依据**：先用 allocation 计数及既有音频输入确认成本，在同分析器复用串行工作缓冲，仅尺寸变化时调整；不改变窗函数、频带、包络、输出数组所有权。A2/A14；不搬 GPU，不额外启动采集。
- **反例／验收**：T5；左右不对称、换采样率／窗尺寸、静音、停止重启，连续帧不能残留前帧数据；真实音乐对照 Video/Web/Scene 柱形与环形，作者样式不变。
- **停止**：缓冲共享引入竞态或保有内存明显抵消收益。局部少分配不称整体能耗完成。

### M2｜P1：按 Web 消费需求生成歌曲封面

- **F／owner**：[SystemMediaService](../../MyWallpaperX/Core/Playback/SystemMedia/SystemMediaService.swift) 390–405 行在新 media generation 且 current artwork 非空时提交 Web 转换尝试；当前订阅仅 needsMedia，Scene-only 也会尝试。[WebArtwork](../../MyWallpaperX/Core/Playback/SystemMedia/SystemMediaWebArtwork.swift) 已有解码／合法性和512 px／1 MiB限制。
- **最小改法／依据**：原 subscription 区分是否需要 Web artwork；首个 Web 消费者晚到时对当前原图按需生成一次，无 Web 时省转换和额外 revision。只变 Web artwork 需求不调用 `reloadSource()`，不推进媒体 epoch／重启或清空 Scene 会话；转换回包另核当前 Web 需求租约／revision。仍由同一 artwork owner，Scene 原图／调色板保留；A2/A15。
- **反例／验收**：T6 补 converter 计数，Scene-only 零 Web 转换；Web 晚订阅出当前封面；最后 Web 退出拒绝在途回包，重订阅不接收旧需求结果；换曲 A→B→A、清空、坏图、授权拒绝／恢复。Scene 持续订阅时 Web 加入／退出不得增加 source start/stop 或清空 Scene snapshot。真实 Music 与系统来源均验。
- **停止**：要新增长期缓存或第二媒体采集者。若跨进程需求类型变化，先补原媒体协议的兼容／清空设计。

### W1｜P2：Web 被动鼠标位置共享去重

- **F／owner**：[Monitors](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+InputForwardingMonitors.swift) 22 行起同时用事件和 30 Hz 轮询；[Forwarding](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+InputForwarding.swift) 12 行起两套位置／throttle 状态；轮询先做原生 hit test。
- **取证／最小改法**：计同一 surface 的原生采样和 JS 被动位置投递，先共享已投递位置，减少重复 JS；保按下／拖动／抬起、hover preheat 和兜底。依据 A6；首批不删／降 30 Hz。
- **反例／验收**：现测试缺原生两路径行为门，需补事件 harness，再真实验 Finder、覆盖窗口移动、外部拖入、多屏、Space、monitor 恢复。指针静止但窗口移到其下时仍必须清 hover；不能把坐标去重简单移到 hit test 前。
- **停止**：无法保持命中与手势安全或没有重复投递；不能用“少轮询”替代完整输入语义。

### W2｜P2：稳定暂停时的 Activity token 生命周期

- **F／owner**：[Lifecycle](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+Lifecycle.swift) 11–16、42 行持 userInitiated Activity，pause 243–246 行未释放；停止／surface teardown 才结束。
- **最小改法／依据**：先限定已完成准备、明确暂停且媒体门完成的状态，按既有生命周期配对释放／恢复前重获；保候选装载与激活期。A6/A7，不把“主窗口隐藏”视为壁纸没有需求，outputActivityAllowed=false 不自动等于 JS 已停。
- **反例／验收**：T7/T14，加真实 host token 状态门；暂停中导航、WebContent 重启、恢复连选、激活失败回滚、锁屏／Space；比较暂停 wakes、App Nap 与恢复首呈现。
- **停止**：恢复迟滞或可见输出／媒体退步；不全局禁用或强制启用 App Nap。

### W3｜P2：一次频谱推送只格式化一次共同数值

- **F／owner**：[FrameReply](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+FrameReply.swift) 118–140 行每 endpoint 对同一 128Float 重复格式化，已有每 endpoint 一个在飞和一个 latest pending。
- **最小改法／依据**：命令内惰性生成共同 immutable 数值 body，endpoint 保各自序号／定向包装；全忙时不提前格式化。只做短命值复用，A2，不改精度、不跨帧缓存。
- **反例／验收**：T7 加真实 FrameReply 多 frame／slow endpoint 数值、序号、清零屏障、导航拒收门；不能只发给 audio listener，因为还有公开 `wallpaper-audio-spectrum` 事件消费者。真实音乐长播和 iframe 内容均验。
- **停止**：单 endpoint 纯增成本或没有实际多消费场景；不宣称修复未知长播停顿。

### M3｜P3：歌曲 helper 等待循环的空唤醒

- **F／owner**：[SystemMediaSource](../../MyWallpaperX/Core/Playback/SystemMedia/SystemMediaSource.swift) 272 行起 poll 最多 1 s 返回一次，心跳 deadline 12 s；helper 常规约 2 s 一条。取消已有 terminate／0.5 s KILL 与 pipe EOF。
- **取证／最小改法**：先验证 EOF／取消可靠唤醒且确有空 poll，再用剩余心跳 deadline 等待；不弱化心跳／ACK／预算，不加第二 timer。依据 A6。
- **反例／验收**：T6 的 source 门，补 TERM 忽略、继承管道未关、部分帧、EINTR、cancel-launch 竞态；退出墙钟不得退步。
- **停止**：任何退出边界需复杂补偿或收益不可归因。它不是引擎启动／FPS 优化，不顺带改 Music PID 查询节奏。

### V1｜P2：视频派生图像的有界异步完成与取消

- **F／owner**：[CachePipeline](../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+CachePipeline.swift) 205 行在并发 utility 队列等二槽 semaphore，263–273 行异步取图后同步 wait；已有缓存、同路径合并与 generation。
- **最小改法／依据**：原派生 owner 维持二槽 admission，用 completion／异步取图释放等待线程，并取消不再需要的 generator；保候选时间、400 px 缩略图、4096 px 静帧和 cache key。A16/A18；不放宽静帧零容差、不降精度。
- **反例／验收**：现门缺该 helper 的行为覆盖，补可控 generator 的完成一次／取消／坏媒体／后备时间；删除重导入同路径不得写旧 cache，系统静态壁纸提交身份保持。隔离少量／批量导入比线程、完成时间和取消后写入。
- **停止**：需新建常驻 pipeline/cache 或正常小批量成本退步；不能声称改善稳态 Video FPS。

### W4｜P3 仅测量：已有空预热的净收益

- **F／owner**：[WebDaemonHostAdapter](../../MyWallpaperX/Core/SteamWorkshopWeb/Process/WebDaemonHostAdapter.swift) 151、213 行已有一个空 prepared process、30 s TTL，84–88 行 memory pressure 退出；没有 WebView／媒体需求／作者编译。
- **任务／依据**：记录真实切换节奏中的预热命中、空进程保有时间／内存与冷切换等待，评价现策略净收益；A3/A6。只在已有策略内调参需要另有对照，不默认延长 TTL 或重复补热。
- **反例／验收**：T14 加 TTL 精确边界、hello 前后接管、取消和压力退出；保下一次请求的 UUID 与进程退出闭环。
- **停止**：无新使用数据，维持现状。“加 TTL／压力回收”已实现，不能再作为新优化。

## UI、列表与存储：8 项

### U1｜P1：Video 索引事务不再让主线程同步等待

- **F／owner**：[Persistence](../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+Persistence.swift) 22–41 行合并 250 ms 后仍在 main 调 save；206–214 行同步 store／失败回退；[IndexStore](../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperIndexStore.swift) 113–128 行 queue.sync 全表 DELETE／INSERT 事务。
- **最小改法／依据**：MainActor 捕获值快照，交原 store 串行队列有序提交；失败回原 fallback，保存 revision 防旧失败覆盖新成功。首批不改增量 SQL、不换数据库。A4/A5；先补持久化提交／退出设计。
- **反例／验收**：T10 只是相邻门，必须新增真实 SQLite harness：A→B、A 迟到失败、reset 排序、不可写 DB、立即退出后重启。真实退出／reset入口使用 `WallpaperManager.flushPersistentState()`（Persistence 460–474行），其有序 flush 不能靠 fire-and-forget 替代。
- **规模／停止**：隔离 1k/10k 值索引看 main 等待、事务写量和交互；若小库成本可忽略，不扩到整套增量存储。数据丢失／旧回包复活是硬失败。

#### U1 实施细则（2026-10-20保存；2026-10-21 D9启动结算扩展）

D9修复此前明确保留的启动整库竞态，覆盖读取期间导入／删库／收藏／标签／个人设置／派生更新及退出。Manager仍是唯一库与用户动作owner，Store原串行队列仍是唯一SQLite执行owner；不增加timer、不禁用操作、不使普通save等待初始read。Store完整读取须终结于SQLITE_DONE，并在同次读取携带原library_initialized（含已初始化空库），不能把读失败当空库。完整可解码fallback（含[]）仍整体权威，坏fallback不冒充空库。

未知基线期间，Manager保存一次性的按规范化路径变化：新增记录作为“不在旧库时的候选”，只将明确编辑的字段覆盖同path旧项；SQLite已有项保稳定ID／未编辑字段。标签记录逐标签增删，保留未见的旧标签；全库标签改名／删除和清预览路径作为有序屏障，避免只修改已见记录。屏障之间同path变化合并为一份，删除保tombstone，删除后重加以较晚动作决定。初始化种子单独保存，仅未初始化库可采用；后台派生回写不把种子变成用户新增。当前快照恢复与真正新导入保各自来源，个人设置导入明确覆盖title／favorite及追加tags；路径命中后修正选择／current／pending引用到稳定ID，不重新发起播放。

未结算时autosave只保存version=1的启动变化到同UserDefaults owner的独立键（不伪装成完整Wallpapers fallback），并沿原Store重试一次读取；只有后续既有save／flush／下次启动触发重试，不循环或加timer。完整基线成功后主线程一次合并并发布，转回原有界writer；成功提交当前完整快照才清增量／fallback，失败则保完整fallback及原增量。加载generation独立撤销迟到回包；reset先撤generation／增量，再按原Store顺序清库并保存fresh状态。退出在原队列同步读完整基线、合并再全事务保存；读取仍失败则保旧DB并持久化变化，供下次恢复，不写半库。

recent在未知基线时不得按临时库裁剪；完整结算后再归一化。损坏或未知版本增量保留原始字节到一个有界隔离键并明确提示，不能解释为空动作或清空旧DB；可恢复完整DB与本次新动作，不承诺恢复不可解码的历史动作。格式仅承担尚未完成的启动恢复，不是长期第二索引；无未结算变化时不写空journal。最近门必须使用真实SQLite／产品合并方法，覆盖A+B、删后重加、同path字段与稳定引用、空库／种子、标签屏障、recent、读中断／失败重启、无主callback的退出及reset；保原有界writer／fallback回归。不据此宣称所有存储故障或性能验收。

稳态保存保留U1原合同：主线程捕获不可变快照与revision／reset epoch，至多一个在飞及一个最新pending，原utility串行队列执行原全表事务／WAL；结果只更新同epoch／当前revision的fallback，旧失败不覆盖新成功，旧成功不清新fallback。退出同步flush排在已有事务之后，不依赖主callback；reset撤pending并沿原队列reset→save。原SQLite事务回滚、有界合并、fallback含空库、旧回包和跨进程重启门继续保留。此前只保留稳态优化的阶段已结束，启动变化按上方D9合同结算，不再沿未结算临时数组全量保存。

### U2｜P1：SIL 首次装载和保存都沿唯一快照 owner

- **F／owner**：[DetailHost](../../MyWallpaperX/Shell/AppKitDetailHostViewController.swift) 23–26、89 行初始化即访问 SILService；[SILService](../../MyWallpaperX/Modules/StaticImageLibrary/Core/SILService.swift) 117–160 行同步 JSON／旧图片 metadata，177–191 行全路径 stat 和缺失后保存。后台补尺寸 save 闭包仍读 live wallpapers。
- **最小改法／依据**：现 JSON 格式不变，后台读取／补 metadata／检查后回 MainActor 以 load generation 加库状态 revision 提交，导入／删除／reset 均改变后者，晚到装载不得覆盖新修改；保存捕获 immutable 快照，由单个串行 writer 合并，reset／退出 flush 进入同一有序提交边界。先消除非图片首窗的同步 I/O；只延迟 singleton 订阅不足以解决首次打开图片库。A3/A4/A5。
- **反例／验收**：T10 外补真实装载／writer 门；旧缺尺寸库、装载中导入／删除／reset、慢卷／离线卷、保存失败／退出。异步不能把暂不可达文件错误视为用户删除；保原缺失提示与合法恢复语义，任何改变须明确设计。
- **规模／停止**：齐全／旧格式各 1k/10k 元数据，媒体用自有小 fixture／隔离副本；分别量首窗和首次进图片库。无实际等待时不迁移数据库或引入新缓存。

#### U2 实施边界（2026-10-20）

先资格测量现有 JSON／旧尺寸补全／路径检查的成本，再决定保存与首次装载分别是否值得异步化。异步 writer 若实施，捕获原格式的不可变值，使用一个串行提交 owner、有界最新 pending 与 reset epoch，必须把真实 App 退出和库 reset 接入有序 flush／remove；后台闭包不得读取 live wallpapers。首次装载不能仅因期间有用户修改就整份拒绝，也不能直接覆盖当前库：须合并期间的增删改，保个人设置导入按路径合并及标签语义；旧 metadata 只可补当前同 ID／path 的未修改字段。该合并复杂度超出已证等待收益则停止装载迁移，保留简单保存收益即可。缺失、权限／离线不可达须分开，不能为优化扩大删库范围。不借此变更 JSON 格式、SQLite 化或另造持久缓存。

U2本轮资格后只推进局部旧 metadata 补齐：JSON读取／解码与库发布保持原顺序，缺尺寸项捕获不可变(id,path,原尺寸)值后在utility读header，主线程只补同id/path且目标字段仍缺失的值，保留期间标题／标签／lastUsed等用户修改。一次准备generation在load/reset撤销；失败不删记录、不覆盖已有尺寸，回包后沿原save同步保存，普通save格式／退出语义不变。首次完整元数据库不建后台任务；该片不引入异步完整loader、writer、合并delta或新数据库，也不把资格中约709ms外推真实首窗收益。需要等全量后台metadata才能显示网格的方案禁止。

### U3｜P2：可见路径探针停启与 SIL single-flight

- **F／owner**：[Video grid](../../MyWallpaperX/Modules/VideoLibrary/UI/AppKitLibraryGridView.swift) 885 行、[SIL grid](../../MyWallpaperX/Modules/StaticImageLibrary/UI/SILGridContainerView.swift) 444 行每 2 s 后台查可见项；Video 已有在飞门，SIL 缺。未见按窗口可见性停表，旧 controller 离场则释放。
- **最小改法／依据**：SIL 补同 owner 在飞和完成身份复核；真正离窗／最小化时停现 timer，重新可见即时探测。全遮挡是否停先验证通知可靠性，不把桌面 renderer 也一并停掉。A6；不新建全库 watcher。
- **反例／验收**：T11 目前偏 Video，补 SIL、在飞离窗再回、同 ID 换路径、排序、外部删除／恢复。正常／慢卷观察 10 min 可见与最小化的批次数及叠加。
- **停止**：恢复反馈退步或只能靠新全局观察平台实现；2 s 是活跃检测周期，不能直接设长周期掩盖问题。

### U4｜P2：状态栏先省相同图标，再测采样体

- **F／owner**：[StatusBarController](../../MyWallpaperX/App/StatusBarController.swift) 56 行每 2 s 主队列 refresh／update；75–97 行同百分比仍新建图标；[SystemMonitor](../../MyWallpaperX/Core/System/SystemMonitor.swift) 66 行起采 CPU／VM／网卡／GPU registry。SMC 温度已不在高频路径。
- **最小改法／依据**：先按已显示百分比及外观状态省重复绘制；采样本体若有成本，再由原唯一串行采样 owner 离主采集、主线程发布。菜单打开仍完整更新；A2/A4/A6。
- **反例／验收**：需轻量采样／图标投影门；nil GPU、暗亮模式、网络差分首样、菜单打开的即时新鲜度、并发重入。固定播放 30 min 观察采样 CPU／wakeups／重绘次数。
- **停止**：只减少代码调用却没有实际绘制／开销，或后台采样引入差分竞态。先不做第二套“菜单／图标”监控器。

### U5｜P2：Online cell 只消费下载状态，不同步探盘

- **F／owner**：[OLBrowserGrid](../../MyWallpaperX/Modules/OnlineLibrary/UI/AppKitOLBrowserGridView.swift) 246、267–272 行 cell 配置／刷新调用 isItemDownloaded，对未知 ID fileExists，命中还会发布集合变化。已有进度 throttle 与定向刷新。
- **最小改法／依据**：cell 消费服务现有 downloadedIDs；初次／页面进入／显式刷新，以及视口中新出现的未知ID，都由原服务合并后台校准，同一视口不反复探盘、不增加常驻watcher。提交绑定 generation 和下载集合本地修改 revision，扫描期间下载／删除事件须合并或重扫，旧集合不得覆盖新修改；真实点击播放仍最终核文件。A4，不能因缓存优化删存在性校验。
- **反例／验收**：T10 相邻门外补目录校准；页面保持打开，外部添加／删除后滚入、滚出再滚回；扫描A在飞时下载B完成，A不得移除B；另验搜索换代和旧点击。滚动未下载卡片时 main File Activity 不再反复 stat。
- **停止**：目录很小且成本无贡献，不增加持续 watcher；不让外部文件永远无法被发现。

### U6｜P2／极小：SIL 标签键盘导航先筛选再排序

- **F／owner**：[SILService](../../MyWallpaperX/Modules/StaticImageLibrary/Core/SILService.swift) 410 行方向键先 sortedWallpapers 再筛 tag；329 行已有 `sortedWallpapers(forSILTag:)`，网格已用。N 大、标签 K 小时做 N log N 而非 K log K。
- **最小改法／依据**：复用已有标签投影，不添缓存／导航 owner；A2。先验证 comparator 对并列项稳定，过滤与排序可交换的条件成立，再改一处调用。
- **反例／验收**：T10 加真实方向键输出，tag／search、同名／同排序值、首尾、跨列、无选中。不要顺手改删除后邻选的 `resolveNextSelectionID`。
- **停止**：排序不稳定导致相对顺序不同；先修或限定等价性，不能仅据复杂度公式认领 App 提速。

### U7｜P2：Steam 详情缓存 I/O 与呈现隔离

- **F／owner**：[DetailPresentation](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+ItemDetailPresentation.swift) 46 行冷详情读 cache；[DownloadSelection](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+DownloadSelection.swift) 177 行读 metadata/cache；[LibraryRecords](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+LibraryRecords.swift) 162 行同步 Data／JSON；网络完成后也同步保存。
- **最小改法／依据**：复用单一 cache，内存已知详情先显示，后台读写以 item／消费方／generation 提交；TTL、过期后台补全、离线展示、作者来源沿原常量和合同，不在此重设。A4/A5；nonisolated static 不等于异步。
- **反例／验收**：T12 的隔离 HOME 门补 A→B→A、关闭、下载／浏览详情互换、坏缓存／过期／网络失败保旧值；快速开 100 项时区分磁盘读与网络等待。
- **停止**：小 JSON 本已很快，或要增加第二长期缓存。已经修好的 stale 展示／作者返回不能回退为前台 loading。

### U8｜P3：Steam 下载列表一次提交只派生一次

- **F／owner**：[Service](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService.swift) 548 行合成 failed intents，随后 [DownloadFiltering](../../MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+DownloadFiltering.swift) 12 行再次合成；didSet 有一次重入，displayed 数组相等未抑制发布。progress 已独立，失败历史最多 100。
- **最小改法／依据**：同 owner 内“已合成记录 → 筛选排序”私有阶段复用，最终相等不发布；必要时只合并同一 main turn 的派生。A2/A4，不延迟 downloads 删除意图本身，Web store 清理依赖它。
- **反例／验收**：T13；账号切换、失败重试、ready 不被旧失败覆盖、清历史、过滤／排序／搜索和选择消失。1k/10k 自有记录观察合成／排序次数与可见响应。
- **停止**：正常规模成本很低或抑制发布吞掉实际状态；不建持久索引，也不声称每个进度 tick 都全量排序。

## 已完成、停止或不建议的方向

以下不是 24 项待实施任务。重开须先有新的实际 consumer／成本证据，并引用原停止原因；不能把上下文遗失当新发现。

| 方向 | 当前事实／原结论 | 后续边界 |
|---|---|---|
| 共享上传 queue／批量 mipmap 与 BC conversion | 已按设备复用；批提交／32 未提交上限／完成失败 identity 已具备 | 不删完成 wait；新瓶颈需具体 conversion／提交证据 |
| 全部静态 TEX shared→private | [旧筛](../scene/history/static-tex-storage-screen-2026-10-15.md)相同 3427×897／5 mip：预算峰 18,711,040→37,422,080 B，额外 copy 中位约236/411 µs，STOP | 统一内存不等于 private 总更快；不得重跑同输入挑好结果 |
| shader／模型／descriptor 扩缓存 | 资格缓存、MDL重复验证、长期 descriptor、panel DTO 等已有停止／撤回；P4 成功投影函数内复用已保留 | 不加新 cache owner、永久可信 token、额外完整资源见证 |
| IPC 背压／主界面逐帧驱动 | DaemonCommandBuffer 已 latest-only、控制屏障；接收量／单次 drain 有界，音频后台直投 | 没有传输瓶颈不改 XPC／合并 daemon；ProcessType 不机械套 AppKit renderer |
| Video 硬件路径／Scene 视频纹理桥 | AVPlayerLayer／AVQueuePlayer，Scene AVPlayerItemVideoOutput＋CVMetalTextureCache 已具备 | 不称全部 codec 必然硬解，不默认改像素格式或自行造 decoder |
| 缩略图／GIF／diffable | ImageIO 最长边800、GIF静态候选最多8帧、动画激活租约、预算、同ID跳过结构snapshot与串行apply已具备 | 实际大量GIF峰值／scale问题出现再局部查，不重写全缓存／snapshot framework |
| 系统暂停与 Web shadow CSS 兜底 | 系统事件／idle deadline 已有；shadow animationstart 不冒泡，暂停期1 s扫描是[既有设计](../web/css-animation-freeze-redesign.md)取舍 | 没有等价覆盖不删；native media gate 不代替作者CSS／JS暂停 |
| fetchall 目录监听 | 事件＋10 s恢复兜底、0.5 s trailing debounce、后台枚举与revision拒收已具备 | 缺失目录恢复仍需要；不直接删补偿timer |
| 降精度／全局重排／新后端 | half、memoryless、untracked hazard、Metal4、tile shader都有适用条件 | 不改作者数学／排序／格式／阴影范围来换性能；不引入另一renderer或语言所有权 |
| 后台预编译／长期预热／Release探针 | 用户明确不采用后台预编译，Release开发入口已剥离；空Web预热有限寿命 | 研究工具只放隔离开发链，不能重新塞周期采样／selftest进发行版 |

## 如何做可比较的测量

### 冻结输入与避免并行污染

1. 每批从 Git 状态列出 owned 文件，基于确切提交＋owned 导出固定构建输入，排除并行改动；记录 App／主 binary／helper／优化配置／签名、样本与属性、窗口尺寸、目标 FPS、显示器、音频来源、系统状态及缓存目录。
2. 构建与性能运行串行使用仓库现有锁；锁只能约束合作方，无法排除另一个会话手动跑样本。观察同时活跃的 renderer／编译任务、热状态与时间段，污染窗口单列，不混入配对结果、不改并行任务的 App／媒体／进程。
3. 区分主 App 冷启动、renderer 冷进程、项目／编译缓存冷、OS文件页缓存冷热、已有daemon接管。只清本任务指定缓存；不清用户真实缓存、不执行系统 purge，不把“删除一份shader cache”称整机冷启动。
4. 主指标是点击／原请求发出到目标实际可见且原输出交接完成。Scene presented 与 Web/Video 可见确认的证据等级不同，分别报告；hello／ready／主窗口出现不是同一个终点。属性准备另记请求到可操作控件，不与播放首帧混算。
5. profiler／详细截图／Debug 诊断另开资格窗口；普通优化产品的性能窗口不混进去。系统 CPU 时间先核单位，GPU allocated 与进程footprint分别报；局部阶段不能相加成总耗时，均值不能冒充分位数。

### 短筛、保留与正式声明

- 第一轮用受控输入／行为门、一次联合归因和少量交替 A/B 排除明显无效方向。证据应能说明“确省了哪份工作”，不是只看一段wall数字。
- 低复杂度局部修改：需要原输出／失败反例等价，真实操作通过，主要成本没有稳定负面变化；省调用／分配可如实标局部机制收益。噪声导致整体提速比例未知时保留未知，不为凑10%撤回可靠小改，也不直接认领稳定提速。
- 声称整体稳定收益：使用原专项相称的正式窗口。稳态通常每轮30 s预热＋至少60 s计量，至少3份有效基线与3份候选；启动冷／暖各至少5次交替比较，不用5个点声称p95/p99。必要的30 min稳态／20次轻重切换只在高风险生命周期或阶段收尾执行，不能每个小修重跑全矩阵。
- 任何功能／安全／用户数据回归先修；增加的排队、内存保有、状态数、冷失效成本与维护面必须列账。只有全面量化达到现役性能卡要求时才标正式专项验收，局部保留不是篡改原始门或完成全引擎优化。

### 最近行为门与明确缺口

所有以下模块文件已在本轮确认存在；列出入口不表示已执行或已有足够行为覆盖。实施前读断言和真实输入。统一运行形式：`python3.12 -B script/run_scene_tests.py --module <模块> -j 1`；只选本次涉及模块，不把整表当每批必跑。

| 门 | 可复用模块／仍需补的覆盖 |
|---|---|
| T1 PSO | `test_scene_resolved_material_pass_encoder`：去重、共享library、负缓存、archive；S3补退出／发布取消 |
| T2 compiler | `test_scene_generic_shader_compiler_process`：正常、signal、timeout、诊断／驻留限额 |
| T3 frame | `test_scene_paused_frame_recovery`、`test_scene_surface_evaluation_transaction`、`test_scene_frame_context`、`test_scene_cursor_surface_routing`；S5仍需真实多屏时序 |
| T4 resources | `test_scene_resource_budget`、`test_scene_tex_cache_budget`、`test_scene_geometry_auxiliary_lifetime`、`test_scene_directional_shadow_frame_owner`、`test_scene_frame_texture_registry`、`test_scene_particle_runtime`；S7/S8必须新consumer／allocation证据 |
| T5 audio | `test_system_audio_spectrum`、`test_audio_spectrum_response`、`test_system_audio_spectrum_recovery`；补连续帧缓冲复用与尺寸切换 |
| T6 media | `test_scene_system_media_provider`、`test_web_system_media`、`test_scene_system_media_ipc`、`test_scene_system_media_source`；补Web封面需求／晚订阅与转换计数 |
| T7 Web | `test_web_playback_pause`、`test_web_compat_parity`、`test_playback_switch_endpoints`；未覆盖token原生生命周期、全部频谱endpoint背压，须补真实owner门 |
| T10 UI算法 | `test_ui_library_algorithms`、`test_ui_projection_efficiency`、`test_library_toolbar_behaviors`；不证明SQLite/SIL持久化、目录校准、视频generator正确，须各补行为harness |
| T11探针 | `test_ui_visible_path_probe`、`test_ui_projection_efficiency`；现探针重点为Video，补SIL／窗口停启 |
| T12详情 | `test_steam_detail_navigation`、`test_steam_detail_layout`；保隔离HOME和实际cache消费者 |
| T13下载 | `test_steam_download_history`、`test_steam_download_sorting`、`test_steam_library_interactions`、`test_steam_grid_updates` |
| T14进程 | `test_daemon_process_transport`、`test_playback_process_isolation`、`test_daemon_process_lifetime`；预热TTL精确边界仍需补 |

Swift产品变更做Debug build；时钟／GPU／VM／IPC／持久化与可见变化做隔离代表运行，最终Release实际产物核无新增开发入口／周期诊断、签名及arm64。Debug内部runner只证明其路径，不能直接当普通Release性能或线上Steam验收。

### 实际工具入口

复用现有工具，不新增 benchmark 框架或常驻监控；以下参数已通过本轮 `--help` 核实。执行时先核当前版本，隔离目录由任务自行建立。命令是后续模板，本轮未运行它们；不得给真实媒体目录作为可写runtime root。

```bash
# 构建和触达门先预览；owned参数逐个声明，不卷入并行变化。
python3.12 -B script/verify_scene_change.py --phase checkpoint --base HEAD --owned-path <本批真实文件>

# 代表Scene的Debug资格运行；app参数是已签名的可执行文件。
python3.12 -B script/scene_wallpaper_benchmark.py --app <隔离Debug可执行文件> --sample-root <隔离样本根> --sample-id <代表ID> --output-dir <本轮输出> --no-execution-observations --performance-fps 30 --performance-warmup 30 --duration 61

# Web行为运行；不使用--kill-existing干扰并行实例。
python3.12 -B script/web_wallpaper_benchmark.py --app <隔离Debug可执行文件> --workshop-root <隔离发现根> --runtime-workshop-root <隔离运行根> --runtime-home <隔离HOME> --ids <代表ID> --duration 60 --output-dir <本轮输出>

# 跨引擎隔离/交接行为；仍不是Release速度测量。
python3.12 -B script/playback_process_isolation_benchmark.py --app <隔离Debug可执行文件> --runtime-home <隔离HOME> --scene-root <隔离Scene副本> --output-dir <本轮输出>
```

普通优化产品通过外部 Instruments 的 App Launch／Time Profiler／Thread State／File Activity／Allocations／Metal System Trace／Display 联合采样，先确认当前工具模板支持；不把iOS专属指标强套macOS，不要求Xcode Organizer线上聚合或新增埋点。实际Music验证固定同一片段／音量／输出设备／采集权限；合成正弦／静音只作可复现反例，不代真实音乐。画面截图与功耗窗口分开。

## 交付、记录与退役

每项开始时只在所属现役计划／合同记录当前owner、冻结身份、假设与最近门；完成后保存一份简短结果：改了什么、去掉的工作、实际数据与噪声、功能／失败反例、负面成本、保留／停止理由、未覆盖项及后继指针。失败或放弃的原数保留，不挑最好值；正文不不断追加campaign日志。

研究文档批次已提交；当前实施按每批真实 owned 文件界定范围。共享角色／设计／预算 JSON 逐项增量合并，不覆盖并行条目；产品与测试仅改本批 owner，未经核对不纳入他人源文件。此路线的实施细则只补职责、退出与验证，不复制既有能力台账。

各实现批次分别列 owned 文件、验证、独立审查、产物去留、Git 状态；本轮已获逐批提交授权，不推送。原24项过程冻结为结项记录，当前新增顺序只由上方D阶段维护。本文U1/U2实施边界仍由现设计登记引用；待稳定合同由原owner专题接管后整体归档，不为搬文档复制第二份当前事实。重开STOP必须满足本页记录的条件，或由用户明确授权新阶段。
