<!-- document-role: stable-contract -->

<a id="scene-gpu-stage-timestamp-诊断合同"></a>
# Scene GPU 观测与诊断截图合同

本合同分别管理公开 Metal stage 观测与[诊断截图](#debug-capture-lifecycle)。两者观察既有执行链，不决定普通内容的准入、资源发布或 GPU 提交。现役选序归[性能卡](../roadmap/performance-convergence-card.md)，stage 方法的资格与边界归[原生记录](../history/gpu-stage-timestamp-qualification-2026-10-15.md)。不另建执行队列，不预支 GPU 或能耗收益。

## 入口与唯一职责

本节仅管理 stage timestamps：DEBUG、显式设置绝对路径 `MWX_SCENE_GPU_STAGE_TIMESTAMPS_OUTPUT` 时启用；`MWX_SCENE_GPU_STAGE_TIMESTAMPS_DELAY_SECONDS` 默认30，合法0–600秒，从首个原帧CB开始观察后计时。实际暖态仍须核对首帧完成到选帧的间隔。每进程只消费一个请求，失败不重试；JSON最多512KiB。非DEBUG走原工厂；停用时不逐pass加锁或分配。

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

<a id="debug-capture-lifecycle"></a>
## 诊断截图生命周期

截图只在 DEBUG 且显式使用 `--mwx-debug-scene-evidence-dir` 时启用。该模式为 readback 配置 surface，普通 SDR 播放保持原 framebuffer-only。`SceneDebugFrameCapture`拥有请求与独立 readback buffer，Session 负责把截图退出纳入既有停止链；它不持有第二套 Scene、资源图或输出 owner。关闭、替换、配额不足和导出失败只影响诊断请求，不能成为正常帧提交许可。

### 请求与资源额度

以下是可按实际内存和证据需求调整的项目诊断策略，不是 Scene 内容架构上限，也不承诺限制全部 RSS 或框架内部内存：

| 范围 | 当前策略 |
|---|---|
| 每个 capture 的待编码 required | 最多 2 个，超额请求显式 rejected |
| 每个 capture 的待编码 periodic | 最多 1 个，仅保留最新；被替换的已接纳请求报告 superseded 失败 |
| 全进程在 GPU、排队或 CPU 导出的 readback buffer | 合计最多 2 个 |
| 上述 buffer 的实际分配字节 | 合计不超过现有 resident 总额的四分之一 |
| 每个已接纳请求 | 恰好一次 persisted 或 failed；PNG 实际写成才算 persisted |

实际 buffer 只取得一份原生 allocation 租约，不能为诊断再登记相同资源的第二份成本。当前浮点导出使用 GPU 完成后的独立 buffer 原地转换；若增加可控 CPU 整帧副本，计入既有 decoded 子额。PNG 等框架内部暂存不冒充已被该额度完整覆盖。

### Submit 与导出

```text
显式请求 → capture 待编码队列
    → 原 PreparedFrame.submit 内追加 readback
    → 原 command buffer present / commit
    → 原 GPU completion
    → 独立 buffer 交串行 utility 导出
    → PNG 写成或显式失败 → 释放额度并结算请求
```

readback 只在原 submit 内、present/commit 前消费请求；cancel 或 seal 失败不消费。全进程 readback lane 暂满时请求仍留 pending，不阻塞普通提交。已选中的 stage timestamp command buffer 不追加独立诊断 readback，避免改变该次测量；请求仍由原队列等待后继提交或关闭结算。注册 completion 和 commit 前先计入 outstanding，覆盖 GPU 完成回调到导出排队的间隙。

completion 只向导出队列交独立 buffer、尺寸、颜色与请求值数据，不把 drawable、源纹理或 command buffer 交给长期 CPU 工作。所有成功、GPU 失败、分配/编码失败和写入失败出口都结算请求并释放一次额度。诊断 GPU 错误与产品原提交结果分别记录，不补采、重放或伪造成功。

### Close 与排空

`closeAndDrain`立即拒绝新请求，把尚未编码的已接纳请求逐项结算为失败。只有 closed 且 outstanding 为零，导出 drain 才完成；GPU barrier 只证明 GPU 已终结，不能替代 CPU PNG 导出完成。

Session 在 stop 清空 surface 前固定 active 与 retiring capture 集合；单个 surface 退役也保留 capture 到 GPU 与 export 均终结，失败出口不能漏掉集合。Runner 先进入 closing、拒绝迟到 launch/请求，再由唯一 Host 停止链排空；隔离 AppKit 退出沿 AppDelegate 的 `terminationReplyPending`等待并只 reply 一次。这不扩展 Web 或普通产品退出入口。外部 TERM/KILL 或框架强退不保证 graceful drain，不能添加假成功超时。

### 源码与验证

具体文件由[事实地图](runtime-as-built-map.md#diagnostic-source-map)维护。最近行为门为 `scene-debug-capture`，对应 `test_scene_debug_frame_capture.py`与`test_scene_debug_capture_shutdown.py`；GPU 接线变化再补真实截图与退出验证。历史设计和冻结结果分别见[生命周期设计](../history/debug-frame-capture-lifecycle-design-2026-10-06.md)和[原验收](../history/rf05-debug-capture-lifecycle-implementation-2026-10-02.md)，不代表当前环境重新运行通过。
