<!-- document-role: active-plan -->
<!-- retirementCondition: 现役帧准入的互斥、释放与短重试通过反例门且合同并入稳定时钟架构后归档，不新增平行定时器。 -->

# D10 — 帧不重叠准入与 busy 重探测

> 复核基线：2026-10-01，独立工作树 `93b1b85a`。本文是设计裁决，不是当前能力或运行验收；合并到 `codex/engine-refactor-program` 时重新核对所列 owner。`approved` 仅表示本设计完成，阶段性 unknown 仍受本文准入门约束。

## 目标合同与设计判据

一条 scene session 的 CPU frame transaction 不可重入；资源有冲突的 GPU submission 不可重叠。busy tick 不推进可提交状态，短间隔再探测；真正 dropped/inactive 不当作 busy 无限重试。跨 frame driver、simulation、target lease 与 completion，触及唯一 clock/transaction 权威。

## 当前事实与证据

- `MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+FrameDriver.swift:15` 已有 busy retry interval，`:16` 为帧间隔八分之一且至少 1 ms；`:98` busy 调度，`:103` dropped 走正常 cadence，`:109` inactive 停止。
- 同文件 `:118` 每次 arm 先撤旧 timer；`:153` 在所有 surface 的 shouldDeferResolvedMaterialFrame 上阻挡 busy，`:169` 才快照/推进 clock。但 `:151` 已准备脚本 timer state，需通过 rollback 门审查，不能由 guard 的位置直接声称无副作用。
- `MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticlePlaybackState.swift:91`/`:111` 已有 prepare/discard；不是全新 FrameTimer 功能。
- 交接 Mirage clock-0/1 的 CAS 是实现候选；项目当前 owner 在主线程调度，复制第三方 gate 可能多出一个 authority。

## owner

现役 host frame driver owns tick 与 CPU transaction 准入；existing submission coordinator/target lease owns GPU 资源可用性；GPU completion 只释放自己的 submission token。timer、sceneClock、particle transaction 均沿原 owner，不加一个全局 busy Bool 统管所有生命周期。

## 方案设计与选型

选择**完善现有准入状态机，保留现役短重试**，不机械新增 CAS timer。主 actor 串行入口可直接维护 CPU ticket；若后来出现真实跨线程 tick producer，才在同一个入口用原子抢占或等价同步，不能两层 gate 独立裁决。

1. tick 先验证 session epoch 与 mode，再取得唯一 CPU ticket；在调用脚本、clock、particle/provider mutation 前完成可提前判定的 resource admission。不得持锁调用 VM/GPU。
2. busy 不递增已提交 frame index，不提交 timer 事件、粒子或 provider 状态。不能前移的准备工作必须有同 ticket 的完整 discard；pending 外部事件保留到后续成功帧且只消费一次。
3. CPU ticket 在全部 return/throw 路径 exactly-once 释放；提交成功后 GPU lease 留到真实 completion。command buffer 未提交时立即取消 reservation；部分 surface 已提交时只取消未提交者，已提交资源必须 drain，并沿现役 all-surface failure 合同处理可见/状态差异。
4. 维持现役 GPU 容量及 queue/hazard 合同；history 有依赖时串行，没有依赖的合法 submission 可在既有预算内重叠。**不把“CPU 不重入”扩大为所有 GPU 全局最多一帧**，那会撤销已证明的并发而无收益证据。
5. busy 沿当前八分之一 interval / 最低 1 ms 有界重探测，每 session 最多一个 timer；不 busy-wait，不固定堆积历史 tick。pause/teardown 撤销 timer，候选首帧重试继续沿现役有界 deadline。
6. completion 回调验证 epoch+ticket，反序/重复/旧 generation completion 不释放新 reservation。长期 GPU 无响应进入既有失效恢复，不靠无限快速探测解决。

## fallback / route

准入失败保留 previous-current 与未消费事件；dropped 保持正常 cadence，inactive 停止 timer。任何身份/lease 错配拒绝最小 unsafe submission。首选现役路径内修正，不增加新 route；若需线程模型迁移，observe-only 不能实际触发第二次 frame，然后才单点切换。

## 纠正门

- 可控时钟与 completion：重入 tick、busy 多次后放行、无 drawable、encoder 失败、提交后失败、completion 反序、pause/reload/teardown，断言 CPU 最大并发为 1、每 token 一次释放、仅成功事务推进状态。
- 区分 history 资源与独立工作对；验证前者不重叠、后者不被新 gate 意外串行化。保留现役 GPU 最大提交预算，测试不可硬编码“所有情况一帧”。
- 脚本 timer 在 busy 前准备的反例必须同时观察 C VM 与 Swift staged state；粒子、媒体/输入事件不重复或丢失，拒绝后 next-frame 与无拒绝序列对应。
- 检查短重试唤醒次数及延迟分布，不只看平均 FPS；性能主张需三次同 identity/window 的优化构建基线。当前设计文档没有运行此门，不能把已存在重试记成新性能完成。

## 退役条件

门与释放反例闭合、旧多余 gate/timer 撤销或证实不存在、合同进入稳定架构后归档。不得以新增 CAS 符号或测试全绿代替事务证据。
