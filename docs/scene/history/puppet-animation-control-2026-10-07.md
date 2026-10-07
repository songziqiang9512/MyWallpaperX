# Puppet 动画层脚本控制验收记录（2026-10-07）

> **历史证据 — 非现役入口**

截止日期：2026-10-07。当前能力归[高级对象覆盖](../capabilities/advanced-object-coverage.md)，未开放profile归[D4](../roadmap/batch2/script-component-api-design.md)，样本剩余问题归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。本记录保留控制事务及独立审查的反例，不决定后续任务。

## 实施与局部失败

沿上一片的唯一 LaunchContext 播放 owner 接入 nested Boolean owner，稳定身份包含父ID、动画层authored index及ID。metadata来自已准备MDLA，C只维护回调镜像、命令和真实ended roots；play/pause/stop/setFrame与rate/blend/visible进入现owner effect、fixed-point拒绝及consumed-cadence提交。公开bone getter读脚本前快照，控制从下一cadence进入共同pose、alpha、挂点、physics与GPU；没有新增clock/renderer或样本分支。

显式定位与自然循环分开：raw getter保留负值和超尾值，暂停pose钳位到首尾；自然single/loop/mirror继续原插值。mix weight变化即使paused、sample不变，也会使geometry/coverage更新。持久本层handle允许同owner跨callback使用，拒绝跨owner/过期身份。

独立审查关闭两类问题：ended的输入消费不能随effects回滚（否则JS闭包副作用重放），水位改为单调而roots/control仍撤回；额外准备的初始隐藏script clip不能撤销健康父层，未知动画、不支持参数、与必需/其他可选clip重复ID及consequential multi-clip alpha profile冲突均局部剥离该新可选资源，相关script因prepared metadata不可用局部失败。原visible/property-bound profile保持原拒绝规则。latched ended profile失败停用对应script owner，避免每帧重试；自然模型播放不受影响。

## 验证范围

证据根 `/private/tmp/mwx-puppet-control-20261007`；`product-identity.json`固定最终28个产品文件，`review-product.diff`保存tracked diff，新增typed control与Swift bridge另有完整source hash。最终diff SHA256为 `d65cf069148e0874cfb15c8baae472ec2ee3412dc812607b4cbba9414128615a`。

- `runtime-focused.log`：20项真实Swift owner测试，raw seek、pause/stop/play/rate/blend、自然三模式、hidden恢复、错ID/预算/非有限值与同cadence重用。
- `puppet-gpu.log`：35项通过；新反例同一paused sample仅改blend，实际Metal中心alpha48→32且图像hash变化。既有GPU发布失败与恢复、Puppet采样/权重门保持。
- `selection-final.log`：最终selection与runtime/parser共32项通过；`parser-final.log`另验证optional-before-required及optional重复的局部拒绝。现有binding parser14项、frame/video13项与目录结构2项通过。
- `host-final.log`：最终C/Swift真实VM7项通过，包括实际作者init、持久handle、事务拒绝、ended不重放与不支持profile只停用本owner；关联Script回归52项在前一冻结版本通过，最后改动仅上述失败返回及pending过滤。
- `build-final.log`成功；最终App CDHash `e8fb6fdd4e7b88a1f782619d3411ab1e05e0f58d`，三个运行前后签名均通过。`final-original/report.json`：原始样本30秒正常退出，两条作者动画层脚本完成，4条控制命令frame0提交；6个Puppet层、10个clip，41个graph全部GPU编码，failure=0。
- `seek-frame-25/75`：同一App中暂停定位raw frame0.25/0.75，各提交3条控制。自有轨道bone11的x预期22.5/27.5，经下一cadence公开getter放大到origin，再进入实际合成；图像非背景bbox x=838…1737与1165…2064，centroid x=1276.17→1601.43，姿态也变化。此对照证明VM控制经过共享pose到最终像素，不是原样本完整画质或官方GPU相位证明。
- 三个benchmark总判定仍为FAIL，唯一原因均为hover output未达最低变化量；不改门槛或宣称交互通过。前期两个夹具问题（缺builder、百分比乘360落入同一恒定轨道）已纠正，无效对照不计入结果。只保留最终受控与原始运行。
- 与用户只读官方“截屏”比较，原样本当前仍明显偏暗，眼部组装与半透明副本尚未收口；viewport、鼠标、动画时刻未完全对齐，不从单张差异直接归因HDR。

## 限制与材料

真实用户样本及其“截屏”官方图片只读。最终GPU seek相位未与官方固定帧对齐，不宣称完整官方parity；ended仅已证的loop单次自然越界，single/mirror及单tick多圈明确unsupported，原自然姿态仍播放。跨层动画lookup/create/destroy仍未开放。本批不证明完整样本正确、眼部组装、最终亮度、HDR/SDR、重型样本启动、多surface控制联验、长稳或性能。

临时App、输入副本和重试产物在进程退出后清理；只保留必要报告、压缩日志、身份与每组一张截图。中央证据缓存已满，prune未发现可清的登记过期包，promotion拒绝；不删除未知归属材料，本批有界结果暂留上述证据根，下一轮优先复核迁移。一份连续构建缓存沿用 `/private/tmp/mwx-scene-next-build/cache/14d60a183f08e048bc3d072d`。
