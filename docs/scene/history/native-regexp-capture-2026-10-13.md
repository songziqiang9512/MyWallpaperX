<!-- document-role: historical-evidence -->

# 原生 RegExp 捕获状态与真实时钟恢复

> **历史证据 — 非现役入口**。截止2026-10-13；合同归[API表](../capabilities/scenescript-api-coverage.md#native-regexp-captures)，未完成项归[属性卡](../roadmap/properties-panel-card.md)、[性能卡](../roadmap/performance-convergence-card.md)及[队列](../roadmap/scene-open-breakpoint-queue.md)。

## 公共语义、设计与实现

接收`8e80de8f8`工作区的未提交native intrinsic设计/实现/自有fixture，再闭合成本与实际运行。原native匹配已经成功，但缺`RegExp.$1…$9`使合法timer的捕获长度读取失败；修复不按样本/属性键选行为。公开来源仅[TC39 legacy提案](https://github.com/tc39/proposal-regexp-legacy-features/tree/e4257f8e83c4d4b648ef1b6150c01ba5938def37)（Stage 3）及现vendored QuickJS，不消费私有实现或作者formatter，不声明完整提案/ECMA-262接受。

先在D4落设计，比较JS exec wrapper与原生producer：wrapper新增解释器调用、改变exec identity并退出empty-replacement fastpath；采用原context九槽、原RegExp immutable creation-realm/eligibility与既有GC/lifetime。成功native match原子发布，失败保旧状态；同realm subclass成功失效、foreign realm不写；native getters限定原intrinsic receiver，槽不足/未参与为空String。empty-replace沿原捕获位置准备，borrowed native exec realm持有至成功/异常返回；保嵌套replacer与最后完成match的顺序。原replace初始化输出OOM的成功值伴pending exception缺陷同时退出，保原异常。无新正则算法、状态registry、frame rollback或clock owner。

初次三轮微基准暴露无组匹配重复清空九槽的额外成本。实施前补设计：context保存当前捕获范围，发布只替换新范围并清理旧尾部一次；未用槽恒NULL，无组恢复与失效语义保持。无懒解析、额外输入String驻留或cache；原JSObject头部布局不扩张。vendor README记录来源、范围及上游替换退出门，第三方ABI不拆文件。

独审提出并经自有夹具复现两处失败：exec getter/lastIndex转换冻结原data字段后，旧fastpath提前发布新槽或使子类状态失效；长slice捕获跨GC保整段1–2 MiB parent。前者把原native所需lastIndex写入移到捕获准备/发布前，保zero-length进位及最终失败归零；后者双producer沿同一有界helper，仅对slice用现8/16-bit构造器复制捕获字节，普通String仍复用。同步原memory estimator计入context槽；初次只看memory_used_size漏计，真正驻留对照使用malloc_size，不把旧估算当收益。没有新parser/字符串算法或资源owner。

## 真实产品输出与边界

正常AppKit选择→client→daemon→桌面。基线App SHA `77a19bd212c6a5423a15d5f8b2f2a8a5454d0c86b4fbec312129e6ea2a4b9635`；范围候选Developer ID签名Debug `SWIFT_OPTIMIZATION_LEVEL=-O` App SHA `5dc74adef184eda79915ff8608a099681f8bc45019a8038e9732fce93d2c9d84`，4263构建输入一致。两样本树字节与前批隔离副本一致，输入/属性不改作者源码。基线Clock1/2均on，166/120各`length of undefined`且画面无时钟；候选同默认实际显示16:10及10|13，后帧16:12。Clock1 off实际只隐藏时间，on恢复；同daemon2334、window23575，无新增startup，关闭重开保持on。此次只关闭这两处timer技术断点，格式/更多定义的面板准入及媒体blur/spin、真实来源仲裁仍开放。

未参与RegExp修法的3042492564在同App正常切换后window23615中，16:15→16:16进位，人物/星星/光束、谱条及封面继续变化；封面右裁切、544 `event is not defined`和1128非有限origin仍开放。1128重复失败诊断与逐帧材质准备已有5秒CPU栈供后继归因，不能据一次栈采样宣称高温根因或收益。未控制实时音频/媒体，不作幅度、全平台或整景parity结论；HDR、多屏、取消/失败启动与长期切换未在本批重验。

## 测量与验证

全自有原生VM门含变量/资源改名、等价表达式、optional/九组范围、无组/失败、String匹配、empty/nested replace、subclass/Reflect/原型变更、双realm/GC、真实Scene timer、allocation ordinal、内存预算和interrupt。普通及强制GC门各通过；最终47/26分配位置全部拒绝，九槽未部分发布，无泄漏。范围优化补少→多→无组、旧尾部清空与invalid→empty反例。最终33项相邻timer/string/event/storage/budget/retirement/reference门、ASAN与Debug构建通过，具体日志见本机冻结包，不以这些门代替画面。

原生`clang -O2`四种全自有高频工作负载，固定源码/输入，至少三轮按baseline→初候选→范围候选交替比较process CPU时间；原未实现capture的版本不可能成为功能等价性能基线。短轮结果：400000次capture test的候选/原版中位1.069，no-group test 1.019；4096000次native empty-replace capture 1.661、no-group 1.169。范围候选/初候选分别0.993、0.974、0.966、0.953；首组候选67.935ms异常值保留，短轮不作稳定收益。必要捕获字符串仍有成本，不能写成整景优化。各工作负载释放context并GC后均为24439 bytes，原版与候选相同；驻留候选多2306 bytes，不代表App内存/缓存长稳。

独立只读代码与最终证据审查回执、最终相邻门和清理回执归 `.artifacts/tmp/regexp-capture-closeout-20261013`；本记录只报告实际执行范围。性能专项与属性专项阶段估计不因时钟修复提高；本批不是CPU/GPU/能耗/温度或首帧收敛接受。

**最终原生内存对照。** 固定review前源SHA `1bef51abe2f43af8401a3be8a47085e2e3419bbc446726af7f4783f3631875d5`（由HEAD加保存的12981-byte patch重建并核SHA），最终源SHA `9065ee26a1a66f417726b8fc9850502c7ac147b56073eadf6875f4856beb3433`。相同`clang -O2`与五个自有临时输入，每例三份fresh context，普通GC，比较真实malloc_size增量。两版所有三轮都一致：

| 捕获消费 | 复审前驻留bytes | 最终驻留bytes | 清槽后两版相同增量bytes |
|---|---:|---:|---:|
| ASCII native test | 1065320 | 1584 | 312 |
| ASCII empty replace | 1065488 | 1752 | 584 |
| Unicode native test | 2113896 | 5424 | 312 |
| Unicode empty replace | 2114064 | 5592 | 584 |
| 嵌套slice native test | 2114000 | 1688 | 416 |

输入其它字节不再被capture长期保留；约99.7%–99.9%的驻留减少只限这些native输入。临时compile inputs另验证前后`sizeof(JSObject)==72`；不是App footprint、解码峰值或长期cache接受。后继native/forced-GC/ASAN全部保持captured code units，47/26所有分配ordinal拒绝无半发布。

**最终构建与真实画面。** 后继签名Debug -O App SHA `a65a30ac499d978950a6dee900f9596f804a84a18b83b0b282d26715671501c3`，4263构建输入不变；此前5dc候选不代最终证据。最终正常App8916→daemon8927：293 window23647实际16:45→16:50、日期与人物/水纹/星星/频谱/封面保持；Clock1 off只隐时间，on恢复，关闭重开on，期间仅一个accepted启动且无VM failure。独立304 window23681实际16:54→16:57，原裁切/544/1128问题仍在。正常stop后两scene分别41/71 owners全quiescent，failures/timers/jobs/mutations/dynamicLayers均0；App/daemon已退出，不据此代长期切换/多屏回落。

**最终CPU成本边界。** 无App/测试/构建竞争时，每例三轮`base→review-baseline→final`，均`clang -O2`，先各一次未计warm调用，保所有数据。四种输入分别4000000次capture test、no-group test，及40960000次capture/no-group native empty replace。最终/原无capture版本中位ratio为1.063、1.049、1.758、1.175；最终/复审前兼容候选为1.020、0.998、1.110、1.133。第一例最终第三轮719.466ms高值保留；这些数值不证明CPU优化。后两例增加的是正确lastIndex提交边界与capture所有权的成本，原未实现/错误语义不能作功能等价优化基线；现仍保native exec与快速路径。长期CPU/功耗/温度、GPU/history与主线程响应保持未验。

最终独立只读静态审查`ACCEPT`绑定五个product/test精确SHA，未代执行native门/ASAN或UI。必要截图与证据按32MiB收窄后，正式1GiB缓存仍无到期包且拒绝promotion；不增预算、不删其他owner。清理/保留回执与提交身份随本机proof归档，下一批接现役工作卡。

本轮临时HOME、退役App（包括前批明确留作本次follow-up的77a1）、中间截图/编译源/二进制与重试输出已按精确路径退役。限量proof约28MiB保 `.artifacts/tmp/regexp-capture-closeout-20261013/proof`；连续后继仅留最终a65候选、两样本隔离副本及一份 `.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData`。未修改原样本，未测实际磁盘释放量。另修前批材质历史记录指向已不存在E1 fragment的导航链接，不改其执行结论。
