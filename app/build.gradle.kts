import com.android.build.gradle.internal.api.ApkVariantOutputImpl
import java.time.LocalDate
import java.time.format.DateTimeFormatter

plugins {
    alias(libs.plugins.juying.android.application)
    alias(libs.plugins.juying.android.hilt)
}

val appDisplayName = "JuYing"
val baseVersionName = "0.1.0"
val buildDate: String = LocalDate.now().format(DateTimeFormatter.ofPattern("yyyyMMdd"))

android {
    namespace = "com.flytech.juying"

    defaultConfig {
        applicationId = "com.flytech.juying"
        versionCode = 1
        versionName = baseVersionName
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // 只打主流电视/手机架构，减小体积
        ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a") }
    }

    buildFeatures { viewBinding = false }

    buildTypes {
        debug {
            // 版本号默认格式：debug_版本_日期（如 debug_0.1.0_20261024）
            versionNameSuffix = ""
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            // 默认回退使用 debug 签名以便直接真机验证 Release R8 包；CI 可通过环境变量覆盖正式签名
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    // 统一产物命名与版本号：
    // 1. versionName = "{debug|release}_{版本}_{日期}"（如 debug_0.1.0_20261024）
    // 2. APK 文件名   = "JuYing_{debug|release}_{版本}_{日期}.apk"（如 JuYing_debug_0.1.0_20261024.apk）
    // 3. 编译完成后自动归档至根目录 dist/<子目录>/（可通过 -PdistMode=version|date|version_date 切换，默认 v{版本}_{日期}）
    applicationVariants.configureEach {
        val buildTypeName = buildType.name
        val fullVersionName = "${buildTypeName}_${baseVersionName}_${buildDate}"
        val apkFileName = "${appDisplayName}_${fullVersionName}.apk"
        outputs.configureEach {
            if (this is ApkVariantOutputImpl) {
                versionNameOverride = fullVersionName
                outputFileName = apkFileName
            }
        }

        val distMode = providers.gradleProperty("distMode").orElse("version_date").get().lowercase()
        val distSubFolder = when (distMode) {
            "version" -> "v${baseVersionName}"
            "date" -> buildDate
            else -> "v${baseVersionName}_${buildDate}"
        }
        val distDir = rootProject.layout.projectDirectory.dir("dist/$distSubFolder").asFile
        val apkSourceFile = layout.buildDirectory.file("outputs/apk/$buildTypeName/$apkFileName").get().asFile
        val mappingSourceFile = layout.buildDirectory.file("outputs/mapping/$buildTypeName/mapping.txt").get().asFile
        val isReleaseVariant = (buildTypeName == "release")
        val targetApkFile = File(distDir, apkFileName)
        val targetMappingFile = File(distDir, "${appDisplayName}_${fullVersionName}_mapping.txt")

        assembleProvider.configure {
            doLast {
                distDir.mkdirs()
                if (apkSourceFile.exists()) {
                    apkSourceFile.copyTo(targetApkFile, overwrite = true)
                    println("==> [Dist] APK -> ${targetApkFile.absolutePath}")
                }
                if (isReleaseVariant && mappingSourceFile.exists()) {
                    mappingSourceFile.copyTo(targetMappingFile, overwrite = true)
                    println("==> [Dist] R8 Mapping -> ${targetMappingFile.absolutePath}")
                }
            }
        }
    }

    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }

    packaging {
        resources.excludes += setOf("/META-INF/{AL2.0,LGPL2.1}", "META-INF/DEPENDENCIES", "META-INF/INDEX.LIST")
    }
}

dependencies {
    // QuickJS 的运行库带有 Kotlin 2.4 元数据，Hilt 聚合处理器需使用对应读取器。
    annotationProcessor(libs.kotlin.metadata.jvm)
    implementation(project(":core:model"))
    implementation(project(":core:common"))
    implementation(project(":core:network"))
    implementation(project(":core:data"))
    implementation(project(":core:ui"))
    implementation(project(":core:designsystem"))

    implementation(project(":player:api"))
    // 播放内核：想换内核，只改这一行（并提供另一个 PlayerEngineFactory）
    implementation(project(":player:media3"))

    // 数据源：新增一个数据源 = 新建模块 + 在这里加一行
    implementation(project(":source:cctv"))
    implementation(project(":source:iptv"))
    implementation(project(":source:tvbox"))
    implementation(project(":source:smb"))
    implementation(project(":source:local"))

    implementation(project(":feature:home"))
    implementation(project(":feature:live"))
    implementation(project(":feature:vod"))
    implementation(project(":feature:browse"))
    implementation(project(":feature:search"))
    implementation(project(":feature:history"))
    implementation(project(":feature:settings"))
    implementation(project(":feature:player"))

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.androidx.fragment.ktx)
    implementation(libs.androidx.recyclerview)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.navigation.fragment.ktx)
    implementation(libs.androidx.navigation.ui.ktx)
    implementation(libs.androidx.profileinstaller)
    implementation(libs.material)
    implementation(libs.androidx.constraintlayout)
    implementation(libs.okhttp)
    implementation(libs.coil)
    androidTestImplementation(project(":source:api"))
    androidTestImplementation(project(":core:database"))
    androidTestImplementation(project(":core:datastore"))
    androidTestImplementation(libs.room.runtime)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.junit)
    androidTestImplementation(libs.okhttp.mockwebserver)
    androidTestImplementation(libs.media3.datasource)
}
