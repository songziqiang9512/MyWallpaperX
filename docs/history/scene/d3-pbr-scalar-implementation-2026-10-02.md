<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# D3 PBR 标量直射材质实施记录（2026-10-02）

> **历史证据 — 非现役入口**。目标合同由[D3设计](../../scene/design/2d-lighting-material-design.md)拥有，后继由[实施路线](../../scene/scene-compatibility-roadmap.md)及[RF10工作卡](../../scene/design/reference-evidence-implementation-cards.md#rf10-pbr-direct)选择。此记录只覆盖金属度/粗糙度标量与默认值，不代表slot2贴图、环境反射或完整PBR已完成。

## 输入依据与真实反例

基线为 `1548aad4f7625519a1e8e08ded66ec1091e69bba`。经独立审查的[PBR中性交接](d3-pbr-input-neutral-contract-2026-10-02.md)确认builtin genericimage2/4的字段/default、Lighting的直射开关及map空时使用slider。研究者与实施者分离；实施上下文未消费私有shader、算法表达或原始研究输出。具体shading是本项目独立实现，可对照公共[微表面模型说明](https://google.github.io/filament/main/filament.html#materialsystem/specularbrdf)，不是官方数学或像素parity。

本机证据根 `/private/tmp/mwx-rf10-pbr/`。`implementation/baseline-scalar-prerun.json` 在运行前冻结旧App、输入与runner；runner SHA-256为 `516d00c20ed77ca83f254739e9f66b72f9022a8a45b8c78c39e1671697036020`。旧App的genericimage2粗糙度0.5/1、genericimage4金属度0/1四次实际运行，ready/after ROI全部为21，健康绿色邻层3721像素，均完成。预定粗糙度差值门失败，测试1 FAIL（60.238s）；金属度差值同为0，但第二断言未执行，不能记成两个已执行失败。

## 实施职责与途中修复

有效单pass builtin及LIGHTING=1在准备期消费metallic/roughness与各tier默认值；未提供slot2仍有标量响应。instance逐键覆盖并保留缺省继承，有限越界局部clamp，非法值回该分量tier默认。legacy隐式shader保留原diffuse准入；Reflection不成为直射的额外开关。尚无slot2解码消费，不提前添加无消费者的资源需求。

同一lit source使用已有normal、world、灯光与同帧camera；普通帧不重新解析材质。正交view复用既有投影约定，透视使用现camera eye。独立微表面响应保留premultiplied覆盖和HDR：仅反射率取值有界，输出在完整coverage/tint之后约束至RGBA16F有限域，不能先截断裸高光或clamp至1。plain/effects沿原graph与唯一terminal compositor，不建立新资源、时钟或输出owner。

独立产品审查v1发现启动用户属性的真实断链：原resolver写入wrapper.value但保留user，profile误判未解析；非法object/number user反而被接受。真实resolver→loader→profile反例1 FAIL（10.953s），修后首轮1 PASS（9.052s）。修复在原SceneUserPropertyResolution发布精确startupValuePaths：只来源于成功写入，或合法无条件引用缺值而保留作者fallback；后一种不增加resolvedBindingCount。Format消费该正向路径凭据，不以值变化推断成功，保留authoredRaw；material catalog未经过resolver的wrapper、非法user、脚本/Timeline仍局部默认。7项真实启动profile及3种未解析material输入随最终107项邻接门通过。

同时复核并更正[前批normal记录](d3-authored-normal-input-implementation-2026-10-02.md#rf10-后继复核更正2026-10-02)中的instance fixture错字段：旧运行不能证明instance端到端。此次PBR标量使用实际objects[].instance及可区分值重验；normal用例虽已改为实际instance字段，但覆盖前后引用同一albedo，仍不能证明可区分的纹理替换；后续专门补跑确实发现旧漏接，见下文。不覆盖旧证据。

## 冻结与验证

产品v2为12个现有owner，`implementation/product-freeze-v2/manifest.json` SHA `9f3c0367b0fc232e8689e795cad86dedb953e22c2c2e89ccdfbca07f0b12284c`。源码/测试冻结 `implementation/final-source-v2/manifest.json` SHA `22a53e30638633575ffded6945ae8fc956ff0bc78780ba99c48733038583169d`，共2790个文件，其中29个owned（12产品、17测试）与2761个其余依赖；2773是包含12个owned产品的产品树口径，不能另相加。终审者已实核产品copy/live一致并关闭用户属性发现；最终App及整批裁决另绑定本机final-batch manifest与独立报告。

- 独立审查者在读取实施oracle前冻结14个高精度输入；随后使用自身Decimal计算交叉核31个GPU输入，half舍入目标31/31相同，实际GPU不超过1 half ULP。`cross-review/review.md`保留两套独立计算身份；这是数值交叉验证，不替代实际App。
- 最终GPU门包含31项标量、12项既有world/灯光/normal及19项normal格式与6项独立UV/sampler组合。既有lit组合最大误差约0.0006748，normal格式约0.00007934，6项UV/sampler不超过0.0001641214；原0.002容差未放宽。HDR超范围、覆盖后截断、零opacity/tint、极端有限因素、无效view/重合光源及减半effect均有实际GPU消费。
- startup/profile/真实property与8个Format邻接模块107 PASS（99.848s）。既有graph helper误启用新增材质导致旧diffuse断言失败，恢复legacy输入material:nil后通过，原断言不改。direct-draw独立编译漏带前批typed normal依赖，补实际源集合后4 PASS（10.43s）。中间oracle括号及测试误调用parser owner等失败保留在原日志，不列成产品反例。

### 实际App输出

Debug构建、严格签名以及code-health（0 error，238 warning）、scene-defense（0 dead、18 canonical helper、3 swallow pattern）和12个精确产品路径design-gate通过。冻结 `implementation/source-v2.app`，主执行文件SHA `c635a9fa805b2b4f7609b883f0b45a539d6eee299187bb9892ee1baf97291d4d`，debug dylib SHA `dbb4f86398c3f4b5576f33a83d864d542e3c862b2fb7fc5b7e913a0b7a047f1a`；构建后完整源码/测试冻结SHA一致，审查者实核全部2790个文件无漂移，App运行中未编辑已加载测试模块。

已完成的标量plain正控制如下，ready/after一致且健康邻层保留；这些是自写作者输入与项目算法的实际结果，不是官方对照。

| 作者输入 | 旧App ROI | 新App ROI |
|---|---:|---:|
| genericimage2，metallic=1，roughness=0.5 | 21 | 83 |
| genericimage2，metallic=1，roughness=1 | 21 | 5 |
| genericimage4，metallic=0，roughness=1 | 21 | 20 |
| genericimage4，metallic=1，roughness=1 | 21 | 5 |

同一roughness对照经过自写减半effect输出42/3，独立运行前期望41.472/2.592，容差±2未改。root目检两张最终窗口截图，前者高光渐变清楚，后者接近黑色但保留层轮廓，两者绿色邻层完整。两个tier默认输出52/22；真实instance zero/非法分量局部fallback输出20。相机两次静态eye对照通过。完整单次runner `app-v2.log` 为18 PASS（569.414s），包括PBR 6方法/16场景和normal 12方法/21场景；每场景记录App/输入身份、实际完成、drained及ready/after输出。启动用户属性.8与合法missing fallback.8、normal动画下一帧、父层变换、固有尺寸、格式与局部缺图/坏图全部通过。上述37场景计数仍包含一次覆盖前后同图的normal instance运行，不能单凭它声称纹理覆盖已视觉区分；专门区分实验结果见下文，未计入上述单次通过结果。

初轮文档角色/治理25 PASS（2.139s）、链接门1 PASS（30.418s）；补入F2边界后最终合并26 PASS（29.684s）。没有修改并行结构基线或三份受保护权威文档。

### 补强测试发现的普通实例底图漏接

完整v2运行结束后，test-only v3将instance slot0改为另一张自写灰64图片，slot1以null继承BC5 +X。运行前冻结独立目标21.37979±2；若未覆盖底图则36.48007，若法线丢失则37.19426，足以区分。`app-v3-instance.log` 为1 FAIL（15.392s），实际ROI36.55、中心37，健康邻层保留。实际preview日志明确加载原albedo.png；独立复核确认它属于基线已有普通instance静态slot0漏接，不是新增PBR数值错误。

Format虽保留instance.textureSlots，Layer尚未投影普通slot0；SceneTexturePathResolver(for:layer)只从imagePath/model/material第一pass选源，准备与安装都复用此结果。normal profile另行消费slot1，故产生原灰128与正确BC5方向的输出。这个发现推翻的是旧instance纹理覆盖的证据，不撤销其他scalar/default或normal结果。

按职责将其作为紧接的base source选择修复：补现D3的layer-local投影与共享resolver合同、同model层隔离及原失败边界，再修实际owner；不能在provider compiler增建资产分派。当前scalar提交仅纳入v2冻结测试，v3失败用例与现场保留给下一批，工作树不覆盖。下一批完成前，普通instance静态slot0覆盖明确未闭合。

## 验证上限与后继

256×256、每command32次draw、4灯的三轮暖态GPU探索显示新增材质计算成本，同时存在明显时钟爬升噪声；它不能证明整App帧时间无退化，也不是性能优化闭合。未做全corpus、发布或官方逐像素验收。静态不同camera eye的两次App启动只证明视点响应，不能冒称播放中camera动画、暂停重试或resize全组合通过。

slot2组件presence已取得中性证据，但物理存储通道及map与scalar组合仍需补证；有三个真实Lighting+slot2材料只声明emissive组件，不能读取不存在的metal/rough通道覆盖合法slider。后继先关闭上述真实instance底图反例，同时继续固定参考合同与官方自写单组件实验，随后独立实现明确的贴图输入；不因缺少私有公式跳过能力。环境反射和有合法caster/depth输入的阴影分别接续。窄设计登记继续覆盖RF10贴图后继，不因标量完成提前退役。

## 独立终审与提交边界

独立终审ACCEPT本标量职责，报告为 `/private/tmp/mwx-rf10-pbr/product-review.md`，初次整批绑定 `final-batch-v1/manifest.json` SHA `92eeba2d14db5970a2c8996eb29f8a3f082b3302200430ef099106d84cba76f2`。审查者核40个index路径/字节、37次App执行身份/完成/邻层以及2561个App文件哈希；仅本记录收尾文字更新后再绑定final-batch-v2，不改变产品、测试或App。

实施汇总 `implementation/verification-summary.json` SHA `65273f777572ad3a404945d10da6797f25620b0e367dad8845d620c747d09c66` 按方法去重为17个选定模块、131项非App PASS；不是把重跑次数相加，也不称所有历史run全绿。完整单次App18 PASS与后来F2 1 FAIL维持分别登记。普通instance底图覆盖是已复现但本片未修的下一职责，工作树保留强反例；scalar提交中该单个测试文件严格使用冻结v2，其余owned按终审身份提交。

实际App/测试进程均已退出。冻结App、源码身份、红绿日志及PNG保留供审查；共享DerivedData未清理，少量本片可重建GPU编译缓存按精确清单登记，未删除证据或归属不明产物。不推送、不新建分支；长期Scene Goal继续active，先修普通实例实际源，再推进slot2输入。
