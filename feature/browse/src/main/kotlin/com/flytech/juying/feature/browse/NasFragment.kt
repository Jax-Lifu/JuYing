package com.flytech.juying.feature.browse

import android.os.Bundle
import android.view.View
import androidx.activity.OnBackPressedCallback
import androidx.core.view.isVisible
import androidx.fragment.app.viewModels
import androidx.recyclerview.widget.LinearLayoutManager
import com.flytech.juying.core.model.SourceCapability
import com.flytech.juying.core.ui.MediaRow
import com.flytech.juying.core.ui.MediaRowAdapter
import com.flytech.juying.core.ui.Navigator
import com.flytech.juying.core.ui.ViewBindingFragment
import com.flytech.juying.feature.browse.databinding.FragmentNasBinding
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject
import com.flytech.juying.core.designsystem.R as D

/** 局域网网络存储（SMB/NAS）向导与设备发现 Fragment。 */
@AndroidEntryPoint
class NasFragment : ViewBindingFragment<FragmentNasBinding>(FragmentNasBinding::inflate) {
    private val vm: NasViewModel by viewModels()
    @Inject lateinit var navigator: Navigator

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        val devices = MediaRowAdapter({ row ->
            val device = vm.ui.value.devices.firstOrNull { address(it.host, it.port) == row.id } ?: return@MediaRowAdapter
            val connectedId = vm.connectedSourceIdFor(device)
            if (connectedId != null) {
                navigator.openSource(requireActivity(), connectedId, SourceCapability.BROWSE)
            } else {
                vm.select(device)
            }
        })
        val shares = MediaRowAdapter({ row -> if (!vm.ui.value.busy) vm.connectShare(row.id) })
        binding.devices.apply { layoutManager = LinearLayoutManager(context); adapter = devices; itemAnimator = null }
        binding.shares.apply { layoutManager = LinearLayoutManager(context); adapter = shares; itemAnimator = null }
        var previousStage: NasStage? = null
        var manualExpanded = false
        val back = object : OnBackPressedCallback(false) {
            override fun handleOnBackPressed() { vm.backToDevices() }
        }
        requireActivity().onBackPressedDispatcher.addCallback(viewLifecycleOwner, back)
        binding.back.setOnClickListener { requireActivity().onBackPressedDispatcher.onBackPressed() }
        binding.rescan.setOnClickListener { vm.scan() }
        binding.manualAddress.setOnClickListener { vm.manual() }
        binding.readShares.setOnClickListener {
            vm.login(binding.address.text.toString(), binding.username.text.toString(),
                binding.password.text.toString(), binding.domain.text.toString())
        }
        binding.editLogin.setOnClickListener { vm.editLogin() }
        binding.manualShareToggle.setOnClickListener {
            manualExpanded = true
            binding.manualFields.isVisible = true
            binding.manualShareToggle.isVisible = false
            binding.connectionActions.isVisible = binding.editLogin.isVisible
            binding.manualShare.requestFocus()
        }
        binding.connectShare.setOnClickListener {
            when (vm.ui.value.stage) {
                NasStage.LOGIN -> vm.connectManualShare(binding.address.text.toString(), binding.username.text.toString(),
                    binding.password.text.toString(), binding.domain.text.toString(), binding.manualShare.text.toString())
                NasStage.SHARES -> vm.connectShare(binding.manualShare.text.toString())
                NasStage.DEVICES -> Unit
            }
        }
        launchOnStarted { vm.ui.collect { state ->
            state.connectedSourceId?.let { sourceId ->
                vm.consumeConnection()
                navigator.openSource(requireActivity(), sourceId, SourceCapability.BROWSE)
                return@collect
            }
            val changedStage = previousStage != state.stage
            if (changedStage) {
                manualExpanded = false
                binding.manualShare.setText("")
                if (state.stage == NasStage.DEVICES) {
                    binding.address.setText(""); binding.username.setText("")
                    binding.password.setText(""); binding.domain.setText("")
                } else if (state.stage == NasStage.LOGIN &&
                    (previousStage == NasStage.DEVICES || binding.address.text.isBlank())) {
                    binding.address.setText(state.device?.let { address(it.host, it.port) }.orEmpty())
                }
            }
            back.isEnabled = state.stage != NasStage.DEVICES
            binding.back.setText(if (back.isEnabled) R.string.nas_back_to_scan else D.string.ui_back)
            binding.title.setText(when (state.stage) {
                NasStage.DEVICES -> R.string.nas_devices_title
                NasStage.LOGIN -> R.string.nas_login_title
                NasStage.SHARES -> R.string.nas_shares_title
            })
            binding.devicesPanel.isVisible = state.stage == NasStage.DEVICES
            binding.devices.isVisible = state.stage == NasStage.DEVICES
            binding.loginForm.isVisible = state.stage == NasStage.LOGIN
            binding.shares.isVisible = state.stage == NasStage.SHARES
            binding.editLogin.isVisible = state.stage == NasStage.SHARES
            binding.manualShareToggle.isVisible = !manualExpanded &&
                (state.stage == NasStage.SHARES || state.stage == NasStage.LOGIN && state.error != null)
            binding.connectionActions.isVisible = binding.editLogin.isVisible || binding.manualShareToggle.isVisible
            binding.manualFields.isVisible = manualExpanded && state.stage != NasStage.DEVICES
            binding.progress.isVisible = state.scanning || state.busy
            binding.rescan.isEnabled = !state.scanning
            binding.readShares.isEnabled = !state.busy
            binding.editLogin.isEnabled = !state.busy
            binding.manualShareToggle.isEnabled = !state.busy
            binding.connectShare.isEnabled = !state.busy
            binding.address.isEnabled = !state.busy; binding.username.isEnabled = !state.busy
            binding.password.isEnabled = !state.busy; binding.domain.isEnabled = !state.busy
            binding.manualShare.isEnabled = !state.busy
            binding.address.error = if (state.error == NasError.INVALID_ADDRESS) getString(R.string.nas_invalid_address) else null
            binding.manualShare.error = if (state.error == NasError.INVALID_SHARE && manualExpanded) getString(R.string.nas_invalid_share) else null
            val message = when {
                state.busy -> R.string.nas_connecting
                state.error != null -> when (state.error) {
                    NasError.SCAN_FAILED -> R.string.nas_scan_failed
                    NasError.INVALID_ADDRESS -> R.string.nas_invalid_address
                    NasError.ACCESS_DENIED -> R.string.nas_access_denied
                    NasError.CONNECTION_FAILED -> R.string.nas_connection_failed
                    NasError.INVALID_SHARE -> R.string.nas_invalid_share
                }
                state.scanning -> R.string.nas_scanning
                state.stage == NasStage.DEVICES && state.devices.isEmpty() -> R.string.nas_no_devices
                state.stage == NasStage.SHARES && state.shares.isEmpty() -> R.string.nas_no_shares
                else -> null
            }
            binding.status.isVisible = message != null
            message?.let(binding.status::setText)
            devices.submitList(state.devices.map { device ->
                val location = address(device.host, device.port)
                val connectedId = vm.connectedSourceIdFor(device)
                val isConnected = connectedId != null
                val title = if (isConnected) {
                    "${device.name.ifBlank { location }} (${getString(R.string.nas_connected_tag)})"
                } else {
                    device.name.ifBlank { location }
                }
                val subtitle = if (isConnected) {
                    getString(R.string.nas_connected_hint, location)
                } else {
                    location.takeUnless { it == device.name }.orEmpty()
                }
                val icon = if (isConnected) D.drawable.ic_check else D.drawable.ic_server
                MediaRow(location, title, subtitle, icon)
            })
            shares.submitList(state.shares.map { MediaRow(it, it, getString(R.string.nas_open_share), D.drawable.ic_files) })
            if (changedStage && state.stage == NasStage.LOGIN) {
                if (binding.address.text.isBlank()) binding.address.requestFocus() else binding.username.requestFocus()
            }
            previousStage = state.stage
        } }
    }

    override fun onStart() {
        super.onStart()
        if (vm.ui.value.stage == NasStage.DEVICES && !vm.ui.value.scanning) vm.scan()
    }

    override fun onStop() {
        vm.stopScan()
        super.onStop()
    }

    override fun onDestroyView() {
        binding.devices.adapter = null; binding.shares.adapter = null
        super.onDestroyView()
    }

    private fun address(host: String, port: Int) =
        "${if (':' in host && !host.startsWith('[')) "[$host]" else host}:$port"
}
