<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# 隐藏图片与文字的属性热更新（2026-10-05）

> **历史证据 — 非现役入口**。当前能力由[运行输入属性表](../capabilities/runtime-input-property-coverage.md)维护。

基线产品`622f61a1`。Host启动时用visible过滤image.color和text消费者，但文字loader/store已准备全部合法作者文字，普通图片颜色也已有snapshot消费者。真实2938612768隐藏文字1171直接绑定newproperty32；颜色newproperty19还共享924及79的effect target。启动遗漏使整键live拒绝，产品Service随后走原有整场景重建。最小修复删除两处visibility过滤；保留effectless image、text/style和limitWidth资格，不改变脚本producer、资源准备、raster、clock、Program或compositor。

## 实际验证

真实包原件只读；pkg SHA256 `1f3a74c0241bb8f57c0abdbcded05562e329ebfc6ff47bf762e8b71f4e0326fc`，project SHA256 `224360470a676696a07fc15a620c422126d1653f193d58b089c49b4e1a34f547`。同一序列为隐藏时改内容→显示1171→再改内容→共享改色。旧App接受结果`false/true/false/false`，候选全部true，同run surface/window始终相同且只有一次ready。隐藏时完成text publication，显示后1171实际effect GPU/compositor/next-frame成功；按时间戳核对series0004/0006/0009，依次见自有内容变化及绿色文字。作者封面遮挡右部文字仍保留。`scene-after-window`是启动后的固定延时捕获，不能按文件名当最终态。

两App该配置均实际执行56个effect，24个终端effect输出被compositor消费。descriptor包含73个作者effect，未触达17个处于其他隐藏布局或关闭选项，不能算失败或全样本正确；29/29 text source加载只证明准备。未做全模式、系统媒体来源或官方像素等价验收。

自有9000000790同时验证hidden image.color、text content/pointSize和shared color：隐藏时更新不偷显示，随后显现红图/红字，再变绿且字号10→14；蓝peer保持35721像素。最终非法color拒绝，frame6和frame9全图像素相同。含maxWidth用户wrapper的前置反例整键拒绝：编译器仍将该键列rebuildRequired，本次不扩准；CPU直接构造maxWidth target只能证明Host接纳条件，不能升级为用户控件已热更新。

Debug build和严格签名校验通过，候选dylib SHA256 `2a5fad6391ce16cd6f20912ba7529938eb42ead54b26e219748ddad9f28e4421`。CPU新门编译实际Host/eligibility/Program/LiveState；旧Host六个预期失败，新Host通过，八组无消费者/畸形输入仍原子拒绝。删除三条锁定旧visibility源码形状的断言，以行为门接管。独立只读审查确认prepared consumer生命周期与显隐职责分离。结构门两项既有inventory/classification失败未抬基线；其余最终门记录在收口包。

证据包`.artifacts/scene-evidence/runs/hidden-property-consumers-20261005/final/samples/2938612768/runtime_evidence.zip`：SHA256 `3aabdb91e2a458441fe5957c3965ab98c56da79f9300c5d6a645147f79ea20fc`，29832644 bytes，51项payload+manifest；仅必要截图、日志、自有输入与身份，不含真实媒体包/App。最终审查及提交后校验独立存同名`-commit`收口包。主运行使用现有Debug Host入口，未重新操作普通设置UI；普通Service成功分支由最近门验证，无整场性能提升百分比声明。

下一批以293属性模式为入口核对未触达17个effect，先区分作者关闭与准备/执行缺口，修复真实失败；不把本批四次热更新成功视作整样本100%。
