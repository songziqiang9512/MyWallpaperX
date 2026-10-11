# 动态图层顺序同步（2026-10-12）

> **历史证据 — 非现役入口**。能力归[SceneScript API](../capabilities/scenescript-api-coverage.md)，后继归[断点队列 N06](../roadmap/scene-open-breakpoint-queue.md)。

## 通用语义与实现

排序是共同场景的操作顺序，不能被同回调后续属性写入覆盖，也不能由早先回调的绝对位置重新推算。基线b81bd703的真实VM→typed反例确认三类断链：sort后alpha使C为[B,A,C]而Swift仍[A,B,C]；连续插入使C为[Y,A,B,X,C]而Swift为[Y,A,X,B,C]；已有动态X仅改alpha后另一owner排序，使C为[C,A,X,B]而Swift为[C,X,A,B]。

修复复用原C topology baseline/journal的同一重放实现，纯投影只保留已接纳owner的pending操作及原committed操作，保留全domain实际调用顺序。原evaluation/owner-effects独立传递拓扑身份，合法属性裁剪不会丢掉排序；原DynamicLayerRuntime验证资源和属性后消费投影，再沿原退休阶段移除tombstone。旧Swift绝对index重排完全删除，不留测试专用备用算法。没有topology请求的普通帧保持当前order；缺失或不一致身份拒绝相应候选，不用旧排序救场。正常有效移动的成功出口返回官方已证Boolean `true`，使作者的条件分支继续执行；same-index早返回与非法输入行为未扩域。设计见[D4](../roadmap/batch2/script-component-api-design.md)。

无新增路径/hash/固定源码形状视觉规则。资源发现仍有上批登记的限制，本片不扩大create资源、特殊clone或模型支持。

## 官方与真实画面

固定官方2.8.0.42的公开API与自有普通色块黑盒确认：新X移到调用前C索引，两次有效移动均返回`true`，后续alpha不改变排序；下一callback插入Y到A前，过滤独立文本driver后为[Y,A,B,X,C]，重叠像素与读回一致。只证明有效新层向前移动的正常路径；异常、越界、已有层向后移动等未作官方扩域。未读取私有实现。

同一原生Debug输入、预登记重叠ROI，在首帧及后续帧均由错误的(128,128,0)恢复为预期红(255,0,0)，连续插入的(0,255,0)恢复为预期黄(255,255,0)。最终返回值探针还由`sortLayer(...) === true`控制alpha及第二次合法排序：首/后帧重叠区34800像素均红，独立区13050像素均(0,128,0)，实际走入成功分支。这些是实际Metal/窗口输出，不是profile或顺序数组断言。自有探针第一次loose输入停在资源缓存准备且无截图；修正为原有PKG输入后才取得上述证据，exit0未被当作启动成功。

未参与本批实现选型或调参的3792817546原包，人物/时钟与有色频谱仍实际可见，63个动态层、无VM错误。2887542690的隔离shadow触发副本仍有大面积黑色遮挡及6个特殊clone null错误，29个owner与28个动态候选进入；排序修复不能记作其阴影或整样本修复。副本只改作者现有静态shadow选项，不冒充默认输入或产品属性UI操作。

## 验证与边界

Debug构建、签名校验和15项结构门通过。最终源与二进制绑定10个产品文件，五次native运行均ready、exit0、GPU drain完成。28项排序VM/事务反例通过，覆盖改名、等价表达式、相邻属性-only、late rejection、throw、tombstone、301操作及返回值分支；其余最近消费者门的最终范围由本批验证收据记录；构建及direct Host不证明普通App→daemon入口、性能、发布或全样本正确率。

本机证据在`.artifacts/tmp/dynamic-layer-order-20261012/`：`implementation-source-freeze.json`、`product-build-identity.json`、`vm-before-tests.log`、`pixel-comparison.json`、`native-results.json`、`return-control-pixels.json`及`official/neutral-contract.json`。官方输入与输出经独立研究后由`official-handoff-review.json`批准，raw私有实现未进入实现上下文；正式收尾身份以`full-owned-freeze.json`及提交后收据为准。

排序首断点关闭范围不覆盖静态autosize、特殊clone、text wrapper及间接资源发现。后继优先统一现有静态尺寸消费者与已准备自然尺寸合同，再按真实样本首错推进，不把未解黑遮挡直接归因于任一剩余项。

本轮运行HOME与shader转储已清理；正式证据提取因既有总预算达到上限而拒绝，未提高预算或删除未知证据，保留本机最小日志/截图/身份。连续开发仅保留`scene-constructor-runtime-20261011/DerivedData`一份构建缓存。
