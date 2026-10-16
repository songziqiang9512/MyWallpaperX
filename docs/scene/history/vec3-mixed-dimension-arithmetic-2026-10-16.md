<!-- document-role: historical-evidence -->
# Vec3 与 Vec2 混合算术的缺维保留

> **历史证据 — 非现役入口**。截止2026-10-16。本记录覆盖共享 Vec3 四算术方法对实际 Vec2 操作数的限定行为；当前合同归[D4](../roadmap/batch2/script-component-api-design.md#vector-mixed-dimension-arithmetic)，API边界归[覆盖表](../capabilities/scenescript-api-coverage.md#102-vectors)，剩余可见问题归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。原包只取得owner-executed与独立实图回归，不记完整位置交互或整样本完成。

## 首断点与通用修复

U13 原包3042492564的layer1128 origin脚本在混合 Vec3/Vec2 算术后产生非有限z，旧typed return拒绝该值。[原定位记录](native-cpu-allocation-screen-2026-10-15.md#nonfinite-origin)当时未取得官方规则，保留原历史事实；本轮补齐固定客户端黑盒，再独立实施。

最早错误owner是`SceneQuickJSValueHost`共享Vec3的`add/subtract/multiply/divide`向量支路：无条件读取实际Vec2不存在的z，运算后得到NaN。现仅在实际Vec2分支保留接收者z，x/y继续原运算，仍构造新Vec3且不改左值；不按样本、资源路径、hash或源码形状分派。

构造`Vec3(Vec2)`/`Vec3(x,y)`仍补零，单Number构造与算术仍广播全部xyz；显式Vec3继续三维运算，显式z=0除法仍可在VM内产生Infinity。C有限值校验、typed publication、previous-current、journal与失败后恢复均未放宽，也未新增vector owner、cache、identity或帧准备。

## 固定官方可观察合同

来源为固定官方2.8.0.42自有黑盒，遵守[官方研究边界](../development/official-client-behavior-research-workflow.md)，未消费私有实现或真实作者表达式。

| 身份 | SHA256 |
|---|---|
| 官方executable | `daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07` |
| 自有probe | `b3611913bdb284f59085f1768f91f212370b348bc6d9268598b2d6c36abcaae5` |
| 有效CUA截图 | `1889d477193b6aa3b040be5a4f7501fac54b0d453a5689183a5d3f42fd4189ea` |
| 独立中性审查 | `23db7479792494da5dda669a94b591cc411b2c1886f49ce131bce7a01c243e24` |

Vec3接收者为(8,12,20)，实际Vec2操作数为(2,4)：

| 方法 | 观察结果 |
|---|---|
| add | (10,16,20) |
| subtract | (6,8,20) |
| multiply | (16,48,20) |
| divide | (4,3,20) |

完整24行包括改名直调、scalar 2及显式Vec3 z=0/1/5对照；左值均保持，结果均不同于左值。显式Vec3 z=0的multiply结果z=0、divide结果z=Infinity；另有Vec3(Vec2)构造补零对照，不能据构造规则定义混合算术。

黑盒没有测返回prototype/instanceof或右值是否改变，返回Vec3类型沿公开签名与现owner；本地测试的类型及右值不变断言属于保旧合同。缺维原样保留与中性运算数解释在这些有限输入上不可区分，不反推官方算法。

Vec4、mix、反向维度、plain object/array、追加z的Vec2、非有限输入、显式undefined及接收者正负零均未由本次黑盒裁决，不将本轮结果外推为其官方一致性。

## 最近门与产品身份

产品仅改`SceneQuickJSValueHost.c`四处表达式；源码SHA256为`8b7c5a45dc5a9d0555c206b532402c25c6d8dea083bbf8066841ba38567236b6`，397行。

复用`test_scene_script_quickjs.SceneScriptQuickJSTest.test_real_ecmascript_owner_contract`及原C fixture，不新增harness或镜像运算实现。新增行为断言覆盖四方法、改名等价式、scalar/显式Vec3、对象身份、构造补零、非法typed值与同owner恢复。

raw Infinity先在VM内部检查后用finite sentinel返回；另一独立回调直接返回非有限Vec3，必须BAD_RETURN，下一帧同owner有效值恢复。没有将Infinity写入typed snapshot的成功断言。

最近真实C门最终重跑PASS，2.907s、输入无漂移。Debug build PASS，13.524s、4279个输入稳定；构建与门只证明相应范围，不替代原包运行。

首次C门唯一FAIL是旧Topology fixture的滞后预期：dynamic snapshot包含`shadow.text='tick'`，setter自`be785aa9c3`已发布TEXT位，expected fields由0纠正为TEXT。本片30个新行为case无失败；Support只补actual/expected失败diagnostic，比较条件保留。此更正与currentOrigin无关，不为测试失败改产品。

## 原包运行的限定结果

同原包baseline观察窗12秒记录195个target1128非有限badReturn；candidate为0。首帧vectorValues由51增至52、failures由2减至1，剩余为layer544作者`ReferenceError:event`，未因本片处理该作者异常。

candidate ready15.730s、总28.063s、exit0、inputDrift=[]、退出gpuDrained=true。候选复用了baseline缓存，不比较启动性能，也不以时长差异认领收益。

两次`yuu_float` false/true热改均accepted，window42539与1个surface保持；根代理查看过候选真实画面。该证据证明原包不再命中1128的同一非有限首错，层级保S3 owner-executed；没有直接采集目标向量实际值，位置运动/布局与交互仍unknown，不能据无错误推为完整可见motion。

独立3147346398使用同一冻结App fresh运行：ready4.175902s、总14.327727s、exit0、inputDrift=[]、ownedGroupGone=true且GPU排空。根代理实际查看`scene-after-window.png`，暖色火光/砖墙、白色时钟日期与music line清楚；只作未参与修法的真实画面回归，不证明声学或完整parity。

不把root particle、健康peer或原包ready代替目标输出。光束、封面/裁切、布局、粒子及真实系统媒体仍有边界，没有整样本、官方画面parity或性能结论。

## 证据去留

官方中性观察、交接、独审与receipt保留于`.artifacts/tmp/nonfinite-origin-research-20261015/attempt-20261016/`。有效结果是`official-probe-cua.png`；黑屏`official-probe.png`与`capture-prlctl-black.png`不计结果。相同输入第二次加载只修复采集，不是扩展case。

三次本机运行均已退出、ownedGroupGone=true且GPU排空。逐项清掉本轮样本副本、HOME、临时目录、shader cache、原始runtime JSON及重复截图，共删除644,448,378逻辑B；日志经gzip解压回读验证后保留。根目录保留26,503,641B及两张after实图，精确清单见`cleanup.json`；全局证据预算已满，未扩大或删除他批证据。唯一连续DerivedData仍在`.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData`供后继复用；Windows VM按用户要求保持运行。

本轮执行与最近门根为`.artifacts/tmp/vec3-vec2-arithmetic-20261016/`，包含`baseline304/`与`candidate304/`的`execution.json`/`app.log.gz`、`c-vm-tests.json`及安全计数汇总`runtime-summary.json`；原始runtime JSON和作者表达式不进入实现或此记录。
