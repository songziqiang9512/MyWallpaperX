<!-- document-role: stable-contract -->

# Direct model 的 bind 几何

目标是在动画尚未支持时仍显示独立合法的作者模型几何，优先恢复缺失主体；不将 bind 几何称为作者默认姿态或动画成功。当前支持范围归[高级对象覆盖](advanced-object-coverage.md)，结果与未覆盖证据归[运行证据](runtime-evidence-current.md)，选序归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

## 职责与数据流

原 Format 模型 reader 完整验证所消费的 mesh envelope、材料/part、XYZ、normal、tangent、UV 与索引，并复用同一 rig 验证 owner 核准骨层级和权重 → 同一 metadata/readParts 事实 → RuntimeSourceFacts → PreparedStaticModelResources → 原 StaticModelPipeline/shared scene depth → 唯一 compositor。immutable bind mesh 无新 pose、clock、renderer、资源池或普通帧解析；不经会丢Z/normal/material的二维 image Puppet 上传链，也不制造第二 LBS。

现 rig reader 若只需要 version/stride/vertex span，可提取一个被 mesh 与 direct reader 共用的最小 layout 事实，使原验证实现复用，不构造重复顶点数组或复制 parser。metadata 与真实 geometry 入口必须执行相同验证；需要缓存时复用已有 launch/resource 权威，不另建无界模型缓存。

## 有界准入与失败

首片限已证 MDLV0023 的单mesh/单material、80B顶点及完整同一 header/vertex format 0x0180000f、uint16三角索引；真实材料与通道原样保留。mesh附录须完整证明无额外stream/part/clipping并严格定位版本匹配的MDLS边界；不掩码flags、扫过坏mesh、补默认法线或重建tangent。原XYZ在声明bounds内、各通道有限/有界、索引与rig权重安全仍为硬门；未知flags/part/clip、截断或非法必需rig拒绝该最小模型。

几何准入与可选动画分开：只发布经过验证的 bind geometry 与明确 typed bind-only/degraded 状态；未读/不支持/失败的MDLA、reference或默认clip不得改记成功，不扫描跳过坏track。不完整理解可选动画不能代替必需mesh/rig的安全验证。既有static模型及image Puppet合同保持，材料、HDR/SDR、depth、取消与生命周期沿原消费者。

## 验收与退出

先以非零Z、非平凡normal/tangent和多面遮挡的自有模型证明原通道与shared depth，覆盖资源改名/等价实例、错误索引/权重、未知flag/part、截断及非有限通道反例；metadata与geometry结果一致。再用原模型实际prepare/encode/GPU/末合成与可归因主体ROI，保留动画失败；各取既有static和image Puppet健康邻例，不以白色替身或非黑判断成功。

无法证明完整所消费envelope/通道即不进入Rendering；实际bind画面仍为散片、错误几何或无明显主体收益则不关闭用户缺口，转入reference/默认动画能力。所有旧路径退出与能力结论只按实际证据更新，不扩成整体光照、动画/交互、官方同相位或性能验收。
