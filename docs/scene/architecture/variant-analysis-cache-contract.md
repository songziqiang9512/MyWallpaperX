# 变体分析缓存合同

<!-- document-role: stable-contract -->

状态：B 方案设计已批准，产品未实施；批准不表示性能或运行验收。本文承接[运行架构 §3.5](runtime-architecture.md#35-启动是候选事务不是全量兼容门)，维护原 v22 wire、兼容扩展与成功回填的完整合同；当前执行顺序与结果归[性能工作卡](../roadmap/performance-convergence-card.md)。

<a id="variant-analysis-source-pure-extension"></a>

## 1. 目标与方案选择

目标是在原 `SceneResolvedMaterialVariantAnalysisCache` 内补齐遗漏的 source-pure 结果，减少同一编译源在暖 preparation 中重复分析；不新增 cache owner，不保留 Unit/AST，不缓存逐节点 eligibility 或图、格式、purpose、provider/context 准入。一次 opt-in 资格中三类入口累计 6559.573ms，属于可并发、可嵌套的 inclusive worker 区间和；它只超过继续归因阈值，不是可省墙钟或 CPU。294 次入口各有多少有效旧前缀命中仍未计量。直接共享单次 variant 的解析 Unit 是备选 A，只能省相同源的重复 lexer/parser；优先 B 复用现前缀，若兼容补写不能保持下列边界则停止 B，再评估 A。

## 2. 旧前缀与集合的 wire 身份

原 v22 前缀继续使用现 key、目录、字段和 `recordSHA256`。其多种 Mirror 含 Set；有界原 owner 探针中，七元素集合写入后同进程及一个 fresh reader 均 miss，singleton 两者 hit，文件未变且原 wire 载荷摘要匹配。这证明 decode Set 后重编码会破坏摘要的可能性，不证明真实 variant 的受影响比例。持久投影须把这些集合表示为有序数组，先保留旧文件数组顺序验证旧摘要，再转为运行时 Set；新 store 只对明确具有集合语义的字段排序，不能全局排序 JSON 数组。此修正不 bump v22 或清理旧 tier，也不声称已修复旧 binary 的 Set 解码行为。

## 3. 源纯事实与兼容扩展

B 的最小新增值是完整的 source-pure facts envelope：RGB blend scalar-alpha 的可选 source slot，以及 Provider 中 preserved-alpha、TypedData 两分析器按原短路顺序得出的可选 slot 集合。只投影当前消费者实际需要的值，不序列化整个 Fact；后者 `.some([])` 表示已匹配空集合，必须阻止继续 fallback，`nil` 才表示这两级均未匹配。Provider 后续 same-alpha、RGB fallback 及所有逐节点上下文判断仍在原位置执行。扩展整体缺失表示未计算；扩展存在且内部值为 nil 表示已计算无匹配，不能把旧 Record 的缺字段当 negative，也不能为填满扩展强制执行原本短路跳过的分析器。

扩展放在现文件的外层 Envelope，具有独立语义版本和完整性摘要，摘要覆盖版本、当前 key、前缀 `recordSHA256` 与完整 facts；前缀内的 canonical compiler sources 因此也受绑定。不得把新事实加入旧 payload 后仍沿用旧摘要协议：旧 binary 忽略未知 payload 字段后重算会强制 miss。旧 reader 应可忽略未知外层扩展并保持原前缀判定；新 reader 先独立验证 v22 前缀，再验证扩展。扩展坏类型、缺字段、错误版本/key/prefix/digest 仅丢弃扩展，保留有效前缀并运行原分析；整个 JSON 损坏或原前缀失效仍为完整 safe miss。实现须独立解码扩展，不能让可选扩展的解码失败连带拒绝有效前缀。原前缀语义变化仍按其 schema 失效；仅本扩展分析语义变化用扩展版本局部失效，不借新字段淘汰全部暖缓存。

## 4. 成功回填与并发退出

冷 miss 沿原成功发布点保存；暖前缀缺有效扩展时，原算法计算遗漏结果，只有 `finalizeVariantBindings` 成功后才在同一 owner、同一 key 原子补写。补写保留已验证的完整前缀 wire 投影、字段和摘要，不从本节点重建其他旧事实；原锁内复核当前文件前缀已变则放弃该次补写。现进程锁不是跨进程 CAS；与旧 binary 并行写入仍可整文件 last-writer-wins，每份文件必须自洽，不能宣称阻止了跨进程覆盖。任一后续 throw、拒绝、取消沿原路径退出，不保存 rejected variant，不增加失败 cache；写入失败或超额只影响可选缓存，不影响当前准备结果。

## 5. 预算与普通帧

沿用现每项 512KiB 上限、目录与清理入口，不提高预算，不新增常驻表。现 4096 是进程首次 store 前的 prune 参数，并非每次写入后都保证的硬条目上限；本批不借性能补齐扩大磁盘治理职责。暖补写超过单项上限时保留旧有效文件，load 不建目录；普通帧不增加解析、哈希、IO 或诊断。

## 6. 验收与停止条件

最近验收分两层：原 cache 行为门补多元素 Set 的旧 wire/new-reader、cold store/fresh-reader 与损坏摘要反例；冻结旧 binary 对同一前缀加外层扩展前后的 singleton HIT 控制，保前缀字段及摘要不变，多 Set 只要求不新增强制失效，不要求原有随机 miss 变 HIT。另以真实 Color/Provider variant 入口验证 warm 正事实、negative、匹配空集合与 fallback 顺序，含改名、等价表达式、compiler source 漂移和图/格式/context 不准入；成功补写保全旧事实，后续失败不发布。扩展损坏、版本/key/prefix 失配和已变化前缀不补写分别反证。以上闭合后才构建并做一次同条件暖启动短筛，先核实际前缀/扩展命中、编译/准入结果与画面；启动降幅不足 10% 停止，不因入口累计时间推定收益。旧 binary 本来就 miss 的记录不能作为已修复旧 App 的证据；若共享 cache 会改变两臂前缀条件，先隔离相同起点的 cache 视图，不能污染基线后继续比较。
