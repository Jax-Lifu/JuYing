import org.gradle.api.JavaVersion
import org.gradle.api.Plugin
import org.gradle.api.Project
import org.gradle.api.plugins.JavaPluginExtension
import org.gradle.kotlin.dsl.configure
import org.gradle.kotlin.dsl.dependencies

/** 纯 Kotlin 模块（无 Android 依赖），编译快、可直接跑单元测试。 */
class JvmLibraryConventionPlugin : Plugin<Project> {
    override fun apply(target: Project) {
        with(target) {
            with(pluginManager) {
                apply("org.jetbrains.kotlin.jvm")
                apply("org.jetbrains.kotlin.plugin.serialization")
            }
            extensions.configure<JavaPluginExtension> {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
            configureKotlinJvmTarget()
            dependencies {
                add("implementation", lib("kotlinx-coroutines-core"))
                add("testImplementation", lib("junit"))
                add("testImplementation", lib("kotlinx-coroutines-test"))
            }
        }
    }
}
