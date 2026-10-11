<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。终端职责归[运行架构](../architecture/runtime-architecture.md#terminal-material-raster)，剩余任务归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。
# 文字倾斜越界与在途修复收尾（2026-10-12）

## 文字裁切

用户在2877855240发现时间/日期倾斜后右端裁切。此前补g_TextureReductionScale只恢复顶点执行，未闭合文字输出边界。text先在原矩形离屏RT执行变形，末端采已裁graph-final；提高RT像素密度不能扩大内容域。原simple color chain已证明targetPixels，已有terminal material/receipt/MainPass，只有FramePreflight与compositor的solid准入漏接text。

先修订既有设计及登记，再仅修改这两处产品条件：可见、正交、普通blend、单stage文字沿原完整proof进入既有终端绘制；无geometry/provider capture/外部依赖，不扩大FBO/history/高级混合/透视。文字源extent、padding、CoreText、pivot和generation不变；source alpha沿原输入一次消费，不新增裁切或Skew算法。产品diff SHA36ac5c745492fa5b2ff901d1f65313ae3f3d8a8d680e5afabc93c5ad45e5e702，独立只读审查无P1/P2。

原包只读副本、隔离HOME、受控静音、内部Host运行：两个文字层88/97实际terminal-material-replay，frame0/1 GPU completed及compositorConsumed=true；四段solid继续显示。最终App冷启动22.825秒，播放12秒，exit0、surfacesAfter=0、gpuDrained=true，实际截图确认末字右缘完整与秒数更新。专项两目标2/2闭合，不是整样本、桌面产品入口、全属性、长稳或官方全图parity。App主程序SHA0787495248b3f5ae70ca5c853656d95d101c4dbaf32c812769e1b4192b463299、dylib c50ba11b0cd7db842125a578c7d6aba33c3191c737f501357d8d1f16b845b64d；包含下述广播及v20。后续仅cache解释注释修正，不改变构建行为。

GPU终端模块最终5门通过（原3门加2新门、13个实际case）：正负倾斜及平移在原quad之外、主目标之内保留非蓝像素，旧graph纹理路径该点仍为蓝底；identity全图一致；半透明红蓝混合为[128,0,128,255]容差1，能检出重复alpha。296个依赖before/after身份一致，test SHA f28a546a74fa5b032e174d55700219bf38a514fa253ac28a4894331b32f50313。裸Swift载体按既有策略用bounded Program/Metal，不冒充generic App准入；真实text入口由上述原包验证。前四次是测试载体缺compiler bundle、新fragment颜色合同未证、图复合未读取真实straight-alpha表示、字段位置写错；均保留失败，不计通过。最终复用原identity片段与publication.candidate.content→sourceSampling.y合同，没有为测试放宽产品或预期。5项terminal receipt门、Debug构建及职责门通过。

## 主树广播在途收尾

用户确认没有并行任务，接手原三文件冻结5a1a64d33d74a0c414cf1afd613acdbee1bf2fe4d17e328b27c873c6bc65b3ad。复用声明scanner，只允许同函数已声明且类型一致的scalar→vector转换，覆盖逗号声明，普通comma expression不误改；不借其他函数类型。补VariantAnalysis v19→v20，防止旧canonical source跳过归一化。原重复函数体已消失，defense按实际122→121收紧。六路径diff SHA cddb23a5c80e4a58dfebd3c0e7b2633772f10eee6fe4a90cfe4683f5b5c81258，独立复审无P1/P2。

现builtin模块16项（含GLSL→SPIRV-Cross→Metal数值）通过。缓存四tier行为门首次因fixture仍指v17目录在publish失败；改为v20目录并保v19 stale反例后通过，保留损坏/摘要/命中断言。Debug两次构建通过。3662390671原包layer58/effect612由编译失败推进至Program 9fae8712…真实GPU执行；四段effect全部completed，末段compositorConsumed=true。启动约51秒、播放12秒、exit0且GPU排空；背景视频与文字仍显示。此运行静音，不能声称音频响应/全样本正确；3792400801本批未重跑。

## 工作区与后继

本批切回主工作树codex/engine-refactor-program；广播收尾提交5e527a36，文字接线另按职责提交，不推送。旧LDR树73项中59项逐字节等主树，其余为后继修复/文档元数据；Release树6项中5项逐字节等主树，余项已由后继provider data准入覆盖。两旧HEAD无独有提交，无需合回，整树覆盖会倒退。最初归档工具受pinned保护拒绝，未绕过；随后用户已自行删除旧树，git worktree核对只剩主树及既有prunable登记。不能仅凭文件状态断言当时未清理的具体原因。

证据根`.artifacts/tmp/text-terminal-overflow-20261012`保留原生日志/截图、identity、红绿测试与独审。本批原包副本、隔离HOME、生成shader和重复截图已清理约167MiB；只复用`.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData`构建缓存。下一项回到N06 Sound：复用owner事务与唯一Sound registry，区分脚本播放意图和宿主暂停；公开合同及三原包调用收据在sound-control-20261012，尚无产品实现，不记已完成。
