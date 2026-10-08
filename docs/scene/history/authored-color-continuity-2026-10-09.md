# 作者颜色跨 effect 连续性：第一卡

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。截止2026-10-09；当前合同归[运行架构](../architecture/runtime-architecture.md)，待办归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

本记录归属[颜色设计](../roadmap/batch2/hdr-tonemap-edr-design.md#作者颜色跨-effect-连续性2026-10-08待实施)，不是新的执行队列。起点为 `4eb05bd4`，产品修复提交 `9ecbea35`；真实样本灰色头冠仍未关闭。

## 结果与职责

生成颜色经过普通 effect 后保留 straight RGB，后继修改 alpha 可以显露之前完全透明的颜色。沿原 Program → graph publication → 唯一 compositor 实施；源纹理上传/capture仍为既有PMA，第二卡继续处理，不反推零alpha已丢失的RGB。

- 同一准备合同标记颜色槽与输出表示；既有uint uniform携带八槽实际PMA和signal掩码。generic/bounded的vertex和fragment均只转换真正PMA颜色，原始data/signal不变；最终合成按真实表示关联一次，additive权重独立。
- 严格源码/编译证明保留，generic在原始MSL上统一适配。没有作者uniform的entry/helper复用同一uniform上下文；真实compiler的`always_inline`属性不会再被误认成函数名。请求v25、frontend schema48撤销旧生成代码。
- 同一variant保存确定的nominal输出内容，供同effect后继pass准备；未知保持未知，跨effect保留原并行编译。scalar/RG数据按已准入storage传播，不按`.r/.rg`猜用途。源码已证passthrough的指定槽按同一掩码的实际signal位保留raw输出，真实straight/PMA回退走普通颜色适配；最终表示由实际帧publication决定。
- attachment、平面named、copy/swap传递真实内容；named geometry在原栅格化边界关联为PMA。未迁移的straight direct replay使用既有offscreen→compositor。没有新增纹理副本、采样算法、renderer或资源owner。

## 有界证据

官方Windows 11 / WE 2.8.0.42的自有输入先输出白RGB和alpha 0/.5/1，后一个effect只把alpha改为.5。官方override三卡均159，baseline为64/159/255；本机旧版override为32/160/160。原始合同、输入manifest及排除的无效实验见[既有证据入口](../capabilities/runtime-evidence-current.md#e-2026-10-08-transparent-color-continuity)。不消费参考项目的私有实现。

最终签名Debug构建源哈希在构建前后相同：App `1bb7c7a2a87d3996ac85a4040c70cd0fd0d6c2e2520d01eac047846a32c73f1c`，dylib `0d5f48e82ad72f89f292134c33bbe8da010a559d047aa0e82de055ba6e00d5bd`。隔离cache/HOME运行相同自有输入，override **160/160/160**、baseline **64/160/255**；5×5 ROI逐通道在预置±2以内。override三层六effect均首帧/下一帧GPU completed，终端被唯一compositor消费，rejectedNodes=0；不是“未执行effect所以看起来正确”。身份和ROI在 `/private/tmp/mwx-color-continuity-20261008/{build-final.json,verified-fixture-report.json}`。

定向GPU覆盖非白RGB、alpha0/.5/1、straight→PMA局部回退且无variant重编译，单通道颜色读取，默认背景，vertex采样、data/signal隔离，scalar/RG四种storage的真实producer→consumer，图层opacity、normal/additive、named/clipping及原数值回归。离线请求门覆盖signal producer/preserving/composite/underlay与非法角色/输出拒绝。完整旧Graph大门既有30项失败仍属原队列；未以定向通过宣称全门通过。

## 原包与退出边界

3807668787在实施中曾因Gaussian helper拒绝而出现“灰边消失”的假阳性；之后又因signal输入误套ordinary边界导致首帧超时。两者均作为失败反例修正，不能计为视觉收益。修后原包GodRays 802五个material节点全部执行，灰边仍可见；**U19①保持开放**，不能归咎于“特效未运行”或继续关effect、修改gain补偿。源链第二卡和后续同输入合成对照须继续辨明其根因。音频条已闭合的证据沿原队列，不以本片重开。

本片不证明原图零alpha RGB、named geometry隐藏颜色、完整GodRays官方数值、物理EDR、243样本兼容或性能改善。Python预存classifier仍比产品Swift窄，部分无expected-transfer的alpha override等请求另记验证工具边界；本片只同步新的boundary与严格角色合同。


## 收尾

最终同一App原包复验：3807668787的GodRays五节点与终端消费成功，灰冠仍在；3747190633青色频谱和3807151772黄色频谱仍可见。三者使用受控频谱输入，不能替代真实声源、完整交互与整样本正确率。最终Graph定向6/6通过，涵盖跨两个effect的signal传递、局部失败回退和不重编译；compiler边界30项离线合同、真实Metal动态/vertex对照及篡改反例通过。此前覆盖的compositor、named publication、clipping和默认背景回归保留。签名Debug构建、结构/依赖/防御/设计/文档门通过。

独立只读审查未留可行动问题；审查50文件product/compiler manifest为`e1ded3f40ad108c12b2d2f4f3648acfd52964754a21f629aad5e6a2fec7d1946`，与构建43个产品文件逐个匹配。审查没有执行测试，运行结论来自上述回执。

最终截图、日志、请求、ROI、构建与审查身份保留于`/private/tmp/mwx-color-continuity-20261008`；正式promote因现有证据缓存超总预算拒绝，prune没有可自动到期项，未扩预算或删除未知材料。已清本批停止使用的样本副本、HOME/cache和重复运行产物447399000 bytes；清理回执同目录。连续开发仅保留既有构建缓存`/private/tmp/mwx-scene-next-build/cache/14d60a183f08e048bc3d072d`，供源链第二卡使用。
