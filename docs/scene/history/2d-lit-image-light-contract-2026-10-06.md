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
- 实机：P3DG/P3DN（point 类灯+静态球）在我方引擎渲染全黑=3D 分流生效（此前两类都会点亮球）；IMG5L/IMG5U（point 类灯+lit image）在我方引擎 image 区域仍全黑——**2D lit 接合预存缺口**：lit capture 未对夹具/语料形态启动（img5l 与 2815826216 运行日志均无 lit 线索），先于本批存在，登记为独立后继批（2D lit profile/管线准入排查）；合同数值部分（k/衰减/分流）已经 harness oracle 与编译验证。
- 预存红（非本批）：`test_scene_frame_rejection_fault`、`test_scene_resolved_material_runtime_bridge`、`test_scene_utility_layers`（源形状/源清单漂移，均未涉本批文件）。

## 开放

2D lit 接合缺口（我方 lit image 对 point 灯全黑的产品排查）；spot/directional 对 2D 图的官方合同未探（当前保持既有消费）；2D 路径 ambient 律（平坦/斜坡）未探；k_2D 精确值 ±5%（1.85±0.1）；光 z 对 NdotL 之外可能的第二作用未分离。

## 证据

官方 18 夹具+捕获、我方 4 次运行，298 文件逐 SHA manifest，`/private/tmp/mwx-light3-20261006/2d-lit-image-light-contract-20261006.zip`（`87b870ed…886c`）。
