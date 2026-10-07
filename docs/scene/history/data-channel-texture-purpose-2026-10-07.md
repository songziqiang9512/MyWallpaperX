<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。语义裁决与 fail-closed 边界见[render-graph-shader-coverage 当日条目](../capabilities/render-graph-shader-coverage.md)；工作卡见[断点队列 QF 段](../roadmap/scene-open-breakpoint-queue.md)。

# 数据通道纹理用途 source-proven 证明（juguangdeng 形态，2026-10-07）

起点 `b130c538`（批B 后工作树）。承接用户点名样本 3791967416（合成不全、特效不全）：层 23「后期处理层」两个 juguangdeng 聚光灯效果的 `texSample2D(g_Texture2, uv).ra` 通道采样被判 `texture-purpose-unproven` → `material-variant-envelope-texture-purpose` 精确 pair passthrough → 聚光灯暗化链整体缺失（人物身体不可见、白花背景灰蒙、顶部异常蓝线）。

## 先决事实更正

画质审查（2026-10-01）第三层#3 登记的「typing 喂 canonical 源全部失效」已由 `ec59195e`（2026-10-01）按「typing 分析 prepared 源」修复；本批残量是 prepared 源上的**诚实证明失败**——`.ra` 通道子集→标量链→mix 权重位的数据流不在 aux(phase/normal)/straight-color/spatial-weighted 三个证明器覆盖内。审查文档已补核对注记。

## 修复（2 产品文件，沿既有分析器加 Role，守 shape-analyzer-fleet 棘轮）

- `SceneAuthoredShaderAuxiliaryTexturePurposeAnalyzer`：新增 `.dataChannels` Role 与 `dataChannelFacts` 生产者。证明形状=`vecN t = texSample2D(slot, uv).swz`（单字母族真子集投影，长度=声明宽度<4）；t 只允许 `.分量` 读；float 局部经标量算术+十函数白名单（saturate/abs/min/max/clamp/smoothstep/floor/ceil/fract/mod）传递闭包；闭包成员只允许出现在 `mix(a,b,t)` 第三参（权重位）或白名单参数位。fail-closed=whole-vector、mix 前两参、非白名单调用（含构造器）、裸标识符、复合赋值、gl_FragColor 非权重位、语法诊断、同槽歧义。phase/normal 证明器逐字节不变。
- `SceneResolvedMaterialShaderSchema.sourceTypedAuxiliarySamplers`：门槛删除 `defaultTexture == nil`（juguangdeng 的 `particle/halo_6` default 即现实形态）；`.dataChannels`→`.preservedChannels`；default 在 stock registry 已登记且冲突时跳过 fact（registry 保持权威），最终仍过 `purpose(for:)` 三方仲裁。**有意变更**：该放宽同样作用于 phase/normal 的应用包络（批前 default 携带使全部 fact 作废，批后按冲突仲裁）。

## 验证（2026-10-07，隔离根 /private/tmp/mwx-sample4，Debug App）

- 3791967416：`texture-purpose-unproven` 2→0；层 23 全部五个效果 encoded-output；截图人物身体恢复、背景暗化（对照官方聚光灯构图）。层 265/271/275/57 的 tech_circle_barcode `color-contract-unproven` 残留归 E5 ②-e/②-f（colorTransfer 残类，另批）。
- 门禁 37/37 模块全绿（verify_scene_change 推导集，510s）；`test_scene_source_proven_auxiliary_texture_purpose` 扩 4 正例+5 负例（dataChannel/renamed/withDefault/withUnregisteredDefault；wholeVector 单通道不触发/colorOperand mix 颜色位/outputAlpha 输出位/bareUse 裸向量逃逸/conflictDefault registry 胜出）；结构门（dependencies/defense/residue/code-health/design-gate/document-health）全绿。
- 回归：3226487183 失败清单为批A 后严格子集（零新增）且组合效果遥测逐层一致（2522/115975/1625/2168/982）；3809618616 启动 3.4s/零拒绝/teardown 干净（loaded=0 与 833227004 的 hover 族=已知真实时间抖动）；批B 成果（零 stage-link 拒绝）保持。
- 冷缓存注意：分析器改动使 launch-result-cache 失效，3226487183 隔离 HOME 冷启动 ~62s 会挤掉 duration+60 预算内证据窗（批A 后已存在同族，验证用 duration≥25 且以遥测为行为证据）。

## 独立审查

首轮 REJECT：分析器核心经系统性反例构造未发现误证明（嵌套块/helper 逃逸/重赋值/mix 颜色位/构造器/负号折叠/单字母碰撞全部 fail-closed），但 P1×3=裁决卡门槛句与实现矛盾（「无 default 纹理」幻影不变量）、dataChannels 零 fixture、phase/normal 包络变宽未声明。处置后 APPROVE：卡重写（default 语义/十函数白名单/包络有意变更声明）、fixture 补齐并实测绿、P2（claimedSlots 防御死代码/白名单参数位标量调制/registry-declared 不对称）登记保留。

## 边界

- 官方 parity 未验（聚光灯形状/边缘模糊的精确视觉对照留用户实机）；tech_circle_barcode color-contract 残类、phase-with-default 专属 fixture 登记为后继。
- 833227004（flowimage planned=0）与 3809618616 底图（genericimage4 不绘制）归批D material-only 路由。
