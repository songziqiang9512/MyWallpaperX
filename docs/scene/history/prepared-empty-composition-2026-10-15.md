<!-- document-role: historical-evidence -->

# 空composition原型资格与撤回（2026-10-15）

> **历史证据 — 非现役入口**。设计归[D4](../roadmap/batch2/script-component-api-design.md#prepared-empty-composition)，后继归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。结论为NO-GO：产品与测试原型已撤回，没有新增支持、原包画面恢复或性能收益。

## 问题、实验与停止理由

原2887542690的composition模型已被识别，但未进入动态图片catalog，create返回null。请求资格只读固定key存在性，覆盖普通完整原型链，没有读取getter、作者表达式或任意序列化；copybackground、config、parent、children、dependencies均省略，旧同输入证据亦无animations/effects。该资格没有裁决perspective值，不足以证明真实请求属于“空组且无透视”。临时C观测已恢复原SHA并退役。

隔离原型泛化同一prepared-resource模板与kind，沿原C catalog/journal、Swift共同候选、typed topology及utility顺序建立空composition；不复制源层成员、效果、脚本或图片publication。自有省略profile的状态与退休正确，但真实请求触及另一消费者缺口：

- 中间App允许constructor override，PID13160的目标origin回调完成；随后的共同bundle拒绝明确为`target=286 kind=composition requested=Optional(true) authored=nil`。完成VM回调不等于提交，原有33动态层也不证明新composition已生效。
- 独审发现动态factory亦会保存透视Bool，而实际utility camera恒为screen-space。补齐相邻拒绝边界后，constructor override在出生前返回null，PID14946原请求恢复为visible-of-null。该A/B证明请求携非省略override，但未观察constructor实际Bool，不能把它写成已证true。
- 原authored guard不能删除；固定false镜像也无法消费已证true。背景采集当前三角affine UV、回绘、第四角及cursor合同仍未知，不能借空组无像素忽略配置。

省略窄片没有改善真实请求。为避免交付无实际收益的基础设施，20个产品/测试文件全部按冻结基线`1366789d3a1f60c01dbc9df1bb7f83a357f130ac`字节恢复，原型diff、SHA与结果保留。未归属的project.pbxproj改动不动；设计登记改为重启前须补透视消费者设计。composition创建与更广视觉/交互问题继续开放。

## 有效证据及其限度

自有1200×800原生场景先创建两个空组，立即读写属性并排序，通过有效handle控制红色peer：首图红块隐藏，4秒图在中间位置，后继在右侧位置；健康青块ROI全阶段SHA一致。销毁分支后仍到达后续getter/setter与移动，没有VM异常，surface/GPU正常排空。7–9秒黄色过渡未被3秒采样命中，不补报黄色像素或逐帧动态计数。空组自身没有新画面、capture或材质输出。

最终原型Debug executable SHA为`4ef4eb2058e79a91d70af37355ae2f5a0b20f5f3c8b64868f7b94746f65eab49`，debug.dylib为`6ba587b0e20f13020886142404a0c8808045b216fa3b5f7bc0f2046d35de55d6`，CDHash `df829412b64686a040091a3d6e6fb65357363da8`。自有PID14675与原包PID14946均exit0、App drift为空、gpuDrained=true。原包最终仍缺composition，不计收益。

独立3232289987原包在最后constructor拒绝边界之前的App运行，PID11237持续显示人物、头部/手臂组装与背景，无SceneScript failure并正常排空。该证据仅保护原型中的既有Puppet/图片/utility路线，不冒充最终App全组合验收。撤回后产品字节仍为基线，不额外重建或重跑全矩阵。

CPU门VM/ABI4项与完整parser/projection12项通过；最终边界轮共16项、192个输入源前后drift为空。覆盖kind、改名/opaque asset、8字段own/inherited presence、getter不执行与异常/Proxy、throw/discard、排序/销毁、独立几何和不继承source；另验constructor透视own/inherited false/true均在出生前拒绝、后续省略创建仍为首identity与ABI2、factory非nil反例。它们不证明GPU或官方透视合同。中间fixture适配失败和最终收据均保留。静态独审促成透视边界收紧与本次撤回，不以测试通过保留无真实收益原型。

## 后继与材料

公开资料未裁决composition透视或动态背景缺省；官方普通image/text黑盒不能外推。本项重启须有可见正控制、非零深度/倾角和透视false/true对照，再设计同一采集/回绘消费者。下一项优先N08十个可见RopeTrail的world方向与负subdivision行为资格；不能abs/clamp或只放宽profile。属性已证小洞多数已闭，待验组合与性能卡继续保留，真实大成本/回归触发性能专项。

必要输入身份、原型patch、最小失败与像素证据暂存`.artifacts/tmp/prepared-composition-20261015/`；请求资格与测试收据在`.artifacts/tmp/composition-create-qualification-20261015/`。真实媒体终检SHA未变。原型App、复制样本、临时HOME、生成shader/raw runtime JSON及重复PNG当轮清理，日志压缩保留；仅既有`.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData`一份连续构建缓存继续复用。证据缓存按原1GiB预算处理，不加额、不删除未知材料；本轮移除约440.9MiB可重建逻辑字节（含撤回App），主证据根约13.7MiB、资格与测试根约9.9MiB暂留。promotion因既有总预算拒绝，prune无可移除包，未扩大预算或删除未知材料；细目见任务根cleanup/promotion收据。
