<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。当前能力和后继分别归文内所链的高级对象合同与 D4。

# Puppet 动画隐藏恢复与共享播放位置

本记录保存 `f70a0787` 后继的有界实施。当前能力归[高级对象覆盖](../capabilities/advanced-object-coverage.md)，脚本控制后继归[D4](../roadmap/batch2/script-component-api-design.md)，样本剩余问题归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。不据此重开已完成步骤。

## 问题与实施

旧 `ScenePuppetPlaybackState` 在 getter、physics、geometry 三处各用 sceneTime 求动画帧，动画层隐藏再显示会跳过隐藏期间。现在 LaunchContext 的唯一 `ScenePuppetAnimationPlaybackRuntime` 注册已准备 clip 定义、消费既有 SceneClock 和 typed visibility；隐藏冻结位置，恢复只加入当前 cadence 增量。所有 surface 的骨骼、alpha、挂点、skinning 和 encode 消费同一份 samples；自然 single/loop/mirror/rate 及 TRS 插值算法不变。没有新增 clock、资源系统或 compositor。

相同定义复注册保留进度。独立审查发现暂停首帧局部资源失败、暂停重建后新注册层可能遗漏于旧快照；已修为同 cadence 仅补入新 parent，保持已有 samples、visibility 和冻结 sceneTime，下一 cadence 再共同推进。反例由实际 Swift owner 验证；未在完整 App 注入 GPU 分配失败。

## 官方行为边界

固定官方 `2.8.0.42` 的自有输入黑盒记录在 `/private/tmp/mwx-puppet-seek-20261007/official/behavior-contract.json`，保留约3.42MB必要材料。客户端 SHA256 为 `DAAC1EA7C991207FDB6098616757E3DAE393850F6862845DB55D04921B6BDA07`。隐藏约0.79秒 getFrame 冻结而 isPlaying 仍 true，恢复后继续。受控轨道 0/.5/1 的平移20/25/30、角度10/20/30度与现插值一致。

同次研究还为下一片确认直接 IAnimationLayer、play→93% seek、raw getter 与端点钳位、自然 loop ended callback 位于普通 update 前；这些是**待实施控制 API 的输入合同**，不是本批已支持功能。最终 GPU 的 seek/visibility 相位、mirror ended 和跨多圈事件仍未测。Windows 自有实验窗口已关闭、staging已删除、VM恢复 suspended。

## 验证与证据上限

本批原件根 `/private/tmp/mwx-puppet-visibility-20261007`；产品确切文件和diff身份由 `product-identity-final.json`、`review-product-final.diff` 固定。运行App、输入及清理身份以同根 `manifest.json` 为准；最终App CDHash `95baf12b5055f8b6f67f0a0f765bdb7c6c782fa7`，strict deep签名验证、运行前后签名及最终独审均通过。

- `focused.log`：43项通过，覆盖唯一推进、隐藏恢复、初始隐藏、非零起点、自然三模式与rate、复注册/冲突、缺失/错误visibility、暂停晚注册、旧几何失败与恢复。生产Metal门读取实际像素；恢复帧骨骼/挂点X均0.125、coverage0.5，两surface相同。
- `frame-routing.log`：6项现有接线门通过。code-health、Scene依赖、防御与结构门通过；防御仅既有acknowledgement告警。Debug构建和最终App结果见同根日志。
- 受控App用同一作者资源、单clip750、rate .05，typed property初始false、两秒后true；observer脚本锁存首次可见的bone11.x并放大投影到origin，使跳帧差异可直接见于像素。它是观测fixture，不是原包身体应平移的结论。基线/最终候选的截图非背景重心X为1763.3825/1125.7278，Y基本不变；两次各自沿用同一窗口、属性接受、exit0/无超时；通用hover门因无交互位移仍FAIL，不改成整体PASS。
- 原始 `3791967416` 隔离回放：六个Puppet层、十条clip进入现役播放；graph GPU完成、terminal compositor与next-frame均有证据。通用hover位移仍未通过。亮度、眼部组装和动画层脚本seek尚未闭合，不报整样本正确率。

产物只保留必要日志、报告、身份和对照截图；中央证据库已满，promotion拒绝、prune无可清包；不删除未知旧证据，本批限量保留于上述根目录。临时App/输入/重复运行产物在进程退出后清理。同一连续任务仅保留既有build cache `/private/tmp/mwx-scene-next-build/cache/14d60a183f08e048bc3d072d`。完整显示器切换、长稳、性能与官方整帧parity未由本批证明。
