package com.flytech.juying.source.tvbox.spider

import com.flytech.juying.source.tvbox.SpiderLanguage
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull

/** 内部 IPC 契约；站点配置与凭据仅驻留内存，不写入日志和播放历史。 */
@Serializable
internal data class SpiderSpec(
    val key: String,
    val language: SpiderLanguage,
    val api: String,
    val jar: String? = null,
    val ext: JsonElement = JsonNull,
)

@Serializable
internal enum class SpiderMethod(val function: String, val legacyFunction: String) {
    HOME("homeContent", "home"),
    CATEGORY("categoryContent", "category"),
    DETAIL("detailContent", "detail"),
    SEARCH("searchContent", "search"),
    PLAYER("playerContent", "play"),
}

/** 跨进程 Spider 爬虫调用请求与方法签名载体。 */
@Serializable
internal data class SpiderCall(val spec: SpiderSpec, val method: SpiderMethod, val args: JsonArray)

/** 爬虫执行超时与并发调用预算限制。 */
internal object SpiderLimits {
    const val CALL_TIMEOUT_MS = 20_000L
    const val BIND_TIMEOUT_MS = 5_000L
    const val IDLE_TIMEOUT_MS = 30_000L
    const val HTTP_TIMEOUT_MS = 8_000L
    // Binder 的事务上限由进程共享，留出 Bundle、错误与并发系统事务的余量。
    const val IPC_MAX_BYTES = 512 * 1024
    const val SCRIPT_MAX_BYTES = 2 * 1024 * 1024L
    const val JAR_MAX_BYTES = 32 * 1024 * 1024L
    const val JS_HEAP_BYTES = 24 * 1024 * 1024L
    const val MODULE_COUNT = 32
}

/** 爬虫跨进程调用序列化协议与 JSON 桥接工具。 */
internal object SpiderWire {
    const val CALL = 1
    const val RESULT = 2
    const val CANCEL = 3
    const val PAYLOAD = "payload"
    const val ERROR = "error"
}
