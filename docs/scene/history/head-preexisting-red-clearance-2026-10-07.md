<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。mixed provider 合同见 exact mixed provider admission 引入提交 ae6aaad4 的语义边界与 `SceneResolvedMaterialMixedProviderSlotFact`；2D lit 光照合同见[2D lit 光照合同](2d-lit-image-light-contract-2026-10-06.md)。

# HEAD 预存红偿清批（lit oracle 迁移/utility 断言迁移/mixed 证明收口，2026-10-07）

起点 `5f55de4f`。承接 [2D lit 光照合同批](2d-lit-image-light-contract-2026-10-06.md)登记的独立后继批，偿清当时 HEAD 的三项预存红。产品改动仅 2 文件（mixed ABI 收口），其余为测试预言/形状断言迁移。

## 1. `test_scene_authored_normal` — harness oracle 未随官方 2D lit 合同迁移

**登记归因修正**：前批登记为"normal 纹理槽 validity 漂移"，实锤为**测试预言债**——`SceneAuthoredNormalHarness` 内两处 oracle（`check()` 与 `atlasOracle()`）仍用 3D 距离衰减且无能量因子，而产品 shader 已按官方黑盒合同（[2D lit 批](2d-lit-image-light-contract-2026-10-06.md)：平面距离 `(1−d_xy/R)²` + 点光能量 ×1.85、NdotL 保持三维）渲染。oracle 落后导致 `precondition(maxError < 0.002)` 崩溃（-5），报告从未打印，validity 状态本身全部正确。

**落地**：两处 oracle 迁移为平面距离 + ×1.85（方向保持三维归一）。产品零改动。

**验证**：19 格式用例全过、19 合同全 true，`maxOracleError=0.000157`、六项 `uvOracleErrors ≤ 0.00032`（迁移前 0.06–0.21）。

## 2. `test_scene_utility_layers` — `userPropertyDemands` 形状断言迁移到 launch owner

`0d666304`（user-texture-live-update 批）把共享 MaterialProgram 的 demand 聚合从 `SceneMetalView` 迁到 launch 路径并增强 live update；行为合同未丢。断言改指新 owner 并钉三条链：

- `resolvedMaterialCatalog.userPropertyDemands`（catalog 侧聚合）
- `.union(baseMaterialProviderBindings.userPropertyDemands)`（provider 侧并集）
- `requestedIdentities: userTextureDemands`（聚合结果真正进入 loader 请求）

删除无消费者的 `METAL_VIEW_SOURCE` 常量。行为核：`satisfiesRequiredProperties` 门与 `SceneUserPropertyTextureLoader` 请求消费在同一 owner 内。

## 3. `unselectedPotentialDoesNotRevokeSystemOnlyProgram` — 0781cc73 ABI 拓宽误触发 mixed 证明（产品缺陷）

**归因链**（三桩插桩固定，均已还原）：

1. harness stub plan 对 potential-only 场景不产 binding（`matches=0`）——计划层无 external 来源；
2. `.externalPrimary` 实际产生于 Program 编译后的 `finalizeDependencyOwnership`：`ownership=.none` + `potentialBindings=1` + `resolved=[exactMixedOptionalFallback L81→L879 s1]` → `expandedPotentialBinding` 提升为 externalPrimary；
3. 该提升要求 `provesExactMixedNamedFallback(slot:1)` 为真，其"存在 premultiplied 颜色 ABI 变体"条件在 `0781cc73`（2026-10-05，preserve ordinary shader color input ABI）后对 ordinary-shader profile 恒可满足——该提交把 `premultipliedColorAuxiliarySlots` 并入 ordinary+color 输出的 `premultipliedColorInputSlots`，而 system-only 场景的 mixed 槽（named 下位候选+system 顶层候选）经 `selectedMixedPremultipliedSlots`→`terminalNamedSlots` 早已进入 aux 集合。

混合形状（overlay 混色 shader）编译为 `source-proven-graph-input-color-blend` profile、不受影响；只有 ordinary 标量辅助形状被误提升——恰好推翻 ae6aaad4 划定的"descriptor-only system/named 候选不升格产品依赖权威"边界：未选中的 potential 使 system-only program 被外部 provider 权威征用，provider 层未准入时整个消费层被丢弃（可见回归面）。

**修复**（2 产品文件）：`resolveVariantFrontend` 增 `mixedProviderSlots: Set<Int> = []` 参数；ordinary-shader profile 的 premultiplied 集合减去 mixed-provider 槽（用与 mixed 合同同源的 `mixedProviderSlotFacts` 权威推导，产品 `+Compilation` 调用点传入）。source-proven 各 profile 与 0781cc73 自有合同（typed aux 颜色输入/背景边界/非 color 输出）不动；typed-input-lowering harness 不编译 ProviderSlots/Compilation，默认参数保持其直接调用不变。

**验证**：`test_scene_resolved_material_graph_executor` 全绿（此前 270/271）；`test_scene_generic_shader_typed_input_lowering` 4 测试全绿。

## 门禁复验

`verify_scene_change.py --path` 对两个产品文件推导 33 个 focused 模块（material-program/render-graph/shader-source-set-conservation 组）+ 治理门；三模块（authored_normal/utility_layers/authored_normal 集成跳过）单独复跑全绿。checkpoint Debug build 与 focused 套件结果见下。

## 开放

- mixed 槽在 ordinary shader 中绑定下位 named 颜色发布时的 premultiplied 输入 ABI 仍为 pre-0781cc73 行为（raw）；若真实内容需要该 ABI，须先定 mixed 合同对该组合的官方行为，不得静默恢复拓宽。
- 官方黑盒余项沿用前批登记：spot 朝向约定、pitch 效应、2D 路径 ambient 律、spot/directional 的 2D 合同、`lightconfig` 在场且 point=false 象限、点光与方向光响应曲线不一致。
