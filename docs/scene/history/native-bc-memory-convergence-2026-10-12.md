<!-- document-role: historical-evidence -->

# 原生BC上传的内存收敛（2026-10-12）

> **历史证据 — 非现役入口**。当前执行仍归[性能卡](../roadmap/performance-convergence-card.md)，位图发射能力归[粒子E03](../capabilities/particle-component-coverage.md#4-emitters)。本记录只封存这一成本点，不关闭其他视觉、性能或面板缺口。

通用语义：单张二维BC1/2/3、保留源通道用途、设备支持BC时，唯一`SceneCompressedTextureUploader`复用原`uploadDirect`，不在CPU展开完整RGBA mip链。原PMA归一化、多图、volume、设备不支持及坏mip失败合同保留；没有样本/路径/hash例外、新缓存或第二解码算法。

独审在提交前发现CPU图片粒子发射map只接RGBA/BGRA，native BC会使既有静态`emitterimage`失去映射。已在原Map修复：shared/managed、最多1,048,576像素的2D来源，仅为该CPU消费者复用已有BC decoder读取base level；源纹理与其余mip保持压缩。位置、alpha权重与随机采样算法不变。原BC→RGBA测试blit也改为唯一共享GPU采样fixture，不把格式选择当实际像素。

## 同条件运行结果

3662790108使用隔离副本、同尺寸单surface（窗口3024×1964）、60fps目标、静音fixture、关闭execution observations；修前与最终修后各三轮。均为Debug构建显式`-O`，保留DEBUG实验入口，独立签名App同团队且不关闭library validation。engine cache与HOME逐次新建，OS文件cache已暖；不是物理冷盘、Release或普通桌面产品入口验收。每轮warmup30s，实际测量62.49–62.51s，exit0、GPU drain、实际present及footprint计量均有效。

| 指标 | 修前3轮 | 最终修后3轮 | 结论 |
|---|---|---|---|
| Metal分配峰值（MiB） | 1950.06 / 1950.06 / 1950.06 | 1367.84 / 1367.84 / 1367.84 | 稳定减少582.22MiB，29.86% |
| 渲染App主进程kernel lifetime footprint峰值（MiB） | 2640.69 / 2575.32 / 2604.97 | 1999.22 / 1994.41 / 1989.86 | 均值减少612.50MiB，23.49%；不含子工具进程 |
| steady sampled footprint峰值（MiB） | 2315.89 / 2209.58 / 2305.89 | 1651.19 / 1906.89 / 1902.94 | 全部降低，仍有驻留波动；与Metal数字不可相加 |
| launch-return（s） | 26.877 / 27.608 / 28.962 | 27.155 / 27.114 / 27.365 | 未证明稳定启动收益 |
| GPU p95（ms） | 106.679 / 105.887 / 106.346 | 105.432 / 105.076 / 106.107 | 近似持平，不宣称GPU利用率下降 |
| completed FPS | 13.471 / 13.491 / 13.470 | 13.566 / 13.583 / 13.474 | 近似持平；最终三轮failed frame均0 |

自有三codec上传probe各三轮：实际texture allocation，BC1减少87.52%、BC2减少74.71%、BC3减少74.47%；全mip GPU样值与PMA对照保持。BC3 wall11.382/7.485/7.569→1.961/1.245/1.597ms；BC1/2首轮波动，不能外推稳定耗时收益。真实App结果不能被这些primitive数字替代。

## 正确性与证据边界

新/旧BC与batch门23项通过，mixed颜色/alpha selectors、nearest/linear、hidden RGB、padding、全mip、改名、PMA、多图、volume、坏tail均实际采样。压缩硬件与RGBA8量化容差预设nearest1/linear2个UNorm码值，未为过门扩大。真实uploader→real descriptor→原emitter compiler→Map三项全部执行，RGBA/BGRA/sRGB参照的发射位置及seed919连续1024次抽样一致；private、预算、空alpha、unsupported和animated拒绝保持。相邻粒子门120执行通过、10个既有真实样本证据/cache缺失skip；完整candidate门、最终Debug build通过。不支持BC的设备仅静态确认旧fallback保留，未实机执行。

3662790108修前/后截图保持同一已有intro/HUD画面，不代表太阳系的其他未修行为已正确。未参与修法的2134765860也由最终App实际渲染、取得present回执并drain；房间背景、灯光和时钟未见新增缺损/色偏，未声称官方全片等价或全样本兼容。HDR/history、连续桌面切换与长期缓存验收仍待后续专项。

未优化Debug探针、错误stage签名启动和native-only ablation不是最终结果；后者第三次present stream缺失完整保留但不计对照。libproc读取kernel lifetime max与50Hz sampled footprint分别保留；同一行两字段更新可略有滞后，按完整窗口最大值/计数单调性判定，不伪造峰值或用进程退出后的0证明资源回落。

证据根：`.artifacts/tmp/performance-panel-intake-20261012`，核心为`final-performance-comparison.json`、`baseline-results.json`、`after-results.json`、before/final staged identity、BC/particle/candidate日志及原样截图；最终owned/evidence manifest与独审回执绑定精确SHA。原样本只读，临时副本/HOME/cache/App与生成源码收尾删除，保留必要证据及一份复用DerivedData。

下一轮按现有入口量重复TEX解析与模型metadata读取的真实成本：后者虽按模型去重，`retainGeometry:false`仍完整校验几何，后续再读geometry；不能把延迟打印model-build当重复build，也不能改成unchecked header。面板卡的通知放大、条件重复投影及reset仲裁仍是未实施诊断，不以本批内存收益关闭。
