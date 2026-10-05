<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# 原生透视 Scene 的鼠标世界坐标（2026-10-06）

> **历史证据 — 非现役入口**。现役合同见[SceneScript API](../capabilities/scenescript-api-coverage.md)，后续工作见[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

首断点：surface polling 始终反投影正交画布，使原生 3D Scene 的 `input.cursorWorldPosition` 错取二维像素平面。修复复用唯一 `SceneParticleCameraFrame` 的 native eye/basis、FOV、zoom、viewport 和 farZ，解析远平面点，避免大 far/near 比的 Float 逆矩阵抵消。普通帧只做向量运算；非法值局部拒绝，越界拖动不截断。2D polling 保留原正交出口；`event.worldPosition` 仍是层命中点，与 polling 各有独立载荷，不新增相机或脚本 owner。

## 官方行为与边界

官方客户端受控自有探针，eye=(0,0,10)、center=0、FOV=50、2268×1473：client=(1134,736) 得 world=(0,3.165749073,-9990.00097656)，client=(1701,736) 得 (3589.904785156,3.165749073,-9990.00097656)。仅 farZ 从10000改5000，X/Y减半、Z=-4990。只消费自有 console 前缀，输入前后hash一致；探针脚本与原始回执由官方研究产物保留。旋转姿态尝试未成功生效，不计官方旋转证据。

实现回归另覆盖旋转、active camera、zoom、resize、越界、非法输入；实际 QuickJS owner 失败重试保留不同的 polling 远点与event命中点。它们是项目回归，不外推官方全部相机组合或事件语义。

## 产品验证

Debug build成功；camera/geometry 34、真实VM owner事务11、surface/capture18项回归通过。真实太阳系原包仅关闭开场：标题栏内NDC (0.8,0.06)→(0.6,0.08)拖动，layer1256完成Down/Move/Up，信息面板可见向左上移动并在松开后保持，媒体面板不跟随。最终3024×1964原始PNG、命令、日志与identity保留；exit0、gpuDrained=true。Debug dylib SHA256 `02c162ac77a87207302960b0d75effaeef0d08c81fbdfd4ed93b13a839c839f6`。先前一次大步越出旧标题栏触发作者cursorLeave取消，只记方法反例。

本批证明native polling坐标及一个真实拖动消费者，不等于面板所有拖动/官方像素比例、旋转相机官方对照或整景验收。轨道仍呈散点：实际通用MSL保留线段插值、out/inout与float，2048²工作纹理下线宽约0.307 texel，是下一批欠采样验证入口；不改作者采样数或按shader名特判。太阳系专项约58%为工程估计。

结构13项中两项仍失败于既有`shape-derived-analyzer-fleet`66/65登记，错误列表与已验证HEAD完全相同；其余结构及依赖、代码健康、defense、设计、测试断言和文档门通过。证据根 `/private/tmp/mwx-solar-input-20261006`，最终只留限量压缩日志/原图和复验脚本；临时App、样本副本、HOME与重试输出在提交后清理，单份构建缓存沿用。
