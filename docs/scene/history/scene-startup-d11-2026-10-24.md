# D11：启动配对摘要与 seek 失败相位

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**
>
> 截止：2026-10-24。顺序与停止条件归[启动专项](../../development/wallpaper-startup-optimization-plan.md)，验收归[性能卡](../roadmap/performance-convergence-card.md)。本批没有产品实现变化，不重标 D10。

## 改动与前后边界

本批仅改原 `SceneVideoRepeatedCommandsHarness.swift` 和原 benchmark／测试两个 Python 文件。产品 4349 项源码/工程输入逐 SHA 保持 D10 build-v2；沿用专用 Startup 身份的签名 Debug App，exe 为 `3b96b37992ddc8b3c3a4524fccf2efddb4dcb4b3a41b22d78e1d14bf150614c5`。脚本/fixture 变化未触发新 App 构建，不声称新的产品提速。

原 seek fixture 的两次 await 增加 `first-target` / `after-discard` 相位；只在原失败发生后、stop 前观察状态。成功热循环不加反射或额外 prepare/读帧，原 Python 六方法、2秒 await、12秒 child、像素/texture/generation 断言字节保持。去除新增观测及参数后的原 fixture 行为投影逐字节核等。当前 fixture 556行，SHA `beabfe684e3622988e15abba321feee7a8e42daf5e27e2bf620bc155686c7370`。

性能卡原本要求配对降幅中位数；旧工具只输出各臂独立汇总。原 `wallpaper_startup_benchmark.py` 新增一个纯 `summarize_paired`，沿原 `summarize` 取得真实条件值，按 iteration/condition/arm 配对；`--baseline-app` 的报告附 `pairedSummary`，单臂形状及原 `summary/runs` 保留。完整两臂各条件须唯一、成功且有限，缺失、重复、失败或歧义时不输出部分比较；零基线保全部毫秒差，条件百分比中位显式 null。负差为 candidate 更快，百分比是逐对比例的中位，不能用两个汇总中位数之比替代。

新摘要不自动授予性能验收。main只附报告字段，其余原17函数逐字节保持，含取值、计时、隔离、执行和退出；stage provider 未改。原5%噪声、10%目标、两倍噪声与非目标门不放宽。原 Python 模块17方法通过，含保留12方法与新增5方法；实际5依赖前后SHA一致，性质仅纯Python/模拟调度。最终 core SHA `ef2eb0fe6b64a8f0b3fa5f951f7277b4ea6080a17e8806130cfbe18b3235672b`，594行。

## 原 seek 六门只执行一次

本次六方法用时100.516秒，五方法通过，playing-seek 方法的 `seek6` 子例失败；其余该方法子例及 discard-after 没有失败。保留原失败，不重跑直到绿。

新增事实为 `first-target`：215次尝试、约2.006秒，未取得首候选；原 published generation1/texture 保持，pending frame/cache为空。Source positioning 是同一当前 item、target6的 pending；事后 playerTime6、rate0，`hasBufferAtTargetAfterFailure=true`。stop 后 player item 为空。这把本次失败缩到首次目标的 positioning 接受之前，没有证明 AV completion 是否进入，也没有证明原截止前已可取 buffer，更未证明整个期间只有一次 operation。不能据此修改 seed、clock、缓存或绕过完成确认。

采集包装器在六门全部结束后，因 ffmpeg 原始RGB输出是 bytes，最终 JSON 序列化失败。原 unittest.log、原生失败完整JSON和生成carrier仍在；逐 command 的 argv、成功stdout及输入双SHA只在已退出进程内存，未持久化。恢复报告明确该限制，不补造命令收据，也不因此重跑。独立前后全产品输入与 fixture/Python 冻结SHA一致只能证明其范围。后继另存按命令落盘、bytes可编码的任务包装器，未拿它重执行本批。

`d11-seek-suite-recovered.json`、`d11-seek-native-failure.json`、`d11-seek-causal-decision.json` 保原数与裁决。此次 first-target 失败和本轮 discard-after 通过都不能关闭既有 D7 discard-after 未解证据。

## 同 App、同来源 A/A

只执行一次预定五组AB/BA、30 App／40请求，全部30 FPS；正式版按用户既有授权正常退出，未与 seek/编译/App 测试并行。沿保留的实际 D8 publisher binary 一次发布完整作者输入：18文件、59,243,475B，原 digest `54128d5ebeb06c9f9a58158105d61a58e5402d7f6adda8a91904ff6e714e49bb`；这不是手写 metadata/ready marker，也不冒充当前WT重新编译的publisher。两标签使用完全相同 App 路径/hash、来源JSON、库、generation与可信ref，仅原staging路径和各轮独立HOME不同。

generation `2cb0db57-74f6-4010-865d-ad7e68a9b4b5`，receipt7615B；实际完整认证、metadata/marker/ref三guard、每请求 admittedSource、深严格签名、标准偏好及正常退出全部有资格。测试标准域清理，无残留子进程；原runner自动删除本批 staged App/HOME。C0只指新HOME，不是OS冷缓存；输入预读及系统/路径/WebKit/GPU状态未分离。

| 条件 | A标签中位ms | B标签中位ms | 分臂中位数之差ms | 同轮配对差中位ms／% | A／B最大偏差噪声 |
|---|---:|---:|---:|---:|---:|
| C0 | 1462.017 | 1465.901 | +3.884 | -37.596／-2.501% | 29.814%／4.086% |
| C1 | 885.233 | 899.459 | +14.226 | +14.281／+1.613% | 2.154%／18.851% |
| W0 | 247.847 | 233.135 | -14.712 | +1.835／+0.703% | 7.219%／20.623% |

相同代码下，W0的分臂中位差与配对中位差方向不同；五个真实配对毫秒差为 `[-11.937,-24.676,3.180,33.368,1.835]`，三慢两快。四个条件噪声超过原5%门。它说明本次环境／原方法的合并变异仍大，既不是改善，也没有证明配对能消除噪声、原因已定位或已有正式无回退结论。小样本不能证明总体分布、尾部或统计显著性，不增样本追绿。

原 `d11-aa-five/report.json` SHA `2bf2781417a031f87eccb58e442ed7ce1c1d82dfe38c4b33f4f949f2cf35db8a`、实际计时core `fddbb01c3f91311bf0615f148d9de4d862f5c38f1a262b13d88cea84f0b77299` 原样保留。新core只离线解释该批实际iteration，结果与独立算术核等，另存 `d11-aa-canonical-paired-summary.json`；没有将原计时重标成新工具运行或改写 D10。

## 后继边界与材料

下一次 seek 因果观察只允许一个原 seek6 child，在任务冻结源副本记录同 operation 的发起、AV completion入口、原 main block入口及guard接受/拒绝；原seek/dispatch/guard语义、2秒/12秒及结果期待保留。只失败后读取有界标记，不额外pump、prepare或修状态；未复现或无新增因果事实即停止，不能把绿点称修复。

P5只读评估确认原空daemon已经覆盖暖请求的AppKit/IPC hello。首个可实施切片是原两槽内退休daemon完整reset/drain、旧lease终态后重绑新请求并新建view；是否超出现预备机制获得净收益仍未实测。P5b保留view缺公开可证的旧文档清场及现bridge执行身份，当前停止；P5a不能冲销原Web C1债。D4资源、原seek、峰值、多屏/Release及完整P2/P7继续开放。

本批必要原点、源版本、日志、失败和资格收据按既有规则提取到 `.artifacts/scene-evidence/runs/wallpaper-startup-scene-d11-20261024-checkpoint/`。临时库/副本在核验必要结果后精确清理；单份连续构建缓存仍为 `/private/tmp/mwx-startup-optimization-fbRhFY/DerivedData`。实际清理与归档核验以包内收据为准；跨批唯一失败保留。未暂存、未提交、未推送，goal仍进行中。
