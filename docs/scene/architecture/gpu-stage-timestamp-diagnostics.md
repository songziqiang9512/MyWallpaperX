<!-- document-role: stable-contract -->

# Scene GPU stage timestamp 诊断合同

本合同限定原生一帧的公开 Metal stage 观测；现役选序归[性能卡](../roadmap/performance-convergence-card.md)，资格与边界归[原生记录](../history/gpu-stage-timestamp-qualification-2026-10-15.md)。不另建执行队列，不预支 GPU 或能耗收益。

## 入口与唯一职责

仅 DEBUG、显式设置绝对路径 `MWX_SCENE_GPU_STAGE_TIMESTAMPS_OUTPUT` 时启用；`MWX_SCENE_GPU_STAGE_TIMESTAMPS_DELAY_SECONDS` 默认30，合法0–600秒，从首个原帧CB开始观察后计时。实际暖态仍须核对首帧完成到选帧的间隔。每进程只消费一个请求，失败不重试；JSON最多512KiB。非DEBUG走原工厂；停用时不逐pass加锁或分配。

`opt-in → 原Telemetry选定CB → 原descriptor附点/真实draw事件 → 原提交或取消 → 原completion后CPU resolve → 有界JSON`。

- `SceneFramePerformanceTelemetry.debugEvidence` 独占请求及有界record；辅助对象只管理索引、manifest、换算和结果，不持有Scene/Program/资源图或授予准入、publication、提交、输出权。
- 选帧在原CB创建成功后、任何编码前。记录原CB/CQ/device、frameIndex/registry epoch、现coordinator observation/reset/effect/execution身份；原PreparedFrame在提交前借用FrameDriver的真实surfaceID，不新增identity。缺失或frame不符的身份不qualified。
- 在实际render descriptor创建处附VS/VE/FS/FE；复用encoder只记一pass。blit在同CB的`MTLBlitPassDescriptor`附start/end，不调用设备未支持的指令间sample。不拆encoder/CB，不增加barrier、提交、逐pass wait或replay。
- manifest记录实际成功创建、role/序号、可得layer/effect/command/ledger、目标/附件及索引；blit目前无尺寸/format。真实draw入口标yes；main关闭时按实际draw事件确认no，resource initialization明确no。unknown不得qualified，不由role、timestamp的0/sentinel或旧census猜有无draw。clear-only保附件成本缺口，不填零。
- 单shared sample buffer最多1024点，溢出即不完整，不扩容。选中CB关闭独立诊断readback；启动upload等独立CB不混入。CPU StageBoundaryObserver不作为硬件采样点。

## 时钟、生命周期与失败

编码前和原CB完成回调各调用一次`sampleTimestamps`，保留原UInt64 `(C0,G0)/(C1,G1)`。CPU时间按公开API纳秒单位处理，不再套rusage Mach tick转换；先检查差值，以`ΔGPU × (C1−C0)/(G1−G0)/1000`转微秒。保原值及比例；拒绝错误sentinel、反向/越界区间、非正校准跨度及非有限结果。

原CB `.completed` 且无error后才CPU `resolveCounterRange`，检查精确字节长度，不另建resolve blit/CB或主动等GPU。未提交取消退休同record；已提交buffer仅随原completion存活，encoder弱引用防identity复用，不强捕CB/renderer。原coordinator匹配identity的stop/reset/epoch失效使迟到record无效；不能由无关Session退出全局撤权。Telemetry reset仅影响自己的debugEvidence记录。buffer创建、GPU、resolve、陈旧或输出错误只使证据无效，保持原产品失败/回退，不补采。

stage区间可重叠，累加不是整帧、独占成本或利用率；端点不承诺覆盖全部load/store/clear。长elapsed不证明shader行、ALU或texture limiter；校准到首sample间隔还混有CPU准备、提交及排队，不能当CPU成本或GPU idle。只按已绑定事实选后继实验，真实优化仍按性能卡同条件验收。

## 验证与退出

最近CPU-only门`gpu-stage-timestamps`编译真实Telemetry/helper，覆盖换算、长度/范围、sentinel、draw/clear-only/vertex-only、取消/stale及overflow；不创建Metal设备或证明实际采样。GPU接线改动补隔离原生资格和原画面/停止检查。旧census仅交叉核，不能代完整descriptor/draw清单。

本合同接管先落库并独审的有界设计；一次原生资格已使该方法可供后继同条件GPU筛选复用，设计窄登记退出。每次请求终结后退休观察和buffer，普通播放保持原提交链；方法无后继价值或失效时删hooks及门，不保第二诊断框架。

公开依据：[采样](https://developer.apple.com/documentation/metal/sampling-gpu-data-into-counter-sample-buffers)、[resolve](https://developer.apple.com/documentation/metal/converting-a-gpus-counter-data-into-a-readable-format)、[时钟转换](https://developer.apple.com/documentation/metal/converting-gpu-timestamps-into-cpu-time)。
