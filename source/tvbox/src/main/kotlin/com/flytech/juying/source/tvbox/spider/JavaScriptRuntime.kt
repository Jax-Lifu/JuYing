package com.flytech.juying.source.tvbox.spider

import android.content.Context
import com.dokar.quickjs.ModuleContent
import com.dokar.quickjs.QuickJs
import com.dokar.quickjs.binding.asyncFunction
import com.dokar.quickjs.binding.function
import com.dokar.quickjs.moduleLoader
import com.flytech.juying.source.tvbox.TvboxJson
import com.flytech.juying.source.tvbox.TvboxSiteType
import kotlinx.coroutines.Dispatchers
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

internal class JavaScriptRuntime private constructor(private val engine: QuickJs) : SpiderRuntime {
    override suspend fun call(method: SpiderMethod, args: JsonArray): String = engine.evaluate(
        "await __invokeSpider(${JsonPrimitive(method.function)},${JsonPrimitive(method.legacyFunction)},$args)",
    )

    override fun close() = engine.close()

    companion object {
        private const val LEGACY_EXPORT = "__jsEvalReturn"

        suspend fun create(context: Context, spec: SpiderSpec, http: ScriptHttp): JavaScriptRuntime {
            val modules = mutableMapOf(spec.api to http.text(spec.api))
            val missing = mutableSetOf<String>()
            val loader = moduleLoader {
                normalize { base, requested -> TvboxJson.httpUrl(requested, base) }
                load { name ->
                    modules[name]?.let { ModuleContent.Source(it) } ?: run { missing += name; null }
                }
            }
            val engine = QuickJs.create(Dispatchers.IO, loader).apply {
                memoryLimit = SpiderLimits.JS_HEAP_BYTES
                evaluationTimeoutMillis = SpiderLimits.HTTP_TIMEOUT_MS
            }
            try {
                engine.function("__http") { args -> http.request(args[0] as String, args[1] as String) }
                engine.asyncFunction("__httpAsync") { args -> http.request(args[0] as String, args[1] as String) }
                engine.evaluate<Any?>(context.assets.open("spider_bridge.js").bufferedReader().use { it.readText() })
                val source = modules.getValue(spec.api)
                val legacy = source.contains(LEGACY_EXPORT)
                if (legacy) {
                    engine.evaluate<Any?>(source, filename = spec.api)
                    engine.evaluate<Any?>("globalThis.__spider = $LEGACY_EXPORT;")
                } else {
                    var entry: ByteArray? = null
                    // compile 也会解析静态导入；缺失依赖在回调之外下载，再重新编译。
                    while (entry == null) {
                        missing.clear()
                        val compilation = runCatching { engine.compile(
                            "import value from ${JsonPrimitive(spec.api)}; globalThis.__spider = typeof value === 'function' ? value() : value;",
                            filename = spec.api + ENTRY_SUFFIX, asModule = true,
                        ) }
                        if (compilation.isSuccess) { entry = compilation.getOrThrow(); break }
                        if (missing.isEmpty()) throw requireNotNull(compilation.exceptionOrNull())
                        require(modules.size + missing.size <= SpiderLimits.MODULE_COUNT) { "JS 依赖模块过多" }
                        missing.forEach { modules[it] = http.text(it) }
                    }
                    engine.evaluate<Any?>(checkNotNull(entry))
                }
                val init = if (legacy) buildJsonObject {
                    put("skey", spec.key); put("stype", TvboxSiteType.SPIDER.code); put("ext", spec.ext)
                } else spec.ext
                engine.evaluate<Any?>("globalThis.__spider=await __spider;if(__spider.init)await __spider.init($init);")
                return JavaScriptRuntime(engine)
            } catch (error: Throwable) {
                engine.close()
                throw error
            }
        }

        private const val ENTRY_SUFFIX = ".juying-entry.js"
    }
}
