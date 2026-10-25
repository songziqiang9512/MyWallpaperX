# Scene 启动 D18：构建期 stock 清单

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**
>
> 截止：2026-10-25。步骤与停止条件归[启动专项](../../development/wallpaper-startup-optimization-plan.md)，缓存边界归[启动合同](../architecture/scene-launch-responsiveness-contract.md)。本批实施默认stock首建减工，限定行为/构建/产品资格通过；5/6性能噪声门失败，不授整体提速、无回归或完整P2/P3/P7。

## 成本先于改造

以D15实际最终App `bb1d2199…9256` 的stock为输入，原六源Index/Root探针一次运行，未启动产品App。默认槽首次154.214125ms、命中0.017042ms且同一Root；另一child的原枚举128.777250ms、Root建表3.437583ms。2264项资源的路径/kind/长度、原始/大写/invariant查找、逐项payload SHA和完整availableRelativePaths全部相同。stock整个bundle为2273文件、55916121B，区别于assets可见项数。

复制及完整哈希在计时前已暖文件系统；两child不是等OS缓存A/B。该同步叶窗不代表CPU独占、OS冷启动或App净收益，也不把D17模型组合窗之差归给stock。真实首次成本足以选择原owner的构建期清单；未再增加variant内存层或完整PreparedContent缓存。

## 唯一生产与消费链

先在专项P3b及原design登记写清方案，再实施：

1. 原 `copy-scene-stock-assets.sh` 在rsync过滤完成后调用薄Swift生成器；生成器和原Index源码同编译，仍用原完整 `buildWithCompleteness`，不在Python重写hidden/package可见规则。
2. 只有完整结果才能原子写bundle顶层 `SceneStockIndex.json`，位于assets外；原运行资源/许可证字节不变。清单前先删除旧输出，生成失败使构建失败，不携带旧清单继续。
3. envelope仅含schema1、原始行JSON Data的base64与其SHA256；行仅raw relativePath/Int64 fileSize。不存绝对URL、构建机kind/locale或lookup。生产与消费均限4MiB；消费先核常规文件/type/大小，再最多读取cap+1，解码前已有界。
4. 原默认 `BundledStockRoot.value` 仅在canonical assets位于本App、sidecar仍为同stock bundle的原leaf时尝试。保`/tmp`→`/private/tmp`系统别名，拒绝sidecar软链（含指回同bundle）。custom/显式stock、外部重定向、loose、package不进入该快路。
5. 原IndexBuilder核schema、payload SHA、长度、路径/唯一性，仍沿当前Locale分类和排序，再交原Root双firstWins表。排序出现相等歧义则撤快路；任何缺坏/越界清单也回原完整枚举与原成功完整Root共享，不常驻负结果。

自SHA只保证清单自洽，不能发现一份合法但陈旧的清单；assets关联靠同次post-rsync完整生成、失败去旧清单及真实打包投影门闭合。信任边界仍是本App不可变bundle，不是作者授权；未新增资源、缓存、lease、clock或输出owner。原build/kind/可见规则逐字节不变；View仅在默认槽新增可选读取，旧枚举作为明确fallback，未双建。

## 最近门及纠偏

原ResourceView正反例保留，新增门检查：逆序清单在en_US/tr_TR重建完整namespace；独立sentinel metadata区分默认槽实际消费与显式Root仍枚举，不能用相同结果冒充快路命中；缺坏/schema/SHA/超限/非法路径/负长度/重复行回退；同bundle sidecar软链拒绝；外部assets重定向仍不共享/匹配fresh。打包门保原逐文件byte及许可证检查，并以原Index核的完整投影核清单；新增工具失败反例要求退出73、旧清单消失、没有成功生成输出。

首轮两个模块14方法中12通过、2个child SIGTRAP。原check=True采集只交付失败argv/信号，未交付child raw stderr，不能声称完整原生原因已采得。新排序夹具强制假设三个候选必有`.orderedSame`，实际此前提不可用，删除这个无效新增方法/分支；产品tie guard未改，其distinct-path分支只经静审，不冒充native覆盖。外部Root夹具给生成器传了重定向URL，改为实际目标后原default外部重定向/不共享/fresh断言一次通过；产品语义未改。采集改为check=False后立即断言exit0并附完整stdout/stderr，不放宽失败。

现役14方法证据由首轮12成功、纠偏后窄跑1及新增shell失败门1组成，非同一轮全跑全绿。首轮夹具源按原 `70705a3b…70584` SHA精确还原归档，未重跑退休反例或补造原stderr。另一次错误的新方法selector在0native阶段失败，改用实际方法名后通过，原输出保留。80个code-health/验证路由治理方法一次通过；新build-only Swift纳入原1000行门与原打包测试路由，未放宽上限。依赖、设计、防御面与测试断言门通过，不由这些数量推导兼容或性能。

## 实际构建与资源结果

全5948个Git可见输入冻结，未用诊断覆盖；沿相同Debug `-O`/wholemodule和测试bundle/Team构建420.607s通过，snapshot/live输入前后全等、deep strict签名通过。构建期间另一会话只可用不同源/缓存做短CLI正确性任务，未共享DerivedData或启动产品App/GPU；构建耗时不作性能比较。实际arm64 App `b5021b0f2c006006ec4703fd32e390a44e4bbfe914742d14b6d59828a5582fb2`，CDHash `36215769fb11bdf105d349e3ca97dd4b850d7d8e`，`com.songziqiang.MyWallpaperX.Debug.Startup`、Team `H9QWU9XN8R`。shader semantics为 `182dc218…79dcc`，toolchain仍 `a3a31085…305e`；未把新旧cache分区冒认相同。

实际App清单267540B、SHA `46984e52758be283d8bad97abaebd76d247864f8ece8bd7b72e6f57c84c094a6`。新六源探针沿原runner/timers，只有计时外新增实际清单可用性断言：

| 窗口 | 改前（ms） | 改后（ms） |
|---|---:|---:|
| 默认首次 | 154.214125 | 83.562958 |
| 默认命中 | 0.017042 | 0.017417 |
| 独立direct原枚举 | 128.777250 | 140.131209 |
| direct原Root建表 | 3.437583 | 3.426708 |

2264项完整资源/字节/查找投影及namespace SHA均与改前一致，命中仍同Root。整个bundle只新增清单；完整payload不在计时内读取。默认首次减少70.651ms是该两次同步叶的观察差异，未执行多次叶A/B；direct原方法未改，其窗口也有漂移，不能把所有差异或剩余83ms归给单一操作，更不能据此接受整App性能。

## 同输入五对产品运行

用户授权直接与「UI改进专项」协调安静窗口，本root与对方子代理均无Swift/native/App/GPU；真实process前检及99份一秒/边界观察未见识别到的冲突或错误（不证明全host或亚秒空闲）。先原stock叶，再原唯一benchmark五组AB/BA；计时结束即释放窗口。baseline为保留的实际D15最终产品bb1d，candidate为上述b502，运行包名均 `MyWallpaperX.app`。source仍是D15同一真实library/generation，40完整admittedSource逐项相等，三出版guard、作者/库树、偏好整轮不变。30份raw native逐项匹配报告，原四helper/四函数、90s/30FPS/原调度不变；strict签名、正常退出/children/defaults/HOME清理通过，无重试。

| 条件 | baseline中位（ms） | candidate中位（ms） | 配对差中位（ms / %） | baseline / candidate噪声 |
|---|---:|---:|---:|---:|
| C0 | 1617.436 | 1520.040 | −121.269 / −7.4976% | 9.4185% / 6.4667% |
| C1 | 1005.260 | 980.209 | −37.642 / −3.7725% | 6.3604% / 3.2752% |
| W0 | 232.048 | 233.289 | −5.919 / −2.4744% | 23.1163% / 63.3772% |

配对值先按同iteration的candidate−baseline求差，再取中位，不由两个独立中位相减替代。沿原最大绝对中位偏离/中位的5%门，5/6失败，三个条件也未达配对10%收益门。candidate iteration3 W0 381.141ms与配对231.076ms完整保留，差150.065ms/+64.9418%；不能删点或称性能无回归。此暖慢点原因未归因，未以当前快路观察追认D17或其他旧失败。

## 后继与产物

保留已验证的bundle枚举减工；下一门只任务比较“当前comparator已证严格递增时线性消费、逆序走原sort”的成本，尚未实施到产品。Swift排序本身可能自适应，不以最坏复杂度声称还有收益；无效即停。完整内容cache、P2媒体重复物化/旧seek与P7仍开放，历史Web及D4资源边界不随本片关闭。

原失败、协议/源码/命令、构建与真实资源投影、30App全部原点和独审保留在本机 `.artifacts/scene-evidence/runs/wallpaper-startup-scene-d18-20261025-checkpoint/`，具体映射与清理收据见包manifest/sourceAliases及任务收据。只清已终态且核验归档/无打开句柄的快照和运行壳、native缓存；一份任务DerivedData继续保留（现已是实际产品b502，不是D17诊断App），bb1d前驱、P0及历史Web前驱与同generation输入继续供后继验证。下一叶未执行任务材料保留，不混入D18已完成证据。未暂存、提交、推送或安装；goal活动。
