<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。后续以性能卡和对应现役合同为准。

# Scene 证据工具职责收敛（2026-10-13）

本记录保存已实施的工具迁移及验收边界；后续执行归[性能卡](../roadmap/performance-convergence-card.md)，使用与证据边界归[工程宪章](../development/development-workflow.md)。不是产品兼容或性能收益结论。

原 runner 与测试单文件分别为9426、8261行。CLI保留严格默认、矩阵前置检查、签名App调度、清理与报告发布；日志grammar/解析、采集、验收按既有语义各保唯一owner。直接导入保持原API，无wrapper、反向CLI依赖、第二解析或新增产品owner。全部本批代码文件≤1000行。

282个旧定义按AST原样迁移；唯一采集到验收接缝复用同一份证据和控制观察，不序列化回读、不重算日志。loaded/candidate阈值仍用未舍入比例，报告保持四位比例；失败顺序、函数签名/默认、CLI help保持。独审发现的未消费形参已删除。旧monolith退出；测试按合同唯一发现，退休的源码形状检查由实际运行边界反例接管，门映射同步迁移。

冻结46路径patch SHA-256 `d4f861c9e45d2cf180a056c439c4fac410cd4cdf8ba7c67034d8621d969c878a`，manifest `3371d3ef6820293c3b47842bc87ed9fa364436c389dd1288cc953a16a6879fd2`。独立只读审查及接缝重审接受；10个完整报告/命令和4个异常golden与旧工具一致，205项自有CPU/模拟Swift测试通过。主树169迁移项、36外部消费者通过；初次命令误写两个外部模块名导致loader错误，改用实际文件名后外部36项通过，没有掩盖行为失败。

迁移工具的首份有界签名App实际运行：3662790108正常开场、935owner、30s warmup、零帧失败及GPU排空，requested performance/preparation PASS；report SHA-256 `863c9d2978736d11947366de1593fd16abbe21b244b60a7c17c6424c685a5e39`。显式关闭执行观察，graph保持unavailable/has_evidence=false，不能据此称graph成功、全样本正确或帧率收益；后续真实渲染和对照归对应GPU批。

直接reexport保持调用入口，但针对实现内部依赖的外部monkeypatch须指向实际owner。隔离验证、身份与独审保留于本机`.artifacts/tmp/benchmark-responsibility-convergence-20261013`；只保留必要文本证据，副本与重试输出按本批清理回执收缩。无真实作者源码、路径或hash视觉特判。
