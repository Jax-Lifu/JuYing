plugins {
    alias(libs.plugins.juying.android.library)
}
android { namespace = "com.flytech.juying.core.testing" }
dependencies {
    api(project(":core:model"))
    api(project(":core:data"))
    api(libs.junit)
    api(libs.kotlinx.coroutines.test)
    api(libs.turbine)
}
