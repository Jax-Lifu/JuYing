# ADR-014: TVBox 跨端站源真实边界与 Android DEX 受控运行时策略

## 状态
已接受 (Accepted) - 2026-10-21 (具体化与落地 ADR-008)

## 背景与上下文
TVBox 社区多仓生态（如饭太硬、Jinenge、25175 等配置）中 70%~80% 为 Jar 爬虫（包含在 `spider.jar` 内的 Android DEX 字节码）。
在旧代码库中，由于 Windows 缺乏 Android ART 运行时，导致旧单体应用中塞入了大量伪造分类与假 GUID 播放数据的欺骗性实现，被审计报告严厉指出。
同时，在 Android 端，虽然已有基于 `DexClassLoader` 的原生执行能力（`TvBoxDexRuntime.kt`），但直接加载并执行未经验证的第三方二进制字节码存在安全与提权隐患。

## 决策
1. **彻底拔除伪数据与假映射**：
   - 彻底删除所有伪造分类与将第三方站源请求重定向至固定 CCTV GUID 的假逻辑。
2. **Windows 严格置灰阻断**：
   - 在 Windows 端，对所有未移植为纯 Dart 规则的 Jar 类站点在 UI 上显式置灰，标明“当前平台不支持 Jar 字节码爬虫，需等待 Dart 规则移植”，并禁止进入播放流程。
   - Windows 仅提供原生 CMS (XML/JSON)、官方 CCTV、以及纯 Dart 移植版站源（XBPQ 规则引擎、AppYsV2、兔小贝、B站等）。
3. **Android DEX 运行时受控启用**：
   - Android 平台保留 `TvBoxDexRuntime.kt`，但**默认处于关闭状态**。
   - 仅当用户在“设置 - 实验室 - 第三方 Dex 运行时”中主动勾选并同意安全免责声明后，方可激活并加载外部 `spider.jar`。
4. **架构下沉至 packages**：
   - 纯 Dart 爬虫规则（XBPQ、AppYsV2 等）全部抽离沉淀至 `packages/source_providers/lib/tvbox/ports/`，脱离主 UI 单体工程独立运行与单测。

## 权衡与后果
- **收益**：确立了代码的绝对真实性与开源合规性；Android 用户仍保留高阶兼容性，Windows 用户享受轻量无污染体验。
- **代价**：Windows 端导入外部多仓时，部分纯 Jar 站点将无法使用。
