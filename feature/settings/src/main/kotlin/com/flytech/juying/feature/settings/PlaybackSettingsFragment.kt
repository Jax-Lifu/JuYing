package com.flytech.juying.feature.settings

import android.os.Bundle
import android.view.View
import androidx.lifecycle.lifecycleScope
import androidx.navigation.fragment.findNavController
import com.flytech.juying.core.data.SettingsRepository
import com.flytech.juying.core.model.DecoderMode
import com.flytech.juying.core.ui.ViewBindingFragment
import com.flytech.juying.feature.settings.databinding.FragmentPlaybackSettingsBinding
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject
import kotlinx.coroutines.launch
import com.flytech.juying.core.designsystem.R as D

@AndroidEntryPoint
class PlaybackSettingsFragment : ViewBindingFragment<FragmentPlaybackSettingsBinding>(FragmentPlaybackSettingsBinding::inflate) {
    @Inject lateinit var settings: SettingsRepository
    private var rendering = false
    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        binding.back.setOnClickListener { findNavController().popBackStack() }
        binding.decoder.setOnClickListener {
            MaterialAlertDialogBuilder(requireContext()).setTitle(D.string.ui_playback)
                .setItems(arrayOf(getString(D.string.ui_hardware), getString(D.string.ui_software))) { _, index ->
                    viewLifecycleOwner.lifecycleScope.launch { settings.setDecoderMode(DecoderMode.entries[index]) }
                }.show()
        }
        binding.frameRate.setOnCheckedChangeListener { _, checked ->
            if (!rendering) viewLifecycleOwner.lifecycleScope.launch { settings.setAutoFrameRate(checked) }
        }
        launchOnStarted { settings.settings.collect {
            rendering = true
            binding.decoder.setText(if (it.decoderMode == DecoderMode.HARDWARE_FIRST) D.string.ui_hardware else D.string.ui_software)
            binding.frameRate.isChecked = it.autoFrameRate
            rendering = false
        } }
    }
}
