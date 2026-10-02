<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# RF15：真实模型点光全向阴影（2026-10-03）

> **历史证据 — 非现役入口**。本批设计前置提交 `a2197d71`。产品冻结为 v3，独立产品终审 **ACCEPT RF15 coherent v3**。本机证据根 `/private/tmp/mwx-rf15/`；现役职责由[架构](../../scene/design/runtime-architecture.md)接管，后继只由[兼容路线](../../scene/scene-compatibility-roadmap.md)选择。

## 实际结果与职责

现总四灯准入内所有 cast-on point 可对已经准备的静态及 source-only named 模型投影，覆盖六轴、面边和角部的完整球域。原首方向光优先，其后聚光、点光分别保作者顺序；最多四项记录，失败不压缩原候选槽。只衰减对应灯的 direct，保其它灯、ambient、emission、alpha 和唯一输出。不把普通 image、particle 或 Puppet 虚构为模型 caster。

每个点光使用原 pool 的一张 3072×2048 depth32Float atlas，六面各1024²；每灯逻辑24MiB，四灯96MiB，native 成本另按真实 descriptor 计费。原 mandatory/gather 与主颜色各一次，原 pin/completion 管理已编码资源，六面全部写完才发布一项 typed map；某面失败取消该灯阴影，保原 direct、健康灯和主画面。没有新资源 registry、灯时钟或 compositor，没有提高结构与预算基线。

参考资料提供作者行为、输入及生命周期依据；本项目独立选择六面表示、径向深度及跨面九点消费，不复制参考代码或私有算法。点光开关复用既有严格布尔判据，snapshot 保存当前灯身份与意图。caster 使用真实三角面与实际片元射线交点写径向深度；receiver 每个 tap 独立选面，重定位到最终 nearest texel，再按该射线求接收面深度。不把布局相邻 tile 当空间邻面，不借上一帧图。

## 反例与本批修复

旧 RF14 不可变 App 的四输入位于 `baseline-6gy9prgy`：cast-on/off/no-caster 的接收区均62，light-off为9，灯光贡献53但 on/off 整图完全相同。四次真实完成、drain 与身份通过，只证明一个实际缺影方向。protocol SHA `b2171728060220777231b14fbe8f1b163cd52fdb6b30d6cef954b230d4080e2d`。

v1 的完整遮挡门通过后，部分覆盖的面角门暴露实际数值缺陷：中心片元三个相对分量逐位相同，但快速除法消去使本应为0的面UV变成约−9.84e−9，floor选到了前一格。先排除测试片元一ULP偏移和 tint/opacity 非法并用，再用同一预登记独立九射线期望证明产品反例。v2 仅将点光两个UV换算消费点改用精确除法与融合仿射映射；原143行部分PCF、阈值和bias未放宽。原红、centered红及诊断保留。

v2 的真实缺入口注入又发现：Metal 允许无 fragment 的 depth-only PSO，原可选点光状态仍成功创建并发布错误图。该问题同样影响方向光coverage和聚光轴深度，v3 在原三类PSO各自创建边界确认必要vertex和fragment均存在。分别缺三种fragment只退化对应阴影；缺共享透视vertex时保方向光和主颜色。这是由真实缺函数library证明的失败边界，不新增无产生者兜底。

两类测试输入纠正不计作产品缺陷：动态移动灯的不同位置存在正常直接光空间梯度，最初把跨位置健康ROI当精确相等而失败；新增同状态cast-off对照，用两个清晰direct控制区匹配状态后，健康ROI逐像素相等。named App初稿将父层隐藏，导致子灯按既有父可见性合同也隐藏；只改父可见，保持world、ROI和阈值再执行。所有原红保留，未通过放宽产品阈值取得绿。

## 冻结身份与验证

六产品清单 `implementation/checkpoint-v3-products.json` SHA `a2f6372da3678f7698c0f411e9caa1924dbd2dc219d43fab8b723d3b5d459d19`；相对设计提交的六产品diff SHA `f9a5e3dca867a87d331ac62e32180d03ffd738f60673f5534a139301e28821d6`。最终三测试清单 `test-sources-final-v3.json` SHA `da58ebe332918ccb19abbe03ec575753c1a1406b8b50efa5cf495ddf6ebda974`。两个旧模块仅更新三处真实drawShadow调用参数，原行为断言未弱化。

完整 Debug 构建、code-health、scene-defense、design-gate、文档门通过；build-v3/receipt.json记录六产品前后不变、同一source-v3.app五文件身份、deep strict和两个helper Team requirement。code-health为1056 Swift、240 warnings，不是零警告或发布验收。构建之后产品未变。并行owner随后提交 `8c2429c2`，仅三份census文档，未改变本批六产品/三测试；最终diff仍与冻结产品一致。

最终点光11方法通过164.966s，连同下述18个相邻方法合计29个唯一方法。总索引 `test-final-v3.json` SHA `2f3bbd0802ab827e74c6fa028ca79e106205e2608008669caf2e20700c5d92ca` 的475个显式工件及root索引68项均重新校验一致；`coverage-gap-map-final.md` SHA `0e0891b6f6d1a846f7661a7c03a69f3b169e8da179f101c048099814622149b9`限定每项证据上限。G0包含12种真实三角输入的六面写入/clear及两个extent；G1含238行self/正负间隙、143行独立部分PCF与6行倾斜/非均匀/平移；G2实际解析/世界帧有12检查；G3涵盖10资源输入、部分写入及4种缺入口library各3场景。旧相邻directional7、spot10及spot-plan1已按实际方法通过，不累计同版本聚焦重跑次数。部分编码门的作者大alpha由真实CPU RuntimeModelBuilder进入prepared边界；未实编GPU资源builder，不能称端到端资产加载。资源零光强用例只证明mandatory、slot、pin与配额，不作为辐射证据。

最终实际App分四组，同source-v3：

- 原四输入重放 `original-four-v3-tg55lxok`：阴影恢复，off/no-caster/light-off保控制输出。
- 六方向8输入 `six-axis-app-pd8_yreo`：真实透视相机分别观察±X/±Y/±Z，六向shadow9、healthy62、caster125；另有cast-off与light-off。相机/ROI事先确定，无结果后修订。
- 混灯/动态6输入 `mixed-app-v3-foxmu_vb`：四点光与directional+spot+两point分别on/off，四个ROI各自衰减，健康区和其它通道exact。动态光80→100→80时遮挡位置交换并恢复，与同状态cast-off对照的健康区逐像素相等。协议 SHA `ff4e6c290a1514681d2159e24f44fcfc779c6dc50f0af4aedfbf7e6713ba3b37`；68项显式索引 `root-app-index-v3.json` SHA `de2d3e12ffea12493385ec99f9f5d923a486d98978104cad43e4461eb91ee1ce`。
- named当前纹理1输入 `named-point-v3-trdip5ro`：带实际父变换，receiver cast=false；provider alpha变化使shadow9→62→9，健康区始终62。当前named绑定、主颜色、frame0/1/2、completion及drain成立；协议 SHA `addedb0256bfe587e12cea9881a324265ad65b81eca722ca4965159a4f60dcac`。

以上共19次最终App执行，不将旧v1/v2复验累计进去；各组身份、输入、completion、发布、terminal输出和next-frame检查由其协议/结果限定。纯native接缝数值门不冒充App逐接缝截图。

## 未验边界与移交

没有证明官方图像parity、完整原包收益、性能提升、所有模型格式、全部阴影组合或多方向光。项目固定分辨率、九点过滤和8epsilon尺度裕量是有限质量策略，不是全域数值误差定理；片元depth及每灯六次几何绘制的性能仍需实际优化构建度量。资源证据区分逻辑驻留、native计费和仍被强引用的Metal对象，不将计费归零称物理析构。

独立终审 `product-final-review-v3.md` SHA `a7fb0cee8d563adc17d952dd1dae58fab7e8cc6e108c45f331dba7b8b9edbc15` 接受上述六产品、三测试及最终索引，无剩余阻断finding。[前置设计](rf15-model-point-shadow-design-2026-10-03.md)归档、窄gate删除，稳定合同移交架构；完整D3仍未关闭。下一RF16已用原reader准确归因历史24→22：层479顶点预算超限，层724五材质触发四段准入上限。先追较小的多材质完整资源链及当前可见受害，再按设计修一个实际断点；不抬高顶点预算，不把旧零shadow事件当当前点光实现失败。CPU归因不是实际画面恢复，后继证据单独记录。
