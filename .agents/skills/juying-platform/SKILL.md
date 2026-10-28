---
name: juying-platform
description: 为聚映 (JuYing) Android 原生多源聚合播放器提供工程与开发指导。用于新增或修改数据源、扩展播放内核能力、优化 TV/平板/手机三端适配以及执行低配性能与稳定性回归。
---

# 聚映 (JuYing) 平台开发规范与技能指导

面向 **Android TV / 平板 / 手机** 的高性能全源聚合播放器，最低支持 Android 9 (`minSdk 28`)。
任何代码变更必须遵循 [AGENTS.md](../../../AGENTS.md) 的核心工程约束。

---

## 1. 核心工程底线

- **原生 View 体系**：采用 `Fragment` + `ViewBinding` + `RecyclerView`，**严禁引入 Jetpack Compose**。
- **单播放器与硬件直出**：视频渲染使用原生 `SurfaceView` 与 Media3，禁止默认 `TextureView`；全局最多持有一个 `PlayerEngine`，离开播放页面立即 `release()`。
- **低配设备优先**：
  - `Application.onCreate` 零 I/O、零网络与零数据库初始化；所有组件（Room、OkHttp、DataSource、Spider、Media3）均按需懒加载。
  - 性能策略由 `DeviceProfile.tier`（LOW / MID / HIGH）统一驱动，不在代码中写死易变阈值。
  - 播放进度仅在控制栏处于前台可见时以 1 秒低频轮询，**严禁将高频进度塞入全局 `StateFlow`**。

---

## 2. 模块边界与跳转

```text
app                 组装入口、NavGraph 与 AppNavigator 实现
feature:*           业务页面（只依赖 core:* 与 player:api）
core:model          纯 Kotlin 领域模型（无 Android 框架依赖）
core:data           Repository、SourceRegistry 与多重绑定
source:api          SourceProvider 及 Live/Vod/Browse/Searchable 能力接口
source:*            具体数据源实现（cctv, iptv, tvbox, smb, local）
player:api          播放器抽象与 PlaybackManager
player:media3       Media3 / ExoPlayer 具体实现
```

- **单向依赖铁律**：`feature:*` 之间禁止互相依赖，禁止直接依赖 `source:*` 具体实现或 `player:media3`。
- **全局路由**：页面间跳转与源选择必须统一通过 `core:ui` 的 `Navigator`，UI 层严禁拼接协议细节或构造播放内核实例。

---

## 3. 数据源扩展流程（标准 3 步）

1. **实现能力接口**：
   在 `source:<name>` 模块中根据需要实现组合接口：
   - 直播源：`LiveSource`
   - 点播源：`VodSource`
   - 存储/目录浏览：`BrowseSource`
   - 联邦搜索支持：`SearchableSource`
   - 动态局域网发现：`SourceDiscoveryProvider`

2. **Hilt 依赖注入**：
   在对应 source 模块声明注入绑定：
   ```kotlin
   @Module
   @InstallIn(SingletonComponent::class)
   abstract class MySourceModule {
       @Binds
       @IntoSet
       abstract fun bindSource(impl: MySourceProvider): SourceProvider
   }
   ```
   如需自定义协议 `DataSource`（例如 `nfs://`），通过 `@Binds @IntoMap @StringKey("nfs")` 绑定 `DataSource.Factory`。

3. **依赖挂载与装配**：
   在 `app/build.gradle.kts` 中添加：
   ```kotlin
   implementation(project(":source:<name>"))
   ```

---

## 4. 连续交互与切台优化规则

- **合并连续输入**：连续快速换台时，优先以待切频道为基准累计偏移，新输入立即取消上一次进行中的解析任务，最后一次输入生效。
- **旧解析隔离**：迟到的异步回调必须经由协程有效性校验，禁止已取消请求的结果覆盖当前播放。
- **局部刷新**：RecyclerView 列表项状态切换（如选中高亮）必须使用 `payload`，禁止全项重绘，避免重复触发台标或封面加载。

---

## 5. 三端形态与焦点系统

- **布局与资源分流**：
  - 手机：`res/layout/`（底部导航栏、竖屏分行控制栏）
  - 平板：`res/layout-sw600dp/`（侧边栏双栏布局）
  - 电视：`res/layout-television/`（大尺寸按钮、D-Pad 遥控器优先）
  - 尺寸与行列数统一由 `res/values/`、`values-sw600dp/`、`values-television/` 分流。
- **遥控器焦点闭环**：所有交互组件必须配置 `bg_item_focusable` 焦点背景，支持 D-Pad 方向键（上下左右、确认、返回、菜单），且返回键必须正确恢复上一焦点。

---

## 6. 验证与检查清单

在完成功能或修复后，按最小范围到全工程顺序执行验证：

1. **JVM 单元测试**：
   ```powershell
   .\gradlew.bat testDebugUnitTest :core:model:test :source:api:test
   ```
2. **Debug 构建**：
   ```powershell
   .\gradlew.bat :app:assembleDebug
   ```
3. **设备测试**：
   确认至少有一台处于 `device` 状态的 Android 设备：
   ```powershell
   adb devices
   # 仅在多设备时设置目标序列号：
   # $env:ANDROID_SERIAL = "<设备序列号>"
   .\gradlew.bat :app:connectedDebugAndroidTest
   ```
4. **提交前安全检查**：
   - 检查 `git status`，只提交必要代码，保留用户既有改动。
   - 严禁将日志、缓存、APK、密钥凭据或未纳管的设计草稿提交进仓库。
