pluginManagement {
    // 运行时依赖含 Kotlin 2.4 metadata，需要比 AGP 8.13 内置版本更新的 R8。
    buildscript {
        repositories {
            google()
            mavenCentral()
        }
        dependencies {
            classpath("com.android.tools:r8:9.1.57")
        }
    }
    includeBuild("build-logic")
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "juying"

include(":app")

include(":core:model", ":core:common", ":core:network", ":core:database", ":core:datastore")
include(":core:data", ":core:domain", ":core:designsystem", ":core:ui", ":core:testing")

include(":player:api", ":player:media3")

include(":source:api", ":source:cctv", ":source:iptv", ":source:tvbox", ":source:smb", ":source:local")

include(
    ":feature:home", ":feature:live", ":feature:vod", ":feature:browse",
    ":feature:search", ":feature:history", ":feature:settings", ":feature:player",
)
