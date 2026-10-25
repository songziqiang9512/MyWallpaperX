# Scene 启动 D17：规范化对照与两项停止裁决

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**
>
> 截止：2026-10-25。当前顺序归[启动专项](../../development/wallpaper-startup-optimization-plan.md)。本批真实对照与叶级反例改变后继选择，未改产品或永久测试；正式性能门未通过，不能认整体提速或完整P2/P3/P7验收。

## 规范化输入与执行资格

沿[D16](../../history/cross-topic/wallpaper-startup-d16-2026-10-25.md)的统一运行包名，比较实际保留D12原App `01c4a729…0256d` 与D15最终产品 `bb1d2199…9256`，两者本专项的产品源码差异仅为原两行noise范围遍历，App字节与签名身份仍不同。原唯一benchmark执行五组AB/BA、各臂连续C0/C1/W0，30 FPS/90s、不采样/不构建/不重新发布。输入复用D15同一真实library/generation，40请求全部完整admittedSource相同，三出版guard、作者/库树及source/facts均核等；生产偏好按本轮合法现状新捕获，仅核整轮不变，不恢复D15旧值。

第一次D17在内部preflight发现外部Swift frontend38743而阻断，尚未stage或调用主核，0App/0请求；其退出后一次准备检查又发现图库grid编译39138/39139，仍未启动App。两份失败保留。经用户明确授权，直接与另一会话协调构建/native窗口，其子代理也保持静态；确认真实进程及连续有限快照后，冻结新D17b命名空间，仅补识别swift-driver和已知grid App。不是重采已有原生数据，D17b后没有再试。

D17b原30份native与总报告逐项匹配；每臂实际stage均为 `MyWallpaperX.app`，原主SHA/CDHash、strict签名及正常退出、children/defaults/HOME清理资格通过。94份一秒及边界进程快照未见识别到的争用/观察错误；这不证明没有亚秒进程或系统负载。四helper及四计时/调度/统计函数字节不变。计时结束即通知另一会话释放窗口，未扩大终止其他进程权限。

## 前后结果与未过门

| 条件 | 原App中位（ms） | 最终产品中位（ms） | 配对差中位（ms / %） | 原App / 产品噪声 |
|---|---:|---:|---:|---:|
| C0 | 1487.616 | 1517.828 | +6.373 / +0.4309% | 5.3959% / 2.1322% |
| C1 | 930.682 | 930.548 | −0.711 / −0.0764% | 3.1088% / 2.8282% |
| W0 | 243.148 | 244.265 | +3.392 / +1.2599% | 10.7293% / 62.7728% |

差按同iteration的candidate−baseline计算，独立中位之差不取代配对值。沿原性能卡用最大绝对中位偏离/中位计算噪声；原App C0和两臂W0共3/6超5%门，三条件均无10%收益。产品iteration4暖点397.597ms完整保留，其配对265.155ms、差132.442ms；不能删点或宣称性能无回归。

新daemon首请求的entry→accepted观测在两臂均约503–539ms，旧[D15](scene-startup-d15-2026-10-25.md)额外约0.5s的臂间差异在新条件未复现。只限本次规范化、协调后的观察，不能反推旧名称、OS、安全或产品因果；不把旧D15或污染D16重标为有效性能对照。397.597ms慢点accepted仅1.910ms，resources→surfaces等组合窗扩大，不能将它归给单一CPU/IO/GPU叶。

## 真实 variant key/load：不增内存缓存

现有小夹具不是375实际模板的生产者：wire门替身Sampler，persistent probe手造Record，Finalizer门手造graph/contract且disable-generic。为避免测错对象，将全部5946个Git可见输入冻结到任务快照，只在原Preparation的keyDigest/load边界和原CompileProfile中插入标记观察；删标记可逐字节还原。原锁/reset/worker join后一次额外汇总，不改调用、算法、缓存或current eligibility，不逐key建表。工作树保持原产品。

诊断Debug沿原 `-O`/wholemodule、同测试bundle/Team构建，414.144s通过，深度strict签名及快照/实时输入前后核等。诊断exe `4135a6b3…2631`；不是D15产品。生成器包含Compilation源，因此诊断shader semantics为 `ccaa2fbb…419f7`，与原产品 `02bfede9…51923`自然不同，toolchain相同；首次准备中误加的同semantics限制在0App阶段失败后已撤，原失败及窄修正保留，不改生成器或追认两个cache分区相同。

另一次协调短窗口里只执行原单臂3App/4请求，真实来源/签名/退出及14份有界进程观察通过；不作App A/B。每请求恰一条原profile与lookup行，按原串行ordinal关联，无并发catalog。结果为并行worker墙钟区间之和，不能视为catalog独占时长、CPU、可节省量或最终收益。

| 请求 | key调用 / load命中 / miss | key总窗（ms） | load总窗（ms） | 原rest总窗（ms） |
|---|---|---:|---:|---:|
| C0 | 18 / 0 / 18 | 1.161875 | 1.117625 | 40.645208 |
| C1 | 18 / 18 / 0 | 1.196459 | 4.202958 | 36.951333 |
| W0首项 | 18 / 18 / 0 | 1.099250 | 4.331708 | 36.757708 |
| W0暖项 | 18 / 18 / 0 | 0.846042 | 3.824083 | 35.305708 |

所有keyAvailable；每次loadCalls=hits+misses。退出后、HOME清理前只枚举实际缓存目录的元数据：均18个JSON、110023B；不读回payload或修改cache。hit仅代表load返回Record，不表示当前eligibility或最终编译成功。原rest仍包含未剖分成本及观察开销，以上区间不可与之重复相加。

在此实际输入上，暖load合计约3.8–4.3ms，不足以支撑新增global memory tier，停止此方向。完整PreparedContent缓存仍暂缓。新对照候选五组的preparingModel→preparingPrograms观察窗中位为C1 188.427ms、同daemon暖40.352ms（保留70.167ms慢点），仅支持下一门去量原默认stock Root/index的首次独占成本；先用原owner最小真实叶门验证，再决定是否采用专项已列的构建期manifest，不能直接把组合差称stock成本。

## 已取得视频候选的 discard 反例

旧D7名为discard-after的失败未区分首次await和discard后await；D11保留的实捕是seek6/first-target pending，old generation1未动，没有证据表明新payload已被discard丢失。D6曾有类似首次等待失败，后续独立通过也不构成因果修复。

本批保原Source、14个Swift源的原编译闭包和原六方法/seek逻辑，仅任务夹具增加51行独立分支：先取得真实ordinary advancing candidate并冻结产生它的timing，再相邻调用discard→同timing prepare，中间没有新seek、回调、时钟读取、RunLoop、observer或GPU读回。沿原2s acquire、12s child、原FFmpeg输入/像素/尺寸阈值，不重跑六方法。

一次执行通过，原编译11.234s、单child0.612s（不是性能对比）。18项事实均真：首候选/重试generation2、同一实际texture/requestedItemTime0.114及frameIndex10；commit前保持旧texture/generation1，唯一commit后才到2。真实红像素[254,0,0]、320×180及黑白/输入红蓝oracle均通过。16个冻结/实时输入前后不变，原逐命令stdout/stderr含二进制RGB均保留。

按预定STOP，不修改视频Source、seed、clock或状态机；不为数量增加永久门。此结果限定已取得ordinary payload的拒绝/重试合同，D7/D11组合seek首次等待旧失败仍保留，不能称已修复或全部视频兼容。任务反例随证据保留，后继触达该owner可直接复用。

## 产物与 Git

必要协议、原被拦记录、30App全部慢点、诊断快照身份/两源、原始profile/native、AV源/输入/输出和独审提取到 `.artifacts/scene-evidence/runs/wallpaper-startup-scene-d17-20261025-checkpoint/`。保护原因为性能噪声/暖慢点及旧seek原因仍未解，不能误认整体通过；载荷与已清来源映射见manifest/sourceAliases。构建快照的全部未提交输入另保字节，可由ae0ac798c加这些输入及两标记覆盖重建，不打包整个App/媒体/DerivedData。

归档核验且无打开句柄后清本轮结束的快照、AV编译/输入副本及运行目录。继续保单一DerivedData（现为诊断构建，不能当原产品）；实际最终产品在任务 `d17-final-product.app`、原App及同generation发布输入仍为后继验证使用。下一stock叶门的未执行任务材料保留，清理精确结果归 `d17-cleanup-receipt.json`。本批只有文档状态变更，产品/永久测试字节不变，未暂存、提交、推送或安装；goal活动。
