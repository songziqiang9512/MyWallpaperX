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


## 2026-10-09：发光脚本与嵌套属性

本节扩展上文当时明确排除的 emission 与 nested user 范围；上文旧范围不再代表当前能力。设计先落于 runtime-architecture §3.4 并登记：复用候选、属性编译器及原资源准备，禁止第二材质 VM/算法/当前值 owner；通过后本节留执行证据，稳定合同仍归架构。

首断点与实现：模型 renderer 已有 `emissivecolor/brightness` typed consumer，候选投影却只枚举 alpha/color/brightness，且排除 nested user。现将可选发光字段补入同一投影，排除必需通道已占用的别名；不扩展必需 ShaderSchema。RuntimeModel 把已投影的 target/inputs 交现材料属性编译器，image/model 共用原 nested lowering。live target 使用同一完整材料路径编码；所有当前值仍归 property snapshot 和共享 VM。原资源 prepare 的动态声明需求补 script，与 user 一样在 seed0 时准备 mask；编译失败没有 live owner，声明预留不冒充执行。缺 mask 仍只关闭发光，普通帧不重新解析或加载。

U12 原作者 layer47 `townfbx/Image_3.json` 的脚本 seed=7.4299998，nested `minvalue` 绑定 `windowsresponsetoaudio1dontrespond`，`smooth` 绑定 `smoothaudio`。project 缺省 minvalue=1（不响应音频），不是 wrapper fallback0：因此默认应保持常亮，本批不宣称默认整体颜色再次改善。独立 `emissivecolor.user` 继续原属性链。

有界验证：

- 原始脚本 bytes 经真实候选和 QuickJS，固定谱输入0/0.25/1、minvalue0返回0/1.85749995/7.4299998；minvalue1恢复7.4299998；smooth4首帧沿作者缓存返回0.75。该实验是 typed spectrum 输入，不冒充真实采集或GPU parity。
- 当前签名 Debug App，原包/原project隔离副本，0 PCM，经现 capture-service/FFT/inbox：常亮→响应→常亮全部 live accepted，surface和窗口ID不变。预登记前窗ROI RGB均值123.91/119.81/62.94→51.29/47.54/41.58，左窗69.92/70.08/38.48→24.97/23.28/20.49；屋顶52.09/34.31/34.39完全不变，恢复常亮后三个ROI精确回到默认值。说明切换影响真实窗光且未重建窗口，不证明产品App→daemon属性UI全链。
- 宽频PCM实际进入该 material owner；所取截图第0频段未亮窗，结果与静音一致，不能将 nonSilent 或 callback计数当作该截图的音乐视觉验收。
- VM最小门原3通过、新3失败；修复后6通过，覆盖零seed、两实例/材质路径隔离、nested同帧输入、非法返回/Float溢出保旧与恢复、别名不重复、冲突拒绝。真实property/live state和资源reader/prepare另8方法通过；mask缺失或typed加载失败保留peer（transport边界故障注入），rejected part不准备。7组相关回归通过（其中8项需额外集成输入而跳过），未将skip计为通过。

构建App SHA256 `f886aa4546e02e5fbe9291920fb1eeaa81d5b5ed5bc26c127cff880f00a5966e`，Debug dylib `d548ecea7490b4b401964f3eae7813356420fc082b6d4cc2d85131280d605371`；4239源码hash与构建前后一致，签名严格验证通过。原pkg SHA `e524945b1152f50c0be83d7f40dfd4003663d86060728737ac78a615826b9dbe`、project `ae4174518663ecc55d78aea6298a09abfccda806caa23997e5b943649efc20cb` 均未变；所有运行exit0。证据根 `.artifacts/tmp/u12-material-script-inputs-20261009`，原输入/ROI/构建/脚本/测试各有独立收据。

受益面是已有static-model consumer的五类数值脚本及嵌套实时属性，不按U12选择行为。U12月亮低频/颜色、整体彩色与其他模型能力仍开放；不证明所有样本、官方精确音频包络、长稳性能、HDR或发布。本文新增正文预算用于记录已实现的跨候选/属性/资源合同，其余现役状态只用短指针，不复制本节过程。
