package com.flytech.juying.source.tvbox.spider

import android.app.Service
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.Process
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import timber.log.Timber
import javax.inject.Inject

/** 故障隔离进程；与宿主共享 UID，并不构成第三方代码的权限沙箱。 */
@AndroidEntryPoint
class SpiderService : Service() {
    @Inject lateinit var client: OkHttpClient
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO.limitedParallelism(1))
    private val main = Handler(Looper.getMainLooper())
    private val watchdog = Runnable { Process.killProcess(Process.myPid()) }
    private var active = false
    private var spec: SpiderSpec? = null
    private var runtime: SpiderRuntime? = null
    private val messenger = Messenger(Handler(Looper.getMainLooper()) { message ->
        when (message.what) {
            SpiderWire.CANCEL -> Process.killProcess(Process.myPid())
            SpiderWire.CALL -> execute(message)
        }
        true
    })

    override fun onBind(intent: Intent): IBinder = messenger.binder

    private fun execute(message: Message) {
        val reply = message.replyTo ?: return
        if (active) {
            reply(reply, error = "Spider 正忙，请重试")
            return
        }
        active = true
        main.postDelayed(watchdog, SpiderLimits.CALL_TIMEOUT_MS)
        val payload = message.data.getString(SpiderWire.PAYLOAD).orEmpty()
        scope.launch {
            var value: String? = null
            var failure: String? = null
            try {
                require(payload.toByteArray().size <= SpiderLimits.IPC_MAX_BYTES)
                val call = Json.decodeFromString<SpiderCall>(payload)
                if (call.spec != spec) {
                    runtime?.close()
                    runtime = null
                    spec = null
                    runtime = SpiderRuntime.create(this@SpiderService, call.spec, ScriptHttp(client))
                    spec = call.spec
                }
                val result = requireNotNull(runtime).call(call.method, call.args)
                require(result.toByteArray().size <= SpiderLimits.IPC_MAX_BYTES) { "Spider 响应过大" }
                value = result
            } catch (error: Throwable) {
                // 脚本异常可能包含 Cookie 或带令牌的 URL，只记录异常类型。
                val cause = generateSequence(error) { it.cause }.take(6).last()
                Timber.w("Spider call failed: %s at %s", cause.javaClass.simpleName, cause.stackTrace.firstOrNull())
                if (cause is ClassNotFoundException) {
                    val missing = Regex("[A-Za-z_$][A-Za-z0-9_$]*(?:\\.[A-Za-z_$][A-Za-z0-9_$]*){2,}").find(cause.message.orEmpty())?.value
                    Timber.w("Spider missing class: %s", missing)
                }
                failure = "Spider 执行失败，请检查脚本及其依赖"
            } finally {
                main.post {
                    main.removeCallbacks(watchdog)
                    active = false
                    // 先恢复可调用状态，再回复宿主，避免紧接的下一次调用误报忙碌。
                    reply(reply, value = value, error = failure)
                }
            }
        }
    }

    private fun reply(target: Messenger, value: String? = null, error: String? = null) {
        runCatching {
            target.send(Message.obtain(null, SpiderWire.RESULT).apply {
                data = Bundle().apply {
                    putString(SpiderWire.PAYLOAD, value)
                    putString(SpiderWire.ERROR, error)
                }
            })
        }
    }

    override fun onDestroy() {
        scope.cancel()
        // CPython 不能可靠卸载，进程退出也收回第三方 JAR 自建的线程与静态引用。
        super.onDestroy()
        Process.killProcess(Process.myPid())
    }
}
