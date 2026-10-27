plugins {
    alias(libs.plugins.juying.android.feature)
}
android { namespace = "com.flytech.juying.feature.browse" }

dependencies {
    testImplementation(project(":core:testing"))
    testImplementation("org.robolectric:robolectric:4.16.1")
}
