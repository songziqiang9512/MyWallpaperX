<!-- document-role: active-plan -->
<!-- retirementCondition: 启动冷路径的解析核函数全部 nonisolated 单实现、后台段执行并被门禁断言锁定后，若后续引入替代编排则整体归档。 -->

# Web 冷路径 descriptor 解析后台下沉

> 设计复核：2026-10-18。当前实现与验证结果分别以源码、最终运行证据为准；本设计不单独证明启动收益。

## 目标与取舍

用户点击播放后，主 actor 只收集记录/属性状态、必要的轻量入口事实和书签副作用；项目全量解析、HTML/JS/CSS 依赖扫描、缓存读写在后台执行。保持唯一 descriptor 构造核，播放不依赖完整属性面板或样本诊断。

选择解析核 nonisolated 化、播放编排 async 化；同步属性面板仍使用同一核与 memo。将所有 descriptor API 改为 async 会扩大 UI 状态机改动；另建播放解析器则会产生第二解释权威，均不采用。不增加预热容量、周期任务或 Release 诊断。

## 职责与数据流

- `SteamWorkshopService` 主 actor 快照 `webPropertyDefinitionSourceRecord`、有效属性与书签状态，拥有现有 memo 和失效钩子。
- `parseWebProjectDescriptorCore` 是共享解析核，显式消费 record、属性来源、entry/root；静态摘要、目录结构与结构风险 helpers 不回读 actor 状态。
- 主 actor 的 `assembleResolvedWebProjectDescriptor` 收尾 baseline 可见性、preset 资源绑定与 preconditions。书签解析及陈旧书签回写继续留在原 owner；没有新增书签解析实现。
- `prepareWebPlaybackContext` 返回不可变的 `context + descriptor`。产品切换只消费入口、root、属性 JSON、语言和同次 descriptor 的兼容档位，不构造完整 runtime model。

播放链按以下次序执行：

1. `setAsWallpaper` 的入口准入只检查实际/声明入口及依赖可用事实；不调用 descriptor，从而避免后台准备之前先在主线程扫描项目。
2. async 准备在后台读取/校验 execution cache；同时经共享 descriptor memo、分析缓存或解析核取得同一项目解释，主 actor 完成装配。
3. 冷路径生成有效属性 payload，保持原有 `await saveWebRuntimeCache` 完成时序；同步 UI 与后台编排共用同一解析与缓存实现。
4. 产品接纳返回值前复核 launch generation 和进程准备身份；档位只检查 descriptor 中 service worker、ES module、WASM streaming、敏感 WebGL、iframe 和截断扫描六类风险。完整面板模型额外产生的文件/目录缺失标记不参与档位选择。
5. 通过现役 ready-to-play 通知进入唯一切换事务；快照准备、媒体 ACK、可见确认、失败保留旧输出均不缩减。兼容接口 `resolvedWebPlaybackContext` 委托同一准备流程，供现有 preload/Debug 调用者使用。

## 缓存候选与失败退出

“先交付播放、后持久化”候选已撤回。真实清单的 Swift 动态 Codable 屏选中，可后移的编码加双原子写盘中位约 0.9–4.5ms，不能支撑约 200 行新增排序、代际和 metadata 重核。该屏选不是 App 收益或数学上界；原保存 owner、等待语义与失效边界保留，不新增缓存或保存队列。

缺失入口/根目录走原失败反馈；后台解析失败不发布播放。较新选择使旧请求退休，迟到完成不得清除新请求 pending 或替换当前输出。取消、预备进程释放和资源 lifetime 仍归现役请求 owner。解析和签名的现有 mtime/依赖校验边界保持，本批不宣称提供原子文件系统快照。

## 验收与停止条件

入口行为门覆盖首次与重复校验、缺失声明入口、依赖宿主 fallback、入口删除及正常错误反馈；测试不提供完整 descriptor 实现。档位门编译真实风险 owner，覆盖六类风险、非消费风险与组合，不提供完整 runtime model 实现。

真实产品入口验证冷/完整暖应用缓存、属性/书签跨进程恢复与清空、快速连续选择、失败保留和退出；以 matching request 的提交为计时边界，同安装路径、配置和输入交替比较。Release 不编入测量入口。收益未达门或出现功能回退则撤回相应候选，不以跳过资源/可见检查、增加 timeout 或减少作者内容换速度。

## 2026-10-18 验证边界

独立局部五对在优化 Debug、固定作品 1509243786、关闭可选预加载且内存 memo 为空时，直接测得真实 `setAsWallpaper` 同步主线程 CPU 中位 461.18→4.07ms，基线噪声 2.93%；仅验收未预热入口的同步减工。暖 CPU 噪声 8.19% 不认稳定收益，暖完整提交未见回退。另一次保留自然预加载的整体启动五对，冷基线噪声 34.09% 超门、暖配对改善仅 3.50%，整体启动收益为 NO-GO。同次 descriptor/context 编排只作为数据流收敛保留；局部结果不证明档位选择或普通 Release 的耗时收益。临时计时及禁预加载 hook 只在隔离验证副本，最终源码与 Release 无此改动；原属性门的九项退役日志观测失败保留，实际值、书签、host 顺序和精确进程退出另行补测。
