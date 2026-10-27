plugins {
    alias(libs.plugins.juying.android.library)
}
android {
    namespace = "com.flytech.juying.core.ui"
    buildFeatures { viewBinding = true }
}
dependencies {
    api(project(":core:model"))
    implementation(project(":core:designsystem"))
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.androidx.fragment.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.recyclerview)
    implementation(libs.coil)
}
