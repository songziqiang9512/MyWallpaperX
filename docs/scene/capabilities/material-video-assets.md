<!-- document-role: stable-contract -->

# 材质视频资产合同

本页的视频入口合同已实施；下方需求生命周期设计尚未实施，不改变现役播放行为。

本合同扩现役Scene视频owner的材质入口；能力与实际证据归[台账](coverage-ledger.md#current-overview)及[批次记录](../history/material-video-assets-2026-10-12.md)。

<a id="material-video-assets"></a>

**材质视频asset/fallback合同：** catalog不持播放器，视频声明的`preparedVideoColor`只承诺发布合法颜色帧，不冒充ready；实际decoded frame仍验证alpha/purpose/publication，未知或straight alpha局部拒绝。asset沿原SourceKey/device/session共享源，逻辑asset、source incarnation、epoch和generation各保identity；不虚构layerID，不进入layer脚本控制。原timing传入各surface bridge，同帧prepare去重，video由原registry跨屏统一commit，atlas仍逐屏commit/discard。fallback选择与solid采样都只接完整typed videoAsset，静态图片及其他provider原准入保持。selected still优先，empty/reset恢复作者视频并保Scene-clock相位；原全局pause/resume、rebuild重取、source换代及stop取消管同一source。现役材质入口按potential demand存续，尚无active-demand执行；本片不证明解码能耗优化、任意purpose或完整普通material组合。设计取舍与有界后验见[归档](../history/material-video-assets-2026-10-12.md)。

只接已准入的premultipliedColor需求；data/normal/flow及未知颜色表示不猜测。现video线明确linearClamp，不由未知TEX flag、文件名、路径或hash选择颜色/alpha/采样算法。普通帧不解析媒体声明，不建图或新播放器。SourceKey只界定资源身份；sample/layer/截图是回归身份，不能参与视觉派发。

<a id="video-consumer-demand"></a>
## 待实施：视频消费需求与后台解码分离

目标是避免无消费者的并行解码拖住可见视频；资格见[同App输入消融](runtime-evidence-current.md#video-publication-demand-20261021)。不以隐藏、离屏或同源直接判定可停，不改作者内容降低负载，也不把动态视频创建失败合并为此优化。

- **职责与数据流：** 复用prepared图的取源/命名依赖与typed可见性、播放intent形成消费需求；Session在共享帧汇合各surface需求，再交原registry/source决定backend是否工作。未知依赖、脚本帧/EOF观测需求保守active；asset/property视频先保原路。不新增需求registry、时钟、播放器池、图或最终输出owner，普通帧不解析脚本、重建图或扫描资源。
- **逻辑与backend分离：** 脚本命令/snapshot、起点、相位和终结必须先资格，不能把当前eager实现反定为官方合同。10-21官方自有隐藏载体的播放状态、currentTime与EOF回调呈混合行为，原advance/held判据均未成立，保持STOP_UNKNOWN，暂不接dormant。现prepareFrame同时负责首次启动、anchor及依赖backend的loop/非loop EOF，不能直接skip或借全局pause/suspend。恢复必须复用唯一source，未ready保last-ready，不从零重播或伪造帧。
- **identity与失败：** 同源不同owner/播放intent不合并。跨屏取并集，单屏缺drawable不能停另一屏所需source；需求不能在一个surface拒绝后覆盖共享生命周期。原epoch/command generation、候选/commit/discard、GPU持有texture与stop/rebuild/迟到回调继续生效。不能证明无消费时退回当前eager行为，不能扩大黑屏或整帧失败半径。
- **切片与退出：** 无图像消费者的帧提取/Metal包装原型已因非目标footprint退步撤回，限定结果归[运行记录](runtime-evidence-current.md#video-publication-demand-20261021)，不重复同型验收。后继须先取得新的backend消费或实际供帧证据；保原prepare/anchor/EOF与last-ready，任何首次prepare前汇合跨屏需求，未知依赖保持eager，不合并不同source/intent。dormant另待隐藏行为和typed clock资格，dynamic createLayer另立切片。覆盖改名/等价输入、隐藏→显现、seek/rate、真实loop/EOF、跨屏拒帧/重建/停止及独立真实视频；资格或收益不成立撤候选。

普通优化配置的同输入前后对照须证明可见视频供帧及CPU/内存收益且无非目标退步，按[性能卡](../roadmap/performance-convergence-card.md)风险分级，不把删除输入的消融当性能验收。动态视频实例另需prepared资格、每实例owner/epoch、拓扑事务与资源复用/退出设计；不能为绕过null直接放开constructor，更不能照作者每帧destroy/create就重复写MP4、重建播放器。
