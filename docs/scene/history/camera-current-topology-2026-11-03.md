# Scene 当前相机拓扑交接后验

> **历史证据 — 非现役入口**

<!-- document-role: historical-evidence -->

> 2026-11-03 固定批。目标归[设计](../roadmap/engine-refactor-program.md#sprite与当前拓扑消费者)，实际接线归事实地图，后续问题归唯一队列。

<a id="current-camera-topology"></a>
## 当前成员、顺序与同阶段 world frames

原 factory 不再从 base descriptor 选候选后套当前 world frame；同一次调用只收 descriptor、layersByID 和 worldFrames 三份同阶段投影。候选选择仍由原 FrameWorldProjection owner 负责，保持逆 renderOrder、父显隐、默认2D与通用相机回退。没有新增世界状态缓存、相机 owner、普通帧诊断或按样本分支。

前置 VM 输入取已提交拓扑；最终模拟、粒子发射和Puppet骨骼取最终投影；paused/held 取原冻结阶段。不能把这些不同阶段的 world frames 合并成一个全局“最新”。10产品文件增119/删83，增长用于明确相位输入及共用原选择器；7测试路径随真实API更新。

## 固定验证

| 项目 | 结果与边界 |
|---|---|
| 产品10文件身份 | ordered path/NUL/SHA/newline aggregate `9c07460c34098737e188ead5b8cc38d0e96659ddf518c5a5786348eee955c5fe`；本机camera-final-source-v4.json保17路径前后SHA |
| 原签名App | `a993632220c3b7628fe21ff0b0872e9771411a87e11df4406d91d1f6cdc81a47` |
| 新签名App | `98539ede73e5ab7aa14babd2e9805f28b085643492755feae22404f7a6a7d6a2`；联合含M3准备/设备/资源值改动，arm64 Debug -O、Team H9QWU9XN8R严格验签 |
| factory同输入旧/新 | 旧真实factory经仅旧签名适配后，在删除、排序、父隐藏和活winner缺FOV的两改名变体共8断言失败；新factory门通过，不以缺API/编译失败当旧行为反例 |
| 真App拓扑正反 | 两个固定深度模型，删除B后应选A、把A排序至后应选A、全移除应选general；原App delete错误落general、sort仍选B，新App三臂固定ROI全部正确 |
| 真App原角度邻例 | seed/rotated两臂原角度脚本、模型字节、独立投影与RGB阈值不变，全部通过；五次运行都有实际完成帧、正常退出和GPU排空 |
| typed与相邻门 | Default2D 18例、native factory、cursor surface、particle camera均通过；Puppet bone origin 3例、pose publication 4例通过 |
| 原始证据 | 本机 .artifacts/scene-architecture-continuation-20261102/camera-*；旧、新App各三拓扑预登记、输入hash/像素JSON/截图/日志保留 |

## 首失败与纠正

native夹具先把裸字符串交给sortLayer，真实API只接受图层handle，导致脚本异常。改用已有getLayer返回值后，三臂、RGB阈值、异常和排空断言全部保留；第一次不合格输入和失败日志保留，不认领为旧行为基线。

Default2D首次编译缺真实SCENE root remap，后续旧夹具又把跨owner顺序写误认为冲突；补实际路径并核顺序覆盖结果，另用真实越界origin使坏peer失败，保持健康peer和C getter断言。没有恢复已退仲裁、放宽值域或改变产品来迎合测试。

本批证明当前拓扑进入实际相机投影；不证明官方完整相机兼容、物理多屏、显示器恢复、整体性能或其他组件全部退休。
