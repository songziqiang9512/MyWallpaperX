<!-- document-role: historical-evidence -->

# effect 辅助图片入口可见筛查（2026-10-15）

> **历史证据 — 非现役入口**

本记录只补既有能力证据、纠正旧覆盖表；没有新增texture Program/store/consumer。合同归[属性覆盖](../capabilities/runtime-input-property-coverage.md#effect-user-texture-visible)，选序归[属性卡](../roadmap/properties-panel-card.md)。

206原声明已有service→catalog demand→原资源事务→FrameRegistry→selection链。作者Custom Background指向342/effect344、Custom Circle指向161/effect947的辅助slot；shader元数据`g_Texture1 mode=rgbmask`使purpose由原schema推导preservedChannels，不能凭标签猜通道。静态声明与CPU applied不能证明实际选中slot，故先以原App零改动筛真实画面。

App SHA `3d66673365c6f56435aca0341e1630562c78afd5747c856ed32c67975df440b7`复用前批冻结Debug；product-entry沿真实Service/通知/Coordinator/daemon，副本内自有320×192 PNG为可识别棋盘，一张含0/128/255 alpha及透明像素非零RGB。保持作者background_settings/background、circle/circle2显示条件。此取证surface framebufferOnly=false，仅正确性，不量性能。

第一次因临时HOME仍在真实账户HOME内被严格guard拒绝（issued=false），19s停止空闲runner，无daemon/首帧，不记产品失败。改独占/private/tmp HOME后：

| 运行 | 实际画面及采用 | 身份与限制 |
|---|---|---|
| 冷轮 | 原山景/黑圆→背景绿紫棋盘→圆形橙黄图案 | parent98373/daemon98377；request14A48FE3-26C5-4F0C-9AAF-5C97508FEFFA，session972EFAF7-039E-4667-AD14-19B4387A6A08；一次launch/first-present，两次applied；冷准备约37s占45s窗，reset没执行 |
| 暖补验 | 首帧已保留前轮两项选图；头两步同值重发，随后reset背景恢复山景且保圆形选图，再reset圆形恢复黑圆/Windows图案 | parent98913/daemon98925；request35138C8E-EB78-4CAC-BE09-C73B69451410，一次launch/first-present，四回执applied、reset committedValue=null；新HOME没有清同一Debug suite的既有意图，不能合写跨两轮为一个session从default四次可见变化 |

root与独审实际查看原图，不以回执/PNG存在替代画面；圆形左侧白区不证明alpha透出背景正确。graph日志342/effect344与161/effect947在既有Program成功/GPU completed；Circle还经过suffix，单个中间节点compositorConsumed=false不代表最终不可见。原Transform/其他局部失败仍开放，不记整206兼容或官方parity。

两轮均正常退出0、对应37/37 VM quiescent，failures/timers/jobs/mutations/dynamicLayers=0，四PID消失；未导出全部纹理/pin drain。仍缺exact selected slot/purpose/publication generation、逐次frontend/shader/PSO准备次数、JPEG/坏图/取消/原生picker、普通framebufferOnly surface及性能验收。当前已足以否定“只有面板/CPU采用、无可见consumer”；不凭旧表再造链，后继只补具体未证合同。

`.artifacts/tmp/effect-texture-native-screen-20261015/proof/`保源/命令、失败前置/冷部分与暖结果、原日志和必要图共23,705,748B、独审/cleanup。原用户源tree复核source_changes=[]；isolated_changes仅自有两fixture及运行派生，副本及两外部HOME/tmp已清43,086,868B。唯一Debug domain清理命令返回not found，不删除任何其他偏好域；两键已由实际reset清override。共享App/构建缓存/shader cache延续前批，不生成新App。
