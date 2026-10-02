<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# D3 反射环境输入与资源顺序中性合同（2026-10-02）

> **历史证据 — 非现役入口**。归档两份分别通过独立隔离审查的中性交接。实现裁决由[D3 F5设计](../../scene/design/2d-lighting-material-design.md#f5-reflection-environment)拥有，任务方向由[兼容路线](../../scene/scene-compatibility-roadmap.md)拥有。本文不批准产品、不提供官方算法、像素golden或官方运行时序证明。

## 隔离、身份与审查范围

研究者永久research-only；root、实现者与审查者均未接收原始shader、函数体、公式或研究工具原始输出。声明阶段只交白名单字段及presence；资源阶段只交角色、资源版本与先后。实现者可以据此独立编写方法，不能把第三方方法或输入名称推断成官方数值合同。

本机冻结证据包 `/private/tmp/mwx-reflection-environment/`：

| 文件 | SHA-256 | 裁决范围 |
|---|---|---|
| neutral-contract-draft.md | `8f0fe115cc13c7cfc44c83ecb1f45c55a64d07ac3e62c2b50640048cbaa29b9c` | 输入声明中性正文 |
| extract-declaration-metadata.py | `465c802bd52a41ad6ded14da2cf7065c267a9e9c8a56b73c14c44213c0fb5eae` | 本次精确白名单提取器，非通用消毒器授权 |
| declaration-metadata.json | `fbac91cf07a67dba1c2c02c5431262b54f62bdb5cd3d8938fdcde767fbd9b2dc` | 精确声明结果 |
| neutral-declaration-review.md | `5c1e5ce1512341b715b69976bbb9f8b39ecdedb2dd9c452c97d9f8ae9c853f12` | ACCEPT上述中性结果；未重跑原始提取 |
| neutral-resource-order-draft.md | `573fd2b0e4ad423aa815a8e8e376763c69db3dcc4745e7b6d61941fa3dd2f369` | 第三方资源顺序中性正文 |
| neutral-resource-order-review.md | `bdecde5294247dab6c20525730c5ea65682f62a931e3b6c052d2ed7985f40f88` | ACCEPT中性顺序与类别边界，独立核六个固定blob摘要 |

草稿保留其研究时的pending标记，没有倒改冻结原件；后续审查文件才是各自ACCEPT的依据。两次审查都不构成产品设计批准。

## official-public-doc：作者行为

[Lighting & Reflections](https://docs.wallpaperengine.io/en/scene/lighting/introduction.html)说明Lighting与Reflection可以分别启用；normal影响表面，roughness影响反射模糊，Reflectivity与Reflection map分别控制整体与局部反射。[Shader Variables](https://docs.wallpaperengine.io/en/scene/shader/variables.html)说明隐藏sampler可指向内部目标以及default输入职责。两页都没有确定本目标的生产时点、内容范围或frame age。本轮访问日期2026-10-02。

## official-client-static-observation：输入身份

固定客户端2.8.42；version.json SHA `63d3083d31280df36b37855ea833a6bcdb49afd59dd7963a27cf771e3532d1e1`；wallpaper32.exe SHA `daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07`。以下仅定位声明，不引用私有表达：

| 相对assets/shaders路径 | 文件SHA-256 | 中性事实 |
|---|---|---|
| genericimage2.frag:47 | `1e252e2271cae57fcfdecf3bd79d1685bb726e1e8afe09ba863dca2e1b12d68e` | hidden slot3，2D，default `_rt_MipMappedFrameBuffer` |
| genericimage4.frag:68 | `6b5344953054ae853ff8a7942f716dd9eb67f61cc1526bd8b6bc67df92c76e1f` | 同上；不是cube或默认 `_rt_Reflection` |
| genericimage4.frag:70 | 同上 | hidden作者float reflectivitydistance，声明default4 |

在LIGHTING0组合中，上述声明presence需要REFLECTION1且NORMALMAP1。**声明presence不证明实际执行准入、纹理绑定或GPU输出。** reflectivitydistance的官方单位、数值作用仍unknown；genericimage2精确提取未见同名字段，不能据此补出另一个公式。reflectivity默认1及slot2逻辑B权重分别复用[PBR输入合同](d3-pbr-input-neutral-contract-2026-10-02.md)与[贴图输入合同](d3-pbr-map-input-neutral-contract-2026-10-02.md)。

## third-party-reference-pattern：一次共享本帧前缀

固定Mirage revision `da4fa7b3ee33e9e94c59307f47098aa521f21aa6`，读取固定git对象，未切换或修改参考checkout。下列路径相对 `SceneRenderer/Sources/SceneRenderer/`，行号仅作证据定位：

| 文件 | SHA-256 | 证据窗口 |
|---|---|---|
| Gpu/Pipeline/SceneRenderPlanner.cpp | `af03a0d1c33aaaffda8f07e14f1584a84c4f4881ae676de4c9a73e485eccaebc` | 104–110、173–193、233–245、349–394、428、507–510、531–566 |
| Frame/Graph/FrameGraph.cpp | `a1a85ec0c50a1ed290361ac77910e7b75c509c47cbc78a09f2912949a6bef667` | 357–420 |
| Wallpaper/Compiler/SceneCompiler.cpp | `856016a5aae99c4a9dcdcdf634aa28897dabff34480eab0f80af4307be7dfdba` | 5617–5629 |
| Gpu/Pipeline/BlitPass.cpp | `3aaeb392bf76b36976f1a8484804af78e70d983c8a14215b1a946e52c44b703b` | 21–38、56–98、100–117、164–168、185–201 |
| Gpu/Pipeline/VulkanFrameEngine.cpp | `8e458e6deab5edf9dbf57f68620ed9fb4dce828ec49e2990d30a5b00f534476a` | 204–217、313–364、496–543、1491–1503、1524–1530 |
| Gpu/Pipeline/PreparePass.cpp | `d74bc2cf90b22ea2b5401484cddfba3fc6fc2202313ab1abc2da7f21a205c23e` | 145–181 |

资源descriptor准备与像素生产是两件事。首次Mip消费者取得当时主scene最新逻辑颜色版本，形成独立快照；后续消费者复用该快照。每帧执行copy再生成mips，下一帧重新生产，不是previous-frame history，也不是每个receiver重新抓背景。没有消费者，该分支不新增copy/mip工作；这不证明没有descriptor登记或任何资源分配。

普通主scene单draw首receiver本次输出尚未写入快照，后续receiver输出也不追加进去。这里没有对象身份排除规则：同一对象此前已完成的另一主scene pass可能属于前缀，layer-local工作目标也不会自动进入全局scene。图的版本依赖确保读写次序，不能单凭静态图证明实际GPU completion。

普通该链在绘制前清理主目标；空前缀可以包含当帧clear。新图重新选择首消费者，已准备图每帧重新执行像素生产；尺寸变化更新目标请求，mips取决于物理extent。旧行号SceneRenderPlanner:264–269对应effect authored copy，本次Mip入口是365–366，快照owner是233–245。不得沿旧行号误认职责。

## inference：项目可以独立选择的策略

上述信息足以设计“首次有效消费前共享一次本帧前缀”的独立环境输入，不必追私有BRDF。具体什么是有效消费、forward provider提前执行、可见性变化和group未合成颜色怎样处理，必须由本项目设计明确；不能把我们现有调度行为冒称已获得官方证明。环境只读资源、真实mips、epoch/generation、预算、在飞回收与取消继续由既有owner承担。

判别验收应区分共享与逐consumer快照：前置红绿板、receiver A、中间蓝板、receiver B；只把蓝板移至A之前，二者才共同改变环境。逐帧脉冲区分同帧与history；改变A本次输出不应通过共享环境影响B。另验证clear、no-consumer、plain/effect、resize及失败恢复。这些是拟议自有实验，本文不将其写成已通过。

## 旧产品反例与证据上限

基线产品提交`6a95278f`的实际Swift builder四例保留genericimage4、LIGHTING0、REFLECTION0/1、reflectivity0/4和三槽，却均没有normal/map需求。冻结App同四例、两帧共八张PNG逐像素一致，SHA均为 `2c0507fe6c44f58b4d8b7264c01fff76f6e92b7e846801cc3ed5a675abb35fc3`。运行记录有completion、单session及drain；这证明现产品缺响应，不能倒推出正确环境来源或官方像素。

本机 `evidence-manifest.json` SHA `67663f3e4d179deef6e1aae3238c34aafd79bda953529c65b3caf9fb9dd0a430`，独立 `red-review.md` SHA `6427b39c713e0a1d5852717b7a3b5171fef0d3a299fcbd1d23d38847a1bab9f5` ACCEPT该反例。实际输入、101个生产依赖与App三项binary身份在该冻结包，不复制成现役运行权威。

官方时序、数值公式、reflectivitydistance官方单位、复杂多pass/planar混合、MSAA和第三方所有在飞失败路径仍未证明；未运行官方或Mirage动态对照。项目独立实现可以继续，但不能由本合同声称官方parity、完整反射兼容或性能完成。
