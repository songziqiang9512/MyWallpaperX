<!-- document-role: historical-evidence -->

# 动态实例槽位寿命与视频接续资格

> **历史证据 — 非现役入口**

截止：2026-10-29。当前职责归[D4实例寿命](../roadmap/batch2/script-component-api-design.md#dynamic-layer-slot-lifetime)、[API台账](../capabilities/scenescript-api-coverage.md)和[视频合同](../capabilities/material-video-assets.md)，未闭项只归[队列](../roadmap/scene-open-breakpoint-queue.md)。本记录不授动态视频创建或官方时钟语义。

## 实施与必要边界

基于11ff2298f，原C动态层只追加存储，负ID从-1重扫全部历史record；持续重建既累积槽位，又反复搜索。现原domain在安装作者层时归纳负ID起点，出生单调消耗；原数组以free-head/next-free复用共同事务已终结的动态槽。作者槽不回收。失败/回滚出生也消耗ID，旧JS对象不阻挡回收，也不能指向新实例。

所有动态可达layer、property及媒体handle沿原LayerAccessHandle/resolver消费expected ID；视频/纹理动画重复lookup退出。journal、value participant及pending/rollback/order未终结时不回收；沿原finalize/rollback/abort仅处理journal触及的CREATE/DESTROY索引。失败构造撤对应CREATE，不被重放复活。原record释放合并，未新增owner、clock、逐帧扫描或Swift调度；产品净增42行，删除失效baseline count。

最近C七个tests及额外ASAN通过，后者1391 checks/0 failures，含5000轮、旧对象/方法/媒体ABA、失败出生、peer接纳/拒绝、snapshot回滚/abort和无topology的value participant。相邻Puppet bones/animation共28 tests通过。首次两门在外部stub缺CameraDescriptor时编译失败、未执行行为；仅补类型别名及eye/center/up数据字段，完整共享输入typecheck后再跑，未改算法或断言。

## 原生App与独立样本

同一8-live自有图片输入，零PCM、中心pointer、60FPS请求、18s窗口、独立HOME；每次先退上一代8层，再生8层并保留至下一帧，不使用同callback净零出生。旧App为本轮此前保留的11ff C实现，带未执行的视频专用临时探针；本输入无视频。其App SHA为d852aa087dfd2a66ff99ba446ef52e5296c268938db0ab7bc011f1afde6c77d9，不冒充纯净HEAD全产品基线。

候选签名Debug一次34.93s、4409输入无漂移，App SHA为be0cf81c04be60321a72a7d08744aed04f7fa720bcd1e318f5fd09b0ff0b8c9d。源码中的视频探针已恢复为原产品。旧图age15.436/callback437记录2832次出生、2824次销毁，触发夹具UNDERQUALIFIED门；**未复现原生容量耗尽/null**。候选图age15.087/callback904为6704/6696、active8，旧对象及绑定方法各拒绝8127次，14s资格完成后方块仍移动变色。C门/设计证明动态槽高水位16，native没有额外测该字段。此单对构造负载不认稳定CPU/GPU/内存或整引擎性能收益。

候选独立原3792817546运行10s，原project/pkg哈希相同、克隆inode独立；63个动态层在frame1/2均publication63/encode63、GPU完成，照片与部分日期/时钟可见。仅候选运行，不作前后同phase无回归或音频样式比较。所有原生图均为原3024×1964 cover输出，左侧文字/首方块或时钟被裁，未完成完整注册ROI。三run均App0、VM failures0、surface1→0且GPU drained。

产品/测试与最终原图经独立Sol Max审查，有界GO。必要日志、原图、身份、测试/审查收据及自有输入保于`.artifacts/scene-evidence/runs/dynamic-layer-slot-lifetime-20261029/`，普通14天。更宽并发、媒体实例完整生命周期、HDR/多屏与长稳未随本片关闭。

<a id="video-carrier-qualification"></a>
## 视频供帧资格：仍未改产品

3372715909原控制器120先保存12份初始配置并删除原层，update逐帧删除旧实例、创建当前视频并play；当前constructor返回null后异常退出。它按本地小时自动选昼/夜/黄昏/雨景，或以tod手选时段、newproperty1选三种主题，没有生效点击切换。该首错已移至正常播放能力队列，槽位修正不是视频恢复。

原包12路3750×2250/60FPS/12s H.264的packet时间连续，未测有效内容帧率。新30s/60FPS/零PCM/中心pointer探针在首个长发布空档中比较Scene请求、output帧host映射和当前host映射：12路三种hasNew均false，映射差约1ms，查询延迟1.218–1.722ms；不支持改clock或移动prepare位置，copy/acquire未重复。

同12路且保原prepare/定位/EOF，仅临时关闭11个video tracks时，可见100在24.5s有1464次发布、最大间隔.065s。全部恢复后各首帧2.982–3.055s；只恢复106则.322s，可见100在随后5s仍295次、最大.098s。disabled期间真实EOF继续推进。OS ps的CPU/RSS受日志变化及进程口径限制，不证decoder停转、整体能耗收益或无缝切换。三次均正常退出/drain；必要协议、身份、日志、原图及撤回patch归`video-publication-qualified-20261029`。

10-21提取/Metal包装原型早已因两对footprint分别+69.38%/+29.59%撤回，第三对未跑；仍保原eager链。旧官方隐藏clock两候选均未通过，保持STOP_UNKNOWN，原身份归`video-extraction-demand-stop-20261021`、`video-hidden-clock-20261021`。上述新轨道结果不重授旧候选。

本轮固定官方2.8.42/Win11自有双实例载体仅见getter/ACK0、未得视频正控；P1命令返回0但无属性ACK，后段捕获冻结原因未知。两个窗口/资源布局未资格，**不由双方6.25读数认共享播放时钟**；lifetime板未启动。CLI关闭未确认且CUA报noWindowsAvailable，用户已手动关闭唯一实验预览，VM及主客户端保持。失格输入/原图及命令收据归`video-instance-qualification-stop-20261029`。一次修正载体离线准备好，未运行或据此实现视频时钟。

## 清理与开放边界

旧三次视频探针的App、HOME、重复截图及构建输出已精确清理约1389MiB；后继只留一份显式构建缓存`.build-cache/scene-gravity-20261028`供连续迭代。原生槽位运行环境在提取必要证据后清理，不保Workshop包副本或安装App。

同callback新生立即删除的净零拓扑，C导出最终destroy而Swift目前要求已发布实例，只有代码证据；已单列队列，不混成槽位回收失败。本批未实现动态视频、后台需求优化或官方实例身份，其他视觉/音频/属性问题按原队列保留。
