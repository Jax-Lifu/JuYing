plugins {
    alias(libs.plugins.juying.android.library)
    alias(libs.plugins.juying.android.hilt)
}
android { namespace = "com.flytech.juying.player.media3" }
dependencies {
    implementation(project(":core:model"))
    implementation(project(":core:common"))
    implementation(project(":core:network"))
    implementation(project(":player:api"))
    implementation(libs.androidx.core.ktx)
    implementation(libs.media3.common)
    implementation(libs.media3.ui)
    implementation(libs.media3.exoplayer)
    implementation(libs.media3.exoplayer.hls)
    implementation(libs.media3.exoplayer.dash)
    implementation(libs.media3.datasource)
    implementation(libs.media3.datasource.okhttp)
    testImplementation("org.robolectric:robolectric:4.16.1")
}

kotlin {
    compilerOptions { optIn.add("androidx.media3.common.util.UnstableApi") }
}
