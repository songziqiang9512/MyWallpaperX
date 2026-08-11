# Web 外部代表样本基线（2026-07-20）

> 状态：历史运行基线，不代表当前 HEAD。以下 App 身份、样本数量、得分和 PASS 只属于 2026-07-20 批次；当前证据状态查 [Web 现役状态](../current-state.md)。

## 1. 目的与结论

这组基线用于补充本机已有 10 项代表矩阵和 34 项完整基线，重点覆盖属性密集、WebGL2、WASM、Worker、音频频谱、大体积生成脚本和持续动画的组合场景；其中 `1396475780` 还包含一个浏览器独立运行分支的 Service Worker helper。

2026-07-20 使用本轮最终 Debug App 在隔离 Workshop 根重跑，结果为：

- 5/5 可运行，5 个 A；
- 平均得分 98.8，平均 evidence coverage 94.3%；
- `launch`、`host_runtime`、`navigation`、`resource_mapping`、`properties`、`media_audio`、`interaction`、`visual_output`、`animation` 均无短板；
- 外部矩阵门禁通过。

这说明当时运行时通过了 5 个新增高差异样本，不表示已经覆盖所有 Wallpaper Engine Web 壁纸。外部样本不并入默认 10 项矩阵或 34 项本机基线，因为第三方构建产物没有提交到仓库，缺少 fixture 时不应让默认门禁产生假失败。

## 2. 样本来源

SteamCMD 匿名下载和隔离配置尝试没有取得这些新条目。测试包来自样本 `project.json` 指向或作者公开的源码仓库；2026-07-20 通过 `git ls-remote` 复核下列 revision 仍为各仓库 HEAD，5 个 Workshop 页面均返回 HTTP 200。

| Workshop ID | 样本 | 作者源码 | 测试 revision | 准备方式 |
| --- | --- | --- | --- | --- |
| [`1748506393`](https://steamcommunity.com/sharedfiles/filedetails/?id=1748506393) | Colorful Fluid Animation [Audio Responsive] | [Delivator/WebGL-Fluid-Simulation](https://github.com/Delivator/WebGL-Fluid-Simulation) | `3273172af182fe51664faad66a09f7af5e5310e3` | 直接使用仓库 Web 产物和样本 metadata |
| [`1396475780`](https://steamcommunity.com/sharedfiles/filedetails/?id=1396475780) | AudiOrbits 2.4 | [hexxone/audiorbits](https://github.com/hexxone/audiorbits) | `802de0433f251c9c14abbb4b7588e451cb39369f` | 递归初始化 submodule，安装锁定依赖，以作者 production 配置构建 `dist/production` |
| [`2014502586`](https://steamcommunity.com/sharedfiles/filedetails/?id=2014502586) | ReactiveInk (Rorschach) | [hexxone/ReactiveInk](https://github.com/hexxone/ReactiveInk) | `1aa10d177980494710d8c2c4df2b0ac0737aeefe` | 递归初始化 submodule；测试时 submodule revision 为 `39f914a9115a7dce386a1486caef250a4c4acd40` |
| [`2119347960`](https://steamcommunity.com/sharedfiles/filedetails/?id=2119347960) | Living Worlds - Animated Web Wallpaper | [jmdajm7/living-worlds](https://github.com/jmdajm7/living-worlds) | `8e5be5ac7e1de1ac1e63f373bfa892908e717ede` | 直接使用仓库 Web 产物和样本 metadata |
| [`2553306714`](https://steamcommunity.com/sharedfiles/filedetails/?id=2553306714) | Vanta | [UserR00T/WE-Vanta](https://github.com/UserR00T/WE-Vanta) | `9ae13521b416214ac2fc23bc7dc14488f484a70a` | 直接使用仓库 Web 产物和样本 metadata |

AudiOrbits 的作者 production webpack 配置要求本地 HTTPS 证书，准备测试包时使用了临时 localhost 证书。该证书只用于构建，没有进入仓库。作者仓库中未提供的 BPM ONNX 模型没有伪造或补空文件。

## 3. 能力覆盖与门禁

执行清单由 [`script/web_wallpaper_external_sample_matrix.json`](../../../script/web_wallpaper_external_sample_matrix.json) 定义：

| ID | 主要能力组合 | 单项门 |
| --- | --- | --- |
| `1748506393` | WebGL2、35 项属性、音频频谱、指针、持续流体动画 | A，coverage >= 95% |
| `1396475780` | 174 项属性、WASM、Worker、WebGL、音频频谱、持续粒子动画；另含独立浏览器 Service Worker helper | A，coverage >= 95% |
| `2014502586` | WebGL 后处理、Worker、音频频谱、持续墨迹动画 | A，coverage >= 95% |
| `2119347960` | Canvas、约 33 MB 生成脚本、general properties、FPS、调色板循环动画 | A，coverage >= 90% |
| `2553306714` | 74 项属性、WebGL、指针、general properties、持续动画 | A，coverage >= 90% |

批次门为平均分不低于 95、平均 coverage 不低于 92%，并禁止关键运行、资源、属性、音频、交互、视觉和动画短板。AudiOrbits 额外注入 `seizure_warning=false` 和 `icue_mode=0`，只为越过作者默认遮罩并验收真实粒子画面，不修改样本脚本。

## 4. 最终结果

本轮最终报告目录：`.codex/web-external-final-20260720/results/`。它是被 Git 忽略的本机证据，保留到分支合并，不属于版本控制资产。

| ID | 得分/等级 | Coverage | 视觉快照 | 结果 |
| --- | ---: | ---: | ---: | --- |
| `1748506393` | 100 / A | 95.5% | 6 | 音频监听、128-bin 分发、频谱变化、指针和三源动态证据通过 |
| `1396475780` | 100 / A | 95.5% | 6 | WASM/Worker、174 项属性、音频和动态证据通过；静态分析识别大脚本中的 `navigator.serviceWorker.register`，但 Wallpaper Engine 分支主动 Standby，运行时注册数为 0 |
| `2014502586` | 100 / A | 95.5% | 6 | WebView 快照偶发黑屏时，Canvas 和 ScreenCaptureKit 窗口合成证据确认画面与运动 |
| `2119347960` | 96 / A | 90.3% | 6 | Service Worker 补扫去重并限制为单文件 1 MiB；进程口径 `host.ready` 为 6.5 秒，仍记 `performance` 提醒；交互和动画证据通过 |
| `2553306714` | 98 / A | 94.8% | 6 | 属性、指针和动态通过；初始化前的 deferred side effect 被重放且未形成短板 |

视觉门使用 WebView、页面 Canvas 和当前进程独立窗口三种来源。运动证据只比较同一来源的非空前后帧，避免 WebGL drawing buffer 被清空时把“变黑”误判为动画。

## 5. 音频证据边界

基准命令在 Debug 专用参数下生成确定性的 64+64 测试频谱，再走正式 JS 分发链输出 Wallpaper Engine 约定的 128 项布局：前 64 项为左声道，后 64 项为右声道。音频样本必须同时出现：

1. `audio.listener.registered`；
2. `audio.spectrum.dispatched`，且 `bins=128`、`stereoDelta=0`；
3. `audio.spectrum.changed`，证明不是重复发送静态数组。

这个 fixture 证明监听注册、64+64 布局、JS 桥接和样本消费链路，不单独证明系统音频采集相关性。生产链的 signed stereo FFT、受控系统音源和按需采集生命周期证据见 [Web 与 Scene 当前状况评估](../../reviews/web-scene-current-state-roadmap-2026-07-19.md)；设备切换、真正系统静音和睡眠恢复仍需单独验收，不能用本基线替代。

## 6. Service Worker 证据边界

本轮修复了大型压缩脚本只扫描首尾窗口导致的漏检：`1396475780` 的分析缓存现在记录 `usesServiceWorkerRegistration=true`，缓存版本为 14。补扫使用 64 KiB 分块匹配、单文件 1 MiB 上限，并复用描述符摘要，既覆盖其 606 KiB 控制脚本中段信号，也避免 `2119347960` 的几十个生成脚本重复拖慢启动。实际 Debug 运行的 DOM 证据为 `serviceWorkerSupported=true`、`serviceWorkerRegistrationCount=0`；作者代码在检测到 Wallpaper Engine 宿主桥接后进入 Standby，Service Worker 注册只属于浏览器独立运行分支。因此当前结论是“静态识别正确、loopback 运行正确”，不是“宿主已通过 Service Worker 注册行为门”。后续要关闭这一项，应加入确定性 Web fixture 或找到在 Wallpaper Engine 分支确实执行注册的样本。

## 7. 复现

第三方测试包应准备到隔离目录 `<external-root>/Web/<id>`，不得直接使用或修改 `~/Movies/MyWallpaperX/创意工坊`。运行命令：

```bash
python3 script/web_wallpaper_benchmark.py \
  --app <debug-app>/Contents/MacOS/MyWallpaperX \
  --workshop-root <external-root>/Web \
  --runtime-workshop-root <external-root> \
  --runtime-home <temporary-home> \
  --matrix script/web_wallpaper_external_sample_matrix.json \
  --duration 18 \
  --screenshot \
  --kill-existing \
  --output-dir <report-directory>
```

验收时应检查 `report.md` 的 Matrix Gate 为 PASS，并抽查每个样本的 `after-interaction-window.png` 或 `after-interaction-canvas.png`。只看 `host.ready`、总分或桌面全屏截图不构成视觉闭环。
