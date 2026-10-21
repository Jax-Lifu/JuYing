package com.flytech.juying.tvbox

import android.content.Context
import android.os.Handler
import android.os.Looper
import dalvik.system.DexClassLoader
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.lang.reflect.InvocationTargetException
import java.net.URL
import java.security.MessageDigest
import java.util.ArrayList
import java.util.HashMap
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

import okhttp3.HttpUrl.Companion.toHttpUrl

/**
 * Android-only CatVod JAR/Dex host.
 *
 * TVBox JAR files contain Android bytecode and deliberately link their Spider base class from the
 * host. The runtime keeps downloaded code in the app-private code cache, verifies an optional MD5,
 * marks it read-only before class loading (required by recent Android versions), and exposes only
 * the standard CatVod lifecycle to Flutter.
 *
 * This is a compatibility runtime, not a security sandbox: importing a third-party JAR grants that
 * code the Android app process permissions. Callers must present this trust boundary to users.
 */
class TvBoxDexRuntime(private val context: Context) : MethodChannel.MethodCallHandler {
    private val workers = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val loaders = ConcurrentHashMap<String, DexClassLoader>()
    private data class LoadedSpider(var extend: String, var instance: Any)

    private val spiders = ConcurrentHashMap<String, LoadedSpider>()
    private val initializedLoaders = ConcurrentHashMap.newKeySet<String>()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(true)
            "invoke" -> runAsync(result) { invoke(call) }
            "disposeSite" -> runAsync(result) {
                disposeSite(call.argument<String>("siteKey").orEmpty())
                true
            }
            "disposeAll" -> runAsync(result) {
                disposeAll()
                true
            }
            else -> result.notImplemented()
        }
    }

    private fun invoke(call: MethodCall): String {
        val siteKey = requireArgument(call, "siteKey")
        val api = requireArgument(call, "api")
        val jar = requireArgument(call, "jar")
        val operation = requireArgument(call, "operation")
        val extend = call.argument<String>("extend").orEmpty()
        val arguments = call.argument<Map<String, Any?>>("arguments").orEmpty()
        val jarIdentity = sha256(jar)
        val spiderIdentity = "$jarIdentity::$siteKey::$api"
        val loaded = spiders.computeIfAbsent(spiderIdentity) {
            LoadedSpider(extend, createSpider(jarIdentity, siteKey, api, jar, extend))
        }
        // Most published spiders keep mutable parser/session state and are not thread-safe.
        return synchronized(loaded) {
            // Refresh ext under the same lock as calls, so no request uses a destroyed instance.
            if (loaded.extend != extend) {
                val replacement = createSpider(jarIdentity, siteKey, api, jar, extend)
                destroySpider(loaded)
                loaded.instance = replacement
                loaded.extend = extend
            }
            val spider = loaded.instance
            when (operation) {
                "home" -> callString(spider, "homeContent", true)
                "category" -> callString(
                    spider,
                    "categoryContent",
                    arguments["tid"]?.toString().orEmpty(),
                    arguments["page"]?.toString() ?: "1",
                    true,
                    HashMap<String, String>(),
                )
                "detail" -> callString(
                    spider,
                    "detailContent",
                    arrayListOf(arguments["id"]?.toString().orEmpty()),
                )
                "search" -> invokeSearch(
                    spider,
                    arguments["keyword"]?.toString().orEmpty(),
                    arguments["page"]?.toString() ?: "1",
                )
                "player" -> callString(
                    spider,
                    "playerContent",
                    arguments["flag"]?.toString().orEmpty(),
                    arguments["id"]?.toString().orEmpty(),
                    ArrayList((arguments["flags"] as? List<*>)?.filterIsInstance<String>().orEmpty()),
                )
                else -> error("Unsupported CatVod operation: $operation")
            }
        }
    }

    private fun createSpider(
        jarIdentity: String,
        siteKey: String,
        api: String,
        jar: String,
        extend: String,
    ): Any {
        val loader = loaders.computeIfAbsent(jarIdentity) {
            val jarFile = obtainJar(jar, jarIdentity)
            DexClassLoader(
                jarFile.absolutePath,
                context.codeCacheDir.absolutePath,
                null,
                context.classLoader,
            )
        }
        initializeJarOnce(jarIdentity, loader)
        val classCandidates = mutableListOf<String>()
        if (api.contains(".")) {
            classCandidates.add(api)
        }
        val classSuffix = api.removePrefix("csp_").trim()
        if (classSuffix.isNotEmpty()) {
            classCandidates.add("com.github.catvod.spider.$classSuffix")
            classCandidates.add("com.github.catvod.spider.csp_$classSuffix")
            classCandidates.add("com.github.catvod.spider.$api")
        }
        var loadedClass: Class<*>? = null
        var lastError: Throwable? = null
        for (className in classCandidates.distinct()) {
            try {
                loadedClass = loader.loadClass(className)
                break
            } catch (e: Throwable) {
                lastError = e
            }
        }
        val targetClass = loadedClass ?: throw (lastError ?: ClassNotFoundException("CatVod Spider class not found for api: $api"))
        val spider = targetClass
            .getDeclaredConstructor()
            .newInstance()
        runCatching { spider.javaClass.getField("siteKey").set(spider, siteKey) }
        val initWithExtend = spider.javaClass.methods.firstOrNull {
            it.name == "init" && it.parameterTypes.size == 2
        }
        if (initWithExtend != null) {
            initWithExtend.invoke(spider, context.applicationContext, extend)
        } else {
            spider.javaClass.getMethod("init", Context::class.java)
                .invoke(spider, context.applicationContext)
        }
        return spider
    }

    private fun initializeJarOnce(identity: String, loader: DexClassLoader) {
        // Concurrent sites sharing one bundle must wait until its static Init has completed.
        synchronized(loader) {
            if (initializedLoaders.contains(identity)) return
            try {
                val initClass = loader.loadClass("com.github.catvod.spider.Init")
                val method = initClass.methods.firstOrNull {
                    it.name == "init" && it.parameterTypes.size == 1
                }
                method?.invoke(null, context.applicationContext)
            } catch (_: ClassNotFoundException) {
                // Init is optional in the CatVod ABI; simple spiders do not ship it.
            }
            initializedLoaders.add(identity)
        }
    }

    private fun obtainJar(specification: String, identity: String): File {
        val parts = specification.split(";md5;", limit = 2)
        val sourceUrl = parts.first().trim()
        val expectedMd5 = parts.getOrNull(1)?.trim()?.lowercase().orEmpty()
        require(sourceUrl.startsWith("http://") || sourceUrl.startsWith("https://")) {
            "Only HTTP(S) CatVod JAR URLs are supported"
        }
        val directory = File(context.codeCacheDir, "tvbox_jars").apply { mkdirs() }
        val target = File(directory, "$identity.jar")
        if (target.isFile && target.length() > 0L && verifyMd5(target, expectedMd5)) {
            require(target.setReadOnly()) { "Unable to make CatVod JAR read-only" }
            return target
        }
        if (target.exists()) target.delete()
        val temporary = File(directory, "$identity.download")
        // A process exit may leave an immutable partial download; replace it before opening.
        if (temporary.exists()) require(temporary.delete()) { "Unable to replace CatVod download" }
        try {
            URL(normalizeUnicodeHost(sourceUrl)).openConnection().apply {
                connectTimeout = 15_000
                readTimeout = 30_000
                setRequestProperty("User-Agent", "okhttp/3.15")
            }.getInputStream().use { input ->
                FileOutputStream(temporary).use { output ->
                    // Android 14 requires code to be immutable before loading. Marking the open
                    // file before writing also closes the path-based modification race.
                    require(temporary.setReadOnly()) { "Unable to make CatVod download read-only" }
                    input.copyTo(output)
                }
            }
            require(temporary.length() > 0L) { "Downloaded CatVod JAR is empty" }
            require(verifyMd5(temporary, expectedMd5)) { "CatVod JAR MD5 mismatch" }
            require(temporary.renameTo(target)) { "Unable to commit CatVod JAR cache" }
            require(target.setReadOnly()) { "Unable to make CatVod JAR read-only" }
            return target
        } finally {
            if (temporary.exists()) temporary.delete()
        }
    }

    private fun invokeSearch(spider: Any, keyword: String, page: String): String {
        val paged = spider.javaClass.methods.firstOrNull {
            it.name == "searchContent" && it.parameterTypes.size == 3
        }
        return if (paged != null) {
            paged.invoke(spider, keyword, false, page)?.toString().orEmpty()
        } else {
            callString(spider, "searchContent", keyword, false)
        }
    }

    private fun callString(target: Any, name: String, vararg arguments: Any): String {
        val method = target.javaClass.methods.firstOrNull {
            it.name == name && it.parameterTypes.size == arguments.size
        } ?: error("CatVod method not found: $name/${arguments.size}")
        return method.invoke(target, *arguments)?.toString().orEmpty()
    }

    private fun disposeSite(siteKey: String) {
        val matches = spiders.entries.filter { it.key.contains("::$siteKey::") }
        for ((key, spider) in matches) {
            destroySpider(spider)
            spiders.remove(key)
        }
    }

    private fun disposeAll() {
        for (spider in spiders.values) {
            destroySpider(spider)
        }
        spiders.clear()
        loaders.clear()
        initializedLoaders.clear()
    }

    private fun destroySpider(loaded: LoadedSpider) {
        synchronized(loaded) {
            val spider = loaded.instance
            runCatching { spider.javaClass.getMethod("destroy").invoke(spider) }
        }
    }

    private fun runAsync(result: MethodChannel.Result, block: () -> Any?) {
        workers.execute {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (rawError: Throwable) {
                val error = unwrap(rawError)
                mainHandler.post {
                    result.error(
                        "TVBOX_DEX_ERROR",
                        error.message ?: error.javaClass.simpleName,
                        error.stackTraceToString(),
                    )
                }
            }
        }
    }

    private fun requireArgument(call: MethodCall, name: String): String {
        return call.argument<String>(name)?.trim().takeUnless { it.isNullOrEmpty() }
            ?: error("Missing CatVod argument: $name")
    }

    private fun verifyMd5(file: File, expected: String): Boolean {
        if (expected.isEmpty()) return true
        val digest = MessageDigest.getInstance("MD5")
        file.inputStream().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) } == expected
    }

    private fun sha256(value: String): String {
        return MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray())
            .joinToString("") { "%02x".format(it) }
    }

    private fun normalizeUnicodeHost(value: String): String {
        // URI.host is null for Unicode authorities; OkHttp performs IDNA and path escaping.
        return value.toHttpUrl().toString()
    }

    private fun unwrap(error: Throwable): Throwable {
        var current = error
        while (current is InvocationTargetException && current.targetException != null) {
            current = current.targetException
        }
        return current
    }
}
