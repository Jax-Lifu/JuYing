# 架构说明

## 技术方向

采用“Flutter 共享产品层 + 平台专用宿主 + 可替换适配器”的结构。共享层负责界面、领域模型、导航、主题和多语言；平台宿主只负责系统能力；外部内容通过明确授权边界的适配器进入统一目录。

```text
apps/juying_app
  presentation  响应式 UI、TV 焦点、车机安全视图
  application   用例、状态、策略（下一阶段）
  domain        来源、媒体、用户、儿童策略、播放端口
  infrastructure CCTV 公开网页适配器；NAS/搜索适配器（下一阶段）

platform_hosts
  android_tv    遥控器、Leanback、推荐频道
  android_auto  MediaBrowser/音频模板；行驶中禁用视频浏览
  apple         iOS/tvOS/CarPlay 宿主与 entitlement
  desktop       Windows/Linux 系统集成
```

## 核心原则

1. **来源与播放器分离**：来源只产生规范化条目；播放器只接收已授权、可播放 URI。
2. **能力声明优先**：每个来源声明 browse/search/play 等能力，界面不猜测。
3. **授权默认拒绝**：`unknown` 来源不进入自动聚合或后台索引。
4. **儿童策略在查询前生效**：搜索、推荐、历史记录都必须先经过年龄与家长策略。
5. **凭据只存安全存储**：JSON 中只能出现 `secure://` 引用，不能出现密码或 token。
6. **车机安全降级**：行驶状态只允许平台认可的音频模板、语音和有限操作。

## CCTV 当前数据流

```text
api.cntv.cn 片库列表
  → tv.cctv.com 官方节目页
  → 提取页面显式声明的 guid
  → vdn.apps.cntv.cn 播放元数据
  → 校验版权/保护标记与可信域名
  → media_kit 原生播放 HLS
```

适配器不执行 JavaScript、不加载 WebView、不推导 CDN 路径，也不读取加密 manifest。播放 URL 只在当前播放会话内使用，不持久化。

## 后续建议模块

- `MediaItem` 规范化模型与来源去重/合并策略。
- 本地全文索引、拼音/多语言分词与儿童安全过滤。
- 播放会话、字幕/音轨、进度同步、投屏和画中画。
- 离线下载（仅来源明确允许）、存储配额和到期策略。
- 账户可选：优先 local-first，家庭同步端可自托管。
- 诊断中心：来源健康度、网络、解码器、日志脱敏导出。
