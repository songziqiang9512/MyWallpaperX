<!-- document-role: historical-evidence -->

# JPEG 显示方向与自然尺寸（2026-10-15）

> **历史证据 — 非现役入口**。通用语义归[资源准入](../architecture/scene-resource-admission.md#jpeg-display-layout)，后继归[属性卡](../roadmap/properties-panel-card.md)。本批修正已支持JPEG的EXIF方向及尺寸一致性，不扩文件格式，不计CPU/GPU/内存或能耗收益。

旧direct-property loader成功发布了EXIF6的48×32原始像素；作者应见的32×48显示尺寸和旋转均未应用，embedded入口则已有方向处理。受控RED实际经过资源loader、双purpose与candidate：尺寸48×32、四角未旋转，publication完整，证明问题在解码与header语义而非准入。证据根 `.artifacts/tmp/direct-jpeg-orientation-qualification-20261015/`，RED的输入/输出/收据保留。

## 唯一链与最近门

SceneImageTextureUploader拥有共享JPEG layout及解码；URL/Data header只取metadata，5–8交换显示轴，非identity复用既有ImageIO transform并核输出extent，identity保原路径。SceneTextureMipUploader委托此owner，保原embedded输入识别与原始Int二维上限；没有先读header再重复解析decode。SourceKey、purpose、代次、资源事务和发布/失败保旧链不变，PNG专用通道与encoded-preserved非identity拒绝保留；缓存选项未混入改动。

原Python内完整Swift harness移到一份fixture，保单次编译/原20产品源，不分裂测试owner；两uploader与fixture均登记到现有user-texture最近门。最终20tests PASS（7.014s），24输入前后SHA一致。真实Metal readback验证缺省/1–8、资源及属性改名、direct双purpose、natural/header/embedded尺寸及四角、损坏header、PNG hidden RGB/alpha与strict反例。产品aggregate `3cb8481000b39eff8d466728c954ef59e0151c52e885a20cbf4603d79603a0cc`，五路径 `522cc8494d47e741101dbeb91c98160447bd1014598110855aeff767616d4091`。

首次执行在fixture资格guard失败后SIGTRAP，0断言运行；实际ImageIO将自造EXIF9规范化为1，不能声称产品拒绝了原9。坏输入已改为ImageIO确认无header的截断APP1，只重跑受影响同门；原失败/字节/metadata保留。独审核产品、fixture增量、gate可达性与最终收据，无重复测试。

Debug build23.7595s、4298输入无漂移；同一次App同时带默认关闭的临时world CPU诊断，exe SHA `c8f4757f1a1d9746feccc530bd4dcc909bf19b0cf6d57133124b91cf01c967d0`，完整插桩源码另存忽略区。以下原生操作WORLD环境关闭；这份诊断Debug binary不等于插桩撤回后的源码树，也不代表优化Release。

## 真实面板与画面

普通原生入口、隔离Workshop/HOME/defaults，无内部资源更新CLI。2938612768选择Local files后实际选EXIF6，再换identity1；背景四角分别蓝红/黄绿、红绿/蓝黄，前景唱片和粒子保留。关闭重开保identity1，逐资源reset保Local模式、清resource override/bookmark并恢复黑底，最终全reset清持久项。全程同session `637701C0…`，没有新增Scene启动。

未参与修法的2067939514在既有Custom Background入口选同EXIF6，显示正确四角及中央黑圆/Windows/粒子；重开保值，逐key reset实际恢复山景，resource override/bookmark清除。仍同session `5C30E8E0…`。root独立查看两样本的实际改后/reset原图；没有以label、publication或非黑代替画面，native全屏fill不单独证明自然像素尺寸。

两样本均Stop/正常Quit退出0、精确App/daemon PID消失，各仅一次launch/firstFrame/activated；critical资源及原/副本输入无变化，最终属性持久态均空。首次CUA按常用名错误另开/Applications实例，尚未编辑前已按其精确PID关闭并排除；候选保持原session，后续按冻结bundle路径控制。详见本批 `native/native-acceptance.json`。

## 边界与产物

普通入口未导出VM逐域quiescent/pin终值，不以进程退出代替全owner账本；原取消/坏图失败保旧沿现有门，不重跑无变化矩阵。ICC/HDR、其他格式、多screen及全reset部分失败未扩，原293右侧时钟裁切与其他视觉问题仍开放。原SourceMaterials→RuntimeCatalog依赖门失败未改、不扩baseline。

保留输入/源码冻结、首试失败、最终聚焦/构建/独审及native原始收据；六张必要Scene图共13181079 B。进程退出且lsof无句柄后，两隔离runtime已清220172670 logical B；保当前App、唯一DerivedData及后继CPU/内存归因需要的共享缓存，不称磁盘逻辑清理量为RAM收益。
