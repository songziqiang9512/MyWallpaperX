<!-- document-role: historical-evidence -->

# 已准备Puppet默认几何动态实例（2026-10-15）

> **历史证据 — 非现役入口**。能力归[SceneScript API](../capabilities/scenescript-api-coverage.md#prepared-puppet-default-instances)，边界归[D4](../roadmap/batch2/script-component-api-design.md#prepared-puppet-clone)，后继归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。本片没有性能或完整样本正确性结论。

## 通用语义与职责

动态图片创建可命中本launch已准备的Puppet模型，使用实际mesh及默认reference或exact bind几何，不复制源层动画、脚本或effects。准入限静态atlas、原普通单pass builtin image材质和已准备mesh；动画/effect配置的own或继承字段在journal前局部拒绝，字段查询异常保原owner撤回。普通图片不增加这些字段访问。

原prepared-device资源按mesh身份合并动画需求OR，一次读mesh/rig/attachments及按需轨道，分别准备作者pose与默认pose；初始bone读取和各surface安装消费同一结果，原产品重复读取退出。无reference的exact bind保shear/小行列式；rig/animation失败仍保原局部bind fallback，只有真正缺mesh允许原texture product fallback。新实例缺mesh不入catalog。

原DynamicLayerRuntime拥有候选与共同提交。surface只在committed topology revision变化时实例化或释放几何；每实例独立PlaybackState、physics/scratch、vertex ring、clipping domain及FIFO。共享AnimationPlaybackRuntime仍独占clock与sample，在advance前按自身negative definitions与committed live集合清退；即使旧surface已重建、没有历史ID差量也能退休。atlas经原setPuppetGeometry原子安装，只是采样资源，不伪造完成的quad publication。in-flight资源沿原completion保留。

## 资格、真实运行与边界

原2887542690的31次图片创建中25次普通命中，六次缺失为五Puppet与composition286。隔离临时诊断只读固定key存在性，核验完整普通prototype链，没有读取getter/值/脚本表达；六请求均未声明animations/puppetAnimationLayers/effects。五源mesh原本已成功准备，源声明动画不能被当作创建请求。诊断C代码已恢复原始SHA，不进入最终App。

最终Debug App executable SHA为`c377e58ec0274db7d58f62068f7f0f28acfa96ea081f53e7517a57bc56c90ccf`，实际代码载体debug.dylib为`06a50c56bbf610740b018663bf5980af3f591286b70885db34ca6af2ac247709`，CDHash `c6833cee7da522cd0d9d9651c8f6616134c039b2`。两个零调用按需读取工厂退役后，最终触发/heldout/双实例App均复验、产品源SHA无漂移，exit0且gpuDrained=true；原包默认另保前一冻结候选收据：

- 288原包默认：五Puppet创建取得独立geometry（一个bind、四个reference），33个动态层；默认选项下visible/encoded均0。五个Puppet所属origin脚本的创建异常消失，仍有composition286的visible-of-null，不称默认新增可见阴影。
- 同包隔离触发：仅将五源的既有`origin.scriptproperties.dropShadow`从2改0，其余entry字节保持，脚本表达未改。五动态Puppet实际visible/encoded均5，下一帧command buffer completed；实际图可见人物后黑色轮廓。默认/触发截图时间不同，不作逐像素A/B；偏移、轮廓与动画跟随未取得官方合同或parity，不能称完整阴影正确。
- 未参与修法的3232289987原包：九个作者Puppet几何成功，实际人物、头部/手臂组装及背景持续出画面，无SceneScript failure并正常drain。未验完整交互、提示框时序、全部效果与官方视觉。

自有800×600双实例App：early为黄色source及红/青两个真实三角；3秒后仅红实例右移且横向宽度303→453像素、着色面积91507→137259，三角fill/bbox约0.5。9秒删除红实例及source后红/黄像素归零，青实例仍完整绘制；青ROI在四阶段字节SHA相同。实际两GeometryProduct/world draw及command buffer完成；stop后timers/jobs/mutations/dynamicLayers均0，surface与GPU排空。source的合法clip是反继承邻居，不证明新动画实例能力。

## 验证与审查

完整生产LayerLoad/PlaybackState/readers/evaluator及PreparedPuppetResources CPU门6/6通过：同mesh需求OR正反序与改名、source/default隔离、reference/cached骨骼完整层级、exact bind shear/小行列式、删除输入后复用和缺失/读取/解析/路径/rig/轨道失败。新门不创建任何Metal对象；旧rig getter源码切片退役，其数值断言迁入完整门，reader门14通过、一个可选real-data跳过。

真实Swift→C catalog门3/3通过，覆盖默认/改名、own及继承配置拒绝、getter不读值、Proxy异常与journal discard、健康peer及ordinary不受影响。runtime、原prepared ordinary image与geometry mapping相邻门32/32通过，包含same-cadence peer冻结、无surface历史的清退和后继继续。

独审发现surface历史控制launch退休的P2，已移回共享runtime按committed成员裁决；最终产品审查无剩余可行动P1/P2。Debug build、代码健康、布局、防御面与design gate通过。原SourceMaterials→RuntimeCatalog依赖门失败仍在，未改baseline或捆绑修复。buffer publication门14/14、clipping pool门5/5通过；buffer原DEBUG harness缺计时hook编译失败已修为明确禁用的外围诊断适配，保留真实Metal encoder/draw/publication及首轮失败证据，没有重跑App。

## 未覆盖与材料

显式动画/effects、任意新模型或脚本、动态atlas、composition实例、负ID动画/骨骼API、HDR/多屏实际呈现及官方一致性继续开放。CPU复用和状态退休不等于已测内存、GPU、启动或能耗收益，本片不作性能声明。

材料根`.artifacts/tmp/prepared-puppet-design-20261015/`保存精确输入、source/App身份、最小日志及必要截图；真实媒体只读。连续迭代仅留既有`.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData`一份构建缓存。证据cache先前已达1GiB预算，不提高预算或删除未知材料；本片必要材料约20.1MiB暂留任务根，promotion再次因总预算拒绝、prune无可删包。已清理约698MiB临时HOME/样本/缓存与冗余运行输出，完整旧日志压缩保留，最终必要截图限量留存；原包四文件终检SHA未变。
