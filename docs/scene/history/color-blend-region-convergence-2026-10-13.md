<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。后续以性能卡和对应现役合同为准。

# 高级混合区域复制收敛（2026-10-13）

后续执行归[性能卡](../roadmap/performance-convergence-card.md)，资源与最终输出职责归[运行合同](../architecture/runtime-architecture.md)。本批修普通四边形高级混合的背景读取范围：现有fragment只读当前像素，以最终MVP的原始NDC顶点得保守AABB，Y-down、向外取整并外扩一像素，再clamp到实际target。复用现projection、main-pass store/load、snapshot和compositor，不新增绘制或资源owner、视觉特判、预算和分辨率策略。

snapshot仍完整尺寸，同坐标复制；每次刷新本quad实际可能读取的背景。custom geometry、无可信投影、裁面/W/nonfinite/空范围保全屏；粒子折射保全屏，因为读取可以偏移。mode5/10不因alpha零跳过。只改复制范围，shader数学、coverage、纹理容量与失败回退保持。

独审发现旧Float clipping在极大有限坐标下可能算小范围，已用同一owner的原始投影AABB修正。旧X界`[32,15,35,13]`修为`[0,15,67,13]`；1e30在该GPU的全屏参考也无覆盖，明确是静态界反例，没有伪称GPU像素失败。相邻大坐标有真实像素覆盖。880次完整目标纹理字节等价覆盖19种模式、SDR/HDR、变换、连续帧/混合和resize，另保容量、在途与失败边界；独审及修订重审接受16路径patch `d90af096e6211e31bc58355877a2b1b7de01c9bfa4bd655375716f3668f92aa6`。

同仪表对照：从77df1a3f冻结源得到全屏参考，仅原snapshot调用传`region:nil`；两App其余产品源及新增HDR/reflection复制计量相同。Debug明确-O，同输入、3024×1964单surface、60fps请求、静音、fresh HOME/engine cache、OS暖、94s/30s warmup，先三份有效基线后再三份优化测量。六轮935owner、零失败domain/帧、GPU排空、AS1有效且呈现回执持续。

| 3662790108实测 | 全屏参考三轮 | 区域复制三轮 | 中位数变化 |
|---|---|---|---|
| 背景捕获逻辑B/帧 | 95,026,176 | 5,297,600 | -94.43% |
| 全部已计量复制逻辑B/帧 | 142,539,264 | 52,810,688 | -62.95% |
| GPU帧p95(ms) | 50.611 / 47.861 / 47.135 | 43.107 / 43.587 / 43.208 | -9.72% |
| 完成FPS | 15.190 / 15.445 / 15.696 | 16.834 / 16.662 / 16.735 | +8.35% |
| 进程kernel峰值MiB | 2052.10 / 2047.27 / 2070.53 | 2058.80 / 2040.44 / 2089.97 | 无稳定下降 |

render/copy pass数量保持38主pass、7depth、53offscreen、3copy；少复制像素并非减少作者内容。字节为实际编码区域的逻辑量，不是物理带宽；总复制包含本批补齐的HDR/reflection，旧仪表漏计不能作收益。ready范围27.16–30.45s到25.49–26.11s，本批不归因为启动准备收益。仍是内部Host可读目标测量，不代普通桌面/Release或全样本性能。

实看参考/优化后的太阳、星空、轨道、标签与HUD；开场推进，没有重现第一屏卡住。独立2932157836启用严格默认执行观察PASS、零failures及868呈现，人物、星星、水纹实际输出；它未参与实现选型或调参。没有据此声称歌曲媒体、全部交互、HDR物理亮度或官方完整parity。

最近门还修正历史测试：BC3用已有GPU sampling readback代替把compressed block当RGBA，保留`[255,130,0,64]`和原偏移数值；named mixed fixture补现役uniform扩展及零text offset carrier，不修改产品算法。完整Debug-O build、最近GPU门及独审闭合。必要文本/最终主样本和heldout截图归本机`.artifacts/tmp/gpu-blend-actual-20261013`，身份与边界反例归`.artifacts/tmp/gpu-blend-region-convergence-20261013`；具体去留按本批cleanup回执。
