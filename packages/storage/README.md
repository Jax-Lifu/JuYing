# juying_storage

结构化持久化、配置与安全凭据存储包。

## 核心职责 (What)
- 版本化设置与偏好存储（Schema Versioning）。
- 数据库连接与多表查询封装（频道、EPG、播放历史、收藏）。
- 硬件安全存储契约封装（`ISecureCredentialVault`）。

## 设计动机 (Why)
遵循 Section 5.10 配置与存储分层规范，保证敏感凭据硬件加密、业务数据具备索引迁移能力。
