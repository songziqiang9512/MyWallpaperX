<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# RF05 named provider 启动准备与显示分离（2026-10-02）

> **历史证据 — 非现役入口**。当前权威：[兼容路线](../roadmap/scene-compatibility-roadmap.md)、[能力台账](../capabilities/coverage-ledger.md)、[运行证据](../capabilities/runtime-evidence-current.md)。后两份并行权威未改；本记录只保存本批冻结事实。

同页历史分节：[未支持组合局部失败后继记录](#rf05-optional-failure)。

## 结果与职责

基线为接管后的主分支；本批三个产品文件：`SceneDesktopWallpaperHost+DeferredBaseImages.swift`、`SceneDependencyRenderPlan+ImageProgramReference.swift`、`SceneDependencyRenderPlan+BindingCompilation.swift`。设计见[启动资源准备合同](../architecture/scene-resource-admission.md)。没有新 registry、capture 或 publication owner。

1. Host 启动 defer 只豁免 static-model named providers，导致属性初值覆盖为隐藏的普通 image source 不加载，消费层显示白色原图。现复用唯一引用分析的普通及 potential optional named provider 集合，保证潜在 source 可准备；未消费隐藏图片仍 defer，terminal user texture 遮蔽不误加载，隐藏 consumer 的潜在来源可保守准备。
2. 已加载的普通图片初值可见时，又被 named composite 两入口拒绝。两入口共用现有 predicate，开放无 effects、无两类 dependencies、无 children、非 Puppet 普通图片，显示隐藏与 source 资格分离。旧 hidden 分支等价；generic 专属依赖约束保留在其调用处。可见 effectful image 仍走 graph-final，顺序、循环、purpose、预算及 generation 不放宽。

## 反例与实际验证

本机证据根 `/private/tmp/mwx-rf05-provider/`；自写 PNG、shader、scene/package，未改真实样本。最终 `manifest-final-v2.json` 固定三个产品、两个测试及20个 App payload 的 SHA256。签名 App 为 `frozen-v2.app`，CDHash `c944b19aa0ce46ea9c40230d404c40054ed573b6`；实际 Debug dylib SHA256 `c851a0f95f64b6d4145708338e6aea92456f054ed134cbbb4b14ec824d8c2e99`，metallib `991cdb9f9e431e782210cfeacb285fbf64d2d6736e13a27c59e7057c0718ffcc`。

- 修前冻结 App 三对照中，常量隐藏来源消费蓝色，无消费者保持黑色且 defer；属性隐藏来源却消费白色，绿色邻层正常。最终同输入 red 单门仍失败，输入 SHA 与修后一致。
- 首轮修后八门六过两败：初始可见→隐藏仍白；未声明用途的 optional RGBA shader 被现役用途准入拒绝。保留原日志，不把后者称为非法作者语法。
- visible 准入 Swift 红例成立；修后 dependency 模块28项通过，含显式/缺省可见、前向 capture、Puppet/children/deps 排除与 effectful 不进 raw。首次相邻 dependency/registry 37项通过（49.933s）；最终改动的 dependency 模块另跑28项。
- 最终同一 v2 App 七门通过（149.808s）加限定 exact-two-candidate rgbmask optional 门通过（20.603s）。七门执行时测试文件的 optional 分支尚未去掉重复 named，其余七门输入和断言未变；执行时源码另存 `integration-seven-run-source.py`，不能声称单次八门同一测试字节。覆盖常量隐藏、属性初值覆盖隐藏、无消费者 defer、隐藏 consumer 保守准备、live 双向、terminal shadow、optional unavailable 后 named fallback。中心蓝色/白色/黑色及绿色邻层按输入判定，provider 显示独立负 ROI；要求实际 named capture/binding、frame completion、terminal ready/after、next-frame 与 gpuDrained 退出。不是仅检查资源已加载。
- 完整 Debug build 与 strict/deep 签名通过；code-health 1047 Swift、0 error、237 review warnings；防御面0 dead/18 canonical/3 swallow保持，design-gate通过。独立终审结论另核同一源码、测试与冻结 App。

## 未关闭边界与下一批

optional 首次改用 rgbmask 后，真实解析产生 `material named → instance named → system userTexture` 三候选；它超出现役 mixed-provider 两候选 profile，并导致 `resourceSnapshotUnresolved` 阻断全场首帧。完整输入及 timeout 保存在 `optional-profile-v2/`。本批第八门仅移除材料层重复 named，保持 instance named + system 的既有合同与蓝色 oracle；没有将原三候选计为通过。

下一批先在现役 prepared/material 准入关闭这个未支持组合的失败半径：局部退化该 effect，保护健康层与终端，不泛吞 identity/snapshot 错误，不为通过扩大 matcher。该可见阻断修复后继续 D1 composition 层级与真实 source。任意 optional shader、三候选兼容、跨屏、性能提升及官方 parity 均未由本批证明。

<a id="rf05-optional-failure"></a>

## 未支持组合局部失败后继记录

下文完整保留该阶段的历史裁决、证据身份和未验证边界；其中状态与后继顺序仅适用于原记录日期。

<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

<a id="rf05-optional-failure--rf05-未支持-optionalnamed-组合的局部失败2026-10-02"></a>
### RF05 未支持 optional/named 组合的局部失败（2026-10-02）

> **历史证据 — 非现役入口**。当前权威：[兼容路线](../roadmap/scene-compatibility-roadmap.md)、[能力台账](../capabilities/coverage-ledger.md)、[运行证据](../capabilities/runtime-evidence-current.md)。后两份并行权威未改；本记录只保存本批冻结事实。

<a id="rf05-optional-failure--结果与职责"></a>
#### 结果与职责

基线 `5f603403`。真实作者解析保留 material named、instance named、system userTexture 三候选，但既有 mixed-provider 只证明两候选；未支持组合仍进入帧准备，optional 不可用时又无 named 依赖 owner，导致全场首帧反复拒绝。

实施前批准的设计（保存在本记录末尾）选择三个现役职责：`SceneResolvedMaterialExecutionCapability+Stages` 在 variant、active demand、invariant 后对活跃且未被 graph 覆盖的未证明组合产生可定位的 launch rejection；`+ProgramFirstStages` 与 `SceneResolvedMaterialGraphExecutor+VisualFailurePassthrough` 复用现有无 history、无 clear 的窄拓扑证明，将安全 effect 留在入口颜色。候选顺序、IR、用途、exact-two profile 均未扩大；不增加 registry、matcher/helper 家族或每帧分析。

<a id="rf05-optional-failure--冻结身份与实际输出"></a>
#### 冻结身份与实际输出

本机证据根 `/private/tmp/mwx-optional-failsoft/`。旧 App 运行新反例门失败（7.785s，`app-red.log`），`phase=launch-failed`/首帧 timeout；同一自写 package 为2641字节，SHA256 `905a211c779383c75961e471d1f5495ab0b5e87263398218cb76af05e7c98274`。修前后所有作者输入 hash 相等。

新 `frozen-v1.app` 的 CDHash 为 `5153e1e1de46bf60b7f814d6a5fc66a7d94e9db4`；实际 Debug dylib SHA256 `2ceafe6e927e3d28555353cccec004623d55b48aeb1b0d1741658a824631d370`、metallib `f9146b9b0990f669db61deb207ab797c170bbc7393948447fbeb621519676542`。三个产品文件在 build-source 与冻结 diff 一致，`payload-v1.json`保存2561文件 hash，strict/deep 签名通过。

两项真实 App 门通过（46.506s）：三候选 consumer 在 ready/after 保留白色入口，中心通道255，绿色邻层175个采样点，蓝色来源不贡献，named capture/binding为0；exact-two 对照仍为蓝色中心并有实际 named capture/binding。每场 frame0/1/2 同 surface GPU completion，publication、terminal consumption、next-frame及退出 drain 有实际事件；三候选 materials=0/rejected=1，不能把白色结果称为 named fallback 已执行。

<a id="rf05-optional-failure--行为门与终审"></a>
#### 行为门与终审

最终 `final-v1/manifest.json` SHA256 为 `e5d32c7653c941493d0f4db389b6b88edc60d1f41b9b09c96f78d580bfbdb05c`，绑定三个产品、两个测试、构建输入及 App payload。独立只读终审重算这些身份及448项 harness dependency；App 2561个 payload 无差异，接受本有界修复。

- 实际作者解析及 stage 行为两门通过（201.253s），13项断言覆盖：三候选局部失败、零 materials/依赖申领、exact-two继续执行、不同 provider/secondary不归一化、两个相邻有效 effect、inactive slot、terminal asset、authoritative graph override，以及 history 与真实 clearFunctions 拒绝。clear 另有可执行正控制。
- 边界门曾失败：graph override 测试只改 graphRole、未随真实 producer 追加 `.graph` 候选，触发模板身份错误；terminal asset 测试缺少匹配 path/purpose 的 ready/data 与 r8 事实。按实际诊断补足输入后强断言通过，未放宽产品 gate。产品三个文件在各轮始终相同；旧失败日志保留，不把早期测试版本冒称最终版本。
- 相邻 finalizer 33门通过（99.722s），既有 graph executor GPU 模块通过（99.902s）；覆盖既有 exact-two system/property envelope、缺失/不完整状态及 copy/swap 拒绝。不是本片全部状态均有独立真实媒体 App 对照。
- Debug build、strict/deep 签名、code-health通过（1047 Swift、0 error、237 review warnings），防御面保持0 dead/18 canonical/3 swallow。设计门通过；其输出“无设计前置命中”来自 checker 跳过 approved 条目，另以 `design-match-audit.json` 确认三条产品路径匹配已批准设计。没有改基线规避。
- `test_document_role_index` 与 `test_scene_governance_contract` 在本批精确暂存快照中25门通过（1.041s）。共享工作区首跑的两项失败来自并行新建的全仓审查文档尚未登记；其后该任务新增的登记与索引行完整留在工作区，未混入本批。产品没有新增普通帧解析、建图或 hash。

<a id="rf05-optional-failure--未验证边界与下一批"></a>
#### 未验证边界与下一批

此片恢复的是合法但未支持输入的安全失败半径，不支持三候选 fallback，不保证任意 optional shader、真实媒体迟到、物理多屏、性能或官方 parity。history/clear及 unsafe command 拓扑仍受原硬门约束。现有两个候选的执行合同由对照保护。

下一能力批是 D1：核官方 composition 外层顺序，再在既有 scope 中闭合普通图片父子层级、实际 group source、透明 clear、extent及 GPU lifetime，撤销可退役的旧捕获分支，不创建第二 compositor。

<a id="rf05-optional-failure--已退役的设计裁决"></a>
#### 已退役的设计裁决

本片已实施、验证并独立接受，一般失败合同由[稳定架构§3.3](../architecture/runtime-architecture.md#33-保留事务安全不扩大视觉失败半径)拥有。按设计门 policy.retirement 删除完成的临时登记；以下保留实施前设计的独有依据，不再作为 active plan。

本设计在实施前 approved，属于[兼容路线](../roadmap/scene-compatibility-roadmap.md) RF05 后继；五判据①②④命中：跨 prepared stage 与执行输出、唯一依赖/失败合同及冻结材质家族。只使用本项目源码与自写输入的行为证据，不扩作者 profile，不读取参考项目实现。

<a id="rf05-optional-failure--目标合同与现状"></a>
##### 目标合同与现状

合法作者输入超出现役 mixed-provider profile 时，只退化已证明可安全跳过的 effect，保留其入口颜色、其他层和相邻有效效果。不能让局部视觉不支持反复阻断全场首帧；identity、cycle、range、history 与 target 生命周期错误继续硬拒绝最小 unsafe unit。

`SceneAuthoredMaterialResolver.swift:105–119,247` 依次保留 material named、instance named、system userTexture 三项 provenance；`SceneResolvedMaterialExecutionCapabilityVariant+ProviderSlots.swift:48–64` 的 exact mixed 合同只接受两候选。`SceneResolvedMaterialExecutionCapability+DependencyOwnership.swift:582–608` 不申领该未证明 named dependency，stage却可继续准入。运行时选到 unavailable system 后，`SceneResolvedMaterialTextureResolver.swift:351–356` 产生 resourceSnapshotUnresolved；`SceneResolvedMaterialGraphExecutor+Preparation.swift:255–261` 缺局部失败证明，整帧反复拒绝。

真实修前输入与签名 App 见[RF05 执行记录](rf05-named-provider-readiness-implementation-2026-10-02.md)的三候选边界；本机 package SHA256 为 `905a211c779383c75961e471d1f5495ab0b5e87263398218cb76af05e7c98274`，日志记录 rendered=0、151次尝试均drop。退出成功不等于呈现成功。路径行号为 `5f603403` 附近定位线索，实施需按冻结代码重核。

<a id="rf05-optional-failure--owner方案与备选"></a>
##### owner、方案与备选

选现役 `SceneResolvedMaterialExecutionCapability+Stages`：先执行真实 variant、active demand、invariant验证，再检查 launchEnvelopeActiveTextureSlots 中没有 authoritative graph override、terminal candidate 为现typed OptionalInput且lower candidate有named的实际slot。复用现 exact mixed proof；未证明时产生可归因到node/slot的专用 launch rejection。全inactive、静态asset/graph终端遮蔽不触发。不修改候选IR、顺序、purpose或选择器，不新增 matcher/helper family。

`+ProgramFirstStages` 的现失败fold只将该专用reason送入既有 `dependencyStageFailureMayPassthrough`，保留no-clear约束；失败stage不安装materials或申领named执行，相邻支持stage沿原ownership/order守恒。`SceneResolvedMaterialGraphExecutor+VisualFailurePassthrough` 消费同reason且复用相同无history窄拓扑，不能加入更宽的ordinary history-capable列表。

备选扩大frame-time吞错会混淆缺资源与identity错误；去重作者候选或放宽exact2会改变支持合同；引入新依赖结果类型会扩多个owner。本片均不选。新增拒绝的产生者是上述真实三候选模板，拒绝范围只能缩小到这个未证明的活跃optional/named责任。

<a id="rf05-optional-failure--fallback纠正门与退役"></a>
##### fallback、纠正门与退役

安全拓扑按现有effect-entry passthrough；clear/history/copy/swap等不满足安全证明时沿既有拒绝，不捏造history或publication。不得把局部白色原图称为三候选named fallback执行成功。

验收：真实作者解析保留三候选及provenance；launch仅该stage退化、零材料/依赖申领；同修前package在签名App出现首帧/next-frame completion、白consumer和绿peer、无timeout及虚假capture；相邻支持effect继续执行；exact2 system/property的ready/absent/pending/unavailable原合同不回退；inactive/terminal-shadow/graph override不误拒绝；不同provider、secondary、错误slot identity及unsafe拓扑不被归一化。Swift行为门、Debug build、code-health、防御/设计门和独立终审均按本片失败半径执行。

稳定材质失败合同接管且上述门通过后归档本设计并删除临时登记；未来扩大mixed profile必须另行设计，不能用本片安全输出当兼容性完成。


<a id="rf05-deferred-intent"></a>
### RF05 资源准备期间连续属性意图（2026-10-04）

基线 `38be3dcefd4c3ecb9dfa1b19ec60a78d14dec158`。首断点是 Session 用最后一笔请求覆盖整个 pending：A 开启后再开启 B，或 bulk A/B 开启后只取消 A，都会丢掉仍有效的独立意图。当前修复在同一 Session 合并待提交键、同键最新值含删除胜出，并向原资源 owner 请求完整所需 layer 集合；无重叠且不需资源的修改仍立即提交。稳定边界归[启动合同](../architecture/scene-launch-responsiveness-contract.md)。apply 与 promotion 收在同一 LiveConsumers extension，未增加属性 owner、graph、clock 或输出路径。

实际画面收益：隐藏启动后连续开启两层，两张图都出现；取消其中一层仍显示另一层；取消同键不会迟到显示，无效后续修改不会清除已接受修改。自有输入的健康绿色邻层保持不变。Debug runner 只增加同步 burst 入口以命中资源尚未准备的交互时序。

验证：实际 Session 方法与真实 property program/state 的 CPU 基线出现三项反例（独立更新、部分撤销、删除值），修后 11 门通过，含两 surface 部分接入回滚/重试、无 surface 等待和资源失败后的独立即时值保留。相邻属性/activation/runner 32 门通过。最终 Debug App 四项 burst 门通过，要求完整 pending/superseded/committed identity、窗口不重建、Metal 首帧/后帧 ROI 及 GPU drain；原 hidden-provider show/hide 两项 App 控制通过。此处两 surface 是受控 CPU seam，不声称物理多屏验收。 独立终审有界 ACCEPT：初版独立即时值被延迟的 P2 已修复；最终 8 PNG、24 ROI 独立复算像素误差为 0。

初次 App 输入为两张 4096² PNG，9 秒内未完成准备；延长同一输入至 40 秒，实际各约 7.8 秒准备后完成提交，排除本次调度卡死。最终四门用 1024² PNG，仍强制证明进入 pending 并重叠，不把未命中时序当通过。Debug 解码耗时仅作为后续候选，不作 Release 性能结论。初次测试 prepared entries 误写为 2，已按实际“0 即时 + 2 deferred”纠正；旧失败不计最终 PASS。

源码/App/输入 hash、原始截图、CPU/App 日志及审查保存在 `.artifacts/scene-evidence/runs/rf05-deferred-intent-20261004`（14 天）；最终身份以包内 `build-identity-v2.json` 为准。code-health、依赖、防御、设计、Debug 布局和 residue 门通过。结构门仍有 RF04 已存在的两项失败：`shape-derived-analyzer-fleet` 实际 66、登记 65；本批未改该库存，也未抬基线。

下一批优先 hidden consumer 条件激活与 script fallback：真实输入 `2938612768` 有两 consumer 共用 hidden provider，先用同结构自有输入找到执行断点，再按真实样本复验。当前 RF05 只关闭本子批，初值/脚本/多 surface 组合尚未全闭合；既定 Scene 卡仍为 15/16（93.75%），不代表全部真实样本兼容率。


<a id="rf05-png-decode-cost"></a>
### RF05 后继组合核验与 PNG 准备成本（2026-10-04）

产品基线 `27972161`。三个自有 App 组合均沿现有实现正确执行：隐藏 consumer 开启；两个 consumer 共用隐藏 provider，分别开启并关闭其中一个；visibility script 先返回 false、随后 exception，再使用最新 user 条件显示。每例 9 张 Metal readback、固定 ROI、GPU completion/drain 与输入/App 前后身份闭合，未据此改写已有正常路径，也不宣称对应真实 Workshop 整包已正确。

本批实际修改 `SceneImageTextureUploader.decodeRGBA8PNG`：filter 0 跳过恒零预测；连续行一次复制（含 Adam7 最后一 pass），其余交错像素直接写四通道，移除逐像素 slice/replace 开销。CRC、inflate 完整性、尺寸/字节预算、APNG、原颜色空间与透明 RGB 合同未变；同一入口继续服务普通图片、内嵌 PNG 与媒体，不增加缓存或 owner。

同输入单次 Debug App：两张 4096² PNG 从 generation 2 pending 到 committed，修前 15.509 秒、修后 0.376 秒；ready/after 四张实际输出及健康邻层像素相同。这是资源准备/提交时间，不是物理屏幕首像素时延，也不是 Release App 性能。独立 native harness 预载同一 RGBA 输入，每项三次，计时仅生产 decodeSourceImage，provider 读取及 SHA 在计时外；1024² 输入中位数：

| 编译 | filter 0 修前→修后 | filter 4 修前→修后 |
|---|---|---|
| `-Onone` | 483.397→10.134 ms | 610.298→481.786 ms |
| `-O` | 13.339→3.759 ms | 9.465→8.737 ms |

四轮共 84 次输出 SHA 与独立原始 RGBA 一致。9×11 Adam7 的优化编译测量有微秒级回退，不声称所有 PNG 均加速；这里只接受有界收益。通道门覆盖 60 个尺寸/交错/滤波组合，并保留损坏输入和 APNG 回归；Debug build 与相邻上传门按最终冻结源码执行。原静态显隐断言退役后漏收紧的登记已由独立窄提交 `29e3650a` 从 249 降至 248，不混入本产品修改。

最终源码、输入、App、native 原始测量及独立审查保存在 `.artifacts/scene-evidence/runs/rf05-png-decode-20261004`（14 天）。已知结构库存 66/登记65 的两项基线失败仍保留。下一步对真实 `2938612768` 执行隔离加载和属性切换，按首个公共失败定位修复；暂停期间延迟属性只确认了静态等待边界，尚未裁决冻结画面语义，不写成已修复。RF05 与完整真实样本目标继续开放，工作卡仍 15/16。


<a id="rf05-conditional-fullscreen-design"></a>
### 2026-10-04 隐藏全屏后处理即时切换（原实施前设计）

真实 `2938612768` 在冻结 `8bb5f522` 的正确签名隔离 App 中完成首帧，但背景 combo 两次 live 请求均拒绝。其 key 同时控制 image/fullscreen/particle/text/solid 显示；现役 live route 不准备隐藏 fullscreen 或 particle，任一未准备目标令整键回退重建。产品 service 已有重建回退，不能将 Debug live=false 外推为整个属性功能失败。

**目标/取舍。** 补齐具有 typed visibility owner 的独立 fullscreen 后处理准备及即时开关，作为真实组合的必要前置。完整23-target还缺粒子潜在可见准备、hidden simulation/child/RNG合同；本片不称整键可live。拒绝原拟 false-to-false 未准备目标豁免：脚本可覆盖 property visibility，两个 user false 不证明最终隐藏。保留完整 cohort 原子校验，避免 accepted 而资源未准备。Debug启动PNG成本另行处理。

**职责/数据流。** 原 `SceneDynamicLayerVisibilityRouteAdmission` 只扩无父/无子/无依赖、合法source route的 fullscreen utility 候选；原 graph admission/catalog、utility plan、preflight/pool 和唯一 compositor 负责准备与执行。计划准备不改 authored visible；隐藏帧不申领/编码该 graph，显示帧才捕获当前主画面。Utility planner只为已由graph admission接受的fullscreen保留capture计划；Host仅以实际execution ID及可capture计划声明live consumer；无owner、非法route、依赖/父子形态保持原边界。普通帧不解析、建图或增加资源owner，不修改property validator。

**验收/退出。** 自有 App先证旧版本不能开启隐藏fullscreen，再证开/关真实颜色、正确作者slot、首帧/后续GPU completion、退出drain和窗口不重建；同key含未准备粒子的负例仍须整笔拒绝，旧画面不变。Swift Debug build、相邻property/utility/graph门及独立审查通过后，将稳定职责并入原合同并删除临时设计登记。若现役source或生命周期不能承载则修原owner，不新增第二路径。后继补齐粒子动态准备后，再闭合真实293整组交互。


<a id="rf05-hidden-fullscreen-result"></a>
#### 实施与验收

三个产品职责已落地：结构admission准备有owner的合格fullscreen；utility planner保留已admitted capture；Host仅实际execution及capture就绪才声明live consumer。完整property cohort验证未放宽；稳定合同归[运行架构](../architecture/runtime-architecture.md#83-一帧的有序工作与可见时间)前的utility说明，临时设计登记已退役。

同自有输入修前两次live均拒绝，修后off→on→off两次接受，白底→128灰→白，后置green保持255，window/session不重建。含未准备粒子的同键负例、无effect/captured execution的fullscreen均整笔拒绝并保持白底。长期App三门通过（59.798s）；相邻property/visibility/utility/routing 44门与真实graph executor GPU harness通过（73.360s），Debug build通过。独审重算探针9张登记图/27个ROI、全输入/App身份及GPU完成/消费/drain，无新增P1/P2。既有结构库存66/登记65两项失败继续保留，未抬基线。

本机证据 `.artifacts/scene-evidence/runs/rf05-hidden-fullscreen-20261004` 限期14天。真实293第一次adhoc helper运行因签名不合产品Team门而无效；有效重跑已用正确helper签名，首帧78.239s，两次live拒绝由完整cohort解释，不能声称本片已修复整键或所有真实样本。后继补粒子潜在可见准备、hidden simulation/child/RNG与再显示语义，再复验真实293；公开visible合同没有规定hidden模拟策略，先做最小官方对照。工作卡15/16不变，RF05继续开放。


<a id="rf05-particle-visibility-design"></a>
### 2026-10-04 粒子潜在显现与生命周期

**目标。** 让初始隐藏、由 typed visibility 或 SceneScript 控制的粒子在原窗口中显现，推进真实背景属性的完整 consumer cohort；同时修正现有可见粒子后来隐藏时的模拟规则。仅扩充候选而接受空资源不构成完成。

**职责/取舍。** Host 在现有动态可见性准入选择可能显现的独立粒子根，将准备需求交给原 MetalView / ParticlePlaybackState / ParticleRuntime；不改 authored visible、不另建资源或模拟 owner。每个 surface 保留实际准备成功的粒子身份，Session 的既有 unavailableConsumerTargets 负责整键原子拒绝，surface 集合和 script generation 必须与当前会话匹配。准备失败局部降级，不能借静态 candidate、空 draw batch 或其他 surface 成功冒充可用。脚本直接改 visible 同样必须消费已准备实例及唯一 committed snapshot；child-only 和部分 child 失败应保持原局部失败语义。

**待裁决。** 官方公开 visible 只说明显示状态，不能推出 hidden 等于 pause、stop 或持续模拟。固定 2.8.0.42 自有双系统黑盒，以标记时钟及数量/位置区分继续、冻结、重启和仅停止发射；结果决定原 runtime 的推进策略。在此之前不批准隐藏状态模拟改变。一般性候选按作者语义识别，不按真实样本 ID/路径选择算法。

**验收/退出。** 自有初始隐藏→显示、显示→隐藏→显示、同键失败原子性、多 surface 实际准备缺失和脚本可见性；既有粒子 playback/child 回归，Debug、真实 App/GPU 和独审。随后重跑真实背景组合。普通帧不重建粒子图或纹理；隐藏路径能省去的工作须符合已证行为。最终稳定职责移交现有架构后退役窄登记，未证子系统语义继续明示，不能称全粒子 parity。


**首个行为裁决与实施分工。** 自有白 TEX 的固定官方 cycle 两次重复，在首次隐藏前两条粒子轨迹一致；t≈4.2及8.3重新显示时 experiment 仅有出生位置附近的新粒子，control仍保有多粒子长轨迹，排除持续模拟及原位置冻结续播。初始隐藏对照同样在显示时从出生状态开始。原 PNG黄色点状首试控制无效，不计结论。批准潜在准备与实际资源准入接线；运行时必须在现有 owner 中处理重新启动，不能仅解除 visible 过滤。starttime、pause/stop交互和child恢复仍由同一最小黑盒继续裁决，未证部分不得擅自等同。脚本 setter 与纯 visible返回两条路径都须拒绝未准备目标的显示请求；允许单独隐藏但同owner其他无效请求仍整笔拒绝。


**生命周期与事务裁决。** 后续自有差分确认：根的重新显示不重做 starttime；已完成 duration 的 emitter、paused/stopped 不因显示复活。静态子系统（含无根renderer容器）保留已有粒子并继续运动/老化，但隐藏期间不新增发射。RNG精确序列与所有flags不由这些观察证明。两个 paused 控制将 `emitParticles(1)` 分别放在 show setter 前、后，同帧出生均在显示后保留；单独隐藏帧的显式出生不会积累到稍后show。故现有“命令先install、advance再清群”不可接受，也不需要另建有序visibility journal。沿原粒子transaction在候选基线处理可见性，再重放当前帧命令，固定点重算失败owner；install原子提交原runtime的可见性与population。准入后的可见性setter（含父层）进入本cadence唯一typed snapshot，模拟与合成读取同值，不新增skip-reset标记、第二时钟或第二状态owner。preview也须使用同一可见性基线，防止满旧population导致合法show+emit在最终prepare前被拒绝。帧放弃必须同时恢复population、wasVisible和child状态。


**实施与验收。** 原 Host/Session→MetalView→ParticlePlaybackState/Runtime 已接通潜在根准备、全 surface/代际实际资源检查及同帧 visibility/emission 事务；纯 `visible` callback 也进入既有 bool VM。稳定合同移交[架构粒子职责](../architecture/runtime-architecture.md)及[粒子 G17](../capabilities/particle-component-coverage.md)，窄设计登记退役。冻结20个Swift输入的排序紧凑路径/哈希映射 SHA256 为 `dd80a9d7e7fe71dcc142f27f726760b7a22a565c9d9d756c56fb00371ea9b7a9`。Debug构建通过；8项粒子App与3项既有全屏App通过，独审重算36张粒子登记PNG：23张hidden无白粒子、13张visible的出生位置/同帧蓝时钟及绿色邻层全部通过。两种同回调show/emit位置差均≤0.678 scene px；3个重合出生的数量另由实际runtime记录验证，PNG本身不计重合粒子数。双surface只证明两个实际surface完成与同会话接受，不外推物理多屏逐屏像素。

真实QuickJS→两个Simulator的事务回归确认旧IDs 0/1先清，再安装新IDs 2/3/4；stale identity拒绝整owner、无安装调用、旧人口/RNG/revision不变。生命周期、属性deferred promotion、动态schema、帧提交及既有粒子回归通过，10个依赖外部语料的旧case明确跳过。两项旧fixture载体缺依赖已独立修复；新事务测试的种子revision不同步及诊断Swift类型推导错误均属无效初测，修后进入实际prepare路径通过。静态代码/设计/文档/依赖门通过；既有结构库存66/登记65两项失败保留，未抬基线。全语料、任意child/flags、GPU错误恢复及官方RNG/像素parity未验。隐藏空root重复清理有后续可省成本，但无本片性能测量。

**真实样本与后继。** 隔离2938612768最终App正常首帧、播放和GPU排空；5个粒子实例已准备。背景key `newproperty2` 两次仍拒绝：1021/1054各有一个当前inactive effect，fullscreen layer visibility仍要求capture/execution资格，阻断完整23目标cohort。后继先修这类无输出准入并保留真正缺capture的失败反例，再验背景整组切换；不计真实293完整正确。真实原件SHA复验未变；工作卡15/16（93.75%）不变，RF05与长期Goal继续开放。最终有界日志/自有输入/官方截图/App像素及身份限期保存在本机 `rf05-particle-visibility-20261004` 证据包；官方首个PNG黄色控制与失败启动不计有效语义观察。


<a id="rf05-inactive-fullscreen-design"></a>
### 2026-10-04 初始关闭的全屏 effect 准备

**目标与断点。** 真实293的背景属性仍受两个初始effect关闭的fullscreen阻塞。现有inactive effect admission排除了所有utility；仅放宽layer visibility不能支持独立effect开关。优先复用现有准备链，胜过无条件空输出豁免或另设重建路径。

**职责与边界。** 原SceneDirectBoolEffectVisibilityRouteAdmission接纳有动态owner、无父子/依赖且合法source route的独立fullscreen，保留普通媒体script依赖特权的原范围；graph planner仍须证明inactive stage可安全passthrough，实际catalog负责资源/执行准入。原utility planner为已准备fullscreen保留capture，帧snapshot决定实际执行。Host仅对完全没有effect、没有named-target职责且无依赖的合法fullscreen允许visibility空操作；有effect但无execution仍拒绝完整cohort。不增加owner、普通帧解析或graph重建。

**验收与退出。** 自有App验证独立layer/effect开关及隐藏时更新，白/灰底与后置绿色邻层、同window/session、Metal完成/drain；缺shader、缺粒子资源和依赖形态保持负例。复验真实293背景combo及独立effect属性，报告实际截图与接受边界，不以live=true冒充视觉兼容。Debug、相关原生门及独审通过后将稳定合同合入原架构并退役登记；RF05及完整样本目标继续开放。

自有共享bool App反例进一步定位：原TargetMapping只接Combo条件layerVisibility，缺direct bool映射，导致同键effect/particle全部落入rebuild。将layerVisibility映射为原typed bool target，继续由实际Host资源准入决定整键可用；不扩大层拓扑或绕过资源失败。共享bool App门保留为长期回归。

#### 有界实施结果

四个既有产品职责接通：inactive fullscreen effect准入、已准备capture保留、零effect无命名职责的visibility空操作，以及direct bool layerVisibility映射。后者由共享effect/particle开关的实际失败反例定位，限制为非负ID及bool属性，错误类型继续原拒绝；普通帧未增加解析/建图或新owner。修前初始inactive开关拒绝，最终自有App七门通过（171.431s）：白→灰→白、隐藏时更新后再显示，以及同key灰背景/红粒子同步出现和消失；后置绿peer保持正确。缺shader与缺particle texture仍整键拒绝。

冻结四源Debug通过；属性编译/提交46门、activation 23门、最终相邻23门及原graph Metal门71.614s通过。初版共享bool失败与修前反例保留，不计最终PASS。结构库存66/登记65的两项既存失败未改阈值；测试carrier无需扩充，超长executor保持原样。实际资源、GPU completion/drain、窗口/会话及原始像素证据由独立审查复核，单surface App不等于物理多屏或全样本兼容。

真实293同一冻结App首帧123.180s，背景1..8共八次同window/session即时接受；前三种有实际Metal截图。第四种起读回报metal-readback-setup，后续有superseded；最终GPU failed=0且drain完成，仍不能从接受或GPU完成推出全部八种画面正确。独立newproperty43两次拒绝：两个fullscreen已准备，但blur_combine的source-proven-previous-blurred-composite-unowned使stage保留inactive passthrough，没有冒充effect live consumer。进程采样落在原PNG解码；不把本次冷启动与旧样本时长直接做性能归因。

独立终审复算27张自有PNG/81ROI均正确率1.0、最大通道误差0，四产品源码/输入/App身份零漂移，有界ACCEPT。普通证据保留14天；真实293未闭合的读回/blur反例另行保护。下一批先定位切换后的资源/最终输出与读回失败，再接blur合成；其后多surface失败隔离与PNG准备成本。工作卡仍15/16（93.75%），RF05与全样本目标开放。


<a id="rf05-late-decoded-release"></a>
### 2026-10-04 晚期解码缓存回收

基础图片已经清过缓存，但后续静态模型、特殊图片和粒子模板仍会通过同一loader重新填充CPU解码缓存；会话持有loader令这些副本持续占总预算。现有两个同步准备结束点再次evict，仅释放CPU缓存及其lease，GPU cache和各消费者已准备资源保持原owner。诊断读回失败增加分配/预算快照，保留原失败退出，不改变配额。

真实293同输入/同八种切换：修前失败时decoded为63,887,105 bytes，修后为0。两次均能取得前四模式PNG，后四仍无足够预算；不能把截图增量、FPS或启动速度算作本片收益。修后首次失败resident为3,172,532,928/3,178,278,912，23,756,544-byte读回仍被拒；4,141.660ms最大呈现间隔未修，blur开关仍拒绝。全部八次背景属性接受、GPU failed=0与drain完成均不等于全部画面正确。

Debug构建、18项相邻原生门与修复载体后的截图生命周期门、14项deferred意图门通过；3项实际App回归（74.523s）覆盖粒子显隐、双surface及粒子/fullscreen共享开关。既有结构库存66/登记65的两项失败仍保留，未抬基线。独立只读审查未发现新增P1/P2。本片回归验证loader晚期再填充/再次回收、真实Metal预算拒绝→回收后准入，以及既有GPU纹理对象和红色像素不变；它不直接调用两个准备结束点，实际App覆盖消费者接线。验证与独审结果由本机rf05-late-decoded-release-20261004包固定；资源失败最小证据另行保护。下一批继续定位GPU持有/重复上传与切换间断，其后blur和多surface隔离。工作卡15/16（93.75%）不变，全样本正确率未建立，RF05与Goal继续开放。


<a id="rf05-video-backing-retirement"></a>
### 2026-10-04 视频 backing 退休与真实背景切换

实际分配探针排除了本样本同purpose重复上传：普通loader的46次上传没有同来源/设备/用途重复，约486MB，非视频大额存活峰值约715MB。视频导入失败时仍持165个backing、2,433,034,560 bytes；原入口把backing关联到Core Video cache持有的纹理，缓存存活时旧帧不能及时退休。自有四帧预算下100次导入仅4次成功，flush也不恢复，销毁cache才归零。

修复限定原importVideo：独立同格式texture view共享存储，同时保CVMetalTexture binding和CVPixelBuffer backing；租约仍按同一backing一次计费，GPU保view期间持续记账。Source的last/pending Frame已有view，不再另保currentCVMetalTexture及rollback副本。没有新cache、像素拷贝、配额扩大或每帧分析。初版只保binding的候选被GPU保账门否定（提前释放backing对象/额度），该候选App截图不计最终验收。

最终Debug和7项原生资源/截图/提交门、7项视频状态门通过。连续100帧default/flush各峰值两帧；另保GPU阻塞旧帧时100次仍成功、峰值三帧。四帧满额仍拒第五帧，GPU旧帧和当前帧全64² BGRA像素正确；完成后只留当前帧，全部owner释放后cache仍活着但额度归零。两个已知结构库存66/登记65失败继续保留，未抬基线。

最终冻结App在同一293输入与八模式顺序下，八次背景属性接受，25次实际Metal截图全成功，目标分配与读回失败均0。采样445次callback均提交、444次已完成/呈现、GPU failed=0，随后安全drain；最大呈现间隔75ms。GPU分配采样峰值1,104,412,672 bytes；修前诊断运行约3.45GB。历史4.14秒间断在本批若干未修诊断中也未复现，故不作普遍FPS或4.14→75ms因果加速声明；本片证明视频退休及该序列输出恢复，不是全画面官方parity、物理多屏或所有样本验收。

最终身份、原生反例和八张原始模式截图分包保留于本机rf05-video-retirement-20261004及rf05-video-retirement-captures-20261004（各低于32MiB、14天）。下一批直接处理两个fullscreen的blur_combine previous-blurred-composite首断点，之后多surface失败隔离；工作卡15/16（93.75%）不变，RF05及全样本Goal继续开放。


<a id="rf05-blur-kernel-one"></a>
### 2026-10-04 Standard Blur KERNEL1实际合成

真实293的两个fullscreen模糊层均为KERNEL1，原whole-stage只接受0；中性探针确认target、binding、state、scale和combine均满足合同。修复仅让原GraphAdmission接受H/V同为0或1，每node仍独立通过现有source/schema/resource proof，没有新shader数学、renderer、缓存或每帧分析。混合0/1、负值、2/未知值及错target继续拒绝；临时探针全部退出。

冻结Debug的原输入false→true→false→true三次均接受，同一窗口9次Metal截图成功；开启后背景细节模糊，关闭恢复，前景音乐卡和文字保持清晰。另以blur=true顺序覆盖八种背景，七次切换接受、18次截图无失败；1021和1054均实际执行downsample、H/V normalized-sample-sum、previous-blurred-composite四个genericCompilerArtifact pass，两轮都完成GPU drain。输入原件/副本与App前后hash一致。

自有静态App的三点归一化滤波验证两处条纹ROI白255→灰128→白255，每ROI79,524像素全部满足原±4容差；后置绿色保持不变，同窗口Metal/完成/drain及hash门通过。初版测试误用了另一个alpha-weighted合同而被colorTransfer拒绝，修正自有shader形状后通过，产品代码和oracle未放宽。GraphAdmission、unowned/owned failure及stock compiler/Metal编译三组15项通过；后者不是GPU数值验收。Debug、依赖、代码健康、防御、设计与产物门通过；结构门保留原有两项66/65库存失败，不抬基线。独立审查确认准入和真实可见结果无P1/P2。

本片收益是原本无效的背景模糊开关进入实际输出；开启时执行作者四pass。带截图的八模式运行采样约21.26 completed FPS、GPU分配峰值1,060,601,856 bytes、286/286完成且failed=0；这不是同条件性能对照，不能声明降低成本或官方kernel权重等价。KERNEL1×mask/Timeline等动态scale组合未单独运行，物理多屏与全样本仍未验收。最小中性日志、身份、回归结果与原始截图保留于本机`rf05-blur-kernel-one-20261004`，单包<32MiB、14天；临时App/样本/缓存清理，沿用一份checkpoint构建缓存。下一批多surface提交失败隔离与恢复；当前卡15/16（93.75%）保持，不能作为全样本正确率。


<a id="rf05-paused-text-publication"></a>
### 2026-10-04 暂停后的异步文字发布

双surface的单方提交失败及双方frame0 seal拒绝均能恢复；VM与粒子事务不重复消费，未因此新增产品分支。沿暂停首帧继续验证时发现真实断点：文字在首帧提交后才异步光栅化，成功发布没有通知原surface，暂停驱动已停止，因而持续显示旧字。修前隔离App的两个surface均完成frame0，随后文字发布却没有重画。

原TextStore仅在generation接受且光栅成功、释放锁后通知；原MetalView核对store身份后转既有surface invalidation。Session继续核对surface身份，暂停时重画冻结frame，不推进VM、时钟或模拟。失败与stale不通知；没有新增timer、资源owner或普通帧轮询。Debug增加显式start-paused和证据模式下有界文字延迟，固定反例时序。

最终Debug与17项相邻原生门通过；六项实际双surface故障/恢复门通过。延迟两秒、暂停双surface的实际App与同App静态NEW TEXT对照一致：3024×1964读回中128,190个白色文字核心像素的mask、边界和数量完全相同，绿色邻层35,721像素保持正确；两个surface均在frame0重画并完成，脚本没有重放。像素仅代表选中的一个surface，不能外推物理多屏逐屏像素；暂停后没有新invalidation的晚期after截图在退出时失败属预期，不算成功截图。依赖、代码健康、防御、设计与产物门通过；结构门原两项66/65库存失败保留。

此修复让已暂停场景的晚到文字真正出现在最终画面，不需要恢复播放或resize；未做性能对照，也未证明全部真实文字内容及官方排版。最小自有输入、前后反例、PNG和身份保留于本机`rf05-paused-text-20261004`（<32MiB、14天）；临时App退出后清理，复用一份checkpoint缓存。下一批优先核异步媒体首帧/重建后的发布与暂停重画，若无实际断点则回到真实样本失败队列；不扩充纯证据批。工作卡15/16（93.75%）不变，RF05与全样本Goal继续开放。


<a id="rf05-paused-media-publication"></a>
### 2026-10-04 暂停媒体资源发布修复

修前正常播放显示自有青色封面，暂停首帧后两个store均ready却不重画。原View的重复pending输入在提交失败时丢失；改由SimulationFrame持Host已采输入，成功提交幂等update，失败只解除资源pin。Store在接受成功/缺失/坏图终态后锁外通知，stale不通知。Session仅在全surface同冻结frame/已采generation皆terminal时更新资源快照，不重采Inbox、执行VM或媒体事件；旧surface仍受身份检查。

初版复验发现单面拒绝令两个decode错开约30ms，首个ready沿通用失效入口提前重画备用图。改用原失效回调的typed reason，媒体通知先检查完整cohort且changed再唤醒；后续同代通知不额外重画，正常播放由下cadence取资源。文字/窗口等仍按原surface失效处理，无新timer、cache或提交owner；Debug证据模式有界延迟只固定回归时序。

最终实际App三门通过：同输入control/暂停晚到、一次单面提交拒绝后恢复、坏封面回退。选定surface的3024×1964 PNG分别含571,536个青色封面像素或同面积红色作者fallback，35,721个绿色邻层像素保留；正常control与暂停青色面积一致。两个surface均在最后store terminal之后完成frame0，媒体事件实际执行一次，无VM重放，GPU排空。首个fixture用不支持的solid.color脚本导致owners=0，已改为已支持visible布尔入口；该无效初测及初版提前重画不计验收。

Debug、8项原生provider/事务门及frame-context载体适配通过；文字、共享VM和粒子相邻实际App回归以最终冻结日志为准。依赖、健康、防御、设计与产物门通过；结构库存66/登记65的两项既存失败保留。只证明冻结帧已采媒体输入的晚到资源刷新，不承诺暂停期间新Inbox事件被执行，也不外推物理多屏逐屏像素、官方parity或性能提升。最小自有反例、身份与PNG保留本机`rf05-paused-media-20261004`（<32MiB、14天），临时App清理，保留一份checkpoint缓存。

下一批回到真实Pixels（3122339805）：本次25秒隔离运行两次Metal读回及GPU排空正常，历史三层text bad-return未复现，但layer101/effect0仍有effectVisibility的out-of-cohort mutation拒绝。先取得中性mutation形态并修共享owner边界，保留越界写入负例；其次复验3470948192，不沿用旧失败当当前事实。当前卡15/16（93.75%）不变，RF05与全样本Goal开放。

<a id="rf05-effect-owner-alias"></a>
### 同一特效句柄的可见状态事务（2026-10-04）

真实Pixels（3122339805）的中性探针确认：layer101/effect0的visibility owner只写回自身effect（fields256），却被当作跨cohort layer mutation拒绝。现于既有C句柄入口按layer/effect身份复用thisObject.visible的staged/pending/committed状态；name/index及thisScene lookup读取同一事务。保留stale handle、active owner、effectful Bool检查和跨effect/层副作用拒绝，不新增状态、owner或普通帧解析；临时探针已撤除。

修前真实QuickJS新增五个别名反例失败，修后同owner别名、双向read-your-writes、事件回滚重试/idle quiet及bad-return恢复通过，跨effect/层/其他字段继续拒绝。自有App复用现役fullscreen fixture，仅以scene time控制同effect：修前3.5秒仍白，修后1/3.5/7秒为白/灰/白，后置绿色邻层不变；同窗口、真实Metal读回与GPU排空成立。Pixels最终25秒运行原拒绝消失、两次截图与排空正常，输入及源码/App身份未变。未做官方像素对照、全部交互或性能测量，不能据此宣称Pixels或全样本完成。

最小自有输入、前后像素、真实中性日志与身份保留于本机`rf05-effect-owner-alias-20261004`（14天）；构建与独审结果由冻结证据记录。临时App/样本在归档后清理，仅复用一份checkpoint缓存。下一批复验真实3470948192（水滴 三体）的pass API/变换/最终合成，以当前实际失败决定修复，不把历史异常当作现状；其次复验3509243656。工作卡15/16（93.75%）不变，RF05与全样本Goal开放；完整样本正确率尚无可报告分母。

<a id="rf05-png-filter-cost"></a>
### 内嵌PNG加载与同尺寸通道转换成本（2026-10-04）

真实3509243656在Debug App的150秒观察窗口内未到首帧；进程采样定位内嵌PNG滤波循环。只优化循环后，热点推进到原尺寸RGBA仍逐像素box重采样，150秒窗口仅刚到首帧。最终在同一SceneImageTextureUploader中借用行buffer并使用直接字节循环；对已校验、同尺寸、tight-row、非little-endian的RGB8 straight-last源直接复制原字节。真正缩放、padding、其他通道/位深仍走原路径，颜色空间职责、透明RGB、CRC/inflate与APNG合同不变；规则依据[PNG公开标准](https://www.w3.org/TR/png-3/#9Filters)，不增加cache/owner。

最终隔离App从accepted至launched为14.351秒，继续播放25秒、两次Metal截图与GPU排空正常；输入与产品/App身份不变。这是单次Debug启动观察，不是受控Release端到端性能结论。原生基准对同一自有输入每项预热一次、计时三次，分别测decodeSourceImage和预解码后的rgbaData，完整字节与SHA在计时外核验。2048² Paeth中位数：Debug解码1964.478→680.337ms、同尺寸转换3541.335→0.224ms；优化编译分别28.174→25.198ms、29.447→0.164ms。filter0的1024²解码有小幅回退（Debug11.352→11.714ms、优化4.873→5.361ms），不声称所有PNG均加速，也不把两段相加冒充App完整耗时；结果及独审由本机`rf05-png-filter-cost-20261004`冻结证据保存（14天）。原PNG正反例增加真实通道转换字节核验，原通道/上传/预算边界继续回归。

3470948192的一次scale bad-return在24ms后已有有限输出，作者shared输入与官方首帧仍unknown，未改数值fallback或执行顺序。下一批回到真实交互/显示组合，优先检验三体已加载后的属性切换与输出，出现当前公共断点即修；没有实际失败则转其他真实能力缺口。工作卡15/16（93.75%）不变，不代表全样本正确率；RF05与长期Goal继续开放。

<a id="rf05-parent-visibility"></a>
### 普通父层显隐与后代准备（2026-10-04）

真实3509243656的clock绑定普通container父层，三个text子层已具备资源和父链显示消费，热更新却被无父子根层准入拒绝。保留原整键事务，在同一准入owner区分作者visibility目标与可被其揭示的准备闭包；固定、唯一身份、父引用完整且无环的普通container/image/solid/text树进入现有graph和首surface准备。子层自身false不被覆盖；图片后代保持eager准备，避免父show不改子条件key时漏请求；初始false的子effect与legacy文字Program同样准备，QuickJS优先排除不变。非普通层级维持原边界，无新状态owner或普通帧建树。

同一真实输入与clock false→true→false请求，基线三次拒绝，最终冻结App三次接受且同窗口内更新；after原始Metal截图中时间、星期、日期一起隐藏，星空、天体和文明状态仍显示，输入及App身份不变、GPU排空。该对照关闭了“只能重建才能切换普通父层”缺口，不证明整个三体场景或官方画面一致。临时中性probe只用于定位consumer不在准入集，已完整撤除。

设计与产品独审发现的fullscreen子层误扩张已收紧：普通子层走普通树准入，fullscreen仍要求无父子。重复ID反例不进入旧visibility的唯一键字典；非法树按目标拒绝。最终Debug及原有FBO激活回归通过；自有App隐藏/可见启动两门通过，文字像素与静态00:00控制一致，子effect白→灰、普通图片随父显隐、子自身false及绿色邻层保持，同窗口且GPU排空。8项准入正反例通过，基线父层断言失败；包括真实DirectBool/utility route的普通子effect接纳与fullscreen子层拒绝。完整输入、最终验证与独审身份由本机`rf05-parent-visibility-20261004`保留。前两次控制图测量分别受cover裁切和Y坐标反转影响，修正输入位置及ROI后按原容差完整重跑；无效初测与中途改动导致的编译失败均不作产品验收。

下一批修真实背景combo涉及的模型子层显隐与准备；本次不放开模型准入。工作卡15/16（93.75%）不变，RF05与长期Goal继续；全部真实样本正确率仍无可信百分比。原始必要PNG与最小日志/输入保存14天，已停止的App、临时HOME和重复缓存归档后清理，仅复用一份构建缓存及下一批App。

<a id="rf05-model-visibility"></a>
### 已准备静态模型的属性显隐（2026-10-04）

真实3509243656的背景combo同时控制三个普通容器下的模型叶层及一个image；静态模型已由原shared device resources提前准备，Host却未登记visibility consumer，整键因此拒绝。原准入增加实际prepared IDs输入，只接受无effect/utility/子层的静态模型及合法普通祖先；同一树校验核祖先child索引一致性。Host在准备后登记属性consumer，其他准备/脚本调用默认空集；不新增状态、模型资源、阴影或合成owner，不把部分multipart Entry当完整模型或named provider发布。

同输入五次背景请求从全部拒绝变为全部接受，原窗口最终从8K星空切至纯色，时钟/天体继续显示；另一次纯色→8K在原窗口恢复星空。输入与App身份保持、Metal截图及GPU排空成立。自有模型+image同combo隐藏启动→显示→隐藏→显示与独立静态controls逐ROI一致：阴影9/亮接收面85，隐藏后两区恢复85；模型、蓝image及绿色peer正确，自身false的红模型始终不画。坏MDL时两次请求均拒绝，普通image保持隐藏，证明整键原子guard未削弱。

Debug构建、9项结构准入（原基线新增模型断言失败）、31项相邻属性/材质与11项准入回归、自有App两门通过；独审及身份随本机`rf05-model-visibility-20261004`保留。首次staged App的Sparkle签名无效试跑已终止，不计验收；修正隔离签名并deep/strict验证后完整重跑。结构库存66/登记65两项既存失败未改变。未新增脚本模型、模型父层/effect或动画能力，也未证明named provider新覆盖、完整三体场景、官方parity或性能收益。

下一批转向非350的真实组合：优先3769761761粒子与光束特效，其次3211615441点击/跟随输入、3775355045双video。旧记录仅为有界通过或未验画面，不当作当前故障；逐个隔离复验，找到当前公共首断点后直接修产品，不另开纯证据批。工作卡15/16（93.75%）不变，RF05与长期Goal继续，全部真实样本正确率未知。本批最小输入、关键PNG与身份保留14天；归档核验后清理临时App/HOME，仅留下一批App和一份构建缓存。

<a id="rf05-turbulent-forward"></a>
### 湍流初速度保留作者 forward 幅度（2026-10-04）

3769761761的官方窗口关闭Ember后目标斜光消失，独立429仍显示光束；自有白纹理黑盒进一步确认forward为`0 1 0 / 0 2 0 / 0 20 0`、speed=10、phase/scale/offset=0时，官方速度约10/20/200。原实现两次归一化丢弃作者幅度，现仅在既有初始化结果乘回forward长度，随机数消费、方向/noise及出生安全owner不变。来源与边界见[官方黑盒合同](../development/source-index.md#particle-turbulent-forward-blackbox)。

自有App的forward20速度由约9.73恢复至198.30，官方约199.82；独立蓝色时钟估计年龄，帧相位和像素量化差异不作精确parity。真实429黑底可见对照从左侧短段扩展为大范围斜束，但未保存该variant两次运行前后完整输入身份收据，因此不称严格same-byte单变量验收。原包最终35秒运行、六张Metal截图、输入/App身份与GPU排空通过；头发上方斜光仍偏弱且方向不同，整样本缺口继续开放。

原生门经真实parse→birth→两秒motion→trail验证：基线九项反例失败，候选三门通过；forward与speed分别可表示而乘积超Float时四次出生均拒绝，独立健康sim正常。相邻81门的唯一旧幅度期望已纠正并单独复验；Debug构建和独立只读审查通过。无新owner或普通帧分析，不声称性能收益、非正交轴/noise等价或全样本正确。结构库存66/登记65两项既存失败不在本批调整。

最小自有输入、原始必要PNG、身份和验证保留于本机`rf05-turbulent-forward-20261004`（14天）；临时App/HOME及传输副本归档后清理，复用下一批App与一份checkpoint缓存。下一批用相同白纹理控制输入收敛非正交轴方向，再处理真实斜光亮度；若方向无差异则转3211615441输入交互或3775355045双video组合。工作卡15/16（93.75%）不变，RF05与长期Goal开放，全部真实样本正确率未知。

<a id="rf05-turbulent-axis"></a>
### 湍流非正交轴旋转（2026-10-04）

前批恢复forward幅度后，受控倾斜normal仍暴露方向误差。现于同一初始化owner改用单位轴旋转，保留forward沿轴分量；原raw-cross阈值、parallel/zero退化处理、phase→speed随机数顺序及最终Float出生安全检查不变。只增加出生路径常数算术，无新owner或普通帧分析；[六个官方黑盒控制](../development/source-index.md#particle-turbulent-axis-blackbox)支持方向修正，不证明noise/up或随机分布等价。

自有App的倾斜轴XY速度约(36.986,67.715)→(26.888,74.461)，官方约(27.129,75.212)；轴×10与候选原轴像素测量一致，正交控制保留。原生parse→birth→两秒运动→trail门中，基线四个非正交子例失败，候选连同相邻共86门通过；非法轴真实strict emit预备拒绝且状态回滚。Debug构建及独立审查通过，结构库存66/登记65两项既存失败未调整。

同包SHA的真实429根粒子黑底前后15秒运行、12秒截图、App/输入身份与GPU排空成立；光束分布上移、方向发生变化，但亮度仍弱，不能视作官方视觉匹配。原包前后各35秒、六张Metal截图及排空成立，头发上方目标斜光仍不明显，完整样本不关闭。ray-vector黑盒与理想旋转数值的余差原因仍未知，不确定归因为投影或phase；未测性能收益。

本机`rf05-turbulent-axis-20261004`保留最小自有输入、关键PNG、身份与验证14天；遮挡初测及一次guest调用失败不计验收，后续仅重跑缺失输入。官方窗口/guest临时目录已清理，VM恢复暂停；本轮App/HOME/传输副本归档后清理，留一份下一批App与checkpoint缓存。下一批核粒子片元alpha到加法合成的亮度链，再按真实证据选择纹理/尾迹宽度或321输入、377双video。工作卡15/16（93.75%）不变，RF05与长期Goal开放，全部真实样本正确率未知。

<a id="rf05-particle-alpha-contract"></a>
### 粒子顶层 alpha 合同纠正（2026-10-04）

自有10格静态和12格绑定/写入输入在官方2.8.0.42中确认：generic particle顶层alpha不调制Sprite，instance、粒子及纹理alpha各自有效，零instance透明而零顶层不隐藏。现有Runtime却把顶层alpha再乘到root/child输出；现删除该存储与每帧读取，保留逐粒子/instance alpha及显隐生命周期，rope与child既有参数入口取单位乘数，不新增owner。此前R01的顶层调制说明已纠正；公开来源及受控边界见[黑盒合同](../development/source-index.md)。

同输入冻结App前后，静态10格由4格匹配官方变为10格匹配；顶层.01的白粒子由3恢复255，纹理.25与粒子.25控制保持64。动态12格由5格匹配变为11格：静态/包装/绑定/thisLayer.alpha不再错误压暗；thisLayer.instance.alpha写入仍输出128而官方32，单列下一批，不称全部实例API通过。root+child原生反例旧版输出.2而应为.5，候选九组静态/typed快照及playback输出均.5；邻接播放/显隐等58项运行中46通过、12无本机输入跳过。

真实376原包35秒播放、六张Metal读回、输入/App身份及GPU排空成立，目标头发上方斜光仍缺。必须纠正调查中的归因：429的.01是instanceoverride.alpha，真实包所有粒子均无顶层alpha，因此本修复不提高该样本光束亮度，不能据自有控制宣称真实缺光恢复；原作者实例值保持不动。官方900方窗只作为有界视觉参照，既存editor对话框遮挡右下，目标左上未遮挡，不作同尺寸像素真值。

Debug构建通过，结构库存66/登记65两项既存失败未调基线；其余职责门与独立终审由冻结收据记录。触达的巨型测试载体按既有职责迁为可直接编译的Swift fixtures及Python测试组，保持唯一编译入口和原有断言，不把文件/测试数量算成果。本机rf05-particle-alpha-20261004保留最小自有输入、关键PNG及身份14天；临时App/HOME归档后清理，保留下一批App与一份checkpoint缓存。下一批先修已复现的instance alpha写入，再按真实证据回到376出生/轨迹、321输入或377双video。工作卡15/16（93.75%）不变，长期Goal与全样本正确率仍开放。

<a id="rf05-instance-alpha"></a>
### 粒子实例透明度的脚本读写与出生消费（2026-10-04）

`thisLayer.instance.alpha`原先为undefined，赋值使脚本失败。现将有限Number读写接入既有layer mutation journal、owner准入、typed粒子值及出生consumer；没有作者override时用单位默认，实际已准备但alpha=0的层仍可恢复。getter读当前回调前缀，两次emit各取调用时值；throw、迟到owner拒绝、失效身份和超预算均不发布半个事务。Generic layer alpha保持独立，未开放其它instance字段，也未增加renderer、clock或最终输出owner。

官方自有Sprite黑盒在蓝色时钟确认切换后：存量灰粒子保持128，新生降为32，绑定与setter一致；只支持该受控profile的出生消费，不证明精确callback/return/GPU阶段或其它renderer。冻结App同输入前后，12格控制中setter由128→32，达到12格匹配；六格时序中存量仍128、setter新生128→32。五格发射对照中，.25与.5两次发射由无输出恢复合成96，与.75静态控制一致；抛错层保持0、健康邻层64，初始instance=0的层赋值并发射后0→32。六次App运行均输入/可执行身份不变、正常退出及GPU排空。该收益适用于使用此API的粒子脚本，不等于真实376缺光已修复；本批没有新的376整包画面验收。

Debug、C接口正反例、真实VM→typed→simulator与邻接回归结果由冻结收据保存；原alpha0层“不准备”测试改为prepared draw batch的GPU ABI实例数组非空且alpha全0。初次C重名编译失败、误复用已禁用owner的测试失败和旧alpha0名单失败已分别修正复验，不作为通过证据。结构库存66/登记65两项既存失败未调基线；独立审查范围及结果随本机`rf05-instance-alpha-20261004`记录。未测性能提升；为可恢复零透明层保留实际准备会增加此类输入的必要资源/模拟成本，未引入第二份生命周期。

最小自有输入、关键PNG、身份及验证保留14天；官方自有窗口与guest临时目录清理，VM恢复暂停，App/HOME及传输副本归档核验后清理，复用一份下一批App和构建缓存。下一批转真实3211615441输入交互，若当前链健康则转3775355045双video；376斜光继续开放，避免围绕已关闭的alpha控制重复实验。工作卡仍15/16（93.75%），RF05与长期Goal开放，全真实样本正确率未知。


<a id="rf05-composition-visibility"></a>
### 固定组合层实时显隐（2026-10-04）

真实326的clock与第1分组分别关闭/恢复均被原热更新拒绝，moon两次接受。沿原准入准备合法composition祖先/后代与初始隐藏文字/子图；保留已准备group及childless背景采集的capture计划，无effect组只保序。独审静态反例还补齐潜在高级混合层的启动drawable读取用途。产品只改两位现有owner，无新增状态树/compositor。收益是同窗口切换与恢复，原服务可能通过重载完成相同意图，不能表述成原样本完全无法显隐。

冻结V3 Debug与自有App两门通过：同一输入原版隐藏启动后三次请求拒绝，候选隐藏/可见启动两种反复切换均接受；三层dim灰块32、两层灰块64、文字mask与literal静态对照一致，自身false红层无残留，绿色邻层保持，Metal完成并排空。真实326六步由false/true/false/false/true/false变为全true，窗口身份不变；截图已见时钟隐藏/恢复、第1警示带隐藏及最后请求之后的独立末图恢复（after delay=16）。正式收据归本机`rf05-composition-visibility-20261004`。

CPU visibility/readable各15项通过，HEAD分别5项/1项失败；后者仅为实际函数合同反例，Debug截图会强制可读目标，不能充当未改版GPU崩溃复现。138项治理通过；结构库存66/登记65的两项既存失败保留。自有App与真实样本只证固定profile，不证明特殊成员、passthrough、官方画面等价或性能数值；启动隐藏资源准备可能增加。首次将App目录误作可执行路径的试跑未启动、明确排除。

选题复核另确认321当前Central点击换图、Double移动有响应；377视频source首帧等待后第4/5帧完成并被compositor消费。旧记录不足以证明当前故障，不为这些旧标签另改产品；这两项仅是本轮有界复核，并非整样本验收。15/16 Scene卡完成的口径不变，RF05与全样本正确性仍开放。


<a id="rf05-parent-particle-visibility"></a>
### 普通父层的粒子显隐与资源准入（2026-10-04）

真实3396722575的代码雨父层2772控制四个已能绘制的粒子后代，但关闭/恢复均被live拒绝；独立粒子开关正常。现由唯一visibility准备闭包接纳固定普通父树下有path、无effect/子层的粒子叶，删除旧root-only helper。Launch保存目标→所需粒子ID，Session的整键及script owner检查完整surface、generation和实际资源；普通帧不重建层级。独审发现并修复了独立根粒子带inactive effect时的资格回退；保留旧显隐资格不表示其effect已获支持。

同输入冻结App前后，真实四次请求从false/false/true/true变为全部true，同一窗口完成；最终Metal截图关闭时底部代码雨消失，恢复后重现，退出GPU排空、输入及App身份不变。未复现旧particle-load-incomplete标签，本批收益是分组切换进入现有会话，不宣称修复了全部加载、官方reset时序或整个样本。

最终Debug构建及12项实际App显隐门通过（309.171s），旧App在同一嵌套父层双surface正例失败。新门覆盖隐藏启动→显现→隐藏→恢复的实际粒子位置、image、独立false子层与健康peer；缺纹理整键拒绝、setter/纯visible返回失败均撤回同owner的peer透明度与独立有效emitter发射。CPU路由20、Session18及相邻36门通过；HEAD相同CPU输入分别有3个失败测试、14个失败子例。独立审查复核产品、输入身份与像素；结构库存66/登记65的两项既存失败未调整。两surface运行不外推物理多屏，也未测CPU/能耗改善。

本机`rf05-parent-particle-visibility-20261004`保留必要输入、日志、关键原图及身份14天，临时App/HOME/包副本在核验归档后清理，留下一批App与一份构建缓存。下一批回到376上发丝斜光，区分operator运动轨迹与SpriteTrail几何；312旧文字/alias故障已不复现，不重开旧修复。工作卡仍15/16（93.75%），RF05及长期Goal开放，全样本正确率未知。


<a id="rf05-turbulence-mask"></a>
### 湍流逐轴mask保留幅度（2026-10-04）

376的429真实粒子使用`1 0 0`mask。共享math在逐轴相乘后再次归一化，错误擦除作者幅度并把单轴衰减放大；现删除该次归一化，沿原Simulator的有限Float原子累加消费，不改noise、seed、时钟、renderer或compositor。公开[Mask合同](https://docs.wallpaperengine.io/en/scene/particles/component/operator.html#turbulence)明确逐轴缩放。

官方2.8.0.42/hash `daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07`的自有同输入单粒子黑盒，只改mask：unit/quarter/unit重复的约2秒位移分别为(45.23,36.80)/(3.41,6.08)/(33.28,24.85)，quarter差异超过重复波动加4单位。仅支持幅度有影响；空间noise反馈不支持总位移精确1/4。早期零scale无响应、过强输入裁切及五行精确比值方案均未计通过，不据此推断官方noise公式、seed或3D等价。

同冻结输入在实际MyWallpaperX运行：旧版unit/quarter/double三行均为(81.51,-23.50)；修复后同帧分别为(74.91,-21.72)/(18.79,-5.21)/(149.81,-43.05)，x-only保留unit的X且Y约0，zero保持原位。绿色原点与蓝色时钟确认采样，未跨运行硬比相位。此项目自有零scale门验证消费到最终像素，不充当官方轨迹golden。真实376原包前后各35秒正常播放、Metal捕获及GPU排空；上发丝斜光仍缺，整样本未验收。

新增6项parse→Simulator门在旧math产生7个失败子例，修复后全过；覆盖倍率、各轴/零/负mask、顺序、RNG不变与Float累加溢出只拒绝当前粒子。Debug及相邻CPU门通过，最终审查与归档身份归本机`rf05-turbulence-mask-20261004`。不增加owner，不量化性能收益；下一批核SpriteTrail转向几何。工作卡仍15/16（93.75%），RF05及全样本正确性开放。


<a id="rf05-trail-direction"></a>
### SpriteTrail当前速度定向与历史退役（2026-10-04）

自有白纹理单粒子抛物线的实际App near-apex主轴56.31°，自身六质心轨迹切线34.31°，误差22.00°；8槽历史弦预测57.29°。独立像素复算排除了时钟起点、裁切及白阈值，官方同版本/hash六曲线帧的误差0.05...2.40°、直线六帧为0°。因此当前速度统一负责SpriteTrail方向和stretch：已有TrailRenderPlan用max-abs与Double hypot生成安全Float单位方向，root与child共用，child仍先经原transform.velocity。删除仅SpriteTrail使用的8槽环、模拟器构造/记录/快照/预算接线；RopeTrail的step recorder及回滚保留。每个SpriteTrail粒子不再保存8个Double位置与head，不宣称测得CPU/能耗改善。

冻结Debug候选的相同曲线after主轴−26.57°、自身轨迹切线−30.96°，误差4.39°，处于半隐式fixed-step与像素误差界；不跨运行硬比clock/角度。自有低速Y输入`.00006`在旧root因历史弦与GPU阈值错配显示水平，修复后竖直；static child始终竖直、zero始终保持既有水平fallback。实际Runtime packing门覆盖root/child、apex两侧、低速、zero、大有限值、普通Sprite不变及stretch。真实376原包35秒播放/截图/退出排空通过，上发丝斜光仍缺；不能把上述门报成整样本修复。

官方position-only补充探针出现新assert且无有效像素，修正输入后的启动又进入恢复提示，两组均不计行为证据；只关闭本轮窗口/新进程、删除本轮guest目录并恢复VM暂停，既有editor错误窗口未处理。不据失败猜测oscillation或零速官方语义。正式证据归本机`rf05-trail-direction-20261004`，下一批追376覆盖区域及材质/合成首断点；若无新断点则重排其他真实故障。15/16卡（93.75%）仅为有界卡口径，RF05、长期Goal与全样本正确性仍开放。


<a id="rf05-trail-affine"></a>
### SpriteTrail非等比宽度与作者平面（2026-10-04）

旧GPU在投影后重建垂直宽轴并统一乘layer X尺度，丢失作者非等比缩放及剪切。现由既有CameraFrame传递local screen/fixed的变换前平面法线，GPU先定宽轴再施加完整layer线性变换；保留原纹理朝向符号，world-size、world/upright及Rope位移分支维持原行为。不新增owner、资源或每帧解析，未测性能收益。独审淘汰了从退化矩阵重建法线的初版，零深度倾斜及Fixed-XZ零Y反例覆盖显式平面来源。

官方2.8.0.42及前批相同hash的自有白纹理八卡，与冻结Debug App消费同输入。X拖尾scale(.5,.125,.25)长/宽：官方128/8.53，旧App128.46/31.67，修复后128.46/8.21场景单位；斜向及旋转卡恢复仿射轮廓，单位与等比控制不变。左侧unit-X被App cover裁剪，不计长度对齐；全部斜向bbox也不宣称±2单位或纹理/镜像官方parity。低alpha重叠实验两端一致，未改混合精度；真实材质可从随App发布的stock资产解析，未将缺少包内纹理误判为程序回退。

最终Debug构建、26组生产Metal顶点/像素输入及相邻渲染门通过。新门独立计算四角及完整覆盖，含旋转、镜像、零列、极小尺度、Fixed-XZ、world-size、普通Sprite及真实RopePlan控制；原±10测试深度裁剪已修为±1000，未放宽几何容差。真实376原包35秒播放、Metal截图、身份不变及退出排空通过，上发丝斜光仍未恢复，整样本未验收。证据及独立终审绑定本机`rf05-trail-affine-20261004`，不外推完整3D/透视/atlas或全语料。

连续376局部修复已有可见收益，继续追noise/亮度的即时收益尚不明确；下一批先复现3470948192首帧非有限scale，若存在则修最早共享owner并复验真实加载。376保留为未解视觉差异，不删除或判通过。15/16卡（93.75%）仅为有界卡口径，RF05、长期Goal及全样本正确率仍开放；临时App/样本/HOME归档后清理，连续迭代只留一份构建缓存。


<a id="rf05-model-material-keys"></a>
### 静态模型材质声明键（2026-10-04）

**静态模型材质键绑定修复决定（2026-10-04）。** 显隐结果见[原执行记录](#rf05-model-visibility)。347粉紫覆盖随模型186隐藏消失；官方同包仅改Alpha=.02→1产生强粉色，改alpha=0仍暗。同uniform在不同声明映射Alpha/Color/Brigtness或alpha/color/brightness，现模型按小写优先取值错误。direct model唯一pass0在descriptor准备期复用现ShaderSchema证明无条件三通道接口，校验stage/include闭包、全潜在声明的类型/array/key唯一性及宏歧义；不依赖完整shader执行、纹理ready/format，也不枚举资源状态。immutable DTO保存精确key/default供静态、属性和帧消费共用。区分proven、unavailable和已证输入invalid：无法证明接口保留原绘制及属性接线并记录迁移债，不能因未知sampler信息丢模型；已证明具体非法值拒绝当前part。无source的hostBuiltin维持原入口。只修现color/opacity/brightness寻址，不新增custom shader语义、mesh Program或输出owner。自有反例覆盖大小写、条件重复、宏重写、跨stage冲突、属性与peer；冻结App必须保住115/186/14并改善粉色覆盖。满足后收口，星轨named93→115等差异继续按真实首断点选题。

真实3470948192原包SHA256 `7151bf3194a8765ce6183149d80dbb48e8d869c075cc2940f52abbf900d0e818`。旧App背景粉紫；隐藏186后消失。官方2.8.0.42同包单变量：Alpha .02→1出现强粉色，alpha 1→0仍暗；上调Alpha仅留人工屏幕观察，黑色无效截图不计证据。独立实现只消费声明接口和行为结果，未读取私有表达式。

准备期复用严格无条件接口证明，DTO置于Runtime供编译与渲染共享；三通道静态值、property Program及动态consumer使用同一精确键。未知宏/条件/producer保持原绘制及emissive接线；已证明的非法形状、Float范围或被旧decoder丢失的非数值token只拒绝当前part。完整shader准备依赖未知纹理ready/format的早期方案已撤回，不枚举资源状态或猜格式。

最终V8 Debug的1085份产品源码冻结无漂移；同一未改原包播放35秒（进程46.124秒），115/186使用已证绑定，14保留原入口，prepared IDs仍为14/115/186。实际Metal截图确认粉紫覆盖消失、日期/时间/公式及暗模型保留；远离文字/模型的固定背景ROI平均亮度169.925→1.357。首帧、连续截图、退出GPU排空通过；一次既有115 scale badReturn及星轨缺失仍在，整样本、全208样本正确率和性能未验收。最终受限证据存本机`rf05-model-material-keys-20261004`；无效官方黑截图及私有payload/raw日志不入包。

反例覆盖精确大小写/拼写、声明和宏歧义、跨stage冲突、非法原值、属性与动态consumer、旧emissive及未知接口退路。最终10项CPU门通过（67.392秒），相邻绘制/属性/输入26项与source-set登记11项通过。结构普查保留既有shape-derived-analyzer 66/登记65两项失败；本批新增文件的目录登记及归档链接另行修正，不上调该库存基线。

四个既有独立harness补接真实DTO与显式unavailable编译边界，共享一个fixture，不把完整shader依赖带入Timeline/Text/display测试；40项相邻CPU及15项Text Metal门通过。触及的Timeline target测试原超1000行，原214行Swift harness按字节不变移到实际Swift fixture，Python回到890行。


<a id="rf05-model-culling"></a>
### 静态模型逐材质段剔除状态（2026-10-04）

基线`51851169`。347模型115材质明确nocull，颜色及阴影encoder却固定back；隐藏图片93的scroll另被现模型named准入拒绝。原包只改115 texture0为同一原始0mxx2的对照仍无星轨，纯白纹理控制同样不可见，而独立平面显示该TEX星图，分离了几何与provider两个断点。

修复复用既有Cull词汇，在逐段准备时将nocull映射为Metal.none，normal/缺省/未知保留旧back；状态随原SceneStaticModelMaterial及两个动态复制方法传递，color/shadow编码共用，CCW及原输出/资源/时钟owner不变。未扩展其它绕序或未知状态语义，也未改shader算法。

冻结候选Debug通过且1085份产品源码无漂移。同一direct-TEX输入35秒回放从无星纹变为可见放射状星轨；只证明cull修复，不冒充作者scroll效果或相位parity。原包35秒回放仍缺星轨、一次scale badReturn保留，14/115/186及文字仍在，两次退出GPU排空。后继必须把effectful provider纳入现graph准备、publication及消费者，不能移除准入guard后以raw capture代替效果输出。

自有八材质段真实App对照覆盖正反绕序、nocull规范化、normal/缺省/未知、同模型混合状态及独立健康邻居。旧App反面颜色与阴影均失败，候选三场景全部通过；两帧像素稳定、输入/App身份不变且GPU排空。真实reader与动态复制CPU门通过；该证据不外推整个样本或官方阴影parity。


<a id="rf05-model-graph-albedo"></a>
### 隐藏特效图输出进入静态模型颜色与阴影（2026-10-04）

基线`6d446683`。上一批已修nocull，但未改347原包仍缺星轨：模型named输入只接受source-only，隐藏93的scroll未进入模型115。现将已准入、顺序独立的隐藏image/solid图纳入既有准备闭包、帧需求、前置执行和publication；模型读取完整premultiplied颜色输出，颜色/阴影消费同帧纹理。两个入口共用原target pool及reservation校验，不伪造effect slot、不以raw capture替代特效、不增加输出或时钟owner。稳定范围见[架构合同](../architecture/runtime-architecture.md#model-effectful-named-output)。

独立审查发现无材质资源模型可能激活未执行的provider事务，进而阻断后续健康图。已用visible与prepared named模型交集决定需求，memo包含prepared集合；合法MDL/link但非法材质的实际App按model→healthy graph→provider作者序验证局部拒绝，健康图继续经历明暗和透明三阶段。typed data可合法发布但不能作为模型albedo，资源预算失败只降级当前依赖；native证明释放预算后可恢复，并另验跨epoch清理。

最终新增8门通过（86.460秒）：真实plan、Runtime/Metal publication和实际App覆盖provider前后顺序、动态颜色/alpha与阴影、source-only、显隐恢复、双模型共享、同帧只复制一次、变尺寸/epoch清理、分配失败恢复及无资源模型反例。有效旧App同输入的模型仍是背景85，候选跟随独立witness的green50/100及透明背景85，能区分raw source绿色200与graph-final。早期helper被deep adhoc覆盖导致签名无效，以及P1夹具字段误拼的运行均不计验收；最终使用符合产品Team检查的helper，未放松产品签名策略。

最终V3 Debug冻结1085份产品源码无漂移；未改347原包播放35秒，进程47.254秒，93图输出与115绑定均成功。root实看两张不同时间的Metal截图，放射星轨已恢复并随场景变化，日期/时钟/公式及暗背景保留，退出GPU排空、输入/App身份不变。一次既有scale badReturn仍在，不据单条首帧日志判持续失败，也不宣称整个样本、官方像素或全208样本正确性验收。

相邻graph-output runtime八门通过；结构门仅保留既有shape-derived-analyzer 66/登记65两项失败，未抬基线。独立终审及有限证据归本机`rf05-model-graph-albedo-20261004`（14天、单包32MiB内）。临时App/副本/HOME收尾后清理，只保留后续候选App和一份构建缓存。下一批优先复验3509243656的连续播放、文字及交互，以新的公共断点修复扩展真实覆盖；376斜光仍为未解。15/16卡只是有界卡口径，全样本正确率未知，长期Goal继续开放。


<a id="rf05-text-outline-shadow"></a>
### 文字描边与投影实施决定（2026-10-04）

当前真实声明有outline/outlinethickness/outlinecolor与dropshadow/offset/size/opacity/color，现TextDescriptor和共同光栅器均未消费。沿既有descriptor保留typed样式，静态load和动态text/font/pointSize/color更新共用原TextTextureLoader；纹理、尺寸、generation及最终compositor继续由现owner负责，不新增渲染器、逐帧解析或独立样式缓存。`msdf=true`不能成为拒绝样式的条件；独立栅格算法不冒充官方MSDF实现，spacing等独立缺口不算本片已完成。

描边厚度单位、内外扩展与投影偏移方向/模糊范围先用同字体、自有文字的官方黑盒决定，再实施数值映射；关闭、描边厚度为零或投影opacity为零保留原像素及几何。轮廓与投影只作用字形，不给整个不透明背景投影；光栅缩放必须同步样式尺寸，既有padding、对齐、换行与pivot不漂移。非法样式数值局部停用该装饰，不能丢整层文字；资源失败沿原纹理publication保旧值。新增字体算法或扩大逐帧职责均须重新评估。

验收同时包括真实声明读取、自有官方正控制/单变量、旧App反例、静态与动态同内容像素恒等、字号/字体变化后样式保留、alpha/边缘/最大纹理缩放，以及未修改原包的最终画面。Debug、邻近文字门、独立审查及身份冻结通过后收口，不能用一张有描边的图代替全部文字或全样本兼容；实施前决定不等于运行验收。

**边界补充决定。** tight自有O的官方可见投影超出glyph框，原candidate在size1/padding0实测截边。装饰外边距由同一typed文字样式一次决定，纹理/logical extent对称扩展，原内容排版和opaque background仍限原盒；唯一layer transform把相同外边距加入原pivot inset，不能只扩纹理导致边对齐漂移。静态/动态/命名及普通effect仍消费原完整publication。非有限或超本地4096场景单位装饰预算只停当前装饰，不新增buffer owner；该预算不是官方支持上限。官方大offset的夹取范围仍待独立判别，不把自有宽偏移测试冒充官方幅度一致。


基线2966caca。先复验350原包60秒与11次live属性切换，未重现旧intro/undefined，拖动试次未进入正确窗口不计通过；随后按当前metadata选择四样本11处文字样式缺口。官方2.8.0.42自有输入确认描边4/8为场景单位、fill核心保留，投影含描边且正Y向下，size0/2/4同输出、6/12软尾增宽。fresh tight O的padding0/128目标ROI逐RGB相同；X尖角允许超过半径，故采用独立有界miter近似而非圆化，不宣称MSDF内部或边缘parity。大offset96/48实际约24/24的原因仍未知，留作后继裁决。

最终画布由共同光栅器对称扩展，原wrap/opaque盒不增长；publication携带新texture与logical extent，原transform补同一inset。独审发现cursor使用原作者size却被补inset的回归，已限定仅published size override补偿；原内容hit语义保持，不冒充解决旧动态文字命中尺寸问题。outline厚度预算4096，含miter margin可达12288，shadow margin预算4096；组合最大16384，物理纹理仍受2048上限。超预算样式局部停用。

冻结V4 Debug的1085份源码无漂移。两份未改原样本3806202923/3765760121各播放18秒，进程26.869/26.067秒；root实看最终Metal图及局部：红色日期恢复黑色描边，白色日期/时钟/星期恢复投影，字形与原场景保留。输入/App身份不变，退出GPU排空；380原有一次exception同基线保留，376无failure token。只证明这两份样本的文字视觉改善，完整交互/特效/官方画面及全208正确率仍未知。


最终自有91输入同fixture/harness对照：旧owner 12门47失败子例，candidate 12门全过（native39.768/42.421秒），证明装饰、tight正负投影、字号/字体更新、alpha、预算与pivot的实际像素。相邻row-limit 15门通过，文字几何/绑定/generation/script四模块及登记四模块通过。实际App九种水平×垂直对齐的同输入开/关对照均有outline/shadow，fill边界漂移≤1输出像素；首试loose夹具缺PKG未准备成功，已排除，正式两次PKG运行8秒左右且身份不变/GPU排空。结构门仍仅旧shape-derived-analyzer 66/65两项失败，未抬库存基线。

相邻pivot/anchor两模块通过；原pivot测试中只接受旧padding源码拼写的regex已退役，保留真实几何门并以本批glyph/published extent及App九对齐对照补足行为证据。设计临时gate随实施闭合退役，稳定owner与能力边界接管。

<a id="rf05-text-padding"></a>
### 文字留白与内容尺寸（2026-10-05）

局部纠偏卡：官方同输入padding 0→32使背景四边各增长32，left/top与right/bottom字形边界不动；现有raster却取半值，pivot取全值。修复共同文字测量/光栅入口，使每边padding及装饰inset各消费一次；宽度限制与保存size另用同输入对照裁决，不让留白挤成1像素内容框。继续由原texture/extent/generation发布与唯一compositor消费，不改作者hitbox，不新增owner。验收为真实像素位置/边界、动态换字与maxWidth、描边投影/降采样邻门及App代表画面；官方未测部分不记parity。

基线b78735bc。官方2.8.0.42、1024×768自有HO输入确认padding32使四边各增32，left/top、right/bottom及未遮挡center H字形不动；center O被后层遮挡排除。限定宽度size1/264的最终截图失败，不记精确官方结果；大shadow offset未测。本地207份可读scene.json中103份、918处文字有非零padding，这只是声明影响面，不是样本通过数。

共同owner改为一次准备裁行、测量及wrap宽度，初始/更新均不受保存size裁剪；每边padding和装饰inset各计一次。绘制消费同一准备结果，删除第二次裁行与宽度推导。内容测量约束16384，加入留白后logical extent可更大，物理纹理仍≤2048；非有限extent局部拒绝，动态失败保旧texture/extent，作者hitbox语义未改。

同一34输入/harness：旧版6门74失败子例；初版仅超长文本1失败，因绘制用取整内容宽重新换行导致第三行裁切。修订版6门全过，长文本padding0/64均两行，logical16361×303/16489×431降采样到2048宽后字形世界边界差<1。该反例使准备与绘制约束真正闭合，不用放宽像素门掩盖裁切。

V2 Debug冻结1085份源码无漂移。实际App自有九对齐同输入padding0/32对照：旧最大glyph漂移38输出像素，修订后0；背景每边扩75/76输出像素，符合32场景单位。两次候选进程9.468/8.176秒，输入/App身份不变且GPU排空。真实3807151772副本播放18秒、进程35.130秒，无失败token且退出排空；root实看文字与场景，原有时钟横向裁切仍在，时间内容不同不作同glyph黄金对照，整样本/交互/全部特效仍未验收。

相邻描边/投影12门和行数限制15门通过；旧saved-size强制cap夹具改用真实长文本触发2048。scaled O半径对照以额外padding匹配装饰后的实际extent/栅格，保留原1.25物理像素容差、fill/孔洞和错误physical4反例区分；首次不同pixel grid失败已留解释。几何5门、绑定/generation/script/pivot/anchor五模块35门及登记四模块151门通过。结构13门仍只原shape-derived-analyzer 66/65两项失败，未抬基线；构建/上述局部运行不证明208完整正确率，后继转vortex_v2官方最小轨迹与既有模拟器接入。


<a id="rf05-text-shadow-offset"></a>
### 文字正向投影偏移纠偏（2026-10-05）

实施前决定：固定官方自有输入已观察32/64磅正向偏移分别在约25/50场景单位饱和，各轴独立，msdf布尔不改变此结果；负大偏移出现不同截片，不能推为对称限幅。独立小字号输入补证1磅放大10倍后正向位移约8像素，8/16磅及Consolas16保持字号相关上限方向；采用本项目经验映射min(rawAxis, pointSize×25/32)，不是官方公式。沿原共同光栅器，在替换后的live字号下规范正向offset，再乘一次raster scale；原raw offset留白预算、published extent、pivot、generation及compositor不变。此保守留白避免引入动态装饰尺寸owner，但不声称消除大留白导致的降采样成本；负偏移保留现项目行为，不仿制未解释的碎片。非法样式和资源失败沿旧局部降级。验收用旧owner同输入反例、实际像素位移、动态字号、降采样、描边与锚点邻门、真实声明样本及冻结App；全部通过后退役窄设计登记，不外推阴影kernel或全样本parity。


基线11b2fbe2。208份入口只读解析发现7处shadow声明，均为4,4，其中3747492842:59字号1；临时统计遗漏gifscene.pkg已修正，正式读取器本来支持。官方两份自有矩阵支持上述正向经验响应；msdf布尔不改变16对tile结果。Arial/Consolas字体差异、小字号完整kernel及大负偏移仍不记parity。380时钟横向截断另证为none anchor配合cover的视口裁切，本批未误改文字布局。

旧owner同fixture的13门有4个失败子例；候选13门通过，包含小字号、低偏移、混合正负轴、动态字号和真实降采样；相邻文字/留白/行数/脚本/pivot/anchor 46门通过。冻结Debug 1085份源码无漂移。实际App四格同输入对照中32磅位移96/48→25.01/25.00，64磅96/96→50.00/50.00；降采样约95.48/95.46→50.17/50.15，glyph通道逐像素未改。1磅放大对照约4→1，仍受低分辨率光栅和模糊量化影响，不记官方0.75的精确等价。一次与native重叠的App试次被终止、排除并单独重跑；不作性能结论。

未改3747492842副本播放18秒、进程33.954秒，原纹理/文字/特效链继续呈现，输入/App身份不变且退出GPU排空；真实画面的微小shadow差异未单独量化，不计整样本修复。59实际使用stock Alcubierre，日志stockSubstituted标签不代表字形已换成其它字体；173 effect speed脚本在scalar value上调用.add，旧/新App均复现一次，属作者类型错误，不伪造Number.add。装饰留白、small-font kernel、动态文字hit语义及208完整正确率均未闭合。最终身份、正反像素与审查材料限量保留在`.artifacts/scene-evidence/runs/text-shadow-offset-20261005/final/samples/1/runtime_evidence.zip`。


<a id="rf05-image-material-alpha"></a>
### 普通图片材质 Alpha 属性接线（2026-10-05）

实施前决定：真实1937925563的一份genericimage2材料被12个可见image层复用，公开stock的g_UserAlpha声明material键Alpha，作者绑定visualizer_transparency；现图片属性编译仅接emissivebrightness，源像素未消费材质Alpha。复用既有base material准备结果和materialConstant身份，限定公开内建genericimage/genericimage2单pass的精确Alpha静态值或{user,value} scalar wrapper；不为其他shader造键别名。instance的同键覆盖优先，冲突动态源、不合法数值、未知wrapper不准入该项，其他图层照常。

现property Program拥有值与事务，prepared base material映射拥有每层consumer，现draw request携带同帧sourceMaterialAlpha；普通直出、graph源采集及局部source passthrough共用source fragment uniforms，在premultiplied源上乘一次材质alpha，保留layer alpha独立作用与唯一final compositor，不另建时钟/纹理/发布owner。main-target capture不重复施加。选择该链而非修改layer.alpha，以保留材质→effects的作者顺序和脚本层alpha职责。普通帧只读prepared映射/typed snapshot。

验收：旧App同输入启动0与热切0→1→0失败反例；新App重复切换、material .5×layer .5、半透明输入及改写alpha的后续特效区分source/final次序；无关绿色peer保持。CPU门覆盖真实磁盘builder→唯一targets→原子事务及instance优先/非法wrapper/其他shader负例。冻结Debug、真实193固定PCM隔离运行、GPU排空与独立审查；不把12层恢复或声明规模记作整样本/官方全像素通过。验收后记录结果并退役窄设计登记。

基线39409e65。旧App同自有输入三次更新全部拒绝，材料Alpha静态.5与instance.25均未消费。最终V2冻结1085份产品源无漂移，Debug及deep strict签名验证通过，dylib `9b935913baaf3ffb44e46fdc85e14aad2ad91c85451100abba850430cc38a89a`。自有App0→1→.5→0全部接受：蓝背景上源ROI分别[0,0,255]/[255,255,255]/[128,128,255]；材料.5×层.5和半透明PNG×材料.5均[64,64,255]。后继dim effect在.5时[64,64,191]，opaque红色effect在材料0时仍[255,0,0]，区分源顺序与错误final乘法；绿色peer不变。两个effect均真实materialNodes=1，无失败路径，GPU排空、App/输入不漂移。首次自有c.a取色shader因现颜色合同拒绝且ROI曾误用fit，该尝试排除；最终fixture改用已准入常量红输出与dim两路，并按实际cover坐标量测。

独立早审发现旧numericComponents会将“0.5 junk”压成单数值；4门中2失败的红例固定后，在Alpha准入重证完整raw token，未改全局parser。4个本批native方法、5个emission、16个live-property、1个provider和32个相邻方法通过；provider旧stub缺两个旧字段和本次rawValue字段已补齐，报告新增两计数同步预期。13个结构门仍仅原analyzer66/65两项失败，未抬基线；其它职责/设计/文档/断言/资源门通过。

真实1937925563原包只读副本、固定PCM、同一0→.25→1序列：基线三次拒绝，V2三次接受且保持同window/session；实际画面两侧音频条在.25透出背景、1恢复不透明。两版各播放18秒，最终V2进程43.057秒且GPU排空，原媒体hash无漂移；不同时间音频/粒子相位不作逐像素parity或性能比较。12层材料声明复用不等于12个样本验收，208整样本正确率仍未知。

最终本机证据包 `.artifacts/scene-evidence/runs/image-material-alpha-20261005/final/samples/1/runtime_evidence.zip`，SHA `2dcc75840a2481fe5a7cf322d2c475772364994314b6863307ded7ad743b2aa1`；限定14日保存。下一批转293文件纹理连续替换的未验操作，不重复已验八背景/模糊；同语料没有BC5或已关联builtin非默认Brightness，不扩无收益分支。


<a id="rf05-texture-picker"></a>
### 文件纹理选图入口恢复（2026-10-05）

基线19344b01。真实2938612768的newproperty25由775的effect pass usertextures[1]消费，但scenePropertyContext只收集user wrapper/scalar绑定，遗漏裸纹理键，导致文件选择控件未进入actionableDefinitions。修复在原属性服务收集typed effect pass的合法0…7槽property引用并与scenetexture声明相交；base复用原BaseMaterialProviderBindingCompiler准入结果，保留exact slot-0、single-pass、instance优先及fallback合同。不直接开放全部声明，不新增解析、纹理、graph或输出owner。effect材料内部的独立usertextures声明未扩入本片。

文件选择仍经原PNG/JPEG picker、bookmark和180ms合并Host重载；不是scalar热切，也不重启App。真实隔离原包加两张自有红/蓝PNG、固定PCM和媒体关闭状态，用同record的Host候选替换检验下游：旧/新App都将封面从红[255,0,0]换成蓝[0,0,255]，白标记保持[255,255,255]，圆角与其它图层继续合成。故本批新增收益是恢复普通面板入口，不宣称新造纹理合成能力。Debug runner跳过picker/bookmark交互；UI入口由实际context行为回归约束，不声称完成文件对话框/跨重启授权实测。

最终Debug冻结1085份产品源无漂移，deep strict签名通过，dylib SHA 3382a3641636bb16a81156cc00597be3ba818d99d3adff7a59d2001436555551。两版各播放60秒，候选进程89.431秒；同Host切换accepted且surface维持1，结束为0、gpuDrained=true。真实媒体hash无漂移；动态背景/音频不同相位不作像素parity或性能对比。首次24秒试次在第二次资源准备结束前正常关闭，排除切换验收，不记产品失败。

实际sourceFacts→完整属性服务→actionableDefinitions的4个native方法在旧Service为3失败/1通过，合法effect/base消费者均漏入；候选连同既有门共18通过。纹理加载18项、base与live状态17项通过；13个结构门仍为既有analyzer 66/65的两项失败，其余职责/设计/文档门通过，未放宽结构基线。独立只读审查核对入口、同源码App与红蓝图；最终冻结身份由证据包manifest保存。

证据限量保存于`.artifacts/scene-evidence/runs/texture-picker-20261005/final/samples/1/runtime_evidence.zip`（14日）；仅留必要日志、两张截图、源码/输入身份和自有图片，不复制真实包。208整样本正确率仍未知，RF05未完成。下一批检查普通产品文件选择、reset及失效bookmark后的恢复，或发现更早的真实合成断点后重排，不重复已证红蓝渲染路径。


<a id="rf05-texture-selection-failure"></a>
### 损坏选图保留原选择（2026-10-05）

基线e51f1fe4的文件入口仅检查扩展名、存在性和bookmark。自有9字节broken.png实际是regular/public.png，旧Service仍接受并覆盖健康bookmark/override，180ms后把坏URL传给重载；这不是目录选择器反例。现入口在任何持久化之前打开security scope，确认regular file并调用运行时同一个SceneImageTextureUploader.decodeSourceImage，失败保留旧bookmark字节、属性和场景，不请求重载；nil恢复默认沿原链。此检查不保证之后GPU分配或外部改写后的文件仍有效。

用户本轮已亲自确认普通UI能选择背景与播放器封面，同时指出每次整Scene重建很慢。本修复只防坏图覆盖，不宣称改善换图性能：Debug/Onone自有4096² PNG一次完整选择校验187.355ms，仍在主线程；下一批把校验合入异步纹理资源准备，消除同步重复decode和不必要的全场景重建，保留Scene/script/clock，失败保留旧图。

真实Service、共享decoder、bookmark、180ms debounce、请求通知与daemon引用解析的候选22门通过；旧版同4个新方法暴露3个独立失败（坏PNG、CRC坏PNG、目录误接受），目录仅为service反例，普通面板禁止选择目录。Debug冻结1085份产品源无漂移，deep strict签名通过，dylib `30c8e2df2537e771ba0282b5d4c3c627d66b098f1aeda0e69ac2b7da6763ed51`。本批未重新测GPU画面或复杂/更大文件耗时；用户UI验证的是前批入口，不冒充本候选坏图端到端验收。独立只读终审核对失败原子性与回归链；本机证据`.artifacts/scene-evidence/runs/texture-selection-failure-20261005/final/samples/1/runtime_evidence.zip`限量14日。
