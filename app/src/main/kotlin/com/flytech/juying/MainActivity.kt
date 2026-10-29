package com.flytech.juying

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.KeyEvent
import android.view.View
import android.widget.Button
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.isVisible
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.navigation.fragment.NavHostFragment
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.navOptions
import androidx.navigation.ui.setupWithNavController
import com.flytech.juying.core.data.SourceBrowseMemory
import com.flytech.juying.core.data.SourceRepository
import com.flytech.juying.core.model.PlayRequest
import com.flytech.juying.core.model.SourceCapability
import com.flytech.juying.core.ui.FocusTarget
import com.flytech.juying.core.ui.JuyingActivity
import com.flytech.juying.core.ui.NavigationGuard
import com.flytech.juying.core.ui.Navigator
import com.flytech.juying.core.ui.SourcePickerHost
import com.flytech.juying.core.ui.findFirstFocusable
import com.google.android.material.navigation.NavigationBarView
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import com.flytech.juying.core.designsystem.R as D

/** 单 Activity 架构主界面宿主，承载全局 Fragment 导航视图容器与遥控按键分发。 */
@AndroidEntryPoint
class MainActivity : JuyingActivity(), SourcePickerHost {
    @Inject lateinit var navigator: Navigator
    @Inject lateinit var sources: SourceRepository
    @Inject lateinit var memory: SourceBrowseMemory
    private lateinit var host: NavHostFragment
    private var currentSource: String? = null
    private val storagePermission = registerForActivityResult(androidx.activity.result.contract.ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) host.childFragmentManager.setFragmentResult(Navigator.STORAGE_ACCESS_RESULT, Bundle.EMPTY)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        setContentView(R.layout.activity_main)
        ViewCompat.setOnApplyWindowInsetsListener(findViewById(R.id.shell)) { view, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
            // Let adjustPan reveal the focused input without collapsing forms on short landscape screens.
            view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            insets
        }
        host = supportFragmentManager.findFragmentById(R.id.nav_host) as NavHostFragment
        val nav = findViewById<NavigationBarView>(R.id.nav_bar)
        nav.setupWithNavController(host.navController)
        nav.setOnItemSelectedListener { item ->
            val page = host.childFragmentManager.primaryNavigationFragment
            fun navigate(): Boolean {
                // 扁平导航图会把整段子页栈映射给首页；各入口直达总览，浏览位置由页面单独保存。
                host.navController.navigate(item.itemId, null, navOptions {
                    launchSingleTop = true
                    restoreState = false
                    popUpTo(host.navController.graph.findStartDestination().id) { saveState = false }
                })
                focusCurrentContent()
                return true
            }
            if (page is NavigationGuard) { page.confirmLeave { navigate() }; false } else navigate()
        }
        nav.setOnItemReselectedListener {
            focusCurrentContent()
        }
        findViewById<View>(R.id.source_switch).setOnClickListener { guarded { navigator.showSourcePicker(this, currentSource) } }
        findViewById<View>(R.id.global_search).setOnClickListener { guarded { host.navController.navigate(R.id.search) } }
        findViewById<View>(R.id.global_history).setOnClickListener { guarded { host.navController.navigate(R.id.history) } }
        val rootTabs = setOf(
            R.id.nav_home, R.id.nav_live, R.id.nav_vod, R.id.nav_browse, R.id.nav_settings
        )
        host.navController.addOnDestinationChangedListener { _, destination, _ ->
            val isRoot = destination.id in rootTabs
            findViewById<View>(R.id.nav_bar)?.isVisible = isRoot
            updateHeader()
        }
        host.childFragmentManager.registerFragmentLifecycleCallbacks(object : androidx.fragment.app.FragmentManager.FragmentLifecycleCallbacks() {
            override fun onFragmentResumed(fm: androidx.fragment.app.FragmentManager, f: androidx.fragment.app.Fragment) {
                val nav = findViewById<NavigationBarView?>(R.id.nav_bar)
                val focused = currentFocus
                if (focused == null || (nav != null && isChildOf(focused, nav))) {
                    focusCurrentContent()
                }
            }
        }, true)
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                combine(sources.observeSources(), memory.updates) { configs, _ -> configs }.collect { updateHeader() }
            }
        }
        if (savedInstanceState == null) {
            handleIntent(intent)
            findViewById<View>(R.id.nav_host)?.postDelayed({ focusCurrentContent() }, 300)
        }
    }

    fun focusCurrentContent() {
        val navHostView = findViewById<View>(R.id.nav_host) ?: return
        fun doFocus() {
            if (navHostView.hasFocus()) return
            val currentFragment = host.childFragmentManager.primaryNavigationFragment
                ?: host.childFragmentManager.fragments.firstOrNull { it.isVisible }
            if (currentFragment is FocusTarget && currentFragment.requestPrimaryFocus()) return
            val target = navHostView.findFirstFocusable()
            target?.requestFocus()
        }
        navHostView.post { doFocus() }
        navHostView.postDelayed({ doFocus() }, 100)
        navHostView.postDelayed({ doFocus() }, 300)
    }

    private fun guarded(proceed: () -> Unit) {
        val page = host.childFragmentManager.primaryNavigationFragment
        if (page is NavigationGuard) page.confirmLeave(proceed) else proceed()
    }
    internal val currentSourceCapability: SourceCapability?
        get() = when (host.navController.currentDestination?.id) {
            R.id.nav_live -> SourceCapability.LIVE
            R.id.nav_vod, R.id.vod_detail -> SourceCapability.VOD
            R.id.nav_browse -> SourceCapability.BROWSE
            else -> null
        }
    private fun updateHeader() {
        currentSource = currentSourceCapability?.let(memory::selected)
        val selected = currentSource
        lifecycleScope.launch {
            val source = selected?.let { sources.get(it) }
            if (selected == currentSource) findViewById<Button>(R.id.source_switch).apply {
                text = source?.name ?: getString(D.string.ui_all_sources)
                contentDescription = "$text, ${getString(D.string.ui_switch_source)}"
            }
        }
    }
    fun requestStorageAccess() {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.R) {
            storagePermission.launch(android.Manifest.permission.READ_EXTERNAL_STORAGE)
            return
        }
        val settings = Intent(android.provider.Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
            android.net.Uri.parse("package:$packageName"))
        try { startActivity(settings) }
        catch (_: android.content.ActivityNotFoundException) {
            try { startActivity(Intent(android.provider.Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)) }
            catch (_: android.content.ActivityNotFoundException) {
                com.google.android.material.dialog.MaterialAlertDialogBuilder(this)
                    .setMessage(D.string.ui_storage_permission_missing).setPositiveButton(D.string.ui_close, null).show()
            }
        }
    }
    fun openSource(capability: SourceCapability) {
        val destination = when (capability) {
            SourceCapability.LIVE -> R.id.nav_live
            SourceCapability.VOD -> R.id.nav_vod
            else -> R.id.nav_browse
        }
        guarded {
            if (host.navController.currentDestination?.id == R.id.nas) {
                // Reconnecting the selected share must leave the storage chooser and restore its directory.
                host.navController.navigate(destination, null, androidx.navigation.NavOptions.Builder()
                    .setPopUpTo(R.id.nav_browse, true).build())
            } else if (host.navController.currentDestination?.id != destination) host.navController.navigate(destination)
            updateHeader()
        }
    }
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); handleIntent(intent) }
    private fun handleIntent(intent: Intent) {
        if (intent.getBooleanExtra("manage_sources", false)) host.navController.navigate(R.id.sources)
        intent.getStringExtra("source_capability")?.let { value ->
            runCatching { SourceCapability.valueOf(value) }.getOrNull()?.let(::openSource)
        }
    }
    override fun playFromPicker(request: PlayRequest) = navigator.openPlayer(this, request)
    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (keyCode == KeyEvent.KEYCODE_MENU) { guarded { navigator.showSourcePicker(this, currentSource) }; return true }
        val nav = findViewById<NavigationBarView?>(R.id.nav_bar)
        if (nav != null && nav.isVisible) {
            val focused = currentFocus
            // 遥控器在左侧导航栏按“向右”键时，直接聚焦到当前主内容区
            if (keyCode == KeyEvent.KEYCODE_DPAD_RIGHT && focused != null && isChildOf(focused, nav)) {
                focusCurrentContent()
                return true
            }
            // 遥控器在主内容区按“向左”键回退到导航栏时，精准对齐到当前选中的栏目，避免因纵向坐标跳跃到其他栏目
            if (keyCode == KeyEvent.KEYCODE_DPAD_LEFT && focused != null && !isChildOf(focused, nav)) {
                val next = focused.focusSearch(View.FOCUS_LEFT)
                if (next == null || isChildOf(next, nav)) {
                    val activeItem = nav.findViewById<View>(nav.selectedItemId)
                    if (activeItem != null && activeItem.requestFocus()) return true
                }
            }
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean {
        val nav = findViewById<NavigationBarView?>(R.id.nav_bar)
        if (nav != null && nav.isVisible) {
            val focused = currentFocus
            if (focused != null && isChildOf(focused, nav)) {
                if (keyCode == KeyEvent.KEYCODE_DPAD_CENTER || keyCode == KeyEvent.KEYCODE_ENTER) {
                    focusCurrentContent()
                }
            }
        }
        return super.onKeyUp(keyCode, event)
    }

    private fun isChildOf(view: View, parent: View): Boolean {
        var current: Any? = view
        while (current != null) {
            if (current === parent) return true
            current = (current as? View)?.parent
        }
        return false
    }

    companion object {
        fun sourceIntent(context: Context, capability: SourceCapability) = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP).putExtra("source_capability", capability.name)
        fun sourcesIntent(context: Context) = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP).putExtra("manage_sources", true)
    }
}
