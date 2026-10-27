package com.flytech.juying.source.tvbox.spider

import android.content.Context
import com.chaquo.python.PyObject
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import com.flytech.juying.source.tvbox.SpiderLanguage
import com.github.catvod.crawler.Spider
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import java.security.MessageDigest

internal interface SpiderRuntime : AutoCloseable {
    suspend fun call(method: SpiderMethod, args: JsonArray): String

    companion object {
        suspend fun create(context: Context, spec: SpiderSpec, http: ScriptHttp): SpiderRuntime =
            when (spec.language) {
                SpiderLanguage.JAR -> JarRuntime(context, spec, http)
                SpiderLanguage.JAVASCRIPT -> JavaScriptRuntime.create(context, spec, http)
                SpiderLanguage.PYTHON -> PythonRuntime(context, spec, http)
            }
    }
}

internal fun JsonElement.extString(): String = when (this) {
    JsonNull -> ""
    is JsonPrimitive -> content
    else -> toString()
}

private class JarRuntime(context: Context, spec: SpiderSpec, http: ScriptHttp) : SpiderRuntime {
    private val loader = JarSpiderLoader(context)
    private val spider: Spider

    init {
        val declaration = requireNotNull(spec.jar) { "站点缺少 Spider JAR" }.split(JAR_HASH_SEPARATOR)
        require(declaration.size <= 2) { "Spider JAR 校验格式错误" }
        val expectedHash = declaration.getOrNull(1)?.also {
            require(MD5_PATTERN.matches(it)) { "Spider JAR MD5 格式错误" }
        }
        val bytes = http.bytes(declaration.first(), SpiderLimits.JAR_MAX_BYTES)
        val hash = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
        val folder = File(context.codeCacheDir, "downloaded_spiders").apply { mkdirs() }
        val jar = File(folder, "$hash.jar")
        if (!jar.exists()) {
            // Android 14 要求加载的 DEX 在写入前标记只读；已打开的文件描述符仍可完成写入。
            jar.outputStream().use { output ->
                check(jar.setReadOnly()) { "无法保护 Spider JAR" }
                output.write(bytes)
            }
        }
        folder.listFiles()?.filter { it != jar }?.forEach { it.delete() }
        spider = loader.load(jar, spec.api, spec.ext.extString(), expectedHash)
    }

    override suspend fun call(method: SpiderMethod, args: JsonArray): String = when (method) {
        SpiderMethod.HOME -> spider.homeContent(args[0].jsonPrimitive.boolean)
        SpiderMethod.CATEGORY -> spider.categoryContent(
            args[0].jsonPrimitive.content, args[1].jsonPrimitive.content, args[2].jsonPrimitive.boolean,
            HashMap(args[3].jsonObject.mapValues { it.value.jsonPrimitive.content }),
        )
        SpiderMethod.DETAIL -> spider.detailContent(args[0].jsonArray.map { it.jsonPrimitive.content })
        SpiderMethod.SEARCH -> spider.searchContent(
            args[0].jsonPrimitive.content, args[1].jsonPrimitive.boolean, args[2].jsonPrimitive.content,
        )
        SpiderMethod.PLAYER -> spider.playerContent(
            args[0].jsonPrimitive.content, args[1].jsonPrimitive.content,
            args[2].jsonArray.map { it.jsonPrimitive.content },
        )
    }

    override fun close() {
        try { spider.destroy() } finally { loader.clear() }
    }

    private companion object {
        const val JAR_HASH_SEPARATOR = ";md5;"
        val MD5_PATTERN = Regex("[a-fA-F0-9]{32}")
    }
}

private class PythonRuntime(context: Context, spec: SpiderSpec, http: ScriptHttp) : SpiderRuntime {
    private val module: PyObject
    private val spider: PyObject

    init {
        if (!Python.isStarted()) Python.start(AndroidPlatform(context))
        module = Python.getInstance().getModule("juying_spider")
        spider = module.callAttr("load", http.text(spec.api), spec.api, spec.ext.extString(), http)
    }

    override suspend fun call(method: SpiderMethod, args: JsonArray): String =
        module.callAttr("invoke", spider, method.function, args.toString()).toString()

    override fun close() {
        try { module.callAttr("destroy", spider) } finally { spider.close(); module.close() }
    }
}
