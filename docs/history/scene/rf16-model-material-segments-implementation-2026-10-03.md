<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# RF16：通用有界多材质模型显示（2026-10-03）

> **历史证据 — 非现役入口**。 设计提交 `fcc0ea1f`；单产品 v1 已获独立终审 **ACCEPT**。证据根 `/private/tmp/mwx-rf16/`；稳定职责见[架构](../../scene/design/runtime-architecture.md)，下一批只由[兼容路线](../../scene/scene-compatibility-roadmap.md)选择。

## 实际改动与结果

原 MDLV0023 reader 将完整合法五段模型以“四段上限”整拒，导致全部材质段不能进入原资源和绘制链。本批只修改原 `SceneMdlStaticModelReader`：以每模型最多64段的明确工程工作预算替代裸4段 profile，并为超额声明增加独立 typed 错误。64不是官方格式最大值。MDLV0016仍单段，累计编码顶点64MiB、索引32MiB、路径/有限值/局部索引/末尾等安全门不变；格式或后段结构失败仍整模型拒绝。工作预算在第一条材质路径及逐段分配之前检查。

多段沿原完整 metadata → SourceFacts/descriptor → Resources.prepare → 原 mesh/material/纹理 → StaticModels 主循环 → Metal/唯一输出消费，保文件 part 顺序。资源或材质失败继续原 part 局部半径，不新增全模型事务、registry、持久缓存、普通帧解析或样本分派。没有新增需要失效的持久拒绝缓存；metadata与资源准备原两次完整验证保持。本次没有优化CPU峰值、扩大命名材质或上调几何预算。

独立自有输入证实5、8、64段均实际准备并逐段绘色；完整App证实五段投影和八段颜色。真实原包模型724的准备从0恢复为5个part，模型成功集合22→23；但它在本批取得的同帧采样中均位于视锥外，**不宣称原包可见或阴影恢复**。

## 反例、验证与证据身份

旧reader实编14输入的冻结反例见 `reader-baseline-v1/`：完整1/4段成功，完整5/7/64段因旧count界限失败。原包CPU首拒见 `reader-stage/result.json`：724为unsupportedMaterialCount(5)，479为vertexBudgetExceeded(150933888)。count5诊断只证明结构可读；实际材质/GPU/输出由后述门补足。中性参考只贡献完整part顺序与draw range职责，不贡献官方段数上限或私有算法。

最终 **19个唯一方法** 全通过，不累计聚焦重跑：

- Reader12方法覆盖51输入：完整4/5/8/64及混合索引宽度，65/巨大声明typed预算拒绝，legacy/零count格式拒绝，坏后段、全metadata、累计字节门。
- 实际builder1方法覆盖5/8/64与坏8段四个磁盘输入；完整材质链接/纹理slot进入descriptor，坏模型不给出成功前缀。全局catalog保留磁盘材料，不以坏模型为由清空。
- 实际原Resources.prepare及main-loop的4个native方法覆盖7行：每段独立geometry/material/texture与两帧ROI，64段完整消费；真实native配额只允许健康peer与前两段，后六段拒绝，释放后新prepare恢复8段，所有行驻留计费恢复基线；坏后段整模型拒绝而peer保留；红后绿的半透明覆盖得到约[64,128,0,255]。纹理transport/部分descriptor使用测试壳，实际图片解码及完整装载链由App另证。
- App2方法、3次执行：five-on/off的五个投影区RGB9对117，五个caster和健康区跨对照逐像素不变；eight的八个颜色均出现，含灰底上的黑段。各次不可变App/输入、实际frame1与next-frame2完成、drain、ready/after整图一致。

产品manifest `product-manifest-v1.json` SHA `d8ecf11e251253262bed4e352c26431cede6b837456406a9be1ce15acb3fe645`；Reader SHA `73d3b631f732b646689c8b5eb5ac1268d7a35941c1552597eaa6d2dfa315327e`。测试最终索引 `test-final-v1.json` SHA `15715328bc150389fd40ff280294a8baf57b3b1e6be9dfabc07295e5a50926e1`，842显式工件经独立复核；壳与证据边界见 `coverage-gap-map-final.md` SHA `e82b5c62b712987bb98ab715658bd84f822fbf297d81dead485e347906378ce1`。两测试源身份和事前App协议在 `test-protocol-final-v1.json`。

完整Debug、code-health、scene-defense、design-gate、文档门与App/helper签名检查通过，`build-v1/receipt.json`证明产品未变；code-health仍有240项既有警告，不是零警告。最终Reader精确路径登记两真实测试模块，避免旧format关键词选中无关模块却漏材质段回归；选择结果见 `selector-specific-result.json`。选择器自身64项测试有9项失败，使用HEAD原registry复跑得到相同失败，涉及既有design-gate期待与旧cursor分组；保留 `selector-check.log`、`selector-head-check.log`、`selector-head-failures.json`，不伪称全库测试绿，不在本批修改这些独立职责的期待。

## 原包同帧观测及诚实上限

原包724五个引用均为普通纹理材质，0与2复用相同材料内容，不称五个不同原资源。静态作者投影不能代表运行时：724父链有脚本变换；旧 runtime-evidence 只含装载输入，没有已提交world。故在隔离源码副本的原terminal readback和原capture请求处加入临时中性观测，经独立审查后编译诊断App；live产品不含这两个hook。原request ID将实际world/camera/visible/alpha/preparedCount与同command buffer completion、PNG导出绑定，没有第二VM、时钟或capture。

旧reader初始两capture在约1.26和3.38秒均无屏内候选。随后按事前60秒、5秒周期协议采样旧、新App，各13个已完成capture，约1.3至57.3秒；输入保持原包、未改资产/变换/脚本。新旧实际frame/time不同，各自只用同CB矩阵，不做假设像素对齐。冻结CPU工具对每part先裁剪投影包络，再独立裁剪实际三角；26个capture、130次part观测均在共同视锥半空间外，三角交集均0。新13条记录均prepared5，旧均0；所有记录effective visible=true、alpha1，但这不等于屏内可见。

最终原包报告 `captured-roi-old-new-report.md` SHA `9aa2c8bec63f960798cc6afbe7bf7de32eb9da45596b446fa35112c34748584e`；combined清单 `captured-roi-old-new-identity.json` SHA `ebe9ede4cd4c94131db8d297a3c9fecd38e2df9e02c0fe155b23147c36abc0b2`。原包两次60秒执行的精确索引各在 `world-baseline-late/index.json` 与 `world-new-late/index.json`，诊断App具有独立字节身份，不能冒充未插桩source-v1 App。

没有从新图片挑ROI；上述结论不覆盖采样间隙、完整播放或离屏模型可能产生的阴影。479仍不在准备集合，原顶点预算未改；不据成功计数直接扩预算。原始首个无插桩观察额外frame2日志断言失败保留；初次诊断runner又误以为Metal状态描述会输出completed，实际为rawValue4，本机SDK确认其值并以原capture导出门重新核对，原FAIL保留、单独sidecar订正，未重跑伪造成功。native首次错误要求坏模型使全局catalog也清空的断言同样保留后纠正，不计产品缺陷。

## 终审与移交

独立产品终审 `product-final-review-v1.md` SHA `0192bf2509174666323c305a3e694f827e7a0071946690d5cdcc63af78995095` 接受单Reader产品、冻结两测试及上述证据，无剩余阻断项。[前置设计](rf16-model-material-segments-design-2026-10-03.md)归档，窄gate删除，稳定预算/分段职责移交架构；受保护能力台账、运行索引和工程档案均未修改，由其owner引用本记录。

本批未证明官方parity、性能提升、全模型格式、全场画面恢复或任意数量材质支持。下一主方向返回RF02公开Rotation/Translation companion：先固定官方可区分行为，再沿现有反射/typed uniform/实际sampler闭合。原479资源成本和724其它时域保留为有实际可见证据时再启动的独立后继，不以缺少私有方法为由永久跳过。
