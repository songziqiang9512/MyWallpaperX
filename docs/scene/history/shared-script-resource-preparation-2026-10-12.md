# 脚本公共图片资源准备（2026-10-12）

> **历史证据 — 非现役入口**。当前能力归[SceneScript API](../capabilities/scenescript-api-coverage.md)，未闭部分归[断点队列 N06](../roadmap/scene-open-breakpoint-queue.md)。

## 通用语义与责任

同一普通图片创建请求不应因所属属性返回Boolean、Scalar、Vector或String而丢失准备资源或材质颜色。旧需求来自Boolean visibility投影，其他合法owner虽执行回调却创建失败。本片把直接literal请求的发现接到既有四族owner目录与ValueOwner配置入口；同一source分析给原材质lowering提供候选依赖，实际成功domain给原DeviceResourcesTask提交最终GPU需求。失败候选及被替换route不发布需求，alias仍属原owner；metadata与静态准备并行及原GPU join保留，没有新loader、renderer或逐帧IO。

请求扫描复用既有lexer，退出原正则请求抽取；注释、字符串里的伪调用/伪image字段不遮住真实请求，未知间接请求不抹掉同源码已知请求。权限仍由原host合同决定，发现资源不能把value-only、effect或Puppet Boolean升级为可变更图层的owner。设计见[D4](../roadmap/batch2/script-component-api-design.md)。有限literal语法仍是[集中登记的兼容限制](../development/development-workflow.md#compatibility-exceptions)，不宣称任意JavaScript依赖发现。

## 实际输出与验收边界

基线fd2c2aea的自有四族输入仅Boolean位置有100×50图片。相同最终输入四格均可见；另用既有自有neutral shader和script material color证明四格均为绿色，避免只接通白纹理而漏掉颜色消费者。变量/资源改名、等价scale表达式、普通字符串/注释伪调用和独立未知helper请求的变体，实际白色截图与原四格完全一致。三组首帧/后帧24格尺寸均100×50，误差小于1作者像素；不是profile命中断言。

未参与实现选型或调参的2983846453原包前后，时间/日期、日夜开关外观及频谱保留；3792817546的63个动态图片实际publication及encode，画面频谱仍可见。时钟未固定，颜色/动画相位变化不作为逐像素等价。2887542690默认原包复验仍保留6个特殊clone的null/visible异常；不把默认关闭的阴影、text wrapper或完整布局计作本片修复。

最终十产品文件冻结清单为`implementation/product-freeze.json`，SHA256 `90b9221b8beea5d8b12817a2d6b8c742aa3198a0ef3f67ae0202f9f81cc3375b`。Debug构建、签名校验及六次隔离原生运行通过，均ready、exit0、GPU drain完成。证据根`.artifacts/tmp/dynamic-text-wrapper-20261012/`，`product-build-identity.json`绑定源码/App，`native-results.json`绑定输入、实际截图与像素测量。该入口是direct Host和受控音频，不等于普通App→daemon、真实系统音源、性能或完整官方parity。

## 已研究但未实现的文本后继

官方2.8.0.42自有输入证明：text原始wrapper保留value/script；纯String与value-only对象可见；两次复制含脚本配置的文字得到独立init/update状态，创建第二份不重置源或第一份。创建返回后的第一次text读取已可见init结果，但实验不能区分create内部完成与getter触发。`official-handoff-approval.json`绑定自有输入、两张原始截图及中性合同，合同SHA256 `f2c5e10d4c3c20b870deee905ff619c996792b94d2407c95c57194084355e50a`。

这需要接入既有动态层的脚本identity、状态、事务及退出，不应仅把wrapper取value或借用源owner。user绑定、失败回滚、销毁与任意新source/import仍缺合同。本片未实现此能力；后继先比较它与缺省FOV投影的可见覆盖和闭合成本，不因已有研究继续无界扩题。helper/registered handle资源、特殊Puppet/composition clone仍留N06。

收尾边界：七项真实VM与三项原task受控门覆盖四族输出、相邻词法反例、最终route过滤、owner-local alias、Cursor权限、失败重建、空需求与取消；最近既有几何/编译门和路由登记另按冻结收据记录。产品没有新增逐帧工作；本片未做性能测量。隔离HOME、真实包副本与重复截图已清理，约27MiB必要证据留上述根目录；正式提取仍被既有1GiB总预算拒绝，未提高预算或删除未知证据。仅保留`scene-constructor-runtime-20261011/DerivedData`连续构建缓存。既有218B `.mimosa`未知归属保留，residue门仍有finding，不能记PASS。
