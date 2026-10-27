plugins {
    alias(libs.plugins.juying.android.library)
    alias(libs.plugins.juying.android.hilt)
    alias(libs.plugins.juying.android.room)
}
android { namespace = "com.flytech.juying.core.database" }
dependencies {
    implementation(project(":core:model"))
}
