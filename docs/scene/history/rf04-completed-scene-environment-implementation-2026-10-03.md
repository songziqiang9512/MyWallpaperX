# RF04 A — 完成画面作为默认环境反射源

> **历史证据 — 非现役入口**
> 本片实现和运行事实；现役职责见[运行时架构](../architecture/runtime-architecture.md)，选序见[工作卡](../roadmap/batch2/reference-evidence-implementation-cards.md#rf04--d12-已完成画面的共享-mip-输入)，设计与未完成B见[D12](../roadmap/batch2/copy-pass-unification-design.md#rf04-completed-scene-environment)。

## 用户结果与边界

默认builtin F5此前在首次消费时抓取当前main前缀，作者顺序较后的图层不会进入该次环境。A将来源改为同surface最后成功完成的raw画面：后置层可以进入后继反射，首帧缺历史仍正常显示。plain/graph沿原共同lit consumer；不新增history、registry、clock或最终输出owner。

[官方中性观察](rf04-scene-mip-observations-2026-10-03.md)支持该有界历史源方向；它只证明所采呈现关系，不证明精确上一GPU帧、HDR、alpha或mip过滤公式。本项目选择最后成功raw、pre-Bloom/pre-display-copy和硬件mip，保持独立算法。B作者`_rt_MipMappedFrameBuffer`名称仍未准入，其Program preflight阶段环未解，不将A默认反射验收冒称作者sampler可用。

## 实现与失败合同

- 原`completedSceneColor`同时服务persistence和可选snapshot；前者保HDR seed/paused export/display，后者用实际BGRA8/RGBA8/RGBA16F双raw，不无条件支付第三张display。
- 当前reservation冻结previous texture及真实producer receipt。snapshot同simulation frame重画也轮换member；生产identity包含实际CB注册身份、frame/execution epoch、allocation generation与reset epoch，不能借consumer当前epoch冒充生产时刻。
- snapshot完成后只留元数据，实际pair归原pool cache，后帧mandatory可驱逐。mandatory准备后重取真实lease并验证身份，才恢复previous；cache miss按无历史重新启动。
- 当前ReflectionFrame只从该冻结previous生成一次完整mip并共享；普通main在原terminal前复制到候选。成功copy不等于完成，原seal/FIFO completion成功后才提升；取消、GPU失败seam、reset或陈旧完成不提升。
- 可选copy失败只detach snapshot，不取消display/persistence；已有在飞pins仍由原terminal释放。depth、Bloom、framebuffer及原graph/plain目标先保护；late named-shadow帧保原顺序，不预取可选历史。普通drawable可读条件纳入prepared反射需求，capture强制可读不能替代该门。

## 冻结身份与执行

基线产品为`f674a6cd`，并保留其外部DEBUG访问器修复。测试兼容修复单独提交`1306dd6f`和`17fb155a`。A的20个产品Swift执行manifest SHA256为`a4175b84cfe32023248e42cccbe632b8ba29dfe58942c4a5d8fd617ffa87afa8`；修正后Debug构建成功，前后无漂移。实际隔离App仅为本机ad-hoc Debug，不是发布包；完整App/调试dylib/metallib、命令、输入、test和源码身份保存在本机证据。

| 执行门 | 结果与实际范围 |
| --- | --- |
| real pool/coordinator/terminal + registry + lit | 3模块18 tests，85.280s，OK；snapshot三格式、精确双/三目标预算、跨帧mandatory驱逐、bootstrap、same-frame失败保旧、取消、reset、display共存；现HDR累积/paused路径回归。 |
| completed history→copy/mip→consumer | 两自有Metal sampler槽读不同LOD，共享source atom；当前main蓝suffix不改变本帧已冻结mip，下一次成功历史读蓝。真实生产receipt、pending不可读、失败copy局部detach、失败completion seam和实际pin释放均过。槽只是fixture，不是B作者绑定。 |
| shared model/particle depth | 两模块13项执行通过、1项环境skip，131.296s，OK；跳过项未提供其独立App环境。实际native owner覆盖原depth/晚named准备，不单凭此证明SceneDrawing caller。 |
| actual App默认反射 | Ref0/Ref1仅改变REFLECTION。四张原PNG的receiver分别恒`[128,128,128]`/`[179,128,128]`，独立double期望红通道179.0652、容差4；后置红源与绿色邻居不变。源码、输入包与App前后身份不变。 |
| 普通drawable | 同Ref1输入关闭capture，不传evidence-dir；实际ready、first GPU completion和drain，无Metal错误。没有PNG，不声称该次像素验收。 |
| actual App晚named + depth粒子 | 合法hidden provider、奇异named model、F5、需depth的健康粒子0/1对照，1 test 31.097s OK；实际capture11成功、准备models `{1,2}`、粒子真实完成且failedFrames=0、两阶段像素不变。仅正常预算，不声称紧预算故障动态复现或lease数。 |

测试原型曾错误设置provider可见，违反原static-model named输入的hidden合同，未进入目标路径；失败原型保留为fixture纠正证据，不计产品caller覆盖。独审静态发现新history准备可能与late named owner重复申请粒子depth，已用`!preparesNamedModelShadow`保守退出修正；对应正常预算App及原owner回归如上。

## 审查、产物与未覆盖

初始独立设计审查与最终产品审查均为有界ACCEPT。独审复算普通App的4张原PNG、3个包全部entries及GPU producer的303仓库输入、保存carrier/harness；合法named组合的4张原PNG、16个自有输入身份与真实capture/particle完成事件也已核验。最终20产品源码零漂移，产品审查记录SHA256为`0f581f2dc1cacb98070aba6594031759378c645f90db54ddb7e036eb24249d35`；B和共享fixture迁移不包含在该产品结论中。

共享测试载体由5742行Python中的嵌入Swift迁至11个完整职责fixture，原Python保留测试入口，12个文件均不超过1000行。78个结果键、测试AST、场景输入及全部场景正文/执行顺序保持；carrier只适配真实接口，不另模拟history。5个直接消费者24项测试134.281s通过且无skip，含回滚texture identity反例；独审确认每段场景正文/顺序和替换锚保持，迁移无新增history实现。

最终选定的85个模块均有成功调用记录；依赖独立App环境的skip仍以日志为准，不计实际App覆盖。新增登记相关的13个治理模块264项测试10.518s通过；结构、依赖、断言、代码健康、defense、产物、残留、设计、文档健康及导航门通过。广泛回归找到的既有carrier/import缺失按职责另修，原失败与修复后通过日志均保留，不掩盖首次失败。

产品证据已限量提升到`.artifacts/scene-evidence/runs/rf04-completed-scene-environment-20261003`；150个归档文件逐SHA复核，archive SHA256为`afe6cdd3ee4910266dd0e535e9736326e69bd58e8037b852867be9ccc7fb3d19`。包含最终源码/测试身份、真实输入、10张原PNG（含错误fixture两张）、原失败/通过日志及独审；不含App、临时HOME或缓存。默认保留14天，数字sample id只作本机归档键，不是Workshop来源。官方证据已独立提升到`.artifacts/scene-evidence/runs/rf04-official-mip-consumer-observations-20261003`，不得混称产品回归。构建缓存仅留`/private/tmp/mwx-scene-next-build/cache`供连续迭代，staged App与临时HOME在本批结束清理。

未覆盖硬件真实GPU故障、全部原包/多surface动态组合、官方HDR/alpha/kernel parity和B作者sampler。构建、少量自有App及项目数值oracle不代表全Scene兼容、性能提升或发布就绪。

## 后继：原生分配失败后的闲置缓存回收

A之后的真实配额反例揭示：pool仅在临时字典里预测驱逐，旧闲置纹理仍持有原生额度，mandatory候选会在实际apply驱逐前分配失败。修复基线为`8eca8adf`，不是官方行为兼容扩展，也不开放B作者名称。

回收仍属于原allocation cache，与逻辑驱逐共用victim/history闭包规则。实际factory返回nil后，每个逻辑分配批次最多回收一次并只重试失败项，成功前缀保留；shared pair与随后graph共用额度。完整请求key、cached/reusable/retired及history来源generation、submission和SceneColor retention受保护；原子返回本次revision，外部变更不被吸收。native账户只在真实纹理最后引用释放时退还，不手动返账、不跨pool驱逐，也不提前发布graph/history。损失可重建idle缓存允许发生，重试仍失败则拒绝该批候选。

最终7个产品文件manifest SHA256为`6e6b71eccd80a9a21118275638b68a10817b7e22a9c74e6dbcc44ee552d7c580`。Debug构建与12项新增回归17.650s通过，产品及两组各35个编译输入身份无漂移。28组非graph真实预算组合覆盖frame、单composition、group、environment、shadow、snapshot和persistence；owned/shared graph两组调用完整pool入口，冷/暖所需native charge均为9600 bytes，idle为5888 bytes，另一pool的pinned资源512 bytes保持；一次真实quota rejection后回收成功，最终账户恢复。人工reserve只限制准入额度，不是物理设备OOM实验。

外部强引用保留实际额度时，缓存可已移除而retry仍失败；释放最后引用后原请求恢复。真实shared-event阻塞CB的在飞pin在完成前保持，completion后请求可恢复；此用例无像素回读。定向factory nil补充检查一次恢复、前缀identity、retired复用到最终commit和外部revision拒绝，不能混作硬件故障。

隔离最终Debug App共8项测试、159.962s：7项实际执行通过，覆盖3个plain反射、2个late named/depth及4个HDR/暂停resize场景；缺少专门移除mapping函数的故障App用例明确skip。默认Ref0/Ref1接收区保持128³/179,128,128及健康邻层；capture-off仅证明正常提交/drain。HDR runner本身不保存每case App身份，另以固定App三artifact、最终源码manifest、完整命令及日志联合登记，范围不扩成官方parity、全Scene兼容、性能或发布结论。

旧pool测试的三条Nth分配“零缓存变化”要求与本次恢复合同冲突，已改为一次恢复/保前缀/失败不发布。其余143个顶层结果键、29个Python测试、17段case正文和顺序、pre-main支持及跨段对象传递经独立机械核对保持；载体拆为六个完整职责Swift fixture与420行Python，均≤1000行。机械保持不证明新函数scope下全部ARC轨迹相同；真实pool的29项回归8.882s通过，另跑直接消费者。首跑新断言误用不存在的cache accessor，修为原锁内residents查询后通过；原编译失败日志保留，不冒称产品故障。

composition另以同一固定App补跑15项、204.834s全部通过，覆盖真实group source、childless/nested capture、空源清除、取消恢复与resize；原无App调用的skip不被计为这次执行。三个直接消费者初跑成功、pool编译修正后29项通过；仅源码场景同构不替代这些实际运行结果。

整批25文件冻结独审为有界ACCEPT、无P1/P2，记录SHA256为`7a2e634c4fc998d711d487c1603c64b6e9a6fa035578bdd9eb643b53b438dd46`；10项门禁与14个治理模块均通过。最终证据提升至`.artifacts/scene-evidence/runs/rf04-native-allocation-recovery-20261003`，334个成员逐SHA核验，archive SHA256为`980451f61d167faa7811a349e567e9591a0c52a1d358de317d032ba325b65736`，默认14天。原protected容量反例五个文件以原字节保存在archive的`prior-counterexample/`，原独立保护包随问题解决退役；47张最终App PNG、实际输入、原失败与通过日志、源码身份及独审一并保留。原collector的非数字归档键不符合promotion schema，改为本机数字键后成功，不改变archive字节或验收结果。
