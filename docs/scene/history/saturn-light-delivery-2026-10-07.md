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

## 产物

`/private/tmp/mwx-l1-retest-20261007/saturn/`（修复后日志+14 张快照）保留至 2026-10-21；对比图 `/tmp/saturn-side-by-side.png`、`/tmp/saturn-disk-crops.png`（会话临时）。
