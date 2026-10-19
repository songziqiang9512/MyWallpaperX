<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**

# Web / Scene 准备成本收敛

> 截止：2026-10-19。本批设计、候选取舍与有界证据归档；长期职责已移交下述现有合同。原数值门及其STOP不改写，用户修订后的产品保留决定单独记录，不代表普遍提速或全部兼容。

## 目标与职责

缩短可避免的播放/属性准备等待，保持作者效果、支持集合、保存/reset、资源授权、进程隔离和可见交接。复用现有 SteamWorkshopService、Web descriptor/cache、Scene preparation、取消和 panel owner；不新增协调器、长期 watcher、后台预编译或缓存层。Release 不增加诊断入口、计时或周期任务。

Web 的稳定作者解释、有效值与资源授权是不同事实。属性 JSON 是作者数据，不是文件授权；只由主 App 已解析的项目/依赖根及用户书签产生 typed grants。Scene 的运行 Program 与面板静态支持集合不是天然等价，不能以减少等待为由扩可调项或提前发布 ready。

未解析的 file/directory 原值及作者 sentinel 保留原 payload 语义，读不到的路径不产生 grant；不能通过清空作者值替代授权修复。只有实际缓存解释改变才升级版本，不因新增非持久化运行输入清掉有效暖缓存。

现有长期语义分别归[技术栈边界](../../architecture/technology-stack-boundaries.md)、[播放事务](../../architecture/playback-lifecycle-transaction-design.md)、[Web 模型](../../web/web-project-json-runtime-model.md)、[Scene 启动合同](../../scene/architecture/scene-launch-responsiveness-contract.md)。本设计只拥有本批实施次序、候选与退出；完成后把稳定变更交回这些 owner，过程按专题归档。

## 阶段与数据流

### P1：Web 可信资源授权

先用真实 handler 反例确认原路径把 file 的父目录当 grant。将 grants 与 propertiesJSON 分开：精确文件只能访问自身，目录允许规范化后的合法后代；symlink、路径解码与 regular-file 检查仍由资源消费 owner 执行。主 App 从原 binding/bookmark owner 构造 grants，同现 request/属性更新一起传输，不通过 JS 值反推授权。

初始播放、预设/依赖、本地选择、清空、reset、reload、候选复用和多屏均消费同份授权快照；属性更新同时替换而非累计 grants。旧 request/navigation/transport 不得扩大新授权。文件已存在不能代替用户授权；项目相对资源继续走原 namespace。保留 file/directory 实际资源和媒体读取，修复父目录扩大不视为合法功能回归。

random/fetchall 目录枚举、快照和 watcher 的 producer 也必须在读取/开监听/发布结果前消费同份授权；只在最终 handler 拦截不足以保护目录清单。沿现 request 的资源授权 revision 退休同请求内旧异步结果；替换、清空、reset、撤销同步退役旧快照与 watcher，合法新资源仍可读取和重建。

沿现有 launch request、runtime command、IPC 和 scheme/loopback handler 传递有界 immutable grant 数据，不另建资源表。跨版本不兼容用协议版本拒绝；非权威磁盘 execution cache 不保存仍需 live bookmark resolution 的授权。预备进程、scope/lifetime、失败回滚继续由原 owner 管理。

### P2：Web 同次准备复用与分层失效

execution cache 先比较版本、record、语言、项目/来源/入口 metadata、overrides 和 entry/root 等廉价字段，再取得资源签名。单次 preparation 在相同输入、entry/root 下只扫描一次，供 execution/analysis 清单消费；失配、缺失/损坏清单继续原重算。共享只存在于该准备调用，不成为会话永久免校验 token，也不把签名的现有 metadata 盲区宣称为原子文件快照。

普通值提交只失效有效值/显示条件/执行 payload；稳定项目解释可继续复用。先辨清 descriptor 中的 preset bindings/baseline preconditions 与书签副作用，资源、依赖、来源或语言改变仍失效对应解释并重解析授权。保持原保存等待与版本失效语义，退役原两次扫描及普通值的无差别 descriptor 清除，不保并行实现。

最终缩减范围：较大的 observation/descriptor 保留方案存在已证陈旧解释写回和额外读取，整体撤回；只保留上述第一项中“先比较原有廉价字段，再扫描”的顺序调整。版本、语言、项目/来源 metadata、overrides、entry/root 失配本来就拒绝，故提前拒绝可省无用扫描；命中仍扫描并核完整资源签名与路径存在。保留原 descriptor 清除、保存与重算，不新增输入快照、重试或状态。

### P3：Scene 协作取消

先在真实 A→B 连选中确认已过期 A 占用原串行准备队列。沿原 cancellation，在 SourceFacts 阶段及 descriptor 材质循环的边界退出；检查置于会转 nil 的 try?/catch 之外，取消不得变成缺资源或兼容降级。资源/Program 验证逻辑与队列保持，不向单次同步 reader/hash/flock 承诺即时抢占。

只验收过期工作更早退出、B 更早进入准备、旧结果不发布及原输出连续；不把它写成单个作品冷启动加速。租约、GPU drain、临时资源和候选回滚按原生命周期结清。

### P4：Scene 函数内重复投影短筛

限定 `unconditionalStaticModelUniforms` 同次调用内重复 `uniformSchema`：完整 field 身份包含 name/stage/type，失败与顺序语义不变；graph、hash、宏、条件、producer 与冲突证明照常执行。先给出实际优化配置下的局部成本与启动分母，再决定是否保留函数局部复用；不扩为跨 pass/阶段/进程缓存。

这是新的重复 consumer，不重开已停止的 MDL packet/cache、直接 PKG 迁移、定义裁剪、五个正则复用、声明/variant 扩缓存或 toolchain 资格缓存。[旧 STOP](../../scene/history/native-cpu-allocation-screen-2026-10-15.md#mdl-validation-followup-20261019)保持。

### P5：Scene 面板按需复用资格

只研究已提交 active session 在面板首次请求时返回有字节预算的静态 DTO；不在每次播放 eager 构造面板模型，不传 SourceFacts、descriptor、shader 或整模型。必须先证明现 prepared binding 与当前 staticActionableKeys 的策略等价，连接 transport/request/source、实际资源和结构属性身份；最多一份有界投影随原 panel/session owner 退休。

若当前 prepared 结果不足以等价生成，或需要额外编译、全量 namespace 见证、大载荷及新缓存权威才能成立，则该阶段以 NO-GO 结束，保留原完整准备。未播放首次冷开保持现支持语义；不以全 catalog 控件替代已证可调项，不以隐藏 loading 计作提速。

## 验证、收益与停止

每阶段冻结 baseline/owned diff、输入、工具链、配置及产物身份；完成最近行为门后交独立子代理审查，修复后复审受影响结论。产品 Swift 做 Debug build；最终优化配置另核 Release 无新增诊断。真实媒体只读，样本/HOME/cache/App 在隔离目录；全局构建/运行串行，不混入并行工作区修改。

- P1：真实资源任务验证精确文件/同目录 sibling、目录后代/外逃、raw 绝对值、编码/symlink、替换/清空/reset、旧消息及多屏；另验 random/fetchall 未授权时零枚举/零监听、授权撤销后同请求旧结果不可发布。保正常项目、依赖、预设和合法用户选择；修复前反例应失败、修后通过。
- P2：真实 cache owner 的扫描计数验证同次有效双清单一次扫描、廉价失配零无用扫描、坏缓存重算；覆盖项目/依赖/语言/JS/CSS/资源修改、书签移动/撤销、旧 parse 结果、颜色去抖/reset/条件和同 label 不同值。不能仅断言源码字符串。
- P3：受控取消行为门加隔离真实连选，核 A 退出/B 开始/旧发布拒绝/前景持续；取消不能变失败通知或 lease 提前释放，单选冷暖不能退步。未证实际阻塞或不能安全传播即停。
- P4：自有 shader 输入覆盖 stage/type 同名冲突、material key 争用、条件/宏、坏 default/range、改名与不应命中反例；完整输出等价后才看性能。任何语义差异即撤回。
- P5：不打开面板的启动不得新增 compile/namespace 扫描；实际面板命中无 builder，未命中走原准备；key/row/条件/持久化/resource/reset/callback 集合等价，关闭、切换、崩溃重启、资源/语言/属性变更与超预算失效。

冷空缓存、新进程磁盘暖缓存、同进程 memo 分开；启动固定安装路径/优化与签名/预热/surface/作者属性及音频，交替至少五次。先短筛，局部正向才正式运行；初始性能卡预锁定目标降幅≥10%、超过两倍基线最大相对噪声、噪声≤5%，原数与门结果不得事后改写。样本差异、噪声或观测不足不声称达到该正式精度；局部减少扫描不冒充完整启动收益。

2026-10-19 用户补充：其他并行任务偶尔运行样本，可能干扰测量；允许保留相比原先有实际进步、复杂度增加不大的方案。因此最终保留同时看全部配对方向/量级、因果路径、功能反例与新增运行成本，不将初始5%噪声门当作自动删除有价值修改的产品规则。有可归因退步仍撤回；原STOP结果保留，不重跑选点、不改称原门通过，也不把无法排除的并行负载写成已证噪声来源。P2存在正确性与额外读取问题，P4缺少整体启动收益，P5需新状态与额外准备，均不因本次取舍变化而扩张。

## 完成与 Git 边界

本批只在所有阶段得到“保留且验证通过”或“有依据停止且候选撤回”的结论后统一提交，不推送。性能门失败不继续扩缓存/并行度或放宽安全边界；每阶段记录实际结果、审查及未覆盖范围。共享 JSON 只修改本设计及本批明确所属记录，保留其他会话 staged/unstaged/untracked 内容。

| 阶段 | 当前状态 | 结果/证据 |
|---|---|---|
| P1 | 通过 | 真实 sibling 越权反例红→绿，21 行为门通过；恢复撤权与无关流中断两项独审问题已修复并复审，Debug 零警告/错误。持久化三阶段实跑通过：选择/A→B→A/重启书签移动/清空/再重启及缓存恢复。旧进程内退出日志前提已退役，改用实际 adapter 状态与 OS 子进程退出收据，16 门及独审通过；不把进程退出写成 WebKit 子进程或 surface 测量。 |
| P2 | 保留极窄早退出/独审通过 | 五对局部 -O 对照未过噪声门（磁盘暖 CPU 基线44.8%、普通提交11.6%），独审另发现 override 廉价 miss+JS 改动可将旧 memo 配新签名写新鲜，以及 preload/inactive shell 新增读取。完整五路径候选已精确恢复P1；按用户新取舍只摘取无新状态的字段检查顺序，实际loader红→绿：廉价失配零扫描、有效命中一次扫描及payload不变、JS/CSS/JSON修改与缺entry拒绝、坏清单原重算接口均通过，不恢复其余候选，不重跑性能选点。 |
| P3 | 保留合作取消/独审与有界连续性通过 | 唯一40slot功能全通过；两个package条件共十组配对的B排队和首帧均改善，baseline/candidate区间不重叠。四目标基线噪声22.35%–29.25%，原5%门STOP保持；多数单选控制也噪声过大，不宣称稳定提速比例或全部单选无退步。只沿原token补准备边界取消，不增加队列/缓存/诊断；先撤回后按用户新要求恢复同一已审候选，另做非计时连续性，两arm各三观察点均保持旧前景及B正确接续，正常exit/drain；三点截图不保证任意瞬时无闪烁，最终集成见下。 |
| P4 | 保留局部memo/独审通过 | 唯一局部短筛CPU中位7315.757→6698.160ms、配对8.442%、基线噪声14.929%，不改称原门通过。独立复核确认当前三字段consumer有重复投影，最小独立三uniform可由9次投影减为3次；代价是本函数内完整Field键的短命字典，单field/早失败可能纯增成本。只缓存成功投影、保原调用/错误顺序；完整Field、冲突/坏值等价门baseline/candidate各11/11通过，九组完整JSON逐值相同，不做额外性能campaign。 |
| P5 | NO-GO/独立复核通过 | active session 只持 launch context，没有完整 catalog/localization；运行 proven bindings 与面板默认编译支持集合不等价。复用需新增保留/编译及资源见证，违背本阶段零额外启动成本条件，故未写 DTO/IPC/产品候选，保留原按需准备。 |

## 集成收尾边界

最终产品为P1授权与目录同步、P2廉价失配早退出、P3合作取消、P4函数内成功投影复用；P5已完成资格审查，以NO-GO结束，没有新增DTO或IPC。固定已提交`6237cdf8…`加本批owned、排除未提交并行工作的最终Debug/Release均0警告/0错误，最终Release主二进制`415cc879…`签名deep/strict通过；已知开发诊断owner符号未入该主二进制，四项诊断隔离门通过。实际Debug Web三阶段验证选择A→B→A、重启书签移动、clear/reset与再重启、缓存恢复和捕获child的OS退出均通过；实际Release Scene单arm验证旧328→取消准备中的366→B328，3load/3release、matching首帧、正常exit/drain与三个画面观察点通过。各保留阶段独审及最终owned提交树审查均通过。本记录随本批实现统一提交，不推送，不纳入其他会话工作区改动。

正式40次使用固定Git33基线与同源候选，所有原数保留；最终集成另采用已提交Git基线加本批owned，排除未提交并行修改。全局flock只协调遵守同一锁的任务，无法排除另一个不使用此锁的样本运行，不能反推波动确定来自并行任务。SourceFacts、shader和资源安全检查未放宽；合作取消不能抢占单次reader/hash/flock。

未覆盖：不能由本次运行证明全部作品冷启动、稳定提速比例、最低macOS、全部音频/输入/多屏、长期能耗或官方画面一致。全局依赖词法门的`PassEncoder → ProgramIdentity`未登记边已在本批前Git33源码复现，本批不修改该owner或放宽基线；隔离owned提交树的文档/行数/防御/测试断言门通过。过程原数、最后日志和必要截图限量保存于忽略的证据包；可重建执行环境在本轮清理，最终测试App单独保留。
