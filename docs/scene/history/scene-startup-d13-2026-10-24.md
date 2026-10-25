# Scene 启动 D13：双 encoder 成本资格与 P4 停止

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**

截止 2026-10-24。当前顺序与重开条件归[冷暖启动专项](../../development/wallpaper-startup-optimization-plan.md#p4同-launchdevice-共享成功-metal-librarypso)。本批未改产品、原测试或构建 App；未提交、推送或安装。结论是停止本轮 P4 共享实施，不是专项全部完成。

## 裁决与输入资格

现有固定内建 pipeline 已同 launch 共享；authored library/PSO 仍由每个 pass encoder 缓存。源码能证明实例缓存各自存在，不能证明这是值得增加共享层的启动热点。先以相同真实 device、相同 Program/WarmupPlan、两个同时存活且 owner 独立的真实 encoder，观察原创建计数、PSO 对象身份、原 binary archive 和 GPU 输出。

首次运行完整保留原 sole method 与断言，但在探针之前的 `Program.assemble(...)!` 崩溃：Swift 编译成功约33.968s，原生进程约1.611s以 SIGTRAP 退出。尚未进入 P4 探针，不能把这次失败当作共享成本证据。

定位到旧测试 `uniforms(...)` helper 仅特殊处理 `mwxRenderSize`，其余默认填4B Float。真实 frontend 总是声明两个16B float4坐标，Host 默认值是 `mwxVertexCoordinates01=(0,1,1,1)`、`mwxVertexCoordinates23=(0,0,1,0)`，Program 严格长度检查因此拒绝。HEAD `ae0ac798ca712e724a82fb1d06e1e148565b8a6e` 与当前 WT 的相关定义同文，静态证据说明夹具失配已经存在；没有运行整个 HEAD 门，也没有据此推断其完整结果。

仅在隔离副本的 Swift literal 加入这两个真实 SIMD4 输入分支，共4行；未改 WT 原测试。原 sole method/class AST、其余输入、原断言及截止期保持。旧 Python 内含约三千行 native harness，不直接追加补丁越过单文件职责/长度规则；其永久维护与原门恢复仍开放。原失败保留，一次因果修正后的输入资格不改名为“原门通过”。

## 一次隔离结果

修正输入后仅运行一次：122个冻结 Swift 源，编译30.845s、原生运行6.199s，均退出0；sole method为1通过、0失败/错误/跳过，原141项结果与新增10项机制结果全部为true。它们是结果事实，不是151个测试方法。原生输出、探针即时独立输出及22份收据哈希已由主 Agent 逐项核对；源、原 WT 测试和探针执行前后 SHA 均不变。

| 操作顺序 | library 创建增量 | PSO 创建增量 | whole warmup 观察 |
|---|---:|---:|---:|
| 第一个 encoder，相同 key | 1 | 1 | 537.201ms，原 archive absent并发布 |
| 第二个 encoder，相同 key | 1 | 1 | 0.345ms，命中原 archive |
| 第一个 encoder，再次相同 key | 0 | 0 | 0.009ms |
| 第一个 encoder，改变 attachment format | 0 | 1 | 9.556ms，单独 archive absent并发布 |

相同 key 的两个实际 PSO 对象不同，异格式 PSO 也独立；一屏 reset 后旧 PreparedPass 被拒绝、不能跨 encoder owner 编码，另一屏仍完成 GPU 工作且像素正确；reset 后原本地缓存和输出保持。全段 archive retries、invalid loads、publication failures均为0。

此处第二个 encoder 在第一个完成后才开始 warmup，已经具备原 archive。未测并发首次编译、多 key 总成本、真实双屏 App、不同实际 GPU/device、最后强借用释放或未来弱共享生命周期。全段耗时包含原 warmup工作，不是 Metal API 独占 CPU profile；驱动/系统 cache 状态未知，无清缓存。首次537ms不会因跨 encoder共享而消失，单 key 后继约0.35ms不足以证明实际启动收益，也不能乘未知 key 数外推。

## 设计修订与后续边界

P4 产品实施停止，原 encoder/内建 repository/archive 保持。仅在真实 launch/device 的重复 key 频率或关键窗口有新证据时重开。条件设计已纠正为弱成功索引、短命 single-flight和原 encoder 强正/局部负缓存，避免强共享表延长退休屏驻留；不建立闲置复用 API、第二磁盘 owner或跨 launch保温。完整条件与验收只归专项。

本批没有产品前后性能对照，不认冷/暖启动提速、能力完整通过或官方等价。D7/D11 seek失败、D4残余资源成本、Web C1窗口及P2/P3/P7未闭项继续按原记录处理。初次 native失败、主 Agent 一次比较错 JSON wrapper的提取结果与后续按真实字段核对均保留；后者没有触发 native重跑。

## 产物与 Git

最终资格收据 `final-assessment.json` SHA256 `e2987d4c40ba2bea361ee377e2f7a69314efae90248e250f12b2435be25d718b`；首次失败收据 SHA256 `a3012649666ae9643c39836c682a1b67841eabf673d47e9759057e015ca8bff2`。原D13保护包材料在[D14原门修复](scene-startup-d14-2026-10-24.md)后转存 `.artifacts/scene-evidence/runs/wallpaper-startup-scene-d14-20261024-checkpoint/`，原重复包清理。保留原失败、隔离修正、冻结输入及原始输出；按report的sourceAliases查sample ID/payload，原task路径仅为历史来源别名。

原测试 TemporaryDirectory 已删除编译二进制、模块和私有 archive；提取核验后清理本批停止使用的冻结副本，精确清单另存任务顶层 `d13-cleanup-receipt.json`。连续任务只保留 `/private/tmp/mwx-startup-optimization-fbRhFY/DerivedData` 一份构建缓存及跨批仍引用的材料。未操作其他窗口试用 App或真实用户媒体。本批修改仅专项/设计登记/文档预算、此历史与索引；保持所有既有并发改动，暂存区为空，goal仍活动。
