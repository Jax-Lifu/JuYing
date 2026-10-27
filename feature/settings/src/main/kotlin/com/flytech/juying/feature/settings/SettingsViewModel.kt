package com.flytech.juying.feature.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.flytech.juying.core.data.SourceRepository
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.UrlSourceSetup
import dagger.hilt.android.lifecycle.HiltViewModel
import java.net.URI
import java.util.UUID
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

enum class SourceFormMessage { NONE, INVALID_NAME, INVALID_URL, INVALID_EPG, SAVED, FAILED, CHECKED, CHECK_EMPTY, CHECK_FAILED, CHECK_TIMEOUT, FILE_FAILED }
data class SourceEditor(val setup: UrlSourceSetup, val existing: SourceConfig? = null,
    val name: String = existing?.name.orEmpty(), val url: String = existing?.url.orEmpty(),
    val enabled: Boolean = existing?.enabled ?: true,
    val username: String = existing?.username.orEmpty(), val password: String = existing?.password.orEmpty(),
    val epgUrl: String = existing?.extra?.get("epgUrl").orEmpty(),
    val userAgent: String = existing?.extra?.get("userAgent").orEmpty(),
    val referer: String = existing?.extra?.get("referer").orEmpty()) {
    val dirty: Boolean get() = name != existing?.name.orEmpty() || url != existing?.url.orEmpty() ||
        enabled != (existing?.enabled ?: true) || username != existing?.username.orEmpty() || password != existing?.password.orEmpty() ||
        epgUrl != existing?.extra?.get("epgUrl").orEmpty() || userAgent != existing?.extra?.get("userAgent").orEmpty() || referer != existing?.extra?.get("referer").orEmpty()
}
data class SettingsUiState(val sources: List<SourceConfig> = emptyList(), val editor: SourceEditor? = null,
    val saving: Boolean = false, val checking: Boolean = false, val checkedCount: Int = 0,
    val message: SourceFormMessage = SourceFormMessage.NONE)

@HiltViewModel
class SettingsViewModel @Inject constructor(private val sources: SourceRepository) : ViewModel() {
    val setups = sources.urlSetups()
    private val state = MutableStateFlow(SettingsUiState())
    val ui = state.asStateFlow()
    private var checkJob: kotlinx.coroutines.Job? = null
    init { viewModelScope.launch { sources.observeSources().collect { list -> state.update { it.copy(sources = list) } } } }
    fun add(setup: UrlSourceSetup) {
        if (setup in setups && !state.value.saving && !state.value.checking)
            state.update { it.copy(editor = SourceEditor(setup), message = SourceFormMessage.NONE) }
    }
    fun edit(id: String) {
        val config = state.value.sources.firstOrNull { it.id == id && !it.isReadOnly } ?: return
        val setup = setups.firstOrNull { it.type == config.type } ?: return
        if (!state.value.saving && !state.value.checking) state.update { it.copy(editor = SourceEditor(setup, config), message = SourceFormMessage.NONE) }
    }
    fun change(name: String, url: String, enabled: Boolean,
        username: String = state.value.editor?.username.orEmpty(), password: String = state.value.editor?.password.orEmpty(),
        epgUrl: String = state.value.editor?.epgUrl.orEmpty(), userAgent: String = state.value.editor?.userAgent.orEmpty(), referer: String = state.value.editor?.referer.orEmpty()) {
        if (!state.value.saving && !state.value.checking) state.update { it.copy(editor = it.editor?.copy(name = name, url = url, enabled = enabled, username = username, password = password,
            epgUrl = epgUrl, userAgent = userAgent, referer = referer),
            message = SourceFormMessage.NONE) }
    }
    fun cancel() {
        if (state.value.saving) return
        checkJob?.cancel()
        state.update { it.copy(editor = null, checking = false, message = SourceFormMessage.NONE) }
    }
    fun selectFile(uri: String, name: String) {
        val editor = state.value.editor ?: return
        if (editor.setup.fileMimeTypes.isEmpty()) return
        change(editor.name.ifBlank { name }, uri, editor.enabled)
    }
    fun fileFailed() { state.update { it.copy(message = SourceFormMessage.FILE_FAILED) } }
    fun check() {
        if (state.value.saving || state.value.checking) return
        val config = validatedConfig() ?: return
        state.update { it.copy(checking = true, message = SourceFormMessage.NONE) }
        checkJob = viewModelScope.launch {
            try {
                val count = kotlinx.coroutines.withTimeout(20_000) { sources.check(config) }
                state.update { it.copy(checking = false, checkedCount = count,
                    message = if (count == 0) SourceFormMessage.CHECK_EMPTY else SourceFormMessage.CHECKED) }
            } catch (_: kotlinx.coroutines.TimeoutCancellationException) {
                state.update { it.copy(checking = false, message = SourceFormMessage.CHECK_TIMEOUT) }
            } catch (e: CancellationException) { throw e }
            catch (_: Exception) { state.update { it.copy(checking = false, message = SourceFormMessage.CHECK_FAILED) } }
        }
    }
    fun toggleSource(config: SourceConfig) = mutateSource(config.id) { current ->
        sources.upsert(current.copy(enabled = !current.enabled))
    }
    fun removeSource(id: String) = mutateSource(id) { sources.delete(it.id) }
    private fun mutateSource(id: String, mutation: suspend (SourceConfig) -> Unit) {
        if (state.value.saving || state.value.checking || state.value.sources.none { it.id == id && !it.isReadOnly }) return
        // Lock before launching so repeated remote clicks cannot overlap a source mutation.
        state.update { it.copy(saving = true, message = SourceFormMessage.NONE) }
        viewModelScope.launch {
            try {
                val current = checkNotNull(sources.get(id))
                check(!current.isReadOnly)
                mutation(current)
                state.update { it.copy(saving = false) }
            } catch (e: CancellationException) { throw e }
            catch (_: Exception) { state.update { it.copy(saving = false, message = SourceFormMessage.FAILED) } }
        }
    }
    fun delete() {
        val existing = state.value.editor?.existing ?: return
        if (existing.isReadOnly || state.value.saving || state.value.checking) return
        state.update { it.copy(saving = true) }
        viewModelScope.launch {
            try {
                val current = sources.get(existing.id)
                check(current?.isReadOnly != true)
                sources.delete(existing.id)
                state.update { it.copy(editor = null, saving = false, message = SourceFormMessage.NONE) }
            } catch (e: CancellationException) { throw e }
            catch (_: Exception) { state.update { it.copy(saving = false, message = SourceFormMessage.FAILED) } }
        }
    }
    private fun validatedConfig(): SourceConfig? {
        val editor = state.value.editor ?: return null
        val name = editor.name.trim()
        val url = editor.url.trim()
        val validUrl = runCatching { URI(url).let { it.scheme?.lowercase() in editor.setup.schemes && !it.rawAuthority.isNullOrBlank() &&
            (!editor.setup.requiresPath || !it.path.trim('/').isBlank()) && !url.contains('\n') && !url.contains('\r') } }.getOrDefault(false)
        if (name.isBlank() || !validUrl) {
            state.update { it.copy(message = if (name.isBlank()) SourceFormMessage.INVALID_NAME else SourceFormMessage.INVALID_URL) }
            return null
        }
        if (editor.setup.epg && listOf(editor.epgUrl, editor.referer).any { value -> value.isNotBlank() &&
                !runCatching { URI(value.trim()).let { it.scheme in setOf("http", "https") && !it.rawAuthority.isNullOrBlank() } }.getOrDefault(false) } ||
            editor.userAgent.any { it == '\r' || it == '\n' }) {
            state.update { it.copy(message = SourceFormMessage.INVALID_EPG) }; return null
        }
        val extra = editor.existing?.extra.orEmpty().toMutableMap()
        if (editor.setup.epg) {
            mapOf("epgUrl" to editor.epgUrl, "userAgent" to editor.userAgent, "referer" to editor.referer).forEach { (key, value) ->
                if (value.isBlank()) extra.remove(key) else extra[key] = value.trim()
            }
        }
        return SourceConfig(editor.existing?.id ?: UUID.randomUUID().toString(), name, editor.setup.type, url, editor.enabled,
            username = if (editor.setup.credentials) editor.username else editor.existing?.username,
            password = if (editor.setup.credentials) editor.password else editor.existing?.password, extra = extra)
    }
    fun save() {
        val editor = state.value.editor ?: return
        if (state.value.saving || state.value.checking) return
        val config = validatedConfig() ?: return
        state.update { it.copy(saving = true, message = SourceFormMessage.NONE) }
        viewModelScope.launch {
            try {
                val existing = editor.existing?.let { sources.get(it.id) ?: error("订阅已删除") }
                check(existing?.isReadOnly != true)
                sources.upsert(config)
                state.update { it.copy(editor = null, saving = false, message = SourceFormMessage.SAVED) }
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                state.update { it.copy(saving = false, message = SourceFormMessage.FAILED) }
            }
        }
    }
}
