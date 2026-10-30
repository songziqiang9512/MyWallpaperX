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


<a id="puppet-parameter-timelines-20261031"></a>
## 动画层rate/blend时间线（2026-10-31）

3141464346的动画参数wrapper被parse取静态value，曲线未入现Timeline链；另原Selector以rate>0拒196/284的零速clip，使整父没有实际播放consumer。先在D4设计，后沿原IR保两条Optional曲线/诊断，原compiler发布具唯一parent/动画ID的scalar target，原SceneClock/resolver/Playback消费；原setRate保相位、ClipState.blend/LayerFrame.blends供pose与alpha，静态0保持冻结。五产品净增70行，必要增长为保作者参数及接既有消费者，未增owner、clock、持久播放状态或skin算法；普通static clip保短路，不每帧造target查snapshot。

旧产品语义RED38→Puppet playback12门GREEN，连真实parse/compiler/resolver/Selector/evaluator；0启动、blend>1、改名/等价曲线、隐藏冻结/同cadence、坏参数/真实混源与未准备Timeline99反例通过。另原rateScript11、property-preparation8、Timeline相邻2通过；standalone旧依赖漂移的编译失败保留并仅修source list/叶carrier。独审发现显式null被错误当竞争source，精确RED8后按原String codec修，最终12门17.396s通过；原direct变体带alpha却绕真实consumer的错误证据声明已撤，最终变体全部image，不认direct输出验收。

最终普通Debug32.197s build/严格签名、产品漂移0，主体2411aecf…6e756/dylib7364bc11…38de。314与baseline同包、PCM/指针、24秒after/30秒运行；baseline优化Release诊断、final普通Debug，不能比较性能。修前196/284无Playback consumer且骨骼hash不变；最终各640/204两个clip，204从rate0/frame0经变化到rate1/currentFrame502.098517，骨骼GPU完成且末graph被合成消费至frame773。原166/438、412/337的blend target已在真实prepared descriptor，日志未逐帧印blend，不把这一点升级成所有动作/混合数值已证。实际手臂及持烟位置明显改变，亲看与独立Max核对一致；无同官方输入/phase，仍不认整景parity或全部错位关闭。

原314前后strict均particle loading incomplete，188/332 world-space Rope与右下环保开放。独立3292370168最终App可见中央骷髅及背景视频，layer29 53 bones、model-depth encode与视频frame12 qualified，八rate VM target完成0.15；只证明所观测输出，不认八clip全播放。该run仍七项utility/graph期待失败，且无同条件修前，不能称新/旧回归或整例PASS。原始失败、完整日志、六张必要原PNG与改名门/红绿/构建身份归同次`.artifacts/scene-evidence/runs/user-priority-capabilities-20261031/`，29,371,936B/181成员、SHA23122036…c3d808；heldout仅保缩小JPEG及原图SHA，不能作精确像素/HDR golden。

后继6d2a390e6只合入UI文件，逐Scene输入hash与最终构建一致；二进制不追认成含该UI的新App。本轮原生/worker均退出，真实样本只读，VM/主客户端保持运行未做新官方实验。临时副本、HOME、原图与重复build报告归档后清理，仅保`.build-cache/scene-gravity-20261028`连续缓存；不认长稳、HDR/多屏、全部属性或性能收益。
