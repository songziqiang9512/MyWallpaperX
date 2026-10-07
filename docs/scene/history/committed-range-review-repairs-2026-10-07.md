<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。后续任务见[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

# 提交区间复审与在途修复（2026-10-07）

冻结审查范围 `dead0a10..f430c473`，33 次提交。用户授权接管在途修改、修复已发现问题并继续检查算法与职责。本记录是该次修复证据；现役顺序仍由[断点队列](../roadmap/scene-open-breakpoint-queue.md)决定，不是另一份待办。

## 修复与实际收益

| 职责 | 修复 | 用户可见结果与范围 |
|---|---|---|
| shader 用途证明 | 短 `float` 声明先检查 token 数量；数据通道仅以完整、无未知/遮蔽调用的 `mix` 权重消费成立 | 避免加载合法 shader 时越界崩溃；避免颜色消费被误判成原始数据通道 |
| shader 类型归一化 | 同一声明中逗号后的所有变量进入原类型表；同名异类保守禁重写 | 合法 float 复合赋值不再被另一函数的 int 同名变量误截断；实际 Metal RGB 保持 0.5 |
| 灯光单位 | authored 与 typed snapshot 都消费 canonical radians；脚本度数只在既有 VM 边界转换一次 | 只改灯色/强度时不扭转原方向；脚本灯角不再二次缩小。初次修复和 fixture 曾错误保留脚本二次转换，独审追到真实 producer 后纠正 |
| 灯光配置/上传 | 缺失或畸形 lightconfig 不启用灯族，有限非零数值才开启；pointCount 使用过滤后的实际点灯数 | 不再产生未声明的光照；0–4 个有效点灯与 GPU uniform 一致 |
| 媒体仲裁 | Music 授权不立即退役 system，只有完整快照被 inbox 接受后接管；epoch 拦截迟到 system 回包 | Music 无曲目/读取失败/快照无效时，其他系统播放器的歌名与封面不再被清空 |
| Release 打包 | observer dylib 在外层 App 前用同一 Developer ID 签名 | 修正发布包嵌套代码签名遗漏；不等于已完成 CI、公证或平台全覆盖 |
| 模型材质 schema | comparison sampler 从数值 uniform 冲突检查排除，其余身份/声明证明保持 | 阴影 sampler 元数据不再误拒无关的数值材质参数；不授权新的 shadow 或 material-only 执行路径 |
| 内嵌 JPEG | 删除在途手写 EXIF/TIFF 与手工旋转，复用 ImageIO 的完整方向变换；元数据尺寸按显示方向校验 | nil/1 及旋转/镜像 2–8 正确上传。大图降采样复用已校正图像，删除第二次解码；照片底图可进入实际显示 |

没有样本 ID/路径算法分派，没有新增 runtime owner。`SceneGraphPreparationAdmission` 仅更名为 `SceneGraphPreparationHandle`：其 finalize/cancel/deinit 一直委托原 allocation cache，名称现在表达真实生命周期句柄职责；不扩分析器家族、不改基线数值或准入算法。归档后断链同步修复。

## 可复验边界

- 原失败与修复后用例：短声明越界、跨函数 float 截断、lightconfig 缺字段、点灯数量、媒体 fallback、嵌套签名命令、JPEG 正常/镜像/旋转与尺寸不匹配。
- JPEG 大图反例走实际 TEXB3 loader：4097×2、orientation 6，最终纹理应为 1×4096；旧 fallback 实测丢失方向，修复后通过。四角读回验证实际 Metal 像素，原 PNG source-channel 用例保留。
- 灯角回归必须经过真实 VM degrees→radians→snapshot→light consumer；单独向 fixture 填 90 并不足以证明脚本链正确。
- 首轮四样本回放发现独立局部 float 权重被新递归误拒；补入原类型表并覆盖赋值/遮蔽反例。随后独审发现同名局部变量可吞掉调用检查，又补调用形态优先反例；合法聚光灯效果须在最终 App 中重新执行，不能只凭合成测试收口。
- 新方向测试登记在 resources 组；独审发现初次误挂 layer-source-passthrough 后纠正，单独改纹理产品源可选中该门。
- 实际构建、运行身份与最终验证结果见下节；局部测试、可见截图、全样本正确性和官方一致性分别计算。

## 整合验证

最终产品/测试冻结到 `final-source-identity.json`；Debug build 成功，Developer ID 本机 staged App 深度/严格验签通过。本轮均为隔离 Debug direct Host，不能代替普通 App分发→client→daemon 验收。最终 App CDHash `0ee97af533a47c516e1b146bf1566a153afbd2b4`，Debug dylib SHA256 `9afaa9337f03fbf5dd999d90a2a3ec2f3c7e3a899239ef9b0bd6fbe410e6b3af`。未执行 Release CI、公证或官方同输入对齐。

聚焦门：纹理方向/真实 loader 2、PNG source-channel 与模型绑定原门、shader canonicalization 11及最终用途模块2、lighting/真实VM 40（点灯GPU上传另有此前不变修复门）、媒体/发布16、allocation29、frame-resource1、结构15均通过。文档/门禁工具150项全部通过；code-health、defense、dependencies、design、registry、document-health和diff检查均通过。独立代理先后否决了大图fallback、脚本角度fixture、门禁分组与同名调用漏洞，修正后终审接受；只读审查不冒充独立App复跑。

| 运行 | 实际结果 | 未通过边界 |
|---|---|---|
| 首轮四反馈样本，10s | 四者均启动、exit0并清退；380照片恢复。发现379的局部scalar用途回归，随后修复 | 整体benchmark均FAIL，不能把loaded比例当完整正确率；322既有UV维度转换/粒子/图接合失败、833和380 hover门、379其他效果仍未闭合 |
| 最终379，10s | 用途拒绝归零；层23五效果均encoded-output，五条效果输出恢复，脚本材质值进入执行 | loaded=0.958仅为加载比例；其他color-contract/GPU/compositor观察项仍令整体benchmark FAIL |
| 最终380，10s | 照片底图方向与实际合成显示正常，exit0 | loaded=1.0不代表整样本完成；hover输出低于通用阈值，音频活动/全部交互没有本轮验收 |
| 最终土星，75s | exit0、无超时、GPU drain；定时后段截图可见土星受光与云带，未见 non-finite vector/badReturn；同一最终App身份 | after截图未落盘，通用benchmark仍因非黑/hover观察门FAIL，开场与稳定态不能混用；明暗分界、环影、能量尚未完成官方同输入对齐 |

源输入 SHA 与具体失败、App身份绑定各轮 report；最终379 package SHA `c2ac2d365c87ba0253c439381709d686db24a7218c1005529df63b8b9bc61199`，380 package SHA `5360c2d4a52d22be093e0c4462fde6f29e24be4707eb7d88afd3b60f1aaa5b89`。现场与最终最小证据保留位置 `/private/tmp/mwx-review-fixes-20261007`，不是仓库依赖。已有共享证据缓存接近1GiB且无可到期包；默认提取超过32MiB已拒绝，不扩预算或删除未知材料，收尾仅保留必要报告、日志、身份和代表图；大体积文本无损 gzip，映射及原 SHA 见 retention-manifest.json。

## 用户官方截图对照

用户确认真实样本目录中的 `截屏*.png` 是官方客户端实机图；只读取图，不修改原件。2026-10-07 本次已核对 380 的 `截屏2026-10-07 08.26.54.png`、379 的 `截屏2026-10-07 08.28.05.png`、土星的 `截屏2026-10-06 10.07.18.png`。官方图含虚拟机边框且分辨率/时间/鼠标/音乐状态未同步，故仅作定性构图与细节基准，非逐像素parity。

380 的照片方向和主体已恢复；裁切随显示比例不同，不据此宣称完整交互完成。379 我方仍明显偏暗且身体/服饰细节弱于官方，不能因聚光灯用途准入闭合而宣称完整显示恢复。土星已受光，但环面亮度、颗粒细节、明暗分界仍明显不同；不得用截图调色常量代替 light/material/shadow 合同修复。现役余项已回到 QF 对应卡。

## 保留的能力缺口

四样本的 puppet 附件错位、material-only flow 执行，以及 `tech_circle_barcode` 色彩证明等余项继续按 QF 路线处理。土星官方方向/能量对齐、HDR 的多屏/SDR/物理亮度、所有播放器与歌词能力也没有被本次修复自动验收。下一 Agent 不得把已关闭的七个审查缺陷重新当作能力计划，也不得把上述未验收项标为完成。
