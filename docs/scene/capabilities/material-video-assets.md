<!-- document-role: stable-contract -->

# 材质视频资产合同

本合同扩现役Scene视频owner的材质入口；能力与实际证据归[台账](coverage-ledger.md#current-overview)及[批次记录](../history/material-video-assets-2026-10-12.md)。

<a id="material-video-assets"></a>

**材质视频asset/fallback合同：** catalog不持播放器，视频声明的`preparedVideoColor`只承诺发布合法颜色帧，不冒充ready；实际decoded frame仍验证alpha/purpose/publication，未知或straight alpha局部拒绝。asset沿原SourceKey/device/session共享源，逻辑asset、source incarnation、epoch和generation各保identity；不虚构layerID，不进入layer脚本控制。原timing传入各surface bridge，同帧prepare去重，video由原registry跨屏统一commit，atlas仍逐屏commit/discard。fallback选择与solid采样都只接完整typed videoAsset，静态图片及其他provider原准入保持。selected still优先，empty/reset恢复作者视频并保Scene-clock相位；原全局pause/resume、rebuild重取、source换代及stop取消管同一source。potential demand存续不另造active-demand分析器；本片不证明解码能耗优化、任意purpose或完整普通material组合。设计取舍与有界后验见[归档](../history/material-video-assets-2026-10-12.md)。

只接已准入的premultipliedColor需求；data/normal/flow及未知颜色表示不猜测。现video线明确linearClamp，不由未知TEX flag、文件名、路径或hash选择颜色/alpha/采样算法。普通帧不解析媒体声明，不建图或新播放器。SourceKey只界定资源身份；sample/layer/截图是回归身份，不能参与视觉派发。
