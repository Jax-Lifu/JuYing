package com.flytech.juying.core.data

import com.flytech.juying.source.api.SourceDiscoveryProvider
import com.flytech.juying.source.api.SourceProvider
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dagger.multibindings.Multibinds

@Module
@InstallIn(SingletonComponent::class)
abstract class DataModule {
    /** 声明多重绑定集合：即使暂时没有任何数据源模块被引入，也能通过编译。 */
    @Multibinds
    abstract fun sourceProviders(): Set<SourceProvider>

    /** 声明动态发现源集合（如本地存储、USB 热插拔卷、UPnP SSDP 发现器）。 */
    @Multibinds
    abstract fun sourceDiscoveryProviders(): Set<SourceDiscoveryProvider>

    @Multibinds
    abstract fun sourcePresets(): Set<com.flytech.juying.core.model.SourceConfig>

    @Binds abstract fun sources(impl: DefaultSourceRepository): SourceRepository
    @Binds abstract fun live(impl: DefaultLiveRepository): LiveRepository
    @Binds abstract fun vod(impl: DefaultVodRepository): VodRepository
    @Binds abstract fun browse(impl: DefaultBrowseRepository): BrowseRepository
    @Binds abstract fun history(impl: DefaultHistoryRepository): HistoryRepository
    @Binds abstract fun favorites(impl: DefaultFavoriteRepository): FavoriteRepository
    @Binds abstract fun settings(impl: DefaultSettingsRepository): SettingsRepository
}
