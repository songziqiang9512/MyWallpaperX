<!-- document-role: stable-contract -->

# 前级图像与模糊结果合成准入

<a id="previous-blurred-composite-admission"></a>

本合同修正现有 MaterialProgram 的准入范围；不新增 Blur 算法、profile、graph 或输出 owner。目标是让合法 authored 采样量和等价资源名称沿原编译、typed binding、GraphExecutor 与唯一 compositor 执行。当前状态与运行边界归[图与shader覆盖表](render-graph-shader-coverage.md)，开放项归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

**设计决定（2026-10-12，实施前）：** `scale` 是作者采样量，不是 render-target 尺寸除数；[官方说明](https://docs.wallpaperengine.io/en/scene/effects/effect/blur.html)定义其控制 X/Y 模糊量，未声明 `0.01…2` 上限。本片撤销上限；保留现有一/二分量 shape、两 pass 同源相等与 `>=0.01` 有界 cohort，并要求有限 Float 可表达，保留 author 值，不截断、猜值或按样本放大。`0.01` 下界仍是待替换的旧准入偏差，不冒充官方范围；零、负值、更小采样量留待独立行为验收。极大值的视觉意义仍由作者代码承担，不承诺所有 Float 值 GPU 算术有限或官方像素一致性。静态、user、Timeline 各自沿现有 producer 与 ABI 证明，不扩大 SceneScript 准入。

**职责与取舍：** GraphAdmission 验证既有四 pass、两 effect-local quarter targets、输入/写读顺序、格式/state 与常量形状；definition/material/shader 路径仅用于原资源查找，不能证明执行语义，因此撤销本 owner 的名称 gate。OwnerAdmission 仍验证 utility 生命周期及 scale producer；每个源、typed slot、uniform/variant 和完整 stage 必须通过原 generic compiler/Eligibility/Program 证明才获得执行权。有限 scalar→float2 仍复用原 UniformProjection，不增另一套转换。优先扩现有链路，避免 stock 名称绑定和新专用 backend。

**失败与退出：** 资源身份/hazard/ABI/producer 失败拒绝最小不安全 stage；普通编译或可选视觉失败沿已有 typed passthrough。无 profile、旧 owner 或 fallback 变更；不得因为路径改名恢复 dedicated owner。现四 pass cohort 与 source analyzer 有界形状属迁移偏差，集中登记于[兼容例外](../development/development-workflow.md#compatibility-exceptions)，由更宽 Program 证明及真实正反验收替换。

**验收与停止：** 自有输入复现旧数值与改名拒绝，改动后验证变量/资源改名、等价表达式、Float 溢出、不同 pass 值、错误 binding/target/state 与未证动态 producer；须检查 actual compiler→GPU 像素及两个连续 frame。另用未参与修法的真实样本验画面，实际主样本两段运行及末合成；路由命中/非黑/构建不等于视觉完成。二级拒绝另按最早 owner 处理，不修改私有算法；无可見收益不能宣布本批兼容闭合。
