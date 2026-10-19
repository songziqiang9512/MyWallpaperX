<!-- document-role: active-plan -->
# 多段材质链的输入尺寸与终端显示

目标：修正普通 solid 特效把屏幕尺寸当作源纹理尺寸造成的重复采样，同时保留末尾效果停用时前一有效材质的屏幕细节。沿用唯一 graph、Program、pool、submission 与 MainPass，不增加样本分支或第二输出链。

## 行为与范围

官方 2.8.0.42 自有实验（2026-10-11）确认：120×60 solid 经 identity 后，下一段 g_Texture0Resolution.xy/zw 仍为 120×60，不随世界缩放及窗口尺寸改变；10×10 solid 生成64周期条纹，末段 identity 停用时为屏幕密度，启用时经历小尺寸中间采样。固定输入、二进制和像素测量保存在 `.artifacts/tmp/effect-texture-extent-20261011/`，失败探针不作为合同。真实纹理替换的尺寸比例问题是该能力的消费者，不是准入键。

首批限定可见、非 provider 的简单 color 链、普通 source-over、target-pixel 顶点、无 FBO/history/function/compose/几何网格；保留现高级混合职责。2026-10-12 补充：普通正交文字的单 stage 链复用同一证明与 terminal receipt，保留文字源尺寸、padding、pivot 和动态纹理 generation；作者顶点越过原矩形时直接进入既有 MainPass，不先采已裁的 graph-final。文字高级混合、透视及跨图输出暂不扩域。先验证无外部依赖，再依据同一资源生命周期合同接入已准入的外部只读输入。未验证的跨图 provider 与复杂图保持原路径。

## 外部只读输入扩域（2026-10-12）

已证首错是consumer工作纹理使用placement放大尺寸，named provider和Resolution编码已传递真实资源尺寸；不修改作者shader、采样器或uniform数值。扩展同一prepared资格，使原依赖owner已准入的精确externalPrimary在可见、非provider、简单color链及target-pixel顶点证明成立时使用同一源尺寸/terminal链；保留`!requiresGraphOutputProvider`：本片不要求provider graph output；binding仍由原owner准入，不能直接删除全部dependency守卫。外部text、透视solid、高级混合、aggregate、同层/secondary、几何placement特殊合同与复杂图不据此扩大。

原FrameInputs依赖证据、PreparedLedger与GPU submission共同保留provider/slot/epoch/object/content及实际texture；terminal replay只消费已经验证并编码的同帧资源，冻结Program输入不再解析/捕获。最终消费仍通过唯一ticket、MainPass和completion pin，不能为named输入新增尺寸表、资源缓存或输出入口。真实写后读冲突继续原输入副本机制；普通缺图沿原局部passthrough；陈旧/被覆盖资源拒绝当前不安全单元，不能回放旧帧。

验收补充：尺寸不同的named provider与consumer、scale/viewport改变、末段active/inactive/失败、多段覆盖保留、错误provider/slot/epoch/object/content、同buffer/重复消费、取消与完成前pin。官方named实验须先通过内容正控；历史失败探针不作数值合同。原始376截图必须实际减少矩形重复，保留头部deformer独立缺口及其他样本回归，不以效果节点执行成功代替画面收益。

## 职责与数据流

1. Capability 用已有 prepared graph/material/variant 事实证明所有可能成为终端的材质；纯停用或局部失败阶段可透传，不独立发明材质。
2. FramePreflight 使用真实静态源 mapped extent；无静态源的程序化 solid 使用作者尺寸。Resolution uniform 始终来自真实资源 descriptor，不伪造 Candidate 或修改 shader 数学。
3. GraphExecutor 仍准备和执行完整小尺寸 graph。最后成功 active material 的冻结 Program 通过现 PassEncoder 派生 terminal pass；后续透传不抹掉它。
4. 若后续阶段会覆盖该 pass 所读的 pair 输入，现 pool 按层及纹理槽保留同 descriptor 的临时副本，现 resource encoder 在该阶段完成后、覆盖前追加一次精确 copy。PassEncoder 仅将相同 descriptor 的物理绑定换为副本，采样器、uniform、Program 和 epoch 不变。无覆盖不用副本，无成功材质不用 replay。不得每段复制或新增 registry publication。
5. 副本 pin 由 PreparedGraph 随原 submission ledger 保持至 GPU completion；未编码失败立即释放，编码后取消沿现 ledger terminalizer。无独立生命周期 owner。最终仍由同一 MainPass 在原层顺序消费一次 terminal receipt。

## 取舍、失败与退出

仅缩小所有 RT 会破坏停用尾段的细线；伪造 resolution 会破坏物理资源合同；只回放最后声明阶段会丢失最后有效阶段。这三种捷径不采用。副本只在真实写后读冲突时出现，代价是一张源尺寸纹理和一次拷贝。副本分配或准备失败不得回放被覆盖输入，可局部使用真实 graph 输出（细节降级），不得丢帧或读取陈旧句柄。未知图不扩大准入；新设计没有新的 renderer、clock、资源注册表或提交器。通过后删除单 stage 限制，未证明复杂图继续保留现受限路线。

## 验收

真实 GPU 正反例：末段 active / inactive / 局部失败，细线密度、精确输入颜色、一次必要 copy、无冲突零 copy、同 buffer / stale / one-shot 守恒与完成前 pin。文字补充正负倾斜越界像素、identity 与 alpha、动态日期/时间末字边缘，停用回原 graph 路线。Debug build；原生同一官方自有尺寸及条纹输入对照；原始真实样本短跑与截图。外部依赖、全样本、桌面产品入口、长期性能不得由这些门代替。实现结果与剩余边界归现有队列；完成过程归档，稳定职责归运行架构。

<a id="procedural-solid-local-source"></a>

## 无静态纹理的程序化 solid 源域（2026-10-18，有界已实施）

目标是让局部 effect 的采样域独立于最终放置，关闭固定路径被显示比例带动旋转的问题。新片限定原 capturedLayer 的普通正交可见 solid、无真实 texture Candidate、显式合法作者尺寸；须同时满足现 prepared source-sized simple color claim、dependency.none、非 graph-output provider、无显式 RT/history/function/copy/swap/compose。上述资格在原准备/计划 owner 确定一次，draw/scratch 消费同一选择，不能仅据 layer 类型与 nil Candidate 各自判定。复用原 `SceneLayerEffectSourceExtent.resolveSolid` 作为作者源尺寸权威，graph preflight、draw request 和 scratch reservation 消费同一结果。现投影 AABB 两轴分别取大污染了局部宽高比，该分支退出；不另造密度算法或尺寸缓存。作者尺寸缺席时保原投影 fallback，显式非法在预留前局部拒绝，不能降级绕过；新早分支保原正尺寸资格；0→1像素仍留原 fallback/resolveSolid 边界，不扩大该早分支。真实 Candidate、精确 atlas、native/perspective、外部 provider 与显式 FBO 保各自原来源和资源门。

高级混合除[模式31终端后继](#additive-terminal-density)外仍按完整 graph-final → 原 compositor 输出；不伪造 Candidate 或 `g_TextureNResolution`。graph publication 继续以真实 descriptor 和实际 UV 发布 physical/mapped；固定作者源域经原等比预算处理，最终 canonical world/MVP 独占显示的 scale/angle。保旧普通 source-over、局部失败/停用末段、graph/history/resize、取消与 completion pin；若需新的 logical/physical 类型、采样质量策略或跨图来源，停在相应合同，不借本片改 metadata 含义。

最低验收：自有局部圆与沿环标记，静态非等比外部放置，多个时间点的主轴/轴比保持而标记继续移动；改名及等价变体、viewport/世界scale变化、合法矩形源和缺席/非法尺寸反例。沿实际 preflight→graph descriptor→uniform→GPU→末合成验证，不能只断言helper或冻结clock。原380受控静音多相位对照用户固定路径观察，再用未参与修法的真实样本检查输出/退出；一次有效Debug及独审。不承诺全样本、精确官方音频/相位或性能收益，成本变化另遵循性能卡。

实际原包静音三相位、非零PCM与独立样本后验归[运行证据](../../capabilities/runtime-evidence-current.md#procedural-solid-local-source-20261018)；只关闭固定路径自转反馈，不认完整官方相位/速度、音频幅度或性能通过。

<a id="background-terminal-density"></a>

## 无成员背景采集的终端密度（2026-10-19，有界实现）

目标是避免把巨大屏外画布压到工作纹理后放大。原型只按屏幕密度重放末材质，实际284仅末弧清楚，后继背景capture仍低清先前弧，已撤回；必要证据 `../../../../.artifacts/scene-evidence/runs/arc-density-qualification-20261019/current/report.json`保留，不从单pass或回执计数认三弧修好。

后继沿现 Compiler/ArtifactBuilder→Program→pool/GraphExecutor→唯一MainPass保住背景与新细节。共享SyntaxUnit/binding facts证明canonical quad仅经原MVP、原UV的xy无改写、slot0全部普通2D采样读取原xy；改名、括号与恒等向量构造不改变资格。未知坐标/offset/LOD/helper传递/条件改写/vertex warp拒绝可选入口；targetPixels及prefix-link不能替代证明。先限单个resolved color stage、无成员capturedMain、普通正交、无provider/依赖/显式FBO、最终alpha=1及原完整输出合同；slot0精确ingress复用现capturedMainTargetSourceSlot，不以node.bindings遗漏合法材质alias。不能用当前背景偷换前序active效果，未准入的多段链保原图。

选择在现ArtifactBuilder完成普通MSL、反射、uniform布局和颜色lowering后结构化派生可选完整terminal MSL：精确反射binding0→fragment entry参数，inventory其全部使用，仅允许entry内普通两参数sample，以避冲突的color(0)参数替换完整sample子表达式；外围输入/输出颜色转换及作者运算逐字保留。复用现token/call边界，不以作者源码或生成函数形状匹配算法。未知helper/alias/其他method/参数/资源使用令变体缺席，普通artifact不变。另编GLSL subpass会增加link/反射并重复颜色边界，SPIR-V改写需新工具依赖，均不作为本片路径。

同一artifact/frontend/Program携带版本化proof、可选source SHA/入口与物理texture槽；普通逻辑slot0/Resolution仍来自真实graph descriptor，terminal仅省texture0，保其它槽共享的sampler0及原资源pin。遵循既有build producer identity，同producer请求只给合资格源追加能力版本；变体源计入原缓存预算，PSO/archive均区分变体SHA。launch按实际资格预热，普通帧不分析或编译。现CaptureGeometry比较sourceUV与经实际enclosing-pass raster变换的outputMVP：有限且w恒定非零，四角误差每轴不超1/16目标像素，不随屏外坐标放宽。坐标/目标/PSO不支持保原graph-final；typed role/ticket核对一次消费、当前目标及completion pin，仍用原颜色表示的混合合同。不直接采样正在写的纹理、不放宽framebufferOnly、不增输出owner。

先以自有非平凡alpha背景及连续三draw实际验证BGRA8/RGBA16Float attachment读取、普通冻结texture反例；本机signed cross的MSL2.0拒fetch、2.3才产生color(0)，不能声称原后端版本无条件支持。随后验共享proof改名/等价及邻反例、ordinary artifact不变、颜色转换一次、物理绑定/映射拒绝、停用/失败/stale/重复消费，再用原284三弧与独立样本实际出图。可选能力失败只保原图；如任一前弧再次低清，撤回route，不以末弧或回执计数结案。保2048预算、原uniform及UV，不伪造Candidate/Resolution、不偷换不同extent副本；未覆盖组合及整体性能仍开放。

<a id="additive-terminal-density"></a>

## 加法终端密度（2026-10-19，有界实现）

当前 source-sized 程序化 solid 的高级混合会将小 graph-final 放大，最后一遍连续细线也丢失。先限定项目已有模式31的通用合同 `background + straightSource * alpha`：源为 PMA 时 RGB 系数 one，为 straight 时 sourceAlpha，目标 RGB 系数 one；alpha 保背景值。该模式可由 Metal 固定混合直接消费既有 terminal Program，不需要 framebuffer fetch、另建 scratch、提高全图预算或改作者 shader。其他模式不从此开放。

沿原 capability 的 simple color、全终端变体 target-pixel 及输入保存证明；仅普通正交可见 solid、无依赖/provider/geometry、合法原源尺寸和现有最终覆盖资格。FramePreflight 通过原 frame request 传递模式，GraphExecutor/PassEncoder 派生 typed 加法 pass role，role 进入既有 cache key 和 launch warmup；ordinary frame 不编译。Compositor 与原 submission ticket 同时核对外层模式和 pass role，再在原 MainPass 原层序恰好消费一次；中间 extent/Resolution/UV、activation、失败后前一成功材质与 completion pin 均保持。准备不支持时保真实 graph-final，不能把已消耗的 ticket 再走另一输出。元数据记录实际 blend 资格，避免为所有普通层预热无用加法 PSO。

验收复用连续细线/非平凡源：同 Program 源 extent 不变、实际加法输出细节、straight/PMA/opaque 与背景非1 alpha，以及同 pixel 普通混合相邻反例；末段停用/失败、被覆盖输入、stale/重复消费、改名及等价表达式。GPU 门与 Debug 后，原293对照圆环重复亮段消除、人物/粒子保持，另验未参与修法的真实加法样本。透明边界、HDR/SDR、resize 与取消沿原约束；未覆盖组合保持开放。收益必须来自实际清晰度和可比开销，不从256²不变或通过测试推性能结论。

实际运行与剩余边界归[当前证据](../../capabilities/runtime-evidence-current.md#additive-terminal-density-20261019)；284三弧仍开放，不由293连续环或单pass回执代验。
