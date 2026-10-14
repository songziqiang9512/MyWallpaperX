<!-- document-role: historical-evidence -->

# Shader 完成结果缓存保有收敛（2026-10-15）

> **历史证据 — 非现役入口**。当前合同归[资源准入](../architecture/scene-resource-admission.md#shader-completed-cache-retention)，执行顺序归[性能卡](../roadmap/performance-convergence-card.md)。本批限制跨场景可重建 CPU 编译结果的保有，并修复编译失败在内层永久缓存、外层重试无法恢复的问题；不改变作者 shader、磁盘身份、prepared Program 或 Metal 输出。

## 实现与行为边界

Preparation、Frontend、generic resolution、compiler completion 保留原 owner 和锁，只共用内部 completed LRU 容器。合计 97 MiB 是显式字段的缓存权重上限，不是 RSS 上限；active/candidate/in-flight 强引用和编译器/driver 瞬态不在其中。成本在完成发布时计算，裁剪按保存的访问序排序，不在比较器重复哈希完整源码 key。超大合法项照常返回但不缓存，不驱逐其他有用项；同一 Flight 的等待者直接共享该次结果，不因未准入串行重编。

旧组合 fixture 复现 outer operation 两次、inner compiler 一次，修复输入后仍得到首次失败。修后同 Flight 共享失败，后续独立请求可成功重试。不同 material/surface/新准备仍可能串行重试失败 key；不是每 generation 同 key 只编译一次。普通帧只选择已经准备的 ready variant，不进入编译。

最终五条行为门通过，包含字节/LRU、长 key/MSL/sourceMap/annotation/layout、超额合法项与活跃引用、等待共享、失败恢复；裁剪反例实测 5 次 key 哈希且保持正确 LRU。源集/持久缓存静态门 16 条通过，隔离 cold/warm 持久缓存行为门通过。历史测试硬编码 v20 目录已改为隔离空 HOME 内验证唯一版本目录，产品仍用 v22。最终 Debug build 23.197s，4297 个输入前后无漂移；未重复未受比较器修正影响的持久缓存门。独审覆盖四产品 owner、Flight、成本与普通帧路径；最终比较器按审查建议修正。

## 测量协议与解释边界

本机证据根 `.artifacts/tmp/shader-completed-retention-20261015/`。真实原 generic resolution owner 的独立进程 fixture 保有合成 MSL：32×256KiB 为可容纳工作集，256×512KiB 为独立输入压力，再访问前 16 项；外部 `proc_pid_rusage` 采样 physical footprint。每阶段停留 3.25s、至少三个有效点。初始 B/C/C/B/B/C 三基线三候选后，最终比较器修订只补三候选，复用原二进制身份未变的三基线。它证明此 owner 的真实进程保有变化，不证明日常 App RAM、CPU、GPU 或能耗收益。

App 对照为同 Debug/签名/60FPS/隔离 HOME 与 generic cache，单 PID 连续 L0→A1→B1→L1→A2→B2→L2：L=3766415113，A=3042492564，B=2932157836。原媒体只读，输入复制至隔离目录；默认属性、静音，无外部媒体发布。首帧按 request/record 关联；现役 Metal 诊断截图在每步 9s 采样窗之前完成，外部 CPU 取窗口内采样差，不使用累计 frameStats.cpuFrameMs。这个 floating/framebufferOnly=false 诊断配置两臂一致，不等同普通桌面或 Release。compiler lifecycle 的 source=spawn 是原协调器 operation，不必然是 OS 编译进程；无新记录不区分内存与磁盘命中。暖门只要求之前成功 key 不反复执行，失败重试单列。

最终受控压力结果：三基线 loaded physical footprint 中位 **143590000 B**，三最终候选 **20922872 B**，下降 **85.428740%**；候选保有 31 项、约16.325 MB权重。基线最大偏差0.000017%，候选2.584%，收益远大于噪声。重访前16项时基线16命中/256次operation，候选0命中/272次operation，明确付出被驱逐项的重新准备成本。可容纳工作集两臂均16命中/32次operation；footprint中位12337632→12681720 B（+2.789%，低于5%反例预算），没有通过清空cache制造收益。

最终 probe SHA `0a3e8729d01897692f5e6fa73a8195ae209aecd170629778e171ffd8b7d19a16`，冻结基线 `b175524e3cad602f73f5dd7b440eccfde6f3079d579545666adfc5962467437f`。`owner-screen/final-summary.json` 保留各轮、采样数与命中；旧候选三轮是中间结果，最终数字不混入。此实验无优化级别 CPU 或真实 compiler 开销结论。

## 真实 App 短筛

最终 App SHA `97e6d9eaff65841063a5012132bebdb45608713af23f2df22698f7462bb560e7`，基线 `e2ddf9e2a7305541a4478a0d95ccf4dfb69a341a7444390bfeb5df69b4b213cf`。两臂七步成功，正常退出 0；暖 A2/B2 均没有新的 compiler lifecycle，首次 A/B 各 54/30 个 spawn:published，失败记录均 0。所有采样窗 busy/dropped/fallback 差分均 0；切换区间发生的累计 dropped 不混入稳定窗结论。

| 尾三点中位数（B / C） | L0 | L1 | L2 |
|---|---:|---:|---:|
| physical footprint / B | 250135608 / 200688648 | 372245968 / 357467696 | 369477216 / 330204672 |
| GPU allocated / B | 98025472 / 98025472 | 98222080 / 98189312 | 98222080 / 98189312 |
| RT pool / B | 0 / 0 | 0 / 0 | 0 / 0 |

A1→A2 首帧 B 68.863→21.282s，C 67.649→20.996s；B1→B2 为 45.477→12.915s、44.301→12.566s。暖重场景 CPU 时间率两臂约 1026/1033ms/s，未证下降。轻场景 C 的 CPU 时间率 L0 下降约16.6%，L1/L2 升约19.8%/10.6%，首次 L0 启动升约25.9%；短窗无稳定噪声基线，不能归因于缓存或写成非目标性能门通过。原始差值保留，当前不认领 App 启动/CPU/RAM稳定收益；未新增普通帧缓存工作。重访无需反复编译、轻场景资源回落只关闭此短序列边界，不等于全部 pin 释放或长期有界。

root 实看两臂 L0/L2 的瓶子、湖面和像素星空，A 的塔楼/两人物/星空/日期，B 的人物/水面/星形，返回后主画面一致；A 的点线时钟及 B 首图无时钟保持为证据限制。未参与缓存修法的 L 提供独立真实画面与轻载反例。收据 `app-screen/comparison.json` 记录截图与窗口原始来源，`summary.py` SHA `483865376bc2e13c200a8436bd5c7d48cdb91ad15cd7aa6c1bc7a5a7ecc84ea5`。

## 未完成边界与无效尝试

无效准备尝试分别保留：完整历史矩阵缺少 A 的条目，尚未启动 App；普通桌面 captureFrame 只返回 1×1 JPEG，尽管首帧成功且持续呈现，未开采样窗；第一候选诊断运行等待人工看图确认超时，正常退出，未算有效对照。后者只重跑候选，基线不重测。1×1 capture 原因尚未确认，疑点是 ScreenCaptureKit 窗口尺寸/捕获时机，不据此认定 Scene 输出错误，另留现役队列。

这些短窗不能证明最终旧 session/pin 归零、30 分钟长期稳定、20 次切换、多屏、HDR、最低设备、正式 Release 或热/功耗收益。真实样本旧视觉和 unsupported profile 仍留队列；首帧快照中 A 的时钟仍呈点线、B 未出现时钟，不能把主画面存在写成整样本兼容通过。

## 产物与保留

本轮已停止运行的隔离 HOME/样本/缓存、中间 App、探针二进制与模块缓存共清理 1040975743 B。最终 App 与 `.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData` 保留供下一轮唯一构建缓存/归因；必要原始测量、源身份与失败日志保留本批目录。压缩且逐文件验哈希的最终证据17.34MB、基线画面16.78MB已备妥；正式证据根达到全局预算，提取被工具拒绝，不扩大预算、不清未知旧证据。
