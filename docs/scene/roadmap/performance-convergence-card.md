# Scene 性能测量与改进

<!-- document-role: active-plan -->

本页保留测量方法和当前可检查的成本入口，不维护旧实验成绩。实际兼容缺口先按[开放队列](scene-open-breakpoint-queue.md)定位；实现边界归[架构](../architecture/runtime-architecture.md)。没有同条件数据，不声称现阶段 CPU/GPU、内存或能耗已改善。

<a id="measure"></a>
## 同条件比较

1. 固定源码/App、硬件、系统、输入文件与属性、pointer/audio/media、显示拓扑、viewport、分辨率与构建配置。冷/暖 cache 分开，先保存原值和测量窗口。
2. 同时记录输入到可见/事件输出与 CPU/GPU 成本。区分准备、模拟、encode、提交、presented 和后台工作；attempt、GPU completed 与实际 presented 不是同一个计数。
3. 先用采样找最贵调用/分配，再做能排除候选原因的局部实验。GPU stage 区间可重叠；frame elapsed 不直接等于 shader 成本。
4. 旧/新交替重复，报告分布、噪声和失败；不在看到结果后放宽窗口、阈值或删失败。测量时避免构建、测试、导出和 profiler 相互争用。
5. 同输入确认内容、动画、属性、交互、暂停恢复和退出没有退化，再讨论收益。日志减少、代码变短、少几次调用或构建成功都不是整体性能结果。

工具入口：[scene_wallpaper_benchmark](../../../script/scene_wallpaper_benchmark.py)、[scene_wallpaper_performance](../../../script/scene_wallpaper_performance.py)、[verify_scene_change](../../../script/verify_scene_change.py)。使用前读取实际 `--help`和所选门的输入/断言，不在本文复制易漂移参数。

<a id="costs"></a>
## 当前成本调查入口

| 入口 | 代码可证事实 | 下一步应证明什么 |
|---|---|---|
| 复杂场景冷准备 | Host / RuntimeCatalog / Shader preparation 仍须解析、构造实际 Program 和设备资源；首 Surface 还有实例装配 | 区分必要工作与真正重复，测准备/主线程/后台争用占比；不先建新 scheduler/cache |
| 多 Surface 设备准备 | 每个 GraphExecutor 建立自己的 PassEncoder 并 warmup；encoder token/reset/target 是每屏状态 | 先测重复 library/PSO 构造是否显著，再判断原 repository/prepared-device owner 能否共享不可变结果；不能共享 frame encoder/history/目标 |
| 视频与资源长期驻留 | 应用预算、pool/cache、AV/driver/backing 与 in-flight 生命周期不同 | 同 PID 多次切换后核最后 consumer、对象引用和原生资源；区分可复用缓存、未完成 borrower 与泄漏 |
| 属性打开与热更新 | 未准备来源可能需要完整分析；值热更新与资源/结构重准备有不同路径 | 分别量打开、编辑到实际 consumer、重开/恢复；不以隐藏控件、丢定义或合并事件换响应 |

这些是调查入口，不是已经测定的瓶颈或性能回退。新的改造应有当前证据；没有可避免工作时停止，不为统一架构机械增加共享 cache、registry 或 wrapper。

源码：[Host 准备](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+Launch.swift)、[GraphExecutor 准备](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialGraphExecutor.swift)、[资源预算](../architecture/scene-resource-admission.md)、[视频 source](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Providers/SceneVideoTextureSource.swift)。

<a id="memory"></a>
## 内存与能耗的口径

应用计费是可控 allocation 的准入，不是 RSS。报告 active/candidate/retiring 叠加、decoded 与 GPU resident、cache 驱逐及真实对象释放；不要用进程退出、stop 清引用或 pool 数量代替同 PID 稳态回落。

冷启动和单帧优化不外推长稳能耗。CPU/GPU 同时比较，检查 FPS、画质与实际 workload；不能通过放慢动画、跳帧、减少粒子/特效或缩小输出宣称等价提速。系统电源/物理多屏结论需要相应硬件运行。

开发诊断保持显式 opt-in，普通播放不逐帧构造完整报告。GPU 采样、截图及其测量干扰遵守[诊断合同](../architecture/gpu-stage-timestamp-diagnostics.md)。
