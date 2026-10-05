<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# 终端材质光栅与太阳系连续轨道（2026-10-06）

> **历史证据 — 非现役入口**。当前合同见[运行架构](../architecture/runtime-architecture.md)和[终端材质设计](terminal-material-raster-design-2026-10-06.md)，后继见[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

首断点：程序化细线先在小工作纹理上光栅化，再放大合成，导致真实太阳系轨道断成散点。提高全部输入纹理尺寸会改变作者采样语义并增加内存，因此分开输入纹理尺寸与最终显示光栅。

## 实现与受益边界

原生透视 solid、普通颜色混合、无图输出消费者及外部依赖、单 stage/单 material node、所有已编译变体使用 typed targetPixels 时，由同一个 finalized Program 准备终端放置矩阵。原始输入纹理与 resolution uniform 不变；唯一 MainPass 按作者顺序绘制并独立确认 Program 消费，不伪称消费离屏结果。两种输出格式预热，普通帧不重新解析、编译或建图。opaque/premultiplied 接受，straight/data 拒绝；停用或不满足范围沿原纹理出口。

现阶段仍执行原有小图 pass，保留状态、历史与 completion owner；不宣称已消除这份光栅成本或改善帧率。未来 destination-aware 计划能等价保持这些职责后退役重复小图 draw，见设计。受益为同类可准入的3D程序化细线/图形，不按样本或 shader 名分派，也不外推多阶段、FBO、geometry 或全部 alpha 行为。

## 证据与验证

官方自有探针：同一投影大小下，作者10/20输入分别报告10/20；64条纹实测62次过渡，否定先按10像素着色再放大。E1152选定微分格读数1235×1235与投影1235.236一致；E768混合格无效，不记为831。它们只证明外部行为，不证明官方采用 replay。89项冻结包经独立只读核验，VM已挂起；未消费私有实现或库存shader源码。

真实 App 最终候选：原包仅关闭开场，在3024×1964画面中红/蓝/黄轨道连续；标题栏NDC(0.8,0.06)→(0.6,0.08)拖动后，信息面板移动并保留、媒体面板不随动。exit0、gpuDrained=true；dylib SHA256 `0de78ced0e767fd74cc26b50ce79e88093227ccf9452945d816bc2b5c1cb2387`。画面仍有面板布局问题，整景未验收；太阳系专项约62%为工程估计，不是自动测得的完整正确率。

Debug build通过；真实Metal验证同Program保留10×10源、最终128像素内64条纹达到至少120次过渡且保留外部背景，覆盖停用、错误command buffer、reset/stale及零scale；copy/history实际像素回归通过；真实Bridge/Coordinator的独立消费、重复/陈旧ticket、opaque/premultiplied边界通过。独立审查发现的opaque拒绝与无逆矩阵消费者时零scale误拒已修正并复核。

完整graph门的 `unselectedPotentialDoesNotRevokeSystemOnlyProgram` 仍失败：隔离提取修改前 HEAD `b9d95faf85a831575b6b03ab87d0be0ea8872b34` 的281项输入后，在实际GPU复现同一失败，capability非nil而依赖为external-primary；不计本批通过。结构门仍有既有 shape-derived-analyzer-fleet 66/65，两者不放宽预算或改断言。新MainPass writer增长已通过归还encoder创建给原owner消除。

限量证据位于 `/private/tmp/mwx-solar-orbits-20261006/runtime-evidence.zip`，官方自有探针一并纳入该包，成功证据保留至2026-10-20；本地证据缓存总量已达预算，晋升工具拒绝新增，此唯一包暂留原位，不扩大预算或清理未知证据；既有graph失败的最小复现已单独晋升并保护。最终包保留身份、复验输入/脚本、关键日志和前后原图；本轮App、HOME、样本副本及重复输出在提交后移除，沿用单份构建与shader缓存。
