<!-- document-role: historical-evidence -->
# 模型实例共享场景深度域

> **历史证据 — 非现役入口**。 截止2026-10-19；职责归[运行架构](../architecture/runtime-architecture.md)，决定归[F6场景深度域](../roadmap/batch2/2d-lighting-material-design.md#model-scene-depth-domain)，样本余项归[队列](../roadmap/scene-open-breakpoint-queue.md)。本批不关闭333或343。

旧规则按完整geometry hash、相近轴长和固定距离下限1，将后继模型分到空私有depth。自有不接触闭合cube的实际App红例：原单位远红覆盖近绿，模型/相机/clip整体×10后才近绿；原selector CPU也记录域随单位变化。首轮overlay被裁剪、颜色包装fallback的载体失败保留，后者不等于模型缺失。R2修正载体后两臂正控全部成立，才实施通用修正；未按样本、路径或hash选择新算法。

StaticModelFrame现在按实际pass/CB持有一次申请及首次clear，mandatory、late named、模型和获准terminal复用同一域与失败决定。第一成功encoder clear0，重开load；不同pass独立。退休near-coincident selector、每part depth缓存和唯一消费的完整geometry hash，保mesh资源缓存、材质/cull/write、三槽pool、粒子独立lessEqual/clear1及原group准入。错CB arm曾可提前交出shadow pin，独审发现后修为只标原typed failure且保可取消/正确提交；domain身份失败上交dropped，其他帧busy仍defer并取消未提交候选。图片base bind也改用显式always/no-write stencil，实际Metal API validation及原13组像素保持。

同冻结候选App的原R2两单位输入均恢复近绿，边缘、独立模型与overlay正控保持。另一次四panel合成App覆盖资源改名、UV/tangent等价变体、旋转和反向顺序；自有闭合球内外壳按65.1/65近共面，半红/绿为(124,124,44)，先绘前景蓝仍为(24,64,224)，露出壳体、各单源和overlay/black共12 ROI在ready/after均符合冻结原值。世界矩阵、实际draw、pass/CB日志均来自候选，不把selector预测写成GPU trace；未使用官方算法或作者几何载荷。

必要owner门改用真实压力：三个pending CB各持一个模型域，第四候选不提交；completion后恢复。同CB独立耗尽三槽后当前域失败保持memo，健康颜色仍可用；同pass四模型只一槽、两pass/HDR attachment独立、首次clear/load readback、错CB arm pin守恒、cancel、late named前缀和5/8/64part实际输出均通过。选定shadow七方法与四份owner/parts/named/blend harness十三方法均取得通过；另在同一blend harness增加唯一写关闭方法：近红独绘仍红且depth0，后绘远蓝恢复到far-only像素/深度，开写近红仍挡远蓝。原parts overlap是far→near，不能反证writer误开；误归属已撤回，旧16向量/128资源字节均保。宽锥旧90°正向输入失败保留，改45°恢复原四map oracle，90/120/179保direct仅拒optional shadow的原CPU邻门另验。只修旧fixture叶依赖，未放宽pixel/配额/四灯断言；没有跑整个宽映射矩阵。

原333同非中心pointer/PCM/property的修前后两臂均App0、无输入或App漂移、正常stop/GPU排空；候选前三帧18实例各有实际world/encoded及唯一pass/CB。两图仍见倒向文字透见、粉顶/扁盒与黑背景；原effect CPU、229 Program fallback及Rope三FAIL保持，本包没有可认视觉关闭。原343两个模型的前三帧同样完整，修前后after均保地表、云、蓝边与银河；夜侧仍偏亮。两臂截图序列有superseded，候选另有teardown失败，raw全部保留；现有成功图只证基础合成，不关闭间歇闪烁、精确光影或collision，也不作官方同phase/HDR parity。单次资源需求观察仅归[性能卡](../roadmap/performance-convergence-card.md)，不据删hash认稳定性能收益。

产品冻结`223edda4800350f5711ce93a14fbd4b197f3869c4c33c6969150f23e450b33c4`，固定基线`a06b0976749a6604a929c770cd70328921f472a5`叠加明确53文件，两次必要Debug均4314输入/外部闭包无漂移、严格签名0。最终候选executable `922781e946cb8ba320bbc86a4d474fc3318130d33784b2c8313b85d4a1ce7379`、dylib `8e20495e86a540ccacb4336231271ff633775353ba402b742d2bbdddb43e45fe`；审查后只纠正两行过时注释，精确替换收据证明语句/行数不变，未为注释再构建或重复App验收。外部project改动不在构建overlay或提交内。

必要原数、失败、协议/输入、PNG、身份和独审以14天包`.artifacts/scene-evidence/runs/model-scene-depth-domain-20261019/`保存；343原始PNG每张约18.7MiB，修前另存`model-scene-depth-before-20261019/`以满足单包32MiB，主包引用修前包，原PNG字节不变。本机任务`.artifacts/tmp/native-model-depth-domain-20261019/`仅留轻量收据及后继所需App/共享构建缓存。VM未运行新实验、原官方预览状态仍未知，不关闭官方主客户端或虚拟机；default text的原STOP_UNKNOWN不被本批补证。
