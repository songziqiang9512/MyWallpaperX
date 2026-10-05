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
