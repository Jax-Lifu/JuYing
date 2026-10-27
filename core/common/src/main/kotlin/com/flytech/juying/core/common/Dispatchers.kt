package com.flytech.juying.core.common

import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import javax.inject.Qualifier

@Qualifier
@Retention(AnnotationRetention.RUNTIME)
annotation class Dispatcher(val dispatcher: JuyingDispatchers)

enum class JuyingDispatchers { Default, IO }

@Module
@InstallIn(SingletonComponent::class)
object DispatchersModule {
    @Provides
    @Dispatcher(JuyingDispatchers.IO)
    fun ioDispatcher(): CoroutineDispatcher = Dispatchers.IO

    @Provides
    @Dispatcher(JuyingDispatchers.Default)
    fun defaultDispatcher(): CoroutineDispatcher = Dispatchers.Default
}
