<!-- document-role: active-plan -->
<!-- retirementCondition: Collision Bounds 的有界执行与可见验收由粒子能力表接管，剩余 profile 明确归属后归档。 -->

# 粒子壁纸边界碰撞设计

## 目标和裁决

补齐作者 `collisionbounds` 的实际运动行为。当前名称落入 unsupported；真实系统省略所有参数，不能猜默认动作或用 emitter 出生域代替碰撞边界。官方公开 Operator 文档将该组件定义为壁纸外框，并列出 Bounce/Slide/Stop/Delete；默认序列化字段、触边判据与坐标关系需固定客户端的自有对照裁清后才实施。

本项比继续扩调试UI或微调已执行的噪声更直接补齐真实样本缺失行为。最小交付是省略参数的真实 profile 从声明进入现有模拟与合成，边界位置、动作和健康邻层均有正反例；不为通过测试缩成与实际输入无关的孤立数学函数。

## 唯一职责和数据流

`DefinitionParser → typed collision declaration → prepared operator plan + existing frame geometry → Simulator → existing particle runtime/geometry → compositor`。作者字段只解析一次；场景尺寸取现有descriptor，相机/图层变换取现有canonical frame，不新建clock、graph、事件队列、资源或渲染owner。CPU只消费准备好的边界与参数，不能每个粒子重解图层树或转换JSON。

保留既有Plane Collision结果和失效边界。碰撞操作遵守作者operator顺序；若需要删除，沿原step死亡收口清缓存、发事件并稳定压缩，不直接移除索引数组、不改age/lifetime伪造自然死亡。自然短寿命粒子的单帧可见策略不能无证据推广到碰撞删除。snapshot/restore、prewarm、child事件和停止语义仍由现有owner承担。

有效边界与行为必须共同准入；未知或畸形profile仅跳过对应operator，保留其他健康组件。退化变换、非有限候选拒绝最小不安全更新，不能将坐标转换失败当作零边界或删除所有粒子。

## 待定行为及实施门

固定官方2.8.42自有同场已证：省略字段为Bounce；unit/inside-born以中心触边、法向约半速反向、切向保持；外生也受影响。输入与18张自有截图经独立审查，三轮scale对照的碰前速度/尺寸一致，碰后却不一致：0.5快速内移，1.5/2/3持续显示边缘片段，非均匀5/8在顶部零碎回归。片段质心不能当完整中心或速度；不据此恢复公式、添加scale阈值分支，或把自然affine反弹称作真实系统已修复。

四轮自有对照在此停止。零速度、无Movement的外生probe在1.25/1.75/3.65/6.55秒四相的可见span相同，但bounds/无bounds位置不同；1.25秒前与采样间过程未知，不能反推出公式。输入、四图与像素经独审，不解决既有scale反例。重开条件为能解释并检验unit、scaled及outside-born反例的公共合同或共享坐标方案；必要时仅做有界producer/consumer职责调查，不接收私有算法表达。当前保留891未完成，转向有真实反例的隐藏文字属性准入修复。

本设计暂不批准产品实现。证据返回后在此记录实际准入和失败半径，再更新设计登记；未知动态/透视/child组合不能无条件标为支持，也不能靠按样本或path分支绕过。

## 验证和退出

新增小型行为门穿过真实parser、prepared plan、simulator，覆盖四边、角、外部出生、变换、作者顺序、时间分区、非法输入及旧Plane控制；按实际动作补死亡/事件/回滚。Debug build后用隔离自有probe与真实样本验证实际GPU与最终合成，官方VM与原生App串行。若真实profile仍无法正确执行，就继续纠正合同/接线，不以仅单元通过完成本项。

最终独立只读审查冻结diff与证据；提交后重新校验HEAD并清理临时副本。进度按目标样本的执行和可见正确性分别报告，不以组件接通代替完整画面正确率或性能收益。

自有官方证据保留于 `.artifacts/scene-evidence/runs/particle-collision-bounds-20261005/final/samples/3780119725/runtime_evidence.zip`（SHA256 `43c329dacc75fd16ea5f22b7a9354b64b626c468054b19b7c2595f05dd9e34bc`，147293 bytes）；未解决反例受保护。官方主进程/config身份未改，研究窗口精确关闭，VM恢复入口suspended。没有产品实现或样本画面改善声明。
