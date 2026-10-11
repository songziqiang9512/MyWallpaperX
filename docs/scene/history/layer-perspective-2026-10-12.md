<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。职责归[脚本覆盖](../capabilities/scenescript-api-coverage.md)，未完成项归[断点队列 N06](../roadmap/scene-open-breakpoint-queue.md)。

# 图层透视状态进入共享相机链（2026-10-12）

## 通用语义与结果

基线 `766db850` 的脚本 `layer.perspective = Boolean` 只是 JS 自有属性，没有绘制消费者。本片把 getter/setter 接入原 QuickJS journal、Swift owner bundle、typed snapshot，再由现有 camera/geometry、cursor 和 attachment 消费；不添加视觉 profile、投影算法或第二套状态 owner。现有动态 image/text handle 同样可修改此字段，createLayer 配置读取仍未扩展。

继承默认与显式 Bool 分开存储。首次写入与当前默认相同的 Bool 仍成为显式 override，后续相机切换不吞作者意图；已显式同值沿既有 no-op 规则。独立审查发现 scene fallback 与可见 default camera layer 的默认判断可能不一致，现将原相机选择函数移入共享 camera owner，双方使用相同 prepared world frame 与 typed visibility。没有增加动态相机算法。

2887542690 的前景、背景和窗口/标识现在可随作者旋转呈现透视倾斜。之前已接通的25个普通图片创建目标继续执行，但本片没有增加资源准入：5个Puppet资源仍拒绝，composition286在更早的无透视consumer边界拒绝，仍共6个失败owner。3个text clone的wrapper缺口也未闭合。原25/34约74%是上批创建目标接线进度，不能拿来表示本片或整样本画面正确率。

## 变体、反例与证据边界

- 新字段使用API语义与typed layer类别；没有按变量名、资源名、路径、hash或固定脚本形状选择算法。本批没有新增兼容例外。验收规则和集中例外登记归[开发工作流](../development/development-workflow.md#compatibility-exceptions)，空表不表示已审计所有存量。
- C/Swift门覆盖变量与资源改名、等价Bool表达式、非Bool及无几何consumer反例、继承/显式值、相机图层默认、同帧读回、throw及Swift拒绝撤回、旧handle、动态层与健康peer。判据包含实际typed snapshot和矩阵消费者，不能仅以mutation/profile出现作为通过。
- 自有官方2.8.0.42实验：正交 image/text省略值为false；Bool同callback和重新lookup可读回；所测number/string写入被忽略；false→true→false画面与相应静态参照ROI完全一致。官方setter后throw仍保留新值，本项目继续执行整个owner bundle原子撤回，这是明确的项目事务约束，不宣称该项parity。
- native同输入隔离App的false→true→false让有深度/旋转几何变化并返回原几何，z0平面控制保持不变；旧App各阶段没有变化。原生缺省FOV下与官方仍有投影差异；官方同fixture显式95与省略值截图一致仅是有界事实，不能外推完整默认公式。本片不改FOV数学。
- 独立样本2890473419未提供给实现者调参；最终真实截图检查场景及侧面人物存在，提交/完成/呈现持续推进。它仍有3个特殊资源拒绝及4个undefined.visible错误，均在修复前存在。动画相位未锁定，不把所有前后像素差归因于本修复，不报整样本通过。
- 3761619125复验保留既有deformer链，115个唯一首帧阶段（78 material、37关闭透传）均succeeded且GPU completed；只有39个最终阶段标记compositorConsumed，不能把中间/透传阶段说成直接消费。静音fixture不能验真实音源；direct Host不能替代普通桌面dispatch、全属性交互、长稳/能耗或完整官方视觉验收。

## 验证身份与后继

证据根 `.artifacts/tmp/layer-perspective-20261012`。`product-final-identity.json`绑定最终源码与Debug App，`*-final-launch.json`绑定输入SHA、命令、App、进程退出；`runtime-comparison-final.json`及`native-geometry-final.json`记录真实运行结果。官方中性合同及原始量测在 `official/`，不消费参考项目私有实现。最终冻结清单、独立审查与提交后身份另保留同根。

Debug build、定向VM/快照/相机门及结构/依赖/防御/文档门结果见同根收据；构建或规则通过不提高上述画面验收上限。仅保留一份 `.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData` 增量缓存；本轮样本副本、HOME及重复中间截图在完成后清理，最终证据保留清单见 `cleanup.json`。已释放约1.00 GB本批临时产物；标准晋升因既有总缓存预算拒绝，受控prune无可清项，因此保留有界唯一证据于原根，不提高预算或删除未知资料。既有218字节 `.mimosa` 与Xcode自动格式变更的project文件均未清理或混入本批提交。

下一项优先查 create size 与 text wrapper 的公共输入边界。缺省FOV偏差、动态初始配置、特殊Puppet/composition clone继续列队；2960821850与3113287126仅被静态扫描发现有显式透视而缺override，尚未验证实际受影响。不按这些编号扩算法。
