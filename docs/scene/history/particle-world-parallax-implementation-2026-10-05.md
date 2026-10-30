<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# 静态世界空间粒子的视差准入修复（2026-10-05）

> **历史证据 — 非现役入口**。当前权威：[粒子能力](../capabilities/particle-component-coverage.md)。

基线 `11d6ac049dc282c26cfbcb9a77fe438594014342`。真实3780119725的静态水滴root578/472及Rain440/468/466中的fast child被`dynamicWorldSpaceTransform`拒绝，首断点是静态方向基底的准备计划把camera parallax与系统TRS运动混为一谈。包SHA256 `712e522744c3122c91a6422217bd2707aa565e52496516ca06ed0acd88c56481`，原件只读；两种配置的基线记录复用上一批同产品身份，非新性能基准。

## 行为裁决及最小修复

官方2.8.42／Steam23967692自有二维同场：单次发射、零速度、寿命600，直接与祖先继承depth的已生world粒子，与local对照及同depth色标，在公开camera mouseinfluence 0→1→0时均移动−80/+80像素，彼此位移残差0；depth0参考不动，各阶段双图稳定。独立绿标读取enabled/amount/influence确认参数生效。物理鼠标方法未推动参考标，没有被当作A/B证据。该结果只证明相机视图平移影响已有粒子，不恢复官方内部表示或动态系统TRS语义。

局部修复裁决先写入RF05工作卡：沿原canonical world frame与renderer view translation，删除静态计划的parallax判据及Descriptor重复扫描；不增加出生位置补偿。真正transform script/timeline、父链循环、nil/退化方向矩阵继续保护原边界。root/child Runtime的当前变换采用、冻结、恢复、snapshot rollback与资源/深度/预算准入没有改动。原绘制`T(parallax) × world × Y-flip`只平移存量几何，不改变3×3方向逆矩阵或粒子尺寸。

## 验证及上限

最近真实descriptor门先修旧测试缺失的材质绑定依赖，保留原断言；新输入包含非零视差父子链、同TRS零depth对照和transform script拒绝。旧产品17方法仅新增方法出现3个行为失败，无编译假红。候选descriptor/camera共33项、world runtime的冻结/恢复/回滚等13项通过；含旋转、镜像与非均匀scale下方向和尺寸不受平移影响、已生位置的绘制差恰等于视差平移。

Debug build与严格签名校验通过。最终dylib SHA256 `797646edeff51d606ea83ba33da70f5ea1cb72e0dc63e3f075710a433a3a40e7`。真实两模式均退出0、GPU drained；各44/44可见root加载并完成非空GPU实例，旧为43/44。默认578完成73帧／493实例，替代472完成73帧／418实例；440/466/468的child模板2→3、unsupported降0，实际每层四个绘制batch消费恢复的子粒子。作者隐藏的其他root仍按原值处理，不以可见root加载率宣称完整样本正确率。

本批没有修改视差幅度/缓动公式，没有官方perspective、动态TRS、camera path、物理多屏或性能验收；删除重复准备扫描不等于已经测得整体运行成本下降。结构门仍有两项既有analyzer inventory/classification失败，未抬基线；依赖、代码健康、防御、设计及仓库残留门通过。

产品复用相同自有三行probe，在现有debug pointer输入−0.5→0.5→−0.5时，三类存量粒子与同depth红标同步−302/+302px，depth0青标不动，位移残差0，Y位置与900px粒子面积不变；读回原图3024×1964。原probe仅移除官方clock/API标、将mouseinfluence固定1；两端输入手段与viewport不同，只验同视差共移行为，不宣称绝对像素或mouse曲线一致。无trajectory的先前运行只证明加载，precondition/loose-resource失败不计入通过证据。

下一批首断点为该样本891的`collisionbounds`：当前算子未解析，需先核实省略参数的边界来源及碰撞结果，再接现有粒子执行链。

附加`clockonlyfortheflipoption=true`配置使原先作者隐藏的417特效进入GPU并被合成，三配置联合实际触达37/37 authored effect stages。该附加配置保留`clock=true`，作者两个独立时钟开关同时开启，造成普通与镜像文字叠加；只作特效触达证据，不作完整画面验收。单镜像时钟需同时`clock=false`。纹理ready与text publication分别表示资源及发布链路状态，不能单凭这两者宣称像素正确。

保留包：`.artifacts/scene-evidence/runs/particle-world-parallax-20261005/final/samples/3780119725/runtime_evidence.zip`，SHA256 `38734a88d0b82dd489d016c73835e12361f7733d7a53633c369545cb76df486c`，22488464 bytes、113个payload；含自有官方输入/六图、原生三帧、真实三配置日志/终图、CPU红绿证据和App身份，不含真实媒体包或App。独立审查核对代码、输入身份与原生像素；审查及提交后校验记录单独保留在同名`-commit`包。默认14天保留。

<a id="world-rope-pointer-reference-20261031"></a>
## Root平移Rope与pointer力共用reference（2026-10-31）

基线`7195e3694`。原3141464346的188/332均为General-world、单Screen Rope/subdivision3、固定非均匀scale、relative XY origin Timeline及本地pointer CP1/controlpointattract。旧root平移profile仅Sprite并拒pointer/力，二者以dynamicSystemTransform未准备；只放Rope类型会令live pointer与旧粒子reference坐标不同。设计先落现役粒子合同，完成后窄登记退役，稳定职责见[reference输入](../capabilities/particle-component-coverage.md#root-world-rope-reference-inputs)。

实现沿原W₀、出生offset、Rope geometry/model与pointer投影：准备期typed demand替换Set，仅携可选W₀；普通帧与显式emit消费同reference，无第二map/inverse/clock或输出owner。复用同一Rope plan与forceEnvironment，力沿原消费者资格；pointer出生源、world CP flags2、非零force origin、层级、refraction/native/perspective及变basis/Z仍不扩。移除被basis/Z/w与offset有限门覆盖的current全矩阵finite扫描。七产品净增30行是输入合同的必要传递，不作性能收益。

最近十方法102.542秒全过，含原Runtime与真实Renderer：非均匀basis下旧世界点/新出生/实际连接、force reference、explicit前缀、outside/parallax、改名/等价曲线及反例；48个NaN/±Inf矩阵lane、变Z/变基冻结恢复保持。已有Rope邻例包含离屏GPU提交，已完成；新增world参考门本身是CPU行为门，不能借邻例称world像素通过。普通Debug构建42.06秒、签名通过、输入无漂移；exe SHA256 `d70510e3428cb922a0bbc3eb5d033b06a20954c901f5ab19dc34b10bfc6ea2a5`，dylib `daa2a07b2c6efc1aafc9bdee5e2de238f9c1a405edb52dd8e5d10226af44ee24`。

自有两变体分别30/60FPS等价曲线、改layer/资源名，6秒原生输出可见弯曲world红绳与local蓝绳/绿标。原314最终普通Debug运行51秒、48秒终图，覆盖188移动、332约28.43秒显现及45秒wrap：两个root均加载，188完成1384帧/81356几何实例、332完成1384帧/50720实例，失败帧0；20/48秒原图见细灰轨迹，停止surface1→0且GPU drained。该run的nonempty字段来自启动预览summary，hover/after截图路径未追加settled粒子报告，不能据其空列表否定后段Rope；实际绘制由完成日志与原图取证。旧优化DEBUG的4秒基线只用于同首门拒绝对照，优化档、UI身份与时长不同，不作像素/性能对照。

未参与修法的3742133044原包6秒普通Debug出图/退出通过，保留红月、人物、花/雾与雪的观察；无配对基线，不外推官方等价。独立审查覆盖七产品、测试及原生证据。右下音频环、木偶官方同phase、蒸汽精确形态/位置、全部world组合、HDR/长稳/性能仍未验，314不整例销账。两次matrix缺name是启动前失败，修正后复用同App；不记产品失败或隐藏重试。

本片必要材料归`.artifacts/scene-evidence/runs/particle-world-rope-reference-20261031/metadata/samples/0/runtime_evidence.zip`，20,587,060 bytes/78成员，SHA256 `16db93da8e11fd35469b3698669a3497fa9cc9e47a745c048dbb89606677f803`，默认14天；含原始失败/最终日志、五张原PNG、自有载体、构建/测试/独审身份和两处材料更正，不含真实媒体包、App或DerivedData。
