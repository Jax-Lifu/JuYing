plugins {
    alias(libs.plugins.juying.android.feature)
}
android { namespace = "com.flytech.juying.feature.home" }
dependencies {
    testImplementation(project(":core:testing"))
}
