plugins {
    alias(libs.plugins.juying.android.library)
    alias(libs.plugins.juying.android.hilt)
}
android { namespace = "com.flytech.juying.source.iptv" }
dependencies {
    implementation(project(":core:model"))
    implementation(project(":core:common"))
    implementation(project(":core:network"))
    implementation(project(":source:api"))
}
