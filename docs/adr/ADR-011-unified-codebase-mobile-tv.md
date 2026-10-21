# ADR-011: 手机与 Android TV 共享单一代码库与业务领域，响应式与焦点导航按形态适配

## 状态
已接受 (Accepted) (v0.2 Q1 / ADR-011)

## 日期
2026-10-20

## 背景与上下文
聚映首个版本即正式支持 Android 手机与 Android TV（Q1 / APP-04）。传统做法往往因为移动端触控交互与 TV 遥控器焦点交互的差异，导致工程分化为两个独立分支或不同 App。
长此以往会导致领域逻辑、协议解析、BUG 修复的严重重复和碎片化。

## 决策
1. **单一代码库与单包分发**：
   - 手机、平板、桌面与 Android TV 统一在 `apps/juying_app` 中构建，共享同一套领域模型（`packages/core`）与业务特征库（`features/*`）。
2. **形态感知与双模交互适配**：
   - 通过 `PlatformInfo` 动态感知当前设备形态（ScreenFormFactor: mobile / tablet / desktop / tv）与触摸屏/遥控器输入能力。
   - **移动端**：优先渲染底部标签栏（Bottom Navigation）、滑动手势调光调音、触摸卡片。
   - **电视端 (10-Foot UI)**：严格留出安全边距（Overscan 留白），字体放大至客厅可视尺寸，所有交互元素外包 `TvFocusWrapper`，焦点放大并呈现高光发光环，按键映射严格响应方向键、确认、返回、菜单及数字键。
3. **Android TV 清单与 Banner 完整声明**：
   - AndroidManifest.xml 明确声明 `android.software.leanback` 为非必须、`android.hardware.touchscreen` 为非必须，配置 `LEANBACK_LAUNCHER` 与 TV Banner，确保在 Android TV 应用商店与电视启动器中正确展示。

## 原因分析与权衡
1. **研发效率最大化**：
   - 协议解析（M3U、TVBox、SMB、DLNA、EPG）与核心状态机仅写一套，单测与回归测试一次完成。
2. **渐进增强**：
   - 业务页面内通过响应式布局（Responsive Layout）和焦点系统（FocusTraversalGroup）自适应不同交互输入，不限制电视端的操作体验。
