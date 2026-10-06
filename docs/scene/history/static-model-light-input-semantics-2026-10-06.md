<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。光照能量合同（k≈0.30）见[模型光照能量合同](model-light-energy-contract-implementation-2026-10-06.md)；现役代码以 `SceneLightSnapshot`/`SceneStaticModel.metal` 为准。

# 静态模型光照输入语义批（官方黑盒 v2，2026-10-06）

起点 `b50ad32e`。承接光照能量合同的开放边界，用 61 个官方黑盒夹具（Parallels WE 2.8.0.42，二进制 SHA 当日由 `…685F…` 变更为 `…6862…` 同版本字节替换，P4/NA 锚点复现证明行为不变）钉死四项输入语义并落地产品代码。

## 官方黑盒结论（全部 own-fixture，逐帧 PNG+输入 SHA 冻结）

1. **光角度值按弧度直读**：`ldirectional` 的 authored 角度数值不经度→弧度换算直接进入旋转。yaw=1（弧度）时受光方向=(cos1, 0, sin1)（标志性验证：球面三点 134/23/153 与该方向逐点吻合，R 侧内点 n·L=0.999→153=P4 满值）；yaw 细扫（1/1.2/1.4/1.5708/1.8/2/2.4/2.6/2.8/3/4/5/6）与 Jacobian（yaw±0.3、roll±0.3、roll 0.6）一致：**yaw→XZ 平面方位（+Z 为正）、roll→仰角（+Y 为正，0.3rad→17.85° 线性）、pitch 对方向无观测效应**；角度恰为零时官方保持默认朝向 (0,0,−1)（背面，D1/D4 全黑复现）。
2. **ambient 为世界法线 y 线性斜坡**：`clamp(0.5 − 0.73·n.y, 0.15, 0.85)`（NA 全图 35k 点拟合 rms≈2.5/255；AROLL 相机横滚证明随世界非视角、AOFF 平移球证明与位置无关；两端钳位在 n.y≈±0.48 生效）。我方原为平坦 ×1.0（赤道 2× 过亮）。
3. **缺省 ambient 为黑**：ambientcolor 字段省略时与显式 0 0 0 同渲染（ADEF 探针）；旧白回退退役。全语料 207 样本凡带模型均 author ambient/skylight，回退移除零影响。
4. **spot 受 lightconfig 门控，键名 `spot`**：无 lightconfig 全黑（SP1）、`{"spot":1}` 点亮（SP2 中心 150=P4×falloff 家族 k）。spot 朝向约定未探（近全向锥测量不可分辨），保持既有 frame 语义。

**方向光响应曲线开放**：官方方向光存在陡 S 响应（G(0.53)≈0.15、G(0.76)≈0.61、G(0.89)≈0.93、G(1)≈1，终止线附近抬肩与 0.15 地板），我方线性 NdotL 在中间调低约 4%（GY90 中心官方 142 vs 我方 137）。未实施猜测曲线，登记开放。2D lit image（IMG1 截顶，k_2D≥1.1 倍于 3D）、spot 朝向、pitch 效应、2D 路径 ambient 同为开放。另两条已钉定事实的固有边界：零角(0,0,−1)默认与微小非零→≈+X 之间的近零不连续（时间线扫过零角会 90° 跳变，近零区间无官方观测）；方向改按原始角度直读后父链旋转不再作用于光方向（原 frame 路径会继承父旋转，父变换对光方向的影响未探）。

## 落地（6 文件）

- `SceneDocument+General.swift`：`LightClassesDescriptor` 增 `spot` 键。
- `SceneLightSnapshot.swift`：spot 门控接入；白 ambient 回退移除（N 系/ADEF 证据）；`directional()` 改从**原始角度值**（authored `anglesXYZ` + 动态 `.angles` typed 通道，脚本驱动的 3589454154 日照保持实时）按官方公式计算——矩阵回取会丢 wrap 后 cos 符号（yaw≈2.0346/90 弧度族实测黑面即该错误），故不经 frame；正交场景按 frame 反射约定把方向镜像过 Y。
- `SceneStaticModel.metal`：ambient 乘斜坡 `clamp(0.5−0.73·n.y, 0.15, 0.85)`；符号经 `ambientColor.w` 传入（正交 −1，作者空间 y）。
- `SceneStaticModelPipeline.swift`：`ambientColor.w` 打包空间符号（ABI 无变化，w 原空置）。
- `SceneDynamicLayerValues.swift`：新增 `lightAngles` typed 读取（有限 vector3 胜 authored）。
- 测试：pipeline 模块 harness 迁移新语义（弧度公式断言、spot 门控反例、缺省 ambient 黑）；shadow 家族 stub 补 `lightClasses`/`anglesXYZ`/`camera` 与 `SceneStaticModelMaterialBindings` 源（多为上午批次遗留红的偿清）；named/spot/point 期望值按斜坡合同迁移（255→128 等）。

## 验证

- 单元：`test_scene_static_model_pipeline`（新公式+门控+缺省黑断言）与 shadow 家族 10 模块全绿。
- 实机 A/B（签名 Debug，相机对象夹具，中心像素对公式精确）：yaw 1→129、1.5708→153、2→139、3→22、90(弧度)→137（官方 142=响应曲线差）、零角黑×2；spot 门控 150=官方精确值、未门控黑=官方 SP1；pt I=4→150（官方 153=k 界内）；amb 省略→37（官方 38）。我方渲染视图对 authored 相机存在水平镜像（夹具级现象，太阳系等真实样本交互已用户验证，不属本批）。
- 预存红（非本批）：`test_scene_frame_rejection_fault`/`test_scene_resolved_material_runtime_bridge` 在 HEAD 因 `SceneCompletedColorSourceIdentity`/`hasTerminalMaterialReplay` 源清单漂移（ce0cd7dd 家族提交未同步 harness）。

## 证据

官方 61 夹具+捕获（含锚点 ANCHP4 复现 153）、我方 33 次运行快照/日志/身份，共 627 文件逐 SHA manifest，打包 `/private/tmp/mwx-light2-20261006/static-light-input-semantics-20261006.zip`（`296498bf…41d9`）。
