# 聚映完整回归报告（2026-08-26）

## 1. 回归范围

本轮依据以下文档核对实现、测试、构建和运行结果：

- `docs/PROJECT_AUDIT_ACTION_PLAN.md`
- `docs/SPRINT1_ACTION_PLAN.md`
- `docs/FEATURE_ROADMAP.md`
- `docs/RESILIENCE_ROADMAP.md`

主验证宿主为 Windows 11，补充执行 Android APK 构建、Android TV 模拟器和 Android 14 实机冒烟。

## 2. 本轮修复

### TVBox Spider 专用适配器被通用 XBPQ 抢占

- 现象：强制真实源测试中，`xhztv -> csp_Bili` 分类可加载但媒体列表为空。
- 根因：`XbpqDartSpiderAdapter.supports()` 将所有 `csp_*` 都视为 XBPQ，并且分发顺序早于 Bilibili/AppYs 专用适配器。
- 修复：通用 XBPQ 兜底显式排除 Bilibili 和 AppYs 协议身份，避免错误路由。
- 测试：新增 Bilibili/AppYs 不被 XBPQ 捕获的回归断言；在线 Bilibili 测试在前 10 条真实搜索结果中寻找首个可播放项目，规避上游首条内容删除、地区限制或登录限制造成的脆弱断言，但仍要求直链首包读取成功。

### 安全、生命周期与 TV 包装

- WebDAV 凭据迁移至平台安全存储，完整写入后才清除旧版明文值。
- 注册 `PlatformDispatcher.instance.onError`；播放页和应用级生命周期完成暂停、进度保存与资源释放闭环。
- 局域网门户使用真实二维码携带 6 位配对码；Android TV 增加各密度 `android:banner` 资源。

### WebDAV v1 双向同步

- 远端拆分为 history、favorites、subscriptions、settings 四个 Gzip 文件。
- 实现实体规范化、墓碑、历史进度优先、收藏/设置字段级 LWW、ETag 条件 MOVE 和临时文件原子写入。
- 应用启动后台拉取，播放历史写入后 3 秒防抖同步；设置页提供统一“立即同步”。

### 离线 HLS 下载

- 支持主清单最高带宽变体选择、AES-128 密钥/IV 解析与在线解密。
- worker 数提升到 8，保留三次重试和完整性门；暂停后可复用非空分片继续下载。

## 3. 自动化结果

| 检查项 | 结果 | 说明 |
| --- | --- | --- |
| `dart format --output=none --set-exit-if-changed lib test integration_test` | 通过 | 102 个文件，0 个需修改 |
| `flutter analyze` | 通过 | 0 issue |
| `flutter test --reporter expanded` | 通过 | 115 passed，6 skipped |
| Windows 集成测试 | 通过 | 设置页、LAN 门户开关、配对码和二维码交互 1/1 |
| TVBox 强制真实源测试 | 通过 | 3/3；Bilibili、4K MacCMS、DC 多仓 T4 均完成真实播放首包探测 |
| Windows Debug 构建 | 通过 | 生成 `build/windows/x64/runner/Debug/juying.exe` |
| Windows Release 构建 | 通过 | 生成 `build/windows/x64/runner/Release/juying.exe` |
| Android Debug APK | 通过 | 生成 `build/app/outputs/flutter-apk/app-debug.apk` |
| Android Release APK | 通过 | 103.0 MB，生成 `build/app/outputs/flutter-apk/app-release.apk` |

默认全量测试中的 6 个跳过项：

- 3 个 QuickJS FFI 用例：无头 Flutter Test 环境未加载原生 QuickJS 动态库。
- 3 个真实 TVBox 源用例：默认通过 `TVBOX_LIVE_TEST` 开关隔离；本轮已另行显式开启并全部通过。

真实多仓导入过程中，三个第三方订阅地址返回 HTTP 502，聚合器按容错设计跳过失效源，最终有效 T4 链路仍通过。该现象属于上游源健康度告警，不影响本次链路结论。

## 4. Windows 运行冒烟

- Release 程序冷启动后持续存活，工作集约 311 MB。
- 本地 Range 代理仅监听 `127.0.0.1:9978`。
- 无效代理 Token 请求返回 HTTP 404。
- 未开启远程配置时，LAN 门户端口 `9979` 不监听。
- 配对码的缺失、错误、过期和有效 Bearer Token 路径由 `local_proxy_server_test.dart` 覆盖。

结论：Windows 构建、启动、默认网络暴露边界及设置页远程门户二维码交互均通过。

## 5. Android / Android TV 冒烟

- Android 16 TV x86_64 模拟器：Debug APK 覆盖安装成功，冷启动成功，Activity 保持前台。
- TV 语义树存在可聚焦、可点击和可滚动节点；发送方向键后焦点从一个分类移动到另一个分类。
- 模拟器日志未发现应用 `FATAL EXCEPTION`、SIGSEGV、SIGABRT 或 Flutter error。
- Android 14 实机：保留数据覆盖安装成功，冷启动成功，Activity 保持前台，未发现应用崩溃日志。

## 6. 文档目标差距

以下项目不能标记为完成，需进入后续迭代：

1. 离线下载仍缺磁盘空间预检、任务状态持久化和 FFmpeg `-c copy` MP4 重封装；当前产物明确保持 `.ts`。
2. 主题 Token 全量替换、Riverpod Service 注入和完整 i18n 尚未完成。
3. Android Release 当前仍使用 debug signing，不可作为商店生产包；生产签名需要发布方提供密钥策略与机密。
4. 播放故障恢复、全页面 TV 焦点和完整真实播放流程仍需扩展端到端覆盖。

## 7. 工具链风险

- Android 构建在当前 Windows 受限子进程环境中需要将 `TEMP`/`TMP` 指向短路径 `C:\jtmp`，否则 Gradle 本地回环连接初始化失败。
- `flutter_js` 仍自行应用 Kotlin Gradle Plugin；Flutter 已提示未来版本将不再接受，需要迁移到 Built-in Kotlin 或替换插件。
- Android SDK 命令行工具只能理解 XML v3，但当前 SDK 元数据包含 v4，应升级 command-line tools 并保持 Android Studio/SDK 工具版本一致。
- 依赖检查发现 8 个受约束的新版本；其中 `dart_smb2` 可从 0.1.1 升级到 0.1.2，建议另开兼容性回归处理，不在本轮无差别升级。

## 8. 结论

当前代码在格式、静态分析、115 项单测、Windows 桌面集成冒烟、Release 构建、真实源链路、Android 构建及既有 TV/实机冒烟范围内通过。安全与稳定性 P0、WebDAV v1 同步主链路已收口；后续重点是离线 MP4 重封装/持久化、DI/主题/i18n 治理以及更完整的真实播放 E2E。
