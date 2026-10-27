plugins {
    alias(libs.plugins.juying.android.feature)
}
android { namespace = "com.flytech.juying.feature.player" }
dependencies {
    implementation(project(":player:api"))
    testImplementation(project(":core:testing"))
    testImplementation(project(":core:datastore"))
    testImplementation("org.robolectric:robolectric:4.16.1")
}
