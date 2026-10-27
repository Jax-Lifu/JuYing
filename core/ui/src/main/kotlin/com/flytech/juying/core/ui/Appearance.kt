package com.flytech.juying.core.ui

import android.content.Context
import android.content.res.Configuration
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import com.flytech.juying.core.designsystem.R
import java.util.Locale

/** Presentation preferences are independent of playback and source configuration. */
object Appearance {
    private fun prefs(context: Context) = context.getSharedPreferences("appearance", Context.MODE_PRIVATE)
    fun language(context: Context): String = prefs(context).getString("language", "zh-Hans") ?: "zh-Hans"
    fun theme(context: Context): String = prefs(context).getString("theme", "dark") ?: "dark"
    fun setLanguage(context: Context, value: String) { prefs(context).edit().putString("language", value).apply() }
    fun setTheme(context: Context, value: String) { prefs(context).edit().putString("theme", value).apply() }

    fun localize(context: Context): Context {
        val tag = language(context)
        if (tag == "system") return context
        val config = Configuration(context.resources.configuration)
        config.setLocale(Locale.forLanguageTag(tag))
        return context.createConfigurationContext(config)
    }

    fun style(context: Context): Int = when (theme(context)) {
        "light" -> R.style.Theme_Juying_Light
        "black" -> R.style.Theme_Juying_Black
        "system" -> if (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_NO)
            R.style.Theme_Juying_Light else R.style.Theme_Juying
        else -> R.style.Theme_Juying
    }
}

abstract class JuyingActivity : AppCompatActivity() {
    override fun attachBaseContext(newBase: Context) = super.attachBaseContext(Appearance.localize(newBase))
    override fun onCreate(savedInstanceState: Bundle?) {
        setTheme(Appearance.style(this))
        super.onCreate(savedInstanceState)
    }
}
