plugins {
    alias(libs.plugins.juying.android.library)
}
android { namespace = "com.flytech.juying.core.designsystem" }
dependencies {
    api(libs.material)
    api(libs.androidx.appcompat)
}
