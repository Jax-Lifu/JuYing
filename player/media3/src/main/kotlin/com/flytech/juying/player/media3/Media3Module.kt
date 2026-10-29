package com.flytech.juying.player.media3

import android.content.Context
import androidx.media3.common.util.UnstableApi
import com.flytech.juying.core.model.DeviceProfile
import com.flytech.juying.player.api.PlayerEngineFactory
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import dagger.multibindings.Multibinds
import androidx.media3.datasource.DataSource

/** Media3 播放引擎工厂与 DataSource 的 Hilt 注入模块。 */
@Module
@InstallIn(SingletonComponent::class)
abstract class Media3Module {

    /** 自定义协议（smb 等）的 DataSource.Factory 集合，key 为 URI scheme。 */
    @Multibinds
    abstract fun customDataSources(): Map<String, @JvmSuppressWildcards DataSource.Factory>

    companion object {
        @UnstableApi
        @Provides
        fun engineFactory(
            @ApplicationContext context: Context,
            profile: DeviceProfile,
            dataSources: JuyingDataSourceFactory,
        ): PlayerEngineFactory = PlayerEngineFactory { settings ->
            Media3Engine(context, profile, settings, dataSources)
        }
    }
}
