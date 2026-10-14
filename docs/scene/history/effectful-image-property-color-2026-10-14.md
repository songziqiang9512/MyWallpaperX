<!-- document-role: historical-evidence -->

# Effectful image 的属性颜色消费（2026-10-14）

> **历史证据 — 非现役入口**。能力边界归[属性合同](../capabilities/runtime-input-property-coverage.md#6-user-property-target-矩阵)，后续归[属性工作卡](../roadmap/properties-panel-card.md)。此批不关闭属性或性能专项。

## 通用语义

作者颜色已进入binding program和typed snapshot，普通带effect图片的capture也已消费颜色，但service/Host仍只承认effectless图片，造成合法颜色定义被过滤、编辑走整景回退。本批复用原链：service登记潜在ordinary image颜色；Host要求实际captured-layer capability、无依赖且不可能生成completed source，再登记原color target。隐藏不撤销consumer，未准备或mixed key保原原子拒绝。SceneScript、Puppet/model及非capture路径未扩展。

completed source会清除下游tint，因此不能仅排除首屏编译成功的material。由原Catalog.template候选投影本层及共享模型alias，覆盖首屏失败、后屏成功的情况；投影与runtime查找共用迁移后的原source-specific路径规范化，原prototype唯一性选择不变。没有新parser、store、通知、renderer或运行缓存。

## 验证与边界

最近门：hidden原7项、routing受改1项、LiveState17项及原effect_draw_alpha Metal三帧3项通过。独审指出跨surface准备差异及alias空白规范化两项静态反例后，补真实didSet/index/lookup反例，最终hidden8项与routing1项通过；GPU/LiveState未改，不重复运行。首轮fixture少换行编译失败、随后掩盖空白反例的旧收据均保留，不覆盖最终结果。最终独审ACCEPT。

正常Debug最终构建21.197秒通过，4294输入无漂移；真实376冷准备超过现启动预算，未ready，保超时失败，不计画面通过。最终优化诊断Release构建100.455秒通过，4294输入无漂移，App SHA `4a2524173ed61b4cc82682d4018bfa8e74d6d116e7be242a1b086276924ff853`。未测CPU/GPU、内存、启动或能耗收益。

真实376基线使用作者原包，仅启动打开文字并调alpha为1，live把颜色改红；旧App明确拒绝，画面仍浅蓝，正常退出、GPU排空，唯一验收失败为该更新拒绝。最终候选同条件原包运行PASS、exit0，无timeout；颜色更新accepted=true且surface/window identity不变，实际截图文字变红，人物、背景及动态效果继续呈现；停止surface归零且gpuDrained=true。固定文字ROI红色像素从0变为84421/810000，仅辅助已查看画面，不是同相位golden。未参与修法的Bunk原包运行PASS、exit0、无timeout，已查看实际房间、灯、窗景和时钟完整呈现；单屏局部画面不证明全样本或官方parity。

正常产品入口使用隔离工坊/HOME/defaults，实际播放376；面板打开、滚到底部，文字2 false→true按条件显示颜色/alpha，alpha0.3→1，关闭重开后Bool与alpha仍为true/1，颜色行保留。日志仅一场session激活，停止后正常exit0。原生颜色选择器未能通过自动化稳定展开，完整面板颜色连续编辑/重开、正常入口桌面像素仍未验；不把内部Host像素证据替代该缺口。退出后的工具AX读取自动重开了测试App且未继承隔离；未做编辑，即退出精确自有副本，进程均结束。

## 证据

本轮运行根 `.artifacts/tmp/effectful-image-property-color-20261014/`；最近门与最终八路径freeze在 `.artifacts/tmp/effectful-user-color-20261014/proof/`。已清理两份Debug App、隔离正常运行HOME/样本和重复ready截图共691552531字节，压缩11份日志；保留三个after截图、原始报告/身份及失败复现。最终优化App留作紧接CPU重构基线，连续构建沿 `.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData` 唯一缓存复用。证据全局1GiB预算前轮已满，未删未知记录或扩预算，本批紧凑证据留本地根，见 `proof/cleanup.json`。
