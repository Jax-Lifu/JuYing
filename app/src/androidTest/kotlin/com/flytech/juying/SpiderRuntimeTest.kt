package com.flytech.juying

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.flytech.juying.core.model.PlaybackRoute
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SourceType
import com.flytech.juying.source.tvbox.TvboxSource
import com.flytech.juying.source.tvbox.spider.SpiderClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import okio.Buffer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import javax.inject.Provider

@RunWith(AndroidJUnit4::class)
class SpiderRuntimeTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val server = MockWebServer()
    private val started = CountDownLatch(1)
    private val client = OkHttpClient()
    private val source = TvboxSource(Provider { client }, Dispatchers.Default, Provider { spiderClient })

    @Before fun startServer() {
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                val path = request.requestUrl!!.encodedPath.removePrefix("/")
                val response = MockResponse()
                return when {
                    path.endsWith(".json") -> {
                        val name = path.removeSuffix(".json")
                        val api = if (name == "jar") "csp_Fixture" else "$name.${if (name == "python" || name == "stuck") "py" else "js"}"
                        response.setBody("""{"spider":"${server.url("/fixture.jar")}","sites":[{"key":"fixture","name":"测试","type":3,"api":"$api","ext":"${server.url("/")}"}]}""")
                    }
                    path == "fixture.jar" -> response.setBody(Buffer().write(File(instrumentation.context.applicationInfo.sourceDir).readBytes()))
                    path == "categories" -> response.setBody("""{"class":[{"type_id":"films","type_name":"测试分类"}]}""")
                    path == "title" -> response.setBody("<html><h1>测试分类</h1></html>")
                    path == "started" -> { started.countDown(); response.setBody("ok") }
                    else -> {
                        val asset = when (path) { "modern.js" -> "fixture.js"; "python.py" -> "fixture.py"; else -> path }
                        response.setBody(instrumentation.context.assets.open("spiders/$asset").bufferedReader().use { it.readText() })
                    }
                }
            }
        }
        server.start()
    }

    @After fun stopServer() = server.shutdown()

    @Test fun jarExecutesCompleteContentContract() = runBlocking { verifyContract("jar", "Jar") }
    @Test fun javascriptModuleAndHttpExecuteCompleteContentContract() = runBlocking { verifyContract("modern", "JS") }
    @Test fun legacyJavascriptExecutesCompleteContentContract() = runBlocking { verifyContract("legacy", "Legacy") }
    @Test fun pythonAndBundledLibrariesExecuteCompleteContentContract() = runBlocking { verifyContract("python", "Python") }

    @Test fun cancellingBusyPythonAllowsImmediateNewJavascriptRequest() = runBlocking {
        val busy = launch(Dispatchers.Default) { source.categories(config("stuck")) }
        try {
            assertTrue("Python never reached its loop", started.await(15, TimeUnit.SECONDS))
        } finally {
            busy.cancelAndJoin()
        }
        withTimeout(15_000) { verifyContract("modern", "JS") }
    }

    private suspend fun verifyContract(name: String, label: String) {
        val config = config(name)
        val category = source.categories(config).single()
        assertEquals("测试分类", category.name)
        val item = source.list(config, category.id, 2).single()
        assertEquals("$label films 2", item.title)
        val detail = source.detail(config, item.id)
        assertEquals("$label 详情", detail.item.title)
        assertEquals("中文关键字", source.search(config, "中文关键字", 1).single().title)
        if (name == "jar" || name == "python") assertTrue(source.search(config, "中文关键字", 2).isEmpty())
        val play = source.resolve(config, detail.playGroups.single().episodes.single().ref)
        assertEquals(server.url("/video.mp4").toString(), play.url)
        assertEquals(server.url("/").toString(), play.headers["Referer"])
        assertEquals(PlaybackRoute.NATIVE, play.route)
        // Consecutive calls expose reply/worker-idle ordering races.
        repeat(8) { assertEquals(category, source.categories(config).single()) }
    }

    private fun config(name: String) = SourceConfig(name, name, SourceType.TVBOX, server.url("/$name.json").toString())

    companion object {
        private val spiderClient by lazy { SpiderClient(InstrumentationRegistry.getInstrumentation().targetContext) }
    }
}
