<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。现状归[运行证据](../capabilities/runtime-evidence-current.md)，未完成项归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

# 普通画布缺省透视与坐标反算（2026-10-12）

## 通用语义与边界

基线 `c13d2b6d` 的普通正交画布在省略 `perspectiveoverridefov` 时使用固定眼距1000；显式FOV使用原画布拟合。缺省应与显式95保持相同的层透视结果。本片在原 `SceneParticleCameraFrame` 补缺省输入，继续共享原投影、typed frame、GPU、cursor与最终合成。仅同时具有正交宽高的普通画布补此缺省；显式非法数值保留原回退，原生相机、partial canvas、动态origin.z优先与zoom仍走原职责。不可解析原始FOV仍由现有parser归为nil，因此消费缺省；未新增字段区分坏值与省略，不宣称官方coercion一致。不增加样本、路径、hash或源码形状例外。

实际反例还揭示原 `SceneLayerCursorGeometry` 的Float反演残差会拒绝有效投影，影响鼠标命中与required effect projection。camera near=.01/far10000、倾斜有深度的自有卡，旧缺省和旧显式95均可拒绝；half profile有约.0026局部坐标误差。修复在原几何owner以唯一Double求逆及CPU射线/平面计算完成，原五组profile与36格反例的82项policy值均准入，CPU local最大误差约3.90e-7；输出给shader的Float矩阵仍有舍入误差，同探针Float乘clip与归一化NDC的XY最大误差约.01134/.01538，不能以CPU结果宣称GPU effect像素一致；不以改near/far或放宽残差阈值掩盖输入。

## 官方证据与实际收益

自有纯黑盒输入，不消费私有实现。官方2.8.0.42固定身份下，1210×786、720×786、605×393三组普通画布的省略/显式95在预声明ROI均0变化像素。95/50对照有48191像素变化，先证明字段真实生效。此证据不说明独立viewport依赖、任意相机组合或非法值转换行为。

本机证据根 `.artifacts/tmp/camera-default-fov-20261012`：批准中性合同、73项官方输入/截图/命令hash在 `official/` 与 `official-handoff-approval.json`；native输入、App身份、矩阵/像素与退出回执同根。运行结果、独立审查及清理收尾在最终记录中绑定，构建或profile命中不算画面验收。

静态筛选278份可解析输入，在“省略override且显式perspective，带非零Z/X/Y倾斜或动态几何”的有限条件下未选出已证受益的真实层，不能推断不存在运行时受益。2960821850基线实际停在layer92/effect1的 `resourceSnapshotUnresolved` 并首帧超时，属于N04，不能算相机修复或画面通过。3113287126作为未参与实现的真实回归样本；平面输入的保留不等于新增可见收益或整样本官方一致。

后续优先处理N04已复现的资源快照/依赖首断点；文本wrapper完整生命周期、特殊clone和其他相机组合仍按现役队列推进。

## 本批验收

- 最终Debug App构建及严格签名校验通过；40项相机/坐标CPU门与6项实际Metal readback门通过。后者保护既有粒子深度、剔除与纹理方向，不证明Float effect反算的像素精度。
- 10次最终隔离运行均ready、正常退出并GPU drain。三组native省略/95、两组资源/变量改名和等价表达式输入均ROI零差；原显式50/95前后ROI零差。1210×786同尺寸官方对照的8张可见色卡边界差均≤1px；边缘仍有1339个非一致像素，不报全像素parity。旧缺省到新缺省实际改变52975像素，深度卡最大边界移动82px。
- 独立3113287126修前/修后截图均有人物、星球背景和粒子；后验提交117、完成116、呈现116、failed=0，排空退出。作者时钟与动画相位不同，不把截图差当修复增益；未验完整属性交互、系统音源、普通桌面入口和长稳/性能。
- `native-geometry.json`、`implementation-unit-receipt.json`、`inverse-*-probe.json`与`product-build-identity.json`分别绑定实际像素、CPU反例和最终App。冻结差异及独立只读审查单独保存；未将profile命中计作画面结果。
- 结构、依赖、防御、测试断言与文档门通过；工作区残留门仍报告既有218字节`.mimosa`，归属未知原样保留。已停止使用的本批HOME、真实样本副本与重复生成输出按精确清单清理；保留必要截图/日志和一份既有增量DerivedData，不提高证据预算或删除未知资料。
