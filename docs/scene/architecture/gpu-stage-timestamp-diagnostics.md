# Scene GPU 观察与截图

<!-- document-role: stable-contract -->

观察由现有 Diagnostics / DEBUG runner 显式启用。它只读取真实执行，不成为资源、图、提交或输出 owner；关闭观察不改变正常播放。总体线程与释放归[架构](runtime-architecture.md#threads)。

<a id="timestamps"></a>
## GPU stage timestamp

`MWX_SCENE_GPU_STAGE_TIMESTAMPS_OUTPUT`选择输出，`MWX_SCENE_GPU_STAGE_TIMESTAMPS_DELAY_SECONDS`控制采样延迟。原 `SceneGPUStageTimestampHook`把一个真实 command buffer 与 runtime/frame/surface、graph effect、node 和 GPU sample 区间关联；不另提交通用 probe 或重复绘制。

counter sample buffer、descriptor attachment、resolve 和 CPU/GPU 时间校准使用同一设备与原 completion。样本越界、容量不足、unsupported、sentinel、缺提交/完成或陈旧 epoch 均使本次观察无效，不补零、不重放。当前每 buffer 的采样容量在实现中有界，观察对象随原请求/命令终结释放。

stage 区间可以重叠，累加不等于整帧或独占 GPU 成本；端点不证明覆盖全部 load/store/clear。长 elapsed 不能直接归因 shader 指令、ALU、texture limiter 或 GPU 利用率；校准到 sample 的时间还混有 CPU、提交与排队。

源码：[timestamp hook 与 sample 管理](../../../MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/SceneGPUStageTimestampObservation.swift)。测量条件与解释归[性能方法](../roadmap/performance-convergence-card.md)。

<a id="capture"></a>
## 截图请求与资源

截图在 DEBUG 且显式 evidence-dir 模式启用；普通 SDR 播放保持原 framebuffer-only。`SceneDebugFrameCapture`持请求和独立 readback buffer，Session 将其纳入原停止链。失败只影响诊断，不拒绝正常提交。

| 范围 | 当前策略 |
|---|---|
| 每 capture 待编码 required | 最多 2 个，超额明确 rejected |
| 每 capture 待编码 periodic | 最多 1 个，只保最新；被替换者结算 superseded |
| 全进程在 GPU/排队/CPU 导出的 buffer | 最多 2 个，实际字节不超过 resident 总额四分之一 |
| 每个已接纳请求 | 一次 persisted 或 failed；PNG 写成才算 persisted |

buffer 只取得原 allocation 租约，不能双重计费。浮点导出在独立 buffer 上原地转换；框架内部 PNG 暂存不冒充被预算完整覆盖。

```text
请求 → 待编码
  → 原 PreparedFrame.submit 内追加 readback
  → 原 present / commit → GPU completion
  → 独立 buffer 交串行 utility 导出
  → PNG 写成或失败 → 释放额度、结算请求
```

cancel 或 seal 失败不消费请求；readback lane 满时保 pending，不阻塞提交。被 stage timestamp 选中的 command buffer 不追加截图，避免改变该次测量。commit 前登记 outstanding，completion 只把 buffer/尺寸/颜色/请求值交 CPU 导出，不长期持 drawable、源纹理或 command buffer。

<a id="drain"></a>
## Close 与排空

closeAndDrain 拒绝新请求，结算尚未编码的已接纳请求；closed 且 outstanding=0 才完成。GPU barrier 不代替 PNG 导出结束。

Session 先固定 active/retiring capture 集合，Surface 退役保 capture 到 GPU/export 都结束。runner closing 后拒迟到 launch/请求，再走唯一 Host 关闭链；隔离 AppKit 退出等待实际 shutdown completion 并只 reply 一次。TERM/KILL 不保证排空，不能用超时伪报成功。

源码：[capture](../../../MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/SceneDebugFrameCapture.swift)、[Session drain](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+Shutdown.swift)、[submit](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+Submission.swift)。

观察改动先核真实换算、范围、stale/cancel 与预算，再以隔离真实 GPU/截图验证接线；CPU helper 或日志通过不能证明硬件采样或实际画面。诊断默认关闭，方法无消费者时应删除原 hook，而非另保框架。
