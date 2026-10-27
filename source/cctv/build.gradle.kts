plugins {
    alias(libs.plugins.juying.android.library)
    alias(libs.plugins.juying.android.hilt)
}
android {
    namespace = "com.flytech.juying.source.cctv"
    ndkVersion = "28.2.13676358"
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }
}
dependencies {
    implementation(project(":core:model"))
    implementation(project(":core:common"))
    implementation(project(":core:network"))
    implementation(project(":source:api"))
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.media3.common)
    implementation(libs.media3.datasource)
    testImplementation("org.robolectric:robolectric:4.16.1")
}

kotlin {
    compilerOptions { optIn.add("androidx.media3.common.util.UnstableApi") }
}
