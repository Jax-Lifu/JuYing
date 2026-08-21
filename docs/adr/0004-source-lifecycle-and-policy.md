# ADR-0004：来源生命周期与策略裁决

状态：已接受  
日期：2026-08-19  
复审日期：2027-02-19

## 背景

来源必须独立失败、下架和限制；页面不能依据来源名称猜测能力。

## 备选方案

1. 页面内 if/else；2. 只用 enabled；3. 来源能力、授权、健康、生命周期与统一策略。

## 决定

采用方案 3。来源声明能力、授权、健康和 active/paused/circuitOpen/retired 状态；策略统一裁决 browse/search/episodes/nativePlayback/officialFallback。`officialEntryOnly` 仅能在显式选择来源时浏览/搜索，且只允许官网回退播放。

## 后果与迁移

全局聚合不得自动纳入 unknown 或 officialEntryOnly 来源；来源级错误不能使其他来源失败。

## 验收与复审触发条件

启用、暂停、熔断、下架、恢复矩阵通过；授权地区或许可变化时复审。
