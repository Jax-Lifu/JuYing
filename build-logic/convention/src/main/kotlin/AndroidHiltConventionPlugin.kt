import org.gradle.api.Plugin
import org.gradle.api.Project
import org.gradle.kotlin.dsl.dependencies

class AndroidHiltConventionPlugin : Plugin<Project> {
    override fun apply(target: Project) {
        with(target) {
            with(pluginManager) {
                apply("com.google.devtools.ksp")
                // 编译提速：仅在包含 Activity/Fragment/ViewModel (@AndroidEntryPoint / @HiltViewModel) 的模块
                // 挂载 Hilt Gradle 插件执行 ASM 字节码插桩；纯数据/源模块仅需 KSP 注解处理器即可。
                if (path == ":app" || path.startsWith(":feature:")) {
                    apply("com.google.dagger.hilt.android")
                }
            }
            dependencies {
                add("implementation", lib("hilt-android"))
                add("ksp", lib("hilt-compiler"))
            }
        }
    }
}
