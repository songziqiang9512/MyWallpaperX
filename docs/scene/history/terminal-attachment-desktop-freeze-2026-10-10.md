> **历史证据 — 非现役入口**。当前任务从[断点队列](../roadmap/scene-open-breakpoint-queue.md)继续。

# 正常桌面终端目标权限与歌曲触发停帧（2026-10-10）

现役状态归[U16/U24断点队列](../roadmap/scene-open-breakpoint-queue.md)，本页只记录本批完成范围。

## 首断点与修复

基线 `7b4b896a`。用户报告 `3122339805`、`3420215721` 从Xcode Cmd+R构建后设为桌面，歌曲信息出现时整个场景停止。原测试使用截图证据窗口，不能覆盖普通桌面：`SceneDebugFrameCapture.configure` 为readback将CAMetalLayer设为非framebuffer-only；调试入口还可能默认关闭系统媒体。

在隔离HOME/样本副本中以相同协议启动普通 `--mwx-scene-daemon`，不带debug root/evidence参数，读取真实系统媒体。312用用户Xcode二进制及候选都复现：77帧之后rendered/drawCalls固定，dropped持续增加，busy为0，时钟截图停止。临时中性诊断确定首拒绝为 `graph-preflight-stage-0-node-0-material-0-…-pass-target-rejected`，不是主线程死锁或自动暂停。

`SceneResolvedMaterialAttachmentStorage.target` 把离屏输出的 `.shaderRead` 要求错误套到最终绘制目标。媒体使相关材质图层出现后，terminal replay在准备阶段拒绝普通SDR drawable；调试截图目标已有读取权限，掩盖了该错误。

只将已有 `PassRole` 显式传入同一target检查，准备与编码再验证一致：离屏要求renderTarget+shaderRead，terminal要求renderTarget。输入纹理可采样、输入/目标不得别名、格式/设备/尺寸/mip/sample、Program/reset身份和one-shot回执全部保留。没有修改CAMetalLayer策略、媒体Store、Program profile、资源owner或合成算法。所有临时日志均已撤回。

## 验证及边界

- 旧产品上，既有pass GPU门仅新增的PMA/straight renderTarget-only两像素断言失败，其他135项含原readable像素控制、offscreen拒绝及shaderRead-only终端拒绝通过。既有graph端到端门改成只可绘制目标后，同样报targetRejected。
- 修复后两GPU门通过，覆盖实际prepare→MainPass→GPU完成及像素；one-shot terminal receipt门首次因旧mock缺已提交的sharedModelPath而编译失败，补齐不可构造stub的trap-only成员后5项通过。最终pass门重跑通过，未在mock中实现新产品逻辑。
- Debug构建、签名及761个Scene源身份核对通过。最终dylib SHA `9320635c5fdb800456d46d7d1fd2b7bf992137992fcea7827f739b4b5c7392dd`。构建复用隔离checkout（Web基线较旧），不是全HEAD发布验证。
- 正常桌面312第一轮修复后940帧/0drop，真实metadata/cover进入，30秒后的时钟和数字窗口继续更新；最终移除临时日志后的构建再跑988帧/0drop/busy0，exit0，launch.json事前绑定普通daemon参数及最终产品身份。直接daemon覆盖真实桌面surface和system media，不等于App音频采集、全设置或全部交互验收。
- 342以用户Xcode二进制、修复前、修复后默认配置均持续出帧（分别498、489、487提交）；30fps请求下约半数尝试因in-flight未提交，且未接App音频采集，不能宣称用户的停帧报告已解决。其封面491准备拒绝和频谱/亮度余项仍开放。
- Scene依赖、defense、设计门通过。全仓code-health仍被未改Web文件1008行阻挡；residue检查发现未知归属的Scene/.mimosa（218字节），按规则保留。本批没有调整基线或清理他人文件。

## 产物与后继

本机根 `.artifacts/tmp/media-freeze-20261010` 保留有界运行、构建身份与红绿证据，pass红收据另见 `.artifacts/tmp/terminal-replay-target-20261010/audit`。正式证据库已达1GiB预算，本批不扩预算、不删除他人包。仅连续复用 `.build-cache/solid-source-domains-recovery-20261009` 一份构建缓存。

独立审查覆盖原公共权限合同、同一检查的两调用方、反例及真实桌面证据。下一项继续U24真实App音频/可见冻结条件及in-flight丢帧；不把U16因果闭环写成两样本全修。正常桌面与证据窗口的验证差异已写回开发工作流。


## 后继：真实App音频与U24资源驻留（同日）

基线 `ffac15da`。先前直接daemon不采集App音频，未覆盖触发条件。本轮新增Debug runner结果目录参数，只写现有结果JSON，不启用证据窗口或改变framebuffer权限。隔离原包、HOME，正常App product entry→client→daemon，真实系统音频与媒体信息进入后，342只提交7帧，随后3706次丢帧；首个非零音频使更多示波器图层进入渲染。不能把同时出现的歌曲文字本身当作因果。

连续定位到两处资源问题：预检把本command buffer已经预留、尚未提交的组输入当成可等GPU完成释放的旧资源，永远延期；修正分类并共享空透明输入后，graph已能准备/编码，但末端颜色转换还要新增47,513,088B scratch，仍因预算不足丢弃整帧。中间候选7帧/3388drop仍失败，明确不算闭环。

最终沿原资源链修复：

- 只有无成员且copybackground=false的组共享同帧透明输入，forward预检可读前清零；有成员/背景组、graph输出和history独立。此样本四个同尺寸空输入合为一个，减少142,539,264B重复占用。
- 当前command buffer自己的pin计入本帧必需量，不再等待自身完成；其他buffer在飞资源仍按原规则延期。
- authored绘制与反射快照结束后，最终颜色转换可覆盖复用已经读完的等尺寸组输入，省掉另分配47,513,088B。仍由原group pin持有至取消/GPU完成；copy、mapper、seal及无组时原scratch入口不变。没有提高预算、改变分辨率/颜色算法或增加资源owner。

最终Debug构建来自当前主工作区，临时诊断撤回；真实App路径80秒提交1324帧、2680次未提交，非零音频峰值0.4477，metadata和thumbnail事件实际到达，exit0。冻结反例已闭，2680次未提交的具体原因仍待分解，不能把此结果当作性能完成或完整画面验收。封面491的execution-stage-conservation及官方圆环亮度对照仍开放。

同一最终App回归3122339805：40秒提交1328帧、0drop，真实metadata/thumbnail进入后仍更新，exit0；这不扩展为所有交互验收。

永久GPU反例验证四组在三张纹理预算内运行、先读透明/背景像素后终端覆写仍保留旧读结果、错buffer拒绝、arm后不可借用、completion释放及下帧清零；原terminal/HDR/reflection门继续验证真实mapper与seal。实际App补足新组合分支。独立只读审查核对named输出/history没有跨帧保留raw组输入，原cancel/arm唯一链不变。

本批有界证据保留于 `.artifacts/tmp/scene-empty-composition-20261010`，含基线、中间失败、最终运行、源码/App身份和验证日志；一份连续构建缓存仍为 `.build-cache/solid-source-domains-recovery-20261009`。当前状态及下一项以队列为准。


<a id="u24-cover-dependency"></a>

## 后继：封面依赖与完整画面驻留（同日）

基线 `057ae394`。342封面491有五个作者effect：三项初始启用的direct/system/previous输入、一项初始关闭的本地direct输入、末端圆角mask。初始引用漏掉inactive direct候选，准备Program却包含该stage，finalizer因此以execution-stage-conservation拒绝整链。现在沿原候选投影统一收集optional fallback与inactive direct，按已准入Program、consumer/provider/slot/purpose的完整身份合并；原base引用必须恰好保留一次。候选仅用于准备，实际采集仍取admitted Program交集。无依赖的effect自有FBO不再被无关限制拒绝；external/aggregate/self的原边界保留。没有新增provider、shader或输出路径。

完整封面恢复后，真实音频又使旧子额度不足：合法目标集合805,233,856B，旧automatic额度794,569,728B；其中140,953,600B旧history仍有真实pin，shared pair已去重。此时不能删history或别名复用。按资源准入设计，将原automatic池策略从设备建议工作集/16改为/8，192–1536MiB限幅不变；显式额度及唯一进程父账不变。实际父账上限3,178,278,912B，诊断采样占用由219,728,896增至933,760,768/935,078,656B，无拒绝、decoded为0。这是有界容量修正，不是显存优化，也不证明其他重型样本或多屏全部可用；采样不等于峰值。

最终无临时日志Debug App的普通App→client→daemon路径运行60秒，提交931帧、1879次未提交、busy0，真实音频峰值0.6161，媒体信息实际进入且未冻结。池占用908,260,032B；MTL统计1,223,245,824B与父账口径不同。未提交的具体原因与提交率仍需后继检查；最终视觉日志另有circular_text slot1 textureBindingInvalid，保留后继首断点，不宣称圆周文字正常。同一冻结App另回归312普通桌面30秒，真实音频峰值0.5245，提交921帧、0drop、busy0，exit0；未复验其全部交互。

同一最终App的原包副本由受控封面红→蓝，属性系统→本地→系统两次热切accepted，同window/surface保持。准备5/5 stages与4/4命名引用，GPU记录含初始inactive effect357；截图依次验证红封面、作者本地图、蓝封面。直接证据窗口只证明此显示/热切，不替代上述普通桌面验证；没有宣称与官方全部亮度/转场逐帧一致。首次after截图请求早于第二次切回，其本地图不是回归；最终将请求延后至8秒，`sample-visual-final-scene-after-window.png`已确认蓝图。

验证：候选/预证明/计划36项、补充final proof 7项、池31项、预算/父账4项、FBO激活与颜色GPU 2项通过；真实App自有inactive direct+optional+健康peer像素反例与既有mixed ABI通过。自有激活fixture含合法layer-access脚本，不单独证明纯属性激活；实际包热切补足本次用户路径。旧graph宽门候选仍32项false，隔离基线40项false，无新增失败；8项差别来自baseline缺默认Metal库，不能列为本批修复。该宽门仍非全绿，不改旧预期掩盖失败。Debug build、依赖/defense/代码健康与设计门通过，产品获独立只读审查；临时诊断撤回。

有界证据归 `.artifacts/tmp/scene-cover-dependency-20261010`，最终App/源码身份、红绿门、实际输入与截图分别留收据。复用一份 `.build-cache/solid-source-domains-recovery-20261009`，本批隔离样本/HOME在证据提取后清理。当前剩余与下一项只由队列维护。
