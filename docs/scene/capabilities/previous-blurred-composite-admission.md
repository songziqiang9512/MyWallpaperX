<!-- document-role: stable-contract -->

# 前级图像与模糊结果合成准入

<a id="previous-blurred-composite-admission"></a>

本合同修正现有 MaterialProgram 的准入范围；不新增 Blur 算法、profile、graph 或输出 owner。目标是让合法 authored 采样量和等价资源名称沿原编译、typed binding、GraphExecutor 与唯一 compositor 执行。当前状态与运行边界归[图与shader覆盖表](render-graph-shader-coverage.md)，开放项归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

**设计决定（2026-10-19，零轴修订）：** `scale` 是作者采样量，不是 render-target 尺寸除数；[官方说明](https://docs.wallpaperengine.io/en/scene/effects/effect/blur.html)定义其控制 X/Y 模糊量。原 vertex 各轴以 `g_Scale` 乘采样偏移并除对应 texture resolution，FBO 则独立使用 extent scale。沿现有 generic Program 准入每轴非负、Double 与转换后 Float 均有限的一/二分量值，撤销旧 `0.01` 下界；零轴重复同一坐标采样，全零仍执行原两 pass 和 downsample/combine，不等同跳过整个效果。保留作者值及 Float 的既有转换（含微小正值下溢为零），不截断或放大，不新增滤波与输出 owner。两 pass 同源相等、shape、source/state/资源及各 static/user/Timeline producer 证明保持；已有动态值校验合同不扩大。负值、缺字段、非有限与 Float 溢出仍拒绝，真正零尺寸 target 仍由独立 extent/资源门拒绝。极大非负值的视觉意义由作者代码承担，不承诺所有 Float 算术有限或官方像素一致性。

**职责与取舍：** GraphAdmission 验证既有四 pass、两 effect-local quarter targets、输入/写读顺序、格式/state 与常量形状；definition/material/shader 路径仅用于原资源查找，不能证明执行语义，因此撤销本 owner 的名称 gate。OwnerAdmission 仍验证 utility 生命周期及 scale producer；每个源、typed slot、uniform/variant 和完整 stage 必须通过原 generic compiler/Eligibility/Program 证明才获得执行权。有限 scalar→float2 仍复用原 UniformProjection。终端direct-red mask须为typed opacityMask；显式槽保持非空asset候选，缺席时可消费原sampler的typed asset default，不用default救不合法override。资源readiness、purpose与publication仍归原resolver。

**失败与退出：** 资源身份/hazard/ABI/producer 失败拒绝最小不安全 stage；普通编译或可选视觉失败沿已有 typed passthrough。无 profile、旧 owner 或 fallback 变更；不得因为路径改名恢复 dedicated owner。现四 pass cohort 与 source analyzer 有界形状属迁移偏差，集中登记于[兼容例外](../development/development-workflow.md#compatibility-exceptions)，由更宽 Program 证明及真实正反验收替换。

**验收与停止：** 自有输入复现旧数值与改名拒绝，改动后验证变量/资源改名、等价表达式、Float 溢出、不同 pass 值、错误 binding/target/state 与未证动态 producer；须检查 actual compiler→GPU 像素及两个连续 frame。另用未参与修法的真实样本验画面，实际主样本两段运行及末合成；路由命中/非黑/构建不等于视觉完成。二级拒绝另按最早 owner 处理，不修改私有算法；无可見收益不能宣布本批兼容闭合。

**2026-10-19 有界后验：** 原GraphAdmission仅将下界`.01→0`；11方法准入门与四个自有真实App/GPU模式门通过，负值/Float非法、两pass同源与原shape/state/producer/资源证明保持。原360由整段拒绝转四Program/GPU执行，但目标细条被后画UI大幅覆盖且camera阶段不同，未辨独立视觉收益；只闭旧数值首拒，不认完整Standard Blur或整图闭合。未参与修法的213原包短窗主体可见、after-only边界保留，详见[零轴后继](../history/previous-blurred-composite-admission-2026-10-12.md#zero-axis-followup-20261019)。
