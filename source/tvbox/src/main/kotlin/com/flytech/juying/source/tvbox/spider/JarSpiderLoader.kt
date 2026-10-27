package com.flytech.juying.source.tvbox.spider

import android.content.Context
import com.github.catvod.crawler.Spider
import dalvik.system.DexClassLoader
import timber.log.Timber
import com.flytech.juying.source.tvbox.JAR_API_PREFIX
import java.io.File
import java.security.MessageDigest

/**
 * 加载 TVBox 的 jar 爬虫（site.type=3，api 形如 "csp_Foo"）。
 *
 * 安全与低配优化要点（Why）：
 * 1. Android 14+ 要求被动态加载的 DEX/JAR 文件必须只读，加载前强制 `setReadOnly()`；
 * 2. 若配置中声明了 `url;md5;xxx`，强制校验 JAR 文件 MD5，防止中间人篡改；
 * 3. 与 CatVod 一致传入 Application，部分 JAR 会注册应用生命周期回调；同 UID 代码可访问宿主数据；
 * 4. 同一 JAR 复用同一个 `DexClassLoader`，避免重复加载撑爆低配机 Metaspace/Native 内存。
 */
class JarSpiderLoader(private val context: Context) {

    private val loaders = HashMap<String, DexClassLoader>()

    @Synchronized
    fun load(jarFile: File, api: String, ext: String, expectedMd5: String? = null): Spider {
        if (!expectedMd5.isNullOrBlank()) {
            val actualMd5 = computeMd5(jarFile)
            require(actualMd5.equals(expectedMd5.trim(), ignoreCase = true)) {
                "Spider JAR MD5 mismatch: expected=$expectedMd5, actual=$actualMd5"
            }
        }
        require(api.startsWith(JAR_API_PREFIX)) { "无效的 Spider 类名" }
        check(jarFile.setReadOnly()) { "无法保护 Spider JAR" }
        val loader = loaders.getOrPut(jarFile.absolutePath) {
            val optDir = File(context.codeCacheDir, "spider").apply { mkdirs() }
            Timber.d("Creating DexClassLoader for spider jar: %s", jarFile.name)
            DexClassLoader(jarFile.absolutePath, optDir.absolutePath, null, context.classLoader).also { created ->
                // CatVod JAR 通常先建立全局 Context，再创建具体站点；只有缺少可选入口才可忽略。
                val initializer = try { created.loadClass("com.github.catvod.spider.Init") } catch (_: ClassNotFoundException) { null }
                initializer?.getMethod("init", Context::class.java)?.invoke(null, context.applicationContext)
            }
        }
        val className = "com.github.catvod.spider." + api.removePrefix(JAR_API_PREFIX)
        val spider = loader.loadClass(className).getDeclaredConstructor().newInstance() as Spider
        spider.init(context.applicationContext, ext)
        return spider
    }

    @Synchronized
    fun clear() = loaders.clear()

    private fun computeMd5(file: File): String {
        val digest = MessageDigest.getInstance("MD5")
        file.inputStream().buffered().use { input ->
            val buf = ByteArray(8192)
            var n: Int
            while (input.read(buf).also { n = it } > 0) {
                digest.update(buf, 0, n)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}
