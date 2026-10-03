<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# RF13：当前 named albedo 模型参与方向光投影（2026-10-02）

> **历史证据 — 非现役入口**。设计前置提交 `bf73d0b1`，实际 lighting payload 需求补丁 `de72544b`。本机证据根 `/private/tmp/mwx-rf13/`。本片七产品与两个测试已获独立产品终审 **ACCEPT RF13 v4**；稳定职责移交[架构](../architecture/runtime-architecture.md)，后继只由[兼容路线](../roadmap/scene-compatibility-roadmap.md)排序。

同页历史分节：[已退役设计裁决](#rf13-retired-design)。

## 用户结果与职责

已准入的 hidden image/solid source-only named albedo 模型，在冷帧也使用当前帧实际纹理、geometry、world 与原 coverage 参与方向光 caster/receiver。此前模型颜色能绘制，但 shadow 准备早于 named publication，而且 caster 还要求静态 albedo 存在；较晚绑定因此无影。未扩 named provider 准入，没有新增 shader、pool、registry 或 compositor。

现 frame owner 保持原完整 forward 一次执行，按原作者资源次序准备 mandatory 资源：source-only 当前捕获、真实模型/粒子 depth、实际 plain scratch、各消费者/utility 快照，最后 Bloom/display 容量，再申请 optional shadow。普通读取背景的 provider 仅提前容量，内容仍在原作者位置复制。相同 epoch 的成功捕获复用原 registry；named 尚未确定时不写空 prepared 数组、不推进 depth plan。失败保留原资源前缀；已尝试失败的 depth 与未访问 mesh 分开，后缀沿原循环继续。无法确定完整 caster 时本帧可关闭阴影，健康颜色仍保留。

## 修前反例与实现纠偏

`baseline-zwnb1ivz` 的原 RF12 App 三输入证明：静态正控 shadow9，named 早/晚两例却85；三者 caster 绿95/control85，named capture/binding 均成功，App/输入不变且首帧、后帧和安全退出完成。协议 SHA `3346dca609aaffff7c42f6cc839424b49a4f5bf079e1ff219d75f03f5b50ea90`，索引 SHA `232ab6e454e952486365919876a28969efed85a11fd678053f159251fa32fa56`。这些为自有合法输入，不是官方像素 golden。

原池 native quota 探针显示，同样只容一份256² target，提前 named 可抢掉较早模型 depth；cancel 不退还缓存物理计费。由此选择完整 mandatory 原序准备，不能用 first-model-only 或 cache-only 规避冷帧及中间 provider。

独审又发现两个 phantom scratch 反例：reflection-only 缺 normal 时原 typed payload miss，本不需要 scratch；非法 colorBlendMode 由原 compositor 拒绝，也不需要 scratch。v1 实际 owner 反例均丢失较晚健康 depth；v4 复用原 payload resolution 和实际 blend supports 准入，恢复健康颜色，并缓存本帧真实 resolution 给原消费入口，避免重复 packLights。environment 闭包仍在原绘制点执行，沿原 F5 准入决定是否可用。

## 冻结身份与验证边界

七产品冻结清单 `implementation/checkpoint-v4-products.json` SHA `c5c963ab3952443a737090e3e2973fb1fc5a30f5c73d48b0b61972e681ba5b0c`；diff SHA `93d9f34f6030f1f1c5856b937d6490156c18cc1d51f3c6044a33ef0947f78bbf`。清单内 verification 字段是冻结时快照，后续实际验证以下述日志为准。完整 Debug 构建通过；不可变签名 App 为 `source-v4.app`，`build-v4/identity.json` 固定五项身份，其中 debug dylib SHA `20fea7ed26332d08c82c3c3ff6a1881bff2bf9c155f3813b33e6fa7cac0b55dd`。本机签名不是公开发布/公证验收。

`named-model-shadow-app-anw8z0bs`：3方法/5输入通过。旧静态、named早、named晚输入逐字节不变，新增中间 image 动态alpha和late solid。新 named shadow9、caster绿95/control85；中间alpha1→0→1时 named shadow9→85→9，而健康静态peer始终9；ready/after整图一致、frame1/2 completion与安全drain、shadow/current named publication/模型binding/terminal消费均可核。独审重算15张PNG，接受该有限App证据。运行测试源码副本为事后按prerun SHA重建匹配，不冒称预执行已保存副本。

forward 附加 App `named-model-shadow-app-hbf7izkb` 使用自有 `own_dim→own_sample` graph：provider31先于consumer50，前者不terminal、后者实际terminal，背景邻区绿100与named阴影9同时成立，frame0/1完成。首轮 `named-model-shadow-app-x2wq_wac` 的坐标fixture错误保留：image作者Y与model worldY方向不同；只改输入坐标，ROI位置/颜色/容差不变，不能把首轮写成产品失败或全绿。

最终测试索引 `test-final-v4.json` SHA `ce71050f4dd679672885d437b6990f0c41b73b6958bdd148c8ad7ff44eb98a56` 绑定两个测试文件、执行副本、全部日志与结果；root逐项复核84个显式文件身份。新测试 SHA `9af3bb8f8936ce593ec7c76e2228e914214b0802b9cec81a17b111779d4a7f00`，旧测试 SHA `d78fe2cdd7bc4b6d3f3a03a0330ea3f7af5cf75ca4af6fe526af5f9bec935722`。最终 native 11方法/23输入行通过（110.092s）；App共5方法/7唯一输入，分3+1+1三次执行，不称单次全量运行。

G3完整App `named-model-shadow-app-zipze1om`：原脚本在frame0将已准入consumer71隐藏，normal composition provider70仍在约3秒恢复前捕获；恢复后当前binding、graph、terminal与next-frame完成，消费区ready背景85→after绿95，原shadow9不变。实际preflight可见性过滤、此完整App相位与native无reservation owner共同约束该边界，不冒称每个隐藏帧的分配次数。native两独立composition provider进一步证明先blue后green的原位内容，重复首provider保留blue，容量阶段red没有被提前发布。

Native owner 门编译实际顺序准备、dependency capture、模型 draw、原 resource pools；prepared route/pose/group/frameplan壳必须与完整 renderer 区分。G1覆盖 cold/真实target resize、source失败后原位重试、同层多mesh ready/failed/unvisited；G2覆盖当前alpha、同epoch幂等、下一epoch恢复、两个cast=false named receiver共享provider且仍接收独立caster阴影，以及SharedEvent阻塞已提交A时B resize/取消后A完成，shadow resident最终归零。该强引用探针不证明named纹理最终析构。

G4 mixed覆盖真实color-blend、粒子depth/refraction、utility触发、原snapshot与Bloom消费者的8行：可选map拒绝保mandatory、中途失败保前缀、失败depth不重试、terminal Bloom容量失败后原encode继续。其activeNamedModels为空，named组合另由G1/App证明；terminal回调不等于完整coordinator/display scratch执行门。

原 FrameOwner3方法通过18.670s：仅适配新接口的未调用壳，原3方法断言不变。因root漏设证据父目录，原执行目录 `directional-shadow-frame-owner-4rtxdkd0` 精确镜像到 `legacy-frame-owner-v4-evidence`，逐文件SHA一致且所有编译源均匹配v4；不因路径重跑GPU。该模块只编译七个改动中的StaticModels。

原完整包3589454154使用已隔离副本运行8秒：exit0、App/输入身份不变、frame1完成、drain、22模型prepared，零shadow；`original-v4/protocol.json` 与 `summary.json`保存结果。仅作既有模型显示邻接，不宣称原包named阴影收益。

code-health通过（1055 Swift、0 locked legacy、8 locked review warnings、240 warnings）；scene-defense通过（0 locked dead、18 canonical、3 swallow），design-gate通过。没有改结构/防御预算。产品独审已接受上述冻结身份；移交时文档角色13方法通过，未放宽测试。

测试壳曾有直接CPU读取private纹理和unsupported控制的两个编译错误；分别改为同CB blit读回、修正重复声明与类型别名。未改产品或像素oracle，不把这些测试基础设施失败计作产品红例；现场与实际v1产品红例由最终索引分别登记。

## 未验范围与下一方向

不宣称官方parity、性能、多屏、App窗口resize、全部model格式、effectful named source、所有group/forward组合或其它光型已完成。native target resize与实际App分别证明各自范围。保留原失败现场，证据不纳入源码提交。

下一主片为真实模型聚光阴影：从cast意图进入唯一typed light到透视投影、当前资源与选中灯贡献闭环，采用本项目独立算法；全向point紧随，不能用单面图冒充。参考资料用于中性输入/生命周期/消费职责，缺私有方法不构成跳过理由。reader 22/24差额先具体归因，不能猜测放宽安全边界。

## 终审与提交边界

独立终审 **ACCEPT RF13 v4**，报告 `product-final-review-v4.md` SHA `36ea4d9a7df371e5a2c768f6b41c6e9ecacfdb7386f66089a5b1dcc2c81a41a8` 接受七产品、两个最终测试及上述有界证据，无剩余产品finding。稳定职责移交架构，[前置设计](rf13-named-model-shadow-implementation-2026-10-02.md#rf13-retired-design)归档并删除本片窄gate；D3整体仍持续实施。按职责窄提交，不包含并行layout排序；未推送。GPU/App执行已结束，唯一失败现场和精确证据根保留本机。

<a id="rf13-retired-design"></a>

## 已退役设计裁决

下文完整保留该阶段的历史裁决、证据身份和未验证边界；其中状态与后继顺序仅适用于原记录日期。

<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

<a id="rf13-retired-design--rf13-当前-named-albedo-模型参与方向光投影"></a>
### RF13 — 当前 named albedo 模型参与方向光投影

> **历史证据 — 非现役入口**。本文保留实施前裁决及当时验收待办；RF13 已完成有界产品验收，结果见[执行记录](rf13-named-model-shadow-implementation-2026-10-02.md)。稳定职责见[架构](../architecture/runtime-architecture.md)。

基线 `d5908b53`。承接[RF13工作卡](../roadmap/batch2/reference-evidence-implementation-cards.md#rf13-named-model-shadow)。**设计已批准，实施/运行验收尚未完成**；`scene-named-model-directional-shadow`登记为`approved`。本文不修改原named source准入或私有阴影算法。

<a id="rf13-retired-design--目标合同与当前事实"></a>
#### 目标合同与当前事实

已在原direct static-model主链合法显示的hidden image/solid source-only named albedo，与静态纹理模型使用同一个当前帧纹理、geometry、world、material/coverage及directional light形成阴影；同帧颜色和阴影不能借不同资源或前帧publication。冷启动和resize也是目标，不能把只命中缓存的帧作为完成条件。未支持的可见/effectful/有子层provider不借本片放开。

以下源码路径相对`MyWallpaperX/Core/SteamWorkshopScene/`，行号属于基线：

- `Rendering/Dependencies/SceneDependencyRenderPlan+StaticModel.swift:130–164`已限定hidden image/solid、无effect/dependency/children、primary slot0并记录forward需要。
- `Rendering/Frame/SceneMetalRenderer+StaticModels.swift:156–160`在named输入尚未发布时返回nil取消整帧shadow；`:253–254`即使ready仍要求entry静态albedo存在才投影。原颜色draw在`:79–92`能解析当前named albedo。
- `Rendering/Frame/SceneMetalRenderer.swift:323–348`在shadow之后准备forward providers，`:468`在作者循环捕获原provider。因此静态反例有真实调用路径，并非只有字段未连线。
- `Rendering/Dependencies/SceneDependencyFrameRuntime.swift:302–308,380–389`已有当前publication幂等；有reservation时先检查epoch/extent/texture身份，不应新增无条件complete快返。`:331–339`将mixed normal/static消费形状局部判unsupported；`:530–569`拥有原source-only capture与provider动态alpha/color。
- `Rendering/Frame/SceneMetalRenderer+TextureFrame.swift:37`开启原registry frame epoch；`SceneDependencyFrameRuntime+StaticModel.swift:79–109`裁决完整当前named publication，保premultiplied/frame/sampling身份。
- `Rendering/Dependencies/SceneNamedRenderTargetPool.swift:38–79`按provider缓存真实target；`Rendering/Particles/SceneParticleDepthTargetPool.swift:37–44,122–126`的cancel/completion只释放reserved标志，不能假称退还cache纹理或恢复旧槽。

真实修前证据：`/private/tmp/mwx-rf13/baseline-zwnb1ivz`三次不可变RF12 App运行。静态正控shadow9、caster绿95、control85；named早/晚两例caster与control相同、provider11 capture及model2 binding成功，但shadow85。三例exit0、App未变、frame1/2 completion与安全drain、ready/after整图一致。预运行protocol SHA `3346dca609aaffff7c42f6cc839424b49a4f5bf079e1ff219d75f03f5b50ea90`；索引SHA `232ab6e454e952486365919876a28969efed85a11fd678053f159251fa32fa56`。这是自有合法输入的真实缺影反例，不是官方parity或完整原包收益。

<a id="rf13-retired-design--参考证据的用途"></a>
#### 参考证据的用途

[Mirage参考](../development/reference/miragewallpaper-rendering-reference.md#64-rendergraph-的资源版本) §6.4将材质slot read、target write和linked source版本作为同一依赖图职责；§11.6区分隐藏但被采样的source私有写入与最终显示。这些`third-party-reference-pattern`中性信息支持当前帧producer先于consumer、隐藏不等于无资源的目标，不是官方精确调度或预算公式。其§8.4明确固定版本没有完整shadow atlas，不能复制不存在的实现来假闭合。本项目继续使用已经独立实现的F6投影，仅纠正准备/消费的缺边。

<a id="rf13-retired-design--owner方案与待裁决点"></a>
#### Owner、方案与待裁决点

唯一dependency capture/registry owns当前source-only publication；现frame owner组织资源次序，原StaticModelFrame与depth plan/pool owns mandatory lease；现model draw与shadow consumer共用resolved输入，最终输出owner不变。不新增provider、registry、clock、第二capture实现或另一套alpha解释。

只提前已由static-model plan准入、且本帧实际活跃模型需要的source-only职责。原forward preparation还执行effectful graph并可能触发首次环境reflection，不能未经相位与资源核验整体移动。旧named帧的forward本来就在首个主颜色draw前；若仍只执行一次并保持内部顺序/claim及首次reflection内容相位，而shadow只写独立depth，则forward先于shadow并非天然不合法。设计以实际主颜色内容与mandatory容量为判据，不为先前保护性假设另造raw prepass。提取重复raw capture参数计算时应替换现forward/作者循环两处，第三调用点复用同一owner；原loop先前执行的base selection/identity拒绝不能被helper吞掉。当前published沿原registry幂等复用，不另存captured集合。

named的premultiplied颜色身份沿原模型路径解读；投影只复用该draw既有alpha/opacity/tint-mask coverage，provider alpha不得重复应用，也不能影射新材质开关。

**预算顺序已有真实反例。** 把named target提前可能让它占掉作者较早模型的depth配额；optional shadow最后分配本身不足以证明原画面不受影响。本机Apple M4原NamedPool/DepthPool测试为两种256²纹理各实际264192 bytes，仅留一份配额时，旧depth→provider得到depth成功/provider失败，反序得到相反结果；cancel前后仍计264192，owner作用域退出后才归零。结果`/private/tmp/mwx-rf13/pool-probe/result.json`，原源码未改，无command buffer/encode，证明真实分配顺序风险但不冒称App回归。

<a id="rf13-retired-design--选型原owner按原资源次序准备原循环按原位置绘制"></a>
##### 选型：原owner按原资源次序准备，原循环按原位置绘制

选用完整作者序准备方案。首模型前才尝试阴影无法覆盖“较早健康模型→中间backward provider→较晚named模型”，cache-only无法覆盖冷启动/resize，均不作为本片交付。跨owner交易manager、复制恢复depth旧reserved快照、先encode后假称rollback也不选；GPU completion可合法改变在飞slot状态，原lease.cancel并不退还缓存容量。

1. **原前置阶段。** 保持原graph/FBO/effect named reservation与D1组target的准入。旧named-pending帧的`requiresShadow=false`判断不改成hasShadowReceiver，原reflection确需的F5批预留仍保留。原完整forward只执行一次，内部graph/claim及首次reflection内容相位不变；新shadow只写独立depth，不消费主帧前缀。
2. **原frame owner消费现prepared计划。** 在现StaticModelFrame mandatory准备职责中，按原orderedLayers与真实group pass访问原资源消费者，不在普通帧重新解析、建图或序列化。作者位置依次处理raw target、真实model/particle depth、plain scratch、该消费者snapshot、该位置utility触发的snapshot。跳过规则与原主循环一致，隐藏触发层的utility defer仍计入。
3. **内容与容量分开。** 已编译准入的static-only source capture可在准备阶段执行，复用原source/alpha/color/world与唯一registry。普通normal provider可能读取已绘制主帧，提前只准备实际target容量，不encode或publish。主颜色、背景复制、reflection内容与utility graph依旧原位执行；成功source-only捕获在旧调用点靠原epoch幂等返回，不能另建captured集合。
4. **真实depth准备一次消费一次。** 实际resolve成功的draw记录写入原StaticModelFrame，使用原depth plan和lease；粒子用上传后真实draw batches和现particleDepth。caster/receiver共用同一resolved纹理/coverage/world。shadow map生成与mandatory depth收集分开，不能再次申请depth或推进plan。静态帧复用同一map emitter。
5. **复用现容量计算。** F5单层scratch尺寸从原batch实现提取，batch与作者序准备共用；RF12实际snapshot消费者/utility target逻辑同样共用，不复制matcher。snapshot仍遵守原单槽extent/format边界；同owner不同extent必须在替换首slot前停止准备，不能释放尚未encode的首尺寸破坏原quota。内容copy不提前。已有group/graph容量不重复申请。terminal使用原路径真实顺序：无sceneColor时Bloom先于display scratch，不能借旧批收集顺序让新增scratch抢先。terminal准备仅取得原pool的composition/display容量并由现main-pass pin持有，不提前调用`SubmissionCoordinator.reserveDisplayScratch`：该入口要求`preparedDisplayScratch==nil`，仍只在原terminal处调用并接管，避免第二次调用失败而跳过显示映射。
6. **完成后才可选阴影。** 完整当前模型集合与mandatory容量成功后才分配、写入原F6 map，随后主颜色只执行一次。失败不撤销已encode的source，不重放graph，不伪造complete publication。

<a id="rf13-retired-design--普通provider的无内容容量职责"></a>
##### 普通provider的无内容容量职责

normal provider并非全部已reservation：`SceneResolvedMaterialFramePreflight.swift:142–144`跳过动态隐藏consumer，而`SceneDependencyFrameRuntime.swift:146–160`仍保load plan normal provider集合，`SceneDependencyFrameRuntime+StaticModel.swift:68–69`使原provider进入`:392–401`无reservation真实分配。这是必须覆盖的实际产生者。

在原dependency runtime中提取原capture的extent/target/identity选择供容量准备与实际capture共用，替换原段而不是复制。容量准备不消费debugCaptureFault计数，也不记录capture/publication事件；这些只由实际capture执行（static-only早capture即实际capture）。容量准备仅取得原pool缓存，不创建EffectTargetReservation，不publish、不读取main、不存第二ticket；已有当前publication不越过原reservation identity验证。容量检查失败只停止shadow准备，不标记原capture已处理或提前封帧；typed invalid仍由原capture在实际点裁决。原capture仍在作者位置按原合同重查identity并报告typed结果，不用提前的容量成功抹掉后续invalid。静态source与normal/background的分类来自现plan索引，不再匹配作者形状。

<a id="rf13-retired-design--部分失败与计划交接"></a>
##### 部分失败与计划交接

在实际source/target/depth/scratch/snapshot/Bloom失败点停止后续准备并关闭本帧可选shadow；保留恰好原顺序的资源前缀，主循环继续原消费。多mesh同层保留完整已resolve数组：`Depth(lease:nil)`表示已尝试失败而不重复申请，`depth=nil`表示未访问的mesh，后续从同一plan续行；未访问层不写prepared项。named draw集合未确定时不得写空数组、不得推进该模型depth plan。前缀draw使用已准备depth，后缀仍从原plan正确位置继续，普通原capture可在原位重试，下一帧重新按epoch处理。明确没有draw的singular变换只用现normalMatrix准入；不增第二几何筛选。

不能在每个image/utility/normal provider处永久停准备来规避所有者缺失。必要的容量职责在原owner内补齐，冷/resize中间provider是验收门；原RF12未支持extent组合仍单独标明，不能用它掩盖新漏项。

<a id="rf13-retired-design--f1纠正容量需求由真实lighting-payload决定设计补丁已批准"></a>
##### F1纠正：容量需求由真实lighting payload决定（设计补丁已批准）

v1独审定位了实际反例：reflection-only且`LIGHTING=0`的层遇缺失/unsupported normal时，原`SceneResolvedMaterialFramePreflight+LitCapture.swift:137–139`产生miss，plain request没有sourceLighting且blend为0，本来不消费scratch；只看`profile.surfaceEnabled`会在较晚健康模型depth之前预留无消费者容量。geometry、pipeline、light packing和payload validation也沿同一真实producer拒绝，不能另造只匹配这一反例的normal条件。

容量准备调用原`makeLitCapturePayload`获得实际typed resolution，lighting只在payload存在时产生scratch需求，color-blend仍按原实际消费准入。resolution保存于现frame准备记录，原`preparePlainSourceLighting`消费同一结果并保原诊断；未访问的层沿原现场resolve。输入使用同一已冻结frame light/dynamic/world/source snapshot，不反复packLights，不新增lighting matcher或registry。environmentSource只保原延迟闭包，准备时不执行，真正背景内容仍由原consumer第一次调用取得；沿原F5 admission决定闭包是否可用，不能因新增scratch准备成功而把原nil变为可用或改变reflection.scratchReady。beginTextureFrame已一次性发布normal/map的asset状态，这类lookup不依赖后续named publication，缓存本帧miss不锁掉合法named晚恢复。

为复用这一原producer，需将`Frame/SceneResolvedMaterialFramePreflight+LitCapture.swift`纳入第七个原owner路径，仅增加原plain消费入口可选prepared resolution；其余六路径不扩。补丁独立设计ACCEPT绑定freeze SHA `e5d0fad83c44c730fa2ba892b6d9fd3214a7fb4e960a889a9bc63e586915f3a6`；复核`/private/tmp/mwx-rf13/design-f1-review.md` SHA `311e313c4e4d581b89e13e71ae8cb34972265bac88b7a3f15a60e860c1232fa3`。前置提交后批准第七路径实施，产品F1负/正控仍未验收。最小反例必须实际编译该producer与容量入口，在紧nativequota下证明reflection-only缺normal不消耗scratch且后续模型depth存活；配对可生成payload的场景仍需正确保容量，不能删掉所有lighting预留来过门。

<a id="rf13-retired-design--精确实施职责"></a>
##### 精确实施职责

产品仅触达以下七个原owner文件（均相对`MyWallpaperX/Core/SteamWorkshopScene/Rendering/`）：`Frame/SceneMetalRenderer.swift`、`Frame/SceneMetalRenderer+StaticModels.swift`、`Frame/SceneMetalRenderer+DependencyProviders.swift`、`Frame/SceneResolvedMaterialFramePreflight+Admission.swift`、`Frame/SceneResolvedMaterialFramePreflight+LitCapture.swift`、`Dependencies/SceneDependencyFrameRuntime.swift`、`Dependencies/SceneDependencyFrameRuntime+StaticModel.swift`。提取raw输入调用必须替换现forward/主循环重复计算，保主循环先前source identity拒绝。无需新增shader、pool、registry、reservation ABI或parser。其他路径须先指出现owner的具体缺口并修订设计；本精确方案已获独立设计ACCEPT：冻结v3 SHA `2f91ab8f673b2e22f7fab67d87143199f572cbf2c13d8f1e951eb37908d344aa`，复核记录`/private/tmp/mwx-rf13/design-review-v1.md` SHA `aa8f9ee0ae000f160268f4770738eacd103d83d49d7c882cc272aa4fd20a5f36`。裁决仅批准此实施边界，产品仍须通过后述行为门与独立终审。

<a id="rf13-retired-design--fallback-与纠正门"></a>
#### Fallback 与纠正门

普通source/capture unavailable仍由原模型显示路径局部处理；若稍后原loop可能恢复，不能锁prepared空结果或借旧named纹理。完整当前caster集合仍不能确定时，本帧阴影可保守关闭，健康模型原颜色必须保留；已确定缺失与可恢复unavailable不可混同。epoch、reservation、range、publication identity无效沿原失败权威拒绝，不能降级为optional miss。

最小验收：同一冻结早/晚named反例转绿，补solid真实消费与较早健康模型→中间provider→较晚named模型冷启动/真实resize；provider alpha与cast/receive分离、健康peer和后帧更新；真实capture/registry幂等（原循环不重复encode）；紧配额下保持原mandatory优先级、optional失败不夺原输出；普通无reservation provider背景内容仍在原位置、plain scratch/snapshot/utility及Bloom/display次序；部分prefix失败后后缀继续、取消、在飞与最终释放。每项覆盖范围以实际owner/App证据标明，测试壳不能冒称完整renderer。Swift/Metal编译、Debug构建、code-health/defense/design、文档门及独立产品终审按风险完成。

原模型显示场景可作邻接回归；添加cast-on灯的派生样本必须明确标记，不冒称未改原包收益。官方画面一致性、性能、多屏、其他光型、所有模型格式和effectful provider不因本片通过而完成。

<a id="rf13-retired-design--退役条件"></a>
#### 退役条件

真实缺影反例、原显示保护和资源门均关闭并获独立终审后，稳定职责移交[runtime architecture](../architecture/runtime-architecture.md)，冻结运行记录归历史；本设计归档且删除窄gate。其余D3与后继仅由[兼容路线](../roadmap/scene-compatibility-roadmap.md)排序，不将方法未知当永久跳过。
