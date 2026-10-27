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

/** 来源地址也可能带令牌。字段与记录绑定加密，密钥仅在首次后台读写时加载。 */
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
