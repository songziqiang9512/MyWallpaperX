<!-- document-role: historical-evidence -->

# 属性 typed 候选复用收敛（2026-10-13）

> **历史证据 — 非现役入口**。优先级及未执行项归[属性卡](../roadmap/properties-panel-card.md)与[性能卡](../roadmap/performance-convergence-card.md)。

## 公共语义与实现

同次属性事务的可见性选择消费已经求值、校验过的candidate `userValues`，不再用effective dictionary重新遍历Program和validator。仅改原Session两处调用及private selector；没有新parser、cache、状态或owner。相同值仍保pending取消语义；资源就绪时重新apply最新committed state，整键cohort、sound/readiness、record/generation、多surface、particle与失败rollback不放宽。不是新增视觉规则，未引入样本/路径/hash或源码形状例外。

## 同条件局部成本

自有Session shell，`swiftc -O`，32/256/2048个绑定（两conditional Combo，其余scalar）；构造和warmup在计时外，诊断关闭。原/后三轮独立进程，getrusage user+system CPU计时；计数版未参与计时。改变值的每事务CPU中位数：

| 绑定数 | 原/ms | 修后/ms |
|---|---:|---:|
| 32 | 0.1972 | 0.0105 |
| 256 | 1.9354 | 0.0676 |
| 2048 | 19.5351 | 0.5328 |

改变值的求值/校验2/1→1/0，相同值1/1→0/0，四命令合并/取消周期11/7→4/0；各规模一致。9组workload/scale的最终typed值、revision、pending、resource与sound结果在六轮一致。收益来自省去重复validator及排序，不证明整个面板、App内存、启动或GPU下降。

## 行为、实际画面及边界

39个最近行为门通过：改名后的property/target/resource、mixed layer/effect Combo、合法/非法sibling、错类型/选项、同值取消、旧record/generation、readiness/sound/particle及失败事务。原18个pending intent回归保留，夹具拆分为资源support及行为harness，各自职责独立。原`scene-deferred-property-intent`门补登记两Swift fixture，避免fixture改动绕过行为门。

最终Developer ID签名Debug显式-O App，CDHash `249612a219c4df69e6160420afb9fab38a1b64e4`，产品源SHA `bacae33716e56f8077c81767c2c1e6cfea27569660b59216c00023a0142cb188`。四个现有App/Metal integration全通过：独立合并、局部取消、同键取消、非法编辑保留意图；ready/after蓝红目标与健康绿peer的完整ROI正确率1.0，同surface/window、一次candidate/activation且GPU正常终结。不用dispatch accepted代替最终像素。

两真实样本只读复制134文件，v3 marker保持；隔离库经原`SteamWorkshopLibraryTransaction.publish`注册索引，不另造ready路径。普通AppKit详情/属性→client→daemon实际播放3042492564：Cloud关后右下云层消失，人物、粒子及构图继续显示；恢复默认、关闭重开值和依赖行恢复，Strength三次编辑值均正确。受控单次Cloud编辑及三次scalar编辑均产生新startup/activation，**整场景重建仍未解决**。同daemon的六次session观测，warm prepare-end 6.24–7.38s；这是等待成本，不是本批改善量。下一批先区分App dispatch admission与daemon rejection，再查rebuildRequiredKeys、prepared active/unavailable cohort；现有日志无属性ack，拒绝原因未定。

未参与修法的2932157836正常桌面播放，Front AVR四次开关依赖行正确，窗口22331保持且未新增startup/session；日志有真实propertyInputApplied→effectConstant回调，检查最终人物、水纹、星星和媒体组件实际画面。未控制系统音频/媒体，不宣称音频环幅度、全部属性、官方parity或Release验收。既有两样本时钟缺失、304封面裁切及layer1128非有限返回仍开放；这些状态继续归[队列](../roadmap/scene-open-breakpoint-queue.md)，不因成本修复误关。

## 审查与保留

独立只读审查接受冻结产品/夹具及门映射；完整最终scope与证据身份另存回执。第一次Xcode初始化在DVTFilePath递归dispatch锁中停住，采样后仅取消本次PID；同命令一次重试完成，不计失败构建为通过。文档、最近行为及结构门与提交后检查见收尾回执。

CPU六轮、计数、源码身份与原始日志保留于忽略的`.artifacts/tmp/property-candidate-evaluation-20261013`；App/GPU/普通窗口证据在`.artifacts/tmp/property-candidate-actual-20261013`。停止后的App、副本、HOME/cache及临时可执行按本批清理回执移除，复用一份既有DerivedData；原媒体只读，不清未知或其他批的唯一证据。
