# 无根效果背景组合的局部边界与终端透明度

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**

> 历史证据，截止2026-10-22。仅证明本批输入与产品身份的限定结果；当前能力与后继范围见[能力台账](../capabilities/coverage-ledger.md)和[D1](../roadmap/batch2/composition-render-target-design.md)，不决定实施顺序。

<a id="composition-background-bounds-20261022"></a>
## 2026-10-22 无根效果背景组的局部边界与终端alpha

原378五父宽512、子宽1032、省略copybackground=true，仅保顺序导致切片盖过邻栏。原SourceRoute将无authored根效果的正交非passthrough普通组纳入既有localSource；原pool预留/pin、首次写入按实际enclosing raster映射采背景、子效果与唯一终端输出复用。原无offscreen直绘漏用finalCompositeAlpha同时补齐，普通nil调用不变；任意隐藏根效果仍留原背景viewport路径。

官方2.8.42自有双子板两帧各7独立正控/4角25/25，无效果省略背景组X/Y外点蓝、内点RGB合格；B/C各6 ROI相同不证明全部passthrough。非线性F组不支持朴素G/P解释，377/370子树效果继续开放。r2单参数构造编译失败的STOP保留，不改门槛救ROI；旧10-21失格OFF不升级。

签名优化Debug的最终App SHA`799596d21777e7ad53ea7f73b174702daca120201529fc9e6cc1895a7f4a9289`，6个产品owner差分。5最近模块通过；5 App像素案例通过：缺省局部组、true+改名/π2旋转、旧true/false带效果、子隐藏后背景恢复。半透明重叠、非均匀背景、两轴越界和健康前后层均达预设门。首轮omitted输入/11 ROI与最终版完全相同且5独立正控通过，保真实红例；两个旧旋转/错误Y夹具不合格，未计验收。

同原包/3024×1964 cover、中心pointer、静音、20s/30FPS，378五次组capture成功、接缝与四黑线对齐；独立347网格/人物/文字与花片保持，两例原effect/GPU/终端及正常stop/drain完成。不同动作时相不作逐像素golden。最终两例benchmark PASS只作链路证据，整样本仍unreviewed。原签名失败native-candidate的helperSignatureInvalid与降级FAIL完整保留：本机构建时间戳服务失败后，测试包补全原Team ID的主App/三个helper签名，无产品安全降级；所有最终运行均使用完整签名包。

必要原图、输入/App身份、独审、正反与失格尝试归`.artifacts/scene-evidence/runs/composition-background-bounds-20261022/`（ZIP 29,475,357B、SHA`a591ea78dbb4b117087419760618bbbb9b158740a79ab2850b4f0f7da9de5484`），普通14天/单包32MiB/总5GiB；原始官方编译缓存仅记hash、不复制。官方主客户端/虚拟机保留，本轮预览及三独占测试目录已清。没有整样本官方parity、HDR/嵌套/全变换/全属性或性能收益结论，未改全样本历史运行分母。
