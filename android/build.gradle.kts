allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// Force all plugin modules (e.g. file_picker) to compile against a modern SDK
// so their AAR-metadata check passes. Reflection avoids an AGP type import, and
// the state.executed guard avoids "afterEvaluate on an already-evaluated project".
subprojects {
    val proj = project
    val setSdk = {
        val androidExt = proj.extensions.findByName("android")
        if (androidExt != null) {
            try {
                androidExt.javaClass
                    .getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                    .invoke(androidExt, 36)
            } catch (e: Exception) {
                proj.logger.warn("compileSdk override skipped for ${proj.name}: ${e.message}")
            }
        }
    }
    if (proj.state.executed) setSdk() else proj.afterEvaluate { setSdk() }
}
