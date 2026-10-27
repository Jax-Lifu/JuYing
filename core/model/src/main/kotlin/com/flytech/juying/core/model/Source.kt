package com.flytech.juying.core.model

/**
 * 全场景统一数据源分类。
 *
 * **What**: 覆盖在线官方源（CCTV）、聚合点播/直播源（TVBOX/IPTV）、云端网盘（CLOUD_DRIVE/ALIST/WEBDAV）、
 * 局域网共享与发现（SMB/NFS/UPNP）以及本机与热插拔外置存储（LOCAL/USB_STORAGE）。
 *
 * **Why**: 在框架初期固定全量源枚举与正交能力模型（[SourceCapability]），避免后续接入新源时在 UI 层
 * 散落硬编码分支。业务层一律通过 `SourceRegistry` 按能力查询，不直接耦合具体枚举值。
 */
enum class SourceType {
    CCTV,
    TVBOX,
    IPTV,
    CLOUD_DRIVE,
    ALIST,
    WEBDAV,
    SMB,
    NFS,
    LOCAL,
    USB_STORAGE,
    UPNP,
}

/** 数据源对外提供的正交业务能力。一个 [SourceType] 可同时具备多种能力（如 CCTV 同时具备 LIVE + VOD + SEARCH）。 */
enum class SourceCapability {
    LIVE,
    VOD,
    BROWSE,
    SEARCH,
}

/**
 * 复合数据源（如 TVBox 单仓内的多个 Spider 站点、网盘内的多个挂载盘）暴露的子源描述。
 */
data class SubSource(
    val id: String,
    val name: String,
    val searchable: Boolean = true,
)

/** Provider-owned address form: the UI validates supported schemes without branching on source types. */
data class UrlSourceSetup(val type: SourceType, val name: String, val description: String,
    val schemes: Set<String> = setOf("http", "https"), val credentials: Boolean = false,
    val requiresPath: Boolean = false, val fileMimeTypes: List<String> = emptyList(),
    val epg: Boolean = false)

/**
 * 统一数据源配置实体（涵盖用户手动配置源与系统动态发现源）。
 *
 * **What**: 描述一个可寻址的数据源实例；各协议特有的扩展字段（如 TVBox 的 `repoUrl`/`siteKey`、
 * 网盘的 `driveType`/`refreshToken`、SMB 的 `domain`、UPnP 的 `udn`/`controlUrl`、USB 的 `uuid`）
 * 统一存放在 [extra] 键值表中。
 *
 * **Why**: 不同协议的参数差异极大，使用 `extra` 键值映射可在不修改 Room 表结构的前提下无缝扩展任意新源；
 * [isReadOnly] 区分内置/热插拔动态发现源（如 CCTV、USB 移动存储、UPnP）与用户可增删改的持久源。
 */
data class SourceConfig(
    val id: String,
    val name: String,
    val type: SourceType,
    val url: String,
    val enabled: Boolean = true,
    val username: String? = null,
    val password: String? = null,
    val extra: Map<String, String> = emptyMap(),
    val isReadOnly: Boolean = false,
)
