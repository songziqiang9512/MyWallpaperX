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
