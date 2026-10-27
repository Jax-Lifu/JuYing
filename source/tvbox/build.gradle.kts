plugins {
    alias(libs.plugins.juying.android.library)
    alias(libs.plugins.juying.android.hilt)
    alias(libs.plugins.hilt)
    alias(libs.plugins.chaquopy)
}
android {
    namespace = "com.flytech.juying.source.tvbox"
    defaultConfig {
        ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a") }
        consumerProguardFiles("consumer-rules.pro")
    }
}
chaquopy {
    defaultConfig {
        // Python 3.11 保留老款 32 位机顶盒支持，解释器只在 Spider 进程按需启动。
        version = "3.11"
        pip {
            install("requests==2.32.5")
            install("beautifulsoup4==4.14.3")
            install("lxml==5.3.0")
        }
    }
}
dependencies {
    implementation(project(":core:model"))
    implementation(project(":core:common"))
    implementation(project(":core:network"))
    implementation(project(":source:api"))
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.quickjs)
    // CatVod JAR 将 Gson 留给宿主提供，与 FongMi 的运行时版本保持一致。
    implementation(libs.gson)
}
