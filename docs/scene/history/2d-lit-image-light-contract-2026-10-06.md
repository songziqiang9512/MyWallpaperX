<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。3D 静态模型光照合同见[模型光照能量合同](model-light-energy-contract-implementation-2026-10-06.md)与[静态模型光照输入语义](static-model-light-input-semantics-2026-10-06.md)；2D 材质设计见[2D 光照材质](../roadmap/batch2/2d-lighting-material-design.md)。

# 2D lit image 光照合同与点灯类分流（官方黑盒 v3，2026-10-06）

起点 `09b33d0d`。以 18 个官方夹具钉定 2D lit image 的点光合同与官方点灯类分流语义，并落地产品代码。

## 官方黑盒结论（own-fixture，逐帧 PNG+输入 SHA 冻结）

1. **`point` 与 `lpoint` 按消费者分流**：`"light": "point"` 只照亮 2D lit image；`"light": "lpoint"` 只照亮静态模型，对 2D 图贡献恰为零（IMG5 黑 vs IMG6 亮对照；P3D 球黑 vs P 系列球亮对照）。官方语料 2815826216 同时携带两类正是此分工。首战（IMG1 系列）的"255 亮区"实为错误纹理黄色，初判 k_2D≥1.13 已废弃。
2. **2D 点光能量因子 k_2D≈1.85**（lit/unlit 同像素比值场拟合，r=1700 上 21860 样本 k 中位 1.82、p25 1.75/p75 1.92；r=900 交叉验证 p75 一致，中位受映射精度拖低）。强度线性（I=1→2 比值精确翻倍）。
3. **2D 点光衰减为纯平面距离** `(1−d_xy/R)²`——光的高度 z 不进衰减（无 z 项拟合误差 0.0014，含 z 项 0.0045，四律对比中最优且 k 离散最窄 9.4%）；NdotL 仍用三维方向。
4. **夹具形态坑（方法论）**：官方 2D 图像对象引用中间描述符 `{"autosize":true,"material":"materials/x.json"}`；材质纹理须 `.tex` 容器（PNG 引用→纯黄错误纹理带）；2D 图只在正交场景渲染（透视场景不画）。窗口↔逻辑空间映射非中心裁剪。

## 落地（4 产品文件 + 2 测试文件）

- `SceneLightSnapshot.swift`：`Point` 增 `illuminatesStaticModels`（lpoint=true/point=false，来自 definition.kind）；`shadowLights` 的点光投影槽按标志过滤。
- `SceneStaticModelPipeline.swift`：3D 编码只消费 `illuminatesStaticModels` 点光（数量同步过滤）。
- `SceneResolvedMaterialFramePreflight+LitCapture.swift`：2D lit 打包只消费 `!illuminatesStaticModels`（point 类）点光。
- `SceneLitImageLayer.metal`：点光项乘 `sceneLitImagePointEnergyScale = 1.85`；衰减改平面距离 `float3(delta.xy, 0)`（方向仍三维）。
- 测试：`test_scene_material_user_emission` stub 补标志；`SceneLitImageLayerHarness` 预言迁移新合同（平面衰减+1.85）。
- 我方解析器本就接受两类（旧注释放对同一 kind）——本批引入的是消费分流而非解析扩展。

## 验证

- 单元：`test_scene_lit_image_layer`（迁移后 oracle 全绿）、emission/pbr/authored_normal/pipeline/snapshot/point-shadow 等本批映射模块全绿。
- 实机：P3DG/P3DN（point 类灯+静态球）在我方引擎渲染全黑=3D 分流生效（此前两类都会点亮球）。
- 预存红（非本批）：`test_scene_frame_rejection_fault`、`test_scene_resolved_material_runtime_bridge`、`test_scene_utility_layers`（源形状/源清单漂移，均未涉本批文件）。

## 接合缺口收口（同日后继批）

前段记录的"IMG5L lit image 我方全黑"经追踪排查为**双因**：①夹具笔误——IMG5 系列误用 `lpoint`（IMG6 才是 point 类），我方按分流渲染黑是正确行为；②**真产品缺陷**——`SceneLightSnapshot.make` 的 lightconfig 门控把无 `lightconfig` 场景（语料 2815826216 实况）的 point 灯整灯丢弃（LITPACK counts=(0,0) 逐帧证据）。官方证据矩阵：lightconfig 只门控静态模型消费（N 系列=静态模型探针）；2D 图像路径不问 lightconfig（IMG6 无 config 亮、语料无 config 亮）。修复：`point` 类灯绕过模型预算直接入快照（模型四槽预算仍归模型灯；dir 应回归抓出的预算挤占问题当批修正）；`LightClassesDescriptor` 注释同步改述。终验：IMG6 我方渲染点亮且自渲染比值场拟合 k=1.907（应用 1.85 容差内、峰值比值 1.63≈官方 1.6）；**语料 2815826216 图像区从无光照变为 (116,0,0) 音频律动光晕**（两盏 point 灯+脚本强度 0.6 实际流入 LITPACK）。顺带偿清 directional_shadow 的 `SceneStaticModelMaterialBindings` 源清单漂移。

## 开放

spot/directional 对 2D 图的官方合同未探（当前保持既有消费）；2D 路径 ambient 律（平坦/斜坡）未探；k_2D 精确值 ±5%（1.85±0.1）；光 z 对 NdotL 之外可能的第二作用未分离；lightconfig 在场且 point=false 时 point 类灯是否仍照 2D 图（本批无界准入对该象限同样生效，官方证据只覆盖无 config 象限，未探）。

## >4 灯整包拒绝收口与零点哨兵修复（同日后续批）

前段登记的两项均已收口，另修复一项实施缺陷：

1. **>4 灯整包拒绝 → 有界截断**：`packLights` 保留调用方 authored 顺序前 4 盏（point 优先占槽、spot 取剩余槽），不再整包拒绝。混合灯数反例（3 point+3 spot→counts(3,1)、5 point→counts(4,0) 且 authored 半径顺序保持）进 `SceneLitImageLayerHarness` oracle；实机 5 盏 point 灯变体（IMG6Q5）渲染点亮不再回落；逐灯畸形（intensity/radius/cone）仍整包拒绝（原语义不变）。
2. **平面衰减零点哨兵缺陷（产品 bug，终审 INFO 项转实锤）**：前批平面 falloff 复用 `sceneLitFalloff`，其除零哨兵使**恰在灯正下方的接收像素**（`delta.xy=(0,0)`）返回 falloff=0 跳过该灯——正下方变黑。graph_executor 的 litCenter=0（角 194 与新预言精确吻合）实锤该路径。修复：点光环改为显式 `saturate(length(delta.xy)/R)` 平方衰减，无哨兵；正下方=最大值（合同平滑外推一致）。
3. **lit 族测试债偿清**（前批 k=1.85/平面衰减落地时未迁移的 oracle+两类源漂移）：`test_scene_authored_pbr_map`（map_oracle 迁移平面+1.85）、`test_scene_pbr_scalar`（stub 补 `staticModelMaterialBindings`、falloff oracle 迁移、malformed 键集补产品新增的 `Alpha`）、`test_scene_base_material_provider_binding`（HARNESS 删重复 `SceneEffectTextureInput` 桩）、`test_scene_resolved_material_graph_executor`（lit oracle 迁移、`overCapacityPayloadIsRejected` 改断言截断、`overCapacityPayloadKeepsSafeUnlitOutput` 随截断自愈）。9 模块 ALL OK。
4. **遗留开放（HEAD 预存、非光照域）**：`test_scene_authored_normal`（normal 纹理槽 validity 漂移，status=invalid fallback=flat-lit）与 graph_executor 的 `unselectedPotentialDoesNotRevokeSystemOnlyProgram`（system provider 程序撤销域）——stash 证 HEAD 即红，登记独立后继批。

## 证据

官方 18 夹具+捕获、我方 4 次运行，298 文件逐 SHA manifest，`/private/tmp/mwx-light3-20261006/2d-lit-image-light-contract-20261006.zip`（`87b870ed…886c`）。
