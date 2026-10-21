# juying_source_providers

源提供者统一契约与适配器包（遵循 Section 5.2 规范）。

## 核心职责 (What)
- 定义 `SourceProvider`、`SourceCapability` 与 `SourceConfig` 核心契约。
- 规范直播源（M3U/TXT）、CMS 站点、TVBox 爬虫及 NAS/WebDAV 的统一接入行为。
- 支持平台不支持能力的感知声明（由界面统一置灰处理，ADR-008）。

## 设计动机 (Why)
一种源一个实现，对上层界面隐藏协议细节，所有网络访问统一走受控 HttpClient。
