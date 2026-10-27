package com.flytech.juying.core.datastore

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.core.stringSetPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.flytech.juying.core.model.AppSettings
import com.flytech.juying.core.model.DecoderMode
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

private val Context.settingsStore: DataStore<Preferences> by preferencesDataStore(name = "settings")

@Singleton
class SettingsDataSource @Inject constructor(@ApplicationContext private val context: Context) {

    private object Keys {
        val DECODER = stringPreferencesKey("decoder_mode")
        val AUTO_FPS = booleanPreferencesKey("auto_frame_rate")
        val SOURCE_PRESETS = stringSetPreferencesKey("installed_source_presets")
    }

    val settings: Flow<AppSettings> = context.settingsStore.data.map { p ->
        AppSettings(
            decoderMode = p[Keys.DECODER]?.let { runCatching { DecoderMode.valueOf(it) }.getOrNull() }
                ?: DecoderMode.HARDWARE_FIRST,
            autoFrameRate = p[Keys.AUTO_FPS] ?: false,
        )
    }

    suspend fun setDecoderMode(mode: DecoderMode) {
        context.settingsStore.edit { it[Keys.DECODER] = mode.name }
    }

    suspend fun setAutoFrameRate(enabled: Boolean) {
        context.settingsStore.edit { it[Keys.AUTO_FPS] = enabled }
    }

    val installedSourcePresets: Flow<Set<String>> = context.settingsStore.data.map { it[Keys.SOURCE_PRESETS].orEmpty() }

    suspend fun markSourcePresetInstalled(id: String) {
        context.settingsStore.edit { it[Keys.SOURCE_PRESETS] = it[Keys.SOURCE_PRESETS].orEmpty() + id }
    }
}
