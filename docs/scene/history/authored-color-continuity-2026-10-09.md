# 作者颜色跨 effect 连续性：生成颜色与静态源

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。截止2026-10-09；当前合同归[运行架构](../architecture/runtime-architecture.md)，待办归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

本记录前半保存第一卡当时状态；静态源后继见文末，不将历史失败误作当前待办。

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


## 静态源上传与采集后继

第二卡起点 `494544ce`，产品修复提交 `7d54723d`。普通静态图片、单图静态Puppet沿既有`straightAlbedo`上传与Candidate采样合同进入原graph；不再提前清掉alpha为零texel的RGB。BC原生格式保留原Candidate及mapped UV，不额外复制或裁图。普通直采在原compositor关联一次；unlit全quad源采集保留straight，tint影响RGB、opacity/vertex/clip coverage影响alpha，PreparedCommand发布实际存储。自定义source Program复用原普通颜色边界。文字、动态媒体、动画、lit和命名几何的真实PMA生产者不伪称具有已丢失的隐藏颜色。

独立审查发现并修正同一次迁移中的命名模型接线：准备/发布确认原先使用PMA-only裸纹理入口，改为原typed resource身份读取；模型消费者从同一publication取得实际颜色表示，沿已有`isPremultiplied`标志进入原shader。opaque输入经过opacity调制后发布真实PMA；data/signal不作为模型颜色。未新增资源注册表、纹理副本或第二合成出口。

真实3807668787人物层25的BC3资源存储3584×2816、作者映射3528×2815，原字节中7,353,175个alpha0 texel里7,353,174个带RGB；相邻有coverage的透明texel也保留颜色。原GodRays后继提高alpha后，这些颜色会重新可见。新App原包头冠外沿由灰黑恢复亮色；GodRays802五material节点和人物末端都进入GPU/最终消费，输入extent3528×2815，未关闭effect、修改gain或加样本分支。原包SHA256 `55b4a24e6cddd46d1d45308ad383cb736a9d38c569ea3b18cd0f1661108ad90a`，原媒体未改。

初次可见运行App `dfd372b84985eaa283514e6c10fa2f1484a9527c8f4a067305fff2bdf3c72ec8`、dylib `35299121525ef37633b6307e243c17be723805cc782a44543dc52ccdc44e6ab2`；命名模型审查修正后的签名Debug构建App `d3e12db3deeb13f9cf663980ad0bb60a2b291fe929ab1697dca2b1fdf608fae2`、dylib `7ee2af44b54743484ca40d56338d5712ce19d85f36bb0da2dcce7d74e3a36ccf`，构建前后源码哈希相同。最终同一构建原包后验保持亮色头冠；GodRays五节点与终端消费成功且无拒绝，正常停止并排空GPU。3747190633青色及3807151772黄色频谱同样保持可见，均用受控频谱，不证明外部声源。

像素门覆盖PNG透明RGB/线性边缘、decoded与8192×2052原生BC3的映射/填充/mip、静态Puppet复用同一Candidate、真PMA动画及R8非法映射拒绝；108项capture覆盖颜色表示、opacity/tint/coverage，36项真实Graph覆盖capture→alpha override→normal/additive终端且无表示变化重编译。测试只证明这些输入；旧巨型Python harness仍是存量结构债，新源上传合同置于185行独立fixture，复用一次编译与已有读回，不复制运行链。

官方自有source试验输入34文件manifest `a4286efb2a816277a83b27f887fbd9f464dc148b9b86dd536cccf0f8c55cdfd3`，WE2.8.0.42源卡全部为黄黑棋盘格，opaque/半透明/零alpha准入control失败，仅灰背景正确，立即停止，没有执行override或据此宣称parity。相同自有输入本机也在场景准备失败，不将进程exit0当运行成功。此实验不能裁决source细节；产品修复依据已证effect颜色合同、作者资源与本机共享链像素/真实样本后验。诊断输入和失败证据保留以便后续查准入，未转成样本规则。

边界：U19两项主报告现象有实际可见证据，不代表完整样本交互、真实外部声源、所有HDR/SDR、动态PMA/命名几何隐藏RGB或官方精确像素完成。下一批按现役队列复核U21/U23纹理混合的共同缺口；不以提交数或本片用例数代表全样本进度。

独立审查按18个产品文件冻结；最终manifest `a5b5ee3ef9378374cf0d481e76ce1f57b44cc964d3102852b135d22ba0384cab`，binary diff `98f8eff135431824eef343f528e6dfc9817f426a9d5425c4a387af9e2b6c5e19`，逐文件匹配最终构建。审查无剩余可行动问题，审查本身未运行GPU。新292行命名/光照门沿真实Runtime、Registry、Capture与Metal验证42项命名发布/重复读取/模型实际标志及data/signal拒绝，36项光照/无效PSO局部回退像素全部通过；原publication身份不可同帧换内容的反例保留。两个最终回执在`.artifacts/color-source-named-lit-20261009`，前序Graph/采集回执在`.artifacts/color-source-capture-20261009`。不以数量代替完整样本验收。

产品提交后核对18文件仍逐个匹配构建/独立审查身份。定向源上传GPU及无effect用户纹理消费通过；原CPU fixture补齐BC格式枚举后通过。源capture→alpha override门从旧巨型Graph测试文件移至独立205行入口，方法AST保持原样，沿同一harness复用，旧文件无净新增；产品提交后独立入口实际复跑PASS（79.364秒）。结构、依赖、防御、设计、文档与gate选择器检查通过；未跑完整Scene旧测试套件或全样本长稳。

本批最终日志、截图、输入与失败诊断留在`/private/tmp/mwx-source-color-20261009`。正式证据提取被既有缓存总预算拒绝，prune无可删除登记项，未扩预算、未清未知材料。已删除本批停止使用的临时样本、HOME/cache及重复生成输出256269286 bytes；保留前述唯一连续构建缓存供下一批，不另建第二份。
