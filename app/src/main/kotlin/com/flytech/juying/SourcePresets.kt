package com.flytech.juying

import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SourceType
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dagger.multibindings.IntoSet

/** 用户选定入口中于 2026-10-26 实机验证的两个站点；以普通来源保存，允许编辑与删除。 */
@Module
@InstallIn(SingletonComponent::class)
object SourcePresets {
    @Provides @IntoSet fun golden(): SourceConfig = SourceConfig(
        "preset-feimao-jpys", "金牌 · 肥猫", SourceType.TVBOX, "http://肥猫.net/", extra = mapOf("siteKey" to "csp_Jpys"))

    @Provides @IntoSet fun firstAid(): SourceConfig = SourceConfig(
        "preset-feimao-firstaid", "急救 · 肥猫", SourceType.TVBOX, "http://肥猫.net/", extra = mapOf("siteKey" to "csp_FirstAid"))
}
