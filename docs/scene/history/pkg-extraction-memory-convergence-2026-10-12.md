<!-- document-role: historical-evidence -->

# PKG提取内存收敛（2026-10-12，10-13收尾）

> **历史证据 — 非现役入口**。后续仍归[性能卡](../roadmap/performance-convergence-card.md)及[属性卡](../roadmap/properties-panel-card.md)，本批不关闭既有视觉断点。

通用语义：原`ScenePkgCacheExtractor`持有一次owning包快照，将已由reader验界的条目准备为借用Data视图，用于source SHA、冷输出与暖cache逐字节校验；不再为冷输出调用subdata复制，也不重复hash暖cache内容。原package SHA、entry SHA、marker与精确文件集合均保留。公有`readEntryData`的零索引/独立Data合同不变，没有新解析器、常驻cache或视觉特判。

同project/package的外置文件锁覆盖快照读取至marker发布，防止本owner并发复制大包与删写同cache；不同包仍可并行，抛错/进程退出关闭FD即释放，锁文件不unlink。缓存root/child的regular与symlink检查先于内容读取；异常锁路径不阻塞。在同一existing owner内先读取目标cache卷的大小写能力：敏感卷保留独立大小写路径，不敏感卷只复用同目标同字节alias，冲突内容或实际保留marker目标拒绝；缺少能力返回ENOTSUP，查询错误传播，不猜别名安全性。原root lstat拒绝保留后，单次canonicalPathKey统一枚举器与prefix，修正/var HOME和/private/var子项造成的假cache miss；不逐文件realpath，不另造资源解析owner。reader在reserve前拒绝不可能的entry count。直接mmap所有source被否决：legacy/user目录没有immutable publication证明，原地写/截断会破坏快照稳定性。

## 三轮同条件结果

实际3662790108隔离副本的PKG为569,384,066字节、1175项，提取1171合法项；own extractor独立进程使用同-O工具、每轮新HOME，先cold再warm。OS文件cache已暖，cold/warm只表示提取cache状态，非物理冷盘。下表为10-13最终volume及canonical-root修法的重新测量，未沿用早期候选身份。libproc kernel lifetime footprint峰值：

| 指标 | 修前3轮 | 修后3轮 | 范围 |
|---|---|---|---|
| cold峰值MiB | 712.64 / 712.61 / 712.59 | 551.58 / 551.63 / 551.67 | 均值下降约160.99MiB、22.59% |
| warm峰值MiB | 770.41 / 770.41 / 770.41 | 711.28 / 711.28 / 711.33 | 均值下降约59.11MiB、7.67% |
| cold耗时ms | 1022.7 / 826.2 / 786.4 | 1009.7 / 829.4 / 765.2 | 基本持平，不声称稳定启动收益 |
| warm耗时ms | 720.3 / 704.9 / 699.0 | 560.6 / 539.0 / 524.8 | 本次三轮降低，仅提取cache校验范围 |

实际App另有修前/后各三轮：同Debug显式-O、单3024×1964 surface、目标60、静音fixture、execution observations关闭、fresh HOME/cache，warmup30s/测量62.5s。全部exit0、present、GPU drain、failed frame0。主进程峰值1979.86/1982.33/2005.67→1979.61/1974.32/1942.38MiB，GPU峰值约1367.84MiB，GPU p95及FPS近似持平；不能宣称App整体稳定内存或GPU收益。launch-return30.559/29.357/30.587→29.941/48.334/28.572s，其中48.334s保留且未归因；不能宣称稳定首帧收益或已排除该延迟。

## 正确性与边界

18个实际Swift门覆盖冷暖、同尺寸/短文件损坏、额外文件、同metadata原子替换、资源改名/重排/空条目、traversal与未知类别、同内容alias复用/冲突alias拒绝、巨大count/越界、线程/跨进程并发、同key等待与distinct key通行、退出释放锁、root/child symlink与FIFO。真实APFS/APFSX镜像执行生产SceneProjectLoader→extractor→SceneDocumentLoader，入口改名/顺序、同字节与不同字节大小写路径、loose有/无、相邻marker拼写均有反例；/var HOME复现并闭合暖缓存资源与marker mtime重写，损坏仍重建、新package仍选择新key。暖cache没有重写marker。独立未计时核对修前/后1171输出的全部字节hash及解码后的marker字段相同；原始JSONEncoder key顺序不固定，不能用marker原始SHA差异判语义变化。

最终Debug-O build及相应结构/质量/依赖门记录在证据根。两样本均由签名隔离App真实渲染：3662790108仍有原intro/HUD叠字；后验确认84fe33b9已与本批前后同样construction预算4096/计划935耗尽、全域owner=0，开启观测/取消性能驱动仍失败。App测量属于退化静态场景，不代表正常脚本播放。本批测量时未证明具体安装失败原因；后续[有界host修复](scenescript-host-heap-admission-2026-10-13.md)已确认原16MiB共享VM在第742/935个owner安装时耗尽，并恢复原包开场与更新，准确引入commit仍未知。正常播放的App性能需重新建基线，不能沿用本批静态负载宣称收益。独立2134765860房间、灯光和时钟未见新增缺损，灰矩形旧问题仍在。并非官方全片、HDR/history、桌面正常产品链、所有文件系统Unicode等价或全样本验收；未知volume运行尚未实测，canonical查询失败只使existing cache无效。锁仅约束本owner，不承诺返回后抵抗外部任意篡改。

早期候选证据根`.artifacts/tmp/startup-resource-convergence-20261012`：`performance-comparison.json`、前后App/源码身份、`marker-proof.json`、cold/warm与App receipts、原样截图、测试/build/gates日志及最终review manifest。首个before driver解析失败不计三轮基线；有效基线为before-valid-o-1至3。源样本只读；收尾删除副本、HOME/cache、staged App和生成源码，保留必要证据及原一份DerivedData。

最终源码与测量归`.artifacts/tmp/startup-active-playback-20261013`的8-source lock、final-marker-proof及final-pkg-performance-comparison；真实卷及路径别名before/after归`.artifacts/tmp/pkg-physical-alias-repair-20261013/receipt.json`。原第一轮独审因大小写敏感入口丢失拒绝，物理alias及HOME路径别名修正均已SOURCE ACCEPT，最终完整身份独审另有回执。普通帧没有新增文件系统查询。

正常播放新基线使用同一最终Debug-O签名App、8-source lock，3024×1964单surface、60目标、静音输入、execution observations关闭、每轮fresh HOME/cache、warmup30s/测量约62.7s，三轮exit0/present/drain且domain/memory/failed frame=0。进程kernel lifetime峰值2088.25/2088.75/2054.46MiB，completed FPS16.749/16.710/16.780，GPU p95为44.001/44.082/43.949ms，CPU p95为12.263/12.386/12.207ms。ready观测25.933/24.897/26.590s只包含该driver观测延迟；不是独立精确首帧计时。Root实看ready仅标题、after30s太阳系/HUD；该负载与旧owner停用测量不同，只作下批起点，不归因给PKG改动。

最终App、HOME/cache、媒体副本与采样工具已清理，最后3张原样截图、必要receipt及压缩日志在最终证据根约31MiB内保留。提取至正式evidence cache因既有总预算超限失败；工具此前prune-expired为0，不删除未知资料或静默放宽预算。继续迭代仅保留`.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData`一份构建缓存；最终签名身份为采集时回执，staged App已删除。
