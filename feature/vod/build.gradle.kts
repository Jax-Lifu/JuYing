plugins {
    alias(libs.plugins.juying.android.feature)
}
android { namespace = "com.flytech.juying.feature.vod" }
dependencies { testImplementation(project(":core:testing")) }
