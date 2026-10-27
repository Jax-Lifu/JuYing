plugins {
    alias(libs.plugins.juying.android.library)
    alias(libs.plugins.juying.android.hilt)
}
android { namespace = "com.flytech.juying.core.network" }
dependencies {
    implementation(project(":core:model"))
    implementation(project(":core:common"))
    api(libs.okhttp)
}
