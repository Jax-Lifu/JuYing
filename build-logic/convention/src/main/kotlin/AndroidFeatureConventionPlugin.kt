import com.android.build.api.dsl.LibraryExtension
import org.gradle.api.GradleException
import org.gradle.api.Plugin
import org.gradle.api.Project
import org.gradle.api.artifacts.ProjectDependency
import org.gradle.kotlin.dsl.configure
import org.gradle.kotlin.dsl.dependencies

/**
 * feature 模块约定：
 *  - 只依赖 core:*（及 player:api），不依赖其他 feature、source:*、player:media3；
 *  - 开启 ViewBinding，统一引入 View 体系所需依赖。
 * 违反依赖规则会在配置阶段直接报错，保证模块边界。
 */
class AndroidFeatureConventionPlugin : Plugin<Project> {
    override fun apply(target: Project) {
        with(target) {
            with(pluginManager) {
                apply("juying.android.library")
                apply("juying.android.hilt")
            }
            extensions.configure<LibraryExtension> {
                buildFeatures { viewBinding = true }
            }
            dependencies {
                add("implementation", project(":core:model"))
                add("implementation", project(":core:common"))
                add("implementation", project(":core:data"))
                add("implementation", project(":core:domain"))
                add("implementation", project(":core:ui"))
                add("implementation", project(":core:designsystem"))

                add("implementation", lib("androidx-core-ktx"))
                add("implementation", lib("androidx-appcompat"))
                add("implementation", lib("androidx-fragment-ktx"))
                add("implementation", lib("androidx-lifecycle-viewmodel-ktx"))
                add("implementation", lib("androidx-lifecycle-runtime-ktx"))
                add("implementation", lib("androidx-recyclerview"))
                add("implementation", lib("androidx-constraintlayout"))
                add("implementation", lib("androidx-navigation-fragment-ktx"))
                add("implementation", lib("androidx-navigation-ui-ktx"))
                add("implementation", lib("material"))
            }
            afterEvaluate {
                val forbidden = listOf(":feature:", ":source:", ":player:media3")
                configurations.flatMap { it.dependencies }
                    .filterIsInstance<ProjectDependency>()
                    .forEach { dep ->
                        val p = dep.path
                        if (p != path && forbidden.any { p.startsWith(it) }) {
                            throw GradleException(
                                "模块依赖违规: $path 不能依赖 $p（feature 只能依赖 core:* 与 player:api）",
                            )
                        }
                    }
            }
        }
    }
}
