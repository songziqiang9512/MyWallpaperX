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
- **逻辑与backend分离：** 原lifecycle仍在相同起点启动并按Scene时钟推进，脚本命令/snapshot保原语义。不能直接skip现prepareFrame：首次启动在该方法，loop/非loop终结又依赖backend EOF；须先闭合隐藏期相位、loop与endedGeneration。不能借全局pause/suspend实现dormant。恢复在唯一source按当前相位重锚，未ready保last-ready，不从零重播、不发布伪造帧。
- **identity与失败：** 同源不同owner/播放intent不合并。跨屏取并集，单屏缺drawable不能停另一屏所需source；需求不能在一个surface拒绝后覆盖共享生命周期。原epoch/command generation、候选/commit/discard、GPU持有texture与stop/rebuild/迟到回调继续生效。不能证明无消费时退回当前eager行为，不能扩大黑屏或整帧失败半径。
- **最小切片与退出：** 先限已证无外部消费者的layer视频，证明typed clock与backend分离后才接dormant；不同时扩dynamic createLayer或材质purpose。必须覆盖改名/等价输入、隐藏→显现、播放/暂停/seek/rate、loop/非loop及EOF、跨屏、拒帧/重建/停止，并用未参与设计的真实视频样本检查画面/次帧。资格或收益不成立即撤候选，保原eager路；验收后由本节接管稳定合同并删除迁移说明。

普通优化配置的同输入前后对照须证明可见视频供帧及CPU/内存收益且无非目标退步，按[性能卡](../roadmap/performance-convergence-card.md)风险分级，不把删除输入的消融当性能验收。动态视频实例另需prepared资格、每实例owner/epoch、拓扑事务与资源复用/退出设计；不能为绕过null直接放开constructor，更不能照作者每帧destroy/create就重复写MP4、重建播放器。
