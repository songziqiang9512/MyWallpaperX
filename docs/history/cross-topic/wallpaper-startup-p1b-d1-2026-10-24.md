<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**

# Web 捕获解析

> 截止：2026-10-24。当前Web职责见[项目模型](../../web/web-project-json-runtime-model.md)和[现役状态](../../web/current-state.md)。

## 改动与纠偏

P1b 沿原 service 统一作者输入捕获：own/属性来源项目的同份 Data、实际入口与根、目录/静态摘要及完整语言序列，进入真实纯解析核。memo、磁盘和 flight 只共享纯 product；主 actor 在最后 await 后装配当前属性、书签及 grants，原 awaited 保存/CAS 删除边界保留。签名预算与无文件数上限的 summary 分开，205 文件之后仍可冷播；前后片段和 service-worker 规则不扩张。原临时跨阶段重开/ctime 收据退出，不声称目录或 WK 页面获得原子快照。

完整身份补入实际 summary/topLevelNames，已捕获依赖存在性不随后继磁盘删除而改变；不被认证覆盖的 summary 不授复用资格。符号链接声明入口保原 canonical 语义。普通文件先非阻塞打开再检查类型，FIFO 不会在取消 join 前无限等待。同步 canLaunch/WebValidation 只查选中入口事实，不另读项目 JSON；无 pin 的旧兼容发现成本仍在。

每次准备在同一 actor admission 取得实际 managed roots 并集租约，覆盖后台 capture 与共享 flight 的 join；成功 token 随通知交给原 renderer session，失败、取消和无消费者请求按原生命周期释放。纯 product/cache/flight 无租约或授权。Manager 推进唯一产品 epoch 后，通过 App 回调取消旧 Web 准备，涵盖本地 Video、静态图和 stop；Web 先取得进程预备意图再采 service 代际，避免自我判旧。preload 的 known-live 跳过判定仅查已存绝对路径 override/书签状态，保守跳过已知 live 作品，避免在租约外解析定义；未跳过项仍走持租约的完整准备，正常播放按实际定义处理。

独审发现的摘要事实漏入 key、声明 alias 回退已修正。完整构建额外暴露通知 nil-coalescing 的 Optional→Any 推断警告，仅加显式可选 lifetime 局部变量；实际通知/取消门重跑通过，其余28个 Web owned 文件未变，并重新独审/构建。v1 未运行，不作性能原点。

## 行为与构建资格

Web 六 CPU 模块通过（25.939s），执行真实 capture/parser/cache/选择生命周期；窄类型修正后实际 intent 模块再次通过（5.250s）。Swift6 complete concurrency/default-MainActor 编译通过。root 另实际执行资源授权两测试，真实 WK/书签移动、精确文件/邻居拒绝、撤权等通过（模块29.7s）。最初误用系统Python3.9在导入期失败，0产品执行；改用3.12后通过，不归产品回归。

自有三文件冷 service 签名+真实解析核探针，解释输出相同：payload读取API操作10→3，返回字节800→190。它不计 kernel read syscall、物理盘、OS页缓存 miss、页面、manifest 或完整 setAsWallpaper 前门；不是全启动或所有输入的比例。

## 同条件产品对照

直接前驱仍为180 App（executable SHA `180ee9d31245d4d99d620968aa675bc807ee879580bfd81ef8ed1c8d3d511ca6`）。有效v2为`05f7e5b011eb1cfb8a6c87f8a0702171186c7af872687eb6518e42f2d02f7133`；其原始C1回退另存保护包。最终v3在原mute migration之后、coordinator/configureRuntimeSwitching之前安装回调，恢复Manager原初始化时点；端点门重跑通过。独审确认Engine首次初始化并未被提前，故不得将这项装配纠偏记为原回退原因或修复。

v3优化Debug/WMO构建329.471s通过，构建前后Git可见文件摘要均为`b173d5a0aac7267785527d0f8b7958be40b0a1c9de0eb2d5172c07ed268ef195`；executable SHA `355bdb60b3b72958fa5a64f078bdc94661d67fdd222c907a85da432997c87cf6`，CDHash `7c3ef9dc8b6585900798f5045133cff459558ff8`。专用bundle `com.songziqiang.MyWallpaperX.Debug.Startup`、Team `H9QWU9XN8R`、2.11.0(283)，deep/strict验签通过。仅未改InspectorBadgeView既有NSBox弃用警告。原标准域token、物理HOME/cache、私有suite、输入及生产偏好双摘要、精确PID/出生时间清理沿原wrapper，30FPS；没有清OS/WebKit cache。

### v2 原始Web回退与诊断

轻输入900000001五组AB/BA，30个App、90请求；C0/C1各5个独立App/arm，W0每App六个相关暖原点。原数不剔除、不并入后续v3。

| 条件 | 前驱中位ms | 候选中位ms | 前驱/候选噪声 | 配对App组降幅中位 |
|---|---:|---:|---:|---:|
| C0 | 683.239 | 863.658 | 269.632% / 5.583% | -24.013% |
| C1 | 682.758 | 861.350 | 2.188% / 6.918% | -24.761% |
| W0 | 296.613 | 275.557 | 10.070% / 64.604% | 7.074% |

C1增加约179ms且超过原非目标门，不能用W0下降抵消。selection→hello中位422.398→600.980ms，几乎解释总增量；profile/origin/store相同，页面创建/ready/snapshot/可见确认没有同类增量。

三对无页面daemon spawn→hello→shutdown诊断保全部原点：前驱2078.200/570.646/592.852、候选1608.229/607.479/599.772ms，不支持固定180ms独立binary增量；它不经过产品父端，不是正式性能验收。一次父采样显示主线程主要空闲，后续只补漏采child；第一次漏采因/tmp与/private/tmp别名，已按规范binary身份修正。两child均有NSApplication/LaunchServices/TCC等待，样本跨hello和页面阶段，聚合采样数不能当耗时差值。未观察候选新增解析热点，不足以归因。DYLD统计请求无有效输出。两App原Info字典与entitlements相同；未执行备用Info扰动/重签、未重置TCC。

v3资格轮未改180基线C1已变为874.071ms、v3为904.963ms；原基线自身不同于前一五组，故不把变化归给装配调整。原v2回退与首次C0 2525.474ms、候选W0慢点全部保留于`wallpaper-startup-p1b-c1-regression-unresolved-20261024`保护包。原因未闭合，不写“已修复”或“不是回归”。

### v3 最终Web五组

另起固定v3的五组AB/BA，30App、90请求，条件与统计门不变；资格轮和有采样诊断不混入。

| 条件 | 前驱中位ms | 候选中位ms | 前驱/候选噪声 | 配对App组降幅中位 |
|---|---:|---:|---:|---:|
| C0 | 899.851 | 874.380 | 4.946% / 7.369% | 2.433% |
| C1 | 871.188 | 901.436 | 6.271% / 4.630% | -3.142% |
| W0 | 270.620 | 274.718 | 23.367% / 5.167% | -0.766% |

C1当前总中位增加30.248ms（3.472%），在5%相对中位范围内；但基线计时噪声超过5%，不能据此证明完整非目标卡或全场景无回退。三个条件均无正式提速结论，不追加重复轮求通过。W0按App组配对，不将30相关暖请求当30独立App。性能卡还缺CPU/GPU尾部、峰值内存与能耗，整体未通过。P1此后只保必要纠错，不围绕轻输入继续微调。

## 证据、边界与后续

最终有期限包`wallpaper-startup-p1b-d1-20261024`保build身份、真实解析减工/行为门和v2/v3有效运行原数，默认14天。原v2 Web回退/基线漂移与采样诊断在上述最小保护包，不自动到期；旧600ms与P2a marker未归因保护包继续保留。`batch/report.json samples[].label`映射原路径，实际文件按数字id存于`batch/samples/`，不依赖清掉的临时路径。

Swift产品通过1000行门；手查本批新建代码未越线。原`test_scene_shader_preprocessor.py`1659行（主体为旧嵌入Swift harness）行数未增，本批只适配throws，不将Swift门通过写成全语言或全仓结构达标。未补完整画面、真实sourceChanged竞态注入、物理Space/多屏、30分钟长稳或Release；内部正常提交/presented不代这些门。

保留一份DerivedData与原P0/180比较App、当前候选和v2未归因诊断App、固定只读输入及必要before-source，供持续goal；各运行HOME/staged App按原wrapper删除。最终精确清理/保留收据归任务根，结果包保清理前文件清单与身份验证；不批量清未知材料，不把移动进忽略目录算释放磁盘。全部实施保持未暂存、未提交、未推送、未安装；主工作区保持干净。

下一步按专项D2迁结构字节读取，再闭合receipt/全部消费者/释放后才能启用package backing。现有NSApp启动等待可作为P5后继成本线索，但P5a不省WebView创建，必须完整reset/drain/两槽和新意图身份才可复用；不为未证收益只加闲置协议。专项goal仍active，本批不认领全部改造完成。
