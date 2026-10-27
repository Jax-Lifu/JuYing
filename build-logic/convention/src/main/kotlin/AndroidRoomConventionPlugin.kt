import com.google.devtools.ksp.gradle.KspExtension
import org.gradle.api.Plugin
import org.gradle.api.Project
import org.gradle.kotlin.dsl.configure
import org.gradle.kotlin.dsl.dependencies

class AndroidRoomConventionPlugin : Plugin<Project> {
    override fun apply(target: Project) {
        with(target) {
            pluginManager.apply("com.google.devtools.ksp")
            dependencies {
                add("implementation", lib("room-runtime"))
                add("implementation", lib("room-ktx"))
                add("ksp", lib("room-compiler"))
            }
        }
    }
}
