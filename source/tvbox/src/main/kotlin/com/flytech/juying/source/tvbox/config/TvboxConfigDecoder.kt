package com.flytech.juying.source.tvbox.config

import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

/** TVBox 配置封装兼容 FongMi/TV Decoder.java（GPL-3.0，aa30eb047c749fe5a96dd47b94947cda2421354f）。 */
internal object TvboxConfigDecoder {
    private val base64Marker = Regex("[A-Za-z0-9]{8}\\*\\*")

    fun decode(value: String): String {
        var text = value.removePrefix("\uFEFF").trim()
        require(text.isNotEmpty()) { "订阅为空" }
        if (text.startsWith("{") || text.startsWith("//")) return text
        base64Marker.find(text)?.let { marker ->
            text = String(Base64.getMimeDecoder().decode(text.substring(marker.range.last + 1)), Charsets.UTF_8)
        }
        if (!text.startsWith("2423")) return text
        val hex = text.filterNot(Char::isWhitespace)
        val bytes = hexBytes(hex)
        val decoded = String(bytes, Charsets.UTF_8).lowercase(java.util.Locale.ROOT)
        val separator = decoded.indexOf("#$")
        require(separator in 2..18 && decoded.length >= separator + 15) { "订阅加密头无效" }
        val key = decoded.substring(2, separator).padEnd(16, '0').toByteArray(Charsets.UTF_8)
        val iv = decoded.takeLast(13).padEnd(16, '0').toByteArray(Charsets.UTF_8)
        require(key.size == 16 && iv.size == 16) { "订阅密钥无效" }
        val ciphertext = hexBytes(hex.substring(hex.indexOf("2324") + 4, hex.length - 26))
        val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
        return String(cipher.doFinal(ciphertext), Charsets.UTF_8)
    }

    private fun hexBytes(value: String): ByteArray {
        require(value.length % 2 == 0 && value.all { it.digitToIntOrNull(16) != null }) { "订阅密文无效" }
        return ByteArray(value.length / 2) { value.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
    }
}
