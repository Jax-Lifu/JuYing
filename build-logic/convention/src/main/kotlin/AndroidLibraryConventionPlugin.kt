import com.android.build.api.dsl.LibraryExtension
import org.gradle.api.Plugin
import org.gradle.api.Project
import org.gradle.kotlin.dsl.configure
import org.gradle.kotlin.dsl.dependencies

class AndroidLibraryConventionPlugin : Plugin<Project> {
    override fun apply(target: Project) {
        with(target) {
            with(pluginManager) {
                apply("com.android.library")
                apply("org.jetbrains.kotlin.android")
                apply("org.jetbrains.kotlin.plugin.serialization")
            }
            extensions.configure<LibraryExtension> {
                configureKotlinAndroid(this)
            }
            dependencies {
                add("implementation", lib("kotlinx-coroutines-android"))
                add("implementation", lib("timber"))
                add("testImplementation", lib("junit"))
                add("testImplementation", lib("kotlinx-coroutines-test"))
                add("testImplementation", lib("turbine"))
            }
        }
    }
}
