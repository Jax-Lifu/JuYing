package com.flytech.juying.source.tvbox.spider

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.Json
import java.io.IOException
import javax.inject.Inject
import javax.inject.Singleton

/** 所有脚本站点串行共享一个惰性工作进程；取消时回收整个进程，防止遗留线程继续耗电。 */
@Singleton
class SpiderClient @Inject constructor(@ApplicationContext private val context: Context) {
    private val gate = Mutex()
    private val handler = Handler(Looper.getMainLooper())
    private var connection: ServiceConnection? = null
    private var remote: Messenger? = null
    private var pending: CompletableDeferred<String>? = null
    private var stopping: CompletableDeferred<Unit>? = null
    private val idle = Runnable { disconnect() }

    internal suspend fun call(call: SpiderCall, timeoutMillis: Long? = null): String = gate.withLock {
        val execute: suspend () -> String = { withContext(Dispatchers.Main.immediate) {
            handler.removeCallbacks(idle)
            val result = CompletableDeferred<String>()
            // 每次调用拥有自己的回复端点，迟到回复不能完成下一次请求。
            val replies = Messenger(Handler(Looper.getMainLooper()) { message ->
                if (message.what == SpiderWire.RESULT) {
                    val error = message.data.getString(SpiderWire.ERROR)
                    if (error != null) result.completeExceptionally(IOException(error))
                    else result.complete(message.data.getString(SpiderWire.PAYLOAD).orEmpty())
                }
                true
            })
            pending = result
            var completed = false
            try {
                val worker = connect()
                val payload = Json.encodeToString(call)
                require(payload.toByteArray().size <= SpiderLimits.IPC_MAX_BYTES) { "Spider 请求过大" }
                worker.send(Message.obtain(null, SpiderWire.CALL).apply {
                    data = Bundle().apply { putString(SpiderWire.PAYLOAD, payload) }
                    replyTo = replies
                })
                withTimeout(SpiderLimits.CALL_TIMEOUT_MS + SpiderLimits.BIND_TIMEOUT_MS) { result.await() }
                    .also { completed = true }
            } finally {
                pending = null
                if (completed) handler.postDelayed(idle, SpiderLimits.IDLE_TIMEOUT_MS)
                else disconnect()
            }
        } }
        if (timeoutMillis == null) execute() else withTimeout(timeoutMillis) { execute() }
    }

    private suspend fun connect(): Messenger {
        // 等待旧进程退出后再绑定，避免新请求连上刚收到 CANCEL 的旧进程。
        stopping?.let { withTimeout(SpiderLimits.BIND_TIMEOUT_MS) { it.await() } }
        stopping = null
        remote?.let { return it }
        val bound = CompletableDeferred<Messenger>()
        val candidate = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName, service: IBinder) {
                if (connection !== this) return
                remote = Messenger(service)
                bound.complete(remote!!)
            }
            override fun onServiceDisconnected(name: ComponentName) {
                if (connection !== this) return
                remote = null
                bound.completeExceptionally(IOException("Spider 服务连接中断"))
                pending?.completeExceptionally(IOException("Spider 已退出或运行超时"))
            }
            override fun onNullBinding(name: ComponentName) {
                if (connection !== this) return
                bound.completeExceptionally(IOException("Spider 服务无法启动"))
            }
            override fun onBindingDied(name: ComponentName) {
                if (connection !== this) return
                onServiceDisconnected(name)
                bound.completeExceptionally(IOException("Spider 服务连接失效"))
            }
        }
        connection = candidate
        check(context.bindService(Intent(context, SpiderService::class.java), candidate, Context.BIND_AUTO_CREATE)) {
            "Spider 服务无法启动"
        }
        return withTimeout(SpiderLimits.BIND_TIMEOUT_MS) { bound.await() }
    }

    private fun disconnect() {
        handler.removeCallbacks(idle)
        remote?.binder?.let { binder ->
            val stopped = CompletableDeferred<Unit>()
            stopping = stopped
            runCatching { binder.linkToDeath({ stopped.complete(Unit) }, 0) }
                .onFailure { stopped.complete(Unit) }
        }
        runCatching { remote?.send(Message.obtain(null, SpiderWire.CANCEL)) }
        connection?.let { runCatching { context.unbindService(it) } }
        connection = null
        remote = null
    }
}
