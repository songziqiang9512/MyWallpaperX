<!-- document-role: historical-evidence -->
# Text layer pointsize setter 与媒体文字

> **历史证据 — 非现役入口**。截止2026-10-16。限定合同归[D4](../roadmap/batch2/script-component-api-design.md#text-layer-pointsize-setter)，API状态归[覆盖表](../capabilities/scenescript-api-coverage.md)，真实余项归[队列](../roadmap/scene-open-breakpoint-queue.md)。最近门、签名构建与真实标题更新达到S4 bounded real title visible；不记artist文字、整样本或面板新能力。

## 共享职责与数值域

thisLayer与lookup handle共用原C layer/value owner。pointsize复用既有double载荷与明确字段位，字号、文字和同owner其他副作用共同进入journal/typed候选；authored staging/baseline、dynamic rollback、跨回调current及partial merge均保raw值。

Swift沿原`.text(.pointSize)`、dynamic definition与settled snapshot交给同一CoreText/source publication，再经既有graph/compositor。setter接受现scalar consumer的有限Double，0/1025及极大有限值保raw；渲染由唯一`SceneTextDescriptor.renderedPointSize`复用原1...1024规则，先夹Double再转Float。constructor原范围不扩，不将项目消费边界称为官方数值边界。

非Number/非有限、非text、stale/value-only、越权/冲突与callback失败沿原owner整包撤回；不新增VM、store、cache、clock或输出owner。已有typed producer优先级及生命周期不旁路。ABI数据DTO/enums/callback typedef归HostTypes，函数声明仍由原header提供；主头1301→984行，新头326行，原owner不变。

## 中性资格与旧基线

公开ITextLayer将pointsize声明为Number且未标readonly。白名单AST投影只给出206/457在mediaPropertiesChanged先写pointsize Number、另写text；两个资源同一341B脚本，未消费作者表达式或公式。原host两张注册表均getter-only，与异常相符，但不冒充动态源码行归因。

原2134765860输入project SHA256 `d7148106c25efbbfc5b58238f3d24305ab6f7f81634298be94be549b20ea152f`，pkg `4198746acad0d1216c0d598624396ba9e9e4ddd114ccd29d1a8a0c5783245e0f`；真实原件只读，实验用隔离副本。

旧签名App使用默认属性与自有64×64封面、title/artist、playbackState=1：媒体入口三项均published，206/457各一次TypeError:no setter for property，completed与动态文字发布均0。两层fallback graph GPU completed/末effect被合成不能代替脚本文字成功；根代理实看房间/光照/时钟与自有色块，未见两段probe文字，右黑块未归因。

该次PID5747，ready40.171491s、总50.820801s、exit0/noTimeout/reaped、inputDrift=[]、GPU排空且ownedGroupGone。只作修前基线，无性能比较。

## 最近门与实际结果

最终产品独立静态GO；真实C owner门PASS 2.817769s，旧particle baseline caller syntax门PASS 0.248311s；Swift pointsize class四方法PASS 59.965974s，clone新方法PASS 57.494950s，输入均无漂移。旧fixture调用新增point_size参数由测试owner同步，未为门改数值合同。

独审在Swift门前发现Bridge仍套create范围且只接text字段，已在原Bridge修为finite raw与text/pointSize组合；未知bit与非text仍拒绝，C未变。Swift首次两FAIL为fixture未发布current，独审核实生产既有runtime-field bootstrap责任后仅改fixture五处，原日志保留，不是产品修法。

唯一Debug build PASS 47.977373s、4280输入稳定，deep/strict签名PASS；executable SHA256 `a42c7d3b985e9fe9ce5836deecbfe3f06d46dfca262359e6612b9ee6b0e78b0a`，debug dylib `62007767de06e3bc0861f8215d13c21714d5db5251715da6ec56b4348fb2903d`。code-health、defense、design与结构最近单门PASS，不替代实际文字输出。

候选213 PID11600，ready42.352872s、总52.343113s、exit0/noTimeout、inputDrift=[]、ownedGroupGone且GPU排空；206/457原no-setter各1次变为0。两owner各收到mediaPropertiesChanged generation1/2/3，首次各有1条callback completed及1条dynamic-text-published，pointSize=8、logicalSize=348×104。后续publication默认只记首次，不能称有三次publication日志。

2s/4s两轮properties换词均accepted，window42583与1surface保持；根代理实际查看ready/after，桌边标题由`MWX Probe Track`变为`MWX Final Track`。两层为同源主要文字/阴影，artist只作为输入，不将两层当作title/artist分别显示。原两条opacityMask slot1启动失败保留，右旧黑块未归因，不认领全部媒体或字体parity。

独立3147346398 PID12240使用同一App：ready4.501366s、总14.528016s、exit0/noTimeout、inputDrift=[]、ownedGroupGone且GPU排空；根代理实看火光/砖墙、时钟日期及music line。仅作未参与修法的真实回归，不证明声学或完整parity，所有时长不计性能收益。

## 边界与证据去留

本片是文字handle setter，不是属性面板新控件；不借此提升alpha/font等其他字段等级。真实系统媒体、完整文字/布局/字体、暂停/多surface、官方像素parity与性能未获验收，右黑块与其他失败仍分列。

资格与基线保留`.artifacts/tmp/213-member-write-projection-20261016/qualified-field.json`及`.artifacts/tmp/213-media-text-qualification-20261016/`；基线独占环境已精确清理，留1after、压缩log与中性/签名/执行收据共8.162MiB，App/原件finalDrift=[]，VM按用户要求保持运行。

本片冻结、测试与运行收据根为`.artifacts/tmp/text-pointsize-setter-20261016/`，安全汇总`candidate-runtime-summary.json`绑定两份execution收据。两运行已停止，精确清掉样本副本、HOME/TMP/cache、raw runtime和生成诊断；大日志与身份收据经gzip回读验证后保留，累计删除388,984,834逻辑B，保3张必要实图及收据低于32MiB，见`cleanup.json`。全局证据预算已满，本根保留最小结果，不扩大预算或删除他批证据；唯一连续DerivedData仍在`.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData`供后继复用，VM保持运行。
