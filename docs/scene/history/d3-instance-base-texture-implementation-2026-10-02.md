<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# D3 普通instance底图选择实施记录（2026-10-02）

> **历史证据 — 非现役入口**。目标、owner和失败合同由[D3设计的F2节](../roadmap/batch2/2d-lighting-material-design.md#f2-普通instance底图选择纠正独立设计审查已批准)拥有，后继由[实施路线](../roadmap/scene-compatibility-roadmap.md)及[RF10工作卡](../roadmap/batch2/reference-evidence-implementation-cards.md#rf10-pbr-direct)决定。本记录不把静态底图覆盖扩大为动态instance改写或PBR贴图支持。

## 真实反例与首断点

实施基线 `a32e814fece8c81f74d40058358699e49cec15c9`。前批标量材质的完整App运行后，进一步纠正了原normal实例测试覆盖前后同图的问题，见[前批补强记录](d3-pbr-scalar-implementation-2026-10-02.md#补强测试发现的普通实例底图漏接)。请求另一张灰64图片、slot1以null继承BC5 +X；独立运行前预期21.37979±2，忽略底图覆盖为36.48007、丢失normal为37.19426。实际ROI36.55、中心37，preview明确加载原灰128底图，健康邻层保留。该运行1 FAIL（15.392s），保留在 `/private/tmp/mwx-rf10-pbr/implementation/app-v3-instance.log`，不是源码模型推测。

反例使用已冻结的前批 `source-v2.app`，产品字节与本片基线相同；主执行文件SHA `c635a9fa805b2b4f7609b883f0b45a539d6eee299187bb9892ee1baf97291d4d`、debug dylib SHA `dbb4f86398c3f4b5576f33a83d864d542e3c862b2fb7fc5b7e913a0b7a047f1a`。强用例原样留在工作树承接本片，未修改旧失败像素或扩大容差。

Format已保留instance.textureSlots，descriptor未传递普通slot0；唯一SceneTexturePathResolver(for:layer)仅按model/material默认选源，设备准备与最终安装都因此选择同一张错误底图。normal由独立profile正确继承，因此该失败不归因于法线或PBR数值模型。修复责任属于准备期的图层来源投影与共享路径选择，不能在provider、frame draw或共享material表另加资产分派。

## 设计与实施范围

独立设计审查ACCEPT，记录在 `/private/tmp/mwx-f2-instance-base/design-review.md`，释放身份见 `design-release.json`。仅现有三产品文件增加一个可向后解码的optional图层路径、一次typed实例投影及resolver消费：SceneRenderDescriptor+Layer、SceneRenderDescriptorBuilder与SceneTexturePathResolver。准备/安装、cache、loader、候选与frame owner仍共用既有链。

非空静态slot0覆盖只在该图层生效；null/省略继承。合法userTextureInputs全nil仍属于静态输入，任何非nil typed声明留原provider准入，不能按字符串为空重解释。选中后缺文件/坏图/非法路径沿原VFS和base loader失败，不静默加载material默认。model-only解析与已发布dynamic来源的优先级保持原义；纹理metadata随选中来源，作者显式/model尺寸保留几何owner。没有新增持久descriptor恢复owner，现demand cache不拥有底图选择，故不为此盲目升cache版本。

## 验证记录

本片证据根 `/private/tmp/mwx-f2-instance-base/`。首轮CPU为5方法PASS（20.240s），经过真实SourceFacts→Document/Catalog→Descriptor→resolver，覆盖同model不同图层、静态槽继承、typed user输入边界、missing/escape、model-only、作者尺寸及旧descriptor解码。它证明实际准备选择，不能替代GPU/App显示。

最终冻结 `final-source-v1/manifest.json` SHA `ef2389f5c2b00270ec0ec9c264d903b52fb50c0eca3b8b6c39ffdc598273f2c8`：3产品、5测试及实际依赖镜像。App主程序SHA `45eb659138491670dd9847f54a0cc79a8ceb063f02350921f922ff0427c290be`、debug dylib SHA `8f3ffdd4ad34caf763f12aceebaa814312fedbbddef5b9ba060cad53a7b9258e`。运行从冻结测试镜像加载，测试期间未改模块；共享fixture与新断言各自SHA在 `app-v1-execution-source.json` 分列，不能只用fixture hash代表全部断言。

最终CPU冻结复跑5 PASS（20.997s），含15个真实layer输入及非nil空property；selected-v1另7 PASS（31.339s，含同批重复CPU和既有provider ready/stale/fallback/extent、VFS），adjacent-v1 21 PASS（60.232s）。不同运行不可简单加总当作独立用例数。Debug build、严格签名通过；code-health 0 errors/238既有warnings，防御面0 dead/18 helpers/3 swallows。设计门工具只检查blocked条目，approved条目被跳过；其“无设计前置命中”输出不应误称机器验证了设计内容，实际批准见独立设计记录。

实际App为5方法、7场景PASS（141.613s），日志 `app-v1.log`，像素与运行身份见 `app-v1-roi.json`、`app-v1-identity.json`：

| 可区分行为 | 实际ready/after结果 |
|---|---|
| 灰64实例覆盖、继承BC5 +X | ROI均21，原失败36.55，未放宽预期21.37979±2 |
| 选中动画帧继续前进 | ROI由21变45，normal仍继承 |
| 缺文件、坏文件两场景 | 中心均0，健康邻层各3721像素，未回用material底图 |
| 12×4来源与作者方形几何、同model无覆盖邻层 | 主层21、同model邻层39，来源尺寸不覆盖作者几何 |
| 非恒等effect、NORMALMAP=0两控制 | 分别11、37，证明新来源经过effect且normal开关仍有效 |

独立产品终审ACCEPT，核对4728冻结文件、8个live owned文件、3个App二进制、7次App/test及自写输入身份均匹配；记录见本机 `product-review.md`。此身份不声称完整App bundle hash。另normal GPU为1方法、19数值case PASS（11.438s，最大误差7.934e-5）；非App共29个不同选定方法通过，文档治理25 PASS（1.885s）。稳定架构接管后，本批退役F2窄登记，原批准状态及3路径匹配留在本机 `approved-gate-snapshot.json`。本片不以这些自有场景宣称官方视觉parity或性能改进。

## 证据上限与后继

provider邻接证明registry行为，不冒称新增dynamic-model实际App验收。本片不重新定义provider fallback、动态model资源、作者reset、运行时instance变更或新格式。所有普通帧仅消费准备结果，未新增解析、hash、registry或compositor。底图选择职责已交稳定架构并退役本片窄门禁，下一职责继续经独立审查的slot2输入及PBR贴图落地。
