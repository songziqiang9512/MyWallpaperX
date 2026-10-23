# 无源四点几何与光束位置

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。截止2026-10-23；当前职责见[终端材质设计](../roadmap/batch2/terminal-material-chain-design.md#authored-direct-draw-domain)，待办见[现役队列](../roadmap/scene-open-breakpoint-queue.md)。声明统计由[光照清单](../capabilities/lighting-sample-inventory.md)独立维护。

<a id="authored-direct-draw-domain-20261023"></a>
## 通用语义与可见结果

旧无源quad把作者四点、原UV和object position都截在固定单位方形。3321237804的光源角点越出该域；world origin/rotation已经正确传递，移动origin或改光强不能修复它。准备期现从EffectPerspectiveUV材质角色和唯一source material绑定四个活跃float2输入，沿同一DynamicSnapshot/数值resolver取值，再由原Program绘制真实凸四边形。两后端共用packed顶点属性，逻辑H×H与实际RT尺寸分离；透明AABB捕获纹理沿原world/parent/parallax和唯一compositor放置，未覆盖区域保留RGBA0。

332默认原包的左上斜入光束明显恢复，修前头部附近的错误局部范围消失；人物、树叶、背景和文字保留。用户官方截屏与原生3024×1964的viewport比例、相位及媒体状态不同，只认定大体位置收益，不认定精确亮度、像素或整样本一致。背景视频首可见帧完整性仍开放，本批没有修改视频链。

无角色、角色歧义或四个活跃输入/顶点资格未证时，typed原因保留既有unit路线，不猜首个、不造点。已选择四点域后，非法数、退化、自交、不可表示extent和陈旧frame/generation仍局部拒绝。普通图片、source-based effect及其他graph节点保持原单位输入。partial opaque attachment由既有storage owner推导PMA；另补齐原nominal owner已知PMA却返回unknown的缺口，signal/boundary优先级不变，未知/data/独立alpha不借此放宽。

## 官方与原生验收

官方客户端可执行文件SHA256 `daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07`，Windows交互用户Session1。自有R3常量/UV/position三行×单位U、越界矩形E、凸四点N板：36个固定覆盖点一致，9个轮廓最大边差≤2px；相对UV/position变化支持画布高度H尺度。官方原图实际为JPEG+ICC；共同RGB偏移、绝对position截距、非仿射插值拓扑未据此资格。R2缺活跃p0的UV/P分支维持单位域，R3只补witness消歧；R1缺stock依赖的失败不作几何证据。另一板保留官方Linear/Radial/Corner三种Color样式，未测Gradient。

同一签名优化Debug App SHA256 `a40fd213ae9ede97baeda25607874ce8827d2f0f1c45d0a1a53255f2e3f644d0`，基于2710b64b1加本批Scene差分，5512个冻结输入无漂移、无构建警告。两份并行UI改动以HEAD文件构建，未混入。R2/R3/styles/332默认8s、after4s、30FPS、静音输入：4/4运行门通过，并亲看终端原图。R2的C行与R3的三行E/N真实扩域，R2未证UV/P六格保unit；三光束样式保留，styles板与修前同尺寸PNG逐像素相同。332 layer292实际v3准备、原effect GPU/终端与下一帧完成；原有4个clipping_mask材质拒绝与旧baseline一致，无新增几何拒绝。

未参与修法的3287715210 layer470（径向）与3566880847 layer415（角模式）均实际v3、帧0/1 Program/GPU/终端消费完成，人物与光束大构成保持；两者四点都在unit内部，只补偏斜/作者变换的真实跨样本覆盖，无before不称收益。1926190458 layer13未误入v3，原GodRays五个material节点实际GPU完成，最终effect8消费；3/3运行门、退出与drain通过。三原图及356官方图独审无明显新gross缺图；另外两者没有官方运行截屏，356也有crop/雪花相位差，均不认完整parity。

两后端最近GPU门7测试/84离屏帧，覆盖改名/等价表达式、单位与越界、透明孔洞和逻辑H独立于RT尺寸；HEAD红例为实际编译后的CPU输入/存储断言失败，未声称跑过旧GPU。几何/变换/动态与frame身份门、既有graph/parallax邻例通过；PMA准备门1测试11断言通过。独立代码审查通过，未以纯静态审查代替真实终端验收。

首候选App `0559a1ef…da0f` 的benchmark虽报3/3，实际三灯和332被新几何门拒绝，已经撤回并保留失败证据。定位到名义PMA缺口后在原owner补正；R2反例同时促使未资格几何保旧unit。修后实际原图和准备日志复验，未通过降低安全门或删除失败收据“转绿”。首次冻结导出遗漏daemon entry的链接失败也只归构建输入，不归产品缺陷。

## 未覆盖边界与产物

不证明71个光照样本均正确、原生灯/模型受光或GodRays全族一致；Gradient、完整mask、任意后续filter、凹域/任意顶点位移、全动态属性、HDR/Release、多屏和长稳未在本批验收。没有CPU/GPU/内存或启动性能收益结论。原视频首帧问题继续按队列推进。

必要原图、输入与App身份、官方实验、正反/变体、构建与独审归本机正式证据库：`.artifacts/scene-evidence/runs/authored-direct-draw-domain-20261023/`（ZIP 28,844,588B，SHA256 `6b8cea6c90e11d32c07d9b31ba6eefdd2de7fbda9d233a895fa344315e9e46b6`）及`authored-direct-draw-domain-holdout-20261023/`（ZIP 31,985,519B，SHA256 `e560dac86c95493c6db66496cee799c8f60eb7ed6eda25eb15e75e3fb128ce7c`）。正式包哈希与ZIP完整性复核；id0仅是归档transport，内部原始报告保留真实/自有板身份。默认14天、单包32MiB、总5GiB。真实样本只读；13个已停止使用的执行副本/实验输入/重复输出目录已清；Windows三处自有stage删除，主客户端PID8640及虚拟机保持运行。连续迭代仅保留`.build-cache/video-extraction-demand-20261021`及其147MiB冻结源码输入`.artifacts/light-compatibility-program-20261023/source`，供下一批视频首帧复用；并行UI App及改动保持。
