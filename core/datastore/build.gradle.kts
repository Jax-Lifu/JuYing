plugins {
    alias(libs.plugins.juying.android.library)
    alias(libs.plugins.juying.android.hilt)
}
android { namespace = "com.flytech.juying.core.datastore" }
dependencies {
    implementation(project(":core:model"))
    implementation(libs.androidx.datastore.preferences)
}
