<!-- document-role: stable-contract -->
# Shader metadata 失败合同

<a id="malformed-combo-record"></a>

### 畸形 COMBO 的记录局部失败（2026-10-16 决策）

目标是让合法 shader 不被一条损坏的编辑器 COMBO JSON 记录整段拒绝。当前 parser 已先保留声明、随后记录解析诊断且不生成 Annotation；旧准入却要求另一个无条件合法记录的 outer fields 相同，额外重解析并把不能证明的注释升级为整个 Template 失败。343 的新资格只确认纯注释 COMBO 首门，未读取作者表达或证明其余画面。

依据[来源索引的固定版本记录](../development/source-index.md)，解析失败的 metadata record 可跳过；本片仅开放 parser 已诊断、确切 source line 中无代码且以 COMBO marker 和 JSON payload 开始的记录。由现有 `SceneShaderMalformedMetadataAdmission` 统一模板与预处理器准入，保留原 source、声明和诊断，不生成坏记录的 Annotation、default 或 options，也不修复非法 JSON、要求重复记录或新建 cache。普通帧不参与。inline uniform/sampler、其他 marker、directive/code 混排、无位置诊断和完整性失败仍沿原边界拒绝；未来扩大须另有真实资格。

下游 combo definedness、uniform producer、资源用途、路径/图身份、预算和 backend 仍拥有原验证权。丢失必需 default 不得猜补或借相邻字段回退；失败仍限最小 pass/effect，当前成功不等于整样本完成。旧 outer-field/重复证明及其解析算法在本片退出，不留并行恢复策略；缓存 wire 不变；preparation 语义以 frontend 49、VariantAnalysis v23、DemandAnalysis v6 退出旧 tier，原失败不缓存为成功。

验收覆盖无重复及重命名/等价 source、大小写/CRLF、条件/include、合法邻居保留、坏记录不产生 Annotation；inline sampler/混排/结构安全及下游缺 producer 继续拒绝。原包需证明目标 Program/GPU/末合成与实际画面，另验未参与修法样本，最后独审；任一完整性或错误值猜补反例失败即撤回这片。只在证据支持的记录范围扩能力，不报未经测量的性能收益。

当前状态归[运行证据](../capabilities/runtime-evidence-current.md)，有界结果与未修范围见[实施记录](../history/malformed-combo-record-recovery-2026-10-16.md)；执行顺序只查[现役队列](../roadmap/scene-open-breakpoint-queue.md)。

<a id="unused-client-version-combo"></a>

### 未消费的客户端版本字段（2026-10-16 决策）

目标是避免合法材质因携带未使用的 `VERSION` / `SHADERVERSION` 而在源码准备前被误拒绝。两者始终是 case-sensitive、尚无可信 provider 的客户端版本名；材质整数不能证明官方客户端版本，也不能授权版本分支。当前 environment 初始化直接拒绝全部这类记录，早于真实宏消费，导致没有相关依赖的源码也失去原有材质路径。

沿原 VariantEnvironment 保留 authored resolution 与 variant identity，但不把未验证 client-version 记录发布到 selected definitions、initial macro table 或下游 integer facts。复用现有 Preprocessor 的有效分支读取检查：普通代码、展开后的别名、条件与 active include 真正读取版本名仍局部拒绝；inactive 分支不消费，注释与字符串不属于宏读取。source define/undef、runtime requirement 对版本的声明也不能制造可信 provider。后端语言、平台、纹理格式及 authored environmentDefines 的现有准入不扩大，不新增扫描器、宏算法、材质例外或 renderer。

该变化只退役客户端版本记录的提前拒绝；错误值、冲突、shader/include 身份、预算、sampler、color/render state 和资源生命周期仍由原 owner 验证。frontend50、variant analysis24 与 demand analysis7 的语义版本共同退出旧 cache tier；prepared source 中未使用记录不影响文本，身份仍区分作者输入。验收以原有 source→Program→GPU→唯一合成为终点，包含名称/数值/include 变体、实际消费的邻例与未参与修法样本；若下游仍拒绝，只报告已推进的首断点，不把整层或整样本记完成。没有同条件性能测量就不报性能收益。

<a id="sampler-presence-editor-requirements"></a>

### Sampler presence 与编辑器条件分域（2026-10-17 决策）

目标是避免合法材质因 sampler 的 `require` 缺省键或条件不符，在资源需求发现前失去整个 pass。固定官方客户端 2.8.0.42 的自有六臂普通材质对照中，缺省键要求 0/1、已赋值键与要求冲突及改名均不关闭已绑定纹理的 presence combo；无纹理正反控制、独立必需纹理和持续更新同时成立。该证据区分了编辑器条件与运行 readiness，不给缺省键猜补值，也不证明所有 metadata 或格式行为。

沿现有 VariantResolver 的 Schema origin 区分：普通 sampler presence 与 authored COMBO 的 `require/requireany` 只保留为已解析编辑器关系，运行 presence 只由确切 slot readiness 决定；实际源码 `#if`、include 与活跃 sampler 仍由原预处理器及资源闭包决定。SchemaSeed 的自门控 presence、共享 presence 的可达假设及单个 authored zero default 让位于 readiness 统一消费该分类，退出三个直接用 raw 条件判断运行资格的旧入口，不增解析器、cache、资源或 compositor owner。原 bounded fixed point 继续服务未单独验证的 texture-format 条件；它是项目现有有界策略，不冒充官方合同。

错误 metadata 类型、缺 readiness、显式 presence 冲突、共享 slot 冲突、format provider、实际读取 host/version 宏、资源用途/路径/代际与局部失败边界保持。缓存 wire 不变，frontend51、VariantAnalysis25、DemandAnalysis8 退出旧语义 tier。验收为改名/等价输入、presence 有无与冲突反例、自门控和共享 presence、format 邻例；原包 Program→GPU→唯一合成→下一帧及未参与修法样本实际画面另验，失败时保留局部 previous-current，完整性错误仍拒绝。未取得原包可见收益、控制不成立或存在安全回退即撤回；不据少跑准备或单轮启动时间宣称性能收益。实际结果只归运行证据，选序只归现役队列。
