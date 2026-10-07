<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。断点链见[L1 复测](l1-heavy-retest-2026-10-07.md)与[灯光送达](saturn-light-delivery-2026-10-07.md)；现役剩余归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

# 模型材质接口证明修复：#require 指令准入（2026-10-07）

起点 `be7780fe`。承接[L1 复测](l1-heavy-retest-2026-10-07.md)钉死的断点：土星全部 23 模型层 `model-material state=unavailable reason=shader-interface-unproven` → 模型以无光照回退渲染（盘面无明暗梯度、受光能量 0.44× 的共同根因；L1 期已同在，非新回归）。可复核的幸存运行证据=`/private/tmp/mwx-l1-retest-20261007/run-3589454154/app.log`（04:31 产品入口，恰 23 个不同层 422…724 同 reason；后续 probe 目录的日志已被灯光批重跑覆盖）。

## 根因（读证明器定位，非探针猜测定向）

`SceneResolvedMaterialShaderSchema+StaticModelInterface.swift` 的 `staticModelDirectivesAreSafe` 把 `.require` 列入无条件拒绝清单（与 `defineFunction`/`unknown`/`malformed` 同组）。而官方 **stock 照明 shader 全族**（generic4 等）的 fragment 都带 `#require LightingV1`（generic4.frag:75）——这一个 guard 就让**每一个照明能力 stock shader** 的模型材质接口证明必然失败。土星行星/环/卫星 23 层全部使用该族材质 → 全部 `shader-interface-unproven` → 无光照平坦渲染。

`#require <module>` 是引擎能力模块请求（元数据指令）：请求注入 LightingV1 的照明机制，**从不重写、重命名或条件化本证明读取的三通道声明**（g_TintAlpha/g_TintColor/g_Brightness 在 generic4.frag:37-40 无条件声明）。拒绝它没有安全收益，只有"全部照明 shader 无法证明"的代价。

## 修复（1 产品文件）

`staticModelDirectivesAreSafe`：良构 `.require` → `continue`（放行）；`.malformedRequire`（带多余 token/非法标识符的 require）与 `defineFunction`/`unknown`/`unsupported`/`malformed` 等真正重写指令**保持拒绝**。注释记录 3589454154 的 23 层反例。

## 验证

- 单元（fixture 编译真实证明器）：新增 `requireDirectiveAdmitted`（fragment 前缀 `#require LightingV1` → state=**authored**，keys/components 完整）与 `malformedRequireRejected`（`#require Lighting 1` → unavailable）正反例钉入 `test_scene_static_model_material_bindings`；模块 9 测试 OK。
- 门禁：verify_scene_change 对修复文件推导 12 模块套件 **ALL OK**（authored_normal/pbr_map/lit_image_layer/bindings/properties 等）。
- 实机：**被并行会话在途改动阻塞**——工作树构建包含其未提交的 `SceneAuthoredShaderAuxiliaryTexturePurposeAnalyzer` 新增 `dataChannelFacts/dataChannelDeclaration`（QF 批 3718261802 特性），土星启动即在其 `dataChannelDeclaration` 内 `Fatal error: Index out of range` 崩溃（崩溃报告 MyWallpaperX-2026-10-07-111927.ips，栈：reachableSamplers→analyze→dataChannelFacts→dataChannelDeclaration→Array subscript）。崩溃函数只存在于其未提交 diff，非本批路径缺陷。**待其批次落地后重跑土星 75s 探针**验证 23 层状态翻转与盘面明暗梯度。

## 覆盖面判断（保守）

放行 `.require` 只影响"带良构 #require 的 authored 合同"的模型材质证明——此前这些合同**全部**证明失败（本修复把不可能变可能），不存在"曾经可证现在不可证"的回归方向；malformed 形态与其它危险指令仍拒绝。同族受益面=使用 stock 照明 shader 族的全部模型层（土星 23 层为已证实样本）。

## 产物

崩溃报告 `~/Library/Logs/DiagnosticReports/MyWallpaperX-2026-10-07-111927.ips`（并行会话修复参考）；土星隔离副本重建于 `/private/tmp/mwx-l1-retest-20261007/workshop/`（旧 solar-layout 副本已被 /tmp 回收）。
