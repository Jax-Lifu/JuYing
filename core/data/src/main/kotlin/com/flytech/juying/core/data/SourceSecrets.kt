package com.flytech.juying.core.data

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.inject.Inject
import javax.inject.Singleton

/**
 * 数据源凭据安全加密组件（AndroidKeyStore + AES-GCM）。
 *
 * **What**: 对数据源敏感信息（访问密码、包含凭据的 URL 令牌等）进行硬件隔离加密存储。
 *
 * **Why**: 避免密码或认证 Cookie 明文持久化到 Room 数据库或在备份/导出时泄露。
 * 加密使用 AES/GCM/NoPadding，AAD 绑定字段名（如 "password"），防止跨字段密文篡改伪造。
 */
@Singleton
class SourceSecrets @Inject constructor() {
    private val key: SecretKey by lazy {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey) ?: KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
            generateKey()
        }
    }

    fun encrypt(value: String, field: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key)
        cipher.updateAAD(field.toByteArray(Charsets.UTF_8))
        return PREFIX + Base64.getEncoder().encodeToString(cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8)))
    }

    /** 旧明文只供一次迁移读取；认证失败必须向上报告，不能覆盖原始记录。 */
    fun decrypt(value: String, field: String): String {
        if (!value.startsWith(PREFIX)) return value
        val bytes = Base64.getDecoder().decode(value.removePrefix(PREFIX))
        require(bytes.size >= 28) { "来源密文损坏" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
        cipher.updateAAD(field.toByteArray(Charsets.UTF_8))
        return String(cipher.doFinal(bytes, 12, bytes.size - 12), Charsets.UTF_8)
    }

    fun isEncrypted(value: String) = value.startsWith(PREFIX)

    private companion object {
        const val ALIAS = "juying-source-secrets-v1"
        const val PREFIX = "enc:v1:"
    }
}
