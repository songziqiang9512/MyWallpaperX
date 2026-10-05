<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# 底部音频隐藏数据源（2026-10-05）

> **历史证据 — 非现役入口**。源尺寸职责见[运行架构§3.4](../architecture/runtime-architecture.md)，当前证据见[运行摘要](../capabilities/runtime-evidence-current.md)。

基线`da46b1dc`。真实3395777145的底部音频371依赖隐藏solid395；四个断点是依赖准入按visible拒绝395、startup-hidden composition未准备live consumer、零scale投影将源变成1×1丢失横向数据、runtime utility planner再次剪掉启动隐藏依赖composition的捕获计划。原件pkg SHA256 `f766d3875637c1847c468664b854eb8770bc13d3c02928287e85f3a08fd44b1c`，project `017d48a481c87d026ee726aa2ef0eaeabe7b927fed6fd008c57d143b11a37494`。

复用原dependency计划、utility route/MaterialProgram准备、source-extent/preflight、资源预算、named publication和唯一compositor。隐藏solid仅有实际依赖需求才执行；合法无父子composition的startup-visible不再决定准备资格，依赖composition仍须实际执行能力及已验证闭包，已准备的捕获计划跨初始隐藏保留，实际visible仍决定显示。源尺寸采用有限非负authored size的每轴向上取整/至少1下限，保留较大投影采样；无作者尺寸沿原投影，显式非法尺寸复用`frame-target-plan-unsupported-target-descriptor`局部fallback，不拒绝整帧。该分配是项目policy，不是官方公式；不新增provider或source-size owner。

官方2.8.42（file2.8.0.42）自有stock-route对照：hidden source的64×1/scale1、64×1/scale0、64×0/scale0、64×4/scale1均被named consumer读出8条UV色带；alpha1与单变量alpha0两轮的同场witness均通过，40个条带中心RGB最大差0、相邻红差至少24。排除该profile因显示scale0塌成单横向样本；不反推官方64×1/FBO、默认高度或算法，fixture只含自有shader/像素，不读私有缓存。

原PCM配置25/39作者effect实际material GPU执行、11直接合成；只去visible guard的候选增至27/39、12直接，但395仍1×1、整排音频条等高。中途live候选三次accepted而371/395零实际graph，促成第四处计划保留修复；accepted本身不计执行。

最终dylib SHA256 `44427da33e38b4557bb4a073ee36e1dff8e10f0570f5a319ace371426043ad32`，Debug build-complete成功；complete-toggle/silence两轮各27/39实际material GPU、12直接compositor、零graph failure且gpuDrained=true。395输入64×1，首次显示371帧64/66 GPU completed并consumed=true；同PID81480/window312258的371帧0false→64true→125false→186true，395帧187恢复执行。371重复显示receipt由sticky去重，无重复日志不作新completion证据；截图0001出现、0003消失、0005/0010恢复并有频率高低，silence0010为十四低点，支持本序列同窗口开关无需重建。

36项focused CPU与4项graph history/fallback门通过，相关capture/visibility门通过；1项utility旧源码形状门与HEAD同样失败，不计新增回归。证据包`.artifacts/scene-evidence/runs/bottom-audio-provider-20261005/final/samples/3395777145/runtime_evidence.zip`，SHA256 `351320b63ce8ab30391872cf46a0b9f13a84fc148b771c63e4cecef5497c9b52`，25,272,265 bytes。

未验系统音频/媒体来源、设置UI操作、物理多屏、其他utility/effect profile、provider生命周期与官方音频逐像素一致性；实际执行不作正确率，样本粗估仍60–70%/低confidence。后继转向同样本其他未触发effect及交互的实际验证，RF05整卡仍开放。
