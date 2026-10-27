package com.flytech.juying.source.smb

import android.net.Uri
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SourceType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.net.URI

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class SmbTargetTest {

    @Test
    fun `toPlayUri does not leak password in URI string`() {
        val config = SourceConfig(
            id = "nas-1",
            name = "Home NAS",
            type = SourceType.SMB,
            url = "smb://192.168.1.10/movies/4k",
            username = "admin",
            password = "TopSecretPassword123!",
            extra = mapOf("domain" to "WORKGROUP"),
        )
        val target = SmbTarget.fromConfig(config)
        val uri = target.toPlayUri("Avatar/Avatar.mkv")

        assertEquals("smb://admin@192.168.1.10/movies/4k/Avatar/Avatar.mkv", uri)
        assertFalse("Password must never appear in play URI", uri.contains("TopSecretPassword123!"))
        assertEquals("WORKGROUP", target.domain)
    }

    @Test
    fun `play URI preserves special characters in share directory and filename`() {
        val target = SmbTarget("nas", "共享 #?%+", "目录 #?%+", "admin")
        val relative = "季 1/电影 #?% +.mkv"
        val url = target.toPlayUri(relative)
        val uri = Uri.parse(url)
        val decoded = SmbTarget.fromPlayUri(uri)

        assertEquals("/${target.share}/${target.fullPath(relative)}", URI(url).path)
        assertNull(uri.query)
        assertNull(uri.fragment)
        assertEquals(target.host, decoded.host)
        assertEquals(target.share, decoded.share)
        assertEquals(target.fullPath(relative), decoded.basePath)
    }

    @Test
    fun `configured paths and literal percent escapes are encoded exactly once`() {
        val target = SmbTarget.fromConfig(SourceConfig(
            id = "nas", name = "NAS", type = SourceType.SMB,
            url = "smb://nas/shared%20movies/folder%23one",
            username = "admin",
        ))
        for (name in listOf("literal%23%3F%2F.mkv", "100%.mkv", "字幕 + #1?.srt")) {
            val uri = Uri.parse(target.toPlayUri(name))
            val decoded = SmbTarget.fromPlayUri(uri)

            assertNull(uri.query)
            assertNull(uri.fragment)
            assertEquals("shared movies", decoded.share)
            assertEquals("folder#one/$name", decoded.basePath)
        }
    }

    @Test
    fun `configured port survives playback URI and defaults to 445`() {
        for (authority in listOf("nas", "nas:445", "nas:1445", "[::1]:1445")) {
            val target = SmbTarget.fromConfig(SourceConfig(
                id = "nas", name = "NAS", type = SourceType.SMB,
                url = "smb://$authority/shared%20movies/folder", username = "guest",
            ))
            val expectedPort = if (authority.endsWith(":1445")) 1445 else 445
            val url = target.toPlayUri("movie.mkv")
            val decoded = SmbTarget.fromPlayUri(Uri.parse(url))

            assertEquals(expectedPort, target.port)
            assertEquals(expectedPort, decoded.port)
            assertEquals(target.host, decoded.host)
            assertEquals("shared movies", decoded.share)
            assertEquals("folder/movie.mkv", decoded.basePath)
            assertEquals(if (expectedPort == 445) -1 else expectedPort, URI(url).port)
        }
    }

    @Test
    fun `invalid configured and playback ports are rejected`() {
        for (port in listOf("0", "65536", "-2", "invalid")) {
            val url = "smb://nas:$port/share/movie.mkv"
            assertThrows(IllegalArgumentException::class.java) {
                SmbTarget.fromConfig(SourceConfig(id = "nas", name = "NAS", type = SourceType.SMB, url = url))
            }
            assertThrows(IllegalArgumentException::class.java) { SmbTarget.fromPlayUri(Uri.parse(url)) }
        }
    }
}
