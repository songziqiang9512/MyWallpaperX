<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# RF13 — 当前 named albedo 模型参与方向光投影

> **历史证据 — 非现役入口**。本文保留实施前裁决及当时验收待办；RF13 已完成有界产品验收，结果见[执行记录](rf13-named-model-shadow-implementation-2026-10-02.md)。稳定职责见[架构](../../scene/design/runtime-architecture.md)。

基线 `d5908b53`。承接[RF13工作卡](../../scene/design/reference-evidence-implementation-cards.md#rf13-named-model-shadow)。**设计已批准，实施/运行验收尚未完成**；`scene-named-model-directional-shadow`登记为`approved`。本文不修改原named source准入或私有阴影算法。

## 目标合同与当前事实

已在原direct static-model主链合法显示的hidden image/solid source-only named albedo，与静态纹理模型使用同一个当前帧纹理、geometry、world、material/coverage及directional light形成阴影；同帧颜色和阴影不能借不同资源或前帧publication。冷启动和resize也是目标，不能把只命中缓存的帧作为完成条件。未支持的可见/effectful/有子层provider不借本片放开。

以下源码路径相对`MyWallpaperX/Core/SteamWorkshopScene/`，行号属于基线：

- `Rendering/Dependencies/SceneDependencyRenderPlan+StaticModel.swift:130–164`已限定hidden image/solid、无effect/dependency/children、primary slot0并记录forward需要。
- `Rendering/Frame/SceneMetalRenderer+StaticModels.swift:156–160`在named输入尚未发布时返回nil取消整帧shadow；`:253–254`即使ready仍要求entry静态albedo存在才投影。原颜色draw在`:79–92`能解析当前named albedo。
- `Rendering/Frame/SceneMetalRenderer.swift:323–348`在shadow之后准备forward providers，`:468`在作者循环捕获原provider。因此静态反例有真实调用路径，并非只有字段未连线。
- `Rendering/Dependencies/SceneDependencyFrameRuntime.swift:302–308,380–389`已有当前publication幂等；有reservation时先检查epoch/extent/texture身份，不应新增无条件complete快返。`:331–339`将mixed normal/static消费形状局部判unsupported；`:530–569`拥有原source-only capture与provider动态alpha/color。
- `Rendering/Frame/SceneMetalRenderer+TextureFrame.swift:37`开启原registry frame epoch；`SceneDependencyFrameRuntime+StaticModel.swift:79–109`裁决完整当前named publication，保premultiplied/frame/sampling身份。
- `Rendering/Dependencies/SceneNamedRenderTargetPool.swift:38–79`按provider缓存真实target；`Rendering/Particles/SceneParticleDepthTargetPool.swift:37–44,122–126`的cancel/completion只释放reserved标志，不能假称退还cache纹理或恢复旧槽。

真实修前证据：`/private/tmp/mwx-rf13/baseline-zwnb1ivz`三次不可变RF12 App运行。静态正控shadow9、caster绿95、control85；named早/晚两例caster与control相同、provider11 capture及model2 binding成功，但shadow85。三例exit0、App未变、frame1/2 completion与安全drain、ready/after整图一致。预运行protocol SHA `3346dca609aaffff7c42f6cc839424b49a4f5bf079e1ff219d75f03f5b50ea90`；索引SHA `232ab6e454e952486365919876a28969efed85a11fd678053f159251fa32fa56`。这是自有合法输入的真实缺影反例，不是官方parity或完整原包收益。

## 参考证据的用途

[Mirage参考](../../scene/semantics/miragewallpaper-rendering-reference.md#64-rendergraph-的资源版本) §6.4将材质slot read、target write和linked source版本作为同一依赖图职责；§11.6区分隐藏但被采样的source私有写入与最终显示。这些`third-party-reference-pattern`中性信息支持当前帧producer先于consumer、隐藏不等于无资源的目标，不是官方精确调度或预算公式。其§8.4明确固定版本没有完整shadow atlas，不能复制不存在的实现来假闭合。本项目继续使用已经独立实现的F6投影，仅纠正准备/消费的缺边。

## Owner、方案与待裁决点

唯一dependency capture/registry owns当前source-only publication；现frame owner组织资源次序，原StaticModelFrame与depth plan/pool owns mandatory lease；现model draw与shadow consumer共用resolved输入，最终输出owner不变。不新增provider、registry、clock、第二capture实现或另一套alpha解释。

只提前已由static-model plan准入、且本帧实际活跃模型需要的source-only职责。原forward preparation还执行effectful graph并可能触发首次环境reflection，不能未经相位与资源核验整体移动。旧named帧的forward本来就在首个主颜色draw前；若仍只执行一次并保持内部顺序/claim及首次reflection内容相位，而shadow只写独立depth，则forward先于shadow并非天然不合法。设计以实际主颜色内容与mandatory容量为判据，不为先前保护性假设另造raw prepass。提取重复raw capture参数计算时应替换现forward/作者循环两处，第三调用点复用同一owner；原loop先前执行的base selection/identity拒绝不能被helper吞掉。当前published沿原registry幂等复用，不另存captured集合。

named的premultiplied颜色身份沿原模型路径解读；投影只复用该draw既有alpha/opacity/tint-mask coverage，provider alpha不得重复应用，也不能影射新材质开关。

**预算顺序已有真实反例。** 把named target提前可能让它占掉作者较早模型的depth配额；optional shadow最后分配本身不足以证明原画面不受影响。本机Apple M4原NamedPool/DepthPool测试为两种256²纹理各实际264192 bytes，仅留一份配额时，旧depth→provider得到depth成功/provider失败，反序得到相反结果；cancel前后仍计264192，owner作用域退出后才归零。结果`/private/tmp/mwx-rf13/pool-probe/result.json`，原源码未改，无command buffer/encode，证明真实分配顺序风险但不冒称App回归。

### 选型：原owner按原资源次序准备，原循环按原位置绘制

选用完整作者序准备方案。首模型前才尝试阴影无法覆盖“较早健康模型→中间backward provider→较晚named模型”，cache-only无法覆盖冷启动/resize，均不作为本片交付。跨owner交易manager、复制恢复depth旧reserved快照、先encode后假称rollback也不选；GPU completion可合法改变在飞slot状态，原lease.cancel并不退还缓存容量。

1. **原前置阶段。** 保持原graph/FBO/effect named reservation与D1组target的准入。旧named-pending帧的`requiresShadow=false`判断不改成hasShadowReceiver，原reflection确需的F5批预留仍保留。原完整forward只执行一次，内部graph/claim及首次reflection内容相位不变；新shadow只写独立depth，不消费主帧前缀。
2. **原frame owner消费现prepared计划。** 在现StaticModelFrame mandatory准备职责中，按原orderedLayers与真实group pass访问原资源消费者，不在普通帧重新解析、建图或序列化。作者位置依次处理raw target、真实model/particle depth、plain scratch、该消费者snapshot、该位置utility触发的snapshot。跳过规则与原主循环一致，隐藏触发层的utility defer仍计入。
3. **内容与容量分开。** 已编译准入的static-only source capture可在准备阶段执行，复用原source/alpha/color/world与唯一registry。普通normal provider可能读取已绘制主帧，提前只准备实际target容量，不encode或publish。主颜色、背景复制、reflection内容与utility graph依旧原位执行；成功source-only捕获在旧调用点靠原epoch幂等返回，不能另建captured集合。
4. **真实depth准备一次消费一次。** 实际resolve成功的draw记录写入原StaticModelFrame，使用原depth plan和lease；粒子用上传后真实draw batches和现particleDepth。caster/receiver共用同一resolved纹理/coverage/world。shadow map生成与mandatory depth收集分开，不能再次申请depth或推进plan。静态帧复用同一map emitter。
5. **复用现容量计算。** F5单层scratch尺寸从原batch实现提取，batch与作者序准备共用；RF12实际snapshot消费者/utility target逻辑同样共用，不复制matcher。snapshot仍遵守原单槽extent/format边界；同owner不同extent必须在替换首slot前停止准备，不能释放尚未encode的首尺寸破坏原quota。内容copy不提前。已有group/graph容量不重复申请。terminal使用原路径真实顺序：无sceneColor时Bloom先于display scratch，不能借旧批收集顺序让新增scratch抢先。terminal准备仅取得原pool的composition/display容量并由现main-pass pin持有，不提前调用`SubmissionCoordinator.reserveDisplayScratch`：该入口要求`preparedDisplayScratch==nil`，仍只在原terminal处调用并接管，避免第二次调用失败而跳过显示映射。
6. **完成后才可选阴影。** 完整当前模型集合与mandatory容量成功后才分配、写入原F6 map，随后主颜色只执行一次。失败不撤销已encode的source，不重放graph，不伪造complete publication。

### 普通provider的无内容容量职责

normal provider并非全部已reservation：`SceneResolvedMaterialFramePreflight.swift:142–144`跳过动态隐藏consumer，而`SceneDependencyFrameRuntime.swift:146–160`仍保load plan normal provider集合，`SceneDependencyFrameRuntime+StaticModel.swift:68–69`使原provider进入`:392–401`无reservation真实分配。这是必须覆盖的实际产生者。

在原dependency runtime中提取原capture的extent/target/identity选择供容量准备与实际capture共用，替换原段而不是复制。容量准备不消费debugCaptureFault计数，也不记录capture/publication事件；这些只由实际capture执行（static-only早capture即实际capture）。容量准备仅取得原pool缓存，不创建EffectTargetReservation，不publish、不读取main、不存第二ticket；已有当前publication不越过原reservation identity验证。容量检查失败只停止shadow准备，不标记原capture已处理或提前封帧；typed invalid仍由原capture在实际点裁决。原capture仍在作者位置按原合同重查identity并报告typed结果，不用提前的容量成功抹掉后续invalid。静态source与normal/background的分类来自现plan索引，不再匹配作者形状。

### 部分失败与计划交接

在实际source/target/depth/scratch/snapshot/Bloom失败点停止后续准备并关闭本帧可选shadow；保留恰好原顺序的资源前缀，主循环继续原消费。多mesh同层保留完整已resolve数组：`Depth(lease:nil)`表示已尝试失败而不重复申请，`depth=nil`表示未访问的mesh，后续从同一plan续行；未访问层不写prepared项。named draw集合未确定时不得写空数组、不得推进该模型depth plan。前缀draw使用已准备depth，后缀仍从原plan正确位置继续，普通原capture可在原位重试，下一帧重新按epoch处理。明确没有draw的singular变换只用现normalMatrix准入；不增第二几何筛选。

不能在每个image/utility/normal provider处永久停准备来规避所有者缺失。必要的容量职责在原owner内补齐，冷/resize中间provider是验收门；原RF12未支持extent组合仍单独标明，不能用它掩盖新漏项。

### F1纠正：容量需求由真实lighting payload决定（设计补丁已批准）

v1独审定位了实际反例：reflection-only且`LIGHTING=0`的层遇缺失/unsupported normal时，原`SceneResolvedMaterialFramePreflight+LitCapture.swift:137–139`产生miss，plain request没有sourceLighting且blend为0，本来不消费scratch；只看`profile.surfaceEnabled`会在较晚健康模型depth之前预留无消费者容量。geometry、pipeline、light packing和payload validation也沿同一真实producer拒绝，不能另造只匹配这一反例的normal条件。

容量准备调用原`makeLitCapturePayload`获得实际typed resolution，lighting只在payload存在时产生scratch需求，color-blend仍按原实际消费准入。resolution保存于现frame准备记录，原`preparePlainSourceLighting`消费同一结果并保原诊断；未访问的层沿原现场resolve。输入使用同一已冻结frame light/dynamic/world/source snapshot，不反复packLights，不新增lighting matcher或registry。environmentSource只保原延迟闭包，准备时不执行，真正背景内容仍由原consumer第一次调用取得；沿原F5 admission决定闭包是否可用，不能因新增scratch准备成功而把原nil变为可用或改变reflection.scratchReady。beginTextureFrame已一次性发布normal/map的asset状态，这类lookup不依赖后续named publication，缓存本帧miss不锁掉合法named晚恢复。

为复用这一原producer，需将`Frame/SceneResolvedMaterialFramePreflight+LitCapture.swift`纳入第七个原owner路径，仅增加原plain消费入口可选prepared resolution；其余六路径不扩。补丁独立设计ACCEPT绑定freeze SHA `e5d0fad83c44c730fa2ba892b6d9fd3214a7fb4e960a889a9bc63e586915f3a6`；复核`/private/tmp/mwx-rf13/design-f1-review.md` SHA `311e313c4e4d581b89e13e71ae8cb34972265bac88b7a3f15a60e860c1232fa3`。前置提交后批准第七路径实施，产品F1负/正控仍未验收。最小反例必须实际编译该producer与容量入口，在紧nativequota下证明reflection-only缺normal不消耗scratch且后续模型depth存活；配对可生成payload的场景仍需正确保容量，不能删掉所有lighting预留来过门。

### 精确实施职责

产品仅触达以下七个原owner文件（均相对`MyWallpaperX/Core/SteamWorkshopScene/Rendering/`）：`Frame/SceneMetalRenderer.swift`、`Frame/SceneMetalRenderer+StaticModels.swift`、`Frame/SceneMetalRenderer+DependencyProviders.swift`、`Frame/SceneResolvedMaterialFramePreflight+Admission.swift`、`Frame/SceneResolvedMaterialFramePreflight+LitCapture.swift`、`Dependencies/SceneDependencyFrameRuntime.swift`、`Dependencies/SceneDependencyFrameRuntime+StaticModel.swift`。提取raw输入调用必须替换现forward/主循环重复计算，保主循环先前source identity拒绝。无需新增shader、pool、registry、reservation ABI或parser。其他路径须先指出现owner的具体缺口并修订设计；本精确方案已获独立设计ACCEPT：冻结v3 SHA `2f91ab8f673b2e22f7fab67d87143199f572cbf2c13d8f1e951eb37908d344aa`，复核记录`/private/tmp/mwx-rf13/design-review-v1.md` SHA `aa8f9ee0ae000f160268f4770738eacd103d83d49d7c882cc272aa4fd20a5f36`。裁决仅批准此实施边界，产品仍须通过后述行为门与独立终审。

## Fallback 与纠正门

普通source/capture unavailable仍由原模型显示路径局部处理；若稍后原loop可能恢复，不能锁prepared空结果或借旧named纹理。完整当前caster集合仍不能确定时，本帧阴影可保守关闭，健康模型原颜色必须保留；已确定缺失与可恢复unavailable不可混同。epoch、reservation、range、publication identity无效沿原失败权威拒绝，不能降级为optional miss。

最小验收：同一冻结早/晚named反例转绿，补solid真实消费与较早健康模型→中间provider→较晚named模型冷启动/真实resize；provider alpha与cast/receive分离、健康peer和后帧更新；真实capture/registry幂等（原循环不重复encode）；紧配额下保持原mandatory优先级、optional失败不夺原输出；普通无reservation provider背景内容仍在原位置、plain scratch/snapshot/utility及Bloom/display次序；部分prefix失败后后缀继续、取消、在飞与最终释放。每项覆盖范围以实际owner/App证据标明，测试壳不能冒称完整renderer。Swift/Metal编译、Debug构建、code-health/defense/design、文档门及独立产品终审按风险完成。

原模型显示场景可作邻接回归；添加cast-on灯的派生样本必须明确标记，不冒称未改原包收益。官方画面一致性、性能、多屏、其他光型、所有模型格式和effectful provider不因本片通过而完成。

## 退役条件

真实缺影反例、原显示保护和资源门均关闭并获独立终审后，稳定职责移交[runtime architecture](../../scene/design/runtime-architecture.md)，冻结运行记录归历史；本设计归档且删除窄gate。其余D3与后继仅由[兼容路线](../../scene/scene-compatibility-roadmap.md)排序，不将方法未知当永久跳过。
