<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# 新分配目标的正常 completion 交错（2026-10-06）

> **历史证据 — 非现役入口**。稳定职责见[运行架构](../architecture/runtime-architecture.md)，下一步由[RF05卡](../roadmap/batch2/reference-evidence-implementation-cards.md)拥有。

基线 `f79e6455`。339启动后第6帧临时分支探针确认 `prepare` 失败来自 cache revision 漂移：reset epoch 相同、未尝试回收；没有证据表明这次是物理分配失败。另一轮探针未复现，属于交错时序问题。探针及调用栈代码全部撤出产品。上一批全cached复用之外，mixed/new allocation仍把正常GPU完成释放pin当成整批失败。

成功物化只要求同epoch，allocator在准备前后沿原cache锁重新预留并核对cached/reusable/history/shared-pair身份；原admission和commit继续验证资源、顺序、预算并pin。shared-pair发布在原锁内核对初始完整pair快照的generation或真实缺席，禁止覆盖期间出现的新pair，再走原预算stage。实际factory返回nil仍只允许一次严格expectedRevision回收；不能采样外部修改冒充自有回收。不增加owner、配额、输出路径或样本算法。

真实cache/Metal反例覆盖owned/shared mixed批次在reservation之后或成功factory内释放实际外部pin、新shared-pair提交前的pin释放，以及reset/并发pair替换拒绝。旧版新增断言8项失败；最终36项池/恢复门及修正后的静态源反例共37项通过；此前其余14项copy/history与runtime bridge检查通过，合计51项的覆盖结果分两次取得。相邻静态源harness的alpha仍声明let，与现役产品可变uniform不符，已单行纠正，未改断言。Debug build、代码健康、设计、防御及依赖门通过。目录布局门通过；结构inventory门另有既有失败：SceneGraphPreparationAdmission使shape计数66而基线65，隔离导出未修改HEAD同样复现，本批不提高基线掩盖它。

最终签名候选dylib `0e42e7232def9f2f87a96ec7e7548407a72bb6f3006144c9caaa8430672b419d`。同339原包/default属性、自有标题/歌手/红封面、60FPS、55秒direct Host：`frame-target-plan-allocation-failed`为0，exit0且gpuDrained；25个material effect实际GPU执行完成，12个末端effect结果由compositor消费。截图保留封面、标题、歌手、音频线及背景。该轮部分时间与相邻harness编译/执行重叠，不作性能比较；另有3个dropped，不能声称所有丢帧消失。此结果不证明全样本或官方parity，真实音频输入未固定；339整体仍约70–75%/低置信。下一步继续339真实音频模式及剩余可见分支，再按用户顺序处理HDR/SDR和重型启动。

证据包 `/private/tmp/mwx-early-targets-20261005/runtime_evidence.zip`，5,204,700 bytes，SHA256 `e911f75ce2ea807ed84b43fd524c8e78f6e2778196a91dce95ea4c4ed334a42b`；原证据根接近总预算，临时限14日保留，不提高额度。提取后清理本轮运行HOME/截图重试及旧候选，保留当前候选、原样本测试副本和同任务唯一checkpoint缓存用于连续音频验证。
