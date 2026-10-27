plugins {
    alias(libs.plugins.juying.android.feature)
}
android { namespace = "com.flytech.juying.feature.settings" }
dependencies { testImplementation(project(":core:testing")) }
