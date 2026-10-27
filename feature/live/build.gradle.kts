plugins {
    alias(libs.plugins.juying.android.feature)
}
android { namespace = "com.flytech.juying.feature.live" }
dependencies {
    testImplementation(project(":core:testing"))
}
