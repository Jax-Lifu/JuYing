package com.flytech.juying.feature.settings

import android.os.Bundle
import android.view.View
import android.widget.RadioButton
import androidx.navigation.fragment.findNavController
import com.flytech.juying.core.ui.Appearance
import com.flytech.juying.core.ui.Navigator
import com.flytech.juying.core.ui.ViewBindingFragment
import com.flytech.juying.feature.settings.databinding.FragmentAppearanceBinding
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject
import com.flytech.juying.core.designsystem.R as D

/** 外观与主题偏好设置 Fragment。 */
@AndroidEntryPoint
class AppearanceFragment : ViewBindingFragment<FragmentAppearanceBinding>(FragmentAppearanceBinding::inflate) {
    @Inject lateinit var navigator: Navigator
    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        val languages = listOf(binding.languageSystem to "system", binding.languageHans to "zh-Hans", binding.languageHant to "zh-Hant", binding.languageEnglish to "en")
        val themes = listOf(binding.themeSystem to "system", binding.themeDark to "dark", binding.themeLight to "light", binding.themeBlack to "black")
        fun bind(options: List<Pair<RadioButton, String>>, value: String, save: (String) -> Unit) {
            options.forEach { (button, key) ->
                button.isChecked = value == key
                button.isSelected = value == key
                button.setOnClickListener { if (value != key) { save(key); requireActivity().recreate() } }
            }
        }
        bind(languages, Appearance.language(requireContext())) { Appearance.setLanguage(requireContext(), it) }
        bind(themes, Appearance.theme(requireContext())) { Appearance.setTheme(requireContext(), it) }
        binding.playback.setOnClickListener { findNavController().navigate(R.id.playback_settings) }
        binding.manage.setOnClickListener { navigator.openSourceSettings(this) }
        binding.about.setOnClickListener {
            val context = requireContext()
            val version = context.packageManager.getPackageInfo(context.packageName, 0).versionName.orEmpty()
                .replace(Regex("^(debug|release)_(.+)_(\\d{8})$"), "\$2_\$1_\$3")
            MaterialAlertDialogBuilder(context).setTitle(D.string.ui_about)
                .setMessage("${getString(D.string.ui_about_body)}\n\n$version")
                .setPositiveButton(D.string.ui_close, null).show()
        }
    }
}
