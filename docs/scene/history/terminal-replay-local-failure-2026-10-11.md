<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。职责归[运行架构](../architecture/runtime-architecture.md)，余项归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。
# 终端材质保留局部失败结果（2026-10-11）

基线98532068（隔离树e2291772）。最新App复验2877855240：六段Skew仍缺g_TextureReductionScale，但更早出现首帧超时。进程exit0不代表启动成功：没有ready和截图，启动明确launch-failed。日志中的人物333等失败是全帧丢弃后的传播，首个局部失败来自solid84后继Skew。

Execution从已成功准备的graph阶段生成effectFailures，记录安全passthrough。GraphExecutor已保留最后成功material的terminal replay，并为失败suffix可能覆盖的输入保留真实副本；FrameCommit却要求ticket.effectFailures为空，将局部视觉失败升级为整帧丢弃。修复只删除这一冲突条件，保留capability、epoch、ticket、真实output、外部依赖、目标、command buffer及一次性receipt检查；没有新fallback或compositor。

最新Debug App修后约18.836秒ready，持续12秒播放，人物、背景、文字、时钟可见，退出gpuDrained=true。原包SHA `3a3b1ff68529e885d4a9455cdc0b3b9b8aad55914a36615058a5231a7e1f2933`；App主程序SHA `dd7c17e6ba638e89f5a15e2d1bd4bad2462784c8737666687383e3391925b9ee`，dylib `71a1b019955b3b3fefe5a640b6d4714addf3e958a9477b6982668bd3ceb8c3d4`。同包、隔离HOME和内部Host验证，不能升级为桌面入口、长稳、性能或整样本官方parity；六段Skew仍未恢复。

5项terminal receipt测试修前只有新增局部失败正例失败，修后全通过；数据输出、错误目标/buffer、过期或重复ticket、无claim、编码失败仍不提交。原graph GPU测试3项通过，验证failed/inactive suffix保留最后材质及其真实采样输入。Debug构建通过，独立审查和最终门由本批收据绑定。

另按独立测试职责修正此前33项finalizer中的3个旧失败：实际straight graph输入与新颜色边界已受支持，旧断言却绑定历史PMA或要求拒绝。现验证真实slot、purpose/content、provenance、uniform字节及输出表示，新增straight内容误标PMA的真实拒绝反例，missing/stale等反例保留；33项全通过。它们没有shader draw/readback，不能冒充像素验收。

本机证据根`.artifacts/tmp/skew-reduction-20261011/`，before/after分开保存launch状态和App身份；terminal-graph、receipt与finalizer-contract各自保留门的边界。官方缩减参数研究保留在official（neutral-contract SHA `2270c2ecfcdc9097d9a9537aeb6983a2955e44fea70c52cc27b9b582b78c033a`；客户端2.8.0.42 SHA `daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07`）：有效ordinary solid/text、多stage、三档layer scale与两档viewport观察均与1相容；explicitFBO探针marker未到属无效，质量缩减仍未知，不能据此全域硬填1。后续继续Skew公共尺寸合同，不用样本开关补画面。
