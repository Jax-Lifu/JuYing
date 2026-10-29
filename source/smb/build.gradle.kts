plugins {
    alias(libs.plugins.juying.android.library)
    alias(libs.plugins.juying.android.hilt)
}
android {
    namespace = "com.flytech.juying.source.smb"
    defaultConfig { consumerProguardFiles("consumer-rules.pro") }
}
dependencies {
    implementation(project(":core:model"))
    implementation(project(":core:common"))
    implementation(project(":source:api"))
    implementation(libs.smbj)
    implementation(libs.dcerpc)
    implementation(libs.media3.common)
    implementation(libs.media3.datasource)
    implementation(libs.coil)
    testImplementation("org.robolectric:robolectric:4.16.1")
}

kotlin {
    compilerOptions { optIn.add("androidx.media3.common.util.UnstableApi") }
}
