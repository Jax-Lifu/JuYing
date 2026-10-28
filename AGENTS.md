# 聚映 (JuYing) 工程说明

本文件只保留会改变代理行为的项目约束。实现细节以源码、Gradle 配置和测试为准；历史验证结果放在 `docs/`，不要把一次设备测试写成永久规则。

## 1. 项目边界

- 面向 Android TV、平板和手机，最低支持 Android 9（`minSdk 28`）。UI 使用 `Fragment`、ViewBinding 和 RecyclerView，不引入 Compose。
- 低配设备优先：应用启动保持轻量，数据库、网络、数据源和播放器按需初始化；复用现有 `DeviceProfile` 的档位策略，不在文档中复制易变的阈值。
- 视频输出使用 `SurfaceView` 和 Media3。全局只保留一个 `PlayerEngine`，离开播放页时释放它。
- 应用不内置、分发或运营第三方盗版媒体源。央视使用官方公开入口；其他订阅源由用户自行配置。
- 修改前先查看 `git status`。保留用户已有改动，只触碰完成当前请求所需的文件；不要把日志、缓存、APK、凭据或运行产物提交进仓库。

## 2. 模块边界

```text
app                 组装模块并实现 Navigator
feature:*           页面功能，只依赖 core:* 与 player:api
core:model          无 Android 依赖的领域模型
core:data           Repository、SourceRegistry 和数据源汇总
source:api          SourceProvider 及能力接口
source:*            具体数据源实现
player:api           播放器抽象与 PlaybackManager
player:media3        Media3 播放实现
```

- 当前已接入的具体数据源模块是 `cctv`、`iptv`、`tvbox`、`smb`、`local`；`SourceType` 中的其他类型是统一契约的扩展位，不能据此宣称功能已经接入。
- `feature:*` 不得直接依赖其他 feature、`source:*` 或 `player:media3`。跨页面跳转统一通过 `core:ui` 的 `Navigator`。
- 新模块应沿用现有 convention plugin、Hilt 绑定和测试结构，不为单次需求增加包装层或新依赖。

## 3. 数据源契约

- 数据源按 `LiveSource`、`VodSource`、`BrowseSource`、`SearchableSource` 组合能力，并通过 `SourceRegistry` 按能力查询；ViewModel 和 Fragment 不维护硬编码的 `SourceType` 列表。
- `SourceConfig.extra` 保存协议扩展字段，动态发现源通过 `SourceDiscoveryProvider` 合并到 Repository。新增字段前先复用现有模型和序列化方式。
- `PlayLine`、请求头和备用线路必须沿现有 `PlayItem`/播放器链路传递；不要在 UI 层拼接协议细节。
- 目录型源生成播放项时沿用 `SidecarSubtitles` 匹配同目录字幕。密码、Cookie、Token 只能加密存储或脱敏记录，日志不得输出明文。

## 4. 实现与文档风格

- Kotlin 使用官方风格，日志使用 Timber。公开契约、性能边界和协议适配点只写必要的 What/Why 注释。
- 保持现有原生 View、SurfaceView、生命周期和低频进度更新策略；不要为了“统一”重构相邻代码。
- 文档只写当前可验证的能力和明确边界。具体 APK 哈希、设备型号、时间点和历史失败记录放在对应验证文档，不写入通用规则。
- 提交信息使用 `feat`、`fix`、`refactor`、`perf`、`docs`、`test` 或 `chore` 前缀。

## 5. 验证

先完成与改动相匹配的最小检查，再扩大范围：

```powershell
# JVM/模块测试
.\gradlew.bat testDebugUnitTest :core:model:test :source:api:test

# Debug 构建
.\gradlew.bat :app:assembleDebug

# 设备测试：只要求有一台处于 device 状态的 Android 设备
adb devices
# 多设备时才取消注释并填写；单设备时不要设置
# $env:ANDROID_SERIAL = "<可用设备序列号>"
.\gradlew.bat :app:connectedDebugAndroidTest
```

`ANDROID_SERIAL` 只在需要选定设备时设置；不要要求固定型号、固定序列号或固定 Android 版本。没有可用设备时运行主机测试和构建，并明确记录未执行设备测试。设备测试报告必须注明实际设备、APK/测试包和检查范围，不能用静态检查或一次通过推断所有设备、网络源或长时间播放均已验收。

---

> 详细工程与数据源开发技能指导见 [.agents/skills/juying-platform/SKILL.md](.agents/skills/juying-platform/SKILL.md)。
