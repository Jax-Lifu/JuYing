import com.android.build.api.dsl.CommonExtension
import org.gradle.api.JavaVersion
import org.gradle.api.Project
import org.gradle.api.artifacts.VersionCatalog
import org.gradle.api.artifacts.VersionCatalogsExtension
import org.gradle.kotlin.dsl.getByType
import org.gradle.kotlin.dsl.withType
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

internal const val COMPILE_SDK = 36
internal const val TARGET_SDK = 35
/** 项目最低支持 Android 9 (API 28)。 */
internal const val MIN_SDK = 28

internal val Project.libs: VersionCatalog
    get() = extensions.getByType<VersionCatalogsExtension>().named("libs")

internal fun Project.lib(alias: String) = libs.findLibrary(alias).get()

internal fun Project.configureKotlinAndroid(ext: CommonExtension<*, *, *, *, *, *>) {
    ext.apply {
        compileSdk = COMPILE_SDK
        defaultConfig.minSdk = MIN_SDK
        compileOptions {
            sourceCompatibility = JavaVersion.VERSION_17
            targetCompatibility = JavaVersion.VERSION_17
        }
    }
    configureKotlinJvmTarget()
}

internal fun Project.configureKotlinJvmTarget() {
    tasks.withType<KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
            allWarningsAsErrors.set(false)
            freeCompilerArgs.addAll(
                "-Xmetadata-version=2.2.0",
                "-Xannotation-default-target=param-property",
            )
        }
    }
}
