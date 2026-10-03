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
