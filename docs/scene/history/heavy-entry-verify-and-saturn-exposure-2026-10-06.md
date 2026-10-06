<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。现役顺序见[断点队列](../roadmap/scene-open-breakpoint-queue.md)太阳系条目；首断点归因见[水星诊断](mercury-closeup-brightness-diagnosis-2026-10-06.md)。

# 重型样本普通入口复验与土星稳态过曝（2026-10-06）

起点 `dead0a10`（接手后第二批）。用户指正：首帧截图取于过场动画内，不能作画面判定；须待加载完成。本批按普通产品入口复验重型样本启动，并按用户实机观察（土星"严重过曝"）取稳态画面量化。

## 普通入口启动复验（当前 HEAD）

签名 Debug App（dylib `43db5557ba60d83a21cfb6a12f61d4482ed656493e9cd46a4eaaf382b05754a4`，即 `dead0a10` 源码），经 `--mwx-debug-scene-daemon-client --mwx-debug-scene-daemon-stable --mwx-debug-scene-product-entry` 走 App→coordinator→client→daemon 完整链，隔离 HOME/defaults/Workshop 副本：

| 样本 | launched | 首帧 graph | 结束 | 备注 |
|---|---|---|---|---|
| 三体 `3509243656` | 约14.5秒 | frame 0 succeeded/gpu completed | 65s exit0、session 干净退出 | 与隔夜批（`1478e113`，约18秒首帧）一致 |
| 土星 `3589454154` | 约15.1秒 | frame 0 正常 | 90s exit0、干净退出 | 首次经普通入口验证 |

当前 HEAD **无可复现的启动失败**。隔夜批（rf16 后继）已修静态 MDL 逐值读取热点；"不能启动"按存量已修处理，**关闭需用户实机复测确认**（用户原始失败可能在旧构建或其本机配置）。完整模拟画面正确性不在本表内。

## 土星稳态过曝（用户实机观察 + 隔离量化）

用户在实机桌面看到土星"严重过曝"。隔离回放（同 App，周期截图 10s×150s）确认：过场亮峰（t≈10s 全图近白 33.4%）消退后，稳态全图近白 17.2–17.5%。独立子代理对 t≈140s 稳态帧实测：**土星球体盘面约 89% 面积为精确 (1,1,1) 顶格白**（中心扫描线 >1000px 无波动 1.0 平台），云带/临边纹理全部不可辨；**光环不过曝**（峰值 0.2–0.45、层次与卡西尼缝可辨，偏冷灰）；背景星空正常。

作者数据：`general.hdr=true`、bloom=true（bloomstrength 1.2、bloomhdrstrength 0.62、bloomhdrthreshold 0.5）、ambient/skylight 全黑；光源两个——点光 `lpoint` intensity **6.0**（radius 100）+ 方向光 `ldirectional` intensity **5.0**（radius 200），白色。受光面 ≈ albedo×(5+6×diffuse)，与[水星诊断](mercury-closeup-brightness-diagnosis-2026-10-06.md)同一首断点家族（显示域相乘→超白→终端裁剪）；光环未受静态模型光照故幸存，反向佐证归因。修复同样等待官方模型点光应用域裁决（探针被 VM PIN 登录阻塞，见交接与队列登记）。

## 证据与保留

包 `/private/tmp/mwx-heavy-verify-20261006/heavy-verify-and-saturn-exposure-20261006.zip`（31,758,330 bytes，SHA `14fe26b35a53d39aa2a20ef7363674cf206c0fad61e3b12e8914bdd9da514d04`）：两次产品入口完整日志、土星 t≈10s/t≈140s 原帧 PNG、逐文件 manifest（含两样本 pkg SHA）。土星稳态运行的 14 帧周期序列与三体/土星首帧 daemon 截图保留在 `/private/tmp/mwx-solar-layout-20261006/saturn-steady` 与 `/private/tmp/mwx-heavy-verify-20261006` 至清理。真实创意工坊只读未改。
