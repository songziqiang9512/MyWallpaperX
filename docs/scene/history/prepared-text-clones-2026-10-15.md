<!-- document-role: historical-evidence -->

# 已准备文字 wrapper 的独立动态实例（2026-10-15）

> **历史证据 — 非现役入口**。语义范围归 [SceneScript API](../capabilities/scenescript-api-coverage.md#prepared-text-clones)，设计归 [D4](../roadmap/batch2/script-component-api-design.md#prepared-text-clone)，后继归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。不计性能收益或完整样本正确。

原 createLayer 未消费 Object text wrapper；现在复用本 launch 成功准备的完整作者模板，value/user 不新建 VM，script 每次读入可信已编译载体形成独立模块，返回 handle 前完成 init。source 不重复编译/init；源码、wrapper 元数据和当前 prepared 输入必须对应，不按样本或源码 hash 选择行为。

## 原执行链与局部失败

C catalog/creator journal 暂持 child，父异常、预算或后置 typed 拒绝原子撤回；共同提交后，仅按 DynamicLayerRuntime 接纳的 live layer/template map 交给原 StringProgram。输出、用户输入和显式 setter 仍进入唯一 typed snapshot、TextTextureStore 与 compositor。birth 的 init current 与作者 seed 分离；后继 update 保独立状态，纯 user 复用原 property producer，值编辑不重建整景。

原 retire 回收 quiescent 负 ID binding、索引及派生缓存；timer snapshot 强持捕获时的准确 owner，删除中间 binding 后恢复/丢弃不再错配。旧 snapshot 释放后 child 可回收，不增退休队列。动态 layer 原 ABI 的4096 UTF-8字节/无NUL约束在最早局部输入/返回边界执行；非法 user 值从原 evaluation transaction 保安全 current，普通作者 String 的65536合同保留。

产品的 particle frame 覆盖整个 cadence，不能把 active scope 当作文字创建禁令。同步 child 构造/init/失败销毁在词法 scope 中暂抑原 emission/boundary hooks，并还原父 hooks/opaque；native work/reservation 不重置。child 播放/emit 在 native preview 前 sticky 拒绝；父 prefix 与健康后继保原事务。没有第二 VM、模拟或输出 owner。

## 验证和真实结果

最终 Debug App SHA：`4db953c85fae03b0d35aedc8bda2ccd7971acfef3ec5ba226064f82b067b32a3`，产品28路径构建前后无漂移。最终 C 12路径 aggregate `8a57d17a82c11893d0b217b3b2e4203937c2cf5c269e3f93e3386d8a3adf41c8`。聚焦门：prepared clones 15项（59.829s），direct Runtime 17项（3.769s），原 String lifecycle 4项（56.889s），evaluation transaction/frame routing 15项（2.512s）。变体含 wrapper/key顺序、null user、改名、双实例、getter/Proxy/改后未知模板、坏返回/健康peer、父throw/晚拒、sort/TEXT ABI、同帧生灭、jobs/depth、4096/4097/NUL、持旧timer snapshot多轮回收。

独审发现并定向核对了 TEXT ABI、sort身份、同帧生灭接管、null user、字符串失败半径及产品particle scope六个问题；最终静态无新增P1/P2。particle门用真实domain scope及记录型native回调，证明C prefix/64字节reservation，不等于完整模拟器或module-time caught命令的独立动态验收。

真实2887542690仅在隔离副本把作者887/318/640已有 dropShadow 从Off切Static，其他作者字段、源码和资源未改。三条文字create不再null；clock script clone与两个user clone进入真实动态文字发布。逐帧原图可见黑色时钟文字从19:25:55推进至19:26:03，用户文字由 Wallpaper Engine 改为 CLONE ALPHA/BETA/GAMMA，原生同窗口39948三次热更新均接受，未重启surface。原字符串与clone的排版/字体切换仍有可见差异，不称逐帧对齐或官方parity。Stop后41 owners quiescent，timers/jobs/mutations/dynamicLayers均0，GPU drain完成。

未参与修法的3042492564原包实际显示角色、星空、时钟和日期并正常drain退出；仍观察到544 effect color的event未定义与1128 origin非有限向量，未把它们计完成或称整样本PASS。首个候选的该样本冷准备120s未ready并终止，原日志保留；最终沿同隔离cache验画面，不计启动收益。两份真实原件的project/pkg SHA均保持。

## 未覆盖与材料

仅接受本launch的prepared模板；任意新源码、完整动态配置getter、子async job、depth>1及未接media/cursor/audio模板不开放；不能保target的child命令贡献局部拒绝。同pending动态record的跨creator/property-owner setter冲突仍拒后者。prepared字节占原heap，极近上限的容量竞争未声称零影响。

288的五个Puppet与一个composition clone仍局部null/六个origin异常；黑遮挡、字体/偏移/布局、完整交互、HDR/多screen和官方整图正确性继续开放。owner回收不等于已测RAM下降，本批无CPU/GPU/RAM/启动/能耗收益声明。

证据根 `.artifacts/tmp/text-wrapper-clone-qualification-20261015/`，`report.json`保存精确App/source/input、最终门与native身份；首候选、carrier诊断RED及最终日志保留。所选四张最终原图和日志合计约30.5MiB。promotion按既有1GiB预算拒绝（现cache约1029MiB，prune-expired无可删包），未提高预算或删除未知证据；必要材料暂留本任务根，待已登记材料审理后晋升。构建仅复用本任务唯一DerivedData，临时HOME/样本/编译carrier按本轮清理收据处理。原SourceMaterials→RuntimeCatalog依赖门失败未改、不扩baseline。
