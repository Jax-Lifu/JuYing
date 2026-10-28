plugins {
    alias(libs.plugins.juying.android.library)
    alias(libs.plugins.juying.android.hilt)
    alias(libs.plugins.hilt)
    alias(libs.plugins.chaquopy)
}
android {
    namespace = "com.flytech.juying.source.tvbox"
    defaultConfig {
        ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a") }
        consumerProguardFiles("consumer-rules.pro")
    }
}
fun findPython311(): String? {
    // 0. 最高优先级：当前项目根目录的 uv 虚拟环境 (.venv)
    val projectVenv = listOf(
        rootProject.file(".venv/Scripts/python.exe"),
        rootProject.file(".venv/bin/python")
    ).firstOrNull { it.exists() }
    if (projectVenv != null) return projectVenv.absolutePath

    val envCandidate = System.getenv("PYTHON_311") ?: System.getenv("CHAQUOPY_PYTHON")
    if (!envCandidate.isNullOrBlank() && file(envCandidate).exists()) return envCandidate

    val appData = System.getenv("APPDATA")
    if (!appData.isNullOrBlank()) {
        val uvDir = File(appData, "uv/python")
        if (uvDir.exists()) {
            val py311 = uvDir.listFiles()?.firstOrNull { it.isDirectory && it.name.startsWith("cpython-3.11") }
            val exe = if (py311 != null) File(py311, "python.exe") else null
            if (exe != null && exe.exists()) return exe.absolutePath
        }
    }

    val candidates = listOf(
        File(System.getenv("LOCALAPPDATA") ?: "", "Programs/Python/Python311/python.exe"),
        File("C:/Program Files/Python311/python.exe"),
        File("C:/Python311/python.exe"),
        File("/usr/bin/python3.11"),
        File("/usr/local/bin/python3.11")
    )
    for (candidate in candidates) {
        if (candidate.exists()) return candidate.absolutePath
    }

    try {
        val process = ProcessBuilder("uv", "python", "find", "3.11").start()
        val path = process.inputStream.bufferedReader().readLine()?.trim()
        if (process.waitFor() == 0 && !path.isNullOrBlank() && File(path).exists()) {
            return path
        }
    } catch (_: Exception) {}

    return null
}

chaquopy {
    defaultConfig {
        // Python 3.11 保留老款 32 位机顶盒支持，解释器只在 Spider 进程按需启动。
        version = "3.11"
        val py311 = findPython311()
        if (py311 != null) {
            buildPython(py311)
        }
        pip {
            install("requests==2.32.5")
            install("beautifulsoup4==4.14.3")
            install("lxml==5.3.0")
        }
    }
}
dependencies {
    implementation(project(":core:model"))
    implementation(project(":core:common"))
    implementation(project(":core:network"))
    implementation(project(":source:api"))
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.quickjs)
    // CatVod JAR 将 Gson 留给宿主提供，与 FongMi 的运行时版本保持一致。
    implementation(libs.gson)
}
