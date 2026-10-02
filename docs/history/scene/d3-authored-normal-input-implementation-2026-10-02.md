<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# D3 作者 normal 输入实施记录（2026-10-02）

> **历史证据 — 非现役入口**。目标合同由 [D3设计](../../scene/design/2d-lighting-material-design.md)拥有，选序由[兼容路线](../../scene/scene-compatibility-roadmap.md)拥有。本记录区分中性研究、自有行为门和实际 App 输出；最终候选及独立终审以下文为准。

## 目标、依据与修前反例

基线 `ced0d1fffd31b24288913c6a0ce8f2c264d6abf1`。将 builtin genericimage2/4 的作者 slot 1 法线接到现有受光 producer；slot 2 是 PBR，不因路径名误作 normal。输入依据为[经审查中性交接](d3-normal-input-neutral-contract-2026-10-02.md)。研究者未参与本片实施，实施者声明未接收研究原始输出；只有归一化作者绑定、资源用途及每槽 frame 职责进入实现上下文。方向处理是本项目独立策略，不是官方算法或像素一致性声明。

本机证据根为 `/private/tmp/mwx-d3-normal-next/implementation/`。`baseline-cpu/` 编译真实 profile/compiler，在普通 slot 1、误收 slot 2、instance 只改 albedo 后丢失 inherited normal、NORMALMAP=0 四项得到修前反例；小型 harness 的模型替身不算完整解析链证明。

`baseline-app/` 使用 D1 已冻结 App 和自写包：相反 X 方向的两张法线在 ready、after 的中心及 7×7 ROI 均为灰值 100，LIGHTING=0 为 128。受光已经执行，但普通作者法线没有产生区别；每次存在实际 Metal 完成、drained、两帧截图及 3721 个抽样健康绿色邻层像素。不是官方运行结果或原始 Workshop 样本恢复证据。

## 实施职责

- Base profile 在 launch 固定有效 LIGHTING、NORMALMAP 与每槽 instance 继承，并准备 normal 的 typed asset identity。仅有实际 receiver 才向唯一 material asset catalog 贡献 `.normal` 需求，颜色用途保持独立 identity；普通帧不重新解析法线路径。
- 现 loader、FrameProvider、registry 与 slot binding 保留用途、格式、物理尺寸、完整 UV origin/axes、sampler 及发布身份。法线使用自己的 frame，纹理对象相同也消费新 frame metadata，不建立第二个资源表或动画时钟。
- 同一 lit producer 解释 RGB UNORM 的完整方向、RG8 UNORM 与 BC5 RG SNORM 的两通道方向。后者已经有符号，不能再套无符号变换。两通道的独立方向补全、超范围 XY 和 RGB 过滤抵消均有自写反例；没有为中性测试新增浮点法线产品入口。
- 缺失、未支持与非法 normal 保留分开的 typed 原因；拒绝非法 normal 的绑定后仍使用有效 flat-lit payload。实际两个 capture encoder 区分 normal 局部失败和 target 非法，后者保留原拒绝边界。geometry 不支持等整个受光 producer 的失败仍沿既有 unlit fallback。

## 验证记录

### 最终产品与执行身份

最终产品与测试冻结 `implementation/final-source-v2-tests/manifest.json`，SHA-256 `5252e7a110e5168d34815d710099f3c1f6c8f94f619cb747ae94ff0ed7e30a89`：9个产品文件、7个测试文件、4207项依赖，root逐项复核无差异。产品与source-v2构建一致；App为 `implementation/source-v2.app`，执行文件SHA `6832ed48d372e3b6ff9c48693f9fd6097f27da16e914e376aad4bedd7f663ab8`，debug dylib SHA `b7d3f77ea2eb9eaeb26bfcb04ed8760d507097c78f4e1020c310e4eab1054011`。Debug build、严格签名、code-health、scene-defense和精确owned-path design-gate均通过，未扩结构/防御基线。

### 实际通过门与失败归因

- `normal-v5.log` 的4项 focused 门通过（21.270s），包含真实Swift profile、12项既有world/rectangle/normal GPU组合和16项初始格式输入；flat误差0，基础GPU最大oracle误差0.0003271。profile在最终身份另跑2项通过（1.901s）。
- `final-gpu-graph.log` 最终3项通过（87.864s）：扩展到19项实际loader/格式/方向输入，包含BC1/2/3的完整RGB负Z、RG8和实际BC5 signed采样、neutral、RGB过滤抵消、purpose隔离、无效/缺资源flat、真实capture的normal-target alias及非法target拒绝。最大方向oracle误差0.000160948，小于运行前门0.002。
- 同一最终GPU门的6项独立UV/sampler oracle误差最大0.000160441。人工typed候选与真实catalog FrameProvider分别验证非零origin/axes、不同区域、nearest/linear实际采样值；同纹理下一frame及discard/retry仍走现registry。故障注入与自然asset发布分开登记，不能将手工alias构造说成普通catalog自然复现。
- 最终App有效覆盖12个方法、21个场景：原v2运行11 PASS、1个父变换fixture FAIL（300.282s），保留日志；纠正该输入/oracle后完整父变换3例另跑1 PASS（46.057s）。其余通过场景不重写成一次全绿运行。原PNG斜法线保留，plain正/反输出140/0，自写减半effect输出70/0；32、128与128×32固有尺寸均符合方向不变门。LIGHTING=0仍128，NORMALMAP=0/缺图/坏图/slot2均flat-lit约100，健康绿色邻层保持。每次成功场景有App/输入身份、Metal completion、drained和ready/after快照；动画asset的两帧方向实际改变。root目检effect输出。

父变换第一次把90当弧度输入，改为π/2后仍发现旧85 oracle漏掉归一化灯光的Z投影。完整独立计算并经终审者复核，正确中心为scale 126.6825、rotation 60.2507、mirror 0；误差仍±2。两次失败记录保留于 `app-v2.log`、`parent-final.log`，完整计算在 `parent-oracle-correction.json`，最终补跑为 `parent-corrected-final.log`，产品未为错误fixture改动。

相邻图门初跑两处测试失败：独立Swift编译源列表漏带新typed依赖、旧normal fixture使用本片未准入的BGRA8 carrier。已补编译依赖并改用自写RGBA8，保留方向/热点断言；没有为旧测试开放额外产品格式。最终两方法随上述3项门通过。

### App测试文件身份澄清

v2 App进程运行期间，同一Python文件仅GPU方法的格式数量断言16→19曾被写入磁盘，App类没有变化。旧runner逐场景记录的是采集时磁盘testSHA，因此20份原identity有18份为冻结源码 `d42e9d…e2f30`、2份为中间 `012986…e0843`。独立审查者重算两版哈希及精确单行delta，确认App执行代码相同；原identity没有覆盖。`app-v2-provenance-correction.json`保留完整两版、delta、启动命令与时间，加载SHA明确仅为实施者报告，不能冒称由进程仪器独立观测。承接未变化App证据依据是两候选App代码等价；父变换真实输入变化另有最终加载身份与完整补跑。后续runner在setUpClass固定testSHA，运行期不再编辑其加载文件。

独立产品终审ACCEPT，报告为 `/private/tmp/mwx-d3-normal-next/product-review.md`；整批文档/登记与审查身份由 `final-batch/manifest.json` 及同报告的最终绑定保存。稳定职责进入架构§3.4，`scene-authored-normal-input`窄登记随片退役；D3整体设计及PBR/反射/阴影后继继续active。三份受保护权威文档与并行layout排序改动未触碰。

### v1 接线通过后发现的方向错误

v1 的真实 loader/GPU 门区分了 RG8、BC5 的有符号采样与 RGB 完整 Z；App 的 10 个方法、15 次执行也通过了当时断言。但原倾斜 RGB 输入仅从修前的相同灰值 100 变为 102/98，带自写减半 effect 时为 51/49。root 实际查看输出并追问区分度，独立终审确认这是遗漏的真实错误，不能以这些弱断言宣告法线方向正确。

位置 model 包含 unitquad 到图片固有像素尺寸的变换，既有 normal basis 又对完整位置 model 求逆转置；64×64 图片因而把斜法线的平面分量压小。旧 oracle 重复了同一个完整矩阵策略，flat 或纯 X 输入也不能揭示错误。中间日志 `app-v1.log` 为 225.096s，源与测试冻结在 `source-v1/`；这些结果仅保留为接线及反例证据。方向纠正另经设计审查，位置继续保留完整 model，normal 单独使用同帧作者/父层变换与 card 朝向；固有尺寸变化和作者 scale 变化必须分开验证。

`basis-red.log` 随后在同一 v1 App 保留原倾斜 PNG、world 取样点与灯光，仅改变固有尺寸为 32/128，实际执行一项门失败（30.304s）。32 的中心值 105、ROI 104.714，与运行前固定的独立目标 140±2 不符；两次 App 都完成且健康邻层保留。不能将这个反例归因为效果未执行、GPU 未完成或后来重新挑选极端方向。

### 文档门与既有结构清单失败

最终文档角色/治理25项通过（1.622s），相对链接门通过（24.164s），design-gate及diff检查通过。额外完整semantics扩展初跑32项中29 PASS、3 FAIL（177.405s）：一项是旧D2/D3记录指向RF07的旧锚已失效，已在现役卡上保留显式稳定锚，单项复跑通过；另外两方法共同报告既有结构清单差异：shape-derived-analyzer-fleet为66而基线65、额外命中文件为Diagnostics/SceneDebugFrameCapture.swift，legacy-dependency-singular-route为6而基线5。

`semantics-head-comparison.json`使用同一检查器，以HEAD字节替换全部9个变更产品和并行layout文件，仅对纯注释剥离函数作结果缓存，完整重算得到与当前完全相同的三条violation。故这两方法是本批前已有失败；没有提升预算或将foreign排序纳入提交。原32项运行不是全绿，也没有以最终25项文档门代替结构门。对照、最终门日志与窄登记批准存档在 `/private/tmp/mwx-d3-normal-next/`；原完整运行结果保留于本任务工具记录。

## 证据上限与后继

只读 corpus 检索覆盖 207 个包、1195 个 genericimage2/4 pass；找到两包三项已关联 normal 材质，但其 REFLECTION=1，LIGHTING=0 或未声明。它们是作者绑定正例和本片 lighting 关闭反例，不能声称本片恢复了这些原场景的受光。`corpus-normal-candidates.md` 保存精确 package index 与 JSON entry 身份；没有读取私有 shader 或纹理 payload 猜用途。

下一片按这些真实 reflection/PBR 消费者确定作者开关、环境输入及 masks 通道合同，然后在已有 normal、资源、frame 与 lit producer 上独立实现有界反射/材质响应；缺官方数学时用可区分自有输入验证项目算法，不能退回整项等待。阴影另沿合法 caster/depth 输入闭合。不宣称本片完成 PBR、reflection、shadow、额外动态 provider、官方 Y/packing/atlas parity、全 corpus、性能或发布验收。
