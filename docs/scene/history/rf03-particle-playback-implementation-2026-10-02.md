<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# RF03 作者粒子播放四方法实施证据（2026-10-02）

> **历史证据 — 非现役入口**。当前权威：[兼容路线](../roadmap/scene-compatibility-roadmap.md)、[能力台账](../capabilities/coverage-ledger.md)、[运行证据](../capabilities/runtime-evidence-current.md)。本批未改三个受保护的能力/运行/重构总表。

同页历史分节：[连续排放后继记录](#rf03-continuous)、[显式出生后继记录](#rf03-explicit-emission)。

## 范围与责任

基线为主目录 `codex/engine-refactor-program`、HEAD `85415320` 与先前冻结的 D2/D3、RF01、RF05 未提交实现。依据 [D4](../roadmap/batch2/script-component-api-design.md) 与 [D11](../roadmap/batch2/particle-playback-state-design.md)，开放已准备 root、无 authored child、单个 supported 确定性有限或固定周期 schedule 的 `play/pause/stop/isPlaying`。作者从 thisLayer/现有 layer lookup 调用；particle.instanceoverride.alpha 的 thisObject 仍是属性/组件 scope。emitParticles、reset、多 emitter、children、随机周期继续不支持，不声明完整 SceneScript/粒子兼容。

C handle 镜像和 callback journal 产生带既有 callback epoch/ordinal 的命令；DynamicLayerRuntime 的同一 owner fixed point 保存作者 intent/revision，拒绝 owner 后重算有序计划。Session 对完整同代 surface 实例派生 OR 查询，每屏在模拟前消费同一计划一次。GPU 提交失败不回退 VM/模拟/命令。rebuild 的 committed paused/stopped 在 constructor warm-up 前注入，不重放旧 transition；playing rebuild 不承诺迁移既有 RNG/粒子状态。

pause 仅停自动排放，已有粒子继续老化与死亡。stop 清 live、瞬态出生/事件、年龄/振荡/Trail/step 缓存和 Runtime rope/batch；同时重置局部发射游标，所以 stop→pause→play 不恢复旧游标。play 对未结束 schedule 续播、对停止/自然结束 schedule rearm，保留已有 live ID/年龄、全局模拟时间和随机序列；初次 launch 保留现有预热次序。以上 restart/init 和多surface OR 是项目边界，不宣称官方相位或多屏 parity。

## 反例、修复与独立终审

本机证据统一位于 `/private/tmp/mwx-rf03/`。

- 模拟修前：simulator-before.log 十个行为失败；ordered-stop-before.log 证明 stop→pause→play 恢复了旧游标。修后 simulator-final.log 通过，清理断言使用真实非空缓存/事件前态；runtime-playback-frozen.log 的真实 Metal-backed Runtime 门通过（19.789秒），包括 rope ghost、revision、缺实例、rebuild。
- 独审发现 Session 动态隐藏/alpha=0 被当作缺 runtime，误拒已有 prepared 实例。改为实际实例完整性；hidden prepared query/stop 的真实跨链断言通过。
- 独审发现同 cadence 多 timer、video-ended handlers 与后续 update 共 epoch，查询串入前 callback staged 命令。真实 timer/ended 反例修前失败，修后按实际 callback 推进现有 epoch；所属 microtask 在该 callback 内 drain，导出 journal 和调用顺序保留。
- 独审发现相同 owner 的 cursor/update 分包绕过256总预算。callback-budget-handles-before.log 使用255/256个不同 authored image 的真实 QuickJS handle 写入：256条总命令合法、257条旧版也接受；修后按 owner 合计全部 bundle。早先未经授权层的 fixture 和数字 lookup/index 误用仅作测试排障，不作为漏洞证据。
- typed ended dispatcher 初修漏掉 uncaught 第65条命令的预算错误分类。ended-overflow-before.log 的唯一失败证明该回归；v3 恢复同步异常及微任务失败的现役 overflow 分类，typed timeout/OOM 不丢失。
- 旧 App 的有限 duration=20、非零 startTime、真实 particle alpha 脚本 init.stop 反例见 integration-before-finite.log：实际进入 VM，报 TypeError，红色粒子仍显示。更早 visibility 绑定未入 VM、无 duration fixture 不在开放 profile 的材料均不作本片支持对照；未用通用 benchmark PASS 冒称 API 成功。

最终独立只读终审核对上述修复、新 guard 的真实产生者、完整源码/测试/App 身份及实际输出，接受 v3 限定批次，无剩余阻断 finding。审查者未运行测试或 GPU，运行由实施/root 完成。

## 冻结身份与验证

product-freeze-v3.json 为28个产品路径；test-freeze-v3.json 为14个测试/helper/fixture，另有 root-app-test-freeze-v3.json 的完整 App 门。build-source-v3.json 保存累计78个受改产品源 SHA，构建前后匹配；build-v3.log 为 BUILD SUCCEEDED。build-v3-payload-identity.json 的17个实际 binary/dylib/metallib SHA 与 frozen-v3.app 一致。App 2.10.0(280)，team H9QWU9XN8R，CDHash `005df94fa60f74140647cadfa1d8dd2f051a4b53`，deep/strict 签名校验通过。

- 最终 v3 ended-overflow-after.log：4 tests PASS，62.652秒；包含真实 QuickJS→Swift fixed point→双模拟器的39条行为结果及3项 author 门。覆盖首次 init、staged query、callback/owner顺序、完整surface OR、指针导致实例分歧、whole-owner拒绝、零工作、64/65与256/257、unsupported参数、rebuild和revision不重放。
- adjacent-v2.log：43 tests PASS，318.972秒；前半使用v2，后半v3（差异仅ended错误分类），不能称全套同身份。两处旧独立projection夹具补了新opaque payload类型/字段后真实编译通过。更早 property-vector 25项也通过。
- code-health-v3.log：1044 Swift文件/0错误，237条既有warning；defense-v3.log、design-gate-v3.log 与 owned diff-check通过。结构预算未放宽。
- app-integration-v3.log：同一签名冻结App的6 tests PASS，93.661秒。实际 init.pause 的ready/after live均4，init.stop两图清除红色，stop→play重新出现红色；全部drawable缺失、一屏缺drawable、post-prepare拒绝三门分别验证每surface revision只消费一次、peer安全输出和恢复completion。证据是12张terminal PNG、日志和 app-oracles-v3.json；pause/play红色像素55696、stop为0，稳定green peer均10471。

故障三门执行 stop→play→pause，最终零粒子，签收的是命令唯一消费、安全peer输出、实际surface恢复completion；不将其扩大为带birth/RNG/children的GPU重播验收。多surface为受控合成屏，非物理多屏验收。

## 未验证边界与交接

旧 simulator 回归68/69通过，pointer-control-point-force 的一个失败用实际 HEAD 旧实现复现同结果（simulator-old-pointer.log）；未改断言凑绿。audio5与boids2通过。真实异步GPU error、物理多屏、长稳性能/资源、完整官方行为对照未执行；受控drawable/提交拒绝和CPU seam不替代它们。未暂存、提交或推送。源码/冻结App及唯一失败日志保留，用于后继隔离比较；RF07 是独立下一片，不改变本记录的冻结验收身份。

<a id="rf03-continuous"></a>

## 连续排放后继记录

下文完整保留该阶段的历史裁决、证据身份和未验证边界；其中状态与后继顺序仅适用于原记录日期。

<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

<a id="rf03-continuous--rf03-连续排放四方法后继2026-10-02"></a>
### RF03 连续排放四方法后继（2026-10-02）

> **历史证据 — 非现役入口**。当前入口：[兼容路线](../roadmap/scene-compatibility-roadmap.md)、[能力台账](../capabilities/coverage-ledger.md)、[运行证据](../capabilities/runtime-evidence-current.md)。未改受保护三份总表。

<a id="rf03-continuous--实际结果与责任"></a>
#### 实际结果与责任

默认连续排放的已准备单 root 粒子系统现在可用 play/pause/stop/isPlaying。原先模拟器已能持续发射，但 preparedPlaybackWork 要求非零 rate 必须有正 duration，导致作者 init.stop 抛 TypeError、红色粒子继续出现。依据[官方 emitter Duration](https://docs.wallpaperengine.io/en/scene/particles/component/emitter.html#duration) 的默认0无限行为，移除这个不必要的有限时长限制；仍用既有 C journal、Swift typed意图、per-surface simulator与唯一compositor。

独立终审又发现 parser 将显式非法 duration 折为 nil，修复为在 SceneParticleEmitter 保留 hasMalformedDuration 并在同一 prepared admission拒绝。producer 是 SceneParticleDefinitionParser.parseEmitter，覆盖bool、不可解析字符串、数组与无value字典；缺省/null与数值0分开验证。没有新增模拟owner或时钟。设计见[D11](../roadmap/batch2/particle-playback-state-design.md)/[D4](../roadmap/batch2/script-component-api-design.md)。

<a id="rf03-continuous--冻结与反例"></a>
#### 冻结与反例

工作目录为主分支 codex/engine-refactor-program，批次起点 HEAD 85415320 加已验收五批未提交文件；只对新增3产品、2测试及明确文档差异负责。隔离证据根 `/private/tmp/mwx-rf03-continuous/`：baseline保存本批前字节；review-v3/manifest.json与owned.diff保存受审代码/测试；最终文档措辞把App缺省duration与Swift的0/null分开。20项实际App载荷见payload-v3.json；frozen-v3.app严格deep验签，Team H9QWU9XN8R，CDHash `a790e6ab53c1e82725ebe0c2479e8d006f50504e`。

- simulator-red.log：真实 Swift parser/simulator 六反例失败；simulator-green.log初修通过。
- app-red.log及app-before：旧冻结RF07 App的真实 init.stop TypeError，GPU仍完成、红色粒子未被停止（ready/after两图均55696红像素，绿色peer10471像素）。未以非黑或route代替命令成功。
- malformed-red.log：终审四个非法作者值反例先失败；simulator-parser-v3.log最终7测试通过（12.440s），另含delay/remainder暂停、重复play不重启、stop后重启delay及ID连续、零容量/null。
- focused.log：author、transaction、runtime三模块全通过；runtime53测试含10个既有skip，不能记成全部执行。此邻接门先于新增malformed字段，最终parser/simulator和App按v3执行。
- build-v3.log：最终完整Debug构建成功。中间build-v2因局部编辑误及child初始化产生编译错误，已修，日志保留，不作成功证据。
- app-v3.log：最终三个独立App场景通过，73.656s；六PNG，最终stop两图红像素均0，其余两场景红像素55696，所有图绿色peer10471像素（pixel-oracles.json）。缺省duration init.stop首/后图红色消失且绿色peer保留；pause保留warm-up存量继续模拟；stop→play重新出生。实际frame0命令revision一次消费、frame0/1/2 GPU completion、后续terminal截图和gpuDrained停止链闭合。
- code-health-v3、defense-v3、design-gate-v3通过；doc-gates.log当时25文档测试通过。独立astra high复核接受v3，无剩余阻断finding。

<a id="rf03-continuous--未验证边界与下一批"></a>
#### 未验证边界与下一批

duration=0/null由真实Swift门覆盖，App为缺省duration。未新增显式emit、多emitter、children、随机周期、reset、模拟迁移或官方像素parity；未做性能收益声明。实际硬件GPU故障和物理多屏不在本小批。

按用户要求本批随3产品/2测试和设计增量按职责提交；提交号由Git记录，不在正文制造自引用。下一批是RF05初始属性隐藏但被普通image consumer采样的provider：先三对照复现deferred资源缺边，再修既有selector；之后推进D1现有isolated scope的真实组源与图片父子树闭合。

<a id="rf03-explicit-emission"></a>

## 显式出生后继记录

下文完整保留该阶段的历史裁决、证据身份和未验证边界；其中状态与后继顺序仅适用于原记录日期。

<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

<a id="rf03-explicit-emission--rf03-显式粒子出生后继2026-10-02"></a>
### RF03 显式粒子出生后继（2026-10-02）

> **历史证据 — 非现役入口**。当前入口：[兼容路线](../roadmap/scene-compatibility-roadmap.md)、[能力台账](../capabilities/coverage-ledger.md)、[运行证据](../capabilities/runtime-evidence-current.md)。本记录已完成下述验证并获独立终审 ACCEPT，随本职责批窄提交；受保护三份总表未改。

<a id="rf03-explicit-emission--结果与责任边界"></a>
#### 结果与责任边界

沿现 SceneScript 句柄、owner admission、实际 simulator 和唯一 compositor 实施 `emitParticles(n)`；设计见[D4](../roadmap/batch2/script-component-api-design.md)/[D11](../roadmap/batch2/particle-playback-state-design.md)。首片为显式整数0…1024、已准备root、无authored child、单个现支持的确定性schedule；仍受实际容量、scene总存活数及native预算限制，不保证最大数量在所有存量下都可用。0仍占命令额度，不能改RNG/ID/live。

调用时借用原simulator真实初始化候选，再还原已提交状态；同callback query观察真实候选，最终owner准入从已提交状态按调用期输入重建，通过后全surface安装。后置属性return不追溯改写出生；每次transform setter前缀分别生效。manual出生不改变自动play/pause/stop意图，不推进schedule、clock或warm-up；正常advance和事件只消费一次。没有新simulator、RNG、clock、registry、compositor或持久出生队列。未调用emit的cadence不新增全root扫描；不据此宣称测得性能收益。

<a id="rf03-explicit-emission--反例及审查修复"></a>
#### 反例及审查修复

证据根为 `/private/tmp/mwx-particle-emit-next/`，真实样本根未写入。

- 相同自有package SHA256 `2fc4d01c6c0aeda00bed6d654f4483f975ec2bd33a9a5ebb10e646f13d93a1c7`：旧App缺API导致init.stop随回调失败回滚，7秒实际teardown63；新WIPv1实际3且仍stopped。`app-before-v2/`与`app-wip-v1/`保留输入、App身份、日志、runtime JSON和PNG；不是只以红色可见判断出生数。
- `implementation/transaction-red-v1.log`是真QuickJS→Swift反例；`transaction-v2.log`进一步走两个实际simulator、final admission、安装、advance及真实birth IDs drain，每屏3、二次drain空，超出journal数量层证据。
- 首条native work/bytes失败时C已锁unsafe，但command_count为0令Swift空循环漏检；修正overflow出口，JS catch不能逃过owner拒绝。
- 独立终审发现capacity/ID/scene-live预算错归普通参数错误；`transaction-v6-red.log`真实证明catch后可保留pause。按budget/stale identity分类硬拒owner，普通unsupported出生仍局部失败，不混淆两种命运。
- 独立终审发现pointer initializer缺输入时静默跳过，emit却报成功。`pointer-red.log`仅缺输入反例失败，有输入正例通过；严格出生沿实际initializer返回结果，失败恢复候选，自动发射默认行为不变。`pointer-green-v1.log`通过，不禁掉有合法输入的CP家族。
- 移除无producer的安装失败`.dropped`分支：最终prepare至install为同一MainActor同步段，无await、作者callback或surface写入者；完整集、revision和预算仍在准入边界复核。删除同样无nil producer的基础initializer plan guards。保留真实输入可触发的复杂plan检查。

<a id="rf03-explicit-emission--冻结及验证"></a>
#### 冻结及验证

最终候选产品清单为`implementation/build-v3-source.json`，22文件，清单SHA256 `330725c70f3aeda16f9a8dc23be4a366cda1731463f90ee576bde1c002a6adca`。`final-v3.app`完整Debug构建成功并严格deep验签，Team H9QWU9XN8R，CDHash `c583a10a0565c447f3350dac23aad2cd7c9c1df9`；debug dylib SHA256 `d9cce65d3afedcc456acc3e80cbaf928e4eaae36c0a7139e4a544fb5504441e8`。v2构建因DEBUG读取private事件标记失败，v3仅放开该字段的读取权限，访问差异单独冻结；相关CPU门与最终App身份分别记录，不把v2构建记为成功。

- `implementation/transaction-v11.log`：最终真实事务门通过，61.960秒；覆盖命令顺序/回调隔离、actual query、owner撤回重算RNG/ID、双surface原子性、取消、native超限、zero额度、ID溢出及scene总存量边界。另`simulator-v13.log`以1024存量、trail8和20个audio initializers测得两个保留候选各1,182,368B，预留峰值4,850,880B、work79768；超过下一预留上限会拒绝且已提交状态不变，释放归零。这是实际capacity与临时额度门，不是RSS测量。
- `runtime-final.log`：53测试，43通过、10因隔离真实样本缓存/证据缺失跳过，26.061秒。不是53项全部执行。
- WIPv1六个实际App场景通过：stop后3、pause存量4加2、lifetime1出生后return0、两surface单屏drawable缺失恢复不重放、两次angles setter分别影响出生方向、lifetime0失败不能被后置return1补救。方向场景after图人工确认两个分离红块。
- 最终`app-final-v3.log`共17场景全部通过，356.800秒，覆盖旧四方法及新增八场景，包含上述六项、prepared提交拒绝和全部drawable丢失恢复；新增门断言实际manual birth事件切片、IDs/live及健康绿色邻层，排除warm-up旧事件。17份执行身份的package与App SHA逐项保留；每surface stop后手动3个的实际ID为4–6，pause新增2个为4–5。
- `adjacent-vm-final.log`八个共享VM邻接模块共76测试通过，240.252秒；author/audio/boids聚焦门通过。完整simulator模块以Python3.12执行69项，68通过、1条pointer force旧预期失败；隔离HEAD真实Swift源重现同一失败，`head-pointer-regression.log`与源清单保留，未当作全绿。
- code-health、scene-defense、design-gate通过；三个新扩展文件补入原owner目录准入后layout单门通过。完整semantics门仍有3个HEAD既有失败：D2历史RF07片段断链及两项authority校验（shape66/65、legacy6/5）；22产品文件与HEAD逐项pattern差为0，没有借本批扩大基线。正式文档门25项通过；独立终审对39个owned文件的冻结树`9ee44b6fad9d427bea30884c57ccf9cb1032ed7d`作出ACCEPT，报告保存在`/private/tmp/mwx-particle-emit-next/independent-review.md`。终审后的收口仅更新本记录、实施卡和路线的完成状态，不修改产品或测试。

直接particle渲染没有独立graph-provider publication；本批观察typed安装→draw batches/instance buffer→GPU completion→mainPass/terminal→host激活/next-frame，不凭空补provider发布断言。虚拟双surface不代表物理多屏官方parity；原始真实样本缺缓存的skip未用自有内容冒充。

<a id="rf03-explicit-emission--未验证边界与下一批"></a>
#### 未验证边界与下一批

默认count、多emitter、authored children、reset、存活粒子重建迁移、官方调度/随机序列、物理多屏parity未开放。native临时容量记账不等于物理RSS上界；未做性能收益或实际硬件GPU故障声明。可重建App/DerivedData与关键失败现场分开保留，未清理其他任务产物。

下一批选D1实际source一致性：先落盘中性参考交接并批准窄设计，以真实两色source反例修graph准备与编码消费错位，再验工作空间及资源生命周期。采集成员/flag未明分支继续有界研究，不因缺官方像素golden整体冻结已有资源正确性责任；本记录不批准D1新视觉语义。
