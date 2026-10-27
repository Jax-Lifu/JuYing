plugins {
    alias(libs.plugins.juying.android.library)
    alias(libs.plugins.juying.android.hilt)
}
android { namespace = "com.flytech.juying.player.api" }
dependencies {
    api(project(":core:model"))
    implementation(project(":core:datastore"))
}
