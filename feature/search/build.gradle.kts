plugins {
    alias(libs.plugins.juying.android.feature)
}
android { namespace = "com.flytech.juying.feature.search" }
dependencies { testImplementation(project(":core:testing")) }
