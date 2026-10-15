# 变体缓存集合 wire 修复与源纯补齐短筛

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**

现役职责归[缓存合同](../architecture/variant-analysis-cache-contract.md#variant-analysis-wire)，选序与性能验收归[性能卡](../roadmap/performance-convergence-card.md#sampler-seed-preparation)。本记录区分保留的通用正确性修复与未达继续门的性能原型。

## 保留：集合顺序不能决定合法记录是否命中

原 owner 的有界探针复现：七元素 auxiliaryDataSlots 的有效记录同进程和 fresh reader 均可能 miss，singleton 控制命中；文件未变，按原 wire 数组顺序计算的载荷摘要匹配。问题是合成 Codable 将数组解成 Set，随后重编码的枚举顺序变了；`sortedKeys` 仅排序 object key。它证明错误可能，不证明真实壁纸受影响比例。

修复只改原缓存 owner：五类私有 Wire 保原数组顺序先校验旧 v22 摘要，再映射 Set；新写仅排序9个明确的 Set 字段，其他有序数组不改。schema/key/目录、成功发布点和损坏 safe miss 均保留，无新缓存、回填、常驻表或准入 owner。真实 consumer 的 graph/格式/purpose/context 判断继续原链；不申报 CPU/RAM/首帧收益。

SetOnly 小门2/2通过（2.964s，一次真实 Cache+Support+值壳三源编译），覆盖两份自有旧 wire、新写跨进程、五类集合排序、非集合有序邻项及损坏/key/版本/载荷篡改的只读 miss。旧 binary 的原随机 miss 不称已修复。撤回前真实 Color/Provider 四门通过；最终仅保 Set wire 的差量经独审确认。Debug 构建22.355s，4298输入无漂移，最终 App SHA `d6180c82723edb3ad9f2783ec701c2ec057b7f2f889e77b9c5a762c850dab8d2`。最终原生304星空/塔/人物/时钟、独立324蓝粉粒子球/时钟均实际查看并有首GPU完成及后续播放证据；304只认Quit退出（71/71 VM quiescent），324实际Stop后Quit（17/17），两次正式App exit0，六个本轮PID全退出。两份source verify均exit0、原件/副本变化为空；核验前只恢复setup移出的复制品ownership marker，不覆盖新文件。304首轮复制品discovery前置失败独立保留，不当渲染或性能样本。完成帧计数、最终pin、全部画面/parity未验，1128既有badReturn仍开放。

## 撤回：源纯结果兼容扩展

一次资格测三入口 inclusive worker 区间和6559.573ms，只允许继续归因。随后 B 原型在同一 v22 文件外层增加独立版本/完整性摘要的源纯投影，仅成功后同 key 补齐；negative、空集合与逐节点准入分离。小 wire 门、实际旧 reader 的外层兼容控制及真实 consumer 冷暖/反例通过，原型仍须通过预锁 App 继续门。

单对 Debug：基线 `3de90bc4…`，候选 `c05566f7…`，均启同一 opt-in，原样轻376→重304→中293→重304→轻376，60FPS/mute、独立进程/HOME、同字节缓存种子各自副本，无 sample/profiler/截图。A2 request→匹配首帧17477.140250→16075.542250ms，候选/基线0.9198039278765873，下降8.019607212341274%，低于实验前10%继续门：**STOP，不扩五对，不接受稳定收益。**

候选A1 prefix294/294、projection0；A2 prefix及projection均294/294，三入口尝试294/294/294→0/0/0。基线A2入口累计6652.618ms仍是重叠worker区间和，不是可省墙钟或CPU；基线未导出prefix命中数。两臂A2 archive均暖命中、无新编译operation，原发出的准入事实和实际消费prepared token一致；这些不证明全variant census或像素一致。两臂均正常退出且gpuDrained=true，PID/observer已退出。CPU采用严格相位内的Python receipt样本，两臂覆盖时长不同且含旧景播放，不计CPU百分比；观测内存不计稳定收益。原型未做原生视觉验收，不外推兼容/Release/GPU/功耗。

完整源纯扩展、回填、三入口计时和cache命中诊断均已撤回，窄设计登记退役；顶层合同只保集合wire职责。该三入口不再惯性实现共享Unit备选或追加微调，除非新的实际热点/分母支持。其他未修视觉、GPU片元、长期切换/最终pin和属性专项保持原状态。

## 证据与产物

有界原 wire/旧reader、小门、源码冻结、独审及原型源码保 `.artifacts/tmp/variant-analysis-cache-wire-20261015/`；单对原始协议/缓存起点清单/日志/receipt在 `.artifacts/tmp/variant-analysis-source-pure-20261015/`，单对主要结果 `pair-result.json` 与 `screen-summary.json`；最终 App/native 证据归 `.artifacts/tmp/variant-analysis-set-wire-20261015/`。已清理两臂停止副本、三个缓存视图及退役D/E staged App，共990641992逻辑字节；原始收据和源码均保留。两份已停止native副本另清399844479逻辑字节，总计1390486471；保两张必要实图、原日志/前置失败与身份/退出/源校验小收据，最终SetOnly App仍留给后继对照。共用 DerivedData/既有 shader cache 与独有GPU失败证据保留，不复制至近满的受管缓存。
