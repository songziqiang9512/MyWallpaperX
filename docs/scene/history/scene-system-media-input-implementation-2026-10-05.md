<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# Scene 系统媒体输入（2026-10-05）

> **历史证据 — 非现役入口**。冻结实施证据；未完成输入由[RF05卡](../roadmap/batch2/reference-evidence-implementation-cards.md)接管，职责与实验发行边界见[媒体输入设计](../roadmap/batch2/system-media-input-design.md)。

基线 `915bad17`。准备完成的媒体消费者向进程内唯一 producer 注册需求；所选 Music 公开只读来源或 Debug 系统实验来源提交同一 Inbox 原子会话。最后需求退出撤状态、终止reader；多显示器共用输入。无帧内查询、进程启动或新合成owner。

参考只消费独立审核的中性合同：WaifuX `289b5028e075d05fd4840d1306961c2548a2dadb`、Mirage `77e4886e619514391f3f0ebd9433cce525eb261b`。自写相同库的Native→Perl→Native实验证明本机宿主差异；封面范围请求进入队列。未复制参考代码。公共XS入口在装载完成后运行，避开构造器持锁与图片插件装载相互等待。

系统来源核对完整player path与曲目identity，跨来源同ID及提取中变化拒绝；无封面ID时低频比较受限字节。管道24MiB/图片16MiB，12秒无完整记录回收，有需求时2至30秒退避重启并推进epoch。未知contentType留空。默认关闭，私有helper与UI仅Debug；Release偏好拒绝系统来源、构建阶段排除库，不代表发行审批。

最终签名Debug dylib SHA256 `00791d89e7d52dadd5c5dd7f37fc4dda4c82991be0fd9af7adc5b878b2b2560a`，helper `1847e5cacdb5dc1e46bd92b837ad0e36de972518e262a60b5ffa664d3fa9da60`，strict/deep签名通过。macOS27.0 arm64，两轮隔离339样本均退出0、gpuDrained=true。live-system的series0005显示真实歌曲名、歌手、专辑封面；generation2的媒体状态/信息/封面事件随后进入原VM，state2下作者面板隐藏。没有给用户播放器发控制命令，未把系统选中来源的自然变化宣称多个播放器完整适配。

live-recovery仅终止该App的直接子reader4334，记录processExited(15)，新reader4377约6.6秒后重新published，同Scene runtime继续运行，退出后无遗留reader。两轮各27个material effect有GPU完成、12个被终端compositor直接消费，graph失败0；当前配置未开启全部可选effect，不能与先前36/39覆盖混作回退或增长。波形仍为受控音频输入，真实系统音频与进度逐项可见验收未由本轮证明。

Debug build、provider五方法及Music/transport/Inbox十方法通过；Observer实际snapshot与Release排除五方法通过，布局登记门通过；广域结构13方法中的两项旧analyzer计数/清单差异仍失败，不作全门通过声明。独立审查未发现新的P1/P2，范围与身份由最终证据包保存。未证明所有播放器、Apple Music真实授权/曲目、所有系统版本、物理多屏或发布。样本主观约70%/低置信；不是像素正确率，既有36/39触达仍不是完整正确性。

本机证据 `.artifacts/scene-evidence/runs/scene-system-media-input-20261005/final/samples/3395777145/runtime_evidence.zip`，SHA256 `55499d2032048a1a0d69c3d9fa674f50351ea31340a19c32cc3b223e7eca3686`，5534260 bytes。保留一份checkpoint缓存与本轮签名候选供连续迭代，其余已停止实验产物按精确清单清理；原用户媒体只读。

## 通用专辑歌手与跨样本后继

后继基线`a63b4112`。Music公开`pAlA`以前未读取，293/297作者的`albumArtist → artist`消费只能回退；现由原Transaction读取并沿原producer原子发布，明确缺失发布空，不保留前曲数据。当前网易云只读探针连续三次没有专辑歌手字段，不为系统来源猜值；歌词仍无已确认consumer。

实际Source/Palette两方法及Provider/Inbox五方法通过，覆盖可选字段缺失、失败传播、换曲拒绝、同曲封面缓存下metadata刷新和字段清除。Debug build与独立产品审查通过。签名candidate dylib SHA256 `1e3f0ff61b681f98aff2a80ac32349f335e9289bdb758208fc5aa79c5fd9862a`；297的`album-artist-visible`使用自有红封面、state1和不同artist/albumArtist，最终显示`Owned Album Track / Album Ensemble`。最初未提供播放状态的`album-artist-controlled`仅证VM输出，不计可见。两段证据不等于真实Music权限/曲目已验收。

基线签名App另在339移除PCM fixture，实际系统声音以generation2进入16/64频段uniform及脚本；series0005/0012底部音频与音频线区域有动态差异。297也在相同系统来源链取得真实文字、封面；312取得文字/状态/频谱，但94/101作者回调赋值`event.state`被只读接口抛错，须裁决官方语义后修公共owner，不能算完整通过。三次原样本运行均退出0且GPU drained。339估计仍约70–75%/低置信，不按新增证据抬高完整正确率。

四路径冻结、App/样本身份、测试/原始运行日志与必要截图保存在`/private/tmp/mwx-media-common-20261005/package/runtime_evidence.zip`，10,196,273 bytes，SHA256 `0077737d8332a02a658d77ccb356f0673962def44d38bf8e93b4f69267c7623a`。证据区1GiB预算已满，工具拒绝提取；暂留该任务包，不调高预算或删除未知/唯一证据。后继追312官方事件可写性与原339剩余交互，之后仍优先HDR/SDR和重型启动。

## 播放事件值语义

后继基线`febce53e`。官方2.8.42/build23967692的自有黑盒fixture证明严格模式可赋值`MediaPlaybackEvent.state`：返回值与truthiness为1/true、2/true、0/false；A/B分别保留123/124，独立观察者及后续真实事件仍收到来源0/1/2。仅消费公开声明和自有黑盒输出，不读取私有实现。客户端SHA256 `daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07`，自有package `780993cc99aa722b33cdc1faca35bdcc959c72ace8d10927a02c5cf62e5b9eb7`。

原QuickJS owner仅为每次新建的state属性加writable；native payload、常量、generation和其他事件字段不变。实际QuickJS修前抛错/修后通过，覆盖三个owner隔离、旧对象保留、连续状态、非法native3及stale拒绝；既有生命周期回归和Debug build通过。312原脚本94/101不改动：相同自有标题/歌手/封面/state1，修前两个回调只读异常、无封面，修后回调完成并显示作者着色后的方形封面。作者使用赋值条件，任何输入最后都会写visible=true；本修复不替作者改为比较，也不证明暂停隐藏正确。

最终签名dylib SHA256 `b8cba76ff05fdf7c79f21cd8b5b1455c4f0c4a512d8eec6d99399edebb1c954a`。两轮同属性/descriptor、22秒、退出0且GPU drained；真实系统音频未固定，不作整帧像素一致性或真实播放器验收。独立审查绑定产品/证据冻结；未做312完整评估，原339仍约70–75%/低置信，27个GPU material效果与12个direct消费者不因本片增加。后继回339封面选择/清除及设置来源切换，再按用户顺序处理HDR/SDR、重型启动。

必要黑盒截图/自有fixture、修前后App日志与截图、身份和门日志保存在`/private/tmp/mwx-playback-event-20261005/package/runtime_evidence.zip`，16,091,423 bytes，SHA256 `1dc9ed67b3601e898b826b186a43e013efc3e384f62e777b5976ea0877827674`。提取再次被1GiB总预算拒绝；暂留任务包，不增加上限。官方测试进程/临时目录已清并恢复VM初始挂起；本机保留最终候选和单份checkpoint缓存供339后继。


## 339音频模式与静音恢复收口（2026-10-06）

基线 `3f48f4a1`，未新增产品能力。最终产品候选 `0e42e723…b419d` 的三轮24秒隔离运行：真实系统音频的8步开关/封面模式、严格零PCM的5步、真实音频的滚动/静态与独立颜色5步均接受，同PID/窗口内生效，无allocation failure，exit0且GPU drained。main audio关闭后两条线消失而底条继续；恢复后重新出图。392/338的静态stage1实际完成GPU，蓝/绿独立线与红底条可见。三轮分别30/13、29/13、29/13个实际material/末端consumer，不能相加或当整样本正确率。该轮alpha0发生在未激活的tint模式，只证明存值，不声称活跃零边界；此前mode2非零范围证据仍独立有效。

补同会话过渡只临时改Debug PCM输入：0–5秒有声、5–13秒严格零、13–24秒恢复；沿真实capture-service小块回调/FFT/Inbox到脚本及395历史/371合成，未直接注入频谱或alpha。实验候选 `d10fce7f…92f293` 的series0001/0004/0008分别显示有声、线消退且底条归点、恢复形态；日志频谱归零再恢复，两个末端alpha对应消退/恢复，exit0/drained且零allocation failure。该临时源码已逐字节还原HEAD，不保留额外fixture接口。它不是用户播放器暂停/恢复验收。

只读复核确认其余392:3、338:2/4是作者字面false，无公开设置或脚本激活；radial blur的varyingUnsupported保留为潜在通用能力缺口，不强改作者内容凑39/39。结合既有媒体、文件reset、字体/时钟/日期/显隐证据，本轮未发现剩余已证可见阻断；完整官方视觉/全播放器字段仍未证明，339粗估仍70–75%/低置信。按用户优先级转HDR/SDR，再重型样本启动；339继续作回归，不称全样本或整体Goal完成。

必要日志/六图/命令与临时输入身份在 `/private/tmp/mwx-audio-modes-20261006/runtime_evidence.zip`，11,498,811 bytes，SHA256 `9d0cba38373ce65e42a2aad15045e864f15c1c16205983103af02cdcfbeb13a4`。证据根总预算已满，临时保留14天；取证后清理四轮HOME/截图重试及实验App，继续复用同任务构建缓存。

<a id="single-replay"></a>

## 单次动画重播与切歌文字（2026-10-09）

U12 `3477054430` 的 billboard=true 副本在两次媒体属性事件后 Artist120 持续不可见，首断点为 completed Single 保持旧 elapsed，以及持久 alpha=0 压住 Timeline。沿唯一 playback state 与 layer candidate 修复；拒绝命令保留旧值，不加样本分支。官方2.8.0.42（EXE `daac1ea7…bda07`）自有 genericimage4 双卡两次重播分别56→120→128、64→128；六卡中三种含play赋值顺序渐显一致，play后pause/stop三卡保持首值26，未保留手写0.5对应64。旧genericimage2正控失败已排除；无play setter语义、头部鼠标输入未验。最终签名Debug dylib `1075c365…e3ecc` 在同一输入连续三轮恢复两卡；U12两次受控媒体事件实际显示ARTIST ONE/TWO，退出GPU排空。源码/App、输入SHA、官方序列和运行日志在 `.artifacts/tmp/u12-dynamic-media-20261009/` 的 `build-final.json`、`implementation-freeze.json`、`official/official-observation-receipt.json` 与 `native-media-billboard-final/`。受控媒体输入不证明外部播放器供给、封面替换、完整U12或全样本正确率。

三个既有产品文件只补播放状态与已准入属性接管；Timeline 15、dynamic layer 16最近门通过，独立只读审查无阻塞。最终native六卡40帧中31帧在timer触发后，top三卡逐帧相同，bottom三卡全部RGB26。无play的setter/暂停、非alpha和跨owner官方顺序尚未作观测，不扩大合同。
