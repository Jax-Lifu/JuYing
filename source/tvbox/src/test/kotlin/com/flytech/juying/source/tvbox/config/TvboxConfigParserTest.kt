package com.flytech.juying.source.tvbox.config

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class TvboxConfigParserTest {

    @Test
    fun parsesSitesLivesWithCommentsAndUnknownKeys() {
        val text = """
            // 注释行
            {"spider":"./a.jar;md5;xx","unknown":1,
             "sites":[{"key":"k1","name":"站点1","type":3,"api":"csp_Foo","ext":{"a":1}},
                      {"key":"k2","name":"站点2","type":1,"api":"http://x/api.php","ext":"str"}],
             "lives":[{"name":"直播","type":0,"url":"http://x/live.txt"}]}
        """.trimIndent()
        val cfg = TvboxConfigParser.parse(text)
        assertEquals(2, cfg.sites.size)
        assertEquals(3, cfg.sites[0].type)
        assertNotNull(cfg.sites[0].ext)
        assertEquals("http://x/live.txt", cfg.lives.single().url)
    }

    @Test
    fun detectsMultiRepo() {
        val repos = TvboxConfigParser.parseRepoList("""{"urls":[{"url":"http://a","name":"A"}]}""")
        assertEquals("http://a", repos!!.single().url)
        assertNull(TvboxConfigParser.parseRepoList("""{"sites":[]}"""))
    }

    @Test fun decodesPictureEnvelopeAndFongmiAesEnvelope() {
        val json = """{"sites":[{"key":"a","type":3,"api":"csp_Test"}]}"""
        val picture = "binary-picture\uFFFDabcdefgh**" + java.util.Base64.getEncoder().encodeToString(json.toByteArray())
        assertEquals("a", TvboxConfigParser.parse(picture).sites.single().key)
        val key = "configkey"
        val iv = "1700000000000"
        val cipher = javax.crypto.Cipher.getInstance("AES/CBC/PKCS5Padding")
        cipher.init(javax.crypto.Cipher.ENCRYPT_MODE,
            javax.crypto.spec.SecretKeySpec(key.padEnd(16, '0').toByteArray(), "AES"),
            javax.crypto.spec.IvParameterSpec(iv.padEnd(16, '0').toByteArray()))
        val encoded = ("\$#$key#\$".toByteArray() + cipher.doFinal(json.toByteArray()) + iv.toByteArray())
            .joinToString("") { "%02x".format(it) }
        assertEquals("a", TvboxConfigParser.parse(encoded).sites.single().key)
        org.junit.Assert.assertTrue(runCatching { TvboxConfigParser.parse("2423invalid") }.isFailure)
    }

    @Test fun resolvesRelativeValuesWithInlineCommentsAndTrailingCommas() {
        val document = TvboxConfigParser.document("""{"sites":[/* inline */
            {"key":"a","type":3,"api":"./spider.js","ext":{"rule":"../rule.js"},},],
            "script":"console.log('./untouched')"}""", "https://example.test/redirect/config.json")
        val site = TvboxConfigParser.parse(document.toString()).sites.single()
        assertEquals("https://example.test/redirect/spider.js", site.api)
        org.junit.Assert.assertTrue(site.ext.toString().contains("https://example.test/rule.js"))
        org.junit.Assert.assertTrue(document.toString().contains("console.log('./untouched')"))
    }
}
