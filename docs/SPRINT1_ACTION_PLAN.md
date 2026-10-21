# 聚映 (JuYing) Sprint 1：底座安全治理与 Mock 隔离实施任务单

> **执行基线**：本项目工程约束 (`AGENTS.md`)、`PROJECT_AUDIT_ACTION_PLAN.md` 阶段 0 与阶段 1。  
> **质量原则**：每个原子任务配套单元测试，完成即执行 `dart format` 与 `flutter test`，严禁产生构建坏死。

---

## 📋 任务分解与执行清单

### 任务 1：代理服务安全分层与动态配对鉴权 (P0 - 安全)
- [x] **目标文件**：`lib/core/proxy/local_proxy_server.dart`，`lib/features/settings/presentation/settings_page.dart`
- [x] **实施内容**：
  1. 将内部媒体 Range 代理严格限制绑定在 `127.0.0.1:9978`，杜绝局域网未授权读取媒体流。
  2. 独立 LAN Gateway 门户服务（或可控开关），绑定 `0.0.0.0:9979`。
  3. 引入 6 位动态随机配对码 + 30 分钟有效期会话 Token。
  4. 门户首页与 API（`/api/push_config`, `/api/push_stream`）增加 Bearer Token 验证拦截器。
  5. TV 设置页右侧面板生成包含 `http://{IP}:9979?token={token}` 的动态二维码与当前配对码。
- [x] **测试保障**：`test/local_proxy_server_test.dart` 已覆盖无 Token、错误 Token、过期 Token 与有效 Token。

---

### 任务 2：全局异常捕获与应用生命周期管理 (P0 - 稳定性)
- [x] **目标文件**：`lib/main.dart`
- [x] **实施内容**：
  1. 使用 `runZonedGuarded` 包裹 `main()` 入口，捕获所有未受检异步异常。
  2. 注册 `FlutterError.onError` 与 `PlatformDispatcher.instance.onError`，杜绝红色崩溃屏，在 UI 上提供友好的遥控器可操作恢复提示。
  3. 接入 `WidgetsBindingObserver`，在 `AppLifecycleState.paused` 时保存当前播放进度并暂停下载，在 `resumed` 时恢复状态，在 `detached` 时优雅释放 Proxy 与 Player 资源。
- [x] **测试保障**：生命周期 Widget 测试与 Windows 集成冒烟均通过。

---

### 任务 3：隔离 Mock 数据，建立真实诊断与优雅降级机制 (P0 - 功能真实性)
- [ ] **目标文件**：
  - `lib/features/cloud_drive/services/cloud_drive_service.dart`
  - `lib/features/metadata/services/media_metadata_service.dart`
  - `lib/features/tvbox/services/tvbox_spider_engine.dart`
  - `lib/features/home/presentation/home_page.dart`
  - `lib/features/detail/presentation/video_detail_page.dart`
- [ ] **实施内容**：
  1. 移除 `cloud_drive_service.dart` 中的 `drive.stream.example.com` 假直链与假刷新，未配置 Token 时返回 `CloudDriveNotConfiguredException`，UI 引导去设置页配置。
  2. `tvbox_spider_engine.dart` 移除为所有非 CCTV 站点生成假 CCTV GUID 的逻辑；无真实运行时支持的站源明确标记并在 UI 显示“⚠️ 待沙箱适配”。
  3. 详情页与首页增加优雅无数据与可诊断提示，禁止假数据混入生产环境。
- [ ] **测试保障**：更新 `test/tvbox_spider_test.dart` 等用例，添加针对未支持站源返回明确异常与安全降级的断言。

---

## 🏁 验收标准 (Definition of Done)
1. `dart format --output=none --set-exit-if-changed lib test` 100% 通过无格式变动。
2. `flutter analyze` 保持 0 警告 0 错误。
3. `flutter test` 所有单元测试与安全测试全部 Green 通过。
4. Windows 端本地启动正常，远程配置页面需输入配对码或扫码方可推送数据。
