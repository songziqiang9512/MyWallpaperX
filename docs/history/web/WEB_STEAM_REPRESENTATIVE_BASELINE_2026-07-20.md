# Web Steam 代表样本基线（2026-07-20）

> **历史证据 — 非现役入口**
>
> 本文仅保存 2026-07-20 的 Steam CDN 代表样本基线；其中样本、网络结果、App 身份、命令、得分和 PASS 均不得作为当前兼容性结论。
>
> 现役结论只查 [Web 现役状态](../../web/current-state.md)；全部历史材料见[历史索引](../README.md)。

> 状态：历史运行基线，不代表当前 HEAD。以下 App 身份、样本数量、网络结果和 PASS 只属于 2026-07-20 批次；当前证据状态查 [Web 现役状态](../../web/current-state.md)。

## 1. 目的与当时结论

这组基线直接来自 Steam Workshop CDN，用于补充作者公开源码 5 项门，重点检查响应式 Canvas、手工三视口 WebGL 和真实外部 API 请求。它不替代 34 项完整基线，也不把普通联网成功误写成网络断开恢复已经闭环。

2026-07-20 使用本轮最终 Debug App 在隔离 Workshop 根运行，最终结果为：

- 3/3 可运行，3 个 A；
- 平均得分 98.0，平均 evidence coverage 90.3%；
- 每项均有 `host.ready`、`navigation.finish`、DOM、交互、视觉和动画证据；
- 三张人工抽查快照均非空且内容符合项目预期；
- `3764966764` 显示实时价格、纪元、质押量和市值，本机当前网络/代理下 CoinGecko 请求成功。

最终报告与样本副本当时分别保存在 Git 忽略的 `web-steam-final-20260720/results` 和 `web-steam-representative-samples-20260720`；两份本机产物现已清理。

## 2. 来源与固定快照

样本通过 SteamCMD 复用本机已有 Steam 登录缓存下载。SteamCMD 先在隔离运行时副本内自更新，实际 Workshop 内容由 Steam 缓存保存；测试时再复制到批次专用的隔离 `Web/<id>` 目录，不直接运行用户的 MyWallpaperX Workshop 目录。该历史批次的本机副本已清理。

| Workshop ID | 样本 | CDN 大小 | Workshop 更新时间 | 选择原因 |
| --- | --- | ---: | --- | --- |
| [`3733483918`](https://steamcommunity.com/sharedfiles/filedetails/?id=3733483918) | Mindscape Minimalist - Customizable and Multimonitor | 779,738 B | `2026-05-30T09:09:43Z` | 单文件 Canvas、8 项属性、`devicePixelRatio` 和视口 resize |
| [`3765959388`](https://steamcommunity.com/sharedfiles/filedetails/?id=3765959388) | Out There | 5,217,464 B | `2026-07-18T20:25:22Z` | 70 多项属性、ES module、WebGL、三视口/三相机布局、FPS 控制 |
| [`3764966764`](https://steamcommunity.com/sharedfiles/filedetails/?id=3764966764) | ADA Cardano by SzaboBeatz | 133,550 B | `2026-07-14T23:44:47Z` | Canvas 动画和 `fetch` 到 `api.coingecko.com` 的真实实时数据 |

匿名 SteamCMD 对三个 ID 都返回 `No Connection`；复用本机现有登录缓存后全部下载成功。复现时若没有已授权且拥有 Wallpaper Engine 的 Steam 会话，应由操作者登录，不能在脚本、文档或仓库中保存账号、密码或 Steam Guard 信息。

## 3. 能力门

执行清单由 [`script/web_wallpaper_steam_representative_sample_matrix.json`](../../../script/web_wallpaper_steam_representative_sample_matrix.json) 定义：

| ID | 主要能力组合 | 单项门 |
| --- | --- | --- |
| `3733483918` | Canvas、属性、DPR、响应式布局、动画 | A，coverage >= 90% |
| `3765959388` | WebGL、属性密集、三视口布局、loopback origin、FPS、动画 | A，coverage >= 90% |
| `3764966764` | Canvas、外部 fetch、实时数据、响应式布局、动画 | A，coverage >= 90% |

批次门为平均分不低于 95、平均 coverage 不低于 90%，并禁止启动、宿主、导航、资源、属性、交互、视觉、性能和动画短板。

## 4. 证据边界

- `3733483918` 的标题包含 Multimonitor，但源码只读取 DPR 和当前视口；它证明响应式布局，不证明跨物理显示器一致性。
- `3765959388` 在单个页面中构造三视口/三相机，屏幕几何由属性提供；本轮单屏截图不能替代真实双屏或三屏 scale factor、热插拔和分辨率变化测试。
- `3764966764` 证明当前联网成功态。它没有可观测的失败/恢复状态，也没有自动切换系统代理，因此不能关闭一般网络断开恢复待办。
- 三个样本都没有 Shadow DOM，也没有在 Wallpaper Engine 分支实际注册 Service Worker。两者都属于 WebKit/浏览器能力边界，后续应使用确定性 fixture 验证 DOM 证据、属性注入和输入穿透，不应随机下载大量壁纸碰运气。

## 5. 复现

```bash
python3 script/web_wallpaper_benchmark.py \
  --app <debug-app>/Contents/MacOS/MyWallpaperX \
  --workshop-root <steam-sample-root>/Web \
  --runtime-workshop-root <steam-sample-root> \
  --runtime-home <temporary-home> \
  --matrix script/web_wallpaper_steam_representative_sample_matrix.json \
  --duration 20 \
  --screenshot \
  --kill-existing \
  --output-dir <report-directory>
```

`--workshop-root` 必须指向包含 ID 目录的 `Web` 子目录，`--runtime-workshop-root` 必须指向它的父目录。两者传成同一路径会让 App 查找 `Web/Web/<id>`，报告将正确显示样本未找到。
