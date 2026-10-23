# 普通视频候选首呈现完整性

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。截止2026-10-23；现行职责归[启动合同](../architecture/scene-launch-responsiveness-contract.md#initial-video-presentation)，待办归[队列](../roadmap/scene-open-breakpoint-queue.md)。本记录只关闭普通可见视频的候选首门，不关闭全部视频能力。

<a id="initial-video-presentation-20261023"></a>
## 通用语义与真实收益

旧Host把首个GPU成功当作内容完整，普通视频没有buffer时也可能先提升空绘制。Source现在仅报告同一次prepareFrame的ready/pending/已建立失败；实际选源resolver保留pending类型，Renderer只收集真正经过可见及材质资格的普通image消费者。Session以同一次、同一surface对象集合提交的内容资格与GPU完成组成首呈现cohort，Host仍唯一拥有旧active、提升、取消、超时和drain；没有新播放器、clock或延时猜测。隐藏视频、未选authored fallback、已有still及已建立局部失败不会阻塞健康画面。

冷暂停自有红视频的旧App窗口只有灰底与青色peer；候选窗口已有红视频和peer。候选先提交pending帧，沿原资源commit推进，暂停重试保持frame0，真实脚本计数通过peer alpha=1/n送到末端像素，n=1的原颜色门通过。改名双surface同次资格、可见截断视频的局部回退均通过；后者未直接观测payload失败与AVPlayerItem失败的具体分型，不作该子类型声明。

原3321237804背景270在frame64发布generation1，23ms后Host提升；此前空视频帧仍透明提交，最终原图保完整背景、人物、时钟与已修左上光束。首帧decoded0而requested约1.60s，本批保既有首媒体命令commit/下一帧合同，不承诺首seek目标额外同步。等待时间不是性能收益，旧基线196ms空窗与本轮耗时也不作同条件启动性能对比。

独立3292370168原包视频151在提升前发布并持续更新，骷髅、方块与背景轨迹保留。候选与修前App在相同project/pkg、静音、30FPS、8s/after4s下均有utility505失败及相同七项graph运行门失败，封面区域均空；矩阵两者都NON-PASS，不能把本窗空媒体封面记为本批回归或已修，也不以本窗无媒体资格推新缺图。未锁动画/媒体/viewport相位，不认整景官方一致。

## 身份、验收与局限

候选为签名优化Debug App SHA256 `c10d061bb304c116d8815284c6780d29af346ddfe0dd29f877806ef9290d1a13`，5514冻结输入、19个本批产品文件与导出一致，零构建警告；修前App `a40fd213ae9ede97baeda25607874ce8827d2f0f1c45d0a1a53255f2e3f644d0`。并行UI文件以HEAD构建、未混入。所有本批App运行正常退出、surface释放并GPUdrain。

纯cohort八例覆盖pre-seal GPU、不同attempt不累计、surface对象替换、hold至父级确认与迟到成功；实际Host门新增八个延迟父级断言，候选通过、HEAD旧Activation五个反例失败。该门使用受控终端回调，不冒充真实GPU故障注入。真实App另验post-prepare shared heap不重放及候选拒绝保旧窗口/clock两例。资源Snapshot/selection门、真实AVPlayer暂停seek替换/停止邻例通过；property-video两个既有GPU harness仅完成编译准备，未跑完整媒体矩阵。

实际App三例通过，补强后只复跑受影响暂停两例并通过。最初测试错误忽略PNG的ICC导致cyan误判，修正为sRGB后保持原阈值；另一个失败要求只出现payload preparation日志，误排合法AVPlayerItem失败，已收窄到可证输出。产品字节未因这两项测试解释而调整，原失败收据保留。独立代码与终端审查通过；去重visibility/callback日志不能当VM调用计数，最终门使用真实scalar/像素反证。

未验Release/HDR、设备丢失、全部多屏像素、完整seek/媒体依赖、active reveal、全格式和长稳；未给CPU/GPU/内存或启动收益结论。五秒超时仍由旧Host负责，无法产出内容的pending源不能被超时伪装成ready。

## 产物

必要原图、冷暂停红绿对照、自有输入、构建/签名/冻结身份、同输入329失败及三份独审归正式证据库`initial-video-presentation-20261023`（ZIP 17,478,593B，SHA256 `b063675f047c4c53bd617a859ea05a59a4e869a52babeb116f984cf57a5cfc72`），普通14天、单包32MiB、总5GiB。首次私有访问与exhaustive switch编译失败、ICC测试误判保最小日志；不保重复staged App/HOME。连续光照迭代保留唯一`.build-cache/video-extraction-demand-20261021`与其冻结源码导出`.artifacts/light-compatibility-program-20261023/source`；并行UI App、原样本与虚拟机主客户端保持。
