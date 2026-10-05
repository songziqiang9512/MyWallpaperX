<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# 模型材质值脚本接线与太阳近景（2026-10-06）

> **历史证据 — 非现役入口**。稳定职责见[运行架构](../architecture/runtime-architecture.md)，后续问题见[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

目标：外部 MDL 材料已保留的 alpha、color、brightness 脚本能驱动真实模型，包含共享状态触发的连续过渡。现有 `materialConstant(layerID, passIndex, name, materialPath)` 已有独立实例身份和 Metal consumer，缺少 SceneScript producer；不得借用 layer.color 或另建材料 VM。

准备期从 `SceneAssetCatalog` 保留的 ShaderValue、modelMaterialLinks 和 pass 0 投影 typed scalar/vector3 candidate，复用既有 SceneScriptVectorProgram、共享 QuickJS domain、预算、帧事务、失败与卸载。仅对有现役 static-model consumer 的层和明确消费的通道生成定义；材质路径只做资源身份。多 segment 各按真实材料路径区分，同一材料被不同层使用时各有 owner。与现有静态模型资源准备一致，初始隐藏模型也准备值 owner，以支持其他脚本后来显示它；不借用 layer.color 的初始可见准入。已有拒绝材料不重新准入。包装接受 script/value、可选静态 scriptproperties 和 null user；需新外部属性路径的动态 scriptproperties、有效 user、timeline 或未知混合 producer 暂不扩大，保留已有路径。数据必须完整有限且可表示，非法一个字段不阻断健康字段和其他模型。

作者脚本使用既有标量/Vec3 值执行能力，允许读取 shared、保留私有 JS 过渡状态，排在已有共享 producer 后求值；不放宽旧 tintback 的窄合同。owner 使用模型 layer 身份和 property-object 作用域；本片不新增 material handle、动态资源或图重建 API。普通帧仅发布 typed snapshot，原 StaticModelMaterial 消费并进入既有 Metal/compositor。动态 emission 与额外纹理需求、任意材质通道/动画混合不是本片范围。

验收：自有两实例同材料的 scalar/vector 脚本经实际 QuickJS→typed snapshot→原材料 consumer，验证 shared 状态变化、跨帧私有状态、实例隔离、坏返回局部保留、未知包装/材料拒绝、既有属性与 tintback 回归；Debug build 和真实太阳系标签双击近景，记录 callback、consumer 与最终画面。用原 App/输入作前后对照，不把可放大近景当成本片修复，不据本片声称官方配色或整景完成。产品终审后将稳定职责移交现有能力合同，删除窄设计登记。

## 实施与证据

批准设计已实施并获独立只读终审 ACCEPT；稳定职责归[运行时架构](../architecture/runtime-architecture.md#33-保留事务安全不扩大视觉失败半径)，窄登记退役。实现只扩展现有 candidate、layer identity 和 cursor registration；标量超出 Float 范围在发布前局部拒绝，原 Metal consumer 未另建分支。独立审查发现的初始隐藏模型漏准入已修，旧 layer.color/tintback 不变。

真实 `3662790108` 原包、no-intro、相同太阳标签双击：两版都能聚焦，因此聚焦不是本片修复；新版本去掉原来贯穿太阳和面板的白色曲面格线，太阳呈现作者脚本驱动的暖色及光晕。10 个材料字段、8 层完成 VM 回调，四个辅助曲面/曲环 alpha 输出0；1892 的 color/brightness 不再停在初值。最终 Debug dylib SHA256 `0314488bbf346ffa4bfad0d96930fa452f84e20ea0312569dd26efde583dfc24`，运行 exit0、gpuDrained=true。

验证：共享 VM→typed snapshot→原材料 consumer 的两实例、shared 切换、跨帧状态、坏返回/Float溢出局部保旧、hidden→peer 显示及 producer 冲突反例通过；旧 vector/owner/transform 与模型属性回归通过，Debug build及结构门通过。调试入口增加双击序列以复现作者交互，原单击/拖动保持；不新增窗口。最终审查冻结清单 SHA256 `39382140f630ab3c0aacfddd0fe933ae01baf091f17a0eb2f9c83f9d04dbbc76`。证据为 `/private/tmp/mwx-solar-interaction-20261006/runtime-evidence.zip`；最终近景保留原 PNG，基线与总览 JPEG 仅供定性审阅，不用于像素/HDR parity。

当前太阳系专项工程估计约55%，不是全样本正确率。下批处理右侧面板文字/底板重叠及可读性，回归其他行星聚焦；3D cursorWorldPosition 尺度仍需公开日志读回实验。本批不证明完整样本、官方色彩、动态材料 scriptproperties、长稳或性能。
