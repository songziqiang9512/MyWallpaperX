# 静态源 draw-only 降级（unclaimed-visible-effects 家族，彻查②号缺口）

<!-- document-role: active-plan -->

- 日期：2026-10-01 · 状态：设计定案（主会话 authored；实现由工作流执行）
- 目标缺口：全样本彻查 78 缺口之 V=3 组首位——`unclaimed-visible-effects-static-source-graph-role-present`，真实样本 2938612768（layer 875/775，24 行归档命中）整层不绘制。

## 1. 根因（代码语义链，全部实读核实）

1. layer 是带可见 effect 的静态图 **provider**，其输出被可达 consumer 按命名图输入消费：`SceneDependencyRenderPlan+BindingCompilation.swift:128-136` 把"非直通安全（有可见 effect）的 provider"插入 `staticLayerSourcePassthroughBlockedLayerIDs`。阻断动机（`:253-260` 注释明示）：**base 图不得冒充命名图发布**——冲突面是"发布"，不是"绘制"。
2. 该层 effect 链编译失败 → `resolvedMaterialClaim == nil`（unclaimed）→ 组合器走降级直通。
3. 直通计划在 `SceneLayerSourcePassthroughPlan.swift:158-162` 因 `blocksStaticLayerSourcePassthrough && !allowsStaticSourceGraphPublication` 拒绝（`allowsStaticSourceGraphPublication = layerSourceGraphFallbackPublisher != nil`，见 `SceneImageLayerCompositor.swift:104-109`）。
4. publisher 只在 `geometryProduct == nil && requiresDemandedGraphOutputCapture(layer.id)` 时非空（`SceneMetalRenderer.swift:553-563`）；demanded 是运行期收窄集合（`SceneDependencyFrameRuntime.swift:94`），该层不在其中 → publisher nil → 拒绝。
5. `SceneImageLayerCompositor.swift:151-166`：unclaimed + 直通失败 → `return .failed`，整层不绘制。

## 2. 解法：发布与绘制分离的 draw-only 降级

**语义**：当直通计划的**唯一**失败守卫是 `.staticSourceGraphRolePresent`，且请求纹理本帧已解析（`request.texture != nil`）时，构造一个**不发布任何身份**的降级绘制计划：保留几何/混合模式/纹理帧守卫，跳过发布身份验证（publication 系守卫），在主 pass 直接编码绘制 base 纹理。命名图消费者侧零影响——它的绑定失败走既有 fail-soft（未绑定 consumer 的 base-source 回退已在 `:253-260` 注释中确立先例）。

**为什么安全**：降级绘制是纯主 pass 编码——不写 texture registry、不发布 layer-source 身份、不触发 demanded 捕获。阻断存在的原因（冒充命名发布）在 draw-only 路径上结构性地不成立。这与 publisher 存在时的行为互补：demanded 活跃走"捕获+绘制"，demanded 不活跃走"仅绘制"。

## 3. 实施规格（owned paths 与精确改动）

### 3.1 `SceneLayerSourcePassthroughPlan.swift`
- `resolve` 增加参数 `allowsUnpublishedStaticSourceDraw: Bool = false`。
- graph-role 守卫失败且 `allowsUnpublishedStaticSourceDraw` 且 `request.texture != nil` 且**其余守卫全部通过**（实现方式：graph-role 守卫从提前 return 改为记录标志，放行到计划构造；若后续守卫也失败则按原 reason 拒绝）→ 返回降级计划：plan 增加 `degradedFromPublication: Bool`（或 `SourceKind.degradedStaticFileDraw`，选对现有 switch 冲击最小的一种），SourceAtom 以 request 纹理与 layer 身份构造（kind 用现有静态源 kind、`requestIdentity: .layerSource(id)`、`resourceIdentity`/uv 从 `request.resolvedBaseTextureSample()` 取，与 `:151-153` 的 sample 校验同源）。
- **不变**：其余全部 rejection reason 的行为在旗标开/关两种状态下逐字不变（守护断言钉住）。

### 3.2 `SceneImageLayerCompositor.swift`
- `drawOutcome` 增加参数 `allowsUnpublishedStaticSourceDraw: Bool = false`，透传给 plan resolve。
- 成功分支区分降级：plan 为降级形态时 route operation 记 `degraded-static-source-draw-only`（outcome encoded/failed），返回值复用 `.layerSourcePassthrough`（renderer 的 fallbackBranches 计数语义不变）。
- unclaimed 失败分支保持原样（真正无纹理可画的形态继续 fail-closed）。

### 3.3 `SceneMetalRenderer.swift`
- 调用点传 `allowsUnpublishedStaticSourceDraw: layerSourceGraphFallbackPublisher == nil`（publisher 活跃时维持今日行为原样——保守对称）。

### 3.4 测试（红先行，先红后实现）
- 模块 `test_scene_layer_source_passthrough_coverage`（或该 family 既有归属模块，实现员先 grep 确认）：
  1. blocked 静态源 + 旗标开 + 有纹理 → 降级计划（断言降级标志 + 可绘制）；
  2. 旗标关 → 维持 `.staticSourceGraphRolePresent` 拒绝（守护）；
  3. 旗标开但纹理 nil → 维持拒绝（守护）；
  4. 旗标开但失败原因是其他守卫（如 layerBlendUnsupported）→ 维持原拒绝（守护：旗标只救 graph-role 一种）；
  5. 组合器级：unclaimed + graph-role 拒绝 + 旗标 → 编码成功 + trace 记 `degraded-static-source-draw-only`；旗标关 → `.failed` + 原因不变（守护）。

### 3.5 明确不做
- `image-source-required`（text 层源，3750813609，1 行）：无纹理可画，维持 fail-closed，登记。
- `publication-unavailable`（纯合成样本）：不触。
- 矩阵期望更新：2938612768 是矩阵样本，绘制 775/875 会改变 census/截图——**回放观察后再按 owner 复核流程另批处理**，本批不静默改期望。

## 4. 验证阶梯
1. 红先行单测（上列五断言组）→ 实现全绿。
2. 机器推导模块门（`verify_scene_change.py --path <三个 owned paths + 测试>`）。
3. 干净 worktree checkpoint 构建。
4. 2938612768 隔离副本回放（主会话执行）：期望 app.log 出现 `degraded-static-source-draw-only` 且 layer 875/775 路由到它；样本失败码与矩阵期望差异如实报告（不静默改期望）。
