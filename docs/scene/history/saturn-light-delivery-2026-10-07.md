<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。断点定位见[L1 复测与土星对比](l1-heavy-retest-2026-10-07.md)；官方对照截图为用户提供（只读引用）。

# 土星静态模型灯光送达修复（destroy 导出准入，2026-10-07）

起点 `a13ae170`。承接[L1 复测](l1-heavy-retest-2026-10-07.md)钉死的断点：土星层 443 'main'（54KB VSOP87 模拟脚本）的 Bool 可见性 owner 构造被 `invalidSource` 拒收——脚本导出 `destroy`（官方生命周期回调），而 Bool 可见性准入一概拒绝带 destroy 的脚本 → 模拟永不运行 → `shared.sun_pos*` 无发布 → 灯 origin/angles 脚本求值 NaN → 两灯逐帧 `badReturn("non-finite vector output")` 拒入（17,256 行）→ 行星零受光黑剪影。

## 修复（1 产品文件）

`SceneScriptValueRuntime.swift` Bool owner 准入：`!handlesDestroy` → `allowsStatefulLayerSideEffects || !handlesDestroy`（仅 init/update lane；event-only lane 维持原状）。依据：`destroy()` 是 L3 bounded 官方生命周期回调（API 覆盖表），teardown 的 exactly-once destroy 派发机制全 owner 通用（S4 生命周期连续性已证：`owners=N destroyCallbacks=N quiescent=N failures=0`）；stateful owner 带完整 mutation journal 与 quiescence 门，destroy 在 teardown 派发、失败 fail-soft（threw 计数）、journal 随 teardown 丢弃。value-only lane 保持拒绝（无 teardown 生命周期归属）。

## 验证

- 单元：`test_scene_script_boolean_visibility` 16 测试 OK——含新合同断言：stateful+update+destroy 的可见性 owner 获准（definitions=1）且 `destroyProgram.teardown` 恰好派发一次 destroy（invoked=true、quiescent=true、failed=false）；value-only lane 拒绝与主 program teardown 零误派发保持。
- 实机（重建签名 App，75s 调试探针同 L1 口径）：`non-finite vector output` **17,256 → 0**；层 443 `source=authored`（构造失败回退）→ **`source=sceneScript value=true`**（模拟 owner 运行）；稳态帧土星盘面从纯黑剪影变为**受光暖棕+云带+明暗界线**（盘面 ROI mean 0→13.7、带纹 std 28.3、峰值 255），异常蓝灰放射背景消失，文字正常。
  - 口径注记：17,256 为修复前 probe 运行计数（该日志路径被修复后重跑覆盖，工件不再可复核）；幸存同族证据=产品入口 `run-3589454154/app.log` 的 28,520 行同型 badReturn（含 daemon stderr 双写）。ROI 为会话内定义（盘面矩形裁剪），lit-only 口径下能量差约 1.4×；量级方向不受口径影响。
- 同族：放宽覆盖全部 stateful 层字段 owner（场景级）；灯位脚本驱动样本当前证实的为土星，其余样本按需经 census 复查。

## 与官方截图的残余差异（登记，下一层归因）

盘面受光后与官方截图仍有两处量化差异：①明暗界线镜像——官方左亮右暗，我方右亮左暗；②能量偏低——盘面 ROI mean 13.7 vs 官方 60.2（~4.4×），光环近黑 vs 官方 60.8。方向光精确响应曲线族（已登记开放）只能解释 6–25%，不能解释 4.4×；下一归因层=灯 origin/angles 的**值约定**（`0.0005*shared.sun_pos*` 的坐标符号/单位与 typed lightAngles 逐帧值的追踪），需逐帧灯光值探针。

## 同日后续批：度→弧转换 + visible:false 真因修复（当前 HEAD）

**逐帧灯光值探针**（DEBUG 环境门控 `MWX_SCENE_DEBUG_LIGHT_TRACE`，SceneLightSnapshot 节流日志）拿到实际值，两段归因：

1. **typed lightAngles 单位=度**：ldirectional angles 脚本 `deg=-atan2(z,x)*180/PI; value.y=deg-180` 带作者度数方位表（x=-1,z=0→0°…），度数值被 directional() 按弧度直读 → 方向错 57.3× 因子。修：`SceneDynamicLayerValues.lightAngles` 的 typed 分支度→弧转换（authored JSON 角度的弧度合同不动——61 夹具仅覆盖 authored 路径；脚本边界官方按度换算，作者注释表即官方校准）。实机：帧均值 2.55→5.24、盘面带纹增强（方向值生效）。
2. **真因=可见性过滤丢灯**：trace 显示快照只有 directional、point 整帧缺失——`lpoint` 作者 `visible:false`（L1 复测已录）被 `visibleLayerIDs` 门控整灯跳过，而 **origin 脚本本身正常发布 `(-11.04, 0.003, …)`（太阳在 -X，正是官方左亮侧）**。修：`SceneLightSnapshot.make` 灯光层不再按可见集过滤（灯光对象无网格，`visible` 只隐藏编辑表示；官方数据 visible:false 且场景被点亮即官方行为），无用的 `visibleLayerIDs` 参数随删。实机：**双灯入快照**（point 433 position=(-11.64,0.003,-2.71) r=100 i=6.0 + directional 259），盘面亮侧翻到 -X（左），暗侧能量与官方完全一致（34.9 vs 35.7），环点亮（下左带 mean 17.7/max 108）。

## 当前与官方的剩余差距（下一层归因登记）

受光侧能量 0.44×（我方盘面左 37.2 vs 官方 84.5；暗侧 34.9 vs 35.7 完全一致 ⇒ 差异纯在直接光照能量）+ 光环偏暗（17.7 vs 88.3）。候选=逐灯能量分解（双灯叠加口径、衰减形状、响应曲线在真实 E 处的取值）——已登记的响应曲线开放族的延伸，需逐灯值探针带 albedo/NdotL 分解。

## 门禁

三产品文件（ValueRuntime 度→弧 / LightSnapshot 可见过滤+trace+参数 / SceneDrawing 调用点）推导 50 模块套件 **ALL OK**（含连带偿清 `test_scene_text_width_property` 的旧式裸 import 在并行 runner 下的收集失败——改 `script.tests.` 前缀）。

**推导盲区与探针迁移**：登记路由不含"直接编译产品文件的 harness 探针"——`test_scene_point_model_shadow` 与 `test_scene_static_model_pipeline` 直接编译 `SceneLightSnapshot.make`，两条钉旧合同（visibleLayerIDs 门控丢弃灯）的探针随本批迁移为新合同钉定：authored `visible:false` 的灯仍入快照（point_model_shadow 新增 hidden-author 场景反例）与脚本隐藏灯保留在四槽预算（static_model_pipeline bounded 集从 [17,15,12]+溢出1 改为 point[17,15]+spot[16]+溢出3）。独立全语料扫描：216 场景中 visible:false 灯光仅土星 433 一例，行为变更半径=已证实样本。后续 harness 类模块的门禁推导需补"编译该产品文件的测试"通道。

## 产物

`/private/tmp/mwx-l1-retest-20261007/saturn/`（修复后日志+14 张快照）保留至 2026-10-21；对比图 `/tmp/saturn-side-by-side.png`、`/tmp/saturn-disk-crops.png`（会话临时）。
