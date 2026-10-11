<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。当前任务从[断点队列](../roadmap/scene-open-breakpoint-queue.md)继续。

# 采样 alpha 重建接纳标量局部形态（2026-10-10）

固定基线 `24af7e26`。本记录只说明同一 `same-alpha reconstructed RGB(A)` owner 新增接纳的第二种 authored 形态及其证据边界；能力范围由[Render Graph 覆盖](../capabilities/render-graph-shader-coverage.md)维护，本记录不是样本验收或发布结论。

## 首断点与实现

原 owner 只认“一个 `vec4` carrier 先由 snapshot 整体拷贝、再逐分量改写”的形态：snapshot alpha 保留时 `reconstructed.ga = texSample2D(slot, uv).ga`，否则四分量的 alpha 由同槽采样的 `.a` 投影写入 carrier。真实作者 shader 存在另一种写法，不存在中间 vec4：

```glsl
float red   = texSample2D(g_Texture0, computeUV(v_TexCoord.xy,  offset)).r;
float green = texSample2D(g_Texture0, computeUV(v_TexCoord.xy, 0.0)).g;
float blue  = texSample2D(g_Texture0, computeUV(v_TexCoord.xy, -offset)).b;
float alpha = texSample2D(g_Texture0, computeUV(v_TexCoord.xy, 0.0)).a;
gl_FragColor = lerp(texSample2D(g_Texture0, v_TexCoord.xy), vec4(red, green, blue, alpha), mask);
```

这条形态此前落到 `material-variant-envelope-color-contract` 局部回退。修法是在同一 analyzer 内新增 `constructorLocalsFact`，不改 profile、renderer、资源或输出 owner：source proof 要求 terminal 是 `mix/lerp(snapshot, vec4(l0..l3), weight)`、同槽精确五投影（fullVector 一次 + `.r/.g/.b/.a` 各一次）、每个分量名在 `main` 中恰好出现两次（定义与构造器使用各一）、局部定义是 `float` 且 initializer 与同名分量直投影逐字一致、weight 不含分量名与 sample、其他 slot 采样一律作为 typed data。lowering 侧新增 `constructorOutput`，在真实 MSL 上重证同一五投影计数、每个局部定义单次且与同名分量直投影逐字一致、terminal 前的样本位置，然后复用同一 `insertingBoundaries`：只对 color slot 解预乘（含 terminal 内嵌的 snapshot 一次），data mask 保持数据通道，terminal 只预乘一次。

`preservesSnapshotAlpha=false` 仍由既有路由决定 profile，因此命中同一 `source-proven-graph-input-sampled-alpha-reconstructed-rgba-data-filter / generic-only / fallbackOwner=none`；失败仍抛 `Failure.colorTransfer`，不借默认 straight-color boundary 绕过（`hasStrictCompilerOwner` 已覆盖该 owner）。缓存退旧沿用现有杠杆：generic analysis `17→18`、variant `16→17`；prepared frontend 与 program artifact schema 不变，因为本批只改每次准备期在内存中运行的 lowering，不改变已持久化 MSL 或 wire ABI。

同批收紧一处误准入：`mainCallGraphIsReadOnly` 原先无条件跳过 builtin 名，现在只有“未被本 unit 定义”的名字才跳过；`float4`/`floor` 等被作者重定义时进入 helper 纯净性证明。

## 真实形态回归锁

用户本机 variant 缓存中，一条真实 Workshop 效果（材料含 `Chromatic aberration`，取自本机创意工坊样本 `2902406982` 的同源 canonical 源）的 fragment 在 `SceneVariantAnalysis-v10/v11/v12/v16` 中连续记录 `sourceColorTransfer = unresolved`、`sameAlphaReconstructedRGB = null`，即旧 owner 一直拒绝该形态。该 canonical fragment 与真实 `glslang`/`SPIRV-Cross` 产物（`computeUV` 会写自身 `uv` 形参、经调用参数赋值局部、返回前改写 `uv`）现在给出：分析器 `sourceSlot=0`、`auxiliarySlots=[1]`、`preservesSnapshotAlpha=false`、source counts `fullVector/red/green/blue/alpha` 各 1；lowering `straight-alpha`（slot 0）、`mwxGenericUnpremultiply(g_Texture0.sample(` 5 次、terminal 一次 `mwxGenericPremultiply(`。该片段与其 lane/`paramAlias` 漂移反例已固化为 `test_scene_sampled_alpha_rgba_reconstruction` 的回归用例。

## 验证边界

- `script/run_scene_tests.py` 定向 5 modules（`test_scene_sampled_alpha_rgba_reconstruction`、`test_scene_typed_data_rgb_filter`、`test_scene_preserved_alpha_rgb_color_inputs`、`test_scene_persistent_cache_behavior`、`test_scene_authored_shader_frontend`）ALL OK。
- 构造路径：自有用例 + 真实编译器产物 + Metal 像素（五组输入，含 data=0 与 weight=0/0.5/1）；断言 5 次解预乘与 1 次 terminal 预乘，而非只看 `transfer.kind`。
- 反例覆盖源侧与编译产物侧：lane 换序、错槽、错投影、额外 sample、后写、自增、别名逃逸、`inout`、伪 `texSample2D`/`lerp`、注释闭合体、endpoint 漂移。helper 读取自身参数不属于副作用授权，仍接纳。
- 未做：App 内真实样本运行后验（无 selection/截图/GPU 计数），因此不宣告该样本的可见修复；effect612 与“同源未见组合”仍按断点队列复核。
- 未做：Debug build 与完整 inner/milestone 门；本批未改产品可见算法之外的运行时。

证据保留 `.artifacts/verify-constructor-real`（真实 fragment、SPIR-V、MSL、分析器/lowering 探针与源码清单），不在仓库内生成其它缓存或构建产物。
