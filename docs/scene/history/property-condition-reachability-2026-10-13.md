<!-- document-role: historical-evidence -->

# Scene 面板条件依赖与准备阶段复用

> **历史证据 — 非现役入口**。截止2026-10-13；现役合同归[属性定义与面板](../capabilities/runtime-input-property-coverage.md#op-user-overview)，下一项归[属性卡](../roadmap/properties-panel-card.md)、[性能卡](../roadmap/performance-convergence-card.md)和[队列](../roadmap/scene-open-breakpoint-queue.md)。不关闭整样本、整个专项或长期Goal。

## 问题与设计

真实293的`clock1_format/clock2_format`已有consumer，但条件依赖的`sds`被面板过滤；304的格式及其他详细设置也依赖未显示的普通开关。首错在原Scene context的定义投影，不是新增Script parser或缺少格式consumer。

实施前已在属性卡落库设计，完成后从工作卡退出：作者catalog与现binding/provider需求→原ScenePropertyContext一次准备→当前effective values→原控件、存储和typed更新。原Web lexer/parser独占语法、identifier与失败回退；条件tokens作为不可变metadata存同context，当前值仍逐次求值。由真实可编辑consumer出发，闭合控件、相邻说明、所属Group及option条件引用的已定义普通控件，visited使循环有界，保作者顺序及隐藏值。未引用定义、未知类型与未证资源入口不增加运行权。材质编译结果共用target集合，支持判定不重复编译；UI依赖不改变engine能力、全cohort验证或重建出口。

验收包括实际controller可达、格式到桌面文字、关闭重开/reset和独立样本；改名、等价条件、literal/case、非法语法、未定义/未知类型、resource、option/group/cycle反例；至少三轮同输入成本对照。坏/不支持条件仍fail-open且不推导依赖，不凭tokens命中补控件。设计批准不代执行验收。

## 实现与边界

同一parser先做不执行比较的语法校验，再发布已验证identifier引用；正常求值继续该parser。数字文本统一调用原Web属性模型，`Int(exactly:)`保可表示整数，其他数值走原Double文本，`.value`比较及`.text`投影均避免越界转换崩溃。面板body和option显隐复用原context中准备的program及现值输入，未增加AST、通知、解析器或renderer owner。

实际CPU context中293的102个engine-actionable key保持不变，editor定义102→104；304的159个engine-actionable key保持不变，editor定义162→181。新增可达定义包含详细设置与媒体开关，数量只是投影范围，不能代表实际画面或所有属性支持。SceneTexture依赖本身不证明资源consumer；hidden Combo标签仍读完整catalog，隐藏不删值；group按原线性边界、相邻说明保留，未知/不支持类型不补入。

## 可比CPU测量

基线为`8dfbbe013fb06c8f02706688a12cd3f59f5452c8`，最终候选复用相同真实CPU source-facts/parser/compiler和GPU/无关命令leaf；Swift `-O`，同机、同默认值，串行交替三轮，无App/GPU运行或构建竞争。source facts先生成，准备计时不包含解包/全量解析；后续求值使用相同旧可达定义的83/134条条件，完整truth计数逐轮相等。故这里只证明这两条CPU链路，不是面板总延迟、App CPU占用、内存、温度、GPU或能耗。

| 输入 | context准备100次CPU毫秒：基线→修后中位数 | 同条件求值3000次CPU毫秒：基线→修后中位数 | 求值修后/基线 |
|---|---|---|---|
| 2932157836 | 57.975→94.618 | 2078.507→103.205 | 0.0496534 |
| 3042492564 | 192.040→252.505 | 3509.315→173.100 | 0.0493259 |

提前校验及依赖闭合让一次context准备增加约0.366/0.605ms；同条件后续求值稳定下降约95%。完整三轮原始值、truth、fixture及binary identity归本批proof的`measurements.json/measure.py`。不能据此说面板打开已快95%，也不外推全部作者条件。

## 验证及实际输出

现有21个相关模块初跑只有一条历史法线fixture失败：它要求对齐BC1/2/3强制RGBA展开，与已收尾native压缩路径相反。退役该格式断言后仍用作者RGB565端点的独立normal oracle验证GPU，19种格式通过，最大误差0.000157014。其余20模块初跑通过；最终共享数字文本修改后，受影响Web与Scene面板/typed consumer的59项测试通过。结构、代码健康、defense、设计及残留门通过；未执行依赖专用integration环境的子类不计实机通过。

最终Debug `-O`签名包SHA256为`97e04b71a4e4cd1cd7d7e6c66bd307f882a9557f3f42656cad700dbe42262a64`，4270个冻结构建输入无漂移；App/daemon PID 25920/25932。293在window25860从`19:02`变为`19:04:43`，该record只有一次startup；切换213后window26054显示`19:11:12`。停止/退出后41/31 owner全部quiescent，teardown failures/timers/jobs/mutations/dynamicLayers均0；它不否认生命周期中曾发生异常。完整身份及实机后验见本批proof与[当前证据入口](../capabilities/runtime-evidence-current.md#e-property-condition-reachability)。普通AppKit→client→daemon→desktop验证：详细设置打开后格式控件可达，`HH:mm→HH:mm:ss`进入真实桌面文字；关闭重开保持值，reset恢复默认。打开时仍有准备等待，未量化或关闭。独立2134765860未用于修法/CPU基线，实际房间、灯光和时钟有输出；中间候选在有媒体的运行中观察到右侧黑块及206/457的`no setter for property`；最终候选在不同媒体状态下无该异常、右侧是灰色占位矩形。输入条件不同，未把这两项记作修复，保留唯一失败截图/日志；不记整样本健康或新增能力。293的272 cursor/timer取消异常亦单独留队列，不以面板修复关闭。

独立审查接受最终源码、共享数值边界和更新后的BC oracle，只证明静态审查；不替代上述运行和成本证据。HDR/SDR、多surface、全库、完整媒体来源/交互与长期切换未覆盖。

## 产物与后继

限量proof在`.artifacts/tmp/property-condition-reachability-20261013/proof`，保最终截图、身份、完整成本与关键日志；临时HOME、native二进制、重试输出、旧候选和重复样本清理。当前签名候选及一份隔离workshop可用于下一轮直接对照，唯一连续构建缓存仍为`.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData`，不增加缓存额度。UI工具退出后自动重启的无隔离参数进程按精确PID终止并排除证据。

下一批先量打开面板时source facts与同步准备的重复成本；完整callback失败与编辑重建仍保全cohort追最早owner。GPU高级混合/HDR history、首帧准备范围、内存/资源回落及长期切换继续原卡，不因本批测试、提交或局部CPU收益记完成。
