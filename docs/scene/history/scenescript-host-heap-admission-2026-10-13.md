<!-- document-role: historical-evidence -->

# SceneScript 有界 host 容量与原包开场恢复（2026-10-13）

> **历史证据 — 非现役入口**。当前断点归[队列](../roadmap/scene-open-breakpoint-queue.md)，容量与失败合同归[D4](../roadmap/batch2/script-component-api-design.md)，后续成本收敛归[性能卡](../roadmap/performance-convergence-card.md)。

## 问题与归因

用户发现3662790108停在应为过渡的首屏，未来文字全部叠上来。84fe33b9（BC与PKG性能批之前）、803928ca及PKG候选均能绘制，却没有有效脚本owner；开启执行观测或取消性能驱动也失败。因此这两批性能改动不是该首屏问题的起点。准确引入commit仍未确定，旧JUNO导航证据使用修改作者脚本的fixture，不能证明原包自动开场曾正常。

仅投影枚举与数值的原包诊断证实：计划935个合法owner，在第742个owner的layer host安装阶段失败；mallocBytes=16,777,168、mallocLimit=16,777,216、usedBytes=10,957,991，code=memory-exceeded。后续4096累计construction额度耗尽是重试的结果，不能用重置次数修复。全域停用后作者动画和文字显隐不再更新，最终输出仍绘制静态输入，形成首屏叠字。

## 唯一现有链路内的修复

保留原ScalarBudget、QuickJS域、owner handle及typed更新链。默认JS heap为有界32MiB，不预分配、动态增容或按样本身份选择；默认native transient独立保留16MiB。自定义预算省略native参数仍继承其heap，兼容原调用；显式native参数独立生效。4096 construction、source、stack与interrupt限额不变。

选择有限容量而没有改成lazy/prototype API：935个owner的既有host表面包含大量独立C closure，单纯共享heap外native载荷不能解决JS heap耗尽；lazy方法会改变现有data property及保存method语义，扩大本批风险。后续实际成本优化需另量，不能以增加上限冒充性能收益。

compile-only、engine-bind、namespace与handle安装复用同一native失败分类入口，仅读Error自有data message，不执行作者formatter/getter。真实Error与NULL OOM保memory类型；未知无新异常失败不借旧pending升级为OOM。四入口保存旧pending，仅以新异常拒绝成功值，成功恢复旧异常；失败分别释放module/object或恢复engine并沿原owner销毁链退出。作者EvalFunction/rejectedPromise保原路径。失败才保存phase与heap统计，成功及普通帧不扫描heap。effect首项失败释放未转交count；layer/particle factory具体分配失败抛OOM，checked closure在同步构造期区分caller/SDK finalizer的转交，成功清临时指针。没有新异常系统、identity或生命周期owner。

## 实际原包验证

输入47文件与用户目录逐字节核对；原包及脚本不修改。隔离签名App为Debug显式-O，default display clock、静音fixture、独立HOME/cache；不是正常桌面App→client→daemon端到端验收，也不是官方全片parity。

最终v4 source lock SHA c4a3cada9064f74583c16665b374cae3ccab36d53444acc763000c5535d83ec5，App binary SHA 73e85067e85ba1ea314999679a8b726a34d48c2d7cfac2d84afb4f7b3ff85a04。原包45s与80s两run均935 owner保持至停止，无domain失败或memory-exceeded；ready仅标题/署名，后续进入太阳系和右侧HUD，行星标签及轨迹持续移动。80s实际网格点击从无到有，继续播放并GPU drain成功。独立2134765860运行14s，31 owner、房间/灯光/时钟实际保持，灰矩形旧问题未改善。三run均exit0/present/drain，六产品源码运行后SHA匹配；旧候选结果未移作最终身份。

未关闭既有光照、Bloom、布局、完整媒体来源及所有导航边界。当前关闭目标为原包自动开场、后续脚本更新与已验按钮交互；不把935个owner或present回执换算成整样本完整正确率。

## 验证与文档收尾

自有935/1200 owner、变量改名及等价表达式继续调用；有限heap饱和仍拒绝，不无限重试。native分配fault、early/late/success closure释放与formatter零调用、两种SyntaxError和非NULL/NULL parserOOM已有执行门。namespace/bind有限heap故障及四caller的成功值伴新异常、成功保旧pending、未知失败不借旧pending误报均有反例。compile成功伴新异常为caller-contract注入，未证明SDK实际出现此返回；install等的旧行为已由自有fixture复现。作者module/getter/setter throw null保持ordinary；native默认16MiB、自定义继承与override边界已执行。45项原focused门与后继相关C/ASan地址门各保源码身份，不冒充每版全套重跑；macOS leak detector不支持，不称泄漏扫描通过。独立审查及提交回执与最终冻结清单保留在证据包。

证据晋升因现有cache总预算超限被工具拒绝；prune-expired没有可删除的登记包，不猜删旧资料。本批必要证据限制32MiB暂存`.artifacts/tmp/solar-intro-host-installation-20261013`，待cache治理后晋升；保留三张原图和网格交互原图SHA/中性回执。证据保存输入/源码/App身份、失败phase数值回执、原包时序与交互截图、测试/build/review记录。用户媒体只读；收尾删除停止使用的副本、HOME/cache、staged App及生成源码，仅保留必要证据和既有一份DerivedData。前两性能批的App测量仍是脚本停用的退化负载；进入真实播放后必须另建同条件性能基线，不能跨负载比较。
