plugins {
    alias(libs.plugins.juying.android.library)
    alias(libs.plugins.juying.android.hilt)
}
android { namespace = "com.flytech.juying.source.local" }
dependencies {
    implementation(project(":core:model"))
    implementation(project(":core:common"))
    implementation(project(":source:api"))
    testImplementation("org.robolectric:robolectric:4.16.1")
}
