# ADR-008: TVBox 兼容层：CMS/JS 沙箱优先，Jar 类爬虫采用 Dart 纯语言重新移植 (Ports)

## 状态
已更新 (Updated) - 明确 Jar 类爬虫移植路线与 Ports 架构 (v0.2)

## 日期
2026-10-20

## 背景与上下文
TVBox 站源生态包含了多种不同运行时协议：
1. **CMS 接口**：标准 XML / JSON 接口，遵循标准 HTTP 规范，全平台原生解析。
2. **JS 类爬虫（drpy 系列）**：基于 JavaScript，通过轻量级 QuickJS 沙箱跨平台隔离执行。
3. **Jar 类爬虫**：本质上为 Android Dalvik/ART 编译的 DEX 字节码。Dart 运行时无法直接执行 Java/DEX 字节码。用户期望在 Windows 和 Android 上获得一致的体验。

## 决策
1. **统一跨平台实现**：
   - CMS 接口与 QuickJS 宿主沙箱由纯 Dart / C-FFI 跨端原生支持。
2. **Jar 爬虫重构策略（Dart 移植路线）**：
   - 严禁在非 Android 平台强行引入庞大重型的 JVM 运行时。
   - 对核心高频使用的 Jar 站点，采用 **Dart 纯语言重新实现（Ports）**：逐个分析其抓取逻辑（HTTP 请求、HTML/JSON 提取、AES 加密解密、播放地址解析），将其移植为 Dart provider，沉淀在 `packages/source_providers/lib/tvbox/ports/`。
   - 提取共用解析规则，沉淀为通用 Dart 规则引擎。
3. **Android DEX 原生兜底（可选且默认关闭）**：
   - Android 平台保留通过 ClassLoader 原生加载 DEX 的兜底能力，但**默认处于关闭状态**；用户若需开启，必须在设置中显式确认安全警示。
4. **能力矩阵与置灰提示**：
   - 在导入多仓或配置时，对当前平台未移植且不可用的站点在 UI 列表上显式置灰，并写明“暂未移植该类型站源”的原因，严禁静默失败。

## 原因分析与权衡
1. **跨平台确定性**：
   - Dart 移植版代码可在 Windows、Android、以及未来潜在平台上 100% 运行，具备可调试性、单测覆盖率与内存确定性。
2. **安全性与合规**：
   - 避免直接执行不受信任的外部二进制 DEX 字节码，降低内存溢出和恶意网络行为风险。
3. **工程维护性**：
   - 每个移植的站点独立配单元测试和离线固件，站点改版时仅需维护对应的 Dart 脚本规则。

## 何时重审
如果 TVBox 社区出现事实上的跨语言字节码标准（如 WebAssembly），可评估迁移至统一 Wasm 沙箱。
