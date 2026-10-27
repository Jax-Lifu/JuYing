plugins {
    alias(libs.plugins.juying.android.library)
    alias(libs.plugins.juying.android.hilt)
}
android { namespace = "com.flytech.juying.core.domain" }
dependencies {
    api(project(":core:model"))
    implementation(project(":core:data"))
}
