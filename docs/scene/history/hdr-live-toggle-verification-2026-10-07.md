<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。现役合同与裁决见 [D2 设计](../roadmap/batch2/hdr-tonemap-edr-design.md)第 39-57 行（SDR 纠正、阶段 C、HDR Bloom 参数）；单元 GPU 合同见 `test_scene_bloom_post_process`。

# Scene HDR 显示开关运行中热切验证（H1 收口切片，2026-10-07）

起点 `49672888`。承接 [a11e5b6b 复验](../../scene/roadmap/scene-open-breakpoint-queue.md)（开关 A/B、真实域偏好读取、设置→视图链代码核验），本批以固定样本（3662790108 太阳系，隔离 HOME+副本、当前源码重签名 Debug App）完成其遗留的最大缺口：**运行中热切的真实运行验证**。产品零改动。

## 运行证据（run2，单次连续运行）

偏好经真实域 `defaults write com.songziqiang.MyWallpaperX sceneHDRDisplayEnabled` + `DistributedNotificationCenter` 即时投递（复刻设置 UI 的 setEnabled 路径），就绪门控在 `phase=ready` 后切换：

1. **OFF 基线**：surface 创建时唯一显示行 `requested=false enabled=false headroom=1.0000 potential=1.0000 colorspace=kCGColorSpaceExtendedLinearSRGB format=115`（rgba16Float）。
2. **热切 ON**（t≈03:26:26）：`requested=true enabled=true headroom=1.2000 potential=16.0000`，随后 ~1.6s 内 23 次每帧 headroom 更新随内容爬升 1.39→9.36（XDR 本屏 current 标量逐帧生效，potential 恒 16）。
3. **热切 OFF**（t≈03:26:42）：`requested=false enabled=false headroom=1.0000`，**colorspace 与 format 与 ON 期逐字符相同**——同 surface 生命周期颜色空间固定、关闭后同会话回 SDR（D2 §45 合同）。
4. **播放连续性**：两窗口 PERF 行 `rendered=attempts busy=0 dropped=0`（03:26:19→44 五个采样点 35→232 单调递增），零错误（warmup `failed=0`、light completion `error=none`、`failedInvocations=0`），无 surface teardown。
5. **快照相位**（6s 周期 PNG，仅验"有效显示输出"不判物理 EDR）：OFF 回落后的 32 张全部有内容（中心 ROI 均值 21-41、max 255）；ON 相首张黑、第 2 张起有内容——黑帧落在场景动画尚暗的时段，非呈现缺失（同窗口 PERF 帧连续）。

观察到的无害次序现象：首次 `refreshDisplayOutput` 读到 `potential=1.0`（window 尚未附屏），附屏路径自愈（a11e5b6b 的 ON 运行从 1.2 起爬升即证明）；登记备查，不作缺陷。

退出说明：本 run 以编排 SIGTERM 兜底结束（`--mwx-debug-scene-duration` 未在该窗口触发自然退出），drain/gpuDrained 证据不属本门且与既有批次一致复用。

## 已有覆盖回顾（不重复执行）

- 单元 GPU：`test_scene_bloom_post_process` 的 EDR ColorSync 传递函数 oracle（headroom {1,1.2,4,16,0,nan,inf}×暗部/中灰/白点/超白）、超白 Bloom 光晕保持到显示端才裁剪、源/alpha 保持、编码器故障注入+恢复——当前 HEAD 全绿（本日 33 focused 模块套件）。
- 失败保旧帧：线性映射失败→`scene-linear-display-export-unavailable` 拒绝提交保留旧帧的实现语义由上述故障注入门覆盖（App 级自然失败未注入）。

## 边界与 not-run（非本批关闭）

- **暂停重绘**：生产暂停经 daemon IPC（stdin Pipe 为客户端私有，外部不可注入）或播放策略设置（无既有 debug live-settings 通道）；不为验证新建控制通道。待 debug 控制入口或用户实机。
- **移屏/多屏/SDR 设备回退**：本机仅内建 XDR 单屏，物理不可测，按 D2 纠正门标 not-run。
- **物理 EDR 亮度、用户样本对照**：无测量条件，保持待验；PNG 亮度不得作验收。
- **iterations=0/1 官方空间行为**：沿用 D2 开放登记。

## 产物

`/private/tmp/mwx-hdr-toggle-20261007/`（app.log、时间戳、35+2 张快照、签名身份）：保留至 2026-10-21。run1（切换早于 ready，无证据价值）已清理。真实域偏好测试后已复原为 1（已核对）。旧 `hdr-off3` 临时证据路径已过期，现役指针由本记录替代。
