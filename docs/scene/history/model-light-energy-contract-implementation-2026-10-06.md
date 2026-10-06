<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。现役顺序见[断点队列](../roadmap/scene-open-breakpoint-queue.md)太阳系条目；诊断链见[水星诊断](mercury-closeup-brightness-diagnosis-2026-10-06.md)与[重型复验/土星量化](heavy-entry-verify-and-saturn-exposure-2026-10-06.md)。

# 静态模型光照能量合同与过曝修复（2026-10-06）

起点 `a11e5b6b`。用户登录 Windows VM 后，按[官方行为研究工作流](../development/official-client-behavior-research-workflow.md)完成有界黑盒探针战役，落地模型光照合同并修复水星/土星过曝。

## 官方黑盒合同（固定 WE 2.8.0.42 / wallpaper32.exe SHA `daac1ea7…bda07`）

自有夹具：语料球体 MDL（原字节+原路径材质改写为灰 0.5 generic4/metallic 0/roughness 1/无纹理）+ 场景点光（origin (0,0,z)、radius 100、白色）+ 固定相机 (0,0,1)→0/fov50/clearcolor (0.125,0.125,0.25)；768×768 播放窗口 CopyFromScreen，输入哈希前后核验、own 日志行确认模型与相机回读。全部探针为自建输入，未读任何私有实现。

| 探针 | 变量 | 结果 |
|---|---|---|
| I/N/M 系列 | 剧本模型平面 vs `model:` 静态 MDL 层 | **createModelData 剧本几何不接收场景点光**（黑）；静态模型层接收 |
| N 系列 | 无 `general.lightconfig` | 场景光整体无效（黑）；环境光不受门控（ambient 1 → 灰 63.8） |
| P 系列 | lightconfig `{"point":1}`，intensity 1/2/4 | 中心 7×7 精确 **38/76/153**（严格线性 ×2/×4） |
| P0 | 材质无 LIGHTING combo vs LIGHTING:1 | 像素级相同——combo 缺省不排除模型光照 |
| F 系列 | 光距 1/2/4（radius 100） | 中心 153/150/144 = **(1−d/r)² 衰减**（预测 0.9799/0.9403，实测 0.9804/0.9412）；1/d²、1/d 被否证 |
| D 系列 | ldirectional intensity 1/4 | 同样严格 ×4 线性 |

**合同**：静态模型受光面（显示域 sRGB）= albedo × color × intensity × NdotL × (1−d/r)² × **k，k∈[0.30, 0.305]**（由 153/(512×falloff) 反解，8-bit 舍入界内）。方向光复现同一严格线性缩放，按同族共享 k；聚光无独立观测、同族施用（语料 3 样本的 lspot 均为独立锥体绘制，消费未缩放快照值，不受本修复影响）。LIGHTING combo 缺省=受光（我方语义一致）；LIGHTING:0 不受光（我方一致）。**显示域假设成立、线性域假设被否证**——水星诊断的"官方可能线性域"猜想不成立，真实差异是我方缺失 k 因子（约 3.4× 过亮）。

## 实施（本批产品修改）

1. `SceneStaticModelPipeline`：三个静态编码器（directional/point/spot）统一乘 `staticModelLightEnergyScale = 0.30`（新公开常量，注释含测量依据）。Metal ABI/着色器零改动。
2. `SceneDocument+General`：解析 `general.lightconfig` → `LightClassesDescriptor`（缺省=两类全关，非字典 fail-closed）；`SceneRenderDescriptor` 透传。
3. `SceneLightSnapshot.make`：按类门控 directional/point 光层（spot 键名无观测保持不门控）；环境光/天光不受门控。语料影响面=1 样本 `2815826216`（点光、无 lightconfig，官方语义即惰性）。

## 验证

- 门禁推导（4 变更路径）：**19/19 聚焦模块**通过；checkpoint Debug 构建绿；scene-dependencies PASS、scene-defense ratchet 保持、code-health 通过。
- 水星 A/B（同命令同 dylib 形状，修复 dylib `ca60b5de…41bd`）：全图近白 8.1%→**0.0%**；独立视觉判定（实际读图）：修复前盘面 60–70% 白淹、陨石坑不可见、边缘溢光；修复后中性灰盘面、**陨石坑遍布受光面、晨昏线自然连续、无过曝、无过暗/偏色/新问题**。
- 土星 A/B：稳态全图近白 17.5%→**1.9%**；独立视觉判定：**云带纹理与前后环层次完整**（暖奶油/浅棕条带、B/C/A 环层次、辐条纹理），中央球体纯白仅 1.1%（修复前 89%），残留为正常局部高光。
- 门控无回归：`2815826216` 修复后 40s 运行 exit0、干净退出。

## 边界与未覆盖

k 的精确值在 8-bit 舍入内未进一步分离（球体实际半径致 d 有 ±0.5 不确定）；方向光 k 为同族外推（线性已证）；聚光 k 无独立观测；lightconfig 的 spot 键名、`directionalshadow/pointshadow` 子键语义未探；2D 图层光照（lit image materials）的 k 未测故未改动；官方 HDR/Bloom 与本合同正交。JUNO 原完整场景导航验收与布局对照仍开放。官方探针夹具与全部原始截屏保留于 `/private/tmp/mwx-mercury-20261006/official-probe/`（研究卡、deploy/capture 协议、逐帧 JSON+PNG+SHA）。

## 证据与保留

修复前后关键帧与运行身份打包于 `/private/tmp/mwx-mercury-20261006/model-light-energy-fix-20261006.zip`（含官方 P/F/D 系列截屏、水星/土星 A/B 末帧、两次运行 summary 与 manifest，逐文件 SHA）。VM 内 `C:\MWX-MODEL-LIGHTDOMAIN-20261006` 夹具已清理；VM 保持用户登录态运行。真实创意工坊只读未改。
