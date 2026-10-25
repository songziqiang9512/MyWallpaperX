<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**

# Scene 启动 D3：播放入口、粒子定义与完整模型的同源字节链

> 截止2026-10-24。实施顺序归[启动专项](../../development/wallpaper-startup-optimization-plan.md)，稳定边界归[启动合同](../architecture/scene-launch-responsiveness-contract.md)。本批结算目录消费者迁移与同launch准备，不认领按需包IO、P2b完成或正式提速。

## 实际改动与审查纠偏

14个产品文件沿原owner修改，另有14个最近测试/fixture与两个既有门映射；完整清单、实际D2-before及最终SHA见证据包`d3-owned-code-final.json`。4个入口文件中，ResourceView持有目录handle；SourceFacts只建一次loose Root，Project/Document消费它读取的自持Data，DEBUG索引也复用。原解析核、脚本/属性解释和字节witness保留，派生包名先于scene.pkg；Document按package→loose字面首个存在项选择，隐藏入口可读，选中坏内容不改选较低根。轻量记录分类及工具的Project URL适配仍保留，不为它们强建整图索引。

6个粒子/宿主文件把递归定义JSON准备移到Host后台throwing prepare，退出粒子独立目录枚举。定义图放入LaunchContext，各surface消费它建立自己的runtime/GPU/playback状态；硬错误与现有请求取消在候选发布前上抛，普通坏定义局部。另4个设备/模型文件让完整MDL/puppet以同Root的Data供原mesh、rig、animation、attachment核，保原全格式验证、GPU预算和回滚。未新增解析器、资源registry或帧owner。粒子图仍含纹理URL，不是跨launch纯产物缓存。

实际改前对照抓到dot误归一：先折叠`ignored/../entry`会跳过原文件系统要求存在的中间目录。修为probe/open保同一raw路径，规范化仅作边界检查，读payload前校验实际FD仍在captured canonical Root；补存在/缺失目录及symlink/..内外根反例。首次负资格因此多出两项差异，未删断言或把它们改列预期失败；纠正真实读取语义后才恢复恰5项目标失败的对照。

另一轮独审发现粒子原invariant折叠不能换成默认localizedLowercase，且选中的POSIX反斜杠文件名不能再当Windows分隔符重选。现从同一index生成保首到顺序的invariant投影，handle保所选原始路径，共用原raw open/FD核。其他lookup不变，未恢复第二枚举。实际本机冲突样本的目录枚举选中nested peer；记录未冒称真实文件系统会优先反斜杠文件，反向先到次序另以相同索引输入对照原Dictionary核。

## 行为、GPU与构建证据

保存的是实际D2工作源码，不以HEAD冒充前驱。同一真实SourceFacts→ModelBuilder的62项中，actual-before恰5项失败：Project/Document打开FD后换源的双caller四项及选中入口删除一项；其余57项通过。最终源码62项全过，含普通失败、脚本/属性/witness、来源恢复与完整动态namespace；17项最终依赖CPU门通过。en_US、tr_TR、az_AZ各11个真实Graph case和3个Root检查与actual-before相等，覆盖冲突次序、邻近不应命中、外部空白、反斜杠及选中坏定义不fallback。

before/current模型GPU各9项、粒子GPU各47项通过，无skip。38个独立粒子调用及模型结果，只在明确字段去掉受控临时输入根、进程生命周期UUID后差异为零；像素、数值、预算、回滚及单次运行内身份关系未改写。原始113处模型路径差异与5处粒子UUID差异、归一规则及关系检查均保留，不能据此声称raw JSON相等、任意画面或全样本一致。最终门按冻结源码摘要检查前后输入未变；14份产品源码均不超过1000行，未为缩行数另建owner。fixture缺依赖/旧marker定位失效、中间编译失败、实际before对照首次额外失败等资格记录一并保留，不并入有效通过数；旧extractor对loose五段fixture的拒绝属于D2先存边界，D3使用已验证PKG。

签名Debug/WMO构建337.731s通过，原InspectorBadgeView的NSBox弃用警告未在本批修改。构建前后Git可见源码聚合SHA均为`f614c020e9e4561d60277799f5bc8aa69d98f443abc2a26baa05aab96b738058`；候选executable为`4f3998bb180ebbe05f5b9228bda75f0f8af5a609ebf686275ecf19699b7a107f`，直接前驱为`080f17b75c8c9c443853695e8408d96896913e85da2b5df418ca5a3758e4c34c`。专用Startup bundle、2.11.0(283)、Team H9QWU9XN8R，deep/strict验签通过；不是Release或安装验收。最终产品/测试/门映射冻结后仅修改文档与文档预算，未再改产品。code-health、design、dependencies、defense最近门通过，不把模块选择预览当执行结果。

## 首轮资格与固定五组复核

沿原setAsWallpaper入口，30FPS，HOME/cache隔离，无系统缓存flush。C0为空应用缓存的新App，C1为同内容已留缓存的新App，W0为同App/同daemon PID与generation的后继请求。均以匹配的实际presented及parent finalize资格，正常退出且拥有的子进程退出；生产偏好/输入摘要与App身份检查通过。它们不替代typed drain ACK或完整像素验证。

首轮三个输入各单组AB，共18个App/24个请求：

| 首轮单组资格，ms | C0 前→后 | C1 前→后 | W0 前→后 |
|---|---:|---:|---:|
| 3750342273 重输入 | 1729.759→1616.254 | 1043.474→1075.412 | 282.419→291.485 |
| 3141421197 独立输入 | 1254.818→1351.345 | 901.279→942.966 | 131.882→123.882 |
| 自有五段MDL PKG | 886.931→851.749 | 825.370→851.666 | 89.914→89.194 |

三项C1首轮增量26–42ms全部保留。父端观测的分段显示，重输入/独立输入增量主要在accepted前，模型段也有增量；异步/嵌套事件不机械相加，不冒充CPU/GPU独占耗时，未先归因给Root、JSON或外部调度。首轮每arm只有一个原点，因此预先记录一次固定五组交替确认协议，首轮不混入新统计；未剔慢点或复测直到变绿。

固定复核共90个App/120个请求全部完成，连同首轮合计108个App/144个请求，全部资格通过。最终五组各arm中位数如下，完整原点、范围、配对差与协议在`d3-confirm-runtime-analysis.json`及各`report.json`：

| 五组中位数，ms | C0 前→后 | C1 前→后 | W0 前→后 |
|---|---:|---:|---:|
| 3750342273 重输入 | 1626.087→1606.325 | 1039.864→1037.713 | 287.797→284.101 |
| 3141421197 独立输入 | 1267.950→1267.815 | 924.405→901.434 | 131.831→123.926 |
| 自有五段MDL PKG | 846.768→847.005 | 825.620→830.458 | 89.539→89.369 |

首轮C1慢点未在固定组中持续复现，没有据此宣布根因已修或完整无回归。各中位变动在本次非目标计时预算内，但无一达到目标配对收益门。噪声定义为`max(abs(point - median))/median`，不删点：重/独立输入C0前驱噪声分别18.691%/11.987%，重输入W0候选8.372%，独立输入W0两arm约6%，模型W0两arm22.219%/34.285%；均须保留并限制声明。其余C1噪声均低于5%，结果大多持平。独立输入W0中位约−6%仍受噪声及配对门限制，不能算正式提速。

**性能卡未通过。** 本轮未测CPU/GPU尾部、峰值RSS、能耗/温控、长稳、完整画面/音频、多屏和Release；全卡失败不改写为行为失败，也不放宽既定噪声或目标门。没有为D3临时扩张观测基础设施或重跑旧音频矩阵。

## 剩余边界与产物

package backing/receipt尚未激活，extractor仍完整读包和校验缓存。TEX及source identity/cache/candidate和视频声明、sprite同Root sidecar、直接ImageIO、字体和AV媒体物化仍待迁移；receipt、原library lease/IPC及CPU/GPU/provider退出门齐备后才统一切包。inline脚本沿Document同份Data，当前仅builtin模块导入、无作者.js读取叶；LocalStorage仍属可写状态。App正常退出、presented或parent finalize不能替代typed drain ACK、长稳、多屏、完整画面/音频或Release验收。

必要证据提取到`.artifacts/scene-evidence/runs/wallpaper-startup-scene-d3-20261024`，标签到数字样本路径的映射由`batch/report.json`拥有；保实际before/最终身份、审查纠偏、GPU原始与归一结果、首轮及固定五组全部原点和失败资格。586份载荷合计11,571,325B，归档与原文件逐项SHA核验通过，默认14天/32MiB包预算，不扩大预算。精确清理127个路径（含17个执行目录），删除逻辑字节146,760,653B；停止/打开句柄检查通过。连续迭代只留`/private/tmp/mwx-startup-optimization-fbRhFY/DerivedData`一份构建缓存，当前候选与直接前驱App、必要输入/源码副本按清理收据保留；旧未解决Web长尾、v2 C1及P2a CPU-marker证据保护不变。精确删除/保留清单见`wallpaper-startup-scene-d3-20261024-closeout`包内`d3-cleanup-receipt.json`标签；其中也保存最终文档审查/门和源码冻结复核。归档字节仍在磁盘，不把逻辑删除字节数宣称为实际空间回收。工作树未暂存、未提交、未推送；主工作区保持干净，专项goal继续。
