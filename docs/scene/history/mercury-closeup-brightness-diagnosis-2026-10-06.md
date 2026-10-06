<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。现役顺序见[断点队列](../roadmap/scene-open-breakpoint-queue.md)太阳系条目；接手快照见[暂停交接](../roadmap/scene-maintainer-handoff-2026-10-06.md)。本页只记录诊断事实，不含产品修改。

# 水星近景过白：隔离诊断（2026-10-06）

起点 `dead0a10`（暂停交接后接手）。用户报告的太阳系 `3662790108` 水星近景大片发白，本批在隔离副本复现并按[暂停交接 S1 卡](../roadmap/scene-maintainer-handoff-2026-10-06.md)的顺序隔离各阶段，未改产品代码。

## 复现与量化

签名 Debug App（dylib SHA `43db5557ba60d83a21cfb6a12f61d4482ed656493e9cd46a4eaaf382b05754a4`，全部嵌套 helper team `H9QWU9XN8R`）。固定输入：原包隔离副本、`newproperty48=false`（无开场动画）、`newproperty57=1`、中文水星标签受控双击（NDC x=0.107/y=0.101）、3024×1964 窗口、每 5 秒周期截图。

三次运行同 dylib、同命令形状（仅测试副本差异），exit 0：

| 运行 | 输入变体 | 终帧全图 mean | 全图近白(>250) | 水星盘面 |
|---|---|---|---|---|
| baseline | 原包 | 55.5 | 12.3% | 约 95% 均匀过白，仅边缘灰；宽径向辉光占画面约 70-75% 高度 |
| bloom-off | general.bloom=false | 27.4 | 7.8% | 盘面 70.2% 近白；上 1/3 亮度 185 处陨石坑可见，中/下 248/254 细节淹没 |
| light-1 | 光强脚本 maxBrightness/defaultBrightness=6→1（intensity input=1 output=1 已核日志） | 8.0 | 0.0% | 无过白；整体偏暗 |

视觉与像素量化由独立子代理实际读图完成（含盘面分带 21.9%/84.8%/98.0% 近白的实测），非日志复述。

## 作者数据与链路事实

- 场景唯一光源：点光对象 3692 `lpoint`，radius=100000（全场景径向衰减≈1），颜色 (1.0, 0.988, 0.980)，`intensity` 为脚本属性，`maxBrightness`/`defaultBrightness` 默认 6（运行日志 input=6 output=6）；聚焦过渡/terminator 曲线不改变输出量级。
- 水星 `p1`（层 1374）为脚本分配材质/LOD 的静态模型；材质 `materials/models/128qt1/DefaultMaterial.json` 单 pass generic4：`color=(0.725,0.698,0.678)`、`brightness=1`、无 emissive 字段（emission 阶段对本问题不适用）。
- 引擎静态模型片元（`SceneStaticModel.metal`）：`litColor = albedo × materialColor × (ambient + Σ intensity × radial² × diffuse)`，在显示域 sRGB 值上直接相乘。强度 6 时受光面约 2.1–4.4（HDR 中间值），写入 rgba16F raw/display。
- 终端链（`SceneMetalRenderer+ClearColor.encodeTerminalColor`）：Bloom(HDR threshold 0.62/strength 0.8) 只作用于 display scratch；显示映射对 [0,1] 恒等、超白按 headroom 截断（EDR）或裁剪（SDR），无 tone 压缩（D2 2026-10-06 阶段 B 裁决）。
- 本机为 EDR 屏：运行日志 `potential=16.0`，extended-linear-sRGB 已启用，headroom 随内容 1.2→2.8+。窗口 PNG 是 SDR 化预览，EDR 侧超 headroom 部分同样裁剪。

## 阶段隔离结论（首断点归因）

1. **Bloom 不是首因**：关闭后盘面仍 70% 近白；Bloom 贡献约一半全图亮度与外圈辉光，是放大器。
2. **点光强度 6 × 显示域相乘是盘面白淹的直接原因**：强度 1 时白区归零（偏暗），强度 6 时受光面 albedo×0.73×6 全部越过 1。emission 不参与。
3. **终端 SDR 裁剪/EDR 截断只决定越过 1 的部分如何丢失层次**；单调有界且 [0,1] 恒等的输出映射不可能恢复全部 >1 区域的对比度，纯输出侧修复在数学上不成立。

## 剩余未知与下一门

官方客户端对静态模型点光强度的应用域（显示域直接相乘 vs 线性域照明后重新编码 vs 其他归一化）没有已固定证据；能力台账明确模型光照"官方固定输入像素对照均未闭合"。线性域假设下 6× 照明的中灰面约编码为 sRGB 1.09、暗陨石坑约 0.72，可解释官方保留细节的观察方向，但这是待证假设不是合同。

**下一门（S1b 前置）**：按[官方行为研究工作流](../development/official-client-behavior-research-workflow.md)发起有界黑盒探针——自有灰阶静态模型 + 白色点光若干强度（1/2/4/6），固定 WE 2.8.0.42 客户端截图测量受光面输出，区分显示域/线性域/其他候选。取得合同后再设计与实施修复；不得在无官方对照下猜测改光照公式或恢复默认压白 shoulder。

## 证据与保留

最终证据包 `/private/tmp/mwx-mercury-20261006/mercury-closeup-brightness-diagnosis-20261006.zip`（23,037,588 bytes，SHA `e08daaddf4b64456ab8d655b89779781c4b9b9ae642e8c3cbff766ec2af644d2`）：三次运行的 command/summary、baseline/bloom-off 终帧原 PNG、staged App 身份、逐文件 manifest（含原包与两个测试副本 pkg 的 SHA）。light-1 终帧 PNG 因包大小限额未入包，其量化行来自同目录保留的运行现场。两个测试副本（`9000000001` bloom-off、`9000000002` light-1）只存在于隔离 Workshop，未触碰真实用户媒体。真实 `~/Movies/MyWallpaperX/创意工坊` 只读未改。
