# 平台能力矩阵

| 平台 | 共享 Flutter UI | 视频形态 | 输入 | 专用能力/约束 |
|---|---:|---|---|---|
| iOS / iPadOS | 是 | 点播、直播、画中画 | 触控、键盘 | AVPlayer 适配器、AirPlay、系统安全存储 |
| Android | 是 | 点播、直播、画中画 | 触控、键盘 | Media3 适配器、Cast、Keystore |
| Android TV | 大部分 | 电视全屏播放 | D-pad、遥控器 | 焦点图、Leanback、推荐频道 |
| tvOS | 大部分 | 电视全屏播放 | Siri Remote | 独立 Runner、Top Shelf；需单独验证 Flutter 支持策略 |
| Android Auto | 受限 | 以音频为主 | 旋钮、语音、模板 | 仅使用系统批准模板，行驶中不提供视频浏览 |
| CarPlay | 受限 | 以音频为主 | 旋钮、语音、模板 | entitlement 与模板限制；不把手机视频 UI 镜像到车机 |
| Windows | 是 | 窗口/全屏 | 鼠标、键盘、手柄 | 系统媒体键、文件关联、SMB |
| Linux | 是 | 窗口/全屏 | 鼠标、键盘、手柄 | 解码器与发行版依赖探测 |

“支持平台”分为产品层可复用与商店可发布两件事。车机和 tvOS 必须分别通过厂商审核、entitlement 与真实设备验证后才能标记为可发布。

