# TVBox Jar 站点 Dart 移植库 (tvbox/ports)

> 架构依据：[ADR-008](../../../../docs/adr/ADR-008-tvbox-cms-js-first.md) 与 [《聚映项目指导文档 v0.2》第 5.9 节](../../../../docs/PROJECT_GUIDE.md#59-tvbox-兼容层)。

## 1. 架构定位
TVBox 生态中大量第三方站源基于 Android Dalvik/ART 编译为 DEX/JAR 爬虫。由于 Dart 无法直接执行 Java/DEX 字节码，且在 Windows/Linux 桌面端缺乏原生 Dalvik 运行时，聚映采用 **“纯 Dart 重新实现（逐站点移植）”** 路线：
1. 分析目标 Jar 站点的抓取逻辑（HTTP 请求、HTML/JSON 解析、加解密逻辑）；
2. 用纯 Dart 重新实现为独立的 `PortedSpiderProvider`；
3. 共用的提取工具（XPath/CSS选择器/AES解密）沉淀为通用规则引擎。

## 2. 移植规范
每个移植的站点必须满足：
- 继承 `PortedSpiderProvider` 抽象接口；
- 配备对应的离线录制 JSON/HTML 固件（放置于 `test_fixtures/tvbox_configs/`）；
- 具备完整的单元测试，覆盖 `homeContent`、`categoryContent`、`detailContent`、`searchContent` 与 `playerContent`；
- 遵循内容解耦与合规红线（ADR-005），严禁内置任何受保护版权源。
