package com.flytech.juying

import android.os.Looper
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SourceType
import com.flytech.juying.source.cctv.CctvSource
import com.flytech.juying.source.iptv.IptvSource
import com.flytech.juying.source.tvbox.TvboxSource
import java.util.concurrent.atomic.AtomicInteger
import javax.inject.Provider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SourceInitializationTest {
    @Test fun sourceDiscoveryDefersNetworkClientUntilBackgroundRequest() = runBlocking {
        val calls = AtomicInteger()
        val client = OkHttpClient()
        val provider = Provider {
            assertNotEquals("Network initialization must stay off the UI thread", Looper.getMainLooper(), Looper.myLooper())
            calls.incrementAndGet()
            client
        }
        val cctv = CctvSource(provider, Dispatchers.Default)
        val iptv = IptvSource(provider, Dispatchers.Default,
            Provider { androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().targetContext })
        val tvbox = TvboxSource(provider, Dispatchers.Default, Provider { error("CMS must not start Spider") })
        withContext(Dispatchers.Main) {
            assertTrue(cctv.observeDiscoveredSources().first().isNotEmpty())
            for (source in listOf(cctv, iptv, tvbox)) assertTrue(source.capabilities.isNotEmpty())
            assertNotNull(tvbox.urlSetup)
            assertEquals(0, calls.get())
        }
        MockWebServer().use { server ->
            server.start()
            server.enqueue(MockResponse().setBody("#EXTM3U\n#EXTINF:-1,Fixture\nhttps://example.test/video.m3u8"))
            server.enqueue(MockResponse().setBody("""{"class":[{"type_id":"1","type_name":"Fixture"}]}"""))
            server.enqueue(MockResponse().setBody("""{"class":[{"type_id":"1","type_name":"Fixture"}]}"""))
            val playlistUrl = server.url("/iptv").toString()
            val cmsUrl = server.url("/cms").toString()
            withContext(Dispatchers.Main) {
                assertEquals(1, iptv.channels(SourceConfig("iptv", "IPTV", SourceType.IPTV, playlistUrl)).size)
                assertEquals(1, tvbox.categories(SourceConfig("cms", "CMS", SourceType.TVBOX, cmsUrl)).size)
            }
            assertEquals(3, calls.get())
        }
    }
}
