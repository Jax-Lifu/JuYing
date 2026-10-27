plugins {
    alias(libs.plugins.juying.android.library)
    alias(libs.plugins.juying.android.hilt)
}
android { namespace = "com.flytech.juying.core.common" }
dependencies {
    implementation(project(":core:model"))
    implementation(libs.androidx.core.ktx)
}
