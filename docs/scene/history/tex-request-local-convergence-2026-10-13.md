<!-- document-role: historical-evidence -->

# TEX 请求内解析复用（2026-10-13）

> **历史证据 — 非现役入口**。顺序、进度及未执行项归[性能卡](../roadmap/performance-convergence-card.md)；本批不关闭其他视觉或属性断点。

通用语义：同一次纹理 demand 准备中，已解析的同版本 TEX 即使未获 decoded-cache 收纳，也供分类、上传与 typed Candidate 共用。原 Catalog 曾依次读取 container、视频声明、load 和 Candidate metadata；预算拒绝时重解析静态/动画路径四次。现在原 loader 产生短寿命 `PreparedTexSource`，携带完整 SourceKey 和既有不可变 TexResource，URL入口委托同一实现；没有跨请求新缓存、第二 parser/upload owner、预算扩大或样本/路径/hash派发。

source版本在准备结束、使用token、GPU cache/上传与Candidate发布处核对；旧token不能复用原子替换前的metadata或texture。原格式/purpose、padding/UV、动画/视频/volume、局部失败和瞬时allocation重试保持。普通load在decoded淘汰后仍直接命中GPU cache，不因本批先解析TEX。外层base-image/natural-size请求尚未收敛。

## 已证局部成本

自有2048² RGBA/LZ4 TEX（65,889B源→16MiB payload），冻结原d3eb97b3与最终源码、相同`-O` flags/fixture，每条件三个独立native进程。未获缓存收纳时：

| 实际loader调用序列 | 解析次数 | 解析payload同时保留峰值 | 操作耗时中位数 |
|---|---|---|---|
| typed Candidate | 2→1 | 16→16MiB | 24.452→15.606ms |
| Catalog静态序列 | 4→1 | 32→16MiB | 43.761→13.150ms |
| Catalog动画序列 | 4→1 | 48→16MiB | 46.293→12.972ms |

Catalog probe重放真实loader调用序列并显式保留外层container；这些是请求内成本，不是完整Catalog/App峰值。全部修后probe的普通warm load为0解析且同一Metal texture。允许cache的对照本来只解析一次，修后耗时有波动，不能据此声称默认App提速。

## 验证与边界

真实3662790108只读复制，完整935 Script owner运行；同3024×1964单surface、Debug显式-O、静音频谱fixture、execution observations关闭。修前/后各三次新HOME/engine cache，OS文件cache已暖；30s warmup、约63s正式计量，50Hz libproc读取kernel lifetime峰值。全部owner正常、failed frame为0、GPU drain完成。

| App指标 | 修前3轮 | 修后3轮 |
|---|---|---|
| 主进程kernel lifetime峰值（MiB） | 2049.221 / 2006.128 / 2084.643 | 2035.518 / 2069.471 / 2092.034 |
| startup ready（s） | 29.359 / 40.050 / 27.190 | 27.232 / 26.437 / 28.058 |
| completed FPS | 15.524 / 15.231 / 16.246 | 16.082 / 14.901 / 15.603 |
| GPU p95（ms） | 48.733 / 48.644 / 46.182 | 46.678 / 49.351 / 48.559 |

整App成本仍有波动，未证明默认预算下稳定内存、启动或GPU收益，也未量默认decoded拒绝频率。修前/后实际帧均由开场标题推进到太阳系、时钟/HUD；不能把静态退化负载拿来对照。未参与修法的2932157836由最终App独立启动，普通严格观察benchmark PASS，实际人物、水纹和星星继续合成；不代表所有媒体/时钟能力或官方全片等价。内部Host不是普通桌面产品入口或Release验收。

五最近模块27项通过，最终陈旧视频反例另复跑：替换此前成功识别的视频资源后旧token被拒；坏TEX、改名、purpose像素、padding/UV、动画/视频/volume、cache释放/GPU身份及allocation重试保持。补充parse-authority、decode-budget、animated-material、resource-view门及完整Debug-O build通过；独立只读审查绑定4路径diff SHA `888354d6c642e4cbd74f2626f8b215b3bef029fdaee7aca7e9c6dab70c075df0`，不以cache resident=0伪称请求payload或进程内存归零。

六轮旧工具整体benchmark为NON-PASS：主动关闭的graph执行观察仍被错误要求；AS1计量、首帧和drain有效，缺观察不伪装执行成功。旧报告及工具SHA保留，验证策略问题由后继独立工具修复处理，历史结果不追改成PASS。GPU计量亦存在HDR/reflection复制未入census的边界，95,026,176B/帧只代表已登记复制，不能视作全部带宽。后继按性能卡补计量与局部复制，生命周期长期切换仍未验收。

必要微门源码/fixture recipe、计时/身份、独审和少量实际帧保留于忽略的`.artifacts/tmp/tex-request-local-convergence-20261013`；停止使用的App、副本、HOME/cache、执行二进制按回执清理。现有总证据预算不扩大；不猜删未知材料。
