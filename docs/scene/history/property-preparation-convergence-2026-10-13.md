<!-- document-role: historical-evidence -->

# Scene 属性窗口准备复用与来源校验

> **历史证据 — 非现役入口**。截止2026-10-13。现役职责归[启动失效域](../architecture/scene-startup-pipeline.md#5-按需加载与失效域)，属性能力归[面板合同](../capabilities/runtime-input-property-coverage.md#op-user-overview)。[性能卡](../roadmap/performance-convergence-card.md)、[属性卡](../roadmap/properties-panel-card.md)及[断点队列](../roadmap/scene-open-breakpoint-queue.md)继续推进；本批不关闭整个专项或长期Goal。

## 实现与边界

每次打开属性窗口原先新建inspection controller；窗口交付控件后释放该实例，已有snapshot因此无法跨重开复用。沿原owner保一个独立准备实例，只持有最近一次成功的projected context、完整请求identity与来源stamp；不留第二份source facts、GPU/VM、parser或运行资源。冷准备仍走原完整builder→原context→控件/store/typed consumer；值、资源、结构更新出口保持原链。

实施前设计已在属性卡落库。项目namespace在任何project/index/package读取前取样；一次完整builder固定初始观察的真实目录。包经原校验后、ResourceView建索引前取样原入口及实际松散/解包/stock根；完成后复核。record/URL/更新时间/完整overrides与来源版本全相等才命中，MainActor交付再次读取当前download record和overrides。删除、重导入、条件值变化或窗口替换拒绝旧结果或为当前identity重新准备；关闭取消交付。pressure清退并推进准入epoch，在途结果只可交付仍有效窗口，不能回填。

FTS_PHYSICAL/NOCHDIR复用每项stat，inode/device/type/权限/size/mtime/ctime和完整namespace均检查，遍历/I/O/未知元数据、symlink、特殊文件或预算不足整体miss，不保存部分遍历。保原根及resolved根，原入口改变时重查；alias A→B→A不再把B定义盖上A版本。stamp按根共享前缀、只保相对路径及metadata，消除重复绝对路径存储。排序与输入根identity保留，未按样本、路径或hash选择算法。

保守4MiB估算计完整catalog、投影/条件、effective值、完整overrides和全部stamp；普通String与条件token按各自存储成本估算，不提高预算迁就样本。错误、失败包、无控件或超预算context不缓存。门只约束保留估算，不能当物理footprint或FTS遍历瞬时峰值上限；宽目录先由系统FTS建立children暂存，随后仍拒绝超预算版本。

## 测量

基线语义为92cc4b7d每次完整source facts+context，候选在相同完整CPU链上复用成功context并重验来源。单个Swift -O二进制，GPU/无关命令叶桩不参与计时；保真实builder、parser、compiler及签名App同份stock资产，默认值、只读293/304副本、同一隔离PKG暖cache。串行交替三轮，每进程一次首次准备及12次重开；autoreleasepool使每次临时facts退出。CPU取进程clock，physical footprint在池退出后采样；checksum与缓存准入/命中逐轮核对。

| 输入 | 首次CPU毫秒：基线→修后 | 暖CPU毫秒：基线→修后 | 暖修后/基线 | 保留估算字节 | 12次后physical MiB：基线→修后 |
|---|---|---|---|---|---|
| 2932157836 | 251.887→352.520 | 241.622→48.599 | 0.2011386 | 2041532 | 58.704→59.360 |
| 3042492564 | 402.590→508.974 | 388.654→54.203 | 0.1394623 | 2863800 | 152.829→152.751 |


首次准备增加来源校验成本，重复打开降低CPU；范围是这两份输入的准备链，不是整App CPU占用、打开总延迟、GPU、温度或能耗。物理采样用于看本探针12次重开后的驻留，未采真正解码/FTS峰值，也不证明连续壁纸切换后的engine资源回落。估算与physical值分别保留。

## 验证与收尾

编译原请求/cache/version owner的叶桩行为探针检查28个输入/事件/失败反例：完整override、定义/资源改名、同size且恢复mtime的改写、增删/权限、缺失/symlink、准备中变更、失败包/文档、无控件、压力、关闭/替换、当前record删除/重导入、alias ABA及重新指向、解包hidden marker、stock增项、大值与宽目录预算。宽目录名字长度保证门限，不依赖TMPDIR。收尾退役guard拼写断言（由上述行为反例承担），并把测试选择器的空匹配输入绑定到受控模块清单且断言零执行，避免真实新增missing模块使旧负例意外运行。关闭/替换用后台队列→MainActor barrier后断言，未靠固定睡眠推断迟到结果。

最终接受的Debug -O App SHA256 `1afdff423d21ac015543cf20010152a00c451f430e02d09a9fbc38b238cca8ad`，4270个构建输入无漂移；App/daemon PID42030/42043。普通产品入口播放293，正常滚轮可到格式项；window26424从21:45变21:46:49，HH:mm:ss关闭重开仍保存，reset恢复21:48。同record只有一次launched，不把缓存命中替代实际文字。未用于本批修法/CPU基线的2134765860在window26456显示21:51:44、房间/灯光有输出，属性关闭重开保持Time Of Day=Automatic。右侧灰色媒体占位保留，不记恢复媒体。替换293时41 VM owner quiescent，failures/timers/jobs/mutations/dynamicLayers均0；停止/退出后两进程均消失，最后213细粒度退出行未收到，不推断其计数。

另发现U42无障碍端点崩溃：详细设置on后AXScrollToBottom在准备缓存候选PID39401及原92cc签名基线PID39954均触发主线程EXC_BREAKPOINT，栈为SwiftUI AGAttribute.syncMainIfReferences→ForEachState→LazyScrollable→AccessibilityNode；两份ips保留。普通滚轮实际格式操作已验，但此端点未修。暂试普通VStack，三轮打开/AX核验/关闭的App CPU中位数1162.618→2983.493ms，额外工作明显，已撤销；不把该方法当修复。原布局加准备复用的对应观察中位数1004.897ms，但各周期20.85–40.59秒且首轮重叠，不能宣称稳定整面板收益。这些App操作周期无壁纸播放、sds=on，采用Mach ticks/timebase转换并保全部raw快照；不是打开延迟，也不是engine CPU/温度。

后继先顶层设计原生AppKit虚拟列表/控件复用，退出SwiftUI lazy集合端点职责，复用现值/控件/store/typed链；不能靠隐藏内容、全量eager重建或吞掉事件换通过。

独立静态审查先后纠正原包失败准入、当前记录与窗口替换、alias ABA及测试预算依赖；实际运行和可比成本证据独立列出。leaf spy不代真正包/stock/App路径，build/测试不代性能收益。HDR/SDR、多surface、全部属性/媒体、完整callback、滚动及长期切换仍未闭，历史213媒体异常/右侧黑块与293取消异常继续原队列，不因本批改动记恢复。

限量proof归`.artifacts/tmp/property-preparation-convergence-20261013/proof`，保最终成本、harness/输入身份、签名App、关键日志/截图及审查。退出后清理本轮native二进制、module cache、临时HOME、重试App和重复输出；只留下一批当前候选与一份既有只读workshop副本，以及原连续DerivedData。不删除旧唯一未解决证据。
