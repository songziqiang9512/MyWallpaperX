<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。设计与目标合同见[Scene 真实播放器媒体输入设计](../roadmap/batch2/system-media-input-design.md)；前序实施冻结见[系统媒体输入记录](scene-system-media-input-implementation-2026-10-05.md)。

# 系统媒体平台供应确认与实时链验证（2026-10-06）

起点 `3e7a8e88`。M1 后继第一片：确认平台实际供应的 metadata，并用真实活跃会话验证统一系统入口的切歌跟随。

## 平台 metadata 供应表（MediaRemote 观察器实测）

只读探针（与产品同 observer dylib，Perl XS 宿主直跑，11 秒 5 帧）在系统活跃会话（`com.apple.WebKit.GPU`，用户浏览器播放 X 视频）上实测：

| 字段 | 供应 | 实测 |
|---|---|---|
| source / identity | ✓ | `com.apple.WebKit.GPU` / `4839120` |
| title | ✓ | `MELO (@MELO_1M) / X` |
| artist / album | 按来源 | WebKit 视频为空（显式空，非缺失误报） |
| playbackState / position / duration | ✓ | 1 / 399→407s 前进 / 1211.266s |
| artwork + 增量协议 | ✓ | 首帧 4.2MB（base64 约5.6MB）、后续 `artworkChanged=false` 零重传 |
| albumArtist | ✗ | 平台无该字段（前批三次探针确认，不猜值） |

本机已装全部目标播放器（网易云/QQ/QQLive/汽水音乐/Apple Music 且 Music 常驻）；用户偏好已是 `systemNowPlaying`（此前各场景运行中的媒体面板曲目即真实链输出）。

## 实时场景验证（含自然切歌）

签名 Debug App（dylib `ca60b5de…41bd`）跑太阳系 45s（`MWX_SCENE_DEBUG_SYSTEM_MEDIA=1`，偏好 systemNowPlaying）：日志 `source=systemNowPlaying status=published`；**媒体面板实际显示 "MELO (@MELO_1M) / X"**（非音乐网页视频源经统一链入景）；运行期间用户浏览器自然切到下一视频（duration 1211s→约1838s、position 重置 0:03）——**identity 切换被实时跟随**，面板进度/标题随新曲更新；新视频无封面显示为空（显式清除，符合设计"缺字段显式清除，不保留前曲封面"）。

## 结论与剩余边界

统一系统入口的"任意 App 适配 + 切歌跟随 + 发布"以真实非音乐源验证；此前水星/土星各运行中的真实曲目（身骑白马/Pneumatic Tokyo）同链佐证。剩余开放：①暂停/恢复状态迁移的实时观察（state 1↔2 路径已实现+probe 协议验证，未见真实暂停样本）②多播放器并发仲裁切换的显式观察（仲裁权在系统 localNowPlaying，跟随已证）③QQ音乐/网易云/汽水的账号内实测（需播放发生）④歌词独立能力（作者消费合同与来源未定位，另批）。D6 私有发布边界不变；Release 拒绝系统来源照旧。

**午后补充（被动观察，同日）**：同机挂 2 小时只读观察器（7363 帧）捕获完整自然时间线——系统仲裁在 `com.apple.WebKit.GPU`（网页视频，state 1 播放/state 2 暂停均出现）与 `com.apple.Music`（"Pneumatic Tokyo"，state 2 长期暂停）之间多次互切，含 noSession 空窗；观察到暂停态 Music 压过播放态 WebKit 成为当前来源（仲裁跟随最近交互的应用而非播放状态）。剩余边界①②由此获得自然观测：暂停/恢复状态与多播放器仲裁切换均为系统行为，观察器如实上报，场景链消费无需按播放器适配。日志存 `/private/tmp/mwx-mercury-20261006/media-watch.log`（已入证据包 manifest 外的原始全量）。QQ/网易云/汽水账号内实测与歌词仍开放。

## 证据

探针 5 帧 JSON（封面载荷归档时脱敏为摘要+SHA，全量日志在 `/private/tmp/mwx-mercury-20261006/media-probe.log`，sha256 见 manifest）、场景运行日志与末帧 PNG、运行身份打包于 `/private/tmp/mwx-mercury-20261006/system-media-live-20261006.zip`（`53d535dd…80a9`，逐文件 SHA manifest）。
