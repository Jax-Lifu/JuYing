package com.flytech.juying.core.network

import android.content.Context
import com.flytech.juying.core.model.DeviceProfile
import com.flytech.juying.core.model.PerformanceTier
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import okhttp3.Cache
import okhttp3.ConnectionPool
import okhttp3.Dispatcher
import okhttp3.OkHttpClient
import java.io.File
import java.util.concurrent.TimeUnit
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object NetworkModule {

    private const val UA = "Mozilla/5.0 (Linux; Android 9) AppleWebKit/537.36 JuYing/0.1"

    @Provides
    @Singleton
    fun okHttpClient(@ApplicationContext context: Context, profile: DeviceProfile): OkHttpClient {
        val (cacheMb, maxReq, maxIdleConn) = when (profile.tier) {
            PerformanceTier.LOW -> Triple(8L, 16, 2)
            PerformanceTier.MID -> Triple(20L, 32, 4)
            PerformanceTier.HIGH -> Triple(50L, 64, 6)
        }
        return OkHttpClient.Builder()
            .cache(Cache(File(context.cacheDir, "http"), cacheMb * 1024 * 1024))
            .connectionPool(ConnectionPool(maxIdleConn, 2, TimeUnit.MINUTES))
            .dispatcher(Dispatcher().apply { maxRequests = maxReq; maxRequestsPerHost = 8 })
            .connectTimeout(8, TimeUnit.SECONDS)
            .readTimeout(15, TimeUnit.SECONDS)
            .retryOnConnectionFailure(true)
            .addInterceptor { chain ->
                val req = chain.request()
                chain.proceed(
                    if (req.header("User-Agent") == null) req.newBuilder().header("User-Agent", UA).build() else req,
                )
            }
            .build()
    }
}
