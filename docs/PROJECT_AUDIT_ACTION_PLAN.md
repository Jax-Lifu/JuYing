# 聚映 (JuYing) 项目审计 — 完整实施计划

> 审计日期：2026-08-26 | 审计范围：全部 `lib/`、`test/`、平台配置、依赖、架构约束合规性

---

## 🏗️ 总体评估

| 维度 | 评分 | 关键发现 |
|------|------|---------|
| **架构设计** | ⭐⭐⭐⭐ | Feature-First + Clean Architecture 方向正确，领域模型解耦做得好 |
| **功能真实性** | ⭐⭐ | CCTV/NAS/IPTV 有真实实现；云盘/元数据/TVBox 非 CCTV 源为 mock |
| **安全性** | ⭐ | 代理服务 0.0.0.0 无鉴权暴露、WebDAV 凭据未独立安全存储 |
| **可靠性** | ⭐⭐ | 无全局错误处理、无应用生命周期管理、无资源泄漏防护 |
| **测试覆盖** | ⭐⭐ | 有 23 个测试文件但大量验证 mock 行为，缺少集成/端到端测试 |
| **跨平台就绪** | ⭐⭐ | Android TV manifest 基本可用但缺 banner icon，其他平台未验证 |
| **代码规范** | ⭐⭐⭐ | 注释质量好，但 16 个文件硬编码颜色、lint 配置过松、CRLF 混用 |

---

## 阶段 0：紧急安全与稳定性修复 (1-2 天)

> [!CAUTION]
> 这些问题在当前状态下会导致安全漏洞或用户可见的数据损坏，必须最先处理。

### 0.1 代理服务安全拆分与鉴权

- [x] **拆分 `LocalProxyServer` 为两个独立服务**：
  - `LoopbackStreamProxy`：仅绑定 `127.0.0.1:9978`，处理 `/proxy/<token>` Range 流
  - `LanGatewayServer`：绑定 `0.0.0.0:9979`（或同端口但可控开关），处理远程门户和 Push API
- [x] **实现 4-6 位配对码鉴权**：
  - TV 屏幕显示配对码 + 二维码
  - 手机端输入配对码后获取 30 分钟会话 Token
  - 所有 `/api/push_*` 路由验证 `Authorization: Bearer <token>`
- [x] **Stream proxy token 防枚举**：使用 UUID v4 而非可预测 token

> 相关文件：[local_proxy_server.dart](file:///G:/workspace/JuYing/lib/core/proxy/local_proxy_server.dart)

### 0.2 全局错误处理

- [x] **包装 `main()` 为 `runZonedGuarded`**：
  ```dart
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (details) => _reportError(details.exception, details.stack);
    // ... 现有初始化
  }, (error, stack) => _reportError(error, stack));
  ```
- [x] **添加 `ErrorWidget.builder` 替代红屏**：在 TV 上显示可遥控器操作的错误恢复 UI
- [x] **本地日志文件轮转**：写入 `applicationSupportDir/logs/`，保留最近 7 天

> 相关文件：[main.dart](file:///G:/workspace/JuYing/lib/main.dart)

### 0.3 应用生命周期管理

- [x] **添加 `WidgetsBindingObserver`**：
  - `paused` → 保存播放进度、暂停下载任务
  - `resumed` → 恢复下载、刷新网络状态
  - `detached` → `ProxyServer.stop()`、`PlayerEngine.dispose()`
- [ ] **关闭所有 `StreamController.broadcast()`**：在 `dispose()` 中显式调用 `.close()`
- [x] **ProxyServer 绑定 App 生命周期**：热重启时检测端口占用并优雅重启

---

## 阶段 1：去除伪完成状态 (2-3 天)

> [!WARNING]
> mock 数据进入生产 UI 会误导用户和团队对项目进度的判断。

### 1.1 TVBox mock 源隔离

- [ ] 创建显式 `DemoSpiderAdapter`，所有非 CCTV 的 mock 数据迁移至此
- [ ] 生产路径无真实 runtime 时返回 `SpiderNotAvailableError`
- [ ] UI 中 demo 源卡片添加 `🎭 演示` 标签，禁止进入播放流程
- [ ] 添加守卫测试：`expect(() => engine.loadCategory(demoSite), throwsSpiderNotAvailable)`

### 1.2 云盘模拟清理

- [x] 移除 `drive.stream.example.com` 假直链（[cloud_drive_service.dart L105](file:///G:/workspace/JuYing/lib/features/cloud_drive/services/cloud_drive_service.dart#L105)）
- [x] 移除时间戳拼接 Token 刷新（[L119](file:///G:/workspace/JuYing/lib/features/cloud_drive/services/cloud_drive_service.dart#L119)）
- [x] 保留 `CloudDriveToken` + `saveToken/readToken` 作为基础设施
- [x] 未接入的供应商返回 `CloudDriveNotConfiguredError`

### 1.3 元数据模拟清理

- [x] `MediaMetadataService` 未接入真实 API 时返回 `MetadataUnavailableResult`
- [ ] 详情页优雅降级：无元数据时仅显示爬虫返回的标题/封面

### 1.4 离线下载安全门

- [x] 未完成全部分片时禁止标记 `completed`
- [x] 添加分片完整性校验（检查所有 seg_*.ts 文件存在且非 0 字节）
- [x] TS 拼接文件临时命名为 `.ts.tmp`，不伪装为 `.mp4`

---

## 阶段 2：核心工程基础加固 (3-5 天)

### 2.1 DI 统一（Singleton → Riverpod Provider）

- [ ] `LocalProxyServer.instance` → `localProxyServerProvider`
- [ ] `OfflineDownloadManager.instance` → `offlineDownloadProvider`
- [ ] `I18nService.instance` → `i18nServiceProvider`
- [ ] 所有 Service 支持构造器注入 `Dio`/`Storage` 以实现可测试性

### 2.2 主题 Token 全量化

- [ ] 审计 16 个文件中的 `Colors.*` 引用，建立替换清单
- [ ] 扩展 `AppThemeColors` 添加缺失的语义 Token（如 `playerOsdBackground`、`danmakuTextColor` 等）
- [ ] 批量替换所有硬编码颜色
- [ ] 添加自定义 lint 规则或 `analysis_options.yaml` 注释标记禁止 `Colors.*`

### 2.3 静态分析加固

- [x] `analysis_options.yaml` 从 CRLF → LF
- [ ] 开启：
  ```yaml
  analyzer:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
  linter:
    rules:
      avoid_print: true
      prefer_const_constructors: true
      always_use_package_imports: true
      sort_constructors_first: true
      unawaited_futures: true
      cancel_subscriptions: true
  ```
- [x] 修复开启后的所有 lint 警告（Dart 3.13 已移除 `strict-raw-types` 配置，启用当前支持的 strict casts/inference）

### 2.4 依赖清理

- [x] 移除 `http` 包，统一使用 `dio`
- [ ] 调研 `flutter_js` 替代方案（`flutter_qjs`、自建 QuickJS FFI）
- [x] `punycoder` 改为 `^0.3.0`（允许补丁升级）
- [ ] 评估 `dart_smb2` SMBv3 支持和维护状态，记录替代方案
- [ ] 理清 `webview_windows` vs `webview_flutter` 的平台边界

---

## 阶段 3：播放器可靠性强化 (2-3 天)

### 3.1 硬解回退错误分类

- [x] 区分错误类型：
  - **网络错误**（403/DNS/超时）→ 不触发硬解回退，走熔断换源
  - **解码错误**（纹理失败/codec 不支持）→ 触发硬解回退
  - **清单错误**（M3U8 解析失败）→ 报告错误，不回退
- [x] 硬解回退时保留当前 `position`，回退后自动 `seek` 恢复
- [x] `_isHardwareDecodingFailed` 在切换新媒体时重置
- [x] 替换 `as dynamic` 为类型安全的 platform API 调用

### 3.2 watchdog 增强

- [ ] 添加纹理创建监测（frame drop rate）作为硬解健康指标
- [ ] 熔断后自动尝试回退到上一个已知可用线路

> 相关文件：[player_engine.dart](file:///G:/workspace/JuYing/lib/core/player/player_engine.dart)

---

## 阶段 4：补齐核心闭环链路 (按优先级)

### 4.1 离线下载完整流水线 (P0)

- [x] 解析 `#EXT-X-STREAM-INF` 选择清晰度变体
- [x] 解析 `#EXT-X-KEY` 获取 AES-128 密钥
- [x] 分片下载失败重试 3 次
- [ ] 磁盘空间预检查
- [x] AES-128 解密
- [ ] FFmpeg `-c copy` 重封装为标准 MP4
- [ ] 任务状态持久化（SQLite/JSON 文件）
- [x] 断点续传支持（复用已落盘且非空的分片）

### 4.2 WebDAV 同步重构 (P0)

- [x] 分文件存储：`/JuYing/sync/v1/{history,favorites,subscriptions,settings}.json.gz`
- [x] 每个实体添加 `entityId` + `updatedAt` + `isDeleted`
- [x] favorites 字段级 LWW 合并（非整体覆盖）
- [x] settings 字段级 LWW 合并
- [x] 删除墓碑（tombstone）支持
- [x] ETag 并发保护
- [x] 临时文件 + MOVE 原子写入
- [x] WebDAV 凭据迁移到 `flutter_secure_storage`
- [x] 启动/播放退出自动触发同步

### 4.3 IPTV 补齐 (P1)

- [ ] TVBox `lives` JSON 格式解析
- [ ] XMLTV EPG 解析 + 频道模糊匹配
- [ ] 回看 URL 动态插值
- [ ] 线路吞吐采样（最后两个分片首包 + 带宽）
- [ ] 完整错误熔断计数器

### 4.4 TVBox QuickJS 运行时 (P1)

- [ ] QuickJS 隔离执行器（内存限制 + 超时）
- [ ] CatVod 完整方法契约：`homeContent` / `categoryContent` / `detailContent` / `searchContent` / `playerContent`
- [ ] Candidate 聚合与去重

---

## 阶段 5：平台配置与 TV 体验 (2-3 天)

### 5.1 Android TV 完善

- [x] 添加 `android:banner` TV banner icon
- [ ] 添加存储权限（离线下载）
- [ ] 全页面 TV Focus 审计：
  - 搜索页虚拟键盘 D-Pad 操作
  - 设置页 Switch/Dropdown 遥控器操作
  - 详情页选集矩阵焦点缩放
  - 对话框/Toast/BottomSheet 遥控器关闭
- [ ] Android TV 模拟器或实机全流程验证

### 5.2 其他平台保可编译

- [ ] iOS: 检查 `Info.plist` 网络权限、应用名称和图标
- [ ] macOS: 检查 `Entitlements` 网络权限
- [ ] Linux: 检查窗口配置

### 5.3 Windows 窗口配置

- [x] 最小窗口尺寸限制
- [x] 应用图标和标题配置
- [ ] 窗口状态记忆（位置/尺寸）

---

## 阶段 6：仓库卫生 (1 天)

### 6.1 analysis/ 拆分

- [ ] 创建独立参考仓库（或 `.gitignore` + 本地目录）
- [ ] 从主仓移除所有 APK、反编译文件、第三方源码副本
- [ ] 用 BFG Repo-Cleaner 清理 Git 历史中的大文件
- [ ] 主仓仅保留 `analysis/README.md` 含原始参考链接和许可证说明

### 6.2 i18n 全量化

- [ ] 审计所有页面中的硬编码中文字符串
- [ ] 迁移到 i18n 字典
- [ ] 添加缺失语言的翻译文件

---

## 阶段 7：扩展能力 (后续迭代)

| 子系统 | 优先级 | 备注 |
|--------|--------|------|
| 云盘逐供应商接入 | P1 | 先阿里 → 夸克 → 115 → 百度 |
| DLNA DMC 完整控制面 | P1 | Pause/Stop/Seek/Volume/GetPositionInfo |
| DLNA DMR 接收端 | P2 | Windows/Android TV |
| 元数据 TMDB provider | P1 | L1/L2 缓存 + generation guard |
| WebView 嗅探引擎 | P2 | 高风险，12s 硬超时 + 验证码升级 |

---

## 📊 验收门槛 (DoD)

每个子系统从"规划能力"升级为"已实现能力"必须同时满足：

1. ✅ 不使用固定业务结果、示例域名或延时模拟
2. ✅ 真实协议的成功、超时、鉴权失效、取消、资源释放均有测试
3. ✅ UI 调用真实服务，并能展示失败原因与恢复动作
4. ✅ `dart format --output=none --set-exit-if-changed lib test` 通过
5. ✅ `flutter analyze` 零警告
6. ✅ `flutter test` 全部通过
7. ✅ Windows 主力平台实际运行验证
8. ✅ Android/Android TV 可编译并完成核心链路冒烟测试

---

> [!IMPORTANT]
> **建议执行顺序**：阶段 0 → 1 → 2 → 3 → 4.1/4.2 → 5 → 6 → 4.3/4.4 → 7
>
> 阶段 0-2 是**基础设施和安全卫生**，不直接增加功能但决定项目的可靠性天花板。
> 阶段 3-4 是**功能真实性**，将 mock 变为真实能力。
> 阶段 5-7 是**体验与扩展**，在基础稳固后推进。
