<!-- document-role: stable-contract -->

# 动态图层容量与事务存储

> 原owner的容量与按需存储已实施；限定结果归[后验记录](../history/dynamic-layer-slot-lifetime-2026-10-29.md#capacity-storage-20261101)，未闭能力归[唯一队列](../roadmap/scene-open-breakpoint-queue.md#dynamic-resource-recipe)。当前能力以[SceneScript覆盖](../capabilities/scenescript-api-coverage.md)为准。本合同承接[D4](../roadmap/batch2/script-component-api-design.md)，不定义第二套图层、时钟或资源 owner。

## 目标与首断点

合法的普通图片脚本可在一次初始化中创建数百个图元，并在同一 callback 内销毁旧组、创建新组。此前 C live动态层/单callback journal、Swift ABI及候选各限256，Runtime实收owner记录限512，低于已知512段首建及1023条重建需求；本设计用原共享槽边界替换这些相互冲突的限制。

四组 layer journal 此前嵌在每个 C owner 内，合计136 KiB；增大静态数组会把最大容量成本乘到所有 owner。该数字是结构 requested 大小，不是实际物理内存收益。此前普通终态还无条件清零4096个created索引，count归零后无消费者需要这些旧字节。

## 唯一职责与数据流

`prepared image/resource + owner alias → 原C handle/journal → 原Swift owner plan → typed snapshot → 原provider/compositor`保持不变。C domain 仍拥有4096个总 layer slot、原free list及8192条拓扑操作；authored与dynamic共享槽，退役槽仅在现有共同事务/snapshot终态后回收，不保证4096个live dynamic。

- 将现有总槽常量放到原公共C头供内部及Swift消费，C distinct journal与ABI导出沿用这个物理边界；退出重复的live动态256与Swift候选256门，不加另一套动态层计数器。
- 保留Swift Runtime对实收DTO在本处coalescing前的owner记录工作界限并扩至4096；它区别于C槽位容量。Program已合并的同字段写入不会重新展开，不将此界限冒称所有callback原始写次数的累计预算；Runtime收到4097条时仍先拒绝，不能在本处先合成一条绕过。其它particle/media/cursor消费者的独立界限不随之扩大。
- 原created索引、dynamic旧值baseline、authored staged及authored baseline四组buffer改为pointer/count/capacity，按实际append增长并在暖态复用；capacity仅为分配元数据。无写入的owner不为它们分配最大payload。不增加wrapper、身份表或并行journal。原mutation baseline是唯一prepared读值来源；退役没有caller的旧单目标baseline setter/clear、字段及失活fallback，同时把单caller scalar转发并入原primitive入口。
- append先确保空间，再发布新条目/槽位；失败沿原owner局部失败/取消路径退出，不遗留未登记出生。参数读取中可执行JS时不持有会因再次append而失效的buffer裸指针。
- 普通callback/commit/discard只清理active条目的owned字符串/效果和count，退出完整created数组memset；永久teardown成功及owner销毁释放storage，等待peer/snapshot的原重试边界保留。

准备期资源资格、实际model尺寸/材质及owner alias仍由原资源链决定。缺资源返回null不等同容量失败；不补虚假资源、不按样本/路径选择规则。alignment/parallaxDepth等未接几何不因容量通过而记成支持。

## 取舍与验收

静态扩大数组会增加所有owner常驻分配；按需存储用少量capacity元数据保留原count和生命周期。domain catalog与拓扑数组本批不改，避免移动仍被handle/journal引用的LayerRecord。每次create的重复live扫描退出；原导出/排序成本须测，不先新增dirty索引或另一份映射。

1. 真实C及C→Swift门覆盖首建511+原层写、init与update同cadence、同callback销毁511/新建511、Runtime实收DTO工作界限、改名/等价输入，以及缺catalog/alias反例。保真实初始化时序，不拆帧制造通过。
2. throw、late owner拒绝及frame rollback保旧图元、值和顺序，健康peer不受牵连；反复重建复用原slot，不提前复用旧handle。teardown及重试释放原owned payload和新增storage。
3. 测不写journal的owner、一名writer增长及同高水位复用，区分requested/usable与phys_footprint；同条件重复测普通空闲帧/同输出负载，不以更大容量或结构行数当性能收益。
4. Debug构建后，以原包实际prepared资源/alias及可归属音频段ROI证明512段进入原渲染链，另验未参与修法样本。仅C预装模板、日志PASS或非黑不授整样本完成。

若下一首错是资源准备、未接属性、renderer或普通帧成本，先记录并重新选序；不放宽失败处理、改视觉算法或继续堆上限来掩盖它。边界验收不能外推为完整样本、官方parity或整体性能收益。
