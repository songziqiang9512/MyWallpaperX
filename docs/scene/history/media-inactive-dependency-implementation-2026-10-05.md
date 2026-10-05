<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# 初始隐藏媒体封面的依赖准备修复（2026-10-05）

> **历史证据 — 非现役入口**。当前权威：[能力台账](../capabilities/coverage-ledger.md)、[后继卡](../roadmap/batch2/reference-evidence-implementation-cards.md)。

基线 `0d666304`。2938612768 的媒体标题和播放事件已响应，但 current-thumbnail 特效一直直通，背景、唱片和封面框仍显示默认图片。真实包 SHA256 `1f3a74c0241bb8f57c0abdbcded05562e329ebfc6ff47bf762e8b71f4e0326fc`，85个顶层对象；仅在隔离副本运行，原件只读。

## 修复职责

初始隐藏的 optional named 输入原先在引用扫描、顺序恢复及最终依赖计划中被重复按可见性过滤，potential carrier 为空；script preproof 又只接受直接 named 来源。现在 potential 扫描保留这些声明，单候选静态检查不提前授予执行权；既有 Program 的 exact mixed-fallback 证明通过后，preproof/finalizer 与最终计划保留相同 consumer/provider/slot 和作者顺序。最终计划只纳入已授予的引用，实际显隐仍由帧 snapshot 决定。

同 provider 的 base 与 optional sibling 组合保留更严格的 Program 要求；kind、blend、forward capture、无 framebuffer 与最终完整引用守恒不放宽。未证明、错来源、错槽位、循环或不支持形状仍拒绝。没有新 renderer、clock、资源 owner 或按样本分派。

## 验证与边界

- 两个新 CPU 门以同输入对照基线红/候选绿：真实 descriptor → potential carrier → 已授权 final plan，以及生产 preproof/finalizer 函数处理 prepared atoms。后者不冒充完整前端或 GPU 验证。已有 dependency-plan 28 项及 capability 门通过。
- Debug build、深度严格签名校验通过。最终 dylib SHA256 `09958ec97337dde35f471da85972876b5c22ab568d36c109472f2a75ba6e9c8e`。
- App 受控媒体入口注入自有256²红/蓝PNG并清空，检查真实 Metal readback；不等于普通产品已能读取系统媒体。两种背景模式共四个current封面effect（1509/1513/657/239），每轮三处 ROI 确认红 `(220,30,40)` → 蓝 `(20,70,235)` → 作者默认，current stage 真实 GPU 执行。
- 一次中间版本把诊断后缀加到可执行 reason，独审及 App 发现首帧拒绝；已完全撤回，最终保持原精确执行状态。未把构建成功或退出0当作画面通过。
- 原大 graph 测试入口存在旧 stub 编译漂移；本批使用真实依赖计划 CPU 门与完整 App 闭环。结构门两项既有 analyzer inventory/classification 失败仍保留，未抬基线。
- previous-thumbnail 一秒过渡仍未执行；其脚本事件已到，具体编译拒绝待下一批定位。系统媒体 producer/IPC、真实音频/点击、物理多屏及官方 parity 未由本批验证。样本执行覆盖与完整正确率分开报告。

两模式同输入前后对照：实际执行的特效阶段并集从40/73增至44/73（约60.3%），终端由compositor消费的effect层为25/37。四个current-thumbnail阶段全部恢复；这是本批操作覆盖下限，不是整样本正确率，未触发或未知分支不计失败。两轮各一个Session并正常退出，未修改最终输出owner。

最终证据包 `.artifacts/scene-evidence/runs/media-inactive-20261005/final/samples/2938612768/runtime_evidence.zip`，28,804,113字节，SHA256 `cbe8b3de056b597220be4743da1ca080ffbf73d4d222438db05ab77e1a17c167`。50个payload逐文件哈希与ZIP CRC通过；保留14日，不含原始包。完成后移除本轮隔离样本、旧候选App及重试缓存，继续复用一份既有构建缓存。


## 后继：previous 封面过渡（基线172c810a）

上一批保留的四个 previous-thumbnail stage（1509#970、1513#996、657#667、239#257）并非事件或时间轴未到：它们在准备期被 `optional-named-fallback-unproven` 拒绝。同一槽的两个候选恰为 named premultiplied color 与 optional preserved channels；普通 shader 丢失前者的输入 ABI，两个变体都被记作 raw。

修复在现有 generic analysis 与 variant frontend 传递已证明的颜色输入槽，并使 analysis cache v4 失效。普通颜色输出复用现有逐 sample 转换，保留背景默认输入；已转换的 default boundary 不二次除 alpha，preserved 输入不转换。独审指出数据输出的反例后，新增行为限定为 color 输出，原数据路径保持原样。该 ABI 修复没有改变候选数量、mixed-provider 最终证明、graph 或 compositor。

CPU 门实际编译 analysis 与 frontend，区分 named/preserved、已有背景边界、颜色/数据输出及一次转换；基线输入确实进入漏接 owner 后失败。它不执行 MSL，不作为半透明像素数值证明。相邻背景、默认采样、incumbent owner 门通过；结构门仍有原来的两项 inventory/classification 失败，未抬基线。

中间候选恢复四个阶段，却在float模式实际PNG中出现蓝→红→遮罩混合闪帧。原始日志证明同一media事件的frame70使用旧Timeline末值0，frame71才使用约0.999；current/previous已同时ready，FIFO独占readback也排除了截图重用。后继修复在D10既有共享模拟事务中投影已准入命令当帧值；命令在同帧只读投影，帧末仍唯一提交；普通空命令帧不增加完整解析，被拒 owner 的命令与 Script 值均排除，Script 优先级保留。系统媒体来源、音频/点击、全部动画分支及官方逐像素一致性不在本批结论中。


最终 Debug App dylib SHA256 `d4faf16fdfd06764b2ad7c86434f9f6c4508a419859f79bf64726af6f20adafe`，两种背景与连续换图三轮均退出0且GPU完成。原始日志中媒体事件首帧分别为67、68，连续换图两次为68/76；各激活层首帧 Multiply 均为1。真实PNG显示旧图→空间混合→新图，清空回作者默认；float中间版本的蓝→红闪帧不再出现于最终序列。连续换图证据仅证明这次序列重新启动并继续推进，不推广为所有动画或精确截图时刻的定时合同。

本批四个 previous stage 全部恢复，两模式实际 GPU 执行并集44/73→48/73（约65.8%），终端 compositor 消费25/37层；这是操作覆盖下限，不是样本完整正确率。最近 Timeline/Snapshot/owner-admission CPU门48/48、shader输入ABI门4/4及相邻三个模块通过；旧 owner 的有效行为红例、Debug build与独立只读审查用于闭环。

最终证据包 `.artifacts/scene-evidence/runs/media-transition-20261005/final/samples/2938612768/runtime_evidence.zip`，12,494,012字节，SHA256 `86ec7dbffc57bb6e94e8509b657c13550f99c58b0f4353253a945d6642bd4d16`。81个payload逐文件哈希与ZIP CRC通过，保留14日，包含基线跳变、过渡恢复后的首帧反例及最终三轮日志和有限PNG，不含真实样本包或App。清理本轮旧App、隔离HOME/样本与重试缓存，复用一份构建缓存及最新已验App。
