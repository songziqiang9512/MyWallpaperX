<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# RF03 显式粒子出生后继（2026-10-02）

> **历史证据 — 非现役入口**。当前入口：[兼容路线](../../scene/scene-compatibility-roadmap.md)、[能力台账](../../scene/semantics/coverage-ledger.md)、[运行证据](../../scene/semantics/runtime-evidence-current.md)。本记录已完成下述验证并获独立终审 ACCEPT，随本职责批窄提交；受保护三份总表未改。

## 结果与责任边界

沿现 SceneScript 句柄、owner admission、实际 simulator 和唯一 compositor 实施 `emitParticles(n)`；设计见[D4](../../scene/design/script-component-api-design.md)/[D11](../../scene/design/particle-playback-state-design.md)。首片为显式整数0…1024、已准备root、无authored child、单个现支持的确定性schedule；仍受实际容量、scene总存活数及native预算限制，不保证最大数量在所有存量下都可用。0仍占命令额度，不能改RNG/ID/live。

调用时借用原simulator真实初始化候选，再还原已提交状态；同callback query观察真实候选，最终owner准入从已提交状态按调用期输入重建，通过后全surface安装。后置属性return不追溯改写出生；每次transform setter前缀分别生效。manual出生不改变自动play/pause/stop意图，不推进schedule、clock或warm-up；正常advance和事件只消费一次。没有新simulator、RNG、clock、registry、compositor或持久出生队列。未调用emit的cadence不新增全root扫描；不据此宣称测得性能收益。

## 反例及审查修复

证据根为 `/private/tmp/mwx-particle-emit-next/`，真实样本根未写入。

- 相同自有package SHA256 `2fc4d01c6c0aeda00bed6d654f4483f975ec2bd33a9a5ebb10e646f13d93a1c7`：旧App缺API导致init.stop随回调失败回滚，7秒实际teardown63；新WIPv1实际3且仍stopped。`app-before-v2/`与`app-wip-v1/`保留输入、App身份、日志、runtime JSON和PNG；不是只以红色可见判断出生数。
- `implementation/transaction-red-v1.log`是真QuickJS→Swift反例；`transaction-v2.log`进一步走两个实际simulator、final admission、安装、advance及真实birth IDs drain，每屏3、二次drain空，超出journal数量层证据。
- 首条native work/bytes失败时C已锁unsafe，但command_count为0令Swift空循环漏检；修正overflow出口，JS catch不能逃过owner拒绝。
- 独立终审发现capacity/ID/scene-live预算错归普通参数错误；`transaction-v6-red.log`真实证明catch后可保留pause。按budget/stale identity分类硬拒owner，普通unsupported出生仍局部失败，不混淆两种命运。
- 独立终审发现pointer initializer缺输入时静默跳过，emit却报成功。`pointer-red.log`仅缺输入反例失败，有输入正例通过；严格出生沿实际initializer返回结果，失败恢复候选，自动发射默认行为不变。`pointer-green-v1.log`通过，不禁掉有合法输入的CP家族。
- 移除无producer的安装失败`.dropped`分支：最终prepare至install为同一MainActor同步段，无await、作者callback或surface写入者；完整集、revision和预算仍在准入边界复核。删除同样无nil producer的基础initializer plan guards。保留真实输入可触发的复杂plan检查。

## 冻结及验证

最终候选产品清单为`implementation/build-v3-source.json`，22文件，清单SHA256 `330725c70f3aeda16f9a8dc23be4a366cda1731463f90ee576bde1c002a6adca`。`final-v3.app`完整Debug构建成功并严格deep验签，Team H9QWU9XN8R，CDHash `c583a10a0565c447f3350dac23aad2cd7c9c1df9`；debug dylib SHA256 `d9cce65d3afedcc456acc3e80cbaf928e4eaae36c0a7139e4a544fb5504441e8`。v2构建因DEBUG读取private事件标记失败，v3仅放开该字段的读取权限，访问差异单独冻结；相关CPU门与最终App身份分别记录，不把v2构建记为成功。

- `implementation/transaction-v11.log`：最终真实事务门通过，61.960秒；覆盖命令顺序/回调隔离、actual query、owner撤回重算RNG/ID、双surface原子性、取消、native超限、zero额度、ID溢出及scene总存量边界。另`simulator-v13.log`以1024存量、trail8和20个audio initializers测得两个保留候选各1,182,368B，预留峰值4,850,880B、work79768；超过下一预留上限会拒绝且已提交状态不变，释放归零。这是实际capacity与临时额度门，不是RSS测量。
- `runtime-final.log`：53测试，43通过、10因隔离真实样本缓存/证据缺失跳过，26.061秒。不是53项全部执行。
- WIPv1六个实际App场景通过：stop后3、pause存量4加2、lifetime1出生后return0、两surface单屏drawable缺失恢复不重放、两次angles setter分别影响出生方向、lifetime0失败不能被后置return1补救。方向场景after图人工确认两个分离红块。
- 最终`app-final-v3.log`共17场景全部通过，356.800秒，覆盖旧四方法及新增八场景，包含上述六项、prepared提交拒绝和全部drawable丢失恢复；新增门断言实际manual birth事件切片、IDs/live及健康绿色邻层，排除warm-up旧事件。17份执行身份的package与App SHA逐项保留；每surface stop后手动3个的实际ID为4–6，pause新增2个为4–5。
- `adjacent-vm-final.log`八个共享VM邻接模块共76测试通过，240.252秒；author/audio/boids聚焦门通过。完整simulator模块以Python3.12执行69项，68通过、1条pointer force旧预期失败；隔离HEAD真实Swift源重现同一失败，`head-pointer-regression.log`与源清单保留，未当作全绿。
- code-health、scene-defense、design-gate通过；三个新扩展文件补入原owner目录准入后layout单门通过。完整semantics门仍有3个HEAD既有失败：D2历史RF07片段断链及两项authority校验（shape66/65、legacy6/5）；22产品文件与HEAD逐项pattern差为0，没有借本批扩大基线。正式文档门25项通过；独立终审对39个owned文件的冻结树`9ee44b6fad9d427bea30884c57ccf9cb1032ed7d`作出ACCEPT，报告保存在`/private/tmp/mwx-particle-emit-next/independent-review.md`。终审后的收口仅更新本记录、实施卡和路线的完成状态，不修改产品或测试。

直接particle渲染没有独立graph-provider publication；本批观察typed安装→draw batches/instance buffer→GPU completion→mainPass/terminal→host激活/next-frame，不凭空补provider发布断言。虚拟双surface不代表物理多屏官方parity；原始真实样本缺缓存的skip未用自有内容冒充。

## 未验证边界与下一批

默认count、多emitter、authored children、reset、存活粒子重建迁移、官方调度/随机序列、物理多屏parity未开放。native临时容量记账不等于物理RSS上界；未做性能收益或实际硬件GPU故障声明。可重建App/DerivedData与关键失败现场分开保留，未清理其他任务产物。

下一批选D1实际source一致性：先落盘中性参考交接并批准窄设计，以真实两色source反例修graph准备与编码消费错位，再验工作空间及资源生命周期。采集成员/flag未明分支继续有界研究，不因缺官方像素golden整体冻结已有资源正确性责任；本记录不批准D1新视觉语义。
